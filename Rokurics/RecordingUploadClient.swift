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
}

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

final class RecordingUploadClient {
    static let audioMaxBytes = 512 * 1024 * 1024

    private let secureClient: SecureMacUploadClient
    private let audioFileStore: AudioFileStore

    init(
        secureClient: SecureMacUploadClient = SecureMacUploadClient(),
        audioFileStore: AudioFileStore = AudioFileStore()
    ) {
        self.secureClient = secureClient
        self.audioFileStore = audioFileStore
    }

    func uploadRecording(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot
    ) async throws -> RecordingUploadResult {
        guard settings.isPaired else {
            throw RecordingUploadError.notPaired
        }

        let audioURL = try audioFileStore.audioURL(for: metadata)
        guard audioFileStore.fileExists(at: audioURL) else {
            throw RecordingUploadError.audioFileMissing
        }

        let audioSize = try audioFileStore.fileSize(at: audioURL)
        guard audioSize <= Self.audioMaxBytes else {
            throw RecordingUploadError.fileTooLarge(limitBytes: Self.audioMaxBytes)
        }

        let metadataPayload = RecordingUploadMetadataPayload(
            metadata: metadata,
            sourceDeviceName: UIDevice.current.name,
            sourceDeviceID: settings.deviceID
        )
        let metadataBody = try Self.metadataEncoder.encode(metadataPayload)

        let metadataResponse: SecureUploadServerResponse
        do {
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

        let audioResponse: SecureUploadServerResponse
        do {
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

        return RecordingUploadResult(
            recordingID: audioResponse.recordingID ?? metadataResponse.recordingID ?? metadata.id,
            metadataFileName: metadataResponse.metadataFileName ?? metadataResponse.fileName,
            audioFileName: audioResponse.audioFileName ?? audioResponse.fileName
        )
    }

    private static let metadataEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
