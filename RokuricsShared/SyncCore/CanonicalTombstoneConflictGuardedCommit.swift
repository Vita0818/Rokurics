//
//  CanonicalTombstoneConflictGuardedCommit.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated enum CanonicalTombstoneConflictPilotActivationBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case templateNotReadyForNextPilotN0
    case generatedArtifactsTemplateMissing
    case libraryMetadataObservationMissing
    case matrixValidationBlocked
    case activePilotNotTombstoneConflict
    case canaryN0NotReached
    case canaryN1Reached
    case releaseDefaultCutoverEnabled
    case runtimeSwitchEnabled
    case legacySuppressionEnabled
    case readPathNotLegacy
    case productionInjectionPresent
}

nonisolated struct CanonicalTombstoneConflictPilotActivationResult: Codable, Equatable, Sendable {
    var activated: Bool
    var matrix: CanonicalMigrationDomainMatrix
    var matrixReport: CanonicalMigrationMatrixReport
    var blockers: [CanonicalTombstoneConflictPilotActivationBlocker]
    var diagnosticsSummary: String

    nonisolated init(
        matrix: CanonicalMigrationDomainMatrix,
        blockers: [CanonicalTombstoneConflictPilotActivationBlocker]
    ) {
        let matrixReport = matrix.validate()
        let normalizedBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.matrix = matrix
        self.matrixReport = matrixReport
        self.blockers = normalizedBlockers
        self.activated = normalizedBlockers.isEmpty
            && matrixReport.allowed
            && matrixReport.activePilotDomain == .tombstoneConflict
        self.diagnosticsSummary = [
            "domain=tombstoneConflict",
            "version=v8.27",
            "activated=\(activated)",
            "activePilot=\(matrixReport.activePilotDomain?.rawValue ?? "none")",
            "matrixAllowed=\(matrixReport.allowed)",
            "blockers=\(normalizedBlockers.map(\.rawValue).joined(separator: "+"))"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalTombstoneConflictPilotActivation: Codable, Equatable, Sendable {
    var templateReport: CanonicalTombstoneConflictTemplateReport
    var libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool
    var generatedArtifactsTemplateCompleteOrObservationReady: Bool
    var result: CanonicalTombstoneConflictPilotActivationResult

    nonisolated static func v827(
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool,
        generatedArtifactsTemplateCompleteOrObservationReady: Bool,
        templateReport: CanonicalTombstoneConflictTemplateReport = .currentV826Audit()
    ) -> CanonicalTombstoneConflictPilotActivation {
        let result = CanonicalTombstoneConflictPilotActivationGate().evaluate(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            generatedArtifactsTemplateCompleteOrObservationReady: generatedArtifactsTemplateCompleteOrObservationReady,
            templateReport: templateReport
        )
        return CanonicalTombstoneConflictPilotActivation(
            templateReport: templateReport,
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            generatedArtifactsTemplateCompleteOrObservationReady: generatedArtifactsTemplateCompleteOrObservationReady,
            result: result
        )
    }
}

nonisolated struct CanonicalTombstoneConflictPilotActivationGate: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool,
        generatedArtifactsTemplateCompleteOrObservationReady: Bool,
        templateReport: CanonicalTombstoneConflictTemplateReport = .currentV826Audit()
    ) -> CanonicalTombstoneConflictPilotActivationResult {
        let matrix = CanonicalMigrationDomainMatrix.v827TombstoneConflictActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            generatedArtifactsTemplateCompleteOrObservationReady: generatedArtifactsTemplateCompleteOrObservationReady,
            templateReport: templateReport
        )
        let report = matrix.validate()
        let policy = matrix.policy(for: .tombstoneConflict)
        var blockers: [CanonicalTombstoneConflictPilotActivationBlocker] = []
        if !templateReport.readyForNextPilotN0 {
            blockers.append(.templateNotReadyForNextPilotN0)
        }
        if !generatedArtifactsTemplateCompleteOrObservationReady {
            blockers.append(.generatedArtifactsTemplateMissing)
        }
        if !libraryMetadataObservationCompleteOrRetirementCandidateReady {
            blockers.append(.libraryMetadataObservationMissing)
        }
        if !report.allowed {
            blockers.append(.matrixValidationBlocked)
        }
        if report.activePilotDomain != .tombstoneConflict {
            blockers.append(.activePilotNotTombstoneConflict)
        }
        if policy?.hasReached(.canaryN0) != true {
            blockers.append(.canaryN0NotReached)
        }
        if policy?.hasReached(.canaryN1) == true {
            blockers.append(.canaryN1Reached)
        }
        if policy?.defaultCutoverEnabled == true || policy?.releaseDefaultEnabledCutover == true {
            blockers.append(.releaseDefaultCutoverEnabled)
        }
        if policy?.runtimeSwitchEnabled == true {
            blockers.append(.runtimeSwitchEnabled)
        }
        if policy?.legacySuppressionAllowed == true {
            blockers.append(.legacySuppressionEnabled)
        }
        if policy?.readPathLegacy != true {
            blockers.append(.readPathNotLegacy)
        }
        if policy?.noProductionInjection != true {
            blockers.append(.productionInjectionPresent)
        }
        return CanonicalTombstoneConflictPilotActivationResult(matrix: matrix, blockers: blockers)
    }
}

nonisolated enum CanonicalTombstoneConflictGuardedEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case complete
    case incomplete
}

nonisolated enum CanonicalTombstoneConflictGateResult: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case blocked
    case allowedButCanaryBudgetZero
    case missingEvidence
    case unsupportedDomain
    case physicalDeleteBlocked
    case permanentDeleteBlocked
    case tombstoneGCBlocked
    case antiResurrectionBlocked
    case staleLiveResurrectionRisk
    case conflictPolicyAmbiguous
    case readyForN1AfterAudit
}

nonisolated enum CanonicalTombstoneConflictGuardedSeamFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedMode
    case productionExecuteDenied
    case viewRefreshTriggerDenied
    case retryDrainerFreshTombstoneConflictDenied
    case insufficientLocalSnapshot
    case insufficientPeerSnapshot
    case matrixValidationBlocked
    case activePilotNotTombstoneConflict
    case unsupportedDomain
    case unsupportedAction
    case missingToken
    case missingOwnerApproval
    case missingNoCommitEvidence
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingMetadataRouteEvidence
    case productionPortUnavailable
    case realApplyPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case missingRollback
    case rollbackVerificationMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case softTombstoneStoreUnsupported
    case conflictLedgerUnsupported
    case missingTombstoneWinsPolicy
    case missingRollbackEvidence
    case missingTombstoneTimestamp
    case legacyFallbackUnavailable
    case commitExecutorUnavailable
    case missingFailureInjectionEvidence
    case missingReadSideParallel
    case missingObservationEvidence
    case missingAntiResurrectionGate
    case missingPhysicalDeleteGuard
    case missingPermanentDeleteGuard
    case missingTombstoneGCGuard
    case missingConflictConservativePolicy
    case physicalDeletePathDetected
    case permanentDeletePathDetected
    case tombstoneGCPathDetected
    case unsupportedRestore
    case staleLiveResurrectionRisk
    case conflictPolicyAmbiguous
    case generatedArtifactTombstonedParentApplyBlocked
    case duplicateSuppressionPolicyUnavailable
    case duplicateSuppressionPolicyEnabled
    case canaryBudgetNonZeroDenied
    case canaryStageExecutionDenied
    case runtimeSwitchDenied
}

typealias CanonicalTombstoneConflictGateBlocker = CanonicalTombstoneConflictGuardedSeamFailure

nonisolated struct CanonicalTombstoneConflictGuardedGate: Codable, Equatable, Sendable {
    var mode: CanonicalCutoverAppSeamMode
    var allowed: Bool
    var result: CanonicalTombstoneConflictGateResult
    var failures: [CanonicalTombstoneConflictGuardedSeamFailure]
    var reason: String

    nonisolated init(
        mode: CanonicalCutoverAppSeamMode,
        failures: [CanonicalTombstoneConflictGuardedSeamFailure],
        canaryBudgetZero: Bool,
        reason: String
    ) {
        self.mode = mode
        self.failures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = self.failures.isEmpty
        self.result = Self.gateResult(for: self.failures, allowed: self.allowed, canaryBudgetZero: canaryBudgetZero)
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? self.result.rawValue
    }

    private nonisolated static func gateResult(
        for failures: [CanonicalTombstoneConflictGuardedSeamFailure],
        allowed: Bool,
        canaryBudgetZero: Bool
    ) -> CanonicalTombstoneConflictGateResult {
        if allowed && canaryBudgetZero {
            return .allowedButCanaryBudgetZero
        }
        if failures.contains(.physicalDeletePathDetected) {
            return .physicalDeleteBlocked
        }
        if failures.contains(.permanentDeletePathDetected) {
            return .permanentDeleteBlocked
        }
        if failures.contains(.tombstoneGCPathDetected) {
            return .tombstoneGCBlocked
        }
        if failures.contains(.missingAntiResurrectionGate) {
            return .antiResurrectionBlocked
        }
        if failures.contains(.staleLiveResurrectionRisk) {
            return .staleLiveResurrectionRisk
        }
        if failures.contains(.conflictPolicyAmbiguous) {
            return .conflictPolicyAmbiguous
        }
        if failures.contains(.unsupportedDomain) || failures.contains(.unsupportedAction) {
            return .unsupportedDomain
        }
        if failures.contains(where: \.isEvidenceMissing) {
            return .missingEvidence
        }
        return .blocked
    }
}

