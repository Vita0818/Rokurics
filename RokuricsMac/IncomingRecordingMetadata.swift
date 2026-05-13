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
    let sourceDeviceName: String
    let sourceDeviceID: String
    let uploadedAt: Date
}
