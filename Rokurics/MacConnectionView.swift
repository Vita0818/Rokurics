//
//  MacConnectionView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI
import UIKit

private enum MacConnectionFocusedField: Hashable {
    case host
    case port
    case fingerprint
    case pairingCode
}

private enum MacConnectionFeedbackKind {
    case connectionTest
    case pairing
    case upload
}

struct MacUploadTestPresenceGate {
    static func blockedReason(
        snapshot: SecureMacConnectionSnapshot,
        status: DeviceConnectionStatus,
        now: Date = Date(),
        userConnectionIntent: UserConnectionIntent = .wantsConnected,
        isHTTPSUploadEnabled: Bool = SecureMacUploadClient.isHTTPSUploadEnabled
    ) -> String? {
        guard snapshot.isPaired else {
            return "not_paired"
        }
        guard userConnectionIntent == .wantsConnected else {
            return "user_does_not_want_connection"
        }
        guard isHTTPSUploadEnabled else {
            return "https_upload_disabled"
        }
        guard status.deviceID == snapshot.deviceID else {
            return "presence_unavailable"
        }
        let presence = status.presenceSnapshot(now: now)
        if presence.isOnline {
            return nil
        }
        if presence.state == .securityError {
            return "security_error"
        }
        if presence.state == .interrupted || presence.state == .stale {
            return "heartbeat_interrupted"
        }
        if presence.state == .disconnected {
            return "heartbeat_disconnected"
        }
        return "heartbeat_not_online"
    }
}

struct MacConnectionView: View {
    @ObservedObject var connectionStore: SecureMacConnectionStore
    @ObservedObject private var studyLibraryStore: StudyLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var pairingCode = ""
    @State private var isFingerprintVisible = false
    @State private var isCheckingHTTPS = false
    @State private var isPairing = false
    @State private var isUploading = false
    @State private var isDetailPresented = false
    @State private var recentStatus: String?
    @State private var errorMessage: String?
    @State private var feedbackKind: MacConnectionFeedbackKind?
    @State private var transientNotice: String?
    @State private var transientNoticeToken = 0
    @State private var isViewActive = false
    @State private var healthCheckTask: Task<Void, Never>?
    @State private var pairingTask: Task<Void, Never>?
    @State private var uploadTask: Task<Void, Never>?
    @State private var healthCheckRunID: UUID?
    @State private var pairingRunID: UUID?
    @State private var uploadRunID: UUID?
    @FocusState private var focusedField: MacConnectionFocusedField?

    @StateObject private var uploadClient = SecureMacUploadClient()
    @StateObject private var syncCoordinator: StudyLibrarySyncCoordinator

    init(
        connectionStore: SecureMacConnectionStore,
        studyLibraryStore: StudyLibraryStore,
        recordingManager: RecordingManager? = nil,
        uploadCoordinator: RecordingUploadCoordinator? = nil
    ) {
        self.connectionStore = connectionStore
        _studyLibraryStore = ObservedObject(wrappedValue: studyLibraryStore)
        _syncCoordinator = StateObject(wrappedValue: StudyLibrarySyncCoordinator(
            connectionStore: connectionStore,
            studyLibraryStore: studyLibraryStore,
            recordingManager: recordingManager,
            uploadCoordinator: uploadCoordinator
        ))
    }

    var body: some View {
        RokuricsAdaptivePage { metrics in
            ZStack {
                RokuricsColors.pageGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        pageHeader

                        if shouldShowPairedContent {
                            pairedContent(metrics: metrics)
                        } else {
                            unpairedContent
                        }
                    }
                    .padding(.horizontal, RokuricsMobilePageLayoutMetrics.horizontalPadding)
                    .padding(.top, RokuricsMobilePageLayoutMetrics.topPadding)
                    .padding(.bottom, 34)
                    .rokuricsCenteredColumn(maxWidth: metrics.homeMaxWidth)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedField = nil
                            }
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)

