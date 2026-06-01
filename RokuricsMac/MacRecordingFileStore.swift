//
//  MacRecordingFileStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/12.
//

import Foundation

enum MacRecordingFileStoreError: LocalizedError {
    case unableToCreateDirectory
    case invalidRecordingID
    case unsafeDestination
    case metadataAlreadyExists
    case metadataMissing
    case metadataConflict
    case audioAlreadyExists
    case audioMissing
    case audioConflict
    case fileTooLarge
    case invalidSession
    case sessionMissing
    case sessionConflict
    case chunkOffsetMismatch
    case chunkChecksumMismatch
    case sessionIncomplete
    case storageFailed(String)

    var errorDescription: String? {
        switch self {
        case .unableToCreateDirectory:
            return "unable_to_create_directory"
        case .invalidRecordingID:
            return "invalid_recording_id"
        case .unsafeDestination:
            return "unsafe_destination"
        case .metadataAlreadyExists:
            return "recording_metadata_exists"
        case .metadataMissing:
            return "recording_metadata_missing"
        case .metadataConflict:
            return "recording_metadata_conflict"
        case .audioAlreadyExists:
            return "recording_audio_exists"
        case .audioMissing:
            return "recording_audio_missing"
        case .audioConflict:
            return "recording_audio_conflict"
        case .fileTooLarge:
            return "file_too_large"
        case .invalidSession:
            return "invalid_upload_session"
        case .sessionMissing:
            return "upload_session_missing"
        case .sessionConflict:
            return "upload_session_conflict"
        case .chunkOffsetMismatch:
            return "upload_chunk_offset_mismatch"
        case .chunkChecksumMismatch:
            return "upload_chunk_checksum_mismatch"
        case .sessionIncomplete:
            return "upload_session_incomplete"
        case .storageFailed(let reason):
            return reason
        }
    }

    var responseStatusCode: Int {
        switch self {
        case .fileTooLarge:
            return 413
        case .metadataAlreadyExists, .metadataConflict, .audioAlreadyExists, .audioConflict, .sessionConflict, .chunkChecksumMismatch:
            return 409
        case .sessionIncomplete, .chunkOffsetMismatch:
            return 422
        case .sessionMissing:
            return 404
        case .invalidRecordingID, .unsafeDestination, .metadataMissing, .audioMissing, .invalidSession:
            return 400
        case .unableToCreateDirectory, .storageFailed:
            return 500
        }
    }

    var responseReason: String {
        switch responseStatusCode {
        case 400:
            return "Bad Request"
        case 409:
            return "Conflict"
        case 413:
            return "Payload Too Large"
        case 422:
            return "Unprocessable Entity"
        case 404:
            return "Not Found"
        default:
            return "Internal Server Error"
        }
    }
}

struct MacRecordingTranscriptionSource {
    let recordingID: String
    let title: String
    let createdAt: Date
    let duration: TimeInterval
    let audioFileURL: URL
    let metadataFileURL: URL?
}

struct MacRecordingNoteGenerationSource {
    let recordingID: String
    let sanitizedRecordingID: String
    let title: String
    let createdAt: Date
    let duration: TimeInterval
    let transcriptionStatus: String
    let transcriptRelativePath: String?
    let transcriptMarkdownRelativePath: String?
    let transcriptionProviderID: String?
    let transcriptionModelName: String?
    let transcriptURL: URL?
    let transcriptMarkdownURL: URL?
}

final class MacRecordingFileStore {
    static let metadataMaxBytes = 1 * 1024 * 1024
    // First real-audio upload version keeps whole-file uploads capped.
    // Future chunked upload can raise this limit without changing the library layout.
    static let audioMaxBytes = 512 * 1024 * 1024
    static let resumableChunkMaxBytes = 8 * 1024 * 1024
    static let resumableAudioMaxBytes: Int64 = 16 * 1024 * 1024 * 1024
    static let inboxDidChangeNotification = Notification.Name("RokuricsMacRecordingInboxDidChange")

    private struct RecordingIndex: Codable {
        var directoriesByRecordingID: [String: String] = [:]
    }

    private struct ResumableAudioChunkRecord: Codable, Equatable {
        var offset: Int64
        var length: Int
        var sha256: String
    }

    private struct ResumableAudioSessionManifest: Codable, Equatable {
        static let currentVersion = 1

        var version: Int = Self.currentVersion
        var sessionID: String
        var recordingID: String
        var sourceDeviceID: String
        var expectedTotalBytes: Int64
        var expectedTotalSHA256: String
        var chunkSize: Int
        var tempRelativePath: String
        var receivedBytes: Int64
        var receivedChunks: [ResumableAudioChunkRecord]
        var createdAt: Date
        var updatedAt: Date
        var finalizedAt: Date?
        var status: String
        var lastError: String?
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let audioInboxURL: URL
    private let uploadSessionsURL: URL
    private let transcriptsURL: URL
    private let metadataIndexURL: URL
    private let receiveLogURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            self.rootURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
        }
        audioInboxURL = self.rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .standardizedFileURL
        uploadSessionsURL = self.rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("upload-sessions", isDirectory: true)
            .standardizedFileURL
        transcriptsURL = self.rootURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .standardizedFileURL
        metadataIndexURL = self.rootURL
            .appendingPathComponent("metadata", isDirectory: true)
            .appendingPathComponent("recordings-index.json", isDirectory: false)
            .standardizedFileURL
        receiveLogURL = self.rootURL
            .appendingPathComponent("system", isDirectory: true)
            .appendingPathComponent("receive-log.json", isDirectory: false)
            .standardizedFileURL

