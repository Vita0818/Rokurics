//
//  CanonicalRecordingMetadataCommitExecutorTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalRecordingMetadataCommitExecutorTests {
    @Test func defaultExecutorBlocksProductionCommitWithoutInternalFakePort() async {
        let executor = MacRecordingMetadataCutoverExecutor()
        let candidate = RecordingMetadataCutoverTestSupport.candidate()

        let commit = await executor.commitRecordingMetadata(candidate)
        let rollback = await executor.rollbackRecordingMetadata(candidate, reason: .applyFailureBeforeCommit)

        #expect(commit.committed == false)
        #expect(commit.failureKind == .applyFailureBeforeCommit)
        #expect(commit.reason.contains("InternalFakeApplyPort"))
        #expect(rollback.succeeded)
        #expect(rollback.rollbackResult?.completedActionIDs.isEmpty == false)
    }

    @Test func applyCommitUsesApplyPortAndRecordsSafeMetadataSideEffect() async throws {
        let apply = CommitTrackingApplyPort()
        let executor = MacRecordingMetadataCutoverExecutor(applyPort: apply)

        let commit = await executor.commitRecordingMetadata(RecordingMetadataCutoverTestSupport.candidate())

        #expect(commit.committed)
        #expect(commit.preconditionVerified)
        #expect(commit.postconditionVerified)
        #expect(commit.sideEffects.map(\.kind) == [.metadataApply])
        #expect(commit.sideEffects.allSatisfy { $0.kind != .uploadSessionStart && $0.kind != .generatedArtifactApply })
        #expect(await apply.applyCount == 1)
        #expect(await apply.sendCount == 0)
    }

    @Test func sendCommitUsesApplyMetadataRouteProjectionAndSendMetadataPort() async throws {
        let apply = CommitTrackingApplyPort()
        let recorder = RouteRecorder()
        let transport = MacCanonicalProductionTransportPort { request in
            await recorder.record(route: request.buildRequest.existingRoutePath, bodyCount: request.buildRequest.body.count)
            return CanonicalTransportResponse(ok: true, status: "ok", body: Data("{}".utf8))
        }
        let executor = MacRecordingMetadataCutoverExecutor(applyPort: apply, transportPort: transport)

        let commit = await executor.commitRecordingMetadata(Self.sendCandidate())

        #expect(commit.committed)
        #expect(commit.routePath == "/sync/apply-metadata")
        #expect(commit.sideEffects.contains { $0.kind == .networkRequest && $0.route == .applyMetadata })
        #expect(await recorder.routes == ["/sync/apply-metadata"])
        #expect(await recorder.bodyCounts.allSatisfy { $0 > 0 })
        #expect(await apply.sendCount == 1)
        #expect(await apply.applyCount == 0)
    }

    @Test func runnerCanaryZeroExecutesNothingAndPreservesLegacyFallback() async {
        let apply = CommitTrackingApplyPort()
        let executor = MacRecordingMetadataCutoverExecutor(applyPort: apply)

        let result = await Self.run(configuration: .canary(maxObjects: 0), executor: executor)

        #expect(result.canaryAttemptedCount == 0)
        #expect(result.commits.isEmpty)
        #expect(await apply.applyCount == 0)
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataCanaryBudgetExhausted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataLegacyFallbackPreserved })
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataDuplicateSuppressionSkipped })
    }

    @Test func postconditionFailureTriggersRollbackAndDoesNotSuppressDuplicateLegacy() async {
        let apply = CommitTrackingApplyPort(rejectPostcondition: true)
        let executor = MacRecordingMetadataCutoverExecutor(applyPort: apply)

        let result = await Self.run(configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true), executor: executor)

        #expect(result.commits.first?.failureKind == .postconditionMismatch)
        #expect(result.rollbackResults.first?.succeeded == true)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.legacyFallbackUsed)
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataPostconditionFailed })
        #expect(result.diagnostics.contains { $0.kind == .canonicalRecordingMetadataDuplicateSuppressionSkipped })
        #expect(await apply.rollbackCount == 1)
    }

    @Test func partialCommitFailureRollsBackAndRollbackFailureIsFatal() async {
        let rollbackOK = MacRecordingMetadataCutoverExecutor(
            applyPort: CommitTrackingApplyPort(),
            failureInjection: .applyFailureAfterPartialCommit
        )
        let rolledBack = await Self.run(configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true), executor: rollbackOK)
        #expect(rolledBack.rollbackResults.first?.succeeded == true)
        #expect(rolledBack.fatalBlocker == false)

        let rollbackFails = MacRecordingMetadataCutoverExecutor(
            applyPort: CommitTrackingApplyPort(),
            failureInjection: .rollbackFailure
        )
        let fatal = await Self.run(configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true), executor: rollbackFails)
        #expect(fatal.fatalBlocker)
        #expect(fatal.rollbackResults.first?.fatal == true)
        #expect(fatal.diagnostics.contains { $0.kind == .canonicalRecordingMetadataRollbackFatalBlocker })
    }

    @Test func preconditionMismatchAndTransportFailureBlockCommitBeforeSuppression() async {
        let preconditionExecutor = MacRecordingMetadataCutoverExecutor(
            applyPort: CommitTrackingApplyPort(),
            failureInjection: .preconditionMismatch
        )
        let precondition = await Self.run(configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true), executor: preconditionExecutor)
        #expect(precondition.commits.first?.failureKind == .preconditionMismatch)
        #expect(precondition.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(precondition.diagnostics.contains { $0.kind == .canonicalRecordingMetadataCommitPreconditionFailed })

        let transportExecutor = MacRecordingMetadataCutoverExecutor(
            applyPort: CommitTrackingApplyPort(),
            transportPort: MacCanonicalProductionTransportPort { _ in CanonicalTransportResponse(ok: true, status: "ok") },
            failureInjection: .transportFailureBeforeSend
        )
        let transport = await Self.run(configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true), candidates: [Self.sendCandidate()], executor: transportExecutor)
        #expect(transport.commits.first?.failureKind == .transportFailureBeforeSend)
        #expect(transport.duplicateLegacySuppressedActionIDs.isEmpty)

        let apply = CommitTrackingApplyPort()
        let applyBeforeExecutor = MacRecordingMetadataCutoverExecutor(
            applyPort: apply,
            failureInjection: .applyFailureBeforeCommit
        )
        let applyBefore = await Self.run(configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true), executor: applyBeforeExecutor)
        #expect(applyBefore.commits.first?.failureKind == .applyFailureBeforeCommit)
        #expect(applyBefore.rollbackResults.first?.succeeded == true)
        #expect(applyBefore.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(await apply.applyCount == 0)
        #expect(await apply.rollbackCount == 0)
    }

    @Test func idempotentRetryOfSameCommitDoesNotReapplyAndSuccessAllowsDuplicateSuppression() async {
        let apply = CommitTrackingApplyPort()
        let executor = MacRecordingMetadataCutoverExecutor(applyPort: apply)
        let candidate = RecordingMetadataCutoverTestSupport.candidate()

        let first = await executor.commitRecordingMetadata(candidate)
        let second = await executor.commitRecordingMetadata(candidate)
        let runnerResult = await Self.run(configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true), candidates: [candidate], executor: executor)

        #expect(first.committed)
        #expect(second.committed)
        #expect(second.reason == "idempotentRecordingMetadataCommit")
        #expect(await apply.applyCount == 1)
        #expect(runnerResult.duplicateLegacySuppressedActionIDs == [candidate.action.actionID])
        #expect(runnerResult.diagnostics.contains { $0.kind == .canonicalRecordingMetadataDuplicateSuppressionAllowed })
    }

    @Test func nonRecordingMetadataCandidateAndUnexpectedSideEffectsAreBlocked() async {
        let generated = await Self.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            candidates: [RecordingMetadataCutoverTestSupport.candidate(kind: .generatedArtifactDownloadApply)],
            executor: MacRecordingMetadataCutoverExecutor(applyPort: CommitTrackingApplyPort())
        )
        #expect(generated.gate.failures.contains(.unsupportedAction))
        #expect(generated.commits.isEmpty)

        let unexpectedSideEffect = await Self.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            executor: MacRecordingMetadataCutoverExecutor(applyPort: CommitTrackingApplyPort(unexpectedSideEffect: true))
        )
        #expect(unexpectedSideEffect.commits.first?.failureKind == .postconditionMismatch)
        #expect(unexpectedSideEffect.commits.first?.sideEffects.contains { $0.kind == .uploadSessionStart } == true)
        #expect(unexpectedSideEffect.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(unexpectedSideEffect.rollbackResults.first?.succeeded == true)
    }

    @Test func fakeInMemoryPortRollsBackPartialMutationAndLeavesUnrelatedObjectsUntouched() async {
        let apply = MacCanonicalProductionApplyPort(fakeInMemory: true)
        let stable = Self.applyCandidate(id: "recording-stable", title: "Stable", reason: "stable")
        let partial = Self.applyCandidate(id: "recording-partial", title: "Partial", reason: "partial")
        let stableCommit = await MacRecordingMetadataCutoverExecutor(applyPort: apply).commitRecordingMetadata(stable)
        let partialExecutor = MacRecordingMetadataCutoverExecutor(
            applyPort: apply,
            failureInjection: .applyFailureAfterPartialCommit
        )

        let result = await Self.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            candidates: [partial],
            executor: partialExecutor
        )

        #expect(stableCommit.committed)
        #expect(result.commits.first?.partialCommit == true)
        #expect(result.rollbackResults.first?.succeeded == true)
        #expect(await apply.fakeCommittedActionIDs(for: "recording-stable") == [stable.action.actionID])
        #expect(await apply.fakeCommittedActionIDs(for: "recording-partial").isEmpty)
        #expect(await apply.fakeTombstoneCount() == 0)
        #expect(await apply.fakeConflictCount() == 0)
    }

    @Test func duplicateObjectDifferentActionIDIsNotSkippedAndFailureReplayIsNotSuccess() async {
        let apply = CommitTrackingApplyPort()
        let executor = MacRecordingMetadataCutoverExecutor(applyPort: apply)
        let first = Self.applyCandidate(id: "recording-duplicate", title: "First", reason: "firstAction")
        let second = Self.applyCandidate(id: "recording-duplicate", title: "Second", reason: "secondAction")

        let firstCommit = await executor.commitRecordingMetadata(first)
        let secondCommit = await executor.commitRecordingMetadata(second)

        #expect(first.action.actionID != second.action.actionID)
        #expect(firstCommit.committed)
        #expect(secondCommit.committed)
        #expect(await apply.applyCount == 2)

        let failing = MacRecordingMetadataCutoverExecutor(
            applyPort: CommitTrackingApplyPort(),
            failureInjection: .preconditionMismatch
        )
        let failedFirst = await failing.commitRecordingMetadata(first)
        let failedReplay = await failing.commitRecordingMetadata(first)

        #expect(failedFirst.committed == false)
        #expect(failedReplay.committed == false)
        #expect(failedReplay.failureKind == .preconditionMismatch)
    }

    @Test func acceptedTransportMissingCheckpointAndForbiddenSideEffectsRollbackSafely() async {
        let transportAccepted = MacRecordingMetadataCutoverExecutor(
            applyPort: CommitTrackingApplyPort(),
            transportPort: MacCanonicalProductionTransportPort { _ in CanonicalTransportResponse(ok: true, status: "ok") },
            failureInjection: .transportFailureAfterAcceptedResponse
        )
        let acceptedResult = await Self.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            candidates: [Self.sendCandidate()],
            executor: transportAccepted
        )
        #expect(acceptedResult.commits.first?.failureKind == .applyFailureAfterPartialCommit)
        #expect(acceptedResult.rollbackResults.first?.succeeded == true)
        #expect(acceptedResult.duplicateLegacySuppressedActionIDs.isEmpty)

        let missingCheckpoint = await Self.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            executor: MacRecordingMetadataCutoverExecutor(
                applyPort: CommitTrackingApplyPort(),
                failureInjection: .missingRollbackCheckpoint
            )
        )
        #expect(missingCheckpoint.fatalBlocker)
        #expect(missingCheckpoint.rollbackResults.first?.fatal == true)
        #expect(missingCheckpoint.rollbackResults.first?.reason.contains("CheckpointMissing") == true)

        let forbiddenSideEffect = await Self.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            executor: MacRecordingMetadataCutoverExecutor(
                applyPort: MacCanonicalProductionApplyPort(fakeInMemory: true, failureInjection: .unsupportedSideEffect)
            )
        )
        #expect(forbiddenSideEffect.commits.first?.failureKind == .postconditionMismatch)
        #expect(forbiddenSideEffect.commits.first?.sideEffects.contains { $0.kind == .generatedArtifactApply } == true)
        #expect(forbiddenSideEffect.rollbackResults.first?.succeeded == true)
        #expect(forbiddenSideEffect.duplicateLegacySuppressedActionIDs.isEmpty)
    }

    private static func run(
        configuration: CanonicalSingleDomainCutoverConfiguration,
        candidates: [CanonicalRecordingMetadataCutoverCandidate] = [RecordingMetadataCutoverTestSupport.candidate()],
        executor: any CanonicalRecordingMetadataCutoverExecutor
    ) async -> CanonicalCutoverResult {
        await CanonicalRecordingMetadataCutoverRunner().run(
            configuration: configuration,
            token: RecordingMetadataCutoverTestSupport.token(),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .testHarness,
            executor: executor
        )
    }

    private static func sendCandidate() -> CanonicalRecordingMetadataCutoverCandidate {
        let local = CanonicalProductionTestFixtures.recording(
            id: "recording-send-01",
            title: "Local Newer",
            modifiedAt: CanonicalProductionTestFixtures.date(2_200)
        )
        let peer = CanonicalProductionTestFixtures.recording(
            id: "recording-send-01",
            title: "Peer Older",
            modifiedAt: CanonicalProductionTestFixtures.date(2_100)
        )
        return CanonicalRecordingMetadataCutoverCandidate(
            action: CanonicalApplyAction(
                kind: .recordingMetadataSend,
                source: .local,
                target: CanonicalApplyTarget(objectID: "recording-send-01"),
                bridgeHint: .legacyMetadataManifestSend,
                reason: CanonicalApplyActionKind.recordingMetadataSend.rawValue
            ),
            localObject: local,
            peerObject: peer,
            rollbackCheckpointID: "recording-metadata-checkpoint-send-01"
        )
    }

    private static func applyCandidate(
        id: String,
        title: String,
        reason: String
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
                kind: .recordingMetadataApply,
                source: .peer,
                target: CanonicalApplyTarget(objectID: id),
                bridgeHint: .legacyMetadataManifestApply,
                reason: reason
            ),
            localObject: local,
            peerObject: peer,
            rollbackCheckpointID: "recording-metadata-checkpoint-\(id)-\(reason)"
        )
    }
}

