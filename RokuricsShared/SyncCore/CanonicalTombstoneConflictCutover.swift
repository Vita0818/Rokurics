//
//  CanonicalTombstoneConflictCutover.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/4.
//

import Foundation

nonisolated enum CanonicalTombstoneConflictDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case objectTombstone
    case libraryTombstone
    case generatedArtifactTombstoneMarker
    case activeVsTombstoneConflict
    case metadataConflictRecord
    case artifactConflictRecord

    nonisolated var productionDomain: CanonicalProductionDomain {
        switch self {
        case .objectTombstone, .libraryTombstone, .generatedArtifactTombstoneMarker:
            return .tombstones
        case .activeVsTombstoneConflict, .metadataConflictRecord, .artifactConflictRecord:
            return .conflicts
        }
    }

    nonisolated var requiresConflictLedger: Bool {
        switch self {
        case .activeVsTombstoneConflict, .metadataConflictRecord, .artifactConflictRecord:
            return true
        case .objectTombstone, .libraryTombstone, .generatedArtifactTombstoneMarker:
            return false
        }
    }
}

nonisolated enum CanonicalTombstoneConflictActionKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case objectTombstoneApply
    case objectTombstoneSend
    case libraryTombstoneApply
    case libraryTombstoneSend
    case generatedArtifactTombstoneMarkUnsupported
    case conflictRecord
    case resurrectionBlocked
    case unsupported

    nonisolated var isTombstoneMarkerWrite: Bool {
        switch self {
        case .objectTombstoneApply, .objectTombstoneSend, .libraryTombstoneApply, .libraryTombstoneSend:
            return true
        case .generatedArtifactTombstoneMarkUnsupported, .conflictRecord, .resurrectionBlocked, .unsupported:
            return false
        }
    }

    nonisolated var isConflictLedgerWrite: Bool {
        self == .conflictRecord || self == .resurrectionBlocked
    }

    nonisolated var isExecutable: Bool {
        isTombstoneMarkerWrite || isConflictLedgerWrite
    }
}

nonisolated enum CanonicalTombstoneConflictMarkerKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case softObjectTombstoneMarker
    case softLibraryTombstoneMarker
    case conflictRecord
    case resurrectionBlockRecord
    case generatedArtifactTombstoneMarkerReportOnly

    nonisolated var isExecutableCanonicalWrite: Bool {
        switch self {
        case .softObjectTombstoneMarker, .softLibraryTombstoneMarker, .conflictRecord, .resurrectionBlockRecord:
            return true
        case .generatedArtifactTombstoneMarkerReportOnly:
            return false
        }
    }
}

nonisolated enum CanonicalTombstoneConflictDisplayState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case active
    case softDeleted
    case trashed
    case tombstoned
    case conflict
    case resurrectionBlocked
    case manualReviewRequired
    case reportOnly
}

nonisolated struct CanonicalTombstoneConflictBusinessFields: Codable, Equatable, Sendable {
    var markerID: String
    var objectID: String
    var objectKind: CanonicalObjectKind
    var markerKind: CanonicalTombstoneConflictMarkerKind
    var conflictKind: String?
    var tombstoneState: CanonicalTombstoneState
    var displayState: CanonicalTombstoneConflictDisplayState
    var businessModifiedAt: CanonicalTimestamp?
    var actorDeviceRole: String?
    var parentObjectID: String?
    var conflictResolutionState: String?

    nonisolated init(
        markerID: String,
        objectID: String,
        objectKind: CanonicalObjectKind = .recording,
        markerKind: CanonicalTombstoneConflictMarkerKind,
        conflictKind: String? = nil,
        tombstoneState: CanonicalTombstoneState = .active,
        displayState: CanonicalTombstoneConflictDisplayState? = nil,
        businessModifiedAt: CanonicalTimestamp?,
        actorDeviceRole: String? = nil,
        parentObjectID: String? = nil,
        conflictResolutionState: String? = nil,
        ignoredDeleteTargetPath: String? = nil,
        ignoredLocalPath: String? = nil,
        ignoredUIOnlyState: String? = nil,
        ignoredUploadProgressState: String? = nil
    ) {
        _ = ignoredDeleteTargetPath
        _ = ignoredLocalPath
        _ = ignoredUIOnlyState
        _ = ignoredUploadProgressState
        self.markerID = Self.normalizedRequired(markerID, fallback: "tombstone-conflict-marker")
        self.objectID = Self.normalizedRequired(objectID, fallback: "tombstone-conflict-object")
        self.objectKind = objectKind
        self.markerKind = markerKind
        self.conflictKind = Self.normalizedOptional(conflictKind)
        self.tombstoneState = tombstoneState
        self.displayState = displayState ?? Self.defaultDisplayState(markerKind: markerKind, tombstoneState: tombstoneState)
        self.businessModifiedAt = businessModifiedAt
        self.actorDeviceRole = Self.normalizedOptional(actorDeviceRole)
        self.parentObjectID = Self.normalizedOptional(parentObjectID)
        self.conflictResolutionState = Self.normalizedOptional(conflictResolutionState)
    }

    nonisolated init(tombstone: CanonicalTombstone, objectKind: CanonicalObjectKind = .recording) {
        self.init(
            markerID: tombstone.tombstoneID,
            objectID: tombstone.target.objectID,
            objectKind: objectKind,
            markerKind: .softObjectTombstoneMarker,
            tombstoneState: tombstone.state,
            businessModifiedAt: tombstone.deletedAt,
            actorDeviceRole: tombstone.sourceNodeID
        )
    }

    nonisolated init(tombstone: CanonicalLibraryTombstone) {
        self.init(
            markerID: tombstone.tombstoneID,
            objectID: tombstone.objectID.rawValue,
            objectKind: tombstone.objectKind,
            markerKind: .softLibraryTombstoneMarker,
            tombstoneState: .tombstoned,
            businessModifiedAt: tombstone.deletedAt,
            actorDeviceRole: tombstone.sourceNodeID
        )
    }

    nonisolated init(conflict: CanonicalConflictRecord) {
        self.init(
            markerID: conflict.conflictID,
            objectID: conflict.target.objectID,
            objectKind: .recording,
            markerKind: conflict.kind == .activeVsTombstone ? .resurrectionBlockRecord : .conflictRecord,
            conflictKind: conflict.kind.rawValue,
            tombstoneState: conflict.kind == .activeVsTombstone ? .tombstoned : .active,
            displayState: conflict.kind == .activeVsTombstone ? .resurrectionBlocked : .conflict,
            businessModifiedAt: conflict.peerModifiedAt ?? conflict.localModifiedAt,
            conflictResolutionState: conflict.resolutionState.rawValue
        )
    }

    nonisolated init(conflict: CanonicalLibraryConflict) {
        self.init(
            markerID: conflict.conflictID,
            objectID: conflict.objectID.rawValue,
            objectKind: conflict.objectKind,
            markerKind: conflict.kind == .activeVsTombstone ? .resurrectionBlockRecord : .conflictRecord,
            conflictKind: conflict.kind.rawValue,
            tombstoneState: conflict.kind == .activeVsTombstone ? .tombstoned : .active,
            displayState: conflict.kind == .activeVsTombstone ? .resurrectionBlocked : .conflict,
            businessModifiedAt: conflict.peerModifiedAt ?? conflict.localModifiedAt,
            conflictResolutionState: CanonicalConflictResolutionState.unresolved.rawValue
        )
    }

    nonisolated var stableBusinessHashInput: [String: String] {
        [
            "schema": CanonicalTombstoneConflictHashSchema.version,
            "markerID": markerID,
            "objectID": objectID,
            "objectKind": objectKind.rawValue,
            "markerKind": markerKind.rawValue,
            "conflictKind": conflictKind ?? "",
            "tombstoneState": tombstoneState.rawValue,
            "displayState": displayState.rawValue,
            "businessModifiedAt": businessModifiedAt.map(Self.timestampString) ?? "",
            "actorDeviceRole": actorDeviceRole ?? "",
            "parentObjectID": parentObjectID ?? "",
            "conflictResolutionState": conflictResolutionState ?? ""
        ]
    }

    nonisolated var markerHash: CanonicalHash {
        CanonicalTombstoneConflictHashSchema.v1.hash(self)
    }

    private nonisolated static func defaultDisplayState(
        markerKind: CanonicalTombstoneConflictMarkerKind,
        tombstoneState: CanonicalTombstoneState
    ) -> CanonicalTombstoneConflictDisplayState {
        switch markerKind {
        case .softObjectTombstoneMarker, .softLibraryTombstoneMarker:
            return tombstoneState == .tombstoned ? .tombstoned : .active
        case .conflictRecord:
            return .conflict
        case .resurrectionBlockRecord:
            return .resurrectionBlocked
        case .generatedArtifactTombstoneMarkerReportOnly:
            return .reportOnly
        }
    }

    private nonisolated static func normalizedRequired(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallback
    }

    private nonisolated static func normalizedOptional(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private nonisolated static func timestampString(_ timestamp: CanonicalTimestamp) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), timestamp.date.timeIntervalSince1970)
    }
}

nonisolated struct CanonicalTombstoneConflictHashSchema: Codable, Equatable, Sendable {
    static let version = "canonical-tombstone-conflict-v1"
    static let v1 = CanonicalTombstoneConflictHashSchema()

    var schemaVersion: String
    var includedStableBusinessFields: [String]
    var excludedFields: [String]

    nonisolated init(
        schemaVersion: String = CanonicalTombstoneConflictHashSchema.version,
        includedStableBusinessFields: [String] = [
            "schema",
            "markerID",
            "objectID",
            "objectKind",
            "markerKind",
            "conflictKind",
            "tombstoneState",
            "displayState",
            "businessModifiedAt",
            "actorDeviceRole",
            "parentObjectID",
            "conflictResolutionState"
        ],
        excludedFields: [String] = [
            "physicalDeleteTargetPath",
            "deleteTargetPath",
            "absolutePath",
            "localPath",
            "resourcePath",
            "fullMetadataJSON",
            "fullObjectContent",
            "standaloneNoteContent",
            "generatedTranscriptContent",
            "generatedNoteContent",
            "generatedSummaryContent",
            "providerResponse",
            "audioPath",
            "audioHash",
            "audioByteSize",
            "uploadProgress",
            "receiveStatus",
            "observedAt",
            "receivedAt",
            "uiOnlyState",
            "diagnostics"
        ]
    ) {
        self.schemaVersion = schemaVersion
        self.includedStableBusinessFields = includedStableBusinessFields
        self.excludedFields = excludedFields
    }

    nonisolated func hash(_ fields: CanonicalTombstoneConflictBusinessFields) -> CanonicalHash {
        CanonicalHash.sha256(of: fields.stableBusinessHashInput)
    }
}

nonisolated enum CanonicalTombstoneConflictDecisionAction: String, Codable, Equatable, Hashable, Sendable {
    case legacyFallback
    case noOp
    case useLocalMarker
    case applyPeerMarker
    case writeConflictRecord
    case writeResurrectionBlockRecord
    case blocker
}

nonisolated struct CanonicalTombstoneConflictDecisionInput: Codable, Equatable, Sendable {
    var local: CanonicalTombstoneConflictBusinessFields?
    var peer: CanonicalTombstoneConflictBusinessFields?
    var localSchemaVersion: String
    var peerSchemaVersion: String?
    var logicalTimeAvailable: Bool
    var safeConflictRecordWriteAvailable: Bool
    var safeResurrectionBlockWriteAvailable: Bool
    var ambiguousConflictDetected: Bool
    var staleLiveResurrectionDetected: Bool
    var newerLiveVsTombstoneDetected: Bool
    var restoreRequested: Bool
    var clearTombstoneRequested: Bool
    var physicalDeleteRequested: Bool
    var permanentDeleteRequested: Bool
    var tombstoneGCRequested: Bool

    nonisolated init(
        local: CanonicalTombstoneConflictBusinessFields?,
        peer: CanonicalTombstoneConflictBusinessFields?,
        localSchemaVersion: String = CanonicalTombstoneConflictHashSchema.version,
        peerSchemaVersion: String? = CanonicalTombstoneConflictHashSchema.version,
        logicalTimeAvailable: Bool = true,
        safeConflictRecordWriteAvailable: Bool = true,
        safeResurrectionBlockWriteAvailable: Bool = true,
        ambiguousConflictDetected: Bool = false,
        staleLiveResurrectionDetected: Bool = false,
        newerLiveVsTombstoneDetected: Bool = false,
        restoreRequested: Bool = false,
        clearTombstoneRequested: Bool = false,
        physicalDeleteRequested: Bool = false,
        permanentDeleteRequested: Bool = false,
        tombstoneGCRequested: Bool = false
    ) {
        self.local = local
        self.peer = peer
        self.localSchemaVersion = localSchemaVersion
        self.peerSchemaVersion = peerSchemaVersion
        self.logicalTimeAvailable = logicalTimeAvailable
        self.safeConflictRecordWriteAvailable = safeConflictRecordWriteAvailable
        self.safeResurrectionBlockWriteAvailable = safeResurrectionBlockWriteAvailable
        self.ambiguousConflictDetected = ambiguousConflictDetected
        self.staleLiveResurrectionDetected = staleLiveResurrectionDetected
        self.newerLiveVsTombstoneDetected = newerLiveVsTombstoneDetected
        self.restoreRequested = restoreRequested
        self.clearTombstoneRequested = clearTombstoneRequested
        self.physicalDeleteRequested = physicalDeleteRequested
        self.permanentDeleteRequested = permanentDeleteRequested
        self.tombstoneGCRequested = tombstoneGCRequested
    }
}

nonisolated struct CanonicalTombstoneConflictDecisionResult: Codable, Equatable, Sendable {
    var action: CanonicalTombstoneConflictDecisionAction
    var reason: String
    var localHashPrefix: String?
    var peerHashPrefix: String?
    var hashEqual: Bool
    var hashChanged: Bool
    var logicalTimeApplied: Bool
    var tieDeferred: Bool
    var legacyFallback: Bool
    var conflictRecorded: Bool
    var resurrectionBlocked: Bool
    var restoreBlocked: Bool
    var clearBlocked: Bool
    var physicalDeleteBlocked: Bool
    var permanentDeleteBlocked: Bool
    var tombstoneGCBlocked: Bool
    var unsupportedKindBlocked: Bool

    nonisolated init(
        action: CanonicalTombstoneConflictDecisionAction,
        reason: String,
        localHash: CanonicalHash? = nil,
        peerHash: CanonicalHash? = nil,
        hashEqual: Bool = false,
        hashChanged: Bool = false,
        logicalTimeApplied: Bool = false,
        tieDeferred: Bool = false,
        legacyFallback: Bool = false,
        conflictRecorded: Bool = false,
        resurrectionBlocked: Bool = false,
        restoreBlocked: Bool = false,
        clearBlocked: Bool = false,
        physicalDeleteBlocked: Bool = false,
        permanentDeleteBlocked: Bool = false,
        tombstoneGCBlocked: Bool = false,
        unsupportedKindBlocked: Bool = false
    ) {
        self.action = action
        self.reason = reason
        self.localHashPrefix = localHash?.value.shortCanonicalPrefix
        self.peerHashPrefix = peerHash?.value.shortCanonicalPrefix
        self.hashEqual = hashEqual
        self.hashChanged = hashChanged
        self.logicalTimeApplied = logicalTimeApplied
        self.tieDeferred = tieDeferred
        self.legacyFallback = legacyFallback
        self.conflictRecorded = conflictRecorded
        self.resurrectionBlocked = resurrectionBlocked
        self.restoreBlocked = restoreBlocked
        self.clearBlocked = clearBlocked
        self.physicalDeleteBlocked = physicalDeleteBlocked
        self.permanentDeleteBlocked = permanentDeleteBlocked
        self.tombstoneGCBlocked = tombstoneGCBlocked
        self.unsupportedKindBlocked = unsupportedKindBlocked
    }
}

nonisolated struct CanonicalTombstoneConflictModifiedAtPolicy: Codable, Equatable, Sendable {
    enum MissingLogicalTimePolicy: String, Codable, Equatable, Sendable {
        case blockPrimary
        case allowDocumentedFallback
    }

    enum EqualLogicalTimeTiePolicy: String, Codable, Equatable, Sendable {
        case deferAsConflict
    }

    static let current = CanonicalTombstoneConflictModifiedAtPolicy()

    var clockSource: String
    var missingLogicalTimePolicy: MissingLogicalTimePolicy
    var equalLogicalTimeTiePolicy: EqualLogicalTimeTiePolicy

    nonisolated init(
        clockSource: String = "tombstoneConflictBusinessModifiedAtOrLogicalEventTime",
        missingLogicalTimePolicy: MissingLogicalTimePolicy = .blockPrimary,
        equalLogicalTimeTiePolicy: EqualLogicalTimeTiePolicy = .deferAsConflict
    ) {
        self.clockSource = clockSource
        self.missingLogicalTimePolicy = missingLogicalTimePolicy
        self.equalLogicalTimeTiePolicy = equalLogicalTimeTiePolicy
    }

    nonisolated func decide(_ input: CanonicalTombstoneConflictDecisionInput) -> CanonicalTombstoneConflictDecisionResult {
        guard input.localSchemaVersion == CanonicalTombstoneConflictHashSchema.version,
              input.peerSchemaVersion == nil || input.peerSchemaVersion == CanonicalTombstoneConflictHashSchema.version else {
            return CanonicalTombstoneConflictDecisionResult(action: .legacyFallback, reason: "schemaMismatch", legacyFallback: true)
        }
        if input.physicalDeleteRequested {
            return CanonicalTombstoneConflictDecisionResult(action: .blocker, reason: "physicalDeleteBlocked", physicalDeleteBlocked: true)
        }
        if input.permanentDeleteRequested {
            return CanonicalTombstoneConflictDecisionResult(action: .blocker, reason: "permanentDeleteBlocked", permanentDeleteBlocked: true)
        }
        if input.tombstoneGCRequested {
            return CanonicalTombstoneConflictDecisionResult(action: .blocker, reason: "tombstoneGCBlocked", tombstoneGCBlocked: true)
        }
        if input.restoreRequested {
            return CanonicalTombstoneConflictDecisionResult(action: .blocker, reason: "restoreBlocked", restoreBlocked: true)
        }
        if input.clearTombstoneRequested {
            return CanonicalTombstoneConflictDecisionResult(action: .blocker, reason: "clearTombstoneBlocked", clearBlocked: true)
        }
        guard [input.local, input.peer].compactMap({ $0 }).allSatisfy({ $0.markerKind.isExecutableCanonicalWrite }) else {
            return CanonicalTombstoneConflictDecisionResult(action: .legacyFallback, reason: "unsupportedMarkerKind", legacyFallback: true, unsupportedKindBlocked: true)
        }
        if input.staleLiveResurrectionDetected {
            guard input.safeResurrectionBlockWriteAvailable else {
                return CanonicalTombstoneConflictDecisionResult(action: .blocker, reason: "resurrectionBlockWriteUnavailable", resurrectionBlocked: true)
            }
            return CanonicalTombstoneConflictDecisionResult(action: .writeResurrectionBlockRecord, reason: "staleLiveResurrectionBlocked", resurrectionBlocked: true)
        }
        if input.ambiguousConflictDetected || input.newerLiveVsTombstoneDetected {
            guard input.safeConflictRecordWriteAvailable else {
                return CanonicalTombstoneConflictDecisionResult(action: .blocker, reason: "conflictRecordWriteUnavailable", conflictRecorded: false)
            }
            return CanonicalTombstoneConflictDecisionResult(action: .writeConflictRecord, reason: input.ambiguousConflictDetected ? "ambiguousConflictRecorded" : "newerLiveVsTombstoneConflictRecorded", conflictRecorded: true)
        }
        guard input.logicalTimeAvailable || missingLogicalTimePolicy == .allowDocumentedFallback else {
            return CanonicalTombstoneConflictDecisionResult(action: .legacyFallback, reason: "logicalTimeUnavailable", legacyFallback: true)
        }

        switch (input.local, input.peer) {
        case (.none, .none):
            return CanonicalTombstoneConflictDecisionResult(action: .legacyFallback, reason: "snapshotMissing", legacyFallback: true)
        case let (.some(local), .none):
            return CanonicalTombstoneConflictDecisionResult(action: .useLocalMarker, reason: "peerMarkerMissing", localHash: local.markerHash, hashChanged: true, logicalTimeApplied: true)
        case let (.none, .some(peer)):
            return CanonicalTombstoneConflictDecisionResult(action: .applyPeerMarker, reason: "localMarkerMissing", peerHash: peer.markerHash, hashChanged: true, logicalTimeApplied: true)
        case let (.some(local), .some(peer)):
            let localHash = local.markerHash
            let peerHash = peer.markerHash
            if localHash == peerHash {
                return CanonicalTombstoneConflictDecisionResult(action: .noOp, reason: "markerHashEqual", localHash: localHash, peerHash: peerHash, hashEqual: true)
            }
            guard let localModifiedAt = local.businessModifiedAt,
                  let peerModifiedAt = peer.businessModifiedAt else {
                return CanonicalTombstoneConflictDecisionResult(action: .legacyFallback, reason: "logicalTimeUnavailable", localHash: localHash, peerHash: peerHash, hashChanged: true, legacyFallback: true)
            }
            if localModifiedAt > peerModifiedAt {
                return CanonicalTombstoneConflictDecisionResult(action: .useLocalMarker, reason: "localLogicalTimeNewer", localHash: localHash, peerHash: peerHash, hashChanged: true, logicalTimeApplied: true)
            }
            if peerModifiedAt > localModifiedAt {
                return CanonicalTombstoneConflictDecisionResult(action: .applyPeerMarker, reason: "peerLogicalTimeNewer", localHash: localHash, peerHash: peerHash, hashChanged: true, logicalTimeApplied: true)
            }
            return CanonicalTombstoneConflictDecisionResult(action: .writeConflictRecord, reason: "equalLogicalTimeTieDeferred", localHash: localHash, peerHash: peerHash, hashChanged: true, tieDeferred: true, conflictRecorded: true)
        }
    }
}

nonisolated enum CanonicalTombstoneConflictFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable, Error {
    case disabled
    case unsupportedMode
    case unsupportedDomain
    case unsupportedAction
    case missingToken
    case missingOwnerApproval
    case missingRollback
    case missingNoCommitEvidence
    case missingDryRunEquivalence
    case missingExecutionShadowEvidence
    case missingRealDataShadowCopyEvidence
    case blockingDivergence
    case unresolvedConflict
    case missingMetadataRouteEvidence
    case productionPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case rollbackVerificationMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case softDeleteMarkerUnsupported
    case softTombstoneStoreUnsupported
    case conflictLedgerUnsupported
    case objectIDMismatch
    case tombstoneStateMismatch
    case missingTombstoneTimestamp
    case missingTombstoneWinsPolicy
    case missingRollbackEvidence
    case tombstoneTimestampInvalid
    case tombstonePolicyMissing
    case rollbackEvidenceMissing
    case preconditionMismatch
    case postconditionMismatch
    case applyFailureBeforeCommit
    case applyFailureAfterPartialCommit
    case rollbackFailure
    case resurrectionRiskDetected
    case physicalDeleteAttempted
    case permanentDeleteAttempted
    case tombstoneGCAttempted
    case unsupportedRestore
    case conflictPolicyAmbiguous
    case generatedArtifactTombstoneUnsupported
    case missingInternalCanaryConfiguration
    case canaryBudgetAboveOneDenied
    case missingCanaryStageEvidence
    case canaryStageBlocked
    case canaryStageOrderViolation
    case previousStageFailure
    case previousStageRollbackFailure
}

nonisolated enum CanonicalTombstoneConflictApplyPortMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case dryRun
    case fakeInMemory
    case testRootBound
    case productionRootDisabled
    case productionRootBound

    nonisolated var isNonDryRunRootBound: Bool {
        self == .testRootBound || self == .productionRootBound
    }
}

nonisolated enum CanonicalTombstoneConflictCommitFailureInjection: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case preconditionMismatch
    case postconditionMismatch
    case applyFailureBeforeCommit
    case applyFailureAfterPartialCommit
    case rollbackFailure
    case resurrectionRiskDetected
    case physicalDeleteAttempted
    case permanentDeleteAttempted
    case tombstoneGCAttempted
    case unsupportedRestore
    case conflictPolicyAmbiguous
}

nonisolated struct CanonicalTombstoneConflictCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { action.actionID }

    var action: CanonicalApplyAction
    var recordingTombstone: CanonicalTombstone?
    var libraryTombstone: CanonicalLibraryTombstone?
    var conflict: CanonicalConflictRecord?
    var libraryConflict: CanonicalLibraryConflict?
    var localRecordingObject: CanonicalRecordingObject?
    var peerRecordingObject: CanonicalRecordingObject?
    var localLibraryObject: CanonicalLibraryObject?
    var peerLibraryObject: CanonicalLibraryObject?
    var rollbackCheckpointID: String?
    var tombstoneWinsIfNewerPolicy: Bool
    var rollbackEvidenceAvailable: Bool
    var explicitRestoreSignal: Bool
    var staleLiveMetadataRisk: Bool
    var conflictPolicyKnown: Bool
    var routePath: String

    nonisolated init(
        action: CanonicalApplyAction,
        recordingTombstone: CanonicalTombstone? = nil,
        libraryTombstone: CanonicalLibraryTombstone? = nil,
        conflict: CanonicalConflictRecord? = nil,
        libraryConflict: CanonicalLibraryConflict? = nil,
        localRecordingObject: CanonicalRecordingObject? = nil,
        peerRecordingObject: CanonicalRecordingObject? = nil,
        localLibraryObject: CanonicalLibraryObject? = nil,
        peerLibraryObject: CanonicalLibraryObject? = nil,
        rollbackCheckpointID: String? = nil,
        tombstoneWinsIfNewerPolicy: Bool = false,
        rollbackEvidenceAvailable: Bool = false,
        explicitRestoreSignal: Bool = false,
        staleLiveMetadataRisk: Bool = false,
        conflictPolicyKnown: Bool = true,
        routePath: String = "/sync/apply-metadata"
    ) {
        self.action = action
        self.recordingTombstone = recordingTombstone
        self.libraryTombstone = libraryTombstone
        self.conflict = conflict
        self.libraryConflict = libraryConflict
        self.localRecordingObject = localRecordingObject
        self.peerRecordingObject = peerRecordingObject
        self.localLibraryObject = localLibraryObject
        self.peerLibraryObject = peerLibraryObject
        self.rollbackCheckpointID = rollbackCheckpointID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "tombstone-conflict-checkpoint")
        }
        self.tombstoneWinsIfNewerPolicy = tombstoneWinsIfNewerPolicy
        self.rollbackEvidenceAvailable = rollbackEvidenceAvailable
        self.explicitRestoreSignal = explicitRestoreSignal
        self.staleLiveMetadataRisk = staleLiveMetadataRisk
        self.conflictPolicyKnown = conflictPolicyKnown
        self.routePath = CanonicalProductionRedaction.safeDiagnosticText(routePath) ?? "/sync/apply-metadata"
    }

    nonisolated var objectID: String {
        action.target.objectID
    }

    nonisolated var domain: CanonicalTombstoneConflictDomain {
        switch actionKind {
        case .objectTombstoneApply, .objectTombstoneSend:
            return .objectTombstone
        case .libraryTombstoneApply, .libraryTombstoneSend:
            return .libraryTombstone
        case .generatedArtifactTombstoneMarkUnsupported:
            return .generatedArtifactTombstoneMarker
        case .resurrectionBlocked:
            return .activeVsTombstoneConflict
        case .conflictRecord:
            if conflict?.kind == .activeVsTombstone || libraryConflict?.kind == .activeVsTombstone {
                return .activeVsTombstoneConflict
            }
            if conflict?.kind == .generatedArtifactContentMismatch || action.target.artifactKind != nil {
                return .artifactConflictRecord
            }
            return .metadataConflictRecord
        case .unsupported:
            return .metadataConflictRecord
        }
    }

    nonisolated var actionKind: CanonicalTombstoneConflictActionKind {
        switch action.kind {
        case .objectTombstoneApply:
            return .objectTombstoneApply
        case .objectTombstoneSend:
            return .objectTombstoneSend
        case .libraryTombstoneApply:
            return .libraryTombstoneApply
        case .libraryTombstoneSend:
            return .libraryTombstoneSend
        case .artifactTombstoneApply:
            return .generatedArtifactTombstoneMarkUnsupported
        case .conflictRecord:
            return .conflictRecord
        case .deferredUnsupported where action.failureReason == .tombstoneBlocksResurrection:
            return .resurrectionBlocked
        default:
            return .unsupported
        }
    }

    nonisolated var tombstoneState: CanonicalTombstoneState {
        if recordingTombstone?.state == .tombstoned || libraryTombstone != nil || actionKind.isTombstoneMarkerWrite {
            return .tombstoned
        }
        return .active
    }

    nonisolated var deletedAt: CanonicalTimestamp? {
        recordingTombstone?.deletedAt
            ?? libraryTombstone?.deletedAt
            ?? localRecordingObject?.metadata.deletedAt
            ?? peerRecordingObject?.metadata.deletedAt
            ?? localLibraryObject?.deletedAt
            ?? peerLibraryObject?.deletedAt
    }

    nonisolated var deletedAtSummary: String {
        guard let deletedAt else {
            return "deletedAt=missing"
        }
        let value = String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), deletedAt.date.timeIntervalSince1970)
        return "deletedAtHash=\(CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(value).value) ?? "missing")"
    }

    nonisolated var conflictKindSummary: String {
        conflict?.kind.rawValue ?? libraryConflict?.kind.rawValue ?? (actionKind == .resurrectionBlocked ? "resurrectionBlocked" : "none")
    }

    nonisolated var conflictPolicySummary: String {
        conflict?.resolutionPolicy.rawValue
            ?? (libraryConflict != nil ? "manualReview" : (actionKind == .resurrectionBlocked ? "tombstoneRequiresManualReview" : "none"))
    }

    nonisolated var businessFields: CanonicalTombstoneConflictBusinessFields {
        if let recordingTombstone {
            return CanonicalTombstoneConflictBusinessFields(tombstone: recordingTombstone)
        }
        if let libraryTombstone {
            return CanonicalTombstoneConflictBusinessFields(tombstone: libraryTombstone)
        }
        if let conflict {
            return CanonicalTombstoneConflictBusinessFields(conflict: conflict)
        }
        if let libraryConflict {
            return CanonicalTombstoneConflictBusinessFields(conflict: libraryConflict)
        }
        return CanonicalTombstoneConflictBusinessFields(
            markerID: action.tombstoneID
                ?? action.conflictID
                ?? "\(domain.rawValue)|\(objectID)|\(actionKind.rawValue)",
            objectID: objectID,
            objectKind: localLibraryObject?.kind ?? peerLibraryObject?.kind ?? .recording,
            markerKind: markerKind,
            conflictKind: conflictKindSummary == "none" ? nil : conflictKindSummary,
            tombstoneState: tombstoneState,
            displayState: displayState,
            businessModifiedAt: deletedAt ?? localRecordingObject?.metadata.modifiedAt ?? peerRecordingObject?.metadata.modifiedAt,
            actorDeviceRole: localRecordingObject?.nodeID ?? peerRecordingObject?.nodeID,
            conflictResolutionState: conflictPolicySummary == "none" ? nil : conflictPolicySummary
        )
    }

    nonisolated var effectiveRollbackCheckpointID: String {
        rollbackCheckpointID ?? "tombstone-conflict-\(objectID)-\(actionKind.rawValue)"
    }

    nonisolated var markerHash: CanonicalHash {
        businessFields.markerHash
    }

    nonisolated var markerPayload: [String: String] {
        businessFields.stableBusinessHashInput
    }

    private nonisolated var markerKind: CanonicalTombstoneConflictMarkerKind {
        switch actionKind {
        case .objectTombstoneApply, .objectTombstoneSend:
            return .softObjectTombstoneMarker
        case .libraryTombstoneApply, .libraryTombstoneSend:
            return .softLibraryTombstoneMarker
        case .generatedArtifactTombstoneMarkUnsupported:
            return .generatedArtifactTombstoneMarkerReportOnly
        case .resurrectionBlocked:
            return .resurrectionBlockRecord
        case .conflictRecord, .unsupported:
            return .conflictRecord
        }
    }

    private nonisolated var displayState: CanonicalTombstoneConflictDisplayState {
        switch markerKind {
        case .softObjectTombstoneMarker, .softLibraryTombstoneMarker:
            return tombstoneState == .tombstoned ? .tombstoned : .active
        case .conflictRecord:
            return .conflict
        case .resurrectionBlockRecord:
            return .resurrectionBlocked
        case .generatedArtifactTombstoneMarkerReportOnly:
            return .reportOnly
        }
    }

    nonisolated var markerBytes: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(markerPayload)) ?? Data()
    }

    nonisolated var hasActiveVsTombstoneConflict: Bool {
        conflict?.kind == .activeVsTombstone || libraryConflict?.kind == .activeVsTombstone
    }

    nonisolated var wouldRestoreFromAbsenceOnly: Bool {
        explicitRestoreSignal == false
            && actionKind == .conflictRecord
            && hasActiveVsTombstoneConflict == false
            && tombstoneState == .active
            && (localRecordingObject?.metadata.isDeleted == true || peerRecordingObject?.metadata.isDeleted == true || localLibraryObject?.isDeleted == true || peerLibraryObject?.isDeleted == true)
    }

    nonisolated static func candidates(
        from applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest,
        rollbackCheckpointPrefix: String = "tombstone-conflict-cutover"
    ) -> [CanonicalTombstoneConflictCandidate] {
        let localObjects = Dictionary(uniqueKeysWithValues: localManifest.objects.map { ($0.objectID, $0) })
        let peerObjects = Dictionary(uniqueKeysWithValues: peerManifest.objects.map { ($0.objectID, $0) })
        let localLibraryObjects = Dictionary(uniqueKeysWithValues: localManifest.libraryObjects.map { ($0.objectID, $0) })
        let peerLibraryObjects = Dictionary(uniqueKeysWithValues: peerManifest.libraryObjects.map { ($0.objectID, $0) })
        let tombstonesByID = Dictionary(uniqueKeysWithValues: applyPlan.tombstones.map { ($0.tombstoneID, $0) })
        let conflictsByID = Dictionary(uniqueKeysWithValues: applyPlan.conflicts.map { ($0.conflictID, $0) })
        var candidates: [CanonicalTombstoneConflictCandidate] = []

        for action in applyPlan.actions {
            guard action.kind == .objectTombstoneApply
                || action.kind == .objectTombstoneSend
                || action.kind == .artifactTombstoneApply
                || action.kind == .conflictRecord
                || (action.kind == .deferredUnsupported && action.failureReason == .tombstoneBlocksResurrection) else {
                continue
            }
            candidates.append(
                CanonicalTombstoneConflictCandidate(
                    action: action,
                    recordingTombstone: action.tombstoneID.flatMap { tombstonesByID[$0] },
                    conflict: action.conflictID.flatMap { conflictsByID[$0] },
                    localRecordingObject: localObjects[action.target.objectID],
                    peerRecordingObject: peerObjects[action.target.objectID],
                    rollbackCheckpointID: "\(rollbackCheckpointPrefix)-\(action.target.objectID)-\(action.kind.rawValue)",
                    tombstoneWinsIfNewerPolicy: true,
                    rollbackEvidenceAvailable: true,
                    staleLiveMetadataRisk: action.kind == .deferredUnsupported && action.failureReason == .tombstoneBlocksResurrection
                )
            )
        }

        guard let libraryPlan else {
            return candidates
        }
        let libraryConflictsByID = Dictionary(uniqueKeysWithValues: libraryPlan.conflicts.map { ($0.conflictID, $0) })
        let libraryTombstonesByID = Dictionary(uniqueKeysWithValues: libraryPlan.tombstones.map { ($0.tombstoneID, $0) })
        for action in libraryPlan.applyActions {
            guard action.kind == .libraryTombstoneApply || action.kind == .libraryTombstoneSend || action.kind == .conflictRecord else {
                continue
            }
            let objectID = CanonicalLibraryObjectID(action.target.objectID)
            candidates.append(
                CanonicalTombstoneConflictCandidate(
                    action: action,
                    libraryTombstone: action.tombstoneID.flatMap { libraryTombstonesByID[$0] },
                    libraryConflict: action.conflictID.flatMap { libraryConflictsByID[$0] },
                    localLibraryObject: localLibraryObjects[objectID],
                    peerLibraryObject: peerLibraryObjects[objectID],
                    rollbackCheckpointID: "\(rollbackCheckpointPrefix)-\(action.target.objectID)-\(action.kind.rawValue)",
                    tombstoneWinsIfNewerPolicy: true,
                    rollbackEvidenceAvailable: true
                )
            )
        }
        return candidates
    }
}

