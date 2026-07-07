//
//  CanonicalLibraryMetadataCanaryStageTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLibraryMetadataCanaryStageTests {
    @Test func v816StagePolicyDefaultsOff() {
        let policy = CanonicalLibraryMetadataCanaryPolicy()
        let configuration = CanonicalLibraryMetadataCanaryConfiguration()

        #expect(policy.stagePolicy.requestedStage == .disabled)
        #expect(policy.stagePolicy.allowCandidateExecution == false)
        #expect(policy.stagePolicy.runtimeSwitchEnabled == false)
        #expect(configuration.mode == .disabled)
        #expect(configuration.allowAllEligible == false)
        #expect(configuration.runtimeSwitchEnabled == false)
    }

    @Test func n3RequiresN1EvidenceAndSelectsThreeDeterministically() async {
        let policy = Self.policy(.n3)
        let missingEvidence = LibraryMetadataCutoverTestSupport.evidence()
        let candidates = Self.folderCandidates(["folder:003", "folder:001", "folder:004", "folder:002", "folder:005"])

        let blocked = await Self.run(policy: policy, evidence: missingEvidence, candidates: candidates)

        #expect(blocked.succeeded == false)
        #expect(blocked.cutoverResult.gate.failures.contains(.missingCanaryStageEvidence))
        #expect(blocked.cutoverResult.commits.isEmpty)

        let executor = V816LibraryMetadataSequencedExecutor()
        let allowed = await Self.run(
            policy: policy,
            evidence: Self.evidence(stage: .n1, successCount: 1),
            candidates: candidates,
            executor: executor
        )

        #expect(allowed.succeeded)
        #expect(allowed.selection.selectedCandidates.map(\.objectID) == ["folder:001", "folder:002", "folder:003"])
        #expect(allowed.stageObservationReport.executedCount == 3)
        #expect(allowed.stageObservationReport.successCount == 3)
        #expect(allowed.stageObservationReport.nextStageEligible)
        #expect(allowed.stageObservationReport.recommendation == .advanceToN10)
        #expect(allowed.stageObservationReport.duplicateSuppressionCount == 3)
        #expect(allowed.stageObservationReport.readSideParallelEquivalentCount == 3)
        #expect(allowed.stageObservationReport.runtimeSwitchEnabled == false)
        #expect(allowed.stageObservationReport.domain == .libraryMetadata)
        #expect(allowed.stageObservationReport.uiMutated == false)
        #expect(allowed.stageObservationReport.resourceMoved == false)
        #expect(allowed.stageObservationReport.uploadJobCreated == false)
        #expect(allowed.stageObservationReport.diagnosticsSummary.contains("/") == false)
        #expect(await executor.committedObjectIDs == ["folder:001", "folder:002", "folder:003"])
    }

    @Test func n10AndAllEligibleRequireOrderedPreviousStageEvidence() {
        let n10Policy = Self.policy(.n10)
        let n10Blocked = CanonicalLibraryMetadataCanaryStageGate(
            policy: n10Policy.stagePolicy,
            evidence: Self.evidence(stage: .n1, successCount: 1)
        )
        let n10Allowed = CanonicalLibraryMetadataCanaryStageGate(
            policy: n10Policy.stagePolicy,
            evidence: Self.evidence(stage: .n3, successCount: 3)
        )
        let allEligiblePolicy = Self.policy(.allEligible, allowAllEligible: true)
        let allEligibleBlocked = CanonicalLibraryMetadataCanaryStageGate(
            policy: allEligiblePolicy.stagePolicy,
            evidence: Self.evidence(stage: .n3, successCount: 3)
        )
        let allEligibleAllowed = CanonicalLibraryMetadataCanaryStageGate(
            policy: allEligiblePolicy.stagePolicy,
            evidence: Self.evidence(stage: .n10, successCount: 10)
        )

        #expect(n10Blocked.allowed == false)
        #expect(n10Blocked.failures.contains(.canaryStageOrderViolation))
        #expect(n10Allowed.allowed)
        #expect(allEligibleBlocked.allowed == false)
        #expect(allEligibleBlocked.failures.contains(.canaryStageOrderViolation))
        #expect(allEligibleAllowed.allowed)
    }

    @Test func stageEvidenceBlockersStopNextStage() {
        let policy = Self.policy(.n3).stagePolicy
        let blockedEvidence = CanonicalLibraryMetadataCanaryStageEvidence(
            stage: .n1,
            previousStage: .disabled,
            status: .passed,
            successfulCommitCount: 1,
            failedCommitCount: 1,
            rollbackFailureCount: 1,
            blockingDivergenceCount: 1,
            unresolvedConflictCount: 1,
            postconditionFailureCount: 1,
            unsupportedObjectCount: 1,
            resourceMoveAttemptCount: 1,
            folderCycleCount: 1,
            objectIDInstabilityCount: 1,
            readSideParallelDivergenceCount: 1,
            noCommitEvidenceAvailable: true,
            observationWindowComplete: false
        )
        let gate = CanonicalLibraryMetadataCanaryStageGate(
            policy: policy,
            evidence: LibraryMetadataCutoverTestSupport.evidence(stageEvidence: blockedEvidence)
        )

        #expect(gate.allowed == false)
        #expect(gate.failures.contains(.observationWindowIncomplete))
        #expect(gate.failures.contains(.previousStageFailure))
        #expect(gate.failures.contains(.previousStageRollbackFailure))
        #expect(gate.failures.contains(.previousStageBlockingDivergence))
        #expect(gate.failures.contains(.previousStageUnresolvedConflict))
        #expect(gate.failures.contains(.previousStagePostconditionFailure))
        #expect(gate.failures.contains(.previousStageUnsupportedObject))
        #expect(gate.failures.contains(.resourceMoveAttempted))
        #expect(gate.failures.contains(.cycleDetected))
        #expect(gate.failures.contains(.objectIDInstability))
        #expect(gate.failures.contains(.readSideParallelDivergence))
    }

    @Test func firstFailureStopsLaterCandidatesAndPreservesSuccessfulSuppression() async {
        let candidates = Self.folderCandidates(["folder:003", "folder:001", "folder:002"])
        let executor = V816LibraryMetadataSequencedExecutor(failingObjectIDs: ["folder:002"])

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(stage: .n1, successCount: 1),
            candidates: candidates,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(await executor.committedObjectIDs == ["folder:001", "folder:002"])
        #expect(await executor.rolledBackObjectIDs == ["folder:002"])
        #expect(result.cutoverResult.commits.map(\.objectID) == ["folder:001", "folder:002"])
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs == [candidates.first { $0.objectID == "folder:001" }?.action.actionID].compactMap { $0 })
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.stageObservationReport.successCount == 1)
        #expect(result.stageObservationReport.failureCount == 1)
        #expect(result.stageObservationReport.nextStageEligible == false)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataCanaryStageStoppedAfterFailure })
    }

    @Test func rollbackFailureIsFatalBlocker() async {
        let candidate = Self.folderCandidates(["folder:001"])
        let executor = V816LibraryMetadataSequencedExecutor(
            failingObjectIDs: ["folder:001"],
            rollbackSucceeds: false
        )

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(stage: .n1, successCount: 1),
            candidates: candidate,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.fatalBlocker)
        #expect(result.cutoverResult.rollbackResults.first?.succeeded == false)
        #expect(result.stageObservationReport.fatalBlockerCount == 1)
        #expect(result.stageObservationReport.recommendation == .stopForFatalBlocker)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
    }

    private static func run(
        policy: CanonicalLibraryMetadataCanaryPolicy,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        executor: any CanonicalLibraryMetadataCutoverExecutor = V816LibraryMetadataSequencedExecutor()
    ) async -> CanonicalLibraryMetadataCanaryStageResult {
        await CanonicalLibraryMetadataCanaryStageRunner().run(
            policy: policy,
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: evidence,
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v816-library-metadata-stage",
            executor: executor
        )
    }

    private static func policy(
        _ stage: CanonicalLibraryMetadataCanaryStage,
        allowAllEligible: Bool = false
    ) -> CanonicalLibraryMetadataCanaryPolicy {
        CanonicalLibraryMetadataCanaryPolicy(
            stagePolicy: CanonicalLibraryMetadataCanaryStagePolicy(
                requestedStage: stage,
                allowCandidateExecution: true
            ),
            explicitInternalTestConfiguration: true,
            allowAllEligible: allowAllEligible
        )
    }

    private static func evidence(
        stage: CanonicalLibraryMetadataCanaryStage,
        successCount: Int
    ) -> CanonicalLibraryMetadataCutoverEvidence {
        LibraryMetadataCutoverTestSupport.evidence(
            stageEvidence: .passing(stage: stage, successfulCommitCount: successCount)
        )
    }

    private static func folderCandidates(_ objectIDs: [String]) -> [CanonicalLibraryMetadataCutoverCandidate] {
        objectIDs.map { objectID in
            CanonicalLibraryMetadataCutoverCandidate(
                action: CanonicalApplyAction(
                    kind: .folderMetadataApply,
                    source: .peer,
                    target: CanonicalApplyTarget(objectID: objectID),
                    bridgeHint: .legacyMetadataManifestApply,
                    reason: "v816StageTest"
                ),
                localObject: LibraryMetadataCutoverTestSupport.folderObject(
                    objectID: objectID,
                    name: "Local \(objectID)",
                    modifiedAt: 2_000
                ),
                peerObject: LibraryMetadataCutoverTestSupport.folderObject(
                    objectID: objectID,
                    name: "Peer \(objectID)",
                    modifiedAt: 3_000
                ),
                rollbackCheckpointID: "checkpoint-\(objectID)"
            )
        }
    }
}

