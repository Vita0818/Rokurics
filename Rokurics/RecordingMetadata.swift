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
    let studyFiling: StudyFilingPath?
    let isDeleted: Bool
    let deletedAt: Date?

    init(
        id: String,
        title: String,
        fileName: String,
        relativeAudioPath: String,
        relativeMetadataPath: String,
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
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.relativeAudioPath = relativeAudioPath
        self.relativeMetadataPath = relativeMetadataPath
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
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case fileName
        case relativeAudioPath
        case relativeMetadataPath
        case createdAt
        case endedAt
        case duration
        case format
        case codec
        case sampleRate
        case channels
        case bitrate
        case fileSize
        case uploadStatus
        case transcriptionStatus
        case noteStatus
        case tags
        case studyFiling
        case isDeleted
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fileName = try container.decode(String.self, forKey: .fileName)
        relativeAudioPath = try container.decode(String.self, forKey: .relativeAudioPath)
        relativeMetadataPath = try container.decode(String.self, forKey: .relativeMetadataPath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        endedAt = try container.decode(Date.self, forKey: .endedAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        format = try container.decode(String.self, forKey: .format)
        codec = try container.decode(String.self, forKey: .codec)
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        channels = try container.decode(Int.self, forKey: .channels)
        bitrate = try container.decode(Int.self, forKey: .bitrate)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        uploadStatus = try container.decode(String.self, forKey: .uploadStatus)
        transcriptionStatus = try container.decode(String.self, forKey: .transcriptionStatus)
        noteStatus = try container.decode(String.self, forKey: .noteStatus)
        tags = try container.decode([String].self, forKey: .tags)
        let decodedStudyFiling = try container.decodeIfPresent(StudyFilingPath.self, forKey: .studyFiling)
        studyFiling = decodedStudyFiling?.isEmpty == true ? nil : decodedStudyFiling
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

extension RecordingMetadata {
    func updatingTitle(_ title: String) -> RecordingMetadata {
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
            uploadStatus: uploadStatus,
            transcriptionStatus: transcriptionStatus,
            noteStatus: noteStatus,
            tags: tags,
            studyFiling: studyFiling,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
    }

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
            tags: tags,
            studyFiling: studyFiling,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
    }

    func updatingTrashState(isDeleted: Bool, deletedAt: Date?) -> RecordingMetadata {
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
            uploadStatus: uploadStatus,
            transcriptionStatus: transcriptionStatus,
            noteStatus: noteStatus,
            tags: tags,
            studyFiling: studyFiling,
            isDeleted: isDeleted,
            deletedAt: deletedAt
        )
    }

    func updatingStudyFiling(_ studyFiling: StudyFilingPath?) -> RecordingMetadata {
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
            uploadStatus: uploadStatus,
            transcriptionStatus: transcriptionStatus,
            noteStatus: noteStatus,
            tags: tags,
            studyFiling: studyFiling,
            isDeleted: isDeleted,
            deletedAt: deletedAt
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
