//
//  MockTranscriptionProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct MockTranscriptionProvider: TranscriptionProvider {
    let id = "mock"
    let displayName = "Mock Transcription"

    func validateConfiguration() async throws {
        // Mock provider has no external dependencies.
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult {
        let startedAt = Date()
        try await Task.sleep(nanoseconds: 500_000_000)

        let text = """
        这是一段由 Rokurics MockTranscriptionProvider 生成的测试转写文本。
        真实转写引擎尚未配置。
        """

        let segments = [
            TranscriptionSegment(
                id: "\(request.taskID)-segment-1",
                startTime: 0,
                endTime: 5,
                text: "这是一段由 Rokurics MockTranscriptionProvider 生成的测试转写文本。",
                confidence: 1.0
            ),
            TranscriptionSegment(
                id: "\(request.taskID)-segment-2",
                startTime: 5,
                endTime: 9,
                text: "真实转写引擎尚未配置。",
                confidence: 1.0
            )
        ]

        return TranscriptionResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: id,
            providerName: displayName,
            modelName: "mock-local",
            language: request.language ?? "auto",
            text: text,
            segments: segments,
            startedAt: startedAt,
            completedAt: Date(),
            status: "transcribed"
        )
    }
}
