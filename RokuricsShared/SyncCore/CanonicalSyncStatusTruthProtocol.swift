//
//  CanonicalSyncStatusTruthProtocol.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated struct CanonicalStatusFactID: Codable, Equatable, Hashable, Comparable, Sendable {
    var rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = CanonicalKernelStringSanitizer.required(rawValue, fallback: "status-fact")
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = CanonicalKernelStringSanitizer.required(try container.decode(String.self), fallback: "status-fact")
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    nonisolated static func < (left: CanonicalStatusFactID, right: CanonicalStatusFactID) -> Bool {
        left.rawValue < right.rawValue
    }
}

nonisolated enum CanonicalStatusDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case libraryMetadata
    case generatedArtifacts
    case tombstoneConflict
    case audioUpload
    case transfer
    case connection
    case file
}

nonisolated enum CanonicalStatusPhase: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case absent
    case localOnly
    case peerUnknown
    case metadataOnly
    case peerKnownMetadataOnly
    case uploadNeeded
    case uploading
    case partialReceive
    case finalizing
    case finalizedLocally
    case peerVerified
    case completed
    case deferred
    case blocked
    case conflict
    case stale
}

nonisolated enum CanonicalStatusFactSource: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case localFileObservation
    case localMetadataStore
    case legacyCompletedLedger
    case uploadLedger
    case metadataOnlyLedger
    case peerMetadata
    case peerReceiveRecord
    case peerInventory
    case peerHashSize
    case transferFinalizeProof
    case transferSession
    case statusExchangeAck
    case partialReceive
    case viewRefresh
    case retryDrainer
    case syncRuntime
    case fileObservation
    case manualForce
}

typealias CanonicalStatusSource = CanonicalStatusFactSource

nonisolated enum CanonicalStatusProofKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case peerUnknown
    case metadataOnly
    case receiveRecordOnly
    case completedLedgerOnly
    case partialReceive
    case localFileExists
    case expectedManifestHash
    case peerHashSize
    case peerInventoryHashSizeMatch
    case finalizeProof
    case sameHashAndByteSize
    case statusExchangeAck
    case dualAckProofChain
    case existingDifferentAudio
    case tombstone
    case unsupportedSchema
    case existingEligibleRetry
}

nonisolated enum CanonicalStatusCausalityTrigger: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case ordinarySync
    case eventDrivenSync
    case manualForce
    case viewRefresh
    case retryDrainer
    case statusExchange
    case transferFinalize
    case localFileIndex
}

nonisolated struct CanonicalStatusCausality: Codable, Equatable, Hashable, Sendable {
    var trigger: CanonicalStatusCausalityTrigger
    var replacesFactIDs: [CanonicalStatusFactID]
    var causedByFactIDs: [CanonicalStatusFactID]
    var permitsManualPeerUnknownUpload: Bool

    nonisolated init(
        trigger: CanonicalStatusCausalityTrigger = .ordinarySync,
        replacesFactIDs: [CanonicalStatusFactID] = [],
        causedByFactIDs: [CanonicalStatusFactID] = [],
        permitsManualPeerUnknownUpload: Bool = false
    ) {
        self.trigger = trigger
        self.replacesFactIDs = Array(Set(replacesFactIDs)).sorted()
        self.causedByFactIDs = Array(Set(causedByFactIDs)).sorted()
        self.permitsManualPeerUnknownUpload = permitsManualPeerUnknownUpload
    }

    nonisolated static let ordinarySync = CanonicalStatusCausality()
}

nonisolated struct CanonicalStatusExpiry: Codable, Equatable, Hashable, Sendable {
    var staleAfter: CanonicalTimestamp?
    var expiresAt: CanonicalTimestamp?

    nonisolated init(staleAfter: CanonicalTimestamp? = nil, expiresAt: CanonicalTimestamp? = nil) {
        self.staleAfter = staleAfter
        self.expiresAt = expiresAt
    }

    nonisolated static let never = CanonicalStatusExpiry()

    nonisolated func isExpired(now: CanonicalTimestamp) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt < now || expiresAt == now
    }

    nonisolated func isStale(now: CanonicalTimestamp) -> Bool {
        guard let staleAfter else { return false }
        return staleAfter < now || staleAfter == now
    }
}