nonisolated struct CanonicalTombstoneConflictCutoverEvidence: Codable, Equatable, Sendable {
    var noCommitEvidenceAvailable: Bool
    var realDataShadowCopyVerified: Bool
    var executionShadowVerified: Bool
    var dryRunEquivalenceVerified: Bool
    var noBlockingDivergence: Bool
    var noUnresolvedConflict: Bool
    var metadataRouteEvidenceAvailable: Bool
    var productionPortAvailable: Bool
    var realRootBoundApplyPortAvailable: Bool
    var applyPortMode: CanonicalTombstoneConflictApplyPortMode
    var rootBoundWriteAvailable: Bool
    var atomicReplaceAvailable: Bool
    var rollbackCheckpointAvailable: Bool
    var rollbackVerified: Bool
    var productionRootDisabledByDefault: Bool
    var testRootUsed: Bool
    var softTombstoneStoreSupported: Bool
    var conflictLedgerSupported: Bool
    var tombstoneWinsIfNewerPolicyAvailable: Bool
    var rollbackEvidenceAvailable: Bool
    var legacyFallbackAvailable: Bool
    var rollbackPlan: CanonicalRollbackPlan?
    var readSideParallelEquivalent: Bool
    var canaryStageEvidence: CanonicalTombstoneConflictCanaryStageEvidence?

    nonisolated init(
        noCommitEvidenceAvailable: Bool = false,
        realDataShadowCopyVerified: Bool = false,
        executionShadowVerified: Bool = false,
        dryRunEquivalenceVerified: Bool = false,
        noBlockingDivergence: Bool = false,
        noUnresolvedConflict: Bool = false,
        metadataRouteEvidenceAvailable: Bool = false,
        productionPortAvailable: Bool = false,
        realRootBoundApplyPortAvailable: Bool = false,
        applyPortMode: CanonicalTombstoneConflictApplyPortMode = .disabled,
        rootBoundWriteAvailable: Bool = false,
        atomicReplaceAvailable: Bool = false,
        rollbackCheckpointAvailable: Bool = false,
        rollbackVerified: Bool = false,
        productionRootDisabledByDefault: Bool = false,
        testRootUsed: Bool = false,
        softTombstoneStoreSupported: Bool = false,
        conflictLedgerSupported: Bool = false,
        tombstoneWinsIfNewerPolicyAvailable: Bool = false,
        rollbackEvidenceAvailable: Bool = false,
        legacyFallbackAvailable: Bool = false,
        rollbackPlan: CanonicalRollbackPlan? = nil,
        readSideParallelEquivalent: Bool = false,
        canaryStageEvidence: CanonicalTombstoneConflictCanaryStageEvidence? = nil
    ) {
        self.noCommitEvidenceAvailable = noCommitEvidenceAvailable
        self.realDataShadowCopyVerified = realDataShadowCopyVerified
        self.executionShadowVerified = executionShadowVerified
        self.dryRunEquivalenceVerified = dryRunEquivalenceVerified
        self.noBlockingDivergence = noBlockingDivergence
        self.noUnresolvedConflict = noUnresolvedConflict
        self.metadataRouteEvidenceAvailable = metadataRouteEvidenceAvailable
        self.productionPortAvailable = productionPortAvailable
        self.realRootBoundApplyPortAvailable = realRootBoundApplyPortAvailable
        self.applyPortMode = applyPortMode
        self.rootBoundWriteAvailable = rootBoundWriteAvailable
        self.atomicReplaceAvailable = atomicReplaceAvailable
        self.rollbackCheckpointAvailable = rollbackCheckpointAvailable
        self.rollbackVerified = rollbackVerified
        self.productionRootDisabledByDefault = productionRootDisabledByDefault
        self.testRootUsed = testRootUsed
        self.softTombstoneStoreSupported = softTombstoneStoreSupported
        self.conflictLedgerSupported = conflictLedgerSupported
        self.tombstoneWinsIfNewerPolicyAvailable = tombstoneWinsIfNewerPolicyAvailable
        self.rollbackEvidenceAvailable = rollbackEvidenceAvailable
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.rollbackPlan = rollbackPlan
        self.readSideParallelEquivalent = readSideParallelEquivalent
        self.canaryStageEvidence = canaryStageEvidence
    }

    nonisolated static func passing(rollbackPlan: CanonicalRollbackPlan) -> CanonicalTombstoneConflictCutoverEvidence {
        CanonicalTombstoneConflictCutoverEvidence(
            noCommitEvidenceAvailable: true,
            realDataShadowCopyVerified: true,
            executionShadowVerified: true,
            dryRunEquivalenceVerified: true,
            noBlockingDivergence: true,
            noUnresolvedConflict: true,
            metadataRouteEvidenceAvailable: true,
            productionPortAvailable: true,
            realRootBoundApplyPortAvailable: true,
            applyPortMode: .testRootBound,
            rootBoundWriteAvailable: true,
            atomicReplaceAvailable: true,
            rollbackCheckpointAvailable: true,
            rollbackVerified: true,
            productionRootDisabledByDefault: true,
            testRootUsed: true,
            softTombstoneStoreSupported: true,
            conflictLedgerSupported: true,
            tombstoneWinsIfNewerPolicyAvailable: true,
            rollbackEvidenceAvailable: true,
            legacyFallbackAvailable: true,
            rollbackPlan: rollbackPlan,
            readSideParallelEquivalent: true
        )
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    nonisolated var shortCanonicalPrefix: String {
        String(prefix(12))
    }
}

nonisolated enum CanonicalTombstoneConflictCanaryStage: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case n1
    case n3
    case n10
    case allEligible

    nonisolated var isExecutable: Bool { self != .disabled }

    nonisolated var previousStage: CanonicalTombstoneConflictCanaryStage? {
        switch self {
        case .disabled: return nil
        case .n1: return .disabled
        case .n3: return .n1
        case .n10: return .n3
        case .allEligible: return .n10
        }
    }

    nonisolated var nominalBudget: Int {
        switch self {
        case .disabled: return 0
        case .n1: return 1
        case .n3: return 3
        case .n10: return 10
        case .allEligible: return Int.max
        }
    }

    nonisolated var minimumPreviousStageSuccessCount: Int {
        switch self {
        case .disabled, .n1: return 0
        case .n3: return 1
        case .n10: return 3
        case .allEligible: return 10
        }
    }
}

nonisolated enum CanonicalTombstoneConflictStageEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missing
    case incomplete
    case passed
    case failed
    case blocked
}

nonisolated struct CanonicalTombstoneConflictCanaryStageEvidence: Codable, Equatable, Sendable {
    var stage: CanonicalTombstoneConflictCanaryStage
    var previousStage: CanonicalTombstoneConflictCanaryStage?
    var status: CanonicalTombstoneConflictStageEvidenceStatus
    var successfulCommitCount: Int
    var failedCommitCount: Int
    var rollbackFailureCount: Int
    var resurrectionRiskCount: Int
    var physicalDeleteAttemptCount: Int
    var permanentDeleteAttemptCount: Int
    var tombstoneGCAttemptCount: Int
    var conflictAmbiguityCount: Int
    var noCommitEvidenceAvailable: Bool
    var observationWindowComplete: Bool

    nonisolated init(
        stage: CanonicalTombstoneConflictCanaryStage,
        previousStage: CanonicalTombstoneConflictCanaryStage? = nil,
        status: CanonicalTombstoneConflictStageEvidenceStatus,
        successfulCommitCount: Int = 0,
        failedCommitCount: Int = 0,
        rollbackFailureCount: Int = 0,
        resurrectionRiskCount: Int = 0,
        physicalDeleteAttemptCount: Int = 0,
        permanentDeleteAttemptCount: Int = 0,
        tombstoneGCAttemptCount: Int = 0,
        conflictAmbiguityCount: Int = 0,
        noCommitEvidenceAvailable: Bool = false,
        observationWindowComplete: Bool = false
    ) {
        self.stage = stage
        self.previousStage = previousStage
        self.status = status
        self.successfulCommitCount = max(0, successfulCommitCount)
        self.failedCommitCount = max(0, failedCommitCount)
        self.rollbackFailureCount = max(0, rollbackFailureCount)
        self.resurrectionRiskCount = max(0, resurrectionRiskCount)
        self.physicalDeleteAttemptCount = max(0, physicalDeleteAttemptCount)
        self.permanentDeleteAttemptCount = max(0, permanentDeleteAttemptCount)
        self.tombstoneGCAttemptCount = max(0, tombstoneGCAttemptCount)
        self.conflictAmbiguityCount = max(0, conflictAmbiguityCount)
        self.noCommitEvidenceAvailable = noCommitEvidenceAvailable
        self.observationWindowComplete = observationWindowComplete
    }

    nonisolated static func passing(
        stage: CanonicalTombstoneConflictCanaryStage,
        successfulCommitCount: Int
    ) -> CanonicalTombstoneConflictCanaryStageEvidence {
        CanonicalTombstoneConflictCanaryStageEvidence(
            stage: stage,
            previousStage: stage.previousStage,
            status: .passed,
            successfulCommitCount: successfulCommitCount,
            noCommitEvidenceAvailable: true,
            observationWindowComplete: true
        )
    }
}

nonisolated struct CanonicalTombstoneConflictCanaryPolicy: Codable, Equatable, Sendable {
    var requestedStage: CanonicalTombstoneConflictCanaryStage
    var canaryMaxObjectsPerSyncRun: Int
    var allowCandidateExecution: Bool
    var allowsInternalN1Execution: Bool
    var explicitInternalTestConfiguration: Bool
    var runtimeSwitchEnabled: Bool
    var allowAllEligible: Bool

    nonisolated init(
        requestedStage: CanonicalTombstoneConflictCanaryStage = .disabled,
        canaryMaxObjectsPerSyncRun: Int = 0,
        allowCandidateExecution: Bool = false,
        allowsInternalN1Execution: Bool = false,
        explicitInternalTestConfiguration: Bool = false,
        runtimeSwitchEnabled: Bool = false,
        allowAllEligible: Bool = false
    ) {
        self.requestedStage = requestedStage
        self.canaryMaxObjectsPerSyncRun = max(0, canaryMaxObjectsPerSyncRun)
        self.allowCandidateExecution = allowCandidateExecution
        self.allowsInternalN1Execution = allowsInternalN1Execution
        self.explicitInternalTestConfiguration = explicitInternalTestConfiguration
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.allowAllEligible = allowAllEligible
    }

    nonisolated static let disabled = CanonicalTombstoneConflictCanaryPolicy()

    nonisolated var budget: Int {
        requestedStage.isExecutable ? requestedStage.nominalBudget : canaryMaxObjectsPerSyncRun
    }

    private enum CodingKeys: String, CodingKey {
        case requestedStage
        case canaryMaxObjectsPerSyncRun
        case allowCandidateExecution
        case allowsInternalN1Execution
        case explicitInternalTestConfiguration
        case runtimeSwitchEnabled
        case allowAllEligible
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            requestedStage: try container.decodeIfPresent(CanonicalTombstoneConflictCanaryStage.self, forKey: .requestedStage) ?? .disabled,
            canaryMaxObjectsPerSyncRun: try container.decodeIfPresent(Int.self, forKey: .canaryMaxObjectsPerSyncRun) ?? 0,
            allowCandidateExecution: try container.decodeIfPresent(Bool.self, forKey: .allowCandidateExecution) ?? false,
            allowsInternalN1Execution: try container.decodeIfPresent(Bool.self, forKey: .allowsInternalN1Execution) ?? false,
            explicitInternalTestConfiguration: try container.decodeIfPresent(Bool.self, forKey: .explicitInternalTestConfiguration) ?? false,
            runtimeSwitchEnabled: try container.decodeIfPresent(Bool.self, forKey: .runtimeSwitchEnabled) ?? false,
            allowAllEligible: try container.decodeIfPresent(Bool.self, forKey: .allowAllEligible) ?? false
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestedStage, forKey: .requestedStage)
        try container.encode(canaryMaxObjectsPerSyncRun, forKey: .canaryMaxObjectsPerSyncRun)
        try container.encode(allowCandidateExecution, forKey: .allowCandidateExecution)
        try container.encode(allowsInternalN1Execution, forKey: .allowsInternalN1Execution)
        try container.encode(explicitInternalTestConfiguration, forKey: .explicitInternalTestConfiguration)
        try container.encode(runtimeSwitchEnabled, forKey: .runtimeSwitchEnabled)
        try container.encode(allowAllEligible, forKey: .allowAllEligible)
    }
}

nonisolated struct CanonicalTombstoneConflictCanaryStageGate: Codable, Equatable, Sendable {
    var allowed: Bool
    var selectedCandidateLimit: Int
    var failures: [CanonicalTombstoneConflictFailure]

    nonisolated init(
        policy: CanonicalTombstoneConflictCanaryPolicy,
        evidence: CanonicalTombstoneConflictCutoverEvidence
    ) {
        var failures: [CanonicalTombstoneConflictFailure] = []
        if !policy.requestedStage.isExecutable {
            failures.append(.disabled)
        }
        if !policy.allowCandidateExecution {
            failures.append(.missingInternalCanaryConfiguration)
        }
        if policy.runtimeSwitchEnabled {
            failures.append(.unsupportedMode)
        }
        guard let stageEvidence = evidence.canaryStageEvidence else {
            self.failures = Array(Set(failures + [.missingCanaryStageEvidence])).sorted { $0.rawValue < $1.rawValue }
            self.allowed = false
            self.selectedCandidateLimit = 0
            return
        }
        if stageEvidence.status != .passed { failures.append(.canaryStageBlocked) }
        if stageEvidence.previousStage != policy.requestedStage.previousStage { failures.append(.canaryStageOrderViolation) }
        if stageEvidence.successfulCommitCount < policy.requestedStage.minimumPreviousStageSuccessCount { failures.append(.canaryStageOrderViolation) }
        if stageEvidence.failedCommitCount > 0 { failures.append(.previousStageFailure) }
        if stageEvidence.rollbackFailureCount > 0 { failures.append(.previousStageRollbackFailure) }
        if stageEvidence.resurrectionRiskCount > 0 { failures.append(.resurrectionRiskDetected) }
        if stageEvidence.physicalDeleteAttemptCount > 0 { failures.append(.physicalDeleteAttempted) }
        if stageEvidence.permanentDeleteAttemptCount > 0 { failures.append(.permanentDeleteAttempted) }
        if stageEvidence.tombstoneGCAttemptCount > 0 { failures.append(.tombstoneGCAttempted) }
        if stageEvidence.conflictAmbiguityCount > 0 { failures.append(.conflictPolicyAmbiguous) }
        if !stageEvidence.noCommitEvidenceAvailable || !evidence.noCommitEvidenceAvailable { failures.append(.missingNoCommitEvidence) }
        self.failures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = self.failures.isEmpty
        self.selectedCandidateLimit = self.allowed ? policy.requestedStage.nominalBudget : 0
    }
}

nonisolated struct CanonicalTombstoneConflictCutoverGate: Codable, Equatable, Sendable {
    var mode: CanonicalCutoverMode
    var allowed: Bool
    var failures: [CanonicalTombstoneConflictFailure]
    var legacyFallbackAvailable: Bool
    var reason: String

    nonisolated init(
        mode: CanonicalCutoverMode,
        failures: [CanonicalTombstoneConflictFailure],
        legacyFallbackAvailable: Bool,
        reason: String
    ) {
        self.mode = mode
        self.failures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = self.failures.isEmpty
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (self.allowed ? "allowed" : "blocked")
    }
}

nonisolated struct CanonicalTombstoneConflictProductionCommitResult: Codable, Equatable, Sendable {
    var actionID: String
    var objectID: String
    var domain: CanonicalTombstoneConflictDomain
    var actionKind: CanonicalTombstoneConflictActionKind
    var committed: Bool
    var partialCommit: Bool
    var preconditionVerified: Bool
    var postconditionVerified: Bool
    var tombstoneState: CanonicalTombstoneState
    var deletedAtSummary: String
    var conflictKind: String
    var conflictPolicy: String
    var productionCommitSuppressed: Bool
    var physicalDeleteSuppressed: Bool
    var permanentDeleteSuppressed: Bool
    var tombstoneGCSuppressed: Bool
    var generatedArtifactDownloadBlocked: Bool
    var receiveJSONMutated: Bool
    var audioTranscriptNoteSummaryDeleted: Bool
    var sideEffects: [CanonicalProductionSideEffect]
    var failureKind: CanonicalTombstoneConflictFailure?
    var reason: String

    nonisolated init(
        actionID: String,
        objectID: String,
        domain: CanonicalTombstoneConflictDomain,
        actionKind: CanonicalTombstoneConflictActionKind,
        committed: Bool,
        partialCommit: Bool = false,
        preconditionVerified: Bool = true,
        postconditionVerified: Bool = true,
        tombstoneState: CanonicalTombstoneState,
        deletedAtSummary: String,
        conflictKind: String,
        conflictPolicy: String,
        productionCommitSuppressed: Bool = false,
        physicalDeleteSuppressed: Bool = true,
        permanentDeleteSuppressed: Bool = true,
        tombstoneGCSuppressed: Bool = true,
        generatedArtifactDownloadBlocked: Bool = true,
        receiveJSONMutated: Bool = false,
        audioTranscriptNoteSummaryDeleted: Bool = false,
        sideEffects: [CanonicalProductionSideEffect] = [],
        failureKind: CanonicalTombstoneConflictFailure? = nil,
        reason: String
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: actionKind.rawValue)
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "tombstone-object")
        self.domain = domain
        self.actionKind = actionKind
        self.committed = committed
        self.partialCommit = partialCommit
        self.preconditionVerified = preconditionVerified
        self.postconditionVerified = postconditionVerified
        self.tombstoneState = tombstoneState
        self.deletedAtSummary = CanonicalProductionRedaction.safeDiagnosticText(deletedAtSummary) ?? "deletedAt=missing"
        self.conflictKind = CanonicalProductionRedaction.safeDiagnosticText(conflictKind) ?? "none"
        self.conflictPolicy = CanonicalProductionRedaction.safeDiagnosticText(conflictPolicy) ?? "none"
        self.productionCommitSuppressed = productionCommitSuppressed
        self.physicalDeleteSuppressed = physicalDeleteSuppressed
        self.permanentDeleteSuppressed = permanentDeleteSuppressed
        self.tombstoneGCSuppressed = tombstoneGCSuppressed
        self.generatedArtifactDownloadBlocked = generatedArtifactDownloadBlocked
        self.receiveJSONMutated = receiveJSONMutated
        self.audioTranscriptNoteSummaryDeleted = audioTranscriptNoteSummaryDeleted
        self.sideEffects = sideEffects
        self.failureKind = failureKind
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (committed ? "committed" : "failed")
    }

    nonisolated static func success(candidate: CanonicalTombstoneConflictCandidate, sideEffects: [CanonicalProductionSideEffect]) -> CanonicalTombstoneConflictProductionCommitResult {
        CanonicalTombstoneConflictProductionCommitResult(
            actionID: candidate.action.actionID,
            objectID: candidate.objectID,
            domain: candidate.domain,
            actionKind: candidate.actionKind,
            committed: true,
            tombstoneState: candidate.tombstoneState,
            deletedAtSummary: candidate.deletedAtSummary,
            conflictKind: candidate.conflictKindSummary,
            conflictPolicy: candidate.conflictPolicySummary,
            sideEffects: sideEffects,
            reason: "tombstoneConflictCommitted"
        )
    }

    nonisolated static func failure(
        candidate: CanonicalTombstoneConflictCandidate,
        kind failureKind: CanonicalTombstoneConflictFailure,
        partialCommit: Bool = false,
        reason: String
    ) -> CanonicalTombstoneConflictProductionCommitResult {
        CanonicalTombstoneConflictProductionCommitResult(
            actionID: candidate.action.actionID,
            objectID: candidate.objectID,
            domain: candidate.domain,
            actionKind: candidate.actionKind,
            committed: false,
            partialCommit: partialCommit,
            preconditionVerified: failureKind != .preconditionMismatch && failureKind != .objectIDMismatch,
            postconditionVerified: failureKind != .postconditionMismatch,
            tombstoneState: candidate.tombstoneState,
            deletedAtSummary: candidate.deletedAtSummary,
            conflictKind: candidate.conflictKindSummary,
            conflictPolicy: candidate.conflictPolicySummary,
            productionCommitSuppressed: false,
            failureKind: failureKind,
            reason: reason
        )
    }
}

nonisolated struct CanonicalTombstoneConflictRollbackExecutionResult: Codable, Equatable, Sendable {
    var checkpointID: String
    var succeeded: Bool
    var fatal: Bool
    var reason: String
    var rollbackResult: CanonicalRollbackResult?

    nonisolated init(
        checkpointID: String,
        succeeded: Bool,
        fatal: Bool = false,
        reason: String,
        rollbackResult: CanonicalRollbackResult? = nil
    ) {
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "tombstone-conflict-checkpoint")
        self.succeeded = succeeded
        self.fatal = fatal
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (succeeded ? "rollbackCompleted" : "rollbackFailed")
        self.rollbackResult = rollbackResult
    }
}

protocol CanonicalTombstoneConflictCutoverExecutor: Sendable {
    func commitTombstoneConflict(
        _ candidate: CanonicalTombstoneConflictCandidate
    ) async -> CanonicalTombstoneConflictProductionCommitResult

