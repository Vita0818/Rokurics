//
//  RecordingUploadClient.swift
//  Rokurics
//
//  Created by Codex on 2026/5/12.
//

import Foundation
import UIKit

struct RecordingUploadResult {
    let recordingID: String
    let metadataFileName: String?
    let audioFileName: String?
    let metadataDisposition: String?
    let audioDisposition: String?
}

enum RecordingUploadMode: String, Codable, Equatable {
    case singleRequest
    case resumableChunks
}

enum RecordingResumableUploadState: String, Codable, Equatable {
    case notStarted
    case starting
    case uploading
    case paused
    case retryableFailed
    case finalizing
    case completed
    case fatalFailed
}

struct RecordingUploadResumeContext: Equatable {
    var metadataStage: RecordingUploadJobStageState
    var metadataDisposition: RecordingUploadJobDisposition
    var resumableSessionID: String?
    var audioConfirmedBytes: Int64?
    var audioTotalBytes: Int64?
    var audioChunkSize: Int?
    var audioTotalSHA256: String?
}

struct ResumableAudioUploadStartRequest: Codable, Equatable {
    let recordingID: String
    let fileName: String
    let totalBytes: Int64
    let totalSHA256: String
    let chunkSize: Int
    let metadataHash: String?
    let uploadJobID: String?
}

struct ResumableAudioUploadStatusRequest: Codable, Equatable {
    let recordingID: String
    let sessionID: String
    let totalSHA256: String
}

struct ResumableAudioUploadFinalizeRequest: Codable, Equatable {
    let recordingID: String
    let sessionID: String
    let totalBytes: Int64
    let totalSHA256: String
}

struct ResumableAudioUploadSessionResponse: Codable, Equatable {
    let ok: Bool
    let disposition: String?
    let status: String?
    let sessionID: String?
    let confirmedBytes: Int64
    let nextOffset: Int64
    let chunkSize: Int?
    let completed: Bool
    let finalAudioExists: Bool?
    let chunkAccepted: Bool?
    let finalAudioRelativePath: String?
    let checksum: String?
    let fileSize: Int64?
    let receiveStatus: String?
    let processingStatus: String?
    let error: String?
    let reason: String?
}

enum RecordingUploadProgressEvent: Equatable {
    case metadataStarted
    case metadataSucceeded(disposition: String?)
    case audioStarted
    case audioResumableSessionStarted(sessionID: String, totalBytes: Int64, chunkSize: Int, totalSHA256: String, confirmedBytes: Int64)
    case audioResumableProgress(sessionID: String, confirmedBytes: Int64, totalBytes: Int64, nextOffset: Int64)
    case audioResumableFinalizing(sessionID: String, confirmedBytes: Int64, totalBytes: Int64)
    case audioSucceeded(disposition: String?)
}

typealias RecordingUploadProgressHandler = @MainActor (RecordingUploadProgressEvent) throws -> Void

protocol RecordingUploadClientProtocol: AnyObject {
    func uploadRecording(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        progress: RecordingUploadProgressHandler?
    ) async throws -> RecordingUploadResult

    func uploadRecording(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        progress: RecordingUploadProgressHandler?,
        resumeContext: RecordingUploadResumeContext?
    ) async throws -> RecordingUploadResult
}

extension RecordingUploadClientProtocol {
    func uploadRecording(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        progress: RecordingUploadProgressHandler?,
        resumeContext: RecordingUploadResumeContext?
    ) async throws -> RecordingUploadResult {
        try await uploadRecording(metadata: metadata, settings: settings, progress: progress)
    }

    func uploadRecording(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot
    ) async throws -> RecordingUploadResult {
        try await uploadRecording(metadata: metadata, settings: settings, progress: nil)
    }
}

