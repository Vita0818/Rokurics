//
//  CanonicalTombstoneConflictGuardedCommitSeamTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalTombstoneConflictGuardedCommitSeamTests {
    @Test func macGuardedSeamAllowsEvidenceButSkipsCanaryZero() {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let result = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
            context: Self.context(candidates: [candidate])
        )

        #expect(result.gate.allowed)
        #expect(result.gate.result == .allowedButCanaryBudgetZero)
        #expect(result.evidenceReport.status == .complete)
        #expect(result.n1ReadinessReport.status == .readyForN1AfterAudit)
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827GateAllowedBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictGateAllowedButNoExecution })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827CommitNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827DeleteNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827RestoreNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827ConflictNotAutoResolved })
        Self.verifyNoExecution(result)
    }

    @Test func macGuardedSeamRecordsMissingPeerSnapshotAsNonfatalNoExecution() {
        let result = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
            context: Self.context(peerSnapshotAvailable: false, peerManifest: nil, candidates: [])
        )

        #expect(result.gate.allowed == false)
        #expect(result.gate.failures.contains(.insufficientPeerSnapshot))
        #expect(result.n1ReadinessReport.status == .insufficientPeerSnapshot)
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827SeamBlocked })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827CommitNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827DeleteNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827RestoreNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827DuplicateSuppressionNotApplied })
        Self.verifyNoExecution(result)
    }

    @Test func macInventoryEnabledV827CanaryZeroDoesNotChangeResponseAndRecordsNoExecution() async throws {
        let harness = try Self.makeHarness(configuration: Self.v827Configuration())
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v827-tombstone-conflict-enabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(events.contains { $0.phase == "canonicalTombstoneConflictV827SeamStarted" })
        #expect(events.contains { $0.phase == "canonicalTombstoneConflictV827SeamBlocked" })
        #expect(events.contains { $0.phase == "canonicalTombstoneConflictV827CanaryBudgetZero" })
        #expect(events.contains { $0.phase == "canonicalTombstoneConflictV827CommitNotExecuted" })
        #expect(events.contains { $0.phase == "canonicalTombstoneConflictV827DeleteNotExecuted" })
        #expect(events.contains { $0.phase == "canonicalTombstoneConflictV827RestoreNotExecuted" })
        #expect(events.contains { $0.phase == "canonicalTombstoneConflictV827ConflictNotAutoResolved" })
        #expect(events.contains { $0.phase == "canonicalTombstoneConflictV827DuplicateSuppressionNotApplied" })
        #expect(events.first { $0.phase == "canonicalTombstoneConflictV827SeamBlocked" }?.errorMessage?.contains("insufficientPeerSnapshot") == true)
        #expect(events.contains { $0.phase == "canonicalTombstoneDuplicateLegacySuppressed" } == false)
    }

    @Test func macInventoryDefaultV827RecordsNoDiagnostics() async throws {
        let harness = try Self.makeHarness(configuration: .disabled)
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v827-tombstone-conflict-disabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(events.contains { $0.phase == "canonicalTombstoneConflictV827SeamStarted" } == false)
    }

    private struct Harness {
        let rootURL: URL
        let server: SecureLocalHTTPSServer
        let recorder: V827MacDiagnosticRecorder
    }

    private static func makeHarness(
        configuration: CanonicalTombstoneConflictCutoverAppSeamConfiguration
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("MacV827TombstoneConflictGuardedSeam")
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let recorder = V827MacDiagnosticRecorder()
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Recordings", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: MacIdentityManager(securityDirectoryURL: securityURL, tlsKeyTagNamespace: "v827-tombstone-\(UUID().uuidString)"),
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
            canonicalTombstoneConflictCutoverAppSeamConfiguration: configuration,
            canonicalKernelMode: .canonicalApplyNoAudio
        )
        return Harness(rootURL: rootURL, server: server, recorder: recorder)
    }

    private static func v827Configuration(
        canaryPolicy: CanonicalTombstoneConflictCanaryPolicy = CanonicalTombstoneConflictCanaryPolicy()
    ) -> CanonicalTombstoneConflictCutoverAppSeamConfiguration {
        .enabled(
            mode: .canaryCommit,
            policy: CanonicalTombstoneConflictCutoverAppSeamPolicy(canaryPolicy: canaryPolicy),
            evidence: TombstoneConflictCutoverTestSupport.evidence(),
            cutoverToken: TombstoneConflictCutoverTestSupport.token()
        )
    }

    private static func context(
        peerSnapshotAvailable: Bool = true,
        peerManifest: CanonicalManifest? = nil,
        candidates: [CanonicalTombstoneConflictCandidate]
    ) -> CanonicalTombstoneConflictGuardedContext {
        let localManifest = TombstoneConflictCutoverTestSupport.emptyManifest()
        let resolvedPeerManifest = peerManifest ?? TombstoneConflictCutoverTestSupport.emptyManifest(nodeID: "iphone-01", platform: "iPhone")
        return CanonicalTombstoneConflictGuardedContext(
            syncRunID: "mac-v827-tombstone-conflict-direct",
            trigger: .periodic,
            nodeRole: .mac,
            localManifest: localManifest,
            peerManifest: resolvedPeerManifest,
            candidates: candidates,
            legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                .tombstones: candidates.map { $0.action.actionID },
                .conflicts: candidates.map { $0.action.actionID }
            ]),
            matrix: .v827TombstoneConflictActivePilot(
                libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
                generatedArtifactsTemplateCompleteOrObservationReady: true
            ),
            evidence: TombstoneConflictCutoverTestSupport.evidence(),
            canaryPolicy: CanonicalTombstoneConflictCanaryPolicy(),
            cutoverToken: TombstoneConflictCutoverTestSupport.token(),
            localSnapshotAvailable: true,
            peerSnapshotAvailable: peerSnapshotAvailable
        )
    }

    private static func pairedDevice() -> PairedDevice {
        PairedDevice(
            id: "iphone-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: Data("v827-tombstone-conflict-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
    }

    private static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func verifyNoExecution(_ result: CanonicalTombstoneConflictGuardedSeamResult) {
        let assertion = CanonicalTombstoneConflictNoExecutionAssertion.evaluate(result)
        #expect(assertion.passed)
        #expect(result.noExecutionAssertion.passed)
        #expect(result.willExecuteNow == false)
        #expect(result.commitAttemptedCount == 0)
        #expect(result.tombstoneMarkerWrittenCount == 0)
        #expect(result.restoreAttemptedCount == 0)
        #expect(result.physicalDeleteAttemptedCount == 0)
        #expect(result.permanentDeleteAttemptedCount == 0)
        #expect(result.tombstoneGCAttemptedCount == 0)
        #expect(result.conflictResolutionAttemptedCount == 0)
        #expect(result.commitExecutorCalled == false)
        #expect(result.realApplyPortCalled == false)
        #expect(result.receiveJSONMutated == false)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.legacyFallbackPreserved)
        #expect(result.runtimeSwitchEnabled == false)
        #expect(result.legacyPlanUnchanged)
        #expect(result.productionPlanUnchanged)
        #expect(result.uiMutated == false)
        #expect(result.macInventoryResponseMutated == false)
        #expect(result.audioInboxWritten == false)
        #expect(result.transcriptionOrNoteGenerationTriggered == false)
        #expect(result.uploadJobCreated == false)
        #expect(result.networkRequestCalled == false)
        #expect(result.routeBehaviorChanged == false)
        #expect(result.requestVerifierBypassed == false)
    }
}

@MainActor
private final class V827MacDiagnosticRecorder {
    private var events: [SecureConnectionDiagnosticEvent] = []

    func record(_ event: SecureConnectionDiagnosticEvent) {
        events.append(event)
    }

    func snapshot() -> [SecureConnectionDiagnosticEvent] {
        events
    }
}
