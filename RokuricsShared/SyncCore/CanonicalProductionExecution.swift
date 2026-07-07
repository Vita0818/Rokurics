//
//  CanonicalProductionExecution.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalProductionSideEffectKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case fileRead
    case fileWrite
    case metadataApply
    case generatedArtifactApply
    case networkRequest
    case uploadSessionStart
    case uploadChunkSend
    case uploadFinalize
    case tombstoneMark
    case conflictRecord
    case diagnosticsWrite
}

nonisolated struct CanonicalProductionSideEffect: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, domain.rawValue, objectID ?? "", artifactID ?? "", route?.rawValue ?? ""].joined(separator: "|") }

    var kind: CanonicalProductionSideEffectKind
    var domain: CanonicalProductionDomain
    var objectID: String?
    var artifactID: String?
    var route: CanonicalTransportRoute?
    var byteSize: Int64?
    var hashPrefix: String?
    var redactedSummary: String

    nonisolated init(
        kind: CanonicalProductionSideEffectKind,
        domain: CanonicalProductionDomain,
        objectID: String? = nil,
        artifactID: String? = nil,
        route: CanonicalTransportRoute? = nil,
        byteSize: Int64? = nil,
        hash: CanonicalHash? = nil,
        hashPrefix: String? = nil,
        summary: String
    ) {
        self.kind = kind
        self.domain = domain
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.route = route
        self.byteSize = byteSize
        self.hashPrefix = hash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
            ?? CanonicalProductionRedaction.hashPrefix(hashPrefix)
        self.redactedSummary = CanonicalProductionRedaction.safeDiagnosticText(summary) ?? kind.rawValue
    }
}

nonisolated struct CanonicalProductionExecutionTrace: Codable, Equatable, Sendable {
    var operationID: String
    var mode: CanonicalKernelExecutionMode
    var generatedAt: CanonicalTimestamp
    var sideEffects: [CanonicalProductionSideEffect]

    nonisolated init(
        operationID: String,
        mode: CanonicalKernelExecutionMode,
        sideEffects: [CanonicalProductionSideEffect] = [],
        generatedAt: Date = Date()
    ) {
        self.operationID = CanonicalProductionRedaction.safeIdentifier(operationID, fallback: "canonical-operation")
        self.mode = mode
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.sideEffects = sideEffects
    }

    nonisolated var redactedSummaries: [String] {
        sideEffects.map(\.redactedSummary)
    }
}

nonisolated struct CanonicalProductionExecutionFailure: Codable, Equatable, Identifiable, Sendable {
    var id: String { [operationID, reason, domain?.rawValue ?? ""].joined(separator: "|") }

    var operationID: String
    var domain: CanonicalProductionDomain?
    var reason: String

    nonisolated init(operationID: String, domain: CanonicalProductionDomain? = nil, reason: String) {
        self.operationID = CanonicalProductionRedaction.safeIdentifier(operationID, fallback: "canonical-operation")
        self.domain = domain
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? "productionExecutionFailed"
    }
}

nonisolated struct CanonicalProductionExecutionResult: Codable, Equatable, Sendable {
    var operationID: String
    var mode: CanonicalKernelExecutionMode
    var succeeded: Bool
    var trace: CanonicalProductionExecutionTrace
    var failures: [CanonicalProductionExecutionFailure]
    var guardAudit: CanonicalProductionExecutionAudit?

    nonisolated init(
        operationID: String,
        mode: CanonicalKernelExecutionMode,
        succeeded: Bool,
        sideEffects: [CanonicalProductionSideEffect] = [],
        failures: [CanonicalProductionExecutionFailure] = [],
        guardAudit: CanonicalProductionExecutionAudit? = nil,
        generatedAt: Date = Date()
    ) {
        self.operationID = CanonicalProductionRedaction.safeIdentifier(operationID, fallback: "canonical-operation")
        self.mode = mode
        self.succeeded = succeeded
        self.trace = CanonicalProductionExecutionTrace(
            operationID: self.operationID,
            mode: mode,
            sideEffects: sideEffects,
            generatedAt: generatedAt
        )
        self.failures = failures
        self.guardAudit = guardAudit
    }
}

