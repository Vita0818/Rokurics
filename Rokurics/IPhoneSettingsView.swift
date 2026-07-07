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
#if DEBUG
    @AppStorage(CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotModeKey)
    private var libraryMetadataDebugPilotMode = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotOffMode
    @State private var pendingProductionRootPilotMode: String?
    @State private var isProductionRootPilotConfirmationPresented = false
    @State private var isCanonicalSwitchBackProofRunning = false
    @State private var canonicalSwitchBackProofSummary: CanonicalSwitchBackProofUISummary?
#endif

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
#if DEBUG
                        debugCanonicalKernelSwitchSection
                        debugLibraryMetadataPilotSection
#endif
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
            Text(RokuricsCopy.text("Rokurics 只在用户显式触发时调用 AI。API Key 保存在本机设置中，不写入学习库、聊天上下文或日志。", "Rokurics calls AI only when you trigger it. API keys stay in local settings and are not written to the library, chat context, or logs."))
        }
#if DEBUG
        .alert(RokuricsCopy.text("确认真实学习库 metadata 写入", "Confirm Real Metadata Write"), isPresented: $isProductionRootPilotConfirmationPresented) {
            Button(RokuricsCopy.text("取消", "Cancel"), role: .cancel) {
                pendingProductionRootPilotMode = nil
            }
            Button(RokuricsCopy.text("确认开启", "Enable"), role: .destructive) {
                libraryMetadataDebugPilotMode = CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotExecuteProductionRootN1Mode
                UserDefaults.standard.set(
                    true,
                    forKey: CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotProductionRootConfirmedKey
                )
                pendingProductionRootPilotMode = nil
            }
        } message: {
            Text(RokuricsCopy.text(
                "这会允许写真实学习库 metadata 根；仍只限 libraryMetadata，仍只限 N=1，仍保留 rollback 与 legacy fallback。这是第一次真实写。",
                "This allows one real library metadata root write. It is still limited to libraryMetadata, N=1, rollback, and legacy fallback."
            ))
        }
