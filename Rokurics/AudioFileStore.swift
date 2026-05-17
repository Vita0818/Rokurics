//
//  AudioFileStore.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import Foundation

enum AudioFileStoreError: LocalizedError {
    case documentsDirectoryUnavailable
    case directoryCreationFailed(URL, Error)
    case fileRemovalFailed(URL, Error)
    case pathOutsideRokuricsDirectory(URL)
    case fileAttributesFailed(URL, Error)
    case metadataReadFailed(URL, Error)
    case metadataWriteFailed(URL, Error)
    case metadataDirectoryReadFailed(URL, Error)
    case recordingNotFound(String)

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return "无法访问本地 Documents 目录。"
        case let .directoryCreationFailed(url, error):
            return "录音目录创建失败：\(url.path) - \(error.localizedDescription)"
        case let .fileRemovalFailed(url, error):
            return "旧录音文件删除失败：\(url.path) - \(error.localizedDescription)"
        case let .pathOutsideRokuricsDirectory(url):
            return "文件不在 Rokurics 本地目录中：\(url.path)"
        case let .fileAttributesFailed(url, error):
            return "读取文件信息失败：\(url.path) - \(error.localizedDescription)"
        case let .metadataReadFailed(url, error):
            return "metadata 读取失败：\(url.path) - \(error.localizedDescription)"
        case let .metadataWriteFailed(url, error):
            return "metadata 写入失败：\(url.path) - \(error.localizedDescription)"
        case let .metadataDirectoryReadFailed(url, error):
            return "metadata 目录读取失败：\(url.path) - \(error.localizedDescription)"
        case let .recordingNotFound(id):
            return "未找到录音：\(id)"
        }
    }
}

