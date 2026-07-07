//
//  IPhoneGeneratedArtifactCutoverExecutor.swift
//  Rokurics
//
//  Created by Codex on 2026/6/4.
//

import Foundation

actor IPhoneGeneratedArtifactCutoverExecutor: CanonicalGeneratedArtifactCutoverExecutor {
    private let applyPort: any CanonicalProductionApplyPort
    private let peerNode: CanonicalNode
    private let failureInjection: CanonicalGeneratedArtifactCommitFailureInjection
    private var committedActionIDs: Set<String> = []
    private var checkpointIDs: Set<String> = []
    private var rollbackFatalBlocker = false

    init(
        applyPort: any CanonicalProductionApplyPort = IPhoneGeneratedArtifactRealApplyPort(),
        peerNode: CanonicalNode = CanonicalNode(
            nodeID: "mac-generated-artifact-peer",
            platform: "Mac",
            capabilities: [.recordingMetadata, .transcriptArtifact, .noteArtifact, .summaryArtifact]
        ),
        failureInjection: CanonicalGeneratedArtifactCommitFailureInjection = .none
    ) {
        self.applyPort = applyPort
        self.peerNode = peerNode
        self.failureInjection = failureInjection
    }

    func commitGeneratedArtifact(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate
    ) async -> CanonicalGeneratedArtifactProductionCommitResult {
        guard !rollbackFatalBlocker else {
            return .failure(candidate: candidate, kind: .rollbackFailure, reason: "rollbackFatalBlocker")
        }
        if committedActionIDs.contains(candidate.action.actionID) {
            return CanonicalGeneratedArtifactProductionCommitResult(
                actionID: candidate.action.actionID,
                objectID: candidate.objectID,
                artifactID: candidate.artifactID,
                artifactKind: candidate.artifactKind,
                actionKind: candidate.cutoverActionKind,
                committed: true,
                contentHash: candidate.expectedContentHash,
                byteSize: candidate.expectedByteSize,
                reason: "idempotentGeneratedArtifactCommit"
            )
        }
        checkpointIDs.insert(candidate.effectiveRollbackCheckpointID)

        let precondition = makePrecondition(candidate)
        guard failureInjection != .hashMismatchBeforeApply,
              failureInjection != .parentTombstoned,
              failureInjection != .producerAmbiguous,
              failureInjection != .unsupportedKind,
              precondition.accepted else {
            return .failure(
                candidate: candidate,
                kind: failureKind(candidate, fallback: .hashMismatchBeforeApply),
                reason: precondition.reason ?? "generatedArtifactPreconditionMismatch"
            )
        }
        do {
            let verifiedPrecondition = try await applyPort.verifyPrecondition(precondition)
            guard verifiedPrecondition.accepted else {
                return .failure(candidate: candidate, kind: .hashMismatchBeforeApply, reason: verifiedPrecondition.reason ?? "generatedArtifactPreconditionRejected")
            }
        } catch {
            return .failure(candidate: candidate, kind: .hashMismatchBeforeApply, reason: "generatedArtifactPreconditionVerificationFailed")
        }
        guard !applyPort.isDryRunOnly else {
            return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "iphoneGeneratedArtifactCommitRequiresExplicitTestRootApplyPort")
        }
        if failureInjection == .applyFailureBeforeCommit {
            return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "injectedApplyFailureBeforeCommit")
        }

        let applyResult: CanonicalProductionApplyResult
        do {
            applyResult = try await applyPort.applyGeneratedArtifact(
                CanonicalProductionApplyExecutionRequest(
                    action: candidate.action,
                    rollbackCheckpointID: candidate.effectiveRollbackCheckpointID
                )
            )
        } catch {
            return .failure(
                candidate: candidate,
                kind: failureInjection == .applyFailureAfterPartialCommit ? .applyFailureAfterPartialCommit : .applyFailureBeforeCommit,
                partialCommit: failureInjection == .applyFailureAfterPartialCommit,
                reason: "iphoneGeneratedArtifactApplyPortFailed"
            )
        }
        let sideEffects = applyResult.sideEffect.map { [$0] } ?? []
        if failureInjection == .applyFailureAfterPartialCommit {
            return .failure(candidate: candidate, kind: .applyFailureAfterPartialCommit, partialCommit: true, reason: "injectedApplyFailureAfterPartialCommit")
        }
        guard applyResult.status == .applied else {
            return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "generatedArtifactApplyStatusMismatch")
        }
        let postcondition = CanonicalProductionApplyPostcondition(
            actionID: candidate.action.actionID,
            target: candidate.action.target,
            actualHashPrefix: candidate.expectedContentHash?.value,
            accepted: applyResult.postcondition?.accepted != false,
            reason: "generatedArtifactPostcondition"
        )
        do {
            let verifiedPostcondition = try await applyPort.verifyPostcondition(postcondition)
            guard failureInjection != .postconditionMismatch, verifiedPostcondition.accepted else {
                return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: verifiedPostcondition.reason ?? "generatedArtifactPostconditionMismatch")
            }
        } catch {
            return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "generatedArtifactPostconditionVerificationFailed")
        }
        guard sideEffects.allSatisfy(Self.isAllowedGeneratedArtifactSideEffect) else {
            return CanonicalGeneratedArtifactProductionCommitResult(
                actionID: candidate.action.actionID,
                objectID: candidate.objectID,
                artifactID: candidate.artifactID,
                artifactKind: candidate.artifactKind,
                actionKind: candidate.cutoverActionKind,
                committed: false,
                partialCommit: true,
                preconditionVerified: true,
                postconditionVerified: false,
                contentHash: candidate.expectedContentHash,
                byteSize: candidate.expectedByteSize,
                sideEffect: sideEffects.first,
                sideEffects: sideEffects,
                failureKind: .postconditionMismatch,
                reason: "generatedArtifactUnexpectedSideEffect"
            )
        }
        committedActionIDs.insert(candidate.action.actionID)
        return .success(candidate: candidate, sideEffects: sideEffects)
    }

    func rollbackGeneratedArtifact(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate,
        reason: CanonicalGeneratedArtifactCutoverFailure
    ) async -> CanonicalGeneratedArtifactRollbackExecutionResult {
        if failureInjection == .rollbackFailure {
            rollbackFatalBlocker = true
            return CanonicalGeneratedArtifactRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "injectedGeneratedArtifactRollbackFailure"
            )
        }
        if reason == .applyFailureBeforeCommit
            || reason == .hashMismatchBeforeApply
            || reason == .parentTombstoned
            || reason == .producerAmbiguous
            || applyPort.isDryRunOnly {
            committedActionIDs.remove(candidate.action.actionID)
            return CanonicalGeneratedArtifactRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: true,
                reason: "iphoneGeneratedArtifactRollbackNoOp",
                rollbackResult: CanonicalRollbackResult(
                    planID: candidate.effectiveRollbackCheckpointID,
                    succeeded: true,
                    completedActionIDs: []
                )
            )
        }
        guard checkpointIDs.contains(candidate.effectiveRollbackCheckpointID) else {
            rollbackFatalBlocker = true
            return CanonicalGeneratedArtifactRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "iphoneGeneratedArtifactRollbackCheckpointMissing"
            )
        }
        let action = CanonicalRollbackAction(
            actionID: "iphone-generated-artifact-rollback-\(candidate.action.actionID)",
            kind: .generatedArtifactRollback,
            domain: .generatedArtifacts,
            checkpointID: candidate.effectiveRollbackCheckpointID,
            objectID: candidate.objectID,
            artifactID: candidate.artifactID
        )
        do {
            let result = try await applyPort.rollbackApply(action)
            if result.succeeded {
                committedActionIDs.remove(candidate.action.actionID)
                checkpointIDs.remove(candidate.effectiveRollbackCheckpointID)
            } else {
                rollbackFatalBlocker = true
            }
            return CanonicalGeneratedArtifactRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: result.succeeded,
                fatal: !result.succeeded,
                reason: result.succeeded ? "iphoneGeneratedArtifactRollbackCompleted" : "iphoneGeneratedArtifactRollbackFailed",
                rollbackResult: result
            )
        } catch {
            rollbackFatalBlocker = true
            return CanonicalGeneratedArtifactRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "iphoneGeneratedArtifactRollbackFailed"
            )
        }
    }

    private func makePrecondition(_ candidate: CanonicalGeneratedArtifactCutoverCandidate) -> CanonicalProductionApplyPrecondition {
        let failures = preconditionFailures(candidate)
        return CanonicalProductionApplyPrecondition(
            actionID: candidate.action.actionID,
            target: candidate.action.target,
            expectedHashPrefix: candidate.expectedContentHash?.value,
            accepted: failures.isEmpty,
            reason: failures.isEmpty ? "preconditionsAccepted" : failures.joined(separator: ",")
        )
    }

    private func preconditionFailures(_ candidate: CanonicalGeneratedArtifactCutoverCandidate) -> [String] {
        var failures: [String] = []
        if !candidate.cutoverActionKind.isExecutableApply {
            failures.append("unsupportedAction")
        }
        if candidate.action.target.objectID != candidate.objectID {
            failures.append("objectIDMismatch")
        }
        if candidate.artifactID == nil || candidate.action.target.artifactID != candidate.artifactID {
            failures.append("artifactIDMismatch")
        }
        if candidate.artifactKind.map({ !CanonicalProjectionContract.generatedArtifactKinds.contains($0) }) ?? true {
            failures.append("unsupportedKind")
        }
        if candidate.expectedContentHash == nil {
            failures.append("expectedHashMissing")
        }
        if candidate.expectedByteSize == nil {
            failures.append("expectedByteSizeMissing")
        }
        if candidate.unresolvedConflict {
            failures.append("unresolvedConflict")
        }
        if candidate.parentObjectTombstoned || failureInjection == .parentTombstoned {
            failures.append("parentTombstoned")
        }
        if !candidate.peerIsAuthoritative(peerNode: peerNode) || failureInjection == .producerAmbiguous {
            failures.append("peerAuthoritativeEvidenceMissing")
        }
        if candidate.rollbackCheckpointID == nil {
            failures.append("rollbackCheckpointMissing")
        }
        if candidate.routePath != "/sync/artifact-request" {
            failures.append("artifactRequestRouteMismatch")
        }
        return failures
    }

    private func failureKind(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate,
        fallback: CanonicalGeneratedArtifactCutoverFailure
    ) -> CanonicalGeneratedArtifactCutoverFailure {
        if failureInjection == .parentTombstoned || candidate.parentObjectTombstoned {
            return .parentTombstoned
        }
        if failureInjection == .producerAmbiguous {
            return .producerAmbiguous
        }
        if failureInjection == .unsupportedKind {
            return .unsupportedKind
        }
        return fallback
    }

    private nonisolated static func isAllowedGeneratedArtifactSideEffect(_ sideEffect: CanonicalProductionSideEffect) -> Bool {
        switch sideEffect.kind {
        case .generatedArtifactApply:
            return sideEffect.domain == .generatedArtifacts || sideEffect.domain == .apply
        case .networkRequest:
            return false
        case .diagnosticsWrite:
            return true
        case .fileRead, .fileWrite, .metadataApply, .uploadSessionStart, .uploadChunkSend,
             .uploadFinalize, .tombstoneMark, .conflictRecord:
            return false
        }
    }
}
