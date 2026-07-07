//
//  CanonicalSyncPlanner.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/1.
//

import Foundation

nonisolated enum CanonicalSyncPlanTrigger: String, Codable, Equatable, Sendable {
    case manual
    case periodic
    case appActivation
    case retryDrainer
    case viewRefresh

    var allowsAudioUpload: Bool {
        switch self {
        case .manual, .periodic, .appActivation:
            return true
        case .retryDrainer, .viewRefresh:
            return false
        }
    }
}

nonisolated enum CanonicalSyncPlanReason: String, Codable, Equatable, Sendable {
    case canonicalPlanUsed
    case canonicalPlanFallback
    case incompatibleSchema
    case invalidManifestHash
    case missingRecordingMetadataCapability
    case missingAudioArtifactCapability
    case canonicalMetadataHashConverged
    case canonicalCreatedAtIgnoredForMetadataHash
    case canonicalModifiedAtIgnoredProcessingState
    case canonicalBusinessModifiedAtUsed
    case peerMissingMetadata
    case localMissingMetadata
    case metadataHashEqual
    case localMetadataNewer
    case peerMetadataNewer
    case metadataTieConflict
    case legacyWouldUploadMetadataButCanonicalNoOp
    case legacyMetadataHashMismatchButCanonicalHashMatch
    case localAudioUnavailable
    case peerObjectAbsent
    case peerAudioMissing
    case peerAudioMetadataOnly
    case peerStudyItemOnlyWithoutReceiveRecord
    case peerAudioUnknownDeferred
    case peerAudioSameHashSameSize
    case peerAudioHashConflict
    case peerAudioSizeConflict
    case viewRefreshSuppressed
    case retryDrainerSuppressedNewJob
    case canonicalGeneratedArtifactDownload
    case canonicalGeneratedArtifactPeerSameNoOp
    case canonicalGeneratedArtifactPeerUnknownDeferred
    case canonicalGeneratedArtifactConflict
    case canonicalGeneratedArtifactUnsupportedUpload
    case canonicalGeneratedArtifactAuthoritativePeerNewer
    case canonicalGeneratedArtifactLocalProducerNoRoute
    case legacyWouldDownloadArtifactButCanonicalNoOp
    case legacyArtifactMismatchButCanonicalResolved
}

nonisolated enum CanonicalSyncPlanError: Error, Equatable {
    case incompatibleSchema(local: Int, peer: Int)
    case invalidManifestHash(side: String)
    case missingCapability(side: String, capability: CanonicalCapability)
}

nonisolated struct CanonicalRecordingMetadataAction: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(objectID):\(reason.rawValue)" }

    var objectID: String
    var reason: CanonicalSyncPlanReason
    var localMetadataHash: CanonicalHash?
    var peerMetadataHash: CanonicalHash?
    var localModifiedAt: CanonicalTimestamp?
    var peerModifiedAt: CanonicalTimestamp?
}

nonisolated struct CanonicalArtifactTransferAction: Codable, Equatable, Identifiable, Sendable {
    var id: String { "\(objectID):\(artifactID ?? "audio"):\(reason.rawValue)" }

    var objectID: String
    var artifactID: String?
    var kind: CanonicalArtifact.Kind?
    var logicalPathToken: String?
    var reason: CanonicalSyncPlanReason
    var localHash: CanonicalHash?
    var peerHash: CanonicalHash?
    var localByteSize: Int64?
    var peerByteSize: Int64?
}

nonisolated struct CanonicalSyncPlanBridgeDiagnostics: Codable, Equatable, Identifiable, Sendable {
    var id: String { [phase, reason.rawValue, objectID ?? "", artifactID ?? ""].joined(separator: "|") }

    var phase: String
    var reason: CanonicalSyncPlanReason
    var objectID: String?
    var artifactID: String?
    var detail: String?
}

