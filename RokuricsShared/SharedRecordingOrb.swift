//
//  SharedRecordingOrb.swift
//  Rokurics
//
//  Created by Codex on 2026/7/7.
//

import SwiftUI

enum RokuricsSharedRecordingOrbPhase: Equatable {
    case idle
    case preparing
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
        switch self {
        case .preparing, .stopping, .filing, .saving:
            return true
        case .idle, .recording, .paused, .saved, .permissionDenied, .failed:
            return false
        }
    }

    var isActiveSession: Bool {
        switch self {
        case .preparing, .recording, .paused, .stopping, .saving:
            return true
        case .idle, .filing, .saved, .permissionDenied, .failed:
            return false
        }
    }
}

struct RokuricsSharedRecordingOrb: View {
    let visualScale: CGFloat
    let phase: RokuricsSharedRecordingOrbPhase
    let elapsedSeconds: TimeInterval
    var accessibilityLabel: String?
    let action: () -> Void

    @State private var isBreathing = false
    @Environment(\.colorScheme) private var colorScheme
    private let orbitDuration: TimeInterval = 160

    var body: some View {
        let scale = max(visualScale, 0.1)

        TimelineView(.animation) { timeline in
            let orbitDegrees = orbitAngle(for: timeline.date)

            Button(action: action) {
                ZStack {
                    ZStack {
                        RokuricsSharedOrbBubble(
                            size: 88 * scale,
                            colors: [RokuricsSharedStyle.mint, RokuricsSharedStyle.aqua.opacity(0.68)],
                            opacity: 0.42
                        )
                        .rotationEffect(.degrees(-orbitDegrees))
                        .scaleEffect(isBreathing ? 1.035 : 0.985)
                        .offset(x: -94 * scale, y: -66 * scale)

                        RokuricsSharedOrbBubble(
                            size: 76 * scale,
                            colors: [RokuricsSharedStyle.aqua, RokuricsSharedStyle.mint.opacity(0.70)],
                            opacity: 0.32
                        )
                        .rotationEffect(.degrees(-orbitDegrees))
                        .scaleEffect(isBreathing ? 0.985 : 1.04)
                        .offset(x: 100 * scale, y: -54 * scale)

                        RokuricsSharedOrbBubble(
                            size: 74 * scale,
                            colors: [RokuricsSharedStyle.aqua, Color.white],
                            opacity: 0.30
                        )
                        .rotationEffect(.degrees(-orbitDegrees))
                        .scaleEffect(isBreathing ? 1.03 : 0.99)
                        .offset(x: 90 * scale, y: 76 * scale)

                        RokuricsSharedOrbBubble(
                            size: 68 * scale,
                            colors: [RokuricsSharedStyle.leaf.opacity(0.70), RokuricsSharedStyle.mint],
                            opacity: 0.34
                        )
                        .rotationEffect(.degrees(-orbitDegrees))
                        .scaleEffect(isBreathing ? 0.99 : 1.04)
                        .offset(x: -104 * scale, y: 74 * scale)
                    }
                    .rotationEffect(.degrees(orbitDegrees))

                    if phase.isRecording {
                        RokuricsSharedSoundRipple(
                            size: 222 * scale,
                            opacity: isBreathing ? 0.24 : 0.16,
                            tint: RokuricsSharedStyle.coral
                        )
                        .scaleEffect(isBreathing ? 1.10 : 1.02)
                    } else if phase.isPaused {
                        RokuricsSharedSoundRipple(
                            size: 222 * scale,
                            opacity: isBreathing ? 0.17 : 0.11,
                            tint: RokuricsSharedStyle.leaf
                        )
                        .scaleEffect(isBreathing ? 1.05 : 1.00)
                    }

                    Circle()
                        .fill(RokuricsSharedStyle.actionGradient)
                        .frame(width: 238 * scale, height: 238 * scale)
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
                                    lineWidth: phase.isActiveSession ? 2.2 * scale : 1.2 * scale
                                )
                        }
                        .shadow(color: shadowColor.opacity(0.24), radius: 30 * scale, x: 0, y: 18 * scale)
                        .shadow(color: Color.white.opacity(0.22), radius: 10 * scale, x: -3 * scale, y: -5 * scale)
                        .scaleEffect(isBreathing || phase.isActiveSession ? 1.018 : 0.992)

                    if phase.isActiveSession {
                        Text(centerText)
                            .font(centerFont(scale: scale))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.97))
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                            .rokuricsSharedPausedBlinking(phase.isPaused)
                            .shadow(color: RokuricsSharedStyle.deepText(for: colorScheme).opacity(0.16), radius: 8 * scale, y: 4 * scale)
                            .padding(.horizontal, 22 * scale)
                    } else {
                        RokuricsSharedPlusGlyph(size: 92 * scale, thickness: 12 * scale)
                            .foregroundStyle(.white.opacity(0.97))
                            .shadow(color: RokuricsSharedStyle.deepText(for: colorScheme).opacity(0.12), radius: 8 * scale, y: 4 * scale)
                    }
                }
                .frame(width: 272 * scale, height: 286 * scale)
                .scaleEffect(isBreathing || phase.isActiveSession ? 1.010 : 0.996)
                .offset(y: (isBreathing ? -4 : 2) * scale)
                .contentShape(Circle())
            }
            #if os(macOS)
            .buttonStyle(.plain)
            #else
            .buttonStyle(RokuricsScaleButtonStyle())
            #endif
            .accessibilityLabel(accessibilityLabel ?? defaultAccessibilityLabel)
            #if os(macOS)
            .help(accessibilityLabel ?? defaultAccessibilityLabel)
            #endif
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

    private var centerText: String {
        switch phase {
        case .preparing, .stopping, .saving:
            return "..."
        case .recording, .paused:
            return RokuricsSharedRecordingTimeFormat.clock(elapsedSeconds)
        case .idle, .filing, .saved, .permissionDenied, .failed:
            return "+"
        }
    }

    private var centerTextSize: CGFloat {
        centerText.count > 5 ? 34 : 44
    }

    private func centerFont(scale: CGFloat) -> Font {
        #if os(macOS)
        return MacTypography.numberTitle(size: centerTextSize * scale, weight: .bold)
        #else
        return RokuricsTypography.largeNumber(size: centerTextSize * scale, weight: .bold)
        #endif
    }

    private var activeStrokeColor: Color {
        switch phase {
        case .recording:
            return RokuricsSharedStyle.coral
        case .paused:
            return RokuricsSharedStyle.leaf
        case .preparing, .stopping, .saving:
            return RokuricsSharedStyle.aqua
        case .idle, .filing, .saved, .permissionDenied, .failed:
            return RokuricsSharedStyle.mint
        }
    }

    private var activeStrokeOpacity: Double {
        phase.isActiveSession ? 0.42 : 0.25
    }

    private var shadowColor: Color {
        #if os(macOS)
        return MacTheme.shadow(for: colorScheme)
        #else
        return RokuricsColors.shadow
        #endif
    }

    private var defaultAccessibilityLabel: String {
        switch phase {
        case .recording:
            return RokuricsCopy.text("停止录音", "Stop Recording")
        case .paused:
            return RokuricsCopy.text("返回已暂停录音", "Return to Paused Recording")
        case .preparing:
            return RokuricsCopy.text("正在准备录音", "Preparing Recording")
        case .stopping, .saving:
            return RokuricsCopy.text("正在保存录音", "Saving Recording")
        case .filing:
            return RokuricsCopy.text("归档录音", "File Recording")
        default:
            return RokuricsCopy.text("开始录音", "Start Recording")
        }
    }
}

private struct RokuricsSharedSoundRipple: View {
    let size: CGFloat
    let opacity: Double
    var tint: Color = RokuricsSharedStyle.aqua

    var body: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        tint.opacity(opacity),
                        RokuricsSharedStyle.mint.opacity(opacity * 0.70),
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

private struct RokuricsSharedOrbBubble: View {
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
                                RokuricsSharedStyle.aqua.opacity(0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: RokuricsSharedStyle.aqua.opacity(0.08), radius: 14, y: 8)
            .accessibilityHidden(true)
    }
}

private struct RokuricsSharedPlusGlyph: View {
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

enum RokuricsSharedRecordingTimeFormat {
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
}

extension View {
    @ViewBuilder
    func rokuricsSharedPausedBlinking(_ isPaused: Bool) -> some View {
        if isPaused {
            self.opacity(0.62)
        } else {
            self
        }
    }
}
