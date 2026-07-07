//
//  CanonicalInventoryRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/7.
//

import CryptoKit
import Foundation

nonisolated enum CanonicalInventoryRuntimeNodeRole: String, Codable, Equatable, Sendable {
    case iPhone
    case mac
}

nonisolated enum CanonicalInventoryRuntimeSourceKind: String, Codable, Equatable, Sendable {
    case syncTick
    case inventoryRequest
    case artifactLookup
    case testHarness
}

nonisolated struct CanonicalInventoryRuntimeConfiguration: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    var checksumSchemaVersion: Int
    var hashAlgorithm: String
    var cacheFileName: String
    var redactedDiagnostics: Bool
    var persistentChecksumCacheEnabled: Bool
    var cacheStoreNamespace: String?
    var maxCacheRecords: Int
    var maxCacheBytes: Int

    nonisolated init(
        checksumSchemaVersion: Int = Self.currentSchemaVersion,
        hashAlgorithm: String = "sha256",
        cacheFileName: String = "canonical-checksum-cache-v2.json",
        redactedDiagnostics: Bool = true,
        persistentChecksumCacheEnabled: Bool = true,
        cacheStoreNamespace: String? = nil,
        maxCacheRecords: Int = 5_000,
        maxCacheBytes: Int = 4 * 1024 * 1024
    ) {
        self.checksumSchemaVersion = checksumSchemaVersion
        self.hashAlgorithm = hashAlgorithm
        self.cacheFileName = cacheFileName
        self.redactedDiagnostics = redactedDiagnostics
        self.persistentChecksumCacheEnabled = persistentChecksumCacheEnabled
        self.cacheStoreNamespace = cacheStoreNamespace
        self.maxCacheRecords = max(1, maxCacheRecords)
        self.maxCacheBytes = max(8 * 1024, maxCacheBytes)
    }
}

nonisolated struct CanonicalInventoryRuntimeClock: Sendable {
    var now: @Sendable () -> Date

    nonisolated init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    nonisolated static let system = CanonicalInventoryRuntimeClock(now: Date.init)
}

nonisolated enum CanonicalInventoryRuntimeExecutionProbe {
    nonisolated static func isMainThread() -> Bool {
        Thread.isMainThread
    }
}

nonisolated struct CanonicalInventoryRuntimeDiagnostics: Codable, Equatable, Sendable {
    var checksumCacheHitCount: Int
    var checksumCacheMissCount: Int
    var checksumCacheStaleCount: Int
    var checksumCacheErrorCount: Int
    var fileScanCount: Int
    var hashComputedCount: Int
    var hashSkippedByCacheHitCount: Int
    var hashFailedCount: Int
    var hashUnavailableCount: Int
    var mainActorHashAttemptCount: Int
    var mainActorScanAttemptCount: Int
    var mainActorMetadataLoadAttemptCount: Int
    var mainActorJobsLoadAttemptCount: Int
    var mainActorManifestBuildAttemptCount: Int
    var mainActorHashBlockedCount: Int
    var mainActorScanBlockedCount: Int
    var duplicateBuildCount: Int
    var snapshotReuseCount: Int
    var scanDurationMs: Int
    var manifestBuildDurationMs: Int
    var fileScanDurationMs: Int
    var metadataLoadDurationMs: Int
    var jobsLoadDurationMs: Int
    var hashDurationMs: Int
    var cacheLoadDurationMs: Int
    var cacheWriteDurationMs: Int
    var cachePruneDurationMs: Int
    var redactionViolationCount: Int

    nonisolated init(
        checksumCacheHitCount: Int = 0,
        checksumCacheMissCount: Int = 0,
        checksumCacheStaleCount: Int = 0,
        checksumCacheErrorCount: Int = 0,
        fileScanCount: Int = 0,
        hashComputedCount: Int = 0,
        hashSkippedByCacheHitCount: Int = 0,
        hashFailedCount: Int = 0,
        hashUnavailableCount: Int = 0,
        mainActorHashAttemptCount: Int = 0,
        mainActorScanAttemptCount: Int = 0,
        mainActorMetadataLoadAttemptCount: Int = 0,
        mainActorJobsLoadAttemptCount: Int = 0,
        mainActorManifestBuildAttemptCount: Int = 0,
        mainActorHashBlockedCount: Int = 0,
        mainActorScanBlockedCount: Int = 0,
        duplicateBuildCount: Int = 0,
        snapshotReuseCount: Int = 0,
        scanDurationMs: Int = 0,
        manifestBuildDurationMs: Int = 0,
        metadataLoadDurationMs: Int = 0,
        jobsLoadDurationMs: Int = 0,
        hashDurationMs: Int = 0,
        fileScanDurationMs: Int? = nil,
        cacheLoadDurationMs: Int = 0,
        cacheWriteDurationMs: Int = 0,
        cachePruneDurationMs: Int = 0,
        redactionViolationCount: Int = 0
    ) {
        self.checksumCacheHitCount = checksumCacheHitCount
        self.checksumCacheMissCount = checksumCacheMissCount
        self.checksumCacheStaleCount = checksumCacheStaleCount
        self.checksumCacheErrorCount = checksumCacheErrorCount
        self.fileScanCount = fileScanCount
        self.hashComputedCount = hashComputedCount
        self.hashSkippedByCacheHitCount = hashSkippedByCacheHitCount
        self.hashFailedCount = hashFailedCount
        self.hashUnavailableCount = hashUnavailableCount
        self.mainActorHashAttemptCount = mainActorHashAttemptCount
        self.mainActorScanAttemptCount = mainActorScanAttemptCount
        self.mainActorMetadataLoadAttemptCount = mainActorMetadataLoadAttemptCount
        self.mainActorJobsLoadAttemptCount = mainActorJobsLoadAttemptCount
        self.mainActorManifestBuildAttemptCount = mainActorManifestBuildAttemptCount
        self.mainActorHashBlockedCount = mainActorHashBlockedCount
        self.mainActorScanBlockedCount = mainActorScanBlockedCount
        self.duplicateBuildCount = duplicateBuildCount
        self.snapshotReuseCount = snapshotReuseCount
        self.scanDurationMs = scanDurationMs
        self.manifestBuildDurationMs = manifestBuildDurationMs
        self.fileScanDurationMs = fileScanDurationMs ?? scanDurationMs
        self.metadataLoadDurationMs = metadataLoadDurationMs
        self.jobsLoadDurationMs = jobsLoadDurationMs
        self.hashDurationMs = hashDurationMs
        self.cacheLoadDurationMs = cacheLoadDurationMs
        self.cacheWriteDurationMs = cacheWriteDurationMs
        self.cachePruneDurationMs = cachePruneDurationMs
        self.redactionViolationCount = redactionViolationCount
    }

    nonisolated mutating func merge(_ result: CanonicalChecksumCacheResult) {
        fileScanCount += 1
        if result.hashComputed {
            hashComputedCount += 1
        }
        if result.event == .hit, !result.hashComputed {
            hashSkippedByCacheHitCount += 1
        }
        if result.event == .error {
            hashFailedCount += 1
        }
        if result.hashUnavailable {
            hashUnavailableCount += 1
        }
        mainActorHashAttemptCount += result.mainActorHashAttemptCount
        switch result.event {
        case .hit:
            checksumCacheHitCount += 1
        case .miss:
            checksumCacheMissCount += 1
        case .stale:
            checksumCacheStaleCount += 1
        case .error:
            checksumCacheErrorCount += 1
        }
        hashDurationMs += result.hashDurationMs
        cacheLoadDurationMs += result.cacheLoadDurationMs
        cacheWriteDurationMs += result.cacheWriteDurationMs
        cachePruneDurationMs += result.cachePruneDurationMs
        redactionViolationCount += result.redactionViolationCount
    }
}

