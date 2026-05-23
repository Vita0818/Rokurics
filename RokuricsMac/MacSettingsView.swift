//
//  MacSettingsView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import AppKit
import SwiftUI

struct MacSettingsView: View {
    @ObservedObject var audioInboxStore: AudioInboxStore
    @ObservedObject var transcriptionQueue: TranscriptionQueue
    @ObservedObject var transcriptionSettingsStore: TranscriptionSettingsStore
    @ObservedObject var noteGenerationSettingsStore: NoteGenerationSettingsStore
    @ObservedObject var userProfileStore: MacUserProfileStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var activeDetail: MacSettingsDetail?
    @State private var storageOpenError: String?

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            MacDetailContentContainer(maxWidth: 1040, horizontalPadding: 34, topPadding: 30) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("设置")
                        .font(MacTypography.font(for: .pageTitle))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))

                    settingsHome
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $activeDetail) { detail in
            if detail == .profile {
                RokuricsEditProfileSheet(
                    profile: userProfileStore.profile,
                    onSave: { displayName, handle in
                        userProfileStore.update(displayName: displayName, handle: handle)
                    }
                )
            } else {
                RokuricsSettingsDetailSheet(title: detail.title) {
                    detailContent(for: detail)
                }
            }
        }
        .alert("无法打开存储", isPresented: storageErrorBinding) {
            Button("好", role: .cancel) {
                storageOpenError = nil
            }
        } message: {
            Text(storageOpenError ?? "")
        }
    }

    private var settingsHome: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 34) {
                profilePane
                    .frame(width: 270)

                settingsList
                    .frame(maxWidth: 610)
            }

            VStack(alignment: .leading, spacing: 22) {
                profilePane
                settingsList
            }
        }
    }

    private var profilePane: some View {
        MacSettingsProfilePane(
            profile: userProfileStore.profile
        ) {
            activeDetail = .profile
        }
    }

    private var settingsList: some View {
        VStack(spacing: 16) {
            transcriptionGroup
            aiGroup
            aboutGroup
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcriptionGroup: some View {
        MacSettingsHomeGroup(title: MacSettingsSection.transcription.title) {
            MacSettingsHomeRow(
                title: MacSettingsHomeSummary.transcriptionRows[0],
                valueText: transcriptionSettingsStore.selectedProviderDisplayName
            ) {
                activeDetail = .transcriptionProvider
            }

            MacSettingsHomeDivider()

            MacSettingsHomeRow(
                title: MacSettingsHomeSummary.transcriptionRows[1],
                valueText: MacSettingsHomeSummary.transcriptionModelSummary(
                    providerKind: transcriptionSettingsStore.selectedProviderKind,
                    whisperConfiguration: transcriptionSettingsStore.whisperConfiguration
                )
            ) {
                activeDetail = .transcriptionModel
            }

            MacSettingsHomeDivider()

            MacSettingsHomeRow(
                title: MacSettingsHomeSummary.transcriptionRows[2],
                valueText: transcriptionSettingsStore.lastValidationStatus.displayText
            ) {
                activeDetail = .transcriptionAuthorization
            }
        }
    }

    private var aiGroup: some View {
        MacSettingsHomeGroup(title: MacSettingsSection.ai.title) {
            MacSettingsHomeRow(
                title: MacSettingsHomeSummary.aiRows[0],
                valueText: noteGenerationSettingsStore.selectedProviderDisplayName
            ) {
                activeDetail = .aiProvider
            }

            MacSettingsHomeDivider()

            MacSettingsHomeRow(
                title: MacSettingsHomeSummary.aiRows[1],
                valueText: MacSettingsHomeSummary.aiModelSummary(
                    providerKind: noteGenerationSettingsStore.selectedProviderKind,
                    openAIConfiguration: noteGenerationSettingsStore.openAIConfiguration,
                    anthropicConfiguration: noteGenerationSettingsStore.anthropicConfiguration
                )
            ) {
                activeDetail = .aiModel
            }

            MacSettingsHomeDivider()

            MacSettingsHomeRow(title: MacSettingsHomeSummary.aiRows[2], valueText: "查看") {
                activeDetail = .aiAPI
            }

            MacSettingsHomeDivider()

            MacSettingsHomeRow(title: MacSettingsHomeSummary.aiRows[3], valueText: "查看") {
                activeDetail = .aiTest
            }
        }
    }

    private var aboutGroup: some View {
        MacSettingsHomeGroup(title: MacSettingsSection.about.title) {
            MacSettingsHomeRow(title: MacSettingsHomeSummary.aboutRows[0], valueText: "打开") {
                openStorageLocation()
            }

            MacSettingsHomeDivider()

            MacSettingsHomeRow(title: MacSettingsHomeSummary.aboutRows[1], valueText: "查看") {
                activeDetail = .privacyPolicy
            }

            MacSettingsHomeDivider()

            MacSettingsHomeRow(title: MacSettingsHomeSummary.aboutRows[2], valueText: versionText) {
                activeDetail = .copyright
            }
        }
    }

    @ViewBuilder
    private func detailContent(for detail: MacSettingsDetail) -> some View {
        switch detail {
        case .profile:
            EmptyView()
        case .transcriptionProvider:
            MacTranscriptionSettingsView(settingsStore: transcriptionSettingsStore, mode: .provider)
        case .transcriptionModel:
            MacTranscriptionSettingsView(settingsStore: transcriptionSettingsStore, mode: .model)
        case .transcriptionAuthorization:
            MacTranscriptionSettingsView(settingsStore: transcriptionSettingsStore, mode: .authorizationAndTest)
        case .aiProvider:
            MacNoteGenerationSettingsView(settingsStore: noteGenerationSettingsStore, mode: .provider)
        case .aiModel:
            MacNoteGenerationSettingsView(settingsStore: noteGenerationSettingsStore, mode: .model)
        case .aiAPI:
            MacNoteGenerationSettingsView(settingsStore: noteGenerationSettingsStore, mode: .api)
        case .aiTest:
            MacNoteGenerationSettingsView(settingsStore: noteGenerationSettingsStore, mode: .test)
        case .privacyPolicy:
            privacyPolicyDetail
        case .copyright:
            copyrightDetail
        }
    }

    private var privacyPolicyDetail: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            RokuricsSettingsGroup(title: "隐私政策") {
                RokuricsSettingsRow(title: "录音", valueText: "需用户主动开始")
                RokuricsSettingsDivider()
                RokuricsSettingsRow(title: "AI", valueText: "仅在显式触发时调用")
                RokuricsSettingsDivider()
                RokuricsSettingsRow(title: "API Key", valueText: "不写入日志或笔记文件")
            }
        }
    }

    private var copyrightDetail: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            RokuricsSettingsGroup(title: "版权") {
                RokuricsSettingsRow(title: "Rokurics", valueText: "Vela")
                RokuricsSettingsDivider()
                RokuricsSettingsRow(title: "Vitemis", valueText: userProfileStore.profile.displayName)
                RokuricsSettingsDivider()
                RokuricsSettingsRow(title: "Copyright", valueText: "2026")
                RokuricsSettingsDivider()
                RokuricsSettingsRow(title: "Third-party", valueText: "随应用组件保留")
            }
        }
    }

    private var storageErrorBinding: Binding<Bool> {
        Binding {
            storageOpenError != nil
        } set: { isPresented in
            if !isPresented {
                storageOpenError = nil
            }
        }
    }

    private func openStorageLocation() {
        do {
            let storageURL = try MacSettingsStorageLocation.ensureRootExists()
            NSWorkspace.shared.open(storageURL)
        } catch {
            storageOpenError = error.localizedDescription
        }
    }
}

