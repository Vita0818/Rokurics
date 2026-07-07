//
//  CanonicalLibraryMetadataCutover.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/4.
//

import Foundation

nonisolated enum CanonicalLibraryMetadataCutoverDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case folderMetadata
    case studyItemMetadata
    case standaloneNoteMetadata

    nonisolated var productionDomain: CanonicalProductionDomain {
        switch self {
        case .folderMetadata: return .folders
        case .studyItemMetadata: return .studyItems
        case .standaloneNoteMetadata: return .standaloneNotes
        }
    }

    nonisolated var cutoverDomain: CanonicalCutoverDomain {
        switch self {
        case .folderMetadata: return .folders
        case .studyItemMetadata: return .studyItems
        case .standaloneNoteMetadata: return .standaloneNotes
        }
    }
}

nonisolated enum CanonicalLibraryMetadataCutoverActionKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case folderApply
    case folderSend
    case studyItemApply
    case studyItemSend
    case standaloneNoteApply
    case standaloneNoteSend
    case conflictRecord
    case tombstoneMarkerUnsupportedForThisRound
    case unsupported

    nonisolated var isExecutableMetadata: Bool {
        switch self {
        case .folderApply, .folderSend, .studyItemApply, .studyItemSend, .standaloneNoteApply, .standaloneNoteSend:
            return true
        case .conflictRecord, .tombstoneMarkerUnsupportedForThisRound, .unsupported:
            return false
        }
    }

    nonisolated var isSend: Bool {
        self == .folderSend || self == .studyItemSend || self == .standaloneNoteSend
    }

    nonisolated var isApply: Bool {
        self == .folderApply || self == .studyItemApply || self == .standaloneNoteApply
    }
}

nonisolated enum CanonicalLibraryMetadataCutoverFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable, Error {
    case disabled
    case unsupportedMode
    case unsupportedDomain
    case unsupportedObjectKind
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
    case activeVsTombstoneConflict
    case legacyFallbackUnavailable
    case missingMetadataManifestRouteEvidence
    case productionPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case rollbackVerificationMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case objectIDMismatch
    case objectKindMismatch
    case expectedMetadataHashMissing
    case expectedBusinessModifiedAtMissing
    case businessModifiedAtDirectionMismatch
    case applyFailureBeforeCommit
    case applyFailureAfterPartialCommit
    case postconditionMismatch
    case rollbackFailure
    case parentMissing
    case cycleDetected
    case resourceMoveAttempted
    case tombstoneUnsupportedForThisRound
    case conflictDetected
    case missingInternalCanaryConfiguration
    case canaryBudgetAboveOneDenied
    case missingCanaryStageEvidence
    case canaryStageBlocked
    case canaryStageOrderViolation
    case observationWindowIncomplete
    case previousStageFailure
    case previousStageRollbackFailure
    case previousStageBlockingDivergence
    case previousStageUnresolvedConflict
    case previousStagePostconditionFailure
    case previousStageUnsupportedObject
    case allEligibleCanaryDenied
    case activePilotNotLibraryMetadata
    case matrixValidationBlocked
    case defaultEnablementDenied
    case missingReadSideParallelEvidence
    case readSideParallelDivergence
    case multipleEligibleCandidatesDenied
    case folderHierarchyMutationUnsupported
    case standaloneNoteContentMutationUnsupported
    case commitExecutorUnavailable
    case objectIDInstability
    case runtimeSwitchDenied
    case peerSnapshotUnavailable
}

nonisolated struct CanonicalLibraryMetadataCutoverCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { action.actionID }

    var action: CanonicalApplyAction
    var localObject: CanonicalLibraryObject?
    var peerObject: CanonicalLibraryObject?
    var rollbackCheckpointID: String?
    var unresolvedConflict: Bool
    var parentMissingKnown: Bool
    var routePath: String

    nonisolated init(
        action: CanonicalApplyAction,
        localObject: CanonicalLibraryObject?,
        peerObject: CanonicalLibraryObject?,
        rollbackCheckpointID: String? = nil,
        unresolvedConflict: Bool = false,
        parentMissingKnown: Bool = false,
        routePath: String = "/sync/apply-metadata"
    ) {
        self.action = action
        self.localObject = localObject
        self.peerObject = peerObject
        self.rollbackCheckpointID = rollbackCheckpointID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "library-metadata-checkpoint")
        }
        self.unresolvedConflict = unresolvedConflict
        self.parentMissingKnown = parentMissingKnown
        self.routePath = CanonicalProductionRedaction.safeDiagnosticText(routePath) ?? "/sync/apply-metadata"
    }

    nonisolated var objectID: String {
        action.target.objectID
    }

    nonisolated var objectKind: CanonicalObjectKind {
        expectedObject?.kind ?? localObject?.kind ?? peerObject?.kind ?? inferredObjectKind
    }

    nonisolated var domain: CanonicalLibraryMetadataCutoverDomain {
        switch objectKind {
        case .folder:
            return .folderMetadata
        case .standaloneNote:
            return .standaloneNoteMetadata
        default:
            return .studyItemMetadata
        }
    }

    nonisolated var cutoverActionKind: CanonicalLibraryMetadataCutoverActionKind {
        switch action.kind {
        case .folderMetadataApply:
            return objectKind == .folder ? .folderApply : .unsupported
        case .folderMetadataSend:
            return objectKind == .folder ? .folderSend : .unsupported
        case .studyItemMetadataApply:
            return objectKind == .standaloneNote ? .standaloneNoteApply : .studyItemApply
        case .studyItemMetadataSend:
            return objectKind == .standaloneNote ? .standaloneNoteSend : .studyItemSend
        case .conflictRecord:
            return .conflictRecord
        case .libraryTombstoneApply, .libraryTombstoneSend:
            return .tombstoneMarkerUnsupportedForThisRound
        default:
            return .unsupported
        }
    }

    nonisolated var expectedObject: CanonicalLibraryObject? {
        switch action.source {
        case .peer:
            return peerObject ?? localObject
        case .local:
            return localObject ?? peerObject
        case .planner:
            return peerObject ?? localObject
        }
    }

    nonisolated var expectedMetadataHash: CanonicalHash? {
        expectedObject?.metadataHash
    }

    nonisolated var expectedBusinessModifiedAt: CanonicalTimestamp? {
        expectedObject?.businessModifiedAt
    }

    nonisolated var effectiveRollbackCheckpointID: String {
        rollbackCheckpointID ?? "library-metadata-cutover-\(objectID)-\(cutoverActionKind.rawValue)"
    }

    nonisolated var metadataTitle: String {
        expectedObject?.metadata?.title ?? "metadata"
    }

    nonisolated var parentSummary: String {
        guard let object = expectedObject else {
            return "parent=unknown"
        }
        if let folder = object.folder?.metadata {
            return "parent=\(folder.parentID?.rawValue ?? "root")"
        }
        if let item = object.studyItem?.metadata {
            let folders = item.folderIDs.map(\.rawValue).prefix(3).joined(separator: "|")
            let parentRefs = item.parentReferences.map { $0.parentID.rawValue }.prefix(3).joined(separator: "|")
            return "folders=\(folders.isEmpty ? "none" : folders),parents=\(parentRefs.isEmpty ? "none" : parentRefs)"
        }
        return "parent=none"
    }

    nonisolated var tagCount: Int {
        expectedObject?.studyItem?.metadata.tags.count ?? 0
    }

    nonisolated var filingSummary: String {
        expectedObject?.studyItem?.metadata.filingPath.components.joined(separator: "/") ?? "none"
    }

    nonisolated var colorSummary: String {
        expectedObject?.folder?.metadata.colorToken ?? "none"
    }

    nonisolated var logicalResourceTokens: [String] {
        expectedObject?.studyItem?.metadata.logicalResourceTokens ?? []
    }

    nonisolated var hasResourceMoveAttempt: Bool {
        guard let local = localObject?.studyItem?.metadata.logicalResourceTokens,
              let peer = peerObject?.studyItem?.metadata.logicalResourceTokens,
              !local.isEmpty || !peer.isEmpty else {
            return false
        }
        return local != peer
    }

    nonisolated var folderHierarchyMutationAttempted: Bool {
        guard let local = localObject?.folder?.metadata,
              let peer = peerObject?.folder?.metadata else {
            return false
        }
        return local.parentID != peer.parentID
            || local.hierarchyPath != peer.hierarchyPath
            || local.hierarchyLevel != peer.hierarchyLevel
    }

    nonisolated var hasObjectIDInstability: Bool {
        switch objectKind {
        case .folder:
            return expectedObject?.folder?.folderID.rawValue != objectID
        case .standaloneNote:
            return expectedObject?.standaloneNote?.noteID.rawValue != objectID
        case .standaloneStudyItem, .recordingAssociatedStudyItem:
            return expectedObject?.studyItem?.itemID.rawValue != objectID
        default:
            return false
        }
    }

    nonisolated var hasActiveVsTombstoneConflict: Bool {
        guard let localObject, let peerObject else {
            return false
        }
        return localObject.isDeleted != peerObject.isDeleted && cutoverActionKind == .conflictRecord
    }

    nonisolated static func candidates(
        from libraryPlan: CanonicalLibrarySyncPlan,
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest,
        rollbackCheckpointPrefix: String = "library-metadata-cutover"
    ) -> [CanonicalLibraryMetadataCutoverCandidate] {
        let localObjects = Dictionary(uniqueKeysWithValues: localManifest.libraryObjects.map { ($0.objectID, $0) })
        let peerObjects = Dictionary(uniqueKeysWithValues: peerManifest.libraryObjects.map { ($0.objectID, $0) })
        return libraryPlan.applyActions.compactMap { action in
            guard action.kind == .folderMetadataApply
                || action.kind == .folderMetadataSend
                || action.kind == .studyItemMetadataApply
                || action.kind == .studyItemMetadataSend
                || action.kind == .conflictRecord
                || action.kind == .libraryTombstoneApply
                || action.kind == .libraryTombstoneSend else {
                return nil
            }
            let objectID = CanonicalLibraryObjectID(action.target.objectID)
            return CanonicalLibraryMetadataCutoverCandidate(
                action: action,
                localObject: localObjects[objectID],
                peerObject: peerObjects[objectID],
                rollbackCheckpointID: "\(rollbackCheckpointPrefix)-\(action.target.objectID)"
            )
        }
    }

    nonisolated static func folderHierarchyCycleDetected(in candidates: [CanonicalLibraryMetadataCutoverCandidate]) -> Bool {
        var parentsByFolderID: [String: String] = [:]
        for candidate in candidates {
            guard let folder = candidate.expectedObject?.folder?.metadata else {
                continue
            }
            if folder.parentID?.rawValue == folder.folderID.rawValue {
                return true
            }
            if let parentID = folder.parentID?.rawValue {
                parentsByFolderID[folder.folderID.rawValue] = parentID
            }
        }
        for folderID in parentsByFolderID.keys {
            var seen = Set<String>()
            var cursor: String? = folderID
            while let current = cursor {
                if !seen.insert(current).inserted {
                    return true
                }
                cursor = parentsByFolderID[current]
            }
        }
        return false
    }

    nonisolated private var inferredObjectKind: CanonicalObjectKind {
        switch action.kind {
        case .folderMetadataApply, .folderMetadataSend:
            return .folder
        case .studyItemMetadataApply, .studyItemMetadataSend:
            return .standaloneStudyItem
        default:
            return .unknownUnsupported
        }
    }
}

extension CanonicalLibraryObject {
    nonisolated var metadata: CanonicalLibraryMetadata? {
        switch kind {
        case .folder:
            guard let metadata = folder?.metadata else { return nil }
            return CanonicalLibraryMetadata(
                objectID: objectID,
                objectKind: kind,
                title: metadata.name,
                metadataHash: metadata.metadataHash,
                businessModifiedAt: metadata.businessModifiedAt,
                isDeleted: metadata.isDeleted,
                deletedAt: metadata.deletedAt
            )
        case .standaloneStudyItem, .standaloneNote, .recordingAssociatedStudyItem:
            guard let metadata = studyItem?.metadata else { return nil }
            return CanonicalLibraryMetadata(
                objectID: objectID,
                objectKind: kind,
                title: metadata.title,
                metadataHash: metadata.metadataHash,
                businessModifiedAt: metadata.businessModifiedAt,
                isDeleted: metadata.isDeleted,
                deletedAt: metadata.deletedAt
            )
        default:
            return nil
        }
    }

}

nonisolated enum CanonicalLibraryMetadataApplyPortMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case dryRun
    case fakeInMemory
    case testRootBound
    case productionRootDisabled
    case productionRootBound
    case productionRootUnsupported

    nonisolated var isNonDryRunRootBound: Bool {
        self == .testRootBound || self == .productionRootBound
    }

    nonisolated var isDefaultDisabled: Bool {
        self == .disabled || self == .dryRun || self == .productionRootDisabled
    }
}

nonisolated struct CanonicalLibraryMetadataCutoverEvidence: Codable, Equatable, Sendable {
    var noCommitEvidenceAvailable: Bool
    var realDataShadowCopyVerified: Bool
    var executionShadowVerified: Bool
    var dryRunEquivalenceVerified: Bool
    var noBlockingDivergence: Bool
    var noUnresolvedConflict: Bool
    var metadataManifestRouteEvidenceAvailable: Bool
    var productionPortAvailable: Bool
    var realRootBoundApplyPortAvailable: Bool
    var applyPortMode: CanonicalLibraryMetadataApplyPortMode
    var rootBoundWriteAvailable: Bool
    var atomicReplaceAvailable: Bool
    var rollbackCheckpointAvailable: Bool
    var rollbackVerified: Bool
    var productionRootDisabledByDefault: Bool
    var testRootUsed: Bool
    var legacyFallbackAvailable: Bool
    var rollbackPlan: CanonicalRollbackPlan?
    var rollbackRehearsalPassed: Bool
    var readSideParallelEquivalent: Bool
    var canaryStageEvidence: CanonicalLibraryMetadataCanaryStageEvidence?

    nonisolated init(
        noCommitEvidenceAvailable: Bool = false,
        realDataShadowCopyVerified: Bool = false,
        executionShadowVerified: Bool = false,
        dryRunEquivalenceVerified: Bool = false,
        noBlockingDivergence: Bool = false,
        noUnresolvedConflict: Bool = false,
        metadataManifestRouteEvidenceAvailable: Bool = false,
        productionPortAvailable: Bool = false,
        realRootBoundApplyPortAvailable: Bool = false,
        applyPortMode: CanonicalLibraryMetadataApplyPortMode = .disabled,
        rootBoundWriteAvailable: Bool = false,
        atomicReplaceAvailable: Bool = false,
        rollbackCheckpointAvailable: Bool = false,
        rollbackVerified: Bool = false,
        productionRootDisabledByDefault: Bool = false,
        testRootUsed: Bool = false,
        legacyFallbackAvailable: Bool = false,
        rollbackPlan: CanonicalRollbackPlan? = nil,
        rollbackRehearsalPassed: Bool = false,
        readSideParallelEquivalent: Bool = false,
        canaryStageEvidence: CanonicalLibraryMetadataCanaryStageEvidence? = nil
    ) {
        self.noCommitEvidenceAvailable = noCommitEvidenceAvailable
        self.realDataShadowCopyVerified = realDataShadowCopyVerified
        self.executionShadowVerified = executionShadowVerified
        self.dryRunEquivalenceVerified = dryRunEquivalenceVerified
        self.noBlockingDivergence = noBlockingDivergence
        self.noUnresolvedConflict = noUnresolvedConflict
        self.metadataManifestRouteEvidenceAvailable = metadataManifestRouteEvidenceAvailable
        self.productionPortAvailable = productionPortAvailable
        self.realRootBoundApplyPortAvailable = realRootBoundApplyPortAvailable
        self.applyPortMode = applyPortMode
        self.rootBoundWriteAvailable = rootBoundWriteAvailable
        self.atomicReplaceAvailable = atomicReplaceAvailable
        self.rollbackCheckpointAvailable = rollbackCheckpointAvailable
        self.rollbackVerified = rollbackVerified
        self.productionRootDisabledByDefault = productionRootDisabledByDefault
        self.testRootUsed = testRootUsed
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.rollbackPlan = rollbackPlan
        self.rollbackRehearsalPassed = rollbackRehearsalPassed
        self.readSideParallelEquivalent = readSideParallelEquivalent
        self.canaryStageEvidence = canaryStageEvidence
    }

    nonisolated static func passing(rollbackPlan: CanonicalRollbackPlan) -> CanonicalLibraryMetadataCutoverEvidence {
        CanonicalLibraryMetadataCutoverEvidence(
            noCommitEvidenceAvailable: true,
            realDataShadowCopyVerified: true,
            executionShadowVerified: true,
            dryRunEquivalenceVerified: true,
            noBlockingDivergence: true,
            noUnresolvedConflict: true,
            metadataManifestRouteEvidenceAvailable: true,
            productionPortAvailable: true,
            realRootBoundApplyPortAvailable: true,
            applyPortMode: .testRootBound,
            rootBoundWriteAvailable: true,
            atomicReplaceAvailable: true,
            rollbackCheckpointAvailable: true,
            rollbackVerified: true,
            productionRootDisabledByDefault: true,
            testRootUsed: true,
            legacyFallbackAvailable: true,
            rollbackPlan: rollbackPlan,
            rollbackRehearsalPassed: true,
            readSideParallelEquivalent: true
        )
    }
}

nonisolated enum CanonicalLibraryMetadataCanaryStage: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case n1
    case n3
    case n10
    case allEligible

    nonisolated var isExecutable: Bool { self != .disabled }

    nonisolated var previousStage: CanonicalLibraryMetadataCanaryStage? {
        switch self {
        case .disabled: return nil
        case .n1: return .disabled
        case .n3: return .n1
        case .n10: return .n3
        case .allEligible: return .n10
        }
    }

    nonisolated var nominalCanaryBudget: Int {
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

nonisolated struct CanonicalLibraryMetadataCanaryStagePolicy: Codable, Equatable, Sendable {
    var requestedStage: CanonicalLibraryMetadataCanaryStage
    var allowCandidateExecution: Bool
    var runtimeSwitchEnabled: Bool

    nonisolated init(
        requestedStage: CanonicalLibraryMetadataCanaryStage = .disabled,
        allowCandidateExecution: Bool = false,
        runtimeSwitchEnabled: Bool = false
    ) {
        self.requestedStage = requestedStage
        self.allowCandidateExecution = allowCandidateExecution
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
    }

    nonisolated static let disabled = CanonicalLibraryMetadataCanaryStagePolicy()

    nonisolated var canaryBudget: Int {
        requestedStage.nominalCanaryBudget
    }
}

nonisolated enum CanonicalLibraryMetadataStageEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missing
    case incomplete
    case passed
    case failed
    case blocked
}

nonisolated struct CanonicalLibraryMetadataCanaryStageEvidence: Codable, Equatable, Sendable {
    var stage: CanonicalLibraryMetadataCanaryStage
    var previousStage: CanonicalLibraryMetadataCanaryStage?
    var status: CanonicalLibraryMetadataStageEvidenceStatus
    var successfulCommitCount: Int
    var failedCommitCount: Int
    var rollbackFailureCount: Int
    var blockingDivergenceCount: Int
    var unresolvedConflictCount: Int
    var postconditionFailureCount: Int
    var unsupportedObjectCount: Int
    var resourceMoveAttemptCount: Int
    var folderCycleCount: Int
    var objectIDInstabilityCount: Int
    var suppressedLegacyDuplicateCount: Int
    var readSideParallelDivergenceCount: Int
    var noCommitEvidenceAvailable: Bool
    var observationWindowComplete: Bool
    var observationWindowID: String?

    nonisolated init(
        stage: CanonicalLibraryMetadataCanaryStage,
        previousStage: CanonicalLibraryMetadataCanaryStage? = nil,
        status: CanonicalLibraryMetadataStageEvidenceStatus,
        successfulCommitCount: Int = 0,
        failedCommitCount: Int = 0,
        rollbackFailureCount: Int = 0,
        blockingDivergenceCount: Int = 0,
        unresolvedConflictCount: Int = 0,
        postconditionFailureCount: Int = 0,
        unsupportedObjectCount: Int = 0,
        resourceMoveAttemptCount: Int = 0,
        folderCycleCount: Int = 0,
        objectIDInstabilityCount: Int = 0,
        suppressedLegacyDuplicateCount: Int = 0,
        readSideParallelDivergenceCount: Int = 0,
        noCommitEvidenceAvailable: Bool = false,
        observationWindowComplete: Bool = false,
        observationWindowID: String? = nil
    ) {
        self.stage = stage
        self.previousStage = previousStage
        self.status = status
        self.successfulCommitCount = max(0, successfulCommitCount)
        self.failedCommitCount = max(0, failedCommitCount)
        self.rollbackFailureCount = max(0, rollbackFailureCount)
        self.blockingDivergenceCount = max(0, blockingDivergenceCount)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.postconditionFailureCount = max(0, postconditionFailureCount)
        self.unsupportedObjectCount = max(0, unsupportedObjectCount)
        self.resourceMoveAttemptCount = max(0, resourceMoveAttemptCount)
        self.folderCycleCount = max(0, folderCycleCount)
        self.objectIDInstabilityCount = max(0, objectIDInstabilityCount)
        self.suppressedLegacyDuplicateCount = max(0, suppressedLegacyDuplicateCount)
        self.readSideParallelDivergenceCount = max(0, readSideParallelDivergenceCount)
        self.noCommitEvidenceAvailable = noCommitEvidenceAvailable
        self.observationWindowComplete = observationWindowComplete
        self.observationWindowID = observationWindowID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "stage-observation")
        }
    }

    nonisolated static func passing(
        stage: CanonicalLibraryMetadataCanaryStage,
        successfulCommitCount: Int
    ) -> CanonicalLibraryMetadataCanaryStageEvidence {
        CanonicalLibraryMetadataCanaryStageEvidence(
            stage: stage,
            previousStage: stage.previousStage,
            status: .passed,
            successfulCommitCount: successfulCommitCount,
            noCommitEvidenceAvailable: true,
            observationWindowComplete: true,
            observationWindowID: "\(stage.rawValue)-observation"
        )
    }

    private enum CodingKeys: String, CodingKey {
        case stage
        case previousStage
        case status
        case successfulCommitCount
        case failedCommitCount
        case rollbackFailureCount
        case blockingDivergenceCount
        case unresolvedConflictCount
        case postconditionFailureCount
        case unsupportedObjectCount
        case resourceMoveAttemptCount
        case folderCycleCount
        case objectIDInstabilityCount
        case suppressedLegacyDuplicateCount
        case readSideParallelDivergenceCount
        case noCommitEvidenceAvailable
        case observationWindowComplete
        case observationWindowID
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            stage: try container.decode(CanonicalLibraryMetadataCanaryStage.self, forKey: .stage),
            previousStage: try container.decodeIfPresent(CanonicalLibraryMetadataCanaryStage.self, forKey: .previousStage),
            status: try container.decode(CanonicalLibraryMetadataStageEvidenceStatus.self, forKey: .status),
            successfulCommitCount: try container.decodeIfPresent(Int.self, forKey: .successfulCommitCount) ?? 0,
            failedCommitCount: try container.decodeIfPresent(Int.self, forKey: .failedCommitCount) ?? 0,
            rollbackFailureCount: try container.decodeIfPresent(Int.self, forKey: .rollbackFailureCount) ?? 0,
            blockingDivergenceCount: try container.decodeIfPresent(Int.self, forKey: .blockingDivergenceCount) ?? 0,
            unresolvedConflictCount: try container.decodeIfPresent(Int.self, forKey: .unresolvedConflictCount) ?? 0,
            postconditionFailureCount: try container.decodeIfPresent(Int.self, forKey: .postconditionFailureCount) ?? 0,
            unsupportedObjectCount: try container.decodeIfPresent(Int.self, forKey: .unsupportedObjectCount) ?? 0,
            resourceMoveAttemptCount: try container.decodeIfPresent(Int.self, forKey: .resourceMoveAttemptCount) ?? 0,
            folderCycleCount: try container.decodeIfPresent(Int.self, forKey: .folderCycleCount) ?? 0,
            objectIDInstabilityCount: try container.decodeIfPresent(Int.self, forKey: .objectIDInstabilityCount) ?? 0,
            suppressedLegacyDuplicateCount: try container.decodeIfPresent(Int.self, forKey: .suppressedLegacyDuplicateCount) ?? 0,
            readSideParallelDivergenceCount: try container.decodeIfPresent(Int.self, forKey: .readSideParallelDivergenceCount) ?? 0,
            noCommitEvidenceAvailable: try container.decodeIfPresent(Bool.self, forKey: .noCommitEvidenceAvailable) ?? false,
            observationWindowComplete: try container.decodeIfPresent(Bool.self, forKey: .observationWindowComplete) ?? false,
            observationWindowID: try container.decodeIfPresent(String.self, forKey: .observationWindowID)
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stage, forKey: .stage)
        try container.encodeIfPresent(previousStage, forKey: .previousStage)
        try container.encode(status, forKey: .status)
        try container.encode(successfulCommitCount, forKey: .successfulCommitCount)
        try container.encode(failedCommitCount, forKey: .failedCommitCount)
        try container.encode(rollbackFailureCount, forKey: .rollbackFailureCount)
        try container.encode(blockingDivergenceCount, forKey: .blockingDivergenceCount)
        try container.encode(unresolvedConflictCount, forKey: .unresolvedConflictCount)
        try container.encode(postconditionFailureCount, forKey: .postconditionFailureCount)
        try container.encode(unsupportedObjectCount, forKey: .unsupportedObjectCount)
        try container.encode(resourceMoveAttemptCount, forKey: .resourceMoveAttemptCount)
        try container.encode(folderCycleCount, forKey: .folderCycleCount)
        try container.encode(objectIDInstabilityCount, forKey: .objectIDInstabilityCount)
        try container.encode(suppressedLegacyDuplicateCount, forKey: .suppressedLegacyDuplicateCount)
        try container.encode(readSideParallelDivergenceCount, forKey: .readSideParallelDivergenceCount)
        try container.encode(noCommitEvidenceAvailable, forKey: .noCommitEvidenceAvailable)
        try container.encode(observationWindowComplete, forKey: .observationWindowComplete)
        try container.encodeIfPresent(observationWindowID, forKey: .observationWindowID)
    }
}

nonisolated enum CanonicalLibraryMetadataStageEvidenceProbeStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missing
    case equivalent
    case verified
    case divergent
    case blocked

    nonisolated var isPassing: Bool {
        self == .equivalent || self == .verified
    }
}

