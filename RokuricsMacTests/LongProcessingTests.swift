//
//  LongProcessingTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/18.
//

import Foundation
import Testing
@testable import RokuricsMac

struct LongProcessingTests {
    @Test func threeHourDurationGeneratesChunkPlan() throws {
        let plan = LongAudioTranscriptionPlanner.plan(duration: 3 * 60 * 60)
        let first = try #require(plan.chunks.first)
        let last = try #require(plan.chunks.last)

        #expect(plan.mode == .chunked)
        #expect(plan.chunks.count == 12)
        #expect(plan.chunkDuration == 15 * 60)
        #expect(plan.threshold == 30 * 60)
        #expect(first.id == "chunk_000")
        #expect(first.startTime == TimeInterval(0))
        #expect(first.endTime == TimeInterval(15 * 60))
        #expect(last.endTime == TimeInterval(3 * 60 * 60))
        #expect(chunksAreContinuous(plan.chunks, expectedEnd: 3 * 60 * 60))
    }

    @Test func shortAudioStaysSingleTranscription() {
        let plan = LongAudioTranscriptionPlanner.plan(duration: 29 * 60)

        #expect(plan.mode == .single)
        #expect(plan.chunks.isEmpty)
    }

    @Test func audioAboveThirtyMinutesUsesChunkedTranscription() {
        let plan = LongAudioTranscriptionPlanner.plan(duration: 30 * 60 + 1)

        #expect(plan.mode == .chunked)
        #expect(plan.chunks.count == 3)
        #expect(chunksAreContinuous(plan.chunks, expectedEnd: 30 * 60 + 1))
    }

    @Test func fortyFiveMinuteAudioGeneratesThreeChunks() {
        let plan = LongAudioTranscriptionPlanner.plan(duration: 45 * 60)

        #expect(plan.mode == .chunked)
        #expect(plan.chunks.count == 3)
        #expect(plan.chunks.map(\.index) == [0, 1, 2])
        #expect(plan.chunks.map(\.startTime) == [0, 900, 1_800])
        #expect(plan.chunks.map(\.endTime) == [900, 1_800, 2_700])
    }

    @Test func chunkIndexesAndBoundariesAreStable() throws {
        let plan = LongAudioTranscriptionPlanner.plan(duration: 31 * 60)

        let first = try #require(plan.chunks.first)
        let last = try #require(plan.chunks.last)
        #expect(first.index == 0)
        #expect(first.startTime == 0)
        #expect(first.endTime == 15 * 60)
        #expect(last.index == 2)
        #expect(last.startTime == 30 * 60)
        #expect(last.endTime == 31 * 60)
    }

    @Test func chunkFailureRecordKeepsIndexAndError() {
        let descriptor = AudioChunkDescriptor(index: 3, startTime: 2_700, endTime: 3_600)
        let record = RecordingTranscriptionChunkRecord(
            descriptor: descriptor,
            status: .failed,
            error: "chunk 3 timed out"
        )

        #expect(record.index == 3)
        #expect(record.status == .failed)
        #expect(record.error == "chunk 3 timed out")
    }

    @Test func chunkTranscriptsMergeIntoFinalTranscript() {
        let first = AudioChunkDescriptor(index: 0, startTime: 0, endTime: 900)
        let second = AudioChunkDescriptor(index: 1, startTime: 900, endTime: 1_800)
        let third = AudioChunkDescriptor(index: 2, startTime: 1_800, endTime: 2_700)
        let merged = TranscriptionChunkMerger.merge(
            recordingID: "lecture-01",
            taskID: "task-01",
            chunks: [
                (second, makeTranscriptionResult(taskID: "task-02", text: "第二段", segmentStart: 1, segmentEnd: 3)),
                (third, makeTranscriptionResult(taskID: "task-03", text: "第三段", segmentStart: 3, segmentEnd: 4)),
                (first, makeTranscriptionResult(taskID: "task-01", text: "第一段", segmentStart: 2, segmentEnd: 5))
            ]
        )

        #expect(merged.text == "第一段\n\n第二段\n\n第三段")
        #expect(merged.segments.map(\.startTime) == [2, 901, 1_803])
        #expect(merged.status == "transcribed")
    }

