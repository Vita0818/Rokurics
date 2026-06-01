//
//  SecureReceiverService.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

enum SecureReceiverPairingFlowState: String, Equatable {
    case idle
    case startingListener
    case waitingForListenerReady
    case readyForPairing
    case pairingCodeIssued
    case failed
}

enum SecureReceiverConnectionErrorCode: String, Equatable {
    case listenerNotReady
    case serverUnreachable
    case tlsHandshakeFailed
    case fingerprintMismatch
    case pairingCodeRejected
    case requestVerifierRejected
    case heartbeatTimeout
    case staleHostOrPort
    case noReachableLANAddress
    case unknownNetworkError
}

struct SecureReceiverPairingPayload: Equatable {
    let host: String
    let port: Int
    let pairingCode: String
    let fingerprint: String
    let fingerprintType: String
    let expiresAtText: String
}

struct ConnectionDiagnosticEntry: Codable, Equatable {
    let timestamp: Date
    let phase: String
    let host: String?
    let port: Int?
    let fingerprintPrefix: String?
    let listenerState: String?
    let activePort: Int?
    let routeReceivedAt: Date?
    let routePath: String?
    let heartbeatSequence: UInt64?
    let requestDeviceIDPrefix: String?
    let verifierStartedAt: Date?
    let verifierSucceeded: Bool?
    let verifierFailed: Bool?
    let markDeviceSeenCalled: Bool?
    let pairedDeviceLastSeenBefore: Date?
    let pairedDeviceLastSeenAfter: Date?
    let connectionStatusStoreUpdated: Bool?
    let uiObservedLastSeenAt: Date?
    let syncRunID: String?
    let beginPairingRequested: Bool?
    let codeIssued: Bool?
    let beginPairingButtonEnabled: Bool?
    let payloadPublished: Bool?
    let copyEnabled: Bool?
    let errorCode: String?
    let errorMessage: String?
    let errorCategory: String?
}

