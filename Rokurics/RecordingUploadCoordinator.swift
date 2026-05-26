//
//  RecordingUploadCoordinator.swift
//  Rokurics
//
//  Created by Codex on 2026/5/12.
//

import Combine
import Foundation

extension Notification.Name {
    static let recordingUploadJobLedgerDidChange = Notification.Name("RokuricsRecordingUploadJobLedgerDidChange")
}

@MainActor
final class RecordingUploadCoordinator: ObservableObject {
    @Published private(set) var activeStatuses: [String: RecordingUploadStatus] = [:]
    @Published private(set) var errorMessages: [String: String] = [:]

    private let uploadClient: RecordingUploadClientProtocol
    private let jobStore: RecordingUploadJobStore
    private let retryPolicy: RecordingUploadRetryPolicy
    private var uploadTasks: [String: Task<Void, Never>] = [:]

    init(
        uploadClient: RecordingUploadClientProtocol? = nil,
        jobStore: RecordingUploadJobStore? = nil,
        retryPolicy: RecordingUploadRetryPolicy = .standard
    ) {
        self.uploadClient = uploadClient ?? RecordingUploadClient()
        self.jobStore = jobStore ?? RecordingUploadJobStore()
        self.retryPolicy = retryPolicy
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

        if RecordingUploadStatus(rawMetadataValue: metadata.uploadStatus) == .uploaded {
            return .uploaded
        }

        do {
            try jobStore.recoverStaleInProgressJobs(now: Date())
            let existingJob = try jobStore.ensureJob(for: metadata, settings: settings, now: Date())
            if existingJob.overallState == .fatalFailed {
                activeStatuses[metadata.id] = .failed
                errorMessages[metadata.id] = existingJob.lastErrorMessage ?? "上传已失败，需要先处理冲突。"
                try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
                return .failed
            }
        } catch {
            activeStatuses[metadata.id] = .failed
            errorMessages[metadata.id] = "上传任务账本读取失败：\(error.localizedDescription)"
            return .failed
        }

        activeStatuses[metadata.id] = .uploading
        errorMessages[metadata.id] = nil

        do {
            let uploadJob = try jobStore.markAttemptStarted(recordingID: metadata.id, now: Date())
            try recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploading)
            let progress: RecordingUploadProgressHandler = { [weak self] event in
                guard let self else {
                    return
                }

                let updatedJob = try self.jobStore.applyProgress(recordingID: metadata.id, event: event, now: Date())
                if let progressUpdate = Self.metadataProgressUpdate(for: event, job: updatedJob) {
                    try? recordingManager.updateUploadProgress(
                        recordingID: metadata.id,
                        fraction: progressUpdate.fraction,
                        confirmedBytes: progressUpdate.confirmedBytes,
                        totalBytes: progressUpdate.totalBytes,
                        phase: progressUpdate.phase,
                        description: progressUpdate.description
                    )
                }
            }
            let result = try await uploadClient.uploadRecording(
                metadata: metadata.updatingUploadStatus(.uploading),
                settings: settings,
                progress: progress,
                resumeContext: uploadJob.resumeContext
            )
            let completedJob = try jobStore.markSucceeded(recordingID: metadata.id, result: result, now: Date())
            try recordingManager.updateUploadStatus(recordingID: metadata.id, status: .uploaded)
            try? recordingManager.updateUploadProgress(
                recordingID: metadata.id,
                fraction: 1,
                confirmedBytes: completedJob.audioTotalBytes,
                totalBytes: completedJob.audioTotalBytes,
                phase: "completed",
                description: "上传完成"
            )
            activeStatuses[metadata.id] = nil
            errorMessages[metadata.id] = nil
            return .uploaded
        } catch is CancellationError {
            _ = try? jobStore.markRetryableFailure(
                recordingID: metadata.id,
                classification: RecordingUploadFailureClassification(
                    code: "upload_cancelled",
                    message: "上传已中断，可重试。",
                    isFatal: false
                ),
                retryPolicy: retryPolicy,
                now: Date()
            )
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            activeStatuses[metadata.id] = nil
            return .failed
        } catch {
            let classification = RecordingUploadFailureClassification.classify(error)
            _ = try? jobStore.markFailure(
                recordingID: metadata.id,
                classification: classification,
                retryPolicy: retryPolicy,
                now: Date()
            )
            try? recordingManager.updateUploadStatus(recordingID: metadata.id, status: .failed)
            activeStatuses[metadata.id] = .failed
            errorMessages[metadata.id] = error.localizedDescription
            return .failed
        }
    }

    func retryQueue() -> RecordingUploadQueue {
        RecordingUploadQueue(jobStore: jobStore, retryPolicy: retryPolicy)
    }

    private struct MetadataProgressUpdate {
        let fraction: Double?
        let confirmedBytes: Int64?
        let totalBytes: Int64?
        let phase: String?
        let description: String?
    }

    private static func metadataProgressUpdate(
        for event: RecordingUploadProgressEvent,
        job: RecordingUploadJob
    ) -> MetadataProgressUpdate? {
        switch event {
        case .audioResumableSessionStarted:
            return MetadataProgressUpdate(
                fraction: job.currentProgressFraction,
                confirmedBytes: job.audioConfirmedBytes,
                totalBytes: job.audioTotalBytes,
                phase: job.resumableState?.rawValue ?? "uploading",
                description: Self.progressDescription(for: job)
            )
        case .audioResumableProgress:
            return MetadataProgressUpdate(
                fraction: job.currentProgressFraction,
                confirmedBytes: job.audioConfirmedBytes,
                totalBytes: job.audioTotalBytes,
                phase: "uploading",
                description: Self.progressDescription(for: job)
            )
        case .audioResumableFinalizing:
            return MetadataProgressUpdate(
                fraction: job.currentProgressFraction,
                confirmedBytes: job.audioConfirmedBytes,
                totalBytes: job.audioTotalBytes,
                phase: "finalizing",
                description: "正在完成上传"
            )
        case .audioSucceeded:
            return MetadataProgressUpdate(
                fraction: 1,
                confirmedBytes: job.audioTotalBytes,
                totalBytes: job.audioTotalBytes,
                phase: "completed",
                description: "上传完成"
            )
        case .metadataStarted, .metadataSucceeded, .audioStarted:
            return nil
        }
    }

    private static func progressDescription(for job: RecordingUploadJob) -> String? {
        guard let confirmedBytes = job.audioConfirmedBytes,
              let totalBytes = job.audioTotalBytes,
              totalBytes > 0 else {
            return nil
        }

        let percent = Int((Double(confirmedBytes) / Double(totalBytes) * 100).rounded())
        return "上传中 \(min(max(percent, 0), 100))%"
    }
}