                if let transientNotice {
                    VStack {
                        MacConnectionToastView(text: transientNotice)
                            .padding(.top, 12)
                            .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .frame(maxWidth: metrics.homeMaxWidth, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isDetailPresented) {
            MacConnectionDetailView(
                snapshot: settingsSnapshot,
                recentStatus: visibleFeedbackStatus,
                errorMessage: visibleFeedbackError,
                isUploading: isUploading,
                onCopyFingerprint: copyFingerprint,
                onUploadTest: {
                    startUploadTest()
                }
            )
        }
        .onAppear {
            isViewActive = true
            refreshConnectionState()
            syncCoordinator.startForegroundMonitoring()
        }
        .onDisappear {
            isViewActive = false
            cancelConnectionTasks()
            syncCoordinator.stopMonitoring()
        }
        .onChange(of: connectionStore.macHost) { _, _ in
            resetConnectionFeedback()
        }
        .onChange(of: connectionStore.macPortText) { _, newValue in
            sanitizePortInput(newValue)
            resetConnectionFeedback()
        }
        .onChange(of: pairingCode) { _, newValue in
            sanitizePairingCode(newValue)
        }
        .onChange(of: connectionStore.macFingerprint) { _, newValue in
            sanitizeFingerprintInput(newValue)
            resetConnectionFeedback()
        }
    }

    private var pageHeader: some View {
        RokuricsMobilePageHeader(
            leading: {
                RokuricsMobileBackButton(tint: RokuricsColors.deepText) {
                    dismiss()
                }
            },
            trailing: {
                if !shouldShowPairedContent {
                    MacConnectionStateCapsule(text: settingsSnapshot.isPaired ? "未连接" : "未配对")
                }
            }
        ) {
            RokuricsMixedLanguageTitle(
                english: "Mac",
                chinese: "连接",
                englishSize: RokuricsMobilePageLayoutMetrics.titleSize,
                chineseSize: RokuricsMobilePageLayoutMetrics.titleSize
            )
                .foregroundStyle(RokuricsColors.deepText)
        }
    }

    private var unpairedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                PairingInfoFormView(
                    host: $connectionStore.macHost,
                    portText: $connectionStore.macPortText,
                    fingerprint: $connectionStore.macFingerprint,
                    pairingCode: $pairingCode,
                    isFingerprintVisible: $isFingerprintVisible,
                    focusedField: $focusedField
                )

                Button {
                    pastePairingInfo()
                } label: {
                    Label("粘贴配对信息", systemImage: "doc.on.clipboard")
                        .font(RokuricsTypography.caption(size: 13, weight: .semibold))
                        .foregroundStyle(RokuricsColors.softTeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .rokuricsGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.32, shadowOpacity: 0.04, shadowRadius: 7, shadowY: 3)
                }
                .buttonStyle(RokuricsScaleButtonStyle())
            }
            .padding(18)
            .rokuricsLiquidGlassCard(cornerRadius: 28, material: .thinMaterial, fillOpacity: 0.42, strokeOpacity: 0.42, shadowOpacity: 0.10, shadowRadius: 17, shadowY: 9)

            VStack(spacing: 10) {
                Button {
                    startHealthCheck()
                } label: {
                    Label(isCheckingHTTPS ? "测试中" : "测试连接", systemImage: isCheckingHTTPS ? "arrow.triangle.2.circlepath" : "checkmark.shield")
                }
                .buttonStyle(.rokuricsPrimary)
                .disabled(!canRunHTTPSCheck)
                .opacity(canRunHTTPSCheck ? 1 : 0.52)

                Button {
                    startPairing()
                } label: {
                    Label(pairingActionTitle, systemImage: isPairing ? "arrow.triangle.2.circlepath" : "key.fill")
                }
                .buttonStyle(.rokuricsPrimary)
                .disabled(isPairing || isUploading || !canAttemptPairing)
                .opacity(isPairing || isUploading || !canAttemptPairing ? 0.62 : 1)

                Button {
                    startUploadTest()
                } label: {
                    Label(isUploading ? "上传中" : "上传测试", systemImage: isUploading ? "arrow.triangle.2.circlepath" : "lock.doc.fill")
                }
                .buttonStyle(RokuricsTintedCapsuleButtonStyle(tint: RokuricsColors.softTeal))
                .disabled(!canUploadSecurely || isUploading)
                .opacity(canUploadSecurely && !isUploading ? 1 : 0.42)
            }

