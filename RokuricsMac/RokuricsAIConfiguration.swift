import Combine
import Foundation

// This is the Rokurics-owned counterpart of Intatis's provider catalog and
// JSON/JSONC configuration flow. The applications never read each other's
// files; they only share the same user-facing configuration shape.

enum RokuricsJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: RokuricsJSONValue])
    case array([RokuricsJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: RokuricsJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([RokuricsJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .object(let value):
            return value.mapValues(\.foundationValue)
        case .array(let value):
            return value.map(\.foundationValue)
        case .null:
            return NSNull()
        }
    }
}

enum RokuricsAIRequestAdapter: String, Codable, Equatable, Sendable {
    case openAICompatible = "@ai-sdk/openai-compatible"
    case openRouter = "@openrouter/ai-sdk-provider"
    case openAI = "@ai-sdk/openai"
    case legacyOpenAIWire = "intatis:legacy-openai-wire"

    static func configured(_ value: String?) -> RokuricsAIRequestAdapter? {
        guard let value else { return .openAICompatible }
        return RokuricsAIRequestAdapter(rawValue: value)
    }
}

enum RokuricsAICredentialReference: Equatable, Sendable {
    case literal(String)
    case environment(String)
    case file(String)
    case missing

    var configurationValue: String? {
        switch self {
        case .literal(let value): return value
        case .environment(let name): return "{env:\(name)}"
        case .file(let path): return "{file:\(path)}"
        case .missing: return nil
        }
    }

    var displayDescription: String {
        switch self {
        case .literal: return RokuricsCopy.text("已在配置文件中设置", "Configured in file")
        case .environment(let name): return "env · \(name)"
        case .file: return RokuricsCopy.text("外部文件", "External file")
        case .missing: return RokuricsCopy.text("未设置", "Not configured")
        }
    }
}

struct RokuricsAIModelReference: Codable, Equatable, Sendable {
    var providerID: String
    var modelID: String

    var configurationValue: String {
        "\(providerID)/\(modelID)"
    }
}

struct RokuricsAIModel: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var displayName: String
    var requestOptions: [String: RokuricsJSONValue]
    var configurationMetadata: [String: RokuricsJSONValue]

    init(
        id: String,
        displayName: String,
        requestOptions: [String: RokuricsJSONValue] = [:],
        configurationMetadata: [String: RokuricsJSONValue] = [:]
    ) {
        self.id = id
        self.displayName = displayName
        self.requestOptions = requestOptions
        self.configurationMetadata = configurationMetadata
    }

    var title: String {
        let value = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? id : value
    }
}

struct RokuricsAIProvider: Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var adapterRawValue: String
    var baseURL: String
    var chatEndpoint: String
    var credential: RokuricsAICredentialReference
    var models: [RokuricsAIModel]

    init(
        id: String,
        displayName: String,
        adapterRawValue: String = RokuricsAIRequestAdapter.openAICompatible.rawValue,
        baseURL: String,
        chatEndpoint: String? = nil,
        credential: RokuricsAICredentialReference = .missing,
        models: [RokuricsAIModel]
    ) {
        self.id = id
        self.displayName = displayName
        self.adapterRawValue = adapterRawValue
        self.baseURL = baseURL
        self.chatEndpoint = chatEndpoint ?? Self.defaultChatEndpoint(baseURL: baseURL)
        self.credential = credential
        self.models = models
    }

    var title: String {
        let value = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? (URL(string: baseURL)?.host ?? id) : value
    }

    var adapter: RokuricsAIRequestAdapter? {
        RokuricsAIRequestAdapter.configured(adapterRawValue)
    }

    static func defaultChatEndpoint(baseURL: String) -> String {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(base)/chat/completions"
    }
}

struct RokuricsAICatalog: Equatable, Sendable {
    var selectedProviderID: String
    var selectedModelID: String
    var transcriptionModel: RokuricsAIModelReference?
    var providers: [RokuricsAIProvider]

