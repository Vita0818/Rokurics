//
//  SyncCore.swift
//  RokuricsShared
//
//  Created by Codex on 2026/5/30.
//

import CryptoKit
import Foundation

enum SyncObjectAvailability: String, Codable, Equatable, Sendable {
    case local
    case missing
    case availableOnPeer
    case transferring
    case complete
}

enum SyncTransferState: String, Codable, Equatable, Sendable {
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
}

enum SyncTransferDirection: String, Codable, Equatable, Sendable {
    case upload
    case download
}

struct SyncObject: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID }

    var objectID: String
    var objectKind: String
    var ownerID: String
    var displayTitle: String?
    var fileName: String?
    var logicalName: String?
    var sha256: String?
    var size: Int64?
    var updatedAt: Date
    var tombstone: Bool
    var deleted: Bool
    var sourceDeviceID: String?
    var logicalPathToken: String?
    var availability: SyncObjectAvailability
    var transferState: SyncTransferState?
    var transferProgress: Double?
    var conflictStatus: String?
    var autoDownloadAllowed: Bool
    var metadata: [String: String]
}

struct SyncDirectory: Codable, Equatable, Identifiable, Sendable {
    var id: String { directoryID }

    var directoryID: String
    var parentID: String?
    var pathComponents: [String]
    var name: String
    var colorToken: String?
    var updatedAt: Date
    var tombstone: Bool
    var revisionHash: String?
}

struct SyncInventory: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var sourceDeviceID: String
    var sourcePlatform: String
    var generatedAt: Date
    var inventoryRevision: String
    var inventoryHash: String
    var lastKnownPeerRevision: String?
    var objects: [SyncObject]
    var directories: [SyncDirectory]
    var deviceSummary: [String: String]

    static func make(
        schemaVersion: Int = currentSchemaVersion,
        sourceDeviceID: String,
        sourcePlatform: String,
        generatedAt: Date = Date(),
        inventoryRevision: String,
        lastKnownPeerRevision: String? = nil,
        objects: [SyncObject],
        directories: [SyncDirectory] = [],
        deviceSummary: [String: String] = [:]
    ) -> SyncInventory {
        let sortedObjects = objects.sorted { $0.objectID.localizedStandardCompare($1.objectID) == .orderedAscending }
        let sortedDirectories = directories.sorted { $0.directoryID.localizedStandardCompare($1.directoryID) == .orderedAscending }
        var inventory = SyncInventory(
            schemaVersion: schemaVersion,
            sourceDeviceID: sourceDeviceID,
            sourcePlatform: sourcePlatform,
            generatedAt: generatedAt,
            inventoryRevision: inventoryRevision,
            inventoryHash: "",
            lastKnownPeerRevision: lastKnownPeerRevision,
            objects: sortedObjects,
            directories: sortedDirectories,
            deviceSummary: deviceSummary
        )
        inventory.inventoryHash = inventory.computedInventoryHash()
        return inventory
    }

    func computedInventoryHash() -> String {
        let payload = SyncInventoryChecksumPayload(
            schemaVersion: schemaVersion,
            sourceDeviceID: sourceDeviceID,
            sourcePlatform: sourcePlatform,
            generatedAt: generatedAt,
            inventoryRevision: inventoryRevision,
            lastKnownPeerRevision: lastKnownPeerRevision,
            objects: objects,
            directories: directories,
            deviceSummary: deviceSummary
        )
        let data = (try? Self.encoder.encode(payload)) ?? Data()
        return Data(SHA256.hash(data: data)).hexString
    }

    var hasValidInventoryHash: Bool {
        inventoryHash == computedInventoryHash()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private struct SyncInventoryChecksumPayload: Encodable {
    var schemaVersion: Int
    var sourceDeviceID: String
    var sourcePlatform: String
    var generatedAt: Date
    var inventoryRevision: String
    var lastKnownPeerRevision: String?
    var objects: [SyncObject]
    var directories: [SyncDirectory]
    var deviceSummary: [String: String]
}

enum SyncDiffActionKind: String, Codable, Equatable, Sendable {
    case noOp
    case uploadObject
    case downloadObject
    case updateMetadata
    case applyTombstone
    case conflict
    case useExistingUploadPath
    case skip
}

struct SyncDiffAction: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var kind: SyncDiffActionKind
    var objectID: String
    var objectKind: String
    var ownerID: String
    var direction: SyncTransferDirection?
    var reason: String
}

struct SyncDiffPlan: Codable, Equatable, Sendable {
    var actions: [SyncDiffAction] = []

    var uploadObjectActions: [SyncDiffAction] { actions.filter { $0.kind == .uploadObject } }
    var downloadObjectActions: [SyncDiffAction] { actions.filter { $0.kind == .downloadObject } }
    var metadataUpdateActions: [SyncDiffAction] { actions.filter { $0.kind == .updateMetadata } }
    var tombstoneActions: [SyncDiffAction] { actions.filter { $0.kind == .applyTombstone } }
    var conflictActions: [SyncDiffAction] { actions.filter { $0.kind == .conflict } }
    var existingUploadPathActions: [SyncDiffAction] { actions.filter { $0.kind == .useExistingUploadPath } }
    var skippedActions: [SyncDiffAction] { actions.filter { $0.kind == .skip } }
    var noOps: [SyncDiffAction] { actions.filter { $0.kind == .noOp } }
}

