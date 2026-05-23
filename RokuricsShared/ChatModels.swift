//
//  ChatModels.swift
//  Rokurics
//
//  Created by Codex on 2026/5/20.
//

import Foundation

enum ChatMessageRole: String, Codable, Equatable {
    case system
    case user
    case assistant
}

struct ChatMessage: Codable, Equatable, Identifiable {
    var id: String
    var role: ChatMessageRole
    var content: String
    var createdAt: Date
    var attachmentIDs: [String]

    init(
        id: String = UUID().uuidString,
        role: ChatMessageRole,
        content: String,
        createdAt: Date = Date(),
        attachmentIDs: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.attachmentIDs = attachmentIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt
        case attachmentIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        role = try container.decode(ChatMessageRole.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        attachmentIDs = try container.decodeIfPresent([String].self, forKey: .attachmentIDs) ?? []
    }
}

struct ChatContextItem: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var filingPath: StudyFilingPath
    var content: String
    var sourcePath: String?
    var contentCharacterCount: Int
    var isTruncated: Bool

    init(
        id: String,
        title: String,
        filingPath: StudyFilingPath,
        content: String,
        sourcePath: String? = nil,
        contentCharacterCount: Int? = nil,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.title = Self.nonEmpty(title) ?? "未命名知识"
        self.filingPath = filingPath
        self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourcePath = sourcePath.flatMap(Self.nonEmpty)
        self.contentCharacterCount = contentCharacterCount ?? self.content.count
        self.isTruncated = isTruncated
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ChatContextSourceKind: String, Codable, Equatable {
    case studyLibrary
    case studyItem
}

struct ChatContext: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var browsePathComponents: [String]
    var itemCount: Int
    var items: [ChatContextItem]
    var sourceKind: ChatContextSourceKind?
    var sourceItemID: String?
    var contextPathDisplay: String?
    var itemTitle: String?
    var createdAt: Date
    var maxContextCharacters: Int
    var totalCharacterCount: Int
    var isTruncated: Bool

    init(
        id: String = UUID().uuidString,
        title: String,
        browsePathComponents: [String] = [],
        itemCount: Int,
        items: [ChatContextItem],
        sourceKind: ChatContextSourceKind? = nil,
        sourceItemID: String? = nil,
        contextPathDisplay: String? = nil,
        itemTitle: String? = nil,
        createdAt: Date = Date(),
        maxContextCharacters: Int,
        totalCharacterCount: Int? = nil,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.title = Self.nonEmpty(title) ?? "学习库"
        self.browsePathComponents = browsePathComponents
        self.itemCount = itemCount
        self.items = items
        self.sourceKind = sourceKind
        self.sourceItemID = Self.nonEmpty(sourceItemID)
        self.contextPathDisplay = Self.nonEmpty(contextPathDisplay)
        self.itemTitle = Self.nonEmpty(itemTitle)
        self.createdAt = createdAt
        self.maxContextCharacters = maxContextCharacters
        self.totalCharacterCount = totalCharacterCount ?? items.reduce(0) { $0 + $1.content.count }
        self.isTruncated = isTruncated
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case browsePathComponents
        case itemCount
        case items
        case sourceKind
        case sourceItemID
        case contextPathDisplay
        case itemTitle
        case createdAt
        case maxContextCharacters
        case totalCharacterCount
        case isTruncated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .title)) ?? "学习库"
        browsePathComponents = try container.decodeIfPresent([String].self, forKey: .browsePathComponents) ?? []
        itemCount = try container.decodeIfPresent(Int.self, forKey: .itemCount) ?? 0
        items = try container.decodeIfPresent([ChatContextItem].self, forKey: .items) ?? []
        sourceKind = try container.decodeIfPresent(ChatContextSourceKind.self, forKey: .sourceKind)
        sourceItemID = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .sourceItemID))
        contextPathDisplay = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .contextPathDisplay))
        itemTitle = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .itemTitle))
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        maxContextCharacters = try container.decodeIfPresent(Int.self, forKey: .maxContextCharacters) ?? 20_000
        totalCharacterCount = try container.decodeIfPresent(Int.self, forKey: .totalCharacterCount)
            ?? items.reduce(0) { $0 + $1.content.count }
        isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var displayTitle: String {
        title
    }

    var pathDisplay: String {
        if let contextPathDisplay {
            return contextPathDisplay
        }
        let components = ["学习库"] + browsePathComponents
        return components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    var formattedContext: String {
        items.map { item in
            var lines = [
                "### \(item.title)",
                "路径：\(item.filingPath.displaySummary)"
            ]
            if let sourcePath = item.sourcePath {
                lines.append("来源：\(sourcePath)")
            }
            lines.append(item.content)
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }
}

struct ChatContextBuildOptions: Equatable {
    var maxContextCharacters: Int = 20_000
    var maxCharactersPerItem: Int = 2_000
    var maxNoteCharacters: Int = 1_600
    var maxTranscriptCharacters: Int = 1_200
}

struct StudyLibraryContextExporter {
    private let rootURL: URL
    private let fileManager: FileManager
    private let options: ChatContextBuildOptions

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        options: ChatContextBuildOptions = ChatContextBuildOptions()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.options = options
    }

    func export(items: [StudyItemMetadata], path: StudyBrowsePath) -> ChatContext {
        let matchingItems = items
            .filter { !$0.isTrashed }
            .filter { StudyLibraryBrowser.itemMatches($0, path: path) }
            .sorted { left, right in
                if left.createdAt == right.createdAt {
                    return left.title.localizedStandardCompare(right.title) == .orderedAscending
                }
                return left.createdAt > right.createdAt
            }

        return ChatContextBuilder(rootURL: rootURL, fileManager: fileManager, options: options)
            .build(title: Self.contextTitle(for: path), browsePath: path, items: matchingItems)
    }

    func export(item: StudyItemMetadata) -> ChatContext {
        ChatContextBuilder(rootURL: rootURL, fileManager: fileManager, options: options)
            .build(item: item)
    }

    static func contextTitle(for path: StudyBrowsePath) -> String {
        path.components.last ?? "学习库"
    }
}

