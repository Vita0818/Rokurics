//
//  MacAudioUploadCutoverExecutor.swift
//  RokuricsMac
//
//  Created by Codex on 2026/6/12.
//

import Foundation

@MainActor
final class MacAudioUploadCutoverExecutor: CanonicalAudioUploadCutoverExecutor, @unchecked Sendable {
    nonisolated static let existingResumableRoutePaths = [
        "/upload-recording-audio-session/start",
        "/upload-recording-audio-session/status",
        "/upload-recording-audio-session/chunk",
        "/upload-recording-audio-session/finalize"
    ]

    nonisolated static let routeContractSummary = [
        "RequestVerifier verifies every existing resumable audio route.",
        "Partial receive sessions are not audioAvailable.",
        "Finalize is the only server-side transition that can prove audioAvailable."
    ].joined(separator: " ")

    private let recordingFileStore: MacRecordingFileStore
    private var rollbackFatalBlocker = false

    init(recordingFileStore: MacRecordingFileStore = MacRecordingFileStore()) {
        self.recordingFileStore = recordingFileStore
    }

    func canExecute(
        _ candidate: CanonicalAudioUploadCutoverCandidate
    ) async -> CanonicalAudioUploadCutoverExecutorReadiness {
        guard !rollbackFatalBlocker else {
            return .blocked(
                objectID: candidate.objectID,
                kind: .rollbackFailure,
                reason: "rollbackFatalBlocker"
            )
        }
        if candidate.trigger.isViewRefresh {
            return .blocked(
                objectID: candidate.objectID,
                kind: .viewRefreshSuppressed,
                reason: "viewRefreshCannotCreateAudioUploadJob"
            )
        }
        if candidate.trigger.isRetryDrainer, !candidate.retryTruth.hasExistingEligibleRetry {
            return .blocked(
                objectID: candidate.objectID,
                kind: .retryDrainerFreshJobSuppressed,
                reason: "retryDrainerCannotCreateFreshAudioUploadJob"
            )
        }

        switch candidate.actionKind {
        case .audioUploadNoOp:
            guard candidate.peerTruth.peerTruthSufficientForNoOp(local: candidate.localTruth) else {
                return .blocked(
                    objectID: candidate.objectID,
                    kind: .completedLedgerNotAudioProof,
                    reason: "noOpRequiresPeerHashAndByteSizeProof"
                )
            }
            return .noOp(reason: "sameHashAndByteSize")
        case .audioUploadDeferredPeerUnknown:
            return .deferred(objectID: candidate.objectID, reason: "peerUnknownDeferred")
        case .audioUploadConflictRecord:
            return .conflict(objectID: candidate.objectID, reason: "existingDifferentAudio")
        case .audioUploadCanaryCandidate:
            guard candidate.evidenceStatus == .complete,
                  candidate.localTruth.sufficientForUploadCandidate else {
                return .blocked(
                    objectID: candidate.objectID,
                    kind: .localAudioIncomplete,
                    reason: "localAudioTruthIncomplete"
                )
            }
            return .executable(reason: "serverFinalizeProofRequired")
        case .audioUploadShadowRehearsal, .unsupported:
            return .blocked(
                objectID: candidate.objectID,
                kind: .unsupportedAction,
                reason: candidate.reason
            )
        }
    }

    func execute(
        _ request: CanonicalAudioUploadCutoverExecutionRequest
    ) async -> CanonicalAudioUploadCutoverExecutionResult {
        let readiness = await canExecute(request.candidate)
        guard readiness.canExecute else {
            return CanonicalAudioUploadCutoverExecutionResult(
                request: request,
                outcome: .blocked,
                state: .blockedPolicy,
                failure: readiness.failure ?? CanonicalAudioUploadCutoverExecutorFailure(
                    objectID: request.candidate.objectID,
                    kind: .policyBlocked,
                    reason: readiness.reason
                )
            )
        }

        switch request.candidate.actionKind {
        case .audioUploadNoOp:
            return result(request: request, outcome: .noOp, completed: true, reason: "sameHashAndByteSize")
        case .audioUploadDeferredPeerUnknown:
            return result(request: request, outcome: .deferred, completed: false, reason: "peerUnknownDeferred")
        case .audioUploadConflictRecord:
            return result(request: request, outcome: .conflict, completed: false, reason: "existingDifferentAudio")
        case .audioUploadCanaryCandidate:
            guard let proof = request.serverFinalizeProof else {
                return CanonicalAudioUploadCutoverExecutionResult(
                    request: request,
                    outcome: .blocked,
                    state: .failedVerification,
                    failure: CanonicalAudioUploadCutoverExecutorFailure(
                        objectID: request.candidate.objectID,
                        kind: .finalizeProofMissing,
                        reason: "macAudioUploadFinalizeProofRequired"
                    )
                )
            }
            return finalizedResult(request: request, proof: proof)
        case .audioUploadShadowRehearsal, .unsupported:
            return CanonicalAudioUploadCutoverExecutionResult(
                request: request,
                outcome: .blocked,
                state: .blockedUnsupported,
                failure: CanonicalAudioUploadCutoverExecutorFailure(
                    objectID: request.candidate.objectID,
                    kind: .unsupportedAction,
                    reason: request.candidate.reason
                )
            )
        }
    }

