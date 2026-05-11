//
//  MacConnectionView.swift
//  Rokurics
//
//  Created by Codex on 2026/5/10.
//

import SwiftUI
import UIKit

struct MacConnectionView: View {
    @AppStorage(SecureMacConnectionSettings.macHostKey) private var host = ""
    @AppStorage(SecureMacConnectionSettings.macPortKey) private var port = SecureMacConnectionSettings.defaultPort
    @AppStorage(SecureMacConnectionSettings.macFingerprintKey) private var macFingerprint = ""
    @AppStorage(SecureMacConnectionSettings.pairedAtKey) private var pairedAt = ""
    @State private var deviceID = ""
    @State private var sharedSecret = ""
    @State private var pairingCode = ""
    @State private var isCheckingHTTPS = false
    @State private var hasVerifiedHTTPS = false
    @State private var isPairing = false
    @State private var isUploading = false
    @State private var recentStatus = "尚未安全配对"
    @State private var errorMessage: String?
    @State private var diagnosticSteps = ["未测试"]

    @StateObject private var uploadClient = SecureMacUploadClient()
    private let keychainStore = KeychainStore()

    var body: some View {
        RokuricsAdaptivePage { metrics in
            ZStack {
                RokuricsColors.pageGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        VStack(alignment: .leading, spacing: 14) {
                            MacConnectionInputField(
                                title: "Mac 地址",
                                placeholder: "192.168.1.23",
                                text: $host,
                                keyboardType: .numbersAndPunctuation
                            )

                            MacConnectionPortField(port: $port)

                            MacConnectionInputField(
                                title: "配对码",
                                placeholder: "6 位一次性码",
                                text: $pairingCode,
                                keyboardType: .numberPad
                            )

                            MacConnectionInputField(
                                title: "Mac 指纹",
                                placeholder: "Mac 上显示的完整证书指纹",
                                text: $macFingerprint,
                                keyboardType: .asciiCapable
                            )

                            HStack(spacing: 8) {
                                RokuricsStatusPill(text: "同一 Wi-Fi", systemImage: "wifi", tint: RokuricsColors.softTeal)
                                RokuricsStatusPill(text: "HTTPS 8787", systemImage: "lock.fill", tint: RokuricsColors.aqua)
                                RokuricsStatusPill(text: pairedStatusText, systemImage: "checkmark.shield", tint: settingsSnapshot.isPaired ? RokuricsColors.mint : RokuricsColors.tertiaryText)
                            }
                        }
                        .padding(18)
                        .rokuricsLiquidGlassCard(cornerRadius: 28, material: .thinMaterial, fillOpacity: 0.42, strokeOpacity: 0.42, shadowOpacity: 0.10, shadowRadius: 17, shadowY: 9)

                        Button {
                            Task {
                                await testHTTPSConnection()
                            }
                        } label: {
                            Label(isCheckingHTTPS ? "正在验证 HTTPS" : "测试 HTTPS 连接", systemImage: isCheckingHTTPS ? "arrow.triangle.2.circlepath" : "checkmark.shield")
                        }
                        .buttonStyle(.rokuricsPrimary)
                        .disabled(!canRunHTTPSCheck)
                        .opacity(canRunHTTPSCheck ? 1 : 0.52)

                        Button {
                            Task {
                                await attemptPairing()
                            }
                        } label: {
                            Label(isPairing ? "配对中" : "配对", systemImage: isPairing ? "arrow.triangle.2.circlepath" : "key.fill")
                        }
                        .buttonStyle(.rokuricsPrimary)
                        .disabled(isPairing || isUploading || !hasVerifiedHTTPS)
                        .opacity(isPairing || isUploading || !hasVerifiedHTTPS ? 0.62 : 1)

                        Button {
                            Task {
                                await uploadTestFile()
                            }
                        } label: {
                            Label(isUploading ? "安全上传中" : "上传安全测试文件", systemImage: isUploading ? "arrow.triangle.2.circlepath" : "lock.doc.fill")
                        }
                        .buttonStyle(.rokuricsPrimary)
                        .disabled(isUploading || !canUploadSecurely)
                        .opacity(canUploadSecurely && !isUploading ? 1 : 0.52)

                        MacConnectionStatusCard(
                            title: "安全状态",
                            status: recentStatus,
                            errorMessage: errorMessage,
                            diagnosticSteps: diagnosticSteps
                        )

                        Text("需与 Mac 在同一 Wi-Fi；未完成 HTTPS 配对前不会上传")
                            .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                            .foregroundStyle(RokuricsColors.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, 34)
                    .rokuricsCenteredColumn(maxWidth: metrics.homeMaxWidth)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Mac 连接")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            loadSecurePairingFromKeychain()
        }
        .onChange(of: host) { _, _ in
            resetHTTPSCheck()
        }
        .onChange(of: port) { _, _ in
            resetHTTPSCheck()
        }
        .onChange(of: macFingerprint) { _, _ in
            resetHTTPSCheck()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mac 连接")
                .font(RokuricsTypography.title(size: 34))
                .foregroundStyle(RokuricsColors.deepText)

            Text("安全连接")
                .font(RokuricsTypography.body(size: 14, weight: .medium))
                .foregroundStyle(RokuricsColors.softText)
        }
    }

    private var settingsSnapshot: SecureMacConnectionSnapshot {
        SecureMacConnectionSnapshot(
            macHost: normalizedHost(host),
            macPort: port,
            macFingerprint: macFingerprint.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceID: deviceID,
            sharedSecretBase64URL: sharedSecret,
            pairedAt: pairedAt
        )
    }

    private var pairedStatusText: String {
        settingsSnapshot.isPaired ? "已配对" : "未配对"
    }

    private var canUploadSecurely: Bool {
        settingsSnapshot.isPaired && hasVerifiedHTTPS && SecureMacUploadClient.isHTTPSUploadEnabled
    }

    private var canRunHTTPSCheck: Bool {
        !isCheckingHTTPS
            && !normalizedHost(host).isEmpty
            && port > 0
            && !macFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func testHTTPSConnection() async {
        print("[RokuricsHTTPSCheck] health check button tapped")

        guard canRunHTTPSCheck else {
            recentStatus = "未测试"
            errorMessage = "请输入 Mac IP、端口和完整指纹。"
            return
        }

        isCheckingHTTPS = true
        hasVerifiedHTTPS = false
        recentStatus = "正在验证 HTTPS"
        errorMessage = nil
        diagnosticSteps = []

        do {
            _ = try await uploadClient.healthCheck(
                host: normalizedHost(host),
                port: port,
                macFingerprint: macFingerprint,
                diagnostics: { step in
                    Task { @MainActor in
                        appendDiagnosticStep(step)
                    }
                }
            )

            hasVerifiedHTTPS = true
            recentStatus = "HTTPS 连接成功 / 指纹已验证"
            errorMessage = nil
        } catch SecureMacUploadError.fingerprintMismatch {
            recentStatus = "指纹不匹配"
            errorMessage = SecureMacUploadError.fingerprintMismatch.localizedDescription
        } catch {
            recentStatus = "连接失败"
            errorMessage = error.localizedDescription
        }

        isCheckingHTTPS = false
    }

    @MainActor
    private func attemptPairing() async {
        print("[RokuricsPairing] pairing button tapped")

        guard !normalizedHost(host).isEmpty, port > 0 else {
            recentStatus = "配对未开始"
            errorMessage = "请输入 Mac IP 和端口。"
            return
        }

        guard !pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recentStatus = "配对未开始"
            errorMessage = "请输入 Mac 上显示的 6 位配对码。"
            return
        }

        guard !macFingerprint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recentStatus = "配对未开始"
            errorMessage = "请输入 Mac 上显示的指纹。"
            return
        }

        guard hasVerifiedHTTPS else {
            recentStatus = "配对未开始"
            errorMessage = "请先完成 HTTPS 连接测试。"
            return
        }

        isPairing = true
        recentStatus = "验证 Mac 指纹"
        errorMessage = nil

        do {
            let normalizedFingerprint = SecureUploadUtilities.normalizedCertificateFingerprint(macFingerprint)
            let result = try await uploadClient.pair(
                host: normalizedHost(host),
                port: port,
                pairingCode: pairingCode,
                macFingerprint: normalizedFingerprint
            )

            do {
                try keychainStore.save(result.deviceID, account: SecureMacConnectionSettings.deviceIDKey)
                try keychainStore.save(result.sharedSecretBase64URL, account: SecureMacConnectionSettings.sharedSecretKey)
                try keychainStore.save(normalizedFingerprint, account: SecureMacConnectionSettings.macFingerprintKey)
            } catch {
                try? keychainStore.delete(account: SecureMacConnectionSettings.deviceIDKey)
                try? keychainStore.delete(account: SecureMacConnectionSettings.sharedSecretKey)
                try? keychainStore.delete(account: SecureMacConnectionSettings.macFingerprintKey)
                throw error
            }

            deviceID = result.deviceID
            sharedSecret = result.sharedSecretBase64URL
            macFingerprint = normalizedFingerprint
            pairedAt = result.pairedAt
            SecureMacConnectionSettings.clearPrototypeSharedSecretFromDefaults()

            recentStatus = "配对成功"
            errorMessage = nil
        } catch SecureMacUploadError.fingerprintMismatch {
            recentStatus = "指纹不匹配"
            errorMessage = SecureMacUploadError.fingerprintMismatch.localizedDescription
        } catch {
            recentStatus = "配对失败"
            errorMessage = error.localizedDescription
        }

        isPairing = false
    }

