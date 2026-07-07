//
//  CanonicalLibraryMetadataReadSideTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLibraryMetadataReadSideTests {
    @Test func readProjectionEncodesMetadataAndExcludesContentAndPaths() {
        let projection = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [
                Self.folderObject(id: "folder:math", name: "Math", parentID: "folder:root", color: "blue"),
                Self.studyObject(id: "item:study", title: "Study", kind: .externalResource, folders: ["folder:math"], tags: ["Review"], resources: ["resources/study.pdf"]),
                Self.studyObject(id: "item:note", title: "Note", kind: .standaloneNote, folders: ["folder:math"], tags: ["Note"], resources: ["notes/note.md"])
            ]
        )
        let snapshot = projection.snapshot

        #expect(snapshot.folders.count == 1)
        #expect(snapshot.folders.first?.folderID.rawValue == "folder:math")
        #expect(snapshot.folders.first?.parentID?.rawValue == "folder:root")
        #expect(snapshot.folders.first?.colorToken == "blue")
        #expect(snapshot.studyItems.count == 1)
        #expect(snapshot.studyItems.first?.folderIDs.map(\.rawValue) == ["folder:math"])
        #expect(snapshot.studyItems.first?.tags == ["review"])
        #expect(snapshot.standaloneNotes.count == 1)
        #expect(snapshot.standaloneNotes.first?.fullContentIncluded == false)
        #expect(snapshot.contentExcludedCount == 1)
        #expect(snapshot.studyItems.first?.resourceTokenSummary.contains("/") == false)
        #expect(snapshot.standaloneNotes.first?.resourceTokenSummary.contains("/") == false)
        #expect(snapshot.diagnosticsSummary.contains("/Users") == false)
    }

    @Test func projectionOrderIsDeterministic() {
        let first = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [
                Self.studyObject(id: "item:z", title: "Z", kind: .externalResource),
                Self.folderObject(id: "folder:b", name: "B"),
                Self.studyObject(id: "item:a", title: "A", kind: .externalResource),
                Self.folderObject(id: "folder:a", name: "A")
            ]
        ).snapshot
        let second = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [
                Self.folderObject(id: "folder:a", name: "A"),
                Self.studyObject(id: "item:a", title: "A", kind: .externalResource),
                Self.folderObject(id: "folder:b", name: "B"),
                Self.studyObject(id: "item:z", title: "Z", kind: .externalResource)
            ]
        ).snapshot

        #expect(first.folders.map(\.folderID.rawValue) == second.folders.map(\.folderID.rawValue))
        #expect(first.studyItems.map(\.itemID.rawValue) == second.studyItems.map(\.itemID.rawValue))
    }

    @Test func equivalentDiffIsZeroAndMismatchTypesAreReported() {
        let legacy = CanonicalLibraryMetadataReadProjection.build(
            source: .legacy,
            objects: [
                Self.folderObject(id: "folder:math", name: "Math", parentID: "folder:root", color: "blue"),
                Self.studyObject(id: "item:study", title: "Study", kind: .externalResource, folders: ["folder:math"], tags: ["review"], filing: ["course", "math"]),
                Self.studyObject(id: "item:note", title: "Note", kind: .standaloneNote, folders: ["folder:math"], tags: ["note"])
            ]
        ).snapshot
        let equivalent = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [
                Self.folderObject(id: "folder:math", name: "Math", parentID: "folder:root", color: "blue"),
                Self.studyObject(id: "item:study", title: "Study", kind: .externalResource, folders: ["folder:math"], tags: ["review"], filing: ["course", "math"]),
                Self.studyObject(id: "item:note", title: "Note", kind: .standaloneNote, folders: ["folder:math"], tags: ["note"])
            ]
        ).snapshot
        let zero = CanonicalLibraryMetadataReadSideParallelDiff.compare(legacy: legacy, canonical: equivalent)

        #expect(zero.equivalent)
        #expect(zero.divergenceCount == 0)

        let divergent = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [
                Self.folderObject(id: "folder:math", name: "Math 2", parentID: "folder:other", color: "red", isDeleted: true),
                Self.studyObject(id: "item:study", title: "Study 2", kind: .externalResource, folders: ["folder:other"], tags: ["later"], filing: ["course", "physics"]),
                Self.studyObject(id: "item:note", title: "Note 2", kind: .standaloneNote, folders: ["folder:other"], tags: ["later"])
            ]
        ).snapshot
        let report = CanonicalLibraryMetadataReadSideParallelDiff.compare(legacy: legacy, canonical: divergent)
        let kinds = Set(report.divergences.map(\.kind))

        #expect(report.equivalent == false)
        #expect(kinds.contains(.titleMismatch))
        #expect(kinds.contains(.parentMismatch))
        #expect(kinds.contains(.folderMembershipMismatch))
        #expect(kinds.contains(.filingMismatch))
        #expect(kinds.contains(.tagsMismatch))
        #expect(kinds.contains(.colorMismatch))
        #expect(kinds.contains(.trashStateMismatch))
        #expect(report.blockers.contains(.blockingDivergence))
    }

    @Test func unsupportedObjectAndPathLeakRiskBlockReadSideCutover() {
        let legacy = CanonicalLibraryMetadataReadProjection.build(
            source: .legacy,
            objects: [Self.folderObject(id: "folder:math", name: "Math")]
        ).snapshot
        let canonicalUnsupported = CanonicalLibraryMetadataReadProjection.build(
            source: .canonical,
            objects: [
                CanonicalLibraryObject(
                    objectID: CanonicalLibraryObjectID("object:unsupported"),
                    kind: .unknownUnsupported,
                    unsupportedReason: "unknownStudyItemKind"
                )
            ]
        ).snapshot
        let unsupportedReport = CanonicalLibraryMetadataReadSideParallelDiff.compare(
            legacy: legacy,
            canonical: canonicalUnsupported
        )

        #expect(unsupportedReport.unsupportedObjectCount == 1)
        #expect(unsupportedReport.blockers.contains(.unsupportedObject))

        let canonicalPathLeak = CanonicalLibraryMetadataReadSnapshot(
            source: .canonical,
            failures: [
                CanonicalLibraryMetadataReadProjectionFailure(
                    kind: .pathLeakRisk,
                    objectID: "item:leak",
                    objectKind: .standaloneNote,
                    reason: "/Users/redacted/note.md"
                )
            ]
        )
        let pathLeakReport = CanonicalLibraryMetadataReadSideParallelDiff.compare(
            legacy: legacy,
            canonical: canonicalPathLeak
        )

        #expect(pathLeakReport.pathLeakRiskCount == 1)
        #expect(pathLeakReport.blockers.contains(.pathLeakRisk))
        #expect(pathLeakReport.divergences.first?.canonicalValue?.contains("/Users") != true)
    }

    @Test func readSideCutoverCandidateDefaultsOffAndRequiresEvidence() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)

        let disabled = CanonicalLibraryMetadataReadSideCutoverEvaluator.evaluate(
            configuration: .disabled,
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "read-side-disabled"
        )

        #expect(disabled.mode == .disabled)
        #expect(disabled.candidate.state == .disabled)
        #expect(disabled.readPathSwitched == false)

        let missingEvidence = CanonicalLibraryMetadataReadSideCutoverEvaluator.evaluate(
            configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration(mode: .canonicalReadCandidate),
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "read-side-missing-evidence"
        )

        #expect(missingEvidence.candidate.state == .blockedByMissingWriteSideEvidence)
        #expect(missingEvidence.readPathSwitched == false)
        #expect(missingEvidence.uiMutated == false)
        #expect(missingEvidence.syncOrUploadTriggered == false)

        let ready = CanonicalLibraryMetadataReadSideCutoverEvaluator.evaluate(
            configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration(
                mode: .guardedCanonicalRead,
                writeSideEvidence: Self.cleanWriteSideEvidence
            ),
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "read-side-ready"
        )

        #expect(ready.candidate.state == .readyForGuardedCanonicalRead)
        #expect(ready.readPathSwitched == false)
        #expect(ready.diagnostics.contains { $0.kind == .canonicalLibraryMetadataGuardedCanonicalReadSuppressed })
    }

    @Test func retirementCandidateIsReportOnlyAndBlockedBeforeReadSideEvidence() {
        let report = CanonicalLibraryMetadataReadSideParallelDiff.compare(
            legacy: Self.snapshot(source: .legacy),
            canonical: Self.snapshot(source: .canonical)
        )
        let retirement = CanonicalLibraryMetadataRetirementCandidateEvaluator.evaluate(
            writeSideEvidence: Self.cleanWriteSideEvidence,
            readSideCutoverEvidenceAvailable: false,
            observationWindowComplete: true,
            fallbackAvailable: true,
            diffReport: report,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "retirement-report"
        )

        #expect(retirement.candidate.isCandidate == false)
        #expect(retirement.candidate.blockers.contains(.missingReadSideCutoverEvidence))
        #expect(retirement.legacyDeleted == false)
        #expect(retirement.legacyDisabled == false)
        #expect(retirement.reportOnly)
        #expect(retirement.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRetirementCandidateBlocked })
    }

    @Test func iPhoneReadSideParallelSeamIsDefaultOffAndEnabledProducesNonMutatingReport() {
        let manifest = Self.studyManifest(title: "Study")
        let canonical = Self.canonicalManifest(
            objects: IPhoneCanonicalLibraryAdapter().makeLibraryObjects(from: manifest)
        )

        let disabled = IPhoneLibraryMetadataReadSideSeam().evaluate(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            trigger: .periodic,
            syncRunID: "iphone-read-side-disabled"
        )

        #expect(disabled.mode == .disabled)
        #expect(disabled.diffReport == nil)

        let enabled = IPhoneLibraryMetadataReadSideSeam(
            configuration: CanonicalLibraryMetadataReadSideCutoverConfiguration(
                mode: .parallelOnly,
                writeSideEvidence: Self.cleanWriteSideEvidence
            )
        ).evaluate(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            trigger: .periodic,
            syncRunID: "iphone-read-side-enabled"
        )

        #expect(enabled.diffReport?.equivalent == true)
        #expect(enabled.legacyReadFallbackAvailable)
        #expect(enabled.readPathSwitched == false)
        #expect(enabled.uiMutated == false)
        #expect(enabled.syncOrUploadTriggered == false)
        #expect(enabled.diagnostics.contains { $0.kind == .canonicalLibraryMetadataReadSideParallelCompleted })
        #expect(enabled.diagnosticsSummary.contains("/Users") == false)
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

    private static func snapshot(source: CanonicalLibraryMetadataReadProjectionSource) -> CanonicalLibraryMetadataReadSnapshot {
        CanonicalLibraryMetadataReadProjection.build(
            source: source,
            objects: [
                folderObject(id: "folder:math", name: "Math", parentID: "folder:root", color: "blue"),
                studyObject(id: "item:study", title: "Study", kind: .externalResource, folders: ["folder:math"], tags: ["review"], filing: ["course", "math"]),
                studyObject(id: "item:note", title: "Note", kind: .standaloneNote, folders: ["folder:math"], tags: ["note"])
            ]
        ).snapshot
    }

    private static func canonicalManifest(objects: [CanonicalLibraryObject]) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(nodeID: "iphone-01", platform: "iPhone"),
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
            deviceID: "iphone-01",
            generatedAt: date(3_000),
            items: [item],
            folders: [folder]
        )
    }

    private static func folderObject(
        id: String,
        name: String,
        parentID: String? = nil,
        color: String? = nil,
        isDeleted: Bool = false
    ) -> CanonicalLibraryObject {
        let folderID = CanonicalLibraryObjectID(id)
        let folder = CanonicalFolderObject(
            metadata: CanonicalFolderMetadata(
                folderID: folderID,
                name: name,
                parentID: parentID.map { CanonicalLibraryObjectID($0) },
                hierarchyPath: CanonicalHierarchyPath(["course", name.lowercased()]),
                hierarchyLevel: "subject",
                colorToken: color,
                isDeleted: isDeleted,
                deletedAt: isDeleted ? ts(2_500) : nil,
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
        tags: [String] = [],
        filing: [String] = [],
        resources: [String] = [],
        isDeleted: Bool = false
    ) -> CanonicalLibraryObject {
        let itemID = CanonicalLibraryObjectID(id)
        let folderIDs = folders.map { CanonicalLibraryObjectID($0) }
        let item = CanonicalStudyItemObject(
            metadata: CanonicalStudyItemMetadata(
                itemID: itemID,
                itemKind: kind,
                title: title,
                filingPath: CanonicalHierarchyPath(filing),
                folderIDs: folderIDs,
                parentReferences: folderIDs.map { CanonicalParentReference(parentID: $0, relation: "folder") },
                tags: tags,
                logicalResourceTokens: resources,
                isDeleted: isDeleted,
                deletedAt: isDeleted ? ts(2_500) : nil,
                businessModifiedAt: ts(2_000)
            )
        )
        let objectKind: CanonicalObjectKind = kind == .standaloneNote ? .standaloneNote : .standaloneStudyItem
        return CanonicalLibraryObject(
            objectID: item.itemID,
            kind: objectKind,
            studyItem: item,
            standaloneNote: objectKind == .standaloneNote ? CanonicalStandaloneNoteObject(studyItem: item) : nil
        )
    }

    private static func ts(_ value: TimeInterval) -> CanonicalTimestamp {
        CanonicalTimestamp(date(value))
    }

    private static func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}
