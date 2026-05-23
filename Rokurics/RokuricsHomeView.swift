//
//  RokuricsHomeView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

struct RokuricsHomeView: View {
    @ObservedObject var recordingManager: RecordingManager
    @ObservedObject var macConnectionStore: SecureMacConnectionStore
    @ObservedObject var userProfileStore: UserProfileStore
    @StateObject private var uploadCoordinator = RecordingUploadCoordinator()
    @State private var isRecordingSessionPresented = false
    @State private var isRecordingLibraryPresented = false
    @State private var isAIChatPresented = false
    @State private var isMacConnectionPresented = false
    @State private var isSettingsPresented = false

    var body: some View {
        RokuricsAdaptivePage { metrics in
            ZStack {
                RokuricsHomeBackground(metrics: metrics)

                VStack(spacing: 0) {
                    homeHeader(metrics: metrics)
                        .padding(.top, metrics.homeTopPadding)

                    Spacer(minLength: metrics.isPadWidth ? 34 : 22)

                    RokuricsRecordingOrb(
                        visualScale: metrics.orbScale,
                        state: recordingManager.state,
                        elapsedSeconds: recordingManager.elapsedSeconds,
                        action: openRecordingSession
                    )

                    Spacer(minLength: metrics.isPadWidth ? 32 : 20)

                    RokuricsHomeNavigationCard(
                        scale: metrics.dashboardScale,
                        isMacPaired: macConnectionStore.isPaired,
                        onOpenRecordingLibrary: openRecordingLibrary,
                        onOpenAIChat: openAIChat,
                        onOpenMacConnection: openMacConnection
                    )
                        .padding(.bottom, metrics.homeBottomPadding)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(maxWidth: metrics.homeMaxWidth)
                .frame(maxWidth: .infinity, minHeight: metrics.height, alignment: .top)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $isRecordingSessionPresented) {
            RecordingSessionView(recordingManager: recordingManager)
        }
        .navigationDestination(isPresented: $isRecordingLibraryPresented) {
            RecordingLibraryView(
                recordingManager: recordingManager,
                macConnectionStore: macConnectionStore,
                uploadCoordinator: uploadCoordinator
            )
        }
        .navigationDestination(isPresented: $isAIChatPresented) {
            IPhoneAIChatView(
                studyLibraryStore: recordingManager.studyLibraryStore,
                userProfileStore: userProfileStore
            )
        }
        .navigationDestination(isPresented: $isMacConnectionPresented) {
            MacConnectionView(
                connectionStore: macConnectionStore,
                studyLibraryStore: recordingManager.studyLibraryStore,
                recordingManager: recordingManager,
                uploadCoordinator: uploadCoordinator
            )
        }
        .navigationDestination(isPresented: $isSettingsPresented) {
            IPhoneSettingsView(userProfileStore: userProfileStore)
        }
        .onAppear {
            macConnectionStore.refreshFromStorage()
        }
    }

    private func homeHeader(metrics: RokuricsAdaptiveLayout.Metrics) -> some View {
        HStack(alignment: .center) {
            Text("Rokurics")
                .font(RokuricsTypography.appTitle(size: 39 * metrics.headerScale))
                .foregroundStyle(RokuricsColors.deepText)

            Spacer(minLength: 16)

            RokuricsProfileAvatarButton(
                profile: userProfileStore.profile,
                accessibilityLabel: "打开设置",
                size: 46 * metrics.headerScale
            ) {
                isSettingsPresented = true
            }
        }
    }

    private func openRecordingSession() {
        print("[RokuricsNavigation] open recording session")
        isRecordingSessionPresented = true
    }

    private func openRecordingLibrary() {
        print("[RokuricsNavigation] open recording library")
        recordingManager.reloadRecordings()
        isRecordingLibraryPresented = true
    }

    private func openAIChat() {
        print("[RokuricsNavigation] open AI chat")
        isAIChatPresented = true
    }

    private func openMacConnection() {
        print("[RokuricsNavigation] open Mac connection")
        isMacConnectionPresented = true
    }
}

private struct RokuricsHomeBackground: View {
    let metrics: RokuricsAdaptiveLayout.Metrics

    var body: some View {
        ZStack {
            RokuricsColors.pageGradient
                .ignoresSafeArea()

            RokuricsAmbientBubble(
                size: metrics.isPadWidth ? 210 : 150,
                colors: [RokuricsColors.paleAqua, RokuricsColors.mint],
                opacity: 0.30
            )
            .offset(x: -metrics.width * 0.34, y: -metrics.height * 0.31)

            RokuricsAmbientBubble(
                size: metrics.isPadWidth ? 260 : 190,
                colors: [RokuricsColors.skyCyan, RokuricsColors.mistGreen],
                opacity: 0.22
            )
            .offset(x: metrics.width * 0.36, y: -metrics.height * 0.10)

            RokuricsAmbientBubble(
                size: metrics.isPadWidth ? 230 : 170,
                colors: [RokuricsColors.mint, RokuricsColors.aqua],
                opacity: 0.18
            )
            .offset(x: metrics.width * 0.28, y: metrics.height * 0.35)
        }
    }
}

private struct RokuricsAmbientBubble: View {
    let size: CGFloat
    let colors: [Color]
    let opacity: Double

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: colors.map { $0.opacity(opacity) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.30),
                                .white.opacity(0.06),
                                RokuricsColors.aqua.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .blur(radius: 0.15)
            .accessibilityHidden(true)
    }
}

private struct RokuricsRecordingOrb: View {
    let visualScale: CGFloat
    let state: RokuricsRecordingState
    let elapsedSeconds: TimeInterval
    let action: () -> Void
    @State private var isBreathing = false
    private let orbitDuration: TimeInterval = 160

