//
//  MacTranscriptionCard.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacTranscriptionCard: View {
    @ObservedObject var audioInboxStore: AudioInboxStore
    @ObservedObject var transcriptionCoordinator: TranscriptionCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MacDashboardCard(systemImage: "waveform.and.magnifyingglass", tint: MacTheme.leaf) {
            Text("转写队列")
                .font(MacTypography.chineseHeadline(size: 17))
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(audioInboxStore.transcriptionPendingCount)")
                        .font(MacTypography.number(size: 46))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)

                    Spacer()

                    MacStatusPill(text: "\(audioInboxStore.transcribedCount) done", systemImage: "checkmark", tint: MacTheme.aqua)
                }

                Spacer(minLength: 12)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("Provider")
                        .font(MacTypography.englishBody(size: 14, weight: .medium))

                    Text(transcriptionCoordinator.providerDisplayName)
                        .font(MacTypography.englishBody(size: 14, weight: .medium))
                }
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .lineLimit(1)

                Spacer(minLength: 12)

                Text(footerText)
                    .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
            }
        }
    }

    private var footerText: String {
        if transcriptionCoordinator.activeTaskCount > 0 {
            return "\(transcriptionCoordinator.activeTaskCount) active"
        }

        return transcriptionCoordinator.providerID == "mock"
            ? "Mock provider selected"
            : "External provider selected"
    }
}
