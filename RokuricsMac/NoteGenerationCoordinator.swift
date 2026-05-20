//
//  NoteGenerationCoordinator.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Combine
import Foundation

@MainActor
final class NoteGenerationCoordinator: ObservableObject {
    @Published private(set) var activeTaskRecordingIDs: Set<String> = []
    @Published private(set) var lastErrorMessage: String?

    private let providerOverride: (any NoteGenerationProvider)?
    private let settingsStore: NoteGenerationSettingsStore
    private let openAIClient: OpenAICompatibleNoteGenerationClient
    private let anthropicClient: AnthropicMessagesNoteGenerationClient
    private let recordingFileStore: MacRecordingFileStore
    private let noteStore: NoteStore
    private let transcriptLoader: NoteGenerationTranscriptLoader
    private var settingsCancellable: AnyCancellable?

    init(
        provider: (any NoteGenerationProvider)? = nil,
        settingsStore: NoteGenerationSettingsStore? = nil,
        openAIClient: OpenAICompatibleNoteGenerationClient? = nil,
        anthropicClient: AnthropicMessagesNoteGenerationClient? = nil,
        recordingFileStore: MacRecordingFileStore? = nil,
        noteStore: NoteStore? = nil,
        transcriptLoader: NoteGenerationTranscriptLoader? = nil
    ) {
        self.providerOverride = provider
        self.settingsStore = settingsStore ?? .shared
        self.openAIClient = openAIClient ?? OpenAICompatibleNoteGenerationClient()
        self.anthropicClient = anthropicClient ?? AnthropicMessagesNoteGenerationClient()
        self.recordingFileStore = recordingFileStore ?? MacRecordingFileStore()
        self.noteStore = noteStore ?? NoteStore()
        self.transcriptLoader = transcriptLoader ?? NoteGenerationTranscriptLoader()

        settingsCancellable = self.settingsStore.objectWillChange.sink { [weak self] _ in
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

        return settingsStore.currentProviderID
    }

    var activeTaskCount: Int {
        activeTaskRecordingIDs.count
    }

    func isGenerating(recordingID: String) -> Bool {
        activeTaskRecordingIDs.contains(recordingID)
    }

    func startNoteGeneration(recordingID: String) {
        guard !activeTaskRecordingIDs.contains(recordingID) else {
            return
        }

        activeTaskRecordingIDs.insert(recordingID)
        lastErrorMessage = nil

        Task { [weak self] in
            await self?.runNoteGeneration(recordingID: recordingID)
        }
    }

    private func runNoteGeneration(recordingID: String) async {
        var failureProviderID = providerID
        var failureModelName: String?
        var failureEndpointDescription: String?
        var failureMode: ProcessingMode?
        var failureSections: [RecordingNoteSectionRecord]?

        defer {
            activeTaskRecordingIDs.remove(recordingID)
        }

        do {
            let provider = currentProvider()
            failureProviderID = provider.id
            if settingsStore.selectedProviderKind == .openAICompatible {
                failureModelName = settingsStore.openAIConfiguration.trimmedModelName
                failureEndpointDescription = settingsStore.openAIConfiguration.endpointDescription
            } else if settingsStore.selectedProviderKind == .anthropicMessages {
                failureModelName = settingsStore.anthropicConfiguration.trimmedModelName
                failureEndpointDescription = settingsStore.anthropicConfiguration.endpointDescription
            }

            try updateNoteStatus(
                recordingID: recordingID,
                status: "generating",
                noteRelativePath: nil,
                generatedAt: nil,
                providerID: provider.id,
                modelName: failureModelName,
                endpointDescription: failureEndpointDescription,
                errorMessage: nil,
                stage: "mark generating"
            )

            try await provider.validateConfiguration()
            let source = try recordingFileStore.noteGenerationSource(for: recordingID)
            guard source.transcriptionStatus == "transcribed" else {
                throw NoteGenerationError.transcriptNotReady
            }

            let loadedTranscript = try transcriptLoader.load(source: source)
            let taskID = UUID().uuidString.lowercased()
            debugLogPreparedSource(taskID: taskID, source: source, loadedTranscript: loadedTranscript)

            let request = NoteGenerationRequest(
                taskID: taskID,
                recordingID: source.recordingID,
                sanitizedRecordingID: source.sanitizedRecordingID,
                title: source.title,
                createdAt: source.createdAt,
                duration: source.duration,
                transcriptRelativePath: source.transcriptRelativePath,
                transcriptMarkdownRelativePath: source.transcriptMarkdownRelativePath,
                transcriptionProviderID: source.transcriptionProviderID,
                transcriptionModelName: source.transcriptionModelName,
                transcriptResult: loadedTranscript.transcriptResult,
                transcriptMarkdown: loadedTranscript.transcriptMarkdown,
                requestedAt: Date()
            )

            let transcriptText = loadedTranscript.transcriptMarkdown ?? loadedTranscript.transcriptResult?.text ?? ""
            let notePlan = LongNoteGenerationPlanner.plan(transcript: transcriptText)
            var sectionRecords = notePlan.chunks.map { RecordingNoteSectionRecord(chunk: $0) }
            failureMode = notePlan.mode
            failureSections = notePlan.shouldUseChunking ? sectionRecords : nil

            try updateNoteStatus(
                recordingID: recordingID,
                status: "generating",
                noteRelativePath: nil,
                generatedAt: nil,
                providerID: provider.id,
                modelName: failureModelName,
                endpointDescription: failureEndpointDescription,
                errorMessage: nil,
                mode: notePlan.mode,
                sections: notePlan.shouldUseChunking ? sectionRecords : nil,
                stage: "mark note plan"
            )

            let result: NoteGenerationResult
            if notePlan.shouldUseChunking {
                let output: ChunkedNoteGenerationOutput
                do {
                    output = try await ChunkedNoteGenerationRunner(
                        provider: provider,
                        noteStore: noteStore
                    ).generate(request: request, plan: notePlan)
                } catch let error as ChunkedNoteGenerationFailure {
                    failureSections = error.sectionRecords
                    throw error
                }
                result = output.result
                sectionRecords = output.sectionRecords
                failureSections = sectionRecords
            } else {
                result = try await provider.generateNote(request: request)
            }

            let saveResult = try saveNote(result: result, request: request)

            try updateNoteStatus(
                recordingID: recordingID,
                status: "generated",
                noteRelativePath: saveResult.noteRelativePath,
                generatedAt: result.completedAt,
                providerID: result.providerID,
                modelName: result.modelName,
                endpointDescription: failureEndpointDescription,
                errorMessage: nil,
                mode: notePlan.mode,
                sections: notePlan.shouldUseChunking ? sectionRecords : nil,
                stage: "mark generated"
            )
        } catch {
            let failureMessage = error.localizedDescription
            lastErrorMessage = failureMessage
            do {
                try updateNoteStatus(
                    recordingID: recordingID,
                    status: "failed",
                    noteRelativePath: nil,
                    generatedAt: nil,
                    providerID: failureProviderID,
                    modelName: failureModelName,
                    endpointDescription: failureEndpointDescription,
                    errorMessage: failureMessage,
                    mode: failureMode,
                    sections: failureSections,
                    stage: "mark failed"
                )
            } catch {
                lastErrorMessage = "\(failureMessage)\n\(error.localizedDescription)"
                debugLogFailureStatusWriteFailed(recordingID: recordingID, originalError: failureMessage, updateError: error)
            }
        }
    }

    private func currentProvider() -> any NoteGenerationProvider {
        if let providerOverride {
            return providerOverride
        }

        switch settingsStore.selectedProviderKind {
        case .mock:
            return MockNoteGenerationProvider()
        case .openAICompatible:
            return OpenAICompatibleNoteGenerationProvider(
                configuration: settingsStore.openAIConfiguration,
                client: openAIClient
            )
        case .anthropicMessages:
            return AnthropicMessagesNoteGenerationProvider(
                configuration: settingsStore.anthropicConfiguration,
                client: anthropicClient
            )
        }
    }

    private func saveNote(
        result: NoteGenerationResult,
        request: NoteGenerationRequest
    ) throws -> NoteStoreSaveResult {
        do {
            debugLogNoteStoreWrite(request: request)
            return try noteStore.save(result: result, request: request)
        } catch {
            throw NoteGenerationError.noteStoreWriteFailed(
                "note store writing 失败：\n" +
                "stage=note store writing\n" +
                "recordingID=\(request.recordingID)\n" +
                "error=\(error.localizedDescription)"
            )
        }
    }

    private func updateNoteStatus(
        recordingID: String,
        status: String,
        noteRelativePath: String?,
        generatedAt: Date?,
        providerID: String?,
        modelName: String?,
        endpointDescription: String?,
        errorMessage: String?,
        mode: ProcessingMode? = nil,
        sections: [RecordingNoteSectionRecord]? = nil,
        stage: String
    ) throws {
        debugLogReceiveStatusUpdate(
            recordingID: recordingID,
            status: status,
            stage: stage,
            errorMessage: errorMessage
        )

        do {
            try recordingFileStore.updateNoteGenerationStatus(
                recordingID: recordingID,
                status: status,
                noteRelativePath: noteRelativePath,
                generatedAt: generatedAt,
                providerID: providerID,
                modelName: modelName,
                endpointDescription: endpointDescription,
                errorMessage: errorMessage,
                mode: mode,
                sections: sections
            )
            debugLogReceiveStatusUpdateSucceeded(recordingID: recordingID, status: status, stage: stage)
        } catch {
            throw NoteGenerationError.receiveJSONUpdateFailed(
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
        source: MacRecordingNoteGenerationSource,
        loadedTranscript: LoadedNoteTranscript
    ) {
        #if DEBUG
        print(
            "[Rokurics][NoteGenerationCoordinator] preparedSource: " +
            "taskID=\(taskID), " +
            "recordingID=\(source.recordingID), " +
            "transcriptJSON=\(source.transcriptURL?.path ?? "nil"), " +
            "transcriptMarkdown=\(source.transcriptMarkdownURL?.path ?? "nil"), " +
            "markdownCharacters=\(loadedTranscript.transcriptMarkdown?.count ?? 0), " +
            "structuredSegments=\(loadedTranscript.transcriptResult?.segments.count ?? 0)"
        )
        #endif
    }

    private func debugLogNoteStoreWrite(request: NoteGenerationRequest) {
        #if DEBUG
        print(
            "[Rokurics][NoteGenerationCoordinator] noteStore.write: " +
            "taskID=\(request.taskID), " +
            "recordingID=\(request.recordingID)"
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
            "[Rokurics][NoteGenerationCoordinator] receive.update: " +
            "stage=\(stage), " +
            "recordingID=\(recordingID), " +
            "noteStatus=\(status), " +
            "errorSummary=\(errorSummary)"
        )
        #endif
    }

    private func debugLogReceiveStatusUpdateSucceeded(recordingID: String, status: String, stage: String) {
        #if DEBUG
        print(
            "[Rokurics][NoteGenerationCoordinator] receive.update.succeeded: " +
            "stage=\(stage), " +
            "recordingID=\(recordingID), " +
            "noteStatus=\(status)"
        )
        #endif
    }

    private func debugLogFailureStatusWriteFailed(recordingID: String, originalError: String, updateError: Error) {
        #if DEBUG
        print(
            "[Rokurics][NoteGenerationCoordinator] receive.update.failed: " +
            "recordingID=\(recordingID), " +
            "originalError=\(String(originalError.prefix(1000))), " +
            "updateError=\(updateError.localizedDescription)"
        )
        #endif
    }
}
