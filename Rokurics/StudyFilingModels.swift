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
        return parts.isEmpty ? StudyFilingPath.uncategorizedTitle : parts.joined(separator: " / ")
    }

    func value(for level: StudyFilingLevel) -> String? {
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

    static let uncategorizedTitle = "未分类"
    static let missingTitle = "未填写"
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

    static func collect(from recordings: [RecordingMetadata]) -> StudyFilingCandidates {
        StudyFilingCandidates(
            types: sortedUnique(recordings.compactMap(\.studyFiling?.type)),
            subjects: sortedUnique(recordings.compactMap(\.studyFiling?.subject)),
            chapters: sortedUnique(recordings.compactMap(\.studyFiling?.chapter)),
            topics: sortedUnique(recordings.compactMap(\.studyFiling?.topic))
        )
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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