nonisolated struct CanonicalStatusProof: Codable, Equatable, Hashable, Sendable {
    var kind: CanonicalStatusProofKind
    var objectID: CanonicalObjectID
    var hash: CanonicalHash?
    var byteSize: Int64?
    var peerNodeID: CanonicalNodeID?
    var finalizeProof: CanonicalTransferFinalizeProof?
    var ackID: String?
    var schemaVersion: String?
    var proofChain: [CanonicalStatusProof]?
    var observedAt: CanonicalTimestamp
    var expiresAt: CanonicalTimestamp?

    nonisolated init(
        kind: CanonicalStatusProofKind,
        objectID: CanonicalObjectID,
        hash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        peerNodeID: CanonicalNodeID? = nil,
        finalizeProof: CanonicalTransferFinalizeProof? = nil,
        ackID: String? = nil,
        schemaVersion: String? = nil,
        proofChain: [CanonicalStatusProof]? = nil,
        observedAt: CanonicalTimestamp,
        expiresAt: CanonicalTimestamp? = nil
    ) {
        self.kind = kind
        self.objectID = objectID
        self.hash = hash
        self.byteSize = byteSize.map { max(0, $0) }
        self.peerNodeID = peerNodeID
        self.finalizeProof = finalizeProof
        self.ackID = CanonicalKernelStringSanitizer.optional(ackID)
        self.schemaVersion = CanonicalKernelStringSanitizer.optional(schemaVersion)
        self.proofChain = proofChain
        self.observedAt = observedAt
        self.expiresAt = expiresAt
    }

    nonisolated var hasHashSizeProof: Bool {
        hash != nil && byteSize != nil
    }

    nonisolated var hasAcceptedFinalizeProof: Bool {
        finalizeProof?.isReceiverAcceptedProof == true
    }

    nonisolated var hasDualAckProofChain: Bool {
        guard kind == .dualAckProofChain,
              CanonicalKernelStringSanitizer.optional(ackID) != nil,
              let proofChain,
              proofChain.isEmpty == false else {
            return false
        }
        return proofChain.contains { chained in
            chained.hasAcceptedFinalizeProof || chained.hasHashSizeProof
        }
    }
}

