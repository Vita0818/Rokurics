//
//  CanonicalAudioUploadCutover.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/4.
//

import Foundation

nonisolated enum CanonicalAudioUploadCutoverDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case audioUpload
}

nonisolated enum CanonicalAudioUploadActionKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case audioUploadNoOp
    case audioUploadShadowRehearsal
    case audioUploadCanaryCandidate
    case audioUploadConflictRecord
    case audioUploadDeferredPeerUnknown
    case unsupported
}

nonisolated enum CanonicalAudioUploadPeerState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case unknown
    case missing
    case metadataOnly
    case available
    case different
    case deleted
}

nonisolated enum CanonicalAudioUploadEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case complete
    case blocked
    case conflict
    case deferred
    case disabled
}

nonisolated enum CanonicalAudioUploadEvidenceBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case localAudioMissing
    case localHashUnavailable
    case localByteSizeUnavailable
    case peerTruthMissing
    case peerUnknown
    case completedLedgerWithoutPeerMatch
    case metadataUploadedNotAudioProof
    case receiveRecordNotAudioProof
    case uiUploadedNotAudioProof
    case viewRefreshSuppressed
    case retryDrainerFreshJobSuppressed
    case manualUploadButtonLegacyOwned
    case differentHashOrSize
    case productionUploadSuppressed
    case canaryStageBlocked
    case unsupportedProductionCommit
    case shadowRehearsalFailed
}

nonisolated enum CanonicalAudioUploadLedgerPhase: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case queued
    case inFlight
    case finalizing
    case completed
    case failed
    case retryPending
    case fatalFailed
}

nonisolated enum CanonicalAudioUploadTriggerSource: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case manualUploadButton
    case retryDrainer
    case manualSyncIPhone
    case manualSyncMacHint
    case periodicSync
    case appActivationRefresh
    case viewRefresh
    case ordinarySync

    nonisolated static func from(_ trigger: CanonicalSyncPlanTrigger) -> CanonicalAudioUploadTriggerSource {
        switch trigger {
        case .manual: return .manualSyncIPhone
        case .periodic: return .periodicSync
        case .appActivation: return .appActivationRefresh
        case .retryDrainer: return .retryDrainer
        case .viewRefresh: return .viewRefresh
        }
    }

    nonisolated var canonicalSyncPlanTrigger: CanonicalSyncPlanTrigger {
        switch self {
        case .manualUploadButton, .manualSyncIPhone, .manualSyncMacHint:
            return .manual
        case .periodicSync, .ordinarySync:
            return .periodic
        case .appActivationRefresh:
            return .appActivation
        case .retryDrainer:
            return .retryDrainer
        case .viewRefresh:
            return .viewRefresh
        }
    }

    nonisolated var isViewRefresh: Bool {
        self == .viewRefresh
    }

    nonisolated var isRetryDrainer: Bool {
        self == .retryDrainer
    }

    nonisolated var isExplicitManualUploadButton: Bool {
        self == .manualUploadButton
    }
}

nonisolated enum CanonicalAudioUploadNodeRole: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case iPhone
    case mac
    case testHarness
}

nonisolated struct CanonicalAudioUploadLocalTruth: Codable, Equatable, Sendable {
    var audioAvailable: Bool
    var contentHash: CanonicalHash?
    var byteSize: Int64?
    var modifiedAt: CanonicalTimestamp?
    var logicalPathToken: String?
    var sourceDeviceID: String?
    var diagnosticsSummary: String?

    nonisolated init(
        audioAvailable: Bool,
        contentHash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        modifiedAt: CanonicalTimestamp? = nil,
        logicalPathToken: String? = nil,
        sourceDeviceID: String? = nil,
        diagnosticsSummary: String? = nil
    ) {
        self.audioAvailable = audioAvailable
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.logicalPathToken = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken)
        self.sourceDeviceID = Self.safeText(sourceDeviceID)
        self.diagnosticsSummary = Self.safeText(diagnosticsSummary)
    }

    nonisolated static func available(
        hash: CanonicalHash,
        byteSize: Int64,
        logicalPathToken: String? = nil,
        sourceDeviceID: String? = nil
    ) -> CanonicalAudioUploadLocalTruth {
        CanonicalAudioUploadLocalTruth(
            audioAvailable: true,
            contentHash: hash,
            byteSize: byteSize,
            logicalPathToken: logicalPathToken,
            sourceDeviceID: sourceDeviceID
        )
    }

    nonisolated static func from(_ object: CanonicalRecordingObject) -> CanonicalAudioUploadLocalTruth {
        let audio = object.audioArtifact
        let available = audio?.availability == .available || audio?.availability == .availableWithoutHash
        return CanonicalAudioUploadLocalTruth(
            audioAvailable: available && audio?.tombstone != true,
            contentHash: audio?.contentHash,
            byteSize: audio?.byteSize,
            modifiedAt: audio?.modifiedAt,
            logicalPathToken: audio?.logicalPathToken,
            sourceDeviceID: object.nodeID,
            diagnosticsSummary: "availability=\(audio?.availability.rawValue ?? "missing")"
        )
    }

    nonisolated var hashAvailable: Bool {
        contentHash != nil
    }

    nonisolated var byteSizeAvailable: Bool {
        byteSize != nil
    }

    nonisolated var sufficientForUploadCandidate: Bool {
        audioAvailable && hashAvailable && byteSizeAvailable
    }

    nonisolated private static func safeText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(160))
    }
}

nonisolated struct CanonicalAudioUploadPeerTruth: Codable, Equatable, Sendable {
    var state: CanonicalAudioUploadPeerState
    var contentHash: CanonicalHash?
    var byteSize: Int64?
    var receiveRecordExists: Bool
    var metadataUploaded: Bool
    var uiUploaded: Bool
    var diagnosticsSummary: String?

    nonisolated init(
        state: CanonicalAudioUploadPeerState,
        contentHash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        receiveRecordExists: Bool = false,
        metadataUploaded: Bool = false,
        uiUploaded: Bool = false,
        diagnosticsSummary: String? = nil
    ) {
        self.state = state
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.receiveRecordExists = receiveRecordExists
        self.metadataUploaded = metadataUploaded
        self.uiUploaded = uiUploaded
        self.diagnosticsSummary = Self.safeText(diagnosticsSummary)
    }

    nonisolated static func from(_ object: CanonicalRecordingObject?) -> CanonicalAudioUploadPeerTruth {
        guard let object else {
            return CanonicalAudioUploadPeerTruth(state: .missing, diagnosticsSummary: "peerObjectMissing")
        }
        guard let audio = object.audioArtifact else {
            return CanonicalAudioUploadPeerTruth(state: .metadataOnly, diagnosticsSummary: "peerMetadataOnly")
        }
        let state: CanonicalAudioUploadPeerState
        switch audio.availability {
        case .unknown:
            state = .unknown
        case .missing:
            state = .missing
        case .availableWithoutHash, .available:
            state = audio.tombstone == true ? .deleted : .available
        }
        return CanonicalAudioUploadPeerTruth(
            state: state,
            contentHash: audio.contentHash,
            byteSize: audio.byteSize,
            diagnosticsSummary: "availability=\(audio.availability.rawValue)"
        )
    }

    nonisolated func peerTruthSufficientForNoOp(local: CanonicalAudioUploadLocalTruth) -> Bool {
        guard state == .available,
              let peerHash = contentHash,
              let peerByteSize = byteSize,
              let localHash = local.contentHash,
              let localByteSize = local.byteSize else {
            return false
        }
        return peerHash == localHash && peerByteSize == localByteSize
    }

    nonisolated private static func safeText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(160))
    }
}