nonisolated enum CanonicalTombstoneConflictGuardedDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalTombstoneConflictV827SeamStarted
    case canonicalTombstoneConflictV827SeamCompleted
    case canonicalTombstoneConflictV827SeamBlocked
    case canonicalTombstoneConflictV827GateEvaluated
    case canonicalTombstoneConflictV827GateAllowedBudgetZero
    case canonicalTombstoneConflictV827GateBlocked
    case canonicalTombstoneConflictV827CanaryBudgetZero
    case canonicalTombstoneConflictV827CommitNotExecuted
    case canonicalTombstoneConflictV827DeleteNotExecuted
    case canonicalTombstoneConflictV827RestoreNotExecuted
    case canonicalTombstoneConflictV827ConflictNotAutoResolved
    case canonicalTombstoneConflictV827LegacyFallbackPreserved
    case canonicalTombstoneConflictV827DuplicateSuppressionNotApplied
    case canonicalTombstoneConflictV827EvidenceReportBuilt
    case canonicalTombstoneConflictV827N1ReadinessReportBuilt
    case canonicalTombstoneConflictCanaryBudgetZero
    case canonicalTombstoneConflictGateAllowedButNoExecution
    case canonicalTombstoneConflictCommitSkippedBecauseCanaryBudgetZero
    case canonicalTombstoneConflictDeleteSkippedBecauseCanaryBudgetZero
    case canonicalTombstoneConflictRestoreSkippedBecauseCanaryBudgetZero
    case canonicalTombstoneConflictResolutionSkippedBecauseCanaryBudgetZero
}

nonisolated struct CanonicalTombstoneConflictGuardedDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String {
        [kind.rawValue, objectID ?? "run", domain?.rawValue ?? "", result ?? "", reason ?? ""].joined(separator: "|")
    }

    var kind: CanonicalTombstoneConflictGuardedDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var mode: CanonicalCutoverAppSeamMode
    var domain: CanonicalTombstoneConflictDomain?
    var objectID: String?
    var actionKind: CanonicalTombstoneConflictActionKind?
    var candidateCount: Int
    var eligibleCandidateCount: Int
    var gateFailureCount: Int
    var canaryBudget: Int
    var commitAttemptedCount: Int
    var deleteAttemptedCount: Int
    var restoreAttemptedCount: Int
    var conflictResolutionAttemptedCount: Int
    var duplicateSuppressionCandidateCount: Int
    var staleLiveMetadataRiskCount: Int
    var activeVsTombstoneConflictCount: Int
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalTombstoneConflictGuardedDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        mode: CanonicalCutoverAppSeamMode,
        domain: CanonicalTombstoneConflictDomain? = nil,
        objectID: String? = nil,
        actionKind: CanonicalTombstoneConflictActionKind? = nil,
        candidateCount: Int,
        eligibleCandidateCount: Int = 0,
        gateFailureCount: Int = 0,
        canaryBudget: Int,
        commitAttemptedCount: Int = 0,
        deleteAttemptedCount: Int = 0,
        restoreAttemptedCount: Int = 0,
        conflictResolutionAttemptedCount: Int = 0,
        duplicateSuppressionCandidateCount: Int = 0,
        staleLiveMetadataRiskCount: Int = 0,
        activeVsTombstoneConflictCount: Int = 0,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) {
        self.kind = kind
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.mode = mode
        self.domain = domain
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "tombstone-object") }
        self.actionKind = actionKind
        self.candidateCount = max(0, candidateCount)
        self.eligibleCandidateCount = max(0, eligibleCandidateCount)
        self.gateFailureCount = max(0, gateFailureCount)
        self.canaryBudget = max(0, canaryBudget)
        self.commitAttemptedCount = max(0, commitAttemptedCount)
        self.deleteAttemptedCount = max(0, deleteAttemptedCount)
        self.restoreAttemptedCount = max(0, restoreAttemptedCount)
        self.conflictResolutionAttemptedCount = max(0, conflictResolutionAttemptedCount)
        self.duplicateSuppressionCandidateCount = max(0, duplicateSuppressionCandidateCount)
        self.staleLiveMetadataRiskCount = max(0, staleLiveMetadataRiskCount)
        self.activeVsTombstoneConflictCount = max(0, activeVsTombstoneConflictCount)
        self.result = CanonicalProductionRedaction.safeDiagnosticText(result)
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
        self.hashPrefix = hash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            "mode=\(mode.rawValue)",
            domain.map { "domain=\($0.rawValue)" },
            objectID.map { "objectID=\($0)" },
            actionKind.map { "actionKind=\($0.rawValue)" },
            "candidateCount=\(candidateCount)",
            "eligibleCandidateCount=\(eligibleCandidateCount)",
            "gateFailureCount=\(gateFailureCount)",
            "canaryBudget=\(canaryBudget)",
            "commitAttemptedCount=\(commitAttemptedCount)",
            "deleteAttemptedCount=\(deleteAttemptedCount)",
            "restoreAttemptedCount=\(restoreAttemptedCount)",
            "conflictResolutionAttemptedCount=\(conflictResolutionAttemptedCount)",
            "duplicateSuppressionCandidateCount=\(duplicateSuppressionCandidateCount)",
            "staleLiveMetadataRiskCount=\(staleLiveMetadataRiskCount)",
            "activeVsTombstoneConflictCount=\(activeVsTombstoneConflictCount)",
            result.map { "result=\($0)" },
            reason.map { "reason=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated struct CanonicalTombstoneConflictEvidenceReport: Codable, Equatable, Sendable {
    var status: CanonicalTombstoneConflictGuardedEvidenceStatus
    var missingReasons: [CanonicalTombstoneConflictGuardedSeamFailure]
    var matrixReport: CanonicalMigrationMatrixReport
    var canaryPolicy: CanonicalTombstoneConflictCanaryPolicy
    var localSnapshotAvailable: Bool
    var peerSnapshotAvailable: Bool
    var candidateCount: Int
    var eligibleCandidateCount: Int
    var legacyActionCandidateCount: Int
    var staleLiveMetadataRiskCount: Int
    var activeVsTombstoneConflictCount: Int
    var generatedArtifactTombstonedParentApplyBlocked: Bool
    var noCommitEvidenceAvailable: Bool
    var realApplyPortReady: Bool
    var commitExecutorReady: Bool
    var rollbackPlanReady: Bool
    var failureInjectionReady: Bool
    var readSideParallelReady: Bool
    var observationReady: Bool
    var antiResurrectionGatePassed: Bool
    var physicalDeleteGuardPassed: Bool
    var permanentDeleteGuardPassed: Bool
    var tombstoneGCGuardPassed: Bool
    var conflictConservativePolicyPassed: Bool
    var duplicateSuppressionPolicyDisabledBecauseN0: Bool
    var legacyFallbackAvailable: Bool

    nonisolated init(
        missingReasons: [CanonicalTombstoneConflictGuardedSeamFailure],
        matrixReport: CanonicalMigrationMatrixReport,
        canaryPolicy: CanonicalTombstoneConflictCanaryPolicy,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        candidateCount: Int,
        eligibleCandidateCount: Int,
        legacyActionCandidateCount: Int,
        staleLiveMetadataRiskCount: Int,
        activeVsTombstoneConflictCount: Int,
        generatedArtifactTombstonedParentApplyBlocked: Bool,
        noCommitEvidenceAvailable: Bool,
        realApplyPortReady: Bool,
        commitExecutorReady: Bool,
        rollbackPlanReady: Bool,
        failureInjectionReady: Bool,
        readSideParallelReady: Bool,
        observationReady: Bool,
        antiResurrectionGatePassed: Bool,
        physicalDeleteGuardPassed: Bool,
        permanentDeleteGuardPassed: Bool,
        tombstoneGCGuardPassed: Bool,
        conflictConservativePolicyPassed: Bool,
        duplicateSuppressionPolicyDisabledBecauseN0: Bool,
        legacyFallbackAvailable: Bool
    ) {
        let normalizedReasons = Array(Set(missingReasons)).sorted { $0.rawValue < $1.rawValue }
        self.status = normalizedReasons.isEmpty ? .complete : .incomplete
        self.missingReasons = normalizedReasons
        self.matrixReport = matrixReport
        self.canaryPolicy = canaryPolicy
        self.localSnapshotAvailable = localSnapshotAvailable
        self.peerSnapshotAvailable = peerSnapshotAvailable
        self.candidateCount = max(0, candidateCount)
        self.eligibleCandidateCount = max(0, eligibleCandidateCount)
        self.legacyActionCandidateCount = max(0, legacyActionCandidateCount)
        self.staleLiveMetadataRiskCount = max(0, staleLiveMetadataRiskCount)
        self.activeVsTombstoneConflictCount = max(0, activeVsTombstoneConflictCount)
        self.generatedArtifactTombstonedParentApplyBlocked = generatedArtifactTombstonedParentApplyBlocked
        self.noCommitEvidenceAvailable = noCommitEvidenceAvailable
        self.realApplyPortReady = realApplyPortReady
        self.commitExecutorReady = commitExecutorReady
        self.rollbackPlanReady = rollbackPlanReady
        self.failureInjectionReady = failureInjectionReady
        self.readSideParallelReady = readSideParallelReady
        self.observationReady = observationReady
        self.antiResurrectionGatePassed = antiResurrectionGatePassed
        self.physicalDeleteGuardPassed = physicalDeleteGuardPassed
        self.permanentDeleteGuardPassed = permanentDeleteGuardPassed
        self.tombstoneGCGuardPassed = tombstoneGCGuardPassed
        self.conflictConservativePolicyPassed = conflictConservativePolicyPassed
        self.duplicateSuppressionPolicyDisabledBecauseN0 = duplicateSuppressionPolicyDisabledBecauseN0
        self.legacyFallbackAvailable = legacyFallbackAvailable
    }

    nonisolated var diagnosticsSummary: String {
        [
            "status=\(status.rawValue)",
            "missingReasons=\(missingReasons.map(\.rawValue).joined(separator: "+"))",
            "activePilot=\(matrixReport.activePilotDomain?.rawValue ?? "none")",
            "matrixAllowed=\(matrixReport.allowed)",
            "candidateCount=\(candidateCount)",
            "eligibleCandidateCount=\(eligibleCandidateCount)",
            "legacyActionCandidateCount=\(legacyActionCandidateCount)",
            "staleLiveMetadataRiskCount=\(staleLiveMetadataRiskCount)",
            "activeVsTombstoneConflictCount=\(activeVsTombstoneConflictCount)",
            "generatedArtifactTombstonedParentApplyBlocked=\(generatedArtifactTombstonedParentApplyBlocked)",
            "localSnapshotAvailable=\(localSnapshotAvailable)",
            "peerSnapshotAvailable=\(peerSnapshotAvailable)",
            "canaryMaxObjectsPerSyncRun=\(canaryPolicy.canaryMaxObjectsPerSyncRun)",
            "requestedStage=\(canaryPolicy.requestedStage.rawValue)",
            "allowCandidateExecution=\(canaryPolicy.allowCandidateExecution)",
            "runtimeSwitchEnabled=\(canaryPolicy.runtimeSwitchEnabled)",
            "noCommitEvidenceAvailable=\(noCommitEvidenceAvailable)",
            "realApplyPortReady=\(realApplyPortReady)",
            "commitExecutorReady=\(commitExecutorReady)",
            "rollbackPlanReady=\(rollbackPlanReady)",
            "failureInjectionReady=\(failureInjectionReady)",
            "readSideParallelReady=\(readSideParallelReady)",
            "observationReady=\(observationReady)",
            "antiResurrectionGatePassed=\(antiResurrectionGatePassed)",
            "physicalDeleteGuardPassed=\(physicalDeleteGuardPassed)",
            "permanentDeleteGuardPassed=\(permanentDeleteGuardPassed)",
            "tombstoneGCGuardPassed=\(tombstoneGCGuardPassed)",
            "conflictConservativePolicyPassed=\(conflictConservativePolicyPassed)",
            "duplicateSuppressionPolicyDisabledBecauseN0=\(duplicateSuppressionPolicyDisabledBecauseN0)",
            "legacyFallbackAvailable=\(legacyFallbackAvailable)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalTombstoneConflictN1ReadinessStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForN1AfterAudit
    case noEligibleCandidate
    case insufficientPeerSnapshot
    case insufficientEvidence
    case blocked
}

nonisolated enum CanonicalTombstoneConflictN1NextRecommendedStage: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case n1AfterAudit
    case fixBlockers
    case remainStatic
}

nonisolated enum CanonicalTombstoneConflictN1Blocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case explicitN1EnablementRequired
    case localSnapshotUnavailable
    case peerSnapshotUnavailable
    case matrixBlocked
    case activePilotNotTombstoneConflict
    case ownerApprovalMissing
    case noEligibleCandidate
    case missingNoCommitEvidence
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingMetadataRouteEvidence
    case missingRealApplyPort
    case missingCommitExecutor
    case missingRollbackPlan
    case missingRollbackVerification
    case missingFailureInjection
    case missingLegacyFallback
    case missingReadSideParallel
    case missingObservationEvidence
    case missingAntiResurrectionGate
    case missingPhysicalDeleteGuard
    case missingPermanentDeleteGuard
    case missingTombstoneGCGuard
    case missingConflictConservativePolicy
    case physicalDeleteBlocked
    case permanentDeleteBlocked
    case tombstoneGCBlocked
    case staleLiveResurrectionRisk
    case unsupportedRestore
    case autoConflictResolutionBlocked
    case conflictPolicyAmbiguous
    case generatedArtifactTombstonedParentBlocked
    case canaryBudgetMustRemainZeroForV827
    case executableStagePolicyDeniedForV827
    case duplicateSuppressionMustRemainDisabled
}

