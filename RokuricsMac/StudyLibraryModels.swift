//
//  StudyLibraryModels.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct StudyFilingPath: Codable, Equatable, Hashable {
    var type: String?
    var subject: String?
    var chapter: String?
    var topic: String?

    init(
        type: String? = nil,
        subject: String? = nil,
        chapter: String? = nil,
        topic: String? = nil
    ) {
        self.type = Self.normalized(type)
        self.subject = Self.normalized(subject)
        self.chapter = Self.normalized(chapter)
        self.topic = Self.normalized(topic)
    }

    var isEmpty: Bool {
        type == nil && subject == nil && chapter == nil && topic == nil
    }

    var displaySummary: String {
        let parts = [type, subject, chapter, topic].compactMap { $0 }
        return parts.isEmpty ? StudyHierarchyRule.uncategorizedValue : parts.joined(separator: " / ")
    }

    func value(for level: String) -> String? {
        switch StudyTag.normalizedNamespace(level) {
        case "type":
            return type
        case "subject":
            return subject
        case "chapter":
            return chapter
        case "topic":
            return topic
        default:
            return nil
        }
    }

    func suggestedTitle(defaultTitle: String) -> String {
        let parts = [subject, chapter, topic].compactMap { $0 }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }

        return type ?? defaultTitle
    }

    static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

struct StudyFilingCandidates: Equatable {
    var types: [String] = []
    var subjects: [String] = []
    var chapters: [String] = []
    var topics: [String] = []

    static let empty = StudyFilingCandidates()

    func values(for level: String) -> [String] {
        switch StudyTag.normalizedNamespace(level) {
        case "type":
            return types
        case "subject":
            return subjects
        case "chapter":
            return chapters
        case "topic":
            return topics
        default:
            return []
        }
    }

    static func collect(from items: [StudyItemMetadata]) -> StudyFilingCandidates {
        StudyFilingCandidates(
            types: sortedUnique(values(for: "type", in: items)),
            subjects: sortedUnique(values(for: "subject", in: items)),
            chapters: sortedUnique(values(for: "chapter", in: items)),
            topics: sortedUnique(values(for: "topic", in: items))
        )
    }

    private static func values(for level: String, in items: [StudyItemMetadata]) -> [String] {
        items.flatMap { item in
            var values: [String] = []
            if let filingValue = item.filingPath.value(for: level) {
                values.append(filingValue)
            }
            values.append(contentsOf: item.tags.filter { $0.namespace == StudyTag.normalizedNamespace(level) }.map(\.displayTitle))
            return values
        }
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            guard let normalized = StudyFilingPath.normalized(value) else {
                continue
            }

            let key = normalized.lowercased()
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            result.append(normalized)
        }

        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

struct StudyTag: Codable, Hashable, Identifiable {
    let id: String
    var namespace: String
    var value: String
    var displayName: String?
    var createdAt: Date?

    init(
        id: String? = nil,
        namespace: String,
        value: String,
        displayName: String? = nil,
        createdAt: Date? = Date()
    ) {
        let normalizedNamespace = Self.normalizedNamespace(namespace)
        let normalizedValue = Self.normalizedValue(value)
        self.namespace = normalizedNamespace
        self.value = normalizedValue
        self.displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
        self.id = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? Self.makeID(namespace: normalizedNamespace, value: normalizedValue)
    }

    var displayTitle: String {
        displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? value
    }

    static func == (left: StudyTag, right: StudyTag) -> Bool {
        left.namespace == right.namespace && left.value.lowercased() == right.value.lowercased()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(namespace)
        hasher.combine(value.lowercased())
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case namespace
        case value
        case displayName
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let namespace = try container.decodeIfPresent(String.self, forKey: .namespace) ?? "custom"
        let value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        let decodedID = try container.decodeIfPresent(String.self, forKey: .id)

        self.init(
            id: decodedID,
            namespace: namespace,
            value: value,
            displayName: displayName,
            createdAt: createdAt
        )
    }

    nonisolated static func normalizedNamespace(_ namespace: String) -> String {
        namespace
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty ?? "custom"
    }

    nonisolated static func normalizedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func makeID(namespace: String, value: String) -> String {
        "\(normalizedNamespace(namespace)):\(normalizedValue(value).lowercased())"
    }
}

typealias StudyItemID = String
typealias StudyFolderID = String

enum StudyItemKind: String, Codable, Equatable {
    case recordingBundle
    case standaloneNote
}

struct StudyItemMetadata: Codable, Equatable, Identifiable {
    var id: String { itemID }

    var itemID: StudyItemID
    var kind: StudyItemKind
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var filing: StudyFilingPath
    var tags: [StudyTag]
    var folderIDs: [StudyFolderID]
    var customProperties: [String: String]
    var recordingID: String?
    var sanitizedRecordingID: String?
    var duration: TimeInterval?
    var audioRelativePath: String?
    var receiveRelativePath: String?
    var transcriptRelativePath: String?
    var transcriptMarkdownRelativePath: String?
    var noteRelativePath: String?
    var transcriptionStatus: String?
    var noteStatus: String?
    var noteSections: [RecordingNoteSectionRecord]?
    var sourceDescription: String?

