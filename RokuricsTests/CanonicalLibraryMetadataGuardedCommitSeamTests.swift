//
//  CanonicalLibraryMetadataGuardedCommitSeamTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalLibraryMetadataGuardedCommitSeamTests {
    @Test func guardedCommitSeamAllowsEvidenceButSkipsCanaryZero() {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v814Configuration(),
            context: Self.context(candidates: [candidate])
        )

        #expect(result.gate.allowed)
        #expect(result.evidenceReport.status == .complete)
        #expect(result.canExecuteNow)
        #expect(result.canaryBudgetZero)
        #expect(result.willExecuteNow == false)
        #expect(result.n1ReadinessReport.status == .readyAfterExplicitN1Enablement)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814SeamStarted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814GateAllowedBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataGateAllowedButNoExecution })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataCommitSkippedBecauseCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814CommitNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814LegacyFallbackPreserved })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814DuplicateSuppressionNotApplied })
        Self.verifyNoExecution(result)
    }

    @Test func guardedCommitSeamBlocksAnyN1OrExecutableStageConfig() {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let n1 = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v814Configuration(
                canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 1, allowsInternalN1Execution: true)
            ),
            context: Self.context(candidates: [candidate])
        )
        let staged = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v814Configuration(
                canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(
                    stagePolicy: CanonicalLibraryMetadataCanaryStagePolicy(requestedStage: .n1, allowCandidateExecution: true),
                    canaryMaxObjectsPerSyncRun: 1,
                    allowsInternalN1Execution: true
                )
            ),
            context: Self.context(candidates: [candidate])
        )

        #expect(n1.gate.allowed == false)
        #expect(n1.gate.failures.contains(.canaryBudgetNonZeroDenied))
        #expect(n1.gate.failures.contains(.internalN1ExecutionDenied))
        #expect(staged.gate.allowed == false)
        #expect(staged.gate.failures.contains(.stagePolicyExecutionDenied))
        #expect(staged.gate.failures.contains(.canaryBudgetNonZeroDenied))
        Self.verifyNoExecution(n1)
        Self.verifyNoExecution(staged)
    }

    @Test func guardedCommitSeamBlocksUnsafeLibraryMetadataCandidates() {
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v814Configuration(),
            context: Self.context(candidates: [LibraryMetadataCutoverTestSupport.resourceMoveCandidate()])
        )

        #expect(result.gate.allowed == false)
        #expect(result.gate.failures.contains(.resourceMoveAttempted))
        #expect(result.n1ReadinessReport.blockers.contains(.resourceMoveAttempted))
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814SeamBlocked })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814DuplicateSuppressionNotApplied })
        Self.verifyNoExecution(result)
    }

    @Test func performTickEnabledV814CanaryZeroRecordsReportWithoutChangingPlanOrCallingClientApply() async throws {
        let harness = try Self.makeHarness(
            peerInventory: Self.emptyCanonicalInventory(deviceID: "mac-01", platform: .Mac),
            configuration: Self.v814Configuration()
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_400),
            bypassBackoff: true,
            syncRunID: "v814-library-metadata-enabled"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(plan?.uploadMetadataActions.isEmpty == true)
        #expect(plan?.downloadMetadataActions.isEmpty == true)
        #expect(entries.contains { $0.phase == "canonicalLibraryMetadataV814SeamStarted" })
        #expect(entries.contains { $0.phase == "canonicalLibraryMetadataV814GateAllowedBudgetZero" })
        #expect(entries.contains { $0.phase == "canonicalLibraryMetadataV814CanaryBudgetZero" })
        #expect(entries.contains { $0.phase == "canonicalLibraryMetadataV814CommitNotExecuted" })
        #expect(entries.contains { $0.phase == "canonicalLibraryMetadataV814DuplicateSuppressionNotApplied" })
        #expect(entries.contains { $0.phase == "canonicalLibraryMetadataDuplicateLegacySuppressed" } == false)
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    @Test func diagnosticsAreRedactedAndUseNoFullHashesOrPaths() {
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v814Configuration(),
            context: Self.context(candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate])
        )
        let summary = result.diagnostics.map(\.diagnosticsSummary).joined(separator: "\n")

        #expect(summary.contains("/Users/") == false)
        #expect(summary.contains("/private/") == false)
        #expect(summary.contains(String(repeating: "a", count: 64)) == false)
    }

    private struct Harness {
        let rootURL: URL
        let diagnosticsStore: ConnectionDiagnosticsStore
        let client: V814FakeLocalNetworkSyncClient
        let engine: LocalNetworkSyncEngine
    }

    private static func makeHarness(
        peerInventory: LocalNetworkSyncInventory,
        configuration: CanonicalLibraryMetadataCutoverAppSeamConfiguration
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("IPhoneV814LibraryMetadataGuardedCommitSeam")
        let audioStore = AudioFileStore(rootDirectoryURL: rootURL)
        try audioStore.ensureStorageDirectories()
        let studyStore = StudyLibraryStore(rootURL: rootURL.appendingPathComponent("Study", isDirectory: true), audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL.appendingPathComponent("Diagnostics", isDirectory: true))
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true))
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let client = V814FakeLocalNetworkSyncClient(peerInventory: peerInventory)
        let engine = LocalNetworkSyncEngine(
            connectionStore: V814FakeSecureMacConnectionSnapshotProvider(snapshot: Self.pairedSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: client,
            stateStore: stateStore,
            diagnosticsStore: diagnosticsStore,
            canonicalLibraryMetadataCutoverAppSeamConfiguration: configuration
        )
        return Harness(rootURL: rootURL, diagnosticsStore: diagnosticsStore, client: client, engine: engine)
    }

    private static func v814Configuration(
        canaryPolicy: CanonicalLibraryMetadataCanaryPolicy = CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0)
    ) -> CanonicalLibraryMetadataCutoverAppSeamConfiguration {
        .enabled(
            mode: .canaryCommit,
            policy: CanonicalLibraryMetadataCutoverAppSeamPolicy(canaryPolicy: canaryPolicy),
            evidence: LibraryMetadataCutoverTestSupport.evidence(),
            cutoverToken: LibraryMetadataCutoverTestSupport.token()
        )
    }

    private static func context(
        trigger: CanonicalSyncPlanTrigger = .periodic,
        evidence: CanonicalLibraryMetadataCutoverEvidence = LibraryMetadataCutoverTestSupport.evidence(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate]
    ) -> CanonicalLibraryMetadataGuardedCommitContext {
        let localManifest = LibraryMetadataCutoverTestSupport.manifest(candidates.compactMap(\.localObject))
        let peerManifest = LibraryMetadataCutoverTestSupport.manifest(candidates.compactMap(\.peerObject))
        return CanonicalLibraryMetadataGuardedCommitContext(
            syncRunID: "v814-library-direct",
            trigger: trigger,
            nodeRole: .iPhone,
            localManifest: localManifest,
            peerManifest: peerManifest,
            libraryPlan: CanonicalLibrarySyncPlan(trigger: trigger, candidates: candidates),
            legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                .folders: candidates.map { $0.action.actionID }
            ]),
            evidence: evidence,
            canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0),
            cutoverToken: LibraryMetadataCutoverTestSupport.token(),
            candidates: candidates,
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            unresolvedConflictCount: candidates.filter(\.unresolvedConflict).count
        )
    }

    private static func emptyCanonicalInventory(deviceID: String, platform: LocalNetworkSyncPlatform) -> LocalNetworkSyncInventory {
        LocalNetworkSyncInventory.make(
            device: Self.device(deviceID: deviceID, platform: platform),
            canonicalManifest: CanonicalManifest.make(
                node: CanonicalNode(nodeID: deviceID, platform: platform.rawValue, capabilities: [.canonicalLibraryObjectsV1]),
                generatedAt: Date(timeIntervalSince1970: 1_000),
                objects: [],
                libraryObjects: [],
                manifestCapabilities: [.canonicalLibraryObjectsV1]
            )
        )
    }

    private static func device(deviceID: String, platform: LocalNetworkSyncPlatform) -> LocalNetworkSyncDeviceSection {
        LocalNetworkSyncDeviceSection(
            deviceID: deviceID,
            deviceName: platform.rawValue,
            platform: platform,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            lastKnownPeerRevision: nil,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
    }

    private static func pairedSnapshot() -> SecureMacConnectionSnapshot {
        SecureMacConnectionSnapshot(
            macHost: "127.0.0.1",
            macPort: 8787,
            macFingerprint: String(repeating: "a", count: 64),
            macName: "Rokurics Mac",
            macModel: "Mac",
            deviceID: "mac-01",
            sharedSecretBase64URL: Data("v814-library-guarded-secret".utf8).base64URLEncodedString(),
            pairedAt: "2026-06-05T00:00:00Z"
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

private extension CanonicalLibrarySyncPlan {
    init(trigger: CanonicalSyncPlanTrigger, candidates: [CanonicalLibraryMetadataCutoverCandidate]) {
        self.init(
            actions: [],
            applyActions: candidates.map(\.action),
            conflicts: [],
            tombstones: [],
            diagnostics: [
                CanonicalLibrarySyncDiagnostic(
                    phase: "canonicalLibraryMetadataGuardedCommitTestPlan",
                    objectID: nil,
                    objectKind: nil,
                    detail: trigger.rawValue
                )
            ],
            fallbackRequiredObjectIDs: []
        )
    }
}

@MainActor
private final class V814FakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding, SecureMacConnectionIntentProviding {
    var snapshot: SecureMacConnectionSnapshot
    var userConnectionIntent: UserConnectionIntent = .wantsConnected

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
}

private final class V814FakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
    let peerInventory: LocalNetworkSyncInventory
    private(set) var inventoryRequestCount = 0
    private(set) var applyMetadataCount = 0
    private(set) var artifactRequestCount = 0
    private(set) var artifactPutCount = 0

    init(peerInventory: LocalNetworkSyncInventory) {
        self.peerInventory = peerInventory
    }

    func sendDeviceStatus(
        settings: SecureMacConnectionSnapshot,
        statusRequest: DeviceStatusRequest
    ) async throws -> DeviceStatusResponse {
        DeviceStatusResponse(ok: true, status: nil, syncState: nil, error: nil)
    }

    func fetchLocalNetworkSyncInventory(
        settings: SecureMacConnectionSnapshot,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String?
    ) async throws -> LocalNetworkSyncInventoryResponse {
        inventoryRequestCount += 1
        return LocalNetworkSyncInventoryResponse(ok: true, inventory: peerInventory, error: nil)
    }

    func sendLocalNetworkSyncStartSignal(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartRequest
    ) async throws -> LocalNetworkSyncStartResponse {
        LocalNetworkSyncStartResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: "mac-01",
            ackAt: Date(),
            disposition: "ack",
            error: nil
        )
    }

    func sendLocalNetworkSyncStartAck(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartAckRequest
    ) async throws -> LocalNetworkSyncStartAckResponse {
        LocalNetworkSyncStartAckResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: "mac-01",
            ackReceivedAt: Date(),
            error: nil
        )
    }

    func applyLocalNetworkSyncMetadata(
        settings: SecureMacConnectionSnapshot,
        manifest: StudyLibrarySyncManifest
    ) async throws -> StudyLibrarySyncManifestResponse {
        applyMetadataCount += 1
        return StudyLibrarySyncManifestResponse(
            ok: true,
            manifest: nil,
            syncState: nil,
            deviceStatus: nil,
            applyResult: StudyLibrarySyncApplyResult(),
            baseCommitID: nil,
            newCommitID: nil,
            remoteChanges: nil,
            rejectedChanges: nil,
            error: nil
        )
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactRequest
    ) async throws -> LocalNetworkSyncArtifactResponse {
        artifactRequestCount += 1
        return LocalNetworkSyncArtifactResponse(
            ok: false,
            artifactID: nil,
            kind: nil,
            checksum: nil,
            size: nil,
            logicalPathToken: nil,
            dataBase64: nil,
            error: "not_expected"
        )
    }

    func fetchLocalNetworkSyncArtifactStatus(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactStatusRequest
    ) async throws -> LocalNetworkSyncArtifactStatusResponse {
        LocalNetworkSyncArtifactStatusResponse(
            ok: true,
            artifactID: request.artifactID,
            checksum: request.checksum,
            size: request.size,
            confirmedBytes: 0,
            nextOffset: 0,
            state: .pending,
            error: nil
        )
    }

    func putLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactPutRequest
    ) async throws -> LocalNetworkSyncArtifactPutResponse {
        artifactPutCount += 1
        return LocalNetworkSyncArtifactPutResponse(
            ok: true,
            artifactID: request.artifactID,
            disposition: "acceptedNew",
            checksum: request.checksum,
            size: request.size,
            confirmedBytes: request.size,
            error: nil
        )
    }
}
