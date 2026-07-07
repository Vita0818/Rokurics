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
        audioFact: CanonicalArtifactFact? = nil,
        artifactFacts: [CanonicalArtifact] = [],
        nodeID: String? = nil
    ) -> CanonicalRecordingObject {
        let canonicalMetadata = CanonicalRecordingMetadata(
            objectID: metadata.id,
            title: metadata.title,
            createdAt: CanonicalTimestamp(metadata.createdAt),
            modifiedAt: CanonicalTimestamp(metadata.isDeleted ? (metadata.deletedAt ?? metadata.createdAt) : metadata.createdAt),
            duration: metadata.duration,
            filing: CanonicalRecordingMetadata.Filing(metadata.studyFiling),
            tags: metadata.tags,
            isDeleted: metadata.isDeleted,
            deletedAt: metadata.isDeleted ? metadata.deletedAt.map(CanonicalTimestamp.init) : nil
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
            syncState: metadata.isDeleted ? .deleted : .localOnly,
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
        audioFactsByRecordingID: [String: CanonicalArtifactFact],
        artifactFactsByRecordingID: [String: [CanonicalArtifact]] = [:],
        nodeID: String? = nil
    ) -> [CanonicalRecordingObject] {
        recordings.map { metadata in
            makeObject(
                metadata: metadata,
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
