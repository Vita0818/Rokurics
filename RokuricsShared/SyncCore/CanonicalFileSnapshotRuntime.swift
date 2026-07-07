//
//  CanonicalFileSnapshotRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalFileDomainHint: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingAudio
    case recordingMetadata
    case studyLibraryMetadata
    case generatedArtifact
    case receiveRecord
    case diagnostics
    case unknown
}

nonisolated struct CanonicalFileSnapshotScope: Codable, Equatable, Hashable, Sendable {
    var rootToken: CanonicalRootToken
    var logicalScopeToken: String
    var domainHint: CanonicalFileDomainHint
    var schemaVersion: String
    var includeHashProofs: Bool

    nonisolated init(
        rootToken: CanonicalRootToken,
        logicalScopeToken: String,
        domainHint: CanonicalFileDomainHint = .unknown,
        schemaVersion: String = "canonical-file-snapshot-v910",
        includeHashProofs: Bool = true
    ) throws {
        self.rootToken = rootToken
        self.logicalScopeToken = try CanonicalFileRuntimeTokenValidator.safeLogicalToken(
            logicalScopeToken,
            fallback: "."
        )
        self.domainHint = domainHint
        self.schemaVersion = CanonicalKernelStringSanitizer.required(
            schemaVersion,
            fallback: "canonical-file-snapshot-v910"
        )
        self.includeHashProofs = includeHashProofs
    }
}

nonisolated struct CanonicalFileSnapshotSourceEntry: Codable, Equatable, Hashable, Sendable {
    var logicalToken: String
    var kind: CanonicalFileNodeKind
    var byteSize: Int64
    var modifiedAt: CanonicalTimestamp?
    var contentVersion: String?
    var stableFileIdentity: String?
    var domainHint: CanonicalFileDomainHint
    var hashProof: CanonicalHash?

    nonisolated init(
        logicalToken: String,
        kind: CanonicalFileNodeKind,
        byteSize: Int64 = 0,
        modifiedAt: CanonicalTimestamp? = nil,
        contentVersion: String? = nil,
        stableFileIdentity: String? = nil,
        domainHint: CanonicalFileDomainHint = .unknown,
        hashProof: CanonicalHash? = nil
    ) throws {
        self.logicalToken = try CanonicalFileRuntimeTokenValidator.safeLogicalToken(logicalToken)
        self.kind = kind
        self.byteSize = max(0, byteSize)
        self.modifiedAt = modifiedAt
        self.contentVersion = CanonicalFileRuntimeTokenValidator.safeOptionalToken(contentVersion)
        self.stableFileIdentity = CanonicalFileRuntimeTokenValidator.safeOptionalToken(stableFileIdentity)
        self.domainHint = domainHint
        self.hashProof = hashProof
    }
}

nonisolated struct CanonicalFileSnapshotEntry: Codable, Equatable, Hashable, Sendable {
    var stableFileIdentity: String
    var rootToken: CanonicalRootToken
    var logicalToken: String
    var kind: CanonicalFileNodeKind
    var byteSize: Int64
    var modifiedAtEpochMs: Int64?
    var contentVersion: String?
    var domainHint: CanonicalFileDomainHint
    var hashProof: CanonicalHash?

    nonisolated var hashPrefix: String? {
        hashProof.map { String($0.value.prefix(12)) }
    }
}

nonisolated struct CanonicalFileRuntimeSnapshot: Codable, Equatable, Hashable, Sendable {
    var scope: CanonicalFileSnapshotScope
    var capturedAt: CanonicalTimestamp
    var entries: [CanonicalFileSnapshotEntry]
    var builtOffMainActor: Bool
    var durationMs: Int
    var mainActorAttemptCount: Int
    var redacted: Bool

    nonisolated init(
        scope: CanonicalFileSnapshotScope,
        capturedAt: Date,
        entries: [CanonicalFileSnapshotEntry],
        builtOffMainActor: Bool,
        durationMs: Int,
        mainActorAttemptCount: Int,
        redacted: Bool = true
    ) {
        self.scope = scope
        self.capturedAt = CanonicalTimestamp(capturedAt)
        self.entries = entries.sorted { left, right in
            if left.logicalToken == right.logicalToken {
                return left.stableFileIdentity < right.stableFileIdentity
            }
            return left.logicalToken < right.logicalToken
        }
        self.builtOffMainActor = builtOffMainActor
        self.durationMs = max(0, durationMs)
        self.mainActorAttemptCount = max(0, mainActorAttemptCount)
        self.redacted = redacted
    }
}