    init(
        itemID: StudyItemID? = nil,
        kind: StudyItemKind,
        title: String,
        createdAt: Date,
        updatedAt: Date = Date(),
        filing: StudyFilingPath = StudyFilingPath(),
        tags: [StudyTag] = [],
        folderIDs: [StudyFolderID] = [],
        customProperties: [String: String] = [:],
        recordingID: String? = nil,
        sanitizedRecordingID: String? = nil,
        duration: TimeInterval? = nil,
        audioRelativePath: String? = nil,
        receiveRelativePath: String? = nil,
        transcriptRelativePath: String? = nil,
        transcriptMarkdownRelativePath: String? = nil,
        noteRelativePath: String? = nil,
        transcriptionStatus: String? = nil,
        noteStatus: String? = nil,
        noteSections: [RecordingNoteSectionRecord]? = nil,
        sourceDescription: String? = nil
    ) {
        let normalizedRecordingID = Self.normalized(recordingID)
        let resolvedKind = normalizedRecordingID == nil && kind == .recordingBundle ? .standaloneNote : kind
        let resolvedItemID = Self.normalized(itemID)
            ?? normalizedRecordingID.map(Self.recordingBundleItemID(for:))
            ?? "item_note_\(UUID().uuidString.lowercased())"

        self.itemID = resolvedItemID
        self.kind = resolvedKind
        self.title = Self.normalized(title) ?? (resolvedKind == .standaloneNote ? "未命名笔记" : "未命名录音")
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.filing = filing.isEmpty ? StudyFilingPath() : filing
        self.tags = StudyTagList.unique(tags)
        self.folderIDs = Self.uniqueIDs(folderIDs)
        self.customProperties = customProperties
        self.recordingID = normalizedRecordingID
        self.sanitizedRecordingID = Self.normalized(sanitizedRecordingID)
            ?? normalizedRecordingID.map(StudyPathSanitizer.sanitizedPathComponent)
        self.duration = duration
        self.audioRelativePath = Self.normalized(audioRelativePath)
        self.receiveRelativePath = Self.normalized(receiveRelativePath)
        self.transcriptRelativePath = Self.normalized(transcriptRelativePath)
        self.transcriptMarkdownRelativePath = Self.normalized(transcriptMarkdownRelativePath)
        self.noteRelativePath = Self.normalized(noteRelativePath)
        self.transcriptionStatus = Self.normalized(transcriptionStatus)
        self.noteStatus = Self.normalized(noteStatus)
        self.noteSections = noteSections
        self.sourceDescription = Self.normalized(sourceDescription)
    }

    init(
        recordingID: String,
        sanitizedRecordingID: String? = nil,
        title: String,
        createdAt: Date,
        duration: TimeInterval,
        audioRelativePath: String? = nil,
        receiveRelativePath: String? = nil,
        transcriptRelativePath: String? = nil,
        transcriptMarkdownRelativePath: String? = nil,
        noteRelativePath: String? = nil,
        studyFiling: StudyFilingPath? = nil,
        tags: [StudyTag] = [],
        folderIDs: [StudyFolderID] = [],
        customProperties: [String: String] = [:],
        updatedAt: Date = Date(),
        transcriptionStatus: String? = nil,
        noteStatus: String? = nil,
        noteSections: [RecordingNoteSectionRecord]? = nil
    ) {
        let filing = studyFiling?.isEmpty == true ? StudyFilingPath() : (studyFiling ?? StudyFilingPath())
        self.init(
            itemID: Self.recordingBundleItemID(for: recordingID),
            kind: .recordingBundle,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            filing: filing,
            tags: tags,
            folderIDs: folderIDs.isEmpty ? Self.defaultFolderIDs(for: filing) : folderIDs,
            customProperties: customProperties,
            recordingID: recordingID,
            sanitizedRecordingID: sanitizedRecordingID,
            duration: duration,
            audioRelativePath: audioRelativePath,
            receiveRelativePath: receiveRelativePath,
            transcriptRelativePath: transcriptRelativePath,
            transcriptMarkdownRelativePath: transcriptMarkdownRelativePath,
            noteRelativePath: noteRelativePath,
            transcriptionStatus: transcriptionStatus,
            noteStatus: noteStatus,
            noteSections: noteSections
        )
    }

    var hasTranscript: Bool {
        transcriptMarkdownRelativePath != nil || transcriptRelativePath != nil
    }

    var hasNote: Bool {
        noteRelativePath != nil
    }

    var tagsSummary: String {
        var parts: [String] = []
        if !filing.isEmpty {
            parts.append(filing.displaySummary)
        }
        parts.append(contentsOf: tags.map { "\($0.namespace): \($0.displayTitle)" })

        return parts.isEmpty ? "无标签" : parts.joined(separator: " · ")
    }

    var filingPath: StudyFilingPath {
        filing
    }

    var studyFiling: StudyFilingPath? {
        get {
            filing.isEmpty ? nil : filing
        }
        set {
            filing = newValue?.isEmpty == true ? StudyFilingPath() : (newValue ?? StudyFilingPath())
            folderIDs = Self.defaultFolderIDs(for: filing)
        }
    }

    var durationForDisplay: TimeInterval {
        duration ?? 0
    }

