//
//  CanonicalFileProtocol.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalFileNodeKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case file
    case directory
}

nonisolated struct CanonicalFileTreeEntry: Codable, Equatable, Hashable, Sendable {
    var objectID: CanonicalObjectID?
    var relativePath: String
    var kind: CanonicalFileNodeKind
    var byteSize: Int64
    var modifiedAt: CanonicalTimestamp?
    var contentHash: CanonicalHash?

    nonisolated init(
        objectID: CanonicalObjectID? = nil,
        relativePath: String,
        kind: CanonicalFileNodeKind,
        byteSize: Int64 = 0,
        modifiedAt: CanonicalTimestamp? = nil,
        contentHash: CanonicalHash? = nil
    ) {
        self.objectID = objectID
        self.relativePath = CanonicalKernelStringSanitizer.required(relativePath, fallback: ".")
        self.kind = kind
        self.byteSize = max(0, byteSize)
        self.modifiedAt = modifiedAt
        self.contentHash = contentHash
    }
}

nonisolated struct CanonicalFileTreeSnapshot: Codable, Equatable, Hashable, Sendable {
    var rootID: String
    var capturedAt: CanonicalTimestamp
    var entries: [CanonicalFileTreeEntry]
    var builtOffMainActor: Bool

    nonisolated init(
        rootID: String,
        capturedAt: CanonicalTimestamp,
        entries: [CanonicalFileTreeEntry],
        builtOffMainActor: Bool
    ) {
        self.rootID = CanonicalKernelStringSanitizer.required(rootID, fallback: "canonical-root")
        self.capturedAt = capturedAt
        self.entries = entries.sorted { $0.relativePath < $1.relativePath }
        self.builtOffMainActor = builtOffMainActor
    }
}

nonisolated struct CanonicalFileManifestEntry: Codable, Equatable, Hashable, Sendable {
    var relativePath: String
    var byteSize: Int64
    var contentHash: CanonicalHash?

    nonisolated init(relativePath: String, byteSize: Int64, contentHash: CanonicalHash? = nil) {
        self.relativePath = CanonicalKernelStringSanitizer.required(relativePath, fallback: ".")
        self.byteSize = max(0, byteSize)
        self.contentHash = contentHash
    }
}

nonisolated struct CanonicalFileManifest: Codable, Equatable, Hashable, Sendable {
    var rootID: String
    var entries: [CanonicalFileManifestEntry]
    var manifestHash: CanonicalHash?
    var builtAt: CanonicalTimestamp
    var builtOffMainActor: Bool

    nonisolated init(
        rootID: String,
        entries: [CanonicalFileManifestEntry],
        manifestHash: CanonicalHash? = nil,
        builtAt: CanonicalTimestamp,
        builtOffMainActor: Bool
    ) {
        self.rootID = CanonicalKernelStringSanitizer.required(rootID, fallback: "canonical-root")
        self.entries = entries.sorted { $0.relativePath < $1.relativePath }
        self.manifestHash = manifestHash
        self.builtAt = builtAt
        self.builtOffMainActor = builtOffMainActor
    }
}

nonisolated enum CanonicalChecksumLookupState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case hit
    case miss
    case stale
}

nonisolated struct CanonicalChecksumLookupResult: Codable, Equatable, Sendable {
    var state: CanonicalChecksumLookupState
    var record: CanonicalChecksumCacheRecord?

    nonisolated init(state: CanonicalChecksumLookupState, record: CanonicalChecksumCacheRecord? = nil) {
        self.state = state
        self.record = record
    }
}

nonisolated struct CanonicalRollback: Codable, Equatable, Hashable, Sendable {
    var checkpointID: String
    var targetRelativePath: String
    var previousHash: CanonicalHash?

    nonisolated init(
        checkpointID: String,
        targetRelativePath: String,
        previousHash: CanonicalHash? = nil
    ) {
        self.checkpointID = CanonicalKernelStringSanitizer.required(checkpointID, fallback: "rollback-checkpoint")
        self.targetRelativePath = CanonicalKernelStringSanitizer.required(targetRelativePath, fallback: ".")
        self.previousHash = previousHash
    }
}

