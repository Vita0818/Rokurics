//
//  SecureReceiverService.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

@MainActor
final class SecureReceiverService: ObservableObject {
    @Published private(set) var isHTTPSRunning = false
    @Published private(set) var httpsStatusText = "HTTPS 未就绪"
    @Published private(set) var pairingStatusText = "未配对"
    @Published private(set) var port = 8787
    @Published private(set) var localIPAddress = "未知"
    @Published private(set) var fingerprint = "未生成"
    @Published private(set) var fingerprintType = "unknown"
    @Published private(set) var pairingCode = "未生成"
    @Published private(set) var pairingExpiresAtText = "未开始"
    @Published private(set) var pairedDeviceCount = 0
    @Published private(set) var acceptedUploadCount = 0
    @Published private(set) var lastAcceptedFileName = "暂无"
    @Published private(set) var lastReceivedRecordingID = "暂无"
    @Published private(set) var lastError: String?

    let identityManager: MacIdentityManager
    let pairedDeviceStore: PairedDeviceStore
    let pairingManager: PairingManager
    let requestVerifier: RequestVerifier
    let receivedFileStore: ReceivedFileStore
    let recordingFileStore: MacRecordingFileStore

    private var httpsServer: SecureLocalHTTPSServer?
    private let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init() {
        let identityManager = MacIdentityManager()
        let pairedDeviceStore = PairedDeviceStore()
        let pairingManager = PairingManager(pairedDeviceStore: pairedDeviceStore)
        let requestVerifier = RequestVerifier(pairedDeviceStore: pairedDeviceStore)
        let receivedFileStore = ReceivedFileStore()
        let recordingFileStore = MacRecordingFileStore()

        self.identityManager = identityManager
        self.pairedDeviceStore = pairedDeviceStore
        self.pairingManager = pairingManager
        self.requestVerifier = requestVerifier
        self.receivedFileStore = receivedFileStore
        self.recordingFileStore = recordingFileStore

        identityManager.loadOrCreateIdentity()
        acceptedUploadCount = receivedFileStore.savedFileCount()
        refreshSecurityState()
    }

    var canStartHTTPS: Bool {
        identityManager.status.hasTLSIdentity
    }

    var canPair: Bool {
        identityManager.status.hasSigningIdentity
    }

    var fingerprintShortCode: String {
        fingerprint == "未生成" ? "未就绪" : fingerprint.shortSecurityFingerprint
    }

    var formattedFingerprint: String {
        fingerprint == "未生成" ? fingerprint : fingerprint.groupedSecurityFingerprint
    }

    var pairedDeviceSummary: String {
        pairedDeviceCount == 0 ? "未配对设备" : "\(pairedDeviceCount) 台已配对"
    }

    var latestPairedDevice: PairedDevice? {
        pairedDeviceStore.devices.sorted { first, second in
            (first.lastSeenAt ?? first.pairedAt) > (second.lastSeenAt ?? second.pairedAt)
        }
        .first
    }

    var tlsBlockerText: String {
        identityManager.status.tlsBlocker ?? "HTTPS 身份未就绪"
    }

    func startSecureReceiving() {
        print("[RokuricsHTTPS] secure receive button tapped")
        refreshSecurityState()

        guard canStartHTTPS else {
            lastError = tlsBlockerText
            httpsStatusText = "HTTPS 未就绪"
            print("[RokuricsHTTPS] upload accepted/rejected: rejected; reason=tls_identity_unavailable")
            return
        }

        let server = SecureLocalHTTPSServer(
            port: port,
            identityManager: identityManager,
            pairingManager: pairingManager,
            requestVerifier: requestVerifier,
            receivedFileStore: receivedFileStore,
            recordingFileStore: recordingFileStore,
            onReady: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isHTTPSRunning = true
                    self?.httpsStatusText = "HTTPS 运行中"
                    self?.lastError = nil
                }
            },
            onFailed: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.httpsServer = nil
                    self?.isHTTPSRunning = false
                    self?.httpsStatusText = "HTTPS 启动失败"
                    self?.lastError = message
                }
            },
            onPairingChanged: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshPairingState()
                }
            },
            onUploadAccepted: { [weak self] fileName in
                Task { @MainActor [weak self] in
                    self?.acceptedUploadCount = self?.receivedFileStore.savedFileCount() ?? 0
                    self?.lastAcceptedFileName = fileName
                    self?.lastError = nil
                }
            },
            onRecordingAccepted: { [weak self] recordingID in
                Task { @MainActor [weak self] in
                    self?.lastReceivedRecordingID = recordingID
                    self?.lastError = nil
                }
            }
        )

        do {
            try server.start()
            httpsServer = server
            httpsStatusText = "HTTPS 身份就绪"
            lastError = nil
        } catch {
            httpsServer = nil
            isHTTPSRunning = false
            httpsStatusText = "HTTPS 启动失败"
            lastError = error.localizedDescription
        }
    }

    func stopSecureReceiving() {
        httpsServer?.stop()
        httpsServer = nil
        isHTTPSRunning = false
        httpsStatusText = identityManager.status.hasTLSIdentity ? "HTTPS 身份就绪" : "HTTPS 未就绪"
    }

    func beginPairing() {
        pairingManager.refresh()
        guard canPair else {
            lastError = "Mac 身份未就绪，无法生成配对码。"
            print("[RokuricsPairing] pairing failure: identity_not_ready")
            return
        }

        pairingManager.beginPairing()
        refreshPairingState()
        lastError = nil
    }

    func disconnectPairedDevices() {
        pairingManager.invalidatePairing(reason: "mac_ui_disconnect")
        pairedDeviceStore.clearAll()
        refreshPairingState()
        lastError = pairedDeviceStore.lastError
    }

    func refreshSecurityState() {
        localIPAddress = MacLocalNetworkAddressProvider.preferredIPv4Address(logPrefix: "[RokuricsSecurity]") ?? "未知"
        fingerprint = identityManager.status.displayFingerprint
        fingerprintType = identityManager.status.fingerprintType
        pairedDeviceCount = pairedDeviceStore.deviceCount
        httpsStatusText = identityManager.status.hasTLSIdentity ? (isHTTPSRunning ? "HTTPS 运行中" : "HTTPS 身份就绪") : "HTTPS 未就绪"
        refreshPairingState()
    }

    private func refreshPairingState() {
        pairingManager.refresh()
        pairingStatusText = pairingManager.state.displayText
        pairedDeviceCount = pairedDeviceStore.deviceCount

        if let challenge = pairingManager.activeChallenge {
            pairingCode = challenge.code
            pairingExpiresAtText = expiryFormatter.string(from: challenge.expiresAt)
        } else {
            pairingCode = "未生成"
            pairingExpiresAtText = "未开始"
        }

        if let storeError = pairedDeviceStore.lastError {
            lastError = storeError
        } else if let identityError = identityManager.lastError {
            lastError = identityError
        }
    }
}
