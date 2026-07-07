//
//  CanonicalRootBoundMetadataWrite.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/4.
//

import CryptoKit
import Foundation

nonisolated enum CanonicalRecordingMetadataApplyPortMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case dryRun
    case fakeInMemory
    case testRootBound
    case productionRootDisabled
    case productionRootBound
    case productionRootUnsupported

    nonisolated var isNonDryRunRootBound: Bool {
        self == .testRootBound || self == .productionRootBound
    }

    nonisolated var isDefaultDisabled: Bool {
        self == .disabled || self == .dryRun || self == .productionRootDisabled
    }
}

nonisolated enum CanonicalRootBoundMetadataWriteFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable, Error {
    case rootEscape
    case productionRootDisabled
    case checkpointFailed
    case atomicWriteFailed
    case postconditionFailed
    case rollbackFailed
    case unsupportedStoreAPI
    case schemaMismatch
    case decodingFailed
    case permissionDenied
    case unknown
}

nonisolated struct CanonicalRootBoundMetadataTarget: Codable, Equatable, Hashable, Sendable {
    var rootToken: CanonicalRootToken
    var objectID: String
    var domain: CanonicalProductionDomain
    var logicalPathToken: String

    nonisolated init(
        rootToken: CanonicalRootToken,
        objectID: String,
        domain: CanonicalProductionDomain = .recordingMetadata,
        logicalPathToken: String
    ) throws {
        let sanitizedObjectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        guard domain == .recordingMetadata else {
            throw CanonicalRootBoundMetadataWriteFailure.unsupportedStoreAPI
        }
        guard let safePath = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken) else {
            throw CanonicalRootBoundMetadataWriteFailure.rootEscape
        }
        self.rootToken = rootToken
        self.objectID = sanitizedObjectID
        self.domain = domain
        self.logicalPathToken = safePath
    }

    nonisolated static func defaultLogicalPathToken(objectID: String) -> String {
        "recordingMetadata/\(safePathComponent(objectID)).json"
    }

    private nonisolated static func safePathComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = trimmed.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let candidate = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        if !candidate.isEmpty {
            return candidate
        }
        return "recording-\(CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(trimmed).value) ?? "unknown")"
    }
}

nonisolated struct CanonicalRootBoundMetadataWrite: Codable, Equatable, Sendable {
    var target: CanonicalRootBoundMetadataTarget
    var actionKind: CanonicalRecordingMetadataCutoverActionKind
    var metadataBytes: Data
    var metadataHash: CanonicalHash?
    var tombstone: Bool
    var modifiedAt: CanonicalTimestamp?

    nonisolated init(
        target: CanonicalRootBoundMetadataTarget,
        actionKind: CanonicalRecordingMetadataCutoverActionKind,
        metadataBytes: Data,
        metadataHash: CanonicalHash? = nil,
        tombstone: Bool = false,
        modifiedAt: CanonicalTimestamp? = nil
    ) {
        self.target = target
        self.actionKind = actionKind
        self.metadataBytes = metadataBytes
        self.metadataHash = metadataHash
        self.tombstone = tombstone
        self.modifiedAt = modifiedAt
    }
}

nonisolated struct CanonicalRootBoundMetadataCheckpoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { checkpointID }

    var checkpointID: String
    var objectID: String
    var domain: CanonicalProductionDomain
    var rollbackID: String
    var hashPrefixBefore: String?
    var byteCountBefore: Int64?
    var existedBeforeWrite: Bool
    var rollbackAvailable: Bool

    nonisolated init(
        checkpointID: String,
        objectID: String,
        domain: CanonicalProductionDomain = .recordingMetadata,
        rollbackID: String,
        hashBefore: CanonicalHash? = nil,
        byteCountBefore: Int64? = nil,
        existedBeforeWrite: Bool,
        rollbackAvailable: Bool
    ) {
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "metadata-checkpoint")
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.domain = domain
        self.rollbackID = CanonicalProductionRedaction.safeIdentifier(rollbackID, fallback: "metadata-rollback")
        self.hashPrefixBefore = hashBefore.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteCountBefore = byteCountBefore
        self.existedBeforeWrite = existedBeforeWrite
        self.rollbackAvailable = rollbackAvailable
    }
}