            if shouldShowActionFeedback {
                MacConnectionFeedbackView(status: visibleFeedbackStatus, errorMessage: visibleFeedbackError)
            }
        }
    }

    private func pairedContent(metrics: RokuricsAdaptiveLayout.Metrics) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: metrics.isPadWidth ? 28 : 12)

            ConnectedDeviceBubbleView(deviceModel: settingsSnapshot.macModel)
                .frame(maxWidth: .infinity)

            Spacer(minLength: metrics.isPadWidth ? 32 : 18)

            ConnectedDeviceCardView(
                snapshot: settingsSnapshot,
                status: syncCoordinator.connectionStatus,
                isSyncing: syncCoordinator.isSyncing,
                onShowDetails: {
                    isDetailPresented = true
                },
                onSyncNow: {
                    startManualSync()
                },
                onDisconnect: disconnect
            )

        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: max(470, metrics.height - 168), alignment: .center)
    }

    private var settingsSnapshot: SecureMacConnectionSnapshot {
        connectionStore.snapshot
    }

    private var shouldShowPairedContent: Bool {
        settingsSnapshot.isPaired && connectionStore.userConnectionIntent == .wantsConnected
    }

    private var pairingActionTitle: String {
        isPairing ? "配对中" : "配对"
    }

    private var canUploadSecurely: Bool {
        uploadTestBlockedReason == nil
    }

    private var uploadTestBlockedReason: String? {
        MacUploadTestPresenceGate.blockedReason(
            snapshot: settingsSnapshot,
            status: syncCoordinator.connectionStatus,
            userConnectionIntent: connectionStore.userConnectionIntent
        )
    }

    private var canRunHTTPSCheck: Bool {
        !isCheckingHTTPS
            && !normalizedHost(connectionStore.macHost).isEmpty
            && connectionStore.macPort > 0
            && connectionStore.normalizedFingerprint.count == 64
    }

    private var shouldShowActionFeedback: Bool {
        feedbackKind != nil && (recentStatus != nil || errorMessage != nil)
    }

    private var visibleFeedbackStatus: String? {
        feedbackKind == nil ? nil : recentStatus
    }

    private var visibleFeedbackError: String? {
        feedbackKind == nil ? nil : errorMessage
    }

    private var canAttemptPairing: Bool {
        return !normalizedHost(connectionStore.macHost).isEmpty
            && connectionStore.macPort > 0
            && pairingCode.count == 6
            && connectionStore.normalizedFingerprint.count == 64
    }

    @MainActor
    private func startHealthCheck() {
        healthCheckTask?.cancel()
        let runID = UUID()
        healthCheckRunID = runID
        healthCheckTask = Task {
            await testHTTPSConnection(runID: runID)
        }
    }

    @MainActor
    private func startPairing() {
        pairingTask?.cancel()
        let runID = UUID()
        pairingRunID = runID
        pairingTask = Task {
            await attemptPairing(runID: runID)
        }
    }

    @MainActor
    private func startUploadTest() {
        uploadTask?.cancel()
        let runID = UUID()
        uploadRunID = runID
        uploadTask = Task {
            await uploadTestFile(runID: runID)
        }
    }

    @MainActor
    private func testHTTPSConnection(runID: UUID) async {
        print("[RokuricsHTTPSCheck] health check button tapped")

        guard canRunHTTPSCheck else {
            feedbackKind = .connectionTest
            recentStatus = "未测试"
            errorMessage = "请输入 Mac 地址、端口和完整指纹。"
            return
        }

        isCheckingHTTPS = true
        focusedField = nil
        feedbackKind = .connectionTest
        recentStatus = "正在测试连接"
        errorMessage = nil

        do {
            _ = try await uploadClient.healthCheck(
                host: normalizedHost(connectionStore.macHost),
                port: connectionStore.macPort,
                macFingerprint: connectionStore.macFingerprint
            )

            guard canUpdateViewState(for: runID, currentRunID: healthCheckRunID) else {
                return
            }

            recentStatus = "测试连接成功"
            errorMessage = nil
        } catch SecureMacUploadError.fingerprintMismatch {
            guard canUpdateViewState(for: runID, currentRunID: healthCheckRunID) else {
                return
            }

            recentStatus = "指纹不匹配"
            errorMessage = SecureMacUploadError.fingerprintMismatch.localizedDescription
        } catch {
            guard canUpdateViewState(for: runID, currentRunID: healthCheckRunID) else {
                return
            }

            recentStatus = "连接失败"
            errorMessage = error.localizedDescription
        }

        guard canUpdateViewState(for: runID, currentRunID: healthCheckRunID) else {
            return
        }

        isCheckingHTTPS = false
        healthCheckTask = nil
        healthCheckRunID = nil
    }

    @MainActor
    private func attemptPairing(runID: UUID) async {
        print("[RokuricsPairing] pairing button tapped")

        guard !normalizedHost(connectionStore.macHost).isEmpty, connectionStore.macPort > 0 else {
            feedbackKind = .pairing
            recentStatus = "配对未开始"
            errorMessage = "请输入 Mac 地址和端口。"
            return
        }

        guard pairingCode.count == 6 else {
            feedbackKind = .pairing
            recentStatus = "配对未开始"
            errorMessage = "请输入 Mac 上显示的 6 位配对码。"
            return
        }

        guard connectionStore.normalizedFingerprint.count == 64 else {
            feedbackKind = .pairing
            recentStatus = "配对未开始"
            errorMessage = "请输入 Mac 上显示的完整 certificate-sha256 指纹。"
            return
        }

        isPairing = true
        focusedField = nil
        feedbackKind = .pairing
        recentStatus = "正在配对"
        errorMessage = nil

        do {
            let normalizedFingerprint = connectionStore.normalizedFingerprint
            let result = try await uploadClient.pair(
                host: normalizedHost(connectionStore.macHost),
                port: connectionStore.macPort,
                pairingCode: pairingCode,
                macFingerprint: normalizedFingerprint
            )

            guard canUpdateViewState(for: runID, currentRunID: pairingRunID) else {
                return
            }

            try connectionStore.savePairing(
                result: result,
                host: connectionStore.macHost,
                portText: connectionStore.macPortText,
                fingerprint: normalizedFingerprint
            )
            ConnectionDiagnosticsStore.shared.record(
                phase: "userConnectionIntentChanged",
                deviceID: result.deviceID,
                result: UserConnectionIntent.wantsConnected.rawValue
            )

            pairingCode = ""
            feedbackKind = nil
            recentStatus = nil
            errorMessage = nil
        } catch SecureMacUploadError.fingerprintMismatch {
            guard canUpdateViewState(for: runID, currentRunID: pairingRunID) else {
                return
            }

            recentStatus = "指纹不匹配"
            errorMessage = SecureMacUploadError.fingerprintMismatch.localizedDescription
        } catch {
            guard canUpdateViewState(for: runID, currentRunID: pairingRunID) else {
                return
            }

            recentStatus = "配对失败"
            errorMessage = error.localizedDescription
        }

        guard canUpdateViewState(for: runID, currentRunID: pairingRunID) else {
            return
        }

        isPairing = false
        pairingTask = nil
        pairingRunID = nil
    }

    @MainActor
    private func uploadTestFile(runID: UUID) async {
        print("[RokuricsSecureUpload] upload button tapped")
        let blockedReason = uploadTestBlockedReason
        ConnectionDiagnosticsStore.shared.record(
            phase: "uploadTestGateEvaluated",
            deviceID: settingsSnapshot.deviceID,
            uploadTestBlockedReason: blockedReason ?? "allowed"
        )
        guard blockedReason == nil else {
            ConnectionDiagnosticsStore.shared.record(
                phase: "uploadTestBlockedReason",
                deviceID: settingsSnapshot.deviceID,
                uploadTestBlockedReason: blockedReason
            )
            feedbackKind = .upload
            recentStatus = "上传测试已阻断"
            errorMessage = uploadTestBlockedMessage(for: blockedReason)
            return
        }

        isUploading = true
        focusedField = nil
        feedbackKind = .upload
        recentStatus = "正在上传测试"
        errorMessage = nil

        do {
            let result = try await uploadClient.uploadTestFile(settings: settingsSnapshot)
            guard canUpdateViewState(for: runID, currentRunID: uploadRunID) else {
                return
            }

            syncCoordinator.recordSignedRequestSucceeded(settings: settingsSnapshot)
            recentStatus = "上传测试成功：\(result.fileName)"
            errorMessage = nil
        } catch SecureMacUploadError.fingerprintMismatch {
            guard canUpdateViewState(for: runID, currentRunID: uploadRunID) else {
                return
            }

            recentStatus = "指纹不匹配"
            errorMessage = SecureMacUploadError.fingerprintMismatch.localizedDescription
        } catch {
            guard canUpdateViewState(for: runID, currentRunID: uploadRunID) else {
                return
            }

            recentStatus = "上传测试已阻断"
            errorMessage = error.localizedDescription
        }

        guard canUpdateViewState(for: runID, currentRunID: uploadRunID) else {
            return
        }

        isUploading = false
        uploadTask = nil
        uploadRunID = nil
    }

    private func uploadTestBlockedMessage(for reason: String?) -> String {
        switch reason {
        case "not_paired":
            return SecureMacUploadError.notPaired.localizedDescription
        case "user_does_not_want_connection":
            return "当前已断开连接，请重新配对。"
        case "security_error":
            return "连接处于安全错误状态，请重新配对。"
        case "heartbeat_interrupted", "heartbeat_stale", "heartbeat_disconnected", "heartbeat_not_online", "presence_unavailable":
            return "Mac 当前未在线，请等待前台心跳恢复后再测试上传。"
        case "https_upload_disabled":
            return "HTTPS 上传未启用。"
        default:
            return "Mac 当前未在线，请等待前台心跳恢复后再测试上传。"
        }
    }

    @MainActor
    private func disconnect() {
        let snapshot = settingsSnapshot
        syncCoordinator.stopMonitoring()
        syncCoordinator.recordUserDisconnected()
        ConnectionDiagnosticsStore.shared.record(
            phase: "disconnectTapped",
            deviceID: snapshot.deviceID,
            result: UserConnectionIntent.disconnectedByUser.rawValue
        )
        Task { @MainActor in
            do {
                try connectionStore.clearPairing()
                ConnectionDiagnosticsStore.shared.record(phase: "localCredentialsDeleted", deviceID: snapshot.deviceID)
            } catch {
                ConnectionDiagnosticsStore.shared.record(
                    phase: "localCredentialsDeleted",
                    deviceID: snapshot.deviceID,
                    errorCode: "credential_delete_failed",
                    errorMessage: error.localizedDescription
                )
            }
            syncCoordinator.refreshPairingState()
            pairingCode = ""
            isFingerprintVisible = false
            focusedField = nil
            clearFeedback()
            isDetailPresented = false

            if snapshot.isPaired {
                ConnectionDiagnosticsStore.shared.record(phase: "remoteUnpairAttempted", deviceID: snapshot.deviceID)
                do {
                    _ = try await uploadClient.sendDeviceUnpair(settings: snapshot)
                    ConnectionDiagnosticsStore.shared.record(phase: "remoteUnpairSucceeded", deviceID: snapshot.deviceID)
                } catch {
                    ConnectionDiagnosticsStore.shared.record(
                        phase: "remoteUnpairFailed",
                        deviceID: snapshot.deviceID,
                        errorCode: "remote_unpair_failed",
                        errorMessage: error.localizedDescription
                    )
                }
            }
        }
    }

    @MainActor
    private func startManualSync() {
        Task {
            await syncCoordinator.synchronizeNow()
        }
    }

    @MainActor
    private func pastePairingInfo() {
        guard let text = UIPasteboard.general.string,
              let pairingInfo = RokuricsPairingInfoParser.parse(text) else {
            showTransientNotice("剪贴板中没有可识别的配对信息")
            return
        }

        connectionStore.applyPairingInfo(pairingInfo)
        pairingCode = pairingInfo.pairingCode
        focusedField = nil
        clearFeedback()
    }

    @MainActor
    private func copyFingerprint() {
        UIPasteboard.general.string = settingsSnapshot.macFingerprint
        showTransientNotice("指纹已复制")
    }

    private func normalizedHost(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/")
            .first
            .flatMap { $0.split(separator: ":").first }
            .map(String.init) ?? ""
    }

    @MainActor
    private func refreshConnectionState() {
        connectionStore.refreshFromStorage()

        if let storageError = connectionStore.storageError {
            showTransientNotice("Keychain 读取失败：\(storageError)")
        } else if settingsSnapshot.isPaired {
            clearFeedback()
        }
    }

    @MainActor
    private func resetConnectionFeedback() {
        guard !isPairing, !isCheckingHTTPS, !isUploading else {
            return
        }

        if feedbackKind != nil {
            clearFeedback()
        }
    }

    @MainActor
    private func clearFeedback() {
        feedbackKind = nil
        recentStatus = nil
        errorMessage = nil
    }

    @MainActor
    private func showTransientNotice(_ message: String) {
        guard isViewActive else {
            return
        }

        transientNoticeToken += 1
        let token = transientNoticeToken

        withAnimation(.easeInOut(duration: 0.18)) {
            transientNotice = message
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            await MainActor.run {
                guard isViewActive, token == transientNoticeToken else {
                    return
                }

                withAnimation(.easeInOut(duration: 0.18)) {
                    transientNotice = nil
                }
            }
        }
    }

    @MainActor
    private func cancelConnectionTasks() {
        healthCheckTask?.cancel()
        pairingTask?.cancel()
        uploadTask?.cancel()
        healthCheckTask = nil
        pairingTask = nil
        uploadTask = nil
        healthCheckRunID = nil
        pairingRunID = nil
        uploadRunID = nil
    }

    @MainActor
    private func canUpdateViewState(for runID: UUID, currentRunID: UUID?) -> Bool {
        isViewActive && !Task.isCancelled && currentRunID == runID
    }

    @MainActor
    private func sanitizePortInput(_ value: String) {
        let sanitized = SecureMacConnectionStore.sanitizedPortText(value)
        guard sanitized == value else {
            connectionStore.macPortText = sanitized
            return
        }
    }

    @MainActor
    private func sanitizePairingCode(_ value: String) {
        let sanitized = String(value.filter(\.isNumber).prefix(6))
        guard sanitized == value else {
            pairingCode = sanitized
            return
        }

        if sanitized.count == 6 {
            focusedField = nil
        }
    }

    @MainActor
    private func sanitizeFingerprintInput(_ value: String) {
        let sanitized = String(SecureUploadUtilities.normalizedCertificateFingerprint(value).prefix(64))
        guard sanitized == value else {
            connectionStore.macFingerprint = sanitized
            return
        }

        if sanitized.count == 64, focusedField == .fingerprint {
            focusedField = nil
        }
    }
}

