//
//  MacTranscriptionSettingsView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import SwiftUI

enum MacTranscriptionSettingsMode {
    case provider
    case model
    case authorizationAndTest
}

struct MacTranscriptionSettingsView: View {
    @ObservedObject var settingsStore: TranscriptionSettingsStore
    let mode: MacTranscriptionSettingsMode

    init(settingsStore: TranscriptionSettingsStore, mode: MacTranscriptionSettingsMode = .provider) {
        self.settingsStore = settingsStore
        self.mode = mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            switch mode {
            case .provider:
                providerSettings
            case .model:
                modelSettings
            case .authorizationAndTest:
                authorizationAndTestSettings
            }
        }
    }

    private var providerSettings: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            RokuricsSettingsGroup(title: "Provider") {
                RokuricsSettingsPickerRow(title: RokuricsCopy.text("转写 Provider", "Transcription"), selection: providerBinding) {
                    ForEach(TranscriptionProviderKind.allCases) { providerKind in
                        Text(providerKind.displayName)
                            .tag(providerKind)
                            .disabled(!providerKind.isEnabledInCurrentBuild)
                    }
                }

                RokuricsSettingsDivider()

                RokuricsSettingsRow(
                    title: RokuricsCopy.text("状态", "Status"),
                    valueText: settingsStore.selectedProviderKind.isEnabledInCurrentBuild
                        ? RokuricsCopy.text("可用", "Available")
                        : RokuricsCopy.text("暂未启用", "Disabled")
                )
            }
        }
    }

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            if settingsStore.selectedProviderKind == .whisperCpp {
                MacWhisperCppSettingsView(settingsStore: settingsStore, mode: .model)
            } else {
                RokuricsSettingsGroup(title: RokuricsCopy.text("模型", "Model")) {
                    RokuricsSettingsRow(title: RokuricsCopy.text("当前模型", "Current"), valueText: "Mock")
                }
            }
        }
    }

    private var authorizationAndTestSettings: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            if settingsStore.selectedProviderKind == .whisperCpp {
                MacWhisperCppSettingsView(settingsStore: settingsStore, mode: .authorizationAndTest)
            } else {
                RokuricsSettingsGroup(title: RokuricsCopy.text("授权与测试", "Access & Test")) {
                    RokuricsSettingsRow(title: "Provider", valueText: "Mock Transcription")
                    RokuricsSettingsDivider()
                    RokuricsSettingsRow(
                        title: RokuricsCopy.text("状态", "Status"),
                        valueText: RokuricsCopy.text("无需外部配置", "No setup needed")
                    )
                }
            }
        }
    }

    private var providerBinding: Binding<TranscriptionProviderKind> {
        Binding {
            settingsStore.selectedProviderKind
        } set: { newValue in
            guard newValue.isEnabledInCurrentBuild else {
                return
            }
            settingsStore.selectedProviderKind = newValue
        }
    }
}
