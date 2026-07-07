//
//  CanonicalEffectiveSyncStatusProjection.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalEffectiveSyncStatusProjection {
    nonisolated static func project(
        objectID: CanonicalObjectID,
        domain: CanonicalStatusDomain,
        phase: CanonicalStatusPhase,
        proof: CanonicalStatusProof? = nil,
        facts: [CanonicalStatusFact],
        now: CanonicalTimestamp,
        blocker: CanonicalStatusBlocker? = nil,
        canCreateUploadJob: Bool = false,
        canDisplayAsComplete: Bool = false,
        canSuppressLegacyDuplicate: Bool = false
    ) -> CanonicalEffectiveSyncStatus {
        CanonicalEffectiveSyncStatus(
            objectID: objectID,
            domain: domain,
            phase: phase,
            displayState: displayState(for: phase),
            proof: proof,
            sourceSummary: facts.map {
                CanonicalStatusSourceSummary(
                    source: $0.source,
                    factID: $0.factID,
                    phase: $0.phase,
                    stale: $0.isStale(now: now)
                )
            },
            canDisplayAsComplete: canDisplayAsComplete,
            canCreateUploadJob: canCreateUploadJob,
            canSuppressLegacyDuplicate: canSuppressLegacyDuplicate,
            blocker: blocker
        )
    }

    nonisolated static func displayState(for phase: CanonicalStatusPhase) -> CanonicalStatusDisplayState {
        switch phase {
        case .absent:
            return .hidden
        case .localOnly, .peerUnknown, .metadataOnly, .peerKnownMetadataOnly, .deferred:
            return .waiting
        case .uploadNeeded:
            return .uploadNeeded
        case .uploading:
            return .uploading
        case .partialReceive:
            return .uploading
        case .finalizing, .finalizedLocally:
            return .finalizing
        case .peerVerified, .completed:
            return .complete
        case .blocked:
            return .blocked
        case .conflict:
            return .conflict
        case .stale:
            return .stale
        }
    }
}
