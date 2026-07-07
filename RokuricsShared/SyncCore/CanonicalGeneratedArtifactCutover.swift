//
//  CanonicalGeneratedArtifactCutover.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/4.
//

import CryptoKit
import Foundation

nonisolated enum CanonicalGeneratedArtifactCutoverDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case generatedArtifacts

    nonisolated var productionDomain: CanonicalProductionDomain {
        .generatedArtifacts
    }

    nonisolated var cutoverDomain: CanonicalCutoverDomain {
        .generatedArtifacts
    }
}

nonisolated enum CanonicalGeneratedArtifactCutoverActionKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case generatedArtifactApply
    case generatedArtifactDownloadApply
    case generatedArtifactNoOp
    case generatedArtifactConflictRecord
    case unsupported

    nonisolated var isExecutableApply: Bool {
        self == .generatedArtifactApply || self == .generatedArtifactDownloadApply
    }
}

nonisolated enum CanonicalGeneratedArtifactCutoverFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedDomain
    case unsupportedMode
    case unsupportedKind
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
    case legacyFallbackUnavailable
    case missingArtifactRequestRouteEvidence
    case productionPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case rollbackVerificationMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case parentTombstoned
    case peerUnknown
    case peerNotAuthoritative
    case producerAmbiguous
    case artifactIDMismatch
    case objectIDMismatch
    case expectedHashMissing
    case expectedByteSizeMissing
    case localPreviousStateMissing
    case artifactBytesMissing
    case hashMismatchBeforeApply
    case applyFailureBeforeCommit
    case applyFailureAfterPartialCommit
    case postconditionMismatch
    case rollbackFailure
    case missingInternalCanaryConfiguration
    case canaryBudgetAboveOneDenied
    case allEligibleCanaryDenied
    case activePilotNotGeneratedArtifacts
    case matrixValidationBlocked
    case defaultEnablementDenied
    case missingReadSideParallelEvidence
    case commitExecutorUnavailable
    case peerSnapshotUnavailable
    case missingCanaryStageEvidence
    case canaryStageBlocked
    case canaryStageOrderViolation
    case observationWindowIncomplete
    case runtimeSwitchDenied
    case previousStageFailure
    case previousStageRollbackFailure
    case contentLeakRisk
    case unsafePathToken
    case audioConfusionRisk
    case hashUnavailable
    case byteSizeUnavailable
}

nonisolated struct CanonicalGeneratedArtifactCutoverCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { action.actionID }

    var action: CanonicalApplyAction
    var localObject: CanonicalRecordingObject?
    var peerObject: CanonicalRecordingObject?
    var localArtifact: CanonicalArtifact?
    var peerArtifact: CanonicalArtifact?
    var rollbackCheckpointID: String?
    var unresolvedConflict: Bool
    var routePath: String

    nonisolated init(
        action: CanonicalApplyAction,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?,
        localArtifact: CanonicalArtifact? = nil,
        peerArtifact: CanonicalArtifact? = nil,
        rollbackCheckpointID: String? = nil,
        unresolvedConflict: Bool = false,
        routePath: String = "/sync/artifact-request"
    ) {
        self.action = action
        self.localObject = localObject
        self.peerObject = peerObject
        let targetKind = action.target.artifactKind
        self.localArtifact = localArtifact ?? Self.artifact(kind: targetKind, in: localObject)
        self.peerArtifact = peerArtifact ?? Self.artifact(kind: targetKind, in: peerObject)
        self.rollbackCheckpointID = rollbackCheckpointID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "generated-artifact-checkpoint")
        }
        self.unresolvedConflict = unresolvedConflict
        self.routePath = CanonicalProductionRedaction.safeDiagnosticText(routePath) ?? "/sync/artifact-request"
    }

    nonisolated var objectID: String {
        action.target.objectID
    }

    nonisolated var artifactID: String? {
        action.target.artifactID ?? peerArtifact?.artifactID ?? localArtifact?.artifactID
    }

    nonisolated var artifactKind: CanonicalArtifact.Kind? {
        action.target.artifactKind ?? peerArtifact?.kind ?? localArtifact?.kind
    }

    nonisolated var cutoverActionKind: CanonicalGeneratedArtifactCutoverActionKind {
        switch action.kind {
        case .generatedArtifactDownloadApply:
            return .generatedArtifactDownloadApply
        case .generatedArtifactNoOp:
            return .generatedArtifactNoOp
        case .conflictRecord where action.target.artifactKind != nil:
            return .generatedArtifactConflictRecord
        default:
            return .unsupported
        }
    }

    nonisolated var expectedArtifact: CanonicalArtifact? {
        peerArtifact
    }

    nonisolated var expectedContentHash: CanonicalHash? {
        expectedArtifact?.contentHash
    }

    nonisolated var expectedByteSize: Int64? {
        expectedArtifact?.byteSize
    }

    nonisolated var expectedLogicalPathToken: String? {
        expectedArtifact?.logicalPathToken ?? action.target.artifactKind.map {
            CanonicalRootBoundGeneratedArtifactTarget.defaultLogicalPathToken(objectID: objectID, kind: $0)
        }
    }

    nonisolated var effectiveRollbackCheckpointID: String {
        rollbackCheckpointID ?? "generated-artifact-cutover-\(objectID)-\(artifactKind?.rawValue ?? "unknown")"
    }

    nonisolated var parentObjectTombstoned: Bool {
        localObject?.metadata.isDeleted == true
            || peerObject?.metadata.isDeleted == true
            || localObject?.syncState == .deleted
            || peerObject?.syncState == .deleted
    }

    nonisolated func peerIsAuthoritative(peerNode: CanonicalNode?) -> Bool {
        guard let peerArtifact, let peerNode else {
            return false
        }
        return CanonicalProjectionContract.isAuthoritativeProducer(peerArtifact, node: peerNode)
    }

    nonisolated static func candidates(
        from applyPlan: CanonicalApplyPlan,
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest,
        rollbackCheckpointPrefix: String = "generated-artifact-cutover"
    ) -> [CanonicalGeneratedArtifactCutoverCandidate] {
        let localObjects = Dictionary(uniqueKeysWithValues: localManifest.objects.map { ($0.objectID, $0) })
        let peerObjects = Dictionary(uniqueKeysWithValues: peerManifest.objects.map { ($0.objectID, $0) })
        return applyPlan.actions.compactMap { action in
            guard action.kind == .generatedArtifactDownloadApply else {
                return nil
            }
            return CanonicalGeneratedArtifactCutoverCandidate(
                action: action,
                localObject: localObjects[action.target.objectID],
                peerObject: peerObjects[action.target.objectID],
                rollbackCheckpointID: "\(rollbackCheckpointPrefix)-\(action.target.objectID)-\(action.target.artifactKind?.rawValue ?? "artifact")"
            )
        }
    }

    private nonisolated static func artifact(
        kind: CanonicalArtifact.Kind?,
        in object: CanonicalRecordingObject?
    ) -> CanonicalArtifact? {
        guard let kind else {
            return nil
        }
        return object?.artifacts.first { $0.kind == kind }
    }
}

nonisolated enum CanonicalGeneratedArtifactApplyPortMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
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

nonisolated struct CanonicalGeneratedArtifactCutoverEvidence: Codable, Equatable, Sendable {
    var noCommitEvidenceAvailable: Bool
    var realDataShadowCopyVerified: Bool
    var executionShadowVerified: Bool
    var dryRunEquivalenceVerified: Bool
    var noBlockingDivergence: Bool
    var noUnresolvedConflict: Bool
    var artifactRequestRouteEvidenceAvailable: Bool
    var productionPortAvailable: Bool
    var realRootBoundApplyPortAvailable: Bool
    var applyPortMode: CanonicalGeneratedArtifactApplyPortMode
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
    var canaryStageEvidence: CanonicalGeneratedArtifactCanaryStageEvidence?

    nonisolated init(
        noCommitEvidenceAvailable: Bool = false,
        realDataShadowCopyVerified: Bool = false,
        executionShadowVerified: Bool = false,
        dryRunEquivalenceVerified: Bool = false,
        noBlockingDivergence: Bool = false,
        noUnresolvedConflict: Bool = false,
        artifactRequestRouteEvidenceAvailable: Bool = false,
        productionPortAvailable: Bool = false,
        realRootBoundApplyPortAvailable: Bool = false,
        applyPortMode: CanonicalGeneratedArtifactApplyPortMode = .disabled,
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
        canaryStageEvidence: CanonicalGeneratedArtifactCanaryStageEvidence? = nil
    ) {
        self.noCommitEvidenceAvailable = noCommitEvidenceAvailable
        self.realDataShadowCopyVerified = realDataShadowCopyVerified
        self.executionShadowVerified = executionShadowVerified
        self.dryRunEquivalenceVerified = dryRunEquivalenceVerified
        self.noBlockingDivergence = noBlockingDivergence
        self.noUnresolvedConflict = noUnresolvedConflict
        self.artifactRequestRouteEvidenceAvailable = artifactRequestRouteEvidenceAvailable
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

    nonisolated static func passing(rollbackPlan: CanonicalRollbackPlan) -> CanonicalGeneratedArtifactCutoverEvidence {
        CanonicalGeneratedArtifactCutoverEvidence(
            noCommitEvidenceAvailable: true,
            realDataShadowCopyVerified: true,
            executionShadowVerified: true,
            dryRunEquivalenceVerified: true,
            noBlockingDivergence: true,
            noUnresolvedConflict: true,
            artifactRequestRouteEvidenceAvailable: true,
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

nonisolated enum CanonicalGeneratedArtifactCanaryStage: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case n1
    case n3
    case n10
    case allEligible

    nonisolated var isExecutable: Bool {
        self != .disabled
    }

    nonisolated var previousStage: CanonicalGeneratedArtifactCanaryStage? {
        switch self {
        case .disabled:
            return nil
        case .n1:
            return .disabled
        case .n3:
            return .n1
        case .n10:
            return .n3
        case .allEligible:
            return .n10
        }
    }

    nonisolated var nominalCanaryBudget: Int {
        switch self {
        case .disabled:
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

    nonisolated var minimumPreviousStageSuccessCount: Int {
        switch self {
        case .disabled, .n1:
            return 0
        case .n3:
            return 1
        case .n10:
            return 3
        case .allEligible:
            return 10
        }
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryStagePolicy: Codable, Equatable, Sendable {
    var requestedStage: CanonicalGeneratedArtifactCanaryStage
    var allowCandidateExecution: Bool
    var runtimeSwitchEnabled: Bool

    nonisolated init(
        requestedStage: CanonicalGeneratedArtifactCanaryStage = .disabled,
        allowCandidateExecution: Bool = false,
        runtimeSwitchEnabled: Bool = false
    ) {
        self.requestedStage = requestedStage
        self.allowCandidateExecution = allowCandidateExecution
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
    }

    nonisolated static let disabled = CanonicalGeneratedArtifactCanaryStagePolicy()

    nonisolated var canaryBudget: Int {
        requestedStage.nominalCanaryBudget
    }
}

nonisolated enum CanonicalGeneratedArtifactStageEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missing
    case incomplete
    case passed
    case failed
    case blocked

    nonisolated var isPassing: Bool {
        self == .passed
    }
}

nonisolated enum CanonicalGeneratedArtifactStageEvidenceBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case stageDisabled
    case unsupportedDomain
    case runtimeSwitchEnabled
    case candidateExecutionNotApproved
    case previousStageEvidenceMissing
    case stageOrderViolation
    case previousStageInsufficientSuccess
    case previousStageFailure
    case previousStageRollbackFailure
    case previousStageBlockingDivergence
    case previousStageUnresolvedConflict
    case previousStagePostconditionFailure
    case previousStageUnsupportedArtifact
    case previousStageContentLeakRisk
    case previousStageUnsafePathToken
    case previousStageParentTombstone
    case previousStageAudioConfusion
    case previousStageHashUnavailable
    case previousStageByteSizeUnavailable
    case observationWindowIncomplete
    case noCommitEvidenceMissing
    case ownerApprovalMissing
    case rollbackPlanMissing
    case dryRunEquivalenceMissing
    case executionShadowMissing
    case realDataShadowCopyMissing
    case readOnlyTransportProbeMissing
    case productionApplyPortUnavailable
    case artifactRequestRouteEvidenceMissing
    case legacyFallbackUnavailable
    case readSideParallelDivergent
}

nonisolated struct CanonicalGeneratedArtifactStageObservationWindow: Codable, Equatable, Sendable {
    var observationWindowID: String
    var complete: Bool

    nonisolated init(observationWindowID: String = "generated-artifact-stage-window", complete: Bool = false) {
        self.observationWindowID = CanonicalProductionRedaction.safeIdentifier(
            observationWindowID,
            fallback: "generated-artifact-stage-window"
        )
        self.complete = complete
    }

    nonisolated static func complete(_ id: String) -> CanonicalGeneratedArtifactStageObservationWindow {
        CanonicalGeneratedArtifactStageObservationWindow(observationWindowID: id, complete: true)
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryStageEvidence: Codable, Equatable, Sendable {
    var previousStage: CanonicalGeneratedArtifactCanaryStage
    var requestedStage: CanonicalGeneratedArtifactCanaryStage
    var previousStageSuccessCount: Int
    var previousStageFailureCount: Int
    var previousStageRollbackFailureCount: Int
    var previousStageBlockingDivergenceCount: Int
    var previousStageContentLeakRiskCount: Int
    var previousStageUnsafePathTokenCount: Int
    var previousStageParentTombstoneBlockCount: Int
    var previousStageAudioConfusionBlockCount: Int
    var previousStageSuppressedLegacyDuplicateCount: Int
    var previousStagePostconditionFailureCount: Int
    var previousStageUnsupportedArtifactCount: Int
    var previousStageHashUnavailableCount: Int
    var previousStageByteSizeUnavailableCount: Int
    var unresolvedConflictCount: Int
    var dryRunEquivalenceStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var executionShadowStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var realDataShadowCopyStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var readOnlyTransportProbeStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var noCommitEvidenceStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var rollbackPlanStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var productionApplyPortStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var artifactRequestRouteEvidenceStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var legacyFallbackStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var readSideParallelStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var observationWindowID: String
    var observationWindowComplete: Bool
    var ownerApproved: Bool

    nonisolated init(
        previousStage: CanonicalGeneratedArtifactCanaryStage = .disabled,
        requestedStage: CanonicalGeneratedArtifactCanaryStage = .disabled,
        previousStageSuccessCount: Int = 0,
        previousStageFailureCount: Int = 0,
        previousStageRollbackFailureCount: Int = 0,
        previousStageBlockingDivergenceCount: Int = 0,
        previousStageContentLeakRiskCount: Int = 0,
        previousStageUnsafePathTokenCount: Int = 0,
        previousStageParentTombstoneBlockCount: Int = 0,
        previousStageAudioConfusionBlockCount: Int = 0,
        previousStageSuppressedLegacyDuplicateCount: Int = 0,
        previousStagePostconditionFailureCount: Int = 0,
        previousStageUnsupportedArtifactCount: Int = 0,
        previousStageHashUnavailableCount: Int = 0,
        previousStageByteSizeUnavailableCount: Int = 0,
        unresolvedConflictCount: Int = 0,
        dryRunEquivalenceStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        executionShadowStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        realDataShadowCopyStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        readOnlyTransportProbeStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        noCommitEvidenceStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        rollbackPlanStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        productionApplyPortStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        artifactRequestRouteEvidenceStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        legacyFallbackStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        readSideParallelStatus: CanonicalGeneratedArtifactStageEvidenceStatus = .missing,
        observationWindow: CanonicalGeneratedArtifactStageObservationWindow = CanonicalGeneratedArtifactStageObservationWindow(),
        ownerApproved: Bool = false
    ) {
        self.previousStage = previousStage
        self.requestedStage = requestedStage
        self.previousStageSuccessCount = max(0, previousStageSuccessCount)
        self.previousStageFailureCount = max(0, previousStageFailureCount)
        self.previousStageRollbackFailureCount = max(0, previousStageRollbackFailureCount)
        self.previousStageBlockingDivergenceCount = max(0, previousStageBlockingDivergenceCount)
        self.previousStageContentLeakRiskCount = max(0, previousStageContentLeakRiskCount)
        self.previousStageUnsafePathTokenCount = max(0, previousStageUnsafePathTokenCount)
        self.previousStageParentTombstoneBlockCount = max(0, previousStageParentTombstoneBlockCount)
        self.previousStageAudioConfusionBlockCount = max(0, previousStageAudioConfusionBlockCount)
        self.previousStageSuppressedLegacyDuplicateCount = max(0, previousStageSuppressedLegacyDuplicateCount)
        self.previousStagePostconditionFailureCount = max(0, previousStagePostconditionFailureCount)
        self.previousStageUnsupportedArtifactCount = max(0, previousStageUnsupportedArtifactCount)
        self.previousStageHashUnavailableCount = max(0, previousStageHashUnavailableCount)
        self.previousStageByteSizeUnavailableCount = max(0, previousStageByteSizeUnavailableCount)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.dryRunEquivalenceStatus = dryRunEquivalenceStatus
        self.executionShadowStatus = executionShadowStatus
        self.realDataShadowCopyStatus = realDataShadowCopyStatus
        self.readOnlyTransportProbeStatus = readOnlyTransportProbeStatus
        self.noCommitEvidenceStatus = noCommitEvidenceStatus
        self.rollbackPlanStatus = rollbackPlanStatus
        self.productionApplyPortStatus = productionApplyPortStatus
        self.artifactRequestRouteEvidenceStatus = artifactRequestRouteEvidenceStatus
        self.legacyFallbackStatus = legacyFallbackStatus
        self.readSideParallelStatus = readSideParallelStatus
        self.observationWindowID = observationWindow.observationWindowID
        self.observationWindowComplete = observationWindow.complete
        self.ownerApproved = ownerApproved
    }

    nonisolated static func passing(
        previousStage: CanonicalGeneratedArtifactCanaryStage,
        requestedStage: CanonicalGeneratedArtifactCanaryStage,
        previousStageSuccessCount: Int,
        observationWindowID: String
    ) -> CanonicalGeneratedArtifactCanaryStageEvidence {
        CanonicalGeneratedArtifactCanaryStageEvidence(
            previousStage: previousStage,
            requestedStage: requestedStage,
            previousStageSuccessCount: previousStageSuccessCount,
            dryRunEquivalenceStatus: .passed,
            executionShadowStatus: .passed,
            realDataShadowCopyStatus: .passed,
            readOnlyTransportProbeStatus: .passed,
            noCommitEvidenceStatus: .passed,
            rollbackPlanStatus: .passed,
            productionApplyPortStatus: .passed,
            artifactRequestRouteEvidenceStatus: .passed,
            legacyFallbackStatus: .passed,
            readSideParallelStatus: .passed,
            observationWindow: .complete(observationWindowID),
            ownerApproved: true
        )
    }

    private enum CodingKeys: String, CodingKey {
        case previousStage
        case requestedStage
        case previousStageSuccessCount
        case previousStageFailureCount
        case previousStageRollbackFailureCount
        case previousStageBlockingDivergenceCount
        case previousStageContentLeakRiskCount
        case previousStageUnsafePathTokenCount
        case previousStageParentTombstoneBlockCount
        case previousStageAudioConfusionBlockCount
        case previousStageSuppressedLegacyDuplicateCount
        case previousStagePostconditionFailureCount
        case previousStageUnsupportedArtifactCount
        case previousStageHashUnavailableCount
        case previousStageByteSizeUnavailableCount
        case unresolvedConflictCount
        case dryRunEquivalenceStatus
        case executionShadowStatus
        case realDataShadowCopyStatus
        case readOnlyTransportProbeStatus
        case noCommitEvidenceStatus
        case rollbackPlanStatus
        case productionApplyPortStatus
        case artifactRequestRouteEvidenceStatus
        case legacyFallbackStatus
        case readSideParallelStatus
        case observationWindowID
        case observationWindowComplete
        case ownerApproved
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let previousStage = try container.decodeIfPresent(CanonicalGeneratedArtifactCanaryStage.self, forKey: .previousStage) ?? .disabled
        let requestedStage = try container.decodeIfPresent(CanonicalGeneratedArtifactCanaryStage.self, forKey: .requestedStage) ?? .disabled
        let observationWindowID = try container.decodeIfPresent(String.self, forKey: .observationWindowID) ?? "generated-artifact-stage-window"
        let observationWindowComplete = try container.decodeIfPresent(Bool.self, forKey: .observationWindowComplete) ?? false
        self.init(
            previousStage: previousStage,
            requestedStage: requestedStage,
            previousStageSuccessCount: try container.decodeIfPresent(Int.self, forKey: .previousStageSuccessCount) ?? 0,
            previousStageFailureCount: try container.decodeIfPresent(Int.self, forKey: .previousStageFailureCount) ?? 0,
            previousStageRollbackFailureCount: try container.decodeIfPresent(Int.self, forKey: .previousStageRollbackFailureCount) ?? 0,
            previousStageBlockingDivergenceCount: try container.decodeIfPresent(Int.self, forKey: .previousStageBlockingDivergenceCount) ?? 0,
            previousStageContentLeakRiskCount: try container.decodeIfPresent(Int.self, forKey: .previousStageContentLeakRiskCount) ?? 0,
            previousStageUnsafePathTokenCount: try container.decodeIfPresent(Int.self, forKey: .previousStageUnsafePathTokenCount) ?? 0,
            previousStageParentTombstoneBlockCount: try container.decodeIfPresent(Int.self, forKey: .previousStageParentTombstoneBlockCount) ?? 0,
            previousStageAudioConfusionBlockCount: try container.decodeIfPresent(Int.self, forKey: .previousStageAudioConfusionBlockCount) ?? 0,
            previousStageSuppressedLegacyDuplicateCount: try container.decodeIfPresent(Int.self, forKey: .previousStageSuppressedLegacyDuplicateCount) ?? 0,
            previousStagePostconditionFailureCount: try container.decodeIfPresent(Int.self, forKey: .previousStagePostconditionFailureCount) ?? 0,
            previousStageUnsupportedArtifactCount: try container.decodeIfPresent(Int.self, forKey: .previousStageUnsupportedArtifactCount) ?? 0,
            previousStageHashUnavailableCount: try container.decodeIfPresent(Int.self, forKey: .previousStageHashUnavailableCount) ?? 0,
            previousStageByteSizeUnavailableCount: try container.decodeIfPresent(Int.self, forKey: .previousStageByteSizeUnavailableCount) ?? 0,
            unresolvedConflictCount: try container.decodeIfPresent(Int.self, forKey: .unresolvedConflictCount) ?? 0,
            dryRunEquivalenceStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .dryRunEquivalenceStatus) ?? .missing,
            executionShadowStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .executionShadowStatus) ?? .missing,
            realDataShadowCopyStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .realDataShadowCopyStatus) ?? .missing,
            readOnlyTransportProbeStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .readOnlyTransportProbeStatus) ?? .missing,
            noCommitEvidenceStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .noCommitEvidenceStatus) ?? .missing,
            rollbackPlanStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .rollbackPlanStatus) ?? .missing,
            productionApplyPortStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .productionApplyPortStatus) ?? .missing,
            artifactRequestRouteEvidenceStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .artifactRequestRouteEvidenceStatus) ?? .missing,
            legacyFallbackStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .legacyFallbackStatus) ?? .missing,
            readSideParallelStatus: try container.decodeIfPresent(CanonicalGeneratedArtifactStageEvidenceStatus.self, forKey: .readSideParallelStatus) ?? .missing,
            observationWindow: CanonicalGeneratedArtifactStageObservationWindow(
                observationWindowID: observationWindowID,
                complete: observationWindowComplete
            ),
            ownerApproved: try container.decodeIfPresent(Bool.self, forKey: .ownerApproved) ?? false
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(previousStage, forKey: .previousStage)
        try container.encode(requestedStage, forKey: .requestedStage)
        try container.encode(previousStageSuccessCount, forKey: .previousStageSuccessCount)
        try container.encode(previousStageFailureCount, forKey: .previousStageFailureCount)
        try container.encode(previousStageRollbackFailureCount, forKey: .previousStageRollbackFailureCount)
        try container.encode(previousStageBlockingDivergenceCount, forKey: .previousStageBlockingDivergenceCount)
        try container.encode(previousStageContentLeakRiskCount, forKey: .previousStageContentLeakRiskCount)
        try container.encode(previousStageUnsafePathTokenCount, forKey: .previousStageUnsafePathTokenCount)
        try container.encode(previousStageParentTombstoneBlockCount, forKey: .previousStageParentTombstoneBlockCount)
        try container.encode(previousStageAudioConfusionBlockCount, forKey: .previousStageAudioConfusionBlockCount)
        try container.encode(previousStageSuppressedLegacyDuplicateCount, forKey: .previousStageSuppressedLegacyDuplicateCount)
        try container.encode(previousStagePostconditionFailureCount, forKey: .previousStagePostconditionFailureCount)
        try container.encode(previousStageUnsupportedArtifactCount, forKey: .previousStageUnsupportedArtifactCount)
        try container.encode(previousStageHashUnavailableCount, forKey: .previousStageHashUnavailableCount)
        try container.encode(previousStageByteSizeUnavailableCount, forKey: .previousStageByteSizeUnavailableCount)
        try container.encode(unresolvedConflictCount, forKey: .unresolvedConflictCount)
        try container.encode(dryRunEquivalenceStatus, forKey: .dryRunEquivalenceStatus)
        try container.encode(executionShadowStatus, forKey: .executionShadowStatus)
        try container.encode(realDataShadowCopyStatus, forKey: .realDataShadowCopyStatus)
        try container.encode(readOnlyTransportProbeStatus, forKey: .readOnlyTransportProbeStatus)
        try container.encode(noCommitEvidenceStatus, forKey: .noCommitEvidenceStatus)
        try container.encode(rollbackPlanStatus, forKey: .rollbackPlanStatus)
        try container.encode(productionApplyPortStatus, forKey: .productionApplyPortStatus)
        try container.encode(artifactRequestRouteEvidenceStatus, forKey: .artifactRequestRouteEvidenceStatus)
        try container.encode(legacyFallbackStatus, forKey: .legacyFallbackStatus)
        try container.encode(readSideParallelStatus, forKey: .readSideParallelStatus)
        try container.encode(observationWindowID, forKey: .observationWindowID)
        try container.encode(observationWindowComplete, forKey: .observationWindowComplete)
        try container.encode(ownerApproved, forKey: .ownerApproved)
    }
}

