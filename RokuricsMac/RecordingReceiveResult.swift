//
//  RecordingReceiveResult.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/12.
//

import Foundation

enum RecordingUploadDisposition: String, Codable, Equatable {
    case acceptedNew
    case acceptedExisting
    case rejectedConflict
}

struct RecordingReceiveResult {
    let recordingID: String
    let directoryURL: URL
    let metadataFileName: String?
    let audioFileName: String?
    let receiveFileName: String
    let disposition: RecordingUploadDisposition
    let receiveStatus: String
    let processingStatus: String
}

struct ResumableAudioUploadStartRequest: Codable, Equatable {
    let recordingID: String
    let fileName: String
    let totalBytes: Int64
    let totalSHA256: String
    let chunkSize: Int
    let metadataHash: String?
    let uploadJobID: String?
}

struct ResumableAudioUploadStatusRequest: Codable, Equatable {
    let recordingID: String
    let sessionID: String
    let totalSHA256: String
}

struct ResumableAudioUploadFinalizeRequest: Codable, Equatable {
    let recordingID: String
    let sessionID: String
    let totalBytes: Int64
    let totalSHA256: String
}

struct ResumableAudioUploadSessionResponse: Codable, Equatable {
    let ok: Bool
    let disposition: String?
    let status: String?
    let sessionID: String?
    let confirmedBytes: Int64
    let nextOffset: Int64
    let chunkSize: Int?
    let completed: Bool
    let finalAudioExists: Bool?
    let chunkAccepted: Bool?
    let finalAudioRelativePath: String?
    let checksum: String?
    let fileSize: Int64?
    let receiveStatus: String?
    let processingStatus: String?
    let error: String?
    let reason: String?

    static func accepted(
        disposition: RecordingUploadDisposition,
        status: String,
        sessionID: String?,
        confirmedBytes: Int64,
        nextOffset: Int64,
        chunkSize: Int?,
        completed: Bool,
        finalAudioExists: Bool? = nil,
        chunkAccepted: Bool? = nil,
        finalAudioRelativePath: String? = nil,
        checksum: String? = nil,
        fileSize: Int64? = nil,
        receiveStatus: String? = nil,
        processingStatus: String? = nil
    ) -> ResumableAudioUploadSessionResponse {
        ResumableAudioUploadSessionResponse(
            ok: true,
            disposition: disposition.rawValue,
            status: status,
            sessionID: sessionID,
            confirmedBytes: confirmedBytes,
            nextOffset: nextOffset,
            chunkSize: chunkSize,
            completed: completed,
            finalAudioExists: finalAudioExists,
            chunkAccepted: chunkAccepted,
            finalAudioRelativePath: finalAudioRelativePath,
            checksum: checksum,
            fileSize: fileSize,
            receiveStatus: receiveStatus,
            processingStatus: processingStatus,
            error: nil,
            reason: nil
        )
    }

    static func rejected(error: String, reason: String) -> ResumableAudioUploadSessionResponse {
        ResumableAudioUploadSessionResponse(
            ok: false,
            disposition: error.contains("conflict") ? RecordingUploadDisposition.rejectedConflict.rawValue : nil,
            status: nil,
            sessionID: nil,
            confirmedBytes: 0,
            nextOffset: 0,
            chunkSize: nil,
            completed: false,
            finalAudioExists: nil,
            chunkAccepted: nil,
            finalAudioRelativePath: nil,
            checksum: nil,
            fileSize: nil,
            receiveStatus: nil,
            processingStatus: nil,
            error: error,
            reason: reason
        )
    }
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
    var noteRelativePath: String? = nil
    var noteGeneratedAt: Date? = nil
    var noteProviderID: String? = nil
    var noteModelName: String? = nil
    var noteEndpointDescription: String? = nil
    var noteError: String? = nil
    var processingStatus: String
    var suggestedCategory: String?
    var course: String?
    var category: String?
    var tags: [String]
    var studyFiling: StudyFilingPath? = nil
    var createdAt: Date
    var duration: TimeInterval
    var fileSize: Int64
    var suggestedFolder: String?
    var userConfirmedFolder: String?
    var checksum: String?
    var audioRelativePath: String?
    var metadataRelativePath: String
    var transcriptRelativePath: String? = nil
    var transcriptMarkdownRelativePath: String? = nil
    var transcriptionProviderID: String? = nil
    var transcriptionModelName: String? = nil
    var transcriptionStartedAt: Date? = nil
    var transcriptionCompletedAt: Date? = nil
    var transcriptionError: String? = nil
    var transcriptionMode: ProcessingMode? = nil
    var transcriptionChunks: [RecordingTranscriptionChunkRecord]? = nil
    var isDeleted: Bool = false
    var deletedAt: Date? = nil
    var noteGenerationMode: ProcessingMode? = nil
    var noteSections: [RecordingNoteSectionRecord]? = nil
    var lastUploadError: String? = nil
    var lastUploadAttemptAt: Date? = nil