nonisolated enum CanonicalInventoryRuntimeFailure: String, Codable, Equatable, Sendable {
    case cacheCorrupted
    case cacheWriteFailed
    case fileMetadataUnavailable
    case hashUnavailable
    case cancelled
    case unknown
}

nonisolated struct CanonicalInventoryObjectCounts: Codable, Equatable, Sendable {
    var recordingMetadataCount: Int
    var libraryFolderCount: Int
    var libraryItemCount: Int
    var artifactCount: Int
    var audioDescriptorCount: Int
}

nonisolated struct CanonicalInventoryRuntimeSnapshot: Codable, Equatable, Sendable {
    var syncRunID: String
    var nodeRole: CanonicalInventoryRuntimeNodeRole
    var buildStartedAt: Date
    var buildEndedAt: Date
    var sourceKind: CanonicalInventoryRuntimeSourceKind
    var objectCounts: CanonicalInventoryObjectCounts
    var diagnostics: CanonicalInventoryRuntimeDiagnostics
    var mainActorBlocked: Bool
    var reusedWithinTick: Bool
    var redacted: Bool
}

nonisolated struct CanonicalInventoryRuntimeResult: Codable, Equatable, Sendable {
    var snapshot: CanonicalInventoryRuntimeSnapshot
    var failures: [CanonicalInventoryRuntimeFailure]
}

actor CanonicalInventoryRuntimeBuilder {
    private var snapshotsByScope: [String: CanonicalInventoryRuntimeSnapshot] = [:]

    func existingSnapshot(
        syncRunID: String,
        nodeRole: CanonicalInventoryRuntimeNodeRole,
        sourceKind: CanonicalInventoryRuntimeSourceKind
    ) -> CanonicalInventoryRuntimeSnapshot? {
        snapshotsByScope[Self.scopeKey(syncRunID: syncRunID, nodeRole: nodeRole, sourceKind: sourceKind)]
    }

    func remember(_ snapshot: CanonicalInventoryRuntimeSnapshot) {
        snapshotsByScope[Self.scopeKey(
            syncRunID: snapshot.syncRunID,
            nodeRole: snapshot.nodeRole,
            sourceKind: snapshot.sourceKind
        )] = snapshot
    }

    func reusedSnapshot(_ snapshot: CanonicalInventoryRuntimeSnapshot) -> CanonicalInventoryRuntimeSnapshot {
        var reused = snapshot
        reused.reusedWithinTick = true
        return reused
    }

    func duplicateDetectedSnapshot(_ snapshot: CanonicalInventoryRuntimeSnapshot) -> CanonicalInventoryRuntimeSnapshot {
        var duplicate = snapshot
        duplicate.diagnostics.duplicateBuildCount += 1
        return duplicate
    }

    func reset() {
        snapshotsByScope = [:]
    }

    private static func scopeKey(
        syncRunID: String,
        nodeRole: CanonicalInventoryRuntimeNodeRole,
        sourceKind: CanonicalInventoryRuntimeSourceKind
    ) -> String {
        "\(nodeRole.rawValue)|\(sourceKind.rawValue)|\(syncRunID)"
    }
}

