//
//  CanonicalInventoryBuilderContract.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct CanonicalInventoryUnsupportedObject: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID.rawValue }
    var objectID: CanonicalLibraryObjectID
    var objectKind: CanonicalObjectKind
    var reason: String
}

nonisolated struct CanonicalInventoryInputSnapshot: Codable, Equatable, Sendable {
    var node: CanonicalNode
    var generatedAt: CanonicalTimestamp
    var recordingObjects: [CanonicalRecordingObject]
    var libraryObjects: [CanonicalLibraryObject]
    var libraryTombstones: [CanonicalLibraryTombstone]
    var unsupportedObjects: [CanonicalInventoryUnsupportedObject]

    nonisolated init(
        node: CanonicalNode,
        generatedAt: Date = Date(),
        recordingObjects: [CanonicalRecordingObject] = [],
        libraryObjects: [CanonicalLibraryObject] = [],
        libraryTombstones: [CanonicalLibraryTombstone] = [],
        unsupportedObjects: [CanonicalInventoryUnsupportedObject] = []
    ) {
        self.node = node
        self.generatedAt = CanonicalTimestamp(generatedAt)
        self.recordingObjects = recordingObjects
        self.libraryObjects = libraryObjects
        self.libraryTombstones = libraryTombstones
        self.unsupportedObjects = unsupportedObjects
    }
}

nonisolated struct CanonicalInventoryCoverageReport: Codable, Equatable, Sendable {
    var recordingCoverage: Int
    var audioCoverage: Int
    var generatedArtifactCoverage: Int
    var folderCoverage: Int
    var studyItemCoverage: Int
    var tombstoneCoverage: Int
    var unsupportedLegacyObjectCount: Int
    var fallbackRequiredCount: Int
}

nonisolated struct CanonicalInventoryBuildDiagnostics: Codable, Equatable, Sendable {
    var phases: [String]
    var unsupportedReasons: [String]
}

nonisolated struct CanonicalInventoryBuildResult: Codable, Equatable, Sendable {
    var manifest: CanonicalManifest
    var coverage: CanonicalInventoryCoverageReport
    var diagnostics: CanonicalInventoryBuildDiagnostics
}

nonisolated struct CanonicalInventoryBuilderContract {
    nonisolated init() {}

    nonisolated func build(from snapshot: CanonicalInventoryInputSnapshot) -> CanonicalInventoryBuildResult {
        let folders = snapshot.libraryObjects.compactMap(\.folder)
        let studyItems = snapshot.libraryObjects.compactMap { object in
            object.studyItem ?? object.standaloneNote?.studyItem
        }
        let standaloneNotes = snapshot.libraryObjects.compactMap(\.standaloneNote)
        let generatedArtifactCount = snapshot.recordingObjects.reduce(0) { count, object in
            count + object.artifacts.filter { CanonicalProjectionContract.generatedArtifactKinds.contains($0.kind) }.count
        }
        let audioCoverage = snapshot.recordingObjects.filter(\.audioAvailable).count
        let fallbackCount = snapshot.unsupportedObjects.count
        let capabilities: [CanonicalCapability] = [
            .canonicalLibraryObjectsV1,
            .canonicalFolderObjectsV1,
            .canonicalStudyItemObjectsV1,
            .canonicalInventoryBuilderV1
        ]
        let manifest = CanonicalManifest.make(
            node: snapshot.node,
            generatedAt: snapshot.generatedAt.date,
            objects: snapshot.recordingObjects,
            libraryObjects: snapshot.libraryObjects,
            folders: folders,
            studyItems: studyItems,
            standaloneNotes: standaloneNotes,
            libraryTombstones: snapshot.libraryTombstones,
            manifestCapabilities: capabilities
        )
        let coverage = CanonicalInventoryCoverageReport(
            recordingCoverage: snapshot.recordingObjects.count,
            audioCoverage: audioCoverage,
            generatedArtifactCoverage: generatedArtifactCount,
            folderCoverage: folders.count,
            studyItemCoverage: studyItems.count,
            tombstoneCoverage: snapshot.libraryTombstones.count,
            unsupportedLegacyObjectCount: snapshot.unsupportedObjects.count,
            fallbackRequiredCount: fallbackCount
        )
        let diagnostics = CanonicalInventoryBuildDiagnostics(
            phases: [
                "canonicalInventoryCoverageReportWritten",
                "canonicalLibraryObjectsProjected"
            ],
            unsupportedReasons: snapshot.unsupportedObjects.map(\.reason).sorted()
        )
        return CanonicalInventoryBuildResult(manifest: manifest, coverage: coverage, diagnostics: diagnostics)
    }
}