enum MacSettingsSection: String, CaseIterable {
    case userProfile
    case transcription
    case ai
    case about

    var title: String {
        switch self {
        case .userProfile:
            return "用户资料"
        case .transcription:
            return "转写"
        case .ai:
            return "AI"
        case .about:
            return "关于"
        }
    }
}

enum MacSettingsHomeSummary {
    static let sectionOrder: [MacSettingsSection] = [.userProfile, .transcription, .ai, .about]

    static let transcriptionRows = ["Provider", "模型", "授权与测试"]
    static let aiRows = ["Provider", "模型", "API 设置", "测试"]
    static let aboutRows = ["存储", "隐私政策", "版权"]

    static func transcriptionModelSummary(
        providerKind: TranscriptionProviderKind,
        whisperConfiguration: WhisperCppTranscriptionConfiguration
    ) -> String {
        switch providerKind {
        case .whisperCpp:
            return whisperConfiguration.currentModelDisplayName
        default:
            return providerKind.displayName
        }
    }

    static func aiModelSummary(
        providerKind: NoteGenerationProviderKind,
        openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration,
        anthropicConfiguration: AnthropicMessagesConfiguration
    ) -> String {
        switch providerKind {
        case .mock:
            return "mock-note-local"
        case .openAICompatible:
            return compact(openAIConfiguration.trimmedModelName, fallback: "未选择模型")
        case .anthropicMessages:
            return compact(anthropicConfiguration.trimmedModelName, fallback: "未选择模型")
        }
    }

