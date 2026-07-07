//
//  CanonicalGeneratedArtifactGuardedCommitSeamTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalGeneratedArtifactGuardedCommitSeamTests {
    @Test func guardedCommitSeamAllowsEvidenceButSkipsCanaryZero() {
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
        #expect(result.willExecuteNow == false)
        #expect(result.n1ReadinessReport.status == .readyForN1AfterAudit)
        #expect(result.n1ReadinessReport.gateResult == .readyForN1AfterAudit)
        #expect(result.duplicateLegacySuppressionCandidates == [candidate.action.actionID])
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822SeamStarted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822GateAllowedBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactGateAllowedButNoExecution })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactCommitSkippedBecauseCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactDownloadSkippedBecauseCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactApplySkippedBecauseCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822CommitNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822DownloadNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822ApplyNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822LegacyFallbackPreserved })
        #expect(result.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactV822DuplicateSuppressionNotApplied })
        Self.verifyNoExecution(result)
    }

    @Test func guardedCommitSeamBlocksAnyN1OrExecutableStageConfig() {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate().candidate
        let n1 = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: Self.v822Configuration(
                canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy(canaryMaxObjectsPerSyncRun: 1, allowsInternalN1Execution: true)
            ),
            context: Self.context(candidates: [candidate])
        )
        let staged = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: Self.v822Configuration(
                canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy(
                    stagePolicy: CanonicalGeneratedArtifactCanaryStagePolicy(requestedStage: .n1, allowCandidateExecution: true),
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

    @Test func guardedCommitSeamBlocksAudioUnsafePathAndParentTombstone() {
        let audio = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: Self.v822Configuration(),
            context: Self.context(candidates: [GeneratedArtifactCutoverTestSupport.candidate(kind: .audio).candidate])
        )

        var unsafe = GeneratedArtifactCutoverTestSupport.candidate(kind: .noteMarkdown).candidate
        if var artifact = unsafe.peerArtifact {
            artifact.logicalPathToken = "/Users/vita/private/note.md"
            unsafe.peerArtifact = artifact
        }
        let unsafeResult = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: Self.v822Configuration(),
            context: Self.context(candidates: [unsafe])
        )

        var tombstone = GeneratedArtifactCutoverTestSupport.candidate(kind: .summaryJSON).candidate
        if var peerObject = tombstone.peerObject {
            peerObject.syncState = .deleted
            tombstone.peerObject = peerObject
        }
        let tombstoneResult = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: Self.v822Configuration(),
            context: Self.context(candidates: [tombstone])
        )

        #expect(audio.gate.allowed == false)
        #expect(audio.gate.result == .audioConfusionBlocked)
        #expect(audio.gate.failures.contains(.audioConfusionBlocked))
        #expect(audio.gate.failures.contains(.unsupportedArtifactKind))
        #expect(unsafeResult.gate.allowed == false)
        #expect(unsafeResult.gate.result == .unsafePathBlocked)
        #expect(unsafeResult.gate.failures.contains(.unsafePathBlocked))
        #expect(tombstoneResult.gate.allowed == false)
        #expect(tombstoneResult.gate.result == .parentTombstoneBlocked)
        #expect(tombstoneResult.gate.failures.contains(.parentTombstoneBlocked))
        Self.verifyNoExecution(audio)
        Self.verifyNoExecution(unsafeResult)
        Self.verifyNoExecution(tombstoneResult)
    }

    @Test func performTickEnabledV822CanaryZeroRecordsReportWithoutChangingPlanOrCallingArtifactRoutes() async throws {
        let harness = try Self.makeHarness(
            peerInventory: Self.emptyCanonicalInventory(deviceID: "mac-01", platform: .Mac),
            configuration: Self.v822Configuration()
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_500),
            bypassBackoff: true,
            syncRunID: "v822-generated-artifact-enabled"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(entries.contains { $0.phase == "canonicalGeneratedArtifactV822SeamStarted" })
        #expect(entries.contains { $0.phase == "canonicalGeneratedArtifactV822GateAllowedBudgetZero" })
        #expect(entries.contains { $0.phase == "canonicalGeneratedArtifactV822CanaryBudgetZero" })
        #expect(entries.contains { $0.phase == "canonicalGeneratedArtifactV822CommitNotExecuted" })
        #expect(entries.contains { $0.phase == "canonicalGeneratedArtifactV822DownloadNotExecuted" })
        #expect(entries.contains { $0.phase == "canonicalGeneratedArtifactV822ApplyNotExecuted" })
        #expect(entries.contains { $0.phase == "canonicalGeneratedArtifactV822DuplicateSuppressionNotApplied" })
        #expect(entries.contains { $0.phase == "canonicalGeneratedArtifactDuplicateLegacySuppressed" } == false)
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    @Test func diagnosticsAreRedactedAndUseNoFullHashesOrPaths() {
        let result = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: Self.v822Configuration(),
            context: Self.context(candidates: [GeneratedArtifactCutoverTestSupport.candidate().candidate])
        )
        let summary = result.diagnostics.map(\.diagnosticsSummary).joined(separator: "\n")

        #expect(summary.contains("/Users/") == false)
        #expect(summary.contains("/private/") == false)
        #expect(summary.contains(String(repeating: "a", count: 64)) == false)
    }

    private struct Harness {
        let rootURL: URL
        let diagnosticsStore: ConnectionDiagnosticsStore
        let client: V822FakeLocalNetworkSyncClient
        let engine: LocalNetworkSyncEngine
    }

    private static func makeHarness(
        peerInventory: LocalNetworkSyncInventory,
        configuration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("IPhoneV822GeneratedArtifactGuardedCommitSeam")
        let audioStore = AudioFileStore(rootDirectoryURL: rootURL)
        try audioStore.ensureStorageDirectories()
        let studyStore = StudyLibraryStore(rootURL: rootURL.appendingPathComponent("Study", isDirectory: true), audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL.appendingPathComponent("Diagnostics", isDirectory: true))
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true))
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let client = V822FakeLocalNetworkSyncClient(peerInventory: peerInventory)
        let engine = LocalNetworkSyncEngine(
            connectionStore: V822FakeSecureMacConnectionSnapshotProvider(snapshot: Self.pairedSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: client,
            stateStore: stateStore,
            diagnosticsStore: diagnosticsStore,
            canonicalGeneratedArtifactCutoverAppSeamConfiguration: configuration
        )
        return Harness(rootURL: rootURL, diagnosticsStore: diagnosticsStore, client: client, engine: engine)
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
        trigger: CanonicalSyncPlanTrigger = .periodic,
        evidence: CanonicalGeneratedArtifactCutoverEvidence = GeneratedArtifactCutoverTestSupport.evidence(),
        candidates: [CanonicalGeneratedArtifactCutoverCandidate]
    ) -> CanonicalGeneratedArtifactGuardedCommitContext {
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
        return CanonicalGeneratedArtifactGuardedCommitContext(
            syncRunID: "v822-generated-artifact-direct",
            trigger: trigger,
            nodeRole: .iPhone,
            localManifest: localManifest,
            peerManifest: peerManifest,
            legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                .generatedArtifacts: candidates.map { $0.action.actionID }
            ]),
            matrix: .v822GeneratedArtifactsActivePilot(libraryMetadataObservationCompleteOrRetirementCandidateReady: true),
            evidence: evidence,
            canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy(canaryMaxObjectsPerSyncRun: 0),
            cutoverToken: GeneratedArtifactCutoverTestSupport.token(),
            candidates: candidates,
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
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

    private static func emptyCanonicalInventory(deviceID: String, platform: LocalNetworkSyncPlatform) -> LocalNetworkSyncInventory {
        LocalNetworkSyncInventory.make(
            device: Self.device(deviceID: deviceID, platform: platform),
            canonicalManifest: CanonicalManifest.make(
                node: CanonicalNode(
                    nodeID: deviceID,
                    platform: platform.rawValue,
                    capabilities: [.recordingMetadata, .transcriptArtifact, .noteArtifact, .summaryArtifact]
                ),
                generatedAt: Date(timeIntervalSince1970: 1_000),
                objects: [],
                manifestCapabilities: [.recordingMetadata, .transcriptArtifact, .noteArtifact, .summaryArtifact]
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
            sharedSecretBase64URL: Data("v822-generated-artifact-secret".utf8).base64URLEncodedString(),
            pairedAt: "2026-06-05T00:00:00Z"
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

@MainActor
private final class V822FakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding, SecureMacConnectionIntentProviding {
    var snapshot: SecureMacConnectionSnapshot
    var userConnectionIntent: UserConnectionIntent = .wantsConnected

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
}

private final class V822FakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
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
