//
//  TranscriptStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct TranscriptStoreSaveResult {
    let transcriptRelativePath: String
    let transcriptMarkdownRelativePath: String
    let outputDirectoryURL: URL
}

enum TranscriptStoreError: LocalizedError {
    case unableToCreateDirectory
    case unsafeDestination
    case invalidRecordingID
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unableToCreateDirectory:
            return "transcript_directory_unavailable"
        case .unsafeDestination:
            return "unsafe_transcript_destination"
        case .invalidRecordingID:
            return "invalid_recording_id"
        case .writeFailed(let reason):
            return reason
        }
    }
}

final class TranscriptStore {
    private let fileManager: FileManager
    private let rootURL: URL
    private let transcriptsURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootURL = applicationSupportURL
            .appendingPathComponent("Rokurics", isDirectory: true)
            .standardizedFileURL
        transcriptsURL = rootURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .standardizedFileURL
    }

    func outputDirectory(recordingID: String, createdAt: Date) throws -> URL {
        let sanitizedID = sanitizedPathComponent(recordingID)
        guard !sanitizedID.isEmpty else {
            throw TranscriptStoreError.invalidRecordingID
        }

        let outputURL = transcriptsURL
            .appendingPathComponent(Self.dayFormatter.string(from: createdAt), isDirectory: true)
            .appendingPathComponent(sanitizedID, isDirectory: true)
            .standardizedFileURL

        guard isInsideTranscriptsDirectory(outputURL) else {
            throw TranscriptStoreError.unsafeDestination
        }

        return outputURL
    }

    func save(
        result: TranscriptionResult,
        request: TranscriptionRequest,
        recordingTitle: String
    ) throws -> TranscriptStoreSaveResult {
        let outputURL = request.outputDirectory.standardizedFileURL
        let transcriptURL = outputURL.appendingPathComponent("transcript.json", isDirectory: false).standardizedFileURL
        let markdownURL = outputURL.appendingPathComponent("transcript.md", isDirectory: false).standardizedFileURL

        guard isInsideTranscriptsDirectory(outputURL),
              isInsideTranscriptsDirectory(transcriptURL),
              isInsideTranscriptsDirectory(markdownURL) else {
            throw TranscriptStoreError.unsafeDestination
        }

        do {
            try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try Self.jsonEncoder.encode(result).write(to: transcriptURL, options: .atomic)
            try markdown(for: result, recordingTitle: recordingTitle).write(to: markdownURL, atomically: true, encoding: .utf8)

            return TranscriptStoreSaveResult(
                transcriptRelativePath: try relativePath(for: transcriptURL),
                transcriptMarkdownRelativePath: try relativePath(for: markdownURL),
                outputDirectoryURL: outputURL
            )
        } catch let error as TranscriptStoreError {
            throw error
        } catch {
            throw TranscriptStoreError.writeFailed("transcript_write_failed")
        }
    }

    private func markdown(for result: TranscriptionResult, recordingTitle: String) -> String {
        let title = recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名录音" : recordingTitle
        let language = result.language?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? result.language! : "auto"
        let segmentLines = result.segments.map { segment in
            "- [\(Self.timecode(segment.startTime)) - \(Self.timecode(segment.endTime))] \(segment.text)"
        }
        .joined(separator: "\n")

        return """
        # \(title)

        - Provider: \(result.providerName)
        - Transcribed At: \(Self.displayDateFormatter.string(from: result.completedAt))
        - Language: \(language)

        ## Transcript

        \(result.text)

        ## Segments

        \(segmentLines)
        """
    }

    private func relativePath(for url: URL) throws -> String {
        let rootPath = rootURL.standardizedFileURL.path.hasSuffix("/") ? rootURL.standardizedFileURL.path : "\(rootURL.standardizedFileURL.path)/"
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            throw TranscriptStoreError.unsafeDestination
        }

        return String(filePath.dropFirst(rootPath.count))
    }

    private func isInsideTranscriptsDirectory(_ url: URL) -> Bool {
        let transcriptsPath = transcriptsURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == transcriptsPath || filePath.hasPrefix(transcriptsPath + "/")
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

    private static func timecode(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
