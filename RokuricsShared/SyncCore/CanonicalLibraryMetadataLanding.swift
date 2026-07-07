//
//  CanonicalLibraryMetadataLanding.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/6.
//

import Foundation

nonisolated enum CanonicalMigrationLandingFreezeViolation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case noLibraryMetadataActivePilot
    case multipleActivePilots
    case nonLibraryMetadataActivePilot
    case nonLibraryMetadataDomainNotStaticOnly
    case generatedArtifactsNotStaticOnly
    case tombstoneConflictNotStaticOnly
    case audioUploadNotStaticOnly
    case recordingMetadataActive
    case defaultCutoverEnabled
    case releaseDefaultEnabled
    case runtimeSwitchEnabled
    case legacyDuplicateSuppressionEnabled
    case readPathNotLegacy
    case productionInjectionPresent
    case productionExecutorInjectedByDefault
    case productionRootWriteEnabledByDefault
    case legacyFallbackUnavailable
    case canaryBudgetAboveOneDenied
    case allEligibleEnabled
    case unsafeCandidateAllowed
    case resourceMoveAllowed
    case contentWriteAllowed
    case tombstoneDeleteAllowed
}

nonisolated struct CanonicalMigrationLandingFreezeResult: Codable, Equatable, Sendable {
    var allowed: Bool
    var activePilotDomain: CanonicalMigrationDomain?
    var violations: [CanonicalMigrationLandingFreezeViolation]
    var otherDomainsStaticOnly: Bool
    var runtimeSwitchEnabled: Bool
    var diagnosticsSummary: String
    var redacted: Bool
}

nonisolated struct CanonicalMigrationLandingFreeze: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        matrix: CanonicalMigrationDomainMatrix,
        releaseDefaultEnabled: Bool = false,
        runtimeSwitchEnabled: Bool = false,
        productionInjectionPresent: Bool = false,
        productionExecutorInjectedByDefault: Bool = false,
        productionRootWriteEnabledByDefault: Bool = false,
        legacyFallbackAvailable: Bool = true,
        canaryMaxObjectsPerSyncRun: Int = 1,
        allEligibleEnabled: Bool = false,
        unsafeCandidateAllowed: Bool = false,
        resourceMoveAllowed: Bool = false,
        contentWriteAllowed: Bool = false,
        tombstoneDeleteAllowed: Bool = false
    ) -> CanonicalMigrationLandingFreezeResult {
        var violations: [CanonicalMigrationLandingFreezeViolation] = []
        let activePolicies = matrix.policies.filter(\.activePilot)
        let activePilotDomain = activePolicies.count == 1 ? activePolicies.first?.domain : nil

        if activePolicies.isEmpty {
            violations.append(.noLibraryMetadataActivePilot)
        }
        if activePolicies.count > 1 {
            violations.append(.multipleActivePilots)
        }
        if activePolicies.contains(where: { $0.domain != .libraryMetadata }) {
            violations.append(.nonLibraryMetadataActivePilot)
        }

        let nonLibraryPolicies = matrix.policies.filter { $0.domain != .libraryMetadata }
        if nonLibraryPolicies.contains(where: { !$0.staticOnly || !$0.blockedForRealMigration }) {
            violations.append(.nonLibraryMetadataDomainNotStaticOnly)
        }
        if matrix.policy(for: .generatedArtifacts).map({ !$0.staticOnly || $0.activePilot }) == true {
            violations.append(.generatedArtifactsNotStaticOnly)
        }
        if matrix.policy(for: .tombstoneConflict).map({ !$0.staticOnly || $0.activePilot }) == true {
            violations.append(.tombstoneConflictNotStaticOnly)
        }
        if matrix.policy(for: .audioUpload).map({ !$0.staticOnly || $0.activePilot }) == true {
            violations.append(.audioUploadNotStaticOnly)
        }
        if matrix.policy(for: .recordingMetadata).map({ $0.activePilot || !$0.staticOnly }) == true {
            violations.append(.recordingMetadataActive)
        }
        if matrix.policies.contains(where: \.defaultCutoverEnabled) {
            violations.append(.defaultCutoverEnabled)
        }
        if matrix.policies.contains(where: \.releaseDefaultEnabledCutover) || releaseDefaultEnabled {
            violations.append(.releaseDefaultEnabled)
        }
        if matrix.policies.contains(where: \.runtimeSwitchEnabled) || runtimeSwitchEnabled {
            violations.append(.runtimeSwitchEnabled)
        }
        if matrix.policies.contains(where: \.legacySuppressionAllowed) {
            violations.append(.legacyDuplicateSuppressionEnabled)
        }
        if matrix.policies.contains(where: { !$0.readPathLegacy }) {
            violations.append(.readPathNotLegacy)
        }
        if matrix.policies.contains(where: { !$0.noProductionInjection && $0.domain != .libraryMetadata }) || productionInjectionPresent {
            violations.append(.productionInjectionPresent)
        }
        if productionExecutorInjectedByDefault || productionInjectionPresent {
            violations.append(.productionExecutorInjectedByDefault)
        }
        if productionRootWriteEnabledByDefault {
            violations.append(.productionRootWriteEnabledByDefault)
        }
        if !legacyFallbackAvailable {
            violations.append(.legacyFallbackUnavailable)
        }
        if canaryMaxObjectsPerSyncRun > 1 {
            violations.append(.canaryBudgetAboveOneDenied)
        }
        if allEligibleEnabled {
            violations.append(.allEligibleEnabled)
        }
        if unsafeCandidateAllowed {
            violations.append(.unsafeCandidateAllowed)
        }
        if resourceMoveAllowed {
            violations.append(.resourceMoveAllowed)
        }
        if contentWriteAllowed {
            violations.append(.contentWriteAllowed)
        }
        if tombstoneDeleteAllowed {
            violations.append(.tombstoneDeleteAllowed)
        }

        let uniqueViolations = Array(Set(violations)).sorted { $0.rawValue < $1.rawValue }
        let otherDomainsStaticOnly = nonLibraryPolicies.allSatisfy {
            $0.staticOnly
                && $0.blockedForRealMigration
                && !$0.activePilot
                && !$0.defaultCutoverEnabled
                && !$0.releaseDefaultEnabledCutover
                && !$0.runtimeSwitchEnabled
                && !$0.legacySuppressionAllowed
                && $0.readPathLegacy
        }
        let runtimeEnabled = matrix.policies.contains(where: \.runtimeSwitchEnabled) || runtimeSwitchEnabled
        return CanonicalMigrationLandingFreezeResult(
            allowed: uniqueViolations.isEmpty,
            activePilotDomain: activePilotDomain,
            violations: uniqueViolations,
            otherDomainsStaticOnly: otherDomainsStaticOnly,
            runtimeSwitchEnabled: runtimeEnabled,
            diagnosticsSummary: [
                "activePilot=\(activePilotDomain?.rawValue ?? "none")",
                "otherDomainsStaticOnly=\(otherDomainsStaticOnly)",
                "runtimeSwitch=\(runtimeEnabled)",
                "legacyFallbackAvailable=\(legacyFallbackAvailable)",
                "canaryMaxObjectsPerSyncRun=\(canaryMaxObjectsPerSyncRun)",
                "violations=\(uniqueViolations.map(\.rawValue).joined(separator: "|"))",
                "redacted=true"
            ].joined(separator: ","),
            redacted: true
        )
    }
}

