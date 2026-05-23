//
//  NoteStore.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct NoteStoreSaveResult {
    let noteRelativePath: String
    let summaryPreviewRelativePath: String?
    let outputDirectoryURL: URL
}

struct NoteSummaryPreview: Codable, Equatable {
    let recordingID: String
    let noteRelativePath: String
    let shortSummary: String
    let keyPoints: [String]
    let generatedAt: Date?
    let providerDisplayName: String?
    let modelName: String?

    nonisolated var isVisible: Bool {
        !shortSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !keyPoints.isEmpty
    }

    nonisolated static func make(result: NoteGenerationResult, noteRelativePath: String) -> NoteSummaryPreview {
        NoteSummaryPreview(
            recordingID: result.recordingID,
            noteRelativePath: noteRelativePath,
            shortSummary: shortSummary(from: result.markdown) ?? fallbackSummary(from: result.markdown),
            keyPoints: keyPoints(from: result.markdown),
            generatedAt: result.completedAt,
            providerDisplayName: result.providerName,
            modelName: result.modelName
        )
    }

    nonisolated static func shortSummary(from markdown: String) -> String? {
        let summaryLines = section(named: "摘要", in: markdown)
        let text = previewText(from: summaryLines, maxCharacters: 220)
        return text.isEmpty ? nil : text
    }

    nonisolated static func fallbackSummary(from markdown: String) -> String {
        let text = previewText(from: readableBodyLines(from: markdown), maxCharacters: 220)
        return text.isEmpty ? "暂无摘要" : text
    }

    nonisolated static func keyPoints(from markdown: String, maxCount: Int = 4) -> [String] {
        let focusLines = section(named: "重点", in: markdown)
        let bullets = bulletTexts(from: focusLines)
        if !bullets.isEmpty {
            return Array(bullets.prefix(maxCount))
        }

        return Array(bulletTexts(from: readableBodyLines(from: markdown)).prefix(maxCount))
    }

    nonisolated private static func section(named name: String, in markdown: String) -> [String] {
        let lines = markdownLines(markdown)
        guard let startIndex = lines.firstIndex(where: { headingTitle($0) == name }) else {
            return []
        }

        let contentStart = startIndex + 1
        let contentEnd = lines[contentStart...].firstIndex { line in
            headingTitle(line) != nil
        } ?? lines.endIndex
        return Array(lines[contentStart..<contentEnd])
    }

    nonisolated private static func headingTitle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else {
            return nil
        }

