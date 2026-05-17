//
//  MacNoteGenerationSettingsView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import SwiftUI

struct MacNoteGenerationSettingsView: View {
    @ObservedObject var settingsStore: NoteGenerationSettingsStore
    @State private var providerKindDraft: NoteGenerationProviderKind = .mock
    @State private var providerPresetDraft: AIProviderPreset = .customOpenAICompatible
    @State private var baseURLDraft = ""
    @State private var modelNameDraft = ""
    @State private var apiKeyDraft = ""
    @State private var modelCandidatesDraft: [String] = []
    @State private var anthropicBaseURLDraft = ""
    @State private var anthropicModelNameDraft = ""
    @State private var anthropicAPIKeyDraft = ""
    @State private var anthropicVersionDraft = ""
    @State private var anthropicModelCandidatesDraft: [String] = []
    @State private var diagnosticMessage: String?
    @State private var diagnosticIsSuccess = false
    @State private var activeDiagnostic: DiagnosticAction?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AI 总结")
                .font(MacTypography.chineseHeadline(size: 18))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Text("1516")
                .font(MacTypography.numberBody(size: 10, weight: .medium))
                .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                .opacity(0.72)

            VStack(alignment: .leading, spacing: 14) {
                Picker("Provider", selection: $providerKindDraft) {
                    ForEach(NoteGenerationProviderKind.allCases) { providerKind in
                        Text(providerKind.displayName).tag(providerKind)
                    }
                }
                .pickerStyle(.segmented)

                if providerKindDraft == .openAICompatible {
                    openAICompatibleSettings
                } else if providerKindDraft == .anthropicMessages {
                    anthropicSettings
                } else {
                    Text("Mock provider 无需配置")
                        .font(MacTypography.chineseCaption(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                }

                HStack(spacing: 10) {
                    Button("保存配置", action: saveConfiguration)
                        .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                        .buttonStyle(.plain)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .macGlassCapsule(fillOpacity: 0.32, strokeOpacity: 0.30)

                    if providerKindDraft != .mock {
                        if supportsModelRefresh {
                            diagnosticButton(title: "刷新模型", action: .models)
                        }
                        diagnosticButton(title: "测试连接", action: .connection)
                        diagnosticButton(title: "测试模型", action: .model)
                        diagnosticButton(title: "测试生成", action: .generation)
                    }
                }

                if let diagnosticMessage {
                    Text(diagnosticMessage)
                        .font(MacTypography.chineseCaption(size: 12, weight: .medium))
                        .foregroundStyle(diagnosticIsSuccess ? MacTheme.leaf : MacTheme.coral)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 680, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 22, material: .ultraThinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.05, shadowRadius: 10, shadowY: 5)
        .onAppear(perform: syncDrafts)
    }

    @ViewBuilder
    private var openAICompatibleSettings: some View {
        settingsField(title: "Preset") {
            Picker("Preset", selection: providerPresetBinding) {
                ForEach(AIProviderPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 260, alignment: .leading)
        }

        settingsField(title: "Base URL") {
            TextField("http://127.0.0.1:1234/v1", text: $baseURLDraft)
                .textFieldStyle(.roundedBorder)
                .font(MacTypography.englishBody(size: 13, weight: .medium))
        }

        settingsField(title: "Model") {
            VStack(alignment: .leading, spacing: 8) {
                if !modelPickerCandidates.isEmpty {
                    Picker("Model", selection: $modelNameDraft) {
                        ForEach(modelPickerCandidates, id: \.self) { modelName in
                            Text(modelName).tag(modelName)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 340, alignment: .leading)
                }

                TextField("google/gemma-4-e4b", text: $modelNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(MacTypography.englishBody(size: 13, weight: .medium))
            }
        }

        settingsField(title: "API Key") {
            SecureField("可选", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .font(MacTypography.englishBody(size: 13, weight: .medium))
        }
    }

    @ViewBuilder
    private var anthropicSettings: some View {
        settingsField(title: "Base URL") {
            TextField("https://api.anthropic.com", text: $anthropicBaseURLDraft)
                .textFieldStyle(.roundedBorder)
                .font(MacTypography.englishBody(size: 13, weight: .medium))
        }

        settingsField(title: "Model") {
            VStack(alignment: .leading, spacing: 8) {
                if !anthropicModelPickerCandidates.isEmpty {
                    Picker("Model", selection: $anthropicModelNameDraft) {
                        ForEach(anthropicModelPickerCandidates, id: \.self) { modelName in
                            Text(modelName).tag(modelName)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 340, alignment: .leading)
                }

                TextField("claude-sonnet-4-6", text: $anthropicModelNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(MacTypography.englishBody(size: 13, weight: .medium))
            }
        }

        settingsField(title: "API Key") {
            SecureField("必填", text: $anthropicAPIKeyDraft)
                .textFieldStyle(.roundedBorder)
                .font(MacTypography.englishBody(size: 13, weight: .medium))
        }

        settingsField(title: "Anthropic Version") {
            TextField("2023-06-01", text: $anthropicVersionDraft)
                .textFieldStyle(.roundedBorder)
                .font(MacTypography.englishBody(size: 13, weight: .medium))
        }
    }

    private func settingsField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))

            content()
        }
    }

    private func diagnosticButton(title: String, action: DiagnosticAction) -> some View {
        Button {
            runDiagnostic(action)
        } label: {
            Text(activeDiagnostic == action ? "测试中" : title)
                .font(MacTypography.chineseCaption(size: 12, weight: .bold))
                .lineLimit(1)
                .frame(width: action == .models ? 68 : 58)
                .padding(.vertical, 8)
                .macGlassCapsule(fillOpacity: 0.28, strokeOpacity: 0.28)
        }
        .buttonStyle(.plain)
        .disabled(activeDiagnostic != nil)
    }

    private func syncDrafts() {
        providerKindDraft = settingsStore.selectedProviderKind
        providerPresetDraft = settingsStore.selectedProviderPreset
        baseURLDraft = settingsStore.openAIConfiguration.baseURLString
        modelNameDraft = settingsStore.openAIConfiguration.modelName
        apiKeyDraft = settingsStore.openAIConfiguration.apiKey
        modelCandidatesDraft = settingsStore.cachedModelCandidates
        anthropicBaseURLDraft = settingsStore.anthropicConfiguration.baseURLString
        anthropicModelNameDraft = settingsStore.anthropicConfiguration.modelName
        anthropicAPIKeyDraft = settingsStore.anthropicConfiguration.apiKey
        anthropicVersionDraft = settingsStore.anthropicConfiguration.anthropicVersion
        anthropicModelCandidatesDraft = settingsStore.cachedAnthropicModelCandidates
    }

    private func saveConfiguration() {
        settingsStore.update(
            providerKind: providerKindDraft,
            providerPreset: providerPresetDraft,
            openAIConfiguration: draftConfiguration,
            cachedModelCandidates: modelCandidatesDraft,
            anthropicConfiguration: draftAnthropicConfiguration,
            cachedAnthropicModelCandidates: anthropicModelCandidatesDraft
        )
        diagnosticIsSuccess = true
        diagnosticMessage = "配置已保存"
    }

    private func runDiagnostic(_ action: DiagnosticAction) {
        saveConfiguration()
        activeDiagnostic = action
        diagnosticMessage = "测试中"

        Task {
            let result: NoteGenerationDiagnosticResult
            switch action {
            case .models:
                if providerKindDraft == .anthropicMessages {
                    result = await refreshAnthropicModels()
                } else {
                    result = await refreshOpenAICompatibleModels()
                }
            case .connection:
                if providerKindDraft == .anthropicMessages {
                    result = await settingsStore.testAnthropicConnection(configuration: draftAnthropicConfiguration)
                } else {
                    result = await settingsStore.testConnection(configuration: draftConfiguration)
                }
            case .model:
                if providerKindDraft == .anthropicMessages {
                    result = await settingsStore.testAnthropicModel(configuration: draftAnthropicConfiguration)
                } else {
                    result = await settingsStore.testModel(configuration: draftConfiguration)
                }
            case .generation:
                if providerKindDraft == .anthropicMessages {
                    result = await settingsStore.testAnthropicGeneration(configuration: draftAnthropicConfiguration)
                } else {
                    result = await settingsStore.testGeneration(configuration: draftConfiguration)
                }
            }

            diagnosticIsSuccess = result.isSuccess
            diagnosticMessage = result.message
            activeDiagnostic = nil
        }
    }

    private func applyPreset(_ preset: AIProviderPreset) {
        let updatedConfiguration = preset.applyingDefaults(to: draftConfiguration)
        baseURLDraft = updatedConfiguration.baseURLString
        modelNameDraft = updatedConfiguration.modelName
        apiKeyDraft = updatedConfiguration.apiKey

        if preset == .customOpenAICompatible {
            modelCandidatesDraft = modelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? []
                : [modelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)]
        } else {
            modelCandidatesDraft = preset.defaultModelCandidates
        }

        diagnosticMessage = nil
    }

    private func refreshOpenAICompatibleModels() async -> NoteGenerationDiagnosticResult {
        let refreshResult = await settingsStore.refreshModels(configuration: draftConfiguration)
        if refreshResult.isSuccess {
            modelCandidatesDraft = refreshResult.modelIDs
            if modelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let firstModel = refreshResult.modelIDs.first {
                modelNameDraft = firstModel
            }
            settingsStore.update(
                providerKind: providerKindDraft,
                providerPreset: providerPresetDraft,
                openAIConfiguration: draftConfiguration,
                cachedModelCandidates: modelCandidatesDraft,
                anthropicConfiguration: draftAnthropicConfiguration,
                cachedAnthropicModelCandidates: anthropicModelCandidatesDraft
            )

            let currentModel = modelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = currentModel.isEmpty || refreshResult.modelIDs.contains(currentModel)
                ? ""
                : "，当前模型不在刷新列表中"
            return NoteGenerationDiagnosticResult(
                isSuccess: true,
                message: "\(refreshResult.message)\(suffix)"
            )
        }

        return NoteGenerationDiagnosticResult(
            isSuccess: false,
            message: refreshResult.message
        )
    }

    private func refreshAnthropicModels() async -> NoteGenerationDiagnosticResult {
        let refreshResult = await settingsStore.refreshAnthropicModels(configuration: draftAnthropicConfiguration)
        if refreshResult.isSuccess {
            anthropicModelCandidatesDraft = refreshResult.modelIDs
            if anthropicModelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let firstModel = refreshResult.modelIDs.first {
                anthropicModelNameDraft = firstModel
            }
            settingsStore.update(
                providerKind: providerKindDraft,
                providerPreset: providerPresetDraft,
                openAIConfiguration: draftConfiguration,
                cachedModelCandidates: modelCandidatesDraft,
                anthropicConfiguration: draftAnthropicConfiguration,
                cachedAnthropicModelCandidates: anthropicModelCandidatesDraft
            )

            let currentModel = anthropicModelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = currentModel.isEmpty || refreshResult.modelIDs.contains(currentModel)
                ? ""
                : "，当前模型不在刷新列表中"
            return NoteGenerationDiagnosticResult(
                isSuccess: true,
                message: "\(refreshResult.message)\(suffix)"
            )
        }

        return NoteGenerationDiagnosticResult(
            isSuccess: false,
            message: refreshResult.message
        )
    }

    private var modelPickerCandidates: [String] {
        var seen: Set<String> = []
        let currentModel = modelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([currentModel] + modelCandidatesDraft)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { candidate in
                if seen.contains(candidate) {
                    return false
                }
                seen.insert(candidate)
                return true
            }
    }

    private var anthropicModelPickerCandidates: [String] {
        var seen: Set<String> = []
        let currentModel = anthropicModelNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([currentModel] + anthropicModelCandidatesDraft)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { candidate in
                if seen.contains(candidate) {
                    return false
                }
                seen.insert(candidate)
                return true
            }
    }

    private var supportsModelRefresh: Bool {
        switch providerKindDraft {
        case .mock:
            return false
        case .openAICompatible:
            return providerPresetDraft.supportsModelRefresh
        case .anthropicMessages:
            return true
        }
    }

    private var providerPresetBinding: Binding<AIProviderPreset> {
        Binding(
            get: { providerPresetDraft },
            set: { newPreset in
                providerPresetDraft = newPreset
                applyPreset(newPreset)
            }
        )
    }

    private var draftConfiguration: OpenAICompatibleNoteGenerationConfiguration {
        OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: baseURLDraft,
            modelName: modelNameDraft,
            apiKey: apiKeyDraft
        )
    }

    private var draftAnthropicConfiguration: AnthropicMessagesConfiguration {
        AnthropicMessagesConfiguration(
            baseURLString: anthropicBaseURLDraft,
            modelName: anthropicModelNameDraft,
            apiKey: anthropicAPIKeyDraft,
            anthropicVersion: anthropicVersionDraft
        )
    }

    private enum DiagnosticAction {
        case models
        case connection
        case model
        case generation
    }
}
