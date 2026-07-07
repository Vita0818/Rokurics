//
//  CanonicalUploadStateTruth.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/11.
//

import Foundation

nonisolated enum CanonicalUploadStateSource: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case localAudioFile
    case localAudioHashSize
    case localCanonicalUploadJobStore
    case localLegacyUploadLedger
    case retryQueue
    case peerInventoryRecordingExistence
    case peerMetadataOnly
    case peerReceiveRecordOnly
    case peerStudyItemOnly
    case peerAudioAvailable
    case peerAudioHashSize
    case macReceiveSession
    case macFinalizedAudio
    case macReceiveInboxMetadata
    case canonicalExistenceLedger
    case tombstoneConflict
}

nonisolated enum CanonicalUploadStateDecision: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case absentLocalAudio
    case peerUnknownDeferred
    case peerMetadataOnlyNeedsUpload
    case peerReceiveRecordOnlyNeedsUpload
    case peerStudyItemOnlyNeedsUpload
    case uploadPending
    case uploadStarting
    case uploadInProgress
    case uploadInterrupted
    case uploadRetryScheduled
    case uploadFinalizing
    case uploadFinalizedProofPending
    case uploadCompletedVerified
    case uploadNoOpSameAudio
    case uploadConflictDifferentAudio
    case uploadBlockedTombstoned
    case uploadBlockedPolicy
    case uploadFailedNetwork
    case uploadFailedSecurity
    case uploadFailedVerification
    case uploadLegacyFallback
    case uploadUnsupported
}

nonisolated enum CanonicalUploadStateBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingLocalAudio
    case localAudioHashSizeMissing
    case staleLocalAudioFile
    case invalidLocalFileToken
    case peerUnknown
    case metadataOnlyNotAudioAvailable
    case receiveRecordOnlyNotAudioAvailable
    case studyItemOnlyNotAudioAvailable
    case completedLedgerRejectedAsProof
    case finalizedProofMissing
    case finalizedProofRejected
    case expectedManifestHashNotPeerProof
    case differentHashOrSizeConflict
    case tombstonedParent
    case uploadJobCannotOverridePeerConflict
    case malformedLedger
    case retryBackoff
    case maxRetriesReached
    case securityFailure
    case policyBlocked
    case viewRefreshCannotCreateUploadJob
    case retryDrainerCannotCreateFreshJob
    case duplicateCanonicalLegacyJob
    case unsupported
}

nonisolated enum CanonicalUploadPeerInventoryState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case unknown
    case missing
    case metadataOnly
    case receiveRecordOnly
    case studyItemOnly
    case audioAvailable
    case conflict
    case tombstoned
    case unsupported
}

nonisolated enum CanonicalUploadMacReceiveSessionState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case partial
    case finalizing
    case finalized
    case failed
    case aborted
    case conflict
}

nonisolated enum CanonicalUploadDiagnosticEvent: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalUploadStateTruthEvaluated
    case canonicalUploadStateReconciled
    case canonicalUploadStateReconciliationBlocked
    case canonicalUploadRetryDrainEvaluated
    case canonicalUploadRetryDrainResumedExistingJob
    case canonicalUploadRetryDrainSkippedPeerUnknown
    case canonicalUploadRetryDrainSkippedConflict
    case canonicalUploadRetryDrainSkippedMissingLocalAudio
    case canonicalUploadRetryDrainSkippedTombstoned
    case canonicalUploadRetryDrainBackoffApplied
    case canonicalUploadRetryDrainMaxRetriesReached
    case canonicalUploadRetryDrainDidNotCreateFreshJob
    case canonicalUploadDuplicateJobSuppressed
    case canonicalUploadDuplicateJobDetected
    case canonicalUploadOwnershipSelectedCanonical
    case canonicalUploadOwnershipSelectedLegacy
    case canonicalUploadOwnershipFallbackLegacy
    case canonicalUploadCompletedLedgerRejectedAsProof
    case canonicalUploadMetadataOnlyRejectedAsAudioAvailable
    case canonicalUploadPeerUnknownDeferred
    case canonicalUploadExistingDifferentAudioConflict
    case canonicalUploadFinalizedProofAccepted
    case canonicalUploadFinalizedProofMissing
    case canonicalUploadRestartRecoveryStarted
    case canonicalUploadRestartRecoveryCompleted
    case canonicalUploadRestartRecoveryBlocked
    case canonicalUploadStatusProjectionBuilt
}

nonisolated struct CanonicalUploadStateDiagnostic: Codable, Equatable, Sendable {
    var kind: CanonicalUploadDiagnosticEvent
    var objectID: String
    var state: CanonicalUploadStateDecision?
    var reason: String?
    var retryCount: Int?
    var offset: Int64?
    var confirmedBytes: Int64?
    var totalBytes: Int64?
    var chunkSize: Int?
    var hashPrefix: String?
    var sessionIDPrefix: String?
    var durationMs: Int?

    nonisolated init(
        kind: CanonicalUploadDiagnosticEvent,
        objectID: String,
        state: CanonicalUploadStateDecision? = nil,
        reason: String? = nil,
        retryCount: Int? = nil,
        offset: Int64? = nil,
        confirmedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        chunkSize: Int? = nil,
        hash: CanonicalHash? = nil,
        hashPrefix: String? = nil,
        sessionID: CanonicalAudioUploadSessionID? = nil,
        sessionIDPrefix: String? = nil,
        durationMs: Int? = nil
    ) {
        self.kind = kind
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.state = state
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason)
        self.retryCount = retryCount.map { max(0, $0) }
        self.offset = offset.map { max(0, $0) }
        self.confirmedBytes = confirmedBytes.map { max(0, $0) }
        self.totalBytes = totalBytes.map { max(0, $0) }
        self.chunkSize = chunkSize.map { max(1, $0) }
        self.hashPrefix = hash.flatMap { CanonicalAudioUploadRuntimeRedaction.hashPrefix($0.value) }
            ?? CanonicalAudioUploadRuntimeRedaction.hashPrefix(hashPrefix)
        self.sessionIDPrefix = sessionID.map { String($0.rawValue.prefix(12)) }
            ?? CanonicalAudioUploadRuntimeRedaction.hashPrefix(sessionIDPrefix)
        self.durationMs = durationMs.map { max(0, $0) }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "kind=\(kind.rawValue)",
            "objectID=\(objectID)",
            state.map { "state=\($0.rawValue)" },
            reason.map { "reason=\($0)" },
            retryCount.map { "retryCount=\($0)" },
            offset.map { "offset=\($0)" },
            confirmedBytes.map { "confirmedBytes=\($0)" },
            totalBytes.map { "totalBytes=\($0)" },
            chunkSize.map { "chunkSize=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" },
            sessionIDPrefix.map { "sessionIDPrefix=\($0)" },
            durationMs.map { "durationMs=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }
}

nonisolated enum CanonicalAudioUploadAvailability: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case notAvailable
    case metadataOnly
    case receiveRecordOnly
    case studyItemOnly
    case audioAvailable
    case partialReceive
    case failedReceive
    case deferredPeerUnknown
    case conflict
    case blocked

    nonisolated init(
        peerInventoryState: CanonicalUploadPeerInventoryState,
        macReceiveSessionState: CanonicalUploadMacReceiveSessionState = .none
    ) {
        switch macReceiveSessionState {
        case .partial, .finalizing:
            self = .partialReceive
            return
        case .failed, .aborted:
            self = .failedReceive
            return
        case .conflict:
            self = .conflict
            return
        case .none, .finalized:
            break
        }

        switch peerInventoryState {
        case .unknown:
            self = .deferredPeerUnknown
        case .missing:
            self = .notAvailable
        case .metadataOnly:
            self = .metadataOnly
        case .receiveRecordOnly:
            self = .receiveRecordOnly
        case .studyItemOnly:
            self = .studyItemOnly
        case .audioAvailable:
            self = .audioAvailable
        case .conflict:
            self = .conflict
        case .tombstoned, .unsupported:
            self = .blocked
        }
    }
}

nonisolated enum CanonicalAudioUploadReadStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case notAvailable
    case metadataOnly
    case uploadNeeded
    case pending
    case uploading
    case interrupted
    case retryScheduled
    case finalizing
    case uploadedVerified
    case noOpSameAudio
    case conflict
    case deferredPeerUnknown
    case blocked
    case failed

    nonisolated init(_ decision: CanonicalUploadStateDecision) {
        switch decision {
        case .absentLocalAudio:
            self = .notAvailable
        case .peerUnknownDeferred:
            self = .deferredPeerUnknown
        case .peerMetadataOnlyNeedsUpload:
            self = .metadataOnly
        case .peerReceiveRecordOnlyNeedsUpload, .peerStudyItemOnlyNeedsUpload, .uploadPending:
            self = .uploadNeeded
        case .uploadStarting:
            self = .pending
        case .uploadInProgress:
            self = .uploading
        case .uploadInterrupted:
            self = .interrupted
        case .uploadRetryScheduled:
            self = .retryScheduled
        case .uploadFinalizing, .uploadFinalizedProofPending:
            self = .finalizing
        case .uploadCompletedVerified:
            self = .uploadedVerified
        case .uploadNoOpSameAudio:
            self = .noOpSameAudio
        case .uploadConflictDifferentAudio:
            self = .conflict
        case .uploadBlockedTombstoned, .uploadBlockedPolicy, .uploadUnsupported:
            self = .blocked
        case .uploadFailedNetwork, .uploadFailedSecurity, .uploadFailedVerification, .uploadLegacyFallback:
            self = .failed
        }
    }
}