    func mergedWithCurrentInboxItem(_ item: MacRecordingInboxItem) -> StudyItemMetadata {
        let resolvedFiling = filing.isEmpty ? (item.studyFiling ?? StudyFilingPath()) : filing
        let resolvedFolderIDs = folderIDs.isEmpty ? Self.defaultFolderIDs(for: resolvedFiling) : folderIDs
        return StudyItemMetadata(
            itemID: itemID,
            kind: .recordingBundle,
            title: item.title,
            createdAt: item.receivedAt,
            updatedAt: updatedAt,
            filing: resolvedFiling,
            tags: tags,
            folderIDs: resolvedFolderIDs,
            customProperties: customProperties,
            recordingID: item.id,
            sanitizedRecordingID: sanitizedRecordingID,
            duration: item.duration,
            audioRelativePath: item.audioRelativePath ?? audioRelativePath,
            receiveRelativePath: item.receiveRelativePath ?? receiveRelativePath,
            transcriptRelativePath: item.transcriptRelativePath,
            transcriptMarkdownRelativePath: item.transcriptMarkdownRelativePath,
            noteRelativePath: item.noteRelativePath,
            transcriptionStatus: item.transcriptionStatus,
            noteStatus: item.noteStatus,
            noteSections: noteSections,
            sourceDescription: sourceDescription
        )
    }

    func asInboxItem() -> MacRecordingInboxItem {
        MacRecordingInboxItem(
            id: recordingID ?? itemID,
            title: title,
            receivedAt: createdAt,
            duration: durationForDisplay,
            fileSize: 0,
            sourceDeviceName: "iPhone",
            transcriptionStatus: transcriptionStatus ?? (hasTranscript ? "transcribed" : "notStarted"),
            noteStatus: noteStatus ?? (hasNote ? "generated" : "notGenerated"),
            receiveStatus: "received",
            hasAudio: kind == .recordingBundle && audioRelativePath != nil,
            audioRelativePath: audioRelativePath,
            receiveRelativePath: receiveRelativePath,
            transcriptRelativePath: transcriptRelativePath,
            transcriptMarkdownRelativePath: transcriptMarkdownRelativePath,
            transcriptionError: nil,
            studyFiling: studyFiling,
            noteRelativePath: noteRelativePath,
            noteError: nil
        )
    }

    static func defaultMetadata(for item: MacRecordingInboxItem) -> StudyItemMetadata {
        StudyItemMetadata(
            recordingID: item.id,
            sanitizedRecordingID: StudyPathSanitizer.sanitizedPathComponent(item.id),
            title: item.title,
            createdAt: item.receivedAt,
            duration: item.duration,
            audioRelativePath: item.audioRelativePath,
            receiveRelativePath: item.receiveRelativePath,
            transcriptRelativePath: item.transcriptRelativePath,
            transcriptMarkdownRelativePath: item.transcriptMarkdownRelativePath,
            noteRelativePath: item.noteRelativePath,
            studyFiling: item.studyFiling,
            tags: [],
            customProperties: [:],
            updatedAt: Date(),
            transcriptionStatus: item.transcriptionStatus,
            noteStatus: item.noteStatus
        )
    }

    private enum CodingKeys: String, CodingKey {
        case itemID
        case kind
        case title
        case createdAt
        case updatedAt
        case filing
        case tags
        case folderIDs
        case customProperties
        case recordingID
        case sanitizedRecordingID
        case duration
        case audioRelativePath
        case receiveRelativePath
        case transcriptRelativePath
        case transcriptMarkdownRelativePath
        case noteRelativePath
        case studyFiling
        case transcriptionStatus
        case noteStatus
        case noteSections
        case sourceDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let recordingID = try container.decodeIfPresent(String.self, forKey: .recordingID)
        let itemID = try container.decodeIfPresent(String.self, forKey: .itemID)
            ?? recordingID.map(Self.recordingBundleItemID(for:))
        let kind = try container.decodeIfPresent(StudyItemKind.self, forKey: .kind)
            ?? (recordingID == nil ? .standaloneNote : .recordingBundle)
        let title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名录音"
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        let filing = try container.decodeIfPresent(StudyFilingPath.self, forKey: .filing)
            ?? container.decodeIfPresent(StudyFilingPath.self, forKey: .studyFiling)
            ?? StudyFilingPath()
        let folderIDs = try container.decodeIfPresent([String].self, forKey: .folderIDs)
            ?? (filing.isEmpty ? [] : Self.defaultFolderIDs(for: filing))

        self.init(
            itemID: itemID,
            kind: kind,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            filing: filing,
            tags: try container.decodeIfPresent([StudyTag].self, forKey: .tags) ?? [],
            folderIDs: folderIDs,
            customProperties: try container.decodeIfPresent([String: String].self, forKey: .customProperties) ?? [:],
            recordingID: recordingID,
            sanitizedRecordingID: try container.decodeIfPresent(String.self, forKey: .sanitizedRecordingID),
            duration: try container.decodeIfPresent(TimeInterval.self, forKey: .duration),
            audioRelativePath: try container.decodeIfPresent(String.self, forKey: .audioRelativePath),
            receiveRelativePath: try container.decodeIfPresent(String.self, forKey: .receiveRelativePath),
            transcriptRelativePath: try container.decodeIfPresent(String.self, forKey: .transcriptRelativePath),
            transcriptMarkdownRelativePath: try container.decodeIfPresent(String.self, forKey: .transcriptMarkdownRelativePath),
            noteRelativePath: try container.decodeIfPresent(String.self, forKey: .noteRelativePath),
            transcriptionStatus: try container.decodeIfPresent(String.self, forKey: .transcriptionStatus),
            noteStatus: try container.decodeIfPresent(String.self, forKey: .noteStatus),
            noteSections: try container.decodeIfPresent([RecordingNoteSectionRecord].self, forKey: .noteSections),
            sourceDescription: try container.decodeIfPresent(String.self, forKey: .sourceDescription)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(itemID, forKey: .itemID)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(filing, forKey: .filing)
        try container.encode(tags, forKey: .tags)
        try container.encode(folderIDs, forKey: .folderIDs)
        try container.encode(customProperties, forKey: .customProperties)
        try container.encodeIfPresent(recordingID, forKey: .recordingID)
        try container.encodeIfPresent(sanitizedRecordingID, forKey: .sanitizedRecordingID)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(audioRelativePath, forKey: .audioRelativePath)
        try container.encodeIfPresent(receiveRelativePath, forKey: .receiveRelativePath)
        try container.encodeIfPresent(transcriptRelativePath, forKey: .transcriptRelativePath)
        try container.encodeIfPresent(transcriptMarkdownRelativePath, forKey: .transcriptMarkdownRelativePath)
        try container.encodeIfPresent(noteRelativePath, forKey: .noteRelativePath)
        try container.encodeIfPresent(transcriptionStatus, forKey: .transcriptionStatus)
        try container.encodeIfPresent(noteStatus, forKey: .noteStatus)
        try container.encodeIfPresent(noteSections, forKey: .noteSections)
        try container.encodeIfPresent(sourceDescription, forKey: .sourceDescription)
    }

