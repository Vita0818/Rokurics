//
//  CanonicalLibraryMetadataCanaryStageTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalLibraryMetadataCanaryStageTests {
    @Test func macExpandedStageCommitsThreeFakePeerCandidatesThroughSharedRunner() async {
        let candidates = Self.folderCandidates(["folder:003", "folder:001", "folder:002", "folder:004"])
        let executor = V816MacLibraryMetadataSequencedExecutor()

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(stage: .n1, successCount: 1),
            candidates: candidates,
            peerSnapshotAvailable: true,
            executor: executor
        )

        #expect(result.succeeded)
        #expect(result.selection.selectedCandidates.map(\.objectID) == ["folder:001", "folder:002", "folder:003"])
        #expect(result.stageObservationReport.executedCount == 3)
        #expect(result.stageObservationReport.nextStageEligible)
        #expect(result.stageObservationReport.recommendation == .advanceToN10)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataExpandedReadSideParallelEquivalent })
        #expect(await executor.committedObjectIDs == ["folder:001", "folder:002", "folder:003"])
    }

    @Test func macExpandedStageBlocksWhenPeerSnapshotUnavailable() async {
        let candidates = Self.folderCandidates(["folder:001"])
        let executor = V816MacLibraryMetadataSequencedExecutor()

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(stage: .n1, successCount: 1),
            candidates: candidates,
            peerSnapshotAvailable: false,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.gate.failures.contains(.peerSnapshotUnavailable))
        #expect(result.cutoverResult.canaryAttemptedCount == 0)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(result.cutoverResult.diagnostics.contains { $0.kind == .canonicalLibraryMetadataN1MacPeerSnapshotUnavailable })
        #expect(result.stageObservationReport.legacyFallbackCount >= 1)
        #expect(await executor.committedObjectIDs.isEmpty)
    }

    @Test func macAllEligibleRequiresN10EvidenceAndSelectsAllCandidates() async {
        let blockedGate = CanonicalLibraryMetadataCanaryStageGate(
            policy: Self.policy(.allEligible, allowAllEligible: true).stagePolicy,
            evidence: Self.evidence(stage: .n3, successCount: 3)
        )
        #expect(blockedGate.allowed == false)
        #expect(blockedGate.failures.contains(.canaryStageOrderViolation))

        let candidates = Self.folderCandidates(["folder:004", "folder:001", "folder:003", "folder:002"])
        let executor = V816MacLibraryMetadataSequencedExecutor()
        let result = await Self.run(
            policy: Self.policy(.allEligible, allowAllEligible: true),
            evidence: Self.evidence(stage: .n10, successCount: 10),
            candidates: candidates,
            peerSnapshotAvailable: true,
            executor: executor
        )

        #expect(result.succeeded)
        #expect(result.selection.selectedCandidates.count == 4)
        #expect(result.stageObservationReport.stage == .allEligible)
        #expect(result.stageObservationReport.executedCount == 4)
        #expect(result.stageObservationReport.recommendation == .observeCurrentStage)
        #expect(result.stageObservationReport.nextStageEligible == false)
        #expect(await executor.committedObjectIDs == ["folder:001", "folder:002", "folder:003", "folder:004"])
    }

    @Test func macRollbackFailureIsFatalBlocker() async {
        let candidates = Self.folderCandidates(["folder:001"])
        let executor = V816MacLibraryMetadataSequencedExecutor(
            failingObjectIDs: ["folder:001"],
            rollbackSucceeds: false
        )

        let result = await Self.run(
            policy: Self.policy(.n3),
            evidence: Self.evidence(stage: .n1, successCount: 1),
            candidates: candidates,
            peerSnapshotAvailable: true,
            executor: executor
        )

        #expect(result.succeeded == false)
        #expect(result.cutoverResult.fatalBlocker)
        #expect(result.stageObservationReport.fatalBlockerCount == 1)
        #expect(result.stageObservationReport.recommendation == .stopForFatalBlocker)
        #expect(result.cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty)
    }

    private static func run(
        policy: CanonicalLibraryMetadataCanaryPolicy,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        peerSnapshotAvailable: Bool,
        executor: any CanonicalLibraryMetadataCutoverExecutor
    ) async -> CanonicalLibraryMetadataCanaryStageResult {
        await CanonicalLibraryMetadataCanaryStageRunner().run(
            policy: policy,
            token: MacLibraryMetadataCutoverTestSupport.token(),
            evidence: evidence,
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "v816-library-metadata-mac-stage",
            localSnapshotAvailable: true,
            peerSnapshotAvailable: peerSnapshotAvailable,
            executor: executor
        )
    }

    private static func policy(
        _ stage: CanonicalLibraryMetadataCanaryStage,
        allowAllEligible: Bool = false
    ) -> CanonicalLibraryMetadataCanaryPolicy {
        CanonicalLibraryMetadataCanaryPolicy(
            stagePolicy: CanonicalLibraryMetadataCanaryStagePolicy(
                requestedStage: stage,
                allowCandidateExecution: true
            ),
            explicitInternalTestConfiguration: true,
            allowAllEligible: allowAllEligible
        )
    }

    private static func evidence(
        stage: CanonicalLibraryMetadataCanaryStage,
        successCount: Int
    ) -> CanonicalLibraryMetadataCutoverEvidence {
        var evidence = MacLibraryMetadataCutoverTestSupport.evidence()
        evidence.canaryStageEvidence = .passing(stage: stage, successfulCommitCount: successCount)
        return evidence
    }

    private static func folderCandidates(_ objectIDs: [String]) -> [CanonicalLibraryMetadataCutoverCandidate] {
        objectIDs.map { objectID in
            CanonicalLibraryMetadataCutoverCandidate(
                action: CanonicalApplyAction(
                    kind: .folderMetadataApply,
                    source: .peer,
                    target: CanonicalApplyTarget(objectID: objectID),
                    bridgeHint: .legacyMetadataManifestApply,
                    reason: "macV816StageTest"
                ),
                localObject: folderObject(objectID: objectID, name: "Local \(objectID)", modifiedAt: 2_000),
                peerObject: folderObject(objectID: objectID, name: "Peer \(objectID)", modifiedAt: 3_000),
                rollbackCheckpointID: "checkpoint-\(objectID)"
            )
        }
    }

    private static func folderObject(
        objectID: String,
        name: String,
        modifiedAt: TimeInterval
    ) -> CanonicalLibraryObject {
        let folderID = CanonicalLibraryObjectID(objectID)
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
}

private actor V816MacLibraryMetadataSequencedExecutor: CanonicalLibraryMetadataCutoverExecutor {
    private let failingObjectIDs: Set<String>
    private let rollbackSucceeds: Bool
    private(set) var committedObjectIDs: [String] = []

    init(
        failingObjectIDs: Set<String> = [],
        rollbackSucceeds: Bool = true
    ) {
        self.failingObjectIDs = failingObjectIDs
        self.rollbackSucceeds = rollbackSucceeds
    }

    func commitLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate
    ) async -> CanonicalLibraryMetadataProductionCommitResult {
        committedObjectIDs.append(candidate.objectID)
        if failingObjectIDs.contains(candidate.objectID) {
            return .failure(
                candidate: candidate,
                kind: .postconditionMismatch,
                partialCommit: true,
                reason: "macV816InjectedFailure"
            )
        }
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
                    summary: "macV816LibraryMetadataApply"
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
            succeeded: rollbackSucceeds,
            fatal: !rollbackSucceeds,
            reason: rollbackSucceeds ? "macV816RollbackComplete" : "macV816RollbackFailed"
        )
    }
}
