//
//  CanonicalShadowDiagnosticsTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/1.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalShadowDiagnosticsTests {
    @Test func iphoneShadowReportDoesNotMutateLegacyInventoryInput() {
        let inventory = makeInventory()
        let beforeHash = inventory.inventoryHash
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            syncRunID: "sync-01",
            trigger: "manual",
            nodeID: "iphone-01",
            nodeRole: .iphone,
            generatedAt: Date(timeIntervalSince1970: 3_000),
            durationMs: 2,
            manifest: makeManifest(),
            legacy: legacySnapshot(from: inventory)
        )

        #expect(inventory.inventoryHash == beforeHash)
        #expect(inventory.recordings.count == 1)
        #expect(report.legacyRecordingCount == 1)
        #expect(report.canonicalObjectCount == 1)
    }

    @Test func sameCanonicalMetadataReportsConverged() {
        let localManifest = makeManifest(title: "Canonical Lecture")
        let peerManifest = makeManifest(title: "Canonical Lecture", nodeID: "mac-01", platform: "Mac")
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "iphone-01",
            nodeRole: .iphone,
            durationMs: 1,
            manifest: localManifest,
            legacy: makeLegacySnapshot(metadataHash: "11111111111111111111"),
            peerManifest: peerManifest,
            peerLegacy: makeLegacySnapshot(metadataHash: "11111111111111111111")
        )

        #expect(report.comparison.metadataHashConvergedObjectIDs.contains("canonical-recording-01"))
        #expect(report.comparison.contains(.canonicalMetadataHashConverged, objectID: "canonical-recording-01"))
        #expect(!report.comparison.contains(.canonicalMetadataHashMismatch, objectID: "canonical-recording-01"))
    }

    @Test func createdAtAndProcessingStateAreReportedAsIgnoredForMetadataHash() {
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "iphone-01",
            nodeRole: .iphone,
            durationMs: 1,
            manifest: makeManifest(
                createdAt: 2_000,
                processingState: CanonicalProcessingState(transcription: .notStarted, note: .notStarted)
            ),
            legacy: makeLegacySnapshot(),
            peerManifest: makeManifest(
                nodeID: "mac-01",
                platform: "Mac",
                createdAt: 9_000,
                processingState: CanonicalProcessingState(transcription: .completed, note: .completed)
            ),
            peerLegacy: makeLegacySnapshot()
        )

        #expect(report.comparison.contains(.canonicalCreatedAtIgnoredForMetadataHash, objectID: "canonical-recording-01"))
        #expect(report.comparison.contains(.canonicalModifiedAtIgnoredProcessingState, objectID: "canonical-recording-01"))
    }

    @Test func legacyHashMismatchButCanonicalHashSameIsReported() {
        let localManifest = makeManifest(title: "Canonical Lecture")
        let peerManifest = makeManifest(title: "Canonical Lecture", nodeID: "mac-01", platform: "Mac")
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "iphone-01",
            nodeRole: .iphone,
            durationMs: 1,
            manifest: localManifest,
            legacy: makeLegacySnapshot(metadataHash: "11111111111111111111"),
            peerManifest: peerManifest,
            peerLegacy: makeLegacySnapshot(metadataHash: "22222222222222222222")
        )

        #expect(report.comparison.contains(.legacyMetadataHashMismatchButCanonicalHashMatch, objectID: "canonical-recording-01"))
    }

    @Test func sameAudioHashAndSizeIsReportedAsCanonicalSameAudio() {
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "iphone-01",
            nodeRole: .iphone,
            durationMs: 1,
            manifest: makeManifest(audioHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", audioSize: 42),
            legacy: makeLegacySnapshot(audioHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", audioSize: 42),
            peerLegacy: makeLegacySnapshot(audioHash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", audioSize: 42)
        )

        #expect(report.comparison.contains(.canonicalAudioSameHashSameSize, objectID: "canonical-recording-01"))
        #expect(!report.comparison.contains(.canonicalAudioConflict, objectID: "canonical-recording-01"))
    }

    @Test func unknownAudioHashOrSizeDoesNotReportProvenNoOp() {
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "iphone-01",
            nodeRole: .iphone,
            durationMs: 1,
            manifest: makeManifest(audioHash: nil, audioSize: 42, audioAvailability: .availableWithoutHash),
            legacy: makeLegacySnapshot(audioHash: nil, audioSize: 42),
            peerLegacy: makeLegacySnapshot(audioHash: nil, audioSize: 42)
        )

        #expect(report.comparison.contains(.canonicalAudioUnknown, objectID: "canonical-recording-01"))
        #expect(!report.comparison.contains(.canonicalAudioSameHashSameSize, objectID: "canonical-recording-01"))
    }

    @Test func jsonEncodingUsesHashPrefixesAndLogicalNamesOnly() throws {
        let fullHash = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "iphone-01",
            nodeRole: .iphone,
            durationMs: 1,
            manifest: makeManifest(audioHash: fullHash, audioSize: 42, logicalName: "private/path/audio.m4a"),
            legacy: makeLegacySnapshot(audioHash: fullHash, audioSize: 42)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(report), encoding: .utf8) ?? ""

        #expect(!json.contains(fullHash))
        #expect(json.contains("aaaaaaaaaaaa"))
        #expect(!json.contains("private/path/audio.m4a"))
        #expect(json.contains("audio.m4a"))
    }

    @Test func generatedArtifactShadowUsesCategoriesAndRedactedHashPrefix() throws {
        let fullHash = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
        let localManifest = makeManifest(
            generatedArtifact: generatedArtifact(
                hash: fullHash,
                logicalPathToken: "transcripts/canonical-recording-01/transcript.md",
                platform: "iPhone",
                nodeID: nil
            )
        )
        let peerManifest = makeManifest(
            nodeID: "mac-01",
            platform: "Mac",
            generatedArtifact: generatedArtifact(
                hash: fullHash,
                logicalPathToken: "transcripts/canonical-recording-01/transcript.md",
                platform: "Mac",
                nodeID: "mac-01"
            )
        )
        let report = CanonicalShadowReportBuilder().build(
            runID: "run-01",
            nodeID: "iphone-01",
            nodeRole: .iphone,
            durationMs: 1,
            manifest: localManifest,
            legacy: makeLegacySnapshot(),
            peerManifest: peerManifest,
            peerLegacy: makeLegacySnapshot()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(data: try encoder.encode(report), encoding: .utf8) ?? ""

        #expect(report.comparison.contains(.canonicalGeneratedArtifactPeerSameNoOp, objectID: "canonical-recording-01"))
        #expect(!json.contains(fullHash))
        #expect(json.contains("cccccccccccc"))
        #expect(!json.contains("transcripts/canonical-recording-01/transcript.md"))
        #expect(json.contains("transcript.md"))
    }


    private func makeManifest(
        title: String = "Canonical Lecture",
        nodeID: String = "iphone-01",
        platform: String = "iPhone",
        createdAt: TimeInterval = 2_000,
        modifiedAt: TimeInterval = 2_000,
        audioHash: String? = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        audioSize: Int64? = 42,
        audioAvailability: CanonicalArtifact.Availability = .available,
        logicalName: String = "audio.m4a",
        processingState: CanonicalProcessingState = .unknown,
        generatedArtifact: CanonicalArtifact? = nil
    ) -> CanonicalManifest {
        let metadata = CanonicalRecordingMetadata(
            objectID: "canonical-recording-01",
            title: title,
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
            logicalName: logicalName
        ).makeArtifact(objectID: metadata.objectID)
        let object = CanonicalRecordingObject(
            objectID: metadata.objectID,
            nodeID: nodeID,
            metadata: metadata,
            artifacts: [artifact] + [generatedArtifact].compactMap { $0 },
            processingState: processingState
        )
        return CanonicalManifest.make(
            node: CanonicalNode(nodeID: nodeID, platform: platform),
            generatedAt: Date(timeIntervalSince1970: 3_000),
            objects: [object]
        )
    }

    private func generatedArtifact(
        hash: String,
        logicalPathToken: String,
        platform: String,
        nodeID: String?
    ) -> CanonicalArtifact {
        CanonicalProjectionContract.makeArtifact(
            objectID: "canonical-recording-01",
            kind: .transcriptMarkdown,
            availability: .available,
            contentHash: CanonicalHash(hash),
            byteSize: 120,
            logicalPathToken: logicalPathToken,
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 4_000)),
            producedByNodeID: nodeID,
            platform: platform
        )
    }

    private func makeLegacySnapshot(
        metadataHash: String = "legacy-metadata",
        audioHash: String? = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        audioSize: Int64? = 42
    ) -> CanonicalShadowLegacySnapshot {
        CanonicalShadowLegacySnapshot(
            recordingCount: 1,
            studyItemCount: 0,
            artifactCount: audioHash == nil && audioSize == nil ? 0 : 1,
            objects: [
                CanonicalShadowLegacyObjectFact(
                    objectID: "canonical-recording-01",
                    legacyMetadataHash: metadataHash,
                    audioHash: audioHash,
                    audioByteSize: audioSize,
                    audioAvailability: audioHash == nil ? "unknown" : "local",
                    hasRecordingMetadata: true
                )
            ]
        )
    }

    private func makeInventory() -> LocalNetworkSyncInventory {
        let device = LocalNetworkSyncDeviceSection(
            deviceID: "iphone-01",
            deviceName: "iPhone",
            platform: .iPhone,
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
                    receiveStatus: nil,
                    processingStatus: nil,
                    updatedAt: Date(timeIntervalSince1970: 2_000),
                    deleted: false,
                    title: "Canonical Lecture",
                    createdAt: Date(timeIntervalSince1970: 2_000),
                    tombstone: false,
                    audioAvailability: .local,
                    uploadStatus: "localOnly",
                    transcriptionStatus: "notStarted",
                    noteStatus: "notGenerated",
                    sourceDeviceID: "iphone-01",
                    artifactRefs: nil,
                    audioLogicalPathToken: "Recordings/canonical-recording-01.m4a"
                )
            ],
            artifacts: [
                LocalNetworkSyncArtifactEntry(
                    artifactID: "audio:canonical-recording-01",
                    kind: .audio,
                    ownerID: "canonical-recording-01",
                    checksum: nil,
                    size: 42,
                    updatedAt: Date(timeIntervalSince1970: 2_000),
                    availability: .local,
                    logicalPathToken: "Recordings/canonical-recording-01.m4a"
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
                    hasRecordingMetadata: true,
                    hasStudyItem: inventory.studyItems.contains { $0.recordingID == recording.recordingID }
                )
            }
        )
    }
}
