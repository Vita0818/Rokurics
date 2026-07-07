//
//  CanonicalRecordingMetadataGuardedCommitSeamTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalRecordingMetadataGuardedCommitSeamTests {
    @Test func guardedCommitSeamAllowsEvidenceButSkipsCanaryZero() {
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

    @Test func guardedCommitSeamAllowsOnlyExplicitInternalN1ButStillDoesNotExecute() {
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

    @Test func guardedCommitSeamBlocksUnsafeModesTriggersAndMissingEvidence() {
        let candidate = RecordingMetadataCutoverTestSupport.candidate()
        let disabled = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: .disabled,
            context: Self.context(candidates: [candidate])
        )
        let noCommitMode = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: .enabled(
                mode: .guardedExecuteNoCommit,
                evidence: RecordingMetadataCutoverTestSupport.evidence(),
                cutoverToken: RecordingMetadataCutoverTestSupport.token()
            ),
            context: Self.context(candidates: [candidate])
        )
        let viewRefresh = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v86Configuration(),
            context: Self.context(trigger: .viewRefresh, candidates: [candidate])
        )
        let retryDrainer = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v86Configuration(),
            context: Self.context(trigger: .retryDrainer, candidates: [candidate])
        )
        let missingEvidence = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: .enabled(mode: .canaryCommit, cutoverToken: RecordingMetadataCutoverTestSupport.token()),
            context: Self.context(evidence: CanonicalRecordingMetadataCutoverEvidence(), candidates: [candidate])
        )

        #expect(disabled.gate.failures.contains(.disabled))
        #expect(noCommitMode.gate.failures.contains(.unsupportedMode))
        #expect(viewRefresh.gate.failures.contains(.viewRefreshTriggerDenied))
        #expect(retryDrainer.gate.failures.contains(.retryDrainerFreshMetadataDenied))
        #expect(missingEvidence.gate.failures.contains(.missingRealDataShadowCopyEvidence))
        #expect(missingEvidence.gate.failures.contains(.missingExecutionShadowEvidence))
        #expect(missingEvidence.gate.failures.contains(.missingDryRunEquivalence))
        #expect(missingEvidence.evidenceReport.status == .incomplete)
        CanonicalNoCommitOrNZeroExecutionAssertion.verify(disabled)
        CanonicalNoCommitOrNZeroExecutionAssertion.verify(missingEvidence)
    }

    @Test func diagnosticsAreRedactedAndUseNoFullHashesOrPaths() {
        let result = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: Self.v86Configuration(),
            context: Self.context(candidates: [RecordingMetadataCutoverTestSupport.candidate()])
        )
        let summary = result.diagnostics.map(\.diagnosticsSummary).joined(separator: "\n")

        #expect(summary.contains("/Users/") == false)
        #expect(summary.contains("/private/") == false)
        #expect(summary.contains(String(repeating: "a", count: 64)) == false)
    }

    @Test func performTickDefaultV86GuardedCommitRecordsNoDiagnostics() async throws {
        let harness = try Self.makeHarness(peerInventory: Self.emptyCanonicalInventory(deviceID: "mac-01", platform: .Mac))
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_200),
            bypassBackoff: true,
            syncRunID: "v86-disabled"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(entries.contains { $0.phase == "canonicalV86GuardedCommitSeamStarted" } == false)
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    @Test func performTickEnabledV86CanaryZeroRecordsGuardedReportWithoutChangingPlan() async throws {
        let harness = try Self.makeHarness(
            peerInventory: Self.emptyCanonicalInventory(deviceID: "mac-01", platform: .Mac),
            v8Configuration: Self.v86Configuration()
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_300),
            bypassBackoff: true,
            syncRunID: "v86-enabled"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(plan?.uploadMetadataActions.isEmpty == true)
        #expect(plan?.downloadMetadataActions.isEmpty == true)
        #expect(plan?.uploadRecordingAudioActions.isEmpty == true)
        #expect(entries.contains { $0.phase == "canonicalV86GuardedCommitSeamStarted" })
        #expect(entries.contains { $0.phase == "canonicalV86CanaryBudgetZero" })
        #expect(entries.contains { $0.phase == "canonicalV86CommitNotExecuted" })
        #expect(entries.contains { $0.phase == "canonicalV86DuplicateSuppressionNotApplied" })
        #expect(entries.contains { $0.phase == "canonicalV8CutoverSeamStarted" } == false)
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    private struct Harness {
        let rootURL: URL
        let diagnosticsStore: ConnectionDiagnosticsStore
        let client: V86FakeLocalNetworkSyncClient
        let engine: LocalNetworkSyncEngine
    }

    private static func makeHarness(
        peerInventory: LocalNetworkSyncInventory,
        v8Configuration: CanonicalCutoverAppSeamConfiguration = .disabled
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("IPhoneV86GuardedCommitSeam")
        let audioStore = AudioFileStore(rootDirectoryURL: rootURL)
        try audioStore.ensureStorageDirectories()
        let studyStore = StudyLibraryStore(rootURL: rootURL.appendingPathComponent("Study", isDirectory: true), audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL.appendingPathComponent("Diagnostics", isDirectory: true))
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true))
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let client = V86FakeLocalNetworkSyncClient(peerInventory: peerInventory)
        let engine = LocalNetworkSyncEngine(
            connectionStore: V86FakeSecureMacConnectionSnapshotProvider(snapshot: Self.pairedSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: client,
            stateStore: stateStore,
            diagnosticsStore: diagnosticsStore,
            canonicalV8CutoverAppSeamConfiguration: v8Configuration
        )
        return Harness(rootURL: rootURL, diagnosticsStore: diagnosticsStore, client: client, engine: engine)
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
        trigger: CanonicalSyncPlanTrigger = .periodic,
        evidence: CanonicalRecordingMetadataCutoverEvidence = RecordingMetadataCutoverTestSupport.evidence(),
        candidates: [CanonicalRecordingMetadataCutoverCandidate]
    ) -> CanonicalRecordingMetadataGuardedCommitContext {
        let localManifest = Self.manifest(
            nodeID: "iphone-01",
            platform: "iPhone",
            objects: candidates.compactMap(\.localObject)
        )
        let peerManifest = Self.manifest(
            nodeID: "mac-01",
            platform: "Mac",
            objects: candidates.compactMap(\.peerObject)
        )
        return CanonicalRecordingMetadataGuardedCommitContext(
            syncRunID: "v86-direct",
            trigger: trigger,
            nodeRole: .iPhone,
            localManifest: localManifest,
            peerManifest: peerManifest,
            applyPlan: CanonicalApplyPlan(trigger: trigger, actions: candidates.map(\.action)),
            legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                .recordingMetadata: candidates.map { $0.action.actionID }
            ]),
            evidence: evidence,
            unresolvedConflictCount: candidates.filter(\.unresolvedConflict).count,
            canaryPolicy: CanonicalRecordingMetadataCanaryPolicy(maxObjectsPerSyncRun: 0),
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            cutoverToken: RecordingMetadataCutoverTestSupport.token(),
            candidates: candidates,
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true
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

    private static func emptyCanonicalInventory(deviceID: String, platform: LocalNetworkSyncPlatform) -> LocalNetworkSyncInventory {
        LocalNetworkSyncInventory.make(
            device: Self.device(deviceID: deviceID, platform: platform),
            canonicalManifest: Self.manifest(nodeID: deviceID, platform: platform.rawValue, objects: [])
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
            sharedSecretBase64URL: Data("v86-guarded-secret".utf8).base64URLEncodedString(),
            pairedAt: "2026-06-04T00:00:00Z"
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

@MainActor
private final class V86FakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding, SecureMacConnectionIntentProviding {
    var snapshot: SecureMacConnectionSnapshot
    var userConnectionIntent: UserConnectionIntent = .wantsConnected

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
}

private final class V86FakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
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
