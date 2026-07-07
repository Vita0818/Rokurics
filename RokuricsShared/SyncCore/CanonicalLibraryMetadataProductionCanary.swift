//
//  CanonicalLibraryMetadataProductionCanary.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated enum CanonicalLibraryMetadataProductionCanaryMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case diagnosticsOnly
    case canaryN1Armed
    case canaryN1Execute
    case blocked

    nonisolated var requestsExecution: Bool {
        self == .canaryN1Execute
    }

    nonisolated var isConfigured: Bool {
        self != .disabled
    }
}

nonisolated enum CanonicalLibraryMetadataProductionCanaryRootMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case testRoot
    case productionRootExplicit

    nonisolated var isProductionRoot: Bool {
        self == .productionRootExplicit
    }
}

nonisolated struct CanonicalLibraryMetadataProductionCanaryPolicy: Codable, Equatable, Sendable {
    var domain: CanonicalMigrationDomain
    var canaryMaxObjectsPerSyncRun: Int
    var requiresExplicitInternalDebugConfiguration: Bool
    var requiresProductionToken: Bool
    var requiresOwnerApproval: Bool
    var requiresRollbackPlan: Bool
    var requiresReadSideParallelEquivalent: Bool
    var productionRootDisabledByDefault: Bool
    var runtimeSwitchEnabled: Bool
    var allowAllEligible: Bool
    var releaseDefaultEnabled: Bool

    nonisolated init(
        domain: CanonicalMigrationDomain = .libraryMetadata,
        canaryMaxObjectsPerSyncRun: Int = 1,
        requiresExplicitInternalDebugConfiguration: Bool = true,
        requiresProductionToken: Bool = true,
        requiresOwnerApproval: Bool = true,
        requiresRollbackPlan: Bool = true,
        requiresReadSideParallelEquivalent: Bool = true,
        productionRootDisabledByDefault: Bool = true,
        runtimeSwitchEnabled: Bool = false,
        allowAllEligible: Bool = false,
        releaseDefaultEnabled: Bool = false
    ) {
        self.domain = domain
        self.canaryMaxObjectsPerSyncRun = max(0, canaryMaxObjectsPerSyncRun)
        self.requiresExplicitInternalDebugConfiguration = requiresExplicitInternalDebugConfiguration
        self.requiresProductionToken = requiresProductionToken
        self.requiresOwnerApproval = requiresOwnerApproval
        self.requiresRollbackPlan = requiresRollbackPlan
        self.requiresReadSideParallelEquivalent = requiresReadSideParallelEquivalent
        self.productionRootDisabledByDefault = productionRootDisabledByDefault
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.allowAllEligible = allowAllEligible
        self.releaseDefaultEnabled = releaseDefaultEnabled
    }

    nonisolated static let strictLibraryMetadataN1 = CanonicalLibraryMetadataProductionCanaryPolicy()

    nonisolated var isStrictN1LibraryMetadata: Bool {
        domain == .libraryMetadata
            && canaryMaxObjectsPerSyncRun == 1
            && requiresExplicitInternalDebugConfiguration
            && productionRootDisabledByDefault
            && !runtimeSwitchEnabled
            && !allowAllEligible
            && !releaseDefaultEnabled
    }

    nonisolated var asCanaryPolicy: CanonicalLibraryMetadataCanaryPolicy {
        CanonicalLibraryMetadataCanaryPolicy(
            canaryMaxObjectsPerSyncRun: canaryMaxObjectsPerSyncRun,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true,
            runtimeSwitchEnabled: runtimeSwitchEnabled,
            allowAllEligible: allowAllEligible
        )
    }
}

nonisolated struct CanonicalLibraryMetadataProductionCanaryConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalLibraryMetadataProductionCanaryMode
    var rootMode: CanonicalLibraryMetadataProductionCanaryRootMode
    var policy: CanonicalLibraryMetadataProductionCanaryPolicy
    var explicitInternalDebugConfiguration: Bool
    var allowProductionRootWrites: Bool

    nonisolated init(
        mode: CanonicalLibraryMetadataProductionCanaryMode = .disabled,
        rootMode: CanonicalLibraryMetadataProductionCanaryRootMode = .disabled,
        policy: CanonicalLibraryMetadataProductionCanaryPolicy = .strictLibraryMetadataN1,
        explicitInternalDebugConfiguration: Bool = false,
        allowProductionRootWrites: Bool = false
    ) {
        self.mode = mode
        self.rootMode = rootMode
        self.policy = policy
        self.explicitInternalDebugConfiguration = explicitInternalDebugConfiguration
        self.allowProductionRootWrites = allowProductionRootWrites
    }

    nonisolated static let disabled = CanonicalLibraryMetadataProductionCanaryConfiguration()

    nonisolated static func diagnosticsOnly(
        explicitInternalDebugConfiguration: Bool = true
    ) -> CanonicalLibraryMetadataProductionCanaryConfiguration {
        CanonicalLibraryMetadataProductionCanaryConfiguration(
            mode: .diagnosticsOnly,
            rootMode: .disabled,
            explicitInternalDebugConfiguration: explicitInternalDebugConfiguration
        )
    }

    nonisolated static func explicitTestRootN1Armed() -> CanonicalLibraryMetadataProductionCanaryConfiguration {
        CanonicalLibraryMetadataProductionCanaryConfiguration(
            mode: .canaryN1Armed,
            rootMode: .testRoot,
            explicitInternalDebugConfiguration: true
        )
    }

    nonisolated static func explicitTestRootN1Execute() -> CanonicalLibraryMetadataProductionCanaryConfiguration {
        CanonicalLibraryMetadataProductionCanaryConfiguration(
            mode: .canaryN1Execute,
            rootMode: .testRoot,
            explicitInternalDebugConfiguration: true
        )
    }

    nonisolated static func explicitProductionRootN1Execute(
        allowProductionRootWrites: Bool
    ) -> CanonicalLibraryMetadataProductionCanaryConfiguration {
        CanonicalLibraryMetadataProductionCanaryConfiguration(
            mode: .canaryN1Execute,
            rootMode: .productionRootExplicit,
            explicitInternalDebugConfiguration: true,
            allowProductionRootWrites: allowProductionRootWrites
        )
    }

    nonisolated var canaryMaxObjectsPerSyncRun: Int {
        policy.canaryMaxObjectsPerSyncRun
    }

    nonisolated var asN1CanaryConfiguration: CanonicalLibraryMetadataCanaryConfiguration {
        guard mode.requestsExecution else {
            return .disabled
        }
        return CanonicalLibraryMetadataCanaryConfiguration(
            mode: .n1,
            domain: policy.domain,
            canaryMaxObjectsPerSyncRun: policy.canaryMaxObjectsPerSyncRun,
            explicitInternalTestConfiguration: explicitInternalDebugConfiguration,
            productionTokenRequired: policy.requiresProductionToken,
            ownerApprovalRequired: policy.requiresOwnerApproval,
            rollbackPlanRequired: policy.requiresRollbackPlan,
            runtimeSwitchEnabled: policy.runtimeSwitchEnabled,
            allowAllEligible: policy.allowAllEligible,
            releaseDefaultEnabled: policy.releaseDefaultEnabled
        )
    }

    nonisolated var strictExecutableN1: Bool {
        mode == .canaryN1Execute
            && (rootMode == .testRoot || rootMode == .productionRootExplicit)
            && explicitInternalDebugConfiguration
            && policy.isStrictN1LibraryMetadata
            && (rootMode == .testRoot ? !allowProductionRootWrites : allowProductionRootWrites)
    }
}

