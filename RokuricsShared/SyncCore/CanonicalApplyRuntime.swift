//
//  CanonicalApplyRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated enum CanonicalApplyExecutionStatus: String, Codable, Equatable, Sendable {
    case applied
    case sent
    case noOp
    case conflictRecorded
    case deferredUnsupported
    case failed
}

nonisolated struct CanonicalApplyExecutionRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID }
    var actionID: String
    var kind: CanonicalApplyActionKind
    var target: CanonicalApplyTarget
    var status: CanonicalApplyExecutionStatus
    var contentHashPrefix: String?
    var byteSize: Int64?
    var failure: CanonicalApplyFailureReason?
    var detail: String?
}

nonisolated struct CanonicalApplyExecutionReport: Codable, Equatable, Sendable {
    var records: [CanonicalApplyExecutionRecord]
    var conflictReport: CanonicalConflictResolverReport
    var appliedCount: Int
    var failedCount: Int
}

nonisolated struct CanonicalApplyRuntimeContext: Sendable {
    var localManifest: CanonicalManifest
    var peerManifest: CanonicalManifest
    var localFileStore: any CanonicalFileStorePort
    var peerFileStore: any CanonicalFileStorePort
    var localMetadataRoot: CanonicalRootToken
    var peerMetadataRoot: CanonicalRootToken
    var localGeneratedRoot: CanonicalRootToken
    var peerGeneratedRoot: CanonicalRootToken

    nonisolated init(
        localManifest: CanonicalManifest,
        peerManifest: CanonicalManifest,
        localFileStore: any CanonicalFileStorePort,
        peerFileStore: any CanonicalFileStorePort,
        localMetadataRoot: CanonicalRootToken,
        peerMetadataRoot: CanonicalRootToken,
        localGeneratedRoot: CanonicalRootToken,
        peerGeneratedRoot: CanonicalRootToken
    ) {
        self.localManifest = localManifest
        self.peerManifest = peerManifest
        self.localFileStore = localFileStore
        self.peerFileStore = peerFileStore
        self.localMetadataRoot = localMetadataRoot
        self.peerMetadataRoot = peerMetadataRoot
        self.localGeneratedRoot = localGeneratedRoot
        self.peerGeneratedRoot = peerGeneratedRoot
    }
}

nonisolated enum CanonicalApplyRuntimeError: Error, Equatable, Sendable {
    case missingSourceObject(String)
    case missingSourceArtifact(String)
    case missingLogicalPathToken(String)
    case hashOrSizeMismatch(String)
}

nonisolated enum CanonicalApplyRuntimeMode: String, Codable, Equatable, Sendable {
    case disabled
    case diagnosticsOnly
    case noCommit
    case testRootApply
    case productionRootApplyWithLegacyFallback
    case blocked

    nonisolated var executesCommit: Bool {
        switch self {
        case .testRootApply, .productionRootApplyWithLegacyFallback:
            return true
        case .disabled, .diagnosticsOnly, .noCommit, .blocked:
            return false
        }
    }

    nonisolated var syncDiagnosticMode: CanonicalSyncRuntimeMode {
        switch self {
        case .disabled:
            return .disabled
        case .diagnosticsOnly:
            return .diagnosticsOnly
        case .noCommit:
            return .canonicalPlanNoCommit
        case .testRootApply, .productionRootApplyWithLegacyFallback:
            return .canonicalPlanPrimaryWithLegacyFallback
        case .blocked:
            return .blocked
        }
    }
}

nonisolated enum CanonicalApplyRuntimeDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case libraryMetadata
    case generatedArtifacts
    case tombstoneConflict
    case recordingExistence
    case audioUpload
}

nonisolated enum CanonicalApplyRuntimeUnsupportedDomain: String, Codable, Equatable, Hashable, Sendable {
    case audioUpload
    case readSideCutover
    case resourceMove
    case standaloneNoteContent
    case permanentDelete
    case tombstoneGarbageCollection
}

nonisolated enum CanonicalApplyRuntimeBlocker: String, Codable, Equatable, Hashable, Sendable {
    case disabledMode
    case diagnosticsOnly
    case noCommit
    case blockedMode
    case canonicalPlanAuthorityUnavailable
    case inventorySnapshotInvalid
    case applyPlanInvalid
    case enabledDomainsMissing
    case domainNotEnabled
    case missingExecutor
    case dryRunOnlyExecutor
    case rootBoundApplyPortUnavailable
    case rollbackUnavailable
    case postconditionUnavailable
    case legacyFallbackUnavailable
    case unresolvedConflict
    case audioActionBlocked
    case resourceMoveBlocked
    case standaloneNoteContentWriteBlocked
    case permanentDeleteBlocked
    case tombstoneGarbageCollectionBlocked
    case diagnosticsNotRedacted
    case releaseDefaultProductionApplyBlocked
    case debugInternalApprovalMissing
    case runtimeSwitchEnabled
    case readPathNotLegacy
    case unsupportedDomain
    case rollbackFailureFatal
    case actionFailed
}

typealias CanonicalApplyRuntimeGateBlocker = CanonicalApplyRuntimeBlocker

nonisolated struct CanonicalApplyRuntimePolicy: Codable, Equatable, Sendable {
    var debugInternalBuild: Bool
    var ownerApproved: Bool
    var releaseDefaultBuild: Bool
    var legacyFallbackAvailable: Bool
    var diagnosticsRedacted: Bool
    var runtimeSwitchEnabled: Bool
    var readPathLegacy: Bool
    var enabledDomains: [CanonicalApplyRuntimeDomain]
    var allowConflictRecordAction: Bool
    var allowTestRootApply: Bool

    nonisolated init(
        debugInternalBuild: Bool = false,
        ownerApproved: Bool = false,
        releaseDefaultBuild: Bool = true,
        legacyFallbackAvailable: Bool = true,
        diagnosticsRedacted: Bool = true,
        runtimeSwitchEnabled: Bool = false,
        readPathLegacy: Bool = true,
        enabledDomains: [CanonicalApplyRuntimeDomain] = [],
        allowConflictRecordAction: Bool = true,
        allowTestRootApply: Bool = true
    ) {
        self.debugInternalBuild = debugInternalBuild
        self.ownerApproved = ownerApproved
        self.releaseDefaultBuild = releaseDefaultBuild
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.diagnosticsRedacted = diagnosticsRedacted
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.readPathLegacy = readPathLegacy
        self.enabledDomains = Array(Set(enabledDomains)).sorted { $0.rawValue < $1.rawValue }
        self.allowConflictRecordAction = allowConflictRecordAction
        self.allowTestRootApply = allowTestRootApply
    }
}

nonisolated struct CanonicalApplyRuntimeConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalApplyRuntimeMode
    var policy: CanonicalApplyRuntimePolicy

    nonisolated init(
        mode: CanonicalApplyRuntimeMode = .disabled,
        policy: CanonicalApplyRuntimePolicy = CanonicalApplyRuntimePolicy()
    ) {
        self.mode = mode
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalApplyRuntimeConfiguration()
}

nonisolated enum CanonicalApplyRuntimeGateState: String, Codable, Equatable, Sendable {
    case legacyOwner
    case diagnosticsOnly
    case noCommit
    case allowed
    case blocked
}

nonisolated struct CanonicalApplyRuntimeGateResult: Codable, Equatable, Sendable {
    var state: CanonicalApplyRuntimeGateState
    var blockers: [CanonicalApplyRuntimeGateBlocker]
    var mode: CanonicalApplyRuntimeMode

    nonisolated var isAllowed: Bool {
        blockers.isEmpty && state == .allowed
    }

    nonisolated var executesCommit: Bool {
        isAllowed && mode.executesCommit
    }

    nonisolated var usesLegacyFallback: Bool {
        !executesCommit
    }

    nonisolated init(
        state: CanonicalApplyRuntimeGateState,
        blockers: [CanonicalApplyRuntimeGateBlocker],
        mode: CanonicalApplyRuntimeMode
    ) {
        self.state = state
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.mode = mode
    }
}

nonisolated struct CanonicalApplyRuntimeOwnerContext: Sendable {
    var configuration: CanonicalApplyRuntimeConfiguration
    var applyPlan: CanonicalApplyPlan
    var libraryPlan: CanonicalLibrarySyncPlan?
    var localManifest: CanonicalManifest?
    var peerManifest: CanonicalManifest?
    var inventorySnapshotValid: Bool
    var canonicalPlanAuthorityAllowed: Bool
    var legacyFallbackAvailable: Bool
    var registry: CanonicalApplyRuntimeExecutorRegistry
    var syncRunID: String?

    nonisolated init(
        configuration: CanonicalApplyRuntimeConfiguration,
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        localManifest: CanonicalManifest? = nil,
        peerManifest: CanonicalManifest? = nil,
        inventorySnapshotValid: Bool = false,
        canonicalPlanAuthorityAllowed: Bool = false,
        legacyFallbackAvailable: Bool = true,
        registry: CanonicalApplyRuntimeExecutorRegistry = CanonicalApplyRuntimeExecutorRegistry(),
        syncRunID: String? = nil
    ) {
        self.configuration = configuration
        self.applyPlan = applyPlan
        self.libraryPlan = libraryPlan
        self.localManifest = localManifest
        self.peerManifest = peerManifest
        self.inventorySnapshotValid = inventorySnapshotValid
        self.canonicalPlanAuthorityAllowed = canonicalPlanAuthorityAllowed
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.registry = registry
        self.syncRunID = syncRunID
    }

    nonisolated var allActions: [CanonicalApplyAction] {
        var seen = Set<String>()
        return (applyPlan.actions + (libraryPlan?.applyActions ?? [])).filter { seen.insert($0.actionID).inserted }
    }
}

nonisolated struct CanonicalApplyRuntimeExecutorContext: Sendable {
    var action: CanonicalApplyAction
    var applyPlan: CanonicalApplyPlan
    var libraryPlan: CanonicalLibrarySyncPlan?
    var localManifest: CanonicalManifest
    var peerManifest: CanonicalManifest
    var syncRunID: String?
}

nonisolated struct CanonicalApplyRuntimeExecutorResult: Codable, Equatable, Sendable {
    var actionID: String
    var objectID: String
    var domain: CanonicalApplyRuntimeDomain
    var committed: Bool
    var preconditionVerified: Bool
    var postconditionVerified: Bool
    var rollbackAttempted: Bool
    var rollbackSucceeded: Bool?
    var rollbackFatal: Bool
    var failureReason: String?
    var detail: String?

    nonisolated init(
        actionID: String,
        objectID: String,
        domain: CanonicalApplyRuntimeDomain,
        committed: Bool,
        preconditionVerified: Bool = true,
        postconditionVerified: Bool = true,
        rollbackAttempted: Bool = false,
        rollbackSucceeded: Bool? = nil,
        rollbackFatal: Bool = false,
        failureReason: String? = nil,
        detail: String? = nil
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(actionID, fallback: domain.rawValue)
        self.objectID = CanonicalProductionRedaction.safeIdentifier(objectID, fallback: "canonical-object")
        self.domain = domain
        self.committed = committed
        self.preconditionVerified = preconditionVerified
        self.postconditionVerified = postconditionVerified
        self.rollbackAttempted = rollbackAttempted
        self.rollbackSucceeded = rollbackSucceeded
        self.rollbackFatal = rollbackFatal
        self.failureReason = CanonicalProductionRedaction.safeDiagnosticText(failureReason)
        self.detail = CanonicalProductionRedaction.safeDiagnosticText(detail)
    }

    nonisolated var succeeded: Bool {
        committed && preconditionVerified && postconditionVerified && rollbackFatal == false
    }

    nonisolated static func success(
        action: CanonicalApplyAction,
        domain: CanonicalApplyRuntimeDomain,
        detail: String? = nil
    ) -> CanonicalApplyRuntimeExecutorResult {
        CanonicalApplyRuntimeExecutorResult(
            actionID: action.actionID,
            objectID: action.target.objectID,
            domain: domain,
            committed: true,
            detail: detail
        )
    }

    nonisolated static func failure(
        action: CanonicalApplyAction,
        domain: CanonicalApplyRuntimeDomain,
        preconditionVerified: Bool = true,
        postconditionVerified: Bool = true,
        rollbackAttempted: Bool = false,
        rollbackSucceeded: Bool? = nil,
        rollbackFatal: Bool = false,
        reason: String
    ) -> CanonicalApplyRuntimeExecutorResult {
        CanonicalApplyRuntimeExecutorResult(
            actionID: action.actionID,
            objectID: action.target.objectID,
            domain: domain,
            committed: false,
            preconditionVerified: preconditionVerified,
            postconditionVerified: postconditionVerified,
            rollbackAttempted: rollbackAttempted,
            rollbackSucceeded: rollbackSucceeded,
            rollbackFatal: rollbackFatal,
            failureReason: reason
        )
    }
}

