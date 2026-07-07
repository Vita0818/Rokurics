//
//  MacCanonicalProductionUploadPort.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/2.
//

import Foundation

actor MacCanonicalProductionUploadPort: CanonicalProductionUploadPort {
    nonisolated let isDryRunOnly: Bool
    nonisolated let resumableSessionSupported = true
    nonisolated let chunkSizePolicy: Int

    private let mode: Mode
    private var sessions: [CanonicalUploadSessionID: SessionState] = [:]
    private var ledgers: [String: CanonicalProductionUploadLedgerSnapshot] = [:]

    init(chunkSizePolicy: Int = 4 * 1024 * 1024) {
        self.mode = .disabled
        self.isDryRunOnly = true
        self.chunkSizePolicy = chunkSizePolicy
    }

    init(testOnlyChunkSizePolicy: Int = 4 * 1024 * 1024) {
        self.mode = .testOnlyInMemoryLedger
        self.isDryRunOnly = false
        self.chunkSizePolicy = testOnlyChunkSizePolicy
    }

    func startResumableUpload(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try requireTestOnlyInMemoryLedger()
        try validateStart(request)
        let sessionID = sessionID(for: request)
        if let existing = sessions[sessionID] {
            return status(for: existing, disposition: .acceptedExisting)
        }
        let state = SessionState(
            sessionID: sessionID,
            objectID: request.objectID,
            targetReference: request.targetReference,
            totalBytes: request.totalBytes,
            totalHash: request.totalHash,
            chunkSize: request.chunkSize,
            confirmedBytes: 0,
            buffer: Data(),
            chunks: [:],
            phase: .active
        )
        sessions[sessionID] = state
        ledgers[request.objectID] = CanonicalProductionUploadLedgerSnapshot(
            objectID: request.objectID,
            sessionID: sessionID,
            confirmedBytes: 0,
            totalBytes: request.totalBytes,
            contentHash: request.totalHash,
            phase: .active
        )
        return status(for: state, disposition: .acceptedNew)
    }

    func resumeUpload(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try requireTestOnlyInMemoryLedger()
        let state = try state(for: request.sessionID, objectID: request.objectID, totalHash: request.totalHash)
        return status(for: state, disposition: .resumed)
    }

    func uploadChunk(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus {
        try requireTestOnlyInMemoryLedger()
        var state = try state(for: chunk.sessionID, objectID: chunk.objectID, totalHash: chunk.totalHash)
        guard state.phase == .active || state.phase == .retryPending else {
            throw CanonicalUploadRuntimeError.invalidSession(chunk.sessionID.rawValue)
        }
        let actualChunkHash = InMemoryCanonicalFileStore.hash(chunk.bytes, policy: .sha256) ?? CanonicalHash.sha256String("")
        guard actualChunkHash == chunk.chunkHash else {
            throw CanonicalUploadRuntimeError.chunkHashMismatch(expected: chunk.chunkHash.value, actual: actualChunkHash.value)
        }
        if let existing = state.chunks[chunk.offset] {
            guard existing.length == chunk.bytes.count, existing.chunkHash == chunk.chunkHash else {
                throw CanonicalUploadRuntimeError.sessionConflict(chunk.sessionID.rawValue)
            }
            return status(for: state, disposition: .acceptedExisting)
        }
        guard chunk.offset == state.confirmedBytes else {
            throw CanonicalUploadRuntimeError.chunkOffsetMismatch(expected: state.confirmedBytes, actual: chunk.offset)
        }
        guard state.confirmedBytes + Int64(chunk.bytes.count) <= state.totalBytes else {
            throw CanonicalUploadRuntimeError.invalidRequest("chunkExceedsDeclaredSize")
        }
        state.buffer.append(chunk.bytes)
        state.chunks[chunk.offset] = ChunkRecord(length: chunk.bytes.count, chunkHash: chunk.chunkHash)
        state.confirmedBytes = Int64(state.buffer.count)
        state.phase = .active
        sessions[chunk.sessionID] = state
        ledgers[chunk.objectID] = CanonicalProductionUploadLedgerSnapshot(
            objectID: chunk.objectID,
            sessionID: chunk.sessionID,
            confirmedBytes: state.confirmedBytes,
            totalBytes: state.totalBytes,
            contentHash: state.totalHash,
            phase: state.phase
        )
        return status(for: state, disposition: .resumed)
    }

    func queryConfirmedBytes(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> Int64 {
        try await resumeUpload(request, now: now).confirmedBytes
    }

    func finalizeUpload(_ request: CanonicalUploadFinalizeRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try requireTestOnlyInMemoryLedger()
        var state = try state(for: request.sessionID, objectID: request.objectID, totalHash: request.totalHash)
        guard state.confirmedBytes == request.totalBytes, state.totalBytes == request.totalBytes else {
            throw CanonicalUploadRuntimeError.sessionIncomplete(confirmedBytes: state.confirmedBytes, totalBytes: request.totalBytes)
        }
        let actualHash = InMemoryCanonicalFileStore.hash(state.buffer, policy: .sha256) ?? CanonicalHash.sha256String("")
        guard actualHash == request.totalHash else {
            throw CanonicalUploadRuntimeError.finalHashMismatch(expected: request.totalHash.value, actual: actualHash.value)
        }
        state.phase = .completed
        sessions[request.sessionID] = state
        ledgers[request.objectID] = CanonicalProductionUploadLedgerSnapshot(
            objectID: request.objectID,
            sessionID: request.sessionID,
            confirmedBytes: state.confirmedBytes,
            totalBytes: state.totalBytes,
            contentHash: state.totalHash,
            phase: .completed
        )
        return status(for: state, disposition: .finalized, completed: true)
    }

    func cancelUpload(_ request: CanonicalProductionUploadCancelRequest, now: Date) async throws -> CanonicalRollbackResult {
        try requireTestOnlyInMemoryLedger()
        if var state = sessions[request.sessionID] {
            state.phase = .failed
            sessions[request.sessionID] = state
            ledgers[request.objectID] = CanonicalProductionUploadLedgerSnapshot(
                objectID: request.objectID,
                sessionID: request.sessionID,
                confirmedBytes: state.confirmedBytes,
                totalBytes: state.totalBytes,
                contentHash: state.totalHash,
                phase: .failed
            )
        }
        return CanonicalRollbackResult(planID: request.sessionID.rawValue, succeeded: true, completedActionIDs: [request.sessionID.rawValue])
    }

    nonisolated func classifyUploadFailure(_ failure: CanonicalProductionUploadFailure) -> CanonicalProductionUploadFailureClassification {
        let code = failure.code.lowercased()
        if code.contains("conflict") || code == "409" {
            return CanonicalProductionUploadFailureClassification(kind: .conflict, retry: nil, reason: "macUploadConflict")
        }
        if code.contains("timeout") || code.contains("network") || code.contains("retry") {
            return CanonicalProductionUploadFailureClassification(
                kind: .retryable,
                retry: CanonicalRetryPolicySnapshot(retryCount: 1, nextRetryAt: nil, maxAttempts: 3),
                reason: "macUploadRetryable"
            )
        }
        return CanonicalProductionUploadFailureClassification(kind: .fatal, retry: nil, reason: failure.code)
    }

    func readUploadLedger(objectID: String) async throws -> CanonicalProductionUploadLedgerSnapshot {
        ledgers[CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")]
            ?? CanonicalProductionUploadLedgerSnapshot(objectID: objectID)
    }

    func writeUploadLedger(_ snapshot: CanonicalProductionUploadLedgerSnapshot) async throws -> CanonicalProductionUploadLedgerSnapshot {
        try requireTestOnlyInMemoryLedger()
        ledgers[snapshot.objectID] = snapshot
        return snapshot
    }

    nonisolated func projectRetry(_ snapshot: CanonicalProductionUploadLedgerSnapshot, now: Date) -> CanonicalRetryPolicySnapshot? {
        if let retry = snapshot.retry {
            return retry
        }
        guard snapshot.phase == .retryPending || snapshot.phase == .failed else {
            return nil
        }
        return CanonicalRetryPolicySnapshot(retryCount: 1, nextRetryAt: CanonicalTimestamp(now), maxAttempts: 3)
    }

    func rollbackUploadState(_ request: CanonicalProductionUploadRollbackRequest) async throws -> CanonicalRollbackResult {
        try requireTestOnlyInMemoryLedger()
        if let sessionID = request.sessionID {
            sessions.removeValue(forKey: sessionID)
        }
        ledgers[request.objectID] = CanonicalProductionUploadLedgerSnapshot(objectID: request.objectID)
        return CanonicalRollbackResult(planID: request.checkpointID, succeeded: true, completedActionIDs: [request.objectID])
    }

    nonisolated func projectUploadDryRun(
        object: CanonicalRecordingObject,
        artifact: CanonicalArtifact
    ) async throws -> CanonicalProductionUploadTrace {
        guard artifact.kind == .audio else {
            throw CanonicalProductionPortError.unsupportedObject("macUploadOnlySupportsAudio")
        }
        return CanonicalProductionUploadTrace(
            objectID: object.objectID,
            artifactID: artifact.artifactID,
            totalBytes: artifact.byteSize,
            totalHash: artifact.contentHash,
            chunkSize: chunkSizePolicy,
            resumable: true,
            route: .uploadStart,
            reason: isDryRunOnly ? "macProductionUploadDisabled" : "macTestOnlyUploadProjected"
        )
    }

    private enum Mode: Sendable {
        case disabled
        case testOnlyInMemoryLedger
    }

    private struct SessionState: Sendable {
        var sessionID: CanonicalUploadSessionID
        var objectID: String
        var targetReference: CanonicalFileReference
        var totalBytes: Int64
        var totalHash: CanonicalHash
        var chunkSize: Int
        var confirmedBytes: Int64
        var buffer: Data
        var chunks: [Int64: ChunkRecord]
        var phase: CanonicalUploadSessionPhase
    }

    private struct ChunkRecord: Sendable {
        var length: Int
        var chunkHash: CanonicalHash
    }

    private func requireTestOnlyInMemoryLedger() throws {
        guard mode == .testOnlyInMemoryLedger else {
            throw CanonicalProductionPortError.productionMutationAttempted("macProductionUploadDisabled")
        }
    }

    private func validateStart(_ request: CanonicalUploadStartRequest) throws {
        guard request.totalBytes >= 0 else {
            throw CanonicalUploadRuntimeError.invalidRequest("negativeTotalBytes")
        }
        guard request.chunkSize > 0 else {
            throw CanonicalUploadRuntimeError.invalidRequest("invalidChunkSize")
        }
        guard request.chunkSize <= chunkSizePolicy else {
            throw CanonicalUploadRuntimeError.invalidRequest("chunkSizeExceedsPolicy")
        }
    }

    private func state(
        for sessionID: CanonicalUploadSessionID,
        objectID: String,
        totalHash: CanonicalHash
    ) throws -> SessionState {
        guard let state = sessions[sessionID] else {
            throw CanonicalUploadRuntimeError.sessionMissing(sessionID.rawValue)
        }
        guard state.objectID == objectID, state.totalHash == totalHash else {
            throw CanonicalUploadRuntimeError.sessionConflict(sessionID.rawValue)
        }
        return state
    }

    private func sessionID(for request: CanonicalUploadStartRequest) -> CanonicalUploadSessionID {
        CanonicalUploadSessionID("mac-\(request.objectID)-\(String(request.totalHash.value.prefix(12)))")
    }

    private func status(
        for state: SessionState,
        disposition: CanonicalUploadDisposition,
        completed: Bool = false
    ) -> CanonicalUploadSessionStatus {
        CanonicalUploadSessionStatus(
            ok: true,
            disposition: disposition,
            phase: completed ? .completed : state.phase,
            sessionID: state.sessionID,
            confirmedBytes: state.confirmedBytes,
            nextOffset: state.confirmedBytes,
            chunkSize: state.chunkSize,
            completed: completed,
            finalFile: completed ? state.targetReference : nil,
            checksum: completed ? state.totalHash : nil,
            fileSize: completed ? state.totalBytes : nil,
            retry: nil,
            error: nil
        )
    }
}
