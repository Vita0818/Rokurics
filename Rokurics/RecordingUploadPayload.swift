//
//  RecordingUploadPayload.swift
//  Rokurics
//
//  Created by Codex on 2026/5/12.
//

import Foundation

struct RecordingUploadMetadataPayload: Codable {
    let id: String
    let title: String
    let originalFileName: String
    let relativeAudioPath: String
    let createdAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let format: String
    let codec: String
    let sampleRate: Double
    let channels: Int
    let bitrate: Int
    let fileSize: Int64
    let uploadStatus: String
    let transcriptionStatus: String
    let noteStatus: String
    let tags: [String]
    let sourceDeviceName: String
    let sourceDeviceID: String
    let uploadedAt: Date

    init(
        metadata: RecordingMetadata,
        sourceDeviceName: String,
        sourceDeviceID: String,
        uploadedAt: Date = Date()
    ) {
        self.id = metadata.id
        self.title = metadata.title
        self.originalFileName = metadata.fileName
        self.relativeAudioPath = metadata.relativeAudioPath
        self.createdAt = metadata.createdAt
        self.endedAt = metadata.endedAt
        self.duration = metadata.duration
        self.format = metadata.format
        self.codec = metadata.codec
        self.sampleRate = metadata.sampleRate
        self.channels = metadata.channels
        self.bitrate = metadata.bitrate
        self.fileSize = metadata.fileSize
        self.uploadStatus = metadata.uploadStatus
        self.transcriptionStatus = metadata.transcriptionStatus
        self.noteStatus = metadata.noteStatus
        self.tags = metadata.tags
        self.sourceDeviceName = sourceDeviceName
        self.sourceDeviceID = sourceDeviceID
        self.uploadedAt = uploadedAt
    }
}