private struct MacConnectionStateCapsule: View {
    let text: String

    var body: some View {
        Text(text)
            .font(RokuricsTypography.caption(size: 12, weight: .bold))
            .foregroundStyle(RokuricsColors.softTeal)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .rokuricsGlassCapsule(fillOpacity: 0.36, strokeOpacity: 0.34, shadowOpacity: 0.04, shadowRadius: 7, shadowY: 3)
    }
}

private struct PairingInfoFormView: View {
    @Binding var host: String
    @Binding var portText: String
    @Binding var fingerprint: String
    @Binding var pairingCode: String
    @Binding var isFingerprintVisible: Bool
    let focusedField: FocusState<MacConnectionFocusedField?>.Binding

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                TextField("Mac 地址", text: $host)
                    .font(RokuricsTypography.technical(size: 17, weight: .semibold))
                    .foregroundStyle(RokuricsColors.deepText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
                    .focused(focusedField, equals: .host)
                    .macInputCapsule()

                TextField("端口", text: $portText)
                    .font(RokuricsTypography.technical(size: 17, weight: .semibold))
                    .foregroundStyle(RokuricsColors.deepText)
                    .keyboardType(.numberPad)
                    .focused(focusedField, equals: .port)
                    .multilineTextAlignment(.center)
                    .macInputCapsule()
                    .frame(width: 94)
            }