nonisolated struct CanonicalAudioUploadProofSchema: Codable, Equatable, Sendable {
    static let version = "canonical-audio-upload-v1"

    var version: String
    var noOpRequiresSameHashAndByteSize: Bool
    var uploadCompletedRequiresFinalizedMacProof: Bool
    var completedLedgerAloneRejected: Bool
    var metadataOnlyRejectedAsAudioAvailable: Bool
    var receiveRecordOnlyRejectedAsAudioAvailable: Bool
    var peerUnknownDeferred: Bool
    var differentHashOrSizeConflicts: Bool
    var expectedManifestHashNotPeerProof: Bool
    var partialReceiveRejectedAsAudioAvailable: Bool
    var failedSessionRejectedAsAudioAvailable: Bool
    var retryCannotOverridePeerConflict: Bool
    var duplicateJobSuppressionRequiresOwnership: Bool

    nonisolated init(
        version: String = Self.version,
        noOpRequiresSameHashAndByteSize: Bool = true,
        uploadCompletedRequiresFinalizedMacProof: Bool = true,
        completedLedgerAloneRejected: Bool = true,
        metadataOnlyRejectedAsAudioAvailable: Bool = true,
        receiveRecordOnlyRejectedAsAudioAvailable: Bool = true,
        peerUnknownDeferred: Bool = true,
        differentHashOrSizeConflicts: Bool = true,
        expectedManifestHashNotPeerProof: Bool = true,
        partialReceiveRejectedAsAudioAvailable: Bool = true,
        failedSessionRejectedAsAudioAvailable: Bool = true,
        retryCannotOverridePeerConflict: Bool = true,
        duplicateJobSuppressionRequiresOwnership: Bool = true
    ) {
        self.version = version
        self.noOpRequiresSameHashAndByteSize = noOpRequiresSameHashAndByteSize
        self.uploadCompletedRequiresFinalizedMacProof = uploadCompletedRequiresFinalizedMacProof
        self.completedLedgerAloneRejected = completedLedgerAloneRejected
        self.metadataOnlyRejectedAsAudioAvailable = metadataOnlyRejectedAsAudioAvailable
        self.receiveRecordOnlyRejectedAsAudioAvailable = receiveRecordOnlyRejectedAsAudioAvailable
        self.peerUnknownDeferred = peerUnknownDeferred
        self.differentHashOrSizeConflicts = differentHashOrSizeConflicts
        self.expectedManifestHashNotPeerProof = expectedManifestHashNotPeerProof
        self.partialReceiveRejectedAsAudioAvailable = partialReceiveRejectedAsAudioAvailable
        self.failedSessionRejectedAsAudioAvailable = failedSessionRejectedAsAudioAvailable
        self.retryCannotOverridePeerConflict = retryCannotOverridePeerConflict
        self.duplicateJobSuppressionRequiresOwnership = duplicateJobSuppressionRequiresOwnership
    }

    nonisolated var isV855Frozen: Bool {
        version == Self.version
            && noOpRequiresSameHashAndByteSize
            && uploadCompletedRequiresFinalizedMacProof
            && completedLedgerAloneRejected
            && metadataOnlyRejectedAsAudioAvailable
            && receiveRecordOnlyRejectedAsAudioAvailable
            && peerUnknownDeferred
            && differentHashOrSizeConflicts
            && expectedManifestHashNotPeerProof
            && partialReceiveRejectedAsAudioAvailable
            && failedSessionRejectedAsAudioAvailable
            && retryCannotOverridePeerConflict
            && duplicateJobSuppressionRequiresOwnership
    }
}

