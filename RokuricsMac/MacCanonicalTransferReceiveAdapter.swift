//
//  MacCanonicalTransferReceiveAdapter.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/14.
//

import Foundation

enum MacCanonicalTransferReceiveAdapterError: Error, Equatable {
    case sessionMissing(String)
    case sessionContextMissing(String)
}

@MainActor
final class MacCanonicalTransferReceiveAdapter: CanonicalTransferRuntimePort, @unchecked Sendable {
    nonisolated static let existingResumableRoutePaths = MacAudioUploadCutoverExecutor.existingResumableRoutePaths
    nonisolated static let wrapsExistingSecureReceiveStore = true

    private struct SessionContext {
        var objectID: CanonicalObjectID
        var sourceDevice: PairedDevice
        var receiverNodeID: CanonicalNodeID
        var contentHash: CanonicalHash
        var byteSize: Int64
        var chunkSize: Int
    }

    private let executor: MacAudioUploadCutoverExecutor
    private let sourceDevice: PairedDevice
    private let receiverNodeID: CanonicalNodeID
    private var contexts: [CanonicalTransferSessionID: SessionContext] = [:]

    convenience init(
        sourceDevice: PairedDevice,
        receiverNodeID: CanonicalNodeID
    ) {
        self.init(
            sourceDevice: sourceDevice,
            receiverNodeID: receiverNodeID,
            executor: MacAudioUploadCutoverExecutor()
        )
    }

    init(
        sourceDevice: PairedDevice,
        receiverNodeID: CanonicalNodeID,
        executor: MacAudioUploadCutoverExecutor
    ) {
        self.sourceDevice = sourceDevice
        self.receiverNodeID = receiverNodeID
        self.executor = executor
    }

    nonisolated func start(_ request: CanonicalTransferStartRequest) async throws -> CanonicalTransferSession {
        try await startOnMain(request)
    }

    nonisolated func status(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        try await statusOnMain(sessionID: sessionID)
    }

    nonisolated func sendChunk(_ chunk: CanonicalTransferChunk) async throws -> CanonicalTransferChunkAck {
        try await sendChunkOnMain(chunk)
    }

    nonisolated func finalize(_ request: CanonicalTransferFinalizeRequest) async throws -> CanonicalTransferFinalizeProof {
        try await finalizeOnMain(request)
    }

    nonisolated func abortLocalBeforeFinalize(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        try await MainActor.run {
            try abortLocalBeforeFinalizeOnMain(sessionID: sessionID)
        }
    }

    private func startOnMain(_ request: CanonicalTransferStartRequest) async throws -> CanonicalTransferSession {
        let response = try await executor.startReceive(
            ResumableAudioUploadStartRequest(
                recordingID: request.objectID.rawValue,
                fileName: "\(request.objectID.rawValue).m4a",
                totalBytes: request.byteSize,
                totalSHA256: request.contentHash.value,
                chunkSize: request.preferredChunkSize,
                metadataHash: request.manifestHash?.value,
                uploadJobID: request.objectID.rawValue
            ),
            sourceDevice: sourceDevice
        )
        guard let responseSessionID = response.sessionID else {
            throw MacCanonicalTransferReceiveAdapterError.sessionMissing(request.objectID.rawValue)
        }
        let sessionID = CanonicalTransferSessionID(responseSessionID)
        contexts[sessionID] = SessionContext(
            objectID: request.objectID,
            sourceDevice: sourceDevice,
            receiverNodeID: request.destinationNodeID,
            contentHash: request.contentHash,
            byteSize: request.byteSize,
            chunkSize: request.preferredChunkSize
        )
        return CanonicalTransferSession(
            sessionID: sessionID,
            request: request,
            state: Self.transferState(from: response),
            acceptedOffset: response.confirmedBytes,
            createdAt: request.requestedAt,
            updatedAt: CanonicalTimestamp(Date())
        )
    }

    private func statusOnMain(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        let context = try context(for: sessionID)
        let response = try await executor.statusReceive(
            ResumableAudioUploadStatusRequest(
                recordingID: context.objectID.rawValue,
                sessionID: sessionID.rawValue,
                totalSHA256: context.contentHash.value
            ),
            sourceDevice: context.sourceDevice
        )
        return Self.transferStatus(
            from: response,
            sessionID: sessionID,
            objectID: context.objectID,
            totalBytes: context.byteSize,
            receiverNodeID: context.receiverNodeID,
            fallbackHash: context.contentHash
        )
    }

