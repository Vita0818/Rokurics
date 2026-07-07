//
//  CanonicalGeneratedArtifactCanaryStageTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalGeneratedArtifactCanaryStageTests {
    @Test func v824StagePolicyDefaultsDisabled() {
        let policy = CanonicalGeneratedArtifactCanaryPolicy()

        #expect(policy.stagePolicy.requestedStage == .disabled)
        #expect(policy.stagePolicy.allowCandidateExecution == false)
        #expect(policy.stagePolicy.runtimeSwitchEnabled == false)
        #expect(policy.allowAllEligible == false)
        #expect(policy.runtimeSwitchEnabled == false)
    }

    @Test func n3RequiresN1EvidenceAndSelectsThreeDeterministically() async {
        let candidates = Self.candidates(["recording-003", "recording-001", "recording-004", "recording-002"])
        let missingEvidence = GeneratedArtifactCutoverTestSupport.evidence()

        let blocked = await Self.run(policy: Self.policy(.n3), evidence: missingEvidence, candidates: candidates)

        #expect(blocked.succeeded == false)
        #expect(blocked.cutoverResult.gate.failures.contains(.missingCanaryStageEvidence))
        #expect(blocked.cutoverResult.commits.isEmpty)

        let executor = V824GeneratedArtifactSequencedExecutor()
        let allowed = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(previousStage: .n1, successCount: 1),
            candidates: candidates,
            executor: executor
        )

        #expect(allowed.succeeded)
        #expect(allowed.selection.selectedCandidates.map(\.objectID) == ["recording-001", "recording-002", "recording-003"])
        #expect(allowed.stageObservationReport.executedCount == 3)
        #expect(allowed.stageObservationReport.successCount == 3)
        #expect(allowed.stageObservationReport.nextStageEligible)
        #expect(allowed.stageObservationReport.recommendation == .advanceToN10)
        #expect(allowed.stageObservationReport.duplicateSuppressionCount == 3)
        #expect(allowed.stageObservationReport.readSideParallelEquivalentCount == 3)
        #expect(allowed.stageObservationReport.runtimeSwitch == false)
        #expect(allowed.stageObservationReport.domain == .generatedArtifacts)
        #expect(allowed.stageObservationReport.uiMutated == false)
        #expect(allowed.stageObservationReport.artifactUploadJobCreated == false)
        #expect(allowed.stageObservationReport.audioAutoDownloaded == false)
        #expect(allowed.stageObservationReport.diagnosticsSummary.contains("/") == false)
        #expect(await executor.committedObjectIDs == ["recording-001", "recording-002", "recording-003"])
    }

    @Test func n10AndAllEligibleRequireOrderedPreviousStageEvidence() async {
        let n10Blocked = CanonicalGeneratedArtifactCanaryStageGate(
            policy: Self.policy(.n10).stagePolicy,
            domain: .generatedArtifacts,
            token: GeneratedArtifactCutoverTestSupport.token(),
            cutoverEvidence: Self.evidence(previousStage: .n1, successCount: 1)
        )
        let n10Allowed = CanonicalGeneratedArtifactCanaryStageGate(
            policy: Self.policy(.n10).stagePolicy,
            domain: .generatedArtifacts,
            token: GeneratedArtifactCutoverTestSupport.token(),
            cutoverEvidence: Self.evidence(previousStage: .n3, successCount: 3)
        )
        let allEligibleBlocked = CanonicalGeneratedArtifactCanaryStageGate(
            policy: Self.policy(.allEligible, allowAllEligible: true).stagePolicy,
            domain: .generatedArtifacts,
            token: GeneratedArtifactCutoverTestSupport.token(),
            cutoverEvidence: Self.evidence(previousStage: .n3, successCount: 3)
        )
        let allEligibleAllowed = CanonicalGeneratedArtifactCanaryStageGate(
            policy: Self.policy(.allEligible, allowAllEligible: true).stagePolicy,
            domain: .generatedArtifacts,
            token: GeneratedArtifactCutoverTestSupport.token(),
            cutoverEvidence: Self.evidence(previousStage: .n10, successCount: 10)
        )

        #expect(n10Blocked.allowed == false)
        #expect(n10Blocked.blockers.contains(.stageOrderViolation))
        #expect(n10Allowed.allowed)
        #expect(allEligibleBlocked.allowed == false)
        #expect(allEligibleBlocked.blockers.contains(.stageOrderViolation))
        #expect(allEligibleAllowed.allowed)

        let candidates = Self.candidates(["recording-004", "recording-001", "recording-003", "recording-002"])
        let executor = V824GeneratedArtifactSequencedExecutor()
        let result = await Self.run(
            policy: Self.policy(.allEligible, allowAllEligible: true),
            evidence: Self.evidence(previousStage: .n10, successCount: 10),
            candidates: candidates,
            executor: executor
        )

        #expect(result.succeeded)
        #expect(result.selection.selectedCandidates.count == 4)
        #expect(result.stageObservationReport.stage == .allEligible)
        #expect(result.stageObservationReport.executedCount == 4)
        #expect(result.stageObservationReport.recommendation == .observeCurrentStage)
        #expect(result.stageObservationReport.nextStageEligible == false)
        #expect(await executor.committedObjectIDs == ["recording-001", "recording-002", "recording-003", "recording-004"])
    }

    @Test func stageEvidenceBlockersStopNextStage() {
        let blockedEvidence = CanonicalGeneratedArtifactCanaryStageEvidence(
            previousStage: .n1,
            requestedStage: .n3,
            previousStageSuccessCount: 1,
            previousStageFailureCount: 1,
            previousStageRollbackFailureCount: 1,
            previousStageBlockingDivergenceCount: 1,
            previousStageContentLeakRiskCount: 1,
            previousStageUnsafePathTokenCount: 1,
            previousStageParentTombstoneBlockCount: 1,
            previousStageAudioConfusionBlockCount: 1,
            previousStagePostconditionFailureCount: 1,
            previousStageUnsupportedArtifactCount: 1,
            previousStageHashUnavailableCount: 1,
            previousStageByteSizeUnavailableCount: 1,
            unresolvedConflictCount: 1,
            dryRunEquivalenceStatus: .passed,
            executionShadowStatus: .passed,
            realDataShadowCopyStatus: .passed,
            readOnlyTransportProbeStatus: .passed,
            noCommitEvidenceStatus: .passed,
            rollbackPlanStatus: .passed,
            productionApplyPortStatus: .passed,
            artifactRequestRouteEvidenceStatus: .passed,
            legacyFallbackStatus: .passed,
            readSideParallelStatus: .passed,
            observationWindow: CanonicalGeneratedArtifactStageObservationWindow(observationWindowID: "blocked-stage", complete: false),
            ownerApproved: true
        )
        let gate = CanonicalGeneratedArtifactCanaryStageGate(
            policy: Self.policy(.n3).stagePolicy,
            domain: .generatedArtifacts,
            token: GeneratedArtifactCutoverTestSupport.token(),
            cutoverEvidence: Self.evidence(stageEvidence: blockedEvidence)
        )

        #expect(gate.allowed == false)
        #expect(gate.blockers.contains(.observationWindowIncomplete))
        #expect(gate.blockers.contains(.previousStageFailure))
        #expect(gate.blockers.contains(.previousStageRollbackFailure))
        #expect(gate.blockers.contains(.previousStageBlockingDivergence))
        #expect(gate.blockers.contains(.previousStageUnresolvedConflict))
        #expect(gate.blockers.contains(.previousStagePostconditionFailure))
        #expect(gate.blockers.contains(.previousStageUnsupportedArtifact))
        #expect(gate.blockers.contains(.previousStageContentLeakRisk))
        #expect(gate.blockers.contains(.previousStageUnsafePathToken))
        #expect(gate.blockers.contains(.previousStageParentTombstone))
        #expect(gate.blockers.contains(.previousStageAudioConfusion))
        #expect(gate.blockers.contains(.previousStageHashUnavailable))
        #expect(gate.blockers.contains(.previousStageByteSizeUnavailable))
    }

    @Test func firstFailureStopsLaterCandidatesAndPreservesSuccessfulSuppression() async {
        let candidates = Self.candidates(["recording-003", "recording-001", "recording-002"])
        let executor = V824GeneratedArtifactSequencedExecutor(failingObjectIDs: ["recording-002"])

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(previousStage: .n1, successCount: 1),
            candidates: candidates,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(await executor.committedObjectIDs == ["recording-001", "recording-002"])
        #expect(await executor.rolledBackObjectIDs == ["recording-002"])
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs == [candidates.first { $0.objectID == "recording-001" }?.action.actionID].compactMap { $0 })
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.stageObservationReport.successCount == 1)
        #expect(result.stageObservationReport.failureCount == 1)
        #expect(result.stageObservationReport.nextStageEligible == false)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactCanaryStoppedAfterFailure })
    }

    @Test func rollbackFailureIsFatalBlocker() async {
        let candidates = Self.candidates(["recording-001"])
        let executor = V824GeneratedArtifactSequencedExecutor(
            failingObjectIDs: ["recording-001"],
            rollbackSucceeds: false
        )

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(previousStage: .n1, successCount: 1),
            candidates: candidates,
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
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        executor: any CanonicalGeneratedArtifactCutoverExecutor = V824GeneratedArtifactSequencedExecutor()
    ) async -> CanonicalGeneratedArtifactCanaryStageResult {
        await CanonicalGeneratedArtifactCanaryStageRunner().run(
            policy: policy,
            token: GeneratedArtifactCutoverTestSupport.token(),
            evidence: evidence,
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v824-generated-artifact-stage",
            peerNode: GeneratedArtifactCutoverTestSupport.macNode(),
            executor: executor
        )
    }

    private static func policy(
        _ stage: CanonicalGeneratedArtifactCanaryStage,
        allowAllEligible: Bool = false
    ) -> CanonicalGeneratedArtifactCanaryPolicy {
        CanonicalGeneratedArtifactCanaryPolicy(
            stagePolicy: CanonicalGeneratedArtifactCanaryStagePolicy(
                requestedStage: stage,
                allowCandidateExecution: true
            ),
            explicitInternalTestConfiguration: true,
            allowAllEligible: allowAllEligible
        )
    }

    private static func evidence(
        previousStage: CanonicalGeneratedArtifactCanaryStage,
        successCount: Int
    ) -> CanonicalGeneratedArtifactCutoverEvidence {
        Self.evidence(
            stageEvidence: .passing(
                previousStage: previousStage,
                requestedStage: nextStage(after: previousStage),
                previousStageSuccessCount: successCount,
                observationWindowID: "\(previousStage.rawValue)-generated-artifact-observation"
            )
        )
    }

    private static func evidence(
        stageEvidence: CanonicalGeneratedArtifactCanaryStageEvidence?
    ) -> CanonicalGeneratedArtifactCutoverEvidence {
        var evidence = GeneratedArtifactCutoverTestSupport.evidence()
        evidence.canaryStageEvidence = stageEvidence
        return evidence
    }

    private static func candidates(_ objectIDs: [String]) -> [CanonicalGeneratedArtifactCutoverCandidate] {
        objectIDs.map { GeneratedArtifactCutoverTestSupport.candidate(objectID: $0, kind: .summaryJSON).candidate }
    }

    private static func nextStage(after previousStage: CanonicalGeneratedArtifactCanaryStage) -> CanonicalGeneratedArtifactCanaryStage {
        switch previousStage {
        case .n1:
            return .n3
        case .n3:
            return .n10
        case .n10:
            return .allEligible
        case .disabled, .allEligible:
            return .disabled
        }
    }
}

