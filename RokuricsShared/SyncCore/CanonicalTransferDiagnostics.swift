//
//  CanonicalTransferDiagnostics.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalTransferDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case runtimeBlocked
    case startRequested
    case statusRefreshed
    case chunkAccepted
    case duplicateChunkAccepted
    case wrongOffsetStatusRefreshRequired
    case retryBlocked
    case retryEligibleExistingJob
    case finalizeProofAccepted
    case finalizeProofRejected
    case redactionRejected
}

nonisolated struct CanonicalTransferDiagnosticRecord: Codable, Equatable, Hashable, Sendable {
    var kind: CanonicalTransferDiagnosticKind
    var objectID: CanonicalObjectID?
    var sessionID: CanonicalTransferSessionID?
    var confirmedBytes: Int64?
    var hashPrefix: String?
    var redactedDetail: String?

    nonisolated init(
        kind: CanonicalTransferDiagnosticKind,
        objectID: CanonicalObjectID? = nil,
        sessionID: CanonicalTransferSessionID? = nil,
        confirmedBytes: Int64? = nil,
        hashPrefix: String? = nil,
        redactedDetail: String? = nil
    ) {
        self.kind = kind
        self.objectID = objectID
        self.sessionID = sessionID
        self.confirmedBytes = confirmedBytes.map { max(0, $0) }
        self.hashPrefix = hashPrefix.map(CanonicalTransferDiagnostics.hashPrefix)
        self.redactedDetail = redactedDetail.map(CanonicalTransferDiagnostics.redact)
    }

    nonisolated var forbiddenSignals: [CanonicalDiagnosticForbiddenSignal] {
        CanonicalKernelDiagnosticRedaction.detectForbiddenSignals(in: redactedDetail ?? "")
    }

    nonisolated var diagnosticsSummary: String {
        [
            "kind=\(kind.rawValue)",
            objectID.map { "objectID=\($0.rawValue)" },
            sessionID.map { "sessionID=\($0.rawValue)" },
            confirmedBytes.map { "confirmedBytes=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" },
            redactedDetail.map { "detail=\($0)" },
            "redacted=true"
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated enum CanonicalTransferDiagnostics {
    nonisolated static func hashPrefix(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(12))
    }

    nonisolated static func redact(_ value: String) -> String {
        let signals = CanonicalKernelDiagnosticRedaction.detectForbiddenSignals(in: value)
        guard signals.isEmpty else {
            return "redacted=true,count=\(signals.count)"
        }
        return CanonicalKernelStringSanitizer.optional(value) ?? "redacted"
    }

    nonisolated static func finalizeProofAccepted(
        _ proof: CanonicalTransferFinalizeProof
    ) -> CanonicalTransferDiagnosticRecord {
        CanonicalTransferDiagnosticRecord(
            kind: .finalizeProofAccepted,
            objectID: proof.objectID,
            sessionID: proof.sessionID,
            confirmedBytes: proof.byteSize,
            hashPrefix: proof.contentHashPrefix,
            redactedDetail: CanonicalTransferProofRedaction.safeProofSummary(proof)
        )
    }

    nonisolated static func retryEvaluation(
        objectID: CanonicalObjectID,
        sessionID: CanonicalTransferSessionID?,
        evaluation: CanonicalTransferRetryEvaluation
    ) -> CanonicalTransferDiagnosticRecord {
        CanonicalTransferDiagnosticRecord(
            kind: evaluation.decision == .eligibleToResume ? .retryEligibleExistingJob : .retryBlocked,
            objectID: objectID,
            sessionID: sessionID,
            confirmedBytes: evaluation.resumeOffset,
            redactedDetail: [
                "decision=\(evaluation.decision.rawValue)",
                "createdFreshJob=\(evaluation.createdFreshJob)",
                "resumedExistingJob=\(evaluation.resumedExistingJob)",
                "blockers=\(evaluation.blockers.map(\.rawValue).joined(separator: "|"))"
            ].joined(separator: ",")
        )
    }
}
