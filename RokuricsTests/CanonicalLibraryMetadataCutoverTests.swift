//
//  CanonicalLibraryMetadataCutoverTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLibraryMetadataCutoverTests {
    @Test func appSeamDefaultsDisabledAndCanaryBudgetZero() {
        let config = CanonicalLibraryMetadataCutoverAppSeamConfiguration()

        #expect(config.isEnabled == false)
        #expect(config.effectiveMode == .disabled)
        #expect(config.policy.canaryPolicy.canaryMaxObjectsPerSyncRun == 0)
        #expect(config.policy.canaryPolicy.allowsInternalN1Execution == false)
        #expect(config.policy.canaryPolicy.stagePolicy.requestedStage == .disabled)
    }

    @Test func candidateGenerationCoversFolderStudyItemAndStandaloneNoteMetadataOnly() throws {
        let local = LibraryMetadataCutoverTestSupport.manifest([
            LibraryMetadataCutoverTestSupport.folderObject(name: "Local Folder", modifiedAt: 2_000),
            LibraryMetadataCutoverTestSupport.studyObject(kind: .externalResource, objectID: "item:study", title: "Local Study", tags: ["old"], modifiedAt: 2_000),
            LibraryMetadataCutoverTestSupport.studyObject(kind: .standaloneNote, objectID: "item:note", title: "Local Note", resources: ["notes/local.md"], modifiedAt: 2_000)
        ])
        let peer = LibraryMetadataCutoverTestSupport.manifest([
            LibraryMetadataCutoverTestSupport.folderObject(name: "Peer Folder", modifiedAt: 3_000),
            LibraryMetadataCutoverTestSupport.studyObject(kind: .externalResource, objectID: "item:study", title: "Peer Study", tags: ["new", "review"], modifiedAt: 3_000),
            LibraryMetadataCutoverTestSupport.studyObject(kind: .standaloneNote, objectID: "item:note", title: "Peer Note", resources: ["notes/local.md"], modifiedAt: 3_000)
        ])
        let plan = CanonicalLibrarySyncPlanner().plan(local: local, peer: peer, trigger: .periodic)

        let candidates = CanonicalLibraryMetadataCutoverCandidate.candidates(
            from: plan,
            localManifest: local,
            peerManifest: peer
        )
        let folder = try #require(candidates.first { $0.objectKind == CanonicalObjectKind.folder })
        let study = try #require(candidates.first { $0.objectID == "item:study" })
        let note = try #require(candidates.first { $0.objectKind == CanonicalObjectKind.standaloneNote })

        #expect(folder.cutoverActionKind == CanonicalLibraryMetadataCutoverActionKind.folderApply)
        #expect(folder.metadataTitle == "Peer Folder")
        #expect(study.cutoverActionKind == CanonicalLibraryMetadataCutoverActionKind.studyItemApply)
        #expect(study.tagCount == 2)
        #expect(study.filingSummary == "course/math")
        #expect(note.cutoverActionKind == CanonicalLibraryMetadataCutoverActionKind.standaloneNoteApply)
        #expect(note.logicalResourceTokens == ["notes/local.md"])
        #expect(note.logicalResourceTokens.contains { $0.contains("audio") || $0.hasPrefix("/") } == false)
    }

    @Test func noCommitExecutorStagesOnlySummaryAndPreservesLegacyFallback() throws {
        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneLibraryMetadataNoCommit")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = IPhoneLibraryMetadataNoCommitExecutor(stagingRootURL: rootURL)

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
        #expect(result.payloadByteCount > 0)
        #expect(FileManager.default.fileExists(atPath: rootURL.path) == false)
    }

    @Test func rootBoundApplyCommitAndRollbackRestorePreviousBytes() async throws {
        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneLibraryMetadataRootBound")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = LibraryMetadataCutoverTestSupport.folderCandidate()
        let previousBytes = Data("previous-folder-metadata".utf8)
        let logicalPath = CanonicalRootBoundLibraryMetadataTarget.defaultLogicalPathToken(
            objectID: pair.candidate.objectID,
            objectKind: .folder,
            domain: .folderMetadata
        )
        let previousURL = rootURL.appendingPathComponent(logicalPath)
        try FileManager.default.createDirectory(at: previousURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try previousBytes.write(to: previousURL)

        let applyPort = try IPhoneLibraryMetadataRealApplyPort(testRootURL: rootURL)
        try await applyPort.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)
        let executor = IPhoneLibraryMetadataCutoverExecutor(applyPort: applyPort)

        let result = await LibraryMetadataCutoverTestSupport.run(
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

    @Test func productionRootApplyPortIsDisabledByDefault() async throws {
        let rootURL = LibraryMetadataCutoverTestSupport.makeScratchRoot("IPhoneLibraryMetadataProductionDisabled")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pair = LibraryMetadataCutoverTestSupport.folderCandidate()
        let applyPort = try IPhoneLibraryMetadataRealApplyPort(productionRootURL: rootURL)
        try await applyPort.setRootBoundLibraryMetadataPayload(candidate: pair.candidate, metadataBytes: pair.bytes)
        let executor = IPhoneLibraryMetadataCutoverExecutor(applyPort: applyPort)

        let commit = await executor.commitLibraryMetadata(pair.candidate)

        #expect(applyPort.isDryRunOnly)
        #expect(applyPort.applyPortMode == .productionRootDisabled)
        #expect(commit.committed == false)
        #expect(commit.failureKind == .applyFailureBeforeCommit)
        #expect(try await applyPort.rootBoundLibraryMetadataBytes(
            objectID: pair.candidate.objectID,
            objectKind: .folder,
            domain: .folderMetadata
        ) == nil)
    }

    @Test func canaryStagePolicyAdvancesOnlyAfterCleanPreviousStage() {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let n3PassingEvidence = LibraryMetadataCutoverTestSupport.evidence(
            stageEvidence: CanonicalLibraryMetadataCanaryStageEvidence(
                stage: .n1,
                previousStage: .n1,
                status: .passed,
                successfulCommitCount: 1,
                noCommitEvidenceAvailable: true,
                observationWindowComplete: true
            )
        )
        let n3Policy = CanonicalLibraryMetadataCanaryPolicy(
            stagePolicy: CanonicalLibraryMetadataCanaryStagePolicy(requestedStage: .n3, allowCandidateExecution: true),
            canaryMaxObjectsPerSyncRun: 3
        )
        let allowedGate = CanonicalLibraryMetadataCutoverRunner().evaluateGate(
            mode: .canary,
            policy: n3Policy,
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: n3PassingEvidence,
            candidates: [candidate],
            trigger: .periodic
        )
        let rollbackFailedEvidence = LibraryMetadataCutoverTestSupport.evidence(
            stageEvidence: CanonicalLibraryMetadataCanaryStageEvidence(
                stage: .n1,
                previousStage: .n1,
                status: .passed,
                successfulCommitCount: 1,
                rollbackFailureCount: 1,
                noCommitEvidenceAvailable: true,
                observationWindowComplete: true
            )
        )
        let blockedGate = CanonicalLibraryMetadataCutoverRunner().evaluateGate(
            mode: .canary,
            policy: n3Policy,
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: rollbackFailedEvidence,
            candidates: [candidate],
            trigger: .periodic
        )

        #expect(allowedGate.allowed)
        #expect(blockedGate.allowed == false)
        #expect(blockedGate.failures.contains(.previousStageRollbackFailure))
    }

    @Test func gateBlocksResourceMoveCyclesAndConflicts() {
        let resourceMoveGate = CanonicalLibraryMetadataCutoverRunner().evaluateGate(
            mode: .canary,
            policy: LibraryMetadataCutoverTestSupport.n1Policy(),
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: LibraryMetadataCutoverTestSupport.evidence(),
            candidates: [LibraryMetadataCutoverTestSupport.resourceMoveCandidate()],
            trigger: .periodic
        )
        let cycleGate = CanonicalLibraryMetadataCutoverRunner().evaluateGate(
            mode: .canary,
            policy: LibraryMetadataCutoverTestSupport.n1Policy(),
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: LibraryMetadataCutoverTestSupport.evidence(),
            candidates: LibraryMetadataCutoverTestSupport.cycleCandidates(),
            trigger: .periodic
        )
        let conflictGate = CanonicalLibraryMetadataCutoverRunner().evaluateGate(
            mode: .canary,
            policy: LibraryMetadataCutoverTestSupport.n1Policy(),
            token: LibraryMetadataCutoverTestSupport.token(),
            evidence: LibraryMetadataCutoverTestSupport.evidence(),
            candidates: [LibraryMetadataCutoverTestSupport.conflictCandidate()],
            trigger: .periodic
        )

        #expect(resourceMoveGate.failures.contains(.resourceMoveAttempted))
        #expect(cycleGate.failures.contains(.cycleDetected))
        #expect(conflictGate.failures.contains(.conflictDetected))
    }

    @Test func canaryCommitSuppressesOnlyMatchingLegacyMetadataAfterSuccess() async {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor()

        let result = await LibraryMetadataCutoverTestSupport.run(candidates: [candidate], executor: executor)
        let suppressed = CanonicalLibraryMetadataLegacyDuplicateSuppression.suppressedLegacyActionIDs(
            after: result,
            legacyActions: [
                CanonicalLibraryMetadataLegacyActionIdentity(
                    actionID: "legacy-match",
                    objectID: candidate.objectID,
                    objectKind: .folder,
                    domain: .folderMetadata,
                    actionKind: .folderApply
                ),
                CanonicalLibraryMetadataLegacyActionIdentity(
                    actionID: "legacy-send",
                    objectID: candidate.objectID,
                    objectKind: .folder,
                    domain: .folderMetadata,
                    actionKind: .folderSend
                )
            ]
        )

        #expect(result.canarySucceeded)
        #expect(result.duplicateLegacySuppressedActionIDs == [candidate.action.actionID])
        #expect(suppressed == ["legacy-match"])
        #expect(await executor.committedActionIDs == [candidate.action.actionID])
    }

    @Test func failureRollsBackAndPreservesLegacyFallback() async {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let executor = LibraryMetadataCutoverTestSupport.FakeExecutor(.postconditionMismatch)

        let result = await LibraryMetadataCutoverTestSupport.run(candidates: [candidate], executor: executor)
        let suppressed = CanonicalLibraryMetadataLegacyDuplicateSuppression.suppressedLegacyActionIDs(
            after: result,
            legacyActions: [
                CanonicalLibraryMetadataLegacyActionIdentity(
                    actionID: "legacy-match",
                    objectID: candidate.objectID,
                    objectKind: .folder,
                    domain: .folderMetadata,
                    actionKind: .folderApply
                )
            ]
        )

        #expect(result.canarySucceeded == false)
        #expect(result.rollbackResults.first?.succeeded == true)
        #expect(result.legacyFallbackUsed)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(suppressed.isEmpty)
        #expect(await executor.rolledBackActionIDs == [candidate.action.actionID])
    }

    @Test func readSideProjectionIsDiagnosticsOnly() async throws {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let result = await LibraryMetadataCutoverTestSupport.run(
            candidates: [candidate],
            executor: LibraryMetadataCutoverTestSupport.FakeExecutor()
        )
        let projection = try #require(result.readSideProjection)

        #expect(projection.equivalent)
        #expect(projection.mutatedUI == false)
        #expect(projection.noResourceFileMove)
        #expect(projection.syncOrUploadTriggered == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataUIProjectionParallelReadStarted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataUIProjectionParallelReadEquivalent })
    }

    @Test func v814GuardedCommitCanaryZeroNeverSuppressesLegacyDuplicates() {
        let candidate = LibraryMetadataCutoverTestSupport.folderCandidate().candidate
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: .enabled(
                mode: .canaryCommit,
                policy: CanonicalLibraryMetadataCutoverAppSeamPolicy(
                    canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0)
                ),
                evidence: LibraryMetadataCutoverTestSupport.evidence(),
                cutoverToken: LibraryMetadataCutoverTestSupport.token()
            ),
            context: CanonicalLibraryMetadataGuardedCommitContext(
                syncRunID: "v814-cutover-no-suppression",
                trigger: .periodic,
                nodeRole: .iPhone,
                localManifest: LibraryMetadataCutoverTestSupport.manifest([candidate.localObject].compactMap { $0 }),
                peerManifest: LibraryMetadataCutoverTestSupport.manifest([candidate.peerObject].compactMap { $0 }),
                legacyActionSnapshot: CanonicalLegacyActionSnapshot(actionIDsByDomain: [
                    .folders: [candidate.action.actionID]
                ]),
                evidence: LibraryMetadataCutoverTestSupport.evidence(),
                canaryPolicy: CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 0),
                cutoverToken: LibraryMetadataCutoverTestSupport.token(),
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

