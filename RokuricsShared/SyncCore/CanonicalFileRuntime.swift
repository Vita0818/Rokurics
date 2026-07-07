//
//  CanonicalFileRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import CryptoKit
import Foundation

nonisolated struct CanonicalRootToken: Codable, Equatable, Hashable, Sendable {
    var rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "root:unknown"
    }
}

nonisolated enum CanonicalFilePurpose: String, Codable, Equatable, Sendable {
    case artifactBytes
    case generatedArtifact
    case metadataBlob
    case tombstoneMarker
}

nonisolated struct CanonicalFileReference: Codable, Equatable, Hashable, Sendable {
    var rootToken: CanonicalRootToken
    var logicalPathToken: String
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?

    nonisolated init(
        rootToken: CanonicalRootToken,
        logicalPathToken: String,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil
    ) {
        self.rootToken = rootToken
        self.logicalPathToken = logicalPathToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artifactID = artifactID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.artifactKind = artifactKind
    }
}

typealias CanonicalFileHandle = CanonicalFileReference

nonisolated enum CanonicalAtomicWritePolicy: String, Codable, Equatable, Sendable {
    case atomicReplace
    case directInMemoryReplace
}

nonisolated enum CanonicalFileHashPolicy: String, Codable, Equatable, Sendable {
    case sha256
    case none
}

nonisolated enum CanonicalFileConflictPolicy: String, Codable, Equatable, Sendable {
    case noOverwrite
    case replace
    case replaceIfExistingHashMatches
    case idempotentIfSameContent
}

nonisolated struct CanonicalMetadataBlob: Codable, Equatable, Sendable {
    var fields: [String: String]

    nonisolated init(_ fields: [String: String] = [:]) {
        self.fields = Dictionary(uniqueKeysWithValues: fields.map { key, value in
            (key.trimmingCharacters(in: .whitespacesAndNewlines), value)
        }.filter { !$0.0.isEmpty })
    }
}

nonisolated struct CanonicalFileWriteIntent: Codable, Equatable, Sendable {
    var reference: CanonicalFileReference
    var bytes: Data
    var purpose: CanonicalFilePurpose
    var expectedContentHash: CanonicalHash?
    var expectedByteSize: Int64?
    var expectedExistingHash: CanonicalHash?
    var atomicPolicy: CanonicalAtomicWritePolicy
    var hashPolicy: CanonicalFileHashPolicy
    var conflictPolicy: CanonicalFileConflictPolicy
    var metadataBlob: CanonicalMetadataBlob?

    nonisolated init(
        reference: CanonicalFileReference,
        bytes: Data,
        purpose: CanonicalFilePurpose = .artifactBytes,
        expectedContentHash: CanonicalHash? = nil,
        expectedByteSize: Int64? = nil,
        expectedExistingHash: CanonicalHash? = nil,
        atomicPolicy: CanonicalAtomicWritePolicy = .atomicReplace,
        hashPolicy: CanonicalFileHashPolicy = .sha256,
        conflictPolicy: CanonicalFileConflictPolicy = .noOverwrite,
        metadataBlob: CanonicalMetadataBlob? = nil
    ) {
        self.reference = reference
        self.bytes = bytes
        self.purpose = purpose
        self.expectedContentHash = expectedContentHash
        self.expectedByteSize = expectedByteSize
        self.expectedExistingHash = expectedExistingHash
        self.atomicPolicy = atomicPolicy
        self.hashPolicy = hashPolicy
        self.conflictPolicy = conflictPolicy
        self.metadataBlob = metadataBlob
    }
}

nonisolated struct CanonicalFileReadRequest: Codable, Equatable, Sendable {
    var reference: CanonicalFileReference
    var allowTombstonedRead: Bool

    nonisolated init(reference: CanonicalFileReference, allowTombstonedRead: Bool = false) {
        self.reference = reference
        self.allowTombstonedRead = allowTombstonedRead
    }
}

nonisolated enum CanonicalFileWriteDisposition: String, Codable, Equatable, Sendable {
    case created
    case replaced
    case acceptedExisting
    case tombstoneMarked
}