nonisolated enum CanonicalLibraryMetadataDebugPilotMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case diagnosticsOnly
    case armN1Canary
    case executeN1Canary
    case blocked

    nonisolated var isConfigured: Bool {
        self != .disabled
    }

    nonisolated var requestsExecution: Bool {
        self == .executeN1Canary
    }
}

nonisolated struct CanonicalLibraryMetadataDebugPilotPolicy: Codable, Equatable, Sendable {
    var domain: CanonicalMigrationDomain
    var canaryMaxObjectsPerSyncRun: Int
    var requiresExplicitInternalDebugConfiguration: Bool
    var requiresProductionToken: Bool
    var requiresOwnerApproval: Bool
    var requiresRollbackPlan: Bool
    var requiresReadSideParallelEquivalent: Bool
    var requiresObservationEvidence: Bool
    var requiresRealRootBoundApplyPort: Bool
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
        requiresObservationEvidence: Bool = true,
        requiresRealRootBoundApplyPort: Bool = true,
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
        self.requiresObservationEvidence = requiresObservationEvidence
        self.requiresRealRootBoundApplyPort = requiresRealRootBoundApplyPort
        self.productionRootDisabledByDefault = productionRootDisabledByDefault
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.allowAllEligible = allowAllEligible
        self.releaseDefaultEnabled = releaseDefaultEnabled
    }

    nonisolated static let strictLibraryMetadataN1 = CanonicalLibraryMetadataDebugPilotPolicy()

    nonisolated var isStrictLibraryMetadataN1: Bool {
        domain == .libraryMetadata
            && canaryMaxObjectsPerSyncRun == 1
            && requiresExplicitInternalDebugConfiguration
            && requiresProductionToken
            && requiresOwnerApproval
            && requiresRollbackPlan
            && requiresReadSideParallelEquivalent
            && requiresObservationEvidence
            && requiresRealRootBoundApplyPort
            && productionRootDisabledByDefault
            && !runtimeSwitchEnabled
            && !allowAllEligible
            && !releaseDefaultEnabled
    }

    nonisolated var asProductionCanaryPolicy: CanonicalLibraryMetadataProductionCanaryPolicy {
        CanonicalLibraryMetadataProductionCanaryPolicy(
            domain: domain,
            canaryMaxObjectsPerSyncRun: canaryMaxObjectsPerSyncRun,
            requiresExplicitInternalDebugConfiguration: requiresExplicitInternalDebugConfiguration,
            requiresProductionToken: requiresProductionToken,
            requiresOwnerApproval: requiresOwnerApproval,
            requiresRollbackPlan: requiresRollbackPlan,
            requiresReadSideParallelEquivalent: requiresReadSideParallelEquivalent,
            productionRootDisabledByDefault: productionRootDisabledByDefault,
            runtimeSwitchEnabled: runtimeSwitchEnabled,
            allowAllEligible: allowAllEligible,
            releaseDefaultEnabled: releaseDefaultEnabled
        )
    }
}

