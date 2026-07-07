//
//  IPhoneAudioUploadCutoverExecutor.swift
//  Rokurics
//
//  Created by Codex on 2026/6/12.
//

import Foundation

actor IPhoneAudioUploadCutoverExecutor: CanonicalAudioUploadCutoverExecutor {
    private let source: any CanonicalAudioUploadByteSource
    private let uploadPort: any CanonicalProductionUploadPort
    private let jobStore: CanonicalAudioUploadJobStore
    private let runtimeExecutor: CanonicalAudioUploadRuntimeExecutor
    private var rollbackFatalBlocker = false

    init(
        source: any CanonicalAudioUploadByteSource,
        uploadPort: any CanonicalProductionUploadPort,
        jobStore: CanonicalAudioUploadJobStore = CanonicalAudioUploadJobStore(),
        runtimeExecutor: CanonicalAudioUploadRuntimeExecutor = CanonicalAudioUploadRuntimeExecutor()
    ) {
        self.source = source
        self.uploadPort = uploadPort
        self.jobStore = jobStore
        self.runtimeExecutor = runtimeExecutor
    }

    init(
        metadata: RecordingMetadata,
        settings: SecureMacConnectionSnapshot,
        audioFileStore: AudioFileStore = AudioFileStore(),
        transport: any RecordingSecureUploadTransport = SecureMacUploadClient(),
        jobStore: CanonicalAudioUploadJobStore = CanonicalAudioUploadJobStore(),
        runtimeExecutor: CanonicalAudioUploadRuntimeExecutor = CanonicalAudioUploadRuntimeExecutor(),
        preferredChunkSize: Int = 4 * 1024 * 1024
    ) async throws {
        let fileSource = try await IPhoneCanonicalAudioUploadFileSource(
            metadata: metadata,
            audioFileStore: audioFileStore,
            preferredChunkSize: preferredChunkSize
        )
        let securePort = IPhoneCanonicalSecureAudioUploadPort(
            settings: settings,
            transport: transport,
            chunkSizePolicy: preferredChunkSize
        )
        self.init(
            source: fileSource,
            uploadPort: securePort,
            jobStore: jobStore,
            runtimeExecutor: runtimeExecutor
        )
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
        if candidate.trigger.isRetryDrainer {
            let storeHasRetry = await jobStore.hasEligibleRetry(objectID: candidate.objectID, now: Date())
            if !candidate.retryTruth.hasExistingEligibleRetry && !storeHasRetry {
                return .blocked(
                    objectID: candidate.objectID,
                    kind: .retryDrainerFreshJobSuppressed,
                    reason: "retryDrainerCannotCreateFreshAudioUploadJob"
                )
            }
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
            return uploadReadiness(candidate)
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

        let runtimeResult = await runtimeExecutor.execute(
            candidate: request.candidate,
            source: source,
            uploadPort: uploadPort,
            jobStore: jobStore,
            configuration: request.configuration,
            syncRunID: request.syncRunID,
            nodeRole: request.nodeRole,
            now: request.now
        )
        var result = CanonicalAudioUploadCutoverExecutionResult(
            request: request,
            runtimeResult: runtimeResult
        )

        if runtimeResult.outcome == .uploaded, !result.postcondition.finalizeProofAccepted {
            result.failure = CanonicalAudioUploadCutoverExecutorFailure(
                objectID: request.candidate.objectID,
                kind: .finalizeProofMissing,
                conflict: true,
                reason: "uploadedRequiresFinalizedMacProof"
            )
            result.outcome = .failed
            result.state = .failedVerification
        }
        if result.failure?.kind == .securityFailure {
            result.legacyFallbackDecision = CanonicalAudioUploadLegacyFallbackDecision(
                legacyFallbackAvailable: request.legacyFallbackAvailable,
                legacyFallbackUsed: false,
                suppressLegacyDuplicate: runtimeResult.startedTransport,
                reason: result.failure?.reason ?? "securityFailure"
            )
        }

        return result
    }

    func rollbackOrAbort(
        _ request: CanonicalAudioUploadCutoverRollbackRequest
    ) async -> CanonicalAudioUploadCutoverRollbackResult {
        do {
            let ledger = try await uploadPort.readUploadLedger(objectID: request.objectID)
            if ledger.phase == .completed {
                return CanonicalAudioUploadCutoverRollbackResult(
                    objectID: request.objectID,
                    sessionID: ledger.sessionID,
                    succeeded: false,
                    fatal: false,
                    preFinalizeOnly: true,
                    reason: "finalizedUploadCannotBeRolledBack"
                )
            }

            let sessionID = request.sessionID ?? ledger.sessionID
            let rollback = try await uploadPort.rollbackUploadState(
                CanonicalProductionUploadRollbackRequest(
                    objectID: request.objectID,
                    sessionID: sessionID,
                    checkpointID: "iphone-audio-upload-pre-finalize-\(request.objectID)"
                )
            )
            if let sessionID {
                _ = try await uploadPort.cancelUpload(
                    CanonicalProductionUploadCancelRequest(
                        objectID: request.objectID,
                        sessionID: sessionID,
                        reason: request.reason.rawValue
                    ),
                    now: Date()
                )
            }
            return CanonicalAudioUploadCutoverRollbackResult(
                objectID: request.objectID,
                sessionID: sessionID,
                succeeded: rollback.succeeded,
                fatal: !rollback.succeeded,
                preFinalizeOnly: true,
                productionAudioDeleted: false,
                receiveRecordDeleted: false,
                rollbackResult: rollback,
                reason: rollback.succeeded ? "iphoneAudioUploadPreFinalizeAbortCompleted" : "iphoneAudioUploadPreFinalizeAbortFailed"
            )
        } catch {
            rollbackFatalBlocker = true
            return CanonicalAudioUploadCutoverRollbackResult(
                objectID: request.objectID,
                sessionID: request.sessionID,
                succeeded: false,
                fatal: true,
                preFinalizeOnly: true,
                reason: "iphoneAudioUploadRollbackFailed"
            )
        }
    }

    func verifyPostcondition(
        _ postcondition: CanonicalAudioUploadCutoverPostcondition
    ) async -> CanonicalAudioUploadCutoverPostcondition {
        postcondition
    }

    private func uploadReadiness(
        _ candidate: CanonicalAudioUploadCutoverCandidate
    ) -> CanonicalAudioUploadCutoverExecutorReadiness {
        guard candidate.evidenceStatus == .complete,
              candidate.localTruth.sufficientForUploadCandidate else {
            return .blocked(
                objectID: candidate.objectID,
                kind: .localAudioIncomplete,
                reason: "localAudioTruthIncomplete"
            )
        }
        guard source.objectID == candidate.objectID else {
            return .blocked(
                objectID: candidate.objectID,
                kind: .sourceUnavailable,
                reason: "sourceObjectMismatch"
            )
        }
        guard source.byteSize == candidate.localTruth.byteSize else {
            return .blocked(
                objectID: candidate.objectID,
                kind: .finalByteSizeMismatch,
                reason: "sourceByteSizeMismatch"
            )
        }
        guard source.contentHash == candidate.localTruth.contentHash else {
            return .blocked(
                objectID: candidate.objectID,
                kind: .finalHashMismatch,
                reason: "sourceHashMismatch"
            )
        }
        guard uploadPort.resumableSessionSupported else {
            return .blocked(
                objectID: candidate.objectID,
                kind: .routeMutationUnsupported,
                reason: "existingResumableSecureRoutesRequired"
            )
        }
        guard !uploadPort.isDryRunOnly else {
            return .blocked(
                objectID: candidate.objectID,
                kind: .dryRunPort,
                reason: "audioUploadCommitRequiresRealOrTestTransportPort"
            )
        }
        return .executable(reason: candidate.reason)
    }
}
