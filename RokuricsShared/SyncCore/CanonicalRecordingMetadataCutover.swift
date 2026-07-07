//
//  CanonicalRecordingMetadataCutover.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/3.
//

import Foundation

nonisolated enum CanonicalCutoverDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case recordingAudio
    case generatedArtifacts
    case folders
    case studyItems
    case standaloneNotes
    case tombstones
    case conflicts
    case apply
    case fileRuntime
    case transportRuntime
    case uploadRuntime
    case objectProjection
    case inventory
    case uiIntegration

    nonisolated var productionDomain: CanonicalProductionDomain {
        switch self {
        case .recordingMetadata: return .recordingMetadata
        case .recordingAudio: return .recordingAudio
        case .generatedArtifacts: return .generatedArtifacts
        case .folders: return .folders
        case .studyItems: return .studyItems
        case .standaloneNotes: return .standaloneNotes
        case .tombstones: return .tombstones
        case .conflicts: return .conflicts
        case .apply: return .apply
        case .fileRuntime: return .fileRuntime
        case .transportRuntime: return .transportRuntime
        case .uploadRuntime: return .uploadRuntime
        case .objectProjection: return .objectProjection
        case .inventory: return .inventory
        case .uiIntegration: return .uiIntegration
        }
    }
}

nonisolated enum CanonicalCutoverMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case shadowOnly
    case guardedExecuteNoCommit
    case guardedExecuteCommit
    case canary
    case rollbackOnly
    case legacyFallbackOnly

    nonisolated var permitsProductionCommit: Bool {
        self == .guardedExecuteCommit || self == .canary
    }
}

nonisolated struct CanonicalCutoverPolicy: Codable, Equatable, Sendable {
    var canaryMaxObjectsPerSyncRun: Int
    var allowsV87CanaryN1InternalExecution: Bool
    var recordingMetadataCanaryStagePolicy: CanonicalRecordingMetadataCanaryStagePolicy?
    var requireReadOnlyProbeForSend: Bool
    var requireRollbackRehearsal: Bool
    var requireProductionExecutionGuardPass: Bool
    var maxDiagnosticsEvents: Int

    nonisolated init(
        canaryMaxObjectsPerSyncRun: Int = 0,
        allowsV87CanaryN1InternalExecution: Bool = false,
        recordingMetadataCanaryStagePolicy: CanonicalRecordingMetadataCanaryStagePolicy? = nil,
        requireReadOnlyProbeForSend: Bool = true,
        requireRollbackRehearsal: Bool = true,
        requireProductionExecutionGuardPass: Bool = true,
        maxDiagnosticsEvents: Int = 200
    ) {
        self.canaryMaxObjectsPerSyncRun = max(0, canaryMaxObjectsPerSyncRun)
        self.allowsV87CanaryN1InternalExecution = allowsV87CanaryN1InternalExecution
        self.recordingMetadataCanaryStagePolicy = recordingMetadataCanaryStagePolicy
        self.requireReadOnlyProbeForSend = requireReadOnlyProbeForSend
        self.requireRollbackRehearsal = requireRollbackRehearsal
        self.requireProductionExecutionGuardPass = requireProductionExecutionGuardPass
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
    }

    nonisolated var effectiveRecordingMetadataCanaryStagePolicy: CanonicalRecordingMetadataCanaryStagePolicy {
        recordingMetadataCanaryStagePolicy ?? .disabled
    }

    nonisolated var usesExpandedRecordingMetadataStagePolicy: Bool {
        effectiveRecordingMetadataCanaryStagePolicy.requestedStage.isExpandedCanaryStage
    }
}

nonisolated struct CanonicalSingleDomainCutoverConfiguration: Codable, Equatable, Sendable {
    var domain: CanonicalCutoverDomain
    var mode: CanonicalCutoverMode
    var policy: CanonicalCutoverPolicy

    nonisolated init(
        domain: CanonicalCutoverDomain = .recordingMetadata,
        mode: CanonicalCutoverMode = .disabled,
        policy: CanonicalCutoverPolicy = CanonicalCutoverPolicy()
    ) {
        self.domain = domain
        self.mode = mode
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalSingleDomainCutoverConfiguration()

    nonisolated static func canary(
        maxObjects: Int,
        allowsV87CanaryN1InternalExecution: Bool = false
    ) -> CanonicalSingleDomainCutoverConfiguration {
        CanonicalSingleDomainCutoverConfiguration(
            mode: .canary,
            policy: CanonicalCutoverPolicy(
                canaryMaxObjectsPerSyncRun: maxObjects,
                allowsV87CanaryN1InternalExecution: allowsV87CanaryN1InternalExecution
            )
        )
    }

    nonisolated static func stagedCanary(
        stage: CanonicalRecordingMetadataCanaryStage,
        allowCandidateExecution: Bool = true
    ) -> CanonicalSingleDomainCutoverConfiguration {
        CanonicalSingleDomainCutoverConfiguration(
            mode: .canary,
            policy: CanonicalCutoverPolicy(
                canaryMaxObjectsPerSyncRun: stage.nominalCanaryBudget,
                allowsV87CanaryN1InternalExecution: stage == .n1,
                recordingMetadataCanaryStagePolicy: CanonicalRecordingMetadataCanaryStagePolicy(
                    requestedStage: stage,
                    allowCandidateExecution: allowCandidateExecution
                )
            )
        )
    }
}

nonisolated struct CanonicalCutoverToken: Codable, Equatable, Sendable {
    var tokenID: String
    var syncRunID: String
    var ownerApproved: Bool

    nonisolated init(tokenID: String, syncRunID: String, ownerApproved: Bool = false) {
        self.tokenID = CanonicalProductionRedaction.safeIdentifier(tokenID, fallback: "cutover-token")
        self.syncRunID = CanonicalProductionRedaction.safeIdentifier(syncRunID, fallback: "sync-run")
        self.ownerApproved = ownerApproved
    }
}

nonisolated enum CanonicalCutoverFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedDomain
    case modeNotExecutable
    case missingToken
    case missingOwnerApproval
    case missingRollback
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingReadOnlyTransportProbe
    case productionPortUnavailable
    case legacyFallbackUnavailable
    case viewRefreshTriggerDenied
    case retryDrainerFreshMetadataDenied
    case unsupportedAction
    case unstableMetadataHash
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case rollbackVerificationMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case missingInternalCanaryConfiguration
    case canaryBudgetAboveOneDenied
    case missingCanaryStageEvidence
    case canaryStageBlocked
    case canaryStageOrderViolation
    case observationWindowIncomplete
    case runtimeSwitchDenied
    case unsupportedObject
    case previousStageFailure
    case previousStageRollbackFailure
    case previousStageBlockingDivergence
    case previousStageUnresolvedConflict
    case preconditionMismatch
    case postconditionMismatch
    case transportFailureBeforeSend
    case applyFailureBeforeCommit
    case applyFailureAfterPartialCommit
    case rollbackFailed
}

nonisolated struct CanonicalRecordingMetadataCutoverEvidence: Codable, Equatable, Sendable {
    var realDataShadowCopyVerified: Bool
    var executionShadowVerified: Bool
    var dryRunEquivalenceVerified: Bool
    var noBlockingDivergence: Bool
    var noUnresolvedConflict: Bool
    var readOnlyTransportProbePassed: Bool
    var productionPortAvailable: Bool
    var realRootBoundApplyPortAvailable: Bool
    var applyPortMode: CanonicalRecordingMetadataApplyPortMode
    var rootBoundWriteAvailable: Bool
    var atomicReplaceAvailable: Bool
    var rollbackCheckpointAvailable: Bool
    var rollbackVerified: Bool
    var productionRootDisabledByDefault: Bool
    var testRootUsed: Bool
    var legacyFallbackAvailable: Bool
    var rollbackPlan: CanonicalRollbackPlan?
    var rollbackRehearsalPassed: Bool
    var productionExecutionGuardPassed: Bool
    var uiParallelReadEquivalent: Bool
    var canaryStageEvidence: CanonicalRecordingMetadataCanaryStageEvidence?

    nonisolated init(
        realDataShadowCopyVerified: Bool = false,
        executionShadowVerified: Bool = false,
        dryRunEquivalenceVerified: Bool = false,
        noBlockingDivergence: Bool = false,
        noUnresolvedConflict: Bool = false,
        readOnlyTransportProbePassed: Bool = false,
        productionPortAvailable: Bool = false,
        realRootBoundApplyPortAvailable: Bool = false,
        applyPortMode: CanonicalRecordingMetadataApplyPortMode = .disabled,
        rootBoundWriteAvailable: Bool = false,
        atomicReplaceAvailable: Bool = false,
        rollbackCheckpointAvailable: Bool = false,
        rollbackVerified: Bool = false,
        productionRootDisabledByDefault: Bool = false,
        testRootUsed: Bool = false,
        legacyFallbackAvailable: Bool = false,
        rollbackPlan: CanonicalRollbackPlan? = nil,
        rollbackRehearsalPassed: Bool = false,
        productionExecutionGuardPassed: Bool = false,
        uiParallelReadEquivalent: Bool = false,
        canaryStageEvidence: CanonicalRecordingMetadataCanaryStageEvidence? = nil
    ) {
        self.realDataShadowCopyVerified = realDataShadowCopyVerified
        self.executionShadowVerified = executionShadowVerified
        self.dryRunEquivalenceVerified = dryRunEquivalenceVerified
        self.noBlockingDivergence = noBlockingDivergence
        self.noUnresolvedConflict = noUnresolvedConflict
        self.readOnlyTransportProbePassed = readOnlyTransportProbePassed
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
        self.productionExecutionGuardPassed = productionExecutionGuardPassed
        self.uiParallelReadEquivalent = uiParallelReadEquivalent
        self.canaryStageEvidence = canaryStageEvidence
    }

    nonisolated static func passing(rollbackPlan: CanonicalRollbackPlan) -> CanonicalRecordingMetadataCutoverEvidence {
        CanonicalRecordingMetadataCutoverEvidence(
            realDataShadowCopyVerified: true,
            executionShadowVerified: true,
            dryRunEquivalenceVerified: true,
            noBlockingDivergence: true,
            noUnresolvedConflict: true,
            readOnlyTransportProbePassed: true,
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
            productionExecutionGuardPassed: true,
            uiParallelReadEquivalent: true
        )
    }
}

nonisolated struct CanonicalCutoverGate: Codable, Equatable, Sendable {
    var domain: CanonicalCutoverDomain
    var mode: CanonicalCutoverMode
    var allowed: Bool
    var failures: [CanonicalCutoverFailure]
    var legacyFallbackAvailable: Bool
    var reason: String

    nonisolated init(
        domain: CanonicalCutoverDomain,
        mode: CanonicalCutoverMode,
        failures: [CanonicalCutoverFailure],
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

nonisolated enum CanonicalRecordingMetadataCutoverActionKind: String, Codable, Equatable, Sendable {
    case apply
    case send
}

nonisolated struct CanonicalRecordingMetadataCutoverCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { action.actionID }

    var action: CanonicalApplyAction
    var localObject: CanonicalRecordingObject?
    var peerObject: CanonicalRecordingObject?
    var rollbackCheckpointID: String?
    var unresolvedConflict: Bool

    nonisolated init(
        action: CanonicalApplyAction,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?,
        rollbackCheckpointID: String? = nil,
        unresolvedConflict: Bool = false
    ) {
        self.action = action
        self.localObject = localObject
        self.peerObject = peerObject
        self.rollbackCheckpointID = rollbackCheckpointID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: "recording-metadata-checkpoint")
        }
        self.unresolvedConflict = unresolvedConflict
    }

    nonisolated var objectID: String {
        action.target.objectID
    }

    nonisolated var cutoverActionKind: CanonicalRecordingMetadataCutoverActionKind? {
        switch action.kind {
        case .recordingMetadataApply:
            return .apply
        case .recordingMetadataSend:
            return .send
        default:
            return nil
        }
    }

    nonisolated var requiresNetworkSend: Bool {
        cutoverActionKind == .send
    }

    nonisolated var expectedObject: CanonicalRecordingObject? {
        switch cutoverActionKind {
        case .apply:
            return peerObject
        case .send:
            return localObject
        case nil:
            return nil
        }
    }

    nonisolated var stableMetadataHash: CanonicalHash? {
        expectedObject?.metadataHash
    }

    nonisolated var effectiveRollbackCheckpointID: String {
        rollbackCheckpointID ?? "recording-metadata-cutover-\(objectID)"
    }
}

nonisolated enum CanonicalRecordingMetadataCanaryStage: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case n1
    case n3
    case n10
    case allEligible

    nonisolated var isExecutable: Bool {
        self != .disabled
    }

    nonisolated var isExpandedCanaryStage: Bool {
        switch self {
        case .n3, .n10, .allEligible:
            return true
        case .disabled, .n1:
            return false
        }
    }

    nonisolated var previousStage: CanonicalRecordingMetadataCanaryStage? {
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

nonisolated struct CanonicalRecordingMetadataCanaryStagePolicy: Codable, Equatable, Sendable {
    var requestedStage: CanonicalRecordingMetadataCanaryStage
    var allowCandidateExecution: Bool
    var runtimeSwitchEnabled: Bool

    nonisolated init(
        requestedStage: CanonicalRecordingMetadataCanaryStage = .disabled,
        allowCandidateExecution: Bool = false,
        runtimeSwitchEnabled: Bool = false
    ) {
        self.requestedStage = requestedStage
        self.allowCandidateExecution = allowCandidateExecution
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
    }

    nonisolated static let disabled = CanonicalRecordingMetadataCanaryStagePolicy()

    nonisolated var canaryBudget: Int {
        requestedStage.nominalCanaryBudget
    }
}

nonisolated enum CanonicalRecordingMetadataStageEvidenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missing
    case incomplete
    case passed
    case failed
    case blocked

    nonisolated var isPassing: Bool {
        self == .passed
    }
}

nonisolated enum CanonicalRecordingMetadataStageEvidenceBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case stageDisabled
    case unsupportedDomain
    case runtimeSwitchEnabled
    case candidateExecutionNotApproved
    case previousStageEvidenceMissing
    case stageOrderViolation
    case previousStageObservationIncomplete
    case previousStageInsufficientSuccess
    case previousStageFailure
    case previousStageRollbackFailure
    case previousStageBlockingDivergence
    case previousStageUnresolvedConflict
    case previousStagePostconditionFailure
    case previousStageUnsupportedObject
    case ownerApprovalMissing
    case rollbackPlanMissing
    case dryRunEquivalenceMissing
    case executionShadowMissing
    case realDataShadowCopyMissing
    case readOnlyTransportProbeMissing
    case productionApplyPortUnavailable
    case legacyFallbackUnavailable
    case observationWindowIncomplete
}

nonisolated struct CanonicalRecordingMetadataStageObservationWindow: Codable, Equatable, Sendable {
    var observationWindowID: String
    var complete: Bool

    nonisolated init(observationWindowID: String = "recording-metadata-stage-window", complete: Bool = false) {
        self.observationWindowID = CanonicalProductionRedaction.safeIdentifier(
            observationWindowID,
            fallback: "recording-metadata-stage-window"
        )
        self.complete = complete
    }

    nonisolated static func complete(_ id: String) -> CanonicalRecordingMetadataStageObservationWindow {
        CanonicalRecordingMetadataStageObservationWindow(observationWindowID: id, complete: true)
    }
}

nonisolated struct CanonicalRecordingMetadataCanaryStageEvidence: Codable, Equatable, Sendable {
    var previousStage: CanonicalRecordingMetadataCanaryStage
    var requestedStage: CanonicalRecordingMetadataCanaryStage
    var previousStageSuccessCount: Int
    var previousStageFailureCount: Int
    var previousStageRollbackFailureCount: Int
    var previousStageBlockingDivergenceCount: Int
    var previousStageSuppressedLegacyDuplicateCount: Int
    var unresolvedConflictCount: Int
    var previousStagePostconditionFailureCount: Int
    var previousStageUnsupportedObjectCount: Int
    var dryRunEquivalenceStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var executionShadowStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var realDataShadowCopyStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var readOnlyTransportProbeStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var rollbackPlanStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var productionApplyPortStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var legacyFallbackStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var observationWindowID: String
    var observationWindowComplete: Bool
    var ownerApproved: Bool

    nonisolated init(
        previousStage: CanonicalRecordingMetadataCanaryStage = .disabled,
        requestedStage: CanonicalRecordingMetadataCanaryStage = .disabled,
        previousStageSuccessCount: Int = 0,
        previousStageFailureCount: Int = 0,
        previousStageRollbackFailureCount: Int = 0,
        previousStageBlockingDivergenceCount: Int = 0,
        previousStageSuppressedLegacyDuplicateCount: Int = 0,
        unresolvedConflictCount: Int = 0,
        previousStagePostconditionFailureCount: Int = 0,
        previousStageUnsupportedObjectCount: Int = 0,
        dryRunEquivalenceStatus: CanonicalRecordingMetadataStageEvidenceStatus = .missing,
        executionShadowStatus: CanonicalRecordingMetadataStageEvidenceStatus = .missing,
        realDataShadowCopyStatus: CanonicalRecordingMetadataStageEvidenceStatus = .missing,
        readOnlyTransportProbeStatus: CanonicalRecordingMetadataStageEvidenceStatus = .missing,
        rollbackPlanStatus: CanonicalRecordingMetadataStageEvidenceStatus = .missing,
        productionApplyPortStatus: CanonicalRecordingMetadataStageEvidenceStatus = .missing,
        legacyFallbackStatus: CanonicalRecordingMetadataStageEvidenceStatus = .missing,
        observationWindow: CanonicalRecordingMetadataStageObservationWindow = CanonicalRecordingMetadataStageObservationWindow(),
        ownerApproved: Bool = false
    ) {
        self.previousStage = previousStage
        self.requestedStage = requestedStage
        self.previousStageSuccessCount = max(0, previousStageSuccessCount)
        self.previousStageFailureCount = max(0, previousStageFailureCount)
        self.previousStageRollbackFailureCount = max(0, previousStageRollbackFailureCount)
        self.previousStageBlockingDivergenceCount = max(0, previousStageBlockingDivergenceCount)
        self.previousStageSuppressedLegacyDuplicateCount = max(0, previousStageSuppressedLegacyDuplicateCount)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.previousStagePostconditionFailureCount = max(0, previousStagePostconditionFailureCount)
        self.previousStageUnsupportedObjectCount = max(0, previousStageUnsupportedObjectCount)
        self.dryRunEquivalenceStatus = dryRunEquivalenceStatus
        self.executionShadowStatus = executionShadowStatus
        self.realDataShadowCopyStatus = realDataShadowCopyStatus
        self.readOnlyTransportProbeStatus = readOnlyTransportProbeStatus
        self.rollbackPlanStatus = rollbackPlanStatus
        self.productionApplyPortStatus = productionApplyPortStatus
        self.legacyFallbackStatus = legacyFallbackStatus
        self.observationWindowID = observationWindow.observationWindowID
        self.observationWindowComplete = observationWindow.complete
        self.ownerApproved = ownerApproved
    }

    nonisolated static func passing(
        previousStage: CanonicalRecordingMetadataCanaryStage,
        requestedStage: CanonicalRecordingMetadataCanaryStage,
        previousStageSuccessCount: Int,
        previousStageSuppressedLegacyDuplicateCount: Int = 0,
        observationWindowID: String
    ) -> CanonicalRecordingMetadataCanaryStageEvidence {
        CanonicalRecordingMetadataCanaryStageEvidence(
            previousStage: previousStage,
            requestedStage: requestedStage,
            previousStageSuccessCount: previousStageSuccessCount,
            previousStageSuppressedLegacyDuplicateCount: previousStageSuppressedLegacyDuplicateCount,
            dryRunEquivalenceStatus: .passed,
            executionShadowStatus: .passed,
            realDataShadowCopyStatus: .passed,
            readOnlyTransportProbeStatus: .passed,
            rollbackPlanStatus: .passed,
            productionApplyPortStatus: .passed,
            legacyFallbackStatus: .passed,
            observationWindow: .complete(observationWindowID),
            ownerApproved: true
        )
    }
}

