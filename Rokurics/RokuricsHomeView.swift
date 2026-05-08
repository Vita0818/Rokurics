//
//  RokuricsHomeView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/8.
//

import SwiftUI

struct RokuricsHomeView: View {
    @StateObject private var recordingManager = RecordingManager()

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
                        action: recordingManager.toggleRecording
                    )

                    Spacer(minLength: metrics.isPadWidth ? 32 : 20)

                    RokuricsHomeDashboardCard(
                        scale: metrics.dashboardScale,
                        recordingState: recordingManager.state,
                        elapsedSeconds: recordingManager.elapsedSeconds,
                        statusMessage: recordingManager.statusMessage
                    )
                        .padding(.bottom, metrics.homeBottomPadding)
                }
                .padding(.horizontal, metrics.horizontalPadding)
                .frame(maxWidth: metrics.homeMaxWidth)
                .frame(maxWidth: .infinity, minHeight: metrics.height, alignment: .top)
            }
        }
    }

    private func homeHeader(metrics: RokuricsAdaptiveLayout.Metrics) -> some View {
        HStack(alignment: .center) {
            Text("Rokurics")
                .font(RokuricsTypography.appTitle(size: 39 * metrics.headerScale))
                .foregroundStyle(RokuricsColors.deepText)

            Spacer(minLength: 16)

            RokuricsProfileAvatarButton(
                accessibilityLabel: "打开设置",
                size: 46 * metrics.headerScale
            )
        }
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
                                            state.isRecording ? RokuricsColors.coral.opacity(0.42) : RokuricsColors.mint.opacity(0.25)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: state.isRecording ? 2.2 * scale : 1.2 * scale
                                )
                        }
                        .shadow(color: RokuricsColors.shadow.opacity(0.24), radius: 30 * scale, x: 0, y: 18 * scale)
                        .shadow(color: Color.white.opacity(0.22), radius: 10 * scale, x: -3 * scale, y: -5 * scale)
                        .scaleEffect(isBreathing || state.isRecording ? 1.018 : 0.992)

                    if state.isRecording {
                        RokuricsStopGlyph(size: 58 * scale, cornerRadius: 12 * scale)
                            .foregroundStyle(.white.opacity(0.97))
                            .shadow(color: RokuricsColors.deepText.opacity(0.12), radius: 8 * scale, y: 4 * scale)
                    } else {
                        RokuricsPlusGlyph(size: 74 * scale, thickness: 10 * scale)
                            .foregroundStyle(.white.opacity(0.97))
                            .shadow(color: RokuricsColors.deepText.opacity(0.12), radius: 8 * scale, y: 4 * scale)
                    }

                    if let statusPill = statusPill {
                        RokuricsOrbStatusPill(text: statusPill.text, tint: statusPill.tint, scale: scale)
                            .offset(y: 128 * scale)
                    }
                }
                .frame(width: 272 * scale, height: 286 * scale)
                .scaleEffect(isBreathing || state.isRecording ? 1.010 : 0.996)
                .offset(y: (isBreathing ? -4 : 2) * scale)
                .contentShape(Circle())
            }
            .buttonStyle(RokuricsScaleButtonStyle())
            .disabled(state.isBusy)
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

    private var statusPill: (text: String, tint: Color)? {
        switch state {
        case .idle:
            return nil
        case .requestingPermission:
            return ("请求权限", RokuricsColors.aqua)
        case .recording:
            return ("正在录音 \(RokuricsRecordingFormat.clock(elapsedSeconds))", RokuricsColors.coral)
        case .stopping:
            return ("正在保存", RokuricsColors.aqua)
        case .saved:
            return ("保存成功", RokuricsColors.mint)
        case .denied:
            return ("麦克风权限未开启", RokuricsColors.coral)
        case .failed:
            return ("录音失败", RokuricsColors.coral)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .recording:
            return "停止录音"
        case .requestingPermission:
            return "正在请求麦克风权限"
        case .stopping:
            return "正在保存录音"
        default:
            return "开始录音"
        }
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

private struct RokuricsOrbStatusPill: View {
    let text: String
    let tint: Color
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 7 * scale) {
            Circle()
                .fill(tint)
                .frame(width: 7 * scale, height: 7 * scale)
                .shadow(color: tint.opacity(0.30), radius: 8 * scale, y: 2 * scale)

            Text(text)
                .font(RokuricsTypography.caption(size: 12 * scale, weight: .semibold))
                .foregroundStyle(RokuricsColors.deepText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
        }
        .padding(.horizontal, 13 * scale)
        .padding(.vertical, 8 * scale)
        .rokuricsGlassCapsule(fillOpacity: 0.50, strokeOpacity: 0.46, shadowOpacity: 0.10, shadowRadius: 12 * scale, shadowY: 6 * scale)
    }
}

