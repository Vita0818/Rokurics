//
//  IPhoneSettingsView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import SwiftUI

struct IPhoneSettingsView: View {
    @ObservedObject var userProfileStore: UserProfileStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var aiSettingsStore = IPhoneAISettingsStore()
    @State private var activeDetail: IPhoneSettingsDetail?
    @State private var isEditingProfile = false
    @State private var isPrivacyPresented = false

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            RokuricsColors.pageGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        profileSummary
                            .padding(.top, 8)
                            .padding(.bottom, 6)

                        transcriptionSection
                        aiSection
                        aboutSection
                    }
                    .padding(.horizontal, RokuricsMobilePageLayoutMetrics.horizontalPadding)
                    .padding(.bottom, 34)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isEditingProfile) {
            IPhoneEditProfileView(profile: userProfileStore.profile) { displayName, handle, avatar in
                userProfileStore.update(displayName: displayName, handle: handle, avatar: avatar)
            }
        }
        .sheet(item: $activeDetail) { detail in
            IPhoneSettingsDetailSheet(title: detail.title) {
                detailContent(for: detail)
            }
        }
        .alert("隐私政策", isPresented: $isPrivacyPresented) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("Rokurics 只在用户显式触发时调用 AI。API Key 保存在本机设置中，不写入学习库、聊天上下文或日志。")
        }
    }

    private var header: some View {
        RokuricsMobilePageHeader(
            leading: {
                RokuricsMobileBackButton(tint: RokuricsColors.deepText) {
                    dismiss()
                }
            },
            trailing: {
                EmptyView()
            }
        ) {
            RokuricsText("设置", token: .pageTitle, size: RokuricsMobilePageLayoutMetrics.titleSize, weight: .bold)
                .foregroundStyle(RokuricsColors.deepText)
        }
        .padding(.horizontal, RokuricsMobilePageLayoutMetrics.horizontalPadding)
        .padding(.top, RokuricsMobilePageLayoutMetrics.topPadding)
        .padding(.bottom, RokuricsMobilePageLayoutMetrics.headerBottomSpacing)
        .frame(maxWidth: RokuricsMobilePageLayoutMetrics.maxContentWidth)
        .frame(maxWidth: .infinity)
    }

    private var profileSummary: some View {
        VStack(spacing: 12) {
            IPhoneSettingsAvatar(profile: userProfileStore.profile, size: 86)

            VStack(spacing: 4) {
                RokuricsText(userProfileStore.profile.displayName, token: .pageTitle, size: 28, weight: .semibold)
                    .foregroundStyle(RokuricsColors.deepText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                RokuricsText(userProfileStore.profile.displayHandle, token: .body, size: 15, weight: .medium)
                    .foregroundStyle(RokuricsColors.softText)
                    .lineLimit(1)
            }

            Button {
                isEditingProfile = true
            } label: {
                Text("编辑个人资料")
                    .font(RokuricsTypography.button(size: 16))
                    .foregroundStyle(RokuricsColors.deepText)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 13)
                    .rokuricsGlassCapsule(fillOpacity: 0.36, strokeOpacity: 0.40, shadowOpacity: 0.08, shadowRadius: 13, shadowY: 7)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private var transcriptionSection: some View {
        IPhoneSettingsSectionCard(title: "转写") {
            IPhoneSettingsListRow(title: "Provider", valueText: "Mac 安全转写") {
                activeDetail = .transcriptionProvider
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: "模型", valueText: "whisper.cpp") {
                activeDetail = .transcriptionModel
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: "授权与测试", valueText: "查看") {
                activeDetail = .transcriptionAuthorization
            }
        }
    }

    private var aiSection: some View {
        IPhoneSettingsSectionCard(title: "AI") {
            IPhoneSettingsListRow(title: "Provider", valueText: aiSettingsStore.providerDisplayName) {
                activeDetail = .aiProvider
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: "模型", valueText: aiSettingsStore.modelDisplayName) {
                activeDetail = .aiModel
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: "API 设置", valueText: "查看") {
                activeDetail = .aiAPI
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: "测试", valueText: "查看") {
                activeDetail = .aiTest
            }
        }
    }

    private var aboutSection: some View {
        IPhoneSettingsSectionCard(title: "关于") {
            IPhoneSettingsListRow(title: "存储", valueText: "本机") {
                activeDetail = .storage
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: "隐私政策", valueText: "") {
                isPrivacyPresented = true
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: "版权", valueText: versionText, showsChevron: false)
        }
    }

    @ViewBuilder
    private func detailContent(for detail: IPhoneSettingsDetail) -> some View {
        switch detail {
        case .transcriptionProvider:
            IPhoneTranscriptionSettingsDetail(mode: .provider)
        case .transcriptionModel:
            IPhoneTranscriptionSettingsDetail(mode: .model)
        case .transcriptionAuthorization:
            IPhoneTranscriptionSettingsDetail(mode: .authorization)
        case .aiProvider:
            IPhoneAISettingsDetailView(settingsStore: aiSettingsStore, mode: .provider)
        case .aiModel:
            IPhoneAISettingsDetailView(settingsStore: aiSettingsStore, mode: .model)
        case .aiAPI:
            IPhoneAISettingsDetailView(settingsStore: aiSettingsStore, mode: .api)
        case .aiTest:
            IPhoneAISettingsDetailView(settingsStore: aiSettingsStore, mode: .test)
        case .storage:
            IPhoneSettingsSectionCard(title: "存储") {
                IPhoneSettingsStaticRow(title: "学习库", valueText: "本机 App 数据")
                IPhoneSettingsDivider()
                IPhoneSettingsStaticRow(title: "API Key", valueText: "本机设置")
            }
        }
    }
}

private enum IPhoneSettingsDetail: String, Identifiable {
    case transcriptionProvider
    case transcriptionModel
    case transcriptionAuthorization
    case aiProvider
    case aiModel
    case aiAPI
    case aiTest
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcriptionProvider:
            return "转写 Provider"
        case .transcriptionModel:
            return "转写模型"
        case .transcriptionAuthorization:
            return "授权与测试"
        case .aiProvider:
            return "AI Provider"
        case .aiModel:
            return "AI 模型"
        case .aiAPI:
            return "API 设置"
        case .aiTest:
            return "测试"
        case .storage:
            return "存储"
        }
    }
}