nonisolated struct CanonicalPathResolutionResult: Codable, Equatable, Sendable {
    var rootToken: CanonicalRootToken
    var logicalPathToken: String
    var resolvedPathToken: String
    var isInsideRoot: Bool
}

nonisolated struct CanonicalFileWriteResult: Codable, Equatable, Sendable {
    var handle: CanonicalFileHandle
    var resolution: CanonicalPathResolutionResult
    var byteSize: Int64
    var contentHash: CanonicalHash?
    var disposition: CanonicalFileWriteDisposition
    var purpose: CanonicalFilePurpose
    var tombstoned: Bool
}

nonisolated struct CanonicalFileReadResult: Codable, Equatable, Sendable {
    var handle: CanonicalFileHandle
    var resolution: CanonicalPathResolutionResult
    var bytes: Data
    var byteSize: Int64
    var contentHash: CanonicalHash?
    var purpose: CanonicalFilePurpose
    var metadataBlob: CanonicalMetadataBlob?
    var tombstoned: Bool
    var tombstoneReason: String?
}

nonisolated enum CanonicalFileRuntimeError: Error, Equatable, Sendable {
    case rootNotBound(String)
    case invalidPathToken(String)
    case pathTraversalRejected(String)
    case absolutePathRejected(String)
    case schemeURLRejected(String)
    case backslashTraversalRejected(String)
    case rootEscapeRejected(String)
    case fileNotFound(String)
    case tombstoned(String)
    case conflict(String)
    case preWriteHashMismatch(expected: String, actual: String)
    case preWriteSizeMismatch(expected: Int64, actual: Int64)
    case postWriteHashMismatch(expected: String, actual: String)
    case postWriteSizeMismatch(expected: Int64, actual: Int64)
    case existingHashMismatch(expected: String, actual: String?)
    case unsupportedHashPolicy(String)
}

nonisolated protocol CanonicalPathResolver: Sendable {
    func resolve(rootToken: CanonicalRootToken, logicalPathToken: String) throws -> CanonicalPathResolutionResult
}

nonisolated struct CanonicalInMemoryPathResolver: CanonicalPathResolver {
    private var rootBindings: [CanonicalRootToken: String]

    nonisolated init(rootBindings: [CanonicalRootToken: String]) {
        self.rootBindings = rootBindings
    }

    nonisolated func resolve(rootToken: CanonicalRootToken, logicalPathToken: String) throws -> CanonicalPathResolutionResult {
        guard let rawRoot = rootBindings[rootToken] else {
            throw CanonicalFileRuntimeError.rootNotBound(rootToken.rawValue)
        }
        let rootPath = try validatedRootPath(rawRoot)
        let safeToken = try validatedLogicalPath(logicalPathToken)
        let resolved = "\(rootPath)/\(safeToken)"
        guard resolved.hasPrefix("\(rootPath)/") else {
            throw CanonicalFileRuntimeError.rootEscapeRejected(logicalPathToken)
        }
        return CanonicalPathResolutionResult(
            rootToken: rootToken,
            logicalPathToken: safeToken,
            resolvedPathToken: resolved,
            isInsideRoot: true
        )
    }

    private func validatedRootPath(_ token: String) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CanonicalFileRuntimeError.rootEscapeRejected(token)
        }
        guard !trimmed.hasPrefix("/") else {
            throw CanonicalFileRuntimeError.rootEscapeRejected(token)
        }
        guard !trimmed.contains("://") else {
            throw CanonicalFileRuntimeError.rootEscapeRejected(token)
        }
        guard !trimmed.contains("\\") else {
            throw CanonicalFileRuntimeError.rootEscapeRejected(token)
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CanonicalFileRuntimeError.rootEscapeRejected(token)
        }
        return trimmed
    }

    private func validatedLogicalPath(_ token: String) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CanonicalFileRuntimeError.invalidPathToken(token)
        }
        guard !trimmed.hasPrefix("/") else {
            throw CanonicalFileRuntimeError.absolutePathRejected(token)
        }
        guard !trimmed.contains("://") else {
            throw CanonicalFileRuntimeError.schemeURLRejected(token)
        }
        guard !trimmed.contains("\\") else {
            throw CanonicalFileRuntimeError.backslashTraversalRejected(token)
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CanonicalFileRuntimeError.pathTraversalRejected(token)
        }
        guard CanonicalProjectionContract.safeLogicalPathToken(trimmed) != nil else {
            throw CanonicalFileRuntimeError.invalidPathToken(token)
        }
        return trimmed
    }
}