nonisolated struct CanonicalRecordingMetadataStageEvidenceReport: Codable, Equatable, Sendable {
    var status: CanonicalRecordingMetadataStageEvidenceStatus
    var blockers: [CanonicalRecordingMetadataStageEvidenceBlocker]
    var previousStage: CanonicalRecordingMetadataCanaryStage
    var requestedStage: CanonicalRecordingMetadataCanaryStage
    var previousStageSuccessCount: Int
    var previousStageFailureCount: Int
    var previousStageRollbackFailureCount: Int
    var previousStageBlockingDivergenceCount: Int
    var previousStageSuppressedLegacyDuplicateCount: Int
    var unresolvedConflictCount: Int
    var dryRunEquivalenceStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var executionShadowStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var realDataShadowCopyStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var readOnlyTransportProbeStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var rollbackPlanStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var productionApplyPortStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var legacyFallbackStatus: CanonicalRecordingMetadataStageEvidenceStatus
    var observationWindowID: String
    var observationWindowComplete: Bool
    var sensitiveFieldsRedacted: Bool

    nonisolated init(
        evidence: CanonicalRecordingMetadataCanaryStageEvidence?,
        requestedStage: CanonicalRecordingMetadataCanaryStage,
        blockers: [CanonicalRecordingMetadataStageEvidenceBlocker]
    ) {
        let normalizedBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let hasIncompleteEvidence = evidence == nil
            || evidence?.observationWindowComplete == false
            || [
                evidence?.dryRunEquivalenceStatus,
                evidence?.executionShadowStatus,
                evidence?.realDataShadowCopyStatus,
                evidence?.readOnlyTransportProbeStatus,
                evidence?.rollbackPlanStatus,
                evidence?.productionApplyPortStatus,
                evidence?.legacyFallbackStatus
            ].contains { $0 == .missing || $0 == .incomplete }
        if evidence == nil {
            self.status = .missing
        } else if normalizedBlockers.isEmpty {
            self.status = .passed
        } else if hasIncompleteEvidence {
            self.status = .incomplete
        } else {
            self.status = .blocked
        }
        self.blockers = normalizedBlockers
        self.previousStage = evidence?.previousStage ?? requestedStage.previousStage ?? .disabled
        self.requestedStage = requestedStage
        self.previousStageSuccessCount = evidence?.previousStageSuccessCount ?? 0
        self.previousStageFailureCount = evidence?.previousStageFailureCount ?? 0
        self.previousStageRollbackFailureCount = evidence?.previousStageRollbackFailureCount ?? 0
        self.previousStageBlockingDivergenceCount = evidence?.previousStageBlockingDivergenceCount ?? 0
        self.previousStageSuppressedLegacyDuplicateCount = evidence?.previousStageSuppressedLegacyDuplicateCount ?? 0
        self.unresolvedConflictCount = evidence?.unresolvedConflictCount ?? 0
        self.dryRunEquivalenceStatus = evidence?.dryRunEquivalenceStatus ?? .missing
        self.executionShadowStatus = evidence?.executionShadowStatus ?? .missing
        self.realDataShadowCopyStatus = evidence?.realDataShadowCopyStatus ?? .missing
        self.readOnlyTransportProbeStatus = evidence?.readOnlyTransportProbeStatus ?? .missing
        self.rollbackPlanStatus = evidence?.rollbackPlanStatus ?? .missing
        self.productionApplyPortStatus = evidence?.productionApplyPortStatus ?? .missing
        self.legacyFallbackStatus = evidence?.legacyFallbackStatus ?? .missing
        self.observationWindowID = evidence?.observationWindowID ?? "missing-observation-window"
        self.observationWindowComplete = evidence?.observationWindowComplete ?? false
        self.sensitiveFieldsRedacted = true
    }

    nonisolated var diagnosticsSummary: String {
        [
            "status=\(status.rawValue)",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "+"))",
            "previousStage=\(previousStage.rawValue)",
            "requestedStage=\(requestedStage.rawValue)",
            "previousStageSuccessCount=\(previousStageSuccessCount)",
            "previousStageFailureCount=\(previousStageFailureCount)",
            "previousStageRollbackFailureCount=\(previousStageRollbackFailureCount)",
            "previousStageBlockingDivergenceCount=\(previousStageBlockingDivergenceCount)",
            "previousStageSuppressedLegacyDuplicateCount=\(previousStageSuppressedLegacyDuplicateCount)",
            "unresolvedConflictCount=\(unresolvedConflictCount)",
            "dryRunEquivalenceStatus=\(dryRunEquivalenceStatus.rawValue)",
            "executionShadowStatus=\(executionShadowStatus.rawValue)",
            "realDataShadowCopyStatus=\(realDataShadowCopyStatus.rawValue)",
            "readOnlyTransportProbeStatus=\(readOnlyTransportProbeStatus.rawValue)",
            "rollbackPlanStatus=\(rollbackPlanStatus.rawValue)",
            "productionApplyPortStatus=\(productionApplyPortStatus.rawValue)",
            "legacyFallbackStatus=\(legacyFallbackStatus.rawValue)",
            "observationWindowID=\(observationWindowID)",
            "observationWindowComplete=\(observationWindowComplete)",
            "sensitiveFieldsRedacted=\(sensitiveFieldsRedacted)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalRecordingMetadataCanaryStageGate: Codable, Equatable, Sendable {
    var requestedStage: CanonicalRecordingMetadataCanaryStage
    var allowed: Bool
    var selectedCandidateLimit: Int
    var selectsAllEligible: Bool
    var blockers: [CanonicalRecordingMetadataStageEvidenceBlocker]
    var evidenceReport: CanonicalRecordingMetadataStageEvidenceReport
    var reason: String

    nonisolated init(
        policy: CanonicalRecordingMetadataCanaryStagePolicy,
        domain: CanonicalCutoverDomain,
        token: CanonicalCutoverToken?,
        cutoverEvidence: CanonicalRecordingMetadataCutoverEvidence
    ) {
        let requestedStage = policy.requestedStage
        var blockers: [CanonicalRecordingMetadataStageEvidenceBlocker] = []
        if !requestedStage.isExecutable {
            blockers.append(.stageDisabled)
        }
        if domain != .recordingMetadata {
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
        let stageEvidence = cutoverEvidence.canaryStageEvidence
        guard let stageEvidence else {
            blockers.append(.previousStageEvidenceMissing)
            self.requestedStage = requestedStage
            self.allowed = false
            self.selectedCandidateLimit = 0
            self.selectsAllEligible = false
            self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
            self.evidenceReport = CanonicalRecordingMetadataStageEvidenceReport(
                evidence: nil,
                requestedStage: requestedStage,
                blockers: self.blockers
            )
            self.reason = "recordingMetadataCanaryStageBlocked"
            return
        }

        if stageEvidence.requestedStage != requestedStage
            || stageEvidence.previousStage != (requestedStage.previousStage ?? .disabled) {
            blockers.append(.stageOrderViolation)
        }
        if stageEvidence.previousStageSuccessCount < requestedStage.minimumPreviousStageSuccessCount {
            blockers.append(.previousStageInsufficientSuccess)
        }
        if stageEvidence.previousStageFailureCount > 0 {
            blockers.append(.previousStageFailure)
        }
        if stageEvidence.previousStageRollbackFailureCount > 0 {
            blockers.append(.previousStageRollbackFailure)
        }
        if stageEvidence.previousStageBlockingDivergenceCount > 0 {
            blockers.append(.previousStageBlockingDivergence)
        }
        if stageEvidence.unresolvedConflictCount > 0 {
            blockers.append(.previousStageUnresolvedConflict)
        }
        if stageEvidence.previousStagePostconditionFailureCount > 0 {
            blockers.append(.previousStagePostconditionFailure)
        }
        if stageEvidence.previousStageUnsupportedObjectCount > 0 {
            blockers.append(.previousStageUnsupportedObject)
        }
        if !stageEvidence.observationWindowComplete {
            blockers.append(.observationWindowIncomplete)
            blockers.append(.previousStageObservationIncomplete)
        }
        if !stageEvidence.ownerApproved || token?.ownerApproved == false {
            blockers.append(.ownerApprovalMissing)
        }
        if !stageEvidence.dryRunEquivalenceStatus.isPassing || !cutoverEvidence.dryRunEquivalenceVerified {
            blockers.append(.dryRunEquivalenceMissing)
        }
        if !stageEvidence.executionShadowStatus.isPassing || !cutoverEvidence.executionShadowVerified {
            blockers.append(.executionShadowMissing)
        }
        if !stageEvidence.realDataShadowCopyStatus.isPassing || !cutoverEvidence.realDataShadowCopyVerified {
            blockers.append(.realDataShadowCopyMissing)
        }
        if !stageEvidence.readOnlyTransportProbeStatus.isPassing || !cutoverEvidence.readOnlyTransportProbePassed {
            blockers.append(.readOnlyTransportProbeMissing)
        }
        if !stageEvidence.rollbackPlanStatus.isPassing
            || cutoverEvidence.rollbackPlan?.covers(domain: .recordingMetadata) != true
            || !cutoverEvidence.rollbackRehearsalPassed
            || !cutoverEvidence.rollbackVerified {
            blockers.append(.rollbackPlanMissing)
        }
        if !stageEvidence.productionApplyPortStatus.isPassing
            || !cutoverEvidence.productionPortAvailable
            || !cutoverEvidence.realRootBoundApplyPortAvailable
            || !cutoverEvidence.applyPortMode.isNonDryRunRootBound
            || !cutoverEvidence.rootBoundWriteAvailable
            || !cutoverEvidence.atomicReplaceAvailable
            || !cutoverEvidence.rollbackCheckpointAvailable {
            blockers.append(.productionApplyPortUnavailable)
        }
        if !stageEvidence.legacyFallbackStatus.isPassing || !cutoverEvidence.legacyFallbackAvailable {
            blockers.append(.legacyFallbackUnavailable)
        }

        self.requestedStage = requestedStage
        self.allowed = blockers.isEmpty
        self.selectedCandidateLimit = requestedStage.nominalCanaryBudget
        self.selectsAllEligible = requestedStage == .allEligible
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.evidenceReport = CanonicalRecordingMetadataStageEvidenceReport(
            evidence: stageEvidence,
            requestedStage: requestedStage,
            blockers: self.blockers
        )
        self.reason = self.allowed ? "recordingMetadataCanaryStageAllowed" : "recordingMetadataCanaryStageBlocked"
    }
}

nonisolated struct CanonicalRecordingMetadataCanaryStageResult: Codable, Equatable, Sendable {
    var requestedStage: CanonicalRecordingMetadataCanaryStage
    var status: CanonicalRecordingMetadataStageEvidenceStatus
    var gate: CanonicalRecordingMetadataCanaryStageGate
    var selectedCandidateCount: Int
    var executedCandidateCount: Int
    var successCount: Int
    var failureCount: Int
    var rollbackFailureCount: Int
    var suppressedLegacyDuplicateCount: Int
    var runtimeSwitch: Bool
    var observationReport: CanonicalRecordingMetadataStageEvidenceReport

    nonisolated init(
        gate: CanonicalRecordingMetadataCanaryStageGate,
        selection: CanonicalRecordingMetadataCanarySelectionResult,
        result: CanonicalCutoverResult?
    ) {
        let successCount = result?.commits.filter { $0.committed && $0.preconditionVerified && $0.postconditionVerified }.count ?? 0
        let executedCount = result?.canaryAttemptedCount ?? 0
        let rollbackFailures = result?.rollbackResults.filter { !$0.succeeded }.count ?? 0
        self.requestedStage = gate.requestedStage
        if !gate.allowed {
            self.status = gate.evidenceReport.status
        } else if rollbackFailures > 0 || (result?.fatalBlocker == true) {
            self.status = .blocked
        } else if executedCount > 0 && successCount == executedCount {
            self.status = .passed
        } else {
            self.status = .incomplete
        }
        self.gate = gate
        self.selectedCandidateCount = selection.selectedCandidates.count
        self.executedCandidateCount = executedCount
        self.successCount = successCount
        self.failureCount = max(0, executedCount - successCount)
        self.rollbackFailureCount = rollbackFailures
        self.suppressedLegacyDuplicateCount = result?.duplicateLegacySuppressedActionIDs.count ?? 0
        self.runtimeSwitch = false
        self.observationReport = gate.evidenceReport
    }
}

nonisolated enum CanonicalRecordingMetadataCanaryBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedDomain
    case unsupportedMode
    case missingInternalCanaryConfiguration
    case canaryBudgetZero
    case canaryBudgetAboveOneDenied
    case unsupportedTrigger
    case unsupportedAction
    case insufficientEvidence
    case unresolvedConflict
    case tombstoneConflict
    case canonicalMoreAggressiveBlockingDivergence
    case noRollbackCheckpoint
    case realApplyPortUnavailable
    case missingReadOnlyTransportProbe
    case alreadyAttemptedFailedCandidate
    case rollbackUnavailable
    case canaryStageEvidenceMissing
    case canaryStageBlocked
    case noEligibleCandidate
}

nonisolated struct CanonicalRecordingMetadataCanaryCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { cutoverCandidate.action.actionID }

    var cutoverCandidate: CanonicalRecordingMetadataCutoverCandidate
    var objectID: String
    var actionKind: CanonicalRecordingMetadataCutoverActionKind
    var hashPrefix: String?

    nonisolated init(_ cutoverCandidate: CanonicalRecordingMetadataCutoverCandidate) {
        self.cutoverCandidate = cutoverCandidate
        self.objectID = CanonicalProductionRedaction.safeIdentifier(cutoverCandidate.objectID, fallback: "unknown-recording")
        self.actionKind = cutoverCandidate.cutoverActionKind ?? .apply
        self.hashPrefix = cutoverCandidate.stableMetadataHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
    }
}

nonisolated struct CanonicalRecordingMetadataCanarySelectionBlocker: Codable, Equatable, Identifiable, Sendable {
    var id: String { [objectID ?? "run", actionKind?.rawValue ?? "action", reason.rawValue].joined(separator: "|") }

    var objectID: String?
    var actionKind: CanonicalRecordingMetadataCutoverActionKind?
    var reason: CanonicalRecordingMetadataCanaryBlocker

    nonisolated init(
        objectID: String?,
        actionKind: CanonicalRecordingMetadataCutoverActionKind?,
        reason: CanonicalRecordingMetadataCanaryBlocker
    ) {
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.actionKind = actionKind
        self.reason = reason
    }
}

nonisolated struct CanonicalRecordingMetadataCanarySelectionResult: Codable, Equatable, Sendable {
    var selectedCandidates: [CanonicalRecordingMetadataCanaryCandidate]
    var blockers: [CanonicalRecordingMetadataCanarySelectionBlocker]
    var evaluatedCandidateCount: Int
    var noEligibleCandidate: Bool

    nonisolated var selectedCutoverCandidates: [CanonicalRecordingMetadataCutoverCandidate] {
        selectedCandidates.map(\.cutoverCandidate)
    }
}

nonisolated struct CanonicalRecordingMetadataCanarySelector: Sendable {
    nonisolated init() {}

    nonisolated func select(
        configuration: CanonicalSingleDomainCutoverConfiguration,
        trigger: CanonicalSyncPlanTrigger,
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        candidates: [CanonicalRecordingMetadataCutoverCandidate],
        attemptedFailedActionIDs: Set<String> = []
    ) -> CanonicalRecordingMetadataCanarySelectionResult {
        var blockers: [CanonicalRecordingMetadataCanarySelectionBlocker] = []
        let stagePolicy = configuration.policy.effectiveRecordingMetadataCanaryStagePolicy
        let usesStagePolicy = stagePolicy.requestedStage.isExecutable
        let stageGate = usesStagePolicy
            ? CanonicalRecordingMetadataCanaryStageGate(
                policy: stagePolicy,
                domain: configuration.domain,
                token: nil,
                cutoverEvidence: evidence
            )
            : nil
        if configuration.mode == .disabled {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .disabled))
        }
        if configuration.mode != .canary {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .unsupportedMode))
        }
        if configuration.domain != .recordingMetadata {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .unsupportedDomain))
        }
        if configuration.policy.canaryMaxObjectsPerSyncRun == 0 {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .canaryBudgetZero))
        }
        if configuration.policy.canaryMaxObjectsPerSyncRun > 1, !usesStagePolicy {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .canaryBudgetAboveOneDenied))
        }
        if configuration.policy.canaryMaxObjectsPerSyncRun == 1,
           !usesStagePolicy,
           !configuration.policy.allowsV87CanaryN1InternalExecution {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .missingInternalCanaryConfiguration))
        }
        if usesStagePolicy, stageGate?.allowed != true {
            let reason: CanonicalRecordingMetadataCanaryBlocker = evidence.canaryStageEvidence == nil
                ? .canaryStageEvidenceMissing
                : .canaryStageBlocked
            blockers.append(.init(objectID: nil, actionKind: nil, reason: reason))
        }
        if trigger == .viewRefresh || trigger == .retryDrainer {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .unsupportedTrigger))
        }
        let runBlocked = !blockers.isEmpty
        let selectionLimit = usesStagePolicy
            ? (stageGate?.selectedCandidateLimit ?? 0)
            : configuration.policy.canaryMaxObjectsPerSyncRun

        let orderedCandidates = candidates.sorted { lhs, rhs in
            let lhsKind = lhs.cutoverActionKind
            let rhsKind = rhs.cutoverActionKind
            let lhsRank = Self.actionRank(lhsKind)
            let rhsRank = Self.actionRank(rhsKind)
            if lhs.objectID != rhs.objectID {
                return lhs.objectID.localizedStandardCompare(rhs.objectID) == .orderedAscending
            }
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return lhs.action.actionID.localizedStandardCompare(rhs.action.actionID) == .orderedAscending
        }

        var selected: [CanonicalRecordingMetadataCanaryCandidate] = []
        for candidate in orderedCandidates {
            let reasons = Self.candidateBlockers(
                candidate,
                evidence: evidence,
                attemptedFailedActionIDs: attemptedFailedActionIDs
            )
            if reasons.isEmpty,
               !runBlocked,
               selected.count < selectionLimit {
                selected.append(CanonicalRecordingMetadataCanaryCandidate(candidate))
                continue
            }
            blockers.append(contentsOf: reasons.map {
                CanonicalRecordingMetadataCanarySelectionBlocker(
                    objectID: candidate.objectID,
                    actionKind: candidate.cutoverActionKind,
                    reason: $0
                )
            })
        }

        if selected.isEmpty, !candidates.isEmpty, blockers.isEmpty {
            blockers.append(.init(objectID: nil, actionKind: nil, reason: .noEligibleCandidate))
        }
        return CanonicalRecordingMetadataCanarySelectionResult(
            selectedCandidates: selected,
            blockers: blockers,
            evaluatedCandidateCount: candidates.count,
            noEligibleCandidate: selected.isEmpty
        )
    }

    private nonisolated static func candidateBlockers(
        _ candidate: CanonicalRecordingMetadataCutoverCandidate,
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        attemptedFailedActionIDs: Set<String>
    ) -> [CanonicalRecordingMetadataCanaryBlocker] {
        var blockers: [CanonicalRecordingMetadataCanaryBlocker] = []
        guard let actionKind = candidate.cutoverActionKind else {
            return [.unsupportedAction]
        }
        if candidate.unresolvedConflict {
            blockers.append(.unresolvedConflict)
        }
        if candidate.stableMetadataHash == nil || candidate.expectedObject == nil {
            blockers.append(.insufficientEvidence)
        }
        if candidate.localObject?.metadata.isDeleted != candidate.peerObject?.metadata.isDeleted,
           candidate.localObject != nil,
           candidate.peerObject != nil {
            blockers.append(.tombstoneConflict)
        }
        if !evidence.noBlockingDivergence {
            blockers.append(.canonicalMoreAggressiveBlockingDivergence)
        }
        if candidate.rollbackCheckpointID == nil || !evidence.rollbackCheckpointAvailable {
            blockers.append(.noRollbackCheckpoint)
        }
        if !evidence.rollbackVerified || evidence.rollbackPlan?.covers(domain: .recordingMetadata) != true {
            blockers.append(.rollbackUnavailable)
        }
        if !evidence.realRootBoundApplyPortAvailable
            || !evidence.applyPortMode.isNonDryRunRootBound
            || !evidence.rootBoundWriteAvailable
            || !evidence.atomicReplaceAvailable {
            blockers.append(.realApplyPortUnavailable)
        }
        if actionKind == .send, !evidence.readOnlyTransportProbePassed {
            blockers.append(.missingReadOnlyTransportProbe)
        }
        if attemptedFailedActionIDs.contains(candidate.action.actionID) {
            blockers.append(.alreadyAttemptedFailedCandidate)
        }
        return blockers
    }

    private nonisolated static func actionRank(_ kind: CanonicalRecordingMetadataCutoverActionKind?) -> Int {
        switch kind {
        case .apply:
            return 0
        case .send:
            return 1
        case nil:
            return 2
        }
    }
}