nonisolated struct CanonicalAudioUploadLedgerTruth: Codable, Equatable, Sendable {
    var phase: CanonicalAudioUploadLedgerPhase
    var contentHash: CanonicalHash?
    var byteSize: Int64?
    var metadataUploaded: Bool
    var uiUploaded: Bool
    var receiveRecordExists: Bool

    nonisolated init(
        phase: CanonicalAudioUploadLedgerPhase = .none,
        contentHash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        metadataUploaded: Bool = false,
        uiUploaded: Bool = false,
        receiveRecordExists: Bool = false
    ) {
        self.phase = phase
        self.contentHash = contentHash
        self.byteSize = byteSize
        self.metadataUploaded = metadataUploaded
        self.uiUploaded = uiUploaded
        self.receiveRecordExists = receiveRecordExists
    }
}

nonisolated struct CanonicalAudioUploadRetryTruth: Codable, Equatable, Sendable {
    var hasExistingEligibleRetry: Bool
    var retryPending: Bool
    var canFreshCreateJob: Bool

    nonisolated init(
        hasExistingEligibleRetry: Bool = false,
        retryPending: Bool = false,
        canFreshCreateJob: Bool = false
    ) {
        self.hasExistingEligibleRetry = hasExistingEligibleRetry
        self.retryPending = retryPending
        self.canFreshCreateJob = canFreshCreateJob
    }
}

nonisolated enum CanonicalAudioUploadDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalAudioUploadCutoverGateEvaluated
    case canonicalAudioUploadCutoverGateAllowed
    case canonicalAudioUploadCutoverGateBlocked
    case canonicalAudioUploadEvidenceBuilt
    case canonicalAudioUploadEvidenceBlocked
    case canonicalAudioUploadPeerSameNoOp
    case canonicalAudioUploadPeerUnknownDeferred
    case canonicalAudioUploadConflictDetected
    case canonicalAudioUploadCompletedLedgerRejectedAsNoOp
    case canonicalAudioUploadMetadataUploadedRejectedAsAudioProof
    case canonicalAudioUploadReceiveRecordRejectedAsAudioProof
    case canonicalAudioUploadUIUploadedRejectedAsAudioProof
    case canonicalAudioUploadViewRefreshSuppressed
    case canonicalAudioUploadRetryDrainerFreshJobSuppressed
    case canonicalAudioUploadManualButtonLegacyOwned
    case canonicalAudioUploadShadowRehearsalStarted
    case canonicalAudioUploadShadowRehearsalCompleted
    case canonicalAudioUploadShadowReceiverWrote
    case canonicalAudioUploadShadowReceiverNoOp
    case canonicalAudioUploadNoCommitStarted
    case canonicalAudioUploadNoCommitCompleted
    case canonicalAudioUploadProductionCoordinatorSuppressed
    case canonicalAudioUploadRecordingUploadClientSuppressed
    case canonicalAudioUploadSecureMacUploadClientSuppressed
    case canonicalAudioUploadInboxWriteSuppressed
    case canonicalAudioUploadReceiveJSONWriteSuppressed
    case canonicalAudioUploadLedgerMutationSuppressed
    case canonicalAudioUploadRetryDrainerMutationSuppressed
    case canonicalAudioUploadLegacyFallbackPreserved
    case canonicalAudioUploadRuntimeModeEvaluated
    case canonicalAudioUploadRuntimeCandidateSelected
    case canonicalAudioUploadRuntimeCandidateBlocked
    case canonicalAudioUploadRuntimePeerMetadataOnlyCandidate
    case canonicalAudioUploadRuntimeSameAudioNoOp
    case canonicalAudioUploadRuntimeStarted
    case canonicalAudioUploadRuntimeSessionStarted
    case canonicalAudioUploadRuntimeChunkSent
    case canonicalAudioUploadRuntimeChunkConfirmed
    case canonicalAudioUploadRuntimeDuplicateChunkAccepted
    case canonicalAudioUploadRuntimeWrongOffsetDetected
    case canonicalAudioUploadRuntimeResumeStarted
    case canonicalAudioUploadRuntimeSessionResumed
    case canonicalAudioUploadRuntimeFinalizeStarted
    case canonicalAudioUploadRuntimeFinalizeCompleted
    case canonicalAudioUploadRuntimeFinalizeFailed
    case canonicalAudioUploadRuntimeRetryScheduled
    case canonicalAudioUploadRuntimeRetryExhausted
    case canonicalAudioUploadRuntimeLegacyFallbackUsed
    case canonicalAudioUploadRuntimePeerUnknownDeferred
    case canonicalAudioUploadRuntimeConflictBlocked
    case canonicalAudioUploadRuntimeExistingDifferentAudioBlocked
    case canonicalAudioUploadRuntimeCompletedLedgerRejectedAsNoOp
    case canonicalAudioUploadRuntimeDidNotOverwriteExistingAudio
    case canonicalAudioUploadRuntimeDidNotMarkCompletedWithoutProof
    case canonicalAudioUploadRuntimeReportBuilt
    case canonicalAudioUploadReadSideProjectionStarted
    case canonicalAudioUploadReadSideProjectionEquivalent
    case canonicalAudioUploadReadSideProjectionDiverged
    case canonicalAudioUploadAbortRollbackPolicyEvaluated
}

nonisolated struct CanonicalAudioUploadDiagnostic: Codable, Equatable, Sendable {
    var kind: CanonicalAudioUploadDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalAudioUploadTriggerSource
    var nodeRole: CanonicalAudioUploadNodeRole
    var domain: CanonicalAudioUploadCutoverDomain
    var objectID: String?
    var peerState: CanonicalAudioUploadPeerState?
    var ledgerPhase: CanonicalAudioUploadLedgerPhase?
    var action: CanonicalAudioUploadActionKind?
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalAudioUploadDiagnosticKind,
        syncRunID: String? = nil,
        trigger: CanonicalAudioUploadTriggerSource,
        nodeRole: CanonicalAudioUploadNodeRole,
        domain: CanonicalAudioUploadCutoverDomain = .audioUpload,
        objectID: String? = nil,
        peerState: CanonicalAudioUploadPeerState? = nil,
        ledgerPhase: CanonicalAudioUploadLedgerPhase? = nil,
        action: CanonicalAudioUploadActionKind? = nil,
        result: String? = nil,
        reason: String? = nil,
        hashPrefix: String? = nil
    ) {
        self.kind = kind
        self.syncRunID = Self.safeText(syncRunID, maxLength: 96)
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.domain = domain
        self.objectID = Self.safeText(objectID, maxLength: 96)
        self.peerState = peerState
        self.ledgerPhase = ledgerPhase
        self.action = action
        self.result = Self.safeText(result, maxLength: 96)
        self.reason = Self.safeText(reason, maxLength: 160)
        self.hashPrefix = hashPrefix.map { String($0.prefix(12)) }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            "domain=\(domain.rawValue)",
            objectID.map { "objectID=\($0)" },
            peerState.map { "peerState=\($0.rawValue)" },
            ledgerPhase.map { "ledgerPhase=\($0.rawValue)" },
            action.map { "action=\($0.rawValue)" },
            result.map { "result=\($0)" },
            reason.map { "reason=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    nonisolated private static func safeText(_ value: String?, maxLength: Int) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(maxLength))
    }
}