nonisolated struct CanonicalApplyRuntimeExecutorEntry: Sendable {
    var domain: CanonicalApplyRuntimeDomain
    var dryRunOnly: Bool
    var rollbackAvailable: Bool
    var postconditionAvailable: Bool
    var rootBoundApplyPortAvailable: Bool
    private let executeClosure: @Sendable (CanonicalApplyRuntimeExecutorContext) async -> CanonicalApplyRuntimeExecutorResult

    nonisolated init(
        domain: CanonicalApplyRuntimeDomain,
        dryRunOnly: Bool = false,
        rollbackAvailable: Bool = true,
        postconditionAvailable: Bool = true,
        rootBoundApplyPortAvailable: Bool = true,
        execute: @escaping @Sendable (CanonicalApplyRuntimeExecutorContext) async -> CanonicalApplyRuntimeExecutorResult
    ) {
        self.domain = domain
        self.dryRunOnly = dryRunOnly
        self.rollbackAvailable = rollbackAvailable
        self.postconditionAvailable = postconditionAvailable
        self.rootBoundApplyPortAvailable = rootBoundApplyPortAvailable
        self.executeClosure = execute
    }

    func execute(_ context: CanonicalApplyRuntimeExecutorContext) async -> CanonicalApplyRuntimeExecutorResult {
        await executeClosure(context)
    }

    nonisolated static func unsupportedAudioUpload() -> CanonicalApplyRuntimeExecutorEntry {
        CanonicalApplyRuntimeExecutorEntry(
            domain: .audioUpload,
            dryRunOnly: true,
            rollbackAvailable: false,
            postconditionAvailable: false,
            rootBoundApplyPortAvailable: false
        ) { context in
            CanonicalApplyRuntimeExecutorResult.failure(
                action: context.action,
                domain: .audioUpload,
                reason: CanonicalApplyRuntimeBlocker.audioActionBlocked.rawValue
            )
        }
    }
}

nonisolated struct CanonicalApplyRuntimeExecutorRegistry: Sendable {
    private var entries: [CanonicalApplyRuntimeDomain: CanonicalApplyRuntimeExecutorEntry]

    nonisolated init(entries: [CanonicalApplyRuntimeExecutorEntry] = []) {
        var mapped: [CanonicalApplyRuntimeDomain: CanonicalApplyRuntimeExecutorEntry] = [:]
        for entry in entries {
            mapped[entry.domain] = entry
        }
        mapped[.audioUpload] = mapped[.audioUpload] ?? .unsupportedAudioUpload()
        self.entries = mapped
    }

    nonisolated func entry(for domain: CanonicalApplyRuntimeDomain) -> CanonicalApplyRuntimeExecutorEntry? {
        entries[domain]
    }

    nonisolated func contains(_ domain: CanonicalApplyRuntimeDomain) -> Bool {
        entries[domain] != nil
    }

    nonisolated func adding(_ entry: CanonicalApplyRuntimeExecutorEntry) -> CanonicalApplyRuntimeExecutorRegistry {
        var next = entries
        next[entry.domain] = entry
        return CanonicalApplyRuntimeExecutorRegistry(entries: Array(next.values))
    }
}

nonisolated enum CanonicalApplyRuntimeActionStatus: String, Codable, Equatable, Sendable {
    case notExecuted
    case completed
    case failed
    case blocked
}

nonisolated struct CanonicalApplyRuntimeActionRecord: Codable, Equatable, Identifiable, Sendable {
    var id: String { actionID }
    var actionID: String
    var objectID: String
    var artifactID: String?
    var artifactKind: CanonicalArtifact.Kind?
    var actionKind: CanonicalApplyActionKind
    var domain: CanonicalApplyRuntimeDomain
    var status: CanonicalApplyRuntimeActionStatus
    var duplicateLegacySuppressionAllowed: Bool
    var blocker: CanonicalApplyRuntimeBlocker?
    var detail: String?

    nonisolated init(
        action: CanonicalApplyAction,
        domain: CanonicalApplyRuntimeDomain,
        status: CanonicalApplyRuntimeActionStatus,
        duplicateLegacySuppressionAllowed: Bool = false,
        blocker: CanonicalApplyRuntimeBlocker? = nil,
        detail: String? = nil
    ) {
        self.actionID = CanonicalProductionRedaction.safeIdentifier(action.actionID, fallback: action.kind.rawValue)
        self.objectID = CanonicalProductionRedaction.safeIdentifier(action.target.objectID, fallback: "canonical-object")
        self.artifactID = action.target.artifactID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "artifact") }
        self.artifactKind = action.target.artifactKind
        self.actionKind = action.kind
        self.domain = domain
        self.status = status
        self.duplicateLegacySuppressionAllowed = duplicateLegacySuppressionAllowed
        self.blocker = blocker
        self.detail = CanonicalProductionRedaction.safeDiagnosticText(detail)
    }
}

nonisolated struct CanonicalApplyRuntimeReport: Codable, Equatable, Sendable {
    var mode: CanonicalApplyRuntimeMode
    var gateResult: CanonicalApplyRuntimeGateResult
    var actionRecords: [CanonicalApplyRuntimeActionRecord]
    var legacyFallbackUsed: Bool
    var duplicateLegacySuppressedActionIDs: [String]
    var fatalBlocker: Bool
    var diagnostics: [CanonicalSyncRuntimeDiagnostic]
}

nonisolated struct CanonicalApplyRuntimeResult: Codable, Equatable, Sendable {
    var mode: CanonicalApplyRuntimeMode
    var gateResult: CanonicalApplyRuntimeGateResult
    var report: CanonicalApplyRuntimeReport

    nonisolated var executedActionIDs: [String] {
        report.actionRecords.filter { $0.status == .completed }.map(\.actionID)
    }

    nonisolated var duplicateLegacySuppressedActionIDs: [String] {
        report.duplicateLegacySuppressedActionIDs
    }

    nonisolated var legacyFallbackUsed: Bool {
        report.legacyFallbackUsed
    }
}

