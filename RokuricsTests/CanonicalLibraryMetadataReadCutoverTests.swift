//
//  CanonicalLibraryMetadataReadCutoverTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalLibraryMetadataReadCutoverTests {
    @Test func v852ContractUsesCanonicalLibraryMetadataSchemaAndExcludesResourceTokensFromHash() {
        let noteA = Self.studyObject(
            id: "item:note",
            title: "Note",
            kind: .standaloneNote,
            folders: ["folder:math"],
            tags: ["note"],
            filing: ["course", "math"],
            resources: ["notes/a.md"]
        )
        let noteB = Self.studyObject(
            id: "item:note",
            title: "Note",
            kind: .standaloneNote,
            folders: ["folder:math"],
            tags: ["note"],
            filing: ["course", "math"],
            resources: ["notes/b.md"]
        )
        let payload = CanonicalProjectionContract.metadataHashPayload(for: noteA.studyItem!.metadata)

        #expect(payload["schema"] == CanonicalLibraryMetadataHashSchema.version)
        #expect(CanonicalLibraryMetadataHashSchema.v1.schemaVersion == "canonical-library-metadata-v1")
        #expect(CanonicalLibraryMetadataHashSchema.v1.excludedFields.contains("logicalResourceTokens"))
        #expect(payload["logicalResourceTokens"] == nil)
        #expect(payload["resourceTokens"] == nil)
        #expect(noteA.metadataHash == noteB.metadataHash)
    }

    @Test func v852ModifiedAtPolicyOwnsLibraryMetadataDecisionDeterministically() {
        let localNewer = CanonicalLibraryMetadataModifiedAtPolicy.current.decide(
            CanonicalLibraryMetadataDecisionInput(
                objectID: CanonicalLibraryObjectID("item:study"),
                objectKind: .standaloneStudyItem,
                local: Self.studyObject(id: "item:study", title: "Local", kind: .externalResource, modifiedAt: 3_000),
                peer: Self.studyObject(id: "item:study", title: "Peer", kind: .externalResource, modifiedAt: 2_000)
            )
        )
        let peerNewer = CanonicalLibraryMetadataModifiedAtPolicy.current.decide(
            CanonicalLibraryMetadataDecisionInput(
                objectID: CanonicalLibraryObjectID("item:study"),
                objectKind: .standaloneStudyItem,
                local: Self.studyObject(id: "item:study", title: "Local", kind: .externalResource, modifiedAt: 2_000),
                peer: Self.studyObject(id: "item:study", title: "Peer", kind: .externalResource, modifiedAt: 3_000)
            )
        )
        let tieA = CanonicalLibraryMetadataModifiedAtPolicy.current.decide(
            CanonicalLibraryMetadataDecisionInput(
                objectID: CanonicalLibraryObjectID("item:study"),
                objectKind: .standaloneStudyItem,
                local: Self.studyObject(id: "item:study", title: "A", kind: .externalResource, modifiedAt: 2_000),
                peer: Self.studyObject(id: "item:study", title: "B", kind: .externalResource, modifiedAt: 2_000)
            )
        )
        let tieB = CanonicalLibraryMetadataModifiedAtPolicy.current.decide(
            CanonicalLibraryMetadataDecisionInput(
                objectID: CanonicalLibraryObjectID("item:study"),
                objectKind: .standaloneStudyItem,
                local: Self.studyObject(id: "item:study", title: "A", kind: .externalResource, modifiedAt: 2_000),
                peer: Self.studyObject(id: "item:study", title: "B", kind: .externalResource, modifiedAt: 2_000)
            )
        )

        #expect(localNewer.action == .sendLocal)
        #expect(localNewer.reason == "localMetadataNewer")
        #expect(peerNewer.action == .applyPeer)
        #expect(peerNewer.reason == "peerMetadataNewer")
        #expect(tieA.action == .deferTie)
        #expect(tieA.reason == "metadataTieConflict")
        #expect(tieA == tieB)
    }

    @Test func readSourceDefaultsLegacyAndParallelCompareReturnsLegacy() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)

        let defaultResult = CanonicalLibraryMetadataReadSourceProvider().read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: .missing,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-default"
        )

        #expect(defaultResult.mode == .legacy)
        #expect(defaultResult.returnedSource == .legacy)
        #expect(defaultResult.legacyReadReturned)
        #expect(defaultResult.canonicalReadServed == false)
        #expect(defaultResult.canonicalCandidateBuilt == false)
        #expect(defaultResult.fallback == .legacyDefault)

        let parallel = CanonicalLibraryMetadataReadSourceProvider(
            configuration: CanonicalLibraryMetadataReadSourceConfiguration(mode: .parallelCompare)
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-parallel"
        )

        #expect(parallel.returnedSource == .legacy)
        #expect(parallel.diffReport?.equivalent == true)
        #expect(parallel.canonicalCandidateBuilt)
        #expect(parallel.canonicalReadServed == false)
        #expect(parallel.diagnostics.contains { $0.kind == .canonicalLibraryMetadataReadOutputEquivalent })
    }

    @Test func canonicalCandidateBuildsButDoesNotServeUIByDefault() {
        let result = CanonicalLibraryMetadataReadSourceProvider(
            configuration: CanonicalLibraryMetadataReadSourceConfiguration(mode: .canonicalCandidate)
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-candidate"
        )

        #expect(result.canonicalCandidateBuilt)
        #expect(result.returnedSource == .legacy)
        #expect(result.canonicalReadServed == false)
        #expect(result.uiMutated == false)
        #expect(result.storeMutated == false)
    }

    @Test func guardedCanonicalReadGateBlocksWithoutConfigEvidenceOrCleanDiff() {
        let legacy = Self.snapshot(source: .legacy)
        let canonical = Self.snapshot(source: .canonical)

        let missingConfig = CanonicalLibraryMetadataReadSourceProvider(
            configuration: CanonicalLibraryMetadataReadSourceConfiguration(mode: .guardedCanonicalRead)
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-missing-config"
        )
        #expect(missingConfig.gateResult?.state == .blockedByDefaultConfig)
        #expect(missingConfig.fallback == .gateBlocked)
        #expect(missingConfig.returnedSource == .legacy)

        let missingEvidence = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: canonical,
            writeSideEvidence: .missing,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-missing-evidence"
        )
        #expect(missingEvidence.gateResult?.state == .blockedByWriteSideEvidence)
        #expect(missingEvidence.fallback == .gateBlocked)

        let divergent = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: Self.snapshot(source: .canonical, title: "Different"),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-divergent"
        )
        #expect(divergent.gateResult?.state == .blockedByDivergence)
        #expect(divergent.fallback == .divergenceDetected)
        #expect(divergent.fatalForFutureStage)
        #expect(divergent.diagnostics.contains { $0.kind == .canonicalLibraryMetadataReadOutputDivergent })
    }

    @Test func gateBlocksUnsupportedPathLeakFallbackMissingAndOtherActiveDomain() {
        let legacy = Self.snapshot(source: .legacy)
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
            nodeRole: .iPhone,
            syncRunID: "v819-unsupported"
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
            nodeRole: .iPhone,
            syncRunID: "v819-path-leak"
        )
        #expect(pathLeakResult.gateResult?.state == .blockedByPathLeakRisk)
        #expect(pathLeakResult.fallback == .pathLeakRisk)
        #expect(pathLeakResult.diagnostics.map(\.diagnosticsSummary).joined().contains("/Users") == false)

        let fallbackMissing = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            legacyFallbackAvailable: false,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-fallback-missing"
        )
        #expect(fallbackMissing.gateResult?.state == .blockedByFallbackMissing)

        let otherDomain = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead(),
            matrix: Self.matrixWithOtherActivePilot
        ).read(
            legacySnapshot: legacy,
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-other-domain"
        )
        #expect(otherDomain.gateResult?.state == .blockedByOtherActiveDomain)
    }

    @Test func guardedCanonicalReadServesCanonicalOnlyWhenAllEvidencePasses() {
        let result = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-allowed"
        )

        #expect(result.gateResult?.state == .allowed)
        #expect(result.canonicalReadServed)
        #expect(result.returnedSource == .canonical)
        #expect(result.fallback == .none)
        #expect(result.fallbackCount == 0)
        #expect(result.legacySnapshot.objectCount == result.readSource.snapshot.objectCount)
        #expect(result.readSource.coversFolderMetadata)
        #expect(result.readSource.coversStudyItemMetadata)
        #expect(result.readSource.coversStandaloneNoteMetadata)
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

    @Test func guardedReadFallsBackWhenCanonicalMissingOrReadFails() {
        let missing = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: nil,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-canonical-missing"
        )
        #expect(missing.returnedSource == .legacy)
        #expect(missing.fallback == .canonicalProjectionMissing)
        #expect(missing.fallbackCount == 1)

        let failed = CanonicalLibraryMetadataReadSourceProvider(
            configuration: .explicitGuardedCanonicalRead()
        ).read(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-canonical-exception",
            canonicalReadFailureReason: "canonicalReadException"
        )
        #expect(failed.returnedSource == .legacy)
        #expect(failed.fallback == .canonicalReadException)
        #expect(failed.diagnostics.contains { $0.kind == .canonicalLibraryMetadataGuardedCanonicalReadFallback })
    }

    @Test func retirementCandidateUpdatesButDoesNotRetireLegacy() {
        let blocked = CanonicalLibraryMetadataRetirementCandidateEvaluator.updateAfterGuardedRead(
            evidence: CanonicalLibraryMetadataRetirementCandidateEvidence(
                writeSideCanarySuccessEvidence: true,
                guardedReadSourceEvidence: false,
                observationWindowComplete: false,
                legacyFallbackReady: true,
                divergenceZero: true
            ),
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-retirement-blocked"
        )
        #expect(blocked.candidate.isCandidate == false)
        #expect(blocked.candidate.blockers.contains(.missingGuardedReadSourceEvidence))
        #expect(blocked.legacyDeleted == false)
        #expect(blocked.legacyDisabled == false)
        #expect(blocked.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRetirementStillBlocked })

        let ready = CanonicalLibraryMetadataRetirementCandidateEvaluator.updateAfterGuardedRead(
            evidence: CanonicalLibraryMetadataRetirementCandidateEvidence(
                writeSideCanarySuccessEvidence: true,
                guardedReadSourceEvidence: true,
                observationWindowComplete: true,
                legacyFallbackReady: true,
                divergenceZero: true
            ),
            trigger: .periodic,
            nodeRole: .iPhone,
            syncRunID: "v819-retirement-ready"
        )
        #expect(ready.candidate.isCandidate)
        #expect(ready.legacyDeleted == false)
        #expect(ready.legacyDisabled == false)
        #expect(ready.reportOnly)
        #expect(ready.diagnostics.contains { $0.kind == .canonicalLibraryMetadataRetirementCandidateUpdated })
    }

    @Test func iPhoneSeamDefaultLegacyAndExplicitGuardedReadReturnsCanonicalMetadataOnlyOutput() {
        let manifest = Self.studyManifest(title: "Study")
        let canonical = Self.canonicalManifest(
            objects: IPhoneCanonicalLibraryAdapter().makeLibraryObjects(from: manifest)
        )

        let defaultRead = IPhoneLibraryMetadataReadSideSeam().readSource(
            legacyManifest: manifest,
            canonicalManifest: canonical,
            trigger: .periodic,
            syncRunID: "v819-iphone-default"
        )
        #expect(defaultRead.returnedSource == .legacy)
        #expect(defaultRead.legacyReadReturned)

        let guarded = IPhoneLibraryMetadataReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacyManifest: manifest,
            canonicalManifest: canonical,
            writeSideEvidence: Self.cleanWriteSideEvidence,
            trigger: .periodic,
            syncRunID: "v819-iphone-guarded"
        )
        #expect(guarded.returnedSource == .canonical)
        #expect(guarded.canonicalReadServed)
        #expect(guarded.readSource.snapshot.folders.count == 1)
        #expect(guarded.readSource.snapshot.standaloneNotes.count == 1)
        #expect(guarded.readSource.snapshot.standaloneNotes.first?.fullContentIncluded == false)
        #expect(guarded.readSource.excludesAudioState)
        #expect(guarded.readSource.excludesGeneratedArtifactContent)
        #expect(guarded.storeMutated == false)
        #expect(guarded.syncOrUploadTriggered == false)
        #expect(guarded.uiMutated == false)

        let fallback = IPhoneLibraryMetadataReadSideSeam().readSource(
            sourceConfiguration: .explicitGuardedCanonicalRead(),
            legacyManifest: manifest,
            canonicalManifest: canonical,
            writeSideEvidence: .missing,
            trigger: .periodic,
            syncRunID: "v819-iphone-fallback"
        )
        #expect(fallback.returnedSource == .legacy)
        #expect(fallback.fallback != .none)
        #expect(fallback.gateResult?.allowed == false)
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

    private static var matrixWithOtherActivePilot: CanonicalMigrationDomainMatrix {
        var policies = CanonicalMigrationDomainMatrix.defaultV813().policies
        policies.append(
            CanonicalMigrationDomainPolicy(
                domain: .audioUpload,
                activePilot: true,
                activePilotExplicit: true,
                staticOnly: false,
                blockedForRealMigration: false
            )
        )
        return CanonicalMigrationDomainMatrix(policies: policies)
    }

    private static func snapshot(
        source: CanonicalLibraryMetadataReadProjectionSource,
        title: String = "Study"
    ) -> CanonicalLibraryMetadataReadSnapshot {
        CanonicalLibraryMetadataReadProjection.build(
            source: source,
            objects: [
                folderObject(id: "folder:math", name: "Math", parentID: "folder:root", color: "blue"),
                studyObject(id: "item:study", title: title, kind: .externalResource, folders: ["folder:math"], tags: ["review"], filing: ["course", "math"]),
                studyObject(id: "item:note", title: "Note", kind: .standaloneNote, folders: ["folder:math"], tags: ["note"], resources: ["notes/note.md"])
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
        color: String? = nil
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
        modifiedAt: TimeInterval = 2_000
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
                businessModifiedAt: ts(modifiedAt)
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