    func rollbackOrAbort(
        _ request: CanonicalAudioUploadCutoverRollbackRequest
    ) async -> CanonicalAudioUploadCutoverRollbackResult {
        CanonicalAudioUploadCutoverRollbackResult(
            objectID: request.objectID,
            sessionID: request.sessionID,
            succeeded: true,
            fatal: false,
            preFinalizeOnly: true,
            productionAudioDeleted: false,
            receiveRecordDeleted: false,
            reason: "macAudioUploadAbortUsesExistingServerSessionCleanupOnly"
        )
    }

    func startReceive(
        _ request: ResumableAudioUploadStartRequest,
        sourceDevice: PairedDevice
    ) async throws -> ResumableAudioUploadSessionResponse {
        try await recordingFileStore.startResumableAudioUpload(request, sourceDevice: sourceDevice)
    }

    func statusReceive(
        _ request: ResumableAudioUploadStatusRequest,
        sourceDevice: PairedDevice
    ) async throws -> ResumableAudioUploadSessionResponse {
        try await recordingFileStore.resumableAudioUploadStatus(request, sourceDevice: sourceDevice)
    }

    func appendReceiveChunk(
        recordingID: String,
        sessionID: String,
        offset: Int64,
        length: Int,
        chunkSHA256: String,
        totalSHA256: String,
        body: Data,
        sourceDevice: PairedDevice
    ) async throws -> ResumableAudioUploadSessionResponse {
        try await recordingFileStore.appendResumableAudioChunk(
            recordingID: recordingID,
            sessionID: sessionID,
            offset: offset,
            length: length,
            chunkSHA256: chunkSHA256,
            totalSHA256: totalSHA256,
            body: body,
            sourceDevice: sourceDevice
        )
    }

    func finalizeReceive(
        _ request: ResumableAudioUploadFinalizeRequest,
        sourceDevice: PairedDevice,
        cutoverRequest: CanonicalAudioUploadCutoverExecutionRequest? = nil
    ) async throws -> CanonicalAudioUploadCutoverExecutionResult {
        let response = try await recordingFileStore.finalizeResumableAudioUpload(request, sourceDevice: sourceDevice)
        let responseSessionID = CanonicalUploadSessionID(response.sessionID ?? request.sessionID)
        let responseFileSize = response.fileSize ?? request.totalBytes
        let responseHash = response.checksum.map { CanonicalHash($0) }
        let fileSizeVerified = response.completed && response.fileSize == request.totalBytes
        let hashVerified = response.completed && response.checksum == request.totalSHA256
        let receiveRecordCompleted = response.completed && response.receiveStatus == "completed"
        let proof = CanonicalAudioUploadFinalizeProof(
            objectID: request.recordingID,
            sessionID: responseSessionID,
            byteSize: responseFileSize,
            contentHash: responseHash,
            macFileSizeVerified: fileSizeVerified,
            macHashVerified: hashVerified,
            macProofReceived: response.ok,
            receiveRecordMatchesAudioAvailability: receiveRecordCompleted
        )
        let executionRequest = cutoverRequest ?? Self.executionRequest(
            recordingID: request.recordingID,
            totalBytes: request.totalBytes,
            totalSHA256: request.totalSHA256,
            proof: proof
        )
        return finalizedResult(request: executionRequest, proof: proof)
    }

