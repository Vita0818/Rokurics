//
//  ChatProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/20.
//

import Foundation

protocol ChatProvider {
    var id: String { get }
    var displayName: String { get }
    var supportedAttachmentKinds: Set<ChatAttachmentKind> { get }
    var unsupportedAttachmentBehavior: ChatUnsupportedAttachmentBehavior { get }

    func validateConfiguration() async throws
    func send(request: ChatRequest) async throws -> ChatResult
    func generateConversationTitle(request: ChatTitleRequest) async throws -> String
}

extension ChatProvider {
    var supportedAttachmentKinds: Set<ChatAttachmentKind> {
        []
    }

    var unsupportedAttachmentBehavior: ChatUnsupportedAttachmentBehavior {
        .keepLocalOnlyWithNotice
    }

    func generateConversationTitle(request: ChatTitleRequest) async throws -> String {
        let result = try await send(
            request: ChatRequest(
                messages: [
                    ChatMessage(role: .user, content: ChatTitlePromptBuilder.userPrompt(for: request))
                ],
                context: nil,
                modelName: nil,
                maxTokens: 40,
                temperature: 0.1
            )
        )
        return ChatTitlePromptBuilder.cleanedTitle(result.message.content)
    }
}

enum ChatProviderError: LocalizedError, Equatable {
    case providerNotConfigured(String)
    case emptyUserMessage
    case emptyAssistantMessage

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let providerName):
            return "\(providerName) 未配置，请先到设置页配置 AI"
        case .emptyUserMessage:
            return "请输入消息"
        case .emptyAssistantMessage:
            return "AI 没有返回内容"
        }
    }
}

struct MockChatProvider: ChatProvider {
    let id = "mockChatProvider"
    let displayName = "Mock"
    let supportedAttachmentKinds: Set<ChatAttachmentKind> = Set(ChatAttachmentKind.allCases)

    func validateConfiguration() async throws {}

    func send(request: ChatRequest) async throws -> ChatResult {
        let lastQuestion = request.messages.last(where: { $0.role == .user })?.content ?? ""
        let contextHint: String
        if let context = request.context, context.itemCount > 0 {
            contextHint = "已参考 \(context.displayTitle) 的 \(context.itemCount) 项资料。"
        } else {
            contextHint = "当前没有导入学习库上下文。"
        }
        let content = [contextHint, "你问的是：\(lastQuestion)"]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        let message = ChatMessage(role: .assistant, content: content)
        return ChatResult(
            message: message,
            providerID: id,
            providerName: displayName,
            modelName: "mock",
            finishReason: "stop",
            outputWasTruncated: false
        )
    }

    func generateConversationTitle(request: ChatTitleRequest) async throws -> String {
        ChatTitlePromptBuilder.fallbackTitle(for: request)
    }
}

struct OpenAICompatibleChatProvider: ChatProvider {
    let id = "openAICompatibleChatProvider"
    let displayName = "OpenAI-compatible"

    private let configuration: OpenAICompatibleNoteGenerationConfiguration
    private let client: OpenAICompatibleNoteGenerationClient

    init(
        configuration: OpenAICompatibleNoteGenerationConfiguration,
        client: OpenAICompatibleNoteGenerationClient = OpenAICompatibleNoteGenerationClient()
    ) {
        self.configuration = configuration
        self.client = client
    }

    func validateConfiguration() async throws {
        guard !configuration.trimmedBaseURLString.isEmpty,
              !configuration.trimmedModelName.isEmpty else {
            throw ChatProviderError.providerNotConfigured(displayName)
        }
    }

    func send(request: ChatRequest) async throws -> ChatResult {
        try await validateConfiguration()
        let resolvedConfiguration = configuration.withChatOverrides(modelName: request.modelName)
        let result = try await client.chatCompletion(
            configuration: resolvedConfiguration,
            messages: ChatPromptBuilder.openAIMessages(for: request),
            timeout: 120,
            maxTokens: request.maxTokens,
            temperature: request.temperature
        )
        let content = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw ChatProviderError.emptyAssistantMessage
        }

