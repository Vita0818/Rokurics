//
//  CanonicalLibraryMetadataCanaryTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalLibraryMetadataCanaryTests {
    @Test func macN1CanaryCanCommitOneSafeFakePeerCandidateThroughSharedRunner() async {
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = V815MacLibraryMetadataFakeExecutor()

        let result = await Self.run(
            candidates: [candidate],
            peerSnapshotAvailable: true,
            executor: executor
        )

        #expect(result.succeeded)
        #expect(result.cutoverResult.canaryAttemptedCount == 1)
        #expect(result.selection.selectedCandidates.count == 1)
        #expect(result.observationReport.status == .committed)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1CanaryConfigured })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1CommitCompleted })
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1ReadSideParallelEquivalent })
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
    }

    @Test func macInventoryN1BlocksWhenPeerSnapshotIsUnavailable() async {
        let candidate = MacLibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = V815MacLibraryMetadataFakeExecutor()

        let result = await Self.run(
            candidates: [candidate],
            peerSnapshotAvailable: false,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.gate.failures.contains(.peerSnapshotUnavailable))
        #expect(result.cutoverResult.canaryAttemptedCount == 0)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1MacPeerSnapshotUnavailable })
        #expect(result.observationReport.legacyFallbackPreserved)
        #expect(await executor.committedActionIDs.isEmpty)
    }

    @Test func macN1BlocksUnsafeResourceMoveBeforeCommit() async {
        let candidate = Self.resourceMoveCandidate()
        let executor = V815MacLibraryMetadataFakeExecutor()

        let result = await Self.run(
            candidates: [candidate],
            peerSnapshotAvailable: true,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.selection.blockers.contains { $0.reason == .resourceMoveAttempted })
        #expect(result.cutoverResult.candidateSafetyReports?.first?.resourceMoveAttempted == true)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(await executor.committedActionIDs.isEmpty)
    }

    private static func run(
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        peerSnapshotAvailable: Bool,
        executor: any CanonicalLibraryMetadataCutoverExecutor
    ) async -> CanonicalLibraryMetadataCanaryResult {
        await CanonicalLibraryMetadataN1CanaryRunner().run(
            configuration: .internalN1(),
            policy: CanonicalLibraryMetadataCanaryPolicy(
                canaryMaxObjectsPerSyncRun: 1,
                allowsInternalN1Execution: true,
                explicitInternalTestConfiguration: true
            ),
            token: MacLibraryMetadataCutoverTestSupport.token(),
            evidence: MacLibraryMetadataCutoverTestSupport.evidence(),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "v815-library-metadata-mac-canary",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: peerSnapshotAvailable,
            executor: executor
        )
    }

    private static func resourceMoveCandidate() -> CanonicalLibraryMetadataCutoverCandidate {
        CanonicalLibraryMetadataCutoverCandidate(
            action: CanonicalApplyAction(
                kind: .studyItemMetadataApply,
                source: .peer,
                target: CanonicalApplyTarget(objectID: "item:note"),
                bridgeHint: .legacyMetadataManifestApply,
                reason: "macV815ResourceMoveTest"
            ),
            localObject: studyObject(resources: ["notes/local.md"], modifiedAt: 2_000),
            peerObject: studyObject(resources: ["notes/peer.md"], modifiedAt: 3_000),
            rollbackCheckpointID: "note-checkpoint"
        )
    }

    private static func studyObject(resources: [String], modifiedAt: TimeInterval) -> CanonicalLibraryObject {
        let itemID = CanonicalLibraryObjectID("item:note")
        let folderID = CanonicalLibraryObjectID("folder:math")
        let metadata = CanonicalStudyItemMetadata(
            itemID: itemID,
            itemKind: .standaloneNote,
            title: "Note",
            filingPath: CanonicalHierarchyPath(["course", "math"]),
            folderIDs: [folderID],
            parentReferences: [CanonicalParentReference(parentID: folderID, relation: "folder")],
            tags: ["alpha"],
            logicalResourceTokens: resources,
            businessModifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: modifiedAt))
        )
        let item = CanonicalStudyItemObject(metadata: metadata)
        return CanonicalLibraryObject(
            objectID: item.itemID,
            kind: .standaloneNote,
            studyItem: item,
            standaloneNote: CanonicalStandaloneNoteObject(studyItem: item)
        )
    }
}

private actor V815MacLibraryMetadataFakeExecutor: CanonicalLibraryMetadataCutoverExecutor {
    private(set) var committedActionIDs: [String] = []

    func commitLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate
    ) async -> CanonicalLibraryMetadataProductionCommitResult {
        committedActionIDs.append(candidate.action.actionID)
        return .success(
            candidate: candidate,
            payloadByteCount: 64,
            sideEffects: [
                CanonicalProductionSideEffect(
                    kind: .metadataApply,
                    domain: candidate.domain.productionDomain,
                    objectID: candidate.objectID,
                    byteSize: 64,
                    hash: candidate.expectedMetadataHash,
                    summary: "macV815LibraryMetadataApply"
                )
            ]
        )
    }

    func rollbackLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate,
        reason: CanonicalLibraryMetadataCutoverFailure
    ) async -> CanonicalLibraryMetadataRollbackExecutionResult {
        CanonicalLibraryMetadataRollbackExecutionResult(
            checkpointID: candidate.effectiveRollbackCheckpointID,
            succeeded: true,
            reason: "macV815Rollback"
        )
    }
}
