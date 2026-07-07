//
//  CanonicalRuntimeReadiness.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalRuntimeReadinessDomain: String, Codable, Equatable, CaseIterable, Sendable {
    case fileRuntime
    case transportRuntime
    case uploadRuntime
    case applyExecutor
    case conflictResolver
    case simulationHarness
    case productionMigration
}

nonisolated enum CanonicalRuntimeReadinessStatus: String, Codable, Equatable, Hashable, Sendable {
    case notEvaluated
    case notStarted
    case semanticsModeled
    case offlineRuntimeComplete
    case offlineKernelReady
    case productionPortsDeclared
    case dryRunAvailable
    case dryRunEquivalent
    case productionAdapterMissing
    case productionBlocked
    case eligibleForManualMigrationDesign
    case eligibleForShadowMigration
    case eligibleForRuntimeSwitch
    case retired
    case blockedForProduction
    case failed
}

nonisolated enum CanonicalRuntimeReadinessBlockerKind: String, Codable, Equatable, Sendable {
    case rootBindingMissing
    case hashVerificationMissing
    case routeValidationMissing
    case resumableStateMissing
    case applyExecutorMissing
    case conflictResolverMissing
    case harnessMissing
    case legacyProductionOwner
}

nonisolated struct CanonicalRuntimeReadinessBlocker: Codable, Equatable, Identifiable, Sendable {
    var id: String { [domain.rawValue, kind.rawValue, detail ?? ""].joined(separator: "|") }
    var domain: CanonicalRuntimeReadinessDomain
    var kind: CanonicalRuntimeReadinessBlockerKind
    var detail: String?
}

nonisolated struct CanonicalRuntimeReadinessEvidence: Codable, Equatable, Sendable {
    var fileRootBinding: Bool
    var fileHashVerification: Bool
    var transportRouteValidation: Bool
    var uploadResumableState: Bool
    var applyExecutor: Bool
    var conflictResolver: Bool
    var twoNodeHarness: Bool
    var productionStillLegacyOwned: Bool

    nonisolated init(
        fileRootBinding: Bool = false,
        fileHashVerification: Bool = false,
        transportRouteValidation: Bool = false,
        uploadResumableState: Bool = false,
        applyExecutor: Bool = false,
        conflictResolver: Bool = false,
        twoNodeHarness: Bool = false,
        productionStillLegacyOwned: Bool = true
    ) {
        self.fileRootBinding = fileRootBinding
        self.fileHashVerification = fileHashVerification
        self.transportRouteValidation = transportRouteValidation
        self.uploadResumableState = uploadResumableState
        self.applyExecutor = applyExecutor
        self.conflictResolver = conflictResolver
        self.twoNodeHarness = twoNodeHarness
        self.productionStillLegacyOwned = productionStillLegacyOwned
    }
}

nonisolated struct CanonicalRuntimeReadinessReport: Codable, Equatable, Sendable {
    var generatedAt: CanonicalTimestamp
    var statuses: [CanonicalRuntimeReadinessDomain: CanonicalRuntimeReadinessStatus]
    var blockers: [CanonicalRuntimeReadinessBlocker]

    nonisolated func status(for domain: CanonicalRuntimeReadinessDomain) -> CanonicalRuntimeReadinessStatus {
        statuses[domain] ?? .notStarted
    }
}

nonisolated struct CanonicalRuntimeReadinessEvaluator {
    nonisolated init() {}

    nonisolated func evaluate(
        evidence: CanonicalRuntimeReadinessEvidence,
        generatedAt: Date = Date()
    ) -> CanonicalRuntimeReadinessReport {
        var statuses = Dictionary(uniqueKeysWithValues: CanonicalRuntimeReadinessDomain.allCases.map {
            ($0, CanonicalRuntimeReadinessStatus.notStarted)
        })
        var blockers: [CanonicalRuntimeReadinessBlocker] = []

        set(
            .fileRuntime,
            passed: evidence.fileRootBinding && evidence.fileHashVerification,
            missing: [
                evidence.fileRootBinding ? nil : .rootBindingMissing,
                evidence.fileHashVerification ? nil : .hashVerificationMissing
            ],
            statuses: &statuses,
            blockers: &blockers
        )
        set(
            .transportRuntime,
            passed: evidence.transportRouteValidation,
            missing: [evidence.transportRouteValidation ? nil : .routeValidationMissing],
            statuses: &statuses,
            blockers: &blockers
        )
        set(
            .uploadRuntime,
            passed: evidence.uploadResumableState,
            missing: [evidence.uploadResumableState ? nil : .resumableStateMissing],
            statuses: &statuses,
            blockers: &blockers
        )
        set(
            .applyExecutor,
            passed: evidence.applyExecutor,
            missing: [evidence.applyExecutor ? nil : .applyExecutorMissing],
            statuses: &statuses,
            blockers: &blockers
        )
        set(
            .conflictResolver,
            passed: evidence.conflictResolver,
            missing: [evidence.conflictResolver ? nil : .conflictResolverMissing],
            statuses: &statuses,
            blockers: &blockers
        )
        set(
            .simulationHarness,
            passed: evidence.twoNodeHarness,
            missing: [evidence.twoNodeHarness ? nil : .harnessMissing],
            statuses: &statuses,
            blockers: &blockers
        )

        if evidence.productionStillLegacyOwned {
            statuses[.productionMigration] = .blockedForProduction
            blockers.append(
                CanonicalRuntimeReadinessBlocker(
                    domain: .productionMigration,
                    kind: .legacyProductionOwner,
                    detail: "offlineRuntimeOnly"
                )
            )
        } else {
            statuses[.productionMigration] = .offlineRuntimeComplete
        }

        return CanonicalRuntimeReadinessReport(
            generatedAt: CanonicalTimestamp(generatedAt),
            statuses: statuses,
            blockers: blockers
        )
    }

    private func set(
        _ domain: CanonicalRuntimeReadinessDomain,
        passed: Bool,
        missing: [CanonicalRuntimeReadinessBlockerKind?],
        statuses: inout [CanonicalRuntimeReadinessDomain: CanonicalRuntimeReadinessStatus],
        blockers: inout [CanonicalRuntimeReadinessBlocker]
    ) {
        statuses[domain] = passed ? .offlineRuntimeComplete : .failed
        for kind in missing.compactMap({ $0 }) {
            blockers.append(CanonicalRuntimeReadinessBlocker(domain: domain, kind: kind, detail: nil))
        }
    }
}