nonisolated struct CanonicalAudioUploadCutoverCandidate: Codable, Equatable, Sendable {
    var objectID: String
    var localTruth: CanonicalAudioUploadLocalTruth
    var peerTruth: CanonicalAudioUploadPeerTruth
    var ledgerTruth: CanonicalAudioUploadLedgerTruth
    var retryTruth: CanonicalAudioUploadRetryTruth
    var trigger: CanonicalAudioUploadTriggerSource
    var actionKind: CanonicalAudioUploadActionKind
    var reason: String
    var evidenceStatus: CanonicalAudioUploadEvidenceStatus
    var evidenceBlockers: [CanonicalAudioUploadEvidenceBlocker]
    var diagnostics: [CanonicalAudioUploadDiagnosticKind]
    var manualUserAction: Bool
    var ordinarySync: Bool
    var retryDrainer: Bool
    var productionUploadSuppressed: Bool
    var legacyUploadCoordinatorNotCalled: Bool
    var recordingUploadClientNotCalled: Bool
    var secureMacUploadClientNotCalled: Bool

    nonisolated init(
        objectID: String,
        localTruth: CanonicalAudioUploadLocalTruth,
        peerTruth: CanonicalAudioUploadPeerTruth,
        ledgerTruth: CanonicalAudioUploadLedgerTruth = CanonicalAudioUploadLedgerTruth(),
        retryTruth: CanonicalAudioUploadRetryTruth = CanonicalAudioUploadRetryTruth(),
        trigger: CanonicalAudioUploadTriggerSource,
        actionKind: CanonicalAudioUploadActionKind,
        reason: String,
        evidenceStatus: CanonicalAudioUploadEvidenceStatus,
        evidenceBlockers: [CanonicalAudioUploadEvidenceBlocker] = [],
        diagnostics: [CanonicalAudioUploadDiagnosticKind] = []
    ) {
        let trimmedObjectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.objectID = trimmedObjectID.isEmpty ? "object:unknown" : trimmedObjectID
        self.localTruth = localTruth
        self.peerTruth = peerTruth
        self.ledgerTruth = ledgerTruth
        self.retryTruth = retryTruth
        self.trigger = trigger
        self.actionKind = actionKind
        self.reason = reason
        self.evidenceStatus = evidenceStatus
        self.evidenceBlockers = Array(Set(evidenceBlockers)).sorted { $0.rawValue < $1.rawValue }
        self.diagnostics = Array(Set(diagnostics)).sorted { $0.rawValue < $1.rawValue }
        self.manualUserAction = trigger.isExplicitManualUploadButton
        self.ordinarySync = trigger == .ordinarySync || trigger == .periodicSync || trigger == .appActivationRefresh
        self.retryDrainer = trigger.isRetryDrainer
        self.productionUploadSuppressed = true
        self.legacyUploadCoordinatorNotCalled = true
        self.recordingUploadClientNotCalled = true
        self.secureMacUploadClientNotCalled = true
    }

    nonisolated var canaryEligibleInShadowOnlyModel: Bool {
        actionKind == .audioUploadCanaryCandidate
            && evidenceStatus == .complete
            && productionUploadSuppressed
    }

    nonisolated var hashPrefix: String? {
        localTruth.contentHash.map { String($0.value.prefix(12)) }
    }

    nonisolated static func evaluate(
        objectID: String,
        localTruth: CanonicalAudioUploadLocalTruth,
        peerTruth: CanonicalAudioUploadPeerTruth,
        ledgerTruth: CanonicalAudioUploadLedgerTruth = CanonicalAudioUploadLedgerTruth(),
        retryTruth: CanonicalAudioUploadRetryTruth = CanonicalAudioUploadRetryTruth(),
        trigger: CanonicalAudioUploadTriggerSource
    ) -> CanonicalAudioUploadCutoverCandidate {
        var blockers: [CanonicalAudioUploadEvidenceBlocker] = []
        var diagnostics: [CanonicalAudioUploadDiagnosticKind] = [.canonicalAudioUploadEvidenceBuilt]

        if trigger.isViewRefresh {
            blockers.append(.viewRefreshSuppressed)
            diagnostics.append(.canonicalAudioUploadViewRefreshSuppressed)
            return make(
                objectID: objectID,
                localTruth: localTruth,
                peerTruth: peerTruth,
                ledgerTruth: ledgerTruth,
                retryTruth: retryTruth,
                trigger: trigger,
                actionKind: .unsupported,
                reason: "viewRefreshNeverCreatesAudioUploadCandidate",
                status: .blocked,
                blockers: blockers,
                diagnostics: diagnostics
            )
        }

        if trigger.isExplicitManualUploadButton {
            blockers.append(.manualUploadButtonLegacyOwned)
            diagnostics.append(.canonicalAudioUploadManualButtonLegacyOwned)
            return make(
                objectID: objectID,
                localTruth: localTruth,
                peerTruth: peerTruth,
                ledgerTruth: ledgerTruth,
                retryTruth: retryTruth,
                trigger: trigger,
                actionKind: .unsupported,
                reason: "explicitManualUploadButtonStaysLegacyOwnedInV812",
                status: .blocked,
                blockers: blockers,
                diagnostics: diagnostics
            )
        }

        if trigger.isRetryDrainer, !retryTruth.hasExistingEligibleRetry {
            blockers.append(.retryDrainerFreshJobSuppressed)
            diagnostics.append(.canonicalAudioUploadRetryDrainerFreshJobSuppressed)
            return make(
                objectID: objectID,
                localTruth: localTruth,
                peerTruth: peerTruth,
                ledgerTruth: ledgerTruth,
                retryTruth: retryTruth,
                trigger: trigger,
                actionKind: .unsupported,
                reason: "retryDrainerCannotCreateFreshAudioUploadJob",
                status: .blocked,
                blockers: blockers,
                diagnostics: diagnostics
            )
        }

        if !localTruth.audioAvailable {
            blockers.append(.localAudioMissing)
        }
        if localTruth.contentHash == nil {
            blockers.append(.localHashUnavailable)
        }
        if localTruth.byteSize == nil {
            blockers.append(.localByteSizeUnavailable)
        }

        let peerNoOpProof = peerTruth.peerTruthSufficientForNoOp(local: localTruth)
        if ledgerTruth.phase == .completed, !peerNoOpProof {
            blockers.append(.completedLedgerWithoutPeerMatch)
            diagnostics.append(.canonicalAudioUploadCompletedLedgerRejectedAsNoOp)
        }
        if ledgerTruth.metadataUploaded || peerTruth.metadataUploaded {
            diagnostics.append(.canonicalAudioUploadMetadataUploadedRejectedAsAudioProof)
            if !peerNoOpProof {
                blockers.append(.metadataUploadedNotAudioProof)
            }
        }
        if ledgerTruth.receiveRecordExists || peerTruth.receiveRecordExists {
            diagnostics.append(.canonicalAudioUploadReceiveRecordRejectedAsAudioProof)
            if !peerNoOpProof {
                blockers.append(.receiveRecordNotAudioProof)
            }
        }
        if ledgerTruth.uiUploaded || peerTruth.uiUploaded {
            diagnostics.append(.canonicalAudioUploadUIUploadedRejectedAsAudioProof)
            if !peerNoOpProof {
                blockers.append(.uiUploadedNotAudioProof)
            }
        }

        if peerNoOpProof, localTruth.sufficientForUploadCandidate {
            diagnostics.append(.canonicalAudioUploadPeerSameNoOp)
            return make(
                objectID: objectID,
                localTruth: localTruth,
                peerTruth: peerTruth,
                ledgerTruth: ledgerTruth,
                retryTruth: retryTruth,
                trigger: trigger,
                actionKind: .audioUploadNoOp,
                reason: "peerAudioHashAndSizeMatch",
                status: .complete,
                blockers: [],
                diagnostics: diagnostics
            )
        }

        if !localTruth.sufficientForUploadCandidate {
            diagnostics.append(.canonicalAudioUploadEvidenceBlocked)
            return make(
                objectID: objectID,
                localTruth: localTruth,
                peerTruth: peerTruth,
                ledgerTruth: ledgerTruth,
                retryTruth: retryTruth,
                trigger: trigger,
                actionKind: .unsupported,
                reason: "localAudioTruthIncomplete",
                status: .blocked,
                blockers: blockers,
                diagnostics: diagnostics
            )
        }

        switch peerTruth.state {
        case .missing, .metadataOnly:
            return make(
                objectID: objectID,
                localTruth: localTruth,
                peerTruth: peerTruth,
                ledgerTruth: ledgerTruth,
                retryTruth: retryTruth,
                trigger: trigger,
                actionKind: .audioUploadCanaryCandidate,
                reason: peerTruth.state == .missing ? "peerAudioMissing" : "peerMetadataOnlyAudioMissing",
                status: blockers.isEmpty ? .complete : .blocked,
                blockers: blockers,
                diagnostics: diagnostics
            )
        case .unknown:
            blockers.append(.peerUnknown)
            diagnostics.append(.canonicalAudioUploadPeerUnknownDeferred)
            return make(
                objectID: objectID,
                localTruth: localTruth,
                peerTruth: peerTruth,
                ledgerTruth: ledgerTruth,
                retryTruth: retryTruth,
                trigger: trigger,
                actionKind: .audioUploadDeferredPeerUnknown,
                reason: "peerAudioUnknownIsDeferredInV812",
                status: .deferred,
                blockers: blockers,
                diagnostics: diagnostics
            )
        case .available:
            if peerTruth.contentHash == nil || peerTruth.byteSize == nil {
                blockers.append(.peerTruthMissing)
                diagnostics.append(.canonicalAudioUploadEvidenceBlocked)
                return make(
                    objectID: objectID,
                    localTruth: localTruth,
                    peerTruth: peerTruth,
                    ledgerTruth: ledgerTruth,
                    retryTruth: retryTruth,
                    trigger: trigger,
                    actionKind: .unsupported,
                    reason: "peerAvailableWithoutHashOrSizeCannotNoOp",
                    status: .blocked,
                    blockers: blockers,
                    diagnostics: diagnostics
                )
            }
            blockers.append(.differentHashOrSize)
            diagnostics.append(.canonicalAudioUploadConflictDetected)
            return make(
                objectID: objectID,
                localTruth: localTruth,
                peerTruth: peerTruth,
                ledgerTruth: ledgerTruth,
                retryTruth: retryTruth,
                trigger: trigger,
                actionKind: .audioUploadConflictRecord,
                reason: "peerAudioHashOrSizeDifferent",
                status: .conflict,
                blockers: blockers,
                diagnostics: diagnostics
            )
        case .different, .deleted:
            blockers.append(.differentHashOrSize)
            diagnostics.append(.canonicalAudioUploadConflictDetected)
            return make(
                objectID: objectID,
                localTruth: localTruth,
                peerTruth: peerTruth,
                ledgerTruth: ledgerTruth,
                retryTruth: retryTruth,
                trigger: trigger,
                actionKind: .audioUploadConflictRecord,
                reason: peerTruth.state == .deleted ? "peerAudioDeletedRequiresConflictNotOverwrite" : "peerAudioDifferent",
                status: .conflict,
                blockers: blockers,
                diagnostics: diagnostics
            )
        }
    }

    nonisolated static func candidates(
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest?,
        trigger: CanonicalAudioUploadTriggerSource,
        ledgerTruths: [String: CanonicalAudioUploadLedgerTruth] = [:],
        retryTruths: [String: CanonicalAudioUploadRetryTruth] = [:]
    ) -> [CanonicalAudioUploadCutoverCandidate] {
        let peerObjects = Dictionary(uniqueKeysWithValues: (peerManifest?.objects ?? []).map { ($0.objectID, $0) })
        return localManifest.objects.compactMap { object in
            guard object.audioArtifact != nil else {
                return nil
            }
            let objectID = object.objectID
            return evaluate(
                objectID: objectID,
                localTruth: CanonicalAudioUploadLocalTruth.from(object),
                peerTruth: peerManifest == nil ? CanonicalAudioUploadPeerTruth(state: .unknown, diagnosticsSummary: "peerManifestUnavailable") : CanonicalAudioUploadPeerTruth.from(peerObjects[objectID]),
                ledgerTruth: ledgerTruths[objectID] ?? CanonicalAudioUploadLedgerTruth(),
                retryTruth: retryTruths[objectID] ?? CanonicalAudioUploadRetryTruth(),
                trigger: trigger
            )
        }
    }

    nonisolated private static func make(
        objectID: String,
        localTruth: CanonicalAudioUploadLocalTruth,
        peerTruth: CanonicalAudioUploadPeerTruth,
        ledgerTruth: CanonicalAudioUploadLedgerTruth,
        retryTruth: CanonicalAudioUploadRetryTruth,
        trigger: CanonicalAudioUploadTriggerSource,
        actionKind: CanonicalAudioUploadActionKind,
        reason: String,
        status: CanonicalAudioUploadEvidenceStatus,
        blockers: [CanonicalAudioUploadEvidenceBlocker],
        diagnostics: [CanonicalAudioUploadDiagnosticKind]
    ) -> CanonicalAudioUploadCutoverCandidate {
        CanonicalAudioUploadCutoverCandidate(
            objectID: objectID,
            localTruth: localTruth,
            peerTruth: peerTruth,
            ledgerTruth: ledgerTruth,
            retryTruth: retryTruth,
            trigger: trigger,
            actionKind: actionKind,
            reason: reason,
            evidenceStatus: status,
            evidenceBlockers: blockers,
            diagnostics: diagnostics
        )
    }
}