private actor V816LibraryMetadataSequencedExecutor: CanonicalLibraryMetadataCutoverExecutor {
    private let failingObjectIDs: Set<String>
    private let rollbackSucceeds: Bool
    private(set) var committedObjectIDs: [String] = []
    private(set) var rolledBackObjectIDs: [String] = []

    init(
        failingObjectIDs: Set<String> = [],
        rollbackSucceeds: Bool = true
    ) {
        self.failingObjectIDs = failingObjectIDs
        self.rollbackSucceeds = rollbackSucceeds
    }

    func commitLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate
    ) async -> CanonicalLibraryMetadataProductionCommitResult {
        committedObjectIDs.append(candidate.objectID)
        if failingObjectIDs.contains(candidate.objectID) {
            return .failure(
                candidate: candidate,
                kind: .postconditionMismatch,
                partialCommit: true,
                reason: "v816InjectedFailure"
            )
        }
        return .success(
            candidate: candidate,
            payloadByteCount: 64,
            sideEffects: [
                CanonicalProductionSideEffect(
                    kind: .metadataApply,
                    domain: candidate.domain.productionDomain,
                    objectID: candidate.objectID,
                    byteSize: 64,
                    hash: candidate.expectedMetadataHash,
                    summary: "v816LibraryMetadataApply"
                )
            ]
        )
    }

    func rollbackLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate,
        reason: CanonicalLibraryMetadataCutoverFailure
    ) async -> CanonicalLibraryMetadataRollbackExecutionResult {
        rolledBackObjectIDs.append(candidate.objectID)
        return CanonicalLibraryMetadataRollbackExecutionResult(
            checkpointID: candidate.effectiveRollbackCheckpointID,
            succeeded: rollbackSucceeds,
            fatal: !rollbackSucceeds,
            reason: rollbackSucceeds ? "v816RollbackComplete" : "v816RollbackFailed"
        )
    }
}
