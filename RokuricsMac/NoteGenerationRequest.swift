//
//  NoteGenerationRequest.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct NoteGenerationRequest {
    let taskID: String
    let recordingID: String
    let sanitizedRecordingID: String
    let title: String
    let createdAt: Date
    let duration: TimeInterval
    let transcriptRelativePath: String?
    let transcriptMarkdownRelativePath: String?
    let transcriptionProviderID: String?
    let transcriptionModelName: String?
    let transcriptResult: TranscriptionResult?
    let transcriptMarkdown: String?
    let requestedAt: Date
}