private struct IPhoneSettingsSectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RokuricsText(title, token: .secondary, size: 13, weight: .semibold)
                .foregroundStyle(RokuricsColors.softText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .rokuricsLiquidGlassCard(
                cornerRadius: 28,
                material: .thinMaterial,
                fillOpacity: 0.32,
                strokeOpacity: 0.34,
                shadowOpacity: 0.08,
                shadowRadius: 15,
                shadowY: 8
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IPhoneSettingsListRow: View {
    let title: String
    let valueText: String
    var showsChevron = true
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            RokuricsText(title, token: .body, size: 16, weight: .semibold)
                .foregroundStyle(RokuricsColors.deepText)
                .lineLimit(1)
                .minimumScaleFactor(0.84)

            Spacer(minLength: 12)

            if !valueText.isEmpty {
                RokuricsText(valueText, token: .body, size: 16, weight: .semibold)
                    .foregroundStyle(showsChevron ? RokuricsColors.aqua : RokuricsColors.softText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RokuricsColors.tertiaryText)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 58)
        .contentShape(Rectangle())
    }
}

private struct IPhoneSettingsStaticRow: View {
    let title: String
    let valueText: String

    var body: some View {
        IPhoneSettingsListRow(title: title, valueText: valueText, showsChevron: false)
    }
}

private struct IPhoneSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(RokuricsColors.softText.opacity(0.12))
            .frame(height: 1)
            .padding(.leading, 18)
    }
}

private struct IPhoneSettingsAvatar: View {
    let profile: UserProfile
    let size: CGFloat

    var body: some View {
        Image(systemName: profile.avatar)
            .font(.system(size: size * 0.82, weight: .regular))
            .foregroundStyle(RokuricsColors.aqua, .white.opacity(0.88))
            .frame(width: size, height: size)
            .padding(5)
            .rokuricsGlassCircle(fillOpacity: 0.36, strokeOpacity: 0.50, shadowOpacity: 0.14, shadowRadius: 14, shadowY: 8)
    }
}