    func rollbackTombstoneConflict(
        _ candidate: CanonicalTombstoneConflictCandidate,
        reason: CanonicalTombstoneConflictFailure
    ) async -> CanonicalTombstoneConflictRollbackExecutionResult
}

nonisolated enum CanonicalTombstoneConflictCutoverDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalTombstoneCutoverGateEvaluated
    case canonicalTombstoneCutoverGateBlocked
    case canonicalTombstoneNoCommitStarted
    case canonicalTombstoneNoCommitCompleted
    case canonicalTombstoneCommitStarted
    case canonicalTombstoneCommitCompleted
    case canonicalTombstoneCommitFailed
    case canonicalTombstoneRollbackStarted
    case canonicalTombstoneRollbackCompleted
    case canonicalTombstoneRollbackFailed
    case canonicalTombstoneCanaryStarted
    case canonicalTombstoneCanaryCompleted
    case canonicalTombstoneDuplicateLegacySuppressed
    case canonicalTombstoneLegacyFallbackUsed
    case canonicalTombstonePhysicalDeleteBlocked
    case canonicalTombstonePermanentDeleteBlocked
    case canonicalTombstoneGCBlocked
    case canonicalTombstoneResurrectionBlocked
    case canonicalTombstoneResurrectionRiskDetected
    case canonicalConflictRecordCommitted
    case canonicalConflictPolicyAmbiguousBlocked
    case canonicalTombstoneUIProjectionParallelReadStarted
    case canonicalTombstoneUIProjectionParallelReadEquivalent
    case canonicalTombstoneUIProjectionParallelReadDivergent
    case canonicalConflictUIProjectionParallelReadStarted
    case canonicalConflictUIProjectionParallelReadEquivalent
    case canonicalConflictUIProjectionParallelReadDivergent
    case canonicalTombstoneConflictN1CanaryConfigured
    case canonicalTombstoneConflictN1CandidateSelectionStarted
    case canonicalTombstoneConflictN1CandidateSelected
    case canonicalTombstoneConflictN1NoEligibleCandidate
    case canonicalTombstoneConflictN1CandidateBlocked
    case canonicalTombstoneConflictN1CanaryStarted
    case canonicalTombstoneConflictN1CommitStarted
    case canonicalTombstoneConflictN1CommitCompleted
    case canonicalTombstoneConflictN1CommitFailed
    case canonicalTombstoneConflictN1PostconditionVerified
    case canonicalTombstoneConflictN1PostconditionFailed
    case canonicalTombstoneConflictN1RollbackStarted
    case canonicalTombstoneConflictN1RollbackCompleted
    case canonicalTombstoneConflictN1RollbackFailed
    case canonicalTombstoneConflictN1LegacyFallbackUsed
    case canonicalTombstoneConflictN1DuplicateLegacySuppressed
    case canonicalTombstoneConflictN1DuplicateSuppressionSkipped
    case canonicalTombstoneConflictN1FatalBlocker
    case canonicalTombstoneConflictN1ObservationRecorded
    case canonicalTombstoneConflictN1AntiResurrectionBlocked
    case canonicalTombstoneConflictN1PhysicalDeleteBlocked
    case canonicalTombstoneConflictN1PermanentDeleteBlocked
    case canonicalTombstoneConflictN1GCBlocked
    case canonicalTombstoneConflictN1AutoResolutionBlocked
    case canonicalTombstoneConflictN1StaleLiveResurrectionBlocked
    case canonicalTombstoneConflictN1MacPeerSnapshotUnavailable
}

nonisolated struct CanonicalTombstoneConflictCutoverDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", result ?? "", reason ?? ""].joined(separator: "|") }

    var kind: CanonicalTombstoneConflictCutoverDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var domain: CanonicalTombstoneConflictDomain?
    var objectID: String?
    var action: String?
    var tombstoneState: CanonicalTombstoneState?
    var conflictKind: String?
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalTombstoneConflictCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalTombstoneConflictDomain? = nil,
        objectID: String? = nil,
        action: String? = nil,
        tombstoneState: CanonicalTombstoneState? = nil,
        conflictKind: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) {
        self.kind = kind
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.domain = domain
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "tombstone-object") }
        self.action = CanonicalProductionRedaction.safeDiagnosticText(action)
        self.tombstoneState = tombstoneState
        self.conflictKind = CanonicalProductionRedaction.safeDiagnosticText(conflictKind)
        self.result = CanonicalProductionRedaction.safeDiagnosticText(result)
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
        self.hashPrefix = hash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "syncRunID=\(syncRunID ?? "none")",
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            "domain=\(domain?.rawValue ?? "none")",
            "objectID=\(objectID ?? "none")",
            "action=\(action ?? "none")",
            "tombstoneState=\(tombstoneState?.rawValue ?? "none")",
            "conflictKind=\(conflictKind ?? "none")",
            "result=\(result ?? "none")",
            "reason=\(reason ?? "none")",
            "hashPrefix=\(hashPrefix ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalTombstoneConflictReadSideParallelProjectionResult: Codable, Equatable, Sendable {
    var objectID: String
    var domain: CanonicalTombstoneConflictDomain
    var equivalent: Bool
    var mutatedUI: Bool
    var canonicalTombstoneState: CanonicalTombstoneState
    var legacyDeletedState: CanonicalTombstoneState
    var conflictRecorded: Bool
    var antiResurrectionStatus: String
    var syncOrUploadTriggered: Bool
    var reason: String

    nonisolated init(
        candidate: CanonicalTombstoneConflictCandidate,
        equivalent: Bool,
        conflictRecorded: Bool,
        reason: String
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(candidate.objectID, fallback: "tombstone-object")
        self.domain = candidate.domain
        self.equivalent = equivalent
        self.mutatedUI = false
        self.canonicalTombstoneState = candidate.tombstoneState
        self.legacyDeletedState = candidate.tombstoneState
        self.conflictRecorded = conflictRecorded
        self.antiResurrectionStatus = candidate.actionKind == .resurrectionBlocked ? "blocked" : "notTriggered"
        self.syncOrUploadTriggered = false
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (equivalent ? "equivalent" : "divergent")
    }
}

