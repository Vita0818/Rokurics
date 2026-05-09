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
    case stopping
    case saved
    case permissionDenied
    case failed

    var isRecording: Bool {
        self == .recording
    }

    var isBusy: Bool {
        self == .requestingPermission || self == .configuringSession || self == .stopping
    }
}

@MainActor
final class RecordingManager: ObservableObject {
    @Published private(set) var state: RokuricsRecordingState = .idle
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var statusMessage = "录音默认仅保存在本地"
    @Published private(set) var debugMessage: String?

    private let fileStore: AudioFileStore
    private var audioRecorder: AVAudioRecorder?
    private var activeRecordingURL: URL?
    private var recordingStartedAt: Date?
    private var timer: Timer?
    private var activeSettingsName: String?

    init() {
        self.fileStore = AudioFileStore()
    }

    init(fileStore: AudioFileStore) {
        self.fileStore = fileStore
    }

    deinit {
        timer?.invalidate()
    }

    func toggleRecording() {
        log("button tapped. state=\(state)")

        switch state {
        case .recording:
            stopRecording()
        case .requestingPermission, .configuringSession, .stopping:
            log("button ignored while busy. state=\(state)")
        case .idle, .saved, .permissionDenied, .failed:
            startRecording()
        }
    }

    func startRecording() {
        guard !state.isBusy, state != .recording else {
            log("start ignored. state=\(state)")
            return
        }

        cleanupRecorderOnly()
        lastErrorMessage = nil
        elapsedSeconds = 0
        state = .requestingPermission
        statusMessage = "正在请求麦克风权限"
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

    func stopRecording() {
        guard state == .recording else {
            log("stop ignored. state=\(state)")
            return
        }

        state = .stopping
        statusMessage = "正在保存录音"
        stopTimer()

        guard let recorder = audioRecorder else {
            fail("录音保存失败：audioRecorder is nil")
            return
        }

        let finalDuration = max(recorder.currentTime, secondsSinceRecordingStarted())
        log("stopRecording begin. currentTime=\(recorder.currentTime), isRecording=\(recorder.isRecording)")
        recorder.stop()
        audioRecorder = nil
        deactivateAudioSession()

        guard let fileURL = activeRecordingURL else {
            elapsedSeconds = finalDuration
            fail("录音保存失败：missing activeRecordingURL")
            return
        }

        guard fileStore.fileExists(at: fileURL) else {
            elapsedSeconds = finalDuration
            fail("录音文件不存在：\(fileURL.path)")
            return
        }

        elapsedSeconds = finalDuration
        activeRecordingURL = nil
        recordingStartedAt = nil
        lastRecordingURL = fileURL
        lastErrorMessage = nil
        state = .saved
        statusMessage = "已保存 \(fileURL.lastPathComponent)"
        log("saved recording: \(fileURL.path)")
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
        statusMessage = "正在配置录音"

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

            recordingStartedAt = Date()
            elapsedSeconds = 0
            lastErrorMessage = nil
            state = .recording
            statusMessage = "正在录音"
            startTimer()
            log("recording started with \(activeSettingsName ?? "unknown") settings")
        } catch {
            fail("录音启动失败：\(error.localizedDescription)", error: error)
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
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
        let directoryURL = try fileStore.recordingsDirectory()
        log("recordings directory: \(directoryURL.path)")
        log("directory exists: \(fileStore.directoryExists(at: directoryURL))")
        log("directory writable: \(fileStore.isWritableDirectory(at: directoryURL))")
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
        elapsedSeconds = 0
        state = .permissionDenied
        lastErrorMessage = "麦克风权限未开启"
        statusMessage = "麦克风权限未开启"
        errorLog("permission denied")
    }

    private func fail(_ message: String, error: Error? = nil) {
        cleanupRecorderOnly()
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
        if let recorder = audioRecorder, recorder.isRecording {
            recorder.stop()
        }
        audioRecorder = nil
        activeRecordingURL = nil
        recordingStartedAt = nil
        activeSettingsName = nil
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

        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor [weak self] in
                self?.refreshElapsedTime()
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
        elapsedSeconds = max(recorderTime, secondsSinceRecordingStarted())
    }

    private func secondsSinceRecordingStarted() -> TimeInterval {
        guard let recordingStartedAt else {
            return elapsedSeconds
        }

        return max(0, Date().timeIntervalSince(recordingStartedAt))
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
            return "录音文件 URL 无效：\(url.absoluteString)"
        case let .audioSessionConfigurationFailed(error):
            return "AudioSession 配置失败：\(error.localizedDescription)"
        case let .audioSessionActivationFailed(error):
            return "AudioSession 激活失败：\(error.localizedDescription)"
        case let .recorderInitializationFailed(label, error):
            return "\(label) 录音器初始化失败：\(error.localizedDescription)"
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