nonisolated struct CanonicalAudioUploadEvidenceReport: Codable, Equatable, Sendable {
    var candidates: [CanonicalAudioUploadCutoverCandidate]
    var completeCount: Int
    var blockedCount: Int
    var deferredCount: Int
    var conflictCount: Int
    var diagnosticsRedacted: Bool
    var diagnosticsSummary: String

    nonisolated init(candidates: [CanonicalAudioUploadCutoverCandidate]) {
        self.candidates = candidates.sorted { $0.objectID < $1.objectID }
        self.completeCount = candidates.filter { $0.evidenceStatus == .complete }.count
        self.blockedCount = candidates.filter { $0.evidenceStatus == .blocked }.count
        self.deferredCount = candidates.filter { $0.evidenceStatus == .deferred }.count
        self.conflictCount = candidates.filter { $0.evidenceStatus == .conflict }.count
        self.diagnosticsRedacted = true
        self.diagnosticsSummary = [
            "candidateCount=\(candidates.count)",
            "complete=\(completeCount)",
            "blocked=\(blockedCount)",
            "deferred=\(deferredCount)",
            "conflict=\(conflictCount)",
            "diagnosticsRedacted=true"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalAudioUploadCutoverEvidence: Codable, Equatable, Sendable {
    var localAudioDescriptorsReviewed: Bool
    var peerAudioDescriptorsReviewed: Bool
    var shadowReceiverRehearsalPassed: Bool
    var noCommitObserved: Bool
    var readSideProjectionObserved: Bool
    var abortRollbackPolicyDocumented: Bool
    var legacyFallbackAvailable: Bool
    var evidenceReport: CanonicalAudioUploadEvidenceReport?

    nonisolated init(
        localAudioDescriptorsReviewed: Bool = false,
        peerAudioDescriptorsReviewed: Bool = false,
        shadowReceiverRehearsalPassed: Bool = false,
        noCommitObserved: Bool = false,
        readSideProjectionObserved: Bool = false,
        abortRollbackPolicyDocumented: Bool = false,
        legacyFallbackAvailable: Bool = true,
        evidenceReport: CanonicalAudioUploadEvidenceReport? = nil
    ) {
        self.localAudioDescriptorsReviewed = localAudioDescriptorsReviewed
        self.peerAudioDescriptorsReviewed = peerAudioDescriptorsReviewed
        self.shadowReceiverRehearsalPassed = shadowReceiverRehearsalPassed
        self.noCommitObserved = noCommitObserved
        self.readSideProjectionObserved = readSideProjectionObserved
        self.abortRollbackPolicyDocumented = abortRollbackPolicyDocumented
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.evidenceReport = evidenceReport
    }

    nonisolated static func passing(report: CanonicalAudioUploadEvidenceReport? = nil) -> CanonicalAudioUploadCutoverEvidence {
        CanonicalAudioUploadCutoverEvidence(
            localAudioDescriptorsReviewed: true,
            peerAudioDescriptorsReviewed: true,
            shadowReceiverRehearsalPassed: true,
            noCommitObserved: true,
            readSideProjectionObserved: true,
            abortRollbackPolicyDocumented: true,
            legacyFallbackAvailable: true,
            evidenceReport: report
        )
    }

    nonisolated var isPassing: Bool {
        localAudioDescriptorsReviewed
            && peerAudioDescriptorsReviewed
            && shadowReceiverRehearsalPassed
            && noCommitObserved
            && readSideProjectionObserved
            && abortRollbackPolicyDocumented
            && legacyFallbackAvailable
    }
}

nonisolated enum CanonicalAudioUploadCanaryStage: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case shadowOnly
    case n0
    case n1
    case n3
    case n10
    case allEligible

    nonisolated var canaryBudget: Int {
        switch self {
        case .disabled, .shadowOnly, .n0:
            return 0
        case .n1:
            return 1
        case .n3:
            return 3
        case .n10:
            return 10
        case .allEligible:
            return Int.max
        }
    }

    nonisolated var requestsProductionCanary: Bool {
        canaryBudget > 0
    }
}

nonisolated struct CanonicalAudioUploadCanaryPolicy: Codable, Equatable, Sendable {
    var requestedStage: CanonicalAudioUploadCanaryStage
    var allowsTestOnlyFutureStage: Bool
    var requireEvidence: Bool
    var maxDiagnosticsEvents: Int

    nonisolated init(
        requestedStage: CanonicalAudioUploadCanaryStage = .disabled,
        allowsTestOnlyFutureStage: Bool = false,
        requireEvidence: Bool = true,
        maxDiagnosticsEvents: Int = 200
    ) {
        self.requestedStage = requestedStage
        self.allowsTestOnlyFutureStage = allowsTestOnlyFutureStage
        self.requireEvidence = requireEvidence
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
    }

    nonisolated static let disabled = CanonicalAudioUploadCanaryPolicy()

    nonisolated var canaryMaxObjectsPerSyncRun: Int {
        requestedStage.canaryBudget == Int.max ? Int.max : max(0, requestedStage.canaryBudget)
    }

    nonisolated var productionCommitAllowedInV812: Bool {
        false
    }
}

nonisolated enum CanonicalAudioUploadCutoverFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case canaryBudgetZero
    case missingCutoverToken
    case insufficientEvidence
    case candidateEvidenceBlocked
    case noEligibleCandidates
    case productionCommitBlockedV812
    case peerSnapshotUnavailable
    case manualUserActionLegacyOwned
    case futureCanaryStageBlocked
    case shadowRehearsalFailed
}

nonisolated struct CanonicalAudioUploadCutoverGate: Codable, Equatable, Sendable {
    var allowed: Bool
    var productionUploadAllowed: Bool
    var shadowOnlyAllowed: Bool
    var mode: CanonicalCutoverMode
    var canaryStage: CanonicalAudioUploadCanaryStage
    var failures: [CanonicalAudioUploadCutoverFailure]
    var reason: String

    nonisolated init(
        allowed: Bool,
        productionUploadAllowed: Bool = false,
        shadowOnlyAllowed: Bool = false,
        mode: CanonicalCutoverMode,
        canaryStage: CanonicalAudioUploadCanaryStage,
        failures: [CanonicalAudioUploadCutoverFailure] = [],
        reason: String
    ) {
        self.allowed = allowed
        self.productionUploadAllowed = productionUploadAllowed
        self.shadowOnlyAllowed = shadowOnlyAllowed
        self.mode = mode
        self.canaryStage = canaryStage
        self.failures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        self.reason = reason
    }
}

nonisolated struct CanonicalAudioUploadCutoverRunner {
    nonisolated init() {}

    nonisolated func evaluateGate(
        mode: CanonicalCutoverMode,
        policy: CanonicalAudioUploadCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalAudioUploadCutoverEvidence,
        candidates: [CanonicalAudioUploadCutoverCandidate],
        trigger: CanonicalAudioUploadTriggerSource
    ) -> CanonicalAudioUploadCutoverGate {
        var failures: [CanonicalAudioUploadCutoverFailure] = []
        let eligibleCandidates = candidates.filter(\.canaryEligibleInShadowOnlyModel)

        if mode == .disabled || policy.requestedStage == .disabled {
            failures.append(.disabled)
        }
        if mode.permitsProductionCommit || policy.requestedStage.requestsProductionCanary {
            failures.append(.productionCommitBlockedV812)
        }
        if policy.requestedStage.requestsProductionCanary, !policy.allowsTestOnlyFutureStage {
            failures.append(.futureCanaryStageBlocked)
        }
        if mode == .canary, policy.canaryMaxObjectsPerSyncRun == 0 {
            failures.append(.canaryBudgetZero)
        }
        if mode.permitsProductionCommit, token == nil {
            failures.append(.missingCutoverToken)
        }
        if policy.requireEvidence, !evidence.isPassing {
            failures.append(.insufficientEvidence)
        }
        if candidates.contains(where: { !$0.evidenceBlockers.isEmpty }) {
            failures.append(.candidateEvidenceBlocked)
        }
        if eligibleCandidates.isEmpty, mode != .disabled {
            failures.append(.noEligibleCandidates)
        }
        if trigger.isExplicitManualUploadButton {
            failures.append(.manualUserActionLegacyOwned)
        }

        let shadowAllowed = failures.isEmpty && (mode == .shadowOnly || mode == .guardedExecuteNoCommit)
        return CanonicalAudioUploadCutoverGate(
            allowed: shadowAllowed,
            productionUploadAllowed: false,
            shadowOnlyAllowed: shadowAllowed,
            mode: mode,
            canaryStage: policy.requestedStage,
            failures: failures,
            reason: failures.isEmpty ? "shadowOnlyNoCommitAllowed" : failures.map(\.rawValue).joined(separator: ",")
        )
    }
}

nonisolated struct CanonicalAudioUploadNoCommitCandidate: Codable, Equatable, Sendable {
    var cutoverCandidate: CanonicalAudioUploadCutoverCandidate

    nonisolated init(cutoverCandidate: CanonicalAudioUploadCutoverCandidate) {
        self.cutoverCandidate = cutoverCandidate
    }
}

nonisolated struct CanonicalAudioUploadNoCommitResult: Codable, Equatable, Sendable {
    var staged: Bool
    var objectID: String
    var nodeRole: CanonicalAudioUploadNodeRole
    var actionKind: CanonicalAudioUploadActionKind
    var wouldRequestRoute: String?
    var payloadHashPrefix: String?
    var payloadByteCount: Int
    var productionUploadSuppressed: Bool
    var legacyUploadCoordinatorNotCalled: Bool
    var recordingUploadClientNotCalled: Bool
    var secureMacUploadClientNotCalled: Bool
    var didNotCreateUploadJob: Bool
    var didNotWriteInbox: Bool
    var didNotWriteReceiveJSON: Bool
    var didNotMutateUploadLedger: Bool
    var didNotMutateRetryDrainer: Bool

    nonisolated init(candidate: CanonicalAudioUploadCutoverCandidate, nodeRole: CanonicalAudioUploadNodeRole) {
        let payloadHash = CanonicalHash.sha256(of: [
            "schema": "canonical-audio-upload-no-commit-v812",
            "objectID": candidate.objectID,
            "action": candidate.actionKind.rawValue,
            "reason": candidate.reason
        ])
        self.staged = candidate.canaryEligibleInShadowOnlyModel || candidate.actionKind == .audioUploadNoOp
        self.objectID = candidate.objectID
        self.nodeRole = nodeRole
        self.actionKind = candidate.actionKind
        self.wouldRequestRoute = candidate.canaryEligibleInShadowOnlyModel ? "/upload-recording-audio-session/start" : nil
        self.payloadHashPrefix = String(payloadHash.value.prefix(12))
        self.payloadByteCount = candidate.objectID.utf8.count + candidate.reason.utf8.count
        self.productionUploadSuppressed = true
        self.legacyUploadCoordinatorNotCalled = true
        self.recordingUploadClientNotCalled = true
        self.secureMacUploadClientNotCalled = true
        self.didNotCreateUploadJob = true
        self.didNotWriteInbox = true
        self.didNotWriteReceiveJSON = true
        self.didNotMutateUploadLedger = true
        self.didNotMutateRetryDrainer = true
    }
}

nonisolated protocol CanonicalAudioUploadNoCommitExecutor: Sendable {
    func stageAudioUploadNoCommit(_ candidate: CanonicalAudioUploadNoCommitCandidate) -> CanonicalAudioUploadNoCommitResult
}

nonisolated struct CanonicalAudioUploadNoCommitRunner {
    nonisolated init() {}

    nonisolated func run(
        mode: CanonicalCutoverMode,
        policy: CanonicalAudioUploadCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalAudioUploadCutoverEvidence,
        candidates: [CanonicalAudioUploadNoCommitCandidate],
        trigger: CanonicalAudioUploadTriggerSource,
        nodeRole: CanonicalAudioUploadNodeRole,
        syncRunID: String?,
        executor: any CanonicalAudioUploadNoCommitExecutor
    ) -> CanonicalAudioUploadCutoverResult {
        let cutoverCandidates = candidates.map(\.cutoverCandidate)
        let gate = CanonicalAudioUploadCutoverRunner().evaluateGate(
            mode: mode,
            policy: policy,
            token: token,
            evidence: evidence,
            candidates: cutoverCandidates,
            trigger: trigger
        )
        var diagnostics: [CanonicalAudioUploadDiagnostic] = [
            CanonicalAudioUploadDiagnostic(
                kind: .canonicalAudioUploadCutoverGateEvaluated,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.reason
            )
        ]
        diagnostics.append(
            CanonicalAudioUploadDiagnostic(
                kind: gate.allowed ? .canonicalAudioUploadCutoverGateAllowed : .canonicalAudioUploadCutoverGateBlocked,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.failures.map(\.rawValue).joined(separator: ",")
            )
        )

        let results: [CanonicalAudioUploadNoCommitResult]
        if mode == .guardedExecuteNoCommit || mode == .shadowOnly {
            diagnostics.append(
                CanonicalAudioUploadDiagnostic(
                    kind: .canonicalAudioUploadNoCommitStarted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "candidateCount=\(candidates.count)",
                    reason: "productionUploadSuppressed"
                )
            )
            results = candidates.map { executor.stageAudioUploadNoCommit($0) }
            diagnostics.append(
                CanonicalAudioUploadDiagnostic(
                    kind: .canonicalAudioUploadNoCommitCompleted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "stagedCount=\(results.filter(\.staged).count)",
                    reason: "noCommitOnly"
                )
            )
        } else {
            results = []
        }

        diagnostics.append(contentsOf: [
            CanonicalAudioUploadDiagnostic(kind: .canonicalAudioUploadProductionCoordinatorSuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "true"),
            CanonicalAudioUploadDiagnostic(kind: .canonicalAudioUploadRecordingUploadClientSuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "true"),
            CanonicalAudioUploadDiagnostic(kind: .canonicalAudioUploadSecureMacUploadClientSuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "true"),
            CanonicalAudioUploadDiagnostic(kind: .canonicalAudioUploadInboxWriteSuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "true"),
            CanonicalAudioUploadDiagnostic(kind: .canonicalAudioUploadReceiveJSONWriteSuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "true"),
            CanonicalAudioUploadDiagnostic(kind: .canonicalAudioUploadLedgerMutationSuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "true"),
            CanonicalAudioUploadDiagnostic(kind: .canonicalAudioUploadRetryDrainerMutationSuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "true"),
            CanonicalAudioUploadDiagnostic(kind: .canonicalAudioUploadLegacyFallbackPreserved, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "true")
        ])

        return CanonicalAudioUploadCutoverResult(
            gate: gate,
            candidates: cutoverCandidates,
            noCommitResults: results,
            diagnostics: diagnostics,
            legacyFallbackPreserved: true,
            runtimeSwitchEnabled: false
        )
    }
}

nonisolated struct CanonicalAudioUploadCutoverResult: Codable, Equatable, Sendable {
    var gate: CanonicalAudioUploadCutoverGate
    var candidates: [CanonicalAudioUploadCutoverCandidate]
    var noCommitResults: [CanonicalAudioUploadNoCommitResult]
    var diagnostics: [CanonicalAudioUploadDiagnostic]
    var legacyFallbackPreserved: Bool
    var runtimeSwitchEnabled: Bool
    var calledProductionUploadCoordinator: Bool
    var calledRecordingUploadClient: Bool
    var calledSecureMacUploadClient: Bool
    var wroteProductionInbox: Bool
    var wroteReceiveJSON: Bool
    var createdUploadJob: Bool
    var mutatedUploadLedger: Bool
    var mutatedRetryDrainer: Bool
    var suppressedLegacyDuplicate: Bool

    nonisolated init(
        gate: CanonicalAudioUploadCutoverGate,
        candidates: [CanonicalAudioUploadCutoverCandidate] = [],
        noCommitResults: [CanonicalAudioUploadNoCommitResult] = [],
        diagnostics: [CanonicalAudioUploadDiagnostic] = [],
        legacyFallbackPreserved: Bool = true,
        runtimeSwitchEnabled: Bool = false
    ) {
        self.gate = gate
        self.candidates = candidates
        self.noCommitResults = noCommitResults
        self.diagnostics = diagnostics
        self.legacyFallbackPreserved = legacyFallbackPreserved
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.calledProductionUploadCoordinator = false
        self.calledRecordingUploadClient = false
        self.calledSecureMacUploadClient = false
        self.wroteProductionInbox = false
        self.wroteReceiveJSON = false
        self.createdUploadJob = false
        self.mutatedUploadLedger = false
        self.mutatedRetryDrainer = false
        self.suppressedLegacyDuplicate = false
    }
}

final class CanonicalAudioUploadShadowReceiver: @unchecked Sendable {
    let rootToken: CanonicalRootToken
    private let receiver: CanonicalShadowUploadReceiver

    nonisolated init(rootToken: CanonicalRootToken = CanonicalRootToken("canonical-audio-upload-shadow")) {
        self.rootToken = rootToken
        self.receiver = CanonicalShadowUploadReceiver(rootToken: rootToken)
    }

    var canonicalReceiver: CanonicalShadowUploadReceiver {
        receiver
    }

    func seed(reference: CanonicalFileReference, bytes: Data) async throws {
        try await receiver.seed(reference: reference, bytes: bytes)
    }

    func read(reference: CanonicalFileReference) async throws -> CanonicalFileReadResult {
        try await receiver.read(reference: reference)
    }
}

nonisolated struct CanonicalAudioUploadShadowRehearsalInput: Sendable {
    var objectID: String
    var logicalPathToken: String
    var bytes: Data
    var chunkSize: Int
    var declaredTotalHash: CanonicalHash?
    var existingReceiverBytes: Data?
    var simulateInterruptionAfterFirstChunk: Bool

    nonisolated init(
        objectID: String,
        logicalPathToken: String,
        bytes: Data,
        chunkSize: Int = 2 * 1024 * 1024,
        declaredTotalHash: CanonicalHash? = nil,
        existingReceiverBytes: Data? = nil,
        simulateInterruptionAfterFirstChunk: Bool = false
    ) {
        let trimmedObjectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.objectID = trimmedObjectID.isEmpty ? "object:unknown" : trimmedObjectID
        self.logicalPathToken = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken) ?? "audio/\(self.objectID).m4a"
        self.bytes = bytes
        self.chunkSize = max(1, chunkSize)
        self.declaredTotalHash = declaredTotalHash
        self.existingReceiverBytes = existingReceiverBytes
        self.simulateInterruptionAfterFirstChunk = simulateInterruptionAfterFirstChunk
    }
}