nonisolated struct CanonicalStatusFact: Codable, Equatable, Hashable, Sendable {
    var factID: CanonicalStatusFactID
    var objectID: CanonicalObjectID
    var domain: CanonicalStatusDomain
    var phase: CanonicalStatusPhase
    var source: CanonicalStatusSource
    var producerNodeID: CanonicalNodeID
    var logicalTime: CanonicalLogicalTime
    var proof: CanonicalStatusProof
    var causality: CanonicalStatusCausality
    var expiry: CanonicalStatusExpiry

    nonisolated init(
        factID: String,
        objectID: CanonicalObjectID,
        source: CanonicalStatusSource,
        producerNodeID: CanonicalNodeID,
        logicalTime: CanonicalLogicalTime,
        proof: CanonicalStatusProof,
        domain: CanonicalStatusDomain = .audioUpload,
        phase: CanonicalStatusPhase? = nil,
        causality: CanonicalStatusCausality = .ordinarySync,
        expiry: CanonicalStatusExpiry = .never
    ) {
        self.init(
            factID: CanonicalStatusFactID(factID),
            objectID: objectID,
            domain: domain,
            phase: phase ?? CanonicalStatusFact.defaultPhase(for: proof, source: source),
            source: source,
            producerNodeID: producerNodeID,
            logicalTime: logicalTime,
            proof: proof,
            causality: causality,
            expiry: expiry
        )
    }

    nonisolated init(
        factID: CanonicalStatusFactID,
        objectID: CanonicalObjectID,
        domain: CanonicalStatusDomain,
        phase: CanonicalStatusPhase,
        source: CanonicalStatusSource,
        producerNodeID: CanonicalNodeID,
        logicalTime: CanonicalLogicalTime,
        proof: CanonicalStatusProof,
        causality: CanonicalStatusCausality = .ordinarySync,
        expiry: CanonicalStatusExpiry = .never
    ) {
        self.factID = factID
        self.objectID = objectID
        self.domain = domain
        self.phase = phase
        self.source = source
        self.producerNodeID = producerNodeID
        self.logicalTime = logicalTime
        self.proof = proof
        self.causality = causality
        self.expiry = expiry
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        factID = try container.decode(CanonicalStatusFactID.self, forKey: .factID)
        objectID = try container.decode(CanonicalObjectID.self, forKey: .objectID)
        source = try container.decode(CanonicalStatusSource.self, forKey: .source)
        producerNodeID = try container.decode(CanonicalNodeID.self, forKey: .producerNodeID)
        logicalTime = try container.decode(CanonicalLogicalTime.self, forKey: .logicalTime)
        proof = try container.decode(CanonicalStatusProof.self, forKey: .proof)
        domain = try container.decodeIfPresent(CanonicalStatusDomain.self, forKey: .domain) ?? .audioUpload
        phase = try container.decodeIfPresent(CanonicalStatusPhase.self, forKey: .phase)
            ?? CanonicalStatusFact.defaultPhase(for: proof, source: source)
        causality = try container.decodeIfPresent(CanonicalStatusCausality.self, forKey: .causality) ?? .ordinarySync
        expiry = try container.decodeIfPresent(CanonicalStatusExpiry.self, forKey: .expiry) ?? .never
    }

    nonisolated func isExpired(now: CanonicalTimestamp) -> Bool {
        expiry.isExpired(now: now) || proof.expiresAt.map { $0 < now || $0 == now } == true
    }

    nonisolated func isStale(now: CanonicalTimestamp) -> Bool {
        expiry.isStale(now: now)
    }

    private nonisolated static func defaultPhase(
        for proof: CanonicalStatusProof,
        source: CanonicalStatusSource
    ) -> CanonicalStatusPhase {
        switch proof.kind {
        case .peerUnknown:
            return .peerUnknown
        case .metadataOnly:
            return source == .peerMetadata || source == .metadataOnlyLedger ? .peerKnownMetadataOnly : .metadataOnly
        case .receiveRecordOnly:
            return .peerKnownMetadataOnly
        case .completedLedgerOnly:
            return .finalizedLocally
        case .partialReceive:
            return .partialReceive
        case .localFileExists:
            return .localOnly
        case .expectedManifestHash:
            return .metadataOnly
        case .peerHashSize, .peerInventoryHashSizeMatch, .sameHashAndByteSize:
            return .peerVerified
        case .finalizeProof, .dualAckProofChain:
            return .completed
        case .statusExchangeAck:
            return .peerVerified
        case .existingDifferentAudio:
            return .conflict
        case .tombstone, .unsupportedSchema:
            return .blocked
        case .existingEligibleRetry:
            return .deferred
        }
    }
}

nonisolated enum CanonicalStatusDisplayState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case hidden
    case waiting
    case uploadNeeded
    case uploading
    case finalizing
    case complete
    case conflict
    case blocked
    case stale
}

nonisolated enum CanonicalStatusBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case metadataOnlyRejectedAsAudioProof
    case receiveRecordOnlyRejectedAsAudioProof
    case completedLedgerRejectedAsPeerProof
    case partialReceiveRejectedAsCompleted
    case localFileExistsIsNotPeerProof
    case expectedManifestHashRejectedAsPeerProof
    case peerProofUnavailable
    case existingDifferentAudioConflict
    case tombstoneBlocksGeneratedArtifactResurrection
    case staleFactCannotOverrideNewerProof
    case unsupportedSchemaFallback
    case viewRefreshCannotCreateUploadJob
    case retryDrainerRequiresExistingEligibleJob
    case securityBypassDenied
}