        return ChatResult(
            message: ChatMessage(role: .assistant, content: content),
            providerID: id,
            providerName: displayName,
            modelName: resolvedConfiguration.trimmedModelName,
            finishReason: result.finishReason,
            outputWasTruncated: result.isLengthLimited
        )
    }

    func generateConversationTitle(request: ChatTitleRequest) async throws -> String {
        try await validateConfiguration()
        let result = try await client.chatCompletion(
            configuration: configuration,
            messages: ChatTitlePromptBuilder.openAIMessages(for: request),
            timeout: 45,
            maxTokens: 40,
            temperature: 0.1
        )
        let title = ChatTitlePromptBuilder.cleanedTitle(result.content)
        guard !title.isEmpty else {
            throw ChatProviderError.emptyAssistantMessage
        }
        return title
    }
}

struct AnthropicMessagesChatProvider: ChatProvider {
    let id = "anthropicMessagesChatProvider"
    let displayName = "Claude / Anthropic"

    private let configuration: AnthropicMessagesConfiguration
    private let client: AnthropicMessagesNoteGenerationClient

    init(
        configuration: AnthropicMessagesConfiguration,
        client: AnthropicMessagesNoteGenerationClient = AnthropicMessagesNoteGenerationClient()
    ) {
        self.configuration = configuration
        self.client = client
    }

    func validateConfiguration() async throws {
        guard !configuration.trimmedBaseURLString.isEmpty,
              !configuration.trimmedModelName.isEmpty,
              !configuration.trimmedAPIKey.isEmpty else {
            throw ChatProviderError.providerNotConfigured(displayName)
        }
    }

    func send(request: ChatRequest) async throws -> ChatResult {
        try await validateConfiguration()
        let resolvedConfiguration = configuration.withChatOverrides(modelName: request.modelName)
        let result = try await client.message(
            configuration: resolvedConfiguration,
            system: ChatPromptBuilder.systemPrompt(context: request.context),
            userContent: ChatPromptBuilder.anthropicConversationText(for: request.messages),
            timeout: 120,
            maxTokens: request.maxTokens,
            temperature: request.temperature
        )
        let content = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw ChatProviderError.emptyAssistantMessage
        }

        return ChatResult(
            message: ChatMessage(role: .assistant, content: content),
            providerID: id,
            providerName: displayName,
            modelName: resolvedConfiguration.trimmedModelName,
            finishReason: result.stopReason,
            outputWasTruncated: result.isLengthLimited
        )
    }

    func generateConversationTitle(request: ChatTitleRequest) async throws -> String {
        try await validateConfiguration()
        let result = try await client.message(
            configuration: configuration,
            system: ChatTitlePromptBuilder.systemPrompt,
            userContent: ChatTitlePromptBuilder.userPrompt(for: request),
            timeout: 45,
            maxTokens: 40,
            temperature: 0.1
        )
        let title = ChatTitlePromptBuilder.cleanedTitle(result.content)
        guard !title.isEmpty else {
            throw ChatProviderError.emptyAssistantMessage
        }
        return title
    }
}

enum ChatProviderFactory {
    @MainActor
    static func provider(for settingsStore: NoteGenerationSettingsStore) -> any ChatProvider {
        switch settingsStore.selectedProviderKind {
        case .mock:
            return MockChatProvider()
        case .openAICompatible:
            return OpenAICompatibleChatProvider(configuration: settingsStore.openAIConfiguration)
        case .anthropicMessages:
            return AnthropicMessagesChatProvider(configuration: settingsStore.anthropicConfiguration)
        }
    }
}

enum ChatPromptBuilder {
    static func openAIMessages(for request: ChatRequest) -> [OpenAICompatibleMessage] {
        let systemMessage = OpenAICompatibleMessage(
            role: ChatMessageRole.system.rawValue,
            content: systemPrompt(context: request.context)
        )
        let conversationMessages = request.messages
            .filter { $0.role != .system }
            .map { OpenAICompatibleMessage(role: $0.role.rawValue, content: $0.content) }
        return [systemMessage] + conversationMessages
    }

