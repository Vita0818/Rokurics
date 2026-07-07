//
//  IPhoneRecordingMetadataNoCommitExecutor.swift
//  Rokurics
//
//  Created by Codex on 2026/6/3.
//

import Foundation

struct IPhoneRecordingMetadataNoCommitExecutor: CanonicalRecordingMetadataNoCommitExecutor {
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

    nonisolated func stageNoCommit(
        _ candidate: CanonicalRecordingMetadataNoCommitCandidate
    ) -> CanonicalRecordingMetadataNoCommitStagingResult {
        stage(candidate, platformPrefix: "iphone")
    }

    private nonisolated func stage(
        _ candidate: CanonicalRecordingMetadataNoCommitCandidate,
        platformPrefix: String
    ) -> CanonicalRecordingMetadataNoCommitStagingResult {
        let lifecycle = makeLifecycle(platformPrefix: platformPrefix)
        guard candidate.canonicalDirection == .apply || candidate.canonicalDirection == .send else {
            return CanonicalRecordingMetadataNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: true,
                stagingEvidence: lifecycle.stagingEvidence(status: .notCreated),
                failure: .unsupportedAction,
                reason: "unsupportedNoCommitAction"
            )
        }

        if let blocker = lifecycle.validateRoot() {
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalRecordingMetadataNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: false,
                routePath: candidate.canonicalDirection == .send ? "/sync/apply-metadata" : nil,
                stagingEvidence: lifecycle.stagingEvidence(status: .validationFailed),
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: blocker.reason
            )
        }

        let summary = CanonicalRecordingMetadataNoCommitPayloadSummary(candidate: candidate)
        let bytes = summary.encodedBytes()
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let logicalPathToken = "recording-metadata/\(platformPrefix)-\(safePathComponent(candidate.objectID))-\(safePathComponent(candidate.id)).json"
        guard let safeLogicalPathToken = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken) else {
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalRecordingMetadataNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: false,
                routePath: candidate.canonicalDirection == .send ? "/sync/apply-metadata" : nil,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                stagingEvidence: lifecycle.stagingEvidence(status: .notCreated),
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: "unsafeNoCommitLogicalPath"
            )
        }
        let rootURL = lifecycle.root.rootURL.standardizedFileURL
        let destinationURL = rootURL.appendingPathComponent(safeLogicalPathToken, isDirectory: false).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        guard destinationURL.path.hasPrefix(rootPath) else {
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalRecordingMetadataNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: false,
                routePath: candidate.canonicalDirection == .send ? "/sync/apply-metadata" : nil,
                stagedLogicalPathToken: safeLogicalPathToken,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                stagingEvidence: lifecycle.stagingEvidence(status: .validationFailed),
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: "stagingDestinationEscapedRoot"
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
            return CanonicalRecordingMetadataNoCommitStagingResult(
                candidate: candidate,
                staged: true,
                wroteOnlyStagingRoot: true,
                routePath: candidate.canonicalDirection == .send ? "/sync/apply-metadata" : nil,
                stagedLogicalPathToken: safeLogicalPathToken,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                stagingEvidence: stagingEvidence,
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                reason: candidate.canonicalDirection == .send ? "iphoneNoCommitWouldSend" : "iphoneNoCommitWouldApply"
            )
        } catch {
            let stagingEvidence = lifecycle.stagingEvidence(status: .notCreated)
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalRecordingMetadataNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: true,
                routePath: candidate.canonicalDirection == .send ? "/sync/apply-metadata" : nil,
                stagedLogicalPathToken: safeLogicalPathToken,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                stagingEvidence: stagingEvidence,
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: "iphoneNoCommitStagingFailed"
            )
        }
    }

    private nonisolated func makeLifecycle(
        platformPrefix: String
    ) -> CanonicalNoCommitStagingRootLifecycle {
        let rootID = "\(platformPrefix)-\(UUID().uuidString)"
        let rootURL = stagingRootURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsCanonicalV8NoCommit", isDirectory: true)
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
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let result = String(
            value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        )
        .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return result.isEmpty ? "unknown" : String(result.prefix(80))
    }

    private nonisolated func isInside(_ candidateURL: URL, root: URL) -> Bool {
        let candidatePath = candidateURL.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
