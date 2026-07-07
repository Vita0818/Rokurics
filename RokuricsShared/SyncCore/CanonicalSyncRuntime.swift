//
//  CanonicalSyncRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/7.
//

import Foundation

nonisolated enum CanonicalSyncRuntimeMode: String, Codable, Equatable, Sendable {
    case disabled
    case diagnosticsOnly
    case canonicalPlanNoCommit
    case canonicalPlanPrimaryWithLegacyFallback
    case blocked

    nonisolated var canUseCanonicalAsPrimary: Bool {
        self == .canonicalPlanPrimaryWithLegacyFallback
    }

    nonisolated var evaluatesCanonicalCandidate: Bool {
        switch self {
        case .disabled, .diagnosticsOnly, .canonicalPlanNoCommit, .canonicalPlanPrimaryWithLegacyFallback:
            return true
        case .blocked:
            return false
        }
    }
}

nonisolated enum CanonicalSyncRuntimeDecisionScope: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case libraryMetadata
    case generatedArtifacts
    case tombstoneConflict
    case audioUpload
    case recordingExistence
}

nonisolated struct CanonicalSyncRuntimePolicy: Codable, Equatable, Sendable {
    var debugInternalBuild: Bool
    var ownerApproved: Bool
    var releaseDefaultBuild: Bool
    var legacyFallbackAvailable: Bool
    var diagnosticsRedacted: Bool
    var runtimeSwitchEnabled: Bool
    var readPathLegacy: Bool
    var otherActiveMigrationDomainConflicting: Bool
    var allowDocumentedModifiedAtFallback: Bool
    var enabledScopes: [CanonicalSyncRuntimeDecisionScope]

    nonisolated init(
        debugInternalBuild: Bool = false,
        ownerApproved: Bool = false,
        releaseDefaultBuild: Bool = true,
        legacyFallbackAvailable: Bool = true,
        diagnosticsRedacted: Bool = true,
        runtimeSwitchEnabled: Bool = false,
        readPathLegacy: Bool = true,
        otherActiveMigrationDomainConflicting: Bool = false,
        allowDocumentedModifiedAtFallback: Bool = false,
        enabledScopes: [CanonicalSyncRuntimeDecisionScope] = [.recordingMetadata, .libraryMetadata, .generatedArtifacts, .tombstoneConflict, .audioUpload, .recordingExistence]
    ) {
        self.debugInternalBuild = debugInternalBuild
        self.ownerApproved = ownerApproved
        self.releaseDefaultBuild = releaseDefaultBuild
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.diagnosticsRedacted = diagnosticsRedacted
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.readPathLegacy = readPathLegacy
        self.otherActiveMigrationDomainConflicting = otherActiveMigrationDomainConflicting
        self.allowDocumentedModifiedAtFallback = allowDocumentedModifiedAtFallback
        self.enabledScopes = Array(Set(enabledScopes)).sorted { $0.rawValue < $1.rawValue }
    }
}

nonisolated struct CanonicalSyncRuntimeConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalSyncRuntimeMode
    var policy: CanonicalSyncRuntimePolicy

    nonisolated init(
        mode: CanonicalSyncRuntimeMode = .disabled,
        policy: CanonicalSyncRuntimePolicy = CanonicalSyncRuntimePolicy()
    ) {
        self.mode = mode
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalSyncRuntimeConfiguration()
}

nonisolated enum CanonicalSyncPlanAuthorityGateState: String, Codable, Equatable, Sendable {
    case allowed
    case allowedNoCommit
    case blockedMissingSnapshot
    case blockedInvalidManifest
    case blockedPeerUnavailable
    case blockedSchemaMismatch
    case blockedUnsupportedObjects
    case blockedFallbackRequiredObjects
    case blockedConflicts
    case blockedPeerUnknown
    case blockedReleaseDefault
    case blocked
}

nonisolated enum CanonicalSyncPlanAuthorityBlocker: String, Codable, Equatable, Hashable, Sendable {
    case missingInventorySnapshot
    case invalidLocalManifest
    case invalidPeerManifest
    case peerUnavailable
    case schemaMismatch
    case unsupportedObjects
    case fallbackRequiredObjects
    case unresolvedConflicts
    case peerUnknownAudio
    case legacyFallbackUnavailable
    case diagnosticsNotRedacted
    case runtimeSwitchEnabled
    case readPathNotLegacy
    case otherActiveMigrationDomain
    case releaseDefaultPrimary
    case debugInternalApprovalMissing
    case blockedMode
    case canonicalModifiedAtUnavailable
}

nonisolated struct CanonicalSyncPlanAuthorityGateResult: Codable, Equatable, Sendable {
    var state: CanonicalSyncPlanAuthorityGateState
    var blockers: [CanonicalSyncPlanAuthorityBlocker]
    var mode: CanonicalSyncRuntimeMode

    nonisolated var isAllowed: Bool {
        state == .allowed || state == .allowedNoCommit
    }

    nonisolated var shouldUseCanonicalPrimary: Bool {
        state == .allowed && mode == .canonicalPlanPrimaryWithLegacyFallback
    }

    nonisolated var shouldRecordNoCommit: Bool {
        state == .allowedNoCommit || mode == .canonicalPlanNoCommit
    }
}

