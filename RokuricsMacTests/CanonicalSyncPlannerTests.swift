//
//  CanonicalSyncPlannerTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/1.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalSyncPlannerTests {
    @Test func macInventoryDecodesWithoutCanonicalManifest() async throws {
        let inventory = makeInventory(canonicalManifest: nil)
        let data = try JSONEncoder().encode(inventory)
        let decoded = try JSONDecoder().decode(LocalNetworkSyncInventory.self, from: data)

        #expect(decoded.canonicalManifest == nil)
        #expect(decoded.recordings.count == 1)
    }

    @Test func macInventoryEncodesAndDecodesCanonicalManifest() async throws {
        let manifest = makeManifest(nodeID: "mac-01", platform: "Mac")
        let inventory = makeInventory(canonicalManifest: manifest)
        let data = try JSONEncoder().encode(inventory)
        let decoded = try JSONDecoder().decode(LocalNetworkSyncInventory.self, from: data)

        #expect(decoded.canonicalManifest?.object(withID: "recording-01") != nil)
        #expect(decoded.canonicalManifest?.hasValidManifestHash == true)
    }

    @Test func canonicalMetadataSameSuppressesLegacyRecordingMetadataChurn() throws {
        let plan = try CanonicalSyncPlanner().plan(
            local: makeManifest(),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac"),
            trigger: .periodic,
            legacyContext: CanonicalSyncPlannerLegacyContext(legacyUploadMetadataObjectIDs: ["recording-01"])
        )

        #expect(plan.uploadRecordingMetadata.isEmpty)
        #expect(plan.downloadRecordingMetadata.isEmpty)
        #expect(plan.noOpRecordingMetadata.first?.reason == .metadataHashEqual)
        #expect(plan.diagnostics.contains { $0.reason == .legacyWouldUploadMetadataButCanonicalNoOp })
        #expect(plan.diagnostics.contains { $0.reason == .canonicalMetadataHashConverged })
    }

    @Test func canonicalModifiedAtDrivesMetadataDirection() throws {
        let upload = try CanonicalSyncPlanner().plan(
            local: makeManifest(title: "Local", modifiedAt: 2_100),
            peer: makeManifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000),
            trigger: .periodic
        )
        let download = try CanonicalSyncPlanner().plan(
            local: makeManifest(title: "Local", modifiedAt: 2_000),
            peer: makeManifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_100),
            trigger: .periodic
        )
        let conflict = try CanonicalSyncPlanner().plan(
            local: makeManifest(title: "Local", modifiedAt: 2_000),
            peer: makeManifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000),
            trigger: .periodic
        )

        #expect(upload.uploadRecordingMetadata.first?.reason == .localMetadataNewer)
        #expect(download.downloadRecordingMetadata.first?.reason == .peerMetadataNewer)
        #expect(conflict.conflictRecordingMetadata.first?.reason == .metadataTieConflict)
        #expect(upload.diagnostics.contains { $0.reason == .canonicalBusinessModifiedAtUsed })
        #expect(download.diagnostics.contains { $0.reason == .canonicalBusinessModifiedAtUsed })
    }

    @Test func canonicalPlannerDiagnosticsExposeCreatedAtIgnoredForMetadataHash() throws {
        let plan = try CanonicalSyncPlanner().plan(
            local: makeManifest(createdAt: 1_000),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", createdAt: 9_000),
            trigger: .periodic
        )

        #expect(plan.noOpRecordingMetadata.first?.reason == .metadataHashEqual)
        #expect(plan.diagnostics.contains { $0.reason == .canonicalCreatedAtIgnoredForMetadataHash })
    }

    @Test func canonicalAudioSameHashSizeNoOpsAndDifferentAudioConflicts() throws {
        let noOp = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioHash: "aaaaaaaa", audioSize: 42),
            trigger: .periodic
        )
        let conflict = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioHash: "bbbbbbbb", audioSize: 42),
            trigger: .periodic
        )

        #expect(noOp.noOpAudioArtifact.first?.reason == .peerAudioSameHashSameSize)
        #expect(noOp.uploadAudioArtifact.isEmpty)
        #expect(conflict.conflictAudioArtifact.first?.reason == .peerAudioHashConflict)
        #expect(conflict.uploadAudioArtifact.isEmpty)
    }

    @Test func canonicalAudioBootstrapReasonsAreDistinct() throws {
        let absent = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", objects: []),
            trigger: .periodic
        )
        let studyOnly = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioAvailability: nil),
            trigger: .periodic,
            legacyContext: CanonicalSyncPlannerLegacyContext(
                peerObjectFacts: [
                    CanonicalShadowLegacyObjectFact(objectID: "recording-01", legacyMetadataHash: "study", hasStudyItem: true)
                ]
            )
        )
        let metadataOnly = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioAvailability: nil),
            trigger: .periodic,
            legacyContext: CanonicalSyncPlannerLegacyContext(
                peerObjectFacts: [
                    CanonicalShadowLegacyObjectFact(objectID: "recording-01", legacyMetadataHash: "receive", hasReceiveRecord: true)
                ]
            )
        )

        #expect(absent.uploadAudioArtifact.first?.reason == .peerObjectAbsent)
        #expect(studyOnly.uploadAudioArtifact.first?.reason == .peerStudyItemOnlyWithoutReceiveRecord)
        #expect(metadataOnly.uploadAudioArtifact.first?.reason == .peerAudioMetadataOnly)
    }

    @Test func peerUnknownViewRefreshAndRetryDrainerDoNotUpload() throws {
        let unknown = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioHash: nil, audioSize: 42, audioAvailability: .availableWithoutHash),
            trigger: .periodic
        )
        let viewRefresh = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", objects: []),
            trigger: .viewRefresh
        )
        let retryDrainer = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", objects: []),
            trigger: .retryDrainer
        )

        #expect(unknown.deferAudioArtifact.first?.reason == .peerAudioUnknownDeferred)
        #expect(viewRefresh.uploadAudioArtifact.isEmpty)
        #expect(viewRefresh.deferAudioArtifact.first?.reason == .viewRefreshSuppressed)
        #expect(retryDrainer.uploadAudioArtifact.isEmpty)
        #expect(retryDrainer.deferAudioArtifact.first?.reason == .retryDrainerSuppressedNewJob)
    }

    @Test func generatedArtifactDownloadsFromAuthoritativeMacPeerAndNoOpsWhenSame() throws {
        let transcript = generatedArtifact(
            kind: .transcriptJSON,
            hash: "cccccccc",
            size: 180,
            modifiedAt: 4_000,
            nodeID: "mac-01",
            platform: "Mac",
            logicalPathToken: "transcripts/recording-01/transcript.json"
        )
        let peer = manifestByAddingGeneratedArtifact(
            transcript,
            to: makeManifest(
                nodeID: "mac-01",
                platform: "Mac",
                capabilities: [.recordingMetadata, .audioArtifact, .receiveRecord, .transcriptArtifact, .objectProjection]
            )
        )
        let download = try CanonicalSyncPlanner().plan(
            local: makeManifest(),
            peer: peer,
            trigger: .periodic
        )
        let noOp = try CanonicalSyncPlanner().plan(
            local: manifestByAddingGeneratedArtifact(
                generatedArtifact(
                    kind: .transcriptJSON,
                    hash: "cccccccc",
                    size: 180,
                    modifiedAt: 3_000,
                    nodeID: nil,
                    platform: "iPhone",
                    logicalPathToken: "transcripts/recording-01/transcript.json"
                ),
                to: makeManifest()
            ),
            peer: peer,
            trigger: .periodic
        )

        #expect(download.downloadGeneratedArtifact.first?.reason == .canonicalGeneratedArtifactDownload)
        #expect(download.downloadGeneratedArtifact.first?.kind == .transcriptJSON)
        #expect(noOp.noOpGeneratedArtifact.first?.reason == .canonicalGeneratedArtifactPeerSameNoOp)
    }

    @Test func incompatibleCanonicalPayloadThrowsForFallback() throws {
        var peer = makeManifest(nodeID: "mac-01", platform: "Mac")
        peer.schemaVersion = 999

        do {
            _ = try CanonicalSyncPlanner().plan(local: makeManifest(), peer: peer, trigger: .periodic)
            Issue.record("Expected incompatible schema to throw")
        } catch let error as CanonicalSyncPlanError {
            #expect(error == .incompatibleSchema(local: 1, peer: 999))
        }
    }

    @Test func invalidHashAndMissingCapabilityThrowForLegacyFallback() throws {
        var invalidPeer = makeManifest(nodeID: "mac-01", platform: "Mac")
        invalidPeer.manifestHash = CanonicalHash("not-the-manifest-hash")

        do {
            _ = try CanonicalSyncPlanner().plan(local: makeManifest(), peer: invalidPeer, trigger: .periodic)
            Issue.record("Expected invalid manifest hash to throw")
        } catch let error as CanonicalSyncPlanError {
            #expect(error == .invalidManifestHash(side: "peer"))
        }

        let missingAudioCapability = makeManifest(
            nodeID: "mac-01",
            platform: "Mac",
            capabilities: [.recordingMetadata, .receiveRecord, .objectProjection]
        )
        do {
            _ = try CanonicalSyncPlanner().plan(local: makeManifest(), peer: missingAudioCapability, trigger: .periodic)
            Issue.record("Expected missing audio capability to throw")
        } catch let error as CanonicalSyncPlanError {
            #expect(error == .missingCapability(side: "peer", capability: .audioArtifact))
        }
    }

    private func makeManifest(
        title: String = "Lecture",
        nodeID: String = "iphone-01",
        platform: String = "iPhone",
        createdAt: TimeInterval = 1_000,
        modifiedAt: TimeInterval = 2_000,
        audioHash: String? = "aaaaaaaa",
        audioSize: Int64? = 42,
        audioAvailability: CanonicalArtifact.Availability? = .available,
        capabilities: [CanonicalCapability] = [.recordingMetadata, .audioArtifact, .receiveRecord, .objectProjection],
        objects explicitObjects: [CanonicalRecordingObject]? = nil
    ) -> CanonicalManifest {
        let metadata = CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: title,
            createdAt: CanonicalTimestamp(Date(timeIntervalSince1970: createdAt)),
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: modifiedAt)),
            duration: 42,
            filing: CanonicalRecordingMetadata.Filing(type: "course", subject: "math"),
            tags: []
        )
        let artifacts = audioAvailability.map { availability -> [CanonicalArtifact] in
            [
                CanonicalArtifactFact.audio(
                    availability: availability,
                    contentHash: audioHash.map { CanonicalHash($0) },
                    byteSize: audioSize,
                    logicalName: "audio.m4a"
                ).makeArtifact(objectID: metadata.objectID)
            ]
        } ?? []
        let object = CanonicalRecordingObject(
            objectID: metadata.objectID,
            nodeID: nodeID,
            metadata: metadata,
            artifacts: artifacts
        )
        return CanonicalManifest.make(
            node: CanonicalNode(
                nodeID: nodeID,
                platform: platform,
                capabilities: capabilities
            ),
            generatedAt: Date(timeIntervalSince1970: 3_000),
            objects: explicitObjects ?? [object]
        )
    }

    private func makeInventory(canonicalManifest: CanonicalManifest?) -> LocalNetworkSyncInventory {
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
                    recordingID: "recording-01",
                    metadataHash: "legacy",
                    audioAvailable: true,
                    audioChecksum: "aaaaaaaa",
                    audioSize: 42,
                    uploadLedgerState: nil,
                    receiveStatus: "completed",
                    processingStatus: "notStarted",
                    updatedAt: Date(timeIntervalSince1970: 2_000),
                    deleted: false
                )
            ],
            canonicalManifest: canonicalManifest
        )
    }

    private func generatedArtifact(
        kind: CanonicalArtifact.Kind,
        hash: String,
        size: Int64,
        modifiedAt: TimeInterval,
        nodeID: String?,
        platform: String,
        logicalPathToken: String
    ) -> CanonicalArtifact {
        CanonicalProjectionContract.makeArtifact(
            objectID: "recording-01",
            kind: kind,
            availability: .available,
            contentHash: CanonicalHash(hash),
            byteSize: size,
            logicalPathToken: logicalPathToken,
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: modifiedAt)),
            producedByNodeID: nodeID,
            platform: platform
        )
    }

    private func manifestByAddingGeneratedArtifact(
        _ artifact: CanonicalArtifact,
        to manifest: CanonicalManifest
    ) -> CanonicalManifest {
        guard let object = manifest.objects.first else {
            return manifest
        }
        return CanonicalManifest.make(
            node: manifest.node,
            generatedAt: manifest.generatedAt.date,
            objects: [object.replacingArtifacts(object.artifacts + [artifact])]
        )
    }
}