nonisolated struct CanonicalApplyRuntimeGate: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(_ context: CanonicalApplyRuntimeOwnerContext) -> CanonicalApplyRuntimeGateResult {
        let configuration = context.configuration
        switch configuration.mode {
        case .disabled:
            return CanonicalApplyRuntimeGateResult(state: .legacyOwner, blockers: [.disabledMode], mode: configuration.mode)
        case .diagnosticsOnly:
            return CanonicalApplyRuntimeGateResult(state: .diagnosticsOnly, blockers: [.diagnosticsOnly], mode: configuration.mode)
        case .noCommit:
            return CanonicalApplyRuntimeGateResult(state: .noCommit, blockers: [.noCommit], mode: configuration.mode)
        case .blocked:
            return CanonicalApplyRuntimeGateResult(state: .blocked, blockers: [.blockedMode], mode: configuration.mode)
        case .testRootApply, .productionRootApplyWithLegacyFallback:
            break
        }

        var blockers: [CanonicalApplyRuntimeGateBlocker] = []
        if context.canonicalPlanAuthorityAllowed == false {
            blockers.append(.canonicalPlanAuthorityUnavailable)
        }
        if context.inventorySnapshotValid == false {
            blockers.append(.inventorySnapshotInvalid)
        }
        if context.localManifest == nil || context.peerManifest == nil {
            blockers.append(.inventorySnapshotInvalid)
        }
        if context.applyPlan.schemaVersion != CanonicalApplyPlan.currentSchemaVersion {
            blockers.append(.applyPlanInvalid)
        }
        if configuration.policy.enabledDomains.isEmpty {
            blockers.append(.enabledDomainsMissing)
        }
        if context.legacyFallbackAvailable == false || configuration.policy.legacyFallbackAvailable == false {
            blockers.append(.legacyFallbackUnavailable)
        }
        if configuration.policy.diagnosticsRedacted == false {
            blockers.append(.diagnosticsNotRedacted)
        }
        if configuration.policy.runtimeSwitchEnabled {
            blockers.append(.runtimeSwitchEnabled)
        }
        if configuration.policy.readPathLegacy == false {
            blockers.append(.readPathNotLegacy)
        }
        if configuration.mode == .productionRootApplyWithLegacyFallback {
            if configuration.policy.releaseDefaultBuild {
                blockers.append(.releaseDefaultProductionApplyBlocked)
            }
            if configuration.policy.debugInternalBuild == false || configuration.policy.ownerApproved == false {
                blockers.append(.debugInternalApprovalMissing)
            }
        }
        if configuration.mode == .testRootApply,
           configuration.policy.allowTestRootApply == false {
            blockers.append(.debugInternalApprovalMissing)
        }

        let enabledDomains = Set(configuration.policy.enabledDomains)
        let actions = context.allActions
        for action in actions {
            let domain = Self.domain(for: action)
            if domain == .audioUpload {
                blockers.append(.audioActionBlocked)
                continue
            }
            if enabledDomains.contains(domain) == false {
                blockers.append(.domainNotEnabled)
            }
            guard let entry = context.registry.entry(for: domain) else {
                blockers.append(.missingExecutor)
                continue
            }
            if entry.dryRunOnly && configuration.mode.executesCommit {
                blockers.append(.dryRunOnlyExecutor)
            }
            if entry.rootBoundApplyPortAvailable == false && configuration.mode.executesCommit {
                blockers.append(.rootBoundApplyPortUnavailable)
            }
            if entry.rollbackAvailable == false {
                blockers.append(.rollbackUnavailable)
            }
            if entry.postconditionAvailable == false {
                blockers.append(.postconditionUnavailable)
            }
            if action.kind == .deferredUnsupported {
                blockers.append(.unsupportedDomain)
            }
        }
        if hasAudioConflict(context.applyPlan) {
            blockers.append(.audioActionBlocked)
        }
        if hasUnresolvedConflictRequiringRecord(context),
           enabledDomains.contains(.tombstoneConflict) == false || configuration.policy.allowConflictRecordAction == false {
            blockers.append(.unresolvedConflict)
        }

        return CanonicalApplyRuntimeGateResult(
            state: blockers.isEmpty ? .allowed : .blocked,
            blockers: blockers,
            mode: configuration.mode
        )
    }

    nonisolated static func domain(for action: CanonicalApplyAction) -> CanonicalApplyRuntimeDomain {
        if action.target.artifactKind == .audio {
            return .audioUpload
        }
        if action.reason == CanonicalApplyRuntimeOwner.recordingExistenceBridgeReason {
            return .recordingExistence
        }
        switch action.kind {
        case .recordingMetadataApply, .recordingMetadataSend:
            return .recordingMetadata
        case .folderMetadataApply, .folderMetadataSend, .studyItemMetadataApply, .studyItemMetadataSend:
            return .libraryMetadata
        case .generatedArtifactDownloadApply, .generatedArtifactNoOp:
            return .generatedArtifacts
        case .libraryTombstoneApply, .libraryTombstoneSend, .objectTombstoneApply, .objectTombstoneSend, .artifactTombstoneApply, .conflictRecord:
            return .tombstoneConflict
        case .deferredUnsupported:
            return action.failureReason == .tombstoneBlocksResurrection ? .tombstoneConflict : .audioUpload
        }
    }

    nonisolated private func hasAudioConflict(_ plan: CanonicalApplyPlan) -> Bool {
        plan.conflicts.contains { conflict in
            conflict.kind == .recordingAudioContentMismatch || conflict.target.artifactKind == .audio
        }
    }

    nonisolated private func hasUnresolvedConflictRequiringRecord(_ context: CanonicalApplyRuntimeOwnerContext) -> Bool {
        let unresolvedApply = context.applyPlan.conflicts.contains { $0.resolutionState == .unresolved && $0.kind != .recordingAudioContentMismatch }
        let unresolvedLibrary = context.libraryPlan?.conflicts.isEmpty == false
        guard unresolvedApply || unresolvedLibrary else {
            return false
        }
        return context.allActions.contains { action in
            action.kind == .conflictRecord && Self.domain(for: action) == .tombstoneConflict
        } == false
    }
}

