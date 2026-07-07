//
//  CanonicalAudioUploadCutoverExecutor.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/12.
//

import Foundation

nonisolated enum CanonicalAudioUploadCutoverExecutorReadinessKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case executable
    case noOp
    case deferred
    case conflict
    case blocked
}

nonisolated enum CanonicalAudioUploadCutoverExecutorFailureKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable, Error {
    case sourceUnavailable
    case localAudioIncomplete
    case peerUnknownDeferred
    case policyBlocked
    case unsupportedAction
    case viewRefreshSuppressed
    case retryDrainerFreshJobSuppressed
    case existingDifferentAudio
    case completedLedgerNotAudioProof
    case metadataOnlyNotAudioAvailable
    case receiveRecordNotAudioProof
    case finalizeProofMissing
    case finalizeProofRejected
    case finalHashMismatch
    case finalByteSizeMismatch
    case securityFailure
    case networkFailure
    case rollbackFailure
    case routeMutationUnsupported
    case requestVerifierBypass
    case dryRunPort
    case unknown
}

nonisolated struct CanonicalAudioUploadCutoverExecutorFailure: Codable, Equatable, Sendable {
    var objectID: String
    var kind: CanonicalAudioUploadCutoverExecutorFailureKind
    var retryable: Bool
    var conflict: Bool
    var securityBoundary: Bool
    var reason: String?

    nonisolated init(
        objectID: String,
        kind: CanonicalAudioUploadCutoverExecutorFailureKind,
        retryable: Bool = false,
        conflict: Bool = false,
        securityBoundary: Bool = false,
        reason: String? = nil
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.kind = kind
        self.retryable = retryable
        self.conflict = conflict || kind == .existingDifferentAudio
        self.securityBoundary = securityBoundary || kind == .securityFailure || kind == .requestVerifierBypass
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason)
    }
}

nonisolated struct CanonicalAudioUploadCutoverExecutorReadiness: Codable, Equatable, Sendable {
    var kind: CanonicalAudioUploadCutoverExecutorReadinessKind
    var canExecute: Bool
    var reason: String?
    var failure: CanonicalAudioUploadCutoverExecutorFailure?

    nonisolated init(
        kind: CanonicalAudioUploadCutoverExecutorReadinessKind,
        canExecute: Bool,
        reason: String? = nil,
        failure: CanonicalAudioUploadCutoverExecutorFailure? = nil
    ) {
        self.kind = kind
        self.canExecute = canExecute
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason)
        self.failure = failure
    }

    nonisolated static func executable(reason: String? = nil) -> CanonicalAudioUploadCutoverExecutorReadiness {
        CanonicalAudioUploadCutoverExecutorReadiness(kind: .executable, canExecute: true, reason: reason)
    }

    nonisolated static func noOp(reason: String? = nil) -> CanonicalAudioUploadCutoverExecutorReadiness {
        CanonicalAudioUploadCutoverExecutorReadiness(kind: .noOp, canExecute: true, reason: reason)
    }

    nonisolated static func deferred(
        objectID: String,
        reason: String
    ) -> CanonicalAudioUploadCutoverExecutorReadiness {
        CanonicalAudioUploadCutoverExecutorReadiness(
            kind: .deferred,
            canExecute: true,
            reason: reason,
            failure: CanonicalAudioUploadCutoverExecutorFailure(
                objectID: objectID,
                kind: .peerUnknownDeferred,
                reason: reason
            )
        )
    }

    nonisolated static func conflict(
        objectID: String,
        reason: String
    ) -> CanonicalAudioUploadCutoverExecutorReadiness {
        CanonicalAudioUploadCutoverExecutorReadiness(
            kind: .conflict,
            canExecute: true,
            reason: reason,
            failure: CanonicalAudioUploadCutoverExecutorFailure(
                objectID: objectID,
                kind: .existingDifferentAudio,
                conflict: true,
                reason: reason
            )
        )
    }

    nonisolated static func blocked(
        objectID: String,
        kind: CanonicalAudioUploadCutoverExecutorFailureKind,
        reason: String,
        retryable: Bool = false,
        conflict: Bool = false,
        securityBoundary: Bool = false
    ) -> CanonicalAudioUploadCutoverExecutorReadiness {
        CanonicalAudioUploadCutoverExecutorReadiness(
            kind: .blocked,
            canExecute: false,
            reason: reason,
            failure: CanonicalAudioUploadCutoverExecutorFailure(
                objectID: objectID,
                kind: kind,
                retryable: retryable,
                conflict: conflict,
                securityBoundary: securityBoundary,
                reason: reason
            )
        )
    }
}

