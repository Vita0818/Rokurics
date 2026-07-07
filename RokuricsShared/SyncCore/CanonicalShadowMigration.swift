//
//  CanonicalShadowMigration.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalShadowMigrationMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case diagnosticsOnly
    case dryRunCompare
    case shadowReadOnly
    case shadowReadOnlyWithNetworkProbe
    case executionShadowDryRun
    case executionShadowWithShadowFileStore
    case executionShadowWithReadOnlyTransportProbe
    case blockedProductionExecute
    case blockedExecutionShadowWrite
    case blockedExecutionShadowUpload
    case blockedExecutionShadowApply

    nonisolated var runsDryRun: Bool {
        switch self {
        case .dryRunCompare, .shadowReadOnly, .shadowReadOnlyWithNetworkProbe,
             .executionShadowDryRun, .executionShadowWithShadowFileStore, .executionShadowWithReadOnlyTransportProbe:
            return true
        case .disabled, .diagnosticsOnly, .blockedProductionExecute,
             .blockedExecutionShadowWrite, .blockedExecutionShadowUpload, .blockedExecutionShadowApply:
            return false
        }
    }

    nonisolated var runsExecutionShadowPreparation: Bool {
        switch self {
        case .executionShadowDryRun, .executionShadowWithShadowFileStore, .executionShadowWithReadOnlyTransportProbe:
            return true
        case .disabled, .diagnosticsOnly, .dryRunCompare, .shadowReadOnly, .shadowReadOnlyWithNetworkProbe,
             .blockedProductionExecute, .blockedExecutionShadowWrite, .blockedExecutionShadowUpload, .blockedExecutionShadowApply:
            return false
        }
    }

    nonisolated var noSideEffectReason: String {
        switch self {
        case .disabled:
            return "shadowMigrationDisabled"
        case .diagnosticsOnly:
            return "diagnosticsOnlyNoDryRun"
        case .dryRunCompare:
            return "dryRunCompareSuppressed"
        case .shadowReadOnly:
            return "shadowReadOnlySuppressed"
        case .shadowReadOnlyWithNetworkProbe:
            return "readOnlyNetworkProbeOnly"
        case .executionShadowDryRun:
            return "executionShadowDryRunSuppressed"
        case .executionShadowWithShadowFileStore:
            return "executionShadowShadowRootOnly"
        case .executionShadowWithReadOnlyTransportProbe:
            return "executionShadowReadOnlyTransportProbeOnly"
        case .blockedProductionExecute:
            return "productionExecuteBlocked"
        case .blockedExecutionShadowWrite:
            return "executionShadowWriteBlocked"
        case .blockedExecutionShadowUpload:
            return "executionShadowUploadBlocked"
        case .blockedExecutionShadowApply:
            return "executionShadowApplyBlocked"
        }
    }
}

nonisolated enum CanonicalShadowMigrationTrigger: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case iPhoneSyncTick
    case macInventory
    case macReceiver
    case manual
    case periodic
    case appActivation
    case retryDrainer
    case viewRefresh
    case testHarness
}

nonisolated enum CanonicalShadowSuppressedSideEffectKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case noWrite
    case noUpload
    case noApply
    case noRouteMutation
    case noRuntimeSwitch
    case noProductionExecute
}

