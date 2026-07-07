//
//  CanonicalNoCommitV82.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/3.
//

import Foundation

nonisolated enum CanonicalNoCommitSideEffectClass: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case stagingOnly
}

nonisolated enum CanonicalNoCommitBlockerSeverity: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case warning
    case blocker
}

nonisolated struct CanonicalNoCommitBlocker: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { [severity.rawValue, reason].joined(separator: "|") }

    var severity: CanonicalNoCommitBlockerSeverity
    var reason: String

    nonisolated init(
        severity: CanonicalNoCommitBlockerSeverity,
        reason: String
    ) {
        self.severity = severity
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? severity.rawValue
    }
}

nonisolated enum CanonicalNoCommitStagingRootKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case systemTemporary
    case explicitStagingRoot
    case rejectedProductionRoot
}

nonisolated enum CanonicalNoCommitStagingRootLifecycleStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case notCreated
    case created
    case validationFailed
}

nonisolated enum CanonicalNoCommitStagingRootCleanupStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case removed
    case retainedForDiagnostics
    case refusedProductionRoot
    case failed
}

nonisolated enum CanonicalNoCommitStagingRootCleanupPolicy: Codable, Equatable, Sendable {
    case cleanupImmediately
    case retainForDiagnostics(maxAge: TimeInterval, maxCount: Int, maxBytes: Int64)

    private enum CodingKeys: String, CodingKey {
        case kind
        case maxAge
        case maxCount
        case maxBytes
    }

    private enum Kind: String, Codable {
        case cleanupImmediately
        case retainForDiagnostics
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .cleanupImmediately:
            self = .cleanupImmediately
        case .retainForDiagnostics:
            self = .retainForDiagnostics(
                maxAge: try container.decode(TimeInterval.self, forKey: .maxAge),
                maxCount: try container.decode(Int.self, forKey: .maxCount),
                maxBytes: try container.decode(Int64.self, forKey: .maxBytes)
            )
        }
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cleanupImmediately:
            try container.encode(Kind.cleanupImmediately, forKey: .kind)
        case let .retainForDiagnostics(maxAge, maxCount, maxBytes):
            try container.encode(Kind.retainForDiagnostics, forKey: .kind)
            try container.encode(max(0, maxAge), forKey: .maxAge)
            try container.encode(max(0, maxCount), forKey: .maxCount)
            try container.encode(max(0, maxBytes), forKey: .maxBytes)
        }
    }

    nonisolated var policyName: String {
        switch self {
        case .cleanupImmediately:
            return "cleanupImmediately"
        case .retainForDiagnostics:
            return "retainForDiagnostics"
        }
    }
}

nonisolated struct CanonicalNoCommitStagingRoot: Equatable, Sendable {
    var rootID: String
    var rootKind: CanonicalNoCommitStagingRootKind
    var rootURL: URL
    var productionRootURL: URL?
    var createdAt: Date

    nonisolated init(
        rootID: String = UUID().uuidString,
        rootKind: CanonicalNoCommitStagingRootKind,
        rootURL: URL,
        productionRootURL: URL? = nil,
        createdAt: Date = Date()
    ) {
        self.rootID = CanonicalProductionRedaction.safeIdentifier(rootID, fallback: "no-commit-root")
        self.rootKind = rootKind
        self.rootURL = rootURL.standardizedFileURL
        self.productionRootURL = productionRootURL?.standardizedFileURL
        self.createdAt = createdAt
    }
}

nonisolated struct CanonicalNoCommitStagingRootRetentionRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { rootID }

    var rootID: String
    var rootKind: CanonicalNoCommitStagingRootKind
    var createdAt: CanonicalTimestamp
    var retainedBytes: Int64
    var entryCount: Int

    nonisolated init(
        rootID: String,
        rootKind: CanonicalNoCommitStagingRootKind,
        createdAt: Date = Date(),
        retainedBytes: Int64 = 0,
        entryCount: Int = 0
    ) {
        self.rootID = CanonicalProductionRedaction.safeIdentifier(rootID, fallback: "no-commit-root")
        self.rootKind = rootKind
        self.createdAt = CanonicalTimestamp(createdAt)
        self.retainedBytes = max(0, retainedBytes)
        self.entryCount = max(0, entryCount)
    }
}

