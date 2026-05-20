//
//  ChatCoordinator.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/20.
//

import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ChatCoordinator: ObservableObject {
    @Published private(set) var conversation: ChatConversation
    @Published private(set) var recentConversations: [ChatConversation]
    @Published private(set) var activeContext: ChatContext?
    @Published private(set) var pendingAttachments: [ChatAttachment] = []
    @Published private(set) var isGenerating = false
    @Published var errorMessage: String?

    private let settingsStore: NoteGenerationSettingsStore
    private let providerResolver: @MainActor () -> any ChatProvider
    private let conversationStore: ChatConversationStore?

    convenience init() {
        self.init(
            settingsStore: .shared,
            providerResolver: nil,
            conversationStore: ChatConversationStore()
        )
    }

    convenience init(
        providerResolver: (@MainActor () -> any ChatProvider)?,
        conversationStore: ChatConversationStore?
    ) {
        self.init(
            settingsStore: .shared,
            providerResolver: providerResolver,
            conversationStore: conversationStore
        )
    }

    init(
        settingsStore: NoteGenerationSettingsStore,
        providerResolver: (@MainActor () -> any ChatProvider)? = nil,
        conversationStore: ChatConversationStore?
    ) {
        self.settingsStore = settingsStore
        self.providerResolver = providerResolver ?? { ChatProviderFactory.provider(for: settingsStore) }
        self.conversationStore = conversationStore

        let savedConversations = conversationStore?.loadRecentConversations() ?? []
        self.recentConversations = savedConversations

        if let savedConversation = savedConversations.first ?? conversationStore?.loadMostRecentConversation() {
            self.conversation = savedConversation
            self.activeContext = savedConversation.activeContextID.flatMap {
                conversationStore?.loadContext(id: $0)
            }
        } else {
            self.conversation = ChatConversation()
            self.activeContext = nil
        }
    }

    var visibleMessages: [ChatMessage] {
        conversation.messages.filter { $0.role != .system }
    }

    func attachments(for message: ChatMessage) -> [ChatAttachment] {
        conversation.attachments(for: message)
    }

    @discardableResult
    func createNewConversation(context: ChatContext? = nil) -> ChatConversation {
        let now = Date()
        let contextPathDisplay = context?.pathDisplay
        conversation = ChatConversation(
            title: Self.initialTitle(context: context),
            titleSource: .fallback,
            activeContextID: context?.id,
            contextPathDisplay: contextPathDisplay,
            contextItemCount: context?.itemCount,
            createdAt: now,
            updatedAt: now
        )
        activeContext = context
        pendingAttachments = []
        errorMessage = nil
        persist()
        refreshRecentConversations()
        return conversation
    }

    func deleteConversation(id: String) {
        let isDeletingActiveConversation = conversation.id == id
        if let conversationStore {
            try? conversationStore.deleteConversation(id: id)
        }

        recentConversations.removeAll { $0.id == id }

        guard isDeletingActiveConversation else {
            refreshRecentConversations()
            return
        }

        let remainingConversations = conversationStore?.loadRecentConversations()
            ?? recentConversations.sorted { left, right in
                if left.updatedAt == right.updatedAt {
                    return left.createdAt > right.createdAt
                }
                return left.updatedAt > right.updatedAt
            }

        if let nextConversation = remainingConversations.first {
            conversation = nextConversation
            activeContext = nextConversation.activeContextID.flatMap {
                conversationStore?.loadContext(id: $0)
            }
            pendingAttachments = []
            errorMessage = nil
            refreshRecentConversations()
        } else {
            createNewConversation()
        }
    }

    func selectConversation(id: String) {
        guard conversation.id != id else {
            return
        }

        let loadedConversation = conversationStore?.loadConversation(id: id)
            ?? recentConversations.first { $0.id == id }
        guard let loadedConversation else {
            return
        }

        conversation = loadedConversation
        activeContext = loadedConversation.activeContextID.flatMap {
            conversationStore?.loadContext(id: $0)
        }
        pendingAttachments = []
        errorMessage = nil
        refreshRecentConversations()
    }

    func importContext(_ context: ChatContext) {
        createNewConversation(context: context)
    }

    func addAttachments(from urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        guard let conversationStore else {
            errorMessage = "无法保存附件"
            return
        }

        var savedAttachments: [ChatAttachment] = []
        for url in urls {
            do {
                let attachment = try conversationStore.saveAttachment(from: url, conversationID: conversation.id)
                conversation.attach(attachment)
                savedAttachments.append(attachment)
            } catch {
                errorMessage = Self.displayMessage(for: error)
            }
        }

        guard !savedAttachments.isEmpty else {
            return
        }

        pendingAttachments.append(contentsOf: savedAttachments)
        conversation.updatedAt = Date()
        persist()
        refreshRecentConversations()
    }

    func removePendingAttachment(id: String) {
        pendingAttachments.removeAll { $0.id == id }
        conversation.detachAttachment(id: id)
        try? conversationStore?.deleteAttachment(id: id, conversationID: conversation.id)
        conversation.updatedAt = Date()
        persist()
        refreshRecentConversations()
    }

    func send(_ rawText: String) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            errorMessage = ChatProviderError.emptyUserMessage.localizedDescription
            return
        }
        guard !isGenerating else {
            return
        }

        errorMessage = nil
        isGenerating = true

        let provider = providerResolver()
        let outgoingAttachments = pendingAttachments
        let supportedAttachments = outgoingAttachments.filter { provider.supportedAttachmentKinds.contains($0.kind) }
        let unsupportedAttachments = outgoingAttachments.filter { !provider.supportedAttachmentKinds.contains($0.kind) }
        if !unsupportedAttachments.isEmpty {
            errorMessage = Self.unsupportedAttachmentNotice(for: provider.unsupportedAttachmentBehavior)
        }

        conversation.messages.append(
            ChatMessage(
                role: .user,
                content: text,
                attachmentIDs: outgoingAttachments.map(\.id)
            )
        )
        pendingAttachments = []
        conversation.lastMessagePreview = Self.preview(for: text)
        conversation.updatedAt = Date()
        persist()
        refreshRecentConversations()

        let request = ChatRequest(
            messages: conversation.messages,
            context: activeContext,
            attachments: supportedAttachments,
            modelName: currentModelName,
            maxTokens: currentMaxTokens,
            temperature: currentTemperature
        )

        var shouldGenerateTitle = false
        do {
            let result = try await provider.send(request: request)
            conversation.messages.append(result.message)
            conversation.lastMessagePreview = Self.preview(for: result.message.content)
            conversation.updatedAt = Date()
            persist()
            refreshRecentConversations()
            shouldGenerateTitle = true
        } catch {
            errorMessage = Self.displayMessage(for: error)
        }

        isGenerating = false

        if shouldGenerateTitle {
            await generateTitleIfNeeded(provider: provider)
        }
    }

    private func generateTitleIfNeeded(provider: any ChatProvider) async {
        guard conversation.titleSource != .aiGenerated,
              conversation.titleGeneratedAt == nil else {
            return
        }
        let userMessages = conversation.messages
            .filter { $0.role == .user }
            .prefix(2)
            .map(\.content)
        guard !userMessages.isEmpty,
              let firstAssistantMessage = conversation.messages.first(where: { $0.role == .assistant })?.content else {
            return
        }

        let request = ChatTitleRequest(
            firstUserMessages: Array(userMessages),
            firstAssistantMessage: firstAssistantMessage,
            contextPathDisplay: conversation.contextPathDisplay
        )

        do {
            let title = ChatTitlePromptBuilder.cleanedTitle(try await provider.generateConversationTitle(request: request))
            if title.isEmpty {
                applyFallbackTitle(for: request)
            } else {
                conversation.title = title
                conversation.titleSource = .aiGenerated
                conversation.titleGeneratedAt = Date()
                conversation.updatedAt = Date()
                persist()
                refreshRecentConversations()
            }
        } catch {
            applyFallbackTitle(for: request)
        }
    }

    private func applyFallbackTitle(for request: ChatTitleRequest) {
        conversation.title = ChatTitlePromptBuilder.fallbackTitle(for: request)
        conversation.titleSource = .fallback
        conversation.titleGeneratedAt = Date()
        conversation.updatedAt = Date()
        persist()
        refreshRecentConversations()
    }

    private var currentModelName: String? {
        switch settingsStore.selectedProviderKind {
        case .mock:
            return "mock"
        case .openAICompatible:
            return settingsStore.openAIConfiguration.trimmedModelName
        case .anthropicMessages:
            return settingsStore.anthropicConfiguration.trimmedModelName
        }
    }

    private var currentMaxTokens: Int {
        switch settingsStore.selectedProviderKind {
        case .mock:
            return 800
        case .openAICompatible:
            return max(1, settingsStore.openAIConfiguration.maxTokens)
        case .anthropicMessages:
            return max(1, settingsStore.anthropicConfiguration.maxTokens)
        }
    }

    private var currentTemperature: Double {
        switch settingsStore.selectedProviderKind {
        case .mock:
            return 0.1
        case .openAICompatible:
            return settingsStore.openAIConfiguration.temperature
        case .anthropicMessages:
            return settingsStore.anthropicConfiguration.temperature
        }
    }

    private func persist() {
        guard let conversationStore else {
            return
        }

        if let activeContext {
            try? conversationStore.saveContext(activeContext)
        }
        try? conversationStore.saveConversation(conversation)
    }

    private func refreshRecentConversations() {
        guard let conversationStore else {
            recentConversations = [conversation]
            return
        }

        let loaded = conversationStore.loadRecentConversations()
        if loaded.contains(where: { $0.id == conversation.id }) {
            recentConversations = loaded
        } else {
            recentConversations = ([conversation] + loaded)
                .sorted { left, right in
                    left.updatedAt > right.updatedAt
                }
        }
    }

    private static func displayMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return "AI 请求失败"
        }

        return message.replacingOccurrences(
            of: #"sk-[A-Za-z0-9_\-]{6,}"#,
            with: "[redacted]",
            options: .regularExpression
        )
    }

    private static func initialTitle(context: ChatContext?) -> String {
        if context?.sourceKind == .studyItem,
           let itemTitle = context?.itemTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !itemTitle.isEmpty {
            return itemTitle
        }

        guard let contextPathDisplay = context?.pathDisplay,
              !contextPathDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "新对话"
        }

        let lastComponent = contextPathDisplay
            .components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .last ?? "学习库"
        return "\(lastComponent)对话"
    }

    private static func preview(for text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > 80 else {
            return normalized
        }
        return String(normalized.prefix(80))
    }

    private static func unsupportedAttachmentNotice(for behavior: ChatUnsupportedAttachmentBehavior) -> String {
        switch behavior {
        case .keepLocalOnlyWithNotice:
            return "附件已保存到本地，当前模型暂不支持附件输入，本次只发送文字。"
        }
    }
}