    static func homepageSummaryTexts(
        transcriptionProviderKind: TranscriptionProviderKind,
        whisperConfiguration: WhisperCppTranscriptionConfiguration,
        noteProviderKind: NoteGenerationProviderKind,
        openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration,
        anthropicConfiguration: AnthropicMessagesConfiguration
    ) -> [String] {
        [
            MacSettingsSection.transcription.title,
            transcriptionRows[0],
            transcriptionProviderKind.displayName,
            transcriptionRows[1],
            transcriptionModelSummary(
                providerKind: transcriptionProviderKind,
                whisperConfiguration: whisperConfiguration
            ),
            transcriptionRows[2],
            MacSettingsSection.ai.title,
            aiRows[0],
            noteProviderKind.displayName,
            aiRows[1],
            aiModelSummary(
                providerKind: noteProviderKind,
                openAIConfiguration: openAIConfiguration,
                anthropicConfiguration: anthropicConfiguration
            ),
            aiRows[2],
            aiRows[3],
            MacSettingsSection.about.title,
            aboutRows[0],
            aboutRows[1],
            aboutRows[2]
        ]
    }

    private static func compact(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

enum MacSettingsDetail: String, CaseIterable, Identifiable {
    case profile
    case transcriptionProvider
    case transcriptionModel
    case transcriptionAuthorization
    case aiProvider
    case aiModel
    case aiAPI
    case aiTest
    case privacyPolicy
    case copyright

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profile:
            return "编辑个人资料"
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
        case .privacyPolicy:
            return "隐私政策"
        case .copyright:
            return "版权"
        }
    }
}

enum MacSettingsStorageLocation {
    static func rootURL(fileManager: FileManager = .default) -> URL {
        MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
    }

