//
//  StudyLibrarySyncModels.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/21.
//

import CryptoKit
import Foundation

extension Notification.Name {
    static let localNetworkStudyLibraryDidChange = Notification.Name("Rokurics.localNetworkStudyLibraryDidChange")
}

struct StudyLibrarySyncRuntimeConfiguration: Equatable, Sendable {
    var gitBackedSyncEnabled: Bool

    static let disabledReason = "Git-backed study sync is disabled"
    static let disabledStatusText = "同步已暂停"

    static let `default` = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false)
    static let disabled = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false)
    static let gitBackedEnabled = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: true)
}

enum DeviceConnectionLifecycleState: String, Codable, Equatable {
    case unpaired
    case offline
    case connecting
    case connected
}

enum ConnectionPresenceState: String, Codable, Equatable {
    case unknown
    case connecting
    case online
    case interrupted
    case stale
    case disconnected
    case securityError
}

enum ConnectionMonitoringMode: String, Codable, Equatable {
    case foregroundActive
    case suspended
    case disabled
}

struct DeviceConnectionStatus: Codable, Equatable, Identifiable {
    var id: String { deviceID }

    var deviceID: String
    var displayName: String
    var state: DeviceConnectionLifecycleState
    var lastSeenAt: Date?
    var lastHeartbeatAt: Date?
    var lastSyncAt: Date?
    var lastSyncStatus: String?
    var lastError: String?
    var presenceState: ConnectionPresenceState?
    var monitoringMode: ConnectionMonitoringMode?
    var lastHeartbeatSentAt: Date?
    var lastHeartbeatReceivedAt: Date?
    var lastSuccessfulHeartbeatAt: Date?
    var lastSignedRequestSucceededAt: Date?
    var missedHeartbeatCount: Int?
    var consecutiveFailureCount: Int?
    var latencyMilliseconds: Double?
    var lastErrorCode: String?
    var connectionStatusRevision: Int?

    static func unpaired(displayName: String = "iPhone") -> DeviceConnectionStatus {
        DeviceConnectionStatus(
            deviceID: "unpaired",
            displayName: displayName,
            state: .unpaired,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil,
            presenceState: .unknown,
            monitoringMode: .disabled,
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
}

struct ConnectionPresenceSnapshot: Equatable {
    var state: ConnectionPresenceState
    var lifecycleState: DeviceConnectionLifecycleState
    var lastEvidenceAt: Date?
    var lastSeenAt: Date?
    var interruptedSeconds: Int
    var statusText: String
    var recentOnlineText: String
    var isOnline: Bool
    var isSuspended: Bool
}

extension DeviceConnectionStatus {
    func presenceSnapshot(
        now: Date = Date(),
        staleAfter: TimeInterval = 5,
        disconnectedAfter: TimeInterval = 10,
        missedHeartbeatLimit: Int = 3
    ) -> ConnectionPresenceSnapshot {
        if state == .unpaired {
            return ConnectionPresenceSnapshot(
                state: .unknown,
                lifecycleState: .unpaired,
                lastEvidenceAt: nil,
                lastSeenAt: nil,
                interruptedSeconds: 0,
                statusText: "未配对",
                recentOnlineText: "暂无",
                isOnline: false,
                isSuspended: monitoringMode == .disabled
            )
        }

        let evidenceAt = latestPresenceEvidenceAt
        let ageSeconds = evidenceAt.map { max(0, Int(now.timeIntervalSince($0).rounded(.down))) } ?? 0

        if presenceState == .securityError {
            return ConnectionPresenceSnapshot(
                state: .securityError,
                lifecycleState: .offline,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: ageSeconds,
                statusText: "安全校验失败",
                recentOnlineText: evidenceAt == nil ? "暂无" : "连接中断 \(max(1, ageSeconds)) 秒",
                isOnline: false,
                isSuspended: false
            )
        }

        if monitoringMode == .suspended {
            return ConnectionPresenceSnapshot(
                state: .stale,
                lifecycleState: .offline,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: ageSeconds,
                statusText: "前台监测已暂停",
                recentOnlineText: evidenceAt == nil ? "暂无" : "连接中断 \(max(1, ageSeconds)) 秒",
                isOnline: false,
                isSuspended: true
            )
        }

        guard let evidenceAt else {
            let resolvedState: ConnectionPresenceState = presenceState == .connecting ? .connecting : (presenceState ?? .unknown)
            return ConnectionPresenceSnapshot(
                state: resolvedState,
                lifecycleState: resolvedState == .connecting ? .connecting : .offline,
                lastEvidenceAt: nil,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: 0,
                statusText: resolvedState == .connecting ? "正在连接" : "已配对但离线",
                recentOnlineText: "暂无",
                isOnline: false,
                isSuspended: false
            )
        }

        let missedCount = missedHeartbeatCount ?? 0
        let resolvedState: ConnectionPresenceState
        if missedCount >= missedHeartbeatLimit || now.timeIntervalSince(evidenceAt) > disconnectedAfter {
            resolvedState = .disconnected
        } else if now.timeIntervalSince(evidenceAt) > staleAfter {
            resolvedState = .interrupted
        } else {
            resolvedState = .online
        }

        switch resolvedState {
        case .online:
            return ConnectionPresenceSnapshot(
                state: .online,
                lifecycleState: .connected,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: 0,
                statusText: "已连接",
                recentOnlineText: Self.secondsAgoText(ageSeconds),
                isOnline: true,
                isSuspended: false
            )
        case .interrupted, .disconnected:
            let interruptedSeconds = max(1, ageSeconds)
            return ConnectionPresenceSnapshot(
                state: resolvedState,
                lifecycleState: .offline,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: interruptedSeconds,
                statusText: "连接中断 \(interruptedSeconds) 秒",
                recentOnlineText: "连接中断 \(interruptedSeconds) 秒",
                isOnline: false,
                isSuspended: false
            )
        default:
            return ConnectionPresenceSnapshot(
                state: resolvedState,
                lifecycleState: state,
                lastEvidenceAt: evidenceAt,
                lastSeenAt: lastSeenAt,
                interruptedSeconds: ageSeconds,
                statusText: state == .connecting ? "正在连接" : "已配对但离线",
                recentOnlineText: Self.secondsAgoText(ageSeconds),
                isOnline: false,
                isSuspended: false
            )
        }
    }

    var latestPresenceEvidenceAt: Date? {
        [
            lastSuccessfulHeartbeatAt,
            lastSignedRequestSucceededAt,
            lastSeenAt,
            lastHeartbeatAt
        ]
        .compactMap { $0 }
        .max()
    }

    private static func secondsAgoText(_ seconds: Int) -> String {
        seconds <= 0 ? "刚刚" : "\(seconds) 秒前"
    }
}

enum LocalNetworkSyncControlPlaneState: String, Codable, Equatable {
    case idle
    case syncStartSignalSent
    case syncStartSignalReceived
    case syncStartAcked
    case inventoryExchanging
    case planningTransfers
    case transferJobsCreated
    case transferring
    case pausedDisconnected
    case resuming
    case completed
    case failed
    case cancelled
}

enum LocalNetworkTransferState: String, Codable, Equatable {
    case pending
    case transferring
    case paused
    case pausedDisconnected
    case retryPending
    case resuming
    case verifying
    case complete
    case failed
    case conflict

    var isVisibleInActionArea: Bool {
        switch self {
        case .pending, .transferring, .paused, .pausedDisconnected, .retryPending, .resuming, .verifying, .failed, .conflict:
            return true
        case .complete:
            return false
        }
    }
}

struct LocalNetworkTransferProgress: Codable, Equatable, Identifiable {
    var id: String { objectID }

    var objectID: String
    var objectKind: String
    var state: LocalNetworkTransferState
    var progressFraction: Double?
    var receivedBytes: Int64?
    var totalBytes: Int64?
    var sourceDeviceID: String?
    var statusText: String?

    var isVisibleInActionArea: Bool {
        state.isVisibleInActionArea
    }
}

extension StudyItemMetadata {
    var localNetworkTransferProgress: LocalNetworkTransferProgress? {
        guard let stateRaw = customProperties[Self.transferStateKey],
              let state = LocalNetworkTransferState(rawValue: stateRaw),
              let objectID = customProperties[Self.transferObjectIDKey],
              let objectKind = customProperties[Self.transferObjectKindKey] else {
            return nil
        }

        return LocalNetworkTransferProgress(
            objectID: objectID,
            objectKind: objectKind,
            state: state,
            progressFraction: customProperties[Self.transferProgressKey].flatMap(Double.init),
            receivedBytes: customProperties[Self.transferReceivedBytesKey].flatMap(Int64.init),
            totalBytes: customProperties[Self.transferTotalBytesKey].flatMap(Int64.init),
            sourceDeviceID: customProperties[Self.transferSourceDeviceIDKey],
            statusText: customProperties[Self.transferStatusTextKey]
        )
    }

    func withLocalNetworkTransferProgress(_ progress: LocalNetworkTransferProgress?) -> StudyItemMetadata {
        var copy = self
        Self.transferKeys.forEach { copy.customProperties.removeValue(forKey: $0) }

        guard let progress, progress.state != .complete else {
            return copy
        }

        copy.customProperties[Self.transferStateKey] = progress.state.rawValue
        copy.customProperties[Self.transferObjectIDKey] = progress.objectID
        copy.customProperties[Self.transferObjectKindKey] = progress.objectKind
        if let progressFraction = progress.progressFraction {
            copy.customProperties[Self.transferProgressKey] = String(progressFraction)
        }
        if let receivedBytes = progress.receivedBytes {
            copy.customProperties[Self.transferReceivedBytesKey] = String(receivedBytes)
        }
        if let totalBytes = progress.totalBytes {
            copy.customProperties[Self.transferTotalBytesKey] = String(totalBytes)
        }
        if let sourceDeviceID = progress.sourceDeviceID {
            copy.customProperties[Self.transferSourceDeviceIDKey] = sourceDeviceID
        }
        if let statusText = progress.statusText {
            copy.customProperties[Self.transferStatusTextKey] = statusText
        }
        return copy
    }

    private static var transferKeys: [String] {
        [
            transferStateKey,
            transferObjectIDKey,
            transferObjectKindKey,
            transferProgressKey,
            transferReceivedBytesKey,
            transferTotalBytesKey,
            transferSourceDeviceIDKey,
            transferStatusTextKey
        ]
    }

    private static let transferStateKey = "localNetworkTransferState"
    private static let transferObjectIDKey = "localNetworkTransferObjectID"
    private static let transferObjectKindKey = "localNetworkTransferObjectKind"
    private static let transferProgressKey = "localNetworkTransferProgressFraction"
    private static let transferReceivedBytesKey = "localNetworkTransferReceivedBytes"
    private static let transferTotalBytesKey = "localNetworkTransferTotalBytes"
    private static let transferSourceDeviceIDKey = "localNetworkTransferSourceDeviceID"
    private static let transferStatusTextKey = "localNetworkTransferStatusText"
}

struct StudyLibrarySyncState: Codable, Equatable {
    var deviceID: String
    var lastPulledAt: Date?
    var lastPushedAt: Date?
    var lastSuccessfulSyncAt: Date?
    var lastRemoteManifestHash: String?
    var lastKnownRemoteCommitID: String?
    var pendingLocalChanges: Int
    var pendingUploads: Int
    var failedChanges: Int
    var lastError: String?
    var activeSyncRunID: String?
    var syncControlPlaneState: LocalNetworkSyncControlPlaneState?
    var syncControlPlaneUpdatedAt: Date?

    init(
        deviceID: String = "",
        lastPulledAt: Date? = nil,
        lastPushedAt: Date? = nil,
        lastSuccessfulSyncAt: Date? = nil,
        lastRemoteManifestHash: String? = nil,
        lastKnownRemoteCommitID: String? = nil,
        pendingLocalChanges: Int = 0,
        pendingUploads: Int = 0,
        failedChanges: Int = 0,
        lastError: String? = nil,
        activeSyncRunID: String? = nil,
        syncControlPlaneState: LocalNetworkSyncControlPlaneState? = nil,
        syncControlPlaneUpdatedAt: Date? = nil
    ) {
        self.deviceID = deviceID
        self.lastPulledAt = lastPulledAt
        self.lastPushedAt = lastPushedAt
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.lastRemoteManifestHash = lastRemoteManifestHash
        self.lastKnownRemoteCommitID = lastKnownRemoteCommitID
        self.pendingLocalChanges = pendingLocalChanges
        self.pendingUploads = pendingUploads
        self.failedChanges = failedChanges
        self.lastError = lastError
        self.activeSyncRunID = activeSyncRunID
        self.syncControlPlaneState = syncControlPlaneState
        self.syncControlPlaneUpdatedAt = syncControlPlaneUpdatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case lastPulledAt
        case lastPushedAt
        case lastSuccessfulSyncAt
        case lastRemoteManifestHash
        case lastKnownRemoteCommitID
        case pendingLocalChanges
        case pendingUploads
        case failedChanges
        case lastError
        case activeSyncRunID
        case syncControlPlaneState
        case syncControlPlaneUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? ""
        lastPulledAt = try container.decodeIfPresent(Date.self, forKey: .lastPulledAt)
        lastPushedAt = try container.decodeIfPresent(Date.self, forKey: .lastPushedAt)
        lastSuccessfulSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncAt)
        lastRemoteManifestHash = try container.decodeIfPresent(String.self, forKey: .lastRemoteManifestHash)
        lastKnownRemoteCommitID = try container.decodeIfPresent(String.self, forKey: .lastKnownRemoteCommitID)
        pendingLocalChanges = try container.decodeIfPresent(Int.self, forKey: .pendingLocalChanges) ?? 0
        pendingUploads = try container.decodeIfPresent(Int.self, forKey: .pendingUploads) ?? 0
        failedChanges = try container.decodeIfPresent(Int.self, forKey: .failedChanges) ?? 0
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        activeSyncRunID = try container.decodeIfPresent(String.self, forKey: .activeSyncRunID)
        syncControlPlaneState = try container.decodeIfPresent(LocalNetworkSyncControlPlaneState.self, forKey: .syncControlPlaneState)
        syncControlPlaneUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .syncControlPlaneUpdatedAt)
    }
}

