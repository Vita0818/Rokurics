//
//  IPhoneGeneratedArtifactNoCommitExecutor.swift
//  Rokurics
//
//  Created by Codex on 2026/6/4.
//

import Foundation

struct IPhoneGeneratedArtifactNoCommitExecutor: CanonicalGeneratedArtifactNoCommitExecutor {
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

    nonisolated func stageGeneratedArtifactNoCommit(
        _ candidate: CanonicalGeneratedArtifactNoCommitCandidate
    ) -> CanonicalGeneratedArtifactNoCommitStagingResult {
        stage(candidate, platformPrefix: "iphone")
    }

    private nonisolated func stage(
        _ candidate: CanonicalGeneratedArtifactNoCommitCandidate,
        platformPrefix: String
    ) -> CanonicalGeneratedArtifactNoCommitStagingResult {
        let lifecycle = makeLifecycle(platformPrefix: platformPrefix)
        guard candidate.cutoverCandidate.cutoverActionKind.isExecutableApply else {
            return CanonicalGeneratedArtifactNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: true,
                wouldRequestRoute: candidate.expectedRoutePath,
                wouldApplyToLocalGeneratedStore: false,
                stagingEvidence: lifecycle.stagingEvidence(status: .notCreated),
                failure: .unsupportedAction,
                reason: "unsupportedGeneratedArtifactNoCommitAction"
            )
        }

        if let blocker = lifecycle.validateRoot() {
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalGeneratedArtifactNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: false,
                wouldRequestRoute: candidate.expectedRoutePath,
                stagingEvidence: lifecycle.stagingEvidence(status: .validationFailed),
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: blocker.reason
            )
        }

        let summary = CanonicalGeneratedArtifactNoCommitPayloadSummary(candidate: candidate)
        let bytes = summary.encodedBytes()
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let objectComponent = safePathComponent(candidate.cutoverCandidate.objectID)
        let artifactComponent = safePathComponent(candidate.cutoverCandidate.artifactID ?? "artifact")
        let logicalPathToken = "generated-artifacts/\(platformPrefix)-\(objectComponent)-\(artifactComponent).json"
        guard let safeLogicalPathToken = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken) else {
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalGeneratedArtifactNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: false,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                wouldRequestRoute: candidate.expectedRoutePath,
                stagingEvidence: lifecycle.stagingEvidence(status: .notCreated),
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: "unsafeGeneratedArtifactNoCommitLogicalPath"
            )
        }
        let rootURL = lifecycle.root.rootURL.standardizedFileURL
        let destinationURL = rootURL.appendingPathComponent(safeLogicalPathToken, isDirectory: false).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        guard destinationURL.path.hasPrefix(rootPath) else {
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalGeneratedArtifactNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: false,
                stagedLogicalPathToken: safeLogicalPathToken,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                wouldRequestRoute: candidate.expectedRoutePath,
                stagingEvidence: lifecycle.stagingEvidence(status: .validationFailed),
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: "generatedArtifactStagingDestinationEscapedRoot"
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
            return CanonicalGeneratedArtifactNoCommitStagingResult(
                candidate: candidate,
                staged: true,
                wroteOnlyStagingRoot: true,
                stagedLogicalPathToken: safeLogicalPathToken,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                wouldRequestRoute: candidate.expectedRoutePath,
                wouldApplyToLocalGeneratedStore: true,
                productionCommitSuppressed: true,
                legacyDuplicateSuppressed: false,
                stagingEvidence: stagingEvidence,
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                reason: "iphoneGeneratedArtifactNoCommitWouldRequestAndApply"
            )
        } catch {
            let stagingEvidence = lifecycle.stagingEvidence(status: .notCreated)
            let cleanup = lifecycle.cleanup(policy: cleanupPolicy)
            return CanonicalGeneratedArtifactNoCommitStagingResult(
                candidate: candidate,
                staged: false,
                wroteOnlyStagingRoot: true,
                stagedLogicalPathToken: safeLogicalPathToken,
                payloadByteCount: bytes.count,
                payloadHashPrefix: hash.value,
                wouldRequestRoute: candidate.expectedRoutePath,
                stagingEvidence: stagingEvidence,
                cleanupEvidence: CanonicalNoCommitCleanupEvidence(result: cleanup),
                failure: .stagingFailed,
                reason: "iphoneGeneratedArtifactNoCommitStagingFailed"
            )
        }
    }

    private nonisolated func makeLifecycle(platformPrefix: String) -> CanonicalNoCommitStagingRootLifecycle {
        let rootID = "\(platformPrefix)-generated-\(UUID().uuidString)"
        let rootURL = stagingRootURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsCanonicalV89GeneratedArtifactNoCommit", isDirectory: true)
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
        let result = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
        return result.isEmpty ? "unknown" : String(result.prefix(80))
    }

    private nonisolated func isInside(_ candidateURL: URL, root: URL) -> Bool {
        let candidatePath = candidateURL.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