nonisolated enum CanonicalLibraryMetadataStageEvidenceBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingPreviousStageEvidence
    case observationWindowIncomplete
    case previousStageFailed
    case rollbackFailed
    case blockingDivergence
    case unresolvedConflict
    case postconditionFailed
    case unsupportedObject
    case resourceMoveAttempted
    case hierarchyCycle
    case objectIDInstability
    case missingNoCommitEvidence
    case dryRunEquivalenceMissing
    case executionShadowMissing
    case realDataShadowCopyMissing
    case readOnlyTransportProbeMissing
    case rollbackPlanMissing
    case productionApplyPortMissing
    case legacyFallbackMissing
    case readSideParallelDivergent
}

nonisolated struct CanonicalLibraryMetadataStageObservationWindow: Codable, Equatable, Sendable {
    var observationWindowID: String
    var complete: Bool

    nonisolated init(
        observationWindowID: String,
        complete: Bool
    ) {
        self.observationWindowID = CanonicalProductionRedaction.safeIdentifier(
            observationWindowID,
            fallback: "stage-observation"
        )
        self.complete = complete
    }
}

nonisolated struct CanonicalLibraryMetadataStageEvidenceReport: Codable, Equatable, Sendable {
    var previousStage: CanonicalLibraryMetadataCanaryStage?
    var requestedStage: CanonicalLibraryMetadataCanaryStage
    var previousStageSuccessCount: Int
    var previousStageFailureCount: Int
    var previousStageRollbackFailureCount: Int
    var previousStageBlockingDivergenceCount: Int
    var previousStageResourceMoveAttemptCount: Int
    var previousStageObjectIDInstabilityCount: Int
    var previousStageHierarchyCycleCount: Int
    var previousStageSuppressedLegacyDuplicateCount: Int
    var unresolvedConflictCount: Int
    var postconditionFailureCount: Int
    var unsupportedObjectCount: Int
    var dryRunEquivalenceStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus
    var executionShadowStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus
    var realDataShadowCopyStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus
    var readOnlyTransportProbeStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus
    var rollbackPlanStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus
    var productionApplyPortStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus
    var legacyFallbackStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus
    var readSideParallelStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus
    var observationWindow: CanonicalLibraryMetadataStageObservationWindow
    var blockers: [CanonicalLibraryMetadataStageEvidenceBlocker]
    var redacted: Bool

    nonisolated init(
        previousStage: CanonicalLibraryMetadataCanaryStage?,
        requestedStage: CanonicalLibraryMetadataCanaryStage,
        previousStageSuccessCount: Int = 0,
        previousStageFailureCount: Int = 0,
        previousStageRollbackFailureCount: Int = 0,
        previousStageBlockingDivergenceCount: Int = 0,
        previousStageResourceMoveAttemptCount: Int = 0,
        previousStageObjectIDInstabilityCount: Int = 0,
        previousStageHierarchyCycleCount: Int = 0,
        previousStageSuppressedLegacyDuplicateCount: Int = 0,
        unresolvedConflictCount: Int = 0,
        postconditionFailureCount: Int = 0,
        unsupportedObjectCount: Int = 0,
        dryRunEquivalenceStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus = .missing,
        executionShadowStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus = .missing,
        realDataShadowCopyStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus = .missing,
        readOnlyTransportProbeStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus = .missing,
        rollbackPlanStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus = .missing,
        productionApplyPortStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus = .missing,
        legacyFallbackStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus = .missing,
        readSideParallelStatus: CanonicalLibraryMetadataStageEvidenceProbeStatus = .missing,
        observationWindow: CanonicalLibraryMetadataStageObservationWindow = CanonicalLibraryMetadataStageObservationWindow(observationWindowID: "stage-observation", complete: false),
        blockers: [CanonicalLibraryMetadataStageEvidenceBlocker] = [],
        redacted: Bool = true
    ) {
        self.previousStage = previousStage
        self.requestedStage = requestedStage
        self.previousStageSuccessCount = max(0, previousStageSuccessCount)
        self.previousStageFailureCount = max(0, previousStageFailureCount)
        self.previousStageRollbackFailureCount = max(0, previousStageRollbackFailureCount)
        self.previousStageBlockingDivergenceCount = max(0, previousStageBlockingDivergenceCount)
        self.previousStageResourceMoveAttemptCount = max(0, previousStageResourceMoveAttemptCount)
        self.previousStageObjectIDInstabilityCount = max(0, previousStageObjectIDInstabilityCount)
        self.previousStageHierarchyCycleCount = max(0, previousStageHierarchyCycleCount)
        self.previousStageSuppressedLegacyDuplicateCount = max(0, previousStageSuppressedLegacyDuplicateCount)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.postconditionFailureCount = max(0, postconditionFailureCount)
        self.unsupportedObjectCount = max(0, unsupportedObjectCount)
        self.dryRunEquivalenceStatus = dryRunEquivalenceStatus
        self.executionShadowStatus = executionShadowStatus
        self.realDataShadowCopyStatus = realDataShadowCopyStatus
        self.readOnlyTransportProbeStatus = readOnlyTransportProbeStatus
        self.rollbackPlanStatus = rollbackPlanStatus
        self.productionApplyPortStatus = productionApplyPortStatus
        self.legacyFallbackStatus = legacyFallbackStatus
        self.readSideParallelStatus = readSideParallelStatus
        self.observationWindow = observationWindow
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.redacted = redacted
    }

    nonisolated static func from(
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        policy: CanonicalLibraryMetadataCanaryStagePolicy
    ) -> CanonicalLibraryMetadataStageEvidenceReport {
        let stageEvidence = evidence.canaryStageEvidence
        let expectedPreviousStage = policy.requestedStage.previousStage
        var blockers: [CanonicalLibraryMetadataStageEvidenceBlocker] = []
        if stageEvidence == nil {
            blockers.append(.missingPreviousStageEvidence)
        }
        if stageEvidence?.observationWindowComplete != true {
            blockers.append(.observationWindowIncomplete)
        }
        if (stageEvidence?.failedCommitCount ?? 0) > 0 {
            blockers.append(.previousStageFailed)
        }
        if (stageEvidence?.rollbackFailureCount ?? 0) > 0 {
            blockers.append(.rollbackFailed)
        }
        if (stageEvidence?.blockingDivergenceCount ?? 0) > 0 || !evidence.noBlockingDivergence {
            blockers.append(.blockingDivergence)
        }
        if (stageEvidence?.unresolvedConflictCount ?? 0) > 0 || !evidence.noUnresolvedConflict {
            blockers.append(.unresolvedConflict)
        }
        if (stageEvidence?.postconditionFailureCount ?? 0) > 0 {
            blockers.append(.postconditionFailed)
        }
        if (stageEvidence?.unsupportedObjectCount ?? 0) > 0 {
            blockers.append(.unsupportedObject)
        }
        if (stageEvidence?.resourceMoveAttemptCount ?? 0) > 0 {
            blockers.append(.resourceMoveAttempted)
        }
        if (stageEvidence?.folderCycleCount ?? 0) > 0 {
            blockers.append(.hierarchyCycle)
        }
        if (stageEvidence?.objectIDInstabilityCount ?? 0) > 0 {
            blockers.append(.objectIDInstability)
        }
        if !evidence.noCommitEvidenceAvailable {
            blockers.append(.missingNoCommitEvidence)
        }
        if !evidence.dryRunEquivalenceVerified {
            blockers.append(.dryRunEquivalenceMissing)
        }
        if !evidence.executionShadowVerified {
            blockers.append(.executionShadowMissing)
        }
        if !evidence.realDataShadowCopyVerified {
            blockers.append(.realDataShadowCopyMissing)
        }
        if !evidence.metadataManifestRouteEvidenceAvailable {
            blockers.append(.readOnlyTransportProbeMissing)
        }
        if evidence.rollbackPlan == nil || !evidence.rollbackCheckpointAvailable || !evidence.rollbackVerified || !evidence.rollbackRehearsalPassed {
            blockers.append(.rollbackPlanMissing)
        }
        if !evidence.productionPortAvailable || !evidence.realRootBoundApplyPortAvailable || !evidence.applyPortMode.isNonDryRunRootBound {
            blockers.append(.productionApplyPortMissing)
        }
        if !evidence.legacyFallbackAvailable {
            blockers.append(.legacyFallbackMissing)
        }
        if (stageEvidence?.readSideParallelDivergenceCount ?? 0) > 0 || !evidence.readSideParallelEquivalent {
            blockers.append(.readSideParallelDivergent)
        }
        return CanonicalLibraryMetadataStageEvidenceReport(
            previousStage: expectedPreviousStage,
            requestedStage: policy.requestedStage,
            previousStageSuccessCount: stageEvidence?.successfulCommitCount ?? 0,
            previousStageFailureCount: stageEvidence?.failedCommitCount ?? 0,
            previousStageRollbackFailureCount: stageEvidence?.rollbackFailureCount ?? 0,
            previousStageBlockingDivergenceCount: stageEvidence?.blockingDivergenceCount ?? 0,
            previousStageResourceMoveAttemptCount: stageEvidence?.resourceMoveAttemptCount ?? 0,
            previousStageObjectIDInstabilityCount: stageEvidence?.objectIDInstabilityCount ?? 0,
            previousStageHierarchyCycleCount: stageEvidence?.folderCycleCount ?? 0,
            previousStageSuppressedLegacyDuplicateCount: stageEvidence?.suppressedLegacyDuplicateCount ?? 0,
            unresolvedConflictCount: stageEvidence?.unresolvedConflictCount ?? 0,
            postconditionFailureCount: stageEvidence?.postconditionFailureCount ?? 0,
            unsupportedObjectCount: stageEvidence?.unsupportedObjectCount ?? 0,
            dryRunEquivalenceStatus: evidence.dryRunEquivalenceVerified ? .equivalent : .missing,
            executionShadowStatus: evidence.executionShadowVerified ? .verified : .missing,
            realDataShadowCopyStatus: evidence.realDataShadowCopyVerified ? .verified : .missing,
            readOnlyTransportProbeStatus: evidence.metadataManifestRouteEvidenceAvailable ? .verified : .missing,
            rollbackPlanStatus: blockers.contains(.rollbackPlanMissing) ? .missing : .verified,
            productionApplyPortStatus: blockers.contains(.productionApplyPortMissing) ? .missing : .verified,
            legacyFallbackStatus: evidence.legacyFallbackAvailable ? .verified : .missing,
            readSideParallelStatus: evidence.readSideParallelEquivalent ? .equivalent : .divergent,
            observationWindow: CanonicalLibraryMetadataStageObservationWindow(
                observationWindowID: stageEvidence?.observationWindowID ?? "\(policy.requestedStage.rawValue)-observation",
                complete: stageEvidence?.observationWindowComplete == true
            ),
            blockers: blockers,
            redacted: true
        )
    }

    nonisolated var canaryStageEvidence: CanonicalLibraryMetadataCanaryStageEvidence {
        CanonicalLibraryMetadataCanaryStageEvidence(
            stage: previousStage ?? .disabled,
            previousStage: previousStage?.previousStage,
            status: blockers.isEmpty ? .passed : .blocked,
            successfulCommitCount: previousStageSuccessCount,
            failedCommitCount: previousStageFailureCount,
            rollbackFailureCount: previousStageRollbackFailureCount,
            blockingDivergenceCount: previousStageBlockingDivergenceCount,
            unresolvedConflictCount: unresolvedConflictCount,
            postconditionFailureCount: postconditionFailureCount,
            unsupportedObjectCount: unsupportedObjectCount,
            resourceMoveAttemptCount: previousStageResourceMoveAttemptCount,
            folderCycleCount: previousStageHierarchyCycleCount,
            objectIDInstabilityCount: previousStageObjectIDInstabilityCount,
            suppressedLegacyDuplicateCount: previousStageSuppressedLegacyDuplicateCount,
            readSideParallelDivergenceCount: readSideParallelStatus == .divergent ? 1 : 0,
            noCommitEvidenceAvailable: !blockers.contains(.missingNoCommitEvidence),
            observationWindowComplete: observationWindow.complete,
            observationWindowID: observationWindow.observationWindowID
        )
    }

    nonisolated var diagnosticsSummary: String {
        [
            "previousStage=\(previousStage?.rawValue ?? "none")",
            "requestedStage=\(requestedStage.rawValue)",
            "successCount=\(previousStageSuccessCount)",
            "failureCount=\(previousStageFailureCount)",
            "rollbackFailureCount=\(previousStageRollbackFailureCount)",
            "resourceMoveCount=\(previousStageResourceMoveAttemptCount)",
            "objectIDInstabilityCount=\(previousStageObjectIDInstabilityCount)",
            "hierarchyCycleCount=\(previousStageHierarchyCycleCount)",
            "readSideParallel=\(readSideParallelStatus.rawValue)",
            "observationComplete=\(observationWindow.complete)",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=\(redacted)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalLibraryMetadataCanaryStageGate: Codable, Equatable, Sendable {
    var allowed: Bool
    var selectedCandidateLimit: Int
    var failures: [CanonicalLibraryMetadataCutoverFailure]

    nonisolated init(
        policy: CanonicalLibraryMetadataCanaryStagePolicy,
        evidence: CanonicalLibraryMetadataCutoverEvidence
    ) {
        var failures: [CanonicalLibraryMetadataCutoverFailure] = []
        if !policy.requestedStage.isExecutable {
            failures.append(.disabled)
        }
        if policy.runtimeSwitchEnabled {
            failures.append(.runtimeSwitchDenied)
        }
        if !policy.allowCandidateExecution {
            failures.append(.missingInternalCanaryConfiguration)
        }
        guard let stageEvidence = evidence.canaryStageEvidence else {
            self.failures = Array(Set(failures + [.missingCanaryStageEvidence])).sorted { $0.rawValue < $1.rawValue }
            self.allowed = false
            self.selectedCandidateLimit = 0
            return
        }
        if stageEvidence.status != .passed {
            failures.append(.canaryStageBlocked)
        }
        if stageEvidence.stage != policy.requestedStage.previousStage {
            failures.append(.canaryStageOrderViolation)
        }
        if !stageEvidence.observationWindowComplete {
            failures.append(.observationWindowIncomplete)
        }
        if stageEvidence.successfulCommitCount < policy.requestedStage.minimumPreviousStageSuccessCount {
            failures.append(.canaryStageOrderViolation)
        }
        if stageEvidence.failedCommitCount > 0 {
            failures.append(.previousStageFailure)
        }
        if stageEvidence.rollbackFailureCount > 0 {
            failures.append(.previousStageRollbackFailure)
        }
        if stageEvidence.blockingDivergenceCount > 0 {
            failures.append(.previousStageBlockingDivergence)
        }
        if stageEvidence.unresolvedConflictCount > 0 {
            failures.append(.previousStageUnresolvedConflict)
        }
        if stageEvidence.postconditionFailureCount > 0 {
            failures.append(.previousStagePostconditionFailure)
        }
        if stageEvidence.unsupportedObjectCount > 0 {
            failures.append(.previousStageUnsupportedObject)
        }
        if stageEvidence.resourceMoveAttemptCount > 0 {
            failures.append(.resourceMoveAttempted)
        }
        if stageEvidence.folderCycleCount > 0 {
            failures.append(.cycleDetected)
        }
        if stageEvidence.objectIDInstabilityCount > 0 {
            failures.append(.objectIDInstability)
        }
        if !stageEvidence.noCommitEvidenceAvailable || !evidence.noCommitEvidenceAvailable {
            failures.append(.missingNoCommitEvidence)
        }
        if stageEvidence.readSideParallelDivergenceCount > 0 || !evidence.readSideParallelEquivalent {
            failures.append(.readSideParallelDivergence)
        }
        self.failures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = self.failures.isEmpty
        self.selectedCandidateLimit = self.allowed ? policy.requestedStage.nominalCanaryBudget : 0
    }
}

nonisolated struct CanonicalLibraryMetadataCanaryPolicy: Codable, Equatable, Sendable {
    var stagePolicy: CanonicalLibraryMetadataCanaryStagePolicy
    var canaryMaxObjectsPerSyncRun: Int
    var allowsInternalN1Execution: Bool
    var explicitInternalTestConfiguration: Bool
    var runtimeSwitchEnabled: Bool
    var allowAllEligible: Bool

    nonisolated init(
        stagePolicy: CanonicalLibraryMetadataCanaryStagePolicy = .disabled,
        canaryMaxObjectsPerSyncRun: Int = 0,
        allowsInternalN1Execution: Bool = false,
        explicitInternalTestConfiguration: Bool = false,
        runtimeSwitchEnabled: Bool = false,
        allowAllEligible: Bool = false
    ) {
        self.stagePolicy = stagePolicy
        self.canaryMaxObjectsPerSyncRun = max(0, canaryMaxObjectsPerSyncRun)
        self.allowsInternalN1Execution = allowsInternalN1Execution
        self.explicitInternalTestConfiguration = explicitInternalTestConfiguration
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.allowAllEligible = allowAllEligible
    }

    nonisolated static let disabled = CanonicalLibraryMetadataCanaryPolicy()

    private enum CodingKeys: String, CodingKey {
        case stagePolicy
        case canaryMaxObjectsPerSyncRun
        case allowsInternalN1Execution
        case explicitInternalTestConfiguration
        case runtimeSwitchEnabled
        case allowAllEligible
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stagePolicy = try container.decodeIfPresent(CanonicalLibraryMetadataCanaryStagePolicy.self, forKey: .stagePolicy) ?? .disabled
        self.canaryMaxObjectsPerSyncRun = max(0, try container.decodeIfPresent(Int.self, forKey: .canaryMaxObjectsPerSyncRun) ?? 0)
        self.allowsInternalN1Execution = try container.decodeIfPresent(Bool.self, forKey: .allowsInternalN1Execution) ?? false
        self.explicitInternalTestConfiguration = try container.decodeIfPresent(Bool.self, forKey: .explicitInternalTestConfiguration) ?? false
        self.runtimeSwitchEnabled = try container.decodeIfPresent(Bool.self, forKey: .runtimeSwitchEnabled) ?? false
        self.allowAllEligible = try container.decodeIfPresent(Bool.self, forKey: .allowAllEligible) ?? false
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stagePolicy, forKey: .stagePolicy)
        try container.encode(canaryMaxObjectsPerSyncRun, forKey: .canaryMaxObjectsPerSyncRun)
        try container.encode(allowsInternalN1Execution, forKey: .allowsInternalN1Execution)
        try container.encode(explicitInternalTestConfiguration, forKey: .explicitInternalTestConfiguration)
        try container.encode(runtimeSwitchEnabled, forKey: .runtimeSwitchEnabled)
        try container.encode(allowAllEligible, forKey: .allowAllEligible)
    }
}

nonisolated enum CanonicalLibraryMetadataCanaryMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case n1

    nonisolated var isExecutable: Bool {
        self == .n1
    }
}

nonisolated struct CanonicalLibraryMetadataCanaryConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalLibraryMetadataCanaryMode
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
        mode: CanonicalLibraryMetadataCanaryMode = .disabled,
        domain: CanonicalMigrationDomain = .libraryMetadata,
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

    nonisolated static let disabled = CanonicalLibraryMetadataCanaryConfiguration()

    nonisolated static func internalN1(
        explicitInternalTestConfiguration: Bool = true
    ) -> CanonicalLibraryMetadataCanaryConfiguration {
        CanonicalLibraryMetadataCanaryConfiguration(
            mode: .n1,
            canaryMaxObjectsPerSyncRun: 1,
            explicitInternalTestConfiguration: explicitInternalTestConfiguration
        )
    }

    nonisolated init(appSeamConfiguration configuration: CanonicalLibraryMetadataCutoverAppSeamConfiguration) {
        let policy = configuration.policy.canaryPolicy
        let n1Enabled = configuration.isEnabled
            && configuration.effectiveMode == .canaryCommit
            && policy.canaryMaxObjectsPerSyncRun == 1
            && policy.allowsInternalN1Execution
        self.init(
            mode: n1Enabled ? .n1 : .disabled,
            domain: .libraryMetadata,
            canaryMaxObjectsPerSyncRun: policy.canaryMaxObjectsPerSyncRun,
            explicitInternalTestConfiguration: policy.explicitInternalTestConfiguration,
            runtimeSwitchEnabled: policy.runtimeSwitchEnabled || policy.stagePolicy.runtimeSwitchEnabled,
            allowAllEligible: policy.allowAllEligible || policy.stagePolicy.requestedStage == .allEligible,
            releaseDefaultEnabled: false
        )
    }

    nonisolated var strictN1Enabled: Bool {
        mode == .n1
            && domain == .libraryMetadata
            && canaryMaxObjectsPerSyncRun == 1
            && explicitInternalTestConfiguration
            && !runtimeSwitchEnabled
            && !allowAllEligible
            && !releaseDefaultEnabled
    }
}

nonisolated enum CanonicalLibraryMetadataCanaryCandidateSafetyKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case folderRenameOrColorMetadata
    case studyItemTagsFilingOrFolderMembershipMetadata
    case standaloneNoteTitleTagsOrFilingMetadata
    case blocked
}

nonisolated struct CanonicalLibraryMetadataCanaryCandidateSafety: Codable, Equatable, Sendable {
    var candidate: CanonicalLibraryMetadataCanaryCandidate
    var safe: Bool
    var kind: CanonicalLibraryMetadataCanaryCandidateSafetyKind
    var blockers: [CanonicalLibraryMetadataCanaryBlocker]
    var metadataOnly: Bool
    var resourceMoveAttempted: Bool
    var physicalDeleteAttempted: Bool
    var contentBytesMutated: Bool

    nonisolated init(
        candidate: CanonicalLibraryMetadataCutoverCandidate,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        attemptedFailedActionIDs: Set<String> = []
    ) {
        var blockers = CanonicalLibraryMetadataCanarySelector.candidateBlockers(
            candidate,
            evidence: evidence,
            attemptedFailedActionIDs: attemptedFailedActionIDs
        )
        let metadataKind: CanonicalLibraryMetadataCanaryCandidateSafetyKind
        switch candidate.objectKind {
        case .folder:
            if candidate.folderHierarchyMutationAttempted {
                blockers.append(.folderHierarchyMutationUnsupported)
            }
            metadataKind = .folderRenameOrColorMetadata
        case .standaloneNote:
            metadataKind = .standaloneNoteTitleTagsOrFilingMetadata
        case .standaloneStudyItem, .recordingAssociatedStudyItem:
            metadataKind = .studyItemTagsFilingOrFolderMembershipMetadata
        default:
            blockers.append(.unsupportedAction)
            metadataKind = .blocked
        }
        if candidate.expectedObject?.isDeleted == true {
            blockers.append(.activeVsTombstoneConflict)
        }
        self.candidate = CanonicalLibraryMetadataCanaryCandidate(candidate)
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.safe = self.blockers.isEmpty
        self.kind = self.safe ? metadataKind : .blocked
        self.metadataOnly = true
        self.resourceMoveAttempted = candidate.hasResourceMoveAttempt
        self.physicalDeleteAttempted = candidate.expectedObject?.isDeleted == true
        self.contentBytesMutated = false
    }
}

nonisolated enum CanonicalLibraryMetadataCanaryBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedMode
    case canaryBudgetZero
    case missingInternalCanaryConfiguration
    case canaryBudgetAboveOneDenied
    case canaryStageEvidenceMissing
    case canaryStageBlocked
    case unsupportedTrigger
    case unsupportedAction
    case insufficientEvidence
    case missingOwnerApproval
    case matrixBlocked
    case activePilotNotLibraryMetadata
    case commitExecutorUnavailable
    case peerSnapshotUnavailable
    case runtimeSwitchDenied
    case allEligibleDenied
    case defaultEnablementDenied
    case readSideParallelMissing
    case unresolvedConflict
    case noRollbackCheckpoint
    case realApplyPortUnavailable
    case conflictDetected
    case activeVsTombstoneConflict
    case resourceMoveAttempted
    case folderHierarchyMutationUnsupported
    case parentMissing
    case cycleDetected
    case objectIDInstability
    case alreadyAttemptedFailedCandidate
    case noEligibleCandidate
}

nonisolated struct CanonicalLibraryMetadataCanaryCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { cutoverCandidate.action.actionID }
    var cutoverCandidate: CanonicalLibraryMetadataCutoverCandidate
    var objectID: String
    var objectKind: CanonicalObjectKind
    var actionKind: CanonicalLibraryMetadataCutoverActionKind
    var domain: CanonicalLibraryMetadataCutoverDomain
    var metadataHashPrefix: String?

    nonisolated init(_ cutoverCandidate: CanonicalLibraryMetadataCutoverCandidate) {
        self.cutoverCandidate = cutoverCandidate
        self.objectID = CanonicalProductionRedaction.safeIdentifier(cutoverCandidate.objectID, fallback: "library-object")
        self.objectKind = cutoverCandidate.objectKind
        self.actionKind = cutoverCandidate.cutoverActionKind
        self.domain = cutoverCandidate.domain
        self.metadataHashPrefix = cutoverCandidate.expectedMetadataHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
    }
}

nonisolated struct CanonicalLibraryMetadataCanarySelectionBlocker: Codable, Equatable, Identifiable, Sendable {
    var id: String { [objectID ?? "run", reason.rawValue].joined(separator: "|") }
    var objectID: String?
    var reason: CanonicalLibraryMetadataCanaryBlocker

    nonisolated init(objectID: String?, reason: CanonicalLibraryMetadataCanaryBlocker) {
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "library-object") }
        self.reason = reason
    }
}

nonisolated struct CanonicalLibraryMetadataCanarySelectionResult: Codable, Equatable, Sendable {
    var selectedCandidates: [CanonicalLibraryMetadataCanaryCandidate]
    var blockers: [CanonicalLibraryMetadataCanarySelectionBlocker]
    var evaluatedCandidateCount: Int
    var noEligibleCandidate: Bool

    nonisolated var selectedCutoverCandidates: [CanonicalLibraryMetadataCutoverCandidate] {
        selectedCandidates.map(\.cutoverCandidate)
    }
}

