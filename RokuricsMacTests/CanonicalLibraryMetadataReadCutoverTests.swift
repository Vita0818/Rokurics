//
//  CanonicalLibraryMetadataReadCutoverTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalLibraryMetadataReadCutoverTests {
    @Test func macReadSourceDefaultsLegacyAndGuardedReadRequiresExplicitConfig() {
        let manifest = Self.studyManifest(title: "Mac Study")
        let canonical = Self.canonicalManifest(
            objects: MacCanonicalLibraryAdapter().makeLibraryObjects(from: manifest)
        )

        let defaultRead = MacLibraryMetadataReadSideSeam().readSource(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            trigger: .periodic,
            syncRunID: "mac-v819-default"
        )
        #expect(defaultRead.returnedSource == .legacy)
        #expect(defaultRead.canonicalReadServed == false)
        #expect(defaultRead.storeMutated == false)
        #expect(defaultRead.syncOrUploadTriggered == false)

        let blocked = MacLibraryMetadataReadSideSeam().readSource(
            sourceConfiguration: CanonicalLibraryMetadataReadSourceConfiguration(mode: .guardedCanonicalRead),
            legacyManifest: manifest,
            canonicalManifest: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "mac-v819-missing-config"
        )
        #expect(blocked.returnedSource == .legacy)
        #expect(blocked.gateResult?.state == .blockedByDefaultConfig)
        #expect(blocked.fallback == .gateBlocked)
    }

    @Test func macExplicitGuardedReadServesCanonicalMetadataOnlyAndDoesNotMutateInventoryOrInbox() {
        let manifest = Self.studyManifest(title: "Mac Study")
        let canonical = Self.canonicalManifest(
            objects: MacCanonicalLibraryAdapter().makeLibraryObjects(from: manifest)
        )

        let result = MacLibraryMetadataReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacyManifest: manifest,
            canonicalManifest: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "mac-v819-guarded"
        )

        #expect(result.gateResult?.state == .allowed)
        #expect(result.canonicalReadServed)
        #expect(result.returnedSource == .canonical)
        #expect(result.readSource.snapshot.folders.count == 1)
        #expect(result.readSource.snapshot.standaloneNotes.count == 1)
        #expect(result.readSource.snapshot.standaloneNotes.first?.fullContentIncluded == false)
        #expect(result.readSource.excludesAudioState)
        #expect(result.readSource.excludesGeneratedArtifactContent)
        #expect(result.readSource.excludesStandaloneNoteContent)
        #expect(result.storeMutated == false)
        #expect(result.syncOrUploadTriggered == false)
        #expect(result.resourceMoved == false)
        #expect(result.contentWritten == false)
        #expect(result.uiMutated == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalLibraryMetadataGuardedCanonicalReadServed })
    }

    @Test func macGuardedReadFallsBackForGateBlockersCanonicalMissingAndReadException() {
        let manifest = Self.studyManifest(title: "Mac Study")
        let canonical = Self.canonicalManifest(
            objects: MacCanonicalLibraryAdapter().makeLibraryObjects(from: manifest)
        )

        let missingEvidence = MacLibraryMetadataReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacyManifest: manifest,
            canonicalManifest: canonical,
            writeSideEvidence: .missing,
            trigger: .periodic,
            syncRunID: "mac-v819-missing-evidence"
        )
        #expect(missingEvidence.returnedSource == .legacy)
        #expect(missingEvidence.gateResult?.state == .blockedByWriteSideEvidence)
        #expect(missingEvidence.fallback == .gateBlocked)

        let missingCanonical = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: nil,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "mac-v819-missing-canonical"
        )
        #expect(missingCanonical.returnedSource == .legacy)
        #expect(missingCanonical.fallback == .canonicalProjectionMissing)

        let failed = MacLibraryMetadataReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacyManifest: manifest,
            canonicalManifest: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "mac-v819-read-exception",
            canonicalReadFailureReason: "canonicalReadException"
        )
        #expect(failed.returnedSource == .legacy)
        #expect(failed.fallback == .canonicalReadException)
        #expect(failed.diagnostics.contains { $0.kind == .canonicalLibraryMetadataGuardedCanonicalReadFallback })
    }

    @Test func macDivergenceUnsupportedAndPathLeakBlockGuardedReadWithRedactedDiagnostics() {
        let legacy = Self.snapshot(source: .legacy)
        let divergent = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: Self.snapshot(source: .canonical, title: "Changed"),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "mac-v819-divergent"
        )
        #expect(divergent.gateResult?.state == .blockedByDivergence)
        #expect(divergent.fallback == .divergenceDetected)

        let unsupported = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [
                CanonicalLibraryObject(
                    objectID: CanonicalLibraryObjectID("object:unsupported"),
                    kind: .unknownUnsupported,
                    unsupportedReason: "unknownStudyItemKind"
                )
            ]
        ).snapshot
        let unsupportedResult = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: unsupported,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "mac-v819-unsupported"
        )
        #expect(unsupportedResult.gateResult?.state == .blockedByUnsupportedObject)
        #expect(unsupportedResult.fallback == .unsupportedObject)

        let pathLeak = CanonicalLibraryMetadataReadSnapshot(
            source: .canonical,
            failures: [
                CanonicalLibraryMetadataReadProjectionFailure(
                    kind: .pathLeakRisk,
                    objectID: "item:leak",
                    objectKind: .standaloneNote,
                    reason: "/Users/private/note.md"
                )
            ]
        )
        let pathLeakResult = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: pathLeak,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "mac-v819-path-leak"
        )
        #expect(pathLeakResult.gateResult?.state == .blockedByPathLeakRisk)
        #expect(pathLeakResult.fallback == .pathLeakRisk)
        #expect(pathLeakResult.diagnostics.map(\.diagnosticsSummary).joined().contains("/Users") == false)
    }

    @Test func macRetirementCandidateRemainsReportOnly() {
        let report = CanonicalLibraryMetadataRetirementCandidateEvaluator.updateAfterGuardedRead(
            evidence: CanonicalLibraryMetadataRetirementCandidateEvidence(
                writeSideCanarySuccessEvidence: true,
                guardedReadSourceEvidence: true,
                observationWindowComplete: true,
                legacyFallbackReady: true,
                divergenceZero: true
            ),
            trigger: .periodic,
            nodeRole: .mac,
            syncRunID: "mac-v819-retirement"
        )

        #expect(report.candidate.isCandidate)
        #expect(report.legacyDeleted == false)
        #expect(report.legacyDisabled == false)
        #expect(report.reportOnly)
        #expect(report.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRetirementCandidateUpdated })
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

    private static func snapshot(
        source: CanonicalLibraryMetadataReadProjectionSource,
        title: String = "Mac Study"
    ) -> CanonicalLibraryMetadataReadSnapshot {
        CanonicalLibraryMetadataReadProjection.build(
            source: source,
            objects: [
                folderObject(id: "folder:math", name: "Math"),
                studyObject(id: "item:note", title: title, kind: .standaloneNote, folders: ["folder:math"], resources: ["notes/note.md"])
            ]
        ).snapshot
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
            itemID: "item:note",
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