enum StudyLibrarySyncEntityKind: String, Codable, Equatable {
    case item
    case folder
}

enum StudyLibrarySyncOperation: String, Codable, Equatable {
    case upsert
    case delete
    case trash
    case restore
    case deleteMetadataOnly
}

enum PendingRecordingUploadStatus: String, Codable, Equatable {
    case pending
    case uploading
    case uploaded
    case failed
}

struct PendingRecordingUpload: Codable, Equatable, Identifiable {
    var id: String
    var itemID: StudyItemID
    var recordingID: String
    var localAudioRelativePath: String
    var targetDeviceID: String
    var status: PendingRecordingUploadStatus
    var createdAt: Date
    var updatedAt: Date
    var lastAttemptAt: Date?
    var retryCount: Int
    var lastError: String?

    init(
        id: String? = nil,
        itemID: StudyItemID,
        recordingID: String,
        localAudioRelativePath: String,
        targetDeviceID: String,
        status: PendingRecordingUploadStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id ?? "\(itemID):\(recordingID)"
        self.itemID = itemID
        self.recordingID = recordingID
        self.localAudioRelativePath = localAudioRelativePath
        self.targetDeviceID = targetDeviceID
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastAttemptAt = lastAttemptAt
        self.retryCount = retryCount
        self.lastError = lastError
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case itemID
        case recordingID
        case localAudioRelativePath
        case targetDeviceID
        case status
        case createdAt
        case updatedAt
        case lastAttemptAt
        case retryCount
        case lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decodeIfPresent(StudyItemID.self, forKey: .itemID) ?? ""
        recordingID = try container.decodeIfPresent(String.self, forKey: .recordingID) ?? itemID
        localAudioRelativePath = try container.decodeIfPresent(String.self, forKey: .localAudioRelativePath) ?? ""
        targetDeviceID = try container.decodeIfPresent(String.self, forKey: .targetDeviceID) ?? ""
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "\(itemID):\(recordingID)"
        status = try container.decodeIfPresent(PendingRecordingUploadStatus.self, forKey: .status) ?? .pending
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        lastAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastAttemptAt)
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

struct StudyLibrarySyncTombstone: Codable, Equatable, Identifiable {
    var id: String
    var entityKind: StudyLibrarySyncEntityKind
    var entityID: String
    var operation: StudyLibrarySyncOperation
    var updatedAt: Date
    var modifiedByDeviceID: String?
}

struct StudyLibrarySyncChange: Codable, Equatable, Identifiable {
    var id: String
    var entityKind: StudyLibrarySyncEntityKind
    var entityID: String
    var operation: StudyLibrarySyncOperation
    var updatedAt: Date
    var modifiedByDeviceID: String?
    var itemPayload: StudyItemMetadata?
    var folderPayload: StudyFolderMetadata?
}

struct StudyLibrarySyncManifest: Codable, Equatable {
    var deviceID: String
    var generatedAt: Date
    var libraryVersion: Int
    var items: [StudyItemMetadata]
    var folders: [StudyFolderMetadata]
    var tombstones: [StudyLibrarySyncTombstone]
    var pendingUploads: [PendingRecordingUpload]
    var baseCommitID: String?
    var commitID: String?
    var localManifestHash: String?
    var checksum: String