nonisolated enum CanonicalProductionExecutionDomainRole: String, Codable, Equatable, Sendable {
    case iPhone
    case mac
    case testHarness
}

nonisolated struct CanonicalProductionExecutionToken: Codable, Equatable, Sendable {
    var mode: CanonicalKernelExecutionMode
    var domainAllowlist: [CanonicalProductionDomain]
    var nodeRole: CanonicalProductionExecutionDomainRole
    var syncRunID: String
    var dryRunEquivalentReportID: String?
    var rollbackPlanID: String?
    var ownerApproved: Bool

    nonisolated init(
        mode: CanonicalKernelExecutionMode,
        domainAllowlist: [CanonicalProductionDomain],
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String,
        dryRunEquivalentReportID: String? = nil,
        rollbackPlanID: String? = nil,
        ownerApproved: Bool = false
    ) {
        self.mode = mode
        self.domainAllowlist = Array(Set(domainAllowlist)).sorted { $0.rawValue < $1.rawValue }
        self.nodeRole = nodeRole
        self.syncRunID = CanonicalProductionRedaction.safeIdentifier(syncRunID, fallback: "sync-run")
        self.dryRunEquivalentReportID = dryRunEquivalentReportID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "dry-run-report")
        }
        self.rollbackPlanID = rollbackPlanID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "rollback-plan")
        }
        self.ownerApproved = ownerApproved
    }
}

nonisolated struct CanonicalProductionExecutionPolicy: Codable, Equatable, Sendable {
    var requiredDomains: [CanonicalProductionDomain]
    var requiredPorts: [CanonicalProductionPortKind]
    var requireOwnerApproval: Bool
    var requireRollbackPlan: Bool
    var requireDryRunEquivalence: Bool
    var requireMigrationGateUnblocked: Bool
    var rejectUnresolvedConflicts: Bool

    nonisolated init(
        requiredDomains: [CanonicalProductionDomain] = [.recordingMetadata, .fileRuntime],
        requiredPorts: [CanonicalProductionPortKind] = [.file, .transport, .upload, .apply],
        requireOwnerApproval: Bool = true,
        requireRollbackPlan: Bool = true,
        requireDryRunEquivalence: Bool = true,
        requireMigrationGateUnblocked: Bool = true,
        rejectUnresolvedConflicts: Bool = true
    ) {
        self.requiredDomains = Array(Set(requiredDomains)).sorted { $0.rawValue < $1.rawValue }
        self.requiredPorts = Array(Set(requiredPorts)).sorted { $0.rawValue < $1.rawValue }
        self.requireOwnerApproval = requireOwnerApproval
        self.requireRollbackPlan = requireRollbackPlan
        self.requireDryRunEquivalence = requireDryRunEquivalence
        self.requireMigrationGateUnblocked = requireMigrationGateUnblocked
        self.rejectUnresolvedConflicts = rejectUnresolvedConflicts
    }
}

nonisolated enum CanonicalProductionExecutionRejectionReason: String, Codable, Equatable, Hashable, Sendable {
    case modeDisabled
    case blockedProductionExecute
    case missingApproval
    case missingRollbackPlan
    case dryRunNotEquivalent
    case unsupportedDomain
    case unresolvedConflict
    case missingProductionPort
    case productionMigrationBlocked
}

