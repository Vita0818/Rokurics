//
//  CanonicalApplyPlanTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalApplyPlanTests {
    @Test func metadataDirectionsBecomeApplyAndSendActions() throws {
        let send = try applyPlan(
            local: makeManifest(title: "Local", modifiedAt: 2_100),
            peer: makeManifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000)
        )
        let apply = try applyPlan(
            local: makeManifest(title: "Local", modifiedAt: 2_000),
            peer: makeManifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_100)
        )
        let same = try applyPlan(
            local: makeManifest(),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac")
        )

        #expect(send.actions.first { $0.kind == .recordingMetadataSend }?.bridgeHint == .legacyMetadataManifestSend)
        #expect(apply.actions.first { $0.kind == .recordingMetadataApply }?.bridgeHint == .legacyMetadataManifestApply)
        #expect(same.actions.filter { $0.kind == .recordingMetadataApply || $0.kind == .recordingMetadataSend }.isEmpty)
    }

    @Test func metadataTieConflictRecordsRedactedConflictOnly() throws {
        let plan = try applyPlan(
            local: makeManifest(title: "Local", modifiedAt: 2_000),
            peer: makeManifest(title: "Peer", nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000)
        )
        let conflict = try #require(plan.conflicts.first)

        #expect(conflict.kind == .recordingMetadataConcurrentEdit)
        #expect(plan.actions.contains { $0.kind == .conflictRecord && $0.conflictID == conflict.conflictID })
        #expect(conflict.localHashPrefix?.count == 12)
        #expect(conflict.peerHashPrefix?.count == 12)
    }

    @Test func objectTombstoneNewerAppliesOrSendsWithoutPhysicalDelete() throws {
        let peerTombstone = try applyPlan(
            local: makeManifest(modifiedAt: 2_000),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", modifiedAt: 2_500, isDeleted: true, deletedAt: 2_500)
        )
        let localTombstone = try applyPlan(
            local: makeManifest(modifiedAt: 2_600, isDeleted: true, deletedAt: 2_600),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", modifiedAt: 2_000)
        )

        #expect(peerTombstone.actions.first { $0.kind == .objectTombstoneApply }?.bridgeHint == .legacyMetadataManifestApply)
        #expect(localTombstone.actions.first { $0.kind == .objectTombstoneSend }?.bridgeHint == .legacyMetadataManifestSend)
        #expect(peerTombstone.tombstones.allSatisfy { $0.policies.contains(.noPhysicalDelete) && $0.policies.contains(.noGarbageCollection) })
        #expect(localTombstone.actions.filter { $0.kind == .recordingMetadataSend }.isEmpty)
    }

    @Test func activeNewerThanTombstoneRecordsConflictAndDoesNotApply() throws {
        let plan = try applyPlan(
            local: makeManifest(title: "Restored", modifiedAt: 3_000),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", modifiedAt: 2_500, isDeleted: true, deletedAt: 2_500)
        )

        #expect(plan.conflicts.first?.kind == .activeVsTombstone)
        #expect(plan.actions.contains { $0.kind == .conflictRecord })
        #expect(plan.actions.filter { $0.kind == .objectTombstoneApply || $0.kind == .recordingMetadataSend || $0.kind == .recordingMetadataApply }.isEmpty)
    }

    @Test func sameTombstoneCreatesNoApplyOrSendAction() throws {
        let plan = try applyPlan(
            local: makeManifest(modifiedAt: 2_500, isDeleted: true, deletedAt: 2_500),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", modifiedAt: 2_500, isDeleted: true, deletedAt: 2_500)
        )

        #expect(plan.actions.filter { $0.kind == .objectTombstoneApply || $0.kind == .objectTombstoneSend }.isEmpty)
        #expect(plan.conflicts.isEmpty)
    }

    @Test func generatedArtifactDownloadApplyUsesLegacyBridgeAndDoesNotCreateUploadJob() throws {
        let peer = manifestByAddingArtifacts(
            [generatedArtifact(kind: .transcriptMarkdown, hash: String(repeating: "c", count: 64), size: 120, modifiedAt: 4_000, nodeID: "mac-01", platform: "Mac")],
            to: makeManifest(nodeID: "mac-01", platform: "Mac", capabilities: macCapabilities)
        )
        let plan = try applyPlan(local: makeManifest(), peer: peer)
        let action = try #require(plan.actions.first { $0.kind == .generatedArtifactDownloadApply })

        #expect(action.bridgeHint == .legacyArtifactRequestApply)
        #expect(action.target.artifactKind == .transcriptMarkdown)
        #expect(action.preconditions.contains { $0.kind == .peerHashPrefix && $0.value.count == 12 })
        #expect(!plan.actions.contains { $0.bridgeHint == .noGeneratedArtifactUploadJob && $0.kind == .generatedArtifactDownloadApply })
    }

    @Test func tombstonedObjectBlocksGeneratedArtifactResurrection() throws {
        let local = makeManifest(modifiedAt: 5_000, isDeleted: true, deletedAt: 5_000)
        let peer = manifestByAddingArtifacts(
            [generatedArtifact(kind: .noteMarkdown, hash: String(repeating: "d", count: 64), size: 200, modifiedAt: 4_000, nodeID: "mac-01", platform: "Mac")],
            to: makeManifest(nodeID: "mac-01", platform: "Mac", capabilities: macCapabilities)
        )
        let plan = try applyPlan(local: local, peer: peer)

        #expect(plan.actions.filter { $0.kind == .generatedArtifactDownloadApply }.isEmpty)
        #expect(plan.actions.contains { $0.kind == .deferredUnsupported && $0.failureReason == .tombstoneBlocksResurrection })
    }

    @Test func generatedArtifactNoOpDeferConflictAndArtifactTombstoneAreModeledSafely() throws {
        let localSame = generatedArtifact(kind: .summaryJSON, hash: String(repeating: "e", count: 64), size: 80, modifiedAt: 3_000, nodeID: nil, platform: "iPhone")
        let peerSame = generatedArtifact(kind: .summaryJSON, hash: String(repeating: "e", count: 64), size: 80, modifiedAt: 4_000, nodeID: "mac-01", platform: "Mac")
        let noOp = try applyPlan(
            local: manifestByAddingArtifacts([localSame], to: makeManifest(capabilities: iphoneCapabilities + [.summaryArtifact])),
            peer: manifestByAddingArtifacts([peerSame], to: makeManifest(nodeID: "mac-01", platform: "Mac", capabilities: macCapabilities))
        )

        let peerUnknown = CanonicalProjectionContract.makeArtifact(
            objectID: "recording-01",
            kind: .noteJSON,
            availability: .availableWithoutHash,
            byteSize: 42,
            modifiedAt: ts(4_000),
            producedByNodeID: "mac-01",
            platform: "Mac"
        )
        let deferred = try applyPlan(
            local: makeManifest(),
            peer: manifestByAddingArtifacts([peerUnknown], to: makeManifest(nodeID: "mac-01", platform: "Mac", capabilities: macCapabilities))
        )

        let localConflict = generatedArtifact(kind: .transcriptJSON, hash: String(repeating: "a", count: 64), size: 80, modifiedAt: 3_000, nodeID: nil, platform: "iPhone")
        let peerConflict = generatedArtifact(kind: .transcriptJSON, hash: String(repeating: "b", count: 64), size: 80, modifiedAt: 3_000, nodeID: "mac-01", platform: "Mac")
        let conflict = try applyPlan(
            local: manifestByAddingArtifacts([localConflict], to: makeManifest(capabilities: iphoneCapabilities + [.transcriptArtifact])),
            peer: manifestByAddingArtifacts([peerConflict], to: makeManifest(nodeID: "mac-01", platform: "Mac", capabilities: macCapabilities))
        )

        var artifactTombstone = generatedArtifact(kind: .noteMarkdown, hash: String(repeating: "f", count: 64), size: 120, modifiedAt: 4_000, nodeID: "mac-01", platform: "Mac")
        artifactTombstone.tombstone = true
        let tombstone = try applyPlan(
            local: makeManifest(),
            peer: manifestByAddingArtifacts([artifactTombstone], to: makeManifest(nodeID: "mac-01", platform: "Mac", capabilities: macCapabilities))
        )

        #expect(noOp.actions.contains { $0.kind == .generatedArtifactNoOp && $0.result == .noOp })
        #expect(deferred.actions.contains { $0.kind == .deferredUnsupported })
        #expect(conflict.conflicts.first?.kind == .generatedArtifactContentMismatch)
        #expect(tombstone.actions.contains { $0.kind == .artifactTombstoneApply && $0.failureReason == .noPhysicalDeletePolicy })
        #expect(tombstone.tombstones.contains { $0.policies.contains(.noPermanentDelete) })
    }

    @Test func audioConflictRecordsConflictWithoutAudioApplyOrDownload() throws {
        let plan = try applyPlan(
            local: makeManifest(audioHash: String(repeating: "a", count: 64), audioSize: 42),
            peer: makeManifest(nodeID: "mac-01", platform: "Mac", audioHash: String(repeating: "b", count: 64), audioSize: 42)
        )

        #expect(plan.conflicts.first?.kind == .recordingAudioContentMismatch)
        #expect(plan.actions.contains { $0.kind == .conflictRecord })
        #expect(plan.actions.filter { $0.kind == .generatedArtifactDownloadApply || $0.kind == .recordingMetadataApply }.isEmpty)
    }

    @Test func encodedPlanRedactsFullHashesAndPathsAndDedupeKeepsSingleAction() throws {
        let fullHash = String(repeating: "c", count: 64)
        let peer = manifestByAddingArtifacts(
            [generatedArtifact(kind: .transcriptMarkdown, hash: fullHash, size: 120, modifiedAt: 4_000, nodeID: "mac-01", platform: "Mac")],
            to: makeManifest(nodeID: "mac-01", platform: "Mac", capabilities: macCapabilities)
        )
        var plan = try applyPlan(local: makeManifest(), peer: peer)
        if let first = plan.actions.first {
            plan.actions.append(first)
        }
        let deduped = plan.deduplicated()
        let encoded = String(data: try JSONEncoder().encode(deduped), encoding: .utf8) ?? ""

        #expect(deduped.actions.filter { $0.kind == .generatedArtifactDownloadApply }.count == 1)
        #expect(!encoded.contains(fullHash))
        #expect(!encoded.contains("transcripts/recording-01"))
        #expect(!encoded.contains("note body"))
    }

    private var iphoneCapabilities: [CanonicalCapability] {
        [.recordingMetadata, .audioArtifact, .objectProjection]
    }

    private var macCapabilities: [CanonicalCapability] {
        [.recordingMetadata, .audioArtifact, .receiveRecord, .transcriptArtifact, .noteArtifact, .summaryArtifact, .objectProjection]
    }

    private func applyPlan(
        local: CanonicalManifest,
        peer: CanonicalManifest,
        trigger: CanonicalSyncPlanTrigger = .periodic
    ) throws -> CanonicalApplyPlan {
        let syncPlan = try CanonicalSyncPlanner().plan(local: local, peer: peer, trigger: trigger)
        return CanonicalApplyPlanner().plan(local: local, peer: peer, syncPlan: syncPlan, trigger: trigger)
    }

    private func makeManifest(
        title: String = "Lecture",
        nodeID: String = "iphone-01",
        platform: String = "iPhone",
        modifiedAt: TimeInterval = 2_000,
        isDeleted: Bool = false,
        deletedAt: TimeInterval? = nil,
        audioHash: String? = String(repeating: "a", count: 64),
        audioSize: Int64? = 42,
        capabilities: [CanonicalCapability]? = nil
    ) -> CanonicalManifest {
        let metadata = CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: title,
            createdAt: ts(1_000),
            modifiedAt: ts(modifiedAt),
            duration: 42,
            filing: CanonicalRecordingMetadata.Filing(type: "course", subject: "math"),
            isDeleted: isDeleted,
            deletedAt: deletedAt.map(ts)
        )
        let audioAvailability: CanonicalArtifact.Availability = audioHash == nil || audioSize == nil ? .availableWithoutHash : .available
        let audioContentHash = audioHash.map { CanonicalHash($0) }
        let audioArtifact = CanonicalArtifactFact.audio(
            availability: audioAvailability,
            contentHash: audioContentHash,
            byteSize: audioSize,
            logicalName: "audio.m4a"
        ).makeArtifact(objectID: metadata.objectID)
        let artifacts: [CanonicalArtifact] = [audioArtifact]
        let object = CanonicalRecordingObject(objectID: metadata.objectID, nodeID: nodeID, metadata: metadata, artifacts: artifacts)
        return CanonicalManifest.make(
            node: CanonicalNode(nodeID: nodeID, platform: platform, capabilities: capabilities ?? (platform == "Mac" ? macCapabilities : iphoneCapabilities)),
            generatedAt: Date(timeIntervalSince1970: 3_000),
            objects: [object]
        )
    }

    private func generatedArtifact(
        kind: CanonicalArtifact.Kind,
        hash: String,
        size: Int64,
        modifiedAt: TimeInterval,
        nodeID: String?,
        platform: String
    ) -> CanonicalArtifact {
        CanonicalProjectionContract.makeArtifact(
            objectID: "recording-01",
            kind: kind,
            availability: .available,
            contentHash: CanonicalHash(hash),
            byteSize: size,
            logicalPathToken: "transcripts/recording-01/\(kind.rawValue).json",
            modifiedAt: ts(modifiedAt),
            producedByNodeID: nodeID,
            platform: platform
        )
    }

    private func manifestByAddingArtifacts(
        _ artifacts: [CanonicalArtifact],
        to manifest: CanonicalManifest
    ) -> CanonicalManifest {
        guard let object = manifest.objects.first else {
            return manifest
        }
        return CanonicalManifest.make(
            node: manifest.node,
            generatedAt: manifest.generatedAt.date,
            objects: [object.replacingArtifacts(object.artifacts + artifacts)]
        )
    }

    private func ts(_ value: TimeInterval) -> CanonicalTimestamp {
        CanonicalTimestamp(Date(timeIntervalSince1970: value))
    }
}