    var selectedProvider: RokuricsAIProvider? {
        providers.first { $0.id == selectedProviderID }
            ?? providers.first { !$0.models.isEmpty }
            ?? providers.first
    }

    var selectedModel: RokuricsAIModel? {
        guard let provider = selectedProvider else { return nil }
        return provider.models.first { $0.id == selectedModelID }
            ?? provider.models.first
    }

    var summaryModelReference: RokuricsAIModelReference? {
        guard let provider = selectedProvider, let model = selectedModel else {
            return nil
        }
        return RokuricsAIModelReference(providerID: provider.id, modelID: model.id)
    }
}

struct RokuricsAIResolvedRoute: Sendable {
    let providerID: String
    let providerDisplayName: String
    let adapter: RokuricsAIRequestAdapter
    let baseURL: URL
    let chatEndpoint: URL
    let modelID: String
    let requestOptions: [String: RokuricsJSONValue]
    let apiKey: String
}

enum RokuricsAIConfigurationError: LocalizedError, Equatable {
    case configurationUnreadable
    case configurationInvalid
    case providerMissing(String)
    case modelMissing(String)
    case summaryModelNotConfigured
    case transcriptionModelNotConfigured
    case unsupportedAdapter(String)
    case invalidEndpoint
    case credentialMissing(String)
    case credentialFileUnreadable
    case unsafeRequestOptions

    var errorDescription: String? {
        switch self {
        case .configurationUnreadable:
            return RokuricsCopy.text("无法读取 AI 配置文件", "Could not read the AI configuration file")
        case .configurationInvalid:
            return RokuricsCopy.text("AI 配置文件格式无效", "The AI configuration file is invalid")
        case .providerMissing(let id):
            return RokuricsCopy.text("AI 服务不存在：\(id)", "AI provider is missing: \(id)")
        case .modelMissing(let id):
            return RokuricsCopy.text("AI 模型不存在：\(id)", "AI model is missing: \(id)")
        case .summaryModelNotConfigured:
            return RokuricsCopy.text("请先在配置中设置 model", "Configure model before generating a summary")
        case .transcriptionModelNotConfigured:
            return RokuricsCopy.text("请先在配置中设置 transcription_model", "Configure transcription_model before transcribing")
        case .unsupportedAdapter(let value):
            return RokuricsCopy.text("当前服务类型不受支持：\(value)", "The configured provider type is unsupported: \(value)")
        case .invalidEndpoint:
            return RokuricsCopy.text("AI 服务地址无效", "The AI service URL is invalid")
        case .credentialMissing(let provider):
            return RokuricsCopy.text("\(provider) 缺少 API 密钥", "\(provider) is missing an API key")
        case .credentialFileUnreadable:
            return RokuricsCopy.text("无法读取 API 密钥文件", "Could not read the API key file")
        case .unsafeRequestOptions:
            return RokuricsCopy.text("模型选项中包含不允许保存或发送的敏感字段", "Model options contain disallowed secret material")
        }
    }
}

@MainActor
final class RokuricsAIConfigurationStore: ObservableObject {
    static let shared = RokuricsAIConfigurationStore()

    @Published private(set) var catalog: RokuricsAICatalog
    @Published private(set) var configurationURL: URL
    @Published private(set) var lastErrorMessage: String?