nonisolated struct CanonicalInventoryRuntimeReport: Codable, Equatable, Sendable {
    var syncRunID: String
    var nodeRole: CanonicalInventoryRuntimeNodeRole
    var buildDurationMs: Int
    var scanDurationMs: Int
    var hashDurationMs: Int
    var cacheHitCount: Int
    var cacheMissCount: Int
    var cacheStaleCount: Int
    var cacheErrorCount: Int
    var cacheLoadDurationMs: Int
    var cacheWriteDurationMs: Int
    var cachePruneDurationMs: Int
    var hashComputedCount: Int
    var hashSkippedByCacheHitCount: Int
    var hashFailedCount: Int
    var hashUnavailableCount: Int
    var duplicateBuildCount: Int
    var snapshotReuseCount: Int
    var manifestBuildDurationMs: Int
    var metadataLoadDurationMs: Int
    var jobsLoadDurationMs: Int
    var fileScanDurationMs: Int
    var mainActorHashAttemptCount: Int
    var mainActorScanAttemptCount: Int
    var mainActorMetadataLoadAttemptCount: Int
    var mainActorJobsLoadAttemptCount: Int
    var mainActorManifestBuildAttemptCount: Int
    var mainActorHashBlockedCount: Int
    var mainActorScanBlockedCount: Int
    var redactionViolationCount: Int
    var inventoryObjectCounts: CanonicalInventoryObjectCounts
    var redacted: Bool
}