    @MainActor
    private func uploadTestFile() async {
        print("[RokuricsSecureUpload] upload button tapped")
        isUploading = true
        errorMessage = nil
        recentStatus = "准备安全测试 JSON"

        do {
            let result = try await uploadClient.uploadTestFile(settings: settingsSnapshot)
            recentStatus = "安全上传成功：\(result.fileName)"
            errorMessage = nil
        } catch SecureMacUploadError.fingerprintMismatch {
            recentStatus = "指纹不匹配"
            errorMessage = SecureMacUploadError.fingerprintMismatch.localizedDescription
        } catch {
            recentStatus = "安全上传已阻断"
            errorMessage = error.localizedDescription
        }

        isUploading = false
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
    private func loadSecurePairingFromKeychain() {
        SecureMacConnectionSettings.clearPrototypeSharedSecretFromDefaults()

        do {
            if let storedDeviceID = try keychainStore.load(account: SecureMacConnectionSettings.deviceIDKey) {
                deviceID = storedDeviceID
            }
            if let storedSecret = try keychainStore.load(account: SecureMacConnectionSettings.sharedSecretKey) {
                sharedSecret = storedSecret
            }
            if let storedFingerprint = try keychainStore.load(account: SecureMacConnectionSettings.macFingerprintKey), !storedFingerprint.isEmpty {
                macFingerprint = storedFingerprint
            }

            if settingsSnapshot.isPaired {
                recentStatus = "已配对"
                errorMessage = nil
            }
        } catch {
            recentStatus = "Keychain 读取失败"
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func resetHTTPSCheck() {
        hasVerifiedHTTPS = false
        if !isCheckingHTTPS {
            recentStatus = settingsSnapshot.isPaired ? "已配对，HTTPS 未重新测试" : "未测试"
            errorMessage = nil
            diagnosticSteps = ["未测试"]
        }
    }

    @MainActor
    private func appendDiagnosticStep(_ step: String) {
        guard diagnosticSteps.last != step else {
            return
        }

        diagnosticSteps.append(step)
        if diagnosticSteps.count > 6 {
            diagnosticSteps.removeFirst(diagnosticSteps.count - 6)
        }
    }
}

private struct MacConnectionInputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)

            TextField(placeholder, text: $text)
                .font(RokuricsTypography.body(size: 17, weight: .semibold))
                .foregroundStyle(RokuricsColors.deepText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboardType)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .rokuricsGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.32, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
        }
    }
}