    static func ensureRootExists(fileManager: FileManager = .default) throws -> URL {
        let url = rootURL(fileManager: fileManager)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum MacSettingsProfileDefaults {
    static let displayNameKey = MacUserProfile.displayNameKey
    static let handleKey = MacUserProfile.handleKey

    static let displayName = MacUserProfile.defaultDisplayName
    static let handle = MacUserProfile.defaultHandle
    static let editFieldTitles = ["显示名称", "用户 ID"]

    static func normalized(_ value: String, fallback: String) -> String {
        MacUserProfile.normalized(value, fallback: fallback)
    }

    static func normalizedHandle(_ value: String) -> String {
        MacUserProfile.normalizedHandle(value)
    }

    static func displayHandle(_ value: String) -> String {
        MacUserProfile.displayHandle(value)
    }

    static func profileSummaryTexts(displayName: String, handle: String) -> [String] {
        MacUserProfile.profileSummaryTexts(displayName: displayName, handle: handle)
    }
}

struct MacSettingsStatusDescriptor {
    let text: String
    let systemImage: String?
    let tint: Color
}

private struct MacSettingsProfilePane: View {
    let profile: MacUserProfile
    let onEditProfile: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 13) {
            MacSettingsAvatar(initial: profileInitial, size: 92)

            VStack(spacing: 4) {
                MacMixedFontText(
                    text: displayNameText,
                    chineseFont: MacTypography.chineseTitle(size: 30, weight: .semibold),
                    englishFont: MacTypography.englishTitle(size: 30, weight: .semibold),
                    numberFont: MacTypography.numberTitle(size: 30, weight: .semibold)
                )
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

                MacMixedFontText(
                    text: handleText,
                    chineseFont: MacTypography.chineseBody(size: 15, weight: .medium),
                    englishFont: MacTypography.englishBody(size: 15, weight: .medium),
                    numberFont: MacTypography.numberBody(size: 15, weight: .medium)
                )
                .foregroundStyle(MacTheme.softText(for: colorScheme))
            }

            Button(action: onEditProfile) {
                Text("编辑个人资料")
                    .font(MacTypography.chineseBody(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .macGlassCapsule(fillOpacity: 0.28, strokeOpacity: 0.32)
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var displayNameText: String {
        profile.displayName
    }

    private var handleText: String {
        profile.displayHandle
    }

    private var profileInitial: String {
        profile.initial
    }
}

private struct RokuricsEditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let profile: MacUserProfile
    let onSave: (String, String) -> Void
    @State private var draftDisplayName: String
    @State private var draftHandle: String

    init(profile: MacUserProfile, onSave: @escaping (String, String) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _draftDisplayName = State(initialValue: profile.displayName)
        _draftHandle = State(initialValue: profile.handle)
    }

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        avatarEditor

                        VStack(spacing: 14) {
                            RokuricsProfileTextField(
                                title: MacSettingsProfileDefaults.editFieldTitles[0],
                                text: $draftDisplayName
                            )

                            RokuricsProfileTextField(
                                title: MacSettingsProfileDefaults.editFieldTitles[1],
                                text: $draftHandle
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 34)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 500)
    }

    private var header: some View {
        HStack {
            RokuricsBackButton(action: {
                dismiss()
            })

            Spacer()

            Text("编辑个人资料")
                .font(MacTypography.chineseTitle(size: 19, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Spacer()

            Button("保存") {
                saveProfile()
            }
            .font(MacTypography.chineseBody(size: 14, weight: .semibold))
            .foregroundStyle(MacTheme.aqua)
            .frame(width: RokuricsCircleIconButtonConfiguration.size, alignment: .trailing)
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private var avatarEditor: some View {
        VStack(spacing: 12) {
            MacSettingsAvatar(initial: draftInitial, size: 92)

            Button {} label: {
                Label("更换头像", systemImage: "photo")
                    .font(MacTypography.chineseBody(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .macGlassCapsule(fillOpacity: 0.30, strokeOpacity: 0.30)
            }
            .buttonStyle(.plain)
            .help("头像导入稍后接入")
        }
        .padding(.top, 12)
    }

    private var draftInitial: String {
        let name = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.first.map { String($0).uppercased() } ?? MacUserProfile.defaultDisplayNamePrefix
    }

    private func saveProfile() {
        onSave(
            MacSettingsProfileDefaults.normalized(draftDisplayName, fallback: MacSettingsProfileDefaults.displayName),
            MacSettingsProfileDefaults.normalizedHandle(draftHandle)
        )
        dismiss()
    }
}

private struct RokuricsProfileTextField: View {
    let title: String
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 13, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))

            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .font(MacTypography.chineseBody(size: 16, weight: .medium))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .macLiquidGlassCard(
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

private struct MacSettingsAvatar: View {
    let initial: String
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(MacTheme.accentGradient)
                .frame(width: size, height: size)

            Text(initial)
                .font(MacTypography.englishTitle(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(size <= 64 ? 4 : 5)
        .background {
            Circle()
                .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.24 : 0.38))
        }
        .overlay {
            Circle()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.48), lineWidth: 1)
        }
        .shadow(color: MacTheme.shadow(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.13), radius: 14, x: 0, y: 8)
    }
}

private struct MacSettingsHomeGroup<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .macLiquidGlassCard(
                cornerRadius: 22,
                material: .thinMaterial,
                fillOpacity: 0.32,
                strokeOpacity: 0.34,
                shadowOpacity: 0.06,
                shadowRadius: 12,
                shadowY: 7
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacSettingsHomeRow: View {
    let title: String
    let valueText: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(MacTypography.chineseBody(size: 15, weight: .semibold))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))

                Spacer(minLength: 16)

                Text(valueText)
                    .font(MacTypography.chineseBody(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MacSettingsHomeDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(MacTheme.glassStroke(for: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.36))
            .frame(height: 1)
            .padding(.leading, 18)
    }
}

struct RokuricsSettingsDetailSheet<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(MacTypography.chineseTitle(size: 22, weight: .semibold))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))

                    Spacer()

                    RokuricsSettingsIconButton(systemImage: "xmark", accessibilityTitle: "关闭") {
                        dismiss()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    content
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 520)
    }
}

enum RokuricsSettingsMetrics {
    static let groupSpacing: CGFloat = 14
    static let rowHorizontalPadding: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 13
    static let groupCornerRadius: CGFloat = 20
}

struct RokuricsSettingsGroup<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .macLiquidGlassCard(
                cornerRadius: RokuricsSettingsMetrics.groupCornerRadius,
                material: .thinMaterial,
                fillOpacity: 0.32,
                strokeOpacity: 0.32,
                shadowOpacity: 0.05,
                shadowRadius: 10,
                shadowY: 6
            )
        }
    }
}

struct RokuricsSettingsRow: View {
    let title: String
    let valueText: String
    var systemImage: String? = nil
    var tint: Color = MacTheme.aqua
    var isTechnical: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22)
            }

            Text(title)
                .font(MacTypography.chineseBody(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Spacer(minLength: 12)

            if isTechnical && FileRevealService.looksOpenablePath(valueText) {
                ClickableFilePathView(path: valueText)
                    .frame(maxWidth: 320, alignment: .trailing)
            } else {
                Text(valueText)
                    .font(isTechnical ? MacTypography.technical(size: 12, weight: .medium) : MacTypography.chineseBody(size: 14, weight: .medium))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, RokuricsSettingsMetrics.rowHorizontalPadding)
        .padding(.vertical, RokuricsSettingsMetrics.rowVerticalPadding)
    }
}