nonisolated struct CanonicalSyncPlanAuthorityGateContext: Codable, Equatable, Sendable {
    var inventorySnapshotAvailable: Bool
    var localManifest: CanonicalManifest?
    var peerManifest: CanonicalManifest?
    var peerAbsenceExplicitlyModeled: Bool
    var localMetadataHashSchemaVersion: String
    var peerMetadataHashSchemaVersion: String?
    var localLibraryMetadataHashSchemaVersion: String
    var peerLibraryMetadataHashSchemaVersion: String?
    var localGeneratedArtifactHashSchemaVersion: String
    var peerGeneratedArtifactHashSchemaVersion: String?
    var localTombstoneConflictHashSchemaVersion: String
    var peerTombstoneConflictHashSchemaVersion: String?
    var canonicalModifiedAtSemanticsAvailable: Bool
    var unsupportedLegacyObjectCount: Int
    var libraryFallbackRequiredObjectCount: Int
    var conflictCount: Int
    var peerUnknownAudioCount: Int
    var legacyFallbackAvailable: Bool
    var diagnosticsRedacted: Bool
    var runtimeSwitchEnabled: Bool
    var readPathLegacy: Bool
    var otherActiveMigrationDomainConflicting: Bool
    var debugInternalBuild: Bool
    var ownerApproved: Bool
    var releaseDefaultBuild: Bool

    nonisolated init(
        inventorySnapshotAvailable: Bool,
        localManifest: CanonicalManifest?,
        peerManifest: CanonicalManifest?,
        peerAbsenceExplicitlyModeled: Bool = false,
        localMetadataHashSchemaVersion: String = CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
        peerMetadataHashSchemaVersion: String? = CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
        localLibraryMetadataHashSchemaVersion: String = CanonicalLibraryMetadataHashSchema.version,
        peerLibraryMetadataHashSchemaVersion: String? = CanonicalLibraryMetadataHashSchema.version,
        localGeneratedArtifactHashSchemaVersion: String = CanonicalGeneratedArtifactHashSchema.version,
        peerGeneratedArtifactHashSchemaVersion: String? = CanonicalGeneratedArtifactHashSchema.version,
        localTombstoneConflictHashSchemaVersion: String = CanonicalTombstoneConflictHashSchema.version,
        peerTombstoneConflictHashSchemaVersion: String? = CanonicalTombstoneConflictHashSchema.version,
        canonicalModifiedAtSemanticsAvailable: Bool = true,
        unsupportedLegacyObjectCount: Int = 0,
        libraryFallbackRequiredObjectCount: Int = 0,
        conflictCount: Int = 0,
        peerUnknownAudioCount: Int = 0,
        legacyFallbackAvailable: Bool = true,
        diagnosticsRedacted: Bool = true,
        runtimeSwitchEnabled: Bool = false,
        readPathLegacy: Bool = true,
        otherActiveMigrationDomainConflicting: Bool = false,
        debugInternalBuild: Bool = false,
        ownerApproved: Bool = false,
        releaseDefaultBuild: Bool = true
    ) {
        self.inventorySnapshotAvailable = inventorySnapshotAvailable
        self.localManifest = localManifest
        self.peerManifest = peerManifest
        self.peerAbsenceExplicitlyModeled = peerAbsenceExplicitlyModeled
        self.localMetadataHashSchemaVersion = localMetadataHashSchemaVersion
        self.peerMetadataHashSchemaVersion = peerMetadataHashSchemaVersion
        self.localLibraryMetadataHashSchemaVersion = localLibraryMetadataHashSchemaVersion
        self.peerLibraryMetadataHashSchemaVersion = peerLibraryMetadataHashSchemaVersion
        self.localGeneratedArtifactHashSchemaVersion = localGeneratedArtifactHashSchemaVersion
        self.peerGeneratedArtifactHashSchemaVersion = peerGeneratedArtifactHashSchemaVersion
        self.localTombstoneConflictHashSchemaVersion = localTombstoneConflictHashSchemaVersion
        self.peerTombstoneConflictHashSchemaVersion = peerTombstoneConflictHashSchemaVersion
        self.canonicalModifiedAtSemanticsAvailable = canonicalModifiedAtSemanticsAvailable
        self.unsupportedLegacyObjectCount = unsupportedLegacyObjectCount
        self.libraryFallbackRequiredObjectCount = libraryFallbackRequiredObjectCount
        self.conflictCount = conflictCount
        self.peerUnknownAudioCount = peerUnknownAudioCount
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.diagnosticsRedacted = diagnosticsRedacted
        self.runtimeSwitchEnabled = runtimeSwitchEnabled
        self.readPathLegacy = readPathLegacy
        self.otherActiveMigrationDomainConflicting = otherActiveMigrationDomainConflicting
        self.debugInternalBuild = debugInternalBuild
        self.ownerApproved = ownerApproved
        self.releaseDefaultBuild = releaseDefaultBuild
    }
}