nonisolated struct CanonicalAudioUploadCutoverExecutionRequest: Codable, Equatable, Sendable {
    var candidate: CanonicalAudioUploadCutoverCandidate
    var configuration: CanonicalAudioUploadRuntimeConfiguration
    var syncRunID: String?
    var nodeRole: CanonicalAudioUploadNodeRole
    var legacyFallbackAvailable: Bool
    var now: Date
    var serverFinalizeProof: CanonicalAudioUploadFinalizeProof?

    nonisolated init(
        candidate: CanonicalAudioUploadCutoverCandidate,
        configuration: CanonicalAudioUploadRuntimeConfiguration,
        syncRunID: String? = nil,
        nodeRole: CanonicalAudioUploadNodeRole,
        legacyFallbackAvailable: Bool = true,
        now: Date = Date(),
        serverFinalizeProof: CanonicalAudioUploadFinalizeProof? = nil
    ) {
        self.candidate = candidate
        self.configuration = configuration
        self.syncRunID = CanonicalAudioUploadRuntimeRedaction.safeText(syncRunID)
        self.nodeRole = nodeRole
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.now = now
        self.serverFinalizeProof = serverFinalizeProof
    }

    nonisolated var commitRequest: CanonicalAudioUploadCommitRequest {
        CanonicalAudioUploadCommitRequest(
            candidate: candidate,
            configuration: configuration,
            syncRunID: syncRunID,
            nodeRole: nodeRole
        )
    }
}

