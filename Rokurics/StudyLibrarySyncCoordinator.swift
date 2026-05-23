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
    private let heartbeatInterval: TimeInterval
    private let syncInterval: TimeInterval
    private var heartbeatTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var failureCount = 0

    init(
        connectionStore: any SecureMacConnectionSnapshotProviding,
        studyLibraryStore: StudyLibraryStore,
        recordingManager: RecordingManager? = nil,
        uploadCoordinator: RecordingUploadCoordinator? = nil,
        client: SecureMacUploadClient? = nil,
        statusStore: DeviceConnectionStatusStore? = nil,
        syncStateStore: StudyLibrarySyncStateStore? = nil,
        runtimeConfiguration: StudyLibrarySyncRuntimeConfiguration = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false),
        heartbeatInterval: TimeInterval = 3,
        syncInterval: TimeInterval = 240
    ) {
        let resolvedClient = client ?? SecureMacUploadClient()
        let resolvedStatusStore = statusStore ?? DeviceConnectionStatusStore()
        let resolvedSyncStateStore = syncStateStore ?? StudyLibrarySyncStateStore()
        self.connectionStore = connectionStore
        self.studyLibraryStore = studyLibraryStore
        self.recordingManager = recordingManager
        self.uploadCoordinator = uploadCoordinator
        self.client = resolvedClient
        self.statusStore = resolvedStatusStore
        self.syncStateStore = resolvedSyncStateStore
        self.runtimeConfiguration = runtimeConfiguration
        self.heartbeatInterval = heartbeatInterval
        self.syncInterval = syncInterval
        self.syncState = resolvedSyncStateStore.state
        self.connectionStatus = resolvedStatusStore.latestStatus ?? .unpaired(displayName: "Mac")
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

        guard runtimeConfiguration.gitBackedSyncEnabled else {
            recordDisabledStatusForCurrentPairing()
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

        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        connectionStatus = statusStore.status(for: snapshot.deviceID)
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
                lastError: nil
            )
    }

    func performHeartbeat() async {
        let snapshot = connectionStore.snapshot
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
        guard runtimeConfiguration.gitBackedSyncEnabled else {
            recordDisabledStatusForCurrentPairing()
            return nil
        }

        return await performSync(trigger: "manual")
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
            return applyResponse.applyResult ?? pullResult
        } catch {
            syncStateStore.recordFailure(deviceID: snapshot.deviceID, error: error.localizedDescription)
            connectionStatus = statusStore.recordSyncResult(
                deviceID: snapshot.deviceID,
                displayName: displayName,
                statusText: "同步失败",
                error: error.localizedDescription
            )
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
        syncState = syncStateStore.state
        recordDisabledStatus(for: connectionStore.snapshot)
    }

    private func recordDisabledStatus(for snapshot: SecureMacConnectionSnapshot) {
        syncState = syncStateStore.state
        guard snapshot.isPaired else {
            failureCount = 0
            connectionStatus = statusStore.markUnpaired(displayName: "Mac")
            return
        }

        let displayName = snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : snapshot.macName
        connectionStatus = statusStore.recordSyncResult(
            deviceID: snapshot.deviceID,
            displayName: displayName,
            statusText: StudyLibrarySyncRuntimeConfiguration.disabledStatusText,
            error: StudyLibrarySyncRuntimeConfiguration.disabledReason
        )
    }

    private func sleep(seconds: TimeInterval) async {
        let nanoseconds = UInt64(max(0.1, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

private struct PendingUploadProcessingResult {
    var attemptedCount = 0
    var succeededCount = 0
    var failedCount = 0
    var remainingCount = 0
}