    static func recordingBundleItemID(for recordingID: String) -> StudyItemID {
        "item_recording_\(StudyPathSanitizer.sanitizedPathComponent(recordingID))"
    }

    static func defaultFolderIDs(for filing: StudyFilingPath) -> [StudyFolderID] {
        let path = effectiveFolderPath(for: filing)
        guard let deepestLevel = StudyFolderMetadata.deepestLevel(in: path) else {
            return []
        }

        return [StudyFolderMetadata.folderID(for: deepestLevel, path: path)]
    }

    static func effectiveFolderPath(for filing: StudyFilingPath) -> StudyFilingPath {
        if filing.isEmpty {
            return StudyFilingPath(type: StudyHierarchyRule.uncategorizedValue)
        }

        let hasTopic = filing.topic != nil
        let hasChapter = filing.chapter != nil || hasTopic
        let hasSubject = filing.subject != nil || hasChapter
        return StudyFilingPath(
            type: filing.type ?? StudyHierarchyRule.uncategorizedValue,
            subject: hasSubject ? (filing.subject ?? StudyHierarchyRule.missingValue) : nil,
            chapter: hasChapter ? (filing.chapter ?? StudyHierarchyRule.missingValue) : nil,
            topic: filing.topic
        )
    }

    static func uniqueIDs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            guard let normalized = normalized(value),
                  !seen.contains(normalized) else {
                continue
            }

            seen.insert(normalized)
            result.append(normalized)
        }

        return result
    }

    static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

enum StudyFolderLevel: String, Codable, Equatable, CaseIterable {
    case type
    case subject
    case chapter
    case topic
    case custom

    var next: StudyFolderLevel? {
        switch self {
        case .type:
            return .subject
        case .subject:
            return .chapter
        case .chapter:
            return .topic
        case .topic, .custom:
            return nil
        }
    }

    var title: String {
        switch self {
        case .type:
            return "门类"
        case .subject:
            return "课程"
        case .chapter:
            return "章节"
        case .topic:
            return "主题"
        case .custom:
            return "文件夹"
        }
    }
}

enum StudyFolderColorToken: String, Codable, Equatable, CaseIterable, Identifiable {
    case `default`
    case red
    case orange
    case yellow
    case green
    case mint
    case teal
    case cyan
    case blue
    case indigo
    case purple
    case gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default:
            return "默认"
        case .orange:
            return "橙"
        case .yellow:
            return "黄"
        case .green:
            return "绿"
        case .mint:
            return "薄荷"
        case .teal:
            return "青绿"
        case .cyan:
            return "青"
        case .blue:
            return "蓝"
        case .indigo:
            return "靛"
        case .red:
            return "红"
        case .purple:
            return "紫"
        case .gray:
            return "灰"
        }
    }

    static var finderPalette: [StudyFolderColorToken] {
        [.default, .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .gray]
    }
}

struct StudyFolderMetadata: Codable, Equatable, Identifiable {
    var id: String { folderID }

    var folderID: StudyFolderID
    var name: String
    var level: StudyFolderLevel
    var path: StudyFilingPath
    var parentFolderID: StudyFolderID?
    var childFolderIDs: [StudyFolderID]
    var itemIDs: [StudyItemID]
    var createdAt: Date
    var updatedAt: Date
    var colorToken: StudyFolderColorToken?
    var isTrashed: Bool
    var trashedAt: Date?
    var customProperties: [String: String]

    private enum CodingKeys: String, CodingKey {
        case folderID
        case name
        case level
        case path
        case parentFolderID
        case childFolderIDs
        case itemIDs
        case createdAt
        case updatedAt
        case colorToken
        case isTrashed
        case trashedAt
        case customProperties
    }

