//
//  CanonicalEffectiveStatusUIProjectionTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalEffectiveStatusUIProjectionTests {
    private static let objectID = CanonicalObjectID("recordingAudio:v960")
    private static let hash = String(repeating: "a", count: 64)

    @Test func metadataOnlyDoesNotDisplayCompleted() {
        let display = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: Self.objectID,
                localAudioByteSize: 100,
                legacyMetadataOnly: true
            )
        )

        #expect(display.canDisplayAsComplete == false)
        #expect(display.kind != .completed)
        #expect(display.kind != .peerVerified)
        #expect(display.effectiveStatus.blocker == .metadataOnlyRejectedAsAudioProof)
    }

    @Test func completedLedgerAloneDoesNotDisplayPeerVerified() {
        let display = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: Self.objectID,
                localAudioHash: CanonicalHash(Self.hash),
                localAudioByteSize: 100,
                legacyCompletedLedger: true
            )
        )

        #expect(display.canDisplayAsComplete == false)
        #expect(display.kind != .completed)
        #expect(display.kind != .peerVerified)
    }

    @Test func partialReceiveDoesNotDisplayCompleted() {
        let display = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: Self.objectID,
                legacyPartialReceive: true
            )
        )

        #expect(display.canDisplayAsComplete == false)
        #expect(display.kind == .uploading)
        #expect(display.effectiveStatus.blocker == .partialReceiveRejectedAsCompleted)
    }

    @Test func localFileExistsOnlyDoesNotDisplayPeerVerified() {
        let display = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: Self.objectID,
                localAudioHash: CanonicalHash(Self.hash),
                localAudioByteSize: 100
            )
        )

        #expect(display.canDisplayAsComplete == false)
        #expect(display.kind != .completed)
        #expect(display.kind != .peerVerified)
        #expect(display.effectiveStatus.blocker == .localFileExistsIsNotPeerProof)
    }

    @Test func iPhoneLegacyUploadedRequiresFinalizeProof() {
        let ledgerOnly = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusToCanonicalEffectiveStatusAdapter.iPhoneUploadSnapshot(
                recordingID: "v960",
                localAudioByteSize: 100,
                legacyStatus: "uploaded"
            )
        )
        let finalized = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusToCanonicalEffectiveStatusAdapter.iPhoneUploadSnapshot(
                recordingID: "v960",
                localAudioByteSize: 100,
                provenUploadHash: Self.hash,
                provenUploadByteSize: 100,
                legacyStatus: "uploaded"
            )
        )

        #expect(ledgerOnly.canDisplayAsComplete == false)
        #expect(ledgerOnly.kind != .completed)
        #expect(finalized.kind == .completed)
        #expect(finalized.canDisplayAsComplete)
        #expect(finalized.effectiveStatus.proof?.kind == .finalizeProof)
        #expect(finalized.effectiveStatus.proof?.hasAcceptedFinalizeProof == true)
    }

    @Test func peerInventoryHashSizeMatchDisplaysPeerVerified() {
        let display = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: Self.objectID,
                peerInventoryHash: CanonicalHash(Self.hash),
                peerInventoryByteSize: 100
            )
        )

        #expect(display.kind == .peerVerified)
        #expect(display.canDisplayAsComplete)
        #expect(display.effectiveStatus.proof?.kind == .peerInventoryHashSizeMatch)
    }

    @Test func existingDifferentAudioDisplaysConflictNoOverwrite() {
        let display = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: Self.objectID,
                localAudioHash: CanonicalHash(Self.hash),
                localAudioByteSize: 100,
                conflict: true
            )
        )

        #expect(display.kind == .conflict)
        #expect(display.canDisplayAsComplete == false)
        #expect(display.effectiveStatus.blocker == .existingDifferentAudioConflict)
    }

    @Test func peerUnknownAndViewRefreshDoNotCreateUploadJob() {
        let peerUnknown = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: Self.objectID,
                localAudioByteSize: 100,
                peerUnknown: true
            )
        )
        let viewRefresh = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: Self.objectID,
                localAudioByteSize: 100,
                legacyMetadataOnly: true,
                viewRefresh: true
            )
        )

        #expect(peerUnknown.canCreateUploadJob == false)
        #expect(peerUnknown.kind == .deferred)
        #expect(viewRefresh.canCreateUploadJob == false)
        #expect(viewRefresh.effectiveStatus.blocker == .viewRefreshCannotCreateUploadJob)
    }

    @Test @MainActor func studyLibraryStoreExposesCachedEffectiveStatusSnapshot() async throws {
        let runtime = CanonicalStatusTruthRuntime()
        let store = StudyLibraryStore(
            rootURL: Self.temporaryRoot(),
            canonicalStatusTruthRuntime: runtime
        )
        _ = await store.produceCanonicalStatusFact(Self.finalizeProofFact())

        let before = await runtime.projectionMetricsSnapshot()
        let status = store.effectiveSyncStatus(for: Self.objectID)
        let display = store.canonicalDisplaySyncState(for: Self.objectID)
        let after = await runtime.projectionMetricsSnapshot()

        #expect(status?.phase == .completed)
        #expect(display?.kind == .completed)
        #expect(before == after)
    }

    @Test func recordingUploadCoordinatorDisplayGetterDoesNotReadLedgerOrReconcile() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Rokurics/RecordingUploadCoordinator.swift"),
            encoding: .utf8
        )
        guard let range = source.range(of: "func displaySyncState(for metadata: RecordingMetadata)") else {
            Issue.record("displaySyncState(for:) not found")
            return
        }
        let tail = source[range.lowerBound...]
        let body: Substring
        if let end = tail.range(of: "func refreshDisplaySnapshot(for metadata: RecordingMetadata)") {
            body = tail[..<end.lowerBound]
        } else {
            body = tail.prefix(900)
        }

        #expect(body.contains("displaySyncStateByObjectID"))
        #expect(body.contains("jobStore.loadJob") == false)
        #expect(body.contains("effectiveStatus(for:") == false)
        #expect(body.contains("upload(") == false)
    }

    @Test func recordingLibraryViewUsesDisplaySyncStateAsSingleFinalStatusSource() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Rokurics/RecordingLibraryView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("uploadStatus(for:") == false)
        #expect(source.contains("canonicalDisplaySyncState(for item: StudyItemMetadata)"))
        #expect(source.contains("displaySyncState.canDisplayAsComplete") == false)
        #expect(source.contains("uploadCoordinator.displayStatus(for:") == false)
        #expect(source.contains("uploadCoordinator.displaySyncState(for:") == false)
        #expect(source.contains("uploadCoordinator.canonicalDisplaySyncState(for:"))
        #expect(source.contains("displaySyncState: canonicalDisplaySyncState(for: item)"))
    }

    @Test func recordingStudyDetailPageUsesDisplaySyncStateForFinalUploadActions() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Rokurics/RecordingStudyDetailPage.swift"),
            encoding: .utf8
        )

        #expect(source.contains("displayStatus(for:") == false)
        #expect(source.contains("displaySyncState(for:") == false)
        #expect(source.contains("private var uploadStatus") == false)
        #expect(source.contains("uploadCoordinator.canonicalDisplaySyncState(for:"))
        #expect(source.contains("displaySyncState: canonicalDisplaySyncState"))
        #expect(source.contains("displaySyncState: CanonicalDisplaySyncState?"))
    }

    private static func finalizeProofFact() -> CanonicalStatusFact {
        let proof = CanonicalTransferFinalizeProof(
            sessionID: CanonicalTransferSessionID("v911-session"),
            objectID: objectID,
            receiverNodeID: CanonicalNodeID("mac"),
            contentHash: CanonicalHash(hash),
            byteSize: 100,
            acceptedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 9_110)),
            verified: true
        )
        return CanonicalStatusFact(
            factID: "v911-finalize",
            objectID: objectID,
            source: .transferFinalizeProof,
            producerNodeID: CanonicalNodeID("iphone"),
            logicalTime: CanonicalLogicalTime(counter: 1, nodeID: CanonicalNodeID("iphone")),
            proof: CanonicalStatusProof(
                kind: .finalizeProof,
                objectID: objectID,
                hash: proof.contentHash,
                byteSize: proof.byteSize,
                peerNodeID: proof.receiverNodeID,
                finalizeProof: proof,
                observedAt: proof.finalizedAt
            ),
            domain: .audioUpload,
            phase: .completed,
            causality: CanonicalStatusCausality(trigger: .transferFinalize)
        )
    }

    private static func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Rokurics-v911-\(UUID().uuidString)", isDirectory: true)
    }
}