enum LibraryMetadataCutoverTestSupport {
    static func token() -> CanonicalCutoverToken {
        CanonicalCutoverToken(tokenID: "library-metadata-token", syncRunID: "sync-run-v810", ownerApproved: true)
    }

    static func n1Policy() -> CanonicalLibraryMetadataCanaryPolicy {
        CanonicalLibraryMetadataCanaryPolicy(canaryMaxObjectsPerSyncRun: 1, allowsInternalN1Execution: true)
    }

    static func evidence(
        stageEvidence: CanonicalLibraryMetadataCanaryStageEvidence? = nil
    ) -> CanonicalLibraryMetadataCutoverEvidence {
        var evidence = CanonicalLibraryMetadataCutoverEvidence.passing(rollbackPlan: rollbackPlan())
        evidence.canaryStageEvidence = stageEvidence
        return evidence
    }

    static func rollbackPlan() -> CanonicalRollbackPlan {
        CanonicalRollbackPlan(
            planID: "library-metadata-rollback-plan",
            checkpoints: [
                CanonicalRollbackCheckpoint(checkpointID: "folder-checkpoint", domain: .folders, objectID: "folder:math"),
                CanonicalRollbackCheckpoint(checkpointID: "study-checkpoint", domain: .studyItems, objectID: "item:study"),
                CanonicalRollbackCheckpoint(checkpointID: "note-checkpoint", domain: .standaloneNotes, objectID: "item:note")
            ],
            actions: [
                CanonicalRollbackAction(actionID: "folder-rollback", kind: .metadataRollback, domain: .folders, checkpointID: "folder-checkpoint"),
                CanonicalRollbackAction(actionID: "study-rollback", kind: .metadataRollback, domain: .studyItems, checkpointID: "study-checkpoint"),
                CanonicalRollbackAction(actionID: "note-rollback", kind: .metadataRollback, domain: .standaloneNotes, checkpointID: "note-checkpoint")
            ]
        )
    }

