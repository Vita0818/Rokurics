//
//  CanonicalSyncPlannerTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/1.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalSyncPlannerTests {
    @Test func inventoryDecodesWithoutCanonicalManifest() throws {
        let inventory = makeInventory(canonicalManifest: nil)
        let data = try JSONEncoder().encode(inventory)
        let decoded = try JSONDecoder().decode(LocalNetworkSyncInventory.self, from: data)

        #expect(decoded.canonicalManifest == nil)
        #expect(decoded.recordings.count == 1)
    }

    @Test func inventoryEncodesAndDecodesCanonicalManifest() throws {
        let manifest = makeManifest()
        let inventory = makeInventory(canonicalManifest: manifest)
        let data = try JSONEncoder().encode(inventory)
        let decoded = try JSONDecoder().decode(LocalNetworkSyncInventory.self, from: data)

        #expect(decoded.canonicalManifest?.object(withID: "recording-01") != nil)
        #expect(decoded.canonicalManifest?.hasValidManifestHash == true)
    }

    @Test func canonicalMetadataHashSameMakesLegacyMetadataMismatchNoOp() throws {
        let manifest = makeManifest()
        let plan = try CanonicalSyncPlanner().plan(
            local: manifest,
            peer: makeManifest(nodeID: "mac-01", platform: "Mac"),
            trigger: .periodic,
            legacyContext: CanonicalSyncPlannerLegacyContext(legacyUploadMetadataObjectIDs: ["recording-01"])
        )

        #expect(plan.uploadRecordingMetadata.isEmpty)
        #expect(plan.downloadRecordingMetadata.isEmpty)
        #expect(plan.noOpRecordingMetadata.contains { $0.reason == .metadataHashEqual })
        #expect(plan.diagnostics.contains { $0.reason == .legacyWouldUploadMetadataButCanonicalNoOp })
        #expect(plan.diagnostics.contains { $0.reason == .canonicalMetadataHashConverged })
    }

    @Test func canonicalMetadataUsesModifiedAtForUploadDownloadAndTieConflict() throws {
        let localNewer = try CanonicalSyncPlanner().plan(
            local: makeManifest(title: "Local", modifiedAt: 2_100),
            peer: makeManifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000),
            trigger: .periodic
        )
        let peerNewer = try CanonicalSyncPlanner().plan(
            local: makeManifest(title: "Local", modifiedAt: 2_000),
            peer: makeManifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_100),
            trigger: .periodic
        )
        let tie = try CanonicalSyncPlanner().plan(
            local: makeManifest(title: "Local", modifiedAt: 2_000),
            peer: makeManifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000),
            trigger: .periodic
        )

        #expect(localNewer.uploadRecordingMetadata.first?.reason == .localMetadataNewer)
        #expect(peerNewer.downloadRecordingMetadata.first?.reason == .peerMetadataNewer)
        #expect(tie.conflictRecordingMetadata.first?.reason == .metadataTieConflict)
        #expect(localNewer.diagnostics.contains { $0.reason == .canonicalBusinessModifiedAtUsed })
        #expect(peerNewer.diagnostics.contains { $0.reason == .canonicalBusinessModifiedAtUsed })
    }

    @Test func plannerDiagnosticsExposeCreatedAtIgnoredForMetadataHash() throws {
        let plan = try CanonicalSyncPlanner().plan(
            local: makeManifest(createdAt: 1_000),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", createdAt: 9_000),
            trigger: .periodic
        )

        #expect(plan.noOpRecordingMetadata.first?.reason == .metadataHashEqual)
        #expect(plan.diagnostics.contains { $0.reason == .canonicalCreatedAtIgnoredForMetadataHash })
    }

    @Test func canonicalAudioSameHashAndSizeNoOps() throws {
        let plan = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioHash: "aaaaaaaa", audioSize: 42),
            trigger: .periodic
        )

        #expect(plan.uploadAudioArtifact.isEmpty)
        #expect(plan.noOpAudioArtifact.first?.reason == .peerAudioSameHashSameSize)
    }

    @Test func canonicalAudioBootstrapsWhenPeerObjectAbsent() throws {
        let plan = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", objects: []),
            trigger: .periodic
        )

        #expect(plan.uploadAudioArtifact.first?.reason == .peerObjectAbsent)
    }

    @Test func canonicalAudioBootstrapsStudyItemOnlyWithoutReceiveRecord() throws {
        let plan = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioAvailability: nil),
            trigger: .periodic,
            legacyContext: CanonicalSyncPlannerLegacyContext(
                peerObjectFacts: [
                    CanonicalShadowLegacyObjectFact(
                        objectID: "recording-01",
                        legacyMetadataHash: "study",
                        hasStudyItem: true
                    )
                ]
            )
        )

        #expect(plan.uploadAudioArtifact.first?.reason == .peerStudyItemOnlyWithoutReceiveRecord)
    }

    @Test func canonicalAudioBootstrapsMetadataOnlyOrMissing() throws {
        let metadataOnly = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioAvailability: nil),
            trigger: .periodic,
            legacyContext: CanonicalSyncPlannerLegacyContext(
                peerObjectFacts: [
                    CanonicalShadowLegacyObjectFact(
                        objectID: "recording-01",
                        legacyMetadataHash: "receive",
                        hasReceiveRecord: true
                    )
                ]
            )
        )
        let missing = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioHash: nil, audioSize: nil, audioAvailability: .missing),
            trigger: .periodic
        )

        #expect(metadataOnly.uploadAudioArtifact.first?.reason == .peerAudioMetadataOnly)
        #expect(missing.uploadAudioArtifact.first?.reason == .peerAudioMissing)
    }

    @Test func peerAudioUnknownDefersAndConflictDoesNotUpload() throws {
        let unknown = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioHash: nil, audioSize: 42, audioAvailability: .availableWithoutHash),
            trigger: .periodic
        )
        let conflict = try CanonicalSyncPlanner().plan(
            local: makeManifest(audioHash: "aaaaaaaa", audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioHash: "bbbbbbbb", audioSize: 42),
            trigger: .periodic
        )

        #expect(unknown.uploadAudioArtifact.isEmpty)
        #expect(unknown.deferAudioArtifact.first?.reason == .peerAudioUnknownDeferred)
        #expect(conflict.uploadAudioArtifact.isEmpty)
        #expect(conflict.conflictAudioArtifact.first?.reason == .peerAudioHashConflict)
    }

    @Test func viewRefreshAndRetryDrainerDoNotCreateFreshCanonicalAudioUpload() throws {
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

        #expect(viewRefresh.uploadAudioArtifact.isEmpty)
        #expect(viewRefresh.deferAudioArtifact.first?.reason == .viewRefreshSuppressed)
        #expect(retryDrainer.uploadAudioArtifact.isEmpty)
        #expect(retryDrainer.deferAudioArtifact.first?.reason == .retryDrainerSuppressedNewJob)
    }

    @Test func generatedArtifactMissingLocalDownloadsFromAuthoritativePeer() throws {
        let peer = manifestByAddingGeneratedArtifact(
            generatedArtifact(
                kind: .transcriptMarkdown,
                hash: "cccccccc",
                size: 120,
                modifiedAt: 4_000,
                nodeID: "mac-01",
                platform: "Mac",
                logicalPathToken: "transcripts/recording-01/transcript.md"
            ),
            to: makeManifest(
                nodeID: "mac-01",
                platform: "Mac",
                capabilities: [.recordingMetadata, .audioArtifact, .transcriptArtifact, .objectProjection]
            )
        )
        let plan = try CanonicalSyncPlanner().plan(
            local: makeManifest(),
            peer: peer,
            trigger: .periodic
        )

        #expect(plan.downloadGeneratedArtifact.first?.reason == .canonicalGeneratedArtifactDownload)
        #expect(plan.downloadGeneratedArtifact.first?.kind == .transcriptMarkdown)
        #expect(plan.downloadGeneratedArtifact.first?.logicalPathToken == "transcripts/recording-01/transcript.md")
    }

    @Test func generatedArtifactSameHashNoOpsAndRecordsLegacyDownloadSuppression() throws {
        let localArtifact = generatedArtifact(
            kind: .transcriptMarkdown,
            hash: "cccccccc",
            size: 120,
            modifiedAt: 3_000,
            nodeID: nil,
            platform: "iPhone",
            logicalPathToken: "transcripts/recording-01/transcript.md"
        )
        let peerArtifact = generatedArtifact(
            kind: .transcriptMarkdown,
            hash: "cccccccc",
            size: 120,
            modifiedAt: 4_000,
            nodeID: "mac-01",
            platform: "Mac",
            logicalPathToken: "transcripts/recording-01/transcript.md"
        )
        let plan = try CanonicalSyncPlanner().plan(
            local: manifestByAddingGeneratedArtifact(localArtifact, to: makeManifest()),
            peer: manifestByAddingGeneratedArtifact(
                peerArtifact,
                to: makeManifest(
                    nodeID: "mac-01",
                    platform: "Mac",
                    capabilities: [.recordingMetadata, .audioArtifact, .transcriptArtifact, .objectProjection]
                )
            ),
            trigger: .periodic,
            legacyContext: CanonicalSyncPlannerLegacyContext(
                legacyDownloadGeneratedArtifactKeys: [
                    CanonicalProjectionContract.artifactKey(objectID: "recording-01", kind: .transcriptMarkdown)
                ]
            )
        )

        #expect(plan.downloadGeneratedArtifact.isEmpty)
        #expect(plan.noOpGeneratedArtifact.first?.reason == .canonicalGeneratedArtifactPeerSameNoOp)
        #expect(plan.diagnostics.contains { $0.reason == .legacyWouldDownloadArtifactButCanonicalNoOp })
    }

    @Test func generatedArtifactAuthoritativePeerNewerDownloadsAndPeerUnknownDefers() throws {
        let localArtifact = generatedArtifact(
            kind: .noteMarkdown,
            hash: "dddddddd",
            size: 200,
            modifiedAt: 3_000,
            nodeID: nil,
            platform: "iPhone",
            logicalPathToken: "notes/recording-01/note.md"
        )
        let peerNewer = generatedArtifact(
            kind: .noteMarkdown,
            hash: "eeeeeeee",
            size: 210,
            modifiedAt: 4_000,
            nodeID: "mac-01",
            platform: "Mac",
            logicalPathToken: "notes/recording-01/note.md"
        )
        let peerUnknown = CanonicalProjectionContract.makeArtifact(
            objectID: "recording-01",
            kind: .summaryJSON,
            availability: .availableWithoutHash,
            byteSize: 42,
            logicalPathToken: "notes/recording-01/summary.json",
            modifiedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 4_000)),
            producedByNodeID: "mac-01",
            platform: "Mac"
        )
        let peerBase = makeManifest(
            nodeID: "mac-01",
            platform: "Mac",
            capabilities: [.recordingMetadata, .audioArtifact, .noteArtifact, .summaryArtifact, .objectProjection]
        )
        let download = try CanonicalSyncPlanner().plan(
            local: manifestByAddingGeneratedArtifact(localArtifact, to: makeManifest()),
            peer: manifestByAddingGeneratedArtifact(peerNewer, to: peerBase),
            trigger: .periodic
        )
        let deferred = try CanonicalSyncPlanner().plan(
            local: makeManifest(),
            peer: manifestByAddingGeneratedArtifact(peerUnknown, to: peerBase),
            trigger: .periodic
        )

        #expect(download.downloadGeneratedArtifact.first?.reason == .canonicalGeneratedArtifactAuthoritativePeerNewer)
        #expect(deferred.downloadGeneratedArtifact.isEmpty)
        #expect(deferred.deferGeneratedArtifact.first?.reason == .canonicalGeneratedArtifactPeerUnknownDeferred)
    }

    @Test func viewRefreshDoesNotCreateGeneratedArtifactDownload() throws {
        let peer = manifestByAddingGeneratedArtifact(
            generatedArtifact(
                kind: .transcriptJSON,
                hash: "ffffffff",
                size: 240,
                modifiedAt: 4_000,
                nodeID: "mac-01",
                platform: "Mac",
                logicalPathToken: "transcripts/recording-01/transcript.json"
            ),
            to: makeManifest(
                nodeID: "mac-01",
                platform: "Mac",
                capabilities: [.recordingMetadata, .audioArtifact, .transcriptArtifact, .objectProjection]
            )
        )
        let plan = try CanonicalSyncPlanner().plan(
            local: makeManifest(),
            peer: peer,
            trigger: .viewRefresh
        )

        #expect(plan.downloadGeneratedArtifact.isEmpty)
        #expect(plan.deferGeneratedArtifact.first?.reason == .viewRefreshSuppressed)
    }

    @Test func plannerRejectsIncompatibleCanonicalPayloadForLegacyFallback() throws {
        var peer = makeManifest(nodeID: "mac-01", platform: "Mac")
        peer.schemaVersion = 999

        do {
            _ = try CanonicalSyncPlanner().plan(local: makeManifest(), peer: peer, trigger: .periodic)
            Issue.record("Expected incompatible schema to throw")
        } catch let error as CanonicalSyncPlanError {
            #expect(error == .incompatibleSchema(local: 1, peer: 999))
        }
    }

    @Test func plannerRejectsInvalidHashAndMissingCapabilityForLegacyFallback() throws {
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
            capabilities: [.recordingMetadata, .objectProjection]
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
        capabilities: [CanonicalCapability] = [.recordingMetadata, .audioArtifact, .objectProjection],
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
                    recordingID: "recording-01",
                    metadataHash: "legacy",
                    audioAvailable: true,
                    audioChecksum: "aaaaaaaa",
                    audioSize: 42,
                    uploadLedgerState: nil,
                    receiveStatus: nil,
                    processingStatus: nil,
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