nonisolated enum CanonicalLibraryMetadataProductionRootBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingExplicitDebugInternalConfiguration
    case modeNotExecuteN1Canary
    case rootModeNotProductionRootExplicit
    case allowProductionRootWritesFalse
    case missingOwnerApproval
    case activePilotNotLibraryMetadata
    case multipleActivePilots
    case runtimeSwitchEnabled
    case landingFreezeNotGreen
    case diagnosticsOnlyEvidenceMissing
    case armN1EvidenceMissing
    case testRootExecuteEvidenceMissing
    case readSideDivergenceNonZero
    case rollbackEvidenceMissing
    case legacyFallbackUnavailable
    case safeCandidateMissing
    case multipleSafeCandidatesDenied
    case unsafeCandidateSelected
    case noResourceMoveGuardMissing
    case resourceMoveAttempted
    case noContentWriteGuardMissing
    case contentWriteAttempted
    case tombstoneDeleteAttempted
    case productionRootContainmentUnverified
    case checkpointUnavailable
    case postconditionVerificationUnavailable
    case n1BudgetRequired
    case allEligibleDenied
    case nonLibraryMetadataDomain
    case releaseDefaultDenied
    case defaultEnablementDenied
    case localSnapshotUnavailable
    case peerSnapshotUnavailable
    case commitExecutorUnavailable
    case unsupportedTrigger
    case productionPortUnavailable
    case realApplyPortUnavailable
    case rootBoundWriteUnavailable
    case atomicWriteUnavailable
}

nonisolated struct CanonicalLibraryMetadataProductionRootGateResult: Codable, Equatable, Sendable {
    var allowed: Bool
    var blockers: [CanonicalLibraryMetadataProductionRootBlocker]
    var selectedCandidate: CanonicalLibraryMetadataCanaryCandidate?
    var selectedCandidateSafety: CanonicalLibraryMetadataCanaryCandidateSafety?
    var freezeResult: CanonicalMigrationLandingFreezeResult
    var diagnosticsSummary: String
    var redacted: Bool

    nonisolated init(
        blockers: [CanonicalLibraryMetadataProductionRootBlocker],
        selectedCandidate: CanonicalLibraryMetadataCanaryCandidate?,
        selectedCandidateSafety: CanonicalLibraryMetadataCanaryCandidateSafety?,
        freezeResult: CanonicalMigrationLandingFreezeResult
    ) {
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = uniqueBlockers.isEmpty
        self.blockers = uniqueBlockers
        self.selectedCandidate = selectedCandidate
        self.selectedCandidateSafety = selectedCandidateSafety
        self.freezeResult = freezeResult
        self.diagnosticsSummary = [
            "allowed=\(uniqueBlockers.isEmpty)",
            "rootMode=productionRootExplicit",
            "candidateKind=\(selectedCandidateSafety?.kind.rawValue ?? "none")",
            "objectKind=\(selectedCandidate?.objectKind.rawValue ?? "none")",
            "domain=\(selectedCandidate?.domain.rawValue ?? "none")",
            "blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
        self.redacted = true
    }
}

nonisolated struct CanonicalLibraryMetadataProductionRootGate: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        executorAvailable: Bool
    ) -> CanonicalLibraryMetadataProductionRootGateResult {
        var blockers: [CanonicalLibraryMetadataProductionRootBlocker] = []
        if !configuration.explicitInternalDebugConfiguration {
            blockers.append(.missingExplicitDebugInternalConfiguration)
        }
        if configuration.mode != .canaryN1Execute {
            blockers.append(.modeNotExecuteN1Canary)
        }
        if configuration.rootMode != .productionRootExplicit {
            blockers.append(.rootModeNotProductionRootExplicit)
        }
        if !configuration.allowProductionRootWrites {
            blockers.append(.allowProductionRootWritesFalse)
        }
        if configuration.policy.domain != .libraryMetadata {
            blockers.append(.nonLibraryMetadataDomain)
        }
        if configuration.policy.canaryMaxObjectsPerSyncRun != 1 {
            blockers.append(.n1BudgetRequired)
        }
        if configuration.policy.runtimeSwitchEnabled {
            blockers.append(.runtimeSwitchEnabled)
        }
        if configuration.policy.allowAllEligible {
            blockers.append(.allEligibleDenied)
        }
        if configuration.policy.releaseDefaultEnabled {
            blockers.append(.releaseDefaultDenied)
        }
        if token?.ownerApproved != true {
            blockers.append(.missingOwnerApproval)
        }
        if !localSnapshotAvailable {
            blockers.append(.localSnapshotUnavailable)
        }
        if !peerSnapshotAvailable {
            blockers.append(.peerSnapshotUnavailable)
        }
        if !executorAvailable {
            blockers.append(.commitExecutorUnavailable)
        }
        if trigger == .viewRefresh || trigger == .retryDrainer {
            blockers.append(.unsupportedTrigger)
        }

        let freeze = CanonicalMigrationLandingFreeze().evaluate(
            matrix: matrix,
            releaseDefaultEnabled: configuration.policy.releaseDefaultEnabled,
            runtimeSwitchEnabled: configuration.policy.runtimeSwitchEnabled,
            productionInjectionPresent: false,
            productionExecutorInjectedByDefault: false,
            productionRootWriteEnabledByDefault: false,
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            canaryMaxObjectsPerSyncRun: configuration.policy.canaryMaxObjectsPerSyncRun,
            allEligibleEnabled: configuration.policy.allowAllEligible,
            unsafeCandidateAllowed: false,
            resourceMoveAllowed: false,
            contentWriteAllowed: false,
            tombstoneDeleteAllowed: false
        )
        if !freeze.allowed {
            blockers.append(.landingFreezeNotGreen)
        }
        if freeze.activePilotDomain != .libraryMetadata {
            blockers.append(.activePilotNotLibraryMetadata)
        }
        if matrix.policies.filter(\.activePilot).count > 1 {
            blockers.append(.multipleActivePilots)
        }
        if matrix.policies.contains(where: \.defaultCutoverEnabled) {
            blockers.append(.defaultEnablementDenied)
        }

        if !evidence.noCommitEvidenceAvailable || !evidence.dryRunEquivalenceVerified {
            blockers.append(.diagnosticsOnlyEvidenceMissing)
        }
        if !evidence.realDataShadowCopyVerified
            || !evidence.executionShadowVerified
            || !evidence.metadataManifestRouteEvidenceAvailable {
            blockers.append(.armN1EvidenceMissing)
        }
        if !evidence.testRootUsed {
            blockers.append(.testRootExecuteEvidenceMissing)
        }
        if !evidence.readSideParallelEquivalent {
            blockers.append(.readSideDivergenceNonZero)
        }
        if !evidence.rollbackCheckpointAvailable || !evidence.rollbackVerified || !evidence.rollbackRehearsalPassed {
            blockers.append(.rollbackEvidenceMissing)
        }
        if !evidence.legacyFallbackAvailable {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !evidence.productionPortAvailable {
            blockers.append(.productionPortUnavailable)
        }
        if !evidence.realRootBoundApplyPortAvailable {
            blockers.append(.realApplyPortUnavailable)
        }
        if evidence.applyPortMode != .productionRootBound {
            blockers.append(.productionRootContainmentUnverified)
        }
        if !evidence.rootBoundWriteAvailable {
            blockers.append(.rootBoundWriteUnavailable)
        }
        if !evidence.atomicReplaceAvailable {
            blockers.append(.atomicWriteUnavailable)
        }

        let selector = CanonicalLibraryMetadataCanarySelector().select(
            mode: .canary,
            policy: CanonicalLibraryMetadataCanaryPolicy(
                canaryMaxObjectsPerSyncRun: 1,
                allowsInternalN1Execution: true,
                explicitInternalTestConfiguration: true
            ),
            trigger: trigger,
            evidence: evidence,
            candidates: candidates
        )
        let safetyReports = candidates.map {
            CanonicalLibraryMetadataCanaryCandidateSafety(candidate: $0, evidence: evidence)
        }
        let safeReports = safetyReports.filter(\.safe)
        if safeReports.isEmpty {
            blockers.append(.safeCandidateMissing)
        }
        if safeReports.count > 1 {
            blockers.append(.multipleSafeCandidatesDenied)
        }
        if selector.selectedCandidates.count != 1 {
            blockers.append(.safeCandidateMissing)
        }
        if safetyReports.contains(where: { !$0.safe }) {
            blockers.append(.unsafeCandidateSelected)
        }
        if safetyReports.contains(where: \.resourceMoveAttempted) {
            blockers.append(.resourceMoveAttempted)
        }
        if safetyReports.contains(where: \.contentBytesMutated) {
            blockers.append(.contentWriteAttempted)
        }
        if safetyReports.contains(where: \.physicalDeleteAttempted) {
            blockers.append(.tombstoneDeleteAttempted)
        }
        guard let selected = selector.selectedCandidates.first,
              let selectedSafety = safetyReports.first(where: { $0.candidate.id == selected.id }) else {
            return CanonicalLibraryMetadataProductionRootGateResult(
                blockers: blockers,
                selectedCandidate: nil,
                selectedCandidateSafety: nil,
                freezeResult: freeze
            )
        }
        if !selectedSafety.metadataOnly {
            blockers.append(.noContentWriteGuardMissing)
        }
        if selectedSafety.resourceMoveAttempted {
            blockers.append(.noResourceMoveGuardMissing)
        }
        if selectedSafety.contentBytesMutated {
            blockers.append(.contentWriteAttempted)
        }
        if selectedSafety.physicalDeleteAttempted {
            blockers.append(.tombstoneDeleteAttempted)
        }
        if selected.cutoverCandidate.rollbackCheckpointID == nil {
            blockers.append(.checkpointUnavailable)
        }
        if !evidence.atomicReplaceAvailable || !evidence.rootBoundWriteAvailable {
            blockers.append(.postconditionVerificationUnavailable)
        }
        return CanonicalLibraryMetadataProductionRootGateResult(
            blockers: blockers,
            selectedCandidate: selected,
            selectedCandidateSafety: selectedSafety,
            freezeResult: freeze
        )
    }
}

