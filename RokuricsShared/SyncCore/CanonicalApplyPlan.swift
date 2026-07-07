//
//  CanonicalApplyPlan.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalApplyActionKind: String, Codable, Equatable, Sendable {
    case recordingMetadataApply
    case recordingMetadataSend
    case folderMetadataApply
    case folderMetadataSend
    case studyItemMetadataApply
    case studyItemMetadataSend
    case libraryTombstoneApply
    case libraryTombstoneSend
    case generatedArtifactDownloadApply
    case generatedArtifactNoOp
    case objectTombstoneApply
    case objectTombstoneSend
    case artifactTombstoneApply
    case conflictRecord
    case deferredUnsupported
}

nonisolated enum CanonicalApplySource: String, Codable, Equatable, Sendable {
    case local
    case peer
    case planner
}

nonisolated struct CanonicalApplyTarget: Codable, Equatable, Hashable, Sendable {
    var objectID: String
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?

    nonisolated init(
        objectID: String,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil
    ) {
        self.objectID = Self.normalizedRequired(objectID, fallback: "unknown-recording")
        self.artifactID = artifactID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.artifactKind = artifactKind
    }

    nonisolated private static func normalizedRequired(_ value: String, fallback: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallback
    }
}

nonisolated struct CanonicalApplyPrecondition: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        case localModifiedAt
        case peerModifiedAt
        case localHashPrefix
        case peerHashPrefix
        case peerByteSize
        case tombstoneTimestamp
        case noPhysicalDelete
        case legacyBridge
    }

    var kind: Kind
    var value: String

    nonisolated init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum CanonicalApplyResult: String, Codable, Equatable, Sendable {
    case planned
    case noOp
    case conflictRecorded
    case deferredUnsupported
}

nonisolated enum CanonicalApplyFailureReason: String, Codable, Equatable, Sendable {
    case unsupportedRoute
    case conflictDetected
    case tombstoneBlocksResurrection
    case legacyArtifactMissing
    case noPhysicalDeletePolicy
    case hashOrSizeMismatch
}

nonisolated enum CanonicalApplyBridgeHint: String, Codable, Equatable, Sendable {
    case legacyMetadataManifestApply
    case legacyMetadataManifestSend
    case legacyArtifactRequestApply
    case noGeneratedArtifactUploadJob
    case noPhysicalDelete
    case unsupportedNoRoute
    case legacyFallbackPreserved
}

nonisolated struct CanonicalApplyAction: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID }

    var actionID: String
    var kind: CanonicalApplyActionKind
    var source: CanonicalApplySource
    var target: CanonicalApplyTarget
    var bridgeHint: CanonicalApplyBridgeHint?
    var preconditions: [CanonicalApplyPrecondition]
    var result: CanonicalApplyResult
    var failureReason: CanonicalApplyFailureReason?
    var conflictID: String?
    var tombstoneID: String?
    var reason: String

    nonisolated init(
        kind: CanonicalApplyActionKind,
        source: CanonicalApplySource,
        target: CanonicalApplyTarget,
        bridgeHint: CanonicalApplyBridgeHint? = nil,
        preconditions: [CanonicalApplyPrecondition] = [],
        result: CanonicalApplyResult = .planned,
        failureReason: CanonicalApplyFailureReason? = nil,
        conflictID: String? = nil,
        tombstoneID: String? = nil,
        reason: String
    ) {
        self.kind = kind
        self.source = source
        self.target = target
        self.bridgeHint = bridgeHint
        self.preconditions = preconditions
        self.result = result
        self.failureReason = failureReason
        self.conflictID = conflictID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.tombstoneID = tombstoneID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? kind.rawValue
        self.actionID = Self.makeActionID(kind: kind, target: target, reason: self.reason)
    }

    nonisolated private static func makeActionID(
        kind: CanonicalApplyActionKind,
        target: CanonicalApplyTarget,
        reason: String
    ) -> String {
        [
            kind.rawValue,
            target.objectID,
            target.artifactKind?.rawValue ?? "object",
            target.artifactID ?? "metadata",
            reason
        ].joined(separator: "|")
    }
}

