//
//  StudyLibraryStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Combine
import Foundation

enum StudyLibraryStoreError: LocalizedError {
    case unableToCreateDirectory
    case unsafeDestination
    case itemMissing
    case folderMissing
    case unsupportedFolderLevel
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unableToCreateDirectory:
            return "study_directory_unavailable"
        case .unsafeDestination:
            return "unsafe_study_destination"
        case .itemMissing:
            return "study_item_missing"
        case .folderMissing:
            return "study_folder_missing"
        case .unsupportedFolderLevel:
            return "study_folder_level_unsupported"
        case .writeFailed(let reason):
            return reason
        }
    }
}

struct StudyMetadataIndex: Codable, Equatable {
    var itemMetadataFilesByItemID: [String: String] = [:]
    var itemMetadataFilesByRecordingID: [String: String] = [:]
    var folderMetadataFilesByFolderID: [String: String] = [:]
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    private enum CodingKeys: String, CodingKey {
        case itemMetadataFilesByItemID
        case itemMetadataFilesByRecordingID
        case folderMetadataFilesByFolderID
        case updatedAt
    }

    init(
        itemMetadataFilesByItemID: [String: String] = [:],
        itemMetadataFilesByRecordingID: [String: String] = [:],
        folderMetadataFilesByFolderID: [String: String] = [:],
        updatedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.itemMetadataFilesByItemID = itemMetadataFilesByItemID
        self.itemMetadataFilesByRecordingID = itemMetadataFilesByRecordingID
        self.folderMetadataFilesByFolderID = folderMetadataFilesByFolderID
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemMetadataFilesByItemID = try container.decodeIfPresent([String: String].self, forKey: .itemMetadataFilesByItemID) ?? [:]
        itemMetadataFilesByRecordingID = try container.decodeIfPresent([String: String].self, forKey: .itemMetadataFilesByRecordingID) ?? [:]
        folderMetadataFilesByFolderID = try container.decodeIfPresent([String: String].self, forKey: .folderMetadataFilesByFolderID) ?? [:]
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
    }
}

final class StudyLibraryStore: ObservableObject {
    @Published private(set) var allStudyItems: [StudyItemMetadata] = []
    @Published private(set) var allStudyFolders: [StudyFolderMetadata] = []
    @Published private(set) var hierarchyRules: [StudyHierarchyRule] = [.defaultCourseView]
    @Published private(set) var selectedHierarchyRule: StudyHierarchyRule = .defaultCourseView
    @Published private(set) var studyTree: [VirtualStudyNode] = []
    @Published private(set) var filingCandidates: StudyFilingCandidates = .empty

