//
//  IPhoneCanonicalTransferAdapter.swift
//  Rokurics
//
//  Created by Codex on 2026/6/14.
//

import CryptoKit
import Foundation

enum IPhoneCanonicalTransferAdapterError: Error, Equatable {
    case sessionMissing(String)
    case sessionContextMissing(String)
}

struct IPhoneCanonicalTransferFileSource: CanonicalTransferByteSource {
    private let source: IPhoneCanonicalAudioUploadFileSource

    init(source: IPhoneCanonicalAudioUploadFileSource) {
        self.source = source
    }

    var objectID: CanonicalObjectID {
        Self.canonicalAudioObjectID(source.objectID)
    }

    var totalBytes: Int64 {
        source.byteSize
    }

    var totalHash: CanonicalHash {
        source.contentHash
    }

    func readChunk(offset: Int64, maxLength: Int) async throws -> CanonicalTransferSourceChunk {
        let data = try await source.readChunk(
            offset: CanonicalAudioUploadOffset(offset),
            maxLength: maxLength
        )
        return CanonicalTransferSourceChunk(
            offset: offset,
            bytes: data,
            chunkHash: CanonicalHash(Self.sha256Hex(data))
        )
    }

    private nonisolated static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func canonicalAudioObjectID(_ rawValue: String) -> CanonicalObjectID {
        rawValue.hasPrefix("recordingAudio:")
            ? CanonicalObjectID(rawValue)
            : CanonicalObjectID("recordingAudio:\(rawValue)")
    }
}