nonisolated struct CanonicalTombstoneConflictCutoverResult: Codable, Equatable, Sendable {
    var gate: CanonicalTombstoneConflictCutoverGate
    var commits: [CanonicalTombstoneConflictProductionCommitResult]
    var rollbackResults: [CanonicalTombstoneConflictRollbackExecutionResult]
    var diagnostics: [CanonicalTombstoneConflictCutoverDiagnostic]
    var legacyFallbackUsed: Bool
    var duplicateLegacySuppressedActionIDs: [String]
    var canaryAttemptedCount: Int
    var canarySucceeded: Bool
    var fatalBlocker: Bool
    var readSideProjection: CanonicalTombstoneConflictReadSideParallelProjectionResult?

    nonisolated var succeeded: Bool {
        gate.allowed && !fatalBlocker && !commits.isEmpty && commits.allSatisfy { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
    }
}

nonisolated struct CanonicalTombstoneConflictCutoverRunner: Sendable {
    nonisolated init() {}

    nonisolated func evaluateGate(
        mode: CanonicalCutoverMode,
        policy: CanonicalTombstoneConflictCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalTombstoneConflictCutoverEvidence,
        candidates: [CanonicalTombstoneConflictCandidate],
        trigger: CanonicalSyncPlanTrigger
    ) -> CanonicalTombstoneConflictCutoverGate {
        var failures: [CanonicalTombstoneConflictFailure] = []
        if mode == .disabled { failures.append(.disabled) }
        if mode != .canary && mode != .guardedExecuteCommit { failures.append(.unsupportedMode) }
        if token == nil { failures.append(.missingToken) }
        if token?.ownerApproved != true { failures.append(.missingOwnerApproval) }
        let executableCandidates = candidates.filter(\.actionKind.isExecutable)
        let requiredDomains = Set(executableCandidates.map(\.domain.productionDomain))
        if executableCandidates.isEmpty {
            failures.append(.unsupportedAction)
        } else if !requiredDomains.allSatisfy({ evidence.rollbackPlan?.covers(domain: $0) == true }) {
            failures.append(.missingRollback)
        }
        if !evidence.noCommitEvidenceAvailable { failures.append(.missingNoCommitEvidence) }
        if !evidence.dryRunEquivalenceVerified { failures.append(.missingDryRunEquivalence) }
        if !evidence.executionShadowVerified { failures.append(.missingExecutionShadowEvidence) }
        if !evidence.realDataShadowCopyVerified { failures.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.noBlockingDivergence { failures.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict { failures.append(.unresolvedConflict) }
        if !evidence.metadataRouteEvidenceAvailable { failures.append(.missingMetadataRouteEvidence) }
        if !evidence.productionPortAvailable { failures.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { failures.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { failures.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { failures.append(.rollbackCheckpointUnavailable) }
        if !evidence.rollbackVerified { failures.append(.rollbackVerificationMissing) }
        if !evidence.productionRootDisabledByDefault { failures.append(.productionRootEnabledByDefault) }
        if evidence.applyPortMode == .testRootBound && !evidence.testRootUsed { failures.append(.testRootMissing) }
        if !evidence.softTombstoneStoreSupported {
            failures.append(.softDeleteMarkerUnsupported)
            failures.append(.softTombstoneStoreUnsupported)
        }
        if candidates.contains(where: { $0.domain.requiresConflictLedger }) && !evidence.conflictLedgerSupported { failures.append(.conflictLedgerUnsupported) }
        if !evidence.legacyFallbackAvailable { failures.append(.missingRollback) }
        if trigger == .viewRefresh || trigger == .retryDrainer { failures.append(.unsupportedMode) }
        if candidates.contains(where: { $0.actionKind == .generatedArtifactTombstoneMarkUnsupported }) { failures.append(.generatedArtifactTombstoneUnsupported) }
        if candidates.contains(where: { $0.actionKind == .unsupported }) { failures.append(.unsupportedAction) }
        if candidates.contains(where: { $0.actionKind.isTombstoneMarkerWrite && (!$0.tombstoneWinsIfNewerPolicy || !$0.rollbackEvidenceAvailable) }) {
            failures.append(.missingTombstoneWinsPolicy)
            failures.append(.tombstonePolicyMissing)
        }
        if candidates.contains(where: { $0.actionKind.isTombstoneMarkerWrite && $0.deletedAt == nil }) {
            failures.append(.missingTombstoneTimestamp)
            failures.append(.tombstoneTimestampInvalid)
        }
        if !evidence.tombstoneWinsIfNewerPolicyAvailable {
            failures.append(.missingTombstoneWinsPolicy)
            failures.append(.tombstonePolicyMissing)
        }
        if !evidence.rollbackEvidenceAvailable {
            failures.append(.missingRollbackEvidence)
            failures.append(.rollbackEvidenceMissing)
        }
        if candidates.contains(where: { $0.staleLiveMetadataRisk && $0.actionKind != .resurrectionBlocked }) {
            failures.append(.resurrectionRiskDetected)
        }
        if candidates.contains(where: { !$0.conflictPolicyKnown }) { failures.append(.conflictPolicyAmbiguous) }
        if candidates.contains(where: \.wouldRestoreFromAbsenceOnly) { failures.append(.unsupportedRestore) }
        if candidates.contains(where: { !$0.action.reason.lowercased().contains("no") && $0.action.reason.lowercased().contains("physicaldelete") }) {
            failures.append(.physicalDeleteAttempted)
        }
        if candidates.contains(where: { $0.action.reason.lowercased().contains("permanentdelete") }) {
            failures.append(.permanentDeleteAttempted)
        }
        if candidates.contains(where: { $0.action.reason.lowercased().contains("tombstonegc") }) {
            failures.append(.tombstoneGCAttempted)
        }
        if mode == .canary {
            if policy.requestedStage.isExecutable {
                let stageGate = CanonicalTombstoneConflictCanaryStageGate(policy: policy, evidence: evidence)
                failures.append(contentsOf: stageGate.failures)
            } else {
                if policy.canaryMaxObjectsPerSyncRun == 0 { failures.append(.disabled) }
                if policy.canaryMaxObjectsPerSyncRun == 1 && !policy.allowCandidateExecution { failures.append(.missingInternalCanaryConfiguration) }
                if policy.canaryMaxObjectsPerSyncRun > 1 { failures.append(.canaryBudgetAboveOneDenied) }
                if policy.runtimeSwitchEnabled { failures.append(.unsupportedMode) }
            }
        }
        return CanonicalTombstoneConflictCutoverGate(
            mode: mode,
            failures: failures,
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            reason: failures.isEmpty ? "allowed" : failures.map(\.rawValue).joined(separator: ",")
        )
    }

    nonisolated func run(
        mode: CanonicalCutoverMode,
        policy: CanonicalTombstoneConflictCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalTombstoneConflictCutoverEvidence,
        candidates: [CanonicalTombstoneConflictCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        executor: any CanonicalTombstoneConflictCutoverExecutor
    ) async -> CanonicalTombstoneConflictCutoverResult {
        let gate = evaluateGate(mode: mode, policy: policy, token: token, evidence: evidence, candidates: candidates, trigger: trigger)
        var diagnostics: [CanonicalTombstoneConflictCutoverDiagnostic] = [
            diagnostic(.canonicalTombstoneCutoverGateEvaluated, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: gate.allowed ? "allowed" : "blocked", reason: gate.reason)
        ]
        if !gate.allowed {
            diagnostics.append(diagnostic(.canonicalTombstoneCutoverGateBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: gate.failures.map(\.rawValue).joined(separator: ",")))
            appendBoundaryDiagnostics(gate.failures, diagnostics: &diagnostics, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole)
            return CanonicalTombstoneConflictCutoverResult(
                gate: gate,
                commits: [],
                rollbackResults: [],
                diagnostics: diagnostics,
                legacyFallbackUsed: gate.legacyFallbackAvailable,
                duplicateLegacySuppressedActionIDs: [],
                canaryAttemptedCount: 0,
                canarySucceeded: false,
                fatalBlocker: false,
                readSideProjection: nil
            )
        }

        diagnostics.append(diagnostic(.canonicalTombstoneCanaryStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "started", reason: "candidateCount=\(candidates.count)"))
        let selected = selectCandidates(policy: policy, candidates: candidates)
        var commits: [CanonicalTombstoneConflictProductionCommitResult] = []
        var rollbacks: [CanonicalTombstoneConflictRollbackExecutionResult] = []
        var legacyFallbackUsed = false
        var fatalBlocker = false
        for candidate in selected {
            diagnostics.append(diagnostic(.canonicalTombstoneCommitStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, candidate: candidate, result: "started", hash: candidate.markerHash))
            let commit = await executor.commitTombstoneConflict(candidate)
            commits.append(commit)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                diagnostics.append(diagnostic(candidate.domain.requiresConflictLedger ? .canonicalConflictRecordCommitted : .canonicalTombstoneCommitCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, candidate: candidate, result: "committed", hash: candidate.markerHash))
                if candidate.actionKind == .resurrectionBlocked {
                    diagnostics.append(diagnostic(.canonicalTombstoneResurrectionBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, candidate: candidate, result: "blocked", reason: "antiResurrection=true"))
                }
            } else {
                legacyFallbackUsed = true
                diagnostics.append(diagnostic(.canonicalTombstoneCommitFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, candidate: candidate, result: "failed", reason: commit.failureKind?.rawValue ?? commit.reason, hash: candidate.markerHash))
                diagnostics.append(diagnostic(.canonicalTombstoneRollbackStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, candidate: candidate, result: "started"))
                let rollback = await executor.rollbackTombstoneConflict(candidate, reason: commit.failureKind ?? .postconditionMismatch)
                rollbacks.append(rollback)
                fatalBlocker = fatalBlocker || rollback.fatal || !rollback.succeeded
                diagnostics.append(diagnostic(rollback.succeeded ? .canonicalTombstoneRollbackCompleted : .canonicalTombstoneRollbackFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, candidate: candidate, result: rollback.succeeded ? "rolledBack" : "rollbackFailed", reason: rollback.reason))
            }
        }
        let successfulActionIDs = commits
            .filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
            .map(\.actionID)
            .sorted()
        if !successfulActionIDs.isEmpty {
            diagnostics.append(diagnostic(.canonicalTombstoneDuplicateLegacySuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "candidate", reason: "successOnly"))
        }
        if legacyFallbackUsed {
            diagnostics.append(diagnostic(.canonicalTombstoneLegacyFallbackUsed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "used", reason: "commitFailureOrRollback"))
        }
        let readSide = selected.first.map {
            CanonicalTombstoneConflictReadSideParallelProjectionResult(
                candidate: $0,
                equivalent: commits.first?.committed == true,
                conflictRecorded: commits.first?.actionKind == .conflictRecord || commits.first?.actionKind == .resurrectionBlocked,
                reason: commits.first?.committed == true ? "parallelReadEquivalent" : "parallelReadDivergent"
            )
        }
        if let readSide {
            let started: CanonicalTombstoneConflictCutoverDiagnosticKind = readSide.domain.requiresConflictLedger ? .canonicalConflictUIProjectionParallelReadStarted : .canonicalTombstoneUIProjectionParallelReadStarted
            let done: CanonicalTombstoneConflictCutoverDiagnosticKind
            if readSide.domain.requiresConflictLedger {
                done = readSide.equivalent ? .canonicalConflictUIProjectionParallelReadEquivalent : .canonicalConflictUIProjectionParallelReadDivergent
            } else {
                done = readSide.equivalent ? .canonicalTombstoneUIProjectionParallelReadEquivalent : .canonicalTombstoneUIProjectionParallelReadDivergent
            }
            diagnostics.append(diagnostic(started, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, domain: readSide.domain, objectID: readSide.objectID, result: "started", reason: "mutatedUI=false"))
            diagnostics.append(diagnostic(done, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, domain: readSide.domain, objectID: readSide.objectID, result: readSide.equivalent ? "equivalent" : "divergent", reason: "mutatedUI=false"))
        }
        diagnostics.append(diagnostic(.canonicalTombstoneCanaryCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: successfulActionIDs.isEmpty ? "noSuccessfulCommit" : "completed", reason: "attempted=\(selected.count)"))
        return CanonicalTombstoneConflictCutoverResult(
            gate: gate,
            commits: commits,
            rollbackResults: rollbacks,
            diagnostics: diagnostics,
            legacyFallbackUsed: legacyFallbackUsed,
            duplicateLegacySuppressedActionIDs: successfulActionIDs,
            canaryAttemptedCount: selected.count,
            canarySucceeded: !successfulActionIDs.isEmpty && !fatalBlocker && !legacyFallbackUsed,
            fatalBlocker: fatalBlocker,
            readSideProjection: readSide
        )
    }

    nonisolated private func selectCandidates(
        policy: CanonicalTombstoneConflictCanaryPolicy,
        candidates: [CanonicalTombstoneConflictCandidate]
    ) -> [CanonicalTombstoneConflictCandidate] {
        let limit = policy.budget == Int.max ? candidates.count : policy.budget
        return candidates
            .filter(\.actionKind.isExecutable)
            .sorted {
                if $0.domain.rawValue != $1.domain.rawValue { return $0.domain.rawValue < $1.domain.rawValue }
                if $0.objectID != $1.objectID { return $0.objectID.localizedStandardCompare($1.objectID) == .orderedAscending }
                return $0.action.actionID.localizedStandardCompare($1.action.actionID) == .orderedAscending
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    nonisolated private func appendBoundaryDiagnostics(
        _ failures: [CanonicalTombstoneConflictFailure],
        diagnostics: inout [CanonicalTombstoneConflictCutoverDiagnostic],
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) {
        if failures.contains(.physicalDeleteAttempted) {
            diagnostics.append(diagnostic(.canonicalTombstonePhysicalDeleteBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if failures.contains(.permanentDeleteAttempted) {
            diagnostics.append(diagnostic(.canonicalTombstonePermanentDeleteBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if failures.contains(.tombstoneGCAttempted) {
            diagnostics.append(diagnostic(.canonicalTombstoneGCBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if failures.contains(.resurrectionRiskDetected) {
            diagnostics.append(diagnostic(.canonicalTombstoneResurrectionRiskDetected, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if failures.contains(.conflictPolicyAmbiguous) {
            diagnostics.append(diagnostic(.canonicalConflictPolicyAmbiguousBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
    }

    nonisolated private func diagnostic(
        _ kind: CanonicalTombstoneConflictCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        candidate: CanonicalTombstoneConflictCandidate? = nil,
        domain: CanonicalTombstoneConflictDomain? = nil,
        objectID: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalTombstoneConflictCutoverDiagnostic {
        CanonicalTombstoneConflictCutoverDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            domain: candidate?.domain ?? domain,
            objectID: candidate?.objectID ?? objectID,
            action: candidate?.actionKind.rawValue,
            tombstoneState: candidate?.tombstoneState,
            conflictKind: candidate?.conflictKindSummary,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}

nonisolated struct CanonicalTombstoneConflictNoCommitCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { cutoverCandidate.id }
    var cutoverCandidate: CanonicalTombstoneConflictCandidate

    nonisolated init(cutoverCandidate: CanonicalTombstoneConflictCandidate) {
        self.cutoverCandidate = cutoverCandidate
    }
}

nonisolated struct CanonicalTombstoneConflictNoCommitPayloadSummary: Codable, Equatable, Sendable {
    var schema: String
    var objectID: String
    var domain: CanonicalTombstoneConflictDomain
    var actionKind: CanonicalTombstoneConflictActionKind
    var tombstoneState: CanonicalTombstoneState
    var deletedAtSummary: String
    var conflictKind: String
    var conflictPolicy: String
    var productionCommitSuppressed: Bool
    var physicalDeleteSuppressed: Bool
    var permanentDeleteSuppressed: Bool
    var tombstoneGCSuppressed: Bool
    var legacyDuplicateSuppressed: Bool
    var applySyncManifestCalled: Bool
    var networkSendSuppressed: Bool
    var receiveJSONMutationSuppressed: Bool
    var generatedArtifactDeletionSuppressed: Bool
    var audioDeletionSuppressed: Bool

    nonisolated init(candidate: CanonicalTombstoneConflictNoCommitCandidate) {
        let cutover = candidate.cutoverCandidate
        self.schema = "canonical-tombstone-conflict-no-commit-v8-11"
        self.objectID = CanonicalProductionRedaction.safeIdentifier(cutover.objectID, fallback: "tombstone-object")
        self.domain = cutover.domain
        self.actionKind = cutover.actionKind
        self.tombstoneState = cutover.tombstoneState
        self.deletedAtSummary = cutover.deletedAtSummary
        self.conflictKind = cutover.conflictKindSummary
        self.conflictPolicy = cutover.conflictPolicySummary
        self.productionCommitSuppressed = true
        self.physicalDeleteSuppressed = true
        self.permanentDeleteSuppressed = true
        self.tombstoneGCSuppressed = true
        self.legacyDuplicateSuppressed = false
        self.applySyncManifestCalled = false
        self.networkSendSuppressed = true
        self.receiveJSONMutationSuppressed = true
        self.generatedArtifactDeletionSuppressed = true
        self.audioDeletionSuppressed = true
    }

    nonisolated func encodedBytes() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

nonisolated enum CanonicalTombstoneConflictNoCommitFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case unsupportedAction
    case stagingFailed
    case productionCommitSuppressed
}

nonisolated struct CanonicalTombstoneConflictNoCommitStagingResult: Codable, Equatable, Sendable {
    var candidate: CanonicalTombstoneConflictNoCommitCandidate
    var staged: Bool
    var wroteOnlyStagingRoot: Bool
    var stagedLogicalPathToken: String?
    var payloadByteCount: Int
    var payloadHashPrefix: String?
    var objectID: String
    var domain: CanonicalTombstoneConflictDomain
    var actionKind: CanonicalTombstoneConflictActionKind
    var tombstoneState: CanonicalTombstoneState
    var deletedAtSummary: String
    var conflictKind: String
    var conflictPolicy: String
    var productionCommitSuppressed: Bool
    var physicalDeleteSuppressed: Bool
    var permanentDeleteSuppressed: Bool
    var tombstoneGCSuppressed: Bool
    var legacyDuplicateSuppressed: Bool
    var applySyncManifestCalled: Bool
    var networkSendSuppressed: Bool
    var receiveJSONMutationSuppressed: Bool
    var generatedArtifactDeletionSuppressed: Bool
    var audioDeletionSuppressed: Bool
    var stagingEvidence: CanonicalNoCommitStagingEvidence?
    var cleanupEvidence: CanonicalNoCommitCleanupEvidence?
    var failure: CanonicalTombstoneConflictNoCommitFailure?
    var reason: String

    nonisolated init(
        candidate: CanonicalTombstoneConflictNoCommitCandidate,
        staged: Bool,
        wroteOnlyStagingRoot: Bool,
        stagedLogicalPathToken: String? = nil,
        payloadByteCount: Int = 0,
        payloadHashPrefix: String? = nil,
        stagingEvidence: CanonicalNoCommitStagingEvidence? = nil,
        cleanupEvidence: CanonicalNoCommitCleanupEvidence? = nil,
        failure: CanonicalTombstoneConflictNoCommitFailure? = nil,
        reason: String
    ) {
        let cutover = candidate.cutoverCandidate
        self.candidate = candidate
        self.staged = staged
        self.wroteOnlyStagingRoot = wroteOnlyStagingRoot
        self.stagedLogicalPathToken = stagedLogicalPathToken.flatMap(CanonicalProjectionContract.safeLogicalPathToken)
        self.payloadByteCount = max(0, payloadByteCount)
        self.payloadHashPrefix = CanonicalProductionRedaction.hashPrefix(payloadHashPrefix)
        self.objectID = CanonicalProductionRedaction.safeIdentifier(cutover.objectID, fallback: "tombstone-object")
        self.domain = cutover.domain
        self.actionKind = cutover.actionKind
        self.tombstoneState = cutover.tombstoneState
        self.deletedAtSummary = cutover.deletedAtSummary
        self.conflictKind = cutover.conflictKindSummary
        self.conflictPolicy = cutover.conflictPolicySummary
        self.productionCommitSuppressed = true
        self.physicalDeleteSuppressed = true
        self.permanentDeleteSuppressed = true
        self.tombstoneGCSuppressed = true
        self.legacyDuplicateSuppressed = false
        self.applySyncManifestCalled = false
        self.networkSendSuppressed = true
        self.receiveJSONMutationSuppressed = true
        self.generatedArtifactDeletionSuppressed = true
        self.audioDeletionSuppressed = true
        self.stagingEvidence = stagingEvidence
        self.cleanupEvidence = cleanupEvidence
        self.failure = failure
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (staged ? "staged" : "blocked")
    }
}

protocol CanonicalTombstoneConflictNoCommitExecutor: Sendable {
    func stageTombstoneConflictNoCommit(
        _ candidate: CanonicalTombstoneConflictNoCommitCandidate
    ) -> CanonicalTombstoneConflictNoCommitStagingResult
}

nonisolated struct CanonicalTombstoneConflictLegacyActionIdentity: Codable, Equatable, Hashable, Sendable {
    var actionID: String?
    var syncRunID: String?
    var objectID: String
    var domain: CanonicalTombstoneConflictDomain
    var actionKind: CanonicalTombstoneConflictActionKind
    var conflictKind: String?

    nonisolated init(
        actionID: String? = nil,
        syncRunID: String? = nil,
        objectID: String,
        domain: CanonicalTombstoneConflictDomain,
        actionKind: CanonicalTombstoneConflictActionKind,
        conflictKind: String? = nil
    ) {
        self.actionID = actionID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "legacy-action") }
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "tombstone-object")
        self.domain = domain
        self.actionKind = actionKind
        self.conflictKind = CanonicalProductionRedaction.safeDiagnosticText(conflictKind)
    }
}

nonisolated enum CanonicalTombstoneConflictLegacyDuplicateSuppression {
    nonisolated static func suppressedLegacyActionIDs(
        after result: CanonicalTombstoneConflictCutoverResult,
        legacyActions: [CanonicalTombstoneConflictLegacyActionIdentity]
    ) -> [String] {
        guard result.succeeded else {
            return []
        }
        let successfulCommits = result.commits.filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
        let ids = legacyActions.compactMap { legacy -> String? in
            guard successfulCommits.contains(where: { matches(commit: $0, legacy: legacy) }) else {
                return nil
            }
            return legacy.actionID
        }
        return Array(Set(ids)).sorted()
    }

    private nonisolated static func matches(
        commit: CanonicalTombstoneConflictProductionCommitResult,
        legacy: CanonicalTombstoneConflictLegacyActionIdentity
    ) -> Bool {
        guard commit.objectID == legacy.objectID,
              commit.domain == legacy.domain,
              commit.actionKind == legacy.actionKind else {
            return false
        }
        if let conflictKind = legacy.conflictKind {
            return commit.conflictKind == conflictKind
        }
        return true
    }
}

nonisolated struct CanonicalTombstoneConflictCutoverAppSeamPolicy: Codable, Equatable, Sendable {
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int
    var canaryPolicy: CanonicalTombstoneConflictCanaryPolicy

    nonisolated init(
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 200,
        canaryPolicy: CanonicalTombstoneConflictCanaryPolicy = .disabled
    ) {
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
        self.canaryPolicy = canaryPolicy
    }
}

nonisolated struct CanonicalTombstoneConflictCutoverAppSeamConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: CanonicalCutoverAppSeamMode
    var policy: CanonicalTombstoneConflictCutoverAppSeamPolicy
    var evidence: CanonicalTombstoneConflictCutoverEvidence
    var cutoverToken: CanonicalCutoverToken?

    nonisolated init(
        isEnabled: Bool = false,
        mode: CanonicalCutoverAppSeamMode = .disabled,
        policy: CanonicalTombstoneConflictCutoverAppSeamPolicy = CanonicalTombstoneConflictCutoverAppSeamPolicy(),
        evidence: CanonicalTombstoneConflictCutoverEvidence = CanonicalTombstoneConflictCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) {
        self.isEnabled = isEnabled
        self.mode = isEnabled ? mode : .disabled
        self.policy = policy
        self.evidence = evidence
        self.cutoverToken = cutoverToken
    }

    nonisolated static let disabled = CanonicalTombstoneConflictCutoverAppSeamConfiguration()

    nonisolated static func enabled(
        mode: CanonicalCutoverAppSeamMode = .guardedExecuteCommit,
        policy: CanonicalTombstoneConflictCutoverAppSeamPolicy = CanonicalTombstoneConflictCutoverAppSeamPolicy(),
        evidence: CanonicalTombstoneConflictCutoverEvidence = CanonicalTombstoneConflictCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) -> CanonicalTombstoneConflictCutoverAppSeamConfiguration {
        CanonicalTombstoneConflictCutoverAppSeamConfiguration(
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
}

nonisolated struct CanonicalRootBoundTombstoneConflictTarget: Codable, Equatable, Hashable, Sendable {
    var rootToken: CanonicalRootToken
    var objectID: String
    var domain: CanonicalTombstoneConflictDomain
    var actionKind: CanonicalTombstoneConflictActionKind
    var logicalPathToken: String

    nonisolated init(
        rootToken: CanonicalRootToken,
        objectID: String,
        domain: CanonicalTombstoneConflictDomain,
        actionKind: CanonicalTombstoneConflictActionKind,
        logicalPathToken: String
    ) throws {
        guard let safePath = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken) else {
            throw CanonicalTombstoneConflictFailure.rootBoundWriteUnavailable
        }
        self.rootToken = rootToken
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "tombstone-object")
        self.domain = domain
        self.actionKind = actionKind
        self.logicalPathToken = safePath
    }

    nonisolated static func defaultLogicalPathToken(
        objectID: String,
        domain: CanonicalTombstoneConflictDomain,
        actionKind: CanonicalTombstoneConflictActionKind,
        conflictKind: String?
    ) -> String {
        let object = safePathComponent(objectID)
        switch actionKind {
        case .objectTombstoneApply, .objectTombstoneSend:
            return "tombstone-conflict/object-tombstones/\(object).tombstone.json"
        case .libraryTombstoneApply, .libraryTombstoneSend:
            return "tombstone-conflict/library-tombstones/\(object).tombstone.json"
        case .conflictRecord:
            return "tombstone-conflict/conflict-ledger/\(safePathComponent(domain.rawValue))/\(object)-\(safePathComponent(conflictKind ?? "conflict")).json"
        case .resurrectionBlocked:
            return "tombstone-conflict/resurrection-blocks/\(object).json"
        case .generatedArtifactTombstoneMarkUnsupported, .unsupported:
            return "tombstone-conflict/unsupported/\(object).json"
        }
    }

    private nonisolated static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        let result = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_.:"))
        return result.isEmpty ? "object-\(CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(value).value) ?? "unknown")" : String(result.prefix(96))
    }
}

nonisolated struct CanonicalRootBoundTombstoneConflictWriteResult: Codable, Equatable, Sendable {
    var objectID: String
    var domain: CanonicalTombstoneConflictDomain
    var actionKind: CanonicalTombstoneConflictActionKind
    var hashPrefixBefore: String?
    var hashPrefixAfter: String?
    var byteCount: Int
    var checkpointID: String
    var atomicWriteUsed: Bool
    var rollbackAvailable: Bool
    var physicalDeleteSuppressed: Bool
    var permanentDeleteSuppressed: Bool
    var tombstoneGCSuppressed: Bool
    var failure: CanonicalTombstoneConflictFailure?
}

nonisolated struct CanonicalRootBoundTombstoneConflictRollbackResult: Codable, Equatable, Sendable {
    var objectID: String
    var domain: CanonicalTombstoneConflictDomain
    var actionKind: CanonicalTombstoneConflictActionKind
    var checkpointID: String
    var succeeded: Bool
    var rollbackVerified: Bool
    var hashPrefixAfterRollback: String?
    var byteCount: Int?
    var failure: CanonicalTombstoneConflictFailure?
}

nonisolated struct CanonicalRootBoundTombstoneConflictWrite: Codable, Equatable, Sendable {
    var target: CanonicalRootBoundTombstoneConflictTarget
    var bytes: Data
    var contentHash: CanonicalHash
}

nonisolated struct CanonicalRootBoundTombstoneConflictCheckpoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { checkpointID }
    var checkpointID: String
    var objectID: String
    var domain: CanonicalTombstoneConflictDomain
    var actionKind: CanonicalTombstoneConflictActionKind
    var existedBeforeWrite: Bool
    var hashPrefixBefore: String?
    var byteCountBefore: Int?
}

actor CanonicalRootBoundTombstoneConflictWriteCore {
    private struct StoredCheckpoint: Sendable {
        var publicCheckpoint: CanonicalRootBoundTombstoneConflictCheckpoint
        var target: CanonicalRootBoundTombstoneConflictTarget
        var previousBytes: Data?
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let rootToken: CanonicalRootToken
    private let mode: CanonicalTombstoneConflictApplyPortMode
    private var payloadsByActionID: [String: CanonicalRootBoundTombstoneConflictWrite] = [:]
    private var checkpoints: [String: StoredCheckpoint] = [:]
    private var lastWriteByActionID: [String: CanonicalRootBoundTombstoneConflictWriteResult] = [:]
    private var lastRollbackByCheckpointID: [String: CanonicalRootBoundTombstoneConflictRollbackResult] = [:]
    private var checkpointFailureObjectIDs: Set<String> = []
    private var postconditionFailureObjectIDs: Set<String> = []
    private var rollbackFailureCheckpointIDs: Set<String> = []

    init(
        rootURL: URL,
        rootToken: CanonicalRootToken,
        mode: CanonicalTombstoneConflictApplyPortMode,
        fileManager: FileManager = .default
    ) throws {
        guard rootURL.isFileURL else {
            throw CanonicalTombstoneConflictFailure.rootBoundWriteUnavailable
        }
        self.fileManager = fileManager
        self.rootURL = rootURL.standardizedFileURL
        self.rootToken = rootToken
        self.mode = mode
    }

    func setPayload(
        candidate: CanonicalTombstoneConflictCandidate,
        bytes: Data? = nil,
        logicalPathToken: String? = nil
    ) throws {
        let target = try CanonicalRootBoundTombstoneConflictTarget(
            rootToken: rootToken,
            objectID: candidate.objectID,
            domain: candidate.domain,
            actionKind: candidate.actionKind,
            logicalPathToken: logicalPathToken ?? CanonicalRootBoundTombstoneConflictTarget.defaultLogicalPathToken(
                objectID: candidate.objectID,
                domain: candidate.domain,
                actionKind: candidate.actionKind,
                conflictKind: candidate.conflictKindSummary
            )
        )
        let payloadBytes = bytes ?? candidate.markerBytes
        let write = CanonicalRootBoundTombstoneConflictWrite(
            target: target,
            bytes: payloadBytes,
            contentHash: CanonicalTransportEnvelope.hash(payloadBytes)
        )
        payloadsByActionID[CanonicalProductionRedaction.safeIdentifier(candidate.action.actionID, fallback: candidate.actionKind.rawValue)] = write
    }

    func injectCheckpointFailure(objectID: String) {
        checkpointFailureObjectIDs.insert(CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "tombstone-object"))
    }

    func injectPostconditionFailure(objectID: String) {
        postconditionFailureObjectIDs.insert(CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "tombstone-object"))
    }

    func injectRollbackFailure(checkpointID: String) {
        rollbackFailureCheckpointIDs.insert(CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "tombstone-conflict-checkpoint"))
    }

    func write(action: CanonicalApplyAction, checkpointID: String?) throws -> CanonicalRootBoundTombstoneConflictWriteResult {
        try requireWritableMode()
        let actionID = CanonicalProductionRedaction.safeIdentifier(action.actionID, fallback: "tombstone-action")
        guard let payload = payloadsByActionID[actionID] else {
            throw CanonicalTombstoneConflictFailure.applyFailureBeforeCommit
        }
        guard !checkpointFailureObjectIDs.contains(payload.target.objectID) else {
            throw CanonicalTombstoneConflictFailure.applyFailureBeforeCommit
        }
        let effectiveCheckpointID = CanonicalProductionRedaction.safeIdentifier(
            checkpointID ?? "root-bound-tombstone-conflict-\(payload.target.objectID)-\(payload.target.actionKind.rawValue)",
            fallback: "tombstone-conflict-checkpoint"
        )
        let targetURL = try resolvedURL(for: payload.target)
        let previousBytes = fileManager.fileExists(atPath: targetURL.path) ? try Data(contentsOf: targetURL) : nil
        let previousHash = previousBytes.map(CanonicalTransportEnvelope.hash)
        checkpoints[effectiveCheckpointID] = StoredCheckpoint(
            publicCheckpoint: CanonicalRootBoundTombstoneConflictCheckpoint(
                checkpointID: effectiveCheckpointID,
                objectID: payload.target.objectID,
                domain: payload.target.domain,
                actionKind: payload.target.actionKind,
                existedBeforeWrite: previousBytes != nil,
                hashPrefixBefore: previousHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) },
                byteCountBefore: previousBytes?.count
            ),
            target: payload.target,
            previousBytes: previousBytes
        )
        do {
            try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.bytes.write(to: targetURL, options: [.atomic])
            let reread = try Data(contentsOf: targetURL)
            guard !postconditionFailureObjectIDs.contains(payload.target.objectID),
                  reread == payload.bytes,
                  CanonicalTransportEnvelope.hash(reread) == payload.contentHash else {
                try restore(checkpointID: effectiveCheckpointID)
                throw CanonicalTombstoneConflictFailure.postconditionMismatch
            }
            let afterHash = CanonicalTransportEnvelope.hash(reread)
            let result = CanonicalRootBoundTombstoneConflictWriteResult(
                objectID: payload.target.objectID,
                domain: payload.target.domain,
                actionKind: payload.target.actionKind,
                hashPrefixBefore: previousHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) },
                hashPrefixAfter: CanonicalProductionRedaction.hashPrefix(afterHash.value),
                byteCount: reread.count,
                checkpointID: effectiveCheckpointID,
                atomicWriteUsed: true,
                rollbackAvailable: true,
                physicalDeleteSuppressed: true,
                permanentDeleteSuppressed: true,
                tombstoneGCSuppressed: true,
                failure: nil
            )
            lastWriteByActionID[actionID] = result
            return result
        } catch let failure as CanonicalTombstoneConflictFailure {
            throw failure
        } catch {
            try? restore(checkpointID: effectiveCheckpointID)
            throw CanonicalTombstoneConflictFailure.applyFailureBeforeCommit
        }
    }

    func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) -> CanonicalProductionApplyPostcondition {
        var checked = postcondition
        let objectID = CanonicalProductionRedaction.safeIdentifier(postcondition.target.objectID, fallback: "tombstone-object")
        if postconditionFailureObjectIDs.contains(objectID) {
            checked.accepted = false
            checked.reason = CanonicalTombstoneConflictFailure.postconditionMismatch.rawValue
            return checked
        }
        guard lastWriteByActionID[postcondition.actionID] != nil else {
            checked.accepted = false
            checked.reason = "tombstoneConflictWriteMissing"
            return checked
        }
        checked.accepted = true
        return checked
    }

    func rollback(_ request: CanonicalRollbackAction) -> CanonicalRootBoundTombstoneConflictRollbackResult {
        let checkpointID = CanonicalProductionRedaction.safeIdentifier(request.checkpointID ?? request.actionID, fallback: "tombstone-conflict-checkpoint")
        guard let stored = checkpoints[checkpointID] else {
            return CanonicalRootBoundTombstoneConflictRollbackResult(
                objectID: request.objectID ?? "tombstone-object",
                domain: request.domain == .conflicts ? .metadataConflictRecord : .objectTombstone,
                actionKind: request.kind == .conflictLedgerNoOp ? .conflictRecord : .objectTombstoneApply,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                hashPrefixAfterRollback: nil,
                byteCount: nil,
                failure: .rollbackFailure
            )
        }
        if rollbackFailureCheckpointIDs.contains(checkpointID) {
            return CanonicalRootBoundTombstoneConflictRollbackResult(
                objectID: stored.target.objectID,
                domain: stored.target.domain,
                actionKind: stored.target.actionKind,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                hashPrefixAfterRollback: nil,
                byteCount: nil,
                failure: .rollbackFailure
            )
        }
        do {
            try restore(checkpointID: checkpointID)
            let targetURL = try resolvedURL(for: stored.target)
            let currentBytes = fileManager.fileExists(atPath: targetURL.path) ? try Data(contentsOf: targetURL) : nil
            let verified = currentBytes == stored.previousBytes
            let result = CanonicalRootBoundTombstoneConflictRollbackResult(
                objectID: stored.target.objectID,
                domain: stored.target.domain,
                actionKind: stored.target.actionKind,
                checkpointID: checkpointID,
                succeeded: verified,
                rollbackVerified: verified,
                hashPrefixAfterRollback: currentBytes.map { CanonicalProductionRedaction.hashPrefix(CanonicalTransportEnvelope.hash($0).value) } ?? nil,
                byteCount: currentBytes?.count,
                failure: verified ? nil : .rollbackFailure
            )
            lastRollbackByCheckpointID[checkpointID] = result
            if verified {
                checkpoints.removeValue(forKey: checkpointID)
            }
            return result
        } catch {
            let result = CanonicalRootBoundTombstoneConflictRollbackResult(
                objectID: stored.target.objectID,
                domain: stored.target.domain,
                actionKind: stored.target.actionKind,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                hashPrefixAfterRollback: nil,
                byteCount: nil,
                failure: .rollbackFailure
            )
            lastRollbackByCheckpointID[checkpointID] = result
            return result
        }
    }

    func lastWriteResult(actionID: String) -> CanonicalRootBoundTombstoneConflictWriteResult? {
        lastWriteByActionID[CanonicalProductionRedaction.safeIdentifier(actionID, fallback: "tombstone-action")]
    }

    func lastRollbackResult(checkpointID: String) -> CanonicalRootBoundTombstoneConflictRollbackResult? {
        lastRollbackByCheckpointID[CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "tombstone-conflict-checkpoint")]
    }

    func readBytes(actionID: String) throws -> Data? {
        let actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: "tombstone-action")
        guard let payload = payloadsByActionID[actionID] else {
            return nil
        }
        let targetURL = try resolvedURL(for: payload.target)
        guard fileManager.fileExists(atPath: targetURL.path) else {
            return nil
        }
        return try Data(contentsOf: targetURL)
    }

    private func requireWritableMode() throws {
        guard mode.isNonDryRunRootBound else {
            throw CanonicalTombstoneConflictFailure.applyPortDryRunOnly
        }
    }

    private func resolvedURL(for target: CanonicalRootBoundTombstoneConflictTarget) throws -> URL {
        guard target.rootToken == rootToken else {
            throw CanonicalTombstoneConflictFailure.rootBoundWriteUnavailable
        }
        let url = rootURL.appendingPathComponent(target.logicalPathToken, isDirectory: false).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        guard url.path.hasPrefix(rootPath) else {
            throw CanonicalTombstoneConflictFailure.rootBoundWriteUnavailable
        }
        return url
    }

    private func restore(checkpointID: String) throws {
        guard let stored = checkpoints[checkpointID] else {
            throw CanonicalTombstoneConflictFailure.rollbackFailure
        }
        let targetURL = try resolvedURL(for: stored.target)
        if let previousBytes = stored.previousBytes {
            try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try previousBytes.write(to: targetURL, options: [.atomic])
        } else if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
    }
}

nonisolated enum CanonicalTombstoneConflictCanaryMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case n1

    nonisolated var isExecutable: Bool { self == .n1 }
}

nonisolated struct CanonicalTombstoneConflictCanaryConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalTombstoneConflictCanaryMode
    var domain: CanonicalMigrationDomain
    var canaryMaxObjectsPerSyncRun: Int
    var explicitInternalTestConfiguration: Bool
    var productionTokenRequired: Bool
    var ownerApprovalRequired: Bool
    var rollbackPlanRequired: Bool
    var runtimeSwitchEnabled: Bool
    var allowAllEligible: Bool
    var releaseDefaultEnabled: Bool

    nonisolated init(
        mode: CanonicalTombstoneConflictCanaryMode = .disabled,
        domain: CanonicalMigrationDomain = .tombstoneConflict,
        canaryMaxObjectsPerSyncRun: Int = 0,
        explicitInternalTestConfiguration: Bool = false,
        productionTokenRequired: Bool = true,
        ownerApprovalRequired: Bool = true,
        rollbackPlanRequired: Bool = true,
        runtimeSwitchEnabled: Bool = false,
        allowAllEligible: Bool = false,
        releaseDefaultEnabled: Bool = false
    ) {
        self.mode = mode
        self.domain = domain
        self.canaryMaxObjectsPerSyncRun = max(0, canaryMaxObjectsPerSyncRun)
        self.explicitInternalTestConfiguration = explicitInternalTestConfiguration
        self.productionTokenRequired = productionTokenRequired
        self.ownerApprovalRequired = ownerApprovalRequired
        self.rollbackPlanRequired = rollbackPlanRequired
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.allowAllEligible = allowAllEligible
        self.releaseDefaultEnabled = releaseDefaultEnabled
    }

    nonisolated static let disabled = CanonicalTombstoneConflictCanaryConfiguration()

    nonisolated static func internalN1(
        explicitInternalTestConfiguration: Bool = true
    ) -> CanonicalTombstoneConflictCanaryConfiguration {
        CanonicalTombstoneConflictCanaryConfiguration(
            mode: .n1,
            canaryMaxObjectsPerSyncRun: 1,
            explicitInternalTestConfiguration: explicitInternalTestConfiguration
        )
    }

    nonisolated init(appSeamConfiguration configuration: CanonicalTombstoneConflictCutoverAppSeamConfiguration) {
        let policy = configuration.policy.canaryPolicy
        let n1Requested = configuration.isEnabled
            && configuration.effectiveMode == .canaryCommit
            && policy.canaryMaxObjectsPerSyncRun == 1
        self.init(
            mode: n1Requested ? .n1 : .disabled,
            domain: .tombstoneConflict,
            canaryMaxObjectsPerSyncRun: policy.canaryMaxObjectsPerSyncRun,
            explicitInternalTestConfiguration: policy.explicitInternalTestConfiguration,
            runtimeSwitchEnabled: policy.runtimeSwitchEnabled,
            allowAllEligible: policy.allowAllEligible || policy.requestedStage == .allEligible,
            releaseDefaultEnabled: false
        )
    }

    nonisolated var strictN1Enabled: Bool {
        mode == .n1
            && domain == .tombstoneConflict
            && canaryMaxObjectsPerSyncRun == 1
            && explicitInternalTestConfiguration
            && !runtimeSwitchEnabled
            && !allowAllEligible
            && !releaseDefaultEnabled
    }
}

nonisolated enum CanonicalTombstoneConflictCanaryCandidateBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedMode
    case canaryBudgetZero
    case missingInternalCanaryConfiguration
    case canaryBudgetAboveOneDenied
    case allEligibleDenied
    case runtimeSwitchDenied
    case defaultEnablementDenied
    case unsupportedDomain
    case unsupportedAction
    case unsupportedTrigger
    case missingToken
    case missingOwnerApproval
    case matrixBlocked
    case activePilotNotTombstoneConflict
    case peerSnapshotUnavailable
    case localSnapshotUnavailable
    case commitExecutorUnavailable
    case missingNoCommitEvidence
    case missingDryRunEquivalence
    case missingExecutionShadowEvidence
    case missingRealDataShadowCopyEvidence
    case blockingDivergence
    case unresolvedConflict
    case missingMetadataRouteEvidence
    case productionPortUnavailable
    case realApplyPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case missingRollback
    case rollbackVerificationMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case legacyFallbackUnavailable
    case readSideParallelMissing
    case failureInjectionMissing
    case antiResurrectionEvidenceMissing
    case physicalDeleteGuardMissing
    case permanentDeleteGuardMissing
    case tombstoneGCGuardMissing
    case duplicateSuppressionPolicyMissing
    case physicalDeleteCandidate
    case permanentDeleteCandidate
    case tombstoneGCCandidate
    case clearTombstoneCandidate
    case restoreWithoutExplicitSignal
    case ambiguousConflictAutoResolution
    case staleLiveResurrection
    case generatedArtifactApplyOnTombstonedParent
    case audioRelatedAction
    case fullContentMutation
    case unsafePathToken
    case missingRollbackCheckpoint
    case unsupportedObjectKind
    case conflictPolicyAmbiguous
    case tombstoneTimestampMissing
    case objectIDInstability
    case parentMissing
    case irreversibleDeleteAction
    case noEligibleCandidate
}

typealias CanonicalTombstoneConflictCanaryBlocker = CanonicalTombstoneConflictCanaryCandidateBlocker

nonisolated enum CanonicalTombstoneConflictCanaryCandidateSafetyKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case objectSoftTombstoneMarker
    case librarySoftTombstoneMarker
    case conflictRecord
    case resurrectionBlockRecord
    case generatedArtifactTombstoneReportOnly
    case blocked
}

nonisolated struct CanonicalTombstoneConflictCanaryCandidateSafety: Codable, Equatable, Sendable {
    var candidate: CanonicalTombstoneConflictCandidate
    var safe: Bool
    var executable: Bool
    var kind: CanonicalTombstoneConflictCanaryCandidateSafetyKind
    var blockers: [CanonicalTombstoneConflictCanaryCandidateBlocker]
    var safetySummary: String
    var physicalDeletePerformed: Bool
    var permanentDeletePerformed: Bool
    var tombstoneGCPerformed: Bool
    var restorePerformed: Bool
    var tombstoneCleared: Bool
    var autoResolvedConflict: Bool
    var staleLiveResurrectionAllowed: Bool
    var generatedArtifactApplyOrDownloadAllowed: Bool
    var audioActionAllowed: Bool

    nonisolated init(
        candidate: CanonicalTombstoneConflictCandidate,
        evidence: CanonicalTombstoneConflictCutoverEvidence
    ) {
        let blockers = CanonicalTombstoneConflictCanaryCandidateSelector.candidateBlockers(candidate, evidence: evidence)
        self.candidate = candidate
        self.blockers = blockers
        self.kind = Self.kind(for: candidate, blockers: blockers)
        self.safe = blockers.isEmpty && kind != .blocked
        self.executable = self.safe && candidate.actionKind.isExecutable
        self.physicalDeletePerformed = false
        self.permanentDeletePerformed = false
        self.tombstoneGCPerformed = false
        self.restorePerformed = false
        self.tombstoneCleared = false
        self.autoResolvedConflict = false
        self.staleLiveResurrectionAllowed = false
        self.generatedArtifactApplyOrDownloadAllowed = false
        self.audioActionAllowed = false
        self.safetySummary = [
            "kind=\(kind.rawValue)",
            "safe=\(safe)",
            "executable=\(executable)",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "+"))",
            "physicalDelete=false",
            "permanentDelete=false",
            "tombstoneGC=false",
            "restore=false",
            "clearTombstone=false",
            "autoResolve=false",
            "staleLiveResurrection=false"
        ].joined(separator: ",")
    }

    private nonisolated static func kind(
        for candidate: CanonicalTombstoneConflictCandidate,
        blockers: [CanonicalTombstoneConflictCanaryCandidateBlocker]
    ) -> CanonicalTombstoneConflictCanaryCandidateSafetyKind {
        guard blockers.isEmpty else { return .blocked }
        switch candidate.actionKind {
        case .objectTombstoneApply, .objectTombstoneSend:
            return .objectSoftTombstoneMarker
        case .libraryTombstoneApply, .libraryTombstoneSend:
            return .librarySoftTombstoneMarker
        case .conflictRecord:
            return .conflictRecord
        case .resurrectionBlocked:
            return .resurrectionBlockRecord
        case .generatedArtifactTombstoneMarkUnsupported:
            return .generatedArtifactTombstoneReportOnly
        case .unsupported:
            return .blocked
        }
    }
}

nonisolated struct CanonicalTombstoneConflictCanarySelectionBlocker: Codable, Equatable, Identifiable, Sendable {
    var id: String { [objectID ?? "run", actionKind ?? "none", reason.rawValue].joined(separator: "|") }

    var objectID: String?
    var actionKind: String?
    var reason: CanonicalTombstoneConflictCanaryCandidateBlocker

    nonisolated init(
        objectID: String?,
        actionKind: CanonicalTombstoneConflictActionKind?,
        reason: CanonicalTombstoneConflictCanaryCandidateBlocker
    ) {
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "tombstone-object") }
        self.actionKind = actionKind?.rawValue
        self.reason = reason
    }
}

nonisolated struct CanonicalTombstoneConflictCanarySelectionResult: Codable, Equatable, Sendable {
    var selectedCandidates: [CanonicalTombstoneConflictCandidate]
    var blockers: [CanonicalTombstoneConflictCanarySelectionBlocker]
    var safetyReports: [CanonicalTombstoneConflictCanaryCandidateSafety]
    var evaluatedCandidateCount: Int
    var reportOnlyCandidateCount: Int
    var noEligibleCandidate: Bool
}

nonisolated struct CanonicalTombstoneConflictCanaryCandidateSelector: Sendable {
    nonisolated init() {}

    nonisolated func select(
        mode: CanonicalCutoverMode,
        policy: CanonicalTombstoneConflictCanaryPolicy,
        trigger: CanonicalSyncPlanTrigger,
        evidence: CanonicalTombstoneConflictCutoverEvidence,
        candidates: [CanonicalTombstoneConflictCandidate]
    ) -> CanonicalTombstoneConflictCanarySelectionResult {
        var blockers: [CanonicalTombstoneConflictCanarySelectionBlocker] = []
        if mode == .disabled {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .disabled))
        }
        if mode != .canary {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .unsupportedMode))
        }
        if policy.canaryMaxObjectsPerSyncRun == 0 {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .canaryBudgetZero))
        }
        if policy.canaryMaxObjectsPerSyncRun > 1 {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .canaryBudgetAboveOneDenied))
        }
        if policy.canaryMaxObjectsPerSyncRun == 1,
           (!policy.allowCandidateExecution || !policy.allowsInternalN1Execution || !policy.explicitInternalTestConfiguration) {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .missingInternalCanaryConfiguration))
        }
        if policy.requestedStage == .allEligible || policy.allowAllEligible {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .allEligibleDenied))
        } else if policy.requestedStage.isExecutable && policy.requestedStage != .n1 {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .canaryBudgetAboveOneDenied))
        }
        if policy.runtimeSwitchEnabled {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .runtimeSwitchDenied))
        }
        if trigger == .viewRefresh || trigger == .retryDrainer {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .unsupportedTrigger))
        }

        let runBlocked = !blockers.isEmpty
        let safetyReports = candidates.map {
            CanonicalTombstoneConflictCanaryCandidateSafety(candidate: $0, evidence: evidence)
        }
        let orderedReports = safetyReports.sorted { lhs, rhs in
            let lhsPriority = Self.selectionPriority(lhs.candidate)
            let rhsPriority = Self.selectionPriority(rhs.candidate)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if lhs.candidate.objectID != rhs.candidate.objectID {
                return lhs.candidate.objectID.localizedStandardCompare(rhs.candidate.objectID) == .orderedAscending
            }
            if lhs.candidate.actionKind.rawValue != rhs.candidate.actionKind.rawValue {
                return lhs.candidate.actionKind.rawValue < rhs.candidate.actionKind.rawValue
            }
            return lhs.candidate.action.actionID.localizedStandardCompare(rhs.candidate.action.actionID) == .orderedAscending
        }
        var selected: [CanonicalTombstoneConflictCandidate] = []
        for report in orderedReports {
            if report.executable, !runBlocked, selected.isEmpty {
                selected.append(report.candidate)
            }
            blockers.append(contentsOf: report.blockers.map {
                CanonicalTombstoneConflictCanarySelectionBlocker(
                    objectID: report.candidate.objectID,
                    actionKind: report.candidate.actionKind,
                    reason: $0
                )
            })
        }
        if selected.isEmpty, candidates.isEmpty {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .noEligibleCandidate))
        }
        let reportOnlyCount = safetyReports.filter { $0.kind == .generatedArtifactTombstoneReportOnly }.count
        return CanonicalTombstoneConflictCanarySelectionResult(
            selectedCandidates: selected,
            blockers: blockers,
            safetyReports: safetyReports,
            evaluatedCandidateCount: candidates.count,
            reportOnlyCandidateCount: reportOnlyCount,
            noEligibleCandidate: selected.isEmpty
        )
    }

    nonisolated static func candidateBlockers(
        _ candidate: CanonicalTombstoneConflictCandidate,
        evidence: CanonicalTombstoneConflictCutoverEvidence
    ) -> [CanonicalTombstoneConflictCanaryCandidateBlocker] {
        var blockers: [CanonicalTombstoneConflictCanaryCandidateBlocker] = []
        let reason = candidate.action.reason.lowercased()
        if candidate.actionKind == .unsupported {
            blockers.append(.unsupportedAction)
        }
        if candidate.actionKind == .generatedArtifactTombstoneMarkUnsupported {
            return []
        }
        if !candidate.actionKind.isExecutable {
            blockers.append(.unsupportedAction)
        }
        if candidate.action.target.objectID.isEmpty {
            blockers.append(.unsupportedObjectKind)
        }
        if candidate.actionKind.isTombstoneMarkerWrite && candidate.deletedAt == nil {
            blockers.append(.tombstoneTimestampMissing)
        }
        if candidate.actionKind.isTombstoneMarkerWrite && !candidate.tombstoneWinsIfNewerPolicy {
            blockers.append(.missingRollbackCheckpoint)
        }
        if candidate.actionKind.isExecutable && (!candidate.rollbackEvidenceAvailable || candidate.rollbackCheckpointID == nil || !evidence.rollbackCheckpointAvailable) {
            blockers.append(.missingRollbackCheckpoint)
        }
        if candidate.routePath != "/sync/apply-metadata" {
            blockers.append(.unsafePathToken)
        }
        if !candidate.conflictPolicyKnown {
            blockers.append(.conflictPolicyAmbiguous)
            blockers.append(.ambiguousConflictAutoResolution)
        }
        if candidate.wouldRestoreFromAbsenceOnly || (!candidate.explicitRestoreSignal && reason.contains("restore")) {
            blockers.append(.restoreWithoutExplicitSignal)
        }
        if candidate.explicitRestoreSignal {
            blockers.append(.restoreWithoutExplicitSignal)
        }
        if candidate.staleLiveMetadataRisk && candidate.actionKind != .resurrectionBlocked {
            blockers.append(.staleLiveResurrection)
        }
        if !reason.contains("no") && reason.contains("physicaldelete") {
            blockers.append(.physicalDeleteCandidate)
        }
        if reason.contains("permanentdelete") {
            blockers.append(.permanentDeleteCandidate)
        }
        if reason.contains("tombstonegc") {
            blockers.append(.tombstoneGCCandidate)
        }
        if reason.contains("cleartombstone") || reason.contains("tombstoneclear") {
            blockers.append(.clearTombstoneCandidate)
        }
        if reason.contains("artifactapply") || reason.contains("artifactdownload") {
            blockers.append(.generatedArtifactApplyOnTombstonedParent)
        }
        if reason.contains("audio") {
            blockers.append(.audioRelatedAction)
        }
        if reason.contains("fullcontent") || reason.contains("contentmutation") {
            blockers.append(.fullContentMutation)
        }
        if reason.contains("unsafepath") {
            blockers.append(.unsafePathToken)
        }
        if reason.contains("objectidinstability") {
            blockers.append(.objectIDInstability)
        }
        if reason.contains("parentmissing") {
            blockers.append(.parentMissing)
        }
        if reason.contains("irreversible") {
            blockers.append(.irreversibleDeleteAction)
        }
        return Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated static func selectionPriority(_ candidate: CanonicalTombstoneConflictCandidate) -> Int {
        switch candidate.actionKind {
        case .conflictRecord:
            return 0
        case .resurrectionBlocked:
            return 1
        case .objectTombstoneApply, .objectTombstoneSend, .libraryTombstoneApply, .libraryTombstoneSend:
            return 2
        case .generatedArtifactTombstoneMarkUnsupported:
            return 3
        case .unsupported:
            return 99
        }
    }
}

