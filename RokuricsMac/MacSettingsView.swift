//
//  MacSettingsView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacSettingsView: View {
    @ObservedObject var secureReceiverService: SecureReceiverService
    @ObservedObject var audioInboxStore: AudioInboxStore
    @ObservedObject var transcriptionQueue: TranscriptionQueue
    @ObservedObject var llmServiceConfig: LLMServiceConfig
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    MacPageHeader(
                        systemImage: "person.fill",
                        title: .english("Settings"),
                        subtitle: "Local-first defaults for the Mac processing center"
                    )

                    VStack(spacing: 0) {
                        MacSettingsRow(title: "安全接收端口", value: "\(secureReceiverService.port)", systemImage: "number")
                        MacSettingsDivider()
                        MacSettingsRow(title: "HTTPS 状态", value: secureReceiverService.httpsStatusText, systemImage: "lock.shield")
                        MacSettingsDivider()
                        MacSettingsRow(title: "Mac 指纹", value: secureReceiverService.formattedFingerprint, systemImage: "lock.shield")
                        MacSettingsDivider()
                        MacSettingsRow(title: "配对设备", value: "\(secureReceiverService.pairedDeviceCount)", systemImage: "iphone.gen3")
                        MacSettingsDivider()
                        MacSettingsRow(title: "转写引擎", value: transcriptionQueue.status, systemImage: "waveform.and.magnifyingglass")
                        MacSettingsDivider()
                        MacSettingsRow(title: "AI 后端", value: llmServiceConfig.provider, systemImage: "sparkles")
                        MacSettingsDivider()
                        MacSettingsRow(title: "本地目录", value: audioInboxStore.libraryRootDisplayPath, systemImage: "folder")
                        MacSettingsDivider()
                        MacSettingsRow(title: "隐私原则", value: "音频默认不上云", systemImage: "lock.shield")
                    }
                    .padding(6)
                    .frame(maxWidth: 680, alignment: .leading)
                    .macLiquidGlassCard(cornerRadius: 28, material: .thinMaterial, fillOpacity: 0.46, strokeOpacity: 0.42, shadowOpacity: 0.09, shadowRadius: 16, shadowY: 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Endpoint")
                            .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                            .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))

                        Text(llmServiceConfig.endpoint)
                            .font(MacTypography.englishBody(size: 14, weight: .medium))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))
                            .textSelection(.enabled)
                    }
                    .padding(18)
                    .frame(maxWidth: 680, alignment: .leading)
                    .macLiquidGlassCard(cornerRadius: 22, material: .ultraThinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.05, shadowRadius: 10, shadowY: 5)

                    Spacer(minLength: 0)
                }
                .padding(34)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct MacSettingsRow: View {
    let title: String
    let value: String
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.aqua)
                .frame(width: 32, height: 32)

            Text(title)
                .font(MacTypography.chineseBody(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Spacer(minLength: 16)

            Text(value)
                .font(MacTypography.chineseBody(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct MacSettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(MacTheme.glassStroke(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.42))
            .frame(height: 1)
            .padding(.leading, 62)
    }
}

#Preview {
    MacSettingsView(
        secureReceiverService: SecureReceiverService(),
        audioInboxStore: AudioInboxStore(),
        transcriptionQueue: TranscriptionQueue(),
        llmServiceConfig: LLMServiceConfig()
    )
}