nonisolated struct CanonicalLibraryMetadataDebugPilotConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalLibraryMetadataDebugPilotMode
    var rootMode: CanonicalLibraryMetadataProductionCanaryRootMode
    var policy: CanonicalLibraryMetadataDebugPilotPolicy
    var explicitInternalDebugConfiguration: Bool
    var allowProductionRootWrites: Bool
    var evidence: CanonicalLibraryMetadataCutoverEvidence
    var cutoverToken: CanonicalCutoverToken?
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int

    nonisolated init(
        mode: CanonicalLibraryMetadataDebugPilotMode = .disabled,
        rootMode: CanonicalLibraryMetadataProductionCanaryRootMode = .disabled,
        policy: CanonicalLibraryMetadataDebugPilotPolicy = .strictLibraryMetadataN1,
        explicitInternalDebugConfiguration: Bool = false,
        allowProductionRootWrites: Bool = false,
        evidence: CanonicalLibraryMetadataCutoverEvidence = CanonicalLibraryMetadataCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil,
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 200
    ) {
        self.mode = mode
        self.rootMode = rootMode
        self.policy = policy
        self.explicitInternalDebugConfiguration = explicitInternalDebugConfiguration
        self.allowProductionRootWrites = allowProductionRootWrites
        self.evidence = evidence
        self.cutoverToken = cutoverToken
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
    }

    nonisolated static let disabled = CanonicalLibraryMetadataDebugPilotConfiguration()

    nonisolated static func diagnosticsOnly(
        evidence: CanonicalLibraryMetadataCutoverEvidence = CanonicalLibraryMetadataCutoverEvidence()
    ) -> CanonicalLibraryMetadataDebugPilotConfiguration {
        CanonicalLibraryMetadataDebugPilotConfiguration(
            mode: .diagnosticsOnly,
            rootMode: .disabled,
            explicitInternalDebugConfiguration: true,
            evidence: evidence
        )
    }

    nonisolated static func armTestRootN1(
        token: CanonicalCutoverToken,
        evidence: CanonicalLibraryMetadataCutoverEvidence
    ) -> CanonicalLibraryMetadataDebugPilotConfiguration {
        CanonicalLibraryMetadataDebugPilotConfiguration(
            mode: .armN1Canary,
            rootMode: .testRoot,
            explicitInternalDebugConfiguration: true,
            evidence: evidence,
            cutoverToken: token
        )
    }

    nonisolated static func executeTestRootN1(
        token: CanonicalCutoverToken,
        evidence: CanonicalLibraryMetadataCutoverEvidence
    ) -> CanonicalLibraryMetadataDebugPilotConfiguration {
        CanonicalLibraryMetadataDebugPilotConfiguration(
            mode: .executeN1Canary,
            rootMode: .testRoot,
            explicitInternalDebugConfiguration: true,
            evidence: evidence,
            cutoverToken: token
        )
    }

    nonisolated static func executeProductionRootN1(
        token: CanonicalCutoverToken,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        allowProductionRootWrites: Bool
    ) -> CanonicalLibraryMetadataDebugPilotConfiguration {
        CanonicalLibraryMetadataDebugPilotConfiguration(
            mode: .executeN1Canary,
            rootMode: .productionRootExplicit,
            explicitInternalDebugConfiguration: true,
            allowProductionRootWrites: allowProductionRootWrites,
            evidence: evidence,
            cutoverToken: token
        )
    }

    nonisolated var asProductionCanaryConfiguration: CanonicalLibraryMetadataProductionCanaryConfiguration {
        let productionMode: CanonicalLibraryMetadataProductionCanaryMode
        switch mode {
        case .disabled:
            productionMode = .disabled
        case .diagnosticsOnly:
            productionMode = .diagnosticsOnly
        case .armN1Canary:
            productionMode = .canaryN1Armed
        case .executeN1Canary:
            productionMode = .canaryN1Execute
        case .blocked:
            productionMode = .blocked
        }
        return CanonicalLibraryMetadataProductionCanaryConfiguration(
            mode: productionMode,
            rootMode: rootMode,
            policy: policy.asProductionCanaryPolicy,
            explicitInternalDebugConfiguration: explicitInternalDebugConfiguration,
            allowProductionRootWrites: allowProductionRootWrites
        )
    }

    nonisolated var isStrictExecutableN1: Bool {
        mode == .executeN1Canary
            && (rootMode == .testRoot || rootMode == .productionRootExplicit)
            && explicitInternalDebugConfiguration
            && policy.isStrictLibraryMetadataN1
            && (rootMode == .testRoot ? !allowProductionRootWrites : allowProductionRootWrites)
    }
}

nonisolated enum CanonicalLibraryMetadataLandingStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
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

nonisolated enum CanonicalLibraryMetadataLandingRecommendation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case remainDisabled
    case fixBlockers
    case runAnotherN1
    case considerReadSideCutoverAfterAudit
}

nonisolated struct CanonicalLibraryMetadataLandingCandidateSummary: Codable, Equatable, Sendable {
    var selected: Bool
    var kind: CanonicalLibraryMetadataCanaryCandidateSafetyKind?
    var objectKind: CanonicalObjectKind?
    var domain: CanonicalLibraryMetadataCutoverDomain?
    var actionKind: CanonicalLibraryMetadataCutoverActionKind?
    var metadataOnly: Bool
    var resourceMoveAttempted: Bool
    var contentBytesMutated: Bool
}

nonisolated struct CanonicalLibraryMetadataLandingReport: Codable, Equatable, Sendable {
    var status: CanonicalLibraryMetadataLandingStatus
    var mode: CanonicalLibraryMetadataDebugPilotMode
    var rootMode: CanonicalLibraryMetadataProductionCanaryRootMode
    var activePilot: CanonicalMigrationDomain?
    var candidate: CanonicalLibraryMetadataLandingCandidateSummary
    var commitAttempted: Bool
    var commitSucceeded: Bool
    var rollbackAttempted: Bool
    var rollbackSucceeded: Bool
    var legacyFallbackUsed: Bool
    var duplicateSuppressed: Bool
    var duplicateSuppressedCount: Int
    var readSideEquivalent: Bool
    var readSideDivergenceCount: Int
    var uiReadPathSwitched: Bool
    var legacyReadPathPreserved: Bool
    var otherDomainsStaticOnly: Bool
    var runtimeSwitchEnabled: Bool
    var generatedArtifactsStaticOnly: Bool
    var tombstoneConflictStaticOnly: Bool
    var audioUploadStaticOnly: Bool
    var recordingMetadataStaticOnly: Bool
    var recommendation: CanonicalLibraryMetadataLandingRecommendation
    var freezeViolations: [CanonicalMigrationLandingFreezeViolation]
    var blockers: [String]
    var diagnosticsSummary: String
    var redacted: Bool
}

nonisolated struct CanonicalLibraryMetadataDebugPilotBootstrapResult: Codable, Equatable, Sendable {
    var configuration: CanonicalLibraryMetadataDebugPilotConfiguration
    var freezeResult: CanonicalMigrationLandingFreezeResult
    var injectionResult: CanonicalLibraryMetadataProductionCanaryInjectionResult?
    var report: CanonicalLibraryMetadataLandingReport
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var cutoverResult: CanonicalLibraryMetadataCutoverResult?
}

