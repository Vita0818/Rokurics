//
//  NoteGenerationResult.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct NoteGenerationResult: Codable, Equatable {
    let taskID: String
    let recordingID: String
    let providerID: String
    let providerName: String
    let modelName: String?
    let markdown: String
    let startedAt: Date
    let completedAt: Date
    let status: String
    let modelOutputWasTruncated: Bool
    let transcriptInputWasTruncated: Bool

    init(
        taskID: String,
        recordingID: String,
        providerID: String,
        providerName: String,
        modelName: String?,
        markdown: String,
        startedAt: Date,
        completedAt: Date,
        status: String,
        modelOutputWasTruncated: Bool = false,
        transcriptInputWasTruncated: Bool = false
    ) {
        self.taskID = taskID
        self.recordingID = recordingID
        self.providerID = providerID
        self.providerName = providerName
        self.modelName = modelName
        self.markdown = markdown
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.modelOutputWasTruncated = modelOutputWasTruncated
        self.transcriptInputWasTruncated = transcriptInputWasTruncated
    }
}
