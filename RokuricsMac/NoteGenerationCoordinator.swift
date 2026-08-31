import CryptoKit
import Combine
import Foundation

@MainActor
final class NoteGenerationCoordinator: ObservableObject {
    @Published private(set) var activeTaskRecordingIDs: Set<String> = []
    @Published private(set) var lastErrorMessage: String?

    private let configurationStore: RokuricsAIConfigurationStore
    private let runtime: RokuricsAIRuntime
    private let recordingFileStore: MacRecordingFileStore
    private let noteStore: NoteStore
    private let transcriptLoader: NoteGenerationTranscriptLoader
    private var tasks: [String: Task<Void, Never>] = [:]

    convenience init() {
        self.init(
            configurationStore: .shared,
            runtime: RokuricsAIRuntime(),
            recordingFileStore: MacRecordingFileStore(),
            noteStore: NoteStore(),
            transcriptLoader: NoteGenerationTranscriptLoader()
        )
    }

    init(
        configurationStore: RokuricsAIConfigurationStore,
        runtime: RokuricsAIRuntime,
        recordingFileStore: MacRecordingFileStore,
        noteStore: NoteStore,
        transcriptLoader: NoteGenerationTranscriptLoader
    ) {
        self.configurationStore = configurationStore
        self.runtime = runtime
        self.recordingFileStore = recordingFileStore
        self.noteStore = noteStore
        self.transcriptLoader = transcriptLoader
    }

    deinit {
        for task in tasks.values { task.cancel() }
    }

    var providerDisplayName: String {
        configurationStore.catalog.selectedProvider?.title
            ?? RokuricsCopy.text("未配置", "Not configured")
    }

    var providerID: String {
        configurationStore.catalog.summaryModelReference?.providerID ?? "unconfigured"
    }

    var activeTaskCount: Int { activeTaskRecordingIDs.count }

    func isGenerating(recordingID: String) -> Bool {
        activeTaskRecordingIDs.contains(recordingID)
    }

    func startNoteGeneration(recordingID: String) {
        guard tasks[recordingID] == nil else { return }
        configurationStore.reload()
        activeTaskRecordingIDs.insert(recordingID)
        lastErrorMessage = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runNoteGeneration(recordingID: recordingID)
        }
        tasks[recordingID] = task
    }

    func cancelNoteGeneration(recordingID: String) {
        tasks[recordingID]?.cancel()
    }

    func shutdown() async {
        let running = Array(tasks.values)
        for task in running { task.cancel() }
        for task in running { await task.value }
    }

    private func runNoteGeneration(recordingID: String) async {
        var failureProviderID = providerID
        var failureModelName: String?
        var failureEndpointDescription: String?

        defer {
            tasks[recordingID] = nil
            activeTaskRecordingIDs.remove(recordingID)
        }

        do {
            let route = try configurationStore.summaryRoute()
            failureProviderID = route.providerID
            failureModelName = route.modelID
            failureEndpointDescription = route.baseURL.host
            try updateStatus(
                recordingID: recordingID,
                status: "generating",
                noteRelativePath: nil,
                generatedAt: nil,
                providerID: route.providerID,
                modelName: route.modelID,
                endpointDescription: route.baseURL.host,
                errorMessage: nil
            )

            let source = try recordingFileStore.noteGenerationSource(for: recordingID)
            guard source.transcriptURL != nil || source.transcriptMarkdownURL != nil else {
                throw NoteGenerationError.transcriptNotReady
            }
            let loaded = try transcriptLoader.load(source: source)
            let transcript = Self.transcriptText(loaded)
            guard !transcript.isEmpty else {
                throw NoteGenerationError.transcriptDocumentMissing
            }
            let sourceDigest = Self.digest(transcript)
            let startedAt = Date()
            let markdown = try await runtime.generateSummary(
                input: RokuricsAISummaryInput(
                    recordingTitle: source.title,
                    createdAt: source.createdAt,
                    duration: source.duration,
                    transcript: transcript
                ),
                route: route
            )
            try Task.checkCancellation()
            let currentTranscript = Self.transcriptText(try transcriptLoader.load(source: source))
            guard Self.digest(currentTranscript) == sourceDigest else {
                throw NoteGenerationError.transcriptChangedDuringGeneration
            }

            let completedAt = Date()
            let request = NoteGenerationRequest(
                taskID: UUID().uuidString.lowercased(),
                recordingID: source.recordingID,
                sanitizedRecordingID: source.sanitizedRecordingID,
                title: source.title,
                createdAt: source.createdAt,
                duration: source.duration,
                transcriptRelativePath: source.transcriptRelativePath,
                transcriptMarkdownRelativePath: source.transcriptMarkdownRelativePath,
                transcriptionProviderID: source.transcriptionProviderID,
                transcriptionModelName: source.transcriptionModelName,
                transcriptResult: loaded.transcriptResult,
                transcriptMarkdown: loaded.transcriptMarkdown,
                requestedAt: startedAt
            )
            let result = NoteGenerationResult(
                taskID: request.taskID,
                recordingID: recordingID,
                providerID: route.providerID,
                providerName: route.providerDisplayName,
                modelName: route.modelID,
                markdown: markdown,
                startedAt: startedAt,
                completedAt: completedAt,
                status: "generated"
            )
            let saved = try noteStore.save(result: result, request: request)
            try updateStatus(
                recordingID: recordingID,
                status: "generated",
                noteRelativePath: saved.noteRelativePath,
                generatedAt: completedAt,
                providerID: route.providerID,
                modelName: route.modelID,
                endpointDescription: route.baseURL.host,
                errorMessage: nil
            )
        } catch {
            let message = error is CancellationError
                ? RokuricsCopy.text("总结已取消", "Summary cancelled")
                : error.localizedDescription
            lastErrorMessage = message
            do {
                try updateStatus(
                    recordingID: recordingID,
                    status: "failed",
                    noteRelativePath: nil,
                    generatedAt: nil,
                    providerID: failureProviderID,
                    modelName: failureModelName,
                    endpointDescription: failureEndpointDescription,
                    errorMessage: message
                )
            } catch {
                lastErrorMessage = "\(message)\n\(error.localizedDescription)"
            }
        }
    }

    private func updateStatus(
        recordingID: String,
        status: String,
        noteRelativePath: String?,
        generatedAt: Date?,
        providerID: String?,
        modelName: String?,
        endpointDescription: String?,
        errorMessage: String?
    ) throws {
        try recordingFileStore.updateNoteGenerationStatus(
            recordingID: recordingID,
            status: status,
            noteRelativePath: noteRelativePath,
            generatedAt: generatedAt,
            providerID: providerID,
            modelName: modelName,
            endpointDescription: endpointDescription,
            errorMessage: errorMessage,
            mode: .single,
            sections: nil
        )
    }

    private static func transcriptText(_ loaded: LoadedNoteTranscript) -> String {
        let markdown = loaded.transcriptMarkdown?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !markdown.isEmpty { return markdown }
        return loaded.transcriptResult?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func digest(_ text: String) -> String {
        Data(SHA256.hash(data: Data(text.utf8)))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