#endif
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

    private var transcriptionSection: some View {
        IPhoneSettingsSectionCard(title: RokuricsCopy.text("转写", "Transcription")) {
            IPhoneSettingsListRow(title: "Provider", valueText: RokuricsCopy.text("Mac 安全转写", "Secure Mac")) {
                activeDetail = .transcriptionProvider
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: RokuricsCopy.text("模型", "Model"), valueText: "whisper.cpp") {
                activeDetail = .transcriptionModel
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: RokuricsCopy.text("授权与测试", "Access & Test"), valueText: RokuricsCopy.text("查看", "View")) {
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

            IPhoneSettingsListRow(title: RokuricsCopy.text("模型", "Model"), valueText: aiSettingsStore.modelDisplayName) {
                activeDetail = .aiModel
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: RokuricsCopy.text("API 设置", "API Settings"), valueText: RokuricsCopy.text("查看", "View")) {
                activeDetail = .aiAPI
            }

            IPhoneSettingsDivider()

            IPhoneSettingsListRow(title: RokuricsCopy.text("测试", "Test"), valueText: RokuricsCopy.text("查看", "View")) {
                activeDetail = .aiTest
            }
        }
    }

#if DEBUG
    private var debugCanonicalKernelSwitchSection: some View {
        IPhoneSettingsSectionCard(title: RokuricsCopy.text("Debug · 同步内核", "Debug · Sync Kernel")) {
            IPhoneSettingsDebugTextRow(
                title: RokuricsCopy.text("状态", "Status"),
                bodyText: debugCanonicalKernelSwitchStatusText
            )

            IPhoneSettingsDivider()

            IPhoneSettingsDebugTextRow(
                title: RokuricsCopy.text("安全边界", "Safety"),
                bodyText: CanonicalKernelSwitchConfiguration.safetyText
            )

            IPhoneSettingsDivider()

            IPhoneSettingsDebugTextRow(
                title: RokuricsCopy.text("Legacy 兜底", "Legacy Fallback"),
                bodyText: CanonicalKernelSwitchConfiguration.emergencyOldKernelSwitchBackText
            )

            IPhoneSettingsDivider()

            IPhoneSettingsDebugTextRow(
                title: RokuricsCopy.text("诊断文件", "Diagnostics File"),
                bodyText: CanonicalKernelSwitchConfiguration.diagnosticsPathText
            )

            IPhoneSettingsDivider()

            IPhoneSettingsDebugActionRow(
                title: RokuricsCopy.text("运行新旧内核切回证明", "Run Switchback Proof"),
                valueText: canonicalSwitchBackProofActionText,
                systemImage: isCanonicalSwitchBackProofRunning ? "hourglass" : "play.circle.fill",
                isDisabled: isCanonicalSwitchBackProofRunning
            ) {
                runCanonicalSwitchBackProof()
            }

            IPhoneSettingsDivider()

            IPhoneSettingsDebugTextRow(
                title: RokuricsCopy.text("切回证明", "Switchback Proof"),
                bodyText: canonicalSwitchBackProofSummaryText
            )
        }
    }

    private var debugLibraryMetadataPilotSection: some View {
        IPhoneSettingsSectionCard(title: RokuricsCopy.text("Debug · 学习库迁移试点（高级限制/诊断）", "Debug · Library Migration Pilot")) {
            Picker(RokuricsCopy.text("高级限制", "Guardrail"), selection: debugPilotModeBinding) {
                ForEach(CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotModeChoices, id: \.rawValue) { choice in
                    Text(choice.title).tag(choice.rawValue)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 18)
            .frame(minHeight: 58)

            IPhoneSettingsDivider()

            IPhoneSettingsDebugTextRow(
                title: RokuricsCopy.text("诊断文件", "Diagnostics File"),
                bodyText: CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDiagnosticsPathText
            )

            IPhoneSettingsDivider()

            IPhoneSettingsDebugTextRow(
                title: RokuricsCopy.text("取回方式", "Retrieval"),
                bodyText: RokuricsCopy.text(
                    "专项高级开关只能降级、阻断或生成诊断，不能越过固定 canonicalFullSync runtime，不能单独打开 productionRoot write。通过 Xcode Devices & Simulators 下载 app container。默认 off；Release 不显示此区。",
                    "This debug switch can only downgrade, block, or write diagnostics. It cannot bypass canonicalFullSync or independently enable productionRoot writes. Download the app container in Xcode."
                )
            )
        }
    }

    private var debugCanonicalKernelSwitchStatusText: String {
        let result = CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults().resolve()
        if result.isBlocked {
            let blockers = result.blockers.map(\.rawValue).joined(separator: ", ")
            return "blocked · \(blockers)"
        }
        return "\(result.effectiveMode.displayTitle) · owner=\(result.ownerState.rawValue) · legacy fallback retained"
    }

    private var debugPilotModeBinding: Binding<String> {
        Binding {
            CanonicalLibraryMetadataDebugPilotConfiguration.normalizedIPhoneRealDeviceDebugPilotMode(libraryMetadataDebugPilotMode)
        } set: { newValue in
            let normalized = CanonicalLibraryMetadataDebugPilotConfiguration.normalizedIPhoneRealDeviceDebugPilotMode(newValue)
            if normalized == CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotExecuteProductionRootN1Mode {
                pendingProductionRootPilotMode = normalized
                isProductionRootPilotConfirmationPresented = true
            } else {
                libraryMetadataDebugPilotMode = normalized
                UserDefaults.standard.set(
                    false,
                    forKey: CanonicalLibraryMetadataDebugPilotConfiguration.iPhoneRealDeviceDebugPilotProductionRootConfirmedKey
                )
            }
        }
    }

    private var canonicalSwitchBackProofActionText: String {
        if isCanonicalSwitchBackProofRunning {
            return RokuricsCopy.text("运行中", "Running")
        }
        return canonicalSwitchBackProofSummary?.status.rawValue ?? RokuricsCopy.text("未运行", "Not run")
    }

    private var canonicalSwitchBackProofSummaryText: String {
        if isCanonicalSwitchBackProofRunning {
            return RokuricsCopy.text(
                "running · 使用真实库副本创建 temp clone，不直接写当前生产库，不切主开关，不触发 sync/upload。",
                "running · Uses a real-library temp clone; does not write production, flip the main switch, or trigger sync/upload."
            )
        }
        guard let summary = canonicalSwitchBackProofSummary else {
            return RokuricsCopy.text(
                "未运行 · 使用真实库副本；proof 只在 safe temp clone 上执行，不直接写当前生产库，不改变当前 canonicalFullSync 运行时。",
                "Not run · Uses a real-library temp clone only; no production write and no canonicalFullSync runtime change."
            )
        }
        return summary.displayText
    }

    private func runCanonicalSwitchBackProof() {
        guard !isCanonicalSwitchBackProofRunning else { return }
        isCanonicalSwitchBackProofRunning = true
        Task {
            let summary = await IPhoneCanonicalSwitchBackProofDriver().run()
            await MainActor.run {
                canonicalSwitchBackProofSummary = summary
                isCanonicalSwitchBackProofRunning = false
            }
        }
    }
#endif

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
            IPhoneSettingsSectionCard(title: RokuricsCopy.text("存储", "Storage")) {
                IPhoneSettingsStaticRow(title: RokuricsCopy.text("学习库", "Library"), valueText: RokuricsCopy.text("本机 App 数据", "Local App Data"))
                IPhoneSettingsDivider()
                IPhoneSettingsStaticRow(title: "API Key", valueText: RokuricsCopy.text("本机设置", "Local Settings"))
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
            return RokuricsCopy.text("转写 Provider", "Transcription Provider")
        case .transcriptionModel:
            return RokuricsCopy.text("转写模型", "Transcription Model")
        case .transcriptionAuthorization:
            return RokuricsCopy.text("授权与测试", "Access & Test")
        case .aiProvider:
            return "AI Provider"
        case .aiModel:
            return RokuricsCopy.text("AI 模型", "AI Model")
        case .aiAPI:
            return RokuricsCopy.text("API 设置", "API Settings")
        case .aiTest:
            return RokuricsCopy.text("测试", "Test")
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

#if DEBUG
private struct IPhoneSettingsDebugTextRow: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RokuricsText(title, token: .body, size: 15, weight: .semibold)
                .foregroundStyle(RokuricsColors.deepText)

            Text(bodyText)
                .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct IPhoneSettingsDebugActionRow: View {
    let title: String
    let valueText: String
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isDisabled ? RokuricsColors.tertiaryText : RokuricsColors.aqua)
                    .frame(width: 22)

                RokuricsText(title, token: .body, size: 15, weight: .semibold)
                    .foregroundStyle(RokuricsColors.deepText)
                    .lineLimit(2)

                Spacer(minLength: 12)

                RokuricsText(valueText, token: .body, size: 13, weight: .semibold)
                    .foregroundStyle(RokuricsColors.softText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
#endif

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
                IPhoneSettingsStaticRow(title: RokuricsCopy.text("转写 Provider", "Transcription Provider"), valueText: RokuricsCopy.text("Mac 安全转写", "Secure Mac"))
            }
        case .model:
            IPhoneSettingsSectionCard(title: RokuricsCopy.text("模型", "Model")) {
                IPhoneSettingsStaticRow(title: RokuricsCopy.text("当前模型", "Current Model"), valueText: "whisper.cpp")
                IPhoneSettingsDivider()
                IPhoneSettingsStaticRow(title: RokuricsCopy.text("配置位置", "Configured On"), valueText: "Mac")
            }
        case .authorization:
            IPhoneSettingsSectionCard(title: RokuricsCopy.text("授权与测试", "Access & Test")) {
                IPhoneSettingsStaticRow(title: RokuricsCopy.text("授权", "Access"), valueText: RokuricsCopy.text("安全配对", "Secure Pairing"))
                IPhoneSettingsDivider()
                IPhoneSettingsStaticRow(title: RokuricsCopy.text("上传", "Upload"), valueText: RokuricsCopy.text("用户显式触发", "User-triggered"))
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
        IPhoneSettingsSectionCard(title: RokuricsCopy.text("模型", "Model")) {
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
                IPhoneSettingsTextFieldRow(title: RokuricsCopy.text("模型", "Model"), text: $openAIModelDraft, onSubmit: saveDrafts)
            } else {
                IPhoneSettingsTextFieldRow(title: RokuricsCopy.text("模型", "Model"), text: $anthropicModelDraft, onSubmit: saveDrafts)
            }
        }
    }

    private var apiSection: some View {
        IPhoneSettingsSectionCard(title: RokuricsCopy.text("API 设置", "API Settings")) {
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
        IPhoneSettingsSectionCard(title: RokuricsCopy.text("测试", "Test")) {
            IPhoneSettingsListRow(title: RokuricsCopy.text("检查配置", "Check Setup"), valueText: validationMessage ?? RokuricsCopy.text("本机检查", "Local Check")) {
                validationMessage = configurationIsReady ? RokuricsCopy.text("可用", "Ready") : RokuricsCopy.text("未完整", "Incomplete")
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
            return model.isEmpty ? RokuricsCopy.text("未选择模型", "No model selected") : model
        case .anthropicMessages:
            let model = anthropicConfiguration.trimmedModelName
            return model.isEmpty ? RokuricsCopy.text("未选择模型", "No model selected") : model
        }
    }
}

#Preview {
    NavigationStack {
        IPhoneSettingsView(userProfileStore: UserProfileStore())
    }
}