    private func finalizedResult(
        request: CanonicalAudioUploadCutoverExecutionRequest,
        proof: CanonicalAudioUploadFinalizeProof
    ) -> CanonicalAudioUploadCutoverExecutionResult {
        guard proof.objectID == request.candidate.objectID else {
            return CanonicalAudioUploadCutoverExecutionResult(
                request: request,
                outcome: .blocked,
                state: .failedVerification,
                failure: CanonicalAudioUploadCutoverExecutorFailure(
                    objectID: request.candidate.objectID,
                    kind: .finalizeProofRejected,
                    conflict: true,
                    reason: "finalizeProofObjectMismatch"
                )
            )
        }
        guard proof.accepted else {
            return CanonicalAudioUploadCutoverExecutionResult(
                request: request,
                outcome: .blocked,
                state: .failedVerification,
                failure: CanonicalAudioUploadCutoverExecutorFailure(
                    objectID: request.candidate.objectID,
                    kind: .finalizeProofRejected,
                    conflict: true,
                    reason: "finalizeProofRejected"
                )
            )
        }
        guard proof.byteSize == request.candidate.localTruth.byteSize else {
            return CanonicalAudioUploadCutoverExecutionResult(
                request: request,
                outcome: .conflict,
                state: .failedVerification,
                failure: CanonicalAudioUploadCutoverExecutorFailure(
                    objectID: request.candidate.objectID,
                    kind: .finalByteSizeMismatch,
                    conflict: true,
                    reason: "finalizeProofByteSizeMismatch"
                )
            )
        }
        let expectedHashPrefix = request.candidate.localTruth.contentHash
            .map { CanonicalAudioUploadRuntimeRedaction.hashPrefix($0.value) }
        guard expectedHashPrefix == nil || proof.contentHashPrefix == expectedHashPrefix else {
            return CanonicalAudioUploadCutoverExecutionResult(
                request: request,
                outcome: .conflict,
                state: .failedVerification,
                failure: CanonicalAudioUploadCutoverExecutorFailure(
                    objectID: request.candidate.objectID,
                    kind: .finalHashMismatch,
                    conflict: true,
                    reason: "finalizeProofHashMismatch"
                )
            )
        }

        let runtimeResult = CanonicalAudioUploadRuntimeResult(
            mode: request.configuration.mode,
            outcome: .uploaded,
            objectID: request.candidate.objectID,
            sessionID: proof.sessionID,
            confirmedBytes: proof.byteSize,
            completed: true,
            finalizeProof: proof,
            diagnostics: [
                CanonicalAudioUploadDiagnostic(
                    kind: .canonicalAudioUploadRuntimeFinalizeCompleted,
                    syncRunID: request.syncRunID,
                    trigger: request.candidate.trigger,
                    nodeRole: .mac,
                    objectID: request.candidate.objectID,
                    peerState: request.candidate.peerTruth.state,
                    ledgerPhase: request.candidate.ledgerTruth.phase,
                    action: request.candidate.actionKind,
                    result: "verified",
                    reason: "existingServerFinalizeBehavior",
                    hashPrefix: request.candidate.hashPrefix
                )
            ]
        )
        return CanonicalAudioUploadCutoverExecutionResult(
            request: request,
            runtimeResult: runtimeResult,
            postcondition: CanonicalAudioUploadCutoverPostcondition(
                candidate: request.candidate,
                runtimeResult: runtimeResult,
                serverFinalizeProof: proof
            )
        )
    }

    private func result(
        request: CanonicalAudioUploadCutoverExecutionRequest,
        outcome: CanonicalAudioUploadRuntimeOutcome,
        completed: Bool,
        reason: String
    ) -> CanonicalAudioUploadCutoverExecutionResult {
        let runtimeResult = CanonicalAudioUploadRuntimeResult(
            mode: request.configuration.mode,
            outcome: outcome,
            objectID: request.candidate.objectID,
            confirmedBytes: completed ? (request.candidate.localTruth.byteSize ?? 0) : 0,
            completed: completed,
            diagnostics: [
                CanonicalAudioUploadDiagnostic(
                    kind: .canonicalAudioUploadRuntimeReportBuilt,
                    syncRunID: request.syncRunID,
                    trigger: request.candidate.trigger,
                    nodeRole: .mac,
                    objectID: request.candidate.objectID,
                    peerState: request.candidate.peerTruth.state,
                    ledgerPhase: request.candidate.ledgerTruth.phase,
                    action: request.candidate.actionKind,
                    result: outcome.rawValue,
                    reason: reason,
                    hashPrefix: request.candidate.hashPrefix
                )
            ]
        )
        return CanonicalAudioUploadCutoverExecutionResult(request: request, runtimeResult: runtimeResult)
    }

    private nonisolated static func executionRequest(
        recordingID: String,
        totalBytes: Int64,
        totalSHA256: String,
        proof: CanonicalAudioUploadFinalizeProof
    ) -> CanonicalAudioUploadCutoverExecutionRequest {
        let hash = CanonicalHash(totalSHA256)
        let candidate = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: recordingID,
            localTruth: CanonicalAudioUploadLocalTruth.available(
                hash: hash,
                byteSize: totalBytes,
                logicalPathToken: "mac-audio-inbox/\(recordingID)/audio.m4a"
            ),
            peerTruth: CanonicalAudioUploadPeerTruth(state: .missing, diagnosticsSummary: "macReceiveFinalize"),
            trigger: .manualSyncMacHint
        )
        return CanonicalAudioUploadCutoverExecutionRequest(
            candidate: candidate,
            configuration: CanonicalAudioUploadRuntimeConfiguration(
                mode: .canonicalUploadWithLegacyFallback,
                policy: CanonicalAudioUploadRuntimePolicy(
                    debugInternalBuild: true,
                    ownerApprovedCanonicalCommit: true,
                    allowCanonicalUploadWithLegacyFallback: true
                )
            ),
            nodeRole: .mac,
            serverFinalizeProof: proof
        )
    }
}
