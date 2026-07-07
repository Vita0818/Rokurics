//
//  CanonicalRealDataShadowCopy.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/3.
//

import Foundation

nonisolated enum CanonicalRealDataShadowCopyKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case studyMetadata
    case receiveRecord
    case generatedArtifact
    case audioDescriptor
    case audioBytes
}

nonisolated enum CanonicalRealDataShadowCopyBytesMode: String, Codable, Equatable, Hashable, Sendable {
    case inlineBytes
    case fileBytes
    case descriptorOnly
}

nonisolated enum CanonicalRealDataShadowCopyHashPolicy: String, Codable, Equatable, Hashable, Sendable {
    case useProvidedHash
    case computeIfBounded
    case hashUnavailable
}

nonisolated enum CanonicalRealDataShadowCopyCleanupPolicy: Equatable, Sendable {
    case cleanupImmediately
    case retainForDiagnostics(maxAge: TimeInterval, maxBytes: Int64)
    case cleanupOnNextLaunch
}

extension CanonicalRealDataShadowCopyCleanupPolicy: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case maxAge
        case maxBytes
    }

    private enum Kind: String, Codable {
        case cleanupImmediately
        case retainForDiagnostics
        case cleanupOnNextLaunch
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .cleanupImmediately:
            self = .cleanupImmediately
        case .retainForDiagnostics:
            self = .retainForDiagnostics(
                maxAge: try container.decode(TimeInterval.self, forKey: .maxAge),
                maxBytes: try container.decode(Int64.self, forKey: .maxBytes)
            )
        case .cleanupOnNextLaunch:
            self = .cleanupOnNextLaunch
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cleanupImmediately:
            try container.encode(Kind.cleanupImmediately, forKey: .kind)
        case let .retainForDiagnostics(maxAge, maxBytes):
            try container.encode(Kind.retainForDiagnostics, forKey: .kind)
            try container.encode(max(0, maxAge), forKey: .maxAge)
            try container.encode(max(0, maxBytes), forKey: .maxBytes)
        case .cleanupOnNextLaunch:
            try container.encode(Kind.cleanupOnNextLaunch, forKey: .kind)
        }
    }
}

nonisolated struct CanonicalRealDataShadowCopyPolicy: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var maxMetadataBytes: Int64
    var maxGeneratedArtifactBytes: Int64
    var maxAudioBytes: Int64
    var copyAudioBytesByDefault: Bool
    var allowHashComputationForBoundedBytes: Bool
    var requireHashForEqualityProof: Bool
    var cleanupPolicy: CanonicalRealDataShadowCopyCleanupPolicy

    nonisolated init(
        isEnabled: Bool = false,
        maxMetadataBytes: Int64 = 1 * 1024 * 1024,
        maxGeneratedArtifactBytes: Int64 = 512 * 1024,
        maxAudioBytes: Int64 = 8 * 1024 * 1024,
        copyAudioBytesByDefault: Bool = false,
        allowHashComputationForBoundedBytes: Bool = true,
        requireHashForEqualityProof: Bool = true,
        cleanupPolicy: CanonicalRealDataShadowCopyCleanupPolicy = .cleanupImmediately
    ) {
        self.isEnabled = isEnabled
        self.maxMetadataBytes = max(0, maxMetadataBytes)
        self.maxGeneratedArtifactBytes = max(0, maxGeneratedArtifactBytes)
        self.maxAudioBytes = max(0, maxAudioBytes)
        self.copyAudioBytesByDefault = copyAudioBytesByDefault
        self.allowHashComputationForBoundedBytes = allowHashComputationForBoundedBytes
        self.requireHashForEqualityProof = requireHashForEqualityProof
        self.cleanupPolicy = cleanupPolicy
    }

    nonisolated static let disabled = CanonicalRealDataShadowCopyPolicy()

    nonisolated static func enabled(
        cleanupPolicy: CanonicalRealDataShadowCopyCleanupPolicy = .cleanupImmediately
    ) -> CanonicalRealDataShadowCopyPolicy {
        CanonicalRealDataShadowCopyPolicy(isEnabled: true, cleanupPolicy: cleanupPolicy)
    }

    nonisolated func maxBytes(for kind: CanonicalRealDataShadowCopyKind) -> Int64 {
        switch kind {
        case .recordingMetadata, .studyMetadata, .receiveRecord, .audioDescriptor:
            return maxMetadataBytes
        case .generatedArtifact:
            return maxGeneratedArtifactBytes
        case .audioBytes:
            return copyAudioBytesByDefault ? maxAudioBytes : 0
        }
    }
}

