//
//  RecordingManager.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import AVFoundation
import Combine
import Foundation

enum RokuricsRecordingState: Equatable {
    case idle
    case requestingPermission
    case configuringSession
    case recording
    case paused
    case stopping
    case filing
    case saving
    case saved
    case permissionDenied
    case failed

    var isRecording: Bool {
        self == .recording
    }

    var isPaused: Bool {
        self == .paused
    }

    var isBusy: Bool {
        self == .requestingPermission || self == .configuringSession || self == .stopping || self == .filing || self == .saving
    }
}

@MainActor
final class RecordingManager: ObservableObject {
    @Published private(set) var state: RokuricsRecordingState = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var recordings: [RecordingMetadata] = []
    @Published private(set) var trashedRecordings: [RecordingMetadata] = []
    @Published private(set) var latestRecordingMetadata: RecordingMetadata?
    @Published private(set) var statusMessage = RokuricsCopy.text("录音默认仅保存在本地", "Recordings stay local by default")
    @Published private(set) var debugMessage: String?
    @Published private(set) var pendingDefaultTitle: String?
    @Published private(set) var pendingTitle: String?
    @Published private(set) var liveTranscriptText = ""
    @Published private(set) var liveTranscriptSnapshot = RokuricsLiveTranscriptionSnapshot.empty()

    private let fileStore: AudioFileStore
    let studyLibraryStore: StudyLibraryStore
    var audioFileStore: AudioFileStore { fileStore }
    private var audioRecorder: AVAudioRecorder?
    private var activeRecordingURL: URL?
    private var recordingStartedAt: Date?
    private var timer: Timer?
    private var activeSettingsName: String?
    private var pendingRecordingSave: PendingRecordingSave?
    private let liveActivityController = RecordingLiveActivityController()
    private let liveTranscriptionSession = RokuricsSimulatedLiveTranscriptionSession()
    private var elapsedRefreshCadence: ElapsedRefreshCadence = .normal
    private var shouldResumeAfterInterruption = false
    private var audioSessionInterruptionObserver: NSObjectProtocol?
    private var mediaServicesResetObserver: NSObjectProtocol?

    init() {
        let fileStore = AudioFileStore()
        self.fileStore = fileStore
        self.studyLibraryStore = StudyLibraryStore(audioFileStore: fileStore)
        loadExistingRecordings(recoverInterruptedUploads: true)
        observeAudioSessionNotifications()
    }

    init(fileStore: AudioFileStore) {
        self.fileStore = fileStore
        self.studyLibraryStore = StudyLibraryStore(audioFileStore: fileStore)
        loadExistingRecordings(recoverInterruptedUploads: true)
        observeAudioSessionNotifications()
    }

    deinit {
        timer?.invalidate()
        if let audioSessionInterruptionObserver {
            NotificationCenter.default.removeObserver(audioSessionInterruptionObserver)
        }
        if let mediaServicesResetObserver {
            NotificationCenter.default.removeObserver(mediaServicesResetObserver)
        }
    }

    func toggleRecording() {
        log("button tapped. state=\(state)")

        switch state {
        case .recording:
            stopRecording()
        case .requestingPermission, .configuringSession, .stopping, .filing, .saving:
            log("button ignored while busy. state=\(state)")
        case .paused:
            resumeRecording()
        case .idle, .saved, .permissionDenied, .failed:
            startRecording()
        }
    }

    func startRecording() {
        guard !state.isBusy, state != .recording, state != .paused else {
            log("start ignored. state=\(state)")
            return
        }

        studyLibraryStore.refresh()
        cleanupRecorderOnly()
        resetLiveTranscriptionState()
        lastErrorMessage = nil
        elapsedSeconds = 0
        state = .requestingPermission
        statusMessage = RokuricsCopy.text("正在请求麦克风权限", "Requesting microphone access")
        log("startRecording begin")

        Task { [weak self] in
            guard let self else {
                return
            }

            let isGranted = await self.requestPermissionIfNeeded()
            guard isGranted else {
                self.permissionDenied()
                return
            }

            self.startRecorderAfterPermission()
        }
    }

    func pauseRecording() {
        guard state == .recording, let recorder = audioRecorder else {
            log("pause ignored. state=\(state)")
            return
        }

        recorder.pause()
        liveTranscriptionSession.pause()
        stopTimer()
        elapsedSeconds = recorder.currentTime > 0 ? recorder.currentTime : elapsedSeconds
        state = .paused
        statusMessage = RokuricsCopy.text("已暂停", "Paused")
        liveActivityController.update(
            title: activeLiveActivityTitle,
            elapsedSeconds: elapsedSeconds,
            isPaused: true,
            isSavingLocally: false,
            force: true
        )
        log("recording paused. currentTime=\(recorder.currentTime)")
    }

    func resumeRecording() {
        guard state == .paused, let recorder = audioRecorder else {
            log("resume ignored. state=\(state)")
            return
        }

        let didResume = recorder.record()
        log("resume record: \(didResume)")
        log("isRecording: \(recorder.isRecording)")

        guard didResume else {
            fail(RokuricsCopy.text("继续录音失败：record() returned false", "Resume failed: record() returned false"))
            return
        }

        guard recorder.isRecording else {
            fail(RokuricsCopy.text("继续录音失败：recorder.isRecording is false", "Resume failed: recorder.isRecording is false"))
            return
        }

        state = .recording
        statusMessage = RokuricsCopy.text("正在录音", "Recording")
        liveTranscriptionSession.resume()
        startTimer()
        liveActivityController.update(
            title: activeLiveActivityTitle,
            elapsedSeconds: elapsedSeconds,
            isPaused: false,
            isSavingLocally: false,
            force: true
        )
    }

