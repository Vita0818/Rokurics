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

        let reason = rawSummary.isEmpty ? "未记录具体原因" : rawSummary
        let limitedReason: String
        if reason.count > maxCharacters {
            limitedReason = String(reason.prefix(maxCharacters)) + "..."
        } else {
            limitedReason = reason
        }

        return "失败原因：\(limitedReason)"
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