nonisolated struct CanonicalRealDataShadowCopySource: Equatable, Sendable {
    var sourceID: String
    var kind: CanonicalRealDataShadowCopyKind
    var logicalName: String
    var targetLogicalPathToken: String
    var productionRootURL: URL?
    var sourceURL: URL?
    var inlineBytes: Data?
    var byteSize: Int64?
    var modifiedAt: Date?
    var contentHash: CanonicalHash?
    var bytesMode: CanonicalRealDataShadowCopyBytesMode
    var hashPolicy: CanonicalRealDataShadowCopyHashPolicy

    nonisolated init(
        sourceID: String,
        kind: CanonicalRealDataShadowCopyKind,
        logicalName: String,
        targetLogicalPathToken: String,
        productionRootURL: URL? = nil,
        sourceURL: URL? = nil,
        inlineBytes: Data? = nil,
        byteSize: Int64? = nil,
        modifiedAt: Date? = nil,
        contentHash: CanonicalHash? = nil,
        bytesMode: CanonicalRealDataShadowCopyBytesMode,
        hashPolicy: CanonicalRealDataShadowCopyHashPolicy = .computeIfBounded
    ) {
        self.sourceID = CanonicalProductionRedaction.safeIdentifier(sourceID, fallback: "source")
        self.kind = kind
        self.logicalName = CanonicalProjectionContract.logicalName(from: logicalName) ?? kind.rawValue
        self.targetLogicalPathToken = targetLogicalPathToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.productionRootURL = productionRootURL?.standardizedFileURL
        self.sourceURL = sourceURL?.standardizedFileURL
        self.inlineBytes = inlineBytes
        self.byteSize = byteSize.map { max(0, $0) }
        self.modifiedAt = modifiedAt
        self.contentHash = contentHash
        self.bytesMode = bytesMode
        self.hashPolicy = hashPolicy
    }

    nonisolated static func inline(
        sourceID: String,
        kind: CanonicalRealDataShadowCopyKind,
        logicalName: String,
        targetLogicalPathToken: String,
        bytes: Data,
        contentHash: CanonicalHash? = nil,
        modifiedAt: Date? = nil
    ) -> CanonicalRealDataShadowCopySource {
        CanonicalRealDataShadowCopySource(
            sourceID: sourceID,
            kind: kind,
            logicalName: logicalName,
            targetLogicalPathToken: targetLogicalPathToken,
            inlineBytes: bytes,
            byteSize: Int64(bytes.count),
            modifiedAt: modifiedAt,
            contentHash: contentHash,
            bytesMode: .inlineBytes
        )
    }

    nonisolated static func file(
        sourceID: String,
        kind: CanonicalRealDataShadowCopyKind,
        logicalName: String,
        targetLogicalPathToken: String,
        productionRootURL: URL,
        sourceURL: URL,
        byteSize: Int64? = nil,
        modifiedAt: Date? = nil,
        contentHash: CanonicalHash? = nil
    ) -> CanonicalRealDataShadowCopySource {
        CanonicalRealDataShadowCopySource(
            sourceID: sourceID,
            kind: kind,
            logicalName: logicalName,
            targetLogicalPathToken: targetLogicalPathToken,
            productionRootURL: productionRootURL,
            sourceURL: sourceURL,
            byteSize: byteSize,
            modifiedAt: modifiedAt,
            contentHash: contentHash,
            bytesMode: .fileBytes
        )
    }

    nonisolated static func descriptor(
        sourceID: String,
        logicalName: String,
        targetLogicalPathToken: String,
        descriptorBytes: Data,
        byteSize: Int64? = nil,
        contentHash: CanonicalHash? = nil
    ) -> CanonicalRealDataShadowCopySource {
        CanonicalRealDataShadowCopySource(
            sourceID: sourceID,
            kind: .audioDescriptor,
            logicalName: logicalName,
            targetLogicalPathToken: targetLogicalPathToken,
            inlineBytes: descriptorBytes,
            byteSize: byteSize,
            contentHash: contentHash,
            bytesMode: .descriptorOnly,
            hashPolicy: .hashUnavailable
        )
    }
}

