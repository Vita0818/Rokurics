//
//  CanonicalTombstoneConflictGuardedCommitSeamTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalTombstoneConflictGuardedCommitSeamTests {
    @Test func pilotActivationPromotesOnlyTombstoneConflictAfterTemplateReadiness() {
        let activation = CanonicalTombstoneConflictPilotActivation.v827(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            generatedArtifactsTemplateCompleteOrObservationReady: true
        )
        let report = activation.result.matrixReport

        #expect(activation.result.activated)
        #expect(report.allowed)
        #expect(report.activePilotDomain == .tombstoneConflict)
        #expect(activation.result.matrix.policy(for: .tombstoneConflict)?.activePilot == true)
        #expect(activation.result.matrix.policy(for: .generatedArtifacts)?.activePilot == false)
        #expect(activation.result.matrix.policy(for: .libraryMetadata)?.activePilot == false)
        #expect(activation.result.matrix.policies.filter(\.activePilot).count == 1)
        #expect(activation.result.matrix.policies.allSatisfy { $0.runtimeSwitchEnabled == false })
        #expect(CanonicalMigrationGlobalConfigValidator().validate(activation.result.matrix).valid)
    }

    @Test func pilotActivationRequiresGeneratedArtifactsAndLibraryTemplateSources() {
        let blocked = CanonicalTombstoneConflictPilotActivation.v827(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: false,
            generatedArtifactsTemplateCompleteOrObservationReady: false
        )

        #expect(blocked.result.activated == false)
        #expect(blocked.result.blockers.contains(.generatedArtifactsTemplateMissing))
        #expect(blocked.result.blockers.contains(.libraryMetadataObservationMissing))
        #expect(blocked.result.matrixReport.activePilotDomain == nil)
    }

    @Test func guardedSeamAllowsEvidenceButSkipsCanaryZero() {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let result = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
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
        #expect(result.n1ReadinessReport.nextRecommendedStage == .n1AfterAudit)
        #expect(result.duplicateLegacySuppressionCandidates == [candidate.action.actionID])
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827SeamStarted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827GateAllowedBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827CanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictGateAllowedButNoExecution })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictCommitSkippedBecauseCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictDeleteSkippedBecauseCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictRestoreSkippedBecauseCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictResolutionSkippedBecauseCanaryBudgetZero })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827CommitNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827DeleteNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827RestoreNotExecuted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827ConflictNotAutoResolved })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827LegacyFallbackPreserved })
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneConflictV827DuplicateSuppressionNotApplied })
        Self.verifyNoExecution(result)
    }

    @Test func guardedSeamBlocksN1OrExecutableStageConfig() {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let n1 = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(
                canaryPolicy: CanonicalTombstoneConflictCanaryPolicy(
                    requestedStage: .n1,
                    canaryMaxObjectsPerSyncRun: 1,
                    allowCandidateExecution: true
                )
            ),
            context: Self.context(candidates: [candidate])
        )
        let runtime = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(
                canaryPolicy: CanonicalTombstoneConflictCanaryPolicy(runtimeSwitchEnabled: true)
            ),
            context: Self.context(candidates: [candidate])
        )

        #expect(n1.gate.allowed == false)
        #expect(n1.gate.failures.contains(.canaryBudgetNonZeroDenied))
        #expect(n1.gate.failures.contains(.canaryStageExecutionDenied))
        #expect(runtime.gate.allowed == false)
        #expect(runtime.gate.failures.contains(.runtimeSwitchDenied))
        Self.verifyNoExecution(n1)
        Self.verifyNoExecution(runtime)
    }

    @Test func guardedSeamBlocksForbiddenTombstoneConflictActions() {
        let physical = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
            context: Self.context(candidates: [TombstoneConflictCutoverTestSupport.objectTombstoneCandidate(reason: "physicalDelete").candidate])
        )
        let permanent = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
            context: Self.context(candidates: [TombstoneConflictCutoverTestSupport.objectTombstoneCandidate(reason: "permanentDelete").candidate])
        )
        let gc = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
            context: Self.context(candidates: [TombstoneConflictCutoverTestSupport.objectTombstoneCandidate(reason: "tombstoneGC").candidate])
        )
        var staleCandidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        staleCandidate.staleLiveMetadataRisk = true
        let stale = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
            context: Self.context(candidates: [staleCandidate])
        )
        let ambiguous = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
            context: Self.context(candidates: [TombstoneConflictCutoverTestSupport.conflictCandidate(conflictPolicyKnown: false).candidate])
        )
        let generatedArtifactBlocked = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
            context: Self.context(candidates: [TombstoneConflictCutoverTestSupport.generatedArtifactTombstoneCandidate().candidate])
        )

        #expect(physical.gate.result == .physicalDeleteBlocked)
        #expect(permanent.gate.result == .permanentDeleteBlocked)
        #expect(gc.gate.result == .tombstoneGCBlocked)
        #expect(stale.gate.result == .staleLiveResurrectionRisk)
        #expect(ambiguous.gate.result == .conflictPolicyAmbiguous)
        #expect(generatedArtifactBlocked.gate.failures.contains(.generatedArtifactTombstonedParentApplyBlocked))
        [physical, permanent, gc, stale, ambiguous, generatedArtifactBlocked].forEach(Self.verifyNoExecution)
    }

    @Test func diagnosticsAndReadinessReportAreRedacted() {
        let result = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: Self.v827Configuration(),
            context: Self.context(
                syncRunID: "/Users/vita/private/sync-run",
                candidates: [TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate]
            )
        )
        let summary = (result.diagnostics.map(\.diagnosticsSummary) + [result.n1ReadinessReport.diagnosticsSummary]).joined(separator: "\n")

        #expect(summary.contains("/Users/") == false)
        #expect(summary.contains("/private/") == false)
        #expect(summary.contains(String(repeating: "a", count: 64)) == false)
    }

    @Test func iPhoneSeamEnabledWithNZeroEvaluatesGateOnly() async throws {
        let harness = try Self.makeHarness(
            peerInventory: Self.emptyCanonicalInventory(deviceID: "mac-01", platform: .Mac),
            configuration: Self.v827Configuration()
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_500),
            bypassBackoff: true,
            syncRunID: "v827-tombstone-conflict-enabled"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictV827SeamStarted" })
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictV827GateAllowedBudgetZero" })
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictV827CanaryBudgetZero" })
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictV827CommitNotExecuted" })
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictV827DeleteNotExecuted" })
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictV827RestoreNotExecuted" })
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictV827ConflictNotAutoResolved" })
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictV827DuplicateSuppressionNotApplied" })
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    @Test func iPhoneSeamDisabledByDefaultRecordsNoV827Diagnostics() async throws {
        let harness = try Self.makeHarness(
            peerInventory: Self.emptyCanonicalInventory(deviceID: "mac-01", platform: .Mac),
            configuration: .disabled
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        _ = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_500),
            bypassBackoff: true,
            syncRunID: "v827-tombstone-conflict-disabled"
        )

        #expect(harness.diagnosticsStore.loadEntries().contains { $0.phase == "canonicalTombstoneConflictV827SeamStarted" } == false)
    }

    private struct Harness {
        let rootURL: URL
        let diagnosticsStore: ConnectionDiagnosticsStore
        let client: V827FakeLocalNetworkSyncClient
        let engine: LocalNetworkSyncEngine
    }

    private static func makeHarness(
        peerInventory: LocalNetworkSyncInventory,
        configuration: CanonicalTombstoneConflictCutoverAppSeamConfiguration
    ) throws -> Harness {
        let rootURL = Self.makeScratchRoot("IPhoneV827TombstoneConflictGuardedSeam")
        let audioStore = AudioFileStore(rootDirectoryURL: rootURL)
        try audioStore.ensureStorageDirectories()
        let studyStore = StudyLibraryStore(rootURL: rootURL.appendingPathComponent("Study", isDirectory: true), audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL.appendingPathComponent("Diagnostics", isDirectory: true))
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true))
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let client = V827FakeLocalNetworkSyncClient(peerInventory: peerInventory)
        let engine = LocalNetworkSyncEngine(
            connectionStore: V827FakeSecureMacConnectionSnapshotProvider(snapshot: Self.pairedSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: client,
            stateStore: stateStore,
            diagnosticsStore: diagnosticsStore,
            canonicalTombstoneConflictCutoverAppSeamConfiguration: configuration
        )
        return Harness(rootURL: rootURL, diagnosticsStore: diagnosticsStore, client: client, engine: engine)
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
        syncRunID: String = "v827-tombstone-conflict-direct",
        trigger: CanonicalSyncPlanTrigger = .periodic,
        evidence: CanonicalTombstoneConflictCutoverEvidence = TombstoneConflictCutoverTestSupport.evidence(),
        candidates: [CanonicalTombstoneConflictCandidate]
    ) -> CanonicalTombstoneConflictGuardedContext {
        CanonicalTombstoneConflictGuardedContext(
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: .iPhone,
            localManifest: TombstoneConflictCutoverTestSupport.emptyManifest(),
            peerManifest: TombstoneConflictCutoverTestSupport.emptyManifest(nodeID: "mac-01", platform: "Mac"),
            candidates: candidates,
            legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                .tombstones: candidates.map { $0.action.actionID },
                .conflicts: candidates.map { $0.action.actionID }
            ]),
            matrix: .v827TombstoneConflictActivePilot(
                libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
                generatedArtifactsTemplateCompleteOrObservationReady: true
            ),
            evidence: evidence,
            canaryPolicy: CanonicalTombstoneConflictCanaryPolicy(),
            cutoverToken: TombstoneConflictCutoverTestSupport.token(),
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true
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
            sharedSecretBase64URL: Data("v827-tombstone-conflict-secret".utf8).base64URLEncodedString(),
            pairedAt: "2026-06-05T00:00:00Z"
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
        #expect(result.tombstoneMarkerWriteAttempted == false)
        #expect(result.tombstoneClearAttempted == false)
        #expect(result.receiveJSONMutated == false)
        #expect(result.generatedArtifactApplyOrDownloadCausedByTombstonedObject == false)
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
        #expect(result.pendingCountsChanged == false)
    }
}