    init(
        folderID: StudyFolderID? = nil,
        name: String,
        level: StudyFolderLevel,
        path: StudyFilingPath,
        parentFolderID: StudyFolderID? = nil,
        childFolderIDs: [StudyFolderID] = [],
        itemIDs: [StudyItemID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        colorToken: StudyFolderColorToken? = nil,
        isTrashed: Bool = false,
        trashedAt: Date? = nil,
        customProperties: [String: String] = [:]
    ) {
        self.name = StudyItemMetadata.normalized(name) ?? StudyHierarchyRule.missingValue
        self.level = level
        self.path = path
        self.folderID = StudyItemMetadata.normalized(folderID) ?? Self.folderID(for: level, path: path)
        self.parentFolderID = StudyItemMetadata.normalized(parentFolderID)
        self.childFolderIDs = StudyItemMetadata.uniqueIDs(childFolderIDs)
        self.itemIDs = StudyItemMetadata.uniqueIDs(itemIDs)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.colorToken = colorToken
        self.isTrashed = isTrashed
        self.trashedAt = trashedAt
        self.customProperties = customProperties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let level = try container.decode(StudyFolderLevel.self, forKey: .level)
        let path = try container.decode(StudyFilingPath.self, forKey: .path)

        self.name = StudyItemMetadata.normalized(name) ?? StudyHierarchyRule.missingValue
        self.level = level
        self.path = path
        self.folderID = StudyItemMetadata.normalized(try container.decodeIfPresent(String.self, forKey: .folderID))
            ?? Self.folderID(for: level, path: path)
        self.parentFolderID = StudyItemMetadata.normalized(try container.decodeIfPresent(String.self, forKey: .parentFolderID))
        self.childFolderIDs = StudyItemMetadata.uniqueIDs(try container.decodeIfPresent([StudyFolderID].self, forKey: .childFolderIDs) ?? [])
        self.itemIDs = StudyItemMetadata.uniqueIDs(try container.decodeIfPresent([StudyItemID].self, forKey: .itemIDs) ?? [])
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? self.createdAt
        self.colorToken = try container.decodeIfPresent(StudyFolderColorToken.self, forKey: .colorToken)
        self.isTrashed = try container.decodeIfPresent(Bool.self, forKey: .isTrashed) ?? false
        self.trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
        self.customProperties = try container.decodeIfPresent([String: String].self, forKey: .customProperties) ?? [:]
    }

    var pathComponents: [String] {
        Self.pathComponents(for: path, through: level)
    }

    static func folderID(for level: StudyFolderLevel, path: StudyFilingPath) -> StudyFolderID {
        let components = pathComponents(for: path, through: level)
        let raw = ([level.rawValue] + components).joined(separator: "_")
        return "folder_\(StudyPathSanitizer.sanitizedPathComponent(raw))"
    }

    static func pathComponents(for path: StudyFilingPath, through level: StudyFolderLevel) -> [String] {
        let values: [(StudyFolderLevel, String?)] = [
            (.type, path.type),
            (.subject, path.subject),
            (.chapter, path.chapter),
            (.topic, path.topic)
        ]

        var result: [String] = []
        for (candidateLevel, value) in values {
            guard let value = StudyFilingPath.normalized(value) else {
                break
            }

            result.append(value)
            if candidateLevel == level {
                break
            }
        }

        return result
    }

    static func deepestLevel(in path: StudyFilingPath) -> StudyFolderLevel? {
        if path.topic != nil {
            return .topic
        }
        if path.chapter != nil {
            return .chapter
        }
        if path.subject != nil {
            return .subject
        }
        if path.type != nil {
            return .type
        }

        return nil
    }

    static func level(forDepth depth: Int) -> StudyFolderLevel? {
        switch depth {
        case 0:
            return .type
        case 1:
            return .subject
        case 2:
            return .chapter
        case 3:
            return .topic
        default:
            return nil
        }
    }

    static func filingPath(for components: [String]) -> StudyFilingPath {
        StudyFilingPath(
            type: components[safe: 0],
            subject: components[safe: 1],
            chapter: components[safe: 2],
            topic: components[safe: 3]
        )
    }
}

struct StudyHierarchyRule: Codable, Equatable, Identifiable {
    let id: String
    var name: String
    var levels: [String]

    init(id: String = "course-view", name: String, levels: [String]) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "学习视图"
        self.levels = levels
            .map(StudyTag.normalizedNamespace)
            .filter { !$0.isEmpty }
    }

    static let defaultCourseView = StudyHierarchyRule(
        id: "course-view",
        name: "课程视图",
        levels: ["type", "subject", "chapter", "topic"]
    )

    static let uncategorizedValue = "未分类"
    static let missingValue = "未填写"
}

struct VirtualStudyNode: Identifiable, Equatable {
    let id: String
    let levelKey: String
    let levelValue: String
    let children: [VirtualStudyNode]
    let items: [StudyItemMetadata]

    var isUncategorized: Bool {
        levelValue == StudyHierarchyRule.uncategorizedValue
    }
}

struct StudyBrowsePath: Equatable, Hashable {
    var components: [String] = []

    var isRoot: Bool {
        components.isEmpty
    }

    var depth: Int {
        components.count
    }

    var storageKey: String {
        components.joined(separator: "\u{1F}")
    }

    var parent: StudyBrowsePath {
        guard !components.isEmpty else {
            return self
        }

        return StudyBrowsePath(components: Array(components.dropLast()))
    }

    var isUncategorizedTypeSelection: Bool {
        components.count == 1 && components.first == StudyHierarchyRule.uncategorizedValue
    }

    func appending(_ value: String) -> StudyBrowsePath {
        var updated = components
        updated.append(value)
        return StudyBrowsePath(components: updated)
    }

    func truncated(to depth: Int) -> StudyBrowsePath {
        StudyBrowsePath(components: Array(components.prefix(max(0, depth))))
    }
}