nonisolated struct CanonicalRealDataShadowCopyTarget: Equatable, Sendable {
    var rootToken: CanonicalRootToken
    var rootKind: CanonicalShadowRootKind
    var rootURL: URL
    var prohibitedProductionRootURL: URL?

    nonisolated init(
        rootToken: CanonicalRootToken,
        rootKind: CanonicalShadowRootKind = .shadowCopy,
        rootURL: URL,
        prohibitedProductionRootURL: URL? = nil
    ) {
        self.rootToken = rootToken
        self.rootKind = rootKind
        self.rootURL = rootURL.standardizedFileURL
        self.prohibitedProductionRootURL = prohibitedProductionRootURL?.standardizedFileURL
    }

    nonisolated var binding: CanonicalShadowRootBinding {
        CanonicalShadowRootBinding(
            rootToken: rootToken,
            rootKind: rootKind,
            rootURL: rootURL,
            prohibitedProductionRootURL: prohibitedProductionRootURL
        )
    }
}

nonisolated struct CanonicalRealDataShadowCopyPlan: Equatable, Sendable {
    var planID: String
    var sources: [CanonicalRealDataShadowCopySource]
    var target: CanonicalRealDataShadowCopyTarget
    var policy: CanonicalRealDataShadowCopyPolicy

    nonisolated init(
        planID: String = UUID().uuidString,
        sources: [CanonicalRealDataShadowCopySource],
        target: CanonicalRealDataShadowCopyTarget,
        policy: CanonicalRealDataShadowCopyPolicy = .enabled()
    ) {
        self.planID = CanonicalProductionRedaction.safeIdentifier(planID, fallback: "real-data-shadow-copy")
        self.sources = sources.sorted { $0.sourceID < $1.sourceID }
        self.target = target
        self.policy = policy
    }
}

nonisolated enum CanonicalRealDataShadowCopyFailure: String, Codable, Equatable, Hashable, Sendable {
    case disabled
    case sourceEqualsTarget
    case targetIsProductionRoot
    case targetInsideProductionRoot
    case targetPathInvalid
    case sourceOutsideProductionRoot
    case unsafeLogicalPathToken
    case sourceReadFailed
    case sourceTooLarge
    case writeFailed
    case verificationFailed
    case hashMismatch
    case hashUnavailableWhereRequired
    case cleanupFailed
    case unexpected
}

nonisolated enum CanonicalRealDataShadowCopyVerificationStatus: String, Codable, Equatable, Hashable, Sendable {
    case verified
    case evidenceOnly
    case hashUnavailable
    case mismatch
    case descriptorOnly
    case failed
}

nonisolated struct CanonicalRealDataShadowCopyVerification: Codable, Equatable, Identifiable, Sendable {
    var id: String { sourceID }

    var sourceID: String
    var kind: CanonicalRealDataShadowCopyKind
    var logicalName: String
    var byteSize: Int64
    var modifiedAt: CanonicalTimestamp?
    var hashPrefix: String?
    var copiedBytes: Bool
    var descriptorOnly: Bool
    var equalityProof: Bool
    var status: CanonicalRealDataShadowCopyVerificationStatus
    var reason: String?

    nonisolated init(
        sourceID: String,
        kind: CanonicalRealDataShadowCopyKind,
        logicalName: String,
        byteSize: Int64,
        modifiedAt: Date? = nil,
        contentHash: CanonicalHash? = nil,
        copiedBytes: Bool,
        descriptorOnly: Bool,
        equalityProof: Bool,
        status: CanonicalRealDataShadowCopyVerificationStatus,
        reason: String? = nil
    ) {
        self.sourceID = CanonicalProductionRedaction.safeIdentifier(sourceID, fallback: "source")
        self.kind = kind
        self.logicalName = CanonicalProjectionContract.logicalName(from: logicalName) ?? kind.rawValue
        self.byteSize = max(0, byteSize)
        self.modifiedAt = modifiedAt.map(CanonicalTimestamp.init)
        self.hashPrefix = contentHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.copiedBytes = copiedBytes
        self.descriptorOnly = descriptorOnly
        self.equalityProof = equalityProof
        self.status = status
        self.reason = CanonicalShadowMigrationRedaction.safeText(reason)
    }
}