nonisolated struct CanonicalProductionExecutionAudit: Codable, Equatable, Sendable {
    var generatedAt: CanonicalTimestamp
    var allowed: Bool
    var mode: CanonicalKernelExecutionMode
    var nodeRole: CanonicalProductionExecutionDomainRole?
    var requestedMode: CanonicalKernelExecutionMode
    var allowedMode: CanonicalKernelExecutionMode?
    var tokenSyncRunID: String?
    var rejectionReasons: [CanonicalProductionExecutionRejectionReason]
    var deniedSideEffects: [CanonicalProductionSideEffectKind]
    var rollbackAvailable: Bool
    var dryRunEquivalent: Bool
    var unresolvedConflictCount: Int
    var domains: [CanonicalProductionDomain]

    nonisolated init(
        allowed: Bool,
        mode: CanonicalKernelExecutionMode,
        nodeRole: CanonicalProductionExecutionDomainRole? = nil,
        requestedMode: CanonicalKernelExecutionMode? = nil,
        allowedMode: CanonicalKernelExecutionMode? = nil,
        tokenSyncRunID: String? = nil,
        rejectionReasons: [CanonicalProductionExecutionRejectionReason],
        deniedSideEffects: [CanonicalProductionSideEffectKind] = [],
        rollbackAvailable: Bool = false,
        dryRunEquivalent: Bool = false,
        unresolvedConflictCount: Int = 0,
        domains: [CanonicalProductionDomain],
        generatedAt: Date = Date()
    ) {
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.allowed = allowed
        self.mode = mode
        self.nodeRole = nodeRole
        self.requestedMode = requestedMode ?? mode
        self.allowedMode = allowedMode
        self.tokenSyncRunID = tokenSyncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.rejectionReasons = Array(Set(rejectionReasons)).sorted { $0.rawValue < $1.rawValue }
        self.deniedSideEffects = Array(Set(deniedSideEffects)).sorted { $0.rawValue < $1.rawValue }
        self.rollbackAvailable = rollbackAvailable
        self.dryRunEquivalent = dryRunEquivalent
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.domains = Array(Set(domains)).sorted { $0.rawValue < $1.rawValue }
    }
}

nonisolated struct CanonicalRollbackCheckpoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { checkpointID }

    var checkpointID: String
    var domain: CanonicalProductionDomain
    var objectID: String?
    var artifactID: String?
    var atomicBackupToken: String?

    nonisolated init(
        checkpointID: String,
        domain: CanonicalProductionDomain,
        objectID: String? = nil,
        artifactID: String? = nil,
        atomicBackupToken: String? = nil
    ) {
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "checkpoint")
        self.domain = domain
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.atomicBackupToken = atomicBackupToken.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "backup-token") }
    }
}

nonisolated enum CanonicalRollbackActionKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case metadataRollback
    case generatedArtifactRollback
    case tombstoneRollback
    case uploadSessionCancel
    case transportNoOpRollback
    case conflictLedgerNoOp
    case fileWriteRollback
}

nonisolated struct CanonicalRollbackAction: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID }

    var actionID: String
    var kind: CanonicalRollbackActionKind
    var domain: CanonicalProductionDomain
    var checkpointID: String?
    var objectID: String?
    var artifactID: String?

    nonisolated init(
        actionID: String,
        kind: CanonicalRollbackActionKind,
        domain: CanonicalProductionDomain,
        checkpointID: String? = nil,
        objectID: String? = nil,
        artifactID: String? = nil
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: kind.rawValue)
        self.kind = kind
        self.domain = domain
        self.checkpointID = checkpointID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "checkpoint") }
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
    }
}

nonisolated struct CanonicalRollbackPlan: Codable, Equatable, Identifiable, Sendable {
    var id: String { planID }

    var planID: String
    var checkpoints: [CanonicalRollbackCheckpoint]
    var actions: [CanonicalRollbackAction]
    var generatedAt: CanonicalTimestamp

    nonisolated init(
        planID: String,
        checkpoints: [CanonicalRollbackCheckpoint],
        actions: [CanonicalRollbackAction],
        generatedAt: Date = Date()
    ) {
        self.planID = CanonicalProductionRedaction.safeIdentifier(planID, fallback: "rollback-plan")
        self.checkpoints = checkpoints.sorted { $0.id < $1.id }
        self.actions = actions.sorted { $0.id < $1.id }
        self.generatedAt = CanonicalTimestamp(generatedAt)
    }

    nonisolated func covers(domain: CanonicalProductionDomain) -> Bool {
        actions.contains { $0.domain == domain }
    }

    nonisolated func coversAll(_ domains: [CanonicalProductionDomain]) -> Bool {
        domains.allSatisfy(covers(domain:))
    }
}

nonisolated struct CanonicalRollbackFailure: Codable, Equatable, Identifiable, Sendable {
    var id: String { [actionID, reason].joined(separator: "|") }

    var actionID: String
    var reason: String

    nonisolated init(actionID: String, reason: String) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: "rollback-action")
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? "rollbackFailed"
    }
}