enum RecordingUploadJobStageState: String, Codable, Equatable {
    case pending
    case inProgress
    case succeeded
    case failed
}

enum RecordingUploadJobOverallState: String, Codable, Equatable {
    case pending
    case inProgress
    case succeeded
    case retryableFailed
    case fatalFailed
}

enum RecordingUploadJobDisposition: String, Codable, Equatable {
    case none
    case acceptedNew
    case acceptedExisting

    init(serverValue: String?) {
        switch serverValue {
        case "acceptedNew":
            self = .acceptedNew
        case "acceptedExisting":
            self = .acceptedExisting
        default:
            self = .none
        }
    }
}

struct RecordingUploadJob: Codable, Equatable, Identifiable {
    var id: String { recordingID }

    let recordingID: String
    var createdAt: Date
    var updatedAt: Date
    var metadataStage: RecordingUploadJobStageState
    var audioStage: RecordingUploadJobStageState
    var overallState: RecordingUploadJobOverallState
    var metadataDisposition: RecordingUploadJobDisposition
    var audioDisposition: RecordingUploadJobDisposition
    var attemptCount: Int
    var lastAttemptAt: Date?
    var nextRetryAfter: Date?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var isFatal: Bool
    var localMetadataPath: String
    var localAudioPath: String
    var targetDeviceID: String?
    var targetMacName: String?
    var resumableSessionID: String? = nil
    var uploadMode: RecordingUploadMode? = nil
    var audioTotalBytes: Int64? = nil
    var audioConfirmedBytes: Int64? = nil
    var audioChunkSize: Int? = nil
    var audioTotalSHA256: String? = nil
    var audioNextOffset: Int64? = nil
    var audioChunkCount: Int? = nil
    var audioCompletedChunkCount: Int? = nil
    var currentProgressFraction: Double? = nil
    var lastProgressAt: Date? = nil
    var resumableState: RecordingResumableUploadState? = nil
    var lastConfirmedByMacAt: Date? = nil
    var lastSessionStatusError: String? = nil

