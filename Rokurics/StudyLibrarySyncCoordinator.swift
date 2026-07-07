//
//  StudyLibrarySyncCoordinator.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import Combine
import Foundation
import UIKit

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

@MainActor
protocol SecureMacConnectionSnapshotProviding: AnyObject {
    var snapshot: SecureMacConnectionSnapshot { get }
}

extension SecureMacConnectionStore: SecureMacConnectionSnapshotProviding {}

@MainActor
protocol SecureMacConnectionIntentProviding: AnyObject {
    var userConnectionIntent: UserConnectionIntent { get }
}

extension SecureMacConnectionStore: SecureMacConnectionIntentProviding {}

@MainActor
final class StudyLibrarySyncCoordinator: ObservableObject {
    typealias DeviceStatusSender = (
        _ settings: SecureMacConnectionSnapshot,
        _ statusRequest: DeviceStatusRequest
    ) async throws -> DeviceStatusResponse
    typealias HeartbeatRequestedSyncHandler = (_ syncRunID: String?) async -> Bool

    @Published private(set) var connectionStatus: DeviceConnectionStatus
    @Published private(set) var syncState: StudyLibrarySyncState
    @Published private(set) var isSyncing = false

    private let connectionStore: any SecureMacConnectionSnapshotProviding
    private let studyLibraryStore: StudyLibraryStore
    private weak var recordingManager: RecordingManager?
    private let uploadCoordinator: RecordingUploadCoordinator?
    private let client: SecureMacUploadClient
    private let deviceStatusSender: DeviceStatusSender
    private let heartbeatRequestedSyncHandler: HeartbeatRequestedSyncHandler?
    private let localNetworkSyncClient: any LocalNetworkSyncClientProtocol
    private let statusStore: DeviceConnectionStatusStore
    private let syncStateStore: StudyLibrarySyncStateStore
    private let runtimeConfiguration: StudyLibrarySyncRuntimeConfiguration
    private let presenceHeartbeatMonitor: LocalNetworkHeartbeatMonitor
    private let diagnosticsStore: ConnectionDiagnosticsStore
    private let heartbeatInterval: TimeInterval
    private let syncInterval: TimeInterval
    private var canonicalLibraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration
    private var canonicalRecordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)?
    private var canonicalGeneratedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    private var canonicalLibraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)?
    private var canonicalTombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)?
    private var canonicalSyncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration
    private var canonicalApplyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration
    private let canonicalKernelSwitchResultProvider: (() -> CanonicalKernelSwitchResult)?
    private let canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime
    private let canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime
    private let canonicalConnectionRuntime: CanonicalConnectionRuntime
    private var heartbeatTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var statusStoreSubscription: AnyCancellable?
    private var failureCount = 0
    private var pendingManualLocalNetworkSync = false
    private var pendingHeartbeatRequestedSync: (syncRunID: String?, hintedAt: Date)?
    private var heartbeatRequestedSyncTask: Task<Void, Never>?
    private var lastHeartbeatRequestedSyncQueuedAt: Date?
    private var lastHeartbeatRequestedSyncCompletedAt: Date?
    private let heartbeatRequestedSyncDebounceInterval: TimeInterval = 5

    init(
        connectionStore: any SecureMacConnectionSnapshotProviding,
        studyLibraryStore: StudyLibraryStore,
        recordingManager: RecordingManager? = nil,
        uploadCoordinator: RecordingUploadCoordinator? = nil,
        client: SecureMacUploadClient? = nil,
        deviceStatusSender: DeviceStatusSender? = nil,
        heartbeatRequestedSyncHandler: HeartbeatRequestedSyncHandler? = nil,
        localNetworkSyncClient: (any LocalNetworkSyncClientProtocol)? = nil,
        presenceHeartbeatClient: (any LocalNetworkHeartbeatClientProtocol)? = nil,
        statusStore: DeviceConnectionStatusStore? = nil,
        syncStateStore: StudyLibrarySyncStateStore? = nil,
        diagnosticsStore: ConnectionDiagnosticsStore? = nil,
        runtimeConfiguration: StudyLibrarySyncRuntimeConfiguration = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false),
        canonicalLibraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration = .disabled,
        canonicalRecordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)? = nil,
        canonicalGeneratedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)? = nil,
        canonicalLibraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)? = nil,
        canonicalTombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)? = nil,
        canonicalSyncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration = .disabled,
        canonicalApplyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration = .disabled,
        canonicalKernelSwitchResultProvider: (() -> CanonicalKernelSwitchResult)? = nil,
        canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime? = nil,
        canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime? = nil,
        canonicalConnectionRuntime: CanonicalConnectionRuntime? = nil,
        heartbeatInterval: TimeInterval = 3,
        syncInterval: TimeInterval = 240
    ) {
        let resolvedClient = client ?? SecureMacUploadClient()
        let resolvedStatusStore = statusStore ?? .shared
        let resolvedSyncStateStore = syncStateStore ?? StudyLibrarySyncStateStore()
        let resolvedDiagnosticsStore = diagnosticsStore ?? .shared
        let canonicalKernelSwitchResult = canonicalKernelSwitchResultProvider?()
        let resolvedStatusTruthRuntime = canonicalStatusTruthRuntime ?? CanonicalStatusTruthRuntime()
        let resolvedStatusExchangeRuntime = canonicalStatusExchangeRuntime ?? CanonicalStatusExchangeRuntime(
            nodeID: CanonicalNodeID("iphone-\(connectionStore.snapshot.deviceID)"),
            truthRuntime: resolvedStatusTruthRuntime
        )
        let resolvedConnectionRuntime = canonicalConnectionRuntime ?? CanonicalConnectionRuntime(
            configuration: canonicalKernelSwitchResult?.effectiveConfiguration.connectionRuntimeConfiguration ?? .disabled,
            localNode: CanonicalNodeIdentity(
                nodeID: CanonicalNodeID("iphone-\(connectionStore.snapshot.deviceID)"),
                role: .iPhone,
                displayName: UIDevice.current.name
            )
        )
        self.connectionStore = connectionStore
        self.studyLibraryStore = studyLibraryStore
        self.recordingManager = recordingManager
        self.uploadCoordinator = uploadCoordinator
        self.client = resolvedClient
        self.deviceStatusSender = deviceStatusSender ?? { settings, statusRequest in
            try await resolvedClient.sendDeviceStatus(settings: settings, statusRequest: statusRequest)
        }
        self.heartbeatRequestedSyncHandler = heartbeatRequestedSyncHandler
        self.localNetworkSyncClient = localNetworkSyncClient ?? resolvedClient
        self.statusStore = resolvedStatusStore
        self.syncStateStore = resolvedSyncStateStore
        self.runtimeConfiguration = runtimeConfiguration
        self.diagnosticsStore = resolvedDiagnosticsStore
        let productionPortInjection = canonicalKernelSwitchResult.map {
            IPhoneCanonicalProductionPortFactory.make(
                result: $0,
                productionRootURL: studyLibraryStore.libraryRootURL
            )
        }
        if let productionPortInjection {
            self.canonicalLibraryMetadataDebugPilotConfiguration = productionPortInjection.libraryMetadataDebugPilotConfiguration
            self.canonicalRecordingMetadataCutoverExecutor = productionPortInjection.recordingMetadataCutoverExecutor
            self.canonicalGeneratedArtifactCutoverExecutor = productionPortInjection.generatedArtifactCutoverExecutor
            self.canonicalLibraryMetadataCutoverExecutor = productionPortInjection.libraryMetadataCutoverExecutor
            self.canonicalTombstoneConflictCutoverExecutor = productionPortInjection.tombstoneConflictCutoverExecutor
        } else {
            self.canonicalLibraryMetadataDebugPilotConfiguration = canonicalLibraryMetadataDebugPilotConfiguration
            self.canonicalRecordingMetadataCutoverExecutor = canonicalRecordingMetadataCutoverExecutor
            self.canonicalGeneratedArtifactCutoverExecutor = canonicalGeneratedArtifactCutoverExecutor
            self.canonicalLibraryMetadataCutoverExecutor = canonicalLibraryMetadataCutoverExecutor
            self.canonicalTombstoneConflictCutoverExecutor = canonicalTombstoneConflictCutoverExecutor
        }
        self.canonicalSyncRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.syncRuntimeConfiguration ?? canonicalSyncRuntimeConfiguration
        self.canonicalApplyRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.applyRuntimeConfiguration ?? canonicalApplyRuntimeConfiguration
        self.canonicalKernelSwitchResultProvider = canonicalKernelSwitchResultProvider
        self.canonicalStatusTruthRuntime = resolvedStatusTruthRuntime
        self.canonicalStatusExchangeRuntime = resolvedStatusExchangeRuntime
        self.canonicalConnectionRuntime = resolvedConnectionRuntime
        self.presenceHeartbeatMonitor = LocalNetworkHeartbeatMonitor(
            connectionStore: connectionStore,
            client: presenceHeartbeatClient ?? resolvedClient,
            statusStore: resolvedStatusStore,
            diagnosticsStore: resolvedDiagnosticsStore,
            canonicalStatusExchangeRuntime: resolvedStatusExchangeRuntime,
            canonicalConnectionRuntime: resolvedConnectionRuntime
        )
        self.heartbeatInterval = heartbeatInterval
        self.syncInterval = syncInterval
        self.syncState = resolvedSyncStateStore.state
        self.connectionStatus = resolvedStatusStore.latestStatus ?? .unpaired(displayName: "Mac")
        self.statusStoreSubscription = resolvedStatusStore.$statusesByDeviceID
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshConnectionStatusFromStore()
                }
            }
        if let readRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.readRuntimeConfiguration {
            studyLibraryStore.setCanonicalReadRuntimeConfiguration(
                canonicalMasterSwitchReadConfigurationForStore(readRuntimeConfiguration)
            )
        }
    }

    var syncSummary: StudyLibrarySyncStatusSummary {
        StudyLibrarySyncStatusSummary(
            lastSyncAt: syncState.lastSuccessfulSyncAt,
            statusText: runtimeConfiguration.gitBackedSyncEnabled
                ? connectionStatus.lastSyncStatus ?? syncState.lastError
                : StudyLibrarySyncRuntimeConfiguration.disabledStatusText,
            pendingLocalChanges: syncState.pendingLocalChanges,
            pendingUploads: syncState.pendingUploads
        )
    }

    var canonicalStatusTruthReadPathAvailable: Bool {
        true
    }

    func produceCanonicalStatusFact(_ fact: CanonicalStatusFact) async -> CanonicalStatusFactMergeResult {
        let result = await canonicalStatusTruthRuntime.produce(fact)
        await bridgeCanonicalStatusProjections(
            for: [fact.objectID],
            deviceID: connectionStore.snapshot.deviceID,
            syncRunID: nil,
            source: "produceCanonicalStatusFact"
        )
        return result
    }

    func canonicalEffectiveStatus(for facts: [CanonicalStatusFact]) async -> CanonicalEffectiveSyncStatus {
        await canonicalStatusTruthRuntime.effectiveStatus(for: facts)
    }

    @discardableResult
    private func consumeCanonicalStatusExchangeEnvelope(
        _ envelope: CanonicalStatusExchangeEnvelope?,
        carrier: CanonicalStatusExchangeCarrier,
        deviceID: String,
        syncRunID: String?,
        source: String
    ) async -> CanonicalStatusExchangeReceiveResult {
        let result = await canonicalStatusExchangeRuntime.consumeIncomingEnvelope(envelope, carrier: carrier)
        guard envelope != nil else {
            return result
        }

        diagnosticsStore.record(
            phase: carrier == .heartbeat ? "statusEnvelopeCarriedOverHeartbeat" : "statusEnvelopeCarriedOverInventory",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: source
        )
        if envelope?.delta != nil {
            diagnosticsStore.record(
                phase: "statusDeltaReceived",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "facts=\(result.incorporatedFactCount),rejected=\(result.rejectedFactCount)"
            )
            await bridgeCanonicalStatusProjections(
                for: envelope?.delta?.facts.map(\.objectID) ?? [],
                deviceID: deviceID,
                syncRunID: syncRunID,
                source: source
            )
        }
        if envelope?.ack != nil {
            diagnosticsStore.record(
                phase: "statusAckReceived",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: envelope?.ack?.disposition.rawValue
            )
        }
        if envelope?.request != nil {
            diagnosticsStore.record(
                phase: "statusRequestReceived",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: envelope?.request?.kind.rawValue
            )
        }
        if !result.accepted || result.rejectedFactCount > 0 {
            diagnosticsStore.record(
                phase: "statusFactRejected",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: result.reason,
                errorCode: result.stale ? "stale_status_envelope" : "status_fact_rejected"
            )
        }

        for action in result.requestedActions {
            switch action {
            case .enqueueRunSyncSoon:
                handleHeartbeatSyncRequestedHint(syncRunID: syncRunID, hintReceivedAt: Date())
            case .requestLightweightAudioProof:
                diagnosticsStore.record(
                    phase: "peerProofUnavailable",
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "sendAudioProofRequestObserved"
                )
            case .requestFullInventory:
                diagnosticsStore.record(
                    phase: "fullInventoryRequested",
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "requestOnly"
                )
                handleHeartbeatSyncRequestedHint(syncRunID: syncRunID, hintReceivedAt: Date())
            }
        }
        return result
    }

    private func bridgeCanonicalStatusProjections(
        for objectIDs: [CanonicalObjectID],
        deviceID: String,
        syncRunID: String?,
        source: String
    ) async {
        let uniqueObjectIDs = Array(Set(objectIDs)).sorted()
        guard !uniqueObjectIDs.isEmpty else {
            return
        }
        var bridgedCount = 0
        for objectID in uniqueObjectIDs {
            guard let snapshot = await canonicalStatusTruthRuntime.projectionSnapshot(for: objectID) else {
                continue
            }
            studyLibraryStore.applyCanonicalStatusProjection(snapshot)
            uploadCoordinator?.applyCanonicalStatusProjection(snapshot)
            bridgedCount += 1
        }
        _ = (deviceID, syncRunID, source, bridgedCount)
    }

    var isAutomaticSyncMonitoringActive: Bool {
        heartbeatTask != nil || syncTask != nil
    }

    func startForegroundMonitoring() {
        refreshPairingState()
        heartbeatTask?.cancel()
        syncTask?.cancel()
        heartbeatTask = nil
        syncTask = nil

        guard userWantsConnection else {
            recordUserDisconnected()
            return
        }

        guard runtimeConfiguration.gitBackedSyncEnabled else {
            refreshConnectionStatusFromStore()
            return
        }

        heartbeatTask = Task { [weak self] in
            await self?.heartbeatLoop()
        }
        syncTask = Task { [weak self] in
            await self?.syncLoop()
        }
    }

    func stopMonitoring() {
        heartbeatTask?.cancel()
        syncTask?.cancel()
        heartbeatTask = nil
        syncTask = nil
    }

    func refreshPairingState() {
        let snapshot = connectionStore.snapshot
        syncState = syncStateStore.state
        guard snapshot.isPaired else {
            publishConnectionStatusIfChanged(statusStore.markUnpaired(displayName: "Mac"))
            return
        }
        guard userWantsConnection else {
            publishConnectionStatusIfChanged(statusStore.markUserDisconnected(
                deviceID: snapshot.deviceID,
                displayName: displayName(for: snapshot)
            ))
            return
        }

        refreshConnectionStatusFromStore()
    }

    func performHeartbeat() async {
        let snapshot = connectionStore.snapshot
        guard userWantsConnection else {
            recordUserDisconnected()
            return
        }
        guard runtimeConfiguration.gitBackedSyncEnabled else {
            recordDisabledStatus(for: snapshot)
            return
        }

        guard snapshot.isPaired else {
            failureCount = 0
            publishConnectionStatusIfChanged(statusStore.markUnpaired(displayName: "Mac"))
            return
        }

        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        let currentStatus = statusStore.status(for: snapshot.deviceID) ?? connectionStatus
        if currentStatus.state != .connected || currentStatus.presenceState != .online {
            publishConnectionStatusIfChanged(statusStore.markConnecting(deviceID: snapshot.deviceID, displayName: displayName))
        }

        do {
            let peerIdentity = Self.canonicalMacPeerIdentity(snapshot: snapshot, displayName: displayName)
            let connectionEnvelope = await canonicalConnectionRuntime.makeHeartbeatEnvelope(
                destinationNodeID: peerIdentity.nodeID,
                syncRequested: false
            )
            if connectionEnvelope != nil {
                diagnosticsStore.record(
                    phase: "canonicalConnectionHeartbeatEnvelopeBuilt",
                    deviceID: snapshot.deviceID,
                    result: "device-status"
                )
            }
            let outgoingEnvelope = await canonicalStatusExchangeRuntime.makeOutgoingEnvelope(
                carrier: .heartbeat
            )
            if outgoingEnvelope != nil {
                diagnosticsStore.record(
                    phase: "statusEnvelopeCarriedOverHeartbeat",
                    deviceID: snapshot.deviceID,
                    result: "device-status"
                )
                if outgoingEnvelope?.delta != nil {
                    diagnosticsStore.record(phase: "statusDeltaSent", deviceID: snapshot.deviceID, result: "device-status")
                }
                if outgoingEnvelope?.ack != nil {
                    diagnosticsStore.record(phase: "statusAckSent", deviceID: snapshot.deviceID, result: "device-status")
                }
                if outgoingEnvelope?.request != nil {
                    diagnosticsStore.record(phase: "statusRequestSent", deviceID: snapshot.deviceID, result: "device-status")
                }
            }
            let request = DeviceStatusRequest(
                displayName: UIDevice.current.name,
                clientState: UIApplication.shared.applicationState == .active ? "foreground" : "background",
                generatedAt: Date(),
                syncSummary: syncSummary,
                statusExchangeEnvelope: outgoingEnvelope
            )
            let response = try await deviceStatusSender(snapshot, request)
            guard response.ok else {
                throw SecureMacUploadError.serverRejected(response.error ?? "device_status_failed")
            }
            _ = await canonicalConnectionRuntime.recordHeartbeatAcknowledged(
                peer: peerIdentity,
                acknowledgedSequence: connectionEnvelope?.sequence ?? CanonicalSequence(),
                syncRequested: response.syncRequested == true || response.syncStartSignal != nil,
                observedAt: Date()
            )
            await consumeCanonicalStatusExchangeEnvelope(
                response.statusExchangeEnvelope,
                carrier: .heartbeat,
                deviceID: snapshot.deviceID,
                syncRunID: response.syncStartSignal?.syncRunID,
                source: "device-status"
            )

            failureCount = 0
            syncState = syncStateStore.state
            publishConnectionStatusIfChanged(statusStore.markConnected(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                lastSyncAt: syncState.lastSuccessfulSyncAt,
                lastSyncStatus: syncState.lastError ?? connectionStatus.lastSyncStatus
            ))
            if response.syncRequested || response.syncStartSignal != nil {
                handleHeartbeatSyncRequestedHint(
                    syncRunID: response.syncStartSignal?.syncRunID,
                    hintReceivedAt: Date()
                )
            }
        } catch {
            await canonicalConnectionRuntime.recordHeartbeatFailed(
                peer: Self.canonicalMacPeerIdentity(snapshot: snapshot, displayName: displayName),
                observedAt: Date()
            )
            failureCount += 1
            publishConnectionStatusIfChanged(statusStore.markOffline(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                error: error.localizedDescription
            ))
        }
    }

    @discardableResult
    func synchronizeNow() async -> StudyLibrarySyncApplyResult? {
        let snapshot = connectionStore.snapshot
        let perfStartedAt = Date()
        diagnosticsStore.recordPerfLog(
            CanonicalPerfLog.started(operation: .immediateSync),
            deviceID: snapshot.deviceID
        )
        defer {
            let totalMs = CanonicalPerfLog.elapsedMs(since: perfStartedAt)
            let stages = CanonicalPerfLog.StageDurations(waitBackgroundMs: totalMs)
            for record in CanonicalPerfLog.finishedRecords(
                operation: .immediateSync,
                totalMs: totalMs,
                stages: stages
            ) {
                diagnosticsStore.recordPerfLog(record, deviceID: snapshot.deviceID)
            }
        }
        diagnosticsStore.record(phase: "manualSyncTapped", deviceID: snapshot.deviceID)
        diagnosticsStore.record(phase: "manualSyncActionFired", deviceID: snapshot.deviceID)
        guard userWantsConnection else {
            recordUserDisconnected()
            diagnosticsStore.record(
                phase: "syncSkippedBecauseUserDoesNotWantConnection",
                deviceID: snapshot.deviceID
            )
            return nil
        }
        if snapshot.isPaired {
            let presence = statusStore.status(for: snapshot.deviceID)?.presenceSnapshot()
            diagnosticsStore.record(
                phase: "manualSyncPresenceSnapshot",
                deviceID: snapshot.deviceID,
                result: presence?.state.rawValue ?? "unknown"
            )
            if presence?.isOnline != true {
                diagnosticsStore.record(phase: "manualSyncTriggeredImmediateProbe", deviceID: snapshot.deviceID)
                let recovered = await presenceHeartbeatMonitor.requestImmediateProbe(reason: "manualSync")
                refreshConnectionStatusFromStore()
                guard recovered else {
                    diagnosticsStore.record(
                        phase: "manualSyncSkippedOffline",
                        deviceID: snapshot.deviceID,
                        errorCode: "presence_retry_failed"
                    )
                    return nil
                }
            }
        }

        guard runtimeConfiguration.gitBackedSyncEnabled else {
            return await performLocalNetworkManualSync(snapshot: snapshot)
        }

        return await performSync(trigger: "manual")
    }

    private func performLocalNetworkManualSync(snapshot: SecureMacConnectionSnapshot) async -> StudyLibrarySyncApplyResult? {
        guard let recordingManager, let uploadCoordinator else {
            diagnosticsStore.record(
                phase: "syncSkippedReason",
                deviceID: snapshot.deviceID,
                result: "local_network_executor_unavailable",
                errorCode: "local_network_executor_unavailable"
            )
            refreshConnectionStatusFromStore()
            return nil
        }

        guard !isSyncing else {
            pendingManualLocalNetworkSync = true
            diagnosticsStore.record(
                phase: "syncSkippedReason",
                deviceID: snapshot.deviceID,
                result: "alreadyInFlight queued",
                errorCode: "already_in_flight"
            )
            return nil
        }

        isSyncing = true
        defer {
            isSyncing = false
            syncState = syncStateStore.state
        }

        repeat {
            pendingManualLocalNetworkSync = false
            let audioFileStore = recordingManager.audioFileStore
            let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioFileStore)
            let syncRunID = UUID().uuidString
            refreshCanonicalKernelSwitchConfiguration(syncRunID: syncRunID)
            let engine = LocalNetworkSyncEngine(
                connectionStore: connectionStore,
                audioFileStore: audioFileStore,
                studyLibraryStore: studyLibraryStore,
                recordingManager: recordingManager,
                uploadCoordinator: uploadCoordinator,
                uploadJobStore: uploadJobStore,
                client: localNetworkSyncClient,
                connectionStatusStore: statusStore,
                diagnosticsStore: diagnosticsStore,
                canonicalLibraryMetadataDebugPilotConfiguration: canonicalLibraryMetadataDebugPilotConfiguration,
                canonicalSyncRuntimeConfiguration: canonicalSyncRuntimeConfiguration,
                canonicalApplyRuntimeConfiguration: canonicalApplyRuntimeConfiguration,
                canonicalKernelSwitchResultProvider: canonicalKernelSwitchResultProvider,
                canonicalStatusTruthRuntime: canonicalStatusTruthRuntime,
                canonicalStatusExchangeRuntime: canonicalStatusExchangeRuntime,
                canonicalRecordingMetadataCutoverExecutor: canonicalRecordingMetadataCutoverExecutor,
                canonicalGeneratedArtifactCutoverExecutor: canonicalGeneratedArtifactCutoverExecutor,
                canonicalLibraryMetadataCutoverExecutor: canonicalLibraryMetadataCutoverExecutor,
                canonicalTombstoneConflictCutoverExecutor: canonicalTombstoneConflictCutoverExecutor
            )
            syncStateStore.recordControlPlane(
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                state: .syncStartSignalSent
            )
            LocalNetworkSyncProgressStore.shared.record(
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                state: .syncStartSignalSent
            )
            diagnosticsStore.record(phase: "syncRunIDCreated", deviceID: snapshot.deviceID, syncRunID: syncRunID)
            diagnosticsStore.record(phase: "syncStartSignalSent", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: "manual")
            do {
                let response = try await localNetworkSyncClient.sendLocalNetworkSyncStartSignal(
                    settings: snapshot,
                    request: LocalNetworkSyncStartRequest(
                        syncRunID: syncRunID,
                        deviceID: snapshot.deviceID,
                        platform: .iPhone,
                        requestedAt: Date(),
                        reason: "manual"
                    )
                )
                guard response.ok, response.syncRunID == syncRunID else {
                    throw SecureMacUploadError.serverRejected(response.error ?? "sync_start_rejected")
                }
                syncStateStore.recordControlPlane(
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    state: .syncStartAcked
                )
                LocalNetworkSyncProgressStore.shared.record(
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    state: .syncStartAcked
                )
                diagnosticsStore.record(phase: "syncStartAckReceived", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: response.disposition)
            } catch {
                syncStateStore.recordControlPlane(
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    state: .failed
                )
                LocalNetworkSyncProgressStore.shared.record(
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    state: .failed
                )
                syncStateStore.recordFailure(deviceID: snapshot.deviceID, error: error.localizedDescription)
                diagnosticsStore.record(phase: "syncStartFailed", deviceID: snapshot.deviceID, syncRunID: syncRunID, errorCode: "sync_start_failed", errorMessage: error.localizedDescription)
                refreshConnectionStatusFromStore()
                return nil
            }
            let plan = await engine.performTick(trigger: "manual", bypassBackoff: true, syncRunID: syncRunID)
            syncStateStore.recordControlPlane(
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                state: plan == nil ? .failed : .completed
            )
            LocalNetworkSyncProgressStore.shared.record(
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                state: plan == nil ? .failed : .completed
            )
            refreshConnectionStatusFromStore()
        } while pendingManualLocalNetworkSync
        return nil
    }

    private func refreshCanonicalKernelSwitchConfiguration(syncRunID: String? = nil) {
        guard let canonicalKernelSwitchResultProvider else {
            return
        }
        let result = canonicalKernelSwitchResultProvider()
        canonicalSyncRuntimeConfiguration = result.effectiveConfiguration.syncRuntimeConfiguration
        canonicalApplyRuntimeConfiguration = result.effectiveConfiguration.applyRuntimeConfiguration
        let productionPortInjection = IPhoneCanonicalProductionPortFactory.make(
            result: result,
            productionRootURL: studyLibraryStore.libraryRootURL
        )
        canonicalLibraryMetadataDebugPilotConfiguration = productionPortInjection.libraryMetadataDebugPilotConfiguration
        canonicalRecordingMetadataCutoverExecutor = productionPortInjection.recordingMetadataCutoverExecutor
        canonicalGeneratedArtifactCutoverExecutor = productionPortInjection.generatedArtifactCutoverExecutor
        canonicalLibraryMetadataCutoverExecutor = productionPortInjection.libraryMetadataCutoverExecutor
        canonicalTombstoneConflictCutoverExecutor = productionPortInjection.tombstoneConflictCutoverExecutor
        studyLibraryStore.setCanonicalReadRuntimeConfiguration(
            canonicalMasterSwitchReadConfigurationForStore(result.effectiveConfiguration.readRuntimeConfiguration)
        )
        diagnosticsStore.record(
            phase: "canonicalKernelSwitchEvaluated",
            deviceID: connectionStore.snapshot.deviceID,
            syncRunID: syncRunID,
            result: result.diagnosticsSummary,
            errorCode: result.isBlocked ? "canonical_kernel_switch_blocked" : nil
        )
    }

    private func handleHeartbeatSyncRequestedHint(
        syncRunID: String?,
        hintReceivedAt: Date,
        now: Date = Date()
    ) {
        let snapshot = connectionStore.snapshot
        diagnosticsStore.record(
            phase: "heartbeatSyncRequestedHintReceived",
            deviceID: snapshot.deviceID,
            syncRunID: syncRunID,
            result: "device-status"
        )
        diagnosticsStore.record(
            phase: "syncRequestedHintReceived",
            deviceID: snapshot.deviceID,
            syncRunID: syncRunID,
            result: "device-status"
        )

        guard snapshot.isPaired else {
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedHintIgnoredNoPeer",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                errorCode: "not_paired"
            )
            return
        }
        guard userWantsConnection else {
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedHintIgnoredDisconnected",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                errorCode: "user_does_not_want_connection"
            )
            return
        }
        if UIApplication.shared.applicationState == .background {
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedTickDeferredBackground",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                errorCode: "app_background"
            )
            return
        }
        if let presence = statusStore.status(for: snapshot.deviceID, now: now)?.presenceSnapshot(now: now),
           !presence.isOnline {
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedTickDeferredOffline",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: presence.state.rawValue,
                errorCode: "presence_not_online"
            )
            return
        }
        if pendingHeartbeatRequestedSync != nil {
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedTickAlreadyPending",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "immediateSyncDedupedCount=1",
                errorCode: "already_pending"
            )
            return
        }
        if let lastQueuedAt = lastHeartbeatRequestedSyncQueuedAt,
           now.timeIntervalSince(lastQueuedAt) < heartbeatRequestedSyncDebounceInterval {
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedTickDebounced",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "immediateSyncDedupedCount=1",
                errorCode: "debounced"
            )
            return
        }
        if let lastCompletedAt = lastHeartbeatRequestedSyncCompletedAt,
           now.timeIntervalSince(lastCompletedAt) < heartbeatRequestedSyncDebounceInterval {
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedTickDebounced",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "immediateSyncDedupedCount=1",
                errorCode: "recently_completed"
            )
            return
        }

        pendingHeartbeatRequestedSync = (syncRunID, hintReceivedAt)
        lastHeartbeatRequestedSyncQueuedAt = now
        diagnosticsStore.record(
            phase: isSyncing ? "heartbeatSyncRequestedTickAlreadyRunning" : "heartbeatSyncRequestedTickQueued",
            deviceID: snapshot.deviceID,
            syncRunID: syncRunID,
            result: "immediateSyncQueuedCount=1"
        )
        if isSyncing {
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedTickQueued",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "pendingAfterCurrentRun"
            )
        }
        scheduleHeartbeatRequestedSyncDrainIfNeeded()
    }

    private func scheduleHeartbeatRequestedSyncDrainIfNeeded() {
        guard heartbeatRequestedSyncTask == nil else {
            return
        }
        heartbeatRequestedSyncTask = Task { @MainActor [weak self] in
            await self?.drainHeartbeatRequestedSyncQueue()
        }
    }

    private func drainHeartbeatRequestedSyncQueue() async {
        defer { heartbeatRequestedSyncTask = nil }
        while let request = pendingHeartbeatRequestedSync {
            if isSyncing {
                diagnosticsStore.record(
                    phase: "heartbeatSyncRequestedTickAlreadyRunning",
                    deviceID: connectionStore.snapshot.deviceID,
                    syncRunID: request.syncRunID,
                    result: "pendingAfterCurrentRun",
                    errorCode: "already_running"
                )
                try? await Task.sleep(nanoseconds: 250_000_000)
                continue
            }

            pendingHeartbeatRequestedSync = nil
            let startedAt = Date()
            let latencyMs = max(0, startedAt.timeIntervalSince(request.hintedAt) * 1_000)
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedTickStarted",
                deviceID: connectionStore.snapshot.deviceID,
                syncRunID: request.syncRunID,
                result: "immediateSyncStartedCount=1",
                latencyMs: latencyMs
            )
            let completedAt = Date()
            let succeeded = await runHeartbeatRequestedSync(syncRunID: request.syncRunID)
            let finishedAt = Date()
            let durationMs = max(0, finishedAt.timeIntervalSince(completedAt) * 1_000)
            if succeeded {
                lastHeartbeatRequestedSyncCompletedAt = finishedAt
                diagnosticsStore.record(
                    phase: "heartbeatSyncRequestedTickCompleted",
                    deviceID: connectionStore.snapshot.deviceID,
                    syncRunID: request.syncRunID,
                    result: "immediateSyncCompletedCount=1,immediateSyncDurationMs=\(Int(durationMs))",
                    latencyMs: durationMs
                )
            } else {
                diagnosticsStore.record(
                    phase: "heartbeatSyncRequestedTickFailed",
                    deviceID: connectionStore.snapshot.deviceID,
                    syncRunID: request.syncRunID,
                    result: "immediateSyncFailedCount=1,immediateSyncDurationMs=\(Int(durationMs))",
                    latencyMs: durationMs,
                    errorCode: "immediate_sync_failed"
                )
            }
        }
    }

    private func runHeartbeatRequestedSync(syncRunID: String?) async -> Bool {
        if let heartbeatRequestedSyncHandler {
            return await heartbeatRequestedSyncHandler(syncRunID)
        }
        if runtimeConfiguration.gitBackedSyncEnabled {
            return await performSync(trigger: "manual-sync-requested") != nil
        }
        let snapshot = connectionStore.snapshot
        guard recordingManager != nil, uploadCoordinator != nil else {
            diagnosticsStore.record(
                phase: "heartbeatSyncRequestedTickFailed",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                errorCode: "local_network_executor_unavailable"
            )
            return false
        }
        _ = await performLocalNetworkManualSync(snapshot: snapshot)
        return true
    }

    func recordSignedRequestSucceeded(settings: SecureMacConnectionSnapshot, now: Date = Date()) {
        guard settings.isPaired else {
            return
        }

        _ = statusStore.recordSignedRequestSucceeded(
            deviceID: settings.deviceID,
            displayName: settings.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : settings.macName,
            now: now
        )
        diagnosticsStore.record(phase: "signedRequestRefreshedLastSeen", deviceID: settings.deviceID)
        refreshConnectionStatusFromStore(now: now)
    }

    func recordUserDisconnected(now: Date = Date()) {
        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            publishConnectionStatusIfChanged(statusStore.markUnpaired(displayName: "Mac"))
            return
        }
        publishConnectionStatusIfChanged(statusStore.markUserDisconnected(
            deviceID: snapshot.deviceID,
            displayName: displayName(for: snapshot),
            now: now
        ))
        diagnosticsStore.record(
            phase: "heartbeatSuppressedBecauseUserDoesNotWantConnection",
            deviceID: snapshot.deviceID,
            timestamp: now
        )
    }

    private func heartbeatLoop() async {
        guard runtimeConfiguration.gitBackedSyncEnabled else {
            return
        }

        while !Task.isCancelled {
            await performHeartbeat()
            await sleep(seconds: nextHeartbeatDelay())
        }
    }

    private func syncLoop() async {
        guard runtimeConfiguration.gitBackedSyncEnabled else {
            return
        }

        await sleep(seconds: 30)
        while !Task.isCancelled {
            _ = await performSync(trigger: "timer")
            await sleep(seconds: syncInterval)
        }
    }

    @discardableResult
    private func performSync(trigger: String) async -> StudyLibrarySyncApplyResult? {
        guard runtimeConfiguration.gitBackedSyncEnabled else {
            recordDisabledStatusForCurrentPairing()
            return nil
        }

        guard !shouldDeferSyncBecauseUploadActive(trigger: trigger) else {
            return nil
        }

        guard !isSyncing else {
            return nil
        }

        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            publishConnectionStatusIfChanged(statusStore.markUnpaired(displayName: "Mac"))
            return nil
        }

        isSyncing = true
        defer {
            isSyncing = false
            syncState = syncStateStore.state
        }

        let syncRunID = UUID().uuidString
        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        do {
            if trigger == "manual" {
                diagnosticsStore.record(phase: "manualSyncStarted", deviceID: snapshot.deviceID)
            }
            LocalNetworkSyncProgressStore.shared.record(
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                state: .inventoryExchanging
            )
            let remoteResponse = try await client.fetchStudyLibraryManifest(settings: snapshot)
            guard remoteResponse.ok, let remoteManifest = remoteResponse.manifest else {
                throw SecureMacUploadError.serverRejected(remoteResponse.error ?? "sync_manifest_missing")
            }

            LocalNetworkSyncProgressStore.shared.record(
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                state: .planningTransfers
            )
            let pullResult = try await studyLibraryStore.applySyncManifest(remoteManifest, localDeviceID: snapshot.deviceID)
            syncStateStore.recordPull(
                deviceID: snapshot.deviceID,
                remoteManifestHash: remoteManifest.checksum,
                remoteCommitID: remoteManifest.commitID ?? remoteResponse.newCommitID
            )

            let skippedUploadCount = remoteManifest.pendingUploads.filter { $0.status != .uploaded }.count
            let uploadResult = PendingUploadProcessingResult(remainingCount: skippedUploadCount)
            if skippedUploadCount > 0 {
                diagnosticsStore.record(
                    phase: "contentTransferSkippedForStructureSync",
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    result: "pendingRecordingUploads:\(skippedUploadCount)"
                )
            }
            LocalNetworkSyncProgressStore.shared.record(
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                state: .transferring
            )
            var localManifest = await studyLibraryStore.makeSyncManifestInBackground(deviceID: snapshot.deviceID)
            localManifest.baseCommitID = syncStateStore.state.lastKnownRemoteCommitID ?? remoteManifest.commitID ?? remoteResponse.newCommitID
            localManifest.localManifestHash = localManifest.checksum
            let applyResponse = try await client.applyStudyLibraryManifest(settings: snapshot, manifest: localManifest)
            guard applyResponse.ok else {
                throw SecureMacUploadError.serverRejected(applyResponse.error ?? "sync_apply_failed")
            }

            if let returnedManifest = applyResponse.manifest,
               returnedManifest.checksum != remoteManifest.checksum {
                _ = try? await studyLibraryStore.applySyncManifest(returnedManifest, localDeviceID: snapshot.deviceID)
            }

            let summary = Self.syncSummaryText(
                syncSummary: applyResponse.applyResult?.summaryText ?? pullResult.summaryText,
                uploadResult: uploadResult
            )
            syncStateStore.recordPush(
                deviceID: snapshot.deviceID,
                remoteManifestHash: remoteManifest.checksum,
                remoteCommitID: applyResponse.newCommitID ?? applyResponse.manifest?.commitID,
                pendingUploads: uploadResult.remainingCount
            )
            syncState = syncStateStore.state
            publishConnectionStatusIfChanged(statusStore.recordSyncResult(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                statusText: trigger == "manual" ? "手动同步完成：\(summary)" : summary
            ))
            if trigger == "manual" {
                diagnosticsStore.record(phase: "manualSyncSucceededRefreshSignedRequest", deviceID: snapshot.deviceID)
            }
            LocalNetworkSyncProgressStore.shared.record(
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                state: .completed
            )
            return applyResponse.applyResult ?? pullResult
        } catch {
            syncStateStore.recordFailure(deviceID: snapshot.deviceID, error: error.localizedDescription)
            publishConnectionStatusIfChanged(statusStore.recordSyncStatus(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                statusText: "同步失败"
            ))
            LocalNetworkSyncProgressStore.shared.record(
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                state: .failed
            )
            if trigger == "manual" {
                diagnosticsStore.record(
                    phase: "manualSyncFailedButPresenceUnchanged",
                    deviceID: snapshot.deviceID,
                    errorCode: "sync_failed",
                    errorMessage: error.localizedDescription
                )
            }
            return nil
        }
    }

    private func processPendingRecordingUploads(
        remoteManifest: StudyLibrarySyncManifest,
        settings: SecureMacConnectionSnapshot
    ) async -> PendingUploadProcessingResult {
        guard runtimeConfiguration.gitBackedSyncEnabled else {
            return PendingUploadProcessingResult()
        }

        guard settings.isPaired,
              let recordingManager,
              let uploadCoordinator else {
            return PendingUploadProcessingResult()
        }

        recordingManager.reloadRecordings()
        let candidates = pendingUploadCandidates(remoteManifest: remoteManifest, recordingManager: recordingManager)
        guard !candidates.isEmpty else {
            syncStateStore.recordPendingUploads(deviceID: settings.deviceID, pendingUploads: 0)
            return PendingUploadProcessingResult()
        }

        var result = PendingUploadProcessingResult(remainingCount: candidates.count)
        syncStateStore.recordPendingUploads(deviceID: settings.deviceID, pendingUploads: candidates.count)

        for candidate in candidates {
            result.attemptedCount += 1
            let status = await uploadCoordinator.uploadAndWait(
                metadata: candidate,
                settings: settings,
                recordingManager: recordingManager
            )
            switch status {
            case .uploaded:
                result.succeededCount += 1
            case .failed:
                result.failedCount += 1
            case .localOnly, .uploading:
                result.remainingCount += 1
            }
        }

        recordingManager.reloadRecordings()
        result.remainingCount = pendingUploadCandidates(remoteManifest: remoteManifest, recordingManager: recordingManager).count
        syncStateStore.recordPendingUploads(
            deviceID: settings.deviceID,
            pendingUploads: result.remainingCount,
            failedChanges: result.failedCount,
            error: result.failedCount > 0 ? "pending_upload_failed" : nil
        )
        return result
    }

    private func pendingUploadCandidates(
        remoteManifest: StudyLibrarySyncManifest,
        recordingManager: RecordingManager
    ) -> [RecordingMetadata] {
        let remoteItemsByRecordingID = Dictionary(
            remoteManifest.items.compactMap { item -> (String, StudyItemMetadata)? in
                guard let recordingID = item.recordingID else {
                    return nil
                }
                return (recordingID, item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        return recordingManager.recordings.filter { recording in
            guard !recording.isDeleted else {
                return false
            }

            guard let remoteItem = remoteItemsByRecordingID[recording.id] else {
                return RecordingUploadStatus(rawMetadataValue: recording.uploadStatus) != .uploaded
            }

            if remoteItem.audioRelativePath == nil
                || remoteItem.customProperties["syncedMetadataOnly"] == "true" {
                return true
            }

            return RecordingUploadStatus(rawMetadataValue: recording.uploadStatus) != .uploaded
        }
    }

    private static func syncSummaryText(
        syncSummary: String,
        uploadResult: PendingUploadProcessingResult
    ) -> String {
        guard uploadResult.attemptedCount > 0 else {
            return syncSummary
        }

        var parts = [syncSummary, "上传 \(uploadResult.succeededCount)/\(uploadResult.attemptedCount)"]
        if uploadResult.remainingCount > 0 {
            parts.append("待上传 \(uploadResult.remainingCount)")
        }
        return parts.joined(separator: " · ")
    }

    private func nextHeartbeatDelay() -> TimeInterval {
        guard failureCount > 0 else {
            return heartbeatInterval
        }

        let multiplier = min(pow(2, Double(failureCount - 1)), 12)
        return min(heartbeatInterval * multiplier, 60)
    }

    private func recordDisabledStatusForCurrentPairing() {
        recordDisabledStatus(for: connectionStore.snapshot)
    }

    private func publishConnectionStatusIfChanged(_ status: DeviceConnectionStatus) {
        guard !connectionStatus.isPublishEquivalent(to: status) else {
            return
        }
        connectionStatus = status
    }

    private func shouldDeferSyncBecauseUploadActive(trigger: String, syncRunID: String? = nil) -> Bool {
        guard uploadCoordinator?.hasActiveUploadInFlight() == true else {
            return false
        }
        diagnosticsStore.record(
            phase: "syncDeferredBecauseUploadActive",
            deviceID: connectionStore.snapshot.deviceID,
            syncRunID: syncRunID,
            result: "trigger=\(trigger)",
            errorCode: "upload_active"
        )
        return true
    }

    private func recordDisabledStatus(for snapshot: SecureMacConnectionSnapshot) {
        syncState = syncStateStore.state
        guard snapshot.isPaired else {
            failureCount = 0
            publishConnectionStatusIfChanged(statusStore.markUnpaired(displayName: "Mac"))
            return
        }
        guard userWantsConnection else {
            publishConnectionStatusIfChanged(statusStore.markUserDisconnected(
                deviceID: snapshot.deviceID,
                displayName: displayName(for: snapshot)
            ))
            return
        }

        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        publishConnectionStatusIfChanged(statusStore.recordSyncStatus(
            deviceID: snapshot.deviceID,
            displayName: displayName,
            statusText: StudyLibrarySyncRuntimeConfiguration.disabledStatusText
        ))
    }

    private func refreshConnectionStatusFromStore(now: Date = Date()) {
        let snapshot = connectionStore.snapshot
        syncState = syncStateStore.state
        guard snapshot.isPaired else {
            publishConnectionStatusIfChanged(statusStore.markUnpaired(displayName: "Mac"))
            return
        }
        guard userWantsConnection else {
            publishConnectionStatusIfChanged(statusStore.markUserDisconnected(
                deviceID: snapshot.deviceID,
                displayName: displayName(for: snapshot),
                now: now
            ))
            return
        }

        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        publishConnectionStatusIfChanged(statusStore.status(for: snapshot.deviceID, now: now)
            ?? DeviceConnectionStatus(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                state: .offline,
                lastSeenAt: nil,
                lastHeartbeatAt: nil,
                lastSyncAt: syncState.lastSuccessfulSyncAt,
                lastSyncStatus: runtimeConfiguration.gitBackedSyncEnabled
                    ? syncState.lastError ?? "待同步"
                    : StudyLibrarySyncRuntimeConfiguration.disabledStatusText,
                lastError: nil,
                presenceState: .unknown,
                monitoringMode: runtimeConfiguration.gitBackedSyncEnabled ? .foregroundActive : .disabled,
                lastHeartbeatSentAt: nil,
                lastHeartbeatReceivedAt: nil,
                lastSuccessfulHeartbeatAt: nil,
                lastSignedRequestSucceededAt: nil,
                missedHeartbeatCount: 0,
                consecutiveFailureCount: 0,
                latencyMilliseconds: nil,
                lastErrorCode: nil,
                connectionStatusRevision: 0
            ))
    }

    private func sleep(seconds: TimeInterval) async {
        let nanoseconds = UInt64(max(0.1, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private var userWantsConnection: Bool {
        (connectionStore as? SecureMacConnectionIntentProviding)?.userConnectionIntent != .disconnectedByUser
    }

    private func displayName(for snapshot: SecureMacConnectionSnapshot) -> String {
        snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
    }

    private static func canonicalMacPeerIdentity(
        snapshot: SecureMacConnectionSnapshot,
        displayName: String
    ) -> CanonicalNodeIdentity {
        CanonicalNodeIdentity(
            nodeID: CanonicalNodeID("mac-\(snapshot.deviceID)"),
            role: .mac,
            displayName: displayName
        )
    }
}

private extension DeviceConnectionStatus {
    func isPublishEquivalent(to other: DeviceConnectionStatus) -> Bool {
        deviceID == other.deviceID
            && displayName == other.displayName
            && state == other.state
            && lastSyncAt == other.lastSyncAt
            && lastSyncStatus == other.lastSyncStatus
            && lastError == other.lastError
            && presenceState == other.presenceState
            && monitoringMode == other.monitoringMode
            && missedHeartbeatCount == other.missedHeartbeatCount
            && consecutiveFailureCount == other.consecutiveFailureCount
            && lastErrorCode == other.lastErrorCode
    }
}

private struct PendingUploadProcessingResult {
    var attemptedCount = 0
    var succeededCount = 0
    var failedCount = 0
    var remainingCount = 0
}

protocol LocalNetworkSyncClientProtocol {
    func sendDeviceStatus(settings: SecureMacConnectionSnapshot, statusRequest: DeviceStatusRequest) async throws -> DeviceStatusResponse
    func fetchLocalNetworkSyncInventory(settings: SecureMacConnectionSnapshot, localInventory: LocalNetworkSyncInventory, syncRunID: String?) async throws -> LocalNetworkSyncInventoryResponse
    func sendLocalNetworkSyncStartSignal(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncStartRequest) async throws -> LocalNetworkSyncStartResponse
    func sendLocalNetworkSyncStartAck(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncStartAckRequest) async throws -> LocalNetworkSyncStartAckResponse
    func applyLocalNetworkSyncMetadata(settings: SecureMacConnectionSnapshot, manifest: StudyLibrarySyncManifest) async throws -> StudyLibrarySyncManifestResponse
    func requestLocalNetworkSyncArtifact(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactRequest) async throws -> LocalNetworkSyncArtifactResponse
    func fetchLocalNetworkSyncArtifactStatus(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactStatusRequest) async throws -> LocalNetworkSyncArtifactStatusResponse
    func putLocalNetworkSyncArtifact(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactPutRequest) async throws -> LocalNetworkSyncArtifactPutResponse
}

extension LocalNetworkSyncClientProtocol {
    func fetchLocalNetworkSyncInventory(
        settings: SecureMacConnectionSnapshot,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String?,
        statusExchangeEnvelope: CanonicalStatusExchangeEnvelope?
    ) async throws -> LocalNetworkSyncInventoryResponse {
        try await fetchLocalNetworkSyncInventory(
            settings: settings,
            localInventory: localInventory,
            syncRunID: syncRunID
        )
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        artifactID: String
    ) async throws -> LocalNetworkSyncArtifactResponse {
        try await requestLocalNetworkSyncArtifact(
            settings: settings,
            request: LocalNetworkSyncArtifactRequest(artifactID: artifactID)
        )
    }
}

extension SecureMacUploadClient: LocalNetworkSyncClientProtocol {}

protocol LocalNetworkHeartbeatClientProtocol {
    func sendConnectionHeartbeat(
        settings: SecureMacConnectionSnapshot,
        request: ConnectionHeartbeatRequest,
        requestTimeout: TimeInterval
    ) async throws -> ConnectionHeartbeatResponse
    func sendLocalNetworkSyncStartAck(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartAckRequest
    ) async throws -> LocalNetworkSyncStartAckResponse
}

extension LocalNetworkHeartbeatClientProtocol {
    func sendLocalNetworkSyncStartAck(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartAckRequest
    ) async throws -> LocalNetworkSyncStartAckResponse {
        LocalNetworkSyncStartAckResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: settings.deviceID,
            ackReceivedAt: Date(),
            error: nil
        )
    }
}

extension SecureMacUploadClient: LocalNetworkHeartbeatClientProtocol {}

struct LocalNetworkHeartbeatConfiguration: Equatable {
    var heartbeatInterval: TimeInterval
    var requestTimeout: TimeInterval
    var missedHeartbeatLimit: Int
    var staleAfter: TimeInterval
    var disconnectedAfter: TimeInterval

    static let foregroundDefault = LocalNetworkHeartbeatConfiguration(
        heartbeatInterval: 3,
        requestTimeout: 2,
        missedHeartbeatLimit: 3,
        staleAfter: 5,
        disconnectedAfter: 10
    )
}

@MainActor
final class LocalNetworkHeartbeatMonitor: ObservableObject {
    private let connectionStore: any SecureMacConnectionSnapshotProviding
    private let client: any LocalNetworkHeartbeatClientProtocol
    private let statusStore: DeviceConnectionStatusStore
    private let diagnosticsStore: ConnectionDiagnosticsStore
    private let configuration: LocalNetworkHeartbeatConfiguration
    private let canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime?
    private let canonicalConnectionRuntime: CanonicalConnectionRuntime?
    private var heartbeatTask: Task<Void, Never>?
    private var sequenceNumber: UInt64 = 0
    private(set) var isHeartbeatInFlight = false
    var onSyncRequested: ((String?) -> Void)?

    init(
        connectionStore: any SecureMacConnectionSnapshotProviding,
        client: (any LocalNetworkHeartbeatClientProtocol)? = nil,
        statusStore: DeviceConnectionStatusStore? = nil,
        diagnosticsStore: ConnectionDiagnosticsStore? = nil,
        configuration: LocalNetworkHeartbeatConfiguration = .foregroundDefault,
        canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime? = nil,
        canonicalConnectionRuntime: CanonicalConnectionRuntime? = nil
    ) {
        self.connectionStore = connectionStore
        self.client = client ?? SecureMacUploadClient()
        self.statusStore = statusStore ?? .shared
        self.diagnosticsStore = diagnosticsStore ?? .shared
        self.configuration = configuration
        self.canonicalStatusExchangeRuntime = canonicalStatusExchangeRuntime
        self.canonicalConnectionRuntime = canonicalConnectionRuntime
    }

    var isMonitoring: Bool {
        heartbeatTask != nil
    }

    @discardableResult
    func startForegroundMonitoring() -> Bool {
        let snapshot = connectionStore.snapshot
        diagnosticsStore.record(phase: "heartbeatMonitorResumeRequested", deviceID: snapshot.deviceID)

        guard userWantsConnection else {
            stopBecauseUserDoesNotWantConnection()
            return false
        }

        guard heartbeatTask == nil else {
            Task { [weak self] in
                await self?.requestImmediateProbe(reason: "foregroundResume")
            }
            return true
        }

        guard snapshot.isPaired else {
            _ = statusStore.markUnpaired(displayName: "Mac")
            return false
        }

        _ = statusStore.markMonitoringResumed(
            deviceID: snapshot.deviceID,
            displayName: displayName(for: snapshot)
        )
        diagnosticsStore.record(phase: "heartbeatMonitorStart", deviceID: snapshot.deviceID)
        heartbeatTask = Task { [weak self] in
            var isFirstTick = true
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                if isFirstTick {
                    self.diagnosticsStore.record(phase: "heartbeatImmediateProbeStarted", deviceID: self.connectionStore.snapshot.deviceID)
                }
                self.diagnosticsStore.record(phase: "heartbeatTickScheduled", deviceID: self.connectionStore.snapshot.deviceID)
                let succeeded = await self.performHeartbeat()
                if isFirstTick {
                    self.diagnosticsStore.record(
                        phase: succeeded ? "heartbeatImmediateProbeSucceeded" : "heartbeatImmediateProbeFailed",
                        deviceID: self.connectionStore.snapshot.deviceID
                    )
                    isFirstTick = false
                }
                try? await Task.sleep(nanoseconds: UInt64(self.configuration.heartbeatInterval * 1_000_000_000))
            }
        }
        return true
    }

    func suspend() {
        heartbeatTask?.cancel()
        heartbeatTask = nil

        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            _ = statusStore.markUnpaired(displayName: "Mac")
            return
        }

        guard userWantsConnection else {
            _ = statusStore.markUserDisconnected(
                deviceID: snapshot.deviceID,
                displayName: displayName(for: snapshot)
            )
            diagnosticsStore.record(
                phase: "heartbeatSuppressedBecauseUserDoesNotWantConnection",
                deviceID: snapshot.deviceID
            )
            return
        }

        diagnosticsStore.record(phase: "heartbeatMonitorStop", deviceID: snapshot.deviceID)
        let status = statusStore.markMonitoringSuspended(
            deviceID: snapshot.deviceID,
            displayName: displayName(for: snapshot)
        )
        diagnosticsStore.record(phase: "heartbeatMarkedStale", deviceID: snapshot.deviceID, heartbeatMissCount: status.missedHeartbeatCount)
    }

    @discardableResult
    func performHeartbeat(now: Date = Date()) async -> Bool {
        guard !isHeartbeatInFlight else {
            diagnosticsStore.record(
                phase: "heartbeatTickSkippedReason",
                deviceID: connectionStore.snapshot.deviceID,
                errorCode: "heartbeat_in_flight"
            )
            return false
        }

        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            _ = statusStore.markUnpaired(displayName: "Mac")
            return false
        }
        guard userWantsConnection else {
            _ = statusStore.markUserDisconnected(
                deviceID: snapshot.deviceID,
                displayName: displayName(for: snapshot),
                now: now
            )
            diagnosticsStore.record(
                phase: "heartbeatSuppressedBecauseUserDoesNotWantConnection",
                deviceID: snapshot.deviceID,
                timestamp: now
            )
            return false
        }

        isHeartbeatInFlight = true
        defer { isHeartbeatInFlight = false }

        let displayName = displayName(for: snapshot)
        let peerIdentity = Self.canonicalMacPeerIdentity(snapshot: snapshot, displayName: displayName)
        sequenceNumber += 1
        let requestSequence = sequenceNumber
        let statusBeforeSend = statusStore.status(for: snapshot.deviceID, now: now)
        _ = statusStore.markHeartbeatSent(deviceID: snapshot.deviceID, displayName: displayName, now: now)
        diagnosticsStore.record(
            phase: "heartbeatRequestStarted",
            deviceID: snapshot.deviceID,
            heartbeatSequence: requestSequence,
            requestStartedAt: now,
            requestPath: "/connection/heartbeat",
            heartbeatMissCount: statusBeforeSend?.missedHeartbeatCount
        )
        let outgoingEnvelope = await canonicalStatusExchangeRuntime?.makeOutgoingEnvelope(
            carrier: .heartbeat
        )
        let connectionEnvelope = await canonicalConnectionRuntime?.makeHeartbeatEnvelope(
            destinationNodeID: peerIdentity.nodeID,
            syncRequested: false,
            now: now
        )
        if connectionEnvelope != nil {
            diagnosticsStore.record(
                phase: "canonicalConnectionHeartbeatEnvelopeBuilt",
                deviceID: snapshot.deviceID,
                heartbeatSequence: requestSequence,
                requestPath: "/connection/heartbeat",
                result: "connection-heartbeat"
            )
        }
        if outgoingEnvelope != nil {
            diagnosticsStore.record(
                phase: "statusEnvelopeCarriedOverHeartbeat",
                deviceID: snapshot.deviceID,
                heartbeatSequence: requestSequence,
                requestPath: "/connection/heartbeat",
                result: "connection-heartbeat"
            )
            if outgoingEnvelope?.delta != nil {
                diagnosticsStore.record(phase: "statusDeltaSent", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, requestPath: "/connection/heartbeat")
            }
            if outgoingEnvelope?.ack != nil {
                diagnosticsStore.record(phase: "statusAckSent", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, requestPath: "/connection/heartbeat")
            }
            if outgoingEnvelope?.request != nil {
                diagnosticsStore.record(phase: "statusRequestSent", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, requestPath: "/connection/heartbeat")
            }
        }
        let request = ConnectionHeartbeatRequest(
            deviceID: snapshot.deviceID,
            deviceName: UIDevice.current.name,
            platform: .iPhone,
            appInstanceID: nil,
            sequenceNumber: requestSequence,
            sentAt: now,
            lastKnownPeerStatusRevision: statusBeforeSend?.connectionStatusRevision,
            statusExchangeEnvelope: outgoingEnvelope
        )

        do {
            let response = try await client.sendConnectionHeartbeat(
                settings: snapshot,
                request: request,
                requestTimeout: configuration.requestTimeout
            )
            guard response.ok, response.receivedSequenceNumber == request.sequenceNumber else {
                throw SecureMacUploadError.serverRejected(response.error ?? "heartbeat_rejected")
            }
            let receivedAt = Date()
            _ = await canonicalConnectionRuntime?.recordHeartbeatAcknowledged(
                peer: peerIdentity,
                acknowledgedSequence: CanonicalSequence(response.receivedSequenceNumber),
                syncRequested: response.syncRequested == true || response.syncStartSignal != nil,
                observedAt: receivedAt
            )
            let latencyMilliseconds = max(0, receivedAt.timeIntervalSince(now) * 1_000)
            let status = statusStore.recordHeartbeatSuccess(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                sentAt: now,
                receivedAt: receivedAt,
                latencyMilliseconds: latencyMilliseconds
            )
            diagnosticsStore.record(
                phase: "heartbeatResponseReceived",
                deviceID: snapshot.deviceID,
                heartbeatSequence: requestSequence,
                requestStartedAt: now,
                requestPath: "/connection/heartbeat",
                responseReceivedAt: receivedAt,
                responseSequence: response.receivedSequenceNumber,
                result: "online",
                latencyMs: latencyMilliseconds
            )
            diagnosticsStore.record(
                phase: "heartbeatMarkedOnline",
                deviceID: snapshot.deviceID,
                heartbeatSequence: requestSequence,
                responseSequence: response.receivedSequenceNumber,
                result: "online",
                latencyMs: latencyMilliseconds,
                heartbeatMissCount: status.missedHeartbeatCount
            )
            if let statusExchangeEnvelope = response.statusExchangeEnvelope {
                let exchangeResult = await canonicalStatusExchangeRuntime?.consumeIncomingEnvelope(statusExchangeEnvelope, carrier: .heartbeat)
                diagnosticsStore.record(
                    phase: "statusEnvelopeCarriedOverHeartbeat",
                    deviceID: snapshot.deviceID,
                    heartbeatSequence: requestSequence,
                    requestPath: "/connection/heartbeat",
                    responseSequence: response.receivedSequenceNumber,
                    result: "response"
                )
                if statusExchangeEnvelope.delta != nil {
                    diagnosticsStore.record(
                        phase: "statusDeltaReceived",
                        deviceID: snapshot.deviceID,
                        heartbeatSequence: requestSequence,
                        requestPath: "/connection/heartbeat",
                        responseSequence: response.receivedSequenceNumber,
                        result: "facts=\(exchangeResult?.incorporatedFactCount ?? 0),rejected=\(exchangeResult?.rejectedFactCount ?? 0)"
                    )
                }
                if statusExchangeEnvelope.ack != nil {
                    diagnosticsStore.record(phase: "statusAckReceived", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, requestPath: "/connection/heartbeat", responseSequence: response.receivedSequenceNumber, result: statusExchangeEnvelope.ack?.disposition.rawValue)
                }
                if statusExchangeEnvelope.request != nil {
                    diagnosticsStore.record(phase: "statusRequestReceived", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, requestPath: "/connection/heartbeat", responseSequence: response.receivedSequenceNumber, result: statusExchangeEnvelope.request?.kind.rawValue)
                }
                if exchangeResult?.accepted == false || (exchangeResult?.rejectedFactCount ?? 0) > 0 {
                    diagnosticsStore.record(phase: "statusFactRejected", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, requestPath: "/connection/heartbeat", responseSequence: response.receivedSequenceNumber, result: exchangeResult?.reason, errorCode: exchangeResult?.stale == true ? "stale_status_envelope" : "status_fact_rejected")
                }
                if exchangeResult?.requestedActions.contains(.enqueueRunSyncSoon) == true {
                    onSyncRequested?(nil)
                }
                if exchangeResult?.requestedActions.contains(.requestLightweightAudioProof) == true {
                    diagnosticsStore.record(phase: "peerProofUnavailable", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, requestPath: "/connection/heartbeat", responseSequence: response.receivedSequenceNumber, result: "sendAudioProofRequestObserved")
                }
                if exchangeResult?.requestedActions.contains(.requestFullInventory) == true {
                    diagnosticsStore.record(phase: "fullInventoryRequested", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, requestPath: "/connection/heartbeat", responseSequence: response.receivedSequenceNumber, result: "requestOnly")
                    onSyncRequested?(nil)
                }
            }
            if let syncStartSignal = response.syncStartSignal {
                diagnosticsStore.record(
                    phase: "syncStartSignalReceived",
                    deviceID: snapshot.deviceID,
                    heartbeatSequence: requestSequence,
                    responseSequence: response.receivedSequenceNumber,
                    syncRunID: syncStartSignal.syncRunID,
                    result: syncStartSignal.reason
                )
                let ack = try await client.sendLocalNetworkSyncStartAck(
                    settings: snapshot,
                    request: LocalNetworkSyncStartAckRequest(
                        syncRunID: syncStartSignal.syncRunID,
                        deviceID: snapshot.deviceID,
                        platform: .iPhone,
                        acknowledgedAt: Date(),
                        disposition: "ack"
                    )
                )
                guard ack.ok, ack.syncRunID == syncStartSignal.syncRunID else {
                    throw SecureMacUploadError.serverRejected(ack.error ?? "sync_start_ack_failed")
                }
                diagnosticsStore.record(
                    phase: "syncStartAckSent",
                    deviceID: snapshot.deviceID,
                    heartbeatSequence: requestSequence,
                    responseSequence: response.receivedSequenceNumber,
                    syncRunID: syncStartSignal.syncRunID,
                    result: "ack"
                )
                onSyncRequested?(syncStartSignal.syncRunID)
            } else if response.syncRequested == true {
                diagnosticsStore.record(
                    phase: "syncRequestedHintReceived",
                    deviceID: snapshot.deviceID,
                    heartbeatSequence: requestSequence,
                    responseSequence: response.receivedSequenceNumber,
                    result: "syncRequested"
                )
                onSyncRequested?(nil)
            }
            return true
        } catch {
            await canonicalConnectionRuntime?.recordHeartbeatFailed(
                peer: peerIdentity,
                observedAt: Date()
            )
            let mapped = mapHeartbeatError(error)
            let status = statusStore.recordHeartbeatFailure(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                errorCode: mapped.code,
                errorMessage: mapped.message,
                isSecurityFailure: mapped.isSecurityFailure
            )
            diagnosticsStore.record(
                phase: mapped.code.contains("timedOut") || mapped.code.contains("-1001") ? "heartbeatTimeout" : "heartbeatResponseFailure",
                deviceID: snapshot.deviceID,
                heartbeatSequence: requestSequence,
                requestStartedAt: now,
                requestPath: "/connection/heartbeat",
                result: status.presenceState?.rawValue ?? "failed",
                heartbeatMissCount: status.missedHeartbeatCount,
                errorCode: mapped.code,
                errorMessage: mapped.message
            )
            diagnosticsStore.record(
                phase: "heartbeatMissCount",
                deviceID: snapshot.deviceID,
                heartbeatSequence: requestSequence,
                result: status.presenceState?.rawValue,
                heartbeatMissCount: status.missedHeartbeatCount,
                errorCode: mapped.code
            )
            if status.presenceState == .disconnected {
                diagnosticsStore.record(phase: "heartbeatMarkedDisconnected", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, result: "disconnected", heartbeatMissCount: status.missedHeartbeatCount, errorCode: mapped.code)
            } else if status.presenceState == .interrupted {
                diagnosticsStore.record(phase: "heartbeatMarkedInterrupted", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, result: "interrupted", heartbeatMissCount: status.missedHeartbeatCount, errorCode: mapped.code)
            } else if status.presenceState == .stale {
                diagnosticsStore.record(phase: "heartbeatMarkedStale", deviceID: snapshot.deviceID, heartbeatSequence: requestSequence, result: "stale", heartbeatMissCount: status.missedHeartbeatCount, errorCode: mapped.code)
            }
            return false
        }
    }

    func recordSignedRequestSucceeded(settings: SecureMacConnectionSnapshot, now: Date = Date()) {
        guard settings.isPaired else {
            return
        }
        _ = statusStore.recordSignedRequestSucceeded(
            deviceID: settings.deviceID,
            displayName: displayName(for: settings),
            now: now
        )
        diagnosticsStore.record(phase: "signedRequestRefreshedLastSeen", deviceID: settings.deviceID)
    }

    @discardableResult
    func requestImmediateProbe(reason: String, now: Date = Date()) async -> Bool {
        let snapshot = connectionStore.snapshot
        guard userWantsConnection else {
            diagnosticsStore.record(
                phase: "heartbeatSuppressedBecauseUserDoesNotWantConnection",
                deviceID: snapshot.deviceID,
                result: reason,
                timestamp: now
            )
            return false
        }
        diagnosticsStore.record(
            phase: "heartbeatImmediateProbeStarted",
            deviceID: snapshot.deviceID,
            result: reason,
            timestamp: now
        )
        let succeeded = await performHeartbeat(now: now)
        diagnosticsStore.record(
            phase: succeeded ? "heartbeatImmediateProbeSucceeded" : "heartbeatImmediateProbeFailed",
            deviceID: snapshot.deviceID,
            result: reason
        )
        return succeeded
    }

    func stopBecauseUserDoesNotWantConnection(now: Date = Date()) {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            return
        }
        _ = statusStore.markUserDisconnected(
            deviceID: snapshot.deviceID,
            displayName: displayName(for: snapshot),
            now: now
        )
        diagnosticsStore.record(
            phase: "heartbeatSuppressedBecauseUserDoesNotWantConnection",
            deviceID: snapshot.deviceID,
            timestamp: now
        )
    }

    private func displayName(for snapshot: SecureMacConnectionSnapshot) -> String {
        snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Rokurics Mac"
            : snapshot.macName
    }

    private static func canonicalMacPeerIdentity(
        snapshot: SecureMacConnectionSnapshot,
        displayName: String
    ) -> CanonicalNodeIdentity {
        CanonicalNodeIdentity(
            nodeID: CanonicalNodeID("mac-\(snapshot.deviceID)"),
            role: .mac,
            displayName: displayName
        )
    }

    private var userWantsConnection: Bool {
        (connectionStore as? SecureMacConnectionIntentProviding)?.userConnectionIntent != .disconnectedByUser
    }

    private func mapHeartbeatError(_ error: Error) -> (code: String, message: String, isSecurityFailure: Bool) {
        if let secureError = error as? SecureMacUploadError {
            switch secureError {
            case .fingerprintMismatch:
                return ("certificate_pinning_failed", secureError.localizedDescription, true)
            case .invalidFingerprint, .invalidSecret, .notPaired:
                return ("heartbeat_security_failed", secureError.localizedDescription, true)
            case .serverRejected(let reason) where reason.contains("signature") || reason.contains("unknown_device"):
                return (reason, secureError.localizedDescription, true)
            case .httpsUnavailable:
                return ("heartbeat_unreachable", secureError.localizedDescription, false)
            default:
                return ("heartbeat_failed", secureError.localizedDescription, false)
            }
        }

        if let urlError = error as? URLError {
            return ("heartbeat_\(urlError.code.rawValue)", urlError.localizedDescription, false)
        }

        return ("heartbeat_failed", error.localizedDescription, false)
    }
}

struct LocalNetworkSyncInventoryRuntimeBuild {
    let inventory: LocalNetworkSyncInventory
    let snapshot: CanonicalInventoryRuntimeSnapshot
    let report: CanonicalInventoryRuntimeReport
    let failures: [CanonicalInventoryRuntimeFailure]
}

actor LocalNetworkSyncInventoryRuntimeBuildCache {
    private var buildsByScope: [String: LocalNetworkSyncInventoryRuntimeBuild] = [:]

    func existing(
        syncRunID: String?,
        nodeRole: CanonicalInventoryRuntimeNodeRole,
        sourceKind: CanonicalInventoryRuntimeSourceKind
    ) -> LocalNetworkSyncInventoryRuntimeBuild? {
        guard let syncRunID else {
            return nil
        }
        return buildsByScope[Self.scopeKey(syncRunID: syncRunID, nodeRole: nodeRole, sourceKind: sourceKind)]
    }

    func remember(
        _ build: LocalNetworkSyncInventoryRuntimeBuild,
        syncRunID: String?,
        nodeRole: CanonicalInventoryRuntimeNodeRole,
        sourceKind: CanonicalInventoryRuntimeSourceKind
    ) {
        guard let syncRunID else {
            return
        }
        buildsByScope[Self.scopeKey(syncRunID: syncRunID, nodeRole: nodeRole, sourceKind: sourceKind)] = build
    }

    private static func scopeKey(
        syncRunID: String,
        nodeRole: CanonicalInventoryRuntimeNodeRole,
        sourceKind: CanonicalInventoryRuntimeSourceKind
    ) -> String {
        "\(nodeRole.rawValue)|\(sourceKind.rawValue)|\(syncRunID)"
    }
}

private nonisolated struct LocalNetworkSyncInventoryBackgroundInput {
    var manifest: StudyLibrarySyncManifest
    var recordings: [RecordingMetadata]
    var jobsByRecordingID: [String: RecordingUploadJob]
    var rootURL: URL
    var audioFactsByRecordingID: [String: LocalNetworkSyncInventoryBackgroundAudioFact]
    var recordingMetadataHashesByID: [String: String]
    var folderRevisionHashesByID: [StudyFolderID: String]
    var studyItemRevisionHashesByID: [StudyItemID: String]
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var fileRuntimeSnapshot: CanonicalFileRuntimeSnapshot?
    var fileRuntimeManifest: CanonicalFileManifestRuntimeResult?
    var diagnostics: CanonicalInventoryRuntimeDiagnostics
    var failures: [CanonicalInventoryRuntimeFailure]
}

private nonisolated struct LocalNetworkSyncInventoryBackgroundAudioFact {
    var url: URL?
    var available: Bool
    var size: Int64?
}

nonisolated struct LocalNetworkSyncBackgroundStudyManifestBuild {
    var manifest: StudyLibrarySyncManifest
}

private nonisolated struct LocalNetworkSyncBackgroundArtifactBuild {
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var hashComputedCount: Int
    var hashDurationMs: Int
}

private nonisolated struct LocalNetworkSyncCanonicalPlannerBundle {
    var canonicalPlan: CanonicalSyncPlan
    var applyPlan: CanonicalApplyPlan
    var libraryPlan: CanonicalLibrarySyncPlan
    var durationMs: Int
    var mainActorLongTaskDurationMs: Int
}

private nonisolated enum LocalNetworkSyncBackgroundArtifactBuilder {
    static func makeArtifacts(
        from manifest: StudyLibrarySyncManifest,
        recordings: [RecordingMetadata],
        rootURL: URL,
        fileManager: FileManager = .default
    ) -> LocalNetworkSyncBackgroundArtifactBuild {
        makeArtifacts(
            from: manifest,
            recordings: recordings,
            rootURL: rootURL,
            includeChecksums: false,
            fileManager: fileManager
        )
    }

    static func makeArtifacts(
        from manifest: StudyLibrarySyncManifest,
        recordings: [RecordingMetadata],
        rootURL: URL,
        checksumRuntime: CanonicalChecksumRuntime,
        cacheDirectoryURL: URL,
        configuration: CanonicalInventoryRuntimeConfiguration,
        fileManager: FileManager = .default
    ) async -> LocalNetworkSyncBackgroundArtifactBuild {
        var artifacts: [LocalNetworkSyncArtifactEntry] = []
        var hashComputedCount = 0
        var hashDurationMs = 0
        for recording in recordings {
            await appendArtifact(
                relativePath: recording.relativeMetadataPath,
                kind: .metadataJSON,
                ownerID: recording.id,
                rootURL: rootURL,
                checksumRuntime: checksumRuntime,
                cacheDirectoryURL: cacheDirectoryURL,
                configuration: configuration,
                fileManager: fileManager,
                artifacts: &artifacts,
                hashComputedCount: &hashComputedCount,
                hashDurationMs: &hashDurationMs
            )
        }
        for item in manifest.items {
            let ownerID = item.recordingID ?? item.itemID
            await appendArtifact(relativePath: item.receiveRelativePath, kind: .receiveJSON, ownerID: ownerID, rootURL: rootURL, checksumRuntime: checksumRuntime, cacheDirectoryURL: cacheDirectoryURL, configuration: configuration, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            await appendArtifact(relativePath: item.transcriptMarkdownRelativePath, kind: .transcriptMarkdown, ownerID: ownerID, rootURL: rootURL, checksumRuntime: checksumRuntime, cacheDirectoryURL: cacheDirectoryURL, configuration: configuration, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            await appendArtifact(relativePath: item.transcriptRelativePath, kind: .transcriptJSON, ownerID: ownerID, rootURL: rootURL, checksumRuntime: checksumRuntime, cacheDirectoryURL: cacheDirectoryURL, configuration: configuration, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            await appendArtifact(
                relativePath: item.noteRelativePath,
                kind: item.noteRelativePath?.hasSuffix(".json") == true ? .noteJSON : .noteMarkdown,
                ownerID: ownerID,
                rootURL: rootURL,
                checksumRuntime: checksumRuntime,
                cacheDirectoryURL: cacheDirectoryURL,
                configuration: configuration,
                fileManager: fileManager,
                artifacts: &artifacts,
                hashComputedCount: &hashComputedCount,
                hashDurationMs: &hashDurationMs
            )
            await appendArtifact(relativePath: item.audioRelativePath, kind: .audio, ownerID: ownerID, rootURL: rootURL, checksumRuntime: checksumRuntime, cacheDirectoryURL: cacheDirectoryURL, configuration: configuration, includeChecksum: false, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
        }
        return LocalNetworkSyncBackgroundArtifactBuild(
            artifacts: artifacts,
            hashComputedCount: hashComputedCount,
            hashDurationMs: hashDurationMs
        )
    }

    private static func makeArtifacts(
        from manifest: StudyLibrarySyncManifest,
        recordings: [RecordingMetadata],
        rootURL: URL,
        includeChecksums: Bool,
        fileManager: FileManager
    ) -> LocalNetworkSyncBackgroundArtifactBuild {
        var artifacts: [LocalNetworkSyncArtifactEntry] = []
        var hashComputedCount = 0
        var hashDurationMs = 0
        for recording in recordings {
            appendArtifact(relativePath: recording.relativeMetadataPath, kind: .metadataJSON, ownerID: recording.id, rootURL: rootURL, includeChecksum: includeChecksums, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
        }
        for item in manifest.items {
            let ownerID = item.recordingID ?? item.itemID
            appendArtifact(relativePath: item.receiveRelativePath, kind: .receiveJSON, ownerID: ownerID, rootURL: rootURL, includeChecksum: includeChecksums, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            appendArtifact(relativePath: item.transcriptMarkdownRelativePath, kind: .transcriptMarkdown, ownerID: ownerID, rootURL: rootURL, includeChecksum: includeChecksums, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            appendArtifact(relativePath: item.transcriptRelativePath, kind: .transcriptJSON, ownerID: ownerID, rootURL: rootURL, includeChecksum: includeChecksums, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            appendArtifact(relativePath: item.noteRelativePath, kind: item.noteRelativePath?.hasSuffix(".json") == true ? .noteJSON : .noteMarkdown, ownerID: ownerID, rootURL: rootURL, includeChecksum: includeChecksums, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            appendArtifact(relativePath: item.audioRelativePath, kind: .audio, ownerID: ownerID, rootURL: rootURL, includeChecksum: false, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
        }
        return LocalNetworkSyncBackgroundArtifactBuild(artifacts: artifacts, hashComputedCount: hashComputedCount, hashDurationMs: hashDurationMs)
    }

    private static func appendArtifact(
        relativePath: String?,
        kind: LocalNetworkSyncArtifactKind,
        ownerID: String,
        rootURL: URL,
        checksumRuntime: CanonicalChecksumRuntime,
        cacheDirectoryURL: URL,
        configuration: CanonicalInventoryRuntimeConfiguration,
        includeChecksum: Bool = true,
        fileManager: FileManager,
        artifacts: inout [LocalNetworkSyncArtifactEntry],
        hashComputedCount: inout Int,
        hashDurationMs: inout Int
    ) async {
        let fileURL: URL?
        if kind == .audio {
            fileURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: relativePath ?? "")
        } else {
            fileURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: relativePath ?? "", kind: kind)
        }
        guard let relativePath,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = fileURL,
              fileManager.fileExists(atPath: url.path),
              let metadata = LocalNetworkSyncArtifactFileService.metadata(for: url) else {
            return
        }

        let checksum: String?
        if includeChecksum {
            let checksumResult = await checksumRuntime.checksum(
                fileURL: url,
                logicalToken: relativePath,
                nodeRole: .iPhone,
                cacheDirectoryURL: cacheDirectoryURL,
                configuration: configuration,
                metadataProvider: { _ in
                    CanonicalChecksumFileMetadata(byteSize: metadata.size, modifiedAt: metadata.updatedAt)
                }
            )
            checksum = checksumResult.sha256
            hashDurationMs += checksumResult.hashDurationMs
            if checksumResult.hashComputed {
                hashComputedCount += 1
            }
        } else {
            checksum = nil
        }

        artifacts.append(
            LocalNetworkSyncArtifactEntry(
                artifactID: LocalNetworkSyncArtifactID.make(kind: kind, ownerID: ownerID, logicalPathToken: relativePath),
                kind: kind,
                ownerID: ownerID,
                checksum: checksum,
                size: metadata.size,
                updatedAt: metadata.updatedAt,
                availability: .local,
                logicalPathToken: relativePath,
                localAvailability: .local,
                peerAvailability: nil,
                autoDownloadAllowed: kind.isAutoDownloadAllowed
            )
        )
    }

    private static func appendArtifact(
        relativePath: String?,
        kind: LocalNetworkSyncArtifactKind,
        ownerID: String,
        rootURL: URL,
        includeChecksum: Bool = true,
        fileManager: FileManager,
        artifacts: inout [LocalNetworkSyncArtifactEntry],
        hashComputedCount: inout Int,
        hashDurationMs: inout Int
    ) {
        let fileURL: URL?
        if kind == .audio {
            fileURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: relativePath ?? "")
        } else {
            fileURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: relativePath ?? "", kind: kind)
        }
        guard let relativePath,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = fileURL,
              fileManager.fileExists(atPath: url.path),
              let metadata = LocalNetworkSyncArtifactFileService.metadata(for: url) else {
            return
        }

        let checksum: String?
        if includeChecksum {
            checksum = nil
        } else {
            checksum = nil
        }

        artifacts.append(
            LocalNetworkSyncArtifactEntry(
                artifactID: LocalNetworkSyncArtifactID.make(kind: kind, ownerID: ownerID, logicalPathToken: relativePath),
                kind: kind,
                ownerID: ownerID,
                checksum: checksum,
                size: metadata.size,
                updatedAt: metadata.updatedAt,
                availability: .local,
                logicalPathToken: relativePath,
                localAvailability: .local,
                peerAvailability: nil,
                autoDownloadAllowed: kind.isAutoDownloadAllowed
            )
        )
    }
}

nonisolated struct LocalNetworkSyncBackgroundStudyManifestBuilder {
    let fileManager: FileManager
    let rootURL: URL
    let recordings: [RecordingMetadata]
    let deviceID: String
    let generatedAt: Date

    func build() -> LocalNetworkSyncBackgroundStudyManifestBuild {
        let storedItems = loadAllStoredItemMetadata()
        let receiveItems = loadReceiveRecordDerivedItems()
        let storedItemsByRecordingID = Dictionary(
            storedItems.compactMap { item -> (String, StudyItemMetadata)? in
                guard let recordingID = item.recordingID else {
                    return nil
                }
                return (recordingID, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let liveRecordingIDs = Set(recordings.map(\.id))

        var itemsByID: [StudyItemID: StudyItemMetadata] = [:]
        for recording in recordings {
            let fallback = StudyItemMetadata.defaultMetadata(for: recording)
            let metadata = storedItemsByRecordingID[recording.id]?.mergedWithCurrentRecording(recording) ?? fallback
            itemsByID[metadata.itemID] = metadata
        }

        for item in receiveItems where item.recordingID.map({ !liveRecordingIDs.contains($0) }) ?? true {
            itemsByID[item.itemID] = item
        }

        for item in storedItems where shouldIncludeStoredItem(item, liveRecordingIDs: liveRecordingIDs, alreadyLoaded: itemsByID) {
            itemsByID[item.itemID] = item
        }

        let items = itemsByID.values.map { $0.syncSanitized(modifiedByDeviceID: deviceID) }
        let folders = repairedFolders(loadAllFolderMetadata(), items: Array(itemsByID.values))
            .map { $0.syncSanitized(modifiedByDeviceID: deviceID) }
        let tombstones = makeSyncTombstones(items: items, folders: folders)
        let pendingUploads = makePendingRecordingUploads(
            recordings: recordings,
            itemsByID: itemsByID,
            targetDeviceID: deviceID
        )
        let manifest = StudyLibrarySyncManifest.make(
            deviceID: deviceID,
            generatedAt: generatedAt,
            items: items,
            folders: folders,
            tombstones: tombstones,
            pendingUploads: pendingUploads,
            recordings: makeManifestRecordingEntries()
        )
        return LocalNetworkSyncBackgroundStudyManifestBuild(
            manifest: manifest
        )
    }

    private var studyURL: URL {
        rootURL.appendingPathComponent("study", isDirectory: true).standardizedFileURL
    }

    private var itemMetadataURL: URL {
        studyURL.appendingPathComponent("items", isDirectory: true).standardizedFileURL
    }

    private var legacyItemMetadataURL: URL {
        studyURL.appendingPathComponent("item-metadata", isDirectory: true).standardizedFileURL
    }

    private var folderMetadataURL: URL {
        studyURL.appendingPathComponent("folders", isDirectory: true).standardizedFileURL
    }

    private func loadAllStoredItemMetadata() -> [StudyItemMetadata] {
        loadMetadataFiles(from: itemMetadataURL, as: StudyItemMetadata.self)
            + loadMetadataFiles(from: legacyItemMetadataURL, as: StudyItemMetadata.self)
    }

    private func loadAllFolderMetadata() -> [StudyFolderMetadata] {
        loadMetadataFiles(from: folderMetadataURL, as: StudyFolderMetadata.self)
    }

    private func loadMetadataFiles<T: Decodable>(from directoryURL: URL, as type: T.Type) -> [T] {
        guard fileManager.fileExists(atPath: directoryURL.path),
              isInsideStudyDirectory(directoryURL),
              let urls = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "json" && isInsideStudyDirectory($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? Self.jsonDecoder.decode(T.self, from: data)
            }
    }

    private func loadReceiveRecordDerivedItems() -> [StudyItemMetadata] {
        let inboxURL = rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .standardizedFileURL
        guard isInsideRoot(inboxURL),
              fileManager.fileExists(atPath: inboxURL.path),
              let enumerator = fileManager.enumerator(
                at: inboxURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var items: [StudyItemMetadata] = []
        for case let url as URL in enumerator where url.lastPathComponent == "receive.json" {
            let receiveURL = url.standardizedFileURL
            guard isInsideRoot(receiveURL),
                  let data = try? Data(contentsOf: receiveURL),
                  let record = try? Self.jsonDecoder.decode(RecordingReceiveRecord.self, from: data),
                  let relativePath = try? relativePath(for: receiveURL),
                  let item = StudyItemMetadata.defaultMetadata(for: record, receiveRelativePath: relativePath) else {
                continue
            }
            items.append(item)
        }
        return items
    }

    private func shouldIncludeStoredItem(
        _ item: StudyItemMetadata,
        liveRecordingIDs: Set<String>,
        alreadyLoaded: [StudyItemID: StudyItemMetadata]
    ) -> Bool {
        if alreadyLoaded[item.itemID] != nil {
            return false
        }
        if item.kind == .standaloneNote || item.recordingID == nil {
            return true
        }
        if item.customProperties["syncedMetadataOnly"] == "true" {
            return true
        }
        return item.recordingID.map { liveRecordingIDs.contains($0) } ?? false
    }

    private func repairedFolders(
        _ folders: [StudyFolderMetadata],
        items: [StudyItemMetadata]
    ) -> [StudyFolderMetadata] {
        let existingItemIDs = Set(items.map(\.itemID))
        var foldersByID = Dictionary(folders.map { ($0.folderID, $0) }, uniquingKeysWith: { first, _ in first })
        for (folderID, folder) in foldersByID {
            var repaired = folder
            repaired.itemIDs = StudyItemMetadata.uniqueIDs(repaired.itemIDs.filter { existingItemIDs.contains($0) })
            foldersByID[folderID] = repaired
        }
        for item in items {
            for folderID in item.folderIDs {
                guard var folder = foldersByID[folderID] else {
                    continue
                }
                if !folder.itemIDs.contains(item.itemID) {
                    folder.itemIDs.append(item.itemID)
                }
                foldersByID[folderID] = folder
            }
        }
        return foldersByID.values.sorted { left, right in
            if left.pathComponents == right.pathComponents {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            return left.pathComponents.lexicographicallyPrecedes(right.pathComponents) {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        }
    }

    private func makeSyncTombstones(
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata]
    ) -> [StudyLibrarySyncTombstone] {
        let itemTombstones = items.filter(\.isTrashed).map { item in
            StudyLibrarySyncTombstone(
                id: "item:\(item.itemID)",
                entityKind: .item,
                entityID: item.itemID,
                operation: .trash,
                updatedAt: item.trashedAt ?? item.updatedAt,
                modifiedByDeviceID: item.modifiedByDeviceID ?? deviceID
            )
        }
        let folderTombstones = folders.filter(\.isTrashed).map { folder in
            StudyLibrarySyncTombstone(
                id: "folder:\(folder.folderID)",
                entityKind: .folder,
                entityID: folder.folderID,
                operation: .trash,
                updatedAt: folder.trashedAt ?? folder.updatedAt,
                modifiedByDeviceID: folder.modifiedByDeviceID ?? deviceID
            )
        }
        return itemTombstones + folderTombstones
    }

    private func makePendingRecordingUploads(
        recordings: [RecordingMetadata],
        itemsByID: [StudyItemID: StudyItemMetadata],
        targetDeviceID: String
    ) -> [PendingRecordingUpload] {
        recordings.compactMap { recording in
            guard !recording.isDeleted,
                  RecordingUploadStatus(rawMetadataValue: recording.uploadStatus) != .uploaded else {
                return nil
            }
            let fallbackItemID = StudyItemMetadata.recordingBundleItemID(for: recording.id)
            let item = itemsByID[fallbackItemID] ?? StudyItemMetadata.defaultMetadata(for: recording)
            return PendingRecordingUpload(
                itemID: item.itemID,
                recordingID: recording.id,
                localAudioRelativePath: recording.relativeAudioPath,
                targetDeviceID: targetDeviceID,
                status: PendingRecordingUploadStatus(rawValue: recording.uploadStatus) ?? .pending,
                createdAt: recording.createdAt,
                updatedAt: item.updatedAt
            )
        }
    }

    private func makeManifestRecordingEntries() -> [LocalNetworkSyncRecordingEntry] {
        recordings.map { recording in
            let audioURL = localFileURL(relativePath: recording.relativeAudioPath)
            let hasAudio = audioURL.map { fileManager.fileExists(atPath: $0.path) } ?? false
            let byteSize = hasAudio ? audioURL.flatMap { url -> Int64? in
                guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                      let size = attributes[.size] as? NSNumber else {
                    return nil
                }
                return size.int64Value
            } : nil
            return LocalNetworkSyncRecordingEntry(
                recordingID: recording.id,
                metadataHash: LocalNetworkSyncMetadataHash.hash(recording),
                audioAvailable: hasAudio,
                audioChecksum: nil,
                audioSize: byteSize,
                uploadLedgerState: nil,
                receiveStatus: nil,
                processingStatus: nil,
                updatedAt: recording.deletedAt ?? recording.createdAt,
                deleted: recording.isDeleted,
                title: recording.title,
                createdAt: recording.createdAt,
                tombstone: recording.isDeleted,
                audioAvailability: hasAudio ? .local : .missing,
                uploadStatus: recording.uploadStatus,
                transcriptionStatus: recording.transcriptionStatus,
                noteStatus: recording.noteStatus,
                sourceDeviceID: deviceID,
                artifactRefs: [
                    LocalNetworkSyncArtifactID.make(
                        kind: .metadataJSON,
                        ownerID: recording.id,
                        logicalPathToken: recording.relativeMetadataPath
                    )
                ],
                audioLogicalPathToken: recording.relativeAudioPath
            )
        }
    }

    private func localFileURL(relativePath: String) -> URL? {
        guard !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("://") else {
            return nil
        }
        let url = rootURL.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        return isInsideRoot(url) ? url : nil
    }

    private func relativePath(for url: URL) throws -> String {
        let baseURL = rootURL.standardizedFileURL
        let standardizedURL = url.standardizedFileURL
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : "\(baseURL.path)/"
        let filePath = standardizedURL.path
        guard filePath.hasPrefix(basePath) else {
            throw StudyLibraryStoreError.unsafeDestination
        }
        return String(filePath.dropFirst(basePath.count))
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private func isInsideStudyDirectory(_ url: URL) -> Bool {
        let studyPath = studyURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == studyPath || path.hasPrefix(studyPath + "/")
    }

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

nonisolated enum LocalNetworkSyncInventoryBackgroundIO {
    static func loadRecordings(rootURL: URL, includeDeleted: Bool, fileManager: FileManager = .default) -> [RecordingMetadata] {
        let metadataURL = rootURL.appendingPathComponent("Metadata", isDirectory: true).standardizedFileURL
        guard let urls = try? fileManager.contentsOfDirectory(
            at: metadataURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> RecordingMetadata? in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? jsonDecoder.decode(RecordingMetadata.self, from: data)
            }
            .filter { includeDeleted || !$0.isDeleted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func loadUploadJobs(rootURL: URL, fileManager: FileManager = .default) -> [RecordingUploadJob] {
        let ledgerURL = rootURL
            .appendingPathComponent("UploadJobs", isDirectory: true)
            .appendingPathComponent("upload-ledger")
            .appendingPathExtension("json")
            .standardizedFileURL
        guard fileManager.fileExists(atPath: ledgerURL.path),
              let data = try? Data(contentsOf: ledgerURL),
              let ledger = try? jsonDecoder.decode(RecordingUploadJobLedger.self, from: data) else {
            return []
        }
        return ledger.jobs
    }

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

struct LocalNetworkSyncInventoryBuilder {
    let audioFileStore: AudioFileStore
    let studyLibraryStore: StudyLibraryStore
    let uploadJobStore: RecordingUploadJobStore
    let diagnosticsStore: ConnectionDiagnosticsStore
    let canonicalChecksumCache: CanonicalChecksumRuntime
    let runtimeConfiguration: CanonicalInventoryRuntimeConfiguration
    private let buildCache = LocalNetworkSyncInventoryRuntimeBuildCache()

    init(
        audioFileStore: AudioFileStore,
        studyLibraryStore: StudyLibraryStore,
        uploadJobStore: RecordingUploadJobStore,
        diagnosticsStore: ConnectionDiagnosticsStore? = nil,
        canonicalChecksumCache: CanonicalChecksumRuntime? = nil,
        runtimeConfiguration: CanonicalInventoryRuntimeConfiguration = CanonicalInventoryRuntimeConfiguration()
    ) {
        self.audioFileStore = audioFileStore
        self.studyLibraryStore = studyLibraryStore
        self.uploadJobStore = uploadJobStore
        self.diagnosticsStore = diagnosticsStore ?? .shared
        self.canonicalChecksumCache = canonicalChecksumCache ?? CanonicalChecksumRuntime()
        self.runtimeConfiguration = runtimeConfiguration
    }

    private func loadBackgroundInput(
        deviceID: String,
        generatedAt: Date
    ) async -> LocalNetworkSyncInventoryBackgroundInput {
        let rootURL = (try? audioFileStore.baseDirectory()) ?? FileManager.default.temporaryDirectory
        let checksumRuntime = canonicalChecksumCache
        let cacheDirectoryURL = canonicalChecksumCacheDirectory(rootURL: rootURL)
        let inventoryRuntimeConfiguration = runtimeConfiguration
        let startedAt = Date()
        let input = await Task.detached(priority: .utility) {
            let scanStartedAt = Date()
            let scanMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            let metadataStartedAt = Date()
            let metadataMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            let recordings = LocalNetworkSyncInventoryBackgroundIO.loadRecordings(rootURL: rootURL, includeDeleted: true)
            let metadataLoadDurationMs = max(0, Int(Date().timeIntervalSince(metadataStartedAt) * 1_000))
            let jobsStartedAt = Date()
            let jobsMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            let jobsByRecordingID = LocalNetworkSyncInventoryBackgroundIO.loadUploadJobs(rootURL: rootURL)
                .reduce(into: [String: RecordingUploadJob]()) { result, job in
                result[job.recordingID] = job
            }
            let jobsLoadDurationMs = max(0, Int(Date().timeIntervalSince(jobsStartedAt) * 1_000))
            let manifestStartedAt = Date()
            let manifestBuildMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            let manifestBuild = LocalNetworkSyncBackgroundStudyManifestBuilder(
                fileManager: .default,
                rootURL: rootURL,
                recordings: recordings,
                deviceID: deviceID,
                generatedAt: generatedAt
            ).build()
            let manifestBuildDurationMs = max(0, Int(Date().timeIntervalSince(manifestStartedAt) * 1_000))
            let hashStartedAt = Date()
            let audioFactsByRecordingID = Dictionary(
                uniqueKeysWithValues: recordings.map { metadata -> (String, LocalNetworkSyncInventoryBackgroundAudioFact) in
                    let audioURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(
                        rootURL: rootURL,
                        logicalPathToken: metadata.relativeAudioPath
                    )
                    let available = audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                    let size = available ? audioURL.flatMap { LocalNetworkSyncArtifactFileService.metadata(for: $0)?.size } : nil
                    return (
                        metadata.id,
                        LocalNetworkSyncInventoryBackgroundAudioFact(
                            url: audioURL,
                            available: available,
                            size: size
                        )
                    )
                }
            )
            let recordingMetadataHashesByID = Dictionary(
                manifestBuild.manifest.recordings.compactMap { entry -> (String, String)? in
                    guard let hash = entry.metadataHash else {
                        return nil
                    }
                    return (entry.recordingID, hash)
                },
                uniquingKeysWith: { _, latest in latest }
            )
            let folderRevisionHashesByID = Dictionary(
                manifestBuild.manifest.folders.map { folder in
                    (folder.folderID, LocalNetworkSyncMetadataHash.hash(folder))
                },
                uniquingKeysWith: { _, latest in latest }
            )
            let studyItemRevisionHashesByID = Dictionary(
                manifestBuild.manifest.items.map { item in
                    (item.itemID, LocalNetworkSyncMetadataHash.hash(item))
                },
                uniquingKeysWith: { _, latest in latest }
            )
            let artifactBuild = await LocalNetworkSyncBackgroundArtifactBuilder.makeArtifacts(
                from: manifestBuild.manifest,
                recordings: recordings,
                rootURL: rootURL,
                checksumRuntime: checksumRuntime,
                cacheDirectoryURL: cacheDirectoryURL,
                configuration: inventoryRuntimeConfiguration
            )
            let fileRuntime = await Self.makeFileKernelRuntime(
                rootToken: CanonicalRootToken("iphone-library-root"),
                adapter: IPhoneCanonicalFileRuntimeAdapter(
                    entries: Self.fileSnapshotEntries(from: artifactBuild.artifacts)
                )
            )
            let metadataHashDurationMs = max(0, Int(Date().timeIntervalSince(hashStartedAt) * 1_000))
            let scanDurationMs = max(0, Int(Date().timeIntervalSince(scanStartedAt) * 1_000))
            return LocalNetworkSyncInventoryBackgroundInput(
                manifest: manifestBuild.manifest,
                recordings: recordings,
                jobsByRecordingID: jobsByRecordingID,
                rootURL: rootURL,
                audioFactsByRecordingID: audioFactsByRecordingID,
                recordingMetadataHashesByID: recordingMetadataHashesByID,
                folderRevisionHashesByID: folderRevisionHashesByID,
                studyItemRevisionHashesByID: studyItemRevisionHashesByID,
                artifacts: artifactBuild.artifacts,
                fileRuntimeSnapshot: fileRuntime.snapshot,
                fileRuntimeManifest: fileRuntime.manifest,
                diagnostics: CanonicalInventoryRuntimeDiagnostics(
                    fileScanCount: recordings.count,
                    hashComputedCount: recordingMetadataHashesByID.count
                        + folderRevisionHashesByID.count
                        + studyItemRevisionHashesByID.count
                        + artifactBuild.hashComputedCount,
                    mainActorHashAttemptCount: 0,
                    mainActorScanAttemptCount: scanMainActorAttemptCount,
                    mainActorMetadataLoadAttemptCount: metadataMainActorAttemptCount,
                    mainActorJobsLoadAttemptCount: jobsMainActorAttemptCount,
                    mainActorManifestBuildAttemptCount: manifestBuildMainActorAttemptCount,
                    mainActorHashBlockedCount: 0,
                    mainActorScanBlockedCount: scanMainActorAttemptCount,
                    scanDurationMs: scanDurationMs,
                    manifestBuildDurationMs: manifestBuildDurationMs,
                    metadataLoadDurationMs: metadataLoadDurationMs,
                    jobsLoadDurationMs: jobsLoadDurationMs,
                    hashDurationMs: metadataHashDurationMs
                ),
                failures: []
            )
        }.value
        let durationMs = CanonicalPerfLog.elapsedMs(since: startedAt)
        diagnosticsStore.recordPerfLog(
            CanonicalPerfLog.subphaseMeasured(
                operation: .immediateSync,
                subphase: .inventoryBuildMs,
                durationMs: durationMs,
                result: "localNetworkInventoryInput"
            ),
            deviceID: deviceID
        )
        if input.diagnostics.hashDurationMs > 0 {
            diagnosticsStore.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .hashMs,
                    durationMs: input.diagnostics.hashDurationMs,
                    result: "inventoryHash"
                ),
                deviceID: deviceID
            )
        }
        return input
    }

    private static func makeBackgroundInput(
        rootURL: URL,
        deviceID: String,
        generatedAt: Date
    ) -> LocalNetworkSyncInventoryBackgroundInput {
        let scanStartedAt = Date()
        let scanMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
        let metadataStartedAt = Date()
        let metadataMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
        let recordings = LocalNetworkSyncInventoryBackgroundIO.loadRecordings(rootURL: rootURL, includeDeleted: true)
        let metadataLoadDurationMs = max(0, Int(Date().timeIntervalSince(metadataStartedAt) * 1_000))
        let jobsStartedAt = Date()
        let jobsMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
        let jobsByRecordingID = LocalNetworkSyncInventoryBackgroundIO.loadUploadJobs(rootURL: rootURL)
            .reduce(into: [String: RecordingUploadJob]()) { result, job in
                result[job.recordingID] = job
            }
        let jobsLoadDurationMs = max(0, Int(Date().timeIntervalSince(jobsStartedAt) * 1_000))
        let manifestStartedAt = Date()
        let manifestBuildMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
        let manifestBuild = LocalNetworkSyncBackgroundStudyManifestBuilder(
            fileManager: .default,
            rootURL: rootURL,
            recordings: recordings,
            deviceID: deviceID,
            generatedAt: generatedAt
        ).build()
        let manifestBuildDurationMs = max(0, Int(Date().timeIntervalSince(manifestStartedAt) * 1_000))
        let hashStartedAt = Date()
        let audioFactsByRecordingID = Dictionary(
            uniqueKeysWithValues: recordings.map { metadata -> (String, LocalNetworkSyncInventoryBackgroundAudioFact) in
                let audioURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(
                    rootURL: rootURL,
                    logicalPathToken: metadata.relativeAudioPath
                )
                let available = audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                let size = available ? audioURL.flatMap { LocalNetworkSyncArtifactFileService.metadata(for: $0)?.size } : nil
                return (
                    metadata.id,
                    LocalNetworkSyncInventoryBackgroundAudioFact(
                        url: audioURL,
                        available: available,
                        size: size
                    )
                )
            }
        )
        let recordingMetadataHashesByID = Dictionary(
            manifestBuild.manifest.recordings.compactMap { entry -> (String, String)? in
                guard let hash = entry.metadataHash else {
                    return nil
                }
                return (entry.recordingID, hash)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let folderRevisionHashesByID = Dictionary(
            manifestBuild.manifest.folders.map { folder in
                (folder.folderID, LocalNetworkSyncMetadataHash.hash(folder))
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let studyItemRevisionHashesByID = Dictionary(
            manifestBuild.manifest.items.map { item in
                (item.itemID, LocalNetworkSyncMetadataHash.hash(item))
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let artifactBuild = LocalNetworkSyncBackgroundArtifactBuilder.makeArtifacts(
            from: manifestBuild.manifest,
            recordings: recordings,
            rootURL: rootURL
        )
        let metadataHashDurationMs = max(0, Int(Date().timeIntervalSince(hashStartedAt) * 1_000))
        let scanDurationMs = max(0, Int(Date().timeIntervalSince(scanStartedAt) * 1_000))
        return LocalNetworkSyncInventoryBackgroundInput(
            manifest: manifestBuild.manifest,
            recordings: recordings,
            jobsByRecordingID: jobsByRecordingID,
            rootURL: rootURL,
            audioFactsByRecordingID: audioFactsByRecordingID,
            recordingMetadataHashesByID: recordingMetadataHashesByID,
            folderRevisionHashesByID: folderRevisionHashesByID,
            studyItemRevisionHashesByID: studyItemRevisionHashesByID,
            artifacts: artifactBuild.artifacts,
            fileRuntimeSnapshot: nil,
            fileRuntimeManifest: nil,
            diagnostics: CanonicalInventoryRuntimeDiagnostics(
                fileScanCount: recordings.count,
                hashComputedCount: recordingMetadataHashesByID.count
                    + folderRevisionHashesByID.count
                    + studyItemRevisionHashesByID.count
                    + artifactBuild.hashComputedCount,
                mainActorHashAttemptCount: 0,
                mainActorScanAttemptCount: scanMainActorAttemptCount,
                mainActorMetadataLoadAttemptCount: metadataMainActorAttemptCount,
                mainActorJobsLoadAttemptCount: jobsMainActorAttemptCount,
                mainActorManifestBuildAttemptCount: manifestBuildMainActorAttemptCount,
                mainActorHashBlockedCount: 0,
                mainActorScanBlockedCount: scanMainActorAttemptCount,
                scanDurationMs: scanDurationMs,
                manifestBuildDurationMs: manifestBuildDurationMs,
                metadataLoadDurationMs: metadataLoadDurationMs,
                jobsLoadDurationMs: jobsLoadDurationMs,
                hashDurationMs: metadataHashDurationMs
            ),
            failures: []
        )
    }

    func buildRuntimeSnapshot(
        deviceID: String,
        deviceName: String,
        lastKnownPeerRevision: String?,
        generatedAt: Date = Date(),
        shadowTrigger: String? = nil,
        shadowSyncRunID: String? = nil,
        sourceKind: CanonicalInventoryRuntimeSourceKind = .syncTick
    ) async -> LocalNetworkSyncInventoryRuntimeBuild {
        if let cached = await buildCache.existing(syncRunID: shadowSyncRunID, nodeRole: .iPhone, sourceKind: sourceKind) {
            var reusedSnapshot = cached.snapshot
            reusedSnapshot.reusedWithinTick = true
            reusedSnapshot.diagnostics.duplicateBuildCount += 1
            reusedSnapshot.diagnostics.snapshotReuseCount += 1
            let reusedReport = CanonicalInventoryRuntimeReportExporter.report(from: reusedSnapshot)
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeSnapshotReused",
                deviceID: deviceID,
                syncRunID: shadowSyncRunID,
                result: "source=\(sourceKind.rawValue),duplicateBuildCount=\(reusedSnapshot.diagnostics.duplicateBuildCount)"
            )
            return LocalNetworkSyncInventoryRuntimeBuild(
                inventory: cached.inventory,
                snapshot: reusedSnapshot,
                report: reusedReport,
                failures: cached.failures
            )
        }

        let startedAt = Date()
        diagnosticsStore.record(phase: "inventoryBuildStarted", deviceID: deviceID, syncRunID: shadowSyncRunID)
        let input = await loadBackgroundInput(
            deviceID: deviceID,
            generatedAt: generatedAt
        )
        let manifest = input.manifest
        let recordings = input.recordings
        let jobsByRecordingID = input.jobsByRecordingID
        let rootURL = input.rootURL
        let audioFactsByRecordingID = input.audioFactsByRecordingID
        let recordingMetadataHashesByID = input.recordingMetadataHashesByID
        let folderRevisionHashesByID = input.folderRevisionHashesByID
        let studyItemRevisionHashesByID = input.studyItemRevisionHashesByID
        let artifacts = input.artifacts
        recordFileKernelRuntimeDiagnostics(
            snapshot: input.fileRuntimeSnapshot,
            manifest: input.fileRuntimeManifest,
            deviceID: deviceID,
            syncRunID: shadowSyncRunID
        )
        var runtimeDiagnostics = input.diagnostics
        var runtimeFailures: [CanonicalInventoryRuntimeFailure] = input.failures
        let cacheDirectoryURL = canonicalChecksumCacheDirectory(rootURL: rootURL)
        var recordingEntries: [LocalNetworkSyncRecordingEntry] = []
        recordingEntries.reserveCapacity(recordings.count)
        for metadata in recordings {
            if Task.isCancelled {
                runtimeFailures.append(.cancelled)
                break
            }
            let audioFact = audioFactsByRecordingID[metadata.id]
            let audioURL = audioFact?.url
            let hasAudio = audioFact?.available ?? false
            let checksumResult: LocalNetworkChecksumCacheResult?
            if hasAudio, let url = audioURL {
                let runtimeResult = await cachedRuntimeChecksum(
                    fileURL: url,
                    pathToken: metadata.relativeAudioPath,
                    deviceID: deviceID,
                    syncRunID: shadowSyncRunID,
                    recordingID: metadata.id,
                    cacheDirectoryURL: cacheDirectoryURL
                )
                runtimeDiagnostics.merge(runtimeResult.runtimeResult)
                if let failure = runtimeResult.runtimeResult.failure {
                    runtimeFailures.append(failure)
                }
                checksumResult = runtimeResult.legacyResult
            } else {
                checksumResult = nil
            }
            let fileSize = checksumResult?.size ?? audioFact?.size
            let checksum = checksumResult?.sha256
            recordingEntries.append(
                LocalNetworkSyncRecordingEntry(
                    recordingID: metadata.id,
                    metadataHash: recordingMetadataHashesByID[metadata.id],
                    audioAvailable: hasAudio,
                    audioChecksum: checksum,
                    audioSize: fileSize,
                    uploadLedgerState: jobsByRecordingID[metadata.id]?.overallState.rawValue,
                    receiveStatus: nil,
                    processingStatus: nil,
                    updatedAt: metadata.deletedAt ?? metadata.createdAt,
                    deleted: metadata.isDeleted,
                    title: metadata.title,
                    createdAt: metadata.createdAt,
                    tombstone: metadata.isDeleted,
                    audioAvailability: hasAudio ? .local : .missing,
                    uploadStatus: metadata.uploadStatus,
                    transcriptionStatus: metadata.transcriptionStatus,
                    noteStatus: metadata.noteStatus,
                    sourceDeviceID: deviceID,
                    artifactRefs: [
                        LocalNetworkSyncArtifactID.make(
                            kind: .metadataJSON,
                            ownerID: metadata.id,
                            logicalPathToken: metadata.relativeMetadataPath
                        )
                    ],
                    audioLogicalPathToken: metadata.relativeAudioPath
                )
            )
        }
        let folders = manifest.folders.map { folder in
            LocalNetworkSyncFolderEntry(
                folderID: folder.folderID,
                parentID: folder.parentFolderID,
                path: folder.path.displaySummary,
                name: folder.name,
                colorToken: folder.colorToken?.rawValue,
                updatedAt: folder.updatedAt,
                revisionHash: folderRevisionHashesByID[folder.folderID, default: ""],
                deleted: folder.isTrashed
            )
        }
        let studyItems = manifest.items.map { item in
            LocalNetworkSyncStudyItemEntry(
                itemID: item.itemID,
                kind: item.kind,
                title: item.title,
                folderIDs: item.folderIDs,
                recordingID: item.recordingID,
                updatedAt: item.updatedAt,
                revisionHash: studyItemRevisionHashesByID[item.itemID, default: ""],
                deleted: item.isTrashed,
                path: item.filing.displaySummary,
                conflictStatus: nil
            )
        }
        let device = LocalNetworkSyncDeviceSection(
            deviceID: deviceID,
            deviceName: deviceName,
            platform: .iPhone,
            generatedAt: generatedAt,
            lastKnownPeerRevision: lastKnownPeerRevision,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
        let canonicalFactsByRecordingID = Dictionary(
            uniqueKeysWithValues: recordingEntries.map { entry in
                (entry.recordingID, canonicalAudioFact(from: entry))
            }
        )
        let canonicalGeneratedArtifactsByRecordingID = Dictionary(
            grouping: artifacts.compactMap { canonicalGeneratedArtifact(from: $0, nodeID: deviceID, platform: "iPhone") }
        ) { $0.objectID }
        let canonicalNode = CanonicalNode(
            nodeID: deviceID,
            platform: "iPhone",
            capabilities: [
                .recordingMetadata,
                .audioArtifact,
                .objectProjection,
                .canonicalLibraryObjectsV1,
                .canonicalFolderObjectsV1,
                .canonicalStudyItemObjectsV1,
                .canonicalTransferStateV1,
                .canonicalObjectProjectionV1,
                .canonicalInventoryBuilderV1,
                .canonicalRetirementReadinessV1
            ]
        )
        let recordingAdapter = IPhoneCanonicalRecordingAdapter()
        let canonicalRecordingObjects = recordingAdapter.makeObjects(
            recordings: recordings,
            audioFactsByRecordingID: canonicalFactsByRecordingID,
            artifactFactsByRecordingID: canonicalGeneratedArtifactsByRecordingID,
            nodeID: deviceID
        )
        let libraryAdapter = IPhoneCanonicalLibraryAdapter()
        let canonicalLibraryObjects = libraryAdapter.makeLibraryObjects(from: manifest)
        let canonicalLibraryTombstones = libraryAdapter.makeTombstones(from: manifest)
        let canonicalInventoryBuild = CanonicalInventoryBuilderContract().build(
            from: CanonicalInventoryInputSnapshot(
                node: canonicalNode,
                generatedAt: generatedAt,
                recordingObjects: canonicalRecordingObjects,
                libraryObjects: canonicalLibraryObjects,
                libraryTombstones: canonicalLibraryTombstones,
                unsupportedObjects: libraryAdapter.makeUnsupportedObjects(from: manifest)
            )
        )
        let canonicalManifest = canonicalInventoryBuild.manifest
        recordCanonicalInventoryCoverage(
            canonicalInventoryBuild.coverage,
            deviceID: deviceID,
            syncRunID: shadowSyncRunID
        )

        let inventory = LocalNetworkSyncInventory.make(
            device: device,
            recordings: recordingEntries,
            folders: folders,
            studyItems: studyItems,
            artifacts: artifacts,
            studyManifest: manifest,
            canonicalManifest: canonicalManifest
        )
        if shadowTrigger != nil || shadowSyncRunID != nil {
            writeCanonicalShadowReport(
                deviceID: deviceID,
                generatedAt: generatedAt,
                trigger: shadowTrigger,
                syncRunID: shadowSyncRunID,
                canonicalManifest: canonicalManifest,
                recordingEntries: recordingEntries,
                studyItems: studyItems,
                artifacts: inventory.artifacts
            )
        }
        let endedAt = Date()
        let durationMs = max(0, endedAt.timeIntervalSince(startedAt) * 1_000)
        let snapshot = CanonicalInventoryRuntimeSnapshot(
            syncRunID: shadowSyncRunID ?? "unspecified",
            nodeRole: .iPhone,
            buildStartedAt: startedAt,
            buildEndedAt: endedAt,
            sourceKind: sourceKind,
            objectCounts: CanonicalInventoryObjectCounts(
                recordingMetadataCount: recordingEntries.count,
                libraryFolderCount: folders.count,
                libraryItemCount: studyItems.count,
                artifactCount: artifacts.count,
                audioDescriptorCount: recordingEntries.filter { $0.audioAvailable || $0.audioLogicalPathToken != nil }.count
            ),
            diagnostics: runtimeDiagnostics,
            mainActorBlocked: runtimeDiagnostics.mainActorHashBlockedCount > 0
                || runtimeDiagnostics.mainActorScanBlockedCount > 0
                || runtimeDiagnostics.mainActorMetadataLoadAttemptCount > 0
                || runtimeDiagnostics.mainActorJobsLoadAttemptCount > 0
                || runtimeDiagnostics.mainActorManifestBuildAttemptCount > 0,
            reusedWithinTick: false,
            redacted: true
        )
        let report = CanonicalInventoryRuntimeReportExporter.report(from: snapshot)
        recordRuntimeSnapshotDiagnostics(snapshot, report: report, deviceID: deviceID, syncRunID: shadowSyncRunID)
        diagnosticsStore.record(
            phase: "inventoryBuildCompleted",
            deviceID: deviceID,
            syncRunID: shadowSyncRunID,
            result: "recordings=\(recordingEntries.count),durationMs=\(Int(durationMs.rounded()))"
        )
        diagnosticsStore.record(
            phase: "inventoryBuildDurationMs",
            deviceID: deviceID,
            syncRunID: shadowSyncRunID,
            result: "\(Int(durationMs.rounded()))"
        )
        let build = LocalNetworkSyncInventoryRuntimeBuild(
            inventory: inventory,
            snapshot: snapshot,
            report: report,
            failures: runtimeFailures
        )
        await buildCache.remember(build, syncRunID: shadowSyncRunID, nodeRole: .iPhone, sourceKind: sourceKind)
        return build
    }

    func build(
        deviceID: String,
        deviceName: String,
        lastKnownPeerRevision: String?,
        generatedAt: Date = Date(),
        shadowTrigger: String? = nil,
        shadowSyncRunID: String? = nil
    ) -> LocalNetworkSyncInventory {
        let rootURL = (try? audioFileStore.baseDirectory()) ?? FileManager.default.temporaryDirectory
        let makeInput = {
            Self.makeBackgroundInput(
                rootURL: rootURL,
                deviceID: deviceID,
                generatedAt: generatedAt
            )
        }
        let input: LocalNetworkSyncInventoryBackgroundInput
        if CanonicalInventoryRuntimeExecutionProbe.isMainThread() {
            input = DispatchQueue.global(qos: .utility).sync(execute: makeInput)
        } else {
            input = makeInput()
        }
        return buildLegacyInventory(
            input: input,
            deviceID: deviceID,
            deviceName: deviceName,
            lastKnownPeerRevision: lastKnownPeerRevision,
            generatedAt: generatedAt,
            shadowTrigger: shadowTrigger,
            shadowSyncRunID: shadowSyncRunID
        )
    }

    private func buildLegacyInventory(
        input: LocalNetworkSyncInventoryBackgroundInput,
        deviceID: String,
        deviceName: String,
        lastKnownPeerRevision: String?,
        generatedAt: Date,
        shadowTrigger: String?,
        shadowSyncRunID: String?
    ) -> LocalNetworkSyncInventory {
        let startedAt = Date()
        diagnosticsStore.record(phase: "inventoryBuildStarted", deviceID: deviceID)
        let manifest = input.manifest
        let recordings = input.recordings
        let jobsByRecordingID = input.jobsByRecordingID
        let audioFactsByRecordingID = input.audioFactsByRecordingID
        let recordingMetadataHashesByID = input.recordingMetadataHashesByID
        let folderRevisionHashesByID = input.folderRevisionHashesByID
        let studyItemRevisionHashesByID = input.studyItemRevisionHashesByID
        let artifacts = input.artifacts
        let recordingEntries = recordings.map { metadata in
            let audioFact = audioFactsByRecordingID[metadata.id]
            let hasAudio = audioFact?.available ?? false
            let fileSize = audioFact?.size
            let checksum: String? = nil
            return LocalNetworkSyncRecordingEntry(
                recordingID: metadata.id,
                metadataHash: recordingMetadataHashesByID[metadata.id],
                audioAvailable: hasAudio,
                audioChecksum: checksum,
                audioSize: fileSize,
                uploadLedgerState: jobsByRecordingID[metadata.id]?.overallState.rawValue,
                receiveStatus: nil,
                processingStatus: nil,
                updatedAt: metadata.deletedAt ?? metadata.createdAt,
                deleted: metadata.isDeleted,
                title: metadata.title,
                createdAt: metadata.createdAt,
                tombstone: metadata.isDeleted,
                audioAvailability: hasAudio ? .local : .missing,
                uploadStatus: metadata.uploadStatus,
                transcriptionStatus: metadata.transcriptionStatus,
                noteStatus: metadata.noteStatus,
                sourceDeviceID: deviceID,
                artifactRefs: [
                    LocalNetworkSyncArtifactID.make(
                        kind: .metadataJSON,
                        ownerID: metadata.id,
                        logicalPathToken: metadata.relativeMetadataPath
                    )
                ],
                audioLogicalPathToken: metadata.relativeAudioPath
            )
        }
        let folders = manifest.folders.map { folder in
            LocalNetworkSyncFolderEntry(
                folderID: folder.folderID,
                parentID: folder.parentFolderID,
                path: folder.path.displaySummary,
                name: folder.name,
                colorToken: folder.colorToken?.rawValue,
                updatedAt: folder.updatedAt,
                revisionHash: folderRevisionHashesByID[folder.folderID, default: ""],
                deleted: folder.isTrashed
            )
        }
        let studyItems = manifest.items.map { item in
            LocalNetworkSyncStudyItemEntry(
                itemID: item.itemID,
                kind: item.kind,
                title: item.title,
                folderIDs: item.folderIDs,
                recordingID: item.recordingID,
                updatedAt: item.updatedAt,
                revisionHash: studyItemRevisionHashesByID[item.itemID, default: ""],
                deleted: item.isTrashed,
                path: item.filing.displaySummary,
                conflictStatus: nil
            )
        }
        let device = LocalNetworkSyncDeviceSection(
            deviceID: deviceID,
            deviceName: deviceName,
            platform: .iPhone,
            generatedAt: generatedAt,
            lastKnownPeerRevision: lastKnownPeerRevision,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
        let canonicalFactsByRecordingID = Dictionary(
            uniqueKeysWithValues: recordingEntries.map { entry in
                (entry.recordingID, canonicalAudioFact(from: entry))
            }
        )
        let canonicalGeneratedArtifactsByRecordingID = Dictionary(
            grouping: artifacts.compactMap { canonicalGeneratedArtifact(from: $0, nodeID: deviceID, platform: "iPhone") }
        ) { $0.objectID }
        let canonicalNode = CanonicalNode(
            nodeID: deviceID,
            platform: "iPhone",
            capabilities: [
                .recordingMetadata,
                .audioArtifact,
                .objectProjection,
                .canonicalLibraryObjectsV1,
                .canonicalFolderObjectsV1,
                .canonicalStudyItemObjectsV1,
                .canonicalTransferStateV1,
                .canonicalObjectProjectionV1,
                .canonicalInventoryBuilderV1,
                .canonicalRetirementReadinessV1
            ]
        )
        let recordingAdapter = IPhoneCanonicalRecordingAdapter()
        let canonicalRecordingObjects = recordingAdapter.makeObjects(
            recordings: recordings,
            audioFactsByRecordingID: canonicalFactsByRecordingID,
            artifactFactsByRecordingID: canonicalGeneratedArtifactsByRecordingID,
            nodeID: deviceID
        )
        let libraryAdapter = IPhoneCanonicalLibraryAdapter()
        let canonicalLibraryObjects = libraryAdapter.makeLibraryObjects(from: manifest)
        let canonicalLibraryTombstones = libraryAdapter.makeTombstones(from: manifest)
        let canonicalInventoryBuild = CanonicalInventoryBuilderContract().build(
            from: CanonicalInventoryInputSnapshot(
                node: canonicalNode,
                generatedAt: generatedAt,
                recordingObjects: canonicalRecordingObjects,
                libraryObjects: canonicalLibraryObjects,
                libraryTombstones: canonicalLibraryTombstones,
                unsupportedObjects: libraryAdapter.makeUnsupportedObjects(from: manifest)
            )
        )
        let canonicalManifest = canonicalInventoryBuild.manifest
        recordCanonicalInventoryCoverage(
            canonicalInventoryBuild.coverage,
            deviceID: deviceID,
            syncRunID: shadowSyncRunID
        )

        let inventory = LocalNetworkSyncInventory.make(
            device: device,
            recordings: recordingEntries,
            folders: folders,
            studyItems: studyItems,
            artifacts: artifacts,
            studyManifest: manifest,
            canonicalManifest: canonicalManifest
        )
        if shadowTrigger != nil || shadowSyncRunID != nil {
            writeCanonicalShadowReport(
                deviceID: deviceID,
                generatedAt: generatedAt,
                trigger: shadowTrigger,
                syncRunID: shadowSyncRunID,
                canonicalManifest: canonicalManifest,
                recordingEntries: recordingEntries,
                studyItems: studyItems,
                artifacts: inventory.artifacts
            )
        }
        let durationMs = max(0, Date().timeIntervalSince(startedAt) * 1_000)
        diagnosticsStore.record(
            phase: "inventoryBuildCompleted",
            deviceID: deviceID,
            result: "recordings=\(recordingEntries.count),durationMs=\(Int(durationMs.rounded()))"
        )
        diagnosticsStore.record(
            phase: "inventoryBuildDurationMs",
            deviceID: deviceID,
            result: "\(Int(durationMs.rounded()))"
        )
        return inventory
    }

    private func writeCanonicalShadowReport(
        deviceID: String,
        generatedAt: Date,
        trigger: String?,
        syncRunID: String?,
        canonicalManifest: CanonicalManifest,
        recordingEntries: [LocalNetworkSyncRecordingEntry],
        studyItems: [LocalNetworkSyncStudyItemEntry],
        artifacts: [LocalNetworkSyncArtifactEntry]
    ) {
        let startedAt = Date()
        diagnosticsStore.record(phase: "canonicalShadowBuildStarted", deviceID: deviceID, syncRunID: syncRunID, result: trigger)
        let legacy = CanonicalShadowLegacySnapshot(
            recordingCount: recordingEntries.count,
            studyItemCount: studyItems.count,
            artifactCount: artifacts.count,
            objects: legacyObjectFacts(recordingEntries: recordingEntries, studyItems: studyItems)
        )
        let durationMs = max(0, Date().timeIntervalSince(startedAt) * 1_000)
        let report = CanonicalShadowReportBuilder().build(
            runID: syncRunID,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeID: deviceID,
            nodeRole: .iphone,
            generatedAt: generatedAt,
            durationMs: durationMs,
            manifest: canonicalManifest,
            legacy: legacy
        )

        do {
            let rootURL = try audioFileStore.baseDirectory()
            let logURL = rootURL
                .appendingPathComponent("Diagnostics", isDirectory: true)
                .appendingPathComponent("canonical-shadow.jsonl", isDirectory: false)
            try CanonicalShadowReportJSONLWriter().append(report, to: logURL)
            diagnosticsStore.record(
                phase: "canonicalShadowReportWritten",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "objects=\(report.canonicalObjectCount),mismatches=\(report.comparison.mismatches.count)"
            )
        } catch {
            diagnosticsStore.record(
                phase: "canonicalShadowReportWriteFailed",
                deviceID: deviceID,
                syncRunID: syncRunID,
                errorCode: "canonical_shadow_write_failed",
                errorMessage: error.localizedDescription
            )
        }

        diagnosticsStore.record(
            phase: "canonicalShadowBuildCompleted",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "objects=\(report.canonicalObjectCount),legacyRecordings=\(report.legacyRecordingCount)"
        )
        diagnosticsStore.record(
            phase: "canonicalShadowBuildDurationMs",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "\(Int(durationMs.rounded()))"
        )
        recordCanonicalShadowDiagnostics(report, deviceID: deviceID, syncRunID: syncRunID)
    }

    private func canonicalAudioFact(from entry: LocalNetworkSyncRecordingEntry) -> CanonicalArtifactFact {
        let availability: CanonicalArtifact.Availability
        if entry.audioAvailability == .missing || (!entry.audioAvailable && entry.audioSize == nil && entry.audioChecksum == nil) {
            availability = .missing
        } else if entry.audioAvailable, entry.audioChecksum != nil, entry.audioSize != nil {
            availability = .available
        } else {
            availability = .availableWithoutHash
        }
        let contentHash = entry.audioChecksum.map { CanonicalHash($0) }
        return CanonicalArtifactFact.audio(
            availability: availability,
            contentHash: contentHash,
            byteSize: entry.audioSize,
            logicalName: logicalName(from: entry.audioLogicalPathToken),
            logicalPathToken: entry.audioLogicalPathToken,
            producedByNodeID: entry.sourceDeviceID
        )
    }

    private func canonicalGeneratedArtifact(
        from artifact: LocalNetworkSyncArtifactEntry,
        nodeID: String,
        platform: String
    ) -> CanonicalArtifact? {
        guard let kind = canonicalGeneratedArtifactKind(from: artifact.kind) else {
            return nil
        }
        let availability = canonicalAvailability(from: artifact.availability, checksum: artifact.checksum, size: artifact.size)
        return CanonicalProjectionContract.makeArtifact(
            objectID: artifact.ownerID,
            kind: kind,
            availability: availability,
            contentHash: artifact.checksum.map { CanonicalHash($0) },
            byteSize: artifact.size,
            logicalPathToken: artifact.logicalPathToken,
            modifiedAt: CanonicalTimestamp(artifact.updatedAt),
            observedAt: CanonicalTimestamp(artifact.updatedAt),
            producedByNodeID: platform.lowercased().contains("mac") ? nodeID : nil,
            platform: platform
        )
    }

    private func canonicalGeneratedArtifactKind(from kind: LocalNetworkSyncArtifactKind) -> CanonicalArtifact.Kind? {
        switch kind {
        case .transcriptJSON:
            return .transcriptJSON
        case .transcriptMarkdown:
            return .transcriptMarkdown
        case .noteMarkdown:
            return .noteMarkdown
        case .noteJSON:
            return .noteJSON
        case .summaryJSON:
            return .summaryJSON
        case .metadataJSON, .receiveJSON, .summaryMarkdown, .audio:
            return nil
        }
    }

    private func canonicalAvailability(
        from availability: LocalNetworkSyncArtifactAvailability,
        checksum: String?,
        size: Int64?
    ) -> CanonicalArtifact.Availability {
        switch availability {
        case .local, .availableOnPeer, .complete:
            return checksum != nil && size != nil ? .available : .availableWithoutHash
        case .missing:
            return .missing
        case .transferring:
            return .unknown
        }
    }

    private func legacyObjectFacts(
        recordingEntries: [LocalNetworkSyncRecordingEntry],
        studyItems: [LocalNetworkSyncStudyItemEntry]
    ) -> [CanonicalShadowLegacyObjectFact] {
        let itemIDsByRecordingID = Dictionary(grouping: studyItems.compactMap { item -> String? in
            normalizedNonEmpty(item.recordingID)
        }) { $0 }
        let recordingFacts = recordingEntries.map { entry in
            CanonicalShadowLegacyObjectFact(
                objectID: entry.recordingID,
                legacyMetadataHash: entry.metadataHash,
                audioHash: entry.audioChecksum,
                audioByteSize: entry.audioSize,
                audioAvailability: entry.audioAvailability?.rawValue ?? (entry.audioAvailable ? "local" : "missing"),
                hasRecordingMetadata: true,
                hasReceiveRecord: entry.receiveStatus != nil,
                hasStudyItem: itemIDsByRecordingID[entry.recordingID] != nil
            )
        }
        let studyItemFacts = studyItems.compactMap { item -> CanonicalShadowLegacyObjectFact? in
            guard let recordingID = normalizedNonEmpty(item.recordingID) else {
                return nil
            }
            return CanonicalShadowLegacyObjectFact(
                objectID: recordingID,
                legacyMetadataHash: item.revisionHash,
                hasStudyItem: true
            )
        }
        return recordingFacts + studyItemFacts
    }

    private func recordCanonicalShadowDiagnostics(
        _ report: CanonicalShadowReport,
        deviceID: String,
        syncRunID: String?
    ) {
        if !report.comparison.metadataHashConvergedObjectIDs.isEmpty {
            diagnosticsStore.record(
                phase: "canonicalShadowMetadataHashConverged",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "count=\(report.comparison.metadataHashConvergedObjectIDs.count)"
            )
        }
        let grouped = Dictionary(grouping: report.comparison.mismatches) { $0.category }
        for (category, mismatches) in grouped {
            diagnosticsStore.record(
                phase: "canonicalShadowLegacyMismatchDetected",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "category=\(category.rawValue),count=\(mismatches.count)"
            )
            switch category {
            case .studyItemOnlyWithoutReceiveRecord:
                diagnosticsStore.record(phase: "canonicalShadowStudyItemOnlyWithoutReceiveRecord", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            case .canonicalMetadataHashConverged:
                diagnosticsStore.record(phase: "canonicalShadowMetadataHashConverged", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            case .canonicalCreatedAtIgnoredForMetadataHash:
                diagnosticsStore.record(phase: "canonicalShadowCreatedAtIgnoredForMetadataHash", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            case .canonicalModifiedAtIgnoredProcessingState:
                diagnosticsStore.record(phase: "canonicalShadowModifiedAtIgnoredProcessingState", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            case .canonicalMacUpdatedAtRejectedAsProcessingClock:
                diagnosticsStore.record(phase: "canonicalShadowMacUpdatedAtRejectedAsProcessingClock", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            case .canonicalBusinessModifiedAtUsed:
                diagnosticsStore.record(phase: "canonicalShadowBusinessModifiedAtUsed", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            case .canonicalMetadataHashMismatch, .legacyMetadataHashMismatchButCanonicalHashMatch:
                diagnosticsStore.record(phase: "canonicalShadowMetadataHashDiverged", deviceID: deviceID, syncRunID: syncRunID, result: "category=\(category.rawValue),count=\(mismatches.count)")
            case .canonicalAudioConflict:
                diagnosticsStore.record(phase: "canonicalShadowAudioConflictDetected", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            case .canonicalGeneratedArtifactPeerSameNoOp:
                diagnosticsStore.record(phase: "canonicalShadowGeneratedArtifactPeerSameNoOp", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            case .canonicalGeneratedArtifactPeerUnknownDeferred:
                diagnosticsStore.record(phase: "canonicalShadowGeneratedArtifactPeerUnknownDeferred", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            case .canonicalGeneratedArtifactConflict:
                diagnosticsStore.record(phase: "canonicalShadowGeneratedArtifactConflict", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(mismatches.count)")
            default:
                break
            }
        }
    }

    private func recordCanonicalInventoryCoverage(
        _ coverage: CanonicalInventoryCoverageReport,
        deviceID: String,
        syncRunID: String?
    ) {
        diagnosticsStore.record(
            phase: "canonicalInventoryCoverageReportWritten",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "recordings=\(coverage.recordingCoverage)",
                "audio=\(coverage.audioCoverage)",
                "generatedArtifacts=\(coverage.generatedArtifactCoverage)",
                "folders=\(coverage.folderCoverage)",
                "studyItems=\(coverage.studyItemCoverage)",
                "tombstones=\(coverage.tombstoneCoverage)",
                "unsupported=\(coverage.unsupportedLegacyObjectCount)",
                "fallbackRequired=\(coverage.fallbackRequiredCount)"
            ].joined(separator: ",")
        )
        if coverage.folderCoverage > 0 {
            diagnosticsStore.record(phase: "canonicalFolderProjected", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(coverage.folderCoverage)")
        }
        if coverage.studyItemCoverage > 0 {
            diagnosticsStore.record(phase: "canonicalStudyItemProjected", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(coverage.studyItemCoverage)")
        }
        if coverage.tombstoneCoverage > 0 {
            diagnosticsStore.record(phase: "canonicalLibraryTombstoneProjected", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(coverage.tombstoneCoverage)")
        }
        if coverage.unsupportedLegacyObjectCount > 0 {
            diagnosticsStore.record(phase: "canonicalLibraryObjectUnsupported", deviceID: deviceID, syncRunID: syncRunID, result: "count=\(coverage.unsupportedLegacyObjectCount)")
        }
    }

    private func recordFileKernelRuntimeDiagnostics(
        snapshot: CanonicalFileRuntimeSnapshot?,
        manifest: CanonicalFileManifestRuntimeResult?,
        deviceID: String,
        syncRunID: String?
    ) {
        guard let snapshot, let manifest else {
            return
        }
        diagnosticsStore.record(
            phase: "canonicalFileKernelSnapshotBuilt",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "rootToken=\(snapshot.scope.rootToken.rawValue)",
                "entryCount=\(snapshot.entries.count)",
                "durationMs=\(snapshot.durationMs)",
                "builtOffMain=\(snapshot.builtOffMainActor)",
                "mainActorFileTreeAttemptCount=\(snapshot.mainActorAttemptCount)",
                "redacted=\(snapshot.redacted)"
            ].joined(separator: ",")
        )
        diagnosticsStore.record(
            phase: "canonicalFileKernelManifestBuilt",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "rootToken=\(manifest.cacheKey.rootToken.rawValue)",
                "cacheKeyPrefix=\(manifest.cacheKey.cacheKeyHashPrefix)",
                "entryCount=\(manifest.manifest.entries.count)",
                "durationMs=\(manifest.durationMs)",
                "builtOffMain=\(manifest.builtOffMainActor)",
                "mainActorManifestAttemptCount=\(manifest.mainActorAttemptCount)"
            ].joined(separator: ",")
        )
    }

    private static func makeFileKernelRuntime(
        rootToken: CanonicalRootToken,
        adapter: any CanonicalFileSnapshotRuntimeAdapter
    ) async -> (snapshot: CanonicalFileRuntimeSnapshot?, manifest: CanonicalFileManifestRuntimeResult?) {
        guard let scope = try? CanonicalFileSnapshotScope(
            rootToken: rootToken,
            logicalScopeToken: ".",
            domainHint: .studyLibraryMetadata
        ) else {
            return (nil, nil)
        }
        do {
            let snapshot = try await CanonicalFileTreeSnapshotBuilder(adapter: adapter).buildSnapshot(scope: scope)
            let manifestStartedAt = Date()
            let manifest = await Task.detached(priority: .utility) {
                CanonicalManifestRuntimeBuilder().buildFileManifest(from: snapshot)
            }.value
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .inventoryBuildMs,
                    durationMs: CanonicalPerfLog.elapsedMs(since: manifestStartedAt),
                    result: "fileKernelManifestBuild"
                )
            )
            return (snapshot, manifest)
        } catch {
            return (nil, nil)
        }
    }

    private static func fileSnapshotEntries(
        from artifacts: [LocalNetworkSyncArtifactEntry]
    ) -> [CanonicalFileSnapshotSourceEntry] {
        artifacts.compactMap { artifact in
            guard let logicalPathToken = normalizedStaticNonEmpty(artifact.logicalPathToken) else {
                return nil
            }
            return try? CanonicalFileSnapshotSourceEntry(
                logicalToken: logicalPathToken,
                kind: .file,
                byteSize: artifact.size ?? 0,
                modifiedAt: CanonicalTimestamp(artifact.updatedAt),
                contentVersion: artifact.checksum.map { String($0.prefix(12)) },
                stableFileIdentity: artifact.artifactID,
                domainHint: fileDomainHint(for: artifact.kind),
                hashProof: artifact.checksum.map { CanonicalHash($0) }
            )
        }
    }

    private static func fileDomainHint(for kind: LocalNetworkSyncArtifactKind) -> CanonicalFileDomainHint {
        switch kind {
        case .audio:
            return .recordingAudio
        case .metadataJSON:
            return .recordingMetadata
        case .receiveJSON:
            return .receiveRecord
        case .transcriptJSON, .transcriptMarkdown, .noteMarkdown, .noteJSON, .summaryJSON, .summaryMarkdown:
            return .generatedArtifact
        }
    }

    private static func normalizedStaticNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func logicalName(from token: String?) -> String? {
        normalizedNonEmpty(token)?
            .split(separator: "/")
            .last
            .map(String.init)
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func cachedRuntimeChecksum(
        fileURL: URL,
        pathToken: String?,
        deviceID: String,
        syncRunID: String?,
        recordingID: String,
        cacheDirectoryURL: URL
    ) async -> (legacyResult: LocalNetworkChecksumCacheResult?, runtimeResult: CanonicalChecksumCacheResult) {
        let result = await canonicalChecksumCache.checksum(
            fileURL: fileURL,
            logicalToken: pathToken,
            nodeRole: .iPhone,
            cacheDirectoryURL: cacheDirectoryURL,
            configuration: runtimeConfiguration
        )
        let safeRecording = String(recordingID.prefix(12))
        let safePath = String((pathToken ?? "missing").prefix(12))
        switch result.event {
        case .hit:
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeCacheHit",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath),size=\(result.byteSize)"
            )
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeHashSkippedDueToCacheHit",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath),hashPrefix=\(result.redactedHashPrefix ?? "missing")"
            )
            diagnosticsStore.record(
                phase: "checksumCacheHit",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath),size=\(result.byteSize)"
            )
        case .miss:
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeCacheMiss",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath),size=\(result.byteSize)"
            )
            diagnosticsStore.record(
                phase: "checksumCacheMiss",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath),size=\(result.byteSize)"
            )
        case .stale:
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeCacheStale",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath),size=\(result.byteSize)"
            )
            diagnosticsStore.record(
                phase: "checksumCacheInvalidated",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath),size=\(result.byteSize)"
            )
        case .error:
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeCacheError",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath)",
                errorCode: result.failure?.rawValue ?? "cache_error"
            )
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeHashFailed",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath)",
                errorCode: result.failure?.rawValue ?? "hash_unavailable"
            )
            diagnosticsStore.record(
                phase: "checksumCacheMiss",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath)",
                errorCode: "checksum_failed"
            )
        }
        if result.hashComputed {
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeHashComputed",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath),durationMs=\(result.hashDurationMs),hashPrefix=\(result.redactedHashPrefix ?? "missing")"
            )
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeHashStarted",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath)"
            )
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeHashCompleted",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath),durationMs=\(result.hashDurationMs)"
            )
            diagnosticsStore.record(
                phase: "checksumComputedOffMainActor",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safeRecording),path=\(safePath)"
            )
            if result.cachePersisted {
                diagnosticsStore.record(
                    phase: "canonicalInventoryRuntimeCachePersisted",
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "recording=\(safeRecording),path=\(safePath),durationMs=\(result.cacheWriteDurationMs),recordCount=\(result.cacheRecordCount)"
                )
            }
            if result.cachePrunedRecordCount > 0 {
                diagnosticsStore.record(
                    phase: "canonicalInventoryRuntimeCachePruned",
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "prunedRecordCount=\(result.cachePrunedRecordCount),durationMs=\(result.cachePruneDurationMs)"
                )
            }
        }
        guard let sha256 = result.sha256 else {
            return (nil, result)
        }
        let legacyEvent: LocalNetworkChecksumCacheEvent
        switch result.event {
        case .hit:
            legacyEvent = .hit
        case .miss, .error:
            legacyEvent = .miss
        case .stale:
            legacyEvent = .invalidated
        }
        let legacy = LocalNetworkChecksumCacheResult(
            sha256: sha256,
            size: result.byteSize,
            modifiedAt: result.modifiedAt,
            computedAt: Date(),
            event: legacyEvent
        )
        return (legacy, result)
    }

    private func canonicalChecksumCacheDirectory(rootURL: URL) -> URL {
        rootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
    }

    private func recordRuntimeSnapshotDiagnostics(
        _ snapshot: CanonicalInventoryRuntimeSnapshot,
        report: CanonicalInventoryRuntimeReport,
        deviceID: String,
        syncRunID: String?
    ) {
        diagnosticsStore.record(
            phase: "canonicalInventoryRuntimeSnapshotBuilt",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: CanonicalInventoryRuntimeReportExporter.diagnosticsSummary(from: snapshot)
        )
        diagnosticsStore.record(
            phase: "canonicalInventoryRuntimeReportWritten",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "buildDurationMs=\(report.buildDurationMs)",
                "scanDurationMs=\(report.scanDurationMs)",
                "manifestBuildDurationMs=\(report.manifestBuildDurationMs)",
                "metadataLoadDurationMs=\(report.metadataLoadDurationMs)",
                "jobsLoadDurationMs=\(report.jobsLoadDurationMs)",
                "fileScanDurationMs=\(report.fileScanDurationMs)",
                "hashDurationMs=\(report.hashDurationMs)",
                "cacheLoadDurationMs=\(report.cacheLoadDurationMs)",
                "cacheWriteDurationMs=\(report.cacheWriteDurationMs)",
                "cachePruneDurationMs=\(report.cachePruneDurationMs)",
                "cacheHitCount=\(report.cacheHitCount)",
                "cacheMissCount=\(report.cacheMissCount)",
                "cacheStaleCount=\(report.cacheStaleCount)",
                "cacheErrorCount=\(report.cacheErrorCount)",
                "hashComputedCount=\(report.hashComputedCount)",
                "hashSkippedByCacheHitCount=\(report.hashSkippedByCacheHitCount)",
                "hashFailedCount=\(report.hashFailedCount)",
                "hashUnavailableCount=\(report.hashUnavailableCount)",
                "duplicateBuildCount=\(report.duplicateBuildCount)",
                "duplicateSnapshotBuildCount=\(report.duplicateBuildCount)",
                "snapshotReuseCount=\(report.snapshotReuseCount)",
                "mainActorHashAttemptCount=\(report.mainActorHashAttemptCount)",
                "mainActorScanAttemptCount=\(report.mainActorScanAttemptCount)",
                "mainActorMetadataLoadAttemptCount=\(report.mainActorMetadataLoadAttemptCount)",
                "mainActorJobsLoadAttemptCount=\(report.mainActorJobsLoadAttemptCount)",
                "mainActorManifestBuildAttemptCount=\(report.mainActorManifestBuildAttemptCount)",
                "mainActorHashBlockedCount=\(report.mainActorHashBlockedCount)",
                "mainActorScanBlockedCount=\(report.mainActorScanBlockedCount)",
                "redactionViolationCount=\(report.redactionViolationCount)",
                "redacted=\(report.redacted)"
            ].joined(separator: ",")
        )
    }

}

@MainActor
final class LocalNetworkSyncEngine {
    private static let maxSmallArtifactUploadBytes: Int64 = 4 * 1024 * 1024
    private static let artifactChunkBytes = 2 * 1024 * 1024

    private let connectionStore: any SecureMacConnectionSnapshotProviding
    private let inventoryBuilder: LocalNetworkSyncInventoryBuilder
    private let audioFileStore: AudioFileStore
    private let studyLibraryStore: StudyLibraryStore
    private weak var recordingManager: RecordingManager?
    private let uploadCoordinator: RecordingUploadCoordinator?
    private let client: any LocalNetworkSyncClientProtocol
    private let stateStore: LocalNetworkSyncStateStore
    private let progressStore: LocalNetworkSyncProgressStore?
    private let transferJobStore: LocalNetworkSyncTransferJobStore
    private let uploadJobStore: RecordingUploadJobStore
    private let connectionStatusStore: DeviceConnectionStatusStore?
    private let diagnosticsStore: ConnectionDiagnosticsStore
    private let diffPlanner: LocalNetworkSyncDiffPlanner
    private let canonicalShadowMigrationConfiguration: CanonicalShadowMigrationConfiguration
    private let canonicalSingleDomainShadowConfiguration: CanonicalSingleDomainShadowConfiguration
    private let canonicalV8CutoverAppSeamConfiguration: CanonicalCutoverAppSeamConfiguration
    private let canonicalGeneratedArtifactCutoverAppSeamConfiguration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration
    private let canonicalGeneratedArtifactReadSideConfiguration: CanonicalGeneratedArtifactReadSideConfiguration
    private let canonicalLibraryMetadataCutoverAppSeamConfiguration: CanonicalLibraryMetadataCutoverAppSeamConfiguration
    private var canonicalLibraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration
    private let canonicalLibraryMetadataReadSideCutoverConfiguration: CanonicalLibraryMetadataReadSideCutoverConfiguration
    private let canonicalAudioUploadCutoverAppSeamConfiguration: CanonicalAudioUploadCutoverAppSeamConfiguration
    private let canonicalTombstoneConflictCutoverAppSeamConfiguration: CanonicalTombstoneConflictCutoverAppSeamConfiguration
    private var canonicalSyncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration
    private var canonicalApplyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration
    private let canonicalKernelSwitchResultProvider: (() -> CanonicalKernelSwitchResult)?
    private let canonicalLiveReadOnlyTransportProbePolicy: CanonicalLiveReadOnlyTransportProbePolicy
    private let canonicalLiveReadOnlyTransportProbeSender: (any IPhoneCanonicalReadOnlyProbeSending)?
    private let canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime
    private let canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime
    private let canonicalChecksumRuntime = CanonicalChecksumRuntime()
    private let canonicalChecksumRuntimeConfiguration = CanonicalInventoryRuntimeConfiguration()
    private var canonicalRecordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)?
    private var canonicalGeneratedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    private var canonicalLibraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)?
    private var canonicalTombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)?
    private(set) var isSyncing = false

    init(
        connectionStore: any SecureMacConnectionSnapshotProviding,
        audioFileStore: AudioFileStore,
        studyLibraryStore: StudyLibraryStore,
        recordingManager: RecordingManager? = nil,
        uploadCoordinator: RecordingUploadCoordinator? = nil,
        uploadJobStore: RecordingUploadJobStore,
        client: (any LocalNetworkSyncClientProtocol)? = nil,
        stateStore: LocalNetworkSyncStateStore? = nil,
        progressStore: LocalNetworkSyncProgressStore? = .shared,
        transferJobStore: LocalNetworkSyncTransferJobStore? = nil,
        connectionStatusStore: DeviceConnectionStatusStore? = nil,
        diagnosticsStore: ConnectionDiagnosticsStore? = nil,
        diffPlanner: LocalNetworkSyncDiffPlanner? = nil,
        canonicalShadowMigrationConfiguration: CanonicalShadowMigrationConfiguration = .disabled,
        canonicalSingleDomainShadowConfiguration: CanonicalSingleDomainShadowConfiguration = .disabled,
        canonicalV8CutoverAppSeamConfiguration: CanonicalCutoverAppSeamConfiguration = .disabled,
        canonicalGeneratedArtifactCutoverAppSeamConfiguration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration = .disabled,
        canonicalGeneratedArtifactReadSideConfiguration: CanonicalGeneratedArtifactReadSideConfiguration = .disabled,
        canonicalLibraryMetadataCutoverAppSeamConfiguration: CanonicalLibraryMetadataCutoverAppSeamConfiguration = .disabled,
        canonicalLibraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration = .disabled,
        canonicalLibraryMetadataReadSideCutoverConfiguration: CanonicalLibraryMetadataReadSideCutoverConfiguration = .disabled,
        canonicalAudioUploadCutoverAppSeamConfiguration: CanonicalAudioUploadCutoverAppSeamConfiguration = .disabled,
        canonicalTombstoneConflictCutoverAppSeamConfiguration: CanonicalTombstoneConflictCutoverAppSeamConfiguration = .disabled,
        canonicalSyncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration = .disabled,
        canonicalApplyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration = .disabled,
        canonicalKernelSwitchResultProvider: (() -> CanonicalKernelSwitchResult)? = nil,
        canonicalLiveReadOnlyTransportProbePolicy: CanonicalLiveReadOnlyTransportProbePolicy = .disabled,
        canonicalLiveReadOnlyTransportProbeSender: (any IPhoneCanonicalReadOnlyProbeSending)? = nil,
        canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime? = nil,
        canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime? = nil,
        canonicalRecordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)? = nil,
        canonicalGeneratedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)? = nil,
        canonicalLibraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)? = nil,
        canonicalTombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)? = nil
    ) {
        let resolvedClient = client ?? SecureMacUploadClient()
        let canonicalKernelSwitchResult = canonicalKernelSwitchResultProvider?()
        let resolvedStatusTruthRuntime = canonicalStatusTruthRuntime ?? CanonicalStatusTruthRuntime()
        let resolvedStatusExchangeRuntime = canonicalStatusExchangeRuntime ?? CanonicalStatusExchangeRuntime(
            nodeID: CanonicalNodeID("iphone-\(connectionStore.snapshot.deviceID)"),
            truthRuntime: resolvedStatusTruthRuntime
        )
        self.connectionStore = connectionStore
        self.audioFileStore = audioFileStore
        self.studyLibraryStore = studyLibraryStore
        self.recordingManager = recordingManager
        self.uploadCoordinator = uploadCoordinator
        self.client = resolvedClient
        self.stateStore = stateStore ?? LocalNetworkSyncStateStore(rootURL: try? audioFileStore.baseDirectory())
        self.progressStore = progressStore
        self.transferJobStore = transferJobStore ?? LocalNetworkSyncTransferJobStore(rootURL: try? audioFileStore.baseDirectory())
        self.uploadJobStore = uploadJobStore
        self.connectionStatusStore = connectionStatusStore
        self.diagnosticsStore = diagnosticsStore ?? .shared
        self.diffPlanner = diffPlanner ?? LocalNetworkSyncDiffPlanner()
        self.canonicalShadowMigrationConfiguration = canonicalShadowMigrationConfiguration
        self.canonicalSingleDomainShadowConfiguration = canonicalSingleDomainShadowConfiguration
        self.canonicalV8CutoverAppSeamConfiguration = canonicalV8CutoverAppSeamConfiguration
        self.canonicalGeneratedArtifactCutoverAppSeamConfiguration = canonicalGeneratedArtifactCutoverAppSeamConfiguration
        self.canonicalGeneratedArtifactReadSideConfiguration = canonicalGeneratedArtifactReadSideConfiguration
        self.canonicalLibraryMetadataCutoverAppSeamConfiguration = canonicalLibraryMetadataCutoverAppSeamConfiguration
        let productionPortInjection = canonicalKernelSwitchResult.map {
            IPhoneCanonicalProductionPortFactory.make(
                result: $0,
                productionRootURL: studyLibraryStore.libraryRootURL
            )
        }
        if let productionPortInjection {
            self.canonicalLibraryMetadataDebugPilotConfiguration = productionPortInjection.libraryMetadataDebugPilotConfiguration
            self.canonicalRecordingMetadataCutoverExecutor = productionPortInjection.recordingMetadataCutoverExecutor
            self.canonicalGeneratedArtifactCutoverExecutor = productionPortInjection.generatedArtifactCutoverExecutor
            self.canonicalLibraryMetadataCutoverExecutor = productionPortInjection.libraryMetadataCutoverExecutor
            self.canonicalTombstoneConflictCutoverExecutor = productionPortInjection.tombstoneConflictCutoverExecutor
        } else {
            self.canonicalLibraryMetadataDebugPilotConfiguration = canonicalLibraryMetadataDebugPilotConfiguration
            self.canonicalRecordingMetadataCutoverExecutor = canonicalRecordingMetadataCutoverExecutor
            self.canonicalGeneratedArtifactCutoverExecutor = canonicalGeneratedArtifactCutoverExecutor
            self.canonicalLibraryMetadataCutoverExecutor = canonicalLibraryMetadataCutoverExecutor
            self.canonicalTombstoneConflictCutoverExecutor = canonicalTombstoneConflictCutoverExecutor
        }
        self.canonicalLibraryMetadataReadSideCutoverConfiguration = canonicalLibraryMetadataReadSideCutoverConfiguration
        self.canonicalAudioUploadCutoverAppSeamConfiguration = canonicalAudioUploadCutoverAppSeamConfiguration
        self.canonicalTombstoneConflictCutoverAppSeamConfiguration = canonicalTombstoneConflictCutoverAppSeamConfiguration
        self.canonicalSyncRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.syncRuntimeConfiguration ?? canonicalSyncRuntimeConfiguration
        self.canonicalApplyRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.applyRuntimeConfiguration ?? canonicalApplyRuntimeConfiguration
        self.canonicalKernelSwitchResultProvider = canonicalKernelSwitchResultProvider
        self.canonicalLiveReadOnlyTransportProbePolicy = canonicalLiveReadOnlyTransportProbePolicy
        if let canonicalLiveReadOnlyTransportProbeSender {
            self.canonicalLiveReadOnlyTransportProbeSender = canonicalLiveReadOnlyTransportProbeSender
        } else if let secureClient = resolvedClient as? SecureMacUploadClient {
            self.canonicalLiveReadOnlyTransportProbeSender = IPhoneCanonicalReadOnlyTransportProbeSender(client: secureClient)
        } else {
            self.canonicalLiveReadOnlyTransportProbeSender = nil
        }
        self.canonicalStatusTruthRuntime = resolvedStatusTruthRuntime
        self.canonicalStatusExchangeRuntime = resolvedStatusExchangeRuntime
        self.inventoryBuilder = LocalNetworkSyncInventoryBuilder(
            audioFileStore: audioFileStore,
            studyLibraryStore: studyLibraryStore,
            uploadJobStore: uploadJobStore,
            diagnosticsStore: self.diagnosticsStore
        )
        if let readRuntimeConfiguration = canonicalKernelSwitchResult?.effectiveConfiguration.readRuntimeConfiguration {
            studyLibraryStore.setCanonicalReadRuntimeConfiguration(
                canonicalMasterSwitchReadConfigurationForStore(readRuntimeConfiguration)
            )
        }
    }

    private func recordControlPlane(
        deviceID: String,
        syncRunID: String,
        state controlPlaneState: LocalNetworkSyncControlPlaneState,
        at date: Date = Date()
    ) {
        stateStore.recordControlPlane(syncRunID: syncRunID, state: controlPlaneState, at: date)
        progressStore?.record(
            deviceID: deviceID,
            syncRunID: syncRunID,
            state: controlPlaneState,
            at: date
        )
    }

    @discardableResult
    func performTick(
        trigger: String,
        now: Date = Date(),
        bypassBackoff: Bool = false,
        syncRunID providedSyncRunID: String? = nil
    ) async -> LocalNetworkSyncDiffPlan? {
        let snapshot = connectionStore.snapshot
        let syncRunID = providedSyncRunID ?? UUID().uuidString
        let triggerSource = RecordingAudioSyncTriggerSource(syncTrigger: trigger)
        if providedSyncRunID == nil {
            diagnosticsStore.record(phase: "syncRunIDCreated", deviceID: snapshot.deviceID, syncRunID: syncRunID)
        }
        refreshCanonicalKernelSwitchConfiguration(syncRunID: syncRunID)
        guard !shouldDeferSyncBecauseUploadActive(
            trigger: trigger,
            deviceID: snapshot.deviceID,
            syncRunID: syncRunID
        ) else {
            return nil
        }
        let bypassBackoffForTrigger = bypassBackoff || Self.isManualTrigger(trigger)
        guard !isSyncing else {
            diagnosticsStore.record(
                phase: "syncSkippedReason",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "alreadyInFlight",
                errorCode: "already_in_flight"
            )
            return nil
        }
        if !bypassBackoffForTrigger,
           let nextAllowedSyncAt = stateStore.state.nextAllowedSyncAt,
           nextAllowedSyncAt > now {
            diagnosticsStore.record(
                phase: "syncSkippedBackoff",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "backoff_until=\(nextAllowedSyncAt.timeIntervalSince1970)",
                errorCode: "backoff"
            )
            diagnosticsStore.record(
                phase: "syncSkippedReason",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "backoff",
                errorCode: "backoff"
            )
            return nil
        }

        guard snapshot.isPaired else {
            diagnosticsStore.record(phase: "syncSkippedOffline", deviceID: snapshot.deviceID, syncRunID: syncRunID, errorCode: "not_paired")
            diagnosticsStore.record(phase: "syncSkippedReason", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: "not_paired", errorCode: "not_paired")
            stateStore.recordFailure(code: "not_paired", message: "Mac is not paired.", at: now)
            return nil
        }
        if (connectionStore as? SecureMacConnectionIntentProviding)?.userConnectionIntent == .disconnectedByUser {
            diagnosticsStore.record(
                phase: "syncSkippedBecauseUserDoesNotWantConnection",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                errorCode: "user_does_not_want_connection"
            )
            diagnosticsStore.record(
                phase: "syncSkippedReason",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "user_does_not_want_connection",
                errorCode: "user_does_not_want_connection"
            )
            stateStore.recordFailure(
                code: "user_does_not_want_connection",
                message: "User does not want a local network connection.",
                at: now
            )
            return nil
        }
        if let connectionStatusStore {
            guard let status = connectionStatusStore.status(for: snapshot.deviceID, now: now),
                  status.presenceSnapshot(now: now).isOnline else {
                let presence = connectionStatusStore.status(for: snapshot.deviceID, now: now)?.presenceSnapshot(now: now).state.rawValue ?? "unknown"
                diagnosticsStore.record(
                    phase: "syncSkippedOffline",
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    errorCode: "presence_not_online",
                    errorMessage: presence
                )
                diagnosticsStore.record(
                    phase: "syncSkippedReason",
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    result: "presence_not_online",
                    errorCode: "presence_not_online",
                    errorMessage: presence
                )
                stateStore.recordFailure(
                    code: "presence_not_online",
                    message: "Mac presence is \(presence).",
                    at: now
                )
                return nil
            }
        }
        if let status = connectionStatusStore?.status(for: snapshot.deviceID, now: now),
           status.presenceState == .disconnected || status.presenceState == .securityError {
            let errorCode = status.presenceState == .securityError ? "connection_security_error" : "connection_disconnected"
            diagnosticsStore.record(
                phase: "syncSkippedReason",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: errorCode,
                errorCode: errorCode,
                errorMessage: status.lastError
            )
            stateStore.recordFailure(
                code: errorCode,
                message: status.lastError ?? "Mac connection is not available for sync.",
                at: now
            )
            return nil
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            recordControlPlane(deviceID: snapshot.deviceID, syncRunID: syncRunID, state: .syncStartAcked, at: now)
            diagnosticsStore.record(phase: "syncRunStarted", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: trigger)
            diagnosticsStore.record(phase: "syncTickStarted", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: trigger)
            recordControlPlane(deviceID: snapshot.deviceID, syncRunID: syncRunID, state: .inventoryExchanging)
            let localRuntimeBuild = await inventoryBuilder.buildRuntimeSnapshot(
                deviceID: snapshot.deviceID,
                deviceName: UIDevice.current.name,
                lastKnownPeerRevision: stateStore.state.lastPeerInventoryHash,
                generatedAt: now,
                shadowTrigger: trigger,
                shadowSyncRunID: syncRunID,
                sourceKind: .syncTick
            )
            let localInventory = localRuntimeBuild.inventory
            diagnosticsStore.record(
                phase: "localInventoryBuilt",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "objectCount=\(localInventory.objects.count),recordings:\(localInventory.recordings.count),items:\(localInventory.studyItems.count),artifacts:\(localInventory.artifacts.count)"
            )
            await produceCanonicalStatusFactsFromLocalInventory(
                localInventory,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let outgoingStatusEnvelope = await canonicalStatusExchangeRuntime.makeOutgoingEnvelope(
                carrier: .inventory
            )
            if outgoingStatusEnvelope != nil {
                diagnosticsStore.record(
                    phase: "statusEnvelopeCarriedOverInventory",
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    result: "request"
                )
                if outgoingStatusEnvelope?.delta != nil {
                    diagnosticsStore.record(phase: "statusDeltaSent", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: "inventory")
                }
                if outgoingStatusEnvelope?.ack != nil {
                    diagnosticsStore.record(phase: "statusAckSent", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: "inventory")
                }
                if outgoingStatusEnvelope?.request != nil {
                    diagnosticsStore.record(phase: "statusRequestSent", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: "inventory")
                }
            }
            let peerResponse = try await client.fetchLocalNetworkSyncInventory(
                settings: snapshot,
                localInventory: localInventory,
                syncRunID: syncRunID,
                statusExchangeEnvelope: outgoingStatusEnvelope
            )
            guard peerResponse.ok, let peerInventory = peerResponse.inventory else {
                throw SecureMacUploadError.serverRejected(peerResponse.error ?? "sync_inventory_missing")
            }
            await consumeCanonicalInventoryStatusExchangeEnvelope(
                peerResponse.statusExchangeEnvelope,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            await produceCanonicalStatusFactsFromPeerInventory(
                localInventory: localInventory,
                peerInventory: peerInventory,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            diagnosticsStore.record(
                phase: "peerInventoryFetched",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "objectCount=\(peerInventory.objects.count),recordings:\(peerInventory.recordings.count),items:\(peerInventory.studyItems.count),artifacts:\(peerInventory.artifacts.count)"
            )

            recordControlPlane(deviceID: snapshot.deviceID, syncRunID: syncRunID, state: .planningTransfers)
            let lastSuccessfulSyncAt = stateStore.state.lastSuccessfulSyncAt
            let legacyPlan = await Self.makeDiffPlanOffMain(
                local: localInventory,
                peer: peerInventory,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                diagnosticsStore: diagnosticsStore
            )
            recordCanonicalShadowMigrationIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                generatedAt: now
            )
            recordCanonicalV8CutoverNoCommitSeamIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let canonicalRecordingMetadataCanaryResult = await recordCanonicalV86GuardedCommitSeamIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            recordCanonicalGeneratedArtifactNoCommitSeamIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            recordCanonicalGeneratedArtifactReadSideSeamIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            recordCanonicalGeneratedArtifactGuardedCommitSeamIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let canonicalTombstoneConflictCanaryResult = await recordCanonicalTombstoneConflictCutoverSeamIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            recordCanonicalLibraryMetadataNoCommitSeamIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            recordCanonicalLibraryMetadataReadSideSeamIfEnabled(
                localInventory: localInventory,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            recordCanonicalAudioUploadCutoverPreparationSeamIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            refreshCanonicalReadRuntimeProjection(
                localInventory: localInventory,
                peerInventory: peerInventory,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            recordCanonicalRecordingExistenceTruthDiagnostics(
                localInventory: localInventory,
                peerInventory: peerInventory,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let canonicalGeneratedArtifactCanaryResult = await recordCanonicalGeneratedArtifactCutoverSeamIfEnabled(
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let canonicalLibraryMetadataCanaryResult: CanonicalLibraryMetadataCutoverResult?
            if canonicalLibraryMetadataDebugPilotConfiguration.mode.isConfigured {
                canonicalLibraryMetadataCanaryResult = await recordCanonicalLibraryMetadataLandingPilotIfConfigured(
                    localInventory: localInventory,
                    peerInventory: peerInventory,
                    triggerSource: triggerSource,
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID
                )
            } else {
                canonicalLibraryMetadataCanaryResult = await recordCanonicalLibraryMetadataCutoverSeamIfEnabled(
                    localInventory: localInventory,
                    peerInventory: peerInventory,
                    legacyPlan: legacyPlan,
                    triggerSource: triggerSource,
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID
                )
            }
            await recordCanonicalLiveReadOnlyProbeIfEnabled(
                settings: snapshot,
                localInventory: localInventory,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                generatedAt: now
            )
            let planBeforeCanarySuppression = await canonicalSyncRuntimePlan(
                localRuntimeSnapshot: localRuntimeBuild.snapshot,
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let canonicalApplyRuntimeResult = await executeCanonicalApplyRuntimeIfConfigured(
                localRuntimeSnapshot: localRuntimeBuild.snapshot,
                localInventory: localInventory,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                triggerSource: triggerSource,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let applyRuntimeSuppressedPlan = suppressCanonicalApplyRuntimeDuplicateLegacyActions(
                in: planBeforeCanarySuppression,
                runtimeResult: canonicalApplyRuntimeResult,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let recordingMetadataSuppressedPlan = suppressCanonicalRecordingMetadataDuplicateLegacyActions(
                in: applyRuntimeSuppressedPlan,
                cutoverResult: canonicalRecordingMetadataCanaryResult,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let generatedArtifactSuppressedPlan = suppressCanonicalGeneratedArtifactDuplicateLegacyActions(
                in: recordingMetadataSuppressedPlan,
                cutoverResult: canonicalGeneratedArtifactCanaryResult,
                peerInventory: peerInventory,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let libraryMetadataSuppressedPlan = suppressCanonicalLibraryMetadataDuplicateLegacyActions(
                in: generatedArtifactSuppressedPlan,
                cutoverResult: canonicalLibraryMetadataCanaryResult,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let plan = suppressCanonicalTombstoneConflictDuplicateLegacyActions(
                in: libraryMetadataSuppressedPlan,
                cutoverResult: canonicalTombstoneConflictCanaryResult,
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID
            )
            let contentUploadActionCount = plan.uploadRecordingAudioActions.count + plan.uploadArtifactActions.count
            let contentDownloadActionCount = plan.downloadArtifactActions.count
            let pendingUploadCount = plan.uploadMetadataActions.count
            let pendingDownloadCount = plan.downloadMetadataActions.count
            let skippedContentActionCount = contentUploadActionCount + contentDownloadActionCount
            diagnosticsStore.record(
                phase: "diffPlanCreated",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "metadataActionCount=\(pendingUploadCount + pendingDownloadCount),skippedContentActionCount=\(skippedContentActionCount),uploadMetadata:\(plan.uploadMetadataActions.count),uploadAudioSkipped:\(plan.uploadRecordingAudioActions.count),uploadArtifactsSkipped:\(plan.uploadArtifactActions.count),downloadMetadata:\(plan.downloadMetadataActions.count),downloadArtifactsSkipped:\(plan.downloadArtifactActions.count),conflicts:\(plan.conflictActions.count)",
                pendingUploadCount: pendingUploadCount,
                pendingDownloadCount: pendingDownloadCount
            )
            diagnosticsStore.record(
                phase: "bidirectionalDiffPlanCreated",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "metadataActionCount=\(pendingUploadCount + pendingDownloadCount),uploadMetadata:\(pendingUploadCount),downloadMetadata:\(pendingDownloadCount),skippedContent:\(skippedContentActionCount),conflicts:\(plan.conflictActions.count)",
                pendingUploadCount: pendingUploadCount,
                pendingDownloadCount: pendingDownloadCount
            )
            diagnosticsStore.record(
                phase: "transferPlanCreated",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "metadataUpload:\(pendingUploadCount),metadataDownload:\(pendingDownloadCount),contentSkipped:\(skippedContentActionCount),conflict:\(plan.conflictActions.count)",
                pendingUploadCount: pendingUploadCount,
                pendingDownloadCount: pendingDownloadCount
            )
            if skippedContentActionCount > 0 {
                diagnosticsStore.record(
                    phase: "contentTransferSkippedForStructureSync",
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    result: "uploadAudio:\(plan.uploadRecordingAudioActions.count),uploadArtifacts:\(plan.uploadArtifactActions.count),downloadArtifacts:\(plan.downloadArtifactActions.count)"
                )
            }
            recordControlPlane(deviceID: snapshot.deviceID, syncRunID: syncRunID, state: .transferJobsCreated)
            if pendingUploadCount == 0, pendingDownloadCount == 0, plan.conflictActions.isEmpty {
                diagnosticsStore.record(phase: "noTransferNeeded", deviceID: snapshot.deviceID, syncRunID: syncRunID)
            }
            recordWeakCompareDiagnostics(localInventory: localInventory, peerInventory: peerInventory, plan: plan, deviceID: snapshot.deviceID, syncRunID: syncRunID)
            recordRecordingAudioAvailabilityDiagnostics(localInventory: localInventory, peerInventory: peerInventory, deviceID: snapshot.deviceID, syncRunID: syncRunID, triggerSource: triggerSource)
            for action in plan.uploadRecordingAudioActions {
                diagnosticsStore.record(
                    phase: "existingUploadActionCreated",
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    result: "recordingID=\(action.entityID)"
                )
            }
            if !plan.conflictActions.isEmpty {
                recordConflictDiagnostics(localInventory: localInventory, peerInventory: peerInventory, plan: plan, deviceID: snapshot.deviceID, syncRunID: syncRunID)
            }
            stateStore.recordAttempt(
                localDeviceID: localInventory.device.deviceID,
                peerDeviceID: peerInventory.device.deviceID,
                localInventoryHash: localInventory.inventoryHash,
                peerInventoryHash: peerInventory.inventoryHash,
                pendingUploadCount: pendingUploadCount,
                pendingDownloadCount: pendingDownloadCount,
                planSummary: "metadataUpload:\(pendingUploadCount),metadataDownload:\(pendingDownloadCount),contentSkipped:\(skippedContentActionCount),conflict:\(plan.conflictActions.count)",
                conflictCount: plan.conflictActions.count,
                at: now
            )

            try applyPeerRecordingStatuses(peerInventory: peerInventory)
            try await applyPeerMetadataIfNeeded(peerInventory: peerInventory, plan: plan, localDeviceID: snapshot.deviceID)
            recordControlPlane(deviceID: snapshot.deviceID, syncRunID: syncRunID, state: .transferring)
            try await uploadLocalMetadataIfNeeded(
                localInventory: localInventory,
                plan: plan,
                settings: snapshot,
                syncRunID: syncRunID,
                forceSend: Self.isManualTrigger(trigger)
            )

            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeSnapshotReused",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "source=syncTick,objectCount=\(localInventory.objects.count)"
            )
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeDuplicateBuildSuppressed",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "source=syncTick,duplicateBuildCount=\(localRuntimeBuild.report.duplicateBuildCount)"
            )
            diagnosticsStore.record(
                phase: "canonicalInventoryRuntimeDuplicateBuildDetected",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "count=\(localRuntimeBuild.report.duplicateBuildCount)"
            )
            let refreshedInventory = localInventory
            stateStore.recordSuccess(
                peerDeviceID: peerInventory.device.deviceID,
                localInventoryHash: refreshedInventory.inventoryHash,
                peerInventoryHash: peerInventory.inventoryHash,
                appliedPeerRevision: peerInventory.inventoryHash,
                pendingUploadCount: 0,
                pendingDownloadCount: 0
            )
            stateStore.recordActiveTransfers([])
            connectionStatusStore?.recordSignedRequestSucceeded(
                deviceID: snapshot.deviceID,
                displayName: snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName,
                now: Date()
            )
            diagnosticsStore.record(phase: "syncTickCompleted", deviceID: snapshot.deviceID, syncRunID: syncRunID)
            diagnosticsStore.record(phase: "syncRunCompleted", deviceID: snapshot.deviceID, syncRunID: syncRunID)
            recordControlPlane(deviceID: snapshot.deviceID, syncRunID: syncRunID, state: .completed)
            return plan
        } catch {
            diagnosticsStore.record(phase: "syncTickFailed", deviceID: snapshot.deviceID, syncRunID: syncRunID, errorCode: "sync_tick_failed", errorMessage: error.localizedDescription)
            diagnosticsStore.record(phase: "syncRunFailed", deviceID: snapshot.deviceID, syncRunID: syncRunID, errorCode: "sync_tick_failed", errorMessage: error.localizedDescription)
            recordControlPlane(deviceID: snapshot.deviceID, syncRunID: syncRunID, state: .failed)
            stateStore.recordFailure(code: "sync_tick_failed", message: error.localizedDescription, at: now)
            return nil
        }
    }

    private static func isManualTrigger(_ trigger: String) -> Bool {
        let normalized = trigger.lowercased()
        return normalized.contains("manual") || normalized.contains("sync-requested")
    }

    private func shouldDeferSyncBecauseUploadActive(
        trigger: String,
        deviceID: String,
        syncRunID: String
    ) -> Bool {
        guard uploadCoordinator?.hasActiveUploadInFlight() == true else {
            return false
        }
        diagnosticsStore.record(
            phase: "syncDeferredBecauseUploadActive",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "trigger=\(trigger)",
            errorCode: "upload_active"
        )
        diagnosticsStore.record(
            phase: "syncSkippedReason",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "upload_active",
            errorCode: "upload_active"
        )
        return true
    }

    private nonisolated static func makeDiffPlanOffMain(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?,
        deviceID: String,
        syncRunID: String,
        diagnosticsStore: ConnectionDiagnosticsStore
    ) async -> LocalNetworkSyncDiffPlan {
        let startedAt = Date()
        let result = await Task.detached(priority: .utility) {
            let planStartedAt = Date()
            let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
            let plan = LocalNetworkSyncDiffPlanner().plan(
                local: local,
                peer: peer,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt
            )
            let durationMs = max(0, Int(Date().timeIntervalSince(planStartedAt) * 1_000))
            return (
                plan: plan,
                durationMs: durationMs,
                mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
            )
        }.value
        let waitDurationMs = CanonicalPerfLog.elapsedMs(since: startedAt)
        await MainActor.run {
            diagnosticsStore.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .projectionRebuildMs,
                    durationMs: result.durationMs,
                    result: "diffPlan"
                ),
                deviceID: deviceID
            )
            diagnosticsStore.record(
                phase: "diffPlanBuiltOffMain",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: [
                    "durationMs=\(result.durationMs)",
                    "waitBackgroundMs=\(waitDurationMs)",
                    "mainActorLongTaskDurationMs=\(result.mainActorLongTaskDurationMs)"
                ].joined(separator: ",")
            )
        }
        return result.plan
    }

    private nonisolated static func makeCanonicalPlannerBundleOffMain(
        local: CanonicalManifest,
        peer: CanonicalManifest,
        trigger: CanonicalSyncPlanTrigger,
        legacyContext: CanonicalSyncPlannerLegacyContext,
        deviceID: String,
        syncRunID: String,
        diagnosticsStore: ConnectionDiagnosticsStore
    ) async throws -> LocalNetworkSyncCanonicalPlannerBundle {
        let waitStartedAt = Date()
        let result = try await Task.detached(priority: .utility) {
            let startedAt = Date()
            let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
            let canonicalPlan = try CanonicalSyncPlanner().plan(
                local: local,
                peer: peer,
                trigger: trigger,
                legacyContext: legacyContext
            )
            let applyPlan = CanonicalApplyPlanner().plan(
                local: local,
                peer: peer,
                syncPlan: canonicalPlan,
                trigger: trigger,
                legacyContext: legacyContext
            )
            let libraryPlan = CanonicalLibrarySyncPlanner().plan(
                local: local,
                peer: peer,
                trigger: trigger
            )
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            return LocalNetworkSyncCanonicalPlannerBundle(
                canonicalPlan: canonicalPlan,
                applyPlan: applyPlan,
                libraryPlan: libraryPlan,
                durationMs: durationMs,
                mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
            )
        }.value
        let waitDurationMs = CanonicalPerfLog.elapsedMs(since: waitStartedAt)
        await MainActor.run {
            diagnosticsStore.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .projectionRebuildMs,
                    durationMs: result.durationMs,
                    result: "canonicalPlanner"
                ),
                deviceID: deviceID
            )
            diagnosticsStore.record(
                phase: "canonicalPlannerBuiltOffMain",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: [
                    "durationMs=\(result.durationMs)",
                    "waitBackgroundMs=\(waitDurationMs)",
                    "mainActorLongTaskDurationMs=\(result.mainActorLongTaskDurationMs)"
                ].joined(separator: ",")
            )
        }
        return result
    }

    private func recordCanonicalShadowMigrationIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String,
        generatedAt: Date
    ) {
        let shouldRecordGenericShadow = canonicalShadowMigrationConfiguration.isEnabled
            && canonicalShadowMigrationConfiguration.policy.recordDiagnostics
        let shouldRecordSingleDomainShadow = canonicalSingleDomainShadowConfiguration.isEnabled
            && canonicalSingleDomainShadowConfiguration.policy.recordDiagnostics
        guard shouldRecordGenericShadow || shouldRecordSingleDomainShadow else {
            return
        }
        let factoryOutput = IPhoneCanonicalShadowPortFactory(
            configuration: canonicalShadowMigrationConfiguration
        ).makeOutput(
            localInventory: localInventory,
            peerInventory: peerInventory,
            legacyPlan: legacyPlan,
            generatedAt: generatedAt
        )
        recordCanonicalRecordingMetadataShadowIfEnabled(
            factoryOutput: factoryOutput,
            localInventory: localInventory,
            peerInventory: peerInventory,
            legacyPlan: legacyPlan,
            triggerSource: triggerSource,
            deviceID: deviceID,
            syncRunID: syncRunID,
            generatedAt: generatedAt
        )
        guard shouldRecordGenericShadow else {
            return
        }
        if canonicalShadowMigrationConfiguration.effectiveMode.runsExecutionShadowPreparation {
            let realDataCopyResult = makeIPhoneRealDataShadowCopyIfEnabled(
                factoryOutput: factoryOutput,
                localInventory: localInventory,
                syncRunID: syncRunID
            )
            let readOnlyProbeResult = makeIPhoneReadOnlyTransportProbeIfEnabled(
                factoryOutput: factoryOutput
            )
            let result = CanonicalExecutionShadowPreparationRunner().run(
                configuration: canonicalShadowMigrationConfiguration,
                trigger: .iPhoneSyncTick,
                nodeRole: .iPhone,
                domain: .inventory,
                localSnapshot: factoryOutput.localSnapshot,
                peerSnapshot: factoryOutput.peerSnapshot,
                ports: factoryOutput.portSet,
                context: CanonicalDryRunMigrationContext(dryRunID: "iphone-execution-shadow-\(syncRunID)"),
                syncRunID: syncRunID,
                shadowRootKind: canonicalShadowMigrationConfiguration.effectiveMode == .executionShadowWithShadowFileStore ? .shadowCopy : .temporary,
                realDataShadowCopyResult: realDataCopyResult,
                readOnlyTransportProbeResult: readOnlyProbeResult,
                generatedAt: generatedAt
            )
            let safeFactorySummary = String(factoryOutput.diagnosticsSafeSummary.prefix(240))
            for event in result.report.events.prefix(canonicalShadowMigrationConfiguration.policy.maxDiagnosticsEvents) {
                let summary = [
                    event.diagnosticsSummary,
                    "source=\(triggerSource.rawValue)",
                    "factory=\(safeFactorySummary)"
                ].joined(separator: ",")
                diagnosticsStore.record(
                    phase: event.kind.rawValue,
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: summary
                )
            }
            cleanupIPhoneExecutionShadowRootIfNeeded(
                factoryOutput: factoryOutput,
                deviceID: deviceID,
                syncRunID: syncRunID
            )
            return
        }
        let result = CanonicalShadowMigrationRunner().run(
            configuration: canonicalShadowMigrationConfiguration,
            trigger: .iPhoneSyncTick,
            nodeRole: .iPhone,
            domain: .inventory,
            localSnapshot: factoryOutput.localSnapshot,
            peerSnapshot: factoryOutput.peerSnapshot,
            ports: factoryOutput.portSet,
            context: CanonicalDryRunMigrationContext(dryRunID: "iphone-shadow-\(syncRunID)"),
            syncRunID: syncRunID,
            generatedAt: generatedAt
        )
        let safeFactorySummary = String(factoryOutput.diagnosticsSafeSummary.prefix(240))
        for event in result.report.events.prefix(canonicalShadowMigrationConfiguration.policy.maxDiagnosticsEvents) {
            let summary = [
                event.diagnosticsSummary,
                "source=\(triggerSource.rawValue)",
                "factory=\(safeFactorySummary)"
            ].joined(separator: ",")
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: summary
            )
        }
    }

    private func makeIPhoneRealDataShadowCopyIfEnabled(
        factoryOutput: CanonicalShadowPortFactoryOutput,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String
    ) -> CanonicalRealDataShadowCopyResult? {
        let copyPolicy = canonicalShadowMigrationConfiguration.policy.realDataShadowCopyPolicy
        guard copyPolicy.isEnabled,
              canonicalShadowMigrationConfiguration.effectiveMode == .executionShadowWithShadowFileStore,
              let lifecycle = factoryOutput.shadowRootLifecycle else {
            return nil
        }
        let input = IPhoneCanonicalRealDataShadowCopyAdapter.Input(
            shadowRootURL: lifecycle.rootURL,
            cleanupRootID: lifecycle.rootID,
            inventory: localInventory,
            policy: copyPolicy
        )
        let result = IPhoneCanonicalRealDataShadowCopyAdapter().copy(input)
        diagnosticsStore.record(
            phase: result.completed ? "canonicalRealDataShadowCopyCompleted" : "canonicalRealDataShadowCopyFailed",
            deviceID: localInventory.device.deviceID,
            syncRunID: syncRunID,
            result: result.diagnosticsSummary,
            errorCode: result.failure?.rawValue
        )
        return result
    }

    private func makeIPhoneReadOnlyTransportProbeIfEnabled(
        factoryOutput: CanonicalShadowPortFactoryOutput
    ) -> CanonicalReadOnlyTransportProbeResult? {
        let policy = canonicalShadowMigrationConfiguration.policy.readOnlyTransportProbePolicy
        guard policy.isEnabled,
              canonicalShadowMigrationConfiguration.effectiveMode == .executionShadowWithReadOnlyTransportProbe else {
            return nil
        }
        let body = Data("{}".utf8)
        let request = CanonicalReadOnlyTransportProbeRequest(
            route: .syncInventory,
            bodyByteCount: body.count,
            bodyHash: CanonicalTransportEnvelope.hash(body),
            timestampPresent: true,
            noncePresent: true,
            signaturePresent: true,
            tlsPinningPreserved: true,
            hmacPreserved: true,
            bodyHashPreserved: true,
            manifestHashPresent: factoryOutput.localSnapshot != nil,
            manifestHashUsedAsAuth: false
        )
        return CanonicalReadOnlyTransportProbe().evaluate(request: request, policy: policy)
    }

    private func recordCanonicalLiveReadOnlyProbeIfEnabled(
        settings: SecureMacConnectionSnapshot,
        localInventory: LocalNetworkSyncInventory,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String,
        generatedAt: Date
    ) async {
        let policy = canonicalLiveReadOnlyTransportProbePolicy
        guard policy.mode != .disabled else {
            return
        }

        let result: CanonicalLiveReadOnlyTransportProbeResult
        if let sender = canonicalLiveReadOnlyTransportProbeSender {
            result = await sender.evaluateAndMaybeSend(
                settings: settings,
                policy: policy,
                localInventory: localInventory,
                syncRunID: syncRunID,
                generatedAt: generatedAt
            )
        } else {
            let gate = CanonicalLiveReadOnlyTransportProbeGate.evaluate(policy: policy, bodyByteCount: 0)
            result = CanonicalLiveReadOnlyTransportProbeResult(
                mode: gate.mode,
                route: gate.route,
                routeStatus: gate.routeStatus,
                blocked: true,
                failure: .signedEnvelopeBuildFailed,
                diagnostics: [
                    .canonicalLiveReadOnlyProbePolicyEvaluated,
                    .canonicalLiveReadOnlyProbeSendFailed
                ],
                reason: "liveProbeSenderUnavailable"
            )
        }

        for diagnostic in result.diagnostics {
            diagnosticsStore.record(
                phase: diagnostic.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "\(result.diagnosticsSummary),trigger=\(triggerSource.rawValue)",
                errorCode: result.failure?.rawValue
            )
        }
    }

    private func cleanupIPhoneExecutionShadowRootIfNeeded(
        factoryOutput: CanonicalShadowPortFactoryOutput,
        deviceID: String,
        syncRunID: String
    ) {
        guard let lifecycle = factoryOutput.shadowRootLifecycle else {
            return
        }
        diagnosticsStore.record(
            phase: "canonicalRealDataShadowCopyCleanupStarted",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "rootKind=\(lifecycle.rootKind.rawValue),rootID=\(lifecycle.rootID)"
        )
        let cleanup = lifecycle.cleanup(
            policy: canonicalShadowMigrationConfiguration.policy.realDataShadowCopyPolicy.cleanupPolicy
        )
        let phase: String
        switch cleanup.status {
        case .removed:
            phase = "canonicalRealDataShadowCopyCleanupCompleted"
        case .retainedForDiagnostics, .retainedForNextLaunch:
            phase = "canonicalRealDataShadowCopyRetainedForDiagnostics"
        case .refusedProductionRoot, .failed:
            phase = "canonicalRealDataShadowCopyCleanupFailed"
        }
        diagnosticsStore.record(
            phase: phase,
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: cleanup.diagnosticsSummary,
            errorCode: cleanup.status == .failed || cleanup.status == .refusedProductionRoot ? cleanup.status.rawValue : nil,
            errorMessage: cleanup.failureReason
        )
    }

    private func recordCanonicalRecordingMetadataShadowIfEnabled(
        factoryOutput: CanonicalShadowPortFactoryOutput,
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String,
        generatedAt: Date
    ) {
        guard canonicalSingleDomainShadowConfiguration.isEnabled,
              canonicalSingleDomainShadowConfiguration.policy.recordDiagnostics else {
            return
        }
        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
        let localManifest = factoryOutput.localSnapshot?.manifest
        let peerManifest = factoryOutput.peerSnapshot?.manifest
        let canonicalPlan: CanonicalSyncPlan?
        if let localManifest, let peerManifest {
            canonicalPlan = try? CanonicalSyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger,
                legacyContext: legacyContext
            )
        } else {
            canonicalPlan = nil
        }
        let applyPlan = localManifest.flatMap { local in
            peerManifest.flatMap { peer in
                canonicalPlan.map {
                    CanonicalApplyPlanner().plan(
                        local: local,
                        peer: peer,
                        syncPlan: $0,
                        trigger: canonicalTrigger,
                        legacyContext: legacyContext
                    )
                }
            }
        }
        let report = CanonicalRecordingMetadataExecutionShadowPlanner().run(
            configuration: canonicalSingleDomainShadowConfiguration,
            trigger: .iPhoneSyncTick,
            nodeRole: .iPhone,
            localManifest: localManifest,
            peerManifest: peerManifest,
            syncPlan: canonicalPlan,
            applyPlan: applyPlan,
            legacyActions: factoryOutput.localSnapshot?.legacyActions ?? .empty,
            syncRunID: syncRunID,
            generatedAt: generatedAt
        )
        let safeFactorySummary = String(factoryOutput.diagnosticsSafeSummary.prefix(240))
        for event in report.events.prefix(canonicalSingleDomainShadowConfiguration.policy.maxDiagnosticsEvents) {
            let summary = [
                event.diagnosticsSummary,
                "source=\(triggerSource.rawValue)",
                "factory=\(safeFactorySummary)"
            ].joined(separator: ",")
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: summary
            )
        }
    }

    private func recordCanonicalV86GuardedCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) async -> CanonicalCutoverResult? {
        let configuration = canonicalV8CutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return nil
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let localManifest = localInventory.canonicalManifest
        let peerManifest = peerInventory.canonicalManifest
        var applyPlan: CanonicalApplyPlan?
        var candidates: [CanonicalRecordingMetadataCutoverCandidate] = []

        if let localManifest, let peerManifest {
            let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
            if let canonicalPlan = try? CanonicalSyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger,
                legacyContext: legacyContext
            ) {
                let plannedApply = CanonicalApplyPlanner().plan(
                    local: localManifest,
                    peer: peerManifest,
                    syncPlan: canonicalPlan,
                    trigger: canonicalTrigger,
                    legacyContext: legacyContext
                )
                applyPlan = plannedApply
                candidates = canonicalV8RecordingMetadataCutoverCandidates(
                    applyPlan: plannedApply,
                    localManifest: localManifest,
                    peerManifest: peerManifest,
                    rollbackCheckpointPrefix: "v86-guarded-commit"
                )
            }
        }

        let context = CanonicalRecordingMetadataGuardedCommitContext(
            syncRunID: syncRunID,
            trigger: canonicalTrigger,
            nodeRole: .iPhone,
            localManifest: localManifest,
            peerManifest: peerManifest,
            applyPlan: applyPlan,
            legacyActionSnapshot: canonicalRecordingMetadataLegacyActionSnapshot(legacyPlan),
            evidence: configuration.evidence,
            unresolvedConflictCount: canonicalRecordingMetadataConflictCount(legacyPlan),
            canaryPolicy: CanonicalRecordingMetadataCanaryPolicy(
                maxObjectsPerSyncRun: configuration.policy.effectiveCanaryMaxObjectsPerSyncRun,
                runtimeSwitchEnabled: false,
                allowsV87CanaryN1InternalExecution: configuration.policy.allowsV87CanaryN1InternalExecution,
                recordingMetadataCanaryStagePolicy: configuration.policy.recordingMetadataCanaryStagePolicy
            ),
            legacyFallbackAvailable: configuration.evidence.legacyFallbackAvailable,
            cutoverToken: configuration.cutoverToken,
            candidates: candidates,
            localSnapshotAvailable: localManifest != nil,
            peerSnapshotAvailable: peerManifest != nil
        )

        let stagePolicy = configuration.policy.effectiveRecordingMetadataCanaryStagePolicy
        let shouldExecuteV87N1 = configuration.effectiveMode == .canaryCommit
            && configuration.policy.effectiveCanaryMaxObjectsPerSyncRun == 1
            && configuration.policy.allowsV87CanaryN1InternalExecution
        let shouldExecuteStagedCanary = configuration.effectiveMode == .canaryCommit
            && stagePolicy.requestedStage.isExecutable
        if shouldExecuteV87N1 || shouldExecuteStagedCanary {
            guard let canonicalRecordingMetadataCutoverExecutor else {
                diagnosticsStore.record(
                    phase: CanonicalRecordingMetadataCutoverDiagnosticKind.canonicalRecordingMetadataCanaryFatalBlocker.rawValue,
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "reason=executorUnavailable,legacyFallbackAvailable=\(configuration.evidence.legacyFallbackAvailable)"
                )
                diagnosticsStore.record(
                    phase: CanonicalRecordingMetadataCutoverDiagnosticKind.canonicalRecordingMetadataCanaryLegacyFallbackUsed.rawValue,
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "reason=executorUnavailable"
                )
                return nil
            }
            let canaryConfiguration = CanonicalSingleDomainCutoverConfiguration(
                domain: configuration.domain,
                mode: .canary,
                policy: CanonicalCutoverPolicy(
                    canaryMaxObjectsPerSyncRun: shouldExecuteStagedCanary
                        ? stagePolicy.canaryBudget
                        : 1,
                    allowsV87CanaryN1InternalExecution: shouldExecuteV87N1,
                    recordingMetadataCanaryStagePolicy: shouldExecuteStagedCanary ? stagePolicy : nil,
                    maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
                )
            )
            let result = await CanonicalRecordingMetadataCutoverRunner().run(
                configuration: canaryConfiguration,
                token: configuration.cutoverToken,
                evidence: configuration.evidence,
                candidates: candidates,
                trigger: canonicalTrigger,
                nodeRole: .iPhone,
                executor: canonicalRecordingMetadataCutoverExecutor
            )
            recordCanonicalRecordingMetadataCutoverDiagnostics(
                result,
                deviceID: deviceID,
                syncRunID: syncRunID,
                maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
            )
            return result
        }

        let result = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: configuration,
            context: context
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: event.diagnosticsSummary
            )
        }
        return nil
    }

    private func recordCanonicalRecordingMetadataCutoverDiagnostics(
        _ result: CanonicalCutoverResult,
        deviceID: String,
        syncRunID: String,
        maxDiagnosticsEvents: Int
    ) {
        for event in result.diagnostics.prefix(maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalRecordingMetadataCutoverDiagnosticSummary(event)
            )
        }
        if let report = result.observationReport {
            diagnosticsStore.record(
                phase: "canonicalRecordingMetadataCanaryObservationReportBuilt",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: report.diagnosticsSummary
            )
        }
    }

    private func canonicalRecordingMetadataCutoverDiagnosticSummary(
        _ event: CanonicalRecordingMetadataCutoverDiagnostic
    ) -> String {
        [
            "trigger=\(event.trigger.rawValue)",
            "nodeRole=\(event.nodeRole.rawValue)",
            "domain=\(event.domain.rawValue)",
            event.objectID.map { "objectID=\($0)" },
            event.action.map { "action=\($0)" },
            event.result.map { "result=\($0)" },
            event.reason.map { "reason=\($0)" },
            event.hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    private func recordCanonicalGeneratedArtifactGuardedCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) {
        let configuration = canonicalGeneratedArtifactCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let localManifest = localInventory.canonicalManifest
        let peerManifest = peerInventory.canonicalManifest
        var candidates: [CanonicalGeneratedArtifactCutoverCandidate] = []

        if let localManifest, let peerManifest {
            candidates = canonicalGeneratedArtifactCutoverCandidates(
                localManifest: localManifest,
                peerManifest: peerManifest,
                legacyPlan: legacyPlan,
                peerInventory: peerInventory,
                trigger: canonicalTrigger,
                rollbackCheckpointPrefix: "v822-generated-artifact"
            )
        }

        let context = CanonicalGeneratedArtifactGuardedCommitContext(
            syncRunID: syncRunID,
            trigger: canonicalTrigger,
            nodeRole: .iPhone,
            localManifest: localManifest,
            peerManifest: peerManifest,
            legacyActionSnapshot: canonicalGeneratedArtifactLegacyActionSnapshot(from: legacyPlan),
            matrix: .v822GeneratedArtifactsActivePilot(libraryMetadataObservationCompleteOrRetirementCandidateReady: true),
            evidence: configuration.evidence,
            canaryPolicy: configuration.policy.canaryPolicy,
            cutoverToken: configuration.cutoverToken,
            candidates: candidates,
            localSnapshotAvailable: localManifest != nil,
            peerSnapshotAvailable: peerManifest != nil,
            unresolvedConflictCount: candidates.filter(\.unresolvedConflict).count
        )
        let result = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: configuration,
            context: context
        )
        recordCanonicalGeneratedArtifactGuardedCommitDiagnostics(
            result,
            deviceID: deviceID,
            syncRunID: syncRunID,
            maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
        )
    }

    private func recordCanonicalGeneratedArtifactCutoverSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) async -> CanonicalGeneratedArtifactCutoverResult? {
        let configuration = canonicalGeneratedArtifactCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return nil
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let localManifest = localInventory.canonicalManifest
        let peerManifest = peerInventory.canonicalManifest
        var candidates: [CanonicalGeneratedArtifactCutoverCandidate] = []

        if let localManifest, let peerManifest {
            let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
            if let canonicalPlan = try? CanonicalSyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger,
                legacyContext: legacyContext
            ) {
                let applyPlan = CanonicalApplyPlanner().plan(
                    local: localManifest,
                    peer: peerManifest,
                    syncPlan: canonicalPlan,
                    trigger: canonicalTrigger,
                    legacyContext: legacyContext
                )
                candidates = CanonicalGeneratedArtifactCutoverCandidate.candidates(
                    from: applyPlan,
                    localManifest: localManifest,
                    peerManifest: peerManifest,
                    rollbackCheckpointPrefix: "v89-generated-artifact"
                )
            }
        }

        let mode: CanonicalCutoverMode = configuration.effectiveMode == .canaryCommit ? .canary : .guardedExecuteCommit
        let canaryPolicy = configuration.policy.canaryPolicy
        let canaryConfiguration = CanonicalGeneratedArtifactCanaryConfiguration(appSeamConfiguration: configuration)
        let requestedStage = canaryPolicy.stagePolicy.requestedStage
        let expandedStageCanaryEnabled = requestedStage.isExecutable && requestedStage != .n1
        if expandedStageCanaryEnabled, configuration.effectiveMode == .canaryCommit {
            let stageResult = await CanonicalGeneratedArtifactCanaryStageRunner().run(
                policy: canaryPolicy,
                token: configuration.cutoverToken,
                evidence: configuration.evidence,
                matrix: .v824GeneratedArtifactsStagedCanary(
                    libraryMetadataObservationCompleteOrRetirementCandidateReady: true
                ),
                candidates: candidates,
                trigger: canonicalTrigger,
                nodeRole: .iPhone,
                syncRunID: syncRunID,
                localSnapshotAvailable: localManifest != nil,
                peerSnapshotAvailable: peerManifest != nil,
                peerNode: peerManifest?.node,
                executor: canonicalGeneratedArtifactCutoverExecutor
            )
            recordCanonicalGeneratedArtifactCutoverDiagnostics(
                stageResult.cutoverResult,
                deviceID: deviceID,
                syncRunID: syncRunID,
                maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
            )
            return stageResult.cutoverResult
        }
        let shouldRunStrictN1Path = configuration.effectiveMode == .canaryCommit
            && canaryPolicy.canaryMaxObjectsPerSyncRun == 1

        if shouldRunStrictN1Path {
            let canaryResult = await CanonicalGeneratedArtifactN1CanaryRunner().run(
                configuration: canaryConfiguration,
                policy: canaryPolicy,
                token: configuration.cutoverToken,
                evidence: configuration.evidence,
                matrix: .v822GeneratedArtifactsActivePilot(
                    libraryMetadataObservationCompleteOrRetirementCandidateReady: true
                ),
                candidates: candidates,
                trigger: canonicalTrigger,
                nodeRole: .iPhone,
                syncRunID: syncRunID,
                localSnapshotAvailable: localManifest != nil,
                peerSnapshotAvailable: peerManifest != nil,
                peerNode: peerManifest?.node,
                executor: canonicalGeneratedArtifactCutoverExecutor
            )
            recordCanonicalGeneratedArtifactCutoverDiagnostics(
                canaryResult.cutoverResult,
                deviceID: deviceID,
                syncRunID: syncRunID,
                maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
            )
            return canaryResult.cutoverResult
        }

        let gate = CanonicalGeneratedArtifactCutoverRunner().evaluateGate(
            mode: mode,
            policy: canaryPolicy,
            token: configuration.cutoverToken,
            evidence: configuration.evidence,
            candidates: candidates,
            peerNode: peerManifest?.node,
            trigger: canonicalTrigger
        )
        let diagnostics = [
            CanonicalGeneratedArtifactCutoverDiagnostic(
                kind: .canonicalGeneratedArtifactCutoverGateEvaluated,
                syncRunID: syncRunID,
                trigger: canonicalTrigger,
                nodeRole: .iPhone,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.reason
            ),
            CanonicalGeneratedArtifactCutoverDiagnostic(
                kind: gate.allowed ? .canonicalGeneratedArtifactCutoverGateAllowed : .canonicalGeneratedArtifactCutoverGateBlocked,
                syncRunID: syncRunID,
                trigger: canonicalTrigger,
                nodeRole: .iPhone,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.failures.map(\.rawValue).joined(separator: ",")
            )
        ]
        let result = CanonicalGeneratedArtifactCutoverResult(
            gate: gate,
            commits: [],
            rollbackResults: [],
            diagnostics: diagnostics,
            legacyFallbackUsed: !gate.allowed && configuration.evidence.legacyFallbackAvailable,
            duplicateLegacySuppressedActionIDs: [],
            canaryAttemptedCount: 0,
            canarySucceeded: false,
            fatalBlocker: false,
            readSideProjection: nil
        )
        recordCanonicalGeneratedArtifactCutoverDiagnostics(
            result,
            deviceID: deviceID,
            syncRunID: syncRunID,
            maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
        )
        return nil
    }

    private func recordCanonicalGeneratedArtifactNoCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) {
        let configuration = canonicalGeneratedArtifactCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              configuration.effectiveMode == .guardedExecuteNoCommit else {
            return
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let localManifest = localInventory.canonicalManifest
        let peerManifest = peerInventory.canonicalManifest
        var candidates: [CanonicalGeneratedArtifactNoCommitCandidate] = []
        if let localManifest, let peerManifest {
            let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
            if let canonicalPlan = try? CanonicalSyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger,
                legacyContext: legacyContext
            ) {
                let applyPlan = CanonicalApplyPlanner().plan(
                    local: localManifest,
                    peer: peerManifest,
                    syncPlan: canonicalPlan,
                    trigger: canonicalTrigger,
                    legacyContext: legacyContext
                )
                let cutoverCandidates = CanonicalGeneratedArtifactCutoverCandidate.candidates(
                    from: applyPlan,
                    localManifest: localManifest,
                    peerManifest: peerManifest,
                    rollbackCheckpointPrefix: "v89-generated-artifact-no-commit"
                )
                candidates = cutoverCandidates.map { cutoverCandidate in
                    CanonicalGeneratedArtifactNoCommitCandidate(cutoverCandidate: cutoverCandidate)
                }
            }
        }
        diagnosticsStore.record(
            phase: CanonicalGeneratedArtifactCutoverDiagnosticKind.canonicalGeneratedArtifactNoCommitStarted.rawValue,
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "trigger=\(canonicalTrigger.rawValue),candidateCount=\(candidates.count),productionCommitSuppressed=true"
        )
        let executor = IPhoneGeneratedArtifactNoCommitExecutor()
        let results = candidates.map { executor.stageGeneratedArtifactNoCommit($0) }
        diagnosticsStore.record(
            phase: CanonicalGeneratedArtifactCutoverDiagnosticKind.canonicalGeneratedArtifactNoCommitCompleted.rawValue,
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "trigger=\(canonicalTrigger.rawValue)",
                "candidateCount=\(candidates.count)",
                "stagedCount=\(results.filter(\.staged).count)",
                "stagingOnly=true",
                "legacyDuplicateSuppressed=false"
            ].joined(separator: ",")
        )
    }

    private func recordCanonicalGeneratedArtifactReadSideSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) {
        let configuration = canonicalGeneratedArtifactReadSideConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics else {
            return
        }
        let result = IPhoneGeneratedArtifactReadSideSeam(configuration: configuration).evaluate(
            localInventory: localInventory,
            peerInventory: peerInventory,
            trigger: canonicalTrigger(from: triggerSource),
            syncRunID: syncRunID
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: event.diagnosticsSummary
            )
        }
    }

    private func canonicalGeneratedArtifactCutoverCandidates(
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest,
        legacyPlan: LocalNetworkSyncDiffPlan,
        peerInventory: LocalNetworkSyncInventory,
        trigger: CanonicalSyncPlanTrigger,
        rollbackCheckpointPrefix: String
    ) -> [CanonicalGeneratedArtifactCutoverCandidate] {
        let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
        guard let canonicalPlan = try? CanonicalSyncPlanner().plan(
            local: localManifest,
            peer: peerManifest,
            trigger: trigger,
            legacyContext: legacyContext
        ) else {
            return []
        }
        let applyPlan = CanonicalApplyPlanner().plan(
            local: localManifest,
            peer: peerManifest,
            syncPlan: canonicalPlan,
            trigger: trigger,
            legacyContext: legacyContext
        )
        return CanonicalGeneratedArtifactCutoverCandidate.candidates(
            from: applyPlan,
            localManifest: localManifest,
            peerManifest: peerManifest,
            rollbackCheckpointPrefix: rollbackCheckpointPrefix
        )
    }

    private func recordCanonicalTombstoneConflictCutoverSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) async -> CanonicalTombstoneConflictCutoverResult? {
        let configuration = canonicalTombstoneConflictCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return nil
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let localManifest = localInventory.canonicalManifest
        let peerManifest = peerInventory.canonicalManifest
        var candidates: [CanonicalTombstoneConflictCandidate] = []
        if let localManifest, let peerManifest {
            candidates = canonicalTombstoneConflictCutoverCandidates(
                localManifest: localManifest,
                peerManifest: peerManifest,
                legacyPlan: legacyPlan,
                peerInventory: peerInventory,
                trigger: canonicalTrigger,
                rollbackCheckpointPrefix: configuration.policy.canaryPolicy.canaryMaxObjectsPerSyncRun == 1 ? "v828-tombstone-conflict-n1" : "v827-tombstone-conflict"
            )
        }
        let matrix = CanonicalMigrationDomainMatrix.v827TombstoneConflictActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            generatedArtifactsTemplateCompleteOrObservationReady: true
        )
        if configuration.effectiveMode == .canaryCommit,
           configuration.policy.canaryPolicy.canaryMaxObjectsPerSyncRun == 1 {
            let canaryResult = await CanonicalTombstoneConflictN1CanaryRunner().run(
                configuration: CanonicalTombstoneConflictCanaryConfiguration(appSeamConfiguration: configuration),
                policy: configuration.policy.canaryPolicy,
                token: configuration.cutoverToken,
                evidence: configuration.evidence,
                matrix: matrix,
                candidates: candidates,
                trigger: canonicalTrigger,
                nodeRole: .iPhone,
                syncRunID: syncRunID,
                localSnapshotAvailable: localManifest != nil,
                peerSnapshotAvailable: peerManifest != nil,
                executor: canonicalTombstoneConflictCutoverExecutor
            )
            recordCanonicalTombstoneConflictCutoverDiagnostics(
                canaryResult.cutoverResult,
                deviceID: deviceID,
                syncRunID: syncRunID,
                maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
            )
            return canaryResult.cutoverResult
        }

        let context = CanonicalTombstoneConflictGuardedContext(
            syncRunID: syncRunID,
            trigger: canonicalTrigger,
            nodeRole: .iPhone,
            localManifest: localManifest,
            peerManifest: peerManifest,
            candidates: candidates,
            legacyActionSnapshot: canonicalTombstoneConflictLegacyActionSnapshot(from: legacyPlan),
            matrix: matrix,
            evidence: configuration.evidence,
            canaryPolicy: configuration.policy.canaryPolicy,
            cutoverToken: configuration.cutoverToken,
            localSnapshotAvailable: localManifest != nil,
            peerSnapshotAvailable: peerManifest != nil
        )
        let result = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: configuration,
            context: context
        )
        recordCanonicalTombstoneConflictGuardedDiagnostics(
            result,
            deviceID: deviceID,
            syncRunID: syncRunID,
            maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
        )
        return nil
    }

    private func canonicalTombstoneConflictCutoverCandidates(
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest,
        legacyPlan: LocalNetworkSyncDiffPlan,
        peerInventory: LocalNetworkSyncInventory,
        trigger: CanonicalSyncPlanTrigger,
        rollbackCheckpointPrefix: String
    ) -> [CanonicalTombstoneConflictCandidate] {
        let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
        guard let canonicalPlan = try? CanonicalSyncPlanner().plan(
            local: localManifest,
            peer: peerManifest,
            trigger: trigger,
            legacyContext: legacyContext
        ) else {
            return []
        }
        let applyPlan = CanonicalApplyPlanner().plan(
            local: localManifest,
            peer: peerManifest,
            syncPlan: canonicalPlan,
            trigger: trigger,
            legacyContext: legacyContext
        )
        let libraryPlan = CanonicalLibrarySyncPlanner().plan(
            local: localManifest,
            peer: peerManifest,
            trigger: trigger
        )
        return CanonicalTombstoneConflictCandidate.candidates(
            from: applyPlan,
            libraryPlan: libraryPlan,
            localManifest: localManifest,
            peerManifest: peerManifest,
            rollbackCheckpointPrefix: rollbackCheckpointPrefix
        )
    }

    private func recordCanonicalTombstoneConflictGuardedDiagnostics(
        _ result: CanonicalTombstoneConflictGuardedSeamResult,
        deviceID: String,
        syncRunID: String,
        maxDiagnosticsEvents: Int
    ) {
        for event in result.diagnostics.prefix(maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: event.diagnosticsSummary
            )
        }
    }

    private func recordCanonicalTombstoneConflictCutoverDiagnostics(
        _ result: CanonicalTombstoneConflictCutoverResult,
        deviceID: String,
        syncRunID: String,
        maxDiagnosticsEvents: Int
    ) {
        for event in result.diagnostics.prefix(maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: event.diagnosticsSummary
            )
        }
    }

    private func recordCanonicalGeneratedArtifactGuardedCommitDiagnostics(
        _ result: CanonicalGeneratedArtifactGuardedCommitSeamResult,
        deviceID: String,
        syncRunID: String,
        maxDiagnosticsEvents: Int
    ) {
        for event in result.diagnostics.prefix(maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: event.diagnosticsSummary
            )
        }
    }

    private func recordCanonicalGeneratedArtifactCutoverDiagnostics(
        _ result: CanonicalGeneratedArtifactCutoverResult,
        deviceID: String,
        syncRunID: String,
        maxDiagnosticsEvents: Int
    ) {
        for event in result.diagnostics.prefix(maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalGeneratedArtifactCutoverDiagnosticSummary(event)
            )
        }
    }

    private func canonicalGeneratedArtifactCutoverDiagnosticSummary(
        _ event: CanonicalGeneratedArtifactCutoverDiagnostic
    ) -> String {
        [
            "trigger=\(event.trigger.rawValue)",
            "nodeRole=\(event.nodeRole.rawValue)",
            "domain=\(event.domain.rawValue)",
            event.objectID.map { "objectID=\($0)" },
            event.artifactID.map { "artifactID=\($0)" },
            event.artifactKind.map { "artifactKind=\($0.rawValue)" },
            event.action.map { "action=\($0)" },
            event.result.map { "result=\($0)" },
            event.reason.map { "reason=\($0)" },
            event.hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    private func recordCanonicalLibraryMetadataLandingPilotIfConfigured(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) async -> CanonicalLibraryMetadataCutoverResult? {
        let configuration = canonicalLibraryMetadataDebugPilotConfiguration
        guard configuration.mode.isConfigured, configuration.recordDiagnostics else {
            return nil
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let localManifest = localInventory.canonicalManifest
        let peerManifest = peerInventory.canonicalManifest
        var candidates: [CanonicalLibraryMetadataCutoverCandidate] = []
        if let localManifest, let peerManifest {
            let libraryPlan = CanonicalLibrarySyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger
            )
            candidates = CanonicalLibraryMetadataCutoverCandidate.candidates(
                from: libraryPlan,
                localManifest: localManifest,
                peerManifest: peerManifest,
                rollbackCheckpointPrefix: "v829-library-metadata-landing"
            )
        }

        let result = await CanonicalLibraryMetadataDebugPilotBootstrap().evaluateOrRun(
            configuration: configuration,
            matrix: .defaultV813(),
            candidates: candidates,
            trigger: canonicalTrigger,
            nodeRole: .iPhone,
            syncRunID: syncRunID,
            localSnapshotAvailable: localManifest != nil,
            peerSnapshotAvailable: peerManifest != nil,
            executor: canonicalLibraryMetadataCutoverExecutor
        )
        recordCanonicalLibraryMetadataCutoverDiagnostics(
            result.diagnostics,
            deviceID: deviceID,
            syncRunID: syncRunID,
            maxDiagnosticsEvents: configuration.maxDiagnosticsEvents
        )
        return result.cutoverResult
    }

    private func recordCanonicalLibraryMetadataCutoverSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) async -> CanonicalLibraryMetadataCutoverResult? {
        let configuration = canonicalLibraryMetadataCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return nil
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let localManifest = localInventory.canonicalManifest
        let peerManifest = peerInventory.canonicalManifest
        let canaryConfiguration = CanonicalLibraryMetadataCanaryConfiguration(appSeamConfiguration: configuration)
        let requestedStage = configuration.policy.canaryPolicy.stagePolicy.requestedStage
        let expandedStageCanaryEnabled = requestedStage.isExecutable && requestedStage != .n1
        var libraryPlan: CanonicalLibrarySyncPlan?
        var candidates: [CanonicalLibraryMetadataCutoverCandidate] = []
        if let localManifest, let peerManifest {
            let planned = CanonicalLibrarySyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger
            )
            libraryPlan = planned
            candidates = CanonicalLibraryMetadataCutoverCandidate.candidates(
                from: planned,
                localManifest: localManifest,
                peerManifest: peerManifest,
                rollbackCheckpointPrefix: expandedStageCanaryEnabled ? "v816-library-metadata" : (canaryConfiguration.mode == .n1 ? "v815-library-metadata" : "v814-library-metadata")
            )
        }

        if expandedStageCanaryEnabled, configuration.effectiveMode == .canaryCommit {
            let result = await CanonicalLibraryMetadataCanaryStageRunner().run(
                policy: configuration.policy.canaryPolicy,
                token: configuration.cutoverToken,
                evidence: configuration.evidence,
                matrix: .defaultV813(),
                candidates: candidates,
                trigger: canonicalTrigger,
                nodeRole: .iPhone,
                syncRunID: syncRunID,
                localSnapshotAvailable: localManifest != nil,
                peerSnapshotAvailable: peerManifest != nil,
                executor: canonicalLibraryMetadataCutoverExecutor
            )
            recordCanonicalLibraryMetadataCutoverDiagnostics(
                result.cutoverResult,
                deviceID: deviceID,
                syncRunID: syncRunID,
                maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
            )
            return result.cutoverResult
        }

        if canaryConfiguration.mode == .n1 {
            let result = await CanonicalLibraryMetadataN1CanaryRunner().run(
                configuration: canaryConfiguration,
                policy: configuration.policy.canaryPolicy,
                token: configuration.cutoverToken,
                evidence: configuration.evidence,
                matrix: .defaultV813(),
                candidates: candidates,
                trigger: canonicalTrigger,
                nodeRole: .iPhone,
                syncRunID: syncRunID,
                localSnapshotAvailable: localManifest != nil,
                peerSnapshotAvailable: peerManifest != nil,
                executor: canonicalLibraryMetadataCutoverExecutor
            )
            recordCanonicalLibraryMetadataCutoverDiagnostics(
                result.cutoverResult,
                deviceID: deviceID,
                syncRunID: syncRunID,
                maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
            )
            return result.cutoverResult
        }

        let context = CanonicalLibraryMetadataGuardedCommitContext(
            syncRunID: syncRunID,
            trigger: canonicalTrigger,
            nodeRole: .iPhone,
            localManifest: localManifest,
            peerManifest: peerManifest,
            libraryPlan: libraryPlan,
            legacyActionSnapshot: canonicalLibraryMetadataLegacyActionSnapshot(from: legacyPlan),
            evidence: configuration.evidence,
            canaryPolicy: configuration.policy.canaryPolicy,
            cutoverToken: configuration.cutoverToken,
            candidates: candidates,
            localSnapshotAvailable: localManifest != nil,
            peerSnapshotAvailable: peerManifest != nil,
            unresolvedConflictCount: candidates.filter(\.unresolvedConflict).count
        )
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: configuration,
            context: context
        )
        recordCanonicalLibraryMetadataGuardedCommitDiagnostics(
            result,
            deviceID: deviceID,
            syncRunID: syncRunID,
            maxDiagnosticsEvents: configuration.policy.maxDiagnosticsEvents
        )
        return nil
    }

    private func recordCanonicalLibraryMetadataNoCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) {
        let configuration = canonicalLibraryMetadataCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              configuration.effectiveMode == .guardedExecuteNoCommit else {
            return
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        var candidates: [CanonicalLibraryMetadataNoCommitCandidate] = []
        if let localManifest = localInventory.canonicalManifest,
           let peerManifest = peerInventory.canonicalManifest {
            let libraryPlan = CanonicalLibrarySyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger
            )
            candidates = CanonicalLibraryMetadataCutoverCandidate.candidates(
                from: libraryPlan,
                localManifest: localManifest,
                peerManifest: peerManifest,
                rollbackCheckpointPrefix: "v810-library-metadata-no-commit"
            ).map { CanonicalLibraryMetadataNoCommitCandidate(cutoverCandidate: $0) }
        }
        diagnosticsStore.record(
            phase: CanonicalLibraryMetadataCutoverDiagnosticKind.canonicalLibraryMetadataNoCommitStarted.rawValue,
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "trigger=\(canonicalTrigger.rawValue),candidateCount=\(candidates.count),productionCommitSuppressed=true"
        )
        let executor = IPhoneLibraryMetadataNoCommitExecutor()
        let results = candidates.map { executor.stageLibraryMetadataNoCommit($0) }
        diagnosticsStore.record(
            phase: CanonicalLibraryMetadataCutoverDiagnosticKind.canonicalLibraryMetadataNoCommitCompleted.rawValue,
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "trigger=\(canonicalTrigger.rawValue)",
                "candidateCount=\(candidates.count)",
                "stagedCount=\(results.filter(\.staged).count)",
                "stagingOnly=true",
                "legacyDuplicateSuppressed=false"
            ].joined(separator: ",")
        )
    }

    private func recordCanonicalLibraryMetadataReadSideSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) {
        let configuration = canonicalLibraryMetadataReadSideCutoverConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics else {
            return
        }
        let result = IPhoneLibraryMetadataReadSideSeam(configuration: configuration).evaluate(
            legacyManifest: localInventory.studyManifest,
            canonicalManifest: localInventory.canonicalManifest,
            trigger: canonicalTrigger(from: triggerSource),
            syncRunID: syncRunID
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalLibraryMetadataCutoverDiagnosticSummary(event)
            )
        }
    }

    private func recordCanonicalLibraryMetadataCutoverDiagnostics(
        _ result: CanonicalLibraryMetadataCutoverResult,
        deviceID: String,
        syncRunID: String,
        maxDiagnosticsEvents: Int
    ) {
        for event in result.diagnostics.prefix(maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalLibraryMetadataCutoverDiagnosticSummary(event)
            )
        }
    }

    private func recordCanonicalLibraryMetadataCutoverDiagnostics(
        _ diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic],
        deviceID: String,
        syncRunID: String,
        maxDiagnosticsEvents: Int
    ) {
        for event in diagnostics.prefix(maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalLibraryMetadataCutoverDiagnosticSummary(event)
            )
        }
    }

    private func canonicalLibraryMetadataCutoverDiagnosticSummary(
        _ event: CanonicalLibraryMetadataCutoverDiagnostic
    ) -> String {
        [
            "trigger=\(event.trigger.rawValue)",
            "nodeRole=\(event.nodeRole.rawValue)",
            event.domain.map { "domain=\($0.rawValue)" },
            event.objectID.map { "objectID=\($0)" },
            event.objectKind.map { "objectKind=\($0.rawValue)" },
            event.action.map { "action=\($0)" },
            event.result.map { "result=\($0)" },
            event.reason.map { "reason=\($0)" },
            event.hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    private func recordCanonicalLibraryMetadataGuardedCommitDiagnostics(
        _ result: CanonicalLibraryMetadataGuardedCommitSeamResult,
        deviceID: String,
        syncRunID: String,
        maxDiagnosticsEvents: Int
    ) {
        for event in result.diagnostics.prefix(maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalLibraryMetadataGuardedCommitDiagnosticSummary(event)
            )
        }
    }

    private func canonicalLibraryMetadataGuardedCommitDiagnosticSummary(
        _ event: CanonicalLibraryMetadataGuardedCommitDiagnostic
    ) -> String {
        [
            "trigger=\(event.trigger.rawValue)",
            "nodeRole=\(event.nodeRole.rawValue)",
            "mode=\(event.mode.rawValue)",
            event.objectID.map { "objectID=\($0)" },
            event.objectKind.map { "objectKind=\($0.rawValue)" },
            "candidateCount=\(event.candidateCount)",
            "gateFailureCount=\(event.gateFailureCount)",
            "canaryBudget=\(event.canaryBudget)",
            "commitAttemptedCount=\(event.commitAttemptedCount)",
            "duplicateSuppressionCandidateCount=\(event.duplicateSuppressionCandidateCount)",
            event.result.map { "result=\($0)" },
            event.reason.map { "reason=\($0)" },
            event.hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    private func canonicalLibraryMetadataLegacyActionSnapshot(
        from plan: LocalNetworkSyncDiffPlan
    ) -> CanonicalLegacyActionSnapshot {
        var snapshot = CanonicalLegacyActionSnapshot.empty
        snapshot = snapshot.adding(
            libraryMetadataActionIDs(
                from: plan.downloadMetadataActions + plan.uploadMetadataActions,
                entityKinds: ["folder"]
            ),
            domain: .folders
        )
        snapshot = snapshot.adding(
            libraryMetadataActionIDs(
                from: plan.downloadMetadataActions + plan.uploadMetadataActions,
                entityKinds: ["studyItem"]
            ),
            domain: .studyItems
        )
        snapshot = snapshot.adding(
            libraryMetadataActionIDs(
                from: plan.downloadMetadataActions + plan.uploadMetadataActions,
                entityKinds: ["standaloneNote"]
            ),
            domain: .standaloneNotes
        )
        return snapshot
    }

    private func canonicalGeneratedArtifactLegacyActionSnapshot(
        from plan: LocalNetworkSyncDiffPlan
    ) -> CanonicalLegacyActionSnapshot {
        CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .generatedArtifacts: (plan.downloadArtifactActions + plan.uploadArtifactActions).map(\.id)
        ])
    }

    private func canonicalTombstoneConflictLegacyActionSnapshot(
        from plan: LocalNetworkSyncDiffPlan
    ) -> CanonicalLegacyActionSnapshot {
        CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .tombstones: (plan.uploadMetadataActions + plan.downloadMetadataActions)
                .filter { action in
                    action.entityKind == "tombstone"
                        || action.reason.localizedCaseInsensitiveContains("tombstone")
                        || action.reason.localizedCaseInsensitiveContains("delete")
                }
                .map(\.id),
            .conflicts: plan.conflictActions.map(\.id)
        ])
    }

    private func libraryMetadataActionIDs(
        from actions: [LocalNetworkSyncDiffAction],
        entityKinds: Set<String>
    ) -> [String] {
        actions
            .filter { entityKinds.contains($0.entityKind) }
            .map(\.id)
    }

    private func recordCanonicalAudioUploadCutoverPreparationSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) {
        let configuration = canonicalAudioUploadCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics else {
            return
        }

        let trigger = CanonicalAudioUploadTriggerSource.from(canonicalTrigger(from: triggerSource))
        let candidates: [CanonicalAudioUploadCutoverCandidate]
        if let localManifest = localInventory.canonicalManifest {
            candidates = CanonicalAudioUploadCutoverCandidate.candidates(
                localManifest: localManifest,
                peerManifest: peerInventory.canonicalManifest,
                trigger: trigger
            )
        } else {
            candidates = []
        }

        var evidence = configuration.evidence
        if evidence.evidenceReport == nil {
            evidence.evidenceReport = CanonicalAudioUploadEvidenceReport(candidates: candidates)
        }

        let result: CanonicalAudioUploadCutoverResult
        if configuration.effectiveMode == .guardedExecuteNoCommit {
            result = CanonicalAudioUploadNoCommitRunner().run(
                mode: configuration.cutoverMode,
                policy: configuration.policy.canaryPolicy,
                token: configuration.cutoverToken,
                evidence: evidence,
                candidates: candidates.map { CanonicalAudioUploadNoCommitCandidate(cutoverCandidate: $0) },
                trigger: trigger,
                nodeRole: .iPhone,
                syncRunID: syncRunID,
                executor: IPhoneAudioUploadNoCommitExecutor()
            )
        } else {
            let gate = CanonicalAudioUploadCutoverRunner().evaluateGate(
                mode: configuration.cutoverMode,
                policy: configuration.policy.canaryPolicy,
                token: configuration.cutoverToken,
                evidence: evidence,
                candidates: candidates,
                trigger: trigger
            )
            result = CanonicalAudioUploadCutoverResult(
                gate: gate,
                candidates: candidates,
                diagnostics: [
                    CanonicalAudioUploadDiagnostic(
                        kind: .canonicalAudioUploadCutoverGateEvaluated,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: .iPhone,
                        result: gate.allowed ? "allowed" : "blocked",
                        reason: gate.reason
                    ),
                    CanonicalAudioUploadDiagnostic(
                        kind: gate.allowed ? .canonicalAudioUploadCutoverGateAllowed : .canonicalAudioUploadCutoverGateBlocked,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: .iPhone,
                        result: gate.allowed ? "allowed" : "blocked",
                        reason: gate.failures.map(\.rawValue).joined(separator: ",")
                    ),
                    CanonicalAudioUploadDiagnostic(
                        kind: .canonicalAudioUploadLegacyFallbackPreserved,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: .iPhone,
                        result: "true",
                        reason: "v812PreparationOnly"
                    )
                ]
            )
        }

        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalAudioUploadCutoverDiagnosticSummary(event)
            )
        }
    }

    private func canonicalAudioUploadCutoverDiagnosticSummary(
        _ event: CanonicalAudioUploadDiagnostic
    ) -> String {
        event.diagnosticsSummary
    }

    private func refreshCanonicalReadRuntimeProjection(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) {
        let configuration = canonicalKernelSwitchResultProvider?()
            .effectiveConfiguration
            .readRuntimeConfiguration
            ?? .disabled
        let trigger = CanonicalAudioUploadTriggerSource.from(canonicalTrigger(from: triggerSource))
        let uploadCandidates: [CanonicalAudioUploadCutoverCandidate]
        if let localManifest = localInventory.canonicalManifest {
            uploadCandidates = CanonicalAudioUploadCutoverCandidate.candidates(
                localManifest: localManifest,
                peerManifest: peerInventory.canonicalManifest,
                trigger: trigger
            )
        } else {
            uploadCandidates = []
        }

        let result = studyLibraryStore.configureCanonicalReadRuntimeFromSync(
            configuration: configuration,
            localInventory: localInventory,
            peerInventory: peerInventory,
            uploadCandidates: uploadCandidates,
            syncRuntimeResult: nil,
            syncRunID: syncRunID
        )
        for event in result.diagnostics.prefix(32) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: event.diagnosticsSummary
            )
        }
    }

    private func recordCanonicalV8CutoverNoCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) {
        let configuration = canonicalV8CutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              configuration.effectiveMode == .guardedExecuteNoCommit else {
            return
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let localManifest = localInventory.canonicalManifest
        let peerManifest = peerInventory.canonicalManifest
        var candidates: [CanonicalRecordingMetadataNoCommitCandidate] = []

        if let localManifest, let peerManifest {
            let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
            if let canonicalPlan = try? CanonicalSyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger,
                legacyContext: legacyContext
            ) {
                let applyPlan = CanonicalApplyPlanner().plan(
                    local: localManifest,
                    peer: peerManifest,
                    syncPlan: canonicalPlan,
                    trigger: canonicalTrigger,
                    legacyContext: legacyContext
                )
                candidates = canonicalV8NoCommitCandidates(
                    applyPlan: applyPlan,
                    localManifest: localManifest,
                    peerManifest: peerManifest,
                    legacyPlan: legacyPlan
                )
            }
        }

        let result = CanonicalRecordingMetadataNoCommitRunner().run(
            configuration: configuration,
            candidates: candidates,
            trigger: canonicalTrigger,
            nodeRole: .iPhone,
            syncRunID: syncRunID,
            localSnapshotAvailable: localManifest != nil,
            peerSnapshotAvailable: peerManifest != nil,
            executor: IPhoneRecordingMetadataNoCommitExecutor()
        )

        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            diagnosticsStore.record(
                phase: event.kind.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: event.diagnosticsSummary
            )
        }
    }

    private func canonicalV8NoCommitCandidates(
        applyPlan: CanonicalApplyPlan,
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest,
        legacyPlan: LocalNetworkSyncDiffPlan
    ) -> [CanonicalRecordingMetadataNoCommitCandidate] {
        canonicalV8RecordingMetadataCutoverCandidates(
            applyPlan: applyPlan,
            localManifest: localManifest,
            peerManifest: peerManifest,
            rollbackCheckpointPrefix: "v8-no-commit"
        ).map { cutoverCandidate in
            let objectID = cutoverCandidate.objectID
            return CanonicalRecordingMetadataNoCommitCandidate(
                cutoverCandidate: cutoverCandidate,
                legacyDirection: canonicalV8LegacyDirection(objectID: objectID, legacyPlan: legacyPlan),
                legacyObjectID: objectID,
                expectedRoutePath: cutoverCandidate.action.kind == .recordingMetadataSend ? "/sync/apply-metadata" : nil
            )
        }
    }

    private func canonicalV8RecordingMetadataCutoverCandidates(
        applyPlan: CanonicalApplyPlan,
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest,
        rollbackCheckpointPrefix: String
    ) -> [CanonicalRecordingMetadataCutoverCandidate] {
        applyPlan.actions.compactMap { action in
            guard action.kind == .recordingMetadataApply || action.kind == .recordingMetadataSend else {
                return nil
            }
            let objectID = action.target.objectID
            let localObject = localManifest.objects.first { $0.objectID == objectID }
            let peerObject = peerManifest.objects.first { $0.objectID == objectID }
            return CanonicalRecordingMetadataCutoverCandidate(
                action: action,
                localObject: localObject,
                peerObject: peerObject,
                rollbackCheckpointID: "\(rollbackCheckpointPrefix)-\(objectID)",
                unresolvedConflict: false
            )
        }
    }

    private func canonicalRecordingMetadataLegacyActionSnapshot(
        _ legacyPlan: LocalNetworkSyncDiffPlan
    ) -> CanonicalLegacyActionSnapshot {
        let ids = (legacyPlan.uploadMetadataActions + legacyPlan.downloadMetadataActions)
            .filter { $0.entityKind == "recording" }
            .map(\.id)
        return CanonicalLegacyActionSnapshot(actionIDsByDomain: [
            .recordingMetadata: ids
        ])
    }

    private func refreshCanonicalKernelSwitchConfiguration(syncRunID: String? = nil) {
        guard let canonicalKernelSwitchResultProvider else {
            return
        }
        let result = canonicalKernelSwitchResultProvider()
        canonicalSyncRuntimeConfiguration = result.effectiveConfiguration.syncRuntimeConfiguration
        canonicalApplyRuntimeConfiguration = result.effectiveConfiguration.applyRuntimeConfiguration
        let productionPortInjection = IPhoneCanonicalProductionPortFactory.make(
            result: result,
            productionRootURL: studyLibraryStore.libraryRootURL
        )
        canonicalLibraryMetadataDebugPilotConfiguration = productionPortInjection.libraryMetadataDebugPilotConfiguration
        canonicalRecordingMetadataCutoverExecutor = productionPortInjection.recordingMetadataCutoverExecutor
        canonicalGeneratedArtifactCutoverExecutor = productionPortInjection.generatedArtifactCutoverExecutor
        canonicalLibraryMetadataCutoverExecutor = productionPortInjection.libraryMetadataCutoverExecutor
        canonicalTombstoneConflictCutoverExecutor = productionPortInjection.tombstoneConflictCutoverExecutor
        studyLibraryStore.setCanonicalReadRuntimeConfiguration(
            canonicalMasterSwitchReadConfigurationForStore(result.effectiveConfiguration.readRuntimeConfiguration)
        )
        diagnosticsStore.record(
            phase: "canonicalKernelSwitchEvaluated",
            deviceID: connectionStore.snapshot.deviceID,
            syncRunID: syncRunID,
            result: result.diagnosticsSummary,
            errorCode: result.isBlocked ? "canonical_kernel_switch_blocked" : nil
        )
    }

    private func canonicalRecordingMetadataConflictCount(
        _ legacyPlan: LocalNetworkSyncDiffPlan
    ) -> Int {
        legacyPlan.conflictActions.filter { $0.entityKind == "recording" }.count
    }

    private func canonicalV8LegacyDirection(
        objectID: String,
        legacyPlan: LocalNetworkSyncDiffPlan
    ) -> CanonicalRecordingMetadataNoCommitDirection {
        if legacyPlan.uploadMetadataActions.contains(where: { $0.entityKind == "recording" && $0.entityID == objectID }) {
            return .send
        }
        if legacyPlan.downloadMetadataActions.contains(where: { $0.entityKind == "recording" && $0.entityID == objectID }) {
            return .apply
        }
        return .none
    }

    private func executeCanonicalApplyRuntimeIfConfigured(
        localRuntimeSnapshot: CanonicalInventoryRuntimeSnapshot,
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) async -> CanonicalApplyRuntimeResult? {
        let configuration = canonicalApplyRuntimeConfiguration
        guard configuration.mode != .disabled else {
            return nil
        }

        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        guard let localManifest = localInventory.canonicalManifest,
              let peerManifest = peerInventory.canonicalManifest else {
            let fallbackResult = await CanonicalApplyRuntimeOwner().execute(
                CanonicalApplyRuntimeOwnerContext(
                    configuration: configuration,
                    applyPlan: CanonicalApplyPlan(trigger: canonicalTrigger),
                    localManifest: localInventory.canonicalManifest,
                    peerManifest: peerInventory.canonicalManifest,
                    inventorySnapshotValid: false,
                    canonicalPlanAuthorityAllowed: false,
                    legacyFallbackAvailable: true,
                    registry: canonicalApplyRuntimeExecutorRegistry(),
                    syncRunID: syncRunID
                )
            )
            recordCanonicalApplyRuntimeDiagnostics(fallbackResult.report.diagnostics, deviceID: deviceID)
            return fallbackResult
        }

        do {
            let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
            let canonicalPlan = try CanonicalSyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger,
                legacyContext: legacyContext
            )
            let applyPlan = CanonicalApplyPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                syncPlan: canonicalPlan,
                trigger: canonicalTrigger,
                legacyContext: legacyContext
            )
            let libraryPlan = CanonicalLibrarySyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger
            )
            let modifiedAtFallbackCount = canonicalModifiedAtFallbackObjectCount(
                localManifest: localManifest,
                peerManifest: peerManifest
            )
            let syncGateContext = CanonicalSyncPlanAuthorityGateContext(
                inventorySnapshotAvailable: localRuntimeSnapshot.syncRunID == syncRunID,
                localManifest: localManifest,
                peerManifest: peerManifest,
                peerAbsenceExplicitlyModeled: false,
                localMetadataHashSchemaVersion: CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
                peerMetadataHashSchemaVersion: CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
                localLibraryMetadataHashSchemaVersion: CanonicalLibraryMetadataHashSchema.version,
                peerLibraryMetadataHashSchemaVersion: CanonicalLibraryMetadataHashSchema.version,
                localGeneratedArtifactHashSchemaVersion: CanonicalGeneratedArtifactHashSchema.version,
                peerGeneratedArtifactHashSchemaVersion: CanonicalGeneratedArtifactHashSchema.version,
                canonicalModifiedAtSemanticsAvailable: modifiedAtFallbackCount == 0,
                unsupportedLegacyObjectCount: canonicalUnsupportedLegacyObjectCount(
                    localManifest: localManifest,
                    peerManifest: peerManifest
                ),
                libraryFallbackRequiredObjectCount: libraryPlan.fallbackRequiredObjectIDs.count,
                conflictCount: canonicalConflictCount(canonicalPlan: canonicalPlan, applyPlan: applyPlan, libraryPlan: libraryPlan),
                peerUnknownAudioCount: canonicalPeerUnknownAudioCount(canonicalPlan),
                legacyFallbackAvailable: true,
                diagnosticsRedacted: true,
                runtimeSwitchEnabled: false,
                readPathLegacy: true,
                otherActiveMigrationDomainConflicting: false,
                debugInternalBuild: canonicalSyncRuntimeConfiguration.policy.debugInternalBuild,
                ownerApproved: canonicalSyncRuntimeConfiguration.policy.ownerApproved,
                releaseDefaultBuild: canonicalSyncRuntimeConfiguration.policy.releaseDefaultBuild
            )
            let syncGateResult = CanonicalSyncPlanAuthorityGate().evaluate(
                configuration: canonicalSyncRuntimeConfiguration,
                context: syncGateContext
            )
            let result = await CanonicalApplyRuntimeOwner().execute(
                CanonicalApplyRuntimeOwnerContext(
                    configuration: configuration,
                    applyPlan: applyPlan,
                    libraryPlan: libraryPlan,
                    localManifest: localManifest,
                    peerManifest: peerManifest,
                    inventorySnapshotValid: localRuntimeSnapshot.syncRunID == syncRunID,
                    canonicalPlanAuthorityAllowed: syncGateResult.shouldUseCanonicalPrimary,
                    legacyFallbackAvailable: true,
                    registry: canonicalApplyRuntimeExecutorRegistry(),
                    syncRunID: syncRunID
                )
            )
            recordCanonicalApplyRuntimeDiagnostics(result.report.diagnostics, deviceID: deviceID)
            return result
        } catch {
            diagnosticsStore.record(
                phase: CanonicalSyncRuntimeDiagnosticKind.canonicalApplyRuntimeLegacyFallbackUsed.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "reason=canonicalApplyPlanBuildFailed",
                errorCode: canonicalFallbackReason(error)
            )
            return nil
        }
    }

    private func canonicalApplyRuntimeExecutorRegistry() -> CanonicalApplyRuntimeExecutorRegistry {
        var entries: [CanonicalApplyRuntimeExecutorEntry] = []
        if let canonicalRecordingMetadataCutoverExecutor {
            entries.append(CanonicalApplyRuntimeExecutorAdapters.recordingMetadata(canonicalRecordingMetadataCutoverExecutor))
        }
        if let canonicalLibraryMetadataCutoverExecutor {
            entries.append(CanonicalApplyRuntimeExecutorAdapters.libraryMetadata(canonicalLibraryMetadataCutoverExecutor))
        }
        if let canonicalGeneratedArtifactCutoverExecutor {
            entries.append(CanonicalApplyRuntimeExecutorAdapters.generatedArtifacts(canonicalGeneratedArtifactCutoverExecutor))
        }
        if let canonicalTombstoneConflictCutoverExecutor {
            entries.append(CanonicalApplyRuntimeExecutorAdapters.tombstoneConflict(canonicalTombstoneConflictCutoverExecutor))
        }
        return CanonicalApplyRuntimeExecutorRegistry(entries: entries)
    }

    private func suppressCanonicalApplyRuntimeDuplicateLegacyActions(
        in plan: LocalNetworkSyncDiffPlan,
        runtimeResult: CanonicalApplyRuntimeResult?,
        deviceID: String,
        syncRunID: String
    ) -> LocalNetworkSyncDiffPlan {
        guard let runtimeResult,
              runtimeResult.gateResult.executesCommit else {
            return plan
        }
        let successfulRecords = runtimeResult.report.actionRecords.filter {
            $0.status == .completed && $0.duplicateLegacySuppressionAllowed
        }
        guard !successfulRecords.isEmpty else {
            return plan
        }

        var suppressedPlan = plan
        var removedCount = 0
        for record in successfulRecords {
            switch (record.domain, record.actionKind) {
            case (.recordingMetadata, .recordingMetadataApply):
                let before = suppressedPlan.downloadMetadataActions.count
                suppressedPlan.downloadMetadataActions.removeAll {
                    $0.entityKind == "recording"
                        && $0.entityID == record.objectID
                        && $0.reason == CanonicalApplyActionKind.recordingMetadataApply.rawValue
                }
                removedCount += before - suppressedPlan.downloadMetadataActions.count
            case (.recordingMetadata, .recordingMetadataSend):
                let before = suppressedPlan.uploadMetadataActions.count
                suppressedPlan.uploadMetadataActions.removeAll {
                    $0.entityKind == "recording"
                        && $0.entityID == record.objectID
                        && $0.reason == CanonicalApplyActionKind.recordingMetadataSend.rawValue
                }
                removedCount += before - suppressedPlan.uploadMetadataActions.count
            case (.libraryMetadata, .folderMetadataApply):
                let before = suppressedPlan.downloadMetadataActions.count
                suppressedPlan.downloadMetadataActions.removeAll {
                    $0.entityKind == "folder"
                        && $0.entityID == record.objectID
                        && $0.reason == CanonicalApplyActionKind.folderMetadataApply.rawValue
                }
                removedCount += before - suppressedPlan.downloadMetadataActions.count
            case (.libraryMetadata, .folderMetadataSend):
                let before = suppressedPlan.uploadMetadataActions.count
                suppressedPlan.uploadMetadataActions.removeAll {
                    $0.entityKind == "folder"
                        && $0.entityID == record.objectID
                        && $0.reason == CanonicalApplyActionKind.folderMetadataSend.rawValue
                }
                removedCount += before - suppressedPlan.uploadMetadataActions.count
            case (.libraryMetadata, .studyItemMetadataApply):
                let before = suppressedPlan.downloadMetadataActions.count
                suppressedPlan.downloadMetadataActions.removeAll {
                    $0.entityKind == "studyItem"
                        && $0.entityID == record.objectID
                        && $0.reason == CanonicalApplyActionKind.studyItemMetadataApply.rawValue
                }
                removedCount += before - suppressedPlan.downloadMetadataActions.count
            case (.libraryMetadata, .studyItemMetadataSend):
                let before = suppressedPlan.uploadMetadataActions.count
                suppressedPlan.uploadMetadataActions.removeAll {
                    $0.entityKind == "studyItem"
                        && $0.entityID == record.objectID
                        && $0.reason == CanonicalApplyActionKind.studyItemMetadataSend.rawValue
                }
                removedCount += before - suppressedPlan.uploadMetadataActions.count
            case (.generatedArtifacts, .generatedArtifactDownloadApply):
                guard let artifactID = record.artifactID else {
                    continue
                }
                let before = suppressedPlan.downloadArtifactActions.count
                suppressedPlan.downloadArtifactActions.removeAll {
                    $0.entityKind == "artifact" && $0.entityID == artifactID
                }
                removedCount += before - suppressedPlan.downloadArtifactActions.count
            case (.tombstoneConflict, _):
                let beforeDownload = suppressedPlan.downloadMetadataActions.count
                suppressedPlan.downloadMetadataActions.removeAll {
                    $0.entityID == record.objectID && $0.reason == record.actionKind.rawValue
                }
                let beforeUpload = suppressedPlan.uploadMetadataActions.count
                suppressedPlan.uploadMetadataActions.removeAll {
                    $0.entityID == record.objectID && $0.reason == record.actionKind.rawValue
                }
                let beforeConflict = suppressedPlan.conflictActions.count
                suppressedPlan.conflictActions.removeAll {
                    $0.entityID == record.objectID && $0.reason == record.actionKind.rawValue
                }
                removedCount += (beforeDownload - suppressedPlan.downloadMetadataActions.count)
                    + (beforeUpload - suppressedPlan.uploadMetadataActions.count)
                    + (beforeConflict - suppressedPlan.conflictActions.count)
            case (.recordingExistence, _), (.audioUpload, _), (.generatedArtifacts, _), (.libraryMetadata, _), (.recordingMetadata, _):
                continue
            }
        }

        guard removedCount > 0 else {
            return plan
        }
        diagnosticsStore.record(
            phase: CanonicalSyncRuntimeDiagnosticKind.canonicalApplyRuntimeDuplicateLegacySuppressed.rawValue,
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "removedCount=\(removedCount)",
                "reason=canonicalApplyRuntimeCommitSucceeded",
                "legacyFallbackPreservedForUnmatched=true"
            ].joined(separator: ",")
        )
        return suppressedPlan
    }

    private func suppressCanonicalRecordingMetadataDuplicateLegacyActions(
        in plan: LocalNetworkSyncDiffPlan,
        cutoverResult: CanonicalCutoverResult?,
        deviceID: String,
        syncRunID: String
    ) -> LocalNetworkSyncDiffPlan {
        guard let cutoverResult,
              !cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty else {
            return plan
        }
        var suppressedPlan = plan
        let suppressibleActionIDs = Set(cutoverResult.duplicateLegacySuppressedActionIDs)
        for commit in cutoverResult.commits where commit.committed
            && commit.preconditionVerified
            && commit.postconditionVerified
            && suppressibleActionIDs.contains(commit.actionID) {
            let removedCount: Int
            switch commit.actionKind {
            case .apply:
                let before = suppressedPlan.downloadMetadataActions.count
                suppressedPlan.downloadMetadataActions.removeAll {
                    isCanonicalRecordingMetadataDuplicateAction(
                        $0,
                        objectID: commit.objectID,
                        reason: CanonicalApplyActionKind.recordingMetadataApply.rawValue
                    )
                }
                removedCount = before - suppressedPlan.downloadMetadataActions.count
            case .send:
                let before = suppressedPlan.uploadMetadataActions.count
                suppressedPlan.uploadMetadataActions.removeAll {
                    isCanonicalRecordingMetadataDuplicateAction(
                        $0,
                        objectID: commit.objectID,
                        reason: CanonicalApplyActionKind.recordingMetadataSend.rawValue
                    )
                }
                removedCount = before - suppressedPlan.uploadMetadataActions.count
            }
            diagnosticsStore.record(
                phase: CanonicalRecordingMetadataCutoverDiagnosticKind.canonicalRecordingMetadataDuplicateLegacySuppressed.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: [
                    "objectID=\(safePrefix(commit.objectID))",
                    "action=\(commit.actionKind.rawValue)",
                    "removedCount=\(removedCount)",
                    "reason=canonicalCanaryCommitSucceeded"
                ].joined(separator: ",")
            )
        }
        return suppressedPlan
    }

    private func isCanonicalRecordingMetadataDuplicateAction(
        _ action: LocalNetworkSyncDiffAction,
        objectID: String,
        reason: String
    ) -> Bool {
        action.entityKind == "recording"
            && action.entityID == objectID
            && action.reason == reason
    }

    private func suppressCanonicalGeneratedArtifactDuplicateLegacyActions(
        in plan: LocalNetworkSyncDiffPlan,
        cutoverResult: CanonicalGeneratedArtifactCutoverResult?,
        peerInventory: LocalNetworkSyncInventory,
        deviceID: String,
        syncRunID: String
    ) -> LocalNetworkSyncDiffPlan {
        guard let cutoverResult,
              cutoverResult.commits.contains(where: { $0.committed && $0.preconditionVerified && $0.postconditionVerified }) else {
            return plan
        }
        let legacyIdentities = canonicalGeneratedArtifactLegacyActionIdentities(
            actions: plan.downloadArtifactActions,
            peerInventory: peerInventory
        )
        let suppressibleActionIDs = Set(
            CanonicalGeneratedArtifactLegacyDuplicateSuppression.suppressedLegacyActionIDs(
                after: cutoverResult,
                legacyActions: legacyIdentities
            )
        )
        guard !suppressibleActionIDs.isEmpty else {
            return plan
        }

        var suppressedPlan = plan
        let before = suppressedPlan.downloadArtifactActions.count
        suppressedPlan.downloadArtifactActions.removeAll { action in
            suppressibleActionIDs.contains(action.id)
        }
        let removedCount = before - suppressedPlan.downloadArtifactActions.count
        diagnosticsStore.record(
            phase: CanonicalGeneratedArtifactCutoverDiagnosticKind.canonicalGeneratedArtifactDuplicateLegacySuppressed.rawValue,
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "removedCount=\(removedCount)",
                "reason=canonicalGeneratedArtifactCommitSucceeded",
                "legacyFallbackPreservedForUnmatched=true"
            ].joined(separator: ",")
        )
        return suppressedPlan
    }

    private func canonicalGeneratedArtifactLegacyActionIdentities(
        actions: [LocalNetworkSyncDiffAction],
        peerInventory: LocalNetworkSyncInventory
    ) -> [CanonicalGeneratedArtifactLegacyActionIdentity] {
        let peerArtifactsByID = Dictionary(uniqueKeysWithValues: peerInventory.artifacts.map { ($0.artifactID, $0) })
        return actions.compactMap { action in
            guard action.entityKind == "artifact",
                  let artifact = peerArtifactsByID[action.entityID],
                  let kind = canonicalGeneratedArtifactKind(from: artifact.kind) else {
                return nil
            }
            return CanonicalGeneratedArtifactLegacyActionIdentity(
                actionID: action.id,
                objectID: artifact.ownerID,
                artifactID: artifact.artifactID,
                artifactKind: kind,
                actionKind: .generatedArtifactDownloadApply
            )
        }
    }

    private func suppressCanonicalLibraryMetadataDuplicateLegacyActions(
        in plan: LocalNetworkSyncDiffPlan,
        cutoverResult: CanonicalLibraryMetadataCutoverResult?,
        deviceID: String,
        syncRunID: String
    ) -> LocalNetworkSyncDiffPlan {
        guard let cutoverResult,
              cutoverResult.succeeded else {
            return plan
        }
        var suppressedPlan = plan
        var removedCount = 0
        for commit in cutoverResult.commits where commit.committed
            && commit.preconditionVerified
            && commit.postconditionVerified {
            switch commit.actionKind {
            case .folderApply:
                let before = suppressedPlan.downloadMetadataActions.count
                suppressedPlan.downloadMetadataActions.removeAll {
                    $0.entityKind == "folder"
                        && $0.entityID == commit.objectID
                        && $0.reason == CanonicalApplyActionKind.folderMetadataApply.rawValue
                }
                removedCount += before - suppressedPlan.downloadMetadataActions.count
            case .folderSend:
                let before = suppressedPlan.uploadMetadataActions.count
                suppressedPlan.uploadMetadataActions.removeAll {
                    $0.entityKind == "folder"
                        && $0.entityID == commit.objectID
                        && $0.reason == CanonicalApplyActionKind.folderMetadataSend.rawValue
                }
                removedCount += before - suppressedPlan.uploadMetadataActions.count
            case .studyItemApply, .standaloneNoteApply:
                let before = suppressedPlan.downloadMetadataActions.count
                suppressedPlan.downloadMetadataActions.removeAll {
                    $0.entityKind == "studyItem"
                        && $0.entityID == commit.objectID
                        && $0.reason == CanonicalApplyActionKind.studyItemMetadataApply.rawValue
                }
                removedCount += before - suppressedPlan.downloadMetadataActions.count
            case .studyItemSend, .standaloneNoteSend:
                let before = suppressedPlan.uploadMetadataActions.count
                suppressedPlan.uploadMetadataActions.removeAll {
                    $0.entityKind == "studyItem"
                        && $0.entityID == commit.objectID
                        && $0.reason == CanonicalApplyActionKind.studyItemMetadataSend.rawValue
                }
                removedCount += before - suppressedPlan.uploadMetadataActions.count
            case .conflictRecord, .tombstoneMarkerUnsupportedForThisRound, .unsupported:
                break
            }
        }
        guard removedCount > 0 else {
            return plan
        }
        diagnosticsStore.record(
            phase: CanonicalLibraryMetadataCutoverDiagnosticKind.canonicalLibraryMetadataDuplicateLegacySuppressed.rawValue,
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "removedCount=\(removedCount)",
                "reason=canonicalLibraryMetadataCommitSucceeded",
                "legacyFallbackPreservedForUnmatched=true"
            ].joined(separator: ",")
        )
        return suppressedPlan
    }

    private func suppressCanonicalTombstoneConflictDuplicateLegacyActions(
        in plan: LocalNetworkSyncDiffPlan,
        cutoverResult: CanonicalTombstoneConflictCutoverResult?,
        deviceID: String,
        syncRunID: String
    ) -> LocalNetworkSyncDiffPlan {
        guard let cutoverResult,
              cutoverResult.succeeded else {
            return plan
        }
        let legacyIdentities = canonicalTombstoneConflictLegacyActionIdentities(plan)
        let suppressibleActionIDs = Set(
            CanonicalTombstoneConflictLegacyDuplicateSuppression.suppressedLegacyActionIDs(
                after: cutoverResult,
                legacyActions: legacyIdentities
            )
        )
        guard !suppressibleActionIDs.isEmpty else {
            diagnosticsStore.record(
                phase: CanonicalTombstoneConflictCutoverDiagnosticKind.canonicalTombstoneConflictN1DuplicateSuppressionSkipped.rawValue,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "reason=noMatchingLegacyTombstoneConflictDuplicate"
            )
            return plan
        }

        var suppressedPlan = plan
        let beforeDownload = suppressedPlan.downloadMetadataActions.count
        suppressedPlan.downloadMetadataActions.removeAll { suppressibleActionIDs.contains($0.id) }
        let beforeUpload = suppressedPlan.uploadMetadataActions.count
        suppressedPlan.uploadMetadataActions.removeAll { suppressibleActionIDs.contains($0.id) }
        let beforeConflict = suppressedPlan.conflictActions.count
        suppressedPlan.conflictActions.removeAll { suppressibleActionIDs.contains($0.id) }
        let removedCount = (beforeDownload - suppressedPlan.downloadMetadataActions.count)
            + (beforeUpload - suppressedPlan.uploadMetadataActions.count)
            + (beforeConflict - suppressedPlan.conflictActions.count)
        diagnosticsStore.record(
            phase: CanonicalTombstoneConflictCutoverDiagnosticKind.canonicalTombstoneConflictN1DuplicateLegacySuppressed.rawValue,
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: [
                "removedCount=\(removedCount)",
                "reason=canonicalTombstoneConflictCommitSucceeded",
                "legacyFallbackPreservedForUnmatched=true"
            ].joined(separator: ",")
        )
        return suppressedPlan
    }

    private func canonicalTombstoneConflictLegacyActionIdentities(
        _ plan: LocalNetworkSyncDiffPlan
    ) -> [CanonicalTombstoneConflictLegacyActionIdentity] {
        let metadataActions = plan.downloadMetadataActions + plan.uploadMetadataActions
        let tombstoneActions = metadataActions.compactMap { action -> CanonicalTombstoneConflictLegacyActionIdentity? in
            guard let actionKind = canonicalTombstoneConflictActionKind(from: action) else {
                return nil
            }
            return CanonicalTombstoneConflictLegacyActionIdentity(
                actionID: action.id,
                objectID: action.entityID,
                domain: actionKind == .objectTombstoneApply || actionKind == .objectTombstoneSend ? .objectTombstone : .libraryTombstone,
                actionKind: actionKind
            )
        }
        let conflictActions = plan.conflictActions.map { action in
            CanonicalTombstoneConflictLegacyActionIdentity(
                actionID: action.id,
                objectID: action.entityID,
                domain: action.entityKind == "artifact" ? .artifactConflictRecord : .metadataConflictRecord,
                actionKind: .conflictRecord,
                conflictKind: action.reason
            )
        }
        return tombstoneActions + conflictActions
    }

    private func canonicalTombstoneConflictActionKind(
        from action: LocalNetworkSyncDiffAction
    ) -> CanonicalTombstoneConflictActionKind? {
        switch (action.entityKind, action.kind, action.reason) {
        case ("recording", .downloadMetadata, CanonicalApplyActionKind.objectTombstoneApply.rawValue):
            return .objectTombstoneApply
        case ("recording", .uploadMetadata, CanonicalApplyActionKind.objectTombstoneSend.rawValue):
            return .objectTombstoneSend
        case ("folder", .downloadMetadata, CanonicalApplyActionKind.libraryTombstoneApply.rawValue),
             ("studyItem", .downloadMetadata, CanonicalApplyActionKind.libraryTombstoneApply.rawValue):
            return .libraryTombstoneApply
        case ("folder", .uploadMetadata, CanonicalApplyActionKind.libraryTombstoneSend.rawValue),
             ("studyItem", .uploadMetadata, CanonicalApplyActionKind.libraryTombstoneSend.rawValue):
            return .libraryTombstoneSend
        default:
            return nil
        }
    }

    private func canonicalSyncRuntimePlan(
        localRuntimeSnapshot: CanonicalInventoryRuntimeSnapshot,
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) async -> LocalNetworkSyncDiffPlan {
        let configuration = canonicalSyncRuntimeConfiguration
        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        var canonicalPlan: CanonicalSyncPlan?
        var applyPlan: CanonicalApplyPlan?
        var libraryPlan: CanonicalLibrarySyncPlan?
        var extraDiagnostics: [CanonicalSyncRuntimeDiagnostic] = []

        if configuration.mode.evaluatesCanonicalCandidate,
           let localManifest = localInventory.canonicalManifest,
           let peerManifest = peerInventory.canonicalManifest {
            do {
                let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
                let plannerBundle = try await Self.makeCanonicalPlannerBundleOffMain(
                    local: localManifest,
                    peer: peerManifest,
                    trigger: canonicalTrigger,
                    legacyContext: legacyContext,
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    diagnosticsStore: diagnosticsStore
                )
                let plannedCanonical = plannerBundle.canonicalPlan
                let plannedApply = plannerBundle.applyPlan
                let plannedLibrary = plannerBundle.libraryPlan
                canonicalPlan = plannedCanonical
                applyPlan = plannedApply
                libraryPlan = plannedLibrary

                let transferProjection = canonicalTransferProjection(
                    legacyPlan: legacyPlan,
                    canonicalPlan: plannedCanonical,
                    applyPlan: plannedApply,
                    libraryPlan: plannedLibrary
                )
                let objectProjection = CanonicalObjectProjectionBuilder.build(
                    manifest: localManifest,
                    applyPlan: plannedApply,
                    libraryPlan: plannedLibrary,
                    transferProjection: transferProjection
                )
                let readinessReport = CanonicalRetirementReadinessEvaluator().evaluate(
                    manifest: localManifest,
                    libraryPlan: plannedLibrary,
                    applyPlan: plannedApply,
                    transferProjection: transferProjection,
                    inventoryCoverage: CanonicalInventoryCoverageReport(
                        recordingCoverage: localManifest.objects.count,
                        audioCoverage: localManifest.objects.filter(\.audioAvailable).count,
                        generatedArtifactCoverage: localManifest.objects.reduce(0) { $0 + $1.artifacts.filter { CanonicalProjectionContract.generatedArtifactKinds.contains($0.kind) }.count },
                        folderCoverage: localManifest.folders.count,
                        studyItemCoverage: localManifest.studyItems.count,
                        tombstoneCoverage: localManifest.libraryTombstones.count,
                        unsupportedLegacyObjectCount: localManifest.libraryObjects.filter { $0.kind == .unknownUnsupported }.count,
                        fallbackRequiredCount: plannedLibrary.fallbackRequiredObjectIDs.count
                    ),
                    fallbackUsed: !plannedLibrary.fallbackRequiredObjectIDs.isEmpty
                )
                recordCanonicalPlannerDiagnostics(plannedCanonical, deviceID: deviceID, syncRunID: syncRunID)
                recordCanonicalApplyDiagnostics(plannedApply, deviceID: deviceID, syncRunID: syncRunID)
                recordCanonicalLibraryDiagnostics(plannedLibrary, deviceID: deviceID, syncRunID: syncRunID)
                recordCanonicalTransferProjectionDiagnostics(transferProjection, deviceID: deviceID, syncRunID: syncRunID)
                recordCanonicalObjectProjectionDiagnostics(objectProjection, deviceID: deviceID, syncRunID: syncRunID)
                recordCanonicalRetirementReadiness(readinessReport, deviceID: deviceID, syncRunID: syncRunID)
            } catch {
                recordCanonicalPlanFallback(
                    reason: canonicalFallbackReason(error),
                    localInventory: localInventory,
                    peerInventory: peerInventory,
                    triggerSource: triggerSource,
                    deviceID: deviceID,
                    syncRunID: syncRunID
                )
                extraDiagnostics.append(
                    CanonicalSyncRuntimeDiagnostic(
                        kind: .canonicalSyncRuntimePlanFallback,
                        syncRunID: syncRunID,
                        mode: configuration.mode,
                        detail: canonicalFallbackReason(error)
                    )
                )
            }
        } else if localInventory.canonicalManifest == nil || peerInventory.canonicalManifest == nil {
            recordCanonicalPlanFallback(
                reason: localInventory.canonicalManifest == nil ? "localCanonicalManifestMissing" : "peerCanonicalManifestMissing",
                localInventory: localInventory,
                peerInventory: peerInventory,
                triggerSource: triggerSource,
                deviceID: deviceID,
                syncRunID: syncRunID
            )
        }

        let modifiedAtFallbackCount = canonicalModifiedAtFallbackObjectCount(
            localManifest: localInventory.canonicalManifest,
            peerManifest: peerInventory.canonicalManifest
        )
        if modifiedAtFallbackCount > 0 {
            extraDiagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimeModifiedAtUnavailable,
                    syncRunID: syncRunID,
                    mode: configuration.mode,
                    count: modifiedAtFallbackCount,
                    detail: "documentedFallback"
                )
            )
        }

        let context = CanonicalSyncPlanAuthorityGateContext(
            inventorySnapshotAvailable: localRuntimeSnapshot.syncRunID == syncRunID,
            localManifest: localInventory.canonicalManifest,
            peerManifest: peerInventory.canonicalManifest,
            peerAbsenceExplicitlyModeled: false,
            localMetadataHashSchemaVersion: CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
            peerMetadataHashSchemaVersion: peerInventory.canonicalManifest == nil ? nil : CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
            localLibraryMetadataHashSchemaVersion: CanonicalLibraryMetadataHashSchema.version,
            peerLibraryMetadataHashSchemaVersion: peerInventory.canonicalManifest == nil ? nil : CanonicalLibraryMetadataHashSchema.version,
            localGeneratedArtifactHashSchemaVersion: CanonicalGeneratedArtifactHashSchema.version,
            peerGeneratedArtifactHashSchemaVersion: peerInventory.canonicalManifest == nil ? nil : CanonicalGeneratedArtifactHashSchema.version,
            canonicalModifiedAtSemanticsAvailable: modifiedAtFallbackCount == 0,
            unsupportedLegacyObjectCount: canonicalUnsupportedLegacyObjectCount(
                localManifest: localInventory.canonicalManifest,
                peerManifest: peerInventory.canonicalManifest
            ),
            libraryFallbackRequiredObjectCount: libraryPlan?.fallbackRequiredObjectIDs.count ?? 0,
            conflictCount: canonicalConflictCount(canonicalPlan: canonicalPlan, applyPlan: applyPlan, libraryPlan: libraryPlan),
            peerUnknownAudioCount: canonicalPeerUnknownAudioCount(canonicalPlan),
            legacyFallbackAvailable: true,
            diagnosticsRedacted: true,
            runtimeSwitchEnabled: false,
            readPathLegacy: true,
            otherActiveMigrationDomainConflicting: false,
            debugInternalBuild: configuration.policy.debugInternalBuild,
            ownerApproved: configuration.policy.ownerApproved,
            releaseDefaultBuild: configuration.policy.releaseDefaultBuild
        )
        let gateResult = CanonicalSyncPlanAuthorityGate().evaluate(
            configuration: configuration,
            context: context
        )
        extraDiagnostics.append(contentsOf: canonicalSyncRuntimeBlockerDiagnostics(
            gateResult: gateResult,
            syncRunID: syncRunID,
            mode: configuration.mode
        ))

        if gateResult.shouldUseCanonicalPrimary,
           let canonicalPlan,
           let applyPlan,
           let libraryPlan {
            let scopedPlanResult = canonicalScopedPrimaryDecisionPlan(
                canonicalPlan: canonicalPlan,
                applyPlan: applyPlan,
                libraryPlan: libraryPlan,
                peerInventory: peerInventory,
                legacyPlan: legacyPlan,
                deviceID: deviceID,
                syncRunID: syncRunID
            )
            extraDiagnostics.append(contentsOf: scopedPlanResult.diagnostics)
            recordCanonicalSyncRuntimeDiagnostics(
                CanonicalSyncRuntimeResult.make(
                    mode: configuration.mode,
                    gateResult: gateResult,
                    syncRunID: syncRunID,
                    extraDiagnostics: extraDiagnostics
                ),
                deviceID: deviceID
            )
            return scopedPlanResult.plan
        }

        recordCanonicalSyncRuntimeDiagnostics(
            CanonicalSyncRuntimeResult.make(
                mode: configuration.mode,
                gateResult: gateResult,
                syncRunID: syncRunID,
                extraDiagnostics: extraDiagnostics
            ),
            deviceID: deviceID
        )
        return legacyPlan
    }

    private func canonicalScopedPrimaryDecisionPlan(
        canonicalPlan: CanonicalSyncPlan,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        deviceID: String,
        syncRunID: String
    ) -> (plan: LocalNetworkSyncDiffPlan, diagnostics: [CanonicalSyncRuntimeDiagnostic]) {
        _ = deviceID
        var plan = legacyPlan
        var diagnostics = canonicalRuntimeMetadataDiagnostics(
            canonicalPlan: canonicalPlan,
            libraryPlan: libraryPlan,
            legacyPlan: legacyPlan,
            syncRunID: syncRunID
        )
        let enabledScopes = Set(canonicalSyncRuntimeConfiguration.policy.enabledScopes)
        var canonicalIdentities: [CanonicalSyncRuntimeActionIdentity] = []

        if enabledScopes.contains(.recordingMetadata) || enabledScopes.contains(.recordingExistence) {
            let recordingIDs = Set(
                canonicalPlan.uploadRecordingMetadata.map(\.objectID)
                    + canonicalPlan.downloadRecordingMetadata.map(\.objectID)
                    + canonicalPlan.noOpRecordingMetadata.map(\.objectID)
            )
            plan.uploadMetadataActions.removeAll { $0.entityKind == "recording" && recordingIDs.contains($0.entityID) }
            plan.downloadMetadataActions.removeAll { $0.entityKind == "recording" && recordingIDs.contains($0.entityID) }
            plan.conflictActions.removeAll { $0.entityKind == "recording" && recordingIDs.contains($0.entityID) }
            plan.noOps.removeAll { $0.entityKind == "recording" && recordingIDs.contains($0.entityID) }
            for action in applyPlan.actions {
                switch action.kind {
                case .recordingMetadataSend:
                    let diffAction = syncDiffAction(.uploadMetadata, entityKind: "recording", entityID: action.target.objectID, reason: action.kind.rawValue)
                    plan.uploadMetadataActions.append(diffAction)
                    canonicalIdentities.append(runtimeIdentity(for: diffAction, scope: .recordingMetadata))
                case .recordingMetadataApply:
                    let diffAction = syncDiffAction(.downloadMetadata, entityKind: "recording", entityID: action.target.objectID, reason: action.kind.rawValue)
                    plan.downloadMetadataActions.append(diffAction)
                    canonicalIdentities.append(runtimeIdentity(for: diffAction, scope: .recordingMetadata))
                default:
                    break
                }
            }
            for action in canonicalPlan.noOpRecordingMetadata {
                let diffAction = syncDiffAction(.noOp, entityKind: "recording", entityID: action.objectID, reason: action.reason.rawValue)
                plan.noOps.append(diffAction)
            }
        }

        if enabledScopes.contains(.libraryMetadata) {
            let libraryActionEntities = canonicalLibraryRuntimeEntities(libraryPlan)
            plan.uploadMetadataActions.removeAll { libraryActionEntities.contains(runtimeEntityKey(entityKind: $0.entityKind, entityID: $0.entityID)) }
            plan.downloadMetadataActions.removeAll { libraryActionEntities.contains(runtimeEntityKey(entityKind: $0.entityKind, entityID: $0.entityID)) }
            plan.conflictActions.removeAll { libraryActionEntities.contains(runtimeEntityKey(entityKind: $0.entityKind, entityID: $0.entityID)) }
            plan.noOps.removeAll { libraryActionEntities.contains(runtimeEntityKey(entityKind: $0.entityKind, entityID: $0.entityID)) }
            for action in libraryPlan.applyActions {
                switch action.kind {
                case .folderMetadataSend:
                    let diffAction = syncDiffAction(.uploadMetadata, entityKind: "folder", entityID: action.target.objectID, reason: action.kind.rawValue)
                    plan.uploadMetadataActions.append(diffAction)
                    canonicalIdentities.append(runtimeIdentity(for: diffAction, scope: .libraryMetadata))
                case .folderMetadataApply:
                    let diffAction = syncDiffAction(.downloadMetadata, entityKind: "folder", entityID: action.target.objectID, reason: action.kind.rawValue)
                    plan.downloadMetadataActions.append(diffAction)
                    canonicalIdentities.append(runtimeIdentity(for: diffAction, scope: .libraryMetadata))
                case .studyItemMetadataSend:
                    let diffAction = syncDiffAction(.uploadMetadata, entityKind: "studyItem", entityID: action.target.objectID, reason: action.kind.rawValue)
                    plan.uploadMetadataActions.append(diffAction)
                    canonicalIdentities.append(runtimeIdentity(for: diffAction, scope: .libraryMetadata))
                case .studyItemMetadataApply:
                    let diffAction = syncDiffAction(.downloadMetadata, entityKind: "studyItem", entityID: action.target.objectID, reason: action.kind.rawValue)
                    plan.downloadMetadataActions.append(diffAction)
                    canonicalIdentities.append(runtimeIdentity(for: diffAction, scope: .libraryMetadata))
                default:
                    break
                }
            }
            for action in libraryPlan.actions {
                guard action.kind == .folderMetadataNoOp || action.kind == .studyItemMetadataNoOp else {
                    continue
                }
                let diffAction = syncDiffAction(
                    .noOp,
                    entityKind: canonicalRuntimeEntityKind(for: action.objectKind),
                    entityID: action.objectID.rawValue,
                    reason: action.kind.rawValue
                )
                plan.noOps.append(diffAction)
            }
        }

        if enabledScopes.contains(.generatedArtifacts) {
            let generatedArtifactEntities = canonicalGeneratedArtifactRuntimeEntities(
                canonicalPlan: canonicalPlan,
                applyPlan: applyPlan
            )
            plan.uploadArtifactActions.removeAll { generatedArtifactEntities.contains(runtimeEntityKey(entityKind: $0.entityKind, entityID: $0.entityID)) }
            plan.downloadArtifactActions.removeAll { generatedArtifactEntities.contains(runtimeEntityKey(entityKind: $0.entityKind, entityID: $0.entityID)) }
            plan.conflictActions.removeAll { generatedArtifactEntities.contains(runtimeEntityKey(entityKind: $0.entityKind, entityID: $0.entityID)) }
            plan.noOps.removeAll { generatedArtifactEntities.contains(runtimeEntityKey(entityKind: $0.entityKind, entityID: $0.entityID)) }

            for action in applyPlan.actions {
                switch action.kind {
                case .generatedArtifactDownloadApply:
                    guard let artifact = legacyArtifact(for: action, in: peerInventory.artifacts),
                          artifact.kind.isAutoDownloadAllowed else {
                        plan.noOps.append(syncDiffAction(
                            .noOp,
                            entityKind: "artifact",
                            entityID: canonicalApplyEntityID(action),
                            reason: "canonicalGeneratedArtifactLegacyFallback"
                        ))
                        continue
                    }
                    let diffAction = syncDiffAction(
                        .downloadArtifact,
                        entityKind: "artifact",
                        entityID: artifact.artifactID,
                        reason: action.kind.rawValue
                    )
                    plan.downloadArtifactActions.append(diffAction)
                    canonicalIdentities.append(runtimeIdentity(for: diffAction, scope: .generatedArtifacts))
                case .generatedArtifactNoOp, .deferredUnsupported:
                    guard action.target.artifactKind != nil else {
                        continue
                    }
                    plan.noOps.append(syncDiffAction(
                        .noOp,
                        entityKind: "artifact",
                        entityID: canonicalApplyEntityID(action),
                        reason: action.kind.rawValue
                    ))
                default:
                    break
                }
            }
            for action in canonicalPlan.noOpGeneratedArtifact + canonicalPlan.deferGeneratedArtifact {
                plan.noOps.append(syncDiffAction(
                    .noOp,
                    entityKind: "artifact",
                    entityID: canonicalArtifactEntityID(action),
                    reason: action.reason.rawValue
                ))
            }
            for action in canonicalPlan.conflictGeneratedArtifact {
                plan.conflictActions.append(syncDiffAction(
                    .conflict,
                    entityKind: "artifact",
                    entityID: canonicalArtifactEntityID(action),
                    reason: action.reason.rawValue
                ))
            }
        }

        let guardResult = CanonicalSyncRuntimeDuplicateExecutionGuard().evaluate(
            canonicalOwnerUsed: true,
            mode: canonicalSyncRuntimeConfiguration.mode,
            syncRunID: syncRunID,
            canonicalActions: canonicalIdentities,
            legacyActions: runtimeLegacyActionIdentities(legacyPlan),
            enabledScopes: canonicalSyncRuntimeConfiguration.policy.enabledScopes
        )
        diagnostics.append(contentsOf: guardResult.diagnostics)
        return (plan, diagnostics)
    }

    private func canonicalRuntimeMetadataDiagnostics(
        canonicalPlan: CanonicalSyncPlan,
        libraryPlan: CanonicalLibrarySyncPlan,
        legacyPlan: LocalNetworkSyncDiffPlan,
        syncRunID: String
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var diagnostics: [CanonicalSyncRuntimeDiagnostic] = []
        let legacyRecordingMetadataTransferIDs = Set(
            (legacyPlan.uploadMetadataActions + legacyPlan.downloadMetadataActions)
                .filter { $0.entityKind == "recording" }
                .map(\.entityID)
        )
        for action in canonicalPlan.noOpRecordingMetadata {
            diagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimeMetadataHashEqual,
                    syncRunID: syncRunID,
                    mode: canonicalSyncRuntimeConfiguration.mode,
                    objectID: action.objectID,
                    hash: action.localMetadataHash,
                    detail: "recordingMetadata"
                )
            )
            if legacyRecordingMetadataTransferIDs.contains(action.objectID) {
                diagnostics.append(
                    CanonicalSyncRuntimeDiagnostic(
                        kind: .canonicalSyncRuntimeLegacyHashMismatchIgnored,
                        syncRunID: syncRunID,
                        mode: canonicalSyncRuntimeConfiguration.mode,
                        objectID: action.objectID,
                        hash: action.localMetadataHash,
                        detail: "canonicalNoOp"
                    )
                )
            }
        }
        for action in canonicalPlan.uploadRecordingMetadata + canonicalPlan.downloadRecordingMetadata {
            diagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimeModifiedAtLWWApplied,
                    syncRunID: syncRunID,
                    mode: canonicalSyncRuntimeConfiguration.mode,
                    objectID: action.objectID,
                    actionKind: action.reason.rawValue,
                    hash: action.localMetadataHash ?? action.peerMetadataHash,
                    detail: "recordingMetadata"
                )
            )
        }
        let legacyLibraryTransferKeys = Set(
            (legacyPlan.uploadMetadataActions + legacyPlan.downloadMetadataActions)
                .filter { $0.entityKind == "folder" || $0.entityKind == "studyItem" }
                .map { runtimeEntityKey(entityKind: $0.entityKind, entityID: $0.entityID) }
        )
        for action in libraryPlan.actions {
            switch action.kind {
            case .folderMetadataNoOp, .studyItemMetadataNoOp:
                let entityKind = canonicalRuntimeEntityKind(for: action.objectKind)
                diagnostics.append(
                    CanonicalSyncRuntimeDiagnostic(
                        kind: .canonicalSyncRuntimeMetadataHashEqual,
                        syncRunID: syncRunID,
                        mode: canonicalSyncRuntimeConfiguration.mode,
                        objectID: action.objectID.rawValue,
                        hashPrefix: action.localHashPrefix ?? action.peerHashPrefix,
                        detail: entityKind
                    )
                )
                if legacyLibraryTransferKeys.contains(runtimeEntityKey(entityKind: entityKind, entityID: action.objectID.rawValue)) {
                    diagnostics.append(
                        CanonicalSyncRuntimeDiagnostic(
                            kind: .canonicalSyncRuntimeLegacyHashMismatchIgnored,
                            syncRunID: syncRunID,
                            mode: canonicalSyncRuntimeConfiguration.mode,
                            objectID: action.objectID.rawValue,
                            hashPrefix: action.localHashPrefix ?? action.peerHashPrefix,
                            detail: entityKind
                        )
                    )
                }
            case .folderMetadataSend, .folderMetadataApply, .studyItemMetadataSend, .studyItemMetadataApply:
                diagnostics.append(
                    CanonicalSyncRuntimeDiagnostic(
                        kind: .canonicalSyncRuntimeModifiedAtLWWApplied,
                        syncRunID: syncRunID,
                        mode: canonicalSyncRuntimeConfiguration.mode,
                        objectID: action.objectID.rawValue,
                        actionKind: action.kind.rawValue,
                        hashPrefix: action.localHashPrefix ?? action.peerHashPrefix,
                        detail: canonicalRuntimeEntityKind(for: action.objectKind)
                    )
                )
            default:
                break
            }
        }
        let legacyGeneratedArtifactTransferIDs = Set(
            (legacyPlan.uploadArtifactActions + legacyPlan.downloadArtifactActions)
                .filter { $0.entityKind == "artifact" }
                .map(\.entityID)
        )
        for action in canonicalPlan.noOpGeneratedArtifact {
            let artifactID = canonicalArtifactEntityID(action)
            diagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimeMetadataHashEqual,
                    syncRunID: syncRunID,
                    mode: canonicalSyncRuntimeConfiguration.mode,
                    objectID: artifactID,
                    hash: action.localHash ?? action.peerHash,
                    detail: "generatedArtifacts"
                )
            )
            if legacyGeneratedArtifactTransferIDs.contains(artifactID) {
                diagnostics.append(
                    CanonicalSyncRuntimeDiagnostic(
                        kind: .canonicalSyncRuntimeLegacyHashMismatchIgnored,
                        syncRunID: syncRunID,
                        mode: canonicalSyncRuntimeConfiguration.mode,
                        objectID: artifactID,
                        hash: action.localHash ?? action.peerHash,
                        detail: "generatedArtifacts"
                    )
                )
            }
        }
        for action in canonicalPlan.downloadGeneratedArtifact {
            diagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimeModifiedAtLWWApplied,
                    syncRunID: syncRunID,
                    mode: canonicalSyncRuntimeConfiguration.mode,
                    objectID: canonicalArtifactEntityID(action),
                    actionKind: action.reason.rawValue,
                    hash: action.peerHash ?? action.localHash,
                    detail: "generatedArtifacts"
                )
            )
        }
        for action in canonicalPlan.deferGeneratedArtifact {
            diagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalGeneratedArtifactContentMissingDeferred,
                    syncRunID: syncRunID,
                    mode: canonicalSyncRuntimeConfiguration.mode,
                    objectID: canonicalArtifactEntityID(action),
                    actionKind: action.reason.rawValue,
                    hash: action.peerHash ?? action.localHash,
                    detail: "generatedArtifacts"
                )
            )
        }
        for action in canonicalPlan.conflictGeneratedArtifact {
            diagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimeConflictBlocked,
                    syncRunID: syncRunID,
                    mode: canonicalSyncRuntimeConfiguration.mode,
                    objectID: canonicalArtifactEntityID(action),
                    actionKind: action.reason.rawValue,
                    hash: action.peerHash ?? action.localHash,
                    detail: "generatedArtifacts"
                )
            )
        }
        return diagnostics
    }

    private func canonicalLibraryRuntimeEntities(_ libraryPlan: CanonicalLibrarySyncPlan) -> Set<String> {
        let actionKeys = libraryPlan.actions.compactMap { action -> String? in
            switch action.kind {
            case .folderMetadataSend, .folderMetadataApply, .folderMetadataNoOp,
                 .studyItemMetadataSend, .studyItemMetadataApply, .studyItemMetadataNoOp:
                return runtimeEntityKey(
                    entityKind: canonicalRuntimeEntityKind(for: action.objectKind),
                    entityID: action.objectID.rawValue
                )
            default:
                return nil
            }
        }
        let applyKeys = libraryPlan.applyActions.compactMap { action -> String? in
            switch action.kind {
            case .folderMetadataSend, .folderMetadataApply:
                return runtimeEntityKey(entityKind: "folder", entityID: action.target.objectID)
            case .studyItemMetadataSend, .studyItemMetadataApply:
                return runtimeEntityKey(entityKind: "studyItem", entityID: action.target.objectID)
            default:
                return nil
            }
        }
        return Set(actionKeys + applyKeys)
    }

    private func canonicalGeneratedArtifactRuntimeEntities(
        canonicalPlan: CanonicalSyncPlan,
        applyPlan: CanonicalApplyPlan
    ) -> Set<String> {
        let syncKeys = (canonicalPlan.downloadGeneratedArtifact
            + canonicalPlan.deferGeneratedArtifact
            + canonicalPlan.noOpGeneratedArtifact
            + canonicalPlan.conflictGeneratedArtifact).map { action in
                runtimeEntityKey(entityKind: "artifact", entityID: canonicalArtifactEntityID(action))
            }
        let applyKeys = applyPlan.actions.compactMap { action -> String? in
            switch action.kind {
            case .generatedArtifactDownloadApply, .generatedArtifactNoOp, .deferredUnsupported, .artifactTombstoneApply:
                guard action.target.artifactKind != nil else {
                    return nil
                }
                return runtimeEntityKey(entityKind: "artifact", entityID: canonicalApplyEntityID(action))
            default:
                return nil
            }
        }
        return Set(syncKeys + applyKeys)
    }

    private func canonicalRuntimeEntityKind(for objectKind: CanonicalObjectKind) -> String {
        switch objectKind {
        case .folder:
            return "folder"
        default:
            return "studyItem"
        }
    }

    private func runtimeEntityKey(entityKind: String, entityID: String) -> String {
        "\(entityKind):\(entityID)"
    }

    private func runtimeIdentity(
        for action: LocalNetworkSyncDiffAction,
        scope: CanonicalSyncRuntimeDecisionScope
    ) -> CanonicalSyncRuntimeActionIdentity {
        CanonicalSyncRuntimeActionIdentity(scope: scope, objectID: action.entityID, actionKind: action.kind.rawValue)
    }

    private func runtimeLegacyActionIdentities(_ plan: LocalNetworkSyncDiffPlan) -> [CanonicalSyncRuntimeActionIdentity] {
        let metadataActions = plan.uploadMetadataActions + plan.downloadMetadataActions + plan.noOps + plan.conflictActions
        var identities = metadataActions.compactMap { action in
            switch action.entityKind {
            case "recording":
                return runtimeIdentity(for: action, scope: .recordingMetadata)
            case "folder", "studyItem":
                return runtimeIdentity(for: action, scope: .libraryMetadata)
            default:
                return nil
            }
        }
        identities += (plan.uploadArtifactActions + plan.downloadArtifactActions + plan.noOps + plan.conflictActions).compactMap { action in
            guard action.entityKind == "artifact" else {
                return nil
            }
            return runtimeIdentity(for: action, scope: .generatedArtifacts)
        }
        return identities
    }

    private func canonicalUnsupportedLegacyObjectCount(
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?
    ) -> Int {
        [localManifest, peerManifest].compactMap { $0 }.reduce(0) { count, manifest in
            count + manifest.libraryObjects.filter { $0.kind == .unknownUnsupported }.count
        }
    }

    private func canonicalModifiedAtFallbackObjectCount(
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?
    ) -> Int {
        [localManifest, peerManifest].compactMap { $0 }.reduce(0) { count, manifest in
            guard manifest.node.platform.caseInsensitiveCompare("iPhone") == .orderedSame else {
                return count
            }
            return count + manifest.objects.count
        }
    }

    private func canonicalConflictCount(
        canonicalPlan: CanonicalSyncPlan?,
        applyPlan: CanonicalApplyPlan?,
        libraryPlan: CanonicalLibrarySyncPlan?
    ) -> Int {
        (canonicalPlan?.conflictRecordingMetadata.count ?? 0)
            + (canonicalPlan?.conflictAudioArtifact.count ?? 0)
            + (canonicalPlan?.conflictGeneratedArtifact.count ?? 0)
            + (applyPlan?.conflicts.count ?? 0)
            + (libraryPlan?.conflicts.count ?? 0)
    }

    private func canonicalPeerUnknownAudioCount(_ canonicalPlan: CanonicalSyncPlan?) -> Int {
        canonicalPlan?.deferAudioArtifact.filter { $0.reason == .peerAudioUnknownDeferred }.count ?? 0
    }

    private func canonicalSyncRuntimeBlockerDiagnostics(
        gateResult: CanonicalSyncPlanAuthorityGateResult,
        syncRunID: String,
        mode: CanonicalSyncRuntimeMode
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var diagnostics: [CanonicalSyncRuntimeDiagnostic] = []
        if gateResult.blockers.contains(.unsupportedObjects) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimeUnsupportedObjectBlocked, syncRunID: syncRunID, mode: mode, detail: gateResult.state.rawValue))
        }
        if gateResult.blockers.contains(.unresolvedConflicts) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimeConflictBlocked, syncRunID: syncRunID, mode: mode, detail: gateResult.state.rawValue))
        }
        if gateResult.blockers.contains(.peerUnavailable) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimePeerSnapshotUnavailable, syncRunID: syncRunID, mode: mode, detail: gateResult.state.rawValue))
        }
        if gateResult.blockers.contains(.schemaMismatch) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimeSchemaMismatch, syncRunID: syncRunID, mode: mode, detail: gateResult.state.rawValue))
        }
        return diagnostics
    }

    private func recordCanonicalSyncRuntimeDiagnostics(
        _ result: CanonicalSyncRuntimeResult,
        deviceID: String
    ) {
        for diagnostic in result.diagnostics where diagnostic.isRedacted {
            diagnosticsStore.record(
                phase: diagnostic.kind.rawValue,
                deviceID: deviceID,
                syncRunID: diagnostic.syncRunID,
                result: diagnostic.summary()
            )
        }
    }

    private func recordCanonicalApplyRuntimeDiagnostics(
        _ diagnostics: [CanonicalSyncRuntimeDiagnostic],
        deviceID: String
    ) {
        for diagnostic in diagnostics where diagnostic.isRedacted {
            diagnosticsStore.record(
                phase: diagnostic.kind.rawValue,
                deviceID: deviceID,
                syncRunID: diagnostic.syncRunID,
                result: diagnostic.summary()
            )
        }
    }

    private func canonicalSyncPlanIfAvailable(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        legacyPlan: LocalNetworkSyncDiffPlan,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) -> LocalNetworkSyncDiffPlan? {
        guard let localManifest = localInventory.canonicalManifest else {
            recordCanonicalPlanFallback(
                reason: "localCanonicalManifestMissing",
                localInventory: localInventory,
                peerInventory: peerInventory,
                triggerSource: triggerSource,
                deviceID: deviceID,
                syncRunID: syncRunID
            )
            return nil
        }
        guard let peerManifest = peerInventory.canonicalManifest else {
            recordCanonicalPlanFallback(
                reason: "peerCanonicalManifestMissing",
                localInventory: localInventory,
                peerInventory: peerInventory,
                triggerSource: triggerSource,
                deviceID: deviceID,
                syncRunID: syncRunID
            )
            return nil
        }

        do {
            let canonicalTrigger = canonicalTrigger(from: triggerSource)
            let legacyContext = canonicalLegacyContext(legacyPlan: legacyPlan, peerInventory: peerInventory)
            let canonicalPlan = try CanonicalSyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger,
                legacyContext: legacyContext
            )
            let applyPlan = CanonicalApplyPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                syncPlan: canonicalPlan,
                trigger: canonicalTrigger,
                legacyContext: legacyContext
            )
            let libraryPlan = CanonicalLibrarySyncPlanner().plan(
                local: localManifest,
                peer: peerManifest,
                trigger: canonicalTrigger
            )
            let transferProjection = canonicalTransferProjection(
                legacyPlan: legacyPlan,
                canonicalPlan: canonicalPlan,
                applyPlan: applyPlan,
                libraryPlan: libraryPlan
            )
            let objectProjection = CanonicalObjectProjectionBuilder.build(
                manifest: localManifest,
                applyPlan: applyPlan,
                libraryPlan: libraryPlan,
                transferProjection: transferProjection
            )
            let readinessReport = CanonicalRetirementReadinessEvaluator().evaluate(
                manifest: localManifest,
                libraryPlan: libraryPlan,
                applyPlan: applyPlan,
                transferProjection: transferProjection,
                inventoryCoverage: CanonicalInventoryCoverageReport(
                    recordingCoverage: localManifest.objects.count,
                    audioCoverage: localManifest.objects.filter(\.audioAvailable).count,
                    generatedArtifactCoverage: localManifest.objects.reduce(0) { $0 + $1.artifacts.filter { CanonicalProjectionContract.generatedArtifactKinds.contains($0.kind) }.count },
                    folderCoverage: localManifest.folders.count,
                    studyItemCoverage: localManifest.studyItems.count,
                    tombstoneCoverage: localManifest.libraryTombstones.count,
                    unsupportedLegacyObjectCount: localManifest.libraryObjects.filter { $0.kind == .unknownUnsupported }.count,
                    fallbackRequiredCount: libraryPlan.fallbackRequiredObjectIDs.count
                ),
                fallbackUsed: !libraryPlan.fallbackRequiredObjectIDs.isEmpty
            )
            recordCanonicalPlannerDiagnostics(canonicalPlan, deviceID: deviceID, syncRunID: syncRunID)
            recordCanonicalApplyDiagnostics(applyPlan, deviceID: deviceID, syncRunID: syncRunID)
            recordCanonicalLibraryDiagnostics(libraryPlan, deviceID: deviceID, syncRunID: syncRunID)
            recordCanonicalTransferProjectionDiagnostics(transferProjection, deviceID: deviceID, syncRunID: syncRunID)
            recordCanonicalObjectProjectionDiagnostics(objectProjection, deviceID: deviceID, syncRunID: syncRunID)
            recordCanonicalRetirementReadiness(readinessReport, deviceID: deviceID, syncRunID: syncRunID)
            return bridgedCanonicalPlan(
                canonicalPlan,
                applyPlan: applyPlan,
                libraryPlan: libraryPlan,
                legacyPlan: legacyPlan,
                localInventory: localInventory,
                peerInventory: peerInventory,
                deviceID: deviceID,
                syncRunID: syncRunID
            )
        } catch {
            recordCanonicalPlanFallback(
                reason: canonicalFallbackReason(error),
                localInventory: localInventory,
                peerInventory: peerInventory,
                triggerSource: triggerSource,
                deviceID: deviceID,
                syncRunID: syncRunID
            )
            return nil
        }
    }

    private func recordCanonicalPlanFallback(
        reason: String,
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        triggerSource: RecordingAudioSyncTriggerSource,
        deviceID: String,
        syncRunID: String
    ) {
        let canonicalTrigger = canonicalTrigger(from: triggerSource)
        let result = [
            "legacyFallbackUsed=true",
            "reason=\(reason)",
            "trigger=\(canonicalTrigger.rawValue)",
            "nodeRole=iPhone",
            "localRecordings=\(localInventory.recordings.count)",
            "peerRecordings=\(peerInventory.recordings.count)",
            "localCanonicalObjects=\(localInventory.canonicalManifest?.objects.count.description ?? "missing")",
            "peerCanonicalObjects=\(peerInventory.canonicalManifest?.objects.count.description ?? "missing")"
        ].joined(separator: ",")
        diagnosticsStore.record(
            phase: "canonicalPlanFallback",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: result
        )
    }

    private func canonicalTrigger(from triggerSource: RecordingAudioSyncTriggerSource) -> CanonicalSyncPlanTrigger {
        switch triggerSource {
        case .manualUploadButton, .manualSyncIPhone, .manualSyncMacHint:
            return .manual
        case .periodicSync:
            return .periodic
        case .appActivationRefresh:
            return .appActivation
        case .retryDrainer:
            return .retryDrainer
        case .folderViewRefresh, .recordingListRefresh, .studyLibraryRefresh:
            return .viewRefresh
        }
    }

    private func canonicalLegacyContext(
        legacyPlan: LocalNetworkSyncDiffPlan,
        peerInventory: LocalNetworkSyncInventory
    ) -> CanonicalSyncPlannerLegacyContext {
        CanonicalSyncPlannerLegacyContext(
            legacyUploadMetadataObjectIDs: legacyPlan.uploadMetadataActions
                .filter { $0.entityKind == "recording" }
                .map(\.entityID),
            legacyDownloadMetadataObjectIDs: legacyPlan.downloadMetadataActions
                .filter { $0.entityKind == "recording" }
                .map(\.entityID),
            legacyUploadAudioObjectIDs: legacyPlan.uploadRecordingAudioActions.map(\.entityID),
            legacyDownloadGeneratedArtifactKeys: canonicalGeneratedArtifactKeys(
                actions: legacyPlan.downloadArtifactActions,
                inventory: peerInventory
            ),
            legacyConflictGeneratedArtifactKeys: canonicalGeneratedArtifactKeys(
                actions: legacyPlan.conflictActions.filter { $0.entityKind == "artifact" },
                inventory: peerInventory
            ),
            peerObjectFacts: canonicalLegacyFacts(from: peerInventory)
        )
    }

    private func canonicalLegacyFacts(from inventory: LocalNetworkSyncInventory) -> [CanonicalShadowLegacyObjectFact] {
        let recordingFacts = inventory.recordings.map { entry in
            CanonicalShadowLegacyObjectFact(
                objectID: entry.recordingID,
                legacyMetadataHash: entry.metadataHash,
                audioHash: entry.audioChecksum,
                audioByteSize: entry.audioSize,
                audioAvailability: entry.audioAvailability?.rawValue ?? (entry.audioAvailable ? "local" : "missing"),
                hasRecordingMetadata: inventory.sourcePlatform == .iPhone,
                hasReceiveRecord: entry.receiveStatus != nil || inventory.sourcePlatform == .Mac,
                hasStudyItem: inventory.studyItems.contains { $0.recordingID == entry.recordingID }
            )
        }
        let studyItemFacts = inventory.studyItems.compactMap { item -> CanonicalShadowLegacyObjectFact? in
            guard let recordingID = item.recordingID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !recordingID.isEmpty else {
                return nil
            }
            return CanonicalShadowLegacyObjectFact(
                objectID: recordingID,
                legacyMetadataHash: item.revisionHash,
                hasStudyItem: true
            )
        }
        return recordingFacts + studyItemFacts
    }

    private func canonicalGeneratedArtifactKeys(
        actions: [LocalNetworkSyncDiffAction],
        inventory: LocalNetworkSyncInventory
    ) -> [String] {
        let artifactsByID = Dictionary(uniqueKeysWithValues: inventory.artifacts.map { ($0.artifactID, $0) })
        return actions.compactMap { action in
            guard let artifact = artifactsByID[action.entityID],
                  let kind = canonicalGeneratedArtifactKind(from: artifact.kind) else {
                return nil
            }
            return CanonicalProjectionContract.artifactKey(objectID: artifact.ownerID, kind: kind)
        }
    }

    private func canonicalGeneratedArtifactKind(from kind: LocalNetworkSyncArtifactKind) -> CanonicalArtifact.Kind? {
        switch kind {
        case .transcriptJSON:
            return .transcriptJSON
        case .transcriptMarkdown:
            return .transcriptMarkdown
        case .noteMarkdown:
            return .noteMarkdown
        case .noteJSON:
            return .noteJSON
        case .summaryJSON:
            return .summaryJSON
        case .metadataJSON, .receiveJSON, .summaryMarkdown, .audio:
            return nil
        }
    }

    private func bridgedCanonicalPlan(
        _ canonicalPlan: CanonicalSyncPlan,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan,
        legacyPlan: LocalNetworkSyncDiffPlan,
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        deviceID: String,
        syncRunID: String
    ) -> LocalNetworkSyncDiffPlan {
        var plan = legacyPlan
        let canonicalTouchedGeneratedKeys = canonicalGeneratedArtifactTouchedKeys(canonicalPlan)
        let localArtifactsByID = Dictionary(uniqueKeysWithValues: localInventory.artifacts.map { ($0.artifactID, $0) })
        let peerArtifactsByID = Dictionary(uniqueKeysWithValues: peerInventory.artifacts.map { ($0.artifactID, $0) })
        let shouldRemoveGeneratedAction: (LocalNetworkSyncDiffAction) -> Bool = { action in
            guard action.entityKind == "artifact" else {
                return false
            }
            let artifact = localArtifactsByID[action.entityID] ?? peerArtifactsByID[action.entityID]
            guard let artifact,
                  let kind = self.canonicalGeneratedArtifactKind(from: artifact.kind) else {
                return false
            }
            return canonicalTouchedGeneratedKeys.contains(CanonicalProjectionContract.artifactKey(objectID: artifact.ownerID, kind: kind))
        }

        plan.uploadMetadataActions.removeAll { $0.entityKind == "recording" }
        plan.downloadMetadataActions.removeAll { $0.entityKind == "recording" }
        plan.uploadRecordingAudioActions.removeAll { $0.entityKind == "recording" }
        plan.conflictActions.removeAll { $0.entityKind == "recording" }
        plan.noOps.removeAll { $0.entityKind == "recording" }
        let canonicalTouchedFolderIDs = canonicalLibraryTouchedIDs(libraryPlan, objectKind: .folder)
        let canonicalTouchedStudyItemIDs = canonicalLibraryTouchedIDs(libraryPlan, objectKind: .standaloneStudyItem)
            .union(canonicalLibraryTouchedIDs(libraryPlan, objectKind: .standaloneNote))
            .union(canonicalLibraryTouchedIDs(libraryPlan, objectKind: .recordingAssociatedStudyItem))
        let shouldRemoveLibraryAction: (LocalNetworkSyncDiffAction) -> Bool = { action in
            if action.entityKind == "folder" {
                return canonicalTouchedFolderIDs.contains(action.entityID)
            }
            if action.entityKind == "studyItem" {
                return canonicalTouchedStudyItemIDs.contains(action.entityID)
            }
            return false
        }
        plan.uploadMetadataActions.removeAll(where: shouldRemoveLibraryAction)
        plan.downloadMetadataActions.removeAll(where: shouldRemoveLibraryAction)
        plan.conflictActions.removeAll(where: shouldRemoveLibraryAction)
        plan.noOps.removeAll(where: shouldRemoveLibraryAction)
        plan.downloadArtifactActions.removeAll(where: shouldRemoveGeneratedAction)
        plan.uploadArtifactActions.removeAll(where: shouldRemoveGeneratedAction)
        plan.conflictActions.removeAll(where: shouldRemoveGeneratedAction)
        plan.noOps.removeAll(where: shouldRemoveGeneratedAction)

        plan.uploadRecordingAudioActions += canonicalPlan.uploadAudioArtifact.map { action in
            syncDiffAction(.uploadRecordingAudio, entityKind: "recording", entityID: action.objectID, reason: action.reason.rawValue)
        }
        plan.noOps += canonicalPlan.noOpAudioArtifact.map { action in
            syncDiffAction(.noOp, entityKind: "recording", entityID: action.objectID, reason: action.reason.rawValue)
        }
        plan.noOps += canonicalPlan.deferAudioArtifact.map { action in
            syncDiffAction(.noOp, entityKind: "recording", entityID: action.objectID, reason: action.reason.rawValue)
        }

        var bridgedArtifactIDs = Set<String>()
        for action in applyPlan.actions {
            switch action.kind {
            case .recordingMetadataSend, .objectTombstoneSend:
                plan.uploadMetadataActions.append(
                    syncDiffAction(.uploadMetadata, entityKind: "recording", entityID: action.target.objectID, reason: action.kind.rawValue)
                )
            case .recordingMetadataApply, .objectTombstoneApply:
                plan.downloadMetadataActions.append(
                    syncDiffAction(.downloadMetadata, entityKind: "recording", entityID: action.target.objectID, reason: action.kind.rawValue)
                )
            case .folderMetadataSend:
                plan.uploadMetadataActions.append(
                    syncDiffAction(.uploadMetadata, entityKind: "folder", entityID: action.target.objectID, reason: action.kind.rawValue)
                )
            case .folderMetadataApply:
                plan.downloadMetadataActions.append(
                    syncDiffAction(.downloadMetadata, entityKind: "folder", entityID: action.target.objectID, reason: action.kind.rawValue)
                )
            case .studyItemMetadataSend:
                plan.uploadMetadataActions.append(
                    syncDiffAction(.uploadMetadata, entityKind: "studyItem", entityID: action.target.objectID, reason: action.kind.rawValue)
                )
            case .studyItemMetadataApply:
                plan.downloadMetadataActions.append(
                    syncDiffAction(.downloadMetadata, entityKind: "studyItem", entityID: action.target.objectID, reason: action.kind.rawValue)
                )
            case .libraryTombstoneSend:
                let entityKind = canonicalTouchedFolderIDs.contains(action.target.objectID) ? "folder" : "studyItem"
                plan.uploadMetadataActions.append(
                    syncDiffAction(.uploadMetadata, entityKind: entityKind, entityID: action.target.objectID, reason: action.kind.rawValue)
                )
            case .libraryTombstoneApply:
                let entityKind = canonicalTouchedFolderIDs.contains(action.target.objectID) ? "folder" : "studyItem"
                plan.downloadMetadataActions.append(
                    syncDiffAction(.downloadMetadata, entityKind: entityKind, entityID: action.target.objectID, reason: action.kind.rawValue)
                )
            case .generatedArtifactDownloadApply:
                guard let artifact = legacyArtifact(for: action, in: peerInventory.artifacts),
                  artifact.kind.isAutoDownloadAllowed else {
                    recordCanonicalApplyUnsupported(action: action, deviceID: deviceID, syncRunID: syncRunID, reason: "peerLegacyArtifactMissing")
                    plan.noOps.append(
                        syncDiffAction(.noOp, entityKind: "artifact", entityID: canonicalApplyEntityID(action), reason: "canonicalApplyBridgeFallback")
                    )
                    continue
                }
                guard bridgedArtifactIDs.insert(artifact.artifactID).inserted else {
                    continue
                }
                plan.downloadArtifactActions.append(
                    syncDiffAction(.downloadArtifact, entityKind: "artifact", entityID: artifact.artifactID, reason: action.kind.rawValue)
                )
            case .conflictRecord:
                let entityKind = action.target.artifactKind == nil ? "recording" : "artifact"
                plan.conflictActions.append(
                    syncDiffAction(.conflict, entityKind: entityKind, entityID: canonicalApplyEntityID(action), reason: action.reason)
                )
            case .generatedArtifactNoOp, .deferredUnsupported, .artifactTombstoneApply:
                let entityKind = action.target.artifactKind == nil ? "recording" : "artifact"
                plan.noOps.append(
                    syncDiffAction(.noOp, entityKind: entityKind, entityID: canonicalApplyEntityID(action), reason: action.kind.rawValue)
                )
            }
        }
        for action in libraryPlan.applyActions {
            switch action.kind {
            case .folderMetadataSend:
                plan.uploadMetadataActions.append(syncDiffAction(.uploadMetadata, entityKind: "folder", entityID: action.target.objectID, reason: action.kind.rawValue))
            case .folderMetadataApply:
                plan.downloadMetadataActions.append(syncDiffAction(.downloadMetadata, entityKind: "folder", entityID: action.target.objectID, reason: action.kind.rawValue))
            case .studyItemMetadataSend:
                plan.uploadMetadataActions.append(syncDiffAction(.uploadMetadata, entityKind: "studyItem", entityID: action.target.objectID, reason: action.kind.rawValue))
            case .studyItemMetadataApply:
                plan.downloadMetadataActions.append(syncDiffAction(.downloadMetadata, entityKind: "studyItem", entityID: action.target.objectID, reason: action.kind.rawValue))
            case .libraryTombstoneSend:
                let entityKind = canonicalTouchedFolderIDs.contains(action.target.objectID) ? "folder" : "studyItem"
                plan.uploadMetadataActions.append(syncDiffAction(.uploadMetadata, entityKind: entityKind, entityID: action.target.objectID, reason: action.kind.rawValue))
            case .libraryTombstoneApply:
                let entityKind = canonicalTouchedFolderIDs.contains(action.target.objectID) ? "folder" : "studyItem"
                plan.downloadMetadataActions.append(syncDiffAction(.downloadMetadata, entityKind: entityKind, entityID: action.target.objectID, reason: action.kind.rawValue))
            case .conflictRecord:
                let entityKind = canonicalTouchedFolderIDs.contains(action.target.objectID) ? "folder" : "studyItem"
                plan.conflictActions.append(syncDiffAction(.conflict, entityKind: entityKind, entityID: action.target.objectID, reason: action.reason))
            case .recordingMetadataApply, .recordingMetadataSend, .generatedArtifactDownloadApply, .generatedArtifactNoOp, .objectTombstoneApply, .objectTombstoneSend, .artifactTombstoneApply, .deferredUnsupported:
                break
            }
        }
        if !libraryPlan.applyActions.isEmpty {
            diagnosticsStore.record(
                phase: "canonicalLegacyFullManifestFallback",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "libraryActions=\(libraryPlan.applyActions.count),existingFullManifestUsed=true"
            )
        }
        return plan
    }

    private func canonicalLibraryTouchedIDs(
        _ libraryPlan: CanonicalLibrarySyncPlan,
        objectKind: CanonicalObjectKind
    ) -> Set<String> {
        Set(libraryPlan.actions.compactMap { action in
            guard action.objectKind == objectKind,
                  action.kind != .unsupportedFallback,
                  action.kind != .deferred else {
                return nil
            }
            return action.objectID.rawValue
        })
    }

    private func canonicalGeneratedArtifactTouchedKeys(_ canonicalPlan: CanonicalSyncPlan) -> Set<String> {
        let actions = canonicalPlan.downloadGeneratedArtifact
            + canonicalPlan.deferGeneratedArtifact
            + canonicalPlan.noOpGeneratedArtifact
            + canonicalPlan.conflictGeneratedArtifact
        return Set(actions.compactMap { action in
            guard let kind = action.kind else {
                return nil
            }
            return CanonicalProjectionContract.artifactKey(objectID: action.objectID, kind: kind)
        })
    }

    private func legacyArtifact(
        for action: CanonicalArtifactTransferAction,
        in artifacts: [LocalNetworkSyncArtifactEntry]
    ) -> LocalNetworkSyncArtifactEntry? {
        guard let kind = action.kind else {
            return nil
        }
        return artifacts.first { artifact in
            guard artifact.ownerID == action.objectID,
                  canonicalGeneratedArtifactKind(from: artifact.kind) == kind else {
                return false
            }
            if let logicalPathToken = action.logicalPathToken {
                return artifact.logicalPathToken == logicalPathToken
            }
            return true
        }
    }

    private func legacyArtifact(
        for action: CanonicalApplyAction,
        in artifacts: [LocalNetworkSyncArtifactEntry]
    ) -> LocalNetworkSyncArtifactEntry? {
        guard let kind = action.target.artifactKind else {
            return nil
        }
        return artifacts.first { artifact in
            guard artifact.ownerID == action.target.objectID,
                  canonicalGeneratedArtifactKind(from: artifact.kind) == kind else {
                return false
            }
            if let artifactID = action.target.artifactID {
                return artifact.artifactID == artifactID
            }
            return true
        }
    }

    private func canonicalApplyEntityID(_ action: CanonicalApplyAction) -> String {
        if let artifactID = action.target.artifactID {
            return artifactID
        }
        if let kind = action.target.artifactKind {
            return CanonicalProjectionContract.artifactID(objectID: action.target.objectID, kind: kind)
        }
        return action.target.objectID
    }

    private func canonicalArtifactEntityID(_ action: CanonicalArtifactTransferAction) -> String {
        if let artifactID = action.artifactID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !artifactID.isEmpty {
            return artifactID
        }
        if let kind = action.kind {
            return CanonicalProjectionContract.artifactID(objectID: action.objectID, kind: kind)
        }
        return action.objectID
    }

    private func recordCanonicalGeneratedArtifactBridgeFallback(
        action: CanonicalArtifactTransferAction,
        deviceID: String,
        syncRunID: String,
        reason: String
    ) {
        diagnosticsStore.record(
            phase: "canonicalArtifactPlanFallback",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "recording=\(safePrefix(action.objectID)),artifact=\(action.artifactID.map(safePrefix) ?? "missing"),kind=\(action.kind?.rawValue ?? "unknown"),reason=\(reason)"
        )
    }

    private func recordCanonicalApplyUnsupported(
        action: CanonicalApplyAction,
        deviceID: String,
        syncRunID: String,
        reason: String
    ) {
        diagnosticsStore.record(
            phase: "canonicalApplyUnsupportedDeferred",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "\(canonicalApplyActionResult(action)),reason=\(reason)"
        )
    }

    private func syncDiffAction(
        _ kind: LocalNetworkSyncDiffActionKind,
        entityKind: String,
        entityID: String,
        reason: String
    ) -> LocalNetworkSyncDiffAction {
        LocalNetworkSyncDiffAction(
            id: "\(kind.rawValue):\(entityKind):\(entityID):\(reason)",
            kind: kind,
            entityKind: entityKind,
            entityID: entityID,
            reason: reason
        )
    }

    private func recordCanonicalPlannerDiagnostics(
        _ canonicalPlan: CanonicalSyncPlan,
        deviceID: String,
        syncRunID: String
    ) {
        diagnosticsStore.record(
            phase: "canonicalPlanUsed",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "uploadMetadata=\(canonicalPlan.uploadRecordingMetadata.count),downloadMetadata=\(canonicalPlan.downloadRecordingMetadata.count),uploadAudio=\(canonicalPlan.uploadAudioArtifact.count),audioNoOp=\(canonicalPlan.noOpAudioArtifact.count),audioConflict=\(canonicalPlan.conflictAudioArtifact.count),downloadGenerated=\(canonicalPlan.downloadGeneratedArtifact.count),generatedNoOp=\(canonicalPlan.noOpGeneratedArtifact.count),generatedDeferred=\(canonicalPlan.deferGeneratedArtifact.count),generatedConflict=\(canonicalPlan.conflictGeneratedArtifact.count)"
        )
        for diagnostic in canonicalPlan.diagnostics {
            diagnosticsStore.record(
                phase: diagnostic.phase,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalDiagnosticResult(diagnostic)
            )
        }
        for action in canonicalPlan.uploadAudioArtifact {
            diagnosticsStore.record(
                phase: "canonicalAudioBootstrapUpload",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safePrefix(action.objectID)),reason=\(action.reason.rawValue)"
            )
        }
        for action in canonicalPlan.noOpAudioArtifact where action.reason == .peerAudioSameHashSameSize {
            diagnosticsStore.record(
                phase: "canonicalAudioPeerSameNoOp",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safePrefix(action.objectID))"
            )
        }
        for action in canonicalPlan.deferAudioArtifact where action.reason == .peerAudioUnknownDeferred {
            diagnosticsStore.record(
                phase: "canonicalAudioPeerUnknownDeferred",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safePrefix(action.objectID))"
            )
        }
        for action in canonicalPlan.conflictAudioArtifact {
            diagnosticsStore.record(
                phase: "canonicalAudioConflict",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safePrefix(action.objectID)),reason=\(action.reason.rawValue)"
            )
        }
        for action in canonicalPlan.downloadGeneratedArtifact {
            diagnosticsStore.record(
                phase: action.reason == .canonicalGeneratedArtifactAuthoritativePeerNewer ? "canonicalGeneratedArtifactAuthoritativePeerNewer" : "canonicalGeneratedArtifactDownload",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalArtifactActionResult(action)
            )
        }
        for action in canonicalPlan.noOpGeneratedArtifact {
            diagnosticsStore.record(
                phase: "canonicalGeneratedArtifactPeerSameNoOp",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalArtifactActionResult(action)
            )
        }
        for action in canonicalPlan.deferGeneratedArtifact {
            let phase: String
            switch action.reason {
            case .canonicalGeneratedArtifactUnsupportedUpload:
                phase = "canonicalGeneratedArtifactUnsupportedUpload"
            case .canonicalGeneratedArtifactLocalProducerNoRoute:
                phase = "canonicalGeneratedArtifactLocalProducerNoRoute"
            default:
                phase = "canonicalGeneratedArtifactPeerUnknownDeferred"
            }
            diagnosticsStore.record(
                phase: phase,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalArtifactActionResult(action)
            )
        }
        for action in canonicalPlan.conflictGeneratedArtifact {
            diagnosticsStore.record(
                phase: "canonicalGeneratedArtifactConflict",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalArtifactActionResult(action)
            )
        }
    }

    private func recordCanonicalApplyDiagnostics(
        _ applyPlan: CanonicalApplyPlan,
        deviceID: String,
        syncRunID: String
    ) {
        diagnosticsStore.record(
            phase: "canonicalApplyPlanUsed",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "actions=\(applyPlan.actions.count),conflicts=\(applyPlan.conflicts.count),tombstones=\(applyPlan.tombstones.count),metadataConflicts=\(applyPlan.conflictDiagnostics.metadata),audioConflicts=\(applyPlan.conflictDiagnostics.audio),artifactConflicts=\(applyPlan.conflictDiagnostics.generatedArtifact),tombstoneConflicts=\(applyPlan.conflictDiagnostics.tombstone)"
        )
        for diagnostic in applyPlan.diagnostics {
            diagnosticsStore.record(
                phase: diagnostic.phase,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safePrefix(diagnostic.target.objectID)),artifact=\(diagnostic.target.artifactID.map(safePrefix) ?? "missing"),kind=\(diagnostic.target.artifactKind?.rawValue ?? "object"),detail=\(diagnostic.detail ?? "none")"
            )
        }
        for action in applyPlan.actions {
            diagnosticsStore.record(
                phase: canonicalApplyPhase(for: action),
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalApplyActionResult(action)
            )
        }
        for tombstone in applyPlan.tombstones {
            diagnosticsStore.record(
                phase: "canonicalTombstoneRecordCreated",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safePrefix(tombstone.target.objectID)),artifact=\(tombstone.target.artifactID.map(safePrefix) ?? "missing"),kind=\(tombstone.target.artifactKind?.rawValue ?? "object"),state=\(tombstone.state.rawValue),reason=\(tombstone.reason.rawValue),policy=\(tombstone.policies.map(\.rawValue).joined(separator: "+"))"
            )
        }
    }

    private func recordCanonicalLibraryDiagnostics(
        _ libraryPlan: CanonicalLibrarySyncPlan,
        deviceID: String,
        syncRunID: String
    ) {
        diagnosticsStore.record(
            phase: "canonicalLibraryObjectsProjected",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "actions=\(libraryPlan.actions.count),applyActions=\(libraryPlan.applyActions.count),conflicts=\(libraryPlan.conflicts.count),tombstones=\(libraryPlan.tombstones.count),fallbackRequired=\(libraryPlan.fallbackRequiredObjectIDs.count)"
        )
        for diagnostic in libraryPlan.diagnostics {
            diagnosticsStore.record(
                phase: diagnostic.phase,
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "object=\(diagnostic.objectID.map { safePrefix($0.rawValue) } ?? "missing"),kind=\(diagnostic.objectKind?.rawValue ?? "unknown"),detail=\(diagnostic.detail ?? "none")"
            )
        }
        for conflict in libraryPlan.conflicts {
            diagnosticsStore.record(
                phase: "canonicalLibraryConflictRecorded",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "object=\(safePrefix(conflict.objectID.rawValue)),kind=\(conflict.objectKind.rawValue),conflict=\(conflict.kind.rawValue),localHash=\(conflict.localHashPrefix ?? "missing"),peerHash=\(conflict.peerHashPrefix ?? "missing")"
            )
        }
        for action in libraryPlan.applyActions {
            diagnosticsStore.record(
                phase: canonicalApplyPhase(for: action),
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: canonicalApplyActionResult(action)
            )
        }
        if !libraryPlan.fallbackRequiredObjectIDs.isEmpty {
            diagnosticsStore.record(
                phase: "canonicalDomainFallback",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "domain=libraryObjects,count=\(libraryPlan.fallbackRequiredObjectIDs.count)"
            )
        }
    }

    private func canonicalTransferProjection(
        legacyPlan: LocalNetworkSyncDiffPlan,
        canonicalPlan: CanonicalSyncPlan,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan
    ) -> CanonicalTransferProjection {
        var jobs: [CanonicalTransferJob] = []
        jobs += legacyPlan.uploadRecordingAudioActions.map { action in
            CanonicalTransferStateMachine.job(
                objectID: action.entityID,
                artifactID: "audio:\(action.entityID)",
                kind: .recordingAudioUpload,
                direction: .localToPeer,
                legacyState: "planned",
                source: "legacyPlan"
            )
        }
        jobs += canonicalPlan.downloadGeneratedArtifact.map { action in
            CanonicalTransferStateMachine.job(
                objectID: action.objectID,
                artifactID: action.artifactID,
                kind: .generatedArtifactDownload,
                direction: .peerToLocal,
                legacyState: "planned",
                source: "canonicalPlan"
            )
        }
        jobs += (applyPlan.actions + libraryPlan.applyActions).compactMap { action -> CanonicalTransferJob? in
            guard let kind = transferKind(for: action.kind) else {
                return nil
            }
            let direction: CanonicalTransferDirection = action.source == .peer ? .peerToLocal : .localToPeer
            return CanonicalTransferStateMachine.job(
                objectID: action.target.objectID,
                artifactID: action.target.artifactID,
                kind: kind,
                direction: direction,
                legacyState: action.result == .deferredUnsupported ? "unsupported" : "planned",
                failureCode: action.failureReason?.rawValue,
                source: "canonicalApply"
            )
        }
        return CanonicalTransferStateMachine.projection(from: jobs)
    }

    private func transferKind(for actionKind: CanonicalApplyActionKind) -> CanonicalTransferKind? {
        switch actionKind {
        case .recordingMetadataSend:
            return .metadataSend
        case .recordingMetadataApply:
            return .metadataApply
        case .folderMetadataSend:
            return .folderMetadataSend
        case .folderMetadataApply:
            return .folderMetadataApply
        case .studyItemMetadataSend:
            return .studyItemMetadataSend
        case .studyItemMetadataApply:
            return .studyItemMetadataApply
        case .objectTombstoneSend, .libraryTombstoneSend:
            return .tombstoneSend
        case .objectTombstoneApply, .libraryTombstoneApply:
            return .tombstoneApply
        case .generatedArtifactDownloadApply:
            return .generatedArtifactDownload
        case .generatedArtifactNoOp, .artifactTombstoneApply, .conflictRecord, .deferredUnsupported:
            return nil
        }
    }

    private func recordCanonicalTransferProjectionDiagnostics(
        _ projection: CanonicalTransferProjection,
        deviceID: String,
        syncRunID: String
    ) {
        diagnosticsStore.record(
            phase: "canonicalTransferStateProjected",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "jobs=\(projection.jobs.count),inFlight=\(projection.jobs.filter { $0.phase == .inFlight }.count),deferred=\(projection.jobs.filter { $0.phase == .deferred }.count),unsupported=\(projection.jobs.filter { $0.phase == .unsupported }.count)"
        )
    }

    private func recordCanonicalObjectProjectionDiagnostics(
        _ projection: CanonicalLibraryProjection,
        deviceID: String,
        syncRunID: String
    ) {
        diagnosticsStore.record(
            phase: "canonicalObjectProjectionBuilt",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "recordings=\(projection.recordings.count),folders=\(projection.folders.count),studyItems=\(projection.studyItems.count),readOnly=true"
        )
    }

    private func recordCanonicalRetirementReadiness(
        _ report: CanonicalRetirementReadinessReport,
        deviceID: String,
        syncRunID: String
    ) {
        let blocked = report.statuses.filter { $0.value == .blocked }.map { $0.key.rawValue }.sorted()
        diagnosticsStore.record(
            phase: "canonicalRetirementReadinessReportWritten",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "blocked=\(blocked.joined(separator: "+")),blockers=\(report.blockers.count),diagnosticsOnly=true"
        )
    }

    private func canonicalApplyPhase(for action: CanonicalApplyAction) -> String {
        switch action.kind {
        case .recordingMetadataApply:
            return "canonicalRecordingMetadataApplyPlanned"
        case .recordingMetadataSend:
            return "canonicalRecordingMetadataSendPlanned"
        case .folderMetadataApply:
            return "canonicalFolderMetadataApplyPlanned"
        case .folderMetadataSend:
            return "canonicalFolderMetadataSendPlanned"
        case .studyItemMetadataApply:
            return "canonicalStudyItemMetadataApplyPlanned"
        case .studyItemMetadataSend:
            return "canonicalStudyItemMetadataSendPlanned"
        case .libraryTombstoneApply:
            return "canonicalLibraryTombstoneApplyPlanned"
        case .libraryTombstoneSend:
            return "canonicalLibraryTombstoneSendPlanned"
        case .generatedArtifactDownloadApply:
            return "canonicalGeneratedArtifactApplyPlanned"
        case .generatedArtifactNoOp:
            return "canonicalGeneratedArtifactApplyNoOp"
        case .objectTombstoneApply:
            return "canonicalObjectTombstoneApplyPlanned"
        case .objectTombstoneSend:
            return "canonicalObjectTombstoneSendPlanned"
        case .artifactTombstoneApply:
            return "canonicalArtifactTombstoneUnsupported"
        case .conflictRecord:
            return "canonicalConflictRecordCreated"
        case .deferredUnsupported:
            return "canonicalApplyUnsupportedDeferred"
        }
    }

    private func canonicalDiagnosticResult(_ diagnostic: CanonicalSyncPlanBridgeDiagnostics) -> String {
        [
            "reason=\(diagnostic.reason.rawValue)",
            "object=\(diagnostic.objectID.map(safePrefix) ?? "missing")",
            "artifact=\(diagnostic.artifactID.map(safePrefix) ?? "missing")",
            "detail=\(diagnostic.detail ?? "none")"
        ].joined(separator: ",")
    }

    private func canonicalArtifactActionResult(_ action: CanonicalArtifactTransferAction) -> String {
        [
            "recording=\(safePrefix(action.objectID))",
            "artifact=\(action.artifactID.map(safePrefix) ?? "missing")",
            "kind=\(action.kind?.rawValue ?? "unknown")",
            "reason=\(action.reason.rawValue)",
            "localHash=\(action.localHash.map { safePrefix($0.value) } ?? "missing")",
            "peerHash=\(action.peerHash.map { safePrefix($0.value) } ?? "missing")",
            "localSize=\(action.localByteSize.map(String.init) ?? "missing")",
            "peerSize=\(action.peerByteSize.map(String.init) ?? "missing")"
        ].joined(separator: ",")
    }

    private func canonicalApplyActionResult(_ action: CanonicalApplyAction) -> String {
        let preconditions = action.preconditions.map { "\($0.kind.rawValue)=\($0.value)" }.joined(separator: "+")
        return [
            "recording=\(safePrefix(action.target.objectID))",
            "artifact=\(action.target.artifactID.map(safePrefix) ?? "missing")",
            "kind=\(action.target.artifactKind?.rawValue ?? "object")",
            "action=\(action.kind.rawValue)",
            "source=\(action.source.rawValue)",
            "bridge=\(action.bridgeHint?.rawValue ?? "none")",
            "result=\(action.result.rawValue)",
            "failure=\(action.failureReason?.rawValue ?? "none")",
            "reason=\(action.reason)",
            "preconditions=\(preconditions.isEmpty ? "none" : preconditions)"
        ].joined(separator: ",")
    }

    private func isCanonicalGeneratedArtifactVerificationError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("checksum_mismatch")
            || message.contains("size_mismatch")
            || message.contains("hash_mismatch")
    }

    private func canonicalFallbackReason(_ error: Error) -> String {
        if let error = error as? CanonicalSyncPlanError {
            switch error {
            case let .incompatibleSchema(local, peer):
                return "canonicalSchemaUnsupported:local=\(local),peer=\(peer)"
            case let .invalidManifestHash(side):
                return "canonicalManifestValidationFailed:\(side)"
            case let .missingCapability(side, capability):
                return "canonicalCapabilityMissing:\(side):\(capability.rawValue)"
            }
        }
        return "canonicalPlannerFailed:\(String(error.localizedDescription.prefix(64)))"
    }

    private func recordWeakCompareDiagnostics(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        deviceID: String,
        syncRunID: String
    ) {
        for action in allTransferAndConflictActions(plan) {
            let pair = objectPair(for: action, localInventory: localInventory, peerInventory: peerInventory)
            let usedWeakCompare = [pair.local, pair.peer].compactMap { $0 }.contains { object in
                object.sha256 == nil || object.size == nil
            }
            guard usedWeakCompare else {
                continue
            }
            diagnosticsStore.record(
                phase: "weakCompareUsed",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "objectKind=\(action.entityKind),objectID=\(action.entityID),reason=\(action.reason)"
            )
        }
    }

    private func recordRecordingAudioAvailabilityDiagnostics(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        deviceID: String,
        syncRunID: String,
        triggerSource: RecordingAudioSyncTriggerSource
    ) {
        let transferJobs = (try? transferJobStore.loadJobs()) ?? []
        let uploadJobsByRecordingID = ((try? uploadJobStore.loadJobs()) ?? []).reduce(into: [String: RecordingUploadJob]()) { result, job in
            result[job.recordingID] = job
        }
        for localRecording in localInventory.recordings where localRecording.audioAvailable {
            let recordingID = localRecording.recordingID
            let objectID = audioTransferArtifactID(recordingID: recordingID)
            let localAudio = recordingAudioState(recordingID: recordingID, in: localInventory)
            let peerAudio = recordingAudioState(recordingID: recordingID, in: peerInventory)
            let localDecisionState = localAudioDecisionState(recordingID: recordingID, in: localInventory)
            let peerDecisionState = peerAudioDecisionState(recordingID: recordingID, in: peerInventory, localAudioState: localDecisionState)
            let transferState = transferJobState(
                transferID: transferID(direction: .upload, artifactID: objectID),
                transferJobs: transferJobs
            )
            let ledgerState = uploadLedgerState(uploadJobsByRecordingID[recordingID])
            let decision = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
                localAudioState: localDecisionState,
                peerAudioState: peerDecisionState,
                transferJobState: transferState,
                ledgerState: ledgerState,
                triggerSource: triggerSource,
                syncRunID: syncRunID,
                objectID: objectID,
                recordingID: recordingID
            )
            recordRecordingAudioDecisionDiagnostics(
                recordingID: recordingID,
                objectID: objectID,
                logicalPathToken: localRecording.audioLogicalPathToken,
                triggerSource: triggerSource,
                localAudioState: localDecisionState,
                peerAudioState: peerDecisionState,
                transferJobState: transferState,
                ledgerState: ledgerState,
                decision: decision,
                deviceID: deviceID,
                syncRunID: syncRunID
            )
            diagnosticsStore.record(
                phase: "syncDiffEvaluatedRecording",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "recording=\(safePrefix(recordingID))"
            )
            if peerAudio.isAvailable {
                diagnosticsStore.record(
                    phase: "syncPeerAudioAvailable",
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "recording=\(safePrefix(recordingID)),size=\(peerAudio.size.map(String.init) ?? "missing")"
                )
                diagnosticsStore.record(
                    phase: audioSignaturesMatch(localAudio, peerAudio) ? "syncPeerAudioHashMatched" : "syncPeerAudioHashMismatched",
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "recording=\(safePrefix(recordingID)),localHash=\(hashPrefix(localAudio.checksum)),peerHash=\(hashPrefix(peerAudio.checksum))"
                )
            } else if peerInventory.recordings.contains(where: { $0.recordingID == recordingID }) {
                diagnosticsStore.record(
                    phase: "syncPeerAudioMissing",
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "recording=\(safePrefix(recordingID))"
                )
            }
        }
    }

    private func recordCanonicalRecordingExistenceTruthDiagnostics(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        deviceID: String,
        syncRunID: String
    ) {
        guard let localManifest = localInventory.canonicalManifest else {
            return
        }

        let peerObjectsByID = Dictionary(
            uniqueKeysWithValues: (peerInventory.canonicalManifest?.objects ?? []).map { ($0.objectID, $0) }
        )
        let peerKnown = peerInventory.canonicalManifest != nil
        let mode = canonicalSyncRuntimeConfiguration.mode

        for localObject in localManifest.objects {
            let recordingID = localObject.objectID
            let peerRecording = peerInventory.recordings.first { $0.recordingID == recordingID }
            let peerStudyItemExists = peerInventory.studyItems.contains {
                $0.recordingID == recordingID && !$0.deleted
            }
            let peerReceiveRecordExists = peerRecording != nil
            let peerCompletedLedgerOnly = peerRecording?.uploadLedgerState == RecordingUploadJobOverallState.succeeded.rawValue
                && peerRecording?.audioAvailable != true
            let truth = CanonicalRecordingExistenceTruth.evaluate(
                objectID: recordingID,
                local: localObject,
                peer: peerObjectsByID[recordingID],
                peerKnown: peerKnown,
                peerStudyItemExists: peerStudyItemExists,
                peerReceiveRecordExists: peerReceiveRecordExists,
                peerCompletedLedgerOnly: peerCompletedLedgerOnly,
                tombstonedParent: peerRecording?.tombstone == true || peerRecording?.deleted == true
            )

            for diagnostic in truth.diagnostics(syncRunID: syncRunID, mode: mode) where diagnostic.isRedacted {
                diagnosticsStore.record(
                    phase: diagnostic.kind.rawValue,
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: diagnostic.summary()
                )
            }
        }
    }

    private func recordConflictDiagnostics(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        deviceID: String,
        syncRunID: String
    ) {
        for action in plan.conflictActions {
            let pair = objectPair(for: action, localInventory: localInventory, peerInventory: peerInventory)
            let winner: String
            let loser: String
            if let local = pair.local, let peer = pair.peer {
                if local.updatedAt >= peer.updatedAt {
                    winner = "local"
                    loser = "peer"
                } else {
                    winner = "peer"
                    loser = "local"
                }
            } else {
                winner = "undetermined"
                loser = "undetermined"
            }
            diagnosticsStore.record(
                phase: "conflictDetected",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: [
                    "objectKind=\(action.entityKind)",
                    "objectID=\(action.entityID)",
                    "winner=\(winner)",
                    "loser=\(loser)",
                    "localHash=\(hashPrefix(pair.local?.sha256))",
                    "peerHash=\(hashPrefix(pair.peer?.sha256))",
                    "localUpdatedAt=\(timestampText(pair.local?.updatedAt))",
                    "peerUpdatedAt=\(timestampText(pair.peer?.updatedAt))",
                    "reason=\(action.reason)"
                ].joined(separator: ",")
            )
        }
    }

    private func allTransferAndConflictActions(_ plan: LocalNetworkSyncDiffPlan) -> [LocalNetworkSyncDiffAction] {
        plan.uploadMetadataActions
            + plan.uploadArtifactActions
            + plan.downloadMetadataActions
            + plan.downloadArtifactActions
            + plan.uploadRecordingAudioActions
            + plan.conflictActions
    }

    private func objectPair(
        for action: LocalNetworkSyncDiffAction,
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory
    ) -> (local: LocalNetworkSyncObjectEntry?, peer: LocalNetworkSyncObjectEntry?) {
        (
            matchingObject(for: action, in: localInventory.objects),
            matchingObject(for: action, in: peerInventory.objects)
        )
    }

    private func matchingObject(for action: LocalNetworkSyncDiffAction, in objects: [LocalNetworkSyncObjectEntry]) -> LocalNetworkSyncObjectEntry? {
        if action.entityKind == "artifact" {
            return objects.first { $0.objectID == action.entityID }
        }
        let expectedKind: LocalNetworkSyncObjectKind?
        switch action.entityKind {
        case "recording":
            expectedKind = .recordingMetadata
        case "folder":
            expectedKind = .studyFolder
        case "studyItem":
            expectedKind = .studyItem
        default:
            expectedKind = nil
        }
        return objects.first { object in
            (expectedKind == nil || object.objectKind == expectedKind)
                && (object.ownerID == action.entityID || object.objectID == action.entityID)
        }
    }

    private func hashPrefix(_ hash: String?) -> String {
        guard let hash, !hash.isEmpty else {
            return "missing"
        }
        return String(hash.prefix(12))
    }

    private func timestampText(_ date: Date?) -> String {
        guard let date else {
            return "missing"
        }
        return String(format: "%.0f", date.timeIntervalSince1970)
    }

    private func produceCanonicalStatusFactsFromLocalInventory(
        _ inventory: LocalNetworkSyncInventory,
        deviceID: String,
        syncRunID: String
    ) async {
        let producer = CanonicalNodeID("iphone-\(inventory.sourceDeviceID)")
        var facts: [CanonicalStatusFact] = []
        for recording in inventory.recordings {
            let objectID = CanonicalObjectID("recordingAudio:\(recording.recordingID)")
            let counter = logicalCounter(recording.updatedAt)
            if recording.audioAvailable,
               let checksum = recording.audioChecksum,
               let audioSize = recording.audioSize {
                facts.append(
                    statusFact(
                        id: "iphone-local-\(safePrefix(recording.recordingID))-\(safePrefix(checksum))-\(audioSize)",
                        objectID: objectID,
                        source: .localFileObservation,
                        producer: producer,
                        counter: counter,
                        proofKind: .localFileExists,
                        phase: .localOnly,
                        hash: checksum,
                        byteSize: audioSize
                    )
                )
            }
            if recording.uploadLedgerState == "inFlight" || recording.uploadLedgerState == "uploading" {
                facts.append(
                    statusFact(
                        id: "iphone-session-\(safePrefix(recording.recordingID))-\(counter)",
                        objectID: objectID,
                        source: .transferSession,
                        producer: producer,
                        counter: counter,
                        proofKind: .peerUnknown,
                        phase: .uploading
                    )
                )
            }
        }
        for artifact in inventory.artifacts where artifact.availability == .local || artifact.availability == .complete {
            guard let checksum = artifact.checksum, let size = artifact.size else {
                continue
            }
            facts.append(
                statusFact(
                    id: "iphone-artifact-\(safePrefix(artifact.artifactID))-\(safePrefix(checksum))-\(size)",
                    objectID: CanonicalObjectID("generatedArtifact:\(artifact.artifactID)"),
                    domain: .generatedArtifacts,
                    source: .fileObservation,
                    producer: producer,
                    counter: logicalCounter(artifact.updatedAt),
                    proofKind: .sameHashAndByteSize,
                    phase: .peerVerified,
                    hash: checksum,
                    byteSize: size
                )
            )
        }
        await produceCanonicalStatusFacts(facts, deviceID: deviceID, syncRunID: syncRunID)
    }

    private func produceCanonicalStatusFactsFromPeerInventory(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        deviceID: String,
        syncRunID: String
    ) async {
        let producer = CanonicalNodeID("mac-\(peerInventory.sourceDeviceID)")
        let localByID = Dictionary(uniqueKeysWithValues: localInventory.recordings.map { ($0.recordingID, $0) })
        var facts: [CanonicalStatusFact] = []
        for peerRecording in peerInventory.recordings {
            let objectID = CanonicalObjectID("recordingAudio:\(peerRecording.recordingID)")
            let counter = logicalCounter(peerRecording.updatedAt)
            if peerRecording.audioAvailable,
               let checksum = peerRecording.audioChecksum,
               let audioSize = peerRecording.audioSize {
                facts.append(
                    statusFact(
                        id: "mac-peer-\(safePrefix(peerRecording.recordingID))-\(safePrefix(checksum))-\(audioSize)",
                        objectID: objectID,
                        source: .peerInventory,
                        producer: producer,
                        counter: counter,
                        proofKind: .peerInventoryHashSizeMatch,
                        phase: .peerVerified,
                        hash: checksum,
                        byteSize: audioSize,
                        peerNodeID: producer
                    )
                )
                diagnosticsStore.record(
                    phase: "statusConvergenceFinalizeProofAccepted",
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "peerVerifiedHashSize"
                )
            } else {
                facts.append(
                    statusFact(
                        id: "mac-metadataOnly-\(safePrefix(peerRecording.recordingID))-\(counter)",
                        objectID: objectID,
                        source: .peerMetadata,
                        producer: producer,
                        counter: counter,
                        proofKind: .metadataOnly,
                        phase: .peerKnownMetadataOnly,
                        peerNodeID: producer
                    )
                )
                diagnosticsStore.record(
                    phase: "peerProofUnavailable",
                    deviceID: deviceID,
                    syncRunID: syncRunID,
                    result: "metadataOnly"
                )
            }
            if let local = localByID[peerRecording.recordingID],
               local.audioAvailable,
               !peerRecording.audioAvailable {
                facts.append(
                    statusFact(
                        id: "iphone-uploadNeeded-\(safePrefix(peerRecording.recordingID))-\(counter)",
                        objectID: objectID,
                        source: .syncRuntime,
                        producer: CanonicalNodeID("iphone-\(localInventory.sourceDeviceID)"),
                        counter: max(counter, logicalCounter(local.updatedAt)),
                        proofKind: .metadataOnly,
                        phase: .uploadNeeded,
                        peerNodeID: producer,
                        causality: CanonicalStatusCausality(trigger: .eventDrivenSync)
                    )
                )
            }
        }
        for artifact in peerInventory.artifacts where artifact.availability == .availableOnPeer || artifact.availability == .local || artifact.availability == .complete {
            guard let checksum = artifact.checksum, let size = artifact.size else {
                continue
            }
            facts.append(
                statusFact(
                    id: "mac-artifact-\(safePrefix(artifact.artifactID))-\(safePrefix(checksum))-\(size)",
                    objectID: CanonicalObjectID("generatedArtifact:\(artifact.artifactID)"),
                    domain: .generatedArtifacts,
                    source: .peerInventory,
                    producer: producer,
                    counter: logicalCounter(artifact.updatedAt),
                    proofKind: .sameHashAndByteSize,
                    phase: .peerVerified,
                    hash: checksum,
                    byteSize: size,
                    peerNodeID: producer
                )
            )
        }
        await produceCanonicalStatusFacts(facts, deviceID: deviceID, syncRunID: syncRunID)
    }

    private func produceCanonicalStatusFacts(
        _ facts: [CanonicalStatusFact],
        deviceID: String,
        syncRunID: String
    ) async {
        guard !facts.isEmpty else {
            return
        }
        let results = await canonicalStatusTruthRuntime.produce(facts)
        let rejectedCount = results.filter {
            $0.decision == .rejectedExpired || $0.decision == .rejectedStale
        }.count
        await bridgeCanonicalStatusProjections(
            for: facts.map(\.objectID),
            deviceID: deviceID,
            syncRunID: syncRunID,
            source: "inventoryFacts"
        )
        if rejectedCount > 0 {
            diagnosticsStore.record(
                phase: "statusFactRejected",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "rejected=\(rejectedCount)",
                errorCode: "status_fact_rejected"
            )
        }
    }

    private func bridgeCanonicalStatusProjections(
        for objectIDs: [CanonicalObjectID],
        deviceID: String,
        syncRunID: String?,
        source: String
    ) async {
        let uniqueObjectIDs = Array(Set(objectIDs)).sorted()
        guard !uniqueObjectIDs.isEmpty else {
            return
        }
        var bridgedCount = 0
        for objectID in uniqueObjectIDs {
            guard let snapshot = await canonicalStatusTruthRuntime.projectionSnapshot(for: objectID) else {
                continue
            }
            studyLibraryStore.applyCanonicalStatusProjection(snapshot)
            uploadCoordinator?.applyCanonicalStatusProjection(snapshot)
            bridgedCount += 1
        }
        _ = (deviceID, syncRunID, source, bridgedCount)
    }

    private func statusFact(
        id: String,
        objectID: CanonicalObjectID,
        domain: CanonicalStatusDomain = .audioUpload,
        source: CanonicalStatusSource,
        producer: CanonicalNodeID,
        counter: UInt64,
        proofKind: CanonicalStatusProofKind,
        phase: CanonicalStatusPhase,
        hash: String? = nil,
        byteSize: Int64? = nil,
        peerNodeID: CanonicalNodeID? = nil,
        causality: CanonicalStatusCausality = .ordinarySync
    ) -> CanonicalStatusFact {
        CanonicalStatusFact(
            factID: id,
            objectID: objectID,
            source: source,
            producerNodeID: producer,
            logicalTime: CanonicalLogicalTime(counter: counter, nodeID: producer),
            proof: CanonicalStatusProof(
                kind: proofKind,
                objectID: objectID,
                hash: hash.map { CanonicalHash($0) },
                byteSize: byteSize,
                peerNodeID: peerNodeID,
                observedAt: CanonicalTimestamp(Date())
            ),
            domain: domain,
            phase: phase,
            causality: causality
        )
    }

    private func logicalCounter(_ date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince1970.rounded()))
    }

    @discardableResult
    private func consumeCanonicalInventoryStatusExchangeEnvelope(
        _ envelope: CanonicalStatusExchangeEnvelope?,
        deviceID: String,
        syncRunID: String
    ) async -> CanonicalStatusExchangeReceiveResult {
        let result = await canonicalStatusExchangeRuntime.consumeIncomingEnvelope(envelope, carrier: .inventory)
        guard envelope != nil else {
            return result
        }
        diagnosticsStore.record(
            phase: "statusEnvelopeCarriedOverInventory",
            deviceID: deviceID,
            syncRunID: syncRunID,
            result: "response"
        )
        if envelope?.delta != nil {
            diagnosticsStore.record(
                phase: "statusDeltaReceived",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "facts=\(result.incorporatedFactCount),rejected=\(result.rejectedFactCount)"
            )
            await bridgeCanonicalStatusProjections(
                for: envelope?.delta?.facts.map(\.objectID) ?? [],
                deviceID: deviceID,
                syncRunID: syncRunID,
                source: "inventoryEnvelope"
            )
        }
        if envelope?.ack != nil {
            diagnosticsStore.record(phase: "statusAckReceived", deviceID: deviceID, syncRunID: syncRunID, result: envelope?.ack?.disposition.rawValue)
        }
        if envelope?.request != nil {
            diagnosticsStore.record(phase: "statusRequestReceived", deviceID: deviceID, syncRunID: syncRunID, result: envelope?.request?.kind.rawValue)
        }
        if !result.accepted || result.rejectedFactCount > 0 {
            diagnosticsStore.record(
                phase: "statusFactRejected",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: result.reason,
                errorCode: result.stale ? "stale_status_envelope" : "status_fact_rejected"
            )
        }
        for action in result.requestedActions {
            switch action {
            case .enqueueRunSyncSoon:
                LocalNetworkSyncEventTrigger.post(.syncStatusRefreshRequested, source: "CanonicalStatusExchangeRuntime.runSyncSoon")
            case .requestLightweightAudioProof:
                diagnosticsStore.record(phase: "peerProofUnavailable", deviceID: deviceID, syncRunID: syncRunID, result: "sendAudioProofRequestObserved")
            case .requestFullInventory:
                diagnosticsStore.record(phase: "fullInventoryRequested", deviceID: deviceID, syncRunID: syncRunID, result: "requestOnly")
                LocalNetworkSyncEventTrigger.post(.syncStatusRefreshRequested, source: "CanonicalStatusExchangeRuntime.fullInventory")
            }
        }
        return result
    }

    private func applyPeerRecordingStatuses(peerInventory: LocalNetworkSyncInventory) throws {
        var didChange = false
        for peerRecording in peerInventory.recordings where peerRecording.receiveStatus == "completed" {
            guard recordingAudioState(recordingID: peerRecording.recordingID, in: peerInventory).isAvailable else {
                continue
            }
            guard let localMetadata = try? audioFileStore.loadMetadata(id: peerRecording.recordingID),
                  RecordingUploadStatus(rawMetadataValue: localMetadata.uploadStatus) != .uploaded else {
                continue
            }
            try audioFileStore.updateMetadata(localMetadata.updatingUploadStatus(.uploaded))
            didChange = true
        }
        if didChange {
            recordingManager?.reloadRecordings()
        }
    }

    private func applyPeerMetadataIfNeeded(
        peerInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        localDeviceID: String
    ) async throws {
        guard !plan.downloadMetadataActions.isEmpty,
              let manifest = peerInventory.studyManifest else {
            return
        }
        _ = try await studyLibraryStore.applySyncManifest(manifest, localDeviceID: localDeviceID)
        diagnosticsStore.record(phase: "metadataApplied", deviceID: localDeviceID)
        if plan.downloadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.recordingMetadataApply.rawValue }) {
            diagnosticsStore.record(phase: "canonicalRecordingMetadataAppliedFromCanonical", deviceID: localDeviceID)
        }
        if plan.downloadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.objectTombstoneApply.rawValue }) {
            diagnosticsStore.record(phase: "canonicalObjectTombstoneAppliedFromCanonical", deviceID: localDeviceID)
        }
        if plan.downloadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.folderMetadataApply.rawValue }) {
            diagnosticsStore.record(phase: "canonicalFolderMetadataAppliedFromCanonical", deviceID: localDeviceID)
        }
        if plan.downloadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.studyItemMetadataApply.rawValue }) {
            diagnosticsStore.record(phase: "canonicalStudyItemMetadataAppliedFromCanonical", deviceID: localDeviceID)
        }
        if plan.downloadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.libraryTombstoneApply.rawValue }) {
            diagnosticsStore.record(phase: "canonicalLibraryTombstoneAppliedFromCanonical", deviceID: localDeviceID)
        }
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
    }

    private func uploadLocalMetadataIfNeeded(
        localInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        settings: SecureMacConnectionSnapshot,
        syncRunID: String,
        forceSend: Bool = false
    ) async throws {
        guard (forceSend || !plan.uploadMetadataActions.isEmpty),
              let manifest = localInventory.studyManifest else {
            return
        }
        diagnosticsStore.record(phase: "uploadActionStarted", deviceID: settings.deviceID, syncRunID: syncRunID)
        do {
            let response = try await client.applyLocalNetworkSyncMetadata(settings: settings, manifest: manifest)
            guard response.ok else {
                throw SecureMacUploadError.serverRejected(response.error ?? "sync_apply_metadata_failed")
            }
            diagnosticsStore.record(phase: "uploadActionCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
            if plan.uploadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.recordingMetadataSend.rawValue }) {
                diagnosticsStore.record(phase: "canonicalRecordingMetadataSentFromCanonical", deviceID: settings.deviceID, syncRunID: syncRunID)
            }
            if plan.uploadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.objectTombstoneSend.rawValue }) {
                diagnosticsStore.record(phase: "canonicalObjectTombstoneSentFromCanonical", deviceID: settings.deviceID, syncRunID: syncRunID)
            }
            if plan.uploadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.folderMetadataSend.rawValue }) {
                diagnosticsStore.record(phase: "canonicalFolderMetadataSentFromCanonical", deviceID: settings.deviceID, syncRunID: syncRunID)
            }
            if plan.uploadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.studyItemMetadataSend.rawValue }) {
                diagnosticsStore.record(phase: "canonicalStudyItemMetadataSentFromCanonical", deviceID: settings.deviceID, syncRunID: syncRunID)
            }
            if plan.uploadMetadataActions.contains(where: { $0.reason == CanonicalApplyActionKind.libraryTombstoneSend.rawValue }) {
                diagnosticsStore.record(phase: "canonicalLibraryTombstoneSentFromCanonical", deviceID: settings.deviceID, syncRunID: syncRunID)
            }
        } catch {
            diagnosticsStore.record(phase: "uploadActionFailed", deviceID: settings.deviceID, syncRunID: syncRunID, errorCode: "sync_apply_metadata_failed", errorMessage: error.localizedDescription)
            throw error
        }
    }

    private func downloadPeerArtifactsIfNeeded(
        peerInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        settings: SecureMacConnectionSnapshot,
        syncRunID: String
    ) async throws {
        let artifactsByID = Dictionary(uniqueKeysWithValues: peerInventory.artifacts.map { ($0.artifactID, $0) })
        for action in plan.downloadArtifactActions {
            guard let artifact = artifactsByID[action.entityID],
                  artifact.kind.isAutoDownloadAllowed else {
                continue
            }
            diagnosticsStore.record(phase: "downloadActionStarted", deviceID: settings.deviceID, syncRunID: syncRunID)
            do {
                try await downloadPeerArtifact(artifact, peerInventory: peerInventory, settings: settings, syncRunID: syncRunID)
                if action.reason == CanonicalApplyActionKind.generatedArtifactDownloadApply.rawValue {
                    diagnosticsStore.record(
                        phase: "canonicalGeneratedArtifactHashVerifiedBeforeApply",
                        deviceID: settings.deviceID,
                        syncRunID: syncRunID,
                        result: "recording=\(safePrefix(artifact.ownerID)),artifact=\(safePrefix(artifact.artifactID)),kind=\(artifact.kind.rawValue)"
                    )
                }
                diagnosticsStore.record(phase: "downloadActionCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
            } catch {
                if action.reason == CanonicalApplyActionKind.generatedArtifactDownloadApply.rawValue,
                   isCanonicalGeneratedArtifactVerificationError(error) {
                    diagnosticsStore.record(
                        phase: "canonicalGeneratedArtifactHashMismatchAfterDownload",
                        deviceID: settings.deviceID,
                        syncRunID: syncRunID,
                        errorCode: "canonical_generated_artifact_verification_failed",
                        errorMessage: "recording=\(safePrefix(artifact.ownerID)),artifact=\(safePrefix(artifact.artifactID)),kind=\(artifact.kind.rawValue)"
                    )
                }
                try? failTransferJob(
                    direction: .download,
                    artifactID: artifact.artifactID,
                    errorCode: "sync_artifact_download_failed",
                    errorMessage: error.localizedDescription
                )
                try? saveTransferProgress(
                    for: artifact,
                    peerInventory: peerInventory,
                    state: .failed,
                    progressFraction: nil,
                    statusText: "传输失败"
                )
                diagnosticsStore.record(phase: "transferFailed", deviceID: settings.deviceID, syncRunID: syncRunID, errorCode: "sync_artifact_download_failed", errorMessage: error.localizedDescription)
                diagnosticsStore.record(phase: "downloadActionFailed", deviceID: settings.deviceID, syncRunID: syncRunID, errorCode: "sync_artifact_download_failed", errorMessage: error.localizedDescription)
                throw error
            }
        }
    }

    private func downloadPeerArtifact(
        _ artifact: LocalNetworkSyncArtifactEntry,
        peerInventory: LocalNetworkSyncInventory,
        settings: SecureMacConnectionSnapshot,
        syncRunID: String
    ) async throws {
        try beginTransferJob(
            direction: .download,
            ownerID: artifact.ownerID,
            artifactID: artifact.artifactID,
            objectKind: artifact.kind.rawValue,
            logicalName: artifact.logicalPathToken,
            totalBytes: artifact.size,
            transferredBytes: 0,
            sha256: artifact.checksum,
            peerDeviceID: peerInventory.sourceDeviceID,
            deviceID: settings.deviceID,
            syncRunID: syncRunID
        )
        try saveTransferProgress(
            for: artifact,
            peerInventory: peerInventory,
            state: .transferring,
            progressFraction: 0,
            statusText: "传输中"
        )
        stateStore.recordActiveTransfers([
            transferProgress(for: artifact, peerInventory: peerInventory, state: .transferring, progressFraction: 0, statusText: "传输中")
        ])

        let expectedSize = artifact.size ?? 0
        if expectedSize > Self.maxSmallArtifactUploadBytes {
            try await downloadPeerArtifactInChunks(artifact, peerInventory: peerInventory, settings: settings, expectedSize: expectedSize, syncRunID: syncRunID)
        } else {
            let response = try await client.requestLocalNetworkSyncArtifact(settings: settings, request: LocalNetworkSyncArtifactRequest(artifactID: artifact.artifactID, syncRunID: syncRunID))
            try updateTransferJob(
                direction: .download,
                artifactID: artifact.artifactID,
                state: .verifying,
                transferredBytes: response.size ?? artifact.size ?? 0,
                nextOffset: response.size ?? artifact.size ?? 0
            )
            try saveTransferProgress(
                for: artifact,
                peerInventory: peerInventory,
                state: .verifying,
                progressFraction: 1,
                statusText: "校验中"
            )
            diagnosticsStore.record(phase: "transferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID)
            diagnosticsStore.record(phase: "fileTransferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID)
            try writeArtifactResponse(response, expectedArtifact: artifact, deviceID: settings.deviceID)
        }

        try completeTransferJob(direction: .download, artifactID: artifact.artifactID)
        try clearTransferProgress(for: artifact, peerInventory: peerInventory)
        stateStore.recordActiveTransfers([])
        diagnosticsStore.record(phase: "transferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
        diagnosticsStore.record(phase: "fileTransferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
    }

    private func downloadPeerArtifactInChunks(
        _ artifact: LocalNetworkSyncArtifactEntry,
        peerInventory: LocalNetworkSyncInventory,
        settings: SecureMacConnectionSnapshot,
        expectedSize: Int64,
        syncRunID: String
    ) async throws {
        let tempURL = try localIncomingTempURL(for: artifact.artifactID)
        let statusResponse = try await client.fetchLocalNetworkSyncArtifactStatus(
            settings: settings,
            request: LocalNetworkSyncArtifactStatusRequest(
                artifactID: artifact.artifactID,
                checksum: artifact.checksum,
                size: artifact.size,
                syncRunID: syncRunID
            )
        )
        guard statusResponse.ok else {
            throw SecureMacUploadError.serverRejected(statusResponse.error ?? "sync_artifact_status_failed")
        }
        diagnosticsStore.record(phase: "transferSessionStatusFetched", deviceID: settings.deviceID, syncRunID: syncRunID)

        var offset: Int64 = 0
        let existingTempSize = LocalNetworkSyncArtifactFileService.metadata(for: tempURL)?.size ?? 0
        if existingTempSize > expectedSize {
            diagnosticsStore.record(
                phase: "transferOffsetMismatch",
                deviceID: settings.deviceID,
                syncRunID: syncRunID,
                errorCode: "local_temp_larger_than_expected"
            )
            try FileManager.default.removeItem(at: tempURL)
        } else if existingTempSize > 0 {
            offset = existingTempSize
            try updateTransferJob(
                direction: .download,
                artifactID: artifact.artifactID,
                state: .resuming,
                transferredBytes: offset,
                nextOffset: offset
            )
            diagnosticsStore.record(phase: "transferResumeAttempted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "offset=\(offset)")
            diagnosticsStore.record(phase: "transferResumed", deviceID: settings.deviceID, syncRunID: syncRunID, result: "offset=\(offset)")
        }
        if !FileManager.default.fileExists(atPath: tempURL.path) {
            _ = FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: tempURL)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: UInt64(offset))

        while offset < expectedSize {
            let length = min(Self.artifactChunkBytes, Int(expectedSize - offset))
            let response = try await client.requestLocalNetworkSyncArtifact(
                settings: settings,
                request: LocalNetworkSyncArtifactRequest(artifactID: artifact.artifactID, offset: offset, length: length, syncRunID: syncRunID)
            )
            guard response.ok,
                  let dataBase64 = response.dataBase64,
                  let data = Data(base64Encoded: dataBase64),
                  response.offset == offset,
                  response.size == Int64(data.count) else {
                throw SecureMacUploadError.serverRejected(response.error ?? "sync_artifact_chunk_missing")
            }
            if let checksum = response.checksum,
               checksum != SecureUploadUtilities.sha256Hex(data) {
                throw SecureMacUploadError.serverRejected("sync_artifact_chunk_checksum_mismatch")
            }
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
            offset += Int64(data.count)
            let fraction = expectedSize > 0 ? Double(offset) / Double(expectedSize) : 1
            try updateTransferJob(
                direction: .download,
                artifactID: artifact.artifactID,
                state: .transferring,
                transferredBytes: offset,
                nextOffset: offset
            )
            try saveTransferProgress(
                for: artifact,
                peerInventory: peerInventory,
                state: .transferring,
                progressFraction: min(max(fraction, 0), 1),
                statusText: "\(Int((fraction * 100).rounded()))%"
            )
            diagnosticsStore.record(phase: "transferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID)
            diagnosticsStore.record(phase: "fileTransferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID)
        }

        try handle.close()
        try await verifyAndApplyDownloadedArtifact(tempURL: tempURL, artifact: artifact, deviceID: settings.deviceID)
    }

    private func createPlaceholderTransfers(
        peerInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        localDeviceID: String
    ) throws {
        let transfers = transferProgresses(peerInventory: peerInventory, plan: plan, state: .pending)
        guard !transfers.isEmpty else {
            return
        }

        for transfer in transfers {
            guard let item = localStudyItem(ownerID: transfer.objectID, peerInventory: peerInventory) else {
                continue
            }
            try studyLibraryStore.save(item.withLocalNetworkTransferProgress(transfer))
            diagnosticsStore.record(phase: "placeholderCreated", deviceID: localDeviceID)
        }
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
    }

    private func transferProgresses(
        peerInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        state: LocalNetworkTransferState
    ) -> [LocalNetworkTransferProgress] {
        let artifacts = downloadableArtifacts(peerInventory: peerInventory, plan: plan)
        let grouped = Dictionary(grouping: artifacts, by: \.ownerID)
        return grouped.map { ownerID, artifacts in
            let totalBytes = artifacts.compactMap(\.size).reduce(Int64(0), +)
            return LocalNetworkTransferProgress(
                objectID: ownerID,
                objectKind: artifacts.first?.kind.rawValue ?? "artifact",
                state: state,
                progressFraction: state == .pending ? 0 : nil,
                receivedBytes: 0,
                totalBytes: totalBytes > 0 ? totalBytes : nil,
                sourceDeviceID: peerInventory.sourceDeviceID,
                statusText: state == .pending ? "等待传输" : nil
            )
        }
    }

    private func downloadableArtifacts(
        peerInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan
    ) -> [LocalNetworkSyncArtifactEntry] {
        let artifactsByID = Dictionary(uniqueKeysWithValues: peerInventory.artifacts.map { ($0.artifactID, $0) })
        return plan.downloadArtifactActions.compactMap { action in
            guard let artifact = artifactsByID[action.entityID],
                  artifact.kind.isAutoDownloadAllowed else {
                return nil
            }
            return artifact
        }
    }

    private func transferProgress(
        for artifact: LocalNetworkSyncArtifactEntry,
        peerInventory: LocalNetworkSyncInventory,
        state: LocalNetworkTransferState,
        progressFraction: Double?,
        statusText: String?
    ) -> LocalNetworkTransferProgress {
        LocalNetworkTransferProgress(
            objectID: artifact.ownerID,
            objectKind: artifact.kind.rawValue,
            state: state,
            progressFraction: progressFraction,
            receivedBytes: progressFraction == 1 ? artifact.size : 0,
            totalBytes: artifact.size,
            sourceDeviceID: peerInventory.sourceDeviceID,
            statusText: statusText
        )
    }

    private func saveTransferProgress(
        for artifact: LocalNetworkSyncArtifactEntry,
        peerInventory: LocalNetworkSyncInventory,
        state: LocalNetworkTransferState,
        progressFraction: Double?,
        statusText: String?
    ) throws {
        guard let item = localStudyItem(ownerID: artifact.ownerID, peerInventory: peerInventory) else {
            return
        }
        let progress = transferProgress(
            for: artifact,
            peerInventory: peerInventory,
            state: state,
            progressFraction: progressFraction,
            statusText: statusText
        )
        try studyLibraryStore.save(item.withLocalNetworkTransferProgress(progress))
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
    }

    private func clearTransferProgress(
        for artifact: LocalNetworkSyncArtifactEntry,
        peerInventory: LocalNetworkSyncInventory
    ) throws {
        guard let item = localStudyItem(ownerID: artifact.ownerID, peerInventory: peerInventory) else {
            return
        }
        try studyLibraryStore.save(item.withLocalNetworkTransferProgress(nil))
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
    }

    private func localStudyItem(ownerID: String, peerInventory: LocalNetworkSyncInventory) -> StudyItemMetadata? {
        studyLibraryStore.item(recordingID: ownerID)
            ?? studyLibraryStore.item(itemID: ownerID)
            ?? peerInventory.studyManifest?.items.first { $0.recordingID == ownerID || $0.itemID == ownerID }
            ?? peerInventory.studyItems.first(where: { $0.recordingID == ownerID || $0.itemID == ownerID }).map { peerItem in
                StudyItemMetadata(
                    itemID: peerItem.itemID,
                    kind: peerItem.kind,
                    title: peerItem.title,
                    createdAt: peerItem.updatedAt,
                    updatedAt: peerItem.updatedAt,
                    folderIDs: peerItem.folderIDs,
                    recordingID: peerItem.recordingID,
                    syncConflictStatus: peerItem.conflictStatus
                )
            }
    }

    private func uploadLocalArtifactsIfNeeded(
        localInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        settings: SecureMacConnectionSnapshot,
        syncRunID: String
    ) async throws {
        let artifactsByID = Dictionary(uniqueKeysWithValues: localInventory.artifacts.map { ($0.artifactID, $0) })
        let rootURL = try audioFileStore.baseDirectory()
        for action in plan.uploadArtifactActions {
            guard let artifact = artifactsByID[action.entityID],
                  artifact.kind.isAutoDownloadAllowed else {
                continue
            }

            let fileURL = try LocalNetworkSyncArtifactFileService.safeFileURL(
                rootURL: rootURL,
                logicalPathToken: artifact.logicalPathToken,
                kind: artifact.kind
            )
            guard let metadata = LocalNetworkSyncArtifactFileService.metadata(for: fileURL) else {
                continue
            }

            if metadata.size > Self.maxSmallArtifactUploadBytes {
                try await uploadLargeLocalArtifact(
                    artifact,
                    fileURL: fileURL,
                    fileSize: metadata.size,
                    settings: settings,
                    syncRunID: syncRunID
                )
                continue
            }

            let data = try Data(contentsOf: fileURL)
            let checksum = SecureUploadUtilities.sha256Hex(data)
            if let expectedChecksum = artifact.checksum,
               expectedChecksum != checksum {
                throw SecureMacUploadError.serverRejected("sync_artifact_checksum_mismatch")
            }

            let request = LocalNetworkSyncArtifactPutRequest(
                artifactID: artifact.artifactID,
                kind: artifact.kind,
                ownerID: artifact.ownerID,
                checksum: checksum,
                size: Int64(data.count),
                updatedAt: artifact.updatedAt,
                logicalPathToken: artifact.logicalPathToken,
                dataBase64: data.base64EncodedString(),
                syncRunID: syncRunID
            )
            diagnosticsStore.record(phase: "uploadActionStarted", deviceID: settings.deviceID, syncRunID: syncRunID)
            do {
                try beginTransferJob(
                    direction: .upload,
                    ownerID: artifact.ownerID,
                    artifactID: artifact.artifactID,
                    objectKind: artifact.kind.rawValue,
                    logicalName: artifact.logicalPathToken,
                    totalBytes: Int64(data.count),
                    transferredBytes: 0,
                    sha256: checksum,
                    peerDeviceID: settings.deviceID,
                    deviceID: settings.deviceID,
                    syncRunID: syncRunID
                )
                try saveLocalTransferProgress(
                    ownerID: artifact.ownerID,
                    objectKind: artifact.kind.rawValue,
                    sourceDeviceID: settings.deviceID,
                    state: .transferring,
                    progressFraction: 0,
                    receivedBytes: 0,
                    totalBytes: Int64(data.count),
                    statusText: "传输中"
                )
                stateStore.recordActiveTransfers([
                    LocalNetworkTransferProgress(
                        objectID: artifact.ownerID,
                        objectKind: artifact.kind.rawValue,
                        state: .transferring,
                        progressFraction: 0,
                        receivedBytes: 0,
                        totalBytes: Int64(data.count),
                        sourceDeviceID: settings.deviceID,
                        statusText: "传输中"
                    )
                ])
                let response = try await client.putLocalNetworkSyncArtifact(settings: settings, request: request)
                guard response.ok else {
                    throw SecureMacUploadError.serverRejected(response.error ?? "sync_artifact_put_failed")
                }
                try updateTransferJob(
                    direction: .upload,
                    artifactID: artifact.artifactID,
                    state: .verifying,
                    transferredBytes: Int64(data.count),
                    nextOffset: Int64(data.count)
                )
                diagnosticsStore.record(phase: "transferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID)
                diagnosticsStore.record(phase: "fileTransferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID)
                diagnosticsStore.record(phase: "checksumVerified", deviceID: settings.deviceID, syncRunID: syncRunID)
                diagnosticsStore.record(phase: "peerFileApplied", deviceID: settings.deviceID, syncRunID: syncRunID)
                try completeTransferJob(direction: .upload, artifactID: artifact.artifactID)
                try clearLocalTransferProgress(ownerID: artifact.ownerID)
                stateStore.recordActiveTransfers([])
                diagnosticsStore.record(phase: "transferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
                diagnosticsStore.record(phase: "fileTransferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
                diagnosticsStore.record(phase: "uploadActionCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
            } catch {
                try? failTransferJob(
                    direction: .upload,
                    artifactID: artifact.artifactID,
                    errorCode: "sync_artifact_put_failed",
                    errorMessage: error.localizedDescription
                )
                try? saveLocalTransferProgress(
                    ownerID: artifact.ownerID,
                    objectKind: artifact.kind.rawValue,
                    sourceDeviceID: settings.deviceID,
                    state: .failed,
                    progressFraction: nil,
                    receivedBytes: 0,
                    totalBytes: Int64(data.count),
                    statusText: "传输失败，可重试"
                )
                diagnosticsStore.record(phase: "uploadActionFailed", deviceID: settings.deviceID, syncRunID: syncRunID, errorCode: "sync_artifact_put_failed", errorMessage: error.localizedDescription)
                throw error
            }
        }
    }

    private func uploadLargeLocalArtifact(
        _ artifact: LocalNetworkSyncArtifactEntry,
        fileURL: URL,
        fileSize: Int64,
        settings: SecureMacConnectionSnapshot,
        syncRunID: String
    ) async throws {
        let checksum = try await canonicalFileChecksum(
            fileURL: fileURL,
            logicalToken: artifact.logicalPathToken
        )
        if let expectedChecksum = artifact.checksum,
           expectedChecksum != checksum {
            throw SecureMacUploadError.serverRejected("sync_artifact_checksum_mismatch")
        }

        diagnosticsStore.record(phase: "uploadActionStarted", deviceID: settings.deviceID, syncRunID: syncRunID)
        do {
            try beginTransferJob(
                direction: .upload,
                ownerID: artifact.ownerID,
                artifactID: artifact.artifactID,
                objectKind: artifact.kind.rawValue,
                logicalName: artifact.logicalPathToken,
                totalBytes: fileSize,
                transferredBytes: 0,
                sha256: checksum,
                peerDeviceID: settings.deviceID,
                deviceID: settings.deviceID,
                syncRunID: syncRunID
            )
            try saveLocalTransferProgress(
                ownerID: artifact.ownerID,
                objectKind: artifact.kind.rawValue,
                sourceDeviceID: settings.deviceID,
                state: .transferring,
                progressFraction: 0,
                receivedBytes: 0,
                totalBytes: fileSize,
                statusText: "传输中"
            )
            stateStore.recordActiveTransfers([
                LocalNetworkTransferProgress(
                    objectID: artifact.ownerID,
                    objectKind: artifact.kind.rawValue,
                    state: .transferring,
                    progressFraction: 0,
                    receivedBytes: 0,
                    totalBytes: fileSize,
                    sourceDeviceID: settings.deviceID,
                    statusText: "传输中"
                )
            ])

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer {
                try? handle.close()
            }
            let statusResponse = try await client.fetchLocalNetworkSyncArtifactStatus(
                settings: settings,
                request: LocalNetworkSyncArtifactStatusRequest(
                    artifactID: artifact.artifactID,
                    kind: artifact.kind,
                    ownerID: artifact.ownerID,
                    logicalPathToken: artifact.logicalPathToken,
                    checksum: checksum,
                    size: fileSize,
                    syncRunID: syncRunID
                )
            )
            guard statusResponse.ok else {
                throw SecureMacUploadError.serverRejected(statusResponse.error ?? "sync_artifact_status_failed")
            }
            diagnosticsStore.record(phase: "transferSessionStatusFetched", deviceID: settings.deviceID, syncRunID: syncRunID)

            var offset = statusResponse.nextOffset ?? statusResponse.confirmedBytes ?? 0
            if statusResponse.state == .complete,
               statusResponse.confirmedBytes == fileSize,
               statusResponse.checksum == nil || statusResponse.checksum == checksum {
                try updateTransferJob(
                    direction: .upload,
                    artifactID: artifact.artifactID,
                    state: .verifying,
                    transferredBytes: fileSize,
                    nextOffset: fileSize
                )
                diagnosticsStore.record(phase: "checksumVerified", deviceID: settings.deviceID, syncRunID: syncRunID)
                diagnosticsStore.record(phase: "peerFileApplied", deviceID: settings.deviceID, syncRunID: syncRunID)
                try completeTransferJob(direction: .upload, artifactID: artifact.artifactID)
                try clearLocalTransferProgress(ownerID: artifact.ownerID)
                stateStore.recordActiveTransfers([])
                diagnosticsStore.record(phase: "transferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
                diagnosticsStore.record(phase: "fileTransferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "alreadyComplete")
                diagnosticsStore.record(phase: "uploadActionCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
                return
            }
            guard offset >= 0, offset <= fileSize else {
                diagnosticsStore.record(
                    phase: "transferOffsetMismatch",
                    deviceID: settings.deviceID,
                    syncRunID: syncRunID,
                    errorCode: "peer_offset_out_of_range",
                    errorMessage: "offset=\(offset),size=\(fileSize)"
                )
                throw SecureMacUploadError.serverRejected("sync_artifact_offset_mismatch")
            }
            if offset > 0 {
                try updateTransferJob(
                    direction: .upload,
                    artifactID: artifact.artifactID,
                    state: .resuming,
                    transferredBytes: offset,
                    nextOffset: offset
                )
                try handle.seek(toOffset: UInt64(offset))
                let fraction = fileSize > 0 ? Double(offset) / Double(fileSize) : 1
                try saveLocalTransferProgress(
                    ownerID: artifact.ownerID,
                    objectKind: artifact.kind.rawValue,
                    sourceDeviceID: settings.deviceID,
                    state: .resuming,
                    progressFraction: min(max(fraction, 0), 1),
                    receivedBytes: offset,
                    totalBytes: fileSize,
                    statusText: "续传中"
                )
                diagnosticsStore.record(phase: "transferResumeAttempted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "offset=\(offset)")
                diagnosticsStore.record(phase: "transferResumed", deviceID: settings.deviceID, syncRunID: syncRunID, result: "offset=\(offset)")
            }
            var chunkIndex = 0
            while offset < fileSize {
                let data = try handle.read(upToCount: min(Self.artifactChunkBytes, Int(fileSize - offset))) ?? Data()
                guard !data.isEmpty else {
                    break
                }
                let nextOffset = offset + Int64(data.count)
                let request = LocalNetworkSyncArtifactPutRequest(
                    artifactID: artifact.artifactID,
                    kind: artifact.kind,
                    ownerID: artifact.ownerID,
                    checksum: checksum,
                    size: fileSize,
                    updatedAt: artifact.updatedAt,
                    logicalPathToken: artifact.logicalPathToken,
                    dataBase64: data.base64EncodedString(),
                    offset: offset,
                    chunkSize: data.count,
                    totalSize: fileSize,
                    isFinalChunk: nextOffset >= fileSize,
                    syncRunID: syncRunID
                )
                let response = try await client.putLocalNetworkSyncArtifact(settings: settings, request: request)
                guard response.ok else {
                    throw SecureMacUploadError.serverRejected(response.error ?? "sync_artifact_put_failed")
                }
                offset = response.confirmedBytes ?? nextOffset
                let fraction = fileSize > 0 ? Double(offset) / Double(fileSize) : 1
                try updateTransferJob(
                    direction: .upload,
                    artifactID: artifact.artifactID,
                    state: .transferring,
                    transferredBytes: offset,
                    nextOffset: offset
                )
                try saveLocalTransferProgress(
                    ownerID: artifact.ownerID,
                    objectKind: artifact.kind.rawValue,
                    sourceDeviceID: settings.deviceID,
                    state: .transferring,
                    progressFraction: min(max(fraction, 0), 1),
                    receivedBytes: offset,
                    totalBytes: fileSize,
                    statusText: "\(Int((fraction * 100).rounded()))%"
                )
                diagnosticsStore.record(phase: "transferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID)
                diagnosticsStore.record(phase: "fileTransferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID)
                chunkIndex += 1
            }

            guard offset == fileSize else {
                throw SecureMacUploadError.serverRejected("sync_artifact_incomplete")
            }
            try updateTransferJob(
                direction: .upload,
                artifactID: artifact.artifactID,
                state: .verifying,
                transferredBytes: fileSize,
                nextOffset: fileSize
            )
            diagnosticsStore.record(phase: "checksumVerified", deviceID: settings.deviceID, syncRunID: syncRunID)
            diagnosticsStore.record(phase: "peerFileApplied", deviceID: settings.deviceID, syncRunID: syncRunID)
            try completeTransferJob(direction: .upload, artifactID: artifact.artifactID)
            try clearLocalTransferProgress(ownerID: artifact.ownerID)
            stateStore.recordActiveTransfers([])
            diagnosticsStore.record(phase: "transferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
            diagnosticsStore.record(phase: "fileTransferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "chunks=\(chunkIndex)")
            diagnosticsStore.record(phase: "uploadActionCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
        } catch {
            try? pauseTransferJob(
                direction: .upload,
                artifactID: artifact.artifactID,
                state: .retryPending,
                errorCode: "sync_artifact_put_failed",
                errorMessage: error.localizedDescription
            )
            try? saveLocalTransferProgress(
                ownerID: artifact.ownerID,
                objectKind: artifact.kind.rawValue,
                sourceDeviceID: settings.deviceID,
                state: .retryPending,
                progressFraction: nil,
                receivedBytes: 0,
                totalBytes: fileSize,
                statusText: "传输失败，可重试"
            )
            diagnosticsStore.record(phase: "transferPausedDisconnected", deviceID: settings.deviceID, syncRunID: syncRunID, errorCode: "sync_artifact_put_failed", errorMessage: error.localizedDescription)
            diagnosticsStore.record(phase: "uploadActionFailed", deviceID: settings.deviceID, syncRunID: syncRunID, errorCode: "sync_artifact_put_failed", errorMessage: error.localizedDescription)
            throw error
        }
    }

    func uploadRecordingAudioActionsToRun(
        _ actions: [LocalNetworkSyncDiffAction],
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        settings: SecureMacConnectionSnapshot,
        syncRunID: String,
        triggerSource: RecordingAudioSyncTriggerSource = .periodicSync
    ) -> [LocalNetworkSyncDiffAction] {
        let transferJobs = (try? transferJobStore.loadJobs()) ?? []
        let uploadJobsByRecordingID = ((try? uploadJobStore.loadJobs()) ?? []).reduce(into: [String: RecordingUploadJob]()) { result, job in
            result[job.recordingID] = job
        }
        var seenKeys = Set<String>()
        var allowedActions: [LocalNetworkSyncDiffAction] = []

        for action in actions {
            let artifactID = audioTransferArtifactID(recordingID: action.entityID)
            let transferID = transferID(direction: .upload, artifactID: artifactID)
            let dedupKey = "\(action.entityID)|\(artifactID)|upload|\(settings.deviceID)"
            let localAudio = localAudioDecisionState(recordingID: action.entityID, in: localInventory)
            let peerAudio = bridgedPeerAudioDecisionState(
                for: action,
                peerInventory: peerInventory,
                localAudioState: localAudio
            )
            let wasDuplicateInRun = !seenKeys.insert(dedupKey).inserted
            let transferState = wasDuplicateInRun
                ? RecordingTransferJobState.queued
                : transferJobState(transferID: transferID, transferJobs: transferJobs)
            let ledgerState = uploadLedgerState(uploadJobsByRecordingID[action.entityID])
            let decision = RecordingAudioUploadDecisionEvaluator.evaluateRecordingAudioUploadDecision(
                localAudioState: localAudio,
                peerAudioState: peerAudio,
                transferJobState: transferState,
                ledgerState: ledgerState,
                triggerSource: triggerSource,
                syncRunID: syncRunID,
                objectID: artifactID,
                recordingID: action.entityID
            )
            recordRecordingAudioDecisionDiagnostics(
                recordingID: action.entityID,
                objectID: artifactID,
                logicalPathToken: localInventory.recordings.first { $0.recordingID == action.entityID }?.audioLogicalPathToken,
                triggerSource: triggerSource,
                localAudioState: localAudio,
                peerAudioState: peerAudio,
                transferJobState: transferState,
                ledgerState: ledgerState,
                decision: decision,
                deviceID: settings.deviceID,
                syncRunID: syncRunID
            )
            diagnosticsStore.record(
                phase: "transferDedupKeyComputed",
                deviceID: settings.deviceID,
                syncRunID: syncRunID,
                result: "key=\(safePrefix(dedupKey)),object=\(safePrefix(artifactID)),direction=upload"
            )

            guard !wasDuplicateInRun else {
                diagnosticsStore.record(
                    phase: "transferDuplicateSuppressed",
                    deviceID: settings.deviceID,
                    syncRunID: syncRunID,
                    result: "recording=\(safePrefix(action.entityID))"
                )
                continue
            }

            guard decision.shouldCreateUploadJob else {
                continue
            }

            diagnosticsStore.record(
                phase: "syncUploadActionCreatedBecausePeerMissingAudio",
                deviceID: settings.deviceID,
                syncRunID: syncRunID,
                result: RecordingAudioUploadDecisionDiagnostics.result(
                    recordingID: action.entityID,
                    objectID: artifactID,
                    logicalPathToken: localInventory.recordings.first { $0.recordingID == action.entityID }?.audioLogicalPathToken,
                    triggerSource: triggerSource,
                    decision: decision,
                    localAudioState: localAudio,
                    peerAudioState: peerAudio,
                    transferJobState: transferState,
                    ledgerState: ledgerState
                )
            )
            var allowedAction = action
            allowedAction.reason = decision.reasonCode
            allowedActions.append(allowedAction)
        }

        return allowedActions
    }

    private func recordRecordingAudioDecisionDiagnostics(
        recordingID: String,
        objectID: String,
        logicalPathToken: String?,
        triggerSource: RecordingAudioSyncTriggerSource,
        localAudioState: RecordingLocalAudioState,
        peerAudioState: RecordingPeerAudioState,
        transferJobState: RecordingTransferJobState,
        ledgerState: RecordingUploadLedgerState,
        decision: RecordingAudioUploadDecision,
        deviceID: String,
        syncRunID: String
    ) {
        let result = RecordingAudioUploadDecisionDiagnostics.result(
            recordingID: recordingID,
            objectID: objectID,
            logicalPathToken: logicalPathToken,
            triggerSource: triggerSource,
            decision: decision,
            localAudioState: localAudioState,
            peerAudioState: peerAudioState,
            transferJobState: transferJobState,
            ledgerState: ledgerState
        )
        diagnosticsStore.record(phase: "localAudioStateResolved", deviceID: deviceID, syncRunID: syncRunID, result: result)
        diagnosticsStore.record(phase: "peerAudioStateResolved", deviceID: deviceID, syncRunID: syncRunID, result: result)
        diagnosticsStore.record(phase: "transferJobStateResolved", deviceID: deviceID, syncRunID: syncRunID, result: result)
        diagnosticsStore.record(phase: "ledgerStateResolved", deviceID: deviceID, syncRunID: syncRunID, result: result)
        diagnosticsStore.record(phase: "uploadStateEvaluated", deviceID: deviceID, syncRunID: syncRunID, result: result)
        diagnosticsStore.record(phase: "uploadDecisionComputed", deviceID: deviceID, syncRunID: syncRunID, result: result)
        diagnosticsStore.record(phase: decision.diagnosticStage, deviceID: deviceID, syncRunID: syncRunID, result: result)
        switch decision.reasonCode {
        case "peer_metadata_only":
            diagnosticsStore.record(phase: CanonicalSyncRuntimeDiagnosticKind.canonicalExistencePeerMetadataOnlyUploadCandidate.rawValue, deviceID: deviceID, syncRunID: syncRunID, result: result)
        case "peer_missing_audio":
            diagnosticsStore.record(phase: CanonicalSyncRuntimeDiagnosticKind.canonicalExistencePeerAbsentMetadataBridgeRequired.rawValue, deviceID: deviceID, syncRunID: syncRunID, result: result)
        case "peer_audio_unknown_deferred":
            diagnosticsStore.record(phase: CanonicalSyncRuntimeDiagnosticKind.canonicalExistencePeerUnknownDeferred.rawValue, deviceID: deviceID, syncRunID: syncRunID, result: result)
        case "peer_already_has_same_audio", "completed_ledger_peer_matches":
            diagnosticsStore.record(phase: CanonicalSyncRuntimeDiagnosticKind.canonicalExistenceAudioSameNoOp.rawValue, deviceID: deviceID, syncRunID: syncRunID, result: result)
        case "peer_audio_conflict":
            diagnosticsStore.record(phase: CanonicalSyncRuntimeDiagnosticKind.canonicalExistenceAudioConflict.rawValue, deviceID: deviceID, syncRunID: syncRunID, result: result)
        default:
            break
        }
        if decision.reasonCode == "peer_audio_unknown_deferred" {
            diagnosticsStore.record(phase: "peerAudioUnknownVerificationStarted", deviceID: deviceID, syncRunID: syncRunID, result: result)
            diagnosticsStore.record(phase: "peerAudioUnknownVerificationCompleted", deviceID: deviceID, syncRunID: syncRunID, result: "deferredUntilPeerTruth,\(result)")
            diagnosticsStore.record(phase: "peerAudioUnknownDeferred", deviceID: deviceID, syncRunID: syncRunID, result: result)
        }
        if decision.reasonCode == "manual_force_peer_unknown" {
            diagnosticsStore.record(phase: "manualForcePeerUnknownUpload", deviceID: deviceID, syncRunID: syncRunID, result: result)
        }
        if decision.reasonCode == "peer_audio_conflict" {
            diagnosticsStore.record(phase: "audioConflictDetected", deviceID: deviceID, syncRunID: syncRunID, result: result)
            diagnosticsStore.record(phase: "uploadSuppressedConflict", deviceID: deviceID, syncRunID: syncRunID, result: result)
        }
        if decision.reasonCode.contains("retry_pending") {
            diagnosticsStore.record(phase: "retryPendingDisplayState", deviceID: deviceID, syncRunID: syncRunID, result: result)
        }
        if decision.reasonCode == "peer_already_has_same_audio" || decision.reasonCode == "completed_ledger_peer_matches" {
            switch triggerSource {
            case .manualSyncMacHint:
                diagnosticsStore.record(phase: "macManualSyncNoOpBecausePeerMatches", deviceID: deviceID, syncRunID: syncRunID, result: result)
            case .manualSyncIPhone:
                diagnosticsStore.record(phase: "iphoneManualSyncNoOpBecausePeerMatches", deviceID: deviceID, syncRunID: syncRunID, result: result)
            default:
                break
            }
        }
    }

    private func localAudioDecisionState(
        recordingID: String,
        in inventory: LocalNetworkSyncInventory
    ) -> RecordingLocalAudioState {
        guard let recording = inventory.recordings.first(where: { $0.recordingID == recordingID }) else {
            return .missing
        }
        if recording.deleted || recording.tombstone == true {
            return .deleted
        }
        let state = recordingAudioState(recordingID: recordingID, in: inventory)
        guard state.isAvailable else {
            return .missing
        }
        return .available(RecordingAudioSignature(sha256: state.checksum, size: state.size))
    }

    private func peerAudioDecisionState(
        recordingID: String,
        in inventory: LocalNetworkSyncInventory,
        localAudioState: RecordingLocalAudioState
    ) -> RecordingPeerAudioState {
        let recording = inventory.recordings.first { $0.recordingID == recordingID }
        let object = inventory.objects.first { $0.objectID == audioTransferArtifactID(recordingID: recordingID) }
        if recording?.deleted == true || recording?.tombstone == true {
            return .deleted
        }
        let state = recordingAudioState(recordingID: recordingID, in: inventory)
        if state.isAvailable {
            let signature = RecordingAudioSignature(sha256: state.checksum, size: state.size)
            if let localSignature = localAudioState.signature, !localSignature.matches(signature) {
                return .different(signature)
            }
            return .available(signature)
        }
        if isCompletedReceiveStatus(recording?.receiveStatus) {
            return .unknown
        }
        if recording != nil {
            return .metadataOnly
        }
        if object != nil {
            return .missing
        }
        return .unknown
    }

    private func bridgedPeerAudioDecisionState(
        for action: LocalNetworkSyncDiffAction,
        peerInventory: LocalNetworkSyncInventory,
        localAudioState: RecordingLocalAudioState
    ) -> RecordingPeerAudioState {
        if let canonicalReason = CanonicalSyncPlanReason(rawValue: action.reason) {
            switch canonicalReason {
            case .peerObjectAbsent, .peerAudioMissing:
                return .missing
            case .peerAudioMetadataOnly, .peerStudyItemOnlyWithoutReceiveRecord:
                return .metadataOnly
            default:
                break
            }
        }
        return peerAudioDecisionState(recordingID: action.entityID, in: peerInventory, localAudioState: localAudioState)
    }

    private func transferJobState(
        transferID: String,
        transferJobs: [LocalNetworkSyncTransferJob]
    ) -> RecordingTransferJobState {
        guard let job = transferJobs.first(where: { $0.transferID == transferID }) else {
            return .none
        }
        switch job.state {
        case .pending:
            return .queued
        case .transferring, .resuming:
            return .inFlight
        case .verifying:
            return .finalizing
        case .complete:
            return .completed
        case .failed, .conflict:
            return .failed(reason: job.errorCode ?? job.errorMessage)
        case .retryPending:
            return .retryPending
        case .paused, .pausedDisconnected:
            return .paused
        }
    }

    private func uploadLedgerState(_ job: RecordingUploadJob?) -> RecordingUploadLedgerState {
        guard let job else {
            return .none
        }
        if job.overallState == .fatalFailed {
            return .fatalFailed(reason: job.lastErrorCode ?? job.lastErrorMessage)
        }
        if job.overallState == .retryableFailed {
            return .retryPending
        }
        if job.overallState == .succeeded || job.audioStage == .succeeded {
            return .completed(RecordingAudioSignature(sha256: job.audioTotalSHA256, size: job.audioTotalBytes))
        }
        if job.audioStage == .inProgress || job.overallState == .inProgress {
            if job.resumableState == .finalizing {
                return .finalizing
            }
            return .inFlight
        }
        return .none
    }

    private func recordingAudioState(
        recordingID: String,
        in inventory: LocalNetworkSyncInventory
    ) -> (isAvailable: Bool, checksum: String?, size: Int64?) {
        let recording = inventory.recordings.first { $0.recordingID == recordingID }
        let object = inventory.objects.first { $0.objectID == audioTransferArtifactID(recordingID: recordingID) }
        let checksum = recording?.audioChecksum ?? object?.sha256
        let size = recording?.audioSize ?? object?.size
        let availability = recording?.audioAvailability ?? object?.availability
        let isAvailable = (recording?.audioAvailable == true)
            || availability == .local
            || availability == .availableOnPeer
            || availability == .complete
        return (isAvailable, checksum, size)
    }

    private func isCompletedReceiveStatus(_ value: String?) -> Bool {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalized == "completed" || normalized == "complete"
    }

    private func audioSignaturesMatch(
        _ local: (isAvailable: Bool, checksum: String?, size: Int64?),
        _ peer: (isAvailable: Bool, checksum: String?, size: Int64?)
    ) -> Bool {
        guard let localChecksum = local.checksum?.trimmingCharacters(in: .whitespacesAndNewlines),
              !localChecksum.isEmpty,
              let peerChecksum = peer.checksum?.trimmingCharacters(in: .whitespacesAndNewlines),
              !peerChecksum.isEmpty,
              let localSize = local.size,
              let peerSize = peer.size else {
            return false
        }
        return localChecksum == peerChecksum && localSize == peerSize
    }

    private func isInFlightTransferState(_ state: LocalNetworkTransferState) -> Bool {
        switch state {
        case .pending, .transferring, .resuming, .verifying:
            return true
        case .paused, .pausedDisconnected, .retryPending, .complete, .failed, .conflict:
            return false
        }
    }

    private func safePrefix(_ value: String) -> String {
        String(value.prefix(12))
    }

    private func uploadMissingRecordingAudioIfNeeded(
        plan: LocalNetworkSyncDiffPlan,
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        settings: SecureMacConnectionSnapshot,
        syncRunID: String,
        triggerSource: RecordingAudioSyncTriggerSource
    ) async -> [LocalNetworkTransferProgress] {
        guard let recordingManager, let uploadCoordinator else {
            return []
        }
        var remainingTransfers: [LocalNetworkTransferProgress] = []
        recordingManager.reloadRecordings()
        let actions = uploadRecordingAudioActionsToRun(
            plan.uploadRecordingAudioActions,
            localInventory: localInventory,
            peerInventory: peerInventory,
            settings: settings,
            syncRunID: syncRunID,
            triggerSource: triggerSource
        )
        for action in actions {
            guard let metadata = recordingManager.recordings.first(where: { $0.id == action.entityID }) else {
                let traceID = UploadFlightRecorder.makeTraceID()
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "syncSkippedAudioUploadWithReason",
                    traceID: traceID,
                    recordingID: action.entityID,
                    eventResult: "skip",
                    reasonCode: "recording_missing"
                )
                diagnosticsStore.record(
                    phase: "existingUploadActionSkipped",
                    deviceID: settings.deviceID,
                    syncRunID: syncRunID,
                    result: "recordingID=\(action.entityID)",
                    errorCode: "recording_missing"
                )
                continue
            }
            let traceID = UploadFlightRecorder.makeTraceID()
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "syncInventoryRecordingSeen",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus,
                fileSize: metadata.fileSize,
                resolvedRelativePathToken: metadata.relativeAudioPath
            )
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "syncPeerMissingAudioDetected",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                reasonCode: action.reason,
                uploadStatus: metadata.uploadStatus
            )
            if RecordingUploadStatus(rawMetadataValue: metadata.uploadStatus) == .uploaded {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "syncMetadataOnlyStateDetected",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "success",
                    reasonCode: "local_uploaded_peer_missing_audio",
                    uploadStatus: metadata.uploadStatus
                )
            }
            let audioChecksum = localInventory.recordings.first { $0.recordingID == metadata.id }?.audioChecksum
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "syncExistingUploadActionCreated",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus
            )
            diagnosticsStore.record(
                phase: "existingUploadActionQueued",
                deviceID: settings.deviceID,
                syncRunID: syncRunID,
                result: "recordingID=\(metadata.id),objectID=\(audioTransferArtifactID(recordingID: metadata.id))"
            )
            diagnosticsStore.record(phase: "existingUploadActionStarted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id),objectID=\(audioTransferArtifactID(recordingID: metadata.id))")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "syncExistingUploadActionQueued",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "success",
                uploadStatus: metadata.uploadStatus
            )
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "syncExistingUploadActionStarted",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus
            )
            diagnosticsStore.record(phase: "uploadActionStarted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id),objectID=\(audioTransferArtifactID(recordingID: metadata.id))")
            let initialProgress = audioTransferProgress(
                metadata: metadata,
                state: .transferring,
                sourceDeviceID: settings.deviceID,
                statusText: metadata.uploadProgressDescription ?? "传输中"
            )
            try? saveLocalTransferProgress(initialProgress)
            try? beginTransferJob(
                direction: .upload,
                ownerID: metadata.id,
                artifactID: audioTransferArtifactID(recordingID: metadata.id),
                objectKind: LocalNetworkSyncObjectKind.recordingAudio.rawValue,
                logicalName: metadata.fileName,
                totalBytes: metadata.uploadProgressTotalBytes ?? (metadata.fileSize > 0 ? metadata.fileSize : nil),
                transferredBytes: metadata.uploadProgressConfirmedBytes ?? 0,
                sha256: audioChecksum,
                peerDeviceID: settings.deviceID,
                deviceID: settings.deviceID,
                syncRunID: syncRunID
            )
            stateStore.recordActiveTransfers([initialProgress])
            diagnosticsStore.record(phase: "uploadJobCreated", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)")
            diagnosticsStore.record(phase: "recordingUploadCoordinatorCalled", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "syncRecordingUploadCoordinatorCalled",
                traceID: traceID,
                recordingID: metadata.id,
                eventResult: "begin",
                uploadStatus: metadata.uploadStatus
            )
            diagnosticsStore.record(phase: "uploadStarted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)")
            let progressTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard let self else {
                        return
                    }
                    try? self.refreshRecordingAudioTransferProgress(recordingID: metadata.id, settings: settings, syncRunID: syncRunID)
                }
            }
            let uploadLocalAudioState = localAudioDecisionState(recordingID: metadata.id, in: localInventory)
            let uploadPeerAudioState = bridgedPeerAudioDecisionState(
                for: action,
                peerInventory: peerInventory,
                localAudioState: uploadLocalAudioState
            )
            let status = await uploadCoordinator.uploadAndWait(
                metadata: metadata,
                settings: settings,
                recordingManager: recordingManager,
                traceID: traceID,
                triggerSource: triggerSource,
                peerAudioState: uploadPeerAudioState,
                transferJobState: .none,
                syncRunID: syncRunID
            )
            progressTask.cancel()
            switch status {
            case .uploaded:
                let verifiedProgress = audioTransferProgress(
                    metadata: (try? audioFileStore.loadMetadata(id: metadata.id)) ?? metadata,
                    state: .verifying,
                    sourceDeviceID: settings.deviceID,
                    statusText: "校验中"
                )
                try? saveLocalTransferProgress(verifiedProgress)
                try? completeTransferJob(direction: .upload, artifactID: audioTransferArtifactID(recordingID: metadata.id))
                try? clearLocalTransferProgress(ownerID: metadata.id)
                stateStore.recordActiveTransfers([])
                diagnosticsStore.record(phase: "checksumVerified", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)")
                diagnosticsStore.record(phase: "peerFileApplied", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)")
                diagnosticsStore.record(phase: "transferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)")
                diagnosticsStore.record(phase: "fileTransferCompleted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)")
                diagnosticsStore.record(phase: "uploadActionCompleted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)")
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "syncDidNotMarkAudioAvailableWithoutFile",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "success",
                    reasonCode: "completed_after_main_upload",
                    uploadStatus: RecordingUploadStatus.uploaded.rawValue
                )
            case .failed:
                let latestMetadata = (try? audioFileStore.loadMetadata(id: metadata.id)) ?? metadata
                let failedProgress = audioTransferProgress(
                    metadata: latestMetadata,
                    state: .failed,
                    sourceDeviceID: settings.deviceID,
                    statusText: "传输失败，可重试"
                )
                try? saveLocalTransferProgress(failedProgress)
                try? updateTransferJob(
                    direction: .upload,
                    artifactID: audioTransferArtifactID(recordingID: metadata.id),
                    state: .failed,
                    transferredBytes: failedProgress.receivedBytes ?? 0,
                    nextOffset: failedProgress.receivedBytes ?? 0
                )
                try? failTransferJob(
                    direction: .upload,
                    artifactID: audioTransferArtifactID(recordingID: metadata.id),
                    errorCode: "recording_audio_upload_failed",
                    errorMessage: uploadCoordinator.errorMessage(for: latestMetadata) ?? "recording_audio_upload_failed"
                )
                stateStore.recordActiveTransfers([failedProgress])
                remainingTransfers.append(failedProgress)
                diagnosticsStore.record(phase: "uploadActionFailed", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)", errorCode: "recording_audio_upload_failed")
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "syncSkippedAudioUploadWithReason",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "fail",
                    reasonCode: "recording_audio_upload_failed",
                    uploadStatus: latestMetadata.uploadStatus,
                    safeErrorMessage: uploadCoordinator.errorMessage(for: latestMetadata)
                )
            case .localOnly, .uploading:
                let latestMetadata = (try? audioFileStore.loadMetadata(id: metadata.id)) ?? metadata
                let pendingProgress = audioTransferProgress(
                    metadata: latestMetadata,
                    state: .paused,
                    sourceDeviceID: settings.deviceID,
                    statusText: latestMetadata.uploadProgressDescription ?? "等待重试"
                )
                remainingTransfers.append(pendingProgress)
                diagnosticsStore.record(phase: "uploadActionStarted", deviceID: settings.deviceID, syncRunID: syncRunID, result: "recordingID=\(metadata.id)")
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "syncSkippedAudioUploadWithReason",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "skip",
                    reasonCode: "coordinator_returned_\(status.rawValue)",
                    uploadStatus: latestMetadata.uploadStatus
                )
            }
        }
        return remainingTransfers
    }

    private func audioTransferProgress(
        metadata: RecordingMetadata,
        state: LocalNetworkTransferState,
        sourceDeviceID: String,
        statusText: String?
    ) -> LocalNetworkTransferProgress {
        let totalBytes = metadata.uploadProgressTotalBytes ?? (metadata.fileSize > 0 ? metadata.fileSize : nil)
        let confirmedBytes = metadata.uploadProgressConfirmedBytes ?? (state == .complete ? totalBytes : 0)
        let fraction: Double?
        if state == .verifying || state == .complete {
            fraction = 1
        } else if let storedFraction = metadata.uploadProgressFraction {
            fraction = storedFraction
        } else if let confirmedBytes, let totalBytes, totalBytes > 0 {
            fraction = Double(confirmedBytes) / Double(totalBytes)
        } else {
            fraction = state == .pending ? 0 : nil
        }

        return LocalNetworkTransferProgress(
            objectID: metadata.id,
            objectKind: LocalNetworkSyncObjectKind.recordingAudio.rawValue,
            state: state,
            progressFraction: fraction.map { min(max($0, 0), 1) },
            receivedBytes: confirmedBytes,
            totalBytes: totalBytes,
            sourceDeviceID: sourceDeviceID,
            statusText: statusText
        )
    }

    private func refreshRecordingAudioTransferProgress(
        recordingID: String,
        settings: SecureMacConnectionSnapshot,
        syncRunID: String
    ) throws {
        let existingTransferID = transferID(direction: .upload, artifactID: audioTransferArtifactID(recordingID: recordingID))
        let previousJob = try? transferJobStore.loadJobs().first { $0.transferID == existingTransferID }
        let metadata = try audioFileStore.loadMetadata(id: recordingID)
        let speedBytesPerSecond = previousJob.flatMap { previous -> Double? in
            guard let receivedBytes = metadata.uploadProgressConfirmedBytes,
                  receivedBytes > previous.transferredBytes else {
                return nil
            }
            let elapsed = Date().timeIntervalSince(previous.updatedAt)
            guard elapsed > 0 else {
                return nil
            }
            return Double(receivedBytes - previous.transferredBytes) / elapsed
        }
        let progress = audioTransferProgress(
            metadata: metadata,
            state: .transferring,
            sourceDeviceID: settings.deviceID,
            statusText: audioTransferStatusText(metadata: metadata, speedBytesPerSecond: speedBytesPerSecond)
        )
        try saveLocalTransferProgress(progress)
        try? updateTransferJob(
            direction: .upload,
            artifactID: audioTransferArtifactID(recordingID: recordingID),
            state: .transferring,
            transferredBytes: progress.receivedBytes ?? 0,
            nextOffset: progress.receivedBytes ?? 0
        )
        stateStore.recordActiveTransfers([progress])
        diagnosticsStore.record(
            phase: "uploadProgressUpdated",
            deviceID: settings.deviceID,
            syncRunID: syncRunID,
            result: progress.statusText,
            pendingUploadCount: 1
        )
        diagnosticsStore.record(phase: "transferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID, result: progress.statusText)
        diagnosticsStore.record(phase: "fileTransferProgressUpdated", deviceID: settings.deviceID, syncRunID: syncRunID, result: progress.statusText)
    }

    private func audioTransferStatusText(metadata: RecordingMetadata, speedBytesPerSecond: Double?) -> String {
        let totalBytes = metadata.uploadProgressTotalBytes ?? (metadata.fileSize > 0 ? metadata.fileSize : nil)
        let confirmedBytes = metadata.uploadProgressConfirmedBytes ?? 0
        guard let totalBytes, totalBytes > 0 else {
            return metadata.uploadProgressDescription ?? "传输中"
        }

        let percent = min(max(Int((Double(confirmedBytes) / Double(totalBytes) * 100).rounded()), 0), 100)
        guard let speedBytesPerSecond, speedBytesPerSecond > 0 else {
            return metadata.uploadProgressDescription ?? "\(percent)%"
        }
        return "\(percent)% \(Self.byteRateText(speedBytesPerSecond))"
    }

    private static func byteRateText(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1fMB/s", bytesPerSecond / 1_048_576)
        }
        if bytesPerSecond >= 1_024 {
            return String(format: "%.1fKB/s", bytesPerSecond / 1_024)
        }
        return "\(Int(bytesPerSecond.rounded()))B/s"
    }

    private func saveLocalTransferProgress(
        ownerID: String,
        objectKind: String,
        sourceDeviceID: String?,
        state: LocalNetworkTransferState,
        progressFraction: Double?,
        receivedBytes: Int64?,
        totalBytes: Int64?,
        statusText: String?
    ) throws {
        try saveLocalTransferProgress(
            LocalNetworkTransferProgress(
                objectID: ownerID,
                objectKind: objectKind,
                state: state,
                progressFraction: progressFraction,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                sourceDeviceID: sourceDeviceID,
                statusText: statusText
            )
        )
    }

    private func saveLocalTransferProgress(_ progress: LocalNetworkTransferProgress) throws {
        let item: StudyItemMetadata
        if let existing = localStudyItem(ownerID: progress.objectID) {
            item = existing
        } else if let metadata = try? audioFileStore.loadMetadata(id: progress.objectID) {
            item = try studyLibraryStore.upsertRecordingMetadata(metadata)
        } else {
            return
        }
        try studyLibraryStore.save(item.withLocalNetworkTransferProgress(progress))
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
    }

    private func clearLocalTransferProgress(ownerID: String) throws {
        guard let item = localStudyItem(ownerID: ownerID) else {
            return
        }
        try studyLibraryStore.save(item.withLocalNetworkTransferProgress(nil))
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
    }

    private func localStudyItem(ownerID: String) -> StudyItemMetadata? {
        studyLibraryStore.item(recordingID: ownerID) ?? studyLibraryStore.item(itemID: ownerID)
    }

    private func recordTransferJob(
        direction: LocalNetworkSyncTransferDirection,
        ownerID: String,
        artifactID: String,
        objectKind: String,
        logicalName: String?,
        totalBytes: Int64?,
        transferredBytes: Int64,
        sha256: String?,
        state: LocalNetworkTransferState,
        peerDeviceID: String?,
        syncRunID: String?
    ) throws {
        let now = Date()
        let transferID = transferID(direction: direction, artifactID: artifactID)
        let existing = (try? transferJobStore.loadJobs().first { $0.transferID == transferID })
        let job = LocalNetworkSyncTransferJob(
            transferID: transferID,
            direction: direction,
            ownerID: ownerID,
            artifactID: artifactID,
            objectKind: objectKind,
            fileName: logicalName?.split(separator: "/").last.map(String.init),
            logicalName: logicalName,
            totalBytes: totalBytes,
            transferredBytes: transferredBytes,
            sha256: sha256,
            chunkSize: nil,
            nextOffset: transferredBytes,
            state: state,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
            lastAttemptAt: now,
            nextRetryAfter: nil,
            errorCode: nil,
            errorMessage: nil,
            peerDeviceID: peerDeviceID,
            localTempPath: existing?.localTempPath,
            syncRunID: syncRunID,
            objectID: existing?.objectID ?? artifactID,
            logicalPathToken: logicalName,
            relativePathToken: logicalName,
            senderDeviceID: direction == .upload ? stateStore.state.localDeviceID : peerDeviceID,
            receiverDeviceID: direction == .upload ? peerDeviceID : stateStore.state.localDeviceID,
            confirmedBytes: transferredBytes,
            retryCount: existing?.retryCount ?? 0,
            sessionID: existing?.sessionID ?? UUID().uuidString
        )
        try transferJobStore.upsert(job)
    }

    private func beginTransferJob(
        direction: LocalNetworkSyncTransferDirection,
        ownerID: String,
        artifactID: String,
        objectKind: String,
        logicalName: String?,
        totalBytes: Int64?,
        transferredBytes: Int64,
        sha256: String?,
        peerDeviceID: String?,
        deviceID: String,
        syncRunID: String
    ) throws {
        diagnosticsStore.record(phase: "transferJobCreated", deviceID: deviceID, syncRunID: syncRunID, result: "artifactID=\(artifactID),direction=\(direction.rawValue)")
        diagnosticsStore.record(phase: "transferSessionCreated", deviceID: deviceID, syncRunID: syncRunID, result: "artifactID=\(artifactID),direction=\(direction.rawValue)")
        try recordTransferJob(
            direction: direction,
            ownerID: ownerID,
            artifactID: artifactID,
            objectKind: objectKind,
            logicalName: logicalName,
            totalBytes: totalBytes,
            transferredBytes: transferredBytes,
            sha256: sha256,
            state: .transferring,
            peerDeviceID: peerDeviceID,
            syncRunID: syncRunID
        )
        diagnosticsStore.record(phase: "transferJobQueued", deviceID: deviceID, syncRunID: syncRunID, result: "artifactID=\(artifactID),direction=\(direction.rawValue)")
        diagnosticsStore.record(phase: "transferJobStarted", deviceID: deviceID, syncRunID: syncRunID, result: "artifactID=\(artifactID),direction=\(direction.rawValue)")
        diagnosticsStore.record(phase: "transferStarted", deviceID: deviceID, syncRunID: syncRunID)
        diagnosticsStore.record(phase: "fileTransferStarted", deviceID: deviceID, syncRunID: syncRunID, result: "artifactID=\(artifactID),direction=\(direction.rawValue)")
    }

    private func updateTransferJob(
        direction: LocalNetworkSyncTransferDirection,
        artifactID: String,
        state: LocalNetworkTransferState,
        transferredBytes: Int64,
        nextOffset: Int64
    ) throws {
        try transferJobStore.update(transferID: transferID(direction: direction, artifactID: artifactID)) { job in
            job.state = state
            job.transferredBytes = transferredBytes
            job.nextOffset = nextOffset
            job.confirmedBytes = transferredBytes
            job.errorCode = nil
            job.errorMessage = nil
            if let totalBytes = job.totalBytes, transferredBytes > totalBytes {
                job.transferredBytes = totalBytes
                job.nextOffset = totalBytes
            }
        }
    }

    private func completeTransferJob(direction: LocalNetworkSyncTransferDirection, artifactID: String) throws {
        try transferJobStore.markComplete(transferID: transferID(direction: direction, artifactID: artifactID))
    }

    private func failTransferJob(
        direction: LocalNetworkSyncTransferDirection,
        artifactID: String,
        errorCode: String,
        errorMessage: String
    ) throws {
        try transferJobStore.update(transferID: transferID(direction: direction, artifactID: artifactID)) { job in
            job.state = errorCode.contains("conflict") ? .conflict : .failed
            job.lastAttemptAt = Date()
            job.nextRetryAfter = Date().addingTimeInterval(30)
            job.errorCode = errorCode
            job.errorMessage = errorMessage
        }
    }

    private func pauseTransferJob(
        direction: LocalNetworkSyncTransferDirection,
        artifactID: String,
        state: LocalNetworkTransferState,
        errorCode: String,
        errorMessage: String
    ) throws {
        try transferJobStore.update(transferID: transferID(direction: direction, artifactID: artifactID)) { job in
            job.state = state
            job.lastAttemptAt = Date()
            job.nextRetryAfter = Date().addingTimeInterval(30)
            job.retryCount = (job.retryCount ?? 0) + 1
            job.errorCode = errorCode
            job.errorMessage = errorMessage
        }
    }

    private func transferID(direction: LocalNetworkSyncTransferDirection, artifactID: String) -> String {
        "\(direction.rawValue):\(artifactID)"
    }

    private func audioTransferArtifactID(recordingID: String) -> String {
        "recordingAudio:\(recordingID)"
    }

    private func writeArtifactResponse(
        _ response: LocalNetworkSyncArtifactResponse,
        expectedArtifact: LocalNetworkSyncArtifactEntry,
        deviceID: String
    ) throws {
        guard response.ok,
              let kind = response.kind,
              kind.isAutoDownloadAllowed,
              let logicalPathToken = response.logicalPathToken,
              let base64 = response.dataBase64,
              let data = Data(base64Encoded: base64) else {
            throw SecureMacUploadError.serverRejected(response.error ?? "sync_artifact_missing")
        }
        if let checksum = response.checksum,
           checksum != SecureUploadUtilities.sha256Hex(data) {
            throw SecureMacUploadError.serverRejected("sync_artifact_checksum_mismatch")
        }
        if let size = response.size,
           size != Int64(data.count) {
            throw SecureMacUploadError.serverRejected("sync_artifact_size_mismatch")
        }
        if let expectedChecksum = expectedArtifact.checksum,
           expectedChecksum != SecureUploadUtilities.sha256Hex(data) {
            throw SecureMacUploadError.serverRejected("sync_artifact_checksum_mismatch")
        }
        diagnosticsStore.record(phase: "artifactChecksumVerified", deviceID: deviceID)
        diagnosticsStore.record(phase: "checksumVerified", deviceID: deviceID)
        diagnosticsStore.record(phase: "transferVerified", deviceID: deviceID)

        let rootURL = try audioFileStore.baseDirectory()
        let destinationURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: logicalPathToken, kind: kind)
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tempURL = try localIncomingTempURL(for: response.artifactID ?? expectedArtifact.artifactID)
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        try data.write(to: tempURL, options: .atomic)
        try atomicReplace(tempURL: tempURL, destinationURL: destinationURL)
        diagnosticsStore.record(phase: "atomicReplaceCompleted", deviceID: deviceID)
        diagnosticsStore.record(phase: "peerFileApplied", deviceID: deviceID)
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
        LocalNetworkSyncEventTrigger.post(
            .generatedArtifactAvailabilityChanged,
            source: "LocalNetworkSyncEngine.applyDownloadedArtifact"
        )
    }

    private func verifyAndApplyDownloadedArtifact(
        tempURL: URL,
        artifact: LocalNetworkSyncArtifactEntry,
        deviceID: String
    ) async throws {
        if let expectedSize = artifact.size,
           LocalNetworkSyncArtifactFileService.metadata(for: tempURL)?.size != expectedSize {
            throw SecureMacUploadError.serverRejected("sync_artifact_size_mismatch")
        }
        if let expectedChecksum = artifact.checksum,
           try await canonicalFileChecksum(
                fileURL: tempURL,
                logicalToken: "Sync/Incoming/\(artifact.artifactID).part",
                persistentCacheEnabled: false
           ) != expectedChecksum {
            throw SecureMacUploadError.serverRejected("sync_artifact_checksum_mismatch")
        }
        diagnosticsStore.record(phase: "artifactChecksumVerified", deviceID: deviceID)
        diagnosticsStore.record(phase: "checksumVerified", deviceID: deviceID)
        let rootURL = try audioFileStore.baseDirectory()
        let destinationURL = try LocalNetworkSyncArtifactFileService.safeFileURL(
            rootURL: rootURL,
            logicalPathToken: artifact.logicalPathToken,
            kind: artifact.kind
        )
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try atomicReplace(tempURL: tempURL, destinationURL: destinationURL)
        diagnosticsStore.record(phase: "atomicReplaceCompleted", deviceID: deviceID)
        diagnosticsStore.record(phase: "peerFileApplied", deviceID: deviceID)
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
    }

    private func canonicalFileChecksum(
        fileURL: URL,
        logicalToken: String?,
        persistentCacheEnabled: Bool = true
    ) async throws -> String {
        let cacheDirectoryURL = try audioFileStore.baseDirectory()
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
            .standardizedFileURL
        var configuration = canonicalChecksumRuntimeConfiguration
        configuration.persistentChecksumCacheEnabled = persistentCacheEnabled
        let result = await canonicalChecksumRuntime.checksum(
            fileURL: fileURL,
            logicalToken: logicalToken,
            nodeRole: .iPhone,
            cacheDirectoryURL: cacheDirectoryURL,
            configuration: configuration
        )
        guard let checksum = result.sha256 else {
            throw SecureMacUploadError.serverRejected(result.failure?.rawValue ?? "sync_artifact_checksum_unavailable")
        }
        return checksum
    }

    private func localIncomingTempURL(for artifactID: String) throws -> URL {
        let rootURL = try audioFileStore.baseDirectory()
        let tempDirectory = rootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("Incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        return tempDirectory.appendingPathComponent("\(artifactID.safeSyncFileComponent).tmp", isDirectory: false)
    }

    private func atomicReplace(tempURL: URL, destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        }
    }
}

@MainActor
enum LocalNetworkSyncInterval {
    static let defaultInterval: TimeInterval = 60
    static let allowedIntervals: Set<TimeInterval> = [10, 30, 60]

    static func normalized(_ interval: TimeInterval) -> TimeInterval {
        allowedIntervals.contains(interval) ? interval : defaultInterval
    }
}

@MainActor
enum LocalNetworkSyncStartGate {
    static func canRun(
        isActive: Bool,
        snapshot: SecureMacConnectionSnapshot,
        status: DeviceConnectionStatus?,
        userConnectionIntent: UserConnectionIntent = .wantsConnected
    ) -> Bool {
        guard isActive, snapshot.isPaired, userConnectionIntent == .wantsConnected else {
            return false
        }
        guard status?.presenceState != .disconnected,
              status?.presenceState != .securityError else {
            return false
        }
        return status?.presenceSnapshot().isOnline == true
    }
}

@MainActor
final class LocalNetworkSyncScheduler {
    typealias TickHandler = @MainActor (String, String?) async -> Void
    typealias InFlightHandler = @MainActor (String) -> Void

    private let interval: TimeInterval
    private let tickHandler: TickHandler
    private let inFlightHandler: InFlightHandler?
    private var periodicTask: Task<Void, Never>?
    private var pendingRequestAfterCurrentRun: (trigger: String, syncRunID: String?)?
    private(set) var isTickInFlight = false
    var configuredInterval: TimeInterval { interval }
    var isRunning: Bool { periodicTask != nil }
    var hasPendingRequestAfterCurrentRun: Bool { pendingRequestAfterCurrentRun != nil }

    init(
        interval: TimeInterval = 60,
        onInFlightRequestQueued: InFlightHandler? = nil,
        tickHandler: @escaping TickHandler
    ) {
        self.interval = LocalNetworkSyncInterval.normalized(interval)
        self.inFlightHandler = onInFlightRequestQueued
        self.tickHandler = tickHandler
    }

    convenience init(engine: LocalNetworkSyncEngine, interval: TimeInterval = 60) {
        self.init(interval: interval) { trigger, syncRunID in
            _ = await engine.performTick(trigger: trigger, syncRunID: syncRunID)
        }
    }

    @discardableResult
    func foregroundTick() async -> Bool {
        await runTickIfPossible(trigger: "foreground")
    }

    @discardableResult
    func requestTick(trigger: String = "manual", syncRunID: String? = nil) async -> Bool {
        await runTickIfPossible(trigger: trigger, syncRunID: syncRunID)
    }

    func startPeriodicTicks() {
        guard periodicTask == nil else {
            return
        }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                _ = await self.runTickIfPossible(trigger: "timer")
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    @discardableResult
    private func runTickIfPossible(trigger: String, syncRunID: String? = nil) async -> Bool {
        if isTickInFlight {
            pendingRequestAfterCurrentRun = (trigger, syncRunID)
            inFlightHandler?(trigger)
            return false
        }

        isTickInFlight = true
        var nextRequest: (trigger: String, syncRunID: String?)? = (trigger, syncRunID)
        defer {
            isTickInFlight = false
            pendingRequestAfterCurrentRun = nil
        }
        while let currentRequest = nextRequest {
            pendingRequestAfterCurrentRun = nil
            await tickHandler(currentRequest.trigger, currentRequest.syncRunID)
            nextRequest = pendingRequestAfterCurrentRun
        }
        return true
    }
}

@MainActor
final class LocalNetworkSyncAppService: ObservableObject {
    private let connectionStore: SecureMacConnectionStore
    private let connectionStatusStore: DeviceConnectionStatusStore
    private let recordingManager: RecordingManager
    private let uploadCoordinator: RecordingUploadCoordinator
    private let scheduler: LocalNetworkSyncScheduler
    private let heartbeatMonitor: LocalNetworkHeartbeatMonitor
    private var isActive = false
    private var retryDrainTask: Task<Void, Never>?
    private var uploadLedgerObserver: NSObjectProtocol?
    private var syncEventObserver: NSObjectProtocol?
    private var statusConvergenceObserver: NSObjectProtocol?
    private var pairingObserver: NSObjectProtocol?
    private var statusStoreSubscription: AnyCancellable?
    private var lastSyncSoonRequestAt: Date?
    private var lastHeartbeatSyncRequestedQueueAt: Date?
    private var syncEventDebounceTask: Task<Void, Never>?
    private var pendingSyncEventReasons: Set<SyncTriggerReason> = []
    private var pendingSyncEventRunID: String?
    private var pendingSyncEventFirstReceivedAt: Date?
    private var pendingSyncEventReceivedCount = 0
    private var pendingSyncEventCoalescedCount = 0
    private var lastSyncEventQueuedAt: Date?
    private var syncEventWindowStartedAt: Date?
    private var syncEventWindowCount = 0
    private let syncEventTickContextStore: LocalNetworkSyncEventTickContextStore
    private let heartbeatSyncRequestedDebounceInterval: TimeInterval = 5
    private let syncEventDebounceInterval: TimeInterval = 0.75
    private let syncEventMaxFrequencyInterval: TimeInterval = 1.5
    private let syncEventStormWindow: TimeInterval = 5
    private let syncEventMaxEventsPerWindow = 40
    private let syncEventMaxReasonDepth = SyncTriggerReason.allCases.count

    init(interval: TimeInterval = 60) {
        let audioFileStore = AudioFileStore()
        let recordingManager = RecordingManager(fileStore: audioFileStore)
        let connectionStore = SecureMacConnectionStore()
        let connectionStatusStore = DeviceConnectionStatusStore.shared
        let secureClient = SecureMacUploadClient()
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioFileStore)
        let kernelSwitchResultProvider: () -> CanonicalKernelSwitchResult = {
            CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults().resolve()
        }
        let canonicalStatusTruthRuntime = CanonicalStatusTruthRuntime()
        let canonicalStatusExchangeRuntime = CanonicalStatusExchangeRuntime(
            nodeID: CanonicalNodeID("iphone-\(connectionStore.snapshot.deviceID)"),
            truthRuntime: canonicalStatusTruthRuntime
        )
        let uploadCoordinator = RecordingUploadCoordinator(
            jobStore: uploadJobStore,
            canonicalKernelSwitchResultProvider: kernelSwitchResultProvider,
            canonicalStatusTruthRuntime: canonicalStatusTruthRuntime
        )
        let kernelSwitchResult = kernelSwitchResultProvider()
        let eventTickContextStore = LocalNetworkSyncEventTickContextStore()
        let engine = LocalNetworkSyncEngine(
            connectionStore: connectionStore,
            audioFileStore: audioFileStore,
            studyLibraryStore: recordingManager.studyLibraryStore,
            recordingManager: recordingManager,
            uploadCoordinator: uploadCoordinator,
            uploadJobStore: uploadJobStore,
            client: secureClient,
            connectionStatusStore: connectionStatusStore,
            canonicalSyncRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.syncRuntimeConfiguration,
            canonicalApplyRuntimeConfiguration: kernelSwitchResult.effectiveConfiguration.applyRuntimeConfiguration,
            canonicalKernelSwitchResultProvider: kernelSwitchResultProvider,
            canonicalStatusTruthRuntime: canonicalStatusTruthRuntime,
            canonicalStatusExchangeRuntime: canonicalStatusExchangeRuntime
        )

        self.connectionStore = connectionStore
        self.connectionStatusStore = connectionStatusStore
        self.recordingManager = recordingManager
        self.uploadCoordinator = uploadCoordinator
        self.syncEventTickContextStore = eventTickContextStore
        self.heartbeatMonitor = LocalNetworkHeartbeatMonitor(
            connectionStore: connectionStore,
            client: secureClient,
            statusStore: connectionStatusStore,
            canonicalStatusExchangeRuntime: canonicalStatusExchangeRuntime
        )
        let scheduler = LocalNetworkSyncScheduler(
            interval: interval,
            onInFlightRequestQueued: { trigger in
                ConnectionDiagnosticsStore.shared.record(
                    phase: "syncSkippedReason",
                    deviceID: connectionStore.snapshot.deviceID,
                    result: "alreadyInFlight queued:\(trigger)",
                    errorCode: "already_in_flight"
                )
                if trigger == "manual-sync-requested" {
                    ConnectionDiagnosticsStore.shared.record(
                        phase: "heartbeatSyncRequestedTickAlreadyRunning",
                        deviceID: connectionStore.snapshot.deviceID,
                        result: "pendingAfterCurrentRun",
                        errorCode: "already_running"
                    )
                }
                if Self.isEventDrivenTrigger(trigger) {
                    ConnectionDiagnosticsStore.shared.record(
                        phase: "syncEventImmediateTickAlreadyRunning",
                        deviceID: connectionStore.snapshot.deviceID,
                        result: Self.redactedTriggerSummary(trigger),
                        errorCode: "already_running"
                    )
                    ConnectionDiagnosticsStore.shared.record(
                        phase: "syncEventFollowUpTickQueued",
                        deviceID: connectionStore.snapshot.deviceID,
                        result: "followUpSyncQueuedCount=1"
                    )
                }
            }
        ) { trigger, syncRunID in
            if Self.isEventDrivenTrigger(trigger) {
                let context = syncRunID.flatMap { eventTickContextStore.context(for: $0) }
                let startedAt = Date()
                let startLatencyMs = context.map { max(0, startedAt.timeIntervalSince($0.firstReceivedAt) * 1_000) }
                ConnectionDiagnosticsStore.shared.record(
                    phase: "syncEventImmediateTickStarted",
                    deviceID: connectionStore.snapshot.deviceID,
                    syncRunID: syncRunID,
                    result: Self.eventTickMetricsSummary(
                        started: 1,
                        reasons: context?.reasonsSummary ?? Self.redactedTriggerSummary(trigger),
                        coalescedReasonCount: context?.coalescedReasonCount ?? 0
                    ),
                    latencyMs: startLatencyMs
                )
                if context?.reasons.contains(.manualPeerSyncRequested) == true {
                    ConnectionDiagnosticsStore.shared.record(
                        phase: "heartbeatSyncRequestedTickStarted",
                        deviceID: connectionStore.snapshot.deviceID,
                        syncRunID: syncRunID,
                        result: "immediateSyncStartedCount=1",
                        latencyMs: startLatencyMs
                    )
                }
                let plan = await engine.performTick(trigger: trigger, syncRunID: syncRunID)
                let finishedAt = Date()
                let durationMs = max(0, finishedAt.timeIntervalSince(startedAt) * 1_000)
                let completeLatencyMs = context.map { max(0, finishedAt.timeIntervalSince($0.firstReceivedAt) * 1_000) }
                ConnectionDiagnosticsStore.shared.record(
                    phase: plan == nil ? "syncEventImmediateTickFailed" : "syncEventImmediateTickCompleted",
                    deviceID: connectionStore.snapshot.deviceID,
                    syncRunID: syncRunID,
                    result: Self.eventTickMetricsSummary(
                        completed: plan == nil ? 0 : 1,
                        failed: plan == nil ? 1 : 0,
                        durationMs: Int(durationMs),
                        reasons: context?.reasonsSummary ?? Self.redactedTriggerSummary(trigger),
                        coalescedReasonCount: context?.coalescedReasonCount ?? 0
                    ),
                    latencyMs: completeLatencyMs ?? durationMs,
                    errorCode: plan == nil ? "immediate_sync_failed" : nil
                )
                if context?.reasons.contains(.manualPeerSyncRequested) == true {
                    ConnectionDiagnosticsStore.shared.record(
                        phase: plan == nil ? "heartbeatSyncRequestedTickFailed" : "heartbeatSyncRequestedTickCompleted",
                        deviceID: connectionStore.snapshot.deviceID,
                        syncRunID: syncRunID,
                        result: "\(plan == nil ? "immediateSyncFailedCount" : "immediateSyncCompletedCount")=1,immediateSyncDurationMs=\(Int(durationMs))",
                        latencyMs: durationMs,
                        errorCode: plan == nil ? "immediate_sync_failed" : nil
                    )
                }
                if let syncRunID {
                    eventTickContextStore.removeContext(for: syncRunID)
                }
            } else if trigger == "manual-sync-requested" {
                let startedAt = Date()
                ConnectionDiagnosticsStore.shared.record(
                    phase: "heartbeatSyncRequestedTickStarted",
                    deviceID: connectionStore.snapshot.deviceID,
                    syncRunID: syncRunID,
                    result: "immediateSyncStartedCount=1"
                )
                let plan = await engine.performTick(trigger: trigger, syncRunID: syncRunID)
                let durationMs = max(0, Date().timeIntervalSince(startedAt) * 1_000)
                ConnectionDiagnosticsStore.shared.record(
                    phase: plan == nil ? "heartbeatSyncRequestedTickFailed" : "heartbeatSyncRequestedTickCompleted",
                    deviceID: connectionStore.snapshot.deviceID,
                    syncRunID: syncRunID,
                    result: "\(plan == nil ? "immediateSyncFailedCount" : "immediateSyncCompletedCount")=1,immediateSyncDurationMs=\(Int(durationMs))",
                    latencyMs: durationMs,
                    errorCode: plan == nil ? "immediate_sync_failed" : nil
                )
            } else {
                _ = await engine.performTick(trigger: trigger, syncRunID: syncRunID)
            }
        }
        self.scheduler = scheduler
        self.heartbeatMonitor.onSyncRequested = { [weak self] syncRunID in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.handleHeartbeatSyncRequestedHint(syncRunID: syncRunID)
            }
        }
        self.uploadLedgerObserver = NotificationCenter.default.addObserver(
            forName: .recordingUploadJobLedgerDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let service = self else {
                return
            }
            Task { @MainActor in
                service.requestUploadLedgerTick()
            }
        }
        self.syncEventObserver = NotificationCenter.default.addObserver(
            forName: .localNetworkSyncEventTriggered,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let reason = LocalNetworkSyncEventTrigger.reason(from: notification) else {
                return
            }
            Task { @MainActor [weak self] in
                self?.queueImmediateSync(reason: reason)
            }
        }
        self.statusConvergenceObserver = NotificationCenter.default.addObserver(
            forName: .localNetworkStatusConvergenceRefreshRequested,
            object: nil,
            queue: .main
        ) { notification in
            guard let reason = LocalNetworkSyncEventTrigger.reason(from: notification) else {
                return
            }
            ConnectionDiagnosticsStore.shared.record(
                phase: "statusConvergenceRefreshRequested",
                deviceID: connectionStore.snapshot.deviceID,
                result: "reason=\(reason.rawValue),statusProjectionRefreshCount=1"
            )
            if reason == .audioUploadFinalized {
                ConnectionDiagnosticsStore.shared.record(
                    phase: "statusConvergenceFinalizeProofAccepted",
                    deviceID: connectionStore.snapshot.deviceID,
                    result: "reason=\(reason.rawValue)"
                )
            } else if reason == .syncStatusRefreshRequested || reason == .transcriptionStatusChanged || reason == .noteStatusChanged {
                ConnectionDiagnosticsStore.shared.record(
                    phase: "statusConvergencePeerProofUnavailable",
                    deviceID: connectionStore.snapshot.deviceID,
                    result: "reason=\(reason.rawValue)"
                )
            }
        }
        self.pairingObserver = NotificationCenter.default.addObserver(
            forName: .secureMacPairingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let service = self else {
                return
            }
            Task { @MainActor in
                service.handlePairingChanged()
            }
        }
        self.statusStoreSubscription = connectionStatusStore.$statusesByDeviceID
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleConnectionStatusChanged()
                }
            }
    }

    deinit {
        if let uploadLedgerObserver {
            NotificationCenter.default.removeObserver(uploadLedgerObserver)
        }
        if let syncEventObserver {
            NotificationCenter.default.removeObserver(syncEventObserver)
        }
        if let statusConvergenceObserver {
            NotificationCenter.default.removeObserver(statusConvergenceObserver)
        }
        if let pairingObserver {
            NotificationCenter.default.removeObserver(pairingObserver)
        }
    }

    func activate() {
        connectionStore.refreshFromStorage()
        isActive = true
        ConnectionDiagnosticsStore.shared.record(phase: "appBecameActive", deviceID: connectionStore.snapshot.deviceID)
        ConnectionDiagnosticsStore.shared.record(
            phase: "userConnectionIntentLoaded",
            deviceID: connectionStore.snapshot.deviceID,
            result: connectionStore.userConnectionIntent.rawValue
        )
        startPairedServicesIfPossible()
        if !pendingSyncEventReasons.isEmpty {
            queueImmediateSync(reason: .appForegroundedWithPendingChanges)
        }
    }

    func requestUploadLedgerTick() {
        connectionStore.refreshFromStorage()
        startRetryDrainerIfNeeded()
        queueImmediateSync(reason: .retryStateChanged)
    }

    private func handleHeartbeatSyncRequestedHint(syncRunID: String?, now: Date = Date()) {
        connectionStore.refreshFromStorage()
        let snapshot = connectionStore.snapshot
        ConnectionDiagnosticsStore.shared.record(
            phase: "heartbeatSyncRequestedHintReceived",
            deviceID: snapshot.deviceID,
            syncRunID: syncRunID,
            result: "connection-heartbeat"
        )

        guard snapshot.isPaired else {
            ConnectionDiagnosticsStore.shared.record(
                phase: "heartbeatSyncRequestedHintIgnoredNoPeer",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                errorCode: "not_paired"
            )
            return
        }
        guard connectionStore.userConnectionIntent == .wantsConnected else {
            ConnectionDiagnosticsStore.shared.record(
                phase: "heartbeatSyncRequestedHintIgnoredDisconnected",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                errorCode: "user_does_not_want_connection"
            )
            return
        }
        ConnectionDiagnosticsStore.shared.record(
            phase: "syncRequestedHintReceived",
            deviceID: snapshot.deviceID,
            syncRunID: syncRunID,
            result: "connection-heartbeat"
        )
        queueImmediateSync(reason: .manualPeerSyncRequested, syncRunID: syncRunID, now: now)
    }

    private func handlePairingChanged() {
        connectionStore.refreshFromStorage()
        guard isActive else {
            heartbeatMonitor.suspend()
            scheduler.stop()
            return
        }
        startPairedServicesIfPossible()
    }

    private func handleConnectionStatusChanged() {
        connectionStore.refreshFromStorage()
        guard isActive, connectionStore.snapshot.isPaired else {
            return
        }
        guard connectionStore.userConnectionIntent == .wantsConnected else {
            scheduler.stop()
            return
        }
        startSchedulerIfOnline()
    }

    private func startPairedServicesIfPossible() {
        guard connectionStore.snapshot.isPaired else {
            heartbeatMonitor.suspend()
            scheduler.stop()
            retryDrainTask?.cancel()
            retryDrainTask = nil
            return
        }
        guard connectionStore.userConnectionIntent == .wantsConnected else {
            heartbeatMonitor.stopBecauseUserDoesNotWantConnection()
            scheduler.stop()
            retryDrainTask?.cancel()
            retryDrainTask = nil
            ConnectionDiagnosticsStore.shared.record(
                phase: "heartbeatSuppressedBecauseUserDoesNotWantConnection",
                deviceID: connectionStore.snapshot.deviceID
            )
            return
        }

        heartbeatMonitor.startForegroundMonitoring()
        startSchedulerIfOnline()
    }

    private func startSchedulerIfOnline() {
        let snapshot = connectionStore.snapshot
        guard LocalNetworkSyncStartGate.canRun(
            isActive: isActive,
            snapshot: snapshot,
            status: connectionStatusStore.status(for: snapshot.deviceID),
            userConnectionIntent: connectionStore.userConnectionIntent
        ) else {
            scheduler.stop()
            retryDrainTask?.cancel()
            retryDrainTask = nil
            if connectionStore.userConnectionIntent == .disconnectedByUser {
                ConnectionDiagnosticsStore.shared.record(
                    phase: "syncSkippedBecauseUserDoesNotWantConnection",
                    deviceID: snapshot.deviceID,
                    errorCode: "user_does_not_want_connection"
                )
            } else {
                ConnectionDiagnosticsStore.shared.record(phase: "syncSkippedOffline", deviceID: snapshot.deviceID, errorCode: "presence_not_online")
            }
            return
        }

        guard !scheduler.isRunning else {
            if !pendingSyncEventReasons.isEmpty {
                queueImmediateSync(reason: .appForegroundedWithPendingChanges)
            }
            return
        }

        scheduler.startPeriodicTicks()
        startRetryDrainerIfNeeded()
        ConnectionDiagnosticsStore.shared.record(phase: "syncSchedulerStarted", deviceID: connectionStore.snapshot.deviceID)
        Task {
            await scheduler.foregroundTick()
        }
        if !pendingSyncEventReasons.isEmpty {
            queueImmediateSync(reason: .appForegroundedWithPendingChanges)
        }
    }

    private func startRetryDrainerIfNeeded() {
        guard retryDrainTask == nil else {
            return
        }
        retryDrainTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                await self.drainRetryJobsIfPossible()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func drainRetryJobsIfPossible() async {
        connectionStore.refreshFromStorage()
        let snapshot = connectionStore.snapshot
        guard LocalNetworkSyncStartGate.canRun(
            isActive: isActive,
            snapshot: snapshot,
            status: connectionStatusStore.status(for: snapshot.deviceID),
            userConnectionIntent: connectionStore.userConnectionIntent
        ) else {
            return
        }
        guard !uploadCoordinator.hasActiveUploadInFlight() else {
            ConnectionDiagnosticsStore.shared.record(
                phase: "retryDrainerDeferredBecauseUploadActive",
                deviceID: snapshot.deviceID,
                errorCode: "upload_active"
            )
            return
        }
        let syncRunID = UUID().uuidString
        let drained = await uploadCoordinator.drainEligibleRetryJobs(
            settings: snapshot,
            recordingManager: recordingManager,
            syncRunID: syncRunID
        )
        if !drained.isEmpty {
            ConnectionDiagnosticsStore.shared.record(
                phase: "retryDrainerStarted",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "drained=\(drained.count)"
            )
        }
    }

    private func shouldRequestSyncSoon(now: Date, debounceInterval: TimeInterval = 5) -> Bool {
        if let lastSyncSoonRequestAt,
           now.timeIntervalSince(lastSyncSoonRequestAt) < debounceInterval {
            return false
        }
        lastSyncSoonRequestAt = now
        return true
    }

    func queueImmediateSync(
        reason: SyncTriggerReason,
        syncRunID: String? = nil,
        now: Date = Date()
    ) {
        connectionStore.refreshFromStorage()
        let snapshot = connectionStore.snapshot
        recordSyncEventWindow(now: now, reason: reason, deviceID: snapshot.deviceID, syncRunID: syncRunID)
        guard syncEventWindowCount <= syncEventMaxEventsPerWindow else {
            pendingSyncEventReasons.insert(.syncStatusRefreshRequested)
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncEventStormSuppressed",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "reason=\(reason.rawValue),stormSuppressedCount=1,maxEventsPerWindow=\(syncEventMaxEventsPerWindow)",
                errorCode: "event_storm_suppressed"
            )
            return
        }

        let alreadyPending = pendingSyncEventReasons.contains(reason)
        if pendingSyncEventReasons.count >= syncEventMaxReasonDepth, !alreadyPending {
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncEventStormSuppressed",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "reasonDepth=\(pendingSyncEventReasons.count),stormSuppressedCount=1",
                errorCode: "reason_depth_exceeded"
            )
            return
        }

        pendingSyncEventReasons.insert(reason)
        pendingSyncEventRunID = pendingSyncEventRunID ?? syncRunID
        pendingSyncEventFirstReceivedAt = pendingSyncEventFirstReceivedAt ?? now
        pendingSyncEventReceivedCount += 1
        if alreadyPending {
            pendingSyncEventCoalescedCount += 1
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncEventTriggerCoalesced",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "reason=\(reason.rawValue),eventTriggerCoalescedCount=1,coalescedReasonCount=\(pendingSyncEventCoalescedCount)"
            )
        }

        ConnectionDiagnosticsStore.shared.record(
            phase: "syncEventTriggerReceived",
            deviceID: snapshot.deviceID,
            syncRunID: syncRunID,
            result: "reason=\(reason.rawValue),eventTriggerReceivedCount=1,pendingReasonCount=\(pendingSyncEventReasons.count)"
        )
        if reason == .manualPeerSyncRequested {
            ConnectionDiagnosticsStore.shared.record(
                phase: "heartbeatSyncRequestedTickQueued",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "immediateSyncQueuedCount=1"
            )
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncRequestedTickQueued",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "heartbeat"
            )
        }

        guard isActive else {
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncEventImmediateTickDeferredBackground",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "reason=\(reason.rawValue),deferredBackgroundCount=1",
                errorCode: "app_inactive"
            )
            if reason == .manualPeerSyncRequested {
                ConnectionDiagnosticsStore.shared.record(
                    phase: "heartbeatSyncRequestedTickDeferredBackground",
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    errorCode: "app_inactive"
                )
            }
            return
        }

        guard LocalNetworkSyncStartGate.canRun(
            isActive: isActive,
            snapshot: snapshot,
            status: connectionStatusStore.status(for: snapshot.deviceID, now: now),
            userConnectionIntent: connectionStore.userConnectionIntent
        ) else {
            let errorCode = connectionStore.userConnectionIntent == .disconnectedByUser
                ? "user_does_not_want_connection"
                : "presence_not_online"
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncEventImmediateTickDeferredOffline",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "reason=\(reason.rawValue),deferredOfflineCount=1",
                errorCode: errorCode
            )
            if reason == .manualPeerSyncRequested {
                ConnectionDiagnosticsStore.shared.record(
                    phase: "heartbeatSyncRequestedTickDeferredOffline",
                    deviceID: snapshot.deviceID,
                    syncRunID: syncRunID,
                    errorCode: errorCode
                )
            }
            return
        }

        if reason == .manualPeerSyncRequested,
           let lastHeartbeatSyncRequestedQueueAt,
           now.timeIntervalSince(lastHeartbeatSyncRequestedQueueAt) < heartbeatSyncRequestedDebounceInterval {
            pendingSyncEventCoalescedCount += 1
            ConnectionDiagnosticsStore.shared.record(
                phase: "heartbeatSyncRequestedTickDebounced",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "immediateSyncDedupedCount=1",
                errorCode: "debounced"
            )
        }

        scheduleImmediateSyncEventDrain(now: now)
    }

    private func scheduleImmediateSyncEventDrain(now: Date) {
        syncEventDebounceTask?.cancel()
        let frequencyDelay: TimeInterval
        if let lastSyncEventQueuedAt {
            frequencyDelay = max(0, syncEventMaxFrequencyInterval - now.timeIntervalSince(lastSyncEventQueuedAt))
        } else {
            frequencyDelay = 0
        }
        let delay = max(syncEventDebounceInterval, frequencyDelay)
        if delay > syncEventDebounceInterval {
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncEventImmediateTickDebounced",
                deviceID: connectionStore.snapshot.deviceID,
                result: "delayMs=\(Int(delay * 1_000))"
            )
        }
        syncEventDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await self?.drainImmediateSyncEventQueue()
        }
    }

    private func drainImmediateSyncEventQueue() async {
        syncEventDebounceTask = nil
        connectionStore.refreshFromStorage()
        let snapshot = connectionStore.snapshot
        let now = Date()
        guard !pendingSyncEventReasons.isEmpty else {
            return
        }
        guard LocalNetworkSyncStartGate.canRun(
            isActive: isActive,
            snapshot: snapshot,
            status: connectionStatusStore.status(for: snapshot.deviceID, now: now),
            userConnectionIntent: connectionStore.userConnectionIntent
        ) else {
            let phase = isActive ? "syncEventImmediateTickDeferredOffline" : "syncEventImmediateTickDeferredBackground"
            ConnectionDiagnosticsStore.shared.record(
                phase: phase,
                deviceID: snapshot.deviceID,
                syncRunID: pendingSyncEventRunID,
                result: "reasons=\(Self.reasonSummary(pendingSyncEventReasons))",
                errorCode: isActive ? "presence_not_online" : "app_inactive"
            )
            return
        }
        guard !uploadCoordinator.hasActiveUploadInFlight() else {
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncDeferredBecauseUploadActive",
                deviceID: snapshot.deviceID,
                syncRunID: pendingSyncEventRunID,
                result: "reasons=\(Self.reasonSummary(pendingSyncEventReasons))",
                errorCode: "upload_active"
            )
            scheduleImmediateSyncEventDrain(now: now)
            return
        }
        guard shouldRequestSyncSoon(now: now, debounceInterval: syncEventDebounceInterval) else {
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncEventImmediateTickDebounced",
                deviceID: snapshot.deviceID,
                syncRunID: pendingSyncEventRunID,
                result: "reasons=\(Self.reasonSummary(pendingSyncEventReasons))",
                errorCode: "debounced"
            )
            scheduleImmediateSyncEventDrain(now: now)
            return
        }

        let reasons = pendingSyncEventReasons
        let reasonsSummary = Self.reasonSummary(reasons)
        let firstReceivedAt = pendingSyncEventFirstReceivedAt ?? now
        let coalescedCount = pendingSyncEventCoalescedCount
        let receivedCount = pendingSyncEventReceivedCount
        let syncRunID = pendingSyncEventRunID ?? UUID().uuidString
        pendingSyncEventReasons = []
        pendingSyncEventRunID = nil
        pendingSyncEventFirstReceivedAt = nil
        pendingSyncEventReceivedCount = 0
        pendingSyncEventCoalescedCount = 0
        lastSyncEventQueuedAt = now
        if reasons.contains(.manualPeerSyncRequested) {
            lastHeartbeatSyncRequestedQueueAt = now
        }
        syncEventTickContextStore.setContext(LocalNetworkSyncEventTickContext(
            firstReceivedAt: firstReceivedAt,
            reasons: reasons,
            reasonsSummary: reasonsSummary,
            receivedCount: receivedCount,
            coalescedReasonCount: coalescedCount
        ), for: syncRunID)
        ConnectionDiagnosticsStore.shared.record(
            phase: "syncEventImmediateTickQueued",
            deviceID: snapshot.deviceID,
            syncRunID: syncRunID,
            result: "immediateSyncQueuedCount=1,reasons=\(reasonsSummary),eventTriggerReceivedCount=\(receivedCount),eventTriggerCoalescedCount=\(coalescedCount)"
        )
        await scheduler.requestTick(trigger: "event-driven:\(reasonsSummary)", syncRunID: syncRunID)
    }

    private func recordSyncEventWindow(now: Date, reason: SyncTriggerReason, deviceID: String, syncRunID: String?) {
        if syncEventWindowStartedAt == nil || now.timeIntervalSince(syncEventWindowStartedAt ?? now) > syncEventStormWindow {
            syncEventWindowStartedAt = now
            syncEventWindowCount = 0
        }
        syncEventWindowCount += 1
        if reason == .syncStatusRefreshRequested {
            ConnectionDiagnosticsStore.shared.record(
                phase: "statusConvergenceProjectionUpdated",
                deviceID: deviceID,
                syncRunID: syncRunID,
                result: "statusProjectionRefreshCount=1"
            )
        }
    }

    func suspend() {
        isActive = false
        ConnectionDiagnosticsStore.shared.record(phase: "appBecameInactive", deviceID: connectionStore.snapshot.deviceID)
        heartbeatMonitor.suspend()
        scheduler.stop()
        retryDrainTask?.cancel()
        retryDrainTask = nil
        syncEventDebounceTask?.cancel()
        syncEventDebounceTask = nil
    }

    private static func isEventDrivenTrigger(_ trigger: String) -> Bool {
        trigger.hasPrefix("event-driven:")
    }

    private static func redactedTriggerSummary(_ trigger: String) -> String {
        guard isEventDrivenTrigger(trigger),
              let summary = trigger.split(separator: ":", maxSplits: 1).last else {
            return "trigger"
        }
        return String(summary.prefix(240))
    }

    private static func reasonSummary(_ reasons: Set<SyncTriggerReason>) -> String {
        reasons
            .map(\.rawValue)
            .sorted()
            .joined(separator: "+")
            .prefix(240)
            .description
    }

    private static func eventTickMetricsSummary(
        started: Int = 0,
        completed: Int = 0,
        failed: Int = 0,
        durationMs: Int? = nil,
        reasons: String,
        coalescedReasonCount: Int
    ) -> String {
        var parts = [
            "immediateSyncStartedCount=\(started)",
            "immediateSyncCompletedCount=\(completed)",
            "immediateSyncFailedCount=\(failed)",
            "reasons=\(reasons)",
            "coalescedReasonCount=\(coalescedReasonCount)"
        ]
        if let durationMs {
            parts.append("immediateSyncDurationMs=\(durationMs)")
        }
        return parts.joined(separator: ",")
    }
}

private struct LocalNetworkSyncEventTickContext {
    var firstReceivedAt: Date
    var reasons: Set<SyncTriggerReason>
    var reasonsSummary: String
    var receivedCount: Int
    var coalescedReasonCount: Int
}

@MainActor
private final class LocalNetworkSyncEventTickContextStore {
    private var contextsByRunID: [String: LocalNetworkSyncEventTickContext] = [:]

    func setContext(_ context: LocalNetworkSyncEventTickContext, for syncRunID: String) {
        contextsByRunID[syncRunID] = context
    }

    func context(for syncRunID: String) -> LocalNetworkSyncEventTickContext? {
        contextsByRunID[syncRunID]
    }

    func removeContext(for syncRunID: String) {
        contextsByRunID.removeValue(forKey: syncRunID)
    }
}

private extension String {
    var safeSyncFileComponent: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return value.isEmpty ? "sync-object" : value
    }
}
