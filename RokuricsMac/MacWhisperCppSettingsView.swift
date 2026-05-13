//
//  MacWhisperCppSettingsView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import AppKit
import SwiftUI

struct MacWhisperCppSettingsView: View {
    @ObservedObject var settingsStore: TranscriptionSettingsStore
    @State private var isCheckingConfiguration = false
    @State private var saveMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("whisper.cpp 配置")
                        .font(MacTypography.chineseHeadline(size: 17))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))

                    Text("由你手动选择本机可执行文件和模型文件")
                        .font(MacTypography.chineseCaption(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                }

                Spacer()

                MacStatusPill(
                    text: settingsStore.lastValidationStatus.displayText,
                    systemImage: validationIcon,
                    tint: validationTint
                )
            }

            VStack(spacing: 12) {
                pathRow(
                    title: "可执行文件路径",
                    value: executablePathBinding,
                    placeholder: "/path/to/whisper.cpp/main",
                    buttonTitle: "选择文件",
                    action: chooseExecutable
                )

                pathRow(
                    title: "模型文件路径",
                    value: modelPathBinding,
                    placeholder: "/path/to/ggml-model.bin",
                    buttonTitle: "选择模型",
                    action: chooseModel
                )

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("默认语言")
                            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))

                        TextField("auto / zh / en", text: languageBinding)
                            .font(MacTypography.technical(size: 13, weight: .semibold))
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(fieldBackground)
                    }
                    .frame(width: 180, alignment: .leading)

                    Toggle(isOn: preferSegmentOutputBinding) {
                        Text("尝试读取 JSON segments")
                            .font(MacTypography.chineseBody(size: 13, weight: .semibold))
                            .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    }
                    .toggleStyle(.switch)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 10) {
                Button {
                    checkConfiguration()
                } label: {
                    Label(isCheckingConfiguration ? "检查中" : "检查配置", systemImage: "checkmark.shield")
                        .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .macGlassCapsule(fillOpacity: 0.40, strokeOpacity: 0.34)
                }
                .buttonStyle(.plain)
                .disabled(isCheckingConfiguration)

                Button {
                    settingsStore.persist()
                    saveMessage = "已保存"
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                        .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .macGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.30)
                }
                .buttonStyle(.plain)

                if let saveMessage {
                    Text(saveMessage)
                        .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.leaf)
                }

                Spacer()
            }

            Text(settingsStore.lastValidationMessage)
                .font(MacTypography.chineseCaption(size: 12, weight: .medium))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }

    private var executablePathBinding: Binding<String> {
        Binding {
            settingsStore.whisperConfiguration.executablePath
        } set: { value in
            saveMessage = nil
            settingsStore.updateWhisperConfiguration { $0.executablePath = value }
        }
    }

    private var modelPathBinding: Binding<String> {
        Binding {
            settingsStore.whisperConfiguration.modelPath
        } set: { value in
            saveMessage = nil
            settingsStore.updateWhisperConfiguration { $0.modelPath = value }
        }
    }

    private var languageBinding: Binding<String> {
        Binding {
            settingsStore.whisperConfiguration.defaultLanguage
        } set: { value in
            saveMessage = nil
            settingsStore.updateWhisperConfiguration { $0.defaultLanguage = value }
        }
    }

    private var preferSegmentOutputBinding: Binding<Bool> {
        Binding {
            settingsStore.whisperConfiguration.preferSegmentOutput
        } set: { value in
            saveMessage = nil
            settingsStore.updateWhisperConfiguration { $0.preferSegmentOutput = value }
        }
    }

    private var validationTint: Color {
        switch settingsStore.lastValidationStatus {
        case .valid:
            return MacTheme.leaf
        case .notConfigured:
            return MacTheme.amber
        default:
            return MacTheme.coral
        }
    }

    private var validationIcon: String {
        settingsStore.lastValidationStatus == .valid ? "checkmark" : "exclamationmark.triangle"
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(MacTheme.glassSurface(for: colorScheme).opacity(0.32))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.32), lineWidth: 1)
            }
    }

    private func pathRow(
        title: String,
        value: Binding<String>,
        placeholder: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))

            HStack(spacing: 10) {
                TextField(placeholder, text: value)
                    .font(MacTypography.technical(size: 12, weight: .medium))
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(fieldBackground)

                Button(action: action) {
                    Label(buttonTitle, systemImage: "folder")
                        .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .macGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.30)
                }
                .buttonStyle(.plain)
                .frame(width: 108)
            }
        }
    }

    private func chooseExecutable() {
        chooseFile { url in
            settingsStore.updateWhisperConfiguration { $0.executablePath = url.path }
            saveMessage = nil
        }
    }

    private func chooseModel() {
        chooseFile { url in
            settingsStore.updateWhisperConfiguration { $0.modelPath = url.path }
            saveMessage = nil
        }
    }

    private func chooseFile(onSelection: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.prompt = "选择"

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        onSelection(url)
    }

    private func checkConfiguration() {
        guard !isCheckingConfiguration else {
            return
        }

        isCheckingConfiguration = true
        saveMessage = nil

        let configuration = settingsStore.whisperConfiguration
        Task {
            let result = await TranscriptionConfigurationValidator().validateWhisperCpp(configuration)
            await MainActor.run {
                settingsStore.updateValidation(status: result.status, message: result.message)
                isCheckingConfiguration = false
            }
        }
    }
}
