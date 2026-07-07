//
//  CanonicalRecordingMetadataCutoverTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalRecordingMetadataCutoverTests {
    @Test func defaultDisabledBlocksProductionAndUsesLegacyFallback() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()

        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .disabled,
            executor: executor
        )

        #expect(result.gate.allowed == false)
        #expect(result.gate.failures.contains(.disabled))
        #expect(result.gate.failures.contains(.modeNotExecutable))
        #expect(executor.committedObjectIDs.isEmpty)
        #expect(result.legacyFallbackUsed)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
    }

    @Test func unsupportedDomainAndMissingTokenNeverExecuteCanonicalCommit() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: CanonicalSingleDomainCutoverConfiguration(domain: .recordingAudio, mode: .canary),
            token: nil,
            executor: executor
        )

        #expect(result.gate.failures.contains(.unsupportedDomain))
        #expect(result.gate.failures.contains(.missingToken))
        #expect(result.gate.failures.contains(.missingOwnerApproval))
        #expect(executor.committedObjectIDs.isEmpty)
    }

    @Test func guardRequiresShadowEquivalenceRollbackAndSafeTriggers() async {
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            evidence: CanonicalRecordingMetadataCutoverEvidence(legacyFallbackAvailable: true),
            trigger: .viewRefresh
        )

        #expect(result.gate.failures.contains(.missingRealDataShadowCopyEvidence))
        #expect(result.gate.failures.contains(.missingExecutionShadowEvidence))
        #expect(result.gate.failures.contains(.missingDryRunEquivalence))
        #expect(result.gate.failures.contains(.missingRollback))
        #expect(result.gate.failures.contains(.viewRefreshTriggerDenied))
    }

    @Test func retryDrainerAndUnresolvedConflictAreDenied() async {
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            candidates: [RecordingMetadataCutoverTestSupport.candidate(unresolvedConflict: true)],
            trigger: .retryDrainer
        )

        #expect(result.gate.failures.contains(.retryDrainerFreshMetadataDenied))
        #expect(result.gate.failures.contains(.unresolvedConflict))
        #expect(result.commits.isEmpty)
    }

    @Test func canaryWithZeroBudgetExecutesNoObjects() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 0),
            executor: executor
        )

        #expect(result.gate.allowed)
        #expect(result.canaryAttemptedCount == 0)
        #expect(result.commits.isEmpty)
        #expect(executor.committedObjectIDs.isEmpty)
        #expect(result.legacyFallbackUsed == false)
    }

    @Test func canaryN1RequiresExplicitInternalConfiguration() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1),
            executor: executor
        )

        #expect(result.gate.allowed == false)
        #expect(result.gate.failures.contains(.missingInternalCanaryConfiguration))
        #expect(result.commits.isEmpty)
        #expect(executor.committedObjectIDs.isEmpty)
        #expect(result.legacyFallbackUsed)
    }

    @Test func canaryBudgetAboveOneIsDeniedBeforeCommit() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 2, allowsV87CanaryN1InternalExecution: true),
            executor: executor
        )

        #expect(result.gate.allowed == false)
        #expect(result.gate.failures.contains(.canaryBudgetAboveOneDenied))
        #expect(result.commits.isEmpty)
        #expect(executor.committedObjectIDs.isEmpty)
    }

    @Test func canaryCommitsOnlyBudgetedObjectsAndSuppressesDuplicateLegacyAfterSuccess() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let first = RecordingMetadataCutoverTestSupport.candidate(id: "recording-01", title: "First")
        let second = RecordingMetadataCutoverTestSupport.candidate(id: "recording-02", title: "Second")

        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            candidates: [first, second],
            executor: executor
        )

        #expect(result.canaryAttemptedCount == 1)
        #expect(result.canarySucceeded)
        #expect(executor.committedObjectIDs == ["recording-01"])
        #expect(result.duplicateLegacySuppressedActionIDs == [first.action.actionID])
        #expect(result.retirementReadiness.retirementCandidate)
    }

    @Test func canaryFailureRollsBackUsesLegacyFallbackAndDoesNotSuppressDuplicate() async {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor(.preconditionMismatch)

        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            candidates: [
                RecordingMetadataCutoverTestSupport.candidate(id: "recording-01"),
                RecordingMetadataCutoverTestSupport.candidate(id: "recording-02")
            ],
            executor: executor
        )

        #expect(result.canarySucceeded == false)
        #expect(result.rollbackResults.count == 1)
        #expect(executor.rolledBackObjectIDs == ["recording-01"])
        #expect(result.legacyFallbackUsed)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(executor.committedObjectIDs.isEmpty)
    }

    @Test func rollbackFailureBecomesFatalAndBlocksRetirement() async {
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            executor: RecordingMetadataCutoverTestSupport.FakeExecutor(.rollbackFailure)
        )

        #expect(result.fatalBlocker)
        #expect(result.rollbackResults.first?.succeeded == false)
        #expect(result.retirementReadiness.blockers.contains(.rollbackFailed))
        #expect(result.retirementReadiness.retirementCandidate == false)
    }

    @Test func uiParallelProjectionIsDiagnosticsOnly() async throws {
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true)
        )
        let projection = try #require(result.uiProjection)

        #expect(projection.equivalent)
        #expect(projection.mutatedUI == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalUIProjectionParallelReadStarted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalUIProjectionParallelReadEquivalent })
    }

    @Test func stagedN3ExecutesOnlyAfterN1EvidenceAndSuppressesOnlySuccessfulDuplicates() async throws {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let candidates = (1...4).map { RecordingMetadataCutoverTestSupport.candidate(id: "recording-0\($0)") }
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .stagedCanary(stage: .n3),
            evidence: RecordingMetadataCutoverTestSupport.evidence(
                stageEvidence: .passing(
                    previousStage: .n1,
                    requestedStage: .n3,
                    previousStageSuccessCount: 1,
                    previousStageSuppressedLegacyDuplicateCount: 1,
                    observationWindowID: "n1-observation"
                )
            ),
            candidates: candidates,
            executor: executor
        )
        let stage = try #require(result.canaryStageResult)

        #expect(result.gate.allowed)
        #expect(result.canaryAttemptedCount == 3)
        #expect(result.canarySucceeded)
        #expect(executor.committedObjectIDs == ["recording-01", "recording-02", "recording-03"])
        #expect(result.duplicateLegacySuppressedActionIDs.count == 3)
        #expect(stage.requestedStage == .n3)
        #expect(stage.successCount == 3)
        #expect(stage.runtimeSwitch == false)
    }

    @Test func stagedN10BlocksAfterN3RollbackFailureEvidence() async throws {
        var stageEvidence = CanonicalRecordingMetadataCanaryStageEvidence.passing(
            previousStage: .n3,
            requestedStage: .n10,
            previousStageSuccessCount: 3,
            observationWindowID: "n3-observation"
        )
        stageEvidence.previousStageRollbackFailureCount = 1
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .stagedCanary(stage: .n10),
            evidence: RecordingMetadataCutoverTestSupport.evidence(stageEvidence: stageEvidence),
            candidates: [RecordingMetadataCutoverTestSupport.candidate()],
            executor: executor
        )
        let stage = try #require(result.canaryStageResult)

        #expect(result.gate.allowed == false)
        #expect(result.gate.failures.contains(.previousStageRollbackFailure))
        #expect(executor.committedObjectIDs.isEmpty)
        #expect(stage.gate.blockers.contains(.previousStageRollbackFailure))
        #expect(stage.observationReport.previousStageRollbackFailureCount == 1)
    }

    @Test func allEligibleExecutesAllEligibleOnlyAfterN10Evidence() async throws {
        let executor = RecordingMetadataCutoverTestSupport.FakeExecutor()
        let candidates = [
            RecordingMetadataCutoverTestSupport.candidate(id: "recording-03"),
            RecordingMetadataCutoverTestSupport.candidate(id: "recording-01"),
            RecordingMetadataCutoverTestSupport.candidate(id: "recording-02")
        ]
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .stagedCanary(stage: .allEligible),
            evidence: RecordingMetadataCutoverTestSupport.evidence(
                stageEvidence: .passing(
                    previousStage: .n10,
                    requestedStage: .allEligible,
                    previousStageSuccessCount: 10,
                    previousStageSuppressedLegacyDuplicateCount: 10,
                    observationWindowID: "n10-observation"
                )
            ),
            candidates: candidates,
            executor: executor
        )
        let stage = try #require(result.canaryStageResult)

        #expect(result.canaryAttemptedCount == 3)
        #expect(executor.committedObjectIDs == ["recording-01", "recording-02", "recording-03"])
        #expect(stage.requestedStage == .allEligible)
        #expect(stage.selectedCandidateCount == 3)
        #expect(stage.suppressedLegacyDuplicateCount == 3)
        #expect(stage.observationReport.previousStageSuccessCount == 10)
    }
}