    var isRetryable: Bool {
        overallState == .retryableFailed && !isFatal
    }

    var resumeContext: RecordingUploadResumeContext {
        RecordingUploadResumeContext(
            metadataStage: metadataStage,
            metadataDisposition: metadataDisposition,
            resumableSessionID: resumableSessionID,
            audioConfirmedBytes: audioConfirmedBytes,
            audioTotalBytes: audioTotalBytes,
            audioChunkSize: audioChunkSize,
            audioTotalSHA256: audioTotalSHA256
        )
    }

    static func make(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        now: Date
    ) -> RecordingUploadJob {
        RecordingUploadJob(
            recordingID: metadata.id,
            createdAt: now,
            updatedAt: now,
            metadataStage: .pending,
            audioStage: .pending,
            overallState: .pending,
            metadataDisposition: .none,
            audioDisposition: .none,
            attemptCount: 0,
            lastAttemptAt: nil,
            nextRetryAfter: nil,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            isFatal: false,
            localMetadataPath: metadata.relativeMetadataPath,
            localAudioPath: metadata.relativeAudioPath,
            targetDeviceID: settings.deviceID,
            targetMacName: settings.macName.isEmpty ? nil : settings.macName
        )
    }
}

struct RecordingUploadJobLedger: Codable, Equatable {
    static let currentVersion = 2

    var version: Int
    var jobs: [RecordingUploadJob]

    static var empty: RecordingUploadJobLedger {
        RecordingUploadJobLedger(version: currentVersion, jobs: [])
    }
}

struct RecordingUploadFailureClassification: Equatable {
    let code: String
    let message: String
    let isFatal: Bool

    static func classify(_ error: Error) -> RecordingUploadFailureClassification {
        if let uploadError = error as? RecordingUploadError {
            switch uploadError {
            case .metadataUploadFailed(let reason):
                return RecordingUploadFailureClassification(
                    code: reason.contains("recording_metadata_conflict") ? "recording_metadata_conflict" : "metadata_upload_failed",
                    message: uploadError.localizedDescription,
                    isFatal: reason.contains("recording_metadata_conflict")
                )
            case .audioUploadFailed(let reason):
                return RecordingUploadFailureClassification(
                    code: reason.contains("recording_audio_conflict") ? "recording_audio_conflict" : "audio_upload_failed",
                    message: uploadError.localizedDescription,
                    isFatal: reason.contains("recording_audio_conflict")
                )
            case .notPaired:
                return RecordingUploadFailureClassification(code: "not_paired", message: uploadError.localizedDescription, isFatal: false)
            case .audioFileMissing:
                return RecordingUploadFailureClassification(code: "audio_file_missing", message: uploadError.localizedDescription, isFatal: true)
            case .fileTooLarge:
                return RecordingUploadFailureClassification(code: "file_too_large", message: uploadError.localizedDescription, isFatal: true)
            case .macRejected(let reason):
                let isFatal = reason.contains("conflict")
                return RecordingUploadFailureClassification(code: isFatal ? reason : "mac_rejected", message: uploadError.localizedDescription, isFatal: isFatal)
            case .networkFailed:
                return RecordingUploadFailureClassification(code: "network_failed", message: uploadError.localizedDescription, isFatal: false)
            }
        }

        let message = error.localizedDescription
        let isMetadataConflict = message.contains("recording_metadata_conflict")
        let isAudioConflict = message.contains("recording_audio_conflict")
        if isMetadataConflict || isAudioConflict {
            return RecordingUploadFailureClassification(
                code: isMetadataConflict ? "recording_metadata_conflict" : "recording_audio_conflict",
                message: message,
                isFatal: true
            )
        }

        return RecordingUploadFailureClassification(code: "temporary_upload_failed", message: message, isFatal: false)
    }
}

