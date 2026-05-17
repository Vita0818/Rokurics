//
//  NoteStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct NoteStoreSaveResult {
    let noteRelativePath: String
    let outputDirectoryURL: URL
}

enum NoteStoreError: LocalizedError {
    case unableToCreateDirectory
    case unsafeDestination
    case invalidRecordingID
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unableToCreateDirectory:
            return "note_directory_unavailable"
        case .unsafeDestination:
            return "unsafe_note_destination"
        case .invalidRecordingID:
            return "invalid_recording_id"
        case .writeFailed(let reason):
            return reason
        }
    }
}

final class NoteStore {
    private let fileManager: FileManager
    private let rootURL: URL
    private let notesURL: URL

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
        notesURL = self.rootURL
            .appendingPathComponent("notes", isDirectory: true)
            .standardizedFileURL
    }

    func outputDirectory(
        recordingID: String,
        sanitizedRecordingID: String?,
        createdAt: Date
    ) throws -> URL {
        let sanitizedID = sanitizedPathComponent(sanitizedRecordingID?.isEmpty == false ? sanitizedRecordingID : recordingID)
        guard !sanitizedID.isEmpty else {
            throw NoteStoreError.invalidRecordingID
        }

        let outputURL = notesURL
            .appendingPathComponent(Self.dayFormatter.string(from: createdAt), isDirectory: true)
            .appendingPathComponent(sanitizedID, isDirectory: true)
            .standardizedFileURL

        guard isInsideNotesDirectory(outputURL) else {
            throw NoteStoreError.unsafeDestination
        }

        return outputURL
    }

    func save(result: NoteGenerationResult, request: NoteGenerationRequest) throws -> NoteStoreSaveResult {
        let outputURL = try outputDirectory(
            recordingID: request.recordingID,
            sanitizedRecordingID: request.sanitizedRecordingID,
            createdAt: request.createdAt
        )
        let noteURL = outputURL.appendingPathComponent("note.md", isDirectory: false).standardizedFileURL

        guard isInsideNotesDirectory(outputURL),
              isInsideNotesDirectory(noteURL) else {
            throw NoteStoreError.unsafeDestination
        }

        do {
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try result.markdown.write(to: noteURL, atomically: true, encoding: .utf8)

            return NoteStoreSaveResult(
                noteRelativePath: try relativePath(for: noteURL),
                outputDirectoryURL: outputURL
            )
        } catch let error as NoteStoreError {
            throw error
        } catch {
            throw NoteStoreError.writeFailed("note_write_failed")
        }
    }

    private func relativePath(for url: URL) throws -> String {
        let rootPath = rootURL.standardizedFileURL.path.hasSuffix("/") ? rootURL.standardizedFileURL.path : "\(rootURL.standardizedFileURL.path)/"
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            throw NoteStoreError.unsafeDestination
        }

        return String(filePath.dropFirst(rootPath.count))
    }

    private func isInsideNotesDirectory(_ url: URL) -> Bool {
        let notesPath = notesURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == notesPath || filePath.hasPrefix(notesPath + "/")
    }

    private func sanitizedPathComponent(_ value: String?) -> String {
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
