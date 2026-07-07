//
//  CanonicalKernelDiagnostics.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalKernelDiagnosticCategory: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case performance
    case convergence
    case redaction
}

nonisolated enum CanonicalKernelDiagnosticEventKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readProjectionRebuildDurationMs
    case studyTreeRebuildDurationMs
    case fileTreeSnapshotDurationMs
    case manifestBuildDurationMs
    case checksumCacheHit
    case checksumCacheMiss
    case checksumCacheStaleCount
    case hashDurationMs
    case mainActorLongTaskDurationMs
    case routeDurationMs
    case diagnosticsWriteDurationMs
    case statusFactProduced
    case statusFactMerged
    case statusDeltaSent
    case statusDeltaReceived
    case statusAckSent
    case statusAckReceived
    case statusRequestSent
    case statusRequestReceived
    case statusEnvelopeCarriedOverHeartbeat
    case statusEnvelopeCarriedOverInventory
    case fullInventoryRequested
    case statusFactRejected
    case statusProofExpired
    case effectiveStatusProjected
    case statusProjectionDurationMs
    case mainActorStatusReconciliationAttemptCount
    case syncRequestedHintAdvertised
    case syncRequestedHintConsumed
    case eventTriggerQueued
    case eventTriggerCoalesced
    case eventToSyncStartLatencyMs
    case peerProofUnavailable
    case finalizeProofAccepted
    case metadataOnlyRejectedAsAudioProof
    case completedLedgerRejectedAsPeerProof
    case partialReceiveRejectedAsCompleted
    case existingDifferentAudioConflict
    case uploadJobCreationDeniedByStatusTruth
    case diagnosticRedactionRejected
    case redactionViolationBlocked

    nonisolated var category: CanonicalKernelDiagnosticCategory {
        switch self {
        case .readProjectionRebuildDurationMs,
             .studyTreeRebuildDurationMs,
             .fileTreeSnapshotDurationMs,
             .manifestBuildDurationMs,
             .checksumCacheHit,
             .checksumCacheMiss,
             .checksumCacheStaleCount,
             .hashDurationMs,
             .mainActorLongTaskDurationMs,
             .routeDurationMs,
             .diagnosticsWriteDurationMs:
            return .performance
        case .statusFactProduced,
             .statusFactMerged,
             .statusDeltaSent,
             .statusDeltaReceived,
             .statusAckSent,
             .statusAckReceived,
             .statusRequestSent,
             .statusRequestReceived,
             .statusEnvelopeCarriedOverHeartbeat,
             .statusEnvelopeCarriedOverInventory,
             .fullInventoryRequested,
             .statusFactRejected,
             .statusProofExpired,
             .effectiveStatusProjected,
             .statusProjectionDurationMs,
             .mainActorStatusReconciliationAttemptCount,
             .syncRequestedHintAdvertised,
             .syncRequestedHintConsumed,
             .eventTriggerQueued,
             .eventTriggerCoalesced,
             .eventToSyncStartLatencyMs,
             .peerProofUnavailable,
             .finalizeProofAccepted,
             .metadataOnlyRejectedAsAudioProof,
             .completedLedgerRejectedAsPeerProof,
             .partialReceiveRejectedAsCompleted,
             .existingDifferentAudioConflict,
             .uploadJobCreationDeniedByStatusTruth:
            return .convergence
        case .diagnosticRedactionRejected,
             .redactionViolationBlocked:
            return .redaction
        }
    }
}

nonisolated struct CanonicalKernelDiagnosticRecord: Codable, Equatable, Hashable, Sendable {
    var kind: CanonicalKernelDiagnosticEventKind
    var domain: CanonicalDomain
    var objectID: CanonicalObjectID?
    var durationMs: Int?
    var count: Int?
    var redactedDetail: String?

    nonisolated init(
        kind: CanonicalKernelDiagnosticEventKind,
        domain: CanonicalDomain,
        objectID: CanonicalObjectID? = nil,
        durationMs: Int? = nil,
        count: Int? = nil,
        redactedDetail: String? = nil
    ) {
        self.kind = kind
        self.domain = domain
        self.objectID = objectID
        self.durationMs = durationMs.map { max(0, $0) }
        self.count = count.map { max(0, $0) }
        self.redactedDetail = CanonicalKernelStringSanitizer.optional(redactedDetail)
    }
}