private struct IPhoneSettingsDetailSheet<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.dismiss) private var dismiss

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            RokuricsColors.pageGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                RokuricsMobilePageHeader(
                    leading: {
                        RokuricsMobileBackButton(tint: RokuricsColors.deepText) {
                            dismiss()
                        }
                    },
                    trailing: {
                        EmptyView()
                    }
                ) {
                    RokuricsText(title, token: .pageTitle, size: RokuricsMobilePageLayoutMetrics.titleSize, weight: .bold)
                        .foregroundStyle(RokuricsColors.deepText)
                }
                .padding(.horizontal, RokuricsMobilePageLayoutMetrics.horizontalPadding)
                .padding(.top, RokuricsMobilePageLayoutMetrics.topPadding)
                .padding(.bottom, RokuricsMobilePageLayoutMetrics.headerBottomSpacing)

                ScrollView(showsIndicators: false) {
                    content
                        .padding(.horizontal, RokuricsMobilePageLayoutMetrics.horizontalPadding)
                        .padding(.bottom, 30)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private enum IPhoneTranscriptionSettingsMode {
    case provider
    case model
    case authorization
}

private struct IPhoneTranscriptionSettingsDetail: View {
    let mode: IPhoneTranscriptionSettingsMode

    var body: some View {
        switch mode {
        case .provider:
            IPhoneSettingsSectionCard(title: "Provider") {
                IPhoneSettingsStaticRow(title: "转写 Provider", valueText: "Mac 安全转写")
            }
        case .model:
            IPhoneSettingsSectionCard(title: "模型") {
                IPhoneSettingsStaticRow(title: "当前模型", valueText: "whisper.cpp")
                IPhoneSettingsDivider()
                IPhoneSettingsStaticRow(title: "配置位置", valueText: "Mac")
            }
        case .authorization:
            IPhoneSettingsSectionCard(title: "授权与测试") {
                IPhoneSettingsStaticRow(title: "授权", valueText: "安全配对")
                IPhoneSettingsDivider()
                IPhoneSettingsStaticRow(title: "上传", valueText: "用户显式触发")
            }
        }
    }
}

private enum IPhoneAISettingsMode {
    case provider
    case model
    case api
    case test
}

private struct IPhoneAISettingsDetailView: View {
    @ObservedObject var settingsStore: IPhoneAISettingsStore
    let mode: IPhoneAISettingsMode
    @State private var providerKindDraft: NoteGenerationProviderKind = .openAICompatible
    @State private var presetDraft: AIProviderPreset = .openAI
    @State private var openAIBaseURLDraft = ""
    @State private var openAIModelDraft = ""
    @State private var openAIAPIKeyDraft = ""
    @State private var anthropicBaseURLDraft = ""
    @State private var anthropicModelDraft = ""
    @State private var anthropicAPIKeyDraft = ""
    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch mode {
            case .provider:
                providerSection
            case .model:
                modelSection
            case .api:
                apiSection
            case .test:
                testSection
            }
        }
        .onAppear(perform: loadDrafts)
    }

    private var providerSection: some View {
        IPhoneSettingsSectionCard(title: "Provider") {
            Picker("AI Provider", selection: $providerKindDraft) {
                ForEach(NoteGenerationProviderKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .frame(minHeight: 58)
            .onChange(of: providerKindDraft) { _, _ in saveDrafts() }
        }
    }

    private var modelSection: some View {
        IPhoneSettingsSectionCard(title: "模型") {
            if providerKindDraft == .openAICompatible {
                Picker("Preset", selection: $presetDraft) {
                    ForEach(AIProviderPreset.iPhoneVisibleCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 18)
                .frame(minHeight: 58)
                .onChange(of: presetDraft) { _, newValue in
                    let updated = newValue.applyingDefaults(to: openAIConfigurationDraft)
                    openAIBaseURLDraft = updated.baseURLString
                    openAIModelDraft = updated.modelName
                    saveDrafts()
                }

                IPhoneSettingsDivider()
                IPhoneSettingsTextFieldRow(title: "模型", text: $openAIModelDraft, onSubmit: saveDrafts)
            } else {
                IPhoneSettingsTextFieldRow(title: "模型", text: $anthropicModelDraft, onSubmit: saveDrafts)
            }
        }
    }

    private var apiSection: some View {
        IPhoneSettingsSectionCard(title: "API 设置") {
            if providerKindDraft == .openAICompatible {
                IPhoneSettingsTextFieldRow(title: "Endpoint", text: $openAIBaseURLDraft, isTechnical: true, onSubmit: saveDrafts)
                IPhoneSettingsDivider()
                IPhoneSettingsSecureFieldRow(title: "API Key", text: $openAIAPIKeyDraft, onSubmit: saveDrafts)
            } else {
                IPhoneSettingsTextFieldRow(title: "Endpoint", text: $anthropicBaseURLDraft, isTechnical: true, onSubmit: saveDrafts)
                IPhoneSettingsDivider()
                IPhoneSettingsSecureFieldRow(title: "API Key", text: $anthropicAPIKeyDraft, onSubmit: saveDrafts)
            }
        }
    }

    private var testSection: some View {
        IPhoneSettingsSectionCard(title: "测试") {
            IPhoneSettingsListRow(title: "检查配置", valueText: validationMessage ?? "本机检查") {
                validationMessage = configurationIsReady ? "可用" : "未完整"
                saveDrafts()
            }
        }
    }

    private var configurationIsReady: Bool {
        switch providerKindDraft {
        case .openAICompatible:
            let config = openAIConfigurationDraft
            return !config.trimmedBaseURLString.isEmpty
                && !config.trimmedModelName.isEmpty
                && (!presetDraft.requiresAPIKeyOnIPhone || !config.trimmedAPIKey.isEmpty)
        case .anthropicMessages:
            let config = anthropicConfigurationDraft
            return !config.trimmedBaseURLString.isEmpty
                && !config.trimmedModelName.isEmpty
                && !config.trimmedAPIKey.isEmpty
        }
    }

    private var openAIConfigurationDraft: OpenAICompatibleNoteGenerationConfiguration {
        OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: openAIBaseURLDraft,
            modelName: openAIModelDraft,
            apiKey: openAIAPIKeyDraft,
            temperature: settingsStore.openAIConfiguration.temperature,
            maxTokens: settingsStore.openAIConfiguration.maxTokens,
            maxTranscriptCharacters: settingsStore.openAIConfiguration.maxTranscriptCharacters
        )
    }

    private var anthropicConfigurationDraft: AnthropicMessagesConfiguration {
        AnthropicMessagesConfiguration(
            baseURLString: anthropicBaseURLDraft,
            modelName: anthropicModelDraft,
            apiKey: anthropicAPIKeyDraft,
            anthropicVersion: settingsStore.anthropicConfiguration.anthropicVersion,
            temperature: settingsStore.anthropicConfiguration.temperature,
            maxTokens: settingsStore.anthropicConfiguration.maxTokens,
            maxTranscriptCharacters: settingsStore.anthropicConfiguration.maxTranscriptCharacters
        )
    }

    private func loadDrafts() {
        providerKindDraft = settingsStore.selectedProviderKind
        presetDraft = settingsStore.selectedProviderPreset
        openAIBaseURLDraft = settingsStore.openAIConfiguration.baseURLString
        openAIModelDraft = settingsStore.openAIConfiguration.modelName
        openAIAPIKeyDraft = settingsStore.openAIConfiguration.apiKey
        anthropicBaseURLDraft = settingsStore.anthropicConfiguration.baseURLString
        anthropicModelDraft = settingsStore.anthropicConfiguration.modelName
        anthropicAPIKeyDraft = settingsStore.anthropicConfiguration.apiKey
    }

    private func saveDrafts() {
        switch providerKindDraft {
        case .openAICompatible:
            settingsStore.updateOpenAI(preset: presetDraft, configuration: openAIConfigurationDraft)
        case .anthropicMessages:
            settingsStore.updateAnthropic(configuration: anthropicConfigurationDraft)
        }
    }
}

private struct IPhoneSettingsTextFieldRow: View {
    let title: String
    @Binding var text: String
    var isTechnical = false
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RokuricsText(title, token: .body, size: 16, weight: .semibold)
                .foregroundStyle(RokuricsColors.deepText)

            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(isTechnical ? RokuricsTypography.font(for: .technical) : RokuricsTypography.font(for: .chatInput))
                .foregroundStyle(RokuricsColors.deepText)
                .multilineTextAlignment(.trailing)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
    }
}