nonisolated struct CanonicalNoCommitStagingRootCleanupResult: Codable, Equatable, Sendable {
    var rootID: String
    var rootKind: CanonicalNoCommitStagingRootKind
    var policy: CanonicalNoCommitStagingRootCleanupPolicy
    var status: CanonicalNoCommitStagingRootCleanupStatus
    var removedRootCount: Int
    var retainedRootCount: Int
    var removedBytes: Int64
    var retainedBytes: Int64
    var fileCount: Int
    var byteCount: Int64
    var warning: CanonicalNoCommitBlocker?

    nonisolated init(
        rootID: String,
        rootKind: CanonicalNoCommitStagingRootKind,
        policy: CanonicalNoCommitStagingRootCleanupPolicy,
        status: CanonicalNoCommitStagingRootCleanupStatus,
        removedRootCount: Int = 0,
        retainedRootCount: Int = 0,
        removedBytes: Int64 = 0,
        retainedBytes: Int64 = 0,
        fileCount: Int = 0,
        byteCount: Int64 = 0,
        warning: CanonicalNoCommitBlocker? = nil
    ) {
        self.rootID = CanonicalProductionRedaction.safeIdentifier(rootID, fallback: "no-commit-root")
        self.rootKind = rootKind
        self.policy = policy
        self.status = status
        self.removedRootCount = max(0, removedRootCount)
        self.retainedRootCount = max(0, retainedRootCount)
        self.removedBytes = max(0, removedBytes)
        self.retainedBytes = max(0, retainedBytes)
        self.fileCount = max(0, fileCount)
        self.byteCount = max(0, byteCount)
        self.warning = warning
    }

    nonisolated var diagnosticsSummary: String {
        [
            "rootKind=\(rootKind.rawValue)",
            "rootID=\(rootID)",
            "policy=\(policy.policyName)",
            "cleanup=\(status.rawValue)",
            "files=\(fileCount)",
            "bytes=\(byteCount)",
            "removedRoots=\(removedRootCount)",
            "retainedRoots=\(retainedRootCount)",
            "removedBytes=\(removedBytes)",
            "retainedBytes=\(retainedBytes)",
            "warning=\(warning?.reason ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalNoCommitStagingEvidence: Codable, Equatable, Sendable {
    var rootID: String
    var rootKind: CanonicalNoCommitStagingRootKind
    var lifecycleStatus: CanonicalNoCommitStagingRootLifecycleStatus
    var fileCount: Int
    var byteCount: Int64
    var wroteOnlyStagingRoot: Bool
    var sideEffectClass: CanonicalNoCommitSideEffectClass

    nonisolated init(
        rootID: String,
        rootKind: CanonicalNoCommitStagingRootKind,
        lifecycleStatus: CanonicalNoCommitStagingRootLifecycleStatus,
        fileCount: Int = 0,
        byteCount: Int64 = 0,
        wroteOnlyStagingRoot: Bool = true,
        sideEffectClass: CanonicalNoCommitSideEffectClass = .stagingOnly
    ) {
        self.rootID = CanonicalProductionRedaction.safeIdentifier(rootID, fallback: "no-commit-root")
        self.rootKind = rootKind
        self.lifecycleStatus = lifecycleStatus
        self.fileCount = max(0, fileCount)
        self.byteCount = max(0, byteCount)
        self.wroteOnlyStagingRoot = wroteOnlyStagingRoot
        self.sideEffectClass = sideEffectClass
    }

    nonisolated var diagnosticsSummary: String {
        [
            "rootKind=\(rootKind.rawValue)",
            "rootID=\(rootID)",
            "lifecycle=\(lifecycleStatus.rawValue)",
            "files=\(fileCount)",
            "bytes=\(byteCount)",
            "sideEffectClass=\(sideEffectClass.rawValue)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalNoCommitCleanupEvidence: Codable, Equatable, Sendable {
    var rootID: String
    var rootKind: CanonicalNoCommitStagingRootKind
    var policy: String
    var status: CanonicalNoCommitStagingRootCleanupStatus
    var fileCount: Int
    var byteCount: Int64
    var removedRootCount: Int
    var retainedRootCount: Int
    var warning: CanonicalNoCommitBlocker?

    nonisolated init(result: CanonicalNoCommitStagingRootCleanupResult) {
        self.rootID = result.rootID
        self.rootKind = result.rootKind
        self.policy = result.policy.policyName
        self.status = result.status
        self.fileCount = result.fileCount
        self.byteCount = result.byteCount
        self.removedRootCount = result.removedRootCount
        self.retainedRootCount = result.retainedRootCount
        self.warning = result.warning
    }

    nonisolated var diagnosticsSummary: String {
        [
            "rootKind=\(rootKind.rawValue)",
            "rootID=\(rootID)",
            "policy=\(policy)",
            "cleanup=\(status.rawValue)",
            "files=\(fileCount)",
            "bytes=\(byteCount)",
            "removedRoots=\(removedRootCount)",
            "retainedRoots=\(retainedRootCount)",
            "warning=\(warning?.reason ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalNoCommitStagingRootLifecycle: Equatable, Sendable {
    var root: CanonicalNoCommitStagingRoot

    nonisolated init(root: CanonicalNoCommitStagingRoot) {
        self.root = root
    }

    nonisolated var retentionRecord: CanonicalNoCommitStagingRootRetentionRecord {
        let stats = directoryStats(root.rootURL, fileManager: .default)
        return CanonicalNoCommitStagingRootRetentionRecord(
            rootID: root.rootID,
            rootKind: root.rootKind,
            createdAt: root.createdAt,
            retainedBytes: stats.bytes,
            entryCount: stats.files
        )
    }

    nonisolated func validateRoot(fileManager: FileManager = .default) -> CanonicalNoCommitBlocker? {
        guard root.rootURL.isFileURL else {
            return CanonicalNoCommitBlocker(severity: .blocker, reason: "stagingRootMustBeFileURL")
        }
        if root.rootKind == .rejectedProductionRoot {
            return CanonicalNoCommitBlocker(severity: .blocker, reason: "productionRootRefused")
        }
        if let productionRootURL = root.productionRootURL?.standardizedFileURL {
            let stagingPath = root.rootURL.standardizedFileURL.path
            let productionPath = productionRootURL.path
            if stagingPath == productionPath || stagingPath.hasPrefix(productionPath + "/") {
                return CanonicalNoCommitBlocker(severity: .blocker, reason: "productionRootRefused")
            }
        }
        if root.rootKind == .systemTemporary {
            let stagingPath = root.rootURL.standardizedFileURL.path
            let tempPath = fileManager.temporaryDirectory.standardizedFileURL.path
            guard stagingPath == tempPath || stagingPath.hasPrefix(tempPath + "/") else {
                return CanonicalNoCommitBlocker(severity: .blocker, reason: "systemTemporaryRootRequired")
            }
        }
        return nil
    }

    nonisolated func stagingEvidence(
        fileManager: FileManager = .default,
        status: CanonicalNoCommitStagingRootLifecycleStatus
    ) -> CanonicalNoCommitStagingEvidence {
        let stats = directoryStats(root.rootURL, fileManager: fileManager)
        return CanonicalNoCommitStagingEvidence(
            rootID: root.rootID,
            rootKind: root.rootKind,
            lifecycleStatus: status,
            fileCount: stats.files,
            byteCount: stats.bytes,
            wroteOnlyStagingRoot: status == .created
        )
    }

    nonisolated func cleanup(
        policy: CanonicalNoCommitStagingRootCleanupPolicy,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> CanonicalNoCommitStagingRootCleanupResult {
        let stats = directoryStats(root.rootURL, fileManager: fileManager)
        if let blocker = validateRoot(fileManager: fileManager),
           blocker.reason == "productionRootRefused" {
            return CanonicalNoCommitStagingRootCleanupResult(
                rootID: root.rootID,
                rootKind: .rejectedProductionRoot,
                policy: policy,
                status: .refusedProductionRoot,
                retainedRootCount: fileManager.fileExists(atPath: root.rootURL.path) ? 1 : 0,
                retainedBytes: stats.bytes,
                fileCount: stats.files,
                byteCount: stats.bytes,
                warning: blocker
            )
        }

        switch policy {
        case .cleanupImmediately:
            return removeCurrentRoot(
                policy: policy,
                fileManager: fileManager,
                stats: stats,
                reason: nil
            )
        case let .retainForDiagnostics(maxAge, maxCount, maxBytes):
            let boundedMaxCount = max(0, maxCount)
            let boundedMaxBytes = max(0, maxBytes)
            if boundedMaxCount == 0 || stats.bytes > boundedMaxBytes {
                return removeCurrentRoot(
                    policy: policy,
                    fileManager: fileManager,
                    stats: stats,
                    reason: "retentionBoundsExceeded"
                )
            }
            let purge = purgeRetainedRoots(
                parentDirectory: root.rootURL.deletingLastPathComponent(),
                protectedRootURL: root.rootURL,
                maxAge: max(0, maxAge),
                maxCount: boundedMaxCount,
                maxBytes: boundedMaxBytes,
                fileManager: fileManager,
                now: now
            )
            let retainedStats = directoryStats(root.rootURL, fileManager: fileManager)
            return CanonicalNoCommitStagingRootCleanupResult(
                rootID: root.rootID,
                rootKind: root.rootKind,
                policy: policy,
                status: .retainedForDiagnostics,
                removedRootCount: purge.removedCount,
                retainedRootCount: fileManager.fileExists(atPath: root.rootURL.path) ? 1 : 0,
                removedBytes: purge.removedBytes,
                retainedBytes: retainedStats.bytes,
                fileCount: retainedStats.files,
                byteCount: retainedStats.bytes
            )
        }
    }

    private nonisolated func removeCurrentRoot(
        policy: CanonicalNoCommitStagingRootCleanupPolicy,
        fileManager: FileManager,
        stats: (files: Int, bytes: Int64),
        reason: String?
    ) -> CanonicalNoCommitStagingRootCleanupResult {
        do {
            if fileManager.fileExists(atPath: root.rootURL.path) {
                try fileManager.removeItem(at: root.rootURL)
            }
            return CanonicalNoCommitStagingRootCleanupResult(
                rootID: root.rootID,
                rootKind: root.rootKind,
                policy: policy,
                status: .removed,
                removedRootCount: stats.files > 0 || stats.bytes > 0 ? 1 : 0,
                removedBytes: stats.bytes,
                fileCount: stats.files,
                byteCount: stats.bytes,
                warning: reason.map { CanonicalNoCommitBlocker(severity: .warning, reason: $0) }
            )
        } catch {
            return CanonicalNoCommitStagingRootCleanupResult(
                rootID: root.rootID,
                rootKind: root.rootKind,
                policy: policy,
                status: .failed,
                retainedRootCount: 1,
                retainedBytes: stats.bytes,
                fileCount: stats.files,
                byteCount: stats.bytes,
                warning: CanonicalNoCommitBlocker(severity: .warning, reason: "cleanupFailed")
            )
        }
    }

    private nonisolated func purgeRetainedRoots(
        parentDirectory: URL,
        protectedRootURL: URL,
        maxAge: TimeInterval,
        maxCount: Int,
        maxBytes: Int64,
        fileManager: FileManager,
        now: Date
    ) -> (removedCount: Int, removedBytes: Int64) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: parentDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }
        let protectedPath = protectedRootURL.standardizedFileURL.path
        var candidates: [(url: URL, createdAt: Date, bytes: Int64)] = urls
            .map(\.standardizedFileURL)
            .filter { $0.path != protectedPath }
            .map { url in
                let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return (url, createdAt, directoryStats(url, fileManager: fileManager).bytes)
            }
        var removedCount = 0
        var removedBytes: Int64 = 0
        for candidate in candidates where now.timeIntervalSince(candidate.createdAt) > maxAge {
            if (try? fileManager.removeItem(at: candidate.url)) != nil {
                removedCount += 1
                removedBytes += candidate.bytes
            }
        }
        candidates.removeAll { now.timeIntervalSince($0.createdAt) > maxAge }
        let currentBytes = directoryStats(protectedRootURL, fileManager: fileManager).bytes
        var totalBytes = currentBytes + candidates.reduce(Int64(0)) { $0 + $1.bytes }
        var retainedRootCount = 1 + candidates.count
        for candidate in candidates.sorted(by: { $0.createdAt < $1.createdAt }) where retainedRootCount > maxCount || totalBytes > maxBytes {
            if (try? fileManager.removeItem(at: candidate.url)) != nil {
                removedCount += 1
                removedBytes += candidate.bytes
                totalBytes -= candidate.bytes
                retainedRootCount -= 1
            }
        }
        return (removedCount, removedBytes)
    }

    private nonisolated func directoryStats(_ url: URL, fileManager: FileManager) -> (files: Int, bytes: Int64) {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return (0, 0)
        }
        if !isDirectory.boolValue {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            return (1, (attributes?[.size] as? NSNumber)?.int64Value ?? 0)
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }
        var files = 0
        var bytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            if values?.isDirectory == true {
                continue
            }
            files += 1
            bytes += Int64(values?.fileSize ?? 0)
        }
        return (files, bytes)
    }
}

nonisolated enum CanonicalNoCommitEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case complete
    case blocked
    case divergent
    case insufficientEvidence
    case unsupported
    case warning
}

nonisolated struct CanonicalNoCommitEquivalenceEvidence: Codable, Equatable, Sendable {
    var equivalentCount: Int
    var divergentCount: Int
    var insufficientEvidenceCount: Int
    var unsupportedCount: Int
    var hashPrefixes: [String]
    var routeProjectionStatus: String
    var legacyActionComparisonStatus: String

    nonisolated init(
        candidateResults: [CanonicalRecordingMetadataNoCommitCandidateResult]
    ) {
        self.equivalentCount = candidateResults.filter {
            $0.equivalence.status == .equivalent || $0.equivalence.status == .canonicalMoreConservative
        }.count
        self.divergentCount = candidateResults.filter { $0.equivalence.status == .divergent }.count
        self.insufficientEvidenceCount = candidateResults.filter { $0.equivalence.status == .insufficientEvidence }.count
        self.unsupportedCount = candidateResults.filter { $0.equivalence.status == .unsupported }.count
        self.hashPrefixes = Array(Set(candidateResults.compactMap(\.equivalence.metadataHashPrefix))).sorted()
        self.routeProjectionStatus = candidateResults.contains {
            $0.equivalence.canonicalDirection == .send && $0.equivalence.routePath != "/sync/apply-metadata"
        } ? "routeProjectionDivergent" : "routeProjectionSafe"
        self.legacyActionComparisonStatus = candidateResults.contains { $0.equivalence.blocking }
            ? "legacyActionComparisonBlocked"
            : "legacyActionComparisonEquivalent"
    }
}

nonisolated struct CanonicalNoCommitEvidenceReport: Codable, Equatable, Sendable {
    var domain: CanonicalCutoverDomain
    var mode: CanonicalCutoverAppSeamMode
    var status: CanonicalNoCommitEvidenceStatus
    var candidateCount: Int
    var wouldApplyCount: Int
    var wouldSendCount: Int
    var equivalentCount: Int
    var divergentCount: Int
    var insufficientEvidenceCount: Int
    var unsupportedCount: Int
    var stagingRootLifecycleStatus: String
    var cleanupStatus: String
    var routeProjectionStatus: String
    var legacyActionComparisonStatus: String
    var productionCommitSuppressed: Bool
    var legacyDuplicateSuppressed: Bool
    var sideEffectClass: CanonicalNoCommitSideEffectClass
    var equivalenceEvidence: CanonicalNoCommitEquivalenceEvidence
    var stagingEvidence: [CanonicalNoCommitStagingEvidence]
    var cleanupEvidence: [CanonicalNoCommitCleanupEvidence]
    var blockers: [CanonicalNoCommitBlocker]

    nonisolated init(
        gate: CanonicalCutoverAppSeamGate,
        candidateResults: [CanonicalRecordingMetadataNoCommitCandidateResult],
        productionCommitSuppressed: Bool = true,
        legacyDuplicateSuppressed: Bool = false
    ) {
        let equivalence = CanonicalNoCommitEquivalenceEvidence(candidateResults: candidateResults)
        let staging = candidateResults.compactMap { $0.staging?.stagingEvidence }
        let cleanup = candidateResults.compactMap { $0.staging?.cleanupEvidence }
        var blockers: [CanonicalNoCommitBlocker] = gate.failures.map {
            CanonicalNoCommitBlocker(severity: .blocker, reason: $0.rawValue)
        }
        blockers += candidateResults.compactMap { result in
            result.failure.map { CanonicalNoCommitBlocker(severity: .blocker, reason: $0.rawValue) }
        }
        blockers += cleanup.compactMap(\.warning)

        let status: CanonicalNoCommitEvidenceStatus
        if !gate.allowed {
            status = .blocked
        } else if equivalence.unsupportedCount > 0 {
            status = .unsupported
        } else if equivalence.insufficientEvidenceCount > 0 {
            status = .insufficientEvidence
        } else if equivalence.divergentCount > 0 {
            status = .divergent
        } else if blockers.contains(where: { $0.severity == .warning }) {
            status = .warning
        } else {
            status = .complete
        }

        self.domain = gate.domain
        self.mode = gate.mode
        self.status = status
        self.candidateCount = candidateResults.count
        self.wouldApplyCount = candidateResults.filter { $0.staging?.wouldApply == true }.count
        self.wouldSendCount = candidateResults.filter { $0.staging?.wouldSend == true }.count
        self.equivalentCount = equivalence.equivalentCount
        self.divergentCount = equivalence.divergentCount
        self.insufficientEvidenceCount = equivalence.insufficientEvidenceCount
        self.unsupportedCount = equivalence.unsupportedCount
        self.stagingRootLifecycleStatus = staging.map(\.lifecycleStatus.rawValue).sorted().joined(separator: ",")
        self.cleanupStatus = cleanup.map(\.status.rawValue).sorted().joined(separator: ",")
        self.routeProjectionStatus = equivalence.routeProjectionStatus
        self.legacyActionComparisonStatus = equivalence.legacyActionComparisonStatus
        self.productionCommitSuppressed = productionCommitSuppressed
        self.legacyDuplicateSuppressed = legacyDuplicateSuppressed
        self.sideEffectClass = .stagingOnly
        self.equivalenceEvidence = equivalence
        self.stagingEvidence = staging
        self.cleanupEvidence = cleanup
        self.blockers = Array(Set(blockers)).sorted { $0.id < $1.id }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "domain=\(domain.rawValue)",
            "mode=\(mode.rawValue)",
            "status=\(status.rawValue)",
            "candidateCount=\(candidateCount)",
            "wouldApply=\(wouldApplyCount)",
            "wouldSend=\(wouldSendCount)",
            "equivalent=\(equivalentCount)",
            "divergent=\(divergentCount)",
            "insufficientEvidence=\(insufficientEvidenceCount)",
            "unsupported=\(unsupportedCount)",
            "staging=\(stagingRootLifecycleStatus.isEmpty ? "none" : stagingRootLifecycleStatus)",
            "cleanup=\(cleanupStatus.isEmpty ? "none" : cleanupStatus)",
            "routeProjection=\(routeProjectionStatus)",
            "legacyComparison=\(legacyActionComparisonStatus)",
            "productionCommitSuppressed=\(productionCommitSuppressed)",
            "legacyDuplicateSuppressed=\(legacyDuplicateSuppressed)",
            "sideEffectClass=\(sideEffectClass.rawValue)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalMigrationStage: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case off
    case notStarted
    case projected
    case planned
    case noCommit
    case realApplyPort
    case commitExecutor
    case appSeamDefaultOff
    case nextPilotCandidate
    case canaryN0
    case canaryN1
    case expandedCanary
    case domainCutover
    case readSideParallel
    case readSideCutover
    case retirementCandidate
    case retired
    case diagnosticsOnly
    case decisionShadow
    case executionShadow
    case realDataShadowCopy
    case readOnlyTransportProbe
    case recordingMetadataNoCommit
    case recordingMetadataGuardedCommit
    case unsupported
}

nonisolated enum CanonicalMigrationStageSideEffect: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case diagnosticsWrite
    case shadowRootWrite
    case readOnlyNetworkProbe
    case stagingRootWrite
    case productionCommit
}

nonisolated enum CanonicalMigrationStageEvidence: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case dryRunEquivalence
    case executionShadow
    case realDataShadowCopy
    case readOnlyTransportProbe
    case noCommitEvidenceReport
    case ownerApproval
    case rollbackPlan
}

nonisolated struct CanonicalMigrationStagePolicy: Codable, Equatable, Sendable {
    var allowedSideEffects: [CanonicalMigrationStageSideEffect]
    var requiredEvidence: [CanonicalMigrationStageEvidence]
    var allowedDomains: [CanonicalCutoverDomain]
    var forbiddenDomains: [CanonicalCutoverDomain]
    var productionCommitAllowed: Bool
    var existingConfigurationKeys: [String]

    nonisolated init(
        allowedSideEffects: [CanonicalMigrationStageSideEffect],
        requiredEvidence: [CanonicalMigrationStageEvidence],
        allowedDomains: [CanonicalCutoverDomain],
        forbiddenDomains: [CanonicalCutoverDomain],
        productionCommitAllowed: Bool = false,
        existingConfigurationKeys: [String]
    ) {
        self.allowedSideEffects = Array(Set(allowedSideEffects)).sorted { $0.rawValue < $1.rawValue }
        self.requiredEvidence = Array(Set(requiredEvidence)).sorted { $0.rawValue < $1.rawValue }
        self.allowedDomains = Array(Set(allowedDomains)).sorted { $0.rawValue < $1.rawValue }
        self.forbiddenDomains = Array(Set(forbiddenDomains)).sorted { $0.rawValue < $1.rawValue }
        self.productionCommitAllowed = productionCommitAllowed
        self.existingConfigurationKeys = Array(Set(existingConfigurationKeys.compactMap(CanonicalProductionRedaction.safeDiagnosticText))).sorted()
    }

    nonisolated static func defaultPolicy(for stage: CanonicalMigrationStage) -> CanonicalMigrationStagePolicy {
        let recordingOnly: [CanonicalCutoverDomain] = [.recordingMetadata]
        let allExceptRecording = CanonicalCutoverDomain.allCases.filter { $0 != .recordingMetadata }
        switch stage {
        case .off, .notStarted:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [],
                requiredEvidence: [.none],
                allowedDomains: [],
                forbiddenDomains: CanonicalCutoverDomain.allCases,
                productionCommitAllowed: false,
                existingConfigurationKeys: [
                    "canonicalShadowMigrationConfiguration.disabled",
                    "canonicalSingleDomainShadowConfiguration.disabled",
                    "canonicalV8CutoverAppSeamConfiguration.disabled"
                ]
            )
        case .diagnosticsOnly, .projected, .planned, .appSeamDefaultOff, .nextPilotCandidate, .canaryN0, .readSideParallel, .retirementCandidate:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite],
                requiredEvidence: [.none],
                allowedDomains: CanonicalCutoverDomain.allCases,
                forbiddenDomains: [],
                productionCommitAllowed: false,
                existingConfigurationKeys: ["canonicalMigrationMatrix.diagnosticsOnly"]
            )
        case .noCommit:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite, .stagingRootWrite],
                requiredEvidence: [.noCommitEvidenceReport],
                allowedDomains: CanonicalCutoverDomain.allCases,
                forbiddenDomains: [],
                productionCommitAllowed: false,
                existingConfigurationKeys: ["canonicalMigrationMatrix.noCommit"]
            )
        case .realApplyPort, .commitExecutor:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite],
                requiredEvidence: [.noCommitEvidenceReport, .rollbackPlan],
                allowedDomains: CanonicalCutoverDomain.allCases,
                forbiddenDomains: [],
                productionCommitAllowed: false,
                existingConfigurationKeys: ["canonicalMigrationMatrix.\(stage.rawValue)"]
            )
        case .canaryN1, .expandedCanary, .domainCutover:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite, .productionCommit],
                requiredEvidence: [
                    .dryRunEquivalence,
                    .executionShadow,
                    .realDataShadowCopy,
                    .readOnlyTransportProbe,
                    .noCommitEvidenceReport,
                    .ownerApproval,
                    .rollbackPlan
                ],
                allowedDomains: CanonicalCutoverDomain.allCases,
                forbiddenDomains: [],
                productionCommitAllowed: true,
                existingConfigurationKeys: ["canonicalMigrationMatrix.\(stage.rawValue)"]
            )
        case .readSideCutover, .retired:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite],
                requiredEvidence: [.ownerApproval, .rollbackPlan],
                allowedDomains: CanonicalCutoverDomain.allCases,
                forbiddenDomains: [],
                productionCommitAllowed: false,
                existingConfigurationKeys: ["canonicalMigrationMatrix.\(stage.rawValue)"]
            )
        case .decisionShadow:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite],
                requiredEvidence: [.dryRunEquivalence],
                allowedDomains: CanonicalCutoverDomain.allCases,
                forbiddenDomains: [],
                productionCommitAllowed: false,
                existingConfigurationKeys: ["canonicalShadowMigrationConfiguration.dryRunCompare"]
            )
        case .executionShadow:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite, .shadowRootWrite],
                requiredEvidence: [.dryRunEquivalence, .executionShadow],
                allowedDomains: recordingOnly,
                forbiddenDomains: allExceptRecording,
                productionCommitAllowed: false,
                existingConfigurationKeys: ["canonicalSingleDomainShadowConfiguration.executionShadowDryRun"]
            )
        case .realDataShadowCopy:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite, .shadowRootWrite],
                requiredEvidence: [.executionShadow, .realDataShadowCopy],
                allowedDomains: recordingOnly,
                forbiddenDomains: allExceptRecording,
                productionCommitAllowed: false,
                existingConfigurationKeys: ["canonicalShadowMigrationConfiguration.realDataShadowCopyPolicy"]
            )
        case .readOnlyTransportProbe:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite, .readOnlyNetworkProbe],
                requiredEvidence: [.realDataShadowCopy, .readOnlyTransportProbe],
                allowedDomains: recordingOnly,
                forbiddenDomains: allExceptRecording,
                productionCommitAllowed: false,
                existingConfigurationKeys: [
                    "canonicalShadowMigrationConfiguration.readOnlyTransportProbePolicy",
                    "canonicalLiveReadOnlyTransportProbePolicy"
                ]
            )
        case .recordingMetadataNoCommit:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite, .stagingRootWrite],
                requiredEvidence: [.realDataShadowCopy, .readOnlyTransportProbe, .noCommitEvidenceReport],
                allowedDomains: recordingOnly,
                forbiddenDomains: allExceptRecording,
                productionCommitAllowed: false,
                existingConfigurationKeys: ["canonicalV8CutoverAppSeamConfiguration.guardedExecuteNoCommit"]
            )
        case .recordingMetadataGuardedCommit:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [.diagnosticsWrite, .productionCommit],
                requiredEvidence: [
                    .dryRunEquivalence,
                    .executionShadow,
                    .realDataShadowCopy,
                    .readOnlyTransportProbe,
                    .noCommitEvidenceReport,
                    .ownerApproval,
                    .rollbackPlan
                ],
                allowedDomains: recordingOnly,
                forbiddenDomains: allExceptRecording,
                productionCommitAllowed: true,
                existingConfigurationKeys: ["CanonicalSingleDomainCutoverConfiguration.guardedExecuteCommit"]
            )
        case .unsupported:
            return CanonicalMigrationStagePolicy(
                allowedSideEffects: [],
                requiredEvidence: [],
                allowedDomains: [],
                forbiddenDomains: CanonicalCutoverDomain.allCases,
                productionCommitAllowed: false,
                existingConfigurationKeys: []
            )
        }
    }
}