    private let fileManager: FileManager
    private let rootURL: URL
    private let studyURL: URL
    private let itemMetadataURL: URL
    private let folderMetadataURL: URL
    private let indexURL: URL
    private let hierarchyRulesURL: URL
    private let legacyItemMetadataURL: URL
    private let legacyIndexURL: URL
    private let recordingFileStore: MacRecordingFileStore
    private let noteStore: NoteStore
    private var inboxChangeCancellable: AnyCancellable?

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        recordingFileStore: MacRecordingFileStore? = nil,
        listenForInboxChanges: Bool = true
    ) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            self.rootURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
        }
        self.studyURL = self.rootURL
            .appendingPathComponent("study", isDirectory: true)
            .standardizedFileURL
        self.itemMetadataURL = studyURL
            .appendingPathComponent("items", isDirectory: true)
            .standardizedFileURL
        self.folderMetadataURL = studyURL
            .appendingPathComponent("folders", isDirectory: true)
            .standardizedFileURL
        self.indexURL = studyURL
            .appendingPathComponent("index.json", isDirectory: false)
            .standardizedFileURL
        self.hierarchyRulesURL = studyURL
            .appendingPathComponent("hierarchy-rules.json", isDirectory: false)
            .standardizedFileURL
        self.legacyItemMetadataURL = studyURL
            .appendingPathComponent("item-metadata", isDirectory: true)
            .standardizedFileURL
        self.legacyIndexURL = studyURL
            .appendingPathComponent("study-index.json", isDirectory: false)
            .standardizedFileURL
        self.recordingFileStore = recordingFileStore ?? MacRecordingFileStore(fileManager: fileManager, rootURL: self.rootURL)
        self.noteStore = NoteStore(fileManager: fileManager, rootURL: self.rootURL)

        try? ensureStudyDirectories()
        hierarchyRules = loadHierarchyRules()
        selectedHierarchyRule = hierarchyRules.first ?? .defaultCourseView
        refresh()

        if listenForInboxChanges {
            inboxChangeCancellable = NotificationCenter.default
                .publisher(for: MacRecordingFileStore.inboxDidChangeNotification)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.refresh()
                }
        }
    }

    var studyRootDisplayPath: String {
        studyURL.path
    }

    var libraryRootURL: URL {
        rootURL
    }

    func refresh() {
        let inboxItems = recordingFileStore.loadInboxItems()
        let storedItems = loadAllStoredItemMetadata()
        let storedItemsByRecordingID = Dictionary(
            storedItems.compactMap { item -> (String, StudyItemMetadata)? in
                guard let recordingID = item.recordingID else {
                    return nil
                }
                return (recordingID, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let liveRecordingIDs = Set(inboxItems.map(\.id))

        var itemsByID: [StudyItemID: StudyItemMetadata] = [:]
        for inboxItem in inboxItems {
            let fallback = StudyItemMetadata.defaultMetadata(for: inboxItem)
            let metadata = storedItemsByRecordingID[inboxItem.id]?.mergedWithCurrentInboxItem(inboxItem) ?? fallback
            itemsByID[metadata.itemID] = metadata
        }

        for item in storedItems where shouldIncludeStoredItem(item, liveRecordingIDs: liveRecordingIDs) {
            itemsByID[item.itemID] = item
        }

        let items = itemsByID.values.sorted { left, right in
            if left.createdAt == right.createdAt {
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }

            return left.createdAt > right.createdAt
        }
        let folders = repairedFolders(
            loadAllFolderMetadata().filter { !$0.isTrashed },
            items: items
        )

        allStudyItems = items
        allStudyFolders = folders
        filingCandidates = StudyFilingCandidates.collect(from: items)
        studyTree = VirtualStudyTreeBuilder.build(items: items, folders: folders, rule: selectedHierarchyRule)
    }

    func item(recordingID: String) -> StudyItemMetadata? {
        allStudyItems.first { $0.recordingID == recordingID }
    }

    func item(itemID: StudyItemID) -> StudyItemMetadata? {
        allStudyItems.first { $0.itemID == itemID }
    }

    func makeSyncManifest(deviceID: String, generatedAt: Date = Date()) -> StudyLibrarySyncManifest {
        refresh()

        var itemsByID = Dictionary(
            (loadAllStoredItemMetadata() + allStudyItems).map { ($0.itemID, $0) },
            uniquingKeysWith: { _, live in live }
        )
        let storedItemsByRecordingID = Dictionary(
            loadAllStoredItemMetadata().compactMap { item -> (String, StudyItemMetadata)? in
                guard let recordingID = item.recordingID else {
                    return nil
                }
                return (recordingID, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        for inboxItem in recordingFileStore.loadInboxItems() {
            let fallback = StudyItemMetadata.defaultMetadata(for: inboxItem)
            let metadata = storedItemsByRecordingID[inboxItem.id]?.mergedWithCurrentInboxItem(inboxItem) ?? fallback
            itemsByID[metadata.itemID] = metadata
        }

        let foldersByID = Dictionary(
            (loadAllFolderMetadata() + allStudyFolders).map { ($0.folderID, $0) },
            uniquingKeysWith: { _, live in live }
        )
        let items = itemsByID.values.map { item -> StudyItemMetadata in
            var sanitized = item.syncSanitized(modifiedByDeviceID: deviceID)
            attachNoteSummaryPreview(to: &sanitized)
            return sanitized
        }
        let folders = foldersByID.values.map { $0.syncSanitized(modifiedByDeviceID: deviceID) }
        let tombstones = makeSyncTombstones(items: items, folders: folders, deviceID: deviceID)

        return StudyLibrarySyncManifest.make(
            deviceID: deviceID,
            generatedAt: generatedAt,
            items: items,
            folders: folders,
            tombstones: tombstones
        )
    }

    @discardableResult
    func applySyncManifest(_ manifest: StudyLibrarySyncManifest, localDeviceID: String) throws -> StudyLibrarySyncApplyResult {
        guard manifest.hasValidChecksum else {
            throw StudyLibraryStoreError.writeFailed("sync_manifest_checksum_mismatch")
        }

        var result = StudyLibrarySyncApplyResult()

        for incomingFolder in manifest.folders {
            do {
                var remote = incomingFolder.syncSanitized(modifiedByDeviceID: manifest.deviceID)
                let existing = loadStoredFolder(folderID: remote.folderID) ?? allStudyFolders.first { $0.folderID == remote.folderID }
                guard let merged = mergedSyncFolder(existing: existing, incoming: &remote, result: &result) else {
                    continue
                }
                try save(merged)
                result.appliedFolderCount += 1
            } catch {
                result.failedChanges += 1
            }
        }

        for incomingItem in manifest.items {
            do {
                var remote = incomingItem.syncSanitized(modifiedByDeviceID: manifest.deviceID)
                markSyncMetadataOnlyIfNeeded(&remote)
                let existing = editableMetadataIfAvailable(itemID: remote.itemID)
                guard let merged = mergedSyncItem(existing: existing, incoming: &remote, result: &result) else {
                    continue
                }
                try save(merged)
                result.appliedItemCount += 1
            } catch {
                result.failedChanges += 1
            }
        }

        for tombstone in manifest.tombstones {
            do {
                if try applySyncTombstone(tombstone, remoteDeviceID: manifest.deviceID) {
                    result.tombstoneCount += 1
                }
            } catch {
                result.failedChanges += 1
            }
        }

        refresh()
        return result
    }

    func folder(folderID: StudyFolderID) -> StudyFolderMetadata? {
        allStudyFolders.first { $0.folderID == folderID } ?? loadStoredFolder(folderID: folderID)
    }

    func items(matching tag: StudyTag) -> [StudyItemMetadata] {
        let normalizedNamespace = StudyTag.normalizedNamespace(tag.namespace)
        let normalizedValue = StudyTag.normalizedValue(tag.value).lowercased()

        return allStudyItems.filter { item in
            item.tags.contains { candidate in
                candidate.namespace == normalizedNamespace && candidate.value.lowercased() == normalizedValue
            }
        }
    }

    func tree(for rule: StudyHierarchyRule? = nil) -> [VirtualStudyNode] {
        VirtualStudyTreeBuilder.build(
            items: allStudyItems,
            folders: allStudyFolders,
            rule: rule ?? selectedHierarchyRule
        )
    }

    func selectHierarchyRule(id: String) {
        guard let rule = hierarchyRules.first(where: { $0.id == id }) else {
            return
        }

        selectedHierarchyRule = rule
        studyTree = VirtualStudyTreeBuilder.build(items: allStudyItems, folders: allStudyFolders, rule: rule)
    }

    func saveHierarchyRules(_ rules: [StudyHierarchyRule]) throws {
        let normalizedRules = rules.isEmpty ? [.defaultCourseView] : rules
        guard isInsideStudyDirectory(hierarchyRulesURL) else {
            throw StudyLibraryStoreError.unsafeDestination
        }

        do {
            try ensureStudyDirectories()
            try Self.jsonEncoder.encode(normalizedRules).write(to: hierarchyRulesURL, options: .atomic)
            hierarchyRules = normalizedRules
            selectedHierarchyRule = normalizedRules.first ?? .defaultCourseView
            studyTree = VirtualStudyTreeBuilder.build(items: allStudyItems, folders: allStudyFolders, rule: selectedHierarchyRule)
        } catch let error as StudyLibraryStoreError {
            throw error
        } catch {
            throw StudyLibraryStoreError.writeFailed("study_hierarchy_rules_write_failed")
        }
    }

    func updateTags(for recordingID: String, tags: [StudyTag]) throws {
        let previous = try editableMetadata(recordingID: recordingID)
        var metadata = previous
        metadata.tags = StudyTagList.unique(tags)
        metadata.updatedAt = Date()
        try save(metadata, previousMetadata: previous)
        refresh()
    }

    func updateFiling(for recordingID: String, studyFiling: StudyFilingPath?) throws {
        let previous = try editableMetadata(recordingID: recordingID)
        var metadata = previous
        metadata.filing = studyFiling?.isEmpty == true ? StudyFilingPath() : (studyFiling ?? StudyFilingPath())
        metadata.folderIDs = StudyItemMetadata.defaultFolderIDs(for: metadata.filing)
        metadata.updatedAt = Date()
        try save(metadata, previousMetadata: previous)
        refresh()
    }

    func updateCustomProperties(for recordingID: String, customProperties: [String: String]) throws {
        let previous = try editableMetadata(recordingID: recordingID)
        var metadata = previous
        metadata.customProperties = customProperties
        metadata.updatedAt = Date()
        try save(metadata, previousMetadata: previous)
        refresh()
    }

    @discardableResult
    func createFolder(named rawName: String, at path: StudyBrowsePath) throws -> StudyFolderMetadata {
        guard let level = StudyFolderMetadata.level(forDepth: path.depth) else {
            throw StudyLibraryStoreError.unsupportedFolderLevel
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? StudyHierarchyRule.missingValue
        let components = path.components + [name]
        let filing = StudyFolderMetadata.filingPath(for: components)
        let parentFolderID = parentFolderID(for: path)
        let folder = StudyFolderMetadata(
            name: name,
            level: level,
            path: filing,
            parentFolderID: parentFolderID,
            childFolderIDs: [],
            itemIDs: []
        )

        try save(folder)
        if let parentFolderID {
            try appendChildFolderID(folder.folderID, toParentFolderID: parentFolderID, parentPath: path)
        }
        refresh()
        return folder
    }

    func moveItem(itemID: StudyItemID, toFolderID folderID: StudyFolderID) throws {
        let previous = try editableMetadata(itemID: itemID)
        guard let folder = folder(folderID: folderID) else {
            throw StudyLibraryStoreError.folderMissing
        }

        var metadata = previous
        metadata.filing = folder.path
        metadata.folderIDs = [folder.folderID]
        metadata.updatedAt = Date()
        try save(metadata, previousMetadata: previous)
        refresh()
    }

    @discardableResult
    func renameFolder(folderID: StudyFolderID, to rawName: String) throws -> StudyFolderMetadata {
        guard var folder = folder(folderID: folderID) else {
            throw StudyLibraryStoreError.folderMissing
        }

        guard let name = StudyItemMetadata.normalized(rawName) else {
            return folder
        }

        guard folder.name != name else {
            return folder
        }

        let storedFolders = loadAllFolderMetadata()
        let duplicateExists = storedFolders.contains { candidate in
            candidate.folderID != folder.folderID
                && candidate.parentFolderID == folder.parentFolderID
                && candidate.level == folder.level
                && candidate.name.caseInsensitiveCompare(name) == .orderedSame
        }
        if duplicateExists {
            throw StudyLibraryStoreError.writeFailed("study_folder_duplicate_name")
        }

        let oldPath = folder.path
        let oldPathComponents = folder.pathComponents
        let updatedAt = Date()
        var foldersToSave: [StudyFolderMetadata] = []

        for candidate in storedFolders {
            guard pathComponents(candidate.pathComponents, startWith: oldPathComponents),
                  let updatedPath = renamedPath(candidate.path, replacing: folder.level, with: name) else {
                continue
            }

            var updated = candidate
            if updated.folderID == folder.folderID {
                updated.name = name
            }
            updated.path = updatedPath
            updated.updatedAt = updatedAt
            foldersToSave.append(updated)
            if updated.folderID == folder.folderID {
                folder = updated
            }
        }

        if !foldersToSave.contains(where: { $0.folderID == folder.folderID }) {
            folder.name = name
            folder.path = renamedPath(folder.path, replacing: folder.level, with: name) ?? folder.path
            folder.updatedAt = updatedAt
            foldersToSave.append(folder)
        }

        let itemsByID = Dictionary(
            (loadAllStoredItemMetadata() + allStudyItems).map { ($0.itemID, $0) },
            uniquingKeysWith: { _, live in live }
        )
        for candidate in itemsByID.values where item(candidate, matches: oldPath, through: folder.level) {
            var updated = candidate
            updated.filing = renamedPath(candidate.filing, replacing: folder.level, with: name) ?? candidate.filing
            updated.updatedAt = updatedAt
            try writeItemMetadataPreservingFolderLinks(updated)
        }

        for updatedFolder in foldersToSave {
            try save(updatedFolder)
        }

        refresh()
        return folder
    }

    @discardableResult
    func renameFolder(path: StudyBrowsePath, level: StudyFolderLevel, to rawName: String) throws -> StudyFolderMetadata {
        let filing = StudyFolderMetadata.filingPath(for: path.components)
        let folderID = StudyFolderMetadata.folderID(for: level, path: filing)
        if loadStoredFolder(folderID: folderID) == nil {
            let folder = StudyFolderMetadata(
                folderID: folderID,
                name: path.components.last ?? StudyHierarchyRule.missingValue,
                level: level,
                path: filing,
                parentFolderID: parentFolderID(for: path.parent),
                itemIDs: allStudyItems
                    .filter { item($0, matches: filing, through: level) }
                    .map(\.itemID)
            )
            try save(folder)
        }

        return try renameFolder(folderID: folderID, to: rawName)
    }

    @discardableResult
    func renameItem(itemID: StudyItemID, to rawTitle: String) throws -> StudyItemMetadata {
        let previous = try editableMetadata(itemID: itemID)
        guard let trimmedTitle = StudyItemMetadata.normalized(rawTitle) else {
            return previous
        }

        var metadata = previous
        let title: String
        if metadata.kind == .recordingBundle {
            title = RecordingTitleEditRules.normalizedTitle(trimmedTitle, fallback: previous.title)
        } else {
            title = String(trimmedTitle.prefix(RecordingTitleEditRules.maxTitleLength))
        }

        guard title != previous.title else {
            return previous
        }

        if let recordingID = metadata.recordingID {
            _ = try recordingFileStore.updateDisplayTitle(recordingID: recordingID, rawTitle: title)
        }

        metadata.title = title
        metadata.updatedAt = Date()
        try writeItemMetadataPreservingFolderLinks(metadata)
        refresh()
        return metadata
    }

    @discardableResult
    func setFolderColor(folderID: StudyFolderID, colorToken: StudyFolderColorToken?) throws -> StudyFolderMetadata {
        guard var folder = folder(folderID: folderID) else {
            throw StudyLibraryStoreError.folderMissing
        }

        folder.colorToken = colorToken == .default ? nil : colorToken
        folder.updatedAt = Date()
        try save(folder)
        refresh()
        return folder
    }

    @discardableResult
    func moveFolderToTrash(folderID: StudyFolderID) throws -> StudyFolderMetadata {
        guard var folder = loadStoredFolder(folderID: folderID) ?? allStudyFolders.first(where: { $0.folderID == folderID }) else {
            throw StudyLibraryStoreError.folderMissing
        }

        let folderPathComponents = folder.pathComponents
        let descendantFolders = loadAllFolderMetadata().filter { candidate in
            candidate.folderID != folder.folderID
                && !candidate.isTrashed
                && pathComponents(candidate.pathComponents, startWith: folderPathComponents)
        }
        let matchingItems = allStudyItems.filter { item in
            self.item(item, matches: folder.path, through: folder.level)
        }
        let hasIndexedItems = !folder.itemIDs.isEmpty

        guard descendantFolders.isEmpty && matchingItems.isEmpty && !hasIndexedItems else {
            throw StudyLibraryStoreError.writeFailed("study_folder_not_empty")
        }

        folder.isTrashed = true
        folder.trashedAt = Date()
        folder.updatedAt = Date()
        try save(folder)
        refresh()
        return folder
    }

    func save(_ metadata: StudyItemMetadata) throws {
        let previous = editableMetadataIfAvailable(itemID: metadata.itemID)
        try save(metadata, previousMetadata: previous)
    }

    func save(_ folder: StudyFolderMetadata) throws {
        do {
            try ensureStudyDirectories()
            let fileName = folderMetadataFileName(for: folder)
            let folderURL = folderMetadataURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL

            guard isInsideFolderMetadataDirectory(folderURL) else {
                throw StudyLibraryStoreError.unsafeDestination
            }

            try Self.jsonEncoder.encode(folder).write(to: folderURL, options: .atomic)
            var index = loadIndex()
            index.folderMetadataFilesByFolderID[folder.folderID] = fileName
            index.updatedAt = Date()
            try saveIndex(index)
        } catch let error as StudyLibraryStoreError {
            throw error
        } catch {
            throw StudyLibraryStoreError.writeFailed("study_folder_metadata_write_failed")
        }
    }

    private func save(_ metadata: StudyItemMetadata, previousMetadata: StudyItemMetadata?) throws {
        guard !metadata.itemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudyLibraryStoreError.itemMissing
        }

        do {
            try ensureStudyDirectories()
            var metadataToSave = metadata
            metadataToSave.tags = StudyTagList.unique(metadata.tags)
            if metadataToSave.folderIDs.isEmpty {
                metadataToSave.folderIDs = StudyItemMetadata.defaultFolderIDs(for: metadataToSave.filing)
            }

            try syncFolderLinks(for: metadataToSave, previousMetadata: previousMetadata)
            let fileName = itemMetadataFileName(for: metadataToSave)
            let metadataURL = itemMetadataURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL

            guard isInsideItemMetadataDirectory(metadataURL) else {
                throw StudyLibraryStoreError.unsafeDestination
            }

            try Self.jsonEncoder.encode(metadataToSave).write(to: metadataURL, options: .atomic)

            var index = loadIndex()
            index.itemMetadataFilesByItemID[metadataToSave.itemID] = fileName
            if let recordingID = metadataToSave.recordingID {
                index.itemMetadataFilesByRecordingID[recordingID] = fileName
            }
            index.updatedAt = Date()
            try saveIndex(index)
        } catch let error as StudyLibraryStoreError {
            throw error
        } catch {
            throw StudyLibraryStoreError.writeFailed("study_item_metadata_write_failed")
        }
    }

    private func writeItemMetadataPreservingFolderLinks(_ metadata: StudyItemMetadata) throws {
        guard !metadata.itemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudyLibraryStoreError.itemMissing
        }

        do {
            try ensureStudyDirectories()
            var metadataToSave = metadata
            metadataToSave.tags = StudyTagList.unique(metadata.tags)
            if metadataToSave.folderIDs.isEmpty {
                metadataToSave.folderIDs = StudyItemMetadata.defaultFolderIDs(for: metadataToSave.filing)
            }

            let fileName = itemMetadataFileName(for: metadataToSave)
            let metadataURL = itemMetadataURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL

            guard isInsideItemMetadataDirectory(metadataURL) else {
                throw StudyLibraryStoreError.unsafeDestination
            }

            try Self.jsonEncoder.encode(metadataToSave).write(to: metadataURL, options: .atomic)

            var index = loadIndex()
            index.itemMetadataFilesByItemID[metadataToSave.itemID] = fileName
            if let recordingID = metadataToSave.recordingID {
                index.itemMetadataFilesByRecordingID[recordingID] = fileName
            }
            index.updatedAt = Date()
            try saveIndex(index)
        } catch let error as StudyLibraryStoreError {
            throw error
        } catch {
            throw StudyLibraryStoreError.writeFailed("study_item_metadata_write_failed")
        }
    }

    private func editableMetadata(recordingID: String) throws -> StudyItemMetadata {
        if let inboxItem = recordingFileStore.loadInboxItems().first(where: { $0.id == recordingID }) {
            let fallback = StudyItemMetadata.defaultMetadata(for: inboxItem)
            return loadStoredMetadata(recordingID: recordingID)?.mergedWithCurrentInboxItem(inboxItem) ?? fallback
        }

        if let metadata = loadStoredMetadata(recordingID: recordingID) {
            return metadata
        }

        throw StudyLibraryStoreError.itemMissing
    }

    private func editableMetadata(itemID: StudyItemID) throws -> StudyItemMetadata {
        if let metadata = editableMetadataIfAvailable(itemID: itemID) {
            return metadata
        }

        throw StudyLibraryStoreError.itemMissing
    }

    private func editableMetadataIfAvailable(itemID: StudyItemID) -> StudyItemMetadata? {
        if let item = allStudyItems.first(where: { $0.itemID == itemID || $0.recordingID == itemID }) {
            return item
        }

        return loadAllStoredItemMetadata().first { $0.itemID == itemID || $0.recordingID == itemID }
    }

    private func loadStoredMetadata(recordingID: String) -> StudyItemMetadata? {
        let recordingItemID = StudyItemMetadata.recordingBundleItemID(for: recordingID)
        return loadAllStoredItemMetadata().first { metadata in
            metadata.recordingID == recordingID || metadata.itemID == recordingItemID
        }
    }

    private func shouldIncludeStoredItem(_ item: StudyItemMetadata, liveRecordingIDs: Set<String>) -> Bool {
        if item.kind == .standaloneNote || item.recordingID == nil {
            return true
        }
        if item.customProperties["syncedMetadataOnly"] == "true" {
            return true
        }

        return item.recordingID.map { liveRecordingIDs.contains($0) } ?? false
    }

    private func makeSyncTombstones(
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata],
        deviceID: String
    ) -> [StudyLibrarySyncTombstone] {
        let itemTombstones = items.filter(\.isTrashed).map { item in
            StudyLibrarySyncTombstone(
                id: "item:\(item.itemID)",
                entityKind: .item,
                entityID: item.itemID,
                operation: .trash,
                updatedAt: item.trashedAt ?? item.updatedAt,
                modifiedByDeviceID: item.modifiedByDeviceID ?? deviceID
            )
        }
        let folderTombstones = folders.filter(\.isTrashed).map { folder in
            StudyLibrarySyncTombstone(
                id: "folder:\(folder.folderID)",
                entityKind: .folder,
                entityID: folder.folderID,
                operation: .trash,
                updatedAt: folder.trashedAt ?? folder.updatedAt,
                modifiedByDeviceID: folder.modifiedByDeviceID ?? deviceID
            )
        }

        return itemTombstones + folderTombstones
    }

    private func mergedSyncItem(
        existing: StudyItemMetadata?,
        incoming: inout StudyItemMetadata,
        result: inout StudyLibrarySyncApplyResult
    ) -> StudyItemMetadata? {
        guard var existing else {
            return incoming
        }

        if incoming.updatedAt > existing.updatedAt {
            return incoming
        }

        if incoming.updatedAt == existing.updatedAt, incoming != existing {
            existing.syncConflictStatus = "conflict_preserved_local"
            result.conflictCount += 1
            return existing
        }

        result.skippedOlderCount += 1
        return nil
    }

    private func mergedSyncFolder(
        existing: StudyFolderMetadata?,
        incoming: inout StudyFolderMetadata,
        result: inout StudyLibrarySyncApplyResult
    ) -> StudyFolderMetadata? {
        guard var existing else {
            return incoming
        }

        if incoming.updatedAt > existing.updatedAt {
            incoming.itemIDs = StudyItemMetadata.uniqueIDs(existing.itemIDs + incoming.itemIDs)
            incoming.childFolderIDs = StudyItemMetadata.uniqueIDs(existing.childFolderIDs + incoming.childFolderIDs)
            return incoming
        }

        if incoming.updatedAt == existing.updatedAt, incoming != existing {
            existing.itemIDs = StudyItemMetadata.uniqueIDs(existing.itemIDs + incoming.itemIDs)
            existing.childFolderIDs = StudyItemMetadata.uniqueIDs(existing.childFolderIDs + incoming.childFolderIDs)
            existing.syncConflictStatus = "conflict_preserved_local"
            result.conflictCount += 1
            return existing
        }

        result.skippedOlderCount += 1
        return nil
    }

    private func applySyncTombstone(_ tombstone: StudyLibrarySyncTombstone, remoteDeviceID: String) throws -> Bool {
        switch tombstone.entityKind {
        case .item:
            guard var item = editableMetadataIfAvailable(itemID: tombstone.entityID),
                  tombstone.updatedAt >= item.updatedAt else {
                return false
            }
            item.isTrashed = tombstone.operation == .trash || tombstone.operation == .delete || tombstone.operation == .deleteMetadataOnly
            item.trashedAt = item.isTrashed ? tombstone.updatedAt : nil
            item.updatedAt = tombstone.updatedAt
            item.modifiedByDeviceID = tombstone.modifiedByDeviceID ?? remoteDeviceID
            try save(item)
            return true
        case .folder:
            guard var folder = loadStoredFolder(folderID: tombstone.entityID),
                  tombstone.updatedAt >= folder.updatedAt else {
                return false
            }
            folder.isTrashed = tombstone.operation == .trash || tombstone.operation == .delete || tombstone.operation == .deleteMetadataOnly
            folder.trashedAt = folder.isTrashed ? tombstone.updatedAt : nil
            folder.updatedAt = tombstone.updatedAt
            folder.modifiedByDeviceID = tombstone.modifiedByDeviceID ?? remoteDeviceID
            try save(folder)
            return true
        }
    }

    private func markSyncMetadataOnlyIfNeeded(_ item: inout StudyItemMetadata) {
        guard let recordingID = item.recordingID,
              !recordingFileStore.loadInboxItems().contains(where: { $0.id == recordingID }) else {
            return
        }

        item.customProperties["syncedMetadataOnly"] = "true"
    }

    private func attachNoteSummaryPreview(to item: inout StudyItemMetadata) {
        item.customProperties.removeValue(forKey: "noteSummaryPreview")
        item.customProperties.removeValue(forKey: "noteKeyPointsPreview")

        guard let preview = noteStore.loadSummaryPreview(noteRelativePath: item.noteRelativePath),
              preview.isVisible else {
            return
        }

        let summary = preview.shortSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            item.customProperties["noteSummaryPreview"] = summary
        }

        let keyPoints = preview.keyPoints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
        if !keyPoints.isEmpty {
            item.customProperties["noteKeyPointsPreview"] = keyPoints.joined(separator: "\n")
        }
    }

    private func loadAllStoredItemMetadata() -> [StudyItemMetadata] {
        loadMetadataFiles(from: itemMetadataURL, as: StudyItemMetadata.self)
            + loadMetadataFiles(from: legacyItemMetadataURL, as: StudyItemMetadata.self)
    }

    private func loadAllFolderMetadata() -> [StudyFolderMetadata] {
        loadMetadataFiles(from: folderMetadataURL, as: StudyFolderMetadata.self)
    }

    private func loadStoredFolder(folderID: StudyFolderID) -> StudyFolderMetadata? {
        let index = loadIndex()
        var candidateFileNames = [
            index.folderMetadataFilesByFolderID[folderID],
            "\(StudyPathSanitizer.sanitizedPathComponent(folderID)).json"
        ].compactMap { $0 }
        candidateFileNames.append(contentsOf: loadMetadataFileNames(from: folderMetadataURL))

        for fileName in candidateFileNames.uniqueStable() {
            let url = folderMetadataURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
            guard isInsideFolderMetadataDirectory(url),
                  fileManager.fileExists(atPath: url.path),
                  let data = try? Data(contentsOf: url),
                  let folder = try? Self.jsonDecoder.decode(StudyFolderMetadata.self, from: data),
                  folder.folderID == folderID else {
                continue
            }

            return folder
        }

        return nil
    }

    private func loadMetadataFiles<T: Decodable>(from directoryURL: URL, as type: T.Type) -> [T] {
        loadMetadataFileNames(from: directoryURL).compactMap { fileName in
            let url = directoryURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
            guard isInsideStudyDirectory(url),
                  let data = try? Data(contentsOf: url) else {
                return nil
            }

            return try? Self.jsonDecoder.decode(T.self, from: data)
        }
    }

    private func loadMetadataFileNames(from directoryURL: URL) -> [String] {
        guard fileManager.fileExists(atPath: directoryURL.path),
              let urls = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "json" }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func repairedFolders(
        _ folders: [StudyFolderMetadata],
        items: [StudyItemMetadata]
    ) -> [StudyFolderMetadata] {
        let existingItemIDs = Set(items.map(\.itemID))
        var foldersByID = Dictionary(folders.map { ($0.folderID, $0) }, uniquingKeysWith: { first, _ in first })

        for (folderID, folder) in foldersByID {
            var repaired = folder
            repaired.itemIDs = StudyItemMetadata.uniqueIDs(repaired.itemIDs.filter { existingItemIDs.contains($0) })
            foldersByID[folderID] = repaired
        }

        for item in items {
            for folderID in item.folderIDs {
                guard var folder = foldersByID[folderID] else {
                    continue
                }

                if !folder.itemIDs.contains(item.itemID) {
                    folder.itemIDs.append(item.itemID)
                }
                foldersByID[folderID] = folder
            }
        }

        return foldersByID.values.sorted { left, right in
            if left.pathComponents == right.pathComponents {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }

            return left.pathComponents.lexicographicallyPrecedes(right.pathComponents) {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        }
    }

    private func syncFolderLinks(
        for metadata: StudyItemMetadata,
        previousMetadata: StudyItemMetadata?
    ) throws {
        var foldersByID = Dictionary(loadAllFolderMetadata().map { ($0.folderID, $0) }, uniquingKeysWith: { first, _ in first })
        let itemID = metadata.itemID
        let previousFolderIDs = Set(previousMetadata?.folderIDs ?? [])
        let targetFolderIDs = Set(metadata.folderIDs)

        for folderID in previousFolderIDs.subtracting(targetFolderIDs) {
            guard var folder = foldersByID[folderID] else {
                continue
            }

            folder.itemIDs.removeAll { $0 == itemID }
            folder.updatedAt = Date()
            foldersByID[folderID] = folder
        }

        let chain = folderChain(for: metadata.filing, itemID: itemID)
        for folder in chain {
            var stored = foldersByID[folder.folderID] ?? folder
            stored.name = folder.name
            stored.level = folder.level
            stored.path = folder.path
            stored.parentFolderID = folder.parentFolderID
            stored.childFolderIDs = StudyItemMetadata.uniqueIDs(stored.childFolderIDs + folder.childFolderIDs)
            if targetFolderIDs.contains(folder.folderID), !stored.itemIDs.contains(itemID) {
                stored.itemIDs.append(itemID)
            }
            if !targetFolderIDs.contains(folder.folderID) {
                stored.itemIDs.removeAll { $0 == itemID }
            }
            stored.updatedAt = Date()
            foldersByID[folder.folderID] = stored
        }

        for folderID in targetFolderIDs {
            guard var folder = foldersByID[folderID] else {
                continue
            }

            if !folder.itemIDs.contains(itemID) {
                folder.itemIDs.append(itemID)
            }
            folder.updatedAt = Date()
            foldersByID[folderID] = folder
        }

        for folder in foldersByID.values {
            try save(folder)
        }
    }

    private func folderChain(for filing: StudyFilingPath, itemID: StudyItemID?) -> [StudyFolderMetadata] {
        let effectiveFiling = effectiveFilingPath(for: filing)
        let values: [(StudyFolderLevel, String?)] = [
            (.type, effectiveFiling.type),
            (.subject, effectiveFiling.subject),
            (.chapter, effectiveFiling.chapter),
            (.topic, effectiveFiling.topic)
        ]

        var folders: [StudyFolderMetadata] = []
        var parentFolderID: StudyFolderID?
        for index in values.indices {
            let (level, value) = values[index]
            guard let value else {
                break
            }

            let components = values.prefix(index + 1).compactMap { $0.1 }
            let path = StudyFolderMetadata.filingPath(for: components)
            let childFolderIDs: [StudyFolderID]
            if index + 1 < values.count,
               values[index + 1].1 != nil {
                let childPath = StudyFolderMetadata.filingPath(for: values.prefix(index + 2).compactMap { $0.1 })
                childFolderIDs = [StudyFolderMetadata.folderID(for: values[index + 1].0, path: childPath)]
            } else {
                childFolderIDs = []
            }
            let isLeaf = index == values.prefix { $0.1 != nil }.count - 1
            folders.append(StudyFolderMetadata(
                name: value,
                level: level,
                path: path,
                parentFolderID: parentFolderID,
                childFolderIDs: childFolderIDs,
                itemIDs: isLeaf ? itemID.map { [$0] } ?? [] : []
            ))
            parentFolderID = folders.last?.folderID
        }

        return folders
    }

    private func effectiveFilingPath(for filing: StudyFilingPath) -> StudyFilingPath {
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

    private func parentFolderID(for path: StudyBrowsePath) -> StudyFolderID? {
        guard !path.isRoot,
              let parentLevel = StudyFolderMetadata.level(forDepth: path.depth - 1) else {
            return nil
        }

        return StudyFolderMetadata.folderID(
            for: parentLevel,
            path: StudyFolderMetadata.filingPath(for: path.components)
        )
    }

    private func appendChildFolderID(
        _ childFolderID: StudyFolderID,
        toParentFolderID parentFolderID: StudyFolderID,
        parentPath: StudyBrowsePath
    ) throws {
        guard let parentLevel = StudyFolderMetadata.level(forDepth: parentPath.depth - 1) else {
            return
        }

        var parent = loadStoredFolder(folderID: parentFolderID) ?? StudyFolderMetadata(
            name: parentPath.components.last ?? StudyHierarchyRule.uncategorizedValue,
            level: parentLevel,
            path: StudyFolderMetadata.filingPath(for: parentPath.components),
            parentFolderID: self.parentFolderID(for: parentPath.parent)
        )
        if !parent.childFolderIDs.contains(childFolderID) {
            parent.childFolderIDs.append(childFolderID)
            parent.updatedAt = Date()
            try save(parent)
        }
    }

    private func pathComponents(_ components: [String], startWith prefix: [String]) -> Bool {
        guard components.count >= prefix.count else {
            return false
        }

        return Array(components.prefix(prefix.count)) == prefix
    }

    private func item(_ item: StudyItemMetadata, matches folderPath: StudyFilingPath, through level: StudyFolderLevel) -> Bool {
        StudyFolderMetadata.pathComponents(for: item.filing, through: level) == StudyFolderMetadata.pathComponents(for: folderPath, through: level)
    }

    private func renamedPath(
        _ path: StudyFilingPath,
        replacing level: StudyFolderLevel,
        with name: String
    ) -> StudyFilingPath? {
        switch level {
        case .type:
            guard path.type != nil else { return nil }
            return StudyFilingPath(type: name, subject: path.subject, chapter: path.chapter, topic: path.topic)
        case .subject:
            guard path.subject != nil else { return nil }
            return StudyFilingPath(type: path.type, subject: name, chapter: path.chapter, topic: path.topic)
        case .chapter:
            guard path.chapter != nil else { return nil }
            return StudyFilingPath(type: path.type, subject: path.subject, chapter: name, topic: path.topic)
        case .topic:
            guard path.topic != nil else { return nil }
            return StudyFilingPath(type: path.type, subject: path.subject, chapter: path.chapter, topic: name)
        case .custom:
            return nil
        }
    }

    private func ensureStudyDirectories() throws {
        guard isInsideRoot(studyURL),
              isInsideStudyDirectory(itemMetadataURL),
              isInsideStudyDirectory(folderMetadataURL),
              isInsideStudyDirectory(indexURL),
              isInsideStudyDirectory(hierarchyRulesURL),
              isInsideStudyDirectory(legacyItemMetadataURL),
              isInsideStudyDirectory(legacyIndexURL) else {
            throw StudyLibraryStoreError.unsafeDestination
        }

        do {
            try fileManager.createDirectory(at: itemMetadataURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: folderMetadataURL, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: hierarchyRulesURL.path) {
                try Self.jsonEncoder.encode([StudyHierarchyRule.defaultCourseView]).write(to: hierarchyRulesURL, options: .atomic)
            }
            if !fileManager.fileExists(atPath: indexURL.path) {
                try Self.jsonEncoder.encode(StudyMetadataIndex()).write(to: indexURL, options: .atomic)
            }
        } catch {
            throw StudyLibraryStoreError.unableToCreateDirectory
        }
    }

    private func loadHierarchyRules() -> [StudyHierarchyRule] {
        guard fileManager.fileExists(atPath: hierarchyRulesURL.path),
              let data = try? Data(contentsOf: hierarchyRulesURL),
              let rules = try? Self.jsonDecoder.decode([StudyHierarchyRule].self, from: data),
              !rules.isEmpty else {
            return [.defaultCourseView]
        }

        return rules.map { rule in
            if rule.id == StudyHierarchyRule.defaultCourseView.id,
               rule.levels != StudyHierarchyRule.defaultCourseView.levels {
                return .defaultCourseView
            }

            return rule
        }
    }

    private func loadIndex() -> StudyMetadataIndex {
        let urls = [indexURL, legacyIndexURL]
        for url in urls where fileManager.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let index = try? Self.jsonDecoder.decode(StudyMetadataIndex.self, from: data) else {
                continue
            }

            return index
        }

        return StudyMetadataIndex()
    }

    private func saveIndex(_ index: StudyMetadataIndex) throws {
        guard isInsideStudyDirectory(indexURL) else {
            throw StudyLibraryStoreError.unsafeDestination
        }

        try Self.jsonEncoder.encode(index).write(to: indexURL, options: .atomic)
    }

    private func itemMetadataFileName(for metadata: StudyItemMetadata) -> String {
        "\(StudyPathSanitizer.sanitizedPathComponent(metadata.itemID)).json"
    }

    private func folderMetadataFileName(for folder: StudyFolderMetadata) -> String {
        "\(StudyPathSanitizer.sanitizedPathComponent(folder.folderID)).json"
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func isInsideStudyDirectory(_ url: URL) -> Bool {
        let studyPath = studyURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == studyPath || path.hasPrefix(studyPath + "/")
    }

    private func isInsideItemMetadataDirectory(_ url: URL) -> Bool {
        let itemMetadataPath = itemMetadataURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == itemMetadataPath || path.hasPrefix(itemMetadataPath + "/")
    }

    private func isInsideFolderMetadataDirectory(_ url: URL) -> Bool {
        let folderMetadataPath = folderMetadataURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == folderMetadataPath || path.hasPrefix(folderMetadataPath + "/")
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Array where Element == String {
    func uniqueStable() -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for value in self {
            guard !seen.contains(value) else {
                continue
            }

            seen.insert(value)
            result.append(value)
        }

        return result
    }
}
