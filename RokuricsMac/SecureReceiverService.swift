//
//  SecureReceiverService.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation

private func canonicalMasterSwitchReadConfigurationForStore(
    _ configuration: CanonicalReadRuntimeConfiguration?
) -> CanonicalReadRuntimeConfiguration? {
    guard let configuration else {
        return nil
    }
    switch configuration.mode {
    case .disabled, .blocked:
        return nil
    case .parallelCompare, .canonicalReadCandidate, .guardedCanonicalReadWithLegacyFallback:
        return configuration
    }
}

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
    case portInUse
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
    var operation: String? = nil
    var totalMs: Int? = nil
    var dominantSubphase: String? = nil
    var dominantSubphaseMs: Int? = nil
    var inventoryBuildMs: Int? = nil
    var projectionRebuildMs: Int? = nil
    var hashMs: Int? = nil
    var applyMs: Int? = nil
    var waitBackgroundMs: Int? = nil
}

@MainActor
final class ConnectionDiagnosticsStore {
    static let shared = ConnectionDiagnosticsStore()

    private let fileManager: FileManager
    let logURL: URL
    private let maxEntries: Int
    private let diagnosticsWriter: CanonicalAsyncDiagnosticsWriter
    private var recentEntries: [ConnectionDiagnosticEntry] = []
    private var pendingEnqueueTail: Task<Void, Never>?
    private var pendingEnqueueGeneration = 0
    private var runtimeCounterStateByKey: [String: (pending: Int, total: Int, lastLoggedAt: Date)] = [:]

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        maxEntries: Int = 200,
        diagnosticsWriterConfiguration: CanonicalAsyncDiagnosticsWriterConfiguration = CanonicalAsyncDiagnosticsWriterConfiguration()
    ) {
        self.fileManager = fileManager
        self.maxEntries = maxEntries
        let root = rootURL ?? MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
        logURL = root
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("connection-diagnostics.jsonl", isDirectory: false)
        diagnosticsWriter = CanonicalAsyncDiagnosticsWriter(
            sink: CanonicalFileDiagnosticsSink(
                logURL: logURL,
                fileManager: fileManager,
                maxPersistedLines: maxEntries
            ),
            configuration: diagnosticsWriterConfiguration
        )
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
        perfLog: CanonicalPerfLog.Record? = nil,
        timestamp: Date = Date()
    ) {
        let entry = ConnectionDiagnosticEntry(
            timestamp: timestamp,
            phase: sanitizedForDiagnostics(phase) ?? "redactionRejected",
            host: sanitizedForDiagnostics(host),
            port: port,
            fingerprintPrefix: fingerprintPrefix(fingerprint),
            listenerState: sanitizedForDiagnostics(listenerState),
            activePort: activePort,
            routeReceivedAt: routeReceivedAt,
            routePath: sanitizedForDiagnostics(routePath),
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: sanitizedForDiagnostics(requestDeviceIDPrefix).map { String($0.prefix(12)) },
            verifierStartedAt: verifierStartedAt,
            verifierSucceeded: verifierSucceeded,
            verifierFailed: verifierFailed,
            markDeviceSeenCalled: markDeviceSeenCalled,
            pairedDeviceLastSeenBefore: pairedDeviceLastSeenBefore,
            pairedDeviceLastSeenAfter: pairedDeviceLastSeenAfter,
            connectionStatusStoreUpdated: connectionStatusStoreUpdated,
            uiObservedLastSeenAt: uiObservedLastSeenAt,
            syncRunID: sanitizedForDiagnostics(syncRunID),
            beginPairingRequested: beginPairingRequested,
            codeIssued: codeIssued,
            beginPairingButtonEnabled: beginPairingButtonEnabled,
            payloadPublished: payloadPublished,
            copyEnabled: copyEnabled,
            errorCode: sanitizedForDiagnostics(errorCode),
            errorMessage: sanitizedForDiagnostics(errorMessage),
            errorCategory: sanitizedForDiagnostics(errorCategory),
            operation: sanitizedForDiagnostics(perfLog?.operation?.rawValue),
            totalMs: perfLog?.totalMs,
            dominantSubphase: sanitizedForDiagnostics(perfLog?.dominantSubphase?.rawValue),
            dominantSubphaseMs: perfLog?.dominantSubphaseMs,
            inventoryBuildMs: perfLog?.inventoryBuildMs,
            projectionRebuildMs: perfLog?.projectionRebuildMs,
            hashMs: perfLog?.hashMs,
            applyMs: perfLog?.applyMs,
            waitBackgroundMs: perfLog?.waitBackgroundMs
        )

        appendRecentEntry(entry)
        enqueueEntryForAsyncWrite(
            entry,
            priority: Self.diagnosticsPriority(phase: entry.phase, errorCode: entry.errorCode)
        )
    }

    func recordPerfLog(_ record: CanonicalPerfLog.Record) {
        self.record(
            phase: record.phase,
            host: nil,
            port: nil,
            fingerprint: nil,
            listenerState: nil,
            activePort: nil,
            syncRunID: nil,
            errorCategory: record.result ?? record.dominantSubphase?.rawValue,
            perfLog: record
        )
    }

    func recordRuntimeCounterTick(
        scope: String,
        kind: String,
        now: Date = Date()
    ) {
        let safeScope = sanitizedForDiagnostics(scope) ?? "redactionRejected"
        let safeKind = sanitizedForDiagnostics(kind) ?? "counter"
        let key = "\(safeScope)|\(safeKind)"
        var state = runtimeCounterStateByKey[key] ?? (pending: 0, total: 0, lastLoggedAt: now)
        state.pending += 1
        state.total += 1

        guard now.timeIntervalSince(state.lastLoggedAt) >= 1 else {
            runtimeCounterStateByKey[key] = state
            return
        }

        let delta = state.pending
        let total = state.total
        state.pending = 0
        state.lastLoggedAt = now
        runtimeCounterStateByKey[key] = state

        record(
            phase: "runtimeCounterTick",
            host: nil,
            port: nil,
            fingerprint: nil,
            listenerState: nil,
            activePort: nil,
            errorCategory: "scope=\(safeScope),kind=\(safeKind),delta=\(delta),total=\(total)"
        )
    }

    func loadEntries() -> [ConnectionDiagnosticEntry] {
        if recentEntries.isEmpty == false {
            return recentEntries
        }
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

    func flushForTests() async {
        while let pendingEnqueueTail {
            await pendingEnqueueTail.value
        }
        await diagnosticsWriter.flushForTests()
        recentEntries.removeAll(keepingCapacity: true)
    }

    func drainForTests() async {
        await flushForTests()
    }

    func diagnosticsWriterMetricsForTests() async -> CanonicalAsyncDiagnosticsWriterMetrics {
        await diagnosticsWriter.currentMetrics()
    }

    private func appendRecentEntry(_ entry: ConnectionDiagnosticEntry) {
        recentEntries.append(entry)
        if recentEntries.count > maxEntries {
            recentEntries.removeFirst(recentEntries.count - maxEntries)
        }
    }

    private func enqueueEntryForAsyncWrite(
        _ entry: ConnectionDiagnosticEntry,
        priority: CanonicalAsyncDiagnosticsPriority
    ) {
        let data = Self.encodedJSONLData(for: entry)
            ?? Self.encodedJSONLData(for: Self.redactionRejectedEntry(timestamp: entry.timestamp))
        guard let data else {
            return
        }
        let writer = diagnosticsWriter
        let previousTask = pendingEnqueueTail
        pendingEnqueueGeneration += 1
        let generation = pendingEnqueueGeneration
        pendingEnqueueTail = Task { [weak self] in
            if let previousTask {
                await previousTask.value
            }
            _ = await writer.enqueueJSONLLine(data, priority: priority)
            guard let self, self.pendingEnqueueGeneration == generation else {
                return
            }
            self.pendingEnqueueTail = nil
        }
    }

    private nonisolated static func diagnosticsPriority(
        phase: String,
        errorCode: String?
    ) -> CanonicalAsyncDiagnosticsPriority {
        if errorCode?.isEmpty == false {
            return .critical
        }
        let normalizedPhase = phase.lowercased()
        let isTerminalResult = normalizedPhase.hasSuffix("completed")
            || normalizedPhase.hasSuffix("failed")
            || normalizedPhase.hasSuffix("failure")
        if isTerminalResult,
           normalizedPhase.contains("syncrun") || normalizedPhase.contains("synctick") {
            return .critical
        }
        if isTerminalResult,
           normalizedPhase.contains("upload") || normalizedPhase.contains("apply") {
            return .critical
        }
        return .normal
    }

    private nonisolated static func encodedJSONLData(for entry: ConnectionDiagnosticEntry) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(entry),
              let encoded = String(data: data, encoding: .utf8),
              CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(encoded) else {
            return nil
        }
        data.append(0x0A)
        return data
    }

    private nonisolated static func redactionRejectedEntry(timestamp: Date) -> ConnectionDiagnosticEntry {
        ConnectionDiagnosticEntry(
            timestamp: timestamp,
            phase: "diagnosticRedactionRejected",
            host: nil,
            port: nil,
            fingerprintPrefix: nil,
            listenerState: nil,
            activePort: nil,
            routeReceivedAt: nil,
            routePath: nil,
            heartbeatSequence: nil,
            requestDeviceIDPrefix: nil,
            verifierStartedAt: nil,
            verifierSucceeded: nil,
            verifierFailed: nil,
            markDeviceSeenCalled: nil,
            pairedDeviceLastSeenBefore: nil,
            pairedDeviceLastSeenAfter: nil,
            connectionStatusStoreUpdated: nil,
            uiObservedLastSeenAt: nil,
            syncRunID: nil,
            beginPairingRequested: nil,
            codeIssued: nil,
            beginPairingButtonEnabled: nil,
            payloadPublished: nil,
            copyEnabled: nil,
            errorCode: nil,
            errorMessage: nil,
            errorCategory: "redactionRejected"
        )
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

    private func sanitizedForDiagnostics(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        if CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(trimmed) {
            return trimmed
        }
        return "redactionRejected"
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
    @Published private(set) var effectiveSyncStatusByObjectID: [CanonicalObjectID: CanonicalEffectiveSyncStatus] = [:]

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
    let canonicalLiveReadOnlyTransportProbePolicy: CanonicalLiveReadOnlyTransportProbePolicy
    var canonicalLibraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration
    var canonicalRecordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)?
    var canonicalGeneratedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    var canonicalLibraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)?
    var canonicalTombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)?
    var canonicalSyncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration
    var canonicalApplyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration
    var canonicalExistenceApplyRuntimeConfiguration: CanonicalExistenceApplyRuntimeConfiguration
    var canonicalConnectionRuntimeConfiguration: CanonicalConnectionRuntimeConfiguration
    var canonicalReadRuntimeConfiguration: CanonicalReadRuntimeConfiguration
    var canonicalKernelMode: CanonicalKernelSwitchMode
    var canonicalRecordingExistenceApplyPort: (any MacCanonicalRecordingExistenceApplyPort)?
    var canonicalAudioUploadCutoverExecutor: MacAudioUploadCutoverExecutor?
    let canonicalKernelSwitchResultProvider: (() -> CanonicalKernelSwitchResult)?
    let canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime
    let canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime
    var canonicalConnectionRuntime: CanonicalConnectionRuntime

    private var httpsServer: SecureLocalHTTPSServer?
    private var pendingPairingStartAfterHTTPSReady = false
    private var storeObservationCancellables: Set<AnyCancellable> = []
    private var canonicalKernelSwitchObserver: NSObjectProtocol?
    private var syncEventObserver: NSObjectProtocol?
    private var macSyncEventDebounceTask: Task<Void, Never>?
    private var pendingMacSyncEventReasons: Set<SyncTriggerReason> = []
    private var pendingMacSyncEventRecordingIDPrefix: String?
    private var pendingMacSyncEventFirstReceivedAt: Date?
    private var pendingMacSyncEventReceivedCount = 0
    private var pendingMacSyncEventCoalescedCount = 0
    private var macSyncEventWindowStartedAt: Date?
    private var macSyncEventWindowCount = 0
    private let macSyncEventDebounceInterval: TimeInterval = 0.75
    private let macSyncEventStormWindow: TimeInterval = 5
    private let macSyncEventMaxEventsPerWindow = 40
    private let preferredIPAddressProvider: () -> String?
    private let receiverPortDidChange: (Int) -> Void
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
        canonicalLiveReadOnlyTransportProbePolicy: CanonicalLiveReadOnlyTransportProbePolicy = .disabled,
        canonicalLibraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration = .disabled,
        canonicalRecordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)? = nil,
        canonicalGeneratedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)? = nil,
        canonicalLibraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)? = nil,
        canonicalTombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)? = nil,
        canonicalSyncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration = .disabled,
        canonicalApplyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration = .disabled,
        canonicalExistenceApplyRuntimeConfiguration: CanonicalExistenceApplyRuntimeConfiguration = .disabled,
        canonicalConnectionRuntimeConfiguration: CanonicalConnectionRuntimeConfiguration = .disabled,
        canonicalReadRuntimeConfiguration: CanonicalReadRuntimeConfiguration = .disabled,
        canonicalRecordingExistenceApplyPort injectedCanonicalRecordingExistenceApplyPort: (any MacCanonicalRecordingExistenceApplyPort)? = nil,
        canonicalAudioUploadCutoverExecutor injectedCanonicalAudioUploadCutoverExecutor: MacAudioUploadCutoverExecutor? = nil,
        canonicalKernelSwitchResultProvider: (() -> CanonicalKernelSwitchResult)? = nil,
        canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime? = nil,
        canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime? = nil,
        loadIdentityOnInit: Bool = true,
        receiverPortDidChange: @escaping (Int) -> Void = { port in
            MacAppStorageProfile.persistReceiverPort(port)
        },
        preferredIPAddressProvider: @escaping () -> String? = {
            MacLocalNetworkAddressProvider.preferredConnectionHost(logPrefix: "[RokuricsSecurity]")
        }
    ) {
        let identityManager = injectedIdentityManager ?? MacIdentityManager()
        let pairedDeviceStore = injectedPairedDeviceStore ?? PairedDeviceStore()
        let pairingManager = PairingManager(pairedDeviceStore: pairedDeviceStore)
        let requestVerifier = RequestVerifier(
            pairedDeviceStore: pairedDeviceStore,
            pairingManager: pairingManager
        )
        let receivedFileStore = injectedReceivedFileStore ?? ReceivedFileStore()
        let recordingFileStore = injectedRecordingFileStore ?? MacRecordingFileStore()
        let resolvedStatusTruthRuntime = canonicalStatusTruthRuntime ?? CanonicalStatusTruthRuntime()
        let canonicalKernelSwitchResult = canonicalKernelSwitchResultProvider?()
        let productionPortInjection = canonicalKernelSwitchResult.map {
            MacCanonicalProductionPortFactory.make(
                result: $0,
                productionRootURL: recordingFileStore.libraryRootURL,
                recordingFileStore: recordingFileStore
            )
        }
        let resolvedCanonicalExistenceApplyRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.existenceApplyRuntimeConfiguration
            ?? canonicalExistenceApplyRuntimeConfiguration
        let resolvedCanonicalConnectionRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.connectionRuntimeConfiguration
            ?? canonicalConnectionRuntimeConfiguration
        let resolvedCanonicalReadRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.readRuntimeConfiguration
            ?? canonicalReadRuntimeConfiguration
        let canonicalRecordingExistenceApplyPort: (any MacCanonicalRecordingExistenceApplyPort)?
        if let productionPortInjection {
            canonicalRecordingExistenceApplyPort = productionPortInjection.recordingExistenceApplyPort
        } else if let injectedCanonicalRecordingExistenceApplyPort {
            canonicalRecordingExistenceApplyPort = injectedCanonicalRecordingExistenceApplyPort
        } else if resolvedCanonicalExistenceApplyRuntimeConfiguration.canWriteMetadataOnlyRecord {
            canonicalRecordingExistenceApplyPort = MacCanonicalRecordingExistenceLedgerPort(rootURL: recordingFileStore.libraryRootURL)
        } else {
            canonicalRecordingExistenceApplyPort = nil
        }
        let studyLibraryStore = injectedStudyLibraryStore ?? StudyLibraryStore(
            recordingFileStore: recordingFileStore,
            canonicalExistenceApplyRuntimeConfiguration: resolvedCanonicalExistenceApplyRuntimeConfiguration,
            canonicalRecordingExistenceApplyPort: canonicalRecordingExistenceApplyPort,
            canonicalStatusTruthRuntime: resolvedStatusTruthRuntime
        )
        if injectedStudyLibraryStore != nil {
            studyLibraryStore.configureCanonicalExistenceApplyRuntime(
                configuration: resolvedCanonicalExistenceApplyRuntimeConfiguration,
                port: canonicalRecordingExistenceApplyPort
            )
        }
        studyLibraryStore.setCanonicalReadRuntimeConfiguration(
            canonicalMasterSwitchReadConfigurationForStore(resolvedCanonicalReadRuntimeConfiguration)
        )
        let resolvedGitBackedStudyMetadataStore = syncRuntimeConfiguration.gitBackedSyncEnabled
            ? (gitBackedStudyMetadataStore ?? GitBackedStudyMetadataStore())
            : gitBackedStudyMetadataStore
        let deviceConnectionStatusStore = injectedDeviceConnectionStatusStore ?? DeviceConnectionStatusStore()
        let syncStateStore = injectedSyncStateStore ?? StudyLibrarySyncStateStore()
        let connectionDiagnosticsStore = injectedConnectionDiagnosticsStore ?? ConnectionDiagnosticsStore()
        let resolvedStatusExchangeRuntime = canonicalStatusExchangeRuntime ?? CanonicalStatusExchangeRuntime(
            nodeID: CanonicalNodeID("mac-local"),
            truthRuntime: resolvedStatusTruthRuntime
        )
        let resolvedConnectionRuntime = CanonicalConnectionRuntime(
            configuration: resolvedCanonicalConnectionRuntimeConfiguration,
            localNode: CanonicalNodeIdentity(
                nodeID: CanonicalNodeID("mac-local"),
                role: .mac,
                displayName: "Rokurics Mac"
            )
        )
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
        self.canonicalLiveReadOnlyTransportProbePolicy = canonicalLiveReadOnlyTransportProbePolicy
        if let productionPortInjection {
            self.canonicalLibraryMetadataDebugPilotConfiguration = productionPortInjection.libraryMetadataDebugPilotConfiguration
            self.canonicalRecordingMetadataCutoverExecutor = productionPortInjection.recordingMetadataCutoverExecutor
            self.canonicalGeneratedArtifactCutoverExecutor = productionPortInjection.generatedArtifactCutoverExecutor
            self.canonicalLibraryMetadataCutoverExecutor = productionPortInjection.libraryMetadataCutoverExecutor
            self.canonicalTombstoneConflictCutoverExecutor = productionPortInjection.tombstoneConflictCutoverExecutor
            self.canonicalAudioUploadCutoverExecutor = productionPortInjection.audioUploadCutoverExecutor
        } else {
            self.canonicalLibraryMetadataDebugPilotConfiguration = canonicalLibraryMetadataDebugPilotConfiguration
            self.canonicalRecordingMetadataCutoverExecutor = canonicalRecordingMetadataCutoverExecutor
            self.canonicalGeneratedArtifactCutoverExecutor = canonicalGeneratedArtifactCutoverExecutor
            self.canonicalLibraryMetadataCutoverExecutor = canonicalLibraryMetadataCutoverExecutor
            self.canonicalTombstoneConflictCutoverExecutor = canonicalTombstoneConflictCutoverExecutor
            self.canonicalAudioUploadCutoverExecutor = injectedCanonicalAudioUploadCutoverExecutor
        }
        self.canonicalSyncRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.syncRuntimeConfiguration ?? canonicalSyncRuntimeConfiguration
        self.canonicalApplyRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.applyRuntimeConfiguration ?? canonicalApplyRuntimeConfiguration
        self.canonicalExistenceApplyRuntimeConfiguration = resolvedCanonicalExistenceApplyRuntimeConfiguration
        self.canonicalConnectionRuntimeConfiguration = resolvedCanonicalConnectionRuntimeConfiguration
        self.canonicalReadRuntimeConfiguration = resolvedCanonicalReadRuntimeConfiguration
        self.canonicalKernelMode = canonicalKernelSwitchResult?.effectiveMode
            ?? CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults().resolve().effectiveMode
        self.canonicalRecordingExistenceApplyPort = canonicalRecordingExistenceApplyPort
        self.canonicalKernelSwitchResultProvider = canonicalKernelSwitchResultProvider
        self.canonicalStatusTruthRuntime = resolvedStatusTruthRuntime
        self.canonicalStatusExchangeRuntime = resolvedStatusExchangeRuntime
        self.canonicalConnectionRuntime = resolvedConnectionRuntime
        self.preferredIPAddressProvider = preferredIPAddressProvider
        self.receiverPortDidChange = receiverPortDidChange
        self.port = port

        if loadIdentityOnInit {
            identityManager.loadOrCreateIdentity()
        }
        bindPresenceStores()
        bindCanonicalKernelSwitch()
        bindSyncEventTriggers()
        acceptedUploadCount = receivedFileStore.savedFileCount()
        refreshSecurityState()
    }

    deinit {
        if let canonicalKernelSwitchObserver {
            NotificationCenter.default.removeObserver(canonicalKernelSwitchObserver)
        }
        if let syncEventObserver {
            NotificationCenter.default.removeObserver(syncEventObserver)
        }
        macSyncEventDebounceTask?.cancel()
    }

    var canonicalStatusTruthReadPathAvailable: Bool {
        true
    }

    func produceCanonicalStatusFact(_ fact: CanonicalStatusFact) async -> CanonicalStatusFactMergeResult {
        let result = await canonicalStatusTruthRuntime.produce(fact)
        await refreshEffectiveSyncStatusSnapshot(for: fact.objectID)
        return result
    }

    func effectiveSyncStatus(for objectID: CanonicalObjectID) -> CanonicalEffectiveSyncStatus? {
        effectiveSyncStatusByObjectID[objectID]
    }

    func canonicalDisplaySyncState(for objectID: CanonicalObjectID) -> CanonicalDisplaySyncState? {
        effectiveSyncStatus(for: objectID).map(CanonicalEffectiveStatusUIProjection.project(_:))
    }

    private func refreshEffectiveSyncStatusSnapshot(for objectID: CanonicalObjectID) async {
        guard let snapshot = await canonicalStatusTruthRuntime.projectionSnapshot(for: objectID) else {
            return
        }
        effectiveSyncStatusByObjectID[objectID] = snapshot.effectiveStatus
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
        queueMacSyncEvent(reason: .appForegroundedWithPendingChanges, source: "SecureReceiverService.appBecameActive")
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
        refreshCanonicalKernelSwitchConfiguration(restartServerIfNeeded: false)

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
            canonicalLibraryMetadataDebugPilotConfiguration: canonicalLibraryMetadataDebugPilotConfiguration,
            canonicalRecordingMetadataCutoverExecutor: canonicalRecordingMetadataCutoverExecutor,
            canonicalGeneratedArtifactCutoverExecutor: canonicalGeneratedArtifactCutoverExecutor,
            canonicalLibraryMetadataCutoverExecutor: canonicalLibraryMetadataCutoverExecutor,
            canonicalTombstoneConflictCutoverExecutor: canonicalTombstoneConflictCutoverExecutor,
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
            onFailed: { [weak self] failure in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    if failure.kind == .addressInUse {
                        self.handleListenerAddressInUse(
                            failedPort: failure.port,
                            underlyingMessage: failure.message
                        )
                    } else {
                        self.httpsServer = nil
                        self.isHTTPSRunning = false
                        self.pendingPairingStartAfterHTTPSReady = false
                        self.pairingFlowState = .failed
                        self.pairingPayload = nil
                        self.httpsStatusText = "HTTPS 启动失败"
                        self.lastError = failure.message
                        self.connectionErrorCode = .serverUnreachable
                        self.recordConnectionDiagnostic(
                            phase: "listener_failed",
                            listenerState: "failed",
                            errorCode: SecureReceiverConnectionErrorCode.serverUnreachable.rawValue,
                            errorMessage: failure.message
                        )
                    }
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
            onRecordingAccepted: { [weak self] recordingID, reason in
                Task { @MainActor [weak self] in
                    self?.lastReceivedRecordingID = recordingID
                    self?.lastError = nil
                    self?.queueMacSyncEvent(
                        reason: reason,
                        source: "SecureReceiverService.onRecordingAccepted",
                        recordingID: recordingID
                    )
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
            },
            canonicalSyncRuntimeConfiguration: canonicalSyncRuntimeConfiguration,
            canonicalApplyRuntimeConfiguration: canonicalApplyRuntimeConfiguration,
            canonicalExistenceApplyRuntimeConfiguration: canonicalExistenceApplyRuntimeConfiguration,
            canonicalReadRuntimeConfiguration: canonicalReadRuntimeConfiguration,
            canonicalKernelMode: canonicalKernelMode,
            canonicalRecordingExistenceApplyPort: canonicalRecordingExistenceApplyPort,
            canonicalLiveReadOnlyTransportProbePolicy: canonicalLiveReadOnlyTransportProbePolicy,
            canonicalAudioUploadCutoverExecutor: canonicalAudioUploadCutoverExecutor,
            canonicalStatusTruthRuntime: canonicalStatusTruthRuntime,
            canonicalStatusExchangeRuntime: canonicalStatusExchangeRuntime,
            canonicalConnectionRuntime: canonicalConnectionRuntime
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
        } catch SecureHTTPSServerError.addressInUse(let failedPort, let message) {
            handleListenerAddressInUse(failedPort: failedPort, underlyingMessage: message)
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

    private func bindCanonicalKernelSwitch() {
        guard canonicalKernelSwitchResultProvider != nil else {
            return
        }
        canonicalKernelSwitchObserver = NotificationCenter.default.addObserver(
            forName: CanonicalKernelSwitchConfiguration.didChangeNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.refreshCanonicalKernelSwitchConfiguration(restartServerIfNeeded: true)
            }
        }
    }

    private func bindSyncEventTriggers() {
        syncEventObserver = NotificationCenter.default.addObserver(
            forName: .localNetworkSyncEventTriggered,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let reason = LocalNetworkSyncEventTrigger.reason(from: notification) else {
                return
            }
            let recordingID = notification.userInfo?[LocalNetworkSyncEventTrigger.recordingIDUserInfoKey] as? String
            let source = notification.userInfo?[LocalNetworkSyncEventTrigger.sourceUserInfoKey] as? String ?? "Notification"
            Task { @MainActor [weak self] in
                self?.queueMacSyncEvent(reason: reason, source: source, recordingID: recordingID)
            }
        }
    }

    private func queueMacSyncEvent(
        reason: SyncTriggerReason,
        source: String,
        recordingID: String? = nil,
        now: Date = Date()
    ) {
        if macSyncEventWindowStartedAt == nil || now.timeIntervalSince(macSyncEventWindowStartedAt ?? now) > macSyncEventStormWindow {
            macSyncEventWindowStartedAt = now
            macSyncEventWindowCount = 0
        }
        macSyncEventWindowCount += 1
        if macSyncEventWindowCount > macSyncEventMaxEventsPerWindow {
            recordConnectionDiagnostic(
                phase: "syncEventStormSuppressed",
                requestDeviceIDPrefix: recordingID.map { String($0.prefix(12)) },
                errorCode: "event_storm_suppressed",
                errorCategory: "reason=\(reason.rawValue),stormSuppressedCount=1"
            )
            return
        }

        let alreadyPending = pendingMacSyncEventReasons.contains(reason)
        pendingMacSyncEventReasons.insert(reason)
        pendingMacSyncEventRecordingIDPrefix = pendingMacSyncEventRecordingIDPrefix ?? recordingID.map { String($0.prefix(12)) }
        pendingMacSyncEventFirstReceivedAt = pendingMacSyncEventFirstReceivedAt ?? now
        pendingMacSyncEventReceivedCount += 1
        if alreadyPending {
            pendingMacSyncEventCoalescedCount += 1
            recordConnectionDiagnostic(
                phase: "syncEventTriggerCoalesced",
                requestDeviceIDPrefix: pendingMacSyncEventRecordingIDPrefix,
                errorCategory: "reason=\(reason.rawValue),eventTriggerCoalescedCount=1,coalescedReasonCount=\(pendingMacSyncEventCoalescedCount)"
            )
        }
        recordConnectionDiagnostic(
            phase: "syncEventTriggerReceived",
            requestDeviceIDPrefix: recordingID.map { String($0.prefix(12)) },
            errorCategory: "reason=\(reason.rawValue),source=\(source),eventTriggerReceivedCount=1,pendingReasonCount=\(pendingMacSyncEventReasons.count)"
        )
        if reason == .transcriptionStatusChanged || reason == .noteStatusChanged || reason == .syncStatusRefreshRequested {
            recordConnectionDiagnostic(
                phase: "statusConvergenceRefreshRequested",
                requestDeviceIDPrefix: recordingID.map { String($0.prefix(12)) },
                errorCategory: "reason=\(reason.rawValue),statusProjectionRefreshCount=1"
            )
            recordConnectionDiagnostic(
                phase: "statusConvergencePeerProofUnavailable",
                requestDeviceIDPrefix: recordingID.map { String($0.prefix(12)) },
                errorCategory: "reason=\(reason.rawValue)"
            )
        } else if reason == .macAudioReceiveFinalized {
            recordConnectionDiagnostic(
                phase: "statusConvergenceFinalizeProofAccepted",
                requestDeviceIDPrefix: recordingID.map { String($0.prefix(12)) },
                errorCategory: "reason=\(reason.rawValue)"
            )
        }

        macSyncEventDebounceTask?.cancel()
        macSyncEventDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.macSyncEventDebounceInterval ?? 0.75) * 1_000_000_000))
            self?.drainMacSyncEventQueue()
        }
    }

    private func drainMacSyncEventQueue(now: Date = Date()) {
        macSyncEventDebounceTask = nil
        guard !pendingMacSyncEventReasons.isEmpty else {
            return
        }

        let reasons = pendingMacSyncEventReasons
        let reasonsSummary = Self.syncEventReasonSummary(reasons)
        let firstReceivedAt = pendingMacSyncEventFirstReceivedAt ?? now
        let receivedCount = pendingMacSyncEventReceivedCount
        let coalescedCount = pendingMacSyncEventCoalescedCount
        let recordingIDPrefix = pendingMacSyncEventRecordingIDPrefix
        pendingMacSyncEventReasons = []
        pendingMacSyncEventRecordingIDPrefix = nil
        pendingMacSyncEventFirstReceivedAt = nil
        pendingMacSyncEventReceivedCount = 0
        pendingMacSyncEventCoalescedCount = 0

        studyLibraryStore.refresh()
        presenceObservationRevision += 1
        recordConnectionDiagnostic(
            phase: "statusConvergenceProjectionUpdated",
            requestDeviceIDPrefix: recordingIDPrefix,
            errorCategory: "reason=\(reasonsSummary),statusProjectionRefreshCount=1"
        )

        guard let device = latestPairedDevice else {
            recordConnectionDiagnostic(
                phase: "statusConvergencePeerProofUnavailable",
                requestDeviceIDPrefix: recordingIDPrefix,
                errorCode: "no_wants_connected_peer",
                errorCategory: "reason=\(reasonsSummary)"
            )
            return
        }

        let syncRunID = UUID().uuidString
        let latencyMs = max(0, Int(now.timeIntervalSince(firstReceivedAt) * 1_000))
        let pendingRecord = deviceConnectionStatusStore.recordPendingSyncRequestDetails(
            deviceID: device.id,
            displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            statusText: "等待 iPhone 拉取状态",
            syncRunID: syncRunID,
            initiatorDeviceID: "mac-\(String(fingerprint.prefix(16)))",
            reason: reasonsSummary,
            at: now
        )
        let effectiveSyncRunID = pendingRecord.signal.syncRunID
        if !pendingRecord.isDuplicate {
            syncStateStore.recordControlPlane(
                deviceID: device.id,
                syncRunID: effectiveSyncRunID,
                state: .syncStartSignalSent,
                at: now
            )
        }
        recordConnectionDiagnostic(
            phase: "syncEventImmediateTickQueued",
            requestDeviceIDPrefix: String(device.id.prefix(12)),
            syncRunID: effectiveSyncRunID,
            errorCategory: "macHintQueued=1,duplicatePending=\(pendingRecord.isDuplicate ? 1 : 0),reasons=\(reasonsSummary),eventTriggerReceivedCount=\(receivedCount),eventTriggerCoalescedCount=\(coalescedCount),eventToSyncStartLatencyMs=\(latencyMs)"
        )
        recordConnectionDiagnostic(
            phase: "macSyncRequestedHintSetForEvent",
            requestDeviceIDPrefix: String(device.id.prefix(12)),
            syncRunID: effectiveSyncRunID,
            errorCategory: "reasons=\(reasonsSummary)"
        )
    }

    private static func syncEventReasonSummary(_ reasons: Set<SyncTriggerReason>) -> String {
        reasons
            .map(\.rawValue)
            .sorted()
            .joined(separator: "+")
            .prefix(240)
            .description
    }

    private func refreshCanonicalKernelSwitchConfiguration(restartServerIfNeeded: Bool) {
        guard let canonicalKernelSwitchResultProvider else {
            return
        }
        let result = canonicalKernelSwitchResultProvider()
        let productionPortInjection = MacCanonicalProductionPortFactory.make(
            result: result,
            productionRootURL: recordingFileStore.libraryRootURL,
            recordingFileStore: recordingFileStore
        )
        canonicalSyncRuntimeConfiguration = result.effectiveConfiguration.syncRuntimeConfiguration
        canonicalApplyRuntimeConfiguration = result.effectiveConfiguration.applyRuntimeConfiguration
        canonicalExistenceApplyRuntimeConfiguration = result.effectiveConfiguration.existenceApplyRuntimeConfiguration
        canonicalConnectionRuntimeConfiguration = result.effectiveConfiguration.connectionRuntimeConfiguration
        canonicalConnectionRuntime = CanonicalConnectionRuntime(
            configuration: canonicalConnectionRuntimeConfiguration,
            localNode: CanonicalNodeIdentity(
                nodeID: CanonicalNodeID("mac-local"),
                role: .mac,
                displayName: "Rokurics Mac"
            )
        )
        canonicalReadRuntimeConfiguration = result.effectiveConfiguration.readRuntimeConfiguration
        canonicalKernelMode = result.effectiveMode
        canonicalLibraryMetadataDebugPilotConfiguration = productionPortInjection.libraryMetadataDebugPilotConfiguration
        canonicalRecordingMetadataCutoverExecutor = productionPortInjection.recordingMetadataCutoverExecutor
        canonicalGeneratedArtifactCutoverExecutor = productionPortInjection.generatedArtifactCutoverExecutor
        canonicalLibraryMetadataCutoverExecutor = productionPortInjection.libraryMetadataCutoverExecutor
        canonicalTombstoneConflictCutoverExecutor = productionPortInjection.tombstoneConflictCutoverExecutor
        canonicalRecordingExistenceApplyPort = productionPortInjection.recordingExistenceApplyPort
        canonicalAudioUploadCutoverExecutor = productionPortInjection.audioUploadCutoverExecutor
        studyLibraryStore.configureCanonicalExistenceApplyRuntime(
            configuration: canonicalExistenceApplyRuntimeConfiguration,
            port: canonicalRecordingExistenceApplyPort
        )
        studyLibraryStore.setCanonicalReadRuntimeConfiguration(
            canonicalMasterSwitchReadConfigurationForStore(canonicalReadRuntimeConfiguration)
        )
        recordConnectionDiagnostic(
            phase: "canonicalKernelSwitchEvaluated",
            listenerState: httpsServer?.isReady == true ? "ready" : "not_ready",
            errorCode: result.isBlocked ? "canonical_kernel_switch_blocked" : nil,
            errorMessage: result.diagnosticsSummary
        )
        guard restartServerIfNeeded, httpsServer != nil else {
            return
        }
        httpsServer?.stop()
        httpsServer = nil
        isHTTPSRunning = false
        if canStartHTTPS {
            startSecureReceiving()
        }
    }

    @discardableResult
    func prepareManualStudyLibrarySync(for device: PairedDevice?) -> DeviceConnectionStatus {
        let perfStartedAt = Date()
        recordPerfLog(CanonicalPerfLog.started(operation: .immediateSync))
        defer {
            let totalMs = CanonicalPerfLog.elapsedMs(since: perfStartedAt)
            let stages = CanonicalPerfLog.StageDurations(waitBackgroundMs: totalMs)
            for record in CanonicalPerfLog.finishedRecords(
                operation: .immediateSync,
                totalMs: totalMs,
                stages: stages
            ) {
                recordPerfLog(record)
            }
        }
        recordConnectionDiagnostic(phase: "manualSyncTapped")
        recordConnectionDiagnostic(phase: "manualSyncActionFired")
        guard let device else {
            let status = deviceConnectionStatusStore.markUnpaired(displayName: "iPhone")
            publishManualSyncStatus(status)
            return status
        }
        guard device.wantsConnection else {
            recordConnectionDiagnostic(phase: "syncSkippedBecauseUserDoesNotWantConnection")
            let status = deviceConnectionStatusStore.markUserDisconnected(
                deviceID: device.id,
                displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName
            )
            publishManualSyncStatus(status)
            return status
        }

        guard syncRuntimeConfiguration.gitBackedSyncEnabled else {
            let syncRunID = UUID().uuidString
            let initiatorDeviceID = "mac-\(String(fingerprint.prefix(16)))"
            let pendingRecord = deviceConnectionStatusStore.recordPendingSyncRequestDetails(
                deviceID: device.id,
                displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
                statusText: "等待 iPhone 执行同步",
                syncRunID: syncRunID,
                initiatorDeviceID: initiatorDeviceID
            )
            let effectiveSyncRunID = pendingRecord.signal.syncRunID
            if !pendingRecord.isDuplicate {
                syncStateStore.recordControlPlane(
                    deviceID: device.id,
                    syncRunID: effectiveSyncRunID,
                    state: .syncStartSignalSent
                )
            }
            if pendingRecord.isDuplicate {
                recordConnectionDiagnostic(
                    phase: "pendingSyncRequestDuplicate",
                    requestDeviceIDPrefix: String(device.id.prefix(12)),
                    syncRunID: effectiveSyncRunID,
                    errorCategory: "manualSyncDuplicate=1"
                )
            } else {
                recordConnectionDiagnostic(
                    phase: "syncRunIDCreated",
                    requestDeviceIDPrefix: String(device.id.prefix(12)),
                    syncRunID: effectiveSyncRunID
                )
                recordConnectionDiagnostic(
                    phase: "syncStartSignalSent",
                    requestDeviceIDPrefix: String(device.id.prefix(12)),
                    syncRunID: effectiveSyncRunID
                )
                recordConnectionDiagnostic(
                    phase: "pendingSyncRequestCreated",
                    requestDeviceIDPrefix: String(device.id.prefix(12)),
                    syncRunID: effectiveSyncRunID
                )
            }
            recordConnectionDiagnostic(
                phase: "manualSyncPendingCreated",
                requestDeviceIDPrefix: String(device.id.prefix(12)),
                syncRunID: effectiveSyncRunID
            )
            recordConnectionDiagnostic(
                phase: "pendingSyncRequestSet",
                requestDeviceIDPrefix: String(device.id.prefix(12)),
                syncRunID: effectiveSyncRunID
            )
            recordConnectionDiagnostic(
                phase: "manualSyncRequestedPendingSet",
                requestDeviceIDPrefix: String(device.id.prefix(12)),
                syncRunID: effectiveSyncRunID,
                errorCategory: "manualSyncRequestedPendingCount=1"
            )
            let status = pendingRecord.status
            publishManualSyncStatus(status)
            return status
        }

        studyLibraryStore.refresh()
        let manifest = studyLibraryStore.makeSyncManifest(deviceID: "mac-\(String(fingerprint.prefix(16)))")
        syncStateStore.recordPush(deviceID: device.id, remoteManifestHash: nil, pendingUploads: manifest.pendingUploads.count)
        let status = deviceConnectionStatusStore.recordSyncStatus(
            deviceID: device.id,
            displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            statusText: "已准备 \(manifest.summaryText)"
        )
        publishManualSyncStatus(status)
        return status
    }

    private func publishManualSyncStatus(_ status: DeviceConnectionStatus) {
        _ = status
        presenceObservationRevision += 1
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

    private func handleListenerAddressInUse(failedPort: Int, underlyingMessage: String) {
        httpsServer?.stop()
        httpsServer = nil
        isHTTPSRunning = false
        pendingPairingStartAfterHTTPSReady = false
        pairingFlowState = .failed
        pairingPayload = nil

        let nextPort = Self.nextPort(afterAddressInUse: failedPort)
        port = nextPort
        receiverPortDidChange(nextPort)
        httpsStatusText = "端口 \(failedPort) 被占用，已切换到 \(nextPort)"
        lastError = "端口 \(failedPort) 已被占用。下次配对将使用端口 \(nextPort)，请再次点击配对。"
        connectionErrorCode = .portInUse
        recordConnectionDiagnostic(
            phase: "listener_port_advanced_after_address_in_use",
            listenerState: "failed",
            beginPairingRequested: true,
            codeIssued: false,
            errorCode: SecureReceiverConnectionErrorCode.portInUse.rawValue,
            errorMessage: "failedPort=\(failedPort),nextPort=\(nextPort),reason=\(underlyingMessage)"
        )
    }

    nonisolated static func nextPort(afterAddressInUse failedPort: Int) -> Int {
        guard failedPort >= 1, failedPort < 65_535 else {
            return 8_787
        }
        return failedPort + 1
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
        errorCategory: String? = nil,
        perfLog: CanonicalPerfLog.Record? = nil
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
            errorCategory: errorCategory,
            perfLog: perfLog
        )
    }

    private func recordPerfLog(_ record: CanonicalPerfLog.Record) {
        recordConnectionDiagnostic(
            phase: record.phase,
            errorCategory: record.result ?? record.dominantSubphase?.rawValue,
            perfLog: record
        )
    }
}
