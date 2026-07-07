//
//  CanonicalMigrationMatrixTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalMigrationMatrixTests {
    @Test func v813MatrixAllowsExactlyOneLibraryMetadataActivePilot() {
        let matrix = CanonicalMigrationDomainMatrix.defaultV813()
        let report = matrix.validate()

        #expect(report.allowed)
        #expect(report.activePilotDomain == .libraryMetadata)
        #expect(report.policies.filter { $0.activePilot }.count == 1)
        #expect(report.policies.first { $0.domain == .libraryMetadata }?.activePilotExplicit == true)
    }

    @Test func generatedArtifactsCannotBeActivePilotInV813() {
        let matrix = matrixWithActivePilot(.generatedArtifacts)
        let validation = CanonicalMigrationGlobalConfigValidator().validate(matrix)

        #expect(validation.valid == false)
        #expect(validation.violations.contains(.activeDomainNotLibraryMetadata))
        #expect(validation.violations.contains(.generatedArtifactsActiveBeforePilotComplete))
    }

    @Test func tombstoneConflictCannotBeActivePilotInV813() {
        let matrix = matrixWithActivePilot(.tombstoneConflict)
        let validation = CanonicalMigrationGlobalConfigValidator().validate(matrix)

        #expect(validation.valid == false)
        #expect(validation.violations.contains(.activeDomainNotLibraryMetadata))
        #expect(validation.violations.contains(.tombstoneConflictActiveBeforePilotComplete))
    }

    @Test func audioUploadCannotBeActivePilotInV813() {
        let matrix = matrixWithActivePilot(.audioUpload)
        let validation = CanonicalMigrationGlobalConfigValidator().validate(matrix)

        #expect(validation.valid == false)
        #expect(validation.violations.contains(.activeDomainNotLibraryMetadata))
        #expect(validation.violations.contains(.audioUploadActiveBeforePilotComplete))
    }

    @Test func runtimeSwitchTrueIsViolation() {
        let matrix = matrixReplacing(.libraryMetadata) { policy in
            policy.runtimeSwitchEnabled = true
        }
        let validation = CanonicalMigrationGlobalConfigValidator().validate(matrix)

        #expect(validation.valid == false)
        #expect(validation.violations.contains(.runtimeSwitchEnabled))
    }

    @Test func releaseDefaultEnabledCutoverIsViolation() {
        let matrix = matrixReplacing(.libraryMetadata) { policy in
            policy.defaultCutoverEnabled = true
            policy.releaseDefaultEnabledCutover = true
        }
        let validation = CanonicalMigrationGlobalConfigValidator().validate(matrix)

        #expect(validation.valid == false)
        #expect(validation.violations.contains(.releaseDefaultEnabledCutover))
    }

    @Test func legacyRetirementBeforeReadSideCutoverIsViolation() {
        let matrix = matrixReplacing(.legacyRetirement) { policy in
            policy.stageStatuses = [.retirementCandidate: .complete]
            policy.staticOnly = false
            policy.blockedForRealMigration = false
        }
        let validation = CanonicalMigrationGlobalConfigValidator().validate(matrix)

        #expect(validation.valid == false)
        #expect(validation.violations.contains(.legacyRetirementBeforeReadSideCutover))
    }

    @Test func libraryMetadataReadinessReportDetectsPresentParts() {
        let report = CanonicalLibraryMetadataPilotReport.currentV813Audit(readSideParallelProjection: true)

        #expect(report.readiness == .readyForN1)
        #expect(report.readyForN0)
        #expect(report.readyForN1)
        #expect(report.blockers.isEmpty)
    }

    @Test func libraryMetadataReadinessFlagsMissingReadSideParallel() {
        let report = CanonicalLibraryMetadataPilotReport.currentV813Audit(readSideParallelProjection: false)

        #expect(report.readiness == .missingReadSideParallel)
        #expect(report.readyForN0)
        #expect(report.readyForN1 == false)
        #expect(report.blockers.contains(.missingReadSideParallel))
    }

    @Test func otherDomainsReportStaticOnlyAndDefaultOff() {
        let matrix = CanonicalMigrationDomainMatrix.defaultV813()
        let staticOnlyDomains: [CanonicalMigrationDomain] = [
            .recordingMetadata,
            .generatedArtifacts,
            .tombstoneConflict,
            .audioUpload,
            .uiProjection,
            .legacyRetirement
        ]
        let staticAudit = CanonicalOtherDomainsStaticAuditReport.v813Default()

        for domain in staticOnlyDomains {
            #expect(matrix.policy(for: domain)?.staticOnly == true)
            #expect(matrix.policy(for: domain)?.blockedForRealMigration == true)
        }
        #expect(staticAudit.audits.allSatisfy { $0.defaultOff })
        #expect(staticAudit.audits.allSatisfy { $0.readPathLegacy })
    }

    @Test func matrixDoesNotChangeAppBehaviorOrLegacySuppression() {
        let matrix = CanonicalMigrationDomainMatrix.defaultV813()

        #expect(matrix.policies.allSatisfy { $0.defaultCutoverEnabled == false })
        #expect(matrix.policies.allSatisfy { $0.releaseDefaultEnabledCutover == false })
        #expect(matrix.policies.allSatisfy { $0.runtimeSwitchEnabled == false })
        #expect(matrix.policies.allSatisfy { $0.legacySuppressionAllowed == false })
        #expect(CanonicalCutoverAppSeamConfiguration().effectiveMode == .disabled)
        #expect(CanonicalGeneratedArtifactCutoverAppSeamConfiguration().effectiveMode == .disabled)
        #expect(CanonicalLibraryMetadataCutoverAppSeamConfiguration().effectiveMode == .disabled)
        #expect(CanonicalTombstoneConflictCutoverAppSeamConfiguration().effectiveMode == .disabled)
        #expect(CanonicalAudioUploadCutoverAppSeamConfiguration().effectiveMode == .disabled)
    }

    @Test func diagnosticsRemainRedacted() {
        let report = CanonicalMigrationDomainMatrix.defaultV813().validate()
        let sensitivePath = "file:///Users/example/private/secret.json"

        #expect(report.diagnosticsRedacted)
        #expect(report.diagnosticsSummary.contains("/Users/") == false)
        #expect(CanonicalMigrationDomainMatrix.isRedacted(sensitivePath) == false)
    }

    @Test func v814GuardedCommitSeamRequiresLibraryMetadataPilotAndCanaryZero() {
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: v814LibraryConfiguration(),
            context: v814LibraryContext(matrix: .defaultV813())
        )
        let generatedActive = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: v814LibraryConfiguration(),
            context: v814LibraryContext(matrix: matrixWithActivePilot(.generatedArtifacts))
        )

        #expect(result.gate.allowed)
        #expect(result.canaryBudgetZero)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataV814GateAllowedBudgetZero })
        #expect(generatedActive.gate.allowed == false)
        #expect(generatedActive.gate.failures.contains(.activePilotNotLibraryMetadata))
        #expect(generatedActive.willExecuteNow == false)
        #expect(generatedActive.duplicateLegacySuppressedActionIDs.isEmpty)
    }

    @Test func v822GeneratedArtifactsCanBecomeSoleActivePilotAfterLibraryObservation() {
        let activation = CanonicalGeneratedArtifactPilotActivation.v822(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        )
        let matrix = activation.result.matrix
        let report = matrix.validate()
        let globalValidation = CanonicalMigrationGlobalConfigValidator().validate(matrix)
        let generated = matrix.policy(for: .generatedArtifacts)

        #expect(activation.result.activated)
        #expect(report.allowed)
        #expect(globalValidation.valid)
        #expect(report.activePilotDomain == .generatedArtifacts)
        #expect(generated?.activePilot == true)
        #expect(generated?.hasReached(.nextPilotCandidate) == true)
        #expect(generated?.hasReached(.canaryN0) == true)
        #expect(generated?.hasReached(.canaryN1) == false)
        #expect(matrix.policy(for: .libraryMetadata)?.activePilot == false)
        #expect(matrix.policies.filter { $0.domain != .generatedArtifacts }.allSatisfy {
            !$0.activePilot
                && $0.staticOnly
                && !$0.defaultCutoverEnabled
                && !$0.releaseDefaultEnabledCutover
                && !$0.runtimeSwitchEnabled
                && !$0.legacySuppressionAllowed
                && $0.readPathLegacy
                && $0.noProductionInjection
        })
    }

    @Test func v822GeneratedArtifactsActivePilotRequiresLibraryMetadataObservation() {
        let activation = CanonicalGeneratedArtifactPilotActivation.v822(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: false
        )
        let report = activation.result.matrixReport
        let globalValidation = CanonicalMigrationGlobalConfigValidator().validate(activation.result.matrix)

        #expect(activation.result.activated == false)
        #expect(activation.result.blockers.contains(.libraryMetadataObservationMissing))
        #expect(report.allowed == false)
        #expect(report.blockers.contains(.generatedArtifactsActivePilotBeforeLibraryMetadataObservation))
        #expect(report.blockers.contains(.generatedArtifactsNextPilotBeforeLibraryMetadataObservation))
        #expect(globalValidation.valid == false)
        #expect(globalValidation.violations.contains(.generatedArtifactsNextPilotBeforeLibraryMetadataObservation))
    }

    @Test func v824GeneratedArtifactsStagedCanaryExpandsOnlyGeneratedArtifacts() {
        let matrix = CanonicalMigrationDomainMatrix.v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        )
        let report = matrix.validate()
        let globalValidation = CanonicalMigrationGlobalConfigValidator().validate(matrix)
        let generated = matrix.policy(for: .generatedArtifacts)

        #expect(report.allowed)
        #expect(globalValidation.valid)
        #expect(report.activePilotDomain == .generatedArtifacts)
        #expect(generated?.activePilot == true)
        #expect(generated?.hasReached(.nextPilotCandidate) == true)
        #expect(generated?.hasReached(.canaryN0) == true)
        #expect(generated?.hasReached(.canaryN1) == true)
        #expect(generated?.hasReached(.expandedCanary) == true)
        #expect(generated?.defaultCutoverEnabled == false)
        #expect(generated?.releaseDefaultEnabledCutover == false)
        #expect(generated?.runtimeSwitchEnabled == false)
        #expect(generated?.readPathLegacy == true)
        #expect(generated?.noProductionInjection == true)
        #expect(generated?.legacySuppressionAllowed == false)
        #expect(matrix.policies.filter { $0.domain != .generatedArtifacts }.allSatisfy {
            !$0.activePilot
                && $0.staticOnly
                && !$0.defaultCutoverEnabled
                && !$0.releaseDefaultEnabledCutover
                && !$0.runtimeSwitchEnabled
                && !$0.legacySuppressionAllowed
                && $0.readPathLegacy
                && $0.noProductionInjection
        })
    }

    @Test func v824GeneratedArtifactsStagedCanaryStillRequiresLibraryObservation() {
        let matrix = CanonicalMigrationDomainMatrix.v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: false
        )
        let report = matrix.validate()
        let globalValidation = CanonicalMigrationGlobalConfigValidator().validate(matrix)

        #expect(report.allowed == false)
        #expect(report.blockers.contains(.generatedArtifactsActivePilotBeforeLibraryMetadataObservation))
        #expect(report.blockers.contains(.generatedArtifactsNextPilotBeforeLibraryMetadataObservation))
        #expect(globalValidation.valid == false)
        #expect(globalValidation.violations.contains(.generatedArtifactsNextPilotBeforeLibraryMetadataObservation))
    }

    private func matrixWithActivePilot(_ domain: CanonicalMigrationDomain) -> CanonicalMigrationDomainMatrix {
        matrixReplacing(domain) { policy in
            policy.activePilot = true
            policy.activePilotExplicit = true
            policy.staticOnly = false
            policy.blockedForRealMigration = false
            policy.stageStatuses[.canaryN1] = .activePilot
        }
    }

    private func matrixReplacing(
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

    private func v814LibraryConfiguration() -> CanonicalLibraryMetadataCutoverAppSeamConfiguration {
        .enabled(
            mode: .canaryCommit,
            policy: CanonicalLibraryMetadataCutoverAppSeamPolicy(
                canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0)
            ),
            evidence: CanonicalLibraryMetadataCutoverEvidence.passing(
                rollbackPlan: CanonicalRollbackPlan(planID: "mac-v814-matrix-rollback", checkpoints: [], actions: [])
            ),
            cutoverToken: CanonicalCutoverToken(tokenID: "mac-v814-matrix-token", syncRunID: "mac-v814-matrix", ownerApproved: true)
        )
    }

    private func v814LibraryContext(
        matrix: CanonicalMigrationDomainMatrix
    ) -> CanonicalLibraryMetadataGuardedCommitContext {
        let manifest = CanonicalManifest.make(
            node: CanonicalNode(nodeID: "mac-matrix-node", platform: "test", capabilities: [.canonicalLibraryObjectsV1]),
            generatedAt: Date(timeIntervalSince1970: 1_000),
            objects: [],
            libraryObjects: [],
            manifestCapabilities: [.canonicalLibraryObjectsV1]
        )
        return CanonicalLibraryMetadataGuardedCommitContext(
            syncRunID: "mac-v814-matrix",
            trigger: .periodic,
            nodeRole: .testHarness,
            localManifest: manifest,
            peerManifest: manifest,
            matrix: matrix,
            evidence: CanonicalLibraryMetadataCutoverEvidence.passing(
                rollbackPlan: CanonicalRollbackPlan(planID: "mac-v814-matrix-rollback", checkpoints: [], actions: [])
            ),
            canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0),
            cutoverToken: CanonicalCutoverToken(tokenID: "mac-v814-matrix-token", syncRunID: "mac-v814-matrix", ownerApproved: true),
            candidates: [],
            localSnapshotAvailable: true,
            peerSnapshotAvailable: true
        )
    }
}
