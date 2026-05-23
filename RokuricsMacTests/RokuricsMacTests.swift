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
    @Test func iPhoneConnectionCardLayoutKeepsStableWidthAcrossSidebarChanges() {
        #expect(MacIPhoneConnectionCardLayout.cardMaxWidth(isSidebarCollapsed: false) == MacIPhoneConnectionCardLayout.stableMaxWidth)
        #expect(MacIPhoneConnectionCardLayout.cardMaxWidth(isSidebarCollapsed: true) == MacIPhoneConnectionCardLayout.stableMaxWidth)
        #expect(MacIPhoneConnectionCardLayout.cardMaxWidth(isSidebarCollapsed: false) == MacIPhoneConnectionCardLayout.cardMaxWidth(isSidebarCollapsed: true))
        #expect(MacIPhoneConnectionCardLayout.isCentered(isSidebarCollapsed: false))
        #expect(MacIPhoneConnectionCardLayout.isCentered(isSidebarCollapsed: true))
        #expect(MacIPhoneConnectionCardLayout.disablesWidthAnimation)
    }

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

    @Test func audioInboxActionLabelsMatchTranscriptionState() {
        #expect(MacAudioInboxRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "notStarted", transcriptionError: nil),
            isTranscribing: false
        ).label == "转写")

        #expect(MacAudioInboxRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "failed", transcriptionError: "boom"),
            isTranscribing: false
        ).label == "转写")

        #expect(MacAudioInboxRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "queued", transcriptionError: nil),
            isTranscribing: false
        ).label == "转写中")

        #expect(MacAudioInboxRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "transcribing", transcriptionError: nil),
            isTranscribing: false
        ).label == "转写中")

        #expect(MacAudioInboxRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil),
            isTranscribing: false
        ).label == "查看转写")
    }

    @Test func transcribedInboxActionRequestsTranscriptDetail() {
        let action = MacAudioInboxRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil),
            isTranscribing: false
        )

        #expect(action.intent == .viewTranscript)
        #expect(action.isEnabled)
    }

    @Test func failedInboxActionUsesSingleRetryCapsuleIntent() {
        let action = MacAudioInboxRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "failed", transcriptionError: "launch failed"),
            isTranscribing: false
        )

        #expect(action.label == "转写")
        #expect(action.intent == .startTranscription)
    }

    @Test func noteStoreWritesNoteMarkdownToDatedRecordingDirectory() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let request = makeNoteGenerationRequest(recordingID: "note-store-01", sanitizedRecordingID: "note-store-01")
        let result = NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: "mockNoteGenerationProvider",
            providerName: "Mock Note Generation",
            modelName: "mock-note-local",
            markdown: "# 录音笔记\n\n## 摘要\n\nHello Rokurics\n\n## 重点\n\n- 第一条",
            startedAt: Date(timeIntervalSince1970: 2_000),
            completedAt: Date(timeIntervalSince1970: 2_001),
            status: "generated"
        )

        let store = NoteStore(rootURL: scratchURL)
        let saveResult = try store.save(result: result, request: request)
        let noteURL = scratchURL.appendingPathComponent(saveResult.noteRelativePath, isDirectory: false)

        #expect(saveResult.noteRelativePath == "notes/1970-01-01/note-store-01/note.md")
        #expect(saveResult.summaryPreviewRelativePath == "notes/1970-01-01/note-store-01/summary.json")
        #expect(try String(contentsOf: noteURL, encoding: .utf8).contains("Hello Rokurics"))

        let preview = try #require(store.loadSummaryPreview(noteRelativePath: saveResult.noteRelativePath))
        #expect(preview.recordingID == "note-store-01")
        #expect(preview.shortSummary == "Hello Rokurics")
        #expect(preview.keyPoints == ["第一条"])
        #expect(preview.providerDisplayName == "Mock Note Generation")
    }

    @Test func mockNoteGenerationProviderGeneratesNonEmptyNote() async throws {
        let provider = MockNoteGenerationProvider()
        let request = makeNoteGenerationRequest(
            recordingID: "mock-note-01",
            sanitizedRecordingID: "mock-note-01",
            transcriptMarkdown: "# 转写\n\n今天讨论了本地 AI 总结。"
        )

        let result = try await provider.generateNote(request: request)

        #expect(result.providerID == "mockNoteGenerationProvider")
        #expect(result.status == "generated")
        #expect(result.markdown.contains("# 录音笔记"))
        #expect(result.markdown.contains("MockNoteGenerationProvider"))
        #expect(result.markdown.contains("今天讨论了本地 AI 总结。"))
        #expect(NoteSummaryPreview.make(result: result, noteRelativePath: "notes/mock/note.md").shortSummary.contains("占位笔记"))
    }

    @Test func receiveRecordMissingNoteFieldsDefaultsToNotGenerated() throws {
        let record = RecordingReceiveRecord(
            recordingID: "legacy-note",
            sanitizedRecordingID: "legacy-note",
            receivedAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            sourceDeviceID: "device",
            sourceDeviceName: "iPhone",
            originalTitle: "旧录音",
            normalizedTitle: "旧录音",
            audioFileName: "audio.m4a",
            originalAudioFileName: "legacy.m4a",
            metadataFileName: "metadata.json",
            status: "received",
            transcriptionStatus: "transcribed",
            noteStatus: "generated",
            noteRelativePath: "notes/1970-01-01/legacy-note/note.md",
            noteGeneratedAt: Date(timeIntervalSince1970: 3),
            noteProviderID: "mockNoteGenerationProvider",
            noteError: nil,
            processingStatus: "transcribed",
            suggestedCategory: nil,
            course: nil,
            category: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 6,
            fileSize: 5,
            suggestedFolder: nil,
            userConfirmedFolder: nil,
            checksum: nil,
            audioRelativePath: "audio/inbox/1970-01-01/legacy-note/audio.m4a",
            metadataRelativePath: "audio/inbox/1970-01-01/legacy-note/metadata.json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: try encoder.encode(record)) as? [String: Any])
        object.removeValue(forKey: "noteStatus")
        object.removeValue(forKey: "noteRelativePath")
        object.removeValue(forKey: "noteGeneratedAt")
        object.removeValue(forKey: "noteProviderID")
        object.removeValue(forKey: "noteModelName")
        object.removeValue(forKey: "noteEndpointDescription")
        object.removeValue(forKey: "noteError")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingReceiveRecord.self, from: data)

        #expect(decoded.noteStatus == "notGenerated")
        #expect(decoded.noteRelativePath == nil)
        #expect(decoded.noteGeneratedAt == nil)
        #expect(decoded.noteProviderID == nil)
        #expect(decoded.noteModelName == nil)
        #expect(decoded.noteEndpointDescription == nil)
        #expect(decoded.noteError == nil)
    }

    @Test func noteGenerationStatusWritePreservesTranscriptFields() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-note-01", title: "笔记", store: store)
        try store.updateTranscriptionStatus(
            recordingID: "mac-note-01",
            status: "transcribed",
            transcriptRelativePath: "transcripts/1970-01-01/mac-note-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/mac-note-01/transcript.md",
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            errorMessage: nil
        )

        try store.updateNoteGenerationStatus(
            recordingID: "mac-note-01",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/mac-note-01/note.md",
            generatedAt: Date(timeIntervalSince1970: 2_000),
            providerID: "openAICompatible",
            modelName: "google/gemma-4-e4b",
            endpointDescription: "127.0.0.1",
            errorMessage: nil
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-note-01")

        #expect(record.noteStatus == "generated")
        #expect(record.noteRelativePath == "notes/1970-01-01/mac-note-01/note.md")
        #expect(record.noteProviderID == "openAICompatible")
        #expect(record.noteModelName == "google/gemma-4-e4b")
        #expect(record.noteEndpointDescription == "127.0.0.1")
        #expect(record.transcriptRelativePath == "transcripts/1970-01-01/mac-note-01/transcript.json")
        #expect(record.transcriptMarkdownRelativePath == "transcripts/1970-01-01/mac-note-01/transcript.md")
    }

    @Test func failedNoteGenerationPreservesExistingNotePath() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-note-failed", title: "失败保留", store: store)
        let generatedAt = Date(timeIntervalSince1970: 2_000)
        try store.updateNoteGenerationStatus(
            recordingID: "mac-note-failed",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/mac-note-failed/note.md",
            generatedAt: generatedAt,
            providerID: "openAICompatible",
            modelName: "google/gemma-4-e4b",
            endpointDescription: "127.0.0.1",
            errorMessage: nil
        )

        try store.updateNoteGenerationStatus(
            recordingID: "mac-note-failed",
            status: "failed",
            noteRelativePath: nil,
            generatedAt: nil,
            providerID: "openAICompatible",
            modelName: "google/gemma-4-e4b",
            endpointDescription: "127.0.0.1",
            errorMessage: "请求超时"
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-note-failed")

        #expect(record.noteStatus == "failed")
        #expect(record.noteRelativePath == "notes/1970-01-01/mac-note-failed/note.md")
        #expect(record.noteGeneratedAt == generatedAt)
        #expect(record.noteError == "请求超时")
    }

    @Test func anthropicNoteGenerationStatusWritesProviderAndModel() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-note-claude", title: "Claude 笔记", store: store)

        try store.updateNoteGenerationStatus(
            recordingID: "mac-note-claude",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/mac-note-claude/note.md",
            generatedAt: Date(timeIntervalSince1970: 2_400),
            providerID: "anthropicMessages",
            modelName: "claude-sonnet-4-6",
            endpointDescription: "api.anthropic.com",
            errorMessage: nil
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-note-claude")

        #expect(record.noteStatus == "generated")
        #expect(record.noteProviderID == "anthropicMessages")
        #expect(record.noteModelName == "claude-sonnet-4-6")
        #expect(record.noteRelativePath == "notes/1970-01-01/mac-note-claude/note.md")
        #expect(record.noteEndpointDescription == "api.anthropic.com")
        #expect(record.noteGeneratedAt != nil)
    }

    @Test @MainActor func noteGenerationSettingsPersistProviderAndOpenAIConfiguration() throws {
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults)

        store.update(
            providerKind: .openAICompatible,
            providerPreset: .lmStudioLocal,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(
                baseURLString: " http://127.0.0.1:1234/v1/ ",
                modelName: " google/gemma-4-e4b ",
                apiKey: " local-secret "
            ),
            cachedModelCandidates: [" google/gemma-4-e4b "]
        )

        let reloaded = NoteGenerationSettingsStore(userDefaults: defaults)

        #expect(reloaded.selectedProviderKind == .openAICompatible)
        #expect(reloaded.selectedProviderPreset == .lmStudioLocal)
        #expect(reloaded.openAIConfiguration.baseURLString == "http://127.0.0.1:1234/v1/")
        #expect(reloaded.openAIConfiguration.modelName == "google/gemma-4-e4b")
        #expect(reloaded.openAIConfiguration.apiKey == "local-secret")
        #expect(reloaded.cachedModelCandidates == ["google/gemma-4-e4b"])
    }

    @Test func aiProviderPresetDefaultsMatchSupportedProviders() {
        #expect(AIProviderPreset.lmStudioLocal.defaultBaseURLString == "http://127.0.0.1:1234/v1")
        #expect(AIProviderPreset.lmStudioLocal.defaultModelCandidates == ["google/gemma-4-e4b"])
        #expect(AIProviderPreset.deepSeek.defaultBaseURLString == "https://api.deepseek.com")
        #expect(AIProviderPreset.deepSeek.defaultModelCandidates == ["deepseek-v4-flash", "deepseek-v4-pro"])
        #expect(AIProviderPreset.openAI.defaultBaseURLString == "https://api.openai.com/v1")
        #expect(AIProviderPreset.openAI.defaultModelCandidates == ["gpt-5.5", "gpt-5.5-mini", "gpt-5.5-nano"])
        #expect(AIProviderPreset.gemini.defaultBaseURLString == "https://generativelanguage.googleapis.com/v1beta/openai")
        #expect(AIProviderPreset.gemini.defaultModelCandidates == ["gemini-3-flash-preview"])
    }

    @Test func aiProviderPresetAppliesDefaultsAndCustomPreservesManualValues() {
        let manual = OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: "https://example.local/v1",
            modelName: "manual-model",
            apiKey: "secret"
        )
        let deepSeek = AIProviderPreset.deepSeek.applyingDefaults(to: manual)
        let custom = AIProviderPreset.customOpenAICompatible.applyingDefaults(to: manual)

        #expect(deepSeek.baseURLString == "https://api.deepseek.com")
        #expect(deepSeek.modelName == "deepseek-v4-flash")
        #expect(deepSeek.apiKey == "secret")
        #expect(custom.baseURLString == "https://example.local/v1")
        #expect(custom.modelName == "manual-model")
        #expect(custom.apiKey == "secret")
    }

    @Test func aiProviderPresetCanInferFromLegacyBaseURL() {
        #expect(AIProviderPreset.inferred(from: "http://127.0.0.1:1234/v1") == .lmStudioLocal)
        #expect(AIProviderPreset.inferred(from: "https://api.deepseek.com") == .deepSeek)
        #expect(AIProviderPreset.inferred(from: "https://api.openai.com/v1") == .openAI)
        #expect(AIProviderPreset.inferred(from: "https://generativelanguage.googleapis.com/v1beta/openai") == .gemini)
        #expect(AIProviderPreset.inferred(from: "https://example.local/v1") == .customOpenAICompatible)
    }

    @Test @MainActor func legacySettingsWithoutProviderPresetInferPresetFromBaseURL() throws {
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let config = OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: "https://api.deepseek.com",
            modelName: "deepseek-chat"
        )
        let data = try JSONEncoder().encode(config)
        defaults.set(NoteGenerationProviderKind.openAICompatible.rawValue, forKey: "noteGeneration.providerKind")
        defaults.set(data, forKey: "noteGeneration.openAICompatible.configuration")

        let store = NoteGenerationSettingsStore(userDefaults: defaults)

        #expect(store.selectedProviderKind == .openAICompatible)
        #expect(store.selectedProviderPreset == .deepSeek)
        #expect(store.openAIConfiguration.modelName == "deepseek-chat")
        #expect(store.cachedModelCandidates.contains("deepseek-chat"))
    }

    @Test @MainActor func modelRefreshReadsModelIDsAndCanPersistCandidates() async throws {
        let response = Data("""
        {
          "object": "list",
          "data": [
            { "id": "model-a" },
            { "id": "model-b" }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, client: client)

        let result = await store.refreshModels(configuration: OpenAICompatibleNoteGenerationConfiguration(apiKey: "secret"))
        store.update(
            providerKind: .openAICompatible,
            providerPreset: .customOpenAICompatible,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(modelName: "model-b", apiKey: "secret"),
            cachedModelCandidates: result.modelIDs
        )
        let reloaded = NoteGenerationSettingsStore(userDefaults: defaults, client: client)

        #expect(result.isSuccess)
        #expect(result.modelIDs == ["model-a", "model-b"])
        #expect(reloaded.openAIConfiguration.modelName == "model-b")
        #expect(reloaded.cachedModelCandidates == ["model-a", "model-b"])
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test @MainActor func failedModelRefreshDoesNotClearCurrentModelName() async throws {
        let transport = OpenAICompatibleTransportStub(data: Data("{}".utf8), statusCode: 500)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, client: client)
        store.update(
            providerKind: .openAICompatible,
            providerPreset: .customOpenAICompatible,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(modelName: "manual-model"),
            cachedModelCandidates: ["manual-model"]
        )

        let result = await store.refreshModels(configuration: store.openAIConfiguration)

        #expect(!result.isSuccess)
        #expect(store.openAIConfiguration.modelName == "manual-model")
        #expect(store.cachedModelCandidates == ["manual-model"])
    }

    @Test @MainActor func modelCandidateSelectionPersistsAsModelName() throws {
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults)

        store.update(
            providerKind: .openAICompatible,
            providerPreset: .deepSeek,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(
                baseURLString: AIProviderPreset.deepSeek.defaultBaseURLString,
                modelName: "deepseek-v4-pro"
            ),
            cachedModelCandidates: AIProviderPreset.deepSeek.defaultModelCandidates
        )

        let reloaded = NoteGenerationSettingsStore(userDefaults: defaults)

        #expect(reloaded.openAIConfiguration.modelName == "deepseek-v4-pro")
        #expect(reloaded.cachedModelCandidates.contains("deepseek-v4-pro"))
    }

    @Test func anthropicEndpointURLHandlesTrailingSlashAndV1Base() throws {
        let noSlash = try AnthropicMessagesNoteGenerationClient.endpointURL(
            baseURLString: "https://api.anthropic.com",
            path: "v1/messages"
        )
        let slash = try AnthropicMessagesNoteGenerationClient.endpointURL(
            baseURLString: "https://api.anthropic.com/",
            path: "/v1/models"
        )
        let v1Base = try AnthropicMessagesNoteGenerationClient.endpointURL(
            baseURLString: "https://api.anthropic.com/v1/",
            path: "v1/messages"
        )

        #expect(noSlash.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(slash.absoluteString == "https://api.anthropic.com/v1/models")
        #expect(v1Base.absoluteString == "https://api.anthropic.com/v1/messages")
    }

    @Test func anthropicRequestUsesRequiredHeadersAndDoesNotUseBearer() throws {
        let client = AnthropicMessagesNoteGenerationClient()
        let request = try client.makeRequest(
            path: "v1/messages",
            method: "POST",
            configuration: AnthropicMessagesConfiguration(
                apiKey: " claude-secret ",
                anthropicVersion: " 2023-06-01 "
            ),
            timeout: 10,
            body: Data("{}".utf8)
        )

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "claude-secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test @MainActor func anthropicSettingsPersistProviderAndConfiguration() throws {
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults)

        store.update(
            providerKind: .anthropicMessages,
            providerPreset: .customOpenAICompatible,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(),
            cachedModelCandidates: [],
            anthropicConfiguration: AnthropicMessagesConfiguration(
                baseURLString: " https://api.anthropic.com/ ",
                modelName: " claude-haiku-4-5 ",
                apiKey: " claude-secret ",
                anthropicVersion: " 2023-06-01 "
            ),
            cachedAnthropicModelCandidates: [" claude-haiku-4-5 "]
        )

        let reloaded = NoteGenerationSettingsStore(userDefaults: defaults)

        #expect(reloaded.selectedProviderKind == .anthropicMessages)
        #expect(reloaded.currentProviderID == "anthropicMessages")
        #expect(reloaded.anthropicConfiguration.baseURLString == "https://api.anthropic.com/")
        #expect(reloaded.anthropicConfiguration.modelName == "claude-haiku-4-5")
        #expect(reloaded.anthropicConfiguration.apiKey == "claude-secret")
        #expect(reloaded.anthropicConfiguration.anthropicVersion == "2023-06-01")
        #expect(reloaded.cachedAnthropicModelCandidates == ["claude-haiku-4-5"])
    }

    @Test @MainActor func anthropicModelRefreshReadsModelIDsAndDoesNotClearOnFailure() async throws {
        let response = Data("""
        {
          "data": [
            { "id": "claude-sonnet-4-6" },
            { "id": "claude-haiku-4-5" }
          ]
        }
        """.utf8)
        let transport = AnthropicMessagesTransportStub(data: response, statusCode: 200)
        let client = AnthropicMessagesNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, anthropicClient: client)
        let configuration = AnthropicMessagesConfiguration(modelName: "claude-haiku-4-5", apiKey: "claude-secret")

        let result = await store.refreshAnthropicModels(configuration: configuration)
        store.update(
            providerKind: .anthropicMessages,
            providerPreset: .customOpenAICompatible,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(),
            cachedModelCandidates: [],
            anthropicConfiguration: configuration,
            cachedAnthropicModelCandidates: result.modelIDs
        )
        let failedTransport = AnthropicMessagesTransportStub(data: Data("{}".utf8), statusCode: 500)
        let failedStore = NoteGenerationSettingsStore(userDefaults: defaults, anthropicClient: AnthropicMessagesNoteGenerationClient(transport: failedTransport))
        let failedResult = await failedStore.refreshAnthropicModels(configuration: failedStore.anthropicConfiguration)

        #expect(result.isSuccess)
        #expect(result.modelIDs == ["claude-sonnet-4-6", "claude-haiku-4-5"])
        #expect(transport.lastRequest?.url?.absoluteString == "https://api.anthropic.com/v1/models")
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "x-api-key") == "claude-secret")
        #expect(failedResult.isSuccess == false)
        #expect(failedStore.anthropicConfiguration.modelName == "claude-haiku-4-5")
        #expect(failedStore.cachedAnthropicModelCandidates == ["claude-sonnet-4-6", "claude-haiku-4-5"])
    }

    @Test @MainActor func anthropicTestModelUsesMessagesAPIShape() async throws {
        let response = Data("""
        {
          "content": [
            { "type": "text", "text": "Rokurics Claude OK" }
          ],
          "stop_reason": "end_turn"
        }
        """.utf8)
        let transport = AnthropicMessagesTransportStub(data: response, statusCode: 200)
        let client = AnthropicMessagesNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, anthropicClient: client)

        let result = await store.testAnthropicModel(configuration: AnthropicMessagesConfiguration(apiKey: "claude-secret"))
        let body = try requestBodyJSON(from: try #require(transport.lastRequest))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let firstMessage = try #require(messages.first)

        #expect(result.isSuccess)
        #expect(body["model"] as? String == "claude-sonnet-4-6")
        #expect((body["max_tokens"] as? NSNumber)?.intValue == 256)
        #expect((body["temperature"] as? NSNumber)?.doubleValue == 0.1)
        #expect(body["system"] as? String != nil)
        #expect(!body.keys.contains("stream"))
        #expect(firstMessage["role"] as? String == "user")
        #expect((firstMessage["content"] as? String)?.contains("Rokurics Claude OK") == true)
    }

    @Test func anthropicMessageResponseParsesTextBlocksAndRejectsEmptyContent() throws {
        let data = Data("""
        {
          "content": [
            { "type": "text", "text": "第一段" },
            { "type": "tool_use", "id": "tool-1" },
            { "type": "text", "text": "第二段" }
          ],
          "stop_reason": "end_turn",
          "usage": { "input_tokens": 12, "output_tokens": 8 }
        }
        """.utf8)

        let result = try AnthropicMessagesNoteGenerationClient.parseMessage(data: data, statusCode: 200)

        #expect(result.content == "第一段\n第二段")
        #expect(result.stopReason == "end_turn")

        let emptyData = Data("""
        {
          "content": [
            { "type": "text", "text": "   " }
          ],
          "stop_reason": "end_turn"
        }
        """.utf8)
        do {
            _ = try AnthropicMessagesNoteGenerationClient.parseMessage(data: emptyData, statusCode: 200)
            Issue.record("Expected empty Claude content to fail")
        } catch let error as AnthropicMessagesClientError {
            if case .emptyContent(let diagnostics) = error {
                #expect(diagnostics.statusCode == 200)
                #expect(diagnostics.textLength == 0)
            } else {
                Issue.record("Expected empty content error")
            }
        }
    }

    @Test func anthropicMessageResponseAllowsMaxTokensWhenContentExists() throws {
        let data = Data("""
        {
          "content": [
            { "type": "text", "text": "# 录音笔记\\n\\n## 摘要\\nClaude 笔记" }
          ],
          "stop_reason": "max_tokens"
        }
        """.utf8)

        let result = try AnthropicMessagesNoteGenerationClient.parseMessage(data: data)

        #expect(result.content.contains("Claude 笔记"))
        #expect(result.isLengthLimited)
    }

    @Test func anthropicErrorsDoNotExposeResponseBodyOrAPIKey() async throws {
        let response = Data("""
        {
          "content": [
            { "type": "text", "text": "" }
          ],
          "stop_reason": "end_turn",
          "debug": "private response body"
        }
        """.utf8)
        let transport = AnthropicMessagesTransportStub(data: response, statusCode: 200)
        let client = AnthropicMessagesNoteGenerationClient(transport: transport)

        do {
            _ = try await client.message(
                configuration: AnthropicMessagesConfiguration(apiKey: "claude-secret"),
                system: "system",
                userContent: "ping",
                timeout: 30,
                maxTokens: 256
            )
            Issue.record("Expected empty Claude content to fail")
        } catch {
            #expect(error.localizedDescription.contains("status=200"))
            #expect(!error.localizedDescription.contains("private response body"))
            #expect(!error.localizedDescription.contains("claude-secret"))
            #expect(!error.localizedDescription.contains("\"content\""))
        }
    }

    @Test func anthropicProviderCreatesMetadataNoteAndDoesNotPersistUsageOrAPIKey() async throws {
        let response = Data("""
        {
          "content": [
            { "type": "text", "text": "# 录音笔记\\n\\n## 摘要\\nClaude 公开笔记" }
          ],
          "stop_reason": "max_tokens",
          "usage": { "input_tokens": 999, "output_tokens": 888 }
        }
        """.utf8)
        let transport = AnthropicMessagesTransportStub(data: response, statusCode: 200)
        let client = AnthropicMessagesNoteGenerationClient(transport: transport)
        let provider = AnthropicMessagesNoteGenerationProvider(
            configuration: AnthropicMessagesConfiguration(apiKey: "claude-secret"),
            client: client
        )

        let result = try await provider.generateNote(request: makeNoteGenerationRequest(
            recordingID: "claude-note",
            sanitizedRecordingID: "claude-note",
            transcriptMarkdown: "高斯公式和向量场积分有关。"
        ))

        #expect(result.providerID == "anthropicMessages")
        #expect(result.modelName == "claude-sonnet-4-6")
        #expect(result.modelOutputWasTruncated)
        #expect(result.markdown.contains("Provider: Claude / Anthropic"))
        #expect(result.markdown.contains("Claude 公开笔记"))
        #expect(result.markdown.contains("模型输出可能因长度限制被截断"))
        #expect(!result.markdown.contains("input_tokens"))
        #expect(!result.markdown.contains("output_tokens"))
        #expect(!result.markdown.contains("claude-secret"))
    }

    @Test func openAICompatibleEndpointURLHandlesTrailingSlash() throws {
        let noSlash = try OpenAICompatibleNoteGenerationClient.endpointURL(
            baseURLString: "http://127.0.0.1:1234/v1",
            path: "models"
        )
        let slash = try OpenAICompatibleNoteGenerationClient.endpointURL(
            baseURLString: "http://127.0.0.1:1234/v1/",
            path: "/chat/completions"
        )

        #expect(noSlash.absoluteString == "http://127.0.0.1:1234/v1/models")
        #expect(slash.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
    }

    @Test func openAICompatibleRequestOmitsAuthorizationWhenAPIKeyIsEmpty() throws {
        let client = OpenAICompatibleNoteGenerationClient()
        let request = try client.makeRequest(
            path: "models",
            method: "GET",
            configuration: OpenAICompatibleNoteGenerationConfiguration(apiKey: " "),
            timeout: 10,
            body: nil
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func openAICompatibleRequestSendsBearerAuthorizationWhenAPIKeyExists() throws {
        let client = OpenAICompatibleNoteGenerationClient()
        let request = try client.makeRequest(
            path: "models",
            method: "GET",
            configuration: OpenAICompatibleNoteGenerationConfiguration(apiKey: " local-secret "),
            timeout: 10,
            body: nil
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer local-secret")
    }

    @Test @MainActor func noteGenerationTestModelRequestUsesReasoningSafeOptions() async throws {
        let response = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "Rokurics AI OK" },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, client: client)

        let result = await store.testModel(configuration: OpenAICompatibleNoteGenerationConfiguration())
        let body = try requestBodyJSON(from: try #require(transport.lastRequest))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let systemMessage = try #require(messages.first?["content"] as? String)
        let userMessage = try #require(messages.dropFirst().first?["content"] as? String)

        #expect(result.isSuccess)
        #expect((body["max_tokens"] as? NSNumber)?.intValue == 512)
        #expect((body["temperature"] as? NSNumber)?.doubleValue == 0.1)
        #expect((body["stream"] as? Bool) == false)
        #expect(systemMessage.contains("不要输出思考过程"))
        #expect(userMessage.contains("Rokurics AI OK"))
    }

    @Test func openAICompatibleChatResponseParsesFirstChoiceContent() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "# 录音笔记\\n\\n## 摘要" },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)

        let result = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data)

        #expect(result.content.contains("# 录音笔记"))
        #expect(result.finishReason == "stop")
    }

    @Test func openAICompatibleChatResponseRejectsEmptyContent() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "   " },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)

        do {
            _ = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data)
            Issue.record("Expected empty content to fail")
        } catch let error as OpenAICompatibleNoteGenerationClientError {
            if case .emptyContent(let diagnostics) = error {
                #expect(diagnostics.messageContentWasPresent)
                #expect(diagnostics.contentLength == 0)
                #expect(diagnostics.choicesCount == 1)
            } else {
                Issue.record("Expected empty content error")
            }
        }
    }

    @Test func openAICompatibleChatResponseRejectsReasoningOnlyContent() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "",
                "reasoning_content": "private reasoning should not appear"
              },
              "finish_reason": "stop"
            }
          ],
          "usage": {
            "prompt_tokens": 12,
            "completion_tokens": 413,
            "total_tokens": 425,
            "completion_tokens_details": { "reasoning_tokens": 413 }
          }
        }
        """.utf8)

        do {
            _ = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data, statusCode: 200)
            Issue.record("Expected reasoning-only content to fail")
        } catch let error as OpenAICompatibleNoteGenerationClientError {
            if case .reasoningContentWithoutFinalContent(let diagnostics) = error {
                #expect(diagnostics.statusCode == 200)
                #expect(diagnostics.reasoningContentLength > 0)
                #expect(diagnostics.reasoningTokens == 413)
                #expect(!error.localizedDescription.contains("private reasoning should not appear"))
            } else {
                Issue.record("Expected reasoning-only error")
            }
        }
    }

    @Test func openAICompatibleChatResponseRejectsLengthBeforeFinalContent() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "   " },
              "finish_reason": "length"
            }
          ],
          "usage": {
            "prompt_tokens": 8,
            "completion_tokens": 512,
            "total_tokens": 520,
            "completion_tokens_details": { "reasoning_tokens": 413 }
          }
        }
        """.utf8)

        do {
            _ = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data, statusCode: 200)
            Issue.record("Expected length-limited empty content to fail")
        } catch let error as OpenAICompatibleNoteGenerationClientError {
            if case .finalContentStoppedByLength(let diagnostics) = error {
                #expect(diagnostics.finishReason == "length")
                #expect(diagnostics.contentLength == 0)
                #expect(diagnostics.reasoningTokens == 413)
                #expect(error.localizedDescription.contains("请增大 max_tokens"))
            } else {
                Issue.record("Expected length-before-content error")
            }
        }
    }

    @Test func openAICompatibleChatResponseAllowsLengthWhenContentExists() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "Rokurics AI OK" },
              "finish_reason": "length"
            }
          ]
        }
        """.utf8)

        let result = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data)

        #expect(result.content == "Rokurics AI OK")
        #expect(result.isLengthLimited)
    }

    @Test func openAICompatibleEmptyContentDiagnosticsDoNotExposeBodyOrAPIKey() async throws {
        let response = Data("""
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "",
                "reasoning_content": "secret reasoning trace"
              },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)

        do {
            _ = try await client.chatCompletion(
                configuration: OpenAICompatibleNoteGenerationConfiguration(apiKey: "local-secret"),
                messages: [OpenAICompatibleMessage(role: "user", content: "ping")],
                timeout: 30,
                maxTokens: 512
            )
            Issue.record("Expected empty content to fail")
        } catch {
            #expect(error.localizedDescription.contains("status=200"))
            #expect(!error.localizedDescription.contains("secret reasoning trace"))
            #expect(!error.localizedDescription.contains("local-secret"))
            #expect(!error.localizedDescription.contains("\"choices\""))
        }
    }

    @Test func openAICompatibleLengthFinishReasonMarksTruncatedNote() async throws {
        let response = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "# 录音笔记\\n\\n## 摘要\\n测试" },
              "finish_reason": "length"
            }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let provider = OpenAICompatibleNoteGenerationProvider(
            configuration: OpenAICompatibleNoteGenerationConfiguration(modelName: "google/gemma-4-e4b"),
            client: client
        )

        let result = try await provider.generateNote(request: makeNoteGenerationRequest(
            recordingID: "openai-length",
            sanitizedRecordingID: "openai-length",
            transcriptMarkdown: "高斯公式和向量场积分有关。"
        ))

        #expect(result.modelOutputWasTruncated)
        #expect(result.markdown.contains("模型输出可能因长度限制被截断"))
    }

    @Test func openAICompatibleProviderDoesNotPersistReasoningContent() async throws {
        let response = Data("""
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "# 录音笔记\\n\\n## 摘要\\n公开笔记",
                "reasoning_content": "hidden reasoning should never be saved"
              },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let provider = OpenAICompatibleNoteGenerationProvider(
            configuration: OpenAICompatibleNoteGenerationConfiguration(modelName: "google/gemma-4-e4b"),
            client: client
        )

        let result = try await provider.generateNote(request: makeNoteGenerationRequest(
            recordingID: "openai-reasoning",
            sanitizedRecordingID: "openai-reasoning",
            transcriptMarkdown: "高斯公式和向量场积分有关。"
        ))

        #expect(result.markdown.contains("公开笔记"))
        #expect(!result.markdown.contains("hidden reasoning"))
    }

    @Test func openAICompatibleProviderPrefersTranscriptMarkdownOverJSONText() {
        let request = NoteGenerationRequest(
            taskID: "task-transcript-priority",
            recordingID: "transcript-priority",
            sanitizedRecordingID: "transcript-priority",
            title: "优先级",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 6,
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            transcriptionProviderID: "whisper.cpp",
            transcriptionModelName: "small",
            transcriptResult: makeTranscriptionResult(text: "JSON 正文"),
            transcriptMarkdown: "Markdown 正文",
            requestedAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(OpenAICompatibleNoteGenerationProvider.transcriptInput(from: request) == "Markdown 正文")
    }

    @Test func noteGenerationTranscriptLoaderAllowsJSONTextWithoutMarkdown() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let transcriptURL = scratchURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("1970-01-01", isDirectory: true)
            .appendingPathComponent("json-only", isDirectory: true)
            .appendingPathComponent("transcript.json", isDirectory: false)
        try FileManager.default.createDirectory(at: transcriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(makeTranscriptionResult(text: "只有 JSON 的转写正文")).write(to: transcriptURL)

        let loaded = try NoteGenerationTranscriptLoader().load(source: makeNoteSource(
            transcriptURL: transcriptURL,
            transcriptMarkdownURL: transcriptURL.deletingLastPathComponent().appendingPathComponent("missing.md")
        ))

        #expect(loaded.transcriptMarkdown == nil)
        #expect(loaded.transcriptResult?.text == "只有 JSON 的转写正文")
    }

    @Test func openAICompatibleTranscriptInputIsTruncatedConservatively() {
        let result = OpenAICompatibleNoteGenerationProvider.truncatedTranscript(
            String(repeating: "课", count: 12_010),
            maxCharacters: 12_000
        )

        #expect(result.text.count == 12_000)
        #expect(result.wasTruncated)
    }

    @Test func noteGenerationTranscriptLoaderReportsMissingDocuments() throws {
        let loader = NoteGenerationTranscriptLoader()
        let source = makeNoteSource(
            transcriptURL: nil,
            transcriptMarkdownURL: nil
        )

        do {
            _ = try loader.load(source: source)
            Issue.record("Expected missing transcript documents to fail")
        } catch let error as NoteGenerationError {
            #expect(error == .transcriptDocumentMissing)
        }
    }

    @Test func noteGenerationTranscriptLoaderAllowsMarkdownWithoutJSON() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let markdownURL = scratchURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("1970-01-01", isDirectory: true)
            .appendingPathComponent("md-only", isDirectory: true)
            .appendingPathComponent("transcript.md", isDirectory: false)
        try FileManager.default.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "只有 Markdown 的转写正文".write(to: markdownURL, atomically: true, encoding: .utf8)

        let loader = NoteGenerationTranscriptLoader()
        let loaded = try loader.load(source: makeNoteSource(
            transcriptURL: markdownURL.deletingLastPathComponent().appendingPathComponent("missing.json"),
            transcriptMarkdownURL: markdownURL
        ))

        #expect(loaded.transcriptResult == nil)
        #expect(loaded.transcriptMarkdown == "只有 Markdown 的转写正文")
    }

    @Test func noteInboxActionLabelsMatchNoteState() {
        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "notStarted", transcriptionError: nil),
            isGenerating: false
        ) == nil)

        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil),
            isGenerating: false
        )?.label == "生成笔记")

        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil),
            isGenerating: true
        )?.label == "生成中")

        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(
                transcriptionStatus: "transcribed",
                transcriptionError: nil,
                noteStatus: "generated",
                noteRelativePath: "notes/1970-01-01/recording-01/note.md"
            ),
            isGenerating: false
        )?.label == "查看笔记")

        #expect(MacAudioInboxNoteRowAction.regenerateAction(
            for: makeInboxItem(
                transcriptionStatus: "transcribed",
                transcriptionError: nil,
                noteStatus: "generated",
                noteRelativePath: "notes/1970-01-01/recording-01/note.md"
            ),
            isGenerating: false
        )?.label == "重新生成")

        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(
                transcriptionStatus: "transcribed",
                transcriptionError: nil,
                noteStatus: "failed",
                noteError: "未找到可用于生成笔记的转写文档"
            ),
            isGenerating: false
        )?.label == "重试笔记")
    }

    @Test func hoverDeleteIconPresentationSwitchesOnlyWhenIconHovered() {
        let regular = MacAudioInboxIconPresentation.resolve(isDeleteIconHovered: false)
        let destructive = MacAudioInboxIconPresentation.resolve(isDeleteIconHovered: true)

        #expect(regular.systemImage == "waveform")
        #expect(regular.isDestructive == false)
        #expect(regular.containerSize == destructive.containerSize)
        #expect(regular.containerSize == 38)
        #expect(destructive.systemImage == "trash.fill")
        #expect(destructive.isDestructive)
        #expect(destructive.glyphSize <= regular.glyphSize)
    }

    @Test func transcriptMarkdownLoaderReadsExistingMarkdown() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let transcriptURL = scratchURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("2026-05-17", isDirectory: true)
            .appendingPathComponent("recording-01", isDirectory: true)
            .appendingPathComponent("transcript.md", isDirectory: false)
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# 录音\n\n你好 Rokurics".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptMarkdownRelativePath: "transcripts/2026-05-17/recording-01/transcript.md"
        )
        let loader = TranscriptMarkdownDocumentLoader(rootURL: scratchURL)

        #expect(loader.load(item: item) == .loaded("# 录音\n\n你好 Rokurics"))
    }

    @Test func transcriptMarkdownLoaderFallsBackFromTranscriptJSONPath() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let transcriptURL = scratchURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("2026-05-17", isDirectory: true)
            .appendingPathComponent("recording-02", isDirectory: true)
            .appendingPathComponent("transcript.md", isDirectory: false)
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "fallback markdown".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptRelativePath: "transcripts/2026-05-17/recording-02/transcript.json",
            transcriptMarkdownRelativePath: nil
        )
        let loader = TranscriptMarkdownDocumentLoader(rootURL: scratchURL)

        #expect(loader.load(item: item) == .loaded("fallback markdown"))
    }

    @Test func transcriptMarkdownLoaderReportsFriendlyMissingDocument() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptMarkdownRelativePath: "transcripts/missing/transcript.md"
        )
        let loader = TranscriptMarkdownDocumentLoader(rootURL: scratchURL)

        #expect(loader.load(item: item) == .failed("未找到转写文档"))
    }

    @Test func transcriptCleanerExtractsBodyWithoutMarkdownMetadata() {
        let markdown = """
        # 录音 2026-05-19

        - Provider: whisper.cpp
        - Transcribed At: 2026-05-19T08:00:00Z
        - Language: zh

        ## Transcript
        今天学习矩阵乘法。
        第二句。

        ## Segments
        - [00:00.000 --> 00:03.000] 今天学习矩阵乘法。
        """

        let body = RokuricsTranscriptMarkdownCleaner.cleanedBody(from: markdown)
        let metadata = RokuricsTranscriptMarkdownCleaner.metadata(from: markdown)

        #expect(body == "今天学习矩阵乘法。\n第二句。")
        #expect(metadata["provider"] == "whisper.cpp")
        #expect(metadata["language"] == "zh")
        #expect(!body.contains("Provider"))
        #expect(!body.contains("Transcribed At"))
        #expect(!body.contains("Language"))
        #expect(!body.contains("## Transcript"))
        #expect(!body.contains("## Segments"))
    }

    @Test func noteCleanerRemovesTopMetadataAndKeepsStudyContent() {
        let markdown = """
        # 录音笔记

        > 由 Rokurics 生成
        > Provider: OpenAI-compatible
        > Model: deepseek-v4-pro

        ## 基本信息
        - 生成时间：2026-05-19 08:00
        - 转写来源：transcript.md
        - 转写模型：small

        ## 摘要
        这是摘要。

        ## 重点
        - 第一条
        """

        let body = RokuricsNoteMarkdownCleaner.cleanedBody(from: markdown)
        let metadata = RokuricsNoteMarkdownCleaner.metadata(from: markdown)

        #expect(metadata["provider"] == "OpenAI-compatible")
        #expect(metadata["model"] == "deepseek-v4-pro")
        #expect(body.contains("## 摘要"))
        #expect(body.contains("这是摘要。"))
        #expect(body.contains("- 第一条"))
        #expect(!body.contains("Provider"))
        #expect(!body.contains("Model"))
        #expect(!body.contains("## 基本信息"))
    }

    @Test func noteSummaryPreviewExtractsSummaryAndFallsBackToBodyPreview() {
        let markdown = """
        # 录音笔记

        > Provider: Mock

        ## 摘要

        这是一段适合卡片显示的摘要。

        ## 重点

        - 第一个重点
        - 第二个重点
        """
        let fallbackMarkdown = "# 录音笔记\n\n## 大纲\n\n没有摘要时使用正文预览。"

        #expect(NoteSummaryPreview.shortSummary(from: markdown) == "这是一段适合卡片显示的摘要。")
        #expect(NoteSummaryPreview.keyPoints(from: markdown) == ["第一个重点", "第二个重点"])
        #expect(NoteSummaryPreview.shortSummary(from: fallbackMarkdown) == nil)
        #expect(NoteSummaryPreview.fallbackSummary(from: fallbackMarkdown).contains("没有摘要时使用正文预览"))
    }

    @Test func noteSummaryPreviewDoesNotKeepSensitiveDebugText() {
        let markdown = """
        # 录音笔记

        ## 摘要

        API Key: sk-secret
        response JSON should not appear
        安全摘要
        """

        let summary = NoteSummaryPreview.shortSummary(from: markdown)

        #expect(summary == "安全摘要")
        #expect(summary?.contains("sk-secret") == false)
        #expect(summary?.contains("response JSON") == false)
    }

    @Test func noteStoreRegeneratingNoteUpdatesSummaryPreview() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let request = makeNoteGenerationRequest(recordingID: "summary-update-01", sanitizedRecordingID: "summary-update-01")
        let store = NoteStore(rootURL: scratchURL)
        let first = NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: "mockNoteGenerationProvider",
            providerName: "Mock",
            modelName: "mock-1",
            markdown: "# 录音笔记\n\n## 摘要\n\n第一版摘要",
            startedAt: Date(timeIntervalSince1970: 10),
            completedAt: Date(timeIntervalSince1970: 11),
            status: "generated"
        )
        let second = NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: "mockNoteGenerationProvider",
            providerName: "Mock",
            modelName: "mock-2",
            markdown: "# 录音笔记\n\n## 摘要\n\n第二版摘要",
            startedAt: Date(timeIntervalSince1970: 12),
            completedAt: Date(timeIntervalSince1970: 13),
            status: "generated"
        )

        let saveResult = try store.save(result: first, request: request)
        _ = try store.save(result: second, request: request)
        let preview = try #require(store.loadSummaryPreview(noteRelativePath: saveResult.noteRelativePath))

        #expect(preview.shortSummary == "第二版摘要")
        #expect(preview.modelName == "mock-2")
    }

    @Test func markdownRendererParsesHeadingsBulletsAndParagraphs() {
        let blocks = RokuricsMarkdownRenderer.blocks(from: "# 摘要\n\n- 第一条\n普通段落")

        #expect(blocks == [
            .heading(level: 1, text: "摘要"),
            .bullet("第一条"),
            .paragraph("普通段落")
        ])
    }

    @Test func macContentPagesUseIconOnlyBackButton() throws {
        #expect(RokuricsBackButton.visibleTitle.isEmpty)
        #expect(RokuricsBackButton.accessibilityTitle == "返回")
        #expect(RokuricsInfoButton.visibleTitle.isEmpty)
        #expect(RokuricsInfoButton.accessibilityTitle == "信息")
        #expect(RokuricsCircleIconButton.size == RokuricsCircleIconButtonConfiguration.size)

        let repoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "RokuricsMac/MacAudioInboxView.swift",
            "RokuricsMac/MacNoteDetailView.swift",
            "RokuricsMac/MacStudyLibraryView.swift"
        ]

        for relativePath in relativePaths {
            let text = try String(contentsOf: repoURL.appendingPathComponent(relativePath), encoding: .utf8)
            #expect(!text.contains("Label(\"返回\""))
            #expect(!text.contains("Button(\"返回\""))
            #expect(!text.contains("Text(\"返回\""))
        }

        let transcriptText = try String(contentsOf: repoURL.appendingPathComponent("RokuricsMac/MacAudioInboxView.swift"), encoding: .utf8)
        let noteText = try String(contentsOf: repoURL.appendingPathComponent("RokuricsMac/MacNoteDetailView.swift"), encoding: .utf8)
        #expect(transcriptText.contains("RokuricsDocumentPageHeader"))
        #expect(transcriptText.contains("RokuricsInfoButton"))
        #expect(noteText.contains("RokuricsDocumentPageHeader"))
        #expect(noteText.contains("RokuricsInfoButton"))
    }

    @Test func fileRevealServiceRevealsFilesAndOpensFolders() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let directoryURL = scratchURL.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("note.md", isDirectory: false)
        try "note".write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(FileRevealService.action(for: directoryURL.path) == .open(directoryURL.standardizedFileURL))
        #expect(FileRevealService.action(for: fileURL.path) == .reveal(fileURL.standardizedFileURL))
        #expect(FileRevealService.action(for: "notes/note.md", rootURL: scratchURL) == .reveal(fileURL.standardizedFileURL))
        #expect(FileRevealService.looksOpenablePath("transcripts/2026-05-19/a/transcript.md"))
    }

    @Test func macStudyLibraryBreadcrumbNavigationTruncatesBrowsePath() {
        let fullPath = StudyBrowsePath(components: ["数学", "线性代数", "Ch1", "矩阵"])
        let breadcrumbs = StudyLibraryBrowser.breadcrumbs(for: fullPath)
        var state = MacStudyLibraryNavigationState(browsePath: fullPath)

        state.navigate(to: breadcrumbs[0].path)
        #expect(state.browsePath.components == [])

        state.navigate(to: breadcrumbs[1].path)
        #expect(state.browsePath.components == ["数学"])

        state.navigate(to: breadcrumbs[2].path)
        #expect(state.browsePath.components == ["数学", "线性代数"])

        state.navigate(to: breadcrumbs[3].path)
        #expect(state.browsePath.components == ["数学", "线性代数", "Ch1"])
    }

    @Test func sharedFolderTileUsesSharedFolderAccentPalette() {
        #expect(StudyFolderColorToken.blue.sharedAccentColor != nil)
        #expect(StudyFolderColorToken.default.sharedAccentColor == nil)
    }

    @Test func folderContextMenuUsesFinderLikeActionAndTwoColorRows() {
        #expect(MacFolderContextMenuModel.primaryActionTitles == ["重命名", "移入废纸篓"])
        #expect(MacFolderContextMenuModel.colorTokens == [.default, .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .gray])
        #expect(MacFolderContextMenuModel.colorTokens.count == 12)
        #expect(MacFolderContextMenuModel.colorRows.count == 2)
        #expect(MacFolderContextMenuModel.colorRows.allSatisfy { $0.count == 6 })
        #expect(MacFolderContextMenuModel.colorRows.flatMap { $0 } == MacFolderContextMenuModel.colorTokens)
    }

    @Test func legacyFolderColorTokensStillDecode() throws {
        let data = try #require("\"blue\"".data(using: .utf8))
        let decoded = try JSONDecoder().decode(StudyFolderColorToken.self, from: data)

        #expect(decoded == .blue)
    }

    @Test func noteDefaultInfoHidesTranscriptPathAndRawProviderID() {
        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptMarkdownRelativePath: "transcripts/2026-05-16/recording-01/transcript.md",
            noteStatus: "generated",
            noteRelativePath: "notes/2026-05-16/recording-01/note.md"
        )
        let markdown = """
        # 录音笔记

        > Provider: mockNoteGenerationProvider
        > Model: deepseek-v4-pro

        ## 基本信息
        - 转写来源：transcripts/2026-05-16/recording-01/transcript.md

        ## 摘要
        内容
        """

        let metadata = StudyItemMetadata.defaultMetadata(for: item)
        let defaultText = StudyReadingMetadataRows.noteInfoRows(item: metadata, markdown: markdown, receiveRecord: nil)
            .map(\.value)
            .joined(separator: " ")
        let advancedText = StudyReadingMetadataRows.noteAdvancedRows(item: metadata, markdown: markdown, receiveRecord: nil)
            .map(\.value)
            .joined(separator: " ")

        #expect(defaultText.contains("deepseek-v4-pro"))
        #expect(defaultText.contains("Mock"))
        #expect(!defaultText.contains("transcripts/2026-05-16"))
        #expect(!defaultText.contains("mockNoteGenerationProvider"))
        #expect(advancedText.contains("transcripts/2026-05-16/recording-01/transcript.md"))
        #expect(!advancedText.contains("mockNoteGenerationProvider"))
    }

    @Test func transcriptDefaultInfoHidesTranscriptPathAndAdvancedKeepsIt() {
        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptRelativePath: "transcripts/2026-05-16/recording-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/2026-05-16/recording-01/transcript.md"
        )
        let markdown = """
        - Provider: whisper.cpp
        - Language: zh

        ## Transcript
        内容
        """

        let metadata = StudyItemMetadata.defaultMetadata(for: item)
        let defaultText = StudyReadingMetadataRows.transcriptInfoRows(item: metadata, markdown: markdown, transcriptResult: nil, receiveRecord: nil)
            .map(\.value)
            .joined(separator: " ")
        let advancedText = StudyReadingMetadataRows.transcriptAdvancedRows(item: metadata, markdown: markdown, transcriptResult: nil, receiveRecord: nil)
            .map(\.value)
            .joined(separator: " ")

        #expect(defaultText.contains("zh"))
        #expect(!defaultText.contains("transcripts/2026-05-16"))
        #expect(advancedText.contains("transcripts/2026-05-16/recording-01/transcript.md"))
    }

    @Test func transcriptInfoPanelRowsContainReadableTranscriptionMetadata() {
        let item = makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil)
        let result = TranscriptionResult(
            taskID: "task",
            recordingID: item.id,
            providerID: "whisperCppTranscriptionProvider",
            providerName: "WhisperCppTranscriptionProvider",
            modelName: "/models/ggml-small.bin",
            language: "zh",
            text: "正文",
            segments: [],
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            status: "transcribed"
        )
        let rows = StudyReadingMetadataRows.transcriptInfoRows(
            item: StudyItemMetadata.defaultMetadata(for: item),
            markdown: "## Transcript\n正文",
            transcriptResult: result,
            receiveRecord: nil
        )
        let text = rows.map { "\($0.label)=\($0.value)" }.joined(separator: " ")

        #expect(text.contains("录音时间"))
        #expect(text.contains("时长"))
        #expect(text.contains("语言=zh"))
        #expect(text.contains("转写 Provider=whisper.cpp"))
        #expect(text.contains("转写模型=ggml-small.bin"))
    }

    @Test func noteInfoPanelRowsContainReadableGenerationMetadata() {
        let item = makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil)
        let rows = StudyReadingMetadataRows.noteInfoRows(
            item: StudyItemMetadata.defaultMetadata(for: item),
            markdown: "> Provider: mockNoteGenerationProvider\n> Model: mock-note-local\n\n## 基本信息\n- 生成时间：2026-05-19 20:00\n\n## 摘要\n摘要",
            receiveRecord: nil
        )
        let text = rows.map { "\($0.label)=\($0.value)" }.joined(separator: " ")

        #expect(text.contains("生成时间=2026-05-19 20:00"))
        #expect(text.contains("Note Provider=Mock"))
        #expect(text.contains("模型=mock-note-local"))
    }

    @Test func aiNotePromptsRequireShortSummarySection() {
        let request = makeNoteGenerationRequest(transcriptMarkdown: "今天学习矩阵。")
        let openAIMessages = OpenAICompatibleNoteGenerationProvider.messages(
            request: request,
            transcript: "今天学习矩阵。",
            configuration: OpenAICompatibleNoteGenerationConfiguration(),
            wasTruncated: false
        )
        let anthropicPrompt = AnthropicMessagesNoteGenerationProvider.prompt(
            request: request,
            transcript: "今天学习矩阵。",
            configuration: AnthropicMessagesConfiguration(),
            wasTruncated: false
        )
        let openAIText = openAIMessages.map { $0.content }.joined(separator: "\n")

        #expect(openAIText.contains("## 摘要"))
        #expect(openAIText.contains("1～3 句简短摘要"))
        #expect(anthropicPrompt.contains("## 摘要"))
        #expect(anthropicPrompt.contains("1～3 句简短摘要"))
    }

    @Test func documentReadingPagesDefaultToContentOnlyMetadataBehindInfoButton() {
        #expect(RokuricsDocumentReadingLayout.defaultShowsMetadataCards == false)
    }

    @Test func recordingDetailDefaultInfoHidesRecordingIDButAdvancedKeepsFileState() {
        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptMarkdownRelativePath: "transcripts/2026-05-16/recording-01/transcript.md",
            noteStatus: "generated",
            noteRelativePath: "notes/2026-05-16/recording-01/note.md"
        )

        let rows = StudyRecordingFileStatusRows.rows(for: StudyItemMetadata.defaultMetadata(for: item))
        let defaultText = rows
            .filter { !$0.isTechnical }
            .map(\.value)
            .joined(separator: " ")
        let advancedText = rows
            .map(\.value)
            .joined(separator: " ")

        #expect(!defaultText.contains(item.id))
        #expect(advancedText.contains(item.id))
        #expect(advancedText.contains("transcripts/2026-05-16/recording-01/transcript.md"))
        #expect(advancedText.contains("notes/2026-05-16/recording-01/note.md"))
    }

    @Test func rawProviderIDsMapToUserFacingDisplayNames() {
        #expect(RokuricsProviderDisplayName.note("mockNoteGenerationProvider") == "Mock")
        #expect(RokuricsProviderDisplayName.note("openAICompatible") == "OpenAI-compatible")
        #expect(RokuricsProviderDisplayName.note("anthropicMessages") == "Claude / Anthropic")
        #expect(RokuricsProviderDisplayName.transcription("mockTranscriptionProvider") == "Mock")
        #expect(RokuricsProviderDisplayName.transcription("whisper.cpp") == "whisper.cpp")
    }

    @Test func sidebarDoesNotContainTopLevelTranscriptionItem() {
        #expect(!MacSidebarItem.allCases.map(\.title).contains("转写"))
    }

    @Test func sidebarDoesNotContainTopLevelNotesItem() {
        #expect(!MacSidebarItem.allCases.map(\.title).contains("笔记"))
        #expect(!MacSidebarItem.allCases.map(\.title).contains("仪表盘"))
        #expect(MacSidebarItem.allCases.map(\.title) == ["学习库", "AI 对话", "iPhone 连接"])
    }

    @Test func temporaryDebugMarkersAreRemovedFromPrimaryUIFiles() throws {
        let markers = [
            "09" + "19", "09" + "21", "10" + "03", "10" + "25", "10" + "51", "11" + "21",
            "11" + "36", "13" + "22", "14" + "58", "17" + "18", "17" + "42"
        ]
        let repoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "RokuricsMac/MacSettingsView.swift",
            "RokuricsMac/MacStudyLibraryView.swift",
            "Rokurics/RecordingLibraryView.swift"
        ]

        for relativePath in relativePaths {
            let text = try String(contentsOf: repoURL.appendingPathComponent(relativePath), encoding: .utf8)
            for marker in markers {
                #expect(!text.contains("Text(\"\(marker)\")"))
            }
        }
    }

    @Test func macSettingsSectionsUseKikariaStyleHomeGroups() {
        #expect(MacSettingsSection.allCases.map(\.rawValue) == [
            "userProfile",
            "transcription",
            "ai",
            "about"
        ])
        #expect(MacSettingsHomeSummary.sectionOrder.map(\.title) == [
            "用户资料",
            "转写",
            "AI",
            "关于"
        ])
        #expect(!MacSettingsSection.allCases.map(\.title).contains("连接"))
    }

    @Test func macSettingsHomeUsesReducedRowArchitecture() {
        #expect(MacSettingsHomeSummary.transcriptionRows == [
            "Provider",
            "模型",
            "授权与测试"
        ])
        #expect(MacSettingsHomeSummary.aiRows == [
            "Provider",
            "模型",
            "API 设置",
            "测试"
        ])
        #expect(MacSettingsHomeSummary.aboutRows == [
            "存储",
            "隐私政策",
            "版权"
        ])
    }

    @Test func macSettingsHomeCanOpenPrimaryDetailPages() {
        #expect(MacSettingsDetail.allCases.map(\.rawValue) == [
            "profile",
            "transcriptionProvider",
            "transcriptionModel",
            "transcriptionAuthorization",
            "aiProvider",
            "aiModel",
            "aiAPI",
            "aiTest",
            "privacyPolicy",
            "copyright"
        ])
        #expect(MacSettingsDetail.allCases.map(\.title) == [
            "编辑个人资料",
            "转写 Provider",
            "转写模型",
            "授权与测试",
            "AI Provider",
            "AI 模型",
            "API 设置",
            "测试",
            "隐私政策",
            "版权"
        ])
    }

    @Test func macSettingsStorageLocationUsesRokuricsApplicationSupportRoot() throws {
        let rootURL = MacSettingsStorageLocation.rootURL()

        #expect(rootURL.lastPathComponent == "Rokurics")
        #expect(rootURL.path.contains("Application Support"))
        #expect(!rootURL.path.contains("/Desktop/"))
        #expect(!rootURL.path.contains("/Downloads/"))
        #expect(!rootURL.path.contains("/Documents/"))
    }

    @Test func macSettingsHomeSummaryHidesSensitiveAndVerboseConfiguration() {
        var whisperConfiguration = WhisperCppTranscriptionConfiguration.default
        whisperConfiguration.modelPath = "/tmp/rokurics/models/ggml-large-v3.bin"
        whisperConfiguration.defaultLanguage = "zh"
        let openAIConfiguration = OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: "https://secret.example/v1",
            modelName: "deepseek-v4-pro",
            apiKey: "visible-secret"
        )
        let anthropicConfiguration = AnthropicMessagesConfiguration(
            baseURLString: "https://api.anthropic.com",
            modelName: "claude-sonnet-4-6",
            apiKey: "claude-secret"
        )

        let homepageText = MacSettingsHomeSummary.homepageSummaryTexts(
            transcriptionProviderKind: .whisperCpp,
            whisperConfiguration: whisperConfiguration,
            noteProviderKind: .openAICompatible,
            openAIConfiguration: openAIConfiguration,
            anthropicConfiguration: anthropicConfiguration
        ).joined(separator: " ")

        #expect(homepageText.contains("ggml-large-v3.bin"))
        #expect(homepageText.contains("deepseek-v4-pro"))
        #expect(!homepageText.contains("/tmp/rokurics/models"))
        #expect(!homepageText.contains("https://secret.example/v1"))
        #expect(!homepageText.contains("visible-secret"))
        #expect(!homepageText.contains("claude-secret"))
    }

    @Test func macProfileDefaultsUseSeparateLocalProfileKeys() {
        #expect(MacSettingsProfileDefaults.displayName == MacUserProfile.defaultDisplayName)
        #expect(MacSettingsProfileDefaults.handle == MacUserProfile.defaultHandle)
        #expect(MacSettingsProfileDefaults.displayHandle(MacUserProfile.defaultHandle) == "@\(MacUserProfile.defaultHandle)")
        #expect(MacSettingsProfileDefaults.normalizedHandle(" @Custom ") == "Custom")
        #expect(MacSettingsProfileDefaults.displayNameKey.contains("profile"))
        #expect(!MacSettingsProfileDefaults.displayNameKey.contains("apiKey"))
        #expect(MacUserProfile.defaultDisplayName != "Vita")
        #expect(MacUserProfile.defaultHandle != "Vita_0818")
    }

    @Test func macDesignSystemCircleIconConfigurationIsUnifiedGlass() {
        #expect(RokuricsCircleIconButtonConfiguration.size >= 34)
        #expect(RokuricsCircleIconButtonConfiguration.size <= 38)
        #expect(RokuricsCircleIconButtonConfiguration.iconSize > 0)
        #expect(RokuricsCircleIconButtonConfiguration.usesGlassBackground)
        #expect(RokuricsCircleIconButtonConfiguration.borderWidth == 1)
        #expect(RokuricsCircleIconButton.size == RokuricsCircleIconButtonConfiguration.size)
    }

    @Test func macNavigationIconButtonsUseSystemSymbolsWithoutVisibleBackText() {
        #expect(RokuricsBackButton.systemImage == "chevron.left")
        #expect(RokuricsBackButton.visibleTitle.isEmpty)
        #expect(RokuricsBackButton.accessibilityTitle == "返回")
        #expect(RokuricsInfoButton.systemImage == "info")
        #expect(RokuricsInfoButton.visibleTitle.isEmpty)
        #expect(RokuricsCircleIconButtonConfiguration.usesSystemSymbols)
    }

    @Test func mixedTypographyKeepsTechnicalRunsScoped() {
        let fragments: [RokuricsTextFragment] = [
            .text("Provider: ", style: .body),
            .technical("OpenAI-compatible"),
            .text(" 已启用", style: .body)
        ]

        #expect(fragments[0].kind == .normal(.body))
        #expect(fragments[1].kind == .technical)
        #expect(fragments[2].kind == .normal(.body))
    }

    @Test func macStudyLibraryTitleUsesPageTitleToken() {
        #expect(MacStudyLibraryHeaderModel.title == "学习库")
        #expect(MacStudyLibraryHeaderModel.titleStyle == .pageTitle)
    }

    @Test func macSettingsProfileSummaryMatchesKikariaMinimalText() {
        let summary = MacSettingsProfileDefaults.profileSummaryTexts(
            displayName: "Mira",
            handle: "mira_01"
        )
        let visibleText = summary.joined(separator: " ")

        #expect(summary == ["Mira", "@mira_01"])
        #expect(!visibleText.contains("Local" + "-first"))
        #expect(!visibleText.contains("学习" + "助手"))
        #expect(!visibleText.contains("Rokurics" + " Mac"))
    }

    @Test func macEditProfileFieldsMatchKikariaTwoFieldStructure() {
        let fieldTitles = MacSettingsProfileDefaults.editFieldTitles

        #expect(fieldTitles == ["显示名称", "用户 ID"])
        #expect(!fieldTitles.contains("身" + "份"))
        #expect(!fieldTitles.contains("说" + "明"))
    }

    @Test func macProfileSaveNormalizationKeepsDisplayNameAndHandle() {
        #expect(MacSettingsProfileDefaults.normalized("  Vivian  ", fallback: MacSettingsProfileDefaults.displayName) == "Vivian")
        #expect(MacSettingsProfileDefaults.normalizedHandle(" @vivian_01 ") == "vivian_01")
    }

    @Test @MainActor func macUserProfileStorePersistsDisplayNameAndHandle() {
        let suiteName = "RokuricsMacTests.Profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MacUserProfileStore(userDefaults: defaults)

        store.update(displayName: "  Vivian  ", handle: " @vivian ")
        let reloaded = MacUserProfileStore(userDefaults: defaults)

        #expect(reloaded.profile.displayName == "Vivian")
        #expect(reloaded.profile.handle == "vivian")
        #expect(reloaded.profile.displayHandle == "@vivian")
    }

    @Test func studyLibraryHeaderUsesPageTitleTypography() {
        #expect(MacStudyLibraryHeaderModel.title == "学习库")
        #expect(!MacStudyLibraryHeaderModel.showsLeadingIcon)
        #expect(MacStudyLibraryHeaderModel.titleStyle == .pageTitle)
    }

    @Test func macTypographyDefinesSeparateChatAndPageTokens() {
        #expect(RokuricsTextStyle.pageTitle != .chatGreeting)
        #expect(RokuricsTextStyle.chatInput != .pageTitle)
        #expect(RokuricsTextStyle.technical != .body)
    }

    @Test func primaryMacUIFilesDoNotHardcodeDefaultUserName() throws {
        let repoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let literal = "Vi" + "ta"
        let relativePaths = [
            "RokuricsMac/MacAIChatView.swift",
            "RokuricsMac/MacSidebarView.swift",
            "RokuricsMac/MacSettingsView.swift"
        ]

        for relativePath in relativePaths {
            let text = try String(contentsOf: repoURL.appendingPathComponent(relativePath), encoding: .utf8)
            #expect(!text.contains("\"\(literal)\""))
        }
    }

    @Test func studyLibraryRecordingDetailNavigationRestoresBrowsePath() {
        let originalPath = StudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])
        var state = MacStudyLibraryNavigationState(browsePath: originalPath)

        state.openRecordingDetail(recordingID: "recording-01")

        #expect(state.isShowingRecordingDetail)
        #expect(state.selectedRecordingDetailID == "recording-01")
        #expect(state.detailReturnPath == originalPath)

        state.browsePath = StudyBrowsePath()
        state.closeRecordingDetail()

        #expect(!state.isShowingRecordingDetail)
        #expect(state.selectedRecordingDetailID == nil)
        #expect(state.browsePath == originalPath)
    }

    @Test func dashboardDoesNotContainTranscriptionQueueCard() {
        #expect(!MacDashboardCardKind.visibleCards.map(\.title).contains("转写队列"))
    }

    @Test func macRenameInboxItemUpdatesNormalizedTitle() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-rename-01", title: "原始标题", store: store)

        let item = try store.updateDisplayTitle(recordingID: "mac-rename-01", rawTitle: " 新标题 ")
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-rename-01")

        #expect(item.title == "新标题")
        #expect(record.normalizedTitle == "新标题")
    }

    @Test func macRenameDoesNotOverwriteOriginalTitle() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-rename-02", title: "上传标题", store: store)

        _ = try store.updateDisplayTitle(recordingID: "mac-rename-02", rawTitle: "Mac 标题")
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-rename-02")

        #expect(record.originalTitle == "上传标题")
        #expect(record.normalizedTitle == "Mac 标题")
    }

    @Test func receiveRecordMissingDeletedFieldsDefaultsToActive() throws {
        let record = RecordingReceiveRecord(
            recordingID: "legacy",
            sanitizedRecordingID: "legacy",
            receivedAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            sourceDeviceID: "device",
            sourceDeviceName: "iPhone",
            originalTitle: "旧录音",
            normalizedTitle: "旧录音",
            audioFileName: "audio.m4a",
            originalAudioFileName: "legacy.m4a",
            metadataFileName: "metadata.json",
            status: "received",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            processingStatus: "notStarted",
            suggestedCategory: nil,
            course: nil,
            category: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 6,
            fileSize: 5,
            suggestedFolder: nil,
            userConfirmedFolder: nil,
            checksum: nil,
            audioRelativePath: "audio/inbox/1970-01-01/legacy/audio.m4a",
            metadataRelativePath: "audio/inbox/1970-01-01/legacy/metadata.json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: try encoder.encode(record)) as? [String: Any])
        object.removeValue(forKey: "isDeleted")
        object.removeValue(forKey: "deletedAt")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingReceiveRecord.self, from: data)

        #expect(decoded.isDeleted == false)
        #expect(decoded.deletedAt == nil)
    }

    @Test func macSoftDeleteInboxItemMarksDeletedWithoutRemovingDirectory() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let directoryURL = try saveMacInboxRecording(id: "mac-delete-01", title: "删除", store: store)

        try store.deleteRecording(recordingID: "mac-delete-01")
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-delete-01")

        #expect(record.isDeleted)
        #expect(record.deletedAt != nil)
        #expect(FileManager.default.fileExists(atPath: directoryURL.path))
        #expect(store.loadInboxItems().isEmpty)
        #expect(store.loadTrashedInboxItems().map(\.id) == ["mac-delete-01"])
    }

    @Test func macRestoreClearsDeletedStateAndReturnsToInbox() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-restore-01", title: "恢复", store: store)

        try store.deleteRecording(recordingID: "mac-restore-01")
        try store.restoreRecording(recordingID: "mac-restore-01")
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-restore-01")

        #expect(record.isDeleted == false)
        #expect(record.deletedAt == nil)
        #expect(store.loadInboxItems().map(\.id) == ["mac-restore-01"])
        #expect(store.loadTrashedInboxItems().isEmpty)
    }

    @Test func macPermanentDeleteTranscribedItemRemovesTranscriptDirectory() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try saveMacInboxRecording(id: "mac-delete-02", title: "已转写", store: store)
        let transcriptDirectoryURL = rootURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("2026-05-17", isDirectory: true)
            .appendingPathComponent("mac-delete-02", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptDirectoryURL, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: transcriptDirectoryURL.appendingPathComponent("transcript.json"))
        try Data("# transcript".utf8).write(to: transcriptDirectoryURL.appendingPathComponent("transcript.md"))
        try store.updateTranscriptionStatus(
            recordingID: "mac-delete-02",
            status: "transcribed",
            transcriptRelativePath: "transcripts/2026-05-17/mac-delete-02/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/2026-05-17/mac-delete-02/transcript.md",
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            errorMessage: nil
        )

        try store.permanentlyDeleteRecording(recordingID: "mac-delete-02")

        #expect(!FileManager.default.fileExists(atPath: transcriptDirectoryURL.path))
    }

    @Test func macPermanentDeleteRemovesRecordingDirectory() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let directoryURL = try saveMacInboxRecording(id: "mac-permanent-01", title: "永久删除", store: store)

        try store.permanentlyDeleteRecording(recordingID: "mac-permanent-01")

        #expect(!FileManager.default.fileExists(atPath: directoryURL.path))
    }

    @Test func macDeleteRejectsIndexPathOutsideAudioInbox() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        try FileManager.default.createDirectory(at: securityURL, withIntermediateDirectories: true)
        try Data("identity".utf8).write(to: securityURL.appendingPathComponent("identity.json"))
        let indexURL = rootURL
            .appendingPathComponent("metadata", isDirectory: true)
            .appendingPathComponent("recordings-index.json", isDirectory: false)
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"directoriesByRecordingID":{"evil-recording":"Security"}}"#.utf8).write(to: indexURL)

        do {
            try store.permanentlyDeleteRecording(recordingID: "evil-recording")
            Issue.record("Expected delete to reject an index path outside audio/inbox")
        } catch MacRecordingFileStoreError.unsafeDestination {
            #expect(FileManager.default.fileExists(atPath: securityURL.appendingPathComponent("identity.json").path))
        }
    }

    @Test func macDeleteDoesNotRemoveSecurityDirectory() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-delete-03", title: "安全目录", store: store)
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        try FileManager.default.createDirectory(at: securityURL, withIntermediateDirectories: true)
        try Data("paired".utf8).write(to: securityURL.appendingPathComponent("paired-devices.json"))

        try store.permanentlyDeleteRecording(recordingID: "mac-delete-03")

        #expect(FileManager.default.fileExists(atPath: securityURL.appendingPathComponent("paired-devices.json").path))
    }

    @Test func macDeleteWorksForFailedAndNotStartedItems() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-delete-failed", title: "失败", store: store, transcriptionStatus: "failed")
        try saveMacInboxRecording(id: "mac-delete-not-started", title: "未转写", store: store, transcriptionStatus: "notStarted")

        try store.deleteRecording(recordingID: "mac-delete-failed")
        try store.deleteRecording(recordingID: "mac-delete-not-started")

        #expect(store.loadInboxItems().isEmpty)
        #expect(store.loadTrashedInboxItems().count == 2)
    }

    @Test func macTrashListOnlyIncludesDeletedItems() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-active-01", title: "未删除", store: store)
        try saveMacInboxRecording(id: "mac-trash-01", title: "已删除", store: store)

        try store.deleteRecording(recordingID: "mac-trash-01")

        #expect(store.loadInboxItems().map(\.id) == ["mac-active-01"])
        #expect(store.loadTrashedInboxItems().map(\.id) == ["mac-trash-01"])
    }

    @Test func audioInboxStoreDeleteRefreshesCounts() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-count-01", title: "一", store: fileStore)
        try saveMacInboxRecording(id: "mac-count-02", title: "二", store: fileStore, transcriptionStatus: "transcribed")
        let store = AudioInboxStore(recordingFileStore: fileStore)

        try store.deleteRecording(recordingID: "mac-count-02")

        #expect(store.pendingCount == 1)
        #expect(store.transcribedCount == 0)
        #expect(store.recordingItems.map(\.id) == ["mac-count-01"])
    }

    @Test func audioInboxStoreExposesPlayableAudioURL() throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try saveMacInboxRecording(id: "mac-play-01", title: "播放", store: fileStore)
        let store = AudioInboxStore(recordingFileStore: fileStore)

        let audioURL = try store.audioFileURL(recordingID: "mac-play-01")

        #expect(audioURL.lastPathComponent == "audio.m4a")
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(audioURL.path.hasPrefix(rootURL.path))
    }

    private func makeInboxItem(
        transcriptionStatus: String,
        transcriptionError: String?,
        hasAudio: Bool = true,
        transcriptRelativePath: String? = nil,
        transcriptMarkdownRelativePath: String? = nil,
        noteStatus: String = "notGenerated",
        noteRelativePath: String? = nil,
        noteError: String? = nil
    ) -> MacRecordingInboxItem {
        MacRecordingInboxItem(
            id: "recording-01",
            title: "录音 2026-05-16 12:46",
            receivedAt: Date(timeIntervalSince1970: 0),
            duration: 6,
            fileSize: 1024,
            sourceDeviceName: "iPhone",
            transcriptionStatus: transcriptionStatus,
            noteStatus: noteStatus,
            receiveStatus: "received",
            hasAudio: hasAudio,
            transcriptRelativePath: transcriptRelativePath,
            transcriptMarkdownRelativePath: transcriptMarkdownRelativePath,
            transcriptionError: transcriptionError,
            noteRelativePath: noteRelativePath,
            noteError: noteError
        )
    }

    private func makeNoteGenerationRequest(
        recordingID: String = "note-request-01",
        sanitizedRecordingID: String = "note-request-01",
        transcriptMarkdown: String = "测试转写正文"
    ) -> NoteGenerationRequest {
        NoteGenerationRequest(
            taskID: "task-\(recordingID)",
            recordingID: recordingID,
            sanitizedRecordingID: sanitizedRecordingID,
            title: "测试录音",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 90,
            transcriptRelativePath: "transcripts/1970-01-01/\(sanitizedRecordingID)/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/\(sanitizedRecordingID)/transcript.md",
            transcriptionProviderID: "whisper.cpp",
            transcriptionModelName: "small",
            transcriptResult: nil,
            transcriptMarkdown: transcriptMarkdown,
            requestedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    private func makeNoteSource(
        transcriptURL: URL?,
        transcriptMarkdownURL: URL?
    ) -> MacRecordingNoteGenerationSource {
        MacRecordingNoteGenerationSource(
            recordingID: "note-source-01",
            sanitizedRecordingID: "note-source-01",
            title: "测试录音",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 6,
            transcriptionStatus: "transcribed",
            transcriptRelativePath: transcriptURL?.path,
            transcriptMarkdownRelativePath: transcriptMarkdownURL?.path,
            transcriptionProviderID: "whisper.cpp",
            transcriptionModelName: "small",
            transcriptURL: transcriptURL,
            transcriptMarkdownURL: transcriptMarkdownURL
        )
    }

    private func makeTranscriptionResult(text: String) -> TranscriptionResult {
        TranscriptionResult(
            taskID: "task-transcription",
            recordingID: "recording-01",
            providerID: "whisper.cpp",
            providerName: "whisper.cpp",
            modelName: "small",
            language: "zh",
            text: text,
            segments: [],
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            status: "transcribed"
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        return scratchURL
    }

    private func makeMacStore() throws -> (MacRecordingFileStore, URL) {
        let rootURL = try makeScratchDirectory()
            .appendingPathComponent("Rokurics", isDirectory: true)
        let store = MacRecordingFileStore(rootURL: rootURL)
        return (store, rootURL)
    }

    @discardableResult
    private func saveMacInboxRecording(
        id: String,
        title: String,
        store: MacRecordingFileStore,
        transcriptionStatus: String = "notStarted"
    ) throws -> URL {
        let sourceDevice = PairedDevice(
            id: "device-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: "secret",
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
        let metadata = IncomingRecordingMetadata(
            id: id,
            title: title,
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
            transcriptionStatus: transcriptionStatus,
            noteStatus: "notStarted",
            tags: [],
            sourceDeviceName: "Vita iPhone",
            sourceDeviceID: "device-01",
            uploadedAt: Date(timeIntervalSince1970: 1_807)
        )

        let receiveResult = try store.saveMetadata(metadata, sourceDevice: sourceDevice)
        _ = try store.saveAudio(body: Data("audio".utf8), recordingID: id, requestedFileName: "\(id).m4a", sourceDevice: sourceDevice)
        return receiveResult.directoryURL
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

    private func requestBodyJSON(from request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

}

private final class OpenAICompatibleTransportStub: OpenAICompatibleHTTPTransport {
    let data: Data
    let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private final class AnthropicMessagesTransportStub: AnthropicMessagesHTTPTransport {
    let data: Data
    let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.anthropic.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
