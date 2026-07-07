//
//  CanonicalGeneratedArtifactGuardedCommitSeamTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalGeneratedArtifactGuardedCommitSeamTests {
    @Test func macGuardedCommitSeamAllowsEvidenceButSkipsCanaryZero() {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate().candidate
        let result = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: Self.v822Configuration(),
            context: Self.context(candidates: [candidate])
        )

        #expect(result.gate.allowed)
        #expect(result.gate.result == .allowedButCanaryBudgetZero)
        #expect(result.evidenceReport.status == .complete)
        #expect(result.canExecuteNow)
        #expect(result.canaryBudgetZero)
        #expect(result.n1ReadinessReport.status == .readyForN1AfterAudit)
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822GateAllowedBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactGateAllowedButNoExecution })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822CommitNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822DownloadNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822ApplyNotExecuted })
        Self.verifyNoExecution(result)
    }

    @Test func macGuardedCommitSeamBlocksMissingPeerSnapshotButStillReportsNoExecution() {
        let result = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: Self.v822Configuration(),
            context: Self.context(peerSnapshotAvailable: false, peerManifest: nil, candidates: [])
        )

        #expect(result.gate.allowed == false)
        #expect(result.gate.failures.contains(.insufficientPeerSnapshot))
        #expect(result.n1ReadinessReport.status == .insufficientPeerSnapshot)
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822SeamBlocked })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822CommitNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822DownloadNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822ApplyNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822DuplicateSuppressionNotApplied })
        Self.verifyNoExecution(result)
    }

    @Test func macInventoryEnabledV822CanaryZeroDoesNotChangeResponseAndRecordsNoExecution() async throws {
        let harness = try Self.makeHarness(configuration: Self.v822Configuration())
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v822-generated-artifact-enabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(events.contains { $0.phase == "canonicalGeneratedArtifactV822SeamStarted" })
        #expect(events.contains { $0.phase == "canonicalGeneratedArtifactV822SeamBlocked" })
        #expect(events.contains { $0.phase == "canonicalGeneratedArtifactV822CanaryBudgetZero" })
        #expect(events.contains { $0.phase == "canonicalGeneratedArtifactV822CommitNotExecuted" })
        #expect(events.contains { $0.phase == "canonicalGeneratedArtifactV822DownloadNotExecuted" })
        #expect(events.contains { $0.phase == "canonicalGeneratedArtifactV822ApplyNotExecuted" })
        #expect(events.contains { $0.phase == "canonicalGeneratedArtifactV822DuplicateSuppressionNotApplied" })
        #expect(events.first { $0.phase == "canonicalGeneratedArtifactV822SeamBlocked" }?.errorMessage?.contains("insufficientPeerSnapshot") == true)
        #expect(events.contains { $0.phase == "canonicalGeneratedArtifactDuplicateLegacySuppressed" } == false)
    }

    @Test func macInventoryDefaultV822RecordsNoDiagnostics() async throws {
        let harness = try Self.makeHarness(configuration: .disabled)
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v822-generated-artifact-disabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(events.contains { $0.phase == "canonicalGeneratedArtifactV822SeamStarted" } == false)
    }

    private struct Harness {
        let rootURL: URL
        let server: SecureLocalHTTPSServer
        let recorder: V822MacDiagnosticRecorder
    }

    private static func makeHarness(
        configuration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("MacV822GeneratedArtifactGuardedCommitSeam")
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let recorder = V822MacDiagnosticRecorder()
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Recordings", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: MacIdentityManager(securityDirectoryURL: securityURL, tlsKeyTagNamespace: "v822-generated-\(UUID().uuidString)"),
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
            canonicalGeneratedArtifactCutoverAppSeamConfiguration: configuration,
            canonicalKernelMode: .canonicalApplyNoAudio
        )
        return Harness(rootURL: rootURL, server: server, recorder: recorder)
    }

    private static func v822Configuration(
        canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy = CanonicalGeneratedArtifactCanaryPolicy(canaryMaxObjectsPerSyncRun: 0)
    ) -> CanonicalGeneratedArtifactCutoverAppSeamConfiguration {
        .enabled(
            mode: .canaryCommit,
            policy: CanonicalGeneratedArtifactCutoverAppSeamPolicy(canaryPolicy: canaryPolicy),
            evidence: GeneratedArtifactCutoverTestSupport.evidence(),
            cutoverToken: GeneratedArtifactCutoverTestSupport.token()
        )
    }

    private static func context(
        peerSnapshotAvailable: Bool = true,
        peerManifest: CanonicalManifest? = nil,
        candidates: [CanonicalGeneratedArtifactCutoverCandidate]
    ) -> CanonicalGeneratedArtifactGuardedCommitContext {
        let localManifest = Self.manifest(
            nodeID: "iphone-01",
            platform: "iPhone",
            objects: candidates.compactMap(\.localObject)
        )
        let resolvedPeerManifest = peerManifest ?? Self.manifest(
            nodeID: "mac-01",
            platform: "Mac",
            objects: candidates.compactMap(\.peerObject)
        )
        return CanonicalGeneratedArtifactGuardedCommitContext(
            syncRunID: "mac-v822-generated-artifact-direct",
            trigger: .periodic,
            nodeRole: .mac,
            localManifest: localManifest,
            peerManifest: resolvedPeerManifest,
            legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                .generatedArtifacts: candidates.map { $0.action.actionID }
            ]),
            matrix: .v822GeneratedArtifactsActivePilot(libraryMetadataObservationCompleteOrRetirementCandidateReady: true),
            evidence: GeneratedArtifactCutoverTestSupport.evidence(),
            canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy(canaryMaxObjectsPerSyncRun: 0),
            cutoverToken: GeneratedArtifactCutoverTestSupport.token(),
            candidates: candidates,
            localSnapshotAvailable: true,
            peerSnapshotAvailable: peerSnapshotAvailable,
            unresolvedConflictCount: candidates.filter(\.unresolvedConflict).count
        )
    }

    private static func manifest(
        nodeID: String,
        platform: String,
        objects: [CanonicalRecordingObject]
    ) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(
                nodeID: nodeID,
                platform: platform,
                capabilities: [.recordingMetadata, .transcriptArtifact, .noteArtifact, .summaryArtifact]
            ),
            generatedAt: Date(timeIntervalSince1970: 1_000),
            objects: objects,
            manifestCapabilities: [.recordingMetadata, .transcriptArtifact, .noteArtifact, .summaryArtifact]
        )
    }

    private static func pairedDevice() -> PairedDevice {
        PairedDevice(
            id: "iphone-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: Data("v822-generated-artifact-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
    }

    private static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func verifyNoExecution(_ result: CanonicalGeneratedArtifactGuardedCommitSeamResult) {
        let assertion = CanonicalGeneratedArtifactNoExecutionAssertion.evaluate(result)
        #expect(assertion.passed)
        #expect(result.noExecutionAssertion.passed)
        #expect(result.willExecuteNow == false)
        #expect(result.commitAttemptedCount == 0)
        #expect(result.downloadAttemptedCount == 0)
        #expect(result.applyAttemptedCount == 0)
        #expect(result.committedArtifactCount == 0)
        #expect(result.productionCommitCalled == false)
        #expect(result.realApplyPortCommitCalled == false)
        #expect(result.networkRequestCalled == false)
        #expect(result.artifactRequestRouteCalled == false)
        #expect(result.generatedArtifactDownloaded == false)
        #expect(result.generatedArtifactApplied == false)
        #expect(result.generatedArtifactFileWritten == false)
        #expect(result.generatedArtifactUploadJobCreated == false)
        #expect(result.audioAutoDownloadTriggered == false)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.legacyFallbackPreserved)
        #expect(result.runtimeSwitchEnabled == false)
        #expect(result.legacyPlanUnchanged)
        #expect(result.productionPlanUnchanged)
    }
}

private final class V822MacDiagnosticRecorder: @unchecked Sendable {
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
