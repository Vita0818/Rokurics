//
//  IPhoneAIModels.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import Combine
import Foundation

enum NoteGenerationProviderKind: String, CaseIterable, Codable, Identifiable {
    case openAICompatible
    case anthropicMessages

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAICompatible:
            return "OpenAI-compatible"
        case .anthropicMessages:
            return "Claude / Anthropic"
        }
    }
}

enum AIProviderPreset: String, CaseIterable, Codable, Identifiable {
    case customOpenAICompatible
    case lmStudioLocal
    case ollamaLocal
    case deepSeek
    case openAI
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .customOpenAICompatible:
            return "Custom"
        case .lmStudioLocal:
            return "LM Studio"
        case .ollamaLocal:
            return "Ollama"
        case .deepSeek:
            return "DeepSeek"
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }

    var defaultBaseURLString: String {
        switch self {
        case .customOpenAICompatible:
            return "https://"
        case .lmStudioLocal:
            return "http://127.0.0.1:1234/v1"
        case .ollamaLocal:
            return "http://127.0.0.1:11434/v1"
        case .deepSeek:
            return "https://api.deepseek.com"
        case .openAI:
            return "https://api.openai.com/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai"
        }
    }

    var defaultModelCandidates: [String] {
        switch self {
        case .customOpenAICompatible:
            return []
        case .lmStudioLocal:
            return ["google/gemma-4-e4b"]
        case .ollamaLocal:
            return ["llama3.2"]
        case .deepSeek:
            return ["deepseek-chat", "deepseek-reasoner"]
        case .openAI:
            return ["gpt-5.5", "gpt-5.5-mini", "gpt-5.5-nano"]
        case .gemini:
            return ["gemini-3-flash-preview"]
        }
    }

    var isAvailableOnIPhone: Bool {
        switch self {
        case .lmStudioLocal, .ollamaLocal:
            return false
        case .customOpenAICompatible, .deepSeek, .openAI, .gemini:
            return true
        }
    }

    var requiresAPIKeyOnIPhone: Bool {
        switch self {
        case .deepSeek, .openAI, .gemini:
            return true
        case .customOpenAICompatible, .lmStudioLocal, .ollamaLocal:
            return false
        }
    }

    static var iPhoneVisibleCases: [AIProviderPreset] {
        allCases.filter(\.isAvailableOnIPhone)
    }

    func applyingDefaults(to configuration: OpenAICompatibleNoteGenerationConfiguration) -> OpenAICompatibleNoteGenerationConfiguration {
        if self == .customOpenAICompatible {
            return OpenAICompatibleNoteGenerationConfiguration(
                baseURLString: configuration.trimmedBaseURLString.isEmpty ? defaultBaseURLString : configuration.trimmedBaseURLString,
                modelName: configuration.trimmedModelName,
                apiKey: configuration.trimmedAPIKey,
                temperature: configuration.temperature,
                maxTokens: configuration.maxTokens,
                maxTranscriptCharacters: configuration.maxTranscriptCharacters
            )
        }

        return OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: defaultBaseURLString,
            modelName: defaultModelCandidates.first ?? configuration.trimmedModelName,
            apiKey: configuration.trimmedAPIKey,
            temperature: configuration.temperature,
            maxTokens: configuration.maxTokens,
            maxTranscriptCharacters: configuration.maxTranscriptCharacters
        )
    }
}

struct OpenAICompatibleNoteGenerationConfiguration: Codable, Equatable {
    var baseURLString: String
    var modelName: String
    var apiKey: String
    var temperature: Double
    var maxTokens: Int
    var maxTranscriptCharacters: Int

    init(
        baseURLString: String = AIProviderPreset.openAI.defaultBaseURLString,
        modelName: String = AIProviderPreset.openAI.defaultModelCandidates.first ?? "",
        apiKey: String = "",
        temperature: Double = 0.3,
        maxTokens: Int = 2_000,
        maxTranscriptCharacters: Int = 12_000
    ) {
        self.baseURLString = baseURLString
        self.modelName = modelName
        self.apiKey = apiKey
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.maxTranscriptCharacters = maxTranscriptCharacters
    }

