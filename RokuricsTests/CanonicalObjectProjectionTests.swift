//
//  CanonicalObjectProjectionTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalObjectProjectionTests {
    @Test func completedLedgerAloneDoesNotMakeAudioAvailableInProjection() {
        let manifest = manifest(recording: recording(audio: nil))
        let transfer = CanonicalTransferProjection(
            jobs: [
                CanonicalTransferStateMachine.job(
                    objectID: "recording-01",
                    kind: .recordingAudioUpload,
                    direction: .localToPeer,
                    legacyState: "completed",
                    source: "legacyLedger"
                )
            ]
        )
        let projection = CanonicalObjectProjectionBuilder.build(manifest: manifest, transferProjection: transfer)
        let recordingProjection = projection.recordings.first

        #expect(recordingProjection?.displayStates.contains(.waitingForAudio) == true)
        #expect(recordingProjection?.displayStates.contains(.audioAvailable) == false)
        #expect(recordingProjection?.actionAvailability.canUploadAudio == false)
    }

    @Test func generatedArtifactsConflictsDeletedFoldersAndStudyItemsProjectReadOnlyStates() {
        let recording = recording(
            audio: audioArtifact(),
            generated: [
                generatedArtifact(kind: .transcriptMarkdown),
                generatedArtifact(kind: .noteMarkdown),
                generatedArtifact(kind: .summaryJSON)
            ],
            isDeleted: true
        )
        let folder = folderObject(isDeleted: true)
        let item = studyObject()
        let manifest = CanonicalManifest.make(
            node: CanonicalNode(nodeID: "iphone-01", platform: "iPhone"),
            generatedAt: date(3_000),
            objects: [recording],
            libraryObjects: [folder, item],
            manifestCapabilities: [.canonicalObjectProjectionV1]
        )
        let applyPlan = CanonicalApplyPlan(
            trigger: .periodic,
            conflicts: [
                CanonicalConflictRecord(
                    kind: .recordingMetadataConcurrentEdit,
                    target: CanonicalApplyTarget(objectID: "recording-01"),
                    resolutionPolicy: .keepBothNoOverwrite
                )
            ]
        )
        let libraryPlan = CanonicalLibrarySyncPlan(
            conflicts: [
                CanonicalLibraryConflict(
                    kind: .studyItemMetadataConcurrentEdit,
                    objectID: CanonicalLibraryObjectID("item:note"),
                    objectKind: .standaloneNote
                )
            ]
        )
        let projection = CanonicalObjectProjectionBuilder.build(
            manifest: manifest,
            applyPlan: applyPlan,
            libraryPlan: libraryPlan
        )

        #expect(projection.recordings.first?.displayStates.contains(.audioAvailable) == true)
        #expect(projection.recordings.first?.displayStates.contains(.transcriptAvailable) == true)
        #expect(projection.recordings.first?.displayStates.contains(.noteAvailable) == true)
        #expect(projection.recordings.first?.displayStates.contains(.summaryAvailable) == true)
        #expect(projection.recordings.first?.displayStates.contains(.conflict) == true)
        #expect(projection.recordings.first?.displayStates.contains(.deleted) == true)
        #expect(projection.folders.first?.displayState == .tombstoned)
        #expect(projection.folders.first?.actionAvailability.canApplyMetadata == false)
        #expect(projection.studyItems.first?.displayState == .conflict)
        #expect(projection.studyItems.first?.actionAvailability.canResolveConflict == false)
    }

    private func manifest(recording: CanonicalRecordingObject) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(nodeID: "iphone-01", platform: "iPhone"),
            generatedAt: date(3_000),
            objects: [recording]
        )
    }

    private func recording(
        audio: CanonicalArtifact?,
        generated: [CanonicalArtifact] = [],
        isDeleted: Bool = false
    ) -> CanonicalRecordingObject {
        let metadata = CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: "Lecture",
            createdAt: ts(1_000),
            modifiedAt: ts(2_000),
            duration: 42,
            isDeleted: isDeleted,
            deletedAt: isDeleted ? ts(2_500) : nil
        )
        return CanonicalRecordingObject(
            objectID: metadata.objectID,
            nodeID: "iphone-01",
            metadata: metadata,
            artifacts: [audio].compactMap { $0 } + generated
        )
    }

    private func audioArtifact() -> CanonicalArtifact {
        CanonicalArtifactFact.audio(
            availability: .available,
            contentHash: CanonicalHash(String(repeating: "a", count: 64)),
            byteSize: 42,
            logicalName: "audio.m4a"
        ).makeArtifact(objectID: "recording-01")
    }

    private func generatedArtifact(kind: CanonicalArtifact.Kind) -> CanonicalArtifact {
        CanonicalProjectionContract.makeArtifact(
            objectID: "recording-01",
            kind: kind,
            availability: .available,
            contentHash: CanonicalHash(String(repeating: "b", count: 64)),
            byteSize: 120,
            logicalPathToken: "generated/recording-01/\(kind.rawValue).json",
            modifiedAt: ts(3_000),
            producedByNodeID: "mac-01",
            platform: "Mac"
        )
    }

    private func folderObject(isDeleted: Bool) -> CanonicalLibraryObject {
        let folder = CanonicalFolderObject(
            metadata: CanonicalFolderMetadata(
                folderID: CanonicalLibraryObjectID("folder:math"),
                name: "Math",
                isDeleted: isDeleted,
                deletedAt: isDeleted ? ts(2_500) : nil,
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
