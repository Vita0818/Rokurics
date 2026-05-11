//
//  MacTranscriptionCard.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacTranscriptionCard: View {
    @ObservedObject var transcriptionQueue: TranscriptionQueue
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MacDashboardCard(systemImage: "waveform.and.magnifyingglass", tint: MacTheme.leaf) {
            Text("转写队列")
                .font(MacTypography.chineseHeadline(size: 17))
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(transcriptionQueue.status)
                        .font(MacTypography.chineseTitle(size: 32))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)

                    Spacer()

                    MacStatusPill(text: "\(transcriptionQueue.queuedCount) queued", systemImage: "clock", tint: MacTheme.aqua)
                }

                Spacer(minLength: 12)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("Whisper / MLX")
                        .font(MacTypography.englishBody(size: 14, weight: .medium))

                    Text("稍后支持")
                        .font(MacTypography.chineseBody(size: 14, weight: .medium))
                }
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .lineLimit(1)

                Spacer(minLength: 12)

                Text("Local engine")
                    .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
            }
        }
    }
}