nonisolated struct CanonicalSyncPlanAuthorityGate {
    nonisolated init() {}

    nonisolated func evaluate(
        configuration: CanonicalSyncRuntimeConfiguration,
        context: CanonicalSyncPlanAuthorityGateContext
    ) -> CanonicalSyncPlanAuthorityGateResult {
        let mode = configuration.mode
        guard mode != .blocked else {
            return result(.blocked, blockers: [.blockedMode], mode: mode)
        }

        var blockers: [CanonicalSyncPlanAuthorityBlocker] = []
        if !context.inventorySnapshotAvailable {
            blockers.append(.missingInventorySnapshot)
        }
        if let localManifest = context.localManifest {
            if localManifest.schemaVersion != CanonicalManifest.currentSchemaVersion || !localManifest.hasValidManifestHash {
                blockers.append(.invalidLocalManifest)
            }
        } else {
            blockers.append(.invalidLocalManifest)
        }
        if let peerManifest = context.peerManifest {
            if peerManifest.schemaVersion != CanonicalManifest.currentSchemaVersion || !peerManifest.hasValidManifestHash {
                blockers.append(.invalidPeerManifest)
            }
        } else if !context.peerAbsenceExplicitlyModeled {
            blockers.append(.peerUnavailable)
        }
        if context.peerManifest != nil {
            let enabledScopes = Set(configuration.policy.enabledScopes)
            if enabledScopes.contains(.recordingMetadata),
               context.peerMetadataHashSchemaVersion != context.localMetadataHashSchemaVersion {
                blockers.append(.schemaMismatch)
            }
            if enabledScopes.contains(.libraryMetadata),
               context.peerLibraryMetadataHashSchemaVersion != context.localLibraryMetadataHashSchemaVersion {
                blockers.append(.schemaMismatch)
            }
            if enabledScopes.contains(.generatedArtifacts),
               context.peerGeneratedArtifactHashSchemaVersion != context.localGeneratedArtifactHashSchemaVersion {
                blockers.append(.schemaMismatch)
            }
            if enabledScopes.contains(.tombstoneConflict),
               context.peerTombstoneConflictHashSchemaVersion != context.localTombstoneConflictHashSchemaVersion {
                blockers.append(.schemaMismatch)
            }
        }
        if !context.canonicalModifiedAtSemanticsAvailable,
           !configuration.policy.allowDocumentedModifiedAtFallback {
            blockers.append(.canonicalModifiedAtUnavailable)
        }
        if context.unsupportedLegacyObjectCount > 0 {
            blockers.append(.unsupportedObjects)
        }
        if context.libraryFallbackRequiredObjectCount > 0 {
            blockers.append(.fallbackRequiredObjects)
        }
        if mode.canUseCanonicalAsPrimary, context.conflictCount > 0 {
            blockers.append(.unresolvedConflicts)
        }
        if mode.canUseCanonicalAsPrimary, context.peerUnknownAudioCount > 0 {
            blockers.append(.peerUnknownAudio)
        }
        if !context.legacyFallbackAvailable || !configuration.policy.legacyFallbackAvailable {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !context.diagnosticsRedacted || !configuration.policy.diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if context.runtimeSwitchEnabled || configuration.policy.runtimeSwitchEnabled {
            blockers.append(.runtimeSwitchEnabled)
        }
        if !context.readPathLegacy || !configuration.policy.readPathLegacy {
            blockers.append(.readPathNotLegacy)
        }
        if context.otherActiveMigrationDomainConflicting || configuration.policy.otherActiveMigrationDomainConflicting {
            blockers.append(.otherActiveMigrationDomain)
        }
        if mode.canUseCanonicalAsPrimary {
            if context.releaseDefaultBuild || configuration.policy.releaseDefaultBuild {
                blockers.append(.releaseDefaultPrimary)
            }
            if !context.debugInternalBuild || !configuration.policy.debugInternalBuild || !context.ownerApproved || !configuration.policy.ownerApproved {
                blockers.append(.debugInternalApprovalMissing)
            }
        }

        let uniqueBlockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
        if let primaryState = blockedState(for: uniqueBlockers) {
            return result(primaryState, blockers: uniqueBlockers, mode: mode)
        }

        switch mode {
        case .disabled, .diagnosticsOnly, .canonicalPlanNoCommit:
            return result(.allowedNoCommit, blockers: [], mode: mode)
        case .canonicalPlanPrimaryWithLegacyFallback:
            return result(.allowed, blockers: [], mode: mode)
        case .blocked:
            return result(.blocked, blockers: [.blockedMode], mode: mode)
        }
    }

    nonisolated private func blockedState(
        for blockers: [CanonicalSyncPlanAuthorityBlocker]
    ) -> CanonicalSyncPlanAuthorityGateState? {
        guard !blockers.isEmpty else {
            return nil
        }
        if blockers.contains(.missingInventorySnapshot) {
            return .blockedMissingSnapshot
        }
        if blockers.contains(.invalidLocalManifest) || blockers.contains(.invalidPeerManifest) {
            return .blockedInvalidManifest
        }
        if blockers.contains(.peerUnavailable) {
            return .blockedPeerUnavailable
        }
        if blockers.contains(.schemaMismatch) {
            return .blockedSchemaMismatch
        }
        if blockers.contains(.unsupportedObjects) {
            return .blockedUnsupportedObjects
        }
        if blockers.contains(.fallbackRequiredObjects) {
            return .blockedFallbackRequiredObjects
        }
        if blockers.contains(.unresolvedConflicts) {
            return .blockedConflicts
        }
        if blockers.contains(.peerUnknownAudio) {
            return .blockedPeerUnknown
        }
        if blockers.contains(.releaseDefaultPrimary) || blockers.contains(.debugInternalApprovalMissing) {
            return .blockedReleaseDefault
        }
        return .blocked
    }

    nonisolated private func result(
        _ state: CanonicalSyncPlanAuthorityGateState,
        blockers: [CanonicalSyncPlanAuthorityBlocker],
        mode: CanonicalSyncRuntimeMode
    ) -> CanonicalSyncPlanAuthorityGateResult {
        CanonicalSyncPlanAuthorityGateResult(state: state, blockers: blockers, mode: mode)
    }
}

nonisolated enum CanonicalSyncRuntimeDiagnosticKind: String, Codable, Equatable, Sendable {
    case canonicalSyncRuntimeModeEvaluated
    case canonicalSyncRuntimeAuthorityGateAllowed
    case canonicalSyncRuntimeAuthorityGateBlocked
    case canonicalSyncRuntimePlanEvaluated
    case canonicalSyncRuntimePlanAllowed
    case canonicalSyncRuntimePlanUsed
    case canonicalSyncRuntimePlanNoCommit
    case canonicalSyncRuntimePlanFallback
    case canonicalSyncRuntimePlanBlocked
    case canonicalSyncRuntimeLegacyHashMismatchIgnored
    case canonicalSyncRuntimeUnsupportedObjectBlocked
    case canonicalSyncRuntimeConflictBlocked
    case canonicalSyncRuntimePeerSnapshotUnavailable
    case canonicalSyncRuntimeDuplicateLegacySuppressed
    case canonicalSyncRuntimeDuplicateExecutionPrevented
    case canonicalSyncRuntimeMetadataHashEqual
    case canonicalSyncRuntimeModifiedAtLWWApplied
    case canonicalSyncRuntimeModifiedAtUnavailable
    case canonicalSyncRuntimeSchemaMismatch
    case canonicalRecordingMetadataDecisionEvaluated
    case canonicalRecordingMetadataDecisionUsed
    case canonicalRecordingMetadataDecisionFallback
    case canonicalRecordingMetadataHashEqual
    case canonicalRecordingMetadataHashChanged
    case canonicalRecordingMetadataLegacyHashMismatchIgnored
    case canonicalRecordingMetadataLWWApplied
    case canonicalRecordingMetadataLWWTieDeferred
    case canonicalRecordingMetadataModifiedAtUnavailable
    case canonicalRecordingMetadataSchemaMismatch
    case canonicalRecordingMetadataConflictBlocked
    case canonicalLibraryMetadataDecisionEvaluated
    case canonicalLibraryMetadataDecisionUsed
    case canonicalLibraryMetadataDecisionFallback
    case canonicalLibraryMetadataHashEqual
    case canonicalLibraryMetadataHashChanged
    case canonicalLibraryMetadataLWWApplied
    case canonicalLibraryMetadataLWWTieDeferred
    case canonicalLibraryMetadataModifiedAtUnavailable
    case canonicalLibraryMetadataSchemaMismatch
    case canonicalLibraryMetadataConflictBlocked
    case canonicalGeneratedArtifactDecisionEvaluated
    case canonicalGeneratedArtifactDecisionUsed
    case canonicalGeneratedArtifactDecisionFallback
    case canonicalGeneratedArtifactHashEqual
    case canonicalGeneratedArtifactHashChanged
    case canonicalGeneratedArtifactContentMissingDeferred
    case canonicalGeneratedArtifactLWWApplied
    case canonicalGeneratedArtifactLWWTieDeferred
    case canonicalGeneratedArtifactModifiedAtUnavailable
    case canonicalGeneratedArtifactSchemaMismatch
    case canonicalGeneratedArtifactConflictBlocked
    case canonicalGeneratedArtifactUnsupportedKindBlocked
    case canonicalTombstoneConflictDecisionEvaluated
    case canonicalTombstoneConflictDecisionUsed
    case canonicalTombstoneConflictDecisionFallback
    case canonicalTombstoneConflictHashEqual
    case canonicalTombstoneConflictHashChanged
    case canonicalTombstoneConflictLegacyHashMismatchIgnored
    case canonicalTombstoneConflictLogicalTimeApplied
    case canonicalTombstoneConflictTieDeferred
    case canonicalTombstoneConflictLogicalTimeUnavailable
    case canonicalTombstoneConflictSchemaMismatch
    case canonicalTombstoneConflictAmbiguousConflictRecorded
    case canonicalTombstoneConflictResurrectionBlocked
    case canonicalTombstoneConflictRestoreBlocked
    case canonicalTombstoneConflictClearBlocked
    case canonicalTombstoneConflictPhysicalDeleteBlocked
    case canonicalTombstoneConflictPermanentDeleteBlocked
    case canonicalTombstoneConflictGCBlocked
    case canonicalTombstoneConflictUnsupportedKindBlocked
    case canonicalAudioUploadDecisionEvaluated
    case canonicalAudioUploadDecisionUsed
    case canonicalAudioUploadDecisionFallback
    case canonicalAudioUploadCandidateMetadataOnly
    case canonicalAudioUploadCandidateReceiveRecordOnly
    case canonicalAudioUploadPeerUnknownDeferred
    case canonicalAudioUploadSameAudioNoOp
    case canonicalAudioUploadDifferentAudioConflict
    case canonicalAudioUploadLocalAudioMissingBlocked
    case canonicalAudioUploadTombstonedBlocked
    case canonicalAudioUploadCompletedLedgerRejected
    case canonicalAudioUploadCanonicalApplyNoAudioBlocked
    case canonicalAudioUploadSecurityFailureNoBypass
    case canonicalExistenceTruthEvaluated
    case canonicalExistenceApplyBridgeEvaluated
    case canonicalExistenceApplyBridgeBlocked
    case canonicalExistenceMetadataOnlyRecordWritten
    case canonicalExistenceMetadataOnlyRecordNoOp
    case canonicalExistenceApplyBridgeRollbackStarted
    case canonicalExistenceApplyBridgeRollbackCompleted
    case canonicalExistenceApplyBridgeRollbackFailed
    case canonicalManifestRecordingsApplyStarted
    case canonicalManifestRecordingsApplyCompleted
    case canonicalManifestRecordingsApplyNoOp
    case canonicalManifestRecordingsApplyBlocked
    case canonicalManifestRecordingsApplyFailed
    case canonicalManifestRecordingsMalformedBlocked
    case canonicalRecordingExistenceMetadataOnlyWritten
    case canonicalRecordingExistenceMetadataOnlyUpdated
    case canonicalRecordingExistenceMetadataOnlyNoOp
    case canonicalRecordingExistenceAudioSameNoOp
    case canonicalRecordingExistenceAudioConflictBlocked
    case canonicalRecordingExistenceRollbackStarted
    case canonicalRecordingExistenceRollbackCompleted
    case canonicalRecordingExistenceRollbackFailed
    case canonicalRecordingExistenceInventoryMerged
    case canonicalRecordingExistenceInventoryConflict
    case canonicalExistencePeerMetadataOnlyUploadCandidate
    case canonicalExistencePeerAbsentMetadataBridgeRequired
    case canonicalExistencePeerUnknownDeferred
    case canonicalExistenceAudioSameNoOp
    case canonicalExistenceAudioConflict
    case canonicalExistenceLocalAudioMissingNoCandidate
    case canonicalExistenceManifestRecordingsConsumed
    case canonicalExistenceManifestRecordingsIgnoredBlocked
    case canonicalExistenceDidNotWriteAudio
    case canonicalExistenceDidNotMarkAudioAvailable
    case canonicalExistenceDidNotMarkUploadCompleted
    case canonicalApplyRuntimeModeEvaluated
    case canonicalApplyRuntimeGateAllowed
    case canonicalApplyRuntimeGateBlocked
    case canonicalApplyRuntimeActionStarted
    case canonicalApplyRuntimeActionCompleted
    case canonicalApplyRuntimeActionFailed
    case canonicalApplyRuntimeRollbackStarted
    case canonicalApplyRuntimeRollbackCompleted
    case canonicalApplyRuntimeRollbackFailed
    case canonicalApplyRuntimeLegacyFallbackUsed
    case canonicalApplyRuntimeDuplicateLegacySuppressed
    case canonicalApplyRuntimeAudioActionBlocked
    case canonicalApplyRuntimeReportBuilt
}

nonisolated struct CanonicalSyncRuntimeDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, syncRunID ?? "", objectID ?? "", actionKind ?? "", detail ?? ""].joined(separator: "|") }
    var kind: CanonicalSyncRuntimeDiagnosticKind
    var syncRunID: String?
    var mode: CanonicalSyncRuntimeMode
    var objectID: String?
    var actionKind: String?
    var hashPrefix: String?
    var count: Int?
    var detail: String?

    nonisolated init(
        kind: CanonicalSyncRuntimeDiagnosticKind,
        syncRunID: String? = nil,
        mode: CanonicalSyncRuntimeMode,
        objectID: String? = nil,
        actionKind: String? = nil,
        hash: CanonicalHash? = nil,
        hashPrefix: String? = nil,
        count: Int? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.syncRunID = Self.safeText(syncRunID)
        self.mode = mode
        self.objectID = Self.safeText(objectID).map { String($0.prefix(48)) }
        self.actionKind = Self.safeText(actionKind)
        self.hashPrefix = hash.map { Self.hashPrefix($0.value) } ?? hashPrefix.map(Self.hashPrefix)
        self.count = count
        self.detail = Self.safeText(detail)
    }

    nonisolated var isRedacted: Bool {
        let values = [syncRunID, objectID, actionKind, hashPrefix, detail].compactMap { $0 }
        guard values.allSatisfy({ !$0.contains("/") && !$0.contains("\\") && !$0.contains("://") && !$0.contains("{") && !$0.contains("}") }) else {
            return false
        }
        return hashPrefix.map { $0.count <= 12 } ?? true
    }

    nonisolated func summary() -> String {
        [
            "mode=\(mode.rawValue)",
            syncRunID.map { "syncRunID=\($0)" },
            objectID.map { "objectID=\($0)" },
            actionKind.map { "action=\($0)" },
            hashPrefix.map { "hashPrefix=\($0)" },
            count.map { "count=\($0)" },
            detail.map { "detail=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    nonisolated private static func hashPrefix(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
    }

    nonisolated private static func safeText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        let forbidden = ["/", "\\", "://", "{", "}", "\n", "\r"]
        guard forbidden.contains(where: { trimmed.contains($0) }) else {
            return trimmed
        }
        let sanitized = forbidden.reduce(trimmed) { partial, token in
            partial.replacingOccurrences(of: token, with: "_")
        }
        return String(sanitized.prefix(12))
    }
}

