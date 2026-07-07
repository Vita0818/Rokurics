//
//  CanonicalProductionTestFixtures.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
@testable import RokuricsMac

enum CanonicalProductionTestFixtures {
    static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    static func node(_ id: String = "mac-01", platform: String = "Mac") -> CanonicalNode {
        CanonicalNode(
            nodeID: id,
            platform: platform,
            capabilities: [
                .recordingMetadata,
                .audioArtifact,
                .receiveRecord,
                .transcriptArtifact,
                .noteArtifact,
                .summaryArtifact,
                .objectProjection,
                .canonicalLibraryObjectsV1,
                .canonicalFolderObjectsV1,
                .canonicalStudyItemObjectsV1,
                .canonicalTransferStateV1,
                .canonicalObjectProjectionV1,
                .canonicalInventoryBuilderV1,
                .canonicalRetirementReadinessV1
            ]
        )
    }

    static func recording(
        id: String = "recording-01",
        title: String = "Lecture",
        modifiedAt: Date = date(2_000),
        audio: Bool = false
    ) -> CanonicalRecordingObject {
        let metadata = CanonicalRecordingMetadata(
            objectID: id,
            title: title,
            createdAt: CanonicalTimestamp(date(1_000)),
            modifiedAt: CanonicalTimestamp(modifiedAt),
            duration: 42
        )
        let artifacts = audio ? [audioArtifact(objectID: id)] : []
        return CanonicalRecordingObject(objectID: id, nodeID: "mac-01", metadata: metadata, artifacts: artifacts)
    }

    static func audioArtifact(objectID: String = "recording-01") -> CanonicalArtifact {
        CanonicalArtifactFact.audio(
            availability: .available,
            contentHash: CanonicalHash(String(repeating: "a", count: 64)),
            byteSize: 42,
            logicalName: "audio.m4a",
            logicalPathToken: "audio/\(objectID).m4a",
            producedByNodeID: "iphone-01"
        ).makeArtifact(objectID: objectID)
    }

    static func snapshot(
        node: CanonicalNode = node(),
        recordings: [CanonicalRecordingObject] = [recording()],
        legacyActions: CanonicalLegacyActionSnapshot = .empty,
        unsupportedFacts: [CanonicalProductionUnsupportedFact] = [],
        generatedAt: Date = date(4_000)
    ) -> CanonicalProductionSnapshot {
        MacCanonicalProductionSnapshotAdapter().buildSnapshot(
            from: MacCanonicalProductionSnapshotInput(
                node: node,
                recordingObjects: recordings,
                unsupportedFacts: unsupportedFacts,
                legacyActions: legacyActions,
                generatedAt: generatedAt
            )
        )
    }

    static func completeRuntimeReadiness() -> CanonicalRuntimeReadinessReport {
        CanonicalRuntimeReadinessEvaluator().evaluate(
            evidence: CanonicalRuntimeReadinessEvidence(
                fileRootBinding: true,
                fileHashVerification: true,
                transportRouteValidation: true,
                uploadResumableState: true,
                applyExecutor: true,
                conflictResolver: true,
                twoNodeHarness: true,
                productionStillLegacyOwned: true
            ),
            generatedAt: date(5_000)
        )
    }
}
