//
//  NoteGenerationSettingsStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Combine
import Foundation

struct NoteGenerationDiagnosticResult: Equatable {
    let isSuccess: Bool
    let message: String
}

struct NoteGenerationModelRefreshResult: Equatable {
    let isSuccess: Bool
    let message: String
    let modelIDs: [String]
}

@MainActor
final class NoteGenerationSettingsStore: ObservableObject {
    static let shared = NoteGenerationSettingsStore()

    @Published private(set) var selectedProviderKind: NoteGenerationProviderKind
    @Published private(set) var selectedProviderPreset: AIProviderPreset
    @Published private(set) var openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration
    @Published private(set) var cachedModelCandidates: [String]
    @Published private(set) var anthropicConfiguration: AnthropicMessagesConfiguration
    @Published private(set) var cachedAnthropicModelCandidates: [String]

    private let userDefaults: UserDefaults
    private let openAIClient: OpenAICompatibleNoteGenerationClient
    private let anthropicClient: AnthropicMessagesNoteGenerationClient

    init(
        userDefaults: UserDefaults = .standard,
        client: OpenAICompatibleNoteGenerationClient? = nil,
        anthropicClient: AnthropicMessagesNoteGenerationClient? = nil
    ) {
        self.userDefaults = userDefaults
        self.openAIClient = client ?? OpenAICompatibleNoteGenerationClient()
        self.anthropicClient = anthropicClient ?? AnthropicMessagesNoteGenerationClient()

        let storedProvider = userDefaults.string(forKey: Self.providerKindKey)
            .flatMap(NoteGenerationProviderKind.init(rawValue:)) ?? .mock
        selectedProviderKind = storedProvider

        let loadedConfiguration: OpenAICompatibleNoteGenerationConfiguration
        if let data = userDefaults.data(forKey: Self.openAIConfigurationKey),
           let decoded = try? Self.jsonDecoder.decode(OpenAICompatibleNoteGenerationConfiguration.self, from: data) {
            loadedConfiguration = decoded
        } else {
            loadedConfiguration = OpenAICompatibleNoteGenerationConfiguration()
        }
        openAIConfiguration = loadedConfiguration

        let loadedPreset = userDefaults.string(forKey: Self.providerPresetKey)
            .flatMap(AIProviderPreset.init(rawValue:))
            ?? AIProviderPreset.inferred(from: loadedConfiguration.baseURLString)
        selectedProviderPreset = loadedPreset

        if let data = userDefaults.data(forKey: Self.cachedModelCandidatesKey),
           let decoded = try? Self.jsonDecoder.decode([String].self, from: data) {
            cachedModelCandidates = Self.sanitizedModelCandidates(
                decoded,
                currentModelName: loadedConfiguration.trimmedModelName
            )
        } else {
            cachedModelCandidates = Self.sanitizedModelCandidates(
                loadedPreset.defaultModelCandidates,
                currentModelName: loadedConfiguration.trimmedModelName
            )
        }

        let loadedAnthropicConfiguration: AnthropicMessagesConfiguration
        if let data = userDefaults.data(forKey: Self.anthropicConfigurationKey),
           let decoded = try? Self.jsonDecoder.decode(AnthropicMessagesConfiguration.self, from: data) {
            loadedAnthropicConfiguration = decoded
        } else {
            loadedAnthropicConfiguration = AnthropicMessagesConfiguration()
        }
        anthropicConfiguration = loadedAnthropicConfiguration

        if let data = userDefaults.data(forKey: Self.cachedAnthropicModelCandidatesKey),
           let decoded = try? Self.jsonDecoder.decode([String].self, from: data) {
            cachedAnthropicModelCandidates = Self.sanitizedModelCandidates(
                decoded,
                currentModelName: loadedAnthropicConfiguration.trimmedModelName
            )
        } else {
            cachedAnthropicModelCandidates = Self.sanitizedModelCandidates(
                AnthropicMessagesConfiguration.defaultModelCandidates,
                currentModelName: loadedAnthropicConfiguration.trimmedModelName
            )
        }
    }

