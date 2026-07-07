//
//  CanonicalTransferProof.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated struct CanonicalTransferFinalizeProofSnapshot: Codable, Equatable, Hashable, Sendable {
    var receiverNodeID: CanonicalNodeID
    var sessionID: CanonicalTransferSessionID
    var objectID: CanonicalObjectID
    var byteSize: Int64
    var contentHashPrefix: String
    var finalizedAt: CanonicalTimestamp
    var verified: Bool

    nonisolated init(proof: CanonicalTransferFinalizeProof) {
        self.receiverNodeID = proof.receiverNodeID
        self.sessionID = proof.sessionID
        self.objectID = proof.objectID
        self.byteSize = proof.byteSize
        self.contentHashPrefix = CanonicalTransferProofRedaction.hashPrefix(proof.contentHash.value)
        self.finalizedAt = proof.finalizedAt
        self.verified = proof.verified
    }
}

nonisolated enum CanonicalTransferProofRedaction {
    nonisolated static func hashPrefix(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return String(trimmed.prefix(12))
    }

    nonisolated static func safeProofSummary(_ proof: CanonicalTransferFinalizeProof) -> String {
        [
            "receiver=\(proof.receiverNodeID.rawValue)",
            "session=\(proof.sessionID.rawValue)",
            "object=\(proof.objectID.rawValue)",
            "byteSize=\(proof.byteSize)",
            "hashPrefix=\(hashPrefix(proof.contentHash.value))",
            "verified=\(proof.verified)"
        ].joined(separator: ",")
    }
}

extension CanonicalTransferFinalizeProof {
    nonisolated static func v930(
        receiverNodeID: CanonicalNodeID,
        sessionID: CanonicalTransferSessionID,
        objectID: CanonicalObjectID,
        byteSize: Int64,
        contentHash: CanonicalHash,
        manifestHash: CanonicalHash? = nil,
        finalizedAt: CanonicalTimestamp,
        verified: Bool = true
    ) -> CanonicalTransferFinalizeProof {
        CanonicalTransferFinalizeProof(
            sessionID: sessionID,
            objectID: objectID,
            receiverNodeID: receiverNodeID,
            contentHash: contentHash,
            byteSize: byteSize,
            manifestHash: manifestHash,
            acceptedAt: finalizedAt,
            contentHashPrefix: CanonicalTransferProofRedaction.hashPrefix(contentHash.value),
            fullInternalHashProof: contentHash,
            finalizedAt: finalizedAt,
            verified: verified
        )
    }

    nonisolated var diagnosticSnapshot: CanonicalTransferFinalizeProofSnapshot {
        CanonicalTransferFinalizeProofSnapshot(proof: self)
    }

    nonisolated var isV930VerifiedFinalizeProof: Bool {
        verified
            && byteSize >= 0
            && contentHash.value.isEmpty == false
            && CanonicalTransferProofRedaction.hashPrefix(contentHash.value) == contentHashPrefix
    }
}
