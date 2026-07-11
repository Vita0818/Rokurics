//
//  CanonicalFileKernelRuntimeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalFileKernelRuntimeTests {
    @MainActor
    @Test func fileSnapshotBuildsOffMainAndRejectsUnsafeTokens() async throws {
        let fullHash = String(repeating: "a", count: 64)
        let entry = try CanonicalFileSnapshotSourceEntry(
            logicalToken: "inbox/audio.m4a",
            kind: .file,
            byteSize: 12,
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 1_000)),
            contentVersion: "v1",
            domainHint: .recordingAudio,
            hashProof: CanonicalHash(fullHash)
        )
        let scope = try CanonicalFileSnapshotScope(
            rootToken: CanonicalRootToken("mac-test-root"),
            logicalScopeToken: ".",
            domainHint: .studyLibraryMetadata
        )
        let snapshot = try await CanonicalFileTreeSnapshotBuilder(
            adapter: CanonicalStaticFileSnapshotAdapter(entries: [entry])
        ).buildSnapshot(scope: scope)
        let encoded = String(data: try JSONEncoder().encode(snapshot), encoding: .utf8) ?? ""

        #expect(snapshot.entries.count == 1)
        #expect(snapshot.builtOffMainActor)
        #expect(snapshot.mainActorAttemptCount == 0)
        #expect(snapshot.entries.first?.stableFileIdentity.isEmpty == false)
        #expect(!encoded.contains("/Users/"))
        #expect(throws: CanonicalFileRuntimeError.absolutePathRejected("/Users/vita/audio.m4a")) {
            _ = try CanonicalFileSnapshotSourceEntry(logicalToken: "/Users/vita/audio.m4a", kind: .file)
        }
    }

    @Test func manifestCacheKeyIsContentStableAndIgnoresCapturedAt() throws {
        let fullHash = String(repeating: "b", count: 64)
        let scope = try CanonicalFileSnapshotScope(
            rootToken: CanonicalRootToken("manifest-root"),
            logicalScopeToken: ".",
            domainHint: .studyLibraryMetadata
        )
        let entry = CanonicalFileSnapshotEntry(
            stableFileIdentity: "file-1",
            rootToken: scope.rootToken,
            logicalToken: "metadata/recording.json",
            kind: .file,
            byteSize: 42,
            modifiedAtEpochMs: 1_000,
            contentVersion: "v1",
            domainHint: .recordingMetadata,
            hashProof: CanonicalHash(fullHash)
        )
        let first = CanonicalFileRuntimeSnapshot(
            scope: scope,
            capturedAt: Date(timeIntervalSince1970: 10),
            entries: [entry],
            builtOffMainActor: true,
            durationMs: 1,
            mainActorAttemptCount: 0
        )
        let second = CanonicalFileRuntimeSnapshot(
            scope: scope,
            capturedAt: Date(timeIntervalSince1970: 99),
            entries: [entry],
            builtOffMainActor: true,
            durationMs: 5,
            mainActorAttemptCount: 0
        )
        var changedEntry = entry
        changedEntry.byteSize = 43
        let changed = CanonicalFileRuntimeSnapshot(
            scope: scope,
            capturedAt: Date(timeIntervalSince1970: 99),
            entries: [changedEntry],
            builtOffMainActor: true,
            durationMs: 5,
            mainActorAttemptCount: 0
        )
        let builder = CanonicalManifestRuntimeBuilder()

        #expect(builder.buildFileManifest(from: first).cacheKey.cacheKeyHashPrefix == builder.buildFileManifest(from: second).cacheKey.cacheKeyHashPrefix)
        #expect(builder.buildFileManifest(from: first).cacheKey.cacheKeyHashPrefix != builder.buildFileManifest(from: changed).cacheKey.cacheKeyHashPrefix)
    }

    @Test func checksumCacheHitSkipsHashAndStalesOnContentFacts() async throws {
        let runtime = CanonicalFileChecksumRuntime()
        let modifiedAt = Date(timeIntervalSince1970: 1_000)
        let fullHash = String(repeating: "c", count: 64)
        let calls = LockedCounter()
        let first = try CanonicalFileChecksumRequest(
            rootToken: CanonicalRootToken("checksum-root"),
            logicalToken: "inbox/audio.m4a",
            byteSize: 10,
            modifiedAt: modifiedAt,
            contentVersion: "v1",
            domainHint: .recordingAudio
        ) {
            calls.increment()
            return fullHash
        }
        let firstResult = await runtime.checksum(first)
        let secondResult = await runtime.checksum(first)
        let stale = try CanonicalFileChecksumRequest(
            rootToken: CanonicalRootToken("checksum-root"),
            logicalToken: "inbox/audio.m4a",
            byteSize: 11,
            modifiedAt: modifiedAt,
            contentVersion: "v1",
            domainHint: .recordingAudio
        ) {
            calls.increment()
            return String(repeating: "d", count: 64)
        }
        let staleResult = await runtime.checksum(stale)

        #expect(firstResult.event == .miss)
        #expect(secondResult.event == .hit)
        #expect(!secondResult.hashComputed)
        #expect(staleResult.event == .stale)
        #expect(calls.value == 2)
        #expect(secondResult.hashPrefix == String(fullHash.prefix(12)))
    }

    @Test func asyncDiagnosticsWriterRejectsUnsafeDetailsAndUsesClock() async {
        let sink = CanonicalInMemoryDiagnosticsSink()
        let clock = LockedTestClock(start: 1_000, stepMilliseconds: 7)
        let writer = CanonicalAsyncDiagnosticsWriter(
            sink: sink,
            configuration: CanonicalAsyncDiagnosticsWriterConfiguration(maxQueuedEvents: 1),
            clock: CanonicalInventoryRuntimeClock(now: clock.now)
        )
        let safe = CanonicalKernelDiagnosticRecord(
            kind: .diagnosticsWriteDurationMs,
            domain: .file,
            redactedDetail: "cacheKeyPrefix=abc123,hashPrefix=abcdef123456"
        )
        let unsafe = CanonicalKernelDiagnosticRecord(
            kind: .diagnosticsWriteDurationMs,
            domain: .file,
            redactedDetail: "provider response /Users/vita/private.json"
        )

        #expect(await writer.enqueue(safe) == .enqueued)
        #expect(await writer.enqueue(unsafe) == .rejectedRedaction)
        await writer.drain()
        let metrics = await writer.currentMetrics()
        let lines = await sink.allLines()

        #expect(metrics.writtenCount == 1)
        #expect(metrics.rejectedCount == 1)
        #expect(metrics.diagnosticsWriteDurationMs > 0)
        #expect(lines.count == 1)
        #expect(!lines.joined().contains("/Users/"))
        #expect(!lines.joined().contains("provider response"))
    }

    @Test func asyncDiagnosticsWriterCriticalEvictsNormalAndCannotBeEvictedByNormal() async {
        let sink = CanonicalInMemoryDiagnosticsSink()
        let writer = CanonicalAsyncDiagnosticsWriter(
            sink: sink,
            configuration: CanonicalAsyncDiagnosticsWriterConfiguration(
                maxQueuedEvents: 2,
                automaticallyFlush: false
            )
        )
        let firstNormal = CanonicalKernelDiagnosticRecord(
            kind: .diagnosticsWriteDurationMs,
            domain: .file,
            redactedDetail: "event=first-normal"
        )
        let secondNormal = CanonicalKernelDiagnosticRecord(
            kind: .diagnosticsWriteDurationMs,
            domain: .file,
            redactedDetail: "event=second-normal"
        )
        let critical = CanonicalKernelDiagnosticRecord(
            kind: .diagnosticsWriteDurationMs,
            domain: .file,
            redactedDetail: "event=critical-terminal"
        )
        let lateNormal = CanonicalKernelDiagnosticRecord(
            kind: .diagnosticsWriteDurationMs,
            domain: .file,
            redactedDetail: "event=late-normal"
        )

        #expect(await writer.enqueue(firstNormal) == .enqueued)
        #expect(await writer.enqueue(secondNormal) == .enqueued)
        #expect(await writer.enqueue(critical, priority: .critical) == .enqueued)
        #expect(await writer.enqueue(lateNormal) == .droppedBackpressure)
        await writer.drainForTests()
        let metrics = await writer.currentMetrics()
        let lines = await sink.allLines()
        let text = lines.joined(separator: "\n")

        #expect(text.contains("first-normal") == false)
        #expect(text.contains("second-normal"))
        #expect(text.contains("critical-terminal"))
        #expect(text.contains("late-normal") == false)
        #expect(metrics.enqueuedCount == 3)
        #expect(metrics.droppedCount == 2)
        #expect(metrics.writtenCount == 2)
    }

    @MainActor
    @Test func connectionDiagnosticsRecordIsMainActorNonBlockingAndFlushesRedactedJSONL() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConnectionDiagnosticsAsync-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConnectionDiagnosticsStore(
            rootURL: root,
            maxEntries: 25,
            diagnosticsWriterConfiguration: CanonicalAsyncDiagnosticsWriterConfiguration(
                maxQueuedEvents: 1_100,
                automaticallyFlush: false
            )
        )
        let fullHash = String(repeating: "b", count: 64)

        for index in 0..<1_000 {
            store.record(
                phase: "mainActorRecord\(index)",
                host: "127.0.0.1",
                port: 8787,
                fingerprint: fullHash,
                listenerState: "running",
                activePort: 8787,
                routePath: "/sync/inventory",
                errorMessage: index == 999 ? "provider response /Users/vita/private.json hash=\(fullHash)" : nil,
                timestamp: Date(timeIntervalSince1970: Double(index))
            )
        }

        #expect(FileManager.default.fileExists(atPath: store.logURL.path) == false)
        #expect(store.loadEntries().count == 25)

        await store.flushForTests()
        let raw = try String(contentsOf: store.logURL, encoding: .utf8)
        let lines = raw.split(separator: "\n")
        let metrics = await store.diagnosticsWriterMetricsForTests()

        #expect(lines.count == 25)
        #expect(metrics.enqueuedCount == 1_000)
        #expect(metrics.writtenCount == 1_000)
        #expect(raw.contains("/Users/") == false)
        #expect(raw.contains(fullHash) == false)
        #expect(raw.contains("provider response") == false)
        #expect(raw.contains("redactionRejected"))
    }

    @MainActor
    @Test func connectionDiagnosticsNoiseStormPersistsCriticalTerminalsInOrder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacConnectionDiagnosticsCriticalStorm-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ConnectionDiagnosticsStore(
            rootURL: root,
            maxEntries: 10,
            diagnosticsWriterConfiguration: CanonicalAsyncDiagnosticsWriterConfiguration(
                maxQueuedEvents: 5,
                automaticallyFlush: false
            )
        )

        for index in 0..<100 {
            store.record(
                phase: "noiseBefore\(index)",
                host: nil,
                port: nil,
                fingerprint: nil,
                listenerState: nil,
                activePort: nil,
                errorCategory: "normal"
            )
        }
        for phase in [
            "syncRunCompleted",
            "syncTickFailed",
            "uploadFinalizeFailed",
            "metadataApplyFailed"
        ] {
            store.record(
                phase: phase,
                host: nil,
                port: nil,
                fingerprint: nil,
                listenerState: nil,
                activePort: nil,
                syncRunID: "critical-run"
            )
        }
        store.record(
            phase: "ordinaryPhaseWithError",
            host: nil,
            port: nil,
            fingerprint: nil,
            listenerState: nil,
            activePort: nil,
            syncRunID: "critical-run",
            errorCode: "forced_error"
        )
        for index in 0..<100 {
            store.record(
                phase: "noiseAfter\(index)",
                host: nil,
                port: nil,
                fingerprint: nil,
                listenerState: nil,
                activePort: nil,
                errorCategory: "normal"
            )
        }

        await store.flushForTests()
        let raw = try String(contentsOf: store.logURL, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let phases = raw
            .split(separator: "\n")
            .compactMap { try? decoder.decode(ConnectionDiagnosticEntry.self, from: Data($0.utf8)).phase }
        let metrics = await store.diagnosticsWriterMetricsForTests()

        #expect(phases == [
            "syncRunCompleted",
            "syncTickFailed",
            "uploadFinalizeFailed",
            "metadataApplyFailed",
            "ordinaryPhaseWithError"
        ])
        #expect(metrics.droppedCount > 0)
        #expect(metrics.writtenCount == 5)
    }

    @Test func mainActorHotPathGuardCountsInjectedAttempts() async {
        let guardOn = CanonicalMainActorHotPathGuard(isMainActorHotPath: { true })
        await guardOn.recordAttempt(kind: .fileTreeSnapshot, reason: "fileTreeSnapshot")
        await guardOn.recordAttempt(kind: .manifestBuild, reason: "manifestBuild")
        await guardOn.recordAttempt(kind: .fullHash, reason: "fullHash")
        await guardOn.recordAttempt(kind: .diagnosticsWrite, reason: "diagnosticsWrite")
        await guardOn.recordAttempt(kind: .readProjectionRebuild, reason: "readProjectionRebuild")
        await guardOn.recordAttempt(kind: .statusTruthReconciliation, reason: "statusTruthReconciliation")
        await guardOn.recordAttempt(kind: .effectiveStatusProjection, reason: "effectiveStatusProjection")
        let counted = await guardOn.snapshot()

        let guardOff = CanonicalMainActorHotPathGuard(isMainActorHotPath: { false })
        await guardOff.recordAttempt(kind: .diagnosticsWrite, reason: "diagnosticsWrite")
        let skipped = await guardOff.snapshot()

        #expect(counted.fileTreeSnapshotAttemptCount == 1)
        #expect(counted.manifestBuildAttemptCount == 1)
        #expect(counted.fullHashAttemptCount == 1)
        #expect(counted.diagnosticsWriteAttemptCount == 1)
        #expect(counted.readProjectionRebuildAttemptCount == 1)
        #expect(counted.statusTruthReconciliationAttemptCount == 1)
        #expect(counted.effectiveStatusProjectionAttemptCount == 1)
        #expect(counted.totalAttemptCount == 7)
        #expect(skipped.totalAttemptCount == 0)
    }

    @Test func readinessV910ReportsNoFreezeScorecardAndUnsafeBlockers() {
        let ready = CanonicalFileKernelRuntimeReadiness.v910(
            CanonicalFileKernelRuntimeEvidence(
                fileTreeOffMainReady: true,
                manifestOffMainReady: true,
                checksumCacheReady: true,
                contentStableCacheKeyReady: true,
                asyncDiagnosticsReady: true,
                mainActorGuardReady: true,
                readProjectionCacheReady: true,
                macInventoryRouteReady: true,
                diagnosticsRedacted: true,
                routeSecurityUnchanged: true,
                defaultReleaseOldKernel: true,
                legacyFallbackPreserved: true,
                uploadRouteSchemaUnchanged: true,
                requestVerifierPreserved: true
            )
        )
        let unsafe = CanonicalFileKernelRuntimeReadiness.v910(
            CanonicalFileKernelRuntimeEvidence(
                routeSecurityUnchanged: false,
                defaultReleaseOldKernel: false,
                legacyFallbackPreserved: false,
                uploadRouteSchemaUnchanged: false,
                requestVerifierPreserved: false,
                diagnosticsLeakDetected: true,
                mainActorHeavyWorkDetected: true
            )
        )

        #expect(ready.readyForV910FileKernelRuntime)
        #expect(ready.noFreezeScorecard.macInventoryRouteReady)
        #expect(ready.noFreezeScorecard.diagnosticsRedacted)
        #expect(unsafe.status == .unsafeToProceed)
        #expect(unsafe.blockers.contains(.routeSecurityChanged))
        #expect(unsafe.blockers.contains(.requestVerifierBypassed))
        #expect(unsafe.blockers.contains(.mainActorHeavyWorkDetected))
    }

    @Test func redactionRejectsAbsolutePathFullHashRequestBodyAndProviderOutput() {
        let fullHash = String(repeating: "f", count: 64)
        let unsafe = "request body /Users/vita/private.json provider response \(fullHash)"
        let signals = CanonicalKernelDiagnosticRedaction.detectForbiddenSignals(in: unsafe)

        #expect(signals.contains(.absolutePath))
        #expect(signals.contains(.fullHash))
        #expect(signals.contains(.requestBody))
        #expect(signals.contains(.providerResponse))
        #expect(!CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(unsafe))
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class LockedTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: TimeInterval
    private let step: TimeInterval

    init(start: TimeInterval, stepMilliseconds: Int) {
        self.current = start
        self.step = TimeInterval(stepMilliseconds) / 1_000
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        let date = Date(timeIntervalSince1970: current)
        current += step
        return date
    }
}
