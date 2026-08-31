import Combine
import Foundation

@MainActor
final class TranscriptionCoordinator: ObservableObject {
    @Published private(set) var activeTaskRecordingIDs: Set<String> = []
    @Published private(set) var lastErrorMessage: String?

    private let configurationStore: RokuricsAIConfigurationStore
    private let runtime: RokuricsAIRuntime
    private let recordingFileStore: MacRecordingFileStore
    private let transcriptStore: TranscriptStore
    private var tasks: [String: Task<Void, Never>] = [:]

    convenience init() {
        self.init(
            configurationStore: .shared,
            runtime: RokuricsAIRuntime(),
            recordingFileStore: MacRecordingFileStore(),
            transcriptStore: TranscriptStore()
        )
    }

    init(
        configurationStore: RokuricsAIConfigurationStore,
        runtime: RokuricsAIRuntime,
        recordingFileStore: MacRecordingFileStore,
        transcriptStore: TranscriptStore
    ) {
        self.configurationStore = configurationStore
        self.runtime = runtime
        self.recordingFileStore = recordingFileStore
        self.transcriptStore = transcriptStore
    }

    deinit {
        for task in tasks.values { task.cancel() }
    }

    var providerDisplayName: String {
        guard let reference = configurationStore.catalog.transcriptionModel,
              let provider = configurationStore.catalog.providers.first(where: { $0.id == reference.providerID }) else {
            return RokuricsCopy.text("未配置", "Not configured")
        }
        return provider.title
    }

    var providerID: String {
        configurationStore.catalog.transcriptionModel?.providerID ?? "unconfigured"
    }

    var activeTaskCount: Int { activeTaskRecordingIDs.count }

    func isTranscribing(recordingID: String) -> Bool {
        activeTaskRecordingIDs.contains(recordingID)
    }

    func startTranscription(recordingID: String) {
        guard tasks[recordingID] == nil else { return }
        configurationStore.reload()
        activeTaskRecordingIDs.insert(recordingID)
        lastErrorMessage = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runTranscription(recordingID: recordingID)
        }
        tasks[recordingID] = task
    }

    func cancelTranscription(recordingID: String) {
        tasks[recordingID]?.cancel()
    }

    func shutdown() async {
        let running = Array(tasks.values)
        for task in running { task.cancel() }
        for task in running { await task.value }
    }

    private func runTranscription(recordingID: String) async {
        var failureProviderID = providerID
        var failureModelName: String?
        var failureStartedAt: Date?

        defer {
            tasks[recordingID] = nil
            activeTaskRecordingIDs.remove(recordingID)
        }

        do {
            let route = try configurationStore.transcriptionRoute()
            failureProviderID = route.providerID
            failureModelName = route.modelID
            try updateStatus(
                recordingID: recordingID,
                status: "queued",
                transcriptRelativePath: nil,
                transcriptMarkdownRelativePath: nil,
                providerID: route.providerID,
                modelName: route.modelID,
                startedAt: nil,
                completedAt: nil,
                errorMessage: nil
            )

            let source = try recordingFileStore.transcriptionSource(for: recordingID)
            let sourceVersion = try await Self.sourceVersion(fileURL: source.audioFileURL)
            let outputDirectory = try transcriptStore.outputDirectory(
                recordingID: recordingID,
                createdAt: source.createdAt
            )
            let taskID = UUID().uuidString.lowercased()
            let startedAt = Date()
            failureStartedAt = startedAt
            try updateStatus(
                recordingID: recordingID,
                status: "transcribing",
                transcriptRelativePath: nil,
                transcriptMarkdownRelativePath: nil,
                providerID: route.providerID,
                modelName: route.modelID,
                startedAt: startedAt,
                completedAt: nil,
                errorMessage: nil
            )

            let text = try await runtime.transcribeFile(at: source.audioFileURL, route: route)
            try Task.checkCancellation()
            guard try await Self.sourceVersion(fileURL: source.audioFileURL) == sourceVersion else {
                throw RokuricsAIRuntimeError.sourceChanged
            }

            let completedAt = Date()
            let result = TranscriptionResult(
                taskID: taskID,
                recordingID: recordingID,
                providerID: route.providerID,
                providerName: route.providerDisplayName,
                modelName: route.modelID,
                language: nil,
                text: text,
                segments: [],
                startedAt: startedAt,
                completedAt: completedAt,
                status: "transcribed"
            )
            let request = TranscriptionRequest(
                taskID: taskID,
                recordingID: recordingID,
                audioFileURL: source.audioFileURL,
                metadataFileURL: source.metadataFileURL,
                language: nil,
                prompt: nil,
                outputDirectory: outputDirectory,
                createdAt: startedAt,
                sourceDuration: source.duration
            )
            let saved = try transcriptStore.save(
                result: result,
                request: request,
                recordingTitle: source.title
            )
            try updateStatus(
                recordingID: recordingID,
                status: "transcribed",
                transcriptRelativePath: saved.transcriptRelativePath,
                transcriptMarkdownRelativePath: saved.transcriptMarkdownRelativePath,
                providerID: route.providerID,
                modelName: route.modelID,
                startedAt: startedAt,
                completedAt: completedAt,
                errorMessage: nil
            )
        } catch {
            let message = error is CancellationError
                ? RokuricsCopy.text("转写已取消", "Transcription cancelled")
                : error.localizedDescription
            lastErrorMessage = message
            do {
                try updateStatus(
                    recordingID: recordingID,
                    status: "failed",
                    transcriptRelativePath: nil,
                    transcriptMarkdownRelativePath: nil,
                    providerID: failureProviderID,
                    modelName: failureModelName,
                    startedAt: failureStartedAt,
                    completedAt: Date(),
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
        transcriptRelativePath: String?,
        transcriptMarkdownRelativePath: String?,
        providerID: String?,
        modelName: String?,
        startedAt: Date?,
        completedAt: Date?,
        errorMessage: String?
    ) throws {
        try recordingFileStore.updateTranscriptionStatus(
            recordingID: recordingID,
            status: status,
            transcriptRelativePath: transcriptRelativePath,
            transcriptMarkdownRelativePath: transcriptMarkdownRelativePath,
            providerID: providerID,
            modelName: modelName,
            startedAt: startedAt,
            completedAt: completedAt,
            errorMessage: errorMessage,
            mode: .single,
            chunks: nil
        )
    }

    private struct SourceVersion: Equatable, Sendable {
        let byteSize: Int64
        let sha256: String
    }

    private static func sourceVersion(fileURL: URL) async throws -> SourceVersion {
        try await Task.detached(priority: .utility) {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard size >= 0 else { throw RokuricsAIRuntimeError.audioFileUnavailable }
            return SourceVersion(
                byteSize: size,
                sha256: try MacSecurityUtilities.sha256Hex(fileURL: fileURL).lowercased()
            )
        }.value
    }
}
