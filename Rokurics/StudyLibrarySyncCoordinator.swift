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
    private var statusStoreSubscription: AnyCancellable?
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
        let resolvedStatusStore = statusStore ?? .shared
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

        refreshConnectionStatusFromStore()
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

    func recordSignedRequestSucceeded(settings: SecureMacConnectionSnapshot, now: Date = Date()) {
        guard settings.isPaired else {
            return
        }

        _ = statusStore.recordSignedRequestSucceeded(
            deviceID: settings.deviceID,
            displayName: settings.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rokurics Mac" : settings.macName,
            now: now
        )
        ConnectionDiagnosticsStore.shared.record(phase: "signedRequestRefreshedLastSeen", deviceID: settings.deviceID)
        refreshConnectionStatusFromStore(now: now)
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
        refreshConnectionStatusFromStore()
    }

    private func recordDisabledStatus(for snapshot: SecureMacConnectionSnapshot) {
        syncState = syncStateStore.state
        guard snapshot.isPaired else {
            failureCount = 0
            connectionStatus = statusStore.markUnpaired(displayName: "Mac")
            return
        }

        refreshConnectionStatusFromStore()
    }

    private func refreshConnectionStatusFromStore(now: Date = Date()) {
        let snapshot = connectionStore.snapshot
        syncState = syncStateStore.state
        guard snapshot.isPaired else {
            connectionStatus = statusStore.markUnpaired(displayName: "Mac")
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
        staleAfter: 6,
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
        guard heartbeatTask == nil else {
            return true
        }

        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            _ = statusStore.markUnpaired(displayName: "Mac")
            return false
        }

        diagnosticsStore.record(phase: "heartbeatMonitorStart", deviceID: snapshot.deviceID)
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                self.diagnosticsStore.record(phase: "heartbeatTickScheduled", deviceID: self.connectionStore.snapshot.deviceID)
                _ = await self.performHeartbeat()
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
            return false
        }

        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            _ = statusStore.markUnpaired(displayName: "Mac")
            return false
        }

        isHeartbeatInFlight = true
        defer { isHeartbeatInFlight = false }

        let displayName = displayName(for: snapshot)
        sequenceNumber += 1
        let statusBeforeSend = statusStore.status(for: snapshot.deviceID, now: now)
        _ = statusStore.markHeartbeatSent(deviceID: snapshot.deviceID, displayName: displayName, now: now)
        diagnosticsStore.record(phase: "heartbeatRequestStarted", deviceID: snapshot.deviceID, heartbeatMissCount: statusBeforeSend?.missedHeartbeatCount)
        let request = ConnectionHeartbeatRequest(
            deviceID: snapshot.deviceID,
            deviceName: UIDevice.current.name,
            platform: .iPhone,
            appInstanceID: nil,
            sequenceNumber: sequenceNumber,
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
            diagnosticsStore.record(phase: "heartbeatResponseReceived", deviceID: snapshot.deviceID)
            diagnosticsStore.record(phase: "heartbeatMarkedOnline", deviceID: snapshot.deviceID, heartbeatMissCount: status.missedHeartbeatCount)
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
                heartbeatMissCount: status.missedHeartbeatCount,
                errorCode: mapped.code,
                errorMessage: mapped.message
            )
            diagnosticsStore.record(phase: "heartbeatMissCount", deviceID: snapshot.deviceID, heartbeatMissCount: status.missedHeartbeatCount)
            if status.presenceState == .disconnected {
                diagnosticsStore.record(phase: "heartbeatMarkedDisconnected", deviceID: snapshot.deviceID, heartbeatMissCount: status.missedHeartbeatCount)
            } else if status.presenceState == .stale {
                diagnosticsStore.record(phase: "heartbeatMarkedStale", deviceID: snapshot.deviceID, heartbeatMissCount: status.missedHeartbeatCount)
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

    private func displayName(for snapshot: SecureMacConnectionSnapshot) -> String {
        snapshot.macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Rokurics Mac"
            : snapshot.macName
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
            let fileSize = audioURL.flatMap { LocalNetworkSyncArtifactFileService.metadata(for: $0)?.size }
            return LocalNetworkSyncRecordingEntry(
                recordingID: metadata.id,
                metadataHash: LocalNetworkSyncMetadataHash.hash(metadata),
                audioAvailable: audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false,
                audioChecksum: nil,
                audioSize: fileSize,
                uploadLedgerState: jobsByRecordingID[metadata.id]?.overallState.rawValue,
                receiveStatus: nil,
                processingStatus: nil,
                updatedAt: metadata.deletedAt ?? metadata.createdAt,
                deleted: metadata.isDeleted
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
                deleted: item.isTrashed
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
            artifacts: makeArtifacts(from: manifest, rootURL: rootURL),
            studyManifest: manifest
        )
    }

    private func makeArtifacts(from manifest: StudyLibrarySyncManifest, rootURL: URL) -> [LocalNetworkSyncArtifactEntry] {
        var artifacts: [LocalNetworkSyncArtifactEntry] = []
        for item in manifest.items {
            let ownerID = item.recordingID ?? item.itemID
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
        guard let relativePath,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = try? LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: relativePath),
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
                logicalPathToken: relativePath
            )
        )
    }
}

