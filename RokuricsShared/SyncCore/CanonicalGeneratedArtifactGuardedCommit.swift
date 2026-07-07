//
//  CanonicalGeneratedArtifactGuardedCommit.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated enum CanonicalGeneratedArtifactPilotActivationBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case templateNotReadyForNextPilotN0
    case libraryMetadataObservationMissing
    case matrixValidationBlocked
    case activePilotNotGeneratedArtifacts
    case canaryN0NotReached
    case canaryN1Reached
    case releaseDefaultCutoverEnabled
    case runtimeSwitchEnabled
    case legacySuppressionEnabled
    case readPathNotLegacy
    case productionInjectionPresent
}

nonisolated struct CanonicalGeneratedArtifactPilotActivationResult: Codable, Equatable, Sendable {
    var activated: Bool
    var matrix: CanonicalMigrationDomainMatrix
    var matrixReport: CanonicalMigrationMatrixReport
    var blockers: [CanonicalGeneratedArtifactPilotActivationBlocker]
    var diagnosticsSummary: String

    nonisolated init(
        matrix: CanonicalMigrationDomainMatrix,
        blockers: [CanonicalGeneratedArtifactPilotActivationBlocker]
    ) {
        let matrixReport = matrix.validate()
        let normalizedBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.matrix = matrix
        self.matrixReport = matrixReport
        self.blockers = normalizedBlockers
        self.activated = normalizedBlockers.isEmpty
            && matrixReport.allowed
            && matrixReport.activePilotDomain == .generatedArtifacts
        self.diagnosticsSummary = [
            "domain=generatedArtifacts",
            "version=v8.22",
            "activated=\(activated)",
            "activePilot=\(matrixReport.activePilotDomain?.rawValue ?? "none")",
            "matrixAllowed=\(matrixReport.allowed)",
            "blockers=\(normalizedBlockers.map(\.rawValue).joined(separator: "+"))"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalGeneratedArtifactPilotActivation: Codable, Equatable, Sendable {
    var templateReport: CanonicalGeneratedArtifactTemplateReport
    var libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool
    var result: CanonicalGeneratedArtifactPilotActivationResult

    nonisolated static func v822(
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool,
        templateReport: CanonicalGeneratedArtifactTemplateReport = .currentV821Audit()
    ) -> CanonicalGeneratedArtifactPilotActivation {
        let result = CanonicalGeneratedArtifactPilotActivationGate().evaluate(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            templateReport: templateReport
        )
        return CanonicalGeneratedArtifactPilotActivation(
            templateReport: templateReport,
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            result: result
        )
    }
}

nonisolated struct CanonicalGeneratedArtifactPilotActivationGate: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        libraryMetadataObservationCompleteOrRetirementCandidateReady: Bool,
        templateReport: CanonicalGeneratedArtifactTemplateReport = .currentV821Audit()
    ) -> CanonicalGeneratedArtifactPilotActivationResult {
        let matrix = CanonicalMigrationDomainMatrix.v822GeneratedArtifactsActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: libraryMetadataObservationCompleteOrRetirementCandidateReady,
            templateReport: templateReport
        )
        let report = matrix.validate()
        let policy = matrix.policy(for: .generatedArtifacts)
        var blockers: [CanonicalGeneratedArtifactPilotActivationBlocker] = []
        if !templateReport.readyForNextPilotN0 {
            blockers.append(.templateNotReadyForNextPilotN0)
        }
        if !libraryMetadataObservationCompleteOrRetirementCandidateReady {
            blockers.append(.libraryMetadataObservationMissing)
        }
        if !report.allowed {
            blockers.append(.matrixValidationBlocked)
        }
        if report.activePilotDomain != .generatedArtifacts {
            blockers.append(.activePilotNotGeneratedArtifacts)
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
        return CanonicalGeneratedArtifactPilotActivationResult(matrix: matrix, blockers: blockers)
    }
}

nonisolated enum CanonicalGeneratedArtifactGuardedCommitEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case complete
    case incomplete
}

nonisolated enum CanonicalGeneratedArtifactGateResult: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case blocked
    case allowedButCanaryBudgetZero
    case missingEvidence
    case unsupportedArtifactKind
    case contentLeakBlocked
    case unsafePathBlocked
    case parentTombstoneBlocked
    case audioConfusionBlocked
    case readyForN1AfterAudit
}

nonisolated enum CanonicalGeneratedArtifactGuardedCommitSeamFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedMode
    case productionExecuteDenied
    case viewRefreshTriggerDenied
    case retryDrainerFreshArtifactDenied
    case insufficientLocalSnapshot
    case insufficientPeerSnapshot
    case matrixValidationBlocked
    case activePilotNotGeneratedArtifacts
    case missingToken
    case missingOwnerApproval
    case missingNoCommitEvidence
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingArtifactRequestRouteEvidence
    case productionPortUnavailable
    case realApplyPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case missingRollback
    case rollbackVerificationMissing
    case rollbackRehearsalMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case legacyFallbackUnavailable
    case commitExecutorUnavailable
    case missingFailureInjectionEvidence
    case missingReadSideParallel
    case missingObservationEvidence
    case contentLeakGuardMissing
    case audioConfusionGuardMissing
    case unsupportedAction
    case unsupportedArtifactKind
    case contentLeakBlocked
    case unsafePathBlocked
    case parentTombstoneBlocked
    case audioConfusionBlocked
    case peerUnknown
    case peerNotAuthoritative
    case expectedHashMissing
    case expectedByteSizeMissing
    case canaryBudgetNonZeroDenied
    case internalN1ExecutionDenied
    case stagePolicyExecutionDenied
    case runtimeSwitchDenied
}

typealias CanonicalGeneratedArtifactGateBlocker = CanonicalGeneratedArtifactGuardedCommitSeamFailure