private struct MacConnectionPortField: View {
    @Binding var port: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("端口")
                .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)

            TextField("8787", value: $port, format: .number)
                .font(RokuricsTypography.body(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(RokuricsColors.deepText)
                .keyboardType(.numberPad)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .rokuricsGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.32, shadowOpacity: 0.04, shadowRadius: 8, shadowY: 4)
        }
    }
}

private struct MacConnectionStatusCard: View {
    let title: String
    let status: String
    let errorMessage: String?
    let diagnosticSteps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: errorMessage == nil ? "checkmark.seal" : "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(errorMessage == nil ? RokuricsColors.aqua : RokuricsColors.coral)

                Text(title)
                    .font(RokuricsTypography.headline(size: 17))
                    .foregroundStyle(RokuricsColors.deepText)
            }

            Text(status)
                .font(RokuricsTypography.body(size: 14, weight: .semibold))
                .foregroundStyle(RokuricsColors.softText)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            if let errorMessage {
                Text(errorMessage)
                    .font(RokuricsTypography.caption(size: 12, weight: .semibold))
                    .foregroundStyle(RokuricsColors.coral)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)
            }

            if !diagnosticSteps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(diagnosticSteps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Circle()
                                .fill(RokuricsColors.aqua.opacity(0.62))
                                .frame(width: 5, height: 5)

                            Text(step)
                                .font(RokuricsTypography.caption(size: 11, weight: .semibold))
                                .foregroundStyle(RokuricsColors.tertiaryText)
                                .lineLimit(2)
                                .minimumScaleFactor(0.78)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rokuricsLiquidGlassCard(cornerRadius: 24, material: .thinMaterial, fillOpacity: 0.38, strokeOpacity: 0.34, shadowOpacity: 0.07, shadowRadius: 12, shadowY: 6)
    }
}

#Preview {
    NavigationStack {
        MacConnectionView()
    }
}