nonisolated struct CanonicalAudioUploadShadowRehearsalResult: Sendable {
    var shadowResult: CanonicalShadowUploadResult
    var productionUploadSuppressed: Bool
    var calledProductionUploadCoordinator: Bool
    var calledRecordingUploadClient: Bool
    var calledSecureMacUploadClient: Bool
    var wroteProductionInbox: Bool
    var wroteReceiveJSON: Bool
    var diagnostics: [CanonicalAudioUploadDiagnostic]

    nonisolated init(
        shadowResult: CanonicalShadowUploadResult,
        objectID: String,
        syncRunID: String?,
        trigger: CanonicalAudioUploadTriggerSource,
        nodeRole: CanonicalAudioUploadNodeRole
    ) {
        let safeObjectID = {
            let trimmed = objectID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "object:unknown" : trimmed
        }()
        self.shadowResult = shadowResult
        self.productionUploadSuppressed = true
        self.calledProductionUploadCoordinator = false
        self.calledRecordingUploadClient = false
        self.calledSecureMacUploadClient = false
        self.wroteProductionInbox = false
        self.wroteReceiveJSON = false
        self.diagnostics = [
            CanonicalAudioUploadDiagnostic(
                kind: .canonicalAudioUploadShadowRehearsalCompleted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                objectID: safeObjectID,
                action: .audioUploadShadowRehearsal,
                result: shadowResult.completed ? "completed" : "failed",
                reason: shadowResult.divergence.rawValue
            ),
            CanonicalAudioUploadDiagnostic(
                kind: shadowResult.wroteShadowReceiver ? .canonicalAudioUploadShadowReceiverWrote : .canonicalAudioUploadShadowReceiverNoOp,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                objectID: safeObjectID,
                action: .audioUploadShadowRehearsal,
                result: shadowResult.wroteShadowReceiver ? "shadowReceiverWrote" : "shadowReceiverNoOp",
                reason: shadowResult.divergence.rawValue
            )
        ]
    }
}

