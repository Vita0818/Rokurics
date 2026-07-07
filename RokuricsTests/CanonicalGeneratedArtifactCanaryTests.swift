//
//  CanonicalGeneratedArtifactCanaryTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalGeneratedArtifactCanaryTests {
    @Test func v823N1ConfigurationIsExplicitAndDefaultOff() {
        let disabled = CanonicalGeneratedArtifactCanaryConfiguration()
        let n1 = CanonicalGeneratedArtifactCanaryConfiguration.internalN1()

        #expect(disabled.mode == .disabled)
        #expect(disabled.strictN1Enabled == false)
        #expect(n1.mode == .n1)
        #expect(n1.domain == .generatedArtifacts)
        #expect(n1.canaryMaxObjectsPerSyncRun == 1)
        #expect(n1.explicitInternalTestConfiguration)
        #expect(n1.strictN1Enabled)
    }

    @Test func n1CanaryCommitsExactlyOneSafeCandidateAndRecordsObservation() async {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate(kind: .summaryJSON).candidate
        let executor = GeneratedArtifactCutoverTestSupport.FakeExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded)
        #expect(result.cutoverResult.canaryAttemptedCount == 1)
        #expect(result.cutoverResult.commits.count == 1)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs == [candidate.action.actionID])
        #expect(result.selection.selectedCandidates.count == 1)
        #expect(result.observationReport.status == .committed)
        #expect(result.observationReport.generatedArtifactDownloadOnly)
        #expect(result.observationReport.generatedArtifactUploadAttempted == false)
        #expect(result.observationReport.audioUploadAttempted == false)
        #expect(result.observationReport.contentLeakRiskObserved == false)
        #expect(result.observationReport.routeIsArtifactRequest)
        #expect(result.observationReport.uiMutated == false)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1CanaryConfigured })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1CandidateSelected })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1CommitCompleted })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1PostconditionVerified })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1DuplicateLegacySuppressed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1ReadSideParallelEquivalent })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1ObservationRecorded })
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
    }

    @Test func n1CanaryBlocksNAboveOneAllEligibleAndRuntimeSwitch() async {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate().candidate
        let policy = Self.policy(
            canaryMaxObjectsPerSyncRun: 3,
            runtimeSwitchEnabled: true,
            allowAllEligible: true
        )
        let configuration = CanonicalGeneratedArtifactCanaryConfiguration(
            mode: .n1,
            canaryMaxObjectsPerSyncRun: 3,
            explicitInternalTestConfiguration: true,
            runtimeSwitchEnabled: true,
            allowAllEligible: true
        )

        let result = await Self.run(
            configuration: configuration,
            policy: policy,
            candidates: [candidate],
            executor: GeneratedArtifactCutoverTestSupport.FakeExecutor()
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.gate.failures.contains(.canaryBudgetAboveOneDenied))
        #expect(result.cutoverResult.gate.failures.contains(.allEligibleCanaryDenied))
        #expect(result.cutoverResult.gate.failures.contains(.runtimeSwitchDenied))
        #expect(result.cutoverResult.canaryAttemptedCount == 0)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1FatalBlocker })
    }

    @Test func selectorPrioritizesSummaryJSONBeforeFullTranscriptMarkdown() {
        let transcript = GeneratedArtifactCutoverTestSupport.candidate(objectID: "recording-b", kind: .transcriptMarkdown).candidate
        let summary = GeneratedArtifactCutoverTestSupport.candidate(objectID: "recording-z", kind: .summaryJSON).candidate

        let selection = CanonicalGeneratedArtifactCanarySelector().select(
            mode: .canary,
            policy: Self.policy(),
            trigger: .periodic,
            evidence: GeneratedArtifactCutoverTestSupport.evidence(),
            peerNode: GeneratedArtifactCutoverTestSupport.macNode(),
            candidates: [transcript, summary]
        )

        #expect(selection.selectedCandidates.count == 1)
        #expect(selection.selectedCandidates.first?.artifactKind == .summaryJSON)
    }

    @Test func unsafeGeneratedArtifactCandidatesAreBlockedBeforeCommit() async {
        let candidates = [
            Self.candidateWithMissingHash(),
            Self.candidateWithMissingByteSize(),
            Self.candidateWithUnsafeLogicalPath(),
            Self.candidateWithWrongRoute(),
            Self.candidateWithAmbiguousProducer(),
            GeneratedArtifactCutoverTestSupport.candidate(kind: .audio).candidate
        ]
        let executor = GeneratedArtifactCutoverTestSupport.FakeExecutor()

        let result = await Self.run(candidates: candidates, executor: executor)

        #expect(result.succeeded == false)
        #expect(result.selection.selectedCandidates.isEmpty)
        #expect(result.selection.blockers.contains { $0.reason == .hashUnavailable })
        #expect(result.selection.blockers.contains { $0.reason == .byteSizeUnavailable })
        #expect(result.selection.blockers.contains { $0.reason == .unsafeLogicalPathToken })
        #expect(result.selection.blockers.contains { $0.reason == .unsupportedRoute })
        #expect(result.selection.blockers.contains { $0.reason == .producerAmbiguous })
        #expect(result.selection.blockers.contains { $0.reason == .audioConfusionRisk })
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1CandidateBlocked })
        #expect(await executor.committedActionIDs.isEmpty)
    }

    @Test func commitFailureRollsBackPreservesFallbackAndDoesNotSuppressLegacy() async {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate().candidate
        let executor = GeneratedArtifactCutoverTestSupport.FakeExecutor(.postconditionMismatch)

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.rollbackResults.first?.succeeded == true)
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.observationReport.status == .failedRolledBack)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1CommitFailed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1RollbackCompleted })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1LegacyFallbackUsed })
        #expect(await executor.rolledBackActionIDs == [candidate.action.actionID])
    }

    @Test func rollbackFailureBecomesFatalAndKeepsDuplicateSuppressionOff() async {
        let candidate = GeneratedArtifactCutoverTestSupport.candidate().candidate
        let executor = RollbackFailingGeneratedArtifactExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.fatalBlocker)
        #expect(result.observationReport.status == .fatalRollbackFailure)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1RollbackFailed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1FatalBlocker })
    }

    @Test func macPeerSnapshotUnavailableBlocksN1AsReportOnly() async {
        let result = await CanonicalGeneratedArtifactN1CanaryRunner().run(
            configuration: .internalN1(),
            policy: Self.policy(),
            token: GeneratedArtifactCutoverTestSupport.token(),
            evidence: GeneratedArtifactCutoverTestSupport.evidence(),
            candidates: [],
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "v823-generated-artifact-mac",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: false,
            peerNode: nil,
            executor: nil
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.gate.failures.contains(.peerSnapshotUnavailable))
        #expect(result.cutoverResult.gate.failures.contains(.commitExecutorUnavailable))
        #expect(result.cutoverResult.canaryAttemptedCount == 0)
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalGeneratedArtifactN1MacPeerSnapshotUnavailable })
        #expect(result.observationReport.status == .blocked)
    }

    private static func run(
        configuration: CanonicalGeneratedArtifactCanaryConfiguration = .internalN1(),
        policy: CanonicalGeneratedArtifactCanaryPolicy = Self.policy(),
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        executor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    ) async -> CanonicalGeneratedArtifactCanaryResult {
        await CanonicalGeneratedArtifactN1CanaryRunner().run(
            configuration: configuration,
            policy: policy,
            token: GeneratedArtifactCutoverTestSupport.token(),
            evidence: GeneratedArtifactCutoverTestSupport.evidence(),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v823-generated-artifact-canary",
            peerNode: GeneratedArtifactCutoverTestSupport.macNode(),
            executor: executor
        )
    }

    private static func policy(
        canaryMaxObjectsPerSyncRun: Int = 1,
        runtimeSwitchEnabled: Bool = false,
        allowAllEligible: Bool = false
    ) -> CanonicalGeneratedArtifactCanaryPolicy {
        CanonicalGeneratedArtifactCanaryPolicy(
            canaryMaxObjectsPerSyncRun: canaryMaxObjectsPerSyncRun,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true,
            runtimeSwitchEnabled: runtimeSwitchEnabled,
            allowAllEligible: allowAllEligible
        )
    }

    private static func candidateWithMissingHash() -> CanonicalGeneratedArtifactCutoverCandidate {
        var candidate = GeneratedArtifactCutoverTestSupport.candidate(objectID: "missing-hash").candidate
        var artifact = candidate.peerArtifact
        artifact?.contentHash = nil
        candidate.peerArtifact = artifact
        return candidate
    }

    private static func candidateWithMissingByteSize() -> CanonicalGeneratedArtifactCutoverCandidate {
        var candidate = GeneratedArtifactCutoverTestSupport.candidate(objectID: "missing-bytes").candidate
        var artifact = candidate.peerArtifact
        artifact?.byteSize = nil
        candidate.peerArtifact = artifact
        return candidate
    }

    private static func candidateWithUnsafeLogicalPath() -> CanonicalGeneratedArtifactCutoverCandidate {
        var candidate = GeneratedArtifactCutoverTestSupport.candidate(objectID: "unsafe-path").candidate
        var artifact = candidate.peerArtifact
        artifact?.logicalPathToken = "../transcript.json"
        candidate.peerArtifact = artifact
        return candidate
    }

    private static func candidateWithWrongRoute() -> CanonicalGeneratedArtifactCutoverCandidate {
        let base = GeneratedArtifactCutoverTestSupport.candidate(objectID: "wrong-route").candidate
        return CanonicalGeneratedArtifactCutoverCandidate(
            action: base.action,
            localObject: base.localObject,
            peerObject: base.peerObject,
            localArtifact: base.localArtifact,
            peerArtifact: base.peerArtifact,
            rollbackCheckpointID: base.rollbackCheckpointID,
            routePath: "/sync/generated-artifact"
        )
    }

    private static func candidateWithAmbiguousProducer() -> CanonicalGeneratedArtifactCutoverCandidate {
        var candidate = GeneratedArtifactCutoverTestSupport.candidate(objectID: "bad-producer").candidate
        var artifact = candidate.peerArtifact
        artifact?.producedBy = .unknown
        artifact?.producedByNodeID = "unknown-node"
        candidate.peerArtifact = artifact
        return candidate
    }
}

private actor RollbackFailingGeneratedArtifactExecutor: CanonicalGeneratedArtifactCutoverExecutor {
    func commitGeneratedArtifact(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate
    ) async -> CanonicalGeneratedArtifactProductionCommitResult {
        .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "injectedGeneratedArtifactFailure")
    }

    func rollbackGeneratedArtifact(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate,
        reason: CanonicalGeneratedArtifactCutoverFailure
    ) async -> CanonicalGeneratedArtifactRollbackExecutionResult {
        CanonicalGeneratedArtifactRollbackExecutionResult(
            checkpointID: candidate.effectiveRollbackCheckpointID,
            succeeded: false,
            fatal: true,
            reason: "injectedRollbackFailure"
        )
    }
}
