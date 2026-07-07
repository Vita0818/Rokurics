//
//  IPhoneTombstoneConflictCutoverExecutor.swift
//  Rokurics
//
//  Created by Codex on 2026/6/4.
//

import Foundation

actor IPhoneTombstoneConflictCutoverExecutor: CanonicalTombstoneConflictCutoverExecutor {
    private let applyPort: any CanonicalProductionApplyPort
    private let failureInjection: CanonicalTombstoneConflictCommitFailureInjection
    private var committedActionIDs: Set<String> = []
    private var checkpointIDs: Set<String> = []
    private var rollbackFatalBlocker = false

    init(
        applyPort: any CanonicalProductionApplyPort = IPhoneTombstoneConflictRealApplyPort(),
        failureInjection: CanonicalTombstoneConflictCommitFailureInjection = .none
    ) {
        self.applyPort = applyPort
        self.failureInjection = failureInjection
    }

    func commitTombstoneConflict(
        _ candidate: CanonicalTombstoneConflictCandidate
    ) async -> CanonicalTombstoneConflictProductionCommitResult {
        guard !rollbackFatalBlocker else {
            return .failure(candidate: candidate, kind: .rollbackFailure, reason: "rollbackFatalBlocker")
        }
        if committedActionIDs.contains(candidate.action.actionID) {
            return .success(candidate: candidate, sideEffects: [])
        }
        checkpointIDs.insert(candidate.effectiveRollbackCheckpointID)

        let precondition = makePrecondition(candidate)
        guard failureInjection != .preconditionMismatch,
              precondition.accepted else {
            return .failure(candidate: candidate, kind: failureKind(candidate, fallback: .preconditionMismatch), reason: precondition.reason ?? "tombstoneConflictPreconditionMismatch")
        }
        do {
            let verifiedPrecondition = try await applyPort.verifyPrecondition(precondition)
            guard verifiedPrecondition.accepted else {
                return .failure(candidate: candidate, kind: .preconditionMismatch, reason: verifiedPrecondition.reason ?? "tombstoneConflictPreconditionRejected")
            }
        } catch {
            return .failure(candidate: candidate, kind: .preconditionMismatch, reason: "tombstoneConflictPreconditionVerificationFailed")
        }
        guard !applyPort.isDryRunOnly else {
            return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "iphoneTombstoneConflictCommitRequiresExplicitTestRootApplyPort")
        }
        if let injectedFailure = injectedFailureBeforeCommit(candidate) {
            return .failure(candidate: candidate, kind: injectedFailure, reason: "injected\(injectedFailure.rawValue)")
        }

        do {
            try await prepareRootBoundPayload(candidate)
        } catch {
            return .failure(candidate: candidate, kind: .rootBoundWriteUnavailable, reason: "iphoneTombstoneConflictPayloadPreparationFailed")
        }

        let applyResult: CanonicalProductionApplyResult
        do {
            let request = CanonicalProductionApplyExecutionRequest(
                action: candidate.action,
                rollbackCheckpointID: candidate.effectiveRollbackCheckpointID
            )
            switch candidate.actionKind {
            case .objectTombstoneApply, .objectTombstoneSend:
                applyResult = try await applyPort.applyObjectTombstone(request)
            case .libraryTombstoneApply, .libraryTombstoneSend:
                applyResult = try await applyPort.applyLibraryTombstone(request)
            case .conflictRecord, .resurrectionBlocked:
                applyResult = try await applyPort.recordConflict(request)
            case .generatedArtifactTombstoneMarkUnsupported, .unsupported:
                return .failure(candidate: candidate, kind: .unsupportedAction, reason: "unsupportedTombstoneConflictCommitAction")
            }
        } catch {
            return .failure(
                candidate: candidate,
                kind: failureInjection == .applyFailureAfterPartialCommit ? .applyFailureAfterPartialCommit : .applyFailureBeforeCommit,
                partialCommit: failureInjection == .applyFailureAfterPartialCommit,
                reason: "iphoneTombstoneConflictApplyPortFailed"
            )
        }
        let sideEffects = applyResult.sideEffect.map { [$0] } ?? []
        if failureInjection == .applyFailureAfterPartialCommit {
            return .failure(candidate: candidate, kind: .applyFailureAfterPartialCommit, partialCommit: true, reason: "injectedApplyFailureAfterPartialCommit")
        }
        guard applyResult.status == expectedStatus(candidate) else {
            return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "tombstoneConflictApplyStatusMismatch")
        }
        let postcondition = CanonicalProductionApplyPostcondition(
            actionID: candidate.action.actionID,
            target: candidate.action.target,
            actualHashPrefix: applyResult.postcondition?.actualHashPrefix ?? candidate.markerHash.value,
            accepted: applyResult.postcondition?.accepted != false,
            reason: "tombstoneConflictPostcondition"
        )
        do {
            let verifiedPostcondition = try await applyPort.verifyPostcondition(postcondition)
            guard failureInjection != .postconditionMismatch, verifiedPostcondition.accepted else {
                return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: verifiedPostcondition.reason ?? "tombstoneConflictPostconditionMismatch")
            }
        } catch {
            return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "tombstoneConflictPostconditionVerificationFailed")
        }
        guard sideEffects.allSatisfy(Self.isAllowedTombstoneConflictSideEffect) else {
            return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "tombstoneConflictUnexpectedSideEffect")
        }
        committedActionIDs.insert(candidate.action.actionID)
        return .success(candidate: candidate, sideEffects: sideEffects)
    }

    func rollbackTombstoneConflict(
        _ candidate: CanonicalTombstoneConflictCandidate,
        reason: CanonicalTombstoneConflictFailure
    ) async -> CanonicalTombstoneConflictRollbackExecutionResult {
        if failureInjection == .rollbackFailure {
            rollbackFatalBlocker = true
            return CanonicalTombstoneConflictRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "injectedTombstoneConflictRollbackFailure"
            )
        }
        if reason == .applyFailureBeforeCommit || applyPort.isDryRunOnly {
            committedActionIDs.remove(candidate.action.actionID)
            return CanonicalTombstoneConflictRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: true,
                reason: "iphoneTombstoneConflictRollbackNoOp",
                rollbackResult: CanonicalRollbackResult(planID: candidate.effectiveRollbackCheckpointID, succeeded: true)
            )
        }
        guard checkpointIDs.contains(candidate.effectiveRollbackCheckpointID) else {
            rollbackFatalBlocker = true
            return CanonicalTombstoneConflictRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "iphoneTombstoneConflictRollbackCheckpointMissing"
            )
        }
        let action = CanonicalRollbackAction(
            actionID: "iphone-tombstone-conflict-rollback-\(candidate.action.actionID)",
            kind: candidate.domain.requiresConflictLedger ? .conflictLedgerNoOp : .tombstoneRollback,
            domain: candidate.domain.productionDomain,
            checkpointID: candidate.effectiveRollbackCheckpointID,
            objectID: candidate.objectID
        )
        do {
            let result = try await applyPort.rollbackApply(action)
            if result.succeeded {
                committedActionIDs.remove(candidate.action.actionID)
                checkpointIDs.remove(candidate.effectiveRollbackCheckpointID)
            } else {
                rollbackFatalBlocker = true
            }
            return CanonicalTombstoneConflictRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: result.succeeded,
                fatal: !result.succeeded,
                reason: result.succeeded ? "iphoneTombstoneConflictRollbackCompleted" : "iphoneTombstoneConflictRollbackFailed",
                rollbackResult: result
            )
        } catch {
            rollbackFatalBlocker = true
            return CanonicalTombstoneConflictRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "iphoneTombstoneConflictRollbackFailed"
            )
        }
    }

    private func prepareRootBoundPayload(_ candidate: CanonicalTombstoneConflictCandidate) async throws {
        if let port = applyPort as? IPhoneTombstoneConflictRealApplyPort {
            try await port.setRootBoundTombstoneConflictPayload(candidate: candidate)
        }
    }

    private func makePrecondition(_ candidate: CanonicalTombstoneConflictCandidate) -> CanonicalProductionApplyPrecondition {
        let failures = preconditionFailures(candidate)
        return CanonicalProductionApplyPrecondition(
            actionID: candidate.action.actionID,
            target: candidate.action.target,
            expectedHashPrefix: candidate.markerHash.value,
            accepted: failures.isEmpty,
            reason: failures.isEmpty ? "preconditionsAccepted" : failures.joined(separator: ",")
        )
    }

    private func preconditionFailures(_ candidate: CanonicalTombstoneConflictCandidate) -> [String] {
        var failures: [String] = []
        if !candidate.actionKind.isExecutable { failures.append("unsupportedAction") }
        if candidate.action.target.objectID != candidate.objectID { failures.append("objectIDMismatch") }
        if candidate.actionKind.isTombstoneMarkerWrite && candidate.tombstoneState != .tombstoned { failures.append("tombstoneStateMismatch") }
        if candidate.actionKind.isTombstoneMarkerWrite && candidate.deletedAt == nil { failures.append("missingTombstoneTimestamp") }
        if candidate.actionKind.isTombstoneMarkerWrite && !candidate.tombstoneWinsIfNewerPolicy { failures.append("missingTombstoneWinsPolicy") }
        if candidate.actionKind.isTombstoneMarkerWrite && !candidate.rollbackEvidenceAvailable { failures.append("missingRollbackEvidence") }
        if candidate.explicitRestoreSignal || candidate.wouldRestoreFromAbsenceOnly { failures.append("unsupportedRestore") }
        if candidate.staleLiveMetadataRisk && candidate.actionKind != .resurrectionBlocked { failures.append("resurrectionRiskDetected") }
        if !candidate.conflictPolicyKnown { failures.append("conflictPolicyAmbiguous") }
        if candidate.routePath != "/sync/apply-metadata" { failures.append("metadataRouteMismatch") }
        if failureInjection == .physicalDeleteAttempted { failures.append("physicalDeleteAttempted") }
        if failureInjection == .permanentDeleteAttempted { failures.append("permanentDeleteAttempted") }
        if failureInjection == .tombstoneGCAttempted { failures.append("tombstoneGCAttempted") }
        if failureInjection == .unsupportedRestore { failures.append("unsupportedRestore") }
        if failureInjection == .conflictPolicyAmbiguous { failures.append("conflictPolicyAmbiguous") }
        if failureInjection == .resurrectionRiskDetected { failures.append("resurrectionRiskDetected") }
        return failures
    }

    private func failureKind(
        _ candidate: CanonicalTombstoneConflictCandidate,
        fallback: CanonicalTombstoneConflictFailure
    ) -> CanonicalTombstoneConflictFailure {
        if candidate.actionKind == .generatedArtifactTombstoneMarkUnsupported { return .generatedArtifactTombstoneUnsupported }
        if candidate.actionKind == .unsupported { return .unsupportedAction }
        if candidate.actionKind.isTombstoneMarkerWrite && candidate.deletedAt == nil { return .missingTombstoneTimestamp }
        if candidate.actionKind.isTombstoneMarkerWrite && !candidate.tombstoneWinsIfNewerPolicy { return .missingTombstoneWinsPolicy }
        if candidate.actionKind.isTombstoneMarkerWrite && !candidate.rollbackEvidenceAvailable { return .missingRollbackEvidence }
        if candidate.explicitRestoreSignal || candidate.wouldRestoreFromAbsenceOnly || failureInjection == .unsupportedRestore { return .unsupportedRestore }
        if (candidate.staleLiveMetadataRisk && candidate.actionKind != .resurrectionBlocked) || failureInjection == .resurrectionRiskDetected { return .resurrectionRiskDetected }
        if !candidate.conflictPolicyKnown || failureInjection == .conflictPolicyAmbiguous { return .conflictPolicyAmbiguous }
        if failureInjection == .physicalDeleteAttempted { return .physicalDeleteAttempted }
        if failureInjection == .permanentDeleteAttempted { return .permanentDeleteAttempted }
        if failureInjection == .tombstoneGCAttempted { return .tombstoneGCAttempted }
        return fallback
    }

    private func injectedFailureBeforeCommit(_ candidate: CanonicalTombstoneConflictCandidate) -> CanonicalTombstoneConflictFailure? {
        switch failureInjection {
        case .applyFailureBeforeCommit:
            return .applyFailureBeforeCommit
        case .resurrectionRiskDetected:
            return candidate.actionKind == .resurrectionBlocked ? nil : .resurrectionRiskDetected
        case .physicalDeleteAttempted:
            return .physicalDeleteAttempted
        case .permanentDeleteAttempted:
            return .permanentDeleteAttempted
        case .tombstoneGCAttempted:
            return .tombstoneGCAttempted
        case .unsupportedRestore:
            return .unsupportedRestore
        case .conflictPolicyAmbiguous:
            return .conflictPolicyAmbiguous
        case .none, .preconditionMismatch, .postconditionMismatch, .applyFailureAfterPartialCommit, .rollbackFailure:
            return nil
        }
    }

    private nonisolated func expectedStatus(_ candidate: CanonicalTombstoneConflictCandidate) -> CanonicalApplyExecutionStatus {
        switch candidate.actionKind {
        case .objectTombstoneSend, .libraryTombstoneSend:
            return .sent
        case .conflictRecord, .resurrectionBlocked:
            return .conflictRecorded
        case .objectTombstoneApply, .libraryTombstoneApply:
            return .applied
        case .generatedArtifactTombstoneMarkUnsupported, .unsupported:
            return .failed
        }
    }

    private nonisolated static func isAllowedTombstoneConflictSideEffect(_ sideEffect: CanonicalProductionSideEffect) -> Bool {
        switch sideEffect.kind {
        case .tombstoneMark:
            return sideEffect.domain == .tombstones
        case .conflictRecord:
            return sideEffect.domain == .conflicts
        case .diagnosticsWrite:
            return true
        case .fileRead, .fileWrite, .metadataApply, .generatedArtifactApply, .networkRequest,
             .uploadSessionStart, .uploadChunkSend, .uploadFinalize:
            return false
        }
    }
}