    var trimmedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModelName: String {
        modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AnthropicMessagesConfiguration: Codable, Equatable {
    var baseURLString: String
    var modelName: String
    var apiKey: String
    var anthropicVersion: String
    var temperature: Double
    var maxTokens: Int
    var maxTranscriptCharacters: Int

    init(
        baseURLString: String = "https://api.anthropic.com",
        modelName: String = "claude-sonnet-4-6",
        apiKey: String = "",
        anthropicVersion: String = "2023-06-01",
        temperature: Double = 0.3,
        maxTokens: Int = 2_000,
        maxTranscriptCharacters: Int = 12_000
    ) {
        self.baseURLString = baseURLString
        self.modelName = modelName
        self.apiKey = apiKey
        self.anthropicVersion = anthropicVersion
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.maxTranscriptCharacters = maxTranscriptCharacters
    }

    var trimmedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModelName: String {
        modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAnthropicVersion: String {
        anthropicVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class IPhoneAISettingsStore: ObservableObject {
    @Published private(set) var selectedProviderKind: NoteGenerationProviderKind
    @Published private(set) var selectedProviderPreset: AIProviderPreset
    @Published private(set) var openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration
    @Published private(set) var anthropicConfiguration: AnthropicMessagesConfiguration

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        selectedProviderKind = userDefaults.string(forKey: Self.providerKindKey)
            .flatMap(NoteGenerationProviderKind.init(rawValue:)) ?? .openAICompatible
        selectedProviderPreset = userDefaults.string(forKey: Self.providerPresetKey)
            .flatMap(AIProviderPreset.init(rawValue:))
            .map(Self.iPhoneSafePreset) ?? .openAI

        if let data = userDefaults.data(forKey: Self.openAIConfigurationKey),
           let decoded = try? Self.decoder.decode(OpenAICompatibleNoteGenerationConfiguration.self, from: data) {
            openAIConfiguration = decoded
        } else {
            openAIConfiguration = AIProviderPreset.openAI.applyingDefaults(to: OpenAICompatibleNoteGenerationConfiguration())
        }

        if let data = userDefaults.data(forKey: Self.anthropicConfigurationKey),
           let decoded = try? Self.decoder.decode(AnthropicMessagesConfiguration.self, from: data) {
            anthropicConfiguration = decoded
        } else {
            anthropicConfiguration = AnthropicMessagesConfiguration()
        }
    }

    func updateOpenAI(preset: AIProviderPreset, configuration: OpenAICompatibleNoteGenerationConfiguration) {
        selectedProviderKind = .openAICompatible
        selectedProviderPreset = Self.iPhoneSafePreset(preset)
        openAIConfiguration = selectedProviderPreset.applyingDefaults(to: configuration)
        save()
    }

    func updateAnthropic(configuration: AnthropicMessagesConfiguration) {
        selectedProviderKind = .anthropicMessages
        anthropicConfiguration = configuration
        save()
    }

    func provider() -> any IPhoneChatProvider {
        switch selectedProviderKind {
        case .openAICompatible:
            return OpenAICompatibleIPhoneChatProvider(
                preset: selectedProviderPreset,
                configuration: openAIConfiguration
            )
        case .anthropicMessages:
            return AnthropicIPhoneChatProvider(configuration: anthropicConfiguration)
        }
    }

    private func save() {
        userDefaults.set(selectedProviderKind.rawValue, forKey: Self.providerKindKey)
        userDefaults.set(selectedProviderPreset.rawValue, forKey: Self.providerPresetKey)
        userDefaults.set(try? Self.encoder.encode(openAIConfiguration), forKey: Self.openAIConfigurationKey)
        userDefaults.set(try? Self.encoder.encode(anthropicConfiguration), forKey: Self.anthropicConfigurationKey)
    }

    private static func iPhoneSafePreset(_ preset: AIProviderPreset) -> AIProviderPreset {
        preset.isAvailableOnIPhone ? preset : .openAI
    }

    private static let providerKindKey = "iPhoneAI.providerKind"
    private static let providerPresetKey = "iPhoneAI.providerPreset"
    private static let openAIConfigurationKey = "iPhoneAI.openAIConfiguration"
    private static let anthropicConfigurationKey = "iPhoneAI.anthropicConfiguration"

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}

typealias IPhoneChatRole = ChatMessageRole
typealias IPhoneChatMessage = ChatMessage

typealias IPhoneChatContext = ChatContext

struct IPhoneChatRequest: Equatable {
    var messages: [IPhoneChatMessage]
    var context: IPhoneChatContext?
}

protocol IPhoneChatProvider {
    var displayName: String { get }
    func send(request: IPhoneChatRequest) async throws -> IPhoneChatMessage
}

enum IPhoneAIError: LocalizedError {
    case providerNotConfigured(String)
    case invalidEndpoint
    case requestFailed(Int)
    case emptyResponse
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let name):
            return "\(name) 未配置"
        case .invalidEndpoint:
            return "Endpoint 无效"
        case .requestFailed(let statusCode):
            return "AI 请求失败：HTTP \(statusCode)"
        case .emptyResponse:
            return "AI 没有返回内容"
        case .networkUnavailable:
            return "网络不可用"
        }
    }
}

struct OpenAICompatibleIPhoneChatProvider: IPhoneChatProvider {
    let preset: AIProviderPreset
    let configuration: OpenAICompatibleNoteGenerationConfiguration
    let displayName = "OpenAI-compatible"

