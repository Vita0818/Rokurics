//
//  TranscriptionResult.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct TranscriptionResult: Codable, Equatable {
    let taskID: String
    let recordingID: String
    let providerID: String
    let providerName: String
    let modelName: String?
    let language: String?
    let text: String
    let segments: [TranscriptionSegment]
    let startedAt: Date
    let completedAt: Date
    let status: String
}