nonisolated struct CanonicalAudioUploadDomainFields: Codable, Equatable, Sendable {
    var schemaVersion: String
    var recordingID: String
    var objectID: String
    var localAudioExists: Bool
    var localAudioByteSize: Int64?
    var localAudioHashPrefix: String?
    var localAudioSafeFileToken: String?
    var peerRecordingExistence: CanonicalUploadPeerInventoryState
    var peerAudioAvailability: CanonicalAudioUploadAvailability
    var peerAudioAvailable: Bool
    var peerAudioByteSize: Int64?
    var peerAudioHashPrefix: String?
    var uploadSessionIDPrefix: String?
    var confirmedBytes: Int64?
    var finalizeProofAccepted: Bool
    var retryState: String?
    var conflictState: Bool
    var modifiedAtSummary: String?

    nonisolated init(
        schemaVersion: String = CanonicalAudioUploadProofSchema.version,
        recordingID: String,
        objectID: String,
        localAudioExists: Bool,
        localAudioByteSize: Int64?,
        localAudioHash: CanonicalHash?,
        localAudioHashPrefix: String? = nil,
        localAudioSafeFileToken: String? = nil,
        peerRecordingExistence: CanonicalUploadPeerInventoryState,
        peerAudioAvailability: CanonicalAudioUploadAvailability,
        peerAudioAvailable: Bool,
        peerAudioByteSize: Int64? = nil,
        peerAudioHash: CanonicalHash? = nil,
        peerAudioHashPrefix: String? = nil,
        uploadSessionID: CanonicalAudioUploadSessionID? = nil,
        uploadSessionIDPrefix: String? = nil,
        confirmedBytes: Int64? = nil,
        finalizeProofAccepted: Bool = false,
        retryState: String? = nil,
        conflictState: Bool = false,
        modifiedAtSummary: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.recordingID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(recordingID, fallback: "unknown-recording")
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.localAudioExists = localAudioExists
        self.localAudioByteSize = localAudioByteSize.map { max(0, $0) }
        self.localAudioHashPrefix = localAudioHash.flatMap { CanonicalAudioUploadRuntimeRedaction.hashPrefix($0.value) }
            ?? CanonicalAudioUploadRuntimeRedaction.hashPrefix(localAudioHashPrefix)
        self.localAudioSafeFileToken = CanonicalProjectionContract.safeLogicalPathToken(localAudioSafeFileToken)
        self.peerRecordingExistence = peerRecordingExistence
        self.peerAudioAvailability = peerAudioAvailability
        self.peerAudioAvailable = peerAudioAvailable
        self.peerAudioByteSize = peerAudioByteSize.map { max(0, $0) }
        self.peerAudioHashPrefix = peerAudioHash.flatMap { CanonicalAudioUploadRuntimeRedaction.hashPrefix($0.value) }
            ?? CanonicalAudioUploadRuntimeRedaction.hashPrefix(peerAudioHashPrefix)
        self.uploadSessionIDPrefix = uploadSessionID.map { String($0.rawValue.prefix(12)) }
            ?? CanonicalAudioUploadRuntimeRedaction.hashPrefix(uploadSessionIDPrefix)
        self.confirmedBytes = confirmedBytes.map { max(0, $0) }
        self.finalizeProofAccepted = finalizeProofAccepted
        self.retryState = CanonicalAudioUploadRuntimeRedaction.safeText(retryState)
        self.conflictState = conflictState
        self.modifiedAtSummary = CanonicalAudioUploadRuntimeRedaction.safeText(modifiedAtSummary)
    }

    nonisolated init(truth: CanonicalUploadStateTruth) {
        self.init(
            recordingID: truth.objectID,
            objectID: truth.objectID,
            localAudioExists: truth.localAudioExists,
            localAudioByteSize: truth.localByteSize,
            localAudioHash: truth.localContentHash,
            peerRecordingExistence: truth.peerInventoryState,
            peerAudioAvailability: CanonicalAudioUploadAvailability(
                peerInventoryState: truth.peerInventoryState,
                macReceiveSessionState: truth.macReceiveSessionState
            ),
            peerAudioAvailable: truth.peerInventoryState == .audioAvailable && truth.peerHashSizeProven,
            peerAudioByteSize: truth.peerByteSize,
            peerAudioHash: truth.peerContentHash,
            uploadSessionID: nil,
            confirmedBytes: truth.macConfirmedBytes,
            finalizeProofAccepted: truth.macFinalizedProof?.accepted == true,
            retryState: truth.canonicalJobState?.rawValue ?? truth.legacyLedgerTruth.phase.rawValue,
            conflictState: truth.conflictRecorded || truth.peerInventoryState == .conflict || truth.canonicalExistenceState == .audioConflict,
            modifiedAtSummary: truth.localAudioExists ? "localAudioMTimeStatusOnly" : nil
        )
    }

    nonisolated init(candidate: CanonicalAudioUploadCutoverCandidate) {
        self.init(
            recordingID: candidate.objectID,
            objectID: candidate.objectID,
            localAudioExists: candidate.localTruth.audioAvailable,
            localAudioByteSize: candidate.localTruth.byteSize,
            localAudioHash: candidate.localTruth.contentHash,
            localAudioSafeFileToken: candidate.localTruth.logicalPathToken,
            peerRecordingExistence: CanonicalUploadPeerInventoryState(candidate.peerTruth.state),
            peerAudioAvailability: CanonicalAudioUploadAvailability(peerInventoryState: CanonicalUploadPeerInventoryState(candidate.peerTruth.state)),
            peerAudioAvailable: candidate.peerTruth.state == .available && candidate.peerTruth.contentHash != nil && candidate.peerTruth.byteSize != nil,
            peerAudioByteSize: candidate.peerTruth.byteSize,
            peerAudioHash: candidate.peerTruth.contentHash,
            confirmedBytes: nil,
            finalizeProofAccepted: false,
            retryState: candidate.retryTruth.retryPending ? "retryPending" : candidate.ledgerTruth.phase.rawValue,
            conflictState: candidate.evidenceStatus == .conflict || candidate.actionKind == .audioUploadConflictRecord,
            modifiedAtSummary: candidate.localTruth.modifiedAt.map { "unixSeconds=\(Int($0.date.timeIntervalSince1970))" }
        )
    }

    nonisolated var diagnosticsSummary: String {
        [
            "schema=\(schemaVersion)",
            "recordingID=\(recordingID)",
            "objectID=\(objectID)",
            "localAudioExists=\(localAudioExists)",
            localAudioByteSize.map { "localByteSize=\($0)" },
            localAudioHashPrefix.map { "localHashPrefix=\($0)" },
            localAudioSafeFileToken.map { "localFileToken=\($0)" },
            "peerState=\(peerRecordingExistence.rawValue)",
            "availability=\(peerAudioAvailability.rawValue)",
            "peerAudioAvailable=\(peerAudioAvailable)",
            peerAudioByteSize.map { "peerByteSize=\($0)" },
            peerAudioHashPrefix.map { "peerHashPrefix=\($0)" },
            uploadSessionIDPrefix.map { "sessionIDPrefix=\($0)" },
            confirmedBytes.map { "confirmedBytes=\($0)" },
            "finalizeProofAccepted=\(finalizeProofAccepted)",
            retryState.map { "retryState=\($0)" },
            "conflict=\(conflictState)",
            "redacted=true"
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated struct CanonicalAudioUploadOwnershipPolicy: Codable, Equatable, Sendable {
    var mode: CanonicalUploadOwnershipMode
    var gateAllowsCanonical: Bool
    var legacyFallbackAvailable: Bool
    var legacyJobRunning: Bool
    var canonicalSecurityFailure: Bool

    nonisolated init(
        mode: CanonicalUploadOwnershipMode,
        gateAllowsCanonical: Bool = false,
        legacyFallbackAvailable: Bool = true,
        legacyJobRunning: Bool = false,
        canonicalSecurityFailure: Bool = false
    ) {
        self.mode = mode
        self.gateAllowsCanonical = gateAllowsCanonical
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.legacyJobRunning = legacyJobRunning
        self.canonicalSecurityFailure = canonicalSecurityFailure
    }

    nonisolated func evaluate(
        objectID: String,
        stateReport: CanonicalUploadStateReconciliationReport,
        canonicalJobStarted: Bool = false,
        canonicalFailedBeforePeerData: Bool = false,
        canonicalFinalizeSucceeded: Bool = false,
        canonicalFinalizeProofAccepted: Bool = false
    ) -> CanonicalUploadOwnershipDecision {
        let canonicalConflict = stateReport.decision == .uploadConflictDifferentAudio
        let canonicalBlockedBeforeStart = !stateReport.shouldCreateUploadJob
            && stateReport.decision != .uploadNoOpSameAudio
            && stateReport.decision != .uploadCompletedVerified
        return CanonicalUploadDuplicateJobGuard.evaluate(
            objectID: objectID,
            mode: mode,
            gateAllowsCanonical: gateAllowsCanonical && stateReport.shouldCreateUploadJob,
            viewRefresh: stateReport.blockers.contains(.viewRefreshCannotCreateUploadJob),
            peerUnknownDeferred: stateReport.decision == .peerUnknownDeferred,
            canonicalJobStarted: canonicalJobStarted,
            canonicalBlockedBeforeStart: canonicalBlockedBeforeStart,
            canonicalFailedBeforePeerData: canonicalFailedBeforePeerData,
            canonicalSecurityFailure: canonicalSecurityFailure,
            canonicalConflict: canonicalConflict,
            canonicalFinalizeSucceeded: canonicalFinalizeSucceeded,
            canonicalFinalizeProofAccepted: canonicalFinalizeProofAccepted,
            legacyJobRunning: legacyJobRunning,
            legacyFallbackAvailable: legacyFallbackAvailable
        )
    }
}

nonisolated struct CanonicalAudioUploadDecisionInput: Codable, Equatable, Sendable {
    var fields: CanonicalAudioUploadDomainFields
    var truth: CanonicalUploadStateTruth
    var proofSchema: CanonicalAudioUploadProofSchema
    var ownershipPolicy: CanonicalAudioUploadOwnershipPolicy

    nonisolated init(
        truth: CanonicalUploadStateTruth,
        ownershipPolicy: CanonicalAudioUploadOwnershipPolicy,
        proofSchema: CanonicalAudioUploadProofSchema = CanonicalAudioUploadProofSchema()
    ) {
        self.fields = CanonicalAudioUploadDomainFields(truth: truth)
        self.truth = truth
        self.proofSchema = proofSchema
        self.ownershipPolicy = ownershipPolicy
    }
}

nonisolated struct CanonicalAudioUploadDecisionResult: Codable, Equatable, Sendable {
    var fields: CanonicalAudioUploadDomainFields
    var readStatus: CanonicalAudioUploadReadStatus
    var availability: CanonicalAudioUploadAvailability
    var stateReport: CanonicalUploadStateReconciliationReport
    var ownershipDecision: CanonicalUploadOwnershipDecision
    var canonicalDecisionEvaluated: Bool
    var canonicalDecisionUsed: Bool
    var canonicalCommitAllowed: Bool
    var legacyFallbackAllowed: Bool
    var proofSchema: CanonicalAudioUploadProofSchema
    var diagnostics: [CanonicalUploadStateDiagnostic]
    var diagnosticsSummary: String

    nonisolated init(
        input: CanonicalAudioUploadDecisionInput,
        now: Date = Date()
    ) {
        let stateReport = input.truth.reconcile(now: now)
        let ownershipDecision = input.ownershipPolicy.evaluate(
            objectID: input.truth.objectID,
            stateReport: stateReport
        )
        let readStatus = CanonicalAudioUploadReadStatus(stateReport.decision)
        let availability = CanonicalAudioUploadAvailability(
            peerInventoryState: input.truth.peerInventoryState,
            macReceiveSessionState: input.truth.macReceiveSessionState
        )
        let canonicalDecisionEvaluated = input.ownershipPolicy.mode != .oldKernel && input.ownershipPolicy.mode != .blocked
        let canonicalDecisionUsed = ownershipDecision.owner == .canonical && input.proofSchema.isV855Frozen

        self.fields = input.fields
        self.readStatus = readStatus
        self.availability = availability
        self.stateReport = stateReport
        self.ownershipDecision = ownershipDecision
        self.canonicalDecisionEvaluated = canonicalDecisionEvaluated
        self.canonicalDecisionUsed = canonicalDecisionUsed
        self.canonicalCommitAllowed = canonicalDecisionUsed && ownershipDecision.canonicalJobAllowed
        self.legacyFallbackAllowed = ownershipDecision.allowLegacyFallback
        self.proofSchema = input.proofSchema
        self.diagnostics = stateReport.diagnostics + ownershipDecision.diagnostics
        self.diagnosticsSummary = [
            "canonicalAudioUploadDecision=v8.55-p2-5",
            "schema=\(input.proofSchema.version)",
            "objectID=\(input.truth.objectID)",
            "readStatus=\(readStatus.rawValue)",
            "availability=\(availability.rawValue)",
            "canonicalDecisionEvaluated=\(canonicalDecisionEvaluated)",
            "canonicalDecisionUsed=\(canonicalDecisionUsed)",
            "canonicalCommitAllowed=\(canonicalDecisionUsed && ownershipDecision.canonicalJobAllowed)",
            "legacyFallbackAllowed=\(ownershipDecision.allowLegacyFallback)",
            "proofFrozen=\(input.proofSchema.isV855Frozen)",
            "redacted=true"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalUploadStateTruth: Codable, Equatable, Sendable {
    var objectID: String
    var localAudioExists: Bool
    var localContentHash: CanonicalHash?
    var localByteSize: Int64?
    var localFileTokenValid: Bool
    var localFileStale: Bool
    var canonicalJobState: CanonicalAudioUploadSessionState?
    var canonicalJobAttemptCount: Int
    var canonicalJobNextRetryAt: CanonicalTimestamp?
    var legacyLedgerTruth: CanonicalAudioUploadLedgerTruth
    var retryTruth: CanonicalAudioUploadRetryTruth
    var peerInventoryState: CanonicalUploadPeerInventoryState
    var peerContentHash: CanonicalHash?
    var peerByteSize: Int64?
    var peerHashSizeProven: Bool
    var macReceiveSessionState: CanonicalUploadMacReceiveSessionState
    var macConfirmedBytes: Int64?
    var macFinalizedProof: CanonicalAudioUploadFinalizeProof?
    var canonicalExistenceState: CanonicalRecordingExistenceState?
    var expectedManifestHash: CanonicalHash?
    var expectedManifestByteSize: Int64?
    var tombstoned: Bool
    var conflictRecorded: Bool
    var malformedLedger: Bool
    var triggerSource: CanonicalAudioUploadTriggerSource

    nonisolated init(
        objectID: String,
        localAudioExists: Bool,
        localContentHash: CanonicalHash? = nil,
        localByteSize: Int64? = nil,
        localFileTokenValid: Bool = true,
        localFileStale: Bool = false,
        canonicalJobState: CanonicalAudioUploadSessionState? = nil,
        canonicalJobAttemptCount: Int = 0,
        canonicalJobNextRetryAt: CanonicalTimestamp? = nil,
        legacyLedgerTruth: CanonicalAudioUploadLedgerTruth = CanonicalAudioUploadLedgerTruth(),
        retryTruth: CanonicalAudioUploadRetryTruth = CanonicalAudioUploadRetryTruth(),
        peerInventoryState: CanonicalUploadPeerInventoryState,
        peerContentHash: CanonicalHash? = nil,
        peerByteSize: Int64? = nil,
        peerHashSizeProven: Bool = false,
        macReceiveSessionState: CanonicalUploadMacReceiveSessionState = .none,
        macConfirmedBytes: Int64? = nil,
        macFinalizedProof: CanonicalAudioUploadFinalizeProof? = nil,
        canonicalExistenceState: CanonicalRecordingExistenceState? = nil,
        expectedManifestHash: CanonicalHash? = nil,
        expectedManifestByteSize: Int64? = nil,
        tombstoned: Bool = false,
        conflictRecorded: Bool = false,
        malformedLedger: Bool = false,
        triggerSource: CanonicalAudioUploadTriggerSource = .ordinarySync
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.localAudioExists = localAudioExists
        self.localContentHash = localContentHash
        self.localByteSize = localByteSize.map { max(0, $0) }
        self.localFileTokenValid = localFileTokenValid
        self.localFileStale = localFileStale
        self.canonicalJobState = canonicalJobState
        self.canonicalJobAttemptCount = max(0, canonicalJobAttemptCount)
        self.canonicalJobNextRetryAt = canonicalJobNextRetryAt
        self.legacyLedgerTruth = legacyLedgerTruth
        self.retryTruth = retryTruth
        self.peerInventoryState = peerInventoryState
        self.peerContentHash = peerContentHash
        self.peerByteSize = peerByteSize.map { max(0, $0) }
        self.peerHashSizeProven = peerHashSizeProven
        self.macReceiveSessionState = macReceiveSessionState
        self.macConfirmedBytes = macConfirmedBytes.map { max(0, $0) }
        self.macFinalizedProof = macFinalizedProof
        self.canonicalExistenceState = canonicalExistenceState
        self.expectedManifestHash = expectedManifestHash
        self.expectedManifestByteSize = expectedManifestByteSize.map { max(0, $0) }
        self.tombstoned = tombstoned
        self.conflictRecorded = conflictRecorded
        self.malformedLedger = malformedLedger
        self.triggerSource = triggerSource
    }

    nonisolated static func fromCutoverCandidate(
        _ candidate: CanonicalAudioUploadCutoverCandidate,
        canonicalJobState: CanonicalAudioUploadSessionState? = nil,
        canonicalJobAttemptCount: Int = 0,
        macReceiveSessionState: CanonicalUploadMacReceiveSessionState = .none,
        macConfirmedBytes: Int64? = nil,
        macFinalizedProof: CanonicalAudioUploadFinalizeProof? = nil
    ) -> CanonicalUploadStateTruth {
        CanonicalUploadStateTruth(
            objectID: candidate.objectID,
            localAudioExists: candidate.localTruth.audioAvailable,
            localContentHash: candidate.localTruth.contentHash,
            localByteSize: candidate.localTruth.byteSize,
            canonicalJobState: canonicalJobState,
            canonicalJobAttemptCount: canonicalJobAttemptCount,
            legacyLedgerTruth: candidate.ledgerTruth,
            retryTruth: candidate.retryTruth,
            peerInventoryState: CanonicalUploadPeerInventoryState(candidate.peerTruth.state),
            peerContentHash: candidate.peerTruth.contentHash,
            peerByteSize: candidate.peerTruth.byteSize,
            peerHashSizeProven: candidate.peerTruth.state == .available
                && candidate.peerTruth.contentHash != nil
                && candidate.peerTruth.byteSize != nil,
            macReceiveSessionState: macReceiveSessionState,
            macConfirmedBytes: macConfirmedBytes,
            macFinalizedProof: macFinalizedProof,
            triggerSource: candidate.trigger
        )
    }

    nonisolated func reconcile(now: Date = Date()) -> CanonicalUploadStateReconciliationReport {
        var sources = sources()
        var blockers: Set<CanonicalUploadStateBlocker> = []
        var diagnostics: [CanonicalUploadStateDiagnostic] = [
            diagnostic(.canonicalUploadStateTruthEvaluated, state: nil, reason: "begin")
        ]

        if legacyLedgerTruth.phase == .completed {
            blockers.insert(.completedLedgerRejectedAsProof)
            diagnostics.append(diagnostic(.canonicalUploadCompletedLedgerRejectedAsProof, reason: "completed ledger requires peer finalized hash and byteSize proof"))
        }
        if expectedManifestHash != nil || expectedManifestByteSize != nil {
            blockers.insert(.expectedManifestHashNotPeerProof)
        }
        if malformedLedger {
            blockers.insert(.malformedLedger)
            return report(
                decision: .uploadFailedVerification,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "malformed ledger",
                resumeOffset: nil
            )
        }
        if tombstoned || peerInventoryState == .tombstoned || canonicalExistenceState == .tombstoned {
            sources.insert(.tombstoneConflict)
            blockers.insert(.tombstonedParent)
            return report(
                decision: .uploadBlockedTombstoned,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "tombstoned parent",
                resumeOffset: nil
            )
        }
        if conflictRecorded || peerInventoryState == .conflict || canonicalExistenceState == .audioConflict {
            blockers.insert(.differentHashOrSizeConflict)
            blockers.insert(.uploadJobCannotOverridePeerConflict)
            diagnostics.append(diagnostic(.canonicalUploadExistingDifferentAudioConflict, state: .uploadConflictDifferentAudio, reason: "conflict recorded"))
            return report(
                decision: .uploadConflictDifferentAudio,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "existing different audio conflict",
                resumeOffset: nil
            )
        }
        guard localAudioExists else {
            blockers.insert(.missingLocalAudio)
            return report(
                decision: .absentLocalAudio,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "local audio missing",
                resumeOffset: nil
            )
        }
        guard localFileTokenValid else {
            blockers.insert(.invalidLocalFileToken)
            return report(
                decision: .uploadBlockedPolicy,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "local file token invalid",
                resumeOffset: nil
            )
        }
        if localFileStale {
            blockers.insert(.staleLocalAudioFile)
            return report(
                decision: .uploadBlockedPolicy,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "local audio stale",
                resumeOffset: nil
            )
        }
        guard localContentHash != nil, localByteSize != nil else {
            blockers.insert(.localAudioHashSizeMissing)
            return report(
                decision: .uploadBlockedPolicy,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "local hash or byteSize missing",
                resumeOffset: nil
            )
        }

        if let finalizedProof = macFinalizedProof {
            sources.insert(.macFinalizedAudio)
            if finalizedProof.accepted, finalizedProof.byteSize == localByteSize {
                diagnostics.append(diagnostic(.canonicalUploadFinalizedProofAccepted, state: .uploadCompletedVerified, reason: "finalized proof accepted"))
                return report(
                    decision: .uploadCompletedVerified,
                    sources: sources,
                    blockers: blockers.subtracting([.completedLedgerRejectedAsProof, .expectedManifestHashNotPeerProof]),
                    diagnostics: diagnostics,
                    reason: "finalized Mac proof accepted",
                    resumeOffset: nil
                )
            }
            blockers.insert(.finalizedProofRejected)
            diagnostics.append(diagnostic(.canonicalUploadFinalizedProofMissing, state: .uploadFailedVerification, reason: "finalized proof rejected"))
            return report(
                decision: .uploadFailedVerification,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "finalized proof rejected",
                resumeOffset: nil
            )
        }

        switch peerInventoryState {
        case .unknown:
            blockers.insert(.peerUnknown)
            diagnostics.append(diagnostic(.canonicalUploadPeerUnknownDeferred, state: .peerUnknownDeferred, reason: "peer unknown"))
            return report(
                decision: .peerUnknownDeferred,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "peer unknown deferred",
                resumeOffset: nil
            )
        case .audioAvailable:
            sources.insert(.peerAudioAvailable)
            guard peerHashSizeProven, peerContentHash != nil, peerByteSize != nil else {
                blockers.insert(.finalizedProofMissing)
                diagnostics.append(diagnostic(.canonicalUploadFinalizedProofMissing, state: .uploadFinalizedProofPending, reason: "peer audio lacks proven hash or byteSize"))
                return report(
                    decision: .uploadFinalizedProofPending,
                    sources: sources,
                    blockers: blockers,
                    diagnostics: diagnostics,
                    reason: "peer audio proof missing",
                    resumeOffset: nil
                )
            }
            sources.insert(.peerAudioHashSize)
            if sameHashSize(localHash: localContentHash, localByteSize: localByteSize, peerHash: peerContentHash, peerByteSize: peerByteSize) {
                let verified = legacyLedgerTruth.phase == .completed || canonicalJobState == .finalized
                diagnostics.append(diagnostic(.canonicalUploadFinalizedProofAccepted, state: verified ? .uploadCompletedVerified : .uploadNoOpSameAudio, reason: "same hash and byteSize"))
                return report(
                    decision: verified ? .uploadCompletedVerified : .uploadNoOpSameAudio,
                    sources: sources,
                    blockers: blockers.subtracting([.completedLedgerRejectedAsProof, .expectedManifestHashNotPeerProof]),
                    diagnostics: diagnostics,
                    reason: verified ? "completed verified by peer proof" : "same audio no-op",
                    resumeOffset: nil
                )
            }
            blockers.insert(.differentHashOrSizeConflict)
            diagnostics.append(diagnostic(.canonicalUploadExistingDifferentAudioConflict, state: .uploadConflictDifferentAudio, reason: "different hash or byteSize"))
            return report(
                decision: .uploadConflictDifferentAudio,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "different hash or byteSize",
                resumeOffset: nil
            )
        case .metadataOnly:
            sources.insert(.peerMetadataOnly)
            blockers.insert(.metadataOnlyNotAudioAvailable)
            diagnostics.append(diagnostic(.canonicalUploadMetadataOnlyRejectedAsAudioAvailable, state: .peerMetadataOnlyNeedsUpload, reason: "metadataOnly is not audioAvailable"))
            return needsUploadReport(
                preferredDecision: .peerMetadataOnlyNeedsUpload,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "peer metadataOnly needs upload"
            )
        case .receiveRecordOnly:
            sources.insert(.peerReceiveRecordOnly)
            blockers.insert(.receiveRecordOnlyNotAudioAvailable)
            return needsUploadReport(
                preferredDecision: .peerReceiveRecordOnlyNeedsUpload,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "peer receiveRecordOnly needs upload"
            )
        case .studyItemOnly:
            sources.insert(.peerStudyItemOnly)
            blockers.insert(.studyItemOnlyNotAudioAvailable)
            return needsUploadReport(
                preferredDecision: .peerStudyItemOnlyNeedsUpload,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "peer studyItemOnly needs upload"
            )
        case .missing:
            return needsUploadReport(
                preferredDecision: .uploadPending,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "peer missing audio"
            )
        case .conflict, .tombstoned:
            return report(
                decision: peerInventoryState == .tombstoned ? .uploadBlockedTombstoned : .uploadConflictDifferentAudio,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: peerInventoryState.rawValue,
                resumeOffset: nil
            )
        case .unsupported:
            blockers.insert(.unsupported)
            return report(
                decision: .uploadUnsupported,
                sources: sources,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: "unsupported peer inventory",
                resumeOffset: nil
            )
        }
    }

    nonisolated private func needsUploadReport(
        preferredDecision: CanonicalUploadStateDecision,
        sources: Set<CanonicalUploadStateSource>,
        blockers: Set<CanonicalUploadStateBlocker>,
        diagnostics: [CanonicalUploadStateDiagnostic],
        reason: String
    ) -> CanonicalUploadStateReconciliationReport {
        let resumeOffset = macReceiveSessionState == .partial ? macConfirmedBytes : nil
        let decision: CanonicalUploadStateDecision
        if retryTruth.retryPending || legacyLedgerTruth.phase == .retryPending {
            decision = .uploadRetryScheduled
        } else if let canonicalJobState {
            switch canonicalJobState {
            case .starting:
                decision = .uploadStarting
            case .started, .chunking, .resuming:
                decision = .uploadInProgress
            case .interrupted:
                decision = .uploadInterrupted
            case .finalizing:
                decision = .uploadFinalizing
            case .finalized:
                decision = .uploadFinalizedProofPending
            case .failed:
                decision = .uploadFailedNetwork
            case .conflict:
                decision = .uploadConflictDifferentAudio
            case .blocked:
                decision = .uploadBlockedPolicy
            case .aborted:
                decision = .uploadInterrupted
            case .idle:
                decision = preferredDecision
            }
        } else if legacyLedgerTruth.phase == .queued {
            decision = .uploadPending
        } else if legacyLedgerTruth.phase == .inFlight {
            decision = .uploadInProgress
        } else if legacyLedgerTruth.phase == .finalizing {
            decision = .uploadFinalizing
        } else {
            decision = preferredDecision
        }
        return report(
            decision: decision,
            sources: sources,
            blockers: blockers,
            diagnostics: diagnostics,
            reason: reason,
            resumeOffset: resumeOffset
        )
    }

    nonisolated private func sources() -> Set<CanonicalUploadStateSource> {
        var sources: Set<CanonicalUploadStateSource> = [.peerInventoryRecordingExistence]
        if localAudioExists {
            sources.insert(.localAudioFile)
        }
        if localContentHash != nil || localByteSize != nil {
            sources.insert(.localAudioHashSize)
        }
        if canonicalJobState != nil {
            sources.insert(.localCanonicalUploadJobStore)
        }
        if legacyLedgerTruth.phase != .none {
            sources.insert(.localLegacyUploadLedger)
        }
        if retryTruth.retryPending || retryTruth.hasExistingEligibleRetry {
            sources.insert(.retryQueue)
        }
        if macReceiveSessionState != .none {
            sources.insert(.macReceiveSession)
        }
        if canonicalExistenceState != nil {
            sources.insert(.canonicalExistenceLedger)
        }
        return sources
    }

    nonisolated private func report(
        decision: CanonicalUploadStateDecision,
        sources: Set<CanonicalUploadStateSource>,
        blockers: Set<CanonicalUploadStateBlocker>,
        diagnostics: [CanonicalUploadStateDiagnostic],
        reason: String,
        resumeOffset: Int64?
    ) -> CanonicalUploadStateReconciliationReport {
        var diagnostics = diagnostics
        if blockers.isEmpty {
            diagnostics.append(diagnostic(.canonicalUploadStateReconciled, state: decision, reason: reason))
        } else {
            diagnostics.append(diagnostic(.canonicalUploadStateReconciliationBlocked, state: decision, reason: reason))
        }
        return CanonicalUploadStateReconciliationReport(
            objectID: objectID,
            decision: decision,
            sources: sources,
            blockers: blockers,
            diagnostics: diagnostics,
            verifiedCompleted: decision == .uploadCompletedVerified,
            shouldCreateUploadJob: decision.canCreateUploadJob,
            shouldResumeExistingJob: decision.shouldResumeExistingJob,
            shouldRetry: decision.shouldRetry,
            resumeOffset: resumeOffset,
            reason: reason
        )
    }

    nonisolated private func diagnostic(
        _ kind: CanonicalUploadDiagnosticEvent,
        state: CanonicalUploadStateDecision? = nil,
        reason: String? = nil
    ) -> CanonicalUploadStateDiagnostic {
        CanonicalUploadStateDiagnostic(
            kind: kind,
            objectID: objectID,
            state: state,
            reason: reason,
            retryCount: canonicalJobAttemptCount,
            offset: macConfirmedBytes,
            confirmedBytes: macConfirmedBytes,
            totalBytes: localByteSize,
            hash: localContentHash
        )
    }

    nonisolated private func sameHashSize(
        localHash: CanonicalHash?,
        localByteSize: Int64?,
        peerHash: CanonicalHash?,
        peerByteSize: Int64?
    ) -> Bool {
        guard let localHash,
              let localByteSize,
              let peerHash,
              let peerByteSize else {
            return false
        }
        return localHash == peerHash && localByteSize == peerByteSize
    }
}

nonisolated struct CanonicalUploadStateReconciliationReport: Codable, Equatable, Sendable {
    var objectID: String
    var decision: CanonicalUploadStateDecision
    var sources: Set<CanonicalUploadStateSource>
    var blockers: Set<CanonicalUploadStateBlocker>
    var diagnostics: [CanonicalUploadStateDiagnostic]
    var verifiedCompleted: Bool
    var shouldCreateUploadJob: Bool
    var shouldResumeExistingJob: Bool
    var shouldRetry: Bool
    var resumeOffset: Int64?
    var reason: String

    nonisolated init(
        objectID: String,
        decision: CanonicalUploadStateDecision,
        sources: Set<CanonicalUploadStateSource>,
        blockers: Set<CanonicalUploadStateBlocker>,
        diagnostics: [CanonicalUploadStateDiagnostic],
        verifiedCompleted: Bool,
        shouldCreateUploadJob: Bool,
        shouldResumeExistingJob: Bool,
        shouldRetry: Bool,
        resumeOffset: Int64?,
        reason: String
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.decision = decision
        self.sources = sources
        self.blockers = blockers
        self.diagnostics = diagnostics
        self.verifiedCompleted = verifiedCompleted
        self.shouldCreateUploadJob = shouldCreateUploadJob
        self.shouldResumeExistingJob = shouldResumeExistingJob
        self.shouldRetry = shouldRetry
        self.resumeOffset = resumeOffset.map { max(0, $0) }
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason) ?? "unspecified"
    }
}

extension CanonicalUploadStateDecision {
    nonisolated var canCreateUploadJob: Bool {
        switch self {
        case .peerMetadataOnlyNeedsUpload, .peerReceiveRecordOnlyNeedsUpload, .peerStudyItemOnlyNeedsUpload, .uploadPending:
            return true
        case .absentLocalAudio, .peerUnknownDeferred, .uploadStarting, .uploadInProgress, .uploadInterrupted,
             .uploadRetryScheduled, .uploadFinalizing, .uploadFinalizedProofPending, .uploadCompletedVerified,
             .uploadNoOpSameAudio, .uploadConflictDifferentAudio, .uploadBlockedTombstoned, .uploadBlockedPolicy,
             .uploadFailedNetwork, .uploadFailedSecurity, .uploadFailedVerification, .uploadLegacyFallback,
             .uploadUnsupported:
            return false
        }
    }

    nonisolated var shouldResumeExistingJob: Bool {
        switch self {
        case .uploadInterrupted, .uploadRetryScheduled, .uploadInProgress:
            return true
        case .absentLocalAudio, .peerUnknownDeferred, .peerMetadataOnlyNeedsUpload, .peerReceiveRecordOnlyNeedsUpload,
             .peerStudyItemOnlyNeedsUpload, .uploadPending, .uploadStarting, .uploadFinalizing,
             .uploadFinalizedProofPending, .uploadCompletedVerified, .uploadNoOpSameAudio,
             .uploadConflictDifferentAudio, .uploadBlockedTombstoned, .uploadBlockedPolicy,
             .uploadFailedNetwork, .uploadFailedSecurity, .uploadFailedVerification, .uploadLegacyFallback,
             .uploadUnsupported:
            return false
        }
    }

    nonisolated var shouldRetry: Bool {
        switch self {
        case .uploadRetryScheduled, .uploadInterrupted, .uploadFailedNetwork:
            return true
        case .absentLocalAudio, .peerUnknownDeferred, .peerMetadataOnlyNeedsUpload, .peerReceiveRecordOnlyNeedsUpload,
             .peerStudyItemOnlyNeedsUpload, .uploadPending, .uploadStarting, .uploadInProgress, .uploadFinalizing,
             .uploadFinalizedProofPending, .uploadCompletedVerified, .uploadNoOpSameAudio,
             .uploadConflictDifferentAudio, .uploadBlockedTombstoned, .uploadBlockedPolicy,
             .uploadFailedSecurity, .uploadFailedVerification, .uploadLegacyFallback, .uploadUnsupported:
            return false
        }
    }
}

extension CanonicalUploadPeerInventoryState {
    nonisolated init(_ state: CanonicalAudioUploadPeerState) {
        switch state {
        case .unknown:
            self = .unknown
        case .missing:
            self = .missing
        case .metadataOnly:
            self = .metadataOnly
        case .available:
            self = .audioAvailable
        case .different:
            self = .conflict
        case .deleted:
            self = .tombstoned
        }
    }
}

nonisolated enum CanonicalUploadRetryDrainDecision: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case resumeCanonicalExistingJob
    case resumeLegacyExistingJob
    case refreshStatusBeforeResume
    case skipPeerUnknown
    case skipConflict
    case skipMissingLocalAudio
    case skipTombstoned
    case skipBackoff
    case skipMaxRetriesReached
    case skipSecurityFailure
    case skipViewRefresh
    case skipMalformedLedger
    case didNotCreateFreshJob
}

nonisolated enum CanonicalUploadRetryDrainBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case noExistingEligibleJob
    case viewRefreshTrigger
    case peerUnknown
    case conflict
    case missingLocalAudio
    case tombstoned
    case backoffNotElapsed
    case maxRetriesReached
    case securityFailure
    case localFileTokenInvalid
    case staleLocalFile
    case malformedLedger
    case duplicateCanonicalLegacyJob
    case statusRefreshRequired
}

nonisolated struct CanonicalUploadRetryDrainerPolicy: Codable, Equatable, Sendable {
    var maxRetries: Int
    var statusRefreshSupported: Bool
    var requiresValidLocalFileToken: Bool

    nonisolated init(
        maxRetries: Int = 3,
        statusRefreshSupported: Bool = true,
        requiresValidLocalFileToken: Bool = true
    ) {
        self.maxRetries = max(1, maxRetries)
        self.statusRefreshSupported = statusRefreshSupported
        self.requiresValidLocalFileToken = requiresValidLocalFileToken
    }

    nonisolated func evaluate(
        truth: CanonicalUploadStateTruth,
        existingCanonicalJob: CanonicalAudioUploadRetryRecord? = nil,
        existingLegacyJob: CanonicalUploadLegacyRetryRecord? = nil,
        now: Date = Date(),
        securityFailure: Bool = false
    ) -> CanonicalUploadRetryDrainResult {
        var diagnostics: [CanonicalUploadStateDiagnostic] = [
            CanonicalUploadStateDiagnostic(
                kind: .canonicalUploadRetryDrainEvaluated,
                objectID: truth.objectID,
                state: nil,
                reason: truth.triggerSource.rawValue
            )
        ]
        var blockers: Set<CanonicalUploadRetryDrainBlocker> = []
        let report = truth.reconcile(now: now)

        func result(_ decision: CanonicalUploadRetryDrainDecision, reason: String) -> CanonicalUploadRetryDrainResult {
            let diagnosticKind: CanonicalUploadDiagnosticEvent
            switch decision {
            case .resumeCanonicalExistingJob, .resumeLegacyExistingJob, .refreshStatusBeforeResume:
                diagnosticKind = .canonicalUploadRetryDrainResumedExistingJob
            case .skipPeerUnknown:
                diagnosticKind = .canonicalUploadRetryDrainSkippedPeerUnknown
            case .skipConflict:
                diagnosticKind = .canonicalUploadRetryDrainSkippedConflict
            case .skipMissingLocalAudio:
                diagnosticKind = .canonicalUploadRetryDrainSkippedMissingLocalAudio
            case .skipTombstoned:
                diagnosticKind = .canonicalUploadRetryDrainSkippedTombstoned
            case .skipBackoff:
                diagnosticKind = .canonicalUploadRetryDrainBackoffApplied
            case .skipMaxRetriesReached:
                diagnosticKind = .canonicalUploadRetryDrainMaxRetriesReached
            case .didNotCreateFreshJob, .skipViewRefresh, .skipMalformedLedger, .skipSecurityFailure:
                diagnosticKind = .canonicalUploadRetryDrainDidNotCreateFreshJob
            }
            diagnostics.append(
                CanonicalUploadStateDiagnostic(
                    kind: diagnosticKind,
                    objectID: truth.objectID,
                    state: report.decision,
                    reason: reason,
                    retryCount: max(existingCanonicalJob?.attemptCount ?? 0, existingLegacyJob?.attemptCount ?? 0),
                    confirmedBytes: report.resumeOffset,
                    totalBytes: truth.localByteSize,
                    hash: truth.localContentHash,
                    sessionID: existingCanonicalJob?.sessionID,
                    sessionIDPrefix: existingLegacyJob?.sessionIDPrefix
                )
            )
            return CanonicalUploadRetryDrainResult(
                objectID: truth.objectID,
                decision: decision,
                blockers: blockers,
                diagnostics: diagnostics,
                createdFreshJob: false,
                resumedExistingJob: decision == .resumeCanonicalExistingJob || decision == .resumeLegacyExistingJob,
                requiresStatusRefresh: decision == .refreshStatusBeforeResume,
                resumeOffset: report.resumeOffset,
                canonicalJob: existingCanonicalJob,
                legacyJob: existingLegacyJob,
                reason: reason
            )
        }

        if truth.triggerSource == .viewRefresh {
            blockers.insert(.viewRefreshTrigger)
            return result(.skipViewRefresh, reason: "view refresh cannot drain retry")
        }
        if securityFailure {
            blockers.insert(.securityFailure)
            return result(.skipSecurityFailure, reason: "security failure fails closed")
        }
        if truth.malformedLedger {
            blockers.insert(.malformedLedger)
            return result(.skipMalformedLedger, reason: "malformed ledger fails closed")
        }
        if report.blockers.contains(.missingLocalAudio) || report.decision == .absentLocalAudio {
            blockers.insert(.missingLocalAudio)
            return result(.skipMissingLocalAudio, reason: "local audio missing")
        }
        if report.blockers.contains(.tombstonedParent) || report.decision == .uploadBlockedTombstoned {
            blockers.insert(.tombstoned)
            return result(.skipTombstoned, reason: "tombstoned")
        }
        if report.decision == .peerUnknownDeferred {
            blockers.insert(.peerUnknown)
            return result(.skipPeerUnknown, reason: "peer unknown deferred")
        }
        if report.decision == .uploadConflictDifferentAudio {
            blockers.insert(.conflict)
            return result(.skipConflict, reason: "existing different audio")
        }
        if requiresValidLocalFileToken, !truth.localFileTokenValid {
            blockers.insert(.localFileTokenInvalid)
            return result(.skipMissingLocalAudio, reason: "local file token invalid")
        }
        if truth.localFileStale {
            blockers.insert(.staleLocalFile)
            return result(.skipMissingLocalAudio, reason: "local file stale")
        }

        if let canonical = existingCanonicalJob {
            if canonical.attemptCount >= maxRetries {
                blockers.insert(.maxRetriesReached)
                return result(.skipMaxRetriesReached, reason: "canonical max retries reached")
            }
            if let nextRetryAt = canonical.nextRetryAt?.date, nextRetryAt > now {
                blockers.insert(.backoffNotElapsed)
                return result(.skipBackoff, reason: "canonical backoff not elapsed")
            }
            guard canonical.isEligibleRetry(now: now) else {
                blockers.insert(.noExistingEligibleJob)
                return result(.didNotCreateFreshJob, reason: "canonical retry job is not eligible")
            }
            if existingLegacyJob != nil {
                blockers.insert(.duplicateCanonicalLegacyJob)
                diagnostics.append(CanonicalUploadStateDiagnostic(kind: .canonicalUploadDuplicateJobDetected, objectID: truth.objectID, reason: "canonical and legacy retry records exist"))
            }
            if statusRefreshSupported, canonical.sessionID != nil, canonical.state == .interrupted {
                blockers.insert(.statusRefreshRequired)
                return result(.refreshStatusBeforeResume, reason: "status refresh required before canonical resume")
            }
            return result(.resumeCanonicalExistingJob, reason: "resume existing canonical job")
        }

        if let legacy = existingLegacyJob {
            if legacy.attemptCount >= maxRetries {
                blockers.insert(.maxRetriesReached)
                return result(.skipMaxRetriesReached, reason: "legacy max retries reached")
            }
            if let nextRetryAt = legacy.nextRetryAt?.date, nextRetryAt > now {
                blockers.insert(.backoffNotElapsed)
                return result(.skipBackoff, reason: "legacy backoff not elapsed")
            }
            guard legacy.isEligibleRetry(now: now) else {
                blockers.insert(.noExistingEligibleJob)
                return result(.didNotCreateFreshJob, reason: "legacy retry job is not eligible")
            }
            if statusRefreshSupported, legacy.sessionIDPrefix != nil, legacy.state == .interrupted {
                blockers.insert(.statusRefreshRequired)
                return result(.refreshStatusBeforeResume, reason: "status refresh required before legacy resume")
            }
            return result(.resumeLegacyExistingJob, reason: "resume existing legacy job")
        }

        blockers.insert(.noExistingEligibleJob)
        return result(.didNotCreateFreshJob, reason: "no existing eligible retry job")
    }
}

nonisolated enum CanonicalUploadLegacyRetryState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case queued
    case inFlight
    case interrupted
    case retryPending
    case completed
    case conflict
    case fatalFailed
    case malformed
}

nonisolated struct CanonicalUploadLegacyRetryRecord: Codable, Equatable, Sendable {
    var objectID: String
    var sessionIDPrefix: String?
    var confirmedBytes: Int64
    var totalBytes: Int64?
    var contentHashPrefix: String?
    var attemptCount: Int
    var nextRetryAt: CanonicalTimestamp?
    var state: CanonicalUploadLegacyRetryState
    var localFileTokenValid: Bool

    nonisolated init(
        objectID: String,
        sessionIDPrefix: String? = nil,
        confirmedBytes: Int64 = 0,
        totalBytes: Int64? = nil,
        contentHashPrefix: String? = nil,
        attemptCount: Int = 0,
        nextRetryAt: CanonicalTimestamp? = nil,
        state: CanonicalUploadLegacyRetryState,
        localFileTokenValid: Bool = true
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionIDPrefix = CanonicalAudioUploadRuntimeRedaction.hashPrefix(sessionIDPrefix)
        self.confirmedBytes = max(0, confirmedBytes)
        self.totalBytes = totalBytes.map { max(0, $0) }
        self.contentHashPrefix = CanonicalAudioUploadRuntimeRedaction.hashPrefix(contentHashPrefix)
        self.attemptCount = max(0, attemptCount)
        self.nextRetryAt = nextRetryAt
        self.state = state
        self.localFileTokenValid = localFileTokenValid
    }

    nonisolated func isEligibleRetry(now: Date) -> Bool {
        guard localFileTokenValid else {
            return false
        }
        switch state {
        case .queued, .interrupted, .retryPending:
            break
        case .inFlight, .completed, .conflict, .fatalFailed, .malformed:
            return false
        }
        if let nextRetryAt, nextRetryAt.date > now {
            return false
        }
        return true
    }
}

nonisolated struct CanonicalUploadRetryDrainResult: Codable, Equatable, Sendable {
    var objectID: String
    var decision: CanonicalUploadRetryDrainDecision
    var blockers: Set<CanonicalUploadRetryDrainBlocker>
    var diagnostics: [CanonicalUploadStateDiagnostic]
    var createdFreshJob: Bool
    var resumedExistingJob: Bool
    var requiresStatusRefresh: Bool
    var resumeOffset: Int64?
    var canonicalJob: CanonicalAudioUploadRetryRecord?
    var legacyJob: CanonicalUploadLegacyRetryRecord?
    var reason: String

    nonisolated init(
        objectID: String,
        decision: CanonicalUploadRetryDrainDecision,
        blockers: Set<CanonicalUploadRetryDrainBlocker>,
        diagnostics: [CanonicalUploadStateDiagnostic],
        createdFreshJob: Bool,
        resumedExistingJob: Bool,
        requiresStatusRefresh: Bool,
        resumeOffset: Int64?,
        canonicalJob: CanonicalAudioUploadRetryRecord?,
        legacyJob: CanonicalUploadLegacyRetryRecord?,
        reason: String
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.decision = decision
        self.blockers = blockers
        self.diagnostics = diagnostics
        self.createdFreshJob = createdFreshJob
        self.resumedExistingJob = resumedExistingJob
        self.requiresStatusRefresh = requiresStatusRefresh
        self.resumeOffset = resumeOffset.map { max(0, $0) }
        self.canonicalJob = canonicalJob
        self.legacyJob = legacyJob
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason) ?? "unspecified"
    }
}

nonisolated enum CanonicalUploadOwnershipMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case oldKernel
    case diagnosticsOnly
    case canonicalShadow
    case canonicalDecisionOnly
    case canonicalApplyNoAudio
    case canonicalFullSync
    case blocked

    nonisolated init(_ mode: CanonicalKernelSwitchMode) {
        switch mode {
        case .oldKernel:
            self = .oldKernel
        case .diagnosticsOnly:
            self = .diagnosticsOnly
        case .canonicalShadow:
            self = .canonicalShadow
        case .canonicalDecisionOnly:
            self = .canonicalDecisionOnly
        case .canonicalApplyNoAudio:
            self = .canonicalApplyNoAudio
        case .canonicalFullSync:
            self = .canonicalFullSync
        case .blocked:
            self = .blocked
        }
    }
}