nonisolated protocol CanonicalFileSnapshotRuntimeAdapter: Sendable {
    func listFileSnapshotEntries(
        scope: CanonicalFileSnapshotScope
    ) async throws -> [CanonicalFileSnapshotSourceEntry]
}

nonisolated struct CanonicalStaticFileSnapshotAdapter: CanonicalFileSnapshotRuntimeAdapter {
    private var entries: [CanonicalFileSnapshotSourceEntry]

    nonisolated init(entries: [CanonicalFileSnapshotSourceEntry]) {
        self.entries = entries
    }

    nonisolated func listFileSnapshotEntries(
        scope: CanonicalFileSnapshotScope
    ) async throws -> [CanonicalFileSnapshotSourceEntry] {
        entries.filter { entry in
            scope.logicalScopeToken == "."
                || entry.logicalToken == scope.logicalScopeToken
                || entry.logicalToken.hasPrefix(scope.logicalScopeToken + "/")
        }
    }
}

actor CanonicalFileTreeSnapshotBuilder {
    private let adapter: any CanonicalFileSnapshotRuntimeAdapter
    private let clock: CanonicalInventoryRuntimeClock

    init(
        adapter: any CanonicalFileSnapshotRuntimeAdapter,
        clock: CanonicalInventoryRuntimeClock = .system
    ) {
        self.adapter = adapter
        self.clock = clock
    }

    func buildSnapshot(scope: CanonicalFileSnapshotScope) async throws -> CanonicalFileRuntimeSnapshot {
        let adapter = adapter
        let clock = clock
        return try await Task.detached(priority: .utility) {
            let startedAt = clock.now()
            let mainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            let sourceEntries = try await adapter.listFileSnapshotEntries(scope: scope)
            let entries = sourceEntries.map { source in
                CanonicalFileSnapshotEntry(
                    stableFileIdentity: source.stableFileIdentity
                        ?? Self.stableIdentity(rootToken: scope.rootToken, logicalToken: source.logicalToken, kind: source.kind),
                    rootToken: scope.rootToken,
                    logicalToken: source.logicalToken,
                    kind: source.kind,
                    byteSize: source.byteSize,
                    modifiedAtEpochMs: source.modifiedAt.map { Self.epochMs($0.date) },
                    contentVersion: source.contentVersion,
                    domainHint: source.domainHint == .unknown ? scope.domainHint : source.domainHint,
                    hashProof: scope.includeHashProofs ? source.hashProof : nil
                )
            }
            let endedAt = clock.now()
            return CanonicalFileRuntimeSnapshot(
                scope: scope,
                capturedAt: endedAt,
                entries: entries,
                builtOffMainActor: mainActorAttemptCount == 0,
                durationMs: max(0, Int(endedAt.timeIntervalSince(startedAt) * 1_000)),
                mainActorAttemptCount: mainActorAttemptCount,
                redacted: entries.allSatisfy { CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics($0.logicalToken) }
            )
        }.value
    }

    private nonisolated static func stableIdentity(
        rootToken: CanonicalRootToken,
        logicalToken: String,
        kind: CanonicalFileNodeKind
    ) -> String {
        let hash = CanonicalHash.sha256String([
            rootToken.rawValue,
            logicalToken,
            kind.rawValue
        ].joined(separator: "\u{1F}"))
        return "file-\(String(hash.value.prefix(16)))"
    }

    private nonisolated static func epochMs(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

nonisolated enum CanonicalFileRuntimeTokenValidator {
    nonisolated static func safeLogicalToken(
        _ value: String,
        fallback: String? = nil
    ) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, let fallback {
            return fallback
        }
        guard !trimmed.isEmpty else {
            throw CanonicalFileRuntimeError.invalidPathToken(value)
        }
        guard trimmed == "." || !trimmed.hasPrefix("/") else {
            throw CanonicalFileRuntimeError.absolutePathRejected(value)
        }
        guard !trimmed.contains("://") else {
            throw CanonicalFileRuntimeError.schemeURLRejected(value)
        }
        guard !trimmed.contains("\\") else {
            throw CanonicalFileRuntimeError.backslashTraversalRejected(value)
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard trimmed == "." || components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CanonicalFileRuntimeError.pathTraversalRejected(value)
        }
        guard CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(trimmed) else {
            throw CanonicalFileRuntimeError.invalidPathToken(value)
        }
        return trimmed
    }

    nonisolated static func safeOptionalToken(_ value: String?) -> String? {
        guard let value = CanonicalKernelStringSanitizer.optional(value),
              CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics(value),
              !value.hasPrefix("/"),
              !value.contains("://"),
              !value.contains("\\") else {
            return nil
        }
        return value
    }
}
