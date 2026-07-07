//
//  CanonicalTransferKernelReadiness.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalTransferKernelReadinessStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForV930TransferKernelRuntime = "READY_FOR_V9_3_TRANSFER_KERNEL_RUNTIME"
    case partialWithBlockers = "PARTIAL_WITH_BLOCKERS"
    case notReady = "NOT_READY"
    case unsafeToProceed = "UNSAFE_TO_PROCEED"
}

nonisolated enum CanonicalTransferKernelReadinessBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case stateMachineMissing
    case finalizeProofMissing
    case adapterMissing
    case retryBackoffMissing
    case idempotencyMissing
    case routeChanged
    case securityChanged
    case redactionMissing
    case defaultReleaseCanonicalEnabled
    case legacyFallbackMissing
    case uiCompletionMutationDetected
    case completedLedgerAcceptedAsProof
    case partialReceiveAcceptedAsProof
    case uploadRouteSchemaChanged
}

nonisolated struct CanonicalTransferKernelReadinessEvidence: Codable, Equatable, Hashable, Sendable {
    var stateMachineReady: Bool
    var finalizeProofReady: Bool
    var adapterReady: Bool
    var retryBackoffReady: Bool
    var idempotencyReady: Bool
    var noRouteChange: Bool
    var securityUnchanged: Bool
    var diagnosticsRedacted: Bool
    var defaultReleaseOldKernel: Bool
    var legacyFallbackPreserved: Bool
    var uploadRouteSchemaUnchanged: Bool
    var transferDoesNotSetUIComplete: Bool
    var completedLedgerAloneRejectedAsProof: Bool
    var partialReceiveRejectedAsProof: Bool

    nonisolated init(
        stateMachineReady: Bool = false,
        finalizeProofReady: Bool = false,
        adapterReady: Bool = false,
        retryBackoffReady: Bool = false,
        idempotencyReady: Bool = false,
        noRouteChange: Bool = false,
        securityUnchanged: Bool = false,
        diagnosticsRedacted: Bool = false,
        defaultReleaseOldKernel: Bool = false,
        legacyFallbackPreserved: Bool = false,
        uploadRouteSchemaUnchanged: Bool = false,
        transferDoesNotSetUIComplete: Bool = false,
        completedLedgerAloneRejectedAsProof: Bool = false,
        partialReceiveRejectedAsProof: Bool = false
    ) {
        self.stateMachineReady = stateMachineReady
        self.finalizeProofReady = finalizeProofReady
        self.adapterReady = adapterReady
        self.retryBackoffReady = retryBackoffReady
        self.idempotencyReady = idempotencyReady
        self.noRouteChange = noRouteChange
        self.securityUnchanged = securityUnchanged
        self.diagnosticsRedacted = diagnosticsRedacted
        self.defaultReleaseOldKernel = defaultReleaseOldKernel
        self.legacyFallbackPreserved = legacyFallbackPreserved
        self.uploadRouteSchemaUnchanged = uploadRouteSchemaUnchanged
        self.transferDoesNotSetUIComplete = transferDoesNotSetUIComplete
        self.completedLedgerAloneRejectedAsProof = completedLedgerAloneRejectedAsProof
        self.partialReceiveRejectedAsProof = partialReceiveRejectedAsProof
    }

    nonisolated var unsafeBlockers: [CanonicalTransferKernelReadinessBlocker] {
        var blockers: [CanonicalTransferKernelReadinessBlocker] = []
        if !noRouteChange { blockers.append(.routeChanged) }
        if !securityUnchanged { blockers.append(.securityChanged) }
        if !defaultReleaseOldKernel { blockers.append(.defaultReleaseCanonicalEnabled) }
        if !legacyFallbackPreserved { blockers.append(.legacyFallbackMissing) }
        if !uploadRouteSchemaUnchanged { blockers.append(.uploadRouteSchemaChanged) }
        if !transferDoesNotSetUIComplete { blockers.append(.uiCompletionMutationDetected) }
        if !completedLedgerAloneRejectedAsProof { blockers.append(.completedLedgerAcceptedAsProof) }
        if !partialReceiveRejectedAsProof { blockers.append(.partialReceiveAcceptedAsProof) }
        return blockers
    }

    nonisolated var readinessBlockers: [CanonicalTransferKernelReadinessBlocker] {
        var blockers: [CanonicalTransferKernelReadinessBlocker] = []
        if !stateMachineReady { blockers.append(.stateMachineMissing) }
        if !finalizeProofReady { blockers.append(.finalizeProofMissing) }
        if !adapterReady { blockers.append(.adapterMissing) }
        if !retryBackoffReady { blockers.append(.retryBackoffMissing) }
        if !idempotencyReady { blockers.append(.idempotencyMissing) }
        if !diagnosticsRedacted { blockers.append(.redactionMissing) }
        return blockers
    }

    nonisolated var coreRuntimePresent: Bool {
        stateMachineReady || finalizeProofReady || retryBackoffReady || adapterReady
    }
}

nonisolated struct CanonicalTransferKernelReadinessReport: Codable, Equatable, Hashable, Sendable {
    var status: CanonicalTransferKernelReadinessStatus
    var blockers: [CanonicalTransferKernelReadinessBlocker]
    var readyForV930TransferKernelRuntime: Bool

    nonisolated init(
        status: CanonicalTransferKernelReadinessStatus,
        blockers: [CanonicalTransferKernelReadinessBlocker]
    ) {
        self.status = status
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.readyForV930TransferKernelRuntime = status == .readyForV930TransferKernelRuntime
    }
}

nonisolated struct CanonicalTransferKernelReadiness: Sendable {
    nonisolated init() {}

    nonisolated static func v930(
        _ evidence: CanonicalTransferKernelReadinessEvidence
    ) -> CanonicalTransferKernelReadinessReport {
        let unsafe = evidence.unsafeBlockers
        if unsafe.isEmpty == false {
            return CanonicalTransferKernelReadinessReport(status: .unsafeToProceed, blockers: unsafe)
        }

        let blockers = evidence.readinessBlockers
        if blockers.isEmpty {
            return CanonicalTransferKernelReadinessReport(
                status: .readyForV930TransferKernelRuntime,
                blockers: []
            )
        }

        return CanonicalTransferKernelReadinessReport(
            status: evidence.coreRuntimePresent ? .partialWithBlockers : .notReady,
            blockers: blockers
        )
    }
}
