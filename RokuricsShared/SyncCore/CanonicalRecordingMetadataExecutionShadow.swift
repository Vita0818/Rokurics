//
//  CanonicalRecordingMetadataExecutionShadow.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalShadowDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
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

    var productionDomain: CanonicalProductionDomain {
        switch self {
        case .recordingMetadata:
            return .recordingMetadata
        case .recordingAudio:
            return .recordingAudio
        case .generatedArtifacts:
            return .generatedArtifacts
        case .folders:
            return .folders
        case .studyItems:
            return .studyItems
        case .standaloneNotes:
            return .standaloneNotes
        case .tombstones:
            return .tombstones
        case .conflicts:
            return .conflicts
        case .apply:
            return .apply
        case .fileRuntime:
            return .fileRuntime
        case .transportRuntime:
            return .transportRuntime
        case .uploadRuntime:
            return .uploadRuntime
        case .objectProjection:
            return .objectProjection
        case .inventory:
            return .inventory
        case .uiIntegration:
            return .uiIntegration
        }
    }
}

nonisolated struct CanonicalShadowDomainPolicy: Codable, Equatable, Sendable {
    var failureIsFatal: Bool
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int
    var allowCanonicalMoreAggressive: Bool
    var allowedModes: [CanonicalShadowMigrationMode]

    init(
        failureIsFatal: Bool = false,
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 200,
        allowCanonicalMoreAggressive: Bool = false,
        allowedModes: [CanonicalShadowMigrationMode] = [
            .diagnosticsOnly,
            .dryRunCompare,
            .executionShadowDryRun,
            .executionShadowWithShadowFileStore
        ]
    ) {
        self.failureIsFatal = failureIsFatal
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(1, maxDiagnosticsEvents)
        self.allowCanonicalMoreAggressive = allowCanonicalMoreAggressive
        self.allowedModes = Array(Set(allowedModes)).sorted { $0.rawValue < $1.rawValue }
    }

    func permits(_ mode: CanonicalShadowMigrationMode) -> Bool {
        allowedModes.contains(mode)
    }
}

nonisolated struct CanonicalShadowDomainEnablement: Codable, Equatable, Sendable {
    var enabledDomains: [CanonicalShadowDomain]

    init(enabledDomains: [CanonicalShadowDomain] = []) {
        self.enabledDomains = Array(Set(enabledDomains)).sorted { $0.rawValue < $1.rawValue }
    }

    static let none = CanonicalShadowDomainEnablement()

    func isEnabled(_ domain: CanonicalShadowDomain) -> Bool {
        enabledDomains.contains(domain)
    }
}

nonisolated struct CanonicalSingleDomainShadowConfiguration: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var mode: CanonicalShadowMigrationMode
    var policy: CanonicalShadowDomainPolicy
    var enablement: CanonicalShadowDomainEnablement

    init(
        isEnabled: Bool = false,
        mode: CanonicalShadowMigrationMode = .disabled,
        policy: CanonicalShadowDomainPolicy = CanonicalShadowDomainPolicy(),
        enablement: CanonicalShadowDomainEnablement = .none
    ) {
        self.isEnabled = isEnabled
        self.mode = isEnabled ? mode : .disabled
        self.policy = policy
        self.enablement = isEnabled ? enablement : .none
    }

    static let disabled = CanonicalSingleDomainShadowConfiguration()

    static func enabled(
        domain: CanonicalShadowDomain,
        mode: CanonicalShadowMigrationMode,
        policy: CanonicalShadowDomainPolicy = CanonicalShadowDomainPolicy()
    ) -> CanonicalSingleDomainShadowConfiguration {
        CanonicalSingleDomainShadowConfiguration(
            isEnabled: true,
            mode: mode,
            policy: policy,
            enablement: CanonicalShadowDomainEnablement(enabledDomains: [domain])
        )
    }

    static func enabled(
        domains: [CanonicalShadowDomain],
        mode: CanonicalShadowMigrationMode,
        policy: CanonicalShadowDomainPolicy = CanonicalShadowDomainPolicy()
    ) -> CanonicalSingleDomainShadowConfiguration {
        CanonicalSingleDomainShadowConfiguration(
            isEnabled: true,
            mode: mode,
            policy: policy,
            enablement: CanonicalShadowDomainEnablement(enabledDomains: domains)
        )
    }

    var effectiveMode: CanonicalShadowMigrationMode {
        isEnabled ? mode : .disabled
    }
}

nonisolated enum CanonicalShadowDomainFailure: String, Codable, Equatable, Hashable, Sendable {
    case disabled
    case domainNotEnabled
    case unsupportedDomain
    case modeNotAllowed
    case productionExecuteBlocked
    case insufficientLocalSnapshot
    case insufficientPeerSnapshot
    case planningFailed
    case conflictDetected
    case canonicalMoreAggressiveBlocked
}

nonisolated struct CanonicalShadowDomainResult: Codable, Equatable, Sendable {
    var domain: CanonicalShadowDomain
    var mode: CanonicalShadowMigrationMode
    var allowed: Bool
    var failure: CanonicalShadowDomainFailure?
    var reason: String

    static func allowed(domain: CanonicalShadowDomain, mode: CanonicalShadowMigrationMode, reason: String) -> CanonicalShadowDomainResult {
        CanonicalShadowDomainResult(domain: domain, mode: mode, allowed: true, failure: nil, reason: reason)
    }

    static func blocked(
        domain: CanonicalShadowDomain,
        mode: CanonicalShadowMigrationMode,
        failure: CanonicalShadowDomainFailure,
        reason: String
    ) -> CanonicalShadowDomainResult {
        CanonicalShadowDomainResult(domain: domain, mode: mode, allowed: false, failure: failure, reason: reason)
    }
}

nonisolated enum CanonicalRecordingMetadataShadowSource: String, Codable, Equatable, Sendable {
    case local
    case peer
    case planner
}

nonisolated enum CanonicalRecordingMetadataShadowWriteKind: String, Codable, Equatable, Sendable {
    case apply
    case send
    case tombstoneMarker
}