nonisolated struct CanonicalGeneratedArtifactStageEvidenceReport: Codable, Equatable, Sendable {
    var status: CanonicalGeneratedArtifactStageEvidenceStatus
    var blockers: [CanonicalGeneratedArtifactStageEvidenceBlocker]
    var previousStage: CanonicalGeneratedArtifactCanaryStage
    var requestedStage: CanonicalGeneratedArtifactCanaryStage
    var previousStageSuccessCount: Int
    var previousStageFailureCount: Int
    var previousStageRollbackFailureCount: Int
    var previousStageBlockingDivergenceCount: Int
    var previousStageContentLeakRiskCount: Int
    var previousStageUnsafePathTokenCount: Int
    var previousStageParentTombstoneBlockCount: Int
    var previousStageAudioConfusionBlockCount: Int
    var previousStageSuppressedLegacyDuplicateCount: Int
    var previousStagePostconditionFailureCount: Int
    var previousStageUnsupportedArtifactCount: Int
    var previousStageHashUnavailableCount: Int
    var previousStageByteSizeUnavailableCount: Int
    var unresolvedConflictCount: Int
    var dryRunEquivalenceStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var executionShadowStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var realDataShadowCopyStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var readOnlyTransportProbeStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var noCommitEvidenceStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var rollbackPlanStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var productionApplyPortStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var artifactRequestRouteEvidenceStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var legacyFallbackStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var readSideParallelStatus: CanonicalGeneratedArtifactStageEvidenceStatus
    var observationWindowID: String
    var observationWindowComplete: Bool
    var sensitiveFieldsRedacted: Bool

    nonisolated init(
        evidence: CanonicalGeneratedArtifactCanaryStageEvidence?,
        requestedStage: CanonicalGeneratedArtifactCanaryStage,
        blockers: [CanonicalGeneratedArtifactStageEvidenceBlocker]
    ) {
        let normalizedBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        if evidence == nil {
            status = .missing
        } else if normalizedBlockers.isEmpty {
            status = .passed
        } else if evidence?.observationWindowComplete == false {
            status = .incomplete
        } else {
            status = .blocked
        }
        self.blockers = normalizedBlockers
        self.previousStage = evidence?.previousStage ?? requestedStage.previousStage ?? .disabled
        self.requestedStage = requestedStage
        self.previousStageSuccessCount = evidence?.previousStageSuccessCount ?? 0
        self.previousStageFailureCount = evidence?.previousStageFailureCount ?? 0
        self.previousStageRollbackFailureCount = evidence?.previousStageRollbackFailureCount ?? 0
        self.previousStageBlockingDivergenceCount = evidence?.previousStageBlockingDivergenceCount ?? 0
        self.previousStageContentLeakRiskCount = evidence?.previousStageContentLeakRiskCount ?? 0
        self.previousStageUnsafePathTokenCount = evidence?.previousStageUnsafePathTokenCount ?? 0
        self.previousStageParentTombstoneBlockCount = evidence?.previousStageParentTombstoneBlockCount ?? 0
        self.previousStageAudioConfusionBlockCount = evidence?.previousStageAudioConfusionBlockCount ?? 0
        self.previousStageSuppressedLegacyDuplicateCount = evidence?.previousStageSuppressedLegacyDuplicateCount ?? 0
        self.previousStagePostconditionFailureCount = evidence?.previousStagePostconditionFailureCount ?? 0
        self.previousStageUnsupportedArtifactCount = evidence?.previousStageUnsupportedArtifactCount ?? 0
        self.previousStageHashUnavailableCount = evidence?.previousStageHashUnavailableCount ?? 0
        self.previousStageByteSizeUnavailableCount = evidence?.previousStageByteSizeUnavailableCount ?? 0
        self.unresolvedConflictCount = evidence?.unresolvedConflictCount ?? 0
        self.dryRunEquivalenceStatus = evidence?.dryRunEquivalenceStatus ?? .missing
        self.executionShadowStatus = evidence?.executionShadowStatus ?? .missing
        self.realDataShadowCopyStatus = evidence?.realDataShadowCopyStatus ?? .missing
        self.readOnlyTransportProbeStatus = evidence?.readOnlyTransportProbeStatus ?? .missing
        self.noCommitEvidenceStatus = evidence?.noCommitEvidenceStatus ?? .missing
        self.rollbackPlanStatus = evidence?.rollbackPlanStatus ?? .missing
        self.productionApplyPortStatus = evidence?.productionApplyPortStatus ?? .missing
        self.artifactRequestRouteEvidenceStatus = evidence?.artifactRequestRouteEvidenceStatus ?? .missing
        self.legacyFallbackStatus = evidence?.legacyFallbackStatus ?? .missing
        self.readSideParallelStatus = evidence?.readSideParallelStatus ?? .missing
        self.observationWindowID = evidence?.observationWindowID ?? "missing-observation-window"
        self.observationWindowComplete = evidence?.observationWindowComplete ?? false
        self.sensitiveFieldsRedacted = true
    }

    nonisolated var diagnosticsSummary: String {
        [
            "previousStage=\(previousStage.rawValue)",
            "requestedStage=\(requestedStage.rawValue)",
            "successCount=\(previousStageSuccessCount)",
            "failureCount=\(previousStageFailureCount)",
            "rollbackFailureCount=\(previousStageRollbackFailureCount)",
            "blockingDivergence=\(previousStageBlockingDivergenceCount)",
            "contentLeakRisk=\(previousStageContentLeakRiskCount)",
            "unsafePathToken=\(previousStageUnsafePathTokenCount)",
            "parentTombstone=\(previousStageParentTombstoneBlockCount)",
            "audioConfusion=\(previousStageAudioConfusionBlockCount)",
            "suppressedLegacyDuplicate=\(previousStageSuppressedLegacyDuplicateCount)",
            "postconditionFailure=\(previousStagePostconditionFailureCount)",
            "unsupportedArtifact=\(previousStageUnsupportedArtifactCount)",
            "hashUnavailable=\(previousStageHashUnavailableCount)",
            "byteSizeUnavailable=\(previousStageByteSizeUnavailableCount)",
            "unresolvedConflict=\(unresolvedConflictCount)",
            "noCommit=\(noCommitEvidenceStatus.rawValue)",
            "artifactRoute=\(artifactRequestRouteEvidenceStatus.rawValue)",
            "readSideParallel=\(readSideParallelStatus.rawValue)",
            "observationComplete=\(observationWindowComplete)",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=\(sensitiveFieldsRedacted)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryStageGate: Codable, Equatable, Sendable {
    var requestedStage: CanonicalGeneratedArtifactCanaryStage
    var allowed: Bool
    var selectedCandidateLimit: Int
    var selectsAllEligible: Bool
    var blockers: [CanonicalGeneratedArtifactStageEvidenceBlocker]
    var evidenceReport: CanonicalGeneratedArtifactStageEvidenceReport
    var reason: String

    nonisolated init(
        policy: CanonicalGeneratedArtifactCanaryStagePolicy,
        domain: CanonicalGeneratedArtifactCutoverDomain,
        token: CanonicalCutoverToken?,
        cutoverEvidence: CanonicalGeneratedArtifactCutoverEvidence
    ) {
        let requestedStage = policy.requestedStage
        var blockers: [CanonicalGeneratedArtifactStageEvidenceBlocker] = []
        if !requestedStage.isExecutable {
            blockers.append(.stageDisabled)
        }
        if domain != .generatedArtifacts {
            blockers.append(.unsupportedDomain)
        }
        if policy.runtimeSwitchEnabled {
            blockers.append(.runtimeSwitchEnabled)
        }
        if !policy.allowCandidateExecution {
            blockers.append(.candidateExecutionNotApproved)
        }
        if token?.ownerApproved != true && cutoverEvidence.canaryStageEvidence?.ownerApproved != true {
            blockers.append(.ownerApprovalMissing)
        }
        guard let evidence = cutoverEvidence.canaryStageEvidence else {
            blockers.append(.previousStageEvidenceMissing)
            self.requestedStage = requestedStage
            self.allowed = false
            self.selectedCandidateLimit = 0
            self.selectsAllEligible = false
            self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
            self.evidenceReport = CanonicalGeneratedArtifactStageEvidenceReport(
                evidence: nil,
                requestedStage: requestedStage,
                blockers: self.blockers
            )
            self.reason = "generatedArtifactCanaryStageBlocked"
            return
        }
        if evidence.requestedStage != requestedStage
            || evidence.previousStage != (requestedStage.previousStage ?? .disabled) {
            blockers.append(.stageOrderViolation)
        }
        if evidence.previousStageSuccessCount < requestedStage.minimumPreviousStageSuccessCount {
            blockers.append(.previousStageInsufficientSuccess)
        }
        if evidence.previousStageFailureCount > 0 {
            blockers.append(.previousStageFailure)
        }
        if evidence.previousStageRollbackFailureCount > 0 {
            blockers.append(.previousStageRollbackFailure)
        }
        if evidence.previousStageBlockingDivergenceCount > 0 || !cutoverEvidence.noBlockingDivergence {
            blockers.append(.previousStageBlockingDivergence)
        }
        if evidence.unresolvedConflictCount > 0 || !cutoverEvidence.noUnresolvedConflict {
            blockers.append(.previousStageUnresolvedConflict)
        }
        if evidence.previousStagePostconditionFailureCount > 0 {
            blockers.append(.previousStagePostconditionFailure)
        }
        if evidence.previousStageUnsupportedArtifactCount > 0 {
            blockers.append(.previousStageUnsupportedArtifact)
        }
        if evidence.previousStageContentLeakRiskCount > 0 {
            blockers.append(.previousStageContentLeakRisk)
        }
        if evidence.previousStageUnsafePathTokenCount > 0 {
            blockers.append(.previousStageUnsafePathToken)
        }
        if evidence.previousStageParentTombstoneBlockCount > 0 {
            blockers.append(.previousStageParentTombstone)
        }
        if evidence.previousStageAudioConfusionBlockCount > 0 {
            blockers.append(.previousStageAudioConfusion)
        }
        if evidence.previousStageHashUnavailableCount > 0 {
            blockers.append(.previousStageHashUnavailable)
        }
        if evidence.previousStageByteSizeUnavailableCount > 0 {
            blockers.append(.previousStageByteSizeUnavailable)
        }
        if !evidence.observationWindowComplete {
            blockers.append(.observationWindowIncomplete)
        }
        if !evidence.noCommitEvidenceStatus.isPassing || !cutoverEvidence.noCommitEvidenceAvailable {
            blockers.append(.noCommitEvidenceMissing)
        }
        if !evidence.dryRunEquivalenceStatus.isPassing || !cutoverEvidence.dryRunEquivalenceVerified {
            blockers.append(.dryRunEquivalenceMissing)
        }
        if !evidence.executionShadowStatus.isPassing || !cutoverEvidence.executionShadowVerified {
            blockers.append(.executionShadowMissing)
        }
        if !evidence.realDataShadowCopyStatus.isPassing || !cutoverEvidence.realDataShadowCopyVerified {
            blockers.append(.realDataShadowCopyMissing)
        }
        if !evidence.readOnlyTransportProbeStatus.isPassing || !cutoverEvidence.artifactRequestRouteEvidenceAvailable {
            blockers.append(.readOnlyTransportProbeMissing)
        }
        if !evidence.rollbackPlanStatus.isPassing
            || cutoverEvidence.rollbackPlan?.covers(domain: .generatedArtifacts) != true
            || !cutoverEvidence.rollbackRehearsalPassed
            || !cutoverEvidence.rollbackVerified {
            blockers.append(.rollbackPlanMissing)
        }
        if !evidence.productionApplyPortStatus.isPassing
            || !cutoverEvidence.productionPortAvailable
            || !cutoverEvidence.realRootBoundApplyPortAvailable
            || !cutoverEvidence.applyPortMode.isNonDryRunRootBound
            || !cutoverEvidence.rootBoundWriteAvailable
            || !cutoverEvidence.atomicReplaceAvailable
            || !cutoverEvidence.rollbackCheckpointAvailable {
            blockers.append(.productionApplyPortUnavailable)
        }
        if !evidence.artifactRequestRouteEvidenceStatus.isPassing || !cutoverEvidence.artifactRequestRouteEvidenceAvailable {
            blockers.append(.artifactRequestRouteEvidenceMissing)
        }
        if !evidence.legacyFallbackStatus.isPassing || !cutoverEvidence.legacyFallbackAvailable {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !evidence.readSideParallelStatus.isPassing || !cutoverEvidence.readSideParallelEquivalent {
            blockers.append(.readSideParallelDivergent)
        }

        self.requestedStage = requestedStage
        self.allowed = blockers.isEmpty
        self.selectedCandidateLimit = requestedStage.nominalCanaryBudget
        self.selectsAllEligible = requestedStage == .allEligible
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.evidenceReport = CanonicalGeneratedArtifactStageEvidenceReport(
            evidence: evidence,
            requestedStage: requestedStage,
            blockers: self.blockers
        )
        self.reason = self.allowed ? "generatedArtifactCanaryStageAllowed" : "generatedArtifactCanaryStageBlocked"
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryPolicy: Codable, Equatable, Sendable {
    var stagePolicy: CanonicalGeneratedArtifactCanaryStagePolicy
    var canaryMaxObjectsPerSyncRun: Int
    var allowsInternalN1Execution: Bool
    var explicitInternalTestConfiguration: Bool
    var runtimeSwitchEnabled: Bool
    var allowAllEligible: Bool

    nonisolated init(
        stagePolicy: CanonicalGeneratedArtifactCanaryStagePolicy = .disabled,
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

    nonisolated static let disabled = CanonicalGeneratedArtifactCanaryPolicy()

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
        self.stagePolicy = try container.decodeIfPresent(CanonicalGeneratedArtifactCanaryStagePolicy.self, forKey: .stagePolicy) ?? .disabled
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

nonisolated enum CanonicalGeneratedArtifactCanaryMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case n1

    nonisolated var isExecutable: Bool {
        self == .n1
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalGeneratedArtifactCanaryMode
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
        mode: CanonicalGeneratedArtifactCanaryMode = .disabled,
        domain: CanonicalMigrationDomain = .generatedArtifacts,
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

    nonisolated static let disabled = CanonicalGeneratedArtifactCanaryConfiguration()

    nonisolated static func internalN1(
        explicitInternalTestConfiguration: Bool = true
    ) -> CanonicalGeneratedArtifactCanaryConfiguration {
        CanonicalGeneratedArtifactCanaryConfiguration(
            mode: .n1,
            canaryMaxObjectsPerSyncRun: 1,
            explicitInternalTestConfiguration: explicitInternalTestConfiguration
        )
    }

    nonisolated init(appSeamConfiguration configuration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration) {
        let policy = configuration.policy.canaryPolicy
        let n1Requested = configuration.isEnabled
            && configuration.effectiveMode == .canaryCommit
            && policy.canaryMaxObjectsPerSyncRun == 1
        self.init(
            mode: n1Requested ? .n1 : .disabled,
            domain: .generatedArtifacts,
            canaryMaxObjectsPerSyncRun: policy.canaryMaxObjectsPerSyncRun,
            explicitInternalTestConfiguration: policy.explicitInternalTestConfiguration,
            runtimeSwitchEnabled: policy.runtimeSwitchEnabled || policy.stagePolicy.runtimeSwitchEnabled,
            allowAllEligible: policy.allowAllEligible || policy.stagePolicy.requestedStage == .allEligible,
            releaseDefaultEnabled: false
        )
    }

    nonisolated var strictN1Enabled: Bool {
        mode == .n1
            && domain == .generatedArtifacts
            && canaryMaxObjectsPerSyncRun == 1
            && explicitInternalTestConfiguration
            && !runtimeSwitchEnabled
            && !allowAllEligible
            && !releaseDefaultEnabled
    }
}

nonisolated enum CanonicalGeneratedArtifactCanaryBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedMode
    case canaryBudgetZero
    case missingInternalCanaryConfiguration
    case canaryBudgetAboveOneDenied
    case canaryStageEvidenceMissing
    case canaryStageBlocked
    case unsupportedTrigger
    case unsupportedAction
    case unsupportedKind
    case missingOwnerApproval
    case matrixBlocked
    case activePilotNotGeneratedArtifacts
    case commitExecutorUnavailable
    case peerSnapshotUnavailable
    case runtimeSwitchDenied
    case allEligibleDenied
    case defaultEnablementDenied
    case readSideParallelMissing
    case hashUnavailable
    case byteSizeUnavailable
    case unsafeLogicalPathToken
    case contentLeakRisk
    case audioConfusionRisk
    case producerAmbiguous
    case generatedArtifactUploadDenied
    case unsupportedRoute
    case rollbackCheckpointMissing
    case insufficientEvidence
    case unresolvedConflict
    case parentTombstoned
    case noRollbackCheckpoint
    case realApplyPortUnavailable
    case peerNotAuthoritative
    case alreadyAttemptedFailedCandidate
    case noEligibleCandidate
}

nonisolated enum CanonicalGeneratedArtifactCanaryCandidateSafetyKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case summaryJSONMetadataAdjacent
    case noteJSONMetadataAdjacent
    case noteMarkdownGeneratedText
    case transcriptJSONStructured
    case transcriptMarkdownFullText
    case blocked
}

nonisolated struct CanonicalGeneratedArtifactCanaryCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { cutoverCandidate.action.actionID }

    var cutoverCandidate: CanonicalGeneratedArtifactCutoverCandidate
    var objectID: String
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?
    var hashPrefix: String?

    nonisolated init(_ cutoverCandidate: CanonicalGeneratedArtifactCutoverCandidate) {
        self.cutoverCandidate = cutoverCandidate
        self.objectID = CanonicalProductionRedaction.safeIdentifier(cutoverCandidate.objectID, fallback: "unknown-recording")
        self.artifactID = cutoverCandidate.artifactID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown")
        }
        self.artifactKind = cutoverCandidate.artifactKind
        self.hashPrefix = cutoverCandidate.expectedContentHash.flatMap {
            CanonicalProductionRedaction.hashPrefix($0.value)
        }
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryCandidateSafety: Codable, Equatable, Sendable {
    var candidate: CanonicalGeneratedArtifactCanaryCandidate
    var safe: Bool
    var kind: CanonicalGeneratedArtifactCanaryCandidateSafetyKind
    var blockers: [CanonicalGeneratedArtifactCanaryBlocker]
    var generatedArtifactDownloadOnly: Bool
    var generatedArtifactUploadAttempted: Bool
    var audioUploadAttempted: Bool
    var contentLeakRisk: Bool
    var routeIsArtifactRequest: Bool
    var readSideOnly: Bool
    var uiMutated: Bool

    nonisolated init(
        candidate: CanonicalGeneratedArtifactCutoverCandidate,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        peerNode: CanonicalNode?,
        attemptedFailedActionIDs: Set<String> = [],
        contentLeakRiskObserved: Bool = false
    ) {
        var blockers = CanonicalGeneratedArtifactCanarySelector.candidateBlockers(
            candidate,
            evidence: evidence,
            peerNode: peerNode,
            attemptedFailedActionIDs: attemptedFailedActionIDs
        )
        let safetyKind: CanonicalGeneratedArtifactCanaryCandidateSafetyKind
        switch candidate.artifactKind {
        case .summaryJSON:
            safetyKind = .summaryJSONMetadataAdjacent
        case .noteJSON:
            safetyKind = .noteJSONMetadataAdjacent
        case .noteMarkdown:
            safetyKind = .noteMarkdownGeneratedText
        case .transcriptJSON:
            safetyKind = .transcriptJSONStructured
        case .transcriptMarkdown:
            safetyKind = .transcriptMarkdownFullText
        case .audio:
            blockers.append(.audioConfusionRisk)
            safetyKind = .blocked
        case .metadata, .receiveRecord, nil:
            blockers.append(.unsupportedKind)
            safetyKind = .blocked
        }
        if contentLeakRiskObserved {
            blockers.append(.contentLeakRisk)
        }
        self.candidate = CanonicalGeneratedArtifactCanaryCandidate(candidate)
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.safe = self.blockers.isEmpty
        self.kind = self.safe ? safetyKind : .blocked
        self.generatedArtifactDownloadOnly = candidate.cutoverActionKind == .generatedArtifactDownloadApply
        self.generatedArtifactUploadAttempted = candidate.cutoverActionKind != .generatedArtifactDownloadApply
        self.audioUploadAttempted = candidate.artifactKind == .audio
        self.contentLeakRisk = contentLeakRiskObserved
        self.routeIsArtifactRequest = candidate.routePath == "/sync/artifact-request"
        self.readSideOnly = true
        self.uiMutated = false
    }
}

nonisolated struct CanonicalGeneratedArtifactCanarySelectionBlocker: Codable, Equatable, Identifiable, Sendable {
    var id: String { [objectID ?? "run", artifactID ?? "artifact", reason.rawValue].joined(separator: "|") }

    var objectID: String?
    var artifactID: String?
    var reason: CanonicalGeneratedArtifactCanaryBlocker

    nonisolated init(objectID: String?, artifactID: String?, reason: CanonicalGeneratedArtifactCanaryBlocker) {
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.reason = reason
    }
}

nonisolated struct CanonicalGeneratedArtifactCanarySelectionResult: Codable, Equatable, Sendable {
    var selectedCandidates: [CanonicalGeneratedArtifactCanaryCandidate]
    var blockers: [CanonicalGeneratedArtifactCanarySelectionBlocker]
    var evaluatedCandidateCount: Int
    var noEligibleCandidate: Bool

    nonisolated var selectedCutoverCandidates: [CanonicalGeneratedArtifactCutoverCandidate] {
        selectedCandidates.map(\.cutoverCandidate)
    }
}

nonisolated struct CanonicalGeneratedArtifactCanarySelector: Sendable {
    nonisolated init() {}

    nonisolated func select(
        mode: CanonicalCutoverMode,
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        trigger: CanonicalSyncPlanTrigger,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        peerNode: CanonicalNode?,
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        attemptedFailedActionIDs: Set<String> = []
    ) -> CanonicalGeneratedArtifactCanarySelectionResult {
        var blockers: [CanonicalGeneratedArtifactCanarySelectionBlocker] = []
        let usesStagePolicy = policy.stagePolicy.requestedStage.isExecutable
        let stageGate = usesStagePolicy
            ? CanonicalGeneratedArtifactCanaryStageGate(
                policy: policy.stagePolicy,
                domain: .generatedArtifacts,
                token: nil,
                cutoverEvidence: evidence
            )
            : nil

        if mode == .disabled {
            blockers.append(.init(objectID: nil, artifactID: nil, reason: .disabled))
        }
        if mode != .canary {
            blockers.append(.init(objectID: nil, artifactID: nil, reason: .unsupportedMode))
        }
        if policy.canaryMaxObjectsPerSyncRun == 0 && !usesStagePolicy {
            blockers.append(.init(objectID: nil, artifactID: nil, reason: .canaryBudgetZero))
        }
        if policy.canaryMaxObjectsPerSyncRun > 1, !usesStagePolicy {
            blockers.append(.init(objectID: nil, artifactID: nil, reason: .canaryBudgetAboveOneDenied))
        }
        if policy.canaryMaxObjectsPerSyncRun == 1, !usesStagePolicy, !policy.allowsInternalN1Execution {
            blockers.append(.init(objectID: nil, artifactID: nil, reason: .missingInternalCanaryConfiguration))
        }
        if usesStagePolicy {
            if policy.stagePolicy.requestedStage == .allEligible && !policy.allowAllEligible {
                blockers.append(.init(objectID: nil, artifactID: nil, reason: .allEligibleDenied))
            }
        } else if policy.allowAllEligible || policy.stagePolicy.requestedStage == .allEligible {
            blockers.append(.init(objectID: nil, artifactID: nil, reason: .allEligibleDenied))
        }
        if policy.runtimeSwitchEnabled || policy.stagePolicy.runtimeSwitchEnabled {
            blockers.append(.init(objectID: nil, artifactID: nil, reason: .runtimeSwitchDenied))
        }
        if usesStagePolicy, stageGate?.allowed != true {
            blockers.append(
                .init(
                    objectID: nil,
                    artifactID: nil,
                    reason: evidence.canaryStageEvidence == nil ? .canaryStageEvidenceMissing : .canaryStageBlocked
                )
            )
        }
        if trigger == .viewRefresh || trigger == .retryDrainer {
            blockers.append(.init(objectID: nil, artifactID: nil, reason: .unsupportedTrigger))
        }

        let runBlocked = !blockers.isEmpty
        let selectionLimit = usesStagePolicy
            ? (stageGate?.selectedCandidateLimit ?? 0)
            : policy.canaryMaxObjectsPerSyncRun
        let ordered = candidates.sorted { lhs, rhs in
            let lhsPriority = Self.artifactSelectionPriority(lhs.artifactKind)
            let rhsPriority = Self.artifactSelectionPriority(rhs.artifactKind)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            if lhs.objectID != rhs.objectID {
                return lhs.objectID.localizedStandardCompare(rhs.objectID) == .orderedAscending
            }
            if (lhs.artifactKind?.rawValue ?? "") != (rhs.artifactKind?.rawValue ?? "") {
                return (lhs.artifactKind?.rawValue ?? "") < (rhs.artifactKind?.rawValue ?? "")
            }
            return lhs.action.actionID.localizedStandardCompare(rhs.action.actionID) == .orderedAscending
        }
        var selected: [CanonicalGeneratedArtifactCanaryCandidate] = []
        for candidate in ordered {
            let reasons = Self.candidateBlockers(
                candidate,
                evidence: evidence,
                peerNode: peerNode,
                attemptedFailedActionIDs: attemptedFailedActionIDs
            )
            if reasons.isEmpty, !runBlocked, selected.count < selectionLimit {
                selected.append(CanonicalGeneratedArtifactCanaryCandidate(candidate))
                continue
            }
            blockers.append(contentsOf: reasons.map {
                CanonicalGeneratedArtifactCanarySelectionBlocker(
                    objectID: candidate.objectID,
                    artifactID: candidate.artifactID,
                    reason: $0
                )
            })
        }
        if selected.isEmpty, !candidates.isEmpty, blockers.isEmpty {
            blockers.append(.init(objectID: nil, artifactID: nil, reason: .noEligibleCandidate))
        }
        return CanonicalGeneratedArtifactCanarySelectionResult(
            selectedCandidates: selected,
            blockers: blockers,
            evaluatedCandidateCount: candidates.count,
            noEligibleCandidate: selected.isEmpty
        )
    }

    nonisolated static func candidateBlockers(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        peerNode: CanonicalNode?,
        attemptedFailedActionIDs: Set<String>
    ) -> [CanonicalGeneratedArtifactCanaryBlocker] {
        var blockers: [CanonicalGeneratedArtifactCanaryBlocker] = []
        if candidate.cutoverActionKind.isExecutableApply == false {
            blockers.append(candidate.cutoverActionKind == .generatedArtifactNoOp ? .generatedArtifactUploadDenied : .unsupportedAction)
        }
        if candidate.action.kind != .generatedArtifactDownloadApply {
            blockers.append(.generatedArtifactUploadDenied)
        }
        if candidate.artifactKind == .audio {
            blockers.append(.audioConfusionRisk)
        }
        if candidate.artifactKind.map({ !CanonicalProjectionContract.generatedArtifactKinds.contains($0) }) ?? true {
            blockers.append(.unsupportedKind)
        }
        if candidate.expectedArtifact == nil {
            blockers.append(.producerAmbiguous)
        }
        if candidate.expectedContentHash == nil {
            blockers.append(.hashUnavailable)
        }
        if candidate.expectedByteSize == nil {
            blockers.append(.byteSizeUnavailable)
        }
        if candidate.expectedLogicalPathToken.flatMap(CanonicalProjectionContract.safeLogicalPathToken) == nil {
            blockers.append(.unsafeLogicalPathToken)
        }
        if candidate.unresolvedConflict {
            blockers.append(.unresolvedConflict)
        }
        if candidate.parentObjectTombstoned {
            blockers.append(.parentTombstoned)
        }
        if candidate.rollbackCheckpointID == nil || !evidence.rollbackCheckpointAvailable {
            blockers.append(.noRollbackCheckpoint)
            blockers.append(.rollbackCheckpointMissing)
        }
        if !evidence.realRootBoundApplyPortAvailable
            || !evidence.applyPortMode.isNonDryRunRootBound
            || !evidence.rootBoundWriteAvailable
            || !evidence.atomicReplaceAvailable {
            blockers.append(.realApplyPortUnavailable)
        }
        if !candidate.peerIsAuthoritative(peerNode: peerNode) {
            blockers.append(.peerNotAuthoritative)
            blockers.append(.producerAmbiguous)
        }
        if candidate.routePath != "/sync/artifact-request" {
            blockers.append(.unsupportedRoute)
        }
        if attemptedFailedActionIDs.contains(candidate.action.actionID) {
            blockers.append(.alreadyAttemptedFailedCandidate)
        }
        return Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated static func artifactSelectionPriority(_ kind: CanonicalArtifact.Kind?) -> Int {
        switch kind {
        case .summaryJSON:
            return 0
        case .noteJSON:
            return 1
        case .noteMarkdown:
            return 2
        case .transcriptJSON:
            return 3
        case .transcriptMarkdown:
            return 4
        case .audio:
            return 90
        case .metadata, .receiveRecord, nil:
            return 99
        }
    }
}

nonisolated struct CanonicalGeneratedArtifactCutoverGate: Codable, Equatable, Sendable {
    var domain: CanonicalGeneratedArtifactCutoverDomain
    var mode: CanonicalCutoverMode
    var allowed: Bool
    var failures: [CanonicalGeneratedArtifactCutoverFailure]
    var legacyFallbackAvailable: Bool
    var reason: String

    nonisolated init(
        domain: CanonicalGeneratedArtifactCutoverDomain,
        mode: CanonicalCutoverMode,
        failures: [CanonicalGeneratedArtifactCutoverFailure],
        legacyFallbackAvailable: Bool,
        reason: String
    ) {
        self.domain = domain
        self.mode = mode
        self.failures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = self.failures.isEmpty
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (self.allowed ? "allowed" : "blocked")
    }
}

nonisolated enum CanonicalGeneratedArtifactCommitFailureInjection: String, Codable, Equatable, Sendable {
    case none
    case artifactBytesMissing
    case hashMismatchBeforeApply
    case applyFailureBeforeCommit
    case applyFailureAfterPartialCommit
    case postconditionMismatch
    case rollbackFailure
    case parentTombstoned
    case producerAmbiguous
    case unsupportedKind
}

nonisolated struct CanonicalGeneratedArtifactProductionCommitResult: Codable, Equatable, Sendable {
    var actionID: String
    var objectID: String
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?
    var actionKind: CanonicalGeneratedArtifactCutoverActionKind
    var committed: Bool
    var partialCommit: Bool
    var preconditionVerified: Bool
    var postconditionVerified: Bool
    var routePath: String?
    var contentHashPrefix: String?
    var byteSize: Int64?
    var sideEffect: CanonicalProductionSideEffect?
    var sideEffects: [CanonicalProductionSideEffect]
    var failureKind: CanonicalGeneratedArtifactCutoverFailure?
    var reason: String

    nonisolated init(
        actionID: String,
        objectID: String,
        artifactID: String?,
        artifactKind: CanonicalArtifact.Kind?,
        actionKind: CanonicalGeneratedArtifactCutoverActionKind,
        committed: Bool,
        partialCommit: Bool = false,
        preconditionVerified: Bool = true,
        postconditionVerified: Bool = true,
        routePath: String? = "/sync/artifact-request",
        contentHash: CanonicalHash? = nil,
        byteSize: Int64? = nil,
        sideEffect: CanonicalProductionSideEffect? = nil,
        sideEffects: [CanonicalProductionSideEffect]? = nil,
        failureKind: CanonicalGeneratedArtifactCutoverFailure? = nil,
        reason: String
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: actionKind.rawValue)
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.artifactKind = artifactKind
        self.actionKind = actionKind
        self.committed = committed
        self.partialCommit = partialCommit
        self.preconditionVerified = preconditionVerified
        self.postconditionVerified = postconditionVerified
        self.routePath = routePath.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.contentHashPrefix = contentHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteSize = byteSize
        self.sideEffect = sideEffect
        self.sideEffects = sideEffects ?? sideEffect.map { [$0] } ?? []
        self.failureKind = failureKind
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (committed ? "committed" : "failed")
    }

    nonisolated static func success(
        candidate: CanonicalGeneratedArtifactCutoverCandidate,
        sideEffects: [CanonicalProductionSideEffect]
    ) -> CanonicalGeneratedArtifactProductionCommitResult {
        CanonicalGeneratedArtifactProductionCommitResult(
            actionID: candidate.action.actionID,
            objectID: candidate.objectID,
            artifactID: candidate.artifactID,
            artifactKind: candidate.artifactKind,
            actionKind: candidate.cutoverActionKind,
            committed: true,
            contentHash: candidate.expectedContentHash,
            byteSize: candidate.expectedByteSize,
            sideEffect: sideEffects.first,
            sideEffects: sideEffects,
            reason: "generatedArtifactApplyCommitted"
        )
    }

    nonisolated static func failure(
        candidate: CanonicalGeneratedArtifactCutoverCandidate,
        kind failureKind: CanonicalGeneratedArtifactCutoverFailure,
        partialCommit: Bool = false,
        reason: String
    ) -> CanonicalGeneratedArtifactProductionCommitResult {
        CanonicalGeneratedArtifactProductionCommitResult(
            actionID: candidate.action.actionID,
            objectID: candidate.objectID,
            artifactID: candidate.artifactID,
            artifactKind: candidate.artifactKind,
            actionKind: candidate.cutoverActionKind,
            committed: false,
            partialCommit: partialCommit,
            preconditionVerified: failureKind != .objectIDMismatch
                && failureKind != .artifactIDMismatch
                && failureKind != .expectedHashMissing
                && failureKind != .expectedByteSizeMissing
                && failureKind != .parentTombstoned
                && failureKind != .producerAmbiguous
                && failureKind != .unsupportedKind,
            postconditionVerified: failureKind != .postconditionMismatch,
            contentHash: candidate.expectedContentHash,
            byteSize: candidate.expectedByteSize,
            failureKind: failureKind,
            reason: reason
        )
    }
}

nonisolated struct CanonicalGeneratedArtifactRollbackExecutionResult: Codable, Equatable, Sendable {
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
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "generated-artifact-checkpoint")
        self.succeeded = succeeded
        self.fatal = fatal
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (succeeded ? "rollbackCompleted" : "rollbackFailed")
        self.rollbackResult = rollbackResult
    }
}

protocol CanonicalGeneratedArtifactCutoverExecutor: Sendable {
    func commitGeneratedArtifact(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate
    ) async -> CanonicalGeneratedArtifactProductionCommitResult

    func rollbackGeneratedArtifact(
        _ candidate: CanonicalGeneratedArtifactCutoverCandidate,
        reason: CanonicalGeneratedArtifactCutoverFailure
    ) async -> CanonicalGeneratedArtifactRollbackExecutionResult
}

nonisolated enum CanonicalGeneratedArtifactCutoverDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalGeneratedArtifactCutoverGateEvaluated
    case canonicalGeneratedArtifactCutoverGateBlocked
    case canonicalGeneratedArtifactCutoverGateAllowed
    case canonicalGeneratedArtifactNoCommitStarted
    case canonicalGeneratedArtifactNoCommitCompleted
    case canonicalGeneratedArtifactCommitStarted
    case canonicalGeneratedArtifactCommitCompleted
    case canonicalGeneratedArtifactCommitFailed
    case canonicalGeneratedArtifactRollbackStarted
    case canonicalGeneratedArtifactRollbackCompleted
    case canonicalGeneratedArtifactRollbackFailed
    case canonicalGeneratedArtifactCanaryStarted
    case canonicalGeneratedArtifactCanaryCompleted
    case canonicalGeneratedArtifactDuplicateLegacySuppressed
    case canonicalGeneratedArtifactLegacyFallbackUsed
    case canonicalGeneratedArtifactLegacyFallbackPreserved
    case canonicalGeneratedArtifactParentTombstoneBlocked
    case canonicalGeneratedArtifactConflictBlocked
    case canonicalGeneratedArtifactReadSideParallelEquivalent
    case canonicalGeneratedArtifactReadSideParallelDivergent
    case canonicalGeneratedArtifactUIProjectionParallelReadStarted
    case canonicalGeneratedArtifactUIProjectionParallelReadEquivalent
    case canonicalGeneratedArtifactUIProjectionParallelReadDivergent
    case canonicalGeneratedArtifactN1CanaryConfigured
    case canonicalGeneratedArtifactN1CandidateSelectionStarted
    case canonicalGeneratedArtifactN1CandidateSelected
    case canonicalGeneratedArtifactN1NoEligibleCandidate
    case canonicalGeneratedArtifactN1CandidateBlocked
    case canonicalGeneratedArtifactN1CanaryStarted
    case canonicalGeneratedArtifactN1CommitStarted
    case canonicalGeneratedArtifactN1CommitCompleted
    case canonicalGeneratedArtifactN1CommitFailed
    case canonicalGeneratedArtifactN1PostconditionVerified
    case canonicalGeneratedArtifactN1PostconditionFailed
    case canonicalGeneratedArtifactN1RollbackStarted
    case canonicalGeneratedArtifactN1RollbackCompleted
    case canonicalGeneratedArtifactN1RollbackFailed
    case canonicalGeneratedArtifactN1LegacyFallbackUsed
    case canonicalGeneratedArtifactN1DuplicateLegacySuppressed
    case canonicalGeneratedArtifactN1FatalBlocker
    case canonicalGeneratedArtifactN1ObservationRecorded
    case canonicalGeneratedArtifactN1ReadSideParallelStarted
    case canonicalGeneratedArtifactN1ReadSideParallelEquivalent
    case canonicalGeneratedArtifactN1ReadSideParallelDivergent
    case canonicalGeneratedArtifactN1MacPeerSnapshotUnavailable
    case canonicalGeneratedArtifactCanaryStageEvaluated
    case canonicalGeneratedArtifactCanaryStageBlocked
    case canonicalGeneratedArtifactCanaryStageAllowed
    case canonicalGeneratedArtifactCanaryStageStarted
    case canonicalGeneratedArtifactCanaryStageCompleted
    case canonicalGeneratedArtifactCanaryStageFailed
    case canonicalGeneratedArtifactCanaryStageObservationRecorded
    case canonicalGeneratedArtifactCanaryCandidateSkipped
    case canonicalGeneratedArtifactCanaryCandidateExecuted
    case canonicalGeneratedArtifactCanaryStoppedAfterFailure
    case canonicalGeneratedArtifactCanaryNextStageEligible
    case canonicalGeneratedArtifactCanaryNextStageBlocked
    case canonicalGeneratedArtifactCanaryAllEligibleStarted
    case canonicalGeneratedArtifactCanaryAllEligibleCompleted
    case canonicalGeneratedArtifactContentLeakBlocked
    case canonicalGeneratedArtifactUnsafePathTokenBlocked
    case canonicalGeneratedArtifactAudioConfusionBlocked
    case canonicalGeneratedArtifactUnsupportedKindBlocked
    case canonicalGeneratedArtifactProducerAmbiguousBlocked
    case canonicalGeneratedArtifactHashUnavailableBlocked
    case canonicalGeneratedArtifactByteSizeUnavailableBlocked
    case canonicalGeneratedArtifactExpandedReadSideParallelStarted
    case canonicalGeneratedArtifactExpandedReadSideParallelEquivalent
    case canonicalGeneratedArtifactExpandedReadSideParallelDivergent
}

nonisolated struct CanonicalGeneratedArtifactCutoverDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", artifactID ?? "", result ?? "", reason ?? ""].joined(separator: "|") }

    var kind: CanonicalGeneratedArtifactCutoverDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var domain: CanonicalGeneratedArtifactCutoverDomain
    var objectID: String?
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?
    var action: String?
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalGeneratedArtifactCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalGeneratedArtifactCutoverDomain = .generatedArtifacts,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil,
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
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.artifactKind = artifactKind
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
            "domain=\(domain.rawValue)",
            "objectID=\(objectID ?? "none")",
            "artifactID=\(artifactID ?? "none")",
            "artifactKind=\(artifactKind?.rawValue ?? "none")",
            "action=\(action ?? "none")",
            "result=\(result ?? "none")",
            "reason=\(reason ?? "none")",
            "hashPrefix=\(hashPrefix ?? "none")"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalGeneratedArtifactCutoverResult: Codable, Equatable, Sendable {
    var gate: CanonicalGeneratedArtifactCutoverGate
    var commits: [CanonicalGeneratedArtifactProductionCommitResult]
    var rollbackResults: [CanonicalGeneratedArtifactRollbackExecutionResult]
    var diagnostics: [CanonicalGeneratedArtifactCutoverDiagnostic]
    var legacyFallbackUsed: Bool
    var duplicateLegacySuppressedActionIDs: [String]
    var canaryAttemptedCount: Int
    var canarySucceeded: Bool
    var fatalBlocker: Bool
    var readSideProjection: CanonicalGeneratedArtifactReadSideParallelProjectionResult?
    var canaryConfiguration: CanonicalGeneratedArtifactCanaryConfiguration? = nil
    var canarySelection: CanonicalGeneratedArtifactCanarySelectionResult? = nil
    var candidateSafetyReports: [CanonicalGeneratedArtifactCanaryCandidateSafety]? = nil
    var observationReport: CanonicalGeneratedArtifactCanaryObservationReport? = nil
    var stageObservationReport: CanonicalGeneratedArtifactCanaryStageObservationReport? = nil

    nonisolated var succeeded: Bool {
        gate.allowed && !fatalBlocker && !commits.isEmpty && commits.allSatisfy { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
    }
}

nonisolated enum CanonicalGeneratedArtifactCanaryObservationStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case blocked
    case noEligibleCandidate
    case committed
    case failedRolledBack
    case fatalRollbackFailure
}

nonisolated enum CanonicalGeneratedArtifactCanaryObservationRecommendation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case stayDisabled
    case remainN1
    case readyForN3AfterAudit
    case fixBlockers
}

nonisolated struct CanonicalGeneratedArtifactCanaryObservationReport: Codable, Equatable, Sendable {
    var status: CanonicalGeneratedArtifactCanaryObservationStatus
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
    var generatedArtifactDownloadOnly: Bool
    var generatedArtifactUploadAttempted: Bool
    var audioUploadAttempted: Bool
    var contentLeakRiskObserved: Bool
    var routeIsArtifactRequest: Bool
    var uiMutated: Bool
    var fatalBlocker: Bool
    var nextRecommendation: CanonicalGeneratedArtifactCanaryObservationRecommendation
    var reason: String

    nonisolated init(
        status: CanonicalGeneratedArtifactCanaryObservationStatus,
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
        generatedArtifactDownloadOnly: Bool,
        generatedArtifactUploadAttempted: Bool,
        audioUploadAttempted: Bool,
        contentLeakRiskObserved: Bool,
        routeIsArtifactRequest: Bool,
        uiMutated: Bool,
        fatalBlocker: Bool,
        nextRecommendation: CanonicalGeneratedArtifactCanaryObservationRecommendation,
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
        self.generatedArtifactDownloadOnly = generatedArtifactDownloadOnly
        self.generatedArtifactUploadAttempted = generatedArtifactUploadAttempted
        self.audioUploadAttempted = audioUploadAttempted
        self.contentLeakRiskObserved = contentLeakRiskObserved
        self.routeIsArtifactRequest = routeIsArtifactRequest
        self.uiMutated = uiMutated
        self.fatalBlocker = fatalBlocker
        self.nextRecommendation = nextRecommendation
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? status.rawValue
    }
}

nonisolated enum CanonicalGeneratedArtifactCanaryStageRecommendation: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case stayDisabled
    case observeCurrentStage
    case advanceToN10
    case advanceToAllEligible
    case holdForInvestigation
    case stopForFatalBlocker
}

nonisolated struct CanonicalGeneratedArtifactCanaryStageSummary: Codable, Equatable, Sendable {
    var stage: CanonicalGeneratedArtifactCanaryStage
    var budget: Int
    var selectedCount: Int
    var executedCount: Int
    var successCount: Int
    var failureCount: Int

    nonisolated init(
        stage: CanonicalGeneratedArtifactCanaryStage,
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

nonisolated struct CanonicalGeneratedArtifactCanaryStageFailure: Codable, Equatable, Identifiable, Sendable {
    var id: String { [objectID ?? "run", artifactID ?? "artifact", blocker.rawValue].joined(separator: "|") }
    var objectID: String?
    var artifactID: String?
    var blocker: CanonicalGeneratedArtifactCanaryBlocker

    nonisolated init(
        objectID: String?,
        artifactID: String?,
        blocker: CanonicalGeneratedArtifactCanaryBlocker
    ) {
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.blocker = blocker
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryStageObservationReport: Codable, Equatable, Sendable {
    var stage: CanonicalGeneratedArtifactCanaryStage
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
    var contentLeakRiskCount: Int
    var unsafePathTokenCount: Int
    var parentTombstoneBlockCount: Int
    var audioConfusionBlockCount: Int
    var fatalBlockerCount: Int
    var readSideParallelEquivalentCount: Int
    var readSideParallelDivergentCount: Int
    var nextStageEligible: Bool
    var nextStageBlockers: [CanonicalGeneratedArtifactCutoverFailure]
    var runtimeSwitch: Bool
    var domain: CanonicalMigrationDomain
    var uiMutated: Bool
    var artifactUploadJobCreated: Bool
    var audioAutoDownloaded: Bool
    var recommendation: CanonicalGeneratedArtifactCanaryStageRecommendation
    var summary: CanonicalGeneratedArtifactCanaryStageSummary
    var failures: [CanonicalGeneratedArtifactCanaryStageFailure]
    var evidenceReport: CanonicalGeneratedArtifactStageEvidenceReport
    var redacted: Bool

    nonisolated init(
        stage: CanonicalGeneratedArtifactCanaryStage,
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
        contentLeakRiskCount: Int,
        unsafePathTokenCount: Int,
        parentTombstoneBlockCount: Int,
        audioConfusionBlockCount: Int,
        fatalBlockerCount: Int,
        readSideParallelEquivalentCount: Int,
        readSideParallelDivergentCount: Int,
        nextStageEligible: Bool,
        nextStageBlockers: [CanonicalGeneratedArtifactCutoverFailure],
        recommendation: CanonicalGeneratedArtifactCanaryStageRecommendation,
        runtimeSwitch: Bool,
        failures: [CanonicalGeneratedArtifactCanaryStageFailure],
        evidenceReport: CanonicalGeneratedArtifactStageEvidenceReport,
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
        self.contentLeakRiskCount = max(0, contentLeakRiskCount)
        self.unsafePathTokenCount = max(0, unsafePathTokenCount)
        self.parentTombstoneBlockCount = max(0, parentTombstoneBlockCount)
        self.audioConfusionBlockCount = max(0, audioConfusionBlockCount)
        self.fatalBlockerCount = max(0, fatalBlockerCount)
        self.readSideParallelEquivalentCount = max(0, readSideParallelEquivalentCount)
        self.readSideParallelDivergentCount = max(0, readSideParallelDivergentCount)
        self.nextStageEligible = nextStageEligible
        self.nextStageBlockers = Array(Set(nextStageBlockers)).sorted { $0.rawValue < $1.rawValue }
        self.runtimeSwitch = runtimeSwitch
        self.domain = .generatedArtifacts
        self.uiMutated = false
        self.artifactUploadJobCreated = false
        self.audioAutoDownloaded = false
        self.recommendation = recommendation
        self.summary = CanonicalGeneratedArtifactCanaryStageSummary(
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
            "contentLeakRisk=\(contentLeakRiskCount)",
            "unsafePathToken=\(unsafePathTokenCount)",
            "parentTombstone=\(parentTombstoneBlockCount)",
            "audioConfusion=\(audioConfusionBlockCount)",
            "nextStageEligible=\(nextStageEligible)",
            "blockers=\(nextStageBlockers.map(\.rawValue).joined(separator: "|"))",
            "runtimeSwitch=\(runtimeSwitch)",
            "domain=\(domain.rawValue)",
            "uiMutated=\(uiMutated)",
            "artifactUploadJobCreated=\(artifactUploadJobCreated)",
            "audioAutoDownloaded=\(audioAutoDownloaded)",
            "redacted=\(redacted)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryResult: Codable, Equatable, Sendable {
    var configuration: CanonicalGeneratedArtifactCanaryConfiguration
    var cutoverResult: CanonicalGeneratedArtifactCutoverResult
    var selection: CanonicalGeneratedArtifactCanarySelectionResult
    var observationReport: CanonicalGeneratedArtifactCanaryObservationReport

    nonisolated var succeeded: Bool {
        cutoverResult.succeeded
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryStageResult: Codable, Equatable, Sendable {
    var cutoverResult: CanonicalGeneratedArtifactCutoverResult
    var selection: CanonicalGeneratedArtifactCanarySelectionResult
    var stageObservationReport: CanonicalGeneratedArtifactCanaryStageObservationReport

    nonisolated var succeeded: Bool {
        cutoverResult.succeeded
    }
}

nonisolated struct CanonicalGeneratedArtifactCutoverRunner: Sendable {
    nonisolated init() {}

    nonisolated func evaluateGate(
        mode: CanonicalCutoverMode,
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        peerNode: CanonicalNode?,
        trigger: CanonicalSyncPlanTrigger
    ) -> CanonicalGeneratedArtifactCutoverGate {
        var failures: [CanonicalGeneratedArtifactCutoverFailure] = []
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
        if evidence.rollbackPlan?.covers(domain: .generatedArtifacts) != true {
            failures.append(.missingRollback)
        }
        if !evidence.noCommitEvidenceAvailable {
            failures.append(.missingNoCommitEvidence)
        }
        if !evidence.dryRunEquivalenceVerified {
            failures.append(.missingDryRunEquivalence)
        }
        if !evidence.executionShadowVerified {
            failures.append(.missingExecutionShadowEvidence)
        }
        if !evidence.realDataShadowCopyVerified {
            failures.append(.missingRealDataShadowCopyEvidence)
        }
        if !evidence.noBlockingDivergence {
            failures.append(.blockingDivergence)
        }
        if !evidence.noUnresolvedConflict || candidates.contains(where: \.unresolvedConflict) {
            failures.append(.unresolvedConflict)
        }
        if !evidence.artifactRequestRouteEvidenceAvailable {
            failures.append(.missingArtifactRequestRouteEvidence)
        }
        if !evidence.productionPortAvailable {
            failures.append(.productionPortUnavailable)
        }
        if !evidence.realRootBoundApplyPortAvailable || !evidence.applyPortMode.isNonDryRunRootBound {
            failures.append(evidence.applyPortMode == .disabled || evidence.applyPortMode == .dryRun ? .applyPortDryRunOnly : .rootBoundWriteUnavailable)
        }
        if !evidence.rootBoundWriteAvailable {
            failures.append(.rootBoundWriteUnavailable)
        }
        if !evidence.atomicReplaceAvailable {
            failures.append(.atomicReplaceUnavailable)
        }
        if !evidence.rollbackCheckpointAvailable {
            failures.append(.rollbackCheckpointUnavailable)
        }
        if !evidence.rollbackVerified {
            failures.append(.rollbackVerificationMissing)
        }
        if !evidence.productionRootDisabledByDefault {
            failures.append(.productionRootEnabledByDefault)
        }
        if !evidence.testRootUsed && evidence.applyPortMode == .testRootBound {
            failures.append(.testRootMissing)
        }
        if !evidence.legacyFallbackAvailable {
            failures.append(.legacyFallbackUnavailable)
        }
        if !evidence.rollbackRehearsalPassed {
            failures.append(.missingRollback)
        }
        if trigger == .viewRefresh || trigger == .retryDrainer {
            failures.append(.unsupportedMode)
        }
        if candidates.contains(where: { !$0.cutoverActionKind.isExecutableApply }) {
            failures.append(.unsupportedAction)
        }
        if candidates.contains(where: { $0.artifactKind.map { !CanonicalProjectionContract.generatedArtifactKinds.contains($0) } ?? true }) {
            failures.append(.unsupportedKind)
        }
        if candidates.contains(where: \.parentObjectTombstoned) {
            failures.append(.parentTombstoned)
        }
        if candidates.contains(where: { !$0.peerIsAuthoritative(peerNode: peerNode) }) {
            failures.append(.peerNotAuthoritative)
        }
        if candidates.contains(where: { $0.expectedContentHash == nil }) {
            failures.append(.expectedHashMissing)
        }
        if candidates.contains(where: { $0.expectedByteSize == nil }) {
            failures.append(.expectedByteSizeMissing)
        }
        if mode == .canary {
            if policy.stagePolicy.requestedStage.isExecutable {
                let stageGate = CanonicalGeneratedArtifactCanaryStageGate(
                    policy: policy.stagePolicy,
                    domain: .generatedArtifacts,
                    token: token,
                    cutoverEvidence: evidence
                )
                if !stageGate.allowed {
                    failures.append(contentsOf: stageGate.blockers.map(Self.cutoverFailure(for:)))
                }
            } else {
                if policy.canaryMaxObjectsPerSyncRun > 1 {
                    failures.append(.canaryBudgetAboveOneDenied)
                }
                if policy.canaryMaxObjectsPerSyncRun == 1, !policy.allowsInternalN1Execution {
                    failures.append(.missingInternalCanaryConfiguration)
                }
            }
        }
        return CanonicalGeneratedArtifactCutoverGate(
            domain: .generatedArtifacts,
            mode: mode,
            failures: failures,
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            reason: failures.isEmpty ? "generatedArtifactCutoverGateAllowed" : "generatedArtifactCutoverGateBlocked"
        )
    }

    func run(
        mode: CanonicalCutoverMode,
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        peerNode: CanonicalNode?,
        executor: any CanonicalGeneratedArtifactCutoverExecutor
    ) async -> CanonicalGeneratedArtifactCutoverResult {
        let gate = evaluateGate(
            mode: mode,
            policy: policy,
            token: token,
            evidence: evidence,
            candidates: candidates,
            peerNode: peerNode,
            trigger: trigger
        )
        let syncRunID = token?.syncRunID
        var diagnostics: [CanonicalGeneratedArtifactCutoverDiagnostic] = [
            diagnostic(.canonicalGeneratedArtifactCutoverGateEvaluated, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: gate.allowed ? "allowed" : "blocked", reason: gate.reason)
        ]
        guard gate.allowed else {
            diagnostics.append(diagnostic(.canonicalGeneratedArtifactCutoverGateBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: gate.failures.map(\.rawValue).joined(separator: ",")))
            if gate.failures.contains(.parentTombstoned) {
                diagnostics.append(diagnostic(.canonicalGeneratedArtifactParentTombstoneBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: "parentTombstoned"))
            }
            if gate.failures.contains(.unresolvedConflict) {
                diagnostics.append(diagnostic(.canonicalGeneratedArtifactConflictBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: "unresolvedConflict"))
            }
            if evidence.legacyFallbackAvailable {
                diagnostics.append(diagnostic(.canonicalGeneratedArtifactLegacyFallbackUsed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "legacyFallback", reason: "cutoverGateBlocked"))
                diagnostics.append(diagnostic(.canonicalGeneratedArtifactLegacyFallbackPreserved, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "legacyFallbackPreserved", reason: "cutoverGateBlocked"))
            }
            return CanonicalGeneratedArtifactCutoverResult(
                gate: gate,
                commits: [],
                rollbackResults: [],
                diagnostics: diagnostics,
                legacyFallbackUsed: evidence.legacyFallbackAvailable,
                duplicateLegacySuppressedActionIDs: [],
                canaryAttemptedCount: 0,
                canarySucceeded: false,
                fatalBlocker: false,
                readSideProjection: nil
            )
        }
        diagnostics.append(diagnostic(.canonicalGeneratedArtifactCutoverGateAllowed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "allowed", reason: "allGeneratedArtifactEvidencePresent"))
        let selection = mode == .canary
            ? CanonicalGeneratedArtifactCanarySelector().select(
                mode: mode,
                policy: policy,
                trigger: trigger,
                evidence: evidence,
                peerNode: peerNode,
                candidates: candidates
            )
            : CanonicalGeneratedArtifactCanarySelectionResult(
                selectedCandidates: candidates.map(CanonicalGeneratedArtifactCanaryCandidate.init),
                blockers: [],
                evaluatedCandidateCount: candidates.count,
                noEligibleCandidate: candidates.isEmpty
            )
        let selected = selection.selectedCutoverCandidates
        diagnostics.append(diagnostic(.canonicalGeneratedArtifactCanaryStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "started", reason: "selected=\(selected.count)"))

        var commits: [CanonicalGeneratedArtifactProductionCommitResult] = []
        var rollbacks: [CanonicalGeneratedArtifactRollbackExecutionResult] = []
        var duplicateSuppressed: [String] = []
        var legacyFallbackUsed = selected.isEmpty
        var fatalBlocker = false

        for candidate in selected {
            diagnostics.append(diagnostic(.canonicalGeneratedArtifactCommitStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, artifactID: candidate.artifactID, artifactKind: candidate.artifactKind, action: candidate.action.kind.rawValue, result: "started", reason: "generatedArtifactsOnly", hash: candidate.expectedContentHash))
            let commit = await executor.commitGeneratedArtifact(candidate)
            commits.append(commit)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                diagnostics.append(diagnostic(.canonicalGeneratedArtifactCommitCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, artifactID: candidate.artifactID, artifactKind: candidate.artifactKind, action: candidate.action.kind.rawValue, result: "committed", reason: commit.reason, hash: candidate.expectedContentHash))
                duplicateSuppressed.append(candidate.action.actionID)
                diagnostics.append(diagnostic(.canonicalGeneratedArtifactDuplicateLegacySuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, artifactID: candidate.artifactID, artifactKind: candidate.artifactKind, action: candidate.action.kind.rawValue, result: "suppressed", reason: "canonicalCommitSucceeded", hash: candidate.expectedContentHash))
                continue
            }

            let failure = commit.failureKind ?? .postconditionMismatch
            diagnostics.append(diagnostic(.canonicalGeneratedArtifactCommitFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, artifactID: candidate.artifactID, artifactKind: candidate.artifactKind, action: candidate.action.kind.rawValue, result: "failed", reason: failure.rawValue, hash: candidate.expectedContentHash))
            diagnostics.append(diagnostic(.canonicalGeneratedArtifactRollbackStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, artifactID: candidate.artifactID, artifactKind: candidate.artifactKind, action: candidate.action.kind.rawValue, result: "started", reason: failure.rawValue))
            let rollback = await executor.rollbackGeneratedArtifact(candidate, reason: failure)
            rollbacks.append(rollback)
            legacyFallbackUsed = true
            if rollback.succeeded {
                diagnostics.append(diagnostic(.canonicalGeneratedArtifactRollbackCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, artifactID: candidate.artifactID, artifactKind: candidate.artifactKind, action: candidate.action.kind.rawValue, result: "completed", reason: rollback.reason))
                diagnostics.append(diagnostic(.canonicalGeneratedArtifactLegacyFallbackUsed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, artifactID: candidate.artifactID, artifactKind: candidate.artifactKind, action: candidate.action.kind.rawValue, result: "legacyFallback", reason: failure.rawValue))
            } else {
                fatalBlocker = true
                diagnostics.append(diagnostic(.canonicalGeneratedArtifactRollbackFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, artifactID: candidate.artifactID, artifactKind: candidate.artifactKind, action: candidate.action.kind.rawValue, result: "failed", reason: rollback.reason))
                break
            }
        }
        diagnostics.append(diagnostic(.canonicalGeneratedArtifactCanaryCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: fatalBlocker ? "fatalBlocker" : "completed", reason: "attempted=\(selected.count)"))
        let projection = CanonicalGeneratedArtifactReadSideParallelProjectionResult(
            objectID: selected.first?.objectID ?? candidates.first?.objectID ?? "generated-artifact-run",
            artifactID: selected.first?.artifactID ?? candidates.first?.artifactID,
            artifactKind: selected.first?.artifactKind ?? candidates.first?.artifactKind,
            equivalent: evidence.readSideParallelEquivalent,
            canonicalHash: selected.first?.expectedContentHash ?? candidates.first?.expectedContentHash,
            legacyHash: evidence.readSideParallelEquivalent ? (selected.first?.expectedContentHash ?? candidates.first?.expectedContentHash) : nil,
            canonicalByteSize: selected.first?.expectedByteSize ?? candidates.first?.expectedByteSize,
            legacyByteSize: evidence.readSideParallelEquivalent ? (selected.first?.expectedByteSize ?? candidates.first?.expectedByteSize) : nil,
            reason: evidence.readSideParallelEquivalent ? "generatedArtifactReadSideParallelEquivalent" : "generatedArtifactReadSideParallelDivergent"
        )
        diagnostics.append(diagnostic(.canonicalGeneratedArtifactUIProjectionParallelReadStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: projection.objectID, artifactID: projection.artifactID, artifactKind: projection.artifactKind, result: "started", reason: "mutatedUI=false"))
        diagnostics.append(diagnostic(evidence.readSideParallelEquivalent ? .canonicalGeneratedArtifactReadSideParallelEquivalent : .canonicalGeneratedArtifactReadSideParallelDivergent, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: projection.objectID, artifactID: projection.artifactID, artifactKind: projection.artifactKind, result: evidence.readSideParallelEquivalent ? "equivalent" : "divergent", reason: "mutatedUI=false", hash: selected.first?.expectedContentHash ?? candidates.first?.expectedContentHash))
        diagnostics.append(diagnostic(evidence.readSideParallelEquivalent ? .canonicalGeneratedArtifactUIProjectionParallelReadEquivalent : .canonicalGeneratedArtifactUIProjectionParallelReadDivergent, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: projection.objectID, artifactID: projection.artifactID, artifactKind: projection.artifactKind, result: evidence.readSideParallelEquivalent ? "equivalent" : "divergent", reason: "mutatedUI=false", hash: selected.first?.expectedContentHash ?? candidates.first?.expectedContentHash))
        return CanonicalGeneratedArtifactCutoverResult(
            gate: gate,
            commits: commits,
            rollbackResults: rollbacks,
            diagnostics: diagnostics,
            legacyFallbackUsed: legacyFallbackUsed,
            duplicateLegacySuppressedActionIDs: Array(Set(duplicateSuppressed)).sorted(),
            canaryAttemptedCount: selected.count,
            canarySucceeded: !selected.isEmpty && !fatalBlocker && commits.allSatisfy { $0.committed && $0.preconditionVerified && $0.postconditionVerified },
            fatalBlocker: fatalBlocker,
            readSideProjection: projection
        )
    }

    nonisolated static func cutoverFailure(
        for blocker: CanonicalGeneratedArtifactStageEvidenceBlocker
    ) -> CanonicalGeneratedArtifactCutoverFailure {
        switch blocker {
        case .stageDisabled, .candidateExecutionNotApproved:
            return .unsupportedMode
        case .unsupportedDomain:
            return .unsupportedDomain
        case .runtimeSwitchEnabled:
            return .runtimeSwitchDenied
        case .previousStageEvidenceMissing:
            return .missingCanaryStageEvidence
        case .stageOrderViolation:
            return .canaryStageOrderViolation
        case .previousStageInsufficientSuccess:
            return .canaryStageBlocked
        case .previousStageFailure:
            return .previousStageFailure
        case .previousStageRollbackFailure:
            return .previousStageRollbackFailure
        case .previousStageBlockingDivergence:
            return .blockingDivergence
        case .previousStageUnresolvedConflict:
            return .unresolvedConflict
        case .previousStagePostconditionFailure:
            return .postconditionMismatch
        case .previousStageUnsupportedArtifact:
            return .unsupportedKind
        case .previousStageContentLeakRisk:
            return .contentLeakRisk
        case .previousStageUnsafePathToken:
            return .unsafePathToken
        case .previousStageParentTombstone:
            return .parentTombstoned
        case .previousStageAudioConfusion:
            return .audioConfusionRisk
        case .previousStageHashUnavailable:
            return .hashUnavailable
        case .previousStageByteSizeUnavailable:
            return .byteSizeUnavailable
        case .observationWindowIncomplete:
            return .observationWindowIncomplete
        case .noCommitEvidenceMissing:
            return .missingNoCommitEvidence
        case .ownerApprovalMissing:
            return .missingOwnerApproval
        case .rollbackPlanMissing:
            return .missingRollback
        case .dryRunEquivalenceMissing:
            return .missingDryRunEquivalence
        case .executionShadowMissing:
            return .missingExecutionShadowEvidence
        case .realDataShadowCopyMissing:
            return .missingRealDataShadowCopyEvidence
        case .readOnlyTransportProbeMissing:
            return .missingArtifactRequestRouteEvidence
        case .productionApplyPortUnavailable:
            return .productionPortUnavailable
        case .artifactRequestRouteEvidenceMissing:
            return .missingArtifactRequestRouteEvidence
        case .legacyFallbackUnavailable:
            return .legacyFallbackUnavailable
        case .readSideParallelDivergent:
            return .missingReadSideParallelEvidence
        }
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalGeneratedArtifactCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil,
        action: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalGeneratedArtifactCutoverDiagnostic {
        CanonicalGeneratedArtifactCutoverDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            objectID: objectID,
            artifactID: artifactID,
            artifactKind: artifactKind,
            action: action,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}

nonisolated struct CanonicalGeneratedArtifactN1CanaryRunner: Sendable {
    nonisolated init() {}

    nonisolated func run(
        configuration: CanonicalGeneratedArtifactCanaryConfiguration,
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix = .v822GeneratedArtifactsActivePilot(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        ),
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        localSnapshotAvailable: Bool = true,
        peerSnapshotAvailable: Bool = true,
        peerNode: CanonicalNode?,
        executor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    ) async -> CanonicalGeneratedArtifactCanaryResult {
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
            CanonicalGeneratedArtifactCanaryCandidateSafety(
                candidate: $0,
                evidence: evidence,
                peerNode: peerNode
            )
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
        let selectorPolicy = CanonicalGeneratedArtifactCanaryPolicy(
            canaryMaxObjectsPerSyncRun: 1,
            allowsInternalN1Execution: true,
            explicitInternalTestConfiguration: true
        )
        var selection = CanonicalGeneratedArtifactCanarySelector().select(
            mode: .canary,
            policy: selectorPolicy,
            trigger: trigger,
            evidence: evidence,
            peerNode: peerNode,
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
                status: .blocked,
                reason: strictFailures.map(\.rawValue).joined(separator: ",")
            )
        }
        guard let selected = selection.selectedCutoverCandidates.first else {
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
                status: .blocked,
                reason: "commitExecutorUnavailable"
            )
        }

        diagnostics.append(
            Self.diagnostic(
                .canonicalGeneratedArtifactN1CanaryStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                objectID: selected.objectID,
                artifactID: selected.artifactID,
                artifactKind: selected.artifactKind,
                action: selected.cutoverActionKind.rawValue,
                result: "started",
                reason: "n=1"
            )
        )
        diagnostics.append(
            Self.diagnostic(
                .canonicalGeneratedArtifactN1CommitStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                objectID: selected.objectID,
                artifactID: selected.artifactID,
                artifactKind: selected.artifactKind,
                action: selected.cutoverActionKind.rawValue,
                result: "started",
                hash: selected.expectedContentHash
            )
        )
        var cutoverResult = await CanonicalGeneratedArtifactCutoverRunner().run(
            mode: .canary,
            policy: selectorPolicy,
            token: token,
            evidence: evidence,
            candidates: [selected],
            trigger: trigger,
            nodeRole: nodeRole,
            peerNode: peerNode,
            executor: executor
        )
        if let commit = cutoverResult.commits.first {
            diagnostics.append(
                Self.diagnostic(
                    commit.committed ? .canonicalGeneratedArtifactN1CommitCompleted : .canonicalGeneratedArtifactN1CommitFailed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: selected.objectID,
                    artifactID: selected.artifactID,
                    artifactKind: selected.artifactKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: commit.committed ? "committed" : "failed",
                    reason: commit.failureKind?.rawValue ?? commit.reason,
                    hash: selected.expectedContentHash
                )
            )
            diagnostics.append(
                Self.diagnostic(
                    commit.postconditionVerified ? .canonicalGeneratedArtifactN1PostconditionVerified : .canonicalGeneratedArtifactN1PostconditionFailed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: selected.objectID,
                    artifactID: selected.artifactID,
                    artifactKind: selected.artifactKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: commit.postconditionVerified ? "verified" : "failed",
                    hash: selected.expectedContentHash
                )
            )
        }
        for rollback in cutoverResult.rollbackResults {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalGeneratedArtifactN1RollbackStarted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: selected.objectID,
                    artifactID: selected.artifactID,
                    artifactKind: selected.artifactKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: "started",
                    reason: rollback.checkpointID
                )
            )
            diagnostics.append(
                Self.diagnostic(
                    rollback.succeeded ? .canonicalGeneratedArtifactN1RollbackCompleted : .canonicalGeneratedArtifactN1RollbackFailed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: selected.objectID,
                    artifactID: selected.artifactID,
                    artifactKind: selected.artifactKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: rollback.succeeded ? "rolledBack" : "rollbackFailed",
                    reason: rollback.reason
                )
            )
        }
        if cutoverResult.legacyFallbackUsed {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalGeneratedArtifactN1LegacyFallbackUsed,
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
                    .canonicalGeneratedArtifactN1DuplicateLegacySuppressed,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: selected.objectID,
                    artifactID: selected.artifactID,
                    artifactKind: selected.artifactKind,
                    action: selected.cutoverActionKind.rawValue,
                    result: "successOnly",
                    reason: "legacyDuplicateSuppressionCandidate"
                )
            )
        }
        if let readSide = cutoverResult.readSideProjection {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalGeneratedArtifactN1ReadSideParallelStarted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: readSide.objectID,
                    artifactID: readSide.artifactID,
                    artifactKind: readSide.artifactKind,
                    result: "started"
                )
            )
            diagnostics.append(
                Self.diagnostic(
                    readSide.equivalent ? .canonicalGeneratedArtifactN1ReadSideParallelEquivalent : .canonicalGeneratedArtifactN1ReadSideParallelDivergent,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: readSide.objectID,
                    artifactID: readSide.artifactID,
                    artifactKind: readSide.artifactKind,
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
                .canonicalGeneratedArtifactN1ObservationRecorded,
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
                    .canonicalGeneratedArtifactN1FatalBlocker,
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
        return CanonicalGeneratedArtifactCanaryResult(
            configuration: configuration,
            cutoverResult: cutoverResult,
            selection: selection,
            observationReport: observation
        )
    }

    private nonisolated static func strictConfigurationFailures(
        configuration: CanonicalGeneratedArtifactCanaryConfiguration,
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix,
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        executorAvailable: Bool
    ) -> [CanonicalGeneratedArtifactCutoverFailure] {
        var failures: [CanonicalGeneratedArtifactCutoverFailure] = []
        if configuration.mode == .disabled {
            failures.append(.disabled)
        }
        if configuration.mode != .n1 {
            failures.append(.unsupportedMode)
        }
        if configuration.domain != .generatedArtifacts {
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
        if !configuration.explicitInternalTestConfiguration
            || !policy.explicitInternalTestConfiguration
            || !policy.allowsInternalN1Execution {
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
        if matrixReport.activePilotDomain != .generatedArtifacts {
            failures.append(.activePilotNotGeneratedArtifacts)
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
        if !evidence.artifactRequestRouteEvidenceAvailable { failures.append(.missingArtifactRequestRouteEvidence) }
        if !evidence.productionPortAvailable { failures.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { failures.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { failures.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { failures.append(.rollbackCheckpointUnavailable) }
        if configuration.rollbackPlanRequired && evidence.rollbackPlan?.covers(domain: .generatedArtifacts) != true {
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
        configuration: CanonicalGeneratedArtifactCanaryConfiguration,
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        candidateCount: Int,
        failures: [CanonicalGeneratedArtifactCutoverFailure]
    ) -> [CanonicalGeneratedArtifactCutoverDiagnostic] {
        [
            diagnostic(
                .canonicalGeneratedArtifactN1CanaryConfigured,
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
                .canonicalGeneratedArtifactN1CandidateSelectionStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "started",
                reason: "candidateCount=\(candidateCount)"
            )
        ]
    }

    private nonisolated static func selectionDiagnostics(
        selection: CanonicalGeneratedArtifactCanarySelectionResult,
        safetyReports: [CanonicalGeneratedArtifactCanaryCandidateSafety],
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> [CanonicalGeneratedArtifactCutoverDiagnostic] {
        var diagnostics: [CanonicalGeneratedArtifactCutoverDiagnostic] = []
        for selected in selection.selectedCandidates {
            diagnostics.append(
                diagnostic(
                    .canonicalGeneratedArtifactN1CandidateSelected,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: selected.objectID,
                    artifactID: selected.artifactID,
                    artifactKind: selected.artifactKind,
                    action: selected.cutoverCandidate.cutoverActionKind.rawValue,
                    result: "selected",
                    reason: "route=/sync/artifact-request;n=1",
                    hash: selected.cutoverCandidate.expectedContentHash
                )
            )
        }
        for report in safetyReports where !report.safe {
            diagnostics.append(
                diagnostic(
                    .canonicalGeneratedArtifactN1CandidateBlocked,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: report.candidate.objectID,
                    artifactID: report.candidate.artifactID,
                    artifactKind: report.candidate.artifactKind,
                    action: report.candidate.cutoverCandidate.cutoverActionKind.rawValue,
                    result: "blocked",
                    reason: report.blockers.map(\.rawValue).joined(separator: ","),
                    hash: report.candidate.cutoverCandidate.expectedContentHash
                )
            )
        }
        if selection.selectedCandidates.isEmpty {
            diagnostics.append(
                diagnostic(
                    .canonicalGeneratedArtifactN1NoEligibleCandidate,
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
        _ selection: CanonicalGeneratedArtifactCanarySelectionResult,
        failures: [CanonicalGeneratedArtifactCutoverFailure],
        evaluatedCandidateCount: Int
    ) -> CanonicalGeneratedArtifactCanarySelectionResult {
        let runBlockers = failures.map {
            CanonicalGeneratedArtifactCanarySelectionBlocker(
                objectID: nil,
                artifactID: nil,
                reason: blocker(for: $0)
            )
        }
        return CanonicalGeneratedArtifactCanarySelectionResult(
            selectedCandidates: [],
            blockers: selection.blockers + runBlockers,
            evaluatedCandidateCount: evaluatedCandidateCount,
            noEligibleCandidate: true
        )
    }

    private nonisolated static func blocker(
        for failure: CanonicalGeneratedArtifactCutoverFailure
    ) -> CanonicalGeneratedArtifactCanaryBlocker {
        switch failure {
        case .missingOwnerApproval, .missingToken:
            return .missingOwnerApproval
        case .matrixValidationBlocked:
            return .matrixBlocked
        case .activePilotNotGeneratedArtifacts:
            return .activePilotNotGeneratedArtifacts
        case .commitExecutorUnavailable:
            return .commitExecutorUnavailable
        case .peerSnapshotUnavailable, .peerUnknown:
            return .peerSnapshotUnavailable
        case .runtimeSwitchDenied:
            return .runtimeSwitchDenied
        case .allEligibleCanaryDenied, .canaryBudgetAboveOneDenied:
            return .allEligibleDenied
        case .defaultEnablementDenied:
            return .defaultEnablementDenied
        case .missingReadSideParallelEvidence:
            return .readSideParallelMissing
        case .expectedHashMissing:
            return .hashUnavailable
        case .expectedByteSizeMissing:
            return .byteSizeUnavailable
        case .producerAmbiguous:
            return .producerAmbiguous
        case .missingArtifactRequestRouteEvidence:
            return .unsupportedRoute
        case .rollbackCheckpointUnavailable:
            return .rollbackCheckpointMissing
        case .parentTombstoned:
            return .parentTombstoned
        case .unresolvedConflict:
            return .unresolvedConflict
        default:
            return .insufficientEvidence
        }
    }

    private nonisolated static func blockedResult(
        configuration: CanonicalGeneratedArtifactCanaryConfiguration,
        selection: CanonicalGeneratedArtifactCanarySelectionResult,
        safetyReports: [CanonicalGeneratedArtifactCanaryCandidateSafety],
        diagnostics: [CanonicalGeneratedArtifactCutoverDiagnostic],
        failures: [CanonicalGeneratedArtifactCutoverFailure],
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        status: CanonicalGeneratedArtifactCanaryObservationStatus,
        reason: String
    ) -> CanonicalGeneratedArtifactCanaryResult {
        let gate = CanonicalGeneratedArtifactCutoverGate(
            domain: .generatedArtifacts,
            mode: configuration.mode.isExecutable ? .canary : .disabled,
            failures: failures,
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            reason: reason
        )
        var diagnostics = diagnostics
        if failures.contains(.peerSnapshotUnavailable), nodeRole == .mac {
            diagnostics.append(
                diagnostic(
                    .canonicalGeneratedArtifactN1MacPeerSnapshotUnavailable,
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
                    .canonicalGeneratedArtifactN1FatalBlocker,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: reason
                )
            )
        }
        let observation = CanonicalGeneratedArtifactCanaryObservationReport(
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
            generatedArtifactDownloadOnly: safetyReports.allSatisfy(\.generatedArtifactDownloadOnly),
            generatedArtifactUploadAttempted: safetyReports.contains(where: \.generatedArtifactUploadAttempted),
            audioUploadAttempted: safetyReports.contains(where: \.audioUploadAttempted),
            contentLeakRiskObserved: safetyReports.contains(where: \.contentLeakRisk),
            routeIsArtifactRequest: safetyReports.allSatisfy(\.routeIsArtifactRequest),
            uiMutated: false,
            fatalBlocker: status != .noEligibleCandidate,
            nextRecommendation: status == .noEligibleCandidate ? .remainN1 : .fixBlockers,
            reason: reason
        )
        diagnostics.append(
            diagnostic(
                .canonicalGeneratedArtifactN1ObservationRecorded,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: observation.status.rawValue,
                reason: observation.reason
            )
        )
        let cutoverResult = CanonicalGeneratedArtifactCutoverResult(
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
        return CanonicalGeneratedArtifactCanaryResult(
            configuration: configuration,
            cutoverResult: cutoverResult,
            selection: selection,
            observationReport: observation
        )
    }

    private nonisolated static func observation(
        syncRunID: String?,
        nodeRole: CanonicalProductionExecutionDomainRole,
        selection: CanonicalGeneratedArtifactCanarySelectionResult,
        safetyReports: [CanonicalGeneratedArtifactCanaryCandidateSafety],
        cutoverResult: CanonicalGeneratedArtifactCutoverResult,
        evidence: CanonicalGeneratedArtifactCutoverEvidence
    ) -> CanonicalGeneratedArtifactCanaryObservationReport {
        let successful = cutoverResult.commits.filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
        let status: CanonicalGeneratedArtifactCanaryObservationStatus
        if cutoverResult.fatalBlocker {
            status = .fatalRollbackFailure
        } else if !successful.isEmpty {
            status = .committed
        } else if !cutoverResult.rollbackResults.isEmpty {
            status = .failedRolledBack
        } else {
            status = .blocked
        }
        let recommendation: CanonicalGeneratedArtifactCanaryObservationRecommendation
        switch status {
        case .committed:
            recommendation = .readyForN3AfterAudit
        case .failedRolledBack, .blocked, .fatalRollbackFailure:
            recommendation = .fixBlockers
        case .noEligibleCandidate:
            recommendation = .remainN1
        }
        return CanonicalGeneratedArtifactCanaryObservationReport(
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
            generatedArtifactDownloadOnly: safetyReports.allSatisfy(\.generatedArtifactDownloadOnly),
            generatedArtifactUploadAttempted: safetyReports.contains(where: \.generatedArtifactUploadAttempted),
            audioUploadAttempted: safetyReports.contains(where: \.audioUploadAttempted),
            contentLeakRiskObserved: safetyReports.contains(where: \.contentLeakRisk),
            routeIsArtifactRequest: safetyReports.allSatisfy(\.routeIsArtifactRequest),
            uiMutated: false,
            fatalBlocker: cutoverResult.fatalBlocker,
            nextRecommendation: recommendation,
            reason: status.rawValue
        )
    }

    private nonisolated static func diagnostic(
        _ kind: CanonicalGeneratedArtifactCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil,
        action: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalGeneratedArtifactCutoverDiagnostic {
        CanonicalGeneratedArtifactCutoverDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            objectID: objectID,
            artifactID: artifactID,
            artifactKind: artifactKind,
            action: action,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}

nonisolated struct CanonicalGeneratedArtifactCanaryStageRunner: Sendable {
    nonisolated init() {}

    func run(
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix = .v824GeneratedArtifactsStagedCanary(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true
        ),
        candidates: [CanonicalGeneratedArtifactCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String? = nil,
        localSnapshotAvailable: Bool = true,
        peerSnapshotAvailable: Bool = true,
        peerNode: CanonicalNode?,
        executor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    ) async -> CanonicalGeneratedArtifactCanaryStageResult {
        let stagePolicy = policy.stagePolicy
        let stage = stagePolicy.requestedStage
        let stageGate = CanonicalGeneratedArtifactCanaryStageGate(
            policy: stagePolicy,
            domain: .generatedArtifacts,
            token: token,
            cutoverEvidence: evidence
        )
        let evidenceReport = stageGate.evidenceReport
        var diagnostics = Self.initialDiagnostics(
            stagePolicy: stagePolicy,
            evidenceReport: evidenceReport,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            candidateCount: candidates.count
        )
        let safetyReports = candidates.map {
            CanonicalGeneratedArtifactCanaryCandidateSafety(
                candidate: $0,
                evidence: evidence,
                peerNode: peerNode
            )
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
        var selection = CanonicalGeneratedArtifactCanarySelector().select(
            mode: .canary,
            policy: policy,
            trigger: trigger,
            evidence: evidence,
            peerNode: peerNode,
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
                    .canonicalGeneratedArtifactCanaryStageBlocked,
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

        let gate = CanonicalGeneratedArtifactCutoverRunner().evaluateGate(
            mode: .canary,
            policy: policy,
            token: token,
            evidence: evidence,
            candidates: selection.selectedCutoverCandidates,
            peerNode: peerNode,
            trigger: trigger
        )
        diagnostics.append(
            Self.diagnostic(
                gate.allowed ? .canonicalGeneratedArtifactCanaryStageAllowed : .canonicalGeneratedArtifactCanaryStageBlocked,
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
                stage == .allEligible ? .canonicalGeneratedArtifactCanaryAllEligibleStarted : .canonicalGeneratedArtifactCanaryStageStarted,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: "started",
                reason: "stage=\(stage.rawValue);selected=\(selection.selectedCandidates.count)"
            )
        )

        var commits: [CanonicalGeneratedArtifactProductionCommitResult] = []
        var rollbacks: [CanonicalGeneratedArtifactRollbackExecutionResult] = []
        var readSideProjection: CanonicalGeneratedArtifactReadSideParallelProjectionResult?
        var readSideEquivalentCount = 0
        var readSideDivergentCount = 0
        var legacyFallbackUsed = false
        var fatalBlocker = false

        for candidate in selection.selectedCutoverCandidates {
            diagnostics.append(
                Self.diagnostic(
                    .canonicalGeneratedArtifactCanaryCandidateExecuted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: candidate.objectID,
                    artifactID: candidate.artifactID,
                    artifactKind: candidate.artifactKind,
                    action: candidate.cutoverActionKind.rawValue,
                    result: "started",
                    hash: candidate.expectedContentHash
                )
            )
            diagnostics.append(
                Self.diagnostic(
                    .canonicalGeneratedArtifactCommitStarted,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: candidate.objectID,
                    artifactID: candidate.artifactID,
                    artifactKind: candidate.artifactKind,
                    action: candidate.cutoverActionKind.rawValue,
                    result: "started",
                    hash: candidate.expectedContentHash
                )
            )
            let commit = await executor.commitGeneratedArtifact(candidate)
            commits.append(commit)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalGeneratedArtifactCommitCompleted,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        objectID: candidate.objectID,
                        artifactID: candidate.artifactID,
                        artifactKind: candidate.artifactKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "committed",
                        reason: commit.reason,
                        hash: candidate.expectedContentHash
                    )
                )
                let projection = CanonicalGeneratedArtifactReadSideParallelProjectionResult(
                    objectID: candidate.objectID,
                    artifactID: candidate.artifactID,
                    artifactKind: candidate.artifactKind,
                    equivalent: evidence.readSideParallelEquivalent,
                    canonicalHash: candidate.expectedContentHash,
                    legacyHash: evidence.readSideParallelEquivalent ? candidate.expectedContentHash : nil,
                    canonicalByteSize: candidate.expectedByteSize,
                    legacyByteSize: evidence.readSideParallelEquivalent ? candidate.expectedByteSize : nil,
                    reason: evidence.readSideParallelEquivalent ? "expandedGeneratedArtifactReadSideParallelEquivalent" : "expandedGeneratedArtifactReadSideParallelDivergent"
                )
                if readSideProjection == nil {
                    readSideProjection = projection
                }
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalGeneratedArtifactExpandedReadSideParallelStarted,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        objectID: projection.objectID,
                        artifactID: projection.artifactID,
                        artifactKind: projection.artifactKind,
                        result: "started"
                    )
                )
                diagnostics.append(
                    Self.diagnostic(
                        projection.equivalent ? .canonicalGeneratedArtifactExpandedReadSideParallelEquivalent : .canonicalGeneratedArtifactExpandedReadSideParallelDivergent,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        objectID: projection.objectID,
                        artifactID: projection.artifactID,
                        artifactKind: projection.artifactKind,
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
                let failure = commit.failureKind ?? .postconditionMismatch
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalGeneratedArtifactCommitFailed,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        objectID: candidate.objectID,
                        artifactID: candidate.artifactID,
                        artifactKind: candidate.artifactKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "failed",
                        reason: failure.rawValue,
                        hash: candidate.expectedContentHash
                    )
                )
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalGeneratedArtifactRollbackStarted,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        objectID: candidate.objectID,
                        artifactID: candidate.artifactID,
                        artifactKind: candidate.artifactKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: "started",
                        reason: failure.rawValue
                    )
                )
                let rollback = await executor.rollbackGeneratedArtifact(candidate, reason: failure)
                rollbacks.append(rollback)
                fatalBlocker = fatalBlocker || rollback.fatal || !rollback.succeeded
                diagnostics.append(
                    Self.diagnostic(
                        rollback.succeeded ? .canonicalGeneratedArtifactRollbackCompleted : .canonicalGeneratedArtifactRollbackFailed,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        objectID: candidate.objectID,
                        artifactID: candidate.artifactID,
                        artifactKind: candidate.artifactKind,
                        action: candidate.cutoverActionKind.rawValue,
                        result: rollback.succeeded ? "rolledBack" : "rollbackFailed",
                        reason: rollback.reason
                    )
                )
                diagnostics.append(
                    Self.diagnostic(
                        .canonicalGeneratedArtifactCanaryStoppedAfterFailure,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        objectID: candidate.objectID,
                        artifactID: candidate.artifactID,
                        artifactKind: candidate.artifactKind,
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
                    .canonicalGeneratedArtifactDuplicateLegacySuppressed,
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
                    .canonicalGeneratedArtifactLegacyFallbackUsed,
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
                .canonicalGeneratedArtifactCanaryStageObservationRecorded,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: report.stage.rawValue,
                reason: report.diagnosticsSummary
            )
        )
        diagnostics.append(
            Self.diagnostic(
                report.nextStageEligible ? .canonicalGeneratedArtifactCanaryNextStageEligible : .canonicalGeneratedArtifactCanaryNextStageBlocked,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: report.nextStageEligible ? "eligible" : "blocked",
                reason: report.nextStageBlockers.map(\.rawValue).joined(separator: ",")
            )
        )
        diagnostics.append(
            Self.diagnostic(
                stage == .allEligible ? .canonicalGeneratedArtifactCanaryAllEligibleCompleted : (fatalBlocker || report.failureCount > 0 ? .canonicalGeneratedArtifactCanaryStageFailed : .canonicalGeneratedArtifactCanaryStageCompleted),
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: fatalBlocker || report.failureCount > 0 ? "failed" : "completed",
                reason: "stage=\(stage.rawValue);executed=\(commits.count)"
            )
        )

        let legacyObservationStatus: CanonicalGeneratedArtifactCanaryObservationStatus
        if fatalBlocker {
            legacyObservationStatus = .fatalRollbackFailure
        } else if report.failureCount > 0 {
            legacyObservationStatus = .failedRolledBack
        } else {
            legacyObservationStatus = .committed
        }
        let legacyObservation = CanonicalGeneratedArtifactCanaryObservationReport(
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
            generatedArtifactDownloadOnly: safetyReports.allSatisfy(\.generatedArtifactDownloadOnly),
            generatedArtifactUploadAttempted: safetyReports.contains(where: \.generatedArtifactUploadAttempted),
            audioUploadAttempted: safetyReports.contains(where: \.audioUploadAttempted),
            contentLeakRiskObserved: safetyReports.contains(where: \.contentLeakRisk),
            routeIsArtifactRequest: safetyReports.allSatisfy(\.routeIsArtifactRequest),
            uiMutated: false,
            fatalBlocker: fatalBlocker,
            nextRecommendation: .fixBlockers,
            reason: legacyObservationStatus.rawValue
        )
        let cutoverResult = CanonicalGeneratedArtifactCutoverResult(
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
        return CanonicalGeneratedArtifactCanaryStageResult(
            cutoverResult: cutoverResult,
            selection: selection,
            stageObservationReport: report
        )
    }

    private nonisolated static func strictFailures(
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        token: CanonicalCutoverToken?,
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        matrix: CanonicalMigrationDomainMatrix,
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        executorAvailable: Bool
    ) -> [CanonicalGeneratedArtifactCutoverFailure] {
        let stagePolicy = policy.stagePolicy
        var failures: [CanonicalGeneratedArtifactCutoverFailure] = []
        if !stagePolicy.requestedStage.isExecutable {
            failures.append(.disabled)
        }
        if stagePolicy.requestedStage == .n1 {
            failures.append(.canaryStageBlocked)
        }
        if !stagePolicy.allowCandidateExecution || !policy.explicitInternalTestConfiguration {
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
        if matrixReport.activePilotDomain != .generatedArtifacts {
            failures.append(.activePilotNotGeneratedArtifacts)
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
        if !evidence.artifactRequestRouteEvidenceAvailable { failures.append(.missingArtifactRequestRouteEvidence) }
        if !evidence.productionPortAvailable { failures.append(.productionPortUnavailable) }
        if !evidence.realRootBoundApplyPortAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.applyPortMode.isNonDryRunRootBound { failures.append(.applyPortDryRunOnly) }
        if !evidence.rootBoundWriteAvailable { failures.append(.rootBoundWriteUnavailable) }
        if !evidence.atomicReplaceAvailable { failures.append(.atomicReplaceUnavailable) }
        if !evidence.rollbackCheckpointAvailable { failures.append(.rollbackCheckpointUnavailable) }
        if evidence.rollbackPlan?.covers(domain: .generatedArtifacts) != true { failures.append(.missingRollback) }
        if !evidence.rollbackVerified || !evidence.rollbackRehearsalPassed {
            failures.append(.rollbackVerificationMissing)
        }
        if !evidence.productionRootDisabledByDefault { failures.append(.productionRootEnabledByDefault) }
        if evidence.applyPortMode == .testRootBound && !evidence.testRootUsed { failures.append(.testRootMissing) }
        if !evidence.legacyFallbackAvailable { failures.append(.legacyFallbackUnavailable) }
        if !evidence.readSideParallelEquivalent { failures.append(.missingReadSideParallelEvidence) }
        let stageGate = CanonicalGeneratedArtifactCanaryStageGate(
            policy: stagePolicy,
            domain: .generatedArtifacts,
            token: token,
            cutoverEvidence: evidence
        )
        failures.append(contentsOf: stageGate.blockers.map(CanonicalGeneratedArtifactCutoverRunner.cutoverFailure(for:)))
        return Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated static func initialDiagnostics(
        stagePolicy: CanonicalGeneratedArtifactCanaryStagePolicy,
        evidenceReport: CanonicalGeneratedArtifactStageEvidenceReport,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        candidateCount: Int
    ) -> [CanonicalGeneratedArtifactCutoverDiagnostic] {
        [
            diagnostic(
                .canonicalGeneratedArtifactCanaryStageEvaluated,
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
        selection: CanonicalGeneratedArtifactCanarySelectionResult,
        safetyReports: [CanonicalGeneratedArtifactCanaryCandidateSafety],
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> [CanonicalGeneratedArtifactCutoverDiagnostic] {
        var diagnostics: [CanonicalGeneratedArtifactCutoverDiagnostic] = []
        for blocker in selection.blockers where blocker.objectID != nil {
            let kind: CanonicalGeneratedArtifactCutoverDiagnosticKind
            switch blocker.reason {
            case .contentLeakRisk:
                kind = .canonicalGeneratedArtifactContentLeakBlocked
            case .unsafeLogicalPathToken:
                kind = .canonicalGeneratedArtifactUnsafePathTokenBlocked
            case .parentTombstoned:
                kind = .canonicalGeneratedArtifactParentTombstoneBlocked
            case .audioConfusionRisk:
                kind = .canonicalGeneratedArtifactAudioConfusionBlocked
            case .unsupportedKind:
                kind = .canonicalGeneratedArtifactUnsupportedKindBlocked
            case .producerAmbiguous:
                kind = .canonicalGeneratedArtifactProducerAmbiguousBlocked
            case .hashUnavailable:
                kind = .canonicalGeneratedArtifactHashUnavailableBlocked
            case .byteSizeUnavailable:
                kind = .canonicalGeneratedArtifactByteSizeUnavailableBlocked
            default:
                kind = .canonicalGeneratedArtifactCanaryCandidateSkipped
            }
            diagnostics.append(
                diagnostic(
                    kind,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: blocker.objectID,
                    artifactID: blocker.artifactID,
                    result: "skipped",
                    reason: blocker.reason.rawValue
                )
            )
        }
        for report in safetyReports where !report.safe {
            diagnostics.append(
                diagnostic(
                    .canonicalGeneratedArtifactCanaryCandidateSkipped,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: report.candidate.objectID,
                    artifactID: report.candidate.artifactID,
                    artifactKind: report.candidate.artifactKind,
                    action: report.candidate.cutoverCandidate.cutoverActionKind.rawValue,
                    result: "skipped",
                    reason: report.blockers.map(\.rawValue).joined(separator: ","),
                    hash: report.candidate.cutoverCandidate.expectedContentHash
                )
            )
        }
        return diagnostics
    }

    private nonisolated static func selectionBlockedByRunFailures(
        _ selection: CanonicalGeneratedArtifactCanarySelectionResult,
        failures: [CanonicalGeneratedArtifactCutoverFailure],
        evaluatedCandidateCount: Int
    ) -> CanonicalGeneratedArtifactCanarySelectionResult {
        let runBlockers = failures.map {
            CanonicalGeneratedArtifactCanarySelectionBlocker(objectID: nil, artifactID: nil, reason: blocker(for: $0))
        }
        return CanonicalGeneratedArtifactCanarySelectionResult(
            selectedCandidates: [],
            blockers: selection.blockers + runBlockers,
            evaluatedCandidateCount: evaluatedCandidateCount,
            noEligibleCandidate: true
        )
    }

    private nonisolated static func blockedResult(
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        selection: CanonicalGeneratedArtifactCanarySelectionResult,
        safetyReports: [CanonicalGeneratedArtifactCanaryCandidateSafety],
        evidence: CanonicalGeneratedArtifactCutoverEvidence,
        evidenceReport: CanonicalGeneratedArtifactStageEvidenceReport,
        diagnostics: [CanonicalGeneratedArtifactCutoverDiagnostic],
        failures: [CanonicalGeneratedArtifactCutoverFailure],
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        noEligible: Bool = false,
        reason: String
    ) -> CanonicalGeneratedArtifactCanaryStageResult {
        let stage = policy.stagePolicy.requestedStage
        let gate = CanonicalGeneratedArtifactCutoverGate(
            domain: .generatedArtifacts,
            mode: .canary,
            failures: failures,
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            reason: reason
        )
        var diagnostics = diagnostics
        diagnostics.append(
            diagnostic(
                .canonicalGeneratedArtifactCanaryStageBlocked,
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
                    .canonicalGeneratedArtifactN1MacPeerSnapshotUnavailable,
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
                .canonicalGeneratedArtifactCanaryStageObservationRecorded,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                result: stage.rawValue,
                reason: report.diagnosticsSummary
            )
        )
        let legacyObservation = CanonicalGeneratedArtifactCanaryObservationReport(
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
            generatedArtifactDownloadOnly: safetyReports.allSatisfy(\.generatedArtifactDownloadOnly),
            generatedArtifactUploadAttempted: safetyReports.contains(where: \.generatedArtifactUploadAttempted),
            audioUploadAttempted: safetyReports.contains(where: \.audioUploadAttempted),
            contentLeakRiskObserved: safetyReports.contains(where: \.contentLeakRisk),
            routeIsArtifactRequest: safetyReports.allSatisfy(\.routeIsArtifactRequest),
            uiMutated: false,
            fatalBlocker: !noEligible,
            nextRecommendation: noEligible ? .remainN1 : .fixBlockers,
            reason: reason
        )
        let cutoverResult = CanonicalGeneratedArtifactCutoverResult(
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
        return CanonicalGeneratedArtifactCanaryStageResult(
            cutoverResult: cutoverResult,
            selection: selection,
            stageObservationReport: report
        )
    }

    private nonisolated static func observationReport(
        policy: CanonicalGeneratedArtifactCanaryPolicy,
        selection: CanonicalGeneratedArtifactCanarySelectionResult,
        safetyReports: [CanonicalGeneratedArtifactCanaryCandidateSafety],
        commits: [CanonicalGeneratedArtifactProductionCommitResult],
        rollbacks: [CanonicalGeneratedArtifactRollbackExecutionResult],
        evidenceReport: CanonicalGeneratedArtifactStageEvidenceReport,
        fatalBlocker: Bool,
        readSideEquivalentCount: Int,
        readSideDivergentCount: Int,
        explicitBlockers: [CanonicalGeneratedArtifactCutoverFailure] = []
    ) -> CanonicalGeneratedArtifactCanaryStageObservationReport {
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
        let failures = selection.blockers.map {
            CanonicalGeneratedArtifactCanaryStageFailure(
                objectID: $0.objectID,
                artifactID: $0.artifactID,
                blocker: $0.reason
            )
        }
        return CanonicalGeneratedArtifactCanaryStageObservationReport(
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
            unsafeCandidateSkippedCount: safetyReports.filter { !$0.safe }.count,
            contentLeakRiskCount: selection.blockers.filter { $0.reason == .contentLeakRisk }.count,
            unsafePathTokenCount: selection.blockers.filter { $0.reason == .unsafeLogicalPathToken }.count,
            parentTombstoneBlockCount: selection.blockers.filter { $0.reason == .parentTombstoned }.count,
            audioConfusionBlockCount: selection.blockers.filter { $0.reason == .audioConfusionRisk }.count,
            fatalBlockerCount: fatalBlocker ? 1 : 0,
            readSideParallelEquivalentCount: readSideEquivalentCount,
            readSideParallelDivergentCount: readSideDivergentCount,
            nextStageEligible: nextEligible,
            nextStageBlockers: blockerFailures,
            recommendation: recommendation(stage: stage, nextEligible: nextEligible, fatalBlocker: fatalBlocker, failureCount: failureCount),
            runtimeSwitch: policy.runtimeSwitchEnabled || policy.stagePolicy.runtimeSwitchEnabled,
            failures: failures,
            evidenceReport: evidenceReport
        )
    }

    private nonisolated static func nextStageBlockers(
        stage: CanonicalGeneratedArtifactCanaryStage,
        selection: CanonicalGeneratedArtifactCanarySelectionResult,
        successCount: Int,
        failureCount: Int,
        rollbackFailureCount: Int,
        fatalBlocker: Bool,
        readSideDivergentCount: Int
    ) -> [CanonicalGeneratedArtifactCutoverFailure] {
        var blockers: [CanonicalGeneratedArtifactCutoverFailure] = []
        if selection.selectedCandidates.isEmpty {
            blockers.append(.unsupportedAction)
        }
        if successCount < selection.selectedCandidates.count || failureCount > 0 {
            blockers.append(.previousStageFailure)
        }
        if rollbackFailureCount > 0 {
            blockers.append(.previousStageRollbackFailure)
        }
        if fatalBlocker {
            blockers.append(.rollbackFailure)
        }
        if readSideDivergentCount > 0 {
            blockers.append(.missingReadSideParallelEvidence)
        }
        if selection.blockers.contains(where: { $0.reason == .contentLeakRisk }) {
            blockers.append(.contentLeakRisk)
        }
        if selection.blockers.contains(where: { $0.reason == .unsafeLogicalPathToken }) {
            blockers.append(.unsafePathToken)
        }
        if selection.blockers.contains(where: { $0.reason == .parentTombstoned }) {
            blockers.append(.parentTombstoned)
        }
        if selection.blockers.contains(where: { $0.reason == .audioConfusionRisk }) {
            blockers.append(.audioConfusionRisk)
        }
        if selection.blockers.contains(where: { $0.reason == .hashUnavailable }) {
            blockers.append(.hashUnavailable)
        }
        if selection.blockers.contains(where: { $0.reason == .byteSizeUnavailable }) {
            blockers.append(.byteSizeUnavailable)
        }
        if stage == .allEligible {
            blockers.append(.allEligibleCanaryDenied)
        }
        return Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }

    private nonisolated static func recommendation(
        stage: CanonicalGeneratedArtifactCanaryStage,
        nextEligible: Bool,
        fatalBlocker: Bool,
        failureCount: Int
    ) -> CanonicalGeneratedArtifactCanaryStageRecommendation {
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
        case .n3:
            return .advanceToN10
        case .n10:
            return .advanceToAllEligible
        case .allEligible:
            return .observeCurrentStage
        case .n1, .disabled:
            return .stayDisabled
        }
    }

    private nonisolated static func blocker(
        for failure: CanonicalGeneratedArtifactCutoverFailure
    ) -> CanonicalGeneratedArtifactCanaryBlocker {
        switch failure {
        case .missingOwnerApproval, .missingToken:
            return .missingOwnerApproval
        case .matrixValidationBlocked:
            return .matrixBlocked
        case .activePilotNotGeneratedArtifacts:
            return .activePilotNotGeneratedArtifacts
        case .commitExecutorUnavailable:
            return .commitExecutorUnavailable
        case .peerSnapshotUnavailable, .peerUnknown:
            return .peerSnapshotUnavailable
        case .runtimeSwitchDenied:
            return .runtimeSwitchDenied
        case .allEligibleCanaryDenied, .canaryBudgetAboveOneDenied:
            return .allEligibleDenied
        case .defaultEnablementDenied:
            return .defaultEnablementDenied
        case .missingReadSideParallelEvidence:
            return .readSideParallelMissing
        case .expectedHashMissing, .hashUnavailable:
            return .hashUnavailable
        case .expectedByteSizeMissing, .byteSizeUnavailable:
            return .byteSizeUnavailable
        case .producerAmbiguous:
            return .producerAmbiguous
        case .missingArtifactRequestRouteEvidence:
            return .unsupportedRoute
        case .rollbackCheckpointUnavailable:
            return .rollbackCheckpointMissing
        case .parentTombstoned:
            return .parentTombstoned
        case .unresolvedConflict:
            return .unresolvedConflict
        case .contentLeakRisk:
            return .contentLeakRisk
        case .unsafePathToken:
            return .unsafeLogicalPathToken
        case .audioConfusionRisk:
            return .audioConfusionRisk
        default:
            return .insufficientEvidence
        }
    }

    private nonisolated static func diagnostic(
        _ kind: CanonicalGeneratedArtifactCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        objectID: String? = nil,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind? = nil,
        action: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalGeneratedArtifactCutoverDiagnostic {
        CanonicalGeneratedArtifactCutoverDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            objectID: objectID,
            artifactID: artifactID,
            artifactKind: artifactKind,
            action: action,
            result: result,
            reason: reason,
            hash: hash
        )
    }
}

nonisolated struct CanonicalGeneratedArtifactNoCommitCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { cutoverCandidate.id }

    var cutoverCandidate: CanonicalGeneratedArtifactCutoverCandidate
    var expectedRoutePath: String

    nonisolated init(
        cutoverCandidate: CanonicalGeneratedArtifactCutoverCandidate,
        expectedRoutePath: String = "/sync/artifact-request"
    ) {
        self.cutoverCandidate = cutoverCandidate
        self.expectedRoutePath = CanonicalProductionRedaction.safeDiagnosticText(expectedRoutePath) ?? "/sync/artifact-request"
    }
}

nonisolated struct CanonicalGeneratedArtifactNoCommitPayloadSummary: Codable, Equatable, Sendable {
    var schema: String
    var stagedArtifactKind: CanonicalArtifact.Kind?
    var objectID: String
    var artifactID: String?
    var byteSize: Int64?
    var hashPrefix: String?
    var wouldRequestRoute: String
    var wouldApplyToLocalGeneratedStore: Bool
    var productionCommitSuppressed: Bool
    var legacyDuplicateSuppressed: Bool

    nonisolated init(candidate: CanonicalGeneratedArtifactNoCommitCandidate) {
        let cutover = candidate.cutoverCandidate
        self.schema = "canonical-generated-artifact-no-commit-v8-9"
        self.stagedArtifactKind = cutover.artifactKind
        self.objectID = CanonicalProductionRedaction.safeIdentifier(cutover.objectID, fallback: "unknown-recording")
        self.artifactID = cutover.artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.byteSize = cutover.expectedByteSize
        self.hashPrefix = cutover.expectedContentHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.wouldRequestRoute = candidate.expectedRoutePath
        self.wouldApplyToLocalGeneratedStore = cutover.cutoverActionKind.isExecutableApply
        self.productionCommitSuppressed = true
        self.legacyDuplicateSuppressed = false
    }

    nonisolated func encodedBytes() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

nonisolated enum CanonicalGeneratedArtifactNoCommitFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedAction
    case insufficientEvidence
    case stagingFailed
    case productionCommitSuppressed
}

nonisolated struct CanonicalGeneratedArtifactNoCommitStagingResult: Codable, Equatable, Sendable {
    var candidate: CanonicalGeneratedArtifactNoCommitCandidate
    var staged: Bool
    var wroteOnlyStagingRoot: Bool
    var stagedLogicalPathToken: String?
    var payloadByteCount: Int
    var payloadHashPrefix: String?
    var wouldRequestRoute: String
    var wouldApplyToLocalGeneratedStore: Bool
    var productionCommitSuppressed: Bool
    var legacyDuplicateSuppressed: Bool
    var stagingEvidence: CanonicalNoCommitStagingEvidence?
    var cleanupEvidence: CanonicalNoCommitCleanupEvidence?
    var failure: CanonicalGeneratedArtifactNoCommitFailure?
    var reason: String

    nonisolated init(
        candidate: CanonicalGeneratedArtifactNoCommitCandidate,
        staged: Bool,
        wroteOnlyStagingRoot: Bool,
        stagedLogicalPathToken: String? = nil,
        payloadByteCount: Int = 0,
        payloadHashPrefix: String? = nil,
        wouldRequestRoute: String = "/sync/artifact-request",
        wouldApplyToLocalGeneratedStore: Bool = true,
        productionCommitSuppressed: Bool = true,
        legacyDuplicateSuppressed: Bool = false,
        stagingEvidence: CanonicalNoCommitStagingEvidence? = nil,
        cleanupEvidence: CanonicalNoCommitCleanupEvidence? = nil,
        failure: CanonicalGeneratedArtifactNoCommitFailure? = nil,
        reason: String
    ) {
        self.candidate = candidate
        self.staged = staged
        self.wroteOnlyStagingRoot = wroteOnlyStagingRoot
        self.stagedLogicalPathToken = stagedLogicalPathToken.flatMap(CanonicalProjectionContract.safeLogicalPathToken)
        self.payloadByteCount = max(0, payloadByteCount)
        self.payloadHashPrefix = CanonicalProductionRedaction.hashPrefix(payloadHashPrefix)
        self.wouldRequestRoute = CanonicalProductionRedaction.safeDiagnosticText(wouldRequestRoute) ?? "/sync/artifact-request"
        self.wouldApplyToLocalGeneratedStore = wouldApplyToLocalGeneratedStore
        self.productionCommitSuppressed = productionCommitSuppressed
        self.legacyDuplicateSuppressed = legacyDuplicateSuppressed
        self.stagingEvidence = stagingEvidence
        self.cleanupEvidence = cleanupEvidence
        self.failure = failure
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (staged ? "staged" : "blocked")
    }
}

protocol CanonicalGeneratedArtifactNoCommitExecutor: Sendable {
    func stageGeneratedArtifactNoCommit(
        _ candidate: CanonicalGeneratedArtifactNoCommitCandidate
    ) -> CanonicalGeneratedArtifactNoCommitStagingResult
}

nonisolated struct CanonicalGeneratedArtifactReadSideParallelProjectionResult: Codable, Equatable, Sendable {
    var objectID: String
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?
    var equivalent: Bool
    var mutatedUI: Bool
    var canonicalHashPrefix: String?
    var legacyHashPrefix: String?
    var canonicalByteSize: Int64?
    var legacyByteSize: Int64?
    var reason: String

    nonisolated init(
        objectID: String,
        artifactID: String?,
        artifactKind: CanonicalArtifact.Kind?,
        equivalent: Bool,
        canonicalHash: CanonicalHash?,
        legacyHash: CanonicalHash?,
        canonicalByteSize: Int64?,
        legacyByteSize: Int64?,
        reason: String
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.artifactKind = artifactKind
        self.equivalent = equivalent
        self.mutatedUI = false
        self.canonicalHashPrefix = canonicalHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.legacyHashPrefix = legacyHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.canonicalByteSize = canonicalByteSize
        self.legacyByteSize = legacyByteSize
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (equivalent ? "equivalent" : "divergent")
    }
}

nonisolated struct CanonicalGeneratedArtifactLegacyActionIdentity: Codable, Equatable, Hashable, Sendable {
    var actionID: String?
    var syncRunID: String?
    var objectID: String
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind
    var routeTarget: String?
    var actionKind: CanonicalGeneratedArtifactCutoverActionKind

    nonisolated init(
        actionID: String? = nil,
        syncRunID: String? = nil,
        objectID: String,
        artifactID: String? = nil,
        artifactKind: CanonicalArtifact.Kind,
        routeTarget: String? = nil,
        actionKind: CanonicalGeneratedArtifactCutoverActionKind = .generatedArtifactDownloadApply
    ) {
        self.actionID = actionID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "legacy-action") }
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.artifactID = artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact:unknown") }
        self.artifactKind = artifactKind
        self.routeTarget = routeTarget.flatMap(CanonicalProjectionContract.safeLogicalPathToken)
        self.actionKind = actionKind
    }
}

nonisolated enum CanonicalGeneratedArtifactLegacyDuplicateSuppression {
    nonisolated static func suppressedLegacyActionIDs(
        after result: CanonicalGeneratedArtifactCutoverResult,
        legacyActions: [CanonicalGeneratedArtifactLegacyActionIdentity]
    ) -> [String] {
        guard result.succeeded else {
            return []
        }
        let successfulCommits = result.commits.filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
        let ids = legacyActions.compactMap { legacy -> String? in
            guard successfulCommits.contains(where: { commit in
                matches(commit: commit, legacy: legacy)
            }) else {
                return nil
            }
            return legacy.actionID
        }
        return Array(Set(ids)).sorted()
    }

    private nonisolated static func matches(
        commit: CanonicalGeneratedArtifactProductionCommitResult,
        legacy: CanonicalGeneratedArtifactLegacyActionIdentity
    ) -> Bool {
        guard legacy.actionKind == .generatedArtifactApply || legacy.actionKind == .generatedArtifactDownloadApply else {
            return false
        }
        guard commit.objectID == legacy.objectID,
              commit.artifactKind == legacy.artifactKind else {
            return false
        }
        if let commitArtifactID = commit.artifactID,
           let legacyArtifactID = legacy.artifactID {
            return commitArtifactID == legacyArtifactID
        }
        if let routeTarget = legacy.routeTarget,
           routeTarget == commit.artifactID {
            return true
        }
        return legacy.artifactID == nil
    }
}

nonisolated struct CanonicalGeneratedArtifactCutoverAppSeamPolicy: Codable, Equatable, Sendable {
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int
    var canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy

    nonisolated init(
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 200,
        canaryPolicy: CanonicalGeneratedArtifactCanaryPolicy = .disabled
    ) {
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
        self.canaryPolicy = canaryPolicy
    }
}

nonisolated struct CanonicalGeneratedArtifactCutoverAppSeamConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: CanonicalCutoverAppSeamMode
    var policy: CanonicalGeneratedArtifactCutoverAppSeamPolicy
    var evidence: CanonicalGeneratedArtifactCutoverEvidence
    var cutoverToken: CanonicalCutoverToken?

    nonisolated init(
        isEnabled: Bool = false,
        mode: CanonicalCutoverAppSeamMode = .disabled,
        policy: CanonicalGeneratedArtifactCutoverAppSeamPolicy = CanonicalGeneratedArtifactCutoverAppSeamPolicy(),
        evidence: CanonicalGeneratedArtifactCutoverEvidence = CanonicalGeneratedArtifactCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) {
        self.isEnabled = isEnabled
        self.mode = isEnabled ? mode : .disabled
        self.policy = policy
        self.evidence = evidence
        self.cutoverToken = cutoverToken
    }

    nonisolated static let disabled = CanonicalGeneratedArtifactCutoverAppSeamConfiguration()

    nonisolated static func enabled(
        mode: CanonicalCutoverAppSeamMode = .guardedExecuteCommit,
        policy: CanonicalGeneratedArtifactCutoverAppSeamPolicy = CanonicalGeneratedArtifactCutoverAppSeamPolicy(),
        evidence: CanonicalGeneratedArtifactCutoverEvidence = CanonicalGeneratedArtifactCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) -> CanonicalGeneratedArtifactCutoverAppSeamConfiguration {
        CanonicalGeneratedArtifactCutoverAppSeamConfiguration(
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

nonisolated enum CanonicalRootBoundGeneratedArtifactWriteFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable, Error {
    case rootEscape
    case productionRootDisabled
    case unsupportedKind
    case checkpointFailed
    case artifactBytesMissing
    case hashMismatchBeforeApply
    case atomicWriteFailed
    case postconditionFailed
    case rollbackFailed
    case unsupportedStoreAPI
    case permissionDenied
    case unknown
}

nonisolated struct CanonicalRootBoundGeneratedArtifactTarget: Codable, Equatable, Hashable, Sendable {
    var rootToken: CanonicalRootToken
    var objectID: String
    var artifactID: String
    var kind: CanonicalArtifact.Kind
    var domain: CanonicalProductionDomain
    var logicalPathToken: String

    nonisolated init(
        rootToken: CanonicalRootToken,
        objectID: String,
        artifactID: String,
        kind: CanonicalArtifact.Kind,
        domain: CanonicalProductionDomain = .generatedArtifacts,
        logicalPathToken: String
    ) throws {
        guard domain == .generatedArtifacts else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.unsupportedStoreAPI
        }
        guard CanonicalProjectionContract.generatedArtifactKinds.contains(kind) else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.unsupportedKind
        }
        guard let safePath = CanonicalProjectionContract.safeLogicalPathToken(logicalPathToken) else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.rootEscape
        }
        self.rootToken = rootToken
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.artifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: kind.rawValue)
        self.kind = kind
        self.domain = domain
        self.logicalPathToken = safePath
    }

    nonisolated static func defaultLogicalPathToken(objectID: String, kind: CanonicalArtifact.Kind) -> String {
        let component = safePathComponent(objectID)
        switch kind {
        case .transcriptJSON:
            return "transcripts/\(component)/transcript.json"
        case .transcriptMarkdown:
            return "transcripts/\(component)/transcript.md"
        case .noteMarkdown:
            return "notes/\(component)/note.md"
        case .noteJSON:
            return "notes/\(component)/note.json"
        case .summaryJSON:
            return "notes/\(component)/summary.json"
        case .audio, .metadata, .receiveRecord:
            return "generated/\(component)/\(safePathComponent(kind.rawValue))"
        }
    }

    private nonisolated static func safePathComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = trimmed.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let candidate = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        if !candidate.isEmpty {
            return candidate
        }
        return "recording-\(CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(trimmed).value) ?? "unknown")"
    }
}

nonisolated struct CanonicalRootBoundGeneratedArtifactWrite: Codable, Equatable, Sendable {
    var target: CanonicalRootBoundGeneratedArtifactTarget
    var artifactBytes: Data
    var expectedContentHash: CanonicalHash
    var expectedByteSize: Int64

    nonisolated init(
        target: CanonicalRootBoundGeneratedArtifactTarget,
        artifactBytes: Data,
        expectedContentHash: CanonicalHash,
        expectedByteSize: Int64
    ) {
        self.target = target
        self.artifactBytes = artifactBytes
        self.expectedContentHash = expectedContentHash
        self.expectedByteSize = expectedByteSize
    }
}

nonisolated struct CanonicalRootBoundGeneratedArtifactCheckpoint: Codable, Equatable, Identifiable, Sendable {
    var id: String { checkpointID }

    var checkpointID: String
    var objectID: String
    var artifactID: String
    var kind: CanonicalArtifact.Kind
    var domain: CanonicalProductionDomain
    var hashPrefixBefore: String?
    var byteCountBefore: Int64?
    var existedBeforeWrite: Bool
    var rollbackAvailable: Bool

    nonisolated init(
        checkpointID: String,
        objectID: String,
        artifactID: String,
        kind: CanonicalArtifact.Kind,
        hashBefore: CanonicalHash? = nil,
        byteCountBefore: Int64? = nil,
        existedBeforeWrite: Bool,
        rollbackAvailable: Bool
    ) {
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "generated-artifact-checkpoint")
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.artifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: "artifact:unknown")
        self.kind = kind
        self.domain = .generatedArtifacts
        self.hashPrefixBefore = hashBefore.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteCountBefore = byteCountBefore
        self.existedBeforeWrite = existedBeforeWrite
        self.rollbackAvailable = rollbackAvailable
    }
}

nonisolated struct CanonicalRootBoundGeneratedArtifactWriteResult: Codable, Equatable, Sendable {
    var objectID: String
    var artifactID: String
    var kind: CanonicalArtifact.Kind
    var domain: CanonicalProductionDomain
    var hashPrefixBefore: String?
    var hashPrefixAfter: String?
    var byteCount: Int64
    var checkpointID: String
    var atomicWriteUsed: Bool
    var rollbackAvailable: Bool
    var failure: CanonicalRootBoundGeneratedArtifactWriteFailure?

    nonisolated init(
        objectID: String,
        artifactID: String,
        kind: CanonicalArtifact.Kind,
        hashBefore: CanonicalHash? = nil,
        hashAfter: CanonicalHash? = nil,
        byteCount: Int64,
        checkpointID: String,
        atomicWriteUsed: Bool,
        rollbackAvailable: Bool,
        failure: CanonicalRootBoundGeneratedArtifactWriteFailure? = nil
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.artifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: "artifact:unknown")
        self.kind = kind
        self.domain = .generatedArtifacts
        self.hashPrefixBefore = hashBefore.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.hashPrefixAfter = hashAfter.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteCount = max(0, byteCount)
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "generated-artifact-checkpoint")
        self.atomicWriteUsed = atomicWriteUsed
        self.rollbackAvailable = rollbackAvailable
        self.failure = failure
    }
}

nonisolated struct CanonicalRootBoundGeneratedArtifactRollbackResult: Codable, Equatable, Sendable {
    var objectID: String
    var artifactID: String
    var kind: CanonicalArtifact.Kind
    var domain: CanonicalProductionDomain
    var checkpointID: String
    var succeeded: Bool
    var rollbackVerified: Bool
    var hashPrefixAfterRollback: String?
    var byteCount: Int64?
    var failure: CanonicalRootBoundGeneratedArtifactWriteFailure?

    nonisolated init(
        objectID: String,
        artifactID: String,
        kind: CanonicalArtifact.Kind,
        checkpointID: String,
        succeeded: Bool,
        rollbackVerified: Bool,
        hashAfterRollback: CanonicalHash? = nil,
        byteCount: Int64? = nil,
        failure: CanonicalRootBoundGeneratedArtifactWriteFailure? = nil
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.artifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: "artifact:unknown")
        self.kind = kind
        self.domain = .generatedArtifacts
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "generated-artifact-checkpoint")
        self.succeeded = succeeded
        self.rollbackVerified = rollbackVerified
        self.hashPrefixAfterRollback = hashAfterRollback.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.byteCount = byteCount
        self.failure = failure
    }
}

actor CanonicalRootBoundGeneratedArtifactWriteCore {
    private struct StoredCheckpoint: Sendable {
        var publicCheckpoint: CanonicalRootBoundGeneratedArtifactCheckpoint
        var target: CanonicalRootBoundGeneratedArtifactTarget
        var previousBytes: Data?
        var previousHash: CanonicalHash?
    }

    private let fileManager: FileManager
    private let rootURL: URL
    private let rootToken: CanonicalRootToken
    private let mode: CanonicalGeneratedArtifactApplyPortMode
    private var payloadsByActionID: [String: CanonicalRootBoundGeneratedArtifactWrite] = [:]
    private var payloadsByArtifactKey: [String: CanonicalRootBoundGeneratedArtifactWrite] = [:]
    private var checkpoints: [String: StoredCheckpoint] = [:]
    private var lastWriteByActionID: [String: CanonicalRootBoundGeneratedArtifactWriteResult] = [:]
    private var lastRollbackByCheckpointID: [String: CanonicalRootBoundGeneratedArtifactRollbackResult] = [:]
    private var checkpointFailureArtifactIDs: Set<String> = []
    private var postconditionFailureArtifactIDs: Set<String> = []
    private var rollbackFailureCheckpointIDs: Set<String> = []

    init(
        rootURL: URL,
        rootToken: CanonicalRootToken,
        mode: CanonicalGeneratedArtifactApplyPortMode,
        fileManager: FileManager = .default
    ) throws {
        guard rootURL.isFileURL else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.rootEscape
        }
        self.fileManager = fileManager
        self.rootURL = rootURL.standardizedFileURL
        self.rootToken = rootToken
        self.mode = mode
    }

    var applyPortMode: CanonicalGeneratedArtifactApplyPortMode {
        mode
    }

    func setPayload(
        objectID: String,
        artifactID: String,
        kind: CanonicalArtifact.Kind,
        artifactBytes: Data,
        expectedContentHash: CanonicalHash,
        expectedByteSize: Int64,
        logicalPathToken: String? = nil,
        actionID: String? = nil
    ) throws {
        let target = try CanonicalRootBoundGeneratedArtifactTarget(
            rootToken: rootToken,
            objectID: objectID,
            artifactID: artifactID,
            kind: kind,
            logicalPathToken: logicalPathToken ?? CanonicalRootBoundGeneratedArtifactTarget.defaultLogicalPathToken(objectID: objectID, kind: kind)
        )
        let write = CanonicalRootBoundGeneratedArtifactWrite(
            target: target,
            artifactBytes: artifactBytes,
            expectedContentHash: expectedContentHash,
            expectedByteSize: expectedByteSize
        )
        payloadsByArtifactKey[key(objectID: target.objectID, artifactID: target.artifactID, kind: kind)] = write
        if let actionID {
            payloadsByActionID[CanonicalProductionRedaction.safeIdentifier(actionID, fallback: kind.rawValue)] = write
        }
    }

    func injectCheckpointFailure(artifactID: String) {
        checkpointFailureArtifactIDs.insert(CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: "artifact:unknown"))
    }

    func injectPostconditionFailure(artifactID: String) {
        postconditionFailureArtifactIDs.insert(CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: "artifact:unknown"))
    }

    func injectRollbackFailure(checkpointID: String) {
        rollbackFailureCheckpointIDs.insert(CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "generated-artifact-checkpoint"))
    }

    func write(action: CanonicalApplyAction, checkpointID: String?) throws -> CanonicalRootBoundGeneratedArtifactWriteResult {
        try requireWritableMode()
        guard action.kind == .generatedArtifactDownloadApply else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.unsupportedStoreAPI
        }
        guard let artifactID = action.target.artifactID,
              let kind = action.target.artifactKind else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.unsupportedStoreAPI
        }
        let objectID = CanonicalProductionRedaction.safeIdentifier(action.target.objectID, fallback: "unknown-recording")
        let safeArtifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: kind.rawValue)
        guard let payload = payloadsByActionID[action.actionID]
            ?? payloadsByArtifactKey[key(objectID: objectID, artifactID: safeArtifactID, kind: kind)] else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.artifactBytesMissing
        }
        guard payload.target.objectID == objectID,
              payload.target.artifactID == safeArtifactID,
              payload.target.kind == kind else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.unsupportedStoreAPI
        }
        guard !checkpointFailureArtifactIDs.contains(safeArtifactID) else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.checkpointFailed
        }
        let preHash = Self.sha256(payload.artifactBytes)
        guard preHash == payload.expectedContentHash,
              Int64(payload.artifactBytes.count) == payload.expectedByteSize else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.hashMismatchBeforeApply
        }
        let effectiveCheckpointID = CanonicalProductionRedaction.safeIdentifier(
            checkpointID ?? "root-bound-generated-\(objectID)-\(safeArtifactID)",
            fallback: "generated-artifact-checkpoint"
        )
        let targetURL = try resolvedURL(for: payload.target)
        let previousBytes = fileManager.fileExists(atPath: targetURL.path) ? try Data(contentsOf: targetURL) : nil
        let previousHash = previousBytes.map(Self.sha256)
        let checkpoint = CanonicalRootBoundGeneratedArtifactCheckpoint(
            checkpointID: effectiveCheckpointID,
            objectID: objectID,
            artifactID: safeArtifactID,
            kind: kind,
            hashBefore: previousHash,
            byteCountBefore: previousBytes.map { Int64($0.count) },
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
            try payload.artifactBytes.write(to: targetURL, options: .atomic)
            let reread = try Data(contentsOf: targetURL)
            let afterHash = Self.sha256(reread)
            guard !postconditionFailureArtifactIDs.contains(safeArtifactID),
                  afterHash == payload.expectedContentHash,
                  Int64(reread.count) == payload.expectedByteSize else {
                try restore(checkpointID: effectiveCheckpointID)
                throw CanonicalRootBoundGeneratedArtifactWriteFailure.postconditionFailed
            }
            let result = CanonicalRootBoundGeneratedArtifactWriteResult(
                objectID: objectID,
                artifactID: safeArtifactID,
                kind: kind,
                hashBefore: previousHash,
                hashAfter: afterHash,
                byteCount: Int64(reread.count),
                checkpointID: effectiveCheckpointID,
                atomicWriteUsed: true,
                rollbackAvailable: true
            )
            lastWriteByActionID[action.actionID] = result
            return result
        } catch let failure as CanonicalRootBoundGeneratedArtifactWriteFailure {
            throw failure
        } catch {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.atomicWriteFailed
        }
    }

    func rollback(_ action: CanonicalRollbackAction) -> CanonicalRootBoundGeneratedArtifactRollbackResult {
        let checkpointID = CanonicalProductionRedaction.safeIdentifier(
            action.checkpointID ?? action.actionID,
            fallback: "generated-artifact-checkpoint"
        )
        guard let checkpoint = checkpoints[checkpointID] else {
            return CanonicalRootBoundGeneratedArtifactRollbackResult(
                objectID: action.objectID ?? "unknown-recording",
                artifactID: action.artifactID ?? "artifact:unknown",
                kind: .transcriptMarkdown,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                failure: .rollbackFailed
            )
        }
        if rollbackFailureCheckpointIDs.contains(checkpointID) {
            let result = CanonicalRootBoundGeneratedArtifactRollbackResult(
                objectID: checkpoint.target.objectID,
                artifactID: checkpoint.target.artifactID,
                kind: checkpoint.target.kind,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                failure: .rollbackFailed
            )
            lastRollbackByCheckpointID[checkpointID] = result
            return result
        }
        do {
            try restore(checkpointID: checkpointID)
            let targetURL = try resolvedURL(for: checkpoint.target)
            let currentBytes = fileManager.fileExists(atPath: targetURL.path) ? try Data(contentsOf: targetURL) : nil
            let verified = currentBytes == checkpoint.previousBytes
            let hashAfter = currentBytes.map(Self.sha256)
            let result = CanonicalRootBoundGeneratedArtifactRollbackResult(
                objectID: checkpoint.target.objectID,
                artifactID: checkpoint.target.artifactID,
                kind: checkpoint.target.kind,
                checkpointID: checkpointID,
                succeeded: verified,
                rollbackVerified: verified,
                hashAfterRollback: hashAfter,
                byteCount: currentBytes.map { Int64($0.count) },
                failure: verified ? nil : .rollbackFailed
            )
            lastRollbackByCheckpointID[checkpointID] = result
            if verified {
                checkpoints.removeValue(forKey: checkpointID)
            }
            return result
        } catch {
            let result = CanonicalRootBoundGeneratedArtifactRollbackResult(
                objectID: checkpoint.target.objectID,
                artifactID: checkpoint.target.artifactID,
                kind: checkpoint.target.kind,
                checkpointID: checkpointID,
                succeeded: false,
                rollbackVerified: false,
                failure: .rollbackFailed
            )
            lastRollbackByCheckpointID[checkpointID] = result
            return result
        }
    }

    func verifyPostcondition(_ postcondition: CanonicalProductionApplyPostcondition) -> CanonicalProductionApplyPostcondition {
        var result = postcondition
        if postcondition.actualHashPrefix?.count == 64 {
            result.actualHashPrefix = CanonicalProductionRedaction.hashPrefix(postcondition.actualHashPrefix)
        }
        return result
    }

    func lastWriteResult(actionID: String) -> CanonicalRootBoundGeneratedArtifactWriteResult? {
        lastWriteByActionID[CanonicalProductionRedaction.safeIdentifier(actionID, fallback: "generated-artifact-action")]
    }

    func lastRollbackResult(checkpointID: String) -> CanonicalRootBoundGeneratedArtifactRollbackResult? {
        lastRollbackByCheckpointID[CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "generated-artifact-checkpoint")]
    }

    func readArtifactBytes(objectID: String, artifactID: String, kind: CanonicalArtifact.Kind) throws -> Data? {
        let safeObjectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        let safeArtifactID = CanonicalProductionRedaction.safeIdentifier(artifactID, fallback: kind.rawValue)
        let payload = payloadsByArtifactKey[key(objectID: safeObjectID, artifactID: safeArtifactID, kind: kind)]
        let target: CanonicalRootBoundGeneratedArtifactTarget
        if let payload {
            target = payload.target
        } else {
            target = try CanonicalRootBoundGeneratedArtifactTarget(
                rootToken: rootToken,
                objectID: safeObjectID,
                artifactID: safeArtifactID,
                kind: kind,
                logicalPathToken: CanonicalRootBoundGeneratedArtifactTarget.defaultLogicalPathToken(objectID: safeObjectID, kind: kind)
            )
        }
        let url = try resolvedURL(for: target)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try Data(contentsOf: url)
    }

    private func requireWritableMode() throws {
        switch mode {
        case .testRootBound, .productionRootBound:
            return
        case .productionRootDisabled:
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.productionRootDisabled
        case .disabled, .dryRun, .fakeInMemory, .productionRootUnsupported:
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.unsupportedStoreAPI
        }
    }

    private func resolvedURL(for target: CanonicalRootBoundGeneratedArtifactTarget) throws -> URL {
        guard target.rootToken == rootToken else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.rootEscape
        }
        let destination = rootURL.appendingPathComponent(target.logicalPathToken, isDirectory: false).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : "\(rootURL.path)/"
        guard destination.path.hasPrefix(rootPath) else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.rootEscape
        }
        return destination
    }

    private func restore(checkpointID: String) throws {
        guard let checkpoint = checkpoints[checkpointID] else {
            throw CanonicalRootBoundGeneratedArtifactWriteFailure.rollbackFailed
        }
        let targetURL = try resolvedURL(for: checkpoint.target)
        if let previousBytes = checkpoint.previousBytes {
            try fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try previousBytes.write(to: targetURL, options: .atomic)
        } else if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
    }

    private nonisolated func key(objectID: String, artifactID: String, kind: CanonicalArtifact.Kind) -> String {
        "\(objectID)|\(artifactID)|\(kind.rawValue)"
    }

    private nonisolated static func sha256(_ data: Data) -> CanonicalHash {
        let digest = SHA256.hash(data: data)
        return CanonicalHash(digest.map { String(format: "%02x", $0) }.joined())
    }
}