nonisolated struct CanonicalLibraryMetadataCanarySelector: Sendable {
    nonisolated init() {}

    nonisolated func select(
        mode: CanonicalCutoverMode,
        policy: CanonicalLibraryMetadataCanaryPolicy,
        trigger: CanonicalSyncPlanTrigger,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        attemptedFailedActionIDs: Set<String> = []
    ) -> CanonicalLibraryMetadataCanarySelectionResult {
        var blockers: [CanonicalLibraryMetadataCanarySelectionBlocker] = []
        let usesStagePolicy = policy.stagePolicy.requestedStage.isExecutable
        let stageGate = usesStagePolicy ? CanonicalLibraryMetadataCanaryStageGate(policy: policy.stagePolicy, evidence: evidence) : nil

        if mode == .disabled {
            blockers.append(.init(objectID: nil, reason: .disabled))
        }
        if mode != .canary {
            blockers.append(.init(objectID: nil, reason: .unsupportedMode))
        }
        if policy.canaryMaxObjectsPerSyncRun == 0 && !usesStagePolicy {
            blockers.append(.init(objectID: nil, reason: .canaryBudgetZero))
        }
        if policy.canaryMaxObjectsPerSyncRun > 1 && !usesStagePolicy {
            blockers.append(.init(objectID: nil, reason: .canaryBudgetAboveOneDenied))
        }
        if policy.canaryMaxObjectsPerSyncRun == 1 && !usesStagePolicy && !policy.allowsInternalN1Execution {
            blockers.append(.init(objectID: nil, reason: .missingInternalCanaryConfiguration))
        }
        if usesStagePolicy, stageGate?.allowed != true {
            blockers.append(.init(objectID: nil, reason: evidence.canaryStageEvidence == nil ? .canaryStageEvidenceMissing : .canaryStageBlocked))
        }
        if trigger == .viewRefresh || trigger == .retryDrainer {
            blockers.append(.init(objectID: nil, reason: .unsupportedTrigger))
        }

        let runBlocked = !blockers.isEmpty
        let selectionLimit = usesStagePolicy ? (stageGate?.selectedCandidateLimit ?? 0) : policy.canaryMaxObjectsPerSyncRun
        let ordered = candidates.sorted { lhs, rhs in
            if lhs.objectKind.rawValue != rhs.objectKind.rawValue {
                return lhs.objectKind.rawValue < rhs.objectKind.rawValue
            }
            if lhs.objectID != rhs.objectID {
                return lhs.objectID.localizedStandardCompare(rhs.objectID) == .orderedAscending
            }
            return lhs.action.actionID.localizedStandardCompare(rhs.action.actionID) == .orderedAscending
        }
        let cycleDetected = CanonicalLibraryMetadataCutoverCandidate.folderHierarchyCycleDetected(in: candidates)
        var selected: [CanonicalLibraryMetadataCanaryCandidate] = []
        for candidate in ordered {
            var reasons = Self.candidateBlockers(
                candidate,
                evidence: evidence,
                attemptedFailedActionIDs: attemptedFailedActionIDs
            )
            if cycleDetected, candidate.objectKind == .folder {
                reasons.append(.cycleDetected)
            }
            if reasons.isEmpty, !runBlocked, selected.count < selectionLimit {
                selected.append(CanonicalLibraryMetadataCanaryCandidate(candidate))
            } else {
                for reason in reasons {
                    blockers.append(.init(objectID: candidate.objectID, reason: reason))
                }
            }
        }
        if selected.isEmpty {
            blockers.append(.init(objectID: nil, reason: .noEligibleCandidate))
        }
        return CanonicalLibraryMetadataCanarySelectionResult(
            selectedCandidates: selected,
            blockers: blockers,
            evaluatedCandidateCount: candidates.count,
            noEligibleCandidate: selected.isEmpty
        )
    }

    nonisolated static func candidateBlockers(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        attemptedFailedActionIDs: Set<String>
    ) -> [CanonicalLibraryMetadataCanaryBlocker] {
        var blockers: [CanonicalLibraryMetadataCanaryBlocker] = []
        if !candidate.cutoverActionKind.isExecutableMetadata {
            blockers.append(candidate.cutoverActionKind == .conflictRecord ? .conflictDetected : .unsupportedAction)
        }
        if candidate.unresolvedConflict {
            blockers.append(.unresolvedConflict)
        }
        if candidate.hasActiveVsTombstoneConflict {
            blockers.append(.activeVsTombstoneConflict)
        }
        if candidate.rollbackCheckpointID == nil {
            blockers.append(.noRollbackCheckpoint)
        }
        if !evidence.realRootBoundApplyPortAvailable || !evidence.applyPortMode.isNonDryRunRootBound {
            blockers.append(.realApplyPortUnavailable)
        }
        if candidate.hasResourceMoveAttempt {
            blockers.append(.resourceMoveAttempted)
        }
        if candidate.folderHierarchyMutationAttempted {
            blockers.append(.folderHierarchyMutationUnsupported)
        }
        if candidate.parentMissingKnown {
            blockers.append(.parentMissing)
        }
        if candidate.expectedObject?.isDeleted == true {
            blockers.append(.activeVsTombstoneConflict)
        }
        if candidate.hasObjectIDInstability {
            blockers.append(.objectIDInstability)
        }
        if attemptedFailedActionIDs.contains(candidate.action.actionID) {
            blockers.append(.alreadyAttemptedFailedCandidate)
        }
        return Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }
}

nonisolated struct CanonicalLibraryMetadataCutoverGate: Codable, Equatable, Sendable {
    var mode: CanonicalCutoverMode
    var allowed: Bool
    var failures: [CanonicalLibraryMetadataCutoverFailure]
    var legacyFallbackAvailable: Bool
    var reason: String

    nonisolated init(
        mode: CanonicalCutoverMode,
        failures: [CanonicalLibraryMetadataCutoverFailure],
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

nonisolated enum CanonicalLibraryMetadataCommitFailureInjection: String, Codable, Equatable, Sendable {
    case none
    case preconditionMismatch
    case postconditionMismatch
    case applyFailureBeforeCommit
    case applyFailureAfterPartialCommit
    case rollbackFailure
    case parentMissing
    case cycleDetected
    case resourceMoveAttempted
    case unsupportedObjectKind
    case conflictDetected
}

nonisolated struct CanonicalLibraryMetadataProductionCommitResult: Codable, Equatable, Sendable {
    var actionID: String
    var objectID: String
    var objectKind: CanonicalObjectKind
    var domain: CanonicalLibraryMetadataCutoverDomain
    var actionKind: CanonicalLibraryMetadataCutoverActionKind
    var committed: Bool
    var partialCommit: Bool
    var preconditionVerified: Bool
    var postconditionVerified: Bool
    var routePath: String?
    var metadataHashPrefix: String?
    var parentSummary: String
    var tagCount: Int
    var filingSummary: String
    var payloadByteCount: Int
    var sideEffect: CanonicalProductionSideEffect?
    var sideEffects: [CanonicalProductionSideEffect]
    var failureKind: CanonicalLibraryMetadataCutoverFailure?
    var reason: String

    nonisolated init(
        actionID: String,
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain,
        actionKind: CanonicalLibraryMetadataCutoverActionKind,
        committed: Bool,
        partialCommit: Bool = false,
        preconditionVerified: Bool = true,
        postconditionVerified: Bool = true,
        routePath: String? = "/sync/apply-metadata",
        metadataHash: CanonicalHash? = nil,
        metadataHashPrefix: String? = nil,
        parentSummary: String = "parent=none",
        tagCount: Int = 0,
        filingSummary: String = "none",
        payloadByteCount: Int = 0,
        sideEffect: CanonicalProductionSideEffect? = nil,
        sideEffects: [CanonicalProductionSideEffect]? = nil,
        failureKind: CanonicalLibraryMetadataCutoverFailure? = nil,
        reason: String
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: actionKind.rawValue)
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object")
        self.objectKind = objectKind
        self.domain = domain
        self.actionKind = actionKind
        self.committed = committed
        self.partialCommit = partialCommit
        self.preconditionVerified = preconditionVerified
        self.postconditionVerified = postconditionVerified
        self.routePath = routePath.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.metadataHashPrefix = metadataHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
            ?? CanonicalProductionRedaction.hashPrefix(metadataHashPrefix)
        self.parentSummary = CanonicalProductionRedaction.safeDiagnosticText(parentSummary) ?? "parent=none"
        self.tagCount = max(0, tagCount)
        self.filingSummary = CanonicalProductionRedaction.safeDiagnosticText(filingSummary) ?? "none"
        self.payloadByteCount = max(0, payloadByteCount)
        self.sideEffect = sideEffect
        self.sideEffects = sideEffects ?? sideEffect.map { [$0] } ?? []
        self.failureKind = failureKind
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (committed ? "committed" : "failed")
    }

    nonisolated static func success(
        candidate: CanonicalLibraryMetadataCutoverCandidate,
        payloadByteCount: Int,
        sideEffects: [CanonicalProductionSideEffect]
    ) -> CanonicalLibraryMetadataProductionCommitResult {
        CanonicalLibraryMetadataProductionCommitResult(
            actionID: candidate.action.actionID,
            objectID: candidate.objectID,
            objectKind: candidate.objectKind,
            domain: candidate.domain,
            actionKind: candidate.cutoverActionKind,
            committed: true,
            metadataHash: candidate.expectedMetadataHash,
            parentSummary: candidate.parentSummary,
            tagCount: candidate.tagCount,
            filingSummary: candidate.filingSummary,
            payloadByteCount: payloadByteCount,
            sideEffect: sideEffects.first,
            sideEffects: sideEffects,
            reason: "libraryMetadataCommitted"
        )
    }

    nonisolated static func failure(
        candidate: CanonicalLibraryMetadataCutoverCandidate,
        kind failureKind: CanonicalLibraryMetadataCutoverFailure,
        partialCommit: Bool = false,
        reason: String
    ) -> CanonicalLibraryMetadataProductionCommitResult {
        CanonicalLibraryMetadataProductionCommitResult(
            actionID: candidate.action.actionID,
            objectID: candidate.objectID,
            objectKind: candidate.objectKind,
            domain: candidate.domain,
            actionKind: candidate.cutoverActionKind,
            committed: false,
            partialCommit: partialCommit,
            preconditionVerified: ![.objectIDMismatch, .objectKindMismatch, .expectedMetadataHashMissing, .parentMissing, .cycleDetected, .resourceMoveAttempted, .folderHierarchyMutationUnsupported, .unsupportedObjectKind, .conflictDetected, .activeVsTombstoneConflict].contains(failureKind),
            postconditionVerified: failureKind != .postconditionMismatch,
            metadataHash: candidate.expectedMetadataHash,
            parentSummary: candidate.parentSummary,
            tagCount: candidate.tagCount,
            filingSummary: candidate.filingSummary,
            failureKind: failureKind,
            reason: reason
        )
    }
}

nonisolated struct CanonicalLibraryMetadataRollbackExecutionResult: Codable, Equatable, Sendable {
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
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "library-metadata-checkpoint")
        self.succeeded = succeeded
        self.fatal = fatal
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (succeeded ? "rollbackCompleted" : "rollbackFailed")
        self.rollbackResult = rollbackResult
    }
}

protocol CanonicalLibraryMetadataCutoverExecutor: Sendable {
    func commitLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate
    ) async -> CanonicalLibraryMetadataProductionCommitResult

    func rollbackLibraryMetadata(
        _ candidate: CanonicalLibraryMetadataCutoverCandidate,
        reason: CanonicalLibraryMetadataCutoverFailure
    ) async -> CanonicalLibraryMetadataRollbackExecutionResult
}

nonisolated enum CanonicalLibraryMetadataCutoverDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalLibraryMetadataCutoverGateEvaluated
    case canonicalLibraryMetadataCutoverGateBlocked
    case canonicalLibraryMetadataNoCommitStarted
    case canonicalLibraryMetadataNoCommitCompleted
    case canonicalLibraryMetadataCommitStarted
    case canonicalLibraryMetadataCommitCompleted
    case canonicalLibraryMetadataCommitFailed
    case canonicalLibraryMetadataRollbackStarted
    case canonicalLibraryMetadataRollbackCompleted
    case canonicalLibraryMetadataRollbackFailed
    case canonicalLibraryMetadataCanaryStarted
    case canonicalLibraryMetadataCanaryCompleted
    case canonicalLibraryMetadataDuplicateLegacySuppressed
    case canonicalLibraryMetadataLegacyFallbackUsed
    case canonicalLibraryMetadataResourceMoveBlocked
    case canonicalLibraryMetadataHierarchyCycleBlocked
    case canonicalLibraryMetadataObjectIDInstabilityBlocked
    case canonicalLibraryMetadataUnsafeCandidateSkipped
    case canonicalLibraryMetadataCycleBlocked
    case canonicalLibraryMetadataConflictBlocked
    case canonicalLibraryMetadataReadSideParallelEquivalent
    case canonicalLibraryMetadataReadSideParallelDivergent
    case canonicalLibraryMetadataUIProjectionParallelReadStarted
    case canonicalLibraryMetadataUIProjectionParallelReadEquivalent
    case canonicalLibraryMetadataUIProjectionParallelReadDivergent
    case canonicalLibraryMetadataN1CanaryConfigured
    case canonicalLibraryMetadataN1CandidateSelectionStarted
    case canonicalLibraryMetadataN1CandidateSelected
    case canonicalLibraryMetadataN1NoEligibleCandidate
    case canonicalLibraryMetadataN1CandidateBlocked
    case canonicalLibraryMetadataN1CanaryStarted
    case canonicalLibraryMetadataN1CommitStarted
    case canonicalLibraryMetadataN1CommitCompleted
    case canonicalLibraryMetadataN1CommitFailed
    case canonicalLibraryMetadataN1PostconditionVerified
    case canonicalLibraryMetadataN1PostconditionFailed
    case canonicalLibraryMetadataN1RollbackStarted
    case canonicalLibraryMetadataN1RollbackCompleted
    case canonicalLibraryMetadataN1RollbackFailed
    case canonicalLibraryMetadataN1LegacyFallbackUsed
    case canonicalLibraryMetadataN1DuplicateLegacySuppressed
    case canonicalLibraryMetadataN1FatalBlocker
    case canonicalLibraryMetadataN1ObservationRecorded
    case canonicalLibraryMetadataN1ReadSideParallelStarted
    case canonicalLibraryMetadataN1ReadSideParallelEquivalent
    case canonicalLibraryMetadataN1ReadSideParallelDivergent
    case canonicalLibraryMetadataN1MacPeerSnapshotUnavailable
    case canonicalLibraryMetadataCanaryStageEvaluated
    case canonicalLibraryMetadataCanaryStageBlocked
    case canonicalLibraryMetadataCanaryStageAllowed
    case canonicalLibraryMetadataCanaryStageStarted
    case canonicalLibraryMetadataCanaryStageCompleted
    case canonicalLibraryMetadataCanaryStageFailed
    case canonicalLibraryMetadataCanaryStageObservationRecorded
    case canonicalLibraryMetadataCanaryStageCandidateSkipped
    case canonicalLibraryMetadataCanaryStageCandidateExecuted
    case canonicalLibraryMetadataCanaryStageStoppedAfterFailure
    case canonicalLibraryMetadataCanaryStageNextStageEligible
    case canonicalLibraryMetadataCanaryStageNextStageBlocked
    case canonicalLibraryMetadataCanaryStageAllEligibleStarted
    case canonicalLibraryMetadataCanaryStageAllEligibleCompleted
    case canonicalLibraryMetadataExpandedReadSideParallelStarted
    case canonicalLibraryMetadataExpandedReadSideParallelEquivalent
    case canonicalLibraryMetadataExpandedReadSideParallelDivergent
    case canonicalLibraryMetadataReadSideParallelStarted
    case canonicalLibraryMetadataReadSideParallelCompleted
    case canonicalLibraryMetadataReadSideParallelFailed
    case canonicalLibraryMetadataReadSideEquivalent
    case canonicalLibraryMetadataReadSideDivergent
    case canonicalLibraryMetadataReadSideUnsupportedObject
    case canonicalLibraryMetadataReadSidePathLeakBlocked
    case canonicalLibraryMetadataReadSideCutoverCandidateEvaluated
    case canonicalLibraryMetadataReadSideCutoverCandidateBlocked
    case canonicalLibraryMetadataReadSideCutoverCandidateReady
    case canonicalLibraryMetadataGuardedCanonicalReadSuppressed
    case canonicalLibraryMetadataLegacyReadFallbackAvailable
    case canonicalLibraryMetadataRetirementCandidateEvaluated
    case canonicalLibraryMetadataRetirementCandidateBlocked
    case canonicalLibraryMetadataRetirementCandidateReady
    case canonicalLibraryMetadataRealCanaryInjectionConfigured
    case canonicalLibraryMetadataRealCanaryBlocked
    case canonicalLibraryMetadataRealCanaryArmed
    case canonicalLibraryMetadataRealCanaryExecutionStarted
    case canonicalLibraryMetadataRealCanaryExecutionCompleted
    case canonicalLibraryMetadataRealCanaryExecutionFailed
    case canonicalLibraryMetadataRealCanaryNoEligibleCandidate
    case canonicalLibraryMetadataRealCanaryUnsafeCandidateSkipped
    case canonicalLibraryMetadataRealCanaryProductionRootWriteStarted
    case canonicalLibraryMetadataRealCanaryProductionRootWriteCompleted
    case canonicalLibraryMetadataRealCanaryProductionRootWriteFailed
    case canonicalLibraryMetadataRealCanaryRollbackStarted
    case canonicalLibraryMetadataRealCanaryRollbackCompleted
    case canonicalLibraryMetadataRealCanaryRollbackFailed
    case canonicalLibraryMetadataRealCanaryLegacyFallbackUsed
    case canonicalLibraryMetadataRealCanaryDuplicateLegacySuppressed
    case canonicalLibraryMetadataRealCanaryReadSideEquivalent
    case canonicalLibraryMetadataRealCanaryReadSideDivergent
    case canonicalLibraryMetadataRealCanaryFatalBlocker
    case canonicalLibraryMetadataProductionRootGateEvaluated
    case canonicalLibraryMetadataProductionRootGateBlocked
    case canonicalLibraryMetadataProductionRootGateAllowed
    case canonicalLibraryMetadataProductionRootN1Started
    case canonicalLibraryMetadataProductionRootN1Completed
    case canonicalLibraryMetadataProductionRootN1Failed
    case canonicalLibraryMetadataProductionRootSafetyProofBuilt
    case canonicalLibraryMetadataProductionRootCheckpointCreated
    case canonicalLibraryMetadataProductionRootAtomicWriteStarted
    case canonicalLibraryMetadataProductionRootAtomicWriteCompleted
    case canonicalLibraryMetadataProductionRootPostconditionVerified
    case canonicalLibraryMetadataProductionRootRollbackStarted
    case canonicalLibraryMetadataProductionRootRollbackCompleted
    case canonicalLibraryMetadataProductionRootRollbackFailed
    case canonicalLibraryMetadataProductionRootLegacyFallbackUsed
    case canonicalLibraryMetadataProductionRootDuplicateSuppressed
    case canonicalLibraryMetadataProductionRootReadSideEquivalent
    case canonicalLibraryMetadataProductionRootReadSideDivergent
    case canonicalLibraryMetadataLandingConfigEvaluated
    case canonicalLibraryMetadataLandingDisabled
    case canonicalLibraryMetadataLandingArmed
    case canonicalLibraryMetadataLandingBlocked
    case canonicalLibraryMetadataLandingN1Started
    case canonicalLibraryMetadataLandingCandidateSelected
    case canonicalLibraryMetadataLandingNoEligibleCandidate
    case canonicalLibraryMetadataLandingCommitStarted
    case canonicalLibraryMetadataLandingCommitCompleted
    case canonicalLibraryMetadataLandingCommitFailed
    case canonicalLibraryMetadataLandingRollbackStarted
    case canonicalLibraryMetadataLandingRollbackCompleted
    case canonicalLibraryMetadataLandingRollbackFailed
    case canonicalLibraryMetadataLandingLegacyFallbackUsed
    case canonicalLibraryMetadataLandingDuplicateSuppressed
    case canonicalLibraryMetadataLandingReadSideEquivalent
    case canonicalLibraryMetadataLandingReadSideDivergent
    case canonicalLibraryMetadataLandingReportBuilt
    case canonicalMigrationLandingFreezeViolation
    case canonicalLibraryMetadataReadSourceEvaluated
    case canonicalLibraryMetadataReadSourceLegacyReturned
    case canonicalLibraryMetadataReadSourceCanonicalCandidateBuilt
    case canonicalLibraryMetadataGuardedCanonicalReadAllowed
    case canonicalLibraryMetadataGuardedCanonicalReadBlocked
    case canonicalLibraryMetadataGuardedCanonicalReadServed
    case canonicalLibraryMetadataGuardedCanonicalReadFallback
    case canonicalLibraryMetadataReadCutoverGateEvaluated
    case canonicalLibraryMetadataReadCutoverGateBlocked
    case canonicalLibraryMetadataReadCutoverGateAllowed
    case canonicalLibraryMetadataReadOutputEquivalent
    case canonicalLibraryMetadataReadOutputDivergent
    case canonicalLibraryMetadataRetirementCandidateUpdated
    case canonicalLibraryMetadataRetirementStillBlocked
    case canonicalLibraryMetadataObservationWindowStarted
    case canonicalLibraryMetadataObservationWriteSideRecorded
    case canonicalLibraryMetadataObservationReadSideRecorded
    case canonicalLibraryMetadataObservationWindowCompleted
    case canonicalLibraryMetadataObservationGateEvaluated
    case canonicalLibraryMetadataObservationGateBlocked
    case canonicalLibraryMetadataObservationGateReady
    case canonicalLibraryMetadataRetirementCandidateGateEvaluated
    case canonicalLibraryMetadataRetirementCandidateGateBlocked
    case canonicalLibraryMetadataRollbackDrillSummarized
    case canonicalLibraryMetadataEndToEndPilotReportGenerated
}

nonisolated struct CanonicalLibraryMetadataCutoverDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", result ?? "", reason ?? ""].joined(separator: "|") }
    var kind: CanonicalLibraryMetadataCutoverDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var domain: CanonicalLibraryMetadataCutoverDomain?
    var objectID: String?
    var objectKind: CanonicalObjectKind?
    var action: String?
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalLibraryMetadataCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalLibraryMetadataCutoverDomain? = nil,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        action: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) {
        self.kind = kind
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.domain = domain
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "library-object") }
        self.objectKind = objectKind
        self.action = CanonicalProductionRedaction.safeDiagnosticText(action)
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
            "objectKind=\(objectKind?.rawValue ?? "none")",
            "action=\(action ?? "none")",
            "result=\(result ?? "none")",
            "reason=\(reason ?? "none")",
            "hashPrefix=\(hashPrefix ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalLibraryMetadataReadSideParallelProjectionResult: Codable, Equatable, Sendable {
    var objectID: String
    var objectKind: CanonicalObjectKind
    var domain: CanonicalLibraryMetadataCutoverDomain
    var equivalent: Bool
    var mutatedUI: Bool
    var canonicalHashPrefix: String?
    var legacyHashPrefix: String?
    var parentSummary: String
    var tagCount: Int
    var filingSummary: String
    var noResourceFileMove: Bool
    var syncOrUploadTriggered: Bool
    var reason: String

    nonisolated init(
        candidate: CanonicalLibraryMetadataCutoverCandidate,
        equivalent: Bool,
        legacyHash: CanonicalHash?,
        reason: String
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(candidate.objectID, fallback: "library-object")
        self.objectKind = candidate.objectKind
        self.domain = candidate.domain
        self.equivalent = equivalent
        self.mutatedUI = false
        self.canonicalHashPrefix = candidate.expectedMetadataHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.legacyHashPrefix = legacyHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.parentSummary = candidate.parentSummary
        self.tagCount = candidate.tagCount
        self.filingSummary = candidate.filingSummary
        self.noResourceFileMove = true
        self.syncOrUploadTriggered = false
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (equivalent ? "equivalent" : "divergent")
    }
}

nonisolated enum CanonicalLibraryMetadataCanaryObservationStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case blocked
    case noEligibleCandidate
    case committed
    case failedRolledBack
    case fatalRollbackFailure
}

nonisolated struct CanonicalLibraryMetadataCanaryObservationReport: Codable, Equatable, Sendable {
    var status: CanonicalLibraryMetadataCanaryObservationStatus
    var syncRunID: String?
    var nodeRole: CanonicalProductionExecutionDomainRole
    var selectedCandidateCount: Int
    var blockedCandidateCount: Int
    var attemptedCommitCount: Int
    var successfulCommitCount: Int
    var rollbackCount: Int
    var duplicateSuppressionApplied: Bool
    var legacyFallbackPreserved: Bool
    var readSideParallelEquivalent: Bool
    var uiMutated: Bool
    var resourceMoved: Bool
    var physicalDeleteAttempted: Bool
    var contentBytesMutated: Bool
    var fatalBlocker: Bool
    var reason: String

    nonisolated init(
        status: CanonicalLibraryMetadataCanaryObservationStatus,
        syncRunID: String?,
        nodeRole: CanonicalProductionExecutionDomainRole,
        selectedCandidateCount: Int,
        blockedCandidateCount: Int,
        attemptedCommitCount: Int,
        successfulCommitCount: Int,
        rollbackCount: Int,
        duplicateSuppressionApplied: Bool,
        legacyFallbackPreserved: Bool,
        readSideParallelEquivalent: Bool,
        uiMutated: Bool = false,
        resourceMoved: Bool = false,
        physicalDeleteAttempted: Bool = false,
        contentBytesMutated: Bool = false,
        fatalBlocker: Bool = false,
        reason: String
    ) {
        self.status = status
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.nodeRole = nodeRole
        self.selectedCandidateCount = max(0, selectedCandidateCount)
        self.blockedCandidateCount = max(0, blockedCandidateCount)
        self.attemptedCommitCount = max(0, attemptedCommitCount)
        self.successfulCommitCount = max(0, successfulCommitCount)
        self.rollbackCount = max(0, rollbackCount)
        self.duplicateSuppressionApplied = duplicateSuppressionApplied
        self.legacyFallbackPreserved = legacyFallbackPreserved
        self.readSideParallelEquivalent = readSideParallelEquivalent
        self.uiMutated = uiMutated
        self.resourceMoved = resourceMoved
        self.physicalDeleteAttempted = physicalDeleteAttempted
        self.contentBytesMutated = contentBytesMutated
        self.fatalBlocker = fatalBlocker
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? status.rawValue
    }
}

nonisolated enum CanonicalLibraryMetadataCanaryStageRecommendation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case stayDisabled
    case observeCurrentStage
    case advanceToN3
    case advanceToN10
    case advanceToAllEligible
    case holdForInvestigation
    case stopForFatalBlocker
}

nonisolated struct CanonicalLibraryMetadataCanaryStageSummary: Codable, Equatable, Sendable {
    var stage: CanonicalLibraryMetadataCanaryStage
    var budget: Int
    var selectedCount: Int
    var executedCount: Int
    var successCount: Int
    var failureCount: Int

    nonisolated init(
        stage: CanonicalLibraryMetadataCanaryStage,
        budget: Int,
        selectedCount: Int,
        executedCount: Int,
        successCount: Int,
        failureCount: Int
    ) {
        self.stage = stage
        self.budget = max(0, budget)
        self.selectedCount = max(0, selectedCount)
        self.executedCount = max(0, executedCount)
        self.successCount = max(0, successCount)
        self.failureCount = max(0, failureCount)
    }
}

