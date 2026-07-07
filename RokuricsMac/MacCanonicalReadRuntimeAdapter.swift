//
//  MacCanonicalReadRuntimeAdapter.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/7.
//

import Foundation

protocol MacRecordingMetadataReadSideSeamReading: Sendable {
    nonisolated func read(
        legacyCanonicalManifest: CanonicalManifest?,
        canonicalManifest: CanonicalManifest?,
        peerCanonicalManifest: CanonicalManifest?,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate],
        syncRuntimeResult: CanonicalSyncRuntimeResult?,
        syncRunID: String?,
        canonicalReadFailureReason: String?
    ) -> CanonicalReadRuntimeResult
}

extension MacRecordingMetadataReadSideSeam: MacRecordingMetadataReadSideSeamReading {}

struct MacCanonicalReadRuntimeAdapter {
    var configuration: CanonicalReadRuntimeConfiguration
    var recordingMetadataReadSideSeam: any MacRecordingMetadataReadSideSeamReading

    nonisolated init(
        configuration: CanonicalReadRuntimeConfiguration = .disabled,
        recordingMetadataReadSideSeam: (any MacRecordingMetadataReadSideSeamReading)? = nil
    ) {
        self.configuration = configuration
        self.recordingMetadataReadSideSeam = recordingMetadataReadSideSeam
            ?? MacRecordingMetadataReadSideSeam(configuration: configuration)
    }

    nonisolated static func fromCanonicalKernelSwitch(
        _ result: CanonicalKernelSwitchResult = CanonicalKernelSwitchConfiguration.runtimeConfigurationFromStoredDefaults().resolve()
    ) -> MacCanonicalReadRuntimeAdapter {
        MacCanonicalReadRuntimeAdapter(configuration: result.effectiveConfiguration.readRuntimeConfiguration)
    }

