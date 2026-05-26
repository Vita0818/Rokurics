//
//  StudyLibrarySyncModels.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/21.
//

import CryptoKit
import Foundation

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
        lastError: String? = nil
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
    var status: DeviceConnectionStatus?
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
        }
    }
}

enum LocalNetworkSyncPlatform: String, Codable, Equatable, Sendable {
    case iPhone
    case Mac
}

enum LocalNetworkSyncArtifactKind: String, Codable, Equatable, Sendable {
    case transcriptMarkdown
    case transcriptJSON
    case noteMarkdown
    case noteJSON
    case audio

    var isAutoDownloadAllowed: Bool {
        switch self {
        case .transcriptMarkdown, .transcriptJSON, .noteMarkdown, .noteJSON:
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
}

struct LocalNetworkSyncInventory: Codable, Equatable {
    static let appSchemaVersion = 1

    var device: LocalNetworkSyncDeviceSection
    var recordings: [LocalNetworkSyncRecordingEntry]
    var folders: [LocalNetworkSyncFolderEntry]
    var studyItems: [LocalNetworkSyncStudyItemEntry]
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var studyManifest: StudyLibrarySyncManifest?

    var inventoryHash: String {
        let payload = LocalNetworkSyncInventoryChecksumPayload(
            device: device,
            recordings: recordings,
            folders: folders,
            studyItems: studyItems,
            artifacts: artifacts
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
        studyManifest: StudyLibrarySyncManifest? = nil
    ) -> LocalNetworkSyncInventory {
        LocalNetworkSyncInventory(
            device: device,
            recordings: recordings.sorted { $0.recordingID.localizedStandardCompare($1.recordingID) == .orderedAscending },
            folders: folders.sorted { $0.folderID.localizedStandardCompare($1.folderID) == .orderedAscending },
            studyItems: studyItems.sorted { $0.itemID.localizedStandardCompare($1.itemID) == .orderedAscending },
            artifacts: artifacts.sorted { $0.artifactID.localizedStandardCompare($1.artifactID) == .orderedAscending },
            studyManifest: studyManifest
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private struct LocalNetworkSyncInventoryChecksumPayload: Encodable {
    var device: LocalNetworkSyncDeviceSection
    var recordings: [LocalNetworkSyncRecordingEntry]
    var folders: [LocalNetworkSyncFolderEntry]
    var studyItems: [LocalNetworkSyncStudyItemEntry]
    var artifacts: [LocalNetworkSyncArtifactEntry]
}

struct LocalNetworkSyncDeviceSection: Codable, Equatable {
    var deviceID: String
    var deviceName: String
    var platform: LocalNetworkSyncPlatform
    var generatedAt: Date
    var lastKnownPeerRevision: String?
    var appSchemaVersion: Int
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
}

struct LocalNetworkSyncInventoryRequest: Codable, Equatable {
    var deviceID: String
    var generatedAt: Date
    var localInventoryHash: String?
}

struct LocalNetworkSyncInventoryResponse: Codable, Equatable {
    var ok: Bool
    var inventory: LocalNetworkSyncInventory?
    var error: String?
}

struct LocalNetworkSyncArtifactRequest: Codable, Equatable {
    var artifactID: String
}

struct LocalNetworkSyncArtifactResponse: Codable, Equatable {
    var ok: Bool
    var artifactID: String?
    var kind: LocalNetworkSyncArtifactKind?
    var checksum: String?
    var size: Int64?
    var logicalPathToken: String?
    var dataBase64: String?
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
}

struct LocalNetworkSyncDiffPlanner {
    func plan(
        local: LocalNetworkSyncInventory,
        peer: LocalNetworkSyncInventory,
        lastSuccessfulSyncAt: Date?
    ) -> LocalNetworkSyncDiffPlan {
        var plan = LocalNetworkSyncDiffPlan()
        compareRecordings(local: local, peer: peer, lastSuccessfulSyncAt: lastSuccessfulSyncAt, plan: &plan)
        compareFolders(local: local, peer: peer, lastSuccessfulSyncAt: lastSuccessfulSyncAt, plan: &plan)
        compareStudyItems(local: local, peer: peer, lastSuccessfulSyncAt: lastSuccessfulSyncAt, plan: &plan)
        compareArtifacts(local: local, peer: peer, plan: &plan)
        return plan
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

    static var empty: LocalNetworkSyncState {
        LocalNetworkSyncState(
            version: currentVersion,
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
            pendingDownloadCount: 0
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