nonisolated enum CanonicalTombstoneConflictCanaryObservationStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case blocked
    case noEligibleCandidate
    case reportOnly
    case committed
    case failedRolledBack
    case fatalRollbackFailure
}

nonisolated enum CanonicalTombstoneConflictCanaryObservationNextStageRecommendation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case remainN1
    case readyForN3AfterAudit
    case fixBlockers
    case stayDisabled
}

nonisolated struct CanonicalTombstoneConflictCanaryObservationReport: Codable, Equatable, Sendable {
    var status: CanonicalTombstoneConflictCanaryObservationStatus
    var canaryBudget: Int
    var selectedCandidateCount: Int
    var executedCandidateCount: Int
    var successCount: Int
    var failureCount: Int
    var rollbackCount: Int
    var rollbackFailureCount: Int
    var legacyFallbackCount: Int
    var duplicateSuppressionCount: Int
    var unsafeCandidateSkippedCount: Int
    var noEligibleCandidateCount: Int
    var fatalBlockerCount: Int
    var antiResurrectionBlockCount: Int
    var physicalDeleteRiskCount: Int
    var permanentDeleteRiskCount: Int
    var tombstoneGCRiskCount: Int
    var autoConflictResolutionRiskCount: Int
    var staleLiveResurrectionRiskCount: Int
    var readSideEquivalentCount: Int
    var readSideDivergentCount: Int
    var uiMutated: Bool
    var physicalDeletePerformed: Bool
    var permanentDeletePerformed: Bool
    var tombstoneGCPerformed: Bool
    var runtimeSwitch: Bool
    var domain: CanonicalMigrationDomain
    var nextStageRecommendation: CanonicalTombstoneConflictCanaryObservationNextStageRecommendation
    var diagnosticsSummary: String

    nonisolated init(
        status: CanonicalTombstoneConflictCanaryObservationStatus,
        canaryBudget: Int,
        selectedCandidateCount: Int = 0,
        executedCandidateCount: Int = 0,
        successCount: Int = 0,
        failureCount: Int = 0,
        rollbackCount: Int = 0,
        rollbackFailureCount: Int = 0,
        legacyFallbackCount: Int = 0,
        duplicateSuppressionCount: Int = 0,
        unsafeCandidateSkippedCount: Int = 0,
        noEligibleCandidateCount: Int = 0,
        fatalBlockerCount: Int = 0,
        antiResurrectionBlockCount: Int = 0,
        physicalDeleteRiskCount: Int = 0,
        permanentDeleteRiskCount: Int = 0,
        tombstoneGCRiskCount: Int = 0,
        autoConflictResolutionRiskCount: Int = 0,
        staleLiveResurrectionRiskCount: Int = 0,
        readSideEquivalentCount: Int = 0,
        readSideDivergentCount: Int = 0,
        runtimeSwitch: Bool = false,
        nextStageRecommendation: CanonicalTombstoneConflictCanaryObservationNextStageRecommendation? = nil
    ) {
        self.status = status
        self.canaryBudget = max(0, canaryBudget)
        self.selectedCandidateCount = max(0, selectedCandidateCount)
        self.executedCandidateCount = max(0, executedCandidateCount)
        self.successCount = max(0, successCount)
        self.failureCount = max(0, failureCount)
        self.rollbackCount = max(0, rollbackCount)
        self.rollbackFailureCount = max(0, rollbackFailureCount)
        self.legacyFallbackCount = max(0, legacyFallbackCount)
        self.duplicateSuppressionCount = max(0, duplicateSuppressionCount)
        self.unsafeCandidateSkippedCount = max(0, unsafeCandidateSkippedCount)
        self.noEligibleCandidateCount = max(0, noEligibleCandidateCount)
        self.fatalBlockerCount = max(0, fatalBlockerCount)
        self.antiResurrectionBlockCount = max(0, antiResurrectionBlockCount)
        self.physicalDeleteRiskCount = max(0, physicalDeleteRiskCount)
        self.permanentDeleteRiskCount = max(0, permanentDeleteRiskCount)
        self.tombstoneGCRiskCount = max(0, tombstoneGCRiskCount)
        self.autoConflictResolutionRiskCount = max(0, autoConflictResolutionRiskCount)
        self.staleLiveResurrectionRiskCount = max(0, staleLiveResurrectionRiskCount)
        self.readSideEquivalentCount = max(0, readSideEquivalentCount)
        self.readSideDivergentCount = max(0, readSideDivergentCount)
        self.uiMutated = false
        self.physicalDeletePerformed = false
        self.permanentDeletePerformed = false
        self.tombstoneGCPerformed = false
        self.runtimeSwitch = runtimeSwitch
        self.domain = .tombstoneConflict
        self.nextStageRecommendation = nextStageRecommendation ?? Self.defaultRecommendation(status: status, successCount: successCount)
        self.diagnosticsSummary = [
            "status=\(status.rawValue)",
            "domain=tombstoneConflict",
            "canaryBudget=\(self.canaryBudget)",
            "selected=\(self.selectedCandidateCount)",
            "executed=\(self.executedCandidateCount)",
            "success=\(self.successCount)",
            "failure=\(self.failureCount)",
            "rollback=\(self.rollbackCount)",
            "rollbackFailure=\(self.rollbackFailureCount)",
            "fallback=\(self.legacyFallbackCount)",
            "duplicateSuppression=\(self.duplicateSuppressionCount)",
            "unsafeSkipped=\(self.unsafeCandidateSkippedCount)",
            "noEligible=\(self.noEligibleCandidateCount)",
            "fatal=\(self.fatalBlockerCount)",
            "antiResurrection=\(self.antiResurrectionBlockCount)",
            "physicalDeleteRisk=\(self.physicalDeleteRiskCount)",
            "permanentDeleteRisk=\(self.permanentDeleteRiskCount)",
            "tombstoneGCRisk=\(self.tombstoneGCRiskCount)",
            "autoConflictResolutionRisk=\(self.autoConflictResolutionRiskCount)",
            "staleLiveRisk=\(self.staleLiveResurrectionRiskCount)",
            "readSideEquivalent=\(self.readSideEquivalentCount)",
            "readSideDivergent=\(self.readSideDivergentCount)",
            "uiMutated=false",
            "physicalDeletePerformed=false",
            "permanentDeletePerformed=false",
            "tombstoneGCPerformed=false",
            "runtimeSwitch=\(runtimeSwitch)",
            "nextStage=\(self.nextStageRecommendation.rawValue)"
        ].joined(separator: ",")
    }

    private nonisolated static func defaultRecommendation(
        status: CanonicalTombstoneConflictCanaryObservationStatus,
        successCount: Int
    ) -> CanonicalTombstoneConflictCanaryObservationNextStageRecommendation {
        switch status {
        case .committed where successCount == 1:
            return .remainN1
        case .blocked, .failedRolledBack, .fatalRollbackFailure:
            return .fixBlockers
        case .disabled:
            return .stayDisabled
        case .noEligibleCandidate, .reportOnly, .committed:
            return .remainN1
        }
    }
}

