//
//  MacRecordingManager.swift
//  RokuricsMac
//
//  Created by Codex on 2026/7/7.
//

import AVFoundation
import Combine
import Foundation

@MainActor
final class MacRecordingManager: ObservableObject {
    @Published private(set) var phase: RokuricsSharedRecordingOrbPhase = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var statusMessage = RokuricsCopy.text("Mac 本地录音就绪", "Local Mac recorder ready")
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var latestSavedItem: MacRecordingInboxItem?

    private let recordingFileStore: MacRecordingFileStore
    private let fileManager: FileManager
    private var recorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var activeRecordingID: String?
    private var activeRecordingTitle: String?
    private var activeRecordingURL: URL?
    private var recordingStartedAt: Date?

    init(
        recordingFileStore: MacRecordingFileStore = MacRecordingFileStore(),
        fileManager: FileManager = .default
    ) {
        self.recordingFileStore = recordingFileStore
        self.fileManager = fileManager
    }

    deinit {
        recordingTimer?.invalidate()
    }

    var isRecording: Bool {
        phase == .recording
    }

    func toggleRecording() {
        switch phase {
        case .recording:
            stopRecording()
        case .preparing, .stopping, .filing, .saving, .paused:
            return
        case .idle, .saved, .permissionDenied, .failed:
            startRecording()
        }
    }

    func pauseRecording() {
        guard phase == .recording, let recorder else {
            return
        }

        recorder.pause()
        stopTimer()
        elapsedSeconds = recorder.currentTime > 0 ? recorder.currentTime : elapsedSeconds
        phase = .paused
        statusMessage = RokuricsCopy.text("已暂停", "Paused")
    }

    func resumeRecording() {
        guard phase == .paused, let recorder else {
            return
        }

        guard recorder.record() else {
            failRecording(reason: RokuricsCopy.text("继续录音失败", "Failed to resume recording"), errorCode: "mac_recording_resume_failed")
            return
        }

        phase = .recording
        statusMessage = RokuricsCopy.text("正在录音", "Recording")
        startTimer()
    }

    func startRecording() {
        guard !phase.isBusy, phase != .recording else {
            return
        }

        cleanupActiveRecorder(removeActiveFile: true)
        lastErrorMessage = nil
        elapsedSeconds = 0
        phase = .preparing
        statusMessage = RokuricsCopy.text("正在请求麦克风权限", "Requesting microphone access")

        Task { [weak self] in
            await self?.startRecordingAfterPermission()
        }
    }

    func stopRecording() {
        guard (phase == .recording || phase == .paused),
              let recorder,
              let recordingID = activeRecordingID,
              let title = activeRecordingTitle,
              let audioURL = activeRecordingURL,
              let startedAt = recordingStartedAt else {
            return
        }

        phase = .stopping
        statusMessage = RokuricsCopy.text("正在结束录音", "Stopping recording")
        refreshElapsed()
        stopTimer()
        recorder.stop()

        let endedAt = Date()
        let duration = recorder.currentTime > 0 ? recorder.currentTime : max(endedAt.timeIntervalSince(startedAt), elapsedSeconds)
        self.recorder = nil

        Task { [weak self] in
            await self?.persistFinishedRecording(
                recordingID: recordingID,
                title: title,
                temporaryAudioURL: audioURL,
                createdAt: startedAt,
                endedAt: endedAt,
                duration: duration
            )
        }
    }

    private func startRecordingAfterPermission() async {
        let isGranted = await Self.requestMicrophonePermissionIfNeeded()
        guard isGranted else {
            phase = .permissionDenied
            statusMessage = RokuricsCopy.text("需要在系统设置中允许麦克风访问", "Allow microphone access in System Settings")
            lastErrorMessage = "microphone_permission_denied"
            return
        }

        do {
            try startRecorder()
        } catch {
            failRecording(reason: RokuricsCopy.text("录音启动失败", "Failed to start recording"), errorCode: "mac_recording_start_failed")
        }
    }

    private func startRecorder() throws {
        let createdAt = Date()
        let recordingID = "mac-\(UUID().uuidString.lowercased())"
        let title = Self.defaultTitle(createdAt: createdAt)
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("rokurics-\(recordingID).m4a", isDirectory: false)
            .standardizedFileURL

        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }

        let recorder = try AVAudioRecorder(url: temporaryURL, settings: Self.recordingSettings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()
        guard recorder.record() else {
            throw MacRecordingManagerError.recorderDidNotStart
        }

        self.recorder = recorder
        activeRecordingID = recordingID
        activeRecordingTitle = title
        activeRecordingURL = temporaryURL
        recordingStartedAt = createdAt
        elapsedSeconds = 0
        phase = .recording
        statusMessage = RokuricsCopy.text("正在录音", "Recording")
        startTimer()
    }

