//
//  AudioFileStore.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import Foundation

enum AudioFileStoreError: LocalizedError {
    case documentsDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return "无法访问本地 Documents 目录。"
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

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    func makeRecordingURL(date: Date = Date()) throws -> URL {
        let directoryURL = try recordingsDirectory()
        let baseName = "rokurics_\(Self.fileDateFormatter.string(from: date))"
        var candidateURL = directoryURL.appendingPathComponent(baseName).appendingPathExtension("m4a")
        var suffix = 1

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = directoryURL
                .appendingPathComponent("\(baseName)_\(suffix)")
                .appendingPathExtension("m4a")
            suffix += 1
        }

        return candidateURL
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
