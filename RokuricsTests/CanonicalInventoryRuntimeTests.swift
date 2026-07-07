//
//  CanonicalInventoryRuntimeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalInventoryRuntimeTests {
    @Test func cacheKeyChangesWithSize() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("a".utf8).write(to: fileURL)

        let first = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )
        try Data("ab".utf8).write(to: fileURL)
        let second = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )

        #expect(first.event == .miss)
        #expect(second.event == .stale)
        #expect(second.hashComputed)
        #expect(first.sha256 != second.sha256)
    }

    @Test func cacheKeyChangesWithMtime() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("same-size".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: fileURL.path)

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: fileURL.path)
        let second = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )

        #expect(second.event == .stale)
        #expect(second.hashComputed)
    }

    @Test func cacheHitAvoidsHash() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("cached".utf8).write(to: fileURL)

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )
        let hit = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )

        #expect(hit.event == .hit)
        #expect(hit.hashComputed == false)
        #expect(hit.hashUnavailable == false)
        var diagnostics = CanonicalInventoryRuntimeDiagnostics()
        diagnostics.merge(hit)
        #expect(diagnostics.checksumCacheHitCount == 1)
        #expect(diagnostics.hashSkippedByCacheHitCount == 1)
    }

    @Test func cacheHitAvoidsInjectedHashProviderCall() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let counter = HashCounter()
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("cached".utf8).write(to: fileURL)

        let first = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            hashProvider: counter.hash
        )
        let second = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            hashProvider: counter.hash
        )

        #expect(first.event == .miss)
        #expect(second.event == .hit)
        #expect(await counter.value() == 1)
        #expect(second.hashComputed == false)
    }

    @Test func cachePersistsAcrossStoreReconstruction() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let counter = HashCounter()
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("restart-hit".utf8).write(to: fileURL)

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            hashProvider: counter.hash
        )
        let restarted = CanonicalChecksumCacheStore()
        let hit = await restarted.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            hashProvider: counter.hash
        )

        #expect(hit.event == .hit)
        #expect(hit.hashComputed == false)
        #expect(await counter.value() == 1)
    }

    @Test func cacheKeyIncludesLogicalTokenAlgorithmSchemaNodeRoleAndNamespace() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let counter = HashCounter()
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("same-bytes".utf8).write(to: fileURL)
        let baseConfig = CanonicalInventoryRuntimeConfiguration(cacheFileName: "key-contract.json", cacheStoreNamespace: "library-a")

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/a.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: baseConfig,
            hashProvider: counter.hash
        )
        let changedToken = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/b.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: baseConfig,
            hashProvider: counter.hash
        )
        let changedAlgorithm = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/a.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: CanonicalInventoryRuntimeConfiguration(hashAlgorithm: "sha256-v2", cacheFileName: "key-contract.json", cacheStoreNamespace: "library-a"),
            hashProvider: counter.hash
        )
        let changedSchema = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/a.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: CanonicalInventoryRuntimeConfiguration(checksumSchemaVersion: 99, cacheFileName: "key-contract.json", cacheStoreNamespace: "library-a"),
            hashProvider: counter.hash
        )
        let changedNamespace = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/a.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: CanonicalInventoryRuntimeConfiguration(cacheFileName: "key-contract.json", cacheStoreNamespace: "library-b"),
            hashProvider: counter.hash
        )

        #expect(changedToken.event == .miss)
        #expect(changedAlgorithm.event == .stale)
        #expect(changedSchema.event == .stale)
        #expect(changedNamespace.event == .stale)
    }

    @Test func schemaMismatchFromDiskInvalidatesFailClosed() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let counter = HashCounter()
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("schema".utf8).write(to: fileURL)
        let oldConfig = CanonicalInventoryRuntimeConfiguration(checksumSchemaVersion: 1, cacheFileName: "schema-cache.json")
        let currentConfig = CanonicalInventoryRuntimeConfiguration(cacheFileName: "schema-cache.json")

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: oldConfig,
            hashProvider: counter.hash
        )
        let restarted = CanonicalChecksumCacheStore()
        let result = await restarted.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: currentConfig,
            hashProvider: counter.hash
        )

        #expect(result.event == .miss)
        #expect(result.failure == .cacheCorrupted)
        #expect(result.hashComputed)
    }

    @Test func cacheStaleRecomputes() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("old".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: fileURL.path)
        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )

        try Data("new".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: fileURL.path)
        let stale = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )

        #expect(stale.event == .stale)
        #expect(stale.hashComputed)
        #expect(stale.sha256 != nil)
    }

    @Test func fakeMetadataProviderInvalidatesMtimeAndSize() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let counter = HashCounter()
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            metadataProvider: { _ in CanonicalChecksumFileMetadata(byteSize: 4, modifiedAt: Date(timeIntervalSince1970: 10)) },
            hashProvider: counter.hash
        )
        let mtimeStale = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            metadataProvider: { _ in CanonicalChecksumFileMetadata(byteSize: 4, modifiedAt: Date(timeIntervalSince1970: 11)) },
            hashProvider: counter.hash
        )
        let sizeStale = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            metadataProvider: { _ in CanonicalChecksumFileMetadata(byteSize: 5, modifiedAt: Date(timeIntervalSince1970: 11)) },
            hashProvider: counter.hash
        )

        #expect(mtimeStale.event == .stale)
        #expect(sizeStale.event == .stale)
        #expect(await counter.value() == 3)
    }

    @Test func cacheCorruptionFailsClosed() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        try FileManager.default.createDirectory(at: harness.cacheURL, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: harness.cacheURL.appendingPathComponent(CanonicalInventoryRuntimeConfiguration().cacheFileName))
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("recover".utf8).write(to: fileURL)

        let result = await CanonicalChecksumCacheStore().checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )

        #expect(result.sha256 != nil)
        #expect(result.hashUnavailable == false)
        #expect(result.failure == .cacheCorrupted)
    }

    @Test func partialTempFileDoesNotBreakAtomicCacheHit() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let counter = HashCounter()
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("atomic".utf8).write(to: fileURL)
        let config = CanonicalInventoryRuntimeConfiguration(cacheFileName: "atomic-cache.json")

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: config,
            hashProvider: counter.hash
        )
        try FileManager.default.createDirectory(at: harness.cacheURL, withIntermediateDirectories: true)
        try Data("{partial".utf8).write(to: harness.cacheURL.appendingPathComponent("atomic-cache.json.tmp"))
        let restarted = CanonicalChecksumCacheStore()
        let hit = await restarted.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: config,
            hashProvider: counter.hash
        )

        #expect(hit.event == .hit)
        #expect(await counter.value() == 1)
    }

    @Test func pruneDropsOldestRecordsAndKeepsNonCacheFiles() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let counter = HashCounter()
        let config = CanonicalInventoryRuntimeConfiguration(cacheFileName: "prune-cache.json", maxCacheRecords: 1)
        let firstURL = harness.rootURL.appendingPathComponent("first.m4a")
        let secondURL = harness.rootURL.appendingPathComponent("second.m4a")
        let nonCacheURL = harness.cacheURL.appendingPathComponent("keep-me.txt")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        try FileManager.default.createDirectory(at: harness.cacheURL, withIntermediateDirectories: true)
        try Data("not-cache".utf8).write(to: nonCacheURL)

        _ = await harness.cache.checksum(
            fileURL: firstURL,
            logicalToken: "recordings/first.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: config,
            now: Date(timeIntervalSince1970: 1),
            hashProvider: counter.hash
        )
        let second = await harness.cache.checksum(
            fileURL: secondURL,
            logicalToken: "recordings/second.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            configuration: config,
            now: Date(timeIntervalSince1970: 2),
            hashProvider: counter.hash
        )

        let records = try Self.cacheRecordCount(cacheURL: harness.cacheURL.appendingPathComponent(config.cacheFileName))
        #expect(second.cachePrunedRecordCount == 1)
        #expect(records == 1)
        #expect(FileManager.default.fileExists(atPath: nonCacheURL.path))
    }

    @Test func telemetryDurationUsesInjectedClock() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let clock = StepClock()
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")

        let result = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "recordings/audio.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL,
            clock: CanonicalInventoryRuntimeClock(now: clock.now),
            metadataProvider: { _ in CanonicalChecksumFileMetadata(byteSize: 1, modifiedAt: Date(timeIntervalSince1970: 10)) },
            hashProvider: { _ in String(repeating: "b", count: 64) }
        )

        #expect(result.hashDurationMs > 0)
        #expect(result.cacheLoadDurationMs > 0)
        #expect(result.cacheWriteDurationMs > 0)
    }

    @Test func hashUnavailableIsNotEqualityProof() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let result = await harness.cache.checksum(
            fileURL: harness.rootURL.appendingPathComponent("missing.m4a"),
            logicalToken: "recordings/missing.m4a",
            nodeRole: .iPhone,
            cacheDirectoryURL: harness.cacheURL
        )

        #expect(result.sha256 == nil)
        #expect(result.hashUnavailable)
        #expect(result.failure == .fileMetadataUnavailable)
    }

    @Test func snapshotReportIsRedacted() throws {
        let snapshot = Self.snapshot(syncRunID: "runtime-report")
        let json = try CanonicalInventoryRuntimeReportExporter.jsonString(from: snapshot)

        #expect(json.contains("\"redacted\":true"))
        #expect(json.contains("/Users/") == false)
        #expect(json.contains(String(repeating: "a", count: 64)) == false)
    }

    @Test func duplicateSnapshotSuppressionWorks() async {
        let runtimeBuilder = CanonicalInventoryRuntimeBuilder()
        let snapshot = Self.snapshot(syncRunID: "same-run")
        await runtimeBuilder.remember(snapshot)

        let existing = await runtimeBuilder.existingSnapshot(syncRunID: "same-run", nodeRole: .iPhone, sourceKind: .syncTick)
        let reused = await runtimeBuilder.reusedSnapshot(existing ?? snapshot)

        #expect(existing != nil)
        #expect(reused.reusedWithinTick)
        #expect(reused.diagnostics.duplicateBuildCount == 0)
    }

    @Test func mainActorHashBlockerCountIsReportable() {
        var snapshot = Self.snapshot(syncRunID: "blocked")
        snapshot.diagnostics.mainActorHashBlockedCount = 1
        let report = CanonicalInventoryRuntimeReportExporter.report(from: snapshot)

        #expect(report.mainActorHashBlockedCount == 1)
    }

    @MainActor
    @Test func appInventoryBuilderRecordsRealOffMainTelemetry() async throws {
        let harness = try Self.makeAppHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        _ = try Self.saveRecording(id: "inventory-off-main", title: "Off Main", store: harness.audioStore)

        let build = await LocalNetworkSyncInventoryBuilder(
            audioFileStore: harness.audioStore,
            studyLibraryStore: harness.studyStore,
            uploadJobStore: harness.jobStore,
            diagnosticsStore: harness.diagnosticsStore
        ).buildRuntimeSnapshot(
            deviceID: "iphone-inventory",
            deviceName: "iPhone",
            lastKnownPeerRevision: nil,
            generatedAt: Date(timeIntervalSince1970: 10),
            shadowSyncRunID: "inventory-off-main-run"
        )

        #expect(build.report.mainActorHashAttemptCount == 0)
        #expect(build.report.mainActorScanAttemptCount == 0)
        #expect(build.report.mainActorMetadataLoadAttemptCount == 0)
        #expect(build.report.mainActorJobsLoadAttemptCount == 0)
        #expect(build.report.mainActorManifestBuildAttemptCount == 0)
        #expect(build.report.mainActorHashBlockedCount == 0)
        #expect(build.report.mainActorScanBlockedCount == 0)
        #expect(build.report.metadataLoadDurationMs >= 0)
        #expect(build.report.jobsLoadDurationMs >= 0)
        #expect(build.report.manifestBuildDurationMs >= 0)
        #expect(build.report.scanDurationMs >= 0)
        #expect(build.report.hashComputedCount > 0)
        #expect(build.report.hashSkippedByCacheHitCount >= 0)
        #expect(build.inventory.recordings.count == 1)
    }

    @MainActor
    @Test func backgroundManifestBuilderMatchesStoreManifestForPersistedFacts() async throws {
        let harness = try Self.makeAppHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let metadata = try Self.saveRecording(id: "background-manifest", title: "Background Manifest", store: harness.audioStore)
        _ = try harness.studyStore.upsertRecordingMetadata(metadata)
        let generatedAt = Date(timeIntervalSince1970: 12)

        let background = await harness.studyStore.makeSyncManifestInBackground(
            deviceID: "iphone-manifest",
            generatedAt: generatedAt
        )
        let legacy = harness.studyStore.makeSyncManifest(
            deviceID: "iphone-manifest",
            generatedAt: generatedAt
        )

        #expect(background.checksum == legacy.checksum)
        #expect(background.items == legacy.items)
        #expect(background.folders == legacy.folders)
        #expect(background.recordings == legacy.recordings)
        #expect(background.pendingUploads == legacy.pendingUploads)
    }

    @MainActor
    @Test func appInventoryBuilderReusesSnapshotForSameSyncRunID() async throws {
        let harness = try Self.makeAppHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        _ = try Self.saveRecording(id: "inventory-reuse", title: "Reuse", store: harness.audioStore)
        let builder = LocalNetworkSyncInventoryBuilder(
            audioFileStore: harness.audioStore,
            studyLibraryStore: harness.studyStore,
            uploadJobStore: harness.jobStore,
            diagnosticsStore: harness.diagnosticsStore
        )

        _ = await builder.buildRuntimeSnapshot(
            deviceID: "iphone-inventory",
            deviceName: "iPhone",
            lastKnownPeerRevision: nil,
            generatedAt: Date(timeIntervalSince1970: 10),
            shadowSyncRunID: "same-sync-run"
        )
        let second = await builder.buildRuntimeSnapshot(
            deviceID: "iphone-inventory",
            deviceName: "iPhone",
            lastKnownPeerRevision: nil,
            generatedAt: Date(timeIntervalSince1970: 10),
            shadowSyncRunID: "same-sync-run"
        )

        #expect(second.snapshot.reusedWithinTick)
        #expect(second.report.duplicateBuildCount == 1)
    }

    @Test func diagnosticsOmitFullPathsAndHashes() {
        let summary = CanonicalInventoryRuntimeReportExporter.diagnosticsSummary(from: Self.snapshot(syncRunID: "redacted"))

        #expect(summary.contains("/Users/") == false)
        #expect(summary.contains(String(repeating: "a", count: 64)) == false)
        #expect(summary.contains("redacted=true"))
    }

    @Test func performanceGuardReportsMainActorAttemptsWithoutChangingSync() {
        var snapshot = Self.snapshot(syncRunID: "performance")
        snapshot.diagnostics.mainActorManifestBuildAttemptCount = 1
        let report = CanonicalInventoryPerformanceRegressionGuard.evaluate(snapshot: snapshot)

        #expect(report.blockers.contains("mainActorAttemptCount"))
        #expect(report.redacted)
    }

    private struct Harness {
        let rootURL: URL
        let cacheURL: URL
        let cache: CanonicalChecksumCacheStore
    }

    private struct AppHarness {
        let rootURL: URL
        let audioStore: AudioFileStore
        let studyStore: StudyLibraryStore
        let jobStore: RecordingUploadJobStore
        let diagnosticsStore: ConnectionDiagnosticsStore
    }

    private actor HashCounter {
        private var count = 0

        func hash(_ url: URL) async throws -> String {
            count += 1
            let current = count
            return String(repeating: String(format: "%02x", current), count: 32)
        }

        func value() -> Int {
            count
        }
    }

    private final class StepClock: @unchecked Sendable {
        private let lock = NSLock()
        private var tick: TimeInterval = 0

        func now() -> Date {
            lock.lock()
            defer {
                tick += 1
                lock.unlock()
            }
            return Date(timeIntervalSince1970: tick)
        }
    }

    private static func makeHarness() throws -> Harness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalInventoryRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return Harness(
            rootURL: rootURL,
            cacheURL: rootURL.appendingPathComponent("ChecksumCache", isDirectory: true),
            cache: CanonicalChecksumCacheStore()
        )
    }

    private static func cacheRecordCount(cacheURL: URL) throws -> Int {
        let data = try Data(contentsOf: cacheURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["records"] as? [Any])?.count ?? 0
    }

    @MainActor
    private static func makeAppHarness() throws -> AppHarness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalInventoryRuntimeAppTests-\(UUID().uuidString)", isDirectory: true)
        let audioStore = AudioFileStore(rootDirectoryURL: rootURL)
        try audioStore.ensureStorageDirectories()
        let studyStore = StudyLibraryStore(rootURL: rootURL, audioFileStore: audioStore)
        let jobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        return AppHarness(
            rootURL: rootURL,
            audioStore: audioStore,
            studyStore: studyStore,
            jobStore: jobStore,
            diagnosticsStore: diagnosticsStore
        )
    }

    private static func saveRecording(
        id: String,
        title: String,
        store: AudioFileStore,
        audioData: Data = Data("audio".utf8)
    ) throws -> RecordingMetadata {
        let audioURL = try store.recordingsDirectory()
            .appendingPathComponent(id, isDirectory: false)
            .appendingPathExtension("m4a")
        try audioData.write(to: audioURL)
        let metadataURL = try store.makeMetadataURL(id: id)
        let metadata = RecordingMetadata(
            id: id,
            title: title,
            fileName: "\(id).m4a",
            relativeAudioPath: try store.relativePath(for: audioURL),
            relativeMetadataPath: try store.relativePath(for: metadataURL),
            createdAt: Date(timeIntervalSince1970: 10),
            endedAt: Date(timeIntervalSince1970: 16),
            duration: 6,
            format: "m4a",
            codec: "AAC",
            sampleRate: 16_000,
            channels: 1,
            bitrate: 64_000,
            fileSize: Int64(audioData.count),
            uploadStatus: "localOnly",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            tags: [],
            studyFiling: nil
        )
        try store.saveMetadata(metadata)
        return metadata
    }

    private static func snapshot(syncRunID: String) -> CanonicalInventoryRuntimeSnapshot {
        CanonicalInventoryRuntimeSnapshot(
            syncRunID: syncRunID,
            nodeRole: .iPhone,
            buildStartedAt: Date(timeIntervalSince1970: 1),
            buildEndedAt: Date(timeIntervalSince1970: 2),
            sourceKind: .syncTick,
            objectCounts: CanonicalInventoryObjectCounts(
                recordingMetadataCount: 1,
                libraryFolderCount: 1,
                libraryItemCount: 1,
                artifactCount: 1,
                audioDescriptorCount: 1
            ),
            diagnostics: CanonicalInventoryRuntimeDiagnostics(),
            mainActorBlocked: false,
            reusedWithinTick: false,
            redacted: true
        )
    }
}