nonisolated struct CanonicalLibraryMetadataProductionRootSafetyProof: Codable, Equatable, Sendable {
    var rootContainmentVerified: Bool
    var productionRootModeExplicit: Bool
    var logicalTokenSafety: Bool
    var checkpointID: String?
    var atomicWriteUsed: Bool
    var postconditionVerified: Bool
    var rollbackAvailable: Bool
    var rollbackVerifiedIfUsed: Bool
    var sideEffectWhitelistPassed: Bool
    var noResourceMove: Bool
    var noContentWrite: Bool
    var noOtherDomainMutation: Bool
    var redactedTargetSummary: String
    var redacted: Bool

    nonisolated init(
        gate: CanonicalLibraryMetadataProductionRootGateResult,
        cutoverResult: CanonicalLibraryMetadataCutoverResult?,
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration
    ) {
        let commit = cutoverResult?.commits.first
        let rollbackResults = cutoverResult?.rollbackResults ?? []
        let candidate = gate.selectedCandidate
        self.rootContainmentVerified = gate.allowed && configuration.rootMode == .productionRootExplicit
        self.productionRootModeExplicit = configuration.rootMode == .productionRootExplicit
        self.logicalTokenSafety = gate.selectedCandidateSafety?.safe == true
        self.checkpointID = candidate?.cutoverCandidate.effectiveRollbackCheckpointID
        self.atomicWriteUsed = commit?.committed == true && commit?.sideEffects.contains(where: { $0.kind == .metadataApply }) == true
        self.postconditionVerified = commit?.postconditionVerified == true
        self.rollbackAvailable = candidate?.cutoverCandidate.rollbackCheckpointID != nil
        self.rollbackVerifiedIfUsed = rollbackResults.isEmpty || rollbackResults.allSatisfy { $0.succeeded && !$0.fatal }
        self.sideEffectWhitelistPassed = commit?.sideEffects.allSatisfy {
            $0.kind == .metadataApply
                && [.folders, .studyItems, .standaloneNotes].contains($0.domain)
        } ?? gate.allowed
        self.noResourceMove = gate.selectedCandidateSafety?.resourceMoveAttempted == false
        self.noContentWrite = gate.selectedCandidateSafety?.contentBytesMutated == false
        self.noOtherDomainMutation = commit?.sideEffects.allSatisfy {
            [.folders, .studyItems, .standaloneNotes].contains($0.domain)
        } ?? true
        self.redactedTargetSummary = [
            "domain=\(candidate?.domain.rawValue ?? "none")",
            "objectKind=\(candidate?.objectKind.rawValue ?? "none")",
            "candidateKind=\(gate.selectedCandidateSafety?.kind.rawValue ?? "none")",
            "hashPrefix=\(candidate?.metadataHashPrefix ?? "none")"
        ].joined(separator: ",")
        self.redacted = true
    }
}

nonisolated enum CanonicalLibraryMetadataRealCanaryBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case diagnosticsOnlyNoExecution
    case armedNoExecution
    case blockedMode
    case nonLibraryMetadataDomain
    case n1BudgetRequired
    case canaryBudgetAboveOneDenied
    case missingExplicitInternalDebugConfiguration
    case runtimeSwitchDenied
    case allEligibleDenied
    case releaseDefaultDenied
    case defaultEnablementDenied
    case missingToken
    case missingOwnerApproval
    case matrixValidationBlocked
    case activePilotNotLibraryMetadata
    case localSnapshotUnavailable
    case peerSnapshotUnavailable
    case missingNoCommitEvidence
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingMetadataManifestRouteEvidence
    case productionPortUnavailable
    case realApplyPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case rollbackPlanMissing
    case rollbackVerificationMissing
    case productionRootGuardMissing
    case productionRootWritesDisabled
    case productionRootNotExplicit
    case productionRootExplicitBlockedV830
    case allowProductionRootWritesDeniedV830
    case testRootMissing
    case legacyFallbackUnavailable
    case readSideParallelMissing
    case readSideParallelDivergent
    case commitExecutorUnavailable
    case unsupportedTrigger
    case noEligibleCandidate
    case unsafeCandidateSkipped
    case rollbackFailure
    case fatalBlocker
}

nonisolated enum CanonicalLibraryMetadataRealCanaryObservationStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case diagnosticsOnly
    case armed
    case blocked
    case noEligibleCandidate
    case unsafeCandidateSkipped
    case executedSucceeded
    case executedFailedRolledBack
    case fatalRollbackFailure
}

nonisolated enum CanonicalLibraryMetadataRealCanaryRecommendation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case remainDisabled
    case stayN1
    case readyForN3AfterAudit
    case fixBlockers
}

