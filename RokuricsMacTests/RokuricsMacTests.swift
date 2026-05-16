//
//  RokuricsMacTests.swift
//  RokuricsMacTests
//
//  Created by Vita on 2026/5/10.
//

import Foundation
import Testing
@testable import RokuricsMac

struct RokuricsMacTests {

    @Test func failedInboxItemShowsShortTranscriptionErrorSummary() {
        let item = makeInboxItem(
            transcriptionStatus: "failed",
            transcriptionError: "ffmpeg 转码失败：exitCode=1\nstderr=invalid data"
        )

        #expect(item.failureReasonSummary == "失败原因：ffmpeg 转码失败：exitCode=1 stderr=invalid data")
    }

    @Test func failureReasonSummaryIsHiddenForSuccessfulItems() {
        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: "old error"
        )

        #expect(item.failureReasonSummary == nil)
    }

    @Test func longFailureReasonSummaryIsTruncated() {
        let summary = TranscriptionFailureReasonFormatter.summary(
            for: String(repeating: "a", count: 260),
            transcriptionStatus: "failed",
            maxCharacters: 160
        )

        #expect(summary?.hasPrefix("失败原因：") == true)
        #expect(summary?.hasSuffix("...") == true)
        #expect((summary?.count ?? 0) <= 168)
    }

    @Test func ffmpegLaunchFailureSummaryHighlightsNSErrorDetails() {
        let error = """
        ffmpeg 启动失败：
        stage=ffmpeg process launch
        configuredExecutable=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg
        authorizedExecutable=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg
        processExecutableURLPath=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg
        nsErrorDomain=NSCocoaErrorDomain
        nsErrorCode=260
        description=The file “ffmpeg” doesn’t exist.
        """

        let summary = TranscriptionFailureReasonFormatter.summary(
            for: error,
            transcriptionStatus: "failed",
            maxCharacters: 220
        )

        #expect(summary?.contains("processExecutableURL=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg") == true)
        #expect(summary?.contains("NSCocoaErrorDomain") == true)
        #expect(summary?.contains("code=260") == true)
    }

    @Test func ffmpegLaunchFailureSummaryParsesSemicolonDiagnostics() {
        let error = "ffmpeg 启动失败：stage=ffmpeg process launch; processExecutableURLPath=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg; nsErrorDomain=NSCocoaErrorDomain; nsErrorCode=4; description=The file “ffmpeg” doesn’t exist.; bookmarkDataByteCount=6"

        let summary = TranscriptionFailureReasonFormatter.summary(
            for: error,
            transcriptionStatus: "failed",
            maxCharacters: 220
        )

        #expect(summary?.contains("processExecutableURL=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg") == true)
        #expect(summary?.contains("NSCocoaErrorDomain") == true)
        #expect(summary?.contains("code=4") == true)
        #expect(summary?.contains("bookmarkDataByteCount") == false)
    }

    @Test func whisperLaunchFailureSummaryHighlightsProcessExecutableURL() {
        let error = """
        whisper-cli 启动失败：
        stage=whisper-cli process launch
        processExecutableURLPath=/Users/vita/ThirdParty/whisper.cpp/build/bin/whisper-cli
        currentDirectoryURLPath=/Users/vita/ThirdParty/whisper.cpp
        rootDirectoryAccessStarted=true
        nsErrorDomain=NSCocoaErrorDomain
        nsErrorCode=4
        description=The file “whisper-cli” doesn’t exist.
        executableBookmarkDataByteCount=944
        """

        let summary = TranscriptionFailureReasonFormatter.summary(
            for: error,
            transcriptionStatus: "failed",
            maxCharacters: 260
        )

        #expect(summary?.contains("processExecutableURL=/Users/vita/ThirdParty/whisper.cpp/build/bin/whisper-cli") == true)
        #expect(summary?.contains("currentDirectoryURL=/Users/vita/ThirdParty/whisper.cpp") == true)
        #expect(summary?.contains("rootDirectoryAccessStarted=true") == true)
        #expect(summary?.contains("NSCocoaErrorDomain") == true)
        #expect(summary?.contains("code=4") == true)
        #expect(summary?.contains("executableBookmarkDataByteCount") == false)
    }

    @Test func nativeConversionFailureSummaryStaysShort() {
        let summary = TranscriptionFailureReasonFormatter.summary(
            for: "native audio conversion failed: stage=wav writing message=The operation could not be completed.",
            transcriptionStatus: "failed",
            maxCharacters: 220
        )

        #expect(summary == "失败原因：native audio conversion failed: stage=wav writing message=The operation could not be completed.")
    }

    @Test func whisperTextOutputPathMatchesOutputPrefixRule() {
        let outputPrefix = URL(fileURLWithPath: "/tmp/rokurics/whisper-task-01")

        #expect(WhisperCppOutputPaths.expectedTextOutputURL(outputPrefix: outputPrefix).path == "/tmp/rokurics/whisper-task-01.txt")
        #expect(WhisperCppOutputPaths.alternateWavTextOutputURL(outputPrefix: outputPrefix).path == "/tmp/rokurics/whisper-task-01.wav.txt")
    }

    private func makeInboxItem(
        transcriptionStatus: String,
        transcriptionError: String?
    ) -> MacRecordingInboxItem {
        MacRecordingInboxItem(
            id: "recording-01",
            title: "录音 2026-05-16 12:46",
            receivedAt: Date(timeIntervalSince1970: 0),
            duration: 6,
            fileSize: 1024,
            sourceDeviceName: "iPhone",
            transcriptionStatus: transcriptionStatus,
            noteStatus: "notStarted",
            receiveStatus: "received",
            hasAudio: true,
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            transcriptionError: transcriptionError
        )
    }

}