enum RecordingMetadataCutoverTestSupport {
    final class FakeExecutor: CanonicalRecordingMetadataCutoverExecutor, @unchecked Sendable {
        enum FailureMode: Sendable {
            case none
            case preconditionMismatch
            case postconditionMismatch
            case transportFailureBeforeSend
            case applyFailureBeforeCommit
            case applyFailureAfterPartialCommit
            case rollbackFailure
        }

        private let failureMode: FailureMode
        private(set) var committedObjectIDs: [String] = []
        private(set) var rolledBackObjectIDs: [String] = []

        init(_ failureMode: FailureMode = .none) {
            self.failureMode = failureMode
        }

        func commitRecordingMetadata(
            _ candidate: CanonicalRecordingMetadataCutoverCandidate
        ) async -> CanonicalRecordingMetadataProductionCommitResult {
            switch failureMode {
            case .none:
                committedObjectIDs.append(candidate.objectID)
                return .success(candidate: candidate, sideEffect: sideEffect(for: candidate))
            case .preconditionMismatch:
                return .failure(candidate: candidate, kind: .preconditionMismatch, reason: "preconditionMismatch")
            case .postconditionMismatch:
                return .failure(candidate: candidate, kind: .postconditionMismatch, reason: "postconditionMismatch")
            case .transportFailureBeforeSend:
                return .failure(candidate: candidate, kind: .transportFailureBeforeSend, reason: "transportFailureBeforeSend")
            case .applyFailureBeforeCommit:
                return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "applyFailureBeforeCommit")
            case .applyFailureAfterPartialCommit:
                return .failure(candidate: candidate, kind: .applyFailureAfterPartialCommit, partialCommit: true, reason: "applyFailureAfterPartialCommit")
            case .rollbackFailure:
                return .failure(candidate: candidate, kind: .applyFailureAfterPartialCommit, partialCommit: true, reason: "rollbackFailureSetup")
            }
        }

