//
//  MacRecordingInboxItem.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/12.
//

import Foundation

nonisolated struct MacRecordingInboxItem: Identifiable, Equatable {
    let id: String
    let title: String
    let receivedAt: Date
    let duration: TimeInterval
    let fileSize: Int64
    let sourceDeviceID: String?
    let sourceDeviceName: String
    let audioChecksum: String?
    let transcriptionStatus: String
    let noteStatus: String
    let noteRelativePath: String?
    let noteError: String?
    let receiveStatus: String
    let hasAudio: Bool
    let audioRelativePath: String?
    let receiveRelativePath: String?
    let transcriptRelativePath: String?
    let transcriptMarkdownRelativePath: String?
    let transcriptionError: String?
    let studyFiling: StudyFilingPath?
    let isDeleted: Bool
    let deletedAt: Date?
    let transferProgress: LocalNetworkTransferProgress?
    let canonicalDisplaySyncState: CanonicalDisplaySyncState

    init(
        id: String,
        title: String,
        receivedAt: Date,
        duration: TimeInterval,
        fileSize: Int64,
        sourceDeviceID: String? = nil,
        sourceDeviceName: String,
        audioChecksum: String? = nil,
        transcriptionStatus: String,
        noteStatus: String,
        receiveStatus: String,
        hasAudio: Bool,
        audioRelativePath: String? = nil,
        receiveRelativePath: String? = nil,
        transcriptRelativePath: String?,
        transcriptMarkdownRelativePath: String?,
        transcriptionError: String?,
        studyFiling: StudyFilingPath? = nil,
        isDeleted: Bool = false,
        deletedAt: Date? = nil,
        noteRelativePath: String? = nil,
        noteError: String? = nil,
        transferProgress: LocalNetworkTransferProgress? = nil
    ) {
        self.id = id
        self.title = title
        self.receivedAt = receivedAt
        self.duration = duration
        self.fileSize = fileSize
        self.sourceDeviceID = sourceDeviceID
        self.sourceDeviceName = sourceDeviceName
        self.audioChecksum = audioChecksum
        self.transcriptionStatus = transcriptionStatus
        self.noteStatus = RecordingReceiveRecord.normalizedNoteStatus(noteStatus)
        self.noteRelativePath = noteRelativePath
        self.noteError = noteError
        self.receiveStatus = receiveStatus
        self.hasAudio = hasAudio
        self.audioRelativePath = audioRelativePath
        self.receiveRelativePath = receiveRelativePath
        self.transcriptRelativePath = transcriptRelativePath
        self.transcriptMarkdownRelativePath = transcriptMarkdownRelativePath
        self.transcriptionError = transcriptionError
        self.studyFiling = studyFiling?.isEmpty == true ? nil : studyFiling
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
        self.transferProgress = transferProgress
        let snapshot = LegacySyncStatusToCanonicalEffectiveStatusAdapter.macAudioSnapshot(
            recordingID: id,
            hasLocalAudio: hasAudio,
            audioChecksum: audioChecksum,
            audioByteSize: fileSize,
            receiveStatus: receiveStatus,
            transferVisible: transferProgress != nil
        )
        self.canonicalDisplaySyncState = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(for: snapshot)
    }

    var statusText: String {
        switch transcriptionStatus {
        case "queued", "transcribing":
            return RokuricsCopy.text("转写中", "Transcribing")
        case "transcribed":
            return RokuricsCopy.text("已转写", "Transcribed")
        case "failed":
            return RokuricsCopy.text("转写失败", "Transcript failed")
        default:
            return RokuricsCopy.text("待转写", "Needs transcript")
        }
    }

    var canStartTranscription: Bool {
        displayAudioAvailable && (transcriptionStatus == "notStarted" || transcriptionStatus == "failed")
    }

    var transcriptionActionText: String {
        transcriptionStatus == "failed" ? RokuricsCopy.text("重试", "Retry") : RokuricsCopy.text("转写", "Transcribe")
    }

    var isTranscribed: Bool {
        transcriptionStatus == "transcribed"
    }

    var isWaitingForTranscription: Bool {
        displayAudioAvailable && transcriptionStatus == "notStarted"
    }

    var isTranscriptionActive: Bool {
        transcriptionStatus == "queued" || transcriptionStatus == "transcribing"
    }

    var isNoteGenerating: Bool {
        noteStatus == "generating"
    }

    var isNoteGenerated: Bool {
        noteStatus == "generated" && noteRelativePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var isNoteFailed: Bool {
        noteStatus == "failed"
    }

    var displayAudioAvailable: Bool {
        canonicalDisplaySyncState.canDisplayAsComplete
    }

    var displayAudioStatusText: String {
        displayAudioAvailable ? RokuricsCopy.text("可用", "Available") : RokuricsCopy.text("缺失", "Missing")
    }

    var canStartNoteGeneration: Bool {
        isTranscribed && !isNoteGenerating
    }

    var localNetworkReceiveTransferProgress: LocalNetworkTransferProgress? {
        guard !displayAudioAvailable else {
            return nil
        }

        if let transferProgress, transferProgress.isVisibleInActionArea {
            return transferProgress
        }

        let state: LocalNetworkTransferState = receiveStatus == "failed" ? .failed : .transferring
        return LocalNetworkTransferProgress(
            objectID: "recordingAudio:\(id)",
            objectKind: LocalNetworkSyncObjectKind.recordingAudio.rawValue,
            state: state,
            progressFraction: state == .failed ? nil : 0,
            receivedBytes: 0,
            totalBytes: fileSize > 0 ? fileSize : nil,
            sourceDeviceID: nil,
            statusText: state == .failed ? RokuricsCopy.text("接收失败", "Receive failed") : RokuricsCopy.text("正在接收", "Receiving")
        )
    }

    var failureReasonSummary: String? {
        TranscriptionFailureReasonFormatter.summary(
            for: transcriptionError,
            transcriptionStatus: transcriptionStatus
        )
    }
}

enum TranscriptionFailureReasonFormatter {
    static func summary(
        for error: String?,
        transcriptionStatus: String,
        maxCharacters: Int = 320,
        maxLines: Int = 2
    ) -> String? {
        guard transcriptionStatus == "failed" else {
            return nil
        }

        let normalizedLines = (error ?? "")
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ";") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let rawSummary = diagnosticSummary(from: normalizedLines, maxLines: maxLines)

        let reason = rawSummary.isEmpty ? RokuricsCopy.text("未记录具体原因", "No specific reason recorded") : rawSummary
        let limitedReason: String
        if reason.count > maxCharacters {
            limitedReason = String(reason.prefix(maxCharacters)) + "..."
        } else {
            limitedReason = reason
        }

        return RokuricsCopy.text("失败原因：\(limitedReason)", "Reason: \(limitedReason)")
    }

    private static func diagnosticSummary(from lines: [String], maxLines: Int) -> String {
        guard let firstLine = lines.first else {
            return ""
        }

        if firstLine.hasPrefix("ffmpeg 启动失败") || firstLine.hasPrefix("whisper-cli 启动失败") {
            let details = diagnosticDetails(from: lines)
            let title = firstLine
                .components(separatedBy: "：")
                .first ?? firstLine
            let processExecutableURL = details["processExecutableURLPath"]
                ?? details["processExecutableURL"]
                ?? details["executable"]
            let currentDirectoryURL = details["currentDirectoryURLPath"]
                ?? details["currentDirectoryURL"]
            let fields = [
                processExecutableURL.map { "processExecutableURL=\($0)" },
                currentDirectoryURL.map { "currentDirectoryURL=\($0)" },
                details["rootDirectoryAccessStarted"].map { "rootDirectoryAccessStarted=\($0)" },
                details["nsErrorDomain"],
                details["nsErrorCode"].map { "code=\($0)" },
                details["description"]
            ]
            .compactMap { $0 }

            guard !fields.isEmpty else {
                return firstLine
            }

            return "\(title)：\(fields.joined(separator: "；"))"
        }

        return lines
            .prefix(max(1, maxLines))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func diagnosticDetails(from lines: [String]) -> [String: String] {
        var details: [String: String] = [:]
        for line in lines {
            let field = line
                .split(separator: "：", maxSplits: 1, omittingEmptySubsequences: false)
                .last
                .map(String.init) ?? line
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            details[String(parts[0])] = String(parts[1])
        }

        return details
    }
}