nonisolated struct CanonicalRecordingMetadataShadowPrecondition: Codable, Equatable, Sendable {
    var objectID: String
    var localHashPrefix: String?
    var peerHashPrefix: String?
    var localModifiedAt: CanonicalTimestamp?
    var peerModifiedAt: CanonicalTimestamp?
    var expectedSource: CanonicalRecordingMetadataShadowSource
    var accepted: Bool
    var reason: String

    init(
        objectID: String,
        localHash: CanonicalHash?,
        peerHash: CanonicalHash?,
        localModifiedAt: CanonicalTimestamp?,
        peerModifiedAt: CanonicalTimestamp?,
        expectedSource: CanonicalRecordingMetadataShadowSource,
        accepted: Bool = true,
        reason: String
    ) {
        self.objectID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(objectID)
        self.localHashPrefix = CanonicalRecordingMetadataShadowRedaction.hashPrefix(localHash)
        self.peerHashPrefix = CanonicalRecordingMetadataShadowRedaction.hashPrefix(peerHash)
        self.localModifiedAt = localModifiedAt
        self.peerModifiedAt = peerModifiedAt
        self.expectedSource = expectedSource
        self.accepted = accepted
        self.reason = CanonicalRecordingMetadataShadowRedaction.safeText(reason)
    }
}

nonisolated struct CanonicalRecordingMetadataShadowPostcondition: Codable, Equatable, Sendable {
    var objectID: String
    var resultHashPrefix: String?
    var resultModifiedAt: CanonicalTimestamp?
    var tombstone: Bool
    var wroteShadowStore: Bool
    var wroteProductionStore: Bool
    var sentNetworkRequest: Bool
    var touchedReceiveJSON: Bool

    init(
        objectID: String,
        resultHash: CanonicalHash?,
        resultModifiedAt: CanonicalTimestamp?,
        tombstone: Bool,
        wroteShadowStore: Bool
    ) {
        self.objectID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(objectID)
        self.resultHashPrefix = CanonicalRecordingMetadataShadowRedaction.hashPrefix(resultHash)
        self.resultModifiedAt = resultModifiedAt
        self.tombstone = tombstone
        self.wroteShadowStore = wroteShadowStore
        self.wroteProductionStore = false
        self.sentNetworkRequest = false
        self.touchedReceiveJSON = false
    }
}

nonisolated struct CanonicalRecordingMetadataShadowRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { objectID }

    var objectID: String
    var metadataHashPrefix: String?
    var modifiedAt: CanonicalTimestamp?
    var tombstone: Bool
    var source: CanonicalRecordingMetadataShadowSource
    var checkpointID: String

    init(
        objectID: String,
        metadataHash: CanonicalHash?,
        modifiedAt: CanonicalTimestamp?,
        tombstone: Bool,
        source: CanonicalRecordingMetadataShadowSource,
        checkpointID: String
    ) {
        self.objectID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(objectID)
        self.metadataHashPrefix = CanonicalRecordingMetadataShadowRedaction.hashPrefix(metadataHash)
        self.modifiedAt = modifiedAt
        self.tombstone = tombstone
        self.source = source
        self.checkpointID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(checkpointID)
    }
}

nonisolated struct CanonicalRecordingMetadataShadowWrite: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID }

    var actionID: String
    var objectID: String
    var kind: CanonicalRecordingMetadataShadowWriteKind
    var source: CanonicalRecordingMetadataShadowSource
    var precondition: CanonicalRecordingMetadataShadowPrecondition
    var postcondition: CanonicalRecordingMetadataShadowPostcondition
    var rollbackCheckpointID: String
    var result: String
    var reason: String

    init(
        actionID: String,
        objectID: String,
        kind: CanonicalRecordingMetadataShadowWriteKind,
        source: CanonicalRecordingMetadataShadowSource,
        precondition: CanonicalRecordingMetadataShadowPrecondition,
        postcondition: CanonicalRecordingMetadataShadowPostcondition,
        rollbackCheckpointID: String,
        result: String,
        reason: String
    ) {
        self.actionID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(actionID)
        self.objectID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(objectID)
        self.kind = kind
        self.source = source
        self.precondition = precondition
        self.postcondition = postcondition
        self.rollbackCheckpointID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(rollbackCheckpointID)
        self.result = CanonicalRecordingMetadataShadowRedaction.safeText(result)
        self.reason = CanonicalRecordingMetadataShadowRedaction.safeText(reason)
    }
}

nonisolated enum CanonicalRecordingMetadataShadowApplyStatus: String, Codable, Equatable, Sendable {
    case applied
    case tombstoneMarked
    case noOp
    case suppressed
    case insufficientSnapshot
}

nonisolated struct CanonicalRecordingMetadataShadowApplyResult: Codable, Equatable, Sendable {
    var actionID: String
    var objectID: String
    var status: CanonicalRecordingMetadataShadowApplyStatus
    var write: CanonicalRecordingMetadataShadowWrite?

    init(
        actionID: String,
        objectID: String,
        status: CanonicalRecordingMetadataShadowApplyStatus,
        write: CanonicalRecordingMetadataShadowWrite? = nil
    ) {
        self.actionID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(actionID)
        self.objectID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(objectID)
        self.status = status
        self.write = write
    }
}

nonisolated enum CanonicalRecordingMetadataShadowSendStatus: String, Codable, Equatable, Sendable {
    case sent
    case tombstoneProjected
    case noOp
    case suppressed
    case insufficientSnapshot
}

nonisolated struct CanonicalRecordingMetadataShadowSendResult: Codable, Equatable, Sendable {
    var actionID: String
    var objectID: String
    var status: CanonicalRecordingMetadataShadowSendStatus
    var write: CanonicalRecordingMetadataShadowWrite?

    init(
        actionID: String,
        objectID: String,
        status: CanonicalRecordingMetadataShadowSendStatus,
        write: CanonicalRecordingMetadataShadowWrite? = nil
    ) {
        self.actionID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(actionID)
        self.objectID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(objectID)
        self.status = status
        self.write = write
    }
}