    private let fileManager: FileManager
    private let rootURLOverride: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURLOverride = rootURL?.standardizedFileURL
        self.catalog = Self.defaultCatalog
        self.configurationURL = Self.defaultConfigurationURL(
            fileManager: fileManager,
            rootURL: rootURL
        )
        reload()
    }

    var summaryConfigurationText: String {
        catalog.summaryModelReference?.configurationValue
            ?? RokuricsCopy.text("未配置 model", "model not configured")
    }

    var transcriptionConfigurationText: String {
        catalog.transcriptionModel?.configurationValue
            ?? RokuricsCopy.text("未配置 transcription_model", "transcription_model not configured")
    }

    func reload() {
        do {
            let url = try activeConfigurationURL()
            configurationURL = url
            if fileManager.fileExists(atPath: url.path) {
                catalog = try Self.loadCatalog(from: url)
            } else {
                catalog = Self.defaultCatalog
            }
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func save(
        catalog rawCatalog: RokuricsAICatalog,
        apiKeysByProviderID: [String: String]
    ) throws {
        let catalog = Self.normalized(rawCatalog)
        let url = try activeConfigurationURL()
        try Self.writeConfiguration(
            catalog: catalog,
            apiKeysByProviderID: apiKeysByProviderID,
            to: url,
            fileManager: fileManager
        )
        configurationURL = url
        self.catalog = try Self.loadCatalog(from: url)
        lastErrorMessage = nil
    }

    func prepareEditableConfigurationFile() throws -> URL {
        let url = try activeConfigurationURL()
        if !fileManager.fileExists(atPath: url.path) {
            try Self.writeConfiguration(
                catalog: catalog,
                apiKeysByProviderID: [:],
                to: url,
                fileManager: fileManager
            )
        }
        configurationURL = url
        return url
    }

    func summaryRoute() throws -> RokuricsAIResolvedRoute {
        guard let reference = catalog.summaryModelReference else {
            throw RokuricsAIConfigurationError.summaryModelNotConfigured
        }
        return try resolve(reference)
    }

    func transcriptionRoute() throws -> RokuricsAIResolvedRoute {
        guard let reference = catalog.transcriptionModel else {
            throw RokuricsAIConfigurationError.transcriptionModelNotConfigured
        }
        return try resolve(reference)
    }

    private func resolve(_ reference: RokuricsAIModelReference) throws -> RokuricsAIResolvedRoute {
        guard let provider = catalog.providers.first(where: { $0.id == reference.providerID }) else {
            throw RokuricsAIConfigurationError.providerMissing(reference.providerID)
        }
        guard let model = provider.models.first(where: { $0.id == reference.modelID }) else {
            throw RokuricsAIConfigurationError.modelMissing(reference.modelID)
        }
        guard Self.requestOptionsAreSafe(model.requestOptions) else {
            throw RokuricsAIConfigurationError.unsafeRequestOptions
        }
        guard let adapter = provider.adapter else {
            throw RokuricsAIConfigurationError.unsupportedAdapter(provider.adapterRawValue)
        }
        guard let baseURL = Self.validatedHTTPURL(provider.baseURL),
              let chatEndpoint = Self.validatedHTTPURL(provider.chatEndpoint) else {
            throw RokuricsAIConfigurationError.invalidEndpoint
        }
        let apiKey = try Self.resolveCredential(
            provider.credential,
            providerName: provider.title,
            configurationDirectory: configurationURL.deletingLastPathComponent()
        )
        return RokuricsAIResolvedRoute(
            providerID: provider.id,
            providerDisplayName: provider.title,
            adapter: adapter,
            baseURL: baseURL,
            chatEndpoint: chatEndpoint,
            modelID: model.id,
            requestOptions: model.requestOptions,
            apiKey: apiKey
        )
    }

    private func activeConfigurationURL() throws -> URL {
        if let rootURLOverride {
            return rootURLOverride.appendingPathComponent("rokurics.json", isDirectory: false)
        }
        if let override = ProcessInfo.processInfo.environment["ROKURICS_CONFIG"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: Self.expandedPath(override)).standardizedFileURL
        }
        let supportURL = Self.defaultConfigurationURL(fileManager: fileManager, rootURL: nil)
        let supportJSONC = supportURL.deletingPathExtension().appendingPathExtension("jsonc")
        if fileManager.fileExists(atPath: supportURL.path) { return supportURL }
        if fileManager.fileExists(atPath: supportJSONC.path) { return supportJSONC }
        return supportURL
    }

    private static func defaultConfigurationURL(
        fileManager: FileManager,
        rootURL: URL?
    ) -> URL {
        let root = rootURL?.standardizedFileURL
            ?? MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
        return root.appendingPathComponent("rokurics.json", isDirectory: false)
    }

    private static let defaultCatalog = RokuricsAICatalog(
        selectedProviderID: "openai",
        selectedModelID: "gpt-4o-mini",
        transcriptionModel: nil,
        providers: [
            RokuricsAIProvider(
                id: "openai",
                displayName: "OpenAI",
                baseURL: "https://api.openai.com/v1",
                credential: .environment("OPENAI_API_KEY"),
                models: [
                    RokuricsAIModel(id: "gpt-4o-mini", displayName: "GPT-4o mini")
                ]
            )
        ]
    )
}