            MacFingerprintField(
                fingerprint: $fingerprint,
                isVisible: $isFingerprintVisible,
                focusedField: focusedField
            )

            TextField("配对码", text: $pairingCode)
                .font(RokuricsTypography.technical(size: 18, weight: .bold))
                .foregroundStyle(RokuricsColors.deepText)
                .keyboardType(.numberPad)
                .focused(focusedField, equals: .pairingCode)
                .macInputCapsule()
        }
    }
}

private struct MacFingerprintField: View {
    @Binding var fingerprint: String
    @Binding var isVisible: Bool
    let focusedField: FocusState<MacConnectionFocusedField?>.Binding

    var body: some View {
        fieldContent
            .animation(.easeInOut(duration: 0.18), value: isVisible)
    }

    @ViewBuilder
    private var fieldContent: some View {
        if isVisible {
            inputRow
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(minHeight: 124)
                .rokuricsLiquidGlassCard(cornerRadius: 18, material: .thinMaterial, fillOpacity: 0.34, strokeOpacity: 0.32, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
        } else {
            inputRow
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .rokuricsGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.32, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
        }
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            if isVisible {
                TextField("Mac 指纹", text: groupedFingerprintBinding, axis: .vertical)
                    .font(RokuricsTypography.fingerprint(size: 15, weight: .semibold))
                    .foregroundStyle(RokuricsColors.deepText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused(focusedField, equals: .fingerprint)
                    .lineLimit(4, reservesSpace: true)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ZStack(alignment: .leading) {
                    TextField("Mac 指纹", text: rawFingerprintBinding)
                        .font(RokuricsTypography.fingerprint(size: 15, weight: .semibold))
                        .foregroundStyle(fingerprint.isEmpty ? RokuricsColors.deepText : .clear)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused(focusedField, equals: .fingerprint)

                    if !fingerprint.isEmpty {
                        Text(maskedCertificateFingerprint(fingerprint))
                            .font(RokuricsTypography.fingerprint(size: 15, weight: .semibold))
                            .foregroundStyle(RokuricsColors.deepText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsHitTesting(false)
                    }
                }
            }

            Button {
                isVisible.toggle()
            } label: {
                Text(isVisible ? "隐藏" : "显示")
                    .font(RokuricsTypography.caption(size: 12, weight: .bold))
                    .foregroundStyle(RokuricsColors.softTeal)
                    .frame(minWidth: 36)
            }
            .buttonStyle(RokuricsScaleButtonStyle())
        }
    }

    private var rawFingerprintBinding: Binding<String> {
        Binding(
            get: { fingerprint },
            set: { fingerprint = String(SecureUploadUtilities.normalizedCertificateFingerprint($0).prefix(64)) }
        )
    }

    private var groupedFingerprintBinding: Binding<String> {
        Binding(
            get: { formattedCertificateFingerprint(fingerprint) },
            set: { fingerprint = String(SecureUploadUtilities.normalizedCertificateFingerprint($0).prefix(64)) }
        )
    }
}

private struct ConnectedDeviceBubbleView: View {
    let deviceModel: String
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RokuricsColors.quietGradient)
                .frame(width: 98, height: 98)
                .opacity(0.56)
                .offset(x: -86, y: -62)
                .scaleEffect(isBreathing ? 1.05 : 0.97)

            Circle()
                .fill(RokuricsColors.actionGradient)
                .frame(width: 82, height: 82)
                .opacity(0.34)
                .offset(x: 90, y: -42)
                .scaleEffect(isBreathing ? 0.98 : 1.05)

            Circle()
                .fill(RokuricsColors.quietGradient)
                .frame(width: 76, height: 76)
                .opacity(0.38)
                .offset(x: 72, y: 84)
                .scaleEffect(isBreathing ? 1.04 : 0.98)

            Circle()
                .fill(RokuricsColors.actionGradient)
                .frame(width: 196, height: 196)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.38),
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.03)
                                ],
                                center: .topLeading,
                                startRadius: 12,
                                endRadius: 150
                            )
                        )
                        .padding(1)
                }
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.56),
                                    Color.white.opacity(0.12),
                                    RokuricsColors.aqua.opacity(0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                }
                .shadow(color: RokuricsColors.shadow.opacity(0.22), radius: 30, x: 0, y: 18)
                .scaleEffect(isBreathing ? 1.018 : 0.992)

            Image(systemName: iconName)
                .font(.system(size: 68, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: RokuricsColors.deepText.opacity(0.14), radius: 8, y: 4)
        }
        .frame(width: 286, height: 286)
        .onAppear {
            withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private var iconName: String {
        let normalizedModel = deviceModel.lowercased()

        if normalizedModel.contains("imac") {
            return "desktopcomputer"
        }

        if normalizedModel.contains("mini") {
            return "macmini"
        }

        if normalizedModel.contains("studio") {
            return "macstudio"
        }

        if normalizedModel.contains("book") {
            return "laptopcomputer"
        }

        return "laptopcomputer"
    }
}

