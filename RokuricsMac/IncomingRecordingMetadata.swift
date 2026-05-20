//
//  IncomingRecordingMetadata.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/12.
//

import Foundation

struct IncomingRecordingMetadata: Codable {
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
    let studyFiling: StudyFilingPath?
    let sourceDeviceName: String
    let sourceDeviceID: String
    let uploadedAt: Date

    init(
        id: String,
        title: String,
        originalFileName: String,
        relativeAudioPath: String,
        createdAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        format: String,
        codec: String,
        sampleRate: Double,
        channels: Int,
        bitrate: Int,
        fileSize: Int64,
        uploadStatus: String,
        transcriptionStatus: String,
        noteStatus: String,
        tags: [String],
        studyFiling: StudyFilingPath? = nil,
        sourceDeviceName: String,
        sourceDeviceID: String,
        uploadedAt: Date
    ) {
        self.id = id
        self.title = title
        self.originalFileName = originalFileName
        self.relativeAudioPath = relativeAudioPath
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.duration = duration
        self.format = format
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitrate = bitrate
        self.fileSize = fileSize
        self.uploadStatus = uploadStatus
        self.transcriptionStatus = transcriptionStatus
        self.noteStatus = noteStatus
        self.tags = tags
        self.studyFiling = studyFiling?.isEmpty == true ? nil : studyFiling
        self.sourceDeviceName = sourceDeviceName
        self.sourceDeviceID = sourceDeviceID
        self.uploadedAt = uploadedAt
    }
}