        let title = trimmed
            .drop(while: { $0 == "#" || $0 == " " })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    nonisolated private static func previewText(from lines: [String], maxCharacters: Int) -> String {
        let joined = lines
            .compactMap(cleanReadableLine)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard joined.count > maxCharacters else {
            return joined
        }

        return String(joined.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    nonisolated private static func bulletTexts(from lines: [String]) -> [String] {
        lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("- ") {
                return cleanReadableLine(String(trimmed.dropFirst(2)))
            }
            if trimmed.hasPrefix("* ") {
                return cleanReadableLine(String(trimmed.dropFirst(2)))
            }
            return nil
        }
    }

    nonisolated private static func cleanReadableLine(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        if text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.hasPrefix("- ") || text.hasPrefix("* ") {
            text = String(text.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.hasPrefix("#") else {
            return nil
        }

        let lower = text.lowercased()
        let sensitiveMarkers = ["api key", "apikey", "prompt", "response json", "sk-"]
        guard !sensitiveMarkers.contains(where: { lower.contains($0) }) else {
            return nil
        }

        text = text
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    nonisolated private static func readableBodyLines(from markdown: String) -> [String] {
        var lines = markdownLines(markdown)
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        if lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("# ") == true {
            lines.removeFirst()
        }
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        while let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              first.hasPrefix(">") || (first.hasPrefix("- ") && first.contains(":")) {
            lines.removeFirst()
        }
        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        if headingTitle(lines.first ?? "") == "基本信息" {
            lines.removeFirst()
            while let first = lines.first {
                if headingTitle(first) != nil {
                    break
                }
                lines.removeFirst()
            }
        }
        return lines
    }

    nonisolated private static func markdownLines(_ markdown: String) -> [String] {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }
}

struct NoteStoreSectionSaveResult {
    let sectionNoteRelativePath: String
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
            self.rootURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
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

            let noteRelativePath = try relativePath(for: noteURL)
            let summaryPreview = NoteSummaryPreview.make(result: result, noteRelativePath: noteRelativePath)
            let summaryPreviewURL = outputURL.appendingPathComponent("summary.json", isDirectory: false).standardizedFileURL
            try Self.encoder.encode(summaryPreview).write(to: summaryPreviewURL, options: .atomic)

            return NoteStoreSaveResult(
                noteRelativePath: noteRelativePath,
                summaryPreviewRelativePath: try relativePath(for: summaryPreviewURL),
                outputDirectoryURL: outputURL
            )
        } catch let error as NoteStoreError {
            throw error
        } catch {
            throw NoteStoreError.writeFailed("note_write_failed")
        }
    }

    func loadSummaryPreview(noteRelativePath: String?) -> NoteSummaryPreview? {
        guard let noteRelativePath,
              let noteURL = resolvedRootFileURL(relativePath: noteRelativePath) else {
            return nil
        }

        let summaryURL = noteURL
            .deletingLastPathComponent()
            .appendingPathComponent("summary.json", isDirectory: false)
            .standardizedFileURL
        if fileManager.fileExists(atPath: summaryURL.path),
           let data = try? Data(contentsOf: summaryURL),
           let preview = try? Self.decoder.decode(NoteSummaryPreview.self, from: data) {
            return preview
        }

        guard fileManager.fileExists(atPath: noteURL.path),
              let markdown = try? String(contentsOf: noteURL, encoding: .utf8) else {
            return nil
        }

        return NoteSummaryPreview(
            recordingID: "",
            noteRelativePath: noteRelativePath,
            shortSummary: NoteSummaryPreview.shortSummary(from: markdown) ?? NoteSummaryPreview.fallbackSummary(from: markdown),
            keyPoints: NoteSummaryPreview.keyPoints(from: markdown),
            generatedAt: nil,
            providerDisplayName: nil,
            modelName: nil
        )
    }

    func saveSection(
        markdown: String,
        request: NoteGenerationRequest,
        sectionIndex: Int
    ) throws -> NoteStoreSectionSaveResult {
        let outputURL = try outputDirectory(
            recordingID: request.recordingID,
            sanitizedRecordingID: request.sanitizedRecordingID,
            createdAt: request.createdAt
        )
        let sectionsURL = outputURL.appendingPathComponent("sections", isDirectory: true).standardizedFileURL
        let sectionURL = sectionsURL
            .appendingPathComponent("section_\(String(format: "%03d", sectionIndex)).md", isDirectory: false)
            .standardizedFileURL

        guard isInsideNotesDirectory(outputURL),
              isInsideNotesDirectory(sectionsURL),
              isInsideNotesDirectory(sectionURL) else {
            throw NoteStoreError.unsafeDestination
        }

        do {
            try fileManager.createDirectory(at: sectionsURL, withIntermediateDirectories: true)
            try markdown.write(to: sectionURL, atomically: true, encoding: .utf8)
            return NoteStoreSectionSaveResult(
                sectionNoteRelativePath: try relativePath(for: sectionURL),
                outputDirectoryURL: outputURL
            )
        } catch let error as NoteStoreError {
            throw error
        } catch {
            throw NoteStoreError.writeFailed("note_section_write_failed")
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

    private func resolvedRootFileURL(relativePath: String) -> URL? {
        let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, !trimmedPath.hasPrefix("/") else {
            return nil
        }

        let url = rootURL.appendingPathComponent(trimmedPath, isDirectory: false).standardizedFileURL
        return isInsideRoot(url) ? url : nil
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
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

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