struct RecordingUploadRetryPolicy: Equatable {
    nonisolated static let standard = RecordingUploadRetryPolicy(delays: [5, 30, 120], maximumDelay: 600)

    let delays: [TimeInterval]
    let maximumDelay: TimeInterval

    func delay(forAttemptCount attemptCount: Int) -> TimeInterval {
        guard attemptCount > 0 else {
            return 0
        }

        if attemptCount <= delays.count {
            return min(delays[attemptCount - 1], maximumDelay)
        }

        let extraAttempts = attemptCount - delays.count
        let baseDelay = delays.last ?? maximumDelay
        let multiplier = pow(2.0, Double(extraAttempts))
        return min(baseDelay * multiplier, maximumDelay)
    }

    func nextRetryAfter(attemptCount: Int, now: Date) -> Date {
        now.addingTimeInterval(delay(forAttemptCount: attemptCount))
    }
}

final class RecordingUploadJobStore {
    private let audioFileStore: AudioFileStore
    private let fileManager: FileManager
    private(set) var lastReadError: String?

    init(audioFileStore: AudioFileStore = AudioFileStore(), fileManager: FileManager = .default) {
        self.audioFileStore = audioFileStore
        self.fileManager = fileManager
    }

    func ledgerURL() throws -> URL {
        try ledgerDirectory()
            .appendingPathComponent("upload-ledger")
            .appendingPathExtension("json")
            .standardizedFileURL
    }

    func loadJobs() throws -> [RecordingUploadJob] {
        try loadLedger().jobs
    }

    func loadJob(recordingID: String) throws -> RecordingUploadJob? {
        try loadLedger().jobs.first { $0.recordingID == recordingID }
    }

    @discardableResult
    func ensureJob(
        for metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        now: Date
    ) throws -> RecordingUploadJob {
        if let existing = try loadJob(recordingID: metadata.id) {
            return existing
        }

        let job = RecordingUploadJob.make(metadata: metadata, settings: settings, now: now)
        try saveJob(job)
        return job
    }

    func saveJob(_ job: RecordingUploadJob) throws {
        var ledger = try loadLedger()
        ledger.jobs.removeAll { $0.recordingID == job.recordingID }
        ledger.jobs.append(job)
        ledger.jobs.sort { $0.createdAt > $1.createdAt }
        try saveLedger(ledger)
    }

    @discardableResult
    func markAttemptStarted(recordingID: String, now: Date) throws -> RecordingUploadJob {
        try updateJob(recordingID: recordingID) { job in
            job.updatedAt = now
            job.lastAttemptAt = now
            job.nextRetryAfter = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            job.isFatal = false
            job.overallState = .inProgress
            job.attemptCount += 1
            if job.uploadMode == .resumableChunks {
                job.resumableState = job.resumableSessionID == nil ? .starting : .uploading
            }

            if job.metadataStage != .succeeded {
                job.metadataStage = .pending
            }
            if job.audioStage != .succeeded {
                job.audioStage = .pending
            }
        }
    }