nonisolated enum CanonicalConflictKind: String, Codable, Equatable, Sendable {
    case recordingMetadataConcurrentEdit
    case recordingAudioContentMismatch
    case generatedArtifactContentMismatch
    case activeVsTombstone
}

nonisolated enum CanonicalConflictSeverity: String, Codable, Equatable, Sendable {
    case warning
    case blocking
}

nonisolated enum CanonicalConflictResolutionPolicy: String, Codable, Equatable, Sendable {
    case manualReview
    case keepBothNoOverwrite
    case tombstoneRequiresManualReview
}

nonisolated enum CanonicalConflictResolutionState: String, Codable, Equatable, Sendable {
    case unresolved
    case resolved
    case ignored
}

nonisolated struct CanonicalConflictRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { conflictID }

    var conflictID: String
    var kind: CanonicalConflictKind
    var severity: CanonicalConflictSeverity
    var resolutionPolicy: CanonicalConflictResolutionPolicy
    var resolutionState: CanonicalConflictResolutionState
    var target: CanonicalApplyTarget
    var localHashPrefix: String?
    var peerHashPrefix: String?
    var localModifiedAt: CanonicalTimestamp?
    var peerModifiedAt: CanonicalTimestamp?
    var detail: String?

    nonisolated init(
        kind: CanonicalConflictKind,
        target: CanonicalApplyTarget,
        severity: CanonicalConflictSeverity = .blocking,
        resolutionPolicy: CanonicalConflictResolutionPolicy,
        resolutionState: CanonicalConflictResolutionState = .unresolved,
        localHash: CanonicalHash? = nil,
        peerHash: CanonicalHash? = nil,
        localModifiedAt: CanonicalTimestamp? = nil,
        peerModifiedAt: CanonicalTimestamp? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.severity = severity
        self.resolutionPolicy = resolutionPolicy
        self.resolutionState = resolutionState
        self.target = target
        self.localHashPrefix = localHash.map { Self.hashPrefix($0) }
        self.peerHashPrefix = peerHash.map { Self.hashPrefix($0) }
        self.localModifiedAt = localModifiedAt
        self.peerModifiedAt = peerModifiedAt
        self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.conflictID = [
            "conflict",
            kind.rawValue,
            target.objectID,
            target.artifactKind?.rawValue ?? "metadata",
            target.artifactID ?? "object"
        ].joined(separator: "|")
    }

    nonisolated private static func hashPrefix(_ hash: CanonicalHash) -> String {
        String(hash.value.prefix(12))
    }
}

nonisolated struct CanonicalConflictDiagnostics: Codable, Equatable, Sendable {
    var total: Int
    var metadata: Int
    var audio: Int
    var generatedArtifact: Int
    var tombstone: Int
}

nonisolated enum CanonicalTombstoneState: String, Codable, Equatable, Sendable {
    case active
    case tombstoned
}

nonisolated enum CanonicalDeletionReason: String, Codable, Equatable, Sendable {
    case softDelete
    case peerTombstoneNewer
    case localTombstoneNewer
    case artifactTombstonePresent
}

nonisolated enum CanonicalTombstonePolicy: String, Codable, Equatable, Hashable, Sendable {
    case softDeleteOnly
    case antiResurrection
    case noPhysicalDelete
    case noPermanentDelete
    case noGarbageCollection
}

nonisolated struct CanonicalTombstone: Codable, Equatable, Identifiable, Sendable {
    var id: String { tombstoneID }

    var tombstoneID: String
    var target: CanonicalApplyTarget
    var state: CanonicalTombstoneState
    var reason: CanonicalDeletionReason
    var deletedAt: CanonicalTimestamp?
    var sourceNodeID: String?
    var policies: [CanonicalTombstonePolicy]

    nonisolated init(
        target: CanonicalApplyTarget,
        state: CanonicalTombstoneState,
        reason: CanonicalDeletionReason,
        deletedAt: CanonicalTimestamp?,
        sourceNodeID: String?,
        policies: [CanonicalTombstonePolicy] = [.softDeleteOnly, .antiResurrection, .noPhysicalDelete, .noPermanentDelete, .noGarbageCollection]
    ) {
        self.target = target
        self.state = state
        self.reason = reason
        self.deletedAt = deletedAt
        self.sourceNodeID = sourceNodeID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.policies = Array(Set(policies)).sorted { $0.rawValue < $1.rawValue }
        self.tombstoneID = [
            "tombstone",
            target.objectID,
            target.artifactKind?.rawValue ?? "object",
            target.artifactID ?? "metadata"
        ].joined(separator: "|")
    }
}

