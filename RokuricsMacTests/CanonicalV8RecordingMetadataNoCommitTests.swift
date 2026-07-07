//
//  CanonicalV8RecordingMetadataNoCommitTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalV8RecordingMetadataNoCommitTests {
    @Test func v8CutoverSeamConfigIsDisabledByDefaultAndOnlyAllowsNoCommit() {
        let disabled = CanonicalCutoverAppSeamConfiguration()
        #expect(disabled.isEnabled == false)
        #expect(disabled.effectiveMode == .disabled)

        let commit = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: .enabled(mode: .guardedExecuteCommit, evidence: RecordingMetadataCutoverTestSupport.evidence()),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic
        )
        let production = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: .enabled(mode: .productionExecute, evidence: RecordingMetadataCutoverTestSupport.evidence()),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic
        )
        let canary = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: .enabled(mode: .canaryCommit, evidence: RecordingMetadataCutoverTestSupport.evidence()),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic
        )
        let unsupportedDomain = CanonicalRecordingMetadataNoCommitRunner().evaluateGate(
            configuration: .enabled(domain: .folders, evidence: RecordingMetadataCutoverTestSupport.evidence()),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic
        )

        #expect(commit.failures.contains(.guardedExecuteCommitDenied))
        #expect(production.failures.contains(.productionExecuteDenied))
        #expect(canary.failures.contains(.canaryCommitDenied))
        #expect(unsupportedDomain.failures.contains(.unsupportedDomain))
    }

    @Test func noCommitRunnerDoesNotCommitSuppressLegacyOrSendNetwork() throws {
        let result = Self.runNoCommit(candidates: [Self.noCommitCandidate(kind: .recordingMetadataSend, legacyDirection: .send, includeLegacyPayloadEvidence: true)])
        let candidate = try #require(result.candidateResults.first)
        let staging = try #require(candidate.staging)

        #expect(result.gate.allowed)
        #expect(candidate.equivalence.status == .equivalent)
        #expect(result.productionCommitSuppressed)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(staging.sentNetworkRequest == false)
        #expect(staging.calledApplySyncManifest == false)
        #expect(staging.wroteProductionStore == false)
        #expect(staging.routePath == "/sync/apply-metadata")
        #expect(result.diagnostics.contains { $0.kind == .canonicalV8NoCommitCommitSuppressed })
        #expect(result.diagnostics.contains { $0.kind == .canonicalV8NoCommitLegacyDuplicatePreserved })
        #expect(result.evidenceReport.productionCommitSuppressed)
        #expect(result.evidenceReport.legacyDuplicateSuppressed == false)
    }

    @Test func canonicalMoreAggressiveAndInsufficientEvidenceAreBlockingButNonfatal() throws {
        let aggressive = Self.runNoCommit(candidates: [Self.noCommitCandidate(legacyDirection: .none)])
        let insufficientEvidence = CanonicalRecordingMetadataNoCommitRunner().run(
            configuration: .enabled(),
            candidates: [Self.noCommitCandidate()],
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "mac-v8-insufficient-evidence",
            executor: MacRecordingMetadataNoCommitExecutor(stagingRootURL: Self.makeScratchRoot("MacV8NoCommitInsufficient"))
        )

        #expect(try #require(aggressive.candidateResults.first).equivalence.status == .canonicalMoreAggressive)
        #expect(aggressive.nonfatalFailureCount == 1)
        #expect(insufficientEvidence.gate.failures.contains(.insufficientEvidence))
        #expect(insufficientEvidence.diagnostics.contains { $0.kind == .canonicalV8RecordingMetadataNoCommitInsufficientEvidence })
    }

    @Test func macExecutorWritesOnlyStagingRoot() throws {
        let rootURL = Self.makeScratchRoot("MacV8NoCommitStaging")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let executor = MacRecordingMetadataNoCommitExecutor(stagingRootURL: rootURL)
        let staging = executor.stageNoCommit(Self.noCommitCandidate())

        let logicalPath = try #require(staging.stagedLogicalPathToken)
        #expect(staging.staged)
        #expect(staging.wroteOnlyStagingRoot)
        #expect(staging.stagingEvidence?.lifecycleStatus == .created)
        #expect(staging.cleanupEvidence?.status == .removed)
        #expect(staging.wroteProductionStore == false)
        #expect(staging.calledApplySyncManifest == false)
        #expect(staging.sentNetworkRequest == false)
        #expect(staging.suppressedLegacyDuplicate == false)
        #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(logicalPath).path) == false)
        #expect(FileManager.default.fileExists(atPath: rootURL.path) == false)
    }

    @Test func macExecutorCanRetainExplicitStagingRootForDiagnostics() throws {
        let rootURL = Self.makeScratchRoot("MacV8NoCommitRetainedStaging")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let executor = MacRecordingMetadataNoCommitExecutor(
            stagingRootURL: rootURL,
            cleanupPolicy: .retainForDiagnostics(maxAge: 3_600, maxCount: 4, maxBytes: 1_000_000)
        )
        let staging = executor.stageNoCommit(Self.noCommitCandidate())

        let logicalPath = try #require(staging.stagedLogicalPathToken)
        #expect(staging.staged)
        #expect(staging.cleanupEvidence?.status == .retainedForDiagnostics)
        #expect(FileManager.default.fileExists(atPath: rootURL.appendingPathComponent(logicalPath).path))
    }

    @Test func diagnosticsAreRedactedAndUseHashPrefixesOnly() {
        let result = Self.runNoCommit(candidates: [Self.noCommitCandidate(kind: .recordingMetadataSend, legacyDirection: .send, includeLegacyPayloadEvidence: true)])
        let summaries = result.diagnostics.map(\.diagnosticsSummary).joined(separator: "\n")

        #expect(summaries.contains("/Users/") == false)
        #expect(summaries.contains("/private/") == false)
        #expect(summaries.contains(String(repeating: "a", count: 64)) == false)
        #expect(summaries.contains("/sync/apply-metadata"))
    }

    @Test func macInventoryDefaultV8SeamRecordsNoDiagnostics() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v8-disabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory != nil)
        #expect(events.contains { $0.phase == "canonicalV8CutoverSeamStarted" } == false)
    }

    @Test func macInventoryEnabledV8SeamDoesNotChangeResponseAndRecordsMissingPeerSnapshot() async throws {
        let harness = try Self.makeHarness(v8Configuration: .enabled())
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v8-enabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(events.contains { $0.phase == "canonicalV8CutoverSeamStarted" })
        #expect(events.contains { $0.phase == "canonicalV8CutoverSeamCompleted" })
        #expect(events.first { $0.phase == "canonicalV8RecordingMetadataNoCommitInsufficientEvidence" }?.errorMessage?.contains("insufficientPeerSnapshot") == true)
        #expect(events.contains { $0.phase == "canonicalV8RecordingMetadataNoCommitProductionCommitSuppressed" } == false)
    }

    private struct Harness {
        let rootURL: URL
        let server: SecureLocalHTTPSServer
        let recorder: V8DiagnosticRecorder
    }

    private static func makeHarness(
        v8Configuration: CanonicalCutoverAppSeamConfiguration = .disabled
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("MacV8NoCommitSeam")
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let recorder = V8DiagnosticRecorder()
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Recordings", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: MacIdentityManager(securityDirectoryURL: securityURL, tlsKeyTagNamespace: "v8-no-commit-\(UUID().uuidString)"),
            pairingManager: PairingManager(pairedDeviceStore: pairedDeviceStore),
            requestVerifier: RequestVerifier(pairedDeviceStore: pairedDeviceStore),
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingFileStore,
            studyLibraryStore: studyLibraryStore,
            gitBackedStudyMetadataStore: nil,
            deviceConnectionStatusStore: DeviceConnectionStatusStore(rootURL: rootURL.appendingPathComponent("ConnectionStatus", isDirectory: true)),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true)),
            onReady: {},
            onFailed: { _ in },
            onPairingChanged: {},
            onUploadAccepted: { _ in },
            onRecordingAccepted: { _, _ in },
            onConnectionDiagnostic: { recorder.record($0) },
            canonicalV8CutoverAppSeamConfiguration: v8Configuration,
            canonicalKernelMode: .canonicalShadow
        )
        return Harness(rootURL: rootURL, server: server, recorder: recorder)
    }

    private static func runNoCommit(
        candidates: [CanonicalRecordingMetadataNoCommitCandidate]
    ) -> CanonicalRecordingMetadataNoCommitResult {
        let rootURL = Self.makeScratchRoot("MacV8NoCommitRunner")
        return CanonicalRecordingMetadataNoCommitRunner().run(
            configuration: .enabled(evidence: RecordingMetadataCutoverTestSupport.evidence()),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "mac-v8-no-commit",
            executor: MacRecordingMetadataNoCommitExecutor(stagingRootURL: rootURL)
        )
    }

    private static func noCommitCandidate(
        kind: CanonicalApplyActionKind = .recordingMetadataApply,
        legacyDirection: CanonicalRecordingMetadataNoCommitDirection = .apply,
        includeLegacyPayloadEvidence: Bool = false
    ) -> CanonicalRecordingMetadataNoCommitCandidate {
        let cutover = kind == .recordingMetadataSend
            ? Self.sendCutoverCandidate()
            : RecordingMetadataCutoverTestSupport.candidate(kind: kind)
        var candidate = CanonicalRecordingMetadataNoCommitCandidate(
            cutoverCandidate: cutover,
            legacyDirection: legacyDirection,
            legacyObjectID: cutover.objectID,
            expectedRoutePath: kind == .recordingMetadataSend ? "/sync/apply-metadata" : nil
        )
        guard includeLegacyPayloadEvidence else {
            return candidate
        }
        let bytes = CanonicalRecordingMetadataNoCommitPayloadSummary(candidate: candidate).encodedBytes()
        candidate = CanonicalRecordingMetadataNoCommitCandidate(
            cutoverCandidate: cutover,
            legacyDirection: legacyDirection,
            legacyObjectID: cutover.objectID,
            legacyPayloadByteCount: bytes.count,
            legacyPayloadHashPrefix: CanonicalTransportEnvelope.hash(bytes).value,
            expectedRoutePath: "/sync/apply-metadata"
        )
        return candidate
    }

    private static func pairedDevice() -> PairedDevice {
        PairedDevice(
            id: "iphone-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: Data("v8-no-commit-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
    }

    private static func sendCutoverCandidate(id: String = "recording-01") -> CanonicalRecordingMetadataCutoverCandidate {
        let local = CanonicalProductionTestFixtures.recording(
            id: id,
            title: "LocalNewer",
            modifiedAt: CanonicalProductionTestFixtures.date(2_200)
        )
        let peer = CanonicalProductionTestFixtures.recording(
            id: id,
            title: "PeerOlder",
            modifiedAt: CanonicalProductionTestFixtures.date(2_100)
        )
        return CanonicalRecordingMetadataCutoverCandidate(
            action: CanonicalApplyAction(
                kind: .recordingMetadataSend,
                source: .local,
                target: CanonicalApplyTarget(objectID: id),
                bridgeHint: .legacyMetadataManifestSend,
                reason: CanonicalApplyActionKind.recordingMetadataSend.rawValue
            ),
            localObject: local,
            peerObject: peer,
            rollbackCheckpointID: "recording-metadata-checkpoint-\(id)",
            unresolvedConflict: false
        )
    }

    private static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private final class V8DiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SecureConnectionDiagnosticEvent] = []

    func record(_ event: SecureConnectionDiagnosticEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [SecureConnectionDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
