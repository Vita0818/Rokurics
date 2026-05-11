//
//  MacIPhoneConnectionView.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import AppKit
import SwiftUI

struct MacIPhoneConnectionView: View {
    @ObservedObject var secureReceiverService: SecureReceiverService
    @Environment(\.colorScheme) private var colorScheme
    @State private var didCopyFingerprint = false

    var body: some View {
        ZStack {
            MacTheme.pageGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        serviceStatusCard
                        pairingCard
                    }

                    fingerprintCard

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        pairedDevicesCard
                        secureUploadCard
                    }
                }
                .padding(.horizontal, 34)
                .padding(.top, 30)
                .padding(.bottom, 34)
                .frame(maxWidth: 1180, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(minimum: 320), spacing: 18, alignment: .top),
            GridItem(.flexible(minimum: 320), spacing: 18, alignment: .top)
        ]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("iPhone 连接")
                .font(MacTypography.chineseTitle(size: 38))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Text("HTTPS 配对与本地安全接收")
                .font(MacTypography.chineseBody(size: 14, weight: .medium))
                .foregroundStyle(MacTheme.softText(for: colorScheme))
        }
    }

    private var serviceStatusCard: some View {
        MacDetailCard(title: "服务状态", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 16) {
                Text(secureReceiverService.httpsStatusText)
                    .font(MacTypography.chineseTitle(size: 30))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    MacStatusPill(text: "Port \(secureReceiverService.port)", systemImage: "number", tint: MacTheme.leaf)
                    MacStatusPill(text: secureReceiverService.localIPAddress == "未知" ? "IP 未知" : secureReceiverService.localIPAddress, systemImage: "wifi", tint: MacTheme.aqua)
                }

                Button {
                    secureReceiverService.isHTTPSRunning
                        ? secureReceiverService.stopSecureReceiving()
                        : secureReceiverService.startSecureReceiving()
                } label: {
                    Label(
                        secureReceiverService.isHTTPSRunning ? "停止安全接收" : "启动安全接收",
                        systemImage: secureReceiverService.isHTTPSRunning ? "stop.fill" : "lock.fill"
                    )
                }
                .buttonStyle(MacDetailPrimaryButtonStyle(isDestructive: secureReceiverService.isHTTPSRunning))
                .disabled(!secureReceiverService.canStartHTTPS)
                .opacity(secureReceiverService.canStartHTTPS ? 1 : 0.52)

                if let lastError = secureReceiverService.lastError {
                    Text(lastError)
                        .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.coral)
                        .lineLimit(2)
                }
            }
        }
    }

    private var fingerprintCard: some View {
        MacDetailCard(title: "Certificate Fingerprint", systemImage: "fingerprint") {
            VStack(alignment: .leading, spacing: 14) {
                Text(fingerprintDisplayText)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .macLiquidGlassCard(
                        cornerRadius: 18,
                        material: .ultraThinMaterial,
                        fillOpacity: 0.30,
                        strokeOpacity: 0.26,
                        shadowOpacity: 0.03,
                        shadowRadius: 8,
                        shadowY: 4
                    )

                HStack(spacing: 10) {
                    Button {
                        copyFingerprint()
                    } label: {
                        Label(didCopyFingerprint ? "已复制" : "复制指纹", systemImage: didCopyFingerprint ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(MacDetailPrimaryButtonStyle())
                    .disabled(!canCopyFingerprint)
                    .opacity(canCopyFingerprint ? 1 : 0.52)

                    Text("复制完整 certificate-sha256")
                        .font(MacTypography.chineseCaption(size: 12, weight: .medium))
                        .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                }
            }
        }
    }

    private var pairingCard: some View {
        MacDetailCard(title: "配对", systemImage: "key.fill") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Text(secureReceiverService.pairingCode)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineLimit(1)

                    Spacer(minLength: 12)

                    MacStatusPill(text: secureReceiverService.pairingStatusText, systemImage: "checkmark.shield", tint: MacTheme.mint)
                }

                Text("有效期至 \(secureReceiverService.pairingExpiresAtText)")
                    .font(MacTypography.chineseBody(size: 13, weight: .medium))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))

                Button {
                    secureReceiverService.beginPairing()
                } label: {
                    Label(secureReceiverService.pairingCode == "未生成" ? "开始配对" : "重新生成配对码", systemImage: "arrow.clockwise")
                }
                .buttonStyle(MacDetailPrimaryButtonStyle())
                .disabled(!secureReceiverService.canPair)
            }
        }
    }

    private var pairedDevicesCard: some View {
        MacDetailCard(title: "已配对设备", systemImage: "iphone.gen3") {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(secureReceiverService.pairedDeviceCount)")
                    .font(MacTypography.number(size: 42))
                    .foregroundStyle(MacTheme.aqua)

                if secureReceiverService.pairedDeviceStore.devices.isEmpty {
                    Text("暂无已配对设备")
                        .font(MacTypography.chineseBody(size: 13, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                } else {
                    VStack(spacing: 10) {
                        ForEach(secureReceiverService.pairedDeviceStore.devices) { device in
                            pairedDeviceRow(device)
                        }
                    }
                }
            }
        }
    }

    private var secureUploadCard: some View {
        MacDetailCard(title: "安全测试上传", systemImage: "lock.doc") {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(secureReceiverService.acceptedUploadCount)")
                    .font(MacTypography.number(size: 42))
                    .foregroundStyle(MacTheme.leaf)

                Text(secureReceiverService.lastAcceptedFileName == "暂无" ? "最近：暂无测试文件" : "最近：\(secureReceiverService.lastAcceptedFileName)")
                    .font(MacTypography.chineseBody(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.softText(for: colorScheme))
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text("测试 JSON 保存：\(ReceivedFileStore.displayPath)")
                    .font(MacTypography.chineseCaption(size: 12, weight: .medium))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                    .lineLimit(2)
            }
        }
    }

    private var fingerprintDisplayText: String {
        guard canCopyFingerprint else {
            return "HTTPS 身份未就绪"
        }

        return secureReceiverService.fingerprint
            .uppercased()
            .chunkedForDisplay(into: 4)
            .joined(separator: " ")
    }

    private var canCopyFingerprint: Bool {
        !secureReceiverService.fingerprint.isEmpty
            && secureReceiverService.fingerprint != "未生成"
    }

    private func pairedDeviceRow(_ device: PairedDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MacTheme.aqua)
                .frame(width: 32, height: 32)
                .macGlassCapsule(fillOpacity: 0.34, strokeOpacity: 0.28)

            VStack(alignment: .leading, spacing: 4) {
                Text(device.deviceName)
                    .font(MacTypography.chineseBody(size: 13, weight: .semibold))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .lineLimit(1)

                Text("ID \(device.idPrefix) · 最近 \(lastSeenText(for: device))")
                    .font(MacTypography.chineseCaption(size: 11, weight: .medium))
                    .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.26, strokeOpacity: 0.24, shadowOpacity: 0.02, shadowRadius: 6, shadowY: 3)
    }

    private func copyFingerprint() {
        guard canCopyFingerprint else {
            return
        }

        let fullFingerprint = secureReceiverService.fingerprint.uppercased()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullFingerprint, forType: .string)
        didCopyFingerprint = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            didCopyFingerprint = false
        }
    }

    private func lastSeenText(for device: PairedDevice) -> String {
        guard let lastSeenAt = device.lastSeenAt else {
            return "未连接"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: lastSeenAt)
    }
}

private struct MacDetailCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(MacTheme.accentGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text(title)
                    .font(MacTypography.chineseHeadline(size: 17))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .lineLimit(1)
            }

            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .macLiquidGlassCard(cornerRadius: 26, material: .thinMaterial, fillOpacity: 0.46, strokeOpacity: 0.44, shadowOpacity: 0.10, shadowRadius: 17, shadowY: 9)
    }
}

private struct MacDetailPrimaryButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(isDestructive ? MacTheme.coral : .white)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                Capsule(style: .continuous)
                    .fill(isDestructive ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(MacTheme.accentGradient))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isDestructive ? MacTheme.coral.opacity(0.42) : Color.white.opacity(0.42), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private extension String {
    func chunkedForDisplay(into size: Int) -> [String] {
        guard size > 0 else {
            return [self]
        }

        var chunks: [String] = []
        var currentIndex = startIndex

        while currentIndex < endIndex {
            let nextIndex = index(currentIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[currentIndex..<nextIndex]))
            currentIndex = nextIndex
        }

        return chunks
    }
}

#Preview {
    MacIPhoneConnectionView(secureReceiverService: SecureReceiverService())
}