nonisolated struct CanonicalRealDataShadowCopyResult: Codable, Equatable, Sendable {
    var planID: String
    var rootID: String
    var rootKind: CanonicalShadowRootKind
    var started: Bool
    var completed: Bool
    var unavailable: Bool
    var verificationStatus: String
    var copiedEntryCount: Int
    var descriptorOnlyAudioCount: Int
    var bytesCopied: Int64
    var hashUnavailableCount: Int
    var equalityProofCount: Int
    var failure: CanonicalRealDataShadowCopyFailure?
    var failureReason: String?
    var verifications: [CanonicalRealDataShadowCopyVerification]

    nonisolated init(
        planID: String,
        rootID: String,
        rootKind: CanonicalShadowRootKind,
        started: Bool,
        completed: Bool,
        unavailable: Bool = false,
        failure: CanonicalRealDataShadowCopyFailure? = nil,
        failureReason: String? = nil,
        verifications: [CanonicalRealDataShadowCopyVerification] = []
    ) {
        self.planID = CanonicalProductionRedaction.safeIdentifier(planID, fallback: "real-data-shadow-copy")
        self.rootID = CanonicalProductionRedaction.safeIdentifier(rootID, fallback: "shadow-root")
        self.rootKind = rootKind
        self.started = started
        self.completed = completed
        self.unavailable = unavailable
        self.failure = failure
        self.failureReason = CanonicalShadowMigrationRedaction.safeText(failureReason)
        self.verifications = verifications.sorted { $0.sourceID < $1.sourceID }
        self.copiedEntryCount = verifications.filter(\.copiedBytes).count
        self.descriptorOnlyAudioCount = verifications.filter(\.descriptorOnly).count
        self.bytesCopied = verifications.filter(\.copiedBytes).reduce(0) { $0 + $1.byteSize }
        self.hashUnavailableCount = verifications.filter { $0.status == .hashUnavailable }.count
        self.equalityProofCount = verifications.filter(\.equalityProof).count
        if let failure {
            self.verificationStatus = failure.rawValue
        } else if verifications.contains(where: { $0.status == .mismatch || $0.status == .failed }) {
            self.verificationStatus = "failed"
        } else if verifications.contains(where: { $0.status == .hashUnavailable }) {
            self.verificationStatus = "hashUnavailable"
        } else if completed {
            self.verificationStatus = "verified"
        } else {
            self.verificationStatus = "notStarted"
        }
    }

    nonisolated static func unavailable(
        planID: String,
        rootID: String,
        rootKind: CanonicalShadowRootKind,
        failure: CanonicalRealDataShadowCopyFailure,
        reason: String
    ) -> CanonicalRealDataShadowCopyResult {
        CanonicalRealDataShadowCopyResult(
            planID: planID,
            rootID: rootID,
            rootKind: rootKind,
            started: false,
            completed: false,
            unavailable: true,
            failure: failure,
            failureReason: reason
        )
    }

    nonisolated var diagnosticsSummary: String {
        [
            "realDataCopy=\(completed ? "completed" : (unavailable ? "unavailable" : "failed"))",
            "rootKind=\(rootKind.rawValue)",
            "entries=\(copiedEntryCount)",
            "audioDescriptors=\(descriptorOnlyAudioCount)",
            "bytes=\(bytesCopied)",
            "hashUnavailable=\(hashUnavailableCount)",
            "equalityProofs=\(equalityProofCount)",
            "verification=\(verificationStatus)",
            "failure=\(failure?.rawValue ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalRealDataShadowCopyRunner: Sendable {
    nonisolated init() {}

    nonisolated func run(
        plan: CanonicalRealDataShadowCopyPlan,
        fileManager: FileManager = .default
    ) -> CanonicalRealDataShadowCopyResult {
        guard plan.policy.isEnabled else {
            return .unavailable(
                planID: plan.planID,
                rootID: plan.target.rootToken.rawValue,
                rootKind: plan.target.rootKind,
                failure: .disabled,
                reason: "realDataShadowCopyDisabled"
            )
        }

        do {
            let targetRoot = try validatedTargetRoot(plan.target)
            try fileManager.createDirectory(at: targetRoot, withIntermediateDirectories: true)
            var verifications: [CanonicalRealDataShadowCopyVerification] = []
            for source in plan.sources {
                let verification = try copy(source: source, targetRoot: targetRoot, policy: plan.policy, fileManager: fileManager)
                verifications.append(verification)
                if plan.policy.requireHashForEqualityProof,
                   verification.copiedBytes,
                   verification.status == .hashUnavailable {
                    return CanonicalRealDataShadowCopyResult(
                        planID: plan.planID,
                        rootID: plan.target.rootToken.rawValue,
                        rootKind: plan.target.rootKind,
                        started: true,
                        completed: false,
                        failure: .hashUnavailableWhereRequired,
                        failureReason: "hashUnavailableWhereRequired",
                        verifications: verifications
                    )
                }
            }
            return CanonicalRealDataShadowCopyResult(
                planID: plan.planID,
                rootID: plan.target.rootToken.rawValue,
                rootKind: plan.target.rootKind,
                started: true,
                completed: true,
                verifications: verifications
            )
        } catch let failure as RunnerFailure {
            return CanonicalRealDataShadowCopyResult(
                planID: plan.planID,
                rootID: plan.target.rootToken.rawValue,
                rootKind: plan.target.rootKind,
                started: true,
                completed: false,
                failure: failure.failure,
                failureReason: failure.reason,
                verifications: failure.verifications
            )
        } catch {
            return CanonicalRealDataShadowCopyResult(
                planID: plan.planID,
                rootID: plan.target.rootToken.rawValue,
                rootKind: plan.target.rootKind,
                started: true,
                completed: false,
                failure: .unexpected,
                failureReason: String(describing: error)
            )
        }
    }

    private nonisolated struct RunnerFailure: Error {
        var failure: CanonicalRealDataShadowCopyFailure
        var reason: String
        var verifications: [CanonicalRealDataShadowCopyVerification] = []
    }

    private nonisolated func validatedTargetRoot(_ target: CanonicalRealDataShadowCopyTarget) throws -> URL {
        do {
            return try target.binding.validatedShadowRootURL()
        } catch CanonicalProductionPortError.productionMutationAttempted(let reason) {
            let failure: CanonicalRealDataShadowCopyFailure = reason == "shadowRootInsideProductionRootRejected" ? .targetInsideProductionRoot : .targetIsProductionRoot
            throw RunnerFailure(failure: failure, reason: reason)
        } catch {
            throw RunnerFailure(failure: .targetPathInvalid, reason: String(describing: error))
        }
    }

    private nonisolated func copy(
        source: CanonicalRealDataShadowCopySource,
        targetRoot: URL,
        policy: CanonicalRealDataShadowCopyPolicy,
        fileManager: FileManager
    ) throws -> CanonicalRealDataShadowCopyVerification {
        guard let safeToken = CanonicalProjectionContract.safeLogicalPathToken(source.targetLogicalPathToken) else {
            throw RunnerFailure(failure: .unsafeLogicalPathToken, reason: "unsafeLogicalPathToken")
        }
        let destination = targetRoot.appendingPathComponent(safeToken, isDirectory: false).standardizedFileURL
        guard destination.path.hasPrefix(targetRoot.standardizedFileURL.path + "/") else {
            throw RunnerFailure(failure: .targetPathInvalid, reason: "targetPathEscape")
        }
        if let sourceURL = source.sourceURL?.standardizedFileURL {
            if sourceURL.path == destination.path {
                throw RunnerFailure(failure: .sourceEqualsTarget, reason: "sourceEqualsTarget")
            }
            if let productionRootURL = source.productionRootURL?.standardizedFileURL,
               !sourceURL.path.hasPrefix(productionRootURL.path + "/"),
               sourceURL.path != productionRootURL.path {
                throw RunnerFailure(failure: .sourceOutsideProductionRoot, reason: "sourceOutsideProductionRoot")
            }
        }

        let maxBytes = policy.maxBytes(for: source.kind)
        let descriptorOnly = source.bytesMode == .descriptorOnly || (source.kind == .audioBytes && !policy.copyAudioBytesByDefault)
        let loadedBytes: Data
        let copiedBytes: Bool
        if descriptorOnly, let inlineBytes = source.inlineBytes {
            loadedBytes = inlineBytes
            copiedBytes = true
        } else if source.bytesMode == .inlineBytes, let inlineBytes = source.inlineBytes {
            guard maxBytes == 0 || Int64(inlineBytes.count) <= maxBytes else {
                throw RunnerFailure(failure: .sourceTooLarge, reason: "sourceTooLarge")
            }
            loadedBytes = inlineBytes
            copiedBytes = true
        } else if source.bytesMode == .fileBytes, let sourceURL = source.sourceURL {
            let knownSize = source.byteSize ?? fileSize(at: sourceURL, fileManager: fileManager)
            guard maxBytes > 0, knownSize <= maxBytes else {
                throw RunnerFailure(failure: .sourceTooLarge, reason: "sourceTooLarge")
            }
            do {
                loadedBytes = try Data(contentsOf: sourceURL)
                copiedBytes = true
            } catch {
                throw RunnerFailure(failure: .sourceReadFailed, reason: "sourceReadFailed")
            }
        } else {
            throw RunnerFailure(failure: .sourceReadFailed, reason: "sourceBytesUnavailable")
        }

        do {
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try loadedBytes.write(to: destination, options: .atomic)
        } catch {
            throw RunnerFailure(failure: .writeFailed, reason: "writeFailed")
        }

        let actualBytes: Data
        do {
            actualBytes = try Data(contentsOf: destination)
        } catch {
            throw RunnerFailure(failure: .verificationFailed, reason: "verificationReadFailed")
        }
        guard actualBytes.count == loadedBytes.count else {
            throw RunnerFailure(failure: .verificationFailed, reason: "sizeMismatch")
        }

        let actualHash = hash(for: actualBytes, source: source, policy: policy)
        if let expectedHash = source.contentHash, let actualHash, expectedHash != actualHash {
            throw RunnerFailure(failure: .hashMismatch, reason: "hashMismatch")
        }
        let status: CanonicalRealDataShadowCopyVerificationStatus
        let equalityProof: Bool
        if descriptorOnly {
            status = .descriptorOnly
            equalityProof = false
        } else if actualHash != nil {
            status = .verified
            equalityProof = true
        } else {
            status = .hashUnavailable
            equalityProof = false
        }
        return CanonicalRealDataShadowCopyVerification(
            sourceID: source.sourceID,
            kind: source.kind,
            logicalName: source.logicalName,
            byteSize: Int64(actualBytes.count),
            modifiedAt: source.modifiedAt,
            contentHash: actualHash ?? source.contentHash,
            copiedBytes: copiedBytes,
            descriptorOnly: descriptorOnly,
            equalityProof: equalityProof,
            status: status,
            reason: status.rawValue
        )
    }

    private nonisolated func hash(
        for bytes: Data,
        source: CanonicalRealDataShadowCopySource,
        policy: CanonicalRealDataShadowCopyPolicy
    ) -> CanonicalHash? {
        switch source.hashPolicy {
        case .useProvidedHash:
            return source.contentHash
        case .computeIfBounded:
            guard policy.allowHashComputationForBoundedBytes else {
                return source.contentHash
            }
            return InMemoryCanonicalFileStore.hash(bytes, policy: .sha256)
        case .hashUnavailable:
            return source.contentHash
        }
    }

    private nonisolated func fileSize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return Int64.max
        }
        return size.int64Value
    }
}

