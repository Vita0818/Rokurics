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
    @State private var activeDetail: IPhoneSettingsDetail?
    @State private var isEditingProfile = false
    @State private var isPrivacyPresented = false

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.23"
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
        .alert(RokuricsCopy.text("隐私政策", "Privacy Policy"), isPresented: $isPrivacyPresented) {
            Button(RokuricsCopy.text("知道了", "Got It"), role: .cancel) {}
        } message: {
            Text(RokuricsCopy.text("Rokurics 的转写和总结由 Mac 上的独立配置执行，iPhone 不保存 AI 凭据。", "Transcription and summaries use the independent configuration on Mac; iPhone stores no AI credentials."))
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
            RokuricsText(RokuricsCopy.text("设置", "Settings"), token: .pageTitle, size: RokuricsMobilePageLayoutMetrics.titleSize, weight: .bold)
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
                Text(RokuricsCopy.text("编辑个人资料", "Edit Profile"))
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

    private var aboutSection: some View {
        IPhoneSettingsSectionCard(title: RokuricsCopy.text("关于", "About")) {
            IPhoneSettingsListRow(title: RokuricsCopy.text("存储", "Storage"), valueText: RokuricsCopy.text("本机", "Local")) {
                activeDetail = .storage
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: RokuricsCopy.text("隐私政策", "Privacy Policy"), valueText: "") {
                isPrivacyPresented = true
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: RokuricsCopy.text("版权", "Copyright"), valueText: versionText, showsChevron: false)
        }
    }

    @ViewBuilder
    private func detailContent(for detail: IPhoneSettingsDetail) -> some View {
        switch detail {
        case .storage:
            IPhoneSettingsSectionCard(title: RokuricsCopy.text("存储", "Storage")) {
                IPhoneSettingsStaticRow(title: RokuricsCopy.text("学习库", "Library"), valueText: RokuricsCopy.text("本机 App 数据", "Local App Data"))
                IPhoneSettingsDivider()
                IPhoneSettingsStaticRow(title: RokuricsCopy.text("AI 配置", "AI Configuration"), valueText: "Mac")
            }
        }
    }
}

private enum IPhoneSettingsDetail: String, Identifiable {
    case storage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .storage:
            return RokuricsCopy.text("存储", "Storage")
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

extension CanonicalLibraryMetadataDebugPilotConfiguration {
    static let iPhoneRealDeviceDebugPilotModeKey = "Rokurics.iPhone.debug.libraryMetadataPilot.mode"
    static let iPhoneRealDeviceDebugPilotProductionRootConfirmedKey = "Rokurics.iPhone.debug.libraryMetadataPilot.productionRootConfirmed"
    static let iPhoneRealDeviceDebugPilotOffMode = "off"
    static let iPhoneRealDeviceDebugPilotDiagnosticsOnlyMode = "diagnosticsOnly"
    static let iPhoneRealDeviceDebugPilotArmTestRootN1Mode = "armTestRootN1"
    static let iPhoneRealDeviceDebugPilotExecuteTestRootN1Mode = "executeTestRootN1"
    static let iPhoneRealDeviceDebugPilotExecuteProductionRootN1Mode = "executeProductionRootN1"
    static let iPhoneRealDeviceDiagnosticsPathText = "Documents/Rokurics/Sync/Diagnostics/connection-diagnostics.jsonl"

    static let iPhoneRealDeviceDebugPilotModeChoices: [(rawValue: String, title: String)] = [
        (iPhoneRealDeviceDebugPilotOffMode, "off"),
        (iPhoneRealDeviceDebugPilotDiagnosticsOnlyMode, "diagnosticsOnly"),
        (iPhoneRealDeviceDebugPilotArmTestRootN1Mode, "armTestRootN1"),
        (iPhoneRealDeviceDebugPilotExecuteTestRootN1Mode, "executeTestRootN1"),
        (iPhoneRealDeviceDebugPilotExecuteProductionRootN1Mode, "executeProductionRootN1")
    ]

