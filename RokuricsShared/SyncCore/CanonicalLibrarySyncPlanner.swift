//
//  CanonicalLibrarySyncPlanner.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalLibraryActionKind: String, Codable, Equatable, Sendable {
    case folderMetadataApply
    case folderMetadataSend
    case folderMetadataNoOp
    case folderConflict
    case folderTombstoneApply
    case folderTombstoneSend
    case studyItemMetadataApply
    case studyItemMetadataSend
    case studyItemMetadataNoOp
    case studyItemConflict
    case studyItemTombstoneApply
    case studyItemTombstoneSend
    case unsupportedFallback
    case deferred
}

nonisolated struct CanonicalLibrarySyncAction: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID }
    var actionID: String
    var kind: CanonicalLibraryActionKind
    var objectID: CanonicalLibraryObjectID
    var objectKind: CanonicalObjectKind
    var source: CanonicalApplySource
    var reason: String
    var localHashPrefix: String?
    var peerHashPrefix: String?
    var localModifiedAt: CanonicalTimestamp?
    var peerModifiedAt: CanonicalTimestamp?

    nonisolated init(
        kind: CanonicalLibraryActionKind,
        objectID: CanonicalLibraryObjectID,
        objectKind: CanonicalObjectKind,
        source: CanonicalApplySource,
        reason: String,
        localHash: CanonicalHash? = nil,
        peerHash: CanonicalHash? = nil,
        localModifiedAt: CanonicalTimestamp? = nil,
        peerModifiedAt: CanonicalTimestamp? = nil
    ) {
        self.kind = kind
        self.objectID = objectID
        self.objectKind = objectKind
        self.source = source
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? kind.rawValue
        self.localHashPrefix = localHash.map { String($0.value.prefix(12)) }
        self.peerHashPrefix = peerHash.map { String($0.value.prefix(12)) }
        self.localModifiedAt = localModifiedAt
        self.peerModifiedAt = peerModifiedAt
        self.actionID = [kind.rawValue, objectKind.rawValue, objectID.rawValue, self.reason].joined(separator: "|")
    }
}

nonisolated struct CanonicalLibrarySyncDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [phase, objectID?.rawValue ?? "", detail ?? ""].joined(separator: "|") }
    var phase: String
    var objectID: CanonicalLibraryObjectID?
    var objectKind: CanonicalObjectKind?
    var detail: String?
}

nonisolated struct CanonicalLibrarySyncPlan: Codable, Equatable, Sendable {
    var actions: [CanonicalLibrarySyncAction]
    var applyActions: [CanonicalApplyAction]
    var conflicts: [CanonicalLibraryConflict]
    var tombstones: [CanonicalLibraryTombstone]
    var diagnostics: [CanonicalLibrarySyncDiagnostic]
    var fallbackRequiredObjectIDs: [CanonicalLibraryObjectID]

    nonisolated init(
        actions: [CanonicalLibrarySyncAction] = [],
        applyActions: [CanonicalApplyAction] = [],
        conflicts: [CanonicalLibraryConflict] = [],
        tombstones: [CanonicalLibraryTombstone] = [],
        diagnostics: [CanonicalLibrarySyncDiagnostic] = [],
        fallbackRequiredObjectIDs: [CanonicalLibraryObjectID] = []
    ) {
        self.actions = actions
        self.applyActions = applyActions
        self.conflicts = conflicts
        self.tombstones = tombstones
        self.diagnostics = diagnostics
        self.fallbackRequiredObjectIDs = Array(Set(fallbackRequiredObjectIDs)).sorted { $0.rawValue < $1.rawValue }
    }

    nonisolated func deduplicated() -> CanonicalLibrarySyncPlan {
        var seenActions = Set<String>()
        var seenApplyActions = Set<String>()
        var seenConflicts = Set<String>()
        var seenTombstones = Set<String>()
        var seenDiagnostics = Set<String>()
        return CanonicalLibrarySyncPlan(
            actions: actions.filter { seenActions.insert($0.actionID).inserted },
            applyActions: applyActions.filter { seenApplyActions.insert($0.actionID).inserted },
            conflicts: conflicts.filter { seenConflicts.insert($0.conflictID).inserted },
            tombstones: tombstones.filter { seenTombstones.insert($0.tombstoneID).inserted },
            diagnostics: diagnostics.filter { seenDiagnostics.insert($0.id).inserted },
            fallbackRequiredObjectIDs: fallbackRequiredObjectIDs
        )
    }
}

