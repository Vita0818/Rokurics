//
//  CanonicalEffectiveStatusUIProjectionTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import RokuricsMac

@Suite(.serialized)
struct CanonicalEffectiveStatusUIProjectionTests {
    private static let hash = String(repeating: "b", count: 64)

    @Test func macMetadataOnlyAndReceiveRecordDoNotDisplayAudioAvailable() {
        let metadataOnly = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusToCanonicalEffectiveStatusAdapter.macAudioSnapshot(
                recordingID: "v960-metadata",
                hasLocalAudio: false,
                audioChecksum: nil,
                audioByteSize: 0,
                receiveStatus: nil
            )
        )
        let receiveRecordOnly = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusToCanonicalEffectiveStatusAdapter.macAudioSnapshot(
                recordingID: "v960-receive",
                hasLocalAudio: false,
                audioChecksum: nil,
                audioByteSize: 100,
                receiveStatus: "completed"
            )
        )

        #expect(metadataOnly.canDisplayAsComplete == false)
        #expect(metadataOnly.kind != .completed)
        #expect(receiveRecordOnly.canDisplayAsComplete == false)
        #expect(receiveRecordOnly.kind != .peerVerified)
    }

    @Test func macPartialReceiveDoesNotDisplayCompleted() {
        let display = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusToCanonicalEffectiveStatusAdapter.macAudioSnapshot(
                recordingID: "v960-partial",
                hasLocalAudio: false,
                audioChecksum: nil,
                audioByteSize: 100,
                receiveStatus: "receiving",
                transferVisible: true
            )
        )

        #expect(display.canDisplayAsComplete == false)
        #expect(display.kind == .uploading)
        #expect(display.effectiveStatus.blocker == .partialReceiveRejectedAsCompleted)
    }

    @Test func macLocalFileExistsWithoutChecksumDoesNotDisplayAudioAvailable() {
        let item = Self.item(id: "v911-local-only", hasAudio: true, audioChecksum: nil, fileSize: 100)

        #expect(item.displayAudioAvailable == false)
        #expect(item.canStartTranscription == false)
        #expect(MacAudioInboxRowAction.resolve(
            for: item,
            displaySyncState: nil,
            isTranscribing: false
        ).isEnabled == false)
    }

    @Test func macPeerInventoryHashSizeDisplaysAudioAvailable() {
        let display = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusToCanonicalEffectiveStatusAdapter.macAudioSnapshot(
                recordingID: "v960-proof",
                hasLocalAudio: true,
                audioChecksum: Self.hash,
                audioByteSize: 100,
                receiveStatus: "completed"
            )
        )

        #expect(display.canDisplayAsComplete)
        #expect(display.kind == .peerVerified)
        #expect(display.effectiveStatus.proof?.kind == .peerInventoryHashSizeMatch)
    }

    @Test func macInboxItemAudioStatusUsesCanonicalProof() {
        let missingProof = Self.item(id: "v960-missing-proof", hasAudio: true, audioChecksum: nil, fileSize: 100)
        let proven = Self.item(id: "v960-proven", hasAudio: true, audioChecksum: Self.hash, fileSize: 100)

        #expect(missingProof.displayAudioAvailable == false)
        #expect(missingProof.displayAudioStatusText == "缺失")
        #expect(proven.displayAudioAvailable)
        #expect(proven.displayAudioStatusText == "可用")
    }

    @Test func macExistingDifferentAudioDisplaysConflictNoOverwrite() {
        let display = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: CanonicalObjectID("recordingAudio:v911-conflict"),
                localAudioHash: CanonicalHash(Self.hash),
                localAudioByteSize: 100,
                conflict: true
            )
        )

        #expect(display.kind == .conflict)
        #expect(display.canDisplayAsComplete == false)
        #expect(display.effectiveStatus.blocker == .existingDifferentAudioConflict)
    }

    @Test func macInboxItemLegacySnapshotIsNotViewFinalSource() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let itemSource = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/MacRecordingInboxItem.swift"),
            encoding: .utf8
        )
        let inboxSource = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/MacAudioInboxView.swift"),
            encoding: .utf8
        )
        let studySource = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/MacStudyLibraryView.swift"),
            encoding: .utf8
        )

        #expect(itemSource.contains("let canonicalDisplaySyncState: CanonicalDisplaySyncState"))
        #expect(inboxSource.contains("item.canonicalDisplaySyncState") == false)
        #expect(studySource.contains("item.canonicalDisplaySyncState") == false)
    }

    @Test func macStudyLibraryAndInboxActionsReadCanonicalAudioAvailability() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let studySource = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/MacStudyLibraryView.swift"),
            encoding: .utf8
        )
        let inboxSource = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/MacAudioInboxView.swift"),
            encoding: .utf8
        )

        #expect(studySource.contains("canonicalDisplaySyncState(for:"))
        #expect(studySource.contains("studyLibraryStore.canonicalDisplaySyncState(for:"))
        #expect(studySource.contains("displaySyncState?.canDisplayAsComplete"))
        #expect(studySource.contains("?? item.canonicalDisplaySyncState") == false)
        #expect(inboxSource.contains("@ObservedObject var studyLibraryStore: StudyLibraryStore"))
        #expect(inboxSource.contains("studyLibraryStore.canonicalDisplaySyncState(for:"))
        #expect(inboxSource.contains("item.canonicalDisplaySyncState") == false)
        #expect(inboxSource.contains("displaySyncState?.canDisplayAsComplete"))
        #expect(studySource.contains("item.displayAudioAvailable") == false)
        #expect(inboxSource.contains("item.displayAudioAvailable") == false)
        #expect(studySource.contains("item.hasAudio && !isTranscribing") == false)
        #expect(inboxSource.contains("isEnabled: item.hasAudio") == false)
    }

    @Test func macReceiverStatusCardUsesEffectiveDisplayStateForFinalSyncText() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/MacReceiverStatusCard.swift"),
            encoding: .utf8
        )

        #expect(source.contains("secureReceiverService.studyLibraryStore"))
        #expect(source.contains("effectiveSyncStatusByObjectID"))
        #expect(source.contains("canonicalDisplaySyncState(for:"))
        #expect(source.contains("canDisplayAsComplete"))
        #expect(source.contains("receiveRecord") == false)
        #expect(source.contains("hasAudio") == false)
        #expect(source.contains("uploadLedger") == false)
    }

    @Test func macReceiverStatusCardSummaryOnlyCompletesFromProjectedProof() {
        let metadataOnly = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusToCanonicalEffectiveStatusAdapter.macAudioSnapshot(
                recordingID: "v913-metadata",
                hasLocalAudio: false,
                audioChecksum: nil,
                audioByteSize: 0,
                receiveStatus: nil
            )
        )
        let partialReceive = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusToCanonicalEffectiveStatusAdapter.macAudioSnapshot(
                recordingID: "v913-partial",
                hasLocalAudio: false,
                audioChecksum: nil,
                audioByteSize: 100,
                receiveStatus: "receiving",
                transferVisible: true
            )
        )
        let peerVerified = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusToCanonicalEffectiveStatusAdapter.macAudioSnapshot(
                recordingID: "v913-verified",
                hasLocalAudio: true,
                audioChecksum: Self.hash,
                audioByteSize: 100,
                receiveStatus: "completed"
            )
        )
        let conflict = LegacySyncStatusToCanonicalEffectiveStatusAdapter.displayState(
            for: LegacySyncStatusSnapshot(
                objectID: CanonicalObjectID("recordingAudio:v913-conflict"),
                localAudioHash: CanonicalHash(Self.hash),
                localAudioByteSize: 100,
                conflict: true
            )
        )

        #expect(MacReceiverStatusCard.effectiveLastSyncStatus(from: [metadataOnly]) == "暂无")
        #expect(MacReceiverStatusCard.effectiveLastSyncStatus(from: [partialReceive]) == "正在同步")
        #expect(MacReceiverStatusCard.effectiveLastSyncStatus(from: [peerVerified]) == "已同步")
        #expect(MacReceiverStatusCard.effectiveLastSyncStatus(from: [conflict]) == "暂无")
    }

    @Test func macStudyLibraryStoreExposesCachedEffectiveStatusSnapshot() async throws {
        let runtime = CanonicalStatusTruthRuntime()
        let store = StudyLibraryStore(
            rootURL: Self.temporaryRoot(),
            listenForInboxChanges: false,
            canonicalStatusTruthRuntime: runtime
        )
        _ = await store.produceCanonicalStatusFact(Self.finalizeProofFact())

        let before = await runtime.projectionMetricsSnapshot()
        let status = store.effectiveSyncStatus(for: CanonicalObjectID("recordingAudio:v911-mac"))
        let display = store.canonicalDisplaySyncState(for: CanonicalObjectID("recordingAudio:v911-mac"))
        let after = await runtime.projectionMetricsSnapshot()

        #expect(status?.phase == .completed)
        #expect(display?.kind == .completed)
        #expect(before == after)
    }

    private static func item(
        id: String,
        hasAudio: Bool,
        audioChecksum: String?,
        fileSize: Int64
    ) -> MacRecordingInboxItem {
        MacRecordingInboxItem(
            id: id,
            title: "v9.6",
            receivedAt: Date(timeIntervalSince1970: 9_600),
            duration: 1,
            fileSize: fileSize,
            sourceDeviceName: "iPhone",
            audioChecksum: audioChecksum,
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            receiveStatus: "completed",
            hasAudio: hasAudio,
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            transcriptionError: nil
        )
    }

    private static func finalizeProofFact() -> CanonicalStatusFact {
        let objectID = CanonicalObjectID("recordingAudio:v911-mac")
        let proof = CanonicalTransferFinalizeProof(
            sessionID: CanonicalTransferSessionID("v911-mac-session"),
            objectID: objectID,
            receiverNodeID: CanonicalNodeID("mac"),
            contentHash: CanonicalHash(hash),
            byteSize: 100,
            acceptedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 9_111)),
            verified: true
        )
        return CanonicalStatusFact(
            factID: "v911-mac-finalize",
            objectID: objectID,
            source: .transferFinalizeProof,
            producerNodeID: CanonicalNodeID("mac"),
            logicalTime: CanonicalLogicalTime(counter: 1, nodeID: CanonicalNodeID("mac")),
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
            .appendingPathComponent("RokuricsMac-v911-\(UUID().uuidString)", isDirectory: true)
    }
}
