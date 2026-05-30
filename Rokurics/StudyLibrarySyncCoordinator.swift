//
//  StudyLibrarySyncCoordinator.swift
//  Rokurics
//
//  Created by Codex on 2026/5/21.
//

import Combine
import Foundation
import UIKit

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
    @Published private(set) var connectionStatus: DeviceConnectionStatus
    @Published private(set) var syncState: StudyLibrarySyncState
    @Published private(set) var isSyncing = false

    private let connectionStore: any SecureMacConnectionSnapshotProviding
    private let studyLibraryStore: StudyLibraryStore
    private weak var recordingManager: RecordingManager?
    private let uploadCoordinator: RecordingUploadCoordinator?
    private let client: SecureMacUploadClient
    private let statusStore: DeviceConnectionStatusStore
    private let syncStateStore: StudyLibrarySyncStateStore
    private let runtimeConfiguration: StudyLibrarySyncRuntimeConfiguration
    private let presenceHeartbeatMonitor: LocalNetworkHeartbeatMonitor
    private let diagnosticsStore: ConnectionDiagnosticsStore
    private let heartbeatInterval: TimeInterval
    private let syncInterval: TimeInterval
    private var heartbeatTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var statusStoreSubscription: AnyCancellable?
    private var failureCount = 0

    init(
        connectionStore: any SecureMacConnectionSnapshotProviding,
        studyLibraryStore: StudyLibraryStore,
        recordingManager: RecordingManager? = nil,
        uploadCoordinator: RecordingUploadCoordinator? = nil,
        client: SecureMacUploadClient? = nil,
        presenceHeartbeatClient: (any LocalNetworkHeartbeatClientProtocol)? = nil,
        statusStore: DeviceConnectionStatusStore? = nil,
        syncStateStore: StudyLibrarySyncStateStore? = nil,
        diagnosticsStore: ConnectionDiagnosticsStore? = nil,
        runtimeConfiguration: StudyLibrarySyncRuntimeConfiguration = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false),
        heartbeatInterval: TimeInterval = 3,
        syncInterval: TimeInterval = 240
    ) {
        let resolvedClient = client ?? SecureMacUploadClient()
        let resolvedStatusStore = statusStore ?? .shared
        let resolvedSyncStateStore = syncStateStore ?? StudyLibrarySyncStateStore()
        let resolvedDiagnosticsStore = diagnosticsStore ?? .shared
        self.connectionStore = connectionStore
        self.studyLibraryStore = studyLibraryStore
        self.recordingManager = recordingManager
        self.uploadCoordinator = uploadCoordinator
        self.client = resolvedClient
        self.statusStore = resolvedStatusStore
        self.syncStateStore = resolvedSyncStateStore
        self.runtimeConfiguration = runtimeConfiguration
        self.diagnosticsStore = resolvedDiagnosticsStore
        self.presenceHeartbeatMonitor = LocalNetworkHeartbeatMonitor(
            connectionStore: connectionStore,
            client: presenceHeartbeatClient ?? resolvedClient,
            statusStore: resolvedStatusStore,
            diagnosticsStore: resolvedDiagnosticsStore
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
            connectionStatus = statusStore.markUnpaired(displayName: "Mac")
            return
        }
        guard userWantsConnection else {
            connectionStatus = statusStore.markUserDisconnected(
                deviceID: snapshot.deviceID,
                displayName: displayName(for: snapshot)
            )
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
            connectionStatus = statusStore.markUnpaired(displayName: "Mac")
            return
        }

        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        connectionStatus = statusStore.markConnecting(deviceID: snapshot.deviceID, displayName: displayName)

        do {
            let request = DeviceStatusRequest(
                displayName: UIDevice.current.name,
                clientState: UIApplication.shared.applicationState == .active ? "foreground" : "background",
                generatedAt: Date(),
                syncSummary: syncSummary
            )
            let response = try await client.sendDeviceStatus(settings: snapshot, statusRequest: request)
            guard response.ok else {
                throw SecureMacUploadError.serverRejected(response.error ?? "device_status_failed")
            }

            failureCount = 0
            syncState = syncStateStore.state
            connectionStatus = statusStore.markConnected(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                lastSyncAt: syncState.lastSuccessfulSyncAt,
                lastSyncStatus: syncState.lastError ?? connectionStatus.lastSyncStatus
            )
        } catch {
            failureCount += 1
            connectionStatus = statusStore.markOffline(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                error: error.localizedDescription
            )
        }
    }

    @discardableResult
    func synchronizeNow() async -> StudyLibrarySyncApplyResult? {
        let snapshot = connectionStore.snapshot
        diagnosticsStore.record(phase: "manualSyncTapped", deviceID: snapshot.deviceID)
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
            recordDisabledStatusForCurrentPairing()
            return nil
        }

        return await performSync(trigger: "manual")
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
            connectionStatus = statusStore.markUnpaired(displayName: "Mac")
            return
        }
        connectionStatus = statusStore.markUserDisconnected(
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

        guard !isSyncing else {
            return nil
        }

        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            connectionStatus = statusStore.markUnpaired(displayName: "Mac")
            return nil
        }

        isSyncing = true
        defer {
            isSyncing = false
            syncState = syncStateStore.state
        }

        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        do {
            if trigger == "manual" {
                diagnosticsStore.record(phase: "manualSyncStarted", deviceID: snapshot.deviceID)
            }
            let remoteResponse = try await client.fetchStudyLibraryManifest(settings: snapshot)
            guard remoteResponse.ok, let remoteManifest = remoteResponse.manifest else {
                throw SecureMacUploadError.serverRejected(remoteResponse.error ?? "sync_manifest_missing")
            }

            let pullResult = try studyLibraryStore.applySyncManifest(remoteManifest, localDeviceID: snapshot.deviceID)
            syncStateStore.recordPull(
                deviceID: snapshot.deviceID,
                remoteManifestHash: remoteManifest.checksum,
                remoteCommitID: remoteManifest.commitID ?? remoteResponse.newCommitID
            )

            let uploadResult = await processPendingRecordingUploads(remoteManifest: remoteManifest, settings: snapshot)
            var localManifest = studyLibraryStore.makeSyncManifest(deviceID: snapshot.deviceID)
            localManifest.baseCommitID = syncStateStore.state.lastKnownRemoteCommitID ?? remoteManifest.commitID ?? remoteResponse.newCommitID
            localManifest.localManifestHash = localManifest.checksum
            let applyResponse = try await client.applyStudyLibraryManifest(settings: snapshot, manifest: localManifest)
            guard applyResponse.ok else {
                throw SecureMacUploadError.serverRejected(applyResponse.error ?? "sync_apply_failed")
            }

            if let returnedManifest = applyResponse.manifest,
               returnedManifest.checksum != remoteManifest.checksum {
                _ = try? studyLibraryStore.applySyncManifest(returnedManifest, localDeviceID: snapshot.deviceID)
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
            connectionStatus = statusStore.recordSyncResult(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                statusText: trigger == "manual" ? "手动同步完成：\(summary)" : summary
            )
            if trigger == "manual" {
                diagnosticsStore.record(phase: "manualSyncSucceededRefreshSignedRequest", deviceID: snapshot.deviceID)
            }
            return applyResponse.applyResult ?? pullResult
        } catch {
            syncStateStore.recordFailure(deviceID: snapshot.deviceID, error: error.localizedDescription)
            connectionStatus = statusStore.recordSyncStatus(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                statusText: "同步失败"
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
            guard !recording.isDeleted,
                  RecordingUploadStatus(rawMetadataValue: recording.uploadStatus) != .uploaded else {
                return false
            }

            guard let remoteItem = remoteItemsByRecordingID[recording.id] else {
                return true
            }

            return remoteItem.audioRelativePath == nil
                || remoteItem.customProperties["syncedMetadataOnly"] == "true"
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

    private func recordDisabledStatus(for snapshot: SecureMacConnectionSnapshot) {
        syncState = syncStateStore.state
        guard snapshot.isPaired else {
            failureCount = 0
            connectionStatus = statusStore.markUnpaired(displayName: "Mac")
            return
        }
        guard userWantsConnection else {
            connectionStatus = statusStore.markUserDisconnected(
                deviceID: snapshot.deviceID,
                displayName: displayName(for: snapshot)
            )
            return
        }

        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        connectionStatus = statusStore.recordSyncStatus(
            deviceID: snapshot.deviceID,
            displayName: displayName,
            statusText: StudyLibrarySyncRuntimeConfiguration.disabledStatusText
        )
    }

    private func refreshConnectionStatusFromStore(now: Date = Date()) {
        let snapshot = connectionStore.snapshot
        syncState = syncStateStore.state
        guard snapshot.isPaired else {
            connectionStatus = statusStore.markUnpaired(displayName: "Mac")
            return
        }
        guard userWantsConnection else {
            connectionStatus = statusStore.markUserDisconnected(
                deviceID: snapshot.deviceID,
                displayName: displayName(for: snapshot),
                now: now
            )
            return
        }

        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        connectionStatus = statusStore.status(for: snapshot.deviceID, now: now)
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
            )
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
}

private struct PendingUploadProcessingResult {
    var attemptedCount = 0
    var succeededCount = 0
    var failedCount = 0
    var remainingCount = 0
}

protocol LocalNetworkSyncClientProtocol {
    func sendDeviceStatus(settings: SecureMacConnectionSnapshot, statusRequest: DeviceStatusRequest) async throws -> DeviceStatusResponse
    func fetchLocalNetworkSyncInventory(settings: SecureMacConnectionSnapshot, localInventory: LocalNetworkSyncInventory) async throws -> LocalNetworkSyncInventoryResponse
    func applyLocalNetworkSyncMetadata(settings: SecureMacConnectionSnapshot, manifest: StudyLibrarySyncManifest) async throws -> StudyLibrarySyncManifestResponse
    func requestLocalNetworkSyncArtifact(settings: SecureMacConnectionSnapshot, artifactID: String) async throws -> LocalNetworkSyncArtifactResponse
    func putLocalNetworkSyncArtifact(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactPutRequest) async throws -> LocalNetworkSyncArtifactPutResponse
}

extension SecureMacUploadClient: LocalNetworkSyncClientProtocol {}

protocol LocalNetworkHeartbeatClientProtocol {
    func sendConnectionHeartbeat(
        settings: SecureMacConnectionSnapshot,
        request: ConnectionHeartbeatRequest,
        requestTimeout: TimeInterval
    ) async throws -> ConnectionHeartbeatResponse
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
    private var heartbeatTask: Task<Void, Never>?
    private var sequenceNumber: UInt64 = 0
    private(set) var isHeartbeatInFlight = false

    init(
        connectionStore: any SecureMacConnectionSnapshotProviding,
        client: (any LocalNetworkHeartbeatClientProtocol)? = nil,
        statusStore: DeviceConnectionStatusStore? = nil,
        diagnosticsStore: ConnectionDiagnosticsStore? = nil,
        configuration: LocalNetworkHeartbeatConfiguration = .foregroundDefault
    ) {
        self.connectionStore = connectionStore
        self.client = client ?? SecureMacUploadClient()
        self.statusStore = statusStore ?? .shared
        self.diagnosticsStore = diagnosticsStore ?? .shared
        self.configuration = configuration
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
        let request = ConnectionHeartbeatRequest(
            deviceID: snapshot.deviceID,
            deviceName: UIDevice.current.name,
            platform: .iPhone,
            appInstanceID: nil,
            sequenceNumber: requestSequence,
            sentAt: now,
            lastKnownPeerStatusRevision: statusBeforeSend?.connectionStatusRevision
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
            return true
        } catch {
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

@MainActor
struct LocalNetworkSyncInventoryBuilder {
    let audioFileStore: AudioFileStore
    let studyLibraryStore: StudyLibraryStore
    let uploadJobStore: RecordingUploadJobStore

    func build(
        deviceID: String,
        deviceName: String,
        lastKnownPeerRevision: String?,
        generatedAt: Date = Date()
    ) -> LocalNetworkSyncInventory {
        let manifest = studyLibraryStore.makeSyncManifest(deviceID: deviceID, generatedAt: generatedAt)
        let recordings = (try? audioFileStore.loadAllMetadata(includeDeleted: true)) ?? []
        let jobsByRecordingID = ((try? uploadJobStore.loadJobs()) ?? []).reduce(into: [String: RecordingUploadJob]()) { result, job in
            result[job.recordingID] = job
        }
        let rootURL = (try? audioFileStore.baseDirectory()) ?? FileManager.default.temporaryDirectory
        let recordingEntries = recordings.map { metadata in
            let audioURL = try? audioFileStore.audioURL(for: metadata)
            let hasAudio = audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let fileSize = audioURL.flatMap { LocalNetworkSyncArtifactFileService.metadata(for: $0)?.size }
            return LocalNetworkSyncRecordingEntry(
                recordingID: metadata.id,
                metadataHash: LocalNetworkSyncMetadataHash.hash(metadata),
                audioAvailable: hasAudio,
                audioChecksum: nil,
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
                ]
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
                revisionHash: LocalNetworkSyncMetadataHash.hash(folder),
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
                revisionHash: LocalNetworkSyncMetadataHash.hash(item),
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

        return LocalNetworkSyncInventory.make(
            device: device,
            recordings: recordingEntries,
            folders: folders,
            studyItems: studyItems,
            artifacts: makeArtifacts(from: manifest, recordings: recordings, rootURL: rootURL),
            studyManifest: manifest
        )
    }

    private func makeArtifacts(
        from manifest: StudyLibrarySyncManifest,
        recordings: [RecordingMetadata],
        rootURL: URL
    ) -> [LocalNetworkSyncArtifactEntry] {
        var artifacts: [LocalNetworkSyncArtifactEntry] = []
        for recording in recordings {
            appendArtifact(
                relativePath: recording.relativeMetadataPath,
                kind: .metadataJSON,
                ownerID: recording.id,
                rootURL: rootURL,
                artifacts: &artifacts
            )
        }
        for item in manifest.items {
            let ownerID = item.recordingID ?? item.itemID
            appendArtifact(relativePath: item.receiveRelativePath, kind: .receiveJSON, ownerID: ownerID, rootURL: rootURL, artifacts: &artifacts)
            appendArtifact(relativePath: item.transcriptMarkdownRelativePath, kind: .transcriptMarkdown, ownerID: ownerID, rootURL: rootURL, artifacts: &artifacts)
            appendArtifact(relativePath: item.transcriptRelativePath, kind: .transcriptJSON, ownerID: ownerID, rootURL: rootURL, artifacts: &artifacts)
            appendArtifact(
                relativePath: item.noteRelativePath,
                kind: item.noteRelativePath?.hasSuffix(".json") == true ? .noteJSON : .noteMarkdown,
                ownerID: ownerID,
                rootURL: rootURL,
                artifacts: &artifacts
            )
            appendArtifact(relativePath: item.audioRelativePath, kind: .audio, ownerID: ownerID, rootURL: rootURL, includeChecksum: false, artifacts: &artifacts)
        }
        return artifacts
    }

    private func appendArtifact(
        relativePath: String?,
        kind: LocalNetworkSyncArtifactKind,
        ownerID: String,
        rootURL: URL,
        includeChecksum: Bool = true,
        artifacts: inout [LocalNetworkSyncArtifactEntry]
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
              FileManager.default.fileExists(atPath: url.path),
              let metadata = LocalNetworkSyncArtifactFileService.metadata(for: url) else {
            return
        }

        artifacts.append(
            LocalNetworkSyncArtifactEntry(
                artifactID: LocalNetworkSyncArtifactID.make(kind: kind, ownerID: ownerID, logicalPathToken: relativePath),
                kind: kind,
                ownerID: ownerID,
                checksum: includeChecksum ? try? LocalNetworkSyncArtifactFileService.sha256Hex(fileURL: url) : nil,
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

@MainActor
final class LocalNetworkSyncEngine {
    private static let maxSmallArtifactUploadBytes: Int64 = 4 * 1024 * 1024

    private let connectionStore: any SecureMacConnectionSnapshotProviding
    private let inventoryBuilder: LocalNetworkSyncInventoryBuilder
    private let audioFileStore: AudioFileStore
    private let studyLibraryStore: StudyLibraryStore
    private weak var recordingManager: RecordingManager?
    private let uploadCoordinator: RecordingUploadCoordinator?
    private let client: any LocalNetworkSyncClientProtocol
    private let stateStore: LocalNetworkSyncStateStore
    private let connectionStatusStore: DeviceConnectionStatusStore?
    private let diagnosticsStore: ConnectionDiagnosticsStore
    private let diffPlanner: LocalNetworkSyncDiffPlanner
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
        connectionStatusStore: DeviceConnectionStatusStore? = nil,
        diagnosticsStore: ConnectionDiagnosticsStore? = nil,
        diffPlanner: LocalNetworkSyncDiffPlanner? = nil
    ) {
        self.connectionStore = connectionStore
        self.audioFileStore = audioFileStore
        self.studyLibraryStore = studyLibraryStore
        self.recordingManager = recordingManager
        self.uploadCoordinator = uploadCoordinator
        self.client = client ?? SecureMacUploadClient()
        self.stateStore = stateStore ?? LocalNetworkSyncStateStore(rootURL: try? audioFileStore.baseDirectory())
        self.connectionStatusStore = connectionStatusStore
        self.diagnosticsStore = diagnosticsStore ?? .shared
        self.diffPlanner = diffPlanner ?? LocalNetworkSyncDiffPlanner()
        self.inventoryBuilder = LocalNetworkSyncInventoryBuilder(
            audioFileStore: audioFileStore,
            studyLibraryStore: studyLibraryStore,
            uploadJobStore: uploadJobStore
        )
    }

    @discardableResult
    func performTick(trigger: String, now: Date = Date()) async -> LocalNetworkSyncDiffPlan? {
        guard !isSyncing else {
            return nil
        }
        if let nextAllowedSyncAt = stateStore.state.nextAllowedSyncAt,
           nextAllowedSyncAt > now {
            diagnosticsStore.record(phase: "syncSkippedBackoff", deviceID: connectionStore.snapshot.deviceID)
            return nil
        }

        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            diagnosticsStore.record(phase: "syncSkippedOffline", deviceID: snapshot.deviceID, errorCode: "not_paired")
            stateStore.recordFailure(code: "not_paired", message: "Mac is not paired.", at: now)
            return nil
        }
        if (connectionStore as? SecureMacConnectionIntentProviding)?.userConnectionIntent == .disconnectedByUser {
            diagnosticsStore.record(
                phase: "syncSkippedBecauseUserDoesNotWantConnection",
                deviceID: snapshot.deviceID,
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
           status.presenceSnapshot(now: now).state == .disconnected || status.presenceSnapshot(now: now).state == .securityError {
            stateStore.recordFailure(
                code: status.presenceSnapshot(now: now).state == .securityError ? "connection_security_error" : "connection_disconnected",
                message: status.lastError ?? "Mac connection is not available for sync.",
                at: now
            )
            return nil
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            diagnosticsStore.record(phase: "syncTickStarted", deviceID: snapshot.deviceID)
            let localInventory = inventoryBuilder.build(
                deviceID: snapshot.deviceID,
                deviceName: UIDevice.current.name,
                lastKnownPeerRevision: stateStore.state.lastPeerInventoryHash,
                generatedAt: now
            )
            diagnosticsStore.record(phase: "localInventoryBuilt", deviceID: snapshot.deviceID)
            let peerResponse = try await client.fetchLocalNetworkSyncInventory(settings: snapshot, localInventory: localInventory)
            guard peerResponse.ok, let peerInventory = peerResponse.inventory else {
                throw SecureMacUploadError.serverRejected(peerResponse.error ?? "sync_inventory_missing")
            }
            diagnosticsStore.record(phase: "peerInventoryFetched", deviceID: snapshot.deviceID)

            let plan = diffPlanner.plan(
                local: localInventory,
                peer: peerInventory,
                lastSuccessfulSyncAt: stateStore.state.lastSuccessfulSyncAt
            )
            let pendingUploadCount = plan.uploadMetadataActions.count + plan.uploadRecordingAudioActions.count + plan.uploadArtifactActions.count
            let pendingDownloadCount = plan.downloadMetadataActions.count + plan.downloadArtifactActions.count
            diagnosticsStore.record(
                phase: "diffPlanCreated",
                deviceID: snapshot.deviceID,
                pendingUploadCount: pendingUploadCount,
                pendingDownloadCount: pendingDownloadCount
            )
            if !plan.conflictActions.isEmpty {
                diagnosticsStore.record(phase: "conflictDetected", deviceID: snapshot.deviceID)
            }
            stateStore.recordAttempt(
                localDeviceID: localInventory.device.deviceID,
                peerDeviceID: peerInventory.device.deviceID,
                localInventoryHash: localInventory.inventoryHash,
                peerInventoryHash: peerInventory.inventoryHash,
                pendingUploadCount: pendingUploadCount,
                pendingDownloadCount: pendingDownloadCount,
                planSummary: "upload:\(pendingUploadCount),download:\(pendingDownloadCount),conflict:\(plan.conflictActions.count)",
                conflictCount: plan.conflictActions.count,
                at: now
            )
            let pendingTransfers = transferProgresses(peerInventory: peerInventory, plan: plan, state: .pending)
            if !pendingTransfers.isEmpty {
                stateStore.recordActiveTransfers(pendingTransfers)
            }

            try applyPeerRecordingStatuses(peerInventory: peerInventory)
            try applyPeerMetadataIfNeeded(peerInventory: peerInventory, plan: plan, localDeviceID: snapshot.deviceID)
            try createPlaceholderTransfers(peerInventory: peerInventory, plan: plan, localDeviceID: snapshot.deviceID)
            try await uploadLocalMetadataIfNeeded(localInventory: localInventory, plan: plan, settings: snapshot)
            try await uploadLocalArtifactsIfNeeded(localInventory: localInventory, plan: plan, settings: snapshot)
            try await downloadPeerArtifactsIfNeeded(peerInventory: peerInventory, plan: plan, settings: snapshot)
            await uploadMissingRecordingAudioIfNeeded(plan: plan, settings: snapshot)

            let refreshedInventory = inventoryBuilder.build(
                deviceID: snapshot.deviceID,
                deviceName: UIDevice.current.name,
                lastKnownPeerRevision: peerInventory.inventoryHash
            )
            stateStore.recordSuccess(
                peerDeviceID: peerInventory.device.deviceID,
                localInventoryHash: refreshedInventory.inventoryHash,
                peerInventoryHash: peerInventory.inventoryHash,
                appliedPeerRevision: peerInventory.inventoryHash,
                pendingUploadCount: 0,
                pendingDownloadCount: 0
            )
            connectionStatusStore?.recordSignedRequestSucceeded(
                deviceID: snapshot.deviceID,
                displayName: snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName,
                now: Date()
            )
            diagnosticsStore.record(phase: "syncTickCompleted", deviceID: snapshot.deviceID)
            return plan
        } catch {
            diagnosticsStore.record(phase: "syncTickFailed", deviceID: snapshot.deviceID, errorCode: "sync_tick_failed", errorMessage: error.localizedDescription)
            stateStore.recordFailure(code: "sync_tick_failed", message: error.localizedDescription, at: now)
            return nil
        }
    }

    private func applyPeerRecordingStatuses(peerInventory: LocalNetworkSyncInventory) throws {
        var didChange = false
        for peerRecording in peerInventory.recordings where peerRecording.receiveStatus == "completed" {
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
    ) throws {
        guard !plan.downloadMetadataActions.isEmpty,
              let manifest = peerInventory.studyManifest else {
            return
        }
        _ = try studyLibraryStore.applySyncManifest(manifest, localDeviceID: localDeviceID)
        diagnosticsStore.record(phase: "metadataApplied", deviceID: localDeviceID)
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
    }

    private func uploadLocalMetadataIfNeeded(
        localInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        settings: SecureMacConnectionSnapshot
    ) async throws {
        guard !plan.uploadMetadataActions.isEmpty,
              let manifest = localInventory.studyManifest else {
            return
        }
        diagnosticsStore.record(phase: "uploadActionStarted", deviceID: settings.deviceID)
        do {
            let response = try await client.applyLocalNetworkSyncMetadata(settings: settings, manifest: manifest)
            guard response.ok else {
                throw SecureMacUploadError.serverRejected(response.error ?? "sync_apply_metadata_failed")
            }
            diagnosticsStore.record(phase: "uploadActionCompleted", deviceID: settings.deviceID)
        } catch {
            diagnosticsStore.record(phase: "uploadActionFailed", deviceID: settings.deviceID, errorCode: "sync_apply_metadata_failed", errorMessage: error.localizedDescription)
            throw error
        }
    }

    private func downloadPeerArtifactsIfNeeded(
        peerInventory: LocalNetworkSyncInventory,
        plan: LocalNetworkSyncDiffPlan,
        settings: SecureMacConnectionSnapshot
    ) async throws {
        let artifactsByID = Dictionary(uniqueKeysWithValues: peerInventory.artifacts.map { ($0.artifactID, $0) })
        for action in plan.downloadArtifactActions {
            guard let artifact = artifactsByID[action.entityID],
                  artifact.kind.isAutoDownloadAllowed else {
                continue
            }
            diagnosticsStore.record(phase: "downloadActionStarted", deviceID: settings.deviceID)
            do {
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
                diagnosticsStore.record(phase: "transferStarted", deviceID: settings.deviceID)
                let response = try await client.requestLocalNetworkSyncArtifact(settings: settings, artifactID: artifact.artifactID)
                try saveTransferProgress(
                    for: artifact,
                    peerInventory: peerInventory,
                    state: .verifying,
                    progressFraction: 1,
                    statusText: "校验中"
                )
                diagnosticsStore.record(phase: "transferProgressUpdated", deviceID: settings.deviceID)
                try writeArtifactResponse(response, deviceID: settings.deviceID)
                try clearTransferProgress(for: artifact, peerInventory: peerInventory)
                stateStore.recordActiveTransfers([])
                diagnosticsStore.record(phase: "transferCompleted", deviceID: settings.deviceID)
                diagnosticsStore.record(phase: "downloadActionCompleted", deviceID: settings.deviceID)
            } catch {
                try? saveTransferProgress(
                    for: artifact,
                    peerInventory: peerInventory,
                    state: .failed,
                    progressFraction: nil,
                    statusText: "传输失败"
                )
                diagnosticsStore.record(phase: "transferFailed", deviceID: settings.deviceID, errorCode: "sync_artifact_download_failed", errorMessage: error.localizedDescription)
                diagnosticsStore.record(phase: "downloadActionFailed", deviceID: settings.deviceID, errorCode: "sync_artifact_download_failed", errorMessage: error.localizedDescription)
                throw error
            }
        }
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
        settings: SecureMacConnectionSnapshot
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
            guard let metadata = LocalNetworkSyncArtifactFileService.metadata(for: fileURL),
                  metadata.size <= Self.maxSmallArtifactUploadBytes else {
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
                dataBase64: data.base64EncodedString()
            )
            diagnosticsStore.record(phase: "uploadActionStarted", deviceID: settings.deviceID)
            do {
                let response = try await client.putLocalNetworkSyncArtifact(settings: settings, request: request)
                guard response.ok else {
                    throw SecureMacUploadError.serverRejected(response.error ?? "sync_artifact_put_failed")
                }
                diagnosticsStore.record(phase: "uploadActionCompleted", deviceID: settings.deviceID)
            } catch {
                diagnosticsStore.record(phase: "uploadActionFailed", deviceID: settings.deviceID, errorCode: "sync_artifact_put_failed", errorMessage: error.localizedDescription)
                throw error
            }
        }
    }

    private func uploadMissingRecordingAudioIfNeeded(
        plan: LocalNetworkSyncDiffPlan,
        settings: SecureMacConnectionSnapshot
    ) async {
        guard let recordingManager, let uploadCoordinator else {
            return
        }
        recordingManager.reloadRecordings()
        for action in plan.uploadRecordingAudioActions {
            guard let metadata = recordingManager.recordings.first(where: { $0.id == action.entityID }) else {
                continue
            }
            diagnosticsStore.record(phase: "uploadActionStarted", deviceID: settings.deviceID)
            _ = await uploadCoordinator.uploadAndWait(
                metadata: metadata,
                settings: settings,
                recordingManager: recordingManager
            )
            diagnosticsStore.record(phase: "uploadActionCompleted", deviceID: settings.deviceID)
        }
    }

    private func writeArtifactResponse(_ response: LocalNetworkSyncArtifactResponse, deviceID: String) throws {
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
        diagnosticsStore.record(phase: "artifactChecksumVerified", deviceID: deviceID)
        diagnosticsStore.record(phase: "transferVerified", deviceID: deviceID)

        let rootURL = try audioFileStore.baseDirectory()
        let destinationURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: logicalPathToken, kind: kind)
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destinationURL, options: .atomic)
        NotificationCenter.default.post(name: .localNetworkStudyLibraryDidChange, object: nil)
    }
}

@MainActor
enum LocalNetworkSyncInterval {
    static let defaultInterval: TimeInterval = 30
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
        return status?.presenceSnapshot().isOnline == true
    }
}

@MainActor
final class LocalNetworkSyncScheduler {
    typealias TickHandler = @MainActor (String) async -> Void

    private let interval: TimeInterval
    private let tickHandler: TickHandler
    private var periodicTask: Task<Void, Never>?
    private(set) var isTickInFlight = false
    var configuredInterval: TimeInterval { interval }
    var isRunning: Bool { periodicTask != nil }

    init(interval: TimeInterval = 30, tickHandler: @escaping TickHandler) {
        self.interval = LocalNetworkSyncInterval.normalized(interval)
        self.tickHandler = tickHandler
    }

    convenience init(engine: LocalNetworkSyncEngine, interval: TimeInterval = 30) {
        self.init(interval: interval) { trigger in
            _ = await engine.performTick(trigger: trigger)
        }
    }

    @discardableResult
    func foregroundTick() async -> Bool {
        await runTickIfPossible(trigger: "foreground")
    }

    @discardableResult
    func requestTick(trigger: String = "manual") async -> Bool {
        await runTickIfPossible(trigger: trigger)
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
    private func runTickIfPossible(trigger: String) async -> Bool {
        guard !isTickInFlight else {
            return false
        }
        isTickInFlight = true
        defer { isTickInFlight = false }
        await tickHandler(trigger)
        return true
    }
}

@MainActor
final class LocalNetworkSyncAppService: ObservableObject {
    private let connectionStore: SecureMacConnectionStore
    private let connectionStatusStore: DeviceConnectionStatusStore
    private let scheduler: LocalNetworkSyncScheduler
    private let heartbeatMonitor: LocalNetworkHeartbeatMonitor
    private var isActive = false
    private var uploadLedgerObserver: NSObjectProtocol?
    private var pairingObserver: NSObjectProtocol?
    private var statusStoreSubscription: AnyCancellable?
    private var lastSyncSoonRequestAt: Date?

    init(interval: TimeInterval = 30) {
        let audioFileStore = AudioFileStore()
        let recordingManager = RecordingManager(fileStore: audioFileStore)
        let connectionStore = SecureMacConnectionStore()
        let connectionStatusStore = DeviceConnectionStatusStore.shared
        let secureClient = SecureMacUploadClient()
        let uploadCoordinator = RecordingUploadCoordinator()
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioFileStore)
        let engine = LocalNetworkSyncEngine(
            connectionStore: connectionStore,
            audioFileStore: audioFileStore,
            studyLibraryStore: recordingManager.studyLibraryStore,
            recordingManager: recordingManager,
            uploadCoordinator: uploadCoordinator,
            uploadJobStore: uploadJobStore,
            client: secureClient,
            connectionStatusStore: connectionStatusStore
        )

        self.connectionStore = connectionStore
        self.connectionStatusStore = connectionStatusStore
        self.heartbeatMonitor = LocalNetworkHeartbeatMonitor(
            connectionStore: connectionStore,
            client: secureClient,
            statusStore: connectionStatusStore
        )
        self.scheduler = LocalNetworkSyncScheduler(engine: engine, interval: interval)
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
    }

    func requestUploadLedgerTick() {
        connectionStore.refreshFromStorage()
        let snapshot = connectionStore.snapshot
        guard LocalNetworkSyncStartGate.canRun(
            isActive: isActive,
            snapshot: snapshot,
            status: connectionStatusStore.status(for: snapshot.deviceID),
            userConnectionIntent: connectionStore.userConnectionIntent
        ) else {
            let errorCode = connectionStore.userConnectionIntent == .disconnectedByUser
                ? "user_does_not_want_connection"
                : "presence_not_online"
            ConnectionDiagnosticsStore.shared.record(
                phase: connectionStore.userConnectionIntent == .disconnectedByUser
                    ? "syncSkippedBecauseUserDoesNotWantConnection"
                    : "syncSkippedOffline",
                deviceID: snapshot.deviceID,
                errorCode: errorCode
            )
            return
        }
        guard shouldRequestSyncSoon(now: Date()) else {
            return
        }
        Task {
            await scheduler.requestTick(trigger: "upload-ledger")
        }
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
            return
        }
        guard connectionStore.userConnectionIntent == .wantsConnected else {
            heartbeatMonitor.stopBecauseUserDoesNotWantConnection()
            scheduler.stop()
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
            return
        }

        scheduler.startPeriodicTicks()
        ConnectionDiagnosticsStore.shared.record(phase: "syncSchedulerStarted", deviceID: connectionStore.snapshot.deviceID)
        Task {
            await scheduler.foregroundTick()
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

    func suspend() {
        isActive = false
        ConnectionDiagnosticsStore.shared.record(phase: "appBecameInactive", deviceID: connectionStore.snapshot.deviceID)
        heartbeatMonitor.suspend()
        scheduler.stop()
    }
}
