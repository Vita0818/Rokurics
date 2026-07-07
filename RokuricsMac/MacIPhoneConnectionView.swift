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
    var isSidebarCollapsed = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var isFingerprintVisible = false
    @State private var didCopyPairingInfo = false
    @State private var activeSheet: MacIPhoneConnectionSheet?
    @State private var didRecordConnectionPageLoaded = false
    @State private var manualSyncStatusRevision: Int?

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            MacDetailContentContainer(maxWidth: 1120) {
                VStack(alignment: .leading, spacing: 26) {
                    if let device = secureReceiverService.latestPairedDevice {
                        connectedHeader
                        connectedContent(for: device)
                    } else {
                        unpairedSection
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .connectionDetail:
                MacIPhoneConnectionDetailSheet(
                    secureReceiverService: secureReceiverService,
                    device: secureReceiverService.latestPairedDevice
                )
            case .pairedDevices:
                MacPairedDevicesSheet(secureReceiverService: secureReceiverService)
            case .secureUploads:
                MacSecureUploadTestSheet(secureReceiverService: secureReceiverService)
            }
        }
        .onAppear {
            secureReceiverService.recordWindowOpened()
            recordConnectionPageLoadedIfNeeded()
        }
        .onDisappear {
            secureReceiverService.recordWindowClosed()
        }
        .onChange(of: secureReceiverService.pairingPayload) { _, _ in
            recordConnectionPageState()
        }
    }

    private var unpairedHeader: some View {
        connectionTitle(isPaired: false)
    }

    private var connectedHeader: some View {
        connectionTitle(isPaired: true)
    }

    private var unpairedSection: some View {
        VStack(alignment: .leading, spacing: 26) {
            unpairedHeader
            unpairedContent
        }
        .frame(maxWidth: MacIPhoneConnectionCardLayout.cardMaxWidth(isSidebarCollapsed: isSidebarCollapsed), alignment: .leading)
        .frame(maxWidth: .infinity, alignment: MacIPhoneConnectionCardLayout.isCentered(isSidebarCollapsed: isSidebarCollapsed) ? .center : .leading)
        .transaction { transaction in
            if MacIPhoneConnectionCardLayout.disablesWidthAnimation {
                transaction.animation = nil
            }
        }
    }

    private func connectionTitle(isPaired: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            MacMixedFontText(
                text: RokuricsCopy.text("iPhone 连接", "iPhone Link"),
                chineseFont: MacTypography.font(for: .pageTitle),
                englishFont: MacTypography.englishTitle(size: 32, weight: .semibold),
                numberFont: MacTypography.numberTitle(size: 32, weight: .bold)
            )
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Spacer(minLength: 12)

            if !isPaired {
                MacConnectionStateCapsule(text: RokuricsCopy.text("未配对", "Not Paired"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unpairedContent: some View {
        pairingInformationCard
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pairingInformationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                MacPairingInfoFieldRow(
                    title: RokuricsCopy.text("Mac 地址", "Mac Address"),
                    value: secureReceiverService.localIPAddress,
                    valueFont: MacTypography.technical(size: 16, weight: .semibold)
                )

                MacPairingInfoFieldRow(
                    title: RokuricsCopy.text("端口", "Port"),
                    value: "\(secureReceiverService.port)",
                    valueFont: MacTypography.technical(size: 16, weight: .semibold),
                    minWidth: 132
                )
            }

            MacPairingFingerprintFieldRow(
                fingerprint: secureReceiverService.fingerprint,
                isVisible: $isFingerprintVisible
            )

            pairingCodeRow

            Button {
                copyPairingInfo()
            } label: {
                Label(didCopyPairingInfo ? RokuricsCopy.text("已复制", "Copied") : RokuricsCopy.text("复制配对信息", "Copy Pairing"), systemImage: didCopyPairingInfo ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MacConnectionPrimaryButtonStyle())
            .accessibilityIdentifier("mac-iphone-copy-pairing-info-button")
            .disabled(!canCopyPairingInfo)
            .opacity(canCopyPairingInfo ? 1 : 0.52)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 24, material: .thinMaterial, fillOpacity: 0.44, strokeOpacity: 0.40, shadowOpacity: 0.08, shadowRadius: 16, shadowY: 8)
    }

    private var pairingCodeRow: some View {
        Group {
            if let payload = activePairingPayload {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(RokuricsCopy.text("配对码", "Pairing Code"))
                            .font(RokuricsCopy.usesChinese ? MacTypography.chineseCaption(size: 12, weight: .semibold) : MacTypography.englishCaption(size: 12, weight: .semibold))
                            .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))

                        Text(payload.pairingCode)
                            .font(MacTypography.technical(size: 30, weight: .bold))
                            .foregroundStyle(MacTheme.deepText(for: colorScheme))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("mac-iphone-pairing-code")
                            .accessibilityLabel(payload.pairingCode)
                    }

                    Spacer(minLength: 16)

                    Text(payload.expiresAtText)
                        .font(MacTypography.chineseCaption(size: 13, weight: .semibold))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.28, strokeOpacity: 0.26, shadowOpacity: 0.02, shadowRadius: 6, shadowY: 3)
            } else {
                Button {
                    startPairingFlow()
                } label: {
                    Label(startConnectionButtonTitle, systemImage: "key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MacConnectionPrimaryButtonStyle())
                .accessibilityIdentifier("mac-iphone-start-pairing-button")
                .disabled(!isBeginPairingButtonEnabled)
            }
        }
    }

    private func connectedContent(for device: PairedDevice) -> some View {
        let status = secureReceiverService.connectionStatus(for: device)
        let syncState = secureReceiverService.syncStateStore.state
        _ = manualSyncStatusRevision
        return MacConnectedDeviceLayout(
            device: device,
            status: status,
            syncState: syncState,
            connectionAddress: connectionAddress,
            deviceID: device.idPrefix,
            onShowDetail: {
                activeSheet = .connectionDetail
            },
            onSyncNow: {
                let status = secureReceiverService.prepareManualStudyLibrarySync(for: device)
                manualSyncStatusRevision = status.connectionStatusRevision
            },
            onDisconnect: {
                secureReceiverService.disconnectPairedDevices()
            }
        )
    }

    private var activePairingPayload: SecureReceiverPairingPayload? {
        secureReceiverService.pairingPayload
    }

    private var canCopyPairingInfo: Bool {
        secureReceiverService.canCopyPairingInfo
    }

    private var isBeginPairingButtonEnabled: Bool {
        secureReceiverService.canBeginPairingFromUI
    }

    private var startConnectionButtonTitle: String {
        RokuricsCopy.text("开始配对", "Start Pairing")
    }

    private var isFingerprintReady: Bool {
        !secureReceiverService.fingerprint.isEmpty
            && secureReceiverService.fingerprint != "未生成"
    }

    private func startPairingFlow() {
        secureReceiverService.recordBeginPairingButtonTapped(
            beginPairingButtonEnabled: isBeginPairingButtonEnabled,
            copyEnabled: canCopyPairingInfo
        )
        if !secureReceiverService.isHTTPSRunning, secureReceiverService.canStartHTTPS {
            secureReceiverService.startSecureReceiving()
        }

        secureReceiverService.beginPairing()
    }

    private func copyPairingInfo() {
        guard let payload = activePairingPayload else {
            return
        }

        let pairingInfo = """
        Rokurics Pairing
        Host: \(payload.host)
        Port: \(payload.port)
        Code: \(payload.pairingCode)
        Fingerprint: \(payload.fingerprint.uppercased())
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pairingInfo, forType: .string)
        didCopyPairingInfo = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            didCopyPairingInfo = false
        }
    }

    private var connectionAddress: String {
        secureReceiverService.localIPAddress == "未知" ? RokuricsCopy.text("IP 未知", "IP Unknown") : secureReceiverService.localIPAddress
    }

    private func recordConnectionPageLoadedIfNeeded() {
        guard !didRecordConnectionPageLoaded else {
            recordConnectionPageState()
            return
        }

        didRecordConnectionPageLoaded = true
        recordConnectionPageState()
    }

    private func recordConnectionPageState() {
        secureReceiverService.recordConnectionPageLoaded(
            beginPairingButtonEnabled: isBeginPairingButtonEnabled,
            copyEnabled: canCopyPairingInfo
        )
    }
}

private enum MacIPhoneConnectionSheet: String, Identifiable {
    case connectionDetail
    case pairedDevices
    case secureUploads

    var id: String { rawValue }
}

struct MacIPhoneConnectionCardLayout {
    static let stableMaxWidth: CGFloat = 760
    static let disablesWidthAnimation = true

    static func cardMaxWidth(isSidebarCollapsed: Bool) -> CGFloat {
        stableMaxWidth
    }

    static func isCentered(isSidebarCollapsed: Bool) -> Bool {
        true
    }
}

private struct MacConnectionStateCapsule: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(MacTypography.chineseCaption(size: 12, weight: .bold))
            .foregroundStyle(MacTheme.aqua)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .macGlassCapsule(fillOpacity: 0.36, strokeOpacity: 0.34)
    }
}

private struct MacPairingInfoFieldRow: View {
    let title: String
    let value: String
    let valueFont: Font
    var minWidth: CGFloat?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))

            Text(value)
                .font(valueFont)
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minWidth: minWidth, maxWidth: minWidth == nil ? .infinity : minWidth, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.28, strokeOpacity: 0.26, shadowOpacity: 0.02, shadowRadius: 6, shadowY: 3)
    }
}

private struct MacPairingFingerprintFieldRow: View {
    let fingerprint: String
    @Binding var isVisible: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: isVisible ? .top : .firstTextBaseline, spacing: 14) {
            Text(RokuricsCopy.text("Mac 指纹", "Mac Fingerprint"))
                .font(RokuricsCopy.usesChinese ? MacTypography.chineseCaption(size: 12, weight: .semibold) : MacTypography.englishCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                .frame(width: 58, alignment: .leading)
                .padding(.top, isVisible ? 3 : 0)

            Text(isVisible ? visibleFingerprint : hiddenFingerprint)
                .font(MacTypography.fingerprint(size: isVisible ? 14 : 15, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineSpacing(5)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(isVisible ? RokuricsCopy.text("隐藏", "Hide") : RokuricsCopy.text("显示", "Show")) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isVisible.toggle()
                }
            }
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(MacTheme.aqua)
            .buttonStyle(.plain)
            .disabled(!isFingerprintReady)
            .opacity(isFingerprintReady ? 1 : 0.45)
            .padding(.top, isVisible ? 3 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isVisible ? 15 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(
            cornerRadius: 18,
            material: .ultraThinMaterial,
            fillOpacity: 0.28,
            strokeOpacity: 0.26,
            shadowOpacity: 0.02,
            shadowRadius: 6,
            shadowY: 3
        )
    }

    private var isFingerprintReady: Bool {
        !fingerprint.isEmpty && fingerprint != "未生成"
    }

    private var hiddenFingerprint: String {
        isFingerprintReady ? "•••• •••• •••• ••••" : RokuricsCopy.text("HTTPS 身份未就绪", "HTTPS identity not ready")
    }

    private var visibleFingerprint: String {
        fingerprint
            .uppercased()
            .macGroupedFingerprint(groupsPerLine: 8)
    }
}

private struct MacConnectedDeviceBubbleView: View {
    let deviceName: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBreathing = false

    var body: some View {
        ZStack {
            decorativeBubble(size: 98, fill: AnyShapeStyle(MacTheme.pageGradient), opacity: 0.56)
                .offset(x: -86, y: -62)
                .scaleEffect(isBreathing ? 1.05 : 0.97)

            decorativeBubble(size: 82, fill: AnyShapeStyle(MacTheme.accentGradient), opacity: 0.34)
                .offset(x: 90, y: -42)
                .scaleEffect(isBreathing ? 0.98 : 1.05)

            decorativeBubble(size: 76, fill: AnyShapeStyle(MacTheme.pageGradient), opacity: 0.38)
                .offset(x: 72, y: 84)
                .scaleEffect(isBreathing ? 1.04 : 0.98)

            Circle()
                .fill(MacTheme.accentGradient)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.32 : 0.38),
                                    Color.white.opacity(colorScheme == .dark ? 0.11 : 0.14),
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
                                    Color.white.opacity(colorScheme == .dark ? 0.42 : 0.56),
                                    Color.white.opacity(0.12),
                                    MacTheme.aqua.opacity(colorScheme == .dark ? 0.34 : 0.25)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.4
                        )
                }
                .frame(width: 196, height: 196)
                .shadow(color: MacTheme.shadow(for: colorScheme).opacity(colorScheme == .dark ? 0.30 : 0.22), radius: 30, x: 0, y: 18)
                .scaleEffect(isBreathing ? 1.018 : 0.992)

            Image(systemName: iconName)
                .font(.system(size: 68, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .shadow(color: MacTheme.deepText(for: colorScheme).opacity(0.14), radius: 8, y: 4)
        }
        .frame(width: 286, height: 286)
        .onAppear {
            withAnimation(.easeInOut(duration: 4.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private var iconName: String {
        deviceName.lowercased().contains("ipad") ? "ipad" : "iphone.gen3"
    }

    private func decorativeBubble(size: CGFloat, fill: AnyShapeStyle, opacity: Double) -> some View {
        Circle()
            .fill(fill)
            .opacity(colorScheme == .dark ? opacity * 0.78 : opacity)
            .background(.ultraThinMaterial, in: Circle())
            .frame(width: size, height: size)
    }
}

private struct MacConnectedDeviceLayout: View {
    let device: PairedDevice
    let status: DeviceConnectionStatus
    let syncState: StudyLibrarySyncState
    let connectionAddress: String
    let deviceID: String
    let onShowDetail: () -> Void
    let onSyncNow: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 680
            let bubbleSize: CGFloat = 286
            let spacing: CGFloat = isCompact ? 24 : 34
            let cardWidth = isCompact ? min(410, proxy.size.width) : min(430, max(360, proxy.size.width - bubbleSize - spacing))

            Group {
                if isCompact {
                    VStack(spacing: spacing) {
                        MacConnectedDeviceBubbleView(deviceName: device.deviceName)
                            .frame(width: bubbleSize, height: bubbleSize)

                        MacConnectedDeviceCardView(
                            device: device,
                            status: status,
                            syncState: syncState,
                            connectionAddress: connectionAddress,
                            deviceID: deviceID,
                            isCompact: isCompact,
                            onShowDetail: onShowDetail,
                            onSyncNow: onSyncNow,
                            onDisconnect: onDisconnect
                        )
                        .frame(width: cardWidth)
                    }
                } else {
                    HStack(alignment: .center, spacing: spacing) {
                        MacConnectedDeviceBubbleView(deviceName: device.deviceName)
                            .frame(width: bubbleSize, height: bubbleSize)

                        MacConnectedDeviceCardView(
                            device: device,
                            status: status,
                            syncState: syncState,
                            connectionAddress: connectionAddress,
                            deviceID: deviceID,
                            isCompact: isCompact,
                            onShowDetail: onShowDetail,
                            onSyncNow: onSyncNow,
                            onDisconnect: onDisconnect
                        )
                        .frame(width: cardWidth)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .padding(.top, 18)
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .center)
    }
}

struct MacConnectedDeviceCardView: View {
    let deviceName: String
    let connectionInfo: String
    let status: DeviceConnectionStatus
    let syncState: StudyLibrarySyncState
    var isCompact: Bool
    var showsDisconnectAction = true
    var usesCardChrome = true
    let onShowDetail: () -> Void
    let onSyncNow: (() -> Void)?
    let onDisconnect: (() -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @State private var presenceNow = Date()

    init(
        device: PairedDevice,
        status: DeviceConnectionStatus,
        syncState: StudyLibrarySyncState,
        connectionAddress: String,
        deviceID: String,
        isCompact: Bool,
        showsDisconnectAction: Bool = true,
        usesCardChrome: Bool = true,
        onShowDetail: @escaping () -> Void,
        onSyncNow: (() -> Void)? = nil,
        onDisconnect: (() -> Void)? = nil
    ) {
        self.deviceName = device.deviceName.isEmpty ? "iPhone" : device.deviceName
        self.connectionInfo = "\(connectionAddress) · \(deviceID)"
        self.status = status
        self.syncState = syncState
        self.isCompact = isCompact
        self.showsDisconnectAction = showsDisconnectAction
        self.usesCardChrome = usesCardChrome
        self.onShowDetail = onShowDetail
        self.onSyncNow = onSyncNow
        self.onDisconnect = onDisconnect
    }

    init(
        deviceName: String,
        connectionInfo: String,
        status: DeviceConnectionStatus = .unpaired(displayName: "iPhone"),
        syncState: StudyLibrarySyncState = StudyLibrarySyncState(),
        isCompact: Bool,
        showsDisconnectAction: Bool = true,
        usesCardChrome: Bool = true,
        onShowDetail: @escaping () -> Void,
        onSyncNow: (() -> Void)? = nil,
        onDisconnect: (() -> Void)? = nil
    ) {
        self.deviceName = deviceName.isEmpty ? "iPhone" : deviceName
        self.connectionInfo = connectionInfo
        self.status = status
        self.syncState = syncState
        self.isCompact = isCompact
        self.showsDisconnectAction = showsDisconnectAction
        self.usesCardChrome = usesCardChrome
        self.onShowDetail = onShowDetail
        self.onSyncNow = onSyncNow
        self.onDisconnect = onDisconnect
    }

    var body: some View {
        if usesCardChrome {
            cardContent
                .padding(isCompact ? 20 : 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .macLiquidGlassCard(cornerRadius: 24, material: .thinMaterial, fillOpacity: 0.44, strokeOpacity: 0.40, shadowOpacity: 0.08, shadowRadius: 16, shadowY: 8)
        } else {
            cardContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: isCompact ? 13 : 16) {
            Text(deviceName)
                .font(deviceName.macContainsCJK ? MacTypography.chineseTitle(size: 25, weight: .bold) : MacTypography.englishTitle(size: 27, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            connectionInfoView

            VStack(spacing: 8) {
                MacConnectedStatusRow(title: RokuricsCopy.text("状态", "Status"), value: stateText, tint: stateTint)
                MacConnectedStatusRow(title: RokuricsCopy.text("同步内核", "Sync Kernel"), value: kernelSwitchSourceText, tint: MacTheme.softText(for: colorScheme))
                MacConnectedStatusRow(title: RokuricsCopy.text("最近在线", "Last Online"), value: presence.recentOnlineText, tint: MacTheme.softText(for: colorScheme))
                MacConnectedStatusRow(title: RokuricsCopy.text("最近同步", "Last Sync"), value: lastSyncText, tint: MacTheme.softText(for: colorScheme))
            }
            .padding(12)
            .macLiquidGlassCard(cornerRadius: 16, material: .ultraThinMaterial, fillOpacity: 0.24, strokeOpacity: 0.22, shadowOpacity: 0.02, shadowRadius: 5, shadowY: 2)

            VStack(spacing: 10) {
                if let onSyncNow {
                    Button(action: onSyncNow) {
                        MacLocalNetworkSyncButtonLabel(presentation: syncButtonPresentation)
                    }
                    .buttonStyle(MacConnectionPrimaryButtonStyle(verticalPadding: isCompact ? 8 : 10))
                    .disabled(syncButtonPresentation.isActive)
                }

                Button(action: onShowDetail) {
                    Text(RokuricsCopy.text("查看连接信息", "Connection Info"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MacConnectionPrimaryButtonStyle(verticalPadding: isCompact ? 8 : 10))

                if showsDisconnectAction, let onDisconnect {
                    Button(action: onDisconnect) {
                        Text(RokuricsCopy.text("断开连接", "Disconnect"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MacConnectionDestructiveButtonStyle(verticalPadding: isCompact ? 8 : 10))
                }
            }
            .padding(.top, 4)
        }
        .task {
            while !Task.isCancelled {
                presenceNow = Date()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var syncButtonPresentation: MacLocalNetworkSyncButtonPresentation {
        guard syncState.deviceID.isEmpty || syncState.deviceID == status.deviceID else {
            return .idle
        }

        if let state = syncState.syncControlPlaneState,
           state.isSyncProgressActive || shouldShowRecentTerminalSyncState(state) {
            return MacLocalNetworkSyncButtonPresentation(state: state)
        }

        return .idle
    }

    private func shouldShowRecentTerminalSyncState(_ state: LocalNetworkSyncControlPlaneState) -> Bool {
        switch state {
        case .completed, .failed, .cancelled:
            return isRecentTerminalSyncState
        case .idle, .syncStartSignalSent, .syncStartSignalReceived, .syncStartAcked,
             .inventoryExchanging, .planningTransfers, .transferJobsCreated,
             .transferring, .pausedDisconnected, .resuming:
            return false
        }
    }

    private var isRecentTerminalSyncState: Bool {
        guard let updatedAt = syncState.syncControlPlaneUpdatedAt else {
            return false
        }
        return presenceNow.timeIntervalSince(updatedAt) <= 12
    }

    private var connectionInfoView: some View {
        Text(connectionInfo)
            .font(MacTypography.technical(size: 13, weight: .semibold))
            .foregroundStyle(MacTheme.softText(for: colorScheme))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
    }

    private var stateText: String {
        presence.statusText
    }

    private var stateTint: Color {
        switch presence.state {
        case .online:
            return MacTheme.aqua
        case .connecting:
            return MacTheme.mint
        case .interrupted, .stale, .disconnected, .securityError, .unknown:
            return MacTheme.coral
        }
    }

    private var kernelSwitchSourceText: String {
        CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults()
            .resolve()
            .effectiveStatusSourceText
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
        return status.lastSyncStatus ?? RokuricsCopy.text("暂无", "None")
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = RokuricsCopy.displayLocale
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct MacLocalNetworkSyncButtonPresentation: Equatable {
    var title: String
    var progressFraction: Double?
    var isActive: Bool

    static let idle = MacLocalNetworkSyncButtonPresentation(
        title: RokuricsCopy.text("立即同步", "Sync Now"),
        progressFraction: nil,
        isActive: false
    )

    init(state: LocalNetworkSyncControlPlaneState) {
        let fraction = state.syncButtonProgressFraction
        if let fraction, state.isSyncProgressActive {
            let percent = min(max(Int((fraction * 100).rounded()), 0), 100)
            title = "\(state.syncButtonStatusText) \(percent)%"
        } else {
            title = state.syncButtonStatusText
        }
        progressFraction = fraction
        isActive = state.isSyncProgressActive
    }

    private init(title: String, progressFraction: Double?, isActive: Bool) {
        self.title = title
        self.progressFraction = progressFraction
        self.isActive = isActive
    }
}

private struct MacLocalNetworkSyncButtonLabel: View {
    let presentation: MacLocalNetworkSyncButtonPresentation

    var body: some View {
        if presentation.isActive {
            VStack(spacing: 5) {
                Text(presentation.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                ProgressView(value: presentation.progressFraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 118)
            }
            .frame(maxWidth: .infinity)
        } else {
            Text(presentation.title)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct MacConnectedStatusRow: View {
    let title: String
    let value: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(MacTypography.chineseCaption(size: 11, weight: .semibold))
                .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                .frame(width: 58, alignment: .leading)

            Text(value)
                .font(value.macContainsCJK ? MacTypography.chineseCaption(size: 12, weight: .semibold) : MacTypography.numberBody(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(2)
                .truncationMode(.middle)

            Spacer(minLength: 0)
        }
    }
}

private struct MacIPhoneConnectionDetailSheet: View {
    @ObservedObject var secureReceiverService: SecureReceiverService
    let device: PairedDevice?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                MacSheetHeader(title: RokuricsCopy.text("连接状态", "Connection Status"), systemImage: "lock.shield", onClose: { dismiss() })

                VStack(spacing: 0) {
                    detailRow(RokuricsCopy.text("iPhone 名称", "iPhone Name"), device?.deviceName ?? "iPhone", style: .name)
                    MacConnectionDivider()
                    detailRow("deviceID", device?.idPrefix ?? RokuricsCopy.text("未知", "Unknown"), style: .technical)
                    MacConnectionDivider()
                    detailRow("IP", secureReceiverService.localIPAddress, style: .technical)
                    MacConnectionDivider()
                    detailRow(RokuricsCopy.text("连接状态", "Connection Status"), connectionStateText, style: .name)
                    MacConnectionDivider()
                    detailRow(RokuricsCopy.text("配对时间", "Paired At"), device.map { formattedDate($0.pairedAt) } ?? RokuricsCopy.text("未知", "Unknown"), style: .number)
                    MacConnectionDivider()
                    detailRow(RokuricsCopy.text("最近连接", "Last Online"), status.presenceSnapshot().recentOnlineText, style: .number)
                    MacConnectionDivider()
                    detailRow(RokuricsCopy.text("最近同步", "Last Sync"), lastSyncText, style: .name)
                    MacConnectionDivider()
                    detailRow(RokuricsCopy.text("安全上传测试", "Secure Upload Tests"), "\(secureReceiverService.acceptedUploadCount)", style: .number)
                    MacConnectionDivider()
                    detailRow(RokuricsCopy.text("最近测试文件", "Last Test File"), secureReceiverService.lastAcceptedFileName == "暂无" ? RokuricsCopy.text("暂无", "None") : secureReceiverService.lastAcceptedFileName, style: .name)
                }
                .padding(6)
                .macLiquidGlassCard(cornerRadius: 24, material: .thinMaterial, fillOpacity: 0.44, strokeOpacity: 0.38, shadowOpacity: 0.07, shadowRadius: 14, shadowY: 7)

                VStack(alignment: .leading, spacing: 10) {
                    Text("certificate fingerprint")
                        .font(MacTypography.englishCaption(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))

                    Text(fingerprintText)
                        .font(MacTypography.fingerprint(size: 14, weight: .semibold))
                        .foregroundStyle(MacTheme.deepText(for: colorScheme))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.28, strokeOpacity: 0.26, shadowOpacity: 0.02, shadowRadius: 6, shadowY: 3)
                }
            }
            .padding(28)
        }
        .frame(width: 620)
        .frame(minHeight: 560)
    }

    private var fingerprintText: String {
        secureReceiverService.fingerprint == "未生成"
            ? RokuricsCopy.text("HTTPS 身份未就绪", "HTTPS identity not ready")
            : secureReceiverService.fingerprint.uppercased().macGroupedFingerprint(groupsPerLine: 8)
    }

    private var status: DeviceConnectionStatus {
        secureReceiverService.connectionStatus(for: device)
    }

    private var connectionStateText: String {
        status.presenceSnapshot().statusText
    }

    private var lastSyncText: String {
        if let lastSyncAt = status.lastSyncAt {
            return formattedDate(lastSyncAt)
        }
        return status.lastSyncStatus ?? RokuricsCopy.text("暂无", "None")
    }

    private func detailRow(_ label: String, _ value: String, style: MacConnectionDetailValueStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(label)
                .font(label.macContainsCJK ? MacTypography.chineseCaption(size: 12, weight: .semibold) : MacTypography.englishCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                .frame(width: 108, alignment: .leading)

            Text(value)
                .font(style.font(for: value))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct MacPairedDevicesSheet: View {
    @ObservedObject var secureReceiverService: SecureReceiverService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                MacSheetHeader(title: RokuricsCopy.text("已配对设备", "Paired Devices"), systemImage: "iphone.gen3", onClose: { dismiss() })

                Text("\(secureReceiverService.pairedDeviceCount)")
                    .font(MacTypography.numberLarge(size: 42, weight: .bold))
                    .foregroundStyle(MacTheme.aqua)

                if secureReceiverService.pairedDeviceStore.devices.isEmpty {
                    Text(RokuricsCopy.text("暂无已配对设备", "No paired devices"))
                        .font(RokuricsCopy.usesChinese ? MacTypography.chineseBody(size: 14, weight: .medium) : MacTypography.englishBody(size: 14, weight: .medium))
                        .foregroundStyle(MacTheme.softText(for: colorScheme))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .macLiquidGlassCard(cornerRadius: 20, material: .ultraThinMaterial, fillOpacity: 0.28, strokeOpacity: 0.26, shadowOpacity: 0.02, shadowRadius: 6, shadowY: 3)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(secureReceiverService.pairedDeviceStore.devices) { device in
                                MacPairedDeviceListRow(device: device)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: 360)
                }
            }
            .padding(28)
        }
        .frame(width: 600)
    }
}

private struct MacPairedDeviceListRow: View {
    let device: PairedDevice
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.deviceName.lowercased().contains("ipad") ? "ipad" : "iphone.gen3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(MacTheme.aqua)
                .frame(width: 38, height: 38)
                .macGlassCapsule(fillOpacity: 0.30, strokeOpacity: 0.26)

            VStack(alignment: .leading, spacing: 6) {
                Text(device.deviceName.isEmpty ? "iPhone" : device.deviceName)
                    .font(device.deviceName.macContainsCJK ? MacTypography.chineseBody(size: 14, weight: .semibold) : MacTypography.englishBody(size: 14, weight: .semibold))
                    .foregroundStyle(MacTheme.deepText(for: colorScheme))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(device.idPrefix)
                        .font(MacTypography.technical(size: 11, weight: .medium))
                    Text("·")
                        .font(MacTypography.numberBody(size: 11, weight: .medium))
                    Text(formattedDate(device.pairedAt))
                        .font(MacTypography.numberBody(size: 11, weight: .medium))
                    Text("·")
                        .font(MacTypography.numberBody(size: 11, weight: .medium))
                    Text(lastSeenText)
                        .font(lastSeenText.macContainsCJK ? MacTypography.chineseCaption(size: 11, weight: .medium) : MacTypography.numberBody(size: 11, weight: .medium))
                }
                .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macLiquidGlassCard(cornerRadius: 18, material: .ultraThinMaterial, fillOpacity: 0.28, strokeOpacity: 0.26, shadowOpacity: 0.02, shadowRadius: 6, shadowY: 3)
    }

    private var lastSeenText: String {
        device.lastSeenAt.map(formattedDate) ?? RokuricsCopy.text("暂无", "None")
    }
}

private struct MacSecureUploadTestSheet: View {
    @ObservedObject var secureReceiverService: SecureReceiverService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            MacTheme.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                MacSheetHeader(title: RokuricsCopy.text("上传测试", "Upload Test"), systemImage: "lock.doc", onClose: { dismiss() })

                VStack(spacing: 0) {
                    uploadRow(RokuricsCopy.text("安全测试上传数量", "Secure Upload Count"), "\(secureReceiverService.acceptedUploadCount)", style: .number)
                    MacConnectionDivider()
                    uploadRow(RokuricsCopy.text("最近测试 JSON", "Last Test JSON"), secureReceiverService.lastAcceptedFileName == "暂无" ? RokuricsCopy.text("暂无", "None") : secureReceiverService.lastAcceptedFileName, style: .name)
                    MacConnectionDivider()
                    uploadRow(RokuricsCopy.text("保存位置", "Save Location"), ReceivedFileStore.displayPath, style: .name)
                    MacConnectionDivider()
                    uploadRow(RokuricsCopy.text("上传测试状态", "Upload Test Status"), secureReceiverService.acceptedUploadCount > 0 ? RokuricsCopy.text("已接收", "Received") : RokuricsCopy.text("暂无", "None"), style: .name)
                }
                .padding(6)
                .macLiquidGlassCard(cornerRadius: 24, material: .thinMaterial, fillOpacity: 0.44, strokeOpacity: 0.38, shadowOpacity: 0.07, shadowRadius: 14, shadowY: 7)
            }
            .padding(28)
        }
        .frame(width: 600)
    }

    private func uploadRow(_ label: String, _ value: String, style: MacConnectionDetailValueStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(label)
                .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
                .foregroundStyle(MacTheme.tertiaryText(for: colorScheme))
                .frame(width: 128, alignment: .leading)

            Text(value)
                .font(style.font(for: value))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct MacSheetHeader: View {
    let title: String
    let systemImage: String
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(MacTheme.accentGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            Text(title)
                .font(title.macContainsCJK ? MacTypography.chineseTitle(size: 24, weight: .bold) : MacTypography.englishTitle(size: 25, weight: .semibold))
                .foregroundStyle(MacTheme.deepText(for: colorScheme))

            Spacer(minLength: 16)

            RokuricsCircleIconButton(
                systemImage: "xmark",
                accessibilityTitle: RokuricsCopy.text("关闭", "Close"),
                tint: MacTheme.softText(for: colorScheme),
                action: onClose
            )
        }
    }
}

private enum MacConnectionDetailValueStyle {
    case name
    case number
    case technical

    func font(for value: String) -> Font {
        switch self {
        case .name:
            return value.macContainsCJK
                ? MacTypography.chineseBody(size: 13, weight: .semibold)
                : MacTypography.englishBody(size: 13, weight: .semibold)
        case .number:
            return value.macContainsCJK
                ? MacTypography.chineseBody(size: 13, weight: .semibold)
                : MacTypography.numberBody(size: 13, weight: .semibold)
        case .technical:
            return MacTypography.technical(size: 12, weight: .semibold)
        }
    }
}

private struct MacConnectionDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(MacTheme.glassStroke(for: colorScheme).opacity(colorScheme == .dark ? 0.14 : 0.34))
            .frame(height: 1)
            .padding(.leading, 132)
    }
}

private struct MacConnectionPrimaryButtonStyle: ButtonStyle {
    var verticalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
            .background(MacTheme.accentGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.40), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MacConnectionSecondaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(MacTheme.aqua)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MacTheme.aqua.opacity(colorScheme == .dark ? 0.30 : 0.36), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MacConnectionDestructiveButtonStyle: ButtonStyle {
    var verticalPadding: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacTypography.chineseCaption(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, verticalPadding)
            .background(MacTheme.coral.opacity(configuration.isPressed ? 0.76 : 0.90), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.30), lineWidth: 1)
            }
            .shadow(color: MacTheme.coral.opacity(configuration.isPressed ? 0.08 : 0.16), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}

private func formattedDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = RokuricsCopy.displayLocale
    formatter.dateFormat = "MM-dd HH:mm"
    return formatter.string(from: date)
}

private extension String {
    func macGroupedFingerprint(groupsPerLine: Int) -> String {
        let groups = uppercased().macChunked(into: 4)
        guard groupsPerLine > 0 else {
            return groups.joined(separator: " ")
        }

        return stride(from: 0, to: groups.count, by: groupsPerLine)
            .map { index in
                groups[index..<Swift.min(index + groupsPerLine, groups.count)].joined(separator: " ")
            }
            .joined(separator: "\n")
    }

    func macChunked(into size: Int) -> [String] {
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