nonisolated enum CanonicalDiagnosticForbiddenSignal: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case absolutePath
    case fullHash
    case secret
    case fullFingerprint
    case fullMetadataJSON
    case requestBody
    case responseBody
    case rawAudio
    case fullTranscript
    case fullNote
    case fullSummary
    case providerResponse
}

nonisolated enum CanonicalKernelDiagnosticRedaction {
    nonisolated static let forbiddenSignals: [CanonicalDiagnosticForbiddenSignal] = CanonicalDiagnosticForbiddenSignal.allCases

    nonisolated static func detectForbiddenSignals(in value: String) -> [CanonicalDiagnosticForbiddenSignal] {
        var signals: Set<CanonicalDiagnosticForbiddenSignal> = []
        let lowercased = value.lowercased()

        if containsAbsolutePathSignal(value) {
            signals.insert(.absolutePath)
        }
        if containsFullHash(value) {
            signals.insert(.fullHash)
        }
        if containsSecretSignal(lowercased) {
            signals.insert(.secret)
        }
        if containsFullFingerprint(value) || lowercased.contains("fingerprint=") {
            signals.insert(.fullFingerprint)
        }
        if lowercased.contains("\"metadata\"") && value.contains("{") && value.contains("}") {
            signals.insert(.fullMetadataJSON)
        }
        if lowercased.contains("requestbody") || lowercased.contains("request body") {
            signals.insert(.requestBody)
        }
        if lowercased.contains("responsebody") || lowercased.contains("response body") {
            signals.insert(.responseBody)
        }
        if lowercased.contains("raw audio") || lowercased.contains("audiobytes") || lowercased.contains("audio bytes") {
            signals.insert(.rawAudio)
        }
        if lowercased.contains("fulltranscript") || lowercased.contains("full transcript") {
            signals.insert(.fullTranscript)
        }
        if lowercased.contains("fullnote") || lowercased.contains("full note") {
            signals.insert(.fullNote)
        }
        if lowercased.contains("fullsummary") || lowercased.contains("full summary") {
            signals.insert(.fullSummary)
        }
        if lowercased.contains("providerresponse") || lowercased.contains("provider response") {
            signals.insert(.providerResponse)
        }

        return signals.sorted { $0.rawValue < $1.rawValue }
    }

    nonisolated static func isSafeForDiagnostics(_ value: String) -> Bool {
        detectForbiddenSignals(in: value).isEmpty
    }

    private nonisolated static func containsAbsolutePathSignal(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if lowercased.contains("file://") || lowercased.contains("c:\\") {
            return true
        }
        let prefixes = ["/users/", "/private/", "/volumes/", "/var/", "/tmp/"]
        return prefixes.contains { lowercased.contains($0) }
    }

    private nonisolated static func containsFullHash(_ value: String) -> Bool {
        value
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .contains { token in
                token.count >= 64 && token.unicodeScalars.allSatisfy { scalar in
                    CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
                }
            }
    }

    private nonisolated static func containsFullFingerprint(_ value: String) -> Bool {
        value
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .contains { token in
                let pairs = token.split(separator: ":")
                return pairs.count >= 16 && pairs.allSatisfy { pair in
                    pair.count == 2 && pair.unicodeScalars.allSatisfy { scalar in
                        CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
                    }
                }
            }
    }

    private nonisolated static func containsSecretSignal(_ lowercased: String) -> Bool {
        [
            "secret",
            "token=",
            "api_key",
            "apikey",
            "password",
            "privatekey",
            "private key",
            "-----begin"
        ].contains { lowercased.contains($0) }
    }
}
