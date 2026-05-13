//
//  TranscriptionRequest.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct TranscriptionRequest {
    let taskID: String
    let recordingID: String
    let audioFileURL: URL
    let metadataFileURL: URL?
    let language: String?
    let prompt: String?
    let outputDirectory: URL
    let createdAt: Date
}