nonisolated struct CanonicalAudioUploadCutoverPostcondition: Codable, Equatable, Sendable {
    var objectID: String
    var outcome: CanonicalAudioUploadRuntimeOutcome
    var finalizeProofAccepted: Bool
    var peerSameHashAndByteSizeProofAccepted: Bool
    var macFileSizeVerified: Bool
    var macHashVerified: Bool
    var receiveRecordMatchesAudioAvailability: Bool
    var uploadLedgerCompletedAfterProof: Bool
    var legacyDuplicateSuppressedAfterProof: Bool
    var completedLedgerAloneRejected: Bool
    var metadataOnlyNotAudioAvailable: Bool
    var partialReceiveNotAudioAvailable: Bool
    var existingDifferentAudioNotOverwritten: Bool
    var readPathUnchanged: Bool
    var newRouteAdded: Bool
    var requestVerifierBypassed: Bool
    var reason: String?

    nonisolated init(
        objectID: String,
        outcome: CanonicalAudioUploadRuntimeOutcome,
        finalizeProofAccepted: Bool = false,
        peerSameHashAndByteSizeProofAccepted: Bool = false,
        macFileSizeVerified: Bool = false,
        macHashVerified: Bool = false,
        receiveRecordMatchesAudioAvailability: Bool = false,
        uploadLedgerCompletedAfterProof: Bool = false,
        legacyDuplicateSuppressedAfterProof: Bool = false,
        completedLedgerAloneRejected: Bool = false,
        metadataOnlyNotAudioAvailable: Bool = false,
        partialReceiveNotAudioAvailable: Bool = false,
        existingDifferentAudioNotOverwritten: Bool = true,
        readPathUnchanged: Bool = true,
        newRouteAdded: Bool = false,
        requestVerifierBypassed: Bool = false,
        reason: String? = nil
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.outcome = outcome
        self.finalizeProofAccepted = finalizeProofAccepted
        self.peerSameHashAndByteSizeProofAccepted = peerSameHashAndByteSizeProofAccepted
        self.macFileSizeVerified = macFileSizeVerified
        self.macHashVerified = macHashVerified
        self.receiveRecordMatchesAudioAvailability = receiveRecordMatchesAudioAvailability
        self.uploadLedgerCompletedAfterProof = uploadLedgerCompletedAfterProof
        self.legacyDuplicateSuppressedAfterProof = legacyDuplicateSuppressedAfterProof
        self.completedLedgerAloneRejected = completedLedgerAloneRejected
        self.metadataOnlyNotAudioAvailable = metadataOnlyNotAudioAvailable
        self.partialReceiveNotAudioAvailable = partialReceiveNotAudioAvailable
        self.existingDifferentAudioNotOverwritten = existingDifferentAudioNotOverwritten
        self.readPathUnchanged = readPathUnchanged
        self.newRouteAdded = newRouteAdded
        self.requestVerifierBypassed = requestVerifierBypassed
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason)
    }

    nonisolated init(
        candidate: CanonicalAudioUploadCutoverCandidate,
        runtimeResult: CanonicalAudioUploadRuntimeResult,
        serverFinalizeProof: CanonicalAudioUploadFinalizeProof? = nil
    ) {
        let proof = runtimeResult.finalizeProof ?? serverFinalizeProof
        let peerSameProof = candidate.peerTruth.peerTruthSufficientForNoOp(local: candidate.localTruth)
        let proofAccepted = proof?.accepted == true
        let uploaded = runtimeResult.outcome == .uploaded
        let noOp = runtimeResult.outcome == .noOp
        let receiveOnlyWithoutProof = (candidate.peerTruth.receiveRecordExists || candidate.ledgerTruth.receiveRecordExists)
            && candidate.peerTruth.state != .available
            && !proofAccepted

        self.init(
            objectID: candidate.objectID,
            outcome: runtimeResult.outcome,
            finalizeProofAccepted: uploaded && proofAccepted,
            peerSameHashAndByteSizeProofAccepted: noOp && peerSameProof,
            macFileSizeVerified: proof?.macFileSizeVerified == true,
            macHashVerified: proof?.macHashVerified == true,
            receiveRecordMatchesAudioAvailability: proof?.receiveRecordMatchesAudioAvailability == true,
            uploadLedgerCompletedAfterProof: runtimeResult.completed && (proofAccepted || (noOp && peerSameProof)),
            legacyDuplicateSuppressedAfterProof: (uploaded && proofAccepted) || (noOp && peerSameProof),
            completedLedgerAloneRejected: candidate.ledgerTruth.phase == .completed && !peerSameProof && !noOp,
            metadataOnlyNotAudioAvailable: candidate.peerTruth.state == .metadataOnly && !peerSameProof,
            partialReceiveNotAudioAvailable: receiveOnlyWithoutProof,
            existingDifferentAudioNotOverwritten: runtimeResult.outcome != .conflict
                || candidate.peerTruth.state == .different
                || candidate.peerTruth.state == .available,
            readPathUnchanged: true,
            newRouteAdded: false,
            requestVerifierBypassed: false,
            reason: runtimeResult.legacyFallbackReason ?? candidate.reason
        )
    }

    nonisolated var accepted: Bool {
        guard readPathUnchanged, !newRouteAdded, !requestVerifierBypassed else {
            return false
        }
        switch outcome {
        case .uploaded:
            return finalizeProofAccepted
                && macFileSizeVerified
                && macHashVerified
                && receiveRecordMatchesAudioAvailability
                && uploadLedgerCompletedAfterProof
        case .noOp:
            return peerSameHashAndByteSizeProofAccepted
        case .deferred:
            return !uploadLedgerCompletedAfterProof
        case .conflict:
            return existingDifferentAudioNotOverwritten
        case .legacyFallback, .diagnosticsOnly, .noCommit:
            return !uploadLedgerCompletedAfterProof
        case .blocked, .failed, .retryScheduled:
            return false
        }
    }
}