nonisolated protocol CanonicalFileStorePort: Sendable {
    func resolve(_ reference: CanonicalFileReference) async throws -> CanonicalPathResolutionResult
    func read(_ request: CanonicalFileReadRequest) async throws -> CanonicalFileReadResult
    @discardableResult func write(_ intent: CanonicalFileWriteIntent) async throws -> CanonicalFileWriteResult
    @discardableResult func markTombstone(_ reference: CanonicalFileReference, reason: String?) async throws -> CanonicalFileWriteResult
    func contains(_ reference: CanonicalFileReference) async throws -> Bool
}

actor InMemoryCanonicalFileStore: CanonicalFileStorePort {
    private struct Entry: Sendable {
        var bytes: Data
        var purpose: CanonicalFilePurpose
        var contentHash: CanonicalHash?
        var metadataBlob: CanonicalMetadataBlob?
        var tombstoned: Bool
        var tombstoneReason: String?
    }

    private let resolver: any CanonicalPathResolver
    private var entries: [String: Entry] = [:]

    init(rootBindings: [CanonicalRootToken: String]) {
        self.resolver = CanonicalInMemoryPathResolver(rootBindings: rootBindings)
    }

    init(resolver: any CanonicalPathResolver) {
        self.resolver = resolver
    }

    nonisolated func resolve(_ reference: CanonicalFileReference) async throws -> CanonicalPathResolutionResult {
        try resolver.resolve(rootToken: reference.rootToken, logicalPathToken: reference.logicalPathToken)
    }

    func contains(_ reference: CanonicalFileReference) async throws -> Bool {
        let resolution = try await resolve(reference)
        return entries[resolution.resolvedPathToken] != nil
    }

    func read(_ request: CanonicalFileReadRequest) async throws -> CanonicalFileReadResult {
        let resolution = try await resolve(request.reference)
        guard let entry = entries[resolution.resolvedPathToken] else {
            throw CanonicalFileRuntimeError.fileNotFound(resolution.logicalPathToken)
        }
        if entry.tombstoned && !request.allowTombstonedRead {
            throw CanonicalFileRuntimeError.tombstoned(resolution.logicalPathToken)
        }
        return CanonicalFileReadResult(
            handle: request.reference,
            resolution: resolution,
            bytes: entry.bytes,
            byteSize: Int64(entry.bytes.count),
            contentHash: entry.contentHash,
            purpose: entry.purpose,
            metadataBlob: entry.metadataBlob,
            tombstoned: entry.tombstoned,
            tombstoneReason: entry.tombstoneReason
        )
    }

    @discardableResult
    func write(_ intent: CanonicalFileWriteIntent) async throws -> CanonicalFileWriteResult {
        let resolution = try await resolve(intent.reference)
        let newHash = Self.hash(intent.bytes, policy: intent.hashPolicy)
        try validatePreWrite(intent: intent, actualHash: newHash)

        let existing = entries[resolution.resolvedPathToken]
        if let existing,
           isIdempotentSameContent(intent: intent, existing: existing, newHash: newHash) {
            return CanonicalFileWriteResult(
                handle: intent.reference,
                resolution: resolution,
                byteSize: Int64(existing.bytes.count),
                contentHash: existing.contentHash,
                disposition: .acceptedExisting,
                purpose: existing.purpose,
                tombstoned: existing.tombstoned
            )
        }
        try validateConflictPolicy(intent: intent, existing: existing)

        let entry = Entry(
            bytes: intent.bytes,
            purpose: intent.purpose,
            contentHash: newHash,
            metadataBlob: intent.metadataBlob,
            tombstoned: intent.purpose == .tombstoneMarker,
            tombstoneReason: intent.purpose == .tombstoneMarker ? "marker" : nil
        )

        entries[resolution.resolvedPathToken] = entry
        let stored = entries[resolution.resolvedPathToken] ?? entry
        try validatePostWrite(intent: intent, stored: stored)

        return CanonicalFileWriteResult(
            handle: intent.reference,
            resolution: resolution,
            byteSize: Int64(stored.bytes.count),
            contentHash: stored.contentHash,
            disposition: existing == nil ? .created : .replaced,
            purpose: stored.purpose,
            tombstoned: stored.tombstoned
        )
    }

    @discardableResult
    func markTombstone(_ reference: CanonicalFileReference, reason: String?) async throws -> CanonicalFileWriteResult {
        let resolution = try await resolve(reference)
        var entry = entries[resolution.resolvedPathToken] ?? Entry(
            bytes: Data(),
            purpose: .tombstoneMarker,
            contentHash: Self.hash(Data(), policy: .sha256),
            metadataBlob: nil,
            tombstoned: false,
            tombstoneReason: nil
        )
        entry.tombstoned = true
        entry.tombstoneReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "softDelete"
        entries[resolution.resolvedPathToken] = entry
        return CanonicalFileWriteResult(
            handle: reference,
            resolution: resolution,
            byteSize: Int64(entry.bytes.count),
            contentHash: entry.contentHash,
            disposition: .tombstoneMarked,
            purpose: .tombstoneMarker,
            tombstoned: true
        )
    }

    private func validatePreWrite(intent: CanonicalFileWriteIntent, actualHash: CanonicalHash?) throws {
        if let expectedByteSize = intent.expectedByteSize,
           expectedByteSize != Int64(intent.bytes.count) {
            throw CanonicalFileRuntimeError.preWriteSizeMismatch(expected: expectedByteSize, actual: Int64(intent.bytes.count))
        }
        if let expectedContentHash = intent.expectedContentHash {
            guard let actualHash else {
                throw CanonicalFileRuntimeError.unsupportedHashPolicy(intent.hashPolicy.rawValue)
            }
            guard Self.sameHash(expectedContentHash, actualHash) else {
                throw CanonicalFileRuntimeError.preWriteHashMismatch(expected: expectedContentHash.value, actual: actualHash.value)
            }
        }
    }

    private func validatePostWrite(intent: CanonicalFileWriteIntent, stored: Entry) throws {
        if let expectedByteSize = intent.expectedByteSize,
           expectedByteSize != Int64(stored.bytes.count) {
            throw CanonicalFileRuntimeError.postWriteSizeMismatch(expected: expectedByteSize, actual: Int64(stored.bytes.count))
        }
        if let expectedContentHash = intent.expectedContentHash {
            guard let storedHash = stored.contentHash else {
                throw CanonicalFileRuntimeError.unsupportedHashPolicy(intent.hashPolicy.rawValue)
            }
            guard Self.sameHash(expectedContentHash, storedHash) else {
                throw CanonicalFileRuntimeError.postWriteHashMismatch(expected: expectedContentHash.value, actual: storedHash.value)
            }
        }
    }

    private func validateConflictPolicy(intent: CanonicalFileWriteIntent, existing: Entry?) throws {
        guard let existing else {
            return
        }
        if let expectedExistingHash = intent.expectedExistingHash {
            guard let existingHash = existing.contentHash, Self.sameHash(expectedExistingHash, existingHash) else {
                throw CanonicalFileRuntimeError.existingHashMismatch(
                    expected: expectedExistingHash.value,
                    actual: existing.contentHash?.value
                )
            }
        }
        let newHash = Self.hash(intent.bytes, policy: intent.hashPolicy)
        switch intent.conflictPolicy {
        case .replace:
            return
        case .replaceIfExistingHashMatches:
            guard intent.expectedExistingHash != nil else {
                throw CanonicalFileRuntimeError.existingHashMismatch(expected: "required", actual: existing.contentHash?.value)
            }
        case .idempotentIfSameContent:
            if let newHash, let existingHash = existing.contentHash, Self.sameHash(existingHash, newHash), existing.bytes.count == intent.bytes.count {
                return
            }
            throw CanonicalFileRuntimeError.conflict(intent.reference.logicalPathToken)
        case .noOverwrite:
            if let newHash, let existingHash = existing.contentHash, Self.sameHash(existingHash, newHash), existing.bytes.count == intent.bytes.count {
                return
            }
            throw CanonicalFileRuntimeError.conflict(intent.reference.logicalPathToken)
        }
    }

    private func isIdempotentSameContent(
        intent: CanonicalFileWriteIntent,
        existing: Entry,
        newHash: CanonicalHash?
    ) -> Bool {
        guard intent.conflictPolicy == .idempotentIfSameContent || intent.conflictPolicy == .noOverwrite,
              let newHash,
              let existingHash = existing.contentHash else {
            return false
        }
        return Self.sameHash(existingHash, newHash) && existing.bytes.count == intent.bytes.count
    }

    private nonisolated static func sameHash(_ left: CanonicalHash, _ right: CanonicalHash) -> Bool {
        left.algorithm == right.algorithm && left.value == right.value
    }

    nonisolated static func hash(_ data: Data, policy: CanonicalFileHashPolicy = .sha256) -> CanonicalHash? {
        switch policy {
        case .none:
            return nil
        case .sha256:
            let digest = SHA256.hash(data: data)
            return CanonicalHash(digest.map { String(format: "%02x", $0) }.joined())
        }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

nonisolated enum CanonicalFileKernelRuntimeReadinessStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForV910FileKernelRuntime = "READY_FOR_V9_1_FILE_KERNEL_RUNTIME"
    case partialWithBlockers = "PARTIAL_WITH_BLOCKERS"
    case notReady = "NOT_READY"
    case unsafeToProceed = "UNSAFE_TO_PROCEED"
}

nonisolated enum CanonicalFileKernelRuntimeReadinessBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case fileTreeOffMainMissing
    case manifestOffMainMissing
    case checksumCacheMissing
    case contentStableCacheKeyMissing
    case asyncDiagnosticsMissing
    case mainActorGuardMissing
    case readProjectionCacheMissing
    case macInventoryRouteMissing
    case diagnosticsRedactionMissing
    case routeSecurityChanged
    case defaultReleaseCanonicalEnabled
    case legacyFallbackMissing
    case uploadRouteChanged
    case requestVerifierBypassed
    case diagnosticsLeakDetected
    case mainActorHeavyWorkDetected
}