    var selectedProviderDisplayName: String {
        selectedProviderKind.displayName
    }

    var currentProviderID: String {
        switch selectedProviderKind {
        case .mock:
            return "mockNoteGenerationProvider"
        case .openAICompatible:
            return "openAICompatible"
        case .anthropicMessages:
            return "anthropicMessages"
        }
    }

    var endpointDisplay: String {
        switch selectedProviderKind {
        case .mock:
            return "local mock"
        case .openAICompatible:
            return openAIConfiguration.trimmedBaseURLString
        case .anthropicMessages:
            return anthropicConfiguration.trimmedBaseURLString
        }
    }

    func update(
        providerKind: NoteGenerationProviderKind,
        providerPreset: AIProviderPreset? = nil,
        openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration,
        anthropicConfiguration: AnthropicMessagesConfiguration? = nil
    ) {
        update(
            providerKind: providerKind,
            providerPreset: providerPreset,
            openAIConfiguration: openAIConfiguration,
            cachedModelCandidates: nil,
            anthropicConfiguration: anthropicConfiguration,
            cachedAnthropicModelCandidates: nil
        )
    }

    func update(
        providerKind: NoteGenerationProviderKind,
        providerPreset: AIProviderPreset? = nil,
        openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration,
        cachedModelCandidates: [String]?,
        anthropicConfiguration: AnthropicMessagesConfiguration? = nil,
        cachedAnthropicModelCandidates: [String]? = nil
    ) {
        selectedProviderKind = providerKind
        if let providerPreset {
            selectedProviderPreset = providerPreset
        }
        self.openAIConfiguration = sanitized(configuration: openAIConfiguration)
        if let cachedModelCandidates {
            self.cachedModelCandidates = Self.sanitizedModelCandidates(
                cachedModelCandidates,
                currentModelName: self.openAIConfiguration.trimmedModelName
            )
        } else {
            self.cachedModelCandidates = Self.sanitizedModelCandidates(
                self.cachedModelCandidates,
                currentModelName: self.openAIConfiguration.trimmedModelName
            )
        }
        if let anthropicConfiguration {
            self.anthropicConfiguration = sanitized(configuration: anthropicConfiguration)
        }
        if let cachedAnthropicModelCandidates {
            self.cachedAnthropicModelCandidates = Self.sanitizedModelCandidates(
                cachedAnthropicModelCandidates,
                currentModelName: self.anthropicConfiguration.trimmedModelName
            )
        } else {
            self.cachedAnthropicModelCandidates = Self.sanitizedModelCandidates(
                self.cachedAnthropicModelCandidates,
                currentModelName: self.anthropicConfiguration.trimmedModelName
            )
        }
        save()
    }

    func refreshModels(configuration: OpenAICompatibleNoteGenerationConfiguration) async -> NoteGenerationModelRefreshResult {
        do {
            let models = try await openAIClient.models(
                configuration: sanitized(configuration: configuration),
                timeout: 10
            )
            let modelIDs = Self.sanitizedModelCandidates(models.map(\.id), currentModelName: nil)
            guard !modelIDs.isEmpty else {
                return NoteGenerationModelRefreshResult(
                    isSuccess: false,
                    message: RokuricsCopy.text("未读取到模型", "No models found"),
                    modelIDs: []
                )
            }

            return NoteGenerationModelRefreshResult(
                isSuccess: true,
                message: RokuricsCopy.text(
                    "刷新成功：\(modelIDs.count) 个模型",
                    "Refreshed \(modelIDs.count) models"
                ),
                modelIDs: modelIDs
            )
        } catch {
            return NoteGenerationModelRefreshResult(
                isSuccess: false,
                message: error.localizedDescription,
                modelIDs: []
            )
        }
    }

