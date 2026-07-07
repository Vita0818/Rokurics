//
//  IPhoneCanonicalProductionSnapshotAdapter.swift
//  Rokurics
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct IPhoneCanonicalProductionSnapshotInput: Sendable {
    var node: CanonicalNode
    var recordingObjects: [CanonicalRecordingObject]
    var libraryObjects: [CanonicalLibraryObject]
    var libraryTombstones: [CanonicalLibraryTombstone]
    var transferProjection: CanonicalTransferProjection
    var unsupportedObjects: [CanonicalInventoryUnsupportedObject]
    var unsupportedFacts: [CanonicalProductionUnsupportedFact]
    var legacyActions: CanonicalLegacyActionSnapshot
    var generatedAt: Date

    nonisolated init(
        node: CanonicalNode,
        recordingObjects: [CanonicalRecordingObject] = [],
        libraryObjects: [CanonicalLibraryObject] = [],
        libraryTombstones: [CanonicalLibraryTombstone] = [],
        transferProjection: CanonicalTransferProjection = CanonicalTransferProjection(),
        unsupportedObjects: [CanonicalInventoryUnsupportedObject] = [],
        unsupportedFacts: [CanonicalProductionUnsupportedFact] = [],
        legacyActions: CanonicalLegacyActionSnapshot = .empty,
        generatedAt: Date = Date()
    ) {
        self.node = node
        self.recordingObjects = recordingObjects
        self.libraryObjects = libraryObjects
        self.libraryTombstones = libraryTombstones
        self.transferProjection = transferProjection
        self.unsupportedObjects = unsupportedObjects
        self.unsupportedFacts = unsupportedFacts
        self.legacyActions = legacyActions
        self.generatedAt = generatedAt
    }
}

nonisolated struct IPhoneCanonicalProductionSnapshotAdapter {
    nonisolated init() {}

    nonisolated func buildSnapshot(from input: IPhoneCanonicalProductionSnapshotInput) -> CanonicalProductionSnapshot {
        let inventory = CanonicalInventoryBuilderContract().build(
            from: CanonicalInventoryInputSnapshot(
                node: input.node,
                generatedAt: input.generatedAt,
                recordingObjects: input.recordingObjects,
                libraryObjects: input.libraryObjects,
                libraryTombstones: input.libraryTombstones,
                unsupportedObjects: input.unsupportedObjects
            )
        )
        let projection = CanonicalObjectProjectionBuilder.build(
            manifest: inventory.manifest,
            transferProjection: input.transferProjection,
            builtAt: input.generatedAt
        )
        let retirement = CanonicalRetirementReadinessEvaluator().evaluate(
            manifest: inventory.manifest,
            libraryPlan: nil,
            applyPlan: nil,
            transferProjection: input.transferProjection,
            inventoryCoverage: inventory.coverage,
            fallbackUsed: !input.unsupportedObjects.isEmpty || !input.unsupportedFacts.isEmpty,
            generatedAt: input.generatedAt
        )
        let unsupportedFacts = input.unsupportedFacts + input.unsupportedObjects.map {
            CanonicalProductionUnsupportedFact(
                objectID: $0.objectID.rawValue,
                domain: .inventory,
                reason: $0.reason
            )
        }
        let diagnostics = [
            CanonicalProductionDiagnosticsEvent(
                kind: .canonicalProductionSnapshotBuilt,
                domain: .inventory,
                action: "iPhoneSnapshotAdapter",
                reason: "readOnlySnapshotFacts",
                hash: inventory.manifest.manifestHash,
                generatedAt: input.generatedAt
            )
        ]
        let nodeState = CanonicalRuntimeNodeState(
            node: input.node,
            manifest: inventory.manifest,
            transferProjection: input.transferProjection,
            inventoryCoverage: inventory.coverage,
            retirementReadiness: retirement,
            objectProjection: projection,
            unsupportedFacts: unsupportedFacts,
            diagnostics: diagnostics
        )
        return CanonicalProductionSnapshot(
            node: input.node,
            manifest: inventory.manifest,
            runtimeNodeState: nodeState,
            legacyActions: input.legacyActions,
            unsupportedFacts: unsupportedFacts,
            diagnostics: diagnostics
        )
    }
}
