//
//  MacWhisperCppSettingsView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import AppKit
import SwiftUI

enum MacWhisperCppSettingsMode {
    case model
    case authorizationAndTest
}

struct MacWhisperCppSettingsView: View {
    @ObservedObject var settingsStore: TranscriptionSettingsStore
    let mode: MacWhisperCppSettingsMode
    @State private var isCheckingConfiguration = false
    @State private var isTestingWhisperLaunch = false
    @State private var isRefreshingFileDiagnostics = false
    @State private var saveMessage: String?
    @State private var launchProbeMessage: String?
    @State private var fileVisibilityMessage: String?
    @State private var fileVisibilityConclusion: String?
    @State private var pendingExecutableDirectoryFallbackURL: URL?
    @State private var pendingFFmpegDirectoryFallbackURL: URL?
    @State private var isAdvancedDiagnosticsExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    init(settingsStore: TranscriptionSettingsStore, mode: MacWhisperCppSettingsMode = .authorizationAndTest) {
        self.settingsStore = settingsStore
        self.mode = mode
    }

    var body: some View {
        switch mode {
        case .model:
            modelSettings
        case .authorizationAndTest:
            authorizationAndTestSettings
        }
    }

    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            RokuricsSettingsGroup(title: "模型") {
                RokuricsSettingsRow(
                    title: "当前模型",
                    valueText: settingsStore.whisperConfiguration.currentModelDisplayName
                )
                RokuricsSettingsDivider()
                RokuricsSettingsRow(
                    title: "模型等级",
                    valueText: settingsStore.whisperConfiguration.modelKind.displayName
                )
                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: "选择模型",
                    valueText: currentDraft.modelAuthorizationState.displayText,
                    systemImage: "cube",
                    tint: authorizationTint(for: currentDraft.modelAuthorizationState),
                    action: chooseModel
                )
            }
        }
    }

    private var authorizationAndTestSettings: some View {
        VStack(alignment: .leading, spacing: RokuricsSettingsMetrics.groupSpacing) {
            RokuricsSettingsGroup(title: "模型") {
                RokuricsSettingsRow(title: "当前模型", valueText: settingsStore.whisperConfiguration.currentModelDisplayName)
                RokuricsSettingsDivider()
                RokuricsSettingsPickerRow(title: "默认语言", selection: languageBinding) {
                    Text("auto").tag("auto")
                    Text("zh").tag("zh")
                    Text("en").tag("en")
                }
                RokuricsSettingsDivider()
                RokuricsSettingsToggleRow(title: "JSON Segments", isOn: preferSegmentOutputBinding)
            }

            RokuricsSettingsGroup(title: "授权") {
                RokuricsSettingsActionRow(
                    title: "whisper-cli",
                    valueText: currentDraft.executableAuthorizationState.displayText,
                    systemImage: "terminal",
                    tint: authorizationTint(for: currentDraft.executableAuthorizationState),
                    action: chooseExecutable
                )
                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: "模型文件",
                    valueText: currentDraft.modelAuthorizationState.displayText,
                    systemImage: "cube",
                    tint: authorizationTint(for: currentDraft.modelAuthorizationState),
                    action: chooseModel
                )
                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: "whisper.cpp 根目录",
                    valueText: currentDraft.whisperCppRootDirectoryAuthorizationState.displayText,
                    systemImage: "folder",
                    tint: authorizationTint(for: currentDraft.whisperCppRootDirectoryAuthorizationState),
                    action: chooseWhisperCppRootDirectory
                )
                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: "ffmpeg fallback",
                    valueText: ffmpegFallbackValue,
                    systemImage: "film",
                    tint: authorizationTint(for: currentDraft.ffmpegAuthorizationState),
                    action: chooseFFmpeg
                )
            }

            RokuricsSettingsGroup(title: "操作") {
                RokuricsSettingsActionRow(
                    title: isCheckingConfiguration ? "检查中" : "检查配置",
                    valueText: settingsStore.lastValidationStatus.displayText,
                    systemImage: "checkmark.shield",
                    tint: validationTint,
                    isDisabled: isCheckingConfiguration,
                    action: checkConfiguration
                )
                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: isTestingWhisperLaunch ? "测试中" : "测试启动",
                    valueText: "",
                    systemImage: "terminal",
                    isDisabled: isTestingWhisperLaunch,
                    action: testWhisperCliLaunch
                )
                RokuricsSettingsDivider()
                RokuricsSettingsActionRow(
                    title: "保存设置",
                    valueText: saveMessage ?? "",
                    systemImage: "square.and.arrow.down",
                    tint: MacTheme.leaf
                ) {
                    debugLogCurrentBookmarkState(context: "save.beforePersist")
                    settingsStore.persist()
                    saveMessage = "已保存"
                }
                RokuricsSettingsDivider()
                RokuricsSettingsDangerRow(
                    title: "重置授权",
                    valueText: "",
                    systemImage: "arrow.counterclockwise",
                    action: resetAuthorizations
                )
            }

            RokuricsSettingsGroup(title: "高级") {
                RokuricsSettingsDisclosureRow(
                    title: "诊断",
                    valueText: settingsStore.lastValidationStatus.displayText,
                    isExpanded: $isAdvancedDiagnosticsExpanded
                ) {
                    RokuricsSettingsRow(title: "Runtime", valueText: runtimeStatusText)
                    RokuricsSettingsDivider()
                    RokuricsSettingsRow(title: "检查结果", valueText: settingsStore.lastValidationMessage)
                    if let launchProbeMessage {
                        RokuricsSettingsDivider()
                        RokuricsSettingsRow(title: "启动结果", valueText: launchProbeMessage)
                    }
                    RokuricsSettingsDivider()
                    RokuricsSettingsActionRow(
                        title: isRefreshingFileDiagnostics ? "刷新中" : "文件可见性诊断",
                        valueText: fileVisibilityConclusion ?? "",
                        systemImage: "list.bullet.rectangle",
                        isDisabled: isRefreshingFileDiagnostics,
                        action: refreshFileVisibilityDiagnostics
                    )
                    if let fileVisibilityMessage {
                        RokuricsSettingsDivider()
                        Text(fileVisibilityMessage)
                            .font(MacTypography.technical(size: 10, weight: .medium))
                            .foregroundStyle(MacTheme.softText(for: colorScheme))
                            .lineLimit(12)
                            .textSelection(.enabled)
                            .padding(.horizontal, RokuricsSettingsMetrics.rowHorizontalPadding)
                            .padding(.vertical, 10)
                    }
                    RokuricsSettingsDivider()
                    RokuricsSettingsActionRow(
                        title: "whisper-cli 文件夹授权",
                        valueText: "可选",
                        systemImage: "folder.badge.gearshape",
                        action: chooseExecutableParentDirectory
                    )
                    RokuricsSettingsDivider()
                    RokuricsSettingsActionRow(
                        title: "ffmpeg 文件夹授权",
                        valueText: "可选",
                        systemImage: "folder.badge.gearshape",
                        action: chooseFFmpegParentDirectory
                    )
                }
            }
        }
    }

    private var executablePathBinding: Binding<String> {
        Binding {
            settingsStore.whisperConfiguration.executablePath
        } set: { value in
            saveMessage = nil
            updateDraft {
                $0.applyManualPathEdit(value, for: .executable)
            }
        }
    }

    private var modelPathBinding: Binding<String> {
        Binding {
            settingsStore.whisperConfiguration.modelPath
        } set: { value in
            saveMessage = nil
            updateDraft {
                $0.applyManualPathEdit(value, for: .model)
            }
        }
    }

    private var ffmpegPathBinding: Binding<String> {
        Binding {
            settingsStore.whisperConfiguration.ffmpegExecutablePath ?? ""
        } set: { value in
            saveMessage = nil
            updateDraft {
                $0.applyManualPathEdit(value, for: .ffmpeg)
            }
        }
    }

    private var whisperCppRootDirectoryPathBinding: Binding<String> {
        Binding {
            settingsStore.whisperConfiguration.whisperCppRootDirectoryPath ?? ""
        } set: { value in
            saveMessage = nil
            updateDraft {
                $0.applyManualPathEdit(value, for: .whisperCppRootDirectory)
            }
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

    private var ffmpegPlaceholder: String {
        AudioPreprocessorConfiguration.discoveredFFmpegExecutablePath() ?? "/opt/homebrew/bin/ffmpeg"
    }

    private var ffmpegFallbackValue: String {
        let path = settingsStore.whisperConfiguration.normalizedFFmpegExecutablePath
        if path.isEmpty {
            return "可选"
        }
        return currentDraft.ffmpegAuthorizationState.displayText
    }

    private var currentDraft: WhisperCppSettingsDraft {
        WhisperCppSettingsDraft(configuration: settingsStore.whisperConfiguration)
    }

    private var runtimeStatusText: String {
        let runtime = WhisperCppRuntimeResolver().resolveRuntime(
            configuration: settingsStore.whisperConfiguration
        )
        let helperText = runtime.bundledHelperIsExecutable ? "helper：内置可用" : "helper：内置不可用"
        return "\(runtime.statusText)；\(helperText)"
    }

    private var fileVisibilityDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("文件可见性诊断")
                        .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))

                    Text("从 RokuricsMac sandbox 视角只读检查 whisper.cpp 目录")
                        .font(MacTypography.chineseCaption(size: 10, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme).opacity(0.72))
                }

                Spacer()

                Button {
                    refreshFileVisibilityDiagnostics()
                } label: {
                    Label(isRefreshingFileDiagnostics ? "刷新中" : "刷新文件诊断", systemImage: "list.bullet.rectangle")
                        .font(MacTypography.chineseCaption(size: 11, weight: .bold))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .macGlassCapsule(fillOpacity: 0.24, strokeOpacity: 0.24)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingFileDiagnostics)
            }

            if let fileVisibilityMessage {
                Text(fileVisibilityMessage)
                    .font(MacTypography.technical(size: 10, weight: .medium))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .lineLimit(12)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MacTheme.glassSurface(for: colorScheme).opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MacTheme.glassStroke(for: colorScheme).opacity(0.24), lineWidth: 1)
                }
        }
    }

    private func pathRow(
        title: String,
        value: Binding<String>,
        placeholder: String,
        authorizationLabel: String,
        authorizationState: WhisperCppFileAuthorizationState,
        buttonTitle: String,
        action: @escaping () -> Void,
        directoryButtonTitle: String?,
        directoryAction: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))

                Text("\(authorizationLabel)：\(authorizationState.displayText)")
                    .font(MacTypography.chineseCaption(size: 11, weight: .medium))
                    .foregroundStyle(authorizationTint(for: authorizationState))
            }

            HStack(spacing: 10) {
                TextField(placeholder, text: value)
                    .font(MacTypography.technical(size: 12, weight: .medium))
                    .lineLimit(1)
                    .macSettingsFieldChrome()

                Button(action: action) {
                    Label(buttonTitle, systemImage: "folder")
                }
                .buttonStyle(MacSettingsCapsuleButtonStyle(tint: MacTheme.aqua))
                .frame(width: 108)

                if let directoryButtonTitle,
                   let directoryAction {
                    Button(action: directoryAction) {
                        Label(directoryButtonTitle, systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(MacSettingsCapsuleButtonStyle(tint: MacTheme.aqua))
                    .frame(width: 132)
                }
            }
        }
    }

    private func authorizationTint(for state: WhisperCppFileAuthorizationState) -> Color {
        switch state {
        case .authorized:
            return MacTheme.leaf.opacity(0.82)
        case .unauthorized:
            return MacTheme.softText(for: colorScheme).opacity(0.78)
        }
    }

    private func chooseExecutable() {
        chooseFile(configuration: .executable) { url in
            guard let bookmarkData = bookmarkData(
                for: url,
                configuration: .executable,
                label: "executable"
            ) else {
                pendingExecutableDirectoryFallbackURL = url
                return
            }

            pendingExecutableDirectoryFallbackURL = nil
            updateDraft {
                $0.applyExecutableSelection(url: url, bookmarkData: bookmarkData)
            }
            debugLogCurrentBookmarkState(context: "choose.executable.afterUpdate")
            saveMessage = nil
        }
    }

    private func chooseModel() {
        chooseFile(configuration: .model) { url in
            guard let bookmarkData = bookmarkData(
                for: url,
                configuration: .model,
                label: "model"
            ) else {
                return
            }

            updateDraft {
                $0.applyModelSelection(url: url, bookmarkData: bookmarkData)
            }
            debugLogCurrentBookmarkState(context: "choose.model.afterUpdate")
            saveMessage = nil
        }
    }

    private func chooseFFmpeg() {
        chooseFile(configuration: .ffmpeg) { url in
            guard let bookmarkData = bookmarkData(
                for: url,
                configuration: .ffmpeg,
                label: "ffmpeg"
            ) else {
                pendingFFmpegDirectoryFallbackURL = url
                return
            }

            pendingFFmpegDirectoryFallbackURL = nil
            updateDraft {
                $0.applyFFmpegSelection(url: url, bookmarkData: bookmarkData)
            }
            debugLogCurrentBookmarkState(context: "choose.ffmpeg.afterUpdate")
            saveMessage = nil
        }
    }

    private func chooseWhisperCppRootDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "选择目录"

        guard panel.runModal() == .OK,
              let directoryURL = panel.url else {
            return
        }

        guard selectedURLIsDirectory(directoryURL) else {
            settingsStore.updateValidation(
                status: .checkFailed,
                message: "请选择 whisper.cpp 根目录文件夹。"
            )
            return
        }

        do {
            let bookmarkData = try SecurityScopedFileAccess.bookmarkData(
                for: directoryURL,
                mode: .directoryReadOnly,
                role: "whisper.cpp-root"
            )
            guard !bookmarkData.isEmpty else {
                settingsStore.updateValidation(
                    status: .checkFailed,
                    message: "whisper.cpp 根目录 sandbox 授权为空，请重新选择。"
                )
                return
            }

            updateDraft {
                $0.applyWhisperCppRootDirectorySelection(url: directoryURL, bookmarkData: bookmarkData)
            }
            debugLogBookmarkSelection(label: "whisper.cpp-root", bookmarkBytes: bookmarkData.count)
            debugLogCurrentBookmarkState(context: "choose.whisperCppRoot.afterUpdate")
            saveMessage = nil
        } catch TranscriptionError.bookmarkEntitlementMissing {
            settingsStore.updateValidation(
                status: .bookmarkEntitlementMissing,
                message: TranscriptionError.bookmarkEntitlementMissing.localizedDescription
            )
        } catch {
            debugLogParentDirectoryBookmarkSelectionFailure(
                label: "whisper.cpp-root",
                directoryURL: directoryURL,
                error: error
            )
            let diagnostic = WhisperCppBookmarkCreationFailureDiagnostic(
                role: "whisper.cpp-root",
                bookmarkMode: .directoryReadOnly,
                url: directoryURL,
                error: error
            )
            settingsStore.updateValidation(status: .checkFailed, message: diagnostic.userMessage)
        }
    }

    private func bookmarkData(
        for url: URL,
        configuration: WhisperCppFilePickerConfiguration,
        label: String
    ) -> Data? {
        if selectedURLIsDirectory(url) {
            let error = WhisperCppFileSelectionError.directorySelected(configuration.role)
            settingsStore.updateValidation(status: .checkFailed, message: error.localizedDescription)
            return nil
        }

        do {
            let bookmarkData = try SecurityScopedFileAccess.bookmarkData(
                for: url,
                mode: configuration.bookmarkMode,
                role: configuration.diagnosticRole
            )
            debugLogBookmarkSelection(label: label, bookmarkBytes: bookmarkData.count)
            guard !bookmarkData.isEmpty else {
                settingsStore.updateValidation(
                    status: .checkFailed,
                    message: "sandbox 授权为空，请重新选择文件。"
                )
                return nil
            }

            return bookmarkData
        } catch TranscriptionError.bookmarkEntitlementMissing {
            settingsStore.updateValidation(
                status: .bookmarkEntitlementMissing,
                message: TranscriptionError.bookmarkEntitlementMissing.localizedDescription
            )
            return nil
        } catch {
            debugLogBookmarkSelectionFailure(configuration: configuration, url: url, error: error)
            let diagnostic = WhisperCppBookmarkCreationFailureDiagnostic(
                role: configuration.diagnosticRole,
                bookmarkMode: configuration.bookmarkMode,
                url: url,
                error: error
            )
            settingsStore.updateValidation(
                status: .checkFailed,
                message: diagnostic.userMessage
            )
            return nil
        }
    }

    private func chooseExecutableParentDirectory() {
        chooseParentDirectory(
            for: .executable,
            pendingExecutableURL: pendingExecutableDirectoryFallbackURL,
            configuredPath: settingsStore.whisperConfiguration.normalizedExecutablePath,
            label: "whisper-cli-folder"
        )
    }

    private func chooseFFmpegParentDirectory() {
        chooseParentDirectory(
            for: .ffmpeg,
            pendingExecutableURL: pendingFFmpegDirectoryFallbackURL,
            configuredPath: settingsStore.whisperConfiguration.normalizedFFmpegExecutablePath,
            label: "ffmpeg-folder"
        )
    }

    private func chooseParentDirectory(
        for selection: WhisperCppSettingsFileSelection,
        pendingExecutableURL: URL?,
        configuredPath: String,
        label: String
    ) {
        let executableURL: URL
        if let pendingExecutableURL {
            executableURL = pendingExecutableURL
        } else {
            let path = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                settingsStore.updateValidation(
                    status: .checkFailed,
                    message: "请先选择可执行文件，再选择其所在文件夹授权。"
                )
                return
            }
            executableURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: false)
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "选择文件夹"

        guard panel.runModal() == .OK,
              let directoryURL = panel.url else {
            return
        }

        guard selectedURLIsDirectory(directoryURL) else {
            settingsStore.updateValidation(
                status: .checkFailed,
                message: "请选择可执行文件所在的直接父文件夹。"
            )
            return
        }

        guard ExecutableParentDirectoryAuthorization.isAllowedParentDirectoryPath(directoryURL.path),
              ExecutableParentDirectoryAuthorization.isDirectParentDirectory(
                directoryURL.path,
                ofExecutableAtPath: executableURL.path
              ) else {
            settingsStore.updateValidation(
                status: .checkFailed,
                message: "请选择可执行文件所在的直接父文件夹，不要选择过宽目录。"
            )
            return
        }

        let expectedExecutableURL = directoryURL
            .appendingPathComponent(executableURL.lastPathComponent, isDirectory: false)
            .standardizedFileURL
        guard ExecutableParentDirectoryAuthorization.equivalent(expectedExecutableURL, executableURL.standardizedFileURL),
              FileManager.default.fileExists(atPath: expectedExecutableURL.path) else {
            settingsStore.updateValidation(
                status: .checkFailed,
                message: "所选文件夹中没有对应的可执行文件，请选择它的所在文件夹。"
            )
            return
        }

        do {
            let bookmarkData = try SecurityScopedFileAccess.bookmarkData(
                for: directoryURL,
                mode: .directoryReadOnly,
                role: label
            )
            guard !bookmarkData.isEmpty else {
                settingsStore.updateValidation(
                    status: .checkFailed,
                    message: "文件夹 sandbox 授权为空，请重新选择。"
                )
                return
            }

            updateDraft {
                switch selection {
                case .executable:
                    $0.applyExecutableParentDirectorySelection(
                        executableURL: executableURL,
                        directoryURL: directoryURL,
                        bookmarkData: bookmarkData
                    )
                case .whisperCppRootDirectory:
                    break
                case .ffmpeg:
                    $0.applyFFmpegParentDirectorySelection(
                        executableURL: executableURL,
                        directoryURL: directoryURL,
                        bookmarkData: bookmarkData
                    )
                case .model:
                    break
                }
            }
            switch selection {
            case .executable:
                pendingExecutableDirectoryFallbackURL = nil
            case .whisperCppRootDirectory:
                break
            case .ffmpeg:
                pendingFFmpegDirectoryFallbackURL = nil
            case .model:
                break
            }
            debugLogBookmarkSelection(label: label, bookmarkBytes: bookmarkData.count)
            debugLogCurrentBookmarkState(context: "choose.parentDirectory.afterUpdate")
            saveMessage = nil
        } catch {
            debugLogParentDirectoryBookmarkSelectionFailure(label: label, directoryURL: directoryURL, error: error)
            let diagnostic = WhisperCppBookmarkCreationFailureDiagnostic(
                role: label,
                bookmarkMode: .directoryReadOnly,
                url: directoryURL,
                error: error
            )
            settingsStore.updateValidation(status: .checkFailed, message: diagnostic.userMessage)
        }
    }

    private func chooseFile(
        configuration: WhisperCppFilePickerConfiguration,
        onSelection: (URL) -> Void
    ) {
        let panel = NSOpenPanel()
        configuration.apply(to: panel)

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        onSelection(url)
    }

    private func selectedURLIsDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func checkConfiguration() {
        guard !isCheckingConfiguration else {
            return
        }

        isCheckingConfiguration = true
        saveMessage = nil

        settingsStore.persist()
        let configuration = settingsStore.reloadedWhisperConfiguration() ?? settingsStore.whisperConfiguration
        debugLogConfiguration(configuration, context: "checkConfiguration.input")
        Task {
            let result = await TranscriptionConfigurationValidator().validateWhisperCpp(configuration)
            await MainActor.run {
                settingsStore.updateValidation(status: result.status, message: result.message)
                isCheckingConfiguration = false
            }
        }
    }

    private func testWhisperCliLaunch() {
        guard !isTestingWhisperLaunch else {
            return
        }

        isTestingWhisperLaunch = true
        saveMessage = nil
        launchProbeMessage = nil

        settingsStore.persist()
        let configuration = settingsStore.reloadedWhisperConfiguration() ?? settingsStore.whisperConfiguration
        debugLogConfiguration(configuration, context: "launchProbe.input")

        Task {
            let result = await WhisperCppTranscriptionProvider(
                configuration: configuration,
                timeout: 15
            ).launchHelpProbe()

            await MainActor.run {
                if !result.succeeded,
                   let fileVisibilityConclusion {
                    launchProbeMessage = "\(fileVisibilityConclusion)\n\(result.userMessage)"
                } else {
                    launchProbeMessage = result.userMessage
                }
                isTestingWhisperLaunch = false
                debugLogLaunchProbeResult(result)
            }
        }
    }

    private func refreshFileVisibilityDiagnostics() {
        guard !isRefreshingFileDiagnostics else {
            return
        }

        isRefreshingFileDiagnostics = true
        saveMessage = nil
        fileVisibilityMessage = nil
        fileVisibilityConclusion = nil

        settingsStore.persist()
        let configuration = settingsStore.reloadedWhisperConfiguration() ?? settingsStore.whisperConfiguration
        debugLogConfiguration(configuration, context: "fileVisibility.input")

        Task {
            let result = WhisperCppFileVisibilityDiagnostics(
                configuration: configuration
            ).run()

            await MainActor.run {
                fileVisibilityMessage = result.userSummary
                fileVisibilityConclusion = result.keyConclusion
                isRefreshingFileDiagnostics = false
                debugLogFileVisibilityResult(result)
            }
        }
    }

    private func resetAuthorizations() {
        settingsStore.resetWhisperCppAuthorizations()
        saveMessage = "已清除授权"
        launchProbeMessage = nil
        fileVisibilityMessage = nil
        fileVisibilityConclusion = nil
    }

    private func updateDraft(_ update: (inout WhisperCppSettingsDraft) -> Void) {
        launchProbeMessage = nil
        fileVisibilityMessage = nil
        fileVisibilityConclusion = nil
        settingsStore.updateWhisperConfiguration { configuration in
            var draft = WhisperCppSettingsDraft(configuration: configuration)
            update(&draft)
            configuration = draft.configuration
        }
    }

    private func debugLogBookmarkSelection(label: String, bookmarkBytes: Int) {
        #if DEBUG
        print("[Rokurics][MacWhisperCppSettingsView] selected \(label): bookmarkBytes=\(bookmarkBytes)")
        #endif
    }

    private func debugLogBookmarkSelectionFailure(
        configuration: WhisperCppFilePickerConfiguration,
        url: URL,
        error: Error
    ) {
        #if DEBUG
        let diagnostic = WhisperCppBookmarkCreationFailureDiagnostic(
            role: configuration.diagnosticRole,
            bookmarkMode: configuration.bookmarkMode,
            url: url,
            error: error
        )
        print(diagnostic.debugLogMessage)
        #endif
    }

    private func debugLogParentDirectoryBookmarkSelectionFailure(label: String, directoryURL: URL, error: Error) {
        #if DEBUG
        let diagnostic = WhisperCppBookmarkCreationFailureDiagnostic(
            role: label,
            bookmarkMode: .directoryReadOnly,
            url: directoryURL,
            error: error
        )
        print(diagnostic.debugLogMessage)
        #endif
    }

    private func debugLogCurrentBookmarkState(context: String) {
        debugLogConfiguration(settingsStore.whisperConfiguration, context: context)
    }

    private func debugLogConfiguration(_ configuration: WhisperCppTranscriptionConfiguration, context: String) {
        #if DEBUG
        print(
            "[Rokurics][MacWhisperCppSettingsView] \(context): " +
            "executableBookmarkBytes=\(configuration.executableBookmarkData?.count ?? 0), " +
            "executableParentDirectoryBookmarkBytes=\(configuration.executableParentDirectoryBookmarkData?.count ?? 0), " +
            "whisperCppRootDirectoryBookmarkBytes=\(configuration.whisperCppRootDirectoryBookmarkData?.count ?? 0), " +
            "modelBookmarkBytes=\(configuration.modelBookmarkData?.count ?? 0), " +
            "ffmpegBookmarkBytes=\(configuration.ffmpegExecutableBookmarkData?.count ?? 0), " +
            "ffmpegParentDirectoryBookmarkBytes=\(configuration.ffmpegExecutableParentDirectoryBookmarkData?.count ?? 0)"
        )
        #endif
    }

    private func debugLogLaunchProbeResult(_ result: WhisperCppLaunchProbeResult) {
        #if DEBUG
        print(
            "[Rokurics][MacWhisperCppSettingsView] launchProbe.result: " +
            "succeeded=\(result.succeeded), " +
            "runtimeMode=\(result.runtimeMode.rawValue), " +
            "bundledHelperExists=\(result.bundledHelperExists), " +
            "processExecutableURL=\(result.processExecutableURLPath), " +
            "currentDirectoryURL=\(result.currentDirectoryURLPath), " +
            "rootDirectoryAccessStarted=\(result.rootDirectoryAccessStarted), " +
            "stdoutSummary=\(result.stdoutSummary), " +
            "stderrSummary=\(result.stderrSummary), " +
            "diagnostic=\(result.diagnosticMessage)"
        )
        #endif
    }

    private func debugLogFileVisibilityResult(_ result: WhisperCppFileVisibilityDiagnosticResult) {
        #if DEBUG
        print(result.debugLogMessage)
        #endif
    }
}