private extension RokuricsAIConfigurationStore {
    struct ConfigurationFile: Decodable {
        var model: String?
        var transcriptionModel: String?
        var enabledProviders: [String]?
        var provider: [String: ProviderFile]?

        enum CodingKeys: String, CodingKey {
            case model
            case transcriptionModel = "transcription_model"
            case enabledProviders = "enabled_providers"
            case provider
        }
    }

    struct ProviderFile: Decodable {
        var npm: String?
        var name: String?
        var displayName: String?
        var baseURL: String?
        var chatEndpoint: String?
        var apiKey: String?
        var options: ProviderOptionsFile?
        var models: [String: RokuricsJSONValue]?
    }

    struct ProviderOptionsFile: Decodable {
        var baseURL: String?
        var chatEndpoint: String?
        var apiKey: String?
    }

    static func loadCatalog(from url: URL) throws -> RokuricsAICatalog {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RokuricsAIConfigurationError.configurationUnreadable
        }
        let compatible = jsonCompatibleData(data)
        let decoded: ConfigurationFile
        do {
            decoded = try JSONDecoder().decode(ConfigurationFile.self, from: compatible)
        } catch {
            throw RokuricsAIConfigurationError.configurationInvalid
        }

        let enabled = Set((decoded.enabledProviders ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        var providers = (decoded.provider ?? [:]).compactMap { id, value -> RokuricsAIProvider? in
            let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedID.isEmpty,
                  enabled.isEmpty || enabled.contains(normalizedID.lowercased()) else {
                return nil
            }
            let baseURL = value.options?.baseURL ?? value.baseURL ?? defaultBaseURL(providerID: normalizedID)
            guard let baseURL, !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let modelValues = (value.models ?? [:]).map { modelID, raw -> RokuricsAIModel in
                let metadata: [String: RokuricsJSONValue]
                let name: String
                let options: [String: RokuricsJSONValue]
                switch raw {
                case .string(let value):
                    metadata = ["name": .string(value)]
                    name = value
                    options = [:]
                case .object(let object):
                    metadata = object
                    if case .string(let value)? = object["name"] {
                        name = value
                    } else if case .string(let value)? = object["displayName"] {
                        name = value
                    } else {
                        name = modelID
                    }
                    if case .object(let value)? = object["options"] {
                        options = value
                    } else {
                        options = [:]
                    }
                default:
                    metadata = [:]
                    name = modelID
                    options = [:]
                }
                return RokuricsAIModel(
                    id: modelID,
                    displayName: name,
                    requestOptions: options,
                    configurationMetadata: metadata
                )
            }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
            let rawCredential = value.options?.apiKey ?? value.apiKey
            return RokuricsAIProvider(
                id: normalizedID,
                displayName: value.displayName ?? value.name ?? defaultProviderName(providerID: normalizedID),
                adapterRawValue: value.npm ?? RokuricsAIRequestAdapter.openAICompatible.rawValue,
                baseURL: baseURL,
                chatEndpoint: value.options?.chatEndpoint ?? value.chatEndpoint,
                credential: credentialReference(rawCredential),
                models: modelValues
            )
        }
        .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }

        if providers.isEmpty {
            throw RokuricsAIConfigurationError.configurationInvalid
        }

        let configurationDirectory = url.deletingLastPathComponent()
        let summary = modelReference(
            resolvedConfigValue(decoded.model, configurationDirectory: configurationDirectory),
            providers: providers
        )
        let transcription = modelReference(
            resolvedConfigValue(decoded.transcriptionModel, configurationDirectory: configurationDirectory),
            providers: providers
        )
        if let summary {
            ensureModel(summary, in: &providers)
        }
        if let transcription {
            ensureModel(transcription, in: &providers)
        }

        let selectedProviderID = summary?.providerID
            ?? providers.first(where: { !$0.models.isEmpty })?.id
            ?? providers[0].id
        let selectedModelID = summary?.modelID
            ?? providers.first(where: { $0.id == selectedProviderID })?.models.first?.id
            ?? ""
        return normalized(RokuricsAICatalog(
            selectedProviderID: selectedProviderID,
            selectedModelID: selectedModelID,
            transcriptionModel: transcription,
            providers: providers
        ))
    }

