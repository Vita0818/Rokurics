//
//  CanonicalStatusTruthReadiness.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalStatusTruthReadinessStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForV940StatusTruth
    case partialWithBlockers
    case notReady
    case unsafeToProceed
}

nonisolated enum CanonicalStatusTruthReadinessBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case proofDrivenEffectiveStatusMissing
    case hardRulesMissing
    case factStoreMissing
    case integrationAvailabilityMissing
    case uploadJobGateMissing
    case diagnosticsRedactionMissing
    case oldKernelFallbackMissing
    case defaultReleaseNotOldKernel
    case legacyFallbackMissing
    case routeOrUploadSchemaChanged
    case securityInvariantChanged
    case peerProofViolation
    case diagnosticsLeakDetected
}

nonisolated struct CanonicalStatusTruthReadinessEvidence: Codable, Equatable, Hashable, Sendable {
    var proofDrivenEffectiveStatus: Bool
    var hardRulesEnforced: Bool
    var factStoreReady: Bool
    var integrationAvailabilityReady: Bool
    var uploadJobGateReady: Bool
    var diagnosticsRedacted: Bool
    var oldKernelFallbackPreserved: Bool
    var defaultReleaseOldKernel: Bool
    var legacyFallbackPreserved: Bool
    var noRouteChange: Bool
    var uploadRouteSchemaUnchanged: Bool
    var securityInvariantUnchanged: Bool
    var peerProofViolationDetected: Bool
    var diagnosticsLeakDetected: Bool

    nonisolated init(
        proofDrivenEffectiveStatus: Bool = false,
        hardRulesEnforced: Bool = false,
        factStoreReady: Bool = false,
        integrationAvailabilityReady: Bool = false,
        uploadJobGateReady: Bool = false,
        diagnosticsRedacted: Bool = false,
        oldKernelFallbackPreserved: Bool = false,
        defaultReleaseOldKernel: Bool = false,
        legacyFallbackPreserved: Bool = false,
        noRouteChange: Bool = true,
        uploadRouteSchemaUnchanged: Bool = true,
        securityInvariantUnchanged: Bool = true,
        peerProofViolationDetected: Bool = false,
        diagnosticsLeakDetected: Bool = false
    ) {
        self.proofDrivenEffectiveStatus = proofDrivenEffectiveStatus
        self.hardRulesEnforced = hardRulesEnforced
        self.factStoreReady = factStoreReady
        self.integrationAvailabilityReady = integrationAvailabilityReady
        self.uploadJobGateReady = uploadJobGateReady
        self.diagnosticsRedacted = diagnosticsRedacted
        self.oldKernelFallbackPreserved = oldKernelFallbackPreserved
        self.defaultReleaseOldKernel = defaultReleaseOldKernel
        self.legacyFallbackPreserved = legacyFallbackPreserved
        self.noRouteChange = noRouteChange
        self.uploadRouteSchemaUnchanged = uploadRouteSchemaUnchanged
        self.securityInvariantUnchanged = securityInvariantUnchanged
        self.peerProofViolationDetected = peerProofViolationDetected
        self.diagnosticsLeakDetected = diagnosticsLeakDetected
    }
}

nonisolated struct CanonicalStatusTruthReadinessReport: Codable, Equatable, Hashable, Sendable {
    var status: CanonicalStatusTruthReadinessStatus
    var blockers: [CanonicalStatusTruthReadinessBlocker]
    var evidence: CanonicalStatusTruthReadinessEvidence

    nonisolated var ready: Bool {
        status == .readyForV940StatusTruth
    }
}

nonisolated enum CanonicalStatusTruthReadiness {
    nonisolated static func v940(_ evidence: CanonicalStatusTruthReadinessEvidence) -> CanonicalStatusTruthReadinessReport {
        var blockers: [CanonicalStatusTruthReadinessBlocker] = []

        if !evidence.proofDrivenEffectiveStatus { blockers.append(.proofDrivenEffectiveStatusMissing) }
        if !evidence.hardRulesEnforced { blockers.append(.hardRulesMissing) }
        if !evidence.factStoreReady { blockers.append(.factStoreMissing) }
        if !evidence.integrationAvailabilityReady { blockers.append(.integrationAvailabilityMissing) }
        if !evidence.uploadJobGateReady { blockers.append(.uploadJobGateMissing) }
        if !evidence.diagnosticsRedacted { blockers.append(.diagnosticsRedactionMissing) }
        if !evidence.oldKernelFallbackPreserved { blockers.append(.oldKernelFallbackMissing) }
        if !evidence.defaultReleaseOldKernel { blockers.append(.defaultReleaseNotOldKernel) }
        if !evidence.legacyFallbackPreserved { blockers.append(.legacyFallbackMissing) }
        if !evidence.noRouteChange || !evidence.uploadRouteSchemaUnchanged { blockers.append(.routeOrUploadSchemaChanged) }
        if !evidence.securityInvariantUnchanged { blockers.append(.securityInvariantChanged) }
        if evidence.peerProofViolationDetected { blockers.append(.peerProofViolation) }
        if evidence.diagnosticsLeakDetected { blockers.append(.diagnosticsLeakDetected) }

        let unsafe: Set<CanonicalStatusTruthReadinessBlocker> = [
            .defaultReleaseNotOldKernel,
            .legacyFallbackMissing,
            .routeOrUploadSchemaChanged,
            .securityInvariantChanged,
            .peerProofViolation,
            .diagnosticsLeakDetected
        ]
        let status: CanonicalStatusTruthReadinessStatus
        if blockers.contains(where: unsafe.contains) {
            status = .unsafeToProceed
        } else if blockers.isEmpty {
            status = .readyForV940StatusTruth
        } else if evidence.proofDrivenEffectiveStatus || evidence.hardRulesEnforced || evidence.factStoreReady {
            status = .partialWithBlockers
        } else {
            status = .notReady
        }

        return CanonicalStatusTruthReadinessReport(
            status: status,
            blockers: Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue },
            evidence: evidence
        )
    }
}
