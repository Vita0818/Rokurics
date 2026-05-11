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
                    Text("\(secureReceiverService.acceptedUploadCount)")
                        .font(MacTypography.number(size: 46))
                        .foregroundStyle(MacTheme.aqua)
                        .lineLimit(1)

                    Spacer()

                    MacStatusPill(text: "安全测试", systemImage: "lock.doc", tint: MacTheme.leaf)
                }

                Spacer(minLength: 12)

                Text("仅允许已配对 HTTPS JSON")
                    .font(MacTypography.chineseBody(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(secureReceiverService.lastAcceptedFileName == "暂无" ? "HTTPS 未就绪，HTTP 已隔离" : secureReceiverService.lastAcceptedFileName)
                    .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}