        func rollbackRecordingMetadata(
            _ candidate: CanonicalRecordingMetadataCutoverCandidate,
            reason: CanonicalCutoverFailure
        ) async -> CanonicalRecordingMetadataRollbackExecutionResult {
            guard failureMode != .rollbackFailure else {
                return CanonicalRecordingMetadataRollbackExecutionResult(
                    checkpointID: candidate.effectiveRollbackCheckpointID,
                    succeeded: false,
                    fatal: true,
                    reason: "rollbackFailed"
                )
            }
            rolledBackObjectIDs.append(candidate.objectID)
            return CanonicalRecordingMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: true,
                reason: "rollbackCompleted",
                rollbackResult: CanonicalRollbackResult(
                    planID: "recording-metadata-rollback",
                    succeeded: true,
                    completedActionIDs: [candidate.effectiveRollbackCheckpointID]
                )
            )
        }

        private func sideEffect(for candidate: CanonicalRecordingMetadataCutoverCandidate) -> CanonicalProductionSideEffect {
            if candidate.requiresNetworkSend {
                return CanonicalProductionSideEffect(
                    kind: .networkRequest,
                    domain: .transportRuntime,
                    objectID: candidate.objectID,
                    route: .applyMetadata,
                    summary: "recordingMetadataSend"
                )
            }
            return CanonicalProductionSideEffect(
                kind: .metadataApply,
                domain: .apply,
                objectID: candidate.objectID,
                summary: "recordingMetadataApply"
            )
        }
    }

    static func run(
        configuration: CanonicalSingleDomainCutoverConfiguration,
        token: CanonicalCutoverToken? = token(),
        evidence: CanonicalRecordingMetadataCutoverEvidence = evidence(),
        candidates: [CanonicalRecordingMetadataCutoverCandidate] = [candidate()],
        trigger: CanonicalSyncPlanTrigger = .periodic,
        executor: FakeExecutor = FakeExecutor()
    ) async -> CanonicalCutoverResult {
        await CanonicalRecordingMetadataCutoverRunner().run(
            configuration: configuration,
            token: token,
            evidence: evidence,
            candidates: candidates,
            trigger: trigger,
            nodeRole: .testHarness,
            executor: executor
        )
    }

    static func token(ownerApproved: Bool = true) -> CanonicalCutoverToken {
        CanonicalCutoverToken(tokenID: "cutover-token-01", syncRunID: "sync-run-01", ownerApproved: ownerApproved)
    }

    static func evidence(
        legacyFallbackAvailable: Bool = true,
        uiEquivalent: Bool = true,
        stageEvidence: CanonicalRecordingMetadataCanaryStageEvidence? = nil
    ) -> CanonicalRecordingMetadataCutoverEvidence {
        var evidence = CanonicalRecordingMetadataCutoverEvidence.passing(rollbackPlan: rollbackPlan())
        evidence.legacyFallbackAvailable = legacyFallbackAvailable
        evidence.uiParallelReadEquivalent = uiEquivalent
        evidence.canaryStageEvidence = stageEvidence
        return evidence
    }

    static func rollbackPlan() -> CanonicalRollbackPlan {
        CanonicalRollbackPlan(
            planID: "recording-metadata-rollback-plan",
            checkpoints: [
                CanonicalRollbackCheckpoint(checkpointID: "recording-metadata-checkpoint", domain: .recordingMetadata, objectID: "recording-01")
            ],
            actions: [
                CanonicalRollbackAction(
                    actionID: "recording-metadata-rollback",
                    kind: .metadataRollback,
                    domain: .recordingMetadata,
                    checkpointID: "recording-metadata-checkpoint",
                    objectID: "recording-01"
                )
            ]
        )
    }

    static func candidate(
        id: String = "recording-01",
        title: String = "Peer",
        kind: CanonicalApplyActionKind = .recordingMetadataApply,
        unresolvedConflict: Bool = false
    ) -> CanonicalRecordingMetadataCutoverCandidate {
        let local = CanonicalProductionTestFixtures.recording(
            id: id,
            title: "Local",
            modifiedAt: CanonicalProductionTestFixtures.date(2_000)
        )
        let peer = CanonicalProductionTestFixtures.recording(
            id: id,
            title: title,
            modifiedAt: CanonicalProductionTestFixtures.date(2_100)
        )
        return CanonicalRecordingMetadataCutoverCandidate(
            action: CanonicalApplyAction(
                kind: kind,
                source: kind == .recordingMetadataSend ? .local : .peer,
                target: CanonicalApplyTarget(objectID: id),
                bridgeHint: kind == .recordingMetadataSend ? .legacyMetadataManifestSend : .legacyMetadataManifestApply,
                reason: kind.rawValue
            ),
            localObject: local,
            peerObject: peer,
            rollbackCheckpointID: "recording-metadata-checkpoint-\(id)",
            unresolvedConflict: unresolvedConflict
        )
    }
}
