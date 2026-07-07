//
//  CanonicalEffectiveStatusUIProjection.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalDisplaySyncStateKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case hidden
    case deferred
    case uploadNeeded
    case uploading
    case finalizing
    case peerVerified
    case completed
    case blocked
    case conflict
    case failed
    case stale
}

nonisolated struct CanonicalDisplaySyncState: Codable, Equatable, Hashable, Sendable {
    var kind: CanonicalDisplaySyncStateKind
    var effectiveStatus: CanonicalEffectiveSyncStatus
    var canDisplayAsComplete: Bool
    var canCreateUploadJob: Bool
    var canSuppressLegacyDuplicate: Bool
    var blocker: CanonicalStatusBlocker?

    nonisolated init(
        kind: CanonicalDisplaySyncStateKind,
        effectiveStatus: CanonicalEffectiveSyncStatus,
        canDisplayAsComplete: Bool? = nil,
        canCreateUploadJob: Bool? = nil,
        canSuppressLegacyDuplicate: Bool? = nil,
        blocker: CanonicalStatusBlocker? = nil
    ) {
        self.kind = kind
        self.effectiveStatus = effectiveStatus
        self.canDisplayAsComplete = canDisplayAsComplete ?? (kind == .completed || kind == .peerVerified)
        self.canCreateUploadJob = canCreateUploadJob ?? effectiveStatus.canCreateUploadJob
        self.canSuppressLegacyDuplicate = canSuppressLegacyDuplicate ?? effectiveStatus.canSuppressLegacyDuplicate
        self.blocker = blocker ?? effectiveStatus.blocker
    }

    nonisolated var isTerminalComplete: Bool {
        kind == .completed || kind == .peerVerified
    }

    nonisolated var isBlocked: Bool {
        kind == .blocked || kind == .conflict
    }
}

nonisolated enum CanonicalEffectiveStatusUIProjection {
    nonisolated static func project(_ status: CanonicalEffectiveSyncStatus) -> CanonicalDisplaySyncState {
        let hasCompletionProof = hasAcceptedCompletionProof(status.proof)
        let canDisplayComplete = status.canDisplayAsComplete && hasCompletionProof

        switch status.displayState {
        case .hidden:
            return CanonicalDisplaySyncState(kind: .hidden, effectiveStatus: status, canDisplayAsComplete: false)
        case .waiting:
            return CanonicalDisplaySyncState(kind: .deferred, effectiveStatus: status, canDisplayAsComplete: false)
        case .uploadNeeded:
            return CanonicalDisplaySyncState(kind: .uploadNeeded, effectiveStatus: status, canDisplayAsComplete: false)
        case .uploading:
            return CanonicalDisplaySyncState(kind: .uploading, effectiveStatus: status, canDisplayAsComplete: false)
        case .finalizing:
            return CanonicalDisplaySyncState(kind: .finalizing, effectiveStatus: status, canDisplayAsComplete: false)
        case .complete:
            guard canDisplayComplete else {
                return CanonicalDisplaySyncState(
                    kind: .deferred,
                    effectiveStatus: status,
                    canDisplayAsComplete: false,
                    canSuppressLegacyDuplicate: false,
                    blocker: status.blocker ?? .peerProofUnavailable
                )
            }
            let kind: CanonicalDisplaySyncStateKind = status.phase == .completed ? .completed : .peerVerified
            return CanonicalDisplaySyncState(
                kind: kind,
                effectiveStatus: status,
                canDisplayAsComplete: true,
                canCreateUploadJob: false,
                canSuppressLegacyDuplicate: true
            )
        case .conflict:
            return CanonicalDisplaySyncState(kind: .conflict, effectiveStatus: status, canDisplayAsComplete: false)
        case .blocked:
            return CanonicalDisplaySyncState(kind: .blocked, effectiveStatus: status, canDisplayAsComplete: false)
        case .stale:
            return CanonicalDisplaySyncState(kind: .stale, effectiveStatus: status, canDisplayAsComplete: false)
        }
    }

    nonisolated static func hasAcceptedCompletionProof(_ proof: CanonicalStatusProof?) -> Bool {
        guard let proof else {
            return false
        }
        switch proof.kind {
        case .finalizeProof:
            return proof.hasAcceptedFinalizeProof
        case .peerInventoryHashSizeMatch, .peerHashSize, .sameHashAndByteSize:
            return proof.hasHashSizeProof
        case .dualAckProofChain:
            return proof.hasDualAckProofChain
        default:
            return false
        }
    }
}