    private func persistFinishedRecording(
        recordingID: String,
        title: String,
        temporaryAudioURL: URL,
        createdAt: Date,
        endedAt: Date,
        duration: TimeInterval
    ) async {
        phase = .saving
        statusMessage = RokuricsCopy.text("正在保存到学习库", "Saving to library")

        do {
            let fileSize = try fileSize(at: temporaryAudioURL)
            let sourceDevice = Self.localMacSourceDevice()
            let originalFileName = "\(recordingID).m4a"
            let metadata = IncomingRecordingMetadata(
                id: recordingID,
                title: title,
                originalFileName: originalFileName,
                relativeAudioPath: "audio.m4a",
                createdAt: createdAt,
                endedAt: endedAt,
                duration: duration,
                format: "m4a",
                codec: "aac",
                sampleRate: 44_100,
                channels: 1,
                bitrate: 96_000,
                fileSize: fileSize,
                uploadStatus: "localMacRecording",
                transcriptionStatus: "notStarted",
                noteStatus: "notStarted",
                tags: [RokuricsCopy.text("Mac 本地录音", "Mac Local Recording")],
                sourceDeviceName: sourceDevice.deviceName,
                sourceDeviceID: sourceDevice.id,
                uploadedAt: endedAt
            )

            _ = try recordingFileStore.saveMetadata(metadata, sourceDevice: sourceDevice, uploadTraceID: nil)
            let uploadURL = try recordingFileStore.temporaryAudioUploadURL(recordingID: recordingID)
            if fileManager.fileExists(atPath: uploadURL.path) {
                try fileManager.removeItem(at: uploadURL)
            }
            try fileManager.moveItem(at: temporaryAudioURL, to: uploadURL)
            let checksum = try await recordingFileStore.checksumForTemporaryAudioUpload(at: uploadURL, recordingID: recordingID)
            _ = try await recordingFileStore.saveAudio(
                temporaryFileURL: uploadURL,
                recordingID: recordingID,
                requestedFileName: originalFileName,
                sourceDevice: sourceDevice,
                checksum: checksum,
                fileSize: fileSize,
                uploadTraceID: nil
            )

            latestSavedItem = recordingFileStore.loadInboxItems().first { $0.id == recordingID }
            phase = .saved
            statusMessage = RokuricsCopy.text("录音已保存到学习库", "Recording saved to library")
            cleanupActiveRecorder(removeActiveFile: false)
        } catch {
            failRecording(reason: RokuricsCopy.text("录音保存失败", "Failed to save recording"), errorCode: "mac_recording_save_failed")
            if fileManager.fileExists(atPath: temporaryAudioURL.path) {
                try? fileManager.removeItem(at: temporaryAudioURL)
            }
        }
    }

    private func startTimer() {
        stopTimer()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshElapsed()
            }
        }
    }

    private func stopTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func refreshElapsed() {
        guard let recordingStartedAt else {
            elapsedSeconds = 0
            return
        }

        if let recorder, recorder.currentTime > 0 {
            elapsedSeconds = recorder.currentTime
        } else {
            elapsedSeconds = max(0, Date().timeIntervalSince(recordingStartedAt))
        }
        recorder?.updateMeters()
    }

    private func cleanupActiveRecorder(removeActiveFile: Bool) {
        stopTimer()
        recorder?.stop()
        recorder = nil
        if removeActiveFile, let activeRecordingURL, fileManager.fileExists(atPath: activeRecordingURL.path) {
            try? fileManager.removeItem(at: activeRecordingURL)
        }
        activeRecordingID = nil
        activeRecordingTitle = nil
        activeRecordingURL = nil
        recordingStartedAt = nil
    }

    private func failRecording(reason: String, errorCode: String) {
        cleanupActiveRecorder(removeActiveFile: true)
        phase = .failed
        statusMessage = reason
        lastErrorMessage = errorCode
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw MacRecordingManagerError.fileSizeUnavailable
        }
        return fileSize.int64Value
    }

    private static func requestMicrophonePermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func defaultTitle(createdAt: Date) -> String {
        RokuricsCopy.text(
            "Mac 录音 \(titleDateFormatter.string(from: createdAt))",
            "Mac Recording \(titleDateFormatter.string(from: createdAt))"
        )
    }

    private static func localMacSourceDevice() -> PairedDevice {
        let hostName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceName = hostName?.isEmpty == false ? hostName! : "Mac"
        return PairedDevice(
            id: "mac-local-recording",
            deviceName: deviceName,
            sharedSecretBase64URL: "local-mac-recording-source",
            pairedAt: Date(),
            lastSeenAt: Date(),
            userConnectionIntent: .wantsConnected
        )
    }

    private static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 96_000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private enum MacRecordingManagerError: Error {
    case recorderDidNotStart
    case fileSizeUnavailable
}