    func refreshAnthropicModels(configuration: AnthropicMessagesConfiguration) async -> NoteGenerationModelRefreshResult {
        do {
            let models = try await anthropicClient.models(
                configuration: sanitized(configuration: configuration),
                timeout: 10
            )
            let modelIDs = Self.sanitizedModelCandidates(models.map(\.id), currentModelName: nil)
            guard !modelIDs.isEmpty else {
                return NoteGenerationModelRefreshResult(
                    isSuccess: false,
                    message: RokuricsCopy.text("未读取到 Claude 模型", "No Claude models found"),
                    modelIDs: []
                )
            }

            return NoteGenerationModelRefreshResult(
                isSuccess: true,
                message: RokuricsCopy.text(
                    "刷新成功：\(modelIDs.count) 个 Claude 模型",
                    "Refreshed \(modelIDs.count) Claude models"
                ),
                modelIDs: modelIDs
            )
        } catch {
            return NoteGenerationModelRefreshResult(
                isSuccess: false,
                message: error.localizedDescription,
                modelIDs: []
            )
        }
    }

    func testConnection(configuration: OpenAICompatibleNoteGenerationConfiguration) async -> NoteGenerationDiagnosticResult {
        do {
            let models = try await openAIClient.models(
                configuration: sanitized(configuration: configuration),
                timeout: 10
            )
            let firstModel = models.first?.id ?? "unknown"
            return NoteGenerationDiagnosticResult(
                isSuccess: true,
                message: RokuricsCopy.text(
                    "连接成功：\(models.count) 个模型，首个 \(firstModel)",
                    "Connected: \(models.count) models, first \(firstModel)"
                )
            )
        } catch {
            return NoteGenerationDiagnosticResult(isSuccess: false, message: error.localizedDescription)
        }
    }

    func testAnthropicConnection(configuration: AnthropicMessagesConfiguration) async -> NoteGenerationDiagnosticResult {
        do {
            let models = try await anthropicClient.models(
                configuration: sanitized(configuration: configuration),
                timeout: 10
            )
            let firstModel = models.first?.id ?? "unknown"
            return NoteGenerationDiagnosticResult(
                isSuccess: true,
                message: RokuricsCopy.text(
                    "连接成功：\(models.count) 个 Claude 模型，首个 \(firstModel)",
                    "Connected: \(models.count) Claude models, first \(firstModel)"
                )
            )
        } catch {
            return NoteGenerationDiagnosticResult(isSuccess: false, message: error.localizedDescription)
        }
    }

    func testModel(configuration: OpenAICompatibleNoteGenerationConfiguration) async -> NoteGenerationDiagnosticResult {
        do {
            let result = try await openAIClient.chatCompletion(
                configuration: sanitized(configuration: configuration),
                messages: [
                    OpenAICompatibleMessage(
                        role: "system",
                        content: RokuricsCopy.text(
                            "你是一个本地连接测试助手。只输出最终答案，不要输出思考过程、草稿、推理步骤或解释。",
                            "You are a local connection test assistant. Output only the final answer."
                        )
                    ),
                    OpenAICompatibleMessage(
                        role: "user",
                        content: RokuricsCopy.text(
                            """
                        请只输出下面这一行，不要添加任何其他内容：
                        Rokurics AI OK
                        """,
                            """
                        Output exactly this line and nothing else:
                        Rokurics AI OK
                        """
                        )
                    )
                ],
                timeout: 30,
                maxTokens: Self.testModelMaxTokens,
                temperature: 0.1
            )
            let truncationHint = result.isLengthLimited
                ? RokuricsCopy.text("，可能被长度截断", ", may be truncated")
                : ""
            return NoteGenerationDiagnosticResult(
                isSuccess: true,
                message: RokuricsCopy.text(
                    "模型测试成功\(truncationHint)：\(Self.preview(result.content, maxCharacters: 80))",
                    "Model OK\(truncationHint): \(Self.preview(result.content, maxCharacters: 80))"
                )
            )
        } catch {
            return NoteGenerationDiagnosticResult(isSuccess: false, message: error.localizedDescription)
        }
    }