nonisolated struct CanonicalShadowMigrationPolicy: Codable, Equatable, Sendable {
    var failureIsFatal: Bool
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int
    var suppressedSideEffects: [CanonicalShadowSuppressedSideEffectKind]
    var networkProbePolicy: CanonicalShadowNetworkProbePolicy
    var realDataShadowCopyPolicy: CanonicalRealDataShadowCopyPolicy
    var readOnlyTransportProbePolicy: CanonicalReadOnlyTransportProbePolicy

    nonisolated init(
        failureIsFatal: Bool = false,
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 200,
        suppressedSideEffects: [CanonicalShadowSuppressedSideEffectKind] = CanonicalShadowSuppressedSideEffectKind.allCases,
        networkProbePolicy: CanonicalShadowNetworkProbePolicy = CanonicalShadowNetworkProbePolicy(),
        realDataShadowCopyPolicy: CanonicalRealDataShadowCopyPolicy = .disabled,
        readOnlyTransportProbePolicy: CanonicalReadOnlyTransportProbePolicy = .disabled
    ) {
        self.failureIsFatal = failureIsFatal
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
        self.suppressedSideEffects = Array(Set(suppressedSideEffects)).sorted { $0.rawValue < $1.rawValue }
        self.networkProbePolicy = networkProbePolicy
        self.realDataShadowCopyPolicy = realDataShadowCopyPolicy
        self.readOnlyTransportProbePolicy = readOnlyTransportProbePolicy
    }
}

nonisolated struct CanonicalShadowMigrationConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: CanonicalShadowMigrationMode
    var policy: CanonicalShadowMigrationPolicy

    nonisolated init(
        isEnabled: Bool = false,
        mode: CanonicalShadowMigrationMode = .disabled,
        policy: CanonicalShadowMigrationPolicy = CanonicalShadowMigrationPolicy()
    ) {
        self.isEnabled = isEnabled
        self.mode = isEnabled ? mode : .disabled
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalShadowMigrationConfiguration()

    nonisolated static func enabled(
        mode: CanonicalShadowMigrationMode,
        policy: CanonicalShadowMigrationPolicy = CanonicalShadowMigrationPolicy()
    ) -> CanonicalShadowMigrationConfiguration {
        CanonicalShadowMigrationConfiguration(isEnabled: true, mode: mode, policy: policy)
    }

    nonisolated var effectiveMode: CanonicalShadowMigrationMode {
        isEnabled ? mode : .disabled
    }
}

nonisolated enum CanonicalShadowMigrationFailure: String, Codable, Equatable, Hashable, Sendable {
    case disabled
    case blockedProductionExecute
    case blockedExecutionShadowWrite
    case blockedExecutionShadowUpload
    case blockedExecutionShadowApply
    case roleNotAllowed
    case insufficientLocalSnapshot
    case insufficientPeerSnapshot
    case dryRunFailed
    case diagnosticsOnly
    case networkProbeRejected
    case realDataShadowCopyUnavailable
    case realDataShadowCopyFailed
    case readOnlyTransportProbeRejected
    case shadowRootCleanupFailed
    case unexpected
}

nonisolated struct CanonicalShadowMigrationGate: Codable, Equatable, Sendable {
    var allowed: Bool
    var mode: CanonicalShadowMigrationMode
    var trigger: CanonicalShadowMigrationTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var failure: CanonicalShadowMigrationFailure?
    var reason: String
    var suppressedSideEffects: [CanonicalShadowSuppressedSideEffectKind]

    nonisolated static func evaluate(
        configuration: CanonicalShadowMigrationConfiguration,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        requestedProductionExecute: Bool = false
    ) -> CanonicalShadowMigrationGate {
        let mode = configuration.effectiveMode
        let suppressed = configuration.policy.suppressedSideEffects
        guard mode != .disabled else {
            return CanonicalShadowMigrationGate(
                allowed: false,
                mode: mode,
                trigger: trigger,
                nodeRole: nodeRole,
                failure: .disabled,
                reason: "shadowMigrationDisabled",
                suppressedSideEffects: suppressed
            )
        }
        guard !requestedProductionExecute, mode != .blockedProductionExecute else {
            return CanonicalShadowMigrationGate(
                allowed: false,
                mode: mode,
                trigger: trigger,
                nodeRole: nodeRole,
                failure: .blockedProductionExecute,
                reason: "productionExecuteBlockedInShadowStage",
                suppressedSideEffects: suppressed
            )
        }
        switch mode {
        case .blockedExecutionShadowWrite:
            return CanonicalShadowMigrationGate(
                allowed: false,
                mode: mode,
                trigger: trigger,
                nodeRole: nodeRole,
                failure: .blockedExecutionShadowWrite,
                reason: mode.noSideEffectReason,
                suppressedSideEffects: suppressed
            )
        case .blockedExecutionShadowUpload:
            return CanonicalShadowMigrationGate(
                allowed: false,
                mode: mode,
                trigger: trigger,
                nodeRole: nodeRole,
                failure: .blockedExecutionShadowUpload,
                reason: mode.noSideEffectReason,
                suppressedSideEffects: suppressed
            )
        case .blockedExecutionShadowApply:
            return CanonicalShadowMigrationGate(
                allowed: false,
                mode: mode,
                trigger: trigger,
                nodeRole: nodeRole,
                failure: .blockedExecutionShadowApply,
                reason: mode.noSideEffectReason,
                suppressedSideEffects: suppressed
            )
        case .disabled, .diagnosticsOnly, .dryRunCompare, .shadowReadOnly, .shadowReadOnlyWithNetworkProbe,
             .executionShadowDryRun, .executionShadowWithShadowFileStore, .executionShadowWithReadOnlyTransportProbe,
             .blockedProductionExecute:
            break
        }
        switch nodeRole {
        case .iPhone, .mac, .testHarness:
            return CanonicalShadowMigrationGate(
                allowed: true,
                mode: mode,
                trigger: trigger,
                nodeRole: nodeRole,
                failure: nil,
                reason: mode.noSideEffectReason,
                suppressedSideEffects: suppressed
            )
        }
    }
}

nonisolated enum CanonicalShadowMigrationEventKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalShadowMigrationStarted
    case canonicalShadowMigrationCompleted
    case canonicalShadowMigrationBlocked
    case canonicalShadowMigrationDivergenceDetected
    case canonicalShadowMigrationEquivalent
    case canonicalShadowMigrationSuppressedSideEffects
}

nonisolated struct CanonicalShadowMigrationEvent: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, syncRunID ?? "", trigger.rawValue, nodeRole.rawValue, mode.rawValue, domain.rawValue, reason ?? ""].joined(separator: "|") }

    var kind: CanonicalShadowMigrationEventKind
    var syncRunID: String?
    var trigger: CanonicalShadowMigrationTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var mode: CanonicalShadowMigrationMode
    var domain: CanonicalProductionDomain
    var equivalenceStatus: String?
    var migrationGateStatus: String?
    var blockerCount: Int
    var divergenceCount: Int
    var suppressedSideEffectCount: Int
    var reason: String?
    var generatedAt: CanonicalTimestamp

    nonisolated init(
        kind: CanonicalShadowMigrationEventKind,
        syncRunID: String?,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        mode: CanonicalShadowMigrationMode,
        domain: CanonicalProductionDomain,
        equivalenceStatus: String? = nil,
        migrationGateStatus: String? = nil,
        blockerCount: Int = 0,
        divergenceCount: Int = 0,
        suppressedSideEffectCount: Int = 0,
        reason: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.kind = kind
        self.syncRunID = CanonicalShadowMigrationRedaction.safeIdentifier(syncRunID)
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.mode = mode
        self.domain = domain
        self.equivalenceStatus = CanonicalShadowMigrationRedaction.safeText(equivalenceStatus)
        self.migrationGateStatus = CanonicalShadowMigrationRedaction.safeText(migrationGateStatus)
        self.blockerCount = max(0, blockerCount)
        self.divergenceCount = max(0, divergenceCount)
        self.suppressedSideEffectCount = max(0, suppressedSideEffectCount)
        self.reason = CanonicalShadowMigrationRedaction.safeText(reason)
        self.generatedAt = CanonicalTimestamp(generatedAt)
    }

    nonisolated var diagnosticsSummary: String {
        [
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            "mode=\(mode.rawValue)",
            "domain=\(domain.rawValue)",
            "equivalence=\(equivalenceStatus ?? "unknown")",
            "gate=\(migrationGateStatus ?? "unknown")",
            "blockers=\(blockerCount)",
            "divergences=\(divergenceCount)",
            "suppressed=\(suppressedSideEffectCount)",
            "reason=\(reason ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalShadowMigrationDivergenceSummary: Codable, Equatable, Sendable {
    var divergenceCount: Int
    var blockingDivergenceCount: Int
    var divergentDomains: [CanonicalProductionDomain]

    nonisolated init(plan: CanonicalDryRunMigrationPlan?) {
        let divergences = plan?.equivalenceReport.legacyEquivalence.divergences ?? []
        self.divergenceCount = divergences.count
        self.blockingDivergenceCount = divergences.filter(\.isBlocking).count
        self.divergentDomains = Array(Set(divergences.map { $0.domain.productionDomain })).sorted { $0.rawValue < $1.rawValue }
    }
}

nonisolated struct CanonicalShadowMigrationSuppressedSideEffectSummary: Codable, Equatable, Sendable {
    var noWrite: Bool
    var noUpload: Bool
    var noApply: Bool
    var noRouteMutation: Bool
    var noRuntimeSwitch: Bool
    var noProductionExecute: Bool
    var suppressedCount: Int

    nonisolated init(_ effects: [CanonicalShadowSuppressedSideEffectKind] = CanonicalShadowSuppressedSideEffectKind.allCases) {
        let set = Set(effects)
        self.noWrite = set.contains(.noWrite)
        self.noUpload = set.contains(.noUpload)
        self.noApply = set.contains(.noApply)
        self.noRouteMutation = set.contains(.noRouteMutation)
        self.noRuntimeSwitch = set.contains(.noRuntimeSwitch)
        self.noProductionExecute = set.contains(.noProductionExecute)
        self.suppressedCount = set.count
    }
}

nonisolated struct CanonicalShadowMigrationReport: Codable, Equatable, Identifiable, Sendable {
    var id: String { runID }

    var runID: String
    var syncRunID: String?
    var trigger: CanonicalShadowMigrationTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var mode: CanonicalShadowMigrationMode
    var domain: CanonicalProductionDomain
    var generatedAt: CanonicalTimestamp
    var equivalenceStatus: String
    var migrationGateStatus: String
    var blockerCount: Int
    var divergenceSummary: CanonicalShadowMigrationDivergenceSummary
    var suppressedSideEffects: CanonicalShadowMigrationSuppressedSideEffectSummary
    var events: [CanonicalShadowMigrationEvent]
    var failure: CanonicalShadowMigrationFailure?
    var failureReason: String?

    nonisolated init(
        runID: String,
        syncRunID: String?,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        mode: CanonicalShadowMigrationMode,
        domain: CanonicalProductionDomain,
        plan: CanonicalDryRunMigrationPlan?,
        gate: CanonicalShadowMigrationGate,
        events: [CanonicalShadowMigrationEvent],
        failure: CanonicalShadowMigrationFailure? = nil,
        failureReason: String? = nil,
        generatedAt: Date = Date()
    ) {
        self.runID = CanonicalShadowMigrationRedaction.safeIdentifier(runID) ?? "shadow-migration-run"
        self.syncRunID = CanonicalShadowMigrationRedaction.safeIdentifier(syncRunID)
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.mode = mode
        self.domain = domain
        self.generatedAt = CanonicalTimestamp(generatedAt)
        let equivalence = plan?.equivalenceReport.legacyEquivalence
        self.equivalenceStatus = equivalence == nil
            ? "notEvaluated"
            : (equivalence?.hasBlockingDivergence == true ? "divergent" : "equivalent")
        self.migrationGateStatus = plan?.readinessReport.productionMigrationBlocked == true ? "blocked" : (plan == nil ? "notEvaluated" : "manualDesignOnly")
        self.blockerCount = plan?.blockers.count ?? (failure == nil ? 0 : 1)
        self.divergenceSummary = CanonicalShadowMigrationDivergenceSummary(plan: plan)
        self.suppressedSideEffects = CanonicalShadowMigrationSuppressedSideEffectSummary(gate.suppressedSideEffects)
        self.events = Array(events.prefix(200))
        self.failure = failure
        self.failureReason = CanonicalShadowMigrationRedaction.safeText(failureReason)
    }
}

nonisolated struct CanonicalShadowMigrationDiagnostics: Codable, Equatable, Sendable {
    var events: [CanonicalShadowMigrationEvent]
    var report: CanonicalShadowMigrationReport?

    nonisolated init(events: [CanonicalShadowMigrationEvent] = [], report: CanonicalShadowMigrationReport? = nil) {
        self.events = events
        self.report = report
    }
}

nonisolated struct CanonicalShadowMigrationResult: Sendable {
    var configuration: CanonicalShadowMigrationConfiguration
    var gate: CanonicalShadowMigrationGate
    var dryRunPlan: CanonicalDryRunMigrationPlan?
    var report: CanonicalShadowMigrationReport
    var failure: CanonicalShadowMigrationFailure?
    var isFatal: Bool

    nonisolated var succeeded: Bool {
        failure == nil
    }
}

nonisolated struct CanonicalShadowMigrationRunner {
    nonisolated init() {}

    nonisolated func run(
        configuration: CanonicalShadowMigrationConfiguration,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalProductionDomain,
        localSnapshot: CanonicalProductionSnapshot?,
        peerSnapshot: CanonicalProductionSnapshot?,
        ports: CanonicalProductionPortSet,
        currentRuntimeReadiness: CanonicalRuntimeReadinessReport = Self.defaultRuntimeReadiness(),
        context: CanonicalDryRunMigrationContext = CanonicalDryRunMigrationContext(),
        syncRunID: String? = nil,
        generatedAt: Date = Date()
    ) -> CanonicalShadowMigrationResult {
        let gate = CanonicalShadowMigrationGate.evaluate(
            configuration: configuration,
            trigger: trigger,
            nodeRole: nodeRole
        )
        var events: [CanonicalShadowMigrationEvent] = []
        events.append(event(.canonicalShadowMigrationStarted, configuration: configuration, gate: gate, domain: domain, syncRunID: syncRunID, reason: gate.reason, generatedAt: generatedAt))
        events.append(event(.canonicalShadowMigrationSuppressedSideEffects, configuration: configuration, gate: gate, domain: domain, syncRunID: syncRunID, reason: configuration.effectiveMode.noSideEffectReason, generatedAt: generatedAt))

        guard gate.allowed else {
            events.append(event(.canonicalShadowMigrationBlocked, configuration: configuration, gate: gate, domain: domain, syncRunID: syncRunID, reason: gate.reason, generatedAt: generatedAt))
            return makeResult(
                configuration: configuration,
                gate: gate,
                plan: nil,
                events: events,
                failure: gate.failure,
                failureReason: gate.reason,
                domain: domain,
                generatedAt: generatedAt
            )
        }

        guard configuration.effectiveMode.runsDryRun else {
            events.append(event(.canonicalShadowMigrationCompleted, configuration: configuration, gate: gate, domain: domain, syncRunID: syncRunID, reason: "diagnosticsOnly", generatedAt: generatedAt))
            return makeResult(
                configuration: configuration,
                gate: gate,
                plan: nil,
                events: events,
                failure: nil,
                failureReason: nil,
                domain: domain,
                generatedAt: generatedAt
            )
        }

        guard let localSnapshot else {
            events.append(event(.canonicalShadowMigrationBlocked, configuration: configuration, gate: gate, domain: domain, syncRunID: syncRunID, reason: "insufficientLocalSnapshot", generatedAt: generatedAt))
            return makeResult(
                configuration: configuration,
                gate: gate,
                plan: nil,
                events: events,
                failure: .insufficientLocalSnapshot,
                failureReason: "insufficientLocalSnapshot",
                domain: domain,
                generatedAt: generatedAt
            )
        }
        guard let peerSnapshot else {
            events.append(event(.canonicalShadowMigrationBlocked, configuration: configuration, gate: gate, domain: domain, syncRunID: syncRunID, reason: "insufficientPeerSnapshot", generatedAt: generatedAt))
            return makeResult(
                configuration: configuration,
                gate: gate,
                plan: nil,
                events: events,
                failure: .insufficientPeerSnapshot,
                failureReason: "insufficientPeerSnapshot",
                domain: domain,
                generatedAt: generatedAt
            )
        }

        do {
            let plan = try CanonicalDryRunMigrationPlanner().plan(
                local: localSnapshot,
                peer: peerSnapshot,
                ports: ports,
                currentRuntimeReadiness: currentRuntimeReadiness,
                trigger: .periodic,
                context: context,
                generatedAt: generatedAt
            )
            if plan.equivalenceReport.legacyEquivalence.hasBlockingDivergence {
                events.append(event(.canonicalShadowMigrationDivergenceDetected, configuration: configuration, gate: gate, domain: domain, plan: plan, syncRunID: syncRunID, reason: "blockingDivergence", generatedAt: generatedAt))
            } else {
                events.append(event(.canonicalShadowMigrationEquivalent, configuration: configuration, gate: gate, domain: domain, plan: plan, syncRunID: syncRunID, reason: "equivalent", generatedAt: generatedAt))
            }
            if plan.readinessReport.productionMigrationBlocked {
                events.append(event(.canonicalShadowMigrationBlocked, configuration: configuration, gate: gate, domain: domain, plan: plan, syncRunID: syncRunID, reason: "migrationGateBlocked", generatedAt: generatedAt))
            }
            events.append(event(.canonicalShadowMigrationCompleted, configuration: configuration, gate: gate, domain: domain, plan: plan, syncRunID: syncRunID, reason: "dryRunCompareCompleted", generatedAt: generatedAt))
            return makeResult(
                configuration: configuration,
                gate: gate,
                plan: plan,
                events: events,
                failure: nil,
                failureReason: nil,
                domain: domain,
                generatedAt: generatedAt
            )
        } catch {
            events.append(event(.canonicalShadowMigrationBlocked, configuration: configuration, gate: gate, domain: domain, syncRunID: syncRunID, reason: "dryRunFailed", generatedAt: generatedAt))
            return makeResult(
                configuration: configuration,
                gate: gate,
                plan: nil,
                events: events,
                failure: .dryRunFailed,
                failureReason: String(describing: error),
                domain: domain,
                generatedAt: generatedAt
            )
        }
    }

    nonisolated static func defaultRuntimeReadiness(generatedAt: Date = Date()) -> CanonicalRuntimeReadinessReport {
        CanonicalRuntimeReadinessEvaluator().evaluate(
            evidence: CanonicalRuntimeReadinessEvidence(
                fileRootBinding: true,
                fileHashVerification: true,
                transportRouteValidation: true,
                uploadResumableState: true,
                applyExecutor: true,
                conflictResolver: true,
                twoNodeHarness: true,
                productionStillLegacyOwned: true
            ),
            generatedAt: generatedAt
        )
    }

    private nonisolated func makeResult(
        configuration: CanonicalShadowMigrationConfiguration,
        gate: CanonicalShadowMigrationGate,
        plan: CanonicalDryRunMigrationPlan?,
        events: [CanonicalShadowMigrationEvent],
        failure: CanonicalShadowMigrationFailure?,
        failureReason: String?,
        domain: CanonicalProductionDomain,
        generatedAt: Date
    ) -> CanonicalShadowMigrationResult {
        let boundedEvents = Array(events.prefix(configuration.policy.maxDiagnosticsEvents))
        let report = CanonicalShadowMigrationReport(
            runID: plan?.dryRunID ?? gate.reason,
            syncRunID: boundedEvents.first?.syncRunID,
            trigger: gate.trigger,
            nodeRole: gate.nodeRole,
            mode: gate.mode,
            domain: domain,
            plan: plan,
            gate: gate,
            events: boundedEvents,
            failure: failure,
            failureReason: failureReason,
            generatedAt: generatedAt
        )
        return CanonicalShadowMigrationResult(
            configuration: configuration,
            gate: gate,
            dryRunPlan: plan,
            report: report,
            failure: failure,
            isFatal: failure != nil && configuration.policy.failureIsFatal
        )
    }

    private nonisolated func event(
        _ kind: CanonicalShadowMigrationEventKind,
        configuration: CanonicalShadowMigrationConfiguration,
        gate: CanonicalShadowMigrationGate,
        domain: CanonicalProductionDomain,
        plan: CanonicalDryRunMigrationPlan? = nil,
        syncRunID: String? = nil,
        reason: String?,
        generatedAt: Date
    ) -> CanonicalShadowMigrationEvent {
        CanonicalShadowMigrationEvent(
            kind: kind,
            syncRunID: syncRunID,
            trigger: gate.trigger,
            nodeRole: gate.nodeRole,
            mode: configuration.effectiveMode,
            domain: domain,
            equivalenceStatus: plan == nil ? "notEvaluated" : (plan?.equivalenceReport.legacyEquivalence.hasBlockingDivergence == true ? "divergent" : "equivalent"),
            migrationGateStatus: plan == nil ? "notEvaluated" : (plan?.readinessReport.productionMigrationBlocked == true ? "blocked" : "manualDesignOnly"),
            blockerCount: plan?.blockers.count ?? 0,
            divergenceCount: plan?.equivalenceReport.legacyEquivalence.divergences.count ?? 0,
            suppressedSideEffectCount: gate.suppressedSideEffects.count,
            reason: reason,
            generatedAt: generatedAt
        )
    }
}

nonisolated enum CanonicalShadowNetworkProbeKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case health
    case fingerprint
    case syncStatusReadOnly
    case syncInventoryReadOnly
    case artifactRequestReadOnly
    case deviceStatusReadOnly
    case uploadMetadata
    case uploadAudio
    case uploadSessionStart
    case uploadSessionChunk
    case uploadSessionFinalize
    case applyMetadata
    case applyManifest
    case mutatingRoute
}

