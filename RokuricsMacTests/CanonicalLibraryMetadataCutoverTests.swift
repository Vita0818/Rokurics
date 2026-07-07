//
//  CanonicalLibraryMetadataCutoverTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalLibraryMetadataCutoverTests {
    @Test func macAppSeamDefaultsDisabled() {
        let config = CanonicalLibraryMetadataCutoverAppSeamConfiguration()

        #expect(config.isEnabled == false)
        #expect(config.effectiveMode == .disabled)
        #expect(config.policy.canaryPolicy.canaryMaxObjectsPerSyncRun == 0)
    }

    @Test func macNoCommitStagesOnlyAndDoesNotSuppressLegacyDuplicates() throws {
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacLibraryMetadataNoCommit")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = MacLibraryMetadataNoCommitExecutor(stagingRootURL: rootURL)

        let result = executor.stageLibraryMetadataNoCommit(
            CanonicalLibraryMetadataNoCommitCandidate(cutoverCandidate: candidate)
        )

        #expect(result.staged)
        #expect(result.wroteOnlyStagingRoot)
        #expect(result.productionCommitSuppressed)
        #expect(result.legacyDuplicateSuppressed == false)
        #expect(result.wouldUseMetadataManifestBridge)
        #expect(result.cleanupEvidence?.status == .removed)
        #expect(result.payloadHashPrefix?.count == 12)
        #expect(FileManager.default.fileExists(atPath: rootURL.path) == false)
    }

    @Test func macRootBoundApplyCommitAndRollbackRestorePreviousBytes() async throws {
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacLibraryMetadataRootBound")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = MacLibraryMetadataCutoverTestSupport.folderCandidate()
        let previousBytes = Data("previous-mac-folder-metadata".utf8)
        let logicalPath = CanonicalRootBoundLibraryMetadataTarget.defaultLogicalPathToken(
            objectID: pair.candidate.objectID,
            objectKind: .folder,
            domain: .folderMetadata
        )
        let previousURL = rootURL.appendingPathComponent(logicalPath)
        try FileManager.default.createDirectory(at: previousURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try previousBytes.write(to: previousURL)

        let applyPort = try MacLibraryMetadataRealApplyPort(testRootURL: rootURL)
        try await applyPort.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)
        let executor = MacLibraryMetadataCutoverExecutor(applyPort: applyPort)

        let result = await MacLibraryMetadataCutoverTestSupport.run(
            candidates: [pair.candidate],
            executor: executor
        )
        let committedBytes = try await applyPort.rootBoundLibraryMetadataBytes(
            objectID: pair.candidate.objectID,
            objectKind: .folder,
            domain: .folderMetadata
        )
        let rollback = await executor.rollbackLibraryMetadata(pair.candidate, reason: .postconditionMismatch)
        let restoredBytes = try await applyPort.rootBoundLibraryMetadataBytes(
            objectID: pair.candidate.objectID,
            objectKind: .folder,
            domain: .folderMetadata
        )

        #expect(result.canarySucceeded)
        #expect(result.commits.first?.sideEffects.map(\.kind) == [.metadataApply])
        #expect(result.commits.first?.sideEffects.first?.domain == .folders)
        #expect(committedBytes == pair.bytes)
        #expect(rollback.succeeded)
        #expect(restoredBytes == previousBytes)
    }

    @Test func macProductionRootApplyPortIsDisabledByDefault() async throws {
        let rootURL = MacLibraryMetadataCutoverTestSupport.makeScratchRoot("MacLibraryMetadataProductionDisabled")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = MacLibraryMetadataCutoverTestSupport.folderCandidate()
        let applyPort = try MacLibraryMetadataRealApplyPort(productionRootURL: rootURL)
        try await applyPort.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)
        let executor = MacLibraryMetadataCutoverExecutor(applyPort: applyPort)

        let commit = await executor.commitLibraryMetadata(pair.candidate)

        #expect(applyPort.isDryRunOnly)
        #expect(applyPort.applyPortMode == .productionRootDisabled)
        #expect(commit.committed == false)
        #expect(commit.failureKind == .applyFailureBeforeCommit)
    }

    @Test func macV814GuardedCommitCanaryZeroNeverSuppressesLegacyDuplicates() {
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let localManifest = CanonicalManifest.make(
            node: CanonicalNode(nodeID: "mac-01", platform: "Mac", capabilities: [.canonicalLibraryObjectsV1]),
            generatedAt: Date(timeIntervalSince1970: 1_000),
            objects: [],
            libraryObjects: [candidate.localObject].compactMap { $0 },
            manifestCapabilities: [.canonicalLibraryObjectsV1]
        )
        let peerManifest = CanonicalManifest.make(
            node: CanonicalNode(nodeID: "iphone-01", platform: "iPhone", capabilities: [.canonicalLibraryObjectsV1]),
            generatedAt: Date(timeIntervalSince1970: 1_000),
            objects: [],
            libraryObjects: [candidate.peerObject].compactMap { $0 },
            manifestCapabilities: [.canonicalLibraryObjectsV1]
        )
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: .enabled(
                mode: .canaryCommit,
                policy: CanonicalLibraryMetadataCutoverAppSeamPolicy(
                    canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0)
                ),
                evidence: MacLibraryMetadataCutoverTestSupport.evidence(),
                cutoverToken: MacLibraryMetadataCutoverTestSupport.token()
            ),
            context: CanonicalLibraryMetadataGuardedCommitContext(
                syncRunID: "mac-v814-cutover-no-suppression",
                trigger: .periodic,
                nodeRole: .mac,
                localManifest: localManifest,
                peerManifest: peerManifest,
                legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                    .folders: [candidate.action.actionID]
                ]),
                evidence: MacLibraryMetadataCutoverTestSupport.evidence(),
                canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0),
                cutoverToken: MacLibraryMetadataCutoverTestSupport.token(),
                candidates: [candidate],
                localSnapshotAvailable: true,
                peerSnapshotAvailable: true
            )
        )

        #expect(result.succeeded)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.duplicateLegacySuppressionCandidates == [candidate.action.actionID])
        #expect(result.legacyPlanUnchanged)
        #expect(result.productionPlanUnchanged)
        #expect(result.noExecutionAssertion.passed)
    }
}

