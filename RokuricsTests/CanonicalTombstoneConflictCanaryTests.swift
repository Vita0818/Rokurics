//
//  CanonicalTombstoneConflictCanaryTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalTombstoneConflictCanaryTests {
    @Test func n1ConfigurationIsExplicitAndDefaultOff() {
        let defaultConfig = CanonicalTombstoneConflictCanaryConfiguration()
        let defaultAppConfig = CanonicalTombstoneConflictCutoverAppSeamConfiguration()
        let defaultPolicy = CanonicalTombstoneConflictCanaryPolicy()
        let explicitConfig = CanonicalTombstoneConflictCanaryConfiguration.internalN1()
        let explicitPolicy = Self.n1Policy()
        let explicitAppConfig = CanonicalTombstoneConflictCutoverAppSeamConfiguration.enabled(
            mode: .canaryCommit,
            policy: CanonicalTombstoneConflictCutoverAppSeamPolicy(canaryPolicy: explicitPolicy),
            evidence: TombstoneConflictCutoverTestSupport.evidence(),
            cutoverToken: TombstoneConflictCutoverTestSupport.token()
        )

        #expect(defaultConfig.mode == .disabled)
        #expect(defaultConfig.canaryMaxObjectsPerSyncRun == 0)
        #expect(defaultConfig.strictN1Enabled == false)
        #expect(defaultAppConfig.isEnabled == false)
        #expect(CanonicalTombstoneConflictCanaryConfiguration(appSeamConfiguration: defaultAppConfig).strictN1Enabled == false)
        #expect(defaultPolicy.canaryMaxObjectsPerSyncRun == 0)
        #expect(defaultPolicy.allowCandidateExecution == false)
        #expect(defaultPolicy.runtimeSwitchEnabled == false)
        #expect(explicitConfig.strictN1Enabled)
        #expect(CanonicalTombstoneConflictCanaryConfiguration(appSeamConfiguration: explicitAppConfig).strictN1Enabled)
    }

    @Test func n1RequiresTombstoneConflictActivePilotAndBlocksOtherDomains() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let generatedArtifactsMatrix = CanonicalMigrationDomainMatrix.v822GeneratedArtifactsActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        )

        let result = await Self.run(
            matrix: generatedArtifactsMatrix,
            candidates: [candidate],
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.commits.isEmpty)
        #expect(result.observationReport.status == .blocked)
        #expect(result.selection.blockers.contains { $0.reason == .activePilotNotTombstoneConflict })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1FatalBlocker })
    }

    @Test func n1BlocksNAboveOneAllEligibleAndRuntimeSwitch() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let config = CanonicalTombstoneConflictCanaryConfiguration(
            mode: .n1,
            canaryMaxObjectsPerSyncRun: 2,
            explicitInternalTestConfiguration: true,
            runtimeSwitchEnabled: true,
            allowAllEligible: true
        )
        let policy = CanonicalTombstoneConflictCanaryPolicy(
            requestedStage: .allEligible,
            canaryMaxObjectsPerSyncRun: 2,
            allowCandidateExecution: true,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true,
            runtimeSwitchEnabled: true,
            allowAllEligible: true
        )

        let result = await Self.run(
            configuration: config,
            policy: policy,
            candidates: [candidate],
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )
        let blockers = Set(result.selection.blockers.map(\.reason))

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.commits.isEmpty)
        #expect(blockers.contains(.canaryBudgetAboveOneDenied))
        #expect(blockers.contains(.allEligibleDenied))
        #expect(blockers.contains(.runtimeSwitchDenied))
        #expect(result.observationReport.runtimeSwitch)
    }

    @Test func selectorIsDeterministicAndPrefersConflictThenResurrectionBeforeMarkers() {
        let object = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let library = TombstoneConflictCutoverTestSupport.libraryTombstoneCandidate().candidate
        let conflict = TombstoneConflictCutoverTestSupport.conflictCandidate().candidate
        let resurrection = TombstoneConflictCutoverTestSupport.resurrectionCandidate().candidate
        let artifact = TombstoneConflictCutoverTestSupport.generatedArtifactTombstoneCandidate().candidate
        let selector = CanonicalTombstoneConflictCanaryCandidateSelector()

        let first = selector.select(
            mode: .canary,
            policy: Self.n1Policy(),
            trigger: .periodic,
            evidence: TombstoneConflictCutoverTestSupport.evidence(),
            candidates: [object, artifact, library, resurrection, conflict]
        )
        let second = selector.select(
            mode: .canary,
            policy: Self.n1Policy(),
            trigger: .periodic,
            evidence: TombstoneConflictCutoverTestSupport.evidence(),
            candidates: [artifact, resurrection, library, object, conflict]
        )

        #expect(first.selectedCandidates.map(\.actionKind) == [.conflictRecord])
        #expect(second.selectedCandidates.map(\.actionKind) == [.conflictRecord])
        #expect(first.selectedCandidates.count == 1)
        #expect(first.reportOnlyCandidateCount == 1)
        #expect(first.safetyReports.first { $0.candidate.actionKind == .generatedArtifactTombstoneMarkUnsupported }?.kind == .generatedArtifactTombstoneReportOnly)
    }

    @Test func n1CanaryCommitsExactlyOneSoftMarkerAndRecordsObservation() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let executor = TombstoneConflictCutoverTestSupport.FakeExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded)
        #expect(result.cutoverResult.canaryAttemptedCount == 1)
        #expect(result.cutoverResult.commits.count == 1)
        #expect(result.cutoverResult.commits.first?.sideEffects.map(\.kind) == [.tombstoneMark])
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs == [candidate.action.actionID])
        #expect(result.observationReport.status == .committed)
        #expect(result.observationReport.canaryBudget == 1)
        #expect(result.observationReport.selectedCandidateCount == 1)
        #expect(result.observationReport.executedCandidateCount == 1)
        #expect(result.observationReport.successCount == 1)
        #expect(result.observationReport.duplicateSuppressionCount == 1)
        #expect(result.observationReport.uiMutated == false)
        #expect(result.observationReport.physicalDeletePerformed == false)
        #expect(result.observationReport.permanentDeletePerformed == false)
        #expect(result.observationReport.tombstoneGCPerformed == false)
        #expect(result.observationReport.nextStageRecommendation == .remainN1)
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1CanaryConfigured })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1CandidateSelected })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1CommitCompleted })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1PostconditionVerified })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1DuplicateLegacySuppressed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1ObservationRecorded })
    }

    @Test func n1CanaryCommitsExactlyOneConflictRecordCandidate() async {
        let candidate = TombstoneConflictCutoverTestSupport.conflictCandidate().candidate
        let executor = TombstoneConflictCutoverTestSupport.FakeExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded)
        #expect(result.cutoverResult.canaryAttemptedCount == 1)
        #expect(result.cutoverResult.commits.first?.actionKind == .conflictRecord)
        #expect(result.cutoverResult.commits.first?.sideEffects.map(\.kind) == [.conflictRecord])
        #expect(result.cutoverResult.readSideProjection?.mutatedUI == false)
        #expect(result.cutoverResult.readSideProjection?.syncOrUploadTriggered == false)
    }

    @Test func unsafeCandidatesAreBlockedBeforeCommit() async {
        let unsafeCandidates = [
            Self.reasonCandidate("physicalDelete"),
            Self.reasonCandidate("permanentDelete"),
            Self.reasonCandidate("tombstoneGC"),
            Self.reasonCandidate("restoreObject"),
            Self.reasonCandidate("clearTombstone"),
            Self.reasonCandidate("artifactDownload"),
            Self.reasonCandidate("audio"),
            Self.reasonCandidate("fullContentMutation"),
            Self.staleLiveCandidate(),
            TombstoneConflictCutoverTestSupport.conflictCandidate(conflictPolicyKnown: false).candidate,
            Self.missingRollbackCandidate(),
            Self.unsafePathCandidate()
        ]

        let result = await Self.run(
            candidates: unsafeCandidates,
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )
        let blockers = Set(result.selection.blockers.map(\.reason))

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.commits.isEmpty)
        #expect(blockers.contains(.physicalDeleteCandidate))
        #expect(blockers.contains(.permanentDeleteCandidate))
        #expect(blockers.contains(.tombstoneGCCandidate))
        #expect(blockers.contains(.restoreWithoutExplicitSignal))
        #expect(blockers.contains(.clearTombstoneCandidate))
        #expect(blockers.contains(.generatedArtifactApplyOnTombstonedParent))
        #expect(blockers.contains(.audioRelatedAction))
        #expect(blockers.contains(.fullContentMutation))
        #expect(blockers.contains(.staleLiveResurrection))
        #expect(blockers.contains(.ambiguousConflictAutoResolution))
        #expect(blockers.contains(.missingRollbackCheckpoint))
        #expect(blockers.contains(.unsafePathToken))
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1PhysicalDeleteBlocked })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1PermanentDeleteBlocked })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1GCBlocked })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1AutoResolutionBlocked })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1StaleLiveResurrectionBlocked })
    }

    @Test func noEligibleOrReportOnlyCandidateDoesNotExecuteAndKeepsLegacyFallback() async {
        let artifact = TombstoneConflictCutoverTestSupport.generatedArtifactTombstoneCandidate().candidate
        let empty = await Self.run(
            candidates: [],
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )
        let reportOnly = await Self.run(
            candidates: [artifact],
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )

        #expect(empty.cutoverResult.commits.isEmpty)
        #expect(empty.observationReport.status == .noEligibleCandidate)
        #expect(empty.cutoverResult.legacyFallbackUsed)
        #expect(reportOnly.cutoverResult.commits.isEmpty)
        #expect(reportOnly.observationReport.status == .reportOnly)
        #expect(reportOnly.selection.reportOnlyCandidateCount == 1)
        #expect(reportOnly.cutoverResult.legacyFallbackUsed)
    }

    @Test func commitFailureRollsBackPreservesFallbackAndDoesNotSuppressLegacy() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let executor = TombstoneConflictCutoverTestSupport.FakeExecutor(.postconditionMismatch)

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.observationReport.status == .failedRolledBack)
        #expect(result.observationReport.failureCount == 1)
        #expect(result.observationReport.rollbackCount == 1)
        #expect(result.observationReport.rollbackFailureCount == 0)
        #expect(await executor.rolledBackActionIDs == [candidate.action.actionID])
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1CommitFailed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1RollbackCompleted })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1LegacyFallbackUsed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1DuplicateSuppressionSkipped })
    }

    @Test func rollbackFailureIsFatalBlocker() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let executor = RollbackFailingTombstoneConflictExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.fatalBlocker)
        #expect(result.observationReport.status == .fatalRollbackFailure)
        #expect(result.observationReport.rollbackFailureCount == 1)
        #expect(result.observationReport.fatalBlockerCount == 1)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1RollbackFailed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1FatalBlocker })
    }

    @Test func realApplyPortWritesOnlyRootBoundMarkerAndNeverDeletesContent() async throws {
        let rootURL = TombstoneConflictCutoverTestSupport.makeScratchRoot("IPhoneV828TombstoneConflictN1")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let audioURL = rootURL.appendingPathComponent("audio/recording-01.m4a")
        try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("audio-bytes-preserved".utf8).write(to: audioURL)
        let applyPort = try IPhoneTombstoneConflictRealApplyPort(testRootURL: rootURL)
        let executor = IPhoneTombstoneConflictCutoverExecutor(applyPort: applyPort)

        let result = await Self.run(candidates: [candidate], executor: executor)
        let markerBytes = try await applyPort.rootBoundTombstoneConflictBytes(for: candidate.action.actionID)

        #expect(result.succeeded)
        #expect(markerBytes?.isEmpty == false)
        #expect(try Data(contentsOf: audioURL) == Data("audio-bytes-preserved".utf8))
        #expect(result.cutoverResult.commits.first?.physicalDeleteSuppressed == true)
        #expect(result.cutoverResult.commits.first?.permanentDeleteSuppressed == true)
        #expect(result.cutoverResult.commits.first?.tombstoneGCSuppressed == true)
        #expect(result.cutoverResult.commits.first?.generatedArtifactDownloadBlocked == true)
        #expect(result.cutoverResult.commits.first?.receiveJSONMutated == false)
        #expect(result.cutoverResult.commits.first?.audioTranscriptNoteSummaryDeleted == false)
    }

    @Test func iPhoneSeamDisabledByDefaultDoesNotRecordN1DiagnosticsOrUploadJobs() async throws {
        let harness = try Self.makeHarness(configuration: .disabled)
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_500),
            bypassBackoff: true,
            syncRunID: "v828-tombstone-conflict-default-off"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictN1CanaryConfigured" } == false)
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    @Test func iPhoneExplicitN1NoEligibleCandidateDoesNotMutateUploadOrUIPaths() async throws {
        let harness = try Self.makeHarness(
            configuration: .enabled(
                mode: .canaryCommit,
                policy: CanonicalTombstoneConflictCutoverAppSeamPolicy(canaryPolicy: Self.n1Policy()),
                evidence: TombstoneConflictCutoverTestSupport.evidence(),
                cutoverToken: TombstoneConflictCutoverTestSupport.token()
            ),
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        _ = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 2_500),
            bypassBackoff: true,
            syncRunID: "v828-tombstone-conflict-no-eligible"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictN1CanaryConfigured" })
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictN1NoEligibleCandidate" })
        #expect(entries.contains { $0.phase == "canonicalTombstoneConflictN1LegacyFallbackUsed" })
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    private struct Harness {
        let rootURL: URL
        let diagnosticsStore: ConnectionDiagnosticsStore
        let client: V828FakeLocalNetworkSyncClient
        let engine: LocalNetworkSyncEngine
    }

    private static func makeHarness(
        configuration: CanonicalTombstoneConflictCutoverAppSeamConfiguration,
        executor: (any CanonicalTombstoneConflictCutoverExecutor)? = nil
    ) throws -> Harness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("IPhoneV828TombstoneConflictCanary", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let audioStore = AudioFileStore(rootDirectoryURL: rootURL)
        try audioStore.ensureStorageDirectories()
        let studyStore = StudyLibraryStore(rootURL: rootURL.appendingPathComponent("Study", isDirectory: true), audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL.appendingPathComponent("Diagnostics", isDirectory: true))
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true))
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let client = V828FakeLocalNetworkSyncClient(peerInventory: Self.emptyCanonicalInventory(deviceID: "mac-01", platform: .Mac))
        let engine = LocalNetworkSyncEngine(
            connectionStore: V828FakeSecureMacConnectionSnapshotProvider(snapshot: Self.pairedSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: client,
            stateStore: stateStore,
            diagnosticsStore: diagnosticsStore,
            canonicalTombstoneConflictCutoverAppSeamConfiguration: configuration,
            canonicalTombstoneConflictCutoverExecutor: executor
        )
        return Harness(rootURL: rootURL, diagnosticsStore: diagnosticsStore, client: client, engine: engine)
    }

    private static func run(
        configuration: CanonicalTombstoneConflictCanaryConfiguration = .internalN1(),
        policy: CanonicalTombstoneConflictCanaryPolicy = Self.n1Policy(),
        matrix: CanonicalMigrationDomainMatrix = .v827TombstoneConflictActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            generatedArtifactsTemplateCompleteOrObservationReady: true
        ),
        candidates: [CanonicalTombstoneConflictCandidate],
        trigger: CanonicalSyncPlanTrigger = .periodic,
        executor: any CanonicalTombstoneConflictCutoverExecutor
    ) async -> CanonicalTombstoneConflictCanaryResult {
        await CanonicalTombstoneConflictN1CanaryRunner().run(
            configuration: configuration,
            policy: policy,
            token: TombstoneConflictCutoverTestSupport.token(),
            evidence: TombstoneConflictCutoverTestSupport.evidence(),
            matrix: matrix,
            candidates: candidates,
            trigger: trigger,
            nodeRole: .iPhone,
            syncRunID: "v828-tombstone-conflict-n1",
            executor: executor
        )
    }

    private nonisolated static func n1Policy(
        runtimeSwitchEnabled: Bool = false,
        allowAllEligible: Bool = false
    ) -> CanonicalTombstoneConflictCanaryPolicy {
        CanonicalTombstoneConflictCanaryPolicy(
            canaryMaxObjectsPerSyncRun: 1,
            allowCandidateExecution: true,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true,
            runtimeSwitchEnabled: runtimeSwitchEnabled,
            allowAllEligible: allowAllEligible
        )
    }

    private static func reasonCandidate(_ reason: String) -> CanonicalTombstoneConflictCandidate {
        TombstoneConflictCutoverTestSupport.objectTombstoneCandidate(reason: reason).candidate
    }

    private static func staleLiveCandidate() -> CanonicalTombstoneConflictCandidate {
        var candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        candidate.staleLiveMetadataRisk = true
        return candidate
    }

    private static func missingRollbackCandidate() -> CanonicalTombstoneConflictCandidate {
        var candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        candidate.rollbackCheckpointID = nil
        candidate.rollbackEvidenceAvailable = false
        return candidate
    }

    private static func unsafePathCandidate() -> CanonicalTombstoneConflictCandidate {
        var candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        candidate.routePath = "/unsafe-tombstone-conflict"
        return candidate
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
            sharedSecretBase64URL: Data("v828-tombstone-conflict-secret".utf8).base64URLEncodedString(),
            pairedAt: "2026-06-05T00:00:00Z"
        )
    }
}

actor RollbackFailingTombstoneConflictExecutor: CanonicalTombstoneConflictCutoverExecutor {
    func commitTombstoneConflict(
        _ candidate: CanonicalTombstoneConflictCandidate
    ) async -> CanonicalTombstoneConflictProductionCommitResult {
        .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "testPostconditionMismatch")
    }

    func rollbackTombstoneConflict(
        _ candidate: CanonicalTombstoneConflictCandidate,
        reason: CanonicalTombstoneConflictFailure
    ) async -> CanonicalTombstoneConflictRollbackExecutionResult {
        CanonicalTombstoneConflictRollbackExecutionResult(
            checkpointID: candidate.effectiveRollbackCheckpointID,
            succeeded: false,
            fatal: true,
            reason: "testRollbackFailure"
        )
    }
}

@MainActor
private final class V828FakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding, SecureMacConnectionIntentProviding {
    var snapshot: SecureMacConnectionSnapshot
    var userConnectionIntent: UserConnectionIntent = .wantsConnected

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
}

private final class V828FakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
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
