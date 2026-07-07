//
//  MacAudioInboxCard.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacAudioInboxCard: View {
    @ObservedObject var audioInboxStore: AudioInboxStore
    @ObservedObject var secureReceiverService: SecureReceiverService
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MacDashboardCard(systemImage: "tray.and.arrow.down", tint: MacTheme.mint) {
            Text(RokuricsCopy.text("学习库", "Library"))
                .font(RokuricsCopy.usesChinese ? MacTypography.chineseHeadline(size: 17) : MacTypography.englishHeadline(size: 17))
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(audioInboxStore.pendingCount)")
                        .font(MacTypography.number(size: 46))
                        .foregroundStyle(MacTheme.aqua)
                        .lineLimit(1)

                    Spacer()

                    MacStatusPill(text: RokuricsCopy.text("真实录音", "Real Audio"), systemImage: "waveform", tint: MacTheme.leaf)
                }

                Spacer(minLength: 12)

                Text(RokuricsCopy.text("录音、转写与笔记统一入口", "Recordings, transcripts, and notes"))
                    .font(RokuricsCopy.usesChinese ? MacTypography.chineseBody(size: 14, weight: .medium) : MacTypography.englishBody(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 12)

                let footerText = audioInboxStore.latestRecordingItem?.title ?? RokuricsCopy.text("HTTPS + HMAC，HTTP 已隔离", "HTTPS + HMAC, HTTP isolated")
                Text(footerText)
                    .font(footerText.macContainsCJK ? MacTypography.chineseCaption(size: 12, weight: .semibold) : MacTypography.englishCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
