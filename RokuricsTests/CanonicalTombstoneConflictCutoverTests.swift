//
//  CanonicalTombstoneConflictCutoverTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalTombstoneConflictCutoverTests {
    @Test func appSeamDefaultsDisabledAndCanaryBudgetZero() {
        let config = CanonicalTombstoneConflictCutoverAppSeamConfiguration()

        #expect(config.isEnabled == false)
        #expect(config.effectiveMode == .disabled)
        #expect(config.policy.canaryPolicy.requestedStage == .disabled)
        #expect(config.policy.canaryPolicy.canaryMaxObjectsPerSyncRun == 0)
        #expect(config.policy.canaryPolicy.allowCandidateExecution == false)
    }

    @Test func candidateGenerationCoversTombstoneConflictAndUnsupportedArtifactMarker() throws {
        let object = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let artifact = TombstoneConflictCutoverTestSupport.generatedArtifactTombstoneCandidate().candidate
        let conflict = TombstoneConflictCutoverTestSupport.conflictCandidate().candidate
        let resurrection = TombstoneConflictCutoverTestSupport.resurrectionCandidate().candidate
        let library = TombstoneConflictCutoverTestSupport.libraryTombstoneCandidate().candidate
        let applyPlan = CanonicalApplyPlan(
            trigger: .periodic,
            actions: [object.action, artifact.action, conflict.action, resurrection.action],
            conflicts: [try #require(conflict.conflict)],
            tombstones: [try #require(object.recordingTombstone), try #require(artifact.recordingTombstone)]
        )
        let libraryPlan = CanonicalLibrarySyncPlan(
            applyActions: [library.action],
            tombstones: [try #require(library.libraryTombstone)]
        )

        let candidates = CanonicalTombstoneConflictCandidate.candidates(
            from: applyPlan,
            libraryPlan: libraryPlan,
            localManifest: TombstoneConflictCutoverTestSupport.emptyManifest(),
            peerManifest: TombstoneConflictCutoverTestSupport.emptyManifest(nodeID: "mac-01", platform: "Mac")
        )
        let actionKinds = Set(candidates.map(\.actionKind))

        #expect(actionKinds.contains(.objectTombstoneApply))
        #expect(actionKinds.contains(.libraryTombstoneApply))
        #expect(actionKinds.contains(.generatedArtifactTombstoneMarkUnsupported))
        #expect(actionKinds.contains(.conflictRecord))
        #expect(actionKinds.contains(.resurrectionBlocked))
        #expect(candidates.first { $0.actionKind == .generatedArtifactTombstoneMarkUnsupported }?.domain == .generatedArtifactTombstoneMarker)
    }

    @Test func noCommitExecutorStagesSummaryOnlyAndSuppressesProductionPaths() throws {
        let rootURL = TombstoneConflictCutoverTestSupport.makeScratchRoot("IPhoneTombstoneConflictNoCommit")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let executor = IPhoneTombstoneConflictNoCommitExecutor(stagingRootURL: rootURL)

        let result = executor.stageTombstoneConflictNoCommit(
            CanonicalTombstoneConflictNoCommitCandidate(cutoverCandidate: candidate)
        )

        #expect(result.staged)
        #expect(result.wroteOnlyStagingRoot)
        #expect(result.productionCommitSuppressed)
        #expect(result.applySyncManifestCalled == false)
        #expect(result.networkSendSuppressed)
        #expect(result.receiveJSONMutationSuppressed)
        #expect(result.generatedArtifactDeletionSuppressed)
        #expect(result.audioDeletionSuppressed)
        #expect(result.legacyDuplicateSuppressed == false)
        #expect(result.cleanupEvidence?.status == .removed)
        #expect(result.payloadHashPrefix?.count == 12)
        #expect(FileManager.default.fileExists(atPath: rootURL.path) == false)
    }

    @Test func rootBoundCommitAndRollbackOnlyMutateMarkerOrLedger() async throws {
        let rootURL = TombstoneConflictCutoverTestSupport.makeScratchRoot("IPhoneTombstoneConflictRootBound")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let previousMarkerBytes = Data("previous-tombstone-marker".utf8)
        let logicalPath = CanonicalRootBoundTombstoneConflictTarget.defaultLogicalPathToken(
            objectID: candidate.objectID,
            domain: candidate.domain,
            actionKind: candidate.actionKind,
            conflictKind: candidate.conflictKindSummary
        )
        let markerURL = rootURL.appendingPathComponent(logicalPath)
        let audioURL = rootURL.appendingPathComponent("audio/recording-01.m4a")
        try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try previousMarkerBytes.write(to: markerURL)
        try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("audio-bytes-preserved".utf8).write(to: audioURL)

        let applyPort = try IPhoneTombstoneConflictRealApplyPort(testRootURL: rootURL)
        let executor = IPhoneTombstoneConflictCutoverExecutor(applyPort: applyPort)

        let result = await TombstoneConflictCutoverTestSupport.run(candidates: [candidate], executor: executor)
        let committedBytes = try await applyPort.rootBoundTombstoneConflictBytes(for: candidate.action.actionID)
        let rollback = await executor.rollbackTombstoneConflict(candidate, reason: .postconditionMismatch)
        let restoredBytes = try await applyPort.rootBoundTombstoneConflictBytes(for: candidate.action.actionID)

        #expect(result.canarySucceeded)
        #expect(result.commits.first?.sideEffects.map(\.kind) == [.tombstoneMark])
        #expect(result.commits.first?.physicalDeleteSuppressed == true)
        #expect(result.commits.first?.audioTranscriptNoteSummaryDeleted == false)
        #expect(committedBytes != previousMarkerBytes)
        #expect(rollback.succeeded)
        #expect(restoredBytes == previousMarkerBytes)
        #expect(try Data(contentsOf: audioURL) == Data("audio-bytes-preserved".utf8))
    }

    @Test func productionRootApplyPortIsDisabledByDefault() async throws {
        let rootURL = TombstoneConflictCutoverTestSupport.makeScratchRoot("IPhoneTombstoneConflictProductionDisabled")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let applyPort = try IPhoneTombstoneConflictRealApplyPort(productionRootURL: rootURL)
        let executor = IPhoneTombstoneConflictCutoverExecutor(applyPort: applyPort)

        let commit = await executor.commitTombstoneConflict(candidate)

        #expect(applyPort.isDryRunOnly)
        #expect(applyPort.applyPortMode == .productionRootDisabled)
        #expect(commit.committed == false)
        #expect(commit.failureKind == .applyFailureBeforeCommit)
        #expect(try await applyPort.rootBoundTombstoneConflictBytes(for: candidate.action.actionID) == nil)
    }

    @Test func canaryStagePolicyAdvancesOnlyAfterCleanPreviousStage() {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let policy = CanonicalTombstoneConflictCanaryPolicy(
            requestedStage: .n3,
            canaryMaxObjectsPerSyncRun: 3,
            allowCandidateExecution: true
        )
        let allowedGate = CanonicalTombstoneConflictCutoverRunner().evaluateGate(
            mode: .canary,
            policy: policy,
            token: TombstoneConflictCutoverTestSupport.token(),
            evidence: TombstoneConflictCutoverTestSupport.evidence(
                stageEvidence: .passing(stage: .n3, successfulCommitCount: 1)
            ),
            candidates: [candidate],
            trigger: .periodic
        )
        let blockedGate = CanonicalTombstoneConflictCutoverRunner().evaluateGate(
            mode: .canary,
            policy: policy,
            token: TombstoneConflictCutoverTestSupport.token(),
            evidence: TombstoneConflictCutoverTestSupport.evidence(
                stageEvidence: CanonicalTombstoneConflictCanaryStageEvidence(
                    stage: .n3,
                    previousStage: .n1,
                    status: .passed,
                    successfulCommitCount: 1,
                    rollbackFailureCount: 1,
                    noCommitEvidenceAvailable: true,
                    observationWindowComplete: true
                )
            ),
            candidates: [candidate],
            trigger: .periodic
        )

        #expect(allowedGate.allowed)
        #expect(blockedGate.allowed == false)
        #expect(blockedGate.failures.contains(.previousStageRollbackFailure))
    }

    @Test func gateBlocksPhysicalDeleteGcAmbiguityAndArtifactTombstoneMarker() {
        let physicalDelete = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate(reason: "physicalDelete").candidate
        let ambiguousConflict = TombstoneConflictCutoverTestSupport.conflictCandidate(conflictPolicyKnown: false).candidate
        let artifactUnsupported = TombstoneConflictCutoverTestSupport.generatedArtifactTombstoneCandidate().candidate

        let physicalGate = TombstoneConflictCutoverTestSupport.gate(candidates: [physicalDelete])
        let ambiguousGate = TombstoneConflictCutoverTestSupport.gate(candidates: [ambiguousConflict])
        let artifactGate = TombstoneConflictCutoverTestSupport.gate(candidates: [artifactUnsupported])

        #expect(physicalGate.failures.contains(.physicalDeleteAttempted))
        #expect(ambiguousGate.failures.contains(.conflictPolicyAmbiguous))
        #expect(artifactGate.failures.contains(.generatedArtifactTombstoneUnsupported))
    }

    @Test func resurrectionBlockedRecordsConflictLedgerWithoutGeneratedArtifactDownload() async throws {
        let candidate = TombstoneConflictCutoverTestSupport.resurrectionCandidate().candidate
        let executor = TombstoneConflictCutoverTestSupport.FakeExecutor()

        let result = await TombstoneConflictCutoverTestSupport.run(candidates: [candidate], executor: executor)
        let commit = try #require(result.commits.first)

        #expect(result.canarySucceeded)
        #expect(commit.actionKind == .resurrectionBlocked)
        #expect(commit.generatedArtifactDownloadBlocked)
        #expect(commit.receiveJSONMutated == false)
        #expect(commit.audioTranscriptNoteSummaryDeleted == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalTombstoneResurrectionBlocked })
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
    }

    @Test func legacyDuplicateSuppressionRunsOnlyAfterSuccessfulCommit() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let success = await TombstoneConflictCutoverTestSupport.run(
            candidates: [candidate],
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )
        let failed = await TombstoneConflictCutoverTestSupport.run(
            candidates: [candidate],
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor(.postconditionMismatch)
        )
        let legacy = [
            CanonicalTombstoneConflictLegacyActionIdentity(
                actionID: "legacy-match",
                objectID: candidate.objectID,
                domain: candidate.domain,
                actionKind: candidate.actionKind,
                conflictKind: candidate.conflictKindSummary
            )
        ]

        #expect(CanonicalTombstoneConflictLegacyDuplicateSuppression.suppressedLegacyActionIDs(after: success, legacyActions: legacy) == ["legacy-match"])
        #expect(CanonicalTombstoneConflictLegacyDuplicateSuppression.suppressedLegacyActionIDs(after: failed, legacyActions: legacy).isEmpty)
        #expect(failed.legacyFallbackUsed)
    }

    @Test func readSideParallelProjectionIsDiagnosticsOnly() async throws {
        let candidate = TombstoneConflictCutoverTestSupport.conflictCandidate().candidate
        let result = await TombstoneConflictCutoverTestSupport.run(
            candidates: [candidate],
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )
        let projection = try #require(result.readSideProjection)

        #expect(projection.equivalent)
        #expect(projection.mutatedUI == false)
        #expect(projection.syncOrUploadTriggered == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalConflictUIProjectionParallelReadStarted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalConflictUIProjectionParallelReadEquivalent })
    }
}

enum TombstoneConflictCutoverTestSupport {
    struct CandidateBundle {
        var candidate: CanonicalTombstoneConflictCandidate
    }

    static func node(_ id: String = "iphone-01", platform: String = "iPhone") -> CanonicalNode {
        CanonicalNode(
            nodeID: id,
            platform: platform,
            capabilities: [.recordingMetadata, .audioArtifact, .objectProjection]
        )
    }

    static func token() -> CanonicalCutoverToken {
        CanonicalCutoverToken(tokenID: "tombstone-conflict-token", syncRunID: "sync-run-v811", ownerApproved: true)
    }

    static func evidence(
        stageEvidence: CanonicalTombstoneConflictCanaryStageEvidence? = nil
    ) -> CanonicalTombstoneConflictCutoverEvidence {
        var evidence = CanonicalTombstoneConflictCutoverEvidence.passing(
            rollbackPlan: CanonicalRollbackPlan(
                planID: "tombstone-conflict-rollback-plan",
                checkpoints: [
                    CanonicalRollbackCheckpoint(checkpointID: "tombstone-checkpoint", domain: .tombstones, objectID: "recording-01"),
                    CanonicalRollbackCheckpoint(checkpointID: "conflict-checkpoint", domain: .conflicts, objectID: "recording-01")
                ],
                actions: [
                    CanonicalRollbackAction(
                        actionID: "tombstone-rollback",
                        kind: .tombstoneRollback,
                        domain: .tombstones,
                        checkpointID: "tombstone-checkpoint"
                    ),
                    CanonicalRollbackAction(
                        actionID: "conflict-ledger-rollback",
                        kind: .conflictLedgerNoOp,
                        domain: .conflicts,
                        checkpointID: "conflict-checkpoint"
                    )
                ]
            )
        )
        evidence.canaryStageEvidence = stageEvidence
        return evidence
    }

    static func run(
        candidates: [CanonicalTombstoneConflictCandidate],
        executor: any CanonicalTombstoneConflictCutoverExecutor
    ) async -> CanonicalTombstoneConflictCutoverResult {
        await CanonicalTombstoneConflictCutoverRunner().run(
            mode: .canary,
            policy: CanonicalTombstoneConflictCanaryPolicy(
                canaryMaxObjectsPerSyncRun: 1,
                allowCandidateExecution: true
            ),
            token: token(),
            evidence: evidence(),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "sync-run-v811",
            executor: executor
        )
    }

    static func gate(
        candidates: [CanonicalTombstoneConflictCandidate]
    ) -> CanonicalTombstoneConflictCutoverGate {
        CanonicalTombstoneConflictCutoverRunner().evaluateGate(
            mode: .canary,
            policy: CanonicalTombstoneConflictCanaryPolicy(
                canaryMaxObjectsPerSyncRun: 1,
                allowCandidateExecution: true
            ),
            token: token(),
            evidence: evidence(),
            candidates: candidates,
            trigger: .periodic
        )
    }

    static func objectTombstoneCandidate(reason: String = CanonicalDeletionReason.peerTombstoneNewer.rawValue) -> CandidateBundle {
        let target = CanonicalApplyTarget(objectID: "recording-01")
        let tombstone = CanonicalTombstone(
            target: target,
            state: .tombstoned,
            reason: .peerTombstoneNewer,
            deletedAt: ts(3_000),
            sourceNodeID: "mac-01"
        )
        let action = CanonicalApplyAction(
            kind: .objectTombstoneApply,
            source: .peer,
            target: target,
            bridgeHint: .legacyMetadataManifestApply,
            preconditions: [
                CanonicalApplyPrecondition(kind: .tombstoneTimestamp, value: "3000"),
                CanonicalApplyPrecondition(kind: .noPhysicalDelete, value: "true")
            ],
            tombstoneID: tombstone.tombstoneID,
            reason: reason
        )
        return CandidateBundle(
            candidate: CanonicalTombstoneConflictCandidate(
                action: action,
                recordingTombstone: tombstone,
                rollbackCheckpointID: "tombstone-conflict-recording-01-object",
                tombstoneWinsIfNewerPolicy: true,
                rollbackEvidenceAvailable: true
            )
        )
    }

    static func libraryTombstoneCandidate() -> CandidateBundle {
        let objectID = CanonicalLibraryObjectID("folder:math")
        let tombstone = CanonicalLibraryTombstone(
            objectID: objectID,
            objectKind: .folder,
            deletedAt: ts(3_100),
            sourceNodeID: "mac-01",
            reason: .peerTombstoneNewer
        )
        let action = CanonicalApplyAction(
            kind: .libraryTombstoneApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: objectID.rawValue),
            bridgeHint: .legacyMetadataManifestApply,
            tombstoneID: tombstone.tombstoneID,
            reason: CanonicalLibraryTombstoneReason.peerTombstoneNewer.rawValue
        )
        return CandidateBundle(
            candidate: CanonicalTombstoneConflictCandidate(
                action: action,
                libraryTombstone: tombstone,
                rollbackCheckpointID: "tombstone-conflict-folder-math",
                tombstoneWinsIfNewerPolicy: true,
                rollbackEvidenceAvailable: true
            )
        )
    }

    static func generatedArtifactTombstoneCandidate() -> CandidateBundle {
        let target = CanonicalApplyTarget(objectID: "recording-01", artifactID: "noteMarkdown:recording-01", artifactKind: .noteMarkdown)
        let tombstone = CanonicalTombstone(
            target: target,
            state: .tombstoned,
            reason: .artifactTombstonePresent,
            deletedAt: ts(2_800),
            sourceNodeID: "mac-01"
        )
        let action = CanonicalApplyAction(
            kind: .artifactTombstoneApply,
            source: .planner,
            target: target,
            bridgeHint: .noPhysicalDelete,
            result: .deferredUnsupported,
            failureReason: .noPhysicalDeletePolicy,
            tombstoneID: tombstone.tombstoneID,
            reason: CanonicalDeletionReason.artifactTombstonePresent.rawValue
        )
        return CandidateBundle(
            candidate: CanonicalTombstoneConflictCandidate(
                action: action,
                recordingTombstone: tombstone,
                rollbackCheckpointID: "tombstone-conflict-artifact",
                tombstoneWinsIfNewerPolicy: true,
                rollbackEvidenceAvailable: true
            )
        )
    }

    static func conflictCandidate(conflictPolicyKnown: Bool = true) -> CandidateBundle {
        let target = CanonicalApplyTarget(objectID: "recording-01")
        let conflict = CanonicalConflictRecord(
            kind: .activeVsTombstone,
            target: target,
            resolutionPolicy: .tombstoneRequiresManualReview,
            localHash: CanonicalHash.sha256String("local"),
            peerHash: CanonicalHash.sha256String("peer"),
            detail: "activeVsTombstone"
        )
        let action = CanonicalApplyAction(
            kind: .conflictRecord,
            source: .planner,
            target: target,
            bridgeHint: .legacyFallbackPreserved,
            result: .conflictRecorded,
            failureReason: .conflictDetected,
            conflictID: conflict.conflictID,
            reason: conflict.kind.rawValue
        )
        return CandidateBundle(
            candidate: CanonicalTombstoneConflictCandidate(
                action: action,
                conflict: conflict,
                rollbackCheckpointID: "tombstone-conflict-recording-01-conflict",
                rollbackEvidenceAvailable: true,
                conflictPolicyKnown: conflictPolicyKnown
            )
        )
    }

    static func resurrectionCandidate() -> CandidateBundle {
        let action = CanonicalApplyAction(
            kind: .deferredUnsupported,
            source: .planner,
            target: CanonicalApplyTarget(objectID: "recording-01", artifactID: "noteJSON:recording-01", artifactKind: .noteJSON),
            bridgeHint: .noPhysicalDelete,
            result: .deferredUnsupported,
            failureReason: .tombstoneBlocksResurrection,
            reason: "tombstoneBlocksResurrection"
        )
        return CandidateBundle(
            candidate: CanonicalTombstoneConflictCandidate(
                action: action,
                rollbackCheckpointID: "tombstone-conflict-recording-01-resurrection",
                rollbackEvidenceAvailable: true,
                staleLiveMetadataRisk: true
            )
        )
    }

    static func emptyManifest(
        nodeID: String = "iphone-01",
        platform: String = "iPhone"
    ) -> CanonicalManifest {
        CanonicalManifest.make(
            node: node(nodeID, platform: platform),
            generatedAt: Date(timeIntervalSince1970: 4_000),
            objects: []
        )
    }

    static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    static func ts(_ seconds: TimeInterval) -> CanonicalTimestamp {
        CanonicalTimestamp(Date(timeIntervalSince1970: seconds))
    }

    actor FakeExecutor: CanonicalTombstoneConflictCutoverExecutor {
        private let failure: CanonicalTombstoneConflictFailure?
        private var commits: [String] = []
        private var rollbacks: [String] = []

        init(_ failure: CanonicalTombstoneConflictFailure? = nil) {
            self.failure = failure
        }

        var committedActionIDs: [String] { commits }
        var rolledBackActionIDs: [String] { rollbacks }

        func commitTombstoneConflict(
            _ candidate: CanonicalTombstoneConflictCandidate
        ) async -> CanonicalTombstoneConflictProductionCommitResult {
            if let failure {
                return .failure(candidate: candidate, kind: failure, partialCommit: failure == .postconditionMismatch, reason: "injected\(failure.rawValue)")
            }
            commits.append(candidate.action.actionID)
            let sideEffect = CanonicalProductionSideEffect(
                kind: candidate.domain.requiresConflictLedger ? .conflictRecord : .tombstoneMark,
                domain: candidate.domain.productionDomain,
                objectID: candidate.objectID,
                artifactID: candidate.action.target.artifactID,
                byteSize: Int64(candidate.markerBytes.count),
                hash: candidate.markerHash,
                summary: "fakeTombstoneConflictCommit"
            )
            return .success(candidate: candidate, sideEffects: [sideEffect])
        }

        func rollbackTombstoneConflict(
            _ candidate: CanonicalTombstoneConflictCandidate,
            reason: CanonicalTombstoneConflictFailure
        ) async -> CanonicalTombstoneConflictRollbackExecutionResult {
            rollbacks.append(candidate.action.actionID)
            return CanonicalTombstoneConflictRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: true,
                reason: "fakeRollback"
            )
        }
    }
}
