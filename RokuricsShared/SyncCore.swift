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

enum SyncReconciliationDifferenceKind: String, Codable, Equatable, Sendable {
    case onlyOnSource
    case contentModified
    case renameOnly
    case metadataModified
    case deleted
    case timestampTie
    case informationInsufficient
}

enum SyncReconciliationStatus: String, Codable, Equatable, Sendable {
    case pendingTransfer
    case pendingMetadataUpdate
    case queued
    case transferring
    case transferredAwaitingVerification
    case resolved
    case staleSourceVersion
    case deferred
}

struct SyncReconciliationCompletionProof: Codable, Equatable, Sendable {
    var transferID: String?
    var verifiedSHA256: String?
    var verifiedSize: Int64?
    var verifiedAt: Date
}

struct SyncReconciliationRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { recordID }

    var recordID: String
    var objectID: String
    var objectKind: String
    var ownerID: String
    var sourceDeviceID: String?
    var targetDeviceID: String?
    var sourceName: String?
    var targetName: String?
    var sourceSHA256: String?
    var targetSHA256: String?
    var sourceSize: Int64?
    var targetSize: Int64?
    var sourceModifiedAt: Date?
    var targetModifiedAt: Date?
    var differenceKind: SyncReconciliationDifferenceKind
    var requiresContentTransfer: Bool
    var requiresMetadataUpdate: Bool
    var status: SyncReconciliationStatus
    var discoveredAt: Date
    var syncRunID: String?
    var transferID: String?
    var completionProof: SyncReconciliationCompletionProof?
    var reason: String
}

struct SyncReconciliationPlan: Codable, Equatable, Sendable {
    var records: [SyncReconciliationRecord]
    var convergedObjectIDs: [String]
    var evaluatedObjectIDs: [String]

    var actionableRecords: [SyncReconciliationRecord] {
        records.filter { $0.status != .deferred }
    }

    var deferredRecords: [SyncReconciliationRecord] {
        records.filter { $0.status == .deferred }
    }
}

