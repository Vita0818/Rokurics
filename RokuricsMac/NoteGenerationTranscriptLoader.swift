//
//  NoteGenerationTranscriptLoader.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct LoadedNoteTranscript: Equatable {
    let transcriptResult: TranscriptionResult?
    let transcriptMarkdown: String?
}

struct NoteGenerationTranscriptLoader {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func load(source: MacRecordingNoteGenerationSource) throws -> LoadedNoteTranscript {
        let transcriptResult = try loadTranscriptResult(from: source.transcriptURL)
        let transcriptMarkdown = try loadTranscriptMarkdown(from: source.transcriptMarkdownURL)

        let hasMarkdown = transcriptMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasStructuredText = transcriptResult?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        guard hasMarkdown || hasStructuredText else {
            throw NoteGenerationError.transcriptDocumentMissing
        }

        return LoadedNoteTranscript(
            transcriptResult: transcriptResult,
            transcriptMarkdown: transcriptMarkdown
        )
    }

    private func loadTranscriptResult(from url: URL?) throws -> TranscriptionResult? {
        guard let url, fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try Self.jsonDecoder.decode(TranscriptionResult.self, from: data)
        } catch is DecodingError {
            throw NoteGenerationError.transcriptDecodeFailed
        } catch {
            throw NoteGenerationError.transcriptReadFailed
        }
    }

    private func loadTranscriptMarkdown(from url: URL?) throws -> String? {
        guard let url, fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw NoteGenerationError.transcriptReadFailed
        }
    }

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