    init(
        recordingID: String,
        sanitizedRecordingID: String,
        receivedAt: Date,
        updatedAt: Date,
        sourceDeviceID: String,
        sourceDeviceName: String,
        originalTitle: String,
        normalizedTitle: String,
        audioFileName: String?,
        originalAudioFileName: String?,
        metadataFileName: String,
        status: String,
        transcriptionStatus: String,
        noteStatus: String,
        noteRelativePath: String? = nil,
        noteGeneratedAt: Date? = nil,
        noteProviderID: String? = nil,
        noteModelName: String? = nil,
        noteEndpointDescription: String? = nil,
        noteError: String? = nil,
        processingStatus: String,
        suggestedCategory: String?,
        course: String?,
        category: String?,
        tags: [String],
        studyFiling: StudyFilingPath? = nil,
        createdAt: Date,
        duration: TimeInterval,
        fileSize: Int64,
        suggestedFolder: String?,
        userConfirmedFolder: String?,
        checksum: String?,
        audioRelativePath: String?,
        metadataRelativePath: String,
        transcriptRelativePath: String? = nil,
        transcriptMarkdownRelativePath: String? = nil,
        transcriptionProviderID: String? = nil,
        transcriptionModelName: String? = nil,
        transcriptionStartedAt: Date? = nil,
        transcriptionCompletedAt: Date? = nil,
        transcriptionError: String? = nil,
        transcriptionMode: ProcessingMode? = nil,
        transcriptionChunks: [RecordingTranscriptionChunkRecord]? = nil,
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        noteGenerationMode: ProcessingMode? = nil,
        noteSections: [RecordingNoteSectionRecord]? = nil,
        lastUploadError: String? = nil,
        lastUploadAttemptAt: Date? = nil
    ) {
        self.recordingID = recordingID
        self.sanitizedRecordingID = sanitizedRecordingID
        self.receivedAt = receivedAt
        self.updatedAt = updatedAt
        self.sourceDeviceID = sourceDeviceID
        self.sourceDeviceName = sourceDeviceName
        self.originalTitle = originalTitle
        self.normalizedTitle = normalizedTitle
        self.audioFileName = audioFileName
        self.originalAudioFileName = originalAudioFileName
        self.metadataFileName = metadataFileName
        self.status = status
        self.transcriptionStatus = transcriptionStatus
        self.noteStatus = Self.normalizedNoteStatus(noteStatus)
        self.noteRelativePath = noteRelativePath
        self.noteGeneratedAt = noteGeneratedAt
        self.noteProviderID = noteProviderID
        self.noteModelName = noteModelName
        self.noteEndpointDescription = noteEndpointDescription
        self.noteError = noteError
        self.processingStatus = processingStatus
        self.suggestedCategory = suggestedCategory
        self.course = course
        self.category = category
        self.tags = tags
        self.studyFiling = studyFiling?.isEmpty == true ? nil : studyFiling
        self.createdAt = createdAt
        self.duration = duration
        self.fileSize = fileSize
        self.suggestedFolder = suggestedFolder
        self.userConfirmedFolder = userConfirmedFolder
        self.checksum = checksum
        self.audioRelativePath = audioRelativePath
        self.metadataRelativePath = metadataRelativePath
        self.transcriptRelativePath = transcriptRelativePath
        self.transcriptMarkdownRelativePath = transcriptMarkdownRelativePath
        self.transcriptionProviderID = transcriptionProviderID
        self.transcriptionModelName = transcriptionModelName
        self.transcriptionStartedAt = transcriptionStartedAt
        self.transcriptionCompletedAt = transcriptionCompletedAt
        self.transcriptionError = transcriptionError
        self.transcriptionMode = transcriptionMode
        self.transcriptionChunks = transcriptionChunks
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.noteGenerationMode = noteGenerationMode
        self.noteSections = noteSections
        self.lastUploadError = lastUploadError
        self.lastUploadAttemptAt = lastUploadAttemptAt
    }