nonisolated struct SyncReconciliationPlanner: Sendable {
    func plan(
        local: SyncInventory,
        peer: SyncInventory,
        syncRunID: String? = nil,
        discoveredAt: Date = Date()
    ) -> SyncReconciliationPlan {
        let localByID = Dictionary(uniqueKeysWithValues: local.objects.map { ($0.objectID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.objects.map { ($0.objectID, $0) })
        let objectIDs = Set(localByID.keys).union(peerByID.keys).sorted()
        var records: [SyncReconciliationRecord] = []
        var converged: [String] = []

        for objectID in objectIDs {
            let result = reconcile(
                local: localByID[objectID],
                localDeviceID: local.sourceDeviceID,
                peer: peerByID[objectID],
                peerDeviceID: peer.sourceDeviceID,
                syncRunID: syncRunID,
                discoveredAt: discoveredAt
            )
            if let result {
                records.append(result)
            } else {
                converged.append(objectID)
            }
        }
        return SyncReconciliationPlan(
            records: records.sorted { $0.objectID < $1.objectID },
            convergedObjectIDs: converged,
            evaluatedObjectIDs: objectIDs
        )
    }

    private func reconcile(
        local: SyncObject?,
        localDeviceID: String,
        peer: SyncObject?,
        peerDeviceID: String,
        syncRunID: String?,
        discoveredAt: Date
    ) -> SyncReconciliationRecord? {
        switch (local, peer) {
        case let (.some(local), .none):
            guard !local.deletedOrTombstoned else { return nil }
            return makeRecord(source: local, sourceDeviceID: localDeviceID, target: nil, targetDeviceID: peerDeviceID, difference: .onlyOnSource, syncRunID: syncRunID, discoveredAt: discoveredAt, reason: "peer_missing_object")
        case let (.none, .some(peer)):
            guard !peer.deletedOrTombstoned else { return nil }
            return makeRecord(source: peer, sourceDeviceID: peerDeviceID, target: nil, targetDeviceID: localDeviceID, difference: .onlyOnSource, syncRunID: syncRunID, discoveredAt: discoveredAt, reason: "local_missing_object")
        case let (.some(local), .some(peer)):
            let localIsPresent = local.availability != .missing && !local.deletedOrTombstoned
            let peerIsPresent = peer.availability != .missing && !peer.deletedOrTombstoned
            if localIsPresent, !peerIsPresent, !peer.deletedOrTombstoned {
                return makeRecord(source: local, sourceDeviceID: localDeviceID, target: nil, targetDeviceID: peerDeviceID, difference: .onlyOnSource, syncRunID: syncRunID, discoveredAt: discoveredAt, reason: "peer_missing_object")
            }
            if peerIsPresent, !localIsPresent, !local.deletedOrTombstoned {
                return makeRecord(source: peer, sourceDeviceID: peerDeviceID, target: nil, targetDeviceID: localDeviceID, difference: .onlyOnSource, syncRunID: syncRunID, discoveredAt: discoveredAt, reason: "local_missing_object")
            }
            if !localIsPresent, !peerIsPresent, !local.deletedOrTombstoned, !peer.deletedOrTombstoned {
                return nil
            }
            let localProof = proof(for: local)
            let peerProof = proof(for: peer)
            let sameDeletionState = local.deletedOrTombstoned == peer.deletedOrTombstoned
            let sameName = businessName(for: local) == businessName(for: peer)

            if sameDeletionState, localProof.isSufficient, peerProof.isSufficient, localProof == peerProof {
                if sameName { return nil }
                return chooseNewer(local: local, localDeviceID: localDeviceID, peer: peer, peerDeviceID: peerDeviceID, difference: .renameOnly, syncRunID: syncRunID, discoveredAt: discoveredAt, tieReason: "rename_timestamp_tie")
            }

            if !localProof.isSufficient || !peerProof.isSufficient {
                return makeDeferred(local: local, localDeviceID: localDeviceID, peer: peer, peerDeviceID: peerDeviceID, difference: .informationInsufficient, syncRunID: syncRunID, discoveredAt: discoveredAt, reason: "hash_or_size_missing")
            }

            let difference: SyncReconciliationDifferenceKind
            if local.deletedOrTombstoned != peer.deletedOrTombstoned {
                difference = .deleted
            } else if isContentBearing(local.objectKind) {
                difference = .contentModified
            } else {
                difference = .metadataModified
            }
            return chooseNewer(local: local, localDeviceID: localDeviceID, peer: peer, peerDeviceID: peerDeviceID, difference: difference, syncRunID: syncRunID, discoveredAt: discoveredAt, tieReason: "different_versions_same_modified_at")
        case (.none, .none):
            return nil
        }
    }

    private func chooseNewer(
        local: SyncObject,
        localDeviceID: String,
        peer: SyncObject,
        peerDeviceID: String,
        difference: SyncReconciliationDifferenceKind,
        syncRunID: String?,
        discoveredAt: Date,
        tieReason: String
    ) -> SyncReconciliationRecord {
        let localTime = normalized(local.updatedAt)
        let peerTime = normalized(peer.updatedAt)
        if localTime > peerTime {
            return makeRecord(source: local, sourceDeviceID: localDeviceID, target: peer, targetDeviceID: peerDeviceID, difference: difference, syncRunID: syncRunID, discoveredAt: discoveredAt, reason: "latest_modified_at_wins")
        }
        if peerTime > localTime {
            return makeRecord(source: peer, sourceDeviceID: peerDeviceID, target: local, targetDeviceID: localDeviceID, difference: difference, syncRunID: syncRunID, discoveredAt: discoveredAt, reason: "latest_modified_at_wins")
        }
        return makeDeferred(local: local, localDeviceID: localDeviceID, peer: peer, peerDeviceID: peerDeviceID, difference: .timestampTie, syncRunID: syncRunID, discoveredAt: discoveredAt, reason: tieReason)
    }

    private func makeRecord(
        source: SyncObject,
        sourceDeviceID: String,
        target: SyncObject?,
        targetDeviceID: String,
        difference: SyncReconciliationDifferenceKind,
        syncRunID: String?,
        discoveredAt: Date,
        reason: String
    ) -> SyncReconciliationRecord {
        let content = isContentBearing(source.objectKind) && !source.deletedOrTombstoned && difference != .renameOnly
        let targetBusinessName = target.flatMap { businessName(for: $0) }
        let metadata = !content || businessName(for: source) != targetBusinessName
        let normalizedSourceDate = normalized(source.updatedAt)
        let normalizedTargetDate = target.map { normalized($0.updatedAt) }
        let identity = [
            source.objectID, sourceDeviceID, targetDeviceID, source.sha256 ?? "", source.size.map(String.init) ?? "",
            String(Int64(normalizedSourceDate.timeIntervalSince1970)), target?.sha256 ?? "", target?.size.map(String.init) ?? "",
            difference.rawValue
        ].joined(separator: "|")
        return SyncReconciliationRecord(
            recordID: Data(SHA256.hash(data: Data(identity.utf8))).hexString,
            objectID: source.objectID,
            objectKind: source.objectKind,
            ownerID: source.ownerID,
            sourceDeviceID: sourceDeviceID,
            targetDeviceID: targetDeviceID,
            sourceName: businessName(for: source),
            targetName: targetBusinessName,
            sourceSHA256: source.sha256,
            targetSHA256: target?.sha256,
            sourceSize: source.size,
            targetSize: target?.size,
            sourceModifiedAt: normalizedSourceDate,
            targetModifiedAt: normalizedTargetDate,
            differenceKind: source.deletedOrTombstoned ? .deleted : difference,
            requiresContentTransfer: content,
            requiresMetadataUpdate: metadata,
            status: content ? .pendingTransfer : .pendingMetadataUpdate,
            discoveredAt: discoveredAt,
            syncRunID: syncRunID,
            transferID: nil,
            completionProof: nil,
            reason: reason
        )
    }

    private func makeDeferred(
        local: SyncObject,
        localDeviceID: String,
        peer: SyncObject,
        peerDeviceID: String,
        difference: SyncReconciliationDifferenceKind,
        syncRunID: String?,
        discoveredAt: Date,
        reason: String
    ) -> SyncReconciliationRecord {
        let first = localDeviceID <= peerDeviceID ? (local, localDeviceID, peer, peerDeviceID) : (peer, peerDeviceID, local, localDeviceID)
        var record = makeRecord(source: first.0, sourceDeviceID: first.1, target: first.2, targetDeviceID: first.3, difference: difference, syncRunID: syncRunID, discoveredAt: discoveredAt, reason: reason)
        record.sourceDeviceID = nil
        record.targetDeviceID = nil
        record.requiresContentTransfer = false
        record.requiresMetadataUpdate = false
        record.status = .deferred
        return record
    }

    private func proof(for object: SyncObject) -> (hash: String?, size: Int64?, deleted: Bool, isSufficient: Bool) {
        let hash = object.sha256?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sufficient = object.deletedOrTombstoned
            || (!(hash ?? "").isEmpty && (!isContentBearing(object.objectKind) || object.size != nil))
        return (hash, object.size, object.deletedOrTombstoned, sufficient)
    }

    private func isContentBearing(_ kind: String) -> Bool {
        kind != "recordingMetadata" && kind != "studyItem" && kind != "studyFolder"
    }

    private func businessName(for object: SyncObject) -> String? {
        let candidate: String? = isContentBearing(object.objectKind)
            ? (object.fileName ?? object.logicalName ?? object.displayTitle)
            : (object.displayTitle ?? object.logicalName ?? object.fileName)
        let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized?.isEmpty == false ? normalized : nil
    }

    private func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: TimeInterval(Int64(date.timeIntervalSince1970)))
    }
}