nonisolated struct CanonicalStatusSourceSummary: Codable, Equatable, Hashable, Sendable {
    var source: CanonicalStatusSource
    var factID: CanonicalStatusFactID
    var phase: CanonicalStatusPhase
    var stale: Bool

    nonisolated init(source: CanonicalStatusSource, factID: CanonicalStatusFactID, phase: CanonicalStatusPhase, stale: Bool = false) {
        self.source = source
        self.factID = factID
        self.phase = phase
        self.stale = stale
    }
}

nonisolated struct CanonicalEffectiveSyncStatus: Codable, Equatable, Hashable, CaseIterable, Sendable {
    var objectID: CanonicalObjectID
    var domain: CanonicalStatusDomain
    var phase: CanonicalStatusPhase
    var displayState: CanonicalStatusDisplayState
    var proof: CanonicalStatusProof?
    var sourceSummary: [CanonicalStatusSourceSummary]
    var canDisplayAsComplete: Bool
    var canCreateUploadJob: Bool
    var canSuppressLegacyDuplicate: Bool
    var blocker: CanonicalStatusBlocker?

    nonisolated init(
        objectID: CanonicalObjectID,
        domain: CanonicalStatusDomain,
        phase: CanonicalStatusPhase,
        displayState: CanonicalStatusDisplayState,
        proof: CanonicalStatusProof? = nil,
        sourceSummary: [CanonicalStatusSourceSummary] = [],
        canDisplayAsComplete: Bool = false,
        canCreateUploadJob: Bool = false,
        canSuppressLegacyDuplicate: Bool = false,
        blocker: CanonicalStatusBlocker? = nil
    ) {
        self.objectID = objectID
        self.domain = domain
        self.phase = phase
        self.displayState = displayState
        self.proof = proof
        self.sourceSummary = sourceSummary.sorted {
            if $0.source.rawValue != $1.source.rawValue { return $0.source.rawValue < $1.source.rawValue }
            return $0.factID < $1.factID
        }
        self.canDisplayAsComplete = canDisplayAsComplete
        self.canCreateUploadJob = canCreateUploadJob
        self.canSuppressLegacyDuplicate = canSuppressLegacyDuplicate
        self.blocker = blocker
    }

    nonisolated static var allCases: [CanonicalEffectiveSyncStatus] {
        [
            .peerUnknownDeferred,
            .rejectedNotAudioProof,
            .partialReceiveNotCompleted,
            .localOnlyNotPeerProof,
            .audioNoOpSameHashAndSize,
            .peerVerifiedCompleted,
            .conflictNoOverwrite,
            .uploadJobCreationForbidden,
            .retryRequiresExistingEligibleJob,
            .needsUpload
        ]
    }

    nonisolated static let peerUnknownDeferred = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .deferred,
        displayState: .waiting,
        blocker: .peerProofUnavailable
    )
    nonisolated static let rejectedNotAudioProof = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .metadataOnly,
        displayState: .waiting,
        blocker: .metadataOnlyRejectedAsAudioProof
    )
    nonisolated static let partialReceiveNotCompleted = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .partialReceive,
        displayState: .uploading,
        blocker: .partialReceiveRejectedAsCompleted
    )
    nonisolated static let localOnlyNotPeerProof = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .localOnly,
        displayState: .waiting,
        blocker: .localFileExistsIsNotPeerProof
    )
    nonisolated static let audioNoOpSameHashAndSize = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .peerVerified,
        displayState: .complete,
        canDisplayAsComplete: true,
        canSuppressLegacyDuplicate: true
    )
    nonisolated static let peerVerifiedCompleted = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .completed,
        displayState: .complete,
        canDisplayAsComplete: true,
        canSuppressLegacyDuplicate: true
    )
    nonisolated static let conflictNoOverwrite = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .conflict,
        displayState: .conflict,
        blocker: .existingDifferentAudioConflict
    )
    nonisolated static let uploadJobCreationForbidden = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .blocked,
        displayState: .blocked,
        blocker: .viewRefreshCannotCreateUploadJob
    )
    nonisolated static let retryRequiresExistingEligibleJob = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .deferred,
        displayState: .waiting,
        blocker: .retryDrainerRequiresExistingEligibleJob
    )
    nonisolated static let needsUpload = CanonicalEffectiveSyncStatus(
        objectID: CanonicalObjectID("object-unknown"),
        domain: .audioUpload,
        phase: .uploadNeeded,
        displayState: .uploadNeeded,
        canCreateUploadJob: true
    )
}