struct ChatContextBuilder {
    private let rootURL: URL
    private let fileManager: FileManager
    private let options: ChatContextBuildOptions

    init(
        rootURL: URL,
        fileManager: FileManager = .default,
        options: ChatContextBuildOptions = ChatContextBuildOptions()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        self.options = options
    }

    func build(title: String, browsePath: StudyBrowsePath, items: [StudyItemMetadata]) -> ChatContext {
        var contextItems: [ChatContextItem] = []
        var remainingCharacters = max(0, options.maxContextCharacters)
        var totalCharacters = 0
        var contextWasTruncated = false

        for item in items {
            guard remainingCharacters > 0 else {
                contextWasTruncated = true
                break
            }

            let draft = contentDraft(for: item)
            let itemLimit = min(options.maxCharactersPerItem, remainingCharacters)
            let limitedContent = Self.limited(draft.content, to: itemLimit)
            let trimmedContent = limitedContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let wasTruncated = draft.content.count > trimmedContent.count

            guard !trimmedContent.isEmpty else {
                continue
            }

            contextItems.append(
                ChatContextItem(
                    id: item.itemID,
                    title: item.title,
                    filingPath: item.filingPath,
                    content: trimmedContent,
                    sourcePath: draft.sourceLabel,
                    contentCharacterCount: trimmedContent.count,
                    isTruncated: wasTruncated
                )
            )
            remainingCharacters -= trimmedContent.count
            totalCharacters += trimmedContent.count
            contextWasTruncated = contextWasTruncated || wasTruncated
        }

        if contextItems.count < items.count {
            contextWasTruncated = true
        }

        return ChatContext(
            title: title,
            browsePathComponents: browsePath.components,
            itemCount: items.count,
            items: contextItems,
            sourceKind: .studyLibrary,
            contextPathDisplay: Self.pathDisplay(components: browsePath.components),
            maxContextCharacters: options.maxContextCharacters,
            totalCharacterCount: totalCharacters,
            isTruncated: contextWasTruncated
        )
    }

