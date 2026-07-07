//
//  CanonicalLibraryMetadataReadSideTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalLibraryMetadataReadSideTests {
    @Test func macReadSideParallelSeamDisabledByDefault() {
        let manifest = Self.studyManifest(title: "Mac Study")
        let canonical = Self.canonicalManifest(
            objects: MacCanonicalLibraryAdapter().makeLibraryObjects(from: manifest)
        )

        let result = MacLibraryMetadataReadSideSeam().evaluate(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            trigger: .periodic,
            syncRunID: "mac-read-side-disabled"
        )

        #expect(result.mode == .disabled)
        #expect(result.diffReport == nil)
        #expect(result.readPathSwitched == false)
        #expect(result.uiMutated == false)
        #expect(result.syncOrUploadTriggered == false)
    }

    @Test func macReadSideParallelSeamEnabledProducesDiffReportWithoutInventoryMutation() {
        let manifest = Self.studyManifest(title: "Mac Study")
        let canonical = Self.canonicalManifest(
            objects: MacCanonicalLibraryAdapter().makeLibraryObjects(from: manifest)
        )
        let result = MacLibraryMetadataReadSideSeam(
            configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration(
                mode: .parallelOnly,
                writeSideEvidence: Self.cleanWriteSideEvidence
            )
        ).evaluate(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            trigger: .periodic,
            syncRunID: "mac-read-side-enabled"
        )

        #expect(manifest.items.first?.title == "Mac Study")
        #expect(result.diffReport?.equivalent == true)
        #expect(result.legacyReadFallbackAvailable)
        #expect(result.readPathSwitched == false)
        #expect(result.uiMutated == false)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.diagnostics.contains { $0.kind == CanonicalLibraryMetadataCutoverDiagnosticKind.canonicalLibraryMetadataReadSideParallelCompleted })
    }

    @Test func macUnsupportedObjectBlocksReadSideCandidate() {
        let legacy = CanonicalLibraryMetadataReadProjection.build(
            source: .legacy,
            objects: [Self.folderObject(id: "folder:math", name: "Math")]
        ).snapshot
        let canonical = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [
                CanonicalLibraryObject(
                    objectID: CanonicalLibraryObjectID("object:unsupported"),
                    kind: .unknownUnsupported,
                    unsupportedReason: "unknownStudyItemKind"
                )
            ]
        ).snapshot
        let result = CanonicalLibraryMetadataReadSideCutoverEvaluator.evaluate(
            configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration(
                mode: .canonicalReadCandidate,
                writeSideEvidence: Self.cleanWriteSideEvidence
            ),
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "mac-read-side-unsupported"
        )

        #expect(result.candidate.state == CanonicalLibraryMetadataReadSideCutoverCandidateState.blockedByUnsupportedObject)
        #expect(result.failures.contains(CanonicalLibraryMetadataReadSideCutoverFailure.unsupportedObject))
        #expect(result.readPathSwitched == false)
        #expect(result.diagnostics.contains { $0.kind == CanonicalLibraryMetadataCutoverDiagnosticKind.canonicalLibraryMetadataReadSideUnsupportedObject })
    }

    @Test func macLegacyFallbackMissingBlocksGuardedRead() {
        let snapshot = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [Self.folderObject(id: "folder:math", name: "Math")]
        ).snapshot
        let result = CanonicalLibraryMetadataReadSideCutoverEvaluator.evaluate(
            configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration(
                mode: .guardedCanonicalRead,
                writeSideEvidence: Self.cleanWriteSideEvidence,
                legacyFallbackAvailable: false
            ),
            legacySnapshot: snapshot,
            canonicalSnapshot: snapshot,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "mac-read-side-fallback-missing"
        )

        #expect(result.candidate.state == CanonicalLibraryMetadataReadSideCutoverCandidateState.blockedByFallbackMissing)
        #expect(result.legacyReadFallbackAvailable == false)
        #expect(result.readPathSwitched == false)
        #expect(result.diagnostics.contains { $0.kind == CanonicalLibraryMetadataCutoverDiagnosticKind.canonicalLibraryMetadataGuardedCanonicalReadSuppressed })
    }

    @Test func macStandaloneNoteContentExcludedAndDiagnosticsRedacted() {
        let snapshot = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [
                Self.studyObject(
                    id: "item:note",
                    title: "Note",
                    kind: .standaloneNote,
                    folders: ["folder:math"],
                    resources: ["notes/note.md"]
                )
            ]
        ).snapshot

        #expect(snapshot.standaloneNotes.first?.fullContentIncluded == false)
        #expect(snapshot.contentExcludedCount == 1)
        #expect(snapshot.standaloneNotes.first?.resourceTokenSummary.contains("/") == false)
        #expect(snapshot.diagnosticsSummary.contains("/Users") == false)
    }

    private static var cleanWriteSideEvidence: CanonicalLibraryMetadataWriteSideEvidenceLinkage {
        CanonicalLibraryMetadataWriteSideEvidenceLinkage(
            canaryStageStatus: .passed,
            latestSuccessfulStage: .allEligible,
            rollbackFailureCount: 0,
            duplicateSuppressionCount: 3,
            unresolvedConflictCount: 0,
            resourceMoveBlockedCount: 0,
            readSideDivergenceCount: 0,
            writeSideDomainCutoverComplete: true
        )
    }

    private static func canonicalManifest(objects: [CanonicalLibraryObject]) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(nodeID: "mac-01", platform: "Mac"),
            generatedAt: date(3_000),
            objects: [],
            libraryObjects: objects,
            manifestCapabilities: [.canonicalLibraryObjectsV1, .canonicalFolderObjectsV1, .canonicalStudyItemObjectsV1]
        )
    }

    private static func studyManifest(title: String) -> StudyLibrarySyncManifest {
        let item = StudyItemMetadata(
            itemID: "item:study",
            kind: .standaloneNote,
            title: title,
            createdAt: date(1_000),
            updatedAt: date(2_000),
            filing: StudyFilingPath(type: "course", subject: "math"),
            tags: [StudyTag(namespace: "topic", value: "review")],
            folderIDs: ["folder:math"],
            noteRelativePath: "notes/note.md"
        )
        let folder = StudyFolderMetadata(
            folderID: "folder:math",
            name: "Math",
            level: .subject,
            path: StudyFilingPath(type: "course", subject: "math"),
            parentFolderID: "folder:root",
            updatedAt: date(2_000),
            colorToken: .blue
        )
        return StudyLibrarySyncManifest.make(
            deviceID: "mac-01",
            generatedAt: date(3_000),
            items: [item],
            folders: [folder]
        )
    }

    private static func folderObject(id: String, name: String) -> CanonicalLibraryObject {
        let folderID = CanonicalLibraryObjectID(id)
        let folder = CanonicalFolderObject(
            metadata: CanonicalFolderMetadata(
                folderID: folderID,
                name: name,
                hierarchyPath: CanonicalHierarchyPath(["course", name.lowercased()]),
                hierarchyLevel: "subject",
                colorToken: "blue",
                businessModifiedAt: ts(2_000)
            )
        )
        return CanonicalLibraryObject(objectID: folder.folderID, kind: .folder, folder: folder)
    }

    private static func studyObject(
        id: String,
        title: String,
        kind: CanonicalStudyItemKind,
        folders: [String] = [],
        resources: [String] = []
    ) -> CanonicalLibraryObject {
        let itemID = CanonicalLibraryObjectID(id)
        let folderIDs = folders.map { CanonicalLibraryObjectID($0) }
        let item = CanonicalStudyItemObject(
            metadata: CanonicalStudyItemMetadata(
                itemID: itemID,
                itemKind: kind,
                title: title,
                folderIDs: folderIDs,
                parentReferences: folderIDs.map { CanonicalParentReference(parentID: $0, relation: "folder") },
                logicalResourceTokens: resources,
                businessModifiedAt: ts(2_000)
            )
        )
        return CanonicalLibraryObject(
            objectID: item.itemID,
            kind: kind == .standaloneNote ? .standaloneNote : .standaloneStudyItem,
            studyItem: item,
            standaloneNote: kind == .standaloneNote ? CanonicalStandaloneNoteObject(studyItem: item) : nil
        )
    }

    private static func ts(_ value: TimeInterval) -> CanonicalTimestamp {
        CanonicalTimestamp(date(value))
    }

    private static func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}