nonisolated struct CanonicalApplyRuntimeOwner: Sendable {
    nonisolated static let recordingExistenceBridgeReason = "recordingExistenceMetadataOnlyBridge"

    nonisolated init() {}

    func execute(_ context: CanonicalApplyRuntimeOwnerContext) async -> CanonicalApplyRuntimeResult {
        let gateResult = CanonicalApplyRuntimeGate().evaluate(context)
        var diagnostics = baseDiagnostics(context: context, gateResult: gateResult)
        var records: [CanonicalApplyRuntimeActionRecord] = []
        var duplicateSuppressionActionIDs: [String] = []
        var fatalBlocker = false

        guard gateResult.executesCommit,
              let localManifest = context.localManifest,
              let peerManifest = context.peerManifest else {
            diagnostics.append(
                diagnostic(
                    .canonicalApplyRuntimeLegacyFallbackUsed,
                    context: context,
                    detail: Self.nonEmpty(gateResult.blockers.map(\.rawValue).joined(separator: "+")) ?? "legacyOwner"
                )
            )
            diagnostics.append(diagnostic(.canonicalApplyRuntimeReportBuilt, context: context, count: records.count, detail: "legacyFallback"))
            return result(
                context: context,
                gateResult: gateResult,
                records: records,
                legacyFallbackUsed: true,
                duplicateSuppressionActionIDs: [],
                fatalBlocker: false,
                diagnostics: diagnostics
            )
        }

        for action in context.allActions {
            let domain = CanonicalApplyRuntimeGate.domain(for: action)
            guard domain != .audioUpload else {
                diagnostics.append(diagnostic(.canonicalApplyRuntimeAudioActionBlocked, context: context, action: action, detail: "audioUploadUnsupported"))
                records.append(CanonicalApplyRuntimeActionRecord(action: action, domain: domain, status: .blocked, blocker: .audioActionBlocked))
                break
            }
            guard let entry = context.registry.entry(for: domain) else {
                diagnostics.append(diagnostic(.canonicalApplyRuntimeActionFailed, context: context, action: action, detail: "missingExecutor"))
                records.append(CanonicalApplyRuntimeActionRecord(action: action, domain: domain, status: .blocked, blocker: .missingExecutor))
                break
            }

            diagnostics.append(diagnostic(.canonicalApplyRuntimeActionStarted, context: context, action: action, detail: domain.rawValue))
            let executorResult = await entry.execute(
                CanonicalApplyRuntimeExecutorContext(
                    action: action,
                    applyPlan: context.applyPlan,
                    libraryPlan: context.libraryPlan,
                    localManifest: localManifest,
                    peerManifest: peerManifest,
                    syncRunID: context.syncRunID
                )
            )

            if executorResult.rollbackAttempted {
                diagnostics.append(diagnostic(.canonicalApplyRuntimeRollbackStarted, context: context, action: action, detail: domain.rawValue))
                diagnostics.append(
                    diagnostic(
                        executorResult.rollbackSucceeded == true ? .canonicalApplyRuntimeRollbackCompleted : .canonicalApplyRuntimeRollbackFailed,
                        context: context,
                        action: action,
                        detail: executorResult.failureReason ?? executorResult.detail
                    )
                )
            }

            if executorResult.succeeded {
                diagnostics.append(diagnostic(.canonicalApplyRuntimeActionCompleted, context: context, action: action, detail: executorResult.detail ?? "committed"))
                diagnostics.append(diagnostic(.canonicalApplyRuntimeDuplicateLegacySuppressed, context: context, action: action, detail: "eligible"))
                records.append(
                    CanonicalApplyRuntimeActionRecord(
                        action: action,
                        domain: domain,
                        status: .completed,
                        duplicateLegacySuppressionAllowed: true,
                        detail: executorResult.detail
                    )
                )
                duplicateSuppressionActionIDs.append(action.actionID)
                continue
            }

            fatalBlocker = executorResult.rollbackFatal
            diagnostics.append(
                diagnostic(
                    .canonicalApplyRuntimeActionFailed,
                    context: context,
                    action: action,
                    detail: executorResult.failureReason ?? executorResult.detail ?? "failed"
                )
            )
            records.append(
                CanonicalApplyRuntimeActionRecord(
                    action: action,
                    domain: domain,
                    status: .failed,
                    blocker: executorResult.rollbackFatal ? .rollbackFailureFatal : .actionFailed,
                    detail: executorResult.failureReason
                )
            )
            break
        }

        let completedCount = records.filter { $0.status == .completed }.count
        let legacyFallbackUsed = completedCount < context.allActions.count || fatalBlocker
        if legacyFallbackUsed {
            diagnostics.append(diagnostic(.canonicalApplyRuntimeLegacyFallbackUsed, context: context, count: context.allActions.count - completedCount, detail: fatalBlocker ? "fatalBlocker" : "unexecutedActions"))
        }
        diagnostics.append(diagnostic(.canonicalApplyRuntimeReportBuilt, context: context, count: records.count, detail: "canonicalRuntime"))
        return result(
            context: context,
            gateResult: gateResult,
            records: records,
            legacyFallbackUsed: legacyFallbackUsed,
            duplicateSuppressionActionIDs: Array(Set(duplicateSuppressionActionIDs)).sorted(),
            fatalBlocker: fatalBlocker,
            diagnostics: diagnostics
        )
    }

    nonisolated private func baseDiagnostics(
        context: CanonicalApplyRuntimeOwnerContext,
        gateResult: CanonicalApplyRuntimeGateResult
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        [
            diagnostic(.canonicalApplyRuntimeModeEvaluated, context: context, count: context.allActions.count, detail: gateResult.state.rawValue),
            diagnostic(
                gateResult.isAllowed ? .canonicalApplyRuntimeGateAllowed : .canonicalApplyRuntimeGateBlocked,
                context: context,
                count: gateResult.blockers.count,
                detail: Self.nonEmpty(gateResult.blockers.map(\.rawValue).joined(separator: "+")) ?? "none"
            )
        ]
    }

    nonisolated private func diagnostic(
        _ kind: CanonicalSyncRuntimeDiagnosticKind,
        context: CanonicalApplyRuntimeOwnerContext,
        action: CanonicalApplyAction? = nil,
        count: Int? = nil,
        detail: String? = nil
    ) -> CanonicalSyncRuntimeDiagnostic {
        CanonicalSyncRuntimeDiagnostic(
            kind: kind,
            syncRunID: context.syncRunID,
            mode: context.configuration.mode.syncDiagnosticMode,
            objectID: action?.target.objectID,
            actionKind: action?.kind.rawValue,
            count: count,
            detail: detail
        )
    }

    nonisolated private func result(
        context: CanonicalApplyRuntimeOwnerContext,
        gateResult: CanonicalApplyRuntimeGateResult,
        records: [CanonicalApplyRuntimeActionRecord],
        legacyFallbackUsed: Bool,
        duplicateSuppressionActionIDs: [String],
        fatalBlocker: Bool,
        diagnostics: [CanonicalSyncRuntimeDiagnostic]
    ) -> CanonicalApplyRuntimeResult {
        let report = CanonicalApplyRuntimeReport(
            mode: context.configuration.mode,
            gateResult: gateResult,
            actionRecords: records,
            legacyFallbackUsed: legacyFallbackUsed,
            duplicateLegacySuppressedActionIDs: duplicateSuppressionActionIDs,
            fatalBlocker: fatalBlocker,
            diagnostics: diagnostics
        )
        return CanonicalApplyRuntimeResult(
            mode: context.configuration.mode,
            gateResult: gateResult,
            report: report
        )
    }

    nonisolated private static func nonEmpty(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}

nonisolated enum CanonicalApplyRuntimeExecutorAdapters {
    nonisolated static func recordingMetadata(
        _ executor: any CanonicalRecordingMetadataCutoverExecutor,
        dryRunOnly: Bool = false,
        rootBoundApplyPortAvailable: Bool = true
    ) -> CanonicalApplyRuntimeExecutorEntry {
        CanonicalApplyRuntimeExecutorEntry(
            domain: .recordingMetadata,
            dryRunOnly: dryRunOnly,
            rootBoundApplyPortAvailable: rootBoundApplyPortAvailable
        ) { context in
            let action = context.action
            let localObjects = Dictionary(uniqueKeysWithValues: context.localManifest.objects.map { ($0.objectID, $0) })
            let peerObjects = Dictionary(uniqueKeysWithValues: context.peerManifest.objects.map { ($0.objectID, $0) })
            let candidate = CanonicalRecordingMetadataCutoverCandidate(
                action: action,
                localObject: localObjects[action.target.objectID],
                peerObject: peerObjects[action.target.objectID],
                rollbackCheckpointID: "apply-runtime-recording-\(action.target.objectID)"
            )
            guard candidate.cutoverActionKind != nil else {
                return .failure(action: action, domain: .recordingMetadata, reason: CanonicalApplyRuntimeBlocker.unsupportedDomain.rawValue)
            }
            let commit = await executor.commitRecordingMetadata(candidate)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                return .success(action: action, domain: .recordingMetadata, detail: commit.reason)
            }
            let rollback = await executor.rollbackRecordingMetadata(candidate, reason: recordingRollbackReason(commit))
            return .failure(
                action: action,
                domain: .recordingMetadata,
                preconditionVerified: commit.preconditionVerified,
                postconditionVerified: commit.postconditionVerified,
                rollbackAttempted: true,
                rollbackSucceeded: rollback.succeeded,
                rollbackFatal: rollback.fatal || rollback.succeeded == false,
                reason: commit.failureKind?.rawValue ?? commit.reason
            )
        }
    }

    nonisolated static func libraryMetadata(
        _ executor: any CanonicalLibraryMetadataCutoverExecutor,
        dryRunOnly: Bool = false,
        rootBoundApplyPortAvailable: Bool = true
    ) -> CanonicalApplyRuntimeExecutorEntry {
        CanonicalApplyRuntimeExecutorEntry(
            domain: .libraryMetadata,
            dryRunOnly: dryRunOnly,
            rootBoundApplyPortAvailable: rootBoundApplyPortAvailable
        ) { context in
            guard let libraryPlan = context.libraryPlan,
                  let candidate = CanonicalLibraryMetadataCutoverCandidate
                    .candidates(from: libraryPlan, localManifest: context.localManifest, peerManifest: context.peerManifest)
                    .first(where: { $0.action.actionID == context.action.actionID }) else {
                return .failure(action: context.action, domain: .libraryMetadata, reason: CanonicalApplyRuntimeBlocker.missingExecutor.rawValue)
            }
            let commit = await executor.commitLibraryMetadata(candidate)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                return .success(action: context.action, domain: .libraryMetadata, detail: commit.reason)
            }
            let rollback = await executor.rollbackLibraryMetadata(candidate, reason: commit.failureKind ?? .applyFailureBeforeCommit)
            return .failure(
                action: context.action,
                domain: .libraryMetadata,
                preconditionVerified: commit.preconditionVerified,
                postconditionVerified: commit.postconditionVerified,
                rollbackAttempted: true,
                rollbackSucceeded: rollback.succeeded,
                rollbackFatal: rollback.fatal || rollback.succeeded == false,
                reason: commit.failureKind?.rawValue ?? commit.reason
            )
        }
    }

    nonisolated static func generatedArtifacts(
        _ executor: any CanonicalGeneratedArtifactCutoverExecutor,
        dryRunOnly: Bool = false,
        rootBoundApplyPortAvailable: Bool = true
    ) -> CanonicalApplyRuntimeExecutorEntry {
        CanonicalApplyRuntimeExecutorEntry(
            domain: .generatedArtifacts,
            dryRunOnly: dryRunOnly,
            rootBoundApplyPortAvailable: rootBoundApplyPortAvailable
        ) { context in
            guard let candidate = CanonicalGeneratedArtifactCutoverCandidate
                .candidates(from: context.applyPlan, localManifest: context.localManifest, peerManifest: context.peerManifest)
                .first(where: { $0.action.actionID == context.action.actionID }) else {
                return .failure(action: context.action, domain: .generatedArtifacts, reason: CanonicalApplyRuntimeBlocker.missingExecutor.rawValue)
            }
            let commit = await executor.commitGeneratedArtifact(candidate)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                return .success(action: context.action, domain: .generatedArtifacts, detail: commit.reason)
            }
            let rollback = await executor.rollbackGeneratedArtifact(candidate, reason: commit.failureKind ?? .applyFailureBeforeCommit)
            return .failure(
                action: context.action,
                domain: .generatedArtifacts,
                preconditionVerified: commit.preconditionVerified,
                postconditionVerified: commit.postconditionVerified,
                rollbackAttempted: true,
                rollbackSucceeded: rollback.succeeded,
                rollbackFatal: rollback.fatal || rollback.succeeded == false,
                reason: commit.failureKind?.rawValue ?? commit.reason
            )
        }
    }

    nonisolated static func tombstoneConflict(
        _ executor: any CanonicalTombstoneConflictCutoverExecutor,
        dryRunOnly: Bool = false,
        rootBoundApplyPortAvailable: Bool = true
    ) -> CanonicalApplyRuntimeExecutorEntry {
        CanonicalApplyRuntimeExecutorEntry(
            domain: .tombstoneConflict,
            dryRunOnly: dryRunOnly,
            rootBoundApplyPortAvailable: rootBoundApplyPortAvailable
        ) { context in
            guard let candidate = CanonicalTombstoneConflictCandidate
                .candidates(from: context.applyPlan, libraryPlan: context.libraryPlan, localManifest: context.localManifest, peerManifest: context.peerManifest)
                .first(where: { $0.action.actionID == context.action.actionID }) else {
                return .failure(action: context.action, domain: .tombstoneConflict, reason: CanonicalApplyRuntimeBlocker.missingExecutor.rawValue)
            }
            let commit = await executor.commitTombstoneConflict(candidate)
            if commit.committed && commit.preconditionVerified && commit.postconditionVerified {
                return .success(action: context.action, domain: .tombstoneConflict, detail: commit.reason)
            }
            let rollback = await executor.rollbackTombstoneConflict(candidate, reason: commit.failureKind ?? .applyFailureBeforeCommit)
            return .failure(
                action: context.action,
                domain: .tombstoneConflict,
                preconditionVerified: commit.preconditionVerified,
                postconditionVerified: commit.postconditionVerified,
                rollbackAttempted: true,
                rollbackSucceeded: rollback.succeeded,
                rollbackFatal: rollback.fatal || rollback.succeeded == false,
                reason: commit.failureKind?.rawValue ?? commit.reason
            )
        }
    }

    nonisolated private static func recordingRollbackReason(
        _ commit: CanonicalRecordingMetadataProductionCommitResult
    ) -> CanonicalCutoverFailure {
        if commit.failureKind == .preconditionMismatch || commit.preconditionVerified == false {
            return .preconditionMismatch
        }
        if commit.failureKind == .postconditionMismatch || commit.postconditionVerified == false {
            return .postconditionMismatch
        }
        if commit.partialCommit {
            return .applyFailureAfterPartialCommit
        }
        return .applyFailureBeforeCommit
    }
}