    static func make(
        deviceID: String,
        generatedAt: Date = Date(),
        libraryVersion: Int = 1,
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata],
        tombstones: [StudyLibrarySyncTombstone] = [],
        pendingUploads: [PendingRecordingUpload] = [],
        baseCommitID: String? = nil,
        commitID: String? = nil,
        localManifestHash: String? = nil
    ) -> StudyLibrarySyncManifest {
        var manifest = StudyLibrarySyncManifest(
            deviceID: deviceID,
            generatedAt: generatedAt,
            libraryVersion: libraryVersion,
            items: items.sorted { $0.itemID.localizedStandardCompare($1.itemID) == .orderedAscending },
            folders: folders.sorted { $0.folderID.localizedStandardCompare($1.folderID) == .orderedAscending },
            tombstones: tombstones.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending },
            pendingUploads: pendingUploads.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending },
            baseCommitID: baseCommitID,
            commitID: commitID,
            localManifestHash: localManifestHash,
            checksum: ""
        )
        manifest.checksum = manifest.computedChecksum()
        return manifest
    }

    func computedChecksum() -> String {
        let payload = StudyLibrarySyncChecksumPayload(
            deviceID: deviceID,
            generatedAt: generatedAt,
            libraryVersion: libraryVersion,
            items: items,
            folders: folders,
            tombstones: tombstones,
            pendingUploads: pendingUploads
        )
        let data = (try? Self.checksumEncoder.encode(payload)) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }

    var hasValidChecksum: Bool {
        checksum == computedChecksum() || checksum == legacyComputedChecksum()
    }

    var summaryText: String {
        let uploadText = pendingUploads.isEmpty ? nil : "\(pendingUploads.count) 个待上传"
        return (["\(items.count) 项", "\(folders.count) 个文件夹"] + [uploadText].compactMap { $0 })
            .joined(separator: " · ")
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case generatedAt
        case libraryVersion
        case items
        case folders
        case tombstones
        case pendingUploads
        case baseCommitID
        case commitID
        case localManifestHash
        case checksum
    }

    init(
        deviceID: String,
        generatedAt: Date,
        libraryVersion: Int,
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata],
        tombstones: [StudyLibrarySyncTombstone],
        pendingUploads: [PendingRecordingUpload],
        baseCommitID: String? = nil,
        commitID: String? = nil,
        localManifestHash: String? = nil,
        checksum: String
    ) {
        self.deviceID = deviceID
        self.generatedAt = generatedAt
        self.libraryVersion = libraryVersion
        self.items = items
        self.folders = folders
        self.tombstones = tombstones
        self.pendingUploads = pendingUploads
        self.baseCommitID = baseCommitID
        self.commitID = commitID
        self.localManifestHash = localManifestHash
        self.checksum = checksum
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        generatedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        libraryVersion = try container.decodeIfPresent(Int.self, forKey: .libraryVersion) ?? 1
        items = try container.decodeIfPresent([StudyItemMetadata].self, forKey: .items) ?? []
        folders = try container.decodeIfPresent([StudyFolderMetadata].self, forKey: .folders) ?? []
        tombstones = try container.decodeIfPresent([StudyLibrarySyncTombstone].self, forKey: .tombstones) ?? []
        pendingUploads = try container.decodeIfPresent([PendingRecordingUpload].self, forKey: .pendingUploads) ?? []
        baseCommitID = try container.decodeIfPresent(String.self, forKey: .baseCommitID)
        commitID = try container.decodeIfPresent(String.self, forKey: .commitID)
        localManifestHash = try container.decodeIfPresent(String.self, forKey: .localManifestHash)
        checksum = try container.decodeIfPresent(String.self, forKey: .checksum) ?? ""
    }

    private static let checksumEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private func legacyComputedChecksum() -> String {
        let payload = StudyLibrarySyncLegacyChecksumPayload(
            deviceID: deviceID,
            generatedAt: generatedAt,
            libraryVersion: libraryVersion,
            items: items,
            folders: folders,
            tombstones: tombstones
        )
        let data = (try? Self.checksumEncoder.encode(payload)) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }
}

private struct StudyLibrarySyncChecksumPayload: Encodable {
    var deviceID: String
    var generatedAt: Date
    var libraryVersion: Int
    var items: [StudyItemMetadata]
    var folders: [StudyFolderMetadata]
    var tombstones: [StudyLibrarySyncTombstone]
    var pendingUploads: [PendingRecordingUpload]
}

private struct StudyLibrarySyncLegacyChecksumPayload: Encodable {
    var deviceID: String
    var generatedAt: Date
    var libraryVersion: Int
    var items: [StudyItemMetadata]
    var folders: [StudyFolderMetadata]
    var tombstones: [StudyLibrarySyncTombstone]
}

struct StudyLibrarySyncApplyResult: Codable, Equatable {
    var appliedItemCount: Int = 0
    var appliedFolderCount: Int = 0
    var tombstoneCount: Int = 0
    var conflictCount: Int = 0
    var skippedOlderCount: Int = 0
    var failedChanges: Int = 0

    var summaryText: String {
        if failedChanges > 0 {
            return "同步失败 \(failedChanges) 项"
        }
        if appliedItemCount == 0, appliedFolderCount == 0, tombstoneCount == 0, conflictCount == 0 {
            return "已是最新"
        }

        var parts: [String] = []
        if appliedItemCount > 0 {
            parts.append("\(appliedItemCount) 项")
        }
        if appliedFolderCount > 0 {
            parts.append("\(appliedFolderCount) 个文件夹")
        }
        if tombstoneCount > 0 {
            parts.append("\(tombstoneCount) 个废纸篓状态")
        }
        if conflictCount > 0 {
            parts.append("\(conflictCount) 个冲突已保留")
        }
        return parts.joined(separator: " · ")
    }
}

struct StudyLibrarySyncStatusSummary: Codable, Equatable {
    var lastSyncAt: Date?
    var statusText: String?
    var pendingLocalChanges: Int
    var pendingUploads: Int

    init(lastSyncAt: Date?, statusText: String?, pendingLocalChanges: Int, pendingUploads: Int = 0) {
        self.lastSyncAt = lastSyncAt
        self.statusText = statusText
        self.pendingLocalChanges = pendingLocalChanges
        self.pendingUploads = pendingUploads
    }

    private enum CodingKeys: String, CodingKey {
        case lastSyncAt
        case statusText
        case pendingLocalChanges
        case pendingUploads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncAt)
        statusText = try container.decodeIfPresent(String.self, forKey: .statusText)
        pendingLocalChanges = try container.decodeIfPresent(Int.self, forKey: .pendingLocalChanges) ?? 0
        pendingUploads = try container.decodeIfPresent(Int.self, forKey: .pendingUploads) ?? 0
    }
}

struct DeviceStatusRequest: Codable, Equatable {
    var displayName: String
    var clientState: String
    var generatedAt: Date
    var syncSummary: StudyLibrarySyncStatusSummary?
}

struct DeviceStatusResponse: Codable, Equatable {
    var ok: Bool
    var status: DeviceConnectionStatus?
    var syncState: StudyLibrarySyncState?
    var error: String?
}

struct ConnectionHeartbeatRequest: Codable, Equatable {
    var deviceID: String
    var deviceName: String
    var platform: LocalNetworkSyncPlatform
    var appInstanceID: String?
    var sequenceNumber: UInt64
    var sentAt: Date
    var lastKnownPeerStatusRevision: Int?
}

struct ConnectionHeartbeatResponse: Codable, Equatable {
    var ok: Bool
    var disposition: String
    var peerDeviceID: String
    var serverTime: Date
    var receivedSequenceNumber: UInt64
    var connectionStatusRevision: Int
    var minimumSuggestedInterval: TimeInterval?
    var syncRequested: Bool?
    var syncStartSignal: LocalNetworkSyncStartSignal? = nil
    var status: DeviceConnectionStatus?
    var error: String?
}

struct LocalNetworkSyncStartSignal: Codable, Equatable {
    var syncRunID: String
    var initiatorDeviceID: String
    var initiatorPlatform: LocalNetworkSyncPlatform
    var requestedAt: Date
    var reason: String
}

struct LocalNetworkSyncStartRequest: Codable, Equatable {
    var syncRunID: String
    var deviceID: String
    var platform: LocalNetworkSyncPlatform
    var requestedAt: Date
    var reason: String
}

struct LocalNetworkSyncStartResponse: Codable, Equatable {
    var ok: Bool
    var syncRunID: String?
    var peerDeviceID: String?
    var ackAt: Date?
    var disposition: String?
    var error: String?
}

struct LocalNetworkSyncStartAckRequest: Codable, Equatable {
    var syncRunID: String
    var deviceID: String
    var platform: LocalNetworkSyncPlatform
    var acknowledgedAt: Date
    var disposition: String
}

struct LocalNetworkSyncStartAckResponse: Codable, Equatable {
    var ok: Bool
    var syncRunID: String?
    var peerDeviceID: String?
    var ackReceivedAt: Date?
    var error: String?
}

struct StudyLibrarySyncManifestRequest: Codable, Equatable {
    var manifest: StudyLibrarySyncManifest
}

struct StudyLibrarySyncManifestResponse: Codable, Equatable {
    var ok: Bool
    var manifest: StudyLibrarySyncManifest?
    var syncState: StudyLibrarySyncState?
    var deviceStatus: DeviceConnectionStatus?
    var applyResult: StudyLibrarySyncApplyResult?
    var baseCommitID: String?
    var newCommitID: String?
    var remoteChanges: [StudyLibrarySyncChange]?
    var rejectedChanges: [StudyLibrarySyncChange]?
    var error: String?
}

extension StudyLibrarySyncManifest {
    var changesApproximation: [StudyLibrarySyncChange] {
        let itemChanges = items.map { item in
            StudyLibrarySyncChange(
                id: "item:\(item.itemID)",
                entityKind: .item,
                entityID: item.itemID,
                operation: item.isTrashed ? .trash : .upsert,
                updatedAt: item.updatedAt,
                modifiedByDeviceID: item.modifiedByDeviceID ?? deviceID,
                itemPayload: item,
                folderPayload: nil
            )
        }
        let folderChanges = folders.map { folder in
            StudyLibrarySyncChange(
                id: "folder:\(folder.folderID)",
                entityKind: .folder,
                entityID: folder.folderID,
                operation: folder.isTrashed ? .trash : .upsert,
                updatedAt: folder.updatedAt,
                modifiedByDeviceID: folder.modifiedByDeviceID ?? deviceID,
                itemPayload: nil,
                folderPayload: folder
            )
        }
        let tombstoneChanges = tombstones.map { tombstone in
            StudyLibrarySyncChange(
                id: tombstone.id,
                entityKind: tombstone.entityKind,
                entityID: tombstone.entityID,
                operation: tombstone.operation,
                updatedAt: tombstone.updatedAt,
                modifiedByDeviceID: tombstone.modifiedByDeviceID ?? deviceID,
                itemPayload: nil,
                folderPayload: nil
            )
        }
        return itemChanges + folderChanges + tombstoneChanges
    }
}