nonisolated enum CanonicalInventoryRuntimeReportExporter {
    nonisolated static func report(from snapshot: CanonicalInventoryRuntimeSnapshot) -> CanonicalInventoryRuntimeReport {
        CanonicalInventoryRuntimeReport(
            syncRunID: snapshot.syncRunID,
            nodeRole: snapshot.nodeRole,
            buildDurationMs: max(0, Int(snapshot.buildEndedAt.timeIntervalSince(snapshot.buildStartedAt) * 1_000)),
            scanDurationMs: snapshot.diagnostics.scanDurationMs,
            hashDurationMs: snapshot.diagnostics.hashDurationMs,
            cacheHitCount: snapshot.diagnostics.checksumCacheHitCount,
            cacheMissCount: snapshot.diagnostics.checksumCacheMissCount,
            cacheStaleCount: snapshot.diagnostics.checksumCacheStaleCount,
            cacheErrorCount: snapshot.diagnostics.checksumCacheErrorCount,
            cacheLoadDurationMs: snapshot.diagnostics.cacheLoadDurationMs,
            cacheWriteDurationMs: snapshot.diagnostics.cacheWriteDurationMs,
            cachePruneDurationMs: snapshot.diagnostics.cachePruneDurationMs,
            hashComputedCount: snapshot.diagnostics.hashComputedCount,
            hashSkippedByCacheHitCount: snapshot.diagnostics.hashSkippedByCacheHitCount,
            hashFailedCount: snapshot.diagnostics.hashFailedCount,
            hashUnavailableCount: snapshot.diagnostics.hashUnavailableCount,
            duplicateBuildCount: snapshot.diagnostics.duplicateBuildCount,
            snapshotReuseCount: snapshot.diagnostics.snapshotReuseCount,
            manifestBuildDurationMs: snapshot.diagnostics.manifestBuildDurationMs,
            metadataLoadDurationMs: snapshot.diagnostics.metadataLoadDurationMs,
            jobsLoadDurationMs: snapshot.diagnostics.jobsLoadDurationMs,
            fileScanDurationMs: snapshot.diagnostics.fileScanDurationMs,
            mainActorHashAttemptCount: snapshot.diagnostics.mainActorHashAttemptCount,
            mainActorScanAttemptCount: snapshot.diagnostics.mainActorScanAttemptCount,
            mainActorMetadataLoadAttemptCount: snapshot.diagnostics.mainActorMetadataLoadAttemptCount,
            mainActorJobsLoadAttemptCount: snapshot.diagnostics.mainActorJobsLoadAttemptCount,
            mainActorManifestBuildAttemptCount: snapshot.diagnostics.mainActorManifestBuildAttemptCount,
            mainActorHashBlockedCount: snapshot.diagnostics.mainActorHashBlockedCount,
            mainActorScanBlockedCount: snapshot.diagnostics.mainActorScanBlockedCount,
            redactionViolationCount: snapshot.diagnostics.redactionViolationCount,
            inventoryObjectCounts: snapshot.objectCounts,
            redacted: snapshot.redacted
        )
    }

    nonisolated static func diagnosticsSummary(from snapshot: CanonicalInventoryRuntimeSnapshot) -> String {
        let report = report(from: snapshot)
        return [
            "syncRunID=\(report.syncRunID)",
            "nodeRole=\(report.nodeRole.rawValue)",
            "buildDurationMs=\(report.buildDurationMs)",
            "scanDurationMs=\(report.scanDurationMs)",
            "hashDurationMs=\(report.hashDurationMs)",
            "manifestBuildDurationMs=\(report.manifestBuildDurationMs)",
            "metadataLoadDurationMs=\(report.metadataLoadDurationMs)",
            "jobsLoadDurationMs=\(report.jobsLoadDurationMs)",
            "fileScanDurationMs=\(report.fileScanDurationMs)",
            "cacheLoadDurationMs=\(report.cacheLoadDurationMs)",
            "cacheWriteDurationMs=\(report.cacheWriteDurationMs)",
            "cachePruneDurationMs=\(report.cachePruneDurationMs)",
            "cacheHitCount=\(report.cacheHitCount)",
            "cacheMissCount=\(report.cacheMissCount)",
            "cacheStaleCount=\(report.cacheStaleCount)",
            "cacheErrorCount=\(report.cacheErrorCount)",
            "hashComputedCount=\(report.hashComputedCount)",
            "hashSkippedByCacheHitCount=\(report.hashSkippedByCacheHitCount)",
            "hashFailedCount=\(report.hashFailedCount)",
            "hashUnavailableCount=\(report.hashUnavailableCount)",
            "duplicateBuildCount=\(report.duplicateBuildCount)",
            "snapshotReuseCount=\(report.snapshotReuseCount)",
            "mainActorHashAttemptCount=\(report.mainActorHashAttemptCount)",
            "mainActorScanAttemptCount=\(report.mainActorScanAttemptCount)",
            "mainActorMetadataLoadAttemptCount=\(report.mainActorMetadataLoadAttemptCount)",
            "mainActorJobsLoadAttemptCount=\(report.mainActorJobsLoadAttemptCount)",
            "mainActorManifestBuildAttemptCount=\(report.mainActorManifestBuildAttemptCount)",
            "mainActorHashBlockedCount=\(report.mainActorHashBlockedCount)",
            "mainActorScanBlockedCount=\(report.mainActorScanBlockedCount)",
            "redactionViolationCount=\(report.redactionViolationCount)",
            "recordingMetadataCount=\(report.inventoryObjectCounts.recordingMetadataCount)",
            "libraryFolderCount=\(report.inventoryObjectCounts.libraryFolderCount)",
            "libraryItemCount=\(report.inventoryObjectCounts.libraryItemCount)",
            "artifactCount=\(report.inventoryObjectCounts.artifactCount)",
            "audioDescriptorCount=\(report.inventoryObjectCounts.audioDescriptorCount)",
            "redacted=\(report.redacted)"
        ].joined(separator: ",")
    }

    nonisolated static func jsonData(from snapshot: CanonicalInventoryRuntimeSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(report(from: snapshot))
    }

    nonisolated static func jsonString(from snapshot: CanonicalInventoryRuntimeSnapshot) throws -> String {
        let data = try jsonData(from: snapshot)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

nonisolated struct CanonicalChecksumCacheKey: Codable, Equatable, Hashable, Sendable {
    var logicalToken: String
    var byteSize: Int64
    var modifiedAtEpochMs: Int64
    var contentVersion: String?
    var hashAlgorithm: String
    var schemaVersion: Int
    var nodeRole: CanonicalInventoryRuntimeNodeRole
    var storeNamespace: String?
}

nonisolated enum CanonicalChecksumCacheValidationState: String, Codable, Equatable, Sendable {
    case valid
    case stale
    case schemaMismatch
    case corrupted
    case unavailable
    case writeFailed
}

nonisolated struct CanonicalChecksumCacheRecord: Codable, Equatable, Sendable {
    var key: CanonicalChecksumCacheKey
    var hashAlgorithm: String
    var hashValue: String
    var hashPrefix: String
    var byteSize: Int64
    var modifiedAtEpochMs: Int64
    var computedAt: Date
    var schemaVersion: Int
    var sourceRole: CanonicalInventoryRuntimeNodeRole
    var validationState: CanonicalChecksumCacheValidationState

    nonisolated var sha256: String {
        hashValue
    }
}

nonisolated enum CanonicalChecksumCacheEvent: String, Codable, Equatable, Sendable {
    case hit
    case miss
    case stale
    case error
}

nonisolated struct CanonicalChecksumCacheResult: Codable, Equatable, Sendable {
    var sha256: String?
    var byteSize: Int64
    var modifiedAt: Date
    var event: CanonicalChecksumCacheEvent
    var hashComputed: Bool
    var hashUnavailable: Bool
    var failure: CanonicalInventoryRuntimeFailure?
    var hashDurationMs: Int
    var cacheLoadDurationMs: Int
    var cacheWriteDurationMs: Int
    var cachePruneDurationMs: Int
    var cachePersisted: Bool
    var cachePrunedRecordCount: Int
    var cacheRecordCount: Int
    var cacheByteCount: Int
    var validationState: CanonicalChecksumCacheValidationState
    var mainActorHashAttemptCount: Int
    var redactionViolationCount: Int

    nonisolated var redactedHashPrefix: String? {
        sha256.map { String($0.prefix(12)) }
    }
}

nonisolated struct CanonicalChecksumFileMetadata: Equatable, Sendable {
    var byteSize: Int64
    var modifiedAt: Date
    var contentVersion: String?

    nonisolated init(byteSize: Int64, modifiedAt: Date, contentVersion: String? = nil) {
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.contentVersion = contentVersion
    }
}

nonisolated struct CanonicalChecksumCacheLookupResult: Codable, Equatable, Sendable {
    var key: CanonicalChecksumCacheKey
    var record: CanonicalChecksumCacheRecord?
    var event: CanonicalChecksumCacheEvent
    var validationState: CanonicalChecksumCacheValidationState
    var cacheLoadDurationMs: Int
    var failure: CanonicalInventoryRuntimeFailure?
}

nonisolated struct CanonicalChecksumCacheWriteResult: Codable, Equatable, Sendable {
    var persisted: Bool
    var prunedRecordCount: Int
    var cacheWriteDurationMs: Int
    var cachePruneDurationMs: Int
    var cacheByteCount: Int
    var failure: CanonicalInventoryRuntimeFailure?
}

nonisolated struct CanonicalChecksumCacheDiagnostics: Codable, Equatable, Sendable {
    var cacheHitCount: Int
    var cacheMissCount: Int
    var cacheStaleCount: Int
    var cacheErrorCount: Int
    var cacheLoadDurationMs: Int
    var cacheWriteDurationMs: Int
    var cachePruneDurationMs: Int
    var recordsLoadedCount: Int
    var recordsPrunedCount: Int
    var cacheByteCount: Int
    var redactionViolationCount: Int
}

actor CanonicalChecksumCacheStore {
    private struct CacheFile: Codable {
        var schemaVersion: Int
        var records: [CanonicalChecksumCacheRecord]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case records
        }

        init(schemaVersion: Int, records: [CanonicalChecksumCacheRecord]) {
            self.schemaVersion = schemaVersion
            self.records = records
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            var recordsContainer = try container.nestedUnkeyedContainer(forKey: .records)
            var decodedRecords: [CanonicalChecksumCacheRecord] = []
            while !recordsContainer.isAtEnd {
                if let decoded = try? recordsContainer.decode(CanonicalChecksumCacheRecord.self) {
                    decodedRecords.append(decoded)
                } else {
                    _ = try? recordsContainer.decode(IgnoredCorruptRecord.self)
                }
            }
            records = decodedRecords
        }
    }

    private struct IgnoredCorruptRecord: Decodable {}

    private struct PersistResult {
        var writeResult: CanonicalChecksumCacheWriteResult
        var records: [String: CanonicalChecksumCacheRecord]
    }

    private var loadedURL: URL?
    private var recordsByToken: [String: CanonicalChecksumCacheRecord] = [:]
    private var cacheCorrupted = false

    init() {}

    func checksum(
        fileURL: URL,
        logicalToken: String?,
        nodeRole: CanonicalInventoryRuntimeNodeRole,
        cacheDirectoryURL: URL,
        configuration: CanonicalInventoryRuntimeConfiguration = CanonicalInventoryRuntimeConfiguration(),
        now: Date = Date(),
        clock: CanonicalInventoryRuntimeClock = .system,
        metadataProvider: (@Sendable (URL) -> CanonicalChecksumFileMetadata?)? = nil,
        hashProvider: (@Sendable (URL) async throws -> String)? = nil
    ) async -> CanonicalChecksumCacheResult {
        let standardizedURL = fileURL.standardizedFileURL
        guard let metadata = metadataProvider?(standardizedURL) ?? Self.fileMetadata(for: standardizedURL) else {
            return CanonicalChecksumCacheResult(
                sha256: nil,
                byteSize: 0,
                modifiedAt: Date(timeIntervalSince1970: 0),
                event: .error,
                hashComputed: false,
                hashUnavailable: true,
                failure: .fileMetadataUnavailable,
                hashDurationMs: 0,
                cacheLoadDurationMs: 0,
                cacheWriteDurationMs: 0,
                cachePruneDurationMs: 0,
                cachePersisted: false,
                cachePrunedRecordCount: 0,
                cacheRecordCount: recordsByToken.count,
                cacheByteCount: 0,
                validationState: .unavailable,
                mainActorHashAttemptCount: 0,
                redactionViolationCount: 0
            )
        }
        let safeToken = Self.safeLogicalToken(logicalToken) ?? Self.safeLogicalToken(standardizedURL.lastPathComponent) ?? "unknown-file"
        let key = CanonicalChecksumCacheKey(
            logicalToken: safeToken,
            byteSize: metadata.byteSize,
            modifiedAtEpochMs: Self.epochMs(metadata.modifiedAt),
            contentVersion: Self.safeOptionalToken(metadata.contentVersion),
            hashAlgorithm: configuration.hashAlgorithm,
            schemaVersion: configuration.checksumSchemaVersion,
            nodeRole: nodeRole,
            storeNamespace: Self.safeOptionalToken(configuration.cacheStoreNamespace)
        )
        let cacheURL = cacheDirectoryURL.appendingPathComponent(configuration.cacheFileName, isDirectory: false)
        let loadDiagnostics = await loadIfNeeded(
            cacheURL: cacheURL,
            schemaVersion: configuration.checksumSchemaVersion,
            clock: clock
        )

        if configuration.persistentChecksumCacheEnabled,
           let existing = recordsByToken[safeToken],
           existing.key == key,
           existing.validationState == .valid {
            return CanonicalChecksumCacheResult(
                sha256: existing.hashValue,
                byteSize: key.byteSize,
                modifiedAt: metadata.modifiedAt,
                event: .hit,
                hashComputed: false,
                hashUnavailable: false,
                failure: nil,
                hashDurationMs: 0,
                cacheLoadDurationMs: loadDiagnostics.cacheLoadDurationMs,
                cacheWriteDurationMs: 0,
                cachePruneDurationMs: 0,
                cachePersisted: false,
                cachePrunedRecordCount: 0,
                cacheRecordCount: recordsByToken.count,
                cacheByteCount: loadDiagnostics.cacheByteCount,
                validationState: .valid,
                mainActorHashAttemptCount: 0,
                redactionViolationCount: 0
            )
        }

        let event: CanonicalChecksumCacheEvent = recordsByToken[safeToken] == nil ? .miss : .stale
        let mainActorHashAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
        let hashStartedAt = clock.now()
        do {
            try Task.checkCancellation()
            let sha256 = try await (hashProvider ?? Self.sha256Hex)(standardizedURL)
            try Task.checkCancellation()
            let hashDurationMs = max(0, Int(clock.now().timeIntervalSince(hashStartedAt) * 1_000))
            let record = CanonicalChecksumCacheRecord(
                key: key,
                hashAlgorithm: configuration.hashAlgorithm,
                hashValue: sha256,
                hashPrefix: String(sha256.prefix(12)),
                byteSize: key.byteSize,
                modifiedAtEpochMs: key.modifiedAtEpochMs,
                computedAt: now,
                schemaVersion: configuration.checksumSchemaVersion,
                sourceRole: nodeRole,
                validationState: .valid
            )
            var writeResult = CanonicalChecksumCacheWriteResult(
                persisted: false,
                prunedRecordCount: 0,
                cacheWriteDurationMs: 0,
                cachePruneDurationMs: 0,
                cacheByteCount: 0,
                failure: nil
            )
            if configuration.persistentChecksumCacheEnabled {
                recordsByToken[safeToken] = record
                let persisted = persist(
                    cacheURL: cacheURL,
                    schemaVersion: configuration.checksumSchemaVersion,
                    configuration: configuration,
                    clock: clock
                )
                recordsByToken = persisted.records
                writeResult = persisted.writeResult
            }
            return CanonicalChecksumCacheResult(
                sha256: sha256,
                byteSize: key.byteSize,
                modifiedAt: metadata.modifiedAt,
                event: event,
                hashComputed: true,
                hashUnavailable: false,
                failure: writeResult.failure ?? (cacheCorrupted ? .cacheCorrupted : nil),
                hashDurationMs: hashDurationMs,
                cacheLoadDurationMs: loadDiagnostics.cacheLoadDurationMs,
                cacheWriteDurationMs: writeResult.cacheWriteDurationMs,
                cachePruneDurationMs: writeResult.cachePruneDurationMs,
                cachePersisted: writeResult.persisted,
                cachePrunedRecordCount: writeResult.prunedRecordCount,
                cacheRecordCount: recordsByToken.count,
                cacheByteCount: writeResult.cacheByteCount,
                validationState: writeResult.failure == nil ? .valid : .writeFailed,
                mainActorHashAttemptCount: mainActorHashAttemptCount,
                redactionViolationCount: 0
            )
        } catch is CancellationError {
            return CanonicalChecksumCacheResult(
                sha256: nil,
                byteSize: key.byteSize,
                modifiedAt: metadata.modifiedAt,
                event: .error,
                hashComputed: false,
                hashUnavailable: true,
                failure: .cancelled,
                hashDurationMs: max(0, Int(clock.now().timeIntervalSince(hashStartedAt) * 1_000)),
                cacheLoadDurationMs: loadDiagnostics.cacheLoadDurationMs,
                cacheWriteDurationMs: 0,
                cachePruneDurationMs: 0,
                cachePersisted: false,
                cachePrunedRecordCount: 0,
                cacheRecordCount: recordsByToken.count,
                cacheByteCount: loadDiagnostics.cacheByteCount,
                validationState: .unavailable,
                mainActorHashAttemptCount: mainActorHashAttemptCount,
                redactionViolationCount: 0
            )
        } catch {
            return CanonicalChecksumCacheResult(
                sha256: nil,
                byteSize: key.byteSize,
                modifiedAt: metadata.modifiedAt,
                event: .error,
                hashComputed: false,
                hashUnavailable: true,
                failure: .hashUnavailable,
                hashDurationMs: max(0, Int(clock.now().timeIntervalSince(hashStartedAt) * 1_000)),
                cacheLoadDurationMs: loadDiagnostics.cacheLoadDurationMs,
                cacheWriteDurationMs: 0,
                cachePruneDurationMs: 0,
                cachePersisted: false,
                cachePrunedRecordCount: 0,
                cacheRecordCount: recordsByToken.count,
                cacheByteCount: loadDiagnostics.cacheByteCount,
                validationState: .unavailable,
                mainActorHashAttemptCount: mainActorHashAttemptCount,
                redactionViolationCount: 0
            )
        }
    }

    func reset(cacheDirectoryURL: URL, configuration: CanonicalInventoryRuntimeConfiguration = CanonicalInventoryRuntimeConfiguration()) {
        let cacheURL = cacheDirectoryURL.appendingPathComponent(configuration.cacheFileName, isDirectory: false)
        recordsByToken = [:]
        loadedURL = cacheURL
        cacheCorrupted = false
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func loadIfNeeded(
        cacheURL: URL,
        schemaVersion: Int,
        clock: CanonicalInventoryRuntimeClock
    ) async -> CanonicalChecksumCacheDiagnostics {
        let startedAt = clock.now()
        guard loadedURL != cacheURL else {
            return CanonicalChecksumCacheDiagnostics(
                cacheHitCount: 0,
                cacheMissCount: 0,
                cacheStaleCount: 0,
                cacheErrorCount: 0,
                cacheLoadDurationMs: 0,
                cacheWriteDurationMs: 0,
                cachePruneDurationMs: 0,
                recordsLoadedCount: recordsByToken.count,
                recordsPrunedCount: 0,
                cacheByteCount: Self.cacheByteCount(cacheURL),
                redactionViolationCount: 0
            )
        }
        loadedURL = cacheURL
        recordsByToken = [:]
        cacheCorrupted = false
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return CanonicalChecksumCacheDiagnostics(
                cacheHitCount: 0,
                cacheMissCount: 0,
                cacheStaleCount: 0,
                cacheErrorCount: 0,
                cacheLoadDurationMs: max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000)),
                cacheWriteDurationMs: 0,
                cachePruneDurationMs: 0,
                recordsLoadedCount: 0,
                recordsPrunedCount: 0,
                cacheByteCount: 0,
                redactionViolationCount: 0
            )
        }
        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(CacheFile.self, from: data)
            guard decoded.schemaVersion == schemaVersion else {
                cacheCorrupted = true
                return CanonicalChecksumCacheDiagnostics(
                    cacheHitCount: 0,
                    cacheMissCount: 0,
                    cacheStaleCount: 0,
                    cacheErrorCount: 1,
                    cacheLoadDurationMs: max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000)),
                    cacheWriteDurationMs: 0,
                    cachePruneDurationMs: 0,
                    recordsLoadedCount: 0,
                    recordsPrunedCount: 0,
                    cacheByteCount: data.count,
                    redactionViolationCount: 0
                )
            }
            recordsByToken = Dictionary(
                decoded.records.filter { $0.validationState == .valid }.map { ($0.key.logicalToken, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            return CanonicalChecksumCacheDiagnostics(
                cacheHitCount: 0,
                cacheMissCount: 0,
                cacheStaleCount: 0,
                cacheErrorCount: decoded.records.count == recordsByToken.count ? 0 : 1,
                cacheLoadDurationMs: max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000)),
                cacheWriteDurationMs: 0,
                cachePruneDurationMs: 0,
                recordsLoadedCount: recordsByToken.count,
                recordsPrunedCount: 0,
                cacheByteCount: data.count,
                redactionViolationCount: 0
            )
        } catch {
            cacheCorrupted = true
            recordsByToken = [:]
            return CanonicalChecksumCacheDiagnostics(
                cacheHitCount: 0,
                cacheMissCount: 0,
                cacheStaleCount: 0,
                cacheErrorCount: 1,
                cacheLoadDurationMs: max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000)),
                cacheWriteDurationMs: 0,
                cachePruneDurationMs: 0,
                recordsLoadedCount: 0,
                recordsPrunedCount: 0,
                cacheByteCount: Self.cacheByteCount(cacheURL),
                redactionViolationCount: 0
            )
        }
    }

    private func persist(
        cacheURL: URL,
        schemaVersion: Int,
        configuration: CanonicalInventoryRuntimeConfiguration,
        clock: CanonicalInventoryRuntimeClock
    ) -> PersistResult {
        let pruneStartedAt = clock.now()
        let originalCount = recordsByToken.count
        var prunedRecords = Self.pruned(recordsByToken: recordsByToken, maxRecords: configuration.maxCacheRecords)
        var encodedData = Self.encodedCacheData(schemaVersion: schemaVersion, records: prunedRecords)
        while encodedData.count > configuration.maxCacheBytes, prunedRecords.count > 1 {
            let oldestToken = prunedRecords.values
                .sorted { $0.computedAt < $1.computedAt }
                .first?
                .key
                .logicalToken
            if let oldestToken {
                prunedRecords.removeValue(forKey: oldestToken)
                encodedData = Self.encodedCacheData(schemaVersion: schemaVersion, records: prunedRecords)
            } else {
                break
            }
        }
        let pruneDurationMs = max(0, Int(clock.now().timeIntervalSince(pruneStartedAt) * 1_000))
        let writeStartedAt = clock.now()
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encodedData.write(to: cacheURL, options: .atomic)
            return PersistResult(
                writeResult: CanonicalChecksumCacheWriteResult(
                    persisted: true,
                    prunedRecordCount: max(0, originalCount - prunedRecords.count),
                    cacheWriteDurationMs: max(0, Int(clock.now().timeIntervalSince(writeStartedAt) * 1_000)),
                    cachePruneDurationMs: pruneDurationMs,
                    cacheByteCount: encodedData.count,
                    failure: nil
                ),
                records: prunedRecords
            )
        } catch {
            return PersistResult(
                writeResult: CanonicalChecksumCacheWriteResult(
                    persisted: false,
                    prunedRecordCount: max(0, originalCount - prunedRecords.count),
                    cacheWriteDurationMs: max(0, Int(clock.now().timeIntervalSince(writeStartedAt) * 1_000)),
                    cachePruneDurationMs: pruneDurationMs,
                    cacheByteCount: encodedData.count,
                    failure: .cacheWriteFailed
                ),
                records: prunedRecords
            )
        }
    }

    private static func sha256Hex(fileURL: URL) async throws -> String {
        try await Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer {
                try? handle.close()
            }
            var hasher = SHA256()
            while true {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
                if chunk.isEmpty {
                    break
                }
                hasher.update(data: chunk)
            }
            return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
        }.value
    }

    private static func fileMetadata(for url: URL) -> CanonicalChecksumFileMetadata? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sizeNumber = attributes[.size] as? NSNumber else {
            return nil
        }
        let modifiedAt = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return CanonicalChecksumFileMetadata(byteSize: sizeNumber.int64Value, modifiedAt: modifiedAt)
    }

    private static func safeLogicalToken(_ token: String?) -> String? {
        guard let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              !trimmed.hasPrefix("/"),
              !trimmed.contains("://"),
              !trimmed.contains("\\") else {
            return nil
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return trimmed
    }

    private static func safeOptionalToken(_ token: String?) -> String? {
        safeLogicalToken(token)
    }

    private static func epochMs(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func pruned(
        recordsByToken: [String: CanonicalChecksumCacheRecord],
        maxRecords: Int
    ) -> [String: CanonicalChecksumCacheRecord] {
        guard recordsByToken.count > maxRecords else {
            return recordsByToken
        }
        let kept = recordsByToken.values
            .sorted { $0.computedAt > $1.computedAt }
            .prefix(maxRecords)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key.logicalToken, $0) })
    }

    private static func encodedCacheData(
        schemaVersion: Int,
        records: [String: CanonicalChecksumCacheRecord]
    ) -> Data {
        let payload = CacheFile(
            schemaVersion: schemaVersion,
            records: records.values.sorted { $0.key.logicalToken < $1.key.logicalToken }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(payload)) ?? Data("{}".utf8)
    }

    private static func cacheByteCount(_ cacheURL: URL) -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return size.intValue
    }
}

