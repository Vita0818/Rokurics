//
//  CanonicalChecksumRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated struct CanonicalFileChecksumCacheKey: Codable, Equatable, Hashable, Sendable {
    var rootToken: CanonicalRootToken
    var logicalToken: String
    var byteSize: Int64
    var modifiedAtEpochMs: Int64
    var contentVersion: String?
    var schemaVersion: String
    var algorithm: String
    var domainHint: CanonicalFileDomainHint
}

nonisolated struct CanonicalFileChecksumCacheRecord: Codable, Equatable, Sendable {
    var key: CanonicalFileChecksumCacheKey
    var fullHash: String
    var hashPrefix: String
    var computedAt: CanonicalTimestamp
    var validationState: CanonicalChecksumCacheValidationState
}

nonisolated struct CanonicalFileChecksumRequest: Sendable {
    var key: CanonicalFileChecksumCacheKey
    var hashProvider: @Sendable () async throws -> String

    nonisolated init(
        rootToken: CanonicalRootToken,
        logicalToken: String,
        byteSize: Int64,
        modifiedAt: Date,
        contentVersion: String? = nil,
        schemaVersion: String = "canonical-file-checksum-v910",
        algorithm: String = "sha256",
        domainHint: CanonicalFileDomainHint = .unknown,
        hashProvider: @escaping @Sendable () async throws -> String
    ) throws {
        self.key = CanonicalFileChecksumCacheKey(
            rootToken: rootToken,
            logicalToken: try CanonicalFileRuntimeTokenValidator.safeLogicalToken(logicalToken),
            byteSize: max(0, byteSize),
            modifiedAtEpochMs: Int64((modifiedAt.timeIntervalSince1970 * 1_000).rounded()),
            contentVersion: CanonicalFileRuntimeTokenValidator.safeOptionalToken(contentVersion),
            schemaVersion: CanonicalKernelStringSanitizer.required(schemaVersion, fallback: "canonical-file-checksum-v910"),
            algorithm: CanonicalKernelStringSanitizer.required(algorithm, fallback: "sha256"),
            domainHint: domainHint
        )
        self.hashProvider = hashProvider
    }
}

nonisolated struct CanonicalFileChecksumRuntimeResult: Codable, Equatable, Sendable {
    var event: CanonicalChecksumCacheEvent
    var validationState: CanonicalChecksumCacheValidationState
    var hashPrefix: String?
    var fullHashForProtocolUse: String?
    var hashComputed: Bool
    var failure: CanonicalInventoryRuntimeFailure?
    var durationMs: Int
    var mainActorHashAttemptCount: Int
}