extension StudyItemMetadata {
    func syncSanitized(modifiedByDeviceID fallbackDeviceID: String? = nil) -> StudyItemMetadata {
        var copy = self
        copy.modifiedByDeviceID = copy.modifiedByDeviceID ?? fallbackDeviceID
        copy.customProperties = StudyLibrarySyncSanitizer.filteredCustomProperties(customProperties)
        return copy
    }
}

extension StudyFolderMetadata {
    func syncSanitized(modifiedByDeviceID fallbackDeviceID: String? = nil) -> StudyFolderMetadata {
        var copy = self
        copy.modifiedByDeviceID = copy.modifiedByDeviceID ?? fallbackDeviceID
        copy.customProperties = StudyLibrarySyncSanitizer.filteredCustomProperties(customProperties)
        copy.itemIDs = StudyItemMetadata.uniqueIDs(itemIDs)
        copy.childFolderIDs = StudyItemMetadata.uniqueIDs(childFolderIDs)
        return copy
    }
}

enum StudyLibrarySyncSanitizer {
    static func filteredCustomProperties(_ properties: [String: String]) -> [String: String] {
        properties.filter { key, _ in
            let normalized = key.lowercased()
            return !normalized.contains("apikey")
                && !normalized.contains("api_key")
                && !normalized.contains("secret")
                && !normalized.contains("hmac")
                && !normalized.contains("pairing")
                && !normalized.contains("rawresponse")
                && !normalized.contains("raw_response")
                && !normalized.contains("providerresponse")
                && !normalized.contains("provider_response")
                && !normalized.contains("fulltranscript")
                && !normalized.contains("full_transcript")
                && !normalized.contains("fullnote")
                && !normalized.contains("full_note")
                && !normalized.contains("prompt")
                && !normalized.contains("debug")
                && !normalized.contains("rawjson")
                && !normalized.contains("raw_json")
                && !normalized.contains("localnetworktransfer")
        }
    }
}

enum LocalNetworkSyncPlatform: String, Codable, Equatable, Sendable {
    case iPhone
    case Mac
}

enum LocalNetworkSyncArtifactKind: String, Codable, Equatable, Sendable {
    case metadataJSON
    case receiveJSON
    case transcriptMarkdown
    case transcriptJSON
    case noteMarkdown
    case noteJSON
    case summaryMarkdown
    case summaryJSON
    case audio

    var isAutoDownloadAllowed: Bool {
        switch self {
        case .metadataJSON, .receiveJSON, .transcriptMarkdown, .transcriptJSON, .noteMarkdown, .noteJSON, .summaryMarkdown, .summaryJSON:
            return true
        case .audio:
            return false
        }
    }
}

enum LocalNetworkSyncArtifactAvailability: String, Codable, Equatable, Sendable {
    case local
    case availableOnPeer
    case missing
    case transferring
    case complete
}

enum LocalNetworkSyncObjectKind: String, Codable, Equatable, Sendable {
    case recordingAudio
    case recordingMetadata
    case receiveRecord
    case transcriptMarkdown
    case transcriptJSON
    case noteMarkdown
    case noteJSON
    case summaryMarkdown
    case summaryJSON
    case studyItem
    case studyFolder
}

struct LocalNetworkSyncObjectEntry: Codable, Equatable, Identifiable {
    var id: String { objectID }

    var objectID: String
    var objectKind: LocalNetworkSyncObjectKind
    var ownerID: String?
    var displayTitle: String?
    var fileName: String?
    var logicalName: String?
    var sha256: String?
    var size: Int64?
    var updatedAt: Date
    var deleted: Bool
    var tombstone: Bool?
    var sourceDeviceID: String?
    var logicalPathToken: String?
    var availability: LocalNetworkSyncArtifactAvailability
    var transferState: LocalNetworkTransferState?
    var transferProgress: Double?
    var conflictStatus: String?
    var autoDownloadAllowed: Bool?
}

struct LocalNetworkSyncInventory: Codable, Equatable {
    static let appSchemaVersion = 1

    var schemaVersion: Int
    var sourceDeviceID: String
    var sourcePlatform: LocalNetworkSyncPlatform
    var generatedAt: Date
    var inventoryRevision: String
    var lastKnownPeerRevision: String?
    var device: LocalNetworkSyncDeviceSection
    var recordings: [LocalNetworkSyncRecordingEntry]
    var folders: [LocalNetworkSyncFolderEntry]
    var studyItems: [LocalNetworkSyncStudyItemEntry]
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var objects: [LocalNetworkSyncObjectEntry]
    var studyManifest: StudyLibrarySyncManifest?

    var inventoryHash: String {
        let payload = LocalNetworkSyncInventoryChecksumPayload(
            schemaVersion: schemaVersion,
            sourceDeviceID: sourceDeviceID,
            sourcePlatform: sourcePlatform,
            generatedAt: generatedAt,
            inventoryRevision: inventoryRevision,
            lastKnownPeerRevision: lastKnownPeerRevision,
            device: device,
            recordings: recordings,
            folders: folders,
            studyItems: studyItems,
            artifacts: artifacts,
            objects: objects
        )
        let data = (try? Self.encoder.encode(payload)) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }

    static func make(
        device: LocalNetworkSyncDeviceSection,
        recordings: [LocalNetworkSyncRecordingEntry] = [],
        folders: [LocalNetworkSyncFolderEntry] = [],
        studyItems: [LocalNetworkSyncStudyItemEntry] = [],
        artifacts: [LocalNetworkSyncArtifactEntry] = [],
        objects: [LocalNetworkSyncObjectEntry] = [],
        studyManifest: StudyLibrarySyncManifest? = nil
    ) -> LocalNetworkSyncInventory {
        let inventoryRevision = LocalNetworkSyncMetadataHash.hash(device)
        let sortedRecordings = recordings.sorted { $0.recordingID.localizedStandardCompare($1.recordingID) == .orderedAscending }
        let sortedFolders = folders.sorted { $0.folderID.localizedStandardCompare($1.folderID) == .orderedAscending }
        let sortedStudyItems = studyItems.sorted { $0.itemID.localizedStandardCompare($1.itemID) == .orderedAscending }
        let sortedArtifacts = artifacts.sorted { $0.artifactID.localizedStandardCompare($1.artifactID) == .orderedAscending }
        let sortedObjects = (objects.isEmpty
            ? makeObjectEntries(recordings: sortedRecordings, folders: sortedFolders, studyItems: sortedStudyItems, artifacts: sortedArtifacts)
            : objects
        ).sorted { $0.objectID.localizedStandardCompare($1.objectID) == .orderedAscending }
        return LocalNetworkSyncInventory(
            schemaVersion: appSchemaVersion,
            sourceDeviceID: device.deviceID,
            sourcePlatform: device.platform,
            generatedAt: device.generatedAt,
            inventoryRevision: inventoryRevision,
            lastKnownPeerRevision: device.lastKnownPeerRevision,
            device: device,
            recordings: sortedRecordings,
            folders: sortedFolders,
            studyItems: sortedStudyItems,
            artifacts: sortedArtifacts,
            objects: sortedObjects,
            studyManifest: studyManifest
        )
    }

    init(
        schemaVersion: Int,
        sourceDeviceID: String,
        sourcePlatform: LocalNetworkSyncPlatform,
        generatedAt: Date,
        inventoryRevision: String,
        lastKnownPeerRevision: String?,
        device: LocalNetworkSyncDeviceSection,
        recordings: [LocalNetworkSyncRecordingEntry],
        folders: [LocalNetworkSyncFolderEntry],
        studyItems: [LocalNetworkSyncStudyItemEntry],
        artifacts: [LocalNetworkSyncArtifactEntry],
        objects: [LocalNetworkSyncObjectEntry],
        studyManifest: StudyLibrarySyncManifest?
    ) {
        self.schemaVersion = schemaVersion
        self.sourceDeviceID = sourceDeviceID
        self.sourcePlatform = sourcePlatform
        self.generatedAt = generatedAt
        self.inventoryRevision = inventoryRevision
        self.lastKnownPeerRevision = lastKnownPeerRevision
        self.device = device
        self.recordings = recordings
        self.folders = folders
        self.studyItems = studyItems
        self.artifacts = artifacts
        self.objects = objects
        self.studyManifest = studyManifest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.appSchemaVersion
        sourceDeviceID = try container.decode(String.self, forKey: .sourceDeviceID)
        sourcePlatform = try container.decode(LocalNetworkSyncPlatform.self, forKey: .sourcePlatform)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        inventoryRevision = try container.decode(String.self, forKey: .inventoryRevision)
        lastKnownPeerRevision = try container.decodeIfPresent(String.self, forKey: .lastKnownPeerRevision)
        device = try container.decode(LocalNetworkSyncDeviceSection.self, forKey: .device)
        recordings = try container.decodeIfPresent([LocalNetworkSyncRecordingEntry].self, forKey: .recordings) ?? []
        folders = try container.decodeIfPresent([LocalNetworkSyncFolderEntry].self, forKey: .folders) ?? []
        studyItems = try container.decodeIfPresent([LocalNetworkSyncStudyItemEntry].self, forKey: .studyItems) ?? []
        artifacts = try container.decodeIfPresent([LocalNetworkSyncArtifactEntry].self, forKey: .artifacts) ?? []
        objects = try container.decodeIfPresent([LocalNetworkSyncObjectEntry].self, forKey: .objects)
            ?? Self.makeObjectEntries(recordings: recordings, folders: folders, studyItems: studyItems, artifacts: artifacts)
        studyManifest = try container.decodeIfPresent(StudyLibrarySyncManifest.self, forKey: .studyManifest)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sourceDeviceID
        case sourcePlatform
        case generatedAt
        case inventoryRevision
        case lastKnownPeerRevision
        case device
        case recordings
        case folders
        case studyItems
        case artifacts
        case objects
        case studyManifest
    }

