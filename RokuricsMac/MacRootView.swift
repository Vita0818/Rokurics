//
//  MacRootView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI

struct MacRootView: View {
    @State private var selection: MacSidebarItem? = .dashboard
    @State private var isSettingsSelected = false
    @StateObject private var secureReceiverService = SecureReceiverService()
    @StateObject private var audioInboxStore = AudioInboxStore()
    @StateObject private var transcriptionQueue = TranscriptionQueue()
    @StateObject private var llmServiceConfig = LLMServiceConfig()

    var body: some View {
        NavigationSplitView {
            MacSidebarView(selection: $selection, isSettingsSelected: $isSettingsSelected)
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 280)
        } detail: {
            if isSettingsSelected {
                MacSettingsView(
                    secureReceiverService: secureReceiverService,
                    audioInboxStore: audioInboxStore,
                    transcriptionQueue: transcriptionQueue,
                    llmServiceConfig: llmServiceConfig
                )
            } else {
                detailView(for: selection ?? .dashboard)
            }
        }
        .navigationTitle("")
        .toolbar(removing: .title)
        .background(MacTheme.pageGradient)
        .frame(minWidth: 1040, minHeight: 690)
    }

    @ViewBuilder
    private func detailView(for item: MacSidebarItem) -> some View {
        switch item {
        case .dashboard:
            MacDashboardView(
                secureReceiverService: secureReceiverService,
                audioInboxStore: audioInboxStore,
                transcriptionQueue: transcriptionQueue,
                llmServiceConfig: llmServiceConfig,
                onOpenIPhoneConnection: {
                    isSettingsSelected = false
                    selection = .iPhoneConnection
                }
            )
        case .iPhoneConnection:
            MacIPhoneConnectionView(secureReceiverService: secureReceiverService)
        case .audioInbox:
            MacPlaceholderWorkspace(
                title: "Audio Inbox",
                systemImage: "tray.and.arrow.down",
                status: "\(secureReceiverService.acceptedUploadCount)",
                caption: "只接受已配对 HTTPS 测试 JSON，真实音频稍后支持",
                details: ["Real audio: \(audioInboxStore.pendingCount)", "Paired: \(secureReceiverService.pairedDeviceCount)"]
            )
        case .transcripts:
            MacPlaceholderWorkspace(
                title: "Transcripts",
                systemImage: "waveform.and.magnifyingglass",
                status: transcriptionQueue.status,
                caption: "Whisper / MLX 稍后支持",
                details: ["Queued: \(transcriptionQueue.queuedCount)", "Engine: 未配置"]
            )
        case .notes:
            MacPlaceholderWorkspace(
                title: "Notes",
                systemImage: "doc.text",
                status: "Markdown",
                caption: "课堂笔记与知识点卡片稍后支持",
                details: ["Kikaria preset: planned", "Review cards: planned"]
            )
        }
    }
}

private struct MacPlaceholderWorkspace: View {
    let title: String
    let systemImage: String
    let status: String
    let caption: String
    let details: [String]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MacTheme.pageGradient
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(MacTheme.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(MacTypography.englishTitle(size: 36))
                            .foregroundStyle(MacTheme.deepText(for: colorScheme))

                        Text(caption)
                            .font(MacTypography.chineseBody(size: 14))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))
                    }
                }

                VStack(alignment: .leading, spacing: 18) {
                    Text(status)
                        .font(MacTypography.number(size: 44))
                        .foregroundStyle(MacTheme.aqua)

                    HStack(spacing: 10) {
                        ForEach(details, id: \.self) { detail in
                            Text(detail)
                                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                                .foregroundStyle(MacTheme.softText(for: colorScheme))
                                .lineLimit(1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .macGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.32)
                        }
                    }
                }
                .padding(26)
                .frame(maxWidth: 560, alignment: .leading)
                .macLiquidGlassCard(cornerRadius: 28, material: .thinMaterial)

                Spacer()
            }
            .padding(34)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

#Preview {
    MacRootView()
}
