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
    case audioAlreadyExists
    case audioMissing
    case fileTooLarge
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
        case .audioAlreadyExists:
            return "recording_audio_exists"
        case .audioMissing:
            return "recording_audio_missing"
        case .fileTooLarge:
            return "file_too_large"
        case .storageFailed(let reason):
            return reason
        }
    }

    var responseStatusCode: Int {
        switch self {
        case .fileTooLarge:
            return 413
        case .metadataAlreadyExists, .audioAlreadyExists:
            return 409
        case .invalidRecordingID, .unsafeDestination, .metadataMissing, .audioMissing:
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
    static let inboxDidChangeNotification = Notification.Name("RokuricsMacRecordingInboxDidChange")

    private struct RecordingIndex: Codable {
        var directoriesByRecordingID: [String: String] = [:]
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let audioInboxURL: URL
    private let transcriptsURL: URL
    private let metadataIndexURL: URL
    private let receiveLogURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.rootURL = applicationSupportURL
                .appendingPathComponent("Rokurics", isDirectory: true)
                .standardizedFileURL
        }
        audioInboxURL = self.rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
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

    func saveMetadata(_ metadata: IncomingRecordingMetadata, sourceDevice: PairedDevice) throws -> RecordingReceiveResult {
        guard metadataDataSizeIsAllowed(metadata) else {
            throw MacRecordingFileStoreError.fileTooLarge
        }

        try ensureLibraryDirectories()
        let sanitizedID = sanitizedPathComponent(metadata.id)
        guard !sanitizedID.isEmpty else {
            throw MacRecordingFileStoreError.invalidRecordingID
        }

        var index = loadIndex()
        guard index.directoriesByRecordingID[metadata.id] == nil else {
            throw MacRecordingFileStoreError.metadataAlreadyExists
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
                processingStatus: "notStarted",
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
                metadataRelativePath: try relativePath(for: metadataURL)
            )
            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)

            index.directoriesByRecordingID[metadata.id] = try relativePath(for: recordingDirectoryURL)
            try saveIndex(index)
            try appendReceiveLog(recordingID: metadata.id, event: "metadata_received", sourceDeviceID: sourceDevice.id, status: record.status)
            postInboxChanged()
            print("[RokuricsRecordingStore] metadata saved: \(metadataURL.path)")
            return RecordingReceiveResult(
                recordingID: metadata.id,
                directoryURL: recordingDirectoryURL,
                metadataFileName: "metadata.json",
                audioFileName: nil,
                receiveFileName: "receive.json"
            )
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            print("[RokuricsRecordingStore][ERROR] metadata save failed: \(error)")
            throw MacRecordingFileStoreError.storageFailed("metadata_storage_failed")
        }
    }

    func saveAudio(body: Data, recordingID: String, requestedFileName: String?, sourceDevice: PairedDevice) throws -> RecordingReceiveResult {
        guard body.count <= Self.audioMaxBytes else {
            throw MacRecordingFileStoreError.fileTooLarge
        }

        try ensureLibraryDirectories()
        guard !sanitizedPathComponent(recordingID).isEmpty else {
            throw MacRecordingFileStoreError.invalidRecordingID
        }

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        let audioURL = recordingDirectoryURL.appendingPathComponent("audio.m4a", isDirectory: false).standardizedFileURL
        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false).standardizedFileURL
        let metadataURL = recordingDirectoryURL.appendingPathComponent("metadata.json", isDirectory: false).standardizedFileURL

        guard isInsideRoot(recordingDirectoryURL), isInsideRoot(audioURL), isInsideRoot(receiveURL), isInsideRoot(metadataURL) else {
            throw MacRecordingFileStoreError.unsafeDestination
        }

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

        guard !fileManager.fileExists(atPath: audioURL.path) else {
            throw MacRecordingFileStoreError.audioAlreadyExists
        }

        do {
            let sanitizedOriginalName = sanitizedFileName(requestedFileName)
            try body.write(to: audioURL, options: .atomic)
            var record = try loadReceiveRecord(at: receiveURL)
            record.updatedAt = Date()
            record.sourceDeviceID = sourceDevice.id
            if record.sourceDeviceName.isEmpty {
                record.sourceDeviceName = sourceDevice.deviceName
            }
            record.audioFileName = "audio.m4a"
            record.originalAudioFileName = sanitizedOriginalName.isEmpty ? nil : sanitizedOriginalName
            record.status = "received"
            record.processingStatus = "notStarted"
            record.checksum = MacSecurityUtilities.sha256Hex(body)
            record.audioRelativePath = try relativePath(for: audioURL)
            record.fileSize = Int64(body.count)
            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
            try appendReceiveLog(recordingID: recordingID, event: "audio_received", sourceDeviceID: sourceDevice.id, status: record.status)
            postInboxChanged()
            print("[RokuricsRecordingStore] audio saved: \(audioURL.path)")
            return RecordingReceiveResult(
                recordingID: recordingID,
                directoryURL: recordingDirectoryURL,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                receiveFileName: "receive.json"
            )
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            print("[RokuricsRecordingStore][ERROR] audio save failed: \(error)")
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
        fileSize: Int64
    ) throws -> RecordingReceiveResult {
        guard fileSize <= Int64(Self.audioMaxBytes) else {
            throw MacRecordingFileStoreError.fileTooLarge
        }

        try ensureLibraryDirectories()
        guard !sanitizedPathComponent(recordingID).isEmpty else {
            throw MacRecordingFileStoreError.invalidRecordingID
        }

        guard let recordingDirectoryURL = recordingDirectoryURL(for: recordingID) else {
            throw MacRecordingFileStoreError.metadataMissing
        }

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

        guard !fileManager.fileExists(atPath: audioURL.path) else {
            throw MacRecordingFileStoreError.audioAlreadyExists
        }

        do {
            let sanitizedOriginalName = sanitizedFileName(requestedFileName)
            try fileManager.moveItem(at: tempURL, to: audioURL)
            var record = try loadReceiveRecord(at: receiveURL)
            record.updatedAt = Date()
            record.sourceDeviceID = sourceDevice.id
            if record.sourceDeviceName.isEmpty {
                record.sourceDeviceName = sourceDevice.deviceName
            }
            record.audioFileName = "audio.m4a"
            record.originalAudioFileName = sanitizedOriginalName.isEmpty ? nil : sanitizedOriginalName
            record.status = "received"
            record.processingStatus = "notStarted"
            record.checksum = checksum
            record.audioRelativePath = try relativePath(for: audioURL)
            record.fileSize = fileSize
            try Self.jsonEncoder.encode(record).write(to: receiveURL, options: .atomic)
            try appendReceiveLog(recordingID: recordingID, event: "audio_received", sourceDeviceID: sourceDevice.id, status: record.status)
            postInboxChanged()
            print("[RokuricsRecordingStore] audio saved: \(audioURL.path)")
            return RecordingReceiveResult(
                recordingID: recordingID,
                directoryURL: recordingDirectoryURL,
                metadataFileName: "metadata.json",
                audioFileName: "audio.m4a",
                receiveFileName: "receive.json"
            )
        } catch let error as MacRecordingFileStoreError {
            throw error
        } catch {
            print("[RokuricsRecordingStore][ERROR] audio save failed: \(error)")
            throw MacRecordingFileStoreError.storageFailed("audio_storage_failed")
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

    private func ensureLibraryDirectories() throws {
        let directories = [
            rootURL,
            rootURL.appendingPathComponent("audio", isDirectory: true),
            audioInboxURL,
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
            sourceDeviceName: record.sourceDeviceName.isEmpty ? "iPhone" : record.sourceDeviceName,
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
            noteError: record.noteError
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