    @discardableResult
    func applyProgress(
        recordingID: String,
        event: RecordingUploadProgressEvent,
        now: Date
    ) throws -> RecordingUploadJob {
        try updateJob(recordingID: recordingID) { job in
            job.updatedAt = now
            job.overallState = .inProgress
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            job.nextRetryAfter = nil

            switch event {
            case .metadataStarted:
                if job.metadataStage != .succeeded {
                    job.metadataStage = .inProgress
                }
            case .metadataSucceeded(let disposition):
                job.metadataStage = .succeeded
                job.metadataDisposition = RecordingUploadJobDisposition(serverValue: disposition)
            case .audioStarted:
                job.audioStage = .inProgress
                if job.uploadMode == .resumableChunks {
                    job.resumableState = .uploading
                }
            case .audioResumableSessionStarted(let sessionID, let totalBytes, let chunkSize, let totalSHA256, let confirmedBytes):
                job.uploadMode = .resumableChunks
                job.audioStage = .inProgress
                job.resumableState = .uploading
                job.resumableSessionID = sessionID
                job.audioTotalBytes = totalBytes
                job.audioConfirmedBytes = confirmedBytes
                job.audioChunkSize = chunkSize
                job.audioTotalSHA256 = totalSHA256
                job.audioNextOffset = confirmedBytes
                job.audioChunkCount = Self.chunkCount(totalBytes: totalBytes, chunkSize: chunkSize)
                job.audioCompletedChunkCount = Self.completedChunkCount(confirmedBytes: confirmedBytes, chunkSize: chunkSize)
                job.currentProgressFraction = Self.progressFraction(confirmedBytes: confirmedBytes, totalBytes: totalBytes)
                job.lastProgressAt = now
                job.lastConfirmedByMacAt = now
                job.lastSessionStatusError = nil
            case .audioResumableProgress(let sessionID, let confirmedBytes, let totalBytes, let nextOffset):
                job.uploadMode = .resumableChunks
                job.audioStage = .inProgress
                job.resumableState = .uploading
                job.resumableSessionID = sessionID
                job.audioTotalBytes = totalBytes
                job.audioConfirmedBytes = confirmedBytes
                job.audioNextOffset = nextOffset
                if let chunkSize = job.audioChunkSize {
                    job.audioChunkCount = Self.chunkCount(totalBytes: totalBytes, chunkSize: chunkSize)
                    job.audioCompletedChunkCount = Self.completedChunkCount(confirmedBytes: confirmedBytes, chunkSize: chunkSize)
                }
                job.currentProgressFraction = Self.progressFraction(confirmedBytes: confirmedBytes, totalBytes: totalBytes)
                job.lastProgressAt = now
                job.lastConfirmedByMacAt = now
                job.lastSessionStatusError = nil
            case .audioResumableFinalizing(let sessionID, let confirmedBytes, let totalBytes):
                job.uploadMode = .resumableChunks
                job.audioStage = .inProgress
                job.resumableState = .finalizing
                job.resumableSessionID = sessionID
                job.audioTotalBytes = totalBytes
                job.audioConfirmedBytes = confirmedBytes
                job.audioNextOffset = confirmedBytes
                job.currentProgressFraction = Self.progressFraction(confirmedBytes: confirmedBytes, totalBytes: totalBytes)
                job.lastProgressAt = now
            case .audioSucceeded(let disposition):
                job.audioStage = .succeeded
                job.audioDisposition = RecordingUploadJobDisposition(serverValue: disposition)
                if job.uploadMode == .resumableChunks {
                    job.resumableState = .completed
                    job.currentProgressFraction = 1
                    job.audioConfirmedBytes = job.audioTotalBytes ?? job.audioConfirmedBytes
                    job.audioNextOffset = job.audioTotalBytes ?? job.audioNextOffset
                    job.lastProgressAt = now
                }
            }
        }
    }

    @discardableResult
    func markSucceeded(
        recordingID: String,
        result: RecordingUploadResult,
        now: Date
    ) throws -> RecordingUploadJob {
        try updateJob(recordingID: recordingID) { job in
            job.updatedAt = now
            job.metadataStage = .succeeded
            job.audioStage = .succeeded
            job.overallState = .succeeded
            job.metadataDisposition = RecordingUploadJobDisposition(serverValue: result.metadataDisposition)
            job.audioDisposition = RecordingUploadJobDisposition(serverValue: result.audioDisposition)
            job.nextRetryAfter = nil
            job.lastErrorCode = nil
            job.lastErrorMessage = nil
            job.isFatal = false
            if job.uploadMode == .resumableChunks {
                job.resumableState = .completed
                job.currentProgressFraction = 1
                job.audioConfirmedBytes = job.audioTotalBytes ?? job.audioConfirmedBytes
                job.audioNextOffset = job.audioTotalBytes ?? job.audioNextOffset
                job.lastProgressAt = now
            }
        }
    }