nonisolated struct CanonicalTombstoneConflictN1ReadinessReport: Codable, Equatable, Sendable {
    var status: CanonicalTombstoneConflictN1ReadinessStatus
    var gateResult: CanonicalTombstoneConflictGateResult
    var activePilot: CanonicalMigrationDomain?
    var gateAllowed: Bool
    var canaryBudget: Int
    var canExecuteNow: Bool
    var willExecuteNow: Bool
    var missingEvidenceList: [CanonicalTombstoneConflictGuardedSeamFailure]
    var blockerList: [CanonicalTombstoneConflictN1Blocker]
    var n1CandidateCountEstimate: Int
    var safeCandidateKinds: [String]
    var unsafeCandidateKinds: [String]
    var nextRecommendedStage: CanonicalTombstoneConflictN1NextRecommendedStage
    var noExecutionAssertionPassed: Bool
    var diagnosticsSummary: String

    nonisolated init(
        activePilot: CanonicalMigrationDomain?,
        gateAllowed: Bool,
        gateResult: CanonicalTombstoneConflictGateResult,
        blockers: [CanonicalTombstoneConflictN1Blocker],
        missingEvidenceList: [CanonicalTombstoneConflictGuardedSeamFailure],
        candidateCount: Int,
        eligibleCandidateCount: Int,
        canaryBudget: Int,
        canExecuteNow: Bool,
        willExecuteNow: Bool,
        noExecutionAssertionPassed: Bool
    ) {
        let normalizedBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let normalizedMissing = Array(Set(missingEvidenceList)).sorted { $0.rawValue < $1.rawValue }
        self.activePilot = activePilot
        self.gateAllowed = gateAllowed
        self.canaryBudget = max(0, canaryBudget)
        self.canExecuteNow = canExecuteNow
        self.willExecuteNow = willExecuteNow
        self.missingEvidenceList = normalizedMissing
        self.blockerList = normalizedBlockers
        self.n1CandidateCountEstimate = max(0, eligibleCandidateCount)
        self.safeCandidateKinds = [
            "objectSoftTombstoneMarkerApplySend",
            "librarySoftTombstoneMarkerApplySend",
            "conflictRecordOnly",
            "resurrectionBlockRecordOnly"
        ]
        self.unsafeCandidateKinds = [
            "physicalDelete",
            "permanentDelete",
            "tombstoneGC",
            "restoreWithoutExplicitRestoreSignal",
            "autoConflictResolution",
            "staleLiveMetadataApplyOverTombstone",
            "generatedArtifactApplyOnTombstonedParent"
        ]
        self.noExecutionAssertionPassed = noExecutionAssertionPassed
        if normalizedBlockers.contains(.peerSnapshotUnavailable) {
            self.status = .insufficientPeerSnapshot
        } else if normalizedBlockers.contains(.noEligibleCandidate) {
            self.status = .noEligibleCandidate
        } else if normalizedBlockers.contains(where: { !$0.isV827PolicyOnly }) || !normalizedMissing.isEmpty {
            self.status = .insufficientEvidence
        } else if eligibleCandidateCount > 0 {
            self.status = .readyForN1AfterAudit
        } else {
            self.status = .blocked
        }
        self.gateResult = self.status == .readyForN1AfterAudit ? .readyForN1AfterAudit : gateResult
        switch self.status {
        case .readyForN1AfterAudit:
            self.nextRecommendedStage = .n1AfterAudit
        case .noEligibleCandidate:
            self.nextRecommendedStage = .remainStatic
        case .insufficientPeerSnapshot, .insufficientEvidence, .blocked:
            self.nextRecommendedStage = .fixBlockers
        }
        self.diagnosticsSummary = [
            "status=\(status.rawValue)",
            "gateResult=\(self.gateResult.rawValue)",
            "activePilot=\(activePilot?.rawValue ?? "none")",
            "gateAllowed=\(gateAllowed)",
            "blockers=\(normalizedBlockers.map(\.rawValue).joined(separator: "+"))",
            "missingEvidence=\(normalizedMissing.map(\.rawValue).joined(separator: "+"))",
            "candidateCount=\(max(0, candidateCount))",
            "n1CandidateCountEstimate=\(self.n1CandidateCountEstimate)",
            "canaryBudget=\(self.canaryBudget)",
            "canExecuteNow=\(canExecuteNow)",
            "willExecuteNow=\(willExecuteNow)",
            "nextRecommendedStage=\(nextRecommendedStage.rawValue)",
            "noExecutionAssertionPassed=\(noExecutionAssertionPassed)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalTombstoneConflictNoExecutionViolation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case willExecuteNow
    case commitExecutorCalled
    case realApplyPortCalled
    case tombstoneMarkerWritten
    case tombstoneCleared
    case restoreAttempted
    case physicalDeleteAttempted
    case permanentDeleteAttempted
    case tombstoneGCAttempted
    case conflictResolutionAttempted
    case receiveJSONMutated
    case generatedArtifactAppliedOrDownloaded
    case duplicateLegacySuppressed
    case legacyFallbackNotPreserved
    case runtimeSwitchEnabled
    case legacyPlanChanged
    case productionPlanChanged
    case uiMutated
    case macInventoryResponseMutated
    case audioInboxWritten
    case transcriptionOrNoteGenerationTriggered
    case uploadJobCreated
    case networkRequestCalled
    case pendingCountsChanged
    case routeBehaviorChanged
    case requestVerifierBypassed
}

nonisolated struct CanonicalTombstoneConflictNoExecutionAssertion: Codable, Equatable, Sendable {
    var passed: Bool
    var violations: [CanonicalTombstoneConflictNoExecutionViolation]

    nonisolated static func evaluate(
        _ result: CanonicalTombstoneConflictGuardedSeamResult
    ) -> CanonicalTombstoneConflictNoExecutionAssertion {
        var violations: [CanonicalTombstoneConflictNoExecutionViolation] = []
        if result.willExecuteNow { violations.append(.willExecuteNow) }
        if result.commitExecutorCalled || result.commitAttemptedCount != 0 { violations.append(.commitExecutorCalled) }
        if result.realApplyPortCalled { violations.append(.realApplyPortCalled) }
        if result.tombstoneMarkerWriteAttempted || result.tombstoneMarkerWrittenCount != 0 { violations.append(.tombstoneMarkerWritten) }
        if result.tombstoneClearAttempted { violations.append(.tombstoneCleared) }
        if result.restoreAttemptedCount != 0 { violations.append(.restoreAttempted) }
        if result.physicalDeleteAttemptedCount != 0 { violations.append(.physicalDeleteAttempted) }
        if result.permanentDeleteAttemptedCount != 0 { violations.append(.permanentDeleteAttempted) }
        if result.tombstoneGCAttemptedCount != 0 { violations.append(.tombstoneGCAttempted) }
        if result.conflictResolutionAttemptedCount != 0 { violations.append(.conflictResolutionAttempted) }
        if result.receiveJSONMutated { violations.append(.receiveJSONMutated) }
        if result.generatedArtifactApplyOrDownloadCausedByTombstonedObject { violations.append(.generatedArtifactAppliedOrDownloaded) }
        if !result.duplicateLegacySuppressedActionIDs.isEmpty { violations.append(.duplicateLegacySuppressed) }
        if !result.legacyFallbackPreserved { violations.append(.legacyFallbackNotPreserved) }
        if result.runtimeSwitchEnabled { violations.append(.runtimeSwitchEnabled) }
        if !result.legacyPlanUnchanged { violations.append(.legacyPlanChanged) }
        if !result.productionPlanUnchanged { violations.append(.productionPlanChanged) }
        if result.uiMutated { violations.append(.uiMutated) }
        if result.macInventoryResponseMutated { violations.append(.macInventoryResponseMutated) }
        if result.audioInboxWritten { violations.append(.audioInboxWritten) }
        if result.transcriptionOrNoteGenerationTriggered { violations.append(.transcriptionOrNoteGenerationTriggered) }
        if result.uploadJobCreated { violations.append(.uploadJobCreated) }
        if result.networkRequestCalled { violations.append(.networkRequestCalled) }
        if result.pendingCountsChanged { violations.append(.pendingCountsChanged) }
        if result.routeBehaviorChanged { violations.append(.routeBehaviorChanged) }
        if result.requestVerifierBypassed { violations.append(.requestVerifierBypassed) }
        let uniqueViolations = Array(Set(violations)).sorted { $0.rawValue < $1.rawValue }
        return CanonicalTombstoneConflictNoExecutionAssertion(
            passed: uniqueViolations.isEmpty,
            violations: uniqueViolations
        )
    }
}

nonisolated struct CanonicalTombstoneConflictGuardedContext: Codable, Equatable, Sendable {
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var localManifest: CanonicalManifest?
    var peerManifest: CanonicalManifest?
    var candidates: [CanonicalTombstoneConflictCandidate]
    var legacyActionSnapshot: CanonicalLegacyActionSnapshot
    var matrix: CanonicalMigrationDomainMatrix
    var evidence: CanonicalTombstoneConflictCutoverEvidence
    var canaryPolicy: CanonicalTombstoneConflictCanaryPolicy
    var cutoverToken: CanonicalCutoverToken?
    var localSnapshotAvailable: Bool
    var peerSnapshotAvailable: Bool
    var commitExecutorReady: Bool
    var failureInjectionReady: Bool
    var readSideParallelReady: Bool
    var observationReady: Bool
    var antiResurrectionGatePassed: Bool
    var physicalDeleteGuardPassed: Bool
    var permanentDeleteGuardPassed: Bool
    var tombstoneGCGuardPassed: Bool
    var conflictConservativePolicyPassed: Bool
    var staleLiveMetadataRiskCount: Int
    var activeVsTombstoneConflictCount: Int
    var generatedArtifactTombstonedParentApplyBlocked: Bool
    var duplicateSuppressionPolicyAvailable: Bool
    var legacyFallbackAvailable: Bool

    nonisolated init(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?,
        candidates: [CanonicalTombstoneConflictCandidate] = [],
        legacyActionSnapshot: CanonicalLegacyActionSnapshot = .empty,
        matrix: CanonicalMigrationDomainMatrix = .v827TombstoneConflictActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            generatedArtifactsTemplateCompleteOrObservationReady: true
        ),
        evidence: CanonicalTombstoneConflictCutoverEvidence,
        canaryPolicy: CanonicalTombstoneConflictCanaryPolicy = .disabled,
        cutoverToken: CanonicalCutoverToken? = nil,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        commitExecutorReady: Bool = true,
        failureInjectionReady: Bool = true,
        readSideParallelReady: Bool? = nil,
        observationReady: Bool = true,
        antiResurrectionGatePassed: Bool = true,
        physicalDeleteGuardPassed: Bool = true,
        permanentDeleteGuardPassed: Bool = true,
        tombstoneGCGuardPassed: Bool = true,
        conflictConservativePolicyPassed: Bool = true,
        staleLiveMetadataRiskCount: Int? = nil,
        activeVsTombstoneConflictCount: Int? = nil,
        generatedArtifactTombstonedParentApplyBlocked: Bool? = nil,
        duplicateSuppressionPolicyAvailable: Bool = true,
        legacyFallbackAvailable: Bool? = nil
    ) {
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.localManifest = localManifest
        self.peerManifest = peerManifest
        self.candidates = candidates
        self.legacyActionSnapshot = legacyActionSnapshot
        self.matrix = matrix
        self.evidence = evidence
        self.canaryPolicy = canaryPolicy
        self.cutoverToken = cutoverToken
        self.localSnapshotAvailable = localSnapshotAvailable
        self.peerSnapshotAvailable = peerSnapshotAvailable
        self.commitExecutorReady = commitExecutorReady
        self.failureInjectionReady = failureInjectionReady
        self.readSideParallelReady = readSideParallelReady ?? evidence.readSideParallelEquivalent
        self.observationReady = observationReady
        self.antiResurrectionGatePassed = antiResurrectionGatePassed
        self.physicalDeleteGuardPassed = physicalDeleteGuardPassed
        self.permanentDeleteGuardPassed = permanentDeleteGuardPassed
        self.tombstoneGCGuardPassed = tombstoneGCGuardPassed
        self.conflictConservativePolicyPassed = conflictConservativePolicyPassed
        self.staleLiveMetadataRiskCount = max(0, staleLiveMetadataRiskCount ?? candidates.filter(\.staleLiveMetadataRisk).count)
        self.activeVsTombstoneConflictCount = max(0, activeVsTombstoneConflictCount ?? candidates.filter {
            $0.hasActiveVsTombstoneConflict || $0.domain == .activeVsTombstoneConflict || $0.actionKind == .resurrectionBlocked
        }.count)
        self.generatedArtifactTombstonedParentApplyBlocked = generatedArtifactTombstonedParentApplyBlocked
            ?? candidates.contains { $0.actionKind == .generatedArtifactTombstoneMarkUnsupported }
        self.duplicateSuppressionPolicyAvailable = duplicateSuppressionPolicyAvailable
        self.legacyFallbackAvailable = legacyFallbackAvailable ?? evidence.legacyFallbackAvailable
    }
}

nonisolated struct CanonicalTombstoneConflictGuardedSeamResult: Codable, Equatable, Sendable {
    var gate: CanonicalTombstoneConflictGuardedGate
    var evidenceReport: CanonicalTombstoneConflictEvidenceReport
    var n1ReadinessReport: CanonicalTombstoneConflictN1ReadinessReport
    var diagnostics: [CanonicalTombstoneConflictGuardedDiagnostic]
    var noExecutionAssertion: CanonicalTombstoneConflictNoExecutionAssertion
    var canaryBudgetZero: Bool
    var canExecuteNow: Bool
    var willExecuteNow: Bool
    var commitAttemptedCount: Int
    var tombstoneMarkerWrittenCount: Int
    var restoreAttemptedCount: Int
    var physicalDeleteAttemptedCount: Int
    var permanentDeleteAttemptedCount: Int
    var tombstoneGCAttemptedCount: Int
    var conflictResolutionAttemptedCount: Int
    var commitExecutorCalled: Bool
    var realApplyPortCalled: Bool
    var tombstoneMarkerWriteAttempted: Bool
    var tombstoneClearAttempted: Bool
    var receiveJSONMutated: Bool
    var generatedArtifactApplyOrDownloadCausedByTombstonedObject: Bool
    var duplicateLegacySuppressedActionIDs: [String]
    var duplicateLegacySuppressionCandidates: [String]
    var legacyFallbackPreserved: Bool
    var runtimeSwitchEnabled: Bool
    var legacyPlanUnchanged: Bool
    var productionPlanUnchanged: Bool
    var uiMutated: Bool
    var macInventoryResponseMutated: Bool
    var audioInboxWritten: Bool
    var transcriptionOrNoteGenerationTriggered: Bool
    var uploadJobCreated: Bool
    var networkRequestCalled: Bool
    var pendingCountsChanged: Bool
    var routeBehaviorChanged: Bool
    var requestVerifierBypassed: Bool
    var nonfatalFailureCount: Int

    nonisolated var succeeded: Bool {
        gate.allowed && canaryBudgetZero && !willExecuteNow && noExecutionAssertion.passed
    }
}

nonisolated struct CanonicalTombstoneConflictGuardedSeam: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        configuration: CanonicalTombstoneConflictCutoverAppSeamConfiguration,
        context: CanonicalTombstoneConflictGuardedContext
    ) -> CanonicalTombstoneConflictGuardedSeamResult {
        let canaryPolicy = configuration.policy.canaryPolicy
        let duplicateCandidates = duplicateSuppressionCandidates(context)
        let evidenceReport = makeEvidenceReport(
            context: context,
            canaryPolicy: canaryPolicy,
            duplicateCandidates: duplicateCandidates
        )
        let canaryBudgetZero = Self.isCanaryBudgetZero(canaryPolicy)
        let gate = evaluateGate(
            configuration: configuration,
            context: context,
            evidenceReport: evidenceReport,
            canaryPolicy: canaryPolicy,
            canaryBudgetZero: canaryBudgetZero
        )
        let eligibleCandidateCount = eligibleCandidateCount(context.candidates)
        let canExecuteNow = gate.allowed
        let willExecuteNow = false
        let emptyAssertion = CanonicalTombstoneConflictNoExecutionAssertion(passed: true, violations: [])
        let preliminaryReadiness = makeN1ReadinessReport(
            context: context,
            evidenceReport: evidenceReport,
            gate: gate,
            canaryPolicy: canaryPolicy,
            canExecuteNow: canExecuteNow,
            willExecuteNow: willExecuteNow,
            noExecutionAssertionPassed: emptyAssertion.passed
        )
        var diagnostics = baseDiagnostics(
            configuration: configuration,
            context: context,
            gate: gate,
            evidenceReport: evidenceReport,
            n1ReadinessReport: preliminaryReadiness,
            candidateCount: context.candidates.count,
            eligibleCandidateCount: eligibleCandidateCount,
            duplicateSuppressionCandidateCount: duplicateCandidates.count,
            canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
            canaryBudgetZero: canaryBudgetZero,
            willExecuteNow: willExecuteNow
        )
        var result = CanonicalTombstoneConflictGuardedSeamResult(
            gate: gate,
            evidenceReport: evidenceReport,
            n1ReadinessReport: preliminaryReadiness,
            diagnostics: Array(diagnostics.prefix(configuration.policy.maxDiagnosticsEvents)),
            noExecutionAssertion: emptyAssertion,
            canaryBudgetZero: canaryBudgetZero,
            canExecuteNow: canExecuteNow,
            willExecuteNow: willExecuteNow,
            commitAttemptedCount: 0,
            tombstoneMarkerWrittenCount: 0,
            restoreAttemptedCount: 0,
            physicalDeleteAttemptedCount: 0,
            permanentDeleteAttemptedCount: 0,
            tombstoneGCAttemptedCount: 0,
            conflictResolutionAttemptedCount: 0,
            commitExecutorCalled: false,
            realApplyPortCalled: false,
            tombstoneMarkerWriteAttempted: false,
            tombstoneClearAttempted: false,
            receiveJSONMutated: false,
            generatedArtifactApplyOrDownloadCausedByTombstonedObject: false,
            duplicateLegacySuppressedActionIDs: [],
            duplicateLegacySuppressionCandidates: duplicateCandidates,
            legacyFallbackPreserved: true,
            runtimeSwitchEnabled: false,
            legacyPlanUnchanged: true,
            productionPlanUnchanged: true,
            uiMutated: false,
            macInventoryResponseMutated: false,
            audioInboxWritten: false,
            transcriptionOrNoteGenerationTriggered: false,
            uploadJobCreated: false,
            networkRequestCalled: false,
            pendingCountsChanged: false,
            routeBehaviorChanged: false,
            requestVerifierBypassed: false,
            nonfatalFailureCount: gate.failures.count
        )
        let assertion = CanonicalTombstoneConflictNoExecutionAssertion.evaluate(result)
        result.noExecutionAssertion = assertion
        result.n1ReadinessReport = makeN1ReadinessReport(
            context: context,
            evidenceReport: evidenceReport,
            gate: gate,
            canaryPolicy: canaryPolicy,
            canExecuteNow: canExecuteNow,
            willExecuteNow: willExecuteNow,
            noExecutionAssertionPassed: assertion.passed
        )
        diagnostics = baseDiagnostics(
            configuration: configuration,
            context: context,
            gate: gate,
            evidenceReport: evidenceReport,
            n1ReadinessReport: result.n1ReadinessReport,
            candidateCount: context.candidates.count,
            eligibleCandidateCount: eligibleCandidateCount,
            duplicateSuppressionCandidateCount: duplicateCandidates.count,
            canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
            canaryBudgetZero: canaryBudgetZero,
            willExecuteNow: willExecuteNow
        )
        result.diagnostics = Array(diagnostics.prefix(configuration.policy.maxDiagnosticsEvents))
        return result
    }

    private nonisolated func evaluateGate(
        configuration: CanonicalTombstoneConflictCutoverAppSeamConfiguration,
        context: CanonicalTombstoneConflictGuardedContext,
        evidenceReport: CanonicalTombstoneConflictEvidenceReport,
        canaryPolicy: CanonicalTombstoneConflictCanaryPolicy,
        canaryBudgetZero: Bool
    ) -> CanonicalTombstoneConflictGuardedGate {
        var failures: [CanonicalTombstoneConflictGuardedSeamFailure] = []
        let mode = configuration.effectiveMode
        if mode == .disabled {
            failures.append(.disabled)
        }
        switch mode {
        case .disabled:
            break
        case .guardedExecuteCommit, .canaryCommit:
            break
        case .guardedExecuteNoCommit:
            failures.append(.unsupportedMode)
        case .productionExecute:
            failures.append(.productionExecuteDenied)
            failures.append(.unsupportedMode)
        }
        if context.trigger == .viewRefresh {
            failures.append(.viewRefreshTriggerDenied)
        }
        if context.trigger == .retryDrainer {
            failures.append(.retryDrainerFreshTombstoneConflictDenied)
        }
        if !context.localSnapshotAvailable || context.localManifest == nil {
            failures.append(.insufficientLocalSnapshot)
        }
        if !context.peerSnapshotAvailable || context.peerManifest == nil {
            failures.append(.insufficientPeerSnapshot)
        }
        if !evidenceReport.matrixReport.allowed {
            failures.append(.matrixValidationBlocked)
        }
        if evidenceReport.matrixReport.activePilotDomain != .tombstoneConflict {
            failures.append(.activePilotNotTombstoneConflict)
        }
        if context.cutoverToken == nil {
            failures.append(.missingToken)
        }
        if context.cutoverToken?.ownerApproved != true {
            failures.append(.missingOwnerApproval)
        }
        if canaryPolicy.canaryMaxObjectsPerSyncRun > 0 {
            failures.append(.canaryBudgetNonZeroDenied)
        }
        if canaryPolicy.requestedStage.isExecutable || canaryPolicy.allowCandidateExecution {
            failures.append(.canaryStageExecutionDenied)
        }
        if canaryPolicy.runtimeSwitchEnabled {
            failures.append(.runtimeSwitchDenied)
        }
        failures.append(contentsOf: evidenceReport.missingReasons)
        return CanonicalTombstoneConflictGuardedGate(
            mode: mode,
            failures: failures,
            canaryBudgetZero: canaryBudgetZero,
            reason: failures.isEmpty ? "canonicalTombstoneConflictV827GateAllowedBudgetZero" : failures.map(\.rawValue).joined(separator: ",")
        )
    }

    private nonisolated func makeEvidenceReport(
        context: CanonicalTombstoneConflictGuardedContext,
        canaryPolicy: CanonicalTombstoneConflictCanaryPolicy,
        duplicateCandidates: [String]
    ) -> CanonicalTombstoneConflictEvidenceReport {
        let evidence = context.evidence
        let matrixReport = context.matrix.validate()
        let candidateFailures = candidateFailures(context.candidates)
        let requiredDomains = Set(context.candidates.filter(\.actionKind.isExecutable).map(\.domain.productionDomain))
        let rollbackPlanReady = requiredDomains.isEmpty
            ? (evidence.rollbackPlan != nil)
            : requiredDomains.allSatisfy { evidence.rollbackPlan?.covers(domain: $0) == true }
        let realApplyPortReady = evidence.realRootBoundApplyPortAvailable
            && evidence.applyPortMode.isNonDryRunRootBound
            && evidence.rootBoundWriteAvailable
        var missing: [CanonicalTombstoneConflictGuardedSeamFailure] = []
        if !evidence.noCommitEvidenceAvailable { missing.append(.missingNoCommitEvidence) }
        if !evidence.realDataShadowCopyVerified { missing.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.executionShadowVerified { missing.append(.missingExecutionShadowEvidence) }
        if !evidence.dryRunEquivalenceVerified { missing.append(.missingDryRunEquivalence) }
        if !evidence.noBlockingDivergence { missing.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict { missing.append(.unresolvedConflict) }
        if !evidence.metadataRouteEvidenceAvailable { missing.append(.missingMetadataRouteEvidence) }
        if !evidence.productionPortAvailable { missing.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { missing.append(.realApplyPortUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { missing.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { missing.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { missing.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { missing.append(.rollbackCheckpointUnavailable) }
        if !rollbackPlanReady { missing.append(.missingRollback) }
        if !evidence.rollbackVerified { missing.append(.rollbackVerificationMissing) }
        if !evidence.productionRootDisabledByDefault { missing.append(.productionRootEnabledByDefault) }
        if evidence.applyPortMode == .testRootBound && !evidence.testRootUsed { missing.append(.testRootMissing) }
        if !evidence.softTombstoneStoreSupported { missing.append(.softTombstoneStoreUnsupported) }
        if context.candidates.contains(where: { $0.domain.requiresConflictLedger }) && !evidence.conflictLedgerSupported {
            missing.append(.conflictLedgerUnsupported)
        }
        if !evidence.tombstoneWinsIfNewerPolicyAvailable { missing.append(.missingTombstoneWinsPolicy) }
        if !evidence.rollbackEvidenceAvailable { missing.append(.missingRollbackEvidence) }
        if !context.legacyFallbackAvailable { missing.append(.legacyFallbackUnavailable) }
        if !context.commitExecutorReady { missing.append(.commitExecutorUnavailable) }
        if !context.failureInjectionReady { missing.append(.missingFailureInjectionEvidence) }
        if !context.readSideParallelReady { missing.append(.missingReadSideParallel) }
        if !context.observationReady { missing.append(.missingObservationEvidence) }
        if !context.antiResurrectionGatePassed { missing.append(.missingAntiResurrectionGate) }
        if !context.physicalDeleteGuardPassed { missing.append(.missingPhysicalDeleteGuard) }
        if !context.permanentDeleteGuardPassed { missing.append(.missingPermanentDeleteGuard) }
        if !context.tombstoneGCGuardPassed { missing.append(.missingTombstoneGCGuard) }
        if !context.conflictConservativePolicyPassed { missing.append(.missingConflictConservativePolicy) }
        if !context.duplicateSuppressionPolicyAvailable { missing.append(.duplicateSuppressionPolicyUnavailable) }
        if !Self.isCanaryBudgetZero(canaryPolicy) { missing.append(.duplicateSuppressionPolicyEnabled) }
        missing.append(contentsOf: candidateFailures)
        return CanonicalTombstoneConflictEvidenceReport(
            missingReasons: missing,
            matrixReport: matrixReport,
            canaryPolicy: canaryPolicy,
            localSnapshotAvailable: context.localSnapshotAvailable,
            peerSnapshotAvailable: context.peerSnapshotAvailable,
            candidateCount: context.candidates.count,
            eligibleCandidateCount: eligibleCandidateCount(context.candidates),
            legacyActionCandidateCount: duplicateCandidates.count,
            staleLiveMetadataRiskCount: context.staleLiveMetadataRiskCount,
            activeVsTombstoneConflictCount: context.activeVsTombstoneConflictCount,
            generatedArtifactTombstonedParentApplyBlocked: context.generatedArtifactTombstonedParentApplyBlocked,
            noCommitEvidenceAvailable: evidence.noCommitEvidenceAvailable,
            realApplyPortReady: realApplyPortReady,
            commitExecutorReady: context.commitExecutorReady,
            rollbackPlanReady: rollbackPlanReady,
            failureInjectionReady: context.failureInjectionReady,
            readSideParallelReady: context.readSideParallelReady,
            observationReady: context.observationReady,
            antiResurrectionGatePassed: context.antiResurrectionGatePassed,
            physicalDeleteGuardPassed: context.physicalDeleteGuardPassed,
            permanentDeleteGuardPassed: context.permanentDeleteGuardPassed,
            tombstoneGCGuardPassed: context.tombstoneGCGuardPassed,
            conflictConservativePolicyPassed: context.conflictConservativePolicyPassed,
            duplicateSuppressionPolicyDisabledBecauseN0: Self.isCanaryBudgetZero(canaryPolicy),
            legacyFallbackAvailable: context.legacyFallbackAvailable
        )
    }

    private nonisolated func makeN1ReadinessReport(
        context: CanonicalTombstoneConflictGuardedContext,
        evidenceReport: CanonicalTombstoneConflictEvidenceReport,
        gate: CanonicalTombstoneConflictGuardedGate,
        canaryPolicy: CanonicalTombstoneConflictCanaryPolicy,
        canExecuteNow: Bool,
        willExecuteNow: Bool,
        noExecutionAssertionPassed: Bool
    ) -> CanonicalTombstoneConflictN1ReadinessReport {
        var blockers: [CanonicalTombstoneConflictN1Blocker] = [
            .explicitN1EnablementRequired,
            .canaryBudgetMustRemainZeroForV827,
            .duplicateSuppressionMustRemainDisabled
        ]
        if !context.localSnapshotAvailable || context.localManifest == nil { blockers.append(.localSnapshotUnavailable) }
        if !context.peerSnapshotAvailable || context.peerManifest == nil { blockers.append(.peerSnapshotUnavailable) }
        if !evidenceReport.matrixReport.allowed { blockers.append(.matrixBlocked) }
        if evidenceReport.matrixReport.activePilotDomain != .tombstoneConflict { blockers.append(.activePilotNotTombstoneConflict) }
        if context.cutoverToken?.ownerApproved != true { blockers.append(.ownerApprovalMissing) }
        if !context.evidence.noCommitEvidenceAvailable { blockers.append(.missingNoCommitEvidence) }
        if !context.evidence.realDataShadowCopyVerified { blockers.append(.missingRealDataShadowCopyEvidence) }
        if !context.evidence.executionShadowVerified { blockers.append(.missingExecutionShadowEvidence) }
        if !context.evidence.dryRunEquivalenceVerified { blockers.append(.missingDryRunEquivalence) }
        if !context.evidence.noBlockingDivergence { blockers.append(.blockingDivergence) }
        if !context.evidence.noUnresolvedConflict { blockers.append(.unresolvedConflict) }
        if !context.evidence.metadataRouteEvidenceAvailable { blockers.append(.missingMetadataRouteEvidence) }
        if !evidenceReport.realApplyPortReady { blockers.append(.missingRealApplyPort) }
        if !context.commitExecutorReady { blockers.append(.missingCommitExecutor) }
        if !evidenceReport.rollbackPlanReady { blockers.append(.missingRollbackPlan) }
        if !context.evidence.rollbackVerified { blockers.append(.missingRollbackVerification) }
        if !context.failureInjectionReady { blockers.append(.missingFailureInjection) }
        if !context.legacyFallbackAvailable { blockers.append(.missingLegacyFallback) }
        if !context.readSideParallelReady { blockers.append(.missingReadSideParallel) }
        if !context.observationReady { blockers.append(.missingObservationEvidence) }
        if !context.antiResurrectionGatePassed { blockers.append(.missingAntiResurrectionGate) }
        if !context.physicalDeleteGuardPassed { blockers.append(.missingPhysicalDeleteGuard) }
        if !context.permanentDeleteGuardPassed { blockers.append(.missingPermanentDeleteGuard) }
        if !context.tombstoneGCGuardPassed { blockers.append(.missingTombstoneGCGuard) }
        if !context.conflictConservativePolicyPassed { blockers.append(.missingConflictConservativePolicy) }
        if canaryPolicy.requestedStage.isExecutable || canaryPolicy.allowCandidateExecution {
            blockers.append(.executableStagePolicyDeniedForV827)
        }
        let candidateBlockers = candidateFailures(context.candidates)
        if candidateBlockers.contains(.physicalDeletePathDetected) { blockers.append(.physicalDeleteBlocked) }
        if candidateBlockers.contains(.permanentDeletePathDetected) { blockers.append(.permanentDeleteBlocked) }
        if candidateBlockers.contains(.tombstoneGCPathDetected) { blockers.append(.tombstoneGCBlocked) }
        if candidateBlockers.contains(.staleLiveResurrectionRisk) { blockers.append(.staleLiveResurrectionRisk) }
        if candidateBlockers.contains(.unsupportedRestore) { blockers.append(.unsupportedRestore) }
        if candidateBlockers.contains(.conflictPolicyAmbiguous) { blockers.append(.conflictPolicyAmbiguous) }
        if candidateBlockers.contains(.generatedArtifactTombstonedParentApplyBlocked) { blockers.append(.generatedArtifactTombstonedParentBlocked) }
        let eligibleCandidateCount = eligibleCandidateCount(context.candidates)
        if eligibleCandidateCount == 0 {
            blockers.append(.noEligibleCandidate)
        }
        return CanonicalTombstoneConflictN1ReadinessReport(
            activePilot: evidenceReport.matrixReport.activePilotDomain,
            gateAllowed: gate.allowed,
            gateResult: gate.result,
            blockers: blockers,
            missingEvidenceList: evidenceReport.missingReasons.filter(\.isEvidenceMissing),
            candidateCount: context.candidates.count,
            eligibleCandidateCount: eligibleCandidateCount,
            canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
            canExecuteNow: canExecuteNow,
            willExecuteNow: willExecuteNow,
            noExecutionAssertionPassed: noExecutionAssertionPassed
        )
    }

    private nonisolated func baseDiagnostics(
        configuration: CanonicalTombstoneConflictCutoverAppSeamConfiguration,
        context: CanonicalTombstoneConflictGuardedContext,
        gate: CanonicalTombstoneConflictGuardedGate,
        evidenceReport: CanonicalTombstoneConflictEvidenceReport,
        n1ReadinessReport: CanonicalTombstoneConflictN1ReadinessReport,
        candidateCount: Int,
        eligibleCandidateCount: Int,
        duplicateSuppressionCandidateCount: Int,
        canaryBudget: Int,
        canaryBudgetZero: Bool,
        willExecuteNow: Bool
    ) -> [CanonicalTombstoneConflictGuardedDiagnostic] {
        var diagnostics: [CanonicalTombstoneConflictGuardedDiagnostic] = [
            diagnostic(.canonicalTombstoneConflictV827SeamStarted, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: gate.allowed ? "allowed" : "blocked", reason: gate.reason),
            diagnostic(.canonicalTombstoneConflictV827EvidenceReportBuilt, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: evidenceReport.status.rawValue, reason: evidenceReport.diagnosticsSummary),
            diagnostic(.canonicalTombstoneConflictV827N1ReadinessReportBuilt, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: n1ReadinessReport.status.rawValue, reason: n1ReadinessReport.diagnosticsSummary),
            diagnostic(.canonicalTombstoneConflictV827GateEvaluated, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: gate.result.rawValue, reason: gate.reason)
        ]
        diagnostics.append(
            diagnostic(
                gate.allowed && canaryBudgetZero ? .canonicalTombstoneConflictV827GateAllowedBudgetZero : .canonicalTombstoneConflictV827GateBlocked,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: gate.allowed && canaryBudgetZero ? "allowedBudgetZero" : "blocked",
                reason: gate.reason
            )
        )
        if !gate.allowed {
            diagnostics.append(
                diagnostic(.canonicalTombstoneConflictV827SeamBlocked, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "blocked", reason: gate.failures.map(\.rawValue).joined(separator: ","))
            )
        }
        if canaryBudgetZero {
            diagnostics.append(contentsOf: [
                diagnostic(.canonicalTombstoneConflictV827CanaryBudgetZero, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "canaryBudgetZero", reason: "canonicalTombstoneConflictV827CanaryBudgetZero"),
                diagnostic(.canonicalTombstoneConflictCanaryBudgetZero, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "canaryBudgetZero", reason: "canonicalTombstoneConflictCanaryBudgetZero"),
                diagnostic(.canonicalTombstoneConflictCommitSkippedBecauseCanaryBudgetZero, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "commitSkipped", reason: "canaryBudgetZero"),
                diagnostic(.canonicalTombstoneConflictDeleteSkippedBecauseCanaryBudgetZero, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "deleteSkipped", reason: "canaryBudgetZero"),
                diagnostic(.canonicalTombstoneConflictRestoreSkippedBecauseCanaryBudgetZero, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "restoreSkipped", reason: "canaryBudgetZero"),
                diagnostic(.canonicalTombstoneConflictResolutionSkippedBecauseCanaryBudgetZero, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "resolutionSkipped", reason: "canaryBudgetZero")
            ])
        }
        if gate.allowed && !willExecuteNow {
            diagnostics.append(
                diagnostic(.canonicalTombstoneConflictGateAllowedButNoExecution, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "gateAllowedButNoExecution", reason: canaryBudgetZero ? "canaryBudgetZero" : "executionDeniedForV827")
            )
        }
        diagnostics.append(contentsOf: [
            diagnostic(.canonicalTombstoneConflictV827CommitNotExecuted, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "commitNotExecuted", reason: "v827TombstoneConflictGuardedSeamNZero"),
            diagnostic(.canonicalTombstoneConflictV827DeleteNotExecuted, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "deleteNotExecuted", reason: "noPhysicalDeleteNoPermanentDeleteNoGC"),
            diagnostic(.canonicalTombstoneConflictV827RestoreNotExecuted, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "restoreNotExecuted", reason: "explicitRestoreRequiredFutureOnly"),
            diagnostic(.canonicalTombstoneConflictV827ConflictNotAutoResolved, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "conflictNotAutoResolved", reason: "manualReviewOnly"),
            diagnostic(.canonicalTombstoneConflictV827LegacyFallbackPreserved, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "legacyFallbackPreserved", reason: "v827DoesNotReplaceLegacyTombstoneConflictPlan"),
            diagnostic(.canonicalTombstoneConflictV827DuplicateSuppressionNotApplied, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "duplicateSuppressionNotApplied", reason: "v827NZeroDoesNotSuppressLegacyDuplicates"),
            diagnostic(.canonicalTombstoneConflictV827SeamCompleted, configuration: configuration, context: context, candidateCount: candidateCount, eligibleCandidateCount: eligibleCandidateCount, gateFailureCount: gate.failures.count, canaryBudget: canaryBudget, duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount, result: "completed", reason: gate.allowed ? "nonfatalNoExecution" : "nonfatalBlocked")
        ])
        return diagnostics
    }

    private nonisolated func candidateFailures(
        _ candidates: [CanonicalTombstoneConflictCandidate]
    ) -> [CanonicalTombstoneConflictGuardedSeamFailure] {
        var failures: [CanonicalTombstoneConflictGuardedSeamFailure] = []
        for candidate in candidates {
            if !CanonicalTombstoneConflictDomain.allCases.contains(candidate.domain) {
                failures.append(.unsupportedDomain)
            }
            if candidate.actionKind == .unsupported {
                failures.append(.unsupportedAction)
            }
            if candidate.actionKind.isTombstoneMarkerWrite && candidate.deletedAt == nil {
                failures.append(.missingTombstoneTimestamp)
            }
            if candidate.actionKind.isTombstoneMarkerWrite && !candidate.tombstoneWinsIfNewerPolicy {
                failures.append(.missingTombstoneWinsPolicy)
            }
            if candidate.actionKind.isExecutable && !candidate.rollbackEvidenceAvailable {
                failures.append(.missingRollbackEvidence)
            }
            if candidate.actionKind == .generatedArtifactTombstoneMarkUnsupported {
                failures.append(.generatedArtifactTombstonedParentApplyBlocked)
            }
            if candidate.actionKind == .conflictRecord && !candidate.conflictPolicyKnown {
                failures.append(.conflictPolicyAmbiguous)
            }
            if candidate.wouldRestoreFromAbsenceOnly || (candidate.explicitRestoreSignal == false && candidate.action.reason.lowercased().contains("restore")) {
                failures.append(.unsupportedRestore)
            }
            if candidate.staleLiveMetadataRisk && candidate.actionKind != .resurrectionBlocked {
                failures.append(.staleLiveResurrectionRisk)
            }
            let reason = candidate.action.reason.lowercased()
            if !reason.contains("no") && reason.contains("physicaldelete") {
                failures.append(.physicalDeletePathDetected)
            }
            if reason.contains("permanentdelete") {
                failures.append(.permanentDeletePathDetected)
            }
            if reason.contains("tombstonegc") {
                failures.append(.tombstoneGCPathDetected)
            }
        }
        return Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated func eligibleCandidateCount(
        _ candidates: [CanonicalTombstoneConflictCandidate]
    ) -> Int {
        candidates.filter { candidateFailures([$0]).isEmpty && $0.actionKind.isExecutable }.count
    }

    private nonisolated func duplicateSuppressionCandidates(
        _ context: CanonicalTombstoneConflictGuardedContext
    ) -> [String] {
        let legacyIDs = context.legacyActionSnapshot.actionIDSet(for: .tombstones)
            .union(context.legacyActionSnapshot.actionIDSet(for: .conflicts))
        return context.candidates
            .map(\.action.actionID)
            .filter { legacyIDs.contains($0) }
            .compactMap { CanonicalProductionRedaction.safeDiagnosticText($0) }
            .sorted()
    }

    private nonisolated static func isCanaryBudgetZero(
        _ policy: CanonicalTombstoneConflictCanaryPolicy
    ) -> Bool {
        policy.canaryMaxObjectsPerSyncRun == 0
            && !policy.requestedStage.isExecutable
            && !policy.allowCandidateExecution
            && !policy.runtimeSwitchEnabled
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalTombstoneConflictGuardedDiagnosticKind,
        configuration: CanonicalTombstoneConflictCutoverAppSeamConfiguration,
        context: CanonicalTombstoneConflictGuardedContext,
        candidate: CanonicalTombstoneConflictCandidate? = nil,
        candidateCount: Int,
        eligibleCandidateCount: Int,
        gateFailureCount: Int = 0,
        canaryBudget: Int,
        commitAttemptedCount: Int = 0,
        deleteAttemptedCount: Int = 0,
        restoreAttemptedCount: Int = 0,
        conflictResolutionAttemptedCount: Int = 0,
        duplicateSuppressionCandidateCount: Int = 0,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalTombstoneConflictGuardedDiagnostic {
        CanonicalTombstoneConflictGuardedDiagnostic(
            kind: kind,
            syncRunID: context.syncRunID,
            trigger: context.trigger,
            nodeRole: context.nodeRole,
            mode: configuration.effectiveMode,
            domain: candidate?.domain,
            objectID: candidate?.objectID,
            actionKind: candidate?.actionKind,
            candidateCount: candidateCount,
            eligibleCandidateCount: eligibleCandidateCount,
            gateFailureCount: gateFailureCount,
            canaryBudget: canaryBudget,
            commitAttemptedCount: commitAttemptedCount,
            deleteAttemptedCount: deleteAttemptedCount,
            restoreAttemptedCount: restoreAttemptedCount,
            conflictResolutionAttemptedCount: conflictResolutionAttemptedCount,
            duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
            staleLiveMetadataRiskCount: context.staleLiveMetadataRiskCount,
            activeVsTombstoneConflictCount: context.activeVsTombstoneConflictCount,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}

private extension CanonicalTombstoneConflictGuardedSeamFailure {
    nonisolated var isEvidenceMissing: Bool {
        switch self {
        case .missingNoCommitEvidence,
             .missingRealDataShadowCopyEvidence,
             .missingExecutionShadowEvidence,
             .missingDryRunEquivalence,
             .missingMetadataRouteEvidence,
             .productionPortUnavailable,
             .realApplyPortUnavailable,
             .applyPortDryRunOnly,
             .rootBoundWriteUnavailable,
             .atomicReplaceUnavailable,
             .rollbackCheckpointUnavailable,
             .missingRollback,
             .rollbackVerificationMissing,
             .commitExecutorUnavailable,
             .missingFailureInjectionEvidence,
             .missingReadSideParallel,
             .missingObservationEvidence,
             .missingAntiResurrectionGate,
             .missingPhysicalDeleteGuard,
             .missingPermanentDeleteGuard,
             .missingTombstoneGCGuard,
             .missingConflictConservativePolicy,
             .softTombstoneStoreUnsupported,
             .conflictLedgerUnsupported,
             .missingTombstoneWinsPolicy,
             .missingRollbackEvidence,
             .missingTombstoneTimestamp:
            return true
        case .disabled,
             .unsupportedMode,
             .productionExecuteDenied,
             .viewRefreshTriggerDenied,
             .retryDrainerFreshTombstoneConflictDenied,
             .insufficientLocalSnapshot,
             .insufficientPeerSnapshot,
             .matrixValidationBlocked,
             .activePilotNotTombstoneConflict,
             .unsupportedDomain,
             .unsupportedAction,
             .missingToken,
             .missingOwnerApproval,
             .blockingDivergence,
             .unresolvedConflict,
             .productionRootEnabledByDefault,
             .testRootMissing,
             .legacyFallbackUnavailable,
             .physicalDeletePathDetected,
             .permanentDeletePathDetected,
             .tombstoneGCPathDetected,
             .unsupportedRestore,
             .staleLiveResurrectionRisk,
             .conflictPolicyAmbiguous,
             .generatedArtifactTombstonedParentApplyBlocked,
             .duplicateSuppressionPolicyUnavailable,
             .duplicateSuppressionPolicyEnabled,
             .canaryBudgetNonZeroDenied,
             .canaryStageExecutionDenied,
             .runtimeSwitchDenied:
            return false
        }
    }
}

private extension CanonicalTombstoneConflictN1Blocker {
    nonisolated var isV827PolicyOnly: Bool {
        switch self {
        case .explicitN1EnablementRequired,
             .canaryBudgetMustRemainZeroForV827,
             .duplicateSuppressionMustRemainDisabled:
            return true
        default:
            return false
        }
    }
}