nonisolated struct CanonicalMigrationConfigurationSummary: Codable, Equatable, Sendable {
    var stage: CanonicalMigrationStage
    var domain: CanonicalCutoverDomain
    var allowed: Bool
    var blockers: [String]
    var allowedSideEffects: [CanonicalMigrationStageSideEffect]
    var requiredEvidence: [CanonicalMigrationStageEvidence]
    var allowedDomains: [CanonicalCutoverDomain]
    var forbiddenDomains: [CanonicalCutoverDomain]
    var productionCommitAllowed: Bool
    var existingConfigurationKeys: [String]

    nonisolated init(
        stage: CanonicalMigrationStage,
        domain: CanonicalCutoverDomain,
        allowed: Bool,
        blockers: [String],
        policy: CanonicalMigrationStagePolicy
    ) {
        self.stage = stage
        self.domain = domain
        self.allowed = allowed
        self.blockers = Array(Set(blockers.compactMap(CanonicalProductionRedaction.safeDiagnosticText))).sorted()
        self.allowedSideEffects = policy.allowedSideEffects
        self.requiredEvidence = policy.requiredEvidence
        self.allowedDomains = policy.allowedDomains
        self.forbiddenDomains = policy.forbiddenDomains
        self.productionCommitAllowed = policy.productionCommitAllowed
        self.existingConfigurationKeys = policy.existingConfigurationKeys
    }

    nonisolated var diagnosticsSummary: String {
        [
            "stage=\(stage.rawValue)",
            "domain=\(domain.rawValue)",
            "allowed=\(allowed)",
            "sideEffects=\(allowedSideEffects.map(\.rawValue).joined(separator: "+"))",
            "requiredEvidence=\(requiredEvidence.map(\.rawValue).joined(separator: "+"))",
            "productionCommitAllowed=\(productionCommitAllowed)",
            "blockers=\(blockers.joined(separator: "+"))"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalMigrationStageConfiguration: Codable, Equatable, Sendable {
    var stage: CanonicalMigrationStage
    var domain: CanonicalCutoverDomain
    var policy: CanonicalMigrationStagePolicy

    nonisolated init(
        stage: CanonicalMigrationStage = .off,
        domain: CanonicalCutoverDomain = .recordingMetadata,
        policy: CanonicalMigrationStagePolicy? = nil
    ) {
        self.stage = stage
        self.domain = domain
        self.policy = policy ?? CanonicalMigrationStagePolicy.defaultPolicy(for: stage)
    }

    nonisolated static let off = CanonicalMigrationStageConfiguration()

    nonisolated func summary() -> CanonicalMigrationConfigurationSummary {
        var blockers: [String] = []
        if stage == .off {
            blockers.append("stageOff")
        }
        if stage == .unsupported {
            blockers.append("unsupportedStage")
        }
        if !policy.allowedDomains.isEmpty, !policy.allowedDomains.contains(domain) {
            blockers.append("domainNotAllowed")
        }
        if policy.forbiddenDomains.contains(domain) {
            blockers.append("domainForbidden")
        }
        let productionCommitStages: Set<CanonicalMigrationStage> = [
            .recordingMetadataGuardedCommit,
            .canaryN1,
            .expandedCanary,
            .domainCutover
        ]
        if policy.allowedSideEffects.contains(.productionCommit), !productionCommitStages.contains(stage) {
            blockers.append("illegalProductionCommitSideEffect")
        }
        if policy.productionCommitAllowed != policy.allowedSideEffects.contains(.productionCommit) {
            blockers.append("productionCommitPolicyMismatch")
        }
        return CanonicalMigrationConfigurationSummary(
            stage: stage,
            domain: domain,
            allowed: blockers.isEmpty,
            blockers: blockers,
            policy: policy
        )
    }
}