    static func normalizedIPhoneRealDeviceDebugPilotMode(_ rawValue: String?) -> String {
        let value = rawValue ?? iPhoneRealDeviceDebugPilotOffMode
        return iPhoneRealDeviceDebugPilotModeChoices.contains { $0.rawValue == value }
            ? value
            : iPhoneRealDeviceDebugPilotOffMode
    }

    static func iPhoneRealDeviceDebugPilotStoredMode(userDefaults: UserDefaults = .standard) -> String {
        normalizedIPhoneRealDeviceDebugPilotMode(userDefaults.string(forKey: iPhoneRealDeviceDebugPilotModeKey))
    }

    static func setIPhoneRealDeviceDebugPilotMode(_ mode: String, userDefaults: UserDefaults = .standard) {
        let normalized = normalizedIPhoneRealDeviceDebugPilotMode(mode)
        userDefaults.set(normalized, forKey: iPhoneRealDeviceDebugPilotModeKey)
        if normalized != iPhoneRealDeviceDebugPilotExecuteProductionRootN1Mode {
            userDefaults.set(false, forKey: iPhoneRealDeviceDebugPilotProductionRootConfirmedKey)
        }
    }

    static func iPhoneRealDeviceDebugPilotRuntime(
        userDefaults: UserDefaults = .standard,
        productionRootURL: URL?,
        fileManager: FileManager = .default
    ) -> (
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) {
#if DEBUG
        let mode = iPhoneRealDeviceDebugPilotStoredMode(userDefaults: userDefaults)
        switch mode {
        case iPhoneRealDeviceDebugPilotDiagnosticsOnlyMode:
            return (.diagnosticsOnly(evidence: iPhoneRealDeviceDebugPilotEvidence()), nil)
        case iPhoneRealDeviceDebugPilotArmTestRootN1Mode:
            return iPhoneRealDeviceDebugPilotPreparedTestRootRuntime(mode: .armN1Canary, fileManager: fileManager)
        case iPhoneRealDeviceDebugPilotExecuteTestRootN1Mode:
            return iPhoneRealDeviceDebugPilotPreparedTestRootRuntime(mode: .executeN1Canary, fileManager: fileManager)
        case iPhoneRealDeviceDebugPilotExecuteProductionRootN1Mode:
            guard userDefaults.bool(forKey: iPhoneRealDeviceDebugPilotProductionRootConfirmedKey),
                  let productionRootURL else {
                return (.disabled, nil)
            }
            return iPhoneRealDeviceDebugPilotPreparedProductionRootRuntime(
                productionRootURL: productionRootURL,
                fileManager: fileManager
            )
        default:
            return (.disabled, nil)
        }
#else
        return (.disabled, nil)
#endif
    }

#if DEBUG
    private static func iPhoneRealDeviceDebugPilotPreparedTestRootRuntime(
        mode: CanonicalLibraryMetadataDebugPilotMode,
        fileManager: FileManager
    ) -> (
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) {
        do {
            let rootURL = try iPhoneRealDeviceDebugPilotTemporaryRoot(fileManager: fileManager)
            let token = iPhoneRealDeviceDebugPilotToken()
            let evidence = iPhoneRealDeviceDebugPilotEvidence()
            let initialConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration
            switch mode {
            case .armN1Canary:
                initialConfiguration = .armTestRootN1(token: token, evidence: evidence)
            case .executeN1Canary:
                initialConfiguration = .executeTestRootN1(token: token, evidence: evidence)
            default:
                return (.disabled, nil)
            }
            let prepared = try IPhoneLibraryMetadataProductionCanaryBootstrap(
                configuration: initialConfiguration.asProductionCanaryConfiguration,
                fileManager: fileManager
            ).prepare(testRootURL: rootURL, evidence: evidence)
            let configuration: CanonicalLibraryMetadataDebugPilotConfiguration
            switch mode {
            case .armN1Canary:
                configuration = .armTestRootN1(token: token, evidence: prepared.evidence)
            case .executeN1Canary:
                configuration = .executeTestRootN1(token: token, evidence: prepared.evidence)
            default:
                configuration = .disabled
            }
            return (configuration, prepared.executor)
        } catch {
            return (.disabled, nil)
        }
    }