nonisolated final class CanonicalRecordingMetadataShadowStore: @unchecked Sendable {
    private(set) var recordsByObjectID: [String: CanonicalRecordingMetadataShadowRecord] = [:]
    private(set) var writes: [CanonicalRecordingMetadataShadowWrite] = []
    private let mode: CanonicalShadowMigrationMode

    init(mode: CanonicalShadowMigrationMode) {
        self.mode = mode
    }

    var records: [CanonicalRecordingMetadataShadowRecord] {
        recordsByObjectID.values.sorted { $0.objectID < $1.objectID }
    }

    func apply(
        action: CanonicalApplyAction,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?
    ) -> CanonicalRecordingMetadataShadowApplyResult {
        guard let peerObject else {
            return CanonicalRecordingMetadataShadowApplyResult(
                actionID: action.actionID,
                objectID: action.target.objectID,
                status: .insufficientSnapshot
            )
        }
        let write = makeWrite(
            action: action,
            kind: .apply,
            source: .peer,
            resultObject: peerObject,
            localObject: localObject,
            peerObject: peerObject,
            result: "shadowApplyRehearsed"
        )
        return CanonicalRecordingMetadataShadowApplyResult(
            actionID: action.actionID,
            objectID: action.target.objectID,
            status: .applied,
            write: write
        )
    }

    func send(
        action: CanonicalApplyAction,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?
    ) -> CanonicalRecordingMetadataShadowSendResult {
        guard let localObject else {
            return CanonicalRecordingMetadataShadowSendResult(
                actionID: action.actionID,
                objectID: action.target.objectID,
                status: .insufficientSnapshot
            )
        }
        let write = makeWrite(
            action: action,
            kind: .send,
            source: .local,
            resultObject: localObject,
            localObject: localObject,
            peerObject: peerObject,
            result: "shadowSendRehearsed"
        )
        return CanonicalRecordingMetadataShadowSendResult(
            actionID: action.actionID,
            objectID: action.target.objectID,
            status: .sent,
            write: write
        )
    }

    func markTombstone(
        action: CanonicalApplyAction,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?
    ) -> CanonicalRecordingMetadataShadowApplyResult {
        let source: CanonicalRecordingMetadataShadowSource = action.source == .local ? .local : .peer
        let resultObject = action.source == .local ? localObject : peerObject
        let write = makeWrite(
            action: action,
            kind: .tombstoneMarker,
            source: source,
            resultObject: resultObject,
            localObject: localObject,
            peerObject: peerObject,
            result: "shadowTombstoneMarkerRehearsed"
        )
        return CanonicalRecordingMetadataShadowApplyResult(
            actionID: action.actionID,
            objectID: action.target.objectID,
            status: .tombstoneMarked,
            write: write
        )
    }

    private func makeWrite(
        action: CanonicalApplyAction,
        kind: CanonicalRecordingMetadataShadowWriteKind,
        source: CanonicalRecordingMetadataShadowSource,
        resultObject: CanonicalRecordingObject?,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?,
        result: String
    ) -> CanonicalRecordingMetadataShadowWrite {
        let objectID = action.target.objectID
        let checkpointID = "recording-metadata-shadow-\(objectID)-\(kind.rawValue)"
        let precondition = CanonicalRecordingMetadataShadowPrecondition(
            objectID: objectID,
            localHash: localObject?.metadata.metadataHash,
            peerHash: peerObject?.metadata.metadataHash,
            localModifiedAt: localObject?.metadata.modifiedAt,
            peerModifiedAt: peerObject?.metadata.modifiedAt,
            expectedSource: source,
            reason: action.reason
        )
        let metadata = resultObject?.metadata
        let postcondition = CanonicalRecordingMetadataShadowPostcondition(
            objectID: objectID,
            resultHash: metadata?.metadataHash,
            resultModifiedAt: metadata?.modifiedAt,
            tombstone: metadata?.isDeleted == true || kind == .tombstoneMarker,
            wroteShadowStore: mode.recordsInMemoryShadowWrites
        )
        let write = CanonicalRecordingMetadataShadowWrite(
            actionID: action.actionID,
            objectID: objectID,
            kind: kind,
            source: source,
            precondition: precondition,
            postcondition: postcondition,
            rollbackCheckpointID: checkpointID,
            result: result,
            reason: action.reason
        )
        if mode.recordsInMemoryShadowWrites {
            recordsByObjectID[write.objectID] = CanonicalRecordingMetadataShadowRecord(
                objectID: objectID,
                metadataHash: metadata?.metadataHash,
                modifiedAt: metadata?.modifiedAt,
                tombstone: postcondition.tombstone,
                source: source,
                checkpointID: checkpointID
            )
            writes.append(write)
        }
        return write
    }
}

nonisolated enum CanonicalRecordingMetadataExecutionShadowActionKind: String, Codable, Equatable, Sendable {
    case apply
    case send
    case noOp
    case conflict
    case tombstoneMarker
    case blocked
}

nonisolated struct CanonicalRecordingMetadataExecutionShadowAction: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID }

    var actionID: String
    var objectID: String
    var kind: CanonicalRecordingMetadataExecutionShadowActionKind
    var reason: String
    var localHashPrefix: String?
    var peerHashPrefix: String?

    init(
        actionID: String,
        objectID: String,
        kind: CanonicalRecordingMetadataExecutionShadowActionKind,
        reason: String,
        localHash: CanonicalHash? = nil,
        peerHash: CanonicalHash? = nil
    ) {
        self.actionID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(actionID)
        self.objectID = CanonicalRecordingMetadataShadowRedaction.safeIdentifier(objectID)
        self.kind = kind
        self.reason = CanonicalRecordingMetadataShadowRedaction.safeText(reason)
        self.localHashPrefix = CanonicalRecordingMetadataShadowRedaction.hashPrefix(localHash)
        self.peerHashPrefix = CanonicalRecordingMetadataShadowRedaction.hashPrefix(peerHash)
    }
}

nonisolated enum CanonicalRecordingMetadataShadowEquivalence: String, Codable, Equatable, Sendable {
    case notEvaluated
    case equivalent
    case canonicalMoreConservative
    case canonicalMoreAggressive
    case divergent
    case blocked
    case insufficientSnapshot
}

nonisolated enum CanonicalRecordingMetadataShadowDivergenceKind: String, Codable, Equatable, Sendable {
    case canonicalMoreConservative
    case canonicalMoreAggressive
    case legacyDirectionMismatch
    case conflict
    case insufficientSnapshot
    case unsupportedDomain
    case productionExecuteBlocked
}

