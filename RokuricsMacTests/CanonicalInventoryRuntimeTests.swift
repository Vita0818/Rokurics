//
//  CanonicalInventoryRuntimeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalInventoryRuntimeTests {
    @Test func cacheKeyChangesWithSize() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("a".utf8).write(to: fileURL)

        let first = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL
        )
        try Data("ab".utf8).write(to: fileURL)
        let second = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
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
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL
        )
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: fileURL.path)
        let second = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
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
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL
        )
        let hit = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL
        )

        #expect(hit.event == .hit)
        #expect(hit.hashComputed == false)
        #expect(hit.hashUnavailable == false)
    }

    @Test func cacheHitAvoidsInjectedHashProviderCallAfterRestart() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let counter = HashCounter()
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("cached".utf8).write(to: fileURL)

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            hashProvider: counter.hash
        )
        let restarted = CanonicalChecksumCacheStore()
        let hit = await restarted.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
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
        let config = CanonicalInventoryRuntimeConfiguration(cacheFileName: "mac-key-contract.json", cacheStoreNamespace: "library-a")

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/a.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            configuration: config,
            hashProvider: counter.hash
        )
        let changedToken = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/b.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            configuration: config,
            hashProvider: counter.hash
        )
        let changedAlgorithm = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/a.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            configuration: CanonicalInventoryRuntimeConfiguration(hashAlgorithm: "sha256-v2", cacheFileName: "mac-key-contract.json", cacheStoreNamespace: "library-a"),
            hashProvider: counter.hash
        )
        let changedNamespace = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/a.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            configuration: CanonicalInventoryRuntimeConfiguration(cacheFileName: "mac-key-contract.json", cacheStoreNamespace: "library-b"),
            hashProvider: counter.hash
        )

        #expect(changedToken.event == .miss)
        #expect(changedAlgorithm.event == .stale)
        #expect(changedNamespace.event == .stale)
    }

    @Test func cacheStaleRecomputes() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let fileURL = harness.rootURL.appendingPathComponent("audio.m4a")
        try Data("old".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: fileURL.path)
        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL
        )

        try Data("new".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: fileURL.path)
        let stale = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
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
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            metadataProvider: { _ in CanonicalChecksumFileMetadata(byteSize: 4, modifiedAt: Date(timeIntervalSince1970: 10)) },
            hashProvider: counter.hash
        )
        let mtimeStale = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            metadataProvider: { _ in CanonicalChecksumFileMetadata(byteSize: 4, modifiedAt: Date(timeIntervalSince1970: 11)) },
            hashProvider: counter.hash
        )
        let sizeStale = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
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
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
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
        let config = CanonicalInventoryRuntimeConfiguration(cacheFileName: "mac-atomic-cache.json")

        _ = await harness.cache.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            configuration: config,
            hashProvider: counter.hash
        )
        try FileManager.default.createDirectory(at: harness.cacheURL, withIntermediateDirectories: true)
        try Data("{partial".utf8).write(to: harness.cacheURL.appendingPathComponent("mac-atomic-cache.json.tmp"))
        let restarted = CanonicalChecksumCacheStore()
        let hit = await restarted.checksum(
            fileURL: fileURL,
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
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
        let config = CanonicalInventoryRuntimeConfiguration(cacheFileName: "mac-prune-cache.json", maxCacheRecords: 1)
        let firstURL = harness.rootURL.appendingPathComponent("first.m4a")
        let secondURL = harness.rootURL.appendingPathComponent("second.m4a")
        let nonCacheURL = harness.cacheURL.appendingPathComponent("keep-me.txt")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        try FileManager.default.createDirectory(at: harness.cacheURL, withIntermediateDirectories: true)
        try Data("not-cache".utf8).write(to: nonCacheURL)

        _ = await harness.cache.checksum(
            fileURL: firstURL,
            logicalToken: "inbox/first.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            configuration: config,
            now: Date(timeIntervalSince1970: 1),
            hashProvider: counter.hash
        )
        let second = await harness.cache.checksum(
            fileURL: secondURL,
            logicalToken: "inbox/second.m4a",
            nodeRole: .mac,
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
            logicalToken: "inbox/audio.m4a",
            nodeRole: .mac,
            cacheDirectoryURL: harness.cacheURL,
            clock: CanonicalInventoryRuntimeClock(now: clock.now),
            metadataProvider: { _ in CanonicalChecksumFileMetadata(byteSize: 1, modifiedAt: Date(timeIntervalSince1970: 10)) },
            hashProvider: { _ in String(repeating: "c", count: 64) }
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
            logicalToken: "inbox/missing.m4a",
            nodeRole: .mac,
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

        let existing = await runtimeBuilder.existingSnapshot(syncRunID: "same-run", nodeRole: .mac, sourceKind: .inventoryRequest)
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
            .appendingPathComponent("CanonicalInventoryRuntimeMacTests-\(UUID().uuidString)", isDirectory: true)
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

    private static func snapshot(syncRunID: String) -> CanonicalInventoryRuntimeSnapshot {
        CanonicalInventoryRuntimeSnapshot(
            syncRunID: syncRunID,
            nodeRole: .mac,
            buildStartedAt: Date(timeIntervalSince1970: 1),
            buildEndedAt: Date(timeIntervalSince1970: 2),
            sourceKind: .inventoryRequest,
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
