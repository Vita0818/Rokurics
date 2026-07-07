//
//  IPhoneTombstoneConflictNoCommitExecutor.swift
//  Rokurics
//
//  Created by Codex on 2026/6/4.
//

import Foundation

struct IPhoneTombstoneConflictNoCommitExecutor: CanonicalTombstoneConflictNoCommitExecutor {
    private let stagingRootURL: URL?
    private let productionRootURL: URL?
    private let cleanupPolicy: CanonicalNoCommitStagingRootCleanupPolicy

    init(
        stagingRootURL: URL? = nil,
        productionRootURL: URL? = nil,
        cleanupPolicy: CanonicalNoCommitStagingRootCleanupPolicy = .cleanupImmediately
    ) {
        self.stagingRootURL = stagingRootURL?.standardizedFileURL
        self.productionRootURL = productionRootURL?.standardizedFileURL
        self.cleanupPolicy = cleanupPolicy
    }

    nonisolated func stageTombstoneConflictNoCommit(
        _ candidate: CanonicalTombstoneConflictNoCommitCandidate
    ) -> CanonicalTombstoneConflictNoCommitStagingResult {
        stage(candidate, platformPrefix: "iphone")
    }

    private nonisolated func stage(
        _ candidate: CanonicalTombstoneConflictNoCommitCandidate,
        platformPrefix: String
    ) -> CanonicalTombstoneConflictNoCommitStagingResult {
        let lifecycle = makeLifecycle(platformPrefix: platformPrefix)
        guard candidate.cutoverCandidate.actionKind != .unsupported else {
            return CanonicalTombstoneConflictNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: true,
                stagingEvidence: lifecycle.stagingEvidence(status: .notCreated),
                failure: .unsupportedAction,
                reason: "unsupportedTombstoneConflictNoCommitAction"
            )
        }
        if let blocker = lifecycle.validateRoot() {
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalTombstoneConflictNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: false,
                stagingEvidence: lifecycle.stagingEvidence(status: .validationFailed),
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: blocker.reason
            )
        }

        let summary = CanonicalTombstoneConflictNoCommitPayloadSummary(candidate: candidate)
        let bytes = summary.encodedBytes()
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let logicalPathToken = [
            "tombstone-conflict",
            "\(platformPrefix)-\(safePathComponent(candidate.cutoverCandidate.objectID))-\(safePathComponent(candidate.id)).json"
        ].joined(separator: "/")
        guard let safeLogicalPathToken = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken) else {
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalTombstoneConflictNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: false,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                stagingEvidence: lifecycle.stagingEvidence(status: .notCreated),
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: "unsafeTombstoneConflictNoCommitLogicalPath"
            )
        }

        let rootURL = lifecycle.root.rootURL.standardizedFileURL
        let destinationURL = rootURL.appendingPathComponent(safeLogicalPathToken, isDirectory: false).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        guard destinationURL.path.hasPrefix(rootPath) else {
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalTombstoneConflictNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: false,
                stagedLogicalPathToken: safeLogicalPathToken,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                stagingEvidence: lifecycle.stagingEvidence(status: .validationFailed),
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: "tombstoneConflictStagingDestinationEscapedRoot"
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try bytes.write(to: destinationURL, options: [.atomic])
            let stagingEvidence = lifecycle.stagingEvidence(status: .created)
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalTombstoneConflictNoCommitStagingResult(
                candidate: candidate,
                staged: true,
                wroteOnlyStagingRoot: true,
                stagedLogicalPathToken: safeLogicalPathToken,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                stagingEvidence: stagingEvidence,
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                reason: "iphoneTombstoneConflictNoCommitSuppressedProductionCommit"
            )
        } catch {
            let stagingEvidence = lifecycle.stagingEvidence(status: .notCreated)
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalTombstoneConflictNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: true,
                stagedLogicalPathToken: safeLogicalPathToken,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                stagingEvidence: stagingEvidence,
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: "iphoneTombstoneConflictNoCommitStagingFailed"
            )
        }
    }

    private nonisolated func makeLifecycle(platformPrefix: String) -> CanonicalNoCommitStagingRootLifecycle {
        let rootID = "\(platformPrefix)-tombstone-conflict-\(UUID().uuidString)"
        let rootURL = stagingRootURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsCanonicalV811TombstoneConflictNoCommit", isDirectory: true)
            .appendingPathComponent(rootID, isDirectory: true)
        let rootKind: CanonicalNoCommitStagingRootKind
        if let productionRootURL,
           isInside(rootURL, root: productionRootURL) {
            rootKind = .rejectedProductionRoot
        } else if stagingRootURL == nil {
            rootKind = .systemTemporary
        } else {
            rootKind = .explicitStagingRoot
        }
        return CanonicalNoCommitStagingRootLifecycle(
            root: CanonicalNoCommitStagingRoot(
                rootID: rootID,
                rootKind: rootKind,
                rootURL: rootURL,
                productionRootURL: productionRootURL
            )
        )
    }

    private nonisolated func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        let result = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_.:"))
        return result.isEmpty ? "unknown" : String(result.prefix(80))
    }

    private nonisolated func isInside(_ candidateURL: URL, root: URL) -> Bool {
        let candidatePath = candidateURL.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
