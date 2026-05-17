//
//  AnthropicMessagesNoteGenerationProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct AnthropicMessagesNoteGenerationProvider: NoteGenerationProvider {
    let id = "anthropicMessages"
    let displayName = "Claude / Anthropic"

    private let configuration: AnthropicMessagesConfiguration
    private let client: AnthropicMessagesNoteGenerationClient

    init(
        configuration: AnthropicMessagesConfiguration,
        client: AnthropicMessagesNoteGenerationClient = AnthropicMessagesNoteGenerationClient()
    ) {
        self.configuration = configuration
        self.client = client
    }

    func validateConfiguration() async throws {
        guard !configuration.trimmedModelName.isEmpty else {
            throw NoteGenerationError.unsupportedProvider("Claude modelName 为空")
        }
        guard !configuration.trimmedAPIKey.isEmpty else {
            throw AnthropicMessagesClientError.apiKeyMissing
        }
        guard !configuration.trimmedAnthropicVersion.isEmpty else {
            throw AnthropicMessagesClientError.anthropicVersionMissing
        }

        _ = try AnthropicMessagesNoteGenerationClient.endpointURL(
            baseURLString: configuration.baseURLString,
            path: "v1/messages"
        )
    }

    func generateNote(request: NoteGenerationRequest) async throws -> NoteGenerationResult {
        let startedAt = Date()
        let transcriptInput = OpenAICompatibleNoteGenerationProvider.transcriptInput(from: request)
        guard !transcriptInput.isEmpty else {
            throw NoteGenerationError.transcriptDocumentMissing
        }

        let truncatedTranscript = OpenAICompatibleNoteGenerationProvider.truncatedTranscript(
            transcriptInput,
            maxCharacters: configuration.maxTranscriptCharacters
        )
        let prompt = Self.prompt(
            request: request,
            transcript: truncatedTranscript.text,
            configuration: configuration,
            wasTruncated: truncatedTranscript.wasTruncated
        )
        let response = try await client.message(
            configuration: configuration,
            system: Self.systemPrompt,
            userContent: prompt,
            timeout: 180
        )
        let cleanedMarkdown = OpenAICompatibleNoteGenerationProvider.cleanedMarkdown(from: response.content)
        guard !cleanedMarkdown.isEmpty else {
            throw AnthropicMessagesClientError.emptyContent(
                AnthropicMessagesDiagnostics(
                    statusCode: nil,
                    bodyByteCount: 0,
                    contentBlockCount: 1,
                    textLength: 0,
                    stopReason: response.stopReason,
                    inputTokens: nil,
                    outputTokens: nil
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

    static func prompt(
        request: NoteGenerationRequest,
        transcript: String,
        configuration: AnthropicMessagesConfiguration,
        wasTruncated: Bool
    ) -> String {
        let transcriptNotice = wasTruncated
            ? "本次仅基于前 \(configuration.maxTranscriptCharacters) 字生成。"
            : "本次基于完整可用转写生成。"

        return """
        请根据以下转写生成 Markdown 笔记。

        录音标题：\(request.title)
        创建时间：\(displayDateFormatter.string(from: request.createdAt))
        时长：\(durationText(request.duration))
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
        - 如果转写内容很短，就如实生成简短笔记
        - 如果听不清或内容不足，要标注“需要回听确认”
        - 不要输出 AI 自己的思考过程
        - 不要输出英文内部分析
        - 不要输出 JSON
        - 只输出 Markdown 正文

        转写正文：

        \(transcript)
        """
    }

    static func finalNoteMarkdown(
        modelMarkdown: String,
        configuration: AnthropicMessagesConfiguration,
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
            : "\n" + notices.map { "> \($0)" }.joined(separator: "\n")

        return """
        # 录音笔记

        > 由 Rokurics AI 根据转写生成
        > Provider: Claude / Anthropic
        > Model: \(configuration.trimmedModelName)\(noticeBlock)

        \(body)
        """
    }

    static let systemPrompt = """
    你是 Rokurics 的中文课堂笔记整理助手。你的任务是把课堂录音转写整理成清晰、准确、适合复习的 Markdown 笔记。只输出最终 Markdown，不要输出思考过程、草稿、推理步骤、分析过程或任何与笔记无关的说明。不要输出 Drafting、Initial thought、Determine structure、analysis、reasoning 或类似内部过程文字。
    """

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