    func testAnthropicModel(configuration: AnthropicMessagesConfiguration) async -> NoteGenerationDiagnosticResult {
        do {
            let result = try await anthropicClient.message(
                configuration: sanitized(configuration: configuration),
                system: RokuricsCopy.text(
                    "你是一个本地连接测试助手。只输出最终答案，不要输出思考过程、草稿、推理步骤或解释。",
                    "You are a local connection test assistant. Output only the final answer."
                ),
                userContent: RokuricsCopy.text(
                    """
                请只输出下面这一行，不要添加任何其他内容：
                Rokurics Claude OK
                """,
                    """
                Output exactly this line and nothing else:
                Rokurics Claude OK
                """
                ),
                timeout: 30,
                maxTokens: Self.testAnthropicModelMaxTokens,
                temperature: 0.1
            )
            let truncationHint = result.isLengthLimited
                ? RokuricsCopy.text("，可能被长度截断", ", may be truncated")
                : ""
            return NoteGenerationDiagnosticResult(
                isSuccess: true,
                message: RokuricsCopy.text(
                    "模型测试成功\(truncationHint)：\(Self.preview(result.content, maxCharacters: 80))",
                    "Model OK\(truncationHint): \(Self.preview(result.content, maxCharacters: 80))"
                )
            )
        } catch {
            return NoteGenerationDiagnosticResult(isSuccess: false, message: error.localizedDescription)
        }
    }

    func testGeneration(configuration: OpenAICompatibleNoteGenerationConfiguration) async -> NoteGenerationDiagnosticResult {
        do {
            let result = try await openAIClient.chatCompletion(
                configuration: sanitized(configuration: configuration),
                messages: [
                    OpenAICompatibleMessage(
                        role: "system",
                        content: RokuricsCopy.text(
                            "你是 Rokurics 的中文课堂笔记整理助手。只输出最终 Markdown，不要输出思考过程、草稿、推理步骤、分析过程或 JSON。",
                            "You are Rokurics' class note assistant. Output only final Markdown."
                        )
                    ),
                    OpenAICompatibleMessage(
                        role: "user",
                        content: RokuricsCopy.text(
                            """
                        请根据以下转写生成简短中文 Markdown 笔记：

                        高斯公式、格林公式、斯托克斯公式都和向量场积分有关。
                        """,
                            """
                        Generate brief English Markdown notes from this transcript:

                        Gauss, Green, and Stokes formulas are all related to vector field integrals.
                        """
                        )
                    )
                ],
                timeout: 60,
                maxTokens: 1_200
            )
            let truncationHint = result.isLengthLimited
                ? RokuricsCopy.text("，可能被长度截断", ", may be truncated")
                : ""
            return NoteGenerationDiagnosticResult(
                isSuccess: true,
                message: RokuricsCopy.text(
                    "生成成功\(truncationHint)：\(Self.preview(result.content, maxCharacters: 120))",
                    "Generated\(truncationHint): \(Self.preview(result.content, maxCharacters: 120))"
                )
            )
        } catch {
            return NoteGenerationDiagnosticResult(isSuccess: false, message: error.localizedDescription)
        }
    }

    func testAnthropicGeneration(configuration: AnthropicMessagesConfiguration) async -> NoteGenerationDiagnosticResult {
        do {
            let result = try await anthropicClient.message(
                configuration: sanitized(configuration: configuration),
                system: RokuricsCopy.text(
                    "你是 Rokurics 的中文课堂笔记整理助手。只输出最终 Markdown，不要输出思考过程、草稿、推理步骤、分析过程或 JSON。",
                    "You are Rokurics' class note assistant. Output only final Markdown."
                ),
                userContent: RokuricsCopy.text(
                    """
                请根据以下转写生成简短中文 Markdown 笔记：

                高斯公式、格林公式、斯托克斯公式都和向量场积分有关。
                """,
                    """
                Generate brief English Markdown notes from this transcript:

                Gauss, Green, and Stokes formulas are all related to vector field integrals.
                """
                ),
                timeout: 60,
                maxTokens: 1_200
            )
            let truncationHint = result.isLengthLimited
                ? RokuricsCopy.text("，可能被长度截断", ", may be truncated")
                : ""
            return NoteGenerationDiagnosticResult(
                isSuccess: true,
                message: RokuricsCopy.text(
                    "生成成功\(truncationHint)：\(Self.preview(result.content, maxCharacters: 120))",
                    "Generated\(truncationHint): \(Self.preview(result.content, maxCharacters: 120))"
                )
            )
        } catch {
            return NoteGenerationDiagnosticResult(isSuccess: false, message: error.localizedDescription)
        }
    }

