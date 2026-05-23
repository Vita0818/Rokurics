//
//  StudyFilingModels.swift
//  Rokurics
//
//  Created by Codex on 2026/5/18.
//

import Foundation

struct StudyFilingPath: Codable, Equatable, Hashable {
    var type: String?
    var subject: String?
    var chapter: String?
    var topic: String?

    nonisolated init(
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

    nonisolated var isEmpty: Bool {
        type == nil && subject == nil && chapter == nil && topic == nil
    }

    nonisolated var displaySummary: String {
        let parts = [type, subject, chapter, topic].compactMap { $0 }
        return parts.isEmpty ? StudyFilingPath.uncategorizedTitle : parts.joined(separator: " / ")
    }

    nonisolated func value(for level: StudyFilingLevel) -> String? {
        switch level {
        case .type:
            return type
        case .subject:
            return subject
        case .chapter:
            return chapter
        case .topic:
            return topic
        }
    }

    nonisolated func value(for levelKey: String) -> String? {
        switch StudyTag.normalizedNamespace(levelKey) {
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

    nonisolated func value(for level: StudyFolderLevel) -> String? {
        value(for: level.rawValue)
    }

    nonisolated func suggestedTitle(defaultTitle: String) -> String {
        let parts = [subject, chapter, topic].compactMap { $0 }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }

        return type ?? defaultTitle
    }

    nonisolated static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    nonisolated static let uncategorizedTitle = "未分类"
    nonisolated static let missingTitle = "未填写"
}

enum StudyFilingLevel: String, CaseIterable, Identifiable {
    case type
    case subject
    case chapter
    case topic

    var id: String { rawValue }

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
        }
    }
}

struct StudyFilingCandidates: Equatable {
    var types: [String] = []
    var subjects: [String] = []
    var chapters: [String] = []
    var topics: [String] = []

    static let empty = StudyFilingCandidates()

    func values(for level: StudyFilingLevel) -> [String] {
        switch level {
        case .type:
            return types
        case .subject:
            return subjects
        case .chapter:
            return chapters
        case .topic:
            return topics
        }
    }

    func values(for level: StudyFolderLevel) -> [String] {
        switch level {
        case .type:
            return types
        case .subject:
            return subjects
        case .chapter:
            return chapters
        case .topic:
            return topics
        case .custom:
            return []
        }
    }

