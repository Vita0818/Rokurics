//
//  MacReceiverStatusCard.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import AppKit
import SwiftUI

struct MacReceiverStatusCard: View {
    @ObservedObject var secureReceiverService: SecureReceiverService
    let onOpenDetails: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var didCopyPairingInfo = false

    var body: some View {
        MacDashboardCard(systemImage: "iphone.gen3", tint: MacTheme.aqua) {
            MacMixedLanguageTitle(english: "iPhone", chinese: "连接", englishSize: 17, chineseSize: 17)
        } content: {
            if let device = secureReceiverService.latestPairedDevice {
                pairedSummary(device)
            } else {
                unpairedActions
            }
        }
    }

    private func pairedSummary(_ device: PairedDevice) -> some View {
        let status = effectiveDisplayConnectionStatus(for: device)
        return MacConnectedDeviceCardView(
            deviceName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            connectionInfo: "\(ipSummary) · \(device.idPrefix)",
            status: status,
            isCompact: true,
            showsDisconnectAction: true,
            usesCardChrome: false,
            onShowDetail: onOpenDetails,
            onDisconnect: {
                secureReceiverService.disconnectPairedDevices()
            }
        )
    }

    private func effectiveDisplayConnectionStatus(for device: PairedDevice) -> DeviceConnectionStatus {
        var status = secureReceiverService.connectionStatus(for: device)
        let statusStore = secureReceiverService.studyLibraryStore
        let displayStates = statusStore.effectiveSyncStatusByObjectID.keys.compactMap {
            statusStore.canonicalDisplaySyncState(for: $0)
        }
        if let effectiveLastSyncStatus = Self.effectiveLastSyncStatus(from: displayStates) {
            status.lastSyncStatus = effectiveLastSyncStatus
        }
        return status
    }

    static func effectiveLastSyncStatus(from displayStates: [CanonicalDisplaySyncState]) -> String? {
        guard !displayStates.isEmpty else {
            return nil
        }

        if displayStates.contains(where: { $0.kind == .conflict || $0.kind == .blocked || $0.kind == .failed }) {
            return RokuricsCopy.text("暂无", "None")
        }

        let completeStates = displayStates.filter { $0.canDisplayAsComplete }
        if !completeStates.isEmpty,
           completeStates.count == displayStates.count {
            return RokuricsCopy.text("已同步", "Synced")
        }

        if displayStates.contains(where: { $0.kind == .uploadNeeded || $0.kind == .uploading || $0.kind == .finalizing || $0.kind == .stale }) {
            return RokuricsCopy.text("正在同步", "Syncing")
        }

        return RokuricsCopy.text("暂无", "None")
    }

    private var unpairedActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(RokuricsCopy.text("未配对", "Not Paired"))
                .font(RokuricsCopy.usesChinese ? MacTypography.chineseTitle(size: 30) : MacTypography.englishTitle(size: 30))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)

            Spacer(minLength: 0)

            if hasActivePairingCode {
                Button {
                    copyPairingInfo()
                } label: {
                    Label(didCopyPairingInfo ? RokuricsCopy.text("已复制", "Copied") : RokuricsCopy.text("复制配对信息", "Copy Pairing"), systemImage: didCopyPairingInfo ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MacDashboardConnectionButtonStyle(isPrimary: true))
                .disabled(!canCopyPairingInfo)
                .opacity(canCopyPairingInfo ? 1 : 0.55)
            } else {
                Button {
                    startPairingFlow()
                } label: {
                    Label(RokuricsCopy.text("开始配对", "Start Pairing"), systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MacDashboardConnectionButtonStyle(isPrimary: true))
                .disabled(!secureReceiverService.canPair)
                .opacity(secureReceiverService.canPair ? 1 : 0.55)
            }

            Button {
                onOpenDetails()
            } label: {
                Label(RokuricsCopy.text("查看详情", "Details"), systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MacDashboardConnectionButtonStyle(isPrimary: false))
        }
    }

    private var hasActivePairingCode: Bool {
        secureReceiverService.pairingCode.count == 6
            && secureReceiverService.pairingCode.allSatisfy { $0.isNumber }
    }

    private var canCopyPairingInfo: Bool {
        hasActivePairingCode
            && isFingerprintReady
            && secureReceiverService.localIPAddress != "未知"
            && secureReceiverService.port > 0
    }

    private var isFingerprintReady: Bool {
        !secureReceiverService.fingerprint.isEmpty
            && secureReceiverService.fingerprint != "未生成"
    }

    private func startPairingFlow() {
        if !secureReceiverService.isHTTPSRunning, secureReceiverService.canStartHTTPS {
            secureReceiverService.startSecureReceiving()
        }

        secureReceiverService.beginPairing()
    }

    private func copyPairingInfo() {
        guard canCopyPairingInfo else {
            return
        }

        let pairingInfo = """
        Rokurics Pairing
        Host: \(secureReceiverService.localIPAddress)
        Port: \(secureReceiverService.port)
        Code: \(secureReceiverService.pairingCode)
        Fingerprint: \(secureReceiverService.fingerprint.uppercased())
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingInfo, forType: .string)
        didCopyPairingInfo = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            didCopyPairingInfo = false
        }
    }

    private var ipSummary: String {
        secureReceiverService.localIPAddress == "未知" ? RokuricsCopy.text("IP 未知", "IP Unknown") : secureReceiverService.localIPAddress
    }
}

private struct MacDashboardConnectionButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(isPrimary ? .white : MacTheme.aqua)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isPrimary ? AnyShapeStyle(MacTheme.accentGradient) : AnyShapeStyle(.thinMaterial))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isPrimary ? Color.white.opacity(0.40) : MacTheme.aqua.opacity(colorScheme == .dark ? 0.30 : 0.36), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MacReceiverControlButtonStyle: ButtonStyle {
    let isRunning: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(isRunning ? MacTheme.coral : .white)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background {
                Capsule(style: .continuous)
                    .fill(isRunning ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(MacTheme.accentGradient))
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(isRunning ? MacTheme.coral.opacity(0.42) : Color.white.opacity(0.42), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MacPairingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(MacTheme.aqua)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(.thinMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(MacTheme.aqua.opacity(0.36), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}