    private func sendChunkOnMain(_ chunk: CanonicalTransferChunk) async throws -> CanonicalTransferChunkAck {
        let context = try context(for: chunk.sessionID)
        let response = try await executor.appendReceiveChunk(
            recordingID: context.objectID.rawValue,
            sessionID: chunk.sessionID.rawValue,
            offset: chunk.offset,
            length: chunk.bytes.count,
            chunkSHA256: chunk.chunkHash.value,
            totalSHA256: context.contentHash.value,
            body: chunk.bytes,
            sourceDevice: context.sourceDevice
        )
        return CanonicalTransferChunkAck(
            sessionID: chunk.sessionID,
            sequence: chunk.sequence,
            acceptedOffset: chunk.offset,
            acceptedBytes: response.confirmedBytes,
            acknowledgedAt: CanonicalTimestamp(Date())
        )
    }

    private func finalizeOnMain(_ request: CanonicalTransferFinalizeRequest) async throws -> CanonicalTransferFinalizeProof {
        let context = try context(for: request.sessionID)
        let result = try await executor.finalizeReceive(
            ResumableAudioUploadFinalizeRequest(
                recordingID: request.objectID.rawValue,
                sessionID: request.sessionID.rawValue,
                totalBytes: request.byteSize,
                totalSHA256: request.contentHash.value
            ),
            sourceDevice: context.sourceDevice
        )
        let accepted = result.runtimeResult?.finalizeProof?.accepted == true
        return CanonicalTransferFinalizeProof.v930(
            receiverNodeID: context.receiverNodeID,
            sessionID: request.sessionID,
            objectID: request.objectID,
            byteSize: request.byteSize,
            contentHash: request.contentHash,
            manifestHash: request.manifestHash,
            finalizedAt: CanonicalTimestamp(Date()),
            verified: accepted
        )
    }

    private func abortLocalBeforeFinalizeOnMain(sessionID: CanonicalTransferSessionID) throws -> CanonicalTransferStatus {
        let context = try context(for: sessionID)
        return CanonicalTransferStatus(
            sessionID: sessionID,
            objectID: context.objectID,
            state: .aborted,
            acceptedOffset: 0,
            totalBytes: context.byteSize
        )
    }

    private func context(for sessionID: CanonicalTransferSessionID) throws -> SessionContext {
        guard let context = contexts[sessionID] else {
            throw MacCanonicalTransferReceiveAdapterError.sessionContextMissing(sessionID.rawValue)
        }
        return context
    }

    private nonisolated static func transferStatus(
        from response: ResumableAudioUploadSessionResponse,
        sessionID: CanonicalTransferSessionID,
        objectID: CanonicalObjectID,
        totalBytes: Int64,
        receiverNodeID: CanonicalNodeID,
        fallbackHash: CanonicalHash
    ) -> CanonicalTransferStatus {
        let finalizeProof: CanonicalTransferFinalizeProof?
        if response.completed {
            let proofHash: CanonicalHash
            if let checksum = response.checksum {
                proofHash = CanonicalHash(checksum)
            } else {
                proofHash = fallbackHash
            }
            finalizeProof = CanonicalTransferFinalizeProof.v930(
                receiverNodeID: receiverNodeID,
                sessionID: sessionID,
                objectID: objectID,
                byteSize: response.fileSize ?? totalBytes,
                contentHash: proofHash,
                finalizedAt: CanonicalTimestamp(Date()),
                verified: response.fileSize != nil && response.checksum != nil
            )
        } else {
            finalizeProof = nil
        }

        return CanonicalTransferStatus(
            sessionID: sessionID,
            objectID: objectID,
            state: transferState(from: response),
            acceptedOffset: response.confirmedBytes,
            totalBytes: totalBytes,
            finalizeProof: finalizeProof
        )
    }

    private nonisolated static func transferState(
        from response: ResumableAudioUploadSessionResponse
    ) -> CanonicalTransferSessionState {
        if response.completed || response.finalAudioExists == true {
            return .finalized
        }
        let status = response.status?.lowercased() ?? ""
        let reason = [response.error, response.reason].compactMap { $0?.lowercased() }.joined(separator: " ")
        if status.contains("conflict") || reason.contains("conflict") || reason.contains("mismatch") {
            return .conflict
        }
        if status.contains("failed") || status.contains("error") || response.ok == false {
            return .failed
        }
        if response.confirmedBytes > 0 {
            return .chunking
        }
        return .started
    }
}