protocol RecordingSecureUploadTransport: AnyObject {
    func uploadSignedData(
        settings: SecureMacConnectionSnapshot,
        path: String,
        body: Data,
        contentType: String,
        uploadType: String,
        recordingID: String,
        fileName: String,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> SecureUploadServerResponse

    func uploadSignedFile(
        settings: SecureMacConnectionSnapshot,
        path: String,
        fileURL: URL,
        contentType: String,
        uploadType: String,
        recordingID: String,
        fileName: String,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> SecureUploadServerResponse

    func startResumableAudioUpload(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadStartRequest
    ) async throws -> ResumableAudioUploadSessionResponse

    func fetchResumableAudioUploadStatus(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadStatusRequest
    ) async throws -> ResumableAudioUploadSessionResponse

    func uploadResumableAudioChunk(
        settings: SecureMacConnectionSnapshot,
        recordingID: String,
        sessionID: String,
        offset: Int64,
        totalSHA256: String,
        chunk: Data
    ) async throws -> ResumableAudioUploadSessionResponse

    func finalizeResumableAudioUpload(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadFinalizeRequest
    ) async throws -> ResumableAudioUploadSessionResponse
}

extension SecureMacUploadClient: RecordingSecureUploadTransport {}

enum RecordingUploadError: LocalizedError {
    case notPaired
    case audioFileMissing
    case fileTooLarge(limitBytes: Int)
    case metadataUploadFailed(String)
    case audioUploadFailed(String)
    case macRejected(String)
    case networkFailed(String)

    var errorDescription: String? {
        switch self {
        case .notPaired:
            return "请先连接 Mac。"
        case .audioFileMissing:
            return "找不到音频文件。"
        case .fileTooLarge(let limitBytes):
            return "文件过大，当前限制为 \(Self.fileSizeFormatter.string(fromByteCount: Int64(limitBytes)))。"
        case .metadataUploadFailed(let reason):
            return "metadata 上传失败：\(reason)"
        case .audioUploadFailed(let reason):
            return "audio 上传失败：\(reason)"
        case .macRejected(let reason):
            return "Mac 拒绝：\(reason)"
        case .networkFailed(let reason):
            return "网络失败：\(reason)"
        }
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter
    }()
}

final class RecordingUploadClient: RecordingUploadClientProtocol {
    static let singleRequestAudioMaxBytes = 512 * 1024 * 1024
    static let resumableAudioMaxBytes: Int64 = 16 * 1024 * 1024 * 1024
    static let defaultResumableThresholdBytes: Int64 = 64 * 1024 * 1024
    static let defaultResumableChunkSize = 4 * 1024 * 1024

    private let secureClient: any RecordingSecureUploadTransport
    private let audioFileStore: AudioFileStore
    private let resumableThresholdBytes: Int64
    private let resumableChunkSize: Int

    init(
        secureClient: any RecordingSecureUploadTransport = SecureMacUploadClient(),
        audioFileStore: AudioFileStore = AudioFileStore(),
        resumableThresholdBytes: Int64 = RecordingUploadClient.defaultResumableThresholdBytes,
        resumableChunkSize: Int = RecordingUploadClient.defaultResumableChunkSize
    ) {
        self.secureClient = secureClient
        self.audioFileStore = audioFileStore
        self.resumableThresholdBytes = resumableThresholdBytes
        self.resumableChunkSize = resumableChunkSize
    }

    func uploadRecording(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        progress: RecordingUploadProgressHandler? = nil
    ) async throws -> RecordingUploadResult {
        try await uploadRecording(metadata: metadata, settings: settings, progress: progress, resumeContext: nil)
    }

    func uploadRecording(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        progress: RecordingUploadProgressHandler? = nil,
        resumeContext: RecordingUploadResumeContext?
    ) async throws -> RecordingUploadResult {
        guard settings.isPaired else {
            throw RecordingUploadError.notPaired
        }

        let audioURL = try audioFileStore.audioURL(for: metadata)
        guard audioFileStore.fileExists(at: audioURL) else {
            throw RecordingUploadError.audioFileMissing
        }

        let audioSize = try audioFileStore.fileSize(at: audioURL)
        guard audioSize <= Self.resumableAudioMaxBytes else {
            throw RecordingUploadError.fileTooLarge(limitBytes: Int(Self.resumableAudioMaxBytes))
        }

        let metadataResponse = try await uploadMetadataIfNeeded(
            metadata: metadata,
            settings: settings,
            progress: progress,
            resumeContext: resumeContext
        )

        if audioSize >= resumableThresholdBytes {
            return try await uploadResumableAudio(
                metadata: metadata,
                settings: settings,
                audioURL: audioURL,
                audioSize: audioSize,
                metadataResponse: metadataResponse,
                resumeContext: resumeContext,
                progress: progress
            )
        }

        let audioResponse: SecureUploadServerResponse
        do {
            try progress?(.audioStarted)
            audioResponse = try await secureClient.uploadSignedFile(
                settings: settings,
                path: "/upload-recording-audio",
                fileURL: audioURL,
                contentType: "audio/m4a",
                uploadType: "recording-audio",
                recordingID: metadata.id,
                fileName: metadata.fileName,
                requestTimeout: 30,
                resourceTimeout: 60 * 30
            )
        } catch let error as SecureMacUploadError {
            throw RecordingUploadError.audioUploadFailed(error.localizedDescription)
        } catch {
            throw RecordingUploadError.audioUploadFailed(error.localizedDescription)
        }

        guard audioResponse.ok else {
            throw RecordingUploadError.audioUploadFailed(audioResponse.error ?? "audio_upload_failed")
        }
        try progress?(.audioSucceeded(disposition: audioResponse.disposition))

        return RecordingUploadResult(
            recordingID: audioResponse.recordingID ?? metadataResponse.recordingID ?? metadata.id,
            metadataFileName: metadataResponse.metadataFileName ?? metadataResponse.fileName,
            audioFileName: audioResponse.audioFileName ?? audioResponse.fileName,
            metadataDisposition: metadataResponse.disposition,
            audioDisposition: audioResponse.disposition
        )
    }

    private func uploadMetadataIfNeeded(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        progress: RecordingUploadProgressHandler?,
        resumeContext: RecordingUploadResumeContext?
    ) async throws -> SecureUploadServerResponse {
        if resumeContext?.metadataStage == .succeeded {
            return SecureUploadServerResponse(
                ok: true,
                message: "metadata already uploaded",
                disposition: resumeContext?.metadataDisposition == .acceptedExisting ? "acceptedExisting" : "acceptedNew",
                fileName: nil,
                recordingID: metadata.id,
                metadataFileName: "metadata.json",
                audioFileName: nil,
                receiveStatus: "metadataReceived",
                processingStatus: "awaitingAudio",
                error: nil,
                reason: nil
            )
        }

        let metadataPayload = RecordingUploadMetadataPayload(
            metadata: metadata,
            sourceDeviceName: UIDevice.current.name,
            sourceDeviceID: settings.deviceID
        )
        let metadataBody = try Self.metadataEncoder.encode(metadataPayload)

        let metadataResponse: SecureUploadServerResponse
        do {
            try progress?(.metadataStarted)
            metadataResponse = try await secureClient.uploadSignedData(
                settings: settings,
                path: "/upload-recording-metadata",
                body: metadataBody,
                contentType: "application/json",
                uploadType: "recording-metadata",
                recordingID: metadata.id,
                fileName: metadata.fileName,
                requestTimeout: 15,
                resourceTimeout: 30
            )
        } catch let error as SecureMacUploadError {
            throw RecordingUploadError.metadataUploadFailed(error.localizedDescription)
        } catch {
            throw RecordingUploadError.metadataUploadFailed(error.localizedDescription)
        }

        guard metadataResponse.ok else {
            throw RecordingUploadError.metadataUploadFailed(metadataResponse.error ?? "metadata_upload_failed")
        }
        try progress?(.metadataSucceeded(disposition: metadataResponse.disposition))
        return metadataResponse
    }

    private func uploadResumableAudio(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        audioURL: URL,
        audioSize: Int64,
        metadataResponse: SecureUploadServerResponse,
        resumeContext: RecordingUploadResumeContext?,
        progress: RecordingUploadProgressHandler?
    ) async throws -> RecordingUploadResult {
        let normalizedChunkSize = max(1, min(resumableChunkSize, Self.defaultResumableChunkSize * 2))
        let totalSHA256: String
        if let existingSHA256 = resumeContext?.audioTotalSHA256 {
            totalSHA256 = existingSHA256
        } else {
            totalSHA256 = try SecureUploadUtilities.sha256Hex(fileURL: audioURL)
        }
        var sessionID = resumeContext?.resumableSessionID
        var confirmedBytes: Int64 = 0
        var nextOffset: Int64 = 0
        var audioDisposition: String? = nil

        try progress?(.audioStarted)

        if let existingSessionID = sessionID {
            let statusResponse = try await secureClient.fetchResumableAudioUploadStatus(
                settings: settings,
                request: ResumableAudioUploadStatusRequest(
                    recordingID: metadata.id,
                    sessionID: existingSessionID,
                    totalSHA256: totalSHA256
                )
            )
            if statusResponse.completed || statusResponse.finalAudioExists == true {
                try progress?(.audioSucceeded(disposition: statusResponse.disposition ?? "acceptedExisting"))
                return RecordingUploadResult(
                    recordingID: metadata.id,
                    metadataFileName: metadataResponse.metadataFileName ?? metadataResponse.fileName,
                    audioFileName: statusResponse.finalAudioRelativePath?.components(separatedBy: "/").last ?? "audio.m4a",
                    metadataDisposition: metadataResponse.disposition,
                    audioDisposition: statusResponse.disposition ?? "acceptedExisting"
                )
            }
            if statusResponse.ok {
                confirmedBytes = statusResponse.confirmedBytes
                nextOffset = statusResponse.nextOffset
                audioDisposition = statusResponse.disposition
                try progress?(.audioResumableSessionStarted(
                    sessionID: existingSessionID,
                    totalBytes: audioSize,
                    chunkSize: statusResponse.chunkSize ?? normalizedChunkSize,
                    totalSHA256: totalSHA256,
                    confirmedBytes: confirmedBytes
                ))
            } else {
                sessionID = nil
            }
        }

        if sessionID == nil {
            let startResponse = try await secureClient.startResumableAudioUpload(
                settings: settings,
                request: ResumableAudioUploadStartRequest(
                    recordingID: metadata.id,
                    fileName: metadata.fileName,
                    totalBytes: audioSize,
                    totalSHA256: totalSHA256,
                    chunkSize: normalizedChunkSize,
                    metadataHash: nil,
                    uploadJobID: metadata.id
                )
            )
            guard startResponse.ok, let startedSessionID = startResponse.sessionID else {
                throw RecordingUploadError.audioUploadFailed(startResponse.error ?? "resumable_start_failed")
            }
            sessionID = startedSessionID
            confirmedBytes = startResponse.confirmedBytes
            nextOffset = startResponse.nextOffset
            audioDisposition = startResponse.disposition
            try progress?(.audioResumableSessionStarted(
                sessionID: startedSessionID,
                totalBytes: audioSize,
                chunkSize: startResponse.chunkSize ?? normalizedChunkSize,
                totalSHA256: totalSHA256,
                confirmedBytes: confirmedBytes
            ))

            if startResponse.completed || startResponse.finalAudioExists == true {
                try progress?(.audioSucceeded(disposition: startResponse.disposition ?? "acceptedExisting"))
                return RecordingUploadResult(
                    recordingID: metadata.id,
                    metadataFileName: metadataResponse.metadataFileName ?? metadataResponse.fileName,
                    audioFileName: "audio.m4a",
                    metadataDisposition: metadataResponse.disposition,
                    audioDisposition: startResponse.disposition ?? "acceptedExisting"
                )
            }
        }

        guard let activeSessionID = sessionID else {
            throw RecordingUploadError.audioUploadFailed("resumable_session_missing")
        }

        let fileHandle = try FileHandle(forReadingFrom: audioURL)
        defer {
            try? fileHandle.close()
        }

        while confirmedBytes < audioSize {
            let chunk = try readChunk(from: fileHandle, offset: nextOffset, maximumLength: normalizedChunkSize)
            guard !chunk.isEmpty else {
                throw RecordingUploadError.audioUploadFailed("audio_chunk_read_failed")
            }
            let chunkResponse = try await secureClient.uploadResumableAudioChunk(
                settings: settings,
                recordingID: metadata.id,
                sessionID: activeSessionID,
                offset: nextOffset,
                totalSHA256: totalSHA256,
                chunk: chunk
            )
            guard chunkResponse.ok else {
                throw RecordingUploadError.audioUploadFailed(chunkResponse.error ?? "resumable_chunk_failed")
            }
            confirmedBytes = chunkResponse.confirmedBytes
            nextOffset = chunkResponse.nextOffset
            audioDisposition = chunkResponse.disposition
            try progress?(.audioResumableProgress(
                sessionID: activeSessionID,
                confirmedBytes: confirmedBytes,
                totalBytes: audioSize,
                nextOffset: nextOffset
            ))
        }

        try progress?(.audioResumableFinalizing(sessionID: activeSessionID, confirmedBytes: confirmedBytes, totalBytes: audioSize))
        let finalizeResponse = try await secureClient.finalizeResumableAudioUpload(
            settings: settings,
            request: ResumableAudioUploadFinalizeRequest(
                recordingID: metadata.id,
                sessionID: activeSessionID,
                totalBytes: audioSize,
                totalSHA256: totalSHA256
            )
        )
        guard finalizeResponse.ok else {
            throw RecordingUploadError.audioUploadFailed(finalizeResponse.error ?? "resumable_finalize_failed")
        }
        try progress?(.audioSucceeded(disposition: finalizeResponse.disposition ?? audioDisposition))

        return RecordingUploadResult(
            recordingID: metadata.id,
            metadataFileName: metadataResponse.metadataFileName ?? metadataResponse.fileName,
            audioFileName: finalizeResponse.finalAudioRelativePath?.components(separatedBy: "/").last ?? "audio.m4a",
            metadataDisposition: metadataResponse.disposition,
            audioDisposition: finalizeResponse.disposition ?? audioDisposition
        )
    }

    private func readChunk(from fileHandle: FileHandle, offset: Int64, maximumLength: Int) throws -> Data {
        try fileHandle.seek(toOffset: UInt64(offset))
        return try fileHandle.read(upToCount: maximumLength) ?? Data()
    }

    private static let metadataEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
