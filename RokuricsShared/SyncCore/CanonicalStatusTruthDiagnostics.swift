//
//  CanonicalStatusTruthDiagnostics.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalStatusTruthDiagnosticEvent: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case statusFactProduced
    case statusFactMerged
    case statusFactRejected
    case statusProofExpired
    case effectiveStatusProjected
    case statusProjectionDurationMs
    case mainActorStatusReconciliationAttemptCount
    case metadataOnlyRejectedAsAudioProof
    case completedLedgerRejectedAsPeerProof
    case partialReceiveRejectedAsCompleted
    case peerProofUnavailable
    case finalizeProofAccepted
    case existingDifferentAudioConflict
    case uploadJobCreationDeniedByStatusTruth
}

nonisolated struct CanonicalStatusTruthDiagnosticRecord: Codable, Equatable, Hashable, Sendable {
    var event: CanonicalStatusTruthDiagnosticEvent
    var objectID: CanonicalObjectID?
    var domain: CanonicalStatusDomain?
    var factID: CanonicalStatusFactID?
    var source: CanonicalStatusSource?
    var phase: CanonicalStatusPhase?
    var hashPrefix: String?
    var byteSize: Int64?
    var redactedDetail: String?

    nonisolated init(
        event: CanonicalStatusTruthDiagnosticEvent,
        objectID: CanonicalObjectID? = nil,
        domain: CanonicalStatusDomain? = nil,
        factID: CanonicalStatusFactID? = nil,
        source: CanonicalStatusSource? = nil,
        phase: CanonicalStatusPhase? = nil,
        hash: CanonicalHash? = nil,
        hashPrefix: String? = nil,
        byteSize: Int64? = nil,
        detail: String? = nil
    ) {
        self.event = event
        self.objectID = objectID
        self.domain = domain
        self.factID = factID
        self.source = source
        self.phase = phase
        self.hashPrefix = CanonicalStatusTruthRedaction.hashPrefix(hash?.value ?? hashPrefix)
        self.byteSize = byteSize.map { max(0, $0) }
        self.redactedDetail = CanonicalStatusTruthRedaction.safeDetail(detail)
    }

    nonisolated var isRedacted: Bool {
        if let redactedDetail,
           !CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(redactedDetail) {
            return false
        }
        if let hashPrefix, hashPrefix.count > 16 {
            return false
        }
        return true
    }

    nonisolated var summary: String {
        [
            "event=\(event.rawValue)",
            objectID.map { "objectID=\($0.rawValue)" },
            domain.map { "domain=\($0.rawValue)" },
            factID.map { "factID=\($0.rawValue)" },
            source.map { "source=\($0.rawValue)" },
            phase.map { "phase=\($0.rawValue)" },
            hashPrefix.map { "hashPrefix=\($0)" },
            byteSize.map { "byteSize=\($0)" },
            redactedDetail.map { "detail=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }
}

nonisolated enum CanonicalStatusTruthRedaction {
    nonisolated static func hashPrefix(_ value: String?) -> String? {
        guard let value = CanonicalKernelStringSanitizer.optional(value) else {
            return nil
        }
        return String(value.lowercased().prefix(12))
    }

    nonisolated static func safeDetail(_ value: String?) -> String? {
        guard let value = CanonicalKernelStringSanitizer.optional(value) else {
            return nil
        }
        if CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(value) {
            return String(value.prefix(160))
        }
        return "redactionRejected"
    }
}
