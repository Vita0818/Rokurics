//
//  ChatModels.swift
//  RokuricsMac
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