nonisolated enum CanonicalRecordingMetadataCanaryObservationStatus: String, Codable, Equatable, Hashable, Sendable {
    case disabled
    case blocked
    case noEligibleCandidate
    case completed
    case fatalBlocker
}

nonisolated enum CanonicalRecordingMetadataCanaryObservationBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case gateBlocked
    case noEligibleCandidate
    case commitFailure
    case rollbackFailure
    case sensitiveFieldRedactionRequired
}

nonisolated struct CanonicalRecordingMetadataCanaryObservationReport: Codable, Equatable, Sendable {
    var status: CanonicalRecordingMetadataCanaryObservationStatus
    var blockers: [CanonicalRecordingMetadataCanaryObservationBlocker]
    var canaryBudget: Int
    var selectedCandidateCount: Int
    var executedCandidateCount: Int
    var successCount: Int
    var failureCount: Int
    var rollbackCount: Int
    var rollbackFailureCount: Int
    var legacyFallbackCount: Int
    var duplicateSuppressionCount: Int
    var noEligibleCount: Int
    var fatalBlockerCount: Int
    var domain: CanonicalCutoverDomain
    var runtimeSwitch: Bool
    var legacyFallbackAvailable: Bool
    var uiMutated: Bool
    var uploadJobCreated: Bool
    var sensitiveFieldsRedacted: Bool

    nonisolated init(
        configuration: CanonicalSingleDomainCutoverConfiguration,
        selection: CanonicalRecordingMetadataCanarySelectionResult,
        result: CanonicalCutoverResult?
    ) {
        let rollbackFailures = result?.rollbackResults.filter { !$0.succeeded }.count ?? 0
        let fatalCount = result?.fatalBlocker == true ? 1 : 0
        let executedCount = result?.canaryAttemptedCount ?? 0
        let successCount = result?.commits.filter(\.committed).count ?? 0
        let failureCount = max(0, executedCount - successCount)
        let noEligible = selection.noEligibleCandidate ? 1 : 0
        let status: CanonicalRecordingMetadataCanaryObservationStatus
        if configuration.mode == .disabled {
            status = .disabled
        } else if fatalCount > 0 {
            status = .fatalBlocker
        } else if result?.gate.allowed == false {
            status = .blocked
        } else if noEligible > 0 {
            status = .noEligibleCandidate
        } else {
            status = .completed
        }
        var blockers: [CanonicalRecordingMetadataCanaryObservationBlocker] = []
        if result?.gate.allowed == false {
            blockers.append(.gateBlocked)
        }
        if noEligible > 0 {
            blockers.append(.noEligibleCandidate)
        }
        if failureCount > 0 {
            blockers.append(.commitFailure)
        }
        if rollbackFailures > 0 {
            blockers.append(.rollbackFailure)
        }
        self.status = status
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.canaryBudget = configuration.policy.canaryMaxObjectsPerSyncRun
        self.selectedCandidateCount = selection.selectedCandidates.count
        self.executedCandidateCount = executedCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.rollbackCount = result?.rollbackResults.count ?? 0
        self.rollbackFailureCount = rollbackFailures
        self.legacyFallbackCount = result?.legacyFallbackUsed == true ? 1 : 0
        self.duplicateSuppressionCount = result?.duplicateLegacySuppressedActionIDs.count ?? 0
        self.noEligibleCount = noEligible
        self.fatalBlockerCount = fatalCount
        self.domain = configuration.domain
        self.runtimeSwitch = false
        self.legacyFallbackAvailable = result?.gate.legacyFallbackAvailable ?? false
        self.uiMutated = false
        self.uploadJobCreated = false
        self.sensitiveFieldsRedacted = true
    }

    nonisolated var diagnosticsSummary: String {
        [
            "status=\(status.rawValue)",
            "canaryBudget=\(canaryBudget)",
            "selected=\(selectedCandidateCount)",
            "executed=\(executedCandidateCount)",
            "success=\(successCount)",
            "failure=\(failureCount)",
            "rollback=\(rollbackCount)",
            "rollbackFailure=\(rollbackFailureCount)",
            "legacyFallback=\(legacyFallbackCount)",
            "duplicateSuppression=\(duplicateSuppressionCount)",
            "noEligible=\(noEligibleCount)",
            "fatalBlocker=\(fatalBlockerCount)",
            "domain=\(domain.rawValue)",
            "runtimeSwitch=\(runtimeSwitch)",
            "legacyFallbackAvailable=\(legacyFallbackAvailable)",
            "uiMutated=\(uiMutated)",
            "uploadJobCreated=\(uploadJobCreated)",
            "sensitiveFieldsRedacted=\(sensitiveFieldsRedacted)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalRecordingMetadataProductionCommitFailureKind: String, Codable, Equatable, Sendable {
    case preconditionMismatch
    case postconditionMismatch
    case transportFailureBeforeSend
    case applyFailureBeforeCommit
    case applyFailureAfterPartialCommit
}

nonisolated enum CanonicalRecordingMetadataCommitFailureInjection: String, Codable, Equatable, Sendable {
    case none
    case preconditionMismatch
    case postconditionMismatch
    case applyFailureBeforeCommit
    case applyFailureAfterPartialCommit
    case transportFailureBeforeSend
    case transportFailureAfterAcceptedResponse
    case rollbackFailure
    case duplicateCommit
    case idempotentReplay
    case unsupportedSideEffect
    case unexpectedSideEffect
    case missingRollbackCheckpoint
}

nonisolated struct CanonicalRecordingMetadataProductionCommitResult: Codable, Equatable, Sendable {
    var actionID: String
    var objectID: String
    var actionKind: CanonicalRecordingMetadataCutoverActionKind
    var committed: Bool
    var partialCommit: Bool
    var preconditionVerified: Bool
    var postconditionVerified: Bool
    var routePath: String?
    var metadataHashPrefix: String?
    var sideEffect: CanonicalProductionSideEffect?
    var sideEffects: [CanonicalProductionSideEffect]
    var failureKind: CanonicalRecordingMetadataProductionCommitFailureKind?
    var reason: String

    nonisolated init(
        actionID: String,
        objectID: String,
        actionKind: CanonicalRecordingMetadataCutoverActionKind,
        committed: Bool,
        partialCommit: Bool = false,
        preconditionVerified: Bool = true,
        postconditionVerified: Bool = true,
        routePath: String? = nil,
        metadataHash: CanonicalHash? = nil,
        sideEffect: CanonicalProductionSideEffect? = nil,
        sideEffects: [CanonicalProductionSideEffect]? = nil,
        failureKind: CanonicalRecordingMetadataProductionCommitFailureKind? = nil,
        reason: String
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: actionKind.rawValue)
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.actionKind = actionKind
        self.committed = committed
        self.partialCommit = partialCommit
        self.preconditionVerified = preconditionVerified
        self.postconditionVerified = postconditionVerified
        self.routePath = routePath.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.metadataHashPrefix = metadataHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.sideEffect = sideEffect
        self.sideEffects = sideEffects ?? sideEffect.map { [$0] } ?? []
        self.failureKind = failureKind
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (committed ? "committed" : "failed")
    }

    nonisolated static func success(
        candidate: CanonicalRecordingMetadataCutoverCandidate,
        sideEffect: CanonicalProductionSideEffect? = nil
    ) -> CanonicalRecordingMetadataProductionCommitResult {
        let kind = candidate.cutoverActionKind ?? .apply
        return CanonicalRecordingMetadataProductionCommitResult(
            actionID: candidate.action.actionID,
            objectID: candidate.objectID,
            actionKind: kind,
            committed: true,
            routePath: kind == .send ? "/sync/apply-metadata" : nil,
            metadataHash: candidate.stableMetadataHash,
            sideEffect: sideEffect,
            reason: kind == .send ? "recordingMetadataSendCommitted" : "recordingMetadataApplyCommitted"
        )
    }

    nonisolated static func failure(
        candidate: CanonicalRecordingMetadataCutoverCandidate,
        kind failureKind: CanonicalRecordingMetadataProductionCommitFailureKind,
        partialCommit: Bool = false,
        reason: String
    ) -> CanonicalRecordingMetadataProductionCommitResult {
        CanonicalRecordingMetadataProductionCommitResult(
            actionID: candidate.action.actionID,
            objectID: candidate.objectID,
            actionKind: candidate.cutoverActionKind ?? .apply,
            committed: false,
            partialCommit: partialCommit,
            preconditionVerified: failureKind != .preconditionMismatch,
            postconditionVerified: failureKind != .postconditionMismatch,
            routePath: candidate.requiresNetworkSend ? "/sync/apply-metadata" : nil,
            metadataHash: candidate.stableMetadataHash,
            failureKind: failureKind,
            reason: reason
        )
    }
}

nonisolated struct CanonicalRecordingMetadataRollbackExecutionResult: Codable, Equatable, Sendable {
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
        self.checkpointID = CanonicalProductionRedaction.safeIdentifier(checkpointID, fallback: "recording-metadata-checkpoint")
        self.succeeded = succeeded
        self.fatal = fatal
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (succeeded ? "rollbackCompleted" : "rollbackFailed")
        self.rollbackResult = rollbackResult
    }
}

protocol CanonicalRecordingMetadataCutoverExecutor: Sendable {
    func commitRecordingMetadata(
        _ candidate: CanonicalRecordingMetadataCutoverCandidate
    ) async -> CanonicalRecordingMetadataProductionCommitResult

    func rollbackRecordingMetadata(
        _ candidate: CanonicalRecordingMetadataCutoverCandidate,
        reason: CanonicalCutoverFailure
    ) async -> CanonicalRecordingMetadataRollbackExecutionResult
}

nonisolated enum CanonicalRecordingMetadataCutoverDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalRecordingMetadataCutoverGateEvaluated
    case canonicalRecordingMetadataCutoverGateBlocked
    case canonicalRecordingMetadataCutoverGateAllowed
    case canonicalRecordingMetadataCanaryN1Configured
    case canonicalRecordingMetadataCanaryCandidateSelectionStarted
    case canonicalRecordingMetadataCanaryCandidateSelected
    case canonicalRecordingMetadataCanaryNoEligibleCandidate
    case canonicalRecordingMetadataCanaryStarted
    case canonicalRecordingMetadataCanaryCompleted
    case canonicalRecordingMetadataCanaryFailed
    case canonicalRecordingMetadataCanaryBudgetExhausted
    case canonicalRecordingMetadataCommitExecutorCreated
    case canonicalRecordingMetadataCommitPreconditionEvaluated
    case canonicalRecordingMetadataCommitPreconditionFailed
    case canonicalRecordingMetadataCanaryCommitStarted
    case canonicalRecordingMetadataCanaryCommitCompleted
    case canonicalRecordingMetadataCanaryCommitFailed
    case canonicalRecordingMetadataProductionCommitStarted
    case canonicalRecordingMetadataProductionCommitCompleted
    case canonicalRecordingMetadataProductionCommitFailed
    case canonicalRecordingMetadataCanaryPostconditionVerified
    case canonicalRecordingMetadataCanaryPostconditionFailed
    case canonicalRecordingMetadataPostconditionVerified
    case canonicalRecordingMetadataPostconditionFailed
    case canonicalRecordingMetadataCanaryLegacyFallbackUsed
    case canonicalRecordingMetadataLegacyFallbackUsed
    case canonicalRecordingMetadataLegacyFallbackPreserved
    case canonicalRecordingMetadataDuplicateSuppressionAllowed
    case canonicalRecordingMetadataDuplicateSuppressionSkipped
    case canonicalRecordingMetadataDuplicateLegacySuppressed
    case canonicalRecordingMetadataRollbackCheckpointCreated
    case canonicalRecordingMetadataCanaryRollbackStarted
    case canonicalRecordingMetadataCanaryRollbackCompleted
    case canonicalRecordingMetadataCanaryRollbackFailed
    case canonicalRecordingMetadataRollbackStarted
    case canonicalRecordingMetadataRollbackCompleted
    case canonicalRecordingMetadataRollbackFailed
    case canonicalRecordingMetadataCanaryFatalBlocker
    case canonicalRecordingMetadataRollbackFatalBlocker
    case canonicalUIProjectionParallelReadStarted
    case canonicalUIProjectionParallelReadEquivalent
    case canonicalUIProjectionParallelReadDivergent
    case canonicalRecordingMetadataRetirementCandidate
    case canonicalRecordingMetadataRetirementBlocked
}

nonisolated struct CanonicalRecordingMetadataCutoverDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", action ?? "", result ?? "", reason ?? ""].joined(separator: "|") }

    var kind: CanonicalRecordingMetadataCutoverDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var domain: CanonicalCutoverDomain
    var objectID: String?
    var action: String?
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalRecordingMetadataCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalCutoverDomain = .recordingMetadata,
        objectID: String? = nil,
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
        self.action = CanonicalProductionRedaction.safeDiagnosticText(action)
        self.result = CanonicalProductionRedaction.safeDiagnosticText(result)
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
        self.hashPrefix = hash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
    }
}

nonisolated struct CanonicalRecordingMetadataUIParallelProjectionResult: Codable, Equatable, Sendable {
    var objectID: String
    var equivalent: Bool
    var mutatedUI: Bool
    var canonicalHashPrefix: String?
    var displayHashPrefix: String?
    var reason: String

    nonisolated init(
        objectID: String,
        equivalent: Bool,
        canonicalHash: CanonicalHash?,
        displayHash: CanonicalHash?,
        reason: String
    ) {
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.equivalent = equivalent
        self.mutatedUI = false
        self.canonicalHashPrefix = canonicalHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.displayHashPrefix = displayHash.flatMap { CanonicalProductionRedaction.hashPrefix($0.value) }
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (equivalent ? "uiProjectionEquivalent" : "uiProjectionDivergent")
    }
}

nonisolated struct CanonicalRecordingMetadataRetirementReadiness: Codable, Equatable, Sendable {
    var retirementCandidate: Bool
    var canaryPassed: Bool
    var legacyFallbackAvailable: Bool
    var blockers: [CanonicalCutoverFailure]

    nonisolated init(
        retirementCandidate: Bool,
        canaryPassed: Bool,
        legacyFallbackAvailable: Bool,
        blockers: [CanonicalCutoverFailure]
    ) {
        self.retirementCandidate = retirementCandidate
        self.canaryPassed = canaryPassed
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }
}

nonisolated struct CanonicalCutoverResult: Codable, Equatable, Sendable {
    var gate: CanonicalCutoverGate
    var commits: [CanonicalRecordingMetadataProductionCommitResult]
    var rollbackResults: [CanonicalRecordingMetadataRollbackExecutionResult]
    var diagnostics: [CanonicalRecordingMetadataCutoverDiagnostic]
    var legacyFallbackUsed: Bool
    var duplicateLegacySuppressedActionIDs: [String]
    var canaryAttemptedCount: Int
    var canarySucceeded: Bool
    var fatalBlocker: Bool
    var uiProjection: CanonicalRecordingMetadataUIParallelProjectionResult?
    var retirementReadiness: CanonicalRecordingMetadataRetirementReadiness
    var observationReport: CanonicalRecordingMetadataCanaryObservationReport?
    var canaryStageResult: CanonicalRecordingMetadataCanaryStageResult?

    nonisolated var succeeded: Bool {
        gate.allowed && !fatalBlocker && commits.allSatisfy(\.committed)
    }
}

