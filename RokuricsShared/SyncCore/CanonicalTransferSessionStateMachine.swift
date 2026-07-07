//
//  CanonicalTransferSessionStateMachine.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalTransferRuntimeState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case idle
    case starting
    case started
    case chunking
    case interrupted
    case resuming
    case finalizing
    case finalized
    case failed
    case aborted
    case conflict
    case blocked
}

nonisolated enum CanonicalTransferChunkAcceptance: String, Codable, Equatable, Hashable, Sendable {
    case accepted
    case duplicateAccepted
    case statusRefreshRequired
}

nonisolated enum CanonicalTransferNoOverwriteDecision: String, Codable, Equatable, Hashable, Sendable {
    case missing
    case sameObjectNoOp
    case conflictNoOverwrite
}

nonisolated enum CanonicalTransferStateMachineError: Error, Equatable, Sendable {
    case confirmedBytesRegressed(previous: Int64, attempted: Int64)
    case invalidChunkLength(Int)
    case wrongOffsetRequiresStatusRefresh(expected: Int64, actual: Int64)
    case duplicateChunkMismatch(offset: Int64)
    case partialReceiveCannotFinalize(confirmedBytes: Int64, expectedBytes: Int64)
    case finalizeByteSizeMismatch(expected: Int64, actual: Int64)
    case missingFinalizeHashProof
    case finalizeHashMismatch(expectedPrefix: String, actualPrefix: String)
    case alreadyFinalized
    case abortedBeforeFinalize
    case existingDifferentObject
}

nonisolated struct CanonicalTransferChunkReceipt: Codable, Equatable, Hashable, Sendable {
    var offset: Int64
    var length: Int
    var chunkHash: CanonicalHash

    nonisolated init(offset: Int64, length: Int, chunkHash: CanonicalHash) {
        self.offset = max(0, offset)
        self.length = max(0, length)
        self.chunkHash = chunkHash
    }

    nonisolated var endOffset: Int64 {
        offset + Int64(length)
    }
}