nonisolated struct CanonicalLibraryMetadataPilotDiagnosticSummary: Codable, Equatable, Sendable {
    var mode: CanonicalLibraryMetadataDebugPilotMode
    var nodeRole: CanonicalProductionExecutionDomainRole
    var activePilot: CanonicalMigrationDomain?
    var freezeStatus: String
    var candidateSelected: Bool
    var candidateKind: CanonicalLibraryMetadataCanaryCandidateSafetyKind?
    var canaryAttempted: Bool
    var canarySucceeded: Bool
    var rollbackAttempted: Bool
    var rollbackSucceeded: Bool
    var legacyFallbackUsed: Bool
    var duplicateSuppressionCount: Int
    var readSideEquivalent: Bool
    var readSideDivergenceCount: Int
    var otherDomainsStatic: Bool
    var runtimeSwitchFalse: Bool
    var diagnosticsRedacted: Bool
}

nonisolated struct CanonicalLibraryMetadataPilotDiagnosticRedactor: Sendable {
    nonisolated init() {}

    nonisolated func redact(_ value: String?) -> String {
        guard let value else {
            return "redacted"
        }
        if Self.containsUnsafeSignal(value) {
            return "redacted-\(CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(value).value) ?? "diagnostic")"
        }
        return CanonicalProductionRedaction.safeDiagnosticText(value) ?? "redacted"
    }

    nonisolated static func containsUnsafeSignal(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if CanonicalProductionRedaction.containsSensitivePathSignal(value) {
            return true
        }
        if lowercased.contains("api_key")
            || lowercased.contains("apikey")
            || lowercased.contains("secret")
            || lowercased.contains("token=")
            || lowercased.contains("fingerprint")
            || lowercased.contains("transcript")
            || lowercased.contains("provider response") {
            return true
        }
        var hexRun = 0
        for scalar in lowercased.unicodeScalars {
            let value = scalar.value
            if (48...57).contains(value) || (97...102).contains(value) {
                hexRun += 1
                if hexRun >= 32 {
                    return true
                }
            } else {
                hexRun = 0
            }
        }
        return false
    }
}