nonisolated struct CanonicalSyncRuntimeResult: Codable, Equatable, Sendable {
    var mode: CanonicalSyncRuntimeMode
    var gateResult: CanonicalSyncPlanAuthorityGateResult
    var canonicalPlanUsed: Bool
    var canonicalPlanFallback: Bool
    var canonicalPlanBlocked: Bool
    var canonicalPlanNoCommit: Bool
    var diagnostics: [CanonicalSyncRuntimeDiagnostic]

    nonisolated static func make(
        mode: CanonicalSyncRuntimeMode,
        gateResult: CanonicalSyncPlanAuthorityGateResult,
        syncRunID: String?,
        extraDiagnostics: [CanonicalSyncRuntimeDiagnostic] = []
    ) -> CanonicalSyncRuntimeResult {
        let used = gateResult.shouldUseCanonicalPrimary
        let noCommit = !used && gateResult.isAllowed
        let blocked = !gateResult.isAllowed
        var diagnostics = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalSyncRuntimeModeEvaluated,
                syncRunID: syncRunID,
                mode: mode,
                detail: "state=\(gateResult.state.rawValue)"
            ),
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalSyncRuntimePlanEvaluated,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: gateResult.state.rawValue
            ),
            CanonicalSyncRuntimeDiagnostic(
                kind: gateResult.isAllowed ? .canonicalSyncRuntimeAuthorityGateAllowed : .canonicalSyncRuntimeAuthorityGateBlocked,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: gateResult.blockers.map(\.rawValue).joined(separator: "+").nilIfEmpty ?? "none"
            ),
            CanonicalSyncRuntimeDiagnostic(
                kind: gateResult.isAllowed ? .canonicalSyncRuntimePlanAllowed : .canonicalSyncRuntimePlanBlocked,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: gateResult.state.rawValue
            )
        ]
        if used {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimePlanUsed, syncRunID: syncRunID, mode: mode, detail: "primary"))
        } else if noCommit {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimePlanNoCommit, syncRunID: syncRunID, mode: mode, detail: "legacyOwner"))
        } else {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimePlanFallback, syncRunID: syncRunID, mode: mode, count: gateResult.blockers.count, detail: gateResult.state.rawValue))
        }
        diagnostics.append(contentsOf: extraDiagnostics)
        diagnostics.append(contentsOf: recordingMetadataDecisionDiagnostics(
            mode: mode,
            gateResult: gateResult,
            syncRunID: syncRunID,
            used: used,
            noCommit: noCommit,
            extraDiagnostics: extraDiagnostics
        ))
        diagnostics.append(contentsOf: libraryMetadataDecisionDiagnostics(
            mode: mode,
            gateResult: gateResult,
            syncRunID: syncRunID,
            used: used,
            noCommit: noCommit,
            extraDiagnostics: extraDiagnostics
        ))
        diagnostics.append(contentsOf: generatedArtifactDecisionDiagnostics(
            mode: mode,
            gateResult: gateResult,
            syncRunID: syncRunID,
            used: used,
            noCommit: noCommit,
            extraDiagnostics: extraDiagnostics
        ))
        diagnostics.append(contentsOf: tombstoneConflictDecisionDiagnostics(
            mode: mode,
            gateResult: gateResult,
            syncRunID: syncRunID,
            used: used,
            noCommit: noCommit,
            extraDiagnostics: extraDiagnostics
        ))
        diagnostics.append(contentsOf: audioUploadDecisionDiagnostics(
            mode: mode,
            gateResult: gateResult,
            syncRunID: syncRunID,
            used: used,
            noCommit: noCommit,
            extraDiagnostics: extraDiagnostics
        ))
        return CanonicalSyncRuntimeResult(
            mode: mode,
            gateResult: gateResult,
            canonicalPlanUsed: used,
            canonicalPlanFallback: !used,
            canonicalPlanBlocked: blocked,
            canonicalPlanNoCommit: noCommit,
            diagnostics: diagnostics
        )
    }

    private nonisolated static func recordingMetadataDecisionDiagnostics(
        mode: CanonicalSyncRuntimeMode,
        gateResult: CanonicalSyncPlanAuthorityGateResult,
        syncRunID: String?,
        used: Bool,
        noCommit: Bool,
        extraDiagnostics: [CanonicalSyncRuntimeDiagnostic]
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var diagnostics = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalRecordingMetadataDecisionEvaluated,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: gateResult.state.rawValue
            )
        ]

        if used {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalRecordingMetadataDecisionUsed,
                syncRunID: syncRunID,
                mode: mode,
                detail: "primary"
            ))
        } else {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalRecordingMetadataDecisionFallback,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: noCommit ? "legacyOwner" : gateResult.state.rawValue
            ))
        }

        if gateResult.blockers.contains(.schemaMismatch) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalRecordingMetadataSchemaMismatch,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }
        if gateResult.blockers.contains(.canonicalModifiedAtUnavailable) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalRecordingMetadataModifiedAtUnavailable,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }
        if gateResult.blockers.contains(.unresolvedConflicts) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalRecordingMetadataConflictBlocked,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }

        for diagnostic in extraDiagnostics {
            switch diagnostic.kind {
            case .canonicalSyncRuntimeMetadataHashEqual:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalRecordingMetadataHashEqual,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeModifiedAtLWWApplied:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalRecordingMetadataLWWApplied,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalRecordingMetadataHashChanged,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeLegacyHashMismatchIgnored:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalRecordingMetadataLegacyHashMismatchIgnored,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeConflictBlocked:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalRecordingMetadataConflictBlocked,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
                if diagnostic.detail?.localizedCaseInsensitiveContains("tie") == true {
                    diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                        kind: .canonicalRecordingMetadataLWWTieDeferred,
                        syncRunID: diagnostic.syncRunID ?? syncRunID,
                        mode: mode,
                        objectID: diagnostic.objectID,
                        actionKind: diagnostic.actionKind,
                        hashPrefix: diagnostic.hashPrefix,
                        count: diagnostic.count,
                        detail: diagnostic.detail
                    ))
                }
            case .canonicalSyncRuntimeModifiedAtUnavailable:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalRecordingMetadataModifiedAtUnavailable,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeSchemaMismatch:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalRecordingMetadataSchemaMismatch,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            default:
                continue
            }
        }
        return diagnostics
    }

    private nonisolated static func libraryMetadataDecisionDiagnostics(
        mode: CanonicalSyncRuntimeMode,
        gateResult: CanonicalSyncPlanAuthorityGateResult,
        syncRunID: String?,
        used: Bool,
        noCommit: Bool,
        extraDiagnostics: [CanonicalSyncRuntimeDiagnostic]
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var diagnostics = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalLibraryMetadataDecisionEvaluated,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: gateResult.state.rawValue
            )
        ]

        if used {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalLibraryMetadataDecisionUsed,
                syncRunID: syncRunID,
                mode: mode,
                detail: "primary"
            ))
        } else {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalLibraryMetadataDecisionFallback,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: noCommit ? "legacyOwner" : gateResult.state.rawValue
            ))
        }

        if gateResult.blockers.contains(.schemaMismatch) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalLibraryMetadataSchemaMismatch,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }
        if gateResult.blockers.contains(.canonicalModifiedAtUnavailable) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalLibraryMetadataModifiedAtUnavailable,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }
        if gateResult.blockers.contains(.unresolvedConflicts) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalLibraryMetadataConflictBlocked,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }

        for diagnostic in extraDiagnostics {
            switch diagnostic.kind {
            case .canonicalSyncRuntimeMetadataHashEqual:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalLibraryMetadataHashEqual,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeModifiedAtLWWApplied:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalLibraryMetadataLWWApplied,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalLibraryMetadataHashChanged,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeConflictBlocked:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalLibraryMetadataConflictBlocked,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
                if diagnostic.detail?.localizedCaseInsensitiveContains("tie") == true {
                    diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                        kind: .canonicalLibraryMetadataLWWTieDeferred,
                        syncRunID: diagnostic.syncRunID ?? syncRunID,
                        mode: mode,
                        objectID: diagnostic.objectID,
                        actionKind: diagnostic.actionKind,
                        hashPrefix: diagnostic.hashPrefix,
                        count: diagnostic.count,
                        detail: diagnostic.detail
                    ))
                }
            case .canonicalSyncRuntimeModifiedAtUnavailable:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalLibraryMetadataModifiedAtUnavailable,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeSchemaMismatch:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalLibraryMetadataSchemaMismatch,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            default:
                continue
            }
        }
        return diagnostics
    }

    private nonisolated static func generatedArtifactDecisionDiagnostics(
        mode: CanonicalSyncRuntimeMode,
        gateResult: CanonicalSyncPlanAuthorityGateResult,
        syncRunID: String?,
        used: Bool,
        noCommit: Bool,
        extraDiagnostics: [CanonicalSyncRuntimeDiagnostic]
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var diagnostics = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalGeneratedArtifactDecisionEvaluated,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: gateResult.state.rawValue
            )
        ]

        if used {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalGeneratedArtifactDecisionUsed,
                syncRunID: syncRunID,
                mode: mode,
                detail: "primary"
            ))
        } else {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalGeneratedArtifactDecisionFallback,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: noCommit ? "legacyOwner" : gateResult.state.rawValue
            ))
        }

        if gateResult.blockers.contains(.schemaMismatch) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalGeneratedArtifactSchemaMismatch,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }
        if gateResult.blockers.contains(.canonicalModifiedAtUnavailable) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalGeneratedArtifactModifiedAtUnavailable,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }
        if gateResult.blockers.contains(.unresolvedConflicts) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalGeneratedArtifactConflictBlocked,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }

        for diagnostic in extraDiagnostics where isGeneratedArtifactDiagnostic(diagnostic) {
            switch diagnostic.kind {
            case .canonicalSyncRuntimeMetadataHashEqual:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalGeneratedArtifactHashEqual,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeModifiedAtLWWApplied:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalGeneratedArtifactLWWApplied,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalGeneratedArtifactHashChanged,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeConflictBlocked:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalGeneratedArtifactConflictBlocked,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
                if diagnostic.detail?.localizedCaseInsensitiveContains("tie") == true {
                    diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                        kind: .canonicalGeneratedArtifactLWWTieDeferred,
                        syncRunID: diagnostic.syncRunID ?? syncRunID,
                        mode: mode,
                        objectID: diagnostic.objectID,
                        actionKind: diagnostic.actionKind,
                        hashPrefix: diagnostic.hashPrefix,
                        count: diagnostic.count,
                        detail: diagnostic.detail
                    ))
                }
            case .canonicalSyncRuntimeModifiedAtUnavailable:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalGeneratedArtifactModifiedAtUnavailable,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeSchemaMismatch:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalGeneratedArtifactSchemaMismatch,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalGeneratedArtifactContentMissingDeferred:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalGeneratedArtifactContentMissingDeferred,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalGeneratedArtifactUnsupportedKindBlocked:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalGeneratedArtifactUnsupportedKindBlocked,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            default:
                continue
            }
        }
        return diagnostics
    }

    private nonisolated static func isGeneratedArtifactDiagnostic(
        _ diagnostic: CanonicalSyncRuntimeDiagnostic
    ) -> Bool {
        let values = [
            diagnostic.detail,
            diagnostic.actionKind,
            diagnostic.objectID
        ].compactMap { $0?.lowercased() }
        return values.contains { value in
            value.contains("generatedartifact") || value.contains("generatedartifacts")
        }
    }

    private nonisolated static func tombstoneConflictDecisionDiagnostics(
        mode: CanonicalSyncRuntimeMode,
        gateResult: CanonicalSyncPlanAuthorityGateResult,
        syncRunID: String?,
        used: Bool,
        noCommit: Bool,
        extraDiagnostics: [CanonicalSyncRuntimeDiagnostic]
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var diagnostics = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalTombstoneConflictDecisionEvaluated,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: gateResult.state.rawValue
            )
        ]

        if used {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalTombstoneConflictDecisionUsed,
                syncRunID: syncRunID,
                mode: mode,
                detail: "primary"
            ))
        } else {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalTombstoneConflictDecisionFallback,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: noCommit ? "legacyOwner" : gateResult.state.rawValue
            ))
        }

        if gateResult.blockers.contains(.schemaMismatch) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalTombstoneConflictSchemaMismatch,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }
        if gateResult.blockers.contains(.canonicalModifiedAtUnavailable) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalTombstoneConflictLogicalTimeUnavailable,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }
        if gateResult.blockers.contains(.unresolvedConflicts) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalTombstoneConflictAmbiguousConflictRecorded,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }

        for diagnostic in extraDiagnostics where isTombstoneConflictDiagnostic(diagnostic) {
            switch diagnostic.kind {
            case .canonicalSyncRuntimeMetadataHashEqual:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalTombstoneConflictHashEqual,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeModifiedAtLWWApplied:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalTombstoneConflictLogicalTimeApplied,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalTombstoneConflictHashChanged,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeLegacyHashMismatchIgnored:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalTombstoneConflictLegacyHashMismatchIgnored,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeConflictBlocked:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalTombstoneConflictAmbiguousConflictRecorded,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
                if diagnostic.detail?.localizedCaseInsensitiveContains("tie") == true {
                    diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                        kind: .canonicalTombstoneConflictTieDeferred,
                        syncRunID: diagnostic.syncRunID ?? syncRunID,
                        mode: mode,
                        objectID: diagnostic.objectID,
                        actionKind: diagnostic.actionKind,
                        hashPrefix: diagnostic.hashPrefix,
                        count: diagnostic.count,
                        detail: diagnostic.detail
                    ))
                }
            case .canonicalSyncRuntimeModifiedAtUnavailable:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalTombstoneConflictLogicalTimeUnavailable,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalSyncRuntimeSchemaMismatch:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalTombstoneConflictSchemaMismatch,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            case .canonicalTombstoneConflictResurrectionBlocked,
                .canonicalTombstoneConflictRestoreBlocked,
                .canonicalTombstoneConflictClearBlocked,
                .canonicalTombstoneConflictPhysicalDeleteBlocked,
                .canonicalTombstoneConflictPermanentDeleteBlocked,
                .canonicalTombstoneConflictGCBlocked,
                .canonicalTombstoneConflictUnsupportedKindBlocked:
                diagnostics.append(diagnostic)
            default:
                continue
            }
        }
        return diagnostics
    }

    private nonisolated static func isTombstoneConflictDiagnostic(
        _ diagnostic: CanonicalSyncRuntimeDiagnostic
    ) -> Bool {
        switch diagnostic.kind {
        case .canonicalTombstoneConflictResurrectionBlocked,
            .canonicalTombstoneConflictRestoreBlocked,
            .canonicalTombstoneConflictClearBlocked,
            .canonicalTombstoneConflictPhysicalDeleteBlocked,
            .canonicalTombstoneConflictPermanentDeleteBlocked,
            .canonicalTombstoneConflictGCBlocked,
            .canonicalTombstoneConflictUnsupportedKindBlocked:
            return true
        default:
            break
        }
        let values = [
            diagnostic.detail,
            diagnostic.actionKind,
            diagnostic.objectID
        ].compactMap { $0?.lowercased() }
        return values.contains { value in
            value.contains("tombstoneconflict")
                || value.contains("tombstone")
                || value.contains("resurrection")
                || value.contains("conflictrecord")
        }
    }

    private nonisolated static func audioUploadDecisionDiagnostics(
        mode: CanonicalSyncRuntimeMode,
        gateResult: CanonicalSyncPlanAuthorityGateResult,
        syncRunID: String?,
        used: Bool,
        noCommit: Bool,
        extraDiagnostics: [CanonicalSyncRuntimeDiagnostic]
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var diagnostics = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalAudioUploadDecisionEvaluated,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: gateResult.state.rawValue
            )
        ]

        if used {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalAudioUploadDecisionUsed,
                syncRunID: syncRunID,
                mode: mode,
                detail: "primary"
            ))
        } else {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalAudioUploadDecisionFallback,
                syncRunID: syncRunID,
                mode: mode,
                count: gateResult.blockers.count,
                detail: noCommit ? "legacyOwner" : gateResult.state.rawValue
            ))
        }

        if gateResult.blockers.contains(.peerUnknownAudio) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalAudioUploadPeerUnknownDeferred,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }

        for diagnostic in extraDiagnostics where isAudioUploadDiagnostic(diagnostic) {
            switch diagnostic.kind {
            case .canonicalAudioUploadCandidateMetadataOnly,
                .canonicalAudioUploadCandidateReceiveRecordOnly,
                .canonicalAudioUploadPeerUnknownDeferred,
                .canonicalAudioUploadSameAudioNoOp,
                .canonicalAudioUploadDifferentAudioConflict,
                .canonicalAudioUploadLocalAudioMissingBlocked,
                .canonicalAudioUploadTombstonedBlocked,
                .canonicalAudioUploadCompletedLedgerRejected,
                .canonicalAudioUploadCanonicalApplyNoAudioBlocked,
                .canonicalAudioUploadSecurityFailureNoBypass:
                diagnostics.append(diagnostic)
            case .canonicalSyncRuntimeConflictBlocked:
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalAudioUploadDifferentAudioConflict,
                    syncRunID: diagnostic.syncRunID ?? syncRunID,
                    mode: mode,
                    objectID: diagnostic.objectID,
                    actionKind: diagnostic.actionKind,
                    hashPrefix: diagnostic.hashPrefix,
                    count: diagnostic.count,
                    detail: diagnostic.detail
                ))
            default:
                continue
            }
        }

        if mode == .canonicalPlanPrimaryWithLegacyFallback,
           gateResult.blockers.contains(.unresolvedConflicts) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalAudioUploadDifferentAudioConflict,
                syncRunID: syncRunID,
                mode: mode,
                detail: gateResult.state.rawValue
            ))
        }

        return diagnostics
    }

    private nonisolated static func isAudioUploadDiagnostic(
        _ diagnostic: CanonicalSyncRuntimeDiagnostic
    ) -> Bool {
        switch diagnostic.kind {
        case .canonicalAudioUploadCandidateMetadataOnly,
            .canonicalAudioUploadCandidateReceiveRecordOnly,
            .canonicalAudioUploadPeerUnknownDeferred,
            .canonicalAudioUploadSameAudioNoOp,
            .canonicalAudioUploadDifferentAudioConflict,
            .canonicalAudioUploadLocalAudioMissingBlocked,
            .canonicalAudioUploadTombstonedBlocked,
            .canonicalAudioUploadCompletedLedgerRejected,
            .canonicalAudioUploadCanonicalApplyNoAudioBlocked,
            .canonicalAudioUploadSecurityFailureNoBypass:
            return true
        default:
            break
        }
        let values = [
            diagnostic.detail,
            diagnostic.actionKind,
            diagnostic.objectID
        ].compactMap { $0?.lowercased() }
        return values.contains { value in
            value.contains("audioupload")
                || value.contains("audio-upload")
                || value.contains("audio upload")
                || value.contains("recording-audio")
        }
    }
}