private actor CommitTrackingApplyPort: CanonicalProductionApplyPort {
    let isDryRunOnly = false
    let metadataApplySupported = true
    let generatedArtifactApplySupported = false
    let tombstoneApplySupported = false
    let conflictRecordSupported = false

    private let rejectPostcondition: Bool
    private let unexpectedSideEffect: Bool
    private(set) var applyCount = 0
    private(set) var sendCount = 0
    private(set) var rollbackCount = 0

    init(rejectPostcondition: Bool = false, unexpectedSideEffect: Bool = false) {
        self.rejectPostcondition = rejectPostcondition
        self.unexpectedSideEffect = unexpectedSideEffect
    }

    func applyMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        applyCount += 1
        return result(request: request, status: .applied)
    }

    func sendMetadata(_ request: CanonicalProductionApplyExecutionRequest) async throws -> CanonicalProductionApplyResult {
        sendCount += 1
        return result(request: request, status: .sent)
    }

    func rollbackApply(_ request: CanonicalRollbackAction) async throws -> CanonicalRollbackResult {
        rollbackCount += 1
        return CanonicalRollbackResult(planID: request.checkpointID ?? request.actionID, succeeded: true, completedActionIDs: [request.actionID])
    }

    func verifyPrecondition(_ precondition: CanonicalProductionApplyPrecondition) async throws -> CanonicalProductionApplyPrecondition {
        precondition
    }

    func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) async throws -> CanonicalProductionApplyPostcondition {
        var checked = postcondition
        if rejectPostcondition {
            checked.accepted = false
            checked.reason = "injectedPostconditionMismatch"
        }
        return checked
    }

    func projectApplyDryRun(_ action: CanonicalApplyAction) async throws -> CanonicalProductionApplyTrace {
        CanonicalProductionApplyTrace(action: action, wouldCallApplySyncManifest: false, reason: "commitExecutorTest")
    }

    private func result(
        request: CanonicalProductionApplyExecutionRequest,
        status: CanonicalApplyExecutionStatus
    ) -> CanonicalProductionApplyResult {
        CanonicalProductionApplyResult(
            actionID: request.action.actionID,
            status: status,
            precondition: CanonicalProductionApplyPrecondition(actionID: request.action.actionID, target: request.action.target, accepted: true),
            postcondition: CanonicalProductionApplyPostcondition(actionID: request.action.actionID, target: request.action.target, accepted: true),
            sideEffect: CanonicalProductionSideEffect(
                kind: unexpectedSideEffect ? .uploadSessionStart : .metadataApply,
                domain: unexpectedSideEffect ? .uploadRuntime : .recordingMetadata,
                objectID: request.action.target.objectID,
                summary: unexpectedSideEffect ? "unexpectedUploadMutation" : status.rawValue
            ),
            rollbackCheckpointID: request.rollbackCheckpointID
        )
    }
}

private actor RouteRecorder {
    private(set) var routes: [String] = []
    private(set) var bodyCounts: [Int] = []

    func record(route: String, bodyCount: Int) {
        routes.append(route)
        bodyCounts.append(bodyCount)
    }
}
