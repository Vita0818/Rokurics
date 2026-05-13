//
//  RecordingMetadata.swift
//  Rokurics
//
//  Created by Codex on 2026/5/9.
//

import Foundation

struct RecordingMetadata: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let fileName: String
    let relativeAudioPath: String
    let relativeMetadataPath: String
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
}

extension RecordingMetadata {
    func updatingUploadStatus(_ uploadStatus: RecordingUploadStatus) -> RecordingMetadata {
        RecordingMetadata(
            id: id,
            title: title,
            fileName: fileName,
            relativeAudioPath: relativeAudioPath,
            relativeMetadataPath: relativeMetadataPath,
            createdAt: createdAt,
            endedAt: endedAt,
            duration: duration,
            format: format,
            codec: codec,
            sampleRate: sampleRate,
            channels: channels,
            bitrate: bitrate,
            fileSize: fileSize,
            uploadStatus: uploadStatus.rawValue,
            transcriptionStatus: transcriptionStatus,
            noteStatus: noteStatus,
            tags: tags
        )
    }

    static func defaultTitle(createdAt: Date) -> String {
        "录音 \(Self.titleDateFormatter.string(from: createdAt))"
    }

    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
