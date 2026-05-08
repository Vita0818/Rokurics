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
    case recording
    case stopping
    case saved
    case denied
    case failed

    var isRecording: Bool {
        self == .recording
    }

    var isBusy: Bool {
        self == .requestingPermission || self == .stopping
    }
}

@MainActor
final class RecordingManager: ObservableObject {
    @Published private(set) var state: RokuricsRecordingState = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var statusMessage = "录音默认仅保存在本地"

    private let fileStore: AudioFileStore
    private var recorder: AVAudioRecorder?
    private var activeRecordingURL: URL?
    private var recordingStartDate: Date?
    private var elapsedTask: Task<Void, Never>?

    init() {
        self.fileStore = AudioFileStore()
    }

    init(fileStore: AudioFileStore) {
        self.fileStore = fileStore
    }

    deinit {
        elapsedTask?.cancel()
    }

    func toggleRecording() {
        switch state {
        case .recording:
            stopRecording()
        case .requestingPermission, .stopping:
            return
        case .idle, .saved, .denied, .failed:
            startRecording()
        }
    }

    func startRecording() {
        guard state != .recording else {
            return
        }

        state = .requestingPermission
        statusMessage = "正在请求麦克风权限"

        Task { [weak self] in
            guard let self else {
                return
            }

            let isGranted = await self.requestMicrophonePermission()

            guard isGranted else {
                self.handleDeniedPermission()
                return
            }

            self.beginRecording()
        }
    }

    func stopRecording() {
        guard state == .recording else {
            return
        }

        state = .stopping
        statusMessage = "正在保存录音"
        stopElapsedClock()

        let finalDuration = max(recorder?.currentTime ?? 0, secondsSinceRecordingStarted())
        recorder?.stop()
        recorder = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard let fileURL = activeRecordingURL, fileStore.fileExists(at: fileURL) else {
            activeRecordingURL = nil
            recordingStartDate = nil
            elapsedSeconds = finalDuration
            state = .failed
            statusMessage = "录音保存失败"
            return
        }

        activeRecordingURL = nil
        recordingStartDate = nil
        elapsedSeconds = finalDuration
        lastRecordingURL = fileURL
        state = .saved
        statusMessage = "已保存 \(fileURL.lastPathComponent)"
    }

    private func requestMicrophonePermission() async -> Bool {
        let audioSession = AVAudioSession.sharedInstance()

        switch audioSession.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                audioSession.requestRecordPermission { isGranted in
                    continuation.resume(returning: isGranted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func beginRecording() {
        do {
            let fileURL = try fileStore.makeRecordingURL()
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)

            let recorder = try AVAudioRecorder(url: fileURL, settings: Self.recordingSettings)
            recorder.isMeteringEnabled = false

            guard recorder.prepareToRecord(), recorder.record() else {
                throw RecordingManagerError.couldNotStartRecording
            }

            self.recorder = recorder
            activeRecordingURL = fileURL
            recordingStartDate = Date()
            elapsedSeconds = 0
            state = .recording
            statusMessage = "正在录音"
            startElapsedClock()
        } catch {
            handleFailure(error)
        }
    }

    private func handleDeniedPermission() {
        recorder = nil
        activeRecordingURL = nil
        recordingStartDate = nil
        elapsedSeconds = 0
        state = .denied
        statusMessage = "麦克风权限未开启"
    }

    private func handleFailure(_ error: Error) {
        recorder?.stop()
        recorder = nil
        activeRecordingURL = nil
        recordingStartDate = nil
        stopElapsedClock()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        state = .failed
        statusMessage = error.localizedDescription.isEmpty ? "录音失败" : error.localizedDescription
    }

    private func startElapsedClock() {
        elapsedTask?.cancel()
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    self?.refreshElapsedTime()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopElapsedClock() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    private func refreshElapsedTime() {
        guard state == .recording else {
            return
        }

        elapsedSeconds = max(recorder?.currentTime ?? 0, secondsSinceRecordingStarted())
    }

    private func secondsSinceRecordingStarted() -> TimeInterval {
        guard let recordingStartDate else {
            return elapsedSeconds
        }

        return max(0, Date().timeIntervalSince(recordingStartDate))
    }

    private static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 64_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]
}

private enum RecordingManagerError: LocalizedError {
    case couldNotStartRecording

    var errorDescription: String? {
        switch self {
        case .couldNotStartRecording:
            return "无法开始录音。"
        }
    }
}