struct StudyBrowseFolder: Identifiable, Equatable {
    let id: String
    let folderID: StudyFolderID?
    let levelKey: String
    let title: String
    let itemCount: Int
    let path: StudyBrowsePath
    let colorToken: StudyFolderColorToken?

    var isFallback: Bool {
        title == StudyHierarchyRule.uncategorizedValue || title == StudyHierarchyRule.missingValue
    }
}

struct StudyBrowseContent: Equatable {
    let path: StudyBrowsePath
    let folders: [StudyBrowseFolder]
    let items: [StudyItemMetadata]

    var showsRecordings: Bool {
        !items.isEmpty
    }
}

enum StudyLibraryBrowser {
    static let levelKeys = ["type", "subject", "chapter", "topic"]

    static func content(
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata] = [],
        path: StudyBrowsePath
    ) -> StudyBrowseContent {
        let matchingItems = items.filter { itemMatches($0, path: path) }

        if path.depth >= levelKeys.count || path.isUncategorizedTypeSelection {
            return StudyBrowseContent(
                path: path,
                folders: [],
                items: sortedItems(matchingItems)
            )
        }

        let nextLevelKey = levelKeys[path.depth]
        let nextLevel = StudyFolderMetadata.level(forDepth: path.depth)
        let grouped = Dictionary(grouping: matchingItems) { item in
            displayValue(for: item, levelKey: nextLevelKey)
        }
        var browseFoldersByPath: [String: StudyBrowseFolder] = [:]

        for (title, groupedItems) in grouped {
            let folderPath = path.appending(title)
            browseFoldersByPath[folderPath.storageKey] = StudyBrowseFolder(
                id: "\(path.components.joined(separator: "/"))/\(nextLevelKey)=\(title)",
                folderID: nil,
                levelKey: nextLevelKey,
                title: title,
                itemCount: groupedItems.count,
                path: folderPath,
                colorToken: nil
            )
        }

        if let nextLevel {
            for folder in folders where folderMatchesParent(folder, parentPath: path, nextLevel: nextLevel) {
                guard !folder.isTrashed else {
                    continue
                }

                let folderPath = StudyBrowsePath(components: folder.pathComponents)
                let itemCount = items.filter { itemMatches($0, path: folderPath) }.count
                browseFoldersByPath[folderPath.storageKey] = StudyBrowseFolder(
                    id: folder.folderID,
                    folderID: folder.folderID,
                    levelKey: folder.level.rawValue,
                    title: folder.name,
                    itemCount: itemCount,
                    path: folderPath,
                    colorToken: folder.colorToken
                )
            }
        }

        return StudyBrowseContent(
            path: path,
            folders: browseFoldersByPath.values.sorted { folderSort($0, $1) },
            items: []
        )
    }

    static func breadcrumbs(for path: StudyBrowsePath) -> [(title: String, path: StudyBrowsePath)] {
        var result: [(String, StudyBrowsePath)] = [("学习库", StudyBrowsePath())]

        for index in path.components.indices {
            let componentPath = path.truncated(to: index + 1)
            result.append((path.components[index], componentPath))
        }

        return result
    }

    static func levelTitle(for path: StudyBrowsePath) -> String {
        if path.depth >= levelKeys.count || path.isUncategorizedTypeSelection {
            return "录音"
        }

        switch levelKeys[path.depth] {
        case "type":
            return "门类"
        case "subject":
            return "课程"
        case "chapter":
            return "章节"
        case "topic":
            return "主题"
        default:
            return "文件夹"
        }
    }

    static func itemMatches(_ item: StudyItemMetadata, path: StudyBrowsePath) -> Bool {
        guard path.depth <= levelKeys.count else {
            return false
        }

        for (index, component) in path.components.enumerated() {
            guard displayValue(for: item, levelKey: levelKeys[index]) == component else {
                return false
            }
        }

        return true
    }

    private static func folderMatchesParent(
        _ folder: StudyFolderMetadata,
        parentPath: StudyBrowsePath,
        nextLevel: StudyFolderLevel
    ) -> Bool {
        guard folder.level == nextLevel else {
            return false
        }

        let components = folder.pathComponents
        guard components.count == parentPath.depth + 1 else {
            return false
        }

        return Array(components.prefix(parentPath.depth)) == parentPath.components
    }

    private static func displayValue(for item: StudyItemMetadata, levelKey: String) -> String {
        if let value = item.filingPath.value(for: levelKey), !value.isEmpty {
            return value
        }

        return StudyTag.normalizedNamespace(levelKey) == "type"
            ? StudyHierarchyRule.uncategorizedValue
            : StudyHierarchyRule.missingValue
    }

    private static func folderSort(_ left: StudyBrowseFolder, _ right: StudyBrowseFolder) -> Bool {
        if left.isFallback != right.isFallback {
            return left.isFallback
        }

        return left.title.localizedStandardCompare(right.title) == .orderedAscending
    }

    private static func sortedItems(_ items: [StudyItemMetadata]) -> [StudyItemMetadata] {
        items.sorted { left, right in
            if left.createdAt == right.createdAt {
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }

            return left.createdAt > right.createdAt
        }
    }
}

enum StudyTagList {
    nonisolated static func unique(_ tags: [StudyTag]) -> [StudyTag] {
        var seen: Set<String> = []
        var result: [StudyTag] = []

        for tag in tags {
            let value = StudyTag.normalizedValue(tag.value)
            guard !value.isEmpty else {
                continue
            }

            let normalizedTag = StudyTag(
                id: tag.id,
                namespace: tag.namespace,
                value: value,
                displayName: tag.displayName,
                createdAt: tag.createdAt
            )
            let key = "\(normalizedTag.namespace)\u{1F}\(normalizedTag.value.lowercased())"
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            result.append(normalizedTag)
        }

        return result
    }

