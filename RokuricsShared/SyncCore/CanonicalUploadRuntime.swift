//
//  CanonicalUploadRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct CanonicalUploadSessionID: Codable, Equatable, Hashable, Sendable {
    var rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "upload-session:unknown"
    }
}

nonisolated enum CanonicalUploadDisposition: String, Codable, Equatable, Sendable {
    case acceptedNew
    case acceptedExisting
    case resumed
    case finalized
}

nonisolated enum CanonicalUploadSessionPhase: String, Codable, Equatable, Sendable {
    case active
    case retryPending
    case finalizing
    case completed
    case conflict
    case failed
}

nonisolated struct CanonicalUploadRetryPolicy: Codable, Equatable, Sendable {
    var maxAttempts: Int
    var retryDelaySeconds: TimeInterval

    nonisolated init(maxAttempts: Int = 3, retryDelaySeconds: TimeInterval = 5) {
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelaySeconds = max(0, retryDelaySeconds)
    }
}

nonisolated struct CanonicalUploadChunkRecord: Codable, Equatable, Sendable {
    var offset: Int64
    var length: Int
    var sha256: CanonicalHash
}

nonisolated struct CanonicalUploadSession: Codable, Equatable, Sendable {
    var sessionID: CanonicalUploadSessionID
    var objectID: String
    var targetReference: CanonicalFileReference
    var totalBytes: Int64
    var totalHash: CanonicalHash
    var chunkSize: Int
    var confirmedBytes: Int64
    var chunks: [CanonicalUploadChunkRecord]
    var phase: CanonicalUploadSessionPhase
    var retryCount: Int
    var nextRetryAt: CanonicalTimestamp?
    var createdAt: CanonicalTimestamp
    var updatedAt: CanonicalTimestamp
    var finalizedAt: CanonicalTimestamp?
    var lastError: String?
}

nonisolated struct CanonicalUploadStartRequest: Codable, Equatable, Sendable {
    var objectID: String
    var targetReference: CanonicalFileReference
    var totalBytes: Int64
    var totalHash: CanonicalHash
    var chunkSize: Int
    var idempotencyKey: String?

    nonisolated init(
        objectID: String,
        targetReference: CanonicalFileReference,
        totalBytes: Int64,
        totalHash: CanonicalHash,
        chunkSize: Int,
        idempotencyKey: String? = nil
    ) {
        self.objectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown-recording"
        self.targetReference = targetReference
        self.totalBytes = totalBytes
        self.totalHash = totalHash
        self.chunkSize = chunkSize
        self.idempotencyKey = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

nonisolated struct CanonicalUploadStatusRequest: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID
    var totalHash: CanonicalHash
}

nonisolated struct CanonicalUploadChunk: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID
    var offset: Int64
    var bytes: Data
    var chunkHash: CanonicalHash
    var totalHash: CanonicalHash
    var idempotencyKey: String?

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID,
        offset: Int64,
        bytes: Data,
        chunkHash: CanonicalHash,
        totalHash: CanonicalHash,
        idempotencyKey: String? = nil
    ) {
        self.objectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown-recording"
        self.sessionID = sessionID
        self.offset = offset
        self.bytes = bytes
        self.chunkHash = chunkHash
        self.totalHash = totalHash
        self.idempotencyKey = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

nonisolated struct CanonicalUploadFinalizeRequest: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID
    var totalBytes: Int64
    var totalHash: CanonicalHash
}

nonisolated struct CanonicalUploadSessionStatus: Codable, Equatable, Sendable {
    var ok: Bool
    var disposition: CanonicalUploadDisposition?
    var phase: CanonicalUploadSessionPhase
    var sessionID: CanonicalUploadSessionID?
    var confirmedBytes: Int64
    var nextOffset: Int64
    var chunkSize: Int?
    var completed: Bool
    var finalFile: CanonicalFileReference?
    var checksum: CanonicalHash?
    var fileSize: Int64?
    var retry: CanonicalRetryPolicySnapshot?
    var error: String?
}

nonisolated struct CanonicalUploadResumeState: Codable, Equatable, Sendable {
    var sessionID: CanonicalUploadSessionID
    var confirmedBytes: Int64
    var nextOffset: Int64
    var totalBytes: Int64
    var totalHash: CanonicalHash
    var chunkSize: Int
    var phase: CanonicalUploadSessionPhase
}