nonisolated struct CanonicalRecordingMetadataShadowDivergence: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, objectID ?? "run", reason].joined(separator: "|") }

    var kind: CanonicalRecordingMetadataShadowDivergenceKind
    var objectID: String?
    var blocking: Bool
    var reason: String

    init(
        kind: CanonicalRecordingMetadataShadowDivergenceKind,
        objectID: String? = nil,
        blocking: Bool,
        reason: String
    ) {
        self.kind = kind
        self.objectID = objectID.map(CanonicalRecordingMetadataShadowRedaction.safeIdentifier)
        self.blocking = blocking
        self.reason = CanonicalRecordingMetadataShadowRedaction.safeText(reason)
    }
}

nonisolated enum CanonicalRecordingMetadataShadowEventKind: String, Codable, Equatable, Sendable {
    case canonicalRecordingMetadataExecutionShadowStarted
    case canonicalRecordingMetadataExecutionShadowCompleted
    case canonicalRecordingMetadataExecutionShadowBlocked
    case canonicalRecordingMetadataShadowApplyRehearsed
    case canonicalRecordingMetadataShadowSendRehearsed
    case canonicalRecordingMetadataShadowNoOp
    case canonicalRecordingMetadataShadowDivergenceDetected
    case canonicalRecordingMetadataShadowEquivalent
    case canonicalRecordingMetadataShadowProductionExecuteBlocked
}

nonisolated struct CanonicalRecordingMetadataShadowDiagnostics: Codable, Equatable, Sendable {
    var syncRunID: String?
    var trigger: CanonicalShadowMigrationTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var mode: CanonicalShadowMigrationMode
    var domain: CanonicalShadowDomain
    var objectCount: Int
    var applyCount: Int
    var sendCount: Int
    var noOpCount: Int
    var conflictCount: Int
    var tombstoneCount: Int
    var divergenceCount: Int
    var blockerCount: Int
    var suppressedCount: Int
    var objectID: String?
    var hashPrefix: String?
    var reason: String?

    var summary: String {
        [
            "domain=\(domain.rawValue)",
            "mode=\(mode.rawValue)",
            "trigger=\(trigger.rawValue)",
            "nodeRole=\(nodeRole.rawValue)",
            "objects=\(objectCount)",
            "apply=\(applyCount)",
            "send=\(sendCount)",
            "noOp=\(noOpCount)",
            "conflicts=\(conflictCount)",
            "tombstones=\(tombstoneCount)",
            "divergences=\(divergenceCount)",
            "blockers=\(blockerCount)",
            "suppressed=\(suppressedCount)",
            objectID.map { "objectID=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" },
            reason.map { "reason=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }
}

nonisolated struct CanonicalRecordingMetadataShadowEvent: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, diagnostics.objectID ?? "run", diagnostics.reason ?? ""].joined(separator: "|") }

    var kind: CanonicalRecordingMetadataShadowEventKind
    var diagnostics: CanonicalRecordingMetadataShadowDiagnostics

    var diagnosticsSummary: String {
        diagnostics.summary
    }
}

nonisolated struct CanonicalRecordingMetadataExecutionShadowReport: Codable, Equatable, Sendable {
    var domainResult: CanonicalShadowDomainResult
    var syncRunID: String?
    var trigger: CanonicalShadowMigrationTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var mode: CanonicalShadowMigrationMode
    var domain: CanonicalShadowDomain
    var actions: [CanonicalRecordingMetadataExecutionShadowAction]
    var writes: [CanonicalRecordingMetadataShadowWrite]
    var records: [CanonicalRecordingMetadataShadowRecord]
    var events: [CanonicalRecordingMetadataShadowEvent]
    var divergences: [CanonicalRecordingMetadataShadowDivergence]
    var equivalence: CanonicalRecordingMetadataShadowEquivalence
    var objectCount: Int
    var applyCount: Int
    var sendCount: Int
    var noOpCount: Int
    var conflictCount: Int
    var tombstoneCount: Int
    var suppressedCount: Int

    var blockerCount: Int {
        divergences.filter(\.blocking).count
    }

    var succeeded: Bool {
        domainResult.allowed && blockerCount == 0
    }
}

typealias CanonicalRecordingMetadataShadowReport = CanonicalRecordingMetadataExecutionShadowReport

