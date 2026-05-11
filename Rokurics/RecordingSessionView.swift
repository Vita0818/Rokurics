//
//  RecordingSessionView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/9.
//

import SwiftUI

struct RecordingSessionView: View {
    @ObservedObject var recordingManager: RecordingManager
    @Environment(\.dismiss) private var dismiss
    @State private var didRequestStart = false
    @State private var recordingTitle = ""
    @State private var isDraftNamingPresented = false

    var body: some View {
        ZStack {
            RecordingSessionBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 18)

                Spacer(minLength: 28)

                VStack(spacing: 18) {
                    Text(RokuricsRecordingFormat.clock(recordingManager.elapsedSeconds))
                        .font(RokuricsTypography.largeNumber(size: 78, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(RokuricsColors.deepText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .rokuricsPausedBlinking(recordingManager.state.isPaused)

                    if let errorMessage = recordingManager.lastErrorMessage, recordingManager.state == .failed {
                        Text(errorMessage)
                            .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                            .foregroundStyle(RokuricsColors.coral)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .padding(.horizontal, 18)
                .rokuricsLiquidGlassCard(cornerRadius: 34, fillOpacity: 0.36, strokeOpacity: 0.42, shadowOpacity: 0.12, shadowRadius: 24, shadowY: 14)

                Spacer(minLength: 30)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        RecordingSessionControlButton(
                            title: pauseButtonTitle,
                            systemImage: pauseButtonImageName,
                            tint: RokuricsColors.softTeal,
                            isEnabled: canPauseOrResume,
                            action: togglePause
                        )

                        RecordingSessionControlButton(
                            title: "停止",
                            systemImage: "stop.fill",
                            tint: RokuricsColors.coral,
                            isEnabled: canStop,
                            action: stopAndDismiss
                        )

                        RecordingSessionControlButton(
                            title: "上传",
                            systemImage: "arrow.up.circle.fill",
                            tint: RokuricsColors.tertiaryText,
                            isEnabled: false,
                            action: {}
                        )
                    }

                    Text("Mac 传输稍后支持")
                        .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                        .foregroundStyle(RokuricsColors.tertiaryText)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 22)

            if isNamingOverlayPresented {
                RecordingNamingOverlay(
                    title: $recordingTitle,
                    defaultTitle: recordingManager.suggestedRecordingTitle,
                    saveAction: saveNamingOverlay,
                    skipAction: skipNamingOverlay
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(10)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            startIfNeeded()
        }
        .onChange(of: recordingManager.state) { _, newState in
            if newState == .naming {
                recordingTitle = recordingManager.pendingTitle ?? ""
                isDraftNamingPresented = false
            }
        }
        .onDisappear {
            if recordingManager.state == .naming {
                recordingManager.finalizeRecording(title: nil)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: dismissToHome) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(RokuricsColors.deepText)
                    .frame(width: 44, height: 44)
                    .rokuricsGlassCircle(fillOpacity: 0.38, strokeOpacity: 0.42, shadowOpacity: 0.10, shadowRadius: 10, shadowY: 5)
            }
            .buttonStyle(RokuricsScaleButtonStyle())
            .accessibilityLabel("返回首页")

            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
                .onTapGesture(perform: openDraftNaming)
                .accessibilityHidden(true)
        }
    }

    private var isNamingOverlayPresented: Bool {
        recordingManager.state == .naming || isDraftNamingPresented
    }

    private var pauseButtonTitle: String {
        recordingManager.state == .paused ? "继续" : "暂停"
    }

    private var pauseButtonImageName: String {
        recordingManager.state == .paused ? "play.fill" : "pause.fill"
    }

    private var canPauseOrResume: Bool {
        recordingManager.state == .recording || recordingManager.state == .paused
    }

    private var canStop: Bool {
        recordingManager.state == .recording || recordingManager.state == .paused
    }

    private func startIfNeeded() {
        guard !didRequestStart else {
            return
        }

        didRequestStart = true

        switch recordingManager.state {
        case .recording, .paused, .requestingPermission, .configuringSession, .stopping, .naming, .saving:
            return
        case .idle, .saved, .permissionDenied, .failed:
            recordingManager.startRecording()
        }
    }

    private func togglePause() {
        switch recordingManager.state {
        case .recording:
            recordingManager.pauseRecording()
        case .paused:
            recordingManager.resumeRecording()
        default:
            break
        }
    }

    private func stopAndDismiss() {
        recordingManager.stopRecording()

        if recordingManager.state == .saved {
            dismiss()
        }
    }

    private func dismissToHome() {
        if recordingManager.state == .naming {
            finalizeAndDismiss(title: nil)
            return
        }

        dismiss()
    }

    private func finalizeAndDismiss(title: String?) {
        recordingManager.finalizeRecording(title: title)

        if recordingManager.state == .saved {
            dismiss()
        }
    }

    private func openDraftNaming() {
        guard recordingManager.state == .recording || recordingManager.state == .paused else {
            return
        }

        recordingTitle = recordingManager.pendingTitle ?? ""

        withAnimation(.easeInOut(duration: 0.18)) {
            isDraftNamingPresented = true
        }
    }

    private func saveNamingOverlay() {
        if recordingManager.state == .naming {
            finalizeAndDismiss(title: recordingTitle)
            return
        }

        recordingManager.updatePendingTitle(recordingTitle)

        withAnimation(.easeInOut(duration: 0.16)) {
            isDraftNamingPresented = false
        }
    }

    private func skipNamingOverlay() {
        if recordingManager.state == .naming {
            finalizeAndDismiss(title: nil)
            return
        }

        recordingTitle = recordingManager.pendingTitle ?? ""

        withAnimation(.easeInOut(duration: 0.16)) {
            isDraftNamingPresented = false
        }
    }
}

private struct RecordingNamingOverlay: View {
    @Binding var title: String
    let defaultTitle: String
    let saveAction: () -> Void
    let skipAction: () -> Void
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            Color.white.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 16) {
                TextField(defaultTitle, text: $title)
                    .font(RokuricsTypography.body(size: 16, weight: .semibold))
                    .foregroundStyle(RokuricsColors.deepText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .focused($isTextFieldFocused)
                    .onSubmit(saveAction)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(RokuricsColors.glassSurface.opacity(0.52))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(RokuricsColors.glassStroke.opacity(0.42), lineWidth: 1)
                            }
                    )

                HStack(spacing: 12) {
                    Button(action: skipAction) {
                        Text("跳过")
                            .font(RokuricsTypography.button(size: 15))
                            .foregroundStyle(RokuricsColors.softText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(RokuricsScaleButtonStyle())
                    .rokuricsGlassCapsule(fillOpacity: 0.30, strokeOpacity: 0.32, shadowOpacity: 0.04)

                    Button(action: saveAction) {
                        Text("保存")
                            .font(RokuricsTypography.button(size: 15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(RokuricsScaleButtonStyle())
                    .background(RokuricsColors.actionGradient, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    }
                    .shadow(color: RokuricsColors.shadow.opacity(0.16), radius: 14, y: 8)
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .rokuricsLiquidGlassCard(cornerRadius: 30, fillOpacity: 0.52, strokeOpacity: 0.50, shadowOpacity: 0.16, shadowRadius: 26, shadowY: 14)
            .padding(.horizontal, 24)
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

private struct RecordingSessionControlButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))

                Text(title)
                    .font(RokuricsTypography.caption(size: 13, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? tint : RokuricsColors.tertiaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .rokuricsLiquidGlassCard(cornerRadius: 24, fillOpacity: isEnabled ? 0.38 : 0.24, strokeOpacity: 0.34, shadowOpacity: isEnabled ? 0.08 : 0.03, shadowRadius: 12, shadowY: 6)
            .opacity(isEnabled ? 1 : 0.58)
        }
        .buttonStyle(RokuricsScaleButtonStyle())
        .disabled(!isEnabled)
    }
}

private struct RecordingSessionBackground: View {
    var body: some View {
        ZStack {
            RokuricsColors.pageGradient
                .ignoresSafeArea()

            Circle()
                .fill(RokuricsColors.mint.opacity(0.20))
                .frame(width: 220, height: 220)
                .blur(radius: 0.4)
                .offset(x: -150, y: -250)

            Circle()
                .fill(RokuricsColors.skyCyan.opacity(0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 0.4)
                .offset(x: 150, y: 180)
        }
    }
}

#Preview {
    NavigationStack {
        RecordingSessionView(recordingManager: RecordingManager())
    }
}