typealias CanonicalTombstoneConflictCanaryBlockerReport = CanonicalTombstoneConflictCanaryObservationReport

nonisolated struct CanonicalTombstoneConflictCanaryResult: Codable, Equatable, Sendable {
    var configuration: CanonicalTombstoneConflictCanaryConfiguration
    var cutoverResult: CanonicalTombstoneConflictCutoverResult
    var selection: CanonicalTombstoneConflictCanarySelectionResult
    var observationReport: CanonicalTombstoneConflictCanaryObservationReport

    nonisolated var succeeded: Bool {
        cutoverResult.succeeded && observationReport.successCount == 1
    }
}

nonisolated struct CanonicalTombstoneConflictN1CanaryRunner: Sendable {
    nonisolated init() {}

    nonisolated func run(
        configuration: CanonicalTombstoneConflictCanaryConfiguration,
        policy: CanonicalTombstoneConflictCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalTombstoneConflictCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix = .v827TombstoneConflictActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            generatedArtifactsTemplateCompleteOrObservationReady: true
        ),
        candidates: [CanonicalTombstoneConflictCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        localSnapshotAvailable: Bool = true,
        peerSnapshotAvailable: Bool = true,
        failureInjectionAvailable: Bool = true,
        antiResurrectionEvidenceAvailable: Bool = true,
        physicalDeleteGuardPassed: Bool = true,
        permanentDeleteGuardPassed: Bool = true,
        tombstoneGCGuardPassed: Bool = true,
        duplicateSuppressionPolicyAvailable: Bool = true,
        executor: (any CanonicalTombstoneConflictCutoverExecutor)?
    ) async -> CanonicalTombstoneConflictCanaryResult {
        let strictBlockers = Self.strictConfigurationBlockers(
            configuration: configuration,
            policy: policy,
            token: token,
            evidence: evidence,
            matrix: matrix,
            trigger: trigger,
            localSnapshotAvailable: localSnapshotAvailable,
            peerSnapshotAvailable: peerSnapshotAvailable,
            failureInjectionAvailable: failureInjectionAvailable,
            antiResurrectionEvidenceAvailable: antiResurrectionEvidenceAvailable,
            physicalDeleteGuardPassed: physicalDeleteGuardPassed,
            permanentDeleteGuardPassed: permanentDeleteGuardPassed,
            tombstoneGCGuardPassed: tombstoneGCGuardPassed,
            duplicateSuppressionPolicyAvailable: duplicateSuppressionPolicyAvailable,
            executorAvailable: executor != nil
        )
        var diagnostics = Self.initialDiagnostics(
            configuration: configuration,
            policy: policy,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            candidateCount: candidates.count,
            blockers: strictBlockers
        )
        let selectorPolicy = CanonicalTombstoneConflictCanaryPolicy(
            canaryMaxObjectsPerSyncRun: 1,
            allowCandidateExecution: true,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true
        )
        var selection = CanonicalTombstoneConflictCanaryCandidateSelector().select(
            mode: .canary,
            policy: selectorPolicy,
            trigger: trigger,
            evidence: evidence,
            candidates: candidates
        )
        if !strictBlockers.isEmpty {
            selection = Self.selectionBlockedByRunBlockers(
                selection,
                blockers: strictBlockers,
                evaluatedCandidateCount: candidates.count
            )
        }
        diagnostics.append(contentsOf: Self.selectionDiagnostics(
            selection: selection,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole
        ))
        diagnostics.append(contentsOf: Self.boundaryDiagnostics(
            blockers: selection.blockers.map(\.reason) + strictBlockers,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole
        ))

        guard strictBlockers.isEmpty else {
            return Self.blockedResult(
                configuration: configuration,
                selection: selection,
                diagnostics: diagnostics,
                blockers: strictBlockers,
                evidence: evidence,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                status: .blocked,
                reason: strictBlockers.map(\.rawValue).joined(separator: ",")
            )
        }
        guard let selected = selection.selectedCandidates.first else {
            return Self.blockedResult(
                configuration: configuration,
                selection: selection,
                diagnostics: diagnostics,
                blockers: selection.noEligibleCandidate ? [.noEligibleCandidate] : [],
                evidence: evidence,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                status: selection.reportOnlyCandidateCount > 0 ? .reportOnly : .noEligibleCandidate,
                reason: selection.reportOnlyCandidateCount > 0 ? "reportOnlyNoExecution" : "noEligibleCandidate"
            )
        }
        guard let executor else {
            return Self.blockedResult(
                configuration: configuration,
                selection: selection,
                diagnostics: diagnostics,
                blockers: [.commitExecutorUnavailable],
                evidence: evidence,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                status: .blocked,
                reason: "commitExecutorUnavailable"
            )
        }

        diagnostics.append(Self.diagnostic(
            .canonicalTombstoneConflictN1CanaryStarted,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            candidate: selected,
            result: "started",
            reason: "n=1"
        ))
        diagnostics.append(Self.diagnostic(
            .canonicalTombstoneConflictN1CommitStarted,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            candidate: selected,
            result: "started",
            hash: selected.markerHash
        ))

        var cutoverResult = await CanonicalTombstoneConflictCutoverRunner().run(
            mode: .canary,
            policy: selectorPolicy,
            token: token,
            evidence: evidence,
            candidates: [selected],
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID,
            executor: executor
        )
        if let commit = cutoverResult.commits.first {
            diagnostics.append(Self.diagnostic(
                commit.committed ? .canonicalTombstoneConflictN1CommitCompleted : .canonicalTombstoneConflictN1CommitFailed,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidate: selected,
                result: commit.committed ? "committed" : "failed",
                reason: commit.failureKind?.rawValue ?? commit.reason,
                hash: selected.markerHash
            ))
            diagnostics.append(Self.diagnostic(
                commit.postconditionVerified ? .canonicalTombstoneConflictN1PostconditionVerified : .canonicalTombstoneConflictN1PostconditionFailed,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidate: selected,
                result: commit.postconditionVerified ? "verified" : "failed",
                hash: selected.markerHash
            ))
        }
        for rollback in cutoverResult.rollbackResults {
            diagnostics.append(Self.diagnostic(
                .canonicalTombstoneConflictN1RollbackStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidate: selected,
                result: "started",
                reason: rollback.checkpointID
            ))
            diagnostics.append(Self.diagnostic(
                rollback.succeeded ? .canonicalTombstoneConflictN1RollbackCompleted : .canonicalTombstoneConflictN1RollbackFailed,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidate: selected,
                result: rollback.succeeded ? "rolledBack" : "rollbackFailed",
                reason: rollback.reason
            ))
        }
        if cutoverResult.legacyFallbackUsed {
            diagnostics.append(Self.diagnostic(
                .canonicalTombstoneConflictN1LegacyFallbackUsed,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "legacyFallbackUsed",
                reason: "commitFailureOrRollback"
            ))
        }
        if !cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty {
            diagnostics.append(Self.diagnostic(
                .canonicalTombstoneConflictN1DuplicateLegacySuppressed,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidate: selected,
                result: "successOnly",
                reason: "matchingLegacyTombstoneConflictDuplicate"
            ))
        } else {
            diagnostics.append(Self.diagnostic(
                .canonicalTombstoneConflictN1DuplicateSuppressionSkipped,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidate: selected,
                result: "skipped",
                reason: cutoverResult.succeeded ? "noMatchingLegacyDuplicate" : "canonicalCommitNotSuccessful"
            ))
        }
        if cutoverResult.fatalBlocker {
            diagnostics.append(Self.diagnostic(
                .canonicalTombstoneConflictN1FatalBlocker,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "fatal",
                reason: "rollbackFailure"
            ))
        }
        let observation = Self.observation(
            configuration: configuration,
            selection: selection,
            cutoverResult: cutoverResult,
            blockers: []
        )
        diagnostics.append(Self.diagnostic(
            .canonicalTombstoneConflictN1ObservationRecorded,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: observation.status.rawValue,
            reason: observation.diagnosticsSummary
        ))
        cutoverResult.diagnostics = diagnostics + cutoverResult.diagnostics
        return CanonicalTombstoneConflictCanaryResult(
            configuration: configuration,
            cutoverResult: cutoverResult,
            selection: selection,
            observationReport: observation
        )
    }

    private nonisolated static func strictConfigurationBlockers(
        configuration: CanonicalTombstoneConflictCanaryConfiguration,
        policy: CanonicalTombstoneConflictCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalTombstoneConflictCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix,
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        failureInjectionAvailable: Bool,
        antiResurrectionEvidenceAvailable: Bool,
        physicalDeleteGuardPassed: Bool,
        permanentDeleteGuardPassed: Bool,
        tombstoneGCGuardPassed: Bool,
        duplicateSuppressionPolicyAvailable: Bool,
        executorAvailable: Bool
    ) -> [CanonicalTombstoneConflictCanaryCandidateBlocker] {
        var blockers: [CanonicalTombstoneConflictCanaryCandidateBlocker] = []
        if configuration.mode == .disabled { blockers.append(.disabled) }
        if configuration.mode != .n1 { blockers.append(.unsupportedMode) }
        if configuration.domain != .tombstoneConflict { blockers.append(.unsupportedDomain) }
        if configuration.canaryMaxObjectsPerSyncRun == 0 || policy.canaryMaxObjectsPerSyncRun == 0 { blockers.append(.canaryBudgetZero) }
        if configuration.canaryMaxObjectsPerSyncRun > 1 || policy.canaryMaxObjectsPerSyncRun > 1 { blockers.append(.canaryBudgetAboveOneDenied) }
        if configuration.canaryMaxObjectsPerSyncRun != 1 || policy.canaryMaxObjectsPerSyncRun != 1 {
            blockers.append(.missingInternalCanaryConfiguration)
        }
        if !configuration.explicitInternalTestConfiguration
            || !policy.explicitInternalTestConfiguration
            || !policy.allowsInternalN1Execution
            || !policy.allowCandidateExecution {
            blockers.append(.missingInternalCanaryConfiguration)
        }
        if configuration.allowAllEligible || policy.allowAllEligible || policy.requestedStage == .allEligible {
            blockers.append(.allEligibleDenied)
        }
        if policy.requestedStage.isExecutable && policy.requestedStage != .n1 {
            blockers.append(.canaryBudgetAboveOneDenied)
        }
        if configuration.runtimeSwitchEnabled || policy.runtimeSwitchEnabled {
            blockers.append(.runtimeSwitchDenied)
        }
        if configuration.releaseDefaultEnabled {
            blockers.append(.defaultEnablementDenied)
        }
        let matrixReport = matrix.validate()
        if !matrixReport.allowed { blockers.append(.matrixBlocked) }
        if matrixReport.activePilotDomain != .tombstoneConflict { blockers.append(.activePilotNotTombstoneConflict) }
        if configuration.productionTokenRequired && token == nil { blockers.append(.missingToken) }
        if configuration.ownerApprovalRequired && token?.ownerApproved != true { blockers.append(.missingOwnerApproval) }
        if !localSnapshotAvailable { blockers.append(.localSnapshotUnavailable) }
        if !peerSnapshotAvailable { blockers.append(.peerSnapshotUnavailable) }
        if !executorAvailable { blockers.append(.commitExecutorUnavailable) }
        if trigger == .viewRefresh || trigger == .retryDrainer { blockers.append(.unsupportedTrigger) }
        if !evidence.noCommitEvidenceAvailable { blockers.append(.missingNoCommitEvidence) }
        if !evidence.dryRunEquivalenceVerified { blockers.append(.missingDryRunEquivalence) }
        if !evidence.executionShadowVerified { blockers.append(.missingExecutionShadowEvidence) }
        if !evidence.realDataShadowCopyVerified { blockers.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.noBlockingDivergence { blockers.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict { blockers.append(.unresolvedConflict) }
        if !evidence.metadataRouteEvidenceAvailable { blockers.append(.missingMetadataRouteEvidence) }
        if !evidence.productionPortAvailable { blockers.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { blockers.append(.realApplyPortUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { blockers.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { blockers.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { blockers.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { blockers.append(.rollbackCheckpointUnavailable) }
        if configuration.rollbackPlanRequired && evidence.rollbackPlan == nil { blockers.append(.missingRollback) }
        if !evidence.rollbackVerified || !evidence.rollbackEvidenceAvailable { blockers.append(.rollbackVerificationMissing) }
        if !evidence.productionRootDisabledByDefault { blockers.append(.productionRootEnabledByDefault) }
        if evidence.applyPortMode == .testRootBound && !evidence.testRootUsed { blockers.append(.testRootMissing) }
        if !evidence.legacyFallbackAvailable { blockers.append(.legacyFallbackUnavailable) }
        if !evidence.readSideParallelEquivalent { blockers.append(.readSideParallelMissing) }
        if !failureInjectionAvailable { blockers.append(.failureInjectionMissing) }
        if !antiResurrectionEvidenceAvailable { blockers.append(.antiResurrectionEvidenceMissing) }
        if !physicalDeleteGuardPassed { blockers.append(.physicalDeleteGuardMissing) }
        if !permanentDeleteGuardPassed { blockers.append(.permanentDeleteGuardMissing) }
        if !tombstoneGCGuardPassed { blockers.append(.tombstoneGCGuardMissing) }
        if !duplicateSuppressionPolicyAvailable { blockers.append(.duplicateSuppressionPolicyMissing) }
        return Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated static func initialDiagnostics(
        configuration: CanonicalTombstoneConflictCanaryConfiguration,
        policy: CanonicalTombstoneConflictCanaryPolicy,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        candidateCount: Int,
        blockers: [CanonicalTombstoneConflictCanaryCandidateBlocker]
    ) -> [CanonicalTombstoneConflictCutoverDiagnostic] {
        [
            diagnostic(
                .canonicalTombstoneConflictN1CanaryConfigured,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: blockers.isEmpty ? "configured" : "blocked",
                reason: [
                    "mode=\(configuration.mode.rawValue)",
                    "domain=\(configuration.domain.rawValue)",
                    "budget=\(configuration.canaryMaxObjectsPerSyncRun)",
                    "explicitInternal=\(configuration.explicitInternalTestConfiguration)",
                    "policyBudget=\(policy.canaryMaxObjectsPerSyncRun)",
                    "candidateCount=\(candidateCount)",
                    "runtimeSwitch=\(policy.runtimeSwitchEnabled)"
                ].joined(separator: ";")
            ),
            diagnostic(
                .canonicalTombstoneConflictN1CandidateSelectionStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "started",
                reason: "candidateCount=\(candidateCount)"
            )
        ]
    }

    private nonisolated static func selectionDiagnostics(
        selection: CanonicalTombstoneConflictCanarySelectionResult,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> [CanonicalTombstoneConflictCutoverDiagnostic] {
        var diagnostics: [CanonicalTombstoneConflictCutoverDiagnostic] = []
        for selected in selection.selectedCandidates {
            diagnostics.append(diagnostic(
                .canonicalTombstoneConflictN1CandidateSelected,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidate: selected,
                result: "selected",
                reason: "n1SafeCandidate",
                hash: selected.markerHash
            ))
        }
        for blocker in selection.blockers {
            diagnostics.append(diagnostic(
                .canonicalTombstoneConflictN1CandidateBlocked,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                domain: nil,
                objectID: blocker.objectID,
                result: "blocked",
                reason: blocker.reason.rawValue
            ))
        }
        if selection.noEligibleCandidate {
            diagnostics.append(diagnostic(
                .canonicalTombstoneConflictN1NoEligibleCandidate,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "noEligibleCandidate",
                reason: "evaluated=\(selection.evaluatedCandidateCount),reportOnly=\(selection.reportOnlyCandidateCount)"
            ))
        }
        return diagnostics
    }

    private nonisolated static func boundaryDiagnostics(
        blockers: [CanonicalTombstoneConflictCanaryCandidateBlocker],
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> [CanonicalTombstoneConflictCutoverDiagnostic] {
        var diagnostics: [CanonicalTombstoneConflictCutoverDiagnostic] = []
        let blockerSet = Set(blockers)
        if blockerSet.contains(.physicalDeleteCandidate) || blockerSet.contains(.physicalDeleteGuardMissing) {
            diagnostics.append(diagnostic(.canonicalTombstoneConflictN1PhysicalDeleteBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if blockerSet.contains(.permanentDeleteCandidate) || blockerSet.contains(.permanentDeleteGuardMissing) {
            diagnostics.append(diagnostic(.canonicalTombstoneConflictN1PermanentDeleteBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if blockerSet.contains(.tombstoneGCCandidate) || blockerSet.contains(.tombstoneGCGuardMissing) {
            diagnostics.append(diagnostic(.canonicalTombstoneConflictN1GCBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if blockerSet.contains(.antiResurrectionEvidenceMissing) {
            diagnostics.append(diagnostic(.canonicalTombstoneConflictN1AntiResurrectionBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if blockerSet.contains(.staleLiveResurrection) {
            diagnostics.append(diagnostic(.canonicalTombstoneConflictN1StaleLiveResurrectionBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if blockerSet.contains(.ambiguousConflictAutoResolution) || blockerSet.contains(.conflictPolicyAmbiguous) {
            diagnostics.append(diagnostic(.canonicalTombstoneConflictN1AutoResolutionBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        if blockerSet.contains(.peerSnapshotUnavailable), nodeRole == .mac {
            diagnostics.append(diagnostic(.canonicalTombstoneConflictN1MacPeerSnapshotUnavailable, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked"))
        }
        return diagnostics
    }

    private nonisolated static func selectionBlockedByRunBlockers(
        _ selection: CanonicalTombstoneConflictCanarySelectionResult,
        blockers: [CanonicalTombstoneConflictCanaryCandidateBlocker],
        evaluatedCandidateCount: Int
    ) -> CanonicalTombstoneConflictCanarySelectionResult {
        var runBlockers = selection.blockers
        runBlockers.append(contentsOf: blockers.map {
            CanonicalTombstoneConflictCanarySelectionBlocker(objectID: nil, actionKind: nil, reason: $0)
        })
        return CanonicalTombstoneConflictCanarySelectionResult(
            selectedCandidates: [],
            blockers: runBlockers,
            safetyReports: selection.safetyReports,
            evaluatedCandidateCount: evaluatedCandidateCount,
            reportOnlyCandidateCount: selection.reportOnlyCandidateCount,
            noEligibleCandidate: true
        )
    }

    private nonisolated static func blockedResult(
        configuration: CanonicalTombstoneConflictCanaryConfiguration,
        selection: CanonicalTombstoneConflictCanarySelectionResult,
        diagnostics: [CanonicalTombstoneConflictCutoverDiagnostic],
        blockers: [CanonicalTombstoneConflictCanaryCandidateBlocker],
        evidence: CanonicalTombstoneConflictCutoverEvidence,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        status: CanonicalTombstoneConflictCanaryObservationStatus,
        reason: String
    ) -> CanonicalTombstoneConflictCanaryResult {
        var allDiagnostics = diagnostics
        if status == .blocked {
            allDiagnostics.append(diagnostic(
                .canonicalTombstoneConflictN1FatalBlocker,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "blocked",
                reason: reason
            ))
        }
        allDiagnostics.append(diagnostic(
            .canonicalTombstoneConflictN1LegacyFallbackUsed,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: "legacyFallbackPreserved",
            reason: status.rawValue
        ))
        let observation = observation(
            configuration: configuration,
            selection: selection,
            cutoverResult: nil,
            blockers: blockers,
            statusOverride: status
        )
        allDiagnostics.append(diagnostic(
            .canonicalTombstoneConflictN1ObservationRecorded,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: observation.status.rawValue,
            reason: observation.diagnosticsSummary
        ))
        let gate = CanonicalTombstoneConflictCutoverGate(
            mode: .canary,
            failures: blockers.map(mapBlockerToFailure),
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            reason: reason
        )
        let cutoverResult = CanonicalTombstoneConflictCutoverResult(
            gate: gate,
            commits: [],
            rollbackResults: [],
            diagnostics: allDiagnostics,
            legacyFallbackUsed: true,
            duplicateLegacySuppressedActionIDs: [],
            canaryAttemptedCount: 0,
            canarySucceeded: false,
            fatalBlocker: status == .blocked,
            readSideProjection: nil
        )
        return CanonicalTombstoneConflictCanaryResult(
            configuration: configuration,
            cutoverResult: cutoverResult,
            selection: selection,
            observationReport: observation
        )
    }

    private nonisolated static func observation(
        configuration: CanonicalTombstoneConflictCanaryConfiguration,
        selection: CanonicalTombstoneConflictCanarySelectionResult,
        cutoverResult: CanonicalTombstoneConflictCutoverResult?,
        blockers: [CanonicalTombstoneConflictCanaryCandidateBlocker],
        statusOverride: CanonicalTombstoneConflictCanaryObservationStatus? = nil
    ) -> CanonicalTombstoneConflictCanaryObservationReport {
        let commits = cutoverResult?.commits ?? []
        let successCount = commits.filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }.count
        let failureCount = commits.filter { !$0.committed || !$0.postconditionVerified || !$0.preconditionVerified }.count
        let rollbackFailureCount = (cutoverResult?.rollbackResults ?? []).filter { !$0.succeeded || $0.fatal }.count
        let allBlockers = selection.blockers.map(\.reason) + blockers
        let status = statusOverride ?? {
            if cutoverResult?.fatalBlocker == true || rollbackFailureCount > 0 { return .fatalRollbackFailure }
            if successCount > 0 { return .committed }
            if failureCount > 0 { return .failedRolledBack }
            if selection.reportOnlyCandidateCount > 0 && selection.selectedCandidates.isEmpty { return .reportOnly }
            if selection.selectedCandidates.isEmpty { return .noEligibleCandidate }
            return .blocked
        }()
        return CanonicalTombstoneConflictCanaryObservationReport(
            status: status,
            canaryBudget: configuration.canaryMaxObjectsPerSyncRun,
            selectedCandidateCount: selection.selectedCandidates.count,
            executedCandidateCount: cutoverResult?.canaryAttemptedCount ?? 0,
            successCount: successCount,
            failureCount: failureCount,
            rollbackCount: cutoverResult?.rollbackResults.count ?? 0,
            rollbackFailureCount: rollbackFailureCount,
            legacyFallbackCount: cutoverResult?.legacyFallbackUsed == true ? 1 : (status == .committed ? 0 : 1),
            duplicateSuppressionCount: cutoverResult?.duplicateLegacySuppressedActionIDs.count ?? 0,
            unsafeCandidateSkippedCount: selection.blockers.count,
            noEligibleCandidateCount: selection.selectedCandidates.isEmpty ? 1 : 0,
            fatalBlockerCount: (cutoverResult?.fatalBlocker == true || status == .blocked || status == .fatalRollbackFailure) ? 1 : 0,
            antiResurrectionBlockCount: allBlockers.filter { $0 == .antiResurrectionEvidenceMissing }.count,
            physicalDeleteRiskCount: allBlockers.filter { $0 == .physicalDeleteCandidate || $0 == .physicalDeleteGuardMissing }.count,
            permanentDeleteRiskCount: allBlockers.filter { $0 == .permanentDeleteCandidate || $0 == .permanentDeleteGuardMissing }.count,
            tombstoneGCRiskCount: allBlockers.filter { $0 == .tombstoneGCCandidate || $0 == .tombstoneGCGuardMissing }.count,
            autoConflictResolutionRiskCount: allBlockers.filter { $0 == .ambiguousConflictAutoResolution || $0 == .conflictPolicyAmbiguous }.count,
            staleLiveResurrectionRiskCount: allBlockers.filter { $0 == .staleLiveResurrection }.count,
            readSideEquivalentCount: cutoverResult?.readSideProjection?.equivalent == true ? 1 : 0,
            readSideDivergentCount: cutoverResult?.readSideProjection?.equivalent == false ? 1 : 0,
            runtimeSwitch: configuration.runtimeSwitchEnabled
        )
    }

    private nonisolated static func mapBlockerToFailure(
        _ blocker: CanonicalTombstoneConflictCanaryCandidateBlocker
    ) -> CanonicalTombstoneConflictFailure {
        switch blocker {
        case .disabled, .canaryBudgetZero:
            return .disabled
        case .unsupportedMode, .unsupportedTrigger, .runtimeSwitchDenied, .defaultEnablementDenied, .allEligibleDenied:
            return .unsupportedMode
        case .canaryBudgetAboveOneDenied:
            return .canaryBudgetAboveOneDenied
        case .missingInternalCanaryConfiguration:
            return .missingInternalCanaryConfiguration
        case .unsupportedDomain, .activePilotNotTombstoneConflict, .matrixBlocked:
            return .unsupportedDomain
        case .unsupportedAction, .unsupportedObjectKind, .noEligibleCandidate:
            return .unsupportedAction
        case .missingToken:
            return .missingToken
        case .missingOwnerApproval:
            return .missingOwnerApproval
        case .peerSnapshotUnavailable, .localSnapshotUnavailable, .missingRealDataShadowCopyEvidence:
            return .missingRealDataShadowCopyEvidence
        case .commitExecutorUnavailable, .productionPortUnavailable:
            return .productionPortUnavailable
        case .missingNoCommitEvidence:
            return .missingNoCommitEvidence
        case .missingDryRunEquivalence:
            return .missingDryRunEquivalence
        case .missingExecutionShadowEvidence:
            return .missingExecutionShadowEvidence
        case .blockingDivergence:
            return .blockingDivergence
        case .unresolvedConflict:
            return .unresolvedConflict
        case .missingMetadataRouteEvidence:
            return .missingMetadataRouteEvidence
        case .realApplyPortUnavailable, .rootBoundWriteUnavailable:
            return .rootBoundWriteUnavailable
        case .applyPortDryRunOnly:
            return .applyPortDryRunOnly
        case .atomicReplaceUnavailable:
            return .atomicReplaceUnavailable
        case .rollbackCheckpointUnavailable, .missingRollbackCheckpoint:
            return .rollbackCheckpointUnavailable
        case .missingRollback:
            return .missingRollback
        case .rollbackVerificationMissing:
            return .rollbackVerificationMissing
        case .productionRootEnabledByDefault:
            return .productionRootEnabledByDefault
        case .testRootMissing:
            return .testRootMissing
        case .legacyFallbackUnavailable:
            return .missingRollback
        case .readSideParallelMissing:
            return .blockingDivergence
        case .failureInjectionMissing:
            return .missingCanaryStageEvidence
        case .antiResurrectionEvidenceMissing, .staleLiveResurrection:
            return .resurrectionRiskDetected
        case .physicalDeleteGuardMissing, .physicalDeleteCandidate:
            return .physicalDeleteAttempted
        case .permanentDeleteGuardMissing, .permanentDeleteCandidate:
            return .permanentDeleteAttempted
        case .tombstoneGCGuardMissing, .tombstoneGCCandidate:
            return .tombstoneGCAttempted
        case .duplicateSuppressionPolicyMissing:
            return .missingCanaryStageEvidence
        case .clearTombstoneCandidate, .restoreWithoutExplicitSignal:
            return .unsupportedRestore
        case .ambiguousConflictAutoResolution, .conflictPolicyAmbiguous:
            return .conflictPolicyAmbiguous
        case .generatedArtifactApplyOnTombstonedParent:
            return .generatedArtifactTombstoneUnsupported
        case .audioRelatedAction, .fullContentMutation, .unsafePathToken, .objectIDInstability, .parentMissing, .irreversibleDeleteAction:
            return .unsupportedAction
        case .tombstoneTimestampMissing:
            return .missingTombstoneTimestamp
        }
    }

    private nonisolated static func diagnostic(
        _ kind: CanonicalTombstoneConflictCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        candidate: CanonicalTombstoneConflictCandidate? = nil,
        domain: CanonicalTombstoneConflictDomain? = nil,
        objectID: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalTombstoneConflictCutoverDiagnostic {
        CanonicalTombstoneConflictCutoverDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            domain: candidate?.domain ?? domain,
            objectID: candidate?.objectID ?? objectID,
            action: candidate?.actionKind.rawValue,
            tombstoneState: candidate?.tombstoneState,
            conflictKind: candidate?.conflictKindSummary,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}