@MainActor
final class LocalNetworkSyncEngine {
    private let connectionStore: any SecureMacConnectionSnapshotProviding
    private let inventoryBuilder: LocalNetworkSyncInventoryBuilder
    private let audioFileStore: AudioFileStore
    private let studyLibraryStore: StudyLibraryStore
    private weak var recordingManager: RecordingManager?
    private let uploadCoordinator: RecordingUploadCoordinator?
    private let client: any LocalNetworkSyncClientProtocol
    private let stateStore: LocalNetworkSyncStateStore
    private let connectionStatusStore: DeviceConnectionStatusStore?
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
            return nil
        }

        let snapshot = connectionStore.snapshot
        guard snapshot.isPaired else {
            stateStore.recordFailure(code: "not_paired", message: "Mac is not paired.", at: now)
            return nil
        }
        if let status = connectionStatusStore?.status(for: snapshot.deviceID, now: now),
           status.presenceState == .disconnected || status.presenceState == .securityError {
            stateStore.recordFailure(
                code: status.presenceState == .securityError ? "connection_security_error" : "connection_disconnected",
                message: status.lastError ?? "Mac connection is not available for sync.",
                at: now
            )
            return nil
        }

        isSyncing = true
        defer { isSyncing = false }

        do {
            let localInventory = inventoryBuilder.build(
                deviceID: snapshot.deviceID,
                deviceName: UIDevice.current.name,
                lastKnownPeerRevision: stateStore.state.lastPeerInventoryHash,
                generatedAt: now
            )
            let peerResponse = try await client.fetchLocalNetworkSyncInventory(settings: snapshot, localInventory: localInventory)
            guard peerResponse.ok, let peerInventory = peerResponse.inventory else {
                throw SecureMacUploadError.serverRejected(peerResponse.error ?? "sync_inventory_missing")
            }

            let plan = diffPlanner.plan(
                local: localInventory,
                peer: peerInventory,
                lastSuccessfulSyncAt: stateStore.state.lastSuccessfulSyncAt
            )
            stateStore.recordAttempt(
                peerDeviceID: peerInventory.device.deviceID,
                localInventoryHash: localInventory.inventoryHash,
                peerInventoryHash: peerInventory.inventoryHash,
                pendingUploadCount: plan.uploadMetadataActions.count + plan.uploadRecordingAudioActions.count + plan.uploadArtifactActions.count,
                pendingDownloadCount: plan.downloadMetadataActions.count + plan.downloadArtifactActions.count,
                at: now
            )

            try applyPeerRecordingStatuses(peerInventory: peerInventory)
            try applyPeerMetadataIfNeeded(peerInventory: peerInventory, plan: plan, localDeviceID: snapshot.deviceID)
            try await uploadLocalMetadataIfNeeded(localInventory: localInventory, plan: plan, settings: snapshot)
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
            return plan
        } catch {
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
        let response = try await client.applyLocalNetworkSyncMetadata(settings: settings, manifest: manifest)
        guard response.ok else {
            throw SecureMacUploadError.serverRejected(response.error ?? "sync_apply_metadata_failed")
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
            let response = try await client.requestLocalNetworkSyncArtifact(settings: settings, artifactID: artifact.artifactID)
            try writeArtifactResponse(response)
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
            _ = await uploadCoordinator.uploadAndWait(
                metadata: metadata,
                settings: settings,
                recordingManager: recordingManager
            )
        }
    }

    private func writeArtifactResponse(_ response: LocalNetworkSyncArtifactResponse) throws {
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

        let rootURL = try audioFileStore.baseDirectory()
        let destinationURL = try LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: logicalPathToken)
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destinationURL, options: .atomic)
    }
}

@MainActor
final class LocalNetworkSyncScheduler {
    typealias TickHandler = @MainActor (String) async -> Void

    private let interval: TimeInterval
    private let tickHandler: TickHandler
    private var periodicTask: Task<Void, Never>?
    private(set) var isTickInFlight = false

    init(interval: TimeInterval = 60, tickHandler: @escaping TickHandler) {
        self.interval = interval
        self.tickHandler = tickHandler
    }

    convenience init(engine: LocalNetworkSyncEngine, interval: TimeInterval = 60) {
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
    private let scheduler: LocalNetworkSyncScheduler
    private let heartbeatMonitor: LocalNetworkHeartbeatMonitor
    private var isActive = false
    private var uploadLedgerObserver: NSObjectProtocol?
    private var pairingObserver: NSObjectProtocol?

    init(interval: TimeInterval = 60) {
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
        startPairedServicesIfPossible()
    }

    func requestUploadLedgerTick() {
        connectionStore.refreshFromStorage()
        guard isActive, connectionStore.snapshot.isPaired else {
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

    private func startPairedServicesIfPossible() {
        guard connectionStore.snapshot.isPaired else {
            heartbeatMonitor.suspend()
            scheduler.stop()
            return
        }

        heartbeatMonitor.startForegroundMonitoring()
        scheduler.startPeriodicTicks()
        Task {
            await scheduler.foregroundTick()
        }
    }

    func suspend() {
        isActive = false
        heartbeatMonitor.suspend()
        scheduler.stop()
    }
}
