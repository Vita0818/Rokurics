//
//  CanonicalObjectProjection.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalDisplayState: String, Codable, Equatable, Sendable {
    case localOnly
    case waitingForAudio
    case uploadingAudio
    case audioAvailable
    case metadataSynced
    case transcriptAvailable
    case noteAvailable
    case summaryAvailable
    case processing
    case failed
    case retryPending
    case conflict
    case deleted
    case tombstoned
    case available
    case syncing
    case unsupported
    case unknown
}

nonisolated struct CanonicalActionAvailability: Codable, Equatable, Sendable {
    var canUploadAudio: Bool
    var canRequestGeneratedArtifact: Bool
    var canApplyMetadata: Bool
    var canResolveConflict: Bool

    nonisolated static let readOnly = CanonicalActionAvailability(
        canUploadAudio: false,
        canRequestGeneratedArtifact: false,
        canApplyMetadata: false,
        canResolveConflict: false
    )
}

nonisolated struct CanonicalRecordingProjection: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID }
    var objectID: String
    var title: String
    var displayStates: [CanonicalDisplayState]
    var actionAvailability: CanonicalActionAvailability
    var metadataHashPrefix: String?
    var audioHashPrefix: String?
}

nonisolated struct CanonicalFolderProjection: Codable, Equatable, Identifiable, Sendable {
    var id: String { folderID.rawValue }
    var folderID: CanonicalLibraryObjectID
    var title: String
    var displayState: CanonicalDisplayState
    var actionAvailability: CanonicalActionAvailability
}

nonisolated struct CanonicalStudyItemProjection: Codable, Equatable, Identifiable, Sendable {
    var id: String { itemID.rawValue }
    var itemID: CanonicalLibraryObjectID
    var title: String
    var displayState: CanonicalDisplayState
    var actionAvailability: CanonicalActionAvailability
}

nonisolated struct CanonicalLibraryProjection: Codable, Equatable, Sendable {
    var recordings: [CanonicalRecordingProjection]
    var folders: [CanonicalFolderProjection]
    var studyItems: [CanonicalStudyItemProjection]
    var builtAt: CanonicalTimestamp
}

nonisolated enum CanonicalObjectProjectionBuilder {
    nonisolated static func build(
        manifest: CanonicalManifest,
        applyPlan: CanonicalApplyPlan? = nil,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        transferProjection: CanonicalTransferProjection? = nil,
        builtAt: Date = Date()
    ) -> CanonicalLibraryProjection {
        let conflicts = Set((applyPlan?.conflicts ?? []).map { $0.target.objectID })
        let libraryConflicts = Set((libraryPlan?.conflicts ?? []).map { $0.objectID.rawValue })
        let transferByObject = Dictionary(grouping: transferProjection?.jobs ?? [], by: \.objectID)

        return CanonicalLibraryProjection(
            recordings: manifest.objects.map { object in
                recordingProjection(object, conflicts: conflicts, transferJobs: transferByObject[object.objectID] ?? [])
            }.sorted { $0.objectID < $1.objectID },
            folders: manifest.libraryObjects.compactMap { object in
                guard object.kind == .folder, let folder = object.folder else {
                    return nil
                }
                return folderProjection(folder, hasConflict: libraryConflicts.contains(object.objectID.rawValue))
            }.sorted { $0.folderID.rawValue < $1.folderID.rawValue },
            studyItems: manifest.libraryObjects.compactMap { object in
                guard object.kind == .standaloneStudyItem || object.kind == .standaloneNote || object.kind == .recordingAssociatedStudyItem,
                      let item = object.studyItem ?? object.standaloneNote?.studyItem else {
                    return nil
                }
                return studyItemProjection(item, hasConflict: libraryConflicts.contains(object.objectID.rawValue))
            }.sorted { $0.itemID.rawValue < $1.itemID.rawValue },
            builtAt: CanonicalTimestamp(builtAt)
        )
    }

    nonisolated private static func recordingProjection(
        _ object: CanonicalRecordingObject,
        conflicts: Set<String>,
        transferJobs: [CanonicalTransferJob]
    ) -> CanonicalRecordingProjection {
        var states: [CanonicalDisplayState] = []
        if object.metadata.isDeleted {
            states.append(.deleted)
        }
        if conflicts.contains(object.objectID) || object.syncState == .conflict {
            states.append(.conflict)
        }
        if transferJobs.contains(where: { $0.phase == .inFlight || $0.phase == .queued || $0.phase == .planned }) {
            states.append(.uploadingAudio)
        }
        if transferJobs.contains(where: { $0.phase == .failedRetryable }) {
            states.append(.retryPending)
        }
        if transferJobs.contains(where: { $0.phase == .failedFatal }) {
            states.append(.failed)
        }
        if object.audioAvailable {
            states.append(.audioAvailable)
        } else if object.metadata.isDeleted == false {
            states.append(.waitingForAudio)
        }
        if generatedAvailable(object, kind: .transcriptMarkdown) || generatedAvailable(object, kind: .transcriptJSON) {
            states.append(.transcriptAvailable)
        }
        if generatedAvailable(object, kind: .noteMarkdown) || generatedAvailable(object, kind: .noteJSON) {
            states.append(.noteAvailable)
        }
        if generatedAvailable(object, kind: .summaryJSON) {
            states.append(.summaryAvailable)
        }
        if states.isEmpty {
            states.append(.metadataSynced)
        }
        let audio = object.audioArtifact
        return CanonicalRecordingProjection(
            objectID: object.objectID,
            title: object.metadata.title,
            displayStates: unique(states),
            actionAvailability: .readOnly,
            metadataHashPrefix: String(object.metadataHash.value.prefix(12)),
            audioHashPrefix: audio?.contentHash.map { String($0.value.prefix(12)) }
        )
    }

    nonisolated private static func folderProjection(
        _ folder: CanonicalFolderObject,
        hasConflict: Bool
    ) -> CanonicalFolderProjection {
        CanonicalFolderProjection(
            folderID: folder.folderID,
            title: folder.metadata.name,
            displayState: displayState(isDeleted: folder.metadata.isDeleted, hasConflict: hasConflict),
            actionAvailability: .readOnly
        )
    }

    nonisolated private static func studyItemProjection(
        _ item: CanonicalStudyItemObject,
        hasConflict: Bool
    ) -> CanonicalStudyItemProjection {
        CanonicalStudyItemProjection(
            itemID: item.itemID,
            title: item.metadata.title,
            displayState: displayState(isDeleted: item.metadata.isDeleted, hasConflict: hasConflict),
            actionAvailability: .readOnly
        )
    }

    nonisolated private static func displayState(isDeleted: Bool, hasConflict: Bool) -> CanonicalDisplayState {
        if isDeleted {
            return .tombstoned
        }
        if hasConflict {
            return .conflict
        }
        return .available
    }

    nonisolated private static func generatedAvailable(_ object: CanonicalRecordingObject, kind: CanonicalArtifact.Kind) -> Bool {
        object.artifacts.contains { $0.kind == kind && $0.provesCanonicalGeneratedArtifactAvailability }
    }

    nonisolated private static func unique(_ states: [CanonicalDisplayState]) -> [CanonicalDisplayState] {
        var seen = Set<CanonicalDisplayState>()
        return states.filter { seen.insert($0).inserted }
    }
}