nonisolated struct CanonicalLibrarySyncPlanner {
    nonisolated init() {}

    nonisolated func plan(
        local: CanonicalManifest,
        peer: CanonicalManifest,
        trigger: CanonicalSyncPlanTrigger
    ) -> CanonicalLibrarySyncPlan {
        var plan = CanonicalLibrarySyncPlan()
        guard trigger != .viewRefresh else {
            plan.diagnostics.append(
                CanonicalLibrarySyncDiagnostic(
                    phase: "canonicalDomainFallback",
                    objectID: nil,
                    objectKind: nil,
                    detail: "viewRefreshProjectionOnly"
                )
            )
            return plan
        }
        guard trigger != .retryDrainer else {
            plan.diagnostics.append(
                CanonicalLibrarySyncDiagnostic(
                    phase: "canonicalDomainFallback",
                    objectID: nil,
                    objectKind: nil,
                    detail: "retryDrainerNoFreshLibraryTransfer"
                )
            )
            return plan
        }
        guard hasLibraryCapability(local), hasLibraryCapability(peer) else {
            plan.fallbackRequiredObjectIDs = combinedObjectIDs(local: local, peer: peer)
            plan.diagnostics.append(
                CanonicalLibrarySyncDiagnostic(
                    phase: "canonicalDomainFallback",
                    objectID: nil,
                    objectKind: nil,
                    detail: "canonicalLibraryObjectsCapabilityMissing"
                )
            )
            return plan
        }

        let localObjects = libraryObjectsByID(local.libraryObjects)
        let peerObjects = libraryObjectsByID(peer.libraryObjects)
        for objectID in Set(localObjects.keys).union(peerObjects.keys).sorted(by: { $0.rawValue < $1.rawValue }) {
            appendDecision(
                objectID: objectID,
                localObject: localObjects[objectID],
                peerObject: peerObjects[objectID],
                plan: &plan
            )
        }
        plan.diagnostics.append(
            CanonicalLibrarySyncDiagnostic(
                phase: "canonicalLibraryObjectsProjected",
                objectID: nil,
                objectKind: nil,
                detail: "local=\(local.libraryObjects.count),peer=\(peer.libraryObjects.count),actions=\(plan.actions.count)"
            )
        )
        return plan.deduplicated()
    }

    nonisolated private func appendDecision(
        objectID: CanonicalLibraryObjectID,
        localObject: CanonicalLibraryObject?,
        peerObject: CanonicalLibraryObject?,
        plan: inout CanonicalLibrarySyncPlan
    ) {
        guard let localObject = localObject ?? peerObject else {
            return
        }
        guard isSupported(localObject), peerObject.map(isSupported) != false else {
            appendUnsupported(objectID: objectID, object: localObject, plan: &plan)
            return
        }
        switch (localObject.kind, localObject, peerObject) {
        case (.folder, let local, let peer):
            appendMetadataDecision(
                objectID: objectID,
                objectKind: .folder,
                localObject: local,
                peerObject: peer,
                sendKind: .folderMetadataSend,
                applyKind: .folderMetadataApply,
                noOpKind: .folderMetadataNoOp,
                conflictKind: .folderConflict,
                tombstoneSendKind: .folderTombstoneSend,
                tombstoneApplyKind: .folderTombstoneApply,
                plan: &plan
            )
        case (.standaloneStudyItem, let local, let peer),
             (.standaloneNote, let local, let peer),
             (.recordingAssociatedStudyItem, let local, let peer):
            appendMetadataDecision(
                objectID: objectID,
                objectKind: localObject.kind,
                localObject: local,
                peerObject: peer,
                sendKind: .studyItemMetadataSend,
                applyKind: .studyItemMetadataApply,
                noOpKind: .studyItemMetadataNoOp,
                conflictKind: .studyItemConflict,
                tombstoneSendKind: .studyItemTombstoneSend,
                tombstoneApplyKind: .studyItemTombstoneApply,
                plan: &plan
            )
        default:
            appendUnsupported(objectID: objectID, object: localObject, plan: &plan)
        }
    }

    nonisolated private func appendMetadataDecision(
        objectID: CanonicalLibraryObjectID,
        objectKind: CanonicalObjectKind,
        localObject: CanonicalLibraryObject?,
        peerObject: CanonicalLibraryObject?,
        sendKind: CanonicalLibraryActionKind,
        applyKind: CanonicalLibraryActionKind,
        noOpKind: CanonicalLibraryActionKind,
        conflictKind: CanonicalLibraryActionKind,
        tombstoneSendKind: CanonicalLibraryActionKind,
        tombstoneApplyKind: CanonicalLibraryActionKind,
        plan: inout CanonicalLibrarySyncPlan
    ) {
        let localDeletedAt = localObject?.deletedAt
        let peerDeletedAt = peerObject?.deletedAt
        if appendTombstoneDecision(
            objectID: objectID,
            objectKind: objectKind,
            localObject: localObject,
            peerObject: peerObject,
            localDeletedAt: localDeletedAt,
            peerDeletedAt: peerDeletedAt,
            tombstoneSendKind: tombstoneSendKind,
            tombstoneApplyKind: tombstoneApplyKind,
            plan: &plan
        ) {
            return
        }

        let decision = CanonicalLibraryMetadataModifiedAtPolicy.current.decide(
            CanonicalLibraryMetadataDecisionInput(
                objectID: objectID,
                objectKind: objectKind,
                local: localObject,
                peer: peerObject
            )
        )
        switch decision.action {
        case .noOp:
            appendAction(
                noOpKind,
                objectID: objectID,
                objectKind: objectKind,
                source: .planner,
                reason: decision.reason,
                localObject: localObject,
                peerObject: peerObject,
                plan: &plan
            )
        case .sendLocal:
            appendActionAndApply(
                sendKind,
                objectID: objectID,
                objectKind: objectKind,
                source: .local,
                reason: decision.reason,
                localObject: localObject,
                peerObject: peerObject,
                plan: &plan
            )
        case .applyPeer:
            appendActionAndApply(
                applyKind,
                objectID: objectID,
                objectKind: objectKind,
                source: .peer,
                reason: decision.reason,
                localObject: localObject,
                peerObject: peerObject,
                plan: &plan
            )
        case .deferTie, .conflictBlocked:
            guard let local = localObject, let peer = peerObject else {
                return
            }
            appendConflict(
                actionKind: conflictKind,
                conflictKind: objectKind == .folder ? .folderMetadataConcurrentEdit : .studyItemMetadataConcurrentEdit,
                objectID: objectID,
                objectKind: objectKind,
                localObject: local,
                peerObject: peer,
                reason: decision.reason,
                plan: &plan
            )
        case .legacyFallback:
            guard let fallbackObject = localObject ?? peerObject else {
                return
            }
            appendUnsupported(objectID: objectID, object: fallbackObject, plan: &plan)
        }
    }

    nonisolated private func appendTombstoneDecision(
        objectID: CanonicalLibraryObjectID,
        objectKind: CanonicalObjectKind,
        localObject: CanonicalLibraryObject?,
        peerObject: CanonicalLibraryObject?,
        localDeletedAt: CanonicalTimestamp?,
        peerDeletedAt: CanonicalTimestamp?,
        tombstoneSendKind: CanonicalLibraryActionKind,
        tombstoneApplyKind: CanonicalLibraryActionKind,
        plan: inout CanonicalLibrarySyncPlan
    ) -> Bool {
        if let localObject, localObject.isDeleted {
            plan.tombstones.append(libraryTombstone(object: localObject, reason: .localTombstoneNewer))
        }
        if let peerObject, peerObject.isDeleted {
            plan.tombstones.append(libraryTombstone(object: peerObject, reason: .peerTombstoneNewer))
        }

        switch (localObject, peerObject, localDeletedAt, peerDeletedAt) {
        case let (.some(local), .some(peer), .some(localDeletedAt), .some(peerDeletedAt)):
            if localDeletedAt.date > peerDeletedAt.date {
                appendActionAndApply(tombstoneSendKind, objectID: objectID, objectKind: objectKind, source: .local, reason: "localTombstoneNewer", localObject: local, peerObject: peer, plan: &plan)
            } else if peerDeletedAt.date > localDeletedAt.date {
                appendActionAndApply(tombstoneApplyKind, objectID: objectID, objectKind: objectKind, source: .peer, reason: "peerTombstoneNewer", localObject: local, peerObject: peer, plan: &plan)
            }
            return true
        case let (.some(local), .some(peer), .none, .some(peerDeletedAt)):
            if let localModifiedAt = local.businessModifiedAt, localModifiedAt.date > peerDeletedAt.date {
                appendConflict(actionKind: objectKind == .folder ? .folderConflict : .studyItemConflict, conflictKind: .activeVsTombstone, objectID: objectID, objectKind: objectKind, localObject: local, peerObject: peer, reason: "activeNewerThanPeerTombstone", plan: &plan)
            } else {
                appendActionAndApply(tombstoneApplyKind, objectID: objectID, objectKind: objectKind, source: .peer, reason: "peerTombstoneNewer", localObject: local, peerObject: peer, plan: &plan)
            }
            return true
        case let (.some(local), .some(peer), .some(localDeletedAt), .none):
            if let peerModifiedAt = peer.businessModifiedAt, peerModifiedAt.date > localDeletedAt.date {
                appendConflict(actionKind: objectKind == .folder ? .folderConflict : .studyItemConflict, conflictKind: .activeVsTombstone, objectID: objectID, objectKind: objectKind, localObject: local, peerObject: peer, reason: "activeNewerThanLocalTombstone", plan: &plan)
            } else {
                appendActionAndApply(tombstoneSendKind, objectID: objectID, objectKind: objectKind, source: .local, reason: "localTombstoneNewer", localObject: local, peerObject: peer, plan: &plan)
            }
            return true
        case let (.none, .some(peer), _, .some):
            appendActionAndApply(tombstoneApplyKind, objectID: objectID, objectKind: objectKind, source: .peer, reason: "peerTombstoneNewer", localObject: nil, peerObject: peer, plan: &plan)
            return true
        case let (.some(local), .none, .some, _):
            appendActionAndApply(tombstoneSendKind, objectID: objectID, objectKind: objectKind, source: .local, reason: "localTombstoneNewer", localObject: local, peerObject: nil, plan: &plan)
            return true
        default:
            return false
        }
    }

    nonisolated private func appendActionAndApply(
        _ kind: CanonicalLibraryActionKind,
        objectID: CanonicalLibraryObjectID,
        objectKind: CanonicalObjectKind,
        source: CanonicalApplySource,
        reason: String,
        localObject: CanonicalLibraryObject?,
        peerObject: CanonicalLibraryObject?,
        plan: inout CanonicalLibrarySyncPlan
    ) {
        appendAction(kind, objectID: objectID, objectKind: objectKind, source: source, reason: reason, localObject: localObject, peerObject: peerObject, plan: &plan)
        guard let applyKind = applyActionKind(for: kind) else {
            return
        }
        let bridge: CanonicalApplyBridgeHint = source == .peer ? .legacyMetadataManifestApply : .legacyMetadataManifestSend
        plan.applyActions.append(
            CanonicalApplyAction(
                kind: applyKind,
                source: source,
                target: CanonicalApplyTarget(objectID: objectID.rawValue),
                bridgeHint: bridge,
                preconditions: applyPreconditions(localObject: localObject, peerObject: peerObject),
                reason: reason
            )
        )
        plan.diagnostics.append(
            CanonicalLibrarySyncDiagnostic(
                phase: "canonicalLibraryActionBridged",
                objectID: objectID,
                objectKind: objectKind,
                detail: "\(kind.rawValue)->\(bridge.rawValue)"
            )
        )
    }

    nonisolated private func appendAction(
        _ kind: CanonicalLibraryActionKind,
        objectID: CanonicalLibraryObjectID,
        objectKind: CanonicalObjectKind,
        source: CanonicalApplySource,
        reason: String,
        localObject: CanonicalLibraryObject?,
        peerObject: CanonicalLibraryObject?,
        plan: inout CanonicalLibrarySyncPlan
    ) {
        plan.actions.append(
            CanonicalLibrarySyncAction(
                kind: kind,
                objectID: objectID,
                objectKind: objectKind,
                source: source,
                reason: reason,
                localHash: localObject?.metadataHash,
                peerHash: peerObject?.metadataHash,
                localModifiedAt: localObject?.businessModifiedAt,
                peerModifiedAt: peerObject?.businessModifiedAt
            )
        )
        let phase: String
        switch objectKind {
        case .folder:
            phase = kind == .folderMetadataNoOp ? "canonicalFolderMetadataHashConverged" : "canonicalFolderPlanned"
        case .standaloneStudyItem, .standaloneNote, .recordingAssociatedStudyItem:
            phase = kind == .studyItemMetadataNoOp ? "canonicalStudyItemMetadataHashConverged" : "canonicalStudyItemPlanned"
        default:
            phase = "canonicalLibraryObjectPlanned"
        }
        plan.diagnostics.append(
            CanonicalLibrarySyncDiagnostic(phase: phase, objectID: objectID, objectKind: objectKind, detail: reason)
        )
    }

    nonisolated private func appendConflict(
        actionKind: CanonicalLibraryActionKind,
        conflictKind: CanonicalLibraryConflictKind,
        objectID: CanonicalLibraryObjectID,
        objectKind: CanonicalObjectKind,
        localObject: CanonicalLibraryObject,
        peerObject: CanonicalLibraryObject,
        reason: String,
        plan: inout CanonicalLibrarySyncPlan
    ) {
        appendAction(actionKind, objectID: objectID, objectKind: objectKind, source: .planner, reason: reason, localObject: localObject, peerObject: peerObject, plan: &plan)
        let conflict = CanonicalLibraryConflict(
            kind: conflictKind,
            objectID: objectID,
            objectKind: objectKind,
            localHash: localObject.metadataHash,
            peerHash: peerObject.metadataHash,
            localModifiedAt: localObject.businessModifiedAt,
            peerModifiedAt: peerObject.businessModifiedAt,
            detail: reason
        )
        plan.conflicts.append(conflict)
        plan.applyActions.append(
            CanonicalApplyAction(
                kind: .conflictRecord,
                source: .planner,
                target: CanonicalApplyTarget(objectID: objectID.rawValue),
                result: .conflictRecorded,
                failureReason: .conflictDetected,
                conflictID: conflict.conflictID,
                reason: reason
            )
        )
        plan.diagnostics.append(
            CanonicalLibrarySyncDiagnostic(phase: "canonicalLibraryConflictRecorded", objectID: objectID, objectKind: objectKind, detail: conflictKind.rawValue)
        )
    }

    nonisolated private func appendUnsupported(
        objectID: CanonicalLibraryObjectID,
        object: CanonicalLibraryObject,
        plan: inout CanonicalLibrarySyncPlan
    ) {
        plan.fallbackRequiredObjectIDs.append(objectID)
        plan.actions.append(
            CanonicalLibrarySyncAction(
                kind: .unsupportedFallback,
                objectID: objectID,
                objectKind: object.kind,
                source: .planner,
                reason: object.unsupportedReason ?? "unsupportedLibraryObject",
                localHash: object.metadataHash
            )
        )
        plan.diagnostics.append(
            CanonicalLibrarySyncDiagnostic(
                phase: "canonicalLibraryObjectUnsupported",
                objectID: objectID,
                objectKind: object.kind,
                detail: object.unsupportedReason ?? "unsupportedLibraryObject"
            )
        )
    }

    nonisolated private func applyActionKind(for kind: CanonicalLibraryActionKind) -> CanonicalApplyActionKind? {
        switch kind {
        case .folderMetadataApply:
            return .folderMetadataApply
        case .folderMetadataSend:
            return .folderMetadataSend
        case .folderTombstoneApply:
            return .libraryTombstoneApply
        case .folderTombstoneSend:
            return .libraryTombstoneSend
        case .studyItemMetadataApply:
            return .studyItemMetadataApply
        case .studyItemMetadataSend:
            return .studyItemMetadataSend
        case .studyItemTombstoneApply:
            return .libraryTombstoneApply
        case .studyItemTombstoneSend:
            return .libraryTombstoneSend
        case .folderMetadataNoOp, .folderConflict, .studyItemMetadataNoOp, .studyItemConflict, .unsupportedFallback, .deferred:
            return nil
        }
    }

    nonisolated private func applyPreconditions(
        localObject: CanonicalLibraryObject?,
        peerObject: CanonicalLibraryObject?
    ) -> [CanonicalApplyPrecondition] {
        [
            localObject?.businessModifiedAt.map {
                CanonicalApplyPrecondition(kind: .localModifiedAt, value: timestampString($0))
            },
            peerObject?.businessModifiedAt.map {
                CanonicalApplyPrecondition(kind: .peerModifiedAt, value: timestampString($0))
            },
            localObject.map {
                CanonicalApplyPrecondition(kind: .localHashPrefix, value: String($0.metadataHash.value.prefix(12)))
            },
            peerObject.map {
                CanonicalApplyPrecondition(kind: .peerHashPrefix, value: String($0.metadataHash.value.prefix(12)))
            },
            CanonicalApplyPrecondition(kind: .legacyBridge, value: "metadataManifest")
        ].compactMap { $0 }
    }

    nonisolated private func libraryObjectsByID(_ objects: [CanonicalLibraryObject]) -> [CanonicalLibraryObjectID: CanonicalLibraryObject] {
        Dictionary(objects.map { ($0.objectID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    nonisolated private func combinedObjectIDs(local: CanonicalManifest, peer: CanonicalManifest) -> [CanonicalLibraryObjectID] {
        Array(Set(local.libraryObjects.map(\.objectID) + peer.libraryObjects.map(\.objectID))).sorted { $0.rawValue < $1.rawValue }
    }

    nonisolated private func hasLibraryCapability(_ manifest: CanonicalManifest) -> Bool {
        manifest.node.capabilities.contains(.canonicalLibraryObjectsV1)
            || manifest.manifestCapabilities.contains(.canonicalLibraryObjectsV1)
    }

    nonisolated private func isSupported(_ object: CanonicalLibraryObject) -> Bool {
        object.kind != .unknownUnsupported && object.kind != .generatedArtifactEnvelope
    }

    nonisolated private func sameHash(_ left: CanonicalHash, _ right: CanonicalHash) -> Bool {
        left.algorithm == right.algorithm && left.value == right.value
    }

    nonisolated private func libraryTombstone(
        object: CanonicalLibraryObject,
        reason: CanonicalLibraryTombstoneReason
    ) -> CanonicalLibraryTombstone {
        CanonicalLibraryTombstone(
            objectID: object.objectID,
            objectKind: object.kind,
            deletedAt: object.deletedAt,
            reason: reason
        )
    }

    nonisolated private func timestampString(_ timestamp: CanonicalTimestamp) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), timestamp.date.timeIntervalSince1970)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