    func send(request: IPhoneChatRequest) async throws -> IPhoneChatMessage {
        guard !configuration.trimmedBaseURLString.isEmpty,
              !configuration.trimmedModelName.isEmpty else {
            throw IPhoneAIError.providerNotConfigured(preset.displayName)
        }
        if preset.requiresAPIKeyOnIPhone, configuration.trimmedAPIKey.isEmpty {
            throw IPhoneAIError.providerNotConfigured(preset.displayName)
        }

        let messages = [OpenAIChatMessage(role: "system", content: Self.systemPrompt(context: request.context))]
            + request.messages.map { OpenAIChatMessage(role: $0.role.rawValue, content: $0.content) }
        let body = OpenAIChatRequest(
            model: configuration.trimmedModelName,
            messages: messages,
            temperature: configuration.temperature,
            maxTokens: configuration.maxTokens,
            stream: false
        )
        let data = try JSONEncoder().encode(body)
        let responseData = try await Self.sendJSON(
            baseURLString: configuration.trimmedBaseURLString,
            path: "chat/completions",
            apiKey: configuration.trimmedAPIKey,
            body: data
        )
        let response = try JSONDecoder().decode(OpenAIChatResponse.self, from: responseData)
        let content = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else {
            throw IPhoneAIError.emptyResponse
        }
        return IPhoneChatMessage(role: .assistant, content: content)
    }

    private static func sendJSON(baseURLString: String, path: String, apiKey: String, body: Data) async throws -> Data {
        let normalizedBase = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(normalizedBase)/\(path)") else {
            throw IPhoneAIError.invalidEndpoint
        }
        guard !Self.isLoopbackHost(url) else {
            throw IPhoneAIError.providerNotConfigured("iPhone 不支持本地桌面 AI 服务")
        }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw IPhoneAIError.networkUnavailable
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw IPhoneAIError.requestFailed(httpResponse.statusCode)
            }
            return data
        } catch let error as IPhoneAIError {
            throw error
        } catch {
            throw IPhoneAIError.networkUnavailable
        }
    }

    private static func isLoopbackHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static func systemPrompt(context: IPhoneChatContext?) -> String {
        var prompt = "你是 Rokurics 的学习助手。回答必须基于用户显式导入的学习库上下文；上下文不足时请直接说明。"
        if let context, !context.formattedContext.isEmpty {
            prompt += "\n\n已导入上下文：\(context.pathDisplay) · \(context.itemCount) 项\n\n\(context.formattedContext)"
        }
        return prompt
    }
}

struct AnthropicIPhoneChatProvider: IPhoneChatProvider {
    let configuration: AnthropicMessagesConfiguration
    let displayName = "Claude / Anthropic"

    func send(request: IPhoneChatRequest) async throws -> IPhoneChatMessage {
        guard !configuration.trimmedBaseURLString.isEmpty,
              !configuration.trimmedModelName.isEmpty,
              !configuration.trimmedAPIKey.isEmpty else {
            throw IPhoneAIError.providerNotConfigured(displayName)
        }

        let body = AnthropicChatRequest(
            model: configuration.trimmedModelName,
            maxTokens: configuration.maxTokens,
            temperature: configuration.temperature,
            system: OpenAICompatibleIPhoneChatProvider.systemPrompt(context: request.context),
            messages: [
                AnthropicChatMessage(
                    role: "user",
                    content: request.messages.map { "\($0.role.rawValue)：\n\($0.content)" }.joined(separator: "\n\n")
                )
            ]
        )
        let data = try JSONEncoder().encode(body)
        let responseData = try await sendJSON(body: data)
        let response = try JSONDecoder().decode(AnthropicChatResponse.self, from: responseData)
        let content = response.content.compactMap(\.text).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw IPhoneAIError.emptyResponse
        }
        return IPhoneChatMessage(role: .assistant, content: content)
    }

    private func sendJSON(body: Data) async throws -> Data {
        let normalizedBase = configuration.trimmedBaseURLString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(normalizedBase)/v1/messages") else {
            throw IPhoneAIError.invalidEndpoint
        }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.trimmedAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue(configuration.trimmedAnthropicVersion, forHTTPHeaderField: "anthropic-version")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw IPhoneAIError.networkUnavailable
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw IPhoneAIError.requestFailed(httpResponse.statusCode)
            }
            return data
        } catch let error as IPhoneAIError {
            throw error
        } catch {
            throw IPhoneAIError.networkUnavailable
        }
    }
}

private struct OpenAIChatRequest: Codable {
    var model: String
    var messages: [OpenAIChatMessage]
    var temperature: Double
    var maxTokens: Int
    var stream: Bool
}

private struct OpenAIChatMessage: Codable {
    var role: String
    var content: String
}

private struct OpenAIChatResponse: Codable {
    var choices: [Choice]

    struct Choice: Codable {
        var message: Message
    }

    struct Message: Codable {
        var content: String
    }
}

private struct AnthropicChatRequest: Codable {
    var model: String
    var maxTokens: Int
    var temperature: Double
    var system: String
    var messages: [AnthropicChatMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case system
        case messages
    }
}

private struct AnthropicChatMessage: Codable {
    var role: String
    var content: String
}

private struct AnthropicChatResponse: Codable {
    var content: [ContentBlock]

    struct ContentBlock: Codable {
        var type: String
        var text: String?
    }
}