private struct ConnectedDeviceCardView: View {
    let snapshot: SecureMacConnectionSnapshot
    let status: DeviceConnectionStatus
    let isSyncing: Bool
    let onShowDetails: () -> Void
    let onSyncNow: () -> Void
    let onDisconnect: () -> Void
    @State private var presenceNow = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                RokuricsMixedFontText(
                    text: displayName,
                    chineseFont: RokuricsTypography.chineseTitle(size: 25, weight: .semibold),
                    englishFont: RokuricsTypography.englishTitle(size: 25, weight: .semibold),
                    numberFont: RokuricsTypography.numberBody(size: 25, weight: .semibold)
                )
                    .foregroundStyle(RokuricsColors.deepText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text(addressLine)
                    .font(RokuricsTypography.technical(size: 14, weight: .semibold))
                    .foregroundStyle(RokuricsColors.tertiaryText)
            }

            VStack(spacing: 10) {
                MacConnectionStatusLine(title: "状态", value: stateText, tint: stateTint)
                MacConnectionStatusLine(title: "最近连接", value: presence.recentOnlineText, tint: RokuricsColors.softText)
                MacConnectionStatusLine(title: "最近同步", value: lastSyncText, tint: RokuricsColors.softText)
            }
            .padding(14)
            .rokuricsLiquidGlassCard(cornerRadius: 20, material: .thinMaterial, fillOpacity: 0.30, strokeOpacity: 0.26, shadowOpacity: 0.04, shadowRadius: 7, shadowY: 3)