nonisolated struct CanonicalRootBoundMetadataWriteResult: Codable, Equatable, Sendable {
    var objectID: String
    var domain: CanonicalProductionDomain
    var actionKind: CanonicalRecordingMetadataCutoverActionKind
    var hashPrefixBefore: String?
    var hashPrefixAfter: String?
    var byteCount: Int64
    var checkpointID: String
    var atomicWriteUsed: Bool
    var rollbackAvailable: Bool
    var tombstone: Bool
    var modifiedAt: CanonicalTimestamp?
    var failure: CanonicalRootBoundMetadataWriteFailure?

    nonisolated init(
        objectID: String,
        domain: CanonicalProductionDomain = .recordingMetadata,
        actionKind: CanonicalRecordingMetadataCutoverActionKind,
        hashBefore: CanonicalHash? = nil,
        hashAfter: CanonicalHash? = nil,
        byteCount: Int64,
        checkpointID: String,
        atomicWriteUsed: Bool,
        rollbackAvailable: Bool,
        tombstone: Bool,
        modifiedAt: CanonicalTimestamp?,
        failure: CanonicalRootBoundMetadataWriteFailure? = nil
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.domain = domain
        self.actionKind = actionKind
        self.hashPrefixBefore = hashBefore.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.hashPrefixAfter = hashAfter.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteCount = max(0, byteCount)
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "metadata-checkpoint")
        self.atomicWriteUsed = atomicWriteUsed
        self.rollbackAvailable = rollbackAvailable
        self.tombstone = tombstone
        self.modifiedAt = modifiedAt
        self.failure = failure
    }
}

nonisolated struct CanonicalRootBoundMetadataRollbackResult: Codable, Equatable, Sendable {
    var objectID: String
    var domain: CanonicalProductionDomain
    var checkpointID: String
    var succeeded: Bool
    var rollbackVerified: Bool
    var hashPrefixAfterRollback: String?
    var byteCount: Int64?
    var failure: CanonicalRootBoundMetadataWriteFailure?

    nonisolated init(
        objectID: String,
        domain: CanonicalProductionDomain = .recordingMetadata,
        checkpointID: String,
        succeeded: Bool,
        rollbackVerified: Bool,
        hashAfterRollback: CanonicalHash? = nil,
        byteCount: Int64? = nil,
        failure: CanonicalRootBoundMetadataWriteFailure? = nil
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.domain = domain
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "metadata-checkpoint")
        self.succeeded = succeeded
        self.rollbackVerified = rollbackVerified
        self.hashPrefixAfterRollback = hashAfterRollback.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteCount = byteCount
        self.failure = failure
    }
}