nonisolated struct CanonicalFileKernelRuntimeNoFreezeScorecard: Codable, Equatable, Hashable, Sendable {
    var fileTreeOffMainReady: Bool
    var manifestOffMainReady: Bool
    var checksumCacheReady: Bool
    var contentStableCacheKeyReady: Bool
    var asyncDiagnosticsReady: Bool
    var mainActorGuardReady: Bool
    var readProjectionCacheReady: Bool
    var macInventoryRouteReady: Bool
    var diagnosticsRedacted: Bool
    var routeSecurityUnchanged: Bool
}

nonisolated struct CanonicalFileKernelRuntimeEvidence: Codable, Equatable, Hashable, Sendable {
    var fileTreeOffMainReady: Bool
    var manifestOffMainReady: Bool
    var checksumCacheReady: Bool
    var contentStableCacheKeyReady: Bool
    var asyncDiagnosticsReady: Bool
    var mainActorGuardReady: Bool
    var readProjectionCacheReady: Bool
    var macInventoryRouteReady: Bool
    var diagnosticsRedacted: Bool
    var routeSecurityUnchanged: Bool
    var defaultReleaseOldKernel: Bool
    var legacyFallbackPreserved: Bool
    var uploadRouteSchemaUnchanged: Bool
    var requestVerifierPreserved: Bool
    var diagnosticsLeakDetected: Bool
    var mainActorHeavyWorkDetected: Bool

    nonisolated init(
        fileTreeOffMainReady: Bool = false,
        manifestOffMainReady: Bool = false,
        checksumCacheReady: Bool = false,
        contentStableCacheKeyReady: Bool = false,
        asyncDiagnosticsReady: Bool = false,
        mainActorGuardReady: Bool = false,
        readProjectionCacheReady: Bool = false,
        macInventoryRouteReady: Bool = false,
        diagnosticsRedacted: Bool = false,
        routeSecurityUnchanged: Bool = false,
        defaultReleaseOldKernel: Bool = false,
        legacyFallbackPreserved: Bool = false,
        uploadRouteSchemaUnchanged: Bool = false,
        requestVerifierPreserved: Bool = false,
        diagnosticsLeakDetected: Bool = false,
        mainActorHeavyWorkDetected: Bool = false
    ) {
        self.fileTreeOffMainReady = fileTreeOffMainReady
        self.manifestOffMainReady = manifestOffMainReady
        self.checksumCacheReady = checksumCacheReady
        self.contentStableCacheKeyReady = contentStableCacheKeyReady
        self.asyncDiagnosticsReady = asyncDiagnosticsReady
        self.mainActorGuardReady = mainActorGuardReady
        self.readProjectionCacheReady = readProjectionCacheReady
        self.macInventoryRouteReady = macInventoryRouteReady
        self.diagnosticsRedacted = diagnosticsRedacted
        self.routeSecurityUnchanged = routeSecurityUnchanged
        self.defaultReleaseOldKernel = defaultReleaseOldKernel
        self.legacyFallbackPreserved = legacyFallbackPreserved
        self.uploadRouteSchemaUnchanged = uploadRouteSchemaUnchanged
        self.requestVerifierPreserved = requestVerifierPreserved
        self.diagnosticsLeakDetected = diagnosticsLeakDetected
        self.mainActorHeavyWorkDetected = mainActorHeavyWorkDetected
    }

    nonisolated var scorecard: CanonicalFileKernelRuntimeNoFreezeScorecard {
        CanonicalFileKernelRuntimeNoFreezeScorecard(
            fileTreeOffMainReady: fileTreeOffMainReady,
            manifestOffMainReady: manifestOffMainReady,
            checksumCacheReady: checksumCacheReady,
            contentStableCacheKeyReady: contentStableCacheKeyReady,
            asyncDiagnosticsReady: asyncDiagnosticsReady,
            mainActorGuardReady: mainActorGuardReady,
            readProjectionCacheReady: readProjectionCacheReady,
            macInventoryRouteReady: macInventoryRouteReady,
            diagnosticsRedacted: diagnosticsRedacted,
            routeSecurityUnchanged: routeSecurityUnchanged
        )
    }

    nonisolated var hasUnsafeEvidence: Bool {
        !routeSecurityUnchanged
            || !defaultReleaseOldKernel
            || !legacyFallbackPreserved
            || !uploadRouteSchemaUnchanged
            || !requestVerifierPreserved
            || diagnosticsLeakDetected
            || mainActorHeavyWorkDetected
    }

    nonisolated var runtimeEvidenceComplete: Bool {
        fileTreeOffMainReady
            && manifestOffMainReady
            && checksumCacheReady
            && contentStableCacheKeyReady
            && asyncDiagnosticsReady
            && mainActorGuardReady
            && readProjectionCacheReady
            && macInventoryRouteReady
            && diagnosticsRedacted
            && routeSecurityUnchanged
            && defaultReleaseOldKernel
            && legacyFallbackPreserved
            && uploadRouteSchemaUnchanged
            && requestVerifierPreserved
    }
}