nonisolated struct CanonicalAudioUploadShadowRehearsal {
    nonisolated init() {}

    func run(
        input: CanonicalAudioUploadShadowRehearsalInput,
        receiver: CanonicalAudioUploadShadowReceiver = CanonicalAudioUploadShadowReceiver(),
        syncRunID: String? = nil,
        trigger: CanonicalAudioUploadTriggerSource = .ordinarySync,
        nodeRole: CanonicalAudioUploadNodeRole = .testHarness
    ) async -> CanonicalAudioUploadShadowRehearsalResult {
        let reference = CanonicalFileReference(
            rootToken: receiver.rootToken,
            logicalPathToken: input.logicalPathToken,
            artifactID: CanonicalProjectionContract.artifactID(objectID: input.objectID, kind: .audio),
            artifactKind: .audio
        )
        let result = await CanonicalShadowUploadRehearsal().run(
            input: CanonicalShadowUploadRehearsalInput(
                objectID: input.objectID,
                targetReference: reference,
                bytes: input.bytes,
                chunkSize: input.chunkSize,
                declaredTotalHash: input.declaredTotalHash,
                existingReceiverBytes: input.existingReceiverBytes,
                simulateInterruptionAfterFirstChunk: input.simulateInterruptionAfterFirstChunk
            ),
            receiver: receiver.canonicalReceiver
        )
        return CanonicalAudioUploadShadowRehearsalResult(
            shadowResult: result,
            objectID: input.objectID,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole
        )
    }
}

