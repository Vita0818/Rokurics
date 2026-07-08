//
//  SharedRecordingSessionSurface.swift
//  Rokurics
//
//  Created by Codex on 2026/7/7.
//

import SwiftUI

struct RokuricsSharedRecordingSessionSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    let elapsedSeconds: TimeInterval
    let isPaused: Bool
    let errorMessage: String?
    let transcriptText: String
    let pauseButtonTitle: String
    let pauseButtonSystemImage: String
    let canPauseOrResume: Bool
    let canStop: Bool
    var footerMessage = RokuricsCopy.text("Mac 传输稍后支持", "Mac transfer soon")
    let backAction: () -> Void
    let pauseResumeAction: () -> Void
    let stopAction: () -> Void

    var body: some View {
        ZStack {
            RokuricsSharedRecordingSessionBackground()

            VStack(spacing: 0) {
                header
                    .padding(.top, 18)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        RokuricsSharedRecordingTimerCard(
                            elapsedSeconds: elapsedSeconds,
                            isPaused: isPaused,
                            errorMessage: errorMessage
                        )

                        RokuricsSharedLiveTranscriptCard(transcriptText: transcriptText)
                    }
                    .padding(.top, 28)
                    .padding(.bottom, 22)
                }

                controls
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            RokuricsGlassIconButton(
                systemImage: "chevron.left",
                accessibilityTitle: RokuricsCopy.text("返回首页", "Back Home"),
                action: backAction
            )

            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .accessibilityHidden(true)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                RokuricsSharedRecordingControlButton(
                    title: pauseButtonTitle,
                    systemImage: pauseButtonSystemImage,
                    tint: RokuricsSharedStyle.leaf,
                    isEnabled: canPauseOrResume,
                    action: pauseResumeAction
                )

                RokuricsSharedRecordingControlButton(
                    title: RokuricsCopy.text("停止", "Stop"),
                    systemImage: "stop.fill",
                    tint: RokuricsSharedStyle.coral,
                    isEnabled: canStop,
                    action: stopAction
                )

                RokuricsSharedRecordingControlButton(
                    title: RokuricsCopy.text("上传", "Upload"),
                    systemImage: "arrow.up.circle.fill",
                    tint: RokuricsSharedStyle.tertiaryText(for: colorScheme),
                    isEnabled: false,
                    action: {}
                )
            }

            Text(footerMessage)
                .font(sharedCaptionFont(size: 12, weight: .semibold))
                .foregroundStyle(RokuricsSharedStyle.tertiaryText(for: colorScheme))
        }
    }
}

private struct RokuricsSharedRecordingTimerCard: View {
    let elapsedSeconds: TimeInterval
    let isPaused: Bool
    let errorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 18) {
            Text(RokuricsSharedRecordingTimeFormat.clock(elapsedSeconds))
                .font(sharedTimerFont)
                .monospacedDigit()
                .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .rokuricsSharedPausedBlinking(isPaused)

            if let errorMessage {
                Text(errorMessage)
                    .font(sharedCaptionFont(size: 12, weight: .semibold))
                    .foregroundStyle(RokuricsSharedStyle.coral)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 18)
        .rokuricsSharedGlassCard(
            cornerRadius: 34,
            fillOpacity: 0.36,
            strokeOpacity: 0.42,
            shadowOpacity: 0.12,
            shadowRadius: 24,
            shadowY: 14
        )
    }
}

private struct RokuricsSharedLiveTranscriptCard: View {
    let transcriptText: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(RokuricsSharedStyle.aqua)

                Text(RokuricsCopy.text("实时转写", "Live Transcript"))
                    .font(sharedTitleFont(size: 17, weight: .semibold))
                    .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                    .lineLimit(1)
            }

            ScrollView {
                Text(transcriptText.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(sharedBodyFont(size: 14, weight: .medium))
                    .foregroundStyle(RokuricsSharedStyle.deepText(for: colorScheme))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .multilineTextAlignment(.leading)
            }
            .frame(minHeight: 118, maxHeight: 158)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(RokuricsSharedStyle.glassSurface(for: colorScheme).opacity(0.36))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(RokuricsSharedStyle.glassStroke(for: colorScheme).opacity(0.30), lineWidth: 1)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct RokuricsSharedRecordingControlButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))

                Text(title)
                    .font(sharedCaptionFont(size: 13, weight: .semibold))
            }
            .foregroundStyle(isEnabled ? tint : RokuricsSharedStyle.tertiaryText(for: colorScheme))
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .rokuricsSharedGlassCard(
                cornerRadius: 24,
                fillOpacity: isEnabled ? 0.38 : 0.24,
                strokeOpacity: 0.34,
                shadowOpacity: isEnabled ? 0.08 : 0.03,
                shadowRadius: 12,
                shadowY: 6
            )
            .opacity(isEnabled ? 1 : 0.58)
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #else
        .buttonStyle(RokuricsScaleButtonStyle())
        #endif
        .disabled(!isEnabled)
        #if os(macOS)
        .help(title)
        #endif
    }
}

private struct RokuricsSharedRecordingSessionBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RokuricsSharedStyle.pageGradient(for: colorScheme)
            .ignoresSafeArea()
    }
}

private var sharedTimerFont: Font {
    #if os(macOS)
    return MacTypography.numberTitle(size: 78, weight: .bold)
    #else
    return RokuricsTypography.largeNumber(size: 78, weight: .bold)
    #endif
}

private func sharedTitleFont(size: CGFloat, weight: Font.Weight) -> Font {
    #if os(macOS)
    return MacTypography.chineseTitle(size: size, weight: weight)
    #else
    return RokuricsTypography.title(size: size, weight: weight)
    #endif
}

private func sharedBodyFont(size: CGFloat, weight: Font.Weight) -> Font {
    #if os(macOS)
    return MacTypography.chineseBody(size: size, weight: weight)
    #else
    return RokuricsTypography.body(size: size, weight: weight)
    #endif
}

private func sharedCaptionFont(size: CGFloat, weight: Font.Weight) -> Font {
    #if os(macOS)
    return MacTypography.chineseBody(size: size, weight: weight)
    #else
    return RokuricsTypography.caption(size: size, weight: weight)
    #endif
}
