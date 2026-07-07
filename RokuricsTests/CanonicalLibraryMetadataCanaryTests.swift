//
//  CanonicalLibraryMetadataCanaryTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLibraryMetadataCanaryTests {
    @Test func v815N1ConfigurationIsExplicitAndDefaultOff() {
        let disabled = CanonicalLibraryMetadataCanaryConfiguration()
        let n1 = CanonicalLibraryMetadataCanaryConfiguration.internalN1()

        #expect(disabled.mode == .disabled)
        #expect(disabled.strictN1Enabled == false)
        #expect(n1.mode == .n1)
        #expect(n1.domain == .libraryMetadata)
        #expect(n1.canaryMaxObjectsPerSyncRun == 1)
        #expect(n1.explicitInternalTestConfiguration)
        #expect(n1.strictN1Enabled)
    }

    @Test func n1CanaryCommitsExactlyOneSafeCandidateAndRecordsObservation() async {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded)
        #expect(result.cutoverResult.canaryAttemptedCount == 1)
        #expect(result.cutoverResult.commits.count == 1)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs == [candidate.action.actionID])
        #expect(result.selection.selectedCandidates.count == 1)
        #expect(result.observationReport.status == .committed)
        #expect(result.observationReport.uiMutated == false)
        #expect(result.observationReport.resourceMoved == false)
        #expect(result.observationReport.physicalDeleteAttempted == false)
        #expect(result.observationReport.contentBytesMutated == false)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1CanaryConfigured })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1CandidateSelected })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1CommitCompleted })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1PostconditionVerified })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1DuplicateLegacySuppressed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1ReadSideParallelEquivalent })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1ObservationRecorded })
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
    }

    @Test func n1CanaryBlocksNAboveOneAllEligibleAndRuntimeSwitch() async {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let policy = Self.policy(
            canaryMaxObjectsPerSyncRun: 3,
            runtimeSwitchEnabled: true,
            allowAllEligible: true
        )
        let configuration = CanonicalLibraryMetadataCanaryConfiguration(
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
            executor: LibraryMetadataCutoverTestSupport.FakeExecutor()
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.gate.failures.contains(.canaryBudgetAboveOneDenied))
        #expect(result.cutoverResult.gate.failures.contains(.allEligibleCanaryDenied))
        #expect(result.cutoverResult.gate.failures.contains(.runtimeSwitchDenied))
        #expect(result.cutoverResult.canaryAttemptedCount == 0)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1FatalBlocker })
    }

    @Test func unsafeResourceMoveCandidateIsBlockedBeforeCommit() async {
        let candidate = LibraryMetadataCutoverTestSupport.resourceMoveCandidate()
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor()

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded == false)
        #expect(result.selection.selectedCandidates.isEmpty)
        #expect(result.selection.blockers.contains { $0.reason == .resourceMoveAttempted })
        #expect(result.cutoverResult.candidateSafetyReports?.first?.resourceMoveAttempted == true)
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1CandidateBlocked })
        #expect(await executor.committedActionIDs.isEmpty)
    }

    @Test func commitFailureRollsBackPreservesFallbackAndDoesNotSuppressLegacy() async {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor(.postconditionMismatch)

        let result = await Self.run(candidates: [candidate], executor: executor)

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.rollbackResults.first?.succeeded == true)
        #expect(result.cutoverResult.legacyFallbackUsed)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.observationReport.status == .failedRolledBack)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1CommitFailed })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1RollbackCompleted })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1LegacyFallbackUsed })
        #expect(await executor.rolledBackActionIDs == [candidate.action.actionID])
    }

    private static func run(
        configuration: CanonicalLibraryMetadataCanaryConfiguration = .internalN1(),
        policy: CanonicalLibraryMetadataCanaryPolicy = Self.policy(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        executor: any CanonicalLibraryMetadataCutoverExecutor
    ) async -> CanonicalLibraryMetadataCanaryResult {
        await CanonicalLibraryMetadataN1CanaryRunner().run(
            configuration: configuration,
            policy: policy,
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: LibraryMetadataCutoverTestSupport.evidence(),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v815-library-metadata-canary",
            executor: executor
        )
    }

    private static func policy(
        canaryMaxObjectsPerSyncRun: Int = 1,
        runtimeSwitchEnabled: Bool = false,
        allowAllEligible: Bool = false
    ) -> CanonicalLibraryMetadataCanaryPolicy {
        CanonicalLibraryMetadataCanaryPolicy(
            canaryMaxObjectsPerSyncRun: canaryMaxObjectsPerSyncRun,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true,
            runtimeSwitchEnabled: runtimeSwitchEnabled,
            allowAllEligible: allowAllEligible
        )
    }
}