nonisolated struct CanonicalInventoryPerformanceBudget: Codable, Equatable, Sendable {
    var smallLibraryExpectedBuildDurationMs: Int
    var mediumLibraryExpectedBuildDurationMs: Int
    var largeLibraryWarningThresholdMs: Int
    var cacheHitRatioWarningThreshold: Double
    var duplicateBuildWarningThreshold: Int
    var mainActorAttemptThreshold: Int

    nonisolated init(
        smallLibraryExpectedBuildDurationMs: Int = 500,
        mediumLibraryExpectedBuildDurationMs: Int = 2_000,
        largeLibraryWarningThresholdMs: Int = 5_000,
        cacheHitRatioWarningThreshold: Double = 0.50,
        duplicateBuildWarningThreshold: Int = 0,
        mainActorAttemptThreshold: Int = 0
    ) {
        self.smallLibraryExpectedBuildDurationMs = smallLibraryExpectedBuildDurationMs
        self.mediumLibraryExpectedBuildDurationMs = mediumLibraryExpectedBuildDurationMs
        self.largeLibraryWarningThresholdMs = largeLibraryWarningThresholdMs
        self.cacheHitRatioWarningThreshold = cacheHitRatioWarningThreshold
        self.duplicateBuildWarningThreshold = duplicateBuildWarningThreshold
        self.mainActorAttemptThreshold = mainActorAttemptThreshold
    }
}