nonisolated enum CanonicalAudioUploadAbortPhase: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case beforeStart
    case beforeFinalize
    case afterFinalize
}

nonisolated struct CanonicalAudioUploadAbortPlan: Codable, Equatable, Sendable {
    var phase: CanonicalAudioUploadAbortPhase
    var canCancelSession: Bool
    var canDeleteProductionAudio: Bool
    var shouldPreserveLegacyFallback: Bool
    var reason: String

    nonisolated static func plan(phase: CanonicalAudioUploadAbortPhase) -> CanonicalAudioUploadAbortPlan {
        switch phase {
        case .beforeStart:
            return CanonicalAudioUploadAbortPlan(phase: phase, canCancelSession: true, canDeleteProductionAudio: false, shouldPreserveLegacyFallback: true, reason: "abortBeforeStartNoProductionState")
        case .beforeFinalize:
            return CanonicalAudioUploadAbortPlan(phase: phase, canCancelSession: true, canDeleteProductionAudio: false, shouldPreserveLegacyFallback: true, reason: "abortBeforeFinalizeCanCancelShadowSessionOnly")
        case .afterFinalize:
            return CanonicalAudioUploadAbortPlan(phase: phase, canCancelSession: false, canDeleteProductionAudio: false, shouldPreserveLegacyFallback: true, reason: "postFinalizeRollbackNeverDeletesAudio")
        }
    }
}