nonisolated struct CanonicalRollbackResult: Codable, Equatable, Sendable {
    var planID: String
    var succeeded: Bool
    var completedActionIDs: [String]
    var failures: [CanonicalRollbackFailure]

    nonisolated init(
        planID: String,
        succeeded: Bool,
        completedActionIDs: [String] = [],
        failures: [CanonicalRollbackFailure] = []
    ) {
        self.planID = CanonicalProductionRedaction.safeIdentifier(planID, fallback: "rollback-plan")
        self.succeeded = succeeded
        self.completedActionIDs = Array(Set(completedActionIDs.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "rollback-action")
        })).sorted()
        self.failures = failures.sorted { $0.id < $1.id }
    }
}

nonisolated struct CanonicalRollbackAudit: Codable, Equatable, Sendable {
    var planID: String
    var requiredDomains: [CanonicalProductionDomain]
    var missingDomains: [CanonicalProductionDomain]
    var rollbackRequiredForProduction: Bool

    nonisolated init(plan: CanonicalRollbackPlan?, requiredDomains: [CanonicalProductionDomain]) {
        let required = Array(Set(requiredDomains)).sorted { $0.rawValue < $1.rawValue }
        self.planID = plan?.planID ?? "missing"
        self.requiredDomains = required
        self.missingDomains = required.filter { plan?.covers(domain: $0) != true }
        self.rollbackRequiredForProduction = true
    }
}