nonisolated final class SyncReconciliationStore: @unchecked Sendable {
    private struct Ledger: Codable {
        var schemaVersion: Int
        var records: [SyncReconciliationRecord]
    }

    private let fileManager: FileManager
    private let ledgerURL: URL?
    private let lock = NSLock()
    private let maximumRecords: Int

    init(rootURL: URL?, fileManager: FileManager = .default, maximumRecords: Int = 4096) {
        self.fileManager = fileManager
        self.maximumRecords = maximumRecords
        ledgerURL = rootURL?
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("Reconciliation", isDirectory: true)
            .appendingPathComponent("records.json", isDirectory: false)
    }

    func snapshot() -> [SyncReconciliationRecord] {
        lock.withLock { ((try? loadLocked())?.records ?? []).sorted { $0.objectID < $1.objectID } }
    }

    func record(objectID: String) -> SyncReconciliationRecord? {
        snapshot().first { $0.objectID == objectID }
    }

    func pendingSourceRecord(objectID: String, sourceDeviceID: String, targetDeviceID: String? = nil) -> SyncReconciliationRecord? {
        snapshot().first {
            $0.objectID == objectID && $0.sourceDeviceID == sourceDeviceID && (targetDeviceID == nil || $0.targetDeviceID == targetDeviceID) && Self.isPending($0.status)
        }
    }

    func pendingTargetRecord(objectID: String, targetDeviceID: String, sourceDeviceID: String? = nil) -> SyncReconciliationRecord? {
        snapshot().first {
            $0.objectID == objectID && $0.targetDeviceID == targetDeviceID && (sourceDeviceID == nil || $0.sourceDeviceID == sourceDeviceID) && Self.isPending($0.status)
        }
    }

    func apply(plan: SyncReconciliationPlan, localDeviceID: String, syncRunID: String?, now: Date = Date()) throws {
        try lock.withLock {
            var ledger = try loadLocked()
            let evaluated = Set(plan.evaluatedObjectIDs)
            let incoming = plan.records.filter {
                $0.sourceDeviceID == localDeviceID || $0.targetDeviceID == localDeviceID || $0.status == .deferred
            }
            let oldByID = Dictionary(uniqueKeysWithValues: ledger.records.map { ($0.recordID, $0) })
            ledger.records.removeAll { evaluated.contains($0.objectID) }
            ledger.records.append(contentsOf: incoming.map { value in
                var record = value
                record.syncRunID = syncRunID ?? value.syncRunID
                record.discoveredAt = now
                if let old = oldByID[value.recordID], old.status != .resolved {
                    record.status = old.status
                    record.transferID = old.transferID
                    record.completionProof = old.completionProof
                }
                return record
            })
            ledger.records = Array(ledger.records.sorted { $0.discoveredAt > $1.discoveredAt }.prefix(maximumRecords))
            try saveLocked(ledger)
        }
    }

    func update(recordID: String, status: SyncReconciliationStatus, transferID: String? = nil, proof: SyncReconciliationCompletionProof? = nil) throws {
        try lock.withLock {
            var ledger = try loadLocked()
            guard let index = ledger.records.firstIndex(where: { $0.recordID == recordID }) else { return }
            ledger.records[index].status = status
            if let transferID { ledger.records[index].transferID = transferID }
            if let proof { ledger.records[index].completionProof = proof }
            try saveLocked(ledger)
        }
    }

    private static func isPending(_ status: SyncReconciliationStatus) -> Bool {
        [.pendingTransfer, .pendingMetadataUpdate, .queued, .transferring, .transferredAwaitingVerification].contains(status)
    }

    private func loadLocked() throws -> Ledger {
        guard let ledgerURL, fileManager.fileExists(atPath: ledgerURL.path) else {
            return Ledger(schemaVersion: 1, records: [])
        }
        let data = try Data(contentsOf: ledgerURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let ledger = try decoder.decode(Ledger.self, from: data)
        guard ledger.schemaVersion == 1 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return ledger
    }

    private func saveLocked(_ ledger: Ledger) throws {
        guard let ledgerURL else { return }
        try fileManager.createDirectory(at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: ledgerURL, options: .atomic)
    }
}

nonisolated private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

struct SyncDiffPlanner: Sendable {
    func plan(
        local: SyncInventory,
        peer: SyncInventory,
        lastSuccessfulSyncAt: Date?
    ) -> SyncDiffPlan {
        _ = lastSuccessfulSyncAt
        let reconciliation = SyncReconciliationPlanner().plan(local: local, peer: peer)
        let localByID = Dictionary(uniqueKeysWithValues: local.objects.map { ($0.objectID, $0) })
        let peerByID = Dictionary(uniqueKeysWithValues: peer.objects.map { ($0.objectID, $0) })
        var actions: [SyncDiffAction] = []

        for record in reconciliation.records {
            let object = localByID[record.objectID] ?? peerByID[record.objectID]
            guard let object else { continue }
            if record.status == .deferred {
                let kind: SyncDiffActionKind = record.differenceKind == .timestampTie ? .conflict : .skip
                actions.append(action(kind, object: object, direction: nil, reason: record.reason))
                continue
            }
            let sourceIsLocal = record.sourceDeviceID == local.sourceDeviceID
            let direction: SyncTransferDirection = sourceIsLocal ? .upload : .download
            let kind: SyncDiffActionKind
            if record.differenceKind == .deleted {
                kind = .applyTombstone
            } else if record.requiresContentTransfer {
                kind = sourceIsLocal ? .uploadObject : .downloadObject
            } else {
                kind = .updateMetadata
            }
            actions.append(action(kind, object: object, direction: direction, reason: record.reason))
        }
        for objectID in reconciliation.convergedObjectIDs {
            guard let object = localByID[objectID] ?? peerByID[objectID] else { continue }
            actions.append(action(.noOp, object: object, direction: nil, reason: "versions_equal"))
        }
        return SyncDiffPlan(actions: actions.sorted { $0.objectID < $1.objectID })
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
    func verifyChecksum(for object: SyncObject, at url: URL) async throws -> Bool
    func atomicApply(tempURL: URL, for object: SyncObject) throws
    func markTransferState(_ state: SyncTransferState, for object: SyncObject) throws
    func markConflict(_ status: String, for object: SyncObject) throws
}
