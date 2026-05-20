//
//  MacNoteGenerationSettingsView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import SwiftUI

enum MacNoteGenerationSettingsMode {
    case provider
    case model
    case api
    case test
}

struct MacNoteGenerationSettingsView: View {
    @ObservedObject var settingsStore: NoteGenerationSettingsStore
    let mode: MacNoteGenerationSettingsMode
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

    init(settingsStore: NoteGenerationSettingsStore, mode: MacNoteGenerationSettingsMode = .provider) {
        self.settingsStore = settingsStore
        self.mode = mode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            switch mode {
            case .provider:
                aiProviderGroup
            case .model:
                aiModelGroup
            case .api:
                aiAPIGroup
            case .test:
                aiTestGroup
            }
        }
        .onAppear(perform: syncDrafts)
    }

    private var aiProviderGroup: some View {
        RokuricsSettingsGroup(title: "Provider") {
            RokuricsSettingsPickerRow(title: "AI Provider", selection: providerKindBinding) {
                ForEach(NoteGenerationProviderKind.allCases) { providerKind in
                    Text(providerKind.displayName).tag(providerKind)
                }
            }

            RokuricsSettingsDivider()
            RokuricsSettingsRow(
                title: "状态",
                valueText: providerKindDraft == .mock ? "本地" : "需配置"
            )

            RokuricsSettingsDivider()
            RokuricsSettingsActionRow(
                title: "保存设置",
                valueText: diagnosticMessage == "配置已保存" ? "已保存" : "",
                systemImage: "square.and.arrow.down",
                tint: MacTheme.leaf,
                action: saveConfiguration
            )
        }
    }

    private var aiModelGroup: some View {
        RokuricsSettingsGroup(title: "模型") {
            RokuricsSettingsRow(title: "当前模型", valueText: currentModelSummary)

            if providerKindDraft != .mock {
                if !currentModelCandidates.isEmpty {
                    RokuricsSettingsDivider()
                    RokuricsSettingsPickerRow(title: "模型候选", selection: modelNameBinding) {
                        ForEach(currentModelCandidates, id: \.self) { modelName in
                            Text(modelName).tag(modelName)
                        }
                    }
                }

                RokuricsSettingsDivider()
                RokuricsSettingsTextFieldRow(
                    title: "手动模型名",
                    placeholder: modelPlaceholder,
                    text: modelNameBinding
                )

                if supportsModelRefresh {
                    RokuricsSettingsDivider()
                    RokuricsSettingsActionRow(
                        title: activeDiagnostic == .models ? "刷新中" : "刷新模型",
                        valueText: modelCandidateSummary,
                        systemImage: "arrow.clockwise",
                        isDisabled: activeDiagnostic != nil
                    ) {
                        runDiagnostic(.models)
                    }
                }

                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: "保存设置",
                    valueText: diagnosticMessage == "配置已保存" ? "已保存" : "",
                    systemImage: "square.and.arrow.down",
                    tint: MacTheme.leaf,
                    action: saveConfiguration
                )
            }
        }
    }

    private var aiAPIGroup: some View {
        RokuricsSettingsGroup(title: "API 设置") {
            if providerKindDraft == .openAICompatible {
                RokuricsSettingsPickerRow(title: "Preset", selection: providerPresetBinding) {
                    ForEach(AIProviderPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                RokuricsSettingsDivider()
            }

            RokuricsSettingsRow(
                title: "Provider",
                valueText: providerKindDraft.displayName
            )

            if providerKindDraft != .mock {
                RokuricsSettingsDivider()
                RokuricsSettingsTextFieldRow(
                    title: "Base URL",
                    placeholder: baseURLPlaceholder,
                    text: baseURLBinding,
                    isTechnical: true
                )

                RokuricsSettingsDivider()
                RokuricsSettingsSecureFieldRow(
                    title: "API Key",
                    placeholder: apiKeyPlaceholder,
                    text: apiKeyBinding
                )

                if providerKindDraft == .anthropicMessages {
                    RokuricsSettingsDivider()
                    RokuricsSettingsTextFieldRow(
                        title: "Version",
                        placeholder: "2023-06-01",
                        text: $anthropicVersionDraft,
                        isTechnical: true
                    )
                }
            }

            RokuricsSettingsDivider()
            RokuricsSettingsActionRow(
                title: "保存设置",
                valueText: diagnosticMessage == "配置已保存" ? "已保存" : "",
                systemImage: "square.and.arrow.down",
                tint: MacTheme.leaf,
                action: saveConfiguration
            )
        }
    }

    private var aiTestGroup: some View {
        RokuricsSettingsGroup(title: "测试") {
            if providerKindDraft == .mock {
                RokuricsSettingsRow(title: "状态", valueText: "Mock provider 本地可用")
            } else {
                RokuricsSettingsActionRow(
                    title: activeDiagnostic == .connection ? "测试中" : "测试连接",
                    valueText: "",
                    systemImage: DiagnosticAction.connection.systemImage,
                    isDisabled: activeDiagnostic != nil
                ) {
                    runDiagnostic(.connection)
                }

                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: activeDiagnostic == .model ? "测试中" : "测试模型",
                    valueText: "",
                    systemImage: DiagnosticAction.model.systemImage,
                    isDisabled: activeDiagnostic != nil
                ) {
                    runDiagnostic(.model)
                }

                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: activeDiagnostic == .generation ? "测试中" : "测试生成",
                    valueText: "",
                    systemImage: DiagnosticAction.generation.systemImage,
                    isDisabled: activeDiagnostic != nil
                ) {
                    runDiagnostic(.generation)
                }

                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: "保存设置",
                    valueText: diagnosticMessage == "配置已保存" ? "已保存" : "",
                    systemImage: "square.and.arrow.down",
                    tint: MacTheme.leaf,
                    action: saveConfiguration
                )
            }

            if let diagnosticMessage {
                RokuricsSettingsDivider()
                RokuricsSettingsRow(
                    title: "结果",
                    valueText: diagnosticMessage,
                    systemImage: diagnosticIsSuccess ? "checkmark.circle" : "exclamationmark.triangle",
                    tint: diagnosticIsSuccess ? MacTheme.leaf : MacTheme.coral
                )
            }
        }
    }

    private var providerKindBinding: Binding<NoteGenerationProviderKind> {
        Binding {
            providerKindDraft
        } set: { newValue in
            providerKindDraft = newValue
            diagnosticMessage = nil
        }
    }

    private var currentModelSummary: String {
        switch providerKindDraft {
        case .mock:
            return "mock-note-local"
        case .openAICompatible:
            return compactValue(modelNameDraft, fallback: "未选择模型")
        case .anthropicMessages:
            return compactValue(anthropicModelNameDraft, fallback: "未选择模型")
        }
    }

    private var modelCandidateSummary: String {
        let count = currentModelCandidates.count
        return count > 0 ? "\(count) 个" : ""
    }

    private var currentModelCandidates: [String] {
        switch providerKindDraft {
        case .mock:
            return []
        case .openAICompatible:
            return modelPickerCandidates
        case .anthropicMessages:
            return anthropicModelPickerCandidates
        }
    }

    private var baseURLPlaceholder: String {
        switch providerKindDraft {
        case .mock:
            return ""
        case .openAICompatible:
            return "http://127.0.0.1:1234/v1"
        case .anthropicMessages:
            return "https://api.anthropic.com"
        }
    }

    private var modelPlaceholder: String {
        switch providerKindDraft {
        case .mock:
            return "mock-note-local"
        case .openAICompatible:
            return "google/gemma-4-e4b"
        case .anthropicMessages:
            return "claude-sonnet-4-6"
        }
    }

    private var apiKeyPlaceholder: String {
        providerKindDraft == .anthropicMessages ? "必填" : "可选"
    }

    private var baseURLBinding: Binding<String> {
        Binding {
            switch providerKindDraft {
            case .mock:
                return ""
            case .openAICompatible:
                return baseURLDraft
            case .anthropicMessages:
                return anthropicBaseURLDraft
            }
        } set: { value in
            switch providerKindDraft {
            case .mock:
                break
            case .openAICompatible:
                baseURLDraft = value
            case .anthropicMessages:
                anthropicBaseURLDraft = value
            }
            diagnosticMessage = nil
        }
    }

    private var modelNameBinding: Binding<String> {
        Binding {
            switch providerKindDraft {
            case .mock:
                return "mock-note-local"
            case .openAICompatible:
                return modelNameDraft
            case .anthropicMessages:
                return anthropicModelNameDraft
            }
        } set: { value in
            switch providerKindDraft {
            case .mock:
                break
            case .openAICompatible:
                modelNameDraft = value
            case .anthropicMessages:
                anthropicModelNameDraft = value
            }
            diagnosticMessage = nil
        }
    }

    private var apiKeyBinding: Binding<String> {
        Binding {
            switch providerKindDraft {
            case .mock:
                return ""
            case .openAICompatible:
                return apiKeyDraft
            case .anthropicMessages:
                return anthropicAPIKeyDraft
            }
        } set: { value in
            switch providerKindDraft {
            case .mock:
                break
            case .openAICompatible:
                apiKeyDraft = value
            case .anthropicMessages:
                anthropicAPIKeyDraft = value
            }
            diagnosticMessage = nil
        }
    }

    private func compactValue(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
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

    private enum DiagnosticAction: Equatable {
        case models
        case connection
        case model
        case generation

        var systemImage: String {
            switch self {
            case .models:
                return "arrow.clockwise"
            case .connection:
                return "network"
            case .model:
                return "cpu"
            case .generation:
                return "sparkles"
            }
        }
    }

}
