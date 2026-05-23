//
//  RecordingUploadCoordinator.swift
//  Rokurics
//
//  Created by Codex on 2026/5/12.
//

import Combine
import Foundation

@MainActor
final class RecordingUploadCoordinator: ObservableObject {
    @Published private(set) var activeStatuses: [String: RecordingUploadStatus] = [:]
    @Published private(set) var errorMessages: [String: String] = [:]

    private let uploadClient: RecordingUploadClient
    private var uploadTasks: [String: Task<Void, Never>] = [:]

    init(uploadClient: RecordingUploadClient? = nil) {
        self.uploadClient = uploadClient ?? RecordingUploadClient()
    }

    func displayStatus(for metadata: RecordingMetadata) -> RecordingUploadStatus {
        activeStatuses[metadata.id] ?? RecordingUploadStatus(rawMetadataValue: metadata.uploadStatus)
    }

    func errorMessage(for metadata: RecordingMetadata) -> String? {
        errorMessages[metadata.id]
    }

    func upload(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        recordingManager: RecordingManager
    ) {
        guard uploadTasks[metadata.id] == nil else {
            return
        }

        uploadTasks[metadata.id] = Task { [weak self, weak recordingManager] in
            guard let self, let recordingManager else {
                return
            }

            _ = await self.uploadAndWait(
                metadata: metadata,
                settings: settings,
                recordingManager: recordingManager
            )
            self.uploadTasks[metadata.id] = nil
        }
    }

    @discardableResult
    func uploadAndWait(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        recordingManager: RecordingManager
    ) async -> RecordingUploadStatus {
        if activeStatuses[metadata.id] == .uploading {
            return .uploading
        }

        guard settings.isPaired else {
            activeStatuses[metadata.id] = .failed
            errorMessages[metadata.id] = RecordingUploadError.notPaired.localizedDescription
            return .failed
        }

        activeStatuses[metadata.id] = .uploading
        errorMessages[metadata.id] = nil

        do {
            try recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploading)
            _ = try await uploadClient.uploadRecording(metadata: metadata.updatingUploadStatus(.uploading), settings: settings)
            try recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploaded)
            activeStatuses[metadata.id] = nil
            errorMessages[metadata.id] = nil
            return .uploaded
        } catch is CancellationError {
            activeStatuses[metadata.id] = nil
            return .localOnly
        } catch {
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            activeStatuses[metadata.id] = .failed
            errorMessages[metadata.id] = error.localizedDescription
            return .failed
        }
    }
}
