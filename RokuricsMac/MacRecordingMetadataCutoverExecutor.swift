//
//  MacRecordingMetadataCutoverExecutor.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/4.
//

import Foundation

actor MacRecordingMetadataCutoverExecutor: CanonicalRecordingMetadataCutoverExecutor {
    private let applyPort: any CanonicalProductionApplyPort
    private let transportPort: (any CanonicalProductionTransportPort)?
    private let sourceNode: CanonicalNode
    private let destinationNode: CanonicalNode
    private let failureInjection: CanonicalRecordingMetadataCommitFailureInjection
    private var committedActionIDs: Set<String> = []
    private var checkpointIDs: Set<String> = []
    private var rollbackFatalBlocker = false

    init(
        ports: CanonicalProductionPortSet = MacCanonicalProductionPorts.makeDisabledPortSet(),
        sourceNode: CanonicalNode = CanonicalNode(nodeID: "mac-cutover-local", platform: "Mac", capabilities: [.recordingMetadata]),
        destinationNode: CanonicalNode = CanonicalNode(nodeID: "iphone-cutover-peer", platform: "iPhone", capabilities: [.recordingMetadata]),
        failureInjection: CanonicalRecordingMetadataCommitFailureInjection = .none
    ) {
        self.applyPort = ports.apply ?? MacCanonicalProductionApplyPort()
        self.transportPort = ports.transport
        self.sourceNode = sourceNode
        self.destinationNode = destinationNode
        self.failureInjection = failureInjection
    }

    init(
        applyPort: any CanonicalProductionApplyPort,
        transportPort: (any CanonicalProductionTransportPort)? = nil,
        sourceNode: CanonicalNode = CanonicalNode(nodeID: "mac-cutover-local", platform: "Mac", capabilities: [.recordingMetadata]),
        destinationNode: CanonicalNode = CanonicalNode(nodeID: "iphone-cutover-peer", platform: "iPhone", capabilities: [.recordingMetadata]),
        failureInjection: CanonicalRecordingMetadataCommitFailureInjection = .none
    ) {
        self.applyPort = applyPort
        self.transportPort = transportPort
        self.sourceNode = sourceNode
        self.destinationNode = destinationNode
        self.failureInjection = failureInjection
    }

    func commitRecordingMetadata(
        _ candidate: CanonicalRecordingMetadataCutoverCandidate
    ) async -> CanonicalRecordingMetadataProductionCommitResult {
        guard !rollbackFatalBlocker else {
            return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "rollbackFatalBlocker")
        }
        guard let actionKind = candidate.cutoverActionKind else {
            return .failure(candidate: candidate, kind: .preconditionMismatch, reason: "nonRecordingMetadataActionBlocked")
        }
        if committedActionIDs.contains(candidate.action.actionID) {
            return CanonicalRecordingMetadataProductionCommitResult(
                actionID: candidate.action.actionID,
                objectID: candidate.objectID,
                actionKind: actionKind,
                committed: true,
                routePath: actionKind == .send ? "/sync/apply-metadata" : nil,
                metadataHash: candidate.stableMetadataHash,
                reason: "idempotentRecordingMetadataCommit"
            )
        }

        if failureInjection != .missingRollbackCheckpoint {
            checkpointIDs.insert(candidate.effectiveRollbackCheckpointID)
        }
        let precondition = makePrecondition(candidate)
        guard failureInjection != .preconditionMismatch, precondition.accepted else {
            return .failure(candidate: candidate, kind: .preconditionMismatch, reason: precondition.reason ?? "recordingMetadataPreconditionMismatch")
        }
        do {
            let verifiedPrecondition = try await applyPort.verifyPrecondition(precondition)
            guard verifiedPrecondition.accepted else {
                return .failure(candidate: candidate, kind: .preconditionMismatch, reason: verifiedPrecondition.reason ?? "recordingMetadataPreconditionRejected")
            }
        } catch {
            return .failure(candidate: candidate, kind: .preconditionMismatch, reason: "recordingMetadataPreconditionVerificationFailed")
        }
        guard !applyPort.isDryRunOnly else {
            return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "macRecordingMetadataCommitRequiresInternalFakeApplyPort")
        }
        if let realApplyPort = applyPort as? MacRecordingMetadataRealApplyPort {
            do {
                try await realApplyPort.prepare(candidate: candidate)
            } catch {
                return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "macRecordingMetadataRealApplyPortPrepareFailed")
            }
        }

        var sideEffects: [CanonicalProductionSideEffect] = []
        if candidate.requiresNetworkSend {
            guard failureInjection != .transportFailureBeforeSend else {
                return .failure(candidate: candidate, kind: .transportFailureBeforeSend, reason: "injectedTransportFailureBeforeSend")
            }
            do {
                let exchange = try await sendRouteProjection(candidate)
                if let sideEffect = exchange.sideEffect {
                    sideEffects.append(sideEffect)
                }
            } catch {
                return .failure(candidate: candidate, kind: .transportFailureBeforeSend, reason: "macApplyMetadataRouteProjectionFailed")
            }
            if failureInjection == .transportFailureAfterAcceptedResponse {
                return .failure(candidate: candidate, kind: .applyFailureAfterPartialCommit, partialCommit: true, reason: "injectedTransportAcceptedThenFailed")
            }
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
            applyResult = candidate.requiresNetworkSend
                ? try await applyPort.sendMetadata(request)
                : try await applyPort.applyMetadata(request)
        } catch {
            return .failure(candidate: candidate, kind: .applyFailureBeforeCommit, reason: "macRecordingMetadataApplyPortFailed")
        }
        if let sideEffect = applyResult.sideEffect {
            sideEffects.append(sideEffect)
        }

        if failureInjection == .unsupportedSideEffect || failureInjection == .unexpectedSideEffect {
            sideEffects.append(
                CanonicalProductionSideEffect(
                    kind: failureInjection == .unsupportedSideEffect ? .generatedArtifactApply : .uploadSessionStart,
                    domain: failureInjection == .unsupportedSideEffect ? .generatedArtifacts : .uploadRuntime,
                    objectID: candidate.objectID,
                    summary: failureInjection == .unsupportedSideEffect
                        ? "injectedUnsupportedSideEffect"
                        : "injectedUnexpectedSideEffect"
                )
            )
        }

        if failureInjection == .applyFailureAfterPartialCommit
            || failureInjection == .rollbackFailure
            || failureInjection == .missingRollbackCheckpoint {
            let reason: String
            switch failureInjection {
            case .rollbackFailure:
                reason = "injectedRollbackFailureSetup"
            case .missingRollbackCheckpoint:
                reason = "injectedMissingRollbackCheckpoint"
            default:
                reason = "injectedApplyFailureAfterPartialCommit"
            }
            return .failure(candidate: candidate, kind: .applyFailureAfterPartialCommit, partialCommit: true, reason: reason)
        }
        let expectedStatus: CanonicalApplyExecutionStatus = candidate.requiresNetworkSend ? .sent : .applied
        guard applyResult.status == expectedStatus else {
            return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "recordingMetadataApplyStatusMismatch")
        }
        let postcondition = makePostcondition(candidate, accepted: applyResult.postcondition?.accepted != false)
        do {
            let verifiedPostcondition = try await applyPort.verifyPostcondition(postcondition)
            guard failureInjection != .postconditionMismatch, verifiedPostcondition.accepted else {
                return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: verifiedPostcondition.reason ?? "recordingMetadataPostconditionMismatch")
            }
        } catch {
            return .failure(candidate: candidate, kind: .postconditionMismatch, partialCommit: true, reason: "recordingMetadataPostconditionVerificationFailed")
        }
        guard sideEffects.allSatisfy(Self.isAllowedRecordingMetadataSideEffect) else {
            return CanonicalRecordingMetadataProductionCommitResult(
                actionID: candidate.action.actionID,
                objectID: candidate.objectID,
                actionKind: actionKind,
                committed: false,
                partialCommit: true,
                preconditionVerified: true,
                postconditionVerified: false,
                routePath: candidate.requiresNetworkSend ? "/sync/apply-metadata" : nil,
                metadataHash: candidate.stableMetadataHash,
                sideEffect: sideEffects.first,
                sideEffects: sideEffects,
                failureKind: .postconditionMismatch,
                reason: "recordingMetadataUnexpectedSideEffect"
            )
        }

        committedActionIDs.insert(candidate.action.actionID)
        return CanonicalRecordingMetadataProductionCommitResult(
            actionID: candidate.action.actionID,
            objectID: candidate.objectID,
            actionKind: actionKind,
            committed: true,
            routePath: candidate.requiresNetworkSend ? "/sync/apply-metadata" : nil,
            metadataHash: candidate.stableMetadataHash,
            sideEffect: sideEffects.first,
            sideEffects: sideEffects,
            reason: candidate.requiresNetworkSend ? "macRecordingMetadataSendCommitted" : "macRecordingMetadataApplyCommitted"
        )
    }

    func rollbackRecordingMetadata(
        _ candidate: CanonicalRecordingMetadataCutoverCandidate,
        reason: CanonicalCutoverFailure
    ) async -> CanonicalRecordingMetadataRollbackExecutionResult {
        if failureInjection == .rollbackFailure {
            rollbackFatalBlocker = true
            return CanonicalRecordingMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "injectedRollbackFailure"
            )
        }
        let action = CanonicalRollbackAction(
            actionID: "mac-recording-metadata-rollback-\(candidate.action.actionID)",
            kind: reason == .transportFailureBeforeSend ? .transportNoOpRollback : .metadataRollback,
            domain: .recordingMetadata,
            checkpointID: candidate.effectiveRollbackCheckpointID,
            objectID: candidate.objectID
        )
        if reason == .transportFailureBeforeSend
            || failureInjection == .transportFailureAfterAcceptedResponse
            || reason == .applyFailureBeforeCommit
            || reason == .preconditionMismatch
            || applyPort.isDryRunOnly {
            committedActionIDs.remove(candidate.action.actionID)
            return CanonicalRecordingMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: true,
                reason: "macRecordingMetadataRollbackNoOp",
                rollbackResult: CanonicalRollbackResult(
                    planID: candidate.effectiveRollbackCheckpointID,
                    succeeded: true,
                    completedActionIDs: [action.actionID]
                )
            )
        }
        guard checkpointIDs.contains(candidate.effectiveRollbackCheckpointID) else {
            rollbackFatalBlocker = true
            return CanonicalRecordingMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "macRecordingMetadataRollbackCheckpointMissing",
                rollbackResult: CanonicalRollbackResult(
                    planID: candidate.effectiveRollbackCheckpointID,
                    succeeded: false,
                    completedActionIDs: []
                )
            )
        }
        do {
            let result = try await applyPort.rollbackApply(action)
            if result.succeeded {
                committedActionIDs.remove(candidate.action.actionID)
                checkpointIDs.remove(candidate.effectiveRollbackCheckpointID)
            } else {
                rollbackFatalBlocker = true
            }
            return CanonicalRecordingMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: result.succeeded,
                fatal: !result.succeeded,
                reason: result.succeeded ? "macRecordingMetadataRollbackCompleted" : "macRecordingMetadataRollbackFailed",
                rollbackResult: result
            )
        } catch {
            rollbackFatalBlocker = true
            return CanonicalRecordingMetadataRollbackExecutionResult(
                checkpointID: candidate.effectiveRollbackCheckpointID,
                succeeded: false,
                fatal: true,
                reason: "macRecordingMetadataRollbackFailed"
            )
        }
    }

    private func sendRouteProjection(
        _ candidate: CanonicalRecordingMetadataCutoverCandidate
    ) async throws -> CanonicalProductionTransportExchangeResult {
        guard let transportPort else {
            throw CanonicalProductionPortError.networkExecutionSuppressed("macRecordingMetadataTransportPortMissing")
        }
        let body = try CanonicalTransportJSON.encode(candidate.action)
        let envelope = CanonicalProductionTransportBuildRequest(
            source: sourceNode,
            destination: destinationNode,
            route: .applyMetadata,
            existingRoutePath: "/sync/apply-metadata",
            body: body,
            nonce: "external-nonce-required"
        )
        return try await transportPort.sendApplyMetadata(candidate.action, envelope: envelope)
    }

    private func makePrecondition(
        _ candidate: CanonicalRecordingMetadataCutoverCandidate
    ) -> CanonicalProductionApplyPrecondition {
        let failures = preconditionFailures(candidate)
        return CanonicalProductionApplyPrecondition(
            actionID: candidate.action.actionID,
            target: candidate.action.target,
            expectedHashPrefix: candidate.stableMetadataHash?.value,
            accepted: failures.isEmpty,
            reason: failures.isEmpty ? "preconditionsAccepted" : failures.joined(separator: ",")
        )
    }

    private func makePostcondition(
        _ candidate: CanonicalRecordingMetadataCutoverCandidate,
        accepted: Bool
    ) -> CanonicalProductionApplyPostcondition {
        CanonicalProductionApplyPostcondition(
            actionID: candidate.action.actionID,
            target: candidate.action.target,
            actualHashPrefix: candidate.stableMetadataHash?.value,
            accepted: accepted,
            reason: accepted ? "postconditionsAccepted" : "applyPortPostconditionRejected"
        )
    }

    private func preconditionFailures(_ candidate: CanonicalRecordingMetadataCutoverCandidate) -> [String] {
        var failures: [String] = []
        guard let kind = candidate.cutoverActionKind else {
            return ["unsupportedAction"]
        }
        if candidate.action.target.objectID != candidate.objectID {
            failures.append("objectIDMismatch")
        }
        if candidate.expectedObject?.metadataHash == nil {
            failures.append("expectedCanonicalHashMissing")
        }
        if candidate.localObject?.metadataHash == nil {
            failures.append("expectedLocalHashMissing")
        }
        if candidate.peerObject?.metadataHash == nil {
            failures.append("expectedPeerHashMissing")
        }
        if candidate.unresolvedConflict {
            failures.append("unresolvedConflict")
        }
        if kind == .send, candidate.requiresNetworkSend == false {
            failures.append("sendActionMissingRoute")
        }
        if kind == .send, transportPort == nil {
            failures.append("transportPortMissing")
        }
        if kind == .send, candidate.action.bridgeHint != .legacyMetadataManifestSend {
            failures.append("sendBridgeHintMismatch")
        }
        if kind == .apply, candidate.action.bridgeHint != .legacyMetadataManifestApply {
            failures.append("applyBridgeHintMismatch")
        }
        if let local = candidate.localObject, let peer = candidate.peerObject {
            switch kind {
            case .apply:
                if peer.metadata.modifiedAt < local.metadata.modifiedAt {
                    failures.append("modifiedAtDirectionMismatch")
                }
            case .send:
                if local.metadata.modifiedAt < peer.metadata.modifiedAt {
                    failures.append("modifiedAtDirectionMismatch")
                }
            }
            if candidate.expectedObject?.metadata.isDeleted != (kind == .send ? local.metadata.isDeleted : peer.metadata.isDeleted) {
                failures.append("tombstoneStateMismatch")
            }
        }
        return failures
    }

    private nonisolated static func isAllowedRecordingMetadataSideEffect(_ sideEffect: CanonicalProductionSideEffect) -> Bool {
        switch sideEffect.kind {
        case .metadataApply:
            return sideEffect.domain == .recordingMetadata || sideEffect.domain == .apply
        case .networkRequest:
            return sideEffect.route == .applyMetadata
        case .diagnosticsWrite:
            return true
        case .fileRead, .fileWrite, .generatedArtifactApply, .uploadSessionStart, .uploadChunkSend,
             .uploadFinalize, .tombstoneMark, .conflictRecord:
            return false
        }
    }
}