    @Test func longTranscriptUsesChunkedNotePlan() {
        let transcript = String(repeating: "学习", count: 7_000)
        let plan = LongNoteGenerationPlanner.plan(transcript: transcript)

        #expect(plan.mode == .chunked)
        #expect(plan.chunks.count == 2)
    }

    @Test func shortTranscriptUsesSingleNotePlan() {
        let plan = LongNoteGenerationPlanner.plan(transcript: "短转写")

        #expect(plan.mode == .single)
        #expect(plan.chunks.isEmpty)
    }

    @Test func transcriptChunkerPreservesContent() {
        let transcript = "第一段\n第二段\n第三段"
        let chunks = TranscriptChunker.chunk(transcript, chunkCharacters: 4)

        #expect(chunks.map(\.text).joined() == transcript)
        #expect(chunks.map(\.index) == Array(chunks.indices))
    }

    @Test func transcriptChunkerPreservesBlockMarkersInOrder() {
        let transcript = (0..<100)
            .map { index in
                "[BLOCK-\(zeroPadded(index))] " + String(repeating: "x", count: 180)
            }
            .joined(separator: "\n")
        let chunks = TranscriptChunker.chunk(transcript, chunkCharacters: 1_000)
        let rejoined = chunks.map(\.text).joined()

        #expect(rejoined == transcript)
        for index in 0..<100 {
            #expect(rejoined.contains("[BLOCK-\(zeroPadded(index))]"))
        }
    }

    @Test func sectionSummariesComposeFinalNote() {
        let note = NoteSectionSynthesizer.composeFinalNote(
            title: "线性代数",
            sections: [
                NoteSectionSummary(index: 1, sourceStart: 10, sourceEnd: 20, markdown: "## 摘要\n\n第二节摘要", relativePath: nil),
                NoteSectionSummary(index: 0, sourceStart: 0, sourceEnd: 10, markdown: "## 摘要\n\n第一节摘要", relativePath: nil)
            ],
            providerName: "Mock"
        )

        #expect(note.contains("Mode: chunked"))
        #expect(note.contains("## 摘要"))
        #expect(NoteSummaryPreview.shortSummary(from: note)?.contains("第一节摘要") == true)
        #expect(note.range(of: "第一节摘要")!.lowerBound < note.range(of: "第二节摘要")!.lowerBound)
    }

    @Test func chunkedNoteGenerationUsesProviderAbstractionAndWritesSections() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let provider = CountingNoteGenerationProvider()
        let request = makeNoteGenerationRequest(transcriptMarkdown: String(repeating: "A", count: 25))
        let plan = LongNoteGenerationPlanner.plan(
            transcript: request.transcriptMarkdown ?? "",
            maxTranscriptCharacters: 10,
            chunkCharacters: 10
        )

        let output = try await ChunkedNoteGenerationRunner(
            provider: provider,
            noteStore: NoteStore(rootURL: scratchURL)
        ).generate(request: request, plan: plan)