    func reloadRecordings() {
        loadExistingRecordings(recoverInterruptedUploads: false)
    }

    var pendingUploadCount: Int {
        recordings.filter { metadata in
            RecordingUploadStatus(rawMetadataValue: metadata.uploadStatus) != .uploaded
        }.count
    }

    var filingCandidates: StudyFilingCandidates {
        studyLibraryStore.filingCandidates
    }

    func updateUploadStatus(recordingID: String, status: RecordingUploadStatus) throws {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            reloadRecordings()
            guard let reloadedIndex = recordings.firstIndex(where: { $0.id == recordingID }) else {
                return
            }

            let updated = recordings[reloadedIndex].updatingUploadStatus(status)
            try fileStore.updateMetadata(updated)
            recordings[reloadedIndex] = updated
            publishRecordingMetadataUpdate(updated)
            publishUploadStatusSyncEvent(status, recordingID: recordingID)
            return
        }

        let updated = recordings[index].updatingUploadStatus(status)
        try fileStore.updateMetadata(updated)
        recordings[index] = updated
        publishRecordingMetadataUpdate(updated)
        publishUploadStatusSyncEvent(status, recordingID: recordingID)
    }

    func updateUploadProgress(
        recordingID: String,
        fraction: Double?,
        confirmedBytes: Int64?,
        totalBytes: Int64?,
        phase: String?,
        description: String?
    ) throws {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            reloadRecordings()
            guard let reloadedIndex = recordings.firstIndex(where: { $0.id == recordingID }) else {
                return
            }

            let updated = recordings[reloadedIndex].updatingUploadProgress(
                fraction: fraction,
                confirmedBytes: confirmedBytes,
                totalBytes: totalBytes,
                phase: phase,
                description: description
            )
            try fileStore.updateMetadata(updated)
            recordings[reloadedIndex] = updated
            publishRecordingMetadataUpdate(updated)
            publishUploadProgressSyncEvent(recordingID: recordingID, phase: phase)
            return
        }

        let updated = recordings[index].updatingUploadProgress(
            fraction: fraction,
            confirmedBytes: confirmedBytes,
            totalBytes: totalBytes,
            phase: phase,
            description: description
        )
        try fileStore.updateMetadata(updated)
        recordings[index] = updated
        publishRecordingMetadataUpdate(updated)
        publishUploadProgressSyncEvent(recordingID: recordingID, phase: phase)
    }

    func renameRecording(recordingID: String, rawTitle: String) throws {
        guard let existing = recordings.first(where: { $0.id == recordingID }) ?? (try? fileStore.loadMetadata(id: recordingID)) else {
            throw AudioFileStoreError.recordingNotFound(recordingID)
        }

        let title = RecordingTitleEditRules.normalizedTitle(rawTitle, fallback: existing.title)
        guard title != existing.title else {
            return
        }

        do {
            let updated = try fileStore.updateTitle(recordingID: recordingID, rawTitle: title)
            try studyLibraryStore.upsertRecordingMetadata(updated, businessMutationAt: Date())
            replaceRecordingInMemory(updated)
            LocalNetworkSyncEventTrigger.post(.recordingMetadataChanged, source: "RecordingManager.renameRecording", recordingID: recordingID)
            lastErrorMessage = nil
            statusMessage = Self.recentRecordingStatusMessage(for: updated, prefix: RokuricsCopy.text("已重命名", "Renamed"))
        } catch {
            lastErrorMessage = RecordingLocalOperationCopy.renameFailure
            throw error
        }
    }

    func deleteRecording(recordingID: String) throws {
        guard let metadata = recordings.first(where: { $0.id == recordingID }) ?? (try? fileStore.loadMetadata(id: recordingID)) else {
            throw AudioFileStoreError.recordingNotFound(recordingID)
        }

        do {
            let trashedMetadata = try fileStore.moveRecordingToTrash(metadata)
            recordings.removeAll { $0.id == recordingID }
            replaceTrashedRecordingInMemory(trashedMetadata)
            studyLibraryStore.refresh()
            refreshLatestRecordingAfterDeletion()
            LocalNetworkSyncEventTrigger.post(.tombstoneConflictChanged, source: "RecordingManager.deleteRecording", recordingID: recordingID)
            lastErrorMessage = nil
            log("moved recording to trash: \(recordingID)")
        } catch {
            lastErrorMessage = RecordingLocalOperationCopy.deleteFailure
            throw error
        }
    }

    func restoreRecording(recordingID: String) throws {
        do {
            let restoredMetadata = try fileStore.restoreRecording(id: recordingID)
            trashedRecordings.removeAll { $0.id == recordingID }
            try studyLibraryStore.upsertRecordingMetadata(
                restoredMetadata,
                businessMutationAt: Date(),
                clearsRecordingTombstone: true
            )
            replaceRecordingInMemory(restoredMetadata)
            latestRecordingMetadata = recordings.first
            LocalNetworkSyncEventTrigger.post(.tombstoneConflictChanged, source: "RecordingManager.restoreRecording", recordingID: recordingID)
            lastErrorMessage = nil
            statusMessage = Self.recentRecordingStatusMessage(for: restoredMetadata, prefix: RokuricsCopy.text("已恢复", "Restored"))
            log("restored recording: \(recordingID)")
        } catch {
            lastErrorMessage = RecordingLocalOperationCopy.restoreFailure
            throw error
        }
    }

    func permanentlyDeleteRecording(recordingID: String) throws {
        do {
            try fileStore.permanentlyDeleteRecording(id: recordingID)
            recordings.removeAll { $0.id == recordingID }
            trashedRecordings.removeAll { $0.id == recordingID }
            studyLibraryStore.refresh()
            refreshLatestRecordingAfterDeletion()
            LocalNetworkSyncEventTrigger.post(.tombstoneConflictChanged, source: "RecordingManager.permanentlyDeleteRecording", recordingID: recordingID)
            lastErrorMessage = nil
            log("permanently deleted recording: \(recordingID)")
        } catch {
            lastErrorMessage = RecordingLocalOperationCopy.deleteFailure
            throw error
        }
    }

    var suggestedRecordingTitle: String {
        pendingDefaultTitle ?? RecordingMetadata.defaultTitle(createdAt: recordingStartedAt ?? Date())
    }

    func updatePendingTitle(_ rawTitle: String?) {
        let trimmedTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedTitle.isEmpty else {
            log("pending title ignored because title is empty")
            return
        }

        pendingTitle = trimmedTitle
        log("pending title updated")
    }

    func setLowPowerElapsedRefreshEnabled(_ isEnabled: Bool) {
        let newCadence: ElapsedRefreshCadence = isEnabled ? .lowPowerMinute : .normal
        guard elapsedRefreshCadence != newCadence else {
            return
        }

        elapsedRefreshCadence = newCadence
        guard state == .recording else {
            return
        }

        refreshElapsedTime()
        startTimer()
    }

    func refreshElapsedNow() {
        refreshElapsedTime()
    }

    func stopRecording() {
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "recordingStopRequested",
            traceID: "recording-\(UUID().uuidString.lowercased())",
            eventResult: "begin",
            uploadStatus: nil
        )
        guard state == .recording || state == .paused else {
            log("stop ignored. state=\(state)")
            return
        }

        state = .stopping
        statusMessage = RokuricsCopy.text("正在停止录音", "Stopping recording")
        stopTimer()

        guard let recorder = audioRecorder else {
            fail(RokuricsCopy.text("录音保存失败：audioRecorder is nil", "Save failed: audioRecorder is nil"))
            return
        }

        let finalDuration = recorder.currentTime > 0 ? recorder.currentTime : max(elapsedSeconds, secondsSinceRecordingStarted())
        let createdAt = recordingStartedAt ?? Date().addingTimeInterval(-finalDuration)
        let endedAt = Date()
        let settingsSummary = recordingSettingsSummary()
        log("stopRecording begin. currentTime=\(recorder.currentTime), isRecording=\(recorder.isRecording)")
        recorder.stop()
        audioRecorder = nil
        liveActivityController.end(
            title: activeLiveActivityTitle,
            elapsedSeconds: finalDuration,
            isSavingLocally: true
        )
        publishLiveTranscription(liveTranscriptionSession.stop(elapsedSeconds: finalDuration))
        deactivateAudioSession()

        guard let fileURL = activeRecordingURL else {
            elapsedSeconds = finalDuration
            fail(RokuricsCopy.text("录音保存失败：missing activeRecordingURL", "Save failed: missing activeRecordingURL"))
            return
        }

        guard fileStore.fileExists(at: fileURL) else {
            elapsedSeconds = finalDuration
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "recordingAudioFileMissing",
                traceID: "recording-\(UUID().uuidString.lowercased())",
                eventResult: "fail",
                reasonCode: "audio_file_missing",
                fileExists: false,
                safeErrorMessage: "active recording file missing"
            )
            fail(RokuricsCopy.text("录音文件不存在：\(fileURL.path)", "Audio file not found: \(fileURL.path)"))
            return
        }

        let defaultTitle = RecordingMetadata.defaultTitle(createdAt: createdAt)
        pendingRecordingSave = PendingRecordingSave(
            fileURL: fileURL,
            createdAt: createdAt,
            endedAt: endedAt,
            duration: finalDuration,
            settings: settingsSummary,
            defaultTitle: defaultTitle
        )
        pendingDefaultTitle = defaultTitle
        elapsedSeconds = finalDuration
        lastRecordingURL = fileURL
        lastErrorMessage = nil
        state = .filing
        statusMessage = RokuricsCopy.text("等待归档", "Waiting for filing")
        log("recording stopped for filing: \(fileURL.path)")
        print("[RokuricsStorage] audio file exists: \(fileStore.fileExists(at: fileURL))")
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "recordingAudioFileCreated",
            traceID: "recording-\(String(fileURL.deletingPathExtension().lastPathComponent.prefix(12)))",
            recordingID: fileURL.deletingPathExtension().lastPathComponent,
            eventResult: "success",
            fileExists: true,
            fileSize: try? fileStore.fileSize(at: fileURL),
            resolvedRelativePathToken: try? fileStore.relativePath(for: fileURL)
        )
    }

    func finalizeRecording(
        title rawTitle: String? = nil,
        studyFiling: StudyFilingPath? = nil,
        directSave: Bool = false
    ) {
        guard let pendingRecordingSave else {
            log("finalize ignored. no pending recording save. state=\(state)")
            return
        }

        state = .saving
        statusMessage = RokuricsCopy.text("正在保存录音", "Saving recording")

        let resolvedFiling = studyFiling?.isEmpty == true ? nil : studyFiling
        let resolvedTitle = RecordingSaveTitleResolver.title(
            defaultTitle: pendingRecordingSave.defaultTitle,
            pendingTitle: rawTitle ?? pendingTitle,
            studyFiling: resolvedFiling,
            directSave: directSave
        )

        do {
            let metadata = try makeMetadata(
                fileURL: pendingRecordingSave.fileURL,
                title: resolvedTitle,
                createdAt: pendingRecordingSave.createdAt,
                endedAt: pendingRecordingSave.endedAt,
                duration: pendingRecordingSave.duration,
                settings: pendingRecordingSave.settings,
                studyFiling: directSave ? nil : resolvedFiling
            )
            try fileStore.saveMetadata(metadata)
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "recordingMetadataWritten",
                traceID: "recording-\(String(metadata.id.prefix(12)))",
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                fileSize: metadata.fileSize,
                resolvedRelativePathToken: metadata.relativeMetadataPath
            )
            let resolvedAudioURL = try fileStore.audioURL(for: metadata)
            let resolvedAudioExists = fileStore.fileExists(at: resolvedAudioURL)
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: resolvedAudioExists ? "recordingAudioFileExists" : "recordingAudioFileMissing",
                traceID: "recording-\(String(metadata.id.prefix(12)))",
                recordingID: metadata.id,
                eventResult: resolvedAudioExists ? "success" : "fail",
                reasonCode: resolvedAudioExists ? nil : "metadata_audio_path_missing",
                uploadStatus: metadata.uploadStatus,
                fileExists: resolvedAudioExists,
                fileSize: resolvedAudioExists ? (try? fileStore.fileSize(at: resolvedAudioURL)) : nil,
                resolvedRelativePathToken: metadata.relativeAudioPath
            )
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "recordingMetadataRelativeAudioPathChecked",
                traceID: "recording-\(String(metadata.id.prefix(12)))",
                recordingID: metadata.id,
                eventResult: resolvedAudioExists ? "success" : "fail",
                uploadStatus: metadata.uploadStatus,
                fileExists: resolvedAudioExists,
                fileSize: metadata.fileSize,
                resolvedRelativePathToken: metadata.relativeAudioPath
            )
            try studyLibraryStore.upsertRecordingMetadata(metadata)
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "recordingReadyForUpload",
                traceID: "recording-\(String(metadata.id.prefix(12)))",
                recordingID: metadata.id,
                eventResult: resolvedAudioExists && metadata.fileSize > 0 ? "success" : "fail",
                reasonCode: resolvedAudioExists && metadata.fileSize > 0 ? nil : "recording_not_upload_ready",
                uploadStatus: metadata.uploadStatus,
                fileExists: resolvedAudioExists,
                fileSize: metadata.fileSize,
                resolvedRelativePathToken: metadata.relativeAudioPath
            )
            recordings = [metadata] + recordings.filter { $0.id != metadata.id }
            trashedRecordings.removeAll { $0.id == metadata.id }
            latestRecordingMetadata = metadata
            elapsedSeconds = metadata.duration
            activeRecordingURL = nil
            recordingStartedAt = nil
            activeSettingsName = nil
            pendingDefaultTitle = nil
            pendingTitle = nil
            self.pendingRecordingSave = nil
            lastRecordingURL = pendingRecordingSave.fileURL
            lastErrorMessage = nil
            state = .saved
            statusMessage = Self.recentRecordingStatusMessage(for: metadata, prefix: RokuricsCopy.text("已保存", "Saved"))
            LocalNetworkSyncEventTrigger.post(.recordingCreated, source: "RecordingManager.finalizeRecording", recordingID: metadata.id)
            log("saved recording: \(pendingRecordingSave.fileURL.path)")
            print("[RokuricsStorage] audio file size: \(metadata.fileSize)")
            print("[RokuricsStorage] saved metadata: \(metadata.relativeMetadataPath)")
        } catch {
            elapsedSeconds = pendingRecordingSave.duration
            lastRecordingURL = pendingRecordingSave.fileURL
            fail(RokuricsCopy.text("录音已保存，但 metadata 写入失败：\(error.localizedDescription)", "Audio saved, but metadata write failed: \(error.localizedDescription)"), error: error)
        }
    }

    func finalizeRecordingDirectSave() {
        finalizeRecording(title: nil, studyFiling: nil, directSave: true)
    }

    func updateStudyFiling(recordingID: String, studyFiling: StudyFilingPath?) throws {
        guard let existing = recordings.first(where: { $0.id == recordingID }) ?? (try? fileStore.loadMetadata(id: recordingID)) else {
            throw AudioFileStoreError.recordingNotFound(recordingID)
        }

        let updated = existing.updatingStudyFiling(studyFiling)
        try fileStore.updateMetadata(updated)
        try studyLibraryStore.updateFiling(for: recordingID, studyFiling: studyFiling)
        replaceRecordingInMemory(updated)
        LocalNetworkSyncEventTrigger.post(.recordingMetadataChanged, source: "RecordingManager.updateStudyFiling", recordingID: recordingID)
    }

    private func requestPermissionIfNeeded() async -> Bool {
        let session = AVAudioSession.sharedInstance()
        let permission = session.recordPermission
        log("permission status: \(Self.permissionDescription(permission))")

        switch permission {
        case .granted:
            log("permission granted: true")
            return true
        case .denied:
            log("permission granted: false")
            return false
        case .undetermined:
            log("requesting permission...")
            let isGranted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
            log("permission granted: \(isGranted)")
            return isGranted
        @unknown default:
            errorLog("permission status: unknown")
            return false
        }
    }

    private func startRecorderAfterPermission() {
        state = .configuringSession
        statusMessage = RokuricsCopy.text("正在配置录音", "Preparing recorder")

        do {
            log("configure session begin")
            try configureAudioSession()

            try logAndValidateRecordingsDirectory()

            let attemptDate = Date()
            let primaryResult = try attemptRecorderStart(
                label: "primary",
                date: attemptDate,
                fallback: false,
                settings: Self.primaryRecordingSettings
            )

            switch primaryResult {
            case .started:
                break
            case .prepareFailed:
                errorLog("primary prepareToRecord returned false; trying fallback")
                cleanupRecorderOnly(removeActiveFile: true)

                let fallbackResult = try attemptRecorderStart(
                    label: "fallback",
                    date: attemptDate,
                    fallback: true,
                    settings: Self.fallbackRecordingSettings
                )

                switch fallbackResult {
                case .started:
                    log("primary recorder prepare failed, fallback succeeded")
                case .prepareFailed:
                    cleanupRecorderOnly(removeActiveFile: true)
                    throw RecordingManagerError.primaryAndFallbackPrepareFailed
                }
            }

            let startedAt = Date()
            recordingStartedAt = startedAt
            elapsedSeconds = 0
            lastErrorMessage = nil
            state = .recording
            statusMessage = RokuricsCopy.text("正在录音", "Recording")
            startTimer()
            liveActivityController.start(title: activeLiveActivityTitle, elapsedSeconds: elapsedSeconds)
            startLiveTranscription(title: RecordingMetadata.defaultTitle(createdAt: startedAt))
            log("recording started with \(activeSettingsName ?? "unknown") settings")
        } catch {
            fail(RokuricsCopy.text("录音启动失败：\(error.localizedDescription)", "Recording start failed: \(error.localizedDescription)"), error: error)
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
            log("setCategory succeeded: \(session.category.rawValue), mode=\(session.mode.rawValue)")
        } catch {
            errorLog("setCategory failed: \(error.localizedDescription)")
            throw RecordingManagerError.audioSessionConfigurationFailed(error)
        }

        do {
            try session.setPreferredSampleRate(44_100.0)
            log("setPreferredSampleRate succeeded")
        } catch {
            log("setPreferredSampleRate failed: \(error.localizedDescription)")
        }

        do {
            try session.setActive(true, options: [])
            log("setActive succeeded")
            logAudioSessionDetails(session)
        } catch {
            errorLog("setActive failed: \(error.localizedDescription)")
            throw RecordingManagerError.audioSessionActivationFailed(error)
        }
    }

    private func logAudioSessionDetails(_ session: AVAudioSession) {
        log("session category: \(session.category.rawValue)")
        log("session mode: \(session.mode.rawValue)")
        log("session sampleRate: \(session.sampleRate)")
        log("session inputNumberOfChannels: \(session.inputNumberOfChannels)")

        let currentInputs = session.currentRoute.inputs.map { "\($0.portType.rawValue):\($0.portName)" }
        let currentOutputs = session.currentRoute.outputs.map { "\($0.portType.rawValue):\($0.portName)" }
        log("currentRoute inputs: \(currentInputs.isEmpty ? "none" : currentInputs.joined(separator: ","))")
        log("currentRoute outputs: \(currentOutputs.isEmpty ? "none" : currentOutputs.joined(separator: ","))")

        if let inputs = session.availableInputs {
            let names = inputs.map { "\($0.portType.rawValue):\($0.portName)" }
            log("availableInputs: \(names.isEmpty ? "none" : names.joined(separator: ","))")
        } else {
            log("availableInputs: nil")
        }
    }

    private func logAndValidateRecordingsDirectory() throws {
        try fileStore.ensureStorageDirectories()
        let directoryURL = try fileStore.recordingsDirectory()
        log("recordings directory: \(directoryURL.path)")
        log("directory exists: \(fileStore.directoryExists(at: directoryURL))")
        log("directory writable: \(fileStore.isWritableDirectory(at: directoryURL))")
    }

    private func loadExistingRecordings(recoverInterruptedUploads: Bool) {
        do {
            try fileStore.ensureStorageDirectories()
            if recoverInterruptedUploads {
                let uploadJobStore = RecordingUploadJobStore(audioFileStore: fileStore)
                let activeRecordingIDs = RecordingUploadCoordinator.activelyOwnedRecordingIDs
                let recoveredJobs = try uploadJobStore.recoverStaleInProgressJobs(
                    now: Date(),
                    excludingRecordingIDs: activeRecordingIDs
                )
                try fileStore.applyRecoveredUploadJobs(recoveredJobs)
                try fileStore.recoverStaleUploadingMetadata(
                    excludingRecordingIDs: activeRecordingIDs
                )
            }
            let loadedRecordings = try fileStore.loadAllMetadata()
            let loadedTrashedRecordings = try fileStore.loadTrashedMetadata()
            recordings = loadedRecordings
            trashedRecordings = loadedTrashedRecordings
            latestRecordingMetadata = loadedRecordings.first
            studyLibraryStore.refresh()

            if let latestRecordingMetadata {
                elapsedSeconds = latestRecordingMetadata.duration
                statusMessage = Self.recentRecordingStatusMessage(for: latestRecordingMetadata, prefix: RokuricsCopy.text("最近录音", "Recent"))
                lastRecordingURL = try? audioURL(for: latestRecordingMetadata)
            }
        } catch {
            lastErrorMessage = RokuricsCopy.text("读取本地录音失败：\(error.localizedDescription)", "Could not read local recordings: \(error.localizedDescription)")
            statusMessage = RokuricsCopy.text("读取本地录音失败", "Could not read recordings")
            print("[RokuricsStorage][ERROR] load recordings failed: \(error.localizedDescription)")
        }
    }

    private func makeMetadata(
        fileURL: URL,
        title: String,
        createdAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        settings: RecordingSettingsSummary,
        studyFiling: StudyFilingPath?
    ) throws -> RecordingMetadata {
        let id = fileURL.deletingPathExtension().lastPathComponent
        let metadataURL = try fileStore.makeMetadataURL(id: id)
        let fileSize = try fileStore.fileSize(at: fileURL)
        let audioRelativePath = try fileStore.relativePath(for: fileURL)
        let metadataRelativePath = try fileStore.relativePath(for: metadataURL)

        print("[RokuricsStorage] audio file exists: \(fileStore.fileExists(at: fileURL))")
        print("[RokuricsStorage] audio file size: \(fileSize)")

        return RecordingMetadata(
            id: id,
            title: title,
            fileName: fileURL.lastPathComponent,
            relativeAudioPath: audioRelativePath,
            relativeMetadataPath: metadataRelativePath,
            createdAt: createdAt,
            endedAt: endedAt,
            duration: duration,
            format: settings.format,
            codec: settings.codec,
            sampleRate: settings.sampleRate,
            channels: settings.channels,
            bitrate: settings.bitrate,
            fileSize: fileSize,
            uploadStatus: "localOnly",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            tags: [],
            studyFiling: studyFiling
        )
    }

    private func audioURL(for metadata: RecordingMetadata) throws -> URL {
        try fileStore.audioURL(for: metadata)
    }

    private func refreshLatestRecordingAfterMetadataUpdate(_ metadata: RecordingMetadata) {
        if latestRecordingMetadata?.id == metadata.id {
            latestRecordingMetadata = metadata
        }
    }

    private func publishRecordingMetadataUpdate(_ metadata: RecordingMetadata) {
        refreshLatestRecordingAfterMetadataUpdate(metadata)
        studyLibraryStore.refresh()
    }

    private func publishUploadStatusSyncEvent(_ status: RecordingUploadStatus, recordingID: String) {
        if status == .uploaded {
            LocalNetworkSyncEventTrigger.postStatusConvergenceRefresh(
                .audioUploadFinalized,
                source: "RecordingManager.updateUploadStatus",
                recordingID: recordingID
            )
        } else if status == .failed {
            LocalNetworkSyncEventTrigger.postStatusConvergenceRefresh(
                .retryStateChanged,
                source: "RecordingManager.updateUploadStatus",
                recordingID: recordingID
            )
        } else {
            LocalNetworkSyncEventTrigger.postStatusConvergenceRefresh(
                .syncStatusRefreshRequested,
                source: "RecordingManager.updateUploadStatus",
                recordingID: recordingID
            )
        }
    }

    private func publishUploadProgressSyncEvent(recordingID: String, phase: String?) {
        let normalizedPhase = phase?.lowercased() ?? ""
        if normalizedPhase.contains("final") || normalizedPhase.contains("complete") {
            LocalNetworkSyncEventTrigger.postStatusConvergenceRefresh(
                .audioUploadFinalized,
                source: "RecordingManager.updateUploadProgress",
                recordingID: recordingID
            )
        } else if normalizedPhase.contains("retry") || normalizedPhase.contains("fail") {
            LocalNetworkSyncEventTrigger.postStatusConvergenceRefresh(
                .retryStateChanged,
                source: "RecordingManager.updateUploadProgress",
                recordingID: recordingID
            )
        } else {
            LocalNetworkSyncEventTrigger.postStatusConvergenceRefresh(
                .syncStatusRefreshRequested,
                source: "RecordingManager.updateUploadProgress",
                recordingID: recordingID
            )
        }
    }

    private func refreshLatestRecordingAfterDeletion() {
        latestRecordingMetadata = recordings.first
        if let latestRecordingMetadata {
            statusMessage = Self.recentRecordingStatusMessage(for: latestRecordingMetadata, prefix: RokuricsCopy.text("最近录音", "Recent"))
            lastRecordingURL = try? audioURL(for: latestRecordingMetadata)
            elapsedSeconds = latestRecordingMetadata.duration
        } else {
            statusMessage = RokuricsCopy.text("录音默认仅保存在本地", "Recordings stay local by default")
            lastRecordingURL = nil
            elapsedSeconds = 0
        }
    }

    private func replaceRecordingInMemory(_ metadata: RecordingMetadata) {
        if let index = recordings.firstIndex(where: { $0.id == metadata.id }) {
            recordings[index] = metadata
        } else {
            recordings.append(metadata)
            recordings.sort { $0.createdAt > $1.createdAt }
        }

        refreshLatestRecordingAfterMetadataUpdate(metadata)
    }

    private func replaceTrashedRecordingInMemory(_ metadata: RecordingMetadata) {
        if let index = trashedRecordings.firstIndex(where: { $0.id == metadata.id }) {
            trashedRecordings[index] = metadata
        } else {
            trashedRecordings.append(metadata)
            trashedRecordings.sort { ($0.deletedAt ?? $0.createdAt) > ($1.deletedAt ?? $1.createdAt) }
        }
    }

    private func recordingSettingsSummary() -> RecordingSettingsSummary {
        activeSettingsName == "fallback" ? .fallback : .primary
    }

    private func attemptRecorderStart(
        label: String,
        date: Date,
        fallback: Bool,
        settings: [String: Any]
    ) throws -> RecorderStartResult {
        let fileURL = try fileStore.makeRecordingURL(date: date, fallback: fallback)
        log("\(label) file URL: \(fileURL.path)")
        log("\(label) fileURL.isFileURL: \(fileURL.isFileURL)")
        guard fileURL.isFileURL else {
            throw RecordingManagerError.invalidFileURL(fileURL)
        }

        if fileStore.fileExists(at: fileURL) {
            log("\(label) existing file found, deleting before recorder attempt")
            try fileStore.removeFileIfExists(at: fileURL)
        }
        log("\(label) file exists before recorder init: \(fileStore.fileExists(at: fileURL))")
        log("\(label) settings: \(settings)")

        let recorder: AVAudioRecorder
        do {
            recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        } catch {
            throw RecordingManagerError.recorderInitializationFailed(label, error)
        }

        audioRecorder = recorder
        activeRecordingURL = fileURL
        activeSettingsName = label
        recorder.isMeteringEnabled = false
        log("\(label) recorder initialized")

        let didPrepare = recorder.prepareToRecord()
        log("\(label) prepareToRecord: \(didPrepare)")
        guard didPrepare else {
            return .prepareFailed
        }

        let didRecord = recorder.record()
        log("\(label) record: \(didRecord)")
        log("isRecording: \(recorder.isRecording)")
        guard didRecord else {
            throw RecordingManagerError.recordReturnedFalse(label)
        }

        guard recorder.isRecording else {
            throw RecordingManagerError.recorderNotRecordingAfterStart(label)
        }

        return .started
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            log("setActive(false) succeeded")
        } catch {
            errorLog("setActive(false) failed: \(error.localizedDescription)")
        }
    }

    private func permissionDenied() {
        cleanupRecorderOnly()
        resetLiveTranscriptionState()
        liveActivityController.end(title: activeLiveActivityTitle, elapsedSeconds: elapsedSeconds)
        pendingRecordingSave = nil
        pendingDefaultTitle = nil
        pendingTitle = nil
        elapsedSeconds = 0
        state = .permissionDenied
        lastErrorMessage = RokuricsCopy.text("麦克风权限未开启", "Microphone access is off")
        statusMessage = RokuricsCopy.text("麦克风权限未开启", "Microphone access is off")
        errorLog("permission denied")
    }

    private func fail(_ message: String, error: Error? = nil) {
        liveActivityController.end(title: activeLiveActivityTitle, elapsedSeconds: elapsedSeconds)
        cleanupRecorderOnly()
        resetLiveTranscriptionState()
        deactivateAudioSession()
        state = .failed
        lastErrorMessage = message
        statusMessage = message

        if let error {
            errorLog("\(message) | \(error.localizedDescription)")
        } else {
            errorLog(message)
        }
    }

    private func cleanupRecorderOnly() {
        stopTimer()
        liveTranscriptionSession.cancel()
        if let recorder = audioRecorder, recorder.isRecording {
            recorder.stop()
        }
        audioRecorder = nil
        activeRecordingURL = nil
        recordingStartedAt = nil
        activeSettingsName = nil
        pendingRecordingSave = nil
        pendingDefaultTitle = nil
        pendingTitle = nil
    }

    private func cleanupRecorderOnly(removeActiveFile: Bool) {
        let fileURL = activeRecordingURL
        cleanupRecorderOnly()

        if removeActiveFile, let fileURL {
            do {
                try fileStore.removeFileIfExists(at: fileURL)
                log("removed failed recorder file: \(fileURL.path)")
            } catch {
                errorLog("failed to remove recorder file: \(error.localizedDescription)")
            }
        }
    }

    private func startTimer() {
        stopTimer()

        let timer = Timer(timeInterval: nextElapsedRefreshInterval(), repeats: elapsedRefreshCadence == .normal) { _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                self.refreshElapsedTime()

                if self.state == .recording && self.elapsedRefreshCadence == .lowPowerMinute {
                    self.startTimer()
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshElapsedTime() {
        guard state == .recording else {
            return
        }

        let recorderTime = audioRecorder?.currentTime ?? 0
        elapsedSeconds = recorderTime > 0 ? recorderTime : max(elapsedSeconds, secondsSinceRecordingStarted())
        liveActivityController.update(
            title: activeLiveActivityTitle,
            elapsedSeconds: elapsedSeconds,
            isPaused: false,
            isSavingLocally: false
        )
    }

    private func startLiveTranscription(title: String) {
        liveTranscriptionSession.start(recordingTitle: title, deviceName: "iPhone") { [weak self] snapshot in
            self?.publishLiveTranscription(snapshot)
        }
    }

    private func publishLiveTranscription(_ snapshot: RokuricsLiveTranscriptionSnapshot) {
        liveTranscriptSnapshot = snapshot
        liveTranscriptText = snapshot.text
    }

    private func resetLiveTranscriptionState() {
        liveTranscriptionSession.cancel()
        liveTranscriptText = ""
        liveTranscriptSnapshot = RokuricsLiveTranscriptionSnapshot.empty()
    }

    private func secondsSinceRecordingStarted() -> TimeInterval {
        guard let recordingStartedAt else {
            return elapsedSeconds
        }

        return max(0, Date().timeIntervalSince(recordingStartedAt))
    }

    private var activeLiveActivityTitle: String {
        let trimmedTitle = (pendingTitle ?? pendingDefaultTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? RokuricsCopy.text("课堂录音", "Class Recording") : trimmedTitle
    }

    private func nextElapsedRefreshInterval() -> TimeInterval {
        switch elapsedRefreshCadence {
        case .normal:
            return 0.25
        case .lowPowerMinute:
            let currentSeconds = audioRecorder?.currentTime ?? max(elapsedSeconds, secondsSinceRecordingStarted())
            let secondsIntoMinute = max(0, currentSeconds).truncatingRemainder(dividingBy: 60)
            return max(0.5, 60 - secondsIntoMinute + 0.05)
        }
    }

    private func observeAudioSessionNotifications() {
        audioSessionInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioSessionInterruption(notification)
            }
        }

        mediaServicesResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        }
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            shouldResumeAfterInterruption = state == .recording
            guard state == .recording else {
                return
            }

            let recorderTime = audioRecorder?.currentTime ?? 0
            elapsedSeconds = recorderTime > 0 ? recorderTime : max(elapsedSeconds, secondsSinceRecordingStarted())
            audioRecorder?.pause()
            liveTranscriptionSession.pause()
            stopTimer()
            state = .paused
            statusMessage = RokuricsCopy.text("已暂停", "Paused")
            liveActivityController.update(
                title: activeLiveActivityTitle,
                elapsedSeconds: elapsedSeconds,
                isPaused: true,
                isSavingLocally: false,
                force: true
            )
            log("audio session interrupted; recording paused")
        case .ended:
            guard shouldResumeAfterInterruption else {
                return
            }

            shouldResumeAfterInterruption = false
            let optionValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionValue)
            guard options.contains(.shouldResume), state == .paused else {
                log("audio session interruption ended without automatic resume")
                return
            }

            resumeRecording()
            log("audio session interruption ended; recording resumed")
        @unknown default:
            break
        }
    }

    private func handleMediaServicesReset() {
        guard state == .recording || state == .paused || state == .configuringSession else {
            return
        }

        fail(RokuricsCopy.text("录音被系统音频服务重置，请重新开始", "Audio service reset. Please start again."))
    }

    private func log(_ message: String) {
        debugMessage = message
        print("[RokuricsRecording] \(message)")
    }

    private func errorLog(_ message: String) {
        debugMessage = message
        print("[RokuricsRecording][ERROR] \(message)")
    }

    private static func permissionDescription(_ permission: AVAudioSession.RecordPermission) -> String {
        switch permission {
        case .undetermined:
            return "undetermined"
        case .denied:
            return "denied"
        case .granted:
            return "granted"
        @unknown default:
            return "unknown"
        }
    }

    private static let primaryRecordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    private static let fallbackRecordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 128_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    private static func recentRecordingStatusMessage(for metadata: RecordingMetadata, prefix: String) -> String {
        RokuricsCopy.usesChinese
            ? "\(prefix)：\(Self.shortTimeFormatter.string(from: metadata.createdAt)) · \(Self.durationText(metadata.duration))"
            : "\(prefix): \(Self.shortTimeFormatter.string(from: metadata.createdAt)) · \(Self.durationText(metadata.duration))"
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(max(0, Int(seconds.rounded(.down)))) sec"
        }

        return String(format: "%.1f min", seconds / 60)
    }

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = RokuricsCopy.displayLocale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct RecordingSettingsSummary {
    let format: String
    let codec: String
    let sampleRate: Double
    let channels: Int
    let bitrate: Int

    static let primary = RecordingSettingsSummary(
        format: "m4a",
        codec: "AAC",
        sampleRate: 16_000.0,
        channels: 1,
        bitrate: 64_000
    )

    static let fallback = RecordingSettingsSummary(
        format: "m4a",
        codec: "AAC",
        sampleRate: 44_100.0,
        channels: 1,
        bitrate: 128_000
    )
}

