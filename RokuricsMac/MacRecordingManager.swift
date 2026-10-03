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
    @Published private(set) var latestHandoffFileName: String?

    private struct PendingHandoff {
        let temporaryAudioURL: URL
        let displayFileName: String
    }

    private let handoffWriter: KuzioAudioHandoffWriter
    private let fileManager: FileManager
    private var recorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private var activeRecordingID: String?
    private var activeRecordingTitle: String?
    private var activeRecordingURL: URL?
    private var recordingStartedAt: Date?
    private var pendingHandoff: PendingHandoff?

    init(
        handoffWriter: KuzioAudioHandoffWriter = KuzioAudioHandoffWriter(),
        fileManager: FileManager = .default
    ) {
        self.handoffWriter = handoffWriter
        self.fileManager = fileManager
    }

    deinit {
        recordingTimer?.invalidate()
    }

    var isRecording: Bool {
        phase == .recording
    }

    var hasPendingHandoff: Bool {
        pendingHandoff != nil
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

        if pendingHandoff != nil {
            retryHandoff()
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
              let title = activeRecordingTitle,
              let audioURL = activeRecordingURL else {
            return
        }

        phase = .stopping
        statusMessage = RokuricsCopy.text("正在结束录音", "Stopping recording")
        refreshElapsed()
        stopTimer()
        recorder.stop()

        self.recorder = nil

        Task { [weak self] in
            await self?.persistFinishedRecording(
                title: title,
                temporaryAudioURL: audioURL
            )
        }
    }

    func retryHandoff() {
        guard !phase.isBusy, let pendingHandoff else {
            return
        }
        markHandoffInProgress()
        Task { [weak self] in
            await self?.deliverToKuzio(pendingHandoff)
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
        title: String,
        temporaryAudioURL: URL
    ) async {
        let displayFileName = title.lowercased().hasSuffix(".m4a")
            ? title
            : "\(title).m4a"
        let pendingHandoff = PendingHandoff(
            temporaryAudioURL: temporaryAudioURL,
            displayFileName: displayFileName
        )
        self.pendingHandoff = pendingHandoff
        markHandoffInProgress()
        await deliverToKuzio(pendingHandoff)
    }

    private func markHandoffInProgress() {
        phase = .saving
        statusMessage = RokuricsCopy.text("正在交给 Kuzio", "Handing recording to Kuzio")
        lastErrorMessage = nil
    }

    private func deliverToKuzio(_ pendingHandoff: PendingHandoff) async {
        do {
            let receipt = try await handoffWriter.handoffAudio(
                at: pendingHandoff.temporaryAudioURL,
                displayFileName: pendingHandoff.displayFileName
            )
            latestHandoffFileName = receipt.displayFileName
            self.pendingHandoff = nil
            phase = .saved
            statusMessage = RokuricsCopy.text("录音已交给 Kuzio", "Recording handed to Kuzio")
            // The handoff contract copies into the shared queue. Rokurics does
            // not mutate or delete the source recording as part of delivery.
            cleanupActiveRecorder(removeActiveFile: false)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? RokuricsCopy.text("无法将录音交给 Kuzio，请重试。", "Could not hand the recording to Kuzio. Please retry.")
            phase = .failed
            statusMessage = message
            lastErrorMessage = message
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
        pendingHandoff = nil
        cleanupActiveRecorder(removeActiveFile: true)
        phase = .failed
        statusMessage = reason
        lastErrorMessage = errorCode
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
}