actor CanonicalRootBoundMetadataWriteCore {
    private struct StoredCheckpoint: Sendable {
        var publicCheckpoint: CanonicalRootBoundMetadataCheckpoint
        var target: CanonicalRootBoundMetadataTarget
        var previousBytes: Data?
        var previousHash: CanonicalHash?
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let rootToken: CanonicalRootToken
    private let mode: CanonicalRecordingMetadataApplyPortMode
    private var payloadsByActionID: [String: CanonicalRootBoundMetadataWrite] = [:]
    private var payloadsByObjectAndKind: [String: CanonicalRootBoundMetadataWrite] = [:]
    private var checkpoints: [String: StoredCheckpoint] = [:]
    private var actionIDsByCheckpointID: [String: String] = [:]
    private var lastWriteByActionID: [String: CanonicalRootBoundMetadataWriteResult] = [:]
    private var lastRollbackByCheckpointID: [String: CanonicalRootBoundMetadataRollbackResult] = [:]
    private var checkpointFailureObjectIDs: Set<String> = []
    private var postconditionFailureObjectIDs: Set<String> = []
    private var rollbackFailureCheckpointIDs: Set<String> = []

    init(
        rootURL: URL,
        rootToken: CanonicalRootToken,
        mode: CanonicalRecordingMetadataApplyPortMode,
        fileManager: FileManager = .default
    ) throws {
        guard rootURL.isFileURL else {
            throw CanonicalRootBoundMetadataWriteFailure.rootEscape
        }
        self.fileManager = fileManager
        self.rootURL = rootURL.standardizedFileURL
        self.rootToken = rootToken
        self.mode = mode
    }

    var applyPortMode: CanonicalRecordingMetadataApplyPortMode {
        mode
    }

    func setPayload(
        objectID: String,
        actionKind: CanonicalRecordingMetadataCutoverActionKind,
        metadataBytes: Data,
        metadataHash: CanonicalHash? = nil,
        tombstone: Bool = false,
        modifiedAt: CanonicalTimestamp? = nil,
        logicalPathToken: String? = nil,
        actionID: String? = nil
    ) throws {
        let target = try CanonicalRootBoundMetadataTarget(
            rootToken: rootToken,
            objectID: objectID,
            logicalPathToken: logicalPathToken ?? CanonicalRootBoundMetadataTarget.defaultLogicalPathToken(objectID: objectID)
        )
        let write = CanonicalRootBoundMetadataWrite(
            target: target,
            actionKind: actionKind,
            metadataBytes: metadataBytes,
            metadataHash: metadataHash,
            tombstone: tombstone,
            modifiedAt: modifiedAt
        )
        payloadsByObjectAndKind[key(objectID: target.objectID, actionKind: actionKind)] = write
        if let actionID {
            payloadsByActionID[CanonicalProductionRedaction.safeIdentifier(actionID, fallback: actionKind.rawValue)] = write
        }
    }

    func injectCheckpointFailure(for objectID: String) {
        checkpointFailureObjectIDs.insert(CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording"))
    }

    func injectPostconditionFailure(for objectID: String) {
        postconditionFailureObjectIDs.insert(CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording"))
    }

    func injectRollbackFailure(checkpointID: String) {
        rollbackFailureCheckpointIDs.insert(CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "metadata-checkpoint"))
    }

    func write(action: CanonicalApplyAction, actionKind: CanonicalRecordingMetadataCutoverActionKind, checkpointID: String?) throws -> CanonicalRootBoundMetadataWriteResult {
        try requireWritableMode()
        let objectID = CanonicalProductionRedaction.safeIdentifier(action.target.objectID, fallback: "unknown-recording")
        guard let payload = payloadsByActionID[action.actionID] ?? payloadsByObjectAndKind[key(objectID: objectID, actionKind: actionKind)] else {
            throw CanonicalRootBoundMetadataWriteFailure.unsupportedStoreAPI
        }
        guard payload.actionKind == actionKind, payload.target.objectID == objectID else {
            throw CanonicalRootBoundMetadataWriteFailure.schemaMismatch
        }
        guard !checkpointFailureObjectIDs.contains(objectID) else {
            throw CanonicalRootBoundMetadataWriteFailure.checkpointFailed
        }
        let effectiveCheckpointID = CanonicalProductionRedaction.safeIdentifier(
            checkpointID ?? "root-bound-metadata-\(objectID)-\(actionKind.rawValue)",
            fallback: "metadata-checkpoint"
        )
        let targetURL = try resolvedURL(for: payload.target)
        let previousBytes = fileManager.fileExists(atPath: targetURL.path) ? try Data(contentsOf: targetURL) : nil
        let previousHash = previousBytes.map(Self.sha256)
        let checkpoint = CanonicalRootBoundMetadataCheckpoint(
            checkpointID: effectiveCheckpointID,
            objectID: objectID,
            rollbackID: "rollback-\(effectiveCheckpointID)",
            hashBefore: previousHash,
            byteCountBefore: previousBytes.map { Int64($0.count) },
            existedBeforeWrite: previousBytes != nil,
            rollbackAvailable: true
        )
        checkpoints[effectiveCheckpointID] = StoredCheckpoint(
            publicCheckpoint: checkpoint,
            target: payload.target,
            previousBytes: previousBytes,
            previousHash: previousHash
        )
        actionIDsByCheckpointID[effectiveCheckpointID] = action.actionID

        do {
            try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.metadataBytes.write(to: targetURL, options: .atomic)
            let reread = try Data(contentsOf: targetURL)
            guard reread == payload.metadataBytes else {
                try restore(checkpointID: effectiveCheckpointID)
                throw CanonicalRootBoundMetadataWriteFailure.postconditionFailed
            }
            let afterHash = payload.metadataHash ?? Self.sha256(reread)
            let result = CanonicalRootBoundMetadataWriteResult(
                objectID: objectID,
                actionKind: actionKind,
                hashBefore: previousHash,
                hashAfter: afterHash,
                byteCount: Int64(reread.count),
                checkpointID: effectiveCheckpointID,
                atomicWriteUsed: true,
                rollbackAvailable: true,
                tombstone: payload.tombstone,
                modifiedAt: payload.modifiedAt
            )
            lastWriteByActionID[action.actionID] = result
            return result
        } catch let failure as CanonicalRootBoundMetadataWriteFailure {
            throw failure
        } catch CocoaError.fileWriteNoPermission {
            try? restore(checkpointID: effectiveCheckpointID)
            throw CanonicalRootBoundMetadataWriteFailure.permissionDenied
        } catch CocoaError.fileReadNoPermission {
            throw CanonicalRootBoundMetadataWriteFailure.permissionDenied
        } catch {
            try? restore(checkpointID: effectiveCheckpointID)
            throw CanonicalRootBoundMetadataWriteFailure.atomicWriteFailed
        }
    }

    func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) -> CanonicalProductionApplyPostcondition {
        var checked = postcondition
        let objectID = CanonicalProductionRedaction.safeIdentifier(postcondition.target.objectID, fallback: "unknown-recording")
        if postconditionFailureObjectIDs.contains(objectID) {
            checked.accepted = false
            checked.reason = CanonicalRootBoundMetadataWriteFailure.postconditionFailed.rawValue
            return checked
        }
        guard let write = lastWriteByActionID[postcondition.actionID] else {
            checked.accepted = false
            checked.reason = CanonicalRootBoundMetadataWriteFailure.postconditionFailed.rawValue
            return checked
        }
        if let expected = postcondition.actualHashPrefix,
           let actual = write.hashPrefixAfter,
           CanonicalProductionRedaction.hashPrefix(expected) != actual {
            checked.accepted = false
            checked.reason = CanonicalRootBoundMetadataWriteFailure.postconditionFailed.rawValue
        }
        return checked
    }

    func rollback(_ request: CanonicalRollbackAction) -> CanonicalRootBoundMetadataRollbackResult {
        let checkpointID = CanonicalProductionRedaction.safeIdentifier(request.checkpointID ?? request.actionID, fallback: "metadata-checkpoint")
        let objectID = request.objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") } ?? "unknown-recording"
        guard !rollbackFailureCheckpointIDs.contains(checkpointID) else {
            let result = CanonicalRootBoundMetadataRollbackResult(
                objectID: objectID,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                failure: .rollbackFailed
            )
            lastRollbackByCheckpointID[checkpointID] = result
            return result
        }
        do {
            try restore(checkpointID: checkpointID)
            guard let checkpoint = checkpoints[checkpointID] else {
                throw CanonicalRootBoundMetadataWriteFailure.rollbackFailed
            }
            let targetURL = try resolvedURL(for: checkpoint.target)
            let currentBytes = fileManager.fileExists(atPath: targetURL.path) ? try Data(contentsOf: targetURL) : nil
            let verified = currentBytes == checkpoint.previousBytes
            let result = CanonicalRootBoundMetadataRollbackResult(
                objectID: checkpoint.publicCheckpoint.objectID,
                checkpointID: checkpointID,
                succeeded: verified,
                rollbackVerified: verified,
                hashAfterRollback: currentBytes.map(Self.sha256),
                byteCount: currentBytes.map { Int64($0.count) },
                failure: verified ? nil : .rollbackFailed
            )
            lastRollbackByCheckpointID[checkpointID] = result
            return result
        } catch {
            let result = CanonicalRootBoundMetadataRollbackResult(
                objectID: objectID,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                failure: .rollbackFailed
            )
            lastRollbackByCheckpointID[checkpointID] = result
            return result
        }
    }

    func lastWriteResult(actionID: String) -> CanonicalRootBoundMetadataWriteResult? {
        lastWriteByActionID[actionID]
    }

    func lastRollbackResult(checkpointID: String) -> CanonicalRootBoundMetadataRollbackResult? {
        lastRollbackByCheckpointID[CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "metadata-checkpoint")]
    }

    func readMetadataBytes(objectID: String, actionKind: CanonicalRecordingMetadataCutoverActionKind = .apply) throws -> Data? {
        let safeObjectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        guard let payload = payloadsByObjectAndKind[key(objectID: safeObjectID, actionKind: actionKind)] else {
            return nil
        }
        let url = try resolvedURL(for: payload.target)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    private func requireWritableMode() throws {
        switch mode {
        case .testRootBound, .productionRootBound:
            return
        case .productionRootDisabled, .disabled, .dryRun:
            throw CanonicalRootBoundMetadataWriteFailure.productionRootDisabled
        case .productionRootUnsupported, .fakeInMemory:
            throw CanonicalRootBoundMetadataWriteFailure.unsupportedStoreAPI
        }
    }

    private func restore(checkpointID: String) throws {
        guard let checkpoint = checkpoints[checkpointID] else {
            throw CanonicalRootBoundMetadataWriteFailure.rollbackFailed
        }
        let url = try resolvedURL(for: checkpoint.target)
        if let bytes = checkpoint.previousBytes {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url, options: .atomic)
        } else if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func resolvedURL(for target: CanonicalRootBoundMetadataTarget) throws -> URL {
        guard target.rootToken == rootToken,
              CanonicalProjectionContract.safeLogicalPathToken(target.logicalPathToken) != nil else {
            throw CanonicalRootBoundMetadataWriteFailure.rootEscape
        }
        let url = rootURL.appendingPathComponent(target.logicalPathToken, isDirectory: false).standardizedFileURL
        guard isInsideRoot(url), url.path != rootURL.path else {
            throw CanonicalRootBoundMetadataWriteFailure.rootEscape
        }
        return url
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == rootPath || filePath.hasPrefix(rootPath + "/")
    }

    private func key(objectID: String, actionKind: CanonicalRecordingMetadataCutoverActionKind) -> String {
        "\(CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording"))|\(actionKind.rawValue)"
    }

    private nonisolated static func sha256(_ data: Data) -> CanonicalHash {
        let digest = SHA256.hash(data: data)
        return CanonicalHash(digest.map { String(format: "%02x", $0) }.joined())
    }
}