nonisolated enum CanonicalShadowRootCleanupStatus: String, Codable, Equatable, Hashable, Sendable {
    case removed
    case retainedForDiagnostics
    case retainedForNextLaunch
    case refusedProductionRoot
    case failed
}

nonisolated struct CanonicalShadowRootRetentionRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { rootID }

    var rootID: String
    var rootKind: CanonicalShadowRootKind
    var createdAt: CanonicalTimestamp
    var retainedBytes: Int64
    var entryCount: Int

    nonisolated init(
        rootID: String,
        rootKind: CanonicalShadowRootKind,
        createdAt: Date = Date(),
        retainedBytes: Int64 = 0,
        entryCount: Int = 0
    ) {
        self.rootID = CanonicalProductionRedaction.safeIdentifier(rootID, fallback: "shadow-root")
        self.rootKind = rootKind
        self.createdAt = CanonicalTimestamp(createdAt)
        self.retainedBytes = max(0, retainedBytes)
        self.entryCount = max(0, entryCount)
    }
}

nonisolated struct CanonicalShadowRootCleanupResult: Codable, Equatable, Sendable {
    var rootID: String
    var rootKind: CanonicalShadowRootKind
    var status: CanonicalShadowRootCleanupStatus
    var removedRootCount: Int
    var retainedRootCount: Int
    var removedBytes: Int64
    var retainedBytes: Int64
    var failureReason: String?

    nonisolated init(
        rootID: String,
        rootKind: CanonicalShadowRootKind,
        status: CanonicalShadowRootCleanupStatus,
        removedRootCount: Int = 0,
        retainedRootCount: Int = 0,
        removedBytes: Int64 = 0,
        retainedBytes: Int64 = 0,
        failureReason: String? = nil
    ) {
        self.rootID = CanonicalProductionRedaction.safeIdentifier(rootID, fallback: "shadow-root")
        self.rootKind = rootKind
        self.status = status
        self.removedRootCount = max(0, removedRootCount)
        self.retainedRootCount = max(0, retainedRootCount)
        self.removedBytes = max(0, removedBytes)
        self.retainedBytes = max(0, retainedBytes)
        self.failureReason = CanonicalShadowMigrationRedaction.safeText(failureReason)
    }

    nonisolated var diagnosticsSummary: String {
        [
            "rootKind=\(rootKind.rawValue)",
            "rootID=\(rootID)",
            "cleanup=\(status.rawValue)",
            "removedRoots=\(removedRootCount)",
            "retainedRoots=\(retainedRootCount)",
            "removedBytes=\(removedBytes)",
            "retainedBytes=\(retainedBytes)",
            "failure=\(failureReason ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalShadowRootLifecycle: Equatable, Sendable {
    var rootID: String
    var rootKind: CanonicalShadowRootKind
    var rootURL: URL
    var productionRootURL: URL?
    var createdAt: Date

    nonisolated init(
        rootID: String = UUID().uuidString,
        rootKind: CanonicalShadowRootKind,
        rootURL: URL,
        productionRootURL: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.rootID = CanonicalProductionRedaction.safeIdentifier(rootID, fallback: "shadow-root")
        self.rootKind = rootKind
        self.rootURL = rootURL.standardizedFileURL
        self.productionRootURL = productionRootURL?.standardizedFileURL
        self.createdAt = createdAt
    }

    nonisolated var retentionRecord: CanonicalShadowRootRetentionRecord {
        CanonicalShadowRootRetentionRecord(rootID: rootID, rootKind: rootKind, createdAt: createdAt)
    }

    nonisolated func cleanup(
        policy: CanonicalRealDataShadowCopyCleanupPolicy,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> CanonicalShadowRootCleanupResult {
        guard rootURL.isFileURL else {
            return CanonicalShadowRootCleanupResult(rootID: rootID, rootKind: rootKind, status: .failed, failureReason: "shadowRootMustBeFileURL")
        }
        if let productionRootURL {
            let shadowPath = rootURL.standardizedFileURL.path
            let productionPath = productionRootURL.standardizedFileURL.path
            guard shadowPath != productionPath,
                  !shadowPath.hasPrefix(productionPath + "/") else {
                return CanonicalShadowRootCleanupResult(rootID: rootID, rootKind: rootKind, status: .refusedProductionRoot, failureReason: "productionRootRefused")
            }
        }

        switch policy {
        case .cleanupImmediately:
            let bytes = directorySize(rootURL, fileManager: fileManager)
            do {
                if fileManager.fileExists(atPath: rootURL.path) {
                    try fileManager.removeItem(at: rootURL)
                }
                return CanonicalShadowRootCleanupResult(rootID: rootID, rootKind: rootKind, status: .removed, removedRootCount: 1, removedBytes: bytes)
            } catch {
                return CanonicalShadowRootCleanupResult(rootID: rootID, rootKind: rootKind, status: .failed, retainedRootCount: 1, retainedBytes: bytes, failureReason: "cleanupFailed")
            }
        case let .retainForDiagnostics(maxAge, maxBytes):
            let parent = rootURL.deletingLastPathComponent()
            let retainedBytes = directorySize(rootURL, fileManager: fileManager)
            let purge = purgeRetainedRoots(
                parentDirectory: parent,
                protectedRootURL: rootURL,
                maxAge: maxAge,
                maxBytes: maxBytes,
                fileManager: fileManager,
                now: now
            )
            return CanonicalShadowRootCleanupResult(
                rootID: rootID,
                rootKind: rootKind,
                status: .retainedForDiagnostics,
                removedRootCount: purge.removedCount,
                retainedRootCount: 1,
                removedBytes: purge.removedBytes,
                retainedBytes: min(retainedBytes, maxBytes)
            )
        case .cleanupOnNextLaunch:
            return CanonicalShadowRootCleanupResult(
                rootID: rootID,
                rootKind: rootKind,
                status: .retainedForNextLaunch,
                retainedRootCount: fileManager.fileExists(atPath: rootURL.path) ? 1 : 0,
                retainedBytes: directorySize(rootURL, fileManager: fileManager)
            )
        }
    }

    private nonisolated func purgeRetainedRoots(
        parentDirectory: URL,
        protectedRootURL: URL,
        maxAge: TimeInterval,
        maxBytes: Int64,
        fileManager: FileManager,
        now: Date
    ) -> (removedCount: Int, removedBytes: Int64) {
        guard let urls = try? fileManager.contentsOfDirectory(at: parentDirectory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else {
            return (0, 0)
        }
        var removedCount = 0
        var removedBytes: Int64 = 0
        var candidates: [(url: URL, createdAt: Date, bytes: Int64)] = urls
            .filter { $0.standardizedFileURL.path != protectedRootURL.standardizedFileURL.path }
            .map { url in
                let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return (url.standardizedFileURL, createdAt, directorySize(url, fileManager: fileManager))
            }
        for candidate in candidates where now.timeIntervalSince(candidate.createdAt) > maxAge {
            if (try? fileManager.removeItem(at: candidate.url)) != nil {
                removedCount += 1
                removedBytes += candidate.bytes
            }
        }
        candidates.removeAll { now.timeIntervalSince($0.createdAt) > maxAge }
        var totalBytes = candidates.reduce(directorySize(protectedRootURL, fileManager: fileManager)) { $0 + $1.bytes }
        for candidate in candidates.sorted(by: { $0.createdAt < $1.createdAt }) where totalBytes > maxBytes {
            if (try? fileManager.removeItem(at: candidate.url)) != nil {
                removedCount += 1
                removedBytes += candidate.bytes
                totalBytes -= candidate.bytes
            }
        }
        return (removedCount, removedBytes)
    }

    private nonisolated func directorySize(_ url: URL, fileManager: FileManager) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }
        if !isDirectory.boolValue {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }
}