nonisolated struct CanonicalRecordingMetadataCutoverRunner: Sendable {
    nonisolated init() {}

    nonisolated func evaluateGate(
        configuration: CanonicalSingleDomainCutoverConfiguration,
        token: CanonicalCutoverToken?,
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        candidates: [CanonicalRecordingMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger
    ) -> CanonicalCutoverGate {
        var failures: [CanonicalCutoverFailure] = []
        if configuration.mode == .disabled {
            failures.append(.disabled)
        }
        if configuration.domain != .recordingMetadata {
            failures.append(.unsupportedDomain)
        }
        if !configuration.mode.permitsProductionCommit {
            failures.append(.modeNotExecutable)
        }
        if token == nil {
            failures.append(.missingToken)
        }
        if token?.ownerApproved != true {
            failures.append(.missingOwnerApproval)
        }
        if evidence.rollbackPlan == nil || evidence.rollbackPlan?.covers(domain: .recordingMetadata) != true {
            failures.append(.missingRollback)
        }
        if !evidence.realDataShadowCopyVerified {
            failures.append(.missingRealDataShadowCopyEvidence)
        }
        if !evidence.executionShadowVerified {
            failures.append(.missingExecutionShadowEvidence)
        }
        if !evidence.dryRunEquivalenceVerified {
            failures.append(.missingDryRunEquivalence)
        }
        if !evidence.noBlockingDivergence {
            failures.append(.blockingDivergence)
        }
        if !evidence.noUnresolvedConflict || candidates.contains(where: \.unresolvedConflict) {
            failures.append(.unresolvedConflict)
        }
        let sendNeeded = candidates.contains(where: \.requiresNetworkSend)
        if configuration.policy.requireReadOnlyProbeForSend && sendNeeded && !evidence.readOnlyTransportProbePassed {
            failures.append(.missingReadOnlyTransportProbe)
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
        if configuration.mode == .canary {
            let stagePolicy = configuration.policy.effectiveRecordingMetadataCanaryStagePolicy
            if stagePolicy.requestedStage.isExecutable {
                let stageGate = CanonicalRecordingMetadataCanaryStageGate(
                    policy: stagePolicy,
                    domain: configuration.domain,
                    token: token,
                    cutoverEvidence: evidence
                )
                if !stageGate.allowed {
                    failures.append(contentsOf: stageGate.blockers.map(Self.cutoverFailure(for:)))
                }
            } else {
                if configuration.policy.canaryMaxObjectsPerSyncRun > 1 {
                    failures.append(.canaryBudgetAboveOneDenied)
                }
                if configuration.policy.canaryMaxObjectsPerSyncRun == 1,
                   !configuration.policy.allowsV87CanaryN1InternalExecution {
                    failures.append(.missingInternalCanaryConfiguration)
                }
            }
        }
        if !evidence.legacyFallbackAvailable {
            failures.append(.legacyFallbackUnavailable)
        }
        if configuration.policy.requireRollbackRehearsal && !evidence.rollbackRehearsalPassed {
            failures.append(.missingRollback)
        }
        if configuration.policy.requireProductionExecutionGuardPass && !evidence.productionExecutionGuardPassed {
            failures.append(.productionPortUnavailable)
        }
        if trigger == .viewRefresh {
            failures.append(.viewRefreshTriggerDenied)
        }
        if trigger == .retryDrainer {
            failures.append(.retryDrainerFreshMetadataDenied)
        }
        if candidates.contains(where: { $0.cutoverActionKind == nil }) {
            failures.append(.unsupportedAction)
        }
        if candidates.contains(where: { $0.stableMetadataHash == nil }) {
            failures.append(.unstableMetadataHash)
        }
        return CanonicalCutoverGate(
            domain: configuration.domain,
            mode: configuration.mode,
            failures: failures,
            legacyFallbackAvailable: evidence.legacyFallbackAvailable,
            reason: failures.isEmpty ? "recordingMetadataCutoverGateAllowed" : "recordingMetadataCutoverGateBlocked"
        )
    }

    func run(
        configuration: CanonicalSingleDomainCutoverConfiguration,
        token: CanonicalCutoverToken?,
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        candidates: [CanonicalRecordingMetadataCutoverCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        executor: any CanonicalRecordingMetadataCutoverExecutor
    ) async -> CanonicalCutoverResult {
        let gate = evaluateGate(
            configuration: configuration,
            token: token,
            evidence: evidence,
            candidates: candidates,
            trigger: trigger
        )
        let syncRunID = token?.syncRunID
        var diagnostics: [CanonicalRecordingMetadataCutoverDiagnostic] = [
            diagnostic(.canonicalRecordingMetadataCutoverGateEvaluated, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: gate.allowed ? "allowed" : "blocked", reason: gate.reason)
        ]
        guard gate.allowed else {
            diagnostics.append(diagnostic(.canonicalRecordingMetadataCutoverGateBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "blocked", reason: gate.failures.map(\.rawValue).joined(separator: ",")))
            let fallback = evidence.legacyFallbackAvailable
            if fallback {
                diagnostics.append(diagnostic(.canonicalRecordingMetadataLegacyFallbackUsed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "legacyFallback", reason: "cutoverGateBlocked"))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataLegacyFallbackPreserved, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "legacyFallbackPreserved", reason: "cutoverGateBlocked"))
            }
            return makeResult(
                gate: gate,
                configuration: configuration,
                evidence: evidence,
                commits: [],
                rollbackResults: [],
                diagnostics: bounded(diagnostics, max: configuration.policy.maxDiagnosticsEvents),
                legacyFallbackUsed: fallback,
                duplicateSuppressed: [],
                canaryAttemptedCount: 0,
                canarySucceeded: false,
                fatalBlocker: false,
                uiProjection: nil,
                retirementBlockers: gate.failures,
                stageGate: CanonicalRecordingMetadataCanaryStageGate(
                    policy: configuration.policy.effectiveRecordingMetadataCanaryStagePolicy,
                    domain: configuration.domain,
                    token: token,
                    cutoverEvidence: evidence
                ),
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole
            )
        }
        diagnostics.append(diagnostic(.canonicalRecordingMetadataCutoverGateAllowed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "allowed", reason: "allCutoverEvidencePresent"))

        var selection = CanonicalRecordingMetadataCanarySelectionResult(
            selectedCandidates: [],
            blockers: [],
            evaluatedCandidateCount: candidates.count,
            noEligibleCandidate: candidates.isEmpty
        )
        let selected: [CanonicalRecordingMetadataCutoverCandidate]
        let stageGate = CanonicalRecordingMetadataCanaryStageGate(
            policy: configuration.policy.effectiveRecordingMetadataCanaryStagePolicy,
            domain: configuration.domain,
            token: token,
            cutoverEvidence: evidence
        )
        if configuration.mode == .canary {
            if configuration.policy.canaryMaxObjectsPerSyncRun == 1,
               configuration.policy.allowsV87CanaryN1InternalExecution {
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryN1Configured, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "configured", reason: "explicitInternalN1"))
            }
            diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryCandidateSelectionStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "started", reason: "candidateCount=\(candidates.count)"))
            selection = CanonicalRecordingMetadataCanarySelector().select(
                configuration: configuration,
                trigger: trigger,
                evidence: evidence,
                candidates: candidates
            )
            if !selection.selectedCandidates.isEmpty {
                for selectedCandidate in selection.selectedCandidates {
                    diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryCandidateSelected, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: selectedCandidate.objectID, action: selectedCandidate.actionKind.rawValue, result: "selected", reason: stageGate.requestedStage.isExecutable ? stageGate.requestedStage.rawValue : "stableOrder", hash: selectedCandidate.cutoverCandidate.stableMetadataHash))
                }
            } else if let selectedCandidate = selection.selectedCandidates.first {
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryCandidateSelected, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: selectedCandidate.objectID, action: selectedCandidate.actionKind.rawValue, result: "selected", reason: "stableOrder", hash: selectedCandidate.cutoverCandidate.stableMetadataHash))
            } else {
                let blockerReasons = selection.blockers.map(\.reason.rawValue).joined(separator: ",")
                let reason = blockerReasons.isEmpty ? "noEligibleCandidate" : blockerReasons
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryNoEligibleCandidate, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "noEligibleCandidate", reason: reason))
            }
            diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "started", reason: "max=\(configuration.policy.canaryMaxObjectsPerSyncRun)"))
            selected = selection.selectedCutoverCandidates
            if selected.count < candidates.count {
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryBudgetExhausted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "budgetExhausted", reason: "selected=\(selected.count),available=\(candidates.count)"))
            }
        } else {
            selected = candidates
        }

        if selected.isEmpty {
            diagnostics.append(diagnostic(.canonicalRecordingMetadataLegacyFallbackPreserved, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "legacyFallbackPreserved", reason: "noCanonicalCommitSelected"))
            diagnostics.append(diagnostic(.canonicalRecordingMetadataDuplicateSuppressionSkipped, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "skipped", reason: "noCanonicalCommitSelected"))
        } else {
            diagnostics.append(diagnostic(.canonicalRecordingMetadataCommitExecutorCreated, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: "created", reason: "recordingMetadataExecutor"))
        }

        var commits: [CanonicalRecordingMetadataProductionCommitResult] = []
        var rollbacks: [CanonicalRecordingMetadataRollbackExecutionResult] = []
        var duplicateSuppressed: [String] = []
        var legacyFallbackUsed = false
        var fatalBlocker = false
        var retirementBlockers: [CanonicalCutoverFailure] = []

        for candidate in selected {
            diagnostics.append(diagnostic(.canonicalRecordingMetadataRollbackCheckpointCreated, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "checkpointCreated", reason: candidate.effectiveRollbackCheckpointID))
            diagnostics.append(diagnostic(.canonicalRecordingMetadataCommitPreconditionEvaluated, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "evaluated", reason: "objectHashRouteRollbackCanary", hash: candidate.stableMetadataHash))
            diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryCommitStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "started", reason: "recordingMetadataOnly", hash: candidate.stableMetadataHash))
            diagnostics.append(diagnostic(.canonicalRecordingMetadataProductionCommitStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "started", reason: "recordingMetadataOnly", hash: candidate.stableMetadataHash))
            let commit = await executor.commitRecordingMetadata(candidate)
            commits.append(commit)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryPostconditionVerified, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "verified", reason: commit.reason, hash: candidate.stableMetadataHash))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataPostconditionVerified, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "verified", reason: commit.reason, hash: candidate.stableMetadataHash))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryCommitCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "committed", reason: commit.reason, hash: candidate.stableMetadataHash))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataProductionCommitCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "committed", reason: commit.reason, hash: candidate.stableMetadataHash))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataDuplicateSuppressionAllowed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "allowed", reason: "canonicalCommitSucceeded"))
                duplicateSuppressed.append(candidate.action.actionID)
                diagnostics.append(diagnostic(.canonicalRecordingMetadataDuplicateLegacySuppressed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "suppressed", reason: "canonicalCommitSucceeded"))
                continue
            }

            let failure = cutoverFailure(for: commit.failureKind)
            retirementBlockers.append(failure)
            if failure == .preconditionMismatch {
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCommitPreconditionFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "failed", reason: commit.reason, hash: candidate.stableMetadataHash))
            }
            if failure == .postconditionMismatch {
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryPostconditionFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "failed", reason: commit.reason, hash: candidate.stableMetadataHash))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataPostconditionFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "failed", reason: commit.reason, hash: candidate.stableMetadataHash))
            }
            diagnostics.append(diagnostic(.canonicalRecordingMetadataDuplicateSuppressionSkipped, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "skipped", reason: failure.rawValue))
            diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryCommitFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "failed", reason: failure.rawValue, hash: candidate.stableMetadataHash))
            diagnostics.append(diagnostic(.canonicalRecordingMetadataProductionCommitFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "failed", reason: failure.rawValue, hash: candidate.stableMetadataHash))
            diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryRollbackStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "started", reason: failure.rawValue))
            diagnostics.append(diagnostic(.canonicalRecordingMetadataRollbackStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "started", reason: failure.rawValue))
            let rollback = await executor.rollbackRecordingMetadata(candidate, reason: failure)
            rollbacks.append(rollback)
            if rollback.succeeded {
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryRollbackCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "rolledBack", reason: rollback.reason))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataRollbackCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "rolledBack", reason: rollback.reason))
                if evidence.legacyFallbackAvailable {
                    legacyFallbackUsed = true
                    diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryLegacyFallbackUsed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "legacyFallback", reason: "canonicalPrecommitOrCanaryFailed"))
                    diagnostics.append(diagnostic(.canonicalRecordingMetadataLegacyFallbackUsed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "legacyFallback", reason: "canonicalPrecommitOrCanaryFailed"))
                    diagnostics.append(diagnostic(.canonicalRecordingMetadataLegacyFallbackPreserved, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "legacyFallbackPreserved", reason: "canonicalPrecommitOrCanaryFailed"))
                }
            } else {
                fatalBlocker = true
                retirementBlockers.append(.rollbackFailed)
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryRollbackFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "fatal", reason: rollback.reason))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataRollbackFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "fatal", reason: rollback.reason))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryFatalBlocker, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "fatalBlocker", reason: rollback.reason))
                diagnostics.append(diagnostic(.canonicalRecordingMetadataRollbackFatalBlocker, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "fatalBlocker", reason: rollback.reason))
            }
            if configuration.mode == .canary {
                diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryFailed, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidate.objectID, action: candidate.action.kind.rawValue, result: "failed", reason: failure.rawValue))
            }
            break
        }

        let canarySucceeded = configuration.mode == .canary
            && !selected.isEmpty
            && commits.count == selected.count
            && commits.allSatisfy { $0.committed && $0.preconditionVerified && $0.postconditionVerified }
            && !fatalBlocker
        if configuration.mode == .canary {
            diagnostics.append(diagnostic(.canonicalRecordingMetadataCanaryCompleted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: canarySucceeded ? "passed" : "completed", reason: "attempted=\(selected.count)"))
        }

        let uiProjection = makeUIProjection(evidence: evidence, candidate: candidates.first)
        diagnostics.append(diagnostic(.canonicalUIProjectionParallelReadStarted, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidates.first?.objectID, result: "started", reason: "diagnosticsOnly"))
        diagnostics.append(diagnostic(evidence.uiParallelReadEquivalent ? .canonicalUIProjectionParallelReadEquivalent : .canonicalUIProjectionParallelReadDivergent, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, objectID: candidates.first?.objectID, result: evidence.uiParallelReadEquivalent ? "equivalent" : "divergent", reason: "displayUnchanged", hash: candidates.first?.stableMetadataHash))

        return makeResult(
            gate: gate,
            configuration: configuration,
            evidence: evidence,
            commits: commits,
            rollbackResults: rollbacks,
            diagnostics: bounded(diagnostics, max: configuration.policy.maxDiagnosticsEvents),
            legacyFallbackUsed: legacyFallbackUsed,
            duplicateSuppressed: duplicateSuppressed,
            canaryAttemptedCount: selected.count,
            canarySucceeded: canarySucceeded,
            fatalBlocker: fatalBlocker,
            uiProjection: uiProjection,
            retirementBlockers: retirementBlockers,
            selection: selection,
            stageGate: stageGate,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole
        )
    }

    private nonisolated func makeResult(
        gate: CanonicalCutoverGate,
        configuration: CanonicalSingleDomainCutoverConfiguration,
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        commits: [CanonicalRecordingMetadataProductionCommitResult],
        rollbackResults: [CanonicalRecordingMetadataRollbackExecutionResult],
        diagnostics: [CanonicalRecordingMetadataCutoverDiagnostic],
        legacyFallbackUsed: Bool,
        duplicateSuppressed: [String],
        canaryAttemptedCount: Int,
        canarySucceeded: Bool,
        fatalBlocker: Bool,
        uiProjection: CanonicalRecordingMetadataUIParallelProjectionResult?,
        retirementBlockers: [CanonicalCutoverFailure],
        selection: CanonicalRecordingMetadataCanarySelectionResult? = nil,
        stageGate: CanonicalRecordingMetadataCanaryStageGate,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole
    ) -> CanonicalCutoverResult {
        var blockers = retirementBlockers + gate.failures
        if !canarySucceeded {
            blockers.append(.modeNotExecutable)
        }
        if !evidence.uiParallelReadEquivalent {
            blockers.append(.blockingDivergence)
        }
        let retirementCandidate = gate.allowed
            && canarySucceeded
            && !fatalBlocker
            && blockers.isEmpty
            && evidence.rollbackRehearsalPassed
            && evidence.legacyFallbackAvailable
        var allDiagnostics = diagnostics
        allDiagnostics.append(diagnostic(retirementCandidate ? .canonicalRecordingMetadataRetirementCandidate : .canonicalRecordingMetadataRetirementBlocked, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole, result: retirementCandidate ? "candidate" : "blocked", reason: retirementCandidate ? "recordingMetadataOnly" : Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: ",")))
        let provisionalResult = CanonicalCutoverResult(
            gate: gate,
            commits: commits,
            rollbackResults: rollbackResults,
            diagnostics: allDiagnostics,
            legacyFallbackUsed: legacyFallbackUsed,
            duplicateLegacySuppressedActionIDs: Array(Set(duplicateSuppressed)).sorted(),
            canaryAttemptedCount: canaryAttemptedCount,
            canarySucceeded: canarySucceeded,
            fatalBlocker: fatalBlocker,
            uiProjection: uiProjection,
            retirementReadiness: CanonicalRecordingMetadataRetirementReadiness(
                retirementCandidate: retirementCandidate,
                canaryPassed: canarySucceeded,
                legacyFallbackAvailable: evidence.legacyFallbackAvailable,
                blockers: blockers
            ),
            observationReport: nil,
            canaryStageResult: nil
        )
        let selection = selection ?? CanonicalRecordingMetadataCanarySelectionResult(
            selectedCandidates: commits.map { commit in
                CanonicalRecordingMetadataCanaryCandidate(
                    CanonicalRecordingMetadataCutoverCandidate(
                        action: CanonicalApplyAction(
                            kind: commit.actionKind == .send ? .recordingMetadataSend : .recordingMetadataApply,
                            source: commit.actionKind == .send ? .local : .peer,
                            target: CanonicalApplyTarget(objectID: commit.objectID),
                            bridgeHint: commit.actionKind == .send ? .legacyMetadataManifestSend : .legacyMetadataManifestApply,
                            reason: commit.actionKind == .send ? CanonicalApplyActionKind.recordingMetadataSend.rawValue : CanonicalApplyActionKind.recordingMetadataApply.rawValue
                        ),
                        localObject: nil,
                        peerObject: nil
                    )
                )
            },
            blockers: [],
            evaluatedCandidateCount: commits.count,
            noEligibleCandidate: commits.isEmpty
        )
        var result = provisionalResult
        result.observationReport = CanonicalRecordingMetadataCanaryObservationReport(
            configuration: configuration,
            selection: selection,
            result: provisionalResult
        )
        if configuration.policy.effectiveRecordingMetadataCanaryStagePolicy.requestedStage.isExecutable {
            result.canaryStageResult = CanonicalRecordingMetadataCanaryStageResult(
                gate: stageGate,
                selection: selection,
                result: provisionalResult
            )
        }
        return result
    }

    private nonisolated func makeUIProjection(
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        candidate: CanonicalRecordingMetadataCutoverCandidate?
    ) -> CanonicalRecordingMetadataUIParallelProjectionResult? {
        guard let candidate, let expected = candidate.expectedObject else {
            return nil
        }
        return CanonicalRecordingMetadataUIParallelProjectionResult(
            objectID: candidate.objectID,
            equivalent: evidence.uiParallelReadEquivalent,
            canonicalHash: expected.metadataHash,
            displayHash: evidence.uiParallelReadEquivalent ? expected.metadataHash : candidate.localObject?.metadataHash,
            reason: evidence.uiParallelReadEquivalent ? "uiProjectionEquivalent" : "uiProjectionDivergent"
        )
    }

    private nonisolated func cutoverFailure(
        for failureKind: CanonicalRecordingMetadataProductionCommitFailureKind?
    ) -> CanonicalCutoverFailure {
        switch failureKind {
        case .preconditionMismatch:
            return .preconditionMismatch
        case .postconditionMismatch:
            return .postconditionMismatch
        case .transportFailureBeforeSend:
            return .transportFailureBeforeSend
        case .applyFailureBeforeCommit:
            return .applyFailureBeforeCommit
        case .applyFailureAfterPartialCommit:
            return .applyFailureAfterPartialCommit
        case nil:
            return .postconditionMismatch
        }
    }

    private nonisolated static func cutoverFailure(
        for blocker: CanonicalRecordingMetadataStageEvidenceBlocker
    ) -> CanonicalCutoverFailure {
        switch blocker {
        case .stageDisabled, .candidateExecutionNotApproved:
            return .modeNotExecutable
        case .unsupportedDomain:
            return .unsupportedDomain
        case .runtimeSwitchEnabled:
            return .runtimeSwitchDenied
        case .previousStageEvidenceMissing:
            return .missingCanaryStageEvidence
        case .stageOrderViolation:
            return .canaryStageOrderViolation
        case .previousStageObservationIncomplete, .observationWindowIncomplete:
            return .observationWindowIncomplete
        case .previousStageInsufficientSuccess:
            return .canaryStageBlocked
        case .previousStageFailure:
            return .previousStageFailure
        case .previousStageRollbackFailure:
            return .previousStageRollbackFailure
        case .previousStageBlockingDivergence:
            return .previousStageBlockingDivergence
        case .previousStageUnresolvedConflict:
            return .previousStageUnresolvedConflict
        case .previousStagePostconditionFailure:
            return .postconditionMismatch
        case .previousStageUnsupportedObject:
            return .unsupportedObject
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
            return .missingReadOnlyTransportProbe
        case .productionApplyPortUnavailable:
            return .productionPortUnavailable
        case .legacyFallbackUnavailable:
            return .legacyFallbackUnavailable
        }
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalRecordingMetadataCutoverDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        objectID: String? = nil,
        action: String? = nil,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalRecordingMetadataCutoverDiagnostic {
        CanonicalRecordingMetadataCutoverDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            objectID: objectID,
            action: action,
            result: result,
            reason: reason,
            hash: hash
        )
    }

    private nonisolated func bounded(
        _ diagnostics: [CanonicalRecordingMetadataCutoverDiagnostic],
        max: Int
    ) -> [CanonicalRecordingMetadataCutoverDiagnostic] {
        Array(diagnostics.prefix(max))
    }
}

nonisolated enum CanonicalCutoverAppSeamMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case guardedExecuteNoCommit
    case guardedExecuteCommit
    case productionExecute
    case canaryCommit
}

nonisolated struct CanonicalCutoverAppSeamPolicy: Codable, Equatable, Sendable {
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int
    var requireCutoverEvidence: Bool
    var blockCanonicalMoreAggressive: Bool
    var blockInsufficientEvidence: Bool
    var blockUnsupported: Bool
    var blockDivergence: Bool
    var canaryMaxObjectsPerSyncRun: Int?
    var allowsV87CanaryN1InternalExecution: Bool
    var recordingMetadataCanaryStagePolicy: CanonicalRecordingMetadataCanaryStagePolicy?

    nonisolated init(
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 200,
        requireCutoverEvidence: Bool = true,
        blockCanonicalMoreAggressive: Bool = true,
        blockInsufficientEvidence: Bool = true,
        blockUnsupported: Bool = true,
        blockDivergence: Bool = true,
        canaryMaxObjectsPerSyncRun: Int? = 0,
        allowsV87CanaryN1InternalExecution: Bool = false,
        recordingMetadataCanaryStagePolicy: CanonicalRecordingMetadataCanaryStagePolicy? = nil
    ) {
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
        self.requireCutoverEvidence = requireCutoverEvidence
        self.blockCanonicalMoreAggressive = blockCanonicalMoreAggressive
        self.blockInsufficientEvidence = blockInsufficientEvidence
        self.blockUnsupported = blockUnsupported
        self.blockDivergence = blockDivergence
        self.canaryMaxObjectsPerSyncRun = canaryMaxObjectsPerSyncRun.map { max(0, $0) }
        self.allowsV87CanaryN1InternalExecution = allowsV87CanaryN1InternalExecution
        self.recordingMetadataCanaryStagePolicy = recordingMetadataCanaryStagePolicy
    }

    nonisolated var effectiveCanaryMaxObjectsPerSyncRun: Int {
        max(0, canaryMaxObjectsPerSyncRun ?? 0)
    }

    nonisolated var effectiveRecordingMetadataCanaryStagePolicy: CanonicalRecordingMetadataCanaryStagePolicy {
        recordingMetadataCanaryStagePolicy ?? .disabled
    }
}

nonisolated struct CanonicalCutoverAppSeamConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var domain: CanonicalCutoverDomain
    var mode: CanonicalCutoverAppSeamMode
    var policy: CanonicalCutoverAppSeamPolicy
    var evidence: CanonicalRecordingMetadataCutoverEvidence
    var cutoverToken: CanonicalCutoverToken?

    nonisolated init(
        isEnabled: Bool = false,
        domain: CanonicalCutoverDomain = .recordingMetadata,
        mode: CanonicalCutoverAppSeamMode = .disabled,
        policy: CanonicalCutoverAppSeamPolicy = CanonicalCutoverAppSeamPolicy(),
        evidence: CanonicalRecordingMetadataCutoverEvidence = CanonicalRecordingMetadataCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) {
        self.isEnabled = isEnabled
        self.domain = domain
        self.mode = isEnabled ? mode : .disabled
        self.policy = policy
        self.evidence = evidence
        self.cutoverToken = cutoverToken
    }

    nonisolated static let disabled = CanonicalCutoverAppSeamConfiguration()

    nonisolated static func enabled(
        domain: CanonicalCutoverDomain = .recordingMetadata,
        mode: CanonicalCutoverAppSeamMode = .guardedExecuteNoCommit,
        policy: CanonicalCutoverAppSeamPolicy = CanonicalCutoverAppSeamPolicy(),
        evidence: CanonicalRecordingMetadataCutoverEvidence = CanonicalRecordingMetadataCutoverEvidence(),
        cutoverToken: CanonicalCutoverToken? = nil
    ) -> CanonicalCutoverAppSeamConfiguration {
        CanonicalCutoverAppSeamConfiguration(
            isEnabled: true,
            domain: domain,
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

nonisolated enum CanonicalCutoverAppSeamFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedDomain
    case unsupportedMode
    case guardedExecuteCommitDenied
    case productionExecuteDenied
    case canaryCommitDenied
    case viewRefreshTriggerDenied
    case retryDrainerFreshMetadataDenied
    case insufficientLocalSnapshot
    case insufficientPeerSnapshot
    case insufficientEvidence
    case unresolvedConflict
    case unsupportedAction
    case unstableMetadataHash
}

nonisolated struct CanonicalCutoverAppSeamGate: Codable, Equatable, Sendable {
    var domain: CanonicalCutoverDomain
    var mode: CanonicalCutoverAppSeamMode
    var allowed: Bool
    var failures: [CanonicalCutoverAppSeamFailure]
    var reason: String

    nonisolated init(
        domain: CanonicalCutoverDomain,
        mode: CanonicalCutoverAppSeamMode,
        failures: [CanonicalCutoverAppSeamFailure],
        reason: String
    ) {
        self.domain = domain
        self.mode = mode
        self.failures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = self.failures.isEmpty
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (self.failures.isEmpty ? "allowed" : "blocked")
    }
}

nonisolated enum CanonicalRecordingMetadataNoCommitDirection: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case none
    case apply
    case send
}

nonisolated enum CanonicalRecordingMetadataNoCommitOutcome: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case noCommitWouldApply
    case noCommitWouldSend
    case noCommitEquivalent
    case noCommitDivergent
    case noCommitBlocked
    case noCommitInsufficientEvidence
    case noCommitProductionCommitSuppressed
}

nonisolated enum CanonicalRecordingMetadataNoCommitEquivalenceStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case equivalent
    case canonicalMoreConservative
    case canonicalMoreAggressive
    case divergent
    case insufficientEvidence
    case unsupported
    case blocked
}

nonisolated enum CanonicalRecordingMetadataNoCommitFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case appSeamBlocked
    case unsupportedAction
    case unsupportedNoCommitPayloadBuilder
    case insufficientEvidence
    case canonicalMoreAggressive
    case divergent
    case stagingFailed
    case productionCommitSuppressed
}

nonisolated struct CanonicalRecordingMetadataNoCommitCandidate: Codable, Equatable, Identifiable, Sendable {
    var id: String { cutoverCandidate.id }

    var cutoverCandidate: CanonicalRecordingMetadataCutoverCandidate
    var legacyDirection: CanonicalRecordingMetadataNoCommitDirection
    var legacyObjectID: String?
    var legacyPayloadByteCount: Int?
    var legacyPayloadHashPrefix: String?
    var expectedRoutePath: String?

    nonisolated init(
        cutoverCandidate: CanonicalRecordingMetadataCutoverCandidate,
        legacyDirection: CanonicalRecordingMetadataNoCommitDirection,
        legacyObjectID: String? = nil,
        legacyPayloadByteCount: Int? = nil,
        legacyPayloadHashPrefix: String? = nil,
        expectedRoutePath: String? = nil
    ) {
        self.cutoverCandidate = cutoverCandidate
        self.legacyDirection = legacyDirection
        self.legacyObjectID = legacyObjectID.map {
            CanonicalProductionRedaction.safeIdentifier($0, fallback: cutoverCandidate.objectID)
        }
        self.legacyPayloadByteCount = legacyPayloadByteCount
        self.legacyPayloadHashPrefix = CanonicalProductionRedaction.hashPrefix(legacyPayloadHashPrefix)
        self.expectedRoutePath = expectedRoutePath.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
    }

    nonisolated var canonicalDirection: CanonicalRecordingMetadataNoCommitDirection {
        switch cutoverCandidate.cutoverActionKind {
        case .apply:
            return .apply
        case .send:
            return .send
        case nil:
            return .none
        }
    }

    nonisolated var objectID: String {
        cutoverCandidate.objectID
    }
}