struct AudioFileStore {
    private let fileManager: FileManager
    private let rootDirectoryOverride: URL?

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        rootDirectoryOverride = rootDirectoryURL?.standardizedFileURL
    }

    func baseDirectory() throws -> URL {
        if let rootDirectoryOverride {
            do {
                try fileManager.createDirectory(at: rootDirectoryOverride, withIntermediateDirectories: true)
            } catch {
                throw AudioFileStoreError.directoryCreationFailed(rootDirectoryOverride, error)
            }

            return rootDirectoryOverride
        }

        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AudioFileStoreError.documentsDirectoryUnavailable
        }

        let directoryURL = documentsURL
            .appendingPathComponent("Rokurics", isDirectory: true)
            .standardizedFileURL

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw AudioFileStoreError.directoryCreationFailed(directoryURL, error)
        }

        return directoryURL
    }

    func recordingsDirectory() throws -> URL {
        let directoryURL = try baseDirectory()
            .appendingPathComponent("Recordings", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw AudioFileStoreError.directoryCreationFailed(directoryURL, error)
        }

        return directoryURL
    }

    func metadataDirectory() throws -> URL {
        let directoryURL = try baseDirectory()
            .appendingPathComponent("Metadata", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw AudioFileStoreError.directoryCreationFailed(directoryURL, error)
        }

        return directoryURL
    }

    func ensureStorageDirectories() throws {
        let recordingsURL = try recordingsDirectory()
        let metadataURL = try metadataDirectory()
        storageLog("recordings directory: \(recordingsURL.path)")
        storageLog("metadata directory: \(metadataURL.path)")
    }

    func makeRecordingURL(date: Date = Date(), fallback: Bool = false) throws -> URL {
        let directoryURL = try recordingsDirectory()
        let suffix = fallback ? "_fallback" : ""
        let baseName = "rokurics_\(Self.fileDateFormatter.string(from: date))\(suffix)"

        return directoryURL.appendingPathComponent(baseName).appendingPathExtension("m4a")
    }

    func makeMetadataURL(id: String) throws -> URL {
        let url = try metadataDirectory()
            .appendingPathComponent(id)
            .appendingPathExtension("json")
            .standardizedFileURL

        guard try isInsideBaseDirectory(url) else {
            throw AudioFileStoreError.pathOutsideRokuricsDirectory(url)
        }

        return url
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    func isWritableDirectory(at url: URL) -> Bool {
        fileManager.isWritableFile(atPath: url.path)
    }

    func removeFileIfExists(at url: URL) throws {
        guard try isInsideBaseDirectory(url) else {
            throw AudioFileStoreError.pathOutsideRokuricsDirectory(url)
        }

        guard fileExists(at: url) else {
            return
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw AudioFileStoreError.fileRemovalFailed(url, error)
        }
    }

    func fileSize(at url: URL) throws -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber {
                return size.int64Value
            }

            if let size = attributes[.size] as? Int64 {
                return size
            }

            return 0
        } catch {
            throw AudioFileStoreError.fileAttributesFailed(url, error)
        }
    }

    func relativePath(for url: URL) throws -> String {
        let baseURL = try baseDirectory().standardizedFileURL
        let standardizedURL = url.standardizedFileURL
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : "\(baseURL.path)/"
        let filePath = standardizedURL.path

        guard filePath.hasPrefix(basePath) else {
            throw AudioFileStoreError.pathOutsideRokuricsDirectory(url)
        }

        return String(filePath.dropFirst(basePath.count))
    }

    func saveMetadata(_ metadata: RecordingMetadata) throws {
        let metadataURL = try makeMetadataURL(id: metadata.id)
        storageLog("metadata URL: \(metadataURL.path)")

        do {
            let data = try Self.metadataEncoder.encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
            storageLog("metadata saved")
        } catch {
            errorLog("metadata save failed: \(error.localizedDescription)")
            throw AudioFileStoreError.metadataWriteFailed(metadataURL, error)
        }
    }

    func updateMetadata(_ metadata: RecordingMetadata) throws {
        try saveMetadata(metadata)
    }

    func loadMetadata(id: String) throws -> RecordingMetadata {
        let metadataURL = try makeMetadataURL(id: id)
        guard fileExists(at: metadataURL) else {
            throw AudioFileStoreError.recordingNotFound(id)
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            return try Self.metadataDecoder.decode(RecordingMetadata.self, from: data)
        } catch {
            throw AudioFileStoreError.metadataReadFailed(metadataURL, error)
        }
    }

    func updateTitle(recordingID: String, rawTitle: String) throws -> RecordingMetadata {
        let metadata = try loadMetadata(id: recordingID)
        let title = RecordingTitleEditRules.normalizedTitle(rawTitle, fallback: metadata.title)
        let updatedMetadata = metadata.updatingTitle(title)
        try saveMetadata(updatedMetadata)
        return updatedMetadata
    }

    func deleteRecording(id: String) throws {
        _ = try moveRecordingToTrash(id: id)
    }

    @discardableResult
    func moveRecordingToTrash(id: String) throws -> RecordingMetadata {
        let metadata = try loadMetadata(id: id)
        return try moveRecordingToTrash(metadata)
    }

    @discardableResult
    func moveRecordingToTrash(_ metadata: RecordingMetadata, deletedAt: Date = Date()) throws -> RecordingMetadata {
        let updatedMetadata = metadata.updatingTrashState(isDeleted: true, deletedAt: deletedAt)
        try saveMetadata(updatedMetadata)
        return updatedMetadata
    }

    @discardableResult
    func restoreRecording(id: String) throws -> RecordingMetadata {
        let metadata = try loadMetadata(id: id)
        let updatedMetadata = metadata.updatingTrashState(isDeleted: false, deletedAt: nil)
        try saveMetadata(updatedMetadata)
        return updatedMetadata
    }

    func deleteRecording(_ metadata: RecordingMetadata) throws {
        try moveRecordingToTrash(metadata)
    }

    func permanentlyDeleteRecording(id: String) throws {
        let metadata = try loadMetadata(id: id)
        try permanentlyDeleteRecording(metadata)
    }

    func permanentlyDeleteRecording(_ metadata: RecordingMetadata) throws {
        let audioURL = try localFileURL(relativePath: metadata.relativeAudioPath)
        let metadataURL = try localFileURL(relativePath: metadata.relativeMetadataPath)

        guard try isInsideBaseDirectory(audioURL),
              try isInsideBaseDirectory(metadataURL) else {
            throw AudioFileStoreError.pathOutsideRokuricsDirectory(audioURL)
        }

        try removeFileIfExists(at: audioURL)
        try removeFileIfExists(at: metadataURL)
    }

    func audioURL(for metadata: RecordingMetadata) throws -> URL {
        try localFileURL(relativePath: metadata.relativeAudioPath)
    }

    func loadAllMetadata(includeDeleted: Bool = false) throws -> [RecordingMetadata] {
        let metadataURL = try metadataDirectory()
        storageLog("metadata directory: \(metadataURL.path)")

        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: metadataURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            errorLog("metadata directory read failed: \(error.localizedDescription)")
            throw AudioFileStoreError.metadataDirectoryReadFailed(metadataURL, error)
        }

        let recordings = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> RecordingMetadata? in
                do {
                    let data = try Data(contentsOf: url)
                    return try Self.metadataDecoder.decode(RecordingMetadata.self, from: data)
                } catch {
                    errorLog("metadata read failed: \(url.path) - \(error.localizedDescription)")
                    return nil
                }
            }
            .filter { includeDeleted || !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }

        storageLog("loaded recordings count: \(recordings.count)")
        return recordings
    }

    func loadTrashedMetadata() throws -> [RecordingMetadata] {
        try loadAllMetadata(includeDeleted: true)
            .filter(\.isDeleted)
            .sorted { ($0.deletedAt ?? $0.createdAt) > ($1.deletedAt ?? $1.createdAt) }
    }

    func latestMetadata() throws -> RecordingMetadata? {
        try loadAllMetadata().first
    }

    private func storageLog(_ message: String) {
        print("[RokuricsStorage] \(message)")
    }

    private func errorLog(_ message: String) {
        print("[RokuricsStorage][ERROR] \(message)")
    }

    private func localFileURL(relativePath: String) throws -> URL {
        let url = try baseDirectory()
            .appendingPathComponent(relativePath, isDirectory: false)
            .standardizedFileURL

        guard try isInsideBaseDirectory(url) else {
            throw AudioFileStoreError.pathOutsideRokuricsDirectory(url)
        }

        return url
    }

    private func isInsideBaseDirectory(_ url: URL) throws -> Bool {
        let baseURL = try baseDirectory().standardizedFileURL
        let basePath = baseURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == basePath || filePath.hasPrefix(basePath + "/")
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private static let metadataEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let metadataDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
