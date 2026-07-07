//
//  CanonicalTransferProtocol.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated struct CanonicalTransferSessionID: Codable, Equatable, Hashable, Comparable, Sendable {
    var rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = CanonicalKernelStringSanitizer.required(rawValue, fallback: "transfer-session")
    }

    nonisolated static func < (left: CanonicalTransferSessionID, right: CanonicalTransferSessionID) -> Bool {
        left.rawValue < right.rawValue
    }
}

nonisolated struct CanonicalTransferStartRequest: Codable, Equatable, Hashable, Sendable {
    var objectID: CanonicalObjectID
    var sourceNodeID: CanonicalNodeID
    var destinationNodeID: CanonicalNodeID
    var contentHash: CanonicalHash
    var byteSize: Int64
    var manifestHash: CanonicalHash?
    var preferredChunkSize: Int
    var requestedAt: CanonicalTimestamp

    nonisolated init(
        objectID: CanonicalObjectID,
        sourceNodeID: CanonicalNodeID,
        destinationNodeID: CanonicalNodeID,
        contentHash: CanonicalHash,
        byteSize: Int64,
        manifestHash: CanonicalHash? = nil,
        preferredChunkSize: Int = 512 * 1024,
        requestedAt: CanonicalTimestamp
    ) {
        self.objectID = objectID
        self.sourceNodeID = sourceNodeID
        self.destinationNodeID = destinationNodeID
        self.contentHash = contentHash
        self.byteSize = max(0, byteSize)
        self.manifestHash = manifestHash
        self.preferredChunkSize = max(1, preferredChunkSize)
        self.requestedAt = requestedAt
    }
}

nonisolated enum CanonicalTransferSessionState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case idle
    case starting
    case started
    case chunking
    case requested
    case accepted
    case receiving
    case interrupted
    case resuming
    case retryScheduled
    case finalizing
    case finalized
    case rejected
    case failed
    case aborted
    case conflict
    case blocked
}

nonisolated struct CanonicalTransferSession: Codable, Equatable, Hashable, Sendable {
    var sessionID: CanonicalTransferSessionID
    var request: CanonicalTransferStartRequest
    var state: CanonicalTransferSessionState
    var acceptedOffset: Int64
    var createdAt: CanonicalTimestamp
    var updatedAt: CanonicalTimestamp

    nonisolated init(
        sessionID: CanonicalTransferSessionID,
        request: CanonicalTransferStartRequest,
        state: CanonicalTransferSessionState,
        acceptedOffset: Int64 = 0,
        createdAt: CanonicalTimestamp,
        updatedAt: CanonicalTimestamp
    ) {
        self.sessionID = sessionID
        self.request = request
        self.state = state
        self.acceptedOffset = max(0, acceptedOffset)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

nonisolated struct CanonicalTransferStatus: Codable, Equatable, Hashable, Sendable {
    var sessionID: CanonicalTransferSessionID
    var objectID: CanonicalObjectID
    var state: CanonicalTransferSessionState
    var acceptedOffset: Int64
    var totalBytes: Int64
    var retryRecord: CanonicalTransferRetryRecord?
    var finalizeProof: CanonicalTransferFinalizeProof?

    nonisolated init(
        sessionID: CanonicalTransferSessionID,
        objectID: CanonicalObjectID,
        state: CanonicalTransferSessionState,
        acceptedOffset: Int64,
        totalBytes: Int64,
        retryRecord: CanonicalTransferRetryRecord? = nil,
        finalizeProof: CanonicalTransferFinalizeProof? = nil
    ) {
        self.sessionID = sessionID
        self.objectID = objectID
        self.state = state
        self.acceptedOffset = max(0, acceptedOffset)
        self.totalBytes = max(0, totalBytes)
        self.retryRecord = retryRecord
        self.finalizeProof = finalizeProof
    }
}

nonisolated struct CanonicalTransferChunk: Codable, Equatable, Hashable, Sendable {
    var sessionID: CanonicalTransferSessionID
    var sequence: CanonicalSequence
    var offset: Int64
    var bytes: Data
    var chunkHash: CanonicalHash

    nonisolated init(
        sessionID: CanonicalTransferSessionID,
        sequence: CanonicalSequence,
        offset: Int64,
        bytes: Data,
        chunkHash: CanonicalHash
    ) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.offset = max(0, offset)
        self.bytes = bytes
        self.chunkHash = chunkHash
    }
}

nonisolated struct CanonicalTransferChunkAck: Codable, Equatable, Hashable, Sendable {
    var sessionID: CanonicalTransferSessionID
    var sequence: CanonicalSequence
    var acceptedOffset: Int64
    var acceptedBytes: Int64
    var acknowledgedAt: CanonicalTimestamp

    nonisolated init(
        sessionID: CanonicalTransferSessionID,
        sequence: CanonicalSequence,
        acceptedOffset: Int64,
        acceptedBytes: Int64,
        acknowledgedAt: CanonicalTimestamp
    ) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.acceptedOffset = max(0, acceptedOffset)
        self.acceptedBytes = max(0, acceptedBytes)
        self.acknowledgedAt = acknowledgedAt
    }
}

