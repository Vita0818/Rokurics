//
//  CanonicalLibraryMetadataObservation.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/5.
//

import Foundation

nonisolated enum CanonicalLibraryMetadataObservationEventKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case windowStarted
    case windowCompleted
    case canonicalCommitAttempted
    case canonicalCommitSucceeded
    case canonicalCommitFailed
    case rollbackAttempted
    case rollbackSucceeded
    case rollbackFailed
    case rollbackFatal
    case legacyFallbackUsed
    case duplicateLegacySuppressed
    case unresolvedConflictObserved
    case resourceMoveAttempted
    case canonicalReadCandidateBuilt
    case canonicalReadServed
    case legacyReadFallbackUsed
    case readSideParallelEquivalent
    case readSideParallelDivergent
    case readSideUnsupportedObject
    case readSidePathLeakRisk
    case unsafeSideEffectObserved
    case syncOrUploadTriggered
    case uiMutated
    case contentWritten
    case tombstoneDeleteAttempted
}

nonisolated struct CanonicalLibraryMetadataObservationEvent: Codable, Equatable, Sendable {
    var kind: CanonicalLibraryMetadataObservationEventKind
    var count: Int
    var syncRunID: String?
    var trigger: CanonicalSyncPlanTrigger
    var nodeRole: CanonicalProductionExecutionDomainRole
    var reason: String?

    nonisolated init(
        kind: CanonicalLibraryMetadataObservationEventKind,
        count: Int = 1,
        syncRunID: String? = nil,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        reason: String? = nil
    ) {
        self.kind = kind
        self.count = max(0, count)
        self.syncRunID = syncRunID.map { CanonicalProductionRedaction.safeIdentifier($0, fallback: "sync-run") }
        self.trigger = trigger
        self.nodeRole = nodeRole
        self.reason = CanonicalProductionRedaction.safeDiagnosticText(reason)
    }
}

nonisolated struct CanonicalLibraryMetadataObservationPolicy: Codable, Equatable, Sendable {
    var enabled: Bool
    var explicitInternalTestConfiguration: Bool
    var minimumWriteCanonicalCommitCount: Int
    var minimumReadCanonicalEvidenceCount: Int
    var minimumTotalEventCount: Int
    var requireLegacyFallbackAvailable: Bool
    var legacyFallbackAvailable: Bool
    var requireOnlyLibraryMetadataActivePilot: Bool
    var allowParallelReadOnlyEvidence: Bool
    var manualAuditRequired: Bool
    var recordDiagnostics: Bool
    var maxDiagnosticsEvents: Int

    nonisolated init(
        enabled: Bool = false,
        explicitInternalTestConfiguration: Bool = false,
        minimumWriteCanonicalCommitCount: Int = 1,
        minimumReadCanonicalEvidenceCount: Int = 1,
        minimumTotalEventCount: Int = 2,
        requireLegacyFallbackAvailable: Bool = true,
        legacyFallbackAvailable: Bool = true,
        requireOnlyLibraryMetadataActivePilot: Bool = true,
        allowParallelReadOnlyEvidence: Bool = true,
        manualAuditRequired: Bool = true,
        recordDiagnostics: Bool = true,
        maxDiagnosticsEvents: Int = 16
    ) {
        self.enabled = enabled
        self.explicitInternalTestConfiguration = explicitInternalTestConfiguration
        self.minimumWriteCanonicalCommitCount = max(0, minimumWriteCanonicalCommitCount)
        self.minimumReadCanonicalEvidenceCount = max(0, minimumReadCanonicalEvidenceCount)
        self.minimumTotalEventCount = max(0, minimumTotalEventCount)
        self.requireLegacyFallbackAvailable = requireLegacyFallbackAvailable
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.requireOnlyLibraryMetadataActivePilot = requireOnlyLibraryMetadataActivePilot
        self.allowParallelReadOnlyEvidence = allowParallelReadOnlyEvidence
        self.manualAuditRequired = manualAuditRequired
        self.recordDiagnostics = recordDiagnostics
        self.maxDiagnosticsEvents = max(0, maxDiagnosticsEvents)
    }

    nonisolated static let disabled = CanonicalLibraryMetadataObservationPolicy()

    nonisolated static func explicitInternalTest(
        minimumWriteCanonicalCommitCount: Int = 1,
        minimumReadCanonicalEvidenceCount: Int = 1,
        minimumTotalEventCount: Int = 2,
        legacyFallbackAvailable: Bool = true
    ) -> CanonicalLibraryMetadataObservationPolicy {
        CanonicalLibraryMetadataObservationPolicy(
            enabled: true,
            explicitInternalTestConfiguration: true,
            minimumWriteCanonicalCommitCount: minimumWriteCanonicalCommitCount,
            minimumReadCanonicalEvidenceCount: minimumReadCanonicalEvidenceCount,
            minimumTotalEventCount: minimumTotalEventCount,
            legacyFallbackAvailable: legacyFallbackAvailable,
            manualAuditRequired: true
        )
    }
}

