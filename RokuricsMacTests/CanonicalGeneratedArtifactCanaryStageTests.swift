//
//  CanonicalGeneratedArtifactCanaryStageTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalGeneratedArtifactCanaryStageTests {
    @Test func macStageCommitsThreeFakePeerCandidatesThroughSharedRunner() async {
        let candidates = Self.candidates(["recording-003", "recording-001", "recording-002", "recording-004"])
        let executor = V824MacGeneratedArtifactSequencedExecutor()

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(previousStage: .n1, successCount: 1),
            candidates: candidates,
            peerSnapshotAvailable: true,
            executor: executor
        )

        #expect(result.succeeded)
        #expect(result.selection.selectedCandidates.map(\.objectID) == ["recording-001", "recording-002", "recording-003"])
        #expect(result.stageObservationReport.executedCount == 3)
        #expect(result.stageObservationReport.nextStageEligible)
        #expect(result.stageObservationReport.recommendation == .advanceToN10)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactExpandedReadSideParallelEquivalent })
        #expect(await executor.committedObjectIDs == ["recording-001", "recording-002", "recording-003"])
    }

    @Test func macStageBlocksWhenPeerSnapshotUnavailable() async {
        let candidates = Self.candidates(["recording-001"])
        let executor = V824MacGeneratedArtifactSequencedExecutor()

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(previousStage: .n1, successCount: 1),
            candidates: candidates,
            peerSnapshotAvailable: false,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.gate.failures.contains(.peerSnapshotUnavailable))
        #expect(result.cutoverResult.canaryAttemptedCount == 0)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1MacPeerSnapshotUnavailable })
        #expect(result.stageObservationReport.legacyFallbackCount >= 1)
        #expect(await executor.committedObjectIDs.isEmpty)
    }

    @Test func macAllEligibleRequiresN10EvidenceAndSelectsAllCandidates() async {
        let blockedGate = CanonicalGeneratedArtifactCanaryStageGate(
            policy: Self.policy(.allEligible, allowAllEligible: true).stagePolicy,
            domain: .generatedArtifacts,
            token: GeneratedArtifactCutoverTestSupport.token(),
            cutoverEvidence: Self.evidence(previousStage: .n3, successCount: 3)
        )
        #expect(blockedGate.allowed == false)
        #expect(blockedGate.blockers.contains(.stageOrderViolation))

        let candidates = Self.candidates(["recording-004", "recording-001", "recording-003", "recording-002"])
        let executor = V824MacGeneratedArtifactSequencedExecutor()
        let result = await Self.run(
            policy: Self.policy(.allEligible, allowAllEligible: true),
            evidence: Self.evidence(previousStage: .n10, successCount: 10),
            candidates: candidates,
            peerSnapshotAvailable: true,
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

    @Test func macRollbackFailureIsFatalBlocker() async {
        let candidates = Self.candidates(["recording-001"])
        let executor = V824MacGeneratedArtifactSequencedExecutor(
            failingObjectIDs: ["recording-001"],
            rollbackSucceeds: false
        )

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(previousStage: .n1, successCount: 1),
            candidates: candidates,
            peerSnapshotAvailable: true,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.fatalBlocker)
        #expect(result.stageObservationReport.fatalBlockerCount == 1)
        #expect(result.stageObservationReport.recommendation == .stopForFatalBlocker)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
    }

    private static func run(
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        peerSnapshotAvailable: Bool,
        executor: any CanonicalGeneratedArtifactCutoverExecutor
    ) async -> CanonicalGeneratedArtifactCanaryStageResult {
        await CanonicalGeneratedArtifactCanaryStageRunner().run(
            policy: policy,
            token: GeneratedArtifactCutoverTestSupport.token(),
            evidence: evidence,
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "v824-generated-artifact-mac-stage",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: peerSnapshotAvailable,
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
        var evidence = GeneratedArtifactCutoverTestSupport.evidence()
        evidence.canaryStageEvidence = .passing(
            previousStage: previousStage,
            requestedStage: nextStage(after: previousStage),
            previousStageSuccessCount: successCount,
            observationWindowID: "\(previousStage.rawValue)-generated-artifact-observation"
        )
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

private actor V824MacGeneratedArtifactSequencedExecutor: CanonicalGeneratedArtifactCutoverExecutor {
    private let failingObjectIDs: Set<String>
    private let rollbackSucceeds: Bool
    private(set) var committedObjectIDs: [String] = []

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
                reason: "macV824InjectedFailure"
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
                    summary: "macV824GeneratedArtifactApply"
                )
            ]
        )
    }

    func rollbackGeneratedArtifact(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate,
        reason: CanonicalGeneratedArtifactCutoverFailure
    ) async -> CanonicalGeneratedArtifactRollbackExecutionResult {
        CanonicalGeneratedArtifactRollbackExecutionResult(
            checkpointID: candidate.effectiveRollbackCheckpointID,
            succeeded: rollbackSucceeds,
            fatal: !rollbackSucceeds,
            reason: rollbackSucceeds ? "macV824RollbackComplete" : "macV824RollbackFailed"
        )
    }
}