nonisolated struct CanonicalLibraryMetadataPilotDiagnosticExporter: Sendable {
    nonisolated init() {}

    nonisolated func export(
        result: CanonicalLibraryMetadataDebugPilotBootstrapResult,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> CanonicalLibraryMetadataPilotDiagnosticSummary {
        let report = result.report
        return CanonicalLibraryMetadataPilotDiagnosticSummary(
            mode: report.mode,
            nodeRole: nodeRole,
            activePilot: report.activePilot,
            freezeStatus: result.freezeResult.allowed ? "allowed" : "blocked",
            candidateSelected: report.candidate.selected,
            candidateKind: report.candidate.kind,
            canaryAttempted: report.commitAttempted,
            canarySucceeded: report.commitSucceeded,
            rollbackAttempted: report.rollbackAttempted,
            rollbackSucceeded: report.rollbackSucceeded,
            legacyFallbackUsed: report.legacyFallbackUsed,
            duplicateSuppressionCount: report.duplicateSuppressedCount,
            readSideEquivalent: report.readSideEquivalent,
            readSideDivergenceCount: report.readSideDivergenceCount,
            otherDomainsStatic: report.otherDomainsStaticOnly,
            runtimeSwitchFalse: !report.runtimeSwitchEnabled,
            diagnosticsRedacted: report.redacted && result.freezeResult.redacted
        )
    }
}

nonisolated struct CanonicalLibraryMetadataDebugPilotBootstrap: Sendable {
    nonisolated init() {}

    nonisolated func evaluateOrRun(
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) async -> CanonicalLibraryMetadataDebugPilotBootstrapResult {
        let freeze = CanonicalMigrationLandingFreeze().evaluate(
            matrix: matrix,
            releaseDefaultEnabled: configuration.policy.releaseDefaultEnabled,
            runtimeSwitchEnabled: configuration.policy.runtimeSwitchEnabled,
            productionInjectionPresent: false,
            productionExecutorInjectedByDefault: false,
            productionRootWriteEnabledByDefault: false,
            legacyFallbackAvailable: configuration.evidence.legacyFallbackAvailable,
            canaryMaxObjectsPerSyncRun: configuration.policy.canaryMaxObjectsPerSyncRun,
            allEligibleEnabled: configuration.policy.allowAllEligible,
            unsafeCandidateAllowed: false,
            resourceMoveAllowed: false,
            contentWriteAllowed: false,
            tombstoneDeleteAllowed: false
        )
        var diagnostics = [
            diagnostic(
                .canonicalLibraryMetadataLandingConfigEvaluated,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: configuration.mode.rawValue,
                reason: freeze.diagnosticsSummary
            )
        ]

        if !freeze.allowed {
            diagnostics.append(
                diagnostic(
                    .canonicalMigrationLandingFreezeViolation,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: freeze.violations.map(\.rawValue).joined(separator: ",")
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataLandingBlocked,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: "landingFreezeViolation"
                )
            )
            let report = landingReport(
                configuration: configuration,
                matrix: matrix,
                freeze: freeze,
                injectionResult: nil,
                status: .blocked,
                blockers: freeze.violations.map(\.rawValue),
                reason: "landingFreezeViolation"
            )
            diagnostics.append(reportDiagnostic(configuration: configuration, report: report, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
            return CanonicalLibraryMetadataDebugPilotBootstrapResult(
                configuration: configuration,
                freezeResult: freeze,
                injectionResult: nil,
                report: report,
                diagnostics: Array(diagnostics.prefix(configuration.maxDiagnosticsEvents)),
                cutoverResult: nil
            )
        }

        if configuration.mode == .disabled {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataLandingDisabled,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "disabled",
                    reason: "defaultDisabled"
                )
            )
        }
        if configuration.mode == .diagnosticsOnly {
            let report = landingReport(
                configuration: configuration,
                matrix: matrix,
                freeze: freeze,
                injectionResult: nil,
                status: .diagnosticsOnly,
                blockers: [],
                reason: "diagnosticsOnlyNoExecution"
            )
            diagnostics.append(reportDiagnostic(configuration: configuration, report: report, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
            return CanonicalLibraryMetadataDebugPilotBootstrapResult(
                configuration: configuration,
                freezeResult: freeze,
                injectionResult: nil,
                report: report,
                diagnostics: Array(diagnostics.prefix(configuration.maxDiagnosticsEvents)),
                cutoverResult: nil
            )
        }
        if configuration.mode == .armN1Canary {
            let injection = armReadinessInjection(
                configuration: configuration,
                token: configuration.cutoverToken,
                evidence: configuration.evidence,
                matrix: matrix,
                candidates: candidates,
                trigger: trigger,
                localSnapshotAvailable: localSnapshotAvailable,
                peerSnapshotAvailable: peerSnapshotAvailable
            )
            diagnostics.append(contentsOf: landingDiagnostics(from: injection, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
            let report = landingReport(
                configuration: configuration,
                matrix: matrix,
                freeze: freeze,
                injectionResult: injection,
                status: landingStatus(from: injection.observationReport.status),
                blockers: injection.blockers.map(\.rawValue),
                reason: injection.observationReport.reason
            )
            diagnostics.append(reportDiagnostic(configuration: configuration, report: report, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
            return CanonicalLibraryMetadataDebugPilotBootstrapResult(
                configuration: configuration,
                freezeResult: freeze,
                injectionResult: injection,
                report: report,
                diagnostics: Array(diagnostics.prefix(configuration.maxDiagnosticsEvents)),
                cutoverResult: nil
            )
        }
        if configuration.mode == .executeN1Canary {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataLandingN1Started,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "started",
                    reason: "strictN1"
                )
            )
        }

        let injection = await CanonicalLibraryMetadataProductionCanaryInjection().evaluateOrRun(
            configuration: configuration.asProductionCanaryConfiguration,
            token: configuration.cutoverToken,
            evidence: configuration.evidence,
            matrix: matrix,
            candidates: candidates,
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID,
            localSnapshotAvailable: localSnapshotAvailable,
            peerSnapshotAvailable: peerSnapshotAvailable,
            executor: executor
        )
        diagnostics.append(contentsOf: landingDiagnostics(from: injection, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        let status = landingStatus(from: injection.observationReport.status)
        let blockers = injection.blockers.map(\.rawValue)
        let report = landingReport(
            configuration: configuration,
            matrix: matrix,
            freeze: freeze,
            injectionResult: injection,
            status: status,
            blockers: blockers,
            reason: injection.observationReport.reason
        )
        diagnostics.append(reportDiagnostic(configuration: configuration, report: report, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        return CanonicalLibraryMetadataDebugPilotBootstrapResult(
            configuration: configuration,
            freezeResult: freeze,
            injectionResult: injection,
            report: report,
            diagnostics: Array(diagnostics.prefix(configuration.maxDiagnosticsEvents)),
            cutoverResult: injection.cutoverResult
        )
    }

    private nonisolated func armReadinessInjection(
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix,
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool
    ) -> CanonicalLibraryMetadataProductionCanaryInjectionResult {
        let armEvidence = armCandidateSafetyEvidence(from: evidence)
        let selection = CanonicalLibraryMetadataCanarySelector().select(
            mode: .canary,
            policy: CanonicalLibraryMetadataCanaryPolicy(
                canaryMaxObjectsPerSyncRun: 1,
                allowsInternalN1Execution: true,
                explicitInternalTestConfiguration: true
            ),
            trigger: trigger,
            evidence: armEvidence,
            candidates: candidates
        )
        let safetyReports = candidates.map {
            CanonicalLibraryMetadataCanaryCandidateSafety(candidate: $0, evidence: armEvidence)
        }
        var blockers = armReadinessBlockers(
            configuration: configuration,
            token: token,
            evidence: evidence,
            matrix: matrix,
            trigger: trigger,
            localSnapshotAvailable: localSnapshotAvailable,
            peerSnapshotAvailable: peerSnapshotAvailable
        )
        if selection.selectedCandidates.isEmpty {
            let unsafeSkipped = safetyReports.contains { !$0.safe }
            blockers.append(unsafeSkipped ? .unsafeCandidateSkipped : .noEligibleCandidate)
        }
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let status: CanonicalLibraryMetadataRealCanaryObservationStatus = uniqueBlockers.isEmpty ? .armed : .blocked
        let observation = CanonicalLibraryMetadataRealCanaryObservationReport(
            status: status,
            recommendation: uniqueBlockers.isEmpty ? .stayN1 : .fixBlockers,
            configuration: configuration.asProductionCanaryConfiguration,
            selectedCandidateCount: selection.selectedCandidates.count,
            executedCandidateCount: 0,
            successfulCommitCount: 0,
            failedCommitCount: 0,
            rollbackCount: 0,
            rollbackFailureCount: 0,
            legacyFallbackCount: 0,
            duplicateSuppressionCount: 0,
            noEligibleCandidateCount: selection.selectedCandidates.isEmpty ? 1 : 0,
            unsafeCandidateSkippedCount: safetyReports.filter { !$0.safe }.count,
            fatalBlockerCount: 0,
            readSideParallelEquivalent: evidence.readSideParallelEquivalent,
            readSideParallelDivergent: !evidence.readSideParallelEquivalent,
            legacyFallbackPreserved: evidence.legacyFallbackAvailable,
            duplicateSuppressionApplied: false,
            productionRootWriteAttempted: false,
            blockers: uniqueBlockers,
            reason: uniqueBlockers.isEmpty ? "armN1ReadinessOnly" : uniqueBlockers.map(\.rawValue).joined(separator: ",")
        )
        return CanonicalLibraryMetadataProductionCanaryInjectionResult(
            configuration: configuration.asProductionCanaryConfiguration,
            injectionConfigured: true,
            executorInjected: false,
            applyPortInjected: false,
            armed: uniqueBlockers.isEmpty,
            executed: false,
            succeeded: false,
            blockers: uniqueBlockers,
            diagnostics: [],
            canaryResult: nil,
            cutoverResult: nil,
            selection: selection,
            candidateSafetyReports: safetyReports,
            observationReport: observation
        )
    }

    private nonisolated func armReadinessBlockers(
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix,
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool
    ) -> [CanonicalLibraryMetadataRealCanaryBlocker] {
        var blockers: [CanonicalLibraryMetadataRealCanaryBlocker] = []
        if configuration.policy.domain != .libraryMetadata { blockers.append(.nonLibraryMetadataDomain) }
        if configuration.policy.canaryMaxObjectsPerSyncRun != 1 {
            blockers.append(configuration.policy.canaryMaxObjectsPerSyncRun > 1 ? .canaryBudgetAboveOneDenied : .n1BudgetRequired)
        }
        if configuration.policy.runtimeSwitchEnabled { blockers.append(.runtimeSwitchDenied) }
        if configuration.policy.allowAllEligible { blockers.append(.allEligibleDenied) }
        if configuration.policy.releaseDefaultEnabled { blockers.append(.releaseDefaultDenied) }
        if configuration.policy.requiresExplicitInternalDebugConfiguration,
           !configuration.explicitInternalDebugConfiguration {
            blockers.append(.missingExplicitInternalDebugConfiguration)
        }
        let matrixReport = matrix.validate()
        if !matrixReport.allowed { blockers.append(.matrixValidationBlocked) }
        if matrixReport.activePilotDomain != .libraryMetadata { blockers.append(.activePilotNotLibraryMetadata) }
        if configuration.policy.requiresProductionToken, token == nil { blockers.append(.missingToken) }
        if configuration.policy.requiresOwnerApproval, token?.ownerApproved != true { blockers.append(.missingOwnerApproval) }
        if !localSnapshotAvailable { blockers.append(.localSnapshotUnavailable) }
        if !peerSnapshotAvailable { blockers.append(.peerSnapshotUnavailable) }
        if trigger == .viewRefresh || trigger == .retryDrainer { blockers.append(.unsupportedTrigger) }
        if !evidence.noCommitEvidenceAvailable { blockers.append(.missingNoCommitEvidence) }
        if !evidence.realDataShadowCopyVerified { blockers.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.executionShadowVerified { blockers.append(.missingExecutionShadowEvidence) }
        if !evidence.dryRunEquivalenceVerified { blockers.append(.missingDryRunEquivalence) }
        if !evidence.noBlockingDivergence { blockers.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict { blockers.append(.unresolvedConflict) }
        if !evidence.metadataManifestRouteEvidenceAvailable { blockers.append(.missingMetadataManifestRouteEvidence) }
        if evidence.rollbackPlan == nil { blockers.append(.rollbackPlanMissing) }
        if !evidence.rollbackCheckpointAvailable || !evidence.rollbackVerified || !evidence.rollbackRehearsalPassed {
            blockers.append(.rollbackVerificationMissing)
        }
        if !evidence.legacyFallbackAvailable { blockers.append(.legacyFallbackUnavailable) }
        if configuration.policy.requiresReadSideParallelEquivalent,
           !evidence.readSideParallelEquivalent {
            blockers.append(.readSideParallelDivergent)
        }
        return Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated func armCandidateSafetyEvidence(
        from evidence: CanonicalLibraryMetadataCutoverEvidence
    ) -> CanonicalLibraryMetadataCutoverEvidence {
        var armEvidence = evidence
        armEvidence.realRootBoundApplyPortAvailable = true
        armEvidence.applyPortMode = .testRootBound
        armEvidence.rootBoundWriteAvailable = true
        armEvidence.atomicReplaceAvailable = true
        armEvidence.rollbackCheckpointAvailable = true
        armEvidence.testRootUsed = true
        return armEvidence
    }

    private nonisolated func landingDiagnostics(
        from injection: CanonicalLibraryMetadataProductionCanaryInjectionResult,
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> [CanonicalLibraryMetadataCutoverDiagnostic] {
        var diagnostics = injection.diagnostics.filter { diagnostic in
            switch diagnostic.kind {
            case .canonicalLibraryMetadataProductionRootGateEvaluated,
                 .canonicalLibraryMetadataProductionRootGateBlocked,
                 .canonicalLibraryMetadataProductionRootGateAllowed,
                 .canonicalLibraryMetadataProductionRootN1Started,
                 .canonicalLibraryMetadataProductionRootN1Completed,
                 .canonicalLibraryMetadataProductionRootN1Failed,
                 .canonicalLibraryMetadataProductionRootSafetyProofBuilt,
                 .canonicalLibraryMetadataProductionRootCheckpointCreated,
                 .canonicalLibraryMetadataProductionRootAtomicWriteStarted,
                 .canonicalLibraryMetadataProductionRootAtomicWriteCompleted,
                 .canonicalLibraryMetadataProductionRootPostconditionVerified,
                 .canonicalLibraryMetadataProductionRootRollbackStarted,
                 .canonicalLibraryMetadataProductionRootRollbackCompleted,
                 .canonicalLibraryMetadataProductionRootRollbackFailed,
                 .canonicalLibraryMetadataProductionRootLegacyFallbackUsed,
                 .canonicalLibraryMetadataProductionRootDuplicateSuppressed,
                 .canonicalLibraryMetadataProductionRootReadSideEquivalent,
                 .canonicalLibraryMetadataProductionRootReadSideDivergent:
                return true
            default:
                return false
            }
        }
        if injection.armed {
            diagnostics.append(diagnostic(.canonicalLibraryMetadataLandingArmed, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "armed", reason: "strictN1Gate"))
        }
        if !injection.blockers.isEmpty {
            diagnostics.append(diagnostic(.canonicalLibraryMetadataLandingBlocked, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: injection.blockers.map(\.rawValue).joined(separator: ",")))
        }
        if let selection = injection.canaryResult?.selection ?? injection.cutoverResult?.canarySelection ?? injection.selection {
            if let selected = selection.selectedCutoverCandidates.first {
                diagnostics.append(
                    diagnostic(
                        .canonicalLibraryMetadataLandingCandidateSelected,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: selected.domain,
                        objectID: selected.objectID,
                        objectKind: selected.objectKind,
                        action: selected.cutoverActionKind.rawValue,
                        result: "selected",
                        reason: "metadataOnlyN1"
                    )
                )
            } else if selection.selectedCutoverCandidates.isEmpty {
                diagnostics.append(diagnostic(.canonicalLibraryMetadataLandingNoEligibleCandidate, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: selection.blockers.map(\.reason.rawValue).joined(separator: ",")))
            }
        } else if injection.observationReport.noEligibleCandidateCount > 0 {
            diagnostics.append(diagnostic(.canonicalLibraryMetadataLandingNoEligibleCandidate, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: "noEligibleCandidate"))
        }
        if let cutover = injection.cutoverResult {
            for commit in cutover.commits {
                diagnostics.append(
                    diagnostic(
                        .canonicalLibraryMetadataLandingCommitStarted,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: commit.domain,
                        objectID: commit.objectID,
                        objectKind: commit.objectKind,
                        action: commit.actionKind.rawValue,
                        result: "started",
                        reason: "rootBoundMetadataApply"
                    )
                )
                diagnostics.append(
                    diagnostic(
                        commit.committed && commit.postconditionVerified ? .canonicalLibraryMetadataLandingCommitCompleted : .canonicalLibraryMetadataLandingCommitFailed,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: commit.domain,
                        objectID: commit.objectID,
                        objectKind: commit.objectKind,
                        action: commit.actionKind.rawValue,
                        result: commit.committed ? "committed" : "failed",
                        reason: commit.reason
                    )
                )
            }
            for rollback in cutover.rollbackResults {
                diagnostics.append(diagnostic(.canonicalLibraryMetadataLandingRollbackStarted, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "started", reason: rollback.checkpointID))
                diagnostics.append(diagnostic(rollback.succeeded ? .canonicalLibraryMetadataLandingRollbackCompleted : .canonicalLibraryMetadataLandingRollbackFailed, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: rollback.succeeded ? "completed" : "failed", reason: rollback.reason))
            }
            if cutover.legacyFallbackUsed {
                diagnostics.append(diagnostic(.canonicalLibraryMetadataLandingLegacyFallbackUsed, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "used", reason: "legacyFallbackPreserved"))
            }
            if !cutover.duplicateLegacySuppressedActionIDs.isEmpty {
                diagnostics.append(diagnostic(.canonicalLibraryMetadataLandingDuplicateSuppressed, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "successOnly", reason: "matchingLegacyLibraryMetadataOnly"))
            }
            let equivalent = cutover.readSideProjection?.equivalent ?? injection.observationReport.readSideParallelEquivalent
            diagnostics.append(diagnostic(equivalent ? .canonicalLibraryMetadataLandingReadSideEquivalent : .canonicalLibraryMetadataLandingReadSideDivergent, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: equivalent ? "equivalent" : "divergent", reason: cutover.readSideProjection?.reason ?? "readSideParallelEvidence"))
        } else if injection.observationReport.readSideParallelEquivalent {
            diagnostics.append(diagnostic(.canonicalLibraryMetadataLandingReadSideEquivalent, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "equivalent", reason: "readSideParallelEvidence"))
        } else if injection.observationReport.readSideParallelDivergent {
            diagnostics.append(diagnostic(.canonicalLibraryMetadataLandingReadSideDivergent, configuration: configuration, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "divergent", reason: "readSideParallelEvidence"))
        }
        return diagnostics
    }

    private nonisolated func landingReport(
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        matrix: CanonicalMigrationDomainMatrix,
        freeze: CanonicalMigrationLandingFreezeResult,
        injectionResult: CanonicalLibraryMetadataProductionCanaryInjectionResult?,
        status: CanonicalLibraryMetadataLandingStatus,
        blockers: [String],
        reason: String
    ) -> CanonicalLibraryMetadataLandingReport {
        let cutover = injectionResult?.cutoverResult
        let safetyReports = cutover?.candidateSafetyReports ?? injectionResult?.candidateSafetyReports
        let selectedSafety = safetyReports?.first { $0.safe } ?? safetyReports?.first
        let selectedCandidate = injectionResult?.canaryResult?.selection.selectedCutoverCandidates.first
            ?? cutover?.canarySelection?.selectedCutoverCandidates.first
            ?? injectionResult?.selection?.selectedCutoverCandidates.first
        let selectedByCount = selectedCandidate != nil || (injectionResult?.observationReport.selectedCandidateCount ?? 0) > 0
        let commitSucceeded = cutover?.commits.contains { $0.committed && $0.preconditionVerified && $0.postconditionVerified } ?? false
        let rollbackAttempted = !(cutover?.rollbackResults.isEmpty ?? true)
        let rollbackSucceeded = rollbackAttempted ? (cutover?.rollbackResults.allSatisfy { $0.succeeded && !$0.fatal } ?? false) : false
        let readSideEquivalent = cutover?.readSideProjection?.equivalent
            ?? injectionResult?.observationReport.readSideParallelEquivalent
            ?? configuration.evidence.readSideParallelEquivalent
        let readSideDivergent = (cutover?.readSideProjection?.equivalent == false)
            || (injectionResult?.observationReport.readSideParallelDivergent ?? false)
            || !configuration.evidence.readSideParallelEquivalent
        let blockerStrings = Array(Set(blockers + freeze.violations.map(\.rawValue))).sorted()
        let report = CanonicalLibraryMetadataLandingReport(
            status: status,
            mode: configuration.mode,
            rootMode: configuration.rootMode,
            activePilot: freeze.activePilotDomain,
            candidate: CanonicalLibraryMetadataLandingCandidateSummary(
                selected: selectedByCount,
                kind: selectedSafety?.kind,
                objectKind: selectedCandidate?.objectKind,
                domain: selectedCandidate?.domain,
                actionKind: selectedCandidate?.cutoverActionKind,
                metadataOnly: selectedSafety?.metadataOnly ?? selectedByCount,
                resourceMoveAttempted: selectedSafety?.resourceMoveAttempted ?? selectedCandidate?.hasResourceMoveAttempt ?? false,
                contentBytesMutated: selectedSafety?.contentBytesMutated ?? false
            ),
            commitAttempted: !(cutover?.commits.isEmpty ?? true),
            commitSucceeded: commitSucceeded,
            rollbackAttempted: rollbackAttempted,
            rollbackSucceeded: rollbackSucceeded,
            legacyFallbackUsed: cutover?.legacyFallbackUsed ?? injectionResult?.observationReport.legacyFallbackPreserved ?? true,
            duplicateSuppressed: !(cutover?.duplicateLegacySuppressedActionIDs.isEmpty ?? true),
            duplicateSuppressedCount: cutover?.duplicateLegacySuppressedActionIDs.count ?? injectionResult?.observationReport.duplicateSuppressionCount ?? 0,
            readSideEquivalent: readSideEquivalent,
            readSideDivergenceCount: readSideDivergent ? 1 : 0,
            uiReadPathSwitched: false,
            legacyReadPathPreserved: true,
            otherDomainsStaticOnly: freeze.otherDomainsStaticOnly,
            runtimeSwitchEnabled: freeze.runtimeSwitchEnabled || configuration.policy.runtimeSwitchEnabled,
            generatedArtifactsStaticOnly: matrix.policy(for: .generatedArtifacts)?.staticOnly == true,
            tombstoneConflictStaticOnly: matrix.policy(for: .tombstoneConflict)?.staticOnly == true,
            audioUploadStaticOnly: matrix.policy(for: .audioUpload)?.staticOnly == true,
            recordingMetadataStaticOnly: matrix.policy(for: .recordingMetadata)?.staticOnly == true,
            recommendation: recommendation(
                status: status,
                blockers: blockerStrings,
                commitSucceeded: commitSucceeded,
                rollbackSucceeded: rollbackSucceeded,
                rollbackAttempted: rollbackAttempted,
                readSideEquivalent: readSideEquivalent
            ),
            freezeViolations: freeze.violations,
            blockers: blockerStrings,
            diagnosticsSummary: CanonicalProductionRedaction.safeDiagnosticText([
                "status=\(status.rawValue)",
                "mode=\(configuration.mode.rawValue)",
                "rootMode=\(configuration.rootMode.rawValue)",
                "candidateSelected=\(selectedByCount)",
                "commitAttempted=\(!(cutover?.commits.isEmpty ?? true))",
                "commitSucceeded=\(commitSucceeded)",
                "rollbackAttempted=\(rollbackAttempted)",
                "rollbackSucceeded=\(rollbackSucceeded)",
                "fallback=\(cutover?.legacyFallbackUsed ?? false)",
                "duplicateSuppressed=\(!(cutover?.duplicateLegacySuppressedActionIDs.isEmpty ?? true))",
                "readSideEquivalent=\(readSideEquivalent)",
                "uiReadPathSwitched=false",
                "otherDomainsStaticOnly=\(freeze.otherDomainsStaticOnly)",
                "runtimeSwitch=\(freeze.runtimeSwitchEnabled || configuration.policy.runtimeSwitchEnabled)",
                "reason=\(reason)"
            ].joined(separator: ",")) ?? status.rawValue,
            redacted: true
        )
        return report
    }

    private nonisolated func landingStatus(
        from status: CanonicalLibraryMetadataRealCanaryObservationStatus
    ) -> CanonicalLibraryMetadataLandingStatus {
        switch status {
        case .disabled:
            return .disabled
        case .diagnosticsOnly:
            return .diagnosticsOnly
        case .armed:
            return .armed
        case .blocked:
            return .blocked
        case .noEligibleCandidate:
            return .noEligibleCandidate
        case .unsafeCandidateSkipped:
            return .unsafeCandidateSkipped
        case .executedSucceeded:
            return .executedSucceeded
        case .executedFailedRolledBack:
            return .executedFailedRolledBack
        case .fatalRollbackFailure:
            return .fatalRollbackFailure
        }
    }

    private nonisolated func recommendation(
        status: CanonicalLibraryMetadataLandingStatus,
        blockers: [String],
        commitSucceeded: Bool,
        rollbackSucceeded: Bool,
        rollbackAttempted: Bool,
        readSideEquivalent: Bool
    ) -> CanonicalLibraryMetadataLandingRecommendation {
        if status == .disabled || status == .diagnosticsOnly {
            return .remainDisabled
        }
        if !blockers.isEmpty || !readSideEquivalent || (rollbackAttempted && !rollbackSucceeded) {
            return .fixBlockers
        }
        if commitSucceeded {
            return .runAnotherN1
        }
        if status == .armed {
            return .remainDisabled
        }
        return .fixBlockers
    }

    private nonisolated func reportDiagnostic(
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        report: CanonicalLibraryMetadataLandingReport,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        diagnostic(
            .canonicalLibraryMetadataLandingReportBuilt,
            configuration: configuration,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: report.status.rawValue,
            reason: report.diagnosticsSummary
        )
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalLibraryMetadataCutoverDiagnosticKind,
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalLibraryMetadataCutoverDomain? = nil,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        action: String? = nil,
        result: String? = nil,
        reason: String? = nil
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        CanonicalLibraryMetadataCutoverDiagnostic(
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
                "rootMode=\(configuration.rootMode.rawValue)",
                "domain=\(configuration.policy.domain.rawValue)",
                "runtimeSwitch=\(configuration.policy.runtimeSwitchEnabled)"
            ].compactMap { $0 }.joined(separator: ";")
        )
    }
}
