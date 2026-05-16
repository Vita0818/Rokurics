//
//  TranscriptionCoordinator.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Combine
import Foundation

@MainActor
final class TranscriptionCoordinator: ObservableObject {
    @Published private(set) var activeTaskRecordingIDs: Set<String> = []
    @Published private(set) var lastErrorMessage: String?

    private let providerOverride: (any TranscriptionProvider)?
    private let settingsStore: TranscriptionSettingsStore
    private let recordingFileStore: MacRecordingFileStore
    private let transcriptStore: TranscriptStore
    private var settingsCancellable: AnyCancellable?

    init(
        provider: (any TranscriptionProvider)? = nil,
        settingsStore: TranscriptionSettingsStore = .shared,
        recordingFileStore: MacRecordingFileStore = MacRecordingFileStore(),
        transcriptStore: TranscriptStore = TranscriptStore()
    ) {
        self.providerOverride = provider
        self.settingsStore = settingsStore
        self.recordingFileStore = recordingFileStore
        self.transcriptStore = transcriptStore

        settingsCancellable = settingsStore.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.objectWillChange.send()
            }
        }
    }

    var providerDisplayName: String {
        if let providerOverride {
            return providerOverride.displayName
        }

        return settingsStore.selectedProviderDisplayName
    }

    var providerID: String {
        if let providerOverride {
            return providerOverride.id
        }

        return settingsStore.selectedProviderKind.rawValue
    }

    var activeTaskCount: Int {
        activeTaskRecordingIDs.count
    }

    func isTranscribing(recordingID: String) -> Bool {
        activeTaskRecordingIDs.contains(recordingID)
    }

    func startTranscription(recordingID: String) {
        guard !activeTaskRecordingIDs.contains(recordingID) else {
            return
        }

        activeTaskRecordingIDs.insert(recordingID)
        lastErrorMessage = nil

        Task { [weak self] in
            await self?.runTranscription(recordingID: recordingID)
        }
    }

    private func runTranscription(recordingID: String) async {
        var failureProviderID = providerID
        var failureStartedAt: Date?
        var failureModelName: String?

        defer {
            activeTaskRecordingIDs.remove(recordingID)
        }

        do {
            let provider = try currentProvider()
            failureProviderID = provider.id

            try updateTranscriptionStatus(
                recordingID: recordingID,
                status: "queued",
                transcriptRelativePath: nil,
                transcriptMarkdownRelativePath: nil,
                providerID: provider.id,
                modelName: nil,
                startedAt: nil,
                completedAt: nil,
                errorMessage: nil,
                stage: "mark queued"
            )

            try await provider.validateConfiguration()
            let source = try recordingFileStore.transcriptionSource(for: recordingID)
            let outputDirectory = try transcriptStore.outputDirectory(recordingID: recordingID, createdAt: source.createdAt)
            let taskID = UUID().uuidString.lowercased()
            debugLogPreparedSource(
                taskID: taskID,
                recordingID: recordingID,
                source: source,
                outputDirectory: outputDirectory
            )
            let request = TranscriptionRequest(
                taskID: taskID,
                recordingID: recordingID,
                audioFileURL: source.audioFileURL,
                metadataFileURL: source.metadataFileURL,
                language: settingsStore.currentLanguage,
                prompt: nil,
                outputDirectory: outputDirectory,
                createdAt: Date()
            )
            let startedAt = Date()
            failureStartedAt = startedAt

            try updateTranscriptionStatus(
                recordingID: recordingID,
                status: "transcribing",
                transcriptRelativePath: nil,
                transcriptMarkdownRelativePath: nil,
                providerID: provider.id,
                modelName: nil,
                startedAt: startedAt,
                completedAt: nil,
                errorMessage: nil,
                stage: "mark transcribing"
            )

            let result = try await provider.transcribe(request: request)
            failureModelName = result.modelName
            let saveResult = try saveTranscript(result: result, request: request, recordingTitle: source.title)

            try updateTranscriptionStatus(
                recordingID: recordingID,
                status: result.status,
                transcriptRelativePath: saveResult.transcriptRelativePath,
                transcriptMarkdownRelativePath: saveResult.transcriptMarkdownRelativePath,
                providerID: result.providerID,
                modelName: result.modelName,
                startedAt: result.startedAt,
                completedAt: result.completedAt,
                errorMessage: nil,
                stage: "mark transcribed"
            )
        } catch {
            let failureMessage = error.localizedDescription
            lastErrorMessage = failureMessage
            do {
                try updateTranscriptionStatus(
                    recordingID: recordingID,
                    status: "failed",
                    transcriptRelativePath: nil,
                    transcriptMarkdownRelativePath: nil,
                    providerID: failureProviderID,
                    modelName: failureModelName,
                    startedAt: failureStartedAt,
                    completedAt: Date(),
                    errorMessage: failureMessage,
                    stage: "mark failed"
                )
            } catch {
                lastErrorMessage = "\(failureMessage)\n\(error.localizedDescription)"
                debugLogFailureStatusWriteFailed(recordingID: recordingID, originalError: failureMessage, updateError: error)
            }
        }
    }

    private func currentProvider() throws -> any TranscriptionProvider {
        if let providerOverride {
            return providerOverride
        }

        switch settingsStore.selectedProviderKind {
        case .mock:
            return MockTranscriptionProvider()
        case .whisperCpp:
            let configuration = settingsStore.reloadedWhisperConfiguration() ?? settingsStore.whisperConfiguration
            debugLogWhisperConfiguration(configuration)
            return WhisperCppTranscriptionProvider(configuration: configuration)
        case .mlxWhisper, .localHTTP, .cloudAPI, .customCommand:
            throw TranscriptionError.unsupportedProvider(settingsStore.selectedProviderDisplayName)
        }
    }

    private func saveTranscript(
        result: TranscriptionResult,
        request: TranscriptionRequest,
        recordingTitle: String
    ) throws -> TranscriptStoreSaveResult {
        do {
            debugLogTranscriptStoreWrite(request: request)
            return try transcriptStore.save(result: result, request: request, recordingTitle: recordingTitle)
        } catch {
            throw TranscriptionError.transcriptStoreWriteFailed(
                "transcript store writing 失败：\n" +
                "stage=transcript store writing\n" +
                "recordingID=\(request.recordingID)\n" +
                "outputDirectory=\(request.outputDirectory.path)\n" +
                "transcriptJson=\(request.outputDirectory.appendingPathComponent("transcript.json").path)\n" +
                "transcriptMarkdown=\(request.outputDirectory.appendingPathComponent("transcript.md").path)\n" +
                "error=\(error.localizedDescription)"
            )
        }
    }

    private func updateTranscriptionStatus(
        recordingID: String,
        status: String,
        transcriptRelativePath: String?,
        transcriptMarkdownRelativePath: String?,
        providerID: String?,
        modelName: String?,
        startedAt: Date?,
        completedAt: Date?,
        errorMessage: String?,
        stage: String
    ) throws {
        debugLogReceiveStatusUpdate(
            recordingID: recordingID,
            status: status,
            stage: stage,
            errorMessage: errorMessage
        )

        do {
            try recordingFileStore.updateTranscriptionStatus(
                recordingID: recordingID,
                status: status,
                transcriptRelativePath: transcriptRelativePath,
                transcriptMarkdownRelativePath: transcriptMarkdownRelativePath,
                providerID: providerID,
                modelName: modelName,
                startedAt: startedAt,
                completedAt: completedAt,
                errorMessage: errorMessage
            )
            debugLogReceiveStatusUpdateSucceeded(recordingID: recordingID, status: status, stage: stage)
        } catch {
            throw TranscriptionError.receiveJSONUpdateFailed(
                "receive.json 写回失败：\n" +
                "stage=\(stage)\n" +
                "recordingID=\(recordingID)\n" +
                "targetStatus=\(status)\n" +
                "error=\(error.localizedDescription)"
            )
        }
    }

    private func debugLogPreparedSource(
        taskID: String,
        recordingID: String,
        source: MacRecordingTranscriptionSource,
        outputDirectory: URL
    ) {
        #if DEBUG
        print(
            "[Rokurics][TranscriptionCoordinator] preparedSource: " +
            "taskID=\(taskID), " +
            "recordingID=\(recordingID), " +
            "audioFile=\(source.audioFileURL.path), " +
            "metadataFile=\(source.metadataFileURL?.path ?? "nil"), " +
            "outputDirectory=\(outputDirectory.path)"
        )
        #endif
    }

    private func debugLogTranscriptStoreWrite(request: TranscriptionRequest) {
        #if DEBUG
        print(
            "[Rokurics][TranscriptionCoordinator] transcriptStore.write: " +
            "taskID=\(request.taskID), " +
            "recordingID=\(request.recordingID), " +
            "outputDirectory=\(request.outputDirectory.path)"
        )
        #endif
    }

    private func debugLogReceiveStatusUpdate(
        recordingID: String,
        status: String,
        stage: String,
        errorMessage: String?
    ) {
        #if DEBUG
        let errorSummary = errorMessage.map { String($0.prefix(1000)) } ?? "nil"
        print(
            "[Rokurics][TranscriptionCoordinator] receive.update: " +
            "stage=\(stage), " +
            "recordingID=\(recordingID), " +
            "status=\(status), " +
            "errorSummary=\(errorSummary)"
        )
        #endif
    }

    private func debugLogReceiveStatusUpdateSucceeded(recordingID: String, status: String, stage: String) {
        #if DEBUG
        print(
            "[Rokurics][TranscriptionCoordinator] receive.update.succeeded: " +
            "stage=\(stage), " +
            "recordingID=\(recordingID), " +
            "status=\(status)"
        )
        #endif
    }

    private func debugLogFailureStatusWriteFailed(recordingID: String, originalError: String, updateError: Error) {
        #if DEBUG
        print(
            "[Rokurics][TranscriptionCoordinator] receive.update.failed: " +
            "recordingID=\(recordingID), " +
            "originalError=\(String(originalError.prefix(1000))), " +
            "updateError=\(updateError.localizedDescription)"
        )
        #endif
    }

    private func debugLogWhisperConfiguration(_ configuration: WhisperCppTranscriptionConfiguration) {
        #if DEBUG
        print(
            "[Rokurics][TranscriptionCoordinator] whisper.configuration: " +
            "ffmpegPath=\(configuration.normalizedFFmpegExecutablePath), " +
            "ffmpegBookmarkBytes=\(configuration.ffmpegExecutableBookmarkData?.count ?? 0), " +
            "ffmpegParentDirectoryBookmarkBytes=\(configuration.ffmpegExecutableParentDirectoryBookmarkData?.count ?? 0), " +
            "whisperBookmarkBytes=\(configuration.executableBookmarkData?.count ?? 0), " +
            "whisperParentDirectoryBookmarkBytes=\(configuration.executableParentDirectoryBookmarkData?.count ?? 0), " +
            "whisperCppRootDirectoryBookmarkBytes=\(configuration.whisperCppRootDirectoryBookmarkData?.count ?? 0), " +
            "modelBookmarkBytes=\(configuration.modelBookmarkData?.count ?? 0)"
        )
        #endif
    }
}