        try? ensureLibraryDirectories()
    }

    var libraryRootURL: URL {
        rootURL
    }

    var libraryRootDisplayPath: String {
        rootURL.path
    }

    func saveMetadata(
        _ metadata: IncomingRecordingMetadata,
        sourceDevice: PairedDevice,
        uploadTraceID: String? = nil
    ) throws -> RecordingReceiveResult {
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "receiveRecordLookupStarted",
            traceID: uploadTraceID,
            recordingID: metadata.id,
            eventResult: "begin",
            uploadStatus: metadata.uploadStatus,
            fileSize: metadata.fileSize,
            resolvedRelativePathToken: metadata.relativeAudioPath
        )
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "receiveRecordIDMappingChecked",
            traceID: uploadTraceID,
            recordingID: metadata.id,
            eventResult: "begin"
        )
        guard metadataDataSizeIsAllowed(metadata) else {
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordConflictDetected",
                traceID: uploadTraceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "metadata_too_large"
            )
            throw MacRecordingFileStoreError.fileTooLarge
        }

        try ensureLibraryDirectories()
        let sanitizedID = sanitizedPathComponent(metadata.id)
        guard !sanitizedID.isEmpty else {
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordConflictDetected",
                traceID: uploadTraceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "invalid_recording_id"
            )
            throw MacRecordingFileStoreError.invalidRecordingID
        }

        if let existingDirectoryURL = recordingDirectoryURL(for: metadata.id) {
            return try handleExistingMetadataUpload(
                metadata,
                sourceDevice: sourceDevice,
                recordingDirectoryURL: existingDirectoryURL,
                uploadTraceID: uploadTraceID
            )
        }

        let day = Self.dayFormatter.string(from: metadata.createdAt)
        let recordingDirectoryURL = audioInboxURL
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent(sanitizedID, isDirectory: true)
            .standardizedFileURL
        let metadataURL = recordingDirectoryURL.appendingPathComponent("metadata.json", isDirectory: false).standardizedFileURL
        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL

        guard isInsideRoot(recordingDirectoryURL), isInsideRoot(metadataURL), isInsideRoot(receiveURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        guard !fileManager.fileExists(atPath: metadataURL.path) else {
            throw MacRecordingFileStoreError.metadataAlreadyExists
        }

        do {
            try fileManager.createDirectory(at: recordingDirectoryURL, withIntermediateDirectories: true)
            try Self.jsonEncoder.encode(metadata).write(to: metadataURL, options: .atomic)
            let record = RecordingReceiveRecord(
                recordingID: metadata.id,
                sanitizedRecordingID: sanitizedID,
                receivedAt: Date(),
                updatedAt: Date(),
                sourceDeviceID: sourceDevice.id,
                sourceDeviceName: metadata.sourceDeviceName.isEmpty ? sourceDevice.deviceName : metadata.sourceDeviceName,
                originalTitle: metadata.title,
                normalizedTitle: normalizeTitle(metadata.title),
                audioFileName: nil,
                originalAudioFileName: nil,
                metadataFileName: "metadata.json",
                status: "metadataReceived",
                transcriptionStatus: metadata.transcriptionStatus,
                noteStatus: RecordingReceiveRecord.normalizedNoteStatus(metadata.noteStatus),
                processingStatus: "awaitingAudio",
                suggestedCategory: nil,
                course: nil,
                category: nil,
                tags: metadata.tags,
                studyFiling: metadata.studyFiling,
                createdAt: metadata.createdAt,
                duration: metadata.duration,
                fileSize: metadata.fileSize,
                suggestedFolder: nil,
                userConfirmedFolder: nil,
                checksum: nil,
                audioRelativePath: nil,
                metadataRelativePath: try relativePath(for: metadataURL),
                lastUploadError: nil,
                lastUploadAttemptAt: nextUploadAttemptDate(after: nil)
            )
            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordCreated",
                traceID: uploadTraceID,
                recordingID: metadata.id,
                eventResult: "success",
                resolvedRelativePathToken: record.metadataRelativePath,
                macReceiveState: record.status,
                audioRelativePathSet: false
            )
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordWaitingForAudio",
                traceID: uploadTraceID,
                recordingID: metadata.id,
                eventResult: "success",
                macReceiveState: record.status,
                audioRelativePathSet: false
            )

            var index = loadIndex()
            index.directoriesByRecordingID[metadata.id] = try relativePath(for: recordingDirectoryURL)
            try saveIndex(index)
            try appendReceiveLog(recordingID: metadata.id, event: "metadata_received", sourceDeviceID: sourceDevice.id, status: record.status)
            postInboxChanged()
            print("[RokuricsRecordingStore] metadata saved: \(metadataURL.path)")
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordSaved",
                traceID: uploadTraceID,
                recordingID: metadata.id,
                eventResult: "success",
                resolvedRelativePathToken: try? relativePath(for: receiveURL),
                macReceiveState: record.status,
                audioRelativePathSet: false
            )
            return RecordingReceiveResult(
                recordingID: metadata.id,
                directoryURL: recordingDirectoryURL,
                metadataFileName: "metadata.json",
                audioFileName: nil,
                receiveFileName: "receive.json",
                disposition: .acceptedNew,
                receiveStatus: record.status,
                processingStatus: record.processingStatus
            )
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            print("[RokuricsRecordingStore][ERROR] metadata save failed: \(error)")
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordConflictDetected",
                traceID: uploadTraceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "metadata_storage_failed",
                safeErrorMessage: error.localizedDescription
            )
            throw MacRecordingFileStoreError.storageFailed("metadata_storage_failed")
        }
    }

    func saveAudio(
        body: Data,
        recordingID: String,
        requestedFileName: String?,
        sourceDevice: PairedDevice,
        uploadTraceID: String? = nil
    ) throws -> RecordingReceiveResult {
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "audioReceiveRecordLookupStarted",
            traceID: uploadTraceID,
            recordingID: recordingID,
            eventResult: "begin",
            bodyBytes: body.count
        )
        guard body.count <= Self.audioMaxBytes else {
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioReceiveFailedWithReason",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "file_too_large",
                bodyBytes: body.count
            )
            throw MacRecordingFileStoreError.fileTooLarge
        }

        try ensureLibraryDirectories()
        guard !sanitizedPathComponent(recordingID).isEmpty else {
            throw MacRecordingFileStoreError.invalidRecordingID
        }

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioReceiveRecordMissing",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "metadata_missing",
                bodyBytes: body.count
            )
            throw MacRecordingFileStoreError.metadataMissing
        }
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "audioReceiveRecordMatched",
            traceID: uploadTraceID,
            recordingID: recordingID,
            eventResult: "success",
            bodyBytes: body.count
        )

        let audioURL = recordingDirectoryURL.appendingPathComponent("audio.m4a", isDirectory: false).standardizedFileURL
        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        let metadataURL = recordingDirectoryURL.appendingPathComponent("metadata.json", isDirectory: false).standardizedFileURL

        guard isInsideRoot(recordingDirectoryURL), isInsideRoot(audioURL), isInsideRoot(receiveURL), isInsideRoot(metadataURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let incomingChecksum = MacSecurityUtilities.sha256Hex(body)
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "audioChecksumComputed",
            traceID: uploadTraceID,
            recordingID: recordingID,
            eventResult: "success",
            fileSize: Int64(body.count),
            bodyBytes: body.count
        )
        if fileManager.fileExists(atPath: audioURL.path) {
            return try handleExistingAudioUpload(
                recordingID: recordingID,
                recordingDirectoryURL: recordingDirectoryURL,
                audioURL: audioURL,
                receiveURL: receiveURL,
                requestedFileName: requestedFileName,
                sourceDevice: sourceDevice,
                incomingChecksum: incomingChecksum,
                incomingFileSize: Int64(body.count),
                uploadTraceID: uploadTraceID
            )
        }

        try validateNewAudioUpload(
            recordingID: recordingID,
            metadataURL: metadataURL,
            receiveURL: receiveURL,
            sourceDevice: sourceDevice,
            incomingFileSize: Int64(body.count)
        )

        do {
            let sanitizedOriginalName = sanitizedFileName(requestedFileName)
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioFileWriteStarted",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "begin",
                fileSize: Int64(body.count),
                bodyBytes: body.count
            )
            try body.write(to: audioURL, options: .atomic)
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioFileWriteCompleted",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                fileExists: fileManager.fileExists(atPath: audioURL.path),
                fileSize: Int64(body.count)
            )
            var record = try loadReceiveRecord(at: receiveURL)
            record.updatedAt = Date()
            record.sourceDeviceID = sourceDevice.id
            if record.sourceDeviceName.isEmpty {
                record.sourceDeviceName = sourceDevice.deviceName
            }
            record.audioFileName = "audio.m4a"
            record.originalAudioFileName = sanitizedOriginalName.isEmpty ? nil : sanitizedOriginalName
            record.status = "completed"
            record.processingStatus = "notStarted"
            record.checksum = incomingChecksum
            record.audioRelativePath = try relativePath(for: audioURL)
            record.fileSize = Int64(body.count)
            record.lastUploadError = nil
            record.lastUploadAttemptAt = nextUploadAttemptDate(after: record.lastUploadAttemptAt)
            record.localNetworkTransferState = nil
            record.localNetworkTransferProgressFraction = nil
            record.localNetworkTransferReceivedBytes = nil
            record.localNetworkTransferTotalBytes = nil
            record.localNetworkTransferStatusText = nil
            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordAudioPathUpdated",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                resolvedRelativePathToken: record.audioRelativePath,
                macReceiveState: record.status,
                audioRelativePathSet: record.audioRelativePath != nil
            )
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordAudioStatusUpdated",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                macReceiveState: record.status,
                audioRelativePathSet: record.audioRelativePath != nil
            )
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordAudioAvailable",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                fileExists: fileManager.fileExists(atPath: audioURL.path),
                fileSize: Int64(body.count),
                resolvedRelativePathToken: record.audioRelativePath,
                macReceiveState: record.status,
                audioRelativePathSet: record.audioRelativePath != nil
            )
            try appendReceiveLog(recordingID: recordingID, event: "audio_received", sourceDeviceID: sourceDevice.id, status: record.status)
            postInboxChanged()
            print("[RokuricsRecordingStore] audio saved: \(audioURL.path)")
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordSavedAfterAudio",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                resolvedRelativePathToken: try? relativePath(for: receiveURL),
                macReceiveState: record.status,
                audioRelativePathSet: record.audioRelativePath != nil
            )
            return RecordingReceiveResult(
                recordingID: recordingID,
                directoryURL: recordingDirectoryURL,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                receiveFileName: "receive.json",
                disposition: .acceptedNew,
                receiveStatus: record.status,
                processingStatus: record.processingStatus
            )
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            print("[RokuricsRecordingStore][ERROR] audio save failed: \(error)")
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioReceiveFailedWithReason",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "audio_storage_failed",
                safeErrorMessage: error.localizedDescription
            )
            throw MacRecordingFileStoreError.storageFailed("audio_storage_failed")
        }
    }

    func temporaryAudioUploadURL(recordingID: String) throws -> URL {
        try ensureLibraryDirectories()
        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let temporaryDirectoryURL = recordingDirectoryURL
            .appendingPathComponent("uploading", isDirectory: true)
            .standardizedFileURL
        let temporaryURL = temporaryDirectoryURL
            .appendingPathComponent("audio-\(UUID().uuidString.lowercased()).tmp", isDirectory: false)
            .standardizedFileURL

        guard isInsideAudioInboxDirectory(temporaryDirectoryURL),
              isInsideAudioInboxDirectory(temporaryURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        try fileManager.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        return temporaryURL
    }

    func discardTemporaryUpload(at temporaryURL: URL) {
        let url = temporaryURL.standardizedFileURL
        guard isInsideAudioInboxDirectory(url) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }

    func saveAudio(
        temporaryFileURL: URL,
        recordingID: String,
        requestedFileName: String?,
        sourceDevice: PairedDevice,
        checksum: String,
        fileSize: Int64,
        uploadTraceID: String? = nil
    ) throws -> RecordingReceiveResult {
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "audioReceiveRecordLookupStarted",
            traceID: uploadTraceID,
            recordingID: recordingID,
            eventResult: "begin",
            fileSize: fileSize
        )
        guard fileSize <= Int64(Self.audioMaxBytes) else {
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioReceiveFailedWithReason",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "file_too_large",
                fileSize: fileSize
            )
            throw MacRecordingFileStoreError.fileTooLarge
        }

        try ensureLibraryDirectories()
        guard !sanitizedPathComponent(recordingID).isEmpty else {
            throw MacRecordingFileStoreError.invalidRecordingID
        }

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioReceiveRecordMissing",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "metadata_missing",
                fileSize: fileSize
            )
            throw MacRecordingFileStoreError.metadataMissing
        }
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "audioReceiveRecordMatched",
            traceID: uploadTraceID,
            recordingID: recordingID,
            eventResult: "success",
            fileSize: fileSize
        )

        let audioURL = recordingDirectoryURL.appendingPathComponent("audio.m4a", isDirectory: false).standardizedFileURL
        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        let metadataURL = recordingDirectoryURL.appendingPathComponent("metadata.json", isDirectory: false).standardizedFileURL
        let tempURL = temporaryFileURL.standardizedFileURL

        guard isInsideRoot(recordingDirectoryURL),
              isInsideRoot(audioURL),
              isInsideRoot(receiveURL),
              isInsideRoot(metadataURL),
              isInsideAudioInboxDirectory(tempURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "audioChecksumComputed",
            traceID: uploadTraceID,
            recordingID: recordingID,
            eventResult: "success",
            fileSize: fileSize
        )

        if fileManager.fileExists(atPath: audioURL.path) {
            let result = try handleExistingAudioUpload(
                recordingID: recordingID,
                recordingDirectoryURL: recordingDirectoryURL,
                audioURL: audioURL,
                receiveURL: receiveURL,
                requestedFileName: requestedFileName,
                sourceDevice: sourceDevice,
                incomingChecksum: checksum,
                incomingFileSize: fileSize,
                uploadTraceID: uploadTraceID
            )
            discardTemporaryUpload(at: tempURL)
            return result
        }

        try validateNewAudioUpload(
            recordingID: recordingID,
            metadataURL: metadataURL,
            receiveURL: receiveURL,
            sourceDevice: sourceDevice,
            incomingFileSize: fileSize
        )

        do {
            let sanitizedOriginalName = sanitizedFileName(requestedFileName)
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioAtomicReplaceStarted",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "begin",
                fileSize: fileSize
            )
            try fileManager.moveItem(at: tempURL, to: audioURL)
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioAtomicReplaceCompleted",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                fileExists: fileManager.fileExists(atPath: audioURL.path),
                fileSize: fileSize
            )
            var record = try loadReceiveRecord(at: receiveURL)
            record.updatedAt = Date()
            record.sourceDeviceID = sourceDevice.id
            if record.sourceDeviceName.isEmpty {
                record.sourceDeviceName = sourceDevice.deviceName
            }
            record.audioFileName = "audio.m4a"
            record.originalAudioFileName = sanitizedOriginalName.isEmpty ? nil : sanitizedOriginalName
            record.status = "completed"
            record.processingStatus = "notStarted"
            record.checksum = checksum
            record.audioRelativePath = try relativePath(for: audioURL)
            record.fileSize = fileSize
            record.lastUploadError = nil
            record.lastUploadAttemptAt = nextUploadAttemptDate(after: record.lastUploadAttemptAt)
            record.localNetworkTransferState = nil
            record.localNetworkTransferProgressFraction = nil
            record.localNetworkTransferReceivedBytes = nil
            record.localNetworkTransferTotalBytes = nil
            record.localNetworkTransferStatusText = nil
            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordAudioPathUpdated",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                resolvedRelativePathToken: record.audioRelativePath,
                macReceiveState: record.status,
                audioRelativePathSet: record.audioRelativePath != nil
            )
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordAudioStatusUpdated",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                macReceiveState: record.status,
                audioRelativePathSet: record.audioRelativePath != nil
            )
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordAudioAvailable",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                fileExists: fileManager.fileExists(atPath: audioURL.path),
                fileSize: fileSize,
                resolvedRelativePathToken: record.audioRelativePath,
                macReceiveState: record.status,
                audioRelativePathSet: record.audioRelativePath != nil
            )
            try appendReceiveLog(recordingID: recordingID, event: "audio_received", sourceDeviceID: sourceDevice.id, status: record.status)
            postInboxChanged()
            print("[RokuricsRecordingStore] audio saved: \(audioURL.path)")
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordSavedAfterAudio",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "success",
                resolvedRelativePathToken: try? relativePath(for: receiveURL),
                macReceiveState: record.status,
                audioRelativePathSet: record.audioRelativePath != nil
            )
            return RecordingReceiveResult(
                recordingID: recordingID,
                directoryURL: recordingDirectoryURL,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                receiveFileName: "receive.json",
                disposition: .acceptedNew,
                receiveStatus: record.status,
                processingStatus: record.processingStatus
            )
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            print("[RokuricsRecordingStore][ERROR] audio save failed: \(error)")
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioReceiveFailedWithReason",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "audio_storage_failed",
                fileSize: fileSize,
                safeErrorMessage: error.localizedDescription
            )
            throw MacRecordingFileStoreError.storageFailed("audio_storage_failed")
        }
    }

    func startResumableAudioUpload(
        _ request: ResumableAudioUploadStartRequest,
        sourceDevice: PairedDevice
    ) throws -> ResumableAudioUploadSessionResponse {
        try ensureLibraryDirectories()
        try validateResumableRequest(recordingID: request.recordingID, totalBytes: request.totalBytes, chunkSize: request.chunkSize)

        let recordingResources = try recordingResources(for: request.recordingID)
        if let completed = try completedAudioResponseIfPresent(
            recordingID: request.recordingID,
            audioURL: recordingResources.audioURL,
            receiveURL: recordingResources.receiveURL,
            expectedChecksum: request.totalSHA256,
            expectedFileSize: request.totalBytes
        ) {
            return completed
        }

        try validateNewAudioUpload(
            recordingID: request.recordingID,
            metadataURL: recordingResources.metadataURL,
            receiveURL: recordingResources.receiveURL,
            sourceDevice: sourceDevice,
            incomingFileSize: request.totalBytes
        )

        if let existingSession = try existingResumableSession(recordingID: request.recordingID, sourceDeviceID: sourceDevice.id) {
            guard sessionMatchesStart(existingSession, request: request, sourceDevice: sourceDevice) else {
                try? markUploadConflict(
                    receiveURL: recordingResources.receiveURL,
                    recordingID: request.recordingID,
                    sourceDeviceID: sourceDevice.id,
                    error: "upload_session_conflict"
                )
                throw MacRecordingFileStoreError.sessionConflict
            }

            try updateReceiveTransferProgress(
                receiveURL: recordingResources.receiveURL,
                recordingID: request.recordingID,
                sourceDeviceID: sourceDevice.id,
                state: .transferring,
                receivedBytes: existingSession.receivedBytes,
                totalBytes: existingSession.expectedTotalBytes,
                statusText: transferStatusText(receivedBytes: existingSession.receivedBytes, totalBytes: existingSession.expectedTotalBytes)
            )
            return resumableResponse(
                disposition: .acceptedExisting,
                session: existingSession,
                completed: existingSession.status == "completed",
                finalAudioExists: false
            )
        }

        let sessionID = try generatedResumableSessionID(
            recordingID: request.recordingID,
            sourceDeviceID: sourceDevice.id,
            totalSHA256: request.totalSHA256
        )
        let sessionDirectoryURL = try resumableSessionDirectoryURL(sessionID: sessionID)
        let partURL = sessionDirectoryURL.appendingPathComponent("audio.part", isDirectory: false).standardizedFileURL
        let sessionURL = sessionDirectoryURL.appendingPathComponent("session.json", isDirectory: false).standardizedFileURL

        guard isInsideUploadSessionsDirectory(sessionDirectoryURL),
              isInsideUploadSessionsDirectory(partURL),
              isInsideUploadSessionsDirectory(sessionURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        if fileManager.fileExists(atPath: sessionURL.path) {
            let session = try loadResumableSession(at: sessionURL)
            guard sessionMatchesStart(session, request: request, sourceDevice: sourceDevice) else {
                try? markUploadConflict(
                    receiveURL: recordingResources.receiveURL,
                    recordingID: request.recordingID,
                    sourceDeviceID: sourceDevice.id,
                    error: "upload_session_conflict"
                )
                throw MacRecordingFileStoreError.sessionConflict
            }

            try updateReceiveTransferProgress(
                receiveURL: recordingResources.receiveURL,
                recordingID: request.recordingID,
                sourceDeviceID: sourceDevice.id,
                state: .transferring,
                receivedBytes: session.receivedBytes,
                totalBytes: session.expectedTotalBytes,
                statusText: transferStatusText(receivedBytes: session.receivedBytes, totalBytes: session.expectedTotalBytes)
            )
            return resumableResponse(
                disposition: .acceptedExisting,
                session: session,
                completed: session.status == "completed",
                finalAudioExists: false
            )
        }

        try fileManager.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: partURL.path) {
            fileManager.createFile(atPath: partURL.path, contents: nil)
        }

        let now = Date()
        let session = ResumableAudioSessionManifest(
            sessionID: sessionID,
            recordingID: request.recordingID,
            sourceDeviceID: sourceDevice.id,
            expectedTotalBytes: request.totalBytes,
            expectedTotalSHA256: request.totalSHA256,
            chunkSize: request.chunkSize,
            tempRelativePath: try relativePath(for: partURL),
            receivedBytes: 0,
            receivedChunks: [],
            createdAt: now,
            updatedAt: now,
            finalizedAt: nil,
            status: "active",
            lastError: nil
        )
        try saveResumableSession(session)
        try updateReceiveTransferProgress(
            receiveURL: recordingResources.receiveURL,
            recordingID: request.recordingID,
            sourceDeviceID: sourceDevice.id,
            state: .transferring,
            receivedBytes: 0,
            totalBytes: request.totalBytes,
            statusText: "传输中 0%"
        )
        try appendReceiveLog(recordingID: request.recordingID, event: "audio_session_started", sourceDeviceID: sourceDevice.id, status: "active")

        return resumableResponse(
            disposition: .acceptedNew,
            session: session,
            completed: false,
            finalAudioExists: false
        )
    }

    func resumableAudioUploadStatus(
        _ request: ResumableAudioUploadStatusRequest,
        sourceDevice: PairedDevice
    ) throws -> ResumableAudioUploadSessionResponse {
        try ensureLibraryDirectories()
        let sessionID = try safeResumableSessionID(request.sessionID)
        let recordingResources = try recordingResources(for: request.recordingID)
        if let completed = try completedAudioResponseIfPresent(
            recordingID: request.recordingID,
            audioURL: recordingResources.audioURL,
            receiveURL: recordingResources.receiveURL,
            expectedChecksum: request.totalSHA256,
            expectedFileSize: nil
        ) {
            return completed
        }

        let sessionURL = try resumableSessionJSONURL(sessionID: sessionID)
        guard fileManager.fileExists(atPath: sessionURL.path) else {
            return ResumableAudioUploadSessionResponse(
                ok: false,
                disposition: nil,
                status: "missingSession",
                sessionID: sessionID,
                confirmedBytes: 0,
                nextOffset: 0,
                chunkSize: nil,
                completed: false,
                finalAudioExists: false,
                chunkAccepted: nil,
                finalAudioRelativePath: nil,
                checksum: nil,
                fileSize: nil,
                receiveStatus: nil,
                processingStatus: nil,
                error: "upload_session_missing",
                reason: "Not Found"
            )
        }

        let session = try loadResumableSession(at: sessionURL)
        guard session.recordingID == request.recordingID,
              session.sourceDeviceID == sourceDevice.id,
              MacSecurityUtilities.constantTimeEquals(session.expectedTotalSHA256, request.totalSHA256) else {
            try? markUploadConflict(
                receiveURL: recordingResources.receiveURL,
                recordingID: request.recordingID,
                sourceDeviceID: sourceDevice.id,
                error: "upload_session_conflict"
            )
            throw MacRecordingFileStoreError.sessionConflict
        }
        guard session.status != "conflict" else {
            throw MacRecordingFileStoreError.sessionConflict
        }

        try updateReceiveTransferProgress(
            receiveURL: recordingResources.receiveURL,
            recordingID: request.recordingID,
            sourceDeviceID: sourceDevice.id,
            state: .transferring,
            receivedBytes: session.receivedBytes,
            totalBytes: session.expectedTotalBytes,
            statusText: transferStatusText(receivedBytes: session.receivedBytes, totalBytes: session.expectedTotalBytes)
        )
        return resumableResponse(
            disposition: .acceptedExisting,
            session: session,
            completed: session.status == "completed",
            finalAudioExists: false
        )
    }

    func appendResumableAudioChunk(
        recordingID: String,
        sessionID rawSessionID: String,
        offset: Int64,
        length: Int,
        chunkSHA256: String,
        totalSHA256: String,
        body: Data,
        sourceDevice: PairedDevice
    ) throws -> ResumableAudioUploadSessionResponse {
        try ensureLibraryDirectories()
        let sessionID = try safeResumableSessionID(rawSessionID)
        guard length == body.count,
              length > 0,
              length <= Self.resumableChunkMaxBytes,
              offset >= 0 else {
            throw MacRecordingFileStoreError.chunkOffsetMismatch
        }

        let bodyChecksum = MacSecurityUtilities.sha256Hex(body)
        guard MacSecurityUtilities.constantTimeEquals(bodyChecksum, chunkSHA256) else {
            throw MacRecordingFileStoreError.chunkChecksumMismatch
        }

        let recordingResources = try recordingResources(for: recordingID)
        if let completed = try completedAudioResponseIfPresent(
            recordingID: recordingID,
            audioURL: recordingResources.audioURL,
            receiveURL: recordingResources.receiveURL,
            expectedChecksum: totalSHA256,
            expectedFileSize: nil
        ) {
            return completed
        }

        let sessionURL = try resumableSessionJSONURL(sessionID: sessionID)
        guard fileManager.fileExists(atPath: sessionURL.path) else {
            throw MacRecordingFileStoreError.sessionMissing
        }

        var session = try loadResumableSession(at: sessionURL)
        guard session.recordingID == recordingID,
              session.sourceDeviceID == sourceDevice.id,
              MacSecurityUtilities.constantTimeEquals(session.expectedTotalSHA256, totalSHA256) else {
            try? markUploadConflict(
                receiveURL: recordingResources.receiveURL,
                recordingID: recordingID,
                sourceDeviceID: sourceDevice.id,
                error: "upload_session_conflict"
            )
            throw MacRecordingFileStoreError.sessionConflict
        }
        guard session.status == "active" else {
            throw MacRecordingFileStoreError.sessionConflict
        }

        if let existingChunk = session.receivedChunks.first(where: { $0.offset == offset }) {
            guard existingChunk.length == length,
                  MacSecurityUtilities.constantTimeEquals(existingChunk.sha256, chunkSHA256) else {
                try markResumableSessionError(&session, error: "recording_audio_conflict")
                try? markUploadConflict(
                    receiveURL: recordingResources.receiveURL,
                    recordingID: recordingID,
                    sourceDeviceID: sourceDevice.id,
                    error: "audio_conflict"
                )
                throw MacRecordingFileStoreError.audioConflict
            }

            return resumableResponse(
                disposition: .acceptedExisting,
                session: session,
                completed: session.status == "completed",
                finalAudioExists: false,
                chunkAccepted: true
            )
        }

        guard offset == session.receivedBytes else {
            try markResumableSessionError(&session, error: "upload_chunk_offset_mismatch")
            throw MacRecordingFileStoreError.chunkOffsetMismatch
        }

        let partURL = try resolvedResumablePartURL(for: session)
        guard fileSize(at: partURL) == offset else {
            try markResumableSessionError(&session, error: "upload_session_conflict")
            throw MacRecordingFileStoreError.sessionConflict
        }

        let handle = try FileHandle(forWritingTo: partURL)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        handle.write(body)

        session.receivedChunks.append(ResumableAudioChunkRecord(offset: offset, length: length, sha256: chunkSHA256))
        session.receivedBytes += Int64(length)
        session.updatedAt = Date()
        session.lastError = nil
        try saveResumableSession(session)
        try updateReceiveTransferProgress(
            receiveURL: recordingResources.receiveURL,
            recordingID: recordingID,
            sourceDeviceID: sourceDevice.id,
            state: .transferring,
            receivedBytes: session.receivedBytes,
            totalBytes: session.expectedTotalBytes,
            statusText: transferStatusText(receivedBytes: session.receivedBytes, totalBytes: session.expectedTotalBytes)
        )

        return resumableResponse(
            disposition: .acceptedNew,
            session: session,
            completed: false,
            finalAudioExists: false,
            chunkAccepted: true
        )
    }

    func finalizeResumableAudioUpload(
        _ request: ResumableAudioUploadFinalizeRequest,
        sourceDevice: PairedDevice
    ) throws -> ResumableAudioUploadSessionResponse {
        try ensureLibraryDirectories()
        let sessionID = try safeResumableSessionID(request.sessionID)
        try validateResumableRequest(recordingID: request.recordingID, totalBytes: request.totalBytes, chunkSize: 1)
        let recordingResources = try recordingResources(for: request.recordingID)

        if let completed = try completedAudioResponseIfPresent(
            recordingID: request.recordingID,
            audioURL: recordingResources.audioURL,
            receiveURL: recordingResources.receiveURL,
            expectedChecksum: request.totalSHA256,
            expectedFileSize: request.totalBytes
        ) {
            return completed
        }

        let sessionURL = try resumableSessionJSONURL(sessionID: sessionID)
        guard fileManager.fileExists(atPath: sessionURL.path) else {
            throw MacRecordingFileStoreError.sessionMissing
        }

        var session = try loadResumableSession(at: sessionURL)
        guard session.recordingID == request.recordingID,
              session.sourceDeviceID == sourceDevice.id,
              session.expectedTotalBytes == request.totalBytes,
              MacSecurityUtilities.constantTimeEquals(session.expectedTotalSHA256, request.totalSHA256) else {
            try? markUploadConflict(
                receiveURL: recordingResources.receiveURL,
                recordingID: request.recordingID,
                sourceDeviceID: sourceDevice.id,
                error: "upload_session_conflict"
            )
            throw MacRecordingFileStoreError.sessionConflict
        }
        guard session.status == "active" else {
            throw MacRecordingFileStoreError.sessionConflict
        }

        guard session.receivedBytes == request.totalBytes else {
            try markResumableSessionError(&session, error: "upload_session_incomplete")
            throw MacRecordingFileStoreError.sessionIncomplete
        }

        let partURL = try resolvedResumablePartURL(for: session)
        guard fileSize(at: partURL) == request.totalBytes else {
            try markResumableSessionError(&session, error: "upload_session_conflict")
            throw MacRecordingFileStoreError.sessionConflict
        }

        let checksum = try MacSecurityUtilities.sha256Hex(fileURL: partURL)
        guard MacSecurityUtilities.constantTimeEquals(checksum, request.totalSHA256) else {
            try markResumableSessionError(&session, error: "recording_audio_conflict")
            try? markUploadConflict(
                receiveURL: recordingResources.receiveURL,
                recordingID: request.recordingID,
                sourceDeviceID: sourceDevice.id,
                error: "audio_conflict"
            )
            throw MacRecordingFileStoreError.audioConflict
        }

        try validateNewAudioUpload(
            recordingID: request.recordingID,
            metadataURL: recordingResources.metadataURL,
            receiveURL: recordingResources.receiveURL,
            sourceDevice: sourceDevice,
            incomingFileSize: request.totalBytes
        )

        let sanitizedOriginalName = sanitizedFileName("audio.m4a")
        do {
            guard isInsideAudioInboxDirectory(recordingResources.audioURL) else {
                throw MacRecordingFileStoreError.unsafeDestination
            }
            try fileManager.moveItem(at: partURL, to: recordingResources.audioURL)
            var record = try loadReceiveRecord(at: recordingResources.receiveURL)
            record.updatedAt = Date()
            record.sourceDeviceID = sourceDevice.id
            if record.sourceDeviceName.isEmpty {
                record.sourceDeviceName = sourceDevice.deviceName
            }
            record.audioFileName = "audio.m4a"
            record.originalAudioFileName = sanitizedOriginalName.isEmpty ? nil : sanitizedOriginalName
            record.status = "completed"
            record.processingStatus = "notStarted"
            record.checksum = checksum
            record.audioRelativePath = try relativePath(for: recordingResources.audioURL)
            record.fileSize = request.totalBytes
            record.lastUploadError = nil
            record.lastUploadAttemptAt = nextUploadAttemptDate(after: record.lastUploadAttemptAt)
            record.localNetworkTransferState = nil
            record.localNetworkTransferProgressFraction = nil
            record.localNetworkTransferReceivedBytes = nil
            record.localNetworkTransferTotalBytes = nil
            record.localNetworkTransferStatusText = nil
            try Self.jsonEncoder.encode(record).write(to: recordingResources.receiveURL, options: .atomic)
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordAudioAvailable",
                traceID: UploadFlightRecorder.traceID(forRecordingID: request.recordingID) ?? UploadFlightRecorder.makeTraceID(),
                recordingID: request.recordingID,
                eventResult: "success",
                fileExists: fileManager.fileExists(atPath: recordingResources.audioURL.path),
                fileSize: request.totalBytes,
                resolvedRelativePathToken: record.audioRelativePath,
                macReceiveState: record.status,
                audioRelativePathSet: record.audioRelativePath != nil
            )

            session.updatedAt = Date()
            session.finalizedAt = Date()
            session.status = "completed"
            session.lastError = nil
            try saveResumableSession(session)
            try appendReceiveLog(recordingID: request.recordingID, event: "audio_resumable_finalized", sourceDeviceID: sourceDevice.id, status: record.status)
            postInboxChanged()

            return ResumableAudioUploadSessionResponse.accepted(
                disposition: .acceptedNew,
                status: session.status,
                sessionID: session.sessionID,
                confirmedBytes: request.totalBytes,
                nextOffset: request.totalBytes,
                chunkSize: session.chunkSize,
                completed: true,
                finalAudioExists: true,
                finalAudioRelativePath: record.audioRelativePath,
                checksum: checksum,
                fileSize: request.totalBytes,
                receiveStatus: record.status,
                processingStatus: record.processingStatus
            )
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            throw MacRecordingFileStoreError.storageFailed("audio_resumable_finalize_failed")
        }
    }

    func loadInboxItems(includeDeleted: Bool = false) -> [MacRecordingInboxItem] {
        guard fileManager.fileExists(atPath: audioInboxURL.path) else {
            return []
        }

        do {
            let dayDirectories = try fileManager.contentsOfDirectory(
                at: audioInboxURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var items: [MacRecordingInboxItem] = []
            for dayDirectory in dayDirectories {
                guard (try? dayDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    continue
                }

                let recordingDirectories = try fileManager.contentsOfDirectory(
                    at: dayDirectory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )

                for recordingDirectory in recordingDirectories {
                    guard (try? recordingDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                        continue
                    }

                    let receiveURL = recordingDirectory.appendingPathComponent("receive.json", isDirectory: false)
                    guard fileManager.fileExists(atPath: receiveURL.path),
                          let record = try? loadReceiveRecord(at: receiveURL) else {
                        continue
                    }

                    guard includeDeleted || !record.isDeleted else {
                        continue
                    }

                    let audioURL = recordingDirectory.appendingPathComponent("audio.m4a", isDirectory: false)
                    let hasAudio = fileManager.fileExists(atPath: audioURL.path)
                    let fileSize: Int64
                    if hasAudio,
                       let attributes = try? fileManager.attributesOfItem(atPath: audioURL.path),
                       let size = attributes[.size] as? NSNumber {
                        fileSize = size.int64Value
                    } else {
                        fileSize = record.fileSize
                    }

                    items.append(
                        inboxItem(
                            from: record,
                            hasAudio: hasAudio,
                            fileSize: fileSize,
                            receiveRelativePath: try? relativePath(for: receiveURL)
                        )
                    )
                }
            }

            return items.sorted { $0.receivedAt > $1.receivedAt }
        } catch {
            print("[RokuricsRecordingStore][ERROR] inbox load failed: \(error)")
            return []
        }
    }

    func loadTrashedInboxItems() -> [MacRecordingInboxItem] {
        loadInboxItems(includeDeleted: true)
            .filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? $0.receivedAt) > ($1.deletedAt ?? $1.receivedAt) }
    }

    func updateDisplayTitle(recordingID: String, rawTitle: String) throws -> MacRecordingInboxItem {
        try ensureLibraryDirectories()

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        guard isInsideRoot(receiveURL), fileManager.fileExists(atPath: receiveURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        do {
            var record = try loadReceiveRecord(at: receiveURL)
            let currentTitle = record.normalizedTitle.isEmpty ? record.originalTitle : record.normalizedTitle
            let title = RecordingTitleEditRules.normalizedTitle(rawTitle, fallback: currentTitle)
            record.normalizedTitle = title
            record.updatedAt = Date()
            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
            postInboxChanged()

            let audioURL = recordingDirectoryURL.appendingPathComponent("audio.m4a", isDirectory: false)
            let hasAudio = fileManager.fileExists(atPath: audioURL.path)
            let fileSize = fileSizeForInboxItem(record: record, audioURL: audioURL, hasAudio: hasAudio)
            return inboxItem(
                from: record,
                hasAudio: hasAudio,
                fileSize: fileSize,
                receiveRelativePath: try? relativePath(for: receiveURL)
            )
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            throw MacRecordingFileStoreError.storageFailed("recording_title_update_failed")
        }
    }

    func deleteRecording(recordingID: String) throws {
        try updateTrashState(recordingID: recordingID, isDeleted: true, deletedAt: Date(), event: "recording_moved_to_trash")
    }

    func restoreRecording(recordingID: String) throws {
        try updateTrashState(recordingID: recordingID, isDeleted: false, deletedAt: nil, event: "recording_restored")
    }

    func permanentlyDeleteRecording(recordingID: String) throws {
        try ensureLibraryDirectories()

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID)?.standardizedFileURL else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        guard isInsideAudioInboxDirectory(recordingDirectoryURL),
              recordingDirectoryURL.path != audioInboxURL.path else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        let record: RecordingReceiveRecord?
        if fileManager.fileExists(atPath: receiveURL.path) {
            record = try? loadReceiveRecord(at: receiveURL)
        } else {
            record = nil
        }

        var index = loadIndex()
        index.directoriesByRecordingID.removeValue(forKey: recordingID)
        try saveIndex(index)

        do {
            for transcriptDirectoryURL in transcriptDirectoriesToDelete(from: record) {
                try removeDirectoryIfExists(transcriptDirectoryURL, requiredRoot: transcriptsURL)
            }

            try removeDirectoryIfExists(recordingDirectoryURL, requiredRoot: audioInboxURL)
            if let record {
                try? appendReceiveLog(
                    recordingID: recordingID,
                    event: "recording_permanently_deleted",
                    sourceDeviceID: record.sourceDeviceID,
                    status: "deleted"
                )
            }
            postInboxChanged()
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            throw MacRecordingFileStoreError.storageFailed("recording_delete_failed")
        }
    }

    private func updateTrashState(recordingID: String, isDeleted: Bool, deletedAt: Date?, event: String) throws {
        try ensureLibraryDirectories()

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID)?.standardizedFileURL else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        guard isInsideAudioInboxDirectory(recordingDirectoryURL),
              recordingDirectoryURL.path != audioInboxURL.path else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        guard isInsideRoot(receiveURL), fileManager.fileExists(atPath: receiveURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        do {
            var record = try loadReceiveRecord(at: receiveURL)
            record.isDeleted = isDeleted
            record.deletedAt = deletedAt
            record.updatedAt = Date()
            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
            try? appendReceiveLog(
                recordingID: recordingID,
                event: event,
                sourceDeviceID: record.sourceDeviceID,
                status: isDeleted ? "deleted" : record.status
            )
            postInboxChanged()
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            throw MacRecordingFileStoreError.storageFailed("recording_trash_update_failed")
        }
    }

    func transcriptionSource(for recordingID: String) throws -> MacRecordingTranscriptionSource {
        try ensureLibraryDirectories()

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        guard isInsideRoot(receiveURL), fileManager.fileExists(atPath: receiveURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let record = try loadReceiveRecord(at: receiveURL)
        let fallbackAudioURL = recordingDirectoryURL.appendingPathComponent("audio.m4a", isDirectory: false).standardizedFileURL
        let audioURL = record.audioRelativePath
            .map { rootURL.appendingPathComponent($0, isDirectory: false).standardizedFileURL }
            ?? fallbackAudioURL

        guard isInsideRoot(audioURL), fileManager.fileExists(atPath: audioURL.path) else {
            throw MacRecordingFileStoreError.audioMissing
        }

        let metadataURL = rootURL.appendingPathComponent(record.metadataRelativePath, isDirectory: false).standardizedFileURL
        let safeMetadataURL = isInsideRoot(metadataURL) && fileManager.fileExists(atPath: metadataURL.path) ? metadataURL : nil

        return MacRecordingTranscriptionSource(
            recordingID: record.recordingID,
            title: record.normalizedTitle.isEmpty ? record.originalTitle : record.normalizedTitle,
            createdAt: record.createdAt,
            duration: record.duration,
            audioFileURL: audioURL,
            metadataFileURL: safeMetadataURL
        )
    }

    func noteGenerationSource(for recordingID: String) throws -> MacRecordingNoteGenerationSource {
        try ensureLibraryDirectories()

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        guard isInsideRoot(receiveURL), fileManager.fileExists(atPath: receiveURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let record = try loadReceiveRecord(at: receiveURL)
        let transcriptURL = resolvedRootFileURL(relativePath: record.transcriptRelativePath)
        let transcriptMarkdownURL = resolvedRootFileURL(relativePath: record.transcriptMarkdownRelativePath)
            ?? fallbackTranscriptMarkdownURL(from: record.transcriptRelativePath)

        return MacRecordingNoteGenerationSource(
            recordingID: record.recordingID,
            sanitizedRecordingID: record.sanitizedRecordingID,
            title: record.normalizedTitle.isEmpty ? record.originalTitle : record.normalizedTitle,
            createdAt: record.createdAt,
            duration: record.duration,
            transcriptionStatus: record.transcriptionStatus,
            transcriptRelativePath: record.transcriptRelativePath,
            transcriptMarkdownRelativePath: record.transcriptMarkdownRelativePath,
            transcriptionProviderID: record.transcriptionProviderID,
            transcriptionModelName: record.transcriptionModelName,
            transcriptURL: transcriptURL,
            transcriptMarkdownURL: transcriptMarkdownURL
        )
    }

    func updateTranscriptionStatus(
        recordingID: String,
        status: String,
        transcriptRelativePath: String?,
        transcriptMarkdownRelativePath: String?,
        providerID: String?,
        modelName: String?,
        startedAt: Date?,
        completedAt: Date?,
        errorMessage: String?,
        mode: ProcessingMode? = nil,
        chunks: [RecordingTranscriptionChunkRecord]? = nil
    ) throws {
        try ensureLibraryDirectories()

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        guard isInsideRoot(receiveURL), fileManager.fileExists(atPath: receiveURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        do {
            var record = try loadReceiveRecord(at: receiveURL)
            record.updatedAt = Date()
            record.transcriptionStatus = status
            record.processingStatus = status
            if let transcriptRelativePath {
                record.transcriptRelativePath = transcriptRelativePath
            } else if status == "notStarted" {
                record.transcriptRelativePath = nil
            }
            if let transcriptMarkdownRelativePath {
                record.transcriptMarkdownRelativePath = transcriptMarkdownRelativePath
            } else if status == "notStarted" {
                record.transcriptMarkdownRelativePath = nil
            }
            record.transcriptionProviderID = providerID
            record.transcriptionModelName = modelName
            record.transcriptionStartedAt = startedAt
            record.transcriptionCompletedAt = completedAt
            record.transcriptionError = errorMessage
            if let mode {
                record.transcriptionMode = mode
            }
            if let chunks {
                record.transcriptionChunks = chunks
            }

            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
            try appendReceiveLog(
                recordingID: recordingID,
                event: "transcription_\(status)",
                sourceDeviceID: record.sourceDeviceID,
                status: status
            )
            postInboxChanged()
            print("[RokuricsRecordingStore] transcription status updated: \(recordingID) -> \(status)")
            debugLogTranscriptionStatusUpdate(receiveURL: receiveURL, recordingID: recordingID, status: status, errorMessage: errorMessage)
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            print("[RokuricsRecordingStore][ERROR] transcription status update failed: \(error)")
            throw MacRecordingFileStoreError.storageFailed("transcription_status_update_failed")
        }
    }

    func updateNoteGenerationStatus(
        recordingID: String,
        status: String,
        noteRelativePath: String?,
        generatedAt: Date?,
        providerID: String?,
        modelName: String?,
        endpointDescription: String?,
        errorMessage: String?,
        mode: ProcessingMode? = nil,
        sections: [RecordingNoteSectionRecord]? = nil
    ) throws {
        try ensureLibraryDirectories()

        guard noteRelativePath == nil || resolvedRootFileURL(relativePath: noteRelativePath) != nil else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        guard isInsideRoot(receiveURL), fileManager.fileExists(atPath: receiveURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        do {
            var record = try loadReceiveRecord(at: receiveURL)
            let normalizedStatus = RecordingReceiveRecord.normalizedNoteStatus(status)
            record.updatedAt = Date()
            record.noteStatus = normalizedStatus

            if let noteRelativePath {
                record.noteRelativePath = noteRelativePath
            } else if normalizedStatus == "generated" || normalizedStatus == "notGenerated" {
                record.noteRelativePath = nil
            }

            if let generatedAt {
                record.noteGeneratedAt = generatedAt
            } else if normalizedStatus == "generated" || normalizedStatus == "notGenerated" {
                record.noteGeneratedAt = nil
            }

            if let providerID {
                record.noteProviderID = providerID
            }
            if let modelName {
                record.noteModelName = modelName
            }
            if let endpointDescription {
                record.noteEndpointDescription = endpointDescription
            }
            record.noteError = errorMessage
            if let mode {
                record.noteGenerationMode = mode
            }
            if let sections {
                record.noteSections = sections
            }

            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
            try appendReceiveLog(
                recordingID: recordingID,
                event: "note_generation_\(record.noteStatus)",
                sourceDeviceID: record.sourceDeviceID,
                status: record.noteStatus
            )
            postInboxChanged()
            print("[RokuricsRecordingStore] note status updated: \(recordingID) -> \(record.noteStatus)")
            debugLogNoteStatusUpdate(receiveURL: receiveURL, recordingID: recordingID, status: record.noteStatus, errorMessage: errorMessage)
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            print("[RokuricsRecordingStore][ERROR] note status update failed: \(error)")
            throw MacRecordingFileStoreError.storageFailed("note_status_update_failed")
        }
    }

    private func handleExistingMetadataUpload(
        _ metadata: IncomingRecordingMetadata,
        sourceDevice: PairedDevice,
        recordingDirectoryURL: URL,
        uploadTraceID: String? = nil
    ) throws -> RecordingReceiveResult {
        let metadataURL = recordingDirectoryURL.appendingPathComponent("metadata.json", isDirectory: false).standardizedFileURL
        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        let audioURL = recordingDirectoryURL.appendingPathComponent("audio.m4a", isDirectory: false).standardizedFileURL

        guard isInsideRoot(recordingDirectoryURL),
              isInsideRoot(metadataURL),
              isInsideRoot(receiveURL),
              isInsideRoot(audioURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        guard fileManager.fileExists(atPath: metadataURL.path),
              fileManager.fileExists(atPath: receiveURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let existingMetadata = try loadIncomingMetadata(at: metadataURL)
        guard metadataMatchesCoreIdentity(existingMetadata, metadata) else {
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordConflictDetected",
                traceID: uploadTraceID,
                recordingID: metadata.id,
                eventResult: "fail",
                reasonCode: "metadata_conflict"
            )
            try? markUploadConflict(
                receiveURL: receiveURL,
                recordingID: metadata.id,
                sourceDeviceID: sourceDevice.id,
                error: "metadata_conflict"
            )
            throw MacRecordingFileStoreError.metadataConflict
        }

        var record = try loadReceiveRecord(at: receiveURL)
        record.updatedAt = Date()
        record.sourceDeviceID = sourceDevice.id
        if record.sourceDeviceName.isEmpty {
            record.sourceDeviceName = sourceDevice.deviceName
        }
        normalizeUploadState(&record, hasAudio: fileManager.fileExists(atPath: audioURL.path))
        record.lastUploadError = nil
        record.lastUploadAttemptAt = nextUploadAttemptDate(after: record.lastUploadAttemptAt)
        try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "receiveRecordUpdatedMetadata",
            traceID: uploadTraceID,
            recordingID: metadata.id,
            eventResult: "success",
            resolvedRelativePathToken: record.metadataRelativePath,
            macReceiveState: record.status,
            audioRelativePathSet: record.audioRelativePath != nil
        )
        if record.audioRelativePath == nil {
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "receiveRecordWaitingForAudio",
                traceID: uploadTraceID,
                recordingID: metadata.id,
                eventResult: "success",
                macReceiveState: record.status,
                audioRelativePathSet: false
            )
        }
        try appendReceiveLog(recordingID: metadata.id, event: "metadata_idempotent", sourceDeviceID: sourceDevice.id, status: record.status)
        postInboxChanged()
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "receiveRecordSaved",
            traceID: uploadTraceID,
            recordingID: metadata.id,
            eventResult: "success",
            resolvedRelativePathToken: try? relativePath(for: receiveURL),
            macReceiveState: record.status,
            audioRelativePathSet: record.audioRelativePath != nil
        )

        return RecordingReceiveResult(
            recordingID: metadata.id,
            directoryURL: recordingDirectoryURL,
            metadataFileName: "metadata.json",
            audioFileName: record.audioFileName,
            receiveFileName: "receive.json",
            disposition: .acceptedExisting,
            receiveStatus: record.status,
            processingStatus: record.processingStatus
        )
    }

    private func handleExistingAudioUpload(
        recordingID: String,
        recordingDirectoryURL: URL,
        audioURL: URL,
        receiveURL: URL,
        requestedFileName: String?,
        sourceDevice: PairedDevice,
        incomingChecksum: String,
        incomingFileSize: Int64,
        uploadTraceID: String? = nil
    ) throws -> RecordingReceiveResult {
        guard isInsideRoot(recordingDirectoryURL),
              isInsideRoot(audioURL),
              isInsideRoot(receiveURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        guard fileManager.fileExists(atPath: receiveURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        var record = try loadReceiveRecord(at: receiveURL)
        let existingFileSize = fileSize(at: audioURL)
        let existingChecksum = try MacSecurityUtilities.sha256Hex(fileURL: audioURL)
        guard existingFileSize == incomingFileSize,
              MacSecurityUtilities.constantTimeEquals(existingChecksum, incomingChecksum) else {
            let conflictSummary = [
                "existingHash=\(String(existingChecksum.prefix(12)))",
                "incomingHash=\(String(incomingChecksum.prefix(12)))",
                "existingSize=\(existingFileSize)",
                "incomingSize=\(incomingFileSize)"
            ].joined(separator: ",")
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "macRejectExistingAudioDifferentChecksum",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "audio_conflict",
                fileSize: incomingFileSize,
                safeErrorMessage: conflictSummary
            )
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioConflictDetected",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "audio_conflict",
                fileSize: incomingFileSize,
                safeErrorMessage: conflictSummary
            )
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioReceiveFailedWithReason",
                traceID: uploadTraceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "audio_conflict",
                fileSize: incomingFileSize
            )
            try? markUploadConflict(
                receiveURL: receiveURL,
                recordingID: recordingID,
                sourceDeviceID: sourceDevice.id,
                error: "audio_conflict"
            )
            throw MacRecordingFileStoreError.audioConflict
        }

        record.updatedAt = Date()
        record.sourceDeviceID = sourceDevice.id
        if record.sourceDeviceName.isEmpty {
            record.sourceDeviceName = sourceDevice.deviceName
        }
        record.audioFileName = "audio.m4a"
        if record.originalAudioFileName == nil {
            let sanitizedOriginalName = sanitizedFileName(requestedFileName)
            record.originalAudioFileName = sanitizedOriginalName.isEmpty ? nil : sanitizedOriginalName
        }
        record.checksum = existingChecksum
        record.audioRelativePath = try relativePath(for: audioURL)
        record.fileSize = existingFileSize
        normalizeUploadState(&record, hasAudio: true)
        record.lastUploadError = nil
        record.lastUploadAttemptAt = nextUploadAttemptDate(after: record.lastUploadAttemptAt)
        record.localNetworkTransferState = nil
        record.localNetworkTransferProgressFraction = nil
        record.localNetworkTransferReceivedBytes = nil
        record.localNetworkTransferTotalBytes = nil
        record.localNetworkTransferStatusText = nil
        try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "receiveRecordAudioPathUpdated",
            traceID: uploadTraceID,
            recordingID: recordingID,
            eventResult: "success",
            reasonCode: "acceptedExisting",
            resolvedRelativePathToken: record.audioRelativePath,
            macReceiveState: record.status,
            audioRelativePathSet: record.audioRelativePath != nil
        )
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "receiveRecordAudioAvailable",
            traceID: uploadTraceID,
            recordingID: recordingID,
            eventResult: "success",
            reasonCode: "acceptedExisting",
            fileExists: fileManager.fileExists(atPath: audioURL.path),
            fileSize: existingFileSize,
            resolvedRelativePathToken: record.audioRelativePath,
            macReceiveState: record.status,
            audioRelativePathSet: record.audioRelativePath != nil
        )
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "receiveRecordSavedAfterAudio",
            traceID: uploadTraceID,
            recordingID: recordingID,
            eventResult: "success",
            reasonCode: "acceptedExisting",
            resolvedRelativePathToken: try? relativePath(for: receiveURL),
            macReceiveState: record.status,
            audioRelativePathSet: record.audioRelativePath != nil
        )
        try appendReceiveLog(recordingID: recordingID, event: "audio_idempotent", sourceDeviceID: sourceDevice.id, status: record.status)
        postInboxChanged()

        return RecordingReceiveResult(
            recordingID: recordingID,
            directoryURL: recordingDirectoryURL,
            metadataFileName: "metadata.json",
            audioFileName: "audio.m4a",
            receiveFileName: "receive.json",
            disposition: .acceptedExisting,
            receiveStatus: record.status,
            processingStatus: record.processingStatus
        )
    }

    private func validateNewAudioUpload(
        recordingID: String,
        metadataURL: URL,
        receiveURL: URL,
        sourceDevice: PairedDevice,
        incomingFileSize: Int64
    ) throws {
        let metadata = try loadIncomingMetadata(at: metadataURL)
        guard metadata.fileSize == incomingFileSize else {
            try? markUploadConflict(
                receiveURL: receiveURL,
                recordingID: recordingID,
                sourceDeviceID: sourceDevice.id,
                error: "audio_conflict"
            )
            throw MacRecordingFileStoreError.audioConflict
        }
    }

    private struct RecordingStorageResources {
        let directoryURL: URL
        let audioURL: URL
        let receiveURL: URL
        let metadataURL: URL
    }

    private func recordingResources(for recordingID: String) throws -> RecordingStorageResources {
        guard !sanitizedPathComponent(recordingID).isEmpty else {
            throw MacRecordingFileStoreError.invalidRecordingID
        }

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let audioURL = recordingDirectoryURL.appendingPathComponent("audio.m4a", isDirectory: false).standardizedFileURL
        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        let metadataURL = recordingDirectoryURL.appendingPathComponent("metadata.json", isDirectory: false).standardizedFileURL

        guard isInsideRoot(recordingDirectoryURL),
              isInsideAudioInboxDirectory(audioURL),
              isInsideRoot(receiveURL),
              isInsideRoot(metadataURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        guard fileManager.fileExists(atPath: metadataURL.path),
              fileManager.fileExists(atPath: receiveURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        return RecordingStorageResources(
            directoryURL: recordingDirectoryURL,
            audioURL: audioURL,
            receiveURL: receiveURL,
            metadataURL: metadataURL
        )
    }

    private func validateResumableRequest(recordingID: String, totalBytes: Int64, chunkSize: Int) throws {
        guard !sanitizedPathComponent(recordingID).isEmpty else {
            throw MacRecordingFileStoreError.invalidRecordingID
        }
        guard totalBytes > 0,
              totalBytes <= Self.resumableAudioMaxBytes,
              chunkSize > 0,
              chunkSize <= Self.resumableChunkMaxBytes else {
            throw MacRecordingFileStoreError.fileTooLarge
        }
    }

    private func completedAudioResponseIfPresent(
        recordingID: String,
        audioURL: URL,
        receiveURL: URL,
        expectedChecksum: String,
        expectedFileSize: Int64?
    ) throws -> ResumableAudioUploadSessionResponse? {
        guard fileManager.fileExists(atPath: audioURL.path) else {
            return nil
        }

        let existingFileSize = fileSize(at: audioURL)
        if let expectedFileSize, existingFileSize != expectedFileSize {
            throw MacRecordingFileStoreError.audioConflict
        }

        let existingChecksum = try MacSecurityUtilities.sha256Hex(fileURL: audioURL)
        guard MacSecurityUtilities.constantTimeEquals(existingChecksum, expectedChecksum) else {
            throw MacRecordingFileStoreError.audioConflict
        }

        var record = try loadReceiveRecord(at: receiveURL)
        record.audioFileName = "audio.m4a"
        record.checksum = existingChecksum
        record.audioRelativePath = try relativePath(for: audioURL)
        record.fileSize = existingFileSize
        normalizeUploadState(&record, hasAudio: true)
        record.lastUploadError = nil
        record.lastUploadAttemptAt = nextUploadAttemptDate(after: record.lastUploadAttemptAt)
        record.localNetworkTransferState = nil
        record.localNetworkTransferProgressFraction = nil
        record.localNetworkTransferReceivedBytes = nil
        record.localNetworkTransferTotalBytes = nil
        record.localNetworkTransferStatusText = nil
        try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)

        return ResumableAudioUploadSessionResponse.accepted(
            disposition: .acceptedExisting,
            status: "completed",
            sessionID: nil,
            confirmedBytes: existingFileSize,
            nextOffset: existingFileSize,
            chunkSize: nil,
            completed: true,
            finalAudioExists: true,
            finalAudioRelativePath: record.audioRelativePath,
            checksum: existingChecksum,
            fileSize: existingFileSize,
            receiveStatus: record.status,
            processingStatus: record.processingStatus
        )
    }

    private func generatedResumableSessionID(
        recordingID: String,
        sourceDeviceID: String,
        totalSHA256: String
    ) throws -> String {
        let sanitizedID = sanitizedPathComponent(recordingID)
        guard !sanitizedID.isEmpty else {
            throw MacRecordingFileStoreError.invalidRecordingID
        }

        let raw = "\(recordingID)|\(sourceDeviceID)|\(totalSHA256)"
        let digest = MacSecurityUtilities.sha256Hex(Data(raw.utf8))
        return try safeResumableSessionID("\(sanitizedID)-\(String(digest.prefix(16)))")
    }

    private func safeResumableSessionID(_ rawSessionID: String) throws -> String {
        let sessionID = rawSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty,
              !sessionID.contains(".."),
              !sessionID.contains("/"),
              !sessionID.contains("\\"),
              !sessionID.hasPrefix("."),
              sanitizedPathComponent(sessionID) == sessionID else {
            throw MacRecordingFileStoreError.invalidSession
        }

        return sessionID
    }

    private func resumableSessionDirectoryURL(sessionID rawSessionID: String) throws -> URL {
        let sessionID = try safeResumableSessionID(rawSessionID)
        let url = uploadSessionsURL.appendingPathComponent(sessionID, isDirectory: true).standardizedFileURL
        guard isInsideUploadSessionsDirectory(url) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }
        return url
    }

    private func resumableSessionJSONURL(sessionID rawSessionID: String) throws -> URL {
        let url = try resumableSessionDirectoryURL(sessionID: rawSessionID)
            .appendingPathComponent("session.json", isDirectory: false)
            .standardizedFileURL
        guard isInsideUploadSessionsDirectory(url) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }
        return url
    }

    private func loadResumableSession(at url: URL) throws -> ResumableAudioSessionManifest {
        guard isInsideUploadSessionsDirectory(url) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        let data = try Data(contentsOf: url)
        return try Self.jsonDecoder.decode(ResumableAudioSessionManifest.self, from: data)
    }

    private func saveResumableSession(_ session: ResumableAudioSessionManifest) throws {
        let sessionURL = try resumableSessionJSONURL(sessionID: session.sessionID)
        let directoryURL = sessionURL.deletingLastPathComponent().standardizedFileURL
        guard isInsideUploadSessionsDirectory(directoryURL),
              isInsideUploadSessionsDirectory(sessionURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Self.jsonEncoder.encode(session).write(to: sessionURL, options: .atomic)
    }

    private func resolvedResumablePartURL(for session: ResumableAudioSessionManifest) throws -> URL {
        guard let partURL = resolvedRootFileURL(relativePath: session.tempRelativePath),
              isInsideUploadSessionsDirectory(partURL),
              partURL.lastPathComponent == "audio.part" else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: partURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw MacRecordingFileStoreError.sessionMissing
        }

        return partURL
    }

    private func sessionMatchesStart(
        _ session: ResumableAudioSessionManifest,
        request: ResumableAudioUploadStartRequest,
        sourceDevice: PairedDevice
    ) -> Bool {
        session.recordingID == request.recordingID
            && session.sourceDeviceID == sourceDevice.id
            && session.expectedTotalBytes == request.totalBytes
            && MacSecurityUtilities.constantTimeEquals(session.expectedTotalSHA256, request.totalSHA256)
            && session.chunkSize == request.chunkSize
    }

    private func existingResumableSession(recordingID: String, sourceDeviceID: String) throws -> ResumableAudioSessionManifest? {
        guard fileManager.fileExists(atPath: uploadSessionsURL.path) else {
            return nil
        }

        let sessionDirectories = try fileManager.contentsOfDirectory(
            at: uploadSessionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for sessionDirectory in sessionDirectories {
            guard isInsideUploadSessionsDirectory(sessionDirectory),
                  (try? sessionDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            let sessionURL = sessionDirectory.appendingPathComponent("session.json", isDirectory: false).standardizedFileURL
            guard isInsideUploadSessionsDirectory(sessionURL),
                  let session = try? loadResumableSession(at: sessionURL),
                  session.recordingID == recordingID,
                  session.sourceDeviceID == sourceDeviceID,
                  session.status != "expired" else {
                continue
            }

            return session
        }

        return nil
    }

    private func resumableResponse(
        disposition: RecordingUploadDisposition,
        session: ResumableAudioSessionManifest,
        completed: Bool,
        finalAudioExists: Bool,
        chunkAccepted: Bool? = nil
    ) -> ResumableAudioUploadSessionResponse {
        ResumableAudioUploadSessionResponse.accepted(
            disposition: disposition,
            status: session.status,
            sessionID: session.sessionID,
            confirmedBytes: session.receivedBytes,
            nextOffset: session.receivedBytes,
            chunkSize: session.chunkSize,
            completed: completed,
            finalAudioExists: finalAudioExists,
            chunkAccepted: chunkAccepted
        )
    }

    private func markResumableSessionError(
        _ session: inout ResumableAudioSessionManifest,
        error: String
    ) throws {
        session.updatedAt = Date()
        session.lastError = error
        if error.contains("conflict") {
            session.status = "conflict"
        }
        try saveResumableSession(session)
    }

    private func normalizeUploadState(_ record: inout RecordingReceiveRecord, hasAudio: Bool) {
        if hasAudio {
            record.status = "completed"
            if record.processingStatus == "awaitingAudio" {
                record.processingStatus = "notStarted"
            }
            record.localNetworkTransferState = nil
            record.localNetworkTransferProgressFraction = nil
            record.localNetworkTransferReceivedBytes = nil
            record.localNetworkTransferTotalBytes = nil
            record.localNetworkTransferStatusText = nil
        } else {
            record.status = "metadataReceived"
            record.processingStatus = "awaitingAudio"
            record.audioFileName = nil
            record.audioRelativePath = nil
            record.checksum = nil
        }
    }

    private func markUploadConflict(
        receiveURL: URL,
        recordingID: String,
        sourceDeviceID: String,
        error: String
    ) throws {
        guard isInsideRoot(receiveURL), fileManager.fileExists(atPath: receiveURL.path) else {
            return
        }

        var record = try loadReceiveRecord(at: receiveURL)
        record.updatedAt = Date()
        record.lastUploadError = error
        record.lastUploadAttemptAt = nextUploadAttemptDate(after: record.lastUploadAttemptAt)
        record.localNetworkTransferState = error.contains("conflict")
            ? LocalNetworkTransferState.conflict.rawValue
            : LocalNetworkTransferState.failed.rawValue
        record.localNetworkTransferStatusText = error.contains("conflict") ? "传输冲突" : "传输失败，可重试"
        record.localNetworkTransferTotalBytes = record.localNetworkTransferTotalBytes ?? (record.fileSize > 0 ? record.fileSize : nil)
        try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
        try appendReceiveLog(recordingID: recordingID, event: error, sourceDeviceID: sourceDeviceID, status: record.status)
        postInboxChanged()
    }

    private func updateReceiveTransferProgress(
        receiveURL: URL,
        recordingID: String,
        sourceDeviceID: String,
        state: LocalNetworkTransferState,
        receivedBytes: Int64,
        totalBytes: Int64,
        statusText: String?
    ) throws {
        guard isInsideRoot(receiveURL), fileManager.fileExists(atPath: receiveURL.path) else {
            return
        }

        var record = try loadReceiveRecord(at: receiveURL)
        record.updatedAt = Date()
        record.sourceDeviceID = sourceDeviceID
        if state == .complete {
            record.localNetworkTransferState = nil
            record.localNetworkTransferProgressFraction = nil
            record.localNetworkTransferReceivedBytes = nil
            record.localNetworkTransferTotalBytes = nil
            record.localNetworkTransferStatusText = nil
        } else {
            let clampedReceivedBytes = min(max(receivedBytes, 0), totalBytes)
            record.localNetworkTransferState = state.rawValue
            record.localNetworkTransferProgressFraction = totalBytes > 0
                ? min(max(Double(clampedReceivedBytes) / Double(totalBytes), 0), 1)
                : nil
            record.localNetworkTransferReceivedBytes = clampedReceivedBytes
            record.localNetworkTransferTotalBytes = totalBytes
            record.localNetworkTransferStatusText = statusText
        }
        try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
        postInboxChanged()
    }

    private func transferStatusText(receivedBytes: Int64, totalBytes: Int64) -> String {
        guard totalBytes > 0 else {
            return "传输中"
        }
        let percent = Int((Double(receivedBytes) / Double(totalBytes) * 100).rounded())
        return "传输中 \(min(max(percent, 0), 100))%"
    }

    private func nextUploadAttemptDate(after previous: Date?) -> Date {
        let now = Date()
        guard let previous else {
            return now
        }

        return now.timeIntervalSince(previous) >= 1 ? now : previous.addingTimeInterval(1)
    }

    private func ensureLibraryDirectories() throws {
        let directories = [
            rootURL,
            rootURL.appendingPathComponent("audio", isDirectory: true),
            audioInboxURL,
            uploadSessionsURL,
            rootURL.appendingPathComponent("audio", isDirectory: true).appendingPathComponent("processing", isDirectory: true),
            rootURL.appendingPathComponent("audio", isDirectory: true).appendingPathComponent("processed", isDirectory: true),
            rootURL.appendingPathComponent("audio", isDirectory: true).appendingPathComponent("archived", isDirectory: true),
            transcriptsURL,
            rootURL.appendingPathComponent("notes", isDirectory: true),
            rootURL.appendingPathComponent("exports", isDirectory: true),
            rootURL.appendingPathComponent("metadata", isDirectory: true),
            rootURL.appendingPathComponent("system", isDirectory: true)
        ]

        do {
            for directory in directories {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } catch {
            throw MacRecordingFileStoreError.unableToCreateDirectory
        }
    }

    private func metadataDataSizeIsAllowed(_ metadata: IncomingRecordingMetadata) -> Bool {
        guard let data = try? Self.jsonEncoder.encode(metadata) else {
            return false
        }

        return data.count <= Self.metadataMaxBytes
    }

    private func recordingDirectoryURL(for recordingID: String) -> URL? {
        let index = loadIndex()
        if let relativePath = index.directoriesByRecordingID[recordingID] {
            let url = rootURL.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
            return isInsideRoot(url) ? url : nil
        }

        return scanRecordingDirectory(recordingID: recordingID)
    }

    private func scanRecordingDirectory(recordingID: String) -> URL? {
        let sanitizedID = sanitizedPathComponent(recordingID)
        guard !sanitizedID.isEmpty,
              let dayDirectories = try? fileManager.contentsOfDirectory(at: audioInboxURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }

        for dayDirectory in dayDirectories {
            let candidate = dayDirectory.appendingPathComponent(sanitizedID, isDirectory: true).standardizedFileURL
            if fileManager.fileExists(atPath: candidate.path), isInsideRoot(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func loadReceiveRecord(at url: URL) throws -> RecordingReceiveRecord {
        let data = try Data(contentsOf: url)
        return try Self.jsonDecoder.decode(RecordingReceiveRecord.self, from: data)
    }

    private func loadIncomingMetadata(at url: URL) throws -> IncomingRecordingMetadata {
        let data = try Data(contentsOf: url)
        return try Self.jsonDecoder.decode(IncomingRecordingMetadata.self, from: data)
    }

    private func metadataMatchesCoreIdentity(
        _ existing: IncomingRecordingMetadata,
        _ incoming: IncomingRecordingMetadata
    ) -> Bool {
        existing.id == incoming.id
            && existing.originalFileName == incoming.originalFileName
            && existing.relativeAudioPath == incoming.relativeAudioPath
            && timestampsMatch(existing.createdAt, incoming.createdAt)
            && timestampsMatch(existing.endedAt, incoming.endedAt)
            && abs(existing.duration - incoming.duration) < 0.001
            && existing.format == incoming.format
            && existing.codec == incoming.codec
            && abs(existing.sampleRate - incoming.sampleRate) < 0.001
            && existing.channels == incoming.channels
            && existing.bitrate == incoming.bitrate
            && existing.fileSize == incoming.fileSize
    }

    private func timestampsMatch(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 0.001
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return -1
        }

        return size.int64Value
    }

    private func inboxItem(
        from record: RecordingReceiveRecord,
        hasAudio: Bool,
        fileSize: Int64,
        receiveRelativePath: String? = nil
    ) -> MacRecordingInboxItem {
        MacRecordingInboxItem(
            id: record.recordingID,
            title: record.normalizedTitle.isEmpty ? record.originalTitle : record.normalizedTitle,
            receivedAt: record.receivedAt,
            duration: record.duration,
            fileSize: fileSize,
            sourceDeviceID: record.sourceDeviceID,
            sourceDeviceName: record.sourceDeviceName.isEmpty ? "iPhone" : record.sourceDeviceName,
            audioChecksum: record.checksum,
            transcriptionStatus: record.transcriptionStatus,
            noteStatus: record.noteStatus,
            receiveStatus: record.status,
            hasAudio: hasAudio,
            audioRelativePath: record.audioRelativePath,
            receiveRelativePath: receiveRelativePath,
            transcriptRelativePath: record.transcriptRelativePath,
            transcriptMarkdownRelativePath: record.transcriptMarkdownRelativePath,
            transcriptionError: record.transcriptionError,
            studyFiling: record.studyFiling,
            isDeleted: record.isDeleted,
            deletedAt: record.deletedAt,
            noteRelativePath: record.noteRelativePath,
            noteError: record.noteError,
            transferProgress: receiveTransferProgress(from: record)
        )
    }

    private func receiveTransferProgress(from record: RecordingReceiveRecord) -> LocalNetworkTransferProgress? {
        guard let stateRaw = record.localNetworkTransferState,
              let state = LocalNetworkTransferState(rawValue: stateRaw),
              state.isVisibleInActionArea else {
            return nil
        }

        return LocalNetworkTransferProgress(
            objectID: "recordingAudio:\(record.recordingID)",
            objectKind: LocalNetworkSyncObjectKind.recordingAudio.rawValue,
            state: state,
            progressFraction: record.localNetworkTransferProgressFraction,
            receivedBytes: record.localNetworkTransferReceivedBytes,
            totalBytes: record.localNetworkTransferTotalBytes,
            sourceDeviceID: record.sourceDeviceID,
            statusText: record.localNetworkTransferStatusText
        )
    }

    private func fileSizeForInboxItem(record: RecordingReceiveRecord, audioURL: URL, hasAudio: Bool) -> Int64 {
        if hasAudio,
           let attributes = try? fileManager.attributesOfItem(atPath: audioURL.path),
           let size = attributes[.size] as? NSNumber {
            return size.int64Value
        }

        return record.fileSize
    }

    private func loadIndex() -> RecordingIndex {
        guard fileManager.fileExists(atPath: metadataIndexURL.path),
              let data = try? Data(contentsOf: metadataIndexURL),
              let index = try? Self.jsonDecoder.decode(RecordingIndex.self, from: data) else {
            return RecordingIndex()
        }

        return index
    }

    private func saveIndex(_ index: RecordingIndex) throws {
        guard isInsideRoot(metadataIndexURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        try fileManager.createDirectory(at: metadataIndexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.jsonEncoder.encode(index).write(to: metadataIndexURL, options: .atomic)
    }

    private func appendReceiveLog(recordingID: String, event: String, sourceDeviceID: String, status: String) throws {
        var entries: [RecordingReceiveLogEntry] = []
        if fileManager.fileExists(atPath: receiveLogURL.path),
           let data = try? Data(contentsOf: receiveLogURL),
           let decoded = try? Self.jsonDecoder.decode([RecordingReceiveLogEntry].self, from: data) {
            entries = decoded
        }

        entries.append(RecordingReceiveLogEntry(
            recordingID: recordingID,
            event: event,
            at: Date(),
            sourceDeviceIDPrefix: String(sourceDeviceID.prefix(12)),
            status: status
        ))

        if entries.count > 500 {
            entries = Array(entries.suffix(500))
        }

        guard isInsideRoot(receiveLogURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        try fileManager.createDirectory(at: receiveLogURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.jsonEncoder.encode(entries).write(to: receiveLogURL, options: .atomic)
    }

    private func relativePath(for url: URL) throws -> String {
        let rootPath = rootURL.standardizedFileURL.path.hasSuffix("/") ? rootURL.standardizedFileURL.path : "\(rootURL.standardizedFileURL.path)/"
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        return String(filePath.dropFirst(rootPath.count))
    }

    private func resolvedRootFileURL(relativePath: String?) -> URL? {
        guard let relativePath else {
            return nil
        }

        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty,
              !trimmedPath.hasPrefix("/") else {
            return nil
        }

        let url = rootURL.appendingPathComponent(trimmedPath, isDirectory: false).standardizedFileURL
        return isInsideRoot(url) ? url : nil
    }

    private func fallbackTranscriptMarkdownURL(from transcriptRelativePath: String?) -> URL? {
        guard let transcriptRelativePath,
              !transcriptRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let directory = (transcriptRelativePath as NSString).deletingLastPathComponent
        guard !directory.isEmpty else {
            return nil
        }

        let markdownRelativePath = (directory as NSString).appendingPathComponent("transcript.md")
        return resolvedRootFileURL(relativePath: markdownRelativePath)
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private func isInsideAudioInboxDirectory(_ url: URL) -> Bool {
        isInside(url, requiredRoot: audioInboxURL)
    }

    private func isInsideUploadSessionsDirectory(_ url: URL) -> Bool {
        isInside(url.resolvingSymlinksInPath(), requiredRoot: uploadSessionsURL.resolvingSymlinksInPath())
    }

    private func isInsideTranscriptsDirectory(_ url: URL) -> Bool {
        isInside(url, requiredRoot: transcriptsURL)
    }

    private func isInside(_ url: URL, requiredRoot: URL) -> Bool {
        let rootPath = requiredRoot.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private func transcriptDirectoriesToDelete(from record: RecordingReceiveRecord?) -> [URL] {
        guard let record else {
            return []
        }

        let relativePaths = [
            record.transcriptRelativePath,
            record.transcriptMarkdownRelativePath
        ]
        .compactMap { $0 }

        var directories: [URL] = []
        for relativePath in relativePaths {
            let url = rootURL.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
            guard isInsideTranscriptsDirectory(url) else {
                continue
            }

            let directoryURL = url.deletingLastPathComponent().standardizedFileURL
            guard isInsideTranscriptsDirectory(directoryURL),
                  directoryURL.path != transcriptsURL.path,
                  !directories.contains(directoryURL) else {
                continue
            }

            directories.append(directoryURL)
        }

        return directories
    }

    private func removeDirectoryIfExists(_ url: URL, requiredRoot: URL) throws {
        let targetURL = url.standardizedFileURL
        guard isInside(targetURL, requiredRoot: requiredRoot),
              targetURL.path != requiredRoot.standardizedFileURL.path else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
            return
        }

        guard isDirectory.boolValue else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        do {
            try fileManager.removeItem(at: targetURL)
        } catch {
            throw MacRecordingFileStoreError.storageFailed("recording_delete_failed")
        }
    }

    private func sanitizedPathComponent(_ value: String) -> String {
        sanitizedFileName(value)
            .replacingOccurrences(of: ".", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
    }

    private func sanitizedFileName(_ value: String?) -> String {
        let rawName = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lastPathComponent = ((rawName.isEmpty ? "recording" : rawName) as NSString).lastPathComponent
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return lastPathComponent.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private func normalizeTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名录音" : trimmed
    }

    private func postInboxChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.inboxDidChangeNotification, object: nil)
        }
    }

    private func debugLogTranscriptionStatusUpdate(
        receiveURL: URL,
        recordingID: String,
        status: String,
        errorMessage: String?
    ) {
        #if DEBUG
        print(
            "[RokuricsRecordingStore] receive.json updated: " +
            "recordingID=\(recordingID), " +
            "status=\(status), " +
            "receiveJSON=\(receiveURL.path), " +
            "errorSummary=\(errorMessage.map { String($0.prefix(1000)) } ?? "nil")"
        )
        #endif
    }

    private func debugLogNoteStatusUpdate(
        receiveURL: URL,
        recordingID: String,
        status: String,
        errorMessage: String?
    ) {
        #if DEBUG
        print(
            "[RokuricsRecordingStore] receive.json note updated: " +
            "recordingID=\(recordingID), " +
            "noteStatus=\(status), " +
            "receiveJSON=\(receiveURL.path), " +
            "errorSummary=\(errorMessage.map { String($0.prefix(1000)) } ?? "nil")"
        )
        #endif
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