struct SyncDiffPlanner: Sendable {
    func plan(
        local: SyncInventory,
        peer: SyncInventory,
        lastSuccessfulSyncAt: Date?
    ) -> SyncDiffPlan {
        let localByID = Dictionary(uniqueKeysWithValues: local.objects.map { ($0.objectID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.objects.map { ($0.objectID, $0) })
        var plan = SyncDiffPlan()

        for objectID in Set(localByID.keys).union(peerByID.keys).sorted() {
            let localObject = localByID[objectID]
            let peerObject = peerByID[objectID]
            compare(
                objectID: objectID,
                localObject: localObject,
                peerObject: peerObject,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                plan: &plan
            )
        }
        return plan
    }

    private func compare(
        objectID: String,
        localObject: SyncObject?,
        peerObject: SyncObject?,
        lastSuccessfulSyncAt: Date?,
        plan: inout SyncDiffPlan
    ) {
        switch (localObject, peerObject) {
        case let (.some(local), .some(peer)):
            if local.deletedOrTombstoned, peer.deletedOrTombstoned {
                plan.actions.append(action(.noOp, object: local, direction: nil, reason: "tombstone_equal"))
            } else if local.contentSignature == peer.contentSignature, local.deletedOrTombstoned == peer.deletedOrTombstoned {
                plan.actions.append(action(.noOp, object: local, direction: nil, reason: "checksum_equal"))
            } else if lastSuccessfulSyncAt.map({ local.updatedAt > $0 && peer.updatedAt > $0 }) == true {
                plan.actions.append(action(.conflict, object: local, direction: nil, reason: "both_changed_after_last_sync"))
            } else if peer.deletedOrTombstoned, peer.updatedAt >= local.updatedAt {
                plan.actions.append(action(.applyTombstone, object: peer, direction: .download, reason: "peer_tombstone_wins"))
            } else if local.deletedOrTombstoned, local.updatedAt >= peer.updatedAt {
                plan.actions.append(action(.applyTombstone, object: local, direction: .upload, reason: "local_tombstone_wins"))
            } else if local.updatedAt > peer.updatedAt {
                plan.actions.append(action(.uploadObject, object: local, direction: .upload, reason: "local_object_newer"))
            } else if peer.updatedAt > local.updatedAt {
                plan.actions.append(action(.downloadObject, object: peer, direction: .download, reason: "peer_object_newer"))
            } else if local.contentCompletenessScore > peer.contentCompletenessScore {
                plan.actions.append(action(.uploadObject, object: local, direction: .upload, reason: "local_object_more_complete"))
            } else if peer.contentCompletenessScore > local.contentCompletenessScore {
                plan.actions.append(action(.downloadObject, object: peer, direction: .download, reason: "peer_object_more_complete"))
            } else {
                plan.actions.append(action(.conflict, object: local, direction: nil, reason: "object_signature_conflict"))
            }
        case let (.some(local), .none):
            if local.deletedOrTombstoned {
                plan.actions.append(action(.skip, object: local, direction: nil, reason: "local_tombstone_without_peer"))
            } else {
                plan.actions.append(action(.uploadObject, object: local, direction: .upload, reason: "peer_missing_object"))
            }
        case let (.none, .some(peer)):
            if peer.deletedOrTombstoned {
                plan.actions.append(action(.skip, object: peer, direction: nil, reason: "peer_tombstone_without_local"))
            } else {
                plan.actions.append(action(.downloadObject, object: peer, direction: .download, reason: "local_missing_object"))
            }
        case (.none, .none):
            break
        }
    }

    private func action(
        _ kind: SyncDiffActionKind,
        object: SyncObject,
        direction: SyncTransferDirection?,
        reason: String
    ) -> SyncDiffAction {
        SyncDiffAction(
            id: "\(kind.rawValue):\(object.objectID):\(reason)",
            kind: kind,
            objectID: object.objectID,
            objectKind: object.objectKind,
            ownerID: object.ownerID,
            direction: direction,
            reason: reason
        )
    }
}

private extension SyncObject {
    var deletedOrTombstoned: Bool {
        deleted || tombstone
    }

    var contentSignature: String {
        [
            sha256 ?? "",
            size.map(String.init) ?? "",
            deletedOrTombstoned ? "deleted" : "active"
        ].joined(separator: "|")
    }

    var contentCompletenessScore: Int {
        var score = 0
        if sha256 != nil {
            score += 2
        }
        if size != nil {
            score += 1
        }
        if availability == .local || availability == .complete {
            score += 1
        }
        return score
    }
}

struct SyncTransferJob: Codable, Equatable, Identifiable, Sendable {
    var id: String { transferID }

    var transferID: String
    var objectID: String
    var objectKind: String
    var direction: SyncTransferDirection
    var peerDeviceID: String?
    var totalBytes: Int64?
    var transferredBytes: Int64
    var confirmedBytes: Int64
    var sha256: String?
    var chunkSize: Int?
    var nextOffset: Int64
    var state: SyncTransferState
    var lastAttemptAt: Date?
    var nextRetryAfter: Date?
    var errorCode: String?
    var errorMessage: String?
    var localTempToken: String?
}

struct SyncTransferProgress: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID }

    var objectID: String
    var state: SyncTransferState
    var fraction: Double?
    var transferredBytes: Int64?
    var totalBytes: Int64?
    var bytesPerSecond: Double?
    var displayText: String?
}

@MainActor
protocol SyncStorageAdapter {
    func buildDirectorySnapshot() throws -> [SyncDirectory]
    func buildObjectSnapshot() throws -> [SyncObject]
    func resolveLogicalPathToken(_ token: String, for object: SyncObject) throws -> URL
    func createPlaceholder(for object: SyncObject) throws
    func openReadStream(for object: SyncObject) throws -> InputStream
    func openWriteTemp(for object: SyncObject) throws -> URL
    func verifyChecksum(for object: SyncObject, at url: URL) throws -> Bool
    func atomicApply(tempURL: URL, for object: SyncObject) throws
    func markTransferState(_ state: SyncTransferState, for object: SyncObject) throws
    func markConflict(_ status: String, for object: SyncObject) throws
}
