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
            Text("音频收件箱")
                .font(MacTypography.chineseHeadline(size: 17))
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(audioInboxStore.pendingCount)")
                        .font(MacTypography.number(size: 46))
                        .foregroundStyle(MacTheme.aqua)
                        .lineLimit(1)

                    Spacer()

                    MacStatusPill(text: "真实录音", systemImage: "waveform", tint: MacTheme.leaf)
                }

                Spacer(minLength: 12)

                Text("已配对 iPhone 上传的本地音频")
                    .font(MacTypography.chineseBody(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 12)

                let footerText = audioInboxStore.latestRecordingItem?.title ?? "HTTPS + HMAC，HTTP 已隔离"
                Text(footerText)
                    .font(footerText.macContainsCJK ? MacTypography.chineseCaption(size: 12, weight: .semibold) : MacTypography.englishCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
