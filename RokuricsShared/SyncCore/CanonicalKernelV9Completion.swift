//
//  CanonicalKernelV9Completion.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalKernelV9ReadinessStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForV9RuntimeImplementation = "READY_FOR_V9_RUNTIME_IMPLEMENTATION"
    case partialWithBlockers = "PARTIAL_WITH_BLOCKERS"
    case notReady = "NOT_READY"
    case unsafeToProceed = "UNSAFE_TO_PROCEED"
}

nonisolated enum CanonicalKernelV9ReadinessBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case baseTypesMissing
    case connectionContractMissing
    case transferContractMissing
    case syncTruthContractMissing
    case realtimeExchangeContractMissing
    case fileContractMissing
    case diagnosticsTaxonomyMissing
    case invariantsMissing
    case docsMissing
    case iPhoneTestsMissing
    case macTestsMissing
    case transportIndependenceMissing
    case routeOrSecurityBypassDetected
    case defaultOrReleaseCanonicalEnabled
    case legacyFallbackMissing
    case peerProofViolationDetected
    case mainActorHeavyWorkAllowed
    case diagnosticsLeakDetected
}

nonisolated struct CanonicalKernelV9ContractEvidence: Codable, Equatable, Hashable, Sendable {
    var baseTypesDefined: Bool
    var connectionContractDefined: Bool
    var transferContractDefined: Bool
    var syncTruthContractDefined: Bool
    var realtimeExchangeContractDefined: Bool
    var fileContractDefined: Bool
    var diagnosticsTaxonomyDefined: Bool
    var invariantsDefined: Bool
    var docsUpdated: Bool
    var iPhoneTestsAdded: Bool
    var macTestsAdded: Bool
    var transportIndependent: Bool
    var defaultReleaseOldKernel: Bool
    var legacyFallbackPreserved: Bool
    var noRouteOrSchemaChange: Bool
    var securityLayerUnchanged: Bool
    var peerProofRulesEnforced: Bool
    var mainActorHeavyWorkForbidden: Bool
    var diagnosticsRedactionEnforced: Bool
    var routeOrSecurityBypassDetected: Bool
    var defaultOrReleaseCanonicalEnabled: Bool
    var legacyFallbackMissing: Bool
    var peerProofViolationDetected: Bool
    var mainActorHeavyWorkAllowed: Bool
    var diagnosticsLeakDetected: Bool

    nonisolated init(
        baseTypesDefined: Bool = false,
        connectionContractDefined: Bool = false,
        transferContractDefined: Bool = false,
        syncTruthContractDefined: Bool = false,
        realtimeExchangeContractDefined: Bool = false,
        fileContractDefined: Bool = false,
        diagnosticsTaxonomyDefined: Bool = false,
        invariantsDefined: Bool = false,
        docsUpdated: Bool = false,
        iPhoneTestsAdded: Bool = false,
        macTestsAdded: Bool = false,
        transportIndependent: Bool = false,
        defaultReleaseOldKernel: Bool = false,
        legacyFallbackPreserved: Bool = false,
        noRouteOrSchemaChange: Bool = false,
        securityLayerUnchanged: Bool = false,
        peerProofRulesEnforced: Bool = false,
        mainActorHeavyWorkForbidden: Bool = false,
        diagnosticsRedactionEnforced: Bool = false,
        routeOrSecurityBypassDetected: Bool = false,
        defaultOrReleaseCanonicalEnabled: Bool = false,
        legacyFallbackMissing: Bool = false,
        peerProofViolationDetected: Bool = false,
        mainActorHeavyWorkAllowed: Bool = false,
        diagnosticsLeakDetected: Bool = false
    ) {
        self.baseTypesDefined = baseTypesDefined
        self.connectionContractDefined = connectionContractDefined
        self.transferContractDefined = transferContractDefined
        self.syncTruthContractDefined = syncTruthContractDefined
        self.realtimeExchangeContractDefined = realtimeExchangeContractDefined
        self.fileContractDefined = fileContractDefined
        self.diagnosticsTaxonomyDefined = diagnosticsTaxonomyDefined
        self.invariantsDefined = invariantsDefined
        self.docsUpdated = docsUpdated
        self.iPhoneTestsAdded = iPhoneTestsAdded
        self.macTestsAdded = macTestsAdded
        self.transportIndependent = transportIndependent
        self.defaultReleaseOldKernel = defaultReleaseOldKernel
        self.legacyFallbackPreserved = legacyFallbackPreserved
        self.noRouteOrSchemaChange = noRouteOrSchemaChange
        self.securityLayerUnchanged = securityLayerUnchanged
        self.peerProofRulesEnforced = peerProofRulesEnforced
        self.mainActorHeavyWorkForbidden = mainActorHeavyWorkForbidden
        self.diagnosticsRedactionEnforced = diagnosticsRedactionEnforced
        self.routeOrSecurityBypassDetected = routeOrSecurityBypassDetected
        self.defaultOrReleaseCanonicalEnabled = defaultOrReleaseCanonicalEnabled
        self.legacyFallbackMissing = legacyFallbackMissing
        self.peerProofViolationDetected = peerProofViolationDetected
        self.mainActorHeavyWorkAllowed = mainActorHeavyWorkAllowed
        self.diagnosticsLeakDetected = diagnosticsLeakDetected
    }

    nonisolated var hasUnsafeEvidence: Bool {
        routeOrSecurityBypassDetected
            || defaultOrReleaseCanonicalEnabled
            || legacyFallbackMissing
            || peerProofViolationDetected
            || mainActorHeavyWorkAllowed
            || diagnosticsLeakDetected
    }

    nonisolated var coreContractsComplete: Bool {
        baseTypesDefined
            && connectionContractDefined
            && transferContractDefined
            && syncTruthContractDefined
            && realtimeExchangeContractDefined
            && fileContractDefined
            && diagnosticsTaxonomyDefined
            && invariantsDefined
            && transportIndependent
    }

    nonisolated var allReadinessEvidenceComplete: Bool {
        coreContractsComplete
            && docsUpdated
            && iPhoneTestsAdded
            && macTestsAdded
            && defaultReleaseOldKernel
            && legacyFallbackPreserved
            && noRouteOrSchemaChange
            && securityLayerUnchanged
            && peerProofRulesEnforced
            && mainActorHeavyWorkForbidden
            && diagnosticsRedactionEnforced
    }
}