nonisolated struct CanonicalTransferFinalizeRequest: Codable, Equatable, Hashable, Sendable {
    var sessionID: CanonicalTransferSessionID
    var objectID: CanonicalObjectID
    var contentHash: CanonicalHash
    var byteSize: Int64
    var manifestHash: CanonicalHash?
    var requestedAt: CanonicalTimestamp

    nonisolated init(
        sessionID: CanonicalTransferSessionID,
        objectID: CanonicalObjectID,
        contentHash: CanonicalHash,
        byteSize: Int64,
        manifestHash: CanonicalHash? = nil,
        requestedAt: CanonicalTimestamp
    ) {
        self.sessionID = sessionID
        self.objectID = objectID
        self.contentHash = contentHash
        self.byteSize = max(0, byteSize)
        self.manifestHash = manifestHash
        self.requestedAt = requestedAt
    }
}

nonisolated struct CanonicalTransferFinalizeProof: Codable, Equatable, Hashable, Sendable {
    var sessionID: CanonicalTransferSessionID
    var objectID: CanonicalObjectID
    var receiverNodeID: CanonicalNodeID
    var contentHash: CanonicalHash
    var byteSize: Int64
    var manifestHash: CanonicalHash?
    var acceptedAt: CanonicalTimestamp
    var contentHashPrefix: String
    var fullInternalHashProof: CanonicalHash?
    var finalizedAt: CanonicalTimestamp
    var verified: Bool

    nonisolated init(
        sessionID: CanonicalTransferSessionID,
        objectID: CanonicalObjectID,
        receiverNodeID: CanonicalNodeID,
        contentHash: CanonicalHash,
        byteSize: Int64,
        manifestHash: CanonicalHash? = nil,
        acceptedAt: CanonicalTimestamp,
        contentHashPrefix: String? = nil,
        fullInternalHashProof: CanonicalHash? = nil,
        finalizedAt: CanonicalTimestamp? = nil,
        verified: Bool = true
    ) {
        self.sessionID = sessionID
        self.objectID = objectID
        self.receiverNodeID = receiverNodeID
        self.contentHash = contentHash
        self.byteSize = max(0, byteSize)
        self.manifestHash = manifestHash
        self.acceptedAt = acceptedAt
        self.contentHashPrefix = Self.safeHashPrefix(contentHashPrefix ?? contentHash.value)
        self.fullInternalHashProof = fullInternalHashProof ?? contentHash
        self.finalizedAt = finalizedAt ?? acceptedAt
        self.verified = verified
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(CanonicalTransferSessionID.self, forKey: .sessionID)
        objectID = try container.decode(CanonicalObjectID.self, forKey: .objectID)
        receiverNodeID = try container.decode(CanonicalNodeID.self, forKey: .receiverNodeID)
        contentHash = try container.decode(CanonicalHash.self, forKey: .contentHash)
        byteSize = max(0, try container.decode(Int64.self, forKey: .byteSize))
        manifestHash = try container.decodeIfPresent(CanonicalHash.self, forKey: .manifestHash)
        acceptedAt = try container.decode(CanonicalTimestamp.self, forKey: .acceptedAt)
        contentHashPrefix = Self.safeHashPrefix(
            try container.decodeIfPresent(String.self, forKey: .contentHashPrefix) ?? contentHash.value
        )
        fullInternalHashProof = try container.decodeIfPresent(CanonicalHash.self, forKey: .fullInternalHashProof)
            ?? contentHash
        finalizedAt = try container.decodeIfPresent(CanonicalTimestamp.self, forKey: .finalizedAt) ?? acceptedAt
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified)
            ?? (byteSize >= 0 && contentHash.value.isEmpty == false)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(objectID, forKey: .objectID)
        try container.encode(receiverNodeID, forKey: .receiverNodeID)
        try container.encode(contentHash, forKey: .contentHash)
        try container.encode(byteSize, forKey: .byteSize)
        try container.encodeIfPresent(manifestHash, forKey: .manifestHash)
        try container.encode(acceptedAt, forKey: .acceptedAt)
        try container.encode(contentHashPrefix, forKey: .contentHashPrefix)
        try container.encodeIfPresent(fullInternalHashProof, forKey: .fullInternalHashProof)
        try container.encode(finalizedAt, forKey: .finalizedAt)
        try container.encode(verified, forKey: .verified)
    }

    nonisolated var isReceiverAcceptedProof: Bool {
        byteSize >= 0 && contentHash.value.isEmpty == false && verified
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case objectID
        case receiverNodeID
        case contentHash
        case byteSize
        case manifestHash
        case acceptedAt
        case contentHashPrefix
        case fullInternalHashProof
        case finalizedAt
        case verified
    }

    private nonisolated static func safeHashPrefix(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.isEmpty == false else { return "" }
        return String(trimmed.prefix(12))
    }
}