nonisolated struct CanonicalLibraryMetadataRealCanaryObservationReport: Codable, Equatable, Sendable {
    var status: CanonicalLibraryMetadataRealCanaryObservationStatus
    var recommendation: CanonicalLibraryMetadataRealCanaryRecommendation
    var mode: CanonicalLibraryMetadataProductionCanaryMode
    var rootMode: CanonicalLibraryMetadataProductionCanaryRootMode
    var domain: CanonicalMigrationDomain
    var canaryMaxObjectsPerSyncRun: Int
    var selectedCandidateCount: Int
    var executedCandidateCount: Int
    var successfulCommitCount: Int
    var failedCommitCount: Int
    var rollbackCount: Int
    var rollbackFailureCount: Int
    var legacyFallbackCount: Int
    var duplicateSuppressionCount: Int
    var noEligibleCandidateCount: Int
    var unsafeCandidateSkippedCount: Int
    var fatalBlockerCount: Int
    var readSideParallelEquivalent: Bool
    var readSideParallelDivergent: Bool
    var legacyFallbackPreserved: Bool
    var duplicateSuppressionApplied: Bool
    var productionRootWriteAttempted: Bool
    var productionRootWriteExplicitlyAllowed: Bool
    var runtimeSwitchEnabled: Bool
    var allEligibleEnabled: Bool
    var uiMutated: Bool
    var resourceMoved: Bool
    var uploadJobCreated: Bool
    var blockers: [CanonicalLibraryMetadataRealCanaryBlocker]
    var reason: String
    var redacted: Bool

    nonisolated init(
        status: CanonicalLibraryMetadataRealCanaryObservationStatus,
        recommendation: CanonicalLibraryMetadataRealCanaryRecommendation,
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        selectedCandidateCount: Int = 0,
        executedCandidateCount: Int = 0,
        successfulCommitCount: Int = 0,
        failedCommitCount: Int = 0,
        rollbackCount: Int = 0,
        rollbackFailureCount: Int = 0,
        legacyFallbackCount: Int = 0,
        duplicateSuppressionCount: Int = 0,
        noEligibleCandidateCount: Int = 0,
        unsafeCandidateSkippedCount: Int = 0,
        fatalBlockerCount: Int = 0,
        readSideParallelEquivalent: Bool = false,
        readSideParallelDivergent: Bool = false,
        legacyFallbackPreserved: Bool = true,
        duplicateSuppressionApplied: Bool = false,
        productionRootWriteAttempted: Bool = false,
        blockers: [CanonicalLibraryMetadataRealCanaryBlocker] = [],
        reason: String,
        redacted: Bool = true
    ) {
        self.status = status
        self.recommendation = recommendation
        self.mode = configuration.mode
        self.rootMode = configuration.rootMode
        self.domain = configuration.policy.domain
        self.canaryMaxObjectsPerSyncRun = configuration.policy.canaryMaxObjectsPerSyncRun
        self.selectedCandidateCount = max(0, selectedCandidateCount)
        self.executedCandidateCount = max(0, executedCandidateCount)
        self.successfulCommitCount = max(0, successfulCommitCount)
        self.failedCommitCount = max(0, failedCommitCount)
        self.rollbackCount = max(0, rollbackCount)
        self.rollbackFailureCount = max(0, rollbackFailureCount)
        self.legacyFallbackCount = max(0, legacyFallbackCount)
        self.duplicateSuppressionCount = max(0, duplicateSuppressionCount)
        self.noEligibleCandidateCount = max(0, noEligibleCandidateCount)
        self.unsafeCandidateSkippedCount = max(0, unsafeCandidateSkippedCount)
        self.fatalBlockerCount = max(0, fatalBlockerCount)
        self.readSideParallelEquivalent = readSideParallelEquivalent
        self.readSideParallelDivergent = readSideParallelDivergent
        self.legacyFallbackPreserved = legacyFallbackPreserved
        self.duplicateSuppressionApplied = duplicateSuppressionApplied
        self.productionRootWriteAttempted = productionRootWriteAttempted
        self.productionRootWriteExplicitlyAllowed = configuration.allowProductionRootWrites
        self.runtimeSwitchEnabled = configuration.policy.runtimeSwitchEnabled
        self.allEligibleEnabled = configuration.policy.allowAllEligible
        self.uiMutated = false
        self.resourceMoved = false
        self.uploadJobCreated = false
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? status.rawValue
        self.redacted = redacted
    }

    nonisolated var diagnosticsSummary: String {
        [
            "status=\(status.rawValue)",
            "recommendation=\(recommendation.rawValue)",
            "mode=\(mode.rawValue)",
            "rootMode=\(rootMode.rawValue)",
            "domain=\(domain.rawValue)",
            "budget=\(canaryMaxObjectsPerSyncRun)",
            "selected=\(selectedCandidateCount)",
            "executed=\(executedCandidateCount)",
            "success=\(successfulCommitCount)",
            "failure=\(failedCommitCount)",
            "rollback=\(rollbackCount)",
            "rollbackFailure=\(rollbackFailureCount)",
            "legacyFallback=\(legacyFallbackCount)",
            "duplicateSuppression=\(duplicateSuppressionCount)",
            "noEligible=\(noEligibleCandidateCount)",
            "unsafeSkipped=\(unsafeCandidateSkippedCount)",
            "fatal=\(fatalBlockerCount)",
            "readSideEquivalent=\(readSideParallelEquivalent)",
            "readSideDivergent=\(readSideParallelDivergent)",
            "runtimeSwitch=\(runtimeSwitchEnabled)",
            "allEligible=\(allEligibleEnabled)",
            "uiMutated=\(uiMutated)",
            "resourceMoved=\(resourceMoved)",
            "uploadJobCreated=\(uploadJobCreated)",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=\(redacted)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalLibraryMetadataProductionCanaryInjectionResult: Codable, Equatable, Sendable {
    var configuration: CanonicalLibraryMetadataProductionCanaryConfiguration
    var injectionConfigured: Bool
    var executorInjected: Bool
    var applyPortInjected: Bool
    var armed: Bool
    var executed: Bool
    var succeeded: Bool
    var blockers: [CanonicalLibraryMetadataRealCanaryBlocker]
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var canaryResult: CanonicalLibraryMetadataCanaryResult?
    var cutoverResult: CanonicalLibraryMetadataCutoverResult?
    var selection: CanonicalLibraryMetadataCanarySelectionResult?
    var candidateSafetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety]?
    var productionRootGate: CanonicalLibraryMetadataProductionRootGateResult?
    var productionRootSafetyProof: CanonicalLibraryMetadataProductionRootSafetyProof?
    var observationReport: CanonicalLibraryMetadataRealCanaryObservationReport

    nonisolated init(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        injectionConfigured: Bool,
        executorInjected: Bool,
        applyPortInjected: Bool,
        armed: Bool,
        executed: Bool,
        succeeded: Bool,
        blockers: [CanonicalLibraryMetadataRealCanaryBlocker],
        diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic],
        canaryResult: CanonicalLibraryMetadataCanaryResult? = nil,
        cutoverResult: CanonicalLibraryMetadataCutoverResult? = nil,
        selection: CanonicalLibraryMetadataCanarySelectionResult? = nil,
        candidateSafetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety]? = nil,
        productionRootGate: CanonicalLibraryMetadataProductionRootGateResult? = nil,
        productionRootSafetyProof: CanonicalLibraryMetadataProductionRootSafetyProof? = nil,
        observationReport: CanonicalLibraryMetadataRealCanaryObservationReport
    ) {
        self.configuration = configuration
        self.injectionConfigured = injectionConfigured
        self.executorInjected = executorInjected
        self.applyPortInjected = applyPortInjected
        self.armed = armed
        self.executed = executed
        self.succeeded = succeeded
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.diagnostics = diagnostics
        self.canaryResult = canaryResult
        self.cutoverResult = cutoverResult
        self.selection = selection
        self.candidateSafetyReports = candidateSafetyReports
        self.productionRootGate = productionRootGate
        self.productionRootSafetyProof = productionRootSafetyProof
        self.observationReport = observationReport
    }
}

