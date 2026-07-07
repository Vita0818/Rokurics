//
//  MacLibraryMetadataCutoverExecutor.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/4.
//

import Foundation

actor MacLibraryMetadataCutoverExecutor: CanonicalLibraryMetadataCutoverExecutor {
    private let applyPort: any CanonicalProductionApplyPort
    private let failureInjection: CanonicalLibraryMetadataCommitFailureInjection
    private var committedActionIDs: Set<String> = []
    private var checkpointIDs: Set<String> = []
    private var rollbackFatalBlocker = false

    init(
        applyPort: any CanonicalProductionApplyPort = MacLibraryMetadataRealApplyPort(),
        failureInjection: CanonicalLibraryMetadataCommitFailureInjection = .none
    ) {
        self.applyPort = applyPort
        self.failureInjection = failureInjection
    }

    func commitLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate
    ) async -> CanonicalLibraryMetadataProductionCommitResult {
        guard !rollbackFatalBlocker else {
            return .failure(candidate: candidate, kind: .rollbackFailure, reason: "rollbackFatalBlocker")
        }
        if committedActionIDs.contains(candidate.action.actionID) {
            return .success(candidate: candidate, payloadByteCount: 0, sideEffects: [])
        }
        checkpointIDs.insert(candidate.effectiveRollbackCheckpointID)

        let precondition = makePrecondition(candidate)
        guard failureInjection != .preconditionMismatch,
              precondition.accepted else {
            return .failure(candidate: candidate, kind: failureKind(candidate, fallback: .objectIDMismatch), reason: precondition.reason ?? "libraryMetadataPreconditionMismatch")
        }
        do {
            let verifiedPrecondition = try await applyPort.verifyPrecondition(precondition)
            guard verifiedPrecondition.accepted else {
                return .failure(candidate: candidate, kind: .objectIDMismatch, reason: verifiedPrecondition.reason ?? "libraryMetadataPreconditionRejected")
            }
        } catch {
            return .failure(candidate: candidate, kind: .objectIDMismatch, reason: "libraryMetadataPreconditionVerificationFailed")
        }
        guard !applyPort.isDryRunOnly else {
            return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "macLibraryMetadataCommitRequiresExplicitTestRootApplyPort")
        }
        if failureInjection == .applyFailureBeforeCommit {
            return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "injectedApplyFailureBeforeCommit")
        }

        let applyResult: CanonicalProductionApplyResult
        do {
            let request = CanonicalProductionApplyExecutionRequest(
                action: candidate.action,
                rollbackCheckpointID: candidate.effectiveRollbackCheckpointID
            )
            if candidate.cutoverActionKind.isSend {
                applyResult = try await applyPort.sendMetadata(request)
            } else {
                applyResult = try await applyPort.applyMetadata(request)
            }
        } catch {
            return .failure(
                candidate: candidate,
                kind: failureInjection == .applyFailureAfterPartialCommit ? .applyFailureAfterPartialCommit : .applyFailureBeforeCommit,
                partialCommit: failureInjection == .applyFailureAfterPartialCommit,
                reason: "macLibraryMetadataApplyPortFailed"
            )
        }
        let sideEffects = applyResult.sideEffect.map { [$0] } ?? []
        if failureInjection == .applyFailureAfterPartialCommit {
            return .failure(candidate: candidate, kind: .applyFailureAfterPartialCommit, partialCommit: true, reason: "injectedApplyFailureAfterPartialCommit")
        }
        guard applyResult.status == (candidate.cutoverActionKind.isSend ? .sent : .applied) else {
            return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "libraryMetadataApplyStatusMismatch")
        }
        let postcondition = CanonicalProductionApplyPostcondition(
            actionID: candidate.action.actionID,
            target: candidate.action.target,
            actualHashPrefix: applyResult.postcondition?.actualHashPrefix ?? candidate.expectedMetadataHash?.value,
            accepted: applyResult.postcondition?.accepted != false,
            reason: "libraryMetadataPostcondition"
        )
        do {
            let verifiedPostcondition = try await applyPort.verifyPostcondition(postcondition)
            guard failureInjection != .postconditionMismatch, verifiedPostcondition.accepted else {
                return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: verifiedPostcondition.reason ?? "libraryMetadataPostconditionMismatch")
            }
        } catch {
            return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "libraryMetadataPostconditionVerificationFailed")
        }
        guard sideEffects.allSatisfy(Self.isAllowedLibraryMetadataSideEffect) else {
            return CanonicalLibraryMetadataProductionCommitResult(
                actionID: candidate.action.actionID,
                objectID: candidate.objectID,
                objectKind: candidate.objectKind,
                domain: candidate.domain,
                actionKind: candidate.cutoverActionKind,
                committed: false,
                partialCommit: true,
                preconditionVerified: true,
                postconditionVerified: false,
                metadataHash: candidate.expectedMetadataHash,
                parentSummary: candidate.parentSummary,
                tagCount: candidate.tagCount,
                filingSummary: candidate.filingSummary,
                sideEffect: sideEffects.first,
                sideEffects: sideEffects,
                failureKind: .postconditionMismatch,
                reason: "libraryMetadataUnexpectedSideEffect"
            )
        }
        committedActionIDs.insert(candidate.action.actionID)
        return .success(
            candidate: candidate,
            payloadByteCount: Int(sideEffects.first?.byteSize ?? 0),
            sideEffects: sideEffects
        )
    }

    func rollbackLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate,
        reason: CanonicalLibraryMetadataCutoverFailure
    ) async -> CanonicalLibraryMetadataRollbackExecutionResult {
        if failureInjection == .rollbackFailure {
            rollbackFatalBlocker = true
            return CanonicalLibraryMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "injectedLibraryMetadataRollbackFailure"
            )
        }
        if reason == .applyFailureBeforeCommit || applyPort.isDryRunOnly {
            committedActionIDs.remove(candidate.action.actionID)
            return CanonicalLibraryMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: true,
                reason: "macLibraryMetadataRollbackNoOp",
                rollbackResult: CanonicalRollbackResult(planID: candidate.effectiveRollbackCheckpointID, succeeded: true)
            )
        }
        guard checkpointIDs.contains(candidate.effectiveRollbackCheckpointID) else {
            rollbackFatalBlocker = true
            return CanonicalLibraryMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "macLibraryMetadataRollbackCheckpointMissing"
            )
        }
        let action = CanonicalRollbackAction(
            actionID: "mac-library-metadata-rollback-\(candidate.action.actionID)",
            kind: .metadataRollback,
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
            return CanonicalLibraryMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: result.succeeded,
                fatal: !result.succeeded,
                reason: result.succeeded ? "macLibraryMetadataRollbackCompleted" : "macLibraryMetadataRollbackFailed",
                rollbackResult: result
            )
        } catch {
            rollbackFatalBlocker = true
            return CanonicalLibraryMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "macLibraryMetadataRollbackFailed"
            )
        }
    }

    private func makePrecondition(_ candidate: CanonicalLibraryMetadataCutoverCandidate) -> CanonicalProductionApplyPrecondition {
        let failures = preconditionFailures(candidate)
        return CanonicalProductionApplyPrecondition(
            actionID: candidate.action.actionID,
            target: candidate.action.target,
            expectedHashPrefix: candidate.expectedMetadataHash?.value,
            accepted: failures.isEmpty,
            reason: failures.isEmpty ? "preconditionsAccepted" : failures.joined(separator: ",")
        )
    }

    private func preconditionFailures(_ candidate: CanonicalLibraryMetadataCutoverCandidate) -> [String] {
        var failures: [String] = []
        if !candidate.cutoverActionKind.isExecutableMetadata { failures.append("unsupportedAction") }
        if candidate.action.target.objectID != candidate.objectID { failures.append("objectIDMismatch") }
        if candidate.expectedMetadataHash == nil { failures.append("expectedMetadataHashMissing") }
        if candidate.expectedBusinessModifiedAt == nil { failures.append("expectedBusinessModifiedAtMissing") }
        if candidate.unresolvedConflict || failureInjection == .conflictDetected { failures.append("conflictDetected") }
        if candidate.hasActiveVsTombstoneConflict { failures.append("activeVsTombstoneConflict") }
        if candidate.hasResourceMoveAttempt || failureInjection == .resourceMoveAttempted { failures.append("resourceMoveAttempted") }
        if candidate.parentMissingKnown || failureInjection == .parentMissing { failures.append("parentMissing") }
        if candidate.hasObjectIDInstability { failures.append("objectIDInstability") }
        if failureInjection == .cycleDetected { failures.append("cycleDetected") }
        if failureInjection == .unsupportedObjectKind { failures.append("unsupportedObjectKind") }
        if candidate.rollbackCheckpointID == nil { failures.append("rollbackCheckpointMissing") }
        if candidate.routePath != "/sync/apply-metadata" { failures.append("metadataManifestRouteMismatch") }
        return failures
    }

    private func failureKind(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate,
        fallback: CanonicalLibraryMetadataCutoverFailure
    ) -> CanonicalLibraryMetadataCutoverFailure {
        if candidate.unresolvedConflict || failureInjection == .conflictDetected { return .conflictDetected }
        if candidate.hasResourceMoveAttempt || failureInjection == .resourceMoveAttempted { return .resourceMoveAttempted }
        if candidate.parentMissingKnown || failureInjection == .parentMissing { return .parentMissing }
        if failureInjection == .cycleDetected { return .cycleDetected }
        if failureInjection == .unsupportedObjectKind { return .unsupportedObjectKind }
        return fallback
    }

    private nonisolated static func isAllowedLibraryMetadataSideEffect(_ sideEffect: CanonicalProductionSideEffect) -> Bool {
        switch sideEffect.kind {
        case .metadataApply:
            return sideEffect.domain == .folders
                || sideEffect.domain == .studyItems
                || sideEffect.domain == .standaloneNotes
                || sideEffect.domain == .apply
        case .diagnosticsWrite:
            return true
        case .fileRead, .fileWrite, .generatedArtifactApply, .networkRequest, .uploadSessionStart,
             .uploadChunkSend, .uploadFinalize, .tombstoneMark, .conflictRecord:
            return false
        }
    }
}