    static func run(
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        executor: any CanonicalLibraryMetadataCutoverExecutor
    ) async -> CanonicalLibraryMetadataCutoverResult {
        await CanonicalLibraryMetadataCutoverRunner().run(
            mode: .canary,
            policy: n1Policy(),
            token: token(),
            evidence: evidence(),
            candidates: candidates,
            trigger: .periodic,
            nodeRole: .iPhone,
            executor: executor
        )
    }

    static func folderCandidate() -> (candidate: CanonicalLibraryMetadataCutoverCandidate, bytes: Data) {
        let local = folderObject(name: "Local Folder", modifiedAt: 2_000)
        let peer = folderObject(name: "Peer Folder", modifiedAt: 3_000)
        let candidate = CanonicalLibraryMetadataCutoverCandidate(
            action: action(kind: .folderMetadataApply, objectID: "folder:math", bridgeHint: .legacyMetadataManifestApply),
            localObject: local,
            peerObject: peer,
            rollbackCheckpointID: "folder-checkpoint"
        )
        return (candidate, metadataBytes(for: peer))
    }

    static func resourceMoveCandidate() -> CanonicalLibraryMetadataCutoverCandidate {
        CanonicalLibraryMetadataCutoverCandidate(
            action: action(kind: .studyItemMetadataApply, objectID: "item:note", bridgeHint: .legacyMetadataManifestApply),
            localObject: studyObject(kind: .standaloneNote, objectID: "item:note", resources: ["notes/local.md"], modifiedAt: 2_000),
            peerObject: studyObject(kind: .standaloneNote, objectID: "item:note", resources: ["notes/peer.md"], modifiedAt: 3_000),
            rollbackCheckpointID: "note-checkpoint"
        )
    }