    private func save() {
        userDefaults.set(selectedProviderKind.rawValue, forKey: Self.providerKindKey)
        userDefaults.set(selectedProviderPreset.rawValue, forKey: Self.providerPresetKey)
        if let data = try? Self.jsonEncoder.encode(openAIConfiguration) {
            userDefaults.set(data, forKey: Self.openAIConfigurationKey)
        }
        if let data = try? Self.jsonEncoder.encode(cachedModelCandidates) {
            userDefaults.set(data, forKey: Self.cachedModelCandidatesKey)
        }
        if let data = try? Self.jsonEncoder.encode(anthropicConfiguration) {
            userDefaults.set(data, forKey: Self.anthropicConfigurationKey)
        }
        if let data = try? Self.jsonEncoder.encode(cachedAnthropicModelCandidates) {
            userDefaults.set(data, forKey: Self.cachedAnthropicModelCandidatesKey)
        }
    }

    private func sanitized(configuration: OpenAICompatibleNoteGenerationConfiguration) -> OpenAICompatibleNoteGenerationConfiguration {
        OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: configuration.trimmedBaseURLString,
            modelName: configuration.trimmedModelName,
            apiKey: configuration.trimmedAPIKey,
            temperature: configuration.temperature,
            maxTokens: max(1, configuration.maxTokens),
            maxTranscriptCharacters: max(1, configuration.maxTranscriptCharacters)
        )
    }

    private func sanitized(configuration: AnthropicMessagesConfiguration) -> AnthropicMessagesConfiguration {
        AnthropicMessagesConfiguration(
            baseURLString: configuration.trimmedBaseURLString,
            modelName: configuration.trimmedModelName,
            apiKey: configuration.trimmedAPIKey,
            anthropicVersion: configuration.trimmedAnthropicVersion,
            temperature: configuration.temperature,
            maxTokens: max(1, configuration.maxTokens),
            maxTranscriptCharacters: max(1, configuration.maxTranscriptCharacters)
        )
    }

    private static func preview(_ text: String, maxCharacters: Int) -> String {
        let normalized = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard normalized.count > maxCharacters else {
            return normalized
        }

        return String(normalized.prefix(maxCharacters)) + "..."
    }

    private static func sanitizedModelCandidates(
        _ candidates: [String],
        currentModelName: String?
    ) -> [String] {
        var seen: Set<String> = []
        let values = candidates + [currentModelName].compactMap { $0 }
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { candidate in
                if seen.contains(candidate) {
                    return false
                }
                seen.insert(candidate)
                return true
            }
    }

    private static let providerKindKey = "noteGeneration.providerKind"
    private static let providerPresetKey = "noteGeneration.providerPreset"
    private static let openAIConfigurationKey = "noteGeneration.openAICompatible.configuration"
    private static let cachedModelCandidatesKey = "noteGeneration.openAICompatible.cachedModelCandidates"
    private static let anthropicConfigurationKey = "noteGeneration.anthropicMessages.configuration"
    private static let cachedAnthropicModelCandidatesKey = "noteGeneration.anthropicMessages.cachedModelCandidates"

    static let testModelMaxTokens = 512
    static let testAnthropicModelMaxTokens = 256

    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()
}