nonisolated struct CanonicalGeneratedArtifactGuardedCommitGate: Codable, Equatable, Sendable {
    var mode: CanonicalCutoverAppSeamMode
    var allowed: Bool
    var result: CanonicalGeneratedArtifactGateResult
    var failures: [CanonicalGeneratedArtifactGuardedCommitSeamFailure]
    var reason: String

    nonisolated init(
        mode: CanonicalCutoverAppSeamMode,
        failures: [CanonicalGeneratedArtifactGuardedCommitSeamFailure],
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
        for failures: [CanonicalGeneratedArtifactGuardedCommitSeamFailure],
        allowed: Bool,
        canaryBudgetZero: Bool
    ) -> CanonicalGeneratedArtifactGateResult {
        if allowed && canaryBudgetZero {
            return .allowedButCanaryBudgetZero
        }
        if failures.contains(.audioConfusionBlocked) {
            return .audioConfusionBlocked
        }
        if failures.contains(.parentTombstoneBlocked) {
            return .parentTombstoneBlocked
        }
        if failures.contains(.unsafePathBlocked) {
            return .unsafePathBlocked
        }
        if failures.contains(.contentLeakBlocked) || failures.contains(.contentLeakGuardMissing) {
            return .contentLeakBlocked
        }
        if failures.contains(.unsupportedArtifactKind) {
            return .unsupportedArtifactKind
        }
        if failures.contains(where: \.isEvidenceMissing) {
            return .missingEvidence
        }
        return .blocked
    }
}

nonisolated enum CanonicalGeneratedArtifactGuardedCommitDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalGeneratedArtifactV822SeamStarted
    case canonicalGeneratedArtifactV822SeamCompleted
    case canonicalGeneratedArtifactV822SeamBlocked
    case canonicalGeneratedArtifactV822GateEvaluated
    case canonicalGeneratedArtifactV822GateAllowedBudgetZero
    case canonicalGeneratedArtifactV822GateBlocked
    case canonicalGeneratedArtifactV822CanaryBudgetZero
    case canonicalGeneratedArtifactV822CommitNotExecuted
    case canonicalGeneratedArtifactV822DownloadNotExecuted
    case canonicalGeneratedArtifactV822ApplyNotExecuted
    case canonicalGeneratedArtifactV822LegacyFallbackPreserved
    case canonicalGeneratedArtifactV822DuplicateSuppressionNotApplied
    case canonicalGeneratedArtifactV822EvidenceReportBuilt
    case canonicalGeneratedArtifactV822N1ReadinessReportBuilt
    case canonicalGeneratedArtifactCanaryBudgetZero
    case canonicalGeneratedArtifactGateAllowedButNoExecution
    case canonicalGeneratedArtifactCommitSkippedBecauseCanaryBudgetZero
    case canonicalGeneratedArtifactDownloadSkippedBecauseCanaryBudgetZero
    case canonicalGeneratedArtifactApplySkippedBecauseCanaryBudgetZero
}