nonisolated struct CanonicalRecordingMetadataNoCommitPayloadSummary: Codable, Equatable, Sendable {
    var schema: String
    var actionID: String
    var objectID: String
    var direction: CanonicalRecordingMetadataNoCommitDirection
    var bridgeHint: CanonicalApplyBridgeHint?
    var routePath: String?
    var metadataHashPrefix: String?
    var modifiedAtUnixSeconds: String?
    var tombstone: Bool

    nonisolated init(candidate: CanonicalRecordingMetadataNoCommitCandidate) {
        let expected = candidate.cutoverCandidate.expectedObject
        self.schema = "canonical-recording-metadata-no-commit-v8"
        self.actionID = CanonicalProductionRedaction.safeIdentifier(
            candidate.cutoverCandidate.action.actionID,
            fallback: candidate.canonicalDirection.rawValue
        )
        self.objectID = CanonicalProductionRedaction.safeIdentifier(candidate.objectID, fallback: "unknown-recording")
        self.direction = candidate.canonicalDirection
        self.bridgeHint = candidate.cutoverCandidate.action.bridgeHint
        self.routePath = candidate.canonicalDirection == .send ? "/sync/apply-metadata" : nil
        self.metadataHashPrefix = CanonicalProductionRedaction.hashPrefix(expected?.metadataHash.value)
        if let modifiedAt = expected?.metadata.modifiedAt.date {
            self.modifiedAtUnixSeconds = Self.numberString(modifiedAt.timeIntervalSince1970)
        } else {
            self.modifiedAtUnixSeconds = nil
        }
        self.tombstone = expected?.metadata.isDeleted ?? false
    }

    nonisolated func encodedBytes() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    nonisolated private static func numberString(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

nonisolated struct CanonicalRecordingMetadataNoCommitStagingResult: Codable, Equatable, Sendable {
    var actionID: String
    var objectID: String
    var direction: CanonicalRecordingMetadataNoCommitDirection
    var staged: Bool
    var wroteOnlyStagingRoot: Bool
    var wouldApply: Bool
    var wouldSend: Bool
    var routePath: String?
    var stagedLogicalPathToken: String?
    var payloadByteCount: Int?
    var payloadHashPrefix: String?
    var metadataHashPrefix: String?
    var calledApplySyncManifest: Bool
    var sentNetworkRequest: Bool
    var wroteProductionStore: Bool
    var suppressedLegacyDuplicate: Bool
    var stagingEvidence: CanonicalNoCommitStagingEvidence?
    var cleanupEvidence: CanonicalNoCommitCleanupEvidence?
    var failure: CanonicalRecordingMetadataNoCommitFailure?
    var reason: String

    nonisolated init(
        candidate: CanonicalRecordingMetadataNoCommitCandidate,
        staged: Bool,
        wroteOnlyStagingRoot: Bool,
        routePath: String? = nil,
        stagedLogicalPathToken: String? = nil,
        payloadByteCount: Int? = nil,
        payloadHashPrefix: String? = nil,
        stagingEvidence: CanonicalNoCommitStagingEvidence? = nil,
        cleanupEvidence: CanonicalNoCommitCleanupEvidence? = nil,
        failure: CanonicalRecordingMetadataNoCommitFailure? = nil,
        reason: String
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(
            candidate.cutoverCandidate.action.actionID,
            fallback: candidate.canonicalDirection.rawValue
        )
        self.objectID = CanonicalProductionRedaction.safeIdentifier(candidate.objectID, fallback: "unknown-recording")
        self.direction = candidate.canonicalDirection
        self.staged = staged
        self.wroteOnlyStagingRoot = wroteOnlyStagingRoot
        self.wouldApply = candidate.canonicalDirection == .apply
        self.wouldSend = candidate.canonicalDirection == .send
        self.routePath = routePath.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.stagedLogicalPathToken = CanonicalProjectionContract.safeLogicalPathToken(stagedLogicalPathToken)
        self.payloadByteCount = payloadByteCount
        self.payloadHashPrefix = CanonicalProductionRedaction.hashPrefix(payloadHashPrefix)
        self.metadataHashPrefix = candidate.cutoverCandidate.stableMetadataHash.flatMap {
            CanonicalProductionRedaction.hashPrefix($0.value)
        }
        self.calledApplySyncManifest = false
        self.sentNetworkRequest = false
        self.wroteProductionStore = false
        self.suppressedLegacyDuplicate = false
        self.stagingEvidence = stagingEvidence
        self.cleanupEvidence = cleanupEvidence
        self.failure = failure
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (staged ? "noCommitStaged" : "noCommitFailed")
    }
}

protocol CanonicalRecordingMetadataNoCommitExecutor: Sendable {
    nonisolated func stageNoCommit(
        _ candidate: CanonicalRecordingMetadataNoCommitCandidate
    ) -> CanonicalRecordingMetadataNoCommitStagingResult
}

nonisolated struct CanonicalRecordingMetadataNoCommitEquivalence: Codable, Equatable, Sendable {
    var status: CanonicalRecordingMetadataNoCommitEquivalenceStatus
    var blocking: Bool
    var reasons: [String]
    var canonicalDirection: CanonicalRecordingMetadataNoCommitDirection
    var legacyDirection: CanonicalRecordingMetadataNoCommitDirection
    var metadataHashPrefix: String?
    var modifiedAtDirection: String?
    var tombstoneState: String
    var routePath: String?
    var payloadByteCount: Int?
    var payloadHashPrefix: String?

    nonisolated init(
        status: CanonicalRecordingMetadataNoCommitEquivalenceStatus,
        blocking: Bool,
        reasons: [String],
        canonicalDirection: CanonicalRecordingMetadataNoCommitDirection,
        legacyDirection: CanonicalRecordingMetadataNoCommitDirection,
        metadataHashPrefix: String?,
        modifiedAtDirection: String?,
        tombstoneState: String,
        routePath: String?,
        payloadByteCount: Int?,
        payloadHashPrefix: String?
    ) {
        self.status = status
        self.blocking = blocking
        self.reasons = Array(Set(reasons.compactMap(CanonicalProductionRedaction.safeDiagnosticText))).sorted()
        self.canonicalDirection = canonicalDirection
        self.legacyDirection = legacyDirection
        self.metadataHashPrefix = CanonicalProductionRedaction.hashPrefix(metadataHashPrefix)
        self.modifiedAtDirection = CanonicalProductionRedaction.safeDiagnosticText(modifiedAtDirection)
        self.tombstoneState = CanonicalProductionRedaction.safeDiagnosticText(tombstoneState) ?? "unknown"
        self.routePath = routePath.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.payloadByteCount = payloadByteCount
        self.payloadHashPrefix = CanonicalProductionRedaction.hashPrefix(payloadHashPrefix)
    }
}

nonisolated enum CanonicalV8RecordingMetadataNoCommitDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalV8CutoverSeamStarted
    case canonicalV8CutoverSeamCompleted
    case canonicalV8CutoverSeamBlocked
    case canonicalV8RecordingMetadataNoCommitStarted
    case canonicalV8RecordingMetadataNoCommitCompleted
    case canonicalV8RecordingMetadataNoCommitDivergent
    case canonicalV8RecordingMetadataNoCommitEquivalent
    case canonicalV8RecordingMetadataNoCommitProductionCommitSuppressed
    case canonicalV8RecordingMetadataNoCommitInsufficientEvidence
    case canonicalV8RecordingMetadataNoCommitUnsupported
    case canonicalV8RecordingMetadataNoCommitLegacyFallbackPreserved
    case canonicalV8NoCommitStagingRootCreated
    case canonicalV8NoCommitStagingRootCleaned
    case canonicalV8NoCommitStagingRootCleanupFailed
    case canonicalV8NoCommitEvidenceReportBuilt
    case canonicalV8NoCommitEquivalent
    case canonicalV8NoCommitDivergent
    case canonicalV8NoCommitCommitSuppressed
    case canonicalV8NoCommitLegacyDuplicatePreserved
    case canonicalV8NoCommitConfigStageResolved
    case canonicalV8NoCommitConfigBlocked
}

nonisolated struct CanonicalV8RecordingMetadataNoCommitDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", result ?? "", reason ?? ""].joined(separator: "|") }

    var kind: CanonicalV8RecordingMetadataNoCommitDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var domain: CanonicalCutoverDomain
    var mode: CanonicalCutoverAppSeamMode
    var objectID: String?
    var candidateCount: Int
    var equivalentCount: Int
    var divergentCount: Int
    var blockerCount: Int
    var result: String?
    var reason: String?
    var hashPrefix: String?
    var routePath: String?

    nonisolated init(
        kind: CanonicalV8RecordingMetadataNoCommitDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalCutoverDomain = .recordingMetadata,
        mode: CanonicalCutoverAppSeamMode,
        objectID: String? = nil,
        candidateCount: Int = 0,
        equivalentCount: Int = 0,
        divergentCount: Int = 0,
        blockerCount: Int = 0,
        result: String? = nil,
        reason: String? = nil,
        hashPrefix: String? = nil,
        routePath: String? = nil
    ) {
        self.kind = kind
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.domain = domain
        self.mode = mode
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
        self.candidateCount = max(0, candidateCount)
        self.equivalentCount = max(0, equivalentCount)
        self.divergentCount = max(0, divergentCount)
        self.blockerCount = max(0, blockerCount)
        self.result = CanonicalProductionRedaction.safeDiagnosticText(result)
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
        self.hashPrefix = CanonicalProductionRedaction.hashPrefix(hashPrefix)
        self.routePath = routePath.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
    }

    nonisolated var diagnosticsSummary: String {
        [
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            "domain=\(domain.rawValue)",
            "mode=\(mode.rawValue)",
            "candidateCount=\(candidateCount)",
            "equivalentCount=\(equivalentCount)",
            "divergentCount=\(divergentCount)",
            "blockerCount=\(blockerCount)",
            result.map { "result=\($0)" },
            reason.map { "reason=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" },
            routePath.map { "route=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated struct CanonicalRecordingMetadataNoCommitCandidateResult: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID }

    var actionID: String
    var objectID: String
    var outcomes: [CanonicalRecordingMetadataNoCommitOutcome]
    var equivalence: CanonicalRecordingMetadataNoCommitEquivalence
    var staging: CanonicalRecordingMetadataNoCommitStagingResult?
    var failure: CanonicalRecordingMetadataNoCommitFailure?

    nonisolated init(
        candidate: CanonicalRecordingMetadataNoCommitCandidate,
        outcomes: [CanonicalRecordingMetadataNoCommitOutcome],
        equivalence: CanonicalRecordingMetadataNoCommitEquivalence,
        staging: CanonicalRecordingMetadataNoCommitStagingResult?,
        failure: CanonicalRecordingMetadataNoCommitFailure?
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(
            candidate.cutoverCandidate.action.actionID,
            fallback: candidate.canonicalDirection.rawValue
        )
        self.objectID = CanonicalProductionRedaction.safeIdentifier(candidate.objectID, fallback: "unknown-recording")
        self.outcomes = Array(Set(outcomes)).sorted { $0.rawValue < $1.rawValue }
        self.equivalence = equivalence
        self.staging = staging
        self.failure = failure
    }
}

nonisolated struct CanonicalRecordingMetadataNoCommitResult: Codable, Equatable, Sendable {
    var gate: CanonicalCutoverAppSeamGate
    var candidateResults: [CanonicalRecordingMetadataNoCommitCandidateResult]
    var diagnostics: [CanonicalV8RecordingMetadataNoCommitDiagnostic]
    var legacyFallbackPreserved: Bool
    var productionCommitSuppressed: Bool
    var duplicateLegacySuppressedActionIDs: [String]
    var nonfatalFailureCount: Int
    var evidenceReport: CanonicalNoCommitEvidenceReport

    nonisolated var succeeded: Bool {
        gate.allowed && nonfatalFailureCount == 0
    }
}

nonisolated struct CanonicalCutoverAppSeamResult: Codable, Equatable, Sendable {
    var noCommitResult: CanonicalRecordingMetadataNoCommitResult
    var legacyPlanUnchanged: Bool
    var productionPlanUnchanged: Bool

    nonisolated var diagnostics: [CanonicalV8RecordingMetadataNoCommitDiagnostic] {
        noCommitResult.diagnostics
    }
}

nonisolated struct CanonicalRecordingMetadataCanaryPolicy: Codable, Equatable, Sendable {
    var maxObjectsPerSyncRun: Int
    var runtimeSwitchEnabled: Bool
    var allowsV87CanaryN1InternalExecution: Bool
    var recordingMetadataCanaryStagePolicy: CanonicalRecordingMetadataCanaryStagePolicy?

    nonisolated init(
        maxObjectsPerSyncRun: Int = 0,
        runtimeSwitchEnabled: Bool = false,
        allowsV87CanaryN1InternalExecution: Bool = false,
        recordingMetadataCanaryStagePolicy: CanonicalRecordingMetadataCanaryStagePolicy? = nil
    ) {
        self.maxObjectsPerSyncRun = max(0, maxObjectsPerSyncRun)
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.allowsV87CanaryN1InternalExecution = allowsV87CanaryN1InternalExecution
        self.recordingMetadataCanaryStagePolicy = recordingMetadataCanaryStagePolicy
    }

    nonisolated var isZeroBudget: Bool {
        maxObjectsPerSyncRun == 0
    }

    nonisolated var diagnosticsSummary: String {
        [
            "canaryMaxObjectsPerSyncRun=\(maxObjectsPerSyncRun)",
            "runtimeSwitchEnabled=\(runtimeSwitchEnabled)",
            "allowsV87CanaryN1InternalExecution=\(allowsV87CanaryN1InternalExecution)",
            "canaryStage=\(recordingMetadataCanaryStagePolicy?.requestedStage.rawValue ?? CanonicalRecordingMetadataCanaryStage.disabled.rawValue)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalRecordingMetadataRollbackPlanSummary: Codable, Equatable, Sendable {
    var planID: String?
    var checkpointCount: Int
    var actionCount: Int
    var coversRecordingMetadata: Bool
    var rollbackVerified: Bool
    var rollbackRehearsalPassed: Bool

    nonisolated init(
        plan: CanonicalRollbackPlan?,
        rollbackVerified: Bool,
        rollbackRehearsalPassed: Bool
    ) {
        self.planID = plan.flatMap { CanonicalProductionRedaction.safeDiagnosticText($0.planID) }
        self.checkpointCount = plan?.checkpoints.count ?? 0
        self.actionCount = plan?.actions.count ?? 0
        self.coversRecordingMetadata = plan?.covers(domain: .recordingMetadata) ?? false
        self.rollbackVerified = rollbackVerified
        self.rollbackRehearsalPassed = rollbackRehearsalPassed
    }

    nonisolated var diagnosticsSummary: String {
        [
            planID.map { "rollbackPlan=\($0)" },
            "checkpointCount=\(checkpointCount)",
            "actionCount=\(actionCount)",
            "coversRecordingMetadata=\(coversRecordingMetadata)",
            "rollbackVerified=\(rollbackVerified)",
            "rollbackRehearsalPassed=\(rollbackRehearsalPassed)"
        ].compactMap { $0 }.joined(separator: ",")
    }
}

nonisolated struct CanonicalRecordingMetadataProductionApplyPortReadiness: Codable, Equatable, Sendable {
    var productionPortAvailable: Bool
    var applyPortMode: CanonicalRecordingMetadataApplyPortMode
    var realRootBoundApplyPortAvailable: Bool
    var rootBoundWriteAvailable: Bool
    var atomicReplaceAvailable: Bool
    var rollbackCheckpointAvailable: Bool
    var productionRootDisabledByDefault: Bool
    var testRootUsed: Bool

    nonisolated init(evidence: CanonicalRecordingMetadataCutoverEvidence) {
        self.productionPortAvailable = evidence.productionPortAvailable
        self.applyPortMode = evidence.applyPortMode
        self.realRootBoundApplyPortAvailable = evidence.realRootBoundApplyPortAvailable
        self.rootBoundWriteAvailable = evidence.rootBoundWriteAvailable
        self.atomicReplaceAvailable = evidence.atomicReplaceAvailable
        self.rollbackCheckpointAvailable = evidence.rollbackCheckpointAvailable
        self.productionRootDisabledByDefault = evidence.productionRootDisabledByDefault
        self.testRootUsed = evidence.testRootUsed
    }

    nonisolated var readyForGuardedCommit: Bool {
        productionPortAvailable
            && realRootBoundApplyPortAvailable
            && applyPortMode.isNonDryRunRootBound
            && rootBoundWriteAvailable
            && atomicReplaceAvailable
            && rollbackCheckpointAvailable
            && productionRootDisabledByDefault
            && (applyPortMode != .testRootBound || testRootUsed)
    }

    nonisolated var diagnosticsSummary: String {
        [
            "productionPortAvailable=\(productionPortAvailable)",
            "applyPortMode=\(applyPortMode.rawValue)",
            "realRootBoundApplyPortAvailable=\(realRootBoundApplyPortAvailable)",
            "rootBoundWriteAvailable=\(rootBoundWriteAvailable)",
            "atomicReplaceAvailable=\(atomicReplaceAvailable)",
            "rollbackCheckpointAvailable=\(rollbackCheckpointAvailable)",
            "productionRootDisabledByDefault=\(productionRootDisabledByDefault)",
            "testRootUsed=\(testRootUsed)",
            "readyForGuardedCommit=\(readyForGuardedCommit)"
        ].joined(separator: ",")
    }
}

nonisolated struct CanonicalRecordingMetadataProductionTransportPortReadiness: Codable, Equatable, Sendable {
    var productionPortAvailable: Bool
    var applyMetadataRouteAvailable: Bool
    var readOnlyTransportProbePassed: Bool
    var realNetworkExecutionEnabled: Bool

    nonisolated init(
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        applyMetadataRouteAvailable: Bool = true,
        realNetworkExecutionEnabled: Bool = false
    ) {
        self.productionPortAvailable = evidence.productionPortAvailable
        self.applyMetadataRouteAvailable = applyMetadataRouteAvailable
        self.readOnlyTransportProbePassed = evidence.readOnlyTransportProbePassed
        self.realNetworkExecutionEnabled = realNetworkExecutionEnabled
    }

    nonisolated func readyForGuardedCommit(sendNeeded: Bool) -> Bool {
        guard sendNeeded else {
            return true
        }
        return productionPortAvailable
            && applyMetadataRouteAvailable
            && readOnlyTransportProbePassed
    }

    nonisolated var diagnosticsSummary: String {
        [
            "productionPortAvailable=\(productionPortAvailable)",
            "applyMetadataRouteAvailable=\(applyMetadataRouteAvailable)",
            "readOnlyTransportProbePassed=\(readOnlyTransportProbePassed)",
            "realNetworkExecutionEnabled=\(realNetworkExecutionEnabled)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalRecordingMetadataCommitEvidenceStatus: String, Codable, Equatable, Sendable {
    case complete
    case incomplete
}

nonisolated enum CanonicalRecordingMetadataCommitEvidenceMissingReason: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case missingOwnerApprovedToken
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingReadOnlyTransportProbe
    case productionPortUnavailable
    case rootBoundApplyPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case rollbackPlanMissing
    case rollbackPlanDoesNotCoverRecordingMetadata
    case rollbackVerificationMissing
    case rollbackRehearsalMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case legacyFallbackUnavailable
    case productionExecutionGuardMissing
    case canaryBudgetNonZero
    case missingInternalCanaryConfiguration
    case canaryBudgetAboveOne
}

nonisolated struct CanonicalRecordingMetadataCommitEvidenceReport: Codable, Equatable, Sendable {
    var status: CanonicalRecordingMetadataCommitEvidenceStatus
    var missingReasons: [CanonicalRecordingMetadataCommitEvidenceMissingReason]
    var rollbackPlanSummary: CanonicalRecordingMetadataRollbackPlanSummary
    var applyPortReadiness: CanonicalRecordingMetadataProductionApplyPortReadiness
    var transportPortReadiness: CanonicalRecordingMetadataProductionTransportPortReadiness
    var canaryPolicy: CanonicalRecordingMetadataCanaryPolicy
    var localSnapshotAvailable: Bool
    var peerSnapshotAvailable: Bool
    var candidateCount: Int
    var legacyActionCandidateCount: Int
    var unresolvedConflictCount: Int
    var realDataShadowCopySummary: String?
    var executionShadowSummary: String?
    var readOnlyTransportProbeSummary: String?

    nonisolated init(
        missingReasons: [CanonicalRecordingMetadataCommitEvidenceMissingReason],
        rollbackPlanSummary: CanonicalRecordingMetadataRollbackPlanSummary,
        applyPortReadiness: CanonicalRecordingMetadataProductionApplyPortReadiness,
        transportPortReadiness: CanonicalRecordingMetadataProductionTransportPortReadiness,
        canaryPolicy: CanonicalRecordingMetadataCanaryPolicy,
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool,
        candidateCount: Int,
        legacyActionCandidateCount: Int,
        unresolvedConflictCount: Int,
        realDataShadowCopySummary: String? = nil,
        executionShadowSummary: String? = nil,
        readOnlyTransportProbeSummary: String? = nil
    ) {
        let normalizedReasons = Array(Set(missingReasons)).sorted { $0.rawValue < $1.rawValue }
        self.status = normalizedReasons.isEmpty ? .complete : .incomplete
        self.missingReasons = normalizedReasons
        self.rollbackPlanSummary = rollbackPlanSummary
        self.applyPortReadiness = applyPortReadiness
        self.transportPortReadiness = transportPortReadiness
        self.canaryPolicy = canaryPolicy
        self.localSnapshotAvailable = localSnapshotAvailable
        self.peerSnapshotAvailable = peerSnapshotAvailable
        self.candidateCount = max(0, candidateCount)
        self.legacyActionCandidateCount = max(0, legacyActionCandidateCount)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.realDataShadowCopySummary = realDataShadowCopySummary.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.executionShadowSummary = executionShadowSummary.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
        self.readOnlyTransportProbeSummary = readOnlyTransportProbeSummary.flatMap(CanonicalProductionRedaction.safeDiagnosticText)
    }

    nonisolated var diagnosticsSummary: String {
        [
            "status=\(status.rawValue)",
            "missingReasons=\(missingReasons.map(\.rawValue).joined(separator: "+"))",
            "candidateCount=\(candidateCount)",
            "legacyActionCandidateCount=\(legacyActionCandidateCount)",
            "unresolvedConflictCount=\(unresolvedConflictCount)",
            "localSnapshotAvailable=\(localSnapshotAvailable)",
            "peerSnapshotAvailable=\(peerSnapshotAvailable)",
            "canaryMaxObjectsPerSyncRun=\(canaryPolicy.maxObjectsPerSyncRun)",
            "runtimeSwitchEnabled=\(canaryPolicy.runtimeSwitchEnabled)",
            "allowsV87CanaryN1InternalExecution=\(canaryPolicy.allowsV87CanaryN1InternalExecution)",
            "applyPortReady=\(applyPortReadiness.readyForGuardedCommit)",
            "transportProbePassed=\(transportPortReadiness.readOnlyTransportProbePassed)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalRecordingMetadataGuardedCommitSeamFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case unsupportedDomain
    case unsupportedMode
    case productionExecuteDenied
    case viewRefreshTriggerDenied
    case retryDrainerFreshMetadataDenied
    case insufficientLocalSnapshot
    case insufficientPeerSnapshot
    case missingToken
    case missingOwnerApproval
    case missingRealDataShadowCopyEvidence
    case missingExecutionShadowEvidence
    case missingDryRunEquivalence
    case blockingDivergence
    case unresolvedConflict
    case missingReadOnlyTransportProbe
    case productionPortUnavailable
    case rootBoundApplyPortUnavailable
    case applyPortDryRunOnly
    case rootBoundWriteUnavailable
    case atomicReplaceUnavailable
    case rollbackCheckpointUnavailable
    case missingRollback
    case rollbackVerificationMissing
    case productionRootEnabledByDefault
    case testRootMissing
    case legacyFallbackUnavailable
    case productionExecutionGuardMissing
    case unsupportedAction
    case unstableMetadataHash
    case canaryBudgetNonZeroDenied
    case missingInternalCanaryConfiguration
    case canaryBudgetAboveOneDenied
}

nonisolated struct CanonicalRecordingMetadataGuardedCommitGate: Codable, Equatable, Sendable {
    var domain: CanonicalCutoverDomain
    var mode: CanonicalCutoverAppSeamMode
    var allowed: Bool
    var failures: [CanonicalRecordingMetadataGuardedCommitSeamFailure]
    var reason: String

    nonisolated init(
        domain: CanonicalCutoverDomain,
        mode: CanonicalCutoverAppSeamMode,
        failures: [CanonicalRecordingMetadataGuardedCommitSeamFailure],
        reason: String
    ) {
        self.domain = domain
        self.mode = mode
        self.failures = Array(Set(failures)).sorted { $0.rawValue < $1.rawValue }
        self.allowed = self.failures.isEmpty
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason) ?? (self.failures.isEmpty ? "allowed" : "blocked")
    }
}

nonisolated enum CanonicalRecordingMetadataGuardedCommitDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalV86GuardedCommitSeamStarted
    case canonicalV86GuardedCommitSeamCompleted
    case canonicalV86GuardedCommitSeamBlocked
    case canonicalV86GuardedCommitGateEvaluated
    case canonicalV86GuardedCommitGateAllowed
    case canonicalV86GuardedCommitGateBlocked
    case canonicalV86CanaryBudgetZero
    case canonicalV86CommitNotExecuted
    case canonicalV86LegacyFallbackPreserved
    case canonicalV86DuplicateSuppressionNotApplied
    case canonicalV86CommitEvidenceReportBuilt
    case canonicalV86ProductionApplyPortReadinessEvaluated
    case canonicalV86ProductionTransportPortReadinessEvaluated
    case canonicalV86RollbackPlanReadinessEvaluated
    case canonicalRecordingMetadataCanaryBudgetZero
    case canonicalRecordingMetadataGateAllowedButNoExecution
    case canonicalRecordingMetadataCommitSkippedBecauseCanaryBudgetZero
}

nonisolated struct CanonicalRecordingMetadataGuardedCommitDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", result ?? "", reason ?? ""].joined(separator: "|") }

    var kind: CanonicalRecordingMetadataGuardedCommitDiagnosticKind
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var domain: CanonicalCutoverDomain
    var mode: CanonicalCutoverAppSeamMode
    var objectID: String?
    var candidateCount: Int
    var gateFailureCount: Int
    var canaryBudget: Int
    var commitAttemptedCount: Int
    var duplicateSuppressionCandidateCount: Int
    var result: String?
    var reason: String?
    var hashPrefix: String?

    nonisolated init(
        kind: CanonicalRecordingMetadataGuardedCommitDiagnosticKind,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        domain: CanonicalCutoverDomain,
        mode: CanonicalCutoverAppSeamMode,
        objectID: String? = nil,
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
        self.domain = domain
        self.mode = mode
        self.objectID = objectID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "unknown-recording") }
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
            "domain=\(domain.rawValue)",
            "mode=\(mode.rawValue)",
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

nonisolated struct CanonicalRecordingMetadataGuardedCommitContext: Codable, Equatable, Sendable {
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var localManifest: CanonicalManifest?
    var peerManifest: CanonicalManifest?
    var applyPlan: CanonicalApplyPlan?
    var legacyActionSnapshot: CanonicalLegacyActionSnapshot
    var evidence: CanonicalRecordingMetadataCutoverEvidence
    var realDataShadowCopyEvidence: CanonicalRealDataShadowCopyResult?
    var executionShadowEvidence: CanonicalExecutionShadowReport?
    var readOnlyTransportProbeEvidence: CanonicalReadOnlyTransportProbeResult?
    var rollbackPlanSummary: CanonicalRecordingMetadataRollbackPlanSummary
    var productionApplyPortReadiness: CanonicalRecordingMetadataProductionApplyPortReadiness
    var productionTransportPortReadiness: CanonicalRecordingMetadataProductionTransportPortReadiness
    var unresolvedConflictCount: Int
    var canaryPolicy: CanonicalRecordingMetadataCanaryPolicy
    var legacyFallbackAvailable: Bool
    var cutoverToken: CanonicalCutoverToken?
    var candidates: [CanonicalRecordingMetadataCutoverCandidate]
    var localSnapshotAvailable: Bool
    var peerSnapshotAvailable: Bool

    nonisolated init(
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?,
        applyPlan: CanonicalApplyPlan?,
        legacyActionSnapshot: CanonicalLegacyActionSnapshot = .empty,
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        realDataShadowCopyEvidence: CanonicalRealDataShadowCopyResult? = nil,
        executionShadowEvidence: CanonicalExecutionShadowReport? = nil,
        readOnlyTransportProbeEvidence: CanonicalReadOnlyTransportProbeResult? = nil,
        rollbackPlanSummary: CanonicalRecordingMetadataRollbackPlanSummary? = nil,
        productionApplyPortReadiness: CanonicalRecordingMetadataProductionApplyPortReadiness? = nil,
        productionTransportPortReadiness: CanonicalRecordingMetadataProductionTransportPortReadiness? = nil,
        unresolvedConflictCount: Int = 0,
        canaryPolicy: CanonicalRecordingMetadataCanaryPolicy = CanonicalRecordingMetadataCanaryPolicy(),
        legacyFallbackAvailable: Bool? = nil,
        cutoverToken: CanonicalCutoverToken? = nil,
        candidates: [CanonicalRecordingMetadataCutoverCandidate] = [],
        localSnapshotAvailable: Bool,
        peerSnapshotAvailable: Bool
    ) {
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.localManifest = localManifest
        self.peerManifest = peerManifest
        self.applyPlan = applyPlan
        self.legacyActionSnapshot = legacyActionSnapshot
        self.evidence = evidence
        self.realDataShadowCopyEvidence = realDataShadowCopyEvidence
        self.executionShadowEvidence = executionShadowEvidence
        self.readOnlyTransportProbeEvidence = readOnlyTransportProbeEvidence
        self.rollbackPlanSummary = rollbackPlanSummary ?? CanonicalRecordingMetadataRollbackPlanSummary(
            plan: evidence.rollbackPlan,
            rollbackVerified: evidence.rollbackVerified,
            rollbackRehearsalPassed: evidence.rollbackRehearsalPassed
        )
        self.productionApplyPortReadiness = productionApplyPortReadiness ?? CanonicalRecordingMetadataProductionApplyPortReadiness(evidence: evidence)
        self.productionTransportPortReadiness = productionTransportPortReadiness ?? CanonicalRecordingMetadataProductionTransportPortReadiness(evidence: evidence)
        self.unresolvedConflictCount = max(0, unresolvedConflictCount)
        self.canaryPolicy = canaryPolicy
        self.legacyFallbackAvailable = legacyFallbackAvailable ?? evidence.legacyFallbackAvailable
        self.cutoverToken = cutoverToken
        self.candidates = candidates
        self.localSnapshotAvailable = localSnapshotAvailable
        self.peerSnapshotAvailable = peerSnapshotAvailable
    }
}

nonisolated struct CanonicalRecordingMetadataGuardedCommitSeamResult: Codable, Equatable, Sendable {
    var gate: CanonicalRecordingMetadataGuardedCommitGate
    var evidenceReport: CanonicalRecordingMetadataCommitEvidenceReport
    var diagnostics: [CanonicalRecordingMetadataGuardedCommitDiagnostic]
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
        gate.allowed && canaryBudgetZero && !willExecuteNow && nonfatalFailureCount == 0
    }
}

nonisolated struct CanonicalRecordingMetadataGuardedCommitSeam: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        configuration: CanonicalCutoverAppSeamConfiguration,
        context: CanonicalRecordingMetadataGuardedCommitContext
    ) -> CanonicalRecordingMetadataGuardedCommitSeamResult {
        let canaryPolicy = CanonicalRecordingMetadataCanaryPolicy(
            maxObjectsPerSyncRun: configuration.policy.effectiveCanaryMaxObjectsPerSyncRun,
            runtimeSwitchEnabled: false,
            allowsV87CanaryN1InternalExecution: configuration.policy.allowsV87CanaryN1InternalExecution,
            recordingMetadataCanaryStagePolicy: configuration.policy.recordingMetadataCanaryStagePolicy
        )
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
        let canaryBudgetZero = canaryPolicy.isZeroBudget
        let canExecuteNow = gate.allowed
        let willExecuteNow = false
        var diagnostics: [CanonicalRecordingMetadataGuardedCommitDiagnostic] = [
            diagnostic(
                .canonicalV86GuardedCommitSeamStarted,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.reason
            ),
            diagnostic(
                .canonicalV86CommitEvidenceReportBuilt,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: evidenceReport.status.rawValue,
                reason: evidenceReport.diagnosticsSummary
            ),
            diagnostic(
                .canonicalV86ProductionApplyPortReadinessEvaluated,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: context.productionApplyPortReadiness.readyForGuardedCommit ? "ready" : "blocked",
                reason: context.productionApplyPortReadiness.diagnosticsSummary
            ),
            diagnostic(
                .canonicalV86ProductionTransportPortReadinessEvaluated,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: context.productionTransportPortReadiness.readyForGuardedCommit(sendNeeded: sendNeeded(context)) ? "ready" : "blocked",
                reason: context.productionTransportPortReadiness.diagnosticsSummary
            ),
            diagnostic(
                .canonicalV86RollbackPlanReadinessEvaluated,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: context.rollbackPlanSummary.coversRecordingMetadata ? "ready" : "blocked",
                reason: context.rollbackPlanSummary.diagnosticsSummary
            ),
            diagnostic(
                .canonicalV86GuardedCommitGateEvaluated,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.allowed ? "guardedCommitGateAllowed" : gate.failures.map(\.rawValue).joined(separator: ",")
            )
        ]
        diagnostics.append(
            diagnostic(
                gate.allowed ? .canonicalV86GuardedCommitGateAllowed : .canonicalV86GuardedCommitGateBlocked,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.reason
            )
        )
        if !gate.allowed {
            diagnostics.append(
                diagnostic(
                    .canonicalV86GuardedCommitSeamBlocked,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "blocked",
                    reason: gate.failures.map(\.rawValue).joined(separator: ",")
                )
            )
        }
        if canaryBudgetZero {
            diagnostics.append(
                diagnostic(
                    .canonicalV86CanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "canaryBudgetZero",
                    reason: canaryPolicy.diagnosticsSummary
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalRecordingMetadataCanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "canaryBudgetZero",
                    reason: "canonicalRecordingMetadataCanaryBudgetZero"
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalRecordingMetadataCommitSkippedBecauseCanaryBudgetZero,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "commitSkipped",
                    reason: "canaryBudgetZero"
                )
            )
        }
        if gate.allowed && !willExecuteNow {
            diagnostics.append(
                diagnostic(
                    .canonicalRecordingMetadataGateAllowedButNoExecution,
                    configuration: configuration,
                    context: context,
                    candidateCount: context.candidates.count,
                    gateFailureCount: gate.failures.count,
                    canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                    duplicateSuppressionCandidateCount: duplicateCandidates.count,
                    result: "gateAllowedButNoExecution",
                    reason: canaryBudgetZero ? "canaryBudgetZero" : "executionDisabledForV86"
                )
            )
        }
        diagnostics.append(
            diagnostic(
                .canonicalV86CommitNotExecuted,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: "commitNotExecuted",
                reason: canaryBudgetZero ? "canaryBudgetZero" : "guardedCommitSeamReportOnly"
            )
        )
        diagnostics.append(
            diagnostic(
                .canonicalV86LegacyFallbackPreserved,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: "legacyFallbackPreserved",
                reason: "v86DoesNotReplaceLegacyPlan"
            )
        )
        diagnostics.append(
            diagnostic(
                .canonicalV86DuplicateSuppressionNotApplied,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: "duplicateSuppressionNotApplied",
                reason: "v86DoesNotSuppressLegacyDuplicates"
            )
        )
        diagnostics.append(
            diagnostic(
                .canonicalV86GuardedCommitSeamCompleted,
                configuration: configuration,
                context: context,
                candidateCount: context.candidates.count,
                gateFailureCount: gate.failures.count,
                canaryBudget: canaryPolicy.maxObjectsPerSyncRun,
                duplicateSuppressionCandidateCount: duplicateCandidates.count,
                result: "completed",
                reason: gate.allowed ? "nonfatalNoExecution" : "nonfatalBlocked"
            )
        )

        return CanonicalRecordingMetadataGuardedCommitSeamResult(
            gate: gate,
            evidenceReport: evidenceReport,
            diagnostics: Array(diagnostics.prefix(configuration.policy.maxDiagnosticsEvents)),
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
            nonfatalFailureCount: gate.failures.count
        )
    }

    private nonisolated func evaluateGate(
        configuration: CanonicalCutoverAppSeamConfiguration,
        context: CanonicalRecordingMetadataGuardedCommitContext,
        evidenceReport: CanonicalRecordingMetadataCommitEvidenceReport,
        canaryPolicy: CanonicalRecordingMetadataCanaryPolicy
    ) -> CanonicalRecordingMetadataGuardedCommitGate {
        var failures: [CanonicalRecordingMetadataGuardedCommitSeamFailure] = []
        let mode = configuration.effectiveMode
        if mode == .disabled {
            failures.append(.disabled)
        }
        if configuration.domain != .recordingMetadata {
            failures.append(.unsupportedDomain)
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
        if context.cutoverToken == nil {
            failures.append(.missingToken)
        }
        if context.cutoverToken?.ownerApproved != true {
            failures.append(.missingOwnerApproval)
        }
        let stagePolicy = canaryPolicy.recordingMetadataCanaryStagePolicy ?? .disabled
        if stagePolicy.requestedStage.isExecutable {
            let stageGate = CanonicalRecordingMetadataCanaryStageGate(
                policy: stagePolicy,
                domain: configuration.domain,
                token: context.cutoverToken,
                cutoverEvidence: context.evidence
            )
            if !stageGate.allowed {
                failures.append(.canaryBudgetAboveOneDenied)
            }
        } else {
            if canaryPolicy.maxObjectsPerSyncRun > 1 {
                failures.append(.canaryBudgetAboveOneDenied)
            }
            if canaryPolicy.maxObjectsPerSyncRun == 1,
               !canaryPolicy.allowsV87CanaryN1InternalExecution {
                failures.append(.missingInternalCanaryConfiguration)
            }
        }
        if context.candidates.contains(where: { $0.cutoverActionKind == nil }) {
            failures.append(.unsupportedAction)
        }
        if context.candidates.contains(where: { $0.stableMetadataHash == nil }) {
            failures.append(.unstableMetadataHash)
        }
        if context.unresolvedConflictCount > 0
            || context.candidates.contains(where: \.unresolvedConflict)
            || !context.evidence.noUnresolvedConflict {
            failures.append(.unresolvedConflict)
        }
        if configuration.policy.requireCutoverEvidence {
            failures.append(contentsOf: evidenceReport.missingReasons.map(Self.failure(for:)))
        }
        return CanonicalRecordingMetadataGuardedCommitGate(
            domain: configuration.domain,
            mode: mode,
            failures: failures,
            reason: failures.isEmpty ? "canonicalV86GuardedCommitGateAllowed" : "canonicalV86GuardedCommitGateBlocked"
        )
    }

    private nonisolated func makeEvidenceReport(
        configuration: CanonicalCutoverAppSeamConfiguration,
        context: CanonicalRecordingMetadataGuardedCommitContext,
        canaryPolicy: CanonicalRecordingMetadataCanaryPolicy,
        duplicateCandidates: [String]
    ) -> CanonicalRecordingMetadataCommitEvidenceReport {
        let evidence = context.evidence
        let sendNeeded = sendNeeded(context)
        var missing: [CanonicalRecordingMetadataCommitEvidenceMissingReason] = []
        if context.cutoverToken?.ownerApproved != true {
            missing.append(.missingOwnerApprovedToken)
        }
        if !evidence.realDataShadowCopyVerified {
            missing.append(.missingRealDataShadowCopyEvidence)
        }
        if !evidence.executionShadowVerified {
            missing.append(.missingExecutionShadowEvidence)
        }
        if !evidence.dryRunEquivalenceVerified {
            missing.append(.missingDryRunEquivalence)
        }
        if !evidence.noBlockingDivergence {
            missing.append(.blockingDivergence)
        }
        if !evidence.noUnresolvedConflict || context.unresolvedConflictCount > 0 || context.candidates.contains(where: \.unresolvedConflict) {
            missing.append(.unresolvedConflict)
        }
        if configuration.policy.requireCutoverEvidence && sendNeeded && !evidence.readOnlyTransportProbePassed {
            missing.append(.missingReadOnlyTransportProbe)
        }
        if !evidence.productionPortAvailable {
            missing.append(.productionPortUnavailable)
        }
        if !context.productionApplyPortReadiness.realRootBoundApplyPortAvailable {
            missing.append(.rootBoundApplyPortUnavailable)
        }
        if !context.productionApplyPortReadiness.applyPortMode.isNonDryRunRootBound {
            missing.append(.applyPortDryRunOnly)
        }
        if !context.productionApplyPortReadiness.rootBoundWriteAvailable {
            missing.append(.rootBoundWriteUnavailable)
        }
        if !context.productionApplyPortReadiness.atomicReplaceAvailable {
            missing.append(.atomicReplaceUnavailable)
        }
        if !context.productionApplyPortReadiness.rollbackCheckpointAvailable {
            missing.append(.rollbackCheckpointUnavailable)
        }
        if context.rollbackPlanSummary.planID == nil {
            missing.append(.rollbackPlanMissing)
        }
        if !context.rollbackPlanSummary.coversRecordingMetadata {
            missing.append(.rollbackPlanDoesNotCoverRecordingMetadata)
        }
        if !context.rollbackPlanSummary.rollbackVerified {
            missing.append(.rollbackVerificationMissing)
        }
        if !context.rollbackPlanSummary.rollbackRehearsalPassed {
            missing.append(.rollbackRehearsalMissing)
        }
        if !context.productionApplyPortReadiness.productionRootDisabledByDefault {
            missing.append(.productionRootEnabledByDefault)
        }
        if context.productionApplyPortReadiness.applyPortMode == .testRootBound && !context.productionApplyPortReadiness.testRootUsed {
            missing.append(.testRootMissing)
        }
        if !context.legacyFallbackAvailable {
            missing.append(.legacyFallbackUnavailable)
        }
        if !evidence.productionExecutionGuardPassed {
            missing.append(.productionExecutionGuardMissing)
        }
        let stagePolicy = canaryPolicy.recordingMetadataCanaryStagePolicy ?? .disabled
        if !stagePolicy.requestedStage.isExecutable {
            if canaryPolicy.maxObjectsPerSyncRun > 1 {
                missing.append(.canaryBudgetAboveOne)
            }
            if canaryPolicy.maxObjectsPerSyncRun == 1,
               !canaryPolicy.allowsV87CanaryN1InternalExecution {
                missing.append(.missingInternalCanaryConfiguration)
            }
        }
        return CanonicalRecordingMetadataCommitEvidenceReport(
            missingReasons: missing,
            rollbackPlanSummary: context.rollbackPlanSummary,
            applyPortReadiness: context.productionApplyPortReadiness,
            transportPortReadiness: context.productionTransportPortReadiness,
            canaryPolicy: canaryPolicy,
            localSnapshotAvailable: context.localSnapshotAvailable,
            peerSnapshotAvailable: context.peerSnapshotAvailable,
            candidateCount: context.candidates.count,
            legacyActionCandidateCount: duplicateCandidates.count,
            unresolvedConflictCount: context.unresolvedConflictCount,
            realDataShadowCopySummary: context.realDataShadowCopyEvidence?.diagnosticsSummary,
            executionShadowSummary: Self.executionShadowSummary(context.executionShadowEvidence),
            readOnlyTransportProbeSummary: context.readOnlyTransportProbeEvidence?.diagnosticsSummary
        )
    }

    private nonisolated func duplicateSuppressionCandidates(
        _ context: CanonicalRecordingMetadataGuardedCommitContext
    ) -> [String] {
        let legacyIDs = context.legacyActionSnapshot.actionIDSet(for: .recordingMetadata)
        return context.candidates
            .map { $0.action.actionID }
            .filter { legacyIDs.contains($0) }
            .compactMap { CanonicalProductionRedaction.safeDiagnosticText($0) }
            .sorted()
    }

    private nonisolated func sendNeeded(_ context: CanonicalRecordingMetadataGuardedCommitContext) -> Bool {
        context.candidates.contains(where: \.requiresNetworkSend)
    }

    private nonisolated static func executionShadowSummary(
        _ report: CanonicalExecutionShadowReport?
    ) -> String? {
        guard let report else {
            return nil
        }
        return [
            "executionShadow=\(report.dryRunEquivalent ? "equivalent" : "divergent")",
            "blocked=\(report.blocked)",
            "mode=\(report.mode.rawValue)",
            "shadowRootKind=\(report.shadowRootKind?.rawValue ?? "none")",
            "failure=\(report.failure?.rawValue ?? "none")"
        ].joined(separator: ",")
    }

    private nonisolated static func failure(
        for reason: CanonicalRecordingMetadataCommitEvidenceMissingReason
    ) -> CanonicalRecordingMetadataGuardedCommitSeamFailure {
        switch reason {
        case .missingOwnerApprovedToken:
            return .missingOwnerApproval
        case .missingRealDataShadowCopyEvidence:
            return .missingRealDataShadowCopyEvidence
        case .missingExecutionShadowEvidence:
            return .missingExecutionShadowEvidence
        case .missingDryRunEquivalence:
            return .missingDryRunEquivalence
        case .blockingDivergence:
            return .blockingDivergence
        case .unresolvedConflict:
            return .unresolvedConflict
        case .missingReadOnlyTransportProbe:
            return .missingReadOnlyTransportProbe
        case .productionPortUnavailable:
            return .productionPortUnavailable
        case .rootBoundApplyPortUnavailable:
            return .rootBoundApplyPortUnavailable
        case .applyPortDryRunOnly:
            return .applyPortDryRunOnly
        case .rootBoundWriteUnavailable:
            return .rootBoundWriteUnavailable
        case .atomicReplaceUnavailable:
            return .atomicReplaceUnavailable
        case .rollbackCheckpointUnavailable:
            return .rollbackCheckpointUnavailable
        case .rollbackPlanMissing, .rollbackPlanDoesNotCoverRecordingMetadata, .rollbackRehearsalMissing:
            return .missingRollback
        case .rollbackVerificationMissing:
            return .rollbackVerificationMissing
        case .productionRootEnabledByDefault:
            return .productionRootEnabledByDefault
        case .testRootMissing:
            return .testRootMissing
        case .legacyFallbackUnavailable:
            return .legacyFallbackUnavailable
        case .productionExecutionGuardMissing:
            return .productionExecutionGuardMissing
        case .canaryBudgetNonZero:
            return .canaryBudgetNonZeroDenied
        case .missingInternalCanaryConfiguration:
            return .missingInternalCanaryConfiguration
        case .canaryBudgetAboveOne:
            return .canaryBudgetAboveOneDenied
        }
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalRecordingMetadataGuardedCommitDiagnosticKind,
        configuration: CanonicalCutoverAppSeamConfiguration,
        context: CanonicalRecordingMetadataGuardedCommitContext,
        objectID: String? = nil,
        candidateCount: Int,
        gateFailureCount: Int = 0,
        canaryBudget: Int,
        commitAttemptedCount: Int = 0,
        duplicateSuppressionCandidateCount: Int = 0,
        result: String? = nil,
        reason: String? = nil,
        hash: CanonicalHash? = nil
    ) -> CanonicalRecordingMetadataGuardedCommitDiagnostic {
        CanonicalRecordingMetadataGuardedCommitDiagnostic(
            kind: kind,
            syncRunID: context.syncRunID,
            trigger: context.trigger,
            nodeRole: context.nodeRole,
            domain: configuration.domain,
            mode: configuration.effectiveMode,
            objectID: objectID,
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

nonisolated struct CanonicalRecordingMetadataNoCommitRunner: Sendable {
    nonisolated init() {}

    nonisolated func evaluateGate(
        configuration: CanonicalCutoverAppSeamConfiguration,
        evidence: CanonicalRecordingMetadataCutoverEvidence,
        candidates: [CanonicalRecordingMetadataNoCommitCandidate],
        trigger: CanonicalSyncPlanTrigger,
        localSnapshotAvailable: Bool = true,
        peerSnapshotAvailable: Bool = true
    ) -> CanonicalCutoverAppSeamGate {
        var failures: [CanonicalCutoverAppSeamFailure] = []
        if configuration.effectiveMode == .disabled {
            failures.append(.disabled)
        }
        if configuration.domain != .recordingMetadata {
            failures.append(.unsupportedDomain)
        }
        switch configuration.effectiveMode {
        case .disabled:
            break
        case .guardedExecuteNoCommit:
            break
        case .guardedExecuteCommit:
            failures.append(.guardedExecuteCommitDenied)
        case .productionExecute:
            failures.append(.productionExecuteDenied)
        case .canaryCommit:
            failures.append(.canaryCommitDenied)
        }
        if configuration.effectiveMode != .disabled,
           configuration.effectiveMode != .guardedExecuteNoCommit {
            failures.append(.unsupportedMode)
        }
        if trigger == .viewRefresh {
            failures.append(.viewRefreshTriggerDenied)
        }
        if trigger == .retryDrainer {
            failures.append(.retryDrainerFreshMetadataDenied)
        }
        if !localSnapshotAvailable {
            failures.append(.insufficientLocalSnapshot)
        }
        if !peerSnapshotAvailable {
            failures.append(.insufficientPeerSnapshot)
        }
        if candidates.contains(where: { $0.canonicalDirection == .none }) {
            failures.append(.unsupportedAction)
        }
        if candidates.contains(where: { $0.cutoverCandidate.stableMetadataHash == nil }) {
            failures.append(.unstableMetadataHash)
        }
        if candidates.contains(where: { $0.cutoverCandidate.unresolvedConflict }) || !evidence.noUnresolvedConflict {
            failures.append(.unresolvedConflict)
        }
        if configuration.policy.requireCutoverEvidence,
           !hasRequiredNoCommitEvidence(evidence, sendNeeded: candidates.contains { $0.canonicalDirection == .send }) {
            failures.append(.insufficientEvidence)
        }
        return CanonicalCutoverAppSeamGate(
            domain: configuration.domain,
            mode: configuration.effectiveMode,
            failures: failures,
            reason: failures.isEmpty ? "canonicalV8NoCommitGateAllowed" : "canonicalV8NoCommitGateBlocked"
        )
    }

    nonisolated func run(
        configuration: CanonicalCutoverAppSeamConfiguration,
        evidence: CanonicalRecordingMetadataCutoverEvidence? = nil,
        candidates: [CanonicalRecordingMetadataNoCommitCandidate],
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?,
        localSnapshotAvailable: Bool = true,
        peerSnapshotAvailable: Bool = true,
        executor: any CanonicalRecordingMetadataNoCommitExecutor
    ) -> CanonicalRecordingMetadataNoCommitResult {
        let effectiveEvidence = evidence ?? configuration.evidence
        let migrationStageSummary = CanonicalMigrationStageConfiguration(
            stage: .recordingMetadataNoCommit,
            domain: configuration.domain
        ).summary()
        let gate = evaluateGate(
            configuration: configuration,
            evidence: effectiveEvidence,
            candidates: candidates,
            trigger: trigger,
            localSnapshotAvailable: localSnapshotAvailable,
            peerSnapshotAvailable: peerSnapshotAvailable
        )
        var diagnostics: [CanonicalV8RecordingMetadataNoCommitDiagnostic] = [
            diagnostic(
                .canonicalV8CutoverSeamStarted,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidateCount: candidates.count,
                result: gate.allowed ? "allowed" : "blocked",
                reason: gate.reason
            )
        ]
        diagnostics.append(
            diagnostic(
                migrationStageSummary.allowed ? .canonicalV8NoCommitConfigStageResolved : .canonicalV8NoCommitConfigBlocked,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidateCount: candidates.count,
                result: migrationStageSummary.allowed ? "resolved" : "blocked",
                reason: migrationStageSummary.diagnosticsSummary
            )
        )

        guard gate.allowed else {
            diagnostics.append(
                diagnostic(
                    .canonicalV8CutoverSeamBlocked,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    candidateCount: candidates.count,
                    blockerCount: gate.failures.count,
                    result: "blocked",
                    reason: gate.failures.map(\.rawValue).joined(separator: ",")
                )
            )
            if gate.failures.contains(.insufficientEvidence) || gate.failures.contains(.insufficientPeerSnapshot) {
                diagnostics.append(
                    diagnostic(
                        .canonicalV8RecordingMetadataNoCommitInsufficientEvidence,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        candidateCount: candidates.count,
                        blockerCount: gate.failures.count,
                        result: "blocked",
                        reason: gate.failures.contains(.insufficientPeerSnapshot) ? "insufficientPeerSnapshot" : "insufficientEvidence"
                    )
                )
            }
            diagnostics.append(
                diagnostic(
                    .canonicalV8RecordingMetadataNoCommitLegacyFallbackPreserved,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    candidateCount: candidates.count,
                    blockerCount: gate.failures.count,
                    result: "legacyFallbackPreserved",
                    reason: "noCommitCannotReplaceLegacy"
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalV8NoCommitLegacyDuplicatePreserved,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    candidateCount: candidates.count,
                    blockerCount: gate.failures.count,
                    result: "legacyDuplicatePreserved",
                    reason: "noCommitCannotReplaceLegacy"
                )
            )
            let evidenceReport = CanonicalNoCommitEvidenceReport(
                gate: gate,
                candidateResults: [],
                productionCommitSuppressed: true,
                legacyDuplicateSuppressed: false
            )
            diagnostics.append(
                diagnostic(
                    .canonicalV8NoCommitEvidenceReportBuilt,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    candidateCount: candidates.count,
                    blockerCount: gate.failures.count,
                    result: evidenceReport.status.rawValue,
                    reason: evidenceReport.diagnosticsSummary
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalV8CutoverSeamCompleted,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    candidateCount: candidates.count,
                    blockerCount: gate.failures.count,
                    result: "completed",
                    reason: "nonfatalBlocked"
                )
            )
            return CanonicalRecordingMetadataNoCommitResult(
                gate: gate,
                candidateResults: [],
                diagnostics: bounded(diagnostics, max: configuration.policy.maxDiagnosticsEvents),
                legacyFallbackPreserved: true,
                productionCommitSuppressed: true,
                duplicateLegacySuppressedActionIDs: [],
                nonfatalFailureCount: gate.failures.count,
                evidenceReport: evidenceReport
            )
        }

        diagnostics.append(
            diagnostic(
                .canonicalV8RecordingMetadataNoCommitStarted,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidateCount: candidates.count,
                result: "started",
                reason: "guardedExecuteNoCommit"
            )
        )

        var results: [CanonicalRecordingMetadataNoCommitCandidateResult] = []
        var equivalentCount = 0
        var divergentCount = 0
        var blockerCount = 0
        for candidate in candidates {
            let staging = executor.stageNoCommit(candidate)
            if let stagingEvidence = staging.stagingEvidence {
                diagnostics.append(
                    diagnostic(
                        .canonicalV8NoCommitStagingRootCreated,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        objectID: candidate.objectID,
                        candidateCount: candidates.count,
                        result: stagingEvidence.lifecycleStatus.rawValue,
                        reason: stagingEvidence.diagnosticsSummary
                    )
                )
            }
            if let cleanupEvidence = staging.cleanupEvidence {
                diagnostics.append(
                    diagnostic(
                        cleanupEvidence.status == .failed || cleanupEvidence.status == .refusedProductionRoot
                            ? .canonicalV8NoCommitStagingRootCleanupFailed
                            : .canonicalV8NoCommitStagingRootCleaned,
                        configuration: configuration,
                        syncRunID: syncRunID,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        objectID: candidate.objectID,
                        candidateCount: candidates.count,
                        result: cleanupEvidence.status.rawValue,
                        reason: cleanupEvidence.diagnosticsSummary
                    )
                )
            }
            let equivalence = evaluateEquivalence(
                candidate: candidate,
                staging: staging,
                policy: configuration.policy
            )
            if equivalence.status == .equivalent || equivalence.status == .canonicalMoreConservative {
                equivalentCount += 1
            }
            if equivalence.status == .divergent {
                divergentCount += 1
            }
            if equivalence.blocking {
                blockerCount += 1
            }
            var outcomes: [CanonicalRecordingMetadataNoCommitOutcome] = [
                .noCommitProductionCommitSuppressed
            ]
            if staging.wouldApply {
                outcomes.append(.noCommitWouldApply)
            }
            if staging.wouldSend {
                outcomes.append(.noCommitWouldSend)
            }
            switch equivalence.status {
            case .equivalent, .canonicalMoreConservative:
                outcomes.append(.noCommitEquivalent)
            case .canonicalMoreAggressive, .blocked:
                outcomes.append(.noCommitBlocked)
            case .divergent:
                outcomes.append(.noCommitDivergent)
            case .insufficientEvidence:
                outcomes.append(.noCommitInsufficientEvidence)
            case .unsupported:
                outcomes.append(.noCommitBlocked)
            }
            let failure = noCommitFailure(for: equivalence.status, staging: staging)
            results.append(
                CanonicalRecordingMetadataNoCommitCandidateResult(
                    candidate: candidate,
                    outcomes: outcomes,
                    equivalence: equivalence,
                    staging: staging,
                    failure: failure
                )
            )
            let diagnosticKind: CanonicalV8RecordingMetadataNoCommitDiagnosticKind
            switch equivalence.status {
            case .equivalent, .canonicalMoreConservative:
                diagnosticKind = .canonicalV8RecordingMetadataNoCommitEquivalent
            case .insufficientEvidence:
                diagnosticKind = .canonicalV8RecordingMetadataNoCommitInsufficientEvidence
            case .unsupported:
                diagnosticKind = .canonicalV8RecordingMetadataNoCommitUnsupported
            case .canonicalMoreAggressive, .divergent, .blocked:
                diagnosticKind = .canonicalV8RecordingMetadataNoCommitDivergent
            }
            diagnostics.append(
                diagnostic(
                    diagnosticKind,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: candidate.objectID,
                    candidateCount: candidates.count,
                    equivalentCount: equivalentCount,
                    divergentCount: divergentCount,
                    blockerCount: blockerCount,
                    result: equivalence.status.rawValue,
                    reason: equivalence.reasons.joined(separator: ","),
                    hashPrefix: equivalence.metadataHashPrefix,
                    routePath: equivalence.routePath
                )
            )
            diagnostics.append(
                diagnostic(
                    equivalence.status == .equivalent || equivalence.status == .canonicalMoreConservative
                        ? .canonicalV8NoCommitEquivalent
                        : .canonicalV8NoCommitDivergent,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: candidate.objectID,
                    candidateCount: candidates.count,
                    equivalentCount: equivalentCount,
                    divergentCount: divergentCount,
                    blockerCount: blockerCount,
                    result: equivalence.status.rawValue,
                    reason: equivalence.reasons.joined(separator: ","),
                    hashPrefix: equivalence.metadataHashPrefix,
                    routePath: equivalence.routePath
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalV8RecordingMetadataNoCommitProductionCommitSuppressed,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: candidate.objectID,
                    candidateCount: candidates.count,
                    equivalentCount: equivalentCount,
                    divergentCount: divergentCount,
                    blockerCount: blockerCount,
                    result: "suppressed",
                    reason: "noCommitMode",
                    hashPrefix: equivalence.metadataHashPrefix,
                    routePath: equivalence.routePath
                )
            )
            diagnostics.append(
                diagnostic(
                    .canonicalV8NoCommitCommitSuppressed,
                    configuration: configuration,
                    syncRunID: syncRunID,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    objectID: candidate.objectID,
                    candidateCount: candidates.count,
                    equivalentCount: equivalentCount,
                    divergentCount: divergentCount,
                    blockerCount: blockerCount,
                    result: "suppressed",
                    reason: "noCommitMode",
                    hashPrefix: equivalence.metadataHashPrefix,
                    routePath: equivalence.routePath
                )
            )
        }

        diagnostics.append(
            diagnostic(
                .canonicalV8RecordingMetadataNoCommitLegacyFallbackPreserved,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidateCount: candidates.count,
                equivalentCount: equivalentCount,
                divergentCount: divergentCount,
                blockerCount: blockerCount,
                result: "legacyFallbackPreserved",
                reason: "noCommitCannotReplaceLegacy"
            )
        )
        diagnostics.append(
            diagnostic(
                .canonicalV8NoCommitLegacyDuplicatePreserved,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidateCount: candidates.count,
                equivalentCount: equivalentCount,
                divergentCount: divergentCount,
                blockerCount: blockerCount,
                result: "legacyDuplicatePreserved",
                reason: "noCommitCannotReplaceLegacy"
            )
        )
        let evidenceReport = CanonicalNoCommitEvidenceReport(
            gate: gate,
            candidateResults: results,
            productionCommitSuppressed: true,
            legacyDuplicateSuppressed: false
        )
        diagnostics.append(
            diagnostic(
                .canonicalV8NoCommitEvidenceReportBuilt,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidateCount: candidates.count,
                equivalentCount: equivalentCount,
                divergentCount: divergentCount,
                blockerCount: blockerCount,
                result: evidenceReport.status.rawValue,
                reason: evidenceReport.diagnosticsSummary
            )
        )
        diagnostics.append(
            diagnostic(
                .canonicalV8RecordingMetadataNoCommitCompleted,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidateCount: candidates.count,
                equivalentCount: equivalentCount,
                divergentCount: divergentCount,
                blockerCount: blockerCount,
                result: blockerCount == 0 ? "completed" : "blocked",
                reason: "productionCommitSuppressed"
            )
        )
        diagnostics.append(
            diagnostic(
                .canonicalV8CutoverSeamCompleted,
                configuration: configuration,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                candidateCount: candidates.count,
                equivalentCount: equivalentCount,
                divergentCount: divergentCount,
                blockerCount: blockerCount,
                result: "completed",
                reason: "legacyPlanUnchanged"
            )
        )

        return CanonicalRecordingMetadataNoCommitResult(
            gate: gate,
            candidateResults: results,
            diagnostics: bounded(diagnostics, max: configuration.policy.maxDiagnosticsEvents),
            legacyFallbackPreserved: true,
            productionCommitSuppressed: true,
            duplicateLegacySuppressedActionIDs: [],
            nonfatalFailureCount: blockerCount,
            evidenceReport: evidenceReport
        )
    }

    nonisolated func evaluateEquivalence(
        candidate: CanonicalRecordingMetadataNoCommitCandidate,
        staging: CanonicalRecordingMetadataNoCommitStagingResult,
        policy: CanonicalCutoverAppSeamPolicy
    ) -> CanonicalRecordingMetadataNoCommitEquivalence {
        var reasons: [String] = []
        var status: CanonicalRecordingMetadataNoCommitEquivalenceStatus = .equivalent
        let canonicalDirection = candidate.canonicalDirection
        let metadataHashPrefix = candidate.cutoverCandidate.stableMetadataHash.flatMap {
            CanonicalProductionRedaction.hashPrefix($0.value)
        }
        let modifiedAtDirection = modifiedAtDirection(candidate.cutoverCandidate)
        let tombstoneState = candidate.cutoverCandidate.expectedObject?.metadata.isDeleted == true ? "tombstone" : "active"

        if staging.failure != nil || !staging.staged || !staging.wroteOnlyStagingRoot {
            status = .unsupported
            reasons.append(staging.failure?.rawValue ?? "stagingFailed")
        }
        if canonicalDirection == .none {
            status = .unsupported
            reasons.append("unsupportedAction")
        }
        if candidate.legacyDirection == .none, canonicalDirection != .none {
            status = .canonicalMoreAggressive
            reasons.append("legacyNoOpCanonicalWouldExecute")
        } else if candidate.legacyDirection != canonicalDirection {
            status = .divergent
            reasons.append("directionMismatch")
        }
        if let legacyObjectID = candidate.legacyObjectID,
           legacyObjectID != candidate.objectID {
            status = .divergent
            reasons.append("objectIDMismatch")
        }
        if metadataHashPrefix == nil {
            status = .insufficientEvidence
            reasons.append("metadataHashMissing")
        }
        if canonicalDirection == .apply {
            if candidate.cutoverCandidate.action.bridgeHint != .legacyMetadataManifestApply || !staging.wouldApply {
                status = .divergent
                reasons.append("localApplyBridgeMismatch")
            }
        }
        if canonicalDirection == .send {
            if candidate.cutoverCandidate.action.bridgeHint != .legacyMetadataManifestSend || !staging.wouldSend {
                status = .divergent
                reasons.append("metadataSendBridgeMismatch")
            }
            let routePath = staging.routePath ?? candidate.expectedRoutePath
            if routePath != "/sync/apply-metadata" {
                status = .divergent
                reasons.append("routeMismatch")
            }
            if candidate.legacyPayloadByteCount == nil || candidate.legacyPayloadHashPrefix == nil {
                status = .insufficientEvidence
                reasons.append("sendPayloadEvidenceMissing")
            } else {
                if candidate.legacyPayloadByteCount != staging.payloadByteCount {
                    status = .divergent
                    reasons.append("payloadSizeMismatch")
                }
                if candidate.legacyPayloadHashPrefix != staging.payloadHashPrefix {
                    status = .divergent
                    reasons.append("payloadHashMismatch")
                }
            }
        }
        if let modifiedAtDirection,
           modifiedAtDirection != "equal",
           modifiedAtDirection != canonicalDirection.rawValue {
            status = .divergent
            reasons.append("modifiedAtDirectionMismatch")
        }
        if reasons.isEmpty {
            reasons.append("equivalent")
        }
        let blocking: Bool
        switch status {
        case .equivalent, .canonicalMoreConservative:
            blocking = false
        case .canonicalMoreAggressive:
            blocking = policy.blockCanonicalMoreAggressive
        case .insufficientEvidence:
            blocking = policy.blockInsufficientEvidence
        case .unsupported:
            blocking = policy.blockUnsupported
        case .divergent, .blocked:
            blocking = policy.blockDivergence
        }
        return CanonicalRecordingMetadataNoCommitEquivalence(
            status: status,
            blocking: blocking,
            reasons: reasons,
            canonicalDirection: canonicalDirection,
            legacyDirection: candidate.legacyDirection,
            metadataHashPrefix: metadataHashPrefix,
            modifiedAtDirection: modifiedAtDirection,
            tombstoneState: tombstoneState,
            routePath: staging.routePath,
            payloadByteCount: staging.payloadByteCount,
            payloadHashPrefix: staging.payloadHashPrefix
        )
    }

    private nonisolated func hasRequiredNoCommitEvidence(
        _ evidence: CanonicalRecordingMetadataCutoverEvidence,
        sendNeeded: Bool
    ) -> Bool {
        evidence.realDataShadowCopyVerified
            && evidence.executionShadowVerified
            && evidence.dryRunEquivalenceVerified
            && evidence.noBlockingDivergence
            && evidence.noUnresolvedConflict
            && (!sendNeeded || evidence.readOnlyTransportProbePassed)
            && evidence.productionPortAvailable
            && evidence.legacyFallbackAvailable
            && evidence.rollbackPlan?.covers(domain: .recordingMetadata) == true
            && evidence.rollbackRehearsalPassed
            && evidence.productionExecutionGuardPassed
    }

    private nonisolated func modifiedAtDirection(
        _ candidate: CanonicalRecordingMetadataCutoverCandidate
    ) -> String? {
        guard let local = candidate.localObject?.metadata.modifiedAt,
              let peer = candidate.peerObject?.metadata.modifiedAt else {
            return nil
        }
        if local < peer {
            return "apply"
        }
        if peer < local {
            return "send"
        }
        return "equal"
    }

    private nonisolated func noCommitFailure(
        for status: CanonicalRecordingMetadataNoCommitEquivalenceStatus,
        staging: CanonicalRecordingMetadataNoCommitStagingResult
    ) -> CanonicalRecordingMetadataNoCommitFailure? {
        if let failure = staging.failure {
            return failure
        }
        switch status {
        case .equivalent, .canonicalMoreConservative:
            return nil
        case .canonicalMoreAggressive:
            return .canonicalMoreAggressive
        case .divergent, .blocked:
            return .divergent
        case .insufficientEvidence:
            return .insufficientEvidence
        case .unsupported:
            return .unsupportedNoCommitPayloadBuilder
        }
    }

    private nonisolated func diagnostic(
        _ kind: CanonicalV8RecordingMetadataNoCommitDiagnosticKind,
        configuration: CanonicalCutoverAppSeamConfiguration,
        syncRunID: String?,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        objectID: String? = nil,
        candidateCount: Int = 0,
        equivalentCount: Int = 0,
        divergentCount: Int = 0,
        blockerCount: Int = 0,
        result: String? = nil,
        reason: String? = nil,
        hashPrefix: String? = nil,
        routePath: String? = nil
    ) -> CanonicalV8RecordingMetadataNoCommitDiagnostic {
        CanonicalV8RecordingMetadataNoCommitDiagnostic(
            kind: kind,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            domain: configuration.domain,
            mode: configuration.effectiveMode,
            objectID: objectID,
            candidateCount: candidateCount,
            equivalentCount: equivalentCount,
            divergentCount: divergentCount,
            blockerCount: blockerCount,
            result: result,
            reason: reason,
            hashPrefix: hashPrefix,
            routePath: routePath
        )
    }

    private nonisolated func bounded(
        _ diagnostics: [CanonicalV8RecordingMetadataNoCommitDiagnostic],
        max: Int
    ) -> [CanonicalV8RecordingMetadataNoCommitDiagnostic] {
        Array(diagnostics.prefix(max))
    }
}