enum MacLibraryMetadataCutoverTestSupport {
    static func token() -> CanonicalCutoverToken {
        CanonicalCutoverToken(tokenID: "mac-library-metadata-token", syncRunID: "mac-sync-run-v810", ownerApproved: true)
    }

    static func evidence() -> CanonicalLibraryMetadataCutoverEvidence {
        CanonicalLibraryMetadataCutoverEvidence.passing(
            rollbackPlan: CanonicalRollbackPlan(
                planID: "mac-library-metadata-rollback-plan",
                checkpoints: [
                    CanonicalRollbackCheckpoint(checkpointID: "folder-checkpoint", domain: .folders, objectID: "folder:math")
                ],
                actions: [
                    CanonicalRollbackAction(actionID: "folder-rollback", kind: .metadataRollback, domain: .folders, checkpointID: "folder-checkpoint")
                ]
            )
        )
    }

    static func run(
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        executor: any CanonicalLibraryMetadataCutoverExecutor
    ) async -> CanonicalLibraryMetadataCutoverResult {
        await CanonicalLibraryMetadataCutoverRunner().run(
            mode: .canary,
            policy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 1, allowsInternalN1Execution: true),
            token: token(),
            evidence: evidence(),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .mac,
            executor: executor
        )
    }

    static func folderCandidate() -> (candidate: CanonicalLibraryMetadataCutoverCandidate, bytes: Data) {
        let local = folderObject(name: "Local Folder", modifiedAt: 2_000)
        let peer = folderObject(name: "Peer Folder", modifiedAt: 3_000)
        let action = CanonicalApplyAction(
            kind: .folderMetadataApply,
            source: .peer,
            target: CanonicalApplyTarget(objectID: "folder:math"),
            bridgeHint: .legacyMetadataManifestApply,
            reason: "macLibraryMetadataTest"
        )
        let candidate = CanonicalLibraryMetadataCutoverCandidate(
            action: action,
            localObject: local,
            peerObject: peer,
            rollbackCheckpointID: "folder-checkpoint"
        )
        return (candidate, metadataBytes(for: peer))
    }

    static func folderObject(name: String, modifiedAt: TimeInterval) -> CanonicalLibraryObject {
        let folderID = CanonicalLibraryObjectID("folder:math")
        let metadata = CanonicalFolderMetadata(
            folderID: folderID,
            name: name,
            hierarchyPath: CanonicalHierarchyPath(["course", "math"]),
            hierarchyLevel: "subject",
            colorToken: "blue",
            businessModifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: modifiedAt))
        )
        let folder = CanonicalFolderObject(metadata: metadata)
        return CanonicalLibraryObject(objectID: folder.folderID, kind: .folder, folder: folder)
    }

    static func metadataBytes(for object: CanonicalLibraryObject) -> Data {
        guard let folder = object.folder?.metadata else {
            return Data()
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(CanonicalProjectionContract.metadataHashPayload(for: folder))) ?? Data()
    }

    static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }
}