nonisolated struct CanonicalAudioUploadCleanupResult: Codable, Equatable, Sendable {
    var shadowPartialSessionCleaned: Bool
    var productionAudioDeleted: Bool
    var receiveJSONDeleted: Bool
    var legacyFallbackPreserved: Bool
    var reason: String

    nonisolated static func shadowOnlyCleanup(reason: String) -> CanonicalAudioUploadCleanupResult {
        CanonicalAudioUploadCleanupResult(
            shadowPartialSessionCleaned: true,
            productionAudioDeleted: false,
            receiveJSONDeleted: false,
            legacyFallbackPreserved: true,
            reason: reason
        )
    }
}

nonisolated struct CanonicalAudioUploadRollbackPolicy: Codable, Equatable, Sendable {
    var preFinalizeAbort: CanonicalAudioUploadAbortPlan
    var postFinalizeRollback: CanonicalAudioUploadAbortPlan
    var cleanupShadowPartialSessions: Bool
    var neverDeleteProductionAudio: Bool
    var neverDeleteReceiveJSON: Bool

    nonisolated init() {
        self.preFinalizeAbort = .plan(phase: .beforeFinalize)
        self.postFinalizeRollback = .plan(phase: .afterFinalize)
        self.cleanupShadowPartialSessions = true
        self.neverDeleteProductionAudio = true
        self.neverDeleteReceiveJSON = true
    }

    nonisolated func cleanupPartialShadowSession(reason: String = "shadowPartialSessionCleanupOnly") -> CanonicalAudioUploadCleanupResult {
        .shadowOnlyCleanup(reason: reason)
    }
}

nonisolated struct CanonicalAudioUploadReadSideParallelProjection: Codable, Equatable, Sendable {
    var candidateCount: Int
    var equivalent: Bool
    var mutatedUI: Bool
    var wroteUIState: Bool
    var createdUploadJob: Bool
    var diagnostics: [CanonicalAudioUploadDiagnostic]

    nonisolated static func project(
        candidates: [CanonicalAudioUploadCutoverCandidate],
        syncRunID: String?,
        trigger: CanonicalAudioUploadTriggerSource,
        nodeRole: CanonicalAudioUploadNodeRole
    ) -> CanonicalAudioUploadReadSideParallelProjection {
        let diverged = candidates.contains { $0.evidenceStatus == .conflict }
        return CanonicalAudioUploadReadSideParallelProjection(
            candidateCount: candidates.count,
            equivalent: !diverged,
            mutatedUI: false,
            wroteUIState: false,
            createdUploadJob: false,
            diagnostics: [
                CanonicalAudioUploadDiagnostic(kind: .canonicalAudioUploadReadSideProjectionStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "candidateCount=\(candidates.count)"),
                CanonicalAudioUploadDiagnostic(kind: diverged ? .canonicalAudioUploadReadSideProjectionDiverged : .canonicalAudioUploadReadSideProjectionEquivalent, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: diverged ? "diverged" : "equivalent")
            ]
        )
    }
}

nonisolated struct CanonicalAudioUploadCutoverAppSeamPolicy: Codable, Equatable, Sendable {
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int
    var canaryPolicy: CanonicalAudioUploadCanaryPolicy

    nonisolated init(
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 200,
        canaryPolicy: CanonicalAudioUploadCanaryPolicy = .disabled
    ) {
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
        self.canaryPolicy = canaryPolicy
    }
}

nonisolated struct CanonicalAudioUploadCutoverAppSeamConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: CanonicalCutoverAppSeamMode
    var policy: CanonicalAudioUploadCutoverAppSeamPolicy
    var evidence: CanonicalAudioUploadCutoverEvidence
    var cutoverToken: CanonicalCutoverToken?

    nonisolated init(
        isEnabled: Bool = false,
        mode: CanonicalCutoverAppSeamMode = .disabled,
        policy: CanonicalAudioUploadCutoverAppSeamPolicy = CanonicalAudioUploadCutoverAppSeamPolicy(),
        evidence: CanonicalAudioUploadCutoverEvidence = CanonicalAudioUploadCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) {
        self.isEnabled = isEnabled
        self.mode = isEnabled ? mode : .disabled
        self.policy = policy
        self.evidence = evidence
        self.cutoverToken = cutoverToken
    }

    nonisolated static let disabled = CanonicalAudioUploadCutoverAppSeamConfiguration()

    nonisolated static func enabled(
        mode: CanonicalCutoverAppSeamMode = .guardedExecuteNoCommit,
        policy: CanonicalAudioUploadCutoverAppSeamPolicy = CanonicalAudioUploadCutoverAppSeamPolicy(
            canaryPolicy: CanonicalAudioUploadCanaryPolicy(requestedStage: .shadowOnly)
        ),
        evidence: CanonicalAudioUploadCutoverEvidence = CanonicalAudioUploadCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) -> CanonicalAudioUploadCutoverAppSeamConfiguration {
        CanonicalAudioUploadCutoverAppSeamConfiguration(
            isEnabled: true,
            mode: mode,
            policy: policy,
            evidence: evidence,
            cutoverToken: cutoverToken
        )
    }

    nonisolated var effectiveMode: CanonicalCutoverAppSeamMode {
        isEnabled ? mode : .disabled
    }

    nonisolated var cutoverMode: CanonicalCutoverMode {
        switch effectiveMode {
        case .disabled:
            return .disabled
        case .guardedExecuteNoCommit:
            return .guardedExecuteNoCommit
        case .guardedExecuteCommit, .productionExecute:
            return .guardedExecuteCommit
        case .canaryCommit:
            return .canary
        }
    }
}