    static func normalized(_ catalog: RokuricsAICatalog) -> RokuricsAICatalog {
        var seenProviders = Set<String>()
        let providers = catalog.providers.compactMap { provider -> RokuricsAIProvider? in
            let id = provider.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, seenProviders.insert(id.lowercased()).inserted else {
                return nil
            }
            let baseURL = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !baseURL.isEmpty else { return nil }
            var seenModels = Set<String>()
            let models = provider.models.compactMap { model -> RokuricsAIModel? in
                let modelID = model.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !modelID.isEmpty, seenModels.insert(modelID).inserted else { return nil }
                return RokuricsAIModel(
                    id: modelID,
                    displayName: model.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    requestOptions: model.requestOptions,
                    configurationMetadata: model.configurationMetadata
                )
            }
            return RokuricsAIProvider(
                id: id,
                displayName: provider.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                adapterRawValue: provider.adapterRawValue,
                baseURL: baseURL,
                chatEndpoint: provider.chatEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                credential: provider.credential,
                models: models
            )
        }
        guard !providers.isEmpty else { return defaultCatalog }

        let selectedProvider = providers.first { $0.id == catalog.selectedProviderID }
            ?? providers.first { !$0.models.isEmpty }
            ?? providers[0]
        let selectedModel = selectedProvider.models.first { $0.id == catalog.selectedModelID }
            ?? selectedProvider.models.first
        let transcription = catalog.transcriptionModel.flatMap { reference in
            providers.first(where: { $0.id == reference.providerID })?
                .models.first(where: { $0.id == reference.modelID }) == nil ? nil : reference
        }
        return RokuricsAICatalog(
            selectedProviderID: selectedProvider.id,
            selectedModelID: selectedModel?.id ?? "",
            transcriptionModel: transcription,
            providers: providers
        )
    }

    static func writeConfiguration(
        catalog: RokuricsAICatalog,
        apiKeysByProviderID: [String: String],
        to url: URL,
        fileManager: FileManager
    ) throws {
        var root: [String: Any]
        if fileManager.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: jsonCompatibleData(data)),
           let existing = object as? [String: Any] {
            root = existing
        } else {
            root = [:]
        }

        root["$schema"] = "https://opencode.ai/config.json"
        root["enabled_providers"] = catalog.providers.map(\.id)
        if let summary = catalog.summaryModelReference {
            root["model"] = summary.configurationValue
        } else {
            root.removeValue(forKey: "model")
        }
        if let transcription = catalog.transcriptionModel {
            root["transcription_model"] = transcription.configurationValue
        } else {
            root.removeValue(forKey: "transcription_model")
        }