nonisolated struct CanonicalLibraryMetadataCanaryStageFailure: Codable, Equatable, Identifiable, Sendable {
    var id: String { [objectID ?? "run", blocker.rawValue].joined(separator: "|") }
    var objectID: String?
    var blocker: CanonicalLibraryMetadataCanaryBlocker

    nonisolated init(
        objectID: String?,
        blocker: CanonicalLibraryMetadataCanaryBlocker
    ) {
        self.objectID = objectID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "library-object")
        }
        self.blocker = blocker
    }
}

nonisolated struct CanonicalLibraryMetadataCanaryStageObservationReport: Codable, Equatable, Sendable {
    var stage: CanonicalLibraryMetadataCanaryStage
    var budget: Int
    var selectedCount: Int
    var executedCount: Int
    var successCount: Int
    var failureCount: Int
    var rollbackCount: Int
    var rollbackFailureCount: Int
    var legacyFallbackCount: Int
    var duplicateSuppressionCount: Int
    var skippedCount: Int
    var noEligibleCount: Int
    var unsafeCandidateSkippedCount: Int
    var resourceMoveBlockedCount: Int
    var hierarchyCycleBlockedCount: Int
    var objectIDInstabilityBlockedCount: Int
    var fatalBlockerCount: Int
    var readSideParallelEquivalentCount: Int
    var readSideParallelDivergentCount: Int
    var nextStageEligible: Bool
    var nextStageBlockers: [CanonicalLibraryMetadataCutoverFailure]
    var recommendation: CanonicalLibraryMetadataCanaryStageRecommendation
    var runtimeSwitchEnabled: Bool
    var domain: CanonicalMigrationDomain
    var uiMutated: Bool
    var resourceMoved: Bool
    var uploadJobCreated: Bool
    var summary: CanonicalLibraryMetadataCanaryStageSummary
    var failures: [CanonicalLibraryMetadataCanaryStageFailure]
    var evidenceReport: CanonicalLibraryMetadataStageEvidenceReport
    var redacted: Bool

    nonisolated init(
        stage: CanonicalLibraryMetadataCanaryStage,
        budget: Int,
        selectedCount: Int,
        executedCount: Int,
        successCount: Int,
        failureCount: Int,
        rollbackCount: Int,
        rollbackFailureCount: Int,
        legacyFallbackCount: Int,
        duplicateSuppressionCount: Int,
        skippedCount: Int,
        noEligibleCount: Int,
        unsafeCandidateSkippedCount: Int,
        resourceMoveBlockedCount: Int,
        hierarchyCycleBlockedCount: Int,
        objectIDInstabilityBlockedCount: Int,
        fatalBlockerCount: Int,
        readSideParallelEquivalentCount: Int,
        readSideParallelDivergentCount: Int,
        nextStageEligible: Bool,
        nextStageBlockers: [CanonicalLibraryMetadataCutoverFailure],
        recommendation: CanonicalLibraryMetadataCanaryStageRecommendation,
        runtimeSwitchEnabled: Bool,
        failures: [CanonicalLibraryMetadataCanaryStageFailure],
        evidenceReport: CanonicalLibraryMetadataStageEvidenceReport,
        redacted: Bool = true
    ) {
        self.stage = stage
        self.budget = max(0, budget)
        self.selectedCount = max(0, selectedCount)
        self.executedCount = max(0, executedCount)
        self.successCount = max(0, successCount)
        self.failureCount = max(0, failureCount)
        self.rollbackCount = max(0, rollbackCount)
        self.rollbackFailureCount = max(0, rollbackFailureCount)
        self.legacyFallbackCount = max(0, legacyFallbackCount)
        self.duplicateSuppressionCount = max(0, duplicateSuppressionCount)
        self.skippedCount = max(0, skippedCount)
        self.noEligibleCount = max(0, noEligibleCount)
        self.unsafeCandidateSkippedCount = max(0, unsafeCandidateSkippedCount)
        self.resourceMoveBlockedCount = max(0, resourceMoveBlockedCount)
        self.hierarchyCycleBlockedCount = max(0, hierarchyCycleBlockedCount)
        self.objectIDInstabilityBlockedCount = max(0, objectIDInstabilityBlockedCount)
        self.fatalBlockerCount = max(0, fatalBlockerCount)
        self.readSideParallelEquivalentCount = max(0, readSideParallelEquivalentCount)
        self.readSideParallelDivergentCount = max(0, readSideParallelDivergentCount)
        self.nextStageEligible = nextStageEligible
        self.nextStageBlockers = Array(Set(nextStageBlockers)).sorted { $0.rawValue < $1.rawValue }
        self.recommendation = recommendation
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.domain = .libraryMetadata
        self.uiMutated = false
        self.resourceMoved = false
        self.uploadJobCreated = false
        self.summary = CanonicalLibraryMetadataCanaryStageSummary(
            stage: stage,
            budget: budget == Int.max ? selectedCount : budget,
            selectedCount: selectedCount,
            executedCount: executedCount,
            successCount: successCount,
            failureCount: failureCount
        )
        self.failures = failures
        self.evidenceReport = evidenceReport
        self.redacted = redacted
    }

    nonisolated var diagnosticsSummary: String {
        [
            "stage=\(stage.rawValue)",
            "budget=\(budget == Int.max ? "allEligible" : String(budget))",
            "selected=\(selectedCount)",
            "executed=\(executedCount)",
            "success=\(successCount)",
            "failure=\(failureCount)",
            "rollback=\(rollbackCount)",
            "rollbackFailure=\(rollbackFailureCount)",
            "legacyFallback=\(legacyFallbackCount)",
            "duplicateSuppression=\(duplicateSuppressionCount)",
            "skipped=\(skippedCount)",
            "nextStageEligible=\(nextStageEligible)",
            "blockers=\(nextStageBlockers.map(\.rawValue).joined(separator: "|"))",
            "runtimeSwitch=\(runtimeSwitchEnabled)",
            "domain=\(domain.rawValue)",
            "uiMutated=\(uiMutated)",
            "resourceMoved=\(resourceMoved)",
            "uploadJobCreated=\(uploadJobCreated)",
            "redacted=\(redacted)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalLibraryMetadataCutoverResult: Codable, Equatable, Sendable {
    var gate: CanonicalLibraryMetadataCutoverGate
    var commits: [CanonicalLibraryMetadataProductionCommitResult]
    var rollbackResults: [CanonicalLibraryMetadataRollbackExecutionResult]
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var legacyFallbackUsed: Bool
    var duplicateLegacySuppressedActionIDs: [String]
    var canaryAttemptedCount: Int
    var canarySucceeded: Bool
    var fatalBlocker: Bool
    var readSideProjection: CanonicalLibraryMetadataReadSideParallelProjectionResult?
    var canaryConfiguration: CanonicalLibraryMetadataCanaryConfiguration? = nil
    var canarySelection: CanonicalLibraryMetadataCanarySelectionResult? = nil
    var candidateSafetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety]? = nil
    var observationReport: CanonicalLibraryMetadataCanaryObservationReport? = nil
    var stageObservationReport: CanonicalLibraryMetadataCanaryStageObservationReport? = nil

    nonisolated var succeeded: Bool {
        gate.allowed && !fatalBlocker && !commits.isEmpty && commits.allSatisfy { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
    }
}

nonisolated struct CanonicalLibraryMetadataCanaryResult: Codable, Equatable, Sendable {
    var configuration: CanonicalLibraryMetadataCanaryConfiguration
    var cutoverResult: CanonicalLibraryMetadataCutoverResult
    var selection: CanonicalLibraryMetadataCanarySelectionResult
    var observationReport: CanonicalLibraryMetadataCanaryObservationReport

    nonisolated var succeeded: Bool {
        cutoverResult.succeeded
    }
}

nonisolated struct CanonicalLibraryMetadataCanaryStageResult: Codable, Equatable, Sendable {
    var cutoverResult: CanonicalLibraryMetadataCutoverResult
    var selection: CanonicalLibraryMetadataCanarySelectionResult
    var stageObservationReport: CanonicalLibraryMetadataCanaryStageObservationReport

    nonisolated var succeeded: Bool {
        cutoverResult.succeeded
    }
}

nonisolated struct CanonicalLibraryMetadataCutoverRunner: Sendable {
    nonisolated init() {}

    nonisolated func evaluateGate(
        mode: CanonicalCutoverMode,
        policy: CanonicalLibraryMetadataCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger
    ) -> CanonicalLibraryMetadataCutoverGate {
        var failures: [CanonicalLibraryMetadataCutoverFailure] = []
        if mode == .disabled {
            failures.append(.disabled)
        }
        if mode != .canary && mode != .guardedExecuteCommit {
            failures.append(.unsupportedMode)
        }
        if token == nil {
            failures.append(.missingToken)
        }
        if token?.ownerApproved != true {
            failures.append(.missingOwnerApproval)
        }
        let requiredDomains = Set(candidates.filter { $0.cutoverActionKind.isExecutableMetadata }.map { $0.domain.productionDomain })
        if requiredDomains.isEmpty {
            failures.append(.unsupportedAction)
        } else if !requiredDomains.allSatisfy({ evidence.rollbackPlan?.covers(domain: $0) == true }) {
            failures.append(.missingRollback)
        }
        if !evidence.noCommitEvidenceAvailable { failures.append(.missingNoCommitEvidence) }
        if !evidence.dryRunEquivalenceVerified { failures.append(.missingDryRunEquivalence) }
        if !evidence.executionShadowVerified { failures.append(.missingExecutionShadowEvidence) }
        if !evidence.realDataShadowCopyVerified { failures.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.noBlockingDivergence { failures.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict || candidates.contains(where: \.unresolvedConflict) { failures.append(.unresolvedConflict) }
        if !evidence.metadataManifestRouteEvidenceAvailable { failures.append(.missingMetadataManifestRouteEvidence) }
        if !evidence.productionPortAvailable { failures.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { failures.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { failures.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { failures.append(.rollbackCheckpointUnavailable) }
        if !evidence.rollbackVerified { failures.append(.rollbackVerificationMissing) }
        if !evidence.productionRootDisabledByDefault { failures.append(.productionRootEnabledByDefault) }
        if evidence.applyPortMode == .testRootBound && !evidence.testRootUsed { failures.append(.testRootMissing) }
        if !evidence.legacyFallbackAvailable { failures.append(.legacyFallbackUnavailable) }
        if trigger == .viewRefresh || trigger == .retryDrainer { failures.append(.unsupportedMode) }
        if candidates.contains(where: { $0.cutoverActionKind == .conflictRecord }) { failures.append(.conflictDetected) }
        if candidates.contains(where: { $0.cutoverActionKind == .tombstoneMarkerUnsupportedForThisRound }) { failures.append(.tombstoneUnsupportedForThisRound) }
        if candidates.contains(where: \.hasActiveVsTombstoneConflict) { failures.append(.activeVsTombstoneConflict) }
        if candidates.contains(where: \.hasResourceMoveAttempt) { failures.append(.resourceMoveAttempted) }
        if candidates.contains(where: \.folderHierarchyMutationAttempted) { failures.append(.folderHierarchyMutationUnsupported) }
        if candidates.contains(where: \.parentMissingKnown) { failures.append(.parentMissing) }
        if candidates.contains(where: \.hasObjectIDInstability) { failures.append(.objectIDInstability) }
        if CanonicalLibraryMetadataCutoverCandidate.folderHierarchyCycleDetected(in: candidates) { failures.append(.cycleDetected) }
        if mode == .canary {
            if policy.canaryMaxObjectsPerSyncRun == 0 && !policy.stagePolicy.requestedStage.isExecutable {
                failures.append(.disabled)
            }
            if policy.canaryMaxObjectsPerSyncRun == 1 && !policy.stagePolicy.requestedStage.isExecutable && !policy.allowsInternalN1Execution {
                failures.append(.missingInternalCanaryConfiguration)
            }
            if policy.canaryMaxObjectsPerSyncRun > 1 && !policy.stagePolicy.requestedStage.isExecutable {
                failures.append(.canaryBudgetAboveOneDenied)
            }
            if policy.stagePolicy.requestedStage.isExecutable {
                let stageGate = CanonicalLibraryMetadataCanaryStageGate(policy: policy.stagePolicy, evidence: evidence)
                failures.append(contentsOf: stageGate.failures)
            }
        }
        return CanonicalLibraryMetadataCutoverGate(
            mode: mode,
            failures: failures,
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            reason: failures.isEmpty ? "allowed" : failures.map(\.rawValue).joined(separator: ",")
        )
    }

    nonisolated func run(
        mode: CanonicalCutoverMode,
        policy: CanonicalLibraryMetadataCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        executor: any CanonicalLibraryMetadataCutoverExecutor
    ) async -> CanonicalLibraryMetadataCutoverResult {
        let gate = evaluateGate(mode: mode, policy: policy, token: token, evidence: evidence, candidates: candidates, trigger: trigger)
        var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic] = [
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataCutoverGateEvaluated,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.reason
            )
        ]
        if !gate.allowed {
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataCutoverGateBlocked,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: gate.failures.map(\.rawValue).joined(separator: ",")
                )
            )
            return CanonicalLibraryMetadataCutoverResult(
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

        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataCanaryStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "started",
                reason: "candidateCount=\(candidates.count)"
            )
        )
        let selection = CanonicalLibraryMetadataCanarySelector().select(
            mode: mode,
            policy: policy,
            trigger: trigger,
            evidence: evidence,
            candidates: candidates
        )
        var commits: [CanonicalLibraryMetadataProductionCommitResult] = []
        var rollbacks: [CanonicalLibraryMetadataRollbackExecutionResult] = []
        var legacyFallbackUsed = false
        var fatalBlocker = false
        for candidate in selection.selectedCutoverCandidates {
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataCommitStarted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: candidate.domain,
                    objectID: candidate.objectID,
                    objectKind: candidate.objectKind,
                    action: candidate.cutoverActionKind.rawValue,
                    result: "started",
                    hash: candidate.expectedMetadataHash
                )
            )
            let commit = await executor.commitLibraryMetadata(candidate)
            commits.append(commit)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                diagnostics.append(
                    CanonicalLibraryMetadataCutoverDiagnostic(
                        kind: .canonicalLibraryMetadataCommitCompleted,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "committed",
                        hash: candidate.expectedMetadataHash
                    )
                )
            } else {
                legacyFallbackUsed = true
                diagnostics.append(
                    CanonicalLibraryMetadataCutoverDiagnostic(
                        kind: .canonicalLibraryMetadataCommitFailed,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "failed",
                        reason: commit.failureKind?.rawValue ?? commit.reason,
                        hash: candidate.expectedMetadataHash
                    )
                )
                diagnostics.append(
                    CanonicalLibraryMetadataCutoverDiagnostic(
                        kind: .canonicalLibraryMetadataRollbackStarted,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "started"
                    )
                )
                let rollback = await executor.rollbackLibraryMetadata(candidate, reason: commit.failureKind ?? .postconditionMismatch)
                rollbacks.append(rollback)
                fatalBlocker = fatalBlocker || rollback.fatal || !rollback.succeeded
                diagnostics.append(
                    CanonicalLibraryMetadataCutoverDiagnostic(
                        kind: rollback.succeeded ? .canonicalLibraryMetadataRollbackCompleted : .canonicalLibraryMetadataRollbackFailed,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: rollback.succeeded ? "rolledBack" : "rollbackFailed",
                        reason: rollback.reason
                    )
                )
                diagnostics.append(
                    CanonicalLibraryMetadataCutoverDiagnostic(
                        kind: .canonicalLibraryMetadataCanaryStageStoppedAfterFailure,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "stopped",
                        reason: rollback.succeeded ? "legacyFallbackForRemainingCandidates" : "fatalRollbackFailure"
                    )
                )
                break
            }
        }
        let successfulActionIDs = commits
            .filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
            .map(\.actionID)
            .sorted()
        if !successfulActionIDs.isEmpty {
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataDuplicateLegacySuppressed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "candidate",
                    reason: "successOnly"
                )
            )
        }
        if legacyFallbackUsed {
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataLegacyFallbackUsed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "used",
                    reason: "commitFailureOrRollback"
                )
            )
        }
        let readSide = selection.selectedCutoverCandidates.first.map {
            CanonicalLibraryMetadataReadSideParallelProjectionResult(
                candidate: $0,
                equivalent: commits.first?.committed == true,
                legacyHash: $0.expectedMetadataHash,
                reason: commits.first?.committed == true ? "parallelReadEquivalent" : "parallelReadDivergent"
            )
        }
        if let readSide {
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataUIProjectionParallelReadStarted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: readSide.domain,
                    objectID: readSide.objectID,
                    objectKind: readSide.objectKind,
                    result: "started"
                )
            )
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: readSide.equivalent ? .canonicalLibraryMetadataUIProjectionParallelReadEquivalent : .canonicalLibraryMetadataUIProjectionParallelReadDivergent,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: readSide.domain,
                    objectID: readSide.objectID,
                    objectKind: readSide.objectKind,
                    result: readSide.equivalent ? "equivalent" : "divergent",
                    reason: readSide.reason
                )
            )
        }
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataCanaryCompleted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: successfulActionIDs.isEmpty ? "noSuccessfulCommit" : "completed",
                reason: "attempted=\(selection.selectedCandidates.count)"
            )
        )
        return CanonicalLibraryMetadataCutoverResult(
            gate: gate,
            commits: commits,
            rollbackResults: rollbacks,
            diagnostics: diagnostics,
            legacyFallbackUsed: legacyFallbackUsed,
            duplicateLegacySuppressedActionIDs: successfulActionIDs,
            canaryAttemptedCount: selection.selectedCandidates.count,
            canarySucceeded: !successfulActionIDs.isEmpty && !fatalBlocker && !legacyFallbackUsed,
            fatalBlocker: fatalBlocker,
            readSideProjection: readSide
        )
    }
}