    static func anthropicConversationText(for messages: [ChatMessage]) -> String {
        messages
            .filter { $0.role != .system }
            .map { message in
                switch message.role {
                case .user:
                    return "用户：\n\(message.content)"
                case .assistant:
                    return "助手：\n\(message.content)"
                case .system:
                    return ""
                }
            }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    static func systemPrompt(context: ChatContext?) -> String {
        var prompt = """
        你是 Rokurics 的学习助手。请基于用户导入的学习资料上下文回答。若上下文不足，请明确说明需要补充资料，不要编造。
        """

        if let context, !context.formattedContext.isEmpty {
            prompt += """


            已导入上下文：\(context.displayTitle) · \(context.itemCount) 项

            \(context.formattedContext)
            """
        }

        return prompt
    }
}

enum ChatTitlePromptBuilder {
    static let systemPrompt = """
    你只负责为一段 AI 对话生成中文短标题。输出 8 到 20 个中文字符左右，不要引号，不要句号，不要 Markdown，不要解释。
    """

    static func openAIMessages(for request: ChatTitleRequest) -> [OpenAICompatibleMessage] {
        [
            OpenAICompatibleMessage(role: ChatMessageRole.system.rawValue, content: systemPrompt),
            OpenAICompatibleMessage(role: ChatMessageRole.user.rawValue, content: userPrompt(for: request))
        ]
    }

    static func userPrompt(for request: ChatTitleRequest) -> String {
        var lines: [String] = []
        if let contextPath = request.contextPathDisplay?.trimmingCharacters(in: .whitespacesAndNewlines),
           !contextPath.isEmpty {
            lines.append("上下文路径：\(contextPath)")
        }

        let userMessages = request.firstUserMessages
            .map { limited($0, to: 120) }
            .filter { !$0.isEmpty }
        for (index, message) in userMessages.enumerated() {
            lines.append("用户消息 \(index + 1)：\(message)")
        }

        if let assistant = request.firstAssistantMessage.map({ limited($0, to: 160) }),
           !assistant.isEmpty {
            lines.append("助手回复：\(assistant)")
        }

        lines.append("请生成标题。")
        return lines.joined(separator: "\n")
    }

    static func cleanedTitle(_ rawTitle: String) -> String {
        let firstLine = rawTitle
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .first ?? rawTitle
        let stripped = firstLine
            .replacingOccurrences(of: #"^[#\-\s"“”'「」『』`]+|["“”'「」『』`。.\s]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return limited(stripped, to: 24)
    }

    static func fallbackTitle(for request: ChatTitleRequest) -> String {
        if let firstMessage = request.firstUserMessages
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) {
            return cleanedTitle(limited(firstMessage, to: 20))
        }

        if let contextPath = request.contextPathDisplay?.trimmingCharacters(in: .whitespacesAndNewlines),
           !contextPath.isEmpty {
            let lastComponent = contextPath
                .components(separatedBy: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .last ?? "学习库"
            return cleanedTitle("\(lastComponent)对话")
        }

        return "新对话"
    }

    private static func limited(_ text: String, to maxCharacters: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else {
            return trimmed
        }
        return String(trimmed.prefix(maxCharacters))
    }
}

private extension OpenAICompatibleNoteGenerationConfiguration {
    func withChatOverrides(modelName: String?) -> OpenAICompatibleNoteGenerationConfiguration {
        OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: trimmedBaseURLString,
            modelName: Self.nonEmpty(modelName) ?? trimmedModelName,
            apiKey: trimmedAPIKey,
            temperature: temperature,
            maxTokens: maxTokens,
            maxTranscriptCharacters: maxTranscriptCharacters
        )
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension AnthropicMessagesConfiguration {
    func withChatOverrides(modelName: String?) -> AnthropicMessagesConfiguration {
        AnthropicMessagesConfiguration(
            baseURLString: trimmedBaseURLString,
            modelName: Self.nonEmpty(modelName) ?? trimmedModelName,
            apiKey: trimmedAPIKey,
            anthropicVersion: trimmedAnthropicVersion,
            temperature: temperature,
            maxTokens: maxTokens,
            maxTranscriptCharacters: maxTranscriptCharacters
        )
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