        let existingProviderMap = root["provider"] as? [String: Any] ?? [:]
        var providerMap = existingProviderMap
        for provider in catalog.providers {
            var providerObject = existingProviderMap[provider.id] as? [String: Any] ?? [:]
            providerObject["npm"] = provider.adapterRawValue
            providerObject["name"] = provider.title
            var options = providerObject["options"] as? [String: Any] ?? [:]
            options["baseURL"] = provider.baseURL
            let newKey = apiKeysByProviderID[provider.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !newKey.isEmpty {
                options["apiKey"] = newKey
            } else if options["apiKey"] == nil,
                      let configured = provider.credential.configurationValue {
                options["apiKey"] = configured
            }
            providerObject["options"] = options
            providerObject["models"] = Dictionary(uniqueKeysWithValues: provider.models.map { model in
                var metadata = model.configurationMetadata.mapValues(\.foundationValue)
                metadata["name"] = model.title
                if !model.requestOptions.isEmpty {
                    metadata["options"] = model.requestOptions.mapValues(\.foundationValue)
                }
                return (model.id, metadata)
            })
            providerMap[provider.id] = providerObject
        }
        root["provider"] = providerMap

        guard JSONSerialization.isValidJSONObject(root) else {
            throw RokuricsAIConfigurationError.configurationInvalid
        }
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }

    static func resolveCredential(
        _ reference: RokuricsAICredentialReference,
        providerName: String,
        configurationDirectory: URL
    ) throws -> String {
        let value: String
        switch reference {
        case .literal(let secret):
            value = secret
        case .environment(let name):
            value = ProcessInfo.processInfo.environment[name] ?? ""
        case .file(let path):
            let expanded = expandedPath(path)
            let url = expanded.hasPrefix("/")
                ? URL(fileURLWithPath: expanded)
                : configurationDirectory.appendingPathComponent(expanded)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw RokuricsAIConfigurationError.credentialFileUnreadable
            }
            value = text
        case .missing:
            value = ""
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RokuricsAIConfigurationError.credentialMissing(providerName)
        }
        return trimmed
    }

    static func credentialReference(_ raw: String?) -> RokuricsAICredentialReference {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return .missing }
        if let variable = configVariable(raw) {
            switch variable.kind {
            case "env": return .environment(variable.value)
            case "file": return .file(variable.value)
            default: return .missing
            }
        }
        return .literal(raw)
    }

    static func resolvedConfigValue(
        _ raw: String?,
        configurationDirectory: URL
    ) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        guard let variable = configVariable(raw) else { return raw }
        switch variable.kind {
        case "env":
            return ProcessInfo.processInfo.environment[variable.value]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case "file":
            let expanded = expandedPath(variable.value)
            let url = expanded.hasPrefix("/")
                ? URL(fileURLWithPath: expanded)
                : configurationDirectory.appendingPathComponent(expanded)
            return try? String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        default:
            return nil
        }
    }

    static func configVariable(_ raw: String) -> (kind: String, value: String)? {
        guard raw.hasPrefix("{"), raw.hasSuffix("}") else { return nil }
        let body = raw.dropFirst().dropLast()
        guard let separator = body.firstIndex(of: ":") else { return nil }
        let kind = body[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = body[body.index(after: separator)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kind.isEmpty, !value.isEmpty else { return nil }
        return (kind, value)
    }

    static func modelReference(
        _ raw: String?,
        providers: [RokuricsAIProvider]
    ) -> RokuricsAIModelReference? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        for provider in providers.sorted(by: { $0.id.count > $1.id.count }) {
            let prefix = provider.id + "/"
            if raw.hasPrefix(prefix) {
                let modelID = String(raw.dropFirst(prefix.count))
                guard !modelID.isEmpty else { return nil }
                return RokuricsAIModelReference(providerID: provider.id, modelID: modelID)
            }
        }
        let matches = providers.filter { provider in
            provider.models.contains { $0.id == raw }
        }
        guard matches.count == 1, let provider = matches.first else { return nil }
        return RokuricsAIModelReference(providerID: provider.id, modelID: raw)
    }

    static func ensureModel(
        _ reference: RokuricsAIModelReference,
        in providers: inout [RokuricsAIProvider]
    ) {
        guard let providerIndex = providers.firstIndex(where: { $0.id == reference.providerID }),
              !providers[providerIndex].models.contains(where: { $0.id == reference.modelID }) else {
            return
        }
        providers[providerIndex].models.append(RokuricsAIModel(
            id: reference.modelID,
            displayName: reference.modelID
        ))
    }

    static func validatedHTTPURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            return nil
        }
        return url
    }

    static func requestOptionsAreSafe(_ options: [String: RokuricsJSONValue]) -> Bool {
        let disallowedKeys = ["apikey", "api_key", "authorization", "password", "secret", "access_token", "accesstoken"]
        func valueIsSafe(_ value: RokuricsJSONValue) -> Bool {
            switch value {
            case .string(let value):
                let lowered = value.lowercased()
                return !lowered.contains("bearer ") && !lowered.contains("sk-")
            case .object(let object):
                return requestOptionsAreSafe(object)
            case .array(let array):
                return array.allSatisfy(valueIsSafe)
            case .number, .bool, .null:
                return true
            }
        }
        return options.allSatisfy { key, value in
            let normalizedKey = key.lowercased().replacingOccurrences(of: "-", with: "_")
            return !disallowedKeys.contains(normalizedKey) && valueIsSafe(value)
        }
    }

    static func defaultBaseURL(providerID: String) -> String? {
        switch providerID.lowercased() {
        case "openai": return "https://api.openai.com/v1"
        case "openrouter": return "https://openrouter.ai/api/v1"
        case "deepseek": return "https://api.deepseek.com/v1"
        case "ollama": return "http://localhost:11434/v1"
        case "lmstudio", "lm-studio": return "http://localhost:1234/v1"
        case "groq": return "https://api.groq.com/openai/v1"
        default: return nil
        }
    }

    static func defaultProviderName(providerID: String) -> String {
        switch providerID.lowercased() {
        case "openai": return "OpenAI"
        case "openrouter": return "OpenRouter"
        case "deepseek": return "DeepSeek"
        case "ollama": return "Ollama"
        case "lmstudio", "lm-studio": return "LM Studio"
        case "groq": return "Groq"
        default: return providerID
        }
    }

    static func expandedPath(_ value: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == "~" || value.hasPrefix("~/") else { return value }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return value == "~" ? home : home + String(value.dropFirst())
    }

    static func jsonCompatibleData(_ data: Data) -> Data {
        guard var text = String(data: data, encoding: .utf8) else { return data }
        text = removingJSONComments(text)
        text = removingTrailingJSONCommas(text)
        return Data(text.utf8)
    }

    static func removingJSONComments(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }
            if character == "\"" {
                inString = true
                output.append(character)
                index = text.index(after: index)
                continue
            }
            if character == "/" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "/" {
                    index = text.index(after: next)
                    while index < text.endIndex, text[index] != "\n" {
                        index = text.index(after: index)
                    }
                    continue
                }
                if next < text.endIndex, text[next] == "*" {
                    index = text.index(after: next)
                    while index < text.endIndex {
                        if text[index] == "*" {
                            let after = text.index(after: index)
                            if after < text.endIndex, text[after] == "/" {
                                index = text.index(after: after)
                                break
                            }
                        }
                        index = text.index(after: index)
                    }
                    continue
                }
            }
            output.append(character)
            index = text.index(after: index)
        }
        return output
    }

    static func removingTrailingJSONCommas(_ text: String) -> String {
        var output = ""
        var index = text.startIndex
        var inString = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if inString {
                output.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }
            if character == "\"" {
                inString = true
                output.append(character)
                index = text.index(after: index)
                continue
            }
            if character == "," {
                var lookahead = text.index(after: index)
                while lookahead < text.endIndex, text[lookahead].isWhitespace {
                    lookahead = text.index(after: lookahead)
                }
                if lookahead < text.endIndex,
                   text[lookahead] == "}" || text[lookahead] == "]" {
                    index = text.index(after: index)
                    continue
                }
            }
            output.append(character)
            index = text.index(after: index)
        }
        return output
    }
}
