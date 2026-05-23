//
//  ReceivedFileStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Foundation

struct ReceivedFileRecord {
    let fileName: String
    let fileURL: URL
}

enum ReceivedFileStoreError: LocalizedError {
    case unableToCreateDirectory
    case unsafeDestination
    case tooManyDuplicateNames

    var errorDescription: String? {
        switch self {
        case .unableToCreateDirectory:
            return "Unable to create test upload directory."
        case .unsafeDestination:
            return "Upload destination is outside the Rokurics test upload directory."
        case .tooManyDuplicateNames:
            return "Unable to create a unique upload filename."
        }
    }
}

final class ReceivedFileStore {
    static let displayPath = "~/Rokurics/test-uploads/ 或 App Support/\(MacAppStorageProfile.applicationSupportFolderName)/test-uploads/"

    private let fileManager: FileManager
    private let preferredDirectoryURL: URL
    private let fallbackDirectoryURL: URL
    private(set) var directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        preferredDirectoryURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Rokurics", isDirectory: true)
            .appendingPathComponent("test-uploads", isDirectory: true)
            .standardizedFileURL
        fallbackDirectoryURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
            .appendingPathComponent("test-uploads", isDirectory: true)
            .standardizedFileURL
        directoryURL = preferredDirectoryURL
    }

    func saveTestUpload(body: Data, requestedFileName: String?) throws -> ReceivedFileRecord {
        do {
            return try saveTestUpload(body: body, requestedFileName: requestedFileName, usingFallback: false)
        } catch {
            guard directoryURL != fallbackDirectoryURL else {
                throw error
            }

            print("[RokuricsMacStorage] preferred upload directory unavailable, falling back to app support: \(error)")
            directoryURL = fallbackDirectoryURL
            return try saveTestUpload(body: body, requestedFileName: requestedFileName, usingFallback: true)
        }
    }

    func savedFileCount() -> Int {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return 0
        }

        do {
            let files = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            return files.filter { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.count
        } catch {
            print("[RokuricsMacStorage] failed to count saved files: \(error)")
            return 0
        }
    }

    private func ensureDirectoryExists() throws {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            print("[RokuricsMacStorage] failed to create directory: \(error)")
            throw ReceivedFileStoreError.unableToCreateDirectory
        }
    }

    private func saveTestUpload(body: Data, requestedFileName: String?, usingFallback: Bool) throws -> ReceivedFileRecord {
        try ensureDirectoryExists()

        let safeFileName = sanitizedFileName(from: requestedFileName)
        print("[RokuricsMacStorage] sanitized filename: \(safeFileName)")

        let destinationURL = try uniqueDestinationURL(for: safeFileName)
        guard isInsideDirectory(destinationURL) else {
            print("[RokuricsMacStorage] rejected unsafe destination: \(destinationURL.path)")
            throw ReceivedFileStoreError.unsafeDestination
        }

        try body.write(to: destinationURL, options: .atomic)
        if usingFallback {
            print("[RokuricsMacStorage] saved file using app support fallback")
        }
        print("[RokuricsMacStorage] saved file URL: \(destinationURL.path)")

        return ReceivedFileRecord(fileName: destinationURL.lastPathComponent, fileURL: destinationURL)
    }

    private func sanitizedFileName(from requestedFileName: String?) -> String {
        let fallbackName = Self.defaultFileName()
        let rawName = requestedFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastPathComponent = ((rawName?.isEmpty == false ? rawName : fallbackName) as NSString?)?.lastPathComponent ?? fallbackName

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let cleaned = lastPathComponent.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        if cleaned.isEmpty {
            return fallbackName
        }

        return cleaned
    }

    private func uniqueDestinationURL(for fileName: String) throws -> URL {
        let originalURL = directoryURL.appendingPathComponent(fileName, isDirectory: false).standardizedFileURL
        guard fileManager.fileExists(atPath: originalURL.path) else {
            return originalURL
        }

        let baseURL = originalURL.deletingPathExtension()
        let pathExtension = originalURL.pathExtension

        for index in 1...999 {
            let candidateName = pathExtension.isEmpty
                ? "\(baseURL.lastPathComponent)-\(index)"
                : "\(baseURL.lastPathComponent)-\(index).\(pathExtension)"
            let candidateURL = directoryURL.appendingPathComponent(candidateName, isDirectory: false).standardizedFileURL

            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }

        throw ReceivedFileStoreError.tooManyDuplicateNames
    }

    private func isInsideDirectory(_ fileURL: URL) -> Bool {
        let directoryPath = directoryURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        return filePath.hasPrefix(directoryPath + "/")
    }

    private static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "rokurics_test_\(formatter.string(from: Date())).json"
    }
}