nonisolated struct CanonicalAudioUploadCutoverExecutionResult: Codable, Equatable, Sendable {
    var objectID: String
    var outcome: CanonicalAudioUploadRuntimeOutcome
    var state: CanonicalAudioUploadCommitResultState
    var runtimeResult: CanonicalAudioUploadRuntimeResult?
    var postcondition: CanonicalAudioUploadCutoverPostcondition
    var legacyFallbackDecision: CanonicalAudioUploadLegacyFallbackDecision
    var failure: CanonicalAudioUploadCutoverExecutorFailure?
    var diagnostics: [CanonicalAudioUploadDiagnostic]

    nonisolated init(
        request: CanonicalAudioUploadCutoverExecutionRequest,
        runtimeResult: CanonicalAudioUploadRuntimeResult,
        failure: CanonicalAudioUploadCutoverExecutorFailure? = nil,
        postcondition: CanonicalAudioUploadCutoverPostcondition? = nil
    ) {
        let resolvedPostcondition = postcondition ?? CanonicalAudioUploadCutoverPostcondition(
            candidate: request.candidate,
            runtimeResult: runtimeResult,
            serverFinalizeProof: request.serverFinalizeProof
        )
        self.objectID = runtimeResult.objectID
        self.outcome = runtimeResult.outcome
        self.state = runtimeResult.commitResultState
        self.runtimeResult = runtimeResult
        self.postcondition = resolvedPostcondition
        self.legacyFallbackDecision = CanonicalAudioUploadLegacyFallbackDecision(
            legacyFallbackAvailable: request.legacyFallbackAvailable,
            legacyFallbackUsed: runtimeResult.usedLegacyFallback,
            suppressLegacyDuplicate: resolvedPostcondition.legacyDuplicateSuppressedAfterProof,
            reason: runtimeResult.legacyFallbackReason
        )
        self.failure = failure ?? Self.failure(from: runtimeResult, candidate: request.candidate)
        self.diagnostics = runtimeResult.diagnostics
    }

    nonisolated init(
        request: CanonicalAudioUploadCutoverExecutionRequest,
        outcome: CanonicalAudioUploadRuntimeOutcome,
        state: CanonicalAudioUploadCommitResultState,
        failure: CanonicalAudioUploadCutoverExecutorFailure,
        diagnostics: [CanonicalAudioUploadDiagnostic] = []
    ) {
        self.objectID = request.candidate.objectID
        self.outcome = outcome
        self.state = state
        self.runtimeResult = nil
        self.postcondition = CanonicalAudioUploadCutoverPostcondition(
            objectID: request.candidate.objectID,
            outcome: outcome,
            completedLedgerAloneRejected: request.candidate.ledgerTruth.phase == .completed,
            metadataOnlyNotAudioAvailable: request.candidate.peerTruth.state == .metadataOnly,
            partialReceiveNotAudioAvailable: request.candidate.peerTruth.receiveRecordExists || request.candidate.ledgerTruth.receiveRecordExists,
            existingDifferentAudioNotOverwritten: true,
            reason: failure.reason
        )
        self.legacyFallbackDecision = CanonicalAudioUploadLegacyFallbackDecision(
            legacyFallbackAvailable: request.legacyFallbackAvailable,
            legacyFallbackUsed: false,
            suppressLegacyDuplicate: false,
            reason: failure.reason
        )
        self.failure = failure
        self.diagnostics = diagnostics
    }

    nonisolated private static func failure(
        from runtimeResult: CanonicalAudioUploadRuntimeResult,
        candidate: CanonicalAudioUploadCutoverCandidate
    ) -> CanonicalAudioUploadCutoverExecutorFailure? {
        switch runtimeResult.outcome {
        case .uploaded, .noOp, .diagnosticsOnly, .noCommit, .legacyFallback:
            return nil
        case .deferred:
            return CanonicalAudioUploadCutoverExecutorFailure(
                objectID: candidate.objectID,
                kind: .peerUnknownDeferred,
                reason: "peerUnknownDeferred"
            )
        case .conflict:
            return CanonicalAudioUploadCutoverExecutorFailure(
                objectID: candidate.objectID,
                kind: .existingDifferentAudio,
                conflict: true,
                reason: "existingDifferentAudio"
            )
        case .blocked:
            return CanonicalAudioUploadCutoverExecutorFailure(
                objectID: candidate.objectID,
                kind: Self.failureKind(from: runtimeResult.runtimeBlockers, candidate: candidate),
                reason: runtimeResult.legacyFallbackReason ?? candidate.reason
            )
        case .retryScheduled:
            let kind: CanonicalAudioUploadCutoverExecutorFailureKind = runtimeResult.runtimeBlockers.contains(.securityFailure)
                ? .securityFailure
                : .networkFailure
            return CanonicalAudioUploadCutoverExecutorFailure(
                objectID: candidate.objectID,
                kind: kind,
                retryable: kind == .networkFailure,
                securityBoundary: kind == .securityFailure,
                reason: runtimeResult.legacyFallbackReason
            )
        case .failed:
            return CanonicalAudioUploadCutoverExecutorFailure(
                objectID: candidate.objectID,
                kind: Self.failureKind(from: runtimeResult.runtimeBlockers, candidate: candidate),
                retryable: false,
                securityBoundary: runtimeResult.runtimeBlockers.contains(.securityFailure),
                reason: runtimeResult.legacyFallbackReason
            )
        }
    }

    nonisolated private static func failureKind(
        from blockers: [CanonicalAudioUploadRuntimeBlocker],
        candidate: CanonicalAudioUploadCutoverCandidate
    ) -> CanonicalAudioUploadCutoverExecutorFailureKind {
        if blockers.contains(.securityFailure) { return .securityFailure }
        if blockers.contains(.finalHashMismatch) { return .finalHashMismatch }
        if blockers.contains(.finalByteSizeMismatch) { return .finalByteSizeMismatch }
        if blockers.contains(.finalProofMissing) { return .finalizeProofMissing }
        if blockers.contains(.existingDifferentAudio) { return .existingDifferentAudio }
        if blockers.contains(.peerUnknown) { return .peerUnknownDeferred }
        if blockers.contains(.localAudioMissing) { return .localAudioIncomplete }
        if blockers.contains(.completedLedgerNotAudioProof) { return .completedLedgerNotAudioProof }
        if blockers.contains(.metadataOnlyNotAudioAvailable) { return .metadataOnlyNotAudioAvailable }
        if blockers.contains(.viewRefreshSuppressed) { return .viewRefreshSuppressed }
        if blockers.contains(.retryDrainerFreshJobSuppressed) { return .retryDrainerFreshJobSuppressed }
        if blockers.contains(.realSecureUploadPortRequired) { return .dryRunPort }
        if candidate.evidenceStatus == .conflict { return .existingDifferentAudio }
        return blockers.contains(.networkFailure) ? .networkFailure : .policyBlocked
    }
}

