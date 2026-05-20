//
//  LongProcessingModels.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/18.
//

import Foundation

enum LongProcessingDefaults {
    static let transcriptionChunkDuration: TimeInterval = 15 * 60
    static let transcriptionChunkingThreshold: TimeInterval = 30 * 60
    static let noteMaxTranscriptCharacters = 12_000
    static let noteChunkCharacters = 10_000
}

enum LongProcessingIDFormatter {
    static func zeroPadded(_ value: Int, width: Int = 3) -> String {
        let rawValue = String(value)
        guard rawValue.count < width else {
            return rawValue
        }
        return String(repeating: "0", count: width - rawValue.count) + rawValue
    }
}

enum ProcessingMode: String, Codable, Equatable {
    case single
    case chunked
}

enum ProcessingChunkStatus: String, Codable, Equatable {
    case pending
    case processing
    case generated
    case failed
}

struct AudioChunkDescriptor: Codable, Equatable, Identifiable {
    var id: String { "chunk_\(LongProcessingIDFormatter.zeroPadded(index))" }
    let index: Int
    let startTime: TimeInterval
    let endTime: TimeInterval

    var duration: TimeInterval {
        max(0, endTime - startTime)
    }
}

struct AudioChunkPlan: Codable, Equatable {
    let mode: ProcessingMode
    let sourceDuration: TimeInterval
    let chunkDuration: TimeInterval
    let threshold: TimeInterval
    let chunks: [AudioChunkDescriptor]

    var shouldUseChunking: Bool {
        mode == .chunked
    }
}

struct RecordingTranscriptionChunkRecord: Codable, Equatable {
    var index: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    var status: ProcessingChunkStatus
    var transcriptRelativePath: String?
    var transcriptMarkdownRelativePath: String?
    var error: String?

    init(
        index: Int,
        startTime: TimeInterval,
        endTime: TimeInterval,
        status: ProcessingChunkStatus = .pending,
        transcriptRelativePath: String? = nil,
        transcriptMarkdownRelativePath: String? = nil,
        error: String? = nil
    ) {
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.transcriptRelativePath = transcriptRelativePath
        self.transcriptMarkdownRelativePath = transcriptMarkdownRelativePath
        self.error = error
    }

    init(descriptor: AudioChunkDescriptor, status: ProcessingChunkStatus = .pending, error: String? = nil) {
        self.init(
            index: descriptor.index,
            startTime: descriptor.startTime,
            endTime: descriptor.endTime,
            status: status,
            error: error
        )
    }
}

enum LongAudioTranscriptionPlanner {
    static func plan(
        duration: TimeInterval,
        threshold: TimeInterval = LongProcessingDefaults.transcriptionChunkingThreshold,
        chunkDuration: TimeInterval = LongProcessingDefaults.transcriptionChunkDuration
    ) -> AudioChunkPlan {
        let safeDuration = max(0, duration)
        let safeThreshold = max(1, threshold)
        let safeChunkDuration = max(1, chunkDuration)

        guard safeDuration > safeThreshold else {
            return AudioChunkPlan(
                mode: .single,
                sourceDuration: safeDuration,
                chunkDuration: safeChunkDuration,
                threshold: safeThreshold,
                chunks: []
            )
        }

        var chunks: [AudioChunkDescriptor] = []
        var start: TimeInterval = 0
        var index = 0
        while start < safeDuration {
            let end = min(safeDuration, start + safeChunkDuration)
            chunks.append(AudioChunkDescriptor(index: index, startTime: start, endTime: end))
            start = end
            index += 1
        }

        return AudioChunkPlan(
            mode: .chunked,
            sourceDuration: safeDuration,
            chunkDuration: safeChunkDuration,
            threshold: safeThreshold,
            chunks: chunks
        )
    }
}