nonisolated struct CanonicalLibraryMetadataProductionCanaryInjection: Sendable {
    nonisolated init() {}

    nonisolated func evaluateOrRun(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) async -> CanonicalLibraryMetadataProductionCanaryInjectionResult {
        let executorInjected = executor != nil
        let applyPortInjected = evidence.realRootBoundApplyPortAvailable
            && evidence.applyPortMode.isNonDryRunRootBound
        var diagnostics = [
            diagnostic(
                .canonicalLibraryMetadataRealCanaryInjectionConfigured,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: configuration.mode.isConfigured ? "configured" : "disabled",
                reason: "mode=\(configuration.mode.rawValue);rootMode=\(configuration.rootMode.rawValue);budget=\(configuration.canaryMaxObjectsPerSyncRun);explicitInternal=\(configuration.explicitInternalDebugConfiguration)"
            )
        ]

        if configuration.mode == .disabled {
            let blockers: [CanonicalLibraryMetadataRealCanaryBlocker] = [.disabled]
            let report = observation(
                status: .disabled,
                configuration: configuration,
                selection: nil,
                safetyReports: [],
                cutoverResult: nil,
                evidence: evidence,
                blockers: blockers,
                reason: "defaultDisabled"
            )
            return result(
                configuration: configuration,
                executorInjected: false,
                applyPortInjected: false,
                armed: false,
                executed: false,
                succeeded: false,
                blockers: blockers,
                diagnostics: diagnostics,
                report: report
            )
        }

        if configuration.mode == .diagnosticsOnly {
            let report = observation(
                status: .diagnosticsOnly,
                configuration: configuration,
                selection: nil,
                safetyReports: [],
                cutoverResult: nil,
                evidence: evidence,
                blockers: [.diagnosticsOnlyNoExecution],
                reason: "diagnosticsOnlyNoExecution"
            )
            return result(
                configuration: configuration,
                executorInjected: executorInjected,
                applyPortInjected: applyPortInjected,
                armed: false,
                executed: false,
                succeeded: false,
                blockers: [.diagnosticsOnlyNoExecution],
                diagnostics: diagnostics,
                selection: nil,
                candidateSafetyReports: [],
                report: report
            )
        }

        let productionRootGate = configuration.rootMode == .productionRootExplicit
            ? CanonicalLibraryMetadataProductionRootGate().evaluate(
                configuration: configuration,
                token: token,
                evidence: evidence,
                matrix: matrix,
                candidates: candidates,
                trigger: trigger,
                localSnapshotAvailable: localSnapshotAvailable,
                peerSnapshotAvailable: peerSnapshotAvailable,
                executorAvailable: executorInjected
            )
            : nil
        if let productionRootGate {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataProductionRootGateEvaluated,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: productionRootGate.selectedCandidate?.domain,
                    objectID: productionRootGate.selectedCandidate?.objectID,
                    objectKind: productionRootGate.selectedCandidate?.objectKind,
                    action: productionRootGate.selectedCandidate?.actionKind.rawValue,
                    result: productionRootGate.allowed ? "allowed" : "blocked",
                    reason: productionRootGate.diagnosticsSummary
                )
            )
            diagnostics.append(
                diagnostic(
                    productionRootGate.allowed
                        ? .canonicalLibraryMetadataProductionRootGateAllowed
                        : .canonicalLibraryMetadataProductionRootGateBlocked,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: productionRootGate.selectedCandidate?.domain,
                    objectID: productionRootGate.selectedCandidate?.objectID,
                    objectKind: productionRootGate.selectedCandidate?.objectKind,
                    action: productionRootGate.selectedCandidate?.actionKind.rawValue,
                    result: productionRootGate.allowed ? "allowed" : "blocked",
                    reason: productionRootGate.allowed
                        ? "productionRootExplicitGateAllowed"
                        : productionRootGate.blockers.map(\.rawValue).joined(separator: ",")
                )
            )
        }
        let strictBlockers = strictBlockers(
            configuration: configuration,
            token: token,
            evidence: evidence,
            matrix: matrix,
            trigger: trigger,
            localSnapshotAvailable: localSnapshotAvailable,
            peerSnapshotAvailable: peerSnapshotAvailable,
            executorAvailable: executorInjected
        )
        let blockers = Array(Set(strictBlockers + (productionRootGate?.blockers.map { realCanaryBlocker(for: $0) } ?? [])))
            .sorted { $0.rawValue < $1.rawValue }
        let selection = selection(evidence: evidence, candidates: candidates, trigger: trigger)
        let safetyReports = candidates.map {
            CanonicalLibraryMetadataCanaryCandidateSafety(candidate: $0, evidence: evidence)
        }
        let unsafeSkipped = safetyReports.contains { !$0.safe }

        if configuration.mode == .canaryN1Armed, blockers.isEmpty {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataRealCanaryArmed,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "armed",
                    reason: "commitSuppressed=true"
                )
            )
            let report = observation(
                status: .armed,
                configuration: configuration,
                selection: selection,
                safetyReports: safetyReports,
                cutoverResult: nil,
                evidence: evidence,
                blockers: [.armedNoExecution],
                reason: "armedNoExecution"
            )
            return result(
                configuration: configuration,
                executorInjected: executorInjected,
                applyPortInjected: applyPortInjected,
                armed: true,
                executed: false,
                succeeded: false,
                blockers: [.armedNoExecution],
                diagnostics: diagnostics,
                selection: selection,
                candidateSafetyReports: safetyReports,
                productionRootGate: productionRootGate,
                report: report
            )
        }

        if configuration.mode == .canaryN1Armed || configuration.mode == .blocked || !blockers.isEmpty {
            let effectiveBlockers = configuration.mode == .canaryN1Armed && blockers.isEmpty
                ? [.armedNoExecution]
                : blockers
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataRealCanaryBlocked,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: effectiveBlockers.map(\.rawValue).joined(separator: ",")
                )
            )
            let report = observation(
                status: .blocked,
                configuration: configuration,
                selection: selection,
                safetyReports: safetyReports,
                cutoverResult: nil,
                evidence: evidence,
                blockers: effectiveBlockers,
                reason: effectiveBlockers.map(\.rawValue).joined(separator: ",")
            )
            return result(
                configuration: configuration,
                executorInjected: executorInjected,
                applyPortInjected: applyPortInjected,
                armed: false,
                executed: false,
                succeeded: false,
                blockers: effectiveBlockers,
                diagnostics: diagnostics,
                selection: selection,
                candidateSafetyReports: safetyReports,
                productionRootGate: productionRootGate,
                report: report
            )
        }

        if selection.selectedCutoverCandidates.isEmpty {
            let noEligibleBlockers: [CanonicalLibraryMetadataRealCanaryBlocker] = [
                unsafeSkipped ? .unsafeCandidateSkipped : .noEligibleCandidate
            ]
            diagnostics.append(
                diagnostic(
                    unsafeSkipped ? .canonicalLibraryMetadataRealCanaryUnsafeCandidateSkipped : .canonicalLibraryMetadataRealCanaryNoEligibleCandidate,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: selection.blockers.map(\.reason.rawValue).joined(separator: ",")
                )
            )
            let report = observation(
                status: unsafeSkipped ? .unsafeCandidateSkipped : .noEligibleCandidate,
                configuration: configuration,
                selection: selection,
                safetyReports: safetyReports,
                cutoverResult: nil,
                evidence: evidence,
                blockers: noEligibleBlockers,
                reason: unsafeSkipped ? "unsafeCandidateSkipped" : "noEligibleCandidate"
            )
            return result(
                configuration: configuration,
                executorInjected: executorInjected,
                applyPortInjected: applyPortInjected,
                armed: true,
                executed: false,
                succeeded: false,
                blockers: noEligibleBlockers,
                diagnostics: diagnostics,
                selection: selection,
                candidateSafetyReports: safetyReports,
                productionRootGate: productionRootGate,
                report: report
            )
        }

        diagnostics.append(
            diagnostic(
                .canonicalLibraryMetadataRealCanaryExecutionStarted,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                domain: selection.selectedCutoverCandidates.first?.domain,
                objectID: selection.selectedCutoverCandidates.first?.objectID,
                objectKind: selection.selectedCutoverCandidates.first?.objectKind,
                action: selection.selectedCutoverCandidates.first?.cutoverActionKind.rawValue,
                result: "started",
                reason: "strictN1"
            )
        )
        if configuration.rootMode == .productionRootExplicit {
            let selected = selection.selectedCutoverCandidates.first
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataProductionRootN1Started,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: selected?.domain,
                    objectID: selected?.objectID,
                    objectKind: selected?.objectKind,
                    action: selected?.cutoverActionKind.rawValue,
                    result: "started",
                    reason: "explicitProductionRootStrictN1"
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataProductionRootCheckpointCreated,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: selected?.domain,
                    objectID: selected?.objectID,
                    objectKind: selected?.objectKind,
                    action: selected?.cutoverActionKind.rawValue,
                    result: "created",
                    reason: selected?.effectiveRollbackCheckpointID
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataProductionRootAtomicWriteStarted,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: selected?.domain,
                    objectID: selected?.objectID,
                    objectKind: selected?.objectKind,
                    action: selected?.cutoverActionKind.rawValue,
                    result: "started",
                    reason: "rootBoundAtomicMetadataWrite"
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataRealCanaryProductionRootWriteStarted,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "started",
                    reason: "explicitProductionRoot"
                )
            )
        }

        let canaryResult = await CanonicalLibraryMetadataN1CanaryRunner().run(
            configuration: configuration.asN1CanaryConfiguration,
            policy: configuration.policy.asCanaryPolicy,
            token: token,
            evidence: evidence,
            matrix: matrix,
            candidates: selection.selectedCutoverCandidates,
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID,
            localSnapshotAvailable: localSnapshotAvailable,
            peerSnapshotAvailable: peerSnapshotAvailable,
            executor: executor
        )
        let cutoverResult = canaryResult.cutoverResult
        let succeeded = canaryResult.succeeded
        let productionRootSafetyProof = productionRootGate.map {
            CanonicalLibraryMetadataProductionRootSafetyProof(
                gate: $0,
                cutoverResult: cutoverResult,
                configuration: configuration
            )
        }
        diagnostics.append(contentsOf: canaryResult.cutoverResult.diagnostics)
        diagnostics.append(
            diagnostic(
                succeeded ? .canonicalLibraryMetadataRealCanaryExecutionCompleted : .canonicalLibraryMetadataRealCanaryExecutionFailed,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: succeeded ? "completed" : "failed",
                reason: succeeded ? "strictN1Success" : "legacyFallbackPreserved"
            )
        )
        if configuration.rootMode == .productionRootExplicit {
            if let commit = cutoverResult.commits.first, commit.committed {
                diagnostics.append(
                    diagnostic(
                        .canonicalLibraryMetadataProductionRootAtomicWriteCompleted,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: commit.domain,
                        objectID: commit.objectID,
                        objectKind: commit.objectKind,
                        action: commit.actionKind.rawValue,
                        result: "completed",
                        reason: "rootBoundAtomicMetadataWrite",
                        hashPrefix: commit.metadataHashPrefix
                    )
                )
            }
            if let commit = cutoverResult.commits.first, commit.postconditionVerified {
                diagnostics.append(
                    diagnostic(
                        .canonicalLibraryMetadataProductionRootPostconditionVerified,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: commit.domain,
                        objectID: commit.objectID,
                        objectKind: commit.objectKind,
                        action: commit.actionKind.rawValue,
                        result: "verified",
                        reason: "postconditionVerified",
                        hashPrefix: commit.metadataHashPrefix
                    )
                )
            }
            diagnostics.append(
                diagnostic(
                    succeeded
                        ? .canonicalLibraryMetadataProductionRootN1Completed
                        : .canonicalLibraryMetadataProductionRootN1Failed,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: succeeded ? "completed" : "failed",
                    reason: succeeded ? "strictN1Success" : "rollbackOrFallbackRequired"
                )
            )
            diagnostics.append(
                diagnostic(
                    succeeded ? .canonicalLibraryMetadataRealCanaryProductionRootWriteCompleted : .canonicalLibraryMetadataRealCanaryProductionRootWriteFailed,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: succeeded ? "completed" : "failed",
                    reason: succeeded ? "explicitProductionRoot" : "rollbackOrFallbackRequired"
                )
            )
            if let productionRootSafetyProof {
                diagnostics.append(
                    diagnostic(
                        .canonicalLibraryMetadataProductionRootSafetyProofBuilt,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        result: "built",
                        reason: productionRootSafetyProof.redactedTargetSummary
                    )
                )
            }
        }
        for rollback in cutoverResult.rollbackResults {
            if configuration.rootMode == .productionRootExplicit {
                diagnostics.append(
                    diagnostic(
                        .canonicalLibraryMetadataProductionRootRollbackStarted,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        result: "started",
                        reason: rollback.checkpointID
                    )
                )
            }
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataRealCanaryRollbackStarted,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "started",
                    reason: rollback.checkpointID
                )
            )
            if configuration.rootMode == .productionRootExplicit {
                diagnostics.append(
                    diagnostic(
                        rollback.succeeded
                            ? .canonicalLibraryMetadataProductionRootRollbackCompleted
                            : .canonicalLibraryMetadataProductionRootRollbackFailed,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        result: rollback.succeeded ? "completed" : "failed",
                        reason: rollback.reason
                    )
                )
            }
            diagnostics.append(
                diagnostic(
                    rollback.succeeded ? .canonicalLibraryMetadataRealCanaryRollbackCompleted : .canonicalLibraryMetadataRealCanaryRollbackFailed,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: rollback.succeeded ? "completed" : "failed",
                    reason: rollback.reason
                )
            )
        }
        if cutoverResult.legacyFallbackUsed {
            if configuration.rootMode == .productionRootExplicit {
                diagnostics.append(
                    diagnostic(
                        .canonicalLibraryMetadataProductionRootLegacyFallbackUsed,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        result: "used",
                        reason: "commitFailureOrRollback"
                    )
                )
            }
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataRealCanaryLegacyFallbackUsed,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "used",
                    reason: "commitFailureOrRollback"
                )
            )
        }
        if !cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty {
            if configuration.rootMode == .productionRootExplicit {
                diagnostics.append(
                    diagnostic(
                        .canonicalLibraryMetadataProductionRootDuplicateSuppressed,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        result: "successOnly",
                        reason: "matchingLegacyLibraryMetadataOnly"
                    )
                )
            }
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataRealCanaryDuplicateLegacySuppressed,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "successOnly",
                    reason: "matchingLegacyLibraryMetadataOnly"
                )
            )
        }
        let readSideEquivalent = cutoverResult.readSideProjection?.equivalent ?? evidence.readSideParallelEquivalent
        if configuration.rootMode == .productionRootExplicit {
            diagnostics.append(
                diagnostic(
                    readSideEquivalent
                        ? .canonicalLibraryMetadataProductionRootReadSideEquivalent
                        : .canonicalLibraryMetadataProductionRootReadSideDivergent,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: cutoverResult.readSideProjection?.domain,
                    objectID: cutoverResult.readSideProjection?.objectID,
                    objectKind: cutoverResult.readSideProjection?.objectKind,
                    result: readSideEquivalent ? "equivalent" : "divergent",
                    reason: cutoverResult.readSideProjection?.reason ?? "readSideEvidence"
                )
            )
        }
        diagnostics.append(
            diagnostic(
                readSideEquivalent ? .canonicalLibraryMetadataRealCanaryReadSideEquivalent : .canonicalLibraryMetadataRealCanaryReadSideDivergent,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: readSideEquivalent ? "equivalent" : "divergent",
                reason: cutoverResult.readSideProjection?.reason ?? "readSideEvidence"
            )
        )
        if cutoverResult.fatalBlocker {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataRealCanaryFatalBlocker,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "fatal",
                    reason: "rollbackFailure"
                )
            )
        }
        let report = observation(
            status: succeeded ? .executedSucceeded : (cutoverResult.fatalBlocker ? .fatalRollbackFailure : .executedFailedRolledBack),
            configuration: configuration,
            selection: selection,
            safetyReports: safetyReports,
            cutoverResult: cutoverResult,
            evidence: evidence,
            blockers: cutoverResult.fatalBlocker ? [.fatalBlocker] : [],
            reason: succeeded ? "strictN1Success" : "legacyFallbackPreserved"
        )
        return result(
            configuration: configuration,
            executorInjected: executorInjected,
            applyPortInjected: applyPortInjected,
            armed: true,
            executed: !cutoverResult.commits.isEmpty,
            succeeded: succeeded,
            blockers: cutoverResult.fatalBlocker ? [.fatalBlocker] : [],
            diagnostics: diagnostics,
            canaryResult: canaryResult,
            cutoverResult: cutoverResult,
            selection: selection,
            candidateSafetyReports: safetyReports,
            productionRootGate: productionRootGate,
            productionRootSafetyProof: productionRootSafetyProof,
            report: report
        )
    }

    private nonisolated func strictBlockers(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix,
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        executorAvailable: Bool
    ) -> [CanonicalLibraryMetadataRealCanaryBlocker] {
        var blockers: [CanonicalLibraryMetadataRealCanaryBlocker] = []
        if configuration.mode == .blocked {
            blockers.append(.blockedMode)
        }
        if configuration.mode != .canaryN1Execute && configuration.mode != .canaryN1Armed {
            blockers.append(.blockedMode)
        }
        if configuration.policy.domain != .libraryMetadata {
            blockers.append(.nonLibraryMetadataDomain)
        }
        if configuration.policy.canaryMaxObjectsPerSyncRun != 1 {
            blockers.append(configuration.policy.canaryMaxObjectsPerSyncRun > 1 ? .canaryBudgetAboveOneDenied : .n1BudgetRequired)
        }
        if configuration.policy.runtimeSwitchEnabled {
            blockers.append(.runtimeSwitchDenied)
        }
        if configuration.policy.allowAllEligible {
            blockers.append(.allEligibleDenied)
        }
        if configuration.policy.releaseDefaultEnabled {
            blockers.append(.releaseDefaultDenied)
        }
        if configuration.allowProductionRootWrites && configuration.rootMode != .productionRootExplicit {
            blockers.append(.allowProductionRootWritesDeniedV830)
        }
        if configuration.policy.requiresExplicitInternalDebugConfiguration,
           !configuration.explicitInternalDebugConfiguration {
            blockers.append(.missingExplicitInternalDebugConfiguration)
        }
        let matrixReport = matrix.validate()
        if !matrixReport.allowed {
            blockers.append(.matrixValidationBlocked)
        }
        if matrixReport.activePilotDomain != .libraryMetadata {
            blockers.append(.activePilotNotLibraryMetadata)
        }
        if configuration.policy.requiresProductionToken, token == nil {
            blockers.append(.missingToken)
        }
        if configuration.policy.requiresOwnerApproval, token?.ownerApproved != true {
            blockers.append(.missingOwnerApproval)
        }
        if !localSnapshotAvailable {
            blockers.append(.localSnapshotUnavailable)
        }
        if !peerSnapshotAvailable {
            blockers.append(.peerSnapshotUnavailable)
        }
        if !executorAvailable {
            blockers.append(.commitExecutorUnavailable)
        }
        if trigger == .viewRefresh || trigger == .retryDrainer {
            blockers.append(.unsupportedTrigger)
        }
        if !evidence.noCommitEvidenceAvailable { blockers.append(.missingNoCommitEvidence) }
        if !evidence.realDataShadowCopyVerified { blockers.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.executionShadowVerified { blockers.append(.missingExecutionShadowEvidence) }
        if !evidence.dryRunEquivalenceVerified { blockers.append(.missingDryRunEquivalence) }
        if !evidence.noBlockingDivergence { blockers.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict { blockers.append(.unresolvedConflict) }
        if !evidence.metadataManifestRouteEvidenceAvailable { blockers.append(.missingMetadataManifestRouteEvidence) }
        if !evidence.productionPortAvailable { blockers.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { blockers.append(.realApplyPortUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { blockers.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { blockers.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { blockers.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { blockers.append(.rollbackCheckpointUnavailable) }
        if configuration.policy.requiresRollbackPlan, evidence.rollbackPlan == nil {
            blockers.append(.rollbackPlanMissing)
        }
        if !evidence.rollbackVerified || !evidence.rollbackRehearsalPassed {
            blockers.append(.rollbackVerificationMissing)
        }
        if !configuration.policy.productionRootDisabledByDefault || !evidence.productionRootDisabledByDefault {
            blockers.append(.productionRootGuardMissing)
        }
        switch configuration.rootMode {
        case .disabled:
            blockers.append(.productionRootNotExplicit)
        case .testRoot:
            if evidence.applyPortMode != .testRootBound || !evidence.testRootUsed {
                blockers.append(.testRootMissing)
            }
        case .productionRootExplicit:
            if !configuration.allowProductionRootWrites {
                blockers.append(.productionRootWritesDisabled)
            }
            if evidence.applyPortMode != .productionRootBound {
                blockers.append(.productionRootGuardMissing)
            }
        }
        if !evidence.legacyFallbackAvailable {
            blockers.append(.legacyFallbackUnavailable)
        }
        if configuration.policy.requiresReadSideParallelEquivalent {
            if !evidence.readSideParallelEquivalent {
                blockers.append(.readSideParallelDivergent)
            }
        }
        return Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated func realCanaryBlocker(
        for blocker: CanonicalLibraryMetadataProductionRootBlocker
    ) -> CanonicalLibraryMetadataRealCanaryBlocker {
        switch blocker {
        case .missingExplicitDebugInternalConfiguration:
            return .missingExplicitInternalDebugConfiguration
        case .modeNotExecuteN1Canary:
            return .blockedMode
        case .rootModeNotProductionRootExplicit:
            return .productionRootNotExplicit
        case .allowProductionRootWritesFalse:
            return .productionRootWritesDisabled
        case .missingOwnerApproval:
            return .missingOwnerApproval
        case .activePilotNotLibraryMetadata, .multipleActivePilots:
            return .activePilotNotLibraryMetadata
        case .runtimeSwitchEnabled:
            return .runtimeSwitchDenied
        case .landingFreezeNotGreen:
            return .matrixValidationBlocked
        case .diagnosticsOnlyEvidenceMissing:
            return .missingNoCommitEvidence
        case .armN1EvidenceMissing:
            return .missingExecutionShadowEvidence
        case .testRootExecuteEvidenceMissing:
            return .testRootMissing
        case .readSideDivergenceNonZero:
            return .readSideParallelDivergent
        case .rollbackEvidenceMissing:
            return .rollbackVerificationMissing
        case .legacyFallbackUnavailable:
            return .legacyFallbackUnavailable
        case .safeCandidateMissing:
            return .noEligibleCandidate
        case .multipleSafeCandidatesDenied, .n1BudgetRequired:
            return .canaryBudgetAboveOneDenied
        case .unsafeCandidateSelected,
             .noResourceMoveGuardMissing,
             .resourceMoveAttempted,
             .noContentWriteGuardMissing,
             .contentWriteAttempted,
             .tombstoneDeleteAttempted:
            return .unsafeCandidateSkipped
        case .productionRootContainmentUnverified:
            return .productionRootGuardMissing
        case .checkpointUnavailable:
            return .rollbackCheckpointUnavailable
        case .postconditionVerificationUnavailable:
            return .atomicReplaceUnavailable
        case .allEligibleDenied:
            return .allEligibleDenied
        case .nonLibraryMetadataDomain:
            return .nonLibraryMetadataDomain
        case .releaseDefaultDenied:
            return .releaseDefaultDenied
        case .defaultEnablementDenied:
            return .defaultEnablementDenied
        case .localSnapshotUnavailable:
            return .localSnapshotUnavailable
        case .peerSnapshotUnavailable:
            return .peerSnapshotUnavailable
        case .commitExecutorUnavailable:
            return .commitExecutorUnavailable
        case .unsupportedTrigger:
            return .unsupportedTrigger
        case .productionPortUnavailable:
            return .productionPortUnavailable
        case .realApplyPortUnavailable:
            return .realApplyPortUnavailable
        case .rootBoundWriteUnavailable:
            return .rootBoundWriteUnavailable
        case .atomicWriteUnavailable:
            return .atomicReplaceUnavailable
        }
    }

    private nonisolated func selection(
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger
    ) -> CanonicalLibraryMetadataCanarySelectionResult {
        CanonicalLibraryMetadataCanarySelector().select(
            mode: .canary,
            policy: CanonicalLibraryMetadataCanaryPolicy(
                canaryMaxObjectsPerSyncRun: 1,
                allowsInternalN1Execution: true,
                explicitInternalTestConfiguration: true
            ),
            trigger: trigger,
            evidence: evidence,
            candidates: candidates
        )
    }

    private nonisolated func observation(
        status: CanonicalLibraryMetadataRealCanaryObservationStatus,
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        selection: CanonicalLibraryMetadataCanarySelectionResult?,
        safetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety],
        cutoverResult: CanonicalLibraryMetadataCutoverResult?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        blockers: [CanonicalLibraryMetadataRealCanaryBlocker],
        reason: String
    ) -> CanonicalLibraryMetadataRealCanaryObservationReport {
        let successfulCommitCount = cutoverResult?.commits.filter {
            $0.committed && $0.preconditionVerified && $0.postconditionVerified
        }.count ?? 0
        let failedCommitCount = (cutoverResult?.commits.count ?? 0) - successfulCommitCount
        let rollbackFailureCount = cutoverResult?.rollbackResults.filter { !$0.succeeded || $0.fatal }.count ?? 0
        let noEligible = status == .noEligibleCandidate || selection?.selectedCandidates.isEmpty == true
        let unsafeSkipped = safetyReports.filter { !$0.safe }.count
        let fatal = cutoverResult?.fatalBlocker == true || status == .fatalRollbackFailure
        let duplicateSuppressionCount = cutoverResult?.duplicateLegacySuppressedActionIDs.count ?? 0
        return CanonicalLibraryMetadataRealCanaryObservationReport(
            status: status,
            recommendation: recommendation(
                status: status,
                blockers: blockers,
                successfulCommitCount: successfulCommitCount,
                failedCommitCount: failedCommitCount,
                rollbackFailureCount: rollbackFailureCount,
                readSideEquivalent: cutoverResult?.readSideProjection?.equivalent ?? evidence.readSideParallelEquivalent
            ),
            configuration: configuration,
            selectedCandidateCount: selection?.selectedCandidates.count ?? 0,
            executedCandidateCount: cutoverResult?.commits.count ?? 0,
            successfulCommitCount: successfulCommitCount,
            failedCommitCount: failedCommitCount,
            rollbackCount: cutoverResult?.rollbackResults.count ?? 0,
            rollbackFailureCount: rollbackFailureCount,
            legacyFallbackCount: cutoverResult?.legacyFallbackUsed == true || !blockers.isEmpty ? 1 : 0,
            duplicateSuppressionCount: duplicateSuppressionCount,
            noEligibleCandidateCount: noEligible ? 1 : 0,
            unsafeCandidateSkippedCount: unsafeSkipped,
            fatalBlockerCount: fatal ? 1 : 0,
            readSideParallelEquivalent: cutoverResult?.readSideProjection?.equivalent ?? evidence.readSideParallelEquivalent,
            readSideParallelDivergent: (cutoverResult?.readSideProjection?.equivalent == false) || !evidence.readSideParallelEquivalent,
            legacyFallbackPreserved: cutoverResult?.legacyFallbackUsed == true || successfulCommitCount == 0 || !blockers.isEmpty,
            duplicateSuppressionApplied: duplicateSuppressionCount > 0,
            productionRootWriteAttempted: configuration.rootMode == .productionRootExplicit && (cutoverResult?.commits.isEmpty == false),
            blockers: blockers,
            reason: reason
        )
    }

    private nonisolated func recommendation(
        status: CanonicalLibraryMetadataRealCanaryObservationStatus,
        blockers: [CanonicalLibraryMetadataRealCanaryBlocker],
        successfulCommitCount: Int,
        failedCommitCount: Int,
        rollbackFailureCount: Int,
        readSideEquivalent: Bool
    ) -> CanonicalLibraryMetadataRealCanaryRecommendation {
        if status == .disabled || status == .diagnosticsOnly {
            return .remainDisabled
        }
        if !blockers.isEmpty || failedCommitCount > 0 || rollbackFailureCount > 0 || !readSideEquivalent {
            return .fixBlockers
        }
        if successfulCommitCount == 1, status == .executedSucceeded {
            return .stayN1
        }
        return .stayN1
    }

    private nonisolated func result(
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        executorInjected: Bool,
        applyPortInjected: Bool,
        armed: Bool,
        executed: Bool,
        succeeded: Bool,
        blockers: [CanonicalLibraryMetadataRealCanaryBlocker],
        diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic],
        canaryResult: CanonicalLibraryMetadataCanaryResult? = nil,
        cutoverResult: CanonicalLibraryMetadataCutoverResult? = nil,
        selection: CanonicalLibraryMetadataCanarySelectionResult? = nil,
        candidateSafetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety]? = nil,
        productionRootGate: CanonicalLibraryMetadataProductionRootGateResult? = nil,
        productionRootSafetyProof: CanonicalLibraryMetadataProductionRootSafetyProof? = nil,
        report: CanonicalLibraryMetadataRealCanaryObservationReport
    ) -> CanonicalLibraryMetadataProductionCanaryInjectionResult {
        CanonicalLibraryMetadataProductionCanaryInjectionResult(
            configuration: configuration,
            injectionConfigured: configuration.mode.isConfigured,
            executorInjected: executorInjected,
            applyPortInjected: applyPortInjected,
            armed: armed,
            executed: executed,
            succeeded: succeeded,
            blockers: blockers,
            diagnostics: diagnostics,
            canaryResult: canaryResult,
            cutoverResult: cutoverResult,
            selection: selection,
            candidateSafetyReports: candidateSafetyReports,
            productionRootGate: productionRootGate,
            productionRootSafetyProof: productionRootSafetyProof,
            observationReport: report
        )
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalLibraryMetadataCutoverDiagnosticKind,
        configuration: CanonicalLibraryMetadataProductionCanaryConfiguration,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalLibraryMetadataCutoverDomain? = nil,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        action: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil,
        hashPrefix: String? = nil
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        let diagnosticHash = hash ?? hashPrefix.map { CanonicalHash($0) }
        return CanonicalLibraryMetadataCutoverDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            domain: domain,
            objectID: objectID,
            objectKind: objectKind,
            action: action,
            result: result,
            reason: [
                reason,
                "mode=\(configuration.mode.rawValue)",
                "rootMode=\(configuration.rootMode.rawValue)"
            ].compactMap { $0 }.joined(separator: ";"),
            hash: diagnosticHash
        )
    }
}