    @discardableResult
    func markRetryableFailure(
        recordingID: String,
        classification: RecordingUploadFailureClassification,
        retryPolicy: RecordingUploadRetryPolicy,
        now: Date
    ) throws -> RecordingUploadJob {
        try markFailure(recordingID: recordingID, classification: classification, retryPolicy: retryPolicy, now: now)
    }

    @discardableResult
    func markFailure(
        recordingID: String,
        classification: RecordingUploadFailureClassification,
        retryPolicy: RecordingUploadRetryPolicy,
        now: Date
    ) throws -> RecordingUploadJob {
        try updateJob(recordingID: recordingID) { job in
            let failingStage = Self.failingStage(for: classification, job: job)
            job.updatedAt = now
            job.overallState = classification.isFatal ? .fatalFailed : .retryableFailed
            job.isFatal = classification.isFatal
            job.nextRetryAfter = classification.isFatal ? nil : retryPolicy.nextRetryAfter(attemptCount: job.attemptCount, now: now)
            job.lastErrorCode = classification.code
            job.lastErrorMessage = classification.message
            if job.uploadMode == .resumableChunks {
                job.resumableState = classification.isFatal ? .fatalFailed : .retryableFailed
                job.lastSessionStatusError = classification.message
            }

            switch failingStage {
            case .metadata:
                job.metadataStage = .failed
            case .audio:
                job.audioStage = .failed
            }
        }
    }

    @discardableResult
    func recoverStaleInProgressJobs(now: Date) throws -> [RecordingUploadJob] {
        var ledger = try loadLedger()
        var recovered: [RecordingUploadJob] = []

        for index in ledger.jobs.indices {
            guard ledger.jobs[index].overallState == .inProgress
                    || ledger.jobs[index].metadataStage == .inProgress
                    || ledger.jobs[index].audioStage == .inProgress else {
                continue
            }

            if ledger.jobs[index].metadataStage == .inProgress {
                ledger.jobs[index].metadataStage = .failed
            }
            if ledger.jobs[index].audioStage == .inProgress {
                ledger.jobs[index].audioStage = .failed
            }
            if ledger.jobs[index].uploadMode == .resumableChunks,
               let resumableState = ledger.jobs[index].resumableState,
               [.starting, .uploading, .finalizing].contains(resumableState) {
                ledger.jobs[index].resumableState = .paused
            }

            ledger.jobs[index].overallState = .retryableFailed
            ledger.jobs[index].isFatal = false
            ledger.jobs[index].updatedAt = now
            ledger.jobs[index].nextRetryAfter = now
            ledger.jobs[index].lastErrorCode = "upload_interrupted"
            ledger.jobs[index].lastErrorMessage = "上次上传中断，可重试。"
            recovered.append(ledger.jobs[index])
        }

        if !recovered.isEmpty {
            try saveLedger(ledger)
        }

        return recovered
    }

    private enum UploadStage {
        case metadata
        case audio
    }

    private static func failingStage(
        for classification: RecordingUploadFailureClassification,
        job: RecordingUploadJob
    ) -> UploadStage {
        if classification.code.contains("metadata") {
            return .metadata
        }

        if classification.code.contains("audio") {
            return .audio
        }

        if job.metadataStage == .succeeded {
            return .audio
        }

        return .metadata
    }

    private static func progressFraction(confirmedBytes: Int64, totalBytes: Int64) -> Double? {
        guard totalBytes > 0 else {
            return nil
        }

        return min(max(Double(confirmedBytes) / Double(totalBytes), 0), 1)
    }

    private static func chunkCount(totalBytes: Int64, chunkSize: Int) -> Int? {
        guard chunkSize > 0 else {
            return nil
        }

        return Int((totalBytes + Int64(chunkSize) - 1) / Int64(chunkSize))
    }

    private static func completedChunkCount(confirmedBytes: Int64, chunkSize: Int) -> Int? {
        guard chunkSize > 0 else {
            return nil
        }

        return Int(confirmedBytes / Int64(chunkSize))
    }

    private func updateJob(
        recordingID: String,
        update: (inout RecordingUploadJob) -> Void
    ) throws -> RecordingUploadJob {
        var ledger = try loadLedger()
        guard let index = ledger.jobs.firstIndex(where: { $0.recordingID == recordingID }) else {
            throw RecordingUploadJobStoreError.jobNotFound(recordingID)
        }

        update(&ledger.jobs[index])
        let updatedJob = ledger.jobs[index]
        try saveLedger(ledger)
        return updatedJob
    }