nonisolated struct LegacySyncStatusSnapshot: Codable, Equatable, Hashable, Sendable {
    var objectID: CanonicalObjectID
    var domain: CanonicalStatusDomain
    var nodeID: CanonicalNodeID
    var localAudioHash: CanonicalHash?
    var localAudioByteSize: Int64?
    var legacyCompletedLedger: Bool
    var legacyMetadataOnly: Bool
    var legacyReceiveRecordOnly: Bool
    var legacyPartialReceive: Bool
    var peerUnknown: Bool
    var peerInventoryHash: CanonicalHash?
    var peerInventoryByteSize: Int64?
    var finalizeProof: CanonicalTransferFinalizeProof?
    var uploading: Bool
    var finalizing: Bool
    var failed: Bool
    var conflict: Bool
    var viewRefresh: Bool
    var retryDrainer: Bool
    var existingEligibleRetry: Bool

    nonisolated init(
        objectID: CanonicalObjectID,
        domain: CanonicalStatusDomain = .audioUpload,
        nodeID: CanonicalNodeID = CanonicalNodeID("legacy-adapter"),
        localAudioHash: CanonicalHash? = nil,
        localAudioByteSize: Int64? = nil,
        legacyCompletedLedger: Bool = false,
        legacyMetadataOnly: Bool = false,
        legacyReceiveRecordOnly: Bool = false,
        legacyPartialReceive: Bool = false,
        peerUnknown: Bool = false,
        peerInventoryHash: CanonicalHash? = nil,
        peerInventoryByteSize: Int64? = nil,
        finalizeProof: CanonicalTransferFinalizeProof? = nil,
        uploading: Bool = false,
        finalizing: Bool = false,
        failed: Bool = false,
        conflict: Bool = false,
        viewRefresh: Bool = false,
        retryDrainer: Bool = false,
        existingEligibleRetry: Bool = false
    ) {
        self.objectID = objectID
        self.domain = domain
        self.nodeID = nodeID
        self.localAudioHash = localAudioHash
        self.localAudioByteSize = localAudioByteSize.map { max(0, $0) }
        self.legacyCompletedLedger = legacyCompletedLedger
        self.legacyMetadataOnly = legacyMetadataOnly
        self.legacyReceiveRecordOnly = legacyReceiveRecordOnly
        self.legacyPartialReceive = legacyPartialReceive
        self.peerUnknown = peerUnknown
        self.peerInventoryHash = peerInventoryHash
        self.peerInventoryByteSize = peerInventoryByteSize.map { max(0, $0) }
        self.finalizeProof = finalizeProof
        self.uploading = uploading
        self.finalizing = finalizing
        self.failed = failed
        self.conflict = conflict
        self.viewRefresh = viewRefresh
        self.retryDrainer = retryDrainer
        self.existingEligibleRetry = existingEligibleRetry
    }
}