    private static func iPhoneRealDeviceDebugPilotPreparedProductionRootRuntime(
        productionRootURL: URL,
        fileManager: FileManager
    ) -> (
        configuration: CanonicalLibraryMetadataDebugPilotConfiguration,
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) {
        do {
            let token = iPhoneRealDeviceDebugPilotToken()
            let evidence = iPhoneRealDeviceDebugPilotEvidence()
            let initialConfiguration = CanonicalLibraryMetadataDebugPilotConfiguration.executeProductionRootN1(
                token: token,
                evidence: evidence,
                allowProductionRootWrites: true
            )
            let prepared = try IPhoneLibraryMetadataProductionCanaryBootstrap(
                configuration: initialConfiguration.asProductionCanaryConfiguration,
                fileManager: fileManager
            ).prepare(productionRootURL: productionRootURL, evidence: evidence)
            let configuration = CanonicalLibraryMetadataDebugPilotConfiguration.executeProductionRootN1(
                token: token,
                evidence: prepared.evidence,
                allowProductionRootWrites: prepared.executorInjected
            )
            return (configuration, prepared.executor)
        } catch {
            return (.disabled, nil)
        }
    }

    private static func iPhoneRealDeviceDebugPilotTemporaryRoot(fileManager: FileManager) throws -> URL {
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("RokuricsLibraryMetadataDebugPilot", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .standardizedFileURL
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private static func iPhoneRealDeviceDebugPilotToken() -> CanonicalCutoverToken {
        CanonicalCutoverToken(
            tokenID: "iphone-library-metadata-debug-pilot-n1",
            syncRunID: "iphone-library-metadata-debug-pilot",
            ownerApproved: true
        )
    }

    private static func iPhoneRealDeviceDebugPilotEvidence() -> CanonicalLibraryMetadataCutoverEvidence {
        CanonicalLibraryMetadataCutoverEvidence.passing(rollbackPlan: iPhoneRealDeviceDebugPilotRollbackPlan())
    }

    private static func iPhoneRealDeviceDebugPilotRollbackPlan() -> CanonicalRollbackPlan {
        let checkpoints = [
            CanonicalRollbackCheckpoint(checkpointID: "iphone-library-folders", domain: .folders),
            CanonicalRollbackCheckpoint(checkpointID: "iphone-library-study-items", domain: .studyItems),
            CanonicalRollbackCheckpoint(checkpointID: "iphone-library-standalone-notes", domain: .standaloneNotes)
        ]
        let actions = [
            CanonicalRollbackAction(actionID: "iphone-library-folders-rollback", kind: .metadataRollback, domain: .folders, checkpointID: checkpoints[0].checkpointID),
            CanonicalRollbackAction(actionID: "iphone-library-study-items-rollback", kind: .metadataRollback, domain: .studyItems, checkpointID: checkpoints[1].checkpointID),
            CanonicalRollbackAction(actionID: "iphone-library-standalone-notes-rollback", kind: .metadataRollback, domain: .standaloneNotes, checkpointID: checkpoints[2].checkpointID)
        ]
        return CanonicalRollbackPlan(
            planID: "iphone-library-metadata-debug-pilot-rollback",
            checkpoints: checkpoints,
            actions: actions
        )
    }
#endif
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
                        Button(RokuricsCopy.text("保存", "Save"), action: save)
                            .font(RokuricsTypography.button(size: 16))
                            .foregroundStyle(RokuricsColors.aqua)
                            .frame(minWidth: RokuricsIconButtonMetrics.size, minHeight: RokuricsIconButtonMetrics.size, alignment: .trailing)
                    }
                ) {
                    RokuricsText(RokuricsCopy.text("编辑个人资料", "Edit Profile"), token: .pageTitle, size: RokuricsMobilePageLayoutMetrics.titleSize, weight: .bold)
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
                            IPhoneProfileTextField(title: RokuricsCopy.text("显示名称", "Display Name"), text: $displayName)
                            IPhoneProfileTextField(title: RokuricsCopy.text("用户 ID", "User ID"), text: $handle)
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

#Preview {
    NavigationStack {
        IPhoneSettingsView(userProfileStore: UserProfileStore())
    }
}