nonisolated struct CanonicalShadowNetworkProbeRequest: Codable, Equatable, Sendable {
    var kind: CanonicalShadowNetworkProbeKind
    var routePath: String
    var bodyByteCount: Int
    var artifactByteLimit: Int?

    nonisolated init(
        kind: CanonicalShadowNetworkProbeKind,
        routePath: String,
        bodyByteCount: Int = 0,
        artifactByteLimit: Int? = nil
    ) {
        self.kind = kind
        self.routePath = CanonicalShadowMigrationRedaction.safeText(routePath) ?? kind.rawValue
        self.bodyByteCount = max(0, bodyByteCount)
        self.artifactByteLimit = artifactByteLimit.map { max(0, $0) }
    }
}

nonisolated struct CanonicalShadowNetworkProbeDecision: Codable, Equatable, Sendable {
    var accepted: Bool
    var reason: String
    var noMutation: Bool
}

nonisolated struct CanonicalShadowNetworkProbePolicy: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var artifactRequestMaxBytes: Int
    var allowedKinds: [CanonicalShadowNetworkProbeKind]

    nonisolated init(
        isEnabled: Bool = false,
        artifactRequestMaxBytes: Int = 256 * 1024,
        allowedKinds: [CanonicalShadowNetworkProbeKind] = [.health, .fingerprint, .syncStatusReadOnly, .syncInventoryReadOnly, .artifactRequestReadOnly, .deviceStatusReadOnly]
    ) {
        self.isEnabled = isEnabled
        self.artifactRequestMaxBytes = max(0, artifactRequestMaxBytes)
        self.allowedKinds = Array(Set(allowedKinds)).sorted { $0.rawValue < $1.rawValue }
    }

    nonisolated func decision(for request: CanonicalShadowNetworkProbeRequest) -> CanonicalShadowNetworkProbeDecision {
        guard isEnabled else {
            return CanonicalShadowNetworkProbeDecision(accepted: false, reason: "networkProbeDisabled", noMutation: true)
        }
        guard allowedKinds.contains(request.kind), request.kind.isReadOnlyProbe else {
            return CanonicalShadowNetworkProbeDecision(accepted: false, reason: "mutatingRouteRejected", noMutation: true)
        }
        if request.kind == .artifactRequestReadOnly {
            let limit = request.artifactByteLimit ?? artifactRequestMaxBytes
            guard request.bodyByteCount <= limit else {
                return CanonicalShadowNetworkProbeDecision(accepted: false, reason: "artifactRequestSizeBoundExceeded", noMutation: true)
            }
        }
        return CanonicalShadowNetworkProbeDecision(accepted: true, reason: "readOnlyProbeAccepted", noMutation: true)
    }
}