    private static func makeObjectEntries(
        recordings: [LocalNetworkSyncRecordingEntry],
        folders: [LocalNetworkSyncFolderEntry],
        studyItems: [LocalNetworkSyncStudyItemEntry],
        artifacts: [LocalNetworkSyncArtifactEntry]
    ) -> [LocalNetworkSyncObjectEntry] {
        let recordingObjects = recordings.map { recording in
            LocalNetworkSyncObjectEntry(
                objectID: "recordingMetadata:\(recording.recordingID)",
                objectKind: .recordingMetadata,
                ownerID: recording.recordingID,
                displayTitle: recording.title,
                fileName: nil,
                logicalName: recording.recordingID,
                sha256: recording.metadataHash,
                size: nil,
                updatedAt: recording.updatedAt,
                deleted: recording.deleted,
                tombstone: recording.tombstone,
                sourceDeviceID: recording.sourceDeviceID,
                logicalPathToken: nil,
                availability: .local,
                transferState: nil,
                transferProgress: nil,
                conflictStatus: nil,
                autoDownloadAllowed: true
            )
        }
        let recordingAudioObjects = recordings.compactMap { recording -> LocalNetworkSyncObjectEntry? in
            guard recording.audioAvailable || recording.audioSize != nil || recording.audioAvailability != nil else {
                return nil
            }
            return LocalNetworkSyncObjectEntry(
                objectID: "recordingAudio:\(recording.recordingID)",
                objectKind: .recordingAudio,
                ownerID: recording.recordingID,
                displayTitle: recording.title,
                fileName: nil,
                logicalName: recording.recordingID,
                sha256: recording.audioChecksum,
                size: recording.audioSize,
                updatedAt: recording.updatedAt,
                deleted: recording.deleted,
                tombstone: recording.tombstone,
                sourceDeviceID: recording.sourceDeviceID,
                logicalPathToken: nil,
                availability: recording.audioAvailability ?? (recording.audioAvailable ? .local : .missing),
                transferState: nil,
                transferProgress: nil,
                conflictStatus: nil,
                autoDownloadAllowed: false
            )
        }
        let folderObjects = folders.map { folder in
            LocalNetworkSyncObjectEntry(
                objectID: "studyFolder:\(folder.folderID)",
                objectKind: .studyFolder,
                ownerID: folder.folderID,
                displayTitle: folder.name,
                fileName: nil,
                logicalName: folder.path ?? folder.folderID,
                sha256: folder.revisionHash,
                size: nil,
                updatedAt: folder.updatedAt,
                deleted: folder.deleted,
                tombstone: folder.deleted,
                sourceDeviceID: nil,
                logicalPathToken: folder.path,
                availability: .local,
                transferState: nil,
                transferProgress: nil,
                conflictStatus: nil,
                autoDownloadAllowed: true
            )
        }
        let studyItemObjects = studyItems.map { item in
            LocalNetworkSyncObjectEntry(
                objectID: "studyItem:\(item.itemID)",
                objectKind: .studyItem,
                ownerID: item.recordingID ?? item.itemID,
                displayTitle: item.title,
                fileName: nil,
                logicalName: item.path ?? item.itemID,
                sha256: item.revisionHash,
                size: nil,
                updatedAt: item.updatedAt,
                deleted: item.deleted,
                tombstone: item.deleted,
                sourceDeviceID: nil,
                logicalPathToken: item.path,
                availability: .local,
                transferState: nil,
                transferProgress: nil,
                conflictStatus: item.conflictStatus,
                autoDownloadAllowed: true
            )
        }
        let artifactObjects = artifacts.map { artifact in
            LocalNetworkSyncObjectEntry(
                objectID: artifact.artifactID,
                objectKind: objectKind(for: artifact.kind),
                ownerID: artifact.ownerID,
                displayTitle: artifact.ownerID,
                fileName: fileName(artifact.logicalPathToken),
                logicalName: artifact.logicalPathToken,
                sha256: artifact.checksum,
                size: artifact.size,
                updatedAt: artifact.updatedAt,
                deleted: false,
                tombstone: false,
                sourceDeviceID: nil,
                logicalPathToken: artifact.logicalPathToken,
                availability: artifact.availability,
                transferState: nil,
                transferProgress: nil,
                conflictStatus: nil,
                autoDownloadAllowed: artifact.autoDownloadAllowed ?? artifact.kind.isAutoDownloadAllowed
            )
        }
        return recordingObjects + recordingAudioObjects + folderObjects + studyItemObjects + artifactObjects
    }

    private static func objectKind(for artifactKind: LocalNetworkSyncArtifactKind) -> LocalNetworkSyncObjectKind {
        switch artifactKind {
        case .metadataJSON:
            return .recordingMetadata
        case .receiveJSON:
            return .receiveRecord
        case .transcriptMarkdown:
            return .transcriptMarkdown
        case .transcriptJSON:
            return .transcriptJSON
        case .noteMarkdown:
            return .noteMarkdown
        case .noteJSON:
            return .noteJSON
        case .summaryMarkdown:
            return .summaryMarkdown
        case .summaryJSON:
            return .summaryJSON
        case .audio:
            return .recordingAudio
        }
    }

