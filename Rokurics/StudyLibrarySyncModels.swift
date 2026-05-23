//
//  StudyLibrarySyncModels.swift
//  Rokurics
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

    static func unpaired(displayName: String = "Mac") -> DeviceConnectionStatus {
        DeviceConnectionStatus(
            deviceID: "unpaired",
            displayName: displayName,
            state: .unpaired,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
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