    nonisolated static func tags(
        type: String = "",
        subject: String,
        chapter: String,
        topic: String,
        freeText: String
    ) -> [StudyTag] {
        var tags: [StudyTag] = []
        appendQuickTag(namespace: "type", value: type, to: &tags)
        appendQuickTag(namespace: "subject", value: subject, to: &tags)
        appendQuickTag(namespace: "chapter", value: chapter, to: &tags)
        appendQuickTag(namespace: "topic", value: topic, to: &tags)
        tags.append(contentsOf: parseFreeTags(freeText))
        return unique(tags)
    }

    nonisolated static func firstValue(in tags: [StudyTag], namespace: String) -> String {
        let normalizedNamespace = StudyTag.normalizedNamespace(namespace)
        return tags.first { $0.namespace == normalizedNamespace }?.value ?? ""
    }

    nonisolated static func freeTagsText(from tags: [StudyTag]) -> String {
        let quickNamespaces: Set<String> = ["type", "subject", "chapter", "topic"]
        return tags
            .filter { !quickNamespaces.contains($0.namespace) }
            .map { tag in
                tag.namespace == "custom" ? tag.value : "\(tag.namespace):\(tag.value)"
            }
            .joined(separator: ", ")
    }

    nonisolated private static func appendQuickTag(namespace: String, value: String, to tags: inout [StudyTag]) {
        let value = StudyTag.normalizedValue(value)
        guard !value.isEmpty else {
            return
        }

        tags.append(StudyTag(namespace: namespace, value: value))
    }

    nonisolated private static func parseFreeTags(_ text: String) -> [StudyTag] {
        text.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { token in
                let separator = token.firstIndex(of: ":") ?? token.firstIndex(of: "=")
                guard let separator else {
                    return StudyTag(namespace: "custom", value: token)
                }

                let namespace = String(token[..<separator])
                let value = String(token[token.index(after: separator)...])
                return StudyTag(namespace: namespace, value: value)
            }
    }
}

struct StudyFilingSelectionDraft: Equatable {
    var type: String = ""
    var subject: String = ""
    var chapter: String = ""
    var topic: String = ""

    init(path: StudyFilingPath = StudyFilingPath()) {
        type = path.type ?? ""
        subject = path.subject ?? ""
        chapter = path.chapter ?? ""
        topic = path.topic ?? ""
    }

    var filingPath: StudyFilingPath {
        StudyFilingPath(
            type: type,
            subject: subject,
            chapter: chapter,
            topic: topic
        )
    }

    func value(for level: StudyFolderLevel) -> String {
        switch level {
        case .type:
            return type
        case .subject:
            return subject
        case .chapter:
            return chapter
        case .topic:
            return topic
        case .custom:
            return ""
        }
    }

    mutating func select(_ level: StudyFolderLevel, value: String) {
        let normalizedValue = StudyFilingPath.normalized(value) ?? ""
        switch level {
        case .type:
            type = normalizedValue
            subject = ""
            chapter = ""
            topic = ""
        case .subject:
            subject = normalizedValue
            chapter = ""
            topic = ""
        case .chapter:
            chapter = normalizedValue
            topic = ""
        case .topic:
            topic = normalizedValue
        case .custom:
            break
        }
    }

    func parentBrowsePath(for level: StudyFolderLevel) -> StudyBrowsePath? {
        switch level {
        case .type:
            return StudyBrowsePath()
        case .subject:
            guard !type.isEmpty else {
                return nil
            }
            return StudyBrowsePath(components: [type])
        case .chapter:
            guard !type.isEmpty, !subject.isEmpty else {
                return nil
            }
            return StudyBrowsePath(components: [type, subject])
        case .topic:
            guard !type.isEmpty, !subject.isEmpty, !chapter.isEmpty else {
                return nil
            }
            return StudyBrowsePath(components: [type, subject, chapter])
        case .custom:
            return nil
        }
    }
}

enum StudyFilingSelectionFlow {
    static func nextLevelAfterCommit(_ level: StudyFolderLevel) -> StudyFolderLevel? {
        switch level {
        case .type:
            return .subject
        case .subject:
            return .chapter
        case .chapter:
            return .topic
        case .topic, .custom:
            return nil
        }
    }
}

enum StudyFilingCandidateResolver {
    static func candidates(
        for level: StudyFolderLevel,
        current filing: StudyFilingPath,
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata]
    ) -> [String] {
        guard level != .custom else {
            return []
        }

        var values: [String] = []
        for item in items where matchesAncestors(item.filingPath, for: level, current: filing) {
            if level == .type {
                values.append(item.filingPath.type ?? StudyHierarchyRule.uncategorizedValue)
            } else if let value = item.filingPath.value(for: level.rawValue) {
                values.append(value)
            }
        }

        for folder in folders where folder.level == level && matchesAncestors(folder.path, for: level, current: filing) {
            values.append(folder.name)
        }

        if level == .type {
            values.append(StudyHierarchyRule.uncategorizedValue)
        }

        return sortedUnique(values)
    }

    private static func matchesAncestors(
        _ candidate: StudyFilingPath,
        for level: StudyFolderLevel,
        current: StudyFilingPath
    ) -> Bool {
        switch level {
        case .type:
            return true
        case .subject:
            return candidate.type == current.type
        case .chapter:
            return candidate.type == current.type && candidate.subject == current.subject
        case .topic:
            return candidate.type == current.type && candidate.subject == current.subject && candidate.chapter == current.chapter
        case .custom:
            return false
        }
    }

    private static func sortedUnique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in values {
            guard let normalized = StudyFilingPath.normalized(value) else {
                continue
            }

            let key = normalized.lowercased()
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            result.append(normalized)
        }

        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