nonisolated struct CanonicalAtomicWrite: Codable, Equatable, Hashable, Sendable {
    var writeID: String
    var rootID: String
    var targetRelativePath: String
    var bytes: Data
    var expectedHash: CanonicalHash?
    var rollback: CanonicalRollback?

    nonisolated init(
        writeID: String,
        rootID: String,
        targetRelativePath: String,
        bytes: Data,
        expectedHash: CanonicalHash? = nil,
        rollback: CanonicalRollback? = nil
    ) {
        self.writeID = CanonicalKernelStringSanitizer.required(writeID, fallback: "atomic-write")
        self.rootID = CanonicalKernelStringSanitizer.required(rootID, fallback: "canonical-root")
        self.targetRelativePath = CanonicalKernelStringSanitizer.required(targetRelativePath, fallback: ".")
        self.bytes = bytes
        self.expectedHash = expectedHash
        self.rollback = rollback
    }
}

nonisolated struct CanonicalAtomicWritePostcondition: Codable, Equatable, Hashable, Sendable {
    var writeID: String
    var committed: Bool
    var contentHash: CanonicalHash?
    var byteSize: Int64
    var rollbackRequired: Bool

    nonisolated init(
        writeID: String,
        committed: Bool,
        contentHash: CanonicalHash? = nil,
        byteSize: Int64,
        rollbackRequired: Bool = false
    ) {
        self.writeID = CanonicalKernelStringSanitizer.required(writeID, fallback: "atomic-write")
        self.committed = committed
        self.contentHash = contentHash
        self.byteSize = max(0, byteSize)
        self.rollbackRequired = rollbackRequired
    }
}

nonisolated struct CanonicalNoFreezeBudget: Codable, Equatable, Hashable, Sendable {
    var maxMainActorDurationMs: Int
    var maxFileTreeSnapshotDurationMs: Int
    var maxManifestBuildDurationMs: Int
    var maxHashDurationMs: Int
    var fileTreeScanRequiresOffMainActor: Bool
    var manifestBuildRequiresOffMainActor: Bool
    var fullFileHashRequiresOffMainActor: Bool
    var diagnosticsWriteRequiresOffMainActor: Bool

    nonisolated init(
        maxMainActorDurationMs: Int = 16,
        maxFileTreeSnapshotDurationMs: Int = 250,
        maxManifestBuildDurationMs: Int = 250,
        maxHashDurationMs: Int = 250,
        fileTreeScanRequiresOffMainActor: Bool = true,
        manifestBuildRequiresOffMainActor: Bool = true,
        fullFileHashRequiresOffMainActor: Bool = true,
        diagnosticsWriteRequiresOffMainActor: Bool = true
    ) {
        self.maxMainActorDurationMs = max(1, maxMainActorDurationMs)
        self.maxFileTreeSnapshotDurationMs = max(1, maxFileTreeSnapshotDurationMs)
        self.maxManifestBuildDurationMs = max(1, maxManifestBuildDurationMs)
        self.maxHashDurationMs = max(1, maxHashDurationMs)
        self.fileTreeScanRequiresOffMainActor = fileTreeScanRequiresOffMainActor
        self.manifestBuildRequiresOffMainActor = manifestBuildRequiresOffMainActor
        self.fullFileHashRequiresOffMainActor = fullFileHashRequiresOffMainActor
        self.diagnosticsWriteRequiresOffMainActor = diagnosticsWriteRequiresOffMainActor
    }
}

nonisolated enum CanonicalMainActorHotPathViolation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case fileTreeScan
    case manifestBuild
    case fullFileHash
    case diagnosticsWrite
    case readProjectionRebuild
    case studyTreeRebuild
}

nonisolated protocol CanonicalFileTreeProvider: Sendable {
    func snapshotFileTree(rootID: String, budget: CanonicalNoFreezeBudget) async throws -> CanonicalFileTreeSnapshot
}

nonisolated protocol CanonicalManifestBuilder: Sendable {
    func buildManifest(
        from snapshot: CanonicalFileTreeSnapshot,
        budget: CanonicalNoFreezeBudget
    ) async throws -> CanonicalFileManifest
}

nonisolated protocol CanonicalChecksumCachePort: Sendable {
    func lookup(_ key: CanonicalChecksumCacheKey) async throws -> CanonicalChecksumLookupResult
    func store(_ record: CanonicalChecksumCacheRecord) async throws
}

nonisolated protocol CanonicalRootBoundWriter: Sendable {
    func writeAtomically(_ write: CanonicalAtomicWrite) async throws -> CanonicalAtomicWritePostcondition
    func rollback(_ rollback: CanonicalRollback) async throws -> CanonicalAtomicWritePostcondition
}