    nonisolated func read(
        legacyManifest: StudyLibrarySyncManifest?,
        canonicalManifest: CanonicalManifest?,
        peerCanonicalManifest: CanonicalManifest? = nil,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = [],
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalReadRuntimeResult {
        let legacyCanonicalManifest = legacyManifest.map(Self.makeCanonicalManifest)
        return read(
            legacyCanonicalManifest: legacyCanonicalManifest,
            canonicalManifest: canonicalManifest,
            peerCanonicalManifest: peerCanonicalManifest,
            uploadCandidates: uploadCandidates,
            syncRuntimeResult: syncRuntimeResult,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
    }

    nonisolated func read(
        legacyInventory: LocalNetworkSyncInventory,
        canonicalManifest: CanonicalManifest? = nil,
        peerCanonicalManifest: CanonicalManifest? = nil,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = [],
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalReadRuntimeResult {
        let legacyManifest = legacyInventory.canonicalManifest
            ?? legacyInventory.studyManifest.map(Self.makeCanonicalManifest)
            ?? Self.makeCanonicalManifest(
                deviceID: legacyInventory.sourceDeviceID,
                generatedAt: legacyInventory.generatedAt,
                recordings: legacyInventory.recordings,
                libraryObjects: legacyInventory.studyManifest.map { MacCanonicalLibraryAdapter().makeLibraryObjects(from: $0) } ?? []
            )
        return read(
            legacyCanonicalManifest: legacyManifest,
            canonicalManifest: canonicalManifest ?? legacyInventory.canonicalManifest,
            peerCanonicalManifest: peerCanonicalManifest,
            uploadCandidates: uploadCandidates,
            syncRuntimeResult: syncRuntimeResult,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
    }

    nonisolated func read(
        legacyCanonicalManifest: CanonicalManifest?,
        canonicalManifest: CanonicalManifest?,
        peerCanonicalManifest: CanonicalManifest? = nil,
        uploadCandidates: [CanonicalAudioUploadCutoverCandidate] = [],
        syncRuntimeResult: CanonicalSyncRuntimeResult? = nil,
        syncRunID: String? = nil,
        canonicalReadFailureReason: String? = nil
    ) -> CanonicalReadRuntimeResult {
        recordingMetadataReadSideSeam.read(
            legacyCanonicalManifest: legacyCanonicalManifest,
            canonicalManifest: canonicalManifest,
            peerCanonicalManifest: peerCanonicalManifest,
            uploadCandidates: uploadCandidates,
            syncRuntimeResult: syncRuntimeResult,
            syncRunID: syncRunID,
            canonicalReadFailureReason: canonicalReadFailureReason
        )
    }

    nonisolated static func makeCanonicalManifest(_ manifest: StudyLibrarySyncManifest) -> CanonicalManifest {
        makeCanonicalManifest(
            deviceID: manifest.deviceID,
            generatedAt: manifest.generatedAt,
            recordings: manifest.recordings,
            libraryObjects: MacCanonicalLibraryAdapter().makeLibraryObjects(from: manifest)
        )
    }

    private nonisolated static func makeCanonicalManifest(
        deviceID: String,
        generatedAt: Date,
        recordings: [LocalNetworkSyncRecordingEntry],
        libraryObjects: [CanonicalLibraryObject]
    ) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(
                nodeID: deviceID,
                platform: "Mac",
                capabilities: [
                    .recordingMetadata,
                    .audioArtifact,
                    .objectProjection,
                    .canonicalLibraryObjectsV1
                ]
            ),
            generatedAt: generatedAt,
            objects: recordings.map(Self.makeRecordingObject),
            libraryObjects: libraryObjects,
            manifestCapabilities: [
                .recordingMetadata,
                .audioArtifact,
                .objectProjection,
                .canonicalLibraryObjectsV1
            ]
        )
    }

    private nonisolated static func makeRecordingObject(_ entry: LocalNetworkSyncRecordingEntry) -> CanonicalRecordingObject {
        let createdAt = CanonicalTimestamp(entry.createdAt ?? entry.updatedAt)
        let modifiedAt = CanonicalTimestamp(entry.updatedAt)
        let deleted = entry.deleted || entry.tombstone == true
        let metadata = CanonicalRecordingMetadata(
            objectID: entry.recordingID,
            title: entry.title ?? entry.recordingID,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            duration: nil,
            isDeleted: deleted,
            deletedAt: deleted ? modifiedAt : nil
        )
        return CanonicalRecordingObject(
            objectID: entry.recordingID,
            nodeID: entry.sourceDeviceID,
            metadata: metadata,
            artifacts: makeArtifacts(entry),
            syncState: deleted ? .deleted : .unknown,
            transferState: transferState(uploadStatus: entry.uploadStatus),
            processingState: processingState(transcriptionStatus: entry.transcriptionStatus, noteStatus: entry.noteStatus)
        )
    }

    private nonisolated static func makeArtifacts(_ entry: LocalNetworkSyncRecordingEntry) -> [CanonicalArtifact] {
        guard entry.audioAvailable || entry.audioAvailability != nil else {
            return []
        }
        let normalizedHash = entry.audioChecksum?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash: CanonicalHash?
        if let normalizedHash, !normalizedHash.isEmpty {
            hash = CanonicalHash(normalizedHash)
        } else {
            hash = nil
        }
        let availability: CanonicalArtifact.Availability
        if entry.audioAvailable, hash != nil, entry.audioSize != nil {
            availability = .available
        } else if entry.audioAvailable {
            availability = .availableWithoutHash
        } else {
            availability = .missing
        }
        return [
            CanonicalArtifact(
                artifactID: CanonicalProjectionContract.artifactID(objectID: entry.recordingID, kind: .audio),
                objectID: entry.recordingID,
                kind: .audio,
                availability: availability,
                contentHash: hash,
                byteSize: entry.audioSize,
                logicalName: nil,
                logicalPathToken: nil,
                modifiedAt: CanonicalTimestamp(entry.updatedAt),
                producedBy: .audioCapture,
                producedByNodeID: entry.sourceDeviceID,
                tombstone: entry.tombstone
            )
        ]
    }

    private nonisolated static func transferState(uploadStatus: String?) -> CanonicalTransferState {
        switch uploadStatus {
        case "uploaded":
            return .completed
        case "uploading":
            return .inFlight
        case "failed":
            return .failed
        case "retryPending":
            return .retryPending
        default:
            return .none
        }
    }

    private nonisolated static func processingState(
        transcriptionStatus: String?,
        noteStatus: String?
    ) -> CanonicalProcessingState {
        CanonicalProcessingState(
            transcription: processingStage(transcriptionStatus),
            note: processingStage(noteStatus)
        )
    }

    private nonisolated static func processingStage(_ value: String?) -> CanonicalProcessingState.Stage {
        switch value {
        case "completed":
            return .completed
        case "processing":
            return .processing
        case "failed":
            return .failed
        case "queued":
            return .queued
        case nil:
            return .unknown
        default:
            return .notStarted
        }
    }
}
