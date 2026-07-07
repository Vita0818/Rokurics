//
//  CanonicalTombstoneConflictCanaryTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalTombstoneConflictCanaryTests {
    @Test func macN1ConfigurationIsExplicitAndDefaultOff() {
        let defaultConfig = CanonicalTombstoneConflictCanaryConfiguration()
        let defaultAppConfig = CanonicalTombstoneConflictCutoverAppSeamConfiguration()
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
        #expect(explicitConfig.strictN1Enabled)
        #expect(CanonicalTombstoneConflictCanaryConfiguration(appSeamConfiguration: explicitAppConfig).strictN1Enabled)
        #expect(explicitPolicy.runtimeSwitchEnabled == false)
    }

    @Test func macExplicitN1CanCommitOneSafeSoftMarkerCandidate() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let executor = TombstoneConflictCutoverTestSupport.FakeExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded)
        #expect(result.cutoverResult.canaryAttemptedCount == 1)
        #expect(result.cutoverResult.commits.count == 1)
        #expect(result.cutoverResult.commits.first?.sideEffects.map(\.kind) == [.tombstoneMark])
        #expect(result.cutoverResult.commits.first?.receiveJSONMutated == false)
        #expect(result.cutoverResult.commits.first?.audioTranscriptNoteSummaryDeleted == false)
        #expect(result.observationReport.uiMutated == false)
        #expect(result.observationReport.physicalDeletePerformed == false)
        #expect(result.observationReport.permanentDeletePerformed == false)
        #expect(result.observationReport.tombstoneGCPerformed == false)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1CommitCompleted })
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
    }

    @Test func macPeerSnapshotMissingBlocksWithoutCommit() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate

        let result = await CanonicalTombstoneConflictN1CanaryRunner().run(
            configuration: .internalN1(),
            policy: Self.n1Policy(),
            token: TombstoneConflictCutoverTestSupport.token(),
            evidence: TombstoneConflictCutoverTestSupport.evidence(),
            matrix: .v827TombstoneConflictActivePilot(
                libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
                generatedArtifactsTemplateCompleteOrObservationReady: true
            ),
            candidates: [candidate],
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "v828-mac-tombstone-conflict-missing-peer",
            peerSnapshotAvailable: false,
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.commits.isEmpty)
        #expect(result.selection.blockers.contains { $0.reason == .peerSnapshotUnavailable })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1MacPeerSnapshotUnavailable })
        #expect(result.cutoverResult.legacyFallbackUsed)
    }

    @Test func macUnsafePhysicalPermanentGcRestoreAndStaleCandidatesAreBlocked() async {
        let candidates = [
            Self.reasonCandidate("physicalDelete"),
            Self.reasonCandidate("permanentDelete"),
            Self.reasonCandidate("tombstoneGC"),
            Self.reasonCandidate("restoreObject"),
            Self.staleLiveCandidate()
        ]

        let result = await Self.run(
            candidates: candidates,
            executor: TombstoneConflictCutoverTestSupport.FakeExecutor()
        )
        let blockers = Set(result.selection.blockers.map(\.reason))

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.commits.isEmpty)
        #expect(blockers.contains(.physicalDeleteCandidate))
        #expect(blockers.contains(.permanentDeleteCandidate))
        #expect(blockers.contains(.tombstoneGCCandidate))
        #expect(blockers.contains(.restoreWithoutExplicitSignal))
        #expect(blockers.contains(.staleLiveResurrection))
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1PhysicalDeleteBlocked })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1PermanentDeleteBlocked })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1GCBlocked })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1StaleLiveResurrectionBlocked })
    }

    @Test func macCommitFailureRollsBackAndDoesNotSuppressLegacy() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let executor = TombstoneConflictCutoverTestSupport.FakeExecutor(.postconditionMismatch)

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.observationReport.status == .failedRolledBack)
        #expect(result.observationReport.rollbackCount == 1)
        #expect(await executor.rolledBackActionIDs == [candidate.action.actionID])
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1RollbackCompleted })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1DuplicateSuppressionSkipped })
    }

    @Test func macRollbackFailureIsFatalBlocker() async {
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let executor = MacRollbackFailingTombstoneConflictExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.fatalBlocker)
        #expect(result.observationReport.status == .fatalRollbackFailure)
        #expect(result.observationReport.rollbackFailureCount == 1)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1RollbackFailed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalTombstoneConflictN1FatalBlocker })
    }

    @Test func macRealApplyPortWritesOnlyRootBoundMarkerAndLeavesContentUntouched() async throws {
        let rootURL = TombstoneConflictCutoverTestSupport.makeScratchRoot("MacV828TombstoneConflictN1")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = TombstoneConflictCutoverTestSupport.objectTombstoneCandidate().candidate
        let audioURL = rootURL.appendingPathComponent("audio/recording-01.m4a")
        try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("audio-bytes-preserved".utf8).write(to: audioURL)
        let applyPort = try MacTombstoneConflictRealApplyPort(testRootURL: rootURL)
        let executor = MacTombstoneConflictCutoverExecutor(applyPort: applyPort)

        let result = await Self.run(candidates: [candidate], executor: executor)
        let markerBytes = try await applyPort.rootBoundTombstoneConflictBytes(for: candidate.action.actionID)

        #expect(result.succeeded)
        #expect(markerBytes?.isEmpty == false)
        #expect(try Data(contentsOf: audioURL) == Data("audio-bytes-preserved".utf8))
        #expect(result.cutoverResult.commits.first?.physicalDeleteSuppressed == true)
        #expect(result.cutoverResult.commits.first?.permanentDeleteSuppressed == true)
        #expect(result.cutoverResult.commits.first?.tombstoneGCSuppressed == true)
        #expect(result.cutoverResult.commits.first?.receiveJSONMutated == false)
        #expect(result.cutoverResult.commits.first?.audioTranscriptNoteSummaryDeleted == false)
    }

    private static func run(
        configuration: CanonicalTombstoneConflictCanaryConfiguration = .internalN1(),
        policy: CanonicalTombstoneConflictCanaryPolicy = Self.n1Policy(),
        candidates: [CanonicalTombstoneConflictCandidate],
        trigger: CanonicalSyncPlanTrigger = .periodic,
        executor: any CanonicalTombstoneConflictCutoverExecutor
    ) async -> CanonicalTombstoneConflictCanaryResult {
        await CanonicalTombstoneConflictN1CanaryRunner().run(
            configuration: configuration,
            policy: policy,
            token: TombstoneConflictCutoverTestSupport.token(),
            evidence: TombstoneConflictCutoverTestSupport.evidence(),
            matrix: .v827TombstoneConflictActivePilot(
                libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
                generatedArtifactsTemplateCompleteOrObservationReady: true
            ),
            candidates: candidates,
            trigger: trigger,
            nodeRole: .mac,
            syncRunID: "v828-mac-tombstone-conflict-n1",
            executor: executor
        )
    }

    private static func n1Policy() -> CanonicalTombstoneConflictCanaryPolicy {
        CanonicalTombstoneConflictCanaryPolicy(
            canaryMaxObjectsPerSyncRun: 1,
            allowCandidateExecution: true,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true
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
}

actor MacRollbackFailingTombstoneConflictExecutor: CanonicalTombstoneConflictCutoverExecutor {
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