@MainActor
private final class V827FakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding, SecureMacConnectionIntentProviding {
    var snapshot: SecureMacConnectionSnapshot
    var userConnectionIntent: UserConnectionIntent = .wantsConnected

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
}

private final class V827FakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
    let peerInventory: LocalNetworkSyncInventory
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
        LocalNetworkSyncInventoryResponse(ok: true, inventory: peerInventory, error: nil)
    }

    func sendLocalNetworkSyncStartSignal(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartRequest
    ) async throws -> LocalNetworkSyncStartResponse {
        LocalNetworkSyncStartResponse(ok: true, syncRunID: request.syncRunID, peerDeviceID: "mac-01", ackAt: Date(), disposition: "ack", error: nil)
    }

    func sendLocalNetworkSyncStartAck(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartAckRequest
    ) async throws -> LocalNetworkSyncStartAckResponse {
        LocalNetworkSyncStartAckResponse(ok: true, syncRunID: request.syncRunID, peerDeviceID: "mac-01", ackReceivedAt: Date(), error: nil)
    }

    func applyLocalNetworkSyncMetadata(
        settings: SecureMacConnectionSnapshot,
        manifest: StudyLibrarySyncManifest
    ) async throws -> StudyLibrarySyncManifestResponse {
        applyMetadataCount += 1
        return StudyLibrarySyncManifestResponse(ok: true, manifest: nil, syncState: nil, deviceStatus: nil, applyResult: StudyLibrarySyncApplyResult(), baseCommitID: nil, newCommitID: nil, remoteChanges: nil, rejectedChanges: nil, error: nil)
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactRequest
    ) async throws -> LocalNetworkSyncArtifactResponse {
        artifactRequestCount += 1
        return LocalNetworkSyncArtifactResponse(ok: false, artifactID: nil, kind: nil, checksum: nil, size: nil, logicalPathToken: nil, dataBase64: nil, error: "not_expected")
    }

    func fetchLocalNetworkSyncArtifactStatus(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactStatusRequest
    ) async throws -> LocalNetworkSyncArtifactStatusResponse {
        LocalNetworkSyncArtifactStatusResponse(ok: true, artifactID: request.artifactID, checksum: request.checksum, size: request.size, confirmedBytes: 0, nextOffset: 0, state: .pending, error: nil)
    }

    func putLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactPutRequest
    ) async throws -> LocalNetworkSyncArtifactPutResponse {
        artifactPutCount += 1
        return LocalNetworkSyncArtifactPutResponse(ok: true, artifactID: request.artifactID, disposition: "acceptedNew", checksum: request.checksum, size: request.size, confirmedBytes: request.size, error: nil)
    }
}