nonisolated struct CanonicalSyncPlannerLegacyContext: Codable, Equatable, Sendable {
    var legacyUploadMetadataObjectIDs: [String]
    var legacyDownloadMetadataObjectIDs: [String]
    var legacyUploadAudioObjectIDs: [String]
    var legacyDownloadGeneratedArtifactKeys: [String]
    var legacyConflictGeneratedArtifactKeys: [String]
    var peerObjectFacts: [CanonicalShadowLegacyObjectFact]

    init(
        legacyUploadMetadataObjectIDs: [String] = [],
        legacyDownloadMetadataObjectIDs: [String] = [],
        legacyUploadAudioObjectIDs: [String] = [],
        legacyDownloadGeneratedArtifactKeys: [String] = [],
        legacyConflictGeneratedArtifactKeys: [String] = [],
        peerObjectFacts: [CanonicalShadowLegacyObjectFact] = []
    ) {
        self.legacyUploadMetadataObjectIDs = Self.normalizedIDs(legacyUploadMetadataObjectIDs)
        self.legacyDownloadMetadataObjectIDs = Self.normalizedIDs(legacyDownloadMetadataObjectIDs)
        self.legacyUploadAudioObjectIDs = Self.normalizedIDs(legacyUploadAudioObjectIDs)
        self.legacyDownloadGeneratedArtifactKeys = Self.normalizedIDs(legacyDownloadGeneratedArtifactKeys)
        self.legacyConflictGeneratedArtifactKeys = Self.normalizedIDs(legacyConflictGeneratedArtifactKeys)
        self.peerObjectFacts = CanonicalShadowLegacyObjectFact.merged(peerObjectFacts)
    }

    func peerFact(for objectID: String) -> CanonicalShadowLegacyObjectFact? {
        peerObjectFacts.first { $0.objectID == objectID }
    }

    func legacyWouldMoveMetadata(for objectID: String) -> Bool {
        legacyUploadMetadataObjectIDs.contains(objectID) || legacyDownloadMetadataObjectIDs.contains(objectID)
    }

    func legacyWouldDownloadGeneratedArtifact(objectID: String, kind: CanonicalArtifact.Kind) -> Bool {
        legacyDownloadGeneratedArtifactKeys.contains(CanonicalProjectionContract.artifactKey(objectID: objectID, kind: kind))
    }

    func legacyHadGeneratedArtifactConflict(objectID: String, kind: CanonicalArtifact.Kind) -> Bool {
        legacyConflictGeneratedArtifactKeys.contains(CanonicalProjectionContract.artifactKey(objectID: objectID, kind: kind))
    }

    private static func normalizedIDs(_ ids: [String]) -> [String] {
        Array(Set(ids.compactMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        })).sorted()
    }
}

nonisolated struct CanonicalSyncPlan: Codable, Equatable, Sendable {
    var uploadRecordingMetadata: [CanonicalRecordingMetadataAction] = []
    var downloadRecordingMetadata: [CanonicalRecordingMetadataAction] = []
    var noOpRecordingMetadata: [CanonicalRecordingMetadataAction] = []
    var conflictRecordingMetadata: [CanonicalRecordingMetadataAction] = []
    var uploadAudioArtifact: [CanonicalArtifactTransferAction] = []
    var deferAudioArtifact: [CanonicalArtifactTransferAction] = []
    var noOpAudioArtifact: [CanonicalArtifactTransferAction] = []
    var conflictAudioArtifact: [CanonicalArtifactTransferAction] = []
    var downloadGeneratedArtifact: [CanonicalArtifactTransferAction] = []
    var deferGeneratedArtifact: [CanonicalArtifactTransferAction] = []
    var noOpGeneratedArtifact: [CanonicalArtifactTransferAction] = []
    var conflictGeneratedArtifact: [CanonicalArtifactTransferAction] = []
    var diagnostics: [CanonicalSyncPlanBridgeDiagnostics] = []
}