    static func conflictCandidate() -> CanonicalLibraryMetadataCutoverCandidate {
        CanonicalLibraryMetadataCutoverCandidate(
            action: action(kind: .conflictRecord, objectID: "folder:math", source: .planner, bridgeHint: .legacyFallbackPreserved),
            localObject: folderObject(name: "Local", modifiedAt: 2_000),
            peerObject: folderObject(name: "Peer", modifiedAt: 2_000),
            rollbackCheckpointID: "folder-checkpoint"
        )
    }

    static func cycleCandidates() -> [CanonicalLibraryMetadataCutoverCandidate] {
        [
            CanonicalLibraryMetadataCutoverCandidate(
                action: action(kind: .folderMetadataApply, objectID: "folder:a", bridgeHint: .legacyMetadataManifestApply),
                localObject: folderObject(objectID: "folder:a", name: "A", parentID: "folder:b", modifiedAt: 2_000),
                peerObject: folderObject(objectID: "folder:a", name: "A", parentID: "folder:b", modifiedAt: 3_000),
                rollbackCheckpointID: "folder-a-checkpoint"
            ),
            CanonicalLibraryMetadataCutoverCandidate(
                action: action(kind: .folderMetadataApply, objectID: "folder:b", bridgeHint: .legacyMetadataManifestApply),
                localObject: folderObject(objectID: "folder:b", name: "B", parentID: "folder:a", modifiedAt: 2_000),
                peerObject: folderObject(objectID: "folder:b", name: "B", parentID: "folder:a", modifiedAt: 3_000),
                rollbackCheckpointID: "folder-b-checkpoint"
            )
        ]
    }