    private static func fileName(_ logicalPathToken: String) -> String? {
        logicalPathToken.split(separator: "/").last.map(String.init)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private struct LocalNetworkSyncInventoryChecksumPayload: Encodable {
    var schemaVersion: Int
    var sourceDeviceID: String
    var sourcePlatform: LocalNetworkSyncPlatform
    var generatedAt: Date
    var inventoryRevision: String
    var lastKnownPeerRevision: String?
    var device: LocalNetworkSyncDeviceSection
    var recordings: [LocalNetworkSyncRecordingEntry]
    var folders: [LocalNetworkSyncFolderEntry]
    var studyItems: [LocalNetworkSyncStudyItemEntry]
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var objects: [LocalNetworkSyncObjectEntry]
}

extension LocalNetworkSyncInventory {
    var syncCoreInventory: SyncInventory {
        SyncInventory.make(
            schemaVersion: schemaVersion,
            sourceDeviceID: sourceDeviceID,
            sourcePlatform: sourcePlatform.rawValue,
            generatedAt: generatedAt,
            inventoryRevision: inventoryRevision,
            lastKnownPeerRevision: lastKnownPeerRevision,
            objects: objects.map(\.syncObject),
            directories: folders.map(\.syncDirectory),
            deviceSummary: [
                "deviceName": device.deviceName,
                "appSchemaVersion": String(device.appSchemaVersion)
            ]
        )
    }
}

extension LocalNetworkSyncObjectEntry {
    var syncObject: SyncObject {
        SyncObject(
            objectID: objectID,
            objectKind: objectKind.rawValue,
            ownerID: ownerID ?? inferredOwnerID,
            displayTitle: displayTitle,
            fileName: fileName,
            logicalName: logicalName,
            sha256: sha256,
            size: size,
            updatedAt: updatedAt,
            tombstone: tombstone ?? deleted,
            deleted: deleted,
            sourceDeviceID: sourceDeviceID,
            logicalPathToken: logicalPathToken,
            availability: SyncObjectAvailability(rawValue: availability.rawValue) ?? .missing,
            transferState: transferState.flatMap { SyncTransferState(rawValue: $0.rawValue) },
            transferProgress: transferProgress,
            conflictStatus: conflictStatus,
            autoDownloadAllowed: autoDownloadAllowed ?? true,
            metadata: [:]
        )
    }

    private var inferredOwnerID: String {
        if let logicalName, !logicalName.isEmpty {
            return logicalName
        }
        return objectID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? objectID
    }
}

extension LocalNetworkSyncFolderEntry {
    var syncDirectory: SyncDirectory {
        SyncDirectory(
            directoryID: folderID,
            parentID: parentID,
            pathComponents: path?.split(separator: "/").map(String.init) ?? [name],
            name: name,
            colorToken: colorToken,
            updatedAt: updatedAt,
            tombstone: deleted,
            revisionHash: revisionHash
        )
    }
}

struct LocalNetworkSyncDeviceSection: Codable, Equatable {
    var deviceID: String
    var deviceName: String
    var platform: LocalNetworkSyncPlatform
    var generatedAt: Date
    var lastKnownPeerRevision: String?
    var appSchemaVersion: Int
    var appInstanceID: String? = nil
}

struct LocalNetworkSyncRecordingEntry: Codable, Equatable, Identifiable {
    var id: String { recordingID }

    var recordingID: String
    var metadataHash: String?
    var audioAvailable: Bool
    var audioChecksum: String?
    var audioSize: Int64?
    var uploadLedgerState: String?
    var receiveStatus: String?
    var processingStatus: String?
    var updatedAt: Date
    var deleted: Bool
    var title: String? = nil
    var createdAt: Date? = nil
    var tombstone: Bool? = nil
    var audioAvailability: LocalNetworkSyncArtifactAvailability? = nil
    var uploadStatus: String? = nil
    var transcriptionStatus: String? = nil
    var noteStatus: String? = nil
    var sourceDeviceID: String? = nil
    var artifactRefs: [String]? = nil
}

struct LocalNetworkSyncFolderEntry: Codable, Equatable, Identifiable {
    var id: String { folderID }

    var folderID: String
    var parentID: String?
    var path: String?
    var name: String
    var colorToken: String?
    var updatedAt: Date
    var revisionHash: String
    var deleted: Bool
}

struct LocalNetworkSyncStudyItemEntry: Codable, Equatable, Identifiable {
    var id: String { itemID }

    var itemID: String
    var kind: StudyItemKind
    var title: String
    var folderIDs: [StudyFolderID]
    var recordingID: String?
    var updatedAt: Date
    var revisionHash: String
    var deleted: Bool
    var path: String? = nil
    var conflictStatus: String? = nil
}

struct LocalNetworkSyncArtifactEntry: Codable, Equatable, Identifiable {
    var id: String { artifactID }

    var artifactID: String
    var kind: LocalNetworkSyncArtifactKind
    var ownerID: String
    var checksum: String?
    var size: Int64?
    var updatedAt: Date
    var availability: LocalNetworkSyncArtifactAvailability
    var logicalPathToken: String
    var localAvailability: LocalNetworkSyncArtifactAvailability? = nil
    var peerAvailability: LocalNetworkSyncArtifactAvailability? = nil
    var autoDownloadAllowed: Bool? = nil
}

struct LocalNetworkSyncInventoryRequest: Codable, Equatable {
    var deviceID: String
    var generatedAt: Date
    var localInventoryHash: String?
    var syncRunID: String? = nil
}

struct LocalNetworkSyncInventoryResponse: Codable, Equatable {
    var ok: Bool
    var inventory: LocalNetworkSyncInventory?
    var error: String?
}

struct LocalNetworkSyncArtifactRequest: Codable, Equatable {
    var artifactID: String
    var offset: Int64? = nil
    var length: Int? = nil
    var syncRunID: String? = nil
}

struct LocalNetworkSyncArtifactResponse: Codable, Equatable {
    var ok: Bool
    var artifactID: String?
    var kind: LocalNetworkSyncArtifactKind?
    var checksum: String?
    var size: Int64?
    var logicalPathToken: String?
    var dataBase64: String?
    var offset: Int64? = nil
    var totalSize: Int64? = nil
    var isFinalChunk: Bool? = nil
    var error: String?
}

struct LocalNetworkSyncArtifactPutRequest: Codable, Equatable {
    var artifactID: String
    var kind: LocalNetworkSyncArtifactKind
    var ownerID: String
    var checksum: String
    var size: Int64
    var updatedAt: Date
    var logicalPathToken: String
    var dataBase64: String
    var offset: Int64? = nil
    var chunkSize: Int? = nil
    var totalSize: Int64? = nil
    var isFinalChunk: Bool? = nil
    var syncRunID: String? = nil
}

struct LocalNetworkSyncArtifactPutResponse: Codable, Equatable {
    var ok: Bool
    var artifactID: String?
    var disposition: String?
    var checksum: String?
    var size: Int64?
    var confirmedBytes: Int64? = nil
    var error: String?
}

struct LocalNetworkSyncArtifactStatusRequest: Codable, Equatable {
    var artifactID: String
    var kind: LocalNetworkSyncArtifactKind? = nil
    var ownerID: String? = nil
    var logicalPathToken: String? = nil
    var checksum: String? = nil
    var size: Int64? = nil
    var syncRunID: String? = nil
}

struct LocalNetworkSyncArtifactStatusResponse: Codable, Equatable {
    var ok: Bool
    var artifactID: String?
    var checksum: String?
    var size: Int64?
    var confirmedBytes: Int64?
    var nextOffset: Int64?
    var state: LocalNetworkTransferState?
    var error: String?
}

enum LocalNetworkSyncDiffActionKind: String, Codable, Equatable {
    case uploadMetadata
    case uploadArtifact
    case downloadMetadata
    case downloadArtifact
    case uploadRecordingAudio
    case conflict
    case noOp
}

struct LocalNetworkSyncDiffAction: Codable, Equatable, Identifiable {
    var id: String
    var kind: LocalNetworkSyncDiffActionKind
    var entityKind: String
    var entityID: String
    var reason: String
}

struct LocalNetworkSyncDiffPlan: Codable, Equatable {
    var uploadMetadataActions: [LocalNetworkSyncDiffAction] = []
    var uploadArtifactActions: [LocalNetworkSyncDiffAction] = []
    var downloadMetadataActions: [LocalNetworkSyncDiffAction] = []
    var downloadArtifactActions: [LocalNetworkSyncDiffAction] = []
    var uploadRecordingAudioActions: [LocalNetworkSyncDiffAction] = []
    var conflictActions: [LocalNetworkSyncDiffAction] = []
    var noOps: [LocalNetworkSyncDiffAction] = []

    var existingUploadActions: [LocalNetworkSyncDiffAction] {
        uploadRecordingAudioActions
    }
}

struct LocalNetworkSyncDiffPlanner {
    func plan(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?
    ) -> LocalNetworkSyncDiffPlan {
        let corePlan = SyncDiffPlanner().plan(
            local: local.syncCoreInventory,
            peer: peer.syncCoreInventory,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt
        )
        var plan = makeCompatibilityPlan(from: corePlan)
        appendRecordingReceiveStatusNoOps(local: local, peer: peer, plan: &plan)
        return plan
    }

    private func makeCompatibilityPlan(from corePlan: SyncDiffPlan) -> LocalNetworkSyncDiffPlan {
        var plan = LocalNetworkSyncDiffPlan()
        for action in corePlan.actions {
            append(action, to: &plan)
        }
        return plan
    }

    private func append(_ action: SyncDiffAction, to plan: inout LocalNetworkSyncDiffPlan) {
        guard let objectKind = LocalNetworkSyncObjectKind(rawValue: action.objectKind) else {
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: "object", entityID: action.objectID, reason: "unknown_object_kind"))
            return
        }

        switch objectKind {
        case .recordingAudio:
            appendRecordingAudioAction(action, to: &plan)
        case .recordingMetadata:
            appendMetadataAction(action, entityKind: "recording", entityID: action.ownerID, to: &plan)
        case .studyFolder:
            appendMetadataAction(action, entityKind: "folder", entityID: action.ownerID, to: &plan)
        case .studyItem:
            appendMetadataAction(action, entityKind: "studyItem", entityID: action.ownerID, to: &plan)
        case .receiveRecord, .transcriptMarkdown, .transcriptJSON, .noteMarkdown, .noteJSON, .summaryMarkdown, .summaryJSON:
            appendArtifactAction(action, to: &plan)
        }
    }

