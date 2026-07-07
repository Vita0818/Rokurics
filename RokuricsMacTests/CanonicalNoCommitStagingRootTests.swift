//
//  CanonicalNoCommitStagingRootTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalNoCommitStagingRootTests {
    @Test func defaultCleanupRemovesCurrentRootAndRedactsEvidence() throws {
        let rootURL = Self.makeScratchRoot("MacNoCommitDefaultCleanup")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("payload".utf8).write(to: rootURL.appendingPathComponent("metadata.json"))
        let lifecycle = Self.lifecycle(rootURL: rootURL)

        let staging = lifecycle.stagingEvidence(status: .created)
        let cleanup = lifecycle.cleanup(policy: .cleanupImmediately)

        #expect(staging.lifecycleStatus == .created)
        #expect(staging.fileCount == 1)
        #expect(cleanup.status == .removed)
        #expect(FileManager.default.fileExists(atPath: rootURL.path) == false)
        #expect(staging.diagnosticsSummary.contains("/Users/") == false)
        #expect(cleanup.diagnosticsSummary.contains("/private/") == false)
    }

    @Test func cleanupRefusesProductionRootAndProductionChild() throws {
        let productionRoot = Self.makeScratchRoot("MacNoCommitProductionRoot")
        try FileManager.default.createDirectory(at: productionRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: productionRoot) }
        let productionLifecycle = Self.lifecycle(rootURL: productionRoot, productionRootURL: productionRoot)
        let childRoot = productionRoot.appendingPathComponent("NoCommitChild", isDirectory: true)
        let childLifecycle = Self.lifecycle(rootURL: childRoot, productionRootURL: productionRoot)

        let productionCleanup = productionLifecycle.cleanup(policy: .cleanupImmediately)
        let childCleanup = childLifecycle.cleanup(policy: .cleanupImmediately)

        #expect(productionLifecycle.validateRoot()?.reason == "productionRootRefused")
        #expect(childLifecycle.validateRoot()?.reason == "productionRootRefused")
        #expect(productionCleanup.status == .refusedProductionRoot)
        #expect(childCleanup.status == .refusedProductionRoot)
        #expect(FileManager.default.fileExists(atPath: productionRoot.path))
    }

    @Test func retentionPolicyPurgesOldRootsByCountAndBytes() throws {
        let parent = Self.makeScratchRoot("MacNoCommitRetention")
        let current = parent.appendingPathComponent("current", isDirectory: true)
        let oldOne = parent.appendingPathComponent("old-one", isDirectory: true)
        let oldTwo = parent.appendingPathComponent("old-two", isDirectory: true)
        for url in [current, oldOne, oldTwo] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 3).write(to: url.appendingPathComponent("payload.bin"))
        }
        defer { try? FileManager.default.removeItem(at: parent) }

        let countCleanup = Self.lifecycle(rootURL: current).cleanup(
            policy: .retainForDiagnostics(maxAge: 3_600, maxCount: 1, maxBytes: 1_000)
        )

        #expect(countCleanup.status == .retainedForDiagnostics)
        #expect(FileManager.default.fileExists(atPath: current.path))
        #expect(FileManager.default.fileExists(atPath: oldOne.path) == false)
        #expect(FileManager.default.fileExists(atPath: oldTwo.path) == false)

        let oversized = parent.appendingPathComponent("oversized", isDirectory: true)
        try FileManager.default.createDirectory(at: oversized, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 16).write(to: oversized.appendingPathComponent("payload.bin"))
        let bytesCleanup = Self.lifecycle(rootURL: oversized).cleanup(
            policy: .retainForDiagnostics(maxAge: 3_600, maxCount: 4, maxBytes: 8)
        )

        #expect(bytesCleanup.status == .removed)
        #expect(FileManager.default.fileExists(atPath: oversized.path) == false)
    }

    @Test func evidenceReportSummarizesCountsWithoutPaths() throws {
        let candidate = Self.noCommitCandidate()
        let staging = CanonicalRecordingMetadataNoCommitStagingResult(
            candidate: candidate,
            staged: true,
            wroteOnlyStagingRoot: true,
            stagedLogicalPathToken: "recording-metadata/mac-recording-01-action.json",
            payloadByteCount: 24,
            payloadHashPrefix: String(repeating: "b", count: 64),
            stagingEvidence: CanonicalNoCommitStagingEvidence(
                rootID: "mac-root",
                rootKind: .systemTemporary,
                lifecycleStatus: .created,
                fileCount: 1,
                byteCount: 24
            ),
            cleanupEvidence: CanonicalNoCommitCleanupEvidence(
                result: CanonicalNoCommitStagingRootCleanupResult(
                    rootID: "mac-root",
                    rootKind: .systemTemporary,
                    policy: .cleanupImmediately,
                    status: .removed,
                    removedRootCount: 1,
                    removedBytes: 24,
                    fileCount: 1,
                    byteCount: 24
                )
            ),
            reason: "staged"
        )
        let equivalence = CanonicalRecordingMetadataNoCommitEquivalence(
            status: .equivalent,
            blocking: false,
            reasons: ["equivalent"],
            canonicalDirection: .apply,
            legacyDirection: .apply,
            metadataHashPrefix: String(repeating: "c", count: 64),
            modifiedAtDirection: "equal",
            tombstoneState: "active",
            routePath: nil,
            payloadByteCount: staging.payloadByteCount,
            payloadHashPrefix: staging.payloadHashPrefix
        )
        let result = CanonicalRecordingMetadataNoCommitCandidateResult(
            candidate: candidate,
            outcomes: [.noCommitEquivalent, .noCommitProductionCommitSuppressed],
            equivalence: equivalence,
            staging: staging,
            failure: nil
        )
        let gate = CanonicalCutoverAppSeamGate(
            domain: .recordingMetadata,
            mode: .guardedExecuteNoCommit,
            failures: [],
            reason: "allowed"
        )

        let report = CanonicalNoCommitEvidenceReport(gate: gate, candidateResults: [result])

        #expect(report.status == .complete)
        #expect(report.candidateCount == 1)
        #expect(report.equivalentCount == 1)
        #expect(report.cleanupStatus == "removed")
        #expect(report.productionCommitSuppressed)
        #expect(report.legacyDuplicateSuppressed == false)
        #expect(report.diagnosticsSummary.contains("/Users/") == false)
        #expect(report.diagnosticsSummary.contains(String(repeating: "c", count: 64)) == false)
    }

    @Test func migrationStageDefaultsOffAndNoCommitNeverAllowsProductionCommit() {
        let off = CanonicalMigrationStageConfiguration().summary()
        let noCommit = CanonicalMigrationStageConfiguration(stage: .recordingMetadataNoCommit).summary()
        let blockedDomain = CanonicalMigrationStageConfiguration(
            stage: .recordingMetadataNoCommit,
            domain: .generatedArtifacts
        ).summary()
        let guardedCommit = CanonicalMigrationStageConfiguration(stage: .recordingMetadataGuardedCommit).summary()

        #expect(off.stage == .off)
        #expect(off.allowed == false)
        #expect(off.productionCommitAllowed == false)
        #expect(noCommit.allowed)
        #expect(noCommit.allowedSideEffects.contains(.stagingRootWrite))
        #expect(noCommit.allowedSideEffects.contains(.productionCommit) == false)
        #expect(noCommit.productionCommitAllowed == false)
        #expect(blockedDomain.allowed == false)
        #expect(blockedDomain.blockers.contains("domainNotAllowed") || blockedDomain.blockers.contains("domainForbidden"))
        #expect(guardedCommit.productionCommitAllowed)
        #expect(guardedCommit.allowedSideEffects.contains(.productionCommit))
        #expect(guardedCommit.requiredEvidence.contains(.noCommitEvidenceReport))
        #expect(guardedCommit.requiredEvidence.contains(.rollbackPlan))
        #expect(guardedCommit.requiredEvidence.contains(.ownerApproval))
    }

    @Test func macExecutorCleansUpAfterStagingFailure() throws {
        let fileRoot = Self.makeScratchRoot("MacNoCommitFailureCleanup").appendingPathComponent("not-a-directory")
        try FileManager.default.createDirectory(at: fileRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: fileRoot)
        let executor = MacRecordingMetadataNoCommitExecutor(stagingRootURL: fileRoot)

        let staging = executor.stageNoCommit(Self.noCommitCandidate())

        #expect(staging.staged == false)
        #expect(staging.failure == .stagingFailed)
        #expect(staging.cleanupEvidence?.status == .removed)
        #expect(FileManager.default.fileExists(atPath: fileRoot.path) == false)
    }

    private static func lifecycle(
        rootURL: URL,
        productionRootURL: URL? = nil
    ) -> CanonicalNoCommitStagingRootLifecycle {
        CanonicalNoCommitStagingRootLifecycle(
            root: CanonicalNoCommitStagingRoot(
                rootID: "root-\(UUID().uuidString)",
                rootKind: .explicitStagingRoot,
                rootURL: rootURL,
                productionRootURL: productionRootURL
            )
        )
    }

    private static func noCommitCandidate() -> CanonicalRecordingMetadataNoCommitCandidate {
        let cutover = RecordingMetadataCutoverTestSupport.candidate()
        return CanonicalRecordingMetadataNoCommitCandidate(
            cutoverCandidate: cutover,
            legacyDirection: .apply,
            legacyObjectID: cutover.objectID
        )
    }

    private static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
