//
//  CanonicalManifestRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated struct CanonicalManifestRuntimeEntryCacheKey: Codable, Equatable, Hashable, Sendable {
    var rootToken: CanonicalRootToken
    var logicalToken: String
    var byteSize: Int64
    var modifiedAtEpochMs: Int64?
    var contentVersion: String?
    var schemaVersion: String
    var domainHint: CanonicalFileDomainHint
    var hashPrefix: String?
}

nonisolated struct CanonicalManifestRuntimeCacheKey: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: String
    var rootToken: CanonicalRootToken
    var logicalScopeToken: String
    var entryKeys: [CanonicalManifestRuntimeEntryCacheKey]
    var cacheKeyHashPrefix: String

    nonisolated init(
        schemaVersion: String,
        rootToken: CanonicalRootToken,
        logicalScopeToken: String,
        entryKeys: [CanonicalManifestRuntimeEntryCacheKey]
    ) {
        self.schemaVersion = CanonicalKernelStringSanitizer.required(
            schemaVersion,
            fallback: "canonical-file-manifest-v910"
        )
        self.rootToken = rootToken
        self.logicalScopeToken = logicalScopeToken
        self.entryKeys = entryKeys.sorted { left, right in
            if left.logicalToken == right.logicalToken {
                return left.domainHint.rawValue < right.domainHint.rawValue
            }
            return left.logicalToken < right.logicalToken
        }
        let summary = self.entryKeys.map { key in
            [
                key.rootToken.rawValue,
                key.logicalToken,
                String(key.byteSize),
                key.modifiedAtEpochMs.map(String.init) ?? "no-mtime",
                key.contentVersion ?? "no-version",
                key.schemaVersion,
                key.domainHint.rawValue,
                key.hashPrefix ?? "no-hash"
            ].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")
        self.cacheKeyHashPrefix = String(CanonicalHash.sha256String(summary).value.prefix(12))
    }
}

nonisolated struct CanonicalFileManifestRuntimeResult: Codable, Equatable, Hashable, Sendable {
    var manifest: CanonicalFileManifest
    var cacheKey: CanonicalManifestRuntimeCacheKey
    var durationMs: Int
    var mainActorAttemptCount: Int
    var builtOffMainActor: Bool
}

nonisolated struct CanonicalManifestRuntimeBuildResult: Codable, Equatable, Sendable {
    var canonicalManifest: CanonicalManifest
    var fileManifest: CanonicalFileManifest
    var cacheKey: CanonicalManifestRuntimeCacheKey
    var coverage: CanonicalInventoryCoverageReport
    var diagnostics: CanonicalInventoryBuildDiagnostics
}

nonisolated struct CanonicalManifestRuntimeBuilder: Sendable {
    private let clock: CanonicalInventoryRuntimeClock

    nonisolated init(clock: CanonicalInventoryRuntimeClock = .system) {
        self.clock = clock
    }

    nonisolated func buildFileManifest(
        from snapshot: CanonicalFileRuntimeSnapshot,
        schemaVersion: String = "canonical-file-manifest-v910"
    ) -> CanonicalFileManifestRuntimeResult {
        let startedAt = clock.now()
        let mainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
        let entries = snapshot.entries.map { entry in
            CanonicalFileManifestEntry(
                relativePath: entry.logicalToken,
                byteSize: entry.byteSize,
                contentHash: entry.hashProof
            )
        }
        let cacheKey = Self.cacheKey(
            from: snapshot,
            schemaVersion: schemaVersion
        )
        let manifestHash = CanonicalHash.sha256String(
            cacheKey.entryKeys.map { entry in
                [
                    entry.rootToken.rawValue,
                    entry.logicalToken,
                    String(entry.byteSize),
                    entry.modifiedAtEpochMs.map(String.init) ?? "no-mtime",
                    entry.contentVersion ?? "no-version",
                    entry.schemaVersion,
                    entry.domainHint.rawValue,
                    entry.hashPrefix ?? "no-hash"
                ].joined(separator: "\u{1F}")
            }.joined(separator: "\u{1E}")
        )
        let endedAt = clock.now()
        return CanonicalFileManifestRuntimeResult(
            manifest: CanonicalFileManifest(
                rootID: snapshot.scope.rootToken.rawValue,
                entries: entries,
                manifestHash: manifestHash,
                builtAt: CanonicalTimestamp(endedAt),
                builtOffMainActor: mainActorAttemptCount == 0
            ),
            cacheKey: cacheKey,
            durationMs: max(0, Int(endedAt.timeIntervalSince(startedAt) * 1_000)),
            mainActorAttemptCount: mainActorAttemptCount,
            builtOffMainActor: mainActorAttemptCount == 0
        )
    }

    nonisolated func buildCanonicalManifest(
        from inventorySnapshot: CanonicalInventoryInputSnapshot,
        fileSnapshot: CanonicalFileRuntimeSnapshot,
        schemaVersion: String = "canonical-file-manifest-v910"
    ) -> CanonicalManifestRuntimeBuildResult {
        let canonicalBuild = CanonicalInventoryBuilderContract().build(from: inventorySnapshot)
        let fileBuild = buildFileManifest(from: fileSnapshot, schemaVersion: schemaVersion)
        return CanonicalManifestRuntimeBuildResult(
            canonicalManifest: canonicalBuild.manifest,
            fileManifest: fileBuild.manifest,
            cacheKey: fileBuild.cacheKey,
            coverage: canonicalBuild.coverage,
            diagnostics: canonicalBuild.diagnostics
        )
    }

    nonisolated static func cacheKey(
        from snapshot: CanonicalFileRuntimeSnapshot,
        schemaVersion: String = "canonical-file-manifest-v910"
    ) -> CanonicalManifestRuntimeCacheKey {
        CanonicalManifestRuntimeCacheKey(
            schemaVersion: schemaVersion,
            rootToken: snapshot.scope.rootToken,
            logicalScopeToken: snapshot.scope.logicalScopeToken,
            entryKeys: snapshot.entries.map { entry in
                CanonicalManifestRuntimeEntryCacheKey(
                    rootToken: entry.rootToken,
                    logicalToken: entry.logicalToken,
                    byteSize: entry.byteSize,
                    modifiedAtEpochMs: entry.modifiedAtEpochMs,
                    contentVersion: entry.contentVersion,
                    schemaVersion: schemaVersion,
                    domainHint: entry.domainHint,
                    hashPrefix: entry.hashPrefix
                )
            }
        )
    }
}