            VStack(spacing: 10) {
                Button {
                    onSyncNow()
                } label: {
                    Text(isSyncing ? "同步中" : "立即同步")
                }
                .buttonStyle(.rokuricsPrimary)
                .disabled(isSyncing || !snapshot.isPaired)
                .opacity(isSyncing || !snapshot.isPaired ? 0.62 : 1)

                Button("查看连接信息", action: onShowDetails)
                    .buttonStyle(RokuricsTintedCapsuleButtonStyle(tint: RokuricsColors.softTeal, verticalPadding: 13))

                Button("断开连接", action: onDisconnect)
                    .buttonStyle(RokuricsTintedCapsuleButtonStyle(tint: RokuricsColors.coral))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 28, material: .thinMaterial, fillOpacity: 0.42, strokeOpacity: 0.42, shadowOpacity: 0.10, shadowRadius: 17, shadowY: 9)
        .task {
            while !Task.isCancelled {
                presenceNow = Date()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var displayName: String {
        let trimmedName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Rokurics Mac" : trimmedName
    }

    private var addressLine: String {
        let host = snapshot.macHost.isEmpty ? "-" : snapshot.macHost
        let port = snapshot.macPort > 0 ? "\(snapshot.macPort)" : "\(SecureMacConnectionSettings.defaultPort)"
        return "\(host) · \(port)"
    }

    private var stateText: String {
        presence.statusText
    }

    private var stateTint: Color {
        switch presence.state {
        case .online:
            return RokuricsColors.softTeal
        case .connecting:
            return RokuricsColors.aqua
        case .interrupted, .stale, .disconnected, .securityError, .unknown:
            return RokuricsColors.coral
        }
    }

    private var presence: ConnectionPresenceSnapshot {
        status.presenceSnapshot(now: presenceNow)
    }

    private var lastSyncText: String {
        if let lastSyncAt = status.lastSyncAt {
            let relative = Self.relativeDateFormatter.localizedString(for: lastSyncAt, relativeTo: Date())
            if let lastSyncStatus = status.lastSyncStatus, !lastSyncStatus.isEmpty {
                return "\(relative) · \(lastSyncStatus)"
            }
            return relative
        }

        return status.lastSyncStatus ?? "暂无"
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct MacConnectionStatusLine: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                .foregroundStyle(RokuricsColors.tertiaryText)
                .frame(width: 64, alignment: .leading)

            Text(value)
                .font(RokuricsTypography.body(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
    }
}

private struct MacConnectionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: SecureMacConnectionSnapshot
    let recentStatus: String?
    let errorMessage: String?
    let isUploading: Bool
    let onCopyFingerprint: () -> Void
    let onUploadTest: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    MacConnectionDetailRow(title: "Mac 地址", value: snapshot.macHost.isEmpty ? "-" : snapshot.macHost, isTechnical: true)
                    MacConnectionDetailRow(title: "端口", value: snapshot.macPort > 0 ? "\(snapshot.macPort)" : "\(SecureMacConnectionSettings.defaultPort)", isTechnical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Mac 指纹")
                                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                                .foregroundStyle(RokuricsColors.tertiaryText)

                            Spacer()

                            Button("复制", action: onCopyFingerprint)
                                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                                .foregroundStyle(RokuricsColors.softTeal)
                        }

                        Text(formattedCertificateFingerprint(snapshot.macFingerprint))
                            .font(RokuricsTypography.fingerprint(size: 13, weight: .semibold))
                            .foregroundStyle(RokuricsColors.deepText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .rokuricsLiquidGlassCard(cornerRadius: 22, material: .thinMaterial, fillOpacity: 0.36, strokeOpacity: 0.32, shadowOpacity: 0.06, shadowRadius: 10, shadowY: 5)

                    MacConnectionPairingStatusRow(
                        title: "配对状态",
                        stateText: snapshot.isPaired ? "已配对" : "未配对",
                        deviceIDPrefix: deviceIDPrefix
                    )

                    Button {
                        onUploadTest()
                    } label: {
                        Label(isUploading ? "上传中" : "上传测试", systemImage: isUploading ? "arrow.triangle.2.circlepath" : "lock.doc.fill")
                    }
                    .buttonStyle(RokuricsTintedCapsuleButtonStyle(tint: RokuricsColors.softTeal))
                    .disabled(isUploading)
                    .opacity(isUploading ? 0.62 : 1)
                    .padding(.top, 2)

                    if recentStatus != nil || errorMessage != nil {
                        MacConnectionFeedbackView(status: recentStatus, errorMessage: errorMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 34)
            }
            .background(RokuricsColors.pageGradient.ignoresSafeArea())
            .navigationTitle("连接信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var deviceIDPrefix: String {
        String(snapshot.deviceID.prefix(12))
    }
}

private struct MacConnectionDetailRow: View {
    let title: String
    let value: String
    var isTechnical = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                .foregroundStyle(RokuricsColors.tertiaryText)

            Text(value)
                .font(isTechnical ? RokuricsTypography.technical(size: 17, weight: .semibold) : RokuricsTypography.body(size: 17, weight: .semibold))
                .foregroundStyle(RokuricsColors.deepText)
                .textSelection(.enabled)
                .lineLimit(3)
                .minimumScaleFactor(0.76)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 22, material: .thinMaterial, fillOpacity: 0.36, strokeOpacity: 0.32, shadowOpacity: 0.06, shadowRadius: 10, shadowY: 5)
    }
}

private struct MacConnectionPairingStatusRow: View {
    let title: String
    let stateText: String
    let deviceIDPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(RokuricsTypography.caption(size: 12, weight: .bold))
                .foregroundStyle(RokuricsColors.tertiaryText)

            HStack(spacing: 7) {
                Text(stateText)
                    .font(RokuricsTypography.body(size: 17, weight: .semibold))

                if !deviceIDPrefix.isEmpty {
                    Text("·")
                        .font(RokuricsTypography.body(size: 17, weight: .semibold))

                    Text(deviceIDPrefix)
                        .font(RokuricsTypography.technical(size: 17, weight: .semibold))
                        .textSelection(.enabled)
                }
            }
            .foregroundStyle(RokuricsColors.deepText)
            .lineLimit(2)
            .minimumScaleFactor(0.76)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 22, material: .thinMaterial, fillOpacity: 0.36, strokeOpacity: 0.32, shadowOpacity: 0.06, shadowRadius: 10, shadowY: 5)
    }
}

