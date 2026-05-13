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

        defer {
            activeTaskRecordingIDs.remove(recordingID)
        }

        do {
            let provider = try currentProvider()
            failureProviderID = provider.id

            try recordingFileStore.updateTranscriptionStatus(
                recordingID: recordingID,
                status: "queued",
                transcriptRelativePath: nil,
                transcriptMarkdownRelativePath: nil,
                providerID: provider.id,
                modelName: nil,
                startedAt: nil,
                completedAt: nil,
                errorMessage: nil
            )

            try await provider.validateConfiguration()
            let source = try recordingFileStore.transcriptionSource(for: recordingID)
            let outputDirectory = try transcriptStore.outputDirectory(recordingID: recordingID, createdAt: source.createdAt)
            let taskID = UUID().uuidString.lowercased()
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

            try recordingFileStore.updateTranscriptionStatus(
                recordingID: recordingID,
                status: "transcribing",
                transcriptRelativePath: nil,
                transcriptMarkdownRelativePath: nil,
                providerID: provider.id,
                modelName: nil,
                startedAt: startedAt,
                completedAt: nil,
                errorMessage: nil
            )

            let result = try await provider.transcribe(request: request)
            let saveResult = try transcriptStore.save(result: result, request: request, recordingTitle: source.title)

            try recordingFileStore.updateTranscriptionStatus(
                recordingID: recordingID,
                status: result.status,
                transcriptRelativePath: saveResult.transcriptRelativePath,
                transcriptMarkdownRelativePath: saveResult.transcriptMarkdownRelativePath,
                providerID: result.providerID,
                modelName: result.modelName,
                startedAt: result.startedAt,
                completedAt: result.completedAt,
                errorMessage: nil
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            try? recordingFileStore.updateTranscriptionStatus(
                recordingID: recordingID,
                status: "failed",
                transcriptRelativePath: nil,
                transcriptMarkdownRelativePath: nil,
                providerID: failureProviderID,
                modelName: nil,
                startedAt: nil,
                completedAt: Date(),
                errorMessage: error.localizedDescription
            )
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
            return WhisperCppTranscriptionProvider(configuration: settingsStore.whisperConfiguration)
        case .mlxWhisper, .localHTTP, .cloudAPI, .customCommand:
            throw TranscriptionError.unsupportedProvider(settingsStore.selectedProviderDisplayName)
        }
    }
}
