//
//  CanonicalLibraryMetadataProductionRootPilotTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/6.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLibraryMetadataProductionRootPilotTests {
    @Test func productionRootExplicitGateBlocksDefaultReleaseRuntimeSwitchAndNAboveOne() {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let defaultGate = Self.gate(
            configuration: .disabled,
            candidates: [candidate],
            executorAvailable: false
        )
        let oversizedPolicy = CanonicalLibraryMetadataProductionCanaryPolicy(
            canaryMaxObjectsPerSyncRun: 2,
            runtimeSwitchEnabled: true,
            allowAllEligible: true,
            releaseDefaultEnabled: true
        )
        let unsafeGate = Self.gate(
            configuration: Self.configuration(policy: oversizedPolicy),
            candidates: [candidate]
        )

        #expect(defaultGate.allowed == false)
        #expect(defaultGate.blockers.contains(.modeNotExecuteN1Canary))
        #expect(defaultGate.blockers.contains(.rootModeNotProductionRootExplicit))
        #expect(defaultGate.blockers.contains(.allowProductionRootWritesFalse))
        #expect(unsafeGate.allowed == false)
        #expect(unsafeGate.blockers.contains(.n1BudgetRequired))
        #expect(unsafeGate.blockers.contains(.runtimeSwitchEnabled))
        #expect(unsafeGate.blockers.contains(.allEligibleDenied))
        #expect(unsafeGate.blockers.contains(.releaseDefaultDenied))
        #expect(CanonicalLibraryMetadataProductionCanaryConfiguration.disabled.allowProductionRootWrites == false)
        #expect(CanonicalLibraryMetadataProductionCanaryConfiguration.disabled.policy.runtimeSwitchEnabled == false)
        #expect(CanonicalLibraryMetadataProductionCanaryConfiguration.disabled.policy.releaseDefaultEnabled == false)
    }

    @Test func productionRootExplicitGateRequiresOwnerFreezeEvidenceRollbackAndReadSideZero() {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        var notExplicit = Self.configuration()
        notExplicit.explicitInternalDebugConfiguration = false
        var divergentEvidence = Self.productionEvidence()
        divergentEvidence.readSideParallelEquivalent = false
        var noRollbackEvidence = Self.productionEvidence()
        noRollbackEvidence.rollbackVerified = false
        noRollbackEvidence.rollbackRehearsalPassed = false
        var noTestRootEvidence = Self.productionEvidence()
        noTestRootEvidence.testRootUsed = false
        let generatedActive = Self.matrixReplacing(.generatedArtifacts) { policy in
            policy.activePilot = true
            policy.activePilotExplicit = true
            policy.staticOnly = false
            policy.blockedForRealMigration = false
        }

        #expect(Self.gate(configuration: notExplicit, candidates: [candidate]).blockers.contains(.missingExplicitDebugInternalConfiguration))
        #expect(Self.gate(token: Self.token(ownerApproved: false), candidates: [candidate]).blockers.contains(.missingOwnerApproval))
        #expect(Self.gate(evidence: divergentEvidence, candidates: [candidate]).blockers.contains(.readSideDivergenceNonZero))
        #expect(Self.gate(evidence: noRollbackEvidence, candidates: [candidate]).blockers.contains(.rollbackEvidenceMissing))
        #expect(Self.gate(evidence: noTestRootEvidence, candidates: [candidate]).blockers.contains(.testRootExecuteEvidenceMissing))
        #expect(Self.gate(matrix: generatedActive, candidates: [candidate]).blockers.contains(.landingFreezeNotGreen))
    }

    @Test func productionRootExplicitGateBlocksUnsafeMultipleAndOtherDomainCandidates() {
        let folder = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let unsafe = LibraryMetadataCutoverTestSupport.resourceMoveCandidate()
        let otherDomain = Self.configuration(
            policy: CanonicalLibraryMetadataProductionCanaryPolicy(domain: .generatedArtifacts)
        )

        let unsafeGate = Self.gate(candidates: [unsafe])
        let multipleGate = Self.gate(candidates: [folder, Self.secondFolderCandidate()])
        let otherDomainGate = Self.gate(configuration: otherDomain, candidates: [folder])

        #expect(unsafeGate.allowed == false)
        #expect(unsafeGate.blockers.contains(.resourceMoveAttempted))
        #expect(unsafeGate.blockers.contains(.unsafeCandidateSelected))
        #expect(multipleGate.allowed == false)
        #expect(multipleGate.blockers.contains(.multipleSafeCandidatesDenied))
        #expect(otherDomainGate.blockers.contains(.nonLibraryMetadataDomain))
    }

    @Test func iPhoneDefaultConstructionCannotProductionRootWriteAndExplicitConfigCanConstructGate() throws {
        let disabled = try IPhoneLibraryMetadataProductionCanaryBootstrap().prepare()
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let allowedGate = Self.gate(candidates: [candidate])

        #expect(disabled.executorInjected == false)
        #expect(disabled.applyPortInjected == false)
        #expect(disabled.blockers == [.disabled])
        #expect(allowedGate.allowed)
        #expect(allowedGate.selectedCandidate?.objectKind == .folder)
    }

    @Test func iPhoneProductionRootExplicitExecutesOneSafeCandidateAndBuildsRedactedProof() async throws {
        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneV831ProductionRoot")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = LibraryMetadataCutoverTestSupport.folderCandidate()
        let bootstrap = try IPhoneLibraryMetadataProductionCanaryBootstrap(
            configuration: Self.configuration()
        ).prepare(
            productionRootURL: rootURL,
            evidence: Self.productionEvidence()
        )
        let port = try #require(bootstrap.applyPort)
        try await port.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)

        let result = await Self.run(
            configuration: bootstrap.configuration,
            evidence: bootstrap.evidence,
            candidates: [pair.candidate],
            executor: bootstrap.executor
        )
        let bytes = try await port.rootBoundLibraryMetadataBytes(
            objectID: pair.candidate.objectID,
            objectKind: .folder,
            domain: .folderMetadata
        )

        #expect(result.succeeded)
        #expect(result.executed)
        #expect(result.productionRootGate?.allowed == true)
        #expect(result.productionRootSafetyProof?.rootContainmentVerified == true)
        #expect(result.productionRootSafetyProof?.atomicWriteUsed == true)
        #expect(result.productionRootSafetyProof?.postconditionVerified == true)
        #expect(result.productionRootSafetyProof?.redacted == true)
        #expect(result.productionRootSafetyProof?.redactedTargetSummary.contains("/Users/") == false)
        #expect(result.cutoverResult?.commits.count == 1)
        #expect(result.cutoverResult?.duplicateLegacySuppressedActionIDs == [pair.candidate.action.actionID])
        #expect(result.observationReport.uiMutated == false)
        #expect(result.observationReport.resourceMoved == false)
        #expect(result.observationReport.uploadJobCreated == false)
        #expect(bytes == pair.bytes)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataProductionRootGateAllowed })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataProductionRootAtomicWriteCompleted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataProductionRootSafetyProofBuilt })
        #expect(result.diagnostics.allSatisfy { !CanonicalProductionRedaction.containsSensitivePathSignal($0.diagnosticsSummary) })
    }

    @Test func iPhoneRootContainmentCheckpointAndPostconditionFailuresFallbackWithoutDuplicateSuppression() async throws {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        var testRootEvidence = Self.productionEvidence()
        testRootEvidence.applyPortMode = .testRootBound
        var noCheckpointEvidence = Self.productionEvidence()
        noCheckpointEvidence.rollbackCheckpointAvailable = false
        let containmentGate = Self.gate(evidence: testRootEvidence, candidates: [candidate])
        let checkpointGate = Self.gate(evidence: noCheckpointEvidence, candidates: [candidate])

        #expect(containmentGate.blockers.contains(.productionRootContainmentUnverified))
        #expect(checkpointGate.blockers.contains(.rollbackEvidenceMissing))

        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneV831PostconditionRollback")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = LibraryMetadataCutoverTestSupport.folderCandidate()
        let bootstrap = try IPhoneLibraryMetadataProductionCanaryBootstrap(
            configuration: Self.configuration()
        ).prepare(
            productionRootURL: rootURL,
            evidence: Self.productionEvidence()
        )
        let port = try #require(bootstrap.applyPort)
        try await port.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)
        await port.injectRootBoundPostconditionFailure(objectID: pair.candidate.objectID)

        let result = await Self.run(
            configuration: bootstrap.configuration,
            evidence: bootstrap.evidence,
            candidates: [pair.candidate],
            executor: bootstrap.executor
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult?.legacyFallbackUsed == true)
        #expect(result.cutoverResult?.duplicateLegacySuppressedActionIDs.isEmpty == true)
        #expect(result.observationReport.legacyFallbackPreserved)
        #expect(result.observationReport.duplicateSuppressionApplied == false)
        #expect(result.observationReport.uiMutated == false)
        #expect(result.observationReport.resourceMoved == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataProductionRootLegacyFallbackUsed })
    }

    @Test func rollbackFailureIsFatalAndDoesNotSuppressLegacy() async {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let result = await Self.run(
            configuration: Self.configuration(),
            evidence: Self.productionEvidence(),
            candidates: [candidate],
            executor: FatalRollbackExecutor()
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult?.fatalBlocker == true)
        #expect(result.blockers.contains(.fatalBlocker))
        #expect(result.cutoverResult?.duplicateLegacySuppressedActionIDs.isEmpty == true)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataProductionRootRollbackFailed })
    }

    @Test func iPhoneNoReadPathSwitchNoUiNoResourceMoveNoNoteContentAndOtherDomainsStaticOnly() {
        let gate = Self.gate(candidates: [LibraryMetadataCutoverTestSupport.folderCandidate().candidate])
        let matrix = CanonicalMigrationDomainMatrix.defaultV813()

        #expect(gate.allowed)
        #expect(gate.selectedCandidateSafety?.resourceMoveAttempted == false)
        #expect(gate.selectedCandidateSafety?.contentBytesMutated == false)
        #expect(matrix.policy(for: .generatedArtifacts)?.staticOnly == true)
        #expect(matrix.policy(for: .tombstoneConflict)?.staticOnly == true)
        #expect(matrix.policy(for: .audioUpload)?.staticOnly == true)
        #expect(matrix.policies.allSatisfy { $0.readPathLegacy })
        #expect(matrix.policies.allSatisfy { !$0.runtimeSwitchEnabled })
    }

    private static func configuration(
        policy: CanonicalLibraryMetadataProductionCanaryPolicy = .strictLibraryMetadataN1
    ) -> CanonicalLibraryMetadataProductionCanaryConfiguration {
        CanonicalLibraryMetadataProductionCanaryConfiguration(
            mode: .canaryN1Execute,
            rootMode: .productionRootExplicit,
            policy: policy,
            explicitInternalDebugConfiguration: true,
            allowProductionRootWrites: true
        )
    }

    private static func productionEvidence() -> CanonicalLibraryMetadataCutoverEvidence {
        var evidence = LibraryMetadataCutoverTestSupport.evidence()
        evidence.applyPortMode = .productionRootBound
        return evidence
    }

    private static func token(ownerApproved: Bool = true) -> CanonicalCutoverToken {
        CanonicalCutoverToken(
            tokenID: "v831-library-metadata-production-root",
            syncRunID: "v831-production-root-sync",
            ownerApproved: ownerApproved
        )
    }

    private static func gate(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration = Self.configuration(),
        token: CanonicalCutoverToken? = Self.token(),
        evidence: CanonicalLibraryMetadataCutoverEvidence = Self.productionEvidence(),
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        executorAvailable: Bool = true
    ) -> CanonicalLibraryMetadataProductionRootGateResult {
        CanonicalLibraryMetadataProductionRootGate().evaluate(
            configuration: configuration,
            token: token,
            evidence: evidence,
            matrix: matrix,
            candidates: candidates,
            trigger: .manual,
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executorAvailable: executorAvailable
        )
    }

    private static func run(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) async -> CanonicalLibraryMetadataProductionCanaryInjectionResult {
        await CanonicalLibraryMetadataProductionCanaryInjection().evaluateOrRun(
            configuration: configuration,
            token: Self.token(),
            evidence: evidence,
            candidates: candidates,
            trigger: .manual,
            nodeRole: .iPhone,
            syncRunID: "v831-iphone-production-root",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true,
            executor: executor
        )
    }

    private static func secondFolderCandidate() -> CanonicalLibraryMetadataCutoverCandidate {
        CanonicalLibraryMetadataCutoverCandidate(
            action: CanonicalApplyAction(
                kind: .folderMetadataApply,
                source: .peer,
                target: CanonicalApplyTarget(objectID: "folder:science"),
                bridgeHint: .legacyMetadataManifestApply,
                reason: "v831SecondFolder"
            ),
            localObject: LibraryMetadataCutoverTestSupport.folderObject(objectID: "folder:science", name: "Science", modifiedAt: 2_000),
            peerObject: LibraryMetadataCutoverTestSupport.folderObject(objectID: "folder:science", name: "Science Peer", modifiedAt: 3_000),
            rollbackCheckpointID: "folder-science-checkpoint"
        )
    }

    private static func matrixReplacing(
        _ domain: CanonicalMigrationDomain,
        mutate: (inout CanonicalMigrationDomainPolicy) -> Void
    ) -> CanonicalMigrationDomainMatrix {
        var matrix = CanonicalMigrationDomainMatrix.defaultV813()
        matrix.policies = matrix.policies.map { existing in
            var copy = existing
            if copy.domain == domain {
                mutate(&copy)
            }
            return copy
        }
        return matrix
    }
}

private actor FatalRollbackExecutor: CanonicalLibraryMetadataCutoverExecutor {
    func commitLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate
    ) async -> CanonicalLibraryMetadataProductionCommitResult {
        .failure(
            candidate: candidate,
            kind: .postconditionMismatch,
            partialCommit: true,
            reason: "v831FatalRollbackCommitFailure"
        )
    }

    func rollbackLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate,
        reason: CanonicalLibraryMetadataCutoverFailure
    ) async -> CanonicalLibraryMetadataRollbackExecutionResult {
        CanonicalLibraryMetadataRollbackExecutionResult(
            checkpointID: candidate.effectiveRollbackCheckpointID,
            succeeded: false,
            fatal: true,
            reason: "v831FatalRollbackFailure"
        )
    }
}