nonisolated enum CanonicalProductionExecutionGuard {
    nonisolated static func evaluate(
        mode: CanonicalKernelExecutionMode,
        token: CanonicalProductionExecutionToken?,
        policy: CanonicalProductionExecutionPolicy,
        domains: [CanonicalProductionDomain],
        ports: CanonicalProductionPortSet,
        rollbackPlan: CanonicalRollbackPlan?,
        dryRunReportID: String?,
        dryRunEquivalence: CanonicalDryRunEquivalenceReport?,
        readinessReport: CanonicalDryRunReadinessReport?,
        unresolvedConflictCount: Int,
        generatedAt: Date = Date()
    ) -> CanonicalProductionExecutionAudit {
        var reasons: [CanonicalProductionExecutionRejectionReason] = []
        let rollbackAvailable = rollbackPlan?.coversAll(policy.requiredDomains) == true
        let dryRunEquivalent = dryRunEquivalence?.legacyEquivalence.allEquivalent == true
            && dryRunEquivalence?.legacyEquivalence.hasBlockingDivergence != true
        guard mode == .productionExecute, let token, token.mode == .productionExecute else {
            return CanonicalProductionExecutionAudit(
                allowed: false,
                mode: mode,
                nodeRole: token?.nodeRole,
                requestedMode: token?.mode ?? mode,
                allowedMode: nil,
                tokenSyncRunID: token?.syncRunID,
                rejectionReasons: [.modeDisabled],
                deniedSideEffects: CanonicalProductionSideEffectKind.allCases,
                rollbackAvailable: rollbackAvailable,
                dryRunEquivalent: dryRunEquivalent,
                unresolvedConflictCount: unresolvedConflictCount,
                domains: domains,
                generatedAt: generatedAt
            )
        }

        if token.nodeRole != .testHarness {
            reasons.append(.blockedProductionExecute)
        }
        if policy.requireOwnerApproval && !token.ownerApproved {
            reasons.append(.missingApproval)
        }
        if !Set(policy.requiredDomains).isSubset(of: Set(token.domainAllowlist))
            || !Set(domains).isSubset(of: Set(token.domainAllowlist)) {
            reasons.append(.unsupportedDomain)
        }
        if policy.requireRollbackPlan {
            if rollbackPlan == nil
                || token.rollbackPlanID == nil
                || token.rollbackPlanID != rollbackPlan?.planID
                || rollbackPlan?.coversAll(policy.requiredDomains) != true {
                reasons.append(.missingRollbackPlan)
            }
        }
        if policy.requireDryRunEquivalence {
            if dryRunEquivalence == nil
                || dryRunEquivalence?.legacyEquivalence.allEquivalent != true
                || dryRunEquivalence?.legacyEquivalence.hasBlockingDivergence == true
                || token.dryRunEquivalentReportID == nil
                || token.dryRunEquivalentReportID != dryRunReportID {
                reasons.append(.dryRunNotEquivalent)
            }
        }
        if policy.rejectUnresolvedConflicts && unresolvedConflictCount > 0 {
            reasons.append(.unresolvedConflict)
        }
        if policy.requiredPorts.contains(where: { portMissingOrDryRun($0, ports: ports) }) {
            reasons.append(.missingProductionPort)
        }
        if policy.requireMigrationGateUnblocked && readinessReport?.productionMigrationBlocked != false {
            reasons.append(.productionMigrationBlocked)
        }

        return CanonicalProductionExecutionAudit(
            allowed: reasons.isEmpty,
            mode: mode,
            nodeRole: token.nodeRole,
            requestedMode: token.mode,
            allowedMode: reasons.isEmpty ? .productionExecute : nil,
            tokenSyncRunID: token.syncRunID,
            rejectionReasons: reasons,
            deniedSideEffects: reasons.isEmpty ? [] : CanonicalProductionSideEffectKind.allCases,
            rollbackAvailable: rollbackAvailable,
            dryRunEquivalent: dryRunEquivalent,
            unresolvedConflictCount: unresolvedConflictCount,
            domains: domains,
            generatedAt: generatedAt
        )
    }

    nonisolated static func evaluateShadow(
        mode: CanonicalKernelExecutionMode,
        token: CanonicalProductionExecutionToken?,
        domains: [CanonicalProductionDomain],
        rollbackPlan: CanonicalRollbackPlan?,
        dryRunEquivalence: CanonicalDryRunEquivalenceReport?,
        unresolvedConflictCount: Int,
        generatedAt: Date = Date()
    ) -> CanonicalProductionExecutionAudit {
        let requestedMode = token?.mode ?? mode
        let nodeRole = token?.nodeRole
        var reasons: [CanonicalProductionExecutionRejectionReason] = []
        if mode == .productionExecute || requestedMode == .productionExecute {
            reasons.append(.blockedProductionExecute)
        }
        if !mode.isShadowPreparationMode || requestedMode != mode {
            reasons.append(.modeDisabled)
        }
        let roleAllowed = nodeRole == .iPhone || nodeRole == .mac || nodeRole == .testHarness
        if !roleAllowed {
            reasons.append(.productionMigrationBlocked)
        }
        let dryRunEquivalent = dryRunEquivalence?.legacyEquivalence.allEquivalent == true
            && dryRunEquivalence?.legacyEquivalence.hasBlockingDivergence != true
        return CanonicalProductionExecutionAudit(
            allowed: reasons.isEmpty,
            mode: mode,
            nodeRole: nodeRole,
            requestedMode: requestedMode,
            allowedMode: reasons.isEmpty ? mode : nil,
            tokenSyncRunID: token?.syncRunID,
            rejectionReasons: reasons,
            deniedSideEffects: CanonicalProductionSideEffectKind.allCases,
            rollbackAvailable: rollbackPlan != nil,
            dryRunEquivalent: dryRunEquivalent,
            unresolvedConflictCount: unresolvedConflictCount,
            domains: domains,
            generatedAt: generatedAt
        )
    }

    nonisolated private static func portMissingOrDryRun(_ port: CanonicalProductionPortKind, ports: CanonicalProductionPortSet) -> Bool {
        switch port {
        case .file:
            return ports.file == nil || ports.file?.isDryRunOnly == true
        case .transport:
            return ports.transport == nil || ports.transport?.isDryRunOnly == true
        case .upload:
            return ports.upload == nil || ports.upload?.isDryRunOnly == true
        case .apply:
            return ports.apply == nil || ports.apply?.isDryRunOnly == true
        case .syncClock:
            return ports.syncClock == nil
        case .diagnostics:
            return ports.diagnostics == nil
        case .capability:
            return ports.capability == nil
        }
    }
}