    var body: some View {
        let scale = max(visualScale, 0.1)

        TimelineView(.animation) { timeline in
            let orbitDegrees = orbitAngle(for: timeline.date)

            Button(action: action) {
                ZStack {
                    ZStack {
                        RokuricsOrbBubble(
                            size: 88 * scale,
                            colors: [RokuricsColors.mint, RokuricsColors.paleAqua],
                            opacity: 0.42
                        )
                        .rotationEffect(.degrees(-orbitDegrees))
                        .scaleEffect(isBreathing ? 1.035 : 0.985)
                        .offset(x: -94 * scale, y: -66 * scale)

                        RokuricsOrbBubble(
                            size: 76 * scale,
                            colors: [RokuricsColors.skyCyan, RokuricsColors.mistGreen],
                            opacity: 0.32
                        )
                        .rotationEffect(.degrees(-orbitDegrees))
                        .scaleEffect(isBreathing ? 0.985 : 1.04)
                        .offset(x: 100 * scale, y: -54 * scale)

                        RokuricsOrbBubble(
                            size: 74 * scale,
                            colors: [RokuricsColors.aqua, RokuricsColors.paleAqua],
                            opacity: 0.30
                        )
                        .rotationEffect(.degrees(-orbitDegrees))
                        .scaleEffect(isBreathing ? 1.03 : 0.99)
                        .offset(x: 90 * scale, y: 76 * scale)

                        RokuricsOrbBubble(
                            size: 68 * scale,
                            colors: [RokuricsColors.mistGreen, RokuricsColors.mint],
                            opacity: 0.34
                        )
                        .rotationEffect(.degrees(-orbitDegrees))
                        .scaleEffect(isBreathing ? 0.99 : 1.04)
                        .offset(x: -104 * scale, y: 74 * scale)
                    }
                    .rotationEffect(.degrees(orbitDegrees))

                    RokuricsSoundRipple(size: 238 * scale, opacity: isBreathing ? 0.12 : 0.07)
                        .scaleEffect(isBreathing ? 1.045 : 0.975)

                    RokuricsSoundRipple(size: 202 * scale, opacity: isBreathing ? 0.15 : 0.10)
                        .scaleEffect(isBreathing ? 0.99 : 1.035)

                    if state.isRecording {
                        RokuricsSoundRipple(size: 222 * scale, opacity: isBreathing ? 0.24 : 0.16, tint: RokuricsColors.coral)
                            .scaleEffect(isBreathing ? 1.10 : 1.02)
                    } else if state.isPaused {
                        RokuricsSoundRipple(size: 222 * scale, opacity: isBreathing ? 0.17 : 0.11, tint: RokuricsColors.softTeal)
                            .scaleEffect(isBreathing ? 1.05 : 1.00)
                    }

                    Circle()
                        .fill(RokuricsColors.actionGradient)
                        .frame(width: 190 * scale, height: 190 * scale)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color.white.opacity(0.38),
                                            Color.white.opacity(0.15),
                                            Color.white.opacity(0.03)
                                        ],
                                        center: .topLeading,
                                        startRadius: 12 * scale,
                                        endRadius: 150 * scale
                                    )
                                )
                                .padding(scale)
                        }
                        .overlay {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.56),
                                            Color.white.opacity(0.12),
                                            activeStrokeColor.opacity(activeStrokeOpacity)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isActiveSession ? 2.2 * scale : 1.2 * scale
                                )
                        }
                        .shadow(color: RokuricsColors.shadow.opacity(0.24), radius: 30 * scale, x: 0, y: 18 * scale)
                        .shadow(color: Color.white.opacity(0.22), radius: 10 * scale, x: -3 * scale, y: -5 * scale)
                        .scaleEffect(isBreathing || isActiveSession ? 1.018 : 0.992)

                    if isActiveSession {
                        Text(centerText)
                            .font(RokuricsTypography.largeNumber(size: centerTextSize * scale, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.97))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .rokuricsPausedBlinking(state.isPaused)
                            .shadow(color: RokuricsColors.deepText.opacity(0.16), radius: 8 * scale, y: 4 * scale)
                            .padding(.horizontal, 22 * scale)
                    } else {
                        RokuricsPlusGlyph(size: 74 * scale, thickness: 10 * scale)
                            .foregroundStyle(.white.opacity(0.97))
                            .shadow(color: RokuricsColors.deepText.opacity(0.12), radius: 8 * scale, y: 4 * scale)
                    }

                }
                .frame(width: 272 * scale, height: 286 * scale)
                .scaleEffect(isBreathing || isActiveSession ? 1.010 : 0.996)
                .offset(y: (isBreathing ? -4 : 2) * scale)
                .contentShape(Circle())
            }
            .buttonStyle(RokuricsScaleButtonStyle())
            .accessibilityLabel(accessibilityLabel)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private func orbitAngle(for date: Date) -> Double {
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: orbitDuration) / orbitDuration
        return progress * 360
    }

    private var accessibilityLabel: String {
        switch state {
        case .recording:
            return "返回当前录音"
        case .paused:
            return "返回已暂停录音"
        case .requestingPermission:
            return "打开录音页，正在请求麦克风权限"
        case .configuringSession:
            return "打开录音页，正在配置录音"
        case .stopping:
            return "打开录音页，正在保存录音"
        case .filing:
            return "归档录音"
        case .saving:
            return "正在保存录音"
        default:
            return "开始录音"
        }
    }

    private var isActiveSession: Bool {
        switch state {
        case .requestingPermission, .configuringSession, .recording, .paused, .stopping, .saving:
            return true
        case .idle, .filing, .saved, .permissionDenied, .failed:
            return false
        }
    }

    private var centerText: String {
        switch state {
        case .requestingPermission, .configuringSession, .stopping, .saving:
            return "..."
        case .recording, .paused:
            return RokuricsRecordingFormat.clock(elapsedSeconds)
        case .idle, .filing, .saved, .permissionDenied, .failed:
            return "+"
        }
    }

    private var centerTextSize: CGFloat {
        centerText.count > 5 ? 34 : 44
    }

    private var activeStrokeColor: Color {
        switch state {
        case .recording:
            return RokuricsColors.coral
        case .paused:
            return RokuricsColors.softTeal
        case .requestingPermission, .configuringSession, .stopping, .saving:
            return RokuricsColors.aqua
        case .idle, .filing, .saved, .permissionDenied, .failed:
            return RokuricsColors.mint
        }
    }

    private var activeStrokeOpacity: Double {
        isActiveSession ? 0.42 : 0.25
    }
}

