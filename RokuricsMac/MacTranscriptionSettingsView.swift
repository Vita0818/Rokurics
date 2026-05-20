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
                RokuricsSettingsPickerRow(title: "转写 Provider", selection: providerBinding) {
                    ForEach(TranscriptionProviderKind.allCases) { providerKind in
                        Text(providerKind.displayName)
                            .tag(providerKind)
                            .disabled(!providerKind.isEnabledInCurrentBuild)
                    }
                }

                RokuricsSettingsDivider()

                RokuricsSettingsRow(
                    title: "状态",
                    valueText: settingsStore.selectedProviderKind.isEnabledInCurrentBuild ? "可用" : "暂未启用"
                )
            }
        }
    }

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            if settingsStore.selectedProviderKind == .whisperCpp {
                MacWhisperCppSettingsView(settingsStore: settingsStore, mode: .model)
            } else {
                RokuricsSettingsGroup(title: "模型") {
                    RokuricsSettingsRow(title: "当前模型", valueText: "Mock")
                }
            }
        }
    }

    private var authorizationAndTestSettings: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            if settingsStore.selectedProviderKind == .whisperCpp {
                MacWhisperCppSettingsView(settingsStore: settingsStore, mode: .authorizationAndTest)
            } else {
                RokuricsSettingsGroup(title: "授权与测试") {
                    RokuricsSettingsRow(title: "Provider", valueText: "Mock Transcription")
                    RokuricsSettingsDivider()
                    RokuricsSettingsRow(title: "状态", valueText: "无需外部配置")
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