nonisolated struct CanonicalInventoryPerformanceReport: Codable, Equatable, Sendable {
    var syncRunID: String
    var nodeRole: CanonicalInventoryRuntimeNodeRole
    var inventoryBuildDurationMs: Int
    var cacheHitRatio: Double
    var duplicateBuildCount: Int
    var mainActorAttemptCount: Int
    var warnings: [String]
    var blockers: [String]
    var redacted: Bool
}

nonisolated enum CanonicalInventoryPerformanceRegressionGuard {
    nonisolated static func evaluate(
        snapshot: CanonicalInventoryRuntimeSnapshot,
        budget: CanonicalInventoryPerformanceBudget = CanonicalInventoryPerformanceBudget()
    ) -> CanonicalInventoryPerformanceReport {
        let report = CanonicalInventoryRuntimeReportExporter.report(from: snapshot)
        let cacheTotal = report.cacheHitCount + report.cacheMissCount + report.cacheStaleCount + report.cacheErrorCount
        let hitRatio = cacheTotal == 0 ? 1.0 : Double(report.cacheHitCount) / Double(cacheTotal)
        let mainActorAttemptCount = report.mainActorHashAttemptCount
            + report.mainActorScanAttemptCount
            + report.mainActorMetadataLoadAttemptCount
            + report.mainActorJobsLoadAttemptCount
            + report.mainActorManifestBuildAttemptCount
        var warnings: [String] = []
        var blockers: [String] = []

        if report.buildDurationMs > budget.largeLibraryWarningThresholdMs {
            warnings.append("inventoryBuildDurationMs")
        }
        if hitRatio < budget.cacheHitRatioWarningThreshold {
            warnings.append("cacheHitRatioLow")
        }
        if report.duplicateBuildCount > budget.duplicateBuildWarningThreshold {
            warnings.append("duplicateBuildCount")
        }
        if mainActorAttemptCount > budget.mainActorAttemptThreshold {
            blockers.append("mainActorAttemptCount")
        }
        if report.redactionViolationCount > 0 {
            blockers.append("redactionViolationCount")
        }

        return CanonicalInventoryPerformanceReport(
            syncRunID: report.syncRunID,
            nodeRole: report.nodeRole,
            inventoryBuildDurationMs: report.buildDurationMs,
            cacheHitRatio: hitRatio,
            duplicateBuildCount: report.duplicateBuildCount,
            mainActorAttemptCount: mainActorAttemptCount,
            warnings: warnings,
            blockers: blockers,
            redacted: report.redacted
        )
    }
}

typealias CanonicalChecksumCache = CanonicalChecksumCacheStore