enum TranscriptionChunkMerger {
    static func merge(
        recordingID: String,
        taskID: String,
        chunks: [(descriptor: AudioChunkDescriptor, result: TranscriptionResult)]
    ) -> TranscriptionResult {
        let orderedChunks = chunks.sorted { $0.descriptor.index < $1.descriptor.index }
        let text = orderedChunks
            .map { $0.result.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let segments = orderedChunks.flatMap { chunk in
            chunk.result.segments.map { segment in
                TranscriptionSegment(
                    id: "chunk_\(chunk.descriptor.index)_\(segment.id)",
                    startTime: chunk.descriptor.startTime + segment.startTime,
                    endTime: chunk.descriptor.startTime + segment.endTime,
                    text: segment.text,
                    confidence: segment.confidence
                )
            }
        }
        let first = orderedChunks.first?.result
        let startedAt = orderedChunks.map(\.result.startedAt).min() ?? Date()
        let completedAt = orderedChunks.map(\.result.completedAt).max() ?? Date()

        return TranscriptionResult(
            taskID: taskID,
            recordingID: recordingID,
            providerID: first?.providerID ?? "chunked",
            providerName: first?.providerName ?? "Chunked Transcription",
            modelName: first?.modelName,
            language: first?.language,
            text: text,
            segments: segments,
            startedAt: startedAt,
            completedAt: completedAt,
            status: "transcribed"
        )
    }
}

enum WhisperModelKind: String, Codable, Equatable {
    case unknown
    case tiny
    case base
    case small
    case medium
    case large
    case largeV3
    case largeV3Turbo

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .largeV3: return "Large v3"
        case .largeV3Turbo: return "Large v3 Turbo"
        }
    }

    var isLargePreferred: Bool {
        self == .large || self == .largeV3 || self == .largeV3Turbo
    }

    static func infer(fromModelFileName fileName: String?) -> WhisperModelKind {
        let normalized = (fileName ?? "").lowercased()
        if normalized.contains("large-v3-turbo") || normalized.contains("large_v3_turbo") {
            return .largeV3Turbo
        }
        if normalized.contains("large-v3") || normalized.contains("large_v3") {
            return .largeV3
        }
        if normalized.contains("large") {
            return .large
        }
        if normalized.contains("medium") {
            return .medium
        }
        if normalized.contains("small") {
            return .small
        }
        if normalized.contains("base") {
            return .base
        }
        if normalized.contains("tiny") {
            return .tiny
        }
        return .unknown
    }
}

enum WhisperTranscriptionTimeoutPolicy {
    static func timeout(
        audioDuration: TimeInterval?,
        modelKind: WhisperModelKind,
        minimum: TimeInterval = 10 * 60,
        secondsPerAudioSecond: Double? = nil
    ) -> TimeInterval {
        guard let audioDuration, audioDuration > 0 else {
            return 30 * 60
        }

        let multiplier: Double
        if let secondsPerAudioSecond {
            multiplier = secondsPerAudioSecond
        } else {
            switch modelKind {
            case .large, .largeV3, .largeV3Turbo:
                multiplier = 8
            case .medium:
                multiplier = 6
            case .small:
                multiplier = 4
            default:
                multiplier = 5
            }
        }

        return max(minimum, audioDuration * multiplier)
    }
}

struct TranscriptTextChunk: Codable, Equatable, Identifiable {
    var id: String { "section_\(LongProcessingIDFormatter.zeroPadded(index))" }
    let index: Int
    let sourceStart: Int
    let sourceEnd: Int
    let text: String
}

struct LongNotePlan: Codable, Equatable {
    let mode: ProcessingMode
    let maxTranscriptCharacters: Int
    let chunkCharacters: Int
    let chunks: [TranscriptTextChunk]

    var shouldUseChunking: Bool {
        mode == .chunked
    }
}

struct RecordingNoteSectionRecord: Codable, Equatable {
    var index: Int
    var sourceStart: Int
    var sourceEnd: Int
    var status: ProcessingChunkStatus
    var sectionNoteRelativePath: String?
    var error: String?

    init(
        index: Int,
        sourceStart: Int,
        sourceEnd: Int,
        status: ProcessingChunkStatus = .pending,
        sectionNoteRelativePath: String? = nil,
        error: String? = nil
    ) {
        self.index = index
        self.sourceStart = sourceStart
        self.sourceEnd = sourceEnd
        self.status = status
        self.sectionNoteRelativePath = sectionNoteRelativePath
        self.error = error
    }

    init(chunk: TranscriptTextChunk, status: ProcessingChunkStatus = .pending, sectionNoteRelativePath: String? = nil, error: String? = nil) {
        self.init(
            index: chunk.index,
            sourceStart: chunk.sourceStart,
            sourceEnd: chunk.sourceEnd,
            status: status,
            sectionNoteRelativePath: sectionNoteRelativePath,
            error: error
        )
    }
}

struct NoteSectionSummary: Codable, Equatable {
    let index: Int
    let sourceStart: Int
    let sourceEnd: Int
    let markdown: String
    let relativePath: String?
}