    func build(item: StudyItemMetadata) -> ChatContext {
        let draft = contentDraft(for: item)
        let itemLimit = min(options.maxCharactersPerItem, options.maxContextCharacters)
        let limitedContent = Self.limited(draft.content, to: itemLimit)
        let trimmedContent = limitedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasTruncated = draft.content.count > trimmedContent.count
        let browsePathComponents = Self.browsePathComponents(for: item.filingPath)
        let contextPathDisplay = Self.pathDisplay(components: browsePathComponents + [item.title])
        let contextItems = [
            ChatContextItem(
                id: item.itemID,
                title: item.title,
                filingPath: item.filingPath,
                content: trimmedContent,
                sourcePath: draft.sourceLabel,
                contentCharacterCount: trimmedContent.count,
                isTruncated: wasTruncated
            )
        ].filter { !$0.content.isEmpty }

        return ChatContext(
            title: item.title,
            browsePathComponents: browsePathComponents,
            itemCount: 1,
            items: contextItems,
            sourceKind: .studyItem,
            sourceItemID: item.itemID,
            contextPathDisplay: contextPathDisplay,
            itemTitle: item.title,
            maxContextCharacters: options.maxContextCharacters,
            totalCharacterCount: trimmedContent.count,
            isTruncated: wasTruncated
        )
    }

    private func contentDraft(for item: StudyItemMetadata) -> (content: String, sourceLabel: String?) {
        if let preview = loadSummaryPreview(noteRelativePath: item.noteRelativePath), preview.isVisible {
            let summary = ChatContextTextSanitizer.sanitized(preview.shortSummary)
            let keyPoints = preview.keyPoints
                .map(ChatContextTextSanitizer.sanitized)
                .filter { !$0.isEmpty }
            var lines: [String] = []
            if !summary.isEmpty {
                lines.append("摘要：\(summary)")
            }
            if !keyPoints.isEmpty {
                lines.append("重点：")
                lines.append(contentsOf: keyPoints.map { "- \($0)" })
            }
            let content = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                return (content, "note summary")
            }
        }

        if let noteMarkdown = readText(relativePath: item.noteRelativePath) {
            let preview = markdownPreview(
                from: noteMarkdown,
                preferredHeadings: ["摘要", "大纲", "重点", "关键点", "复习重点"],
                maxCharacters: options.maxNoteCharacters
            )
            if !preview.isEmpty {
                return (preview, "note")
            }
        }

        if let transcriptMarkdown = readText(relativePath: item.transcriptMarkdownRelativePath ?? item.transcriptRelativePath) {
            let preview = markdownPreview(
                from: transcriptMarkdown,
                preferredHeadings: ["Transcript", "转写", "正文"],
                maxCharacters: options.maxTranscriptCharacters
            )
            if !preview.isEmpty {
                return (preview, "transcript")
            }
        }