nonisolated struct CanonicalApplyDiagnostic: Codable, Equatable, Identifiable, Sendable {
    nonisolated var id: String { [phase, target.objectID, target.artifactID ?? "", detail ?? ""].joined(separator: "|") }

    var phase: String
    var target: CanonicalApplyTarget
    var detail: String?
}

nonisolated struct CanonicalApplyPlan: Codable, Equatable, Sendable {
    nonisolated static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var trigger: CanonicalSyncPlanTrigger
    var actions: [CanonicalApplyAction]
    var conflicts: [CanonicalConflictRecord]
    var tombstones: [CanonicalTombstone]
    var diagnostics: [CanonicalApplyDiagnostic]
    var conflictDiagnostics: CanonicalConflictDiagnostics

    nonisolated init(
        trigger: CanonicalSyncPlanTrigger,
        actions: [CanonicalApplyAction] = [],
        conflicts: [CanonicalConflictRecord] = [],
        tombstones: [CanonicalTombstone] = [],
        diagnostics: [CanonicalApplyDiagnostic] = []
    ) {
        self.trigger = trigger
        self.actions = actions
        self.conflicts = conflicts
        self.tombstones = tombstones
        self.diagnostics = diagnostics
        self.conflictDiagnostics = Self.makeConflictDiagnostics(conflicts)
    }

    nonisolated func deduplicated() -> CanonicalApplyPlan {
        var seenActions = Set<String>()
        var seenConflicts = Set<String>()
        var seenTombstones = Set<String>()
        var seenDiagnostics = Set<String>()
        return CanonicalApplyPlan(
            trigger: trigger,
            actions: actions.filter { seenActions.insert($0.actionID).inserted },
            conflicts: conflicts.filter { seenConflicts.insert($0.conflictID).inserted },
            tombstones: tombstones.filter { seenTombstones.insert($0.tombstoneID).inserted },
            diagnostics: diagnostics.filter { seenDiagnostics.insert($0.id).inserted }
        )
    }

    nonisolated private static func makeConflictDiagnostics(_ conflicts: [CanonicalConflictRecord]) -> CanonicalConflictDiagnostics {
        CanonicalConflictDiagnostics(
            total: conflicts.count,
            metadata: conflicts.filter { $0.kind == .recordingMetadataConcurrentEdit }.count,
            audio: conflicts.filter { $0.kind == .recordingAudioContentMismatch }.count,
            generatedArtifact: conflicts.filter { $0.kind == .generatedArtifactContentMismatch }.count,
            tombstone: conflicts.filter { $0.kind == .activeVsTombstone }.count
        )
    }
}