nonisolated struct CanonicalLibraryMetadataCanaryStageRunner: Sendable {
    nonisolated init() {}

    nonisolated func run(
        policy: CanonicalLibraryMetadataCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        localSnapshotAvailable: Bool = true,
        peerSnapshotAvailable: Bool = true,
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) async -> CanonicalLibraryMetadataCanaryStageResult {
        let stagePolicy = policy.stagePolicy
        let stage = stagePolicy.requestedStage
        let evidenceReport = CanonicalLibraryMetadataStageEvidenceReport.from(
            evidence: evidence,
            policy: stagePolicy
        )
        var diagnostics = Self.initialDiagnostics(
            stagePolicy: stagePolicy,
            evidenceReport: evidenceReport,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            candidateCount: candidates.count
        )
        let safetyReports = candidates.map {
            CanonicalLibraryMetadataCanaryCandidateSafety(candidate: $0, evidence: evidence)
        }
        let strictFailures = Self.strictFailures(
            policy: policy,
            token: token,
            evidence: evidence,
            matrix: matrix,
            trigger: trigger,
            localSnapshotAvailable: localSnapshotAvailable,
            peerSnapshotAvailable: peerSnapshotAvailable,
            executorAvailable: executor != nil
        )
        var selection = CanonicalLibraryMetadataCanarySelector().select(
            mode: .canary,
            policy: policy,
            trigger: trigger,
            evidence: evidence,
            candidates: candidates
        )
        if !strictFailures.isEmpty {
            selection = Self.selectionBlockedByRunFailures(
                selection,
                failures: strictFailures,
                evaluatedCandidateCount: candidates.count
            )
        }
        diagnostics.append(contentsOf: Self.selectionDiagnostics(
            selection: selection,
            safetyReports: safetyReports,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole
        ))

        guard strictFailures.isEmpty else {
            return Self.blockedResult(
                policy: policy,
                selection: selection,
                safetyReports: safetyReports,
                evidence: evidence,
                evidenceReport: evidenceReport,
                diagnostics: diagnostics,
                failures: strictFailures,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                reason: strictFailures.map(\.rawValue).joined(separator: ",")
            )
        }
        guard !selection.selectedCutoverCandidates.isEmpty else {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataCanaryStageBlocked,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "noEligibleCandidate",
                    reason: selection.blockers.map(\.reason.rawValue).joined(separator: ",")
                )
            )
            return Self.blockedResult(
                policy: policy,
                selection: selection,
                safetyReports: safetyReports,
                evidence: evidence,
                evidenceReport: evidenceReport,
                diagnostics: diagnostics,
                failures: [.unsupportedAction],
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                noEligible: true,
                reason: "noEligibleCandidate"
            )
        }
        guard let executor else {
            return Self.blockedResult(
                policy: policy,
                selection: selection,
                safetyReports: safetyReports,
                evidence: evidence,
                evidenceReport: evidenceReport,
                diagnostics: diagnostics,
                failures: [.commitExecutorUnavailable],
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                reason: "commitExecutorUnavailable"
            )
        }

        let gate = CanonicalLibraryMetadataCutoverRunner().evaluateGate(
            mode: .canary,
            policy: policy,
            token: token,
            evidence: evidence,
            candidates: selection.selectedCutoverCandidates,
            trigger: trigger
        )
        diagnostics.append(
            Self.diagnostic(
                gate.allowed ? .canonicalLibraryMetadataCanaryStageAllowed : .canonicalLibraryMetadataCanaryStageBlocked,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.reason
            )
        )
        guard gate.allowed else {
            return Self.blockedResult(
                policy: policy,
                selection: selection,
                safetyReports: safetyReports,
                evidence: evidence,
                evidenceReport: evidenceReport,
                diagnostics: diagnostics,
                failures: gate.failures,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                reason: gate.reason
            )
        }

        diagnostics.append(
            Self.diagnostic(
                stage == .allEligible ? .canonicalLibraryMetadataCanaryStageAllEligibleStarted : .canonicalLibraryMetadataCanaryStageStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "started",
                reason: "stage=\(stage.rawValue);selected=\(selection.selectedCandidates.count)"
            )
        )

        var commits: [CanonicalLibraryMetadataProductionCommitResult] = []
        var rollbacks: [CanonicalLibraryMetadataRollbackExecutionResult] = []
        var readSideProjection: CanonicalLibraryMetadataReadSideParallelProjectionResult?
        var readSideEquivalentCount = 0
        var readSideDivergentCount = 0
        var legacyFallbackUsed = false
        var fatalBlocker = false

        for candidate in selection.selectedCutoverCandidates {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataCanaryStageCandidateExecuted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: candidate.domain,
                    objectID: candidate.objectID,
                    objectKind: candidate.objectKind,
                    action: candidate.cutoverActionKind.rawValue,
                    result: "started",
                    hash: candidate.expectedMetadataHash
                )
            )
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataCommitStarted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: candidate.domain,
                    objectID: candidate.objectID,
                    objectKind: candidate.objectKind,
                    action: candidate.cutoverActionKind.rawValue,
                    result: "started",
                    hash: candidate.expectedMetadataHash
                )
            )
            let commit = await executor.commitLibraryMetadata(candidate)
            commits.append(commit)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalLibraryMetadataCommitCompleted,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "committed",
                        hash: candidate.expectedMetadataHash
                    )
                )
                let projection = CanonicalLibraryMetadataReadSideParallelProjectionResult(
                    candidate: candidate,
                    equivalent: evidence.readSideParallelEquivalent,
                    legacyHash: candidate.expectedMetadataHash,
                    reason: evidence.readSideParallelEquivalent ? "expandedParallelReadEquivalent" : "expandedParallelReadDivergent"
                )
                if readSideProjection == nil {
                    readSideProjection = projection
                }
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalLibraryMetadataExpandedReadSideParallelStarted,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: projection.domain,
                        objectID: projection.objectID,
                        objectKind: projection.objectKind,
                        result: "started"
                    )
                )
                diagnostics.append(
                    Self.diagnostic(
                        projection.equivalent ? .canonicalLibraryMetadataExpandedReadSideParallelEquivalent : .canonicalLibraryMetadataExpandedReadSideParallelDivergent,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: projection.domain,
                        objectID: projection.objectID,
                        objectKind: projection.objectKind,
                        result: projection.equivalent ? "equivalent" : "divergent",
                        reason: projection.reason
                    )
                )
                if projection.equivalent {
                    readSideEquivalentCount += 1
                } else {
                    readSideDivergentCount += 1
                }
            } else {
                legacyFallbackUsed = true
                readSideDivergentCount += 1
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalLibraryMetadataCommitFailed,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "failed",
                        reason: commit.failureKind?.rawValue ?? commit.reason,
                        hash: candidate.expectedMetadataHash
                    )
                )
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalLibraryMetadataRollbackStarted,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "started"
                    )
                )
                let rollback = await executor.rollbackLibraryMetadata(
                    candidate,
                    reason: commit.failureKind ?? .postconditionMismatch
                )
                rollbacks.append(rollback)
                fatalBlocker = fatalBlocker || rollback.fatal || !rollback.succeeded
                diagnostics.append(
                    Self.diagnostic(
                        rollback.succeeded ? .canonicalLibraryMetadataRollbackCompleted : .canonicalLibraryMetadataRollbackFailed,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: rollback.succeeded ? "rolledBack" : "rollbackFailed",
                        reason: rollback.reason
                    )
                )
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalLibraryMetadataCanaryStageStoppedAfterFailure,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        domain: candidate.domain,
                        objectID: candidate.objectID,
                        objectKind: candidate.objectKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "stopped",
                        reason: rollback.succeeded ? "legacyFallbackForRemainingCandidates" : "fatalRollbackFailure"
                    )
                )
                break
            }
        }

        let successfulActionIDs = commits
            .filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
            .map(\.actionID)
            .sorted()
        if !successfulActionIDs.isEmpty {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataDuplicateLegacySuppressed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "successOnly",
                    reason: "stage=\(stage.rawValue)"
                )
            )
        }
        if legacyFallbackUsed || commits.count < selection.selectedCandidates.count {
            legacyFallbackUsed = true
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataLegacyFallbackUsed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "used",
                    reason: "failedOrUnexecutedCandidates"
                )
            )
        }

        let report = Self.observationReport(
            policy: policy,
            selection: selection,
            safetyReports: safetyReports,
            commits: commits,
            rollbacks: rollbacks,
            evidenceReport: evidenceReport,
            fatalBlocker: fatalBlocker,
            readSideEquivalentCount: readSideEquivalentCount,
            readSideDivergentCount: readSideDivergentCount
        )
        diagnostics.append(
            Self.diagnostic(
                .canonicalLibraryMetadataCanaryStageObservationRecorded,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: report.stage.rawValue,
                reason: report.diagnosticsSummary
            )
        )
        diagnostics.append(
            Self.diagnostic(
                report.nextStageEligible ? .canonicalLibraryMetadataCanaryStageNextStageEligible : .canonicalLibraryMetadataCanaryStageNextStageBlocked,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: report.nextStageEligible ? "eligible" : "blocked",
                reason: report.nextStageBlockers.map(\.rawValue).joined(separator: ",")
            )
        )
        diagnostics.append(
            Self.diagnostic(
                stage == .allEligible ? .canonicalLibraryMetadataCanaryStageAllEligibleCompleted : (fatalBlocker || report.failureCount > 0 ? .canonicalLibraryMetadataCanaryStageFailed : .canonicalLibraryMetadataCanaryStageCompleted),
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: fatalBlocker || report.failureCount > 0 ? "failed" : "completed",
                reason: "stage=\(stage.rawValue);executed=\(commits.count)"
            )
        )

        let legacyObservationStatus: CanonicalLibraryMetadataCanaryObservationStatus
        if fatalBlocker {
            legacyObservationStatus = .fatalRollbackFailure
        } else if report.failureCount > 0 {
            legacyObservationStatus = .failedRolledBack
        } else {
            legacyObservationStatus = .committed
        }
        let legacyObservation = CanonicalLibraryMetadataCanaryObservationReport(
            status: legacyObservationStatus,
            syncRunID: syncRunID,
            nodeRole: nodeRole,
            selectedCandidateCount: selection.selectedCandidates.count,
            blockedCandidateCount: selection.blockers.count,
            attemptedCommitCount: commits.count,
            successfulCommitCount: successfulActionIDs.count,
            rollbackCount: rollbacks.count,
            duplicateSuppressionApplied: !successfulActionIDs.isEmpty,
            legacyFallbackPreserved: legacyFallbackUsed || successfulActionIDs.count < selection.selectedCandidates.count,
            readSideParallelEquivalent: report.readSideParallelDivergentCount == 0,
            fatalBlocker: fatalBlocker,
            reason: legacyObservationStatus.rawValue
        )
        let cutoverResult = CanonicalLibraryMetadataCutoverResult(
            gate: gate,
            commits: commits,
            rollbackResults: rollbacks,
            diagnostics: diagnostics,
            legacyFallbackUsed: legacyFallbackUsed,
            duplicateLegacySuppressedActionIDs: successfulActionIDs,
            canaryAttemptedCount: commits.count,
            canarySucceeded: report.nextStageEligible || (stage == .allEligible && report.failureCount == 0 && !fatalBlocker),
            fatalBlocker: fatalBlocker,
            readSideProjection: readSideProjection,
            canarySelection: selection,
            candidateSafetyReports: safetyReports,
            observationReport: legacyObservation,
            stageObservationReport: report
        )
        return CanonicalLibraryMetadataCanaryStageResult(
            cutoverResult: cutoverResult,
            selection: selection,
            stageObservationReport: report
        )
    }

    private nonisolated static func strictFailures(
        policy: CanonicalLibraryMetadataCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix,
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        executorAvailable: Bool
    ) -> [CanonicalLibraryMetadataCutoverFailure] {
        let stagePolicy = policy.stagePolicy
        var failures: [CanonicalLibraryMetadataCutoverFailure] = []
        if !stagePolicy.requestedStage.isExecutable {
            failures.append(.disabled)
        }
        if stagePolicy.requestedStage == .n1 {
            failures.append(.canaryStageBlocked)
        }
        if !stagePolicy.allowCandidateExecution {
            failures.append(.missingInternalCanaryConfiguration)
        }
        if stagePolicy.runtimeSwitchEnabled || policy.runtimeSwitchEnabled {
            failures.append(.runtimeSwitchDenied)
        }
        if stagePolicy.requestedStage == .allEligible && !policy.allowAllEligible {
            failures.append(.allEligibleCanaryDenied)
        }
        let matrixReport = matrix.validate()
        if !matrixReport.allowed {
            failures.append(.matrixValidationBlocked)
        }
        if matrixReport.activePilotDomain != .libraryMetadata {
            failures.append(.activePilotNotLibraryMetadata)
        }
        if token == nil {
            failures.append(.missingToken)
        }
        if token?.ownerApproved != true {
            failures.append(.missingOwnerApproval)
        }
        if !localSnapshotAvailable {
            failures.append(.missingRealDataShadowCopyEvidence)
        }
        if !peerSnapshotAvailable {
            failures.append(.peerSnapshotUnavailable)
        }
        if !executorAvailable {
            failures.append(.commitExecutorUnavailable)
        }
        if trigger == .viewRefresh || trigger == .retryDrainer {
            failures.append(.unsupportedMode)
        }
        if !evidence.noCommitEvidenceAvailable { failures.append(.missingNoCommitEvidence) }
        if !evidence.realDataShadowCopyVerified { failures.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.executionShadowVerified { failures.append(.missingExecutionShadowEvidence) }
        if !evidence.dryRunEquivalenceVerified { failures.append(.missingDryRunEquivalence) }
        if !evidence.noBlockingDivergence { failures.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict { failures.append(.unresolvedConflict) }
        if !evidence.metadataManifestRouteEvidenceAvailable { failures.append(.missingMetadataManifestRouteEvidence) }
        if !evidence.productionPortAvailable { failures.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { failures.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { failures.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { failures.append(.rollbackCheckpointUnavailable) }
        if evidence.rollbackPlan == nil { failures.append(.missingRollback) }
        if !evidence.rollbackVerified || !evidence.rollbackRehearsalPassed {
            failures.append(.rollbackVerificationMissing)
        }
        if !evidence.productionRootDisabledByDefault { failures.append(.productionRootEnabledByDefault) }
        if evidence.applyPortMode == .testRootBound && !evidence.testRootUsed { failures.append(.testRootMissing) }
        if !evidence.legacyFallbackAvailable { failures.append(.legacyFallbackUnavailable) }
        if !evidence.readSideParallelEquivalent { failures.append(.readSideParallelDivergence) }
        let stageGate = CanonicalLibraryMetadataCanaryStageGate(policy: stagePolicy, evidence: evidence)
        failures.append(contentsOf: stageGate.failures)
        return Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated static func initialDiagnostics(
        stagePolicy: CanonicalLibraryMetadataCanaryStagePolicy,
        evidenceReport: CanonicalLibraryMetadataStageEvidenceReport,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        candidateCount: Int
    ) -> [CanonicalLibraryMetadataCutoverDiagnostic] {
        [
            diagnostic(
                .canonicalLibraryMetadataCanaryStageEvaluated,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: stagePolicy.requestedStage.rawValue,
                reason: [
                    "candidateCount=\(candidateCount)",
                    "budget=\(stagePolicy.canaryBudget == Int.max ? "allEligible" : String(stagePolicy.canaryBudget))",
                    "allowExecution=\(stagePolicy.allowCandidateExecution)",
                    "evidence=\(evidenceReport.diagnosticsSummary)"
                ].joined(separator: ";")
            )
        ]
    }

    private nonisolated static func selectionDiagnostics(
        selection: CanonicalLibraryMetadataCanarySelectionResult,
        safetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety],
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> [CanonicalLibraryMetadataCutoverDiagnostic] {
        var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic] = []
        for blocker in selection.blockers where blocker.objectID != nil {
            let kind: CanonicalLibraryMetadataCutoverDiagnosticKind
            switch blocker.reason {
            case .resourceMoveAttempted:
                kind = .canonicalLibraryMetadataResourceMoveBlocked
            case .cycleDetected:
                kind = .canonicalLibraryMetadataHierarchyCycleBlocked
            case .objectIDInstability:
                kind = .canonicalLibraryMetadataObjectIDInstabilityBlocked
            default:
                kind = .canonicalLibraryMetadataCanaryStageCandidateSkipped
            }
            diagnostics.append(
                diagnostic(
                    kind,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: blocker.objectID,
                    result: "skipped",
                    reason: blocker.reason.rawValue
                )
            )
        }
        for report in safetyReports where !report.safe {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataUnsafeCandidateSkipped,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: report.candidate.domain,
                    objectID: report.candidate.objectID,
                    objectKind: report.candidate.objectKind,
                    action: report.candidate.actionKind.rawValue,
                    result: "skipped",
                    reason: report.blockers.map(\.rawValue).joined(separator: ","),
                    hashPrefix: report.candidate.metadataHashPrefix
                )
            )
        }
        return diagnostics
    }

    private nonisolated static func selectionBlockedByRunFailures(
        _ selection: CanonicalLibraryMetadataCanarySelectionResult,
        failures: [CanonicalLibraryMetadataCutoverFailure],
        evaluatedCandidateCount: Int
    ) -> CanonicalLibraryMetadataCanarySelectionResult {
        let runBlockers = failures.map {
            CanonicalLibraryMetadataCanarySelectionBlocker(objectID: nil, reason: blocker(for: $0))
        }
        return CanonicalLibraryMetadataCanarySelectionResult(
            selectedCandidates: [],
            blockers: selection.blockers + runBlockers,
            evaluatedCandidateCount: evaluatedCandidateCount,
            noEligibleCandidate: true
        )
    }

    private nonisolated static func blockedResult(
        policy: CanonicalLibraryMetadataCanaryPolicy,
        selection: CanonicalLibraryMetadataCanarySelectionResult,
        safetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety],
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        evidenceReport: CanonicalLibraryMetadataStageEvidenceReport,
        diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic],
        failures: [CanonicalLibraryMetadataCutoverFailure],
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        noEligible: Bool = false,
        reason: String
    ) -> CanonicalLibraryMetadataCanaryStageResult {
        let stage = policy.stagePolicy.requestedStage
        let gate = CanonicalLibraryMetadataCutoverGate(
            mode: .canary,
            failures: failures,
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            reason: reason
        )
        var diagnostics = diagnostics
        diagnostics.append(
            diagnostic(
                .canonicalLibraryMetadataCanaryStageBlocked,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: noEligible ? "noEligibleCandidate" : "blocked",
                reason: reason
            )
        )
        if failures.contains(.peerSnapshotUnavailable), nodeRole == .mac {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataN1MacPeerSnapshotUnavailable,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: "peerSnapshotUnavailable"
                )
            )
        }
        let report = observationReport(
            policy: policy,
            selection: selection,
            safetyReports: safetyReports,
            commits: [],
            rollbacks: [],
            evidenceReport: evidenceReport,
            fatalBlocker: !noEligible,
            readSideEquivalentCount: 0,
            readSideDivergentCount: 0,
            explicitBlockers: failures
        )
        diagnostics.append(
            diagnostic(
                .canonicalLibraryMetadataCanaryStageObservationRecorded,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: stage.rawValue,
                reason: report.diagnosticsSummary
            )
        )
        let legacyObservation = CanonicalLibraryMetadataCanaryObservationReport(
            status: noEligible ? .noEligibleCandidate : .blocked,
            syncRunID: syncRunID,
            nodeRole: nodeRole,
            selectedCandidateCount: 0,
            blockedCandidateCount: selection.blockers.count,
            attemptedCommitCount: 0,
            successfulCommitCount: 0,
            rollbackCount: 0,
            duplicateSuppressionApplied: false,
            legacyFallbackPreserved: true,
            readSideParallelEquivalent: evidence.readSideParallelEquivalent,
            resourceMoved: safetyReports.contains(where: \.resourceMoveAttempted),
            physicalDeleteAttempted: safetyReports.contains(where: \.physicalDeleteAttempted),
            contentBytesMutated: safetyReports.contains(where: \.contentBytesMutated),
            fatalBlocker: !noEligible,
            reason: reason
        )
        let cutoverResult = CanonicalLibraryMetadataCutoverResult(
            gate: gate,
            commits: [],
            rollbackResults: [],
            diagnostics: diagnostics,
            legacyFallbackUsed: true,
            duplicateLegacySuppressedActionIDs: [],
            canaryAttemptedCount: 0,
            canarySucceeded: false,
            fatalBlocker: !noEligible,
            readSideProjection: nil,
            canarySelection: selection,
            candidateSafetyReports: safetyReports,
            observationReport: legacyObservation,
            stageObservationReport: report
        )
        return CanonicalLibraryMetadataCanaryStageResult(
            cutoverResult: cutoverResult,
            selection: selection,
            stageObservationReport: report
        )
    }

    private nonisolated static func observationReport(
        policy: CanonicalLibraryMetadataCanaryPolicy,
        selection: CanonicalLibraryMetadataCanarySelectionResult,
        safetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety],
        commits: [CanonicalLibraryMetadataProductionCommitResult],
        rollbacks: [CanonicalLibraryMetadataRollbackExecutionResult],
        evidenceReport: CanonicalLibraryMetadataStageEvidenceReport,
        fatalBlocker: Bool,
        readSideEquivalentCount: Int,
        readSideDivergentCount: Int,
        explicitBlockers: [CanonicalLibraryMetadataCutoverFailure] = []
    ) -> CanonicalLibraryMetadataCanaryStageObservationReport {
        let stage = policy.stagePolicy.requestedStage
        let successCount = commits.filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }.count
        let failureCount = commits.count - successCount
        let rollbackFailureCount = rollbacks.filter { !$0.succeeded || $0.fatal }.count
        let blockerFailures = explicitBlockers + nextStageBlockers(
            stage: stage,
            selection: selection,
            successCount: successCount,
            failureCount: failureCount,
            rollbackFailureCount: rollbackFailureCount,
            fatalBlocker: fatalBlocker,
            readSideDivergentCount: readSideDivergentCount
        )
        let nextEligible = stage != .disabled
            && stage != .allEligible
            && selection.selectedCandidates.count > 0
            && commits.count == selection.selectedCandidates.count
            && successCount == selection.selectedCandidates.count
            && blockerFailures.isEmpty
        let unsafeSkipped = safetyReports.filter { !$0.safe }.count
        let failures = selection.blockers.map {
            CanonicalLibraryMetadataCanaryStageFailure(objectID: $0.objectID, blocker: $0.reason)
        }
        return CanonicalLibraryMetadataCanaryStageObservationReport(
            stage: stage,
            budget: stage.nominalCanaryBudget,
            selectedCount: selection.selectedCandidates.count,
            executedCount: commits.count,
            successCount: successCount,
            failureCount: failureCount,
            rollbackCount: rollbacks.count,
            rollbackFailureCount: rollbackFailureCount,
            legacyFallbackCount: max(0, selection.evaluatedCandidateCount - successCount),
            duplicateSuppressionCount: successCount,
            skippedCount: max(0, selection.evaluatedCandidateCount - selection.selectedCandidates.count),
            noEligibleCount: selection.selectedCandidates.isEmpty ? 1 : 0,
            unsafeCandidateSkippedCount: unsafeSkipped,
            resourceMoveBlockedCount: selection.blockers.filter { $0.reason == .resourceMoveAttempted }.count,
            hierarchyCycleBlockedCount: selection.blockers.filter { $0.reason == .cycleDetected }.count,
            objectIDInstabilityBlockedCount: selection.blockers.filter { $0.reason == .objectIDInstability }.count,
            fatalBlockerCount: fatalBlocker ? 1 : 0,
            readSideParallelEquivalentCount: readSideEquivalentCount,
            readSideParallelDivergentCount: readSideDivergentCount,
            nextStageEligible: nextEligible,
            nextStageBlockers: blockerFailures,
            recommendation: recommendation(stage: stage, nextEligible: nextEligible, fatalBlocker: fatalBlocker, failureCount: failureCount),
            runtimeSwitchEnabled: policy.runtimeSwitchEnabled || policy.stagePolicy.runtimeSwitchEnabled,
            failures: failures,
            evidenceReport: evidenceReport
        )
    }

    private nonisolated static func nextStageBlockers(
        stage: CanonicalLibraryMetadataCanaryStage,
        selection: CanonicalLibraryMetadataCanarySelectionResult,
        successCount: Int,
        failureCount: Int,
        rollbackFailureCount: Int,
        fatalBlocker: Bool,
        readSideDivergentCount: Int
    ) -> [CanonicalLibraryMetadataCutoverFailure] {
        var blockers: [CanonicalLibraryMetadataCutoverFailure] = []
        if selection.selectedCandidates.isEmpty {
            blockers.append(.unsupportedAction)
        }
        if successCount < selection.selectedCandidates.count {
            blockers.append(.previousStageFailure)
        }
        if failureCount > 0 {
            blockers.append(.previousStageFailure)
        }
        if rollbackFailureCount > 0 {
            blockers.append(.previousStageRollbackFailure)
        }
        if fatalBlocker {
            blockers.append(.rollbackFailure)
        }
        if readSideDivergentCount > 0 {
            blockers.append(.readSideParallelDivergence)
        }
        if stage == .allEligible {
            blockers.append(.allEligibleCanaryDenied)
        }
        return Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated static func recommendation(
        stage: CanonicalLibraryMetadataCanaryStage,
        nextEligible: Bool,
        fatalBlocker: Bool,
        failureCount: Int
    ) -> CanonicalLibraryMetadataCanaryStageRecommendation {
        if fatalBlocker {
            return .stopForFatalBlocker
        }
        if failureCount > 0 {
            return .holdForInvestigation
        }
        guard nextEligible else {
            return stage == .disabled ? .stayDisabled : .observeCurrentStage
        }
        switch stage {
        case .n1:
            return .advanceToN3
        case .n3:
            return .advanceToN10
        case .n10:
            return .advanceToAllEligible
        case .allEligible:
            return .observeCurrentStage
        case .disabled:
            return .stayDisabled
        }
    }

    private nonisolated static func blocker(
        for failure: CanonicalLibraryMetadataCutoverFailure
    ) -> CanonicalLibraryMetadataCanaryBlocker {
        switch failure {
        case .missingOwnerApproval, .missingToken:
            return .missingOwnerApproval
        case .matrixValidationBlocked:
            return .matrixBlocked
        case .activePilotNotLibraryMetadata:
            return .activePilotNotLibraryMetadata
        case .commitExecutorUnavailable:
            return .commitExecutorUnavailable
        case .peerSnapshotUnavailable:
            return .peerSnapshotUnavailable
        case .runtimeSwitchDenied:
            return .runtimeSwitchDenied
        case .allEligibleCanaryDenied, .canaryBudgetAboveOneDenied:
            return .allEligibleDenied
        case .defaultEnablementDenied:
            return .defaultEnablementDenied
        case .missingReadSideParallelEvidence, .readSideParallelDivergence:
            return .readSideParallelMissing
        case .resourceMoveAttempted:
            return .resourceMoveAttempted
        case .folderHierarchyMutationUnsupported:
            return .folderHierarchyMutationUnsupported
        case .objectIDInstability:
            return .objectIDInstability
        case .parentMissing:
            return .parentMissing
        case .cycleDetected:
            return .cycleDetected
        case .conflictDetected:
            return .conflictDetected
        case .unresolvedConflict:
            return .unresolvedConflict
        case .disabled:
            return .disabled
        case .unsupportedMode:
            return .unsupportedMode
        case .missingInternalCanaryConfiguration:
            return .missingInternalCanaryConfiguration
        case .multipleEligibleCandidatesDenied:
            return .canaryBudgetAboveOneDenied
        case .missingCanaryStageEvidence:
            return .canaryStageEvidenceMissing
        case .canaryStageBlocked, .canaryStageOrderViolation:
            return .canaryStageBlocked
        default:
            return .insufficientEvidence
        }
    }

    private nonisolated static func diagnostic(
        _ kind: CanonicalLibraryMetadataCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalLibraryMetadataCutoverDomain? = nil,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        action: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil,
        hashPrefix: String? = nil
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        let hash = hash ?? hashPrefix.map { CanonicalHash($0) }
        return CanonicalLibraryMetadataCutoverDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            domain: domain,
            objectID: objectID,
            objectKind: objectKind,
            action: action,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}

nonisolated struct CanonicalLibraryMetadataN1CanaryRunner: Sendable {
    nonisolated init() {}

    nonisolated func run(
        configuration: CanonicalLibraryMetadataCanaryConfiguration,
        policy: CanonicalLibraryMetadataCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        candidates: [CanonicalLibraryMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        localSnapshotAvailable: Bool = true,
        peerSnapshotAvailable: Bool = true,
        executor: (any CanonicalLibraryMetadataCutoverExecutor)?
    ) async -> CanonicalLibraryMetadataCanaryResult {
        let strictFailures = Self.strictConfigurationFailures(
            configuration: configuration,
            policy: policy,
            token: token,
            evidence: evidence,
            matrix: matrix,
            trigger: trigger,
            localSnapshotAvailable: localSnapshotAvailable,
            peerSnapshotAvailable: peerSnapshotAvailable,
            executorAvailable: executor != nil
        )
        let safetyReports = candidates.map {
            CanonicalLibraryMetadataCanaryCandidateSafety(candidate: $0, evidence: evidence)
        }
        var diagnostics = Self.initialDiagnostics(
            configuration: configuration,
            policy: policy,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            candidateCount: candidates.count,
            failures: strictFailures
        )
        let selectorPolicy = CanonicalLibraryMetadataCanaryPolicy(
            canaryMaxObjectsPerSyncRun: 1,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true
        )
        var selection = CanonicalLibraryMetadataCanarySelector().select(
            mode: .canary,
            policy: selectorPolicy,
            trigger: trigger,
            evidence: evidence,
            candidates: candidates
        )
        if !strictFailures.isEmpty {
            selection = Self.selectionBlockedByRunFailures(
                selection,
                failures: strictFailures,
                evaluatedCandidateCount: candidates.count
            )
        }
        diagnostics.append(contentsOf: Self.selectionDiagnostics(
            selection: selection,
            safetyReports: safetyReports,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole
        ))

        guard strictFailures.isEmpty else {
            return Self.blockedResult(
                configuration: configuration,
                selection: selection,
                safetyReports: safetyReports,
                diagnostics: diagnostics,
                failures: strictFailures,
                evidence: evidence,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                reason: strictFailures.map(\.rawValue).joined(separator: ",")
            )
        }
        guard let selected = selection.selectedCutoverCandidates.first else {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataN1NoEligibleCandidate,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "noEligibleCandidate",
                    reason: "legacyFallbackPreserved"
                )
            )
            return Self.blockedResult(
                configuration: configuration,
                selection: selection,
                safetyReports: safetyReports,
                diagnostics: diagnostics,
                failures: [.unsupportedAction],
                evidence: evidence,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                status: .noEligibleCandidate,
                reason: "noEligibleCandidate"
            )
        }
        guard let executor else {
            return Self.blockedResult(
                configuration: configuration,
                selection: selection,
                safetyReports: safetyReports,
                diagnostics: diagnostics,
                failures: [.commitExecutorUnavailable],
                evidence: evidence,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                reason: "commitExecutorUnavailable"
            )
        }

        diagnostics.append(
            Self.diagnostic(
                .canonicalLibraryMetadataN1CanaryStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                domain: selected.domain,
                objectID: selected.objectID,
                objectKind: selected.objectKind,
                action: selected.cutoverActionKind.rawValue,
                result: "started",
                hash: selected.expectedMetadataHash
            )
        )
        diagnostics.append(
            Self.diagnostic(
                .canonicalLibraryMetadataN1CommitStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                domain: selected.domain,
                objectID: selected.objectID,
                objectKind: selected.objectKind,
                action: selected.cutoverActionKind.rawValue,
                result: "started",
                hash: selected.expectedMetadataHash
            )
        )
        var cutoverResult = await CanonicalLibraryMetadataCutoverRunner().run(
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
            diagnostics.append(
                Self.diagnostic(
                    commit.committed ? .canonicalLibraryMetadataN1CommitCompleted : .canonicalLibraryMetadataN1CommitFailed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: selected.domain,
                    objectID: selected.objectID,
                    objectKind: selected.objectKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: commit.committed ? "committed" : "failed",
                    reason: commit.failureKind?.rawValue ?? commit.reason,
                    hash: selected.expectedMetadataHash
                )
            )
            diagnostics.append(
                Self.diagnostic(
                    commit.postconditionVerified ? .canonicalLibraryMetadataN1PostconditionVerified : .canonicalLibraryMetadataN1PostconditionFailed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: selected.domain,
                    objectID: selected.objectID,
                    objectKind: selected.objectKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: commit.postconditionVerified ? "verified" : "failed",
                    hash: selected.expectedMetadataHash
                )
            )
        }
        for rollback in cutoverResult.rollbackResults {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataN1RollbackStarted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: selected.domain,
                    objectID: selected.objectID,
                    objectKind: selected.objectKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: "started",
                    reason: rollback.checkpointID
                )
            )
            diagnostics.append(
                Self.diagnostic(
                    rollback.succeeded ? .canonicalLibraryMetadataN1RollbackCompleted : .canonicalLibraryMetadataN1RollbackFailed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: selected.domain,
                    objectID: selected.objectID,
                    objectKind: selected.objectKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: rollback.succeeded ? "rolledBack" : "rollbackFailed",
                    reason: rollback.reason
                )
            )
        }
        if cutoverResult.legacyFallbackUsed {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataN1LegacyFallbackUsed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "legacyFallbackUsed",
                    reason: "commitFailureOrRollback"
                )
            )
        }
        if !cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataN1DuplicateLegacySuppressed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: selected.domain,
                    objectID: selected.objectID,
                    objectKind: selected.objectKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: "successOnly",
                    reason: "legacyDuplicateSuppressionCandidate"
                )
            )
        }
        if let readSide = cutoverResult.readSideProjection {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataN1ReadSideParallelStarted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: readSide.domain,
                    objectID: readSide.objectID,
                    objectKind: readSide.objectKind,
                    result: "started"
                )
            )
            diagnostics.append(
                Self.diagnostic(
                    readSide.equivalent ? .canonicalLibraryMetadataN1ReadSideParallelEquivalent : .canonicalLibraryMetadataN1ReadSideParallelDivergent,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: readSide.domain,
                    objectID: readSide.objectID,
                    objectKind: readSide.objectKind,
                    result: readSide.equivalent ? "equivalent" : "divergent",
                    reason: readSide.reason
                )
            )
        }
        let observation = Self.observation(
            syncRunID: syncRunID,
            nodeRole: nodeRole,
            selection: selection,
            safetyReports: safetyReports,
            cutoverResult: cutoverResult,
            evidence: evidence
        )
        diagnostics.append(
            Self.diagnostic(
                .canonicalLibraryMetadataN1ObservationRecorded,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: observation.status.rawValue,
                reason: observation.reason
            )
        )
        if cutoverResult.fatalBlocker {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalLibraryMetadataN1FatalBlocker,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "fatal",
                    reason: "rollbackFailure"
                )
            )
        }
        cutoverResult.diagnostics = diagnostics + cutoverResult.diagnostics
        cutoverResult.canaryConfiguration = configuration
        cutoverResult.canarySelection = selection
        cutoverResult.candidateSafetyReports = safetyReports
        cutoverResult.observationReport = observation
        return CanonicalLibraryMetadataCanaryResult(
            configuration: configuration,
            cutoverResult: cutoverResult,
            selection: selection,
            observationReport: observation
        )
    }

    private nonisolated static func strictConfigurationFailures(
        configuration: CanonicalLibraryMetadataCanaryConfiguration,
        policy: CanonicalLibraryMetadataCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix,
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        executorAvailable: Bool
    ) -> [CanonicalLibraryMetadataCutoverFailure] {
        var failures: [CanonicalLibraryMetadataCutoverFailure] = []
        if configuration.mode == .disabled {
            failures.append(.disabled)
        }
        if configuration.mode != .n1 {
            failures.append(.unsupportedMode)
        }
        if configuration.domain != .libraryMetadata {
            failures.append(.unsupportedDomain)
        }
        if configuration.canaryMaxObjectsPerSyncRun == 0 {
            failures.append(.disabled)
        }
        if configuration.canaryMaxObjectsPerSyncRun > 1 || policy.canaryMaxObjectsPerSyncRun > 1 {
            failures.append(.canaryBudgetAboveOneDenied)
        }
        if configuration.canaryMaxObjectsPerSyncRun != 1 || policy.canaryMaxObjectsPerSyncRun != 1 {
            failures.append(.missingInternalCanaryConfiguration)
        }
        if !configuration.explicitInternalTestConfiguration || !policy.allowsInternalN1Execution {
            failures.append(.missingInternalCanaryConfiguration)
        }
        if policy.stagePolicy.requestedStage.isExecutable || policy.stagePolicy.allowCandidateExecution {
            failures.append(policy.stagePolicy.requestedStage == .allEligible ? .allEligibleCanaryDenied : .canaryStageBlocked)
        }
        if configuration.allowAllEligible || policy.allowAllEligible {
            failures.append(.allEligibleCanaryDenied)
        }
        if configuration.runtimeSwitchEnabled || policy.runtimeSwitchEnabled || policy.stagePolicy.runtimeSwitchEnabled {
            failures.append(.runtimeSwitchDenied)
        }
        if configuration.releaseDefaultEnabled {
            failures.append(.defaultEnablementDenied)
        }
        let matrixReport = matrix.validate()
        if !matrixReport.allowed {
            failures.append(.matrixValidationBlocked)
        }
        if matrixReport.activePilotDomain != .libraryMetadata {
            failures.append(.activePilotNotLibraryMetadata)
        }
        if configuration.productionTokenRequired && token == nil {
            failures.append(.missingToken)
        }
        if configuration.ownerApprovalRequired && token?.ownerApproved != true {
            failures.append(.missingOwnerApproval)
        }
        if !localSnapshotAvailable {
            failures.append(.missingRealDataShadowCopyEvidence)
        }
        if !peerSnapshotAvailable {
            failures.append(.peerSnapshotUnavailable)
        }
        if !executorAvailable {
            failures.append(.commitExecutorUnavailable)
        }
        if trigger == .viewRefresh || trigger == .retryDrainer {
            failures.append(.unsupportedMode)
        }
        if !evidence.noCommitEvidenceAvailable { failures.append(.missingNoCommitEvidence) }
        if !evidence.realDataShadowCopyVerified { failures.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.executionShadowVerified { failures.append(.missingExecutionShadowEvidence) }
        if !evidence.dryRunEquivalenceVerified { failures.append(.missingDryRunEquivalence) }
        if !evidence.noBlockingDivergence { failures.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict { failures.append(.unresolvedConflict) }
        if !evidence.metadataManifestRouteEvidenceAvailable { failures.append(.missingMetadataManifestRouteEvidence) }
        if !evidence.productionPortAvailable { failures.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { failures.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { failures.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { failures.append(.rollbackCheckpointUnavailable) }
        if configuration.rollbackPlanRequired && evidence.rollbackPlan == nil {
            failures.append(.missingRollback)
        }
        if !evidence.rollbackVerified || !evidence.rollbackRehearsalPassed {
            failures.append(.rollbackVerificationMissing)
        }
        if !evidence.productionRootDisabledByDefault { failures.append(.productionRootEnabledByDefault) }
        if evidence.applyPortMode == .testRootBound && !evidence.testRootUsed { failures.append(.testRootMissing) }
        if !evidence.legacyFallbackAvailable { failures.append(.legacyFallbackUnavailable) }
        if !evidence.readSideParallelEquivalent { failures.append(.missingReadSideParallelEvidence) }
        return Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated static func initialDiagnostics(
        configuration: CanonicalLibraryMetadataCanaryConfiguration,
        policy: CanonicalLibraryMetadataCanaryPolicy,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        candidateCount: Int,
        failures: [CanonicalLibraryMetadataCutoverFailure]
    ) -> [CanonicalLibraryMetadataCutoverDiagnostic] {
        [
            diagnostic(
                .canonicalLibraryMetadataN1CanaryConfigured,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: failures.isEmpty ? "configured" : "blocked",
                reason: [
                    "mode=\(configuration.mode.rawValue)",
                    "domain=\(configuration.domain.rawValue)",
                    "budget=\(configuration.canaryMaxObjectsPerSyncRun)",
                    "explicitInternal=\(configuration.explicitInternalTestConfiguration)",
                    "policyBudget=\(policy.canaryMaxObjectsPerSyncRun)",
                    "candidateCount=\(candidateCount)"
                ].joined(separator: ";")
            ),
            diagnostic(
                .canonicalLibraryMetadataN1CandidateSelectionStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "started",
                reason: "candidateCount=\(candidateCount)"
            )
        ]
    }

    private nonisolated static func selectionDiagnostics(
        selection: CanonicalLibraryMetadataCanarySelectionResult,
        safetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety],
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> [CanonicalLibraryMetadataCutoverDiagnostic] {
        var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic] = []
        for selected in selection.selectedCandidates {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataN1CandidateSelected,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: selected.domain,
                    objectID: selected.objectID,
                    objectKind: selected.objectKind,
                    action: selected.actionKind.rawValue,
                    result: "selected",
                    reason: "metadataOnly=true",
                    hashPrefix: selected.metadataHashPrefix
                )
            )
        }
        for report in safetyReports where !report.safe {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataN1CandidateBlocked,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    domain: report.candidate.domain,
                    objectID: report.candidate.objectID,
                    objectKind: report.candidate.objectKind,
                    action: report.candidate.actionKind.rawValue,
                    result: "blocked",
                    reason: report.blockers.map(\.rawValue).joined(separator: ","),
                    hashPrefix: report.candidate.metadataHashPrefix
                )
            )
        }
        if selection.selectedCandidates.isEmpty {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataN1NoEligibleCandidate,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "noEligibleCandidate",
                    reason: selection.blockers.map(\.reason.rawValue).joined(separator: ",")
                )
            )
        }
        return diagnostics
    }

    private nonisolated static func selectionBlockedByRunFailures(
        _ selection: CanonicalLibraryMetadataCanarySelectionResult,
        failures: [CanonicalLibraryMetadataCutoverFailure],
        evaluatedCandidateCount: Int
    ) -> CanonicalLibraryMetadataCanarySelectionResult {
        let runBlockers = failures.map {
            CanonicalLibraryMetadataCanarySelectionBlocker(objectID: nil, reason: blocker(for: $0))
        }
        return CanonicalLibraryMetadataCanarySelectionResult(
            selectedCandidates: [],
            blockers: selection.blockers + runBlockers,
            evaluatedCandidateCount: evaluatedCandidateCount,
            noEligibleCandidate: true
        )
    }

    private nonisolated static func blocker(
        for failure: CanonicalLibraryMetadataCutoverFailure
    ) -> CanonicalLibraryMetadataCanaryBlocker {
        switch failure {
        case .missingOwnerApproval, .missingToken:
            return .missingOwnerApproval
        case .matrixValidationBlocked:
            return .matrixBlocked
        case .activePilotNotLibraryMetadata:
            return .activePilotNotLibraryMetadata
        case .commitExecutorUnavailable:
            return .commitExecutorUnavailable
        case .peerSnapshotUnavailable:
            return .peerSnapshotUnavailable
        case .runtimeSwitchDenied:
            return .runtimeSwitchDenied
        case .allEligibleCanaryDenied, .canaryBudgetAboveOneDenied:
            return .allEligibleDenied
        case .defaultEnablementDenied:
            return .defaultEnablementDenied
        case .missingReadSideParallelEvidence:
            return .readSideParallelMissing
        case .resourceMoveAttempted:
            return .resourceMoveAttempted
        case .folderHierarchyMutationUnsupported:
            return .folderHierarchyMutationUnsupported
        case .objectIDInstability:
            return .objectIDInstability
        case .parentMissing:
            return .parentMissing
        case .cycleDetected:
            return .cycleDetected
        case .conflictDetected:
            return .conflictDetected
        case .unresolvedConflict:
            return .unresolvedConflict
        default:
            return .insufficientEvidence
        }
    }

    private nonisolated static func blockedResult(
        configuration: CanonicalLibraryMetadataCanaryConfiguration,
        selection: CanonicalLibraryMetadataCanarySelectionResult,
        safetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety],
        diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic],
        failures: [CanonicalLibraryMetadataCutoverFailure],
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        status: CanonicalLibraryMetadataCanaryObservationStatus = .blocked,
        reason: String
    ) -> CanonicalLibraryMetadataCanaryResult {
        let gate = CanonicalLibraryMetadataCutoverGate(
            mode: configuration.mode.isExecutable ? .canary : .disabled,
            failures: failures,
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            reason: reason
        )
        var diagnostics = diagnostics
        if failures.contains(.peerSnapshotUnavailable), nodeRole == .mac {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataN1MacPeerSnapshotUnavailable,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: "peerSnapshotUnavailable"
                )
            )
        }
        if status != .noEligibleCandidate {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataN1FatalBlocker,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: reason
                )
            )
        }
        let observation = CanonicalLibraryMetadataCanaryObservationReport(
            status: status,
            syncRunID: syncRunID,
            nodeRole: nodeRole,
            selectedCandidateCount: 0,
            blockedCandidateCount: selection.blockers.count,
            attemptedCommitCount: 0,
            successfulCommitCount: 0,
            rollbackCount: 0,
            duplicateSuppressionApplied: false,
            legacyFallbackPreserved: true,
            readSideParallelEquivalent: evidence.readSideParallelEquivalent,
            resourceMoved: safetyReports.contains(where: \.resourceMoveAttempted),
            physicalDeleteAttempted: safetyReports.contains(where: \.physicalDeleteAttempted),
            contentBytesMutated: safetyReports.contains(where: \.contentBytesMutated),
            fatalBlocker: status != .noEligibleCandidate,
            reason: reason
        )
        diagnostics.append(
            diagnostic(
                .canonicalLibraryMetadataN1ObservationRecorded,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: observation.status.rawValue,
                reason: observation.reason
            )
        )
        let cutoverResult = CanonicalLibraryMetadataCutoverResult(
            gate: gate,
            commits: [],
            rollbackResults: [],
            diagnostics: diagnostics,
            legacyFallbackUsed: true,
            duplicateLegacySuppressedActionIDs: [],
            canaryAttemptedCount: 0,
            canarySucceeded: false,
            fatalBlocker: status != .noEligibleCandidate,
            readSideProjection: nil,
            canaryConfiguration: configuration,
            canarySelection: selection,
            candidateSafetyReports: safetyReports,
            observationReport: observation
        )
        return CanonicalLibraryMetadataCanaryResult(
            configuration: configuration,
            cutoverResult: cutoverResult,
            selection: selection,
            observationReport: observation
        )
    }

    private nonisolated static func observation(
        syncRunID: String?,
        nodeRole: CanonicalProductionExecutionDomainRole,
        selection: CanonicalLibraryMetadataCanarySelectionResult,
        safetyReports: [CanonicalLibraryMetadataCanaryCandidateSafety],
        cutoverResult: CanonicalLibraryMetadataCutoverResult,
        evidence: CanonicalLibraryMetadataCutoverEvidence
    ) -> CanonicalLibraryMetadataCanaryObservationReport {
        let successful = cutoverResult.commits.filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
        let status: CanonicalLibraryMetadataCanaryObservationStatus
        if cutoverResult.fatalBlocker {
            status = .fatalRollbackFailure
        } else if !successful.isEmpty {
            status = .committed
        } else if !cutoverResult.rollbackResults.isEmpty {
            status = .failedRolledBack
        } else {
            status = .blocked
        }
        return CanonicalLibraryMetadataCanaryObservationReport(
            status: status,
            syncRunID: syncRunID,
            nodeRole: nodeRole,
            selectedCandidateCount: selection.selectedCandidates.count,
            blockedCandidateCount: selection.blockers.count,
            attemptedCommitCount: cutoverResult.commits.count,
            successfulCommitCount: successful.count,
            rollbackCount: cutoverResult.rollbackResults.count,
            duplicateSuppressionApplied: !cutoverResult.duplicateLegacySuppressedActionIDs.isEmpty,
            legacyFallbackPreserved: cutoverResult.legacyFallbackUsed || successful.isEmpty,
            readSideParallelEquivalent: cutoverResult.readSideProjection?.equivalent ?? evidence.readSideParallelEquivalent,
            resourceMoved: safetyReports.contains(where: \.resourceMoveAttempted),
            physicalDeleteAttempted: safetyReports.contains(where: \.physicalDeleteAttempted),
            contentBytesMutated: safetyReports.contains(where: \.contentBytesMutated),
            fatalBlocker: cutoverResult.fatalBlocker,
            reason: status.rawValue
        )
    }

    private nonisolated static func diagnostic(
        _ kind: CanonicalLibraryMetadataCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalLibraryMetadataCutoverDomain? = nil,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        action: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil,
        hashPrefix: String? = nil
    ) -> CanonicalLibraryMetadataCutoverDiagnostic {
        let hash = hash ?? hashPrefix.map { CanonicalHash($0) }
        return CanonicalLibraryMetadataCutoverDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            domain: domain,
            objectID: objectID,
            objectKind: objectKind,
            action: action,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}