nonisolated struct CanonicalRecordingMetadataExecutionShadowPlanner {
    init() {}

    func run(
        configuration: CanonicalSingleDomainShadowConfiguration,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?,
        syncPlan providedSyncPlan: CanonicalSyncPlan? = nil,
        applyPlan providedApplyPlan: CanonicalApplyPlan? = nil,
        legacyActions: CanonicalLegacyActionSnapshot = .empty,
        syncRunID: String? = nil,
        generatedAt: Date = Date()
    ) -> CanonicalRecordingMetadataExecutionShadowReport {
        let mode = configuration.effectiveMode
        let domain = CanonicalShadowDomain.recordingMetadata
        guard configuration.isEnabled, mode != .disabled else {
            return emptyReport(
                domainResult: .blocked(domain: domain, mode: mode, failure: .disabled, reason: "singleDomainShadowDisabled"),
                configuration: configuration,
                trigger: trigger,
                nodeRole: nodeRole,
                syncRunID: syncRunID,
                equivalence: .notEvaluated
            )
        }
        guard configuration.enablement.isEnabled(.recordingMetadata) else {
            let failure: CanonicalShadowDomainFailure = configuration.enablement.enabledDomains.isEmpty ? .domainNotEnabled : .unsupportedDomain
            return emptyReport(
                domainResult: .blocked(domain: domain, mode: mode, failure: failure, reason: "recordingMetadataDomainNotEnabled"),
                configuration: configuration,
                trigger: trigger,
                nodeRole: nodeRole,
                syncRunID: syncRunID,
                equivalence: .notEvaluated
            )
        }
        guard configuration.policy.permits(mode) else {
            return blockedReport(
                configuration: configuration,
                trigger: trigger,
                nodeRole: nodeRole,
                syncRunID: syncRunID,
                failure: mode == .blockedProductionExecute ? .productionExecuteBlocked : .modeNotAllowed,
                reason: mode == .blockedProductionExecute ? "productionExecuteBlocked" : "modeNotAllowed",
                divergenceKind: mode == .blockedProductionExecute ? .productionExecuteBlocked : .unsupportedDomain
            )
        }
        guard let localManifest else {
            return blockedReport(
                configuration: configuration,
                trigger: trigger,
                nodeRole: nodeRole,
                syncRunID: syncRunID,
                failure: .insufficientLocalSnapshot,
                reason: "insufficientLocalSnapshot",
                divergenceKind: .insufficientSnapshot
            )
        }
        guard let peerManifest else {
            return blockedReport(
                configuration: configuration,
                trigger: trigger,
                nodeRole: nodeRole,
                syncRunID: syncRunID,
                failure: .insufficientPeerSnapshot,
                reason: "insufficientPeerSnapshot",
                divergenceKind: .insufficientSnapshot
            )
        }

        let syncPlan: CanonicalSyncPlan
        let applyPlan: CanonicalApplyPlan
        do {
            if let providedSyncPlan {
                syncPlan = providedSyncPlan
            } else {
                syncPlan = try CanonicalSyncPlanner().plan(local: localManifest, peer: peerManifest, trigger: .manual)
            }
            if let providedApplyPlan {
                applyPlan = providedApplyPlan
            } else {
                applyPlan = CanonicalApplyPlanner().plan(
                    local: localManifest,
                    peer: peerManifest,
                    syncPlan: syncPlan,
                    trigger: syncPlanTrigger(from: trigger)
                )
            }
        } catch {
            return blockedReport(
                configuration: configuration,
                trigger: trigger,
                nodeRole: nodeRole,
                syncRunID: syncRunID,
                failure: .planningFailed,
                reason: "planningFailed",
                divergenceKind: .insufficientSnapshot
            )
        }

        let localObjects = Dictionary(uniqueKeysWithValues: localManifest.objects.map { ($0.objectID, $0) })
        let peerObjects = Dictionary(uniqueKeysWithValues: peerManifest.objects.map { ($0.objectID, $0) })
        let objectIDs = Set(localObjects.keys).union(peerObjects.keys).sorted()
        let recordingActions = recordingMetadataActions(from: applyPlan)
        let conflicts = recordingMetadataConflicts(from: applyPlan, syncPlan: syncPlan)
        let noOps = syncPlan.noOpRecordingMetadata
        let canonicalActionIDs = canonicalDirectionalIDs(from: recordingActions)
        let legacyActionIDs = normalizedLegacyRecordingMetadataIDs(
            legacyActions.actionIDs(for: .recordingMetadata),
            objectIDs: objectIDs
        )
        var actions: [CanonicalRecordingMetadataExecutionShadowAction] = []
        var divergences: [CanonicalRecordingMetadataShadowDivergence] = []
        var equivalence = evaluateEquivalence(
            canonicalIDs: canonicalActionIDs,
            legacyIDs: legacyActionIDs,
            noOps: noOps,
            conflicts: conflicts,
            policy: configuration.policy,
            divergences: &divergences
        )
        let blocksExecution = divergences.contains(where: \.blocking)
        let domainResult: CanonicalShadowDomainResult = blocksExecution
            ? .blocked(
                domain: .recordingMetadata,
                mode: mode,
                failure: conflicts.isEmpty ? .canonicalMoreAggressiveBlocked : .conflictDetected,
                reason: divergences.first(where: \.blocking)?.reason ?? "recordingMetadataShadowBlocked"
            )
            : .allowed(domain: .recordingMetadata, mode: mode, reason: "recordingMetadataShadowEnabled")
        if blocksExecution {
            equivalence = equivalence == .canonicalMoreAggressive ? .canonicalMoreAggressive : .blocked
        }

        let store = CanonicalRecordingMetadataShadowStore(mode: mode)
        var applyCount = 0
        var sendCount = 0
        var tombstoneCount = 0
        var suppressedCount = 0
        var events: [CanonicalRecordingMetadataShadowEvent] = [
            makeEvent(
                .canonicalRecordingMetadataExecutionShadowStarted,
                configuration: configuration,
                trigger: trigger,
                nodeRole: nodeRole,
                syncRunID: syncRunID,
                objectCount: objectIDs.count,
                reason: "started"
            )
        ]

        for noOp in noOps {
            actions.append(
                CanonicalRecordingMetadataExecutionShadowAction(
                    actionID: "recordingMetadataNoOp:\(noOp.objectID)",
                    objectID: noOp.objectID,
                    kind: .noOp,
                    reason: noOp.reason.rawValue,
                    localHash: noOp.localMetadataHash,
                    peerHash: noOp.peerMetadataHash
                )
            )
            events.append(
                makeEvent(
                    .canonicalRecordingMetadataShadowNoOp,
                    configuration: configuration,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    syncRunID: syncRunID,
                    objectCount: objectIDs.count,
                    noOpCount: noOps.count,
                    objectID: noOp.objectID,
                    hashPrefix: CanonicalRecordingMetadataShadowRedaction.hashPrefix(noOp.localMetadataHash ?? noOp.peerMetadataHash),
                    reason: noOp.reason.rawValue
                )
            )
        }

        for conflict in conflicts {
            actions.append(
                CanonicalRecordingMetadataExecutionShadowAction(
                    actionID: conflict.conflictID,
                    objectID: conflict.target.objectID,
                    kind: .conflict,
                    reason: conflict.detail ?? conflict.kind.rawValue
                )
            )
            events.append(
                makeEvent(
                    .canonicalRecordingMetadataShadowDivergenceDetected,
                    configuration: configuration,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    syncRunID: syncRunID,
                    objectCount: objectIDs.count,
                    conflictCount: conflicts.count,
                    divergenceCount: divergences.count,
                    blockerCount: divergences.filter(\.blocking).count,
                    objectID: conflict.target.objectID,
                    reason: conflict.kind.rawValue
                )
            )
        }

        if equivalence == .equivalent {
            events.append(
                makeEvent(
                    .canonicalRecordingMetadataShadowEquivalent,
                    configuration: configuration,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    syncRunID: syncRunID,
                    objectCount: objectIDs.count,
                    reason: "canonicalAndLegacySameDirection"
                )
            )
        }

        if divergences.contains(where: { $0.kind == .canonicalMoreConservative }) {
            suppressedCount += legacyActionIDs.count
            events.append(
                makeEvent(
                    .canonicalRecordingMetadataShadowDivergenceDetected,
                    configuration: configuration,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    syncRunID: syncRunID,
                    objectCount: objectIDs.count,
                    divergenceCount: divergences.count,
                    suppressedCount: suppressedCount,
                    reason: "canonicalMoreConservative"
                )
            )
        }

        if blocksExecution {
            suppressedCount += recordingActions.count
            events.append(
                makeEvent(
                    .canonicalRecordingMetadataShadowProductionExecuteBlocked,
                    configuration: configuration,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    syncRunID: syncRunID,
                    objectCount: objectIDs.count,
                    divergenceCount: divergences.count,
                    blockerCount: divergences.filter(\.blocking).count,
                    suppressedCount: suppressedCount,
                    reason: divergences.first(where: \.blocking)?.reason ?? "recordingMetadataShadowBlocked"
                )
            )
            events.append(
                makeEvent(
                    .canonicalRecordingMetadataExecutionShadowBlocked,
                    configuration: configuration,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    syncRunID: syncRunID,
                    objectCount: objectIDs.count,
                    conflictCount: conflicts.count,
                    divergenceCount: divergences.count,
                    blockerCount: divergences.filter(\.blocking).count,
                    suppressedCount: suppressedCount,
                    reason: domainResult.reason
                )
            )
        } else {
            for action in recordingActions {
                switch action.kind {
                case .recordingMetadataApply:
                    let result = store.apply(
                        action: action,
                        localObject: localObjects[action.target.objectID],
                        peerObject: peerObjects[action.target.objectID]
                    )
                    applyCount += result.status == .applied ? 1 : 0
                    actions.append(shadowAction(from: action, kind: .apply, localObject: localObjects[action.target.objectID], peerObject: peerObjects[action.target.objectID]))
                    events.append(
                        makeEvent(
                            .canonicalRecordingMetadataShadowApplyRehearsed,
                            configuration: configuration,
                            trigger: trigger,
                            nodeRole: nodeRole,
                            syncRunID: syncRunID,
                            objectCount: objectIDs.count,
                            applyCount: applyCount,
                            objectID: action.target.objectID,
                            hashPrefix: result.write?.postcondition.resultHashPrefix,
                            reason: action.reason
                        )
                    )
                case .recordingMetadataSend:
                    let result = store.send(
                        action: action,
                        localObject: localObjects[action.target.objectID],
                        peerObject: peerObjects[action.target.objectID]
                    )
                    sendCount += result.status == .sent ? 1 : 0
                    actions.append(shadowAction(from: action, kind: .send, localObject: localObjects[action.target.objectID], peerObject: peerObjects[action.target.objectID]))
                    events.append(
                        makeEvent(
                            .canonicalRecordingMetadataShadowSendRehearsed,
                            configuration: configuration,
                            trigger: trigger,
                            nodeRole: nodeRole,
                            syncRunID: syncRunID,
                            objectCount: objectIDs.count,
                            sendCount: sendCount,
                            objectID: action.target.objectID,
                            hashPrefix: result.write?.postcondition.resultHashPrefix,
                            reason: action.reason
                        )
                    )
                case .objectTombstoneApply, .objectTombstoneSend:
                    let result = store.markTombstone(
                        action: action,
                        localObject: localObjects[action.target.objectID],
                        peerObject: peerObjects[action.target.objectID]
                    )
                    tombstoneCount += result.status == .tombstoneMarked ? 1 : 0
                    if action.kind == .objectTombstoneApply {
                        applyCount += 1
                    } else {
                        sendCount += 1
                    }
                    actions.append(shadowAction(from: action, kind: .tombstoneMarker, localObject: localObjects[action.target.objectID], peerObject: peerObjects[action.target.objectID]))
                    events.append(
                        makeEvent(
                            action.kind == .objectTombstoneApply ? .canonicalRecordingMetadataShadowApplyRehearsed : .canonicalRecordingMetadataShadowSendRehearsed,
                            configuration: configuration,
                            trigger: trigger,
                            nodeRole: nodeRole,
                            syncRunID: syncRunID,
                            objectCount: objectIDs.count,
                            applyCount: applyCount,
                            sendCount: sendCount,
                            tombstoneCount: tombstoneCount,
                            objectID: action.target.objectID,
                            hashPrefix: result.write?.postcondition.resultHashPrefix,
                            reason: "tombstoneMarkerOnly"
                        )
                    )
                case .conflictRecord, .folderMetadataApply, .folderMetadataSend, .studyItemMetadataApply,
                     .studyItemMetadataSend, .libraryTombstoneApply, .libraryTombstoneSend,
                     .generatedArtifactDownloadApply, .generatedArtifactNoOp, .artifactTombstoneApply,
                     .deferredUnsupported:
                    break
                }
            }
            if !recordingActions.isEmpty {
                events.append(
                    makeEvent(
                        .canonicalRecordingMetadataShadowProductionExecuteBlocked,
                        configuration: configuration,
                        trigger: trigger,
                        nodeRole: nodeRole,
                        syncRunID: syncRunID,
                        objectCount: objectIDs.count,
                        applyCount: applyCount,
                        sendCount: sendCount,
                        tombstoneCount: tombstoneCount,
                        reason: "productionRouteAndStoreSuppressed"
                    )
                )
            }
            events.append(
                makeEvent(
                    .canonicalRecordingMetadataExecutionShadowCompleted,
                    configuration: configuration,
                    trigger: trigger,
                    nodeRole: nodeRole,
                    syncRunID: syncRunID,
                    objectCount: objectIDs.count,
                    applyCount: applyCount,
                    sendCount: sendCount,
                    noOpCount: noOps.count,
                    conflictCount: conflicts.count,
                    tombstoneCount: tombstoneCount,
                    divergenceCount: divergences.count,
                    suppressedCount: suppressedCount,
                    reason: "completed"
                )
            )
        }

        _ = generatedAt
        return CanonicalRecordingMetadataExecutionShadowReport(
            domainResult: domainResult,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            mode: mode,
            domain: .recordingMetadata,
            actions: actions.sorted { $0.actionID < $1.actionID },
            writes: store.writes,
            records: store.records,
            events: events.prefix(configuration.policy.maxDiagnosticsEvents).map { $0 },
            divergences: divergences,
            equivalence: equivalence,
            objectCount: objectIDs.count,
            applyCount: applyCount,
            sendCount: sendCount,
            noOpCount: noOps.count,
            conflictCount: conflicts.count,
            tombstoneCount: tombstoneCount,
            suppressedCount: suppressedCount
        )
    }

    private func recordingMetadataActions(from applyPlan: CanonicalApplyPlan) -> [CanonicalApplyAction] {
        applyPlan.actions.filter {
            switch $0.kind {
            case .recordingMetadataApply, .recordingMetadataSend, .objectTombstoneApply, .objectTombstoneSend:
                return true
            case .folderMetadataApply, .folderMetadataSend, .studyItemMetadataApply, .studyItemMetadataSend,
                 .libraryTombstoneApply, .libraryTombstoneSend, .generatedArtifactDownloadApply,
                 .generatedArtifactNoOp, .artifactTombstoneApply, .conflictRecord, .deferredUnsupported:
                return false
            }
        }
        .sorted { $0.actionID < $1.actionID }
    }

    private func recordingMetadataConflicts(
        from applyPlan: CanonicalApplyPlan,
        syncPlan: CanonicalSyncPlan
    ) -> [CanonicalConflictRecord] {
        var conflicts = applyPlan.conflicts.filter {
            $0.kind == .recordingMetadataConcurrentEdit || $0.kind == .activeVsTombstone
        }
        let existingIDs = Set(conflicts.map(\.target.objectID))
        conflicts += syncPlan.conflictRecordingMetadata.compactMap { action in
            guard !existingIDs.contains(action.objectID) else {
                return nil
            }
            return CanonicalConflictRecord(
                kind: .recordingMetadataConcurrentEdit,
                target: CanonicalApplyTarget(objectID: action.objectID),
                resolutionPolicy: .manualReview,
                localHash: action.localMetadataHash,
                peerHash: action.peerMetadataHash,
                localModifiedAt: action.localModifiedAt,
                peerModifiedAt: action.peerModifiedAt,
                detail: action.reason.rawValue
            )
        }
        return conflicts.sorted { $0.conflictID < $1.conflictID }
    }

    private func canonicalDirectionalIDs(from actions: [CanonicalApplyAction]) -> Set<String> {
        Set(actions.compactMap { action -> String? in
            switch action.kind {
            case .recordingMetadataApply, .objectTombstoneApply:
                return "recordingMetadataApply:\(action.target.objectID)"
            case .recordingMetadataSend, .objectTombstoneSend:
                return "recordingMetadataSend:\(action.target.objectID)"
            case .folderMetadataApply, .folderMetadataSend, .studyItemMetadataApply, .studyItemMetadataSend,
                 .libraryTombstoneApply, .libraryTombstoneSend, .generatedArtifactDownloadApply,
                 .generatedArtifactNoOp, .artifactTombstoneApply, .conflictRecord, .deferredUnsupported:
                return nil
            }
        })
    }

    private func normalizedLegacyRecordingMetadataIDs(_ ids: [String], objectIDs: [String]) -> Set<String> {
        var result = Set<String>()
        for id in ids {
            let raw = CanonicalRecordingMetadataShadowRedaction.safeText(id)
            if raw.hasPrefix("recordingMetadataApply:") || raw.hasPrefix("recordingMetadataSend:") {
                result.insert(raw)
                continue
            }
            let pieces = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if pieces.count >= 4, pieces[1] == "recording" {
                if pieces[0] == LocalNetworkSyncDiffActionKind.uploadMetadata.rawValue {
                    result.insert("recordingMetadataSend:\(pieces[2])")
                    continue
                }
                if pieces[0] == LocalNetworkSyncDiffActionKind.downloadMetadata.rawValue {
                    result.insert("recordingMetadataApply:\(pieces[2])")
                    continue
                }
            }
            if objectIDs.contains(raw) {
                result.insert("recordingMetadataSend:\(raw)")
                result.insert("recordingMetadataApply:\(raw)")
                continue
            }
            if let objectID = objectIDs.first(where: { raw.contains($0) }) {
                if raw.lowercased().contains("download") || raw.lowercased().contains("apply") {
                    result.insert("recordingMetadataApply:\(objectID)")
                } else if raw.lowercased().contains("upload") || raw.lowercased().contains("send") {
                    result.insert("recordingMetadataSend:\(objectID)")
                }
            }
        }
        return result
    }

    private func evaluateEquivalence(
        canonicalIDs: Set<String>,
        legacyIDs: Set<String>,
        noOps: [CanonicalRecordingMetadataAction],
        conflicts: [CanonicalConflictRecord],
        policy: CanonicalShadowDomainPolicy,
        divergences: inout [CanonicalRecordingMetadataShadowDivergence]
    ) -> CanonicalRecordingMetadataShadowEquivalence {
        if !conflicts.isEmpty {
            divergences += conflicts.map {
                CanonicalRecordingMetadataShadowDivergence(
                    kind: .conflict,
                    objectID: $0.target.objectID,
                    blocking: true,
                    reason: $0.kind.rawValue
                )
            }
            return .blocked
        }
        if canonicalIDs == legacyIDs {
            return canonicalIDs.isEmpty ? .notEvaluated : .equivalent
        }
        if canonicalIDs.isEmpty, !legacyIDs.isEmpty {
            let noOpObjectIDs = Set(noOps.map(\.objectID))
            let legacyObjectIDs = Set(legacyIDs.compactMap { $0.split(separator: ":").last.map(String.init) })
            let nonBlocking = legacyObjectIDs.isSubset(of: noOpObjectIDs) || noOpObjectIDs.isEmpty == false
            divergences.append(
                CanonicalRecordingMetadataShadowDivergence(
                    kind: .canonicalMoreConservative,
                    blocking: false,
                    reason: nonBlocking ? "canonicalMoreConservative" : "legacyOnlyRecordingMetadata"
                )
            )
            return .canonicalMoreConservative
        }
        if !canonicalIDs.isEmpty, legacyIDs.isEmpty {
            divergences.append(
                CanonicalRecordingMetadataShadowDivergence(
                    kind: .canonicalMoreAggressive,
                    blocking: !policy.allowCanonicalMoreAggressive,
                    reason: "canonicalMoreAggressive"
                )
            )
            return .canonicalMoreAggressive
        }
        divergences.append(
            CanonicalRecordingMetadataShadowDivergence(
                kind: .legacyDirectionMismatch,
                blocking: true,
                reason: "legacyDirectionMismatch"
            )
        )
        return .divergent
    }

    private func shadowAction(
        from action: CanonicalApplyAction,
        kind: CanonicalRecordingMetadataExecutionShadowActionKind,
        localObject: CanonicalRecordingObject?,
        peerObject: CanonicalRecordingObject?
    ) -> CanonicalRecordingMetadataExecutionShadowAction {
        CanonicalRecordingMetadataExecutionShadowAction(
            actionID: action.actionID,
            objectID: action.target.objectID,
            kind: kind,
            reason: action.reason,
            localHash: localObject?.metadata.metadataHash,
            peerHash: peerObject?.metadata.metadataHash
        )
    }

    private func syncPlanTrigger(from trigger: CanonicalShadowMigrationTrigger) -> CanonicalSyncPlanTrigger {
        switch trigger {
        case .periodic:
            return .periodic
        case .appActivation:
            return .appActivation
        case .retryDrainer:
            return .retryDrainer
        case .viewRefresh:
            return .viewRefresh
        case .iPhoneSyncTick, .macInventory, .macReceiver, .manual, .testHarness:
            return .manual
        }
    }

    private func blockedReport(
        configuration: CanonicalSingleDomainShadowConfiguration,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?,
        failure: CanonicalShadowDomainFailure,
        reason: String,
        divergenceKind: CanonicalRecordingMetadataShadowDivergenceKind
    ) -> CanonicalRecordingMetadataExecutionShadowReport {
        let mode = configuration.effectiveMode
        let divergence = CanonicalRecordingMetadataShadowDivergence(
            kind: divergenceKind,
            blocking: true,
            reason: reason
        )
        let domainResult = CanonicalShadowDomainResult.blocked(
            domain: .recordingMetadata,
            mode: mode,
            failure: failure,
            reason: reason
        )
        let started = makeEvent(
            .canonicalRecordingMetadataExecutionShadowStarted,
            configuration: configuration,
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID,
            reason: "started"
        )
        let blocked = makeEvent(
            .canonicalRecordingMetadataExecutionShadowBlocked,
            configuration: configuration,
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID,
            divergenceCount: 1,
            blockerCount: 1,
            reason: reason
        )
        let productionBlocked = makeEvent(
            .canonicalRecordingMetadataShadowProductionExecuteBlocked,
            configuration: configuration,
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID,
            divergenceCount: 1,
            blockerCount: 1,
            reason: reason
        )
        return CanonicalRecordingMetadataExecutionShadowReport(
            domainResult: domainResult,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            mode: mode,
            domain: .recordingMetadata,
            actions: [],
            writes: [],
            records: [],
            events: [started, productionBlocked, blocked].prefix(configuration.policy.maxDiagnosticsEvents).map { $0 },
            divergences: [divergence],
            equivalence: .insufficientSnapshot,
            objectCount: 0,
            applyCount: 0,
            sendCount: 0,
            noOpCount: 0,
            conflictCount: 0,
            tombstoneCount: 0,
            suppressedCount: 0
        )
    }

    private func emptyReport(
        domainResult: CanonicalShadowDomainResult,
        configuration: CanonicalSingleDomainShadowConfiguration,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?,
        equivalence: CanonicalRecordingMetadataShadowEquivalence
    ) -> CanonicalRecordingMetadataExecutionShadowReport {
        CanonicalRecordingMetadataExecutionShadowReport(
            domainResult: domainResult,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            mode: configuration.effectiveMode,
            domain: .recordingMetadata,
            actions: [],
            writes: [],
            records: [],
            events: [],
            divergences: [],
            equivalence: equivalence,
            objectCount: 0,
            applyCount: 0,
            sendCount: 0,
            noOpCount: 0,
            conflictCount: 0,
            tombstoneCount: 0,
            suppressedCount: 0
        )
    }

    private func makeEvent(
        _ kind: CanonicalRecordingMetadataShadowEventKind,
        configuration: CanonicalSingleDomainShadowConfiguration,
        trigger: CanonicalShadowMigrationTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?,
        objectCount: Int = 0,
        applyCount: Int = 0,
        sendCount: Int = 0,
        noOpCount: Int = 0,
        conflictCount: Int = 0,
        tombstoneCount: Int = 0,
        divergenceCount: Int = 0,
        blockerCount: Int = 0,
        suppressedCount: Int = 0,
        objectID: String? = nil,
        hashPrefix: String? = nil,
        reason: String? = nil
    ) -> CanonicalRecordingMetadataShadowEvent {
        CanonicalRecordingMetadataShadowEvent(
            kind: kind,
            diagnostics: CanonicalRecordingMetadataShadowDiagnostics(
                syncRunID: syncRunID.map(CanonicalRecordingMetadataShadowRedaction.safeIdentifier),
                trigger: trigger,
                nodeRole: nodeRole,
                mode: configuration.effectiveMode,
                domain: .recordingMetadata,
                objectCount: objectCount,
                applyCount: applyCount,
                sendCount: sendCount,
                noOpCount: noOpCount,
                conflictCount: conflictCount,
                tombstoneCount: tombstoneCount,
                divergenceCount: divergenceCount,
                blockerCount: blockerCount,
                suppressedCount: suppressedCount,
                objectID: objectID.map(CanonicalRecordingMetadataShadowRedaction.safeIdentifier),
                hashPrefix: hashPrefix.map(CanonicalRecordingMetadataShadowRedaction.safeText),
                reason: reason.map(CanonicalRecordingMetadataShadowRedaction.safeText)
            )
        )
    }
}

private extension CanonicalShadowMigrationMode {
    nonisolated var recordsInMemoryShadowWrites: Bool {
        switch self {
        case .dryRunCompare, .executionShadowDryRun, .executionShadowWithShadowFileStore:
            return true
        case .disabled, .diagnosticsOnly, .shadowReadOnly, .shadowReadOnlyWithNetworkProbe,
             .executionShadowWithReadOnlyTransportProbe, .blockedProductionExecute,
             .blockedExecutionShadowWrite, .blockedExecutionShadowUpload, .blockedExecutionShadowApply:
            return false
        }
    }
}

private enum CanonicalRecordingMetadataShadowRedaction {
    nonisolated static func safeIdentifier(_ value: String) -> String {
        let text = safeText(value)
        return text.isEmpty ? "unknown" : text
    }

    nonisolated static func safeText(_ value: String) -> String {
        let filtered = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { character in
                character.isLetter || character.isNumber || "-_:|./".contains(character)
            }
        return String(filtered.prefix(160))
    }

    nonisolated static func hashPrefix(_ hash: CanonicalHash?) -> String? {
        hash.map { String($0.value.prefix(12)) }
    }
}