    private func ledgerDirectory() throws -> URL {
        let directoryURL = try audioFileStore.baseDirectory()
            .appendingPathComponent("UploadJobs", isDirectory: true)
            .standardizedFileURL

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw RecordingUploadJobStoreError.directoryCreationFailed(directoryURL, error)
        }

        return directoryURL
    }

    private func loadLedger() throws -> RecordingUploadJobLedger {
        let url = try ledgerURL()
        guard fileManager.fileExists(atPath: url.path) else {
            lastReadError = nil
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let ledger = try Self.decoder.decode(RecordingUploadJobLedger.self, from: data)
            lastReadError = nil
            return RecordingUploadJobLedger(
                version: ledger.version,
                jobs: deduplicatedJobs(ledger.jobs)
            )
        } catch {
            lastReadError = "upload ledger read failed: \(error.localizedDescription)"
            return .empty
        }
    }

    private func saveLedger(_ ledger: RecordingUploadJobLedger) throws {
        let url = try ledgerURL()
        let directoryURL = url.deletingLastPathComponent()
        let temporaryURL = directoryURL
            .appendingPathComponent(".upload-ledger-\(UUID().uuidString)")
            .appendingPathExtension("tmp")

        let normalizedLedger = RecordingUploadJobLedger(
            version: RecordingUploadJobLedger.currentVersion,
            jobs: deduplicatedJobs(ledger.jobs)
        )
        let data = try Self.encoder.encode(normalizedLedger)

        do {
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw RecordingUploadJobStoreError.ledgerWriteFailed(url, error)
        }
        NotificationCenter.default.post(name: .recordingUploadJobLedgerDidChange, object: nil)
    }

    private func deduplicatedJobs(_ jobs: [RecordingUploadJob]) -> [RecordingUploadJob] {
        var latestByRecordingID: [String: RecordingUploadJob] = [:]
        for job in jobs {
            let existing = latestByRecordingID[job.recordingID]
            if existing == nil || job.updatedAt >= existing!.updatedAt {
                latestByRecordingID[job.recordingID] = job
            }
        }

        return latestByRecordingID.values.sorted { $0.createdAt > $1.createdAt }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

enum RecordingUploadJobStoreError: LocalizedError {
    case directoryCreationFailed(URL, Error)
    case ledgerWriteFailed(URL, Error)
    case jobNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .directoryCreationFailed(url, error):
            return "上传任务目录创建失败：\(url.path) - \(error.localizedDescription)"
        case let .ledgerWriteFailed(url, error):
            return "上传任务账本写入失败：\(url.path) - \(error.localizedDescription)"
        case let .jobNotFound(recordingID):
            return "未找到上传任务：\(recordingID)"
        }
    }
}

struct RecordingUploadQueue {
    let jobStore: RecordingUploadJobStore
    let retryPolicy: RecordingUploadRetryPolicy

    func retryableJobs(now: Date = Date()) throws -> [RecordingUploadJob] {
        try jobStore.loadJobs()
            .filter(\.isRetryable)
            .sorted { ($0.nextRetryAfter ?? .distantPast) < ($1.nextRetryAfter ?? .distantPast) }
    }

    func eligibleRetryableJobs(now: Date = Date()) throws -> [RecordingUploadJob] {
        try retryableJobs(now: now).filter { isEligible($0, now: now) }
    }

    func isEligible(_ job: RecordingUploadJob, now: Date = Date()) -> Bool {
        guard job.isRetryable else {
            return false
        }

        guard let nextRetryAfter = job.nextRetryAfter else {
            return true
        }

        return now >= nextRetryAfter
    }

    func drainEligibleJobs(
        now: Date = Date(),
        perform: (RecordingUploadJob) async -> Void
    ) async throws -> [RecordingUploadJob] {
        let jobs = try eligibleRetryableJobs(now: now)
        for job in jobs {
            await perform(job)
        }
        return jobs
    }
}