@MainActor
final class ConnectionDiagnosticsStore {
    private let fileManager: FileManager
    let logURL: URL
    private let maxEntries: Int

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        maxEntries: Int = 200
    ) {
        self.fileManager = fileManager
        self.maxEntries = maxEntries
        let root = rootURL ?? MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
        logURL = root
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("connection-diagnostics.jsonl", isDirectory: false)
    }

    func record(
        phase: String,
        host: String?,
        port: Int?,
        fingerprint: String?,
        listenerState: String?,
        activePort: Int?,
        beginPairingRequested: Bool? = nil,
        codeIssued: Bool? = nil,
        beginPairingButtonEnabled: Bool? = nil,
        payloadPublished: Bool? = nil,
        copyEnabled: Bool? = nil,
        routeReceivedAt: Date? = nil,
        routePath: String? = nil,
        heartbeatSequence: UInt64? = nil,
        requestDeviceIDPrefix: String? = nil,
        verifierStartedAt: Date? = nil,
        verifierSucceeded: Bool? = nil,
        verifierFailed: Bool? = nil,
        markDeviceSeenCalled: Bool? = nil,
        pairedDeviceLastSeenBefore: Date? = nil,
        pairedDeviceLastSeenAfter: Date? = nil,
        connectionStatusStoreUpdated: Bool? = nil,
        uiObservedLastSeenAt: Date? = nil,
        syncRunID: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        errorCategory: String? = nil,
        timestamp: Date = Date()
    ) {
        let entry = ConnectionDiagnosticEntry(
            timestamp: timestamp,
            phase: phase,
            host: sanitized(host),
            port: port,
            fingerprintPrefix: fingerprintPrefix(fingerprint),
            listenerState: listenerState,
            activePort: activePort,
            routeReceivedAt: routeReceivedAt,
            routePath: sanitized(routePath),
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: sanitized(requestDeviceIDPrefix).map { String($0.prefix(12)) },
            verifierStartedAt: verifierStartedAt,
            verifierSucceeded: verifierSucceeded,
            verifierFailed: verifierFailed,
            markDeviceSeenCalled: markDeviceSeenCalled,
            pairedDeviceLastSeenBefore: pairedDeviceLastSeenBefore,
            pairedDeviceLastSeenAfter: pairedDeviceLastSeenAfter,
            connectionStatusStoreUpdated: connectionStatusStoreUpdated,
            uiObservedLastSeenAt: uiObservedLastSeenAt,
            syncRunID: sanitized(syncRunID),
            beginPairingRequested: beginPairingRequested,
            codeIssued: codeIssued,
            beginPairingButtonEnabled: beginPairingButtonEnabled,
            payloadPublished: payloadPublished,
            copyEnabled: copyEnabled,
            errorCode: errorCode,
            errorMessage: sanitized(errorMessage),
            errorCategory: sanitized(errorCategory)
        )

        do {
            try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let nextEntries = Array((loadEntries() + [entry]).suffix(maxEntries))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let lines = try nextEntries
                .map { try String(data: encoder.encode($0), encoding: .utf8) ?? "{}" }
                .joined(separator: "\n")
            try Data((lines + "\n").utf8).write(to: logURL, options: .atomic)
        } catch {
            print("[RokuricsConnectionDiagnostics] write failed: \(error.localizedDescription)")
        }
    }

    func loadEntries() -> [ConnectionDiagnosticEntry] {
        guard fileManager.fileExists(atPath: logURL.path),
              let rawText = try? String(contentsOf: logURL, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return rawText
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(ConnectionDiagnosticEntry.self, from: Data(line.utf8))
            }
    }

    private func fingerprintPrefix(_ fingerprint: String?) -> String? {
        let normalized = fingerprint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalized, !normalized.isEmpty, normalized != "未生成" else {
            return nil
        }
        return String(normalized.prefix(12))
    }

    private func sanitized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

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
    @Published private(set) var connectionErrorCode: SecureReceiverConnectionErrorCode?
    @Published private(set) var pairingFlowState: SecureReceiverPairingFlowState = .idle
    @Published private(set) var pairingPayload: SecureReceiverPairingPayload?
    @Published private(set) var presenceObservationRevision = 0

    let identityManager: MacIdentityManager
    let pairedDeviceStore: PairedDeviceStore
    let pairingManager: PairingManager
    let requestVerifier: RequestVerifier
    let receivedFileStore: ReceivedFileStore
    let recordingFileStore: MacRecordingFileStore
    let studyLibraryStore: StudyLibraryStore
    let gitBackedStudyMetadataStore: GitBackedStudyMetadataStore?
    let deviceConnectionStatusStore: DeviceConnectionStatusStore
    let syncStateStore: StudyLibrarySyncStateStore
    let syncRuntimeConfiguration: StudyLibrarySyncRuntimeConfiguration
    let connectionDiagnosticsStore: ConnectionDiagnosticsStore

    private var httpsServer: SecureLocalHTTPSServer?
    private var pendingPairingStartAfterHTTPSReady = false
    private var storeObservationCancellables: Set<AnyCancellable> = []
    private let preferredIPAddressProvider: () -> String?
    private let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(
        syncRuntimeConfiguration: StudyLibrarySyncRuntimeConfiguration = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false),
        gitBackedStudyMetadataStore: GitBackedStudyMetadataStore? = nil,
        port: Int = 8787,
        identityManager injectedIdentityManager: MacIdentityManager? = nil,
        pairedDeviceStore injectedPairedDeviceStore: PairedDeviceStore? = nil,
        receivedFileStore injectedReceivedFileStore: ReceivedFileStore? = nil,
        recordingFileStore injectedRecordingFileStore: MacRecordingFileStore? = nil,
        studyLibraryStore injectedStudyLibraryStore: StudyLibraryStore? = nil,
        deviceConnectionStatusStore injectedDeviceConnectionStatusStore: DeviceConnectionStatusStore? = nil,
        syncStateStore injectedSyncStateStore: StudyLibrarySyncStateStore? = nil,
        connectionDiagnosticsStore injectedConnectionDiagnosticsStore: ConnectionDiagnosticsStore? = nil,
        loadIdentityOnInit: Bool = true,
        preferredIPAddressProvider: @escaping () -> String? = {
            MacLocalNetworkAddressProvider.preferredIPv4Address(logPrefix: "[RokuricsSecurity]")
        }
    ) {
        let identityManager = injectedIdentityManager ?? MacIdentityManager()
        let pairedDeviceStore = injectedPairedDeviceStore ?? PairedDeviceStore()
        let pairingManager = PairingManager(pairedDeviceStore: pairedDeviceStore)
        let requestVerifier = RequestVerifier(pairedDeviceStore: pairedDeviceStore)
        let receivedFileStore = injectedReceivedFileStore ?? ReceivedFileStore()
        let recordingFileStore = injectedRecordingFileStore ?? MacRecordingFileStore()
        let studyLibraryStore = injectedStudyLibraryStore ?? StudyLibraryStore(recordingFileStore: recordingFileStore)
        let resolvedGitBackedStudyMetadataStore = syncRuntimeConfiguration.gitBackedSyncEnabled
            ? (gitBackedStudyMetadataStore ?? GitBackedStudyMetadataStore())
            : gitBackedStudyMetadataStore
        let deviceConnectionStatusStore = injectedDeviceConnectionStatusStore ?? DeviceConnectionStatusStore()
        let syncStateStore = injectedSyncStateStore ?? StudyLibrarySyncStateStore()
        let connectionDiagnosticsStore = injectedConnectionDiagnosticsStore ?? ConnectionDiagnosticsStore()
        UploadFlightRecorder.configureLogURL(
            recordingFileStore.libraryRootURL
                .appendingPathComponent("system", isDirectory: true)
                .appendingPathComponent("upload-trace.jsonl", isDirectory: false)
        )

        self.identityManager = identityManager
        self.pairedDeviceStore = pairedDeviceStore
        self.pairingManager = pairingManager
        self.requestVerifier = requestVerifier
        self.receivedFileStore = receivedFileStore
        self.recordingFileStore = recordingFileStore
        self.studyLibraryStore = studyLibraryStore
        self.gitBackedStudyMetadataStore = resolvedGitBackedStudyMetadataStore
        self.deviceConnectionStatusStore = deviceConnectionStatusStore
        self.syncStateStore = syncStateStore
        self.syncRuntimeConfiguration = syncRuntimeConfiguration
        self.connectionDiagnosticsStore = connectionDiagnosticsStore
        self.preferredIPAddressProvider = preferredIPAddressProvider
        self.port = port

        if loadIdentityOnInit {
            identityManager.loadOrCreateIdentity()
        }
        bindPresenceStores()
        acceptedUploadCount = receivedFileStore.savedFileCount()
        refreshSecurityState()
    }

    var canStartHTTPS: Bool {
        identityManager.status.hasTLSIdentity
    }

    var canPair: Bool {
        identityManager.status.hasSigningIdentity
    }

    var isHTTPSListenerReady: Bool {
        httpsServer?.isReady ?? false
    }

    var activeHTTPSPort: Int? {
        httpsServer?.activePort
    }

    var canCopyPairingInfo: Bool {
        pairingPayload != nil
    }

    var canBeginPairingFromUI: Bool {
        true
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
        pairedDeviceStore.devices.filter { $0.wantsConnection }.sorted { first, second in
            (first.lastSeenAt ?? first.pairedAt) > (second.lastSeenAt ?? second.pairedAt)
        }
        .first
    }

    var hasStoredPairedDevices: Bool {
        pairedDeviceStore.hasStoredDevices
    }

    var hasPausedPairedDevices: Bool {
        false
    }

    var tlsBlockerText: String {
        identityManager.status.tlsBlocker ?? "HTTPS 身份未就绪"
    }

    func recordAppLaunch() {
        recordConnectionDiagnostic(phase: "appLaunch")
    }

    func appBecameActive() {
        recordConnectionDiagnostic(phase: "appBecameActive")
        resumeConnectionIfUserWantsConnected()
    }

    func appBecameInactive() {
        recordConnectionDiagnostic(phase: "appBecameInactive")
    }

    func resumePresenceEvaluation() {
        let devices = pairedDeviceStore.devices.filter { $0.wantsConnection }
        guard !devices.isEmpty else {
            recordConnectionDiagnostic(phase: "heartbeatSuppressedBecauseUserDoesNotWantConnection")
            return
        }
        for device in devices {
            _ = deviceConnectionStatusStore.markMonitoringResumed(
                deviceID: device.id,
                displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName
            )
        }
        presenceObservationRevision += 1
        recordConnectionDiagnostic(phase: "presenceEvaluatorResumed")
    }

    func recordWindowOpened() {
        recordConnectionDiagnostic(phase: "windowOpened")
        resumeConnectionIfUserWantsConnected()
    }

    func recordWindowClosed() {
        recordConnectionDiagnostic(phase: "windowClosed")
    }

    func recordConnectionPageLoaded(beginPairingButtonEnabled: Bool, copyEnabled: Bool) {
        recordConnectionDiagnostic(
            phase: "connectionPageLoaded",
            beginPairingButtonEnabled: beginPairingButtonEnabled,
            payloadPublished: pairingPayload != nil,
            copyEnabled: copyEnabled
        )
    }

    func recordBeginPairingButtonTapped(beginPairingButtonEnabled: Bool, copyEnabled: Bool) {
        recordConnectionDiagnostic(
            phase: "beginPairingButtonTapped",
            beginPairingButtonEnabled: beginPairingButtonEnabled,
            payloadPublished: pairingPayload != nil,
            copyEnabled: copyEnabled
        )
    }

    func startSecureReceiving() {
        print("[RokuricsHTTPS] secure receive button tapped")
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "receiverServiceRunning",
            traceID: "test-receiver-\(UUID().uuidString.lowercased())",
            eventResult: "begin",
            reasonCode: "startSecureReceiving"
        )
        refreshSecurityState()

        if let httpsServer {
            if httpsServer.isReady {
                applyHTTPSReadyState(activePort: httpsServer.activePort, listenerState: "ready")
                completePendingPairingIfPossible(trigger: "already_ready")
            } else {
                pairingFlowState = pendingPairingStartAfterHTTPSReady ? .waitingForListenerReady : .startingListener
                httpsStatusText = "HTTPS 启动中"
                recordConnectionDiagnostic(
                    phase: "listener_start_already_in_progress",
                    listenerState: "starting",
                    beginPairingRequested: pendingPairingStartAfterHTTPSReady
                )
            }
            return
        }

        guard canStartHTTPS else {
            lastError = tlsBlockerText
            connectionErrorCode = .tlsHandshakeFailed
            httpsStatusText = "HTTPS 未就绪"
            pairingFlowState = .failed
            pairingPayload = nil
            recordConnectionDiagnostic(
                phase: "listener_start_blocked",
                listenerState: "failed",
                errorCode: SecureReceiverConnectionErrorCode.tlsHandshakeFailed.rawValue,
                errorMessage: tlsBlockerText
            )
            print("[RokuricsHTTPS] upload accepted/rejected: rejected; reason=tls_identity_unavailable")
            return
        }

        pairingFlowState = pendingPairingStartAfterHTTPSReady ? .waitingForListenerReady : .startingListener
        httpsStatusText = "HTTPS 启动中"
        recordConnectionDiagnostic(
            phase: "listener_start_requested",
            listenerState: "starting",
            beginPairingRequested: pendingPairingStartAfterHTTPSReady
        )
        recordConnectionDiagnostic(
            phase: "listenerStarting",
            listenerState: "starting",
            beginPairingRequested: pendingPairingStartAfterHTTPSReady
        )

        let server = SecureLocalHTTPSServer(
            port: port,
            identityManager: identityManager,
            pairingManager: pairingManager,
            requestVerifier: requestVerifier,
            receivedFileStore: receivedFileStore,
            recordingFileStore: recordingFileStore,
            studyLibraryStore: studyLibraryStore,
            gitBackedStudyMetadataStore: gitBackedStudyMetadataStore,
            deviceConnectionStatusStore: deviceConnectionStatusStore,
            syncStateStore: syncStateStore,
            syncRuntimeConfiguration: syncRuntimeConfiguration,
            onReady: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    self.applyHTTPSReadyState(activePort: self.httpsServer?.activePort, listenerState: "ready")
                    UploadFlightRecorder.record(
                        side: .Mac,
                        stage: "httpsListenerReady",
                        traceID: "test-receiver-\(UUID().uuidString.lowercased())",
                        eventResult: "success",
                        reasonCode: "listener_ready"
                    )
                    self.completePendingPairingIfPossible(trigger: "listener_ready")
                }
            },
            onFailed: { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.httpsServer = nil
                    self?.isHTTPSRunning = false
                    self?.pendingPairingStartAfterHTTPSReady = false
                    self?.pairingFlowState = .failed
                    self?.pairingPayload = nil
                    self?.httpsStatusText = "HTTPS 启动失败"
                    self?.lastError = message
                    self?.connectionErrorCode = .serverUnreachable
                    self?.recordConnectionDiagnostic(
                        phase: "listener_failed",
                        listenerState: "failed",
                        errorCode: SecureReceiverConnectionErrorCode.serverUnreachable.rawValue,
                        errorMessage: message
                    )
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
            },
            onConnectionDiagnostic: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.recordConnectionDiagnostic(
                        phase: event.phase,
                        listenerState: event.listenerState,
                        activePort: event.activePort,
                        routeReceivedAt: event.routeReceivedAt,
                        routePath: event.routePath,
                        heartbeatSequence: event.heartbeatSequence,
                        requestDeviceIDPrefix: event.requestDeviceIDPrefix,
                        verifierStartedAt: event.verifierStartedAt,
                        verifierSucceeded: event.verifierSucceeded,
                        verifierFailed: event.verifierFailed,
                        markDeviceSeenCalled: event.markDeviceSeenCalled,
                        pairedDeviceLastSeenBefore: event.pairedDeviceLastSeenBefore,
                        pairedDeviceLastSeenAfter: event.pairedDeviceLastSeenAfter,
                        connectionStatusStoreUpdated: event.connectionStatusStoreUpdated,
                        uiObservedLastSeenAt: event.uiObservedLastSeenAt,
                        syncRunID: event.syncRunID,
                        errorCode: event.errorCode,
                        errorMessage: event.errorMessage,
                        errorCategory: event.errorCategory
                    )
                }
            }
        )

        httpsServer = server

        do {
            try server.start()
            httpsStatusText = "HTTPS 身份就绪"
            lastError = nil
            if server.isReady {
                applyHTTPSReadyState(activePort: server.activePort, listenerState: "ready_after_start")
                completePendingPairingIfPossible(trigger: "ready_after_start")
            }
        } catch {
            httpsServer = nil
            isHTTPSRunning = false
            pendingPairingStartAfterHTTPSReady = false
            pairingFlowState = .failed
            pairingPayload = nil
            httpsStatusText = "HTTPS 启动失败"
            lastError = error.localizedDescription
            connectionErrorCode = .serverUnreachable
            recordConnectionDiagnostic(
                phase: "listener_start_failed",
                listenerState: "failed",
                errorCode: SecureReceiverConnectionErrorCode.serverUnreachable.rawValue,
                errorMessage: error.localizedDescription
            )
        }
    }

    func stopSecureReceiving() {
        pendingPairingStartAfterHTTPSReady = false
        httpsServer?.stop()
        httpsServer = nil
        isHTTPSRunning = false
        pairingFlowState = .idle
        pairingPayload = nil
        pairingManager.invalidatePairing(reason: "https_stopped")
        refreshPairingState()
        httpsStatusText = identityManager.status.hasTLSIdentity ? "HTTPS 身份就绪" : "HTTPS 未就绪"
        recordConnectionDiagnostic(phase: "listener_stopped", listenerState: "cancelled")
    }

    func beginPairing() {
        pairingManager.refresh()
        if pairedDeviceStore.hasPausedDevices && !pairedDeviceStore.hasWantsConnectedDevice {
            pairingManager.unpairAll(reason: "start_pairing_after_disconnect")
            _ = deviceConnectionStatusStore.markUnpaired(displayName: "iPhone")
            refreshPairingState()
            recordConnectionDiagnostic(phase: "startPairingAfterDisconnect")
        }
        pendingPairingStartAfterHTTPSReady = true
        recordConnectionDiagnostic(
            phase: "begin_pairing_requested",
            listenerState: httpsServer?.isReady == true ? "ready" : "not_ready",
            beginPairingRequested: true
        )
        recordConnectionDiagnostic(
            phase: "beginPairingRequested",
            listenerState: httpsServer?.isReady == true ? "ready" : "not_ready",
            beginPairingRequested: true
        )

        guard canPair else {
            lastError = "Mac 身份未就绪，无法生成配对码。"
            connectionErrorCode = .tlsHandshakeFailed
            pairingFlowState = .failed
            pairingPayload = nil
            pendingPairingStartAfterHTTPSReady = false
            recordConnectionDiagnostic(
                phase: "begin_pairing_failed",
                listenerState: "identity_not_ready",
                beginPairingRequested: true,
                codeIssued: false,
                errorCode: SecureReceiverConnectionErrorCode.tlsHandshakeFailed.rawValue,
                errorMessage: lastError
            )
            print("[RokuricsPairing] pairing failure: identity_not_ready")
            return
        }

        guard canStartHTTPS else {
            lastError = tlsBlockerText
            connectionErrorCode = .tlsHandshakeFailed
            pairingFlowState = .failed
            pairingPayload = nil
            pendingPairingStartAfterHTTPSReady = false
            httpsStatusText = "HTTPS 未就绪"
            recordConnectionDiagnostic(
                phase: "begin_pairing_deferred_tls_unavailable",
                listenerState: "failed",
                beginPairingRequested: true,
                codeIssued: false,
                errorCode: SecureReceiverConnectionErrorCode.tlsHandshakeFailed.rawValue,
                errorMessage: tlsBlockerText
            )
            print("[RokuricsPairing] pairing deferred: tls_identity_unavailable")
            return
        }

        if let httpsServer, httpsServer.isReady {
            applyHTTPSReadyState(activePort: httpsServer.activePort, listenerState: "ready")
            completePendingPairingIfPossible(trigger: "begin_pairing_already_ready")
            return
        }

        guard isHTTPSRunning else {
            pairingFlowState = httpsServer == nil ? .startingListener : .waitingForListenerReady
            httpsStatusText = "HTTPS 启动中"
            if httpsServer == nil {
                startSecureReceiving()
            } else {
                recordConnectionDiagnostic(
                    phase: "begin_pairing_waiting_for_listener_ready",
                    listenerState: "starting",
                    beginPairingRequested: true,
                    codeIssued: false
                )
            }
            if let httpsServer, httpsServer.isReady {
                applyHTTPSReadyState(activePort: httpsServer.activePort, listenerState: "ready")
                completePendingPairingIfPossible(trigger: "begin_pairing_ready_after_start")
            }
            print("[RokuricsPairing] pairing deferred until HTTPS listener ready")
            return
        }

        completePendingPairingIfPossible(trigger: "begin_pairing_running")
    }

    func disconnectPairedDevices() {
        let devices = pairedDeviceStore.devices
        pairingManager.invalidatePairing(reason: "mac_ui_disconnect")
        pendingPairingStartAfterHTTPSReady = false
        pairingPayload = nil
        httpsServer?.stop()
        httpsServer = nil
        isHTTPSRunning = false
        httpsStatusText = identityManager.status.hasTLSIdentity ? "HTTPS 身份就绪" : "HTTPS 未就绪"
        for device in devices {
            _ = deviceConnectionStatusStore.markUserDisconnected(
                deviceID: device.id,
                displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName
            )
        }
        pairingManager.unpairAll(reason: "mac_ui_disconnect")
        _ = deviceConnectionStatusStore.markUnpaired(displayName: "iPhone")
        refreshPairingState()
        lastError = pairedDeviceStore.lastError
        recordConnectionDiagnostic(phase: "disconnectTapped")
        recordConnectionDiagnostic(phase: "localCredentialsDeleted")
        recordConnectionDiagnostic(phase: "userConnectionIntentChanged", errorMessage: UserConnectionIntent.disconnectedByUser.rawValue)
    }

    func connectionStatus(for device: PairedDevice?) -> DeviceConnectionStatus {
        guard let device else {
            return .unpaired(displayName: "iPhone")
        }

        return deviceConnectionStatusStore.status(for: device.id)
            ?? DeviceConnectionStatus(
                deviceID: device.id,
                displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
                state: .offline,
                lastSeenAt: device.lastSeenAt,
                lastHeartbeatAt: device.lastSeenAt,
                lastSyncAt: syncStateStore.state.lastSuccessfulSyncAt,
                lastSyncStatus: syncRuntimeConfiguration.gitBackedSyncEnabled
                    ? syncStateStore.state.lastError ?? "待同步"
                    : StudyLibrarySyncRuntimeConfiguration.disabledStatusText,
                lastError: nil
            )
    }

    private func bindPresenceStores() {
        pairedDeviceStore.$devices
            .dropFirst()
            .sink { [weak self] devices in
                guard let self else {
                    return
                }
                self.pairedDeviceCount = devices.count
                self.presenceObservationRevision += 1
            }
            .store(in: &storeObservationCancellables)

        deviceConnectionStatusStore.$statusesByDeviceID
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else {
                    return
                }
                self.presenceObservationRevision += 1
            }
            .store(in: &storeObservationCancellables)
    }

    @discardableResult
    func prepareManualStudyLibrarySync(for device: PairedDevice?) -> DeviceConnectionStatus {
        recordConnectionDiagnostic(phase: "manualSyncTapped")
        recordConnectionDiagnostic(phase: "manualSyncActionFired")
        guard let device else {
            return deviceConnectionStatusStore.markUnpaired(displayName: "iPhone")
        }
        guard device.wantsConnection else {
            recordConnectionDiagnostic(phase: "syncSkippedBecauseUserDoesNotWantConnection")
            return deviceConnectionStatusStore.markUserDisconnected(
                deviceID: device.id,
                displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName
            )
        }

        guard syncRuntimeConfiguration.gitBackedSyncEnabled else {
            let syncRunID = UUID().uuidString
            let initiatorDeviceID = "mac-\(String(fingerprint.prefix(16)))"
            syncStateStore.recordControlPlane(
                deviceID: device.id,
                syncRunID: syncRunID,
                state: .syncStartSignalSent
            )
            recordConnectionDiagnostic(
                phase: "syncRunIDCreated",
                requestDeviceIDPrefix: String(device.id.prefix(12)),
                syncRunID: syncRunID
            )
            recordConnectionDiagnostic(
                phase: "syncStartSignalSent",
                requestDeviceIDPrefix: String(device.id.prefix(12)),
                syncRunID: syncRunID
            )
            let status = deviceConnectionStatusStore.recordPendingSyncRequest(
                deviceID: device.id,
                displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
                statusText: "等待 iPhone 执行同步",
                syncRunID: syncRunID,
                initiatorDeviceID: initiatorDeviceID
            )
            recordConnectionDiagnostic(
                phase: "pendingSyncRequestCreated",
                requestDeviceIDPrefix: String(device.id.prefix(12)),
                syncRunID: syncRunID
            )
            recordConnectionDiagnostic(
                phase: "manualSyncPendingCreated",
                requestDeviceIDPrefix: String(device.id.prefix(12)),
                syncRunID: syncRunID
            )
            recordConnectionDiagnostic(
                phase: "pendingSyncRequestSet",
                requestDeviceIDPrefix: String(device.id.prefix(12)),
                syncRunID: syncRunID
            )
            return status
        }

        studyLibraryStore.refresh()
        let manifest = studyLibraryStore.makeSyncManifest(deviceID: "mac-\(String(fingerprint.prefix(16)))")
        syncStateStore.recordPush(deviceID: device.id, remoteManifestHash: nil, pendingUploads: manifest.pendingUploads.count)
        return deviceConnectionStatusStore.recordSyncStatus(
            deviceID: device.id,
            displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            statusText: "已准备 \(manifest.summaryText)"
        )
    }

    func refreshSecurityState() {
        localIPAddress = preferredIPAddressProvider() ?? "未知"
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

        updatePairingPayload()

        if let storeError = pairedDeviceStore.lastError {
            lastError = storeError
        } else if let identityError = identityManager.lastError {
            lastError = identityError
        }
    }

    private func resumeConnectionIfUserWantsConnected() {
        guard pairedDeviceStore.hasWantsConnectedDevice else {
            recordConnectionDiagnostic(phase: "heartbeatSuppressedBecauseUserDoesNotWantConnection")
            return
        }

        if canStartHTTPS, httpsServer == nil {
            startSecureReceiving()
        }
        resumePresenceEvaluation()
    }

    private func applyHTTPSReadyState(activePort: Int?, listenerState: String) {
        isHTTPSRunning = true
        if let activePort, activePort > 0 {
            port = activePort
        }
        refreshSecurityState()
        pairingFlowState = pendingPairingStartAfterHTTPSReady ? .waitingForListenerReady : .readyForPairing
        httpsStatusText = "HTTPS 运行中"
        lastError = nil
        connectionErrorCode = nil
        recordConnectionDiagnostic(
            phase: "listener_ready",
            listenerState: listenerState,
            activePort: activePort ?? httpsServer?.activePort
        )
        recordConnectionDiagnostic(
            phase: "listenerReady",
            listenerState: listenerState,
            activePort: activePort ?? httpsServer?.activePort
        )
    }

    private func completePendingPairingIfPossible(trigger: String) {
        guard pendingPairingStartAfterHTTPSReady else {
            if httpsServer?.isReady == true, pairingFlowState != .pairingCodeIssued {
                pairingFlowState = .readyForPairing
            }
            return
        }

        guard canPair, canStartHTTPS else {
            pairingFlowState = .failed
            pendingPairingStartAfterHTTPSReady = false
            pairingPayload = nil
            connectionErrorCode = .tlsHandshakeFailed
            recordConnectionDiagnostic(
                phase: "pairing_code_not_issued",
                listenerState: "identity_not_ready",
                beginPairingRequested: true,
                codeIssued: false,
                errorCode: SecureReceiverConnectionErrorCode.tlsHandshakeFailed.rawValue,
                errorMessage: lastError ?? tlsBlockerText
            )
            return
        }

        guard let httpsServer, httpsServer.isReady else {
            pairingFlowState = .waitingForListenerReady
            httpsStatusText = "HTTPS 启动中"
            recordConnectionDiagnostic(
                phase: "pairing_waiting_for_listener_ready",
                listenerState: "not_ready",
                beginPairingRequested: true,
                codeIssued: false,
                errorCode: SecureReceiverConnectionErrorCode.listenerNotReady.rawValue
            )
            return
        }

        if let activePort = httpsServer.activePort, activePort > 0 {
            port = activePort
        }
        refreshSecurityState()
        pairingManager.beginPairing()
        pendingPairingStartAfterHTTPSReady = false
        refreshPairingState()
        pairingFlowState = .pairingCodeIssued
        lastError = nil
        connectionErrorCode = nil
        recordConnectionDiagnostic(
            phase: "pairing_code_issued",
            listenerState: "ready",
            activePort: httpsServer.activePort,
            beginPairingRequested: true,
            codeIssued: true,
            payloadPublished: pairingPayload != nil,
            copyEnabled: canCopyPairingInfo
        )
        recordConnectionDiagnostic(
            phase: "codeIssued",
            listenerState: "ready",
            activePort: httpsServer.activePort,
            beginPairingRequested: true,
            codeIssued: true,
            payloadPublished: pairingPayload != nil,
            copyEnabled: canCopyPairingInfo
        )
        print("[RokuricsPairing] pairing code issued from \(trigger)")
    }

    private func updatePairingPayload() {
        let previousPayload = pairingPayload
        if pairingManager.activeChallenge != nil,
           let httpsServer,
           httpsServer.isReady,
           localIPAddress == "未知" {
            pairingPayload = nil
            connectionErrorCode = .noReachableLANAddress
            recordConnectionDiagnostic(
                phase: "payload_not_published",
                listenerState: "ready",
                activePort: httpsServer.activePort,
                payloadPublished: false,
                copyEnabled: false,
                errorCode: SecureReceiverConnectionErrorCode.noReachableLANAddress.rawValue,
                errorMessage: "noReachableLANAddress"
            )
            return
        }

        guard let challenge = pairingManager.activeChallenge,
              let httpsServer,
              httpsServer.isReady,
              let activePort = httpsServer.activePort,
              activePort > 0,
              localIPAddress != "未知",
              identityManager.status.hasTLSIdentity,
              identityManager.status.certificateFingerprint.count == 64 else {
            pairingPayload = nil
            return
        }

        port = activePort
        pairingPayload = SecureReceiverPairingPayload(
            host: localIPAddress,
            port: activePort,
            pairingCode: challenge.code,
            fingerprint: identityManager.status.certificateFingerprint,
            fingerprintType: "certificate-sha256",
            expiresAtText: expiryFormatter.string(from: challenge.expiresAt)
        )

        if previousPayload != pairingPayload {
            recordConnectionDiagnostic(
                phase: "payloadPublished",
                listenerState: "ready",
                activePort: activePort,
                payloadPublished: true,
                copyEnabled: canCopyPairingInfo
            )
        }
    }

    private func recordConnectionDiagnostic(
        phase: String,
        listenerState: String? = nil,
        activePort: Int? = nil,
        beginPairingRequested: Bool? = nil,
        codeIssued: Bool? = nil,
        beginPairingButtonEnabled: Bool? = nil,
        payloadPublished: Bool? = nil,
        copyEnabled: Bool? = nil,
        routeReceivedAt: Date? = nil,
        routePath: String? = nil,
        heartbeatSequence: UInt64? = nil,
        requestDeviceIDPrefix: String? = nil,
        verifierStartedAt: Date? = nil,
        verifierSucceeded: Bool? = nil,
        verifierFailed: Bool? = nil,
        markDeviceSeenCalled: Bool? = nil,
        pairedDeviceLastSeenBefore: Date? = nil,
        pairedDeviceLastSeenAfter: Date? = nil,
        connectionStatusStoreUpdated: Bool? = nil,
        uiObservedLastSeenAt: Date? = nil,
        syncRunID: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        errorCategory: String? = nil
    ) {
        connectionDiagnosticsStore.record(
            phase: phase,
            host: localIPAddress == "未知" ? nil : localIPAddress,
            port: port > 0 ? port : nil,
            fingerprint: fingerprint == "未生成" ? nil : fingerprint,
            listenerState: listenerState,
            activePort: activePort ?? httpsServer?.activePort,
            beginPairingRequested: beginPairingRequested,
            codeIssued: codeIssued,
            beginPairingButtonEnabled: beginPairingButtonEnabled,
            payloadPublished: payloadPublished,
            copyEnabled: copyEnabled,
            routeReceivedAt: routeReceivedAt,
            routePath: routePath,
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: requestDeviceIDPrefix,
            verifierStartedAt: verifierStartedAt,
            verifierSucceeded: verifierSucceeded,
            verifierFailed: verifierFailed,
            markDeviceSeenCalled: markDeviceSeenCalled,
            pairedDeviceLastSeenBefore: pairedDeviceLastSeenBefore,
            pairedDeviceLastSeenAfter: pairedDeviceLastSeenAfter,
            connectionStatusStoreUpdated: connectionStatusStoreUpdated,
            uiObservedLastSeenAt: uiObservedLastSeenAt,
            syncRunID: syncRunID,
            errorCode: errorCode,
            errorMessage: errorMessage,
            errorCategory: errorCategory
        )
    }
}