enum VirtualStudyTreeBuilder {
    nonisolated static func build(items: [StudyItemMetadata], rule: StudyHierarchyRule) -> [VirtualStudyNode] {
        build(items: items, folders: [], rule: rule)
    }

    nonisolated static func build(
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata],
        rule: StudyHierarchyRule
    ) -> [VirtualStudyNode] {
        let root = MutableStudyNode(levelKey: "root", levelValue: rule.name)

        for folder in folders {
            insert(folder: folder, rule: rule, into: root)
        }

        for item in items {
            let levelValues = valuesByLevel(for: item, rule: rule)
            insert(item: item, rule: rule, levelValues: levelValues, depth: 0, into: root)
        }

        return root.children
            .map(makeNode)
            .sorted(by: nodeSort)
    }

    nonisolated private static func insert(
        folder: StudyFolderMetadata,
        rule: StudyHierarchyRule,
        into root: MutableStudyNode
    ) {
        let components = folder.pathComponents
        guard !components.isEmpty else {
            return
        }

        var current = root
        for (index, value) in components.enumerated() {
            guard index < rule.levels.count else {
                return
            }

            let levelKey = rule.levels[index]
            let childID = "\(current.id)/\(levelKey)=\(value)"
            current = current.child(id: childID, levelKey: levelKey, levelValue: value)
        }
    }

    nonisolated private static func valuesByLevel(for item: StudyItemMetadata, rule: StudyHierarchyRule) -> [[String]] {
        rule.levels.map { level in
            if let filingValue = item.filingPath.value(for: level), !filingValue.isEmpty {
                return [filingValue]
            }

            let values = item.tags
                .filter { $0.namespace == level }
                .map(\.displayTitle)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .uniqueStable()

            return values.isEmpty ? [fallbackValue(for: level)] : values
        }
    }

    nonisolated private static func fallbackValue(for level: String) -> String {
        StudyTag.normalizedNamespace(level) == "type"
            ? StudyHierarchyRule.uncategorizedValue
            : StudyHierarchyRule.missingValue
    }

    nonisolated private static func insert(
        item: StudyItemMetadata,
        rule: StudyHierarchyRule,
        levelValues: [[String]],
        depth: Int,
        into node: MutableStudyNode
    ) {
        guard depth < rule.levels.count else {
            node.itemsByID[item.itemID] = item
            return
        }

        let levelKey = rule.levels[depth]
        for value in levelValues[depth] {
            let childID = "\(node.id)/\(levelKey)=\(value)"
            let child = node.child(id: childID, levelKey: levelKey, levelValue: value)
            insert(item: item, rule: rule, levelValues: levelValues, depth: depth + 1, into: child)
        }
    }

    nonisolated private static func makeNode(_ mutable: MutableStudyNode) -> VirtualStudyNode {
        VirtualStudyNode(
            id: mutable.id,
            levelKey: mutable.levelKey,
            levelValue: mutable.levelValue,
            children: mutable.children.map(makeNode).sorted(by: nodeSort),
            items: mutable.itemsByID.values.sorted { left, right in
                if left.createdAt == right.createdAt {
                    return left.title.localizedStandardCompare(right.title) == .orderedAscending
                }
                return left.createdAt > right.createdAt
            }
        )
    }

    nonisolated private static func nodeSort(_ left: VirtualStudyNode, _ right: VirtualStudyNode) -> Bool {
        if left.isUncategorized != right.isUncategorized {
            return left.isUncategorized
        }

        return left.levelValue.localizedStandardCompare(right.levelValue) == .orderedAscending
    }
}

private final class MutableStudyNode {
    let id: String
    let levelKey: String
    let levelValue: String
    var itemsByID: [String: StudyItemMetadata] = [:]
    private var childrenByID: [String: MutableStudyNode] = [:]

    init(id: String? = nil, levelKey: String, levelValue: String) {
        self.levelKey = levelKey
        self.levelValue = levelValue
        self.id = id ?? "\(levelKey)=\(levelValue)"
    }

    var children: [MutableStudyNode] {
        Array(childrenByID.values)
    }

    func child(id: String, levelKey: String, levelValue: String) -> MutableStudyNode {
        if let child = childrenByID[id] {
            return child
        }

        let child = MutableStudyNode(id: id, levelKey: levelKey, levelValue: levelValue)
        childrenByID[id] = child
        return child
    }
}

enum StudyPathSanitizer {
    nonisolated static func sanitizedPathComponent(_ value: String) -> String {
        sanitizedFileName(value)
            .replacingOccurrences(of: ".", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
            .nilIfEmpty ?? "recording"
    }

    nonisolated private static func sanitizedFileName(_ value: String?) -> String {
        let rawName = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lastPathComponent = ((rawName.isEmpty ? "recording" : rawName) as NSString).lastPathComponent
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return lastPathComponent.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array where Element == String {
    nonisolated func uniqueStable() -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in self {
            let key = value.lowercased()
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            result.append(value)
        }

        return result
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