final class ChatConversationStore {
    private let fileManager: FileManager
    private let rootURL: URL
    private let conversationsURL: URL
    private let contextsURL: URL
    private let attachmentsURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.rootURL = applicationSupportURL
                .appendingPathComponent("Rokurics", isDirectory: true)
                .standardizedFileURL
        }
        self.conversationsURL = self.rootURL
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)
            .standardizedFileURL
        self.contextsURL = self.rootURL
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("contexts", isDirectory: true)
            .standardizedFileURL
        self.attachmentsURL = self.rootURL
            .appendingPathComponent("chats", isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
            .standardizedFileURL
    }

    func saveConversation(_ conversation: ChatConversation) throws {
        try ensureDirectories()
        let url = conversationsURL
            .appendingPathComponent(Self.safeFileName(conversation.id), isDirectory: false)
            .appendingPathExtension("json")
            .standardizedFileURL
        guard isInsideConversationsDirectory(url) else {
            return
        }

        try Self.encoder.encode(conversation).write(to: url, options: .atomic)
    }

    func deleteConversation(id: String) throws {
        try ensureDirectories()
        let conversationURL = conversationsURL
            .appendingPathComponent(Self.safeFileName(id), isDirectory: false)
            .appendingPathExtension("json")
            .standardizedFileURL
        if isInsideConversationsDirectory(conversationURL),
           fileManager.fileExists(atPath: conversationURL.path) {
            try fileManager.removeItem(at: conversationURL)
        }

        let attachmentDirectoryURL = attachmentsURL
            .appendingPathComponent(Self.safeFileName(id), isDirectory: true)
            .standardizedFileURL
        if isInsideAttachmentsDirectory(attachmentDirectoryURL),
           fileManager.fileExists(atPath: attachmentDirectoryURL.path) {
            try fileManager.removeItem(at: attachmentDirectoryURL)
        }
    }

    func saveContext(_ context: ChatContext) throws {
        try ensureDirectories()
        let url = contextsURL
            .appendingPathComponent(Self.safeFileName(context.id), isDirectory: false)
            .appendingPathExtension("json")
            .standardizedFileURL
        guard isInsideContextsDirectory(url) else {
            return
        }

        try Self.encoder.encode(context).write(to: url, options: .atomic)
    }

    func loadMostRecentConversation() -> ChatConversation? {
        loadRecentConversations(limit: 1).first
    }

    func loadRecentConversations(limit: Int? = nil) -> [ChatConversation] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: conversationsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let conversations = urls
            .filter { $0.pathExtension == "json" && isInsideConversationsDirectory($0) }
            .compactMap { url -> ChatConversation? in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? Self.decoder.decode(ChatConversation.self, from: data)
            }
            .sorted { left, right in
                if left.updatedAt == right.updatedAt {
                    return left.createdAt > right.createdAt
                }
                return left.updatedAt > right.updatedAt
            }

        if let limit {
            return Array(conversations.prefix(limit))
        }
        return conversations
    }

    func loadConversation(id: String) -> ChatConversation? {
        let url = conversationsURL
            .appendingPathComponent(Self.safeFileName(id), isDirectory: false)
            .appendingPathExtension("json")
            .standardizedFileURL
        guard isInsideConversationsDirectory(url),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? Self.decoder.decode(ChatConversation.self, from: data)
    }

    func loadContext(id: String) -> ChatContext? {
        let url = contextsURL
            .appendingPathComponent(Self.safeFileName(id), isDirectory: false)
            .appendingPathExtension("json")
            .standardizedFileURL
        guard isInsideContextsDirectory(url),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? Self.decoder.decode(ChatContext.self, from: data)
    }

    func saveAttachment(from sourceURL: URL, conversationID: String) throws -> ChatAttachment {
        try ensureDirectories()
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let attachmentID = UUID().uuidString
        let sanitizedConversationID = Self.safeFileName(conversationID)
        let sanitizedFileName = Self.sanitizedAttachmentFileName(sourceURL.lastPathComponent)
        let storedFileName = "\(attachmentID)-\(sanitizedFileName)"
        let conversationDirectoryURL = attachmentsURL
            .appendingPathComponent(sanitizedConversationID, isDirectory: true)
            .standardizedFileURL
        let destinationURL = conversationDirectoryURL
            .appendingPathComponent(storedFileName, isDirectory: false)
            .standardizedFileURL
        guard isInsideAttachmentsDirectory(destinationURL) else {
            throw ChatAttachmentStoreError.invalidDestination
        }

        try fileManager.createDirectory(at: conversationDirectoryURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let fileType = destinationURL.pathExtension.lowercased()
        let type = fileType.isEmpty ? nil : UTType(filenameExtension: fileType)
        let relativePath = [
            "chats",
            "attachments",
            sanitizedConversationID,
            storedFileName
        ].joined(separator: "/")
        return ChatAttachment(
            id: attachmentID,
            conversationID: conversationID,
            fileName: sanitizedFileName,
            fileType: fileType,
            mimeType: type?.preferredMIMEType,
            relativePath: relativePath,
            sizeBytes: Self.fileSize(at: destinationURL, fileManager: fileManager),
            kind: Self.attachmentKind(fileExtension: fileType, contentType: type)
        )
    }

    func deleteAttachment(id: String, conversationID: String) throws {
        let sanitizedConversationID = Self.safeFileName(conversationID)
        let directoryURL = attachmentsURL
            .appendingPathComponent(sanitizedConversationID, isDirectory: true)
            .standardizedFileURL
        guard isInsideAttachmentsDirectory(directoryURL),
              let urls = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for url in urls where url.lastPathComponent.hasPrefix(id + "-") && isInsideAttachmentsDirectory(url) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: conversationsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: contextsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
    }

    private func isInsideConversationsDirectory(_ url: URL) -> Bool {
        isInside(url, directory: conversationsURL)
    }

    private func isInsideContextsDirectory(_ url: URL) -> Bool {
        isInside(url, directory: contextsURL)
    }

    private func isInsideAttachmentsDirectory(_ url: URL) -> Bool {
        isInside(url, directory: attachmentsURL)
    }

    private func isInside(_ url: URL, directory: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == directoryPath || filePath.hasPrefix(directoryPath + "/")
    }

    private static func safeFileName(_ value: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = value.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return sanitized.isEmpty ? UUID().uuidString : sanitized
    }

    static func sanitizedAttachmentFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "attachment" : trimmed
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- "))
        let sanitized = fallback.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        let limited = sanitized.isEmpty ? "attachment" : String(sanitized.prefix(96))
        return limited.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).isEmpty ? "attachment" : limited
    }

    private static func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        if let number = attributes?[.size] as? NSNumber {
            return number.int64Value
        }
        return 0
    }

    private static func attachmentKind(fileExtension: String, contentType: UTType?) -> ChatAttachmentKind {
        if contentType?.conforms(to: .image) == true {
            return .image
        }
        if contentType?.conforms(to: .audio) == true {
            return .audio
        }
        if contentType?.conforms(to: .text) == true || contentType?.conforms(to: .pdf) == true {
            return .document
        }

        let documentExtensions: Set<String> = ["md", "txt", "rtf", "csv", "json", "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx"]
        if documentExtensions.contains(fileExtension.lowercased()) {
            return .document
        }
        return .other
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum ChatAttachmentStoreError: LocalizedError, Equatable {
    case invalidDestination

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return "附件保存路径无效"
        }
    }
}
