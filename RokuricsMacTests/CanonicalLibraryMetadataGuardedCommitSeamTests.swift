//
//  CanonicalLibraryMetadataGuardedCommitSeamTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalLibraryMetadataGuardedCommitSeamTests {
    @Test func macGuardedCommitSeamAllowsEvidenceButSkipsCanaryZero() {
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v814Configuration(),
            context: Self.context(candidates: [candidate])
        )

        #expect(result.gate.allowed)
        #expect(result.evidenceReport.status == .complete)
        #expect(result.canExecuteNow)
        #expect(result.canaryBudgetZero)
        #expect(result.n1ReadinessReport.status == .readyAfterExplicitN1Enablement)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814GateAllowedBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataGateAllowedButNoExecution })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814CommitNotExecuted })
        Self.verifyNoExecution(result)
    }

    @Test func macGuardedCommitSeamBlocksMissingPeerSnapshotButStillReportsNoExecution() {
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v814Configuration(),
            context: Self.context(peerSnapshotAvailable: false, peerManifest: nil, candidates: [])
        )

        #expect(result.gate.allowed == false)
        #expect(result.gate.failures.contains(.insufficientPeerSnapshot))
        #expect(result.n1ReadinessReport.status == .insufficientPeerSnapshot)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814SeamBlocked })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814CommitNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814DuplicateSuppressionNotApplied })
        Self.verifyNoExecution(result)
    }

    @Test func macInventoryEnabledV814CanaryZeroDoesNotChangeResponseAndRecordsNoExecution() async throws {
        let harness = try Self.makeHarness(configuration: Self.v814Configuration())
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v814-library-enabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataV814SeamStarted" })
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataV814SeamBlocked" })
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataV814CanaryBudgetZero" })
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataV814CommitNotExecuted" })
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataV814DuplicateSuppressionNotApplied" })
        #expect(events.first { $0.phase == "canonicalLibraryMetadataV814SeamBlocked" }?.errorMessage?.contains("insufficientPeerSnapshot") == true)
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataDuplicateLegacySuppressed" } == false)
    }

    @Test func macInventoryDefaultV814RecordsNoDiagnostics() async throws {
        let harness = try Self.makeHarness(configuration: .disabled)
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            Self.pairedDevice(),
            syncRunID: "mac-v814-library-disabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(events.contains { $0.phase == "canonicalLibraryMetadataV814SeamStarted" } == false)
    }

    private struct Harness {
        let rootURL: URL
        let server: SecureLocalHTTPSServer
        let recorder: V814MacDiagnosticRecorder
    }

    private static func makeHarness(
        configuration: CanonicalLibraryMetadataCutoverAppSeamConfiguration
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("MacV814LibraryMetadataGuardedCommitSeam")
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let recorder = V814MacDiagnosticRecorder()
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Recordings", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: MacIdentityManager(securityDirectoryURL: securityURL, tlsKeyTagNamespace: "v814-library-\(UUID().uuidString)"),
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
            canonicalLibraryMetadataCutoverAppSeamConfiguration: configuration,
            canonicalKernelMode: .canonicalApplyNoAudio
        )
        return Harness(rootURL: rootURL, server: server, recorder: recorder)
    }

    private static func v814Configuration(
        canaryPolicy: CanonicalLibraryMetadataCanaryPolicy = CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0)
    ) -> CanonicalLibraryMetadataCutoverAppSeamConfiguration {
        .enabled(
            mode: .canaryCommit,
            policy: CanonicalLibraryMetadataCutoverAppSeamPolicy(canaryPolicy: canaryPolicy),
            evidence: MacLibraryMetadataCutoverTestSupport.evidence(),
            cutoverToken: MacLibraryMetadataCutoverTestSupport.token()
        )
    }

    private static func context(
        peerSnapshotAvailable: Bool = true,
        peerManifest: CanonicalManifest? = nil,
        candidates: [CanonicalLibraryMetadataCutoverCandidate]
    ) -> CanonicalLibraryMetadataGuardedCommitContext {
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
        return CanonicalLibraryMetadataGuardedCommitContext(
            syncRunID: "mac-v814-library-direct",
            trigger: .periodic,
            nodeRole: .mac,
            localManifest: localManifest,
            peerManifest: resolvedPeerManifest,
            libraryPlan: CanonicalLibrarySyncPlan(
                actions: [],
                applyActions: candidates.map(\.action),
                conflicts: [],
                tombstones: [],
                diagnostics: [],
                fallbackRequiredObjectIDs: []
            ),
            legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                .folders: candidates.map { $0.action.actionID }
            ]),
            evidence: MacLibraryMetadataCutoverTestSupport.evidence(),
            canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0),
            cutoverToken: MacLibraryMetadataCutoverTestSupport.token(),
            candidates: candidates,
            localSnapshotAvailable: true,
            peerSnapshotAvailable: peerSnapshotAvailable,
            unresolvedConflictCount: candidates.filter(\.unresolvedConflict).count
        )
    }

    private static func manifest(
        nodeID: String,
        platform: String,
        objects: [CanonicalLibraryObject]
    ) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(nodeID: nodeID, platform: platform, capabilities: [.canonicalLibraryObjectsV1]),
            generatedAt: Date(timeIntervalSince1970: 1_000),
            objects: [],
            libraryObjects: objects,
            manifestCapabilities: [.canonicalLibraryObjectsV1]
        )
    }

    private static func pairedDevice() -> PairedDevice {
        PairedDevice(
            id: "iphone-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: Data("v814-library-guarded-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
    }

    private static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private static func verifyNoExecution(_ result: CanonicalLibraryMetadataGuardedCommitSeamResult) {
        let assertion = CanonicalLibraryMetadataNoExecutionAssertion.evaluate(result)
        #expect(assertion.passed)
        #expect(result.noExecutionAssertion.passed)
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

private final class V814MacDiagnosticRecorder: @unchecked Sendable {
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