    static func manifest(_ objects: [CanonicalLibraryObject]) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(nodeID: "iphone-01", platform: "iPhone", capabilities: [.canonicalLibraryObjectsV1]),
            generatedAt: date(5_000),
            objects: [],
            libraryObjects: objects,
            manifestCapabilities: [.canonicalLibraryObjectsV1]
        )
    }

    static func folderObject(
        objectID: String = "folder:math",
        name: String,
        parentID: String? = nil,
        modifiedAt: TimeInterval = 2_000
    ) -> CanonicalLibraryObject {
        let folderID = CanonicalLibraryObjectID(objectID)
        let metadata = CanonicalFolderMetadata(
            folderID: folderID,
            name: name,
            parentID: parentID.map { CanonicalLibraryObjectID($0) },
            hierarchyPath: CanonicalHierarchyPath(["course", "math"]),
            hierarchyLevel: "subject",
            colorToken: "blue",
            businessModifiedAt: ts(modifiedAt)
        )
        let folder = CanonicalFolderObject(metadata: metadata)
        return CanonicalLibraryObject(objectID: folder.folderID, kind: .folder, folder: folder)
    }

    static func studyObject(
        kind: CanonicalStudyItemKind,
        objectID: String,
        title: String = "Note",
        tags: [String] = ["alpha"],
        resources: [String] = ["notes/item.md"],
        modifiedAt: TimeInterval = 2_000
    ) -> CanonicalLibraryObject {
        let itemID = CanonicalLibraryObjectID(objectID)
        let folderID = CanonicalLibraryObjectID("folder:math")
        let metadata = CanonicalStudyItemMetadata(
            itemID: itemID,
            itemKind: kind,
            title: title,
            filingPath: CanonicalHierarchyPath(["course", "math"]),
            folderIDs: [folderID],
            parentReferences: [CanonicalParentReference(parentID: folderID, relation: "folder")],
            tags: tags,
            logicalResourceTokens: resources,
            businessModifiedAt: ts(modifiedAt)
        )
        let item = CanonicalStudyItemObject(metadata: metadata)
        let objectKind: CanonicalObjectKind = kind == .standaloneNote ? .standaloneNote : .standaloneStudyItem
        return CanonicalLibraryObject(
            objectID: item.itemID,
            kind: objectKind,
            studyItem: item,
            standaloneNote: kind == .standaloneNote ? CanonicalStandaloneNoteObject(studyItem: item) : nil
        )
    }

    static func metadataBytes(for object: CanonicalLibraryObject) -> Data {
        if let folder = object.folder?.metadata {
            return sortedJSONBytes(CanonicalProjectionContract.metadataHashPayload(for: folder))
        }
        if let item = object.studyItem?.metadata {
            return sortedJSONBytes(CanonicalProjectionContract.metadataHashPayload(for: item))
        }
        return Data()
    }

    static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    private static func action(
        kind: CanonicalApplyActionKind,
        objectID: String,
        source: CanonicalApplySource = .peer,
        bridgeHint: CanonicalApplyBridgeHint?
    ) -> CanonicalApplyAction {
        CanonicalApplyAction(
            kind: kind,
            source: source,
            target: CanonicalApplyTarget(objectID: objectID),
            bridgeHint: bridgeHint,
            reason: "libraryMetadataTest"
        )
    }

    private static func sortedJSONBytes(_ payload: [String: String]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(payload)) ?? Data()
    }

    private static func ts(_ value: TimeInterval) -> CanonicalTimestamp {
        CanonicalTimestamp(date(value))
    }

    private static func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }

    actor FakeExecutor: CanonicalLibraryMetadataCutoverExecutor {
        private let failure: CanonicalLibraryMetadataCutoverFailure?
        private(set) var committedActionIDs: [String] = []
        private(set) var rolledBackActionIDs: [String] = []

        init(_ failure: CanonicalLibraryMetadataCutoverFailure? = nil) {
            self.failure = failure
        }

        func commitLibraryMetadata(
            _ candidate: CanonicalLibraryMetadataCutoverCandidate
        ) async -> CanonicalLibraryMetadataProductionCommitResult {
            if let failure {
                return .failure(candidate: candidate, kind: failure, partialCommit: true, reason: "injectedLibraryMetadataFailure")
            }
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
                        summary: "testLibraryMetadataApply"
                    )
                ]
            )
        }

        func rollbackLibraryMetadata(
            _ candidate: CanonicalLibraryMetadataCutoverCandidate,
            reason: CanonicalLibraryMetadataCutoverFailure
        ) async -> CanonicalLibraryMetadataRollbackExecutionResult {
            rolledBackActionIDs.append(candidate.action.actionID)
            return CanonicalLibraryMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: true,
                reason: "testLibraryMetadataRollback"
            )
        }
    }
}