nonisolated enum CanonicalUploadOwnershipOwner: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case legacy
    case canonical
}

nonisolated struct CanonicalUploadOwnershipDecision: Codable, Equatable, Sendable {
    var objectID: String
    var mode: CanonicalUploadOwnershipMode
    var owner: CanonicalUploadOwnershipOwner
    var canonicalJobAllowed: Bool
    var suppressLegacyFreshJob: Bool
    var suppressCanonicalFreshJob: Bool
    var allowLegacyFallback: Bool
    var suppressLegacyCompletedState: Bool
    var blockers: Set<CanonicalUploadStateBlocker>
    var diagnostics: [CanonicalUploadStateDiagnostic]
    var reason: String
}

nonisolated enum CanonicalUploadDuplicateJobGuard {
    nonisolated static func evaluate(
        objectID: String,
        mode: CanonicalUploadOwnershipMode,
        gateAllowsCanonical: Bool = false,
        viewRefresh: Bool = false,
        peerUnknownDeferred: Bool = false,
        canonicalJobStarted: Bool = false,
        canonicalBlockedBeforeStart: Bool = false,
        canonicalFailedBeforePeerData: Bool = false,
        canonicalSecurityFailure: Bool = false,
        canonicalConflict: Bool = false,
        canonicalFinalizeSucceeded: Bool = false,
        canonicalFinalizeProofAccepted: Bool = false,
        legacyJobRunning: Bool = false,
        legacyFallbackAvailable: Bool = true
    ) -> CanonicalUploadOwnershipDecision {
        let safeObjectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        var blockers: Set<CanonicalUploadStateBlocker> = []
        var diagnostics: [CanonicalUploadStateDiagnostic] = []

        func decision(
            owner: CanonicalUploadOwnershipOwner,
            canonicalJobAllowed: Bool,
            suppressLegacyFreshJob: Bool,
            suppressCanonicalFreshJob: Bool,
            allowLegacyFallback: Bool,
            suppressLegacyCompletedState: Bool,
            reason: String
        ) -> CanonicalUploadOwnershipDecision {
            let event: CanonicalUploadDiagnosticEvent = owner == .canonical
                ? .canonicalUploadOwnershipSelectedCanonical
                : .canonicalUploadOwnershipSelectedLegacy
            diagnostics.append(CanonicalUploadStateDiagnostic(kind: event, objectID: safeObjectID, reason: reason))
            if suppressLegacyFreshJob || suppressCanonicalFreshJob {
                diagnostics.append(CanonicalUploadStateDiagnostic(kind: .canonicalUploadDuplicateJobSuppressed, objectID: safeObjectID, reason: reason))
            }
            if allowLegacyFallback, owner == .legacy, mode == .canonicalFullSync {
                diagnostics.append(CanonicalUploadStateDiagnostic(kind: .canonicalUploadOwnershipFallbackLegacy, objectID: safeObjectID, reason: reason))
            }
            return CanonicalUploadOwnershipDecision(
                objectID: safeObjectID,
                mode: mode,
                owner: owner,
                canonicalJobAllowed: canonicalJobAllowed,
                suppressLegacyFreshJob: suppressLegacyFreshJob,
                suppressCanonicalFreshJob: suppressCanonicalFreshJob,
                allowLegacyFallback: allowLegacyFallback,
                suppressLegacyCompletedState: suppressLegacyCompletedState,
                blockers: blockers,
                diagnostics: diagnostics,
                reason: CanonicalAudioUploadRuntimeRedaction.safeText(reason) ?? "unspecified"
            )
        }

        if viewRefresh {
            blockers.insert(.viewRefreshCannotCreateUploadJob)
            return decision(
                owner: .none,
                canonicalJobAllowed: false,
                suppressLegacyFreshJob: true,
                suppressCanonicalFreshJob: true,
                allowLegacyFallback: false,
                suppressLegacyCompletedState: false,
                reason: "view refresh cannot create upload job"
            )
        }
        if peerUnknownDeferred {
            blockers.insert(.peerUnknown)
            return decision(
                owner: .none,
                canonicalJobAllowed: false,
                suppressLegacyFreshJob: true,
                suppressCanonicalFreshJob: true,
                allowLegacyFallback: false,
                suppressLegacyCompletedState: false,
                reason: "peer unknown deferred"
            )
        }
        if legacyJobRunning {
            blockers.insert(.duplicateCanonicalLegacyJob)
            diagnostics.append(CanonicalUploadStateDiagnostic(kind: .canonicalUploadDuplicateJobDetected, objectID: safeObjectID, reason: "legacy job already running"))
            return decision(
                owner: .legacy,
                canonicalJobAllowed: false,
                suppressLegacyFreshJob: false,
                suppressCanonicalFreshJob: true,
                allowLegacyFallback: false,
                suppressLegacyCompletedState: false,
                reason: "legacy job already running"
            )
        }
        if canonicalConflict {
            blockers.insert(.differentHashOrSizeConflict)
            return decision(
                owner: .none,
                canonicalJobAllowed: false,
                suppressLegacyFreshJob: true,
                suppressCanonicalFreshJob: true,
                allowLegacyFallback: false,
                suppressLegacyCompletedState: false,
                reason: "canonical conflict blocks fallback overwrite"
            )
        }
        if canonicalSecurityFailure {
            blockers.insert(.securityFailure)
            return decision(
                owner: .none,
                canonicalJobAllowed: false,
                suppressLegacyFreshJob: true,
                suppressCanonicalFreshJob: true,
                allowLegacyFallback: false,
                suppressLegacyCompletedState: false,
                reason: "security failure blocks fallback bypass"
            )
        }
        if canonicalFinalizeSucceeded {
            if canonicalFinalizeProofAccepted {
                return decision(
                    owner: .canonical,
                    canonicalJobAllowed: true,
                    suppressLegacyFreshJob: true,
                    suppressCanonicalFreshJob: false,
                    allowLegacyFallback: false,
                    suppressLegacyCompletedState: true,
                    reason: "canonical finalize proof accepted"
                )
            }
            blockers.insert(.finalizedProofMissing)
            return decision(
                owner: .legacy,
                canonicalJobAllowed: false,
                suppressLegacyFreshJob: false,
                suppressCanonicalFreshJob: true,
                allowLegacyFallback: legacyFallbackAvailable,
                suppressLegacyCompletedState: false,
                reason: "canonical finalize proof missing"
            )
        }

        switch mode {
        case .oldKernel:
            return decision(
                owner: .legacy,
                canonicalJobAllowed: false,
                suppressLegacyFreshJob: false,
                suppressCanonicalFreshJob: true,
                allowLegacyFallback: true,
                suppressLegacyCompletedState: false,
                reason: "old kernel legacy owner"
            )
        case .diagnosticsOnly, .canonicalShadow, .canonicalDecisionOnly, .canonicalApplyNoAudio:
            return decision(
                owner: .legacy,
                canonicalJobAllowed: false,
                suppressLegacyFreshJob: false,
                suppressCanonicalFreshJob: true,
                allowLegacyFallback: true,
                suppressLegacyCompletedState: false,
                reason: "\(mode.rawValue) creates no canonical upload job"
            )
        case .blocked:
            blockers.insert(.policyBlocked)
            return decision(
                owner: .legacy,
                canonicalJobAllowed: false,
                suppressLegacyFreshJob: false,
                suppressCanonicalFreshJob: true,
                allowLegacyFallback: legacyFallbackAvailable,
                suppressLegacyCompletedState: false,
                reason: "canonical upload blocked"
            )
        case .canonicalFullSync:
            if canonicalBlockedBeforeStart || canonicalFailedBeforePeerData {
                return decision(
                    owner: .legacy,
                    canonicalJobAllowed: false,
                    suppressLegacyFreshJob: false,
                    suppressCanonicalFreshJob: true,
                    allowLegacyFallback: legacyFallbackAvailable,
                    suppressLegacyCompletedState: false,
                    reason: canonicalBlockedBeforeStart ? "canonical blocked before start" : "canonical failed before peer data"
                )
            }
            guard gateAllowsCanonical else {
                blockers.insert(.policyBlocked)
                return decision(
                    owner: .legacy,
                    canonicalJobAllowed: false,
                    suppressLegacyFreshJob: false,
                    suppressCanonicalFreshJob: true,
                    allowLegacyFallback: legacyFallbackAvailable,
                    suppressLegacyCompletedState: false,
                    reason: "canonical gate not allowed"
                )
            }
            return decision(
                owner: .canonical,
                canonicalJobAllowed: true,
                suppressLegacyFreshJob: canonicalJobStarted || gateAllowsCanonical,
                suppressCanonicalFreshJob: false,
                allowLegacyFallback: legacyFallbackAvailable,
                suppressLegacyCompletedState: false,
                reason: "canonical full sync owner"
            )
        }
    }
}

