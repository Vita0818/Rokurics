//
//  IPhoneTombstoneConflictReadSideSeam.swift
//  Rokurics
//
//  Created by Codex on 2026/6/5.
//

import Foundation

struct IPhoneTombstoneConflictReadSideSeam {
    var configuration: CanonicalTombstoneConflictReadSideConfiguration

    init(configuration: CanonicalTombstoneConflictReadSideConfiguration = .disabled) {
        self.configuration = configuration
    }

    func evaluate(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory,
        applyPlan: CanonicalApplyPlan? = nil,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        trigger: CanonicalSyncPlanTrigger,
        syncRunID: String?
    ) -> CanonicalTombstoneConflictReadSideEvaluationResult {
        let legacySnapshot = legacySnapshot(localInventory: localInventory, peerInventory: peerInventory)
        let canonicalSnapshot = CanonicalTombstoneConflictReadProjection.snapshot(
            source: .canonical,
            localManifest: localInventory.canonicalManifest,
            peerManifest: peerInventory.canonicalManifest,
            applyPlan: applyPlan,
            libraryPlan: libraryPlan
        )
        return evaluate(
            legacySnapshot: legacySnapshot,
            canonicalSnapshot: canonicalSnapshot,
            trigger: trigger,
            syncRunID: syncRunID
        )
    }

    func evaluate(
        legacySnapshot: CanonicalTombstoneConflictReadSnapshot?,
        canonicalSnapshot: CanonicalTombstoneConflictReadSnapshot?,
        trigger: CanonicalSyncPlanTrigger,
        syncRunID: String?
    ) -> CanonicalTombstoneConflictReadSideEvaluationResult {
        CanonicalTombstoneConflictReadSideEvaluator().evaluate(
            configuration: configuration,
            legacySnapshot: legacySnapshot,
            canonicalSnapshot: canonicalSnapshot,
            trigger: trigger,
            nodeRole: .iPhone,
            syncRunID: syncRunID
        )
    }

    private func legacySnapshot(
        localInventory: LocalNetworkSyncInventory,
        peerInventory: LocalNetworkSyncInventory
    ) -> CanonicalTombstoneConflictReadSnapshot {
        CanonicalTombstoneConflictReadProjection.snapshot(
            source: .legacy,
            facts: legacyFacts(from: localInventory, peer: false) + legacyFacts(from: peerInventory, peer: true)
        )
    }

    private func legacyFacts(
        from inventory: LocalNetworkSyncInventory,
        peer: Bool
    ) -> [CanonicalTombstoneConflictReadProjectionFact] {
        inventory.objects.map { entry in
            let tombstoned = entry.deleted || entry.tombstone == true
            let conflictStatus = Self.conflictStatus(from: entry.conflictStatus)
            return CanonicalTombstoneConflictReadProjectionFact(
                objectID: entry.ownerID ?? entry.objectID,
                objectKind: Self.objectKind(from: entry.objectKind),
                tombstoneState: tombstoned ? .tombstoned : .active,
                deletedDisplayState: Self.deletedDisplayState(deleted: entry.deleted, tombstone: entry.tombstone),
                tombstoneTimestamp: tombstoned ? CanonicalTimestamp(entry.updatedAt) : nil,
                conflictKind: conflictStatus == .none ? nil : entry.conflictStatus,
                conflictStatus: conflictStatus,
                activeVsTombstoneState: Self.activeVsTombstoneState(tombstoned: tombstoned, conflictStatus: conflictStatus, peer: peer),
                antiResurrectionStatus: tombstoned ? .blocked : .notTriggered,
                parentObjectTombstoned: false,
                generatedArtifactResurrectionBlocked: tombstoned && Self.objectKind(from: entry.objectKind) == .generatedArtifactEnvelope,
                softDeleteMarkerPresent: tombstoned,
                hashPrefix: entry.sha256,
                pathLeakRisk: entry.logicalPathToken.map { CanonicalProjectionContract.safeLogicalPathToken($0) == nil } ?? false,
                fullMetadataIncluded: false,
                fullContentIncluded: false,
                physicalDeleteRisk: false,
                permanentDeleteRisk: false,
                tombstoneGCRisk: false,
                staleLiveResurrectionRisk: false,
                autoConflictResolutionRisk: false
            )
        }
    }

    private static func objectKind(from kind: LocalNetworkSyncObjectKind) -> CanonicalObjectKind {
        switch kind {
        case .recordingAudio, .recordingMetadata, .receiveRecord:
            return .recording
        case .transcriptMarkdown, .transcriptJSON, .noteMarkdown, .noteJSON, .summaryMarkdown, .summaryJSON:
            return .generatedArtifactEnvelope
        case .studyItem:
            return .standaloneStudyItem
        case .studyFolder:
            return .folder
        }
    }

    private static func deletedDisplayState(
        deleted: Bool,
        tombstone: Bool?
    ) -> CanonicalTombstoneConflictDeletedDisplayState {
        if tombstone == true {
            return .tombstoned
        }
        return deleted ? .deleted : .active
    }

    private static func conflictStatus(from value: String?) -> CanonicalTombstoneConflictStatus {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let normalized, !normalized.isEmpty else {
            return .none
        }
        if normalized.contains("manual") {
            return .manualReviewRequired
        }
        if normalized.contains("resolved") {
            return .recorded
        }
        return .unresolved
    }

    private static func activeVsTombstoneState(
        tombstoned: Bool,
        conflictStatus: CanonicalTombstoneConflictStatus,
        peer: Bool
    ) -> String {
        if tombstoned {
            return peer ? "peerTombstone" : "localTombstone"
        }
        if conflictStatus != .none {
            return "conflict"
        }
        return "activeOnly"
    }
}
