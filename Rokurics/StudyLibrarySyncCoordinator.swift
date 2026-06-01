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
    private let localNetworkSyncClient: any LocalNetworkSyncClientProtocol
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
    private var pendingManualLocalNetworkSync = false

    init(
        connectionStore: any SecureMacConnectionSnapshotProviding,
        studyLibraryStore: StudyLibraryStore,
        recordingManager: RecordingManager? = nil,
        uploadCoordinator: RecordingUploadCoordinator? = nil,
        client: SecureMacUploadClient? = nil,
        localNetworkSyncClient: (any LocalNetworkSyncClientProtocol)? = nil,
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
        self.localNetworkSyncClient = localNetworkSyncClient ?? resolvedClient
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
            let engine = LocalNetworkSyncEngine(
                connectionStore: connectionStore,
                audioFileStore: audioFileStore,
                studyLibraryStore: studyLibraryStore,
                recordingManager: recordingManager,
                uploadCoordinator: uploadCoordinator,
                uploadJobStore: uploadJobStore,
                client: localNetworkSyncClient,
                connectionStatusStore: statusStore,
                diagnosticsStore: diagnosticsStore
            )
            let syncRunID = UUID().uuidString
            syncStateStore.recordControlPlane(
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
                diagnosticsStore.record(phase: "syncStartAckReceived", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: response.disposition)
            } catch {
                syncStateStore.recordControlPlane(
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
            refreshConnectionStatusFromStore()
        } while pendingManualLocalNetworkSync
        return nil
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
    func fetchLocalNetworkSyncInventory(settings: SecureMacConnectionSnapshot, localInventory: LocalNetworkSyncInventory, syncRunID: String?) async throws -> LocalNetworkSyncInventoryResponse
    func sendLocalNetworkSyncStartSignal(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncStartRequest) async throws -> LocalNetworkSyncStartResponse
    func sendLocalNetworkSyncStartAck(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncStartAckRequest) async throws -> LocalNetworkSyncStartAckResponse
    func applyLocalNetworkSyncMetadata(settings: SecureMacConnectionSnapshot, manifest: StudyLibrarySyncManifest) async throws -> StudyLibrarySyncManifestResponse
    func requestLocalNetworkSyncArtifact(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactRequest) async throws -> LocalNetworkSyncArtifactResponse
    func fetchLocalNetworkSyncArtifactStatus(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactStatusRequest) async throws -> LocalNetworkSyncArtifactStatusResponse
    func putLocalNetworkSyncArtifact(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactPutRequest) async throws -> LocalNetworkSyncArtifactPutResponse
}

extension LocalNetworkSyncClientProtocol {
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
    private var heartbeatTask: Task<Void, Never>?
    private var sequenceNumber: UInt64 = 0
    private(set) var isHeartbeatInFlight = false
    var onSyncRequested: ((String?) -> Void)?

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
    let diagnosticsStore: ConnectionDiagnosticsStore
    var checksumCache = LocalNetworkChecksumCache()

    init(
        audioFileStore: AudioFileStore,
        studyLibraryStore: StudyLibraryStore,
        uploadJobStore: RecordingUploadJobStore,
        diagnosticsStore: ConnectionDiagnosticsStore? = nil,
        checksumCache: LocalNetworkChecksumCache? = nil
    ) {
        self.audioFileStore = audioFileStore
        self.studyLibraryStore = studyLibraryStore
        self.uploadJobStore = uploadJobStore
        self.diagnosticsStore = diagnosticsStore ?? .shared
        self.checksumCache = checksumCache ?? LocalNetworkChecksumCache()
    }

    func build(
        deviceID: String,
        deviceName: String,
        lastKnownPeerRevision: String?,
        generatedAt: Date = Date()
    ) -> LocalNetworkSyncInventory {
        let startedAt = Date()
        diagnosticsStore.record(phase: "inventoryBuildStarted", deviceID: deviceID)
        let manifest = studyLibraryStore.makeSyncManifest(deviceID: deviceID, generatedAt: generatedAt)
        let recordings = (try? audioFileStore.loadAllMetadata(includeDeleted: true)) ?? []
        let jobsByRecordingID = ((try? uploadJobStore.loadJobs()) ?? []).reduce(into: [String: RecordingUploadJob]()) { result, job in
            result[job.recordingID] = job
        }
        let rootURL = (try? audioFileStore.baseDirectory()) ?? FileManager.default.temporaryDirectory
        let recordingEntries = recordings.map { metadata in
            let audioURL = try? audioFileStore.audioURL(for: metadata)
            let hasAudio = audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            let checksumResult = hasAudio ? audioURL.flatMap {
                cachedChecksum(
                    fileURL: $0,
                    pathToken: metadata.relativeAudioPath,
                    deviceID: deviceID,
                    recordingID: metadata.id
                )
            } : nil
            let fileSize = checksumResult?.size ?? audioURL.flatMap { LocalNetworkSyncArtifactFileService.metadata(for: $0)?.size }
            let checksum = checksumResult?.sha256
            return LocalNetworkSyncRecordingEntry(
                recordingID: metadata.id,
                metadataHash: LocalNetworkSyncMetadataHash.hash(metadata),
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

        let inventory = LocalNetworkSyncInventory.make(
            device: device,
            recordings: recordingEntries,
            folders: folders,
            studyItems: studyItems,
            artifacts: makeArtifacts(from: manifest, recordings: recordings, rootURL: rootURL),
            studyManifest: manifest
        )
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

    private func cachedChecksum(
        fileURL: URL,
        pathToken: String?,
        deviceID: String,
        recordingID: String
    ) -> LocalNetworkChecksumCacheResult? {
        do {
            let result = try checksumCache.checksum(
                fileURL: fileURL,
                pathToken: pathToken,
                sourceSide: "iPhone"
            ) { url in
                try Self.sha256HexOffMainActor(fileURL: url)
            }
            if let result {
                let phase: String
                switch result.event {
                case .hit:
                    phase = "checksumCacheHit"
                case .miss:
                    phase = "checksumCacheMiss"
                case .invalidated:
                    phase = "checksumCacheInvalidated"
                }
                diagnosticsStore.record(
                    phase: phase,
                    deviceID: deviceID,
                    result: "recording=\(String(recordingID.prefix(12))),path=\(String((pathToken ?? "missing").prefix(12))),size=\(result.size)"
                )
                if result.event != .hit {
                    diagnosticsStore.record(
                        phase: "checksumComputedOffMainActor",
                        deviceID: deviceID,
                        result: "recording=\(String(recordingID.prefix(12))),path=\(String((pathToken ?? "missing").prefix(12)))"
                    )
                }
            }
            return result
        } catch {
            diagnosticsStore.record(
                phase: "checksumCacheMiss",
                deviceID: deviceID,
                result: "recording=\(String(recordingID.prefix(12))),path=\(String((pathToken ?? "missing").prefix(12)))",
                errorCode: "checksum_failed",
                errorMessage: error.localizedDescription
            )
            return nil
        }
    }

    private static func sha256HexOffMainActor(fileURL: URL) throws -> String {
        guard Thread.isMainThread else {
            return try SecureUploadUtilities.sha256Hex(fileURL: fileURL)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String, Error>!
        DispatchQueue.global(qos: .utility).async {
            result = Result {
                try SecureUploadUtilities.sha256Hex(fileURL: fileURL)
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try result.get()
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
    private static let artifactChunkBytes = 2 * 1024 * 1024

    private let connectionStore: any SecureMacConnectionSnapshotProviding
    private let inventoryBuilder: LocalNetworkSyncInventoryBuilder
    private let audioFileStore: AudioFileStore
    private let studyLibraryStore: StudyLibraryStore
    private weak var recordingManager: RecordingManager?
    private let uploadCoordinator: RecordingUploadCoordinator?
    private let client: any LocalNetworkSyncClientProtocol
    private let stateStore: LocalNetworkSyncStateStore
    private let transferJobStore: LocalNetworkSyncTransferJobStore
    private let uploadJobStore: RecordingUploadJobStore
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
        transferJobStore: LocalNetworkSyncTransferJobStore? = nil,
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
        self.transferJobStore = transferJobStore ?? LocalNetworkSyncTransferJobStore(rootURL: try? audioFileStore.baseDirectory())
        self.uploadJobStore = uploadJobStore
        self.connectionStatusStore = connectionStatusStore
        self.diagnosticsStore = diagnosticsStore ?? .shared
        self.diffPlanner = diffPlanner ?? LocalNetworkSyncDiffPlanner()
        self.inventoryBuilder = LocalNetworkSyncInventoryBuilder(
            audioFileStore: audioFileStore,
            studyLibraryStore: studyLibraryStore,
            uploadJobStore: uploadJobStore,
            diagnosticsStore: self.diagnosticsStore
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
            stateStore.recordControlPlane(syncRunID: syncRunID, state: .syncStartAcked, at: now)
            diagnosticsStore.record(phase: "syncRunStarted", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: trigger)
            diagnosticsStore.record(phase: "syncTickStarted", deviceID: snapshot.deviceID, syncRunID: syncRunID, result: trigger)
            stateStore.recordControlPlane(syncRunID: syncRunID, state: .inventoryExchanging)
            let localInventory = inventoryBuilder.build(
                deviceID: snapshot.deviceID,
                deviceName: UIDevice.current.name,
                lastKnownPeerRevision: stateStore.state.lastPeerInventoryHash,
                generatedAt: now
            )
            diagnosticsStore.record(
                phase: "localInventoryBuilt",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "objectCount=\(localInventory.objects.count),recordings:\(localInventory.recordings.count),items:\(localInventory.studyItems.count),artifacts:\(localInventory.artifacts.count)"
            )
            let peerResponse = try await client.fetchLocalNetworkSyncInventory(settings: snapshot, localInventory: localInventory, syncRunID: syncRunID)
            guard peerResponse.ok, let peerInventory = peerResponse.inventory else {
                throw SecureMacUploadError.serverRejected(peerResponse.error ?? "sync_inventory_missing")
            }
            diagnosticsStore.record(
                phase: "peerInventoryFetched",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "objectCount=\(peerInventory.objects.count),recordings:\(peerInventory.recordings.count),items:\(peerInventory.studyItems.count),artifacts:\(peerInventory.artifacts.count)"
            )

            stateStore.recordControlPlane(syncRunID: syncRunID, state: .planningTransfers)
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
                syncRunID: syncRunID,
                result: "actionCount=\(pendingUploadCount + pendingDownloadCount + plan.conflictActions.count),uploadMetadata:\(plan.uploadMetadataActions.count),uploadAudio:\(plan.uploadRecordingAudioActions.count),uploadArtifacts:\(plan.uploadArtifactActions.count),downloadMetadata:\(plan.downloadMetadataActions.count),downloadArtifacts:\(plan.downloadArtifactActions.count),conflicts:\(plan.conflictActions.count)",
                pendingUploadCount: pendingUploadCount,
                pendingDownloadCount: pendingDownloadCount
            )
            diagnosticsStore.record(
                phase: "bidirectionalDiffPlanCreated",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "actionCount=\(pendingUploadCount + pendingDownloadCount + plan.conflictActions.count),upload:\(pendingUploadCount),download:\(pendingDownloadCount),conflicts:\(plan.conflictActions.count)",
                pendingUploadCount: pendingUploadCount,
                pendingDownloadCount: pendingDownloadCount
            )
            diagnosticsStore.record(
                phase: "transferPlanCreated",
                deviceID: snapshot.deviceID,
                syncRunID: syncRunID,
                result: "upload:\(pendingUploadCount),download:\(pendingDownloadCount),conflict:\(plan.conflictActions.count)",
                pendingUploadCount: pendingUploadCount,
                pendingDownloadCount: pendingDownloadCount
            )
            stateStore.recordControlPlane(syncRunID: syncRunID, state: .transferJobsCreated)
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
            stateStore.recordControlPlane(syncRunID: syncRunID, state: .transferring)
            try await uploadLocalMetadataIfNeeded(localInventory: localInventory, plan: plan, settings: snapshot, syncRunID: syncRunID)
            try await uploadLocalArtifactsIfNeeded(localInventory: localInventory, plan: plan, settings: snapshot, syncRunID: syncRunID)
            try await downloadPeerArtifactsIfNeeded(peerInventory: peerInventory, plan: plan, settings: snapshot, syncRunID: syncRunID)
            let remainingAudioTransfers = await uploadMissingRecordingAudioIfNeeded(
                plan: plan,
                localInventory: localInventory,
                peerInventory: peerInventory,
                settings: snapshot,
                syncRunID: syncRunID,
                triggerSource: triggerSource
            )

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
                pendingUploadCount: remainingAudioTransfers.count,
                pendingDownloadCount: 0
            )
            if !remainingAudioTransfers.isEmpty {
                stateStore.recordActiveTransfers(remainingAudioTransfers)
            }
            connectionStatusStore?.recordSignedRequestSucceeded(
                deviceID: snapshot.deviceID,
                displayName: snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName,
                now: Date()
            )
            diagnosticsStore.record(phase: "syncTickCompleted", deviceID: snapshot.deviceID, syncRunID: syncRunID)
            diagnosticsStore.record(phase: "syncRunCompleted", deviceID: snapshot.deviceID, syncRunID: syncRunID)
            stateStore.recordControlPlane(syncRunID: syncRunID, state: .completed)
            return plan
        } catch {
            diagnosticsStore.record(phase: "syncTickFailed", deviceID: snapshot.deviceID, syncRunID: syncRunID, errorCode: "sync_tick_failed", errorMessage: error.localizedDescription)
            diagnosticsStore.record(phase: "syncRunFailed", deviceID: snapshot.deviceID, syncRunID: syncRunID, errorCode: "sync_tick_failed", errorMessage: error.localizedDescription)
            stateStore.recordControlPlane(syncRunID: syncRunID, state: .failed)
            stateStore.recordFailure(code: "sync_tick_failed", message: error.localizedDescription, at: now)
            return nil
        }
    }

    private static func isManualTrigger(_ trigger: String) -> Bool {
        let normalized = trigger.lowercased()
        return normalized.contains("manual") || normalized.contains("sync-requested")
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
        settings: SecureMacConnectionSnapshot,
        syncRunID: String
    ) async throws {
        guard !plan.uploadMetadataActions.isEmpty,
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
                diagnosticsStore.record(phase: "downloadActionCompleted", deviceID: settings.deviceID, syncRunID: syncRunID)
            } catch {
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
        try verifyAndApplyDownloadedArtifact(tempURL: tempURL, artifact: artifact, deviceID: settings.deviceID)
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
        let checksum = try LocalNetworkSyncArtifactFileService.sha256Hex(fileURL: fileURL)
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
            let peerAudio = peerAudioDecisionState(recordingID: action.entityID, in: peerInventory, localAudioState: localAudio)
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
        if recording != nil {
            return .metadataOnly
        }
        if object != nil {
            return .missing
        }
        return .unknown
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
                ?? (try? audioFileStore.audioURL(for: metadata))
                    .flatMap { try? SecureUploadUtilities.sha256Hex(fileURL: $0) }
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
            let status = await uploadCoordinator.uploadAndWait(
                metadata: metadata,
                settings: settings,
                recordingManager: recordingManager,
                traceID: traceID,
                triggerSource: triggerSource,
                peerAudioState: peerAudioDecisionState(
                    recordingID: metadata.id,
                    in: peerInventory,
                    localAudioState: localAudioDecisionState(recordingID: metadata.id, in: localInventory)
                ),
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
    }

    private func verifyAndApplyDownloadedArtifact(
        tempURL: URL,
        artifact: LocalNetworkSyncArtifactEntry,
        deviceID: String
    ) throws {
        if let expectedSize = artifact.size,
           LocalNetworkSyncArtifactFileService.metadata(for: tempURL)?.size != expectedSize {
            throw SecureMacUploadError.serverRejected("sync_artifact_size_mismatch")
        }
        if let expectedChecksum = artifact.checksum,
           try LocalNetworkSyncArtifactFileService.sha256Hex(fileURL: tempURL) != expectedChecksum {
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
    private var pairingObserver: NSObjectProtocol?
    private var statusStoreSubscription: AnyCancellable?
    private var lastSyncSoonRequestAt: Date?

    init(interval: TimeInterval = 60) {
        let audioFileStore = AudioFileStore()
        let recordingManager = RecordingManager(fileStore: audioFileStore)
        let connectionStore = SecureMacConnectionStore()
        let connectionStatusStore = DeviceConnectionStatusStore.shared
        let secureClient = SecureMacUploadClient()
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioFileStore)
        let uploadCoordinator = RecordingUploadCoordinator(jobStore: uploadJobStore)
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
        self.recordingManager = recordingManager
        self.uploadCoordinator = uploadCoordinator
        self.heartbeatMonitor = LocalNetworkHeartbeatMonitor(
            connectionStore: connectionStore,
            client: secureClient,
            statusStore: connectionStatusStore
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
            }
        ) { trigger, syncRunID in
            _ = await engine.performTick(trigger: trigger, syncRunID: syncRunID)
        }
        self.scheduler = scheduler
        self.heartbeatMonitor.onSyncRequested = { [weak scheduler, weak connectionStore] syncRunID in
            guard let scheduler, let connectionStore else {
                return
            }
            ConnectionDiagnosticsStore.shared.record(
                phase: "syncRequestedTickQueued",
                deviceID: connectionStore.snapshot.deviceID,
                syncRunID: syncRunID,
                result: "heartbeat"
            )
            Task { @MainActor in
                await scheduler.requestTick(trigger: "manual-sync-requested", syncRunID: syncRunID)
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
        startRetryDrainerIfNeeded()
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
            return
        }

        scheduler.startPeriodicTicks()
        startRetryDrainerIfNeeded()
        ConnectionDiagnosticsStore.shared.record(phase: "syncSchedulerStarted", deviceID: connectionStore.snapshot.deviceID)
        Task {
            await scheduler.foregroundTick()
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

    func suspend() {
        isActive = false
        ConnectionDiagnosticsStore.shared.record(phase: "appBecameInactive", deviceID: connectionStore.snapshot.deviceID)
        heartbeatMonitor.suspend()
        scheduler.stop()
        retryDrainTask?.cancel()
        retryDrainTask = nil
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