nonisolated struct CanonicalTransferRetryPolicy: Codable, Equatable, Hashable, Sendable {
    var maxAttempts: Int
    var baseDelayMs: Int
    var maxDelayMs: Int
    var jitterEnabled: Bool

    nonisolated init(
        maxAttempts: Int = 5,
        baseDelayMs: Int = 500,
        maxDelayMs: Int = 60_000,
        jitterEnabled: Bool = true
    ) {
        self.maxAttempts = max(0, maxAttempts)
        self.baseDelayMs = max(0, baseDelayMs)
        self.maxDelayMs = max(baseDelayMs, maxDelayMs)
        self.jitterEnabled = jitterEnabled
    }
}

nonisolated struct CanonicalTransferRetryRecord: Codable, Equatable, Hashable, Sendable {
    var sessionID: CanonicalTransferSessionID
    var attempt: Int
    var nextEligibleAt: CanonicalTimestamp
    var resumeOffset: Int64
    var reason: String

    nonisolated init(
        sessionID: CanonicalTransferSessionID,
        attempt: Int,
        nextEligibleAt: CanonicalTimestamp,
        resumeOffset: Int64,
        reason: String
    ) {
        self.sessionID = sessionID
        self.attempt = max(0, attempt)
        self.nextEligibleAt = nextEligibleAt
        self.resumeOffset = max(0, resumeOffset)
        self.reason = CanonicalKernelStringSanitizer.required(reason, fallback: "retry")
    }
}

nonisolated protocol CanonicalTransferPort: Sendable {
    func startTransfer(_ request: CanonicalTransferStartRequest) async throws -> CanonicalTransferSession
    func sendChunk(_ chunk: CanonicalTransferChunk) async throws -> CanonicalTransferChunkAck
    func finalizeTransfer(_ request: CanonicalTransferFinalizeRequest) async throws -> CanonicalTransferFinalizeProof
    func transferStatus(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus
}

extension CanonicalTransferPort {
    func abortLocalBeforeFinalize(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        try await transferStatus(sessionID: sessionID)
    }
}

nonisolated enum CanonicalTransferProofRule {
    nonisolated static let finalizeProofIsReceiverAcceptedProof = true
    nonisolated static let completedLedgerAloneIsPeerProof = false
    nonisolated static let partialReceiveIsPeerAudioProof = false
}