nonisolated struct CanonicalSyncPlanner {
    init() {}

    func plan(
        local: CanonicalManifest,
        peer: CanonicalManifest,
        trigger: CanonicalSyncPlanTrigger,
        legacyContext: CanonicalSyncPlannerLegacyContext? = nil
    ) throws -> CanonicalSyncPlan {
        try validate(local: local, peer: peer)

        let localObjects = Dictionary(uniqueKeysWithValues: local.objects.map { ($0.objectID, $0) })
        let peerObjects = Dictionary(uniqueKeysWithValues: peer.objects.map { ($0.objectID, $0) })
        let objectIDs = Set(localObjects.keys).union(peerObjects.keys).sorted()
        var plan = CanonicalSyncPlan()
        plan.diagnostics.append(
            CanonicalSyncPlanBridgeDiagnostics(
                phase: "canonicalPlanUsed",
                reason: .canonicalPlanUsed,
                objectID: nil,
                artifactID: nil,
                detail: "objects=\(objectIDs.count)"
            )
        )

        for objectID in objectIDs {
            let localObject = localObjects[objectID]
            let peerObject = peerObjects[objectID]
            appendMetadataDecision(
                objectID: objectID,
                localObject: localObject,
                peerObject: peerObject,
                legacyContext: legacyContext,
                plan: &plan
            )
            if let localObject {
                appendAudioDecision(
                    objectID: objectID,
                    localObject: localObject,
                    peerObject: peerObject,
                    trigger: trigger,
                    legacyContext: legacyContext,
                    plan: &plan
                )
            }
            appendGeneratedArtifactDecisions(
                objectID: objectID,
                localObject: localObject,
                peerObject: peerObject,
                localNode: local.node,
                peerNode: peer.node,
                trigger: trigger,
                legacyContext: legacyContext,
                plan: &plan
            )
        }

        return plan
    }

    private func validate(local: CanonicalManifest, peer: CanonicalManifest) throws {
        guard local.schemaVersion == CanonicalManifest.currentSchemaVersion,
              peer.schemaVersion == CanonicalManifest.currentSchemaVersion else {
            throw CanonicalSyncPlanError.incompatibleSchema(local: local.schemaVersion, peer: peer.schemaVersion)
        }
        guard local.hasValidManifestHash else {
            throw CanonicalSyncPlanError.invalidManifestHash(side: "local")
        }
        guard peer.hasValidManifestHash else {
            throw CanonicalSyncPlanError.invalidManifestHash(side: "peer")
        }
        guard local.node.capabilities.contains(.recordingMetadata) else {
            throw CanonicalSyncPlanError.missingCapability(side: "local", capability: .recordingMetadata)
        }
        guard peer.node.capabilities.contains(.recordingMetadata) else {
            throw CanonicalSyncPlanError.missingCapability(side: "peer", capability: .recordingMetadata)
        }
        guard local.node.capabilities.contains(.audioArtifact) else {
            throw CanonicalSyncPlanError.missingCapability(side: "local", capability: .audioArtifact)
        }
        guard peer.node.capabilities.contains(.audioArtifact) else {
            throw CanonicalSyncPlanError.missingCapability(side: "peer", capability: .audioArtifact)
        }
    }

    private func appendMetadataDecision(
        objectID: String,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?,
        legacyContext: CanonicalSyncPlannerLegacyContext?,
        plan: inout CanonicalSyncPlan
    ) {
        switch (localObject, peerObject) {
        case let (.some(localObject), .some(peerObject)):
            if sameHash(localObject.metadataHash, peerObject.metadataHash) {
                let action = metadataAction(objectID: objectID, reason: .metadataHashEqual, localObject: localObject, peerObject: peerObject)
                plan.noOpRecordingMetadata.append(action)
                plan.diagnostics.append(
                    CanonicalSyncPlanBridgeDiagnostics(
                        phase: "canonicalMetadataHashConverged",
                        reason: .canonicalMetadataHashConverged,
                        objectID: objectID,
                        artifactID: nil,
                        detail: "canonicalMetadataHash=\(hashPrefix(localObject.metadataHash))"
                    )
                )
                if localObject.metadata.createdAt != peerObject.metadata.createdAt {
                    plan.diagnostics.append(
                        CanonicalSyncPlanBridgeDiagnostics(
                            phase: "canonicalCreatedAtIgnoredForMetadataHash",
                            reason: .canonicalCreatedAtIgnoredForMetadataHash,
                            objectID: objectID,
                            artifactID: nil,
                            detail: "canonicalMetadataHash=\(hashPrefix(localObject.metadataHash))"
                        )
                    )
                }
                if localObject.processingState != peerObject.processingState {
                    plan.diagnostics.append(
                        CanonicalSyncPlanBridgeDiagnostics(
                            phase: "canonicalModifiedAtIgnoredProcessingState",
                            reason: .canonicalModifiedAtIgnoredProcessingState,
                            objectID: objectID,
                            artifactID: nil,
                            detail: "canonicalMetadataHash=\(hashPrefix(localObject.metadataHash))"
                        )
                    )
                }
                if legacyContext?.legacyWouldMoveMetadata(for: objectID) == true {
                    plan.diagnostics.append(
                        CanonicalSyncPlanBridgeDiagnostics(
                            phase: "legacyWouldUploadMetadataButCanonicalNoOp",
                            reason: .legacyWouldUploadMetadataButCanonicalNoOp,
                            objectID: objectID,
                            artifactID: nil,
                            detail: "canonicalMetadataHash=\(hashPrefix(localObject.metadataHash))"
                        )
                    )
                    plan.diagnostics.append(
                        CanonicalSyncPlanBridgeDiagnostics(
                            phase: "legacyMetadataHashMismatchButCanonicalHashMatch",
                            reason: .legacyMetadataHashMismatchButCanonicalHashMatch,
                            objectID: objectID,
                            artifactID: nil,
                            detail: "canonicalMetadataHash=\(hashPrefix(localObject.metadataHash))"
                        )
                    )
                }
            } else if localObject.metadata.modifiedAt > peerObject.metadata.modifiedAt {
                plan.uploadRecordingMetadata.append(metadataAction(objectID: objectID, reason: .localMetadataNewer, localObject: localObject, peerObject: peerObject))
                appendBusinessModifiedAtDiagnostic(
                    objectID: objectID,
                    direction: "upload",
                    localObject: localObject,
                    peerObject: peerObject,
                    plan: &plan
                )
            } else if peerObject.metadata.modifiedAt > localObject.metadata.modifiedAt {
                plan.downloadRecordingMetadata.append(metadataAction(objectID: objectID, reason: .peerMetadataNewer, localObject: localObject, peerObject: peerObject))
                appendBusinessModifiedAtDiagnostic(
                    objectID: objectID,
                    direction: "download",
                    localObject: localObject,
                    peerObject: peerObject,
                    plan: &plan
                )
            } else {
                plan.conflictRecordingMetadata.append(metadataAction(objectID: objectID, reason: .metadataTieConflict, localObject: localObject, peerObject: peerObject))
            }
        case let (.some(localObject), .none):
            plan.uploadRecordingMetadata.append(metadataAction(objectID: objectID, reason: .peerMissingMetadata, localObject: localObject, peerObject: nil))
        case let (.none, .some(peerObject)):
            plan.downloadRecordingMetadata.append(metadataAction(objectID: objectID, reason: .localMissingMetadata, localObject: nil, peerObject: peerObject))
        case (.none, .none):
            break
        }
    }

    private func appendAudioDecision(
        objectID: String,
        localObject: CanonicalRecordingObject,
        peerObject: CanonicalRecordingObject?,
        trigger: CanonicalSyncPlanTrigger,
        legacyContext: CanonicalSyncPlannerLegacyContext?,
        plan: inout CanonicalSyncPlan
    ) {
        guard let localAudio = localObject.audioArtifact,
              localAudio.provesCanonicalAudioAvailability else {
            plan.deferAudioArtifact.append(audioAction(objectID: objectID, localAudio: localObject.audioArtifact, peerAudio: peerObject?.audioArtifact, reason: .localAudioUnavailable))
            return
        }

        if trigger == .viewRefresh {
            plan.deferAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: peerObject?.audioArtifact, reason: .viewRefreshSuppressed))
            return
        }

        if trigger == .retryDrainer {
            plan.deferAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: peerObject?.audioArtifact, reason: .retryDrainerSuppressedNewJob))
            return
        }

        guard let peerObject else {
            plan.uploadAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: nil, reason: .peerObjectAbsent))
            return
        }

        guard let peerAudio = peerObject.audioArtifact else {
            plan.uploadAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: nil, reason: peerAudioMissingReason(objectID: objectID, legacyContext: legacyContext)))
            return
        }

        switch peerAudio.availability {
        case .missing:
            plan.uploadAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: peerAudio, reason: peerAudioMissingReason(objectID: objectID, legacyContext: legacyContext)))
        case .unknown, .availableWithoutHash:
            plan.deferAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: peerAudio, reason: .peerAudioUnknownDeferred))
        case .available:
            guard peerAudio.contentHash != nil, peerAudio.byteSize != nil else {
                plan.deferAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: peerAudio, reason: .peerAudioUnknownDeferred))
                return
            }
            if !sameHash(localAudio.contentHash, peerAudio.contentHash) {
                plan.conflictAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: peerAudio, reason: .peerAudioHashConflict))
            } else if localAudio.byteSize != peerAudio.byteSize {
                plan.conflictAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: peerAudio, reason: .peerAudioSizeConflict))
            } else {
                plan.noOpAudioArtifact.append(audioAction(objectID: objectID, localAudio: localAudio, peerAudio: peerAudio, reason: .peerAudioSameHashSameSize))
            }
        }
    }

    private func appendGeneratedArtifactDecisions(
        objectID: String,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?,
        localNode: CanonicalNode,
        peerNode: CanonicalNode,
        trigger: CanonicalSyncPlanTrigger,
        legacyContext: CanonicalSyncPlannerLegacyContext?,
        plan: inout CanonicalSyncPlan
    ) {
        let localArtifacts = generatedArtifactsByKind(localObject)
        let peerArtifacts = generatedArtifactsByKind(peerObject)
        let kinds = Set(localArtifacts.keys).union(peerArtifacts.keys).sorted { $0.rawValue < $1.rawValue }
        for kind in kinds {
            appendGeneratedArtifactDecision(
                objectID: objectID,
                kind: kind,
                localArtifact: localArtifacts[kind],
                peerArtifact: peerArtifacts[kind],
                localNode: localNode,
                peerNode: peerNode,
                trigger: trigger,
                legacyContext: legacyContext,
                plan: &plan
            )
        }
    }

    private func appendGeneratedArtifactDecision(
        objectID: String,
        kind: CanonicalArtifact.Kind,
        localArtifact: CanonicalArtifact?,
        peerArtifact: CanonicalArtifact?,
        localNode: CanonicalNode,
        peerNode: CanonicalNode,
        trigger: CanonicalSyncPlanTrigger,
        legacyContext: CanonicalSyncPlannerLegacyContext?,
        plan: inout CanonicalSyncPlan
    ) {
        if localArtifact?.tombstone == true || peerArtifact?.tombstone == true {
            appendGeneratedDefer(
                objectID: objectID,
                kind: kind,
                localArtifact: localArtifact,
                peerArtifact: peerArtifact,
                reason: .canonicalGeneratedArtifactPeerUnknownDeferred,
                detail: "tombstonePresent",
                plan: &plan
            )
            return
        }

        let localProven = CanonicalProjectionContract.provesGeneratedArtifactAvailability(localArtifact)
        let peerProven = CanonicalProjectionContract.provesGeneratedArtifactAvailability(peerArtifact)
        let peerAuthoritative = peerArtifact.map { CanonicalProjectionContract.isAuthoritativeProducer($0, node: peerNode) } ?? false
        let localAuthoritative = localArtifact.map { CanonicalProjectionContract.isAuthoritativeProducer($0, node: localNode) } ?? false

        if peerProven, !localProven {
            if localArtifact == nil || localArtifact?.availability == .missing {
                appendGeneratedDownloadIfAllowed(
                    objectID: objectID,
                    kind: kind,
                    localArtifact: localArtifact,
                    peerArtifact: peerArtifact,
                    trigger: trigger,
                    reason: .canonicalGeneratedArtifactDownload,
                    detail: "localMissingPeerAvailable",
                    legacyContext: legacyContext,
                    plan: &plan
                )
            } else if peerAuthoritative {
                appendGeneratedDownloadIfAllowed(
                    objectID: objectID,
                    kind: kind,
                    localArtifact: localArtifact,
                    peerArtifact: peerArtifact,
                    trigger: trigger,
                    reason: .canonicalGeneratedArtifactDownload,
                    detail: "localUnknownPeerAuthoritative",
                    legacyContext: legacyContext,
                    plan: &plan
                )
            } else {
                appendGeneratedDefer(
                    objectID: objectID,
                    kind: kind,
                    localArtifact: localArtifact,
                    peerArtifact: peerArtifact,
                    reason: .canonicalGeneratedArtifactPeerUnknownDeferred,
                    detail: "localUnknownPeerNotAuthoritative",
                    plan: &plan
                )
            }
            return
        }

        if !peerProven {
            if let peerArtifact, peerArtifact.availability != .missing {
                appendGeneratedDefer(
                    objectID: objectID,
                    kind: kind,
                    localArtifact: localArtifact,
                    peerArtifact: peerArtifact,
                    reason: .canonicalGeneratedArtifactPeerUnknownDeferred,
                    detail: "peerUnproven",
                    plan: &plan
                )
            } else if localProven, localAuthoritative {
                appendGeneratedDefer(
                    objectID: objectID,
                    kind: kind,
                    localArtifact: localArtifact,
                    peerArtifact: peerArtifact,
                    reason: .canonicalGeneratedArtifactLocalProducerNoRoute,
                    detail: "localAuthoritativeUploadUnsupported",
                    plan: &plan
                )
                appendGeneratedDiagnostic(
                    objectID: objectID,
                    artifactID: localArtifact?.artifactID ?? peerArtifact?.artifactID,
                    kind: kind,
                    reason: .canonicalGeneratedArtifactUnsupportedUpload,
                    localArtifact: localArtifact,
                    peerArtifact: peerArtifact,
                    detail: "generatedArtifactUploadNotPlanned",
                    plan: &plan
                )
            } else if localProven {
                appendGeneratedDefer(
                    objectID: objectID,
                    kind: kind,
                    localArtifact: localArtifact,
                    peerArtifact: peerArtifact,
                    reason: .canonicalGeneratedArtifactUnsupportedUpload,
                    detail: "localGeneratedArtifactNotAuthoritative",
                    plan: &plan
                )
            } else {
                appendGeneratedDefer(
                    objectID: objectID,
                    kind: kind,
                    localArtifact: localArtifact,
                    peerArtifact: peerArtifact,
                    reason: .canonicalGeneratedArtifactPeerUnknownDeferred,
                    detail: "bothUnproven",
                    plan: &plan
                )
            }
            return
        }

        guard let localArtifact, let peerArtifact else {
            return
        }

        if CanonicalProjectionContract.sameContent(localArtifact, peerArtifact) {
            let action = generatedAction(
                objectID: objectID,
                kind: kind,
                localArtifact: localArtifact,
                peerArtifact: peerArtifact,
                reason: .canonicalGeneratedArtifactPeerSameNoOp
            )
            plan.noOpGeneratedArtifact.append(action)
            appendGeneratedDiagnostic(
                action,
                detail: "sameHashAndSize",
                plan: &plan
            )
            if legacyContext?.legacyWouldDownloadGeneratedArtifact(objectID: objectID, kind: kind) == true {
                appendGeneratedDiagnostic(
                    action,
                    reason: .legacyWouldDownloadArtifactButCanonicalNoOp,
                    detail: "canonicalGeneratedArtifactSame",
                    plan: &plan
                )
            }
            return
        }

        if peerAuthoritative,
           let peerModifiedAt = peerArtifact.modifiedAt,
           let localModifiedAt = localArtifact.modifiedAt,
           peerModifiedAt > localModifiedAt {
            appendGeneratedDownloadIfAllowed(
                objectID: objectID,
                kind: kind,
                localArtifact: localArtifact,
                peerArtifact: peerArtifact,
                trigger: trigger,
                reason: .canonicalGeneratedArtifactAuthoritativePeerNewer,
                detail: "peerAuthoritativeNewer",
                legacyContext: legacyContext,
                plan: &plan
            )
            if legacyContext?.legacyHadGeneratedArtifactConflict(objectID: objectID, kind: kind) == true {
                appendGeneratedDiagnostic(
                    objectID: objectID,
                    artifactID: peerArtifact.artifactID,
                    kind: kind,
                    reason: .legacyArtifactMismatchButCanonicalResolved,
                    localArtifact: localArtifact,
                    peerArtifact: peerArtifact,
                    detail: "peerAuthoritativeNewer",
                    plan: &plan
                )
            }
            return
        }

        if localAuthoritative,
           let peerModifiedAt = peerArtifact.modifiedAt,
           let localModifiedAt = localArtifact.modifiedAt,
           localModifiedAt > peerModifiedAt {
            appendGeneratedDefer(
                objectID: objectID,
                kind: kind,
                localArtifact: localArtifact,
                peerArtifact: peerArtifact,
                reason: .canonicalGeneratedArtifactLocalProducerNoRoute,
                detail: "localAuthoritativeNewerUploadUnsupported",
                plan: &plan
            )
            return
        }

        let action = generatedAction(
            objectID: objectID,
            kind: kind,
            localArtifact: localArtifact,
            peerArtifact: peerArtifact,
            reason: .canonicalGeneratedArtifactConflict
        )
        plan.conflictGeneratedArtifact.append(action)
        appendGeneratedDiagnostic(action, detail: "hashOrSizeMismatch", plan: &plan)
    }

    private func appendGeneratedDownloadIfAllowed(
        objectID: String,
        kind: CanonicalArtifact.Kind,
        localArtifact: CanonicalArtifact?,
        peerArtifact: CanonicalArtifact?,
        trigger: CanonicalSyncPlanTrigger,
        reason: CanonicalSyncPlanReason,
        detail: String,
        legacyContext: CanonicalSyncPlannerLegacyContext?,
        plan: inout CanonicalSyncPlan
    ) {
        if trigger == .viewRefresh {
            appendGeneratedDefer(
                objectID: objectID,
                kind: kind,
                localArtifact: localArtifact,
                peerArtifact: peerArtifact,
                reason: .viewRefreshSuppressed,
                detail: detail,
                plan: &plan
            )
            return
        }
        if trigger == .retryDrainer {
            appendGeneratedDefer(
                objectID: objectID,
                kind: kind,
                localArtifact: localArtifact,
                peerArtifact: peerArtifact,
                reason: .retryDrainerSuppressedNewJob,
                detail: detail,
                plan: &plan
            )
            return
        }
        let action = generatedAction(
            objectID: objectID,
            kind: kind,
            localArtifact: localArtifact,
            peerArtifact: peerArtifact,
            reason: reason
        )
        plan.downloadGeneratedArtifact.append(action)
        appendGeneratedDiagnostic(action, detail: detail, plan: &plan)
        if legacyContext?.legacyHadGeneratedArtifactConflict(objectID: objectID, kind: kind) == true {
            appendGeneratedDiagnostic(
                action,
                reason: .legacyArtifactMismatchButCanonicalResolved,
                detail: detail,
                plan: &plan
            )
        }
    }

    private func appendGeneratedDefer(
        objectID: String,
        kind: CanonicalArtifact.Kind,
        localArtifact: CanonicalArtifact?,
        peerArtifact: CanonicalArtifact?,
        reason: CanonicalSyncPlanReason,
        detail: String,
        plan: inout CanonicalSyncPlan
    ) {
        let action = generatedAction(
            objectID: objectID,
            kind: kind,
            localArtifact: localArtifact,
            peerArtifact: peerArtifact,
            reason: reason
        )
        plan.deferGeneratedArtifact.append(action)
        appendGeneratedDiagnostic(action, detail: detail, plan: &plan)
    }

    private func generatedArtifactsByKind(_ object: CanonicalRecordingObject?) -> [CanonicalArtifact.Kind: CanonicalArtifact] {
        guard let object else {
            return [:]
        }
        return object.artifacts.reduce(into: [CanonicalArtifact.Kind: CanonicalArtifact]()) { result, artifact in
            guard CanonicalProjectionContract.generatedArtifactKinds.contains(artifact.kind) else {
                return
            }
            let existing = result[artifact.kind]
            if existing == nil || (artifact.modifiedAt ?? CanonicalTimestamp(Date(timeIntervalSince1970: 0))) > (existing?.modifiedAt ?? CanonicalTimestamp(Date(timeIntervalSince1970: 0))) {
                result[artifact.kind] = artifact
            }
        }
    }

    private func peerAudioMissingReason(
        objectID: String,
        legacyContext: CanonicalSyncPlannerLegacyContext?
    ) -> CanonicalSyncPlanReason {
        guard let fact = legacyContext?.peerFact(for: objectID) else {
            return .peerAudioMissing
        }
        if fact.hasStudyItem && !fact.hasReceiveRecord {
            return .peerStudyItemOnlyWithoutReceiveRecord
        }
        if fact.hasReceiveRecord {
            return .peerAudioMetadataOnly
        }
        return .peerAudioMissing
    }

    private func metadataAction(
        objectID: String,
        reason: CanonicalSyncPlanReason,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?
    ) -> CanonicalRecordingMetadataAction {
        CanonicalRecordingMetadataAction(
            objectID: objectID,
            reason: reason,
            localMetadataHash: localObject?.metadataHash,
            peerMetadataHash: peerObject?.metadataHash,
            localModifiedAt: localObject?.metadata.modifiedAt,
            peerModifiedAt: peerObject?.metadata.modifiedAt
        )
    }

    private func audioAction(
        objectID: String,
        localAudio: CanonicalArtifact?,
        peerAudio: CanonicalArtifact?,
        reason: CanonicalSyncPlanReason
    ) -> CanonicalArtifactTransferAction {
        CanonicalArtifactTransferAction(
            objectID: objectID,
            artifactID: localAudio?.artifactID ?? peerAudio?.artifactID,
            kind: .audio,
            logicalPathToken: nil,
            reason: reason,
            localHash: localAudio?.contentHash,
            peerHash: peerAudio?.contentHash,
            localByteSize: localAudio?.byteSize,
            peerByteSize: peerAudio?.byteSize
        )
    }

    private func generatedAction(
        objectID: String,
        kind: CanonicalArtifact.Kind,
        localArtifact: CanonicalArtifact?,
        peerArtifact: CanonicalArtifact?,
        reason: CanonicalSyncPlanReason
    ) -> CanonicalArtifactTransferAction {
        CanonicalArtifactTransferAction(
            objectID: objectID,
            artifactID: peerArtifact?.artifactID ?? localArtifact?.artifactID ?? CanonicalProjectionContract.artifactID(objectID: objectID, kind: kind),
            kind: kind,
            logicalPathToken: peerArtifact?.logicalPathToken ?? localArtifact?.logicalPathToken,
            reason: reason,
            localHash: localArtifact?.contentHash,
            peerHash: peerArtifact?.contentHash,
            localByteSize: localArtifact?.byteSize,
            peerByteSize: peerArtifact?.byteSize
        )
    }

    private func appendGeneratedDiagnostic(
        _ action: CanonicalArtifactTransferAction,
        reason overrideReason: CanonicalSyncPlanReason? = nil,
        detail: String,
        plan: inout CanonicalSyncPlan
    ) {
        plan.diagnostics.append(
            CanonicalSyncPlanBridgeDiagnostics(
                phase: (overrideReason ?? action.reason).rawValue,
                reason: overrideReason ?? action.reason,
                objectID: action.objectID,
                artifactID: action.artifactID,
                detail: [
                    "kind=\(action.kind?.rawValue ?? "unknown")",
                    "detail=\(detail)",
                    "localHash=\(hashPrefix(action.localHash))",
                    "peerHash=\(hashPrefix(action.peerHash))",
                    "localSize=\(action.localByteSize.map(String.init) ?? "missing")",
                    "peerSize=\(action.peerByteSize.map(String.init) ?? "missing")"
                ].joined(separator: ";")
            )
        )
    }

    private func appendGeneratedDiagnostic(
        objectID: String,
        artifactID: String?,
        kind: CanonicalArtifact.Kind,
        reason: CanonicalSyncPlanReason,
        localArtifact: CanonicalArtifact?,
        peerArtifact: CanonicalArtifact?,
        detail: String,
        plan: inout CanonicalSyncPlan
    ) {
        let action = generatedAction(
            objectID: objectID,
            kind: kind,
            localArtifact: localArtifact,
            peerArtifact: peerArtifact,
            reason: reason
        )
        var diagnosticAction = action
        diagnosticAction.artifactID = artifactID ?? action.artifactID
        appendGeneratedDiagnostic(diagnosticAction, reason: reason, detail: detail, plan: &plan)
    }

    private func appendBusinessModifiedAtDiagnostic(
        objectID: String,
        direction: String,
        localObject: CanonicalRecordingObject,
        peerObject: CanonicalRecordingObject,
        plan: inout CanonicalSyncPlan
    ) {
        plan.diagnostics.append(
            CanonicalSyncPlanBridgeDiagnostics(
                phase: "canonicalBusinessModifiedAtUsed",
                reason: .canonicalBusinessModifiedAtUsed,
                objectID: objectID,
                artifactID: nil,
                detail: [
                    "direction=\(direction)",
                    "localModifiedAt=\(timestampSeconds(localObject.metadata.modifiedAt))",
                    "peerModifiedAt=\(timestampSeconds(peerObject.metadata.modifiedAt))"
                ].joined(separator: ";")
            )
        )
    }

    private func sameHash(_ left: CanonicalHash, _ right: CanonicalHash) -> Bool {
        left.algorithm == right.algorithm && left.value == right.value
    }

    private func sameHash(_ left: CanonicalHash?, _ right: CanonicalHash?) -> Bool {
        left?.algorithm == right?.algorithm && left?.value == right?.value
    }

    private func hashPrefix(_ hash: CanonicalHash?) -> String {
        guard let value = hash?.value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return "missing"
        }
        return String(value.prefix(12))
    }

    private func timestampSeconds(_ timestamp: CanonicalTimestamp) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), timestamp.date.timeIntervalSince1970)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