nonisolated struct CanonicalLibraryMetadataNoCommitCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { cutoverCandidate.id }
    var cutoverCandidate: CanonicalLibraryMetadataCutoverCandidate
    var expectedRoutePath: String

    nonisolated init(
        cutoverCandidate: CanonicalLibraryMetadataCutoverCandidate,
        expectedRoutePath: String = "/sync/apply-metadata"
    ) {
        self.cutoverCandidate = cutoverCandidate
        self.expectedRoutePath = CanonicalProductionRedaction.safeDiagnosticText(expectedRoutePath) ?? "/sync/apply-metadata"
    }
}

nonisolated struct CanonicalLibraryMetadataNoCommitPayloadSummary: Codable, Equatable, Sendable {
    var schema: String
    var objectKind: CanonicalObjectKind
    var objectID: String
    var actionKind: CanonicalLibraryMetadataCutoverActionKind
    var metadataHashPrefix: String?
    var parentFolderSummary: String
    var tagCount: Int
    var filingSummary: String
    var payloadByteCount: Int
    var wouldUseMetadataManifestBridge: Bool
    var productionCommitSuppressed: Bool
    var legacyDuplicateSuppressed: Bool

    nonisolated init(candidate: CanonicalLibraryMetadataNoCommitCandidate) {
        let cutover = candidate.cutoverCandidate
        self.schema = "canonical-library-metadata-no-commit-v8-10"
        self.objectKind = cutover.objectKind
        self.objectID = CanonicalProductionRedaction.safeIdentifier(cutover.objectID, fallback: "library-object")
        self.actionKind = cutover.cutoverActionKind
        self.metadataHashPrefix = cutover.expectedMetadataHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.parentFolderSummary = cutover.parentSummary
        self.tagCount = cutover.tagCount
        self.filingSummary = cutover.filingSummary
        self.payloadByteCount = 0
        self.wouldUseMetadataManifestBridge = true
        self.productionCommitSuppressed = true
        self.legacyDuplicateSuppressed = false
    }

    nonisolated func encodedBytes() -> Data {
        var copy = self
        let bytes = (try? JSONEncoder().encode(copy)) ?? Data()
        copy.payloadByteCount = bytes.count
        return (try? JSONEncoder().encode(copy)) ?? bytes
    }
}

nonisolated enum CanonicalLibraryMetadataNoCommitFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedAction
    case insufficientEvidence
    case stagingFailed
    case productionCommitSuppressed
}

nonisolated struct CanonicalLibraryMetadataNoCommitStagingResult: Codable, Equatable, Sendable {
    var candidate: CanonicalLibraryMetadataNoCommitCandidate
    var staged: Bool
    var wroteOnlyStagingRoot: Bool
    var stagedLogicalPathToken: String?
    var payloadByteCount: Int
    var payloadHashPrefix: String?
    var objectKind: CanonicalObjectKind
    var objectID: String
    var actionKind: CanonicalLibraryMetadataCutoverActionKind
    var metadataHashPrefix: String?
    var parentFolderSummary: String
    var tagCount: Int
    var filingSummary: String
    var wouldUseMetadataManifestBridge: Bool
    var productionCommitSuppressed: Bool
    var legacyDuplicateSuppressed: Bool
    var stagingEvidence: CanonicalNoCommitStagingEvidence?
    var cleanupEvidence: CanonicalNoCommitCleanupEvidence?
    var failure: CanonicalLibraryMetadataNoCommitFailure?
    var reason: String

    nonisolated init(
        candidate: CanonicalLibraryMetadataNoCommitCandidate,
        staged: Bool,
        wroteOnlyStagingRoot: Bool,
        stagedLogicalPathToken: String? = nil,
        payloadByteCount: Int = 0,
        payloadHashPrefix: String? = nil,
        stagingEvidence: CanonicalNoCommitStagingEvidence? = nil,
        cleanupEvidence: CanonicalNoCommitCleanupEvidence? = nil,
        failure: CanonicalLibraryMetadataNoCommitFailure? = nil,
        reason: String
    ) {
        self.candidate = candidate
        self.staged = staged
        self.wroteOnlyStagingRoot = wroteOnlyStagingRoot
        self.stagedLogicalPathToken = stagedLogicalPathToken.flatMap(CanonicalProjectionContract.safeLogicalPathToken)
        self.payloadByteCount = max(0, payloadByteCount)
        self.payloadHashPrefix = CanonicalProductionRedaction.hashPrefix(payloadHashPrefix)
        self.objectKind = candidate.cutoverCandidate.objectKind
        self.objectID = CanonicalProductionRedaction.safeIdentifier(candidate.cutoverCandidate.objectID, fallback: "library-object")
        self.actionKind = candidate.cutoverCandidate.cutoverActionKind
        self.metadataHashPrefix = candidate.cutoverCandidate.expectedMetadataHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.parentFolderSummary = candidate.cutoverCandidate.parentSummary
        self.tagCount = candidate.cutoverCandidate.tagCount
        self.filingSummary = candidate.cutoverCandidate.filingSummary
        self.wouldUseMetadataManifestBridge = true
        self.productionCommitSuppressed = true
        self.legacyDuplicateSuppressed = false
        self.stagingEvidence = stagingEvidence
        self.cleanupEvidence = cleanupEvidence
        self.failure = failure
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (staged ? "staged" : "blocked")
    }
}

protocol CanonicalLibraryMetadataNoCommitExecutor: Sendable {
    func stageLibraryMetadataNoCommit(
        _ candidate: CanonicalLibraryMetadataNoCommitCandidate
    ) -> CanonicalLibraryMetadataNoCommitStagingResult
}

nonisolated struct CanonicalLibraryMetadataLegacyActionIdentity: Codable, Equatable, Hashable, Sendable {
    var actionID: String?
    var syncRunID: String?
    var objectID: String
    var objectKind: CanonicalObjectKind
    var domain: CanonicalLibraryMetadataCutoverDomain
    var actionKind: CanonicalLibraryMetadataCutoverActionKind

    nonisolated init(
        actionID: String? = nil,
        syncRunID: String? = nil,
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain,
        actionKind: CanonicalLibraryMetadataCutoverActionKind
    ) {
        self.actionID = actionID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "legacy-action") }
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object")
        self.objectKind = objectKind
        self.domain = domain
        self.actionKind = actionKind
    }
}

nonisolated enum CanonicalLibraryMetadataLegacyDuplicateSuppression {
    nonisolated static func suppressedLegacyActionIDs(
        after result: CanonicalLibraryMetadataCutoverResult,
        legacyActions: [CanonicalLibraryMetadataLegacyActionIdentity]
    ) -> [String] {
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
        commit: CanonicalLibraryMetadataProductionCommitResult,
        legacy: CanonicalLibraryMetadataLegacyActionIdentity
    ) -> Bool {
        guard commit.objectID == legacy.objectID,
              commit.objectKind == legacy.objectKind,
              commit.domain == legacy.domain,
              commit.actionKind == legacy.actionKind else {
            return false
        }
        return true
    }
}

nonisolated struct CanonicalLibraryMetadataCutoverAppSeamPolicy: Codable, Equatable, Sendable {
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int
    var canaryPolicy: CanonicalLibraryMetadataCanaryPolicy

    nonisolated init(
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 200,
        canaryPolicy: CanonicalLibraryMetadataCanaryPolicy = .disabled
    ) {
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
        self.canaryPolicy = canaryPolicy
    }
}

nonisolated struct CanonicalLibraryMetadataCutoverAppSeamConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: CanonicalCutoverAppSeamMode
    var policy: CanonicalLibraryMetadataCutoverAppSeamPolicy
    var evidence: CanonicalLibraryMetadataCutoverEvidence
    var cutoverToken: CanonicalCutoverToken?

    nonisolated init(
        isEnabled: Bool = false,
        mode: CanonicalCutoverAppSeamMode = .disabled,
        policy: CanonicalLibraryMetadataCutoverAppSeamPolicy = CanonicalLibraryMetadataCutoverAppSeamPolicy(),
        evidence: CanonicalLibraryMetadataCutoverEvidence = CanonicalLibraryMetadataCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) {
        self.isEnabled = isEnabled
        self.mode = isEnabled ? mode : .disabled
        self.policy = policy
        self.evidence = evidence
        self.cutoverToken = cutoverToken
    }

    nonisolated static let disabled = CanonicalLibraryMetadataCutoverAppSeamConfiguration()

    nonisolated static func enabled(
        mode: CanonicalCutoverAppSeamMode = .guardedExecuteCommit,
        policy: CanonicalLibraryMetadataCutoverAppSeamPolicy = CanonicalLibraryMetadataCutoverAppSeamPolicy(),
        evidence: CanonicalLibraryMetadataCutoverEvidence = CanonicalLibraryMetadataCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) -> CanonicalLibraryMetadataCutoverAppSeamConfiguration {
        CanonicalLibraryMetadataCutoverAppSeamConfiguration(
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

nonisolated enum CanonicalLibraryMetadataGuardedCommitEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case complete
    case incomplete
}

nonisolated enum CanonicalLibraryMetadataGuardedCommitSeamFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedMode
    case productionExecuteDenied
    case viewRefreshTriggerDenied
    case retryDrainerFreshMetadataDenied
    case insufficientLocalSnapshot
    case insufficientPeerSnapshot
    case matrixValidationBlocked
    case activePilotNotLibraryMetadata
    case missingToken
    case missingOwnerApproval
    case missingNoCommitEvidence
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingMetadataManifestRouteEvidence
    case productionPortUnavailable
    case realApplyPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case missingRollback
    case rollbackVerificationMissing
    case rollbackRehearsalMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case legacyFallbackUnavailable
    case commitExecutorUnavailable
    case missingFailureInjectionEvidence
    case missingReadSideParallel
    case noResourceMoveGuardMissing
    case noPhysicalDeleteGuardMissing
    case unsupportedAction
    case conflictDetected
    case tombstoneUnsupportedForThisRound
    case activeVsTombstoneConflict
    case resourceMoveAttempted
    case folderHierarchyMutationUnsupported
    case parentMissing
    case cycleDetected
    case objectIDInstability
    case canaryBudgetNonZeroDenied
    case internalN1ExecutionDenied
    case stagePolicyExecutionDenied
    case runtimeSwitchDenied
}

nonisolated struct CanonicalLibraryMetadataGuardedCommitGate: Codable, Equatable, Sendable {
    var mode: CanonicalCutoverAppSeamMode
    var allowed: Bool
    var failures: [CanonicalLibraryMetadataGuardedCommitSeamFailure]
    var reason: String

    nonisolated init(
        mode: CanonicalCutoverAppSeamMode,
        failures: [CanonicalLibraryMetadataGuardedCommitSeamFailure],
        reason: String
    ) {
        self.mode = mode
        self.failures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = self.failures.isEmpty
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (self.allowed ? "allowed" : "blocked")
    }
}

nonisolated enum CanonicalLibraryMetadataGuardedCommitDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalLibraryMetadataV814SeamStarted
    case canonicalLibraryMetadataV814SeamCompleted
    case canonicalLibraryMetadataV814SeamBlocked
    case canonicalLibraryMetadataV814GateEvaluated
    case canonicalLibraryMetadataV814GateAllowedBudgetZero
    case canonicalLibraryMetadataV814GateBlocked
    case canonicalLibraryMetadataV814CanaryBudgetZero
    case canonicalLibraryMetadataV814CommitNotExecuted
    case canonicalLibraryMetadataV814LegacyFallbackPreserved
    case canonicalLibraryMetadataV814DuplicateSuppressionNotApplied
    case canonicalLibraryMetadataV814EvidenceReportBuilt
    case canonicalLibraryMetadataV814N1ReadinessReportBuilt
    case canonicalLibraryMetadataCanaryBudgetZero
    case canonicalLibraryMetadataGateAllowedButNoExecution
    case canonicalLibraryMetadataCommitSkippedBecauseCanaryBudgetZero
}