struct RokuricsSettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(MacTheme.glassStroke(for: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.34))
            .frame(height: 1)
            .padding(.leading, RokuricsSettingsMetrics.rowHorizontalPadding)
    }
}

struct RokuricsSettingsPickerRow<SelectionValue: Hashable, PickerContent: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    let pickerContent: PickerContent
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> PickerContent) {
        self.title = title
        _selection = selection
        pickerContent = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(MacTypography.chineseBody(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Spacer(minLength: 16)

            Picker("", selection: $selection) {
                pickerContent
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 250, alignment: .trailing)
        }
        .padding(.horizontal, RokuricsSettingsMetrics.rowHorizontalPadding)
        .padding(.vertical, 9)
    }
}

struct RokuricsSettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(MacTypography.chineseBody(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
        }
        .toggleStyle(.switch)
        .padding(.horizontal, RokuricsSettingsMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
    }
}

struct RokuricsSettingsActionRow: View {
    let title: String
    var valueText: String = ""
    var systemImage: String = "chevron.right"
    var tint: Color = MacTheme.aqua
    var isDisabled: Bool = false
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22)

                Text(title)
                    .font(MacTypography.chineseBody(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))

                Spacer(minLength: 12)

                if !valueText.isEmpty {
                    Text(valueText)
                        .font(MacTypography.chineseBody(size: 13, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
            }
            .padding(.horizontal, RokuricsSettingsMetrics.rowHorizontalPadding)
            .padding(.vertical, RokuricsSettingsMetrics.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }
}

struct RokuricsSettingsDangerRow: View {
    let title: String
    var valueText: String = ""
    var systemImage: String = "exclamationmark.triangle"
    let action: () -> Void

    var body: some View {
        RokuricsSettingsActionRow(
            title: title,
            valueText: valueText,
            systemImage: systemImage,
            tint: MacTheme.coral,
            action: action
        )
    }
}

struct RokuricsSettingsDisclosureRow<Content: View>: View {
    let title: String
    let valueText: String
    @Binding var isExpanded: Bool
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        valueText: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.valueText = valueText
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .font(MacTypography.chineseBody(size: 14, weight: .semibold))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))

                    Spacer(minLength: 12)

                    Text(valueText)
                        .font(MacTypography.chineseBody(size: 13, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .lineLimit(1)

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                }
                .padding(.horizontal, RokuricsSettingsMetrics.rowHorizontalPadding)
                .padding(.vertical, RokuricsSettingsMetrics.rowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                RokuricsSettingsDivider()
                content
            }
        }
    }
}

struct RokuricsSettingsTextFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isTechnical: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(MacTypography.chineseBody(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(isTechnical ? MacTypography.technical(size: 12, weight: .medium) : MacTypography.chineseBody(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, RokuricsSettingsMetrics.rowHorizontalPadding)
        .padding(.vertical, 12)
    }
}

struct RokuricsSettingsSecureFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(MacTypography.chineseBody(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            SecureField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(MacTypography.chineseBody(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, RokuricsSettingsMetrics.rowHorizontalPadding)
        .padding(.vertical, 12)
    }
}

struct RokuricsSettingsIconButton: View {
    let systemImage: String
    var accessibilityTitle = "操作"
    var tint: Color = MacTheme.aqua
    let action: () -> Void

    var body: some View {
        RokuricsCircleIconButton(
            systemImage: systemImage,
            accessibilityTitle: accessibilityTitle,
            tint: tint,
            action: action
        )
    }
}

struct MacSettingsCapsuleButtonStyle: ButtonStyle {
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background {
                Capsule()
                    .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.34))
            }
            .overlay {
                Capsule()
                    .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.28), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}

private struct MacSettingsFieldChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .foregroundStyle(MacTheme.deepText(for: colorScheme))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(MacTheme.glassSurface(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.34))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.28), lineWidth: 1)
            }
    }
}

extension View {
    func macSettingsFieldChrome() -> some View {
        modifier(MacSettingsFieldChrome())
    }
}

#Preview {
    MacSettingsView(
        audioInboxStore: AudioInboxStore(),
        transcriptionQueue: TranscriptionQueue(),
        transcriptionSettingsStore: TranscriptionSettingsStore(),
        noteGenerationSettingsStore: NoteGenerationSettingsStore(),
        userProfileStore: MacUserProfileStore()
    )
}
