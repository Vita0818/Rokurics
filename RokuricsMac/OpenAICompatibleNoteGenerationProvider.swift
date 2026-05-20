//
//  OpenAICompatibleNoteGenerationProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct OpenAICompatibleNoteGenerationProvider: NoteGenerationProvider {
    let id = "openAICompatible"
    let displayName = "OpenAI-compatible"

    private let configuration: OpenAICompatibleNoteGenerationConfiguration
    private let client: OpenAICompatibleNoteGenerationClient

    init(
        configuration: OpenAICompatibleNoteGenerationConfiguration,
        client: OpenAICompatibleNoteGenerationClient = OpenAICompatibleNoteGenerationClient()
    ) {
        self.configuration = configuration
        self.client = client
    }

    func validateConfiguration() async throws {
        guard !configuration.trimmedModelName.isEmpty else {
            throw NoteGenerationError.unsupportedProvider("modelName 为空")
        }

        _ = try OpenAICompatibleNoteGenerationClient.endpointURL(
            baseURLString: configuration.baseURLString,
            path: "chat/completions"
        )
    }

    func generateNote(request: NoteGenerationRequest) async throws -> NoteGenerationResult {
        let startedAt = Date()
        let transcriptInput = Self.transcriptInput(from: request)
        guard !transcriptInput.isEmpty else {
            throw NoteGenerationError.transcriptDocumentMissing
        }
        let truncatedTranscript = Self.truncatedTranscript(
            transcriptInput,
            maxCharacters: configuration.maxTranscriptCharacters
        )
        let messages = Self.messages(
            request: request,
            transcript: truncatedTranscript.text,
            configuration: configuration,
            wasTruncated: truncatedTranscript.wasTruncated
        )
        let response = try await client.chatCompletion(
            configuration: configuration,
            messages: messages,
            timeout: 180
        )
        let cleanedMarkdown = Self.cleanedMarkdown(from: response.content)
        guard !cleanedMarkdown.isEmpty else {
            throw OpenAICompatibleNoteGenerationClientError.emptyContent(
                OpenAICompatibleChatDiagnostics(
                    statusCode: nil,
                    bodyByteCount: 0,
                    choicesCount: 1,
                    finishReason: response.finishReason,
                    messageContentWasPresent: true,
                    contentLength: 0,
                    reasoningContentWasPresent: false,
                    reasoningContentLength: 0,
                    promptTokens: nil,
                    completionTokens: nil,
                    totalTokens: nil,
                    reasoningTokens: nil
                )
            )
        }

        let noteMarkdown = Self.finalNoteMarkdown(
            modelMarkdown: cleanedMarkdown,
            configuration: configuration,
            modelOutputWasTruncated: response.isLengthLimited,
            transcriptInputWasTruncated: truncatedTranscript.wasTruncated
        )

        return NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: id,
            providerName: displayName,
            modelName: configuration.trimmedModelName,
            markdown: noteMarkdown,
            startedAt: startedAt,
            completedAt: Date(),
            status: "generated",
            modelOutputWasTruncated: response.isLengthLimited,
            transcriptInputWasTruncated: truncatedTranscript.wasTruncated
        )
    }

    static func transcriptInput(from request: NoteGenerationRequest) -> String {
        let markdown = request.transcriptMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let markdown, !markdown.isEmpty {
            return markdown
        }

        let jsonText = request.transcriptResult?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let jsonText, !jsonText.isEmpty {
            return jsonText
        }

        return ""
    }

    static func truncatedTranscript(_ transcript: String, maxCharacters: Int) -> (text: String, wasTruncated: Bool) {
        let normalizedLimit = max(1, maxCharacters)
        guard transcript.count > normalizedLimit else {
            return (transcript, false)
        }

        return (String(transcript.prefix(normalizedLimit)), true)
    }

    static func messages(
        request: NoteGenerationRequest,
        transcript: String,
        configuration: OpenAICompatibleNoteGenerationConfiguration,
        wasTruncated: Bool
    ) -> [OpenAICompatibleMessage] {
        let transcriptNotice = wasTruncated
            ? "本次仅基于前 \(configuration.maxTranscriptCharacters) 字生成。"
            : "本次基于完整可用转写生成。"

        return [
            OpenAICompatibleMessage(
                role: "system",
                content: """
                你是 Rokurics 的中文课堂笔记整理助手。你的任务是把课堂录音转写整理成清晰、准确、适合复习的 Markdown 笔记。只输出最终 Markdown，不要输出思考过程、草稿、推理步骤、分析过程或任何与笔记无关的说明。不要输出 Drafting、Initial thought、Determine structure、analysis、reasoning 或类似内部过程文字。
                """
            ),
            OpenAICompatibleMessage(
                role: "user",
                content: """
                请根据以下转写生成 Markdown 笔记。

                录音标题：\(request.title)
                创建时间：\(Self.displayDateFormatter.string(from: request.createdAt))
                时长：\(Self.durationText(request.duration))
                转写模型：\(request.transcriptionModelName ?? request.transcriptResult?.modelName ?? "unknown")
                \(transcriptNotice)

                输出结构必须是：

                # 录音笔记

                ## 摘要

                ## 大纲

                ## 重点

                ## 待复习问题

                ## 可整理为 Kikaria 知识卡的候选内容

                规则：
                - 不要编造转写中没有的信息
                - “## 摘要”必须包含 1～3 句简短摘要，适合显示在录音详情页摘要卡片中
                - 如果转写内容很短，就如实生成简短笔记
                - 如果听不清或内容不足，要标注“需要回听确认”
                - 不要输出 AI 自己的思考过程
                - 不要输出英文内部分析
                - 不要输出 JSON
                - 只输出 Markdown 正文

                转写正文：

                \(transcript)
                """
            )
        ]
    }

    static func cleanedMarkdown(from content: String) -> String {
        var markdown = content.trimmingCharacters(in: .whitespacesAndNewlines)

        if markdown.hasPrefix("```markdown") {
            markdown = String(markdown.dropFirst("```markdown".count))
        } else if markdown.hasPrefix("```") {
            markdown = String(markdown.dropFirst("```".count))
        }

        markdown = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if markdown.hasSuffix("```") {
            markdown = String(markdown.dropLast(3))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let titleRange = markdown.range(of: "# 录音笔记") {
            markdown = String(markdown[titleRange.lowerBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return markdownWithoutInternalPreamble(markdown)
    }

    private static func markdownWithoutInternalPreamble(_ markdown: String) -> String {
        var lines = markdown.components(separatedBy: .newlines)
        while let firstLine = lines.first {
            let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()
            let isInternalProcessLine = [
                "drafting",
                "initial thought",
                "determine structure",
                "analysis",
                "reasoning"
            ].contains { lowercased.contains($0) }

            guard trimmed.isEmpty || isInternalProcessLine else {
                break
            }

            lines.removeFirst()
        }

        if let firstHeadingIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("#") || trimmed.hasPrefix("##")
        }), firstHeadingIndex > 0 {
            lines = Array(lines[firstHeadingIndex...])
        }

        return lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func finalNoteMarkdown(
        modelMarkdown: String,
        configuration: OpenAICompatibleNoteGenerationConfiguration,
        modelOutputWasTruncated: Bool,
        transcriptInputWasTruncated: Bool
    ) -> String {
        var body = modelMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("# 录音笔记") {
            body = body
                .components(separatedBy: .newlines)
                .dropFirst()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var notices: [String] = []
        if modelOutputWasTruncated {
            notices.append("注意：模型输出可能因长度限制被截断。")
        }
        if transcriptInputWasTruncated {
            notices.append("注意：本笔记基于转写前 \(configuration.maxTranscriptCharacters) 字生成，后续将支持分段总结。")
        }

        let noticeBlock = notices.isEmpty
            ? ""
            : "\n\n" + notices.map { "> \($0)" }.joined(separator: "\n")

        return """
        # 录音笔记

        > 由 Rokurics 本地 AI 根据转写生成
        > Provider: OpenAI-compatible
        > Model: \(configuration.trimmedModelName)\(noticeBlock)

        \(body)
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