    private enum CodingKeys: String, CodingKey {
        case recordingID
        case sanitizedRecordingID
        case receivedAt
        case updatedAt
        case sourceDeviceID
        case sourceDeviceName
        case originalTitle
        case normalizedTitle
        case audioFileName
        case originalAudioFileName
        case metadataFileName
        case status
        case transcriptionStatus
        case noteStatus
        case noteRelativePath
        case noteGeneratedAt
        case noteProviderID
        case noteModelName
        case noteEndpointDescription
        case noteError
        case processingStatus
        case suggestedCategory
        case course
        case category
        case tags
        case studyFiling
        case createdAt
        case duration
        case fileSize
        case suggestedFolder
        case userConfirmedFolder
        case checksum
        case audioRelativePath
        case metadataRelativePath
        case transcriptRelativePath
        case transcriptMarkdownRelativePath
        case transcriptionProviderID
        case transcriptionModelName
        case transcriptionStartedAt
        case transcriptionCompletedAt
        case transcriptionError
        case transcriptionMode
        case transcriptionChunks
        case isDeleted
        case deletedAt
        case noteGenerationMode
        case noteSections
        case lastUploadError
        case lastUploadAttemptAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingID = try container.decode(String.self, forKey: .recordingID)
        sanitizedRecordingID = try container.decode(String.self, forKey: .sanitizedRecordingID)
        receivedAt = try container.decode(Date.self, forKey: .receivedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sourceDeviceID = try container.decode(String.self, forKey: .sourceDeviceID)
        sourceDeviceName = try container.decode(String.self, forKey: .sourceDeviceName)
        originalTitle = try container.decode(String.self, forKey: .originalTitle)
        normalizedTitle = try container.decode(String.self, forKey: .normalizedTitle)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        originalAudioFileName = try container.decodeIfPresent(String.self, forKey: .originalAudioFileName)
        metadataFileName = try container.decode(String.self, forKey: .metadataFileName)
        status = try container.decode(String.self, forKey: .status)
        transcriptionStatus = try container.decode(String.self, forKey: .transcriptionStatus)
        noteStatus = Self.normalizedNoteStatus(try container.decodeIfPresent(String.self, forKey: .noteStatus))
        noteRelativePath = try container.decodeIfPresent(String.self, forKey: .noteRelativePath)
        noteGeneratedAt = try container.decodeIfPresent(Date.self, forKey: .noteGeneratedAt)
        noteProviderID = try container.decodeIfPresent(String.self, forKey: .noteProviderID)
        noteModelName = try container.decodeIfPresent(String.self, forKey: .noteModelName)
        noteEndpointDescription = try container.decodeIfPresent(String.self, forKey: .noteEndpointDescription)
        noteError = try container.decodeIfPresent(String.self, forKey: .noteError)
        processingStatus = try container.decode(String.self, forKey: .processingStatus)
        suggestedCategory = try container.decodeIfPresent(String.self, forKey: .suggestedCategory)
        course = try container.decodeIfPresent(String.self, forKey: .course)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        tags = try container.decode([String].self, forKey: .tags)
        let decodedStudyFiling = try container.decodeIfPresent(StudyFilingPath.self, forKey: .studyFiling)
        studyFiling = decodedStudyFiling?.isEmpty == true ? nil : decodedStudyFiling
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        suggestedFolder = try container.decodeIfPresent(String.self, forKey: .suggestedFolder)
        userConfirmedFolder = try container.decodeIfPresent(String.self, forKey: .userConfirmedFolder)
        checksum = try container.decodeIfPresent(String.self, forKey: .checksum)
        audioRelativePath = try container.decodeIfPresent(String.self, forKey: .audioRelativePath)
        metadataRelativePath = try container.decode(String.self, forKey: .metadataRelativePath)
        transcriptRelativePath = try container.decodeIfPresent(String.self, forKey: .transcriptRelativePath)
        transcriptMarkdownRelativePath = try container.decodeIfPresent(String.self, forKey: .transcriptMarkdownRelativePath)
        transcriptionProviderID = try container.decodeIfPresent(String.self, forKey: .transcriptionProviderID)
        transcriptionModelName = try container.decodeIfPresent(String.self, forKey: .transcriptionModelName)
        transcriptionStartedAt = try container.decodeIfPresent(Date.self, forKey: .transcriptionStartedAt)
        transcriptionCompletedAt = try container.decodeIfPresent(Date.self, forKey: .transcriptionCompletedAt)
        transcriptionError = try container.decodeIfPresent(String.self, forKey: .transcriptionError)
        transcriptionMode = try container.decodeIfPresent(ProcessingMode.self, forKey: .transcriptionMode)
        transcriptionChunks = try container.decodeIfPresent([RecordingTranscriptionChunkRecord].self, forKey: .transcriptionChunks)
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        noteGenerationMode = try container.decodeIfPresent(ProcessingMode.self, forKey: .noteGenerationMode)
        noteSections = try container.decodeIfPresent([RecordingNoteSectionRecord].self, forKey: .noteSections)
        lastUploadError = try container.decodeIfPresent(String.self, forKey: .lastUploadError)
        lastUploadAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastUploadAttemptAt)
    }

    static func normalizedNoteStatus(_ status: String?) -> String {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "generating":
            return "generating"
        case "generated":
            return "generated"
        case "failed":
            return "failed"
        default:
            return "notGenerated"
        }
    }
}

struct RecordingReceiveLogEntry: Codable {
    let recordingID: String
    let event: String
    let at: Date
    let sourceDeviceIDPrefix: String
    let status: String
}