nonisolated enum LegacySyncStatusToCanonicalEffectiveStatusAdapter {
    nonisolated static func effectiveStatus(
        for snapshot: LegacySyncStatusSnapshot,
        now: CanonicalTimestamp = CanonicalTimestamp(Date())
    ) -> CanonicalEffectiveSyncStatus {
        CanonicalStatusReconciliationRuntime.reconcile(
            facts: facts(for: snapshot, now: now),
            now: now
        ).reconciliation.effectiveStatus
    }

    nonisolated static func displayState(
        for snapshot: LegacySyncStatusSnapshot,
        now: CanonicalTimestamp = CanonicalTimestamp(Date())
    ) -> CanonicalDisplaySyncState {
        let status = effectiveStatus(for: snapshot, now: now)
        if snapshot.conflict {
            return CanonicalDisplaySyncState(kind: .conflict, effectiveStatus: status, canDisplayAsComplete: false)
        }
        if snapshot.failed {
            return CanonicalDisplaySyncState(kind: .failed, effectiveStatus: status, canDisplayAsComplete: false)
        }
        return CanonicalEffectiveStatusUIProjection.project(status)
    }

    nonisolated static func displayState(
        for status: CanonicalEffectiveSyncStatus
    ) -> CanonicalDisplaySyncState {
        CanonicalEffectiveStatusUIProjection.project(status)
    }

    nonisolated static func iPhoneUploadSnapshot(
        recordingID: String,
        localAudioHash: String? = nil,
        localAudioByteSize: Int64? = nil,
        provenUploadHash: String? = nil,
        provenUploadByteSize: Int64? = nil,
        legacyStatus: String? = nil,
        legacyPhase: String? = nil,
        activeUploadInFlight: Bool = false,
        activeFailure: Bool = false,
        viewRefresh: Bool = false
    ) -> LegacySyncStatusSnapshot {
        let normalizedStatus = normalized(legacyStatus)
        let normalizedPhase = normalized(legacyPhase)
        let objectID = CanonicalObjectID("recordingAudio:\(recordingID)")
        let hasLocalAudio = localAudioByteSize.map { $0 > 0 } == true
        let uploadProofHash = normalizedHash(provenUploadHash)
        let uploadProofSize = provenUploadByteSize.flatMap { $0 > 0 ? $0 : nil }

        let finalProof: CanonicalTransferFinalizeProof? = uploadProofHash.flatMap { hash in
            guard let uploadProofSize else {
                return nil
            }
            return CanonicalTransferFinalizeProof(
                sessionID: CanonicalTransferSessionID("legacy-upload-\(recordingID)"),
                objectID: objectID,
                receiverNodeID: CanonicalNodeID("mac-peer"),
                contentHash: hash,
                byteSize: uploadProofSize,
                acceptedAt: CanonicalTimestamp(Date()),
                verified: true
            )
        }

        return LegacySyncStatusSnapshot(
            objectID: objectID,
            nodeID: CanonicalNodeID("iphone"),
            localAudioHash: normalizedHash(localAudioHash),
            localAudioByteSize: hasLocalAudio ? localAudioByteSize : nil,
            legacyCompletedLedger: normalizedStatus == "uploaded" && finalProof == nil,
            peerUnknown: normalizedStatus == nil || normalizedStatus == "localonly",
            finalizeProof: finalProof,
            uploading: activeUploadInFlight || normalizedStatus == "uploading" || containsAny(normalizedPhase, ["uploading", "preparing", "starting", "metadata"]),
            finalizing: containsAny(normalizedPhase, ["finalizing", "completed"]),
            failed: activeFailure || normalizedStatus == "failed",
            conflict: containsAny(normalizedPhase, ["conflict"]),
            viewRefresh: viewRefresh
        )
    }

    nonisolated static func macAudioSnapshot(
        recordingID: String,
        hasLocalAudio: Bool,
        audioChecksum: String?,
        audioByteSize: Int64,
        receiveStatus: String?,
        transferVisible: Bool = false
    ) -> LegacySyncStatusSnapshot {
        let normalizedReceiveStatus = normalized(receiveStatus)
        let peerProofHash = hasLocalAudio ? normalizedHash(audioChecksum) : nil
        let peerProofSize = hasLocalAudio && audioByteSize > 0 ? audioByteSize : nil

        return LegacySyncStatusSnapshot(
            objectID: CanonicalObjectID("recordingAudio:\(recordingID)"),
            nodeID: CanonicalNodeID("mac"),
            legacyMetadataOnly: !hasLocalAudio && normalizedReceiveStatus != "failed" && !transferVisible,
            legacyReceiveRecordOnly: normalizedReceiveStatus == "completed" && peerProofHash == nil,
            legacyPartialReceive: transferVisible || (normalizedReceiveStatus != nil && normalizedReceiveStatus != "completed" && normalizedReceiveStatus != "failed"),
            peerInventoryHash: peerProofHash,
            peerInventoryByteSize: peerProofSize,
            failed: normalizedReceiveStatus == "failed"
        )
    }

    nonisolated static func facts(
        for snapshot: LegacySyncStatusSnapshot,
        now: CanonicalTimestamp = CanonicalTimestamp(Date())
    ) -> [CanonicalStatusFact] {
        var facts: [CanonicalStatusFact] = []
        var counter: UInt64 = 1

        func append(
            id: String,
            source: CanonicalStatusSource,
            kind: CanonicalStatusProofKind,
            phase: CanonicalStatusPhase? = nil,
            hash: CanonicalHash? = nil,
            byteSize: Int64? = nil,
            finalizeProof: CanonicalTransferFinalizeProof? = nil,
            causality: CanonicalStatusCausality = .ordinarySync
        ) {
            let proof = CanonicalStatusProof(
                kind: kind,
                objectID: snapshot.objectID,
                hash: hash,
                byteSize: byteSize,
                peerNodeID: snapshot.nodeID,
                finalizeProof: finalizeProof,
                observedAt: now
            )
            facts.append(
                CanonicalStatusFact(
                    factID: id,
                    objectID: snapshot.objectID,
                    source: source,
                    producerNodeID: snapshot.nodeID,
                    logicalTime: CanonicalLogicalTime(counter: counter, nodeID: snapshot.nodeID),
                    proof: proof,
                    domain: snapshot.domain,
                    phase: phase,
                    causality: causality
                )
            )
            counter += 1
        }

        if let finalizeProof = snapshot.finalizeProof {
            append(
                id: "legacy-finalize-proof",
                source: .transferFinalizeProof,
                kind: .finalizeProof,
                phase: .completed,
                hash: finalizeProof.contentHash,
                byteSize: finalizeProof.byteSize,
                finalizeProof: finalizeProof,
                causality: CanonicalStatusCausality(trigger: .transferFinalize)
            )
        }
        if let hash = snapshot.peerInventoryHash,
           let byteSize = snapshot.peerInventoryByteSize,
           byteSize > 0 {
            append(
                id: "legacy-peer-inventory",
                source: .peerInventory,
                kind: .peerInventoryHashSizeMatch,
                phase: .peerVerified,
                hash: hash,
                byteSize: byteSize,
                causality: CanonicalStatusCausality(trigger: .statusExchange)
            )
        }
        if let hash = snapshot.localAudioHash,
           let byteSize = snapshot.localAudioByteSize,
           byteSize > 0 {
            append(
                id: "legacy-local-audio",
                source: .localFileObservation,
                kind: .localFileExists,
                phase: .localOnly,
                hash: hash,
                byteSize: byteSize,
                causality: CanonicalStatusCausality(trigger: .localFileIndex)
            )
        } else if let byteSize = snapshot.localAudioByteSize,
                  byteSize > 0 {
            append(
                id: "legacy-local-audio-observed",
                source: .localFileObservation,
                kind: .localFileExists,
                phase: .localOnly,
                byteSize: byteSize,
                causality: CanonicalStatusCausality(trigger: .localFileIndex)
            )
        }
        if snapshot.conflict {
            append(id: "legacy-conflict", source: .syncRuntime, kind: .existingDifferentAudio, phase: .conflict)
        }
        if snapshot.legacyPartialReceive {
            append(id: "legacy-partial-receive", source: .partialReceive, kind: .partialReceive, phase: .partialReceive)
        }
        if snapshot.legacyMetadataOnly {
            append(id: "legacy-metadata-only", source: .metadataOnlyLedger, kind: .metadataOnly, phase: .peerKnownMetadataOnly)
        }
        if snapshot.legacyReceiveRecordOnly {
            append(id: "legacy-receive-record", source: .peerReceiveRecord, kind: .receiveRecordOnly, phase: .peerKnownMetadataOnly)
        }
        if snapshot.legacyCompletedLedger {
            append(id: "legacy-completed-ledger", source: .legacyCompletedLedger, kind: .completedLedgerOnly, phase: .finalizedLocally)
        }
        if snapshot.uploading {
            append(id: "legacy-uploading", source: .uploadLedger, kind: .metadataOnly, phase: .uploading)
        }
        if snapshot.finalizing {
            append(id: "legacy-finalizing", source: .uploadLedger, kind: .metadataOnly, phase: .finalizing)
        }
        if snapshot.failed {
            append(id: "legacy-failed", source: .uploadLedger, kind: .metadataOnly, phase: .blocked)
        }
        if snapshot.peerUnknown {
            append(id: "legacy-peer-unknown", source: .syncRuntime, kind: .peerUnknown, phase: .peerUnknown)
        }
        if snapshot.existingEligibleRetry {
            append(id: "legacy-existing-retry", source: .retryDrainer, kind: .existingEligibleRetry, phase: .deferred)
        }
        if snapshot.viewRefresh {
            append(
                id: "legacy-view-refresh",
                source: .viewRefresh,
                kind: .peerUnknown,
                phase: .peerUnknown,
                causality: CanonicalStatusCausality(trigger: .viewRefresh)
            )
        }
        if snapshot.retryDrainer {
            append(
                id: "legacy-retry-drainer",
                source: .retryDrainer,
                kind: .peerUnknown,
                phase: .peerUnknown,
                causality: CanonicalStatusCausality(trigger: .retryDrainer)
            )
        }

        return facts
    }

    private nonisolated static func normalized(_ value: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private nonisolated static func normalizedHash(_ value: String?) -> CanonicalHash? {
        guard let value = normalized(value) else {
            return nil
        }
        return CanonicalHash(value)
    }

    private nonisolated static func containsAny(_ value: String?, _ needles: [String]) -> Bool {
        guard let value else {
            return false
        }
        return needles.contains { value.contains($0) }
    }
}