private struct IPhoneSettingsSecureFieldRow: View {
    let title: String
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RokuricsText(title, token: .body, size: 16, weight: .semibold)
                .foregroundStyle(RokuricsColors.deepText)

            SecureField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(RokuricsTypography.font(for: .chatInput))
                .foregroundStyle(RokuricsColors.deepText)
                .multilineTextAlignment(.trailing)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
    }
}

private struct IPhoneEditProfileView: View {
    let profile: UserProfile
    let onSave: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var handle: String
    @State private var avatar: String

    private let avatarChoices = [
        "person.crop.circle.fill",
        "graduationcap.circle.fill",
        "book.circle.fill",
        "sparkles"
    ]

    init(profile: UserProfile, onSave: @escaping (String, String, String) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _displayName = State(initialValue: profile.displayName)
        _handle = State(initialValue: profile.handle)
        _avatar = State(initialValue: profile.avatar)
    }

    var body: some View {
        ZStack {
            RokuricsColors.pageGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                RokuricsMobilePageHeader(
                    leading: {
                        RokuricsMobileBackButton(tint: RokuricsColors.deepText) {
                            dismiss()
                        }
                    },
                    trailing: {
                        Button("保存", action: save)
                            .font(RokuricsTypography.button(size: 16))
                            .foregroundStyle(RokuricsColors.aqua)
                            .frame(minWidth: RokuricsIconButtonMetrics.size, minHeight: RokuricsIconButtonMetrics.size, alignment: .trailing)
                    }
                ) {
                    RokuricsText("编辑个人资料", token: .pageTitle, size: RokuricsMobilePageLayoutMetrics.titleSize, weight: .bold)
                        .foregroundStyle(RokuricsColors.deepText)
                }
                .padding(.horizontal, RokuricsMobilePageLayoutMetrics.horizontalPadding)
                .padding(.top, RokuricsMobilePageLayoutMetrics.topPadding)
                .padding(.bottom, RokuricsMobilePageLayoutMetrics.headerBottomSpacing)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            Image(systemName: avatar)
                                .font(.system(size: 76, weight: .regular))
                                .foregroundStyle(RokuricsColors.aqua, .white.opacity(0.88))
                                .frame(width: 92, height: 92)
                                .padding(5)
                                .rokuricsGlassCircle(fillOpacity: 0.36, strokeOpacity: 0.50, shadowOpacity: 0.14, shadowRadius: 14, shadowY: 8)

                            HStack(spacing: 10) {
                                ForEach(avatarChoices, id: \.self) { systemName in
                                    Button {
                                        avatar = systemName
                                    } label: {
                                        Image(systemName: systemName)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(avatar == systemName ? RokuricsColors.aqua : RokuricsColors.deepText)
                                            .frame(width: RokuricsIconButtonMetrics.size, height: RokuricsIconButtonMetrics.size)
                                            .rokuricsGlassCircle(
                                                fillOpacity: avatar == systemName ? 0.46 : 0.34,
                                                strokeOpacity: avatar == systemName ? 0.54 : 0.34,
                                                shadowOpacity: 0.08,
                                                shadowRadius: 10,
                                                shadowY: 5
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.top, 12)

                        VStack(spacing: 14) {
                            IPhoneProfileTextField(title: "显示名称", text: $displayName)
                            IPhoneProfileTextField(title: "用户 ID", text: $handle)
                        }
                    }
                    .padding(.horizontal, RokuricsMobilePageLayoutMetrics.horizontalPadding)
                    .padding(.bottom, 34)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        onSave(displayName, handle, avatar)
        dismiss()
    }
}

private struct IPhoneProfileTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RokuricsText(title, token: .secondary, size: 14, weight: .semibold)
                .foregroundStyle(RokuricsColors.softText)

            TextField(title, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(RokuricsTypography.font(for: .body))
                .foregroundStyle(RokuricsColors.deepText)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .rokuricsLiquidGlassCard(
                    cornerRadius: 20,
                    material: .thinMaterial,
                    fillOpacity: 0.36,
                    strokeOpacity: 0.30,
                    shadowOpacity: 0.05,
                    shadowRadius: 10,
                    shadowY: 5
                )
        }
    }
}

private extension IPhoneAISettingsStore {
    var providerDisplayName: String {
        switch selectedProviderKind {
        case .openAICompatible:
            return selectedProviderPreset.displayName
        case .anthropicMessages:
            return selectedProviderKind.displayName
        }
    }

    var modelDisplayName: String {
        switch selectedProviderKind {
        case .openAICompatible:
            let model = openAIConfiguration.trimmedModelName
            return model.isEmpty ? "未选择模型" : model
        case .anthropicMessages:
            let model = anthropicConfiguration.trimmedModelName
            return model.isEmpty ? "未选择模型" : model
        }
    }
}

#Preview {
    NavigationStack {
        IPhoneSettingsView(userProfileStore: UserProfileStore())
    }
}