enum LongNoteGenerationPlanner {
    static func plan(
        transcript: String,
        maxTranscriptCharacters: Int = LongProcessingDefaults.noteMaxTranscriptCharacters,
        chunkCharacters: Int = LongProcessingDefaults.noteChunkCharacters
    ) -> LongNotePlan {
        let maxCharacters = max(1, maxTranscriptCharacters)
        let chunkSize = max(1, chunkCharacters)
        guard transcript.count > maxCharacters else {
            return LongNotePlan(
                mode: .single,
                maxTranscriptCharacters: maxCharacters,
                chunkCharacters: chunkSize,
                chunks: []
            )
        }

        return LongNotePlan(
            mode: .chunked,
            maxTranscriptCharacters: maxCharacters,
            chunkCharacters: chunkSize,
            chunks: TranscriptChunker.chunk(transcript, chunkCharacters: chunkSize)
        )
    }
}

enum TranscriptChunker {
    static func chunk(_ transcript: String, chunkCharacters: Int) -> [TranscriptTextChunk] {
        let chunkSize = max(1, chunkCharacters)
        var chunks: [TranscriptTextChunk] = []
        var offset = 0
        var startIndex = transcript.startIndex

        while startIndex < transcript.endIndex {
            let endIndex = transcript.index(startIndex, offsetBy: chunkSize, limitedBy: transcript.endIndex) ?? transcript.endIndex
            let text = String(transcript[startIndex..<endIndex])
            chunks.append(TranscriptTextChunk(
                index: chunks.count,
                sourceStart: offset,
                sourceEnd: offset + text.count,
                text: text
            ))
            offset += text.count
            startIndex = endIndex
        }

        return chunks
    }
}