    private func appendRecordingAudioAction(_ action: SyncDiffAction, to plan: inout LocalNetworkSyncDiffPlan) {
        switch action.kind {
        case .uploadObject:
            plan.uploadRecordingAudioActions.append(legacyAction(.uploadRecordingAudio, action: action, entityKind: "recording", entityID: action.ownerID, reason: "peer_missing_audio_use_existing_upload"))
        case .downloadObject:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: isArtifactID(action.objectID) ? "artifact" : "recording", entityID: isArtifactID(action.objectID) ? action.objectID : action.ownerID, reason: "audio_auto_download_disabled"))
        case .conflict:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: isArtifactID(action.objectID) ? "artifact" : "recording", entityID: isArtifactID(action.objectID) ? action.objectID : action.ownerID, reason: "audio_uses_recording_upload"))
        case .noOp, .skip:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: isArtifactID(action.objectID) ? "artifact" : "recording", entityID: isArtifactID(action.objectID) ? action.objectID : action.ownerID, reason: action.reason))
        case .applyTombstone:
            appendMetadataAction(action, entityKind: "recording", entityID: action.ownerID, to: &plan)
        case .updateMetadata, .useExistingUploadPath:
            plan.uploadRecordingAudioActions.append(legacyAction(.uploadRecordingAudio, action: action, entityKind: "recording", entityID: action.ownerID, reason: "peer_missing_audio_use_existing_upload"))
        }
    }

    private func appendMetadataAction(
        _ action: SyncDiffAction,
        entityKind: String,
        entityID: String,
        to plan: inout LocalNetworkSyncDiffPlan
    ) {
        switch action.kind {
        case .uploadObject, .updateMetadata:
            plan.uploadMetadataActions.append(legacyAction(.uploadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: metadataReason(action.reason, entityKind: entityKind, uploading: true)))
        case .downloadObject:
            plan.downloadMetadataActions.append(legacyAction(.downloadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: metadataReason(action.reason, entityKind: entityKind, uploading: false)))
        case .applyTombstone:
            if action.direction == .upload {
                plan.uploadMetadataActions.append(legacyAction(.uploadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
            } else {
                plan.downloadMetadataActions.append(legacyAction(.downloadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
            }
        case .conflict:
            plan.conflictActions.append(legacyAction(.conflict, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
        case .noOp:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: entityKind, entityID: entityID, reason: entityKind == "recording" && action.reason == "checksum_equal" ? "metadata_equal" : action.reason))
        case .skip:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
        case .useExistingUploadPath:
            plan.uploadMetadataActions.append(legacyAction(.uploadMetadata, action: action, entityKind: entityKind, entityID: entityID, reason: action.reason))
        }
    }

    private func appendArtifactAction(_ action: SyncDiffAction, to plan: inout LocalNetworkSyncDiffPlan) {
        switch action.kind {
        case .uploadObject:
            plan.uploadArtifactActions.append(legacyAction(.uploadArtifact, action: action, entityKind: "artifact", entityID: action.objectID, reason: artifactReason(action.reason, uploading: true)))
        case .downloadObject:
            plan.downloadArtifactActions.append(legacyAction(.downloadArtifact, action: action, entityKind: "artifact", entityID: action.objectID, reason: artifactReason(action.reason, uploading: false)))
        case .conflict:
            plan.conflictActions.append(legacyAction(.conflict, action: action, entityKind: "artifact", entityID: action.objectID, reason: "artifact_checksum_conflict"))
        case .noOp:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: "artifact", entityID: action.objectID, reason: action.reason))
        case .skip:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: "artifact", entityID: action.objectID, reason: action.reason))
        case .applyTombstone, .updateMetadata, .useExistingUploadPath:
            plan.noOps.append(legacyAction(.noOp, action: action, entityKind: "artifact", entityID: action.objectID, reason: action.reason))
        }
    }

    private func appendRecordingReceiveStatusNoOps(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        let localByID = Dictionary(uniqueKeysWithValues: local.recordings.map { ($0.recordingID, $0) })
        for peerRecording in peer.recordings where peerRecording.audioAvailable == false {
            guard localByID[peerRecording.recordingID]?.audioAvailable == true,
                  !plan.uploadRecordingAudioActions.contains(where: { $0.entityID == peerRecording.recordingID }) else {
                continue
            }
            plan.uploadRecordingAudioActions.append(action(.uploadRecordingAudio, entityKind: "recording", entityID: peerRecording.recordingID, reason: "peer_missing_audio_use_existing_upload"))
        }
    }

    private func metadataReason(_ reason: String, entityKind: String, uploading: Bool) -> String {
        switch reason {
        case "peer_missing_object":
            return entityKind == "recording" ? "peer_missing_recording" : "peer_missing"
        case "local_missing_object":
            return entityKind == "recording" ? "local_missing_recording_metadata" : "local_missing"
        case "local_object_newer", "local_object_more_complete":
            return entityKind == "recording" ? "local_recording_newer" : "local_newer"
        case "peer_object_newer", "peer_object_more_complete":
            return entityKind == "recording" ? "peer_recording_newer" : "peer_newer"
        default:
            return reason
        }
    }

    private func artifactReason(_ reason: String, uploading: Bool) -> String {
        switch reason {
        case "peer_missing_object":
            return "peer_missing_artifact"
        case "local_missing_object":
            return "local_missing_artifact"
        case "local_object_newer", "local_object_more_complete":
            return "local_artifact_newer"
        case "peer_object_newer", "peer_object_more_complete":
            return "peer_artifact_newer"
        default:
            return reason
        }
    }

    private func legacyAction(
        _ kind: LocalNetworkSyncDiffActionKind,
        action: SyncDiffAction,
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

    private func isArtifactID(_ objectID: String) -> Bool {
        objectID.hasPrefix("artifact_")
    }

    private func compareRecordings(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        let localByID = Dictionary(uniqueKeysWithValues: local.recordings.map { ($0.recordingID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.recordings.map { ($0.recordingID, $0) })
        for recordingID in Set(localByID.keys).union(peerByID.keys).sorted() {
            let localRecording = localByID[recordingID]
            let peerRecording = peerByID[recordingID]
            switch (localRecording, peerRecording) {
            case let (.some(localRecording), .some(peerRecording)):
                if localRecording.metadataHash == peerRecording.metadataHash {
                    plan.noOps.append(action(.noOp, entityKind: "recording", entityID: recordingID, reason: "metadata_equal"))
                } else if lastSuccessfulSyncAt.map({ localRecording.updatedAt > $0 && peerRecording.updatedAt > $0 }) == true {
                    plan.conflictActions.append(action(.conflict, entityKind: "recording", entityID: recordingID, reason: "both_changed_after_last_sync"))
                } else if peerRecording.deleted, peerRecording.updatedAt >= localRecording.updatedAt {
                    plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: "recording", entityID: recordingID, reason: "peer_tombstone_wins"))
                } else if localRecording.deleted, localRecording.updatedAt >= peerRecording.updatedAt {
                    plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: "recording", entityID: recordingID, reason: "local_tombstone_wins"))
                } else if localRecording.updatedAt > peerRecording.updatedAt {
                    plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: "recording", entityID: recordingID, reason: "local_recording_newer"))
                } else {
                    plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: "recording", entityID: recordingID, reason: "peer_recording_newer"))
                }

                if localRecording.audioAvailable, !peerRecording.audioAvailable {
                    plan.uploadRecordingAudioActions.append(action(.uploadRecordingAudio, entityKind: "recording", entityID: recordingID, reason: "peer_missing_audio_use_existing_upload"))
                }
            case (.some, .none):
                plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: "recording", entityID: recordingID, reason: "peer_missing_recording"))
            case (.none, .some):
                plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: "recording", entityID: recordingID, reason: "local_missing_recording_metadata"))
            case (.none, .none):
                break
            }
        }
    }

    private func compareFolders(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        let localByID = Dictionary(uniqueKeysWithValues: local.folders.map { ($0.folderID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.folders.map { ($0.folderID, $0) })
        for folderID in Set(localByID.keys).union(peerByID.keys).sorted() {
            compareMetadataEntity(
                entityKind: "folder",
                entityID: folderID,
                localHash: localByID[folderID]?.revisionHash,
                peerHash: peerByID[folderID]?.revisionHash,
                localUpdatedAt: localByID[folderID]?.updatedAt,
                peerUpdatedAt: peerByID[folderID]?.updatedAt,
                localDeleted: localByID[folderID]?.deleted ?? false,
                peerDeleted: peerByID[folderID]?.deleted ?? false,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                plan: &plan
            )
        }
    }

    private func compareStudyItems(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        let localByID = Dictionary(uniqueKeysWithValues: local.studyItems.map { ($0.itemID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.studyItems.map { ($0.itemID, $0) })
        for itemID in Set(localByID.keys).union(peerByID.keys).sorted() {
            compareMetadataEntity(
                entityKind: "studyItem",
                entityID: itemID,
                localHash: localByID[itemID]?.revisionHash,
                peerHash: peerByID[itemID]?.revisionHash,
                localUpdatedAt: localByID[itemID]?.updatedAt,
                peerUpdatedAt: peerByID[itemID]?.updatedAt,
                localDeleted: localByID[itemID]?.deleted ?? false,
                peerDeleted: peerByID[itemID]?.deleted ?? false,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                plan: &plan
            )
        }
    }

    private func compareMetadataEntity(
        entityKind: String,
        entityID: String,
        localHash: String?,
        peerHash: String?,
        localUpdatedAt: Date?,
        peerUpdatedAt: Date?,
        localDeleted: Bool,
        peerDeleted: Bool,
        lastSuccessfulSyncAt: Date?,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        switch (localHash, peerHash) {
        case let (.some(localHash), .some(peerHash)) where localHash == peerHash:
            plan.noOps.append(action(.noOp, entityKind: entityKind, entityID: entityID, reason: "checksum_equal"))
        case (.some, .none):
            plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: entityKind, entityID: entityID, reason: "peer_missing"))
        case (.none, .some):
            plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: entityKind, entityID: entityID, reason: "local_missing"))
        case (.some, .some):
            let localDate = localUpdatedAt ?? .distantPast
            let peerDate = peerUpdatedAt ?? .distantPast
            let localChangedAfterSync = lastSuccessfulSyncAt.map { localDate > $0 } ?? false
            let peerChangedAfterSync = lastSuccessfulSyncAt.map { peerDate > $0 } ?? false

            if localChangedAfterSync, peerChangedAfterSync {
                plan.conflictActions.append(action(.conflict, entityKind: entityKind, entityID: entityID, reason: "both_changed_after_last_sync"))
            } else if peerDeleted, peerDate >= localDate {
                plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: entityKind, entityID: entityID, reason: "peer_tombstone_wins"))
            } else if localDeleted, localDate >= peerDate {
                plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: entityKind, entityID: entityID, reason: "local_tombstone_wins"))
            } else if peerDate > localDate {
                plan.downloadMetadataActions.append(action(.downloadMetadata, entityKind: entityKind, entityID: entityID, reason: "peer_newer"))
            } else {
                plan.uploadMetadataActions.append(action(.uploadMetadata, entityKind: entityKind, entityID: entityID, reason: "local_newer"))
            }
        case (.none, .none):
            break
        }
    }

    private func compareArtifacts(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        plan: inout LocalNetworkSyncDiffPlan
    ) {
        let localByID = Dictionary(uniqueKeysWithValues: local.artifacts.map { ($0.artifactID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.artifacts.map { ($0.artifactID, $0) })
        for artifactID in Set(localByID.keys).union(peerByID.keys).sorted() {
            let localArtifact = localByID[artifactID]
            let peerArtifact = peerByID[artifactID]
            switch (localArtifact, peerArtifact) {
            case let (.some(localArtifact), .some(peerArtifact)):
                if localArtifact.checksum == peerArtifact.checksum {
                    plan.noOps.append(action(.noOp, entityKind: "artifact", entityID: artifactID, reason: "checksum_equal"))
                } else if peerArtifact.updatedAt > localArtifact.updatedAt, peerArtifact.kind.isAutoDownloadAllowed {
                    plan.downloadArtifactActions.append(action(.downloadArtifact, entityKind: "artifact", entityID: artifactID, reason: "peer_artifact_newer"))
                } else if localArtifact.updatedAt > peerArtifact.updatedAt, localArtifact.kind != .audio {
                    plan.uploadArtifactActions.append(action(.uploadArtifact, entityKind: "artifact", entityID: artifactID, reason: "local_artifact_newer"))
                } else if localArtifact.kind == .audio || peerArtifact.kind == .audio {
                    plan.noOps.append(action(.noOp, entityKind: "artifact", entityID: artifactID, reason: "audio_uses_recording_upload"))
                } else {
                    plan.conflictActions.append(action(.conflict, entityKind: "artifact", entityID: artifactID, reason: "artifact_checksum_conflict"))
                }
            case let (.some(localArtifact), .none):
                if localArtifact.kind == .audio {
                    plan.noOps.append(action(.noOp, entityKind: "artifact", entityID: artifactID, reason: "audio_uses_recording_upload"))
                } else {
                    plan.uploadArtifactActions.append(action(.uploadArtifact, entityKind: "artifact", entityID: artifactID, reason: "peer_missing_artifact"))
                }
            case let (.none, .some(peerArtifact)):
                if peerArtifact.kind.isAutoDownloadAllowed {
                    plan.downloadArtifactActions.append(action(.downloadArtifact, entityKind: "artifact", entityID: artifactID, reason: "local_missing_artifact"))
                } else {
                    plan.noOps.append(action(.noOp, entityKind: "artifact", entityID: artifactID, reason: "audio_auto_download_disabled"))
                }
            case (.none, .none):
                break
            }
        }
    }

    private func action(
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
}

struct LocalNetworkSyncState: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var localDeviceID: String?
    var peerDeviceID: String?
    var lastSyncStartedAt: Date?
    var lastSyncCompletedAt: Date?
    var lastSyncAt: Date?
    var lastSuccessfulSyncAt: Date?
    var lastPeerDeviceID: String?
    var lastLocalInventoryHash: String?
    var lastPeerInventoryHash: String?
    var lastAppliedPeerRevision: String?
    var consecutiveFailureCount: Int
    var nextAllowedSyncAt: Date?
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var pendingUploadCount: Int
    var pendingDownloadCount: Int
    var lastPlanSummary: String?
    var lastConflictCount: Int?
    var activeTransfers: [LocalNetworkTransferProgress]
    var activeSyncRunID: String?
    var controlPlaneState: LocalNetworkSyncControlPlaneState?
    var lastControlPlaneUpdatedAt: Date?

    static var empty: LocalNetworkSyncState {
        LocalNetworkSyncState(
            version: currentVersion,
            localDeviceID: nil,
            peerDeviceID: nil,
            lastSyncStartedAt: nil,
            lastSyncCompletedAt: nil,
            lastSyncAt: nil,
            lastSuccessfulSyncAt: nil,
            lastPeerDeviceID: nil,
            lastLocalInventoryHash: nil,
            lastPeerInventoryHash: nil,
            lastAppliedPeerRevision: nil,
            consecutiveFailureCount: 0,
            nextAllowedSyncAt: nil,
            lastErrorCode: nil,
            lastErrorMessage: nil,
            pendingUploadCount: 0,
            pendingDownloadCount: 0,
            lastPlanSummary: nil,
            lastConflictCount: nil,
            activeTransfers: [],
            activeSyncRunID: nil,
            controlPlaneState: .idle,
            lastControlPlaneUpdatedAt: nil
        )
    }
}

enum LocalNetworkSyncArtifactValidationError: LocalizedError, Equatable {
    case invalidArtifactID
    case pathTraversal
    case absolutePath
    case unsafeResolvedPath
    case unsupportedArtifactKind
    case artifactNotFound

    var errorDescription: String? {
        switch self {
        case .invalidArtifactID:
            return "invalid_artifact_id"
        case .pathTraversal:
            return "artifact_path_traversal"
        case .absolutePath:
            return "artifact_absolute_path"
        case .unsafeResolvedPath:
            return "artifact_path_escape"
        case .unsupportedArtifactKind:
            return "unsupported_artifact_kind"
        case .artifactNotFound:
            return "artifact_not_found"
        }
    }
}

enum LocalNetworkSyncArtifactID {
    static func make(kind: LocalNetworkSyncArtifactKind, ownerID: String, logicalPathToken: String) -> String {
        let payload = "\(kind.rawValue)|\(ownerID)|\(logicalPathToken)"
        return "artifact_\(Data(SHA256.hash(data: Data(payload.utf8))).hexString)"
    }

    static func validate(_ artifactID: String) throws {
        guard artifactID.count == 73,
              artifactID.hasPrefix("artifact_"),
              artifactID.dropFirst("artifact_".count).allSatisfy(\.isHexDigit) else {
            throw LocalNetworkSyncArtifactValidationError.invalidArtifactID
        }
    }

    static func validateLogicalPathToken(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LocalNetworkSyncArtifactValidationError.artifactNotFound
        }
        guard !trimmed.hasPrefix("/") else {
            throw LocalNetworkSyncArtifactValidationError.absolutePath
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains("..") else {
            throw LocalNetworkSyncArtifactValidationError.pathTraversal
        }
    }

    static func validateLogicalPathToken(_ token: String, for kind: LocalNetworkSyncArtifactKind) throws {
        try validateLogicalPathToken(token)
        let lowercasedToken = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isValidForKind: Bool
        switch kind {
        case .metadataJSON:
            isValidForKind = lowercasedToken.hasSuffix("/metadata.json")
                || lowercasedToken == "metadata.json"
                || (lowercasedToken.hasPrefix("metadata/") && lowercasedToken.hasSuffix(".json"))
        case .receiveJSON:
            isValidForKind = lowercasedToken.hasSuffix("/receive.json") || lowercasedToken == "receive.json"
        case .transcriptMarkdown:
            isValidForKind = lowercasedToken.hasPrefix("transcripts/") && lowercasedToken.hasSuffix(".md")
        case .transcriptJSON:
            isValidForKind = lowercasedToken.hasPrefix("transcripts/") && lowercasedToken.hasSuffix(".json")
        case .noteMarkdown, .summaryMarkdown:
            isValidForKind = lowercasedToken.hasPrefix("notes/") && lowercasedToken.hasSuffix(".md")
        case .noteJSON, .summaryJSON:
            isValidForKind = lowercasedToken.hasPrefix("notes/") && lowercasedToken.hasSuffix(".json")
        case .audio:
            isValidForKind = false
        }
        guard isValidForKind else {
            throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
        }
    }
}

enum LocalNetworkSyncArtifactFileService {
    static func safeFileURL(rootURL: URL, logicalPathToken: String, fileManager: FileManager = .default) throws -> URL {
        try LocalNetworkSyncArtifactID.validateLogicalPathToken(logicalPathToken)
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let standardizedCandidate = root
            .appendingPathComponent(logicalPathToken, isDirectory: false)
            .standardizedFileURL
        let resolvedParent = standardizedCandidate
            .deletingLastPathComponent()
            .resolvingSymlinksInPath()
        let candidate = resolvedParent
            .appendingPathComponent(standardizedCandidate.lastPathComponent, isDirectory: false)
            .standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        guard candidate.path.hasPrefix(rootPath), resolvedParent.path.hasPrefix(rootPath) else {
            throw LocalNetworkSyncArtifactValidationError.unsafeResolvedPath
        }
        return candidate
    }

    static func safeFileURL(rootURL: URL, logicalPathToken: String, kind: LocalNetworkSyncArtifactKind, fileManager: FileManager = .default) throws -> URL {
        try LocalNetworkSyncArtifactID.validateLogicalPathToken(logicalPathToken, for: kind)
        return try safeFileURL(rootURL: rootURL, logicalPathToken: logicalPathToken, fileManager: fileManager)
    }

    static func metadata(for url: URL, fileManager: FileManager = .default) -> (size: Int64, updatedAt: Date)? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let updatedAt = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return (size, updatedAt)
    }

    static func sha256Hex(fileURL: URL, chunkByteCount: Int = 1024 * 1024) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkByteCount) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize()).hexString
    }
}

enum LocalNetworkSyncMetadataHash {
    static func hash<Value: Encodable>(_ value: Value) -> String {
        let data = (try? encoder.encode(value)) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
