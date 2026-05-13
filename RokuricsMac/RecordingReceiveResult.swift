//
//  RecordingReceiveResult.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/12.
//

import Foundation

struct RecordingReceiveResult {
    let recordingID: String
    let directoryURL: URL
    let metadataFileName: String?
    let audioFileName: String?
    let receiveFileName: String
}

struct RecordingReceiveRecord: Codable {
    var recordingID: String
    var sanitizedRecordingID: String
    var receivedAt: Date
    var updatedAt: Date
    var sourceDeviceID: String
    var sourceDeviceName: String
    var originalTitle: String
    var normalizedTitle: String
    var audioFileName: String?
    var originalAudioFileName: String?
    var metadataFileName: String
    var status: String
    var transcriptionStatus: String
    var noteStatus: String
    var processingStatus: String
    var suggestedCategory: String?
    var course: String?
    var category: String?
    var tags: [String]
    var createdAt: Date
    var duration: TimeInterval
    var fileSize: Int64
    var suggestedFolder: String?
    var userConfirmedFolder: String?
    var checksum: String?
    var audioRelativePath: String?
    var metadataRelativePath: String
}

struct RecordingReceiveLogEntry: Codable {
    let recordingID: String
    let event: String
    let at: Date
    let sourceDeviceIDPrefix: String
    let status: String
}