private struct MacConnectionToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(RokuricsTypography.caption(size: 12, weight: .bold))
            .foregroundStyle(RokuricsColors.deepText)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .rokuricsLiquidGlassCard(cornerRadius: 18, material: .thinMaterial, fillOpacity: 0.42, strokeOpacity: 0.34, shadowOpacity: 0.08, shadowRadius: 10, shadowY: 5)
    }
}

private struct MacConnectionFeedbackView: View {
    let status: String?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let status {
                Text(status)
                    .font(RokuricsTypography.body(size: 14, weight: .bold))
                    .foregroundStyle(errorMessage == nil ? RokuricsColors.softTeal : RokuricsColors.coral)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                    .foregroundStyle(RokuricsColors.coral)
                    .lineLimit(4)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 22, material: .thinMaterial, fillOpacity: 0.34, strokeOpacity: 0.30, shadowOpacity: 0.05, shadowRadius: 9, shadowY: 4)
    }
}

private struct RokuricsTintedCapsuleButtonStyle: ButtonStyle {
    let tint: Color
    var verticalPadding: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RokuricsTypography.button())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, verticalPadding)
            .background(tint.opacity(configuration.isPressed ? 0.76 : 0.88), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            }
            .shadow(color: tint.opacity(configuration.isPressed ? 0.08 : 0.16), radius: 14, y: 7)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private extension View {
    func macInputCapsule() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: 52)
            .rokuricsGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.32, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
    }
}

private func formattedCertificateFingerprint(_ value: String, groupsPerLine: Int = 4) -> String {
    let normalized = SecureUploadUtilities.normalizedCertificateFingerprint(value)
    guard !normalized.isEmpty else {
        return ""
    }

    var groups: [String] = []
    var currentIndex = normalized.startIndex

    while currentIndex < normalized.endIndex {
        let nextIndex = normalized.index(currentIndex, offsetBy: 4, limitedBy: normalized.endIndex) ?? normalized.endIndex
        groups.append(String(normalized[currentIndex..<nextIndex]))
        currentIndex = nextIndex
    }

    guard groupsPerLine > 0 else {
        return groups.joined(separator: " ")
    }

    var rows: [String] = []
    var rowStart = 0
    while rowStart < groups.count {
        let rowEnd = min(rowStart + groupsPerLine, groups.count)
        rows.append(groups[rowStart..<rowEnd].joined(separator: " "))
        rowStart = rowEnd
    }

    return rows.joined(separator: "\n")
}

private func maskedCertificateFingerprint(_ value: String) -> String {
    let normalized = SecureUploadUtilities.normalizedCertificateFingerprint(value)
    guard normalized.count > 16 else {
        return formattedCertificateFingerprint(normalized)
    }

    let prefix = String(normalized.prefix(8))
    let suffix = String(normalized.suffix(8))
    return "\(formattedCertificateFingerprint(prefix, groupsPerLine: 0)) •••• •••• •••• \(formattedCertificateFingerprint(suffix, groupsPerLine: 0))"
}

#Preview {
    NavigationStack {
        MacConnectionView(
            connectionStore: SecureMacConnectionStore(),
            studyLibraryStore: StudyLibraryStore()
        )
    }
}
