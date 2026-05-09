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

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return "无法访问本地 Documents 目录。"
        case let .directoryCreationFailed(url, error):
            return "录音目录创建失败：\(url.path) - \(error.localizedDescription)"
        case let .fileRemovalFailed(url, error):
            return "旧录音文件删除失败：\(url.path) - \(error.localizedDescription)"
        }
    }
}

struct AudioFileStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func recordingsDirectory() throws -> URL {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AudioFileStoreError.documentsDirectoryUnavailable
        }

        let directoryURL = documentsURL
            .appendingPathComponent("Rokurics", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw AudioFileStoreError.directoryCreationFailed(directoryURL, error)
        }

        return directoryURL
    }

    func makeRecordingURL(date: Date = Date(), fallback: Bool = false) throws -> URL {
        let directoryURL = try recordingsDirectory()
        let suffix = fallback ? "_fallback" : ""
        let baseName = "rokurics_\(Self.fileDateFormatter.string(from: date))\(suffix)"

        return directoryURL.appendingPathComponent(baseName).appendingPathExtension("m4a")
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

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
