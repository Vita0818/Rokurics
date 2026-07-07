//
//  CanonicalRecordingMetadataGuardedCommitSeamTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalRecordingMetadataGuardedCommitSeamTests {
    @Test func macGuardedCommitSeamAllowsEvidenceButSkipsCanaryZero() {
        let candidate = RecordingMetadataCutoverTestSupport.candidate()
        let result = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v86Configuration(),
            context: Self.context(candidates: [candidate])
        )

        #expect(result.gate.allowed)
        #expect(result.evidenceReport.status == .complete)
        #expect(result.canExecuteNow)
        #expect(result.canaryBudgetZero)
        #expect(result.diagnostics.contains { $0.kind == .canonicalV86CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataGateAllowedButNoExecution })
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataCommitSkippedBecauseCanaryBudgetZero })
        CanonicalNoCommitOrNZeroExecutionAssertion.verify(result)
    }

    @Test func macGuardedCommitSeamAllowsOnlyExplicitInternalN1ButStillDoesNotExecute() {
        let candidate = RecordingMetadataCutoverTestSupport.candidate()
        let missingInternal = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v87Configuration(canaryMaxObjects: 1, allowsInternalN1: false),
            context: Self.context(candidates: [candidate])
        )
        let n1Internal = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v87Configuration(canaryMaxObjects: 1, allowsInternalN1: true),
            context: Self.context(candidates: [candidate])
        )
        let aboveOne = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v87Configuration(canaryMaxObjects: 2, allowsInternalN1: true),
            context: Self.context(candidates: [candidate])
        )

        #expect(missingInternal.gate.failures.contains(.missingInternalCanaryConfiguration))
        #expect(aboveOne.gate.failures.contains(.canaryBudgetAboveOneDenied))
        #expect(n1Internal.gate.allowed)
        #expect(n1Internal.canaryBudgetZero == false)
        #expect(n1Internal.willExecuteNow == false)
        #expect(n1Internal.productionCommitCalled == false)
        #expect(n1Internal.duplicateLegacySuppressedActionIDs.isEmpty)
    }

    @Test func macGuardedCommitSeamBlocksMissingPeerSnapshotButStillReportsCanaryZeroNoExecution() {
        let result = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v86Configuration(),
            context: Self.context(peerSnapshotAvailable: false, peerManifest: nil, candidates: [])
        )

        #expect(result.gate.allowed == false)
        #expect(result.gate.failures.contains(.insufficientPeerSnapshot))
        #expect(result.diagnostics.contains { $0.kind == .canonicalV86GuardedCommitSeamBlocked })
        #expect(result.diagnostics.contains { $0.kind == .canonicalV86CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalV86CommitNotExecuted })
        CanonicalNoCommitOrNZeroExecutionAssertion.verify(result)
    }

    @Test func macInventoryDefaultV86GuardedCommitRecordsNoDiagnostics() async throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v86-disabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory != nil)
        #expect(events.contains { $0.phase == "canonicalV86GuardedCommitSeamStarted" } == false)
    }

    @Test func macInventoryEnabledV86CanaryZeroDoesNotChangeResponseAndRecordsNoExecution() async throws {
        let harness = try Self.makeHarness(v8Configuration: Self.v86Configuration())
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v86-enabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(events.contains { $0.phase == "canonicalV86GuardedCommitSeamStarted" })
        #expect(events.contains { $0.phase == "canonicalV86GuardedCommitSeamBlocked" })
        #expect(events.contains { $0.phase == "canonicalV86CanaryBudgetZero" })
        #expect(events.contains { $0.phase == "canonicalV86CommitNotExecuted" })
        #expect(events.first { $0.phase == "canonicalV86GuardedCommitSeamBlocked" }?.errorMessage?.contains("insufficientPeerSnapshot") == true)
        #expect(events.contains { $0.phase == "canonicalV8CutoverSeamStarted" } == false)
    }

    private struct Harness {
        let rootURL: URL
        let server: SecureLocalHTTPSServer
        let recorder: V86DiagnosticRecorder
    }

    private static func makeHarness(
        v8Configuration: CanonicalCutoverAppSeamConfiguration = .disabled
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("MacV86GuardedCommitSeam")
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let recorder = V86DiagnosticRecorder()
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Recordings", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: MacIdentityManager(securityDirectoryURL: securityURL, tlsKeyTagNamespace: "v86-guarded-\(UUID().uuidString)"),
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
            canonicalKernelMode: .canonicalApplyNoAudio
        )
        return Harness(rootURL: rootURL, server: server, recorder: recorder)
    }

    private static func v86Configuration() -> CanonicalCutoverAppSeamConfiguration {
        .enabled(
            mode: .canaryCommit,
            policy: CanonicalCutoverAppSeamPolicy(canaryMaxObjectsPerSyncRun: 0),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            cutoverToken: RecordingMetadataCutoverTestSupport.token()
        )
    }

    private static func v87Configuration(
        canaryMaxObjects: Int,
        allowsInternalN1: Bool
    ) -> CanonicalCutoverAppSeamConfiguration {
        .enabled(
            mode: .canaryCommit,
            policy: CanonicalCutoverAppSeamPolicy(
                canaryMaxObjectsPerSyncRun: canaryMaxObjects,
                allowsV87CanaryN1InternalExecution: allowsInternalN1
            ),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            cutoverToken: RecordingMetadataCutoverTestSupport.token()
        )
    }

    private static func context(
        peerSnapshotAvailable: Bool = true,
        peerManifest: CanonicalManifest? = nil,
        candidates: [CanonicalRecordingMetadataCutoverCandidate]
    ) -> CanonicalRecordingMetadataGuardedCommitContext {
        let localManifest = Self.manifest(
            nodeID: "mac-01",
            platform: "Mac",
            objects: candidates.compactMap(\.localObject)
        )
        let resolvedPeerManifest = peerManifest ?? Self.manifest(
            nodeID: "iphone-01",
            platform: "iPhone",
            objects: candidates.compactMap(\.peerObject)
        )
        return CanonicalRecordingMetadataGuardedCommitContext(
            syncRunID: "mac-v86-direct",
            trigger: .periodic,
            nodeRole: .mac,
            localManifest: localManifest,
            peerManifest: resolvedPeerManifest,
            applyPlan: CanonicalApplyPlan(trigger: .periodic, actions: candidates.map(\.action)),
            legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                .recordingMetadata: candidates.map { $0.action.actionID }
            ]),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            unresolvedConflictCount: candidates.filter(\.unresolvedConflict).count,
            canaryPolicy: CanonicalRecordingMetadataCanaryPolicy(maxObjectsPerSyncRun: 0),
            legacyFallbackAvailable: true,
            cutoverToken: RecordingMetadataCutoverTestSupport.token(),
            candidates: candidates,
            localSnapshotAvailable: true,
            peerSnapshotAvailable: peerSnapshotAvailable
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
                capabilities: [.recordingMetadata, .canonicalInventoryBuilderV1]
            ),
            generatedAt: Date(timeIntervalSince1970: 1_000),
            objects: objects,
            manifestCapabilities: [.recordingMetadata, .canonicalInventoryBuilderV1]
        )
    }

    private static func pairedDevice() -> PairedDevice {
        PairedDevice(
            id: "iphone-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: Data("v86-guarded-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
    }

    private static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private enum CanonicalNoCommitOrNZeroExecutionAssertion {
    static func verify(_ result: CanonicalRecordingMetadataGuardedCommitSeamResult) {
        #expect(result.willExecuteNow == false)
        #expect(result.commitAttemptedCount == 0)
        #expect(result.committedObjectCount == 0)
        #expect(result.productionCommitCalled == false)
        #expect(result.realApplyPortCommitCalled == false)
        #expect(result.networkSendCalled == false)
        #expect(result.applySyncManifestCalled == false)
        #expect(result.metadataJSONWritten == false)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.legacyFallbackPreserved)
        #expect(result.runtimeSwitchEnabled == false)
        #expect(result.legacyPlanUnchanged)
        #expect(result.productionPlanUnchanged)
    }
}

private final class V86DiagnosticRecorder: @unchecked Sendable {
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