nonisolated struct CanonicalLibraryMetadataGuardedCommitDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", result ?? "", reason ?? ""].joined(separator: "|") }

    var kind: CanonicalLibraryMetadataGuardedCommitDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var mode: CanonicalCutoverAppSeamMode
    var objectID: String?
    var objectKind: CanonicalObjectKind?
    var candidateCount: Int
    var gateFailureCount: Int
    var canaryBudget: Int
    var commitAttemptedCount: Int
    var duplicateSuppressionCandidateCount: Int
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalLibraryMetadataGuardedCommitDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        mode: CanonicalCutoverAppSeamMode,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        candidateCount: Int,
        gateFailureCount: Int = 0,
        canaryBudget: Int,
        commitAttemptedCount: Int = 0,
        duplicateSuppressionCandidateCount: Int = 0,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) {
        self.kind = kind
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.mode = mode
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "library-object") }
        self.objectKind = objectKind
        self.candidateCount = max(0, candidateCount)
        self.gateFailureCount = max(0, gateFailureCount)
        self.canaryBudget = max(0, canaryBudget)
        self.commitAttemptedCount = max(0, commitAttemptedCount)
        self.duplicateSuppressionCandidateCount = max(0, duplicateSuppressionCandidateCount)
        self.result = CanonicalProductionRedaction.safeDiagnosticText(result)
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
        self.hashPrefix = hash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            "mode=\(mode.rawValue)",
            objectID.map { "objectID=\($0)" },
            objectKind.map { "objectKind=\($0.rawValue)" },
            "candidateCount=\(candidateCount)",
            "gateFailureCount=\(gateFailureCount)",
            "canaryBudget=\(canaryBudget)",
            "commitAttemptedCount=\(commitAttemptedCount)",
            "duplicateSuppressionCandidateCount=\(duplicateSuppressionCandidateCount)",
            result.map { "result=\($0)" },
            reason.map { "reason=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated struct CanonicalLibraryMetadataCommitEvidenceReport: Codable, Equatable, Sendable {
    var status: CanonicalLibraryMetadataGuardedCommitEvidenceStatus
    var missingReasons: [CanonicalLibraryMetadataGuardedCommitSeamFailure]
    var matrixReport: CanonicalMigrationMatrixReport
    var canaryPolicy: CanonicalLibraryMetadataCanaryPolicy
    var localSnapshotAvailable: Bool
    var peerSnapshotAvailable: Bool
    var candidateCount: Int
    var legacyActionCandidateCount: Int
    var unresolvedConflictCount: Int
    var noCommitEvidenceAvailable: Bool
    var realApplyPortReady: Bool
    var commitExecutorReady: Bool
    var rollbackPlanReady: Bool
    var failureInjectionReady: Bool
    var noResourceMoveGuardReady: Bool
    var noPhysicalDeleteGuardReady: Bool
    var readSideParallelReady: Bool
    var duplicateSuppressionPolicyDisabledBecauseN0: Bool
    var legacyFallbackAvailable: Bool

    nonisolated init(
        missingReasons: [CanonicalLibraryMetadataGuardedCommitSeamFailure],
        matrixReport: CanonicalMigrationMatrixReport,
        canaryPolicy: CanonicalLibraryMetadataCanaryPolicy,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        candidateCount: Int,
        legacyActionCandidateCount: Int,
        unresolvedConflictCount: Int,
        noCommitEvidenceAvailable: Bool,
        realApplyPortReady: Bool,
        commitExecutorReady: Bool,
        rollbackPlanReady: Bool,
        failureInjectionReady: Bool,
        noResourceMoveGuardReady: Bool,
        noPhysicalDeleteGuardReady: Bool,
        readSideParallelReady: Bool,
        duplicateSuppressionPolicyDisabledBecauseN0: Bool,
        legacyFallbackAvailable: Bool
    ) {
        let normalizedReasons = Array(Set(missingReasons)).sorted { $0.rawValue < $1.rawValue }
        self.status = normalizedReasons.isEmpty ? .complete : .incomplete
        self.missingReasons = normalizedReasons
        self.matrixReport = matrixReport
        self.canaryPolicy = canaryPolicy
        self.localSnapshotAvailable = localSnapshotAvailable
        self.peerSnapshotAvailable = peerSnapshotAvailable
        self.candidateCount = max(0, candidateCount)
        self.legacyActionCandidateCount = max(0, legacyActionCandidateCount)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.noCommitEvidenceAvailable = noCommitEvidenceAvailable
        self.realApplyPortReady = realApplyPortReady
        self.commitExecutorReady = commitExecutorReady
        self.rollbackPlanReady = rollbackPlanReady
        self.failureInjectionReady = failureInjectionReady
        self.noResourceMoveGuardReady = noResourceMoveGuardReady
        self.noPhysicalDeleteGuardReady = noPhysicalDeleteGuardReady
        self.readSideParallelReady = readSideParallelReady
        self.duplicateSuppressionPolicyDisabledBecauseN0 = duplicateSuppressionPolicyDisabledBecauseN0
        self.legacyFallbackAvailable = legacyFallbackAvailable
    }

    nonisolated var diagnosticsSummary: String {
        [
            "status=\(status.rawValue)",
            "missingReasons=\(missingReasons.map(\.rawValue).joined(separator: "+"))",
            "activePilot=\(matrixReport.activePilotDomain?.rawValue ?? "none")",
            "matrixAllowed=\(matrixReport.allowed)",
            "candidateCount=\(candidateCount)",
            "legacyActionCandidateCount=\(legacyActionCandidateCount)",
            "unresolvedConflictCount=\(unresolvedConflictCount)",
            "localSnapshotAvailable=\(localSnapshotAvailable)",
            "peerSnapshotAvailable=\(peerSnapshotAvailable)",
            "canaryMaxObjectsPerSyncRun=\(canaryPolicy.canaryMaxObjectsPerSyncRun)",
            "stagePolicy=\(canaryPolicy.stagePolicy.requestedStage.rawValue)",
            "allowsInternalN1Execution=\(canaryPolicy.allowsInternalN1Execution)",
            "noCommitEvidenceAvailable=\(noCommitEvidenceAvailable)",
            "realApplyPortReady=\(realApplyPortReady)",
            "commitExecutorReady=\(commitExecutorReady)",
            "rollbackPlanReady=\(rollbackPlanReady)",
            "failureInjectionReady=\(failureInjectionReady)",
            "noResourceMoveGuardReady=\(noResourceMoveGuardReady)",
            "noPhysicalDeleteGuardReady=\(noPhysicalDeleteGuardReady)",
            "readSideParallelReady=\(readSideParallelReady)",
            "duplicateSuppressionPolicyDisabledBecauseN0=\(duplicateSuppressionPolicyDisabledBecauseN0)",
            "legacyFallbackAvailable=\(legacyFallbackAvailable)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalLibraryMetadataN1ReadinessStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyAfterExplicitN1Enablement
    case noEligibleCandidate
    case insufficientPeerSnapshot
    case insufficientEvidence
    case blocked
}

nonisolated enum CanonicalLibraryMetadataN1Blocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case explicitN1EnablementRequired
    case localSnapshotUnavailable
    case peerSnapshotUnavailable
    case matrixBlocked
    case activePilotNotLibraryMetadata
    case ownerApprovalMissing
    case noEligibleCandidate
    case missingNoCommitEvidence
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingMetadataManifestRouteEvidence
    case missingRealApplyPort
    case missingCommitExecutor
    case missingRollbackPlan
    case missingRollbackVerification
    case missingFailureInjection
    case missingLegacyFallback
    case missingReadSideParallel
    case resourceMoveAttempted
    case physicalDeleteGuardMissing
    case unsupportedCandidate
    case canaryBudgetMustRemainZeroForV814
    case executableStagePolicyDeniedForV814
    case duplicateSuppressionMustRemainDisabled
}

nonisolated struct CanonicalLibraryMetadataN1ReadinessReport: Codable, Equatable, Sendable {
    var status: CanonicalLibraryMetadataN1ReadinessStatus
    var blockers: [CanonicalLibraryMetadataN1Blocker]
    var candidateCount: Int
    var eligibleCandidateCount: Int
    var canaryBudget: Int
    var canExecuteNow: Bool
    var willExecuteNow: Bool
    var noExecutionAssertionPassed: Bool
    var diagnosticsSummary: String

    nonisolated init(
        blockers: [CanonicalLibraryMetadataN1Blocker],
        candidateCount: Int,
        eligibleCandidateCount: Int,
        canaryBudget: Int,
        canExecuteNow: Bool,
        willExecuteNow: Bool,
        noExecutionAssertionPassed: Bool
    ) {
        let normalizedBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.blockers = normalizedBlockers
        self.candidateCount = max(0, candidateCount)
        self.eligibleCandidateCount = max(0, eligibleCandidateCount)
        self.canaryBudget = max(0, canaryBudget)
        self.canExecuteNow = canExecuteNow
        self.willExecuteNow = willExecuteNow
        self.noExecutionAssertionPassed = noExecutionAssertionPassed
        if normalizedBlockers.contains(.peerSnapshotUnavailable) {
            self.status = .insufficientPeerSnapshot
        } else if normalizedBlockers.contains(.noEligibleCandidate) {
            self.status = .noEligibleCandidate
        } else if normalizedBlockers.contains(where: { $0 != .explicitN1EnablementRequired && $0 != .duplicateSuppressionMustRemainDisabled && $0 != .canaryBudgetMustRemainZeroForV814 }) {
            self.status = .insufficientEvidence
        } else if self.eligibleCandidateCount > 0 {
            self.status = .readyAfterExplicitN1Enablement
        } else {
            self.status = .blocked
        }
        self.diagnosticsSummary = [
            "status=\(status.rawValue)",
            "blockers=\(normalizedBlockers.map(\.rawValue).joined(separator: "+"))",
            "candidateCount=\(self.candidateCount)",
            "eligibleCandidateCount=\(self.eligibleCandidateCount)",
            "canaryBudget=\(self.canaryBudget)",
            "canExecuteNow=\(canExecuteNow)",
            "willExecuteNow=\(willExecuteNow)",
            "noExecutionAssertionPassed=\(noExecutionAssertionPassed)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalLibraryMetadataNoExecutionViolation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case willExecuteNow
    case commitAttempted
    case committedObject
    case productionCommitCalled
    case realApplyPortCommitCalled
    case networkSendCalled
    case applySyncManifestCalled
    case metadataJSONWritten
    case duplicateLegacySuppressed
    case legacyFallbackNotPreserved
    case runtimeSwitchEnabled
    case legacyPlanChanged
    case productionPlanChanged
}

nonisolated struct CanonicalLibraryMetadataNoExecutionAssertion: Codable, Equatable, Sendable {
    var passed: Bool
    var violations: [CanonicalLibraryMetadataNoExecutionViolation]

    nonisolated static func evaluate(
        _ result: CanonicalLibraryMetadataGuardedCommitSeamResult
    ) -> CanonicalLibraryMetadataNoExecutionAssertion {
        var violations: [CanonicalLibraryMetadataNoExecutionViolation] = []
        if result.willExecuteNow { violations.append(.willExecuteNow) }
        if result.commitAttemptedCount != 0 { violations.append(.commitAttempted) }
        if result.committedObjectCount != 0 { violations.append(.committedObject) }
        if result.productionCommitCalled { violations.append(.productionCommitCalled) }
        if result.realApplyPortCommitCalled { violations.append(.realApplyPortCommitCalled) }
        if result.networkSendCalled { violations.append(.networkSendCalled) }
        if result.applySyncManifestCalled { violations.append(.applySyncManifestCalled) }
        if result.metadataJSONWritten { violations.append(.metadataJSONWritten) }
        if !result.duplicateLegacySuppressedActionIDs.isEmpty { violations.append(.duplicateLegacySuppressed) }
        if !result.legacyFallbackPreserved { violations.append(.legacyFallbackNotPreserved) }
        if result.runtimeSwitchEnabled { violations.append(.runtimeSwitchEnabled) }
        if !result.legacyPlanUnchanged { violations.append(.legacyPlanChanged) }
        if !result.productionPlanUnchanged { violations.append(.productionPlanChanged) }
        let uniqueViolations = Array(Set(violations)).sorted { $0.rawValue < $1.rawValue }
        return CanonicalLibraryMetadataNoExecutionAssertion(
            passed: uniqueViolations.isEmpty,
            violations: uniqueViolations
        )
    }
}

nonisolated struct CanonicalLibraryMetadataGuardedCommitContext: Codable, Equatable, Sendable {
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var localManifest: CanonicalManifest?
    var peerManifest: CanonicalManifest?
    var libraryPlan: CanonicalLibrarySyncPlan?
    var legacyActionSnapshot: CanonicalLegacyActionSnapshot
    var matrix: CanonicalMigrationDomainMatrix
    var evidence: CanonicalLibraryMetadataCutoverEvidence
    var canaryPolicy: CanonicalLibraryMetadataCanaryPolicy
    var cutoverToken: CanonicalCutoverToken?
    var candidates: [CanonicalLibraryMetadataCutoverCandidate]
    var localSnapshotAvailable: Bool
    var peerSnapshotAvailable: Bool
    var unresolvedConflictCount: Int
    var commitExecutorReady: Bool
    var failureInjectionReady: Bool
    var noResourceMoveGuardReady: Bool
    var noPhysicalDeleteGuardReady: Bool
    var readSideParallelReady: Bool
    var duplicateSuppressionPolicyAvailable: Bool
    var legacyFallbackAvailable: Bool

    nonisolated init(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        legacyActionSnapshot: CanonicalLegacyActionSnapshot = .empty,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        evidence: CanonicalLibraryMetadataCutoverEvidence,
        canaryPolicy: CanonicalLibraryMetadataCanaryPolicy = .disabled,
        cutoverToken: CanonicalCutoverToken? = nil,
        candidates: [CanonicalLibraryMetadataCutoverCandidate] = [],
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        unresolvedConflictCount: Int = 0,
        commitExecutorReady: Bool = true,
        failureInjectionReady: Bool = true,
        noResourceMoveGuardReady: Bool = true,
        noPhysicalDeleteGuardReady: Bool = true,
        readSideParallelReady: Bool? = nil,
        duplicateSuppressionPolicyAvailable: Bool = true,
        legacyFallbackAvailable: Bool? = nil
    ) {
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.localManifest = localManifest
        self.peerManifest = peerManifest
        self.libraryPlan = libraryPlan
        self.legacyActionSnapshot = legacyActionSnapshot
        self.matrix = matrix
        self.evidence = evidence
        self.canaryPolicy = canaryPolicy
        self.cutoverToken = cutoverToken
        self.candidates = candidates
        self.localSnapshotAvailable = localSnapshotAvailable
        self.peerSnapshotAvailable = peerSnapshotAvailable
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.commitExecutorReady = commitExecutorReady
        self.failureInjectionReady = failureInjectionReady
        self.noResourceMoveGuardReady = noResourceMoveGuardReady
        self.noPhysicalDeleteGuardReady = noPhysicalDeleteGuardReady
        self.readSideParallelReady = readSideParallelReady ?? evidence.readSideParallelEquivalent
        self.duplicateSuppressionPolicyAvailable = duplicateSuppressionPolicyAvailable
        self.legacyFallbackAvailable = legacyFallbackAvailable ?? evidence.legacyFallbackAvailable
    }
}

nonisolated struct CanonicalLibraryMetadataGuardedCommitSeamResult: Codable, Equatable, Sendable {
    var gate: CanonicalLibraryMetadataGuardedCommitGate
    var evidenceReport: CanonicalLibraryMetadataCommitEvidenceReport
    var n1ReadinessReport: CanonicalLibraryMetadataN1ReadinessReport
    var diagnostics: [CanonicalLibraryMetadataGuardedCommitDiagnostic]
    var noExecutionAssertion: CanonicalLibraryMetadataNoExecutionAssertion
    var canaryBudgetZero: Bool
    var canExecuteNow: Bool
    var willExecuteNow: Bool
    var commitAttemptedCount: Int
    var committedObjectCount: Int
    var productionCommitCalled: Bool
    var realApplyPortCommitCalled: Bool
    var networkSendCalled: Bool
    var applySyncManifestCalled: Bool
    var metadataJSONWritten: Bool
    var duplicateLegacySuppressedActionIDs: [String]
    var duplicateLegacySuppressionCandidates: [String]
    var legacyFallbackPreserved: Bool
    var runtimeSwitchEnabled: Bool
    var legacyPlanUnchanged: Bool
    var productionPlanUnchanged: Bool
    var nonfatalFailureCount: Int

    nonisolated var succeeded: Bool {
        gate.allowed && canaryBudgetZero && !willExecuteNow && noExecutionAssertion.passed
    }
}

nonisolated struct CanonicalLibraryMetadataGuardedCommitSeam: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        configuration: CanonicalLibraryMetadataCutoverAppSeamConfiguration,
        context: CanonicalLibraryMetadataGuardedCommitContext
    ) -> CanonicalLibraryMetadataGuardedCommitSeamResult {
        let canaryPolicy = configuration.policy.canaryPolicy
        let duplicateCandidates = duplicateSuppressionCandidates(context)
        let evidenceReport = makeEvidenceReport(
            configuration: configuration,
            context: context,
            canaryPolicy: canaryPolicy,
            duplicateCandidates: duplicateCandidates
        )
        let gate = evaluateGate(
            configuration: configuration,
            context: context,
            evidenceReport: evidenceReport,
            canaryPolicy: canaryPolicy
        )
        let canaryBudgetZero = Self.isCanaryBudgetZero(canaryPolicy)
        let canExecuteNow = gate.allowed
        let willExecuteNow = false
        let nonfatalFailureCount = gate.failures.count
        let emptyAssertion = CanonicalLibraryMetadataNoExecutionAssertion(passed: true, violations: [])
        let preliminaryReadiness = makeN1ReadinessReport(
            context: context,
            evidenceReport: evidenceReport,
            gate: gate,
            canaryPolicy: canaryPolicy,
            canExecuteNow: canExecuteNow,
            willExecuteNow: willExecuteNow,
            noExecutionAssertionPassed: emptyAssertion.passed
        )
        var diagnostics: [CanonicalLibraryMetadataGuardedCommitDiagnostic] = [
            diagnostic(
                .canonicalLibraryMetadataV814SeamStarted,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.reason
            ),
            diagnostic(
                .canonicalLibraryMetadataV814EvidenceReportBuilt,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: evidenceReport.status.rawValue,
                reason: evidenceReport.diagnosticsSummary
            ),
            diagnostic(
                .canonicalLibraryMetadataV814N1ReadinessReportBuilt,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: preliminaryReadiness.status.rawValue,
                reason: preliminaryReadiness.diagnosticsSummary
            ),
            diagnostic(
                .canonicalLibraryMetadataV814GateEvaluated,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.allowed ? "canonicalLibraryMetadataV814GateAllowedBudgetZero" : gate.failures.map(\.rawValue).joined(separator: ",")
            )
        ]
        diagnostics.append(
            diagnostic(
                gate.allowed && canaryBudgetZero ? .canonicalLibraryMetadataV814GateAllowedBudgetZero : .canonicalLibraryMetadataV814GateBlocked,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: gate.allowed && canaryBudgetZero ? "allowedBudgetZero" : "blocked",
                reason: gate.reason
            )
        )
        if !gate.allowed {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataV814SeamBlocked,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "blocked",
                    reason: gate.failures.map(\.rawValue).joined(separator: ",")
                )
            )
        }
        if canaryBudgetZero {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataV814CanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "canaryBudgetZero",
                    reason: "canonicalLibraryMetadataV814CanaryBudgetZero"
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataCanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "canaryBudgetZero",
                    reason: "canonicalLibraryMetadataCanaryBudgetZero"
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataCommitSkippedBecauseCanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "commitSkipped",
                    reason: "canaryBudgetZero"
                )
            )
        }
        if gate.allowed && !willExecuteNow {
            diagnostics.append(
                diagnostic(
                    .canonicalLibraryMetadataGateAllowedButNoExecution,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "gateAllowedButNoExecution",
                    reason: canaryBudgetZero ? "canaryBudgetZero" : "executionDeniedForV814"
                )
            )
        }
        diagnostics.append(
            diagnostic(
                .canonicalLibraryMetadataV814CommitNotExecuted,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: "commitNotExecuted",
                reason: "v814GuardedCommitSeamNZero"
            )
        )
        diagnostics.append(
            diagnostic(
                .canonicalLibraryMetadataV814LegacyFallbackPreserved,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: "legacyFallbackPreserved",
                reason: "v814DoesNotReplaceLegacyPlan"
            )
        )
        diagnostics.append(
            diagnostic(
                .canonicalLibraryMetadataV814DuplicateSuppressionNotApplied,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: "duplicateSuppressionNotApplied",
                reason: "v814NZeroDoesNotSuppressLegacyDuplicates"
            )
        )
        diagnostics.append(
            diagnostic(
                .canonicalLibraryMetadataV814SeamCompleted,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: "completed",
                reason: gate.allowed ? "nonfatalNoExecution" : "nonfatalBlocked"
            )
        )

        var result = CanonicalLibraryMetadataGuardedCommitSeamResult(
            gate: gate,
            evidenceReport: evidenceReport,
            n1ReadinessReport: preliminaryReadiness,
            diagnostics: Array(diagnostics.prefix(configuration.policy.maxDiagnosticsEvents)),
            noExecutionAssertion: emptyAssertion,
            canaryBudgetZero: canaryBudgetZero,
            canExecuteNow: canExecuteNow,
            willExecuteNow: willExecuteNow,
            commitAttemptedCount: 0,
            committedObjectCount: 0,
            productionCommitCalled: false,
            realApplyPortCommitCalled: false,
            networkSendCalled: false,
            applySyncManifestCalled: false,
            metadataJSONWritten: false,
            duplicateLegacySuppressedActionIDs: [],
            duplicateLegacySuppressionCandidates: duplicateCandidates,
            legacyFallbackPreserved: true,
            runtimeSwitchEnabled: false,
            legacyPlanUnchanged: true,
            productionPlanUnchanged: true,
            nonfatalFailureCount: nonfatalFailureCount
        )
        let assertion = CanonicalLibraryMetadataNoExecutionAssertion.evaluate(result)
        result.noExecutionAssertion = assertion
        result.n1ReadinessReport = makeN1ReadinessReport(
            context: context,
            evidenceReport: evidenceReport,
            gate: gate,
            canaryPolicy: canaryPolicy,
            canExecuteNow: canExecuteNow,
            willExecuteNow: willExecuteNow,
            noExecutionAssertionPassed: assertion.passed
        )
        return result
    }

    private nonisolated func evaluateGate(
        configuration: CanonicalLibraryMetadataCutoverAppSeamConfiguration,
        context: CanonicalLibraryMetadataGuardedCommitContext,
        evidenceReport: CanonicalLibraryMetadataCommitEvidenceReport,
        canaryPolicy: CanonicalLibraryMetadataCanaryPolicy
    ) -> CanonicalLibraryMetadataGuardedCommitGate {
        var failures: [CanonicalLibraryMetadataGuardedCommitSeamFailure] = []
        let mode = configuration.effectiveMode
        if mode == .disabled {
            failures.append(.disabled)
        }
        switch mode {
        case .disabled:
            break
        case .guardedExecuteCommit, .canaryCommit:
            break
        case .guardedExecuteNoCommit:
            failures.append(.unsupportedMode)
        case .productionExecute:
            failures.append(.productionExecuteDenied)
            failures.append(.unsupportedMode)
        }
        if context.trigger == .viewRefresh {
            failures.append(.viewRefreshTriggerDenied)
        }
        if context.trigger == .retryDrainer {
            failures.append(.retryDrainerFreshMetadataDenied)
        }
        if !context.localSnapshotAvailable || context.localManifest == nil {
            failures.append(.insufficientLocalSnapshot)
        }
        if !context.peerSnapshotAvailable || context.peerManifest == nil {
            failures.append(.insufficientPeerSnapshot)
        }
        if !evidenceReport.matrixReport.allowed {
            failures.append(.matrixValidationBlocked)
        }
        if evidenceReport.matrixReport.activePilotDomain != .libraryMetadata {
            failures.append(.activePilotNotLibraryMetadata)
        }
        if context.cutoverToken == nil {
            failures.append(.missingToken)
        }
        if context.cutoverToken?.ownerApproved != true {
            failures.append(.missingOwnerApproval)
        }
        if canaryPolicy.canaryMaxObjectsPerSyncRun > 0 {
            failures.append(.canaryBudgetNonZeroDenied)
        }
        if canaryPolicy.allowsInternalN1Execution {
            failures.append(.internalN1ExecutionDenied)
        }
        if canaryPolicy.stagePolicy.requestedStage.isExecutable || canaryPolicy.stagePolicy.allowCandidateExecution {
            failures.append(.stagePolicyExecutionDenied)
        }
        if canaryPolicy.stagePolicy.runtimeSwitchEnabled {
            failures.append(.runtimeSwitchDenied)
        }
        failures.append(contentsOf: evidenceReport.missingReasons)
        return CanonicalLibraryMetadataGuardedCommitGate(
            mode: mode,
            failures: failures,
            reason: failures.isEmpty ? "canonicalLibraryMetadataV814GateAllowedBudgetZero" : failures.map(\.rawValue).joined(separator: ",")
        )
    }

    private nonisolated func makeEvidenceReport(
        configuration: CanonicalLibraryMetadataCutoverAppSeamConfiguration,
        context: CanonicalLibraryMetadataGuardedCommitContext,
        canaryPolicy: CanonicalLibraryMetadataCanaryPolicy,
        duplicateCandidates: [String]
    ) -> CanonicalLibraryMetadataCommitEvidenceReport {
        let evidence = context.evidence
        let matrixReport = context.matrix.validate()
        let requiredDomains = Set(context.candidates.filter { $0.cutoverActionKind.isExecutableMetadata }.map { $0.domain.productionDomain })
        var missing: [CanonicalLibraryMetadataGuardedCommitSeamFailure] = []
        if !evidence.noCommitEvidenceAvailable { missing.append(.missingNoCommitEvidence) }
        if !evidence.realDataShadowCopyVerified { missing.append(.missingRealDataShadowCopyEvidence) }
        if !evidence.executionShadowVerified { missing.append(.missingExecutionShadowEvidence) }
        if !evidence.dryRunEquivalenceVerified { missing.append(.missingDryRunEquivalence) }
        if !evidence.noBlockingDivergence { missing.append(.blockingDivergence) }
        if !evidence.noUnresolvedConflict || context.unresolvedConflictCount > 0 || context.candidates.contains(where: \.unresolvedConflict) {
            missing.append(.unresolvedConflict)
        }
        if !evidence.metadataManifestRouteEvidenceAvailable { missing.append(.missingMetadataManifestRouteEvidence) }
        if !evidence.productionPortAvailable { missing.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { missing.append(.realApplyPortUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { missing.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { missing.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { missing.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { missing.append(.rollbackCheckpointUnavailable) }
        if evidence.rollbackPlan == nil || !requiredDomains.allSatisfy({ evidence.rollbackPlan?.covers(domain: $0) == true }) {
            missing.append(.missingRollback)
        }
        if !evidence.rollbackVerified { missing.append(.rollbackVerificationMissing) }
        if !evidence.rollbackRehearsalPassed { missing.append(.rollbackRehearsalMissing) }
        if !evidence.productionRootDisabledByDefault { missing.append(.productionRootEnabledByDefault) }
        if evidence.applyPortMode == .testRootBound && !evidence.testRootUsed { missing.append(.testRootMissing) }
        if !context.legacyFallbackAvailable { missing.append(.legacyFallbackUnavailable) }
        if !context.commitExecutorReady { missing.append(.commitExecutorUnavailable) }
        if !context.failureInjectionReady { missing.append(.missingFailureInjectionEvidence) }
        if !context.noResourceMoveGuardReady { missing.append(.noResourceMoveGuardMissing) }
        if !context.noPhysicalDeleteGuardReady { missing.append(.noPhysicalDeleteGuardMissing) }
        if !context.readSideParallelReady { missing.append(.missingReadSideParallel) }
        missing.append(contentsOf: candidateFailures(context.candidates))
        let duplicateSuppressionDisabled = Self.isCanaryBudgetZero(canaryPolicy)
        return CanonicalLibraryMetadataCommitEvidenceReport(
            missingReasons: missing,
            matrixReport: matrixReport,
            canaryPolicy: canaryPolicy,
            localSnapshotAvailable: context.localSnapshotAvailable,
            peerSnapshotAvailable: context.peerSnapshotAvailable,
            candidateCount: context.candidates.count,
            legacyActionCandidateCount: duplicateCandidates.count,
            unresolvedConflictCount: context.unresolvedConflictCount,
            noCommitEvidenceAvailable: evidence.noCommitEvidenceAvailable,
            realApplyPortReady: evidence.realRootBoundApplyPortAvailable && evidence.applyPortMode.isNonDryRunRootBound && evidence.rootBoundWriteAvailable,
            commitExecutorReady: context.commitExecutorReady,
            rollbackPlanReady: evidence.rollbackPlan != nil && requiredDomains.allSatisfy { evidence.rollbackPlan?.covers(domain: $0) == true },
            failureInjectionReady: context.failureInjectionReady,
            noResourceMoveGuardReady: context.noResourceMoveGuardReady,
            noPhysicalDeleteGuardReady: context.noPhysicalDeleteGuardReady,
            readSideParallelReady: context.readSideParallelReady,
            duplicateSuppressionPolicyDisabledBecauseN0: duplicateSuppressionDisabled,
            legacyFallbackAvailable: context.legacyFallbackAvailable
        )
    }

    private nonisolated func makeN1ReadinessReport(
        context: CanonicalLibraryMetadataGuardedCommitContext,
        evidenceReport: CanonicalLibraryMetadataCommitEvidenceReport,
        gate: CanonicalLibraryMetadataGuardedCommitGate,
        canaryPolicy: CanonicalLibraryMetadataCanaryPolicy,
        canExecuteNow: Bool,
        willExecuteNow: Bool,
        noExecutionAssertionPassed: Bool
    ) -> CanonicalLibraryMetadataN1ReadinessReport {
        var blockers: [CanonicalLibraryMetadataN1Blocker] = [
            .explicitN1EnablementRequired,
            .canaryBudgetMustRemainZeroForV814,
            .duplicateSuppressionMustRemainDisabled
        ]
        if !context.localSnapshotAvailable || context.localManifest == nil { blockers.append(.localSnapshotUnavailable) }
        if !context.peerSnapshotAvailable || context.peerManifest == nil { blockers.append(.peerSnapshotUnavailable) }
        if !evidenceReport.matrixReport.allowed { blockers.append(.matrixBlocked) }
        if evidenceReport.matrixReport.activePilotDomain != .libraryMetadata { blockers.append(.activePilotNotLibraryMetadata) }
        if context.cutoverToken?.ownerApproved != true { blockers.append(.ownerApprovalMissing) }
        if !context.evidence.noCommitEvidenceAvailable { blockers.append(.missingNoCommitEvidence) }
        if !context.evidence.realDataShadowCopyVerified { blockers.append(.missingRealDataShadowCopyEvidence) }
        if !context.evidence.executionShadowVerified { blockers.append(.missingExecutionShadowEvidence) }
        if !context.evidence.dryRunEquivalenceVerified { blockers.append(.missingDryRunEquivalence) }
        if !context.evidence.noBlockingDivergence { blockers.append(.blockingDivergence) }
        if !context.evidence.noUnresolvedConflict || context.unresolvedConflictCount > 0 { blockers.append(.unresolvedConflict) }
        if !context.evidence.metadataManifestRouteEvidenceAvailable { blockers.append(.missingMetadataManifestRouteEvidence) }
        if !evidenceReport.realApplyPortReady { blockers.append(.missingRealApplyPort) }
        if !context.commitExecutorReady { blockers.append(.missingCommitExecutor) }
        if !evidenceReport.rollbackPlanReady { blockers.append(.missingRollbackPlan) }
        if !context.evidence.rollbackVerified || !context.evidence.rollbackRehearsalPassed { blockers.append(.missingRollbackVerification) }
        if !context.failureInjectionReady { blockers.append(.missingFailureInjection) }
        if !context.legacyFallbackAvailable { blockers.append(.missingLegacyFallback) }
        if !context.readSideParallelReady { blockers.append(.missingReadSideParallel) }
        if !context.noPhysicalDeleteGuardReady { blockers.append(.physicalDeleteGuardMissing) }
        if canaryPolicy.stagePolicy.requestedStage.isExecutable || canaryPolicy.stagePolicy.allowCandidateExecution {
            blockers.append(.executableStagePolicyDeniedForV814)
        }
        let candidateBlockers = candidateFailures(context.candidates)
        if candidateBlockers.contains(.resourceMoveAttempted) { blockers.append(.resourceMoveAttempted) }
        if candidateBlockers.contains(where: { $0 == .unsupportedAction || $0 == .conflictDetected || $0 == .tombstoneUnsupportedForThisRound || $0 == .activeVsTombstoneConflict || $0 == .parentMissing || $0 == .cycleDetected || $0 == .objectIDInstability }) {
            blockers.append(.unsupportedCandidate)
        }
        let eligibleCandidateCount = context.candidates.filter { candidateFailures([$0]).isEmpty }.count
        if eligibleCandidateCount == 0 {
            blockers.append(.noEligibleCandidate)
        }
        return CanonicalLibraryMetadataN1ReadinessReport(
            blockers: blockers,
            candidateCount: context.candidates.count,
            eligibleCandidateCount: eligibleCandidateCount,
            canaryBudget: canaryPolicy.canaryMaxObjectsPerSyncRun,
            canExecuteNow: canExecuteNow && gate.allowed,
            willExecuteNow: willExecuteNow,
            noExecutionAssertionPassed: noExecutionAssertionPassed
        )
    }

    private nonisolated func candidateFailures(
        _ candidates: [CanonicalLibraryMetadataCutoverCandidate]
    ) -> [CanonicalLibraryMetadataGuardedCommitSeamFailure] {
        var failures: [CanonicalLibraryMetadataGuardedCommitSeamFailure] = []
        for candidate in candidates {
            switch candidate.cutoverActionKind {
            case .folderApply, .folderSend, .studyItemApply, .studyItemSend, .standaloneNoteApply, .standaloneNoteSend:
                break
            case .conflictRecord:
                failures.append(.conflictDetected)
            case .tombstoneMarkerUnsupportedForThisRound:
                failures.append(.tombstoneUnsupportedForThisRound)
            case .unsupported:
                failures.append(.unsupportedAction)
            }
            if candidate.unresolvedConflict { failures.append(.unresolvedConflict) }
            if candidate.hasActiveVsTombstoneConflict { failures.append(.activeVsTombstoneConflict) }
            if candidate.hasResourceMoveAttempt { failures.append(.resourceMoveAttempted) }
            if candidate.folderHierarchyMutationAttempted { failures.append(.folderHierarchyMutationUnsupported) }
            if candidate.parentMissingKnown { failures.append(.parentMissing) }
            if candidate.hasObjectIDInstability { failures.append(.objectIDInstability) }
        }
        if CanonicalLibraryMetadataCutoverCandidate.folderHierarchyCycleDetected(in: candidates) {
            failures.append(.cycleDetected)
        }
        return Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated func duplicateSuppressionCandidates(
        _ context: CanonicalLibraryMetadataGuardedCommitContext
    ) -> [String] {
        let domains: [CanonicalProductionDomain] = [.folders, .studyItems, .standaloneNotes]
        let legacyIDs = Set(domains.flatMap { context.legacyActionSnapshot.actionIDs(for: $0) })
        return context.candidates
            .map(\.action.actionID)
            .filter { legacyIDs.contains($0) }
            .compactMap { CanonicalProductionRedaction.safeDiagnosticText($0) }
            .sorted()
    }

    private nonisolated static func isCanaryBudgetZero(
        _ policy: CanonicalLibraryMetadataCanaryPolicy
    ) -> Bool {
        policy.canaryMaxObjectsPerSyncRun == 0
            && !policy.stagePolicy.requestedStage.isExecutable
            && !policy.stagePolicy.allowCandidateExecution
            && !policy.stagePolicy.runtimeSwitchEnabled
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalLibraryMetadataGuardedCommitDiagnosticKind,
        configuration: CanonicalLibraryMetadataCutoverAppSeamConfiguration,
        context: CanonicalLibraryMetadataGuardedCommitContext,
        objectID: String? = nil,
        objectKind: CanonicalObjectKind? = nil,
        candidateCount: Int,
        gateFailureCount: Int = 0,
        canaryBudget: Int,
        commitAttemptedCount: Int = 0,
        duplicateSuppressionCandidateCount: Int = 0,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalLibraryMetadataGuardedCommitDiagnostic {
        CanonicalLibraryMetadataGuardedCommitDiagnostic(
            kind: kind,
            syncRunID: context.syncRunID,
            trigger: context.trigger,
            nodeRole: context.nodeRole,
            mode: configuration.effectiveMode,
            objectID: objectID,
            objectKind: objectKind,
            candidateCount: candidateCount,
            gateFailureCount: gateFailureCount,
            canaryBudget: canaryBudget,
            commitAttemptedCount: commitAttemptedCount,
            duplicateSuppressionCandidateCount: duplicateSuppressionCandidateCount,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}

nonisolated struct CanonicalRootBoundLibraryMetadataTarget: Codable, Equatable, Hashable, Sendable {
    var rootToken: CanonicalRootToken
    var objectID: String
    var objectKind: CanonicalObjectKind
    var domain: CanonicalLibraryMetadataCutoverDomain
    var logicalPathToken: String

    nonisolated init(
        rootToken: CanonicalRootToken,
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain,
        logicalPathToken: String
    ) throws {
        guard let safePath = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken) else {
            throw CanonicalLibraryMetadataCutoverFailure.resourceMoveAttempted
        }
        self.rootToken = rootToken
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object")
        self.objectKind = objectKind
        self.domain = domain
        self.logicalPathToken = safePath
    }

    nonisolated static func defaultLogicalPathToken(objectID: String, objectKind: CanonicalObjectKind, domain: CanonicalLibraryMetadataCutoverDomain) -> String {
        let component = safePathComponent(objectID)
        switch domain {
        case .folderMetadata:
            return "library-metadata/folders/\(component).metadata.json"
        case .studyItemMetadata:
            return "library-metadata/study-items/\(component).metadata.json"
        case .standaloneNoteMetadata:
            return "library-metadata/standalone-notes/\(component).metadata.json"
        }
    }

    private nonisolated static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.:"))
        let result = String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_.:"))
        return result.isEmpty ? "library-\(CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(value).value) ?? "unknown")" : String(result.prefix(96))
    }
}

nonisolated struct CanonicalRootBoundLibraryMetadataWriteResult: Codable, Equatable, Sendable {
    var objectID: String
    var objectKind: CanonicalObjectKind
    var domain: CanonicalLibraryMetadataCutoverDomain
    var hashPrefixBefore: String?
    var hashPrefixAfter: String?
    var byteCount: Int
    var checkpointID: String
    var atomicWriteUsed: Bool
    var rollbackAvailable: Bool
    var failure: CanonicalLibraryMetadataCutoverFailure?

    nonisolated init(
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain,
        hashBefore: CanonicalHash? = nil,
        hashAfter: CanonicalHash? = nil,
        byteCount: Int,
        checkpointID: String,
        atomicWriteUsed: Bool,
        rollbackAvailable: Bool,
        failure: CanonicalLibraryMetadataCutoverFailure? = nil
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object")
        self.objectKind = objectKind
        self.domain = domain
        self.hashPrefixBefore = hashBefore.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.hashPrefixAfter = hashAfter.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteCount = max(0, byteCount)
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "library-metadata-checkpoint")
        self.atomicWriteUsed = atomicWriteUsed
        self.rollbackAvailable = rollbackAvailable
        self.failure = failure
    }
}

nonisolated struct CanonicalRootBoundLibraryMetadataRollbackResult: Codable, Equatable, Sendable {
    var objectID: String
    var objectKind: CanonicalObjectKind
    var domain: CanonicalLibraryMetadataCutoverDomain
    var checkpointID: String
    var succeeded: Bool
    var rollbackVerified: Bool
    var hashPrefixAfterRollback: String?
    var byteCount: Int?
    var failure: CanonicalLibraryMetadataCutoverFailure?

    nonisolated init(
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain,
        checkpointID: String,
        succeeded: Bool,
        rollbackVerified: Bool,
        hashAfterRollback: CanonicalHash? = nil,
        byteCount: Int? = nil,
        failure: CanonicalLibraryMetadataCutoverFailure? = nil
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object")
        self.objectKind = objectKind
        self.domain = domain
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "library-metadata-checkpoint")
        self.succeeded = succeeded
        self.rollbackVerified = rollbackVerified
        self.hashPrefixAfterRollback = hashAfterRollback.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteCount = byteCount
        self.failure = failure
    }
}

nonisolated struct CanonicalRootBoundLibraryMetadataWrite: Codable, Equatable, Sendable {
    var target: CanonicalRootBoundLibraryMetadataTarget
    var metadataBytes: Data
    var metadataHash: CanonicalHash
    var businessModifiedAt: CanonicalTimestamp?

    nonisolated init(
        target: CanonicalRootBoundLibraryMetadataTarget,
        metadataBytes: Data,
        metadataHash: CanonicalHash,
        businessModifiedAt: CanonicalTimestamp? = nil
    ) {
        self.target = target
        self.metadataBytes = metadataBytes
        self.metadataHash = metadataHash
        self.businessModifiedAt = businessModifiedAt
    }
}

nonisolated struct CanonicalRootBoundLibraryMetadataCheckpoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { checkpointID }
    var checkpointID: String
    var objectID: String
    var objectKind: CanonicalObjectKind
    var domain: CanonicalLibraryMetadataCutoverDomain
    var hashPrefixBefore: String?
    var byteCountBefore: Int?
    var existedBeforeWrite: Bool
    var rollbackAvailable: Bool

    nonisolated init(
        checkpointID: String,
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain,
        hashBefore: CanonicalHash? = nil,
        byteCountBefore: Int? = nil,
        existedBeforeWrite: Bool,
        rollbackAvailable: Bool
    ) {
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "library-metadata-checkpoint")
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object")
        self.objectKind = objectKind
        self.domain = domain
        self.hashPrefixBefore = hashBefore.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteCountBefore = byteCountBefore
        self.existedBeforeWrite = existedBeforeWrite
        self.rollbackAvailable = rollbackAvailable
    }
}

actor CanonicalRootBoundLibraryMetadataWriteCore {
    private struct StoredCheckpoint: Sendable {
        var publicCheckpoint: CanonicalRootBoundLibraryMetadataCheckpoint
        var target: CanonicalRootBoundLibraryMetadataTarget
        var previousBytes: Data?
        var previousHash: CanonicalHash?
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let rootToken: CanonicalRootToken
    private let mode: CanonicalLibraryMetadataApplyPortMode
    private var payloadsByActionID: [String: CanonicalRootBoundLibraryMetadataWrite] = [:]
    private var payloadsByObject: [String: CanonicalRootBoundLibraryMetadataWrite] = [:]
    private var checkpoints: [String: StoredCheckpoint] = [:]
    private var lastWriteByActionID: [String: CanonicalRootBoundLibraryMetadataWriteResult] = [:]
    private var lastRollbackByCheckpointID: [String: CanonicalRootBoundLibraryMetadataRollbackResult] = [:]
    private var checkpointFailureObjectIDs: Set<String> = []
    private var postconditionFailureObjectIDs: Set<String> = []
    private var rollbackFailureCheckpointIDs: Set<String> = []

    init(
        rootURL: URL,
        rootToken: CanonicalRootToken,
        mode: CanonicalLibraryMetadataApplyPortMode,
        fileManager: FileManager = .default
    ) throws {
        guard rootURL.isFileURL else {
            throw CanonicalLibraryMetadataCutoverFailure.resourceMoveAttempted
        }
        self.fileManager = fileManager
        self.rootURL = rootURL.standardizedFileURL
        self.rootToken = rootToken
        self.mode = mode
    }

    var applyPortMode: CanonicalLibraryMetadataApplyPortMode {
        mode
    }

    func setPayload(
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain,
        metadataBytes: Data,
        metadataHash: CanonicalHash,
        businessModifiedAt: CanonicalTimestamp? = nil,
        logicalPathToken: String? = nil,
        actionID: String? = nil
    ) throws {
        let target = try CanonicalRootBoundLibraryMetadataTarget(
            rootToken: rootToken,
            objectID: objectID,
            objectKind: objectKind,
            domain: domain,
            logicalPathToken: logicalPathToken ?? CanonicalRootBoundLibraryMetadataTarget.defaultLogicalPathToken(
                objectID: objectID,
                objectKind: objectKind,
                domain: domain
            )
        )
        let write = CanonicalRootBoundLibraryMetadataWrite(
            target: target,
            metadataBytes: metadataBytes,
            metadataHash: metadataHash,
            businessModifiedAt: businessModifiedAt
        )
        payloadsByObject[key(objectID: target.objectID, objectKind: objectKind, domain: domain)] = write
        if let actionID {
            payloadsByActionID[CanonicalProductionRedaction.safeIdentifier(actionID, fallback: domain.rawValue)] = write
        }
    }

    func injectCheckpointFailure(objectID: String) {
        checkpointFailureObjectIDs.insert(CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object"))
    }

    func injectPostconditionFailure(objectID: String) {
        postconditionFailureObjectIDs.insert(CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object"))
    }

    func injectRollbackFailure(checkpointID: String) {
        rollbackFailureCheckpointIDs.insert(CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "library-metadata-checkpoint"))
    }

    func write(
        action: CanonicalApplyAction,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain,
        checkpointID: String?
    ) throws -> CanonicalRootBoundLibraryMetadataWriteResult {
        try requireWritableMode()
        let objectID = CanonicalProductionRedaction.safeIdentifier(action.target.objectID, fallback: "library-object")
        guard let payload = payloadsByActionID[action.actionID] ?? payloadsByObject[key(objectID: objectID, objectKind: objectKind, domain: domain)] else {
            throw CanonicalLibraryMetadataCutoverFailure.applyFailureBeforeCommit
        }
        guard payload.target.objectID == objectID else {
            throw CanonicalLibraryMetadataCutoverFailure.objectKindMismatch
        }
        let effectiveObjectKind = payload.target.objectKind
        let effectiveDomain = payload.target.domain
        guard !checkpointFailureObjectIDs.contains(objectID) else {
            throw CanonicalLibraryMetadataCutoverFailure.applyFailureBeforeCommit
        }
        let effectiveCheckpointID = CanonicalProductionRedaction.safeIdentifier(
            checkpointID ?? "root-bound-library-metadata-\(objectID)-\(domain.rawValue)",
            fallback: "library-metadata-checkpoint"
        )
        let targetURL = try resolvedURL(for: payload.target)
        let previousBytes = fileManager.fileExists(atPath: targetURL.path) ? try Data(contentsOf: targetURL) : nil
        let previousHash = previousBytes.map(Self.sha256)
        let checkpoint = CanonicalRootBoundLibraryMetadataCheckpoint(
            checkpointID: effectiveCheckpointID,
            objectID: objectID,
            objectKind: effectiveObjectKind,
            domain: effectiveDomain,
            hashBefore: previousHash,
            byteCountBefore: previousBytes?.count,
            existedBeforeWrite: previousBytes != nil,
            rollbackAvailable: true
        )
        checkpoints[effectiveCheckpointID] = StoredCheckpoint(
            publicCheckpoint: checkpoint,
            target: payload.target,
            previousBytes: previousBytes,
            previousHash: previousHash
        )
        do {
            try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.metadataBytes.write(to: targetURL, options: [.atomic])
            let reread = try Data(contentsOf: targetURL)
            guard !postconditionFailureObjectIDs.contains(objectID),
                  reread == payload.metadataBytes else {
                try restore(checkpointID: effectiveCheckpointID)
                throw CanonicalLibraryMetadataCutoverFailure.postconditionMismatch
            }
            let afterHash = Self.sha256(reread)
            guard afterHash == payload.metadataHash else {
                try restore(checkpointID: effectiveCheckpointID)
                throw CanonicalLibraryMetadataCutoverFailure.postconditionMismatch
            }
            let result = CanonicalRootBoundLibraryMetadataWriteResult(
                objectID: objectID,
                objectKind: effectiveObjectKind,
                domain: effectiveDomain,
                hashBefore: previousHash,
                hashAfter: afterHash,
                byteCount: reread.count,
                checkpointID: effectiveCheckpointID,
                atomicWriteUsed: true,
                rollbackAvailable: true
            )
            lastWriteByActionID[action.actionID] = result
            return result
        } catch let failure as CanonicalLibraryMetadataCutoverFailure {
            throw failure
        } catch CocoaError.fileWriteNoPermission {
            try? restore(checkpointID: effectiveCheckpointID)
            throw CanonicalLibraryMetadataCutoverFailure.applyFailureBeforeCommit
        } catch {
            try? restore(checkpointID: effectiveCheckpointID)
            throw CanonicalLibraryMetadataCutoverFailure.applyFailureBeforeCommit
        }
    }

    func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) -> CanonicalProductionApplyPostcondition {
        var checked = postcondition
        let objectID = CanonicalProductionRedaction.safeIdentifier(postcondition.target.objectID, fallback: "library-object")
        if postconditionFailureObjectIDs.contains(objectID) {
            checked.accepted = false
            checked.reason = CanonicalLibraryMetadataCutoverFailure.postconditionMismatch.rawValue
            return checked
        }
        guard lastWriteByActionID[postcondition.actionID] != nil else {
            checked.accepted = false
            checked.reason = "libraryMetadataWriteMissing"
            return checked
        }
        checked.accepted = true
        return checked
    }

    func rollback(_ request: CanonicalRollbackAction) -> CanonicalRootBoundLibraryMetadataRollbackResult {
        let checkpointID = CanonicalProductionRedaction.safeIdentifier(
            request.checkpointID ?? request.actionID,
            fallback: "library-metadata-checkpoint"
        )
        guard let stored = checkpoints[checkpointID] else {
            return CanonicalRootBoundLibraryMetadataRollbackResult(
                objectID: request.objectID ?? "library-object",
                objectKind: .unknownUnsupported,
                domain: .studyItemMetadata,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                failure: .rollbackFailure
            )
        }
        if rollbackFailureCheckpointIDs.contains(checkpointID) {
            return CanonicalRootBoundLibraryMetadataRollbackResult(
                objectID: stored.target.objectID,
                objectKind: stored.target.objectKind,
                domain: stored.target.domain,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                failure: .rollbackFailure
            )
        }
        do {
            try restore(checkpointID: checkpointID)
            let targetURL = try resolvedURL(for: stored.target)
            let currentBytes = fileManager.fileExists(atPath: targetURL.path) ? try Data(contentsOf: targetURL) : nil
            let verified = currentBytes == stored.previousBytes
            let result = CanonicalRootBoundLibraryMetadataRollbackResult(
                objectID: stored.target.objectID,
                objectKind: stored.target.objectKind,
                domain: stored.target.domain,
                checkpointID: checkpointID,
                succeeded: verified,
                rollbackVerified: verified,
                hashAfterRollback: currentBytes.map(Self.sha256),
                byteCount: currentBytes?.count,
                failure: verified ? nil : .rollbackFailure
            )
            lastRollbackByCheckpointID[checkpointID] = result
            if verified {
                checkpoints.removeValue(forKey: checkpointID)
            }
            return result
        } catch {
            let result = CanonicalRootBoundLibraryMetadataRollbackResult(
                objectID: stored.target.objectID,
                objectKind: stored.target.objectKind,
                domain: stored.target.domain,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                failure: .rollbackFailure
            )
            lastRollbackByCheckpointID[checkpointID] = result
            return result
        }
    }

    func lastWriteResult(actionID: String) -> CanonicalRootBoundLibraryMetadataWriteResult? {
        lastWriteByActionID[CanonicalProductionRedaction.safeIdentifier(actionID, fallback: "library-action")]
    }

    func lastRollbackResult(checkpointID: String) -> CanonicalRootBoundLibraryMetadataRollbackResult? {
        lastRollbackByCheckpointID[CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "library-metadata-checkpoint")]
    }

    func readMetadataBytes(
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain
    ) throws -> Data? {
        let safeObjectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "library-object")
        guard let payload = payloadsByObject[key(objectID: safeObjectID, objectKind: objectKind, domain: domain)] else {
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
            throw CanonicalLibraryMetadataCutoverFailure.applyPortDryRunOnly
        }
    }

    private func resolvedURL(for target: CanonicalRootBoundLibraryMetadataTarget) throws -> URL {
        guard target.rootToken == rootToken else {
            throw CanonicalLibraryMetadataCutoverFailure.resourceMoveAttempted
        }
        let url = rootURL.appendingPathComponent(target.logicalPathToken, isDirectory: false).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        guard url.path.hasPrefix(rootPath) else {
            throw CanonicalLibraryMetadataCutoverFailure.resourceMoveAttempted
        }
        return url
    }

    private func restore(checkpointID: String) throws {
        guard let stored = checkpoints[checkpointID] else {
            throw CanonicalLibraryMetadataCutoverFailure.rollbackFailure
        }
        let targetURL = try resolvedURL(for: stored.target)
        if let previousBytes = stored.previousBytes {
            try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try previousBytes.write(to: targetURL, options: [.atomic])
        } else if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
    }

    private nonisolated func key(
        objectID: String,
        objectKind: CanonicalObjectKind,
        domain: CanonicalLibraryMetadataCutoverDomain
    ) -> String {
        [domain.rawValue, objectKind.rawValue, objectID].joined(separator: "|")
    }

    private nonisolated static func sha256(_ data: Data) -> CanonicalHash {
        CanonicalTransportEnvelope.hash(data)
    }
}