actor CanonicalFileChecksumRuntime {
    private var recordsByToken: [String: CanonicalFileChecksumCacheRecord] = [:]
    private let clock: CanonicalInventoryRuntimeClock
    private let persistentCache: CanonicalChecksumCacheStore

    init(
        clock: CanonicalInventoryRuntimeClock = .system,
        persistentCache: CanonicalChecksumCacheStore = CanonicalChecksumCacheStore()
    ) {
        self.clock = clock
        self.persistentCache = persistentCache
    }

    func lookup(_ key: CanonicalFileChecksumCacheKey) -> CanonicalChecksumLookupResult {
        guard let record = recordsByToken[key.logicalToken] else {
            return CanonicalChecksumLookupResult(state: .miss)
        }
        guard record.validationState == .valid, Self.isPlausibleHash(record.fullHash, algorithm: key.algorithm) else {
            recordsByToken[key.logicalToken] = nil
            return CanonicalChecksumLookupResult(state: .stale)
        }
        guard record.key == key else {
            return CanonicalChecksumLookupResult(
                state: .stale,
                record: CanonicalChecksumCacheRecord(
                    key: key.legacyInventoryKey,
                    hashAlgorithm: key.algorithm,
                    hashValue: record.fullHash,
                    hashPrefix: record.hashPrefix,
                    byteSize: key.byteSize,
                    modifiedAtEpochMs: key.modifiedAtEpochMs,
                    computedAt: record.computedAt.date,
                    schemaVersion: 0,
                    sourceRole: .iPhone,
                    validationState: .stale
                )
            )
        }
        return CanonicalChecksumLookupResult(
            state: .hit,
            record: CanonicalChecksumCacheRecord(
                key: key.legacyInventoryKey,
                hashAlgorithm: key.algorithm,
                hashValue: record.fullHash,
                hashPrefix: record.hashPrefix,
                byteSize: key.byteSize,
                modifiedAtEpochMs: key.modifiedAtEpochMs,
                computedAt: record.computedAt.date,
                schemaVersion: 0,
                sourceRole: .iPhone,
                validationState: .valid
            )
        )
    }

    func checksum(_ request: CanonicalFileChecksumRequest) async -> CanonicalFileChecksumRuntimeResult {
        let startedAt = clock.now()
        let mainActorHashAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
        let existing = recordsByToken[request.key.logicalToken]
        if let existing, existing.key == request.key, existing.validationState == .valid, Self.isPlausibleHash(existing.fullHash, algorithm: request.key.algorithm) {
            return CanonicalFileChecksumRuntimeResult(
                event: .hit,
                validationState: .valid,
                hashPrefix: existing.hashPrefix,
                fullHashForProtocolUse: existing.fullHash,
                hashComputed: false,
                failure: nil,
                durationMs: max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000)),
                mainActorHashAttemptCount: 0
            )
        }

        let hadCorruptedRecord = existing.map { !Self.isPlausibleHash($0.fullHash, algorithm: request.key.algorithm) || $0.validationState == .corrupted } ?? false
        if hadCorruptedRecord {
            recordsByToken[request.key.logicalToken] = nil
        }
        let event: CanonicalChecksumCacheEvent = existing == nil || hadCorruptedRecord ? .miss : .stale
        do {
            let fullHash = try await request.hashProvider()
            guard Self.isPlausibleHash(fullHash, algorithm: request.key.algorithm) else {
                return CanonicalFileChecksumRuntimeResult(
                    event: .error,
                    validationState: .corrupted,
                    hashPrefix: nil,
                    fullHashForProtocolUse: nil,
                    hashComputed: true,
                    failure: .hashUnavailable,
                    durationMs: max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000)),
                    mainActorHashAttemptCount: mainActorHashAttemptCount
                )
            }
            let normalized = fullHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let record = CanonicalFileChecksumCacheRecord(
                key: request.key,
                fullHash: normalized,
                hashPrefix: String(normalized.prefix(12)),
                computedAt: CanonicalTimestamp(clock.now()),
                validationState: .valid
            )
            recordsByToken[request.key.logicalToken] = record
            return CanonicalFileChecksumRuntimeResult(
                event: event,
                validationState: .valid,
                hashPrefix: record.hashPrefix,
                fullHashForProtocolUse: record.fullHash,
                hashComputed: true,
                failure: hadCorruptedRecord ? .cacheCorrupted : nil,
                durationMs: max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000)),
                mainActorHashAttemptCount: mainActorHashAttemptCount
            )
        } catch is CancellationError {
            return CanonicalFileChecksumRuntimeResult(
                event: .error,
                validationState: .unavailable,
                hashPrefix: nil,
                fullHashForProtocolUse: nil,
                hashComputed: false,
                failure: .cancelled,
                durationMs: max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000)),
                mainActorHashAttemptCount: mainActorHashAttemptCount
            )
        } catch {
            return CanonicalFileChecksumRuntimeResult(
                event: .error,
                validationState: .unavailable,
                hashPrefix: nil,
                fullHashForProtocolUse: nil,
                hashComputed: false,
                failure: .hashUnavailable,
                durationMs: max(0, Int(clock.now().timeIntervalSince(startedAt) * 1_000)),
                mainActorHashAttemptCount: mainActorHashAttemptCount
            )
        }
    }

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
        await persistentCache.checksum(
            fileURL: fileURL,
            logicalToken: logicalToken,
            nodeRole: nodeRole,
            cacheDirectoryURL: cacheDirectoryURL,
            configuration: configuration,
            now: now,
            clock: clock,
            metadataProvider: metadataProvider,
            hashProvider: hashProvider
        )
    }

    func storeForTesting(_ record: CanonicalFileChecksumCacheRecord) {
        recordsByToken[record.key.logicalToken] = record
    }

    func reset() {
        recordsByToken = [:]
    }

    func resetPersistentCache(
        cacheDirectoryURL: URL,
        configuration: CanonicalInventoryRuntimeConfiguration = CanonicalInventoryRuntimeConfiguration()
    ) async {
        await persistentCache.reset(cacheDirectoryURL: cacheDirectoryURL, configuration: configuration)
    }

    private nonisolated static func isPlausibleHash(_ value: String, algorithm: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard algorithm.lowercased() == "sha256" else {
            return !normalized.isEmpty
        }
        return normalized.count == 64
            && normalized.unicodeScalars.allSatisfy { scalar in
                CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
            }
    }
}

typealias CanonicalChecksumRuntime = CanonicalFileChecksumRuntime

private extension CanonicalFileChecksumCacheKey {
    var legacyInventoryKey: CanonicalChecksumCacheKey {
        CanonicalChecksumCacheKey(
            logicalToken: "\(rootToken.rawValue):\(logicalToken):\(domainHint.rawValue)",
            byteSize: byteSize,
            modifiedAtEpochMs: modifiedAtEpochMs,
            contentVersion: contentVersion,
            hashAlgorithm: algorithm,
            schemaVersion: Int(schemaVersion.filter(\.isNumber)) ?? 0,
            nodeRole: .iPhone,
            storeNamespace: rootToken.rawValue
        )
    }
}
