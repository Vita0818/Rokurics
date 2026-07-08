//
//  MacRecordingSessionView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/7/7.
//

import SwiftUI

struct MacRecordingSessionView: View {
    @ObservedObject var recordingManager: MacRecordingManager
    let onDismiss: () -> Void

    @State private var didRequestStart = false

    var body: some View {
        RokuricsSharedRecordingSessionSurface(
            elapsedSeconds: recordingManager.elapsedSeconds,
            isPaused: recordingManager.phase.isPaused,
            errorMessage: recordingManager.phase == .failed ? recordingManager.lastErrorMessage : nil,
            transcriptText: recordingManager.liveTranscriptText,
            pauseButtonTitle: pauseButtonTitle,
            pauseButtonSystemImage: pauseButtonSystemImage,
            canPauseOrResume: canPauseOrResume,
            canStop: canStop,
            backAction: onDismiss,
            pauseResumeAction: togglePause,
            stopAction: recordingManager.stopRecording
        )
        .onAppear {
            startIfNeeded()
        }
        .onChange(of: recordingManager.phase) { _, newPhase in
            if newPhase == .saved {
                onDismiss()
            }
        }
    }

    private var pauseButtonTitle: String {
        recordingManager.phase == .paused ? RokuricsCopy.text("继续", "Resume") : RokuricsCopy.text("暂停", "Pause")
    }

    private var pauseButtonSystemImage: String {
        recordingManager.phase == .paused ? "play.fill" : "pause.fill"
    }

    private var canPauseOrResume: Bool {
        recordingManager.phase == .recording || recordingManager.phase == .paused
    }

    private var canStop: Bool {
        recordingManager.phase == .recording || recordingManager.phase == .paused
    }

    private func startIfNeeded() {
        guard !didRequestStart else {
            return
        }

        didRequestStart = true

        switch recordingManager.phase {
        case .recording, .paused, .preparing, .stopping, .saving:
            return
        case .idle, .filing, .saved, .permissionDenied, .failed:
            recordingManager.startRecording()
        }
    }

    private func togglePause() {
        switch recordingManager.phase {
        case .recording:
            recordingManager.pauseRecording()
        case .paused:
            recordingManager.resumeRecording()
        case .idle, .preparing, .stopping, .filing, .saving, .saved, .permissionDenied, .failed:
            break
        }
    }
}

#Preview {
    MacRecordingSessionView(recordingManager: MacRecordingManager(), onDismiss: {})
}