private struct RokuricsSoundRipple: View {
    let size: CGFloat
    let opacity: Double
    var tint: Color = RokuricsColors.aqua

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        tint.opacity(opacity),
                        RokuricsColors.mint.opacity(opacity * 0.70),
                        Color.white.opacity(opacity * 0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.4
            )
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .opacity(0.92)
            .accessibilityHidden(true)
    }
}

private struct RokuricsOrbBubble: View {
    let size: CGFloat
    let colors: [Color]
    let opacity: Double

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: colors.map { $0.opacity(opacity) },
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.06),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: size * 0.72
                        )
                    )
            }
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.40),
                                Color.white.opacity(0.08),
                                RokuricsColors.aqua.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: RokuricsColors.shadow.opacity(0.08), radius: 14, y: 8)
            .accessibilityHidden(true)
    }
}

private struct RokuricsPlusGlyph: View {
    let size: CGFloat
    let thickness: CGFloat

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .frame(width: size, height: thickness)

            Capsule(style: .continuous)
                .frame(width: thickness, height: size)
        }
    }
}

private struct RokuricsStopGlyph: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .frame(width: size, height: size)
    }
}

private struct RokuricsProfileAvatarButton: View {
    let profile: UserProfile
    let accessibilityLabel: String
    let size: CGFloat
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: profile.avatar)
                .font(.system(size: size * 0.88, weight: .regular))
                .foregroundStyle(RokuricsColors.aqua, .white.opacity(0.88))
                .frame(width: size, height: size)
                .padding(size <= 48 ? 3 : 5)
                .rokuricsGlassCircle(fillOpacity: 0.36, strokeOpacity: 0.50, shadowOpacity: 0.14, shadowRadius: 12, shadowY: 6)
        }
        .buttonStyle(RokuricsScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct RokuricsHomeNavigationCard: View {
    let scale: CGFloat
    let isMacPaired: Bool
    let onOpenRecordingLibrary: () -> Void
    let onOpenAIChat: () -> Void
    let onOpenMacConnection: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            RokuricsHomeNavigationButton(
                title: "学习库",
                systemImage: "books.vertical",
                tint: RokuricsColors.aqua,
                scale: scale,
                action: onOpenRecordingLibrary
            )
            .accessibilityLabel("打开学习库")

            RokuricsHomeDashboardDivider(scale: scale)

            RokuricsHomeNavigationButton(
                title: "AI 对话",
                systemImage: "bubble.left.and.bubble.right",
                tint: RokuricsColors.mint,
                scale: scale,
                action: onOpenAIChat
            )
            .accessibilityLabel("打开 AI 对话")

            RokuricsHomeDashboardDivider(scale: scale)

            RokuricsHomeNavigationButton(
                title: "Mac 连接",
                systemImage: isMacPaired ? "iphone.gen3.radiowaves.left.and.right" : "iphone.slash",
                tint: RokuricsColors.softTeal,
                scale: scale,
                action: onOpenMacConnection
            )
            .accessibilityLabel(isMacPaired ? "打开 Mac 连接，已配对" : "打开 Mac 连接，未配对")
        }
        .frame(maxWidth: .infinity, minHeight: 104 * scale)
        .frame(maxWidth: .infinity)
        .rokuricsLiquidGlassCard(cornerRadius: 30 * scale, fillOpacity: 0.40, strokeOpacity: 0.44, shadowOpacity: 0.12, shadowRadius: 20 * scale, shadowY: 11 * scale)
    }
}

private struct RokuricsHomeNavigationButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let scale: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9 * scale) {
                Image(systemName: systemImage)
                    .font(.system(size: 27 * scale, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(height: 34 * scale)
                    .accessibilityHidden(true)

                Text(title)
                    .font(RokuricsTypography.caption(size: 13 * scale, weight: .semibold))
                    .foregroundStyle(RokuricsColors.deepText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 104 * scale)
            .contentShape(Rectangle())
        }
        .buttonStyle(RokuricsScaleButtonStyle())
    }
}

private struct RokuricsHomeDashboardDivider: View {
    let scale: CGFloat

    var body: some View {
        Rectangle()
            .fill(RokuricsColors.softText.opacity(0.14))
            .frame(width: 1, height: 54 * scale)
    }
}

enum RokuricsRecordingFormat {
    static func durationValue(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(max(0, Int(seconds.rounded(.down))))"
        }

        return String(format: "%.1f", seconds / 60)
    }

    static func durationUnit(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "sec" : "min"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(max(0, Int(seconds.rounded(.down)))) sec"
        }

        return String(format: "%.1f min", seconds / 60)
    }

    static func shortTime(_ date: Date) -> String {
        shortTimeFormatter.string(from: date)
    }

    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        RokuricsHomeView(
            recordingManager: RecordingManager(),
            macConnectionStore: SecureMacConnectionStore(),
            userProfileStore: UserProfileStore()
        )
    }
}