        #expect(provider.requestCount == plan.chunks.count)
        #expect(output.sectionRecords.allSatisfy { $0.status == .generated })
        #expect(output.sectionRecords.allSatisfy { $0.sectionNoteRelativePath?.contains("/sections/section_") == true })
        #expect(output.sectionRecords.map(\.sectionNoteRelativePath) == [
            "notes/1970-01-01/lecture-01/sections/section_000.md",
            "notes/1970-01-01/lecture-01/sections/section_001.md",
            "notes/1970-01-01/lecture-01/sections/section_002.md"
        ])
        #expect(output.result.markdown.contains("Sections: 3"))
    }

    @Test func chunkedNoteGenerationRecordsFailedSectionIndex() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let request = makeNoteGenerationRequest(transcriptMarkdown: String(repeating: "B", count: 25))
        let plan = LongNoteGenerationPlanner.plan(
            transcript: request.transcriptMarkdown ?? "",
            maxTranscriptCharacters: 10,
            chunkCharacters: 10
        )

        do {
            _ = try await ChunkedNoteGenerationRunner(
                provider: FailingSectionNoteGenerationProvider(failOnRequest: 2),
                noteStore: NoteStore(rootURL: scratchURL)
            ).generate(request: request, plan: plan)
            Issue.record("Expected section note generation to fail")
        } catch let error as ChunkedNoteGenerationFailure {
            #expect(error.sectionRecords[0].status == .generated)
            #expect(error.sectionRecords[1].status == .failed)
            #expect(error.sectionRecords[1].error?.contains("section 1 failed") == true)
        }
    }

    @Test func mockProviderWorksInChunkedNoteMode() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let request = makeNoteGenerationRequest(transcriptMarkdown: String(repeating: "今天讨论矩阵乘法。", count: 20))
        let plan = LongNoteGenerationPlanner.plan(
            transcript: request.transcriptMarkdown ?? "",
            maxTranscriptCharacters: 20,
            chunkCharacters: 20
        )

        let output = try await ChunkedNoteGenerationRunner(
            provider: MockNoteGenerationProvider(),
            noteStore: NoteStore(rootURL: scratchURL)
        ).generate(request: request, plan: plan)

        #expect(output.sectionRecords.count == plan.chunks.count)
        #expect(output.result.status == "generated")
    }

    @Test func oldReceiveJSONMissingChunkFieldsDecodes() throws {
        let record = makeReceiveRecord()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: try encoder.encode(record)) as? [String: Any])
        object.removeValue(forKey: "transcriptionMode")
        object.removeValue(forKey: "transcriptionChunks")
        object.removeValue(forKey: "noteGenerationMode")
        object.removeValue(forKey: "noteSections")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingReceiveRecord.self, from: data)

        #expect(decoded.transcriptionMode == nil)
        #expect(decoded.transcriptionChunks == nil)
        #expect(decoded.noteGenerationMode == nil)
        #expect(decoded.noteSections == nil)
    }

    @Test func chunkFieldsEncodeAndDecode() throws {
        var record = makeReceiveRecord()
        record.transcriptionMode = .chunked
        record.transcriptionChunks = [
            RecordingTranscriptionChunkRecord(index: 0, startTime: 0, endTime: 900, status: .generated)
        ]
        record.noteGenerationMode = .chunked
        record.noteSections = [
            RecordingNoteSectionRecord(index: 0, sourceStart: 0, sourceEnd: 100, status: .generated)
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingReceiveRecord.self, from: try encoder.encode(record))

        #expect(decoded.transcriptionMode == .chunked)
        #expect(decoded.transcriptionChunks?.first?.status == .generated)
        #expect(decoded.noteGenerationMode == .chunked)
        #expect(decoded.noteSections?.first?.sourceEnd == 100)
    }

    @Test func shortTaskReceiveJSONDoesNotNeedChunkFields() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "short-receive", store: store)

        try store.updateTranscriptionStatus(
            recordingID: "short-receive",
            status: "transcribed",
            transcriptRelativePath: "transcripts/1970-01-01/short-receive/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/short-receive/transcript.md",
            providerID: "mock",
            modelName: "mock",
            startedAt: Date(timeIntervalSince1970: 10),
            completedAt: Date(timeIntervalSince1970: 11),
            errorMessage: nil
        )
        try store.updateNoteGenerationStatus(
            recordingID: "short-receive",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/short-receive/note.md",
            generatedAt: Date(timeIntervalSince1970: 12),
            providerID: "mock",
            modelName: "mock",
            endpointDescription: nil,
            errorMessage: nil
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "short-receive")

        #expect(record.transcriptionMode == nil)
        #expect(record.transcriptionChunks == nil)
        #expect(record.noteGenerationMode == nil)
        #expect(record.noteSections == nil)
    }

    @Test func longTaskReceiveJSONRecordsChunkMetadata() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "long-receive", store: store)
        let chunks = [
            RecordingTranscriptionChunkRecord(index: 0, startTime: 0, endTime: 900, status: .generated),
            RecordingTranscriptionChunkRecord(index: 1, startTime: 900, endTime: 1_800, status: .failed, error: "timeout")
        ]
        let sections = [
            RecordingNoteSectionRecord(index: 0, sourceStart: 0, sourceEnd: 10_000, status: .generated),
            RecordingNoteSectionRecord(index: 1, sourceStart: 10_000, sourceEnd: 20_000, status: .pending)
        ]

        try store.updateTranscriptionStatus(
            recordingID: "long-receive",
            status: "failed",
            transcriptRelativePath: "transcripts/1970-01-01/long-receive/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/long-receive/transcript.md",
            providerID: "whisperCpp",
            modelName: "large-v3",
            startedAt: Date(timeIntervalSince1970: 10),
            completedAt: Date(timeIntervalSince1970: 11),
            errorMessage: "chunk 1 failed",
            mode: .chunked,
            chunks: chunks
        )
        try store.updateNoteGenerationStatus(
            recordingID: "long-receive",
            status: "generating",
            noteRelativePath: nil,
            generatedAt: nil,
            providerID: "mock",
            modelName: "mock",
            endpointDescription: nil,
            errorMessage: nil,
            mode: .chunked,
            sections: sections
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "long-receive")

        #expect(record.transcriptionMode == .chunked)
        #expect(record.transcriptionChunks == chunks)
        #expect(record.noteGenerationMode == .chunked)
        #expect(record.noteSections == sections)
    }

    @Test func failedTranscriptionStatusDoesNotClearExistingTranscriptPaths() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "transcript-failure", store: store)
        try store.updateTranscriptionStatus(
            recordingID: "transcript-failure",
            status: "transcribed",
            transcriptRelativePath: "transcripts/1970-01-01/transcript-failure/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/transcript-failure/transcript.md",
            providerID: "mock",
            modelName: "mock",
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            errorMessage: nil
        )

        try store.updateTranscriptionStatus(
            recordingID: "transcript-failure",
            status: "failed",
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            providerID: "mock",
            modelName: "mock",
            startedAt: Date(timeIntervalSince1970: 3),
            completedAt: Date(timeIntervalSince1970: 4),
            errorMessage: "chunk 2 failed",
            mode: .chunked,
            chunks: [RecordingTranscriptionChunkRecord(index: 2, startTime: 1_800, endTime: 2_700, status: .failed)]
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "transcript-failure")

        #expect(record.transcriptRelativePath == "transcripts/1970-01-01/transcript-failure/transcript.json")
        #expect(record.transcriptMarkdownRelativePath == "transcripts/1970-01-01/transcript-failure/transcript.md")
        #expect(record.transcriptionChunks?.first?.status == .failed)
    }

    @Test func failedNoteStatusDoesNotClearExistingNotePathWithSections() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "long-note-failure", store: store)
        try store.updateNoteGenerationStatus(
            recordingID: "long-note-failure",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/long-note-failure/note.md",
            generatedAt: Date(timeIntervalSince1970: 2_000),
            providerID: "mock",
            modelName: "mock",
            endpointDescription: nil,
            errorMessage: nil,
            mode: .single,
            sections: nil
        )

        try store.updateNoteGenerationStatus(
            recordingID: "long-note-failure",
            status: "failed",
            noteRelativePath: nil,
            generatedAt: nil,
            providerID: "mock",
            modelName: "mock",
            endpointDescription: nil,
            errorMessage: "section 1 failed",
            mode: .chunked,
            sections: [RecordingNoteSectionRecord(index: 1, sourceStart: 100, sourceEnd: 200, status: .failed)]
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "long-note-failure")

        #expect(record.noteRelativePath == "notes/1970-01-01/long-note-failure/note.md")
        #expect(record.noteGenerationMode == .chunked)
        #expect(record.noteSections?.first?.status == .failed)
    }

    @Test func whisperModelKindRecognizesSmallMediumLarge() {
        #expect(WhisperModelKind.infer(fromModelFileName: "ggml-small.bin") == .small)
        #expect(WhisperModelKind.infer(fromModelFileName: "ggml-medium-q5_0.bin") == .medium)
        #expect(WhisperModelKind.infer(fromModelFileName: "ggml-large-v3.bin") == .largeV3)
        #expect(WhisperModelKind.infer(fromModelFileName: "ggml-large-v3-turbo.bin") == .largeV3Turbo)
    }

    @Test func whisperConfigurationDoesNotHardcodeModelPath() {
        let emptyConfiguration = WhisperCppTranscriptionConfiguration.default
        let largeConfiguration = WhisperCppTranscriptionConfiguration.default.withModelPath("ggml-large-v3.bin")

        #expect(emptyConfiguration.normalizedModelPath.isEmpty)
        #expect(emptyConfiguration.currentModelDisplayName == "未选择模型")
        #expect(largeConfiguration.modelKind == .largeV3)
        #expect(largeConfiguration.preferredLargeModel)
    }

    @Test func streamedFileHashMatchesDataHash() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let data = Data((0..<65_536).map { UInt8($0 % 251) })
        let fileURL = scratchURL.appendingPathComponent("large-upload.bin", isDirectory: false)
        try data.write(to: fileURL)

        let streamedHash = try MacSecurityUtilities.sha256Hex(fileURL: fileURL, chunkByteCount: 1_024)

        #expect(streamedHash == MacSecurityUtilities.sha256Hex(data))
    }

    @Test @MainActor func verifierCanValidatePrecomputedStreamingHash() throws {
        let secret = Data("secret".utf8)
        let body = Data("large body".utf8)
        let timestamp = Date(timeIntervalSince1970: 100)
        let timestampString = String(format: "%.0f", timestamp.timeIntervalSince1970)
        let nonce = "nonce"
        let bodyHash = MacSecurityUtilities.sha256Hex(body)
        let secretBase64URL = secret.base64URLEncodedString()
        let signaturePayload = [
            "POST",
            "/upload-recording-audio",
            timestampString,
            nonce,
            bodyHash
        ].joined(separator: "\n")
        let signature = try #require(MacSecurityUtilities.hmacSHA256Base64URL(
            message: signaturePayload,
            secretBase64URL: secretBase64URL
        ))
        let headers = [
            "Content-Type": "audio/m4a",
            "X-Rokurics-Upload-Type": "recording-audio",
            "X-Rokurics-Device-ID": "device",
            "X-Rokurics-Timestamp": timestampString,
            "X-Rokurics-Nonce": nonce,
            "X-Rokurics-Body-SHA256": bodyHash,
            "X-Rokurics-Signature": signature
        ]
        let verifier = RequestVerifier(
            pairedDeviceProvider: { _ in
                PairedDevice(
                    id: "device",
                    deviceName: "iPhone",
                    sharedSecretBase64URL: secretBase64URL,
                    pairedAt: timestamp,
                    lastSeenAt: nil
                )
            },
            markDeviceSeen: { _, _ in }
        )

        let result = verifier.verify(
            method: "POST",
            path: "/upload-recording-audio",
            headers: headers,
            bodySHA256: bodyHash,
            bodyByteCount: body.count,
            now: timestamp
        )

        if case .accepted = result {
            #expect(true)
        } else {
            Issue.record("Expected streaming hash verification to be accepted")
        }
    }

    @Test func whisperTimeoutScalesWithChunkAndModelKind() {
        let largeTimeout = WhisperTranscriptionTimeoutPolicy.timeout(
            audioDuration: 15 * 60,
            modelKind: .largeV3
        )
        let smallTimeout = WhisperTranscriptionTimeoutPolicy.timeout(
            audioDuration: 15 * 60,
            modelKind: .small
        )

        #expect(largeTimeout == 2 * 60 * 60)
        #expect(smallTimeout == 60 * 60)
    }

    @Test func diagnosticReportIncludesMarkerAndNoSensitivePayloads() {
        let report = LongProcessingDiagnosticReport.markdown(input: LongProcessingDiagnosticReportInput(
            recordingDuration: 3 * 60 * 60,
            audioFileSize: 500_000_000,
            transcriptionMode: .chunked,
            chunkCount: 12,
            failedChunkIndexes: [],
            transcriptCharacterCount: 52_000,
            noteGenerationMode: .chunked,
            sectionCount: 6,
            failedSectionIndexes: [4],
            modelKind: .largeV3
        ))

        #expect(report.components(separatedBy: "\n").contains("1636"))
        #expect(report.contains("Duration: 180 minutes"))
        #expect(report.contains("Estimated chunk count: 12"))
        #expect(report.contains("Failed note section indexes: 4"))
        #expect(!report.contains("sk-test-secret"))
        #expect(!report.contains("sharedSecret"))
        #expect(!report.contains("[BLOCK-042]"))
        #expect(!report.contains("完整 transcript"))
    }

    @Test func uploadMainPathStaticAuditShowsNoWholeAudioDataRead() throws {
        let recordingUploadClient = try sourceText("Rokurics/RecordingUploadClient.swift")
        let secureUploadClient = try sourceText("Rokurics/SecureMacUploadClient.swift")
        let secureUploadUtilities = try sourceText("Rokurics/SecureUploadUtilities.swift")
        let secureServer = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")
        let requestVerifier = try sourceText("RokuricsMac/RequestVerifier.swift")

        #expect(!recordingUploadClient.contains("Data(contentsOf: audioURL)"))
        #expect(secureUploadClient.contains("upload(for: request, fromFile: fileURL)"))
        #expect(secureUploadClient.contains("sha256Hex(fileURL: fileURL)"))
        #expect(secureUploadUtilities.contains("FileHandle(forReadingFrom: fileURL)"))
        #expect(secureServer.contains("StreamingBodyWriter"))
        #expect(secureServer.contains("temporaryAudioUploadURL"))
        #expect(requestVerifier.contains("bodySHA256 actualBodyHash"))
    }

    private func chunksAreContinuous(_ chunks: [AudioChunkDescriptor], expectedEnd: TimeInterval) -> Bool {
        guard let first = chunks.first, first.startTime == 0 else {
            return false
        }

        for pair in zip(chunks, chunks.dropFirst()) {
            guard pair.0.index + 1 == pair.1.index,
                  pair.0.endTime == pair.1.startTime,
                  pair.0.endTime <= pair.1.endTime else {
                return false
            }
        }

        return chunks.last?.endTime == expectedEnd
    }

    private func makeTranscriptionResult(
        taskID: String,
        text: String,
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval
    ) -> TranscriptionResult {
        TranscriptionResult(
            taskID: taskID,
            recordingID: "lecture-01",
            providerID: "mock",
            providerName: "Mock",
            modelName: "mock",
            language: "zh",
            text: text,
            segments: [
                TranscriptionSegment(
                    id: "\(taskID)-segment",
                    startTime: segmentStart,
                    endTime: segmentEnd,
                    text: text,
                    confidence: 1
                )
            ],
            startedAt: Date(timeIntervalSince1970: segmentStart),
            completedAt: Date(timeIntervalSince1970: segmentEnd),
            status: "transcribed"
        )
    }

    private func makeNoteGenerationRequest(transcriptMarkdown: String) -> NoteGenerationRequest {
        NoteGenerationRequest(
            taskID: "note-task",
            recordingID: "lecture-01",
            sanitizedRecordingID: "lecture-01",
            title: "线性代数",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 3 * 60 * 60,
            transcriptRelativePath: "transcripts/1970-01-01/lecture-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/lecture-01/transcript.md",
            transcriptionProviderID: "whisper.cpp",
            transcriptionModelName: "large-v3",
            transcriptResult: nil,
            transcriptMarkdown: transcriptMarkdown,
            requestedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    private func makeReceiveRecord() -> RecordingReceiveRecord {
        RecordingReceiveRecord(
            recordingID: "lecture-01",
            sanitizedRecordingID: "lecture-01",
            receivedAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            sourceDeviceID: "device",
            sourceDeviceName: "iPhone",
            originalTitle: "Lecture",
            normalizedTitle: "Lecture",
            audioFileName: "audio.m4a",
            originalAudioFileName: "lecture.m4a",
            metadataFileName: "metadata.json",
            status: "received",
            transcriptionStatus: "notStarted",
            noteStatus: "notGenerated",
            processingStatus: "notStarted",
            suggestedCategory: nil,
            course: nil,
            category: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 3 * 60 * 60,
            fileSize: 1024,
            suggestedFolder: nil,
            userConfirmedFolder: nil,
            checksum: nil,
            audioRelativePath: "audio/inbox/1970-01-01/lecture-01/audio.m4a",
            metadataRelativePath: "audio/inbox/1970-01-01/lecture-01/metadata.json"
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacLongProcessingTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        return scratchURL
    }

    private func makeMacStore() throws -> (MacRecordingFileStore, URL) {
        let rootURL = try makeScratchDirectory()
            .appendingPathComponent("Rokurics", isDirectory: true)
        return (MacRecordingFileStore(rootURL: rootURL), rootURL)
    }

    @discardableResult
    private func saveMacInboxRecording(id: String, store: MacRecordingFileStore) throws -> URL {
        let device = PairedDevice(
            id: "device",
            deviceName: "iPhone",
            sharedSecretBase64URL: "secret",
            pairedAt: Date(timeIntervalSince1970: 1),
            lastSeenAt: nil
        )
        let metadata = IncomingRecordingMetadata(
            id: id,
            title: id,
            originalFileName: "\(id).m4a",
            relativeAudioPath: "Recordings/\(id).m4a",
            createdAt: Date(timeIntervalSince1970: 1_800),
            endedAt: Date(timeIntervalSince1970: 1_806),
            duration: 6,
            format: "m4a",
            codec: "AAC",
            sampleRate: 16_000,
            channels: 1,
            bitrate: 64_000,
            fileSize: 5,
            uploadStatus: "uploaded",
            transcriptionStatus: "notStarted",
            noteStatus: "notGenerated",
            tags: [],
            sourceDeviceName: "iPhone",
            sourceDeviceID: "device",
            uploadedAt: Date(timeIntervalSince1970: 1_807)
        )
        let result = try store.saveMetadata(metadata, sourceDevice: device)
        _ = try store.saveAudio(body: Data("audio".utf8), recordingID: id, requestedFileName: "\(id).m4a", sourceDevice: device)
        return result.directoryURL
    }

    private func readReceiveRecord(rootURL: URL, recordingID: String) throws -> RecordingReceiveRecord {
        let receiveURL = rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("1970-01-01", isDirectory: true)
            .appendingPathComponent(recordingID, isDirectory: true)
            .appendingPathComponent("receive.json", isDirectory: false)
        let data = try Data(contentsOf: receiveURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingReceiveRecord.self, from: data)
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRootURL.appendingPathComponent(relativePath, isDirectory: false)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func zeroPadded(_ value: Int, width: Int = 3) -> String {
        let rawValue = String(value)
        guard rawValue.count < width else {
            return rawValue
        }
        return String(repeating: "0", count: width - rawValue.count) + rawValue
    }
}

private final class CountingNoteGenerationProvider: NoteGenerationProvider {
    let id = "counting"
    let displayName = "Counting"
    private(set) var requestCount = 0

    func validateConfiguration() async throws {}

    func generateNote(request: NoteGenerationRequest) async throws -> NoteGenerationResult {
        requestCount += 1
        return NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: id,
            providerName: displayName,
            modelName: "counting-model",
            markdown: "Summary \(requestCount): \(request.transcriptMarkdown ?? "")",
            startedAt: Date(timeIntervalSince1970: TimeInterval(requestCount)),
            completedAt: Date(timeIntervalSince1970: TimeInterval(requestCount + 1)),
            status: "generated"
        )
    }
}

private final class FailingSectionNoteGenerationProvider: NoteGenerationProvider {
    let id = "failing"
    let displayName = "Failing"
    private let failOnRequest: Int
    private var requestCount = 0

    init(failOnRequest: Int) {
        self.failOnRequest = failOnRequest
    }

    func validateConfiguration() async throws {}

    func generateNote(request: NoteGenerationRequest) async throws -> NoteGenerationResult {
        requestCount += 1
        if requestCount == failOnRequest {
            throw NoteGenerationError.noteStoreWriteFailed("simulated_section_failure")
        }

        return NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: id,
            providerName: displayName,
            modelName: "failing-model",
            markdown: "Section \(requestCount)",
            startedAt: Date(timeIntervalSince1970: TimeInterval(requestCount)),
            completedAt: Date(timeIntervalSince1970: TimeInterval(requestCount + 1)),
            status: "generated"
        )
    }
}

private extension WhisperCppTranscriptionConfiguration {
    func withModelPath(_ path: String) -> WhisperCppTranscriptionConfiguration {
        var copy = self
        copy.modelPath = path
        return copy
    }
}