nonisolated struct CanonicalSyncRuntimeActionIdentity: Codable, Equatable, Hashable, Sendable {
    var scope: CanonicalSyncRuntimeDecisionScope
    var objectID: String
    var actionKind: String

    nonisolated init(scope: CanonicalSyncRuntimeDecisionScope, objectID: String, actionKind: String) {
        self.scope = scope
        self.objectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.actionKind = actionKind.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated struct CanonicalSyncRuntimeDuplicateExecutionGuardResult: Codable, Equatable, Sendable {
    var suppressedLegacyActions: [CanonicalSyncRuntimeActionIdentity]
    var preventedDuplicateActions: [CanonicalSyncRuntimeActionIdentity]
    var diagnostics: [CanonicalSyncRuntimeDiagnostic]
}

nonisolated struct CanonicalSyncRuntimeDuplicateExecutionGuard {
    nonisolated init() {}

    nonisolated func evaluate(
        canonicalOwnerUsed: Bool,
        mode: CanonicalSyncRuntimeMode,
        syncRunID: String?,
        canonicalActions: [CanonicalSyncRuntimeActionIdentity],
        legacyActions: [CanonicalSyncRuntimeActionIdentity],
        enabledScopes: [CanonicalSyncRuntimeDecisionScope]
    ) -> CanonicalSyncRuntimeDuplicateExecutionGuardResult {
        guard canonicalOwnerUsed else {
            return CanonicalSyncRuntimeDuplicateExecutionGuardResult(
                suppressedLegacyActions: [],
                preventedDuplicateActions: [],
                diagnostics: []
            )
        }
        let enabled = Set(enabledScopes)
        let canonicalSet = Set(canonicalActions.filter { enabled.contains($0.scope) })
        let duplicates = legacyActions.filter { canonicalSet.contains($0) }.sorted {
            [$0.scope.rawValue, $0.objectID, $0.actionKind].joined(separator: "|")
                < [$1.scope.rawValue, $1.objectID, $1.actionKind].joined(separator: "|")
        }
        let diagnostics = duplicates.map {
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalSyncRuntimeDuplicateExecutionPrevented,
                syncRunID: syncRunID,
                mode: mode,
                objectID: $0.objectID,
                actionKind: $0.actionKind,
                detail: $0.scope.rawValue
            )
        } + (duplicates.isEmpty ? [] : [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalSyncRuntimeDuplicateLegacySuppressed,
                syncRunID: syncRunID,
                mode: mode,
                count: duplicates.count,
                detail: "exactScopeObjectAction"
            )
        ])
        return CanonicalSyncRuntimeDuplicateExecutionGuardResult(
            suppressedLegacyActions: duplicates,
            preventedDuplicateActions: duplicates,
            diagnostics: diagnostics
        )
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