actor IPhoneCanonicalTransferAdapter: CanonicalTransferRuntimePort {
    nonisolated static let existingResumableRoutePaths = IPhoneCanonicalSecureAudioUploadPort.existingResumableRoutePaths
    nonisolated static let wrapsExistingSecureUploadClient = true

    private struct SessionContext: Sendable {
        var objectID: CanonicalObjectID
        var destinationNodeID: CanonicalNodeID
        var contentHash: CanonicalHash
        var byteSize: Int64
        var chunkSize: Int
    }

    private let uploadPort: IPhoneCanonicalSecureAudioUploadPort
    private var contexts: [CanonicalTransferSessionID: SessionContext] = [:]

    init(
        settings: SecureMacConnectionSnapshot,
        transport: any RecordingSecureUploadTransport = SecureMacUploadClient(),
        chunkSizePolicy: Int = 4 * 1024 * 1024
    ) {
        self.uploadPort = IPhoneCanonicalSecureAudioUploadPort(
            settings: settings,
            transport: transport,
            chunkSizePolicy: chunkSizePolicy
        )
    }

    func start(_ request: CanonicalTransferStartRequest) async throws -> CanonicalTransferSession {
        let routeRecordingID = Self.routeRecordingID(for: request.objectID)
        let status = try await uploadPort.startResumableUpload(
            CanonicalUploadStartRequest(
                objectID: routeRecordingID,
                targetReference: Self.targetReference(for: request.objectID),
                totalBytes: request.byteSize,
                totalHash: request.contentHash,
                chunkSize: request.preferredChunkSize,
                idempotencyKey: request.objectID.rawValue
            ),
            now: request.requestedAt.date
        )
        guard let uploadSessionID = status.sessionID else {
            throw IPhoneCanonicalTransferAdapterError.sessionMissing(request.objectID.rawValue)
        }
        let sessionID = CanonicalTransferSessionID(uploadSessionID.rawValue)
        contexts[sessionID] = SessionContext(
            objectID: request.objectID,
            destinationNodeID: request.destinationNodeID,
            contentHash: request.contentHash,
            byteSize: request.byteSize,
            chunkSize: request.preferredChunkSize
        )
        let now = CanonicalTimestamp(Date())
        return CanonicalTransferSession(
            sessionID: sessionID,
            request: request,
            state: Self.transferState(from: status),
            acceptedOffset: status.confirmedBytes,
            createdAt: request.requestedAt,
            updatedAt: now
        )
    }

    func status(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        let context = try context(for: sessionID)
        let routeRecordingID = Self.routeRecordingID(for: context.objectID)
        let status = try await uploadPort.resumeUpload(
            CanonicalUploadStatusRequest(
                objectID: routeRecordingID,
                sessionID: CanonicalUploadSessionID(sessionID.rawValue),
                totalHash: context.contentHash
            ),
            now: Date()
        )
        return Self.transferStatus(
            from: status,
            sessionID: sessionID,
            objectID: context.objectID,
            totalBytes: context.byteSize,
            receiverNodeID: context.destinationNodeID
        )
    }

    func sendChunk(_ chunk: CanonicalTransferChunk) async throws -> CanonicalTransferChunkAck {
        let context = try context(for: chunk.sessionID)
        let routeRecordingID = Self.routeRecordingID(for: context.objectID)
        let status = try await uploadPort.uploadChunk(
            CanonicalUploadChunk(
                objectID: routeRecordingID,
                sessionID: CanonicalUploadSessionID(chunk.sessionID.rawValue),
                offset: chunk.offset,
                bytes: chunk.bytes,
                chunkHash: chunk.chunkHash,
                totalHash: context.contentHash,
                idempotencyKey: "\(chunk.sessionID.rawValue):\(chunk.offset):\(chunk.bytes.count)"
            ),
            now: Date()
        )
        return CanonicalTransferChunkAck(
            sessionID: chunk.sessionID,
            sequence: chunk.sequence,
            acceptedOffset: chunk.offset,
            acceptedBytes: status.confirmedBytes,
            acknowledgedAt: CanonicalTimestamp(Date())
        )
    }

    func finalize(_ request: CanonicalTransferFinalizeRequest) async throws -> CanonicalTransferFinalizeProof {
        let context = try context(for: request.sessionID)
        let routeRecordingID = Self.routeRecordingID(for: request.objectID)
        let status = try await uploadPort.finalizeUpload(
            CanonicalUploadFinalizeRequest(
                objectID: routeRecordingID,
                sessionID: CanonicalUploadSessionID(request.sessionID.rawValue),
                totalBytes: request.byteSize,
                totalHash: request.contentHash
            ),
            now: request.requestedAt.date
        )
        let verified = status.completed
            && status.fileSize == request.byteSize
            && status.checksum == request.contentHash
        return CanonicalTransferFinalizeProof.v930(
            receiverNodeID: context.destinationNodeID,
            sessionID: request.sessionID,
            objectID: request.objectID,
            byteSize: request.byteSize,
            contentHash: status.checksum ?? request.contentHash,
            manifestHash: request.manifestHash,
            finalizedAt: CanonicalTimestamp(Date()),
            verified: verified
        )
    }

    func abortLocalBeforeFinalize(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        let context = try context(for: sessionID)
        let routeRecordingID = Self.routeRecordingID(for: context.objectID)
        _ = try await uploadPort.cancelUpload(
            CanonicalProductionUploadCancelRequest(
                objectID: routeRecordingID,
                sessionID: CanonicalUploadSessionID(sessionID.rawValue),
                reason: "canonicalTransferLocalAbortBeforeFinalize"
            ),
            now: Date()
        )
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
            throw IPhoneCanonicalTransferAdapterError.sessionContextMissing(sessionID.rawValue)
        }
        return context
    }

    private nonisolated static func targetReference(for objectID: CanonicalObjectID) -> CanonicalFileReference {
        CanonicalFileReference(
            rootToken: CanonicalRootToken("canonical-transfer-audio"),
            logicalPathToken: "audio/\(objectID.rawValue).m4a",
            artifactID: "audio:\(objectID.rawValue)",
            artifactKind: .audio
        )
    }

    private nonisolated static func routeRecordingID(for objectID: CanonicalObjectID) -> String {
        let prefix = "recordingAudio:"
        let rawValue = objectID.rawValue
        guard rawValue.hasPrefix(prefix) else {
            return rawValue
        }
        return String(rawValue.dropFirst(prefix.count))
    }

    private nonisolated static func transferStatus(
        from status: CanonicalUploadSessionStatus,
        sessionID: CanonicalTransferSessionID,
        objectID: CanonicalObjectID,
        totalBytes: Int64,
        receiverNodeID: CanonicalNodeID
    ) -> CanonicalTransferStatus {
        CanonicalTransferStatus(
            sessionID: sessionID,
            objectID: objectID,
            state: transferState(from: status),
            acceptedOffset: status.confirmedBytes,
            totalBytes: totalBytes,
            finalizeProof: status.completed
                ? CanonicalTransferFinalizeProof.v930(
                    receiverNodeID: receiverNodeID,
                    sessionID: sessionID,
                    objectID: objectID,
                    byteSize: status.fileSize ?? totalBytes,
                    contentHash: status.checksum ?? CanonicalHash(""),
                    finalizedAt: CanonicalTimestamp(Date()),
                    verified: status.checksum != nil && status.fileSize != nil
                )
                : nil
        )
    }

    private nonisolated static func transferState(from status: CanonicalUploadSessionStatus) -> CanonicalTransferSessionState {
        if status.completed || status.phase == .completed {
            return .finalized
        }
        switch status.phase {
        case .active:
            return status.confirmedBytes > 0 ? .chunking : .started
        case .retryPending:
            return .interrupted
        case .finalizing:
            return .finalizing
        case .completed:
            return .finalized
        case .conflict:
            return .conflict
        case .failed:
            return .failed
        }
    }
}