nonisolated struct CanonicalAudioUploadCutoverRollbackRequest: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID?
    var reason: CanonicalAudioUploadCutoverExecutorFailureKind
    var preFinalizeOnly: Bool

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID? = nil,
        reason: CanonicalAudioUploadCutoverExecutorFailureKind,
        preFinalizeOnly: Bool = true
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.reason = reason
        self.preFinalizeOnly = preFinalizeOnly
    }
}

nonisolated struct CanonicalAudioUploadCutoverRollbackResult: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID?
    var succeeded: Bool
    var fatal: Bool
    var preFinalizeOnly: Bool
    var productionAudioDeleted: Bool
    var receiveRecordDeleted: Bool
    var rollbackResult: CanonicalRollbackResult?
    var reason: String

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID? = nil,
        succeeded: Bool,
        fatal: Bool = false,
        preFinalizeOnly: Bool = true,
        productionAudioDeleted: Bool = false,
        receiveRecordDeleted: Bool = false,
        rollbackResult: CanonicalRollbackResult? = nil,
        reason: String
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.succeeded = succeeded
        self.fatal = fatal
        self.preFinalizeOnly = preFinalizeOnly
        self.productionAudioDeleted = productionAudioDeleted
        self.receiveRecordDeleted = receiveRecordDeleted
        self.rollbackResult = rollbackResult
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason) ?? (succeeded ? "rollbackCompleted" : "rollbackFailed")
    }
}

protocol CanonicalAudioUploadCutoverExecutor: Sendable {
    func canExecute(
        _ candidate: CanonicalAudioUploadCutoverCandidate
    ) async -> CanonicalAudioUploadCutoverExecutorReadiness

    func execute(
        _ request: CanonicalAudioUploadCutoverExecutionRequest
    ) async -> CanonicalAudioUploadCutoverExecutionResult

    func rollbackOrAbort(
        _ request: CanonicalAudioUploadCutoverRollbackRequest
    ) async -> CanonicalAudioUploadCutoverRollbackResult

    func verifyPostcondition(
        _ postcondition: CanonicalAudioUploadCutoverPostcondition
    ) async -> CanonicalAudioUploadCutoverPostcondition

    func redactDiagnostics(
        _ diagnostics: [CanonicalAudioUploadDiagnostic]
    ) -> [CanonicalAudioUploadDiagnostic]
}

extension CanonicalAudioUploadCutoverExecutor {
    nonisolated func redactDiagnostics(
        _ diagnostics: [CanonicalAudioUploadDiagnostic]
    ) -> [CanonicalAudioUploadDiagnostic] {
        Array(diagnostics.prefix(128))
    }

    nonisolated func verifyPostcondition(
        _ postcondition: CanonicalAudioUploadCutoverPostcondition
    ) async -> CanonicalAudioUploadCutoverPostcondition {
        postcondition
    }
}