nonisolated struct CanonicalKernelV9ReadinessReport: Codable, Equatable, Hashable, Sendable {
    var status: CanonicalKernelV9ReadinessStatus
    var blockers: [CanonicalKernelV9ReadinessBlocker]
    var readyForRuntimeImplementation: Bool

    nonisolated init(
        status: CanonicalKernelV9ReadinessStatus,
        blockers: [CanonicalKernelV9ReadinessBlocker]
    ) {
        self.status = status
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.readyForRuntimeImplementation = status == .readyForV9RuntimeImplementation
    }
}

nonisolated struct CanonicalKernelV9ContractReadinessGate: Sendable {
    nonisolated init() {}

    nonisolated static func v900(_ evidence: CanonicalKernelV9ContractEvidence) -> CanonicalKernelV9ReadinessReport {
        if evidence.hasUnsafeEvidence {
            return CanonicalKernelV9ReadinessReport(
                status: .unsafeToProceed,
                blockers: unsafeBlockers(from: evidence)
            )
        }

        let blockers = readinessBlockers(from: evidence)
        if blockers.isEmpty && evidence.allReadinessEvidenceComplete {
            return CanonicalKernelV9ReadinessReport(
                status: .readyForV9RuntimeImplementation,
                blockers: []
            )
        }

        if !evidence.coreContractsComplete {
            return CanonicalKernelV9ReadinessReport(
                status: .notReady,
                blockers: blockers
            )
        }

        return CanonicalKernelV9ReadinessReport(
            status: .partialWithBlockers,
            blockers: blockers
        )
    }

    private nonisolated static func unsafeBlockers(
        from evidence: CanonicalKernelV9ContractEvidence
    ) -> [CanonicalKernelV9ReadinessBlocker] {
        var blockers: [CanonicalKernelV9ReadinessBlocker] = []
        if evidence.routeOrSecurityBypassDetected {
            blockers.append(.routeOrSecurityBypassDetected)
        }
        if evidence.defaultOrReleaseCanonicalEnabled {
            blockers.append(.defaultOrReleaseCanonicalEnabled)
        }
        if evidence.legacyFallbackMissing {
            blockers.append(.legacyFallbackMissing)
        }
        if evidence.peerProofViolationDetected {
            blockers.append(.peerProofViolationDetected)
        }
        if evidence.mainActorHeavyWorkAllowed {
            blockers.append(.mainActorHeavyWorkAllowed)
        }
        if evidence.diagnosticsLeakDetected {
            blockers.append(.diagnosticsLeakDetected)
        }
        return blockers
    }

    private nonisolated static func readinessBlockers(
        from evidence: CanonicalKernelV9ContractEvidence
    ) -> [CanonicalKernelV9ReadinessBlocker] {
        var blockers: [CanonicalKernelV9ReadinessBlocker] = []
        if !evidence.baseTypesDefined {
            blockers.append(.baseTypesMissing)
        }
        if !evidence.connectionContractDefined {
            blockers.append(.connectionContractMissing)
        }
        if !evidence.transferContractDefined {
            blockers.append(.transferContractMissing)
        }
        if !evidence.syncTruthContractDefined {
            blockers.append(.syncTruthContractMissing)
        }
        if !evidence.realtimeExchangeContractDefined {
            blockers.append(.realtimeExchangeContractMissing)
        }
        if !evidence.fileContractDefined {
            blockers.append(.fileContractMissing)
        }
        if !evidence.diagnosticsTaxonomyDefined {
            blockers.append(.diagnosticsTaxonomyMissing)
        }
        if !evidence.invariantsDefined {
            blockers.append(.invariantsMissing)
        }
        if !evidence.docsUpdated {
            blockers.append(.docsMissing)
        }
        if !evidence.iPhoneTestsAdded {
            blockers.append(.iPhoneTestsMissing)
        }
        if !evidence.macTestsAdded {
            blockers.append(.macTestsMissing)
        }
        if !evidence.transportIndependent {
            blockers.append(.transportIndependenceMissing)
        }
        if !evidence.defaultReleaseOldKernel {
            blockers.append(.defaultOrReleaseCanonicalEnabled)
        }
        if !evidence.legacyFallbackPreserved {
            blockers.append(.legacyFallbackMissing)
        }
        if !evidence.noRouteOrSchemaChange || !evidence.securityLayerUnchanged {
            blockers.append(.routeOrSecurityBypassDetected)
        }
        if !evidence.peerProofRulesEnforced {
            blockers.append(.peerProofViolationDetected)
        }
        if !evidence.mainActorHeavyWorkForbidden {
            blockers.append(.mainActorHeavyWorkAllowed)
        }
        if !evidence.diagnosticsRedactionEnforced {
            blockers.append(.diagnosticsLeakDetected)
        }
        return blockers
    }
}
