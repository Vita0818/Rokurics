//
//  MacRecordingInboxItem.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/12.
//

import Foundation

struct MacRecordingInboxItem: Identifiable, Equatable {
    let id: String
    let title: String
    let receivedAt: Date
    let duration: TimeInterval
    let fileSize: Int64
    let sourceDeviceName: String
    let transcriptionStatus: String
    let noteStatus: String
    let receiveStatus: String
    let hasAudio: Bool
    let transcriptRelativePath: String?
    let transcriptMarkdownRelativePath: String?
    let transcriptionError: String?

    var statusText: String {
        switch transcriptionStatus {
        case "queued", "transcribing":
            return "转写中"
        case "transcribed":
            return "已转写"
        case "failed":
            return "转写失败"
        default:
            return "待转写"
        }
    }

    var canStartTranscription: Bool {
        hasAudio && (transcriptionStatus == "notStarted" || transcriptionStatus == "failed")
    }

    var transcriptionActionText: String {
        transcriptionStatus == "failed" ? "重试" : "转写"
    }

    var isTranscribed: Bool {
        transcriptionStatus == "transcribed"
    }

    var isWaitingForTranscription: Bool {
        hasAudio && transcriptionStatus == "notStarted"
    }

    var isTranscriptionActive: Bool {
        transcriptionStatus == "queued" || transcriptionStatus == "transcribing"
    }
}
