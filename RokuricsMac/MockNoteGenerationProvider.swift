//
//  MockNoteGenerationProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct MockNoteGenerationProvider: NoteGenerationProvider {
    let id = "mockNoteGenerationProvider"
    let displayName = "Mock Note Generation"

    func validateConfiguration() async throws {
        // Mock note generation has no external dependencies.
    }

    func generateNote(request: NoteGenerationRequest) async throws -> NoteGenerationResult {
        let startedAt = Date()
        let transcriptBody = transcriptBody(for: request)
        let markdown = Self.markdown(
            request: request,
            providerName: displayName,
            generatedAt: startedAt,
            transcriptBody: transcriptBody
        )

        return NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: id,
            providerName: displayName,
            modelName: "mock-note-local",
            markdown: markdown,
            startedAt: startedAt,
            completedAt: Date(),
            status: "generated"
        )
    }

    private func transcriptBody(for request: NoteGenerationRequest) -> String {
        let markdown = request.transcriptMarkdown?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let markdown, !markdown.isEmpty {
            return markdown
        }

        let text = request.transcriptResult?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty {
            return text
        }

        return "未读取到转写正文。"
    }

    private static func markdown(
        request: NoteGenerationRequest,
        providerName: String,
        generatedAt: Date,
        transcriptBody: String
    ) -> String {
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "未命名录音"
            : request.title
        let transcriptSource = request.transcriptMarkdownRelativePath
            ?? request.transcriptRelativePath
            ?? "unknown"
        let modelName = request.transcriptionModelName
            ?? request.transcriptResult?.modelName
            ?? "unknown"
        let transcriptionProvider = request.transcriptionProviderID
            ?? request.transcriptResult?.providerID
            ?? "unknown"

        return """
        # 录音笔记

        ## 基本信息

        - 标题：\(title)
        - 创建时间：\(Self.displayDateFormatter.string(from: request.createdAt))
        - 时长：\(Self.durationText(request.duration))
        - 转写模型：\(modelName)
        - 转写来源：\(transcriptSource)
        - 转写 Provider：\(transcriptionProvider)
        - 笔记 Provider：\(providerName)
        - 生成时间：\(Self.displayDateFormatter.string(from: generatedAt))

        ## 摘要

        这是由 MockNoteGenerationProvider 生成的占位笔记，用于验证 Rokurics 笔记生成链路。

        ## 大纲

        - 待真实 AI 接入后生成课程大纲
        - 待真实 AI 接入后提炼重点
        - 待真实 AI 接入后生成复习问题

        ## 待复习问题

        1. 这段录音主要讲了什么？
        2. 哪些概念需要整理为 Kikaria 知识卡？
        3. 哪些内容需要回听确认？

        ## 原始转写

        \(transcriptBody)
        """
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
