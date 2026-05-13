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
    case metadataWriteFailed(URL, Error)
    case metadataDirectoryReadFailed(URL, Error)

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
        case let .metadataWriteFailed(url, error):
            return "metadata 写入失败：\(url.path) - \(error.localizedDescription)"
        case let .metadataDirectoryReadFailed(url, error):
            return "metadata 目录读取失败：\(url.path) - \(error.localizedDescription)"
        }
    }
}

struct AudioFileStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func baseDirectory() throws -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AudioFileStoreError.documentsDirectoryUnavailable
        }

        let directoryURL = documentsURL.appendingPathComponent("Rokurics", isDirectory: true)

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
        try metadataDirectory()
            .appendingPathComponent(id)
            .appendingPathExtension("json")
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

    func audioURL(for metadata: RecordingMetadata) throws -> URL {
        try baseDirectory().appendingPathComponent(metadata.relativeAudioPath)
    }

    func loadAllMetadata() throws -> [RecordingMetadata] {
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
            .sorted { $0.createdAt > $1.createdAt }

        storageLog("loaded recordings count: \(recordings.count)")
        return recordings
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