    static func collect(from recordings: [RecordingMetadata]) -> StudyFilingCandidates {
        StudyFilingCandidates(
            types: sortedUnique(recordings.compactMap(\.studyFiling?.type)),
            subjects: sortedUnique(recordings.compactMap(\.studyFiling?.subject)),
            chapters: sortedUnique(recordings.compactMap(\.studyFiling?.chapter)),
            topics: sortedUnique(recordings.compactMap(\.studyFiling?.topic))
        )
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
            let normalized = StudyFilingPath.normalized(value)
            guard let normalized else {
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

struct RecordingStudyNode: Identifiable, Equatable {
    let id: String
    let level: StudyFilingLevel
    let title: String
    let children: [RecordingStudyNode]
    let recordings: [RecordingMetadata]

    var isFallback: Bool {
        title == StudyFilingPath.uncategorizedTitle || title == StudyFilingPath.missingTitle
    }
}

struct RecordingStudyBrowsePath: Equatable, Hashable {
    var components: [String] = []

    var isRoot: Bool {
        components.isEmpty
    }

    var depth: Int {
        components.count
    }

    var parent: RecordingStudyBrowsePath {
        guard !components.isEmpty else {
            return self
        }

        return RecordingStudyBrowsePath(components: Array(components.dropLast()))
    }

    var isUncategorizedTypeSelection: Bool {
        components.count == 1 && components.first == StudyFilingPath.uncategorizedTitle
    }

    func appending(_ value: String) -> RecordingStudyBrowsePath {
        var updated = components
        updated.append(value)
        return RecordingStudyBrowsePath(components: updated)
    }

    func truncated(to depth: Int) -> RecordingStudyBrowsePath {
        RecordingStudyBrowsePath(components: Array(components.prefix(max(0, depth))))
    }
}

struct RecordingStudyFolder: Identifiable, Equatable {
    let id: String
    let level: StudyFilingLevel
    let title: String
    let itemCount: Int
    let path: RecordingStudyBrowsePath

    var isFallback: Bool {
        title == StudyFilingPath.uncategorizedTitle || title == StudyFilingPath.missingTitle
    }
}

struct RecordingStudyBrowseContent: Equatable {
    let path: RecordingStudyBrowsePath
    let folders: [RecordingStudyFolder]
    let recordings: [RecordingMetadata]
}

enum RecordingStudyBrowser {
    static func content(recordings: [RecordingMetadata], path: RecordingStudyBrowsePath) -> RecordingStudyBrowseContent {
        let matchingRecordings = recordings.filter { recordingMatches($0, path: path) }

        if path.depth >= StudyFilingLevel.allCases.count || path.isUncategorizedTypeSelection {
            return RecordingStudyBrowseContent(
                path: path,
                folders: [],
                recordings: sortedRecordings(matchingRecordings)
            )
        }

        let nextLevel = StudyFilingLevel.allCases[path.depth]
        let grouped = Dictionary(grouping: matchingRecordings) { recording in
            displayValue(for: recording, level: nextLevel)
        }
        let folders = grouped
            .map { title, groupedRecordings in
                RecordingStudyFolder(
                    id: "\(path.components.joined(separator: "/"))/\(nextLevel.rawValue)=\(title)",
                    level: nextLevel,
                    title: title,
                    itemCount: groupedRecordings.count,
                    path: path.appending(title)
                )
            }
            .sorted { folderSort($0, $1) }

        return RecordingStudyBrowseContent(path: path, folders: folders, recordings: [])
    }

    static func breadcrumbs(for path: RecordingStudyBrowsePath) -> [(title: String, path: RecordingStudyBrowsePath)] {
        var result: [(String, RecordingStudyBrowsePath)] = [("学习库", RecordingStudyBrowsePath())]

        for index in path.components.indices {
            let componentPath = path.truncated(to: index + 1)
            result.append((path.components[index], componentPath))
        }

        return result
    }

    static func levelTitle(for path: RecordingStudyBrowsePath) -> String {
        if path.depth >= StudyFilingLevel.allCases.count || path.isUncategorizedTypeSelection {
            return "录音"
        }

        return StudyFilingLevel.allCases[path.depth].title
    }

    static func recordingMatches(_ recording: RecordingMetadata, path: RecordingStudyBrowsePath) -> Bool {
        guard path.depth <= StudyFilingLevel.allCases.count else {
            return false
        }

        for (index, component) in path.components.enumerated() {
            let level = StudyFilingLevel.allCases[index]
            guard displayValue(for: recording, level: level) == component else {
                return false
            }
        }

        return true
    }

    private static func displayValue(for recording: RecordingMetadata, level: StudyFilingLevel) -> String {
        if let value = recording.studyFiling?.value(for: level), !value.isEmpty {
            return value
        }

        return level == .type ? StudyFilingPath.uncategorizedTitle : StudyFilingPath.missingTitle
    }

    private static func folderSort(_ left: RecordingStudyFolder, _ right: RecordingStudyFolder) -> Bool {
        if left.isFallback != right.isFallback {
            return left.isFallback
        }

        return left.title.localizedStandardCompare(right.title) == .orderedAscending
    }

    private static func sortedRecordings(_ recordings: [RecordingMetadata]) -> [RecordingMetadata] {
        recordings.sorted { left, right in
            if left.createdAt == right.createdAt {
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }

            return left.createdAt > right.createdAt
        }
    }
}

enum RecordingStudyTreeBuilder {
    static func build(recordings: [RecordingMetadata]) -> [RecordingStudyNode] {
        let root = MutableRecordingStudyNode(id: "root", level: .type, title: "学习库")

        for recording in recordings {
            insert(recording, levelIndex: 0, into: root)
        }

        return root.children
            .map { makeNode($0) }
            .sorted { nodeSort($0, $1) }
    }

    private static func insert(
        _ recording: RecordingMetadata,
        levelIndex: Int,
        into node: MutableRecordingStudyNode
    ) {
        guard levelIndex < StudyFilingLevel.allCases.count else {
            node.recordingsByID[recording.id] = recording
            return
        }

        let level = StudyFilingLevel.allCases[levelIndex]
        let title = displayValue(for: recording.studyFiling, level: level)
        let childID = "\(node.id)/\(level.rawValue)=\(title)"
        let child = node.child(id: childID, level: level, title: title)
        insert(recording, levelIndex: levelIndex + 1, into: child)
    }

    private static func displayValue(for filing: StudyFilingPath?, level: StudyFilingLevel) -> String {
        if let value = filing?.value(for: level), !value.isEmpty {
            return value
        }

        return level == .type ? StudyFilingPath.uncategorizedTitle : StudyFilingPath.missingTitle
    }

    private static func makeNode(_ mutable: MutableRecordingStudyNode) -> RecordingStudyNode {
        RecordingStudyNode(
            id: mutable.id,
            level: mutable.level,
            title: mutable.title,
            children: mutable.children.map { makeNode($0) }.sorted { nodeSort($0, $1) },
            recordings: mutable.recordingsByID.values.sorted { left, right in
                if left.createdAt == right.createdAt {
                    return left.title.localizedStandardCompare(right.title) == .orderedAscending
                }

                return left.createdAt > right.createdAt
            }
        )
    }

    private static func nodeSort(_ left: RecordingStudyNode, _ right: RecordingStudyNode) -> Bool {
        if left.isFallback != right.isFallback {
            return left.isFallback
        }

        return left.title.localizedStandardCompare(right.title) == .orderedAscending
    }
}

private final class MutableRecordingStudyNode {
    let id: String
    let level: StudyFilingLevel
    let title: String
    var recordingsByID: [String: RecordingMetadata] = [:]
    private var childrenByID: [String: MutableRecordingStudyNode] = [:]

    init(id: String, level: StudyFilingLevel, title: String) {
        self.id = id
        self.level = level
        self.title = title
    }

    var children: [MutableRecordingStudyNode] {
        Array(childrenByID.values)
    }

    func child(id: String, level: StudyFilingLevel, title: String) -> MutableRecordingStudyNode {
        if let child = childrenByID[id] {
            return child
        }

        let child = MutableRecordingStudyNode(id: id, level: level, title: title)
        childrenByID[id] = child
        return child
    }
}

enum RecordingSaveTitleResolver {
    static func title(
        defaultTitle: String,
        pendingTitle: String?,
        studyFiling: StudyFilingPath?,
        directSave: Bool
    ) -> String {
        if directSave {
            return defaultTitle
        }

        let normalizedPendingTitle = StudyFilingPath.normalized(pendingTitle)
        if let normalizedPendingTitle {
            return normalizedPendingTitle
        }

        return studyFiling?.suggestedTitle(defaultTitle: defaultTitle) ?? defaultTitle
    }
}

typealias StudyItemID = String
typealias StudyFolderID = String

enum StudyItemKind: String, Codable, Equatable {
    case recordingBundle
    case standaloneNote
}

enum ProcessingMode: String, Codable, Equatable {
    case singlePass
    case chunked
    case sectioned
}

struct RecordingTranscriptionChunkRecord: Codable, Equatable {
    var index: Int
    var start: TimeInterval?
    var end: TimeInterval?
    var status: String?
}

struct RecordingNoteSectionRecord: Codable, Equatable {
    var index: Int
    var sourceStart: Int?
    var sourceEnd: Int?
    var status: String?
    var sectionNoteRelativePath: String?
}

struct StudyTag: Codable, Hashable, Identifiable {
    let id: String
    var namespace: String
    var value: String
    var displayName: String?
    var createdAt: Date?

    nonisolated init(
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
        self.init(
            id: try container.decodeIfPresent(String.self, forKey: .id),
            namespace: try container.decodeIfPresent(String.self, forKey: .namespace) ?? "custom",
            value: try container.decodeIfPresent(String.self, forKey: .value) ?? "",
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt)
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
    var isTrashed: Bool
    var trashedAt: Date?
    var modifiedByDeviceID: String?
    var syncConflictStatus: String?

    nonisolated init(
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
        sourceDescription: String? = nil,
        isTrashed: Bool = false,
        trashedAt: Date? = nil,
        modifiedByDeviceID: String? = nil,
        syncConflictStatus: String? = nil
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
        self.isTrashed = isTrashed
        self.trashedAt = trashedAt
        self.modifiedByDeviceID = Self.normalized(modifiedByDeviceID)
        self.syncConflictStatus = Self.normalized(syncConflictStatus)
    }

    nonisolated init(
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
        noteSections: [RecordingNoteSectionRecord]? = nil,
        sourceDescription: String? = nil,
        isTrashed: Bool = false,
        trashedAt: Date? = nil,
        modifiedByDeviceID: String? = nil,
        syncConflictStatus: String? = nil
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
            noteSections: noteSections,
            sourceDescription: sourceDescription,
            isTrashed: isTrashed,
            trashedAt: trashedAt,
            modifiedByDeviceID: modifiedByDeviceID,
            syncConflictStatus: syncConflictStatus
        )
    }

    var hasTranscript: Bool {
        transcriptMarkdownRelativePath != nil || transcriptRelativePath != nil
    }

    var hasNote: Bool {
        noteRelativePath != nil
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

    func mergedWithCurrentRecording(_ recording: RecordingMetadata) -> StudyItemMetadata {
        let resolvedFiling = filing.isEmpty ? (recording.studyFiling ?? StudyFilingPath()) : filing
        let resolvedFolderIDs = folderIDs.isEmpty ? Self.defaultFolderIDs(for: resolvedFiling) : folderIDs
        return StudyItemMetadata(
            itemID: itemID,
            kind: .recordingBundle,
            title: recording.title,
            createdAt: recording.createdAt,
            updatedAt: updatedAt,
            filing: resolvedFiling,
            tags: tags,
            folderIDs: resolvedFolderIDs,
            customProperties: customProperties,
            recordingID: recording.id,
            sanitizedRecordingID: sanitizedRecordingID,
            duration: recording.duration,
            audioRelativePath: recording.relativeAudioPath,
            receiveRelativePath: receiveRelativePath,
            transcriptRelativePath: transcriptRelativePath,
            transcriptMarkdownRelativePath: transcriptMarkdownRelativePath,
            noteRelativePath: noteRelativePath,
            transcriptionStatus: recording.transcriptionStatus,
            noteStatus: recording.noteStatus,
            noteSections: noteSections,
            sourceDescription: sourceDescription,
            isTrashed: isTrashed || recording.isDeleted,
            trashedAt: recording.deletedAt ?? trashedAt,
            modifiedByDeviceID: modifiedByDeviceID,
            syncConflictStatus: syncConflictStatus
        )
    }

    nonisolated static func defaultMetadata(for recording: RecordingMetadata) -> StudyItemMetadata {
        StudyItemMetadata(
            recordingID: recording.id,
            sanitizedRecordingID: StudyPathSanitizer.sanitizedPathComponent(recording.id),
            title: recording.title,
            createdAt: recording.createdAt,
            duration: recording.duration,
            audioRelativePath: recording.relativeAudioPath,
            receiveRelativePath: nil,
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            noteRelativePath: nil,
            studyFiling: recording.studyFiling,
            tags: recording.tags.map { StudyTag(namespace: "custom", value: $0) },
            customProperties: [:],
            updatedAt: Date(),
            transcriptionStatus: recording.transcriptionStatus,
            noteStatus: recording.noteStatus,
            sourceDescription: "iPhone",
            isTrashed: recording.isDeleted,
            trashedAt: recording.deletedAt
        )
    }

    nonisolated static func defaultMetadata(for receiveRecord: RecordingReceiveRecord, receiveRelativePath: String?) -> StudyItemMetadata? {
        guard let recordingID = normalized(receiveRecord.recordingID) else {
            return nil
        }

        return StudyItemMetadata(
            recordingID: recordingID,
            sanitizedRecordingID: receiveRecord.sanitizedRecordingID,
            title: receiveRecord.normalizedTitle ?? receiveRecord.originalTitle ?? "未命名录音",
            createdAt: receiveRecord.createdAt ?? receiveRecord.receivedAt ?? Date(timeIntervalSince1970: 0),
            duration: receiveRecord.duration ?? 0,
            audioRelativePath: receiveRecord.audioRelativePath,
            receiveRelativePath: receiveRelativePath,
            transcriptRelativePath: receiveRecord.transcriptRelativePath,
            transcriptMarkdownRelativePath: receiveRecord.transcriptMarkdownRelativePath,
            noteRelativePath: receiveRecord.noteRelativePath,
            studyFiling: receiveRecord.studyFiling,
            tags: receiveRecord.tags.map { StudyTag(namespace: "custom", value: $0) },
            updatedAt: receiveRecord.updatedAt ?? Date(timeIntervalSince1970: 0),
            transcriptionStatus: receiveRecord.transcriptionStatus,
            noteStatus: receiveRecord.noteStatus,
            noteSections: receiveRecord.noteSections,
            sourceDescription: receiveRecord.sourceDeviceName
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
        case isTrashed
        case trashedAt
        case modifiedByDeviceID
        case syncConflictStatus
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
            sourceDescription: try container.decodeIfPresent(String.self, forKey: .sourceDescription),
            isTrashed: try container.decodeIfPresent(Bool.self, forKey: .isTrashed) ?? false,
            trashedAt: try container.decodeIfPresent(Date.self, forKey: .trashedAt),
            modifiedByDeviceID: try container.decodeIfPresent(String.self, forKey: .modifiedByDeviceID),
            syncConflictStatus: try container.decodeIfPresent(String.self, forKey: .syncConflictStatus)
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
        try container.encode(isTrashed, forKey: .isTrashed)
        try container.encodeIfPresent(trashedAt, forKey: .trashedAt)
        try container.encodeIfPresent(modifiedByDeviceID, forKey: .modifiedByDeviceID)
        try container.encodeIfPresent(syncConflictStatus, forKey: .syncConflictStatus)
    }

    nonisolated static func recordingBundleItemID(for recordingID: String) -> StudyItemID {
        "item_recording_\(StudyPathSanitizer.sanitizedPathComponent(recordingID))"
    }

    nonisolated static func defaultFolderIDs(for filing: StudyFilingPath) -> [StudyFolderID] {
        let path = effectiveFolderPath(for: filing)
        guard let deepestLevel = StudyFolderMetadata.deepestLevel(in: path) else {
            return []
        }

        return [StudyFolderMetadata.folderID(for: deepestLevel, path: path)]
    }

    nonisolated static func effectiveFolderPath(for filing: StudyFilingPath) -> StudyFilingPath {
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

    nonisolated static func uniqueIDs(_ values: [String]) -> [String] {
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

    nonisolated static func normalized(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

enum StudyFolderLevel: String, Codable, Equatable, CaseIterable, Identifiable {
    case type
    case subject
    case chapter
    case topic
    case custom

    var id: String { rawValue }

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
    var modifiedByDeviceID: String?
    var syncConflictStatus: String?

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
        case modifiedByDeviceID
        case syncConflictStatus
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
        customProperties: [String: String] = [:],
        modifiedByDeviceID: String? = nil,
        syncConflictStatus: String? = nil
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
        self.modifiedByDeviceID = StudyItemMetadata.normalized(modifiedByDeviceID)
        self.syncConflictStatus = StudyItemMetadata.normalized(syncConflictStatus)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name) ?? StudyHierarchyRule.missingValue
        let level = try container.decodeIfPresent(StudyFolderLevel.self, forKey: .level) ?? .custom
        let path = try container.decodeIfPresent(StudyFilingPath.self, forKey: .path) ?? StudyFilingPath()

        self.init(
            folderID: try container.decodeIfPresent(String.self, forKey: .folderID),
            name: name,
            level: level,
            path: path,
            parentFolderID: try container.decodeIfPresent(String.self, forKey: .parentFolderID),
            childFolderIDs: try container.decodeIfPresent([StudyFolderID].self, forKey: .childFolderIDs) ?? [],
            itemIDs: try container.decodeIfPresent([StudyItemID].self, forKey: .itemIDs) ?? [],
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(),
            colorToken: try container.decodeIfPresent(StudyFolderColorToken.self, forKey: .colorToken),
            isTrashed: try container.decodeIfPresent(Bool.self, forKey: .isTrashed) ?? false,
            trashedAt: try container.decodeIfPresent(Date.self, forKey: .trashedAt),
            customProperties: try container.decodeIfPresent([String: String].self, forKey: .customProperties) ?? [:],
            modifiedByDeviceID: try container.decodeIfPresent(String.self, forKey: .modifiedByDeviceID),
            syncConflictStatus: try container.decodeIfPresent(String.self, forKey: .syncConflictStatus)
        )
    }

    var pathComponents: [String] {
        Self.pathComponents(for: path, through: level)
    }

    nonisolated static func folderID(for level: StudyFolderLevel, path: StudyFilingPath) -> StudyFolderID {
        let components = pathComponents(for: path, through: level)
        let raw = ([level.rawValue] + components).joined(separator: "_")
        return "folder_\(StudyPathSanitizer.sanitizedPathComponent(raw))"
    }

    nonisolated static func pathComponents(for path: StudyFilingPath, through level: StudyFolderLevel) -> [String] {
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

    nonisolated static func deepestLevel(in path: StudyFilingPath) -> StudyFolderLevel? {
        if path.topic != nil { return .topic }
        if path.chapter != nil { return .chapter }
        if path.subject != nil { return .subject }
        if path.type != nil { return .type }
        return nil
    }

    nonisolated static func level(forDepth depth: Int) -> StudyFolderLevel? {
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

    nonisolated static func filingPath(for components: [String]) -> StudyFilingPath {
        StudyFilingPath(
            type: components[safe: 0],
            subject: components[safe: 1],
            chapter: components[safe: 2],
            topic: components[safe: 3]
        )
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

    nonisolated static let uncategorizedValue = StudyFilingPath.uncategorizedTitle
    nonisolated static let missingValue = StudyFilingPath.missingTitle
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
            return StudyBrowseContent(path: path, folders: [], items: sortedItems(matchingItems))
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

    private static func displayValue(for item: StudyItemMetadata, levelKey: String) -> String {
        if let value = item.filingPath.value(for: levelKey), !value.isEmpty {
            return value
        }

        return StudyTag.normalizedNamespace(levelKey) == "type"
            ? StudyHierarchyRule.uncategorizedValue
            : StudyHierarchyRule.missingValue
    }

    private static func folderMatchesParent(
        _ folder: StudyFolderMetadata,
        parentPath: StudyBrowsePath,
        nextLevel: StudyFolderLevel
    ) -> Bool {
        guard folder.level == nextLevel else {
            return false
        }

        let folderComponents = folder.pathComponents
        guard folderComponents.count == parentPath.depth + 1 else {
            return false
        }

        return Array(folderComponents.prefix(parentPath.depth)) == parentPath.components
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
        StudyFilingPath(type: type, subject: subject, chapter: chapter, topic: topic)
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
            } else if let value = item.filingPath.value(for: level) {
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

struct RecordingReceiveRecord: Codable, Equatable {
    var recordingID: String?
    var sanitizedRecordingID: String?
    var receivedAt: Date?
    var updatedAt: Date?
    var sourceDeviceID: String?
    var sourceDeviceName: String?
    var originalTitle: String?
    var normalizedTitle: String?
    var audioFileName: String?
    var originalAudioFileName: String?
    var metadataFileName: String?
    var status: String?
    var transcriptionStatus: String?
    var noteStatus: String?
    var noteRelativePath: String?
    var noteGeneratedAt: Date?
    var noteProviderID: String?
    var noteModelName: String?
    var processingStatus: String?
    var tags: [String]
    var studyFiling: StudyFilingPath?
    var createdAt: Date?
    var duration: TimeInterval?
    var fileSize: Int64?
    var audioRelativePath: String?
    var metadataRelativePath: String?
    var transcriptRelativePath: String?
    var transcriptMarkdownRelativePath: String?
    var transcriptionProviderID: String?
    var transcriptionModelName: String?
    var transcriptionStartedAt: Date?
    var transcriptionCompletedAt: Date?
    var transcriptionMode: ProcessingMode?
    var transcriptionChunks: [RecordingTranscriptionChunkRecord]?
    var noteGenerationMode: ProcessingMode?
    var noteSections: [RecordingNoteSectionRecord]?

    private enum CodingKeys: String, CodingKey {
        case recordingID
        case sanitizedRecordingID
        case receivedAt
        case updatedAt
        case sourceDeviceID
        case sourceDeviceName
        case originalTitle
        case normalizedTitle
        case audioFileName
        case originalAudioFileName
        case metadataFileName
        case status
        case transcriptionStatus
        case noteStatus
        case noteRelativePath
        case noteGeneratedAt
        case noteProviderID
        case noteModelName
        case processingStatus
        case tags
        case studyFiling
        case createdAt
        case duration
        case fileSize
        case audioRelativePath
        case metadataRelativePath
        case transcriptRelativePath
        case transcriptMarkdownRelativePath
        case transcriptionProviderID
        case transcriptionModelName
        case transcriptionStartedAt
        case transcriptionCompletedAt
        case transcriptionMode
        case transcriptionChunks
        case noteGenerationMode
        case noteSections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingID = try container.decodeIfPresent(String.self, forKey: .recordingID)
        sanitizedRecordingID = try container.decodeIfPresent(String.self, forKey: .sanitizedRecordingID)
        receivedAt = try container.decodeIfPresent(Date.self, forKey: .receivedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        sourceDeviceID = try container.decodeIfPresent(String.self, forKey: .sourceDeviceID)
        sourceDeviceName = try container.decodeIfPresent(String.self, forKey: .sourceDeviceName)
        originalTitle = try container.decodeIfPresent(String.self, forKey: .originalTitle)
        normalizedTitle = try container.decodeIfPresent(String.self, forKey: .normalizedTitle)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        originalAudioFileName = try container.decodeIfPresent(String.self, forKey: .originalAudioFileName)
        metadataFileName = try container.decodeIfPresent(String.self, forKey: .metadataFileName)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        transcriptionStatus = try container.decodeIfPresent(String.self, forKey: .transcriptionStatus)
        noteStatus = Self.normalizedNoteStatus(try container.decodeIfPresent(String.self, forKey: .noteStatus))
        noteRelativePath = try container.decodeIfPresent(String.self, forKey: .noteRelativePath)
        noteGeneratedAt = try container.decodeIfPresent(Date.self, forKey: .noteGeneratedAt)
        noteProviderID = try container.decodeIfPresent(String.self, forKey: .noteProviderID)
        noteModelName = try container.decodeIfPresent(String.self, forKey: .noteModelName)
        processingStatus = try container.decodeIfPresent(String.self, forKey: .processingStatus)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        let decodedStudyFiling = try container.decodeIfPresent(StudyFilingPath.self, forKey: .studyFiling)
        studyFiling = decodedStudyFiling?.isEmpty == true ? nil : decodedStudyFiling
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        audioRelativePath = try container.decodeIfPresent(String.self, forKey: .audioRelativePath)
        metadataRelativePath = try container.decodeIfPresent(String.self, forKey: .metadataRelativePath)
        transcriptRelativePath = try container.decodeIfPresent(String.self, forKey: .transcriptRelativePath)
        transcriptMarkdownRelativePath = try container.decodeIfPresent(String.self, forKey: .transcriptMarkdownRelativePath)
        transcriptionProviderID = try container.decodeIfPresent(String.self, forKey: .transcriptionProviderID)
        transcriptionModelName = try container.decodeIfPresent(String.self, forKey: .transcriptionModelName)
        transcriptionStartedAt = try container.decodeIfPresent(Date.self, forKey: .transcriptionStartedAt)
        transcriptionCompletedAt = try container.decodeIfPresent(Date.self, forKey: .transcriptionCompletedAt)
        transcriptionMode = try container.decodeIfPresent(ProcessingMode.self, forKey: .transcriptionMode)
        transcriptionChunks = try container.decodeIfPresent([RecordingTranscriptionChunkRecord].self, forKey: .transcriptionChunks)
        noteGenerationMode = try container.decodeIfPresent(ProcessingMode.self, forKey: .noteGenerationMode)
        noteSections = try container.decodeIfPresent([RecordingNoteSectionRecord].self, forKey: .noteSections)
    }

    static func normalizedNoteStatus(_ status: String?) -> String? {
        let normalized = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalized == "notGenerated" {
            return "notStarted"
        }
        return normalized.isEmpty ? nil : normalized
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
    nonisolated subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
