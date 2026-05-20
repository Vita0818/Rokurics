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
    let sourceDuration: TimeInterval?
    let chunkDescriptor: AudioChunkDescriptor?

    init(
        taskID: String,
        recordingID: String,
        audioFileURL: URL,
        metadataFileURL: URL?,
        language: String?,
        prompt: String?,
        outputDirectory: URL,
        createdAt: Date,
        sourceDuration: TimeInterval? = nil,
        chunkDescriptor: AudioChunkDescriptor? = nil
    ) {
        self.taskID = taskID
        self.recordingID = recordingID
        self.audioFileURL = audioFileURL
        self.metadataFileURL = metadataFileURL
        self.language = language
        self.prompt = prompt
        self.outputDirectory = outputDirectory
        self.createdAt = createdAt
        self.sourceDuration = sourceDuration
        self.chunkDescriptor = chunkDescriptor
    }

    func chunkRequest(taskID: String, descriptor: AudioChunkDescriptor) -> TranscriptionRequest {
        TranscriptionRequest(
            taskID: taskID,
            recordingID: recordingID,
            audioFileURL: audioFileURL,
            metadataFileURL: metadataFileURL,
            language: language,
            prompt: prompt,
            outputDirectory: outputDirectory,
            createdAt: createdAt,
            sourceDuration: sourceDuration,
            chunkDescriptor: descriptor
        )
    }
}