nonisolated enum CanonicalUploadStatusProjection: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case hidden
    case deferred
    case pending
    case uploading
    case retryPending
    case finalizing
    case uploaded
    case conflict
    case blocked
    case failed
}

nonisolated struct CanonicalUploadStatusProjectionResult: Codable, Equatable, Sendable {
    var objectID: String
    var projection: CanonicalUploadStatusProjection
    var readStatus: CanonicalAudioUploadReadStatus
    var report: CanonicalUploadStateReconciliationReport
    var diagnostics: [CanonicalUploadStateDiagnostic]

    nonisolated init(report: CanonicalUploadStateReconciliationReport) {
        self.objectID = report.objectID
        self.report = report
        self.readStatus = CanonicalAudioUploadReadStatus(report.decision)
        switch report.decision {
        case .absentLocalAudio:
            self.projection = .hidden
        case .peerUnknownDeferred:
            self.projection = .deferred
        case .peerMetadataOnlyNeedsUpload, .peerReceiveRecordOnlyNeedsUpload, .peerStudyItemOnlyNeedsUpload, .uploadPending:
            self.projection = .pending
        case .uploadStarting, .uploadInProgress, .uploadInterrupted:
            self.projection = .uploading
        case .uploadRetryScheduled:
            self.projection = .retryPending
        case .uploadFinalizing, .uploadFinalizedProofPending:
            self.projection = .finalizing
        case .uploadCompletedVerified, .uploadNoOpSameAudio:
            self.projection = .uploaded
        case .uploadConflictDifferentAudio:
            self.projection = .conflict
        case .uploadBlockedTombstoned, .uploadBlockedPolicy, .uploadUnsupported:
            self.projection = .blocked
        case .uploadFailedNetwork, .uploadFailedSecurity, .uploadFailedVerification, .uploadLegacyFallback:
            self.projection = .failed
        }
        var diagnostics = report.diagnostics
        diagnostics.append(
            CanonicalUploadStateDiagnostic(
                kind: .canonicalUploadStatusProjectionBuilt,
                objectID: report.objectID,
                state: report.decision,
                reason: projection.rawValue
            )
        )
        self.diagnostics = diagnostics
    }
}
