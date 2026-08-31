import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct RokuricsAIConfigurationTests {
    @Test func jsoncConfigurationResolvesIndependentSummaryAndTranscriptionModels() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent("rokurics.json")
        try Data("""
        {
          // Same shape and role keys as Intatis.
          "model": "openai/summary-model",
          "transcription_model": "openai/speech-model",
          "enabled_providers": ["openai",],
          "provider": {
            "openai": {
              "npm": "@ai-sdk/openai-compatible",
              "name": "OpenAI",
              "options": {
                "baseURL": "https://example.test/v1",
                "apiKey": "test-secret",
              },
              "models": {
                "summary-model": { "name": "Summary" },
                "speech-model": { "name": "Speech" },
              },
            },
          },
        }
        """.utf8).write(to: configurationURL)

        let store = RokuricsAIConfigurationStore(rootURL: root)
        let summary = try store.summaryRoute()
        let transcription = try store.transcriptionRoute()

        #expect(summary.modelID == "summary-model")
        #expect(transcription.modelID == "speech-model")
        #expect(summary.providerID == transcription.providerID)
        #expect(summary.apiKey == "test-secret")
        #expect(store.configurationURL == configurationURL)
    }

    @Test func savingSettingsWritesCanonicalRoleKeysAndOwnerOnlyFile() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RokuricsAIConfigurationStore(rootURL: root)
        var catalog = store.catalog
        catalog.transcriptionModel = RokuricsAIModelReference(
            providerID: "openai",
            modelID: "whisper-1"
        )
        catalog.providers[0].models.append(
            RokuricsAIModel(id: "whisper-1", displayName: "Whisper")
        )

        try store.save(
            catalog: catalog,
            apiKeysByProviderID: ["openai": "saved-secret"]
        )

        let data = try Data(contentsOf: store.configurationURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let provider = try #require((object["provider"] as? [String: Any])?["openai"] as? [String: Any])
        let options = try #require(provider["options"] as? [String: Any])
        let attributes = try FileManager.default.attributesOfItem(atPath: store.configurationURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)

        #expect(object["model"] as? String == "openai/gpt-4o-mini")
        #expect(object["transcription_model"] as? String == "openai/whisper-1")
        #expect(options["apiKey"] as? String == "saved-secret")
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test func missingTranscriptionRoleFailsWithoutUsingSummaryModel() throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RokuricsAIConfigurationStore(rootURL: root)

        #expect(throws: RokuricsAIConfigurationError.transcriptionModelNotConfigured) {
            _ = try store.transcriptionRoute()
        }
    }

    @Test func summaryRuntimeSendsOneToolFreeRequest() async throws {
        let http = CapturingAIHTTPClient(
            dataResponse: RokuricsAIHTTPResponse(
                data: Data("""
                {
                  "choices": [{
                    "message": {"content": "# 录音笔记\\n\\n## 摘要\\n测试总结"},
                    "finish_reason": "stop"
                  }]
                }
                """.utf8),
                status: 200,
                headers: ["content-type": "application/json"]
            ),
            uploadResponse: nil
        )
        let runtime = RokuricsAIRuntime(http: http)
        let result = try await runtime.generateSummary(
            input: RokuricsAISummaryInput(
                recordingTitle: "课堂",
                createdAt: Date(timeIntervalSince1970: 1_000),
                duration: 60,
                transcript: "向量场积分"
            ),
            route: route(model: "summary-model")
        )
        let request = try #require(await http.lastDataRequest())
        let bodyData = try #require(request.httpBody)
        let decodedBody = try JSONSerialization.jsonObject(with: bodyData)
        let body = try #require(decodedBody as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])

        #expect(result.contains("测试总结"))
        #expect(request.url?.absoluteString == "https://example.test/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret")
        #expect(body["model"] as? String == "summary-model")
        #expect(body["stream"] as? Bool == false)
        #expect(body["tools"] == nil)
        #expect((messages.last?["content"] as? String)?.contains("向量场积分") == true)
    }

    @Test func transcriptionRuntimeUsesDiskBackedMultipartRequest() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("audio.wav")
        try Data("RIFF-test-audio".utf8).write(to: audioURL)
        let http = CapturingAIHTTPClient(
            dataResponse: nil,
            uploadResponse: RokuricsAIHTTPResponse(
                data: Data(#"{"text":"测试文字稿"}"#.utf8),
                status: 200,
                headers: ["content-type": "application/json"]
            )
        )

        let text = try await RokuricsAIRuntime(http: http).transcribeFile(
            at: audioURL,
            route: route(model: "speech-model")
        )
        let capture = try #require(await http.lastUpload())
        let bodyText = String(data: capture.body, encoding: .utf8) ?? ""

        #expect(text == "测试文字稿")
        #expect(capture.request.url?.absoluteString == "https://example.test/v1/audio/transcriptions")
        #expect(capture.request.httpBody == nil)
        #expect(bodyText.contains("name=\"model\""))
        #expect(bodyText.contains("speech-model"))
        #expect(bodyText.contains("RIFF-test-audio"))
    }

    @Test func recordingActionsPersistTranscriptThenSummary() async throws {
        let root = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let configurationURL = root.appendingPathComponent("rokurics.json")
        try Data("""
        {
          "model": "openai/summary-model",
          "transcription_model": "openai/speech-model",
          "provider": {
            "openai": {
              "npm": "@ai-sdk/openai-compatible",
              "options": {
                "baseURL": "https://example.test/v1",
                "apiKey": "test-secret"
              },
              "models": {
                "summary-model": { "name": "Summary" },
                "speech-model": { "name": "Speech" }
              }
            }
          }
        }
        """.utf8).write(to: configurationURL)
        let configurationStore = RokuricsAIConfigurationStore(rootURL: root)
        let http = CapturingAIHTTPClient(
            dataResponse: RokuricsAIHTTPResponse(
                data: Data("""
                {
                  "choices": [{
                    "message": {"content": "# 录音笔记\\n\\n## 摘要\\n持久化总结"},
                    "finish_reason": "stop"
                  }]
                }
                """.utf8),
                status: 200,
                headers: ["content-type": "application/json"]
            ),
            uploadResponse: RokuricsAIHTTPResponse(
                data: Data(#"{"text":"持久化文字稿"}"#.utf8),
                status: 200,
                headers: ["content-type": "application/json"]
            )
        )
        let runtime = RokuricsAIRuntime(http: http)
        let recordingStore = MacRecordingFileStore(rootURL: root)
        try await saveRecording(id: "ai-pipeline", store: recordingStore)

        let transcription = TranscriptionCoordinator(
            configurationStore: configurationStore,
            runtime: runtime,
            recordingFileStore: recordingStore,
            transcriptStore: TranscriptStore(rootURL: root)
        )
        transcription.startTranscription(recordingID: "ai-pipeline")
        try await waitUntil { !transcription.isTranscribing(recordingID: "ai-pipeline") }

        let transcribed = try #require(
            recordingStore.loadInboxItems().first(where: { $0.id == "ai-pipeline" })
        )
        #expect(transcribed.transcriptionStatus == "transcribed")
        #expect(transcribed.transcriptMarkdownRelativePath != nil)

        let summary = NoteGenerationCoordinator(
            configurationStore: configurationStore,
            runtime: runtime,
            recordingFileStore: recordingStore,
            noteStore: NoteStore(rootURL: root),
            transcriptLoader: NoteGenerationTranscriptLoader()
        )
        summary.startNoteGeneration(recordingID: "ai-pipeline")
        try await waitUntil { !summary.isGenerating(recordingID: "ai-pipeline") }

        let summarized = try #require(
            recordingStore.loadInboxItems().first(where: { $0.id == "ai-pipeline" })
        )
        let notePath = try #require(summarized.noteRelativePath)
        let note = try String(contentsOf: root.appendingPathComponent(notePath), encoding: .utf8)
        #expect(summarized.noteStatus == "generated")
        #expect(note.contains("持久化总结"))
    }

    private func route(model: String) -> RokuricsAIResolvedRoute {
        RokuricsAIResolvedRoute(
            providerID: "openai",
            providerDisplayName: "OpenAI",
            adapter: .openAICompatible,
            baseURL: URL(string: "https://example.test/v1")!,
            chatEndpoint: URL(string: "https://example.test/v1/chat/completions")!,
            modelID: model,
            requestOptions: [:],
            apiKey: "test-secret"
        )
    }

    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-ai-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func saveRecording(id: String, store: MacRecordingFileStore) async throws {
        let audio = Data("recording-audio".utf8)
        let device = PairedDevice(
            id: "source-device",
            deviceName: "iPhone",
            sharedSecretBase64URL: "c2VjcmV0",
            pairedAt: Date(timeIntervalSince1970: 1),
            lastSeenAt: nil,
            userConnectionIntent: .wantsConnected
        )
        let metadata = IncomingRecordingMetadata(
            id: id,
            title: "课堂",
            originalFileName: "\(id).m4a",
            relativeAudioPath: "audio.m4a",
            createdAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_060),
            duration: 60,
            format: "m4a",
            codec: "aac",
            sampleRate: 44_100,
            channels: 1,
            bitrate: 96_000,
            fileSize: Int64(audio.count),
            uploadStatus: "received",
            transcriptionStatus: "notStarted",
            noteStatus: "notGenerated",
            tags: [],
            sourceDeviceName: "iPhone",
            sourceDeviceID: device.id,
            uploadedAt: Date(timeIntervalSince1970: 1_060)
        )
        _ = try store.saveMetadata(metadata, sourceDevice: device)
        _ = try await store.saveAudio(
            body: audio,
            recordingID: id,
            requestedFileName: "\(id).m4a",
            sourceDevice: device
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw RokuricsAIRuntimeError.requestTimedOut
    }
}

private actor CapturingAIHTTPClient: RokuricsAIHTTPClient {
    private let dataResponse: RokuricsAIHTTPResponse?
    private let uploadResponse: RokuricsAIHTTPResponse?
    private var dataRequest: URLRequest?
    private var uploadCapture: (request: URLRequest, body: Data)?

    init(
        dataResponse: RokuricsAIHTTPResponse?,
        uploadResponse: RokuricsAIHTTPResponse?
    ) {
        self.dataResponse = dataResponse
        self.uploadResponse = uploadResponse
    }

    func data(for request: URLRequest) async throws -> RokuricsAIHTTPResponse {
        dataRequest = request
        guard let dataResponse else {
            throw RokuricsAIRuntimeError.invalidResponse
        }
        return dataResponse
    }

    func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> RokuricsAIHTTPResponse {
        uploadCapture = (request, try Data(contentsOf: fileURL))
        guard let uploadResponse else {
            throw RokuricsAIRuntimeError.invalidResponse
        }
        return uploadResponse
    }

    func lastDataRequest() -> URLRequest? { dataRequest }
    func lastUpload() -> (request: URLRequest, body: Data)? { uploadCapture }
}
