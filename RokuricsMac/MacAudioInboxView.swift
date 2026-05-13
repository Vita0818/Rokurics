//
//  MacAudioInboxView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/12.
//

import SwiftUI

struct MacAudioInboxView: View {
    @ObservedObject var audioInboxStore: AudioInboxStore
    @ObservedObject var transcriptionCoordinator: TranscriptionCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            MacDetailContentContainer(maxWidth: 980) {
                VStack(alignment: .leading, spacing: 24) {
                    MacPageHeader(
                        systemImage: "tray.and.arrow.down",
                        title: .english("Audio Inbox"),
                        subtitle: "已配对 iPhone 上传的本地录音"
                    )

                    HStack(spacing: 12) {
                        MacInboxMetricPill(title: "真实录音", value: "\(audioInboxStore.pendingCount)", tint: MacTheme.aqua)
                        MacInboxMetricPill(title: "待转写", value: "\(audioInboxStore.transcriptionPendingCount)", tint: MacTheme.mint)
                        MacInboxMetricPill(title: "已转写", value: "\(audioInboxStore.transcribedCount)", tint: MacTheme.leaf)
                    }

                    if audioInboxStore.recordingItems.isEmpty {
                        Text("暂无收到的录音")
                            .font(MacTypography.chineseBody(size: 15, weight: .medium))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))
                            .padding(22)
                            .frame(maxWidth: 620, alignment: .leading)
                            .macLiquidGlassCard(cornerRadius: 22, material: .ultraThinMaterial, fillOpacity: 0.32, strokeOpacity: 0.28, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(audioInboxStore.recordingItems) { item in
                                MacAudioInboxListRow(
                                    item: item,
                                    isTranscribing: transcriptionCoordinator.isTranscribing(recordingID: item.id),
                                    onTranscribe: {
                                        transcriptionCoordinator.startTranscription(recordingID: item.id)
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear {
            audioInboxStore.refreshRecordingInbox()
        }
    }
}

private struct MacInboxMetricPill: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))

            Text(value)
                .font(MacTypography.numberBody(size: 18, weight: .bold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .macGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.30)
    }
}

private struct MacAudioInboxListRow: View {
    let item: MacRecordingInboxItem
    let isTranscribing: Bool
    let onTranscribe: () -> Void

    var body: some View {
        RecordingRowContent(
            title: item.title,
            dateTimeText: Self.dateTimeFormatter.string(from: item.receivedAt),
            durationText: durationText(item.duration),
            layout: .regular
        ) {
            HStack(spacing: 8) {
                MacStatusPill(text: visibleStatusText, systemImage: nil, tint: statusTint)
                    .frame(width: 86, alignment: .trailing)
                    .help(item.transcriptionError ?? visibleStatusText)

                if shouldShowActionButton {
                    Button(action: onTranscribe) {
                        Text(item.transcriptionActionText)
                            .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                            .foregroundStyle(MacTheme.deepText(for: colorScheme))
                            .lineLimit(1)
                            .frame(width: 54)
                            .padding(.vertical, 7)
                            .macGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.30)
                    }
                    .buttonStyle(.plain)
                    .disabled(isTranscribing)
                }
            }
            .frame(width: 154, alignment: .trailing)
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var visibleStatusText: String {
        isTranscribing ? "转写中" : item.statusText
    }

    private var shouldShowActionButton: Bool {
        item.canStartTranscription && !isTranscribing
    }

    private var statusTint: Color {
        if isTranscribing || item.isTranscriptionActive {
            return MacTheme.aqua
        }

        switch item.transcriptionStatus {
        case "transcribed":
            return MacTheme.leaf
        case "failed":
            return MacTheme.coral
        default:
            return MacTheme.mint
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60

        if minutes == 0 {
            return "\(remainingSeconds)''"
        }

        return "\(minutes)'\(String(format: "%02d", remainingSeconds))''"
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}

private enum RecordingRowLayout {
    case regular
}

private struct RecordingRowContent<Trailing: View>: View {
    let title: String
    let dateTimeText: String
    let durationText: String
    let layout: RecordingRowLayout
    private let trailing: Trailing
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        dateTimeText: String,
        durationText: String,
        layout: RecordingRowLayout,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.dateTimeText = dateTimeText
        self.durationText = durationText
        self.layout = layout
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(MacTheme.aqua, .white.opacity(0.88))
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 7) {
                MacMixedFontText(
                    text: title,
                    chineseFont: MacTypography.chineseBody(size: 16, weight: .semibold),
                    englishFont: MacTypography.englishBody(size: 16, weight: .semibold),
                    numberFont: MacTypography.numberBody(size: 16, weight: .semibold)
                )
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Text(dateTimeText)
                .font(rowMetaFont)
                .foregroundStyle(rowMetaColor)
                .lineLimit(1)
                .frame(width: 98, alignment: .trailing)

            Text(durationText)
                .font(rowMetaFont)
                .foregroundStyle(rowMetaColor)
                .frame(width: 62, alignment: .trailing)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
    }

    private var rowMetaFont: Font {
        switch layout {
        case .regular:
            return MacTypography.numberBody(size: 15, weight: .semibold)
        }
    }

    private var rowMetaColor: Color {
        MacTheme.softText(for: colorScheme)
    }
}