nonisolated struct CanonicalFileKernelRuntimeReadinessReport: Codable, Equatable, Hashable, Sendable {
    var status: CanonicalFileKernelRuntimeReadinessStatus
    var blockers: [CanonicalFileKernelRuntimeReadinessBlocker]
    var noFreezeScorecard: CanonicalFileKernelRuntimeNoFreezeScorecard
    var readyForV910FileKernelRuntime: Bool

    nonisolated init(
        status: CanonicalFileKernelRuntimeReadinessStatus,
        blockers: [CanonicalFileKernelRuntimeReadinessBlocker],
        noFreezeScorecard: CanonicalFileKernelRuntimeNoFreezeScorecard
    ) {
        self.status = status
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.noFreezeScorecard = noFreezeScorecard
        self.readyForV910FileKernelRuntime = status == .readyForV910FileKernelRuntime
    }
}

nonisolated struct CanonicalFileKernelRuntimeReadiness: Sendable {
    nonisolated init() {}

    nonisolated static func v910(_ evidence: CanonicalFileKernelRuntimeEvidence) -> CanonicalFileKernelRuntimeReadinessReport {
        if evidence.hasUnsafeEvidence {
            return CanonicalFileKernelRuntimeReadinessReport(
                status: .unsafeToProceed,
                blockers: unsafeBlockers(from: evidence),
                noFreezeScorecard: evidence.scorecard
            )
        }

        let blockers = readinessBlockers(from: evidence)
        if blockers.isEmpty && evidence.runtimeEvidenceComplete {
            return CanonicalFileKernelRuntimeReadinessReport(
                status: .readyForV910FileKernelRuntime,
                blockers: [],
                noFreezeScorecard: evidence.scorecard
            )
        }

        let runtimeCorePresent = evidence.fileTreeOffMainReady
            || evidence.manifestOffMainReady
            || evidence.checksumCacheReady
            || evidence.asyncDiagnosticsReady
            || evidence.mainActorGuardReady
        return CanonicalFileKernelRuntimeReadinessReport(
            status: runtimeCorePresent ? .partialWithBlockers : .notReady,
            blockers: blockers,
            noFreezeScorecard: evidence.scorecard
        )
    }

    private nonisolated static func unsafeBlockers(
        from evidence: CanonicalFileKernelRuntimeEvidence
    ) -> [CanonicalFileKernelRuntimeReadinessBlocker] {
        var blockers: [CanonicalFileKernelRuntimeReadinessBlocker] = []
        if !evidence.routeSecurityUnchanged { blockers.append(.routeSecurityChanged) }
        if !evidence.defaultReleaseOldKernel { blockers.append(.defaultReleaseCanonicalEnabled) }
        if !evidence.legacyFallbackPreserved { blockers.append(.legacyFallbackMissing) }
        if !evidence.uploadRouteSchemaUnchanged { blockers.append(.uploadRouteChanged) }
        if !evidence.requestVerifierPreserved { blockers.append(.requestVerifierBypassed) }
        if evidence.diagnosticsLeakDetected { blockers.append(.diagnosticsLeakDetected) }
        if evidence.mainActorHeavyWorkDetected { blockers.append(.mainActorHeavyWorkDetected) }
        return blockers
    }

    private nonisolated static func readinessBlockers(
        from evidence: CanonicalFileKernelRuntimeEvidence
    ) -> [CanonicalFileKernelRuntimeReadinessBlocker] {
        var blockers: [CanonicalFileKernelRuntimeReadinessBlocker] = []
        if !evidence.fileTreeOffMainReady { blockers.append(.fileTreeOffMainMissing) }
        if !evidence.manifestOffMainReady { blockers.append(.manifestOffMainMissing) }
        if !evidence.checksumCacheReady { blockers.append(.checksumCacheMissing) }
        if !evidence.contentStableCacheKeyReady { blockers.append(.contentStableCacheKeyMissing) }
        if !evidence.asyncDiagnosticsReady { blockers.append(.asyncDiagnosticsMissing) }
        if !evidence.mainActorGuardReady { blockers.append(.mainActorGuardMissing) }
        if !evidence.readProjectionCacheReady { blockers.append(.readProjectionCacheMissing) }
        if !evidence.macInventoryRouteReady { blockers.append(.macInventoryRouteMissing) }
        if !evidence.diagnosticsRedacted { blockers.append(.diagnosticsRedactionMissing) }
        return blockers
    }
}