nonisolated struct CanonicalApplyExecutor {
    private let conflictResolver: CanonicalConflictResolver

    nonisolated init(conflictResolver: CanonicalConflictResolver = CanonicalConflictResolver()) {
        self.conflictResolver = conflictResolver
    }

    func execute(
        applyPlan: CanonicalApplyPlan,
        libraryPlan: CanonicalLibrarySyncPlan? = nil,
        context: CanonicalApplyRuntimeContext
    ) async -> CanonicalApplyExecutionReport {
        var records: [CanonicalApplyExecutionRecord] = []
        for action in applyPlan.actions + (libraryPlan?.applyActions ?? []) {
            let record: CanonicalApplyExecutionRecord
            do {
                record = try await execute(action: action, context: context)
            } catch {
                record = CanonicalApplyExecutionRecord(
                    actionID: action.actionID,
                    kind: action.kind,
                    target: action.target,
                    status: .failed,
                    contentHashPrefix: nil,
                    byteSize: nil,
                    failure: .hashOrSizeMismatch,
                    detail: String(describing: error)
                )
            }
            records.append(record)
        }
        let conflictReport = conflictResolver.resolve(
            conflicts: applyPlan.conflicts,
            libraryConflicts: libraryPlan?.conflicts ?? []
        )
        return CanonicalApplyExecutionReport(
            records: deduplicated(records),
            conflictReport: conflictReport,
            appliedCount: records.filter { $0.status == .applied || $0.status == .sent }.count,
            failedCount: records.filter { $0.status == .failed }.count
        )
    }

    private func execute(
        action: CanonicalApplyAction,
        context: CanonicalApplyRuntimeContext
    ) async throws -> CanonicalApplyExecutionRecord {
        switch action.kind {
        case .recordingMetadataApply, .folderMetadataApply, .studyItemMetadataApply:
            return try await writeMetadata(action: action, source: context.peerManifest, targetStore: context.localFileStore, root: context.localMetadataRoot, status: .applied)
        case .recordingMetadataSend, .folderMetadataSend, .studyItemMetadataSend:
            return try await writeMetadata(action: action, source: context.localManifest, targetStore: context.peerFileStore, root: context.peerMetadataRoot, status: .sent)
        case .objectTombstoneApply, .libraryTombstoneApply:
            return try await markTombstone(action: action, targetStore: context.localFileStore, root: context.localMetadataRoot, status: .applied)
        case .objectTombstoneSend, .libraryTombstoneSend:
            return try await markTombstone(action: action, targetStore: context.peerFileStore, root: context.peerMetadataRoot, status: .sent)
        case .generatedArtifactDownloadApply:
            return try await downloadGeneratedArtifact(action: action, context: context)
        case .generatedArtifactNoOp:
            return record(action: action, status: .noOp, detail: "generatedArtifactSameContent")
        case .artifactTombstoneApply:
            return try await markTombstone(action: action, targetStore: context.localFileStore, root: context.localGeneratedRoot, status: .deferredUnsupported)
        case .conflictRecord:
            return record(action: action, status: .conflictRecorded, detail: action.conflictID)
        case .deferredUnsupported:
            return record(action: action, status: .deferredUnsupported, detail: action.failureReason?.rawValue)
        }
    }

    private func writeMetadata(
        action: CanonicalApplyAction,
        source manifest: CanonicalManifest,
        targetStore: any CanonicalFileStorePort,
        root: CanonicalRootToken,
        status: CanonicalApplyExecutionStatus
    ) async throws -> CanonicalApplyExecutionRecord {
        let data = try metadataData(for: action, source: manifest)
        let hash = InMemoryCanonicalFileStore.hash(data, policy: .sha256)
        let reference = CanonicalFileReference(
            rootToken: root,
            logicalPathToken: metadataPathToken(for: action),
            artifactID: action.target.artifactID,
            artifactKind: action.target.artifactKind
        )
        let result = try await targetStore.write(
            CanonicalFileWriteIntent(
                reference: reference,
                bytes: data,
                purpose: .metadataBlob,
                expectedContentHash: hash,
                expectedByteSize: Int64(data.count),
                conflictPolicy: .replace,
                metadataBlob: CanonicalMetadataBlob([
                    "action": action.kind.rawValue,
                    "objectID": action.target.objectID,
                    "hashPrefix": hash.map { String($0.value.prefix(12)) } ?? ""
                ])
            )
        )
        return CanonicalApplyExecutionRecord(
            actionID: action.actionID,
            kind: action.kind,
            target: action.target,
            status: status,
            contentHashPrefix: result.contentHash.map { String($0.value.prefix(12)) },
            byteSize: result.byteSize,
            failure: nil,
            detail: result.disposition.rawValue
        )
    }

    private func downloadGeneratedArtifact(
        action: CanonicalApplyAction,
        context: CanonicalApplyRuntimeContext
    ) async throws -> CanonicalApplyExecutionRecord {
        guard let kind = action.target.artifactKind,
              let artifact = artifact(
                objectID: action.target.objectID,
                kind: kind,
                in: context.peerManifest
              ) else {
            throw CanonicalApplyRuntimeError.missingSourceArtifact(action.target.objectID)
        }
        guard let token = artifact.logicalPathToken else {
            throw CanonicalApplyRuntimeError.missingLogicalPathToken(action.target.objectID)
        }
        let peerReference = CanonicalFileReference(
            rootToken: context.peerGeneratedRoot,
            logicalPathToken: token,
            artifactID: artifact.artifactID,
            artifactKind: artifact.kind
        )
        let read = try await context.peerFileStore.read(CanonicalFileReadRequest(reference: peerReference))
        try validate(read: read, against: artifact)
        let localReference = CanonicalFileReference(
            rootToken: context.localGeneratedRoot,
            logicalPathToken: token,
            artifactID: artifact.artifactID,
            artifactKind: artifact.kind
        )
        let write = try await context.localFileStore.write(
            CanonicalFileWriteIntent(
                reference: localReference,
                bytes: read.bytes,
                purpose: .generatedArtifact,
                expectedContentHash: artifact.contentHash,
                expectedByteSize: artifact.byteSize,
                conflictPolicy: .idempotentIfSameContent
            )
        )
        return CanonicalApplyExecutionRecord(
            actionID: action.actionID,
            kind: action.kind,
            target: action.target,
            status: .applied,
            contentHashPrefix: write.contentHash.map { String($0.value.prefix(12)) },
            byteSize: write.byteSize,
            failure: nil,
            detail: write.disposition.rawValue
        )
    }

    private func markTombstone(
        action: CanonicalApplyAction,
        targetStore: any CanonicalFileStorePort,
        root: CanonicalRootToken,
        status: CanonicalApplyExecutionStatus
    ) async throws -> CanonicalApplyExecutionRecord {
        let reference = CanonicalFileReference(
            rootToken: root,
            logicalPathToken: action.target.artifactKind == nil ? metadataPathToken(for: action) : artifactTombstoneToken(for: action),
            artifactID: action.target.artifactID,
            artifactKind: action.target.artifactKind
        )
        let result = try await targetStore.markTombstone(reference, reason: action.reason)
        return CanonicalApplyExecutionRecord(
            actionID: action.actionID,
            kind: action.kind,
            target: action.target,
            status: status,
            contentHashPrefix: result.contentHash.map { String($0.value.prefix(12)) },
            byteSize: result.byteSize,
            failure: action.failureReason,
            detail: "noPhysicalDelete"
        )
    }

    private func metadataData(for action: CanonicalApplyAction, source manifest: CanonicalManifest) throws -> Data {
        if let object = manifest.objects.first(where: { $0.objectID == action.target.objectID }) {
            return try CanonicalTransportJSON.encode(object.metadata)
        }
        if let libraryObject = manifest.libraryObjects.first(where: { $0.objectID.rawValue == action.target.objectID }) {
            return try CanonicalTransportJSON.encode(libraryObject)
        }
        throw CanonicalApplyRuntimeError.missingSourceObject(action.target.objectID)
    }

    private func validate(read: CanonicalFileReadResult, against artifact: CanonicalArtifact) throws {
        if let expectedSize = artifact.byteSize, read.byteSize != expectedSize {
            throw CanonicalApplyRuntimeError.hashOrSizeMismatch(artifact.artifactID)
        }
        if let expectedHash = artifact.contentHash,
           let actualHash = read.contentHash,
           expectedHash != actualHash {
            throw CanonicalApplyRuntimeError.hashOrSizeMismatch(artifact.artifactID)
        }
    }

    private func artifact(
        objectID: String,
        kind: CanonicalArtifact.Kind,
        in manifest: CanonicalManifest
    ) -> CanonicalArtifact? {
        manifest.objects.first { $0.objectID == objectID }?.artifacts.first { $0.kind == kind }
    }

    private func record(
        action: CanonicalApplyAction,
        status: CanonicalApplyExecutionStatus,
        detail: String?
    ) -> CanonicalApplyExecutionRecord {
        CanonicalApplyExecutionRecord(
            actionID: action.actionID,
            kind: action.kind,
            target: action.target,
            status: status,
            contentHashPrefix: nil,
            byteSize: nil,
            failure: action.failureReason,
            detail: detail
        )
    }

    private func metadataPathToken(for action: CanonicalApplyAction) -> String {
        let kind = action.kind.rawValue
        return "metadata/\(safePathComponent(kind))/\(safePathComponent(action.target.objectID)).json"
    }

    private func artifactTombstoneToken(for action: CanonicalApplyAction) -> String {
        let kind = action.target.artifactKind?.rawValue ?? "artifact"
        return "tombstones/\(safePathComponent(action.target.objectID))/\(safePathComponent(kind)).marker"
    }

    private func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let pieces = value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "-"
        }
        let component = pieces.joined().trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if component.isEmpty {
            return String(CanonicalHash.sha256String(value).value.prefix(12))
        }
        return component
    }

    private func deduplicated(_ records: [CanonicalApplyExecutionRecord]) -> [CanonicalApplyExecutionRecord] {
        var seen = Set<String>()
        return records.filter { seen.insert($0.actionID).inserted }
    }
}
