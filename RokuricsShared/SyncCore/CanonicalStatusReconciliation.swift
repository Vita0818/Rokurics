//
//  CanonicalStatusReconciliation.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalStatusReconciliationRuntime {
    nonisolated static func reconcile(
        facts inputFacts: [CanonicalStatusFact],
        now: CanonicalTimestamp = CanonicalTimestamp(Date())
    ) -> (reconciliation: CanonicalStatusReconciliation, diagnostics: [CanonicalStatusTruthDiagnosticRecord]) {
        let orderedFacts = CanonicalStatusFactStore.deterministicOrder(inputFacts)
        let liveFacts = orderedFacts.filter { !$0.isExpired(now: now) }
        let staleFacts = liveFacts.filter { $0.isStale(now: now) }
        let freshFacts = liveFacts.filter { !$0.isStale(now: now) }
        let facts = freshFacts.isEmpty ? liveFacts : freshFacts
        let objectID = (facts.first ?? orderedFacts.first)?.objectID ?? CanonicalObjectID("object-unknown")
        let domain = dominantDomain(in: facts) ?? (orderedFacts.first?.domain ?? .audioUpload)
        var diagnostics: [CanonicalStatusTruthDiagnosticRecord] = []
        var blockers: Set<CanonicalStatusHardRule> = []

        func finish(
            phase: CanonicalStatusPhase,
            proof: CanonicalStatusProof? = nil,
            blocker: CanonicalStatusBlocker? = nil,
            canCreateUploadJob: Bool = false,
            canDisplayAsComplete: Bool = false,
            canSuppressLegacyDuplicate: Bool = false,
            extraDiagnostics: [CanonicalStatusTruthDiagnosticRecord] = []
        ) -> (CanonicalStatusReconciliation, [CanonicalStatusTruthDiagnosticRecord]) {
            var projectedCanCreateUploadJob = canCreateUploadJob
            var projectedBlocker = blocker
            var emittedDiagnostics = diagnostics + extraDiagnostics

            let denied = uploadJobCreationDenied(
                facts: facts,
                phase: phase,
                requested: projectedCanCreateUploadJob
            )
            if denied.denied {
                projectedCanCreateUploadJob = false
                projectedBlocker = denied.blocker ?? projectedBlocker
                if let hardRule = denied.hardRule {
                    blockers.insert(hardRule)
                }
                emittedDiagnostics.append(
                    CanonicalStatusTruthDiagnosticRecord(
                        event: .uploadJobCreationDeniedByStatusTruth,
                        objectID: objectID,
                        domain: domain,
                        phase: phase,
                        detail: denied.detail
                    )
                )
            }

            let status = CanonicalEffectiveSyncStatusProjection.project(
                objectID: objectID,
                domain: domain,
                phase: phase,
                proof: proof,
                facts: facts,
                now: now,
                blocker: projectedBlocker,
                canCreateUploadJob: projectedCanCreateUploadJob,
                canDisplayAsComplete: canDisplayAsComplete,
                canSuppressLegacyDuplicate: canSuppressLegacyDuplicate
            )
            emittedDiagnostics.append(
                CanonicalStatusTruthDiagnosticRecord(
                    event: .effectiveStatusProjected,
                    objectID: objectID,
                    domain: domain,
                    phase: phase,
                    hash: proof?.hash ?? proof?.finalizeProof?.contentHash,
                    byteSize: proof?.byteSize ?? proof?.finalizeProof?.byteSize,
                    detail: "canCreateUploadJob=\(projectedCanCreateUploadJob)"
                )
            )
            let reconciliation = CanonicalStatusReconciliation(
                objectID: objectID,
                effectiveStatus: status,
                acceptedProof: proof,
                blockers: Array(blockers),
                mayCreateUploadJob: projectedCanCreateUploadJob,
                mayOverwriteExistingPeerAudio: false
            )
            return (reconciliation, emittedDiagnostics)
        }

        if facts.isEmpty {
            blockers.insert(.peerUnknownMustDefer)
            diagnostics.append(peerProofUnavailable(objectID: objectID, domain: domain, detail: "noFacts"))
            return finish(phase: .deferred, blocker: .peerProofUnavailable)
        }

        if !staleFacts.isEmpty, freshFacts.isEmpty {
            blockers.insert(.staleFactCannotOverrideNewerProof)
            diagnostics.append(
                CanonicalStatusTruthDiagnosticRecord(
                    event: .statusFactRejected,
                    objectID: objectID,
                    domain: domain,
                    phase: .stale,
                    detail: "staleOnly"
                )
            )
            return finish(phase: .stale, blocker: .staleFactCannotOverrideNewerProof)
        }

        if facts.contains(where: { $0.proof.kind == .unsupportedSchema }) {
            blockers.insert(.unsupportedSchemaRequiresFallback)
            return finish(phase: .blocked, blocker: .unsupportedSchemaFallback)
        }

        if domain == .generatedArtifacts,
           facts.contains(where: { $0.proof.kind == .tombstone || $0.domain == .tombstoneConflict }) {
            blockers.insert(.tombstoneBlocksGeneratedArtifactResurrection)
            return finish(phase: .blocked, blocker: .tombstoneBlocksGeneratedArtifactResurrection)
        }

        if let conflict = facts.first(where: { $0.proof.kind == .existingDifferentAudio || $0.phase == .conflict }) {
            blockers.insert(.existingDifferentAudioMustConflictNoOverwrite)
            diagnostics.append(
                CanonicalStatusTruthDiagnosticRecord(
                    event: .existingDifferentAudioConflict,
                    objectID: objectID,
                    domain: domain,
                    factID: conflict.factID,
                    source: conflict.source,
                    phase: .conflict,
                    hash: conflict.proof.hash,
                    byteSize: conflict.proof.byteSize,
                    detail: "noOverwrite"
                )
            )
            return finish(phase: .conflict, proof: conflict.proof, blocker: .existingDifferentAudioConflict)
        }

        let localProof = facts.first { $0.proof.kind == .localFileExists && $0.proof.hasHashSizeProof }?.proof
        let peerHashProof = facts.first {
            ($0.proof.kind == .peerHashSize || $0.proof.kind == .peerInventoryHashSizeMatch || $0.proof.kind == .sameHashAndByteSize)
                && $0.proof.hasHashSizeProof
        }?.proof

        if let localProof, let peerHashProof {
            let noOp = CanonicalStatusTruthRules.evaluateAudioNoOp(
                localHash: localProof.hash!,
                localByteSize: localProof.byteSize!,
                peerHash: peerHashProof.hash!,
                peerByteSize: peerHashProof.byteSize!
            )
            if noOp.effectiveStatus.phase == .conflict {
                blockers.insert(.existingDifferentAudioMustConflictNoOverwrite)
                diagnostics.append(
                    CanonicalStatusTruthDiagnosticRecord(
                        event: .existingDifferentAudioConflict,
                        objectID: objectID,
                        domain: domain,
                        phase: .conflict,
                        hash: peerHashProof.hash,
                        byteSize: peerHashProof.byteSize,
                        detail: "hashSizeMismatch"
                    )
                )
                return finish(phase: .conflict, proof: peerHashProof, blocker: .existingDifferentAudioConflict)
            }
        }

        if let finalize = facts.first(where: { $0.proof.kind == .finalizeProof && $0.proof.hasAcceptedFinalizeProof }) {
            blockers.remove(.completedLedgerAloneIsNotPeerProof)
            diagnostics.append(
                CanonicalStatusTruthDiagnosticRecord(
                    event: .finalizeProofAccepted,
                    objectID: objectID,
                    domain: domain,
                    factID: finalize.factID,
                    source: finalize.source,
                    phase: .completed,
                    hash: finalize.proof.finalizeProof?.contentHash,
                    byteSize: finalize.proof.finalizeProof?.byteSize,
                    detail: "receiverAccepted"
                )
            )
            return finish(
                phase: .completed,
                proof: finalize.proof,
                canDisplayAsComplete: true,
                canSuppressLegacyDuplicate: true
            )
        }

        if let dualAck = facts.first(where: { $0.proof.kind == .dualAckProofChain && $0.proof.hasDualAckProofChain }) {
            return finish(
                phase: .completed,
                proof: dualAck.proof,
                canDisplayAsComplete: true,
                canSuppressLegacyDuplicate: true
            )
        }

        if let peerHashProof {
            blockers.remove(.completedLedgerAloneIsNotPeerProof)
            return finish(
                phase: .peerVerified,
                proof: peerHashProof,
                canDisplayAsComplete: true,
                canSuppressLegacyDuplicate: true
            )
        }

        if let partial = facts.first(where: { $0.proof.kind == .partialReceive || $0.phase == .partialReceive }) {
            blockers.insert(.partialReceiveIsNotCompleted)
            diagnostics.append(
                CanonicalStatusTruthDiagnosticRecord(
                    event: .partialReceiveRejectedAsCompleted,
                    objectID: objectID,
                    domain: domain,
                    factID: partial.factID,
                    source: partial.source,
                    phase: .partialReceive,
                    detail: "partialReceive"
                )
            )
            return finish(phase: .partialReceive, proof: partial.proof, blocker: .partialReceiveRejectedAsCompleted)
        }

        if let completedLedger = facts.first(where: { $0.proof.kind == .completedLedgerOnly || $0.source == .legacyCompletedLedger }) {
            blockers.insert(.completedLedgerAloneIsNotPeerProof)
            diagnostics.append(
                CanonicalStatusTruthDiagnosticRecord(
                    event: .completedLedgerRejectedAsPeerProof,
                    objectID: objectID,
                    domain: domain,
                    factID: completedLedger.factID,
                    source: completedLedger.source,
                    phase: completedLedger.phase,
                    detail: "ledgerOnly"
                )
            )
        }

        let localFileExists = facts.contains { $0.proof.kind == .localFileExists || $0.phase == .localOnly }
        let peerMetadataOnly = facts.first {
            $0.proof.kind == .metadataOnly
                || $0.proof.kind == .receiveRecordOnly
                || $0.phase == .peerKnownMetadataOnly
                || $0.phase == .metadataOnly
        }
        if let peerMetadataOnly {
            if peerMetadataOnly.proof.kind == .receiveRecordOnly {
                blockers.insert(.receiveRecordOnlyIsNotAudioAvailable)
            } else {
                blockers.insert(.metadataOnlyIsNotAudioAvailable)
                diagnostics.append(
                    CanonicalStatusTruthDiagnosticRecord(
                        event: .metadataOnlyRejectedAsAudioProof,
                        objectID: objectID,
                        domain: domain,
                        factID: peerMetadataOnly.factID,
                        source: peerMetadataOnly.source,
                        phase: peerMetadataOnly.phase,
                        detail: "metadataOnly"
                    )
                )
            }
            if localFileExists {
                return finish(
                    phase: .uploadNeeded,
                    proof: peerMetadataOnly.proof,
                    blocker: peerMetadataOnly.proof.kind == .receiveRecordOnly ? .receiveRecordOnlyRejectedAsAudioProof : .metadataOnlyRejectedAsAudioProof,
                    canCreateUploadJob: true
                )
            }
            return finish(
                phase: .peerKnownMetadataOnly,
                proof: peerMetadataOnly.proof,
                blocker: peerMetadataOnly.proof.kind == .receiveRecordOnly ? .receiveRecordOnlyRejectedAsAudioProof : .metadataOnlyRejectedAsAudioProof
            )
        }

        if let peerUnknown = facts.first(where: { $0.proof.kind == .peerUnknown || $0.phase == .peerUnknown }) {
            blockers.insert(.peerUnknownMustDefer)
            diagnostics.append(peerProofUnavailable(objectID: objectID, domain: domain, detail: "peerUnknown"))
            let manualOverride = localFileExists && facts.contains {
                $0.causality.trigger == .manualForce && $0.causality.permitsManualPeerUnknownUpload
            }
            if manualOverride {
                return finish(phase: .uploadNeeded, proof: peerUnknown.proof, canCreateUploadJob: true)
            }
            return finish(phase: .deferred, proof: peerUnknown.proof, blocker: .peerProofUnavailable)
        }

        if facts.contains(where: { $0.phase == .uploading }) {
            return finish(phase: .uploading)
        }

        if facts.contains(where: { $0.phase == .finalizing }) {
            return finish(phase: .finalizing)
        }

        if localFileExists {
            blockers.insert(.localFileExistsIsNotPeerHasFile)
            return finish(phase: .localOnly, proof: localProof, blocker: .localFileExistsIsNotPeerProof)
        }

        if facts.contains(where: { $0.phase == .absent }) {
            return finish(phase: .absent)
        }

        blockers.insert(.peerUnknownMustDefer)
        diagnostics.append(peerProofUnavailable(objectID: objectID, domain: domain, detail: "fallback"))
        return finish(phase: .deferred, blocker: .peerProofUnavailable)
    }

    private nonisolated static func dominantDomain(in facts: [CanonicalStatusFact]) -> CanonicalStatusDomain? {
        facts.reduce(into: [CanonicalStatusDomain: Int]()) { counts, fact in
            counts[fact.domain, default: 0] += 1
        }
        .sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key.rawValue < $1.key.rawValue
        }
        .first?.key
    }

    private nonisolated static func uploadJobCreationDenied(
        facts: [CanonicalStatusFact],
        phase: CanonicalStatusPhase,
        requested: Bool
    ) -> (denied: Bool, blocker: CanonicalStatusBlocker?, hardRule: CanonicalStatusHardRule?, detail: String) {
        guard requested || phase == .uploadNeeded else {
            return (false, nil, nil, "")
        }
        if facts.contains(where: { $0.source == .viewRefresh || $0.causality.trigger == .viewRefresh }) {
            return (true, .viewRefreshCannotCreateUploadJob, .viewRefreshCannotCreateUploadJob, "viewRefresh")
        }
        if facts.contains(where: { $0.source == .retryDrainer || $0.causality.trigger == .retryDrainer }) {
            let hasExistingEligibleRetry = facts.contains { $0.proof.kind == .existingEligibleRetry }
            return (
                true,
                hasExistingEligibleRetry ? nil : .retryDrainerRequiresExistingEligibleJob,
                .retryDrainerCanOnlyResumeExistingEligibleJob,
                hasExistingEligibleRetry ? "retryDrainerResumeOnly" : "retryDrainerNoExistingEligibleJob"
            )
        }
        return (false, nil, nil, "")
    }

    private nonisolated static func peerProofUnavailable(
        objectID: CanonicalObjectID,
        domain: CanonicalStatusDomain,
        detail: String
    ) -> CanonicalStatusTruthDiagnosticRecord {
        CanonicalStatusTruthDiagnosticRecord(
            event: .peerProofUnavailable,
            objectID: objectID,
            domain: domain,
            phase: .deferred,
            detail: detail
        )
    }
}