nonisolated struct CanonicalApplyPlanner {
    nonisolated init() {}

    nonisolated func plan(
        local: CanonicalManifest,
        peer: CanonicalManifest,
        syncPlan: CanonicalSyncPlan,
        trigger: CanonicalSyncPlanTrigger,
        legacyContext: CanonicalSyncPlannerLegacyContext? = nil
    ) -> CanonicalApplyPlan {
        let localObjects = Dictionary(uniqueKeysWithValues: local.objects.map { ($0.objectID, $0) })
        let peerObjects = Dictionary(uniqueKeysWithValues: peer.objects.map { ($0.objectID, $0) })
        let objectIDs = Set(localObjects.keys).union(peerObjects.keys).sorted()
        var actions: [CanonicalApplyAction] = []
        var conflicts: [CanonicalConflictRecord] = []
        var tombstones: [CanonicalTombstone] = []
        var diagnostics: [CanonicalApplyDiagnostic] = []
        var tombstoneOverrideObjectIDs = Set<String>()

        for objectID in objectIDs {
            appendObjectTombstoneDecision(
                objectID: objectID,
                localObject: localObjects[objectID],
                peerObject: peerObjects[objectID],
                actions: &actions,
                conflicts: &conflicts,
                tombstones: &tombstones,
                diagnostics: &diagnostics,
                tombstoneOverrideObjectIDs: &tombstoneOverrideObjectIDs
            )
        }

        appendMetadataActions(
            syncPlan: syncPlan,
            tombstoneOverrideObjectIDs: tombstoneOverrideObjectIDs,
            actions: &actions,
            conflicts: &conflicts
        )
        appendAudioConflictActions(syncPlan: syncPlan, actions: &actions, conflicts: &conflicts)
        appendArtifactTombstones(
            localObjects: localObjects,
            peerObjects: peerObjects,
            actions: &actions,
            tombstones: &tombstones,
            diagnostics: &diagnostics
        )
        appendGeneratedArtifactActions(
            syncPlan: syncPlan,
            localObjects: localObjects,
            peerObjects: peerObjects,
            tombstoneOverrideObjectIDs: tombstoneOverrideObjectIDs,
            actions: &actions,
            conflicts: &conflicts,
            diagnostics: &diagnostics
        )

        diagnostics.append(
            CanonicalApplyDiagnostic(
                phase: "canonicalApplyPlanBuilt",
                target: CanonicalApplyTarget(objectID: "summary"),
                detail: "actions=\(actions.count),conflicts=\(conflicts.count),tombstones=\(tombstones.count),trigger=\(trigger.rawValue),legacyFallbackPreserved=\(legacyContext != nil)"
            )
        )

        return CanonicalApplyPlan(
            trigger: trigger,
            actions: actions,
            conflicts: conflicts,
            tombstones: tombstones,
            diagnostics: diagnostics
        ).deduplicated()
    }

    nonisolated private func appendObjectTombstoneDecision(
        objectID: String,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?,
        actions: inout [CanonicalApplyAction],
        conflicts: inout [CanonicalConflictRecord],
        tombstones: inout [CanonicalTombstone],
        diagnostics: inout [CanonicalApplyDiagnostic],
        tombstoneOverrideObjectIDs: inout Set<String>
    ) {
        let localTombstone = objectTombstone(from: localObject, sourceNodeID: localObject?.nodeID, reason: .localTombstoneNewer)
        let peerTombstone = objectTombstone(from: peerObject, sourceNodeID: peerObject?.nodeID, reason: .peerTombstoneNewer)
        if let localTombstone {
            tombstones.append(localTombstone)
        }
        if let peerTombstone {
            tombstones.append(peerTombstone)
        }

        switch (localObject, peerObject) {
        case let (.some(localObject), .some(peerObject)):
            let localDeletedAt = deletionTimestamp(localObject)
            let peerDeletedAt = deletionTimestamp(peerObject)
            switch (localDeletedAt, peerDeletedAt) {
            case let (.some(localDeletedAt), .some(peerDeletedAt)):
                if peerDeletedAt.date > localDeletedAt.date {
                    appendObjectTombstoneAction(
                        kind: .objectTombstoneApply,
                        source: .peer,
                        objectID: objectID,
                        tombstone: peerTombstone,
                        reason: CanonicalDeletionReason.peerTombstoneNewer.rawValue,
                        actions: &actions
                    )
                    tombstoneOverrideObjectIDs.insert(objectID)
                } else if localDeletedAt.date > peerDeletedAt.date {
                    appendObjectTombstoneAction(
                        kind: .objectTombstoneSend,
                        source: .local,
                        objectID: objectID,
                        tombstone: localTombstone,
                        reason: CanonicalDeletionReason.localTombstoneNewer.rawValue,
                        actions: &actions
                    )
                    tombstoneOverrideObjectIDs.insert(objectID)
                }
            case let (.none, .some(peerDeletedAt)):
                if peerDeletedAt.date > localObject.metadata.modifiedAt.date {
                    appendObjectTombstoneAction(
                        kind: .objectTombstoneApply,
                        source: .peer,
                        objectID: objectID,
                        tombstone: peerTombstone,
                        reason: CanonicalDeletionReason.peerTombstoneNewer.rawValue,
                        actions: &actions
                    )
                    tombstoneOverrideObjectIDs.insert(objectID)
                } else {
                    appendActiveVsTombstoneConflict(
                        objectID: objectID,
                        localObject: localObject,
                        peerObject: peerObject,
                        conflicts: &conflicts,
                        actions: &actions
                    )
                    tombstoneOverrideObjectIDs.insert(objectID)
                }
            case let (.some(localDeletedAt), .none):
                if localDeletedAt.date > peerObject.metadata.modifiedAt.date {
                    appendObjectTombstoneAction(
                        kind: .objectTombstoneSend,
                        source: .local,
                        objectID: objectID,
                        tombstone: localTombstone,
                        reason: CanonicalDeletionReason.localTombstoneNewer.rawValue,
                        actions: &actions
                    )
                    tombstoneOverrideObjectIDs.insert(objectID)
                } else {
                    appendActiveVsTombstoneConflict(
                        objectID: objectID,
                        localObject: localObject,
                        peerObject: peerObject,
                        conflicts: &conflicts,
                        actions: &actions
                    )
                    tombstoneOverrideObjectIDs.insert(objectID)
                }
            case (.none, .none):
                break
            }
        case let (.none, .some(peerObject)) where peerObject.metadata.isDeleted:
            appendObjectTombstoneAction(
                kind: .objectTombstoneApply,
                source: .peer,
                objectID: objectID,
                tombstone: peerTombstone,
                reason: CanonicalDeletionReason.peerTombstoneNewer.rawValue,
                actions: &actions
            )
            tombstoneOverrideObjectIDs.insert(objectID)
        case let (.some(localObject), .none) where localObject.metadata.isDeleted:
            appendObjectTombstoneAction(
                kind: .objectTombstoneSend,
                source: .local,
                objectID: objectID,
                tombstone: localTombstone,
                reason: CanonicalDeletionReason.localTombstoneNewer.rawValue,
                actions: &actions
            )
            tombstoneOverrideObjectIDs.insert(objectID)
        default:
            break
        }

        if localObject?.metadata.isDeleted == true || peerObject?.metadata.isDeleted == true {
            diagnostics.append(
                CanonicalApplyDiagnostic(
                    phase: "canonicalTombstoneObserved",
                    target: CanonicalApplyTarget(objectID: objectID),
                    detail: "softDeleteOnly=true,noPhysicalDelete=true"
                )
            )
        }
    }

    nonisolated private func appendMetadataActions(
        syncPlan: CanonicalSyncPlan,
        tombstoneOverrideObjectIDs: Set<String>,
        actions: inout [CanonicalApplyAction],
        conflicts: inout [CanonicalConflictRecord]
    ) {
        for action in syncPlan.uploadRecordingMetadata where !tombstoneOverrideObjectIDs.contains(action.objectID) {
            actions.append(
                CanonicalApplyAction(
                    kind: .recordingMetadataSend,
                    source: .local,
                    target: CanonicalApplyTarget(objectID: action.objectID),
                    bridgeHint: .legacyMetadataManifestSend,
                    preconditions: metadataPreconditions(action),
                    reason: action.reason.rawValue
                )
            )
        }
        for action in syncPlan.downloadRecordingMetadata where !tombstoneOverrideObjectIDs.contains(action.objectID) {
            actions.append(
                CanonicalApplyAction(
                    kind: .recordingMetadataApply,
                    source: .peer,
                    target: CanonicalApplyTarget(objectID: action.objectID),
                    bridgeHint: .legacyMetadataManifestApply,
                    preconditions: metadataPreconditions(action),
                    reason: action.reason.rawValue
                )
            )
        }
        for action in syncPlan.conflictRecordingMetadata where !tombstoneOverrideObjectIDs.contains(action.objectID) {
            let conflict = CanonicalConflictRecord(
                kind: .recordingMetadataConcurrentEdit,
                target: CanonicalApplyTarget(objectID: action.objectID),
                resolutionPolicy: .manualReview,
                localHash: action.localMetadataHash,
                peerHash: action.peerMetadataHash,
                localModifiedAt: action.localModifiedAt,
                peerModifiedAt: action.peerModifiedAt,
                detail: action.reason.rawValue
            )
            conflicts.append(conflict)
            actions.append(conflictAction(conflict))
        }
    }

    nonisolated private func appendAudioConflictActions(
        syncPlan: CanonicalSyncPlan,
        actions: inout [CanonicalApplyAction],
        conflicts: inout [CanonicalConflictRecord]
    ) {
        for action in syncPlan.conflictAudioArtifact {
            let conflict = CanonicalConflictRecord(
                kind: .recordingAudioContentMismatch,
                target: CanonicalApplyTarget(objectID: action.objectID, artifactID: action.artifactID, artifactKind: .audio),
                resolutionPolicy: .keepBothNoOverwrite,
                localHash: action.localHash,
                peerHash: action.peerHash,
                detail: action.reason.rawValue
            )
            conflicts.append(conflict)
            actions.append(conflictAction(conflict))
        }
    }

    nonisolated private func appendArtifactTombstones(
        localObjects: [String: CanonicalRecordingObject],
        peerObjects: [String: CanonicalRecordingObject],
        actions: inout [CanonicalApplyAction],
        tombstones: inout [CanonicalTombstone],
        diagnostics: inout [CanonicalApplyDiagnostic]
    ) {
        let objectIDs = Set(localObjects.keys).union(peerObjects.keys).sorted()
        for objectID in objectIDs {
            let artifacts = (localObjects[objectID]?.artifacts ?? []) + (peerObjects[objectID]?.artifacts ?? [])
            for artifact in artifacts where artifact.tombstone == true && CanonicalProjectionContract.generatedArtifactKinds.contains(artifact.kind) {
                let tombstone = CanonicalTombstone(
                    target: CanonicalApplyTarget(
                        objectID: objectID,
                        artifactID: artifact.artifactID,
                        artifactKind: artifact.kind
                    ),
                    state: .tombstoned,
                    reason: .artifactTombstonePresent,
                    deletedAt: artifact.modifiedAt,
                    sourceNodeID: artifact.producedByNodeID,
                    policies: [.softDeleteOnly, .antiResurrection, .noPhysicalDelete, .noPermanentDelete, .noGarbageCollection]
                )
                tombstones.append(tombstone)
                actions.append(
                    CanonicalApplyAction(
                        kind: .artifactTombstoneApply,
                        source: .planner,
                        target: tombstone.target,
                        bridgeHint: .noPhysicalDelete,
                        preconditions: [
                            CanonicalApplyPrecondition(kind: .noPhysicalDelete, value: "true")
                        ],
                        result: .deferredUnsupported,
                        failureReason: .noPhysicalDeletePolicy,
                        tombstoneID: tombstone.tombstoneID,
                        reason: CanonicalDeletionReason.artifactTombstonePresent.rawValue
                    )
                )
                diagnostics.append(
                    CanonicalApplyDiagnostic(
                        phase: "canonicalArtifactTombstoneObserved",
                        target: tombstone.target,
                        detail: "noPhysicalDelete=true"
                    )
                )
            }
        }
    }

    nonisolated private func appendGeneratedArtifactActions(
        syncPlan: CanonicalSyncPlan,
        localObjects: [String: CanonicalRecordingObject],
        peerObjects: [String: CanonicalRecordingObject],
        tombstoneOverrideObjectIDs: Set<String>,
        actions: inout [CanonicalApplyAction],
        conflicts: inout [CanonicalConflictRecord],
        diagnostics: inout [CanonicalApplyDiagnostic]
    ) {
        for action in syncPlan.downloadGeneratedArtifact {
            if objectIsTombstoned(localObjects[action.objectID]) || objectIsTombstoned(peerObjects[action.objectID]) || tombstoneOverrideObjectIDs.contains(action.objectID) {
                actions.append(
                    unsupportedGeneratedAction(
                        action,
                        failureReason: .tombstoneBlocksResurrection,
                        reason: "tombstoneBlocksResurrection"
                    )
                )
                diagnostics.append(
                    CanonicalApplyDiagnostic(
                        phase: "canonicalGeneratedArtifactDownloadBlockedByTombstone",
                        target: target(for: action),
                        detail: "antiResurrection=true"
                    )
                )
            } else {
                actions.append(
                    CanonicalApplyAction(
                        kind: .generatedArtifactDownloadApply,
                        source: .peer,
                        target: target(for: action),
                        bridgeHint: .legacyArtifactRequestApply,
                        preconditions: artifactPreconditions(action),
                        reason: action.reason.rawValue
                    )
                )
            }
        }
        for action in syncPlan.noOpGeneratedArtifact {
            actions.append(
                CanonicalApplyAction(
                    kind: .generatedArtifactNoOp,
                    source: .planner,
                    target: target(for: action),
                    bridgeHint: .noGeneratedArtifactUploadJob,
                    preconditions: artifactPreconditions(action),
                    result: .noOp,
                    reason: action.reason.rawValue
                )
            )
        }
        for action in syncPlan.deferGeneratedArtifact {
            actions.append(
                unsupportedGeneratedAction(
                    action,
                    failureReason: .unsupportedRoute,
                    reason: action.reason.rawValue
                )
            )
        }
        for action in syncPlan.conflictGeneratedArtifact {
            let conflict = CanonicalConflictRecord(
                kind: .generatedArtifactContentMismatch,
                target: target(for: action),
                resolutionPolicy: .manualReview,
                localHash: action.localHash,
                peerHash: action.peerHash,
                detail: action.reason.rawValue
            )
            conflicts.append(conflict)
            actions.append(conflictAction(conflict))
        }
    }

    nonisolated private func appendObjectTombstoneAction(
        kind: CanonicalApplyActionKind,
        source: CanonicalApplySource,
        objectID: String,
        tombstone: CanonicalTombstone?,
        reason: String,
        actions: inout [CanonicalApplyAction]
    ) {
        actions.append(
            CanonicalApplyAction(
                kind: kind,
                source: source,
                target: CanonicalApplyTarget(objectID: objectID),
                bridgeHint: kind == .objectTombstoneApply ? .legacyMetadataManifestApply : .legacyMetadataManifestSend,
                preconditions: [
                    CanonicalApplyPrecondition(
                        kind: .tombstoneTimestamp,
                        value: tombstone?.deletedAt.map(Self.timestampString) ?? "missing"
                    ),
                    CanonicalApplyPrecondition(kind: .noPhysicalDelete, value: "true")
                ],
                tombstoneID: tombstone?.tombstoneID,
                reason: reason
            )
        )
    }

    nonisolated private func appendActiveVsTombstoneConflict(
        objectID: String,
        localObject: CanonicalRecordingObject,
        peerObject: CanonicalRecordingObject,
        conflicts: inout [CanonicalConflictRecord],
        actions: inout [CanonicalApplyAction]
    ) {
        let conflict = CanonicalConflictRecord(
            kind: .activeVsTombstone,
            target: CanonicalApplyTarget(objectID: objectID),
            resolutionPolicy: .tombstoneRequiresManualReview,
            localHash: localObject.metadataHash,
            peerHash: peerObject.metadataHash,
            localModifiedAt: localObject.metadata.modifiedAt,
            peerModifiedAt: peerObject.metadata.modifiedAt,
            detail: "activeVsTombstone"
        )
        conflicts.append(conflict)
        actions.append(conflictAction(conflict))
    }

    nonisolated private func conflictAction(_ conflict: CanonicalConflictRecord) -> CanonicalApplyAction {
        CanonicalApplyAction(
            kind: .conflictRecord,
            source: .planner,
            target: conflict.target,
            bridgeHint: .legacyFallbackPreserved,
            preconditions: [
                conflict.localHashPrefix.map { CanonicalApplyPrecondition(kind: .localHashPrefix, value: $0) },
                conflict.peerHashPrefix.map { CanonicalApplyPrecondition(kind: .peerHashPrefix, value: $0) }
            ].compactMap { $0 },
            result: .conflictRecorded,
            failureReason: .conflictDetected,
            conflictID: conflict.conflictID,
            reason: conflict.kind.rawValue
        )
    }

    nonisolated private func unsupportedGeneratedAction(
        _ action: CanonicalArtifactTransferAction,
        failureReason: CanonicalApplyFailureReason,
        reason: String
    ) -> CanonicalApplyAction {
        CanonicalApplyAction(
            kind: .deferredUnsupported,
            source: .planner,
            target: target(for: action),
            bridgeHint: failureReason == .tombstoneBlocksResurrection ? .noPhysicalDelete : .unsupportedNoRoute,
            preconditions: artifactPreconditions(action),
            result: .deferredUnsupported,
            failureReason: failureReason,
            reason: reason
        )
    }

    nonisolated private func target(for action: CanonicalArtifactTransferAction) -> CanonicalApplyTarget {
        CanonicalApplyTarget(
            objectID: action.objectID,
            artifactID: action.artifactID,
            artifactKind: action.kind
        )
    }

    nonisolated private func metadataPreconditions(_ action: CanonicalRecordingMetadataAction) -> [CanonicalApplyPrecondition] {
        [
            action.localMetadataHash.map { CanonicalApplyPrecondition(kind: .localHashPrefix, value: hashPrefix($0)) },
            action.peerMetadataHash.map { CanonicalApplyPrecondition(kind: .peerHashPrefix, value: hashPrefix($0)) },
            action.localModifiedAt.map { CanonicalApplyPrecondition(kind: .localModifiedAt, value: Self.timestampString($0)) },
            action.peerModifiedAt.map { CanonicalApplyPrecondition(kind: .peerModifiedAt, value: Self.timestampString($0)) },
            CanonicalApplyPrecondition(kind: .legacyBridge, value: "metadataManifest")
        ].compactMap { $0 }
    }

    nonisolated private func artifactPreconditions(_ action: CanonicalArtifactTransferAction) -> [CanonicalApplyPrecondition] {
        [
            action.localHash.map { CanonicalApplyPrecondition(kind: .localHashPrefix, value: hashPrefix($0)) },
            action.peerHash.map { CanonicalApplyPrecondition(kind: .peerHashPrefix, value: hashPrefix($0)) },
            action.peerByteSize.map { CanonicalApplyPrecondition(kind: .peerByteSize, value: String($0)) },
            CanonicalApplyPrecondition(kind: .legacyBridge, value: "artifactRequest")
        ].compactMap { $0 }
    }

    nonisolated private func objectTombstone(
        from object: CanonicalRecordingObject?,
        sourceNodeID: String?,
        reason: CanonicalDeletionReason
    ) -> CanonicalTombstone? {
        guard let object,
              object.metadata.isDeleted else {
            return nil
        }
        return CanonicalTombstone(
            target: CanonicalApplyTarget(objectID: object.objectID),
            state: .tombstoned,
            reason: reason,
            deletedAt: deletionTimestamp(object),
            sourceNodeID: sourceNodeID
        )
    }

    nonisolated private func objectIsTombstoned(_ object: CanonicalRecordingObject?) -> Bool {
        object?.metadata.isDeleted == true || object?.syncState == .deleted
    }

    nonisolated private func deletionTimestamp(_ object: CanonicalRecordingObject) -> CanonicalTimestamp? {
        guard object.metadata.isDeleted || object.syncState == .deleted else {
            return nil
        }
        return object.metadata.deletedAt ?? object.metadata.modifiedAt
    }

    nonisolated private func hashPrefix(_ hash: CanonicalHash) -> String {
        String(hash.value.prefix(12))
    }

    nonisolated private static func timestampString(_ timestamp: CanonicalTimestamp) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), timestamp.date.timeIntervalSince1970)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