private struct PendingRecordingSave {
    let fileURL: URL
    let createdAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let settings: RecordingSettingsSummary
    let defaultTitle: String
}

private enum ElapsedRefreshCadence {
    case normal
    case lowPowerMinute
}

private enum RecordingManagerError: LocalizedError {
    case invalidFileURL(URL)
    case audioSessionConfigurationFailed(Error)
    case audioSessionActivationFailed(Error)
    case recorderInitializationFailed(String, Error)
    case primaryAndFallbackPrepareFailed
    case recordReturnedFalse(String)
    case recorderNotRecordingAfterStart(String)

    var errorDescription: String? {
        switch self {
        case let .invalidFileURL(url):
            return RokuricsCopy.text("录音文件 URL 无效：\(url.absoluteString)", "Invalid recording file URL: \(url.absoluteString)")
        case let .audioSessionConfigurationFailed(error):
            return RokuricsCopy.text("AudioSession 配置失败：\(error.localizedDescription)", "AudioSession configuration failed: \(error.localizedDescription)")
        case let .audioSessionActivationFailed(error):
            return RokuricsCopy.text("AudioSession 激活失败：\(error.localizedDescription)", "AudioSession activation failed: \(error.localizedDescription)")
        case let .recorderInitializationFailed(label, error):
            return RokuricsCopy.text("\(label) 录音器初始化失败：\(error.localizedDescription)", "\(label) recorder initialization failed: \(error.localizedDescription)")
        case .primaryAndFallbackPrepareFailed:
            return "primary and fallback prepareToRecord failed"
        case let .recordReturnedFalse(label):
            return "\(label) record() returned false"
        case let .recorderNotRecordingAfterStart(label):
            return "\(label) record() returned true but recorder.isRecording is false"
        }
    }
}

private enum RecorderStartResult {
    case started
    case prepareFailed
}