        return ("标题：\(item.title)\n路径：\(item.filingPath.displaySummary)", "metadata")
    }

    private func loadSummaryPreview(noteRelativePath: String?) -> NoteSummaryPreview? {
        guard let noteURL = resolvedRootFileURL(relativePath: noteRelativePath) else {
            return nil
        }

        let summaryURL = noteURL
            .deletingLastPathComponent()
            .appendingPathComponent("summary.json", isDirectory: false)
            .standardizedFileURL
        if fileManager.fileExists(atPath: summaryURL.path),
           let data = try? Data(contentsOf: summaryURL),
           let preview = try? Self.summaryPreviewDecoder.decode(NoteSummaryPreview.self, from: data) {
            return preview
        }

        guard fileManager.fileExists(atPath: noteURL.path),
              let markdown = try? String(contentsOf: noteURL, encoding: .utf8) else {
            return nil
        }

        return NoteSummaryPreview(
            recordingID: "",
            noteRelativePath: noteRelativePath ?? "",
            shortSummary: NoteSummaryPreview.shortSummary(from: markdown) ?? NoteSummaryPreview.fallbackSummary(from: markdown),
            keyPoints: NoteSummaryPreview.keyPoints(from: markdown),
            generatedAt: nil,
            providerDisplayName: nil,
            modelName: nil
        )
    }

    private func markdownPreview(
        from markdown: String,
        preferredHeadings: [String],
        maxCharacters: Int
    ) -> String {
        let normalizedLines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        let preferredLines = preferredHeadings.flatMap { section(named: $0, in: normalizedLines) }
        let lines = preferredLines.isEmpty ? readableLines(from: normalizedLines) : preferredLines
        let sanitized = ChatContextTextSanitizer.sanitized(lines.joined(separator: "\n"))
        return Self.limited(sanitized, to: maxCharacters).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func section(named headingName: String, in lines: [String]) -> [String] {
        guard let startIndex = lines.firstIndex(where: { Self.headingTitle($0) == headingName }) else {
            return []
        }

        let contentStart = startIndex + 1
        let contentEnd = lines[contentStart...].firstIndex { Self.headingTitle($0) != nil } ?? lines.endIndex
        return Array(lines[contentStart..<contentEnd])
    }

    private func readableLines(from lines: [String]) -> [String] {
        lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return false
            }
            guard Self.headingTitle(trimmed) == nil else {
                return false
            }

            let lower = trimmed.lowercased()
            return !lower.hasPrefix("- provider:")
                && !lower.hasPrefix("- transcribed at:")
                && !lower.hasPrefix("- language:")
        }
    }

    private func readText(relativePath: String?) -> String? {
        guard let url = resolvedRootFileURL(relativePath: relativePath),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func resolvedRootFileURL(relativePath: String?) -> URL? {
        guard let trimmedPath = relativePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/") else {
            return nil
        }

        let url = rootURL.appendingPathComponent(trimmedPath, isDirectory: false).standardizedFileURL
        return isInsideRoot(url) ? url : nil
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private static func headingTitle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else {
            return nil
        }

        let title = trimmed
            .drop(while: { $0 == "#" || $0 == " " })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func limited(_ text: String, to maxCharacters: Int) -> String {
        guard maxCharacters > 0 else {
            return ""
        }
        guard text.count > maxCharacters else {
            return text
        }

        guard maxCharacters > 3 else {
            return String(text.prefix(maxCharacters))
        }

        return String(text.prefix(maxCharacters - 3)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private static func browsePathComponents(for filingPath: StudyFilingPath) -> [String] {
        [filingPath.type, filingPath.subject, filingPath.chapter, filingPath.topic]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func pathDisplay(components: [String]) -> String {
        (["学习库"] + components)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
    }

    private static let summaryPreviewDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum ChatContextTextSanitizer {
    nonisolated static func sanitized(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                let lower = line.lowercased()
                return !sensitiveMarkers.contains { lower.contains($0) }
            }

        return redactSecrets(in: lines.joined(separator: "\n"))
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func redactSecrets(in text: String) -> String {
        text.replacingOccurrences(
            of: #"sk-[A-Za-z0-9_\-]{6,}"#,
            with: "[redacted]",
            options: .regularExpression
        )
    }

    nonisolated private static let sensitiveMarkers = [
        "api key",
        "apikey",
        "api_key",
        "authorization",
        "bearer ",
        "x-api-key",
        "sk-",
        "sharedsecret",
        "shared secret",
        "hmac",
        "pairing",
        "response json",
        "full debug",
        "debug metadata"
    ]
}

enum ChatConversationTitleSource: String, Codable, Equatable {
    case manual
    case aiGenerated
    case fallback
}

enum ChatAttachmentKind: String, Codable, CaseIterable, Equatable, Hashable {
    case image
    case document
    case audio
    case other
}

enum ChatUnsupportedAttachmentBehavior: String, Codable, Equatable {
    case keepLocalOnlyWithNotice
}

struct ChatAttachment: Codable, Equatable, Identifiable {
    var id: String
    var conversationID: String
    var fileName: String
    var fileType: String
    var mimeType: String?
    var relativePath: String
    var sizeBytes: Int64
    var createdAt: Date
    var kind: ChatAttachmentKind

    init(
        id: String = UUID().uuidString,
        conversationID: String,
        fileName: String,
        fileType: String,
        mimeType: String? = nil,
        relativePath: String,
        sizeBytes: Int64,
        createdAt: Date = Date(),
        kind: ChatAttachmentKind
    ) {
        self.id = id
        self.conversationID = conversationID
        self.fileName = Self.nonEmpty(fileName) ?? "attachment"
        self.fileType = fileType
        self.mimeType = Self.nonEmpty(mimeType)
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
        self.kind = kind
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ChatConversation: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var titleGeneratedAt: Date?
    var titleSource: ChatConversationTitleSource
    var messages: [ChatMessage]
    var activeContextID: String?
    var contextPathDisplay: String?
    var contextItemCount: Int?
    var lastMessagePreview: String?
    var attachmentIDs: [String]
    var attachments: [ChatAttachment]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String = "新对话",
        titleGeneratedAt: Date? = nil,
        titleSource: ChatConversationTitleSource = .fallback,
        messages: [ChatMessage] = [],
        activeContextID: String? = nil,
        contextPathDisplay: String? = nil,
        contextItemCount: Int? = nil,
        lastMessagePreview: String? = nil,
        attachmentIDs: [String] = [],
        attachments: [ChatAttachment] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.titleGeneratedAt = titleGeneratedAt
        self.titleSource = titleSource
        self.messages = messages
        self.activeContextID = activeContextID
        self.contextPathDisplay = Self.nonEmpty(contextPathDisplay)
        self.contextItemCount = contextItemCount
        self.lastMessagePreview = Self.nonEmpty(lastMessagePreview)
        self.attachmentIDs = Self.uniqueIDs(attachmentIDs.isEmpty ? attachments.map(\.id) : attachmentIDs)
        self.attachments = attachments
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case titleGeneratedAt
        case titleSource
        case messages
        case activeContextID
        case contextPathDisplay
        case contextItemCount
        case lastMessagePreview
        case attachmentIDs
        case attachments
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "新对话"
        titleGeneratedAt = try container.decodeIfPresent(Date.self, forKey: .titleGeneratedAt)
        titleSource = try container.decodeIfPresent(ChatConversationTitleSource.self, forKey: .titleSource) ?? .fallback
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        activeContextID = try container.decodeIfPresent(String.self, forKey: .activeContextID)
        contextPathDisplay = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .contextPathDisplay))
        contextItemCount = try container.decodeIfPresent(Int.self, forKey: .contextItemCount)
        lastMessagePreview = Self.nonEmpty(try container.decodeIfPresent(String.self, forKey: .lastMessagePreview))
        attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        let decodedAttachmentIDs = try container.decodeIfPresent([String].self, forKey: .attachmentIDs) ?? []
        attachmentIDs = Self.uniqueIDs(decodedAttachmentIDs.isEmpty ? attachments.map(\.id) : decodedAttachmentIDs)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var isEmpty: Bool {
        messages.isEmpty && attachments.isEmpty
    }

    mutating func attach(_ attachment: ChatAttachment) {
        guard !attachments.contains(where: { $0.id == attachment.id }) else {
            return
        }
        attachments.append(attachment)
        attachmentIDs = Self.uniqueIDs(attachmentIDs + [attachment.id])
    }

    mutating func detachAttachment(id: String) {
        attachments.removeAll { $0.id == id }
        attachmentIDs.removeAll { $0 == id }
        for index in messages.indices {
            messages[index].attachmentIDs.removeAll { $0 == id }
        }
    }

    func attachments(for message: ChatMessage) -> [ChatAttachment] {
        message.attachmentIDs.compactMap { attachmentID in
            attachments.first { $0.id == attachmentID }
        }
    }

    nonisolated private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func uniqueIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for id in ids {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else {
                continue
            }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }
}

struct ChatRequest: Equatable {
    var messages: [ChatMessage]
    var context: ChatContext?
    var attachments: [ChatAttachment]
    var modelName: String?
    var maxTokens: Int
    var temperature: Double

    init(
        messages: [ChatMessage],
        context: ChatContext?,
        attachments: [ChatAttachment] = [],
        modelName: String?,
        maxTokens: Int,
        temperature: Double
    ) {
        self.messages = messages
        self.context = context
        self.attachments = attachments
        self.modelName = modelName
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

struct ChatTitleRequest: Equatable {
    var firstUserMessages: [String]
    var firstAssistantMessage: String?
    var contextPathDisplay: String?

    init(
        firstUserMessages: [String],
        firstAssistantMessage: String? = nil,
        contextPathDisplay: String? = nil
    ) {
        self.firstUserMessages = firstUserMessages
        self.firstAssistantMessage = firstAssistantMessage
        self.contextPathDisplay = contextPathDisplay
    }
}

struct ChatResult: Equatable {
    var message: ChatMessage
    var providerID: String
    var providerName: String
    var modelName: String?
    var finishReason: String?
    var outputWasTruncated: Bool
}
