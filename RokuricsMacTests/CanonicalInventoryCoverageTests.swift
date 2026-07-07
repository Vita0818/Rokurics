//
//  CanonicalInventoryCoverageTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalInventoryCoverageTests {
    @Test func inventoryBuilderReportsCoverageAndBuildsManifestWithoutSensitiveContent() throws {
        let result = CanonicalInventoryBuilderContract().build(
            from: CanonicalInventoryInputSnapshot(
                node: CanonicalNode(nodeID: "mac-01", platform: "Mac"),
                generatedAt: date(5_000),
                recordingObjects: [recording()],
                libraryObjects: [folderObject(), studyObject()],
                libraryTombstones: [
                    CanonicalLibraryTombstone(
                        objectID: CanonicalLibraryObjectID("folder:math"),
                        objectKind: .folder,
                        deletedAt: ts(4_000),
                        reason: .softDelete
                    )
                ],
                unsupportedObjects: [
                    CanonicalInventoryUnsupportedObject(
                        objectID: CanonicalLibraryObjectID("unsupported:legacy"),
                        objectKind: .unknownUnsupported,
                        reason: "legacyKind"
                    )
                ]
            )
        )
        let encoded = String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? ""

        #expect(result.manifest.hasValidManifestHash)
        #expect(result.coverage.recordingCoverage == 1)
        #expect(result.coverage.audioCoverage == 1)
        #expect(result.coverage.generatedArtifactCoverage == 1)
        #expect(result.coverage.folderCoverage == 1)
        #expect(result.coverage.studyItemCoverage == 1)
        #expect(result.coverage.tombstoneCoverage == 1)
        #expect(result.coverage.unsupportedLegacyObjectCount == 1)
        #expect(result.manifest.manifestCapabilities.contains(.canonicalInventoryBuilderV1))
        #expect(!encoded.contains("/Users/"))
        #expect(!encoded.contains("full transcript"))
    }

    @Test func retirementReadinessBlocksFallbackConflictsTransportUploadAndStorage() {
        let conflict = CanonicalConflictRecord(
            kind: .recordingMetadataConcurrentEdit,
            target: CanonicalApplyTarget(objectID: "recording-01"),
            resolutionPolicy: .keepBothNoOverwrite
        )
        let report = CanonicalRetirementReadinessEvaluator().evaluate(
            manifest: CanonicalManifest.make(node: CanonicalNode(nodeID: "mac-01", platform: "Mac"), objects: [recording()]),
            libraryPlan: CanonicalLibrarySyncPlan(fallbackRequiredObjectIDs: [CanonicalLibraryObjectID("item:unsupported")]),
            applyPlan: CanonicalApplyPlan(trigger: .periodic, conflicts: [conflict]),
            transferProjection: nil,
            inventoryCoverage: CanonicalInventoryCoverageReport(
                recordingCoverage: 1,
                audioCoverage: 1,
                generatedArtifactCoverage: 1,
                folderCoverage: 0,
                studyItemCoverage: 0,
                tombstoneCoverage: 0,
                unsupportedLegacyObjectCount: 1,
                fallbackRequiredCount: 1
            ),
            fallbackUsed: true,
            generatedAt: date(6_000)
        )

        #expect(report.status(for: .conflicts) == .blocked)
        #expect(report.status(for: .transport) == .blocked)
        #expect(report.status(for: .uploadRuntime) == .blocked)
        #expect(report.status(for: .physicalStorage) == .blocked)
        #expect(report.blockers.contains { $0.kind == .fallbackUsed })
        #expect(report.blockers.contains { $0.kind == .unsupportedObjectKinds })
        #expect(report.blockers.contains { $0.kind == .uiStillReadsLegacyStatus })
    }

    private func recording() -> CanonicalRecordingObject {
        let metadata = CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: "Lecture",
            createdAt: ts(1_000),
            modifiedAt: ts(2_000),
            duration: 42
        )
        let audio = CanonicalArtifactFact.audio(
            availability: .available,
            contentHash: CanonicalHash(String(repeating: "a", count: 64)),
            byteSize: 42,
            logicalName: "audio.m4a"
        ).makeArtifact(objectID: metadata.objectID)
        let transcript = CanonicalProjectionContract.makeArtifact(
            objectID: metadata.objectID,
            kind: .transcriptMarkdown,
            availability: .available,
            contentHash: CanonicalHash(String(repeating: "b", count: 64)),
            byteSize: 120,
            logicalPathToken: "transcripts/recording-01/transcript.md",
            modifiedAt: ts(3_000),
            producedByNodeID: "mac-01",
            platform: "Mac"
        )
        return CanonicalRecordingObject(
            objectID: metadata.objectID,
            nodeID: "mac-01",
            metadata: metadata,
            artifacts: [audio, transcript]
        )
    }

    private func folderObject() -> CanonicalLibraryObject {
        let folder = CanonicalFolderObject(
            metadata: CanonicalFolderMetadata(
                folderID: CanonicalLibraryObjectID("folder:math"),
                name: "Math",
                businessModifiedAt: ts(2_000)
            )
        )
        return CanonicalLibraryObject(objectID: folder.folderID, kind: .folder, folder: folder)
    }

    private func studyObject() -> CanonicalLibraryObject {
        let item = CanonicalStudyItemObject(
            metadata: CanonicalStudyItemMetadata(
                itemID: CanonicalLibraryObjectID("item:note"),
                itemKind: .standaloneNote,
                title: "Note",
                businessModifiedAt: ts(2_000)
            )
        )
        return CanonicalLibraryObject(
            objectID: item.itemID,
            kind: .standaloneNote,
            studyItem: item,
            standaloneNote: CanonicalStandaloneNoteObject(studyItem: item)
        )
    }

    private func ts(_ value: TimeInterval) -> CanonicalTimestamp {
        CanonicalTimestamp(date(value))
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}
