//
//  IPhoneCanonicalAudioUploadRuntimeAdapter.swift
//  Rokurics
//
//  Created by Codex on 2026/6/7.
//

import Foundation

actor IPhoneCanonicalSecureAudioUploadPort: CanonicalProductionUploadPort {
    nonisolated static let existingResumableRoutePaths = [
        "/upload-recording-audio-session/start",
        "/upload-recording-audio-session/status",
        "/upload-recording-audio-session/chunk",
        "/upload-recording-audio-session/finalize"
    ]

    nonisolated let isDryRunOnly = false
    nonisolated let resumableSessionSupported = true
    nonisolated let chunkSizePolicy: Int

    private let settings: SecureMacConnectionSnapshot
    private let transport: any RecordingSecureUploadTransport
    private var ledgers: [String: CanonicalProductionUploadLedgerSnapshot] = [:]

    init(
        settings: SecureMacConnectionSnapshot,
        transport: any RecordingSecureUploadTransport = SecureMacUploadClient(),
        chunkSizePolicy: Int = 4 * 1024 * 1024
    ) {
        self.settings = settings
        self.transport = transport
        self.chunkSizePolicy = max(1, chunkSizePolicy)
    }

    func startResumableUpload(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        let response = try await transport.startResumableAudioUpload(
            settings: settings,
            request: ResumableAudioUploadStartRequest(
                recordingID: request.objectID,
                fileName: Self.fileName(for: request),
                totalBytes: request.totalBytes,
                totalSHA256: request.totalHash.value,
                chunkSize: request.chunkSize,
                metadataHash: nil,
                uploadJobID: request.idempotencyKey
            )
        )
        let status = Self.status(from: response, fallbackObjectID: request.objectID)
        if let sessionID = status.sessionID {
            ledgers[request.objectID] = CanonicalProductionUploadLedgerSnapshot(
                objectID: request.objectID,
                sessionID: sessionID,
                confirmedBytes: status.confirmedBytes,
                totalBytes: request.totalBytes,
                contentHash: request.totalHash,
                phase: status.phase
            )
        }
        return status
    }

    func resumeUpload(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        let response = try await transport.fetchResumableAudioUploadStatus(
            settings: settings,
            request: ResumableAudioUploadStatusRequest(
                recordingID: request.objectID,
                sessionID: request.sessionID.rawValue,
                totalSHA256: request.totalHash.value
            )
        )
        return Self.status(from: response, fallbackObjectID: request.objectID)
    }

    func uploadChunk(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus {
        let response = try await transport.uploadResumableAudioChunk(
            settings: settings,
            recordingID: chunk.objectID,
            sessionID: chunk.sessionID.rawValue,
            offset: chunk.offset,
            totalSHA256: chunk.totalHash.value,
            chunk: chunk.bytes
        )
        return Self.status(from: response, fallbackObjectID: chunk.objectID)
    }

    func queryConfirmedBytes(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> Int64 {
        try await resumeUpload(request, now: now).confirmedBytes
    }

    func finalizeUpload(_ request: CanonicalUploadFinalizeRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        let response = try await transport.finalizeResumableAudioUpload(
            settings: settings,
            request: ResumableAudioUploadFinalizeRequest(
                recordingID: request.objectID,
                sessionID: request.sessionID.rawValue,
                totalBytes: request.totalBytes,
                totalSHA256: request.totalHash.value
            )
        )
        let status = Self.status(from: response, fallbackObjectID: request.objectID)
        if status.completed {
            ledgers[request.objectID] = CanonicalProductionUploadLedgerSnapshot(
                objectID: request.objectID,
                sessionID: request.sessionID,
                confirmedBytes: status.confirmedBytes,
                totalBytes: request.totalBytes,
                contentHash: request.totalHash,
                phase: .completed
            )
        }
        return status
    }

    func cancelUpload(_ request: CanonicalProductionUploadCancelRequest, now: Date) async throws -> CanonicalRollbackResult {
        // There is intentionally no production abort route in v8.41. Abort is local
        // pre-finalize state only; the Mac partial session cleanup remains server-owned.
        if var ledger = ledgers[request.objectID] {
            ledger.phase = .failed
            ledgers[request.objectID] = ledger
        }
        return CanonicalRollbackResult(
            planID: request.sessionID.rawValue,
            succeeded: true,
            completedActionIDs: []
        )
    }

    nonisolated func classifyUploadFailure(_ failure: CanonicalProductionUploadFailure) -> CanonicalProductionUploadFailureClassification {
        let code = failure.code.lowercased()
        if code.contains("conflict") || code.contains("mismatch") || code == "409" {
            return CanonicalProductionUploadFailureClassification(kind: .conflict, retry: nil, reason: "canonicalSecureUploadConflict")
        }
        if code.contains("offset") || code.contains("timeout") || code.contains("network") || code.contains("sessionmissing") {
            return CanonicalProductionUploadFailureClassification(
                kind: .retryable,
                retry: CanonicalRetryPolicySnapshot(retryCount: 1, nextRetryAt: nil, maxAttempts: 3),
                reason: "canonicalSecureUploadRetryable"
            )
        }
        return CanonicalProductionUploadFailureClassification(kind: .fatal, retry: nil, reason: failure.code)
    }

    func readUploadLedger(objectID: String) async throws -> CanonicalProductionUploadLedgerSnapshot {
        ledgers[CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")]
            ?? CanonicalProductionUploadLedgerSnapshot(objectID: objectID)
    }

    func writeUploadLedger(_ snapshot: CanonicalProductionUploadLedgerSnapshot) async throws -> CanonicalProductionUploadLedgerSnapshot {
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
        if let sessionID = request.sessionID,
           var ledger = ledgers[request.objectID],
           ledger.sessionID == sessionID {
            ledger.phase = .failed
            ledgers[request.objectID] = ledger
        }
        return CanonicalRollbackResult(planID: request.checkpointID, succeeded: true, completedActionIDs: [])
    }

    nonisolated func projectUploadDryRun(
        object: CanonicalRecordingObject,
        artifact: CanonicalArtifact
    ) async throws -> CanonicalProductionUploadTrace {
        guard artifact.kind == .audio else {
            throw CanonicalProductionPortError.unsupportedObject("iphoneSecureCanonicalUploadOnlySupportsAudio")
        }
        return CanonicalProductionUploadTrace(
            objectID: object.objectID,
            artifactID: artifact.artifactID,
            totalBytes: artifact.byteSize,
            totalHash: artifact.contentHash,
            chunkSize: chunkSizePolicy,
            resumable: true,
            route: .uploadStart,
            reason: "existingSecureUploadRoutesOnly"
        )
    }

    private nonisolated static func fileName(for request: CanonicalUploadStartRequest) -> String {
        let token = request.targetReference.logicalPathToken
        if let last = token.split(separator: "/").last, !last.isEmpty {
            return String(last)
        }
        return "\(request.objectID).m4a"
    }

    private nonisolated static func status(
        from response: ResumableAudioUploadSessionResponse,
        fallbackObjectID: String
    ) -> CanonicalUploadSessionStatus {
        let sessionID = response.sessionID.map(CanonicalUploadSessionID.init)
        let checksum = response.checksum
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { CanonicalHash($0) }
        let completed = response.completed || response.finalAudioExists == true
        let phase: CanonicalUploadSessionPhase
        if completed {
            phase = .completed
        } else {
            let status = response.status?.lowercased() ?? ""
            let reason = [response.error, response.reason].compactMap { $0?.lowercased() }.joined(separator: " ")
            if status.contains("conflict") || reason.contains("conflict") || reason.contains("mismatch") {
                phase = .conflict
            } else if status.contains("failed") || status.contains("error") || response.ok == false {
                phase = .failed
            } else {
                phase = .active
            }
        }
        return CanonicalUploadSessionStatus(
            ok: response.ok,
            disposition: response.disposition.flatMap(CanonicalUploadDisposition.init(rawValue:)),
            phase: phase,
            sessionID: sessionID,
            confirmedBytes: max(0, response.confirmedBytes),
            nextOffset: max(0, response.nextOffset),
            chunkSize: response.chunkSize,
            completed: completed,
            finalFile: nil,
            checksum: completed ? checksum : nil,
            fileSize: completed ? response.fileSize : nil,
            retry: nil,
            error: response.error ?? response.reason
        )
    }
}

struct IPhoneCanonicalAudioUploadFileSource: CanonicalAudioUploadByteSource {
    let objectID: String
    let targetReference: CanonicalFileReference
    let byteSize: Int64
    let contentHash: CanonicalHash
    let preferredChunkSize: Int

    private let fileURL: URL

    init(
        metadata: RecordingMetadata,
        audioFileStore: AudioFileStore = AudioFileStore(),
        preferredChunkSize: Int = 4 * 1024 * 1024,
        precomputedSignature: RecordingAudioSignature? = nil,
        canonicalChecksumRuntime: CanonicalChecksumRuntime? = nil
    ) async throws {
        let audioURL = try audioFileStore.audioURL(for: metadata)
        let size: Int64
        if let precomputedSize = precomputedSignature?.size {
            size = precomputedSize
        } else {
            size = try audioFileStore.fileSize(at: audioURL)
        }
        let hash: String
        if let precomputedHash = precomputedSignature?.normalizedSHA256 {
            hash = precomputedHash
        } else {
            let cacheDirectoryURL = try audioFileStore.baseDirectory()
                .appendingPathComponent("Sync", isDirectory: true)
                .appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
            let result = await (canonicalChecksumRuntime ?? CanonicalChecksumRuntime()).checksum(
                fileURL: audioURL,
                logicalToken: metadata.relativeAudioPath,
                nodeRole: .iPhone,
                cacheDirectoryURL: cacheDirectoryURL
            )
            guard let checksum = result.sha256 else {
                throw CanonicalAudioUploadRuntimeError.missingSource("checksumUnavailable")
            }
            hash = checksum
        }
        objectID = metadata.id
        targetReference = CanonicalFileReference(
            rootToken: CanonicalRootToken("iphone-audio-local"),
            logicalPathToken: metadata.relativeAudioPath,
            artifactID: CanonicalProjectionContract.artifactID(objectID: metadata.id, kind: .audio),
            artifactKind: .audio
        )
        byteSize = size
        contentHash = CanonicalHash(hash)
        self.preferredChunkSize = max(1, preferredChunkSize)
        fileURL = audioURL
    }

    func readChunk(offset: CanonicalAudioUploadOffset, maxLength: Int) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: UInt64(offset.value))
        return try handle.read(upToCount: max(1, maxLength)) ?? Data()
    }
}