enum NoteSectionSynthesizer {
    static func composeFinalNote(title: String, sections: [NoteSectionSummary], providerName: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "录音笔记" : title
        let orderedSections = sections.sorted { $0.index < $1.index }
        let summaryText = orderedSections
            .compactMap { NoteSummaryPreview.shortSummary(from: $0.markdown) }
            .prefix(3)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = orderedSections.map { section in
            """
            ## Section \(LongProcessingIDFormatter.zeroPadded(section.index + 1))

            \(section.markdown.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        }
        .joined(separator: "\n\n")

        return """
        # 录音笔记

        - Provider: \(providerName)
        - Mode: chunked
        - Sections: \(orderedSections.count)
        - Title: \(normalizedTitle)

        ## 摘要

        \(summaryText.isEmpty ? "这是一条分段生成的长文本笔记，请阅读下方分段总结。" : summaryText)

        ## 分段总结

        \(body)
        """
    }
}

struct ChunkedNoteGenerationOutput {
    let result: NoteGenerationResult
    let sectionRecords: [RecordingNoteSectionRecord]
    let sectionSummaries: [NoteSectionSummary]
}

struct ChunkedNoteGenerationFailure: LocalizedError {
    let message: String
    let sectionRecords: [RecordingNoteSectionRecord]

    var errorDescription: String? {
        message
    }
}

struct LongProcessingDiagnosticReportInput: Equatable {
    var recordingDuration: TimeInterval
    var audioFileSize: Int64
    var transcriptionMode: ProcessingMode
    var chunkCount: Int
    var failedChunkIndexes: [Int]
    var transcriptCharacterCount: Int
    var noteGenerationMode: ProcessingMode
    var sectionCount: Int
    var failedSectionIndexes: [Int]
    var modelKind: WhisperModelKind
    var chunkDuration: TimeInterval

    init(
        recordingDuration: TimeInterval,
        audioFileSize: Int64,
        transcriptionMode: ProcessingMode,
        chunkCount: Int,
        failedChunkIndexes: [Int] = [],
        transcriptCharacterCount: Int,
        noteGenerationMode: ProcessingMode,
        sectionCount: Int,
        failedSectionIndexes: [Int] = [],
        modelKind: WhisperModelKind,
        chunkDuration: TimeInterval = LongProcessingDefaults.transcriptionChunkDuration
    ) {
        self.recordingDuration = recordingDuration
        self.audioFileSize = audioFileSize
        self.transcriptionMode = transcriptionMode
        self.chunkCount = chunkCount
        self.failedChunkIndexes = failedChunkIndexes
        self.transcriptCharacterCount = transcriptCharacterCount
        self.noteGenerationMode = noteGenerationMode
        self.sectionCount = sectionCount
        self.failedSectionIndexes = failedSectionIndexes
        self.modelKind = modelKind
        self.chunkDuration = chunkDuration
    }
}

enum LongProcessingDiagnosticReport {
    static let debugMarker = "1636"

    static func markdown(input: LongProcessingDiagnosticReportInput) -> String {
        """
        # Rokurics Long Processing Diagnostic Report

        \(debugMarker)

        ## Audio

        - Duration: \(minutes(input.recordingDuration)) minutes
        - Audio file size: \(input.audioFileSize) bytes
        - Estimated chunk count: \(input.chunkCount)
        - Chunk duration: \(minutes(input.chunkDuration)) minutes
        - Transcription mode: \(input.transcriptionMode.rawValue)
        - Failed chunk indexes: \(indexSummary(input.failedChunkIndexes))
        - Model grade: \(input.modelKind.displayName)

        ## Note Generation

        - Transcript characters: \(input.transcriptCharacterCount)
        - Note mode: \(input.noteGenerationMode.rawValue)
        - Section count: \(input.sectionCount)
        - Failed note section indexes: \(indexSummary(input.failedSectionIndexes))

        ## Risks

        - \(input.failedChunkIndexes.isEmpty ? "No failed chunks" : "Failed chunks require retry")
        - \(input.failedSectionIndexes.isEmpty ? "No failed note sections" : "Failed note sections require retry")
        """
    }

    private static func minutes(_ seconds: TimeInterval) -> String {
        let value = seconds / 60
        if value.rounded() == value {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private static func indexSummary(_ indexes: [Int]) -> String {
        indexes.isEmpty ? "none" : indexes.map(String.init).joined(separator: ", ")
    }
}

struct ChunkedNoteGenerationRunner {
    let provider: any NoteGenerationProvider
    let noteStore: NoteStore

    func generate(
        request: NoteGenerationRequest,
        plan: LongNotePlan
    ) async throws -> ChunkedNoteGenerationOutput {
        guard plan.mode == .chunked else {
            let result = try await provider.generateNote(request: request)
            return ChunkedNoteGenerationOutput(result: result, sectionRecords: [], sectionSummaries: [])
        }

        var sectionRecords = plan.chunks.map { RecordingNoteSectionRecord(chunk: $0) }
        var summaries: [NoteSectionSummary] = []
        var firstModelName: String?
        let startedAt = Date()

        for chunk in plan.chunks {
            sectionRecords[chunk.index].status = .processing
            let sectionRequest = NoteGenerationRequest(
                taskID: "\(request.taskID)-section-\(LongProcessingIDFormatter.zeroPadded(chunk.index))",
                recordingID: request.recordingID,
                sanitizedRecordingID: request.sanitizedRecordingID,
                title: "\(request.title) section \(chunk.index + 1)",
                createdAt: request.createdAt,
                duration: request.duration,
                transcriptRelativePath: request.transcriptRelativePath,
                transcriptMarkdownRelativePath: request.transcriptMarkdownRelativePath,
                transcriptionProviderID: request.transcriptionProviderID,
                transcriptionModelName: request.transcriptionModelName,
                transcriptResult: nil,
                transcriptMarkdown: chunk.text,
                requestedAt: request.requestedAt
            )

            do {
                let sectionResult = try await provider.generateNote(request: sectionRequest)
                firstModelName = firstModelName ?? sectionResult.modelName
                let saveResult = try noteStore.saveSection(
                    markdown: sectionResult.markdown,
                    request: request,
                    sectionIndex: chunk.index
                )
                sectionRecords[chunk.index].status = .generated
                sectionRecords[chunk.index].sectionNoteRelativePath = saveResult.sectionNoteRelativePath
                summaries.append(NoteSectionSummary(
                    index: chunk.index,
                    sourceStart: chunk.sourceStart,
                    sourceEnd: chunk.sourceEnd,
                    markdown: sectionResult.markdown,
                    relativePath: saveResult.sectionNoteRelativePath
                ))
            } catch {
                sectionRecords[chunk.index].status = .failed
                sectionRecords[chunk.index].error = "section \(chunk.index) failed: \(error.localizedDescription)"
                throw ChunkedNoteGenerationFailure(
                    message: sectionRecords[chunk.index].error ?? "section_summary_failed",
                    sectionRecords: sectionRecords
                )
            }
        }

        let finalMarkdown = NoteSectionSynthesizer.composeFinalNote(
            title: request.title,
            sections: summaries,
            providerName: provider.displayName
        )
        let result = NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: provider.id,
            providerName: provider.displayName,
            modelName: firstModelName,
            markdown: finalMarkdown,
            startedAt: startedAt,
            completedAt: Date(),
            status: "generated"
        )
        return ChunkedNoteGenerationOutput(
            result: result,
            sectionRecords: sectionRecords,
            sectionSummaries: summaries
        )
    }
}