nonisolated struct CanonicalLibraryMetadataObservationWindow: Codable, Equatable, Sendable {
    var observationWindowID: String
    var domain: CanonicalMigrationDomain
    var enabled: Bool
    var explicitInternalTestConfiguration: Bool
    var runtimeSwitchEnabled: Bool
    var defaultCanonicalReadEnabled: Bool
    var defaultCanonicalWriteEnabled: Bool
    var activePilotDomain: CanonicalMigrationDomain?
    var otherDomainsStaticOnly: Bool
    var writeCanonicalCommitAttemptCount: Int
    var writeCanonicalCommitSucceededCount: Int
    var writeCanonicalCommitFailedCount: Int
    var rollbackAttemptCount: Int
    var rollbackSucceededCount: Int
    var rollbackFailedCount: Int
    var rollbackFatalCount: Int
    var legacyFallbackUsedCount: Int
    var duplicateLegacySuppressedCount: Int
    var unresolvedConflictCount: Int
    var resourceMoveAttemptedCount: Int
    var canonicalReadCandidateBuiltCount: Int
    var canonicalReadServedCount: Int
    var legacyReadFallbackCount: Int
    var readSideParallelEquivalentCount: Int
    var readSideParallelDivergentCount: Int
    var readSideDivergenceCount: Int
    var readSideUnsupportedObjectCount: Int
    var readSidePathLeakRiskCount: Int
    var unsafeSideEffectCount: Int
    var syncOrUploadTriggeredCount: Int
    var uiMutatedCount: Int
    var contentWrittenCount: Int
    var tombstoneDeleteAttemptedCount: Int
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var diagnosticsSummary: String

    nonisolated init(
        observationWindowID: String,
        policy: CanonicalLibraryMetadataObservationPolicy = .disabled,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813()
    ) {
        let matrixReport = matrix.validate()
        self.observationWindowID = CanonicalProductionRedaction.safeIdentifier(
            observationWindowID,
            fallback: "library-metadata-observation"
        )
        self.domain = .libraryMetadata
        self.enabled = policy.enabled
        self.explicitInternalTestConfiguration = policy.explicitInternalTestConfiguration
        self.runtimeSwitchEnabled = matrix.policies.contains(where: \.runtimeSwitchEnabled)
        self.defaultCanonicalReadEnabled = matrix.policies.contains(where: \.defaultCutoverEnabled)
        self.defaultCanonicalWriteEnabled = matrix.policies.contains(where: \.releaseDefaultEnabledCutover)
        self.activePilotDomain = matrixReport.activePilotDomain
        self.otherDomainsStaticOnly = matrix.policies
            .filter { $0.domain != .libraryMetadata }
            .allSatisfy { $0.staticOnly && !$0.activePilot && !$0.hasActiveCanaryOrCutover }
        self.writeCanonicalCommitAttemptCount = 0
        self.writeCanonicalCommitSucceededCount = 0
        self.writeCanonicalCommitFailedCount = 0
        self.rollbackAttemptCount = 0
        self.rollbackSucceededCount = 0
        self.rollbackFailedCount = 0
        self.rollbackFatalCount = 0
        self.legacyFallbackUsedCount = 0
        self.duplicateLegacySuppressedCount = 0
        self.unresolvedConflictCount = 0
        self.resourceMoveAttemptedCount = 0
        self.canonicalReadCandidateBuiltCount = 0
        self.canonicalReadServedCount = 0
        self.legacyReadFallbackCount = 0
        self.readSideParallelEquivalentCount = 0
        self.readSideParallelDivergentCount = 0
        self.readSideDivergenceCount = 0
        self.readSideUnsupportedObjectCount = 0
        self.readSidePathLeakRiskCount = 0
        self.unsafeSideEffectCount = 0
        self.syncOrUploadTriggeredCount = 0
        self.uiMutatedCount = 0
        self.contentWrittenCount = 0
        self.tombstoneDeleteAttemptedCount = 0
        self.diagnostics = []
        self.diagnosticsSummary = "v8.20,domain=libraryMetadata,enabled=\(policy.enabled),explicitInternalTest=\(policy.explicitInternalTestConfiguration)"
    }

    nonisolated static func disabled(
        observationWindowID: String = "libraryMetadataObservationDisabled",
        matrix: CanonicalMigrationDomainMatrix = .defaultV813()
    ) -> CanonicalLibraryMetadataObservationWindow {
        CanonicalLibraryMetadataObservationWindow(
            observationWindowID: observationWindowID,
            policy: .disabled,
            matrix: matrix
        )
    }

    nonisolated var totalEventCount: Int {
        writeCanonicalCommitAttemptCount
            + writeCanonicalCommitSucceededCount
            + writeCanonicalCommitFailedCount
            + rollbackAttemptCount
            + rollbackSucceededCount
            + rollbackFailedCount
            + rollbackFatalCount
            + legacyFallbackUsedCount
            + duplicateLegacySuppressedCount
            + unresolvedConflictCount
            + resourceMoveAttemptedCount
            + canonicalReadCandidateBuiltCount
            + canonicalReadServedCount
            + legacyReadFallbackCount
            + readSideParallelEquivalentCount
            + readSideParallelDivergentCount
            + readSideUnsupportedObjectCount
            + readSidePathLeakRiskCount
            + unsafeSideEffectCount
            + syncOrUploadTriggeredCount
            + uiMutatedCount
            + contentWrittenCount
            + tombstoneDeleteAttemptedCount
    }

    nonisolated var readEvidenceCount: Int {
        canonicalReadServedCount + canonicalReadCandidateBuiltCount + readSideParallelEquivalentCount
    }

    nonisolated var noUnsafeSideEffects: Bool {
        unsafeSideEffectCount == 0
            && resourceMoveAttemptedCount == 0
            && syncOrUploadTriggeredCount == 0
            && contentWrittenCount == 0
            && tombstoneDeleteAttemptedCount == 0
            && uiMutatedCount == 0
    }

    nonisolated func recording(_ event: CanonicalLibraryMetadataObservationEvent) -> CanonicalLibraryMetadataObservationWindow {
        guard enabled, event.count > 0 else {
            return self
        }
        var copy = self
        copy.apply(event)
        copy.refreshDiagnosticsSummary()
        return copy
    }

    nonisolated func recordingWriteSideResult(
        _ result: CanonicalLibraryMetadataCutoverResult,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        syncRunID: String? = nil
    ) -> CanonicalLibraryMetadataObservationWindow {
        guard enabled else {
            return self
        }
        var copy = self
        let attemptedCount = max(result.canaryAttemptedCount, result.commits.count)
        copy.apply(.init(kind: .canonicalCommitAttempted, count: attemptedCount, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .canonicalCommitSucceeded, count: result.commits.filter(\.committed).count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .canonicalCommitFailed, count: result.commits.filter { !$0.committed }.count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .rollbackAttempted, count: result.rollbackResults.count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .rollbackSucceeded, count: result.rollbackResults.filter(\.succeeded).count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .rollbackFailed, count: result.rollbackResults.filter { !$0.succeeded }.count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .rollbackFatal, count: result.rollbackResults.filter(\.fatal).count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .legacyFallbackUsed, count: result.legacyFallbackUsed ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .duplicateLegacySuppressed, count: result.duplicateLegacySuppressedActionIDs.count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .resourceMoveAttempted, count: result.diagnostics.filter { $0.kind == .canonicalLibraryMetadataResourceMoveBlocked }.count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .unsafeSideEffectObserved, count: result.commits.flatMap(\.sideEffects).filter(\.isUnsafeForLibraryMetadataObservation).count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .tombstoneDeleteAttempted, count: result.commits.filter { $0.actionKind == .tombstoneMarkerUnsupportedForThisRound }.count, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.appendDiagnostic(
            .canonicalLibraryMetadataObservationWriteSideRecorded,
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID,
            result: "recorded",
            reason: "attempted=\(attemptedCount),succeeded=\(result.commits.filter(\.committed).count),rollbackFailures=\(result.rollbackResults.filter { !$0.succeeded }.count)"
        )
        copy.refreshDiagnosticsSummary()
        return copy
    }

    nonisolated func recordingReadSourceResult(
        _ result: CanonicalLibraryMetadataReadSourceResult,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        syncRunID: String? = nil
    ) -> CanonicalLibraryMetadataObservationWindow {
        guard enabled else {
            return self
        }
        var copy = self
        copy.apply(.init(kind: .canonicalReadCandidateBuilt, count: result.canonicalCandidateBuilt ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .canonicalReadServed, count: result.canonicalReadServed ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .legacyReadFallbackUsed, count: result.fallbackCount, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: result.diffReport?.equivalent == false ? .readSideParallelDivergent : .readSideParallelEquivalent, count: result.diffReport == nil ? 0 : 1, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .readSideUnsupportedObject, count: result.diffReport?.unsupportedObjectCount ?? 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .readSidePathLeakRisk, count: result.diffReport?.pathLeakRiskCount ?? 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .syncOrUploadTriggered, count: result.syncOrUploadTriggered ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .resourceMoveAttempted, count: result.resourceMoved ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .contentWritten, count: result.contentWritten ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .uiMutated, count: result.uiMutated ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.appendDiagnostic(
            .canonicalLibraryMetadataObservationReadSideRecorded,
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID,
            result: result.canonicalReadServed ? "canonicalReadServed" : "reportOnly",
            reason: "candidateBuilt=\(result.canonicalCandidateBuilt),fallback=\(result.fallbackCount),divergence=\(result.diffReport?.divergenceCount ?? 0)"
        )
        copy.refreshDiagnosticsSummary()
        return copy
    }

    nonisolated func recordingReadSideCutoverResult(
        _ result: CanonicalLibraryMetadataReadSideCutoverResult,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        syncRunID: String? = nil
    ) -> CanonicalLibraryMetadataObservationWindow {
        guard enabled else {
            return self
        }
        var copy = self
        if let report = result.diffReport {
            copy.apply(.init(kind: report.equivalent ? .readSideParallelEquivalent : .readSideParallelDivergent, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
            copy.apply(.init(kind: .readSideUnsupportedObject, count: report.unsupportedObjectCount, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
            copy.apply(.init(kind: .readSidePathLeakRisk, count: report.pathLeakRiskCount, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        }
        copy.apply(.init(kind: .legacyReadFallbackUsed, count: result.legacyReadFallbackAvailable ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .syncOrUploadTriggered, count: result.syncOrUploadTriggered ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.apply(.init(kind: .uiMutated, count: result.uiMutated ? 1 : 0, syncRunID: syncRunID, trigger: trigger, nodeRole: nodeRole))
        copy.appendDiagnostic(
            .canonicalLibraryMetadataObservationReadSideRecorded,
            trigger: trigger,
            nodeRole: nodeRole,
            syncRunID: syncRunID,
            result: result.candidate.ready ? "readCandidateReady" : "readCandidateBlocked",
            reason: result.candidate.diagnosticsSummary
        )
        copy.refreshDiagnosticsSummary()
        return copy
    }

    nonisolated private mutating func apply(_ event: CanonicalLibraryMetadataObservationEvent) {
        switch event.kind {
        case .windowStarted:
            break
        case .windowCompleted:
            break
        case .canonicalCommitAttempted:
            writeCanonicalCommitAttemptCount += event.count
        case .canonicalCommitSucceeded:
            writeCanonicalCommitSucceededCount += event.count
        case .canonicalCommitFailed:
            writeCanonicalCommitFailedCount += event.count
        case .rollbackAttempted:
            rollbackAttemptCount += event.count
        case .rollbackSucceeded:
            rollbackSucceededCount += event.count
        case .rollbackFailed:
            rollbackFailedCount += event.count
        case .rollbackFatal:
            rollbackFatalCount += event.count
        case .legacyFallbackUsed:
            legacyFallbackUsedCount += event.count
        case .duplicateLegacySuppressed:
            duplicateLegacySuppressedCount += event.count
        case .unresolvedConflictObserved:
            unresolvedConflictCount += event.count
        case .resourceMoveAttempted:
            resourceMoveAttemptedCount += event.count
        case .canonicalReadCandidateBuilt:
            canonicalReadCandidateBuiltCount += event.count
        case .canonicalReadServed:
            canonicalReadServedCount += event.count
        case .legacyReadFallbackUsed:
            legacyReadFallbackCount += event.count
        case .readSideParallelEquivalent:
            readSideParallelEquivalentCount += event.count
        case .readSideParallelDivergent:
            readSideParallelDivergentCount += event.count
            readSideDivergenceCount += event.count
        case .readSideUnsupportedObject:
            readSideUnsupportedObjectCount += event.count
        case .readSidePathLeakRisk:
            readSidePathLeakRiskCount += event.count
        case .unsafeSideEffectObserved:
            unsafeSideEffectCount += event.count
        case .syncOrUploadTriggered:
            syncOrUploadTriggeredCount += event.count
        case .uiMutated:
            uiMutatedCount += event.count
        case .contentWritten:
            contentWrittenCount += event.count
        case .tombstoneDeleteAttempted:
            tombstoneDeleteAttemptedCount += event.count
        }
    }

    nonisolated private mutating func appendDiagnostic(
        _ kind: CanonicalLibraryMetadataCutoverDiagnosticKind,
        trigger: CanonicalSyncPlanTrigger,
        nodeRole: CanonicalProductionExecutionDomainRole,
        syncRunID: String?,
        result: String,
        reason: String
    ) {
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: kind,
                syncRunID: syncRunID,
                trigger: trigger,
                nodeRole: nodeRole,
                domain: .folderMetadata,
                result: result,
                reason: reason
            )
        )
    }

    nonisolated private mutating func refreshDiagnosticsSummary() {
        diagnosticsSummary = [
            "v8.20",
            "domain=libraryMetadata",
            "enabled=\(enabled)",
            "explicitInternalTest=\(explicitInternalTestConfiguration)",
            "writeAttempts=\(writeCanonicalCommitAttemptCount)",
            "writeSucceeded=\(writeCanonicalCommitSucceededCount)",
            "readEvidence=\(readEvidenceCount)",
            "divergence=\(readSideDivergenceCount)",
            "rollbackFailures=\(rollbackFailedCount)",
            "unsafeSideEffects=\(unsafeSideEffectCount)",
            "fallback=\(legacyFallbackUsedCount + legacyReadFallbackCount)",
            "runtimeSwitch=\(runtimeSwitchEnabled)",
            "defaultRead=\(defaultCanonicalReadEnabled)",
            "defaultWrite=\(defaultCanonicalWriteEnabled)"
        ].joined(separator: ",")
    }
}

nonisolated enum CanonicalLibraryMetadataObservationFailure: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case missingExplicitInternalTestConfiguration
    case nonLibraryMetadataActivePilot
    case otherActiveDomain
    case otherDomainsNotStaticOnly
    case writeSideEvidenceMissing
    case readSideEvidenceMissing
    case observationWindowIncomplete
    case fallbackMissing
    case divergencePresent
    case rollbackFailure
    case unsupportedObject
    case pathLeakRisk
    case unsafeSideEffect
    case runtimeSwitchEnabled
    case defaultCutoverEnabled
}

nonisolated enum CanonicalLibraryMetadataObservationGateState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case incomplete
    case completeButRetirementBlocked
    case completeReadyForRetirementCandidate
    case blockedByDivergence
    case blockedByRollbackFailure
    case blockedByUnsupportedObject
    case blockedByFallbackMissing
    case blockedByOtherActiveDomain
    case blockedByUnsafeSideEffect
}

nonisolated struct CanonicalLibraryMetadataObservationGateResult: Codable, Equatable, Sendable {
    var state: CanonicalLibraryMetadataObservationGateState
    var complete: Bool
    var retirementCandidateReady: Bool
    var blockers: [CanonicalLibraryMetadataObservationFailure]
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var diagnosticsSummary: String
}

nonisolated enum CanonicalLibraryMetadataObservationGate {
    nonisolated static func evaluate(
        window: CanonicalLibraryMetadataObservationWindow,
        policy: CanonicalLibraryMetadataObservationPolicy,
        matrix: CanonicalMigrationDomainMatrix = .defaultV813(),
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        syncRunID: String? = nil
    ) -> CanonicalLibraryMetadataObservationGateResult {
        var blockers: [CanonicalLibraryMetadataObservationFailure] = []
        let matrixReport = matrix.validate()

        if !policy.enabled || !window.enabled {
            blockers.append(.disabled)
        }
        if !policy.explicitInternalTestConfiguration || !window.explicitInternalTestConfiguration {
            blockers.append(.missingExplicitInternalTestConfiguration)
        }
        if policy.requireOnlyLibraryMetadataActivePilot {
            if matrixReport.activePilotDomain != .libraryMetadata {
                blockers.append(.nonLibraryMetadataActivePilot)
            }
            if matrixReport.blockers.contains(.multipleActivePilots) {
                blockers.append(.otherActiveDomain)
            }
        }
        if !window.otherDomainsStaticOnly {
            blockers.append(.otherDomainsNotStaticOnly)
        }
        if window.runtimeSwitchEnabled {
            blockers.append(.runtimeSwitchEnabled)
        }
        if window.defaultCanonicalReadEnabled || window.defaultCanonicalWriteEnabled {
            blockers.append(.defaultCutoverEnabled)
        }
        if window.writeCanonicalCommitSucceededCount < policy.minimumWriteCanonicalCommitCount {
            blockers.append(.writeSideEvidenceMissing)
        }
        if window.readEvidenceCount < policy.minimumReadCanonicalEvidenceCount {
            blockers.append(.readSideEvidenceMissing)
        }
        if window.totalEventCount < policy.minimumTotalEventCount {
            blockers.append(.observationWindowIncomplete)
        }
        if policy.requireLegacyFallbackAvailable, !policy.legacyFallbackAvailable {
            blockers.append(.fallbackMissing)
        }
        if window.legacyFallbackUsedCount + window.legacyReadFallbackCount == 0, policy.requireLegacyFallbackAvailable {
            blockers.append(.fallbackMissing)
        }
        if window.readSideDivergenceCount > 0 {
            blockers.append(.divergencePresent)
        }
        if window.rollbackFailedCount > 0 || window.rollbackFatalCount > 0 {
            blockers.append(.rollbackFailure)
        }
        if window.readSideUnsupportedObjectCount > 0 {
            blockers.append(.unsupportedObject)
        }
        if window.readSidePathLeakRiskCount > 0 {
            blockers.append(.pathLeakRisk)
        }
        if !window.noUnsafeSideEffects {
            blockers.append(.unsafeSideEffect)
        }

        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let complete = uniqueBlockers.isEmpty
        let state: CanonicalLibraryMetadataObservationGateState
        if uniqueBlockers.contains(.unsafeSideEffect) || uniqueBlockers.contains(.pathLeakRisk) || uniqueBlockers.contains(.runtimeSwitchEnabled) || uniqueBlockers.contains(.defaultCutoverEnabled) {
            state = .blockedByUnsafeSideEffect
        } else if uniqueBlockers.contains(.otherActiveDomain) || uniqueBlockers.contains(.nonLibraryMetadataActivePilot) || uniqueBlockers.contains(.otherDomainsNotStaticOnly) {
            state = .blockedByOtherActiveDomain
        } else if uniqueBlockers.contains(.rollbackFailure) {
            state = .blockedByRollbackFailure
        } else if uniqueBlockers.contains(.divergencePresent) {
            state = .blockedByDivergence
        } else if uniqueBlockers.contains(.unsupportedObject) {
            state = .blockedByUnsupportedObject
        } else if uniqueBlockers.contains(.fallbackMissing) {
            state = .blockedByFallbackMissing
        } else if uniqueBlockers.isEmpty {
            state = .completeReadyForRetirementCandidate
        } else if uniqueBlockers.contains(.writeSideEvidenceMissing) || uniqueBlockers.contains(.readSideEvidenceMissing) || uniqueBlockers.contains(.observationWindowIncomplete) || uniqueBlockers.contains(.disabled) || uniqueBlockers.contains(.missingExplicitInternalTestConfiguration) {
            state = .incomplete
        } else {
            state = .completeButRetirementBlocked
        }

        let evaluated = CanonicalLibraryMetadataCutoverDiagnostic(
            kind: .canonicalLibraryMetadataObservationGateEvaluated,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: state.rawValue,
            reason: "reportOnly=true"
        )
        let outcome = CanonicalLibraryMetadataCutoverDiagnostic(
            kind: complete ? .canonicalLibraryMetadataObservationGateReady : .canonicalLibraryMetadataObservationGateBlocked,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: complete ? "ready" : "blocked",
            reason: uniqueBlockers.map(\.rawValue).joined(separator: "+")
        )
        let summary = [
            "v8.20",
            "observationGate=\(state.rawValue)",
            "complete=\(complete)",
            "candidateReady=\(complete)",
            "blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+"))",
            "reportOnly=true"
        ].joined(separator: ",")
        return CanonicalLibraryMetadataObservationGateResult(
            state: state,
            complete: complete,
            retirementCandidateReady: complete,
            blockers: uniqueBlockers,
            diagnostics: [evaluated, outcome],
            diagnosticsSummary: summary
        )
    }
}

nonisolated enum CanonicalLibraryMetadataRetirementCandidateGateStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case ready
    case blocked
}

nonisolated struct CanonicalLibraryMetadataRetirementCandidateReport: Codable, Equatable, Sendable {
    var status: CanonicalLibraryMetadataRetirementCandidateGateStatus
    var retirementCandidateReady: Bool
    var retirementExecutionPerformed: Bool
    var legacyDeleted: Bool
    var legacyDisabled: Bool
    var reportOnly: Bool
    var manualAuditRequired: Bool
    var blockers: [CanonicalLibraryMetadataRetirementBlocker]
    var observationGate: CanonicalLibraryMetadataObservationGateResult
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var diagnosticsSummary: String
}

nonisolated enum CanonicalLibraryMetadataRetirementCandidateGate {
    nonisolated static func evaluate(
        observationGate: CanonicalLibraryMetadataObservationGateResult,
        policy: CanonicalLibraryMetadataObservationPolicy,
        trigger: CanonicalSyncPlanTrigger = .periodic,
        nodeRole: CanonicalProductionExecutionDomainRole = .testHarness,
        syncRunID: String? = nil
    ) -> CanonicalLibraryMetadataRetirementCandidateReport {
        var blockers: [CanonicalLibraryMetadataRetirementBlocker] = []
        if !observationGate.complete || !observationGate.retirementCandidateReady {
            blockers.append(.observationWindowIncomplete)
        }
        if !policy.manualAuditRequired {
            blockers.append(.manualAuditRequired)
        }
        if observationGate.blockers.contains(.fallbackMissing) {
            blockers.append(.fallbackMissing)
        }
        if observationGate.blockers.contains(.divergencePresent) {
            blockers.append(.divergencePresent)
        }
        if observationGate.blockers.contains(.unsupportedObject) {
            blockers.append(.unsupportedObject)
        }
        if observationGate.blockers.contains(.rollbackFailure) {
            blockers.append(.rollbackFatal)
        }
        if observationGate.blockers.contains(.otherActiveDomain) || observationGate.blockers.contains(.otherDomainsNotStaticOnly) {
            blockers.append(.otherDomainsAffected)
        }
        if observationGate.blockers.contains(.unsafeSideEffect) {
            blockers.append(.unsafeSideEffect)
        }
        if observationGate.blockers.contains(.pathLeakRisk) {
            blockers.append(.pathLeakRisk)
        }
        if observationGate.blockers.contains(.runtimeSwitchEnabled) {
            blockers.append(.runtimeSwitchEnabled)
        }
        if observationGate.blockers.contains(.defaultCutoverEnabled) {
            blockers.append(.defaultReadOrWriteCutoverEnabled)
        }

        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        let ready = uniqueBlockers.isEmpty
        let evaluated = CanonicalLibraryMetadataCutoverDiagnostic(
            kind: .canonicalLibraryMetadataRetirementCandidateGateEvaluated,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: ready ? "ready" : "blocked",
            reason: "reportOnly=true,manualAuditRequired=\(policy.manualAuditRequired)"
        )
        let outcome = CanonicalLibraryMetadataCutoverDiagnostic(
            kind: ready ? .canonicalLibraryMetadataRetirementCandidateReady : .canonicalLibraryMetadataRetirementCandidateGateBlocked,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeRole: nodeRole,
            result: ready ? "candidate" : "blocked",
            reason: uniqueBlockers.map(\.rawValue).joined(separator: "+")
        )
        let summary = [
            "v8.20",
            "retirementCandidateReady=\(ready)",
            "retirementExecutionPerformed=false",
            "legacyDeleted=false",
            "legacyDisabled=false",
            "manualAuditRequired=\(policy.manualAuditRequired)",
            "reportOnly=true",
            "blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+"))"
        ].joined(separator: ",")
        return CanonicalLibraryMetadataRetirementCandidateReport(
            status: ready ? .ready : .blocked,
            retirementCandidateReady: ready,
            retirementExecutionPerformed: false,
            legacyDeleted: false,
            legacyDisabled: false,
            reportOnly: true,
            manualAuditRequired: policy.manualAuditRequired,
            blockers: uniqueBlockers,
            observationGate: observationGate,
            diagnostics: [evaluated, outcome],
            diagnosticsSummary: summary
        )
    }
}

nonisolated struct CanonicalLibraryMetadataRollbackDrillSummary: Codable, Equatable, Sendable {
    var attemptedCount: Int
    var succeededCount: Int
    var failedCount: Int
    var fatalCount: Int
    var clean: Bool
    var diagnosticsSummary: String

    nonisolated init(window: CanonicalLibraryMetadataObservationWindow) {
        self.attemptedCount = window.rollbackAttemptCount
        self.succeededCount = window.rollbackSucceededCount
        self.failedCount = window.rollbackFailedCount
        self.fatalCount = window.rollbackFatalCount
        self.clean = window.rollbackFailedCount == 0 && window.rollbackFatalCount == 0
        self.diagnosticsSummary = "v8.20,rollbackDrill,attempted=\(window.rollbackAttemptCount),succeeded=\(window.rollbackSucceededCount),failed=\(window.rollbackFailedCount),fatal=\(window.rollbackFatalCount),clean=\(clean)"
    }
}

nonisolated enum CanonicalLibraryMetadataEndToEndPilotStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case pilotIncomplete
    case pilotWriteSideOnly
    case pilotReadSideParallelOnly
    case pilotObservationReady
    case pilotRetirementCandidateReady
    case blocked
}

nonisolated enum CanonicalLibraryMetadataEndToEndPilotBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case observationBlocked
    case retirementCandidateBlocked
    case writeSideMissing
    case readSideMissing
}

nonisolated struct CanonicalLibraryMetadataEndToEndPilotReport: Codable, Equatable, Sendable {
    var status: CanonicalLibraryMetadataEndToEndPilotStatus
    var observationWindow: CanonicalLibraryMetadataObservationWindow
    var observationGate: CanonicalLibraryMetadataObservationGateResult
    var retirementCandidateReport: CanonicalLibraryMetadataRetirementCandidateReport
    var rollbackDrillSummary: CanonicalLibraryMetadataRollbackDrillSummary
    var blockers: [CanonicalLibraryMetadataEndToEndPilotBlocker]
    var diagnostics: [CanonicalLibraryMetadataCutoverDiagnostic]
    var diagnosticsSummary: String

    nonisolated init(
        observationWindow: CanonicalLibraryMetadataObservationWindow,
        observationGate: CanonicalLibraryMetadataObservationGateResult,
        retirementCandidateReport: CanonicalLibraryMetadataRetirementCandidateReport
    ) {
        self.observationWindow = observationWindow
        self.observationGate = observationGate
        self.retirementCandidateReport = retirementCandidateReport
        self.rollbackDrillSummary = CanonicalLibraryMetadataRollbackDrillSummary(window: observationWindow)
        var blockers: [CanonicalLibraryMetadataEndToEndPilotBlocker] = []
        if observationWindow.writeCanonicalCommitSucceededCount == 0 {
            blockers.append(.writeSideMissing)
        }
        if observationWindow.readEvidenceCount == 0 {
            blockers.append(.readSideMissing)
        }
        if !observationGate.complete {
            blockers.append(.observationBlocked)
        }
        if !retirementCandidateReport.retirementCandidateReady {
            blockers.append(.retirementCandidateBlocked)
        }
        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        self.blockers = uniqueBlockers
        if retirementCandidateReport.retirementCandidateReady {
            self.status = .pilotRetirementCandidateReady
        } else if observationGate.complete {
            self.status = .pilotObservationReady
        } else if observationWindow.writeCanonicalCommitSucceededCount > 0 && observationWindow.readEvidenceCount == 0 {
            self.status = .pilotWriteSideOnly
        } else if observationWindow.writeCanonicalCommitSucceededCount == 0 && observationWindow.readEvidenceCount > 0 {
            self.status = .pilotReadSideParallelOnly
        } else if uniqueBlockers.contains(.observationBlocked) || uniqueBlockers.contains(.retirementCandidateBlocked) {
            self.status = .blocked
        } else {
            self.status = .pilotIncomplete
        }
        let generated = CanonicalLibraryMetadataCutoverDiagnostic(
            kind: .canonicalLibraryMetadataEndToEndPilotReportGenerated,
            syncRunID: nil,
            trigger: .periodic,
            nodeRole: .testHarness,
            result: status.rawValue,
            reason: uniqueBlockers.map(\.rawValue).joined(separator: "+")
        )
        self.diagnostics = observationWindow.diagnostics + observationGate.diagnostics + retirementCandidateReport.diagnostics + [generated]
        self.diagnosticsSummary = [
            "v8.20",
            "endToEndStatus=\(status.rawValue)",
            "retirementCandidateReady=\(retirementCandidateReport.retirementCandidateReady)",
            "legacyDeleted=false",
            "legacyDisabled=false",
            "runtimeSwitch=false",
            "blockers=\(uniqueBlockers.map(\.rawValue).joined(separator: "+"))"
        ].joined(separator: ",")
    }
}

extension CanonicalProductionSideEffect {
    nonisolated var isUnsafeForLibraryMetadataObservation: Bool {
        switch kind {
        case .networkRequest, .uploadSessionStart, .uploadChunkSend, .uploadFinalize, .generatedArtifactApply, .tombstoneMark:
            return true
        case .fileRead, .fileWrite, .metadataApply, .conflictRecord, .diagnosticsWrite:
            return false
        }
    }
}

extension CanonicalMigrationDomainMatrix {
    nonisolated static func v820LibraryMetadataObservationReport(
        observationGate: CanonicalLibraryMetadataObservationGateResult,
        retirementCandidateReport: CanonicalLibraryMetadataRetirementCandidateReport
    ) -> CanonicalMigrationDomainMatrix {
        let base = CanonicalMigrationDomainMatrix.defaultV813()
        let libraryPolicy = CanonicalMigrationDomainPolicy.v820LibraryMetadataObservation(
            observationGate: observationGate,
            retirementCandidateReport: retirementCandidateReport
        )
        return CanonicalMigrationDomainMatrix(
            policies: base.policies.map { $0.domain == .libraryMetadata ? libraryPolicy : $0 },
            libraryMetadataPilotComplete: false
        )
    }
}

extension CanonicalMigrationDomainPolicy {
    nonisolated static func v820LibraryMetadataObservation(
        observationGate: CanonicalLibraryMetadataObservationGateResult,
        retirementCandidateReport: CanonicalLibraryMetadataRetirementCandidateReport
    ) -> CanonicalMigrationDomainPolicy {
        var statuses: [CanonicalMigrationStage: CanonicalMigrationStageStatus] = [
            .projected: .complete,
            .planned: .complete,
            .noCommit: .complete,
            .realApplyPort: .complete,
            .commitExecutor: .complete,
            .appSeamDefaultOff: .complete,
            .nextPilotCandidate: .complete,
            .canaryN0: .complete,
            .canaryN1: .writeSideCanaryObserved,
            .expandedCanary: .writeSideCanaryObserved,
            .domainCutover: .writeSideCanaryObserved,
            .readSideParallel: .readSideObserved,
            .readSideCutover: observationGate.complete ? .observationComplete : .retirementBlocked
        ]
        statuses[.retirementCandidate] = retirementCandidateReport.retirementCandidateReady ? .retirementCandidateReady : .retirementBlocked
        return CanonicalMigrationDomainPolicy(
            domain: .libraryMetadata,
            stageStatuses: statuses,
            activePilot: true,
            activePilotExplicit: true,
            staticOnly: false,
            blockedForRealMigration: !retirementCandidateReport.retirementCandidateReady,
            defaultCutoverEnabled: false,
            releaseDefaultEnabledCutover: false,
            runtimeSwitchEnabled: false,
            legacySuppressionAllowed: false,
            noProductionInjection: true,
            readPathLegacy: true,
            writeSideCutoverSucceeded: observationGate.complete,
            observationComplete: observationGate.complete,
            fallbackReady: !observationGate.blockers.contains(.fallbackMissing)
        )
    }
}