nonisolated enum CanonicalUploadRuntimeError: Error, Equatable, Sendable {
    case invalidRequest(String)
    case invalidSession(String)
    case sessionMissing(String)
    case sessionConflict(String)
    case chunkOffsetMismatch(expected: Int64, actual: Int64)
    case chunkHashMismatch(expected: String, actual: String)
    case sessionIncomplete(confirmedBytes: Int64, totalBytes: Int64)
    case finalHashMismatch(expected: String, actual: String)
    case targetConflict(String)
    case retryLimitExceeded(String)
}

nonisolated protocol CanonicalUploadRuntimePort: Sendable {
    func start(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus
    func status(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus
    func append(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus
    func finalize(_ request: CanonicalUploadFinalizeRequest, now: Date) async throws -> CanonicalUploadSessionStatus
}

actor CanonicalResumableUploadRuntime: CanonicalUploadRuntimePort {
    private struct SessionState: Sendable {
        var session: CanonicalUploadSession
        var buffer: Data
        var idempotencyResponses: [String: CanonicalUploadSessionStatus]
    }

    private let fileStore: any CanonicalFileStorePort
    private let retryPolicy: CanonicalUploadRetryPolicy
    private var sessions: [CanonicalUploadSessionID: SessionState] = [:]

    init(fileStore: any CanonicalFileStorePort, retryPolicy: CanonicalUploadRetryPolicy = CanonicalUploadRetryPolicy()) {
        self.fileStore = fileStore
        self.retryPolicy = retryPolicy
    }

    func start(_ request: CanonicalUploadStartRequest, now: Date = Date()) async throws -> CanonicalUploadSessionStatus {
        try validateStart(request)
        if let completed = try await completedStatusIfPresent(request: request) {
            return completed
        }

        let sessionID = makeSessionID(request)
        if let existing = sessions[sessionID] {
            guard existing.session.objectID == request.objectID,
                  sameHash(existing.session.totalHash, request.totalHash),
                  existing.session.totalBytes == request.totalBytes,
                  existing.session.chunkSize == request.chunkSize else {
                throw CanonicalUploadRuntimeError.sessionConflict(sessionID.rawValue)
            }
            return status(for: existing.session, disposition: .acceptedExisting)
        }

        let session = CanonicalUploadSession(
            sessionID: sessionID,
            objectID: request.objectID,
            targetReference: request.targetReference,
            totalBytes: request.totalBytes,
            totalHash: request.totalHash,
            chunkSize: request.chunkSize,
            confirmedBytes: 0,
            chunks: [],
            phase: .active,
            retryCount: 0,
            nextRetryAt: nil,
            createdAt: CanonicalTimestamp(now),
            updatedAt: CanonicalTimestamp(now),
            finalizedAt: nil,
            lastError: nil
        )
        sessions[sessionID] = SessionState(session: session, buffer: Data(), idempotencyResponses: [:])
        return status(for: session, disposition: .acceptedNew)
    }

    func status(_ request: CanonicalUploadStatusRequest, now: Date = Date()) async throws -> CanonicalUploadSessionStatus {
        guard let state = sessions[request.sessionID] else {
            throw CanonicalUploadRuntimeError.sessionMissing(request.sessionID.rawValue)
        }
        guard state.session.objectID == request.objectID,
              sameHash(state.session.totalHash, request.totalHash) else {
            throw CanonicalUploadRuntimeError.sessionConflict(request.sessionID.rawValue)
        }
        return status(for: state.session, disposition: .resumed)
    }

    func append(_ chunk: CanonicalUploadChunk, now: Date = Date()) async throws -> CanonicalUploadSessionStatus {
        guard var state = sessions[chunk.sessionID] else {
            throw CanonicalUploadRuntimeError.sessionMissing(chunk.sessionID.rawValue)
        }
        if let key = chunk.idempotencyKey,
           let response = state.idempotencyResponses[key] {
            return response
        }
        guard state.session.phase == .active || state.session.phase == .retryPending else {
            throw CanonicalUploadRuntimeError.sessionConflict(chunk.sessionID.rawValue)
        }
        guard state.session.objectID == chunk.objectID,
              sameHash(state.session.totalHash, chunk.totalHash) else {
            throw CanonicalUploadRuntimeError.sessionConflict(chunk.sessionID.rawValue)
        }
        let actualChunkHash = InMemoryCanonicalFileStore.hash(chunk.bytes, policy: .sha256) ?? CanonicalHash("")
        guard sameHash(actualChunkHash, chunk.chunkHash) else {
            state.session.phase = .conflict
            state.session.lastError = "chunkHashMismatch"
            sessions[chunk.sessionID] = state
            throw CanonicalUploadRuntimeError.chunkHashMismatch(expected: chunk.chunkHash.value, actual: actualChunkHash.value)
        }
        if let existing = state.session.chunks.first(where: { $0.offset == chunk.offset }) {
            guard existing.length == chunk.bytes.count,
                  sameHash(existing.sha256, chunk.chunkHash) else {
                state.session.phase = .conflict
                state.session.lastError = "chunkConflict"
                sessions[chunk.sessionID] = state
                throw CanonicalUploadRuntimeError.sessionConflict(chunk.sessionID.rawValue)
            }
            let response = status(for: state.session, disposition: .acceptedExisting)
            if let key = chunk.idempotencyKey {
                state.idempotencyResponses[key] = response
                sessions[chunk.sessionID] = state
            }
            return response
        }
        guard chunk.offset == state.session.confirmedBytes else {
            throw CanonicalUploadRuntimeError.chunkOffsetMismatch(expected: state.session.confirmedBytes, actual: chunk.offset)
        }
        guard state.session.confirmedBytes + Int64(chunk.bytes.count) <= state.session.totalBytes else {
            throw CanonicalUploadRuntimeError.sessionConflict(chunk.sessionID.rawValue)
        }

        state.buffer.append(chunk.bytes)
        state.session.confirmedBytes += Int64(chunk.bytes.count)
        state.session.chunks.append(
            CanonicalUploadChunkRecord(offset: chunk.offset, length: chunk.bytes.count, sha256: chunk.chunkHash)
        )
        state.session.phase = .active
        state.session.updatedAt = CanonicalTimestamp(now)
        state.session.lastError = nil

        let response = status(for: state.session, disposition: .acceptedNew)
        if let key = chunk.idempotencyKey {
            state.idempotencyResponses[key] = response
        }
        sessions[chunk.sessionID] = state
        return response
    }

    func finalize(_ request: CanonicalUploadFinalizeRequest, now: Date = Date()) async throws -> CanonicalUploadSessionStatus {
        guard var state = sessions[request.sessionID] else {
            throw CanonicalUploadRuntimeError.sessionMissing(request.sessionID.rawValue)
        }
        guard state.session.objectID == request.objectID,
              state.session.totalBytes == request.totalBytes,
              sameHash(state.session.totalHash, request.totalHash) else {
            throw CanonicalUploadRuntimeError.sessionConflict(request.sessionID.rawValue)
        }
        guard state.session.confirmedBytes == request.totalBytes else {
            throw CanonicalUploadRuntimeError.sessionIncomplete(
                confirmedBytes: state.session.confirmedBytes,
                totalBytes: request.totalBytes
            )
        }
        let actualHash = InMemoryCanonicalFileStore.hash(state.buffer, policy: .sha256) ?? CanonicalHash("")
        guard sameHash(actualHash, request.totalHash) else {
            state.session.phase = .conflict
            state.session.lastError = "finalHashMismatch"
            sessions[request.sessionID] = state
            throw CanonicalUploadRuntimeError.finalHashMismatch(expected: request.totalHash.value, actual: actualHash.value)
        }

        state.session.phase = .finalizing
        sessions[request.sessionID] = state
        do {
            _ = try await fileStore.write(
                CanonicalFileWriteIntent(
                    reference: state.session.targetReference,
                    bytes: state.buffer,
                    purpose: .artifactBytes,
                    expectedContentHash: request.totalHash,
                    expectedByteSize: request.totalBytes,
                    conflictPolicy: .idempotentIfSameContent
                )
            )
        } catch {
            state.session.phase = .conflict
            state.session.lastError = "targetConflict"
            sessions[request.sessionID] = state
            throw CanonicalUploadRuntimeError.targetConflict(request.objectID)
        }

        state.session.phase = .completed
        state.session.updatedAt = CanonicalTimestamp(now)
        state.session.finalizedAt = CanonicalTimestamp(now)
        state.session.lastError = nil
        sessions[request.sessionID] = state
        return status(for: state.session, disposition: .finalized)
    }

    func resumeState(sessionID: CanonicalUploadSessionID) async throws -> CanonicalUploadResumeState {
        guard let state = sessions[sessionID] else {
            throw CanonicalUploadRuntimeError.sessionMissing(sessionID.rawValue)
        }
        return CanonicalUploadResumeState(
            sessionID: state.session.sessionID,
            confirmedBytes: state.session.confirmedBytes,
            nextOffset: state.session.confirmedBytes,
            totalBytes: state.session.totalBytes,
            totalHash: state.session.totalHash,
            chunkSize: state.session.chunkSize,
            phase: state.session.phase
        )
    }

    @discardableResult
    func recordRetryableFailure(sessionID: CanonicalUploadSessionID, code: String, now: Date = Date()) async throws -> CanonicalUploadSessionStatus {
        guard var state = sessions[sessionID] else {
            throw CanonicalUploadRuntimeError.sessionMissing(sessionID.rawValue)
        }
        let nextRetryCount = state.session.retryCount + 1
        guard nextRetryCount <= retryPolicy.maxAttempts else {
            state.session.phase = .failed
            state.session.lastError = code
            sessions[sessionID] = state
            throw CanonicalUploadRuntimeError.retryLimitExceeded(sessionID.rawValue)
        }
        state.session.retryCount = nextRetryCount
        state.session.phase = .retryPending
        state.session.lastError = code.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "retryableFailure"
        state.session.nextRetryAt = CanonicalTimestamp(now.addingTimeInterval(retryPolicy.retryDelaySeconds))
        state.session.updatedAt = CanonicalTimestamp(now)
        sessions[sessionID] = state
        return status(for: state.session, disposition: .resumed)
    }

    func retryDriveSnapshot(sessionID: CanonicalUploadSessionID) async throws -> CanonicalRetryPolicySnapshot {
        guard let state = sessions[sessionID] else {
            throw CanonicalUploadRuntimeError.sessionMissing(sessionID.rawValue)
        }
        return CanonicalRetryPolicySnapshot(
            retryCount: state.session.retryCount,
            nextRetryAt: state.session.nextRetryAt,
            maxAttempts: retryPolicy.maxAttempts
        )
    }

    private func completedStatusIfPresent(request: CanonicalUploadStartRequest) async throws -> CanonicalUploadSessionStatus? {
        do {
            let read = try await fileStore.read(CanonicalFileReadRequest(reference: request.targetReference))
            guard read.byteSize == request.totalBytes,
                  let checksum = read.contentHash,
                  sameHash(checksum, request.totalHash) else {
                throw CanonicalUploadRuntimeError.targetConflict(request.objectID)
            }
            return CanonicalUploadSessionStatus(
                ok: true,
                disposition: .acceptedExisting,
                phase: .completed,
                sessionID: nil,
                confirmedBytes: request.totalBytes,
                nextOffset: request.totalBytes,
                chunkSize: nil,
                completed: true,
                finalFile: request.targetReference,
                checksum: checksum,
                fileSize: request.totalBytes,
                retry: nil,
                error: nil
            )
        } catch CanonicalFileRuntimeError.fileNotFound(_) {
            return nil
        }
    }

    private func validateStart(_ request: CanonicalUploadStartRequest) throws {
        guard request.totalBytes > 0, request.chunkSize > 0 else {
            throw CanonicalUploadRuntimeError.invalidRequest(request.objectID)
        }
    }

    private func status(for session: CanonicalUploadSession, disposition: CanonicalUploadDisposition?) -> CanonicalUploadSessionStatus {
        CanonicalUploadSessionStatus(
            ok: true,
            disposition: disposition,
            phase: session.phase,
            sessionID: session.sessionID,
            confirmedBytes: session.confirmedBytes,
            nextOffset: session.confirmedBytes,
            chunkSize: session.chunkSize,
            completed: session.phase == .completed,
            finalFile: session.phase == .completed ? session.targetReference : nil,
            checksum: session.phase == .completed ? session.totalHash : nil,
            fileSize: session.phase == .completed ? session.totalBytes : nil,
            retry: session.phase == .retryPending
                ? CanonicalRetryPolicySnapshot(retryCount: session.retryCount, nextRetryAt: session.nextRetryAt, maxAttempts: retryPolicy.maxAttempts)
                : nil,
            error: session.lastError
        )
    }

    private func makeSessionID(_ request: CanonicalUploadStartRequest) -> CanonicalUploadSessionID {
        let raw = "\(request.objectID)|\(request.targetReference.rootToken.rawValue)|\(request.targetReference.logicalPathToken)|\(request.totalHash.value)"
        let digest = CanonicalHash.sha256String(raw).value
        return CanonicalUploadSessionID("\(request.objectID)-\(String(digest.prefix(16)))")
    }

    private nonisolated func sameHash(_ left: CanonicalHash, _ right: CanonicalHash) -> Bool {
        left.algorithm == right.algorithm && left.value == right.value
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
