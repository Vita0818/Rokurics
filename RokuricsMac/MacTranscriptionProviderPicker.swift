//
//  MacTranscriptionProviderPicker.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import SwiftUI

struct MacTranscriptionProviderPicker: View {
    @ObservedObject var settingsStore: TranscriptionSettingsStore
    @Environment(\.colorScheme) private var colorScheme

    private let visibleProviders: [TranscriptionProviderKind] = [.mock, .whisperCpp]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(visibleProviders) { provider in
                Button {
                    settingsStore.selectedProviderKind = provider
                    if provider == .mock {
                        settingsStore.updateValidation(
                            status: .valid,
                            message: "Mock Transcription 无需外部配置"
                        )
                    } else if settingsStore.whisperConfiguration.normalizedExecutablePath.isEmpty
                        || settingsStore.whisperConfiguration.normalizedModelPath.isEmpty {
                        settingsStore.updateValidation(
                            status: .notConfigured,
                            message: "请配置 whisper.cpp 可执行文件路径和模型文件路径"
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: iconName(for: provider))
                            .font(.system(size: 13, weight: .semibold))

                        Text(provider.displayName)
                            .font(MacTypography.englishBody(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(settingsStore.selectedProviderKind == provider ? .white : MacTheme.deepText(for: colorScheme))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(settingsStore.selectedProviderKind == provider ? AnyShapeStyle(MacTheme.accentGradient) : AnyShapeStyle(MacTheme.glassSurface(for: colorScheme).opacity(0.34)))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.34), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func iconName(for provider: TranscriptionProviderKind) -> String {
        switch provider {
        case .mock:
            return "wand.and.stars"
        case .whisperCpp:
            return "terminal"
        case .mlxWhisper, .localHTTP, .cloudAPI, .customCommand:
            return "clock"
        }
    }
}