nonisolated struct CanonicalGeneratedArtifactGuardedCommitDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String {
        [kind.rawValue, objectID ?? "run", artifactID ?? "", result ?? "", reason ?? ""].joined(separator: "|")
    }

    var kind: CanonicalGeneratedArtifactGuardedCommitDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var mode: CanonicalCutoverAppSeamMode
    var objectID: String?
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?
    var candidateCount: Int
    var eligibleCandidateCount: Int
    var gateFailureCount: Int
    var canaryBudget: Int
    var commitAttemptedCount: Int
    var downloadAttemptedCount: Int
    var applyAttemptedCount: Int
    var duplicateSuppressionCandidateCount: Int
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalGeneratedArtifactGuardedCommitDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        mode: CanonicalCutoverAppSeamMode,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil,
        candidateCount: Int,
        eligibleCandidateCount: Int = 0,
        gateFailureCount: Int = 0,
        canaryBudget: Int,
        commitAttemptedCount: Int = 0,
        downloadAttemptedCount: Int = 0,
        applyAttemptedCount: Int = 0,
        duplicateSuppressionCandidateCount: Int = 0,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) {
        self.kind = kind
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.mode = mode
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.artifactKind = artifactKind
        self.candidateCount = max(0, candidateCount)
        self.eligibleCandidateCount = max(0, eligibleCandidateCount)
        self.gateFailureCount = max(0, gateFailureCount)
        self.canaryBudget = max(0, canaryBudget)
        self.commitAttemptedCount = max(0, commitAttemptedCount)
        self.downloadAttemptedCount = max(0, downloadAttemptedCount)
        self.applyAttemptedCount = max(0, applyAttemptedCount)
        self.duplicateSuppressionCandidateCount = max(0, duplicateSuppressionCandidateCount)
        self.result = CanonicalProductionRedaction.safeDiagnosticText(result)
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
        self.hashPrefix = hash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            "mode=\(mode.rawValue)",
            objectID.map { "objectID=\($0)" },
            artifactID.map { "artifactID=\($0)" },
            artifactKind.map { "artifactKind=\($0.rawValue)" },
            "candidateCount=\(candidateCount)",
            "eligibleCandidateCount=\(eligibleCandidateCount)",
            "gateFailureCount=\(gateFailureCount)",
            "canaryBudget=\(canaryBudget)",
            "commitAttemptedCount=\(commitAttemptedCount)",
            "downloadAttemptedCount=\(downloadAttemptedCount)",
            "applyAttemptedCount=\(applyAttemptedCount)",
            "duplicateSuppressionCandidateCount=\(duplicateSuppressionCandidateCount)",
            result.map { "result=\($0)" },
            reason.map { "reason=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated struct CanonicalGeneratedArtifactEvidenceReport: Codable, Equatable, Sendable {
    var status: CanonicalGeneratedArtifactGuardedCommitEvidenceStatus
    var missingReasons: [CanonicalGeneratedArtifactGuardedCommitSeamFailure]
    var matrixReport: CanonicalMigrationMatrixReport
    var canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy
    var localSnapshotAvailable: Bool
    var peerSnapshotAvailable: Bool
    var candidateCount: Int
    var eligibleCandidateCount: Int
    var legacyActionCandidateCount: Int
    var unresolvedConflictCount: Int
    var noCommitEvidenceAvailable: Bool
    var realApplyPortReady: Bool
    var commitExecutorReady: Bool
    var rollbackPlanReady: Bool
    var failureInjectionReady: Bool
    var readSideParallelReady: Bool
    var observationReady: Bool
    var noContentLeakGuardReady: Bool
    var noAudioConfusionGuardReady: Bool
    var duplicateSuppressionPolicyDisabledBecauseN0: Bool
    var legacyFallbackAvailable: Bool

    nonisolated init(
        missingReasons: [CanonicalGeneratedArtifactGuardedCommitSeamFailure],
        matrixReport: CanonicalMigrationMatrixReport,
        canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        candidateCount: Int,
        eligibleCandidateCount: Int,
        legacyActionCandidateCount: Int,
        unresolvedConflictCount: Int,
        noCommitEvidenceAvailable: Bool,
        realApplyPortReady: Bool,
        commitExecutorReady: Bool,
        rollbackPlanReady: Bool,
        failureInjectionReady: Bool,
        readSideParallelReady: Bool,
        observationReady: Bool,
        noContentLeakGuardReady: Bool,
        noAudioConfusionGuardReady: Bool,
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
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.noCommitEvidenceAvailable = noCommitEvidenceAvailable
        self.realApplyPortReady = realApplyPortReady
        self.commitExecutorReady = commitExecutorReady
        self.rollbackPlanReady = rollbackPlanReady
        self.failureInjectionReady = failureInjectionReady
        self.readSideParallelReady = readSideParallelReady
        self.observationReady = observationReady
        self.noContentLeakGuardReady = noContentLeakGuardReady
        self.noAudioConfusionGuardReady = noAudioConfusionGuardReady
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
            "unresolvedConflictCount=\(unresolvedConflictCount)",
            "localSnapshotAvailable=\(localSnapshotAvailable)",
            "peerSnapshotAvailable=\(peerSnapshotAvailable)",
            "canaryMaxObjectsPerSyncRun=\(canaryPolicy.canaryMaxObjectsPerSyncRun)",
            "stagePolicy=\(canaryPolicy.stagePolicy.requestedStage.rawValue)",
            "allowsInternalN1Execution=\(canaryPolicy.allowsInternalN1Execution)",
            "noCommitEvidenceAvailable=\(noCommitEvidenceAvailable)",
            "realApplyPortReady=\(realApplyPortReady)",
            "commitExecutorReady=\(commitExecutorReady)",
            "rollbackPlanReady=\(rollbackPlanReady)",
            "failureInjectionReady=\(failureInjectionReady)",
            "readSideParallelReady=\(readSideParallelReady)",
            "observationReady=\(observationReady)",
            "noContentLeakGuardReady=\(noContentLeakGuardReady)",
            "noAudioConfusionGuardReady=\(noAudioConfusionGuardReady)",
            "duplicateSuppressionPolicyDisabledBecauseN0=\(duplicateSuppressionPolicyDisabledBecauseN0)",
            "legacyFallbackAvailable=\(legacyFallbackAvailable)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalGeneratedArtifactN1ReadinessStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForN1AfterAudit
    case noEligibleCandidate
    case insufficientPeerSnapshot
    case insufficientEvidence
    case blocked
}

nonisolated enum CanonicalGeneratedArtifactN1Blocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case explicitN1EnablementRequired
    case localSnapshotUnavailable
    case peerSnapshotUnavailable
    case matrixBlocked
    case activePilotNotGeneratedArtifacts
    case ownerApprovalMissing
    case noEligibleCandidate
    case missingNoCommitEvidence
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingArtifactRequestRouteEvidence
    case missingRealApplyPort
    case missingCommitExecutor
    case missingRollbackPlan
    case missingRollbackVerification
    case missingFailureInjection
    case missingLegacyFallback
    case missingReadSideParallel
    case missingObservationEvidence
    case contentLeakGuardMissing
    case audioConfusionGuardMissing
    case unsupportedCandidate
    case unsafePathBlocked
    case parentTombstoneBlocked
    case audioConfusionBlocked
    case canaryBudgetMustRemainZeroForV822
    case executableStagePolicyDeniedForV822
    case duplicateSuppressionMustRemainDisabled
}

nonisolated struct CanonicalGeneratedArtifactN1ReadinessReport: Codable, Equatable, Sendable {
    var status: CanonicalGeneratedArtifactN1ReadinessStatus
    var gateResult: CanonicalGeneratedArtifactGateResult
    var blockers: [CanonicalGeneratedArtifactN1Blocker]
    var candidateCount: Int
    var eligibleCandidateCount: Int
    var canaryBudget: Int
    var canExecuteNow: Bool
    var willExecuteNow: Bool
    var noExecutionAssertionPassed: Bool
    var diagnosticsSummary: String

    nonisolated init(
        blockers: [CanonicalGeneratedArtifactN1Blocker],
        candidateCount: Int,
        eligibleCandidateCount: Int,
        canaryBudget: Int,
        canExecuteNow: Bool,
        willExecuteNow: Bool,
        noExecutionAssertionPassed: Bool
    ) {
        let normalizedBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.blockers = normalizedBlockers
        self.candidateCount = max(0, candidateCount)
        self.eligibleCandidateCount = max(0, eligibleCandidateCount)
        self.canaryBudget = max(0, canaryBudget)
        self.canExecuteNow = canExecuteNow
        self.willExecuteNow = willExecuteNow
        self.noExecutionAssertionPassed = noExecutionAssertionPassed
        if normalizedBlockers.contains(.peerSnapshotUnavailable) {
            self.status = .insufficientPeerSnapshot
        } else if normalizedBlockers.contains(.noEligibleCandidate) {
            self.status = .noEligibleCandidate
        } else if normalizedBlockers.contains(where: { !$0.isV822PolicyOnly }) {
            self.status = .insufficientEvidence
        } else if self.eligibleCandidateCount > 0 {
            self.status = .readyForN1AfterAudit
        } else {
            self.status = .blocked
        }
        self.gateResult = self.status == .readyForN1AfterAudit ? .readyForN1AfterAudit : .blocked
        self.diagnosticsSummary = [
            "status=\(status.rawValue)",
            "gateResult=\(gateResult.rawValue)",
            "blockers=\(normalizedBlockers.map(\.rawValue).joined(separator: "+"))",
            "candidateCount=\(self.candidateCount)",
            "eligibleCandidateCount=\(self.eligibleCandidateCount)",
            "canaryBudget=\(self.canaryBudget)",
            "canExecuteNow=\(canExecuteNow)",
            "willExecuteNow=\(willExecuteNow)",
            "noExecutionAssertionPassed=\(noExecutionAssertionPassed)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalGeneratedArtifactNoExecutionViolation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case willExecuteNow
    case commitAttempted
    case downloadAttempted
    case applyAttempted
    case committedArtifact
    case productionCommitCalled
    case realApplyPortCommitCalled
    case networkRequestCalled
    case artifactRequestRouteCalled
    case generatedArtifactDownloaded
    case generatedArtifactApplied
    case generatedArtifactFileWritten
    case generatedArtifactUploadJobCreated
    case audioAutoDownloadTriggered
    case duplicateLegacySuppressed
    case legacyFallbackNotPreserved
    case runtimeSwitchEnabled
    case legacyPlanChanged
    case productionPlanChanged
}

nonisolated struct CanonicalGeneratedArtifactNoExecutionAssertion: Codable, Equatable, Sendable {
    var passed: Bool
    var violations: [CanonicalGeneratedArtifactNoExecutionViolation]

    nonisolated static func evaluate(
        _ result: CanonicalGeneratedArtifactGuardedCommitSeamResult
    ) -> CanonicalGeneratedArtifactNoExecutionAssertion {
        var violations: [CanonicalGeneratedArtifactNoExecutionViolation] = []
        if result.willExecuteNow { violations.append(.willExecuteNow) }
        if result.commitAttemptedCount != 0 { violations.append(.commitAttempted) }
        if result.downloadAttemptedCount != 0 { violations.append(.downloadAttempted) }
        if result.applyAttemptedCount != 0 { violations.append(.applyAttempted) }
        if result.committedArtifactCount != 0 { violations.append(.committedArtifact) }
        if result.productionCommitCalled { violations.append(.productionCommitCalled) }
        if result.realApplyPortCommitCalled { violations.append(.realApplyPortCommitCalled) }
        if result.networkRequestCalled { violations.append(.networkRequestCalled) }
        if result.artifactRequestRouteCalled { violations.append(.artifactRequestRouteCalled) }
        if result.generatedArtifactDownloaded { violations.append(.generatedArtifactDownloaded) }
        if result.generatedArtifactApplied { violations.append(.generatedArtifactApplied) }
        if result.generatedArtifactFileWritten { violations.append(.generatedArtifactFileWritten) }
        if result.generatedArtifactUploadJobCreated { violations.append(.generatedArtifactUploadJobCreated) }
        if result.audioAutoDownloadTriggered { violations.append(.audioAutoDownloadTriggered) }
        if !result.duplicateLegacySuppressedActionIDs.isEmpty { violations.append(.duplicateLegacySuppressed) }
        if !result.legacyFallbackPreserved { violations.append(.legacyFallbackNotPreserved) }
        if result.runtimeSwitchEnabled { violations.append(.runtimeSwitchEnabled) }
        if !result.legacyPlanUnchanged { violations.append(.legacyPlanChanged) }
        if !result.productionPlanUnchanged { violations.append(.productionPlanChanged) }
        let uniqueViolations = Array(Set(violations)).sorted { $0.rawValue < $1.rawValue }
        return CanonicalGeneratedArtifactNoExecutionAssertion(
            passed: uniqueViolations.isEmpty,
            violations: uniqueViolations
        )
    }
}

nonisolated struct CanonicalGeneratedArtifactGuardedCommitContext: Codable, Equatable, Sendable {
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var localManifest: CanonicalManifest?
    var peerManifest: CanonicalManifest?
    var legacyActionSnapshot: CanonicalLegacyActionSnapshot
    var matrix: CanonicalMigrationDomainMatrix
    var evidence: CanonicalGeneratedArtifactCutoverEvidence
    var canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy
    var cutoverToken: CanonicalCutoverToken?
    var candidates: [CanonicalGeneratedArtifactCutoverCandidate]
    var localSnapshotAvailable: Bool
    var peerSnapshotAvailable: Bool
    var unresolvedConflictCount: Int
    var commitExecutorReady: Bool
    var failureInjectionReady: Bool
    var readSideParallelReady: Bool
    var observationReady: Bool
    var noContentLeakGuardReady: Bool
    var noAudioConfusionGuardReady: Bool
    var duplicateSuppressionPolicyAvailable: Bool
    var legacyFallbackAvailable: Bool

    nonisolated init(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?,
        legacyActionSnapshot: CanonicalLegacyActionSnapshot = .empty,
        matrix: CanonicalMigrationDomainMatrix = .v822GeneratedArtifactsActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        ),
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy = .disabled,
        cutoverToken: CanonicalCutoverToken? = nil,
        candidates: [CanonicalGeneratedArtifactCutoverCandidate] = [],
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        unresolvedConflictCount: Int = 0,
        commitExecutorReady: Bool = true,
        failureInjectionReady: Bool = true,
        readSideParallelReady: Bool? = nil,
        observationReady: Bool = true,
        noContentLeakGuardReady: Bool = true,
        noAudioConfusionGuardReady: Bool = true,
        duplicateSuppressionPolicyAvailable: Bool = true,
        legacyFallbackAvailable: Bool? = nil
    ) {
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.localManifest = localManifest
        self.peerManifest = peerManifest
        self.legacyActionSnapshot = legacyActionSnapshot
        self.matrix = matrix
        self.evidence = evidence
        self.canaryPolicy = canaryPolicy
        self.cutoverToken = cutoverToken
        self.candidates = candidates
        self.localSnapshotAvailable = localSnapshotAvailable
        self.peerSnapshotAvailable = peerSnapshotAvailable
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.commitExecutorReady = commitExecutorReady
        self.failureInjectionReady = failureInjectionReady
        self.readSideParallelReady = readSideParallelReady ?? evidence.readSideParallelEquivalent
        self.observationReady = observationReady
        self.noContentLeakGuardReady = noContentLeakGuardReady
        self.noAudioConfusionGuardReady = noAudioConfusionGuardReady
        self.duplicateSuppressionPolicyAvailable = duplicateSuppressionPolicyAvailable
        self.legacyFallbackAvailable = legacyFallbackAvailable ?? evidence.legacyFallbackAvailable
    }
}

nonisolated struct CanonicalGeneratedArtifactGuardedCommitSeamResult: Codable, Equatable, Sendable {
    var gate: CanonicalGeneratedArtifactGuardedCommitGate
    var evidenceReport: CanonicalGeneratedArtifactEvidenceReport
    var n1ReadinessReport: CanonicalGeneratedArtifactN1ReadinessReport
    var diagnostics: [CanonicalGeneratedArtifactGuardedCommitDiagnostic]
    var noExecutionAssertion: CanonicalGeneratedArtifactNoExecutionAssertion
    var canaryBudgetZero: Bool
    var canExecuteNow: Bool
    var willExecuteNow: Bool
    var commitAttemptedCount: Int
    var downloadAttemptedCount: Int
    var applyAttemptedCount: Int
    var committedArtifactCount: Int
    var productionCommitCalled: Bool
    var realApplyPortCommitCalled: Bool
    var networkRequestCalled: Bool
    var artifactRequestRouteCalled: Bool
    var generatedArtifactDownloaded: Bool
    var generatedArtifactApplied: Bool
    var generatedArtifactFileWritten: Bool
    var generatedArtifactUploadJobCreated: Bool
    var audioAutoDownloadTriggered: Bool
    var duplicateLegacySuppressedActionIDs: [String]
    var duplicateLegacySuppressionCandidates: [String]
    var legacyFallbackPreserved: Bool
    var runtimeSwitchEnabled: Bool
    var legacyPlanUnchanged: Bool
    var productionPlanUnchanged: Bool
    var nonfatalFailureCount: Int

    nonisolated var succeeded: Bool {
        gate.allowed && canaryBudgetZero && !willExecuteNow && noExecutionAssertion.passed
    }
}

nonisolated struct CanonicalGeneratedArtifactGuardedCommitSeam: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        configuration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration,
        context: CanonicalGeneratedArtifactGuardedCommitContext
    ) -> CanonicalGeneratedArtifactGuardedCommitSeamResult {
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
        let eligibleCandidateCount = eligibleCandidateCount(context.candidates, peerNode: context.peerManifest?.node)
        let canExecuteNow = gate.allowed
        let willExecuteNow = false
        let nonfatalFailureCount = gate.failures.count
        let emptyAssertion = CanonicalGeneratedArtifactNoExecutionAssertion(passed: true, violations: [])
        let preliminaryReadiness = makeN1ReadinessReport(
            context: context,
            evidenceReport: evidenceReport,
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
        var result = CanonicalGeneratedArtifactGuardedCommitSeamResult(
            gate: gate,
            evidenceReport: evidenceReport,
            n1ReadinessReport: preliminaryReadiness,
            diagnostics: Array(diagnostics.prefix(configuration.policy.maxDiagnosticsEvents)),
            noExecutionAssertion: emptyAssertion,
            canaryBudgetZero: canaryBudgetZero,
            canExecuteNow: canExecuteNow,
            willExecuteNow: willExecuteNow,
            commitAttemptedCount: 0,
            downloadAttemptedCount: 0,
            applyAttemptedCount: 0,
            committedArtifactCount: 0,
            productionCommitCalled: false,
            realApplyPortCommitCalled: false,
            networkRequestCalled: false,
            artifactRequestRouteCalled: false,
            generatedArtifactDownloaded: false,
            generatedArtifactApplied: false,
            generatedArtifactFileWritten: false,
            generatedArtifactUploadJobCreated: false,
            audioAutoDownloadTriggered: false,
            duplicateLegacySuppressedActionIDs: [],
            duplicateLegacySuppressionCandidates: duplicateCandidates,
            legacyFallbackPreserved: true,
            runtimeSwitchEnabled: false,
            legacyPlanUnchanged: true,
            productionPlanUnchanged: true,
            nonfatalFailureCount: nonfatalFailureCount
        )
        let assertion = CanonicalGeneratedArtifactNoExecutionAssertion.evaluate(result)
        result.noExecutionAssertion = assertion
        result.n1ReadinessReport = makeN1ReadinessReport(
            context: context,
            evidenceReport: evidenceReport,
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
        configuration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration,
        context: CanonicalGeneratedArtifactGuardedCommitContext,
        evidenceReport: CanonicalGeneratedArtifactEvidenceReport,
        canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy,
        canaryBudgetZero: Bool
    ) -> CanonicalGeneratedArtifactGuardedCommitGate {
        var failures: [CanonicalGeneratedArtifactGuardedCommitSeamFailure] = []
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
            failures.append(.retryDrainerFreshArtifactDenied)
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
        if evidenceReport.matrixReport.activePilotDomain != .generatedArtifacts {
            failures.append(.activePilotNotGeneratedArtifacts)
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
        if canaryPolicy.allowsInternalN1Execution {
            failures.append(.internalN1ExecutionDenied)
        }
        if canaryPolicy.stagePolicy.requestedStage.isExecutable || canaryPolicy.stagePolicy.allowCandidateExecution {
            failures.append(.stagePolicyExecutionDenied)
        }
        if canaryPolicy.stagePolicy.runtimeSwitchEnabled {
            failures.append(.runtimeSwitchDenied)
        }
        failures.append(contentsOf: evidenceReport.missingReasons)
        return CanonicalGeneratedArtifactGuardedCommitGate(
            mode: mode,
            failures: failures,
            canaryBudgetZero: canaryBudgetZero,
            reason: failures.isEmpty ? "canonicalGeneratedArtifactV822GateAllowedBudgetZero" : failures.map(\.rawValue).joined(separator: ",")
        )
    }

    private nonisolated func makeEvidenceReport(
        context: CanonicalGeneratedArtifactGuardedCommitContext,
        canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy,
        duplicateCandidates: [String]
    ) -> CanonicalGeneratedArtifactEvidenceReport {
        let evidence = context.evidence
        let matrixReport = context.matrix.validate()
        let candidateFailures = candidateFailures(context.candidates, peerNode: context.peerManifest?.node)
        var missing: [CanonicalGeneratedArtifactGuardedCommitSeamFailure] = []
        if !evidence.noCommitEvidenceAvailable { missing.append(.missingNoCommitEvidence) }
        if !evidence.realDataShadowCopyVerified { missing.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.executionShadowVerified { missing.append(.missingExecutionShadowEvidence) }
        if !evidence.dryRunEquivalenceVerified { missing.append(.missingDryRunEquivalence) }
        if !evidence.noBlockingDivergence { missing.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict || context.unresolvedConflictCount > 0 || context.candidates.contains(where: \.unresolvedConflict) {
            missing.append(.unresolvedConflict)
        }
        if !evidence.artifactRequestRouteEvidenceAvailable { missing.append(.missingArtifactRequestRouteEvidence) }
        if !evidence.productionPortAvailable { missing.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { missing.append(.realApplyPortUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { missing.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { missing.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { missing.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { missing.append(.rollbackCheckpointUnavailable) }
        if evidence.rollbackPlan?.covers(domain: .generatedArtifacts) != true { missing.append(.missingRollback) }
        if !evidence.rollbackVerified { missing.append(.rollbackVerificationMissing) }
        if !evidence.rollbackRehearsalPassed { missing.append(.rollbackRehearsalMissing) }
        if !evidence.productionRootDisabledByDefault { missing.append(.productionRootEnabledByDefault) }
        if evidence.applyPortMode == .testRootBound && !evidence.testRootUsed { missing.append(.testRootMissing) }
        if !context.legacyFallbackAvailable { missing.append(.legacyFallbackUnavailable) }
        if !context.commitExecutorReady { missing.append(.commitExecutorUnavailable) }
        if !context.failureInjectionReady { missing.append(.missingFailureInjectionEvidence) }
        if !context.readSideParallelReady { missing.append(.missingReadSideParallel) }
        if !context.observationReady { missing.append(.missingObservationEvidence) }
        if !context.noContentLeakGuardReady {
            missing.append(.contentLeakGuardMissing)
            missing.append(.contentLeakBlocked)
        }
        if !context.noAudioConfusionGuardReady {
            missing.append(.audioConfusionGuardMissing)
            missing.append(.audioConfusionBlocked)
        }
        missing.append(contentsOf: candidateFailures)
        return CanonicalGeneratedArtifactEvidenceReport(
            missingReasons: missing,
            matrixReport: matrixReport,
            canaryPolicy: canaryPolicy,
            localSnapshotAvailable: context.localSnapshotAvailable,
            peerSnapshotAvailable: context.peerSnapshotAvailable,
            candidateCount: context.candidates.count,
            eligibleCandidateCount: eligibleCandidateCount(context.candidates, peerNode: context.peerManifest?.node),
            legacyActionCandidateCount: duplicateCandidates.count,
            unresolvedConflictCount: context.unresolvedConflictCount,
            noCommitEvidenceAvailable: evidence.noCommitEvidenceAvailable,
            realApplyPortReady: evidence.realRootBoundApplyPortAvailable && evidence.applyPortMode.isNonDryRunRootBound && evidence.rootBoundWriteAvailable,
            commitExecutorReady: context.commitExecutorReady,
            rollbackPlanReady: evidence.rollbackPlan?.covers(domain: .generatedArtifacts) == true,
            failureInjectionReady: context.failureInjectionReady,
            readSideParallelReady: context.readSideParallelReady,
            observationReady: context.observationReady,
            noContentLeakGuardReady: context.noContentLeakGuardReady,
            noAudioConfusionGuardReady: context.noAudioConfusionGuardReady,
            duplicateSuppressionPolicyDisabledBecauseN0: Self.isCanaryBudgetZero(canaryPolicy),
            legacyFallbackAvailable: context.legacyFallbackAvailable
        )
    }

    private nonisolated func makeN1ReadinessReport(
        context: CanonicalGeneratedArtifactGuardedCommitContext,
        evidenceReport: CanonicalGeneratedArtifactEvidenceReport,
        canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy,
        canExecuteNow: Bool,
        willExecuteNow: Bool,
        noExecutionAssertionPassed: Bool
    ) -> CanonicalGeneratedArtifactN1ReadinessReport {
        var blockers: [CanonicalGeneratedArtifactN1Blocker] = [
            .explicitN1EnablementRequired,
            .canaryBudgetMustRemainZeroForV822,
            .duplicateSuppressionMustRemainDisabled
        ]
        if !context.localSnapshotAvailable || context.localManifest == nil { blockers.append(.localSnapshotUnavailable) }
        if !context.peerSnapshotAvailable || context.peerManifest == nil { blockers.append(.peerSnapshotUnavailable) }
        if !evidenceReport.matrixReport.allowed { blockers.append(.matrixBlocked) }
        if evidenceReport.matrixReport.activePilotDomain != .generatedArtifacts { blockers.append(.activePilotNotGeneratedArtifacts) }
        if context.cutoverToken?.ownerApproved != true { blockers.append(.ownerApprovalMissing) }
        if !context.evidence.noCommitEvidenceAvailable { blockers.append(.missingNoCommitEvidence) }
        if !context.evidence.realDataShadowCopyVerified { blockers.append(.missingRealDataShadowCopyEvidence) }
        if !context.evidence.executionShadowVerified { blockers.append(.missingExecutionShadowEvidence) }
        if !context.evidence.dryRunEquivalenceVerified { blockers.append(.missingDryRunEquivalence) }
        if !context.evidence.noBlockingDivergence { blockers.append(.blockingDivergence) }
        if !context.evidence.noUnresolvedConflict || context.unresolvedConflictCount > 0 { blockers.append(.unresolvedConflict) }
        if !context.evidence.artifactRequestRouteEvidenceAvailable { blockers.append(.missingArtifactRequestRouteEvidence) }
        if !evidenceReport.realApplyPortReady { blockers.append(.missingRealApplyPort) }
        if !context.commitExecutorReady { blockers.append(.missingCommitExecutor) }
        if !evidenceReport.rollbackPlanReady { blockers.append(.missingRollbackPlan) }
        if !context.evidence.rollbackVerified || !context.evidence.rollbackRehearsalPassed { blockers.append(.missingRollbackVerification) }
        if !context.failureInjectionReady { blockers.append(.missingFailureInjection) }
        if !context.legacyFallbackAvailable { blockers.append(.missingLegacyFallback) }
        if !context.readSideParallelReady { blockers.append(.missingReadSideParallel) }
        if !context.observationReady { blockers.append(.missingObservationEvidence) }
        if !context.noContentLeakGuardReady { blockers.append(.contentLeakGuardMissing) }
        if !context.noAudioConfusionGuardReady { blockers.append(.audioConfusionGuardMissing) }
        if canaryPolicy.stagePolicy.requestedStage.isExecutable || canaryPolicy.stagePolicy.allowCandidateExecution {
            blockers.append(.executableStagePolicyDeniedForV822)
        }
        let candidateBlockers = candidateFailures(context.candidates, peerNode: context.peerManifest?.node)
        if candidateBlockers.contains(.unsafePathBlocked) { blockers.append(.unsafePathBlocked) }
        if candidateBlockers.contains(.parentTombstoneBlocked) { blockers.append(.parentTombstoneBlocked) }
        if candidateBlockers.contains(.audioConfusionBlocked) { blockers.append(.audioConfusionBlocked) }
        if candidateBlockers.contains(where: { $0.isUnsupportedCandidateBlocker }) {
            blockers.append(.unsupportedCandidate)
        }
        let eligibleCandidateCount = eligibleCandidateCount(context.candidates, peerNode: context.peerManifest?.node)
        if eligibleCandidateCount == 0 {
            blockers.append(.noEligibleCandidate)
        }
        return CanonicalGeneratedArtifactN1ReadinessReport(
            blockers: blockers,
            candidateCount: context.candidates.count,
            eligibleCandidateCount: eligibleCandidateCount,
            canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
            canExecuteNow: canExecuteNow,
            willExecuteNow: willExecuteNow,
            noExecutionAssertionPassed: noExecutionAssertionPassed
        )
    }

    private nonisolated func baseDiagnostics(
        configuration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration,
        context: CanonicalGeneratedArtifactGuardedCommitContext,
        gate: CanonicalGeneratedArtifactGuardedCommitGate,
        evidenceReport: CanonicalGeneratedArtifactEvidenceReport,
        n1ReadinessReport: CanonicalGeneratedArtifactN1ReadinessReport,
        candidateCount: Int,
        eligibleCandidateCount: Int,
        duplicateSuppressionCandidateCount: Int,
        canaryBudget: Int,
        canaryBudgetZero: Bool,
        willExecuteNow: Bool
    ) -> [CanonicalGeneratedArtifactGuardedCommitDiagnostic] {
        var diagnostics: [CanonicalGeneratedArtifactGuardedCommitDiagnostic] = [
            diagnostic(
                .canonicalGeneratedArtifactV822SeamStarted,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.reason
            ),
            diagnostic(
                .canonicalGeneratedArtifactV822EvidenceReportBuilt,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: evidenceReport.status.rawValue,
                reason: evidenceReport.diagnosticsSummary
            ),
            diagnostic(
                .canonicalGeneratedArtifactV822N1ReadinessReportBuilt,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: n1ReadinessReport.status.rawValue,
                reason: n1ReadinessReport.diagnosticsSummary
            ),
            diagnostic(
                .canonicalGeneratedArtifactV822GateEvaluated,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: gate.result.rawValue,
                reason: gate.allowed ? "canonicalGeneratedArtifactV822GateAllowedBudgetZero" : gate.failures.map(\.rawValue).joined(separator: ",")
            )
        ]
        diagnostics.append(
            diagnostic(
                gate.allowed && canaryBudgetZero ? .canonicalGeneratedArtifactV822GateAllowedBudgetZero : .canonicalGeneratedArtifactV822GateBlocked,
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
                diagnostic(
                    .canonicalGeneratedArtifactV822SeamBlocked,
                    configuration: configuration,
                    context: context,
                    candidateCount: candidateCount,
                    eligibleCandidateCount: eligibleCandidateCount,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryBudget,
                    duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                    result: "blocked",
                    reason: gate.failures.map(\.rawValue).joined(separator: ",")
                )
            )
        }
        if canaryBudgetZero {
            diagnostics.append(contentsOf: [
                diagnostic(
                    .canonicalGeneratedArtifactV822CanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: candidateCount,
                    eligibleCandidateCount: eligibleCandidateCount,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryBudget,
                    duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                    result: "canaryBudgetZero",
                    reason: "canonicalGeneratedArtifactV822CanaryBudgetZero"
                ),
                diagnostic(
                    .canonicalGeneratedArtifactCanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: candidateCount,
                    eligibleCandidateCount: eligibleCandidateCount,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryBudget,
                    duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                    result: "canaryBudgetZero",
                    reason: "canonicalGeneratedArtifactCanaryBudgetZero"
                ),
                diagnostic(
                    .canonicalGeneratedArtifactCommitSkippedBecauseCanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: candidateCount,
                    eligibleCandidateCount: eligibleCandidateCount,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryBudget,
                    duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                    result: "commitSkipped",
                    reason: "canaryBudgetZero"
                ),
                diagnostic(
                    .canonicalGeneratedArtifactDownloadSkippedBecauseCanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: candidateCount,
                    eligibleCandidateCount: eligibleCandidateCount,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryBudget,
                    duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                    result: "downloadSkipped",
                    reason: "canaryBudgetZero"
                ),
                diagnostic(
                    .canonicalGeneratedArtifactApplySkippedBecauseCanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: candidateCount,
                    eligibleCandidateCount: eligibleCandidateCount,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryBudget,
                    duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                    result: "applySkipped",
                    reason: "canaryBudgetZero"
                )
            ])
        }
        if gate.allowed && !willExecuteNow {
            diagnostics.append(
                diagnostic(
                    .canonicalGeneratedArtifactGateAllowedButNoExecution,
                    configuration: configuration,
                    context: context,
                    candidateCount: candidateCount,
                    eligibleCandidateCount: eligibleCandidateCount,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryBudget,
                    duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                    result: "gateAllowedButNoExecution",
                    reason: canaryBudgetZero ? "canaryBudgetZero" : "executionDeniedForV822"
                )
            )
        }
        diagnostics.append(contentsOf: [
            diagnostic(
                .canonicalGeneratedArtifactV822CommitNotExecuted,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: "commitNotExecuted",
                reason: "v822GeneratedArtifactsGuardedCommitSeamNZero"
            ),
            diagnostic(
                .canonicalGeneratedArtifactV822DownloadNotExecuted,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: "downloadNotExecuted",
                reason: "v822DoesNotCallArtifactRequest"
            ),
            diagnostic(
                .canonicalGeneratedArtifactV822ApplyNotExecuted,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: "applyNotExecuted",
                reason: "v822DoesNotWriteGeneratedArtifact"
            ),
            diagnostic(
                .canonicalGeneratedArtifactV822LegacyFallbackPreserved,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: "legacyFallbackPreserved",
                reason: "v822DoesNotReplaceLegacyArtifactPlan"
            ),
            diagnostic(
                .canonicalGeneratedArtifactV822DuplicateSuppressionNotApplied,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: "duplicateSuppressionNotApplied",
                reason: "v822NZeroDoesNotSuppressLegacyDuplicates"
            ),
            diagnostic(
                .canonicalGeneratedArtifactV822SeamCompleted,
                configuration: configuration,
                context: context,
                candidateCount: candidateCount,
                eligibleCandidateCount: eligibleCandidateCount,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryBudget,
                duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
                result: "completed",
                reason: gate.allowed ? "nonfatalNoExecution" : "nonfatalBlocked"
            )
        ])
        return diagnostics
    }

    private nonisolated func candidateFailures(
        _ candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        peerNode: CanonicalNode?
    ) -> [CanonicalGeneratedArtifactGuardedCommitSeamFailure] {
        var failures: [CanonicalGeneratedArtifactGuardedCommitSeamFailure] = []
        for candidate in candidates {
            if candidate.cutoverActionKind.isExecutableApply == false {
                failures.append(.unsupportedAction)
            }
            guard let kind = candidate.artifactKind else {
                failures.append(.unsupportedArtifactKind)
                continue
            }
            if kind == .audio {
                failures.append(.audioConfusionBlocked)
            }
            if !CanonicalProjectionContract.generatedArtifactKinds.contains(kind) {
                failures.append(.unsupportedArtifactKind)
            }
            if candidate.expectedContentHash == nil {
                failures.append(.expectedHashMissing)
            }
            if candidate.expectedByteSize == nil {
                failures.append(.expectedByteSizeMissing)
            }
            if candidate.unresolvedConflict {
                failures.append(.unresolvedConflict)
            }
            if candidate.parentObjectTombstoned {
                failures.append(.parentTombstoneBlocked)
            }
            if candidate.expectedLogicalPathToken.flatMap(CanonicalProjectionContract.safeLogicalPathToken) == nil {
                failures.append(.unsafePathBlocked)
            }
            if peerNode == nil {
                failures.append(.peerUnknown)
            } else if !candidate.peerIsAuthoritative(peerNode: peerNode) {
                failures.append(.peerNotAuthoritative)
            }
        }
        return Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated func eligibleCandidateCount(
        _ candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        peerNode: CanonicalNode?
    ) -> Int {
        candidates.filter { candidateFailures([$0], peerNode: peerNode).isEmpty }.count
    }

    private nonisolated func duplicateSuppressionCandidates(
        _ context: CanonicalGeneratedArtifactGuardedCommitContext
    ) -> [String] {
        let legacyIDs = context.legacyActionSnapshot.actionIDSet(for: .generatedArtifacts)
        return context.candidates
            .map(\.action.actionID)
            .filter { legacyIDs.contains($0) }
            .compactMap { CanonicalProductionRedaction.safeDiagnosticText($0) }
            .sorted()
    }

    private nonisolated static func isCanaryBudgetZero(
        _ policy: CanonicalGeneratedArtifactCanaryPolicy
    ) -> Bool {
        policy.canaryMaxObjectsPerSyncRun == 0
            && !policy.allowsInternalN1Execution
            && !policy.stagePolicy.requestedStage.isExecutable
            && !policy.stagePolicy.allowCandidateExecution
            && !policy.stagePolicy.runtimeSwitchEnabled
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalGeneratedArtifactGuardedCommitDiagnosticKind,
        configuration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration,
        context: CanonicalGeneratedArtifactGuardedCommitContext,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil,
        candidateCount: Int,
        eligibleCandidateCount: Int,
        gateFailureCount: Int = 0,
        canaryBudget: Int,
        commitAttemptedCount: Int = 0,
        downloadAttemptedCount: Int = 0,
        applyAttemptedCount: Int = 0,
        duplicateSuppressionCandidateCount: Int = 0,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalGeneratedArtifactGuardedCommitDiagnostic {
        CanonicalGeneratedArtifactGuardedCommitDiagnostic(
            kind: kind,
            syncRunID: context.syncRunID,
            trigger: context.trigger,
            nodeRole: context.nodeRole,
            mode: configuration.effectiveMode,
            objectID: objectID,
            artifactID: artifactID,
            artifactKind: artifactKind,
            candidateCount: candidateCount,
            eligibleCandidateCount: eligibleCandidateCount,
            gateFailureCount: gateFailureCount,
            canaryBudget: canaryBudget,
            commitAttemptedCount: commitAttemptedCount,
            downloadAttemptedCount: downloadAttemptedCount,
            applyAttemptedCount: applyAttemptedCount,
            duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}

private extension CanonicalGeneratedArtifactGuardedCommitSeamFailure {
    nonisolated var isEvidenceMissing: Bool {
        switch self {
        case .missingNoCommitEvidence,
             .missingRealDataShadowCopyEvidence,
             .missingExecutionShadowEvidence,
             .missingDryRunEquivalence,
             .missingArtifactRequestRouteEvidence,
             .productionPortUnavailable,
             .realApplyPortUnavailable,
             .applyPortDryRunOnly,
             .rootBoundWriteUnavailable,
             .atomicReplaceUnavailable,
             .rollbackCheckpointUnavailable,
             .missingRollback,
             .rollbackVerificationMissing,
             .rollbackRehearsalMissing,
             .commitExecutorUnavailable,
             .missingFailureInjectionEvidence,
             .missingReadSideParallel,
             .missingObservationEvidence,
             .expectedHashMissing,
             .expectedByteSizeMissing:
            return true
        case .disabled,
             .unsupportedMode,
             .productionExecuteDenied,
             .viewRefreshTriggerDenied,
             .retryDrainerFreshArtifactDenied,
             .insufficientLocalSnapshot,
             .insufficientPeerSnapshot,
             .matrixValidationBlocked,
             .activePilotNotGeneratedArtifacts,
             .missingToken,
             .missingOwnerApproval,
             .blockingDivergence,
             .unresolvedConflict,
             .productionRootEnabledByDefault,
             .testRootMissing,
             .legacyFallbackUnavailable,
             .contentLeakGuardMissing,
             .audioConfusionGuardMissing,
             .unsupportedAction,
             .unsupportedArtifactKind,
             .contentLeakBlocked,
             .unsafePathBlocked,
             .parentTombstoneBlocked,
             .audioConfusionBlocked,
             .peerUnknown,
             .peerNotAuthoritative,
             .canaryBudgetNonZeroDenied,
             .internalN1ExecutionDenied,
             .stagePolicyExecutionDenied,
             .runtimeSwitchDenied:
            return false
        }
    }

    nonisolated var isUnsupportedCandidateBlocker: Bool {
        switch self {
        case .unsupportedAction,
             .unsupportedArtifactKind,
             .unresolvedConflict,
             .peerUnknown,
             .peerNotAuthoritative,
             .expectedHashMissing,
             .expectedByteSizeMissing:
            return true
        default:
            return false
        }
    }
}

private extension CanonicalGeneratedArtifactN1Blocker {
    nonisolated var isV822PolicyOnly: Bool {
        switch self {
        case .explicitN1EnablementRequired,
             .canaryBudgetMustRemainZeroForV822,
             .duplicateSuppressionMustRemainDisabled:
            return true
        default:
            return false
        }
    }
}
