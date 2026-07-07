//
//  CanonicalShadowDiagnosticsTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/1.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalShadowDiagnosticsTests {
    @Test func macShadowReportDoesNotMutateInventoryResponse() {
        let inventory = makeInventory()
        let response = LocalNetworkSyncInventoryResponse(ok: true, inventory: inventory, error: nil)
        let beforeHash = response.inventory?.inventoryHash
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            syncRunID: "sync-01",
            trigger: "sync-inventory",
            nodeID: "mac-01",
            nodeRole: .mac,
            generatedAt: Date(timeIntervalSince1970: 3_000),
            durationMs: 2,
            manifest: makeManifest(),
            legacy: legacySnapshot(from: inventory)
        )

        #expect(response.inventory?.inventoryHash == beforeHash)
        #expect(response.inventory?.recordings.count == 1)
        #expect(report.legacyRecordingCount == 1)
        #expect(report.canonicalObjectCount == 1)
    }

    @Test func studyItemOnlyWithoutReceiveRecordIsReported() {
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "mac-01",
            nodeRole: .mac,
            durationMs: 1,
            manifest: makeManifest(audioHash: nil, audioSize: nil, audioAvailability: .missing),
            legacy: CanonicalShadowLegacySnapshot(
                recordingCount: 0,
                studyItemCount: 1,
                artifactCount: 0,
                objects: [
                    CanonicalShadowLegacyObjectFact(
                        objectID: "canonical-recording-01",
                        legacyMetadataHash: "study-item-hash",
                        hasStudyItem: true
                    )
                ]
            )
        )

        #expect(report.comparison.contains(.studyItemOnlyWithoutReceiveRecord, objectID: "canonical-recording-01"))
    }

    @Test func receiveRecordOnlyWithoutStudyItemIsReported() {
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "mac-01",
            nodeRole: .mac,
            durationMs: 1,
            manifest: makeManifest(),
            legacy: CanonicalShadowLegacySnapshot(
                recordingCount: 1,
                studyItemCount: 0,
                artifactCount: 1,
                objects: [
                    CanonicalShadowLegacyObjectFact(
                        objectID: "canonical-recording-01",
                        legacyMetadataHash: "receive-hash",
                        audioHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                        audioByteSize: 42,
                        audioAvailability: "local",
                        hasReceiveRecord: true
                    )
                ]
            )
        )

        #expect(report.comparison.contains(.receiveRecordOnlyWithoutStudyItem, objectID: "canonical-recording-01"))
    }

    @Test func differentPeerAudioHashOrSizeIsReportedAsConflict() {
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "mac-01",
            nodeRole: .mac,
            durationMs: 1,
            manifest: makeManifest(audioHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", audioSize: 42),
            legacy: makeLegacySnapshot(audioHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", audioSize: 42),
            peerLegacy: makeLegacySnapshot(audioHash: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", audioSize: 42)
        )

        #expect(report.comparison.contains(.canonicalAudioConflict, objectID: "canonical-recording-01"))
        #expect(!report.comparison.contains(.canonicalAudioSameHashSameSize, objectID: "canonical-recording-01"))
    }

    @Test func macProcessingClockRejectionIsReported() {
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "mac-01",
            nodeRole: .mac,
            durationMs: 1,
            manifest: makeManifest(
                processingState: CanonicalProcessingState(transcription: .completed, note: .completed)
            ),
            legacy: makeLegacySnapshot()
        )

        #expect(report.comparison.contains(.canonicalMacUpdatedAtRejectedAsProcessingClock, objectID: "canonical-recording-01"))
    }

    private func makeManifest(
        createdAt: TimeInterval = 2_000,
        modifiedAt: TimeInterval = 2_000,
        audioHash: String? = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        audioSize: Int64? = 42,
        audioAvailability: CanonicalArtifact.Availability = .available,
        processingState: CanonicalProcessingState = .unknown
    ) -> CanonicalManifest {
        let metadata = CanonicalRecordingMetadata(
            objectID: "canonical-recording-01",
            title: "Canonical Lecture",
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: createdAt)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: modifiedAt)),
            duration: 42,
            filing: CanonicalRecordingMetadata.Filing(type: "课堂", subject: "数学"),
            tags: ["Important"]
        )
        let contentHash = audioHash.map { CanonicalHash($0) }
        let artifact = CanonicalArtifactFact.audio(
            availability: audioAvailability,
            contentHash: contentHash,
            byteSize: audioSize,
            logicalName: "audio.m4a"
        ).makeArtifact(objectID: metadata.objectID)
        let object = CanonicalRecordingObject(
            objectID: metadata.objectID,
            nodeID: "mac-01",
            metadata: metadata,
            artifacts: [artifact],
            processingState: processingState
        )
        return CanonicalManifest.make(
            node: CanonicalNode(nodeID: "mac-01", platform: "Mac"),
            generatedAt: Date(timeIntervalSince1970: 3_000),
            objects: [object]
        )
    }

    private func makeLegacySnapshot(
        audioHash: String? = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        audioSize: Int64? = 42
    ) -> CanonicalShadowLegacySnapshot {
        CanonicalShadowLegacySnapshot(
            recordingCount: 1,
            studyItemCount: 1,
            artifactCount: 1,
            objects: [
                CanonicalShadowLegacyObjectFact(
                    objectID: "canonical-recording-01",
                    legacyMetadataHash: "legacy-metadata",
                    audioHash: audioHash,
                    audioByteSize: audioSize,
                    audioAvailability: audioHash == nil ? "unknown" : "local",
                    hasReceiveRecord: true,
                    hasStudyItem: true
                )
            ]
        )
    }

    private func makeInventory() -> LocalNetworkSyncInventory {
        let device = LocalNetworkSyncDeviceSection(
            deviceID: "mac-01",
            deviceName: "Mac",
            platform: .Mac,
            generatedAt: Date(timeIntervalSince1970: 3_000),
            lastKnownPeerRevision: nil,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
        return LocalNetworkSyncInventory.make(
            device: device,
            recordings: [
                LocalNetworkSyncRecordingEntry(
                    recordingID: "canonical-recording-01",
                    metadataHash: "legacy-metadata",
                    audioAvailable: true,
                    audioChecksum: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    audioSize: 42,
                    uploadLedgerState: nil,
                    receiveStatus: "completed",
                    processingStatus: "notStarted",
                    updatedAt: Date(timeIntervalSince1970: 2_500),
                    deleted: false,
                    title: "Canonical Lecture",
                    createdAt: Date(timeIntervalSince1970: 2_500),
                    tombstone: false,
                    audioAvailability: .local,
                    uploadStatus: nil,
                    transcriptionStatus: "notStarted",
                    noteStatus: "notGenerated",
                    sourceDeviceID: "iphone-01",
                    artifactRefs: nil,
                    audioLogicalPathToken: "audio/inbox/canonical-recording-01/audio.m4a"
                )
            ],
            artifacts: [
                LocalNetworkSyncArtifactEntry(
                    artifactID: "audio:canonical-recording-01",
                    kind: .audio,
                    ownerID: "canonical-recording-01",
                    checksum: nil,
                    size: 42,
                    updatedAt: Date(timeIntervalSince1970: 2_500),
                    availability: .local,
                    logicalPathToken: "audio/inbox/canonical-recording-01/audio.m4a"
                )
            ]
        )
    }

    private func legacySnapshot(from inventory: LocalNetworkSyncInventory) -> CanonicalShadowLegacySnapshot {
        CanonicalShadowLegacySnapshot(
            recordingCount: inventory.recordings.count,
            studyItemCount: inventory.studyItems.count,
            artifactCount: inventory.artifacts.count,
            objects: inventory.recordings.map { recording in
                CanonicalShadowLegacyObjectFact(
                    objectID: recording.recordingID,
                    legacyMetadataHash: recording.metadataHash,
                    audioHash: recording.audioChecksum,
                    audioByteSize: recording.audioSize,
                    audioAvailability: recording.audioAvailability?.rawValue ?? "unknown",
                    hasReceiveRecord: true,
                    hasStudyItem: inventory.studyItems.contains { $0.recordingID == recording.recordingID }
                )
            }
        )
    }
}
