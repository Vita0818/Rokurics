//
//  SharedLiveTranscriptionModels.swift
//  Rokurics
//
//  Created by Codex on 2026/7/7.
//

import Foundation

enum RokuricsLiveTranscriptionProviderMetadata {
    static let simulatedProviderID = "shared-live-simulated-asr"
    static let simulatedProviderName = RokuricsCopy.text("本地模拟实时转写", "Local Simulated Realtime ASR")
    static let simulatedModelName = "simulated-live-asr"
}

struct RokuricsLiveTranscriptionSegmentDraft: Identifiable, Equatable {
    let id: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let confidence: Double?
}

struct RokuricsLiveTranscriptionSnapshot: Equatable {
    let providerID: String
    let providerName: String
    let modelName: String
    let startedAt: Date
    let isSimulated: Bool
    var updatedAt: Date
    var text: String
    var segments: [RokuricsLiveTranscriptionSegmentDraft]

    static func empty(startedAt: Date = Date()) -> RokuricsLiveTranscriptionSnapshot {
        RokuricsLiveTranscriptionSnapshot(
            providerID: RokuricsLiveTranscriptionProviderMetadata.simulatedProviderID,
            providerName: RokuricsLiveTranscriptionProviderMetadata.simulatedProviderName,
            modelName: RokuricsLiveTranscriptionProviderMetadata.simulatedModelName,
            startedAt: startedAt,
            isSimulated: true,
            updatedAt: startedAt,
            text: "",
            segments: []
        )
    }
}

@MainActor
final class RokuricsSimulatedLiveTranscriptionSession {
    private var timer: Timer?
    private var snapshot = RokuricsLiveTranscriptionSnapshot.empty()
    private var recordingTitle = ""
    private var deviceName = "Device"
    private var isPaused = false
    private var updateHandler: ((RokuricsLiveTranscriptionSnapshot) -> Void)?

    var currentSnapshot: RokuricsLiveTranscriptionSnapshot {
        snapshot
    }

    func start(
        recordingTitle: String,
        deviceName: String,
        onUpdate: @escaping (RokuricsLiveTranscriptionSnapshot) -> Void
    ) {
        stopTimer()
        self.recordingTitle = recordingTitle
        self.deviceName = deviceName
        isPaused = false
        updateHandler = onUpdate
        snapshot = RokuricsLiveTranscriptionSnapshot.empty()
        appendSegment(
            elapsedSeconds: 0,
            text: RokuricsCopy.text(
                "模拟实时转写：\(deviceName) 已开始接收麦克风音频流。",
                "Simulated realtime transcript: \(deviceName) started receiving microphone audio."
            )
        )

        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.appendNextSegment()
            }
        }
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func stop(elapsedSeconds: TimeInterval) -> RokuricsLiveTranscriptionSnapshot {
        stopTimer()
        isPaused = false
        if snapshot.segments.count == 1 {
            appendSegment(
                elapsedSeconds: max(1, elapsedSeconds),
                text: RokuricsCopy.text(
                    "模拟实时转写：录音结束，增量文本已进入本地转写链路。",
                    "Simulated realtime transcript: recording ended and incremental text entered the local transcript path."
                )
            )
        }
        snapshot.updatedAt = Date()
        updateHandler?(snapshot)
        return snapshot
    }

    func cancel() {
        stopTimer()
        updateHandler = nil
        recordingTitle = ""
        deviceName = "Device"
        isPaused = false
        snapshot = RokuricsLiveTranscriptionSnapshot.empty()
    }

    private func appendNextSegment() {
        guard !isPaused else {
            return
        }

        let elapsed = Date().timeIntervalSince(snapshot.startedAt)
        let nextIndex = snapshot.segments.count
        appendSegment(elapsedSeconds: elapsed, text: simulatedLine(for: nextIndex, elapsedSeconds: elapsed))
    }

    private func appendSegment(elapsedSeconds: TimeInterval, text: String) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return
        }

        let endTime = max(0.5, elapsedSeconds)
        let startTime = snapshot.segments.last?.endTime ?? max(0, endTime - 4)
        let segment = RokuricsLiveTranscriptionSegmentDraft(
            id: "live-segment-\(snapshot.segments.count + 1)",
            startTime: startTime,
            endTime: endTime,
            text: normalizedText,
            confidence: 0.72
        )
        snapshot.segments.append(segment)
        snapshot.updatedAt = Date()
        snapshot.text = snapshot.segments.map(\.text).joined(separator: "\n")
        updateHandler?(snapshot)
    }

    private func simulatedLine(for index: Int, elapsedSeconds: TimeInterval) -> String {
        let title = recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = title.isEmpty ? RokuricsCopy.text("这段录音", "this recording") : title
        let clock = RokuricsSharedRecordingTimeFormat.clock(elapsedSeconds)
        let templates = [
            RokuricsCopy.text(
                "\(clock) 实时片段：正在把 \(displayTitle) 的音频 chunk 送入转写流。",
                "\(clock) live segment: sending an audio chunk from \(displayTitle) into the transcription stream."
            ),
            RokuricsCopy.text(
                "\(clock) 实时片段：转写文本持续刷新，\(deviceName) 会保持录音链路可见。",
                "\(clock) live segment: transcript text keeps updating while \(deviceName) keeps the recording path visible."
            ),
            RokuricsCopy.text(
                "\(clock) 实时片段：当前默认是模拟 provider，后续可切换到 OpenAI Realtime 或 FunASR streaming。",
                "\(clock) live segment: the default provider is simulated; it can later switch to OpenAI Realtime or FunASR streaming."
            )
        ]

        return templates[index % templates.count]
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
