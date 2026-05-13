//
//  MacTranscriptionSettingsView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import SwiftUI

struct MacTranscriptionSettingsView: View {
    @ObservedObject var settingsStore: TranscriptionSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("转写设置")
                            .font(MacTypography.chineseTitle(size: 24, weight: .bold))
                            .foregroundStyle(MacTheme.deepText(for: colorScheme))

                        Text("选择当前转写 Provider")
                            .font(MacTypography.chineseCaption(size: 12, weight: .medium))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))
                    }

                    Spacer()

                    MacStatusPill(
                        text: settingsStore.selectedProviderDisplayName,
                        systemImage: "waveform.and.magnifyingglass",
                        tint: settingsStore.selectedProviderKind == .mock ? MacTheme.aqua : MacTheme.leaf
                    )
                }

                MacTranscriptionProviderPicker(settingsStore: settingsStore)
            }
            .padding(20)
            .frame(maxWidth: 680, alignment: .leading)
            .macLiquidGlassCard(cornerRadius: 22, material: .thinMaterial, fillOpacity: 0.44, strokeOpacity: 0.40, shadowOpacity: 0.07, shadowRadius: 12, shadowY: 6)

            if settingsStore.selectedProviderKind == .whisperCpp {
                MacWhisperCppSettingsView(settingsStore: settingsStore)
                    .padding(20)
                    .frame(maxWidth: 680, alignment: .leading)
                    .macLiquidGlassCard(cornerRadius: 22, material: .thinMaterial, fillOpacity: 0.44, strokeOpacity: 0.40, shadowOpacity: 0.07, shadowRadius: 12, shadowY: 6)
            }
        }
    }
}