extension CanonicalShadowNetworkProbeKind {
    nonisolated var isReadOnlyProbe: Bool {
        switch self {
        case .health, .fingerprint, .syncStatusReadOnly, .syncInventoryReadOnly, .artifactRequestReadOnly, .deviceStatusReadOnly:
            return true
        case .uploadMetadata, .uploadAudio, .uploadSessionStart, .uploadSessionChunk, .uploadSessionFinalize, .applyMetadata, .applyManifest, .mutatingRoute:
            return false
        }
    }
}

nonisolated struct CanonicalShadowPortFactoryOutput: Sendable {
    var portSet: CanonicalProductionPortSet
    var localSnapshot: CanonicalProductionSnapshot?
    var peerSnapshot: CanonicalProductionSnapshot?
    var capabilities: CanonicalProductionCapabilitySummary
    var missingPortReport: CanonicalProductionPortReadiness
    var suppressedSideEffects: CanonicalShadowMigrationSuppressedSideEffectSummary
    var diagnosticsSafeSummary: String
    var networkProbePolicy: CanonicalShadowNetworkProbePolicy
    var shadowRootLifecycle: CanonicalShadowRootLifecycle?
    var realDataShadowCopyResult: CanonicalRealDataShadowCopyResult?
    var readOnlyTransportProbeResult: CanonicalReadOnlyTransportProbeResult?
}

