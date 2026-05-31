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
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "uploadClientEntered",
            recordingID: metadata.id,
            eventResult: "begin",
            uploadStatus: metadata.uploadStatus,
            resolvedRelativePathToken: metadata.relativeAudioPath
        )
        guard settings.isPaired else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "not_paired",
                uploadStatus: metadata.uploadStatus
            )
            throw RecordingUploadError.notPaired
        }

        let audioURL = try audioFileStore.audioURL(for: metadata)
        guard audioFileStore.fileExists(at: audioURL) else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "audio_file_missing",
                uploadStatus: metadata.uploadStatus,
                fileExists: false,
                resolvedRelativePathToken: metadata.relativeAudioPath
            )
            throw RecordingUploadError.audioFileMissing
        }

        let audioSize = try audioFileStore.fileSize(at: audioURL)
        guard audioSize <= Self.resumableAudioMaxBytes else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "audio_file_too_large",
                uploadStatus: metadata.uploadStatus,
                fileExists: true,
                fileSize: audioSize,
                resolvedRelativePathToken: metadata.relativeAudioPath
            )
            throw RecordingUploadError.fileTooLarge(limitBytes: Int(Self.resumableAudioMaxBytes))
        }

        let metadataResponse = try await uploadMetadataIfNeeded(
            metadata: metadata,
            settings: settings,
            progress: progress,
            resumeContext: resumeContext
        )

        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "audioUploadDecisionMade",
            recordingID: metadata.id,
            eventResult: "success",
            reasonCode: audioSize >= resumableThresholdBytes ? RecordingUploadMode.resumableChunks.rawValue : RecordingUploadMode.singleRequest.rawValue,
            uploadStatus: metadata.uploadStatus,
            fileExists: true,
            fileSize: audioSize,
            totalBytes: audioSize
        )
        if audioSize >= resumableThresholdBytes {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "resumableAudioUploadSelected",
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                fileSize: audioSize,
                totalBytes: audioSize
            )
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
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "smallAudioUploadSelected",
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-audio",
                fileSize: audioSize,
                totalBytes: audioSize
            )
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadRequestBuilt",
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-audio",
                fileSize: audioSize,
                totalBytes: audioSize
            )
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
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "secure_upload_error",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-audio",
                errorDomain: "SecureMacUploadError",
                safeErrorMessage: error.localizedDescription
            )
            throw RecordingUploadError.audioUploadFailed(error.localizedDescription)
        } catch {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "audio_upload_error",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-audio",
                errorDomain: "RecordingUploadClient",
                safeErrorMessage: error.localizedDescription
            )
            throw RecordingUploadError.audioUploadFailed(error.localizedDescription)
        }

        guard audioResponse.ok else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: audioResponse.error ?? "audio_upload_failed",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-audio",
                macReceiveState: audioResponse.receiveStatus,
                safeErrorMessage: audioResponse.error
            )
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
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "metadataUploadCompleted",
                recordingID: metadata.id,
                eventResult: "success",
                reasonCode: "resume_context_metadata_succeeded",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-metadata"
            )
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
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "metadataUploadStarted",
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-metadata",
                bodyBytes: metadataBody.count
            )
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
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "metadataUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "secure_upload_error",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-metadata",
                errorDomain: "SecureMacUploadError",
                safeErrorMessage: error.localizedDescription
            )
            throw RecordingUploadError.metadataUploadFailed(error.localizedDescription)
        } catch {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "metadataUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "metadata_upload_error",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-metadata",
                errorDomain: "RecordingUploadClient",
                safeErrorMessage: error.localizedDescription
            )
            throw RecordingUploadError.metadataUploadFailed(error.localizedDescription)
        }

        guard metadataResponse.ok else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "metadataUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: metadataResponse.error ?? "metadata_upload_failed",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-metadata",
                macReceiveState: metadataResponse.receiveStatus,
                safeErrorMessage: metadataResponse.error
            )
            throw RecordingUploadError.metadataUploadFailed(metadataResponse.error ?? "metadata_upload_failed")
        }
        try progress?(.metadataSucceeded(disposition: metadataResponse.disposition))
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "metadataUploadCompleted",
            recordingID: metadata.id,
            eventResult: "success",
            reasonCode: metadataResponse.disposition,
            uploadStatus: metadata.uploadStatus,
            httpPath: "/upload-recording-metadata",
            macReceiveState: metadataResponse.receiveStatus
        )
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
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "resumableStatusStarted",
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus,
                sessionID: existingSessionID,
                httpPath: "/upload-recording-audio-session/status",
                totalBytes: audioSize
            )
            let statusResponse = try await secureClient.fetchResumableAudioUploadStatus(
                settings: settings,
                request: ResumableAudioUploadStatusRequest(
                    recordingID: metadata.id,
                    sessionID: existingSessionID,
                    totalSHA256: totalSHA256
                )
            )
            if statusResponse.completed || statusResponse.finalAudioExists == true {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "resumableStatusCompleted",
                    recordingID: metadata.id,
                    eventResult: "success",
                    reasonCode: statusResponse.disposition,
                    uploadStatus: metadata.uploadStatus,
                    sessionID: existingSessionID,
                    httpPath: "/upload-recording-audio-session/status",
                    confirmedBytes: statusResponse.confirmedBytes,
                    totalBytes: audioSize,
                    macReceiveState: statusResponse.receiveStatus,
                    audioRelativePathSet: statusResponse.finalAudioRelativePath != nil
                )
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
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "resumableStatusCompleted",
                    recordingID: metadata.id,
                    eventResult: "success",
                    reasonCode: statusResponse.disposition,
                    uploadStatus: metadata.uploadStatus,
                    sessionID: existingSessionID,
                    httpPath: "/upload-recording-audio-session/status",
                    confirmedBytes: statusResponse.confirmedBytes,
                    totalBytes: audioSize
                )
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
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "resumableStartStarted",
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus,
                httpPath: "/upload-recording-audio-session/start",
                totalBytes: audioSize
            )
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
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "audioUploadFailed",
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: startResponse.error ?? "resumable_start_failed",
                    uploadStatus: metadata.uploadStatus,
                    httpPath: "/upload-recording-audio-session/start",
                    safeErrorMessage: startResponse.error
                )
                throw RecordingUploadError.audioUploadFailed(startResponse.error ?? "resumable_start_failed")
            }
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "resumableStartCompleted",
                recordingID: metadata.id,
                eventResult: "success",
                reasonCode: startResponse.disposition,
                uploadStatus: metadata.uploadStatus,
                sessionID: startedSessionID,
                httpPath: "/upload-recording-audio-session/start",
                confirmedBytes: startResponse.confirmedBytes,
                totalBytes: audioSize
            )
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
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "audioUploadFailed",
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: "audio_chunk_read_failed",
                    uploadStatus: metadata.uploadStatus,
                    sessionID: activeSessionID,
                    chunkOffset: nextOffset,
                    totalBytes: audioSize
                )
                throw RecordingUploadError.audioUploadFailed("audio_chunk_read_failed")
            }
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "resumableChunkStarted",
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus,
                sessionID: activeSessionID,
                httpPath: "/upload-recording-audio-session/chunk",
                chunkOffset: nextOffset,
                chunkLength: chunk.count,
                confirmedBytes: confirmedBytes,
                totalBytes: audioSize
            )
            let chunkResponse = try await secureClient.uploadResumableAudioChunk(
                settings: settings,
                recordingID: metadata.id,
                sessionID: activeSessionID,
                offset: nextOffset,
                totalSHA256: totalSHA256,
                chunk: chunk
            )
            guard chunkResponse.ok else {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "audioUploadFailed",
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: chunkResponse.error ?? "resumable_chunk_failed",
                    uploadStatus: metadata.uploadStatus,
                    sessionID: activeSessionID,
                    httpPath: "/upload-recording-audio-session/chunk",
                    chunkOffset: nextOffset,
                    chunkLength: chunk.count,
                    safeErrorMessage: chunkResponse.error
                )
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
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "audioUploadFailed",
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: finalizeResponse.error ?? "resumable_finalize_failed",
                uploadStatus: metadata.uploadStatus,
                sessionID: activeSessionID,
                httpPath: "/upload-recording-audio-session/finalize",
                confirmedBytes: confirmedBytes,
                totalBytes: audioSize,
                safeErrorMessage: finalizeResponse.error
            )
            throw RecordingUploadError.audioUploadFailed(finalizeResponse.error ?? "resumable_finalize_failed")
        }
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "resumableFinalizeCompleted",
            recordingID: metadata.id,
            eventResult: "success",
            reasonCode: finalizeResponse.disposition ?? audioDisposition,
            uploadStatus: metadata.uploadStatus,
            sessionID: activeSessionID,
            httpPath: "/upload-recording-audio-session/finalize",
            confirmedBytes: finalizeResponse.confirmedBytes,
            totalBytes: audioSize,
            macReceiveState: finalizeResponse.receiveStatus,
            audioRelativePathSet: finalizeResponse.finalAudioRelativePath != nil
        )
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
