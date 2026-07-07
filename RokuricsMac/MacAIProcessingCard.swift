//
//  MacAIProcessingCard.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacAIProcessingCard: View {
    @ObservedObject var noteGenerationSettingsStore: NoteGenerationSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MacDashboardCard(systemImage: "sparkles", tint: MacTheme.amber) {
            if RokuricsCopy.usesChinese {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("AI")
                        .font(MacTypography.englishHeadline(size: 17))

                    Text("整理")
                        .font(MacTypography.chineseHeadline(size: 17))
                }
            } else {
                Text("AI Notes")
                    .font(MacTypography.englishHeadline(size: 17))
            }
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(noteGenerationSettingsStore.selectedProviderDisplayName)
                        .font(MacTypography.statusDisplay(for: noteGenerationSettingsStore.selectedProviderDisplayName, size: 32))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)

                    Spacer()

                    MacStatusPill(text: "API", systemImage: "bolt", tint: MacTheme.amber)
                }

                Spacer(minLength: 12)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(providerSubtitle)
                        .font(MacTypography.englishBody(size: 14, weight: .medium))

                    Text(RokuricsCopy.text("可切换", "Switchable"))
                        .font(RokuricsCopy.usesChinese ? MacTypography.chineseBody(size: 14, weight: .medium) : MacTypography.englishBody(size: 14, weight: .medium))
                }
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .lineLimit(1)

                Spacer(minLength: 12)

                Text(noteGenerationSettingsStore.endpointDisplay)
                    .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var providerSubtitle: String {
        switch noteGenerationSettingsStore.selectedProviderKind {
        case .mock:
            return "Mock"
        case .openAICompatible:
            return "OpenAI-compatible"
        case .anthropicMessages:
            return "Claude Messages"
        }
    }
}