nonisolated enum CanonicalShadowMigrationRedaction {
    nonisolated static func safeIdentifier(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        return safeText(value)
    }

    nonisolated static func safeText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard !trimmed.isEmpty else {
            return nil
        }
        let lowercased = trimmed.lowercased()
        if CanonicalProductionRedaction.containsSensitivePathSignal(trimmed)
            || lowercased.contains("secret")
            || lowercased.contains("api-key")
            || lowercased.contains("token")
            || lowercased.contains("transcript")
            || lowercased.contains("provider response")
            || lowercased.contains("full note")
            || lowercased.contains("summary content") {
            return "redacted-\(CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(trimmed).value) ?? "shadow")"
        }
        return String(trimmed.prefix(160))
    }
}

nonisolated struct CanonicalShadowMigrationReportJSONLWriter {
    var fileManager: FileManager
    var maxReports: Int

    nonisolated init(fileManager: FileManager = .default, maxReports: Int = 200) {
        self.fileManager = fileManager
        self.maxReports = max(1, maxReports)
    }

    nonisolated func append(_ report: CanonicalShadowMigrationReport, to logURL: URL) throws {
        try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let line = try String(data: encoder.encode(report), encoding: .utf8) ?? "{}"
        let existingLines: [String]
        if fileManager.fileExists(atPath: logURL.path),
           let raw = try? String(contentsOf: logURL, encoding: .utf8) {
            existingLines = raw.split(separator: "\n").map(String.init)
        } else {
            existingLines = []
        }
        let nextLines = Array((existingLines + [line]).suffix(maxReports))
        try Data((nextLines.joined(separator: "\n") + "\n").utf8).write(to: logURL, options: .atomic)
    }
}
