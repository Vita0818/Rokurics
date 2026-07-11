//
//  IPhoneCanonicalRecordingAdapter.swift
//  Rokurics
//
//  Created by Codex on 2026/6/1.
//

import Foundation

struct IPhoneCanonicalRecordingAdapter {
    func makeObject(
        metadata: RecordingMetadata,
        studyItem: StudyItemMetadata? = nil,
        audioFact: CanonicalArtifactFact? = nil,
        artifactFacts: [CanonicalArtifact] = [],
        nodeID: String? = nil
    ) -> CanonicalRecordingObject {
        let isDeleted = studyItem?.isTrashed ?? metadata.isDeleted
        let deletedAt = studyItem?.trashedAt ?? metadata.deletedAt
        let canonicalMetadata = CanonicalRecordingMetadata(
            objectID: metadata.id,
            title: studyItem?.title ?? metadata.title,
            createdAt: CanonicalTimestamp(metadata.createdAt),
            modifiedAt: CanonicalTimestamp(
                isDeleted
                    ? (deletedAt ?? studyItem?.updatedAt ?? metadata.createdAt)
                    : (studyItem?.updatedAt ?? metadata.createdAt)
            ),
            duration: metadata.duration,
            filing: CanonicalRecordingMetadata.Filing(studyItem?.studyFiling ?? metadata.studyFiling),
            tags: studyItem?.tags.map(\.displayTitle) ?? metadata.tags,
            isDeleted: isDeleted,
            deletedAt: isDeleted ? deletedAt.map(CanonicalTimestamp.init) : nil
        )
        var artifacts = artifactFacts.filter { $0.objectID == canonicalMetadata.objectID }
        if let audioFact {
            artifacts.append(audioFact.makeArtifact(objectID: canonicalMetadata.objectID, producedByNodeID: nodeID))
        }

        return CanonicalRecordingObject(
            objectID: canonicalMetadata.objectID,
            nodeID: nodeID,
            metadata: canonicalMetadata,
            artifacts: artifacts,
            syncState: isDeleted ? .deleted : .localOnly,
            transferState: .none,
            processingState: CanonicalProcessingState(
                transcription: Self.processingStage(metadata.transcriptionStatus),
                note: Self.processingStage(metadata.noteStatus)
            )
        )
    }

    func makeManifest(
        recordings: [RecordingMetadata],
        audioFactsByRecordingID: [String: CanonicalArtifactFact],
        artifactFactsByRecordingID: [String: [CanonicalArtifact]] = [:],
        libraryObjects: [CanonicalLibraryObject] = [],
        libraryTombstones: [CanonicalLibraryTombstone] = [],
        manifestCapabilities: [CanonicalCapability] = [],
        node: CanonicalNode,
        generatedAt: Date = Date()
    ) -> CanonicalManifest {
        let objects = makeObjects(
            recordings: recordings,
            audioFactsByRecordingID: audioFactsByRecordingID,
            artifactFactsByRecordingID: artifactFactsByRecordingID,
            nodeID: node.nodeID
        )
        return CanonicalManifest.make(
            node: node,
            generatedAt: generatedAt,
            objects: objects,
            libraryObjects: libraryObjects,
            libraryTombstones: libraryTombstones,
            manifestCapabilities: manifestCapabilities
        )
    }

    func makeObjects(
        recordings: [RecordingMetadata],
        studyItemsByRecordingID: [String: StudyItemMetadata] = [:],
        audioFactsByRecordingID: [String: CanonicalArtifactFact],
        artifactFactsByRecordingID: [String: [CanonicalArtifact]] = [:],
        nodeID: String? = nil
    ) -> [CanonicalRecordingObject] {
        recordings.map { metadata in
            makeObject(
                metadata: metadata,
                studyItem: studyItemsByRecordingID[metadata.id],
                audioFact: audioFactsByRecordingID[metadata.id],
                artifactFacts: artifactFactsByRecordingID[metadata.id] ?? [],
                nodeID: nodeID
            )
        }
    }

    private static func processingStage(_ status: String) -> CanonicalProcessingState.Stage {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "queued":
            return .queued
        case "transcribing", "generating", "processing":
            return .processing
        case "transcribed", "generated", "completed":
            return .completed
        case "failed":
            return .failed
        case "notStarted", "notGenerated", "":
            return .notStarted
        default:
            return .unknown
        }
    }
}

private extension CanonicalRecordingMetadata.Filing {
    init?(_ filing: StudyFilingPath?) {
        guard let filing, !filing.isEmpty else {
            return nil
        }
        self.init(
            type: filing.type,
            subject: filing.subject,
            chapter: filing.chapter,
            topic: filing.topic
        )
    }
}