nonisolated enum CanonicalStatusHardRule: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case metadataOnlyIsNotAudioAvailable
    case receiveRecordOnlyIsNotAudioAvailable
    case completedLedgerAloneIsNotPeerProof
    case partialReceiveIsNotCompleted
    case localFileExistsIsNotPeerHasFile
    case expectedManifestHashIsNotPeerProof
    case sameHashAndSameByteSizeIsAudioNoOp
    case finalizeProofOrPeerHashSizeProofCanComplete
    case peerUnknownMustDefer
    case existingDifferentAudioMustConflictNoOverwrite
    case tombstoneBlocksGeneratedArtifactResurrection
    case staleFactCannotOverrideNewerProof
    case unsupportedSchemaRequiresFallback
    case viewRefreshCannotCreateUploadJob
    case retryDrainerCanOnlyResumeExistingEligibleJob
}

nonisolated struct CanonicalStatusProofEvaluation: Codable, Equatable, Hashable, Sendable {
    var acceptedAsPeerAudioProof: Bool
    var effectiveStatus: CanonicalEffectiveSyncStatus
    var rule: CanonicalStatusHardRule

    nonisolated init(
        acceptedAsPeerAudioProof: Bool,
        effectiveStatus: CanonicalEffectiveSyncStatus,
        rule: CanonicalStatusHardRule
    ) {
        self.acceptedAsPeerAudioProof = acceptedAsPeerAudioProof
        self.effectiveStatus = effectiveStatus
        self.rule = rule
    }
}

nonisolated struct CanonicalStatusReconciliation: Codable, Equatable, Hashable, Sendable {
    var objectID: CanonicalObjectID
    var effectiveStatus: CanonicalEffectiveSyncStatus
    var acceptedProof: CanonicalStatusProof?
    var blockers: [CanonicalStatusHardRule]
    var mayCreateUploadJob: Bool
    var mayOverwriteExistingPeerAudio: Bool

    nonisolated init(
        objectID: CanonicalObjectID,
        effectiveStatus: CanonicalEffectiveSyncStatus,
        acceptedProof: CanonicalStatusProof? = nil,
        blockers: [CanonicalStatusHardRule] = [],
        mayCreateUploadJob: Bool = false,
        mayOverwriteExistingPeerAudio: Bool = false
    ) {
        self.objectID = objectID
        self.effectiveStatus = effectiveStatus
        self.acceptedProof = acceptedProof
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.mayCreateUploadJob = mayCreateUploadJob
        self.mayOverwriteExistingPeerAudio = mayOverwriteExistingPeerAudio
    }
}

nonisolated protocol CanonicalStatusTruthEngine: Sendable {
    func reconcile(facts: [CanonicalStatusFact]) async throws -> CanonicalStatusReconciliation
}