nonisolated struct CanonicalTransferSessionStateMachine: Codable, Equatable, Sendable {
    var sessionID: CanonicalTransferSessionID
    var objectID: CanonicalObjectID
    var state: CanonicalTransferRuntimeState
    var confirmedBytes: Int64
    var expectedByteSize: Int64
    var expectedContentHash: CanonicalHash?
    var chunkSize: Int
    var receipts: [CanonicalTransferChunkReceipt]
    var lastError: String?

    nonisolated init(
        sessionID: CanonicalTransferSessionID,
        objectID: CanonicalObjectID,
        expectedByteSize: Int64,
        expectedContentHash: CanonicalHash? = nil,
        chunkSize: Int = 512 * 1024,
        state: CanonicalTransferRuntimeState = .idle,
        confirmedBytes: Int64 = 0,
        receipts: [CanonicalTransferChunkReceipt] = []
    ) {
        self.sessionID = sessionID
        self.objectID = objectID
        self.state = state
        self.confirmedBytes = max(0, confirmedBytes)
        self.expectedByteSize = max(0, expectedByteSize)
        self.expectedContentHash = expectedContentHash
        self.chunkSize = max(1, chunkSize)
        self.receipts = receipts.sorted { left, right in
            if left.offset != right.offset { return left.offset < right.offset }
            return left.length < right.length
        }
        self.lastError = nil
    }

    nonisolated var nextChunkOffset: Int64 {
        confirmedBytes
    }

    nonisolated var remainingBytes: Int64 {
        max(0, expectedByteSize - confirmedBytes)
    }

    nonisolated var nextChunkLength: Int {
        Int(min(Int64(chunkSize), remainingBytes))
    }

    nonisolated var partialReceiveWithoutFinalize: Bool {
        state != .finalized && confirmedBytes > 0 && confirmedBytes < expectedByteSize
    }

    nonisolated var finalized: Bool {
        state == .finalized
    }

    nonisolated mutating func beginStart() {
        guard state != .finalized else { return }
        state = .starting
        lastError = nil
    }

    nonisolated mutating func markStarted(confirmedBytes remoteConfirmedBytes: Int64 = 0) throws {
        try updateConfirmedBytes(remoteConfirmedBytes)
        state = confirmedBytes > 0 ? .chunking : .started
        lastError = nil
    }

    nonisolated mutating func interrupt(reason: String? = nil) {
        guard state != .finalized else { return }
        state = .interrupted
        lastError = CanonicalKernelStringSanitizer.optional(reason)
    }

    nonisolated mutating func block(reason: String) {
        guard state != .finalized else { return }
        state = .blocked
        lastError = CanonicalKernelStringSanitizer.required(reason, fallback: "blocked")
    }

    nonisolated mutating func abortLocalBeforeFinalize(reason: String? = nil) throws {
        guard state != .finalized else {
            throw CanonicalTransferStateMachineError.alreadyFinalized
        }
        state = .aborted
        lastError = CanonicalKernelStringSanitizer.optional(reason) ?? "localAbortBeforeFinalize"
    }

    @discardableResult
    nonisolated mutating func refreshStatus(confirmedBytes remoteConfirmedBytes: Int64) throws -> Int64 {
        state = .resuming
        try updateConfirmedBytes(remoteConfirmedBytes)
        if confirmedBytes >= expectedByteSize {
            state = .finalizing
        }
        return confirmedBytes
    }

    @discardableResult
    nonisolated mutating func acceptChunk(
        offset: Int64,
        length: Int,
        chunkHash: CanonicalHash,
        serverConfirmedBytes: Int64? = nil
    ) throws -> CanonicalTransferChunkAcceptance {
        guard length > 0 else {
            state = .failed
            lastError = "invalidChunkLength"
            throw CanonicalTransferStateMachineError.invalidChunkLength(length)
        }
        guard state != .aborted else {
            throw CanonicalTransferStateMachineError.abortedBeforeFinalize
        }
        guard state != .finalized else {
            throw CanonicalTransferStateMachineError.alreadyFinalized
        }

        let normalizedOffset = max(0, offset)
        let receipt = CanonicalTransferChunkReceipt(offset: normalizedOffset, length: length, chunkHash: chunkHash)
        if let existing = receipts.first(where: { $0.offset == normalizedOffset }) {
            guard existing.length == receipt.length, existing.chunkHash == receipt.chunkHash else {
                state = .conflict
                lastError = "duplicateChunkMismatch"
                throw CanonicalTransferStateMachineError.duplicateChunkMismatch(offset: normalizedOffset)
            }
            try updateConfirmedBytes(serverConfirmedBytes ?? max(confirmedBytes, existing.endOffset))
            state = confirmedBytes >= expectedByteSize ? .finalizing : .chunking
            return .duplicateAccepted
        }

        guard normalizedOffset == confirmedBytes else {
            state = .interrupted
            lastError = "wrongOffsetRequiresStatusRefresh"
            throw CanonicalTransferStateMachineError.wrongOffsetRequiresStatusRefresh(
                expected: confirmedBytes,
                actual: normalizedOffset
            )
        }

        receipts.append(receipt)
        receipts.sort { left, right in
            if left.offset != right.offset { return left.offset < right.offset }
            return left.length < right.length
        }
        try updateConfirmedBytes(serverConfirmedBytes ?? receipt.endOffset)
        state = confirmedBytes >= expectedByteSize ? .finalizing : .chunking
        lastError = nil
        return .accepted
    }

    nonisolated mutating func finalize(
        receiverNodeID: CanonicalNodeID,
        byteSize: Int64,
        contentHash: CanonicalHash?,
        manifestHash: CanonicalHash? = nil,
        finalizedAt: CanonicalTimestamp
    ) throws -> CanonicalTransferFinalizeProof {
        guard state != .aborted else {
            throw CanonicalTransferStateMachineError.abortedBeforeFinalize
        }
        guard confirmedBytes >= expectedByteSize else {
            state = .failed
            lastError = "partialReceiveCannotFinalize"
            throw CanonicalTransferStateMachineError.partialReceiveCannotFinalize(
                confirmedBytes: confirmedBytes,
                expectedBytes: expectedByteSize
            )
        }
        guard byteSize == expectedByteSize else {
            state = .conflict
            lastError = "finalizeByteSizeMismatch"
            throw CanonicalTransferStateMachineError.finalizeByteSizeMismatch(
                expected: expectedByteSize,
                actual: byteSize
            )
        }

        if let expectedContentHash, expectedContentHash.value.isEmpty == false {
            guard let contentHash else {
                state = .failed
                lastError = "missingFinalizeHashProof"
                throw CanonicalTransferStateMachineError.missingFinalizeHashProof
            }
            guard contentHash == expectedContentHash else {
                state = .conflict
                lastError = "finalizeHashMismatch"
                throw CanonicalTransferStateMachineError.finalizeHashMismatch(
                    expectedPrefix: Self.hashPrefix(expectedContentHash),
                    actualPrefix: Self.hashPrefix(contentHash)
                )
            }
        }

        let provenHash = contentHash ?? expectedContentHash ?? CanonicalHash("")
        state = .finalized
        lastError = nil
        return CanonicalTransferFinalizeProof(
            sessionID: sessionID,
            objectID: objectID,
            receiverNodeID: receiverNodeID,
            contentHash: provenHash,
            byteSize: byteSize,
            manifestHash: manifestHash,
            acceptedAt: finalizedAt,
            contentHashPrefix: Self.hashPrefix(provenHash),
            fullInternalHashProof: provenHash.value.isEmpty ? nil : provenHash,
            finalizedAt: finalizedAt,
            verified: provenHash.value.isEmpty == false || expectedContentHash == nil
        )
    }

    nonisolated mutating func validateNoOverwrite(
        existingByteSize: Int64?,
        existingContentHash: CanonicalHash?
    ) throws -> CanonicalTransferNoOverwriteDecision {
        guard let existingByteSize, let existingContentHash else {
            return .missing
        }
        if existingByteSize == expectedByteSize, existingContentHash == expectedContentHash {
            return .sameObjectNoOp
        }
        state = .conflict
        lastError = "existingDifferentObject"
        throw CanonicalTransferStateMachineError.existingDifferentObject
    }

    private nonisolated mutating func updateConfirmedBytes(_ attempted: Int64) throws {
        let normalized = max(0, min(attempted, expectedByteSize))
        guard normalized >= confirmedBytes else {
            state = .interrupted
            lastError = "confirmedBytesRegressed"
            throw CanonicalTransferStateMachineError.confirmedBytesRegressed(
                previous: confirmedBytes,
                attempted: normalized
            )
        }
        confirmedBytes = normalized
    }

    private nonisolated static func hashPrefix(_ hash: CanonicalHash) -> String {
        String(hash.value.prefix(12))
    }
}
