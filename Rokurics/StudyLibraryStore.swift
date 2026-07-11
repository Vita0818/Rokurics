//
//  StudyLibraryStore.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
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

enum CanonicalEffectiveReadCacheReason: String {
    case readRuntimeResultChanged
    case readRuntimeConfigChanged
    case legacyBackingChanged
    case explicitRefresh
    case fallbackStateChanged
    case cacheMiss
}

struct CanonicalEffectiveReadCacheMetrics: Equatable {
    var projectionRebuildCount = 0
    var treeRebuildCount = 0
    var cacheHitCount = 0
    var cacheMissCount = 0
    var cacheInvalidationCount = 0
    var fallbackLegacyCount = 0
    var repeatedAccessCount = 0
    var itemProjectionBuildCount = 0
    var folderProjectionBuildCount = 0
    var lastRebuildReason: String?
    var lastRebuildDurationMs: Int?
    var lastReadSource: String?

    var diagnosticsSummary: String {
        [
            "projectionRebuildCount=\(projectionRebuildCount)",
            "treeRebuildCount=\(treeRebuildCount)",
            "cacheHitCount=\(cacheHitCount)",
            "cacheMissCount=\(cacheMissCount)",
            "cacheInvalidationCount=\(cacheInvalidationCount)",
            "fallbackLegacyCount=\(fallbackLegacyCount)",
            "repeatedAccessCount=\(repeatedAccessCount)",
            "itemProjectionBuildCount=\(itemProjectionBuildCount)",
            "folderProjectionBuildCount=\(folderProjectionBuildCount)",
            lastRebuildReason.map { "lastRebuildReason=\($0)" },
            lastRebuildDurationMs.map { "lastRebuildDurationMs=\($0)" },
            lastReadSource.map { "lastReadSource=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }
}

private struct CanonicalEffectiveStudyCacheKey: Equatable {
    var mode: CanonicalReadRuntimeMode
    var returnedSource: CanonicalReadProjectionSource
    var fallback: CanonicalReadRuntimeFallback
    var canonicalReadServed: Bool
    var legacyBackingRevision: Int
    var snapshotSignature: String
    var divergenceSignature: String
}

private struct CanonicalEffectiveStudyProjection {
    var key: CanonicalEffectiveStudyCacheKey
    var items: [StudyItemMetadata]
    var folders: [StudyFolderMetadata]
    var source: CanonicalReadProjectionSource
    var divergenceCount: Int
    var rebuildReason: CanonicalEffectiveReadCacheReason
    var rebuildDurationMs: Int
}

@MainActor
final class StudyLibraryStore: ObservableObject {
    @Published private(set) var allStudyItems: [StudyItemMetadata] = []
    @Published private(set) var allStudyFolders: [StudyFolderMetadata] = []
    @Published private(set) var hierarchyRules: [StudyHierarchyRule] = [.defaultCourseView]
    @Published private(set) var selectedHierarchyRule: StudyHierarchyRule = .defaultCourseView
    @Published private(set) var filingCandidates: StudyFilingCandidates = .empty
    @Published private(set) var canonicalReadRuntimeResult: CanonicalReadRuntimeResult?
    @Published private(set) var canonicalReadRuntimeReturnedSource: CanonicalReadProjectionSource = .legacy
    @Published private(set) var canonicalReadRuntimeLastDiagnostics: [CanonicalReadRuntimeDiagnostic] = []
    @Published private(set) var effectiveSyncStatusByObjectID: [CanonicalObjectID: CanonicalEffectiveSyncStatus] = [:]

    private let fileManager: FileManager
    private let rootURL: URL
    private let studyURL: URL
    private let itemMetadataURL: URL
    private let folderMetadataURL: URL
    private let indexURL: URL
    private let hierarchyRulesURL: URL
    private let legacyItemMetadataURL: URL
    private let legacyIndexURL: URL
    private let audioFileStore: AudioFileStore
    private var canonicalReadRuntimeConfigurationOverride: CanonicalReadRuntimeConfiguration?
    private var canonicalReadRuntimeUsesMasterSwitchConfiguration = false
    private var canonicalReadRuntimeCanonicalManifest: CanonicalManifest?
    private var canonicalReadRuntimePeerManifest: CanonicalManifest?
    private var canonicalReadRuntimeUploadCandidates: [CanonicalAudioUploadCutoverCandidate] = []
    private var canonicalReadRuntimeSyncResult: CanonicalSyncRuntimeResult?
    private var canonicalReadRuntimeSyncRunID: String?
    private var canonicalKernelSwitchObserver: NSObjectProtocol?
    private var canonicalEffectiveReadCache: CanonicalEffectiveStudyProjection?
    private var canonicalEffectiveReadCacheMetrics = CanonicalEffectiveReadCacheMetrics()
    private var canonicalEffectiveReadCacheDiagnostics: [CanonicalReadRuntimeDiagnostic] = []
    private var canonicalFileRuntimeDiagnostics: [CanonicalKernelDiagnosticRecord] = []
    private var canonicalEffectiveReadLegacyRevision = 0
    private let canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime
    private var effectiveSyncStatusCacheByObjectID: [CanonicalObjectID: CanonicalEffectiveSyncStatus] = [:]
    private var effectiveSyncStatusPublishTask: Task<Void, Never>?
    private var storePublishCounterCancellable: AnyCancellable?

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        audioFileStore: AudioFileStore? = nil,
        canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime? = nil
    ) {
        self.fileManager = fileManager
        self.audioFileStore = audioFileStore ?? AudioFileStore(fileManager: fileManager, rootDirectoryURL: rootURL)
        self.canonicalStatusTruthRuntime = canonicalStatusTruthRuntime ?? CanonicalStatusTruthRuntime()

        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else if let resolvedRoot = try? self.audioFileStore.baseDirectory() {
            self.rootURL = resolvedRoot.standardizedFileURL
        } else {
            let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.rootURL = documentsURL
                .appendingPathComponent("Rokurics", isDirectory: true)
                .standardizedFileURL
        }

        studyURL = self.rootURL
            .appendingPathComponent("study", isDirectory: true)
            .standardizedFileURL
        itemMetadataURL = studyURL
            .appendingPathComponent("items", isDirectory: true)
            .standardizedFileURL
        folderMetadataURL = studyURL
            .appendingPathComponent("folders", isDirectory: true)
            .standardizedFileURL
        indexURL = studyURL
            .appendingPathComponent("index.json", isDirectory: false)
            .standardizedFileURL
        hierarchyRulesURL = studyURL
            .appendingPathComponent("hierarchy-rules.json", isDirectory: false)
            .standardizedFileURL
        legacyItemMetadataURL = studyURL
            .appendingPathComponent("item-metadata", isDirectory: true)
            .standardizedFileURL
        legacyIndexURL = studyURL
            .appendingPathComponent("study-index.json", isDirectory: false)
            .standardizedFileURL

        startPublishCounter(scope: "iPhoneStudyLibraryStore")

        try? ensureStudyDirectories()
        updatePublished(\.hierarchyRules, to: loadHierarchyRules())
        updatePublished(\.selectedHierarchyRule, to: hierarchyRules.first ?? .defaultCourseView)
        refresh()

        canonicalKernelSwitchObserver = NotificationCenter.default.addObserver(
            forName: CanonicalKernelSwitchConfiguration.didChangeNotificationName,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(forceCanonicalReadRuntimeProjection: true)
            }
        }
    }

    deinit {
        if let canonicalKernelSwitchObserver {
            NotificationCenter.default.removeObserver(canonicalKernelSwitchObserver)
        }
        effectiveSyncStatusPublishTask?.cancel()
    }

    var libraryRootURL: URL {
        rootURL
    }

    var studyRootDisplayPath: String {
        studyURL.path
    }

    var canonicalReadRuntimeConfigurationOverrideIsSet: Bool {
        canonicalReadRuntimeConfigurationOverride != nil
    }

    var canonicalReadEffectiveCacheMetrics: CanonicalEffectiveReadCacheMetrics {
        canonicalEffectiveReadCacheMetrics
    }

    var canonicalReadEffectiveCacheDiagnosticEvents: [CanonicalReadRuntimeDiagnostic] {
        canonicalEffectiveReadCacheDiagnostics
    }

    var canonicalFileRuntimeDiagnosticRecords: [CanonicalKernelDiagnosticRecord] {
        canonicalFileRuntimeDiagnostics
    }

    var canonicalStatusTruthReadPathAvailable: Bool {
        true
    }

    func produceCanonicalStatusFact(_ fact: CanonicalStatusFact) async -> CanonicalStatusFactMergeResult {
        let result = await canonicalStatusTruthRuntime.produce(fact)
        await refreshEffectiveSyncStatusSnapshot(for: fact.objectID)
        return result
    }

    func applyCanonicalStatusProjection(_ snapshot: CanonicalStatusProjectionSnapshot) {
        applyEffectiveSyncStatusUpdates([snapshot.objectID: snapshot.effectiveStatus])
    }

    func effectiveSyncStatus(for objectID: CanonicalObjectID) -> CanonicalEffectiveSyncStatus? {
        effectiveSyncStatusCacheByObjectID[objectID] ?? effectiveSyncStatusByObjectID[objectID]
    }

    func canonicalDisplaySyncState(for objectID: CanonicalObjectID) -> CanonicalDisplaySyncState? {
        effectiveSyncStatus(for: objectID).map(CanonicalEffectiveStatusUIProjection.project(_:))
    }

    var effectiveStudyItems: [StudyItemMetadata] {
        guard let result = canonicalReadRuntimeResult,
              result.canonicalReadServed else {
            return allStudyItems
        }
        return canonicalEffectiveProjection(for: result, reason: .cacheMiss)?.items ?? allStudyItems
    }

    var effectiveStudyFolders: [StudyFolderMetadata] {
        guard let result = canonicalReadRuntimeResult,
              result.canonicalReadServed else {
            return allStudyFolders
        }
        return canonicalEffectiveProjection(for: result, reason: .cacheMiss)?.folders ?? allStudyFolders
    }

    func refresh(forceCanonicalReadRuntimeProjection: Bool = false) {
        let recordings = (try? audioFileStore.loadAllMetadata()) ?? []
        let recordingsWithLocalAudio = Set(recordings.compactMap { recording -> String? in
            guard let audioURL = try? audioFileStore.audioURL(for: recording),
                  fileManager.fileExists(atPath: audioURL.path) else {
                return nil
            }
            return recording.id
        })
        var storedItems = loadAllStoredItemMetadata()
        for index in storedItems.indices {
            guard let recordingID = storedItems[index].recordingID,
                  recordingsWithLocalAudio.contains(recordingID),
                  storedItems[index].customProperties["syncedMetadataOnly"] == "true" else {
                continue
            }
            storedItems[index].customProperties.removeValue(forKey: "syncedMetadataOnly")
            try? writeItemMetadataPreservingFolderLinks(storedItems[index])
        }
        let receiveItems = loadReceiveRecordDerivedItems()
        let storedItemsByRecordingID = Dictionary(
            storedItems.compactMap { item -> (String, StudyItemMetadata)? in
                guard let recordingID = item.recordingID else {
                    return nil
                }
                return (recordingID, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let liveRecordingIDs = Set(recordings.map(\.id))

        var itemsByID: [StudyItemID: StudyItemMetadata] = [:]
        for recording in recordings {
            let fallback = StudyItemMetadata.defaultMetadata(for: recording)
            let metadata = storedItemsByRecordingID[recording.id]?.mergedWithCurrentRecording(recording) ?? fallback
            itemsByID[metadata.itemID] = metadata
        }

        for item in receiveItems where item.recordingID.map({ !liveRecordingIDs.contains($0) }) ?? true {
            itemsByID[item.itemID] = item
        }

        for item in storedItems where shouldIncludeStoredItem(item, liveRecordingIDs: liveRecordingIDs, alreadyLoaded: itemsByID) {
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

        var backingChanged = false
        backingChanged = updatePublished(\.allStudyItems, to: items) || backingChanged
        backingChanged = updatePublished(\.allStudyFolders, to: folders) || backingChanged
        backingChanged = updatePublished(\.filingCandidates, to: StudyFilingCandidates.collect(from: items)) || backingChanged

        if backingChanged {
            canonicalEffectiveReadLegacyRevision += 1
            refreshCanonicalReadRuntimeProjection(cacheRebuildReason: .explicitRefresh)
        } else if forceCanonicalReadRuntimeProjection {
            refreshCanonicalReadRuntimeProjection(cacheRebuildReason: .readRuntimeConfigChanged)
        }
    }

    func item(recordingID: String) -> StudyItemMetadata? {
        effectiveStudyItems.first { $0.recordingID == recordingID }
    }

    func item(itemID: StudyItemID) -> StudyItemMetadata? {
        effectiveStudyItems.first { $0.itemID == itemID || $0.recordingID == itemID }
    }

    @discardableResult
    func setCanonicalReadRuntimeConfiguration(
        _ configuration: CanonicalReadRuntimeConfiguration?
    ) -> CanonicalReadRuntimeResult {
        canonicalReadRuntimeUsesMasterSwitchConfiguration = true
        canonicalReadRuntimeConfigurationOverride = Self.servingReadConfiguration(configuration)
        return refreshCanonicalReadRuntimeProjection(cacheRebuildReason: .readRuntimeConfigChanged)
    }

    @discardableResult
    func configureCanonicalReadRuntime(
        configuration: CanonicalReadRuntimeConfiguration,
        canonicalManifest: CanonicalManifest?,
        peerCanonicalManifest: CanonicalManifest? = nil,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = [],
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalReadRuntimeResult {
        canonicalReadRuntimeUsesMasterSwitchConfiguration = configuration.mode == .disabled || configuration.mode == .blocked
        canonicalReadRuntimeConfigurationOverride = Self.servingReadConfiguration(configuration)
        canonicalReadRuntimeCanonicalManifest = canonicalManifest
        canonicalReadRuntimePeerManifest = peerCanonicalManifest
        canonicalReadRuntimeUploadCandidates = uploadCandidates
        canonicalReadRuntimeSyncResult = syncRuntimeResult
        canonicalReadRuntimeSyncRunID = syncRunID
        return refreshCanonicalReadRuntimeProjection(
            canonicalReadFailureReason: canonicalReadFailureReason,
            cacheRebuildReason: .readRuntimeResultChanged
        )
    }

    @discardableResult
    func configureCanonicalReadRuntimeFromSync(
        configuration: CanonicalReadRuntimeConfiguration,
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory?,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = [],
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalReadRuntimeResult {
        canonicalReadRuntimeUsesMasterSwitchConfiguration = configuration.mode == .disabled || configuration.mode == .blocked
        canonicalReadRuntimeConfigurationOverride = Self.servingReadConfiguration(configuration)
        canonicalReadRuntimeCanonicalManifest = localInventory.canonicalManifest
        canonicalReadRuntimePeerManifest = peerInventory?.canonicalManifest
        canonicalReadRuntimeUploadCandidates = uploadCandidates
        canonicalReadRuntimeSyncResult = syncRuntimeResult
        canonicalReadRuntimeSyncRunID = syncRunID
        let result = IPhoneCanonicalReadRuntimeAdapter(configuration: configuration).read(
            legacyInventory: localInventory,
            canonicalManifest: localInventory.canonicalManifest,
            peerCanonicalManifest: peerInventory?.canonicalManifest,
            uploadCandidates: uploadCandidates,
            syncRuntimeResult: syncRuntimeResult,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
        applyCanonicalReadRuntimeResult(result, cacheRebuildReason: .readRuntimeResultChanged)
        return result
    }

    func clearCanonicalReadRuntimeOverride() {
        canonicalReadRuntimeUsesMasterSwitchConfiguration = false
        canonicalReadRuntimeConfigurationOverride = nil
        canonicalReadRuntimeCanonicalManifest = nil
        canonicalReadRuntimePeerManifest = nil
        canonicalReadRuntimeUploadCandidates = []
        canonicalReadRuntimeSyncResult = nil
        canonicalReadRuntimeSyncRunID = nil
        refreshCanonicalReadRuntimeProjection(cacheRebuildReason: .readRuntimeConfigChanged)
    }

    @discardableResult
    func refreshCanonicalReadRuntimeProjection(
        canonicalReadFailureReason: String? = nil,
        cacheRebuildReason: CanonicalEffectiveReadCacheReason = .readRuntimeResultChanged
    ) -> CanonicalReadRuntimeResult {
        let configuration = resolvedCanonicalReadRuntimeConfiguration()
        let legacyManifest = makeReadRuntimeLegacyManifest(
            deviceID: "iphone-local-read",
            generatedAt: Date()
        )
        let canonicalManifest = canonicalReadRuntimeCanonicalManifest
            ?? IPhoneCanonicalReadRuntimeAdapter.makeCanonicalManifest(legacyManifest)
        let result = IPhoneCanonicalReadRuntimeAdapter(configuration: configuration).read(
            legacyManifest: legacyManifest,
            canonicalManifest: canonicalManifest,
            peerCanonicalManifest: canonicalReadRuntimePeerManifest,
            uploadCandidates: canonicalReadRuntimeUploadCandidates,
            syncRuntimeResult: canonicalReadRuntimeSyncResult,
            syncRunID: canonicalReadRuntimeSyncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
        applyCanonicalReadRuntimeResult(result, cacheRebuildReason: cacheRebuildReason)
        return result
    }

    private func applyCanonicalReadRuntimeResult(
        _ result: CanonicalReadRuntimeResult,
        cacheRebuildReason: CanonicalEffectiveReadCacheReason
    ) {
        updatePublished(\.canonicalReadRuntimeResult, to: result)
        updatePublished(\.canonicalReadRuntimeReturnedSource, to: result.returnedSource)
        updatePublished(\.canonicalReadRuntimeLastDiagnostics, to: result.diagnostics)
        refreshCanonicalEffectiveReadCache(for: result, reason: cacheRebuildReason)
    }

    private func refreshEffectiveSyncStatusSnapshot(for objectID: CanonicalObjectID) async {
        guard let snapshot = await canonicalStatusTruthRuntime.projectionSnapshot(for: objectID) else {
            return
        }
        applyEffectiveSyncStatusUpdates([objectID: snapshot.effectiveStatus])
    }

    @discardableResult
    private func updatePublished<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<StudyLibraryStore, Value>,
        to newValue: Value
    ) -> Bool {
        guard self[keyPath: keyPath] != newValue else {
            return false
        }
        self[keyPath: keyPath] = newValue
        return true
    }

    private func applyEffectiveSyncStatusUpdates(
        _ updates: [CanonicalObjectID: CanonicalEffectiveSyncStatus]
    ) {
        guard updates.isEmpty == false else {
            return
        }
        var changed = false
        for (objectID, status) in updates {
            guard effectiveSyncStatusCacheByObjectID[objectID] != status else {
                continue
            }
            effectiveSyncStatusCacheByObjectID[objectID] = status
            changed = true
        }
        guard changed else {
            return
        }
        scheduleEffectiveSyncStatusPublish()
    }

    private func scheduleEffectiveSyncStatusPublish() {
        effectiveSyncStatusPublishTask?.cancel()
        effectiveSyncStatusPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else {
                return
            }
            self?.publishEffectiveSyncStatusSnapshotIfChanged()
        }
    }

    private func publishEffectiveSyncStatusSnapshotIfChanged() {
        effectiveSyncStatusPublishTask = nil
        updatePublished(\.effectiveSyncStatusByObjectID, to: effectiveSyncStatusCacheByObjectID)
    }

    private func startPublishCounter(scope: String) {
        storePublishCounterCancellable = objectWillChange.sink { [weak self] _ in
            self?.recordPublishCounterTick(scope: scope)
        }
    }

    private func recordPublishCounterTick(scope: String) {
        ConnectionDiagnosticsStore.shared.recordRuntimeCounterTick(scope: scope, kind: "published")
    }

    private func refreshCanonicalEffectiveReadCache(
        for result: CanonicalReadRuntimeResult,
        reason: CanonicalEffectiveReadCacheReason
    ) {
        guard result.canonicalReadServed else {
            invalidateCanonicalEffectiveReadCache(reason: reason == .readRuntimeConfigChanged ? .readRuntimeConfigChanged : .fallbackStateChanged)
            if result.legacyFallbackServed || result.returnedSource == .legacy {
                canonicalEffectiveReadCacheMetrics.fallbackLegacyCount += 1
                canonicalEffectiveReadCacheMetrics.lastReadSource = CanonicalReadProjectionSource.legacy.rawValue
                recordCanonicalEffectiveReadCacheDiagnostic(
                    .canonicalReadEffectiveFallbackLegacy,
                    count: canonicalEffectiveReadCacheMetrics.fallbackLegacyCount,
                    detail: result.fallback.rawValue
                )
            }
            return
        }

        let key = canonicalEffectiveCacheKey(for: result)
        if canonicalEffectiveReadCache?.key == key {
            return
        }

        if canonicalEffectiveReadCache != nil {
            invalidateCanonicalEffectiveReadCache(reason: reason)
        } else {
            canonicalEffectiveReadCacheMetrics.cacheMissCount += 1
            recordCanonicalEffectiveReadCacheDiagnostic(
                .canonicalReadEffectiveCacheMiss,
                count: canonicalEffectiveReadCacheMetrics.cacheMissCount,
                detail: reason.rawValue
            )
        }

        let startedAt = Date()
        let items = canonicalEffectiveStudyItems(from: result.readSnapshot)
        canonicalEffectiveReadCacheMetrics.itemProjectionBuildCount += 1
        let folders = canonicalEffectiveStudyFolders(from: result.readSnapshot, items: items)
        canonicalEffectiveReadCacheMetrics.folderProjectionBuildCount += 1
        let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))

        canonicalEffectiveReadCacheMetrics.projectionRebuildCount += 1
        canonicalEffectiveReadCacheMetrics.lastRebuildReason = reason.rawValue
        canonicalEffectiveReadCacheMetrics.lastRebuildDurationMs = durationMs
        canonicalEffectiveReadCacheMetrics.lastReadSource = result.returnedSource.rawValue
        canonicalEffectiveReadCache = CanonicalEffectiveStudyProjection(
            key: key,
            items: items,
            folders: folders,
            source: result.returnedSource,
            divergenceCount: result.diff?.divergenceCount ?? 0,
            rebuildReason: reason,
            rebuildDurationMs: durationMs
        )
        recordCanonicalEffectiveReadCacheDiagnostic(
            .canonicalReadEffectiveCacheRebuilt,
            count: canonicalEffectiveReadCacheMetrics.projectionRebuildCount,
            detail: reason.rawValue
        )
        recordCanonicalEffectiveReadCacheDiagnostic(
            .canonicalReadEffectiveRebuildDurationMs,
            count: durationMs,
            detail: reason.rawValue
        )
        recordCanonicalFileRuntimeReadProjectionDiagnostic(
            durationMs: durationMs,
            count: canonicalEffectiveReadCacheMetrics.projectionRebuildCount,
            key: key,
            reason: reason
        )
        ConnectionDiagnosticsStore.shared.recordPerfLog(
            CanonicalPerfLog.subphaseMeasured(
                operation: .enterStudyLibrary,
                subphase: .projectionRebuildMs,
                durationMs: durationMs,
                result: reason.rawValue
            )
        )
    }

    private func canonicalEffectiveProjection(
        for result: CanonicalReadRuntimeResult,
        reason: CanonicalEffectiveReadCacheReason
    ) -> CanonicalEffectiveStudyProjection? {
        let key = canonicalEffectiveCacheKey(for: result)
        if let cache = canonicalEffectiveReadCache, cache.key == key {
            canonicalEffectiveReadCacheMetrics.cacheHitCount += 1
            canonicalEffectiveReadCacheMetrics.lastReadSource = cache.source.rawValue
            recordCanonicalEffectiveReadCacheDiagnostic(
                .canonicalReadEffectiveCacheHit,
                count: canonicalEffectiveReadCacheMetrics.cacheHitCount,
                detail: cache.rebuildReason.rawValue
            )
            if canonicalEffectiveReadCacheMetrics.cacheHitCount > canonicalEffectiveReadCacheMetrics.projectionRebuildCount {
                canonicalEffectiveReadCacheMetrics.repeatedAccessCount += 1
                recordCanonicalEffectiveReadCacheDiagnostic(
                    .canonicalReadEffectiveRepeatedAccessAvoidedRebuild,
                    count: canonicalEffectiveReadCacheMetrics.repeatedAccessCount,
                    detail: "sameCacheKey"
                )
            }
            return cache
        }
        if canonicalEffectiveReadCache != nil {
            refreshCanonicalEffectiveReadCache(for: result, reason: reason)
            return canonicalEffectiveReadCache
        }

        canonicalEffectiveReadCacheMetrics.cacheMissCount += 1
        recordCanonicalEffectiveReadCacheDiagnostic(
            .canonicalReadEffectiveCacheMiss,
            count: canonicalEffectiveReadCacheMetrics.cacheMissCount,
            detail: reason.rawValue
        )
        refreshCanonicalEffectiveReadCache(for: result, reason: reason)
        return canonicalEffectiveReadCache
    }

    private func invalidateCanonicalEffectiveReadCache(reason: CanonicalEffectiveReadCacheReason) {
        guard let cache = canonicalEffectiveReadCache else {
            return
        }
        canonicalEffectiveReadCache = nil
        canonicalEffectiveReadCacheMetrics.cacheInvalidationCount += 1
        canonicalEffectiveReadCacheMetrics.lastRebuildReason = reason.rawValue
        recordCanonicalEffectiveReadCacheDiagnostic(
            .canonicalReadEffectiveCacheInvalidated,
            count: canonicalEffectiveReadCacheMetrics.cacheInvalidationCount,
            detail: reason.rawValue
        )
        recordCanonicalFileRuntimeReadProjectionDiagnostic(
            durationMs: nil,
            count: canonicalEffectiveReadCacheMetrics.cacheInvalidationCount,
            key: cache.key,
            reason: reason,
            extra: "invalidation=true"
        )
    }

    private func canonicalEffectiveCacheKey(
        for result: CanonicalReadRuntimeResult
    ) -> CanonicalEffectiveStudyCacheKey {
        CanonicalEffectiveStudyCacheKey(
            mode: result.mode,
            returnedSource: result.returnedSource,
            fallback: result.fallback,
            canonicalReadServed: result.canonicalReadServed,
            legacyBackingRevision: canonicalEffectiveReadLegacyRevision,
            snapshotSignature: Self.canonicalReadSnapshotSignature(result.readSnapshot),
            divergenceSignature: result.diff?.divergences.map(\.id).sorted().joined(separator: "|") ?? "none"
        )
    }

    private nonisolated static func canonicalReadSnapshotSignature(_ snapshot: CanonicalReadSnapshot) -> String {
        [
            "source=\(snapshot.source.rawValue)",
            "recordings=\(snapshot.recordingMetadata.records.map(recordingSignature).joined(separator: ";"))",
            "folders=\(snapshot.libraryMetadata.snapshot.folders.map(folderSignature).joined(separator: ";"))",
            "items=\(snapshot.libraryMetadata.snapshot.studyItems.map(studyItemSignature).joined(separator: ";"))",
            "notes=\(snapshot.libraryMetadata.snapshot.standaloneNotes.map(standaloneNoteSignature).joined(separator: ";"))",
            "artifactItems=\(snapshot.artifactMetadata.snapshot.items.map(artifactSignature).joined(separator: ";"))",
            "artifactFailures=\(snapshot.artifactMetadata.snapshot.failures.map(\.id).joined(separator: ";"))",
            "conflicts=\(snapshot.conflictState.snapshot.items.map(conflictSignature).joined(separator: ";"))",
            "conflictFailures=\(snapshot.conflictState.snapshot.failures.map(\.id).joined(separator: ";"))",
            "uploads=\(snapshot.uploadState.records.map(uploadSignature).joined(separator: ";"))",
            "uploadFailures=\(snapshot.uploadState.failures.map(\.id).joined(separator: ";"))",
            "sync=\(syncStatusSignature(snapshot.syncStatus))",
            "redacted=\(snapshot.redaction.isRedacted)"
        ].joined(separator: "|")
    }

    private nonisolated static func recordingSignature(_ record: CanonicalRecordingReadProjectionRecord) -> String {
        [
            record.objectID,
            record.metadataHashPrefix ?? "metadataHash=none",
            record.title,
            record.tagsKey,
            "\(record.durationSeconds ?? -1)",
            "\(record.isDeleted)",
            record.syncState.rawValue
        ].joined(separator: ":")
    }

    private nonisolated static func folderSignature(_ folder: CanonicalLibraryMetadataReadProjectionFolder) -> String {
        [
            folder.folderID.rawValue,
            folder.metadataHashPrefix ?? "metadataHash=none",
            folder.title,
            folder.parentID?.rawValue ?? "root",
            folder.hierarchyPath.joined(separator: "/"),
            folder.hierarchyLevel ?? "none",
            folder.colorToken ?? "none",
            folder.orderingKey ?? "ordering=none",
            "\(folder.isDeleted)"
        ].joined(separator: ":")
    }

    private nonisolated static func studyItemSignature(_ item: CanonicalLibraryMetadataReadProjectionItem) -> String {
        [
            item.itemID.rawValue,
            item.metadataHashPrefix ?? "metadataHash=none",
            item.itemKind.rawValue,
            item.title,
            item.filingComponents.joined(separator: "/"),
            item.tags.joined(separator: ","),
            item.folderIDs.map(\.rawValue).joined(separator: ","),
            item.parentReferenceKey,
            item.resourceTokenSummary,
            item.orderingKey ?? "ordering=none",
            "\(item.isDeleted)"
        ].joined(separator: ":")
    }

    private nonisolated static func standaloneNoteSignature(_ note: CanonicalLibraryMetadataReadProjectionNote) -> String {
        [
            note.noteItemID.rawValue,
            note.metadataHashPrefix ?? "metadataHash=none",
            note.title,
            note.filingComponents.joined(separator: "/"),
            note.tags.joined(separator: ","),
            note.folderIDs.map(\.rawValue).joined(separator: ","),
            note.parentReferenceKey,
            note.resourceTokenSummary,
            "\(note.isDeleted)"
        ].joined(separator: ":")
    }

    private nonisolated static func artifactSignature(_ item: CanonicalGeneratedArtifactReadProjectionItem) -> String {
        [
            item.objectID,
            item.artifactID,
            item.artifactKind.rawValue,
            item.availability.rawValue,
            item.hashPrefix ?? "hash=none",
            "\(item.byteSize ?? -1)",
            item.localDownloadedState ?? "local=unknown",
            item.peerAuthoritativeState ?? "peer=unknown",
            item.parentObjectStateSummary ?? "parent=unknown",
            "\(item.localAvailability)",
            "\(item.peerAuthoritativeAvailability)",
            "\(item.parentTombstoned)",
            "\(item.unsafePathTokenObserved)"
        ].joined(separator: ":")
    }

    private nonisolated static func conflictSignature(_ item: CanonicalTombstoneConflictReadProjectionItem) -> String {
        [
            item.objectID,
            item.objectKind.rawValue,
            item.tombstoneState.rawValue,
            item.deletedDisplayState.rawValue,
            item.conflictKind,
            item.conflictStatus.rawValue,
            item.activeVsTombstoneState,
            item.antiResurrectionStatus.rawValue,
            item.parentObjectStateSummary,
            "\(item.generatedArtifactResurrectionBlocked)",
            "\(item.softDeleteMarkerPresent)",
            item.hashPrefix ?? "hash=none",
            "\(item.physicalDeleteRisk)",
            "\(item.permanentDeleteRisk)",
            "\(item.tombstoneGCRisk)",
            "\(item.autoConflictResolutionRisk)",
            "\(item.staleLiveResurrectionRisk)"
        ].joined(separator: ":")
    }

    private nonisolated static func uploadSignature(_ record: CanonicalUploadReadProjectionRecord) -> String {
        [
            record.objectID,
            "\(record.audioAvailable)",
            record.audioAvailability.rawValue,
            "\(record.byteSize ?? -1)",
            record.audioHashPrefix ?? "hash=none",
            record.peerState?.rawValue ?? "peer=none",
            record.uploadAction?.rawValue ?? "action=none",
            record.uploadEvidenceStatus?.rawValue ?? "evidence=none",
            record.uploadLedgerPhase?.rawValue ?? "ledger=none",
            "\(record.retryEligible)"
        ].joined(separator: ":")
    }

    private nonisolated static func syncStatusSignature(_ status: CanonicalSyncEngineStatusReadProjection) -> String {
        [
            status.source.rawValue,
            status.mode?.rawValue ?? "mode=none",
            status.syncRuntimeMode?.rawValue ?? "syncMode=none",
            "\(status.canonicalPlanUsed)",
            "\(status.canonicalPlanFallback)",
            "\(status.canonicalPlanBlocked)",
            "\(status.canonicalPlanNoCommit)",
            "\(status.pendingTransferCount)",
            "\(status.inFlightTransferCount)",
            "\(status.failedTransferCount)",
            "\(status.syncOrUploadTriggeredByRead)"
        ].joined(separator: ":")
    }

    private func recordCanonicalEffectiveReadCacheDiagnostic(
        _ kind: CanonicalReadRuntimeDiagnosticKind,
        count: Int? = nil,
        detail: String? = nil
    ) {
        canonicalEffectiveReadCacheDiagnostics.append(
            CanonicalReadRuntimeDiagnostic(
                kind: kind,
                syncRunID: canonicalReadRuntimeSyncRunID,
                mode: canonicalReadRuntimeResult?.mode ?? .disabled,
                source: canonicalReadRuntimeResult?.returnedSource,
                count: count,
                detail: detail
            )
        )
        if canonicalEffectiveReadCacheDiagnostics.count > 64 {
            canonicalEffectiveReadCacheDiagnostics.removeFirst(canonicalEffectiveReadCacheDiagnostics.count - 64)
        }
    }

    private func recordCanonicalFileRuntimeReadProjectionDiagnostic(
        durationMs: Int?,
        count: Int?,
        key: CanonicalEffectiveStudyCacheKey,
        reason: CanonicalEffectiveReadCacheReason,
        extra: String? = nil
    ) {
        let detail = [
            "cacheKeyPrefix=\(canonicalEffectiveCacheKeyPrefix(key))",
            "reason=\(reason.rawValue)",
            extra
        ].compactMap { $0 }.joined(separator: ",")
        guard CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(detail) else {
            canonicalFileRuntimeDiagnostics.append(
                CanonicalKernelDiagnosticRecord(
                    kind: .diagnosticRedactionRejected,
                    domain: .file,
                    count: 1,
                    redactedDetail: "readProjectionDiagnosticRejected"
                )
            )
            trimCanonicalFileRuntimeDiagnostics()
            return
        }
        canonicalFileRuntimeDiagnostics.append(
            CanonicalKernelDiagnosticRecord(
                kind: .readProjectionRebuildDurationMs,
                domain: .file,
                durationMs: durationMs,
                count: count,
                redactedDetail: detail
            )
        )
        trimCanonicalFileRuntimeDiagnostics()
    }

    private func trimCanonicalFileRuntimeDiagnostics() {
        if canonicalFileRuntimeDiagnostics.count > 64 {
            canonicalFileRuntimeDiagnostics.removeFirst(canonicalFileRuntimeDiagnostics.count - 64)
        }
    }

    private nonisolated static func canonicalEffectiveCacheKeyPrefix(
        _ key: CanonicalEffectiveStudyCacheKey
    ) -> String {
        let raw = [
            key.mode.rawValue,
            key.returnedSource.rawValue,
            key.fallback.rawValue,
            "\(key.canonicalReadServed)",
            "\(key.legacyBackingRevision)",
            key.snapshotSignature,
            key.divergenceSignature
        ].joined(separator: "|")
        return String(CanonicalHash.sha256String(raw).value.prefix(12))
    }

    private func canonicalEffectiveCacheKeyPrefix(
        _ key: CanonicalEffectiveStudyCacheKey
    ) -> String {
        Self.canonicalEffectiveCacheKeyPrefix(key)
    }

    private func resolvedCanonicalReadRuntimeConfiguration() -> CanonicalReadRuntimeConfiguration {
        if let canonicalReadRuntimeConfigurationOverride {
            return canonicalReadRuntimeConfigurationOverride
        }
        if canonicalReadRuntimeUsesMasterSwitchConfiguration {
            return .disabled
        }
        return CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults()
            .resolve()
            .effectiveConfiguration
            .readRuntimeConfiguration
    }

    private static func servingReadConfiguration(
        _ configuration: CanonicalReadRuntimeConfiguration?
    ) -> CanonicalReadRuntimeConfiguration? {
        guard let configuration else {
            return nil
        }
        switch configuration.mode {
        case .disabled, .blocked:
            return nil
        case .parallelCompare, .canonicalReadCandidate, .guardedCanonicalReadWithLegacyFallback:
            return configuration
        }
    }

    private func makeReadRuntimeLegacyManifest(
        deviceID: String,
        generatedAt: Date
    ) -> StudyLibrarySyncManifest {
        let itemsByID = Dictionary(
            allStudyItems.map { ($0.itemID, $0) },
            uniquingKeysWith: { _, live in live }
        )
        let items = allStudyItems.map { $0.syncSanitized(modifiedByDeviceID: deviceID) }
        let folders = allStudyFolders.map { $0.syncSanitized(modifiedByDeviceID: deviceID) }
        let recordings = (try? audioFileStore.loadAllMetadata(includeDeleted: true)) ?? []
        return StudyLibrarySyncManifest.make(
            deviceID: deviceID,
            generatedAt: generatedAt,
            items: items,
            folders: folders,
            tombstones: makeSyncTombstones(items: items, folders: folders, deviceID: deviceID),
            pendingUploads: makePendingRecordingUploads(
                recordings: recordings,
                itemsByID: itemsByID,
                targetDeviceID: deviceID
            ),
            recordings: makeManifestRecordingEntries(
                recordings: recordings,
                itemsByRecordingID: Dictionary(
                    itemsByID.values.compactMap { item in item.recordingID.map { ($0, item) } },
                    uniquingKeysWith: { _, latest in latest }
                ),
                deviceID: deviceID
            )
        )
    }

    private func canonicalEffectiveStudyItems(
        from snapshot: CanonicalReadSnapshot
    ) -> [StudyItemMetadata] {
        let generatedAt = snapshot.generatedAt.date
        let legacyByItemID = Dictionary(
            allStudyItems.map { ($0.itemID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let legacyByRecordingID = Dictionary(
            allStudyItems.compactMap { item -> (String, StudyItemMetadata)? in
                guard let recordingID = item.recordingID else { return nil }
                return (recordingID, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var itemsByID: [StudyItemID: StudyItemMetadata] = [:]

        for projection in snapshot.libraryMetadata.snapshot.studyItems {
            let item = canonicalStudyItem(
                itemID: projection.itemID.rawValue,
                kind: projection.itemKind,
                title: projection.title,
                filingComponents: projection.filingComponents,
                tags: projection.tags,
                folderIDs: projection.folderIDs.map(\.rawValue),
                isDeleted: projection.isDeleted,
                generatedAt: generatedAt,
                legacy: legacyByItemID[projection.itemID.rawValue]
            )
            itemsByID[item.itemID] = item
        }

        for projection in snapshot.libraryMetadata.snapshot.standaloneNotes {
            let item = canonicalStudyItem(
                itemID: projection.noteItemID.rawValue,
                kind: .standaloneNote,
                title: projection.title,
                filingComponents: projection.filingComponents,
                tags: projection.tags,
                folderIDs: projection.folderIDs.map(\.rawValue),
                isDeleted: projection.isDeleted,
                generatedAt: generatedAt,
                legacy: legacyByItemID[projection.noteItemID.rawValue]
            )
            itemsByID[item.itemID] = item
        }

        for recording in snapshot.recordingMetadata.records {
            if let legacy = legacyByRecordingID[recording.objectID] {
                let existing = itemsByID[legacy.itemID] ?? legacy
                let item = canonicalRecordingMetadataItem(
                    recording,
                    overlaying: existing,
                    generatedAt: generatedAt
                )
                itemsByID[item.itemID] = item
            } else {
                let filing = canonicalFilingPath(from: [])
                let item = StudyItemMetadata(
                    recordingID: recording.objectID,
                    sanitizedRecordingID: StudyPathSanitizer.sanitizedPathComponent(recording.objectID),
                    title: recording.title,
                    createdAt: generatedAt,
                    duration: TimeInterval(recording.durationSeconds ?? 0),
                    studyFiling: filing,
                    tags: canonicalTags(recording.tags),
                    folderIDs: StudyItemMetadata.defaultFolderIDs(for: filing),
                    updatedAt: generatedAt,
                    transcriptionStatus: nil,
                    noteStatus: nil,
                    sourceDescription: "canonicalReadRuntime",
                    isTrashed: recording.isDeleted,
                    modifiedByDeviceID: "canonicalReadRuntime"
                )
                itemsByID[item.itemID] = item
            }
        }

        return itemsByID.values.sorted { left, right in
            if left.createdAt == right.createdAt {
                return left.title.localizedStandardCompare(right.title) == .orderedAscending
            }
            return left.createdAt > right.createdAt
        }
    }

    private func canonicalEffectiveStudyFolders(
        from snapshot: CanonicalReadSnapshot,
        items: [StudyItemMetadata]
    ) -> [StudyFolderMetadata] {
        let generatedAt = snapshot.generatedAt.date
        let legacyByFolderID = Dictionary(
            allStudyFolders.map { ($0.folderID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return snapshot.libraryMetadata.snapshot.folders.map { projection in
            let path = canonicalFilingPath(from: projection.hierarchyPath)
            let level = StudyFolderLevel(rawValue: projection.hierarchyLevel ?? "")
                ?? StudyFolderMetadata.level(forDepth: max(0, projection.hierarchyPath.count - 1))
                ?? .custom
            var folder = legacyByFolderID[projection.folderID.rawValue] ?? StudyFolderMetadata(
                folderID: projection.folderID.rawValue,
                name: projection.title,
                level: level,
                path: path,
                parentFolderID: projection.parentID?.rawValue,
                createdAt: generatedAt,
                updatedAt: generatedAt,
                colorToken: projection.colorToken.flatMap(StudyFolderColorToken.init(rawValue:)),
                isTrashed: projection.isDeleted,
                modifiedByDeviceID: "canonicalReadRuntime"
            )
            folder.name = projection.title
            folder.level = level
            folder.path = path
            folder.parentFolderID = projection.parentID?.rawValue
            folder.colorToken = projection.colorToken.flatMap(StudyFolderColorToken.init(rawValue:))
            folder.isTrashed = projection.isDeleted
            folder.updatedAt = generatedAt
            folder.modifiedByDeviceID = "canonicalReadRuntime"
            folder.itemIDs = items
                .filter { $0.folderIDs.contains(folder.folderID) }
                .map(\.itemID)
                .sorted()
            return folder
        }
        .sorted { $0.folderID < $1.folderID }
    }

    private func canonicalStudyItem(
        itemID: String,
        kind: CanonicalStudyItemKind,
        title: String,
        filingComponents: [String],
        tags: [String],
        folderIDs: [String],
        isDeleted: Bool,
        generatedAt: Date,
        legacy: StudyItemMetadata?
    ) -> StudyItemMetadata {
        let filing = canonicalFilingPath(from: filingComponents)
        let resolvedKind: StudyItemKind = kind == .recordingBundle ? .recordingBundle : .standaloneNote
        var item = legacy ?? StudyItemMetadata(
            itemID: itemID,
            kind: resolvedKind,
            title: title,
            createdAt: generatedAt,
            updatedAt: generatedAt,
            filing: filing,
            tags: canonicalTags(tags),
            folderIDs: folderIDs.isEmpty ? StudyItemMetadata.defaultFolderIDs(for: filing) : folderIDs,
            sourceDescription: "canonicalReadRuntime",
            isTrashed: isDeleted,
            modifiedByDeviceID: "canonicalReadRuntime"
        )
        item.kind = resolvedKind
        item.title = title
        item.filing = filing
        item.tags = canonicalTags(tags)
        item.folderIDs = folderIDs.isEmpty ? StudyItemMetadata.defaultFolderIDs(for: filing) : folderIDs
        item.isTrashed = isDeleted
        item.updatedAt = generatedAt
        item.modifiedByDeviceID = "canonicalReadRuntime"
        return item
    }

    private func canonicalRecordingMetadataItem(
        _ recording: CanonicalRecordingReadProjectionRecord,
        overlaying existing: StudyItemMetadata,
        generatedAt: Date
    ) -> StudyItemMetadata {
        var item = existing
        item.kind = .recordingBundle
        item.recordingID = recording.objectID
        item.sanitizedRecordingID = item.sanitizedRecordingID
            ?? StudyPathSanitizer.sanitizedPathComponent(recording.objectID)
        if item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.title = recording.title
        }
        let recordingTags = canonicalTags(recording.tags)
        if item.tags.isEmpty || !recordingTags.isEmpty {
            item.tags = StudyTagList.unique(item.tags + recordingTags)
        }
        if let durationSeconds = recording.durationSeconds {
            item.duration = TimeInterval(durationSeconds)
        }
        item.isTrashed = item.isTrashed || recording.isDeleted
        if item.isTrashed, item.trashedAt == nil {
            item.trashedAt = generatedAt
        }
        item.updatedAt = generatedAt
        item.modifiedByDeviceID = "canonicalReadRuntime"
        return item
    }

    private func canonicalFilingPath(from components: [String]) -> StudyFilingPath {
        StudyFilingPath(
            type: components.indices.contains(0) ? components[0] : nil,
            subject: components.indices.contains(1) ? components[1] : nil,
            chapter: components.indices.contains(2) ? components[2] : nil,
            topic: components.indices.contains(3) ? components[3] : nil
        )
    }

    private func canonicalTags(_ values: [String]) -> [StudyTag] {
        values.map { value in
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                return StudyTag(namespace: parts[0], value: parts[1])
            }
            return StudyTag(namespace: "canonical", value: value)
        }
    }

    func makeSyncManifest(deviceID: String, generatedAt: Date = Date()) -> StudyLibrarySyncManifest {
        refresh()

        var itemsByID = Dictionary(
            (loadAllStoredItemMetadata() + allStudyItems).map { ($0.itemID, $0) },
            uniquingKeysWith: { _, live in live }
        )

        let recordings = (try? audioFileStore.loadAllMetadata(includeDeleted: true)) ?? []
        for recording in recordings {
            let fallback = StudyItemMetadata.defaultMetadata(for: recording)
            let metadata = loadStoredMetadata(recordingID: recording.id)?.mergedWithCurrentRecording(recording) ?? fallback
            itemsByID[metadata.itemID] = metadata
        }

        let foldersByID = Dictionary(
            (loadAllFolderMetadata() + allStudyFolders).map { ($0.folderID, $0) },
            uniquingKeysWith: { _, live in live }
        )
        let items = itemsByID.values.map { $0.syncSanitized(modifiedByDeviceID: deviceID) }
        let folders = foldersByID.values.map { $0.syncSanitized(modifiedByDeviceID: deviceID) }
        let tombstones = makeSyncTombstones(items: items, folders: folders, deviceID: deviceID)
        let pendingUploads = makePendingRecordingUploads(
            recordings: recordings,
            itemsByID: itemsByID,
            targetDeviceID: deviceID
        )

        return StudyLibrarySyncManifest.make(
            deviceID: deviceID,
            generatedAt: generatedAt,
            items: items,
            folders: folders,
            tombstones: tombstones,
            pendingUploads: pendingUploads,
            recordings: makeManifestRecordingEntries(
                recordings: recordings,
                itemsByRecordingID: Dictionary(
                    itemsByID.values.compactMap { item in item.recordingID.map { ($0, item) } },
                    uniquingKeysWith: { _, latest in latest }
                ),
                deviceID: deviceID
            )
        )
    }

    func makeSyncManifestInBackground(deviceID: String, generatedAt: Date = Date()) async -> StudyLibrarySyncManifest {
        let rootURL = self.rootURL
        let startedAt = Date()
        let manifest = await Task.detached(priority: .utility) {
            let recordings = LocalNetworkSyncInventoryBackgroundIO.loadRecordings(rootURL: rootURL, includeDeleted: true)
            return LocalNetworkSyncBackgroundStudyManifestBuilder(
                fileManager: .default,
                rootURL: rootURL,
                recordings: recordings,
                deviceID: deviceID,
                generatedAt: generatedAt
            ).build().manifest
        }.value
        let durationMs = CanonicalPerfLog.elapsedMs(since: startedAt)
        ConnectionDiagnosticsStore.shared.recordPerfLog(
            CanonicalPerfLog.subphaseMeasured(
                operation: .immediateSync,
                subphase: .inventoryBuildMs,
                durationMs: durationMs,
                result: "syncManifestBuild"
            ),
            deviceID: deviceID
        )
        return manifest
    }

    @discardableResult
    func applySyncManifest(_ manifest: StudyLibrarySyncManifest, localDeviceID: String) async throws -> StudyLibrarySyncApplyResult {
        let perfStartedAt = Date()
        defer {
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .applyMs,
                    durationMs: CanonicalPerfLog.elapsedMs(since: perfStartedAt),
                    result: "applySyncManifest"
                ),
                deviceID: localDeviceID
            )
        }
        guard manifest.hasValidChecksum else {
            throw StudyLibraryStoreError.writeFailed("sync_manifest_checksum_mismatch")
        }

        let rootURL = rootURL
        let localItems = allStudyItems
        let localFolders = allStudyFolders
        let applyOutput = try await Self.applySyncManifestOffMain(
            manifest,
            rootURL: rootURL,
            localItems: localItems,
            localFolders: localFolders
        )
        let result = applyOutput.result
        if applyOutput.filesChanged {
            refresh()
        }
        if result.tombstoneCount > 0 || result.conflictCount > 0 {
            LocalNetworkSyncEventTrigger.post(.tombstoneConflictChanged, source: "StudyLibraryStore.applySyncManifest")
        } else if result.appliedFolderCount > 0 || result.appliedItemCount > 0 {
            LocalNetworkSyncEventTrigger.post(.studyLibraryMetadataChanged, source: "StudyLibraryStore.applySyncManifest")
        }
        return result
    }

    private nonisolated static func applySyncManifestOffMain(
        _ manifest: StudyLibrarySyncManifest,
        rootURL: URL,
        localItems: [StudyItemMetadata],
        localFolders: [StudyFolderMetadata]
    ) async throws -> (result: StudyLibrarySyncApplyResult, filesChanged: Bool) {
        try await Task.detached(priority: .utility) {
            try applySyncManifestFiles(
                manifest,
                rootURL: rootURL,
                localItems: localItems,
                localFolders: localFolders
            )
        }.value
    }

    private nonisolated static func applySyncManifestFiles(
        _ manifest: StudyLibrarySyncManifest,
        rootURL: URL,
        localItems: [StudyItemMetadata],
        localFolders: [StudyFolderMetadata],
        fileManager: FileManager = .default
    ) throws -> (result: StudyLibrarySyncApplyResult, filesChanged: Bool) {
        let urls = studyStorageURLs(rootURL: rootURL)
        try ensureStudyDirectoriesOffMain(urls: urls, fileManager: fileManager)

        let storedItems = loadAllStoredItemMetadataOffMain(urls: urls, fileManager: fileManager)
        let storedFolders = loadAllFolderMetadataOffMain(urls: urls, fileManager: fileManager)
        var itemsByID = Dictionary(storedItems.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
        for item in localItems {
            itemsByID[item.itemID] = item
        }
        var foldersByID = Dictionary(storedFolders.map { ($0.folderID, $0) }, uniquingKeysWith: { first, _ in first })
        for folder in localFolders {
            foldersByID[folder.folderID] = folder
        }
        let originalItemsByID = itemsByID
        let originalFoldersByID = foldersByID

        var result = StudyLibrarySyncApplyResult()
        var changedItemIDs = Set<StudyItemID>()
        var changedFolderIDs = Set<StudyFolderID>()

        for incomingFolder in manifest.folders {
            do {
                var remote = incomingFolder.syncSanitized(modifiedByDeviceID: manifest.deviceID)
                let existing = foldersByID[remote.folderID]
                guard let merged = mergedSyncFolderOffMain(existing: existing, incoming: &remote, result: &result) else {
                    continue
                }
                foldersByID[merged.folderID] = merged
                if merged != existing {
                    changedFolderIDs.insert(merged.folderID)
                }
                result.appliedFolderCount += 1
            } catch {
                result.failedChanges += 1
            }
        }

        for incomingItem in manifest.items {
            do {
                var remote = incomingItem.syncSanitized(modifiedByDeviceID: manifest.deviceID)
                markSyncMetadataOnlyIfNeededOffMain(&remote, rootURL: rootURL)
                let existing = editableMetadataIfAvailableOffMain(itemID: remote.itemID, itemsByID: itemsByID)
                guard let merged = mergedSyncItemOffMain(existing: existing, incoming: &remote, result: &result) else {
                    continue
                }
                itemsByID[merged.itemID] = merged
                if merged != existing {
                    changedItemIDs.insert(merged.itemID)
                }
                result.appliedItemCount += 1
            } catch {
                result.failedChanges += 1
            }
        }

        for tombstone in manifest.tombstones {
            do {
                switch tombstone.entityKind {
                case .item:
                    guard var item = editableMetadataIfAvailableOffMain(itemID: tombstone.entityID, itemsByID: itemsByID),
                          tombstone.updatedAt >= item.updatedAt else {
                        continue
                    }
                    item.isTrashed = tombstone.operation == .trash || tombstone.operation == .delete || tombstone.operation == .deleteMetadataOnly
                    item.trashedAt = item.isTrashed ? tombstone.updatedAt : nil
                    item.updatedAt = tombstone.updatedAt
                    item.modifiedByDeviceID = tombstone.modifiedByDeviceID ?? manifest.deviceID
                    itemsByID[item.itemID] = item
                    if item != originalItemsByID[item.itemID] {
                        changedItemIDs.insert(item.itemID)
                    }
                    result.tombstoneCount += 1
                case .folder:
                    guard var folder = foldersByID[tombstone.entityID],
                          tombstone.updatedAt >= folder.updatedAt else {
                        continue
                    }
                    folder.isTrashed = tombstone.operation == .trash || tombstone.operation == .delete || tombstone.operation == .deleteMetadataOnly
                    folder.trashedAt = folder.isTrashed ? tombstone.updatedAt : nil
                    folder.updatedAt = tombstone.updatedAt
                    folder.modifiedByDeviceID = tombstone.modifiedByDeviceID ?? manifest.deviceID
                    foldersByID[folder.folderID] = folder
                    if folder != originalFoldersByID[folder.folderID] {
                        changedFolderIDs.insert(folder.folderID)
                    }
                    result.tombstoneCount += 1
                }
            } catch {
                result.failedChanges += 1
            }
        }

        rebuildFolderLinksOffMain(
            foldersByID: &foldersByID,
            itemsByID: &itemsByID,
            changedItemIDs: changedItemIDs
        )
        for (folderID, folder) in foldersByID where folder != originalFoldersByID[folderID] {
            changedFolderIDs.insert(folderID)
        }

        var index = loadIndexOffMain(urls: urls, fileManager: fileManager)
        var filesChanged = false
        for itemID in changedItemIDs.sorted() {
            guard let item = itemsByID[itemID] else {
                continue
            }
            if item != originalItemsByID[itemID] {
                try writeItemMetadataOffMain(item, urls: urls, index: &index, fileManager: fileManager)
                filesChanged = true
            }
            if try applySyncItemToRecordingMetadataOffMain(item, rootURL: rootURL) {
                filesChanged = true
            }
        }
        for folderID in changedFolderIDs.sorted() {
            guard let folder = foldersByID[folderID],
                  folder != originalFoldersByID[folderID] else {
                continue
            }
            try writeFolderMetadataOffMain(folder, urls: urls, index: &index, fileManager: fileManager)
            filesChanged = true
        }
        try saveIndexIfChangedOffMain(index, urls: urls, fileManager: fileManager)
        return (result, filesChanged)
    }

    private nonisolated static func studyStorageURLs(rootURL: URL) -> (
        studyURL: URL,
        itemMetadataURL: URL,
        folderMetadataURL: URL,
        indexURL: URL,
        hierarchyRulesURL: URL,
        legacyItemMetadataURL: URL,
        legacyIndexURL: URL
    ) {
        let studyURL = rootURL.appendingPathComponent("study", isDirectory: true).standardizedFileURL
        return (
            studyURL: studyURL,
            itemMetadataURL: studyURL.appendingPathComponent("items", isDirectory: true).standardizedFileURL,
            folderMetadataURL: studyURL.appendingPathComponent("folders", isDirectory: true).standardizedFileURL,
            indexURL: studyURL.appendingPathComponent("index.json", isDirectory: false).standardizedFileURL,
            hierarchyRulesURL: studyURL.appendingPathComponent("hierarchy-rules.json", isDirectory: false).standardizedFileURL,
            legacyItemMetadataURL: studyURL.appendingPathComponent("item-metadata", isDirectory: true).standardizedFileURL,
            legacyIndexURL: studyURL.appendingPathComponent("study-index.json", isDirectory: false).standardizedFileURL
        )
    }

    private nonisolated static func ensureStudyDirectoriesOffMain(
        urls: (
            studyURL: URL,
            itemMetadataURL: URL,
            folderMetadataURL: URL,
            indexURL: URL,
            hierarchyRulesURL: URL,
            legacyItemMetadataURL: URL,
            legacyIndexURL: URL
        ),
        fileManager: FileManager
    ) throws {
        guard isInsideRootOffMain(urls.studyURL, rootURL: urls.studyURL.deletingLastPathComponent()),
              isInsideStudyDirectoryOffMain(urls.itemMetadataURL, studyURL: urls.studyURL),
              isInsideStudyDirectoryOffMain(urls.folderMetadataURL, studyURL: urls.studyURL),
              isInsideStudyDirectoryOffMain(urls.indexURL, studyURL: urls.studyURL),
              isInsideStudyDirectoryOffMain(urls.hierarchyRulesURL, studyURL: urls.studyURL),
              isInsideStudyDirectoryOffMain(urls.legacyItemMetadataURL, studyURL: urls.studyURL),
              isInsideStudyDirectoryOffMain(urls.legacyIndexURL, studyURL: urls.studyURL) else {
            throw StudyLibraryStoreError.unsafeDestination
        }

        do {
            try fileManager.createDirectory(at: urls.itemMetadataURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: urls.folderMetadataURL, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: urls.hierarchyRulesURL.path) {
                try jsonEncoderOffMain().encode([StudyHierarchyRule.defaultCourseView]).write(to: urls.hierarchyRulesURL, options: .atomic)
            }
            if !fileManager.fileExists(atPath: urls.indexURL.path) {
                try jsonEncoderOffMain().encode(StudyMetadataIndex()).write(to: urls.indexURL, options: .atomic)
            }
        } catch {
            throw StudyLibraryStoreError.unableToCreateDirectory
        }
    }

    private nonisolated static func loadAllStoredItemMetadataOffMain(
        urls: (
            studyURL: URL,
            itemMetadataURL: URL,
            folderMetadataURL: URL,
            indexURL: URL,
            hierarchyRulesURL: URL,
            legacyItemMetadataURL: URL,
            legacyIndexURL: URL
        ),
        fileManager: FileManager
    ) -> [StudyItemMetadata] {
        loadMetadataFilesOffMain(from: urls.itemMetadataURL, studyURL: urls.studyURL, as: StudyItemMetadata.self, fileManager: fileManager)
            + loadMetadataFilesOffMain(from: urls.legacyItemMetadataURL, studyURL: urls.studyURL, as: StudyItemMetadata.self, fileManager: fileManager)
    }

    private nonisolated static func loadAllFolderMetadataOffMain(
        urls: (
            studyURL: URL,
            itemMetadataURL: URL,
            folderMetadataURL: URL,
            indexURL: URL,
            hierarchyRulesURL: URL,
            legacyItemMetadataURL: URL,
            legacyIndexURL: URL
        ),
        fileManager: FileManager
    ) -> [StudyFolderMetadata] {
        loadMetadataFilesOffMain(from: urls.folderMetadataURL, studyURL: urls.studyURL, as: StudyFolderMetadata.self, fileManager: fileManager)
    }

    private nonisolated static func loadMetadataFilesOffMain<T: Decodable>(
        from directoryURL: URL,
        studyURL: URL,
        as type: T.Type,
        fileManager: FileManager
    ) -> [T] {
        guard fileManager.fileExists(atPath: directoryURL.path),
              isInsideStudyDirectoryOffMain(directoryURL, studyURL: studyURL),
              let urls = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                let safeURL = url.standardizedFileURL
                guard isInsideStudyDirectoryOffMain(safeURL, studyURL: studyURL),
                      let data = try? Data(contentsOf: safeURL) else {
                    return nil
                }
                return try? jsonDecoderOffMain().decode(T.self, from: data)
            }
    }

    private nonisolated static func loadIndexOffMain(
        urls: (
            studyURL: URL,
            itemMetadataURL: URL,
            folderMetadataURL: URL,
            indexURL: URL,
            hierarchyRulesURL: URL,
            legacyItemMetadataURL: URL,
            legacyIndexURL: URL
        ),
        fileManager: FileManager
    ) -> StudyMetadataIndex {
        for url in [urls.indexURL, urls.legacyIndexURL] where fileManager.fileExists(atPath: url.path) {
            guard isInsideStudyDirectoryOffMain(url, studyURL: urls.studyURL),
                  let data = try? Data(contentsOf: url),
                  let index = try? jsonDecoderOffMain().decode(StudyMetadataIndex.self, from: data) else {
                continue
            }
            return index
        }
        return StudyMetadataIndex()
    }

    private nonisolated static func saveIndexIfChangedOffMain(
        _ index: StudyMetadataIndex,
        urls: (
            studyURL: URL,
            itemMetadataURL: URL,
            folderMetadataURL: URL,
            indexURL: URL,
            hierarchyRulesURL: URL,
            legacyItemMetadataURL: URL,
            legacyIndexURL: URL
        ),
        fileManager: FileManager
    ) throws {
        guard isInsideStudyDirectoryOffMain(urls.indexURL, studyURL: urls.studyURL) else {
            throw StudyLibraryStoreError.unsafeDestination
        }
        let current = loadIndexOffMain(urls: urls, fileManager: fileManager)
        guard current != index else {
            return
        }
        try jsonEncoderOffMain().encode(index).write(to: urls.indexURL, options: .atomic)
    }

    private nonisolated static func writeItemMetadataOffMain(
        _ metadata: StudyItemMetadata,
        urls: (
            studyURL: URL,
            itemMetadataURL: URL,
            folderMetadataURL: URL,
            indexURL: URL,
            hierarchyRulesURL: URL,
            legacyItemMetadataURL: URL,
            legacyIndexURL: URL
        ),
        index: inout StudyMetadataIndex,
        fileManager: FileManager
    ) throws {
        guard !metadata.itemID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudyLibraryStoreError.itemMissing
        }
        var metadataToSave = metadata
        metadataToSave.tags = StudyTagList.unique(metadata.tags)
        if metadataToSave.folderIDs.isEmpty {
            metadataToSave.folderIDs = StudyItemMetadata.defaultFolderIDs(for: metadataToSave.filing)
        }

        let fileName = "\(StudyPathSanitizer.sanitizedPathComponent(metadataToSave.itemID)).json"
        let metadataURL = urls.itemMetadataURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
        guard isInsideDirectoryOffMain(metadataURL, directoryURL: urls.itemMetadataURL) else {
            throw StudyLibraryStoreError.unsafeDestination
        }
        try jsonEncoderOffMain().encode(metadataToSave).write(to: metadataURL, options: .atomic)
        if index.itemMetadataFilesByItemID[metadataToSave.itemID] != fileName {
            index.itemMetadataFilesByItemID[metadataToSave.itemID] = fileName
            index.updatedAt = Date()
        }
        if let recordingID = metadataToSave.recordingID,
           index.itemMetadataFilesByRecordingID[recordingID] != fileName {
            index.itemMetadataFilesByRecordingID[recordingID] = fileName
            index.updatedAt = Date()
        }
    }

    private nonisolated static func writeFolderMetadataOffMain(
        _ folder: StudyFolderMetadata,
        urls: (
            studyURL: URL,
            itemMetadataURL: URL,
            folderMetadataURL: URL,
            indexURL: URL,
            hierarchyRulesURL: URL,
            legacyItemMetadataURL: URL,
            legacyIndexURL: URL
        ),
        index: inout StudyMetadataIndex,
        fileManager: FileManager
    ) throws {
        let fileName = "\(StudyPathSanitizer.sanitizedPathComponent(folder.folderID)).json"
        let folderURL = urls.folderMetadataURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
        guard isInsideDirectoryOffMain(folderURL, directoryURL: urls.folderMetadataURL) else {
            throw StudyLibraryStoreError.unsafeDestination
        }
        try jsonEncoderOffMain().encode(folder).write(to: folderURL, options: .atomic)
        if index.folderMetadataFilesByFolderID[folder.folderID] != fileName {
            index.folderMetadataFilesByFolderID[folder.folderID] = fileName
            index.updatedAt = Date()
        }
    }

    private nonisolated static func editableMetadataIfAvailableOffMain(
        itemID: StudyItemID,
        itemsByID: [StudyItemID: StudyItemMetadata]
    ) -> StudyItemMetadata? {
        if let item = itemsByID[itemID] {
            return item
        }
        return itemsByID.values.first { $0.recordingID == itemID }
    }

    private nonisolated static func markSyncMetadataOnlyIfNeededOffMain(
        _ item: inout StudyItemMetadata,
        rootURL: URL
    ) {
        guard let recordingID = item.recordingID else {
            return
        }
        let audioStore = AudioFileStore(fileManager: .default, rootDirectoryURL: rootURL)
        if let metadata = try? audioStore.loadMetadata(id: recordingID),
           let audioURL = try? audioStore.audioURL(for: metadata),
           FileManager.default.fileExists(atPath: audioURL.path) {
            item.customProperties.removeValue(forKey: "syncedMetadataOnly")
            return
        }
        item.customProperties["syncedMetadataOnly"] = "true"
    }

    private nonisolated static func applySyncItemToRecordingMetadataOffMain(
        _ item: StudyItemMetadata,
        rootURL: URL
    ) throws -> Bool {
        guard let recordingID = item.recordingID else {
            return false
        }
        let audioFileStore = AudioFileStore(fileManager: .default, rootDirectoryURL: rootURL)
        guard let recording = try? audioFileStore.loadMetadata(id: recordingID) else {
            return false
        }

        let updated = RecordingMetadata(
            id: recording.id,
            title: item.title,
            fileName: recording.fileName,
            relativeAudioPath: recording.relativeAudioPath,
            relativeMetadataPath: recording.relativeMetadataPath,
            createdAt: recording.createdAt,
            endedAt: recording.endedAt,
            duration: recording.duration,
            format: recording.format,
            codec: recording.codec,
            sampleRate: recording.sampleRate,
            channels: recording.channels,
            bitrate: recording.bitrate,
            fileSize: recording.fileSize,
            uploadStatus: recording.uploadStatus,
            transcriptionStatus: item.transcriptionStatus ?? recording.transcriptionStatus,
            noteStatus: item.noteStatus ?? recording.noteStatus,
            tags: item.tags.map(\.displayTitle),
            studyFiling: item.studyFiling,
            uploadProgressFraction: recording.uploadProgressFraction,
            uploadProgressConfirmedBytes: recording.uploadProgressConfirmedBytes,
            uploadProgressTotalBytes: recording.uploadProgressTotalBytes,
            uploadPhase: recording.uploadPhase,
            uploadProgressDescription: recording.uploadProgressDescription,
            isDeleted: item.isTrashed,
            deletedAt: item.isTrashed ? (item.trashedAt ?? recording.deletedAt ?? item.updatedAt) : nil
        )
        guard updated != recording else {
            return false
        }
        try audioFileStore.updateMetadata(updated)
        return true
    }

    private nonisolated static func mergedSyncItemOffMain(
        existing: StudyItemMetadata?,
        incoming: inout StudyItemMetadata,
        result: inout StudyLibrarySyncApplyResult
    ) -> StudyItemMetadata? {
        guard let existing else {
            return incoming
        }
        if let localRecordingID = existing.recordingID,
           let remoteRecordingID = incoming.recordingID,
           localRecordingID != remoteRecordingID {
            result.conflictCount += 1
            return nil
        }
        let existingWithLocalReceiptMarker = mergingSyncMetadataOnlyMarker(
            into: existing,
            from: incoming
        )
        if existing.hasSameLocalNetworkBusinessFieldsV2(as: incoming) {
            return existingWithLocalReceiptMarker == existing ? nil : existingWithLocalReceiptMarker
        }
        if incoming.updatedAt > existing.updatedAt {
            return mergingSyncMetadataOnlyMarker(
                into: existing.mergingRemoteBusinessFieldsV2(from: incoming),
                from: incoming
            )
        }
        if incoming.updatedAt == existing.updatedAt {
            result.conflictCount += 1
            return existingWithLocalReceiptMarker == existing ? nil : existingWithLocalReceiptMarker
        }
        result.skippedOlderCount += 1
        return existingWithLocalReceiptMarker == existing ? nil : existingWithLocalReceiptMarker
    }

    /// `syncedMetadataOnly` is receiver-local existence state, not peer-owned
    /// business metadata. Keep it in step with the local audio check even when
    /// the two business signatures are already equal or the peer clock loses.
    private nonisolated static func mergingSyncMetadataOnlyMarker(
        into item: StudyItemMetadata,
        from locallyClassifiedIncoming: StudyItemMetadata
    ) -> StudyItemMetadata {
        var merged = item
        if locallyClassifiedIncoming.customProperties["syncedMetadataOnly"] == "true" {
            merged.customProperties["syncedMetadataOnly"] = "true"
        } else {
            merged.customProperties.removeValue(forKey: "syncedMetadataOnly")
        }
        return merged
    }

    private nonisolated static func mergedSyncFolderOffMain(
        existing: StudyFolderMetadata?,
        incoming: inout StudyFolderMetadata,
        result: inout StudyLibrarySyncApplyResult
    ) -> StudyFolderMetadata? {
        guard let existing else {
            return incoming
        }
        if existing.hasSameLocalNetworkBusinessFieldsV2(as: incoming) {
            return nil
        }
        if incoming.updatedAt > existing.updatedAt {
            return existing.mergingRemoteBusinessFieldsV2(from: incoming)
        }
        if incoming.updatedAt == existing.updatedAt {
            result.conflictCount += 1
            return nil
        }
        result.skippedOlderCount += 1
        return nil
    }

    private nonisolated static func rebuildFolderLinksOffMain(
        foldersByID: inout [StudyFolderID: StudyFolderMetadata],
        itemsByID: inout [StudyItemID: StudyItemMetadata],
        changedItemIDs: Set<StudyItemID>
    ) {
        guard !changedItemIDs.isEmpty else {
            return
        }
        let liveItemIDs = Set(itemsByID.values.filter { !$0.isTrashed }.map(\.itemID))
        for folderID in foldersByID.keys {
            foldersByID[folderID]?.itemIDs.removeAll { !liveItemIDs.contains($0) }
        }

        for itemID in changedItemIDs.sorted() {
            guard var item = itemsByID[itemID],
                  !item.isTrashed else {
                continue
            }
            if item.folderIDs.isEmpty {
                item.folderIDs = StudyItemMetadata.defaultFolderIDs(for: item.filing)
                itemsByID[item.itemID] = item
            }
            for folder in folderChainOffMain(for: item.filing, itemID: item.itemID) {
                var stored = foldersByID[folder.folderID] ?? folder
                stored.name = folder.name
                stored.level = folder.level
                stored.path = folder.path
                stored.parentFolderID = folder.parentFolderID
                stored.childFolderIDs = StudyItemMetadata.uniqueIDs(stored.childFolderIDs + folder.childFolderIDs)
                if item.folderIDs.contains(folder.folderID), !stored.itemIDs.contains(item.itemID) {
                    stored.itemIDs.append(item.itemID)
                }
                foldersByID[folder.folderID] = stored
            }
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
    }

    private nonisolated static func folderChainOffMain(
        for filing: StudyFilingPath,
        itemID: StudyItemID?
    ) -> [StudyFolderMetadata] {
        let effectiveFiling = StudyItemMetadata.effectiveFolderPath(for: filing)
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
            folders.append(
                StudyFolderMetadata(
                    name: value,
                    level: level,
                    path: path,
                    parentFolderID: parentFolderID,
                    childFolderIDs: childFolderIDs,
                    itemIDs: isLeaf ? itemID.map { [$0] } ?? [] : []
                )
            )
            parentFolderID = folders.last?.folderID
        }
        return folders
    }

    private nonisolated static func jsonEncoderOffMain() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private nonisolated static func jsonDecoderOffMain() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private nonisolated static func isInsideRootOffMain(_ url: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private nonisolated static func isInsideStudyDirectoryOffMain(_ url: URL, studyURL: URL) -> Bool {
        let studyPath = studyURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == studyPath || path.hasPrefix(studyPath + "/")
    }

    private nonisolated static func isInsideDirectoryOffMain(_ url: URL, directoryURL: URL) -> Bool {
        let directoryPath = directoryURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == directoryPath || path.hasPrefix(directoryPath + "/")
    }

    @discardableResult
    func upsertRecordingMetadata(
        _ recording: RecordingMetadata,
        businessMutationAt: Date? = nil,
        clearsRecordingTombstone: Bool = false
    ) throws -> StudyItemMetadata {
        let previous = editableMetadataIfAvailable(recordingID: recording.id)
        let fallback = StudyItemMetadata.defaultMetadata(for: recording)
        var metadata = previous?.mergedWithCurrentRecording(
            recording,
            businessMutationAt: businessMutationAt,
            clearsRecordingTombstone: clearsRecordingTombstone
        ) ?? fallback
        if let businessMutationAt, previous == nil {
            metadata.updatedAt = businessMutationAt
        }
        try save(metadata, previousMetadata: previous)
        refresh()
        LocalNetworkSyncEventTrigger.post(.studyLibraryMetadataChanged, source: "StudyLibraryStore.upsertRecordingMetadata", recordingID: recording.id)
        return metadata
    }

    func updateFiling(for recordingID: String, studyFiling: StudyFilingPath?) throws {
        let previous = try editableMetadata(recordingID: recordingID)
        var metadata = previous
        metadata.filing = studyFiling?.isEmpty == true ? StudyFilingPath() : (studyFiling ?? StudyFilingPath())
        metadata.folderIDs = StudyItemMetadata.defaultFolderIDs(for: metadata.filing)
        metadata.updatedAt = Date()
        try save(metadata, previousMetadata: previous)
        refresh()
        LocalNetworkSyncEventTrigger.post(.studyLibraryMetadataChanged, source: "StudyLibraryStore.updateFiling", recordingID: recordingID)
    }

    func folder(folderID: StudyFolderID) -> StudyFolderMetadata? {
        loadStoredFolder(folderID: folderID) ?? effectiveStudyFolders.first { $0.folderID == folderID }
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
        LocalNetworkSyncEventTrigger.post(.studyLibraryMetadataChanged, source: "StudyLibraryStore.createFolder")
        return folder
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
        LocalNetworkSyncEventTrigger.post(.studyLibraryMetadataChanged, source: "StudyLibraryStore.renameFolder")
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
    func setFolderColor(folderID: StudyFolderID, colorToken: StudyFolderColorToken?) throws -> StudyFolderMetadata {
        guard var folder = folder(folderID: folderID) else {
            throw StudyLibraryStoreError.folderMissing
        }

        folder.colorToken = colorToken == .default ? nil : colorToken
        folder.updatedAt = Date()
        try save(folder)
        refresh()
        LocalNetworkSyncEventTrigger.post(.studyLibraryMetadataChanged, source: "StudyLibraryStore.setFolderColor")
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
        LocalNetworkSyncEventTrigger.post(.tombstoneConflictChanged, source: "StudyLibraryStore.moveFolderToTrash")
        return folder
    }

    func save(_ metadata: StudyItemMetadata) throws {
        let previous = editableMetadataIfAvailable(itemID: metadata.itemID)
        try save(metadata, previousMetadata: previous)
        refresh()
        LocalNetworkSyncEventTrigger.post(.studyLibraryMetadataChanged, source: "StudyLibraryStore.saveItem")
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
        if let recording = (try? audioFileStore.loadMetadata(id: recordingID)) {
            let fallback = StudyItemMetadata.defaultMetadata(for: recording)
            return loadStoredMetadata(recordingID: recordingID)?.mergedWithCurrentRecording(recording) ?? fallback
        }

        if let metadata = loadStoredMetadata(recordingID: recordingID) {
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

    private func editableMetadataIfAvailable(recordingID: String) -> StudyItemMetadata? {
        allStudyItems.first { $0.recordingID == recordingID }
            ?? loadStoredMetadata(recordingID: recordingID)
    }

    private func loadStoredMetadata(recordingID: String) -> StudyItemMetadata? {
        let recordingItemID = StudyItemMetadata.recordingBundleItemID(for: recordingID)
        return loadAllStoredItemMetadata().first { metadata in
            metadata.recordingID == recordingID || metadata.itemID == recordingItemID
        }
    }

    private func shouldIncludeStoredItem(
        _ item: StudyItemMetadata,
        liveRecordingIDs: Set<String>,
        alreadyLoaded: [StudyItemID: StudyItemMetadata]
    ) -> Bool {
        if alreadyLoaded[item.itemID] != nil {
            return false
        }
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

    private func makePendingRecordingUploads(
        recordings: [RecordingMetadata],
        itemsByID: [StudyItemID: StudyItemMetadata],
        targetDeviceID: String
    ) -> [PendingRecordingUpload] {
        let itemsByRecordingID = Dictionary(
            itemsByID.values.compactMap { item in
                item.recordingID.map { ($0, item) }
            },
            uniquingKeysWith: { current, candidate in
                let fallbackItemID = candidate.recordingID.map(StudyItemMetadata.recordingBundleItemID(for:))
                return current.itemID == fallbackItemID && candidate.itemID != fallbackItemID
                    ? candidate
                    : current
            }
        )
        return recordings.compactMap { recording in
            guard !recording.isDeleted,
                  RecordingUploadStatus(rawMetadataValue: recording.uploadStatus) != .uploaded else {
                return nil
            }

            let fallbackItemID = StudyItemMetadata.recordingBundleItemID(for: recording.id)
            let item = itemsByRecordingID[recording.id]
                ?? itemsByID[fallbackItemID]
                ?? StudyItemMetadata.defaultMetadata(for: recording)
            return PendingRecordingUpload(
                itemID: item.itemID,
                recordingID: recording.id,
                localAudioRelativePath: recording.relativeAudioPath,
                targetDeviceID: targetDeviceID,
                status: PendingRecordingUploadStatus(rawValue: recording.uploadStatus) ?? .pending,
                createdAt: recording.createdAt,
                updatedAt: item.updatedAt
            )
        }
    }

    private func makeManifestRecordingEntries(
        recordings: [RecordingMetadata],
        itemsByRecordingID: [String: StudyItemMetadata],
        deviceID: String
    ) -> [LocalNetworkSyncRecordingEntry] {
        let recordingsByID = Dictionary(recordings.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Set(recordingsByID.keys).union(itemsByRecordingID.keys).sorted().compactMap { recordingID in
            let recording = recordingsByID[recordingID]
            guard let item = itemsByRecordingID[recordingID]
                ?? recording.map(StudyItemMetadata.defaultMetadata(for:)) else {
                return nil
            }
            let audioURL = recording.flatMap { try? audioFileStore.audioURL(for: $0) }
            let hasAudio = audioURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
            let byteSize = hasAudio ? audioURL.flatMap { url -> Int64? in
                guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                      let size = attributes[.size] as? NSNumber else {
                    return nil
                }
                return size.int64Value
            } : nil
            return LocalNetworkSyncRecordingEntry(
                recordingID: recordingID,
                metadataHash: item.localNetworkRecordingBusinessSignatureV2,
                audioAvailable: hasAudio,
                audioChecksum: nil,
                audioSize: byteSize,
                uploadLedgerState: nil,
                receiveStatus: nil,
                processingStatus: nil,
                updatedAt: item.trashedAt ?? item.updatedAt,
                deleted: item.isTrashed,
                title: item.title,
                createdAt: item.createdAt,
                tombstone: item.isTrashed,
                audioAvailability: hasAudio ? .local : .missing,
                uploadStatus: recording?.uploadStatus,
                transcriptionStatus: recording?.transcriptionStatus,
                noteStatus: recording?.noteStatus,
                sourceDeviceID: deviceID,
                artifactRefs: recording.map { recording in [
                    LocalNetworkSyncArtifactID.make(
                        kind: .metadataJSON,
                        ownerID: recordingID,
                        logicalPathToken: recording.relativeMetadataPath
                    )
                ] },
                audioLogicalPathToken: recording?.relativeAudioPath
            )
        }
    }

    private func mergedSyncItem(
        existing: StudyItemMetadata?,
        incoming: inout StudyItemMetadata,
        result: inout StudyLibrarySyncApplyResult
    ) -> StudyItemMetadata? {
        guard let existing else {
            return incoming
        }
        if let localRecordingID = existing.recordingID,
           let remoteRecordingID = incoming.recordingID,
           localRecordingID != remoteRecordingID {
            result.conflictCount += 1
            return nil
        }
        let existingWithLocalReceiptMarker = Self.mergingSyncMetadataOnlyMarker(
            into: existing,
            from: incoming
        )
        if existing.hasSameLocalNetworkBusinessFieldsV2(as: incoming) {
            return existingWithLocalReceiptMarker == existing ? nil : existingWithLocalReceiptMarker
        }
        if incoming.updatedAt > existing.updatedAt {
            return Self.mergingSyncMetadataOnlyMarker(
                into: existing.mergingRemoteBusinessFieldsV2(from: incoming),
                from: incoming
            )
        }
        if incoming.updatedAt == existing.updatedAt {
            result.conflictCount += 1
            return existingWithLocalReceiptMarker == existing ? nil : existingWithLocalReceiptMarker
        }

        result.skippedOlderCount += 1
        return existingWithLocalReceiptMarker == existing ? nil : existingWithLocalReceiptMarker
    }

    private func mergedSyncFolder(
        existing: StudyFolderMetadata?,
        incoming: inout StudyFolderMetadata,
        result: inout StudyLibrarySyncApplyResult
    ) -> StudyFolderMetadata? {
        guard let existing else {
            return incoming
        }
        if existing.hasSameLocalNetworkBusinessFieldsV2(as: incoming) {
            return nil
        }
        if incoming.updatedAt > existing.updatedAt {
            return existing.mergingRemoteBusinessFieldsV2(from: incoming)
        }
        if incoming.updatedAt == existing.updatedAt {
            result.conflictCount += 1
            return nil
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
            try applySyncItemToRecordingMetadata(item)
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

    private func loadAllStoredItemMetadata() -> [StudyItemMetadata] {
        loadMetadataFiles(from: itemMetadataURL, as: StudyItemMetadata.self)
            + loadMetadataFiles(from: legacyItemMetadataURL, as: StudyItemMetadata.self)
    }

    private func applySyncItemToRecordingMetadata(_ item: StudyItemMetadata) throws {
        guard let recordingID = item.recordingID,
              let recording = try? audioFileStore.loadMetadata(id: recordingID) else {
            return
        }

        let updated = RecordingMetadata(
            id: recording.id,
            title: item.title,
            fileName: recording.fileName,
            relativeAudioPath: recording.relativeAudioPath,
            relativeMetadataPath: recording.relativeMetadataPath,
            createdAt: recording.createdAt,
            endedAt: recording.endedAt,
            duration: recording.duration,
            format: recording.format,
            codec: recording.codec,
            sampleRate: recording.sampleRate,
            channels: recording.channels,
            bitrate: recording.bitrate,
            fileSize: recording.fileSize,
            uploadStatus: recording.uploadStatus,
            transcriptionStatus: item.transcriptionStatus ?? recording.transcriptionStatus,
            noteStatus: item.noteStatus ?? recording.noteStatus,
            tags: item.tags.map(\.displayTitle),
            studyFiling: item.studyFiling,
            isDeleted: item.isTrashed,
            deletedAt: item.isTrashed ? (item.trashedAt ?? recording.deletedAt ?? item.updatedAt) : nil
        )

        guard updated != recording else {
            return
        }

        try audioFileStore.updateMetadata(updated)
    }

    private func markSyncMetadataOnlyIfNeeded(_ item: inout StudyItemMetadata) {
        guard let recordingID = item.recordingID else {
            return
        }
        if let metadata = try? audioFileStore.loadMetadata(id: recordingID),
           let audioURL = try? audioFileStore.audioURL(for: metadata),
           fileManager.fileExists(atPath: audioURL.path) {
            item.customProperties.removeValue(forKey: "syncedMetadataOnly")
            return
        }
        item.customProperties["syncedMetadataOnly"] = "true"
    }

    private func loadAllFolderMetadata() -> [StudyFolderMetadata] {
        loadMetadataFiles(from: folderMetadataURL, as: StudyFolderMetadata.self)
    }

    private func loadReceiveRecordDerivedItems() -> [StudyItemMetadata] {
        let inboxURL = rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .standardizedFileURL
        guard isInsideRoot(inboxURL),
              fileManager.fileExists(atPath: inboxURL.path),
              let enumerator = fileManager.enumerator(
                at: inboxURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var items: [StudyItemMetadata] = []
        for case let url as URL in enumerator where url.lastPathComponent == "receive.json" {
            let receiveURL = url.standardizedFileURL
            guard isInsideRoot(receiveURL),
                  let data = try? Data(contentsOf: receiveURL),
                  let record = try? Self.jsonDecoder.decode(RecordingReceiveRecord.self, from: data),
                  let relativePath = try? relativePath(for: receiveURL),
                  let item = StudyItemMetadata.defaultMetadata(for: record, receiveRelativePath: relativePath) else {
                continue
            }
            items.append(item)
        }

        return items
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
        let effectiveFiling = StudyItemMetadata.effectiveFolderPath(for: filing)
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

        let parent = loadStoredFolder(folderID: parentFolderID) ?? StudyFolderMetadata(
            name: parentPath.components.last ?? StudyHierarchyRule.uncategorizedValue,
            level: parentLevel,
            path: StudyFolderMetadata.filingPath(for: parentPath.components),
            parentFolderID: self.parentFolderID(for: parentPath.parent)
        )
        var updatedParent = parent
        if !updatedParent.childFolderIDs.contains(childFolderID) {
            updatedParent.childFolderIDs.append(childFolderID)
            updatedParent.updatedAt = Date()
            try save(updatedParent)
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

    private func relativePath(for url: URL) throws -> String {
        let baseURL = rootURL.standardizedFileURL
        let standardizedURL = url.standardizedFileURL
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : "\(baseURL.path)/"
        let filePath = standardizedURL.path

        guard filePath.hasPrefix(basePath) else {
            throw StudyLibraryStoreError.unsafeDestination
        }

        return String(filePath.dropFirst(basePath.count))
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
