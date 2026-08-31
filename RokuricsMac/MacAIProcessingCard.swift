//
//  MacAIProcessingCard.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacAIProcessingCard: View {
    @ObservedObject var aiConfigurationStore: RokuricsAIConfigurationStore
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
                    Text(aiConfigurationStore.catalog.selectedProvider?.title ?? RokuricsCopy.text("未配置", "Not configured"))
                        .font(MacTypography.statusDisplay(for: aiConfigurationStore.catalog.selectedProvider?.title ?? "AI", size: 32))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)

                    Spacer()

                    MacStatusPill(text: "API", systemImage: "bolt", tint: MacTheme.amber)
                }

                Spacer(minLength: 12)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(aiConfigurationStore.summaryConfigurationText)
                        .font(MacTypography.englishBody(size: 14, weight: .medium))

                    Text(RokuricsCopy.text("总结", "Summary"))
                        .font(RokuricsCopy.usesChinese ? MacTypography.chineseBody(size: 14, weight: .medium) : MacTypography.englishBody(size: 14, weight: .medium))
                }
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .lineLimit(1)

                Spacer(minLength: 12)

                Text(aiConfigurationStore.transcriptionConfigurationText)
                    .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

}