nonisolated enum CanonicalStatusTruthRules {
    nonisolated static func evaluatePeerAudioProof(_ proof: CanonicalStatusProof) -> CanonicalStatusProofEvaluation {
        switch proof.kind {
        case .metadataOnly:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: .rejectedNotAudioProof,
                rule: .metadataOnlyIsNotAudioAvailable
            )
        case .receiveRecordOnly:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: .rejectedNotAudioProof,
                rule: .receiveRecordOnlyIsNotAudioAvailable
            )
        case .completedLedgerOnly:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: .rejectedNotAudioProof,
                rule: .completedLedgerAloneIsNotPeerProof
            )
        case .partialReceive:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: .partialReceiveNotCompleted,
                rule: .partialReceiveIsNotCompleted
            )
        case .localFileExists:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: .localOnlyNotPeerProof,
                rule: .localFileExistsIsNotPeerHasFile
            )
        case .expectedManifestHash:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: .rejectedNotAudioProof,
                rule: .expectedManifestHashIsNotPeerProof
            )
        case .peerUnknown:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: .peerUnknownDeferred,
                rule: .peerUnknownMustDefer
            )
        case .existingDifferentAudio:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: .conflictNoOverwrite,
                rule: .existingDifferentAudioMustConflictNoOverwrite
            )
        case .tombstone:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: CanonicalEffectiveSyncStatus(
                    objectID: proof.objectID,
                    domain: .tombstoneConflict,
                    phase: .blocked,
                    displayState: .blocked,
                    blocker: .tombstoneBlocksGeneratedArtifactResurrection
                ),
                rule: .tombstoneBlocksGeneratedArtifactResurrection
            )
        case .unsupportedSchema:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: CanonicalEffectiveSyncStatus(
                    objectID: proof.objectID,
                    domain: .audioUpload,
                    phase: .blocked,
                    displayState: .blocked,
                    blocker: .unsupportedSchemaFallback
                ),
                rule: .unsupportedSchemaRequiresFallback
            )
        case .peerHashSize, .peerInventoryHashSizeMatch:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: proof.hasHashSizeProof,
                effectiveStatus: proof.hasHashSizeProof ? .peerVerifiedCompleted : .peerUnknownDeferred,
                rule: .finalizeProofOrPeerHashSizeProofCanComplete
            )
        case .finalizeProof:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: proof.hasAcceptedFinalizeProof,
                effectiveStatus: proof.hasAcceptedFinalizeProof ? .peerVerifiedCompleted : .peerUnknownDeferred,
                rule: .finalizeProofOrPeerHashSizeProofCanComplete
            )
        case .dualAckProofChain:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: proof.hasDualAckProofChain,
                effectiveStatus: proof.hasDualAckProofChain ? .peerVerifiedCompleted : .peerUnknownDeferred,
                rule: .finalizeProofOrPeerHashSizeProofCanComplete
            )
        case .sameHashAndByteSize:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: proof.hasHashSizeProof,
                effectiveStatus: proof.hasHashSizeProof ? .audioNoOpSameHashAndSize : .peerUnknownDeferred,
                rule: .sameHashAndSameByteSizeIsAudioNoOp
            )
        case .statusExchangeAck, .existingEligibleRetry:
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: false,
                effectiveStatus: .peerUnknownDeferred,
                rule: .peerUnknownMustDefer
            )
        }
    }

    nonisolated static func evaluateAudioNoOp(
        localHash: CanonicalHash,
        localByteSize: Int64,
        peerHash: CanonicalHash,
        peerByteSize: Int64
    ) -> CanonicalStatusProofEvaluation {
        if localHash == peerHash && localByteSize == peerByteSize {
            return CanonicalStatusProofEvaluation(
                acceptedAsPeerAudioProof: true,
                effectiveStatus: .audioNoOpSameHashAndSize,
                rule: .sameHashAndSameByteSizeIsAudioNoOp
            )
        }
        return CanonicalStatusProofEvaluation(
            acceptedAsPeerAudioProof: false,
            effectiveStatus: .conflictNoOverwrite,
            rule: .existingDifferentAudioMustConflictNoOverwrite
        )
    }

    nonisolated static func viewRefreshMayCreateUploadJob() -> Bool {
        false
    }

    nonisolated static func retryDrainerMayCreateFreshUploadJob() -> Bool {
        false
    }
}