private struct RokuricsProfileAvatarButton: View {
    let accessibilityLabel: String
    let size: CGFloat
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle.fill")
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

private struct RokuricsHomeDashboardCard: View {
    let scale: CGFloat
    let recordingState: RokuricsRecordingState
    let elapsedSeconds: TimeInterval
    let statusMessage: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                RokuricsHomeDashboardColumn(
                    title: "录音",
                    value: RokuricsRecordingFormat.durationValue(elapsedSeconds),
                    detail: RokuricsRecordingFormat.durationUnit(elapsedSeconds),
                    tint: recordingTint,
                    scale: scale
                )

                RokuricsHomeDashboardDivider(scale: scale)

                RokuricsHomeDashboardColumn(
                    title: "Mac",
                    value: "未连",
                    detail: "8787",
                    tint: RokuricsColors.softTeal,
                    scale: scale
                )

                RokuricsHomeDashboardDivider(scale: scale)

                RokuricsHomeDashboardColumn(
                    title: "队列",
                    value: "0",
                    detail: "待传",
                    tint: RokuricsColors.mint,
                    scale: scale
                )
            }
            .frame(minHeight: 104 * scale)

            Rectangle()
                .fill(RokuricsColors.softText.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 20 * scale)

            HStack(spacing: 8 * scale) {
                Image(systemName: footerIconName)
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(footerTint)

                Text(statusMessage)
                    .font(RokuricsTypography.caption(size: 12 * scale, weight: .semibold))
                    .foregroundStyle(RokuricsColors.softText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Spacer(minLength: 12 * scale)

                Text("本地")
                    .font(RokuricsTypography.caption(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(RokuricsColors.tertiaryText)
            }
            .padding(.horizontal, 20 * scale)
            .frame(maxWidth: .infinity, minHeight: 44 * scale)
        }
        .frame(maxWidth: .infinity)
        .rokuricsLiquidGlassCard(cornerRadius: 30 * scale, fillOpacity: 0.40, strokeOpacity: 0.44, shadowOpacity: 0.12, shadowRadius: 20 * scale, shadowY: 11 * scale)
    }

    private var recordingTint: Color {
        recordingState.isRecording ? RokuricsColors.coral : RokuricsColors.aqua
    }

    private var footerIconName: String {
        switch recordingState {
        case .recording:
            return "record.circle.fill"
        case .denied, .failed:
            return "exclamationmark.circle.fill"
        case .requestingPermission, .stopping:
            return "hourglass"
        case .idle, .saved:
            return "lock.fill"
        }
    }

    private var footerTint: Color {
        switch recordingState {
        case .recording, .denied, .failed:
            return RokuricsColors.coral
        case .requestingPermission, .stopping:
            return RokuricsColors.softTeal
        case .idle, .saved:
            return RokuricsColors.aqua
        }
    }
}

private struct RokuricsHomeDashboardColumn: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 7 * scale) {
            Text(title)
                .font(RokuricsTypography.caption(size: 13 * scale, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(value)
                .font(RokuricsTypography.largeNumber(size: 28 * scale, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(detail)
                .font(RokuricsTypography.caption(size: 12 * scale, weight: .semibold))
                .foregroundStyle(RokuricsColors.tertiaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .frame(maxWidth: .infinity, minHeight: 104 * scale)
        .contentShape(Rectangle())
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

private enum RokuricsRecordingFormat {
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
}

#Preview {
    RokuricsHomeView()
}
