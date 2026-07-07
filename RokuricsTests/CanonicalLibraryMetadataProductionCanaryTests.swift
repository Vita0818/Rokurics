//
//  CanonicalLibraryMetadataProductionCanaryTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLibraryMetadataProductionCanaryTests {
    @Test func productionCanaryDefaultsDisabledWithN1BudgetOnly() async {
        let configuration = CanonicalLibraryMetadataProductionCanaryConfiguration()
        let result = await Self.run(
            configuration: configuration,
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            executor: nil
        )

        #expect(configuration.mode == .disabled)
        #expect(configuration.policy.domain == .libraryMetadata)
        #expect(configuration.canaryMaxObjectsPerSyncRun == 1)
        #expect(configuration.explicitInternalDebugConfiguration == false)
        #expect(configuration.policy.runtimeSwitchEnabled == false)
        #expect(configuration.policy.allowAllEligible == false)
        #expect(configuration.policy.releaseDefaultEnabled == false)
        #expect(result.injectionConfigured == false)
        #expect(result.executorInjected == false)
        #expect(result.applyPortInjected == false)
        #expect(result.executed == false)
        #expect(result.observationReport.status == .disabled)
    }

    @Test func armedN1ConfigurationInjectsNoCommitAndDoesNotSuppressLegacy() async {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor()

        let result = await Self.run(
            configuration: .explicitTestRootN1Armed(),
            candidates: [candidate],
            executor: executor
        )

        #expect(result.armed)
        #expect(result.executed == false)
        #expect(result.succeeded == false)
        #expect(result.blockers == [.armedNoExecution])
        #expect(result.observationReport.status == .armed)
        #expect(result.observationReport.duplicateSuppressionApplied == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryArmed })
        #expect(await executor.committedActionIDs.isEmpty)
    }

    @Test func explicitN1ExecutesOneSafeCandidateAndSuppressesMatchingLegacyOnlyAfterSuccess() async {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor()

        let result = await Self.run(
            configuration: .explicitTestRootN1Execute(),
            candidates: [candidate],
            executor: executor
        )

        #expect(result.succeeded)
        #expect(result.executed)
        #expect(result.canaryResult?.cutoverResult.canaryAttemptedCount == 1)
        #expect(result.cutoverResult?.duplicateLegacySuppressedActionIDs == [candidate.action.actionID])
        #expect(result.observationReport.status == .executedSucceeded)
        #expect(result.observationReport.successfulCommitCount == 1)
        #expect(result.observationReport.duplicateSuppressionCount == 1)
        #expect(result.observationReport.uiMutated == false)
        #expect(result.observationReport.resourceMoved == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryExecutionStarted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryExecutionCompleted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryDuplicateLegacySuppressed })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryReadSideEquivalent })
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
    }

    @Test func failedN1RollsBackPreservesFallbackAndDoesNotSuppressLegacy() async {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor(.postconditionMismatch)

        let result = await Self.run(
            configuration: .explicitTestRootN1Execute(),
            candidates: [candidate],
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.executed)
        #expect(result.cutoverResult?.rollbackResults.first?.succeeded == true)
        #expect(result.cutoverResult?.legacyFallbackUsed == true)
        #expect(result.cutoverResult?.duplicateLegacySuppressedActionIDs.isEmpty == true)
        #expect(result.observationReport.status == .executedFailedRolledBack)
        #expect(result.observationReport.legacyFallbackPreserved)
        #expect(result.observationReport.duplicateSuppressionApplied == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryExecutionFailed })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryRollbackCompleted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryLegacyFallbackUsed })
        #expect(await executor.rolledBackActionIDs == [candidate.action.actionID])
    }

    @Test func unsafeResourceMoveCandidateIsSkippedBeforeExecution() async {
        let candidate = LibraryMetadataCutoverTestSupport.resourceMoveCandidate()
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor()

        let result = await Self.run(
            configuration: .explicitTestRootN1Execute(),
            candidates: [candidate],
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.executed == false)
        #expect(result.blockers.contains(.unsafeCandidateSkipped))
        #expect(result.observationReport.status == .unsafeCandidateSkipped)
        #expect(result.observationReport.unsafeCandidateSkippedCount == 1)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryUnsafeCandidateSkipped })
        #expect(await executor.committedActionIDs.isEmpty)
    }

    @Test func readSideParallelEvidenceIsRequiredBeforeExecution() async {
        var evidence = LibraryMetadataCutoverTestSupport.evidence()
        evidence.readSideParallelEquivalent = false
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor()

        let result = await Self.run(
            configuration: .explicitTestRootN1Execute(),
            evidence: evidence,
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.executed == false)
        #expect(result.blockers.contains(.readSideParallelDivergent))
        #expect(result.observationReport.readSideParallelDivergent)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryBlocked })
        #expect(await executor.committedActionIDs.isEmpty)
    }

    @Test func policyBlocksNAboveOneRuntimeSwitchAllEligibleAndReleaseDefault() async {
        let policy = CanonicalLibraryMetadataProductionCanaryPolicy(
            canaryMaxObjectsPerSyncRun: 3,
            runtimeSwitchEnabled: true,
            allowAllEligible: true,
            releaseDefaultEnabled: true
        )
        let configuration = CanonicalLibraryMetadataProductionCanaryConfiguration(
            mode: .canaryN1Execute,
            rootMode: .testRoot,
            policy: policy,
            explicitInternalDebugConfiguration: true
        )

        let result = await Self.run(
            configuration: configuration,
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            executor: LibraryMetadataCutoverTestSupport.FakeExecutor()
        )

        #expect(result.executed == false)
        #expect(result.blockers.contains(.canaryBudgetAboveOneDenied))
        #expect(result.blockers.contains(.runtimeSwitchDenied))
        #expect(result.blockers.contains(.allEligibleDenied))
        #expect(result.blockers.contains(.releaseDefaultDenied))
    }

    @Test func iPhoneBootstrapDefaultsOffAndExplicitTestRootInjectsExecutor() throws {
        let disabled = try IPhoneLibraryMetadataProductionCanaryBootstrap().prepare()
        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneV818ProductionCanaryBootstrap")
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let injected = try IPhoneLibraryMetadataProductionCanaryBootstrap(
            configuration: .explicitTestRootN1Execute()
        ).prepare(
            testRootURL: rootURL,
            evidence: LibraryMetadataCutoverTestSupport.evidence()
        )

        #expect(disabled.executorInjected == false)
        #expect(disabled.applyPortInjected == false)
        #expect(disabled.blockers == [.disabled])
        #expect(injected.executorInjected)
        #expect(injected.applyPortInjected)
        #expect(injected.evidence.applyPortMode == .testRootBound)
        #expect(injected.evidence.testRootUsed)
    }

    @Test func productionRootExplicitAllowFalseDoesNotInjectEvenWhenRootURLIsProvided() async throws {
        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneV818ProductionRootDenied")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let configuration = CanonicalLibraryMetadataProductionCanaryConfiguration
            .explicitProductionRootN1Execute(allowProductionRootWrites: false)
        let bootstrap = try IPhoneLibraryMetadataProductionCanaryBootstrap(
            configuration: configuration
        ).prepare(
            productionRootURL: rootURL,
            evidence: LibraryMetadataCutoverTestSupport.evidence()
        )

        let result = await Self.run(
            configuration: bootstrap.configuration,
            evidence: bootstrap.evidence,
            candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate],
            executor: bootstrap.executor
        )

        #expect(bootstrap.executorInjected == false)
        #expect(bootstrap.applyPortInjected == false)
        #expect(bootstrap.evidence.applyPortMode == LibraryMetadataCutoverTestSupport.evidence().applyPortMode)
        #expect(bootstrap.blockers.contains(.productionRootWritesDisabled))
        #expect(result.executed == false)
        #expect(result.blockers.contains(.productionRootWritesDisabled))
        #expect(result.blockers.contains(.productionRootGuardMissing))
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRealCanaryBlocked })
    }

    @Test func allowProductionRootWritesTrueInjectsProductionRootBoundExecutorInV831() async throws {
        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneV830ProductionRootAllowTrue")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = LibraryMetadataCutoverTestSupport.folderCandidate()
        let configuration = CanonicalLibraryMetadataProductionCanaryConfiguration
            .explicitProductionRootN1Execute(allowProductionRootWrites: true)
        let bootstrap = try IPhoneLibraryMetadataProductionCanaryBootstrap(
            configuration: configuration
        ).prepare(
            productionRootURL: rootURL,
            evidence: LibraryMetadataCutoverTestSupport.evidence()
        )
        try await bootstrap.applyPort?.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)

        let result = await Self.run(
            configuration: bootstrap.configuration,
            evidence: bootstrap.evidence,
            candidates: [pair.candidate],
            executor: bootstrap.executor
        )

        #expect(bootstrap.executorInjected)
        #expect(bootstrap.applyPortInjected)
        #expect(bootstrap.evidence.applyPortMode == .productionRootBound)
        #expect(result.succeeded)
        #expect(result.productionRootGate?.allowed == true)
        #expect(result.productionRootSafetyProof?.redacted == true)
    }

    private static func run(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        evidence: CanonicalLibraryMetadataCutoverEvidence = LibraryMetadataCutoverTestSupport.evidence(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) async -> CanonicalLibraryMetadataProductionCanaryInjectionResult {
        await CanonicalLibraryMetadataProductionCanaryInjection().evaluateOrRun(
            configuration: configuration,
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: evidence,
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v818-library-metadata-production-canary",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: executor
        )
    }
}