private actor V824GeneratedArtifactSequencedExecutor: CanonicalGeneratedArtifactCutoverExecutor {
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

    func commitGeneratedArtifact(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate
    ) async -> CanonicalGeneratedArtifactProductionCommitResult {
        committedObjectIDs.append(candidate.objectID)
        if failingObjectIDs.contains(candidate.objectID) {
            return .failure(
                candidate: candidate,
                kind: .postconditionMismatch,
                partialCommit: true,
                reason: "v824InjectedFailure"
            )
        }
        return .success(
            candidate: candidate,
            sideEffects: [
                CanonicalProductionSideEffect(
                    kind: .generatedArtifactApply,
                    domain: .generatedArtifacts,
                    objectID: candidate.objectID,
                    artifactID: candidate.artifactID,
                    byteSize: candidate.expectedByteSize,
                    hash: candidate.expectedContentHash,
                    summary: "v824GeneratedArtifactApply"
                )
            ]
        )
    }

    func rollbackGeneratedArtifact(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate,
        reason: CanonicalGeneratedArtifactCutoverFailure
    ) async -> CanonicalGeneratedArtifactRollbackExecutionResult {
        rolledBackObjectIDs.append(candidate.objectID)
        return CanonicalGeneratedArtifactRollbackExecutionResult(
            checkpointID: candidate.effectiveRollbackCheckpointID,
            succeeded: rollbackSucceeds,
            fatal: !rollbackSucceeds,
            reason: rollbackSucceeds ? "v824RollbackComplete" : "v824RollbackFailed"
        )
    }
}
