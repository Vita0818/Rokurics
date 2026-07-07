//
//  CanonicalKernelSwitch.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/7.
//

import Foundation

nonisolated enum CanonicalKernelSwitchMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case oldKernel
    case diagnosticsOnly
    case canonicalShadow
    case canonicalDecisionOnly
    case canonicalApplyNoAudio
    case canonicalFullSync
    case blocked

    nonisolated var displayTitle: String {
        switch self {
        case .oldKernel:
            return "旧内核"
        case .diagnosticsOnly:
            return "诊断"
        case .canonicalShadow:
            return "新内核影子"
        case .canonicalDecisionOnly:
            return "新内核决策"
        case .canonicalApplyNoAudio:
            return "新内核写入不含音频"
        case .canonicalFullSync:
            return "新内核完整同步"
        case .blocked:
            return "已阻断"
        }
    }
}

nonisolated enum CanonicalKernelSwitchOwnerState: String, Codable, Equatable, Hashable, Sendable {
    case oldKernel
    case shadow
    case canonicalNoWrite
    case canonicalReadWrite
    case blocked
}

nonisolated enum CanonicalKernelSwitchGateState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case allowed
    case blockedReleaseDefault
    case blockedMissingConfirmation
    case blockedMissingOwnerApproval
    case blockedMissingLegacyFallback
    case blockedMissingReadPath
    case blockedMissingDomainReadiness
    case blockedMissingAudioUploadReadiness
    case blockedMissingApplyReadiness
    case blockedMissingSwitchBackReadiness
    case blockedUnsafeDiagnostics
    case blockedRouteSecurityRisk
    case blockedContradictoryConfig
    case blocked
}

nonisolated struct CanonicalKernelSwitchModeChoice: Codable, Equatable, Identifiable, Sendable {
    var id: String { rawValue }
    var rawValue: String
    var title: String

    nonisolated init(mode: CanonicalKernelSwitchMode) {
        self.rawValue = mode.rawValue
        self.title = mode.displayTitle
    }

    nonisolated init(rawValue: String, title: String) {
        self.rawValue = rawValue
        self.title = title
    }
}

nonisolated struct CanonicalKernelSwitchPolicy: Codable, Equatable, Sendable {
    var debugInternalBuild: Bool
    var ownerApproved: Bool
    var releaseDefaultBuild: Bool
    var manualFullSyncConfirmation: Bool
    var legacyFallbackAvailable: Bool
    var diagnosticsRedacted: Bool
    var shadowComparisonEnabled: Bool
    var legacyReadPathAvailable: Bool
    var legacyWritePathAvailable: Bool
    var canonicalWritesLegacyReadable: Bool
    var noDataFormatMigrationRequired: Bool
    var canonicalOnlyRequiredFieldsHaveLegacyFallback: Bool
    var physicalMoveDeleteDisabled: Bool
    var secretPathHashLeakRedactionEnabled: Bool
    var shadowCompareAllowedDuringCanonicalOwner: Bool
    var connectionRuntimeReady: Bool
    var inventoryRuntimeReady: Bool
    var syncDecisionRuntimeReady: Bool
    var nonAudioApplyRuntimeReady: Bool
    var transferRuntimeReady: Bool
    var audioUploadRuntimeReady: Bool
    var readRuntimeReady: Bool
    var recordingMetadataReadiness: Bool
    var libraryMetadataReadiness: Bool
    var generatedArtifactsReadiness: Bool
    var tombstoneConflictReadiness: Bool
    var audioUploadReadiness: Bool
    var routeSecurityUnchanged: Bool
    var productionRootConfigurationSafe: Bool
    var unresolvedConflictBlocker: Bool
    var switchBackHardBlocker: Bool
    var canonicalOnlyDiskFormatBlocker: Bool

    nonisolated init(
        debugInternalBuild: Bool = false,
        ownerApproved: Bool = false,
        releaseDefaultBuild: Bool = true,
        manualFullSyncConfirmation: Bool = false,
        legacyFallbackAvailable: Bool = true,
        diagnosticsRedacted: Bool = true,
        shadowComparisonEnabled: Bool = true,
        legacyReadPathAvailable: Bool = true,
        legacyWritePathAvailable: Bool = true,
        canonicalWritesLegacyReadable: Bool = true,
        noDataFormatMigrationRequired: Bool = true,
        canonicalOnlyRequiredFieldsHaveLegacyFallback: Bool = true,
        physicalMoveDeleteDisabled: Bool = true,
        secretPathHashLeakRedactionEnabled: Bool = true,
        shadowCompareAllowedDuringCanonicalOwner: Bool = true,
        connectionRuntimeReady: Bool = true,
        inventoryRuntimeReady: Bool = true,
        syncDecisionRuntimeReady: Bool = true,
        nonAudioApplyRuntimeReady: Bool = true,
        transferRuntimeReady: Bool = true,
        audioUploadRuntimeReady: Bool = true,
        readRuntimeReady: Bool = true,
        recordingMetadataReadiness: Bool = true,
        libraryMetadataReadiness: Bool = true,
        generatedArtifactsReadiness: Bool = true,
        tombstoneConflictReadiness: Bool = true,
        audioUploadReadiness: Bool = true,
        routeSecurityUnchanged: Bool = true,
        productionRootConfigurationSafe: Bool = true,
        unresolvedConflictBlocker: Bool = false,
        switchBackHardBlocker: Bool = false,
        canonicalOnlyDiskFormatBlocker: Bool = false
    ) {
        self.debugInternalBuild = debugInternalBuild
        self.ownerApproved = ownerApproved
        self.releaseDefaultBuild = releaseDefaultBuild
        self.manualFullSyncConfirmation = manualFullSyncConfirmation
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.diagnosticsRedacted = diagnosticsRedacted
        self.shadowComparisonEnabled = shadowComparisonEnabled
        self.legacyReadPathAvailable = legacyReadPathAvailable
        self.legacyWritePathAvailable = legacyWritePathAvailable
        self.canonicalWritesLegacyReadable = canonicalWritesLegacyReadable
        self.noDataFormatMigrationRequired = noDataFormatMigrationRequired
        self.canonicalOnlyRequiredFieldsHaveLegacyFallback = canonicalOnlyRequiredFieldsHaveLegacyFallback
        self.physicalMoveDeleteDisabled = physicalMoveDeleteDisabled
        self.secretPathHashLeakRedactionEnabled = secretPathHashLeakRedactionEnabled
        self.shadowCompareAllowedDuringCanonicalOwner = shadowCompareAllowedDuringCanonicalOwner
        self.connectionRuntimeReady = connectionRuntimeReady
        self.inventoryRuntimeReady = inventoryRuntimeReady
        self.syncDecisionRuntimeReady = syncDecisionRuntimeReady
        self.nonAudioApplyRuntimeReady = nonAudioApplyRuntimeReady
        self.transferRuntimeReady = transferRuntimeReady
        self.audioUploadRuntimeReady = audioUploadRuntimeReady
        self.readRuntimeReady = readRuntimeReady
        self.recordingMetadataReadiness = recordingMetadataReadiness
        self.libraryMetadataReadiness = libraryMetadataReadiness
        self.generatedArtifactsReadiness = generatedArtifactsReadiness
        self.tombstoneConflictReadiness = tombstoneConflictReadiness
        self.audioUploadReadiness = audioUploadReadiness
        self.routeSecurityUnchanged = routeSecurityUnchanged
        self.productionRootConfigurationSafe = productionRootConfigurationSafe
        self.unresolvedConflictBlocker = unresolvedConflictBlocker
        self.switchBackHardBlocker = switchBackHardBlocker
        self.canonicalOnlyDiskFormatBlocker = canonicalOnlyDiskFormatBlocker
    }

    nonisolated static let releaseDefault = CanonicalKernelSwitchPolicy()
    nonisolated static let canonicalFullSyncRuntime = CanonicalKernelSwitchPolicy(
        debugInternalBuild: true,
        ownerApproved: true,
        releaseDefaultBuild: false,
        manualFullSyncConfirmation: true
    )

    nonisolated static func debugInternal(
        ownerApproved: Bool = true,
        manualFullSyncConfirmation: Bool = false
    ) -> CanonicalKernelSwitchPolicy {
        CanonicalKernelSwitchPolicy(
            debugInternalBuild: true,
            ownerApproved: ownerApproved,
            releaseDefaultBuild: false,
            manualFullSyncConfirmation: manualFullSyncConfirmation
        )
    }
}

nonisolated struct CanonicalKernelSwitchAdvancedOverrides: Codable, Equatable, Sendable {
    var connectionRuntimeConfiguration: CanonicalConnectionRuntimeConfiguration?
    var syncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration?
    var applyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration?
    var existenceApplyRuntimeConfiguration: CanonicalExistenceApplyRuntimeConfiguration?
    var transferRuntimeConfiguration: CanonicalTransferRuntimeConfiguration?
    var audioUploadRuntimeConfiguration: CanonicalAudioUploadRuntimeConfiguration?
    var readRuntimeConfiguration: CanonicalReadRuntimeConfiguration?
    var libraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration?

    nonisolated init(
        connectionRuntimeConfiguration: CanonicalConnectionRuntimeConfiguration? = nil,
        syncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration? = nil,
        applyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration? = nil,
        existenceApplyRuntimeConfiguration: CanonicalExistenceApplyRuntimeConfiguration? = nil,
        transferRuntimeConfiguration: CanonicalTransferRuntimeConfiguration? = nil,
        audioUploadRuntimeConfiguration: CanonicalAudioUploadRuntimeConfiguration? = nil,
        readRuntimeConfiguration: CanonicalReadRuntimeConfiguration? = nil,
        libraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration? = nil
    ) {
        self.connectionRuntimeConfiguration = connectionRuntimeConfiguration
        self.syncRuntimeConfiguration = syncRuntimeConfiguration
        self.applyRuntimeConfiguration = applyRuntimeConfiguration
        self.existenceApplyRuntimeConfiguration = existenceApplyRuntimeConfiguration
        self.transferRuntimeConfiguration = transferRuntimeConfiguration
        self.audioUploadRuntimeConfiguration = audioUploadRuntimeConfiguration
        self.readRuntimeConfiguration = readRuntimeConfiguration
        self.libraryMetadataDebugPilotConfiguration = libraryMetadataDebugPilotConfiguration
    }

    nonisolated static let none = CanonicalKernelSwitchAdvancedOverrides()
}

nonisolated enum CanonicalKernelSwitchBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case explicitBlockedMode
    case releaseDefaultCannotUseCanonicalFullSync
    case canonicalFullSyncRequiresDebugInternalBuild
    case canonicalFullSyncRequiresOwnerApproval
    case canonicalFullSyncRequiresManualConfirmation
    case legacyFallbackUnavailable
    case diagnosticsNotRedacted
    case legacyReadPathUnavailable
    case legacyWritePathUnavailable
    case canonicalWritesNotLegacyReadable
    case switchBackWouldRequireDataFormatMigration
    case canonicalOnlyRequiredFieldWithoutLegacyFallback
    case physicalMoveOrDeleteWouldBeRequired
    case secretPathHashLeakRisk
    case shadowCompareCannotStayEnabledWithCanonicalOwner
    case advancedOverrideContradictsMasterSwitch
    case connectionRuntimeReadinessMissing
    case inventoryRuntimeReadinessMissing
    case syncDecisionRuntimeReadinessMissing
    case nonAudioApplyRuntimeReadinessMissing
    case transferRuntimeReadinessMissing
    case audioUploadRuntimeReadinessMissing
    case readRuntimeReadinessMissing
    case recordingMetadataReadinessMissing
    case libraryMetadataReadinessMissing
    case generatedArtifactsReadinessMissing
    case tombstoneConflictReadinessMissing
    case audioUploadReadinessMissing
    case routeSecurityRisk
    case unsafeProductionRootConfiguration
    case unresolvedConflict
    case switchBackHardBlocker
    case canonicalOnlyDiskFormatBlocker
}

nonisolated enum CanonicalKernelSwitchDiagnosticKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case canonicalKernelSwitchModeEvaluated
    case canonicalKernelSwitchEffectiveConfigBuilt
    case canonicalKernelSwitchGateAllowed
    case canonicalKernelSwitchGateBlocked
    case canonicalKernelSwitchOldKernelSelected
    case canonicalKernelSwitchCanonicalShadowSelected
    case canonicalKernelSwitchCanonicalDecisionOnlySelected
    case canonicalKernelSwitchCanonicalApplyNoAudioSelected
    case canonicalKernelSwitchCanonicalFullSyncRequested
    case canonicalKernelSwitchCanonicalFullSyncAllowed
    case canonicalKernelSwitchCanonicalFullSyncBlocked
    case canonicalKernelSwitchContradictoryConfigBlocked
    case canonicalKernelSwitchSpecializedConfigRestricted
    case canonicalKernelSwitchSpecializedConfigBypassBlocked
    case canonicalKernelSwitchReleaseDefaultBlocked
    case canonicalKernelSwitchFallbackPreserved
    case canonicalKernelSwitchReadinessMissing
    case canonicalKernelSwitchReportBuilt
}

nonisolated struct CanonicalKernelSwitchDiagnostic: Codable, Equatable, Identifiable, Sendable {
    var id: String { [kind.rawValue, mode.rawValue, detail ?? ""].joined(separator: "|") }
    var kind: CanonicalKernelSwitchDiagnosticKind
    var mode: CanonicalKernelSwitchMode
    var nodeRole: String?
    var syncRunID: String?
    var blocker: CanonicalKernelSwitchBlocker?
    var detail: String?

    nonisolated init(
        kind: CanonicalKernelSwitchDiagnosticKind,
        mode: CanonicalKernelSwitchMode,
        nodeRole: String? = nil,
        syncRunID: String? = nil,
        blocker: CanonicalKernelSwitchBlocker? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.mode = mode
        self.nodeRole = Self.safeText(nodeRole)
        self.syncRunID = Self.safeText(syncRunID)
        self.blocker = blocker
        self.detail = Self.safeText(detail)
    }

    nonisolated var isRedacted: Bool {
        [nodeRole, syncRunID, detail].compactMap { $0 }.allSatisfy {
            !$0.contains("/") && !$0.contains("\\") && !$0.contains("://") && !$0.contains("{") && !$0.contains("}")
        }
    }

    nonisolated var diagnosticsSummary: String {
        [
            "kind=\(kind.rawValue)",
            "mode=\(mode.rawValue)",
            nodeRole.map { "nodeRole=\($0)" },
            syncRunID.map { "syncRunID=\($0)" },
            blocker.map { "blocker=\($0.rawValue)" },
            detail.map { "detail=\($0)" },
            "redacted=true"
        ].compactMap { $0 }.joined(separator: ",")
    }

    private nonisolated static func safeText(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        let forbidden = ["/", "\\", "://", "{", "}", "\n", "\r"]
        let sanitized = forbidden.reduce(trimmed) { partial, token in
            partial.replacingOccurrences(of: token, with: "_")
        }
        return String(sanitized.prefix(160))
    }
}

nonisolated struct CanonicalKernelSwitchReversibilityProof: Codable, Equatable, Sendable {
    var legacyReadPathStillExists: Bool
    var legacyWritePathStillExists: Bool
    var canonicalWritesAreLegacyReadable: Bool
    var noDataFormatMigrationRequiredToSwitchBack: Bool
    var noCanonicalOnlyRequiredFieldWithoutLegacyFallback: Bool
    var noPhysicalMoveOrDeleteRequired: Bool
    var secretPathHashLeakRedactionEnabled: Bool
    var shadowCompareCanStayOnWhileCanonicalOwnerActive: Bool
    var requiresDataMigrationToSwitchBack: Bool
    var blockers: [CanonicalKernelSwitchBlocker]

    nonisolated var isReversible: Bool {
        blockers.isEmpty && !requiresDataMigrationToSwitchBack
    }
}

nonisolated struct CanonicalKernelSwitchReversibilityGate: Sendable {
    nonisolated init() {}

    nonisolated func prove(policy: CanonicalKernelSwitchPolicy) -> CanonicalKernelSwitchReversibilityProof {
        var blockers: [CanonicalKernelSwitchBlocker] = []
        if !policy.legacyReadPathAvailable {
            blockers.append(.legacyReadPathUnavailable)
        }
        if !policy.legacyWritePathAvailable {
            blockers.append(.legacyWritePathUnavailable)
        }
        if !policy.canonicalWritesLegacyReadable {
            blockers.append(.canonicalWritesNotLegacyReadable)
        }
        if !policy.noDataFormatMigrationRequired {
            blockers.append(.switchBackWouldRequireDataFormatMigration)
        }
        if !policy.canonicalOnlyRequiredFieldsHaveLegacyFallback {
            blockers.append(.canonicalOnlyRequiredFieldWithoutLegacyFallback)
        }
        if !policy.physicalMoveDeleteDisabled {
            blockers.append(.physicalMoveOrDeleteWouldBeRequired)
        }
        if !policy.secretPathHashLeakRedactionEnabled {
            blockers.append(.secretPathHashLeakRisk)
        }
        if !policy.shadowCompareAllowedDuringCanonicalOwner {
            blockers.append(.shadowCompareCannotStayEnabledWithCanonicalOwner)
        }

        return CanonicalKernelSwitchReversibilityProof(
            legacyReadPathStillExists: policy.legacyReadPathAvailable,
            legacyWritePathStillExists: policy.legacyWritePathAvailable,
            canonicalWritesAreLegacyReadable: policy.canonicalWritesLegacyReadable,
            noDataFormatMigrationRequiredToSwitchBack: policy.noDataFormatMigrationRequired,
            noCanonicalOnlyRequiredFieldWithoutLegacyFallback: policy.canonicalOnlyRequiredFieldsHaveLegacyFallback,
            noPhysicalMoveOrDeleteRequired: policy.physicalMoveDeleteDisabled,
            secretPathHashLeakRedactionEnabled: policy.secretPathHashLeakRedactionEnabled,
            shadowCompareCanStayOnWhileCanonicalOwnerActive: policy.shadowCompareAllowedDuringCanonicalOwner,
            requiresDataMigrationToSwitchBack: !policy.noDataFormatMigrationRequired,
            blockers: blockers
        )
    }
}

nonisolated struct CanonicalKernelSwitchMigrationMatrixPolicy: Codable, Equatable, Sendable {
    var mode: CanonicalKernelSwitchMode
    var ownerState: CanonicalKernelSwitchOwnerState
    var activeCanonicalOwnershipDomains: [CanonicalMigrationDomain]
    var legacyReadPathRetained: Bool
    var legacyWritePathRetained: Bool
    var migrationRequiredToSwitchBack: Bool
    var diskFormatPolicy: String
    var diagnosticsRedacted: Bool

    nonisolated static func make(
        mode: CanonicalKernelSwitchMode,
        ownerState: CanonicalKernelSwitchOwnerState,
        activeCanonicalOwnershipDomains: [CanonicalMigrationDomain],
        policy: CanonicalKernelSwitchPolicy,
        proof: CanonicalKernelSwitchReversibilityProof
    ) -> CanonicalKernelSwitchMigrationMatrixPolicy {
        CanonicalKernelSwitchMigrationMatrixPolicy(
            mode: mode,
            ownerState: ownerState,
            activeCanonicalOwnershipDomains: activeCanonicalOwnershipDomains.sorted { $0.rawValue < $1.rawValue },
            legacyReadPathRetained: policy.legacyReadPathAvailable,
            legacyWritePathRetained: policy.legacyWritePathAvailable,
            migrationRequiredToSwitchBack: proof.requiresDataMigrationToSwitchBack,
            diskFormatPolicy: "legacy-readable-or-dual-write-compatible",
            diagnosticsRedacted: policy.diagnosticsRedacted
        )
    }
}

nonisolated struct CanonicalKernelSwitchEffectiveConfiguration: Codable, Equatable, Sendable {
    var connectionRuntimeConfiguration: CanonicalConnectionRuntimeConfiguration
    var inventoryRuntimeConfiguration: CanonicalInventoryRuntimeConfiguration
    var syncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration
    var applyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration
    var existenceApplyRuntimeConfiguration: CanonicalExistenceApplyRuntimeConfiguration
    var transferRuntimeConfiguration: CanonicalTransferRuntimeConfiguration
    var audioUploadRuntimeConfiguration: CanonicalAudioUploadRuntimeConfiguration
    var readRuntimeConfiguration: CanonicalReadRuntimeConfiguration
    var libraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration
    var migrationMatrixPolicy: CanonicalKernelSwitchMigrationMatrixPolicy

    nonisolated static func blocked(
        policy: CanonicalKernelSwitchPolicy,
        proof: CanonicalKernelSwitchReversibilityProof
    ) -> CanonicalKernelSwitchEffectiveConfiguration {
        CanonicalKernelSwitchEffectiveConfiguration(
            connectionRuntimeConfiguration: CanonicalConnectionRuntimeConfiguration(mode: .blocked),
            inventoryRuntimeConfiguration: CanonicalInventoryRuntimeConfiguration(redactedDiagnostics: policy.diagnosticsRedacted),
            syncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration(mode: .blocked),
            applyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration(mode: .blocked),
            existenceApplyRuntimeConfiguration: CanonicalExistenceApplyRuntimeConfiguration(mode: .blocked),
            transferRuntimeConfiguration: CanonicalTransferRuntimeConfiguration(mode: .blocked),
            audioUploadRuntimeConfiguration: CanonicalAudioUploadRuntimeConfiguration(mode: .blocked),
            readRuntimeConfiguration: CanonicalReadRuntimeConfiguration(mode: .blocked),
            libraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration(mode: .blocked),
            migrationMatrixPolicy: .make(
                mode: .blocked,
                ownerState: .blocked,
                activeCanonicalOwnershipDomains: [],
                policy: policy,
                proof: proof
            )
        )
    }
}

nonisolated struct CanonicalKernelSwitchEffectiveConfigurationBuilder: Sendable {
    nonisolated init() {}

    nonisolated func build(
        configuration: CanonicalKernelSwitchConfiguration
    ) -> CanonicalKernelSwitchResult {
        configuration.resolve()
    }
}

nonisolated struct CanonicalKernelSwitchGateResult: Codable, Equatable, Sendable {
    var state: CanonicalKernelSwitchGateState
    var blockers: [CanonicalKernelSwitchBlocker]
    var allowed: Bool

    nonisolated init(
        state: CanonicalKernelSwitchGateState,
        blockers: [CanonicalKernelSwitchBlocker]
    ) {
        self.state = state
        self.blockers = blockers
        self.allowed = state == .allowed && blockers.isEmpty
    }
}

nonisolated struct CanonicalKernelSwitchGate: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        configuration: CanonicalKernelSwitchConfiguration
    ) -> CanonicalKernelSwitchGateResult {
        let result = configuration.resolve()
        return CanonicalKernelSwitchGateResult(
            state: Self.state(for: result.blockers),
            blockers: result.blockers
        )
    }

    nonisolated static func state(for blockers: [CanonicalKernelSwitchBlocker]) -> CanonicalKernelSwitchGateState {
        guard !blockers.isEmpty else {
            return .allowed
        }
        if blockers.contains(.releaseDefaultCannotUseCanonicalFullSync) {
            return .blockedReleaseDefault
        }
        if blockers.contains(.canonicalFullSyncRequiresManualConfirmation) {
            return .blockedMissingConfirmation
        }
        if blockers.contains(.canonicalFullSyncRequiresOwnerApproval) || blockers.contains(.canonicalFullSyncRequiresDebugInternalBuild) {
            return .blockedMissingOwnerApproval
        }
        if blockers.contains(.legacyFallbackUnavailable) {
            return .blockedMissingLegacyFallback
        }
        if blockers.contains(.legacyReadPathUnavailable) {
            return .blockedMissingReadPath
        }
        if blockers.contains(.nonAudioApplyRuntimeReadinessMissing) {
            return .blockedMissingApplyReadiness
        }
        if blockers.contains(.transferRuntimeReadinessMissing)
            || blockers.contains(.audioUploadRuntimeReadinessMissing)
            || blockers.contains(.audioUploadReadinessMissing) {
            return .blockedMissingAudioUploadReadiness
        }
        if blockers.contains(.readRuntimeReadinessMissing) {
            return .blockedMissingReadPath
        }
        if blockers.contains(.switchBackHardBlocker)
            || blockers.contains(.switchBackWouldRequireDataFormatMigration)
            || blockers.contains(.canonicalOnlyDiskFormatBlocker) {
            return .blockedMissingSwitchBackReadiness
        }
        if blockers.contains(.diagnosticsNotRedacted) || blockers.contains(.secretPathHashLeakRisk) {
            return .blockedUnsafeDiagnostics
        }
        if blockers.contains(.routeSecurityRisk) {
            return .blockedRouteSecurityRisk
        }
        if blockers.contains(.advancedOverrideContradictsMasterSwitch) {
            return .blockedContradictoryConfig
        }
        if blockers.contains(.connectionRuntimeReadinessMissing)
            || blockers.contains(.inventoryRuntimeReadinessMissing)
            || blockers.contains(.syncDecisionRuntimeReadinessMissing)
            || blockers.contains(.recordingMetadataReadinessMissing)
            || blockers.contains(.libraryMetadataReadinessMissing)
            || blockers.contains(.generatedArtifactsReadinessMissing)
            || blockers.contains(.tombstoneConflictReadinessMissing) {
            return .blockedMissingDomainReadiness
        }
        return .blocked
    }
}

nonisolated struct CanonicalKernelSwitchResult: Codable, Equatable, Sendable {
    var requestedMode: CanonicalKernelSwitchMode
    var effectiveMode: CanonicalKernelSwitchMode
    var ownerState: CanonicalKernelSwitchOwnerState
    var blockers: [CanonicalKernelSwitchBlocker]
    var effectiveConfiguration: CanonicalKernelSwitchEffectiveConfiguration
    var reversibilityProof: CanonicalKernelSwitchReversibilityProof
    var gateResult: CanonicalKernelSwitchGateResult
    var diagnostics: [CanonicalKernelSwitchDiagnostic]
    var diagnosticsSummary: String
    var redacted: Bool

    nonisolated var isBlocked: Bool {
        effectiveMode == .blocked || !blockers.isEmpty
    }

    nonisolated var effectiveStatusSourceText: String {
        if isBlocked {
            return "legacy fallback · effective=blocked"
        }
        switch effectiveMode {
        case .oldKernel:
            return "legacy · effective=oldKernel"
        case .diagnosticsOnly:
            return "legacy · diagnosticsOnly"
        case .canonicalShadow:
            return "legacy · canonical shadow"
        case .canonicalDecisionOnly:
            return "canonical decision · legacy apply/read"
        case .canonicalApplyNoAudio:
            return "canonical non-audio · legacy audio/read"
        case .canonicalFullSync:
            return "canonical guarded · legacy fallback"
        case .blocked:
            return "legacy fallback · effective=blocked"
        }
    }
}

nonisolated struct CanonicalKernelSwitchReport: Codable, Equatable, Sendable {
    var result: CanonicalKernelSwitchResult
    var diagnostics: [CanonicalKernelSwitchDiagnostic]
    var diagnosticsSummary: String
    var redacted: Bool

    nonisolated init(result: CanonicalKernelSwitchResult) {
        self.result = result
        self.diagnostics = result.diagnostics + [
            CanonicalKernelSwitchDiagnostic(
                kind: .canonicalKernelSwitchReportBuilt,
                mode: result.effectiveMode,
                detail: "blockerCount=\(result.blockers.count)"
            )
        ]
        self.diagnosticsSummary = result.diagnosticsSummary
        self.redacted = result.redacted
    }
}

nonisolated struct CanonicalKernelSwitchConfiguration: Codable, Equatable, Sendable {
    static let debugModeKey = "Rokurics.debug.canonicalKernelSwitch.mode"
    static let debugFullSyncConfirmedKey = "Rokurics.debug.canonicalKernelSwitch.fullSyncConfirmed"
    static let diagnosticsPathText = "Application Support/Rokurics/Diagnostics/canonical-kernel-switch.log"
    static let safetyText = "运行时固定 canonicalFullSync；旧内核代码保留为 canonical 端口不可执行时的操作级 legacy fallback。Debug/Release 不再读取 AppStorage mode 或人工确认开关，专项 debug switches 只能作为高级限制/诊断，不能越权启用。"
    static let emergencyOldKernelSwitchBackText = "Legacy fallback 保留在具体操作层；切回证明 driver 仅验证 legacy 可读和可逆性，不再提供 oldKernel 运行模式。遇到 Divergent、FreezeViolation、RollbackFailed、SecurityFailure 或 ExistingDifferentAudioBlocked 立即停止当前操作。"

    var mode: CanonicalKernelSwitchMode
    var policy: CanonicalKernelSwitchPolicy
    var advancedOverrides: CanonicalKernelSwitchAdvancedOverrides

    nonisolated init(
        mode: CanonicalKernelSwitchMode = .oldKernel,
        policy: CanonicalKernelSwitchPolicy = .releaseDefault,
        advancedOverrides: CanonicalKernelSwitchAdvancedOverrides = .none
    ) {
        self.mode = mode
        self.policy = policy
        self.advancedOverrides = advancedOverrides
    }

    nonisolated static let `default` = CanonicalKernelSwitchConfiguration()
    nonisolated static let oldKernel = CanonicalKernelSwitchConfiguration()
    nonisolated static let runtimeCanonicalFullSync = CanonicalKernelSwitchConfiguration(
        mode: .canonicalFullSync,
        policy: .canonicalFullSyncRuntime
    )

    nonisolated static var debugModeChoices: [CanonicalKernelSwitchModeChoice] {
        [
            .oldKernel,
            .diagnosticsOnly,
            .canonicalShadow,
            .canonicalDecisionOnly,
            .canonicalApplyNoAudio,
            .canonicalFullSync
        ].map(CanonicalKernelSwitchModeChoice.init(mode:))
    }

    nonisolated static var manualSwitchModeChoices: [CanonicalKernelSwitchModeChoice] {
        [
            CanonicalKernelSwitchModeChoice(rawValue: CanonicalKernelSwitchMode.oldKernel.rawValue, title: "旧内核 oldKernel"),
            CanonicalKernelSwitchModeChoice(rawValue: CanonicalKernelSwitchMode.canonicalShadow.rawValue, title: "新内核影子 canonicalShadow"),
            CanonicalKernelSwitchModeChoice(rawValue: CanonicalKernelSwitchMode.canonicalDecisionOnly.rawValue, title: "新内核决策 canonicalDecisionOnly"),
            CanonicalKernelSwitchModeChoice(rawValue: CanonicalKernelSwitchMode.canonicalApplyNoAudio.rawValue, title: "新内核写入不含音频 canonicalApplyNoAudio"),
            CanonicalKernelSwitchModeChoice(rawValue: CanonicalKernelSwitchMode.canonicalFullSync.rawValue, title: "新内核完整同步 canonicalFullSync")
        ]
    }

    nonisolated static var didChangeNotificationName: Notification.Name {
        Notification.Name("RokuricsCanonicalKernelSwitchConfigurationDidChange")
    }

    nonisolated static func normalizedDebugMode(_ rawValue: String) -> String {
        CanonicalKernelSwitchMode(rawValue: rawValue)?.rawValue ?? CanonicalKernelSwitchMode.canonicalFullSync.rawValue
    }

    nonisolated static func normalizedManualSwitchMode(_ rawValue: String) -> String {
        guard let mode = CanonicalKernelSwitchMode(rawValue: rawValue),
              manualSwitchModeChoices.contains(where: { $0.rawValue == mode.rawValue }) else {
            return CanonicalKernelSwitchMode.oldKernel.rawValue
        }
        return mode.rawValue
    }

    nonisolated static func debugStoredConfiguration(
        userDefaults: UserDefaults = .standard
    ) -> CanonicalKernelSwitchConfiguration {
        _ = userDefaults
        return .runtimeCanonicalFullSync
    }

    nonisolated static func runtimeConfigurationFromStoredDefaults(
        userDefaults: UserDefaults = .standard
    ) -> CanonicalKernelSwitchConfiguration {
        _ = userDefaults
        return .runtimeCanonicalFullSync
    }

    nonisolated static func setDebugStoredMode(
        _ rawValue: String,
        userDefaults: UserDefaults = .standard,
        postNotification: Bool = true
    ) {
        let normalized = normalizedDebugMode(rawValue)
        userDefaults.set(normalized, forKey: debugModeKey)
        if normalized != CanonicalKernelSwitchMode.canonicalFullSync.rawValue {
            userDefaults.set(false, forKey: debugFullSyncConfirmedKey)
        }
        if postNotification {
            NotificationCenter.default.post(name: didChangeNotificationName, object: nil)
        }
    }

    nonisolated static func setDebugFullSyncConfirmed(
        _ confirmed: Bool,
        userDefaults: UserDefaults = .standard,
        postNotification: Bool = true
    ) {
        userDefaults.set(confirmed, forKey: debugFullSyncConfirmedKey)
        if postNotification {
            NotificationCenter.default.post(name: didChangeNotificationName, object: nil)
        }
    }

    nonisolated func resolve(
        reversibilityGate: CanonicalKernelSwitchReversibilityGate = CanonicalKernelSwitchReversibilityGate()
    ) -> CanonicalKernelSwitchResult {
        let proof = reversibilityGate.prove(policy: policy)
        var blockers = proof.blockers

        if mode == .blocked {
            blockers.append(.explicitBlockedMode)
        }
        if !policy.legacyFallbackAvailable {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !policy.diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if (mode == .canonicalShadow || mode == .canonicalFullSync) && !policy.shadowComparisonEnabled {
            blockers.append(.shadowCompareCannotStayEnabledWithCanonicalOwner)
        }
        if !policy.routeSecurityUnchanged {
            blockers.append(.routeSecurityRisk)
        }
        if !policy.productionRootConfigurationSafe {
            blockers.append(.unsafeProductionRootConfiguration)
        }
        if policy.unresolvedConflictBlocker {
            blockers.append(.unresolvedConflict)
        }
        if policy.switchBackHardBlocker {
            blockers.append(.switchBackHardBlocker)
        }
        if policy.canonicalOnlyDiskFormatBlocker {
            blockers.append(.canonicalOnlyDiskFormatBlocker)
        }

        let base = makeEffectiveConfiguration(mode: mode, proof: proof, applyingOverrides: false)
        blockers.append(contentsOf: advancedOverrideBlockers(base: base))
        let effectiveConfiguration = makeEffectiveConfiguration(mode: mode, proof: proof, applyingOverrides: true)

        let uniqueBlockers = Self.unique(blockers)
        if !uniqueBlockers.isEmpty {
            let blockedConfiguration = CanonicalKernelSwitchEffectiveConfiguration.blocked(policy: policy, proof: proof)
            let gateResult = CanonicalKernelSwitchGateResult(
                state: CanonicalKernelSwitchGate.state(for: uniqueBlockers),
                blockers: uniqueBlockers
            )
            let diagnostics = Self.diagnostics(
                requestedMode: mode,
                effectiveMode: .blocked,
                configuration: blockedConfiguration,
                blockers: uniqueBlockers
            )
            return CanonicalKernelSwitchResult(
                requestedMode: mode,
                effectiveMode: .blocked,
                ownerState: .blocked,
                blockers: uniqueBlockers,
                effectiveConfiguration: blockedConfiguration,
                reversibilityProof: proof,
                gateResult: gateResult,
                diagnostics: diagnostics,
                diagnosticsSummary: Self.diagnosticsSummary(
                    requestedMode: mode,
                    effectiveMode: .blocked,
                    ownerState: .blocked,
                    configuration: blockedConfiguration,
                    blockers: uniqueBlockers
                ),
                redacted: policy.diagnosticsRedacted
            )
        }

        let gateResult = CanonicalKernelSwitchGateResult(state: .allowed, blockers: [])
        let diagnostics = Self.diagnostics(
            requestedMode: mode,
            effectiveMode: mode,
            configuration: effectiveConfiguration,
            blockers: []
        )
        return CanonicalKernelSwitchResult(
            requestedMode: mode,
            effectiveMode: mode,
            ownerState: ownerState(for: mode),
            blockers: [],
            effectiveConfiguration: effectiveConfiguration,
            reversibilityProof: proof,
            gateResult: gateResult,
            diagnostics: diagnostics,
            diagnosticsSummary: Self.diagnosticsSummary(
                requestedMode: mode,
                effectiveMode: mode,
                ownerState: ownerState(for: mode),
                configuration: effectiveConfiguration,
                blockers: []
            ),
            redacted: policy.diagnosticsRedacted
        )
    }

    nonisolated private func makeEffectiveConfiguration(
        mode: CanonicalKernelSwitchMode,
        proof: CanonicalKernelSwitchReversibilityProof,
        applyingOverrides: Bool
    ) -> CanonicalKernelSwitchEffectiveConfiguration {
        let inventory = CanonicalInventoryRuntimeConfiguration(redactedDiagnostics: policy.diagnosticsRedacted)
        let connectionPolicy = canonicalConnectionPolicy()
        let syncPolicy = canonicalSyncPolicy()
        let applyPolicy = canonicalApplyPolicy()
        let existencePolicy = canonicalExistencePolicy()
        let transferPolicy = canonicalTransferPolicy()
        let audioPolicy = canonicalAudioPolicy()
        let readPolicy = canonicalReadPolicy()

        let connection: CanonicalConnectionRuntimeConfiguration
        let sync: CanonicalSyncRuntimeConfiguration
        let apply: CanonicalApplyRuntimeConfiguration
        let existence: CanonicalExistenceApplyRuntimeConfiguration
        let transfer: CanonicalTransferRuntimeConfiguration
        let audio: CanonicalAudioUploadRuntimeConfiguration
        let read: CanonicalReadRuntimeConfiguration
        let libraryPilot: CanonicalLibraryMetadataDebugPilotConfiguration
        let activeDomains: [CanonicalMigrationDomain]

        switch mode {
        case .oldKernel:
            connection = .disabled
            sync = .disabled
            apply = .disabled
            existence = .disabled
            transfer = .disabled
            audio = .disabled
            read = .disabled
            libraryPilot = .disabled
            activeDomains = []
        case .diagnosticsOnly:
            connection = CanonicalConnectionRuntimeConfiguration(mode: .diagnosticsOnly, policy: connectionPolicy)
            sync = CanonicalSyncRuntimeConfiguration(mode: .diagnosticsOnly, policy: syncPolicy)
            apply = CanonicalApplyRuntimeConfiguration(mode: .diagnosticsOnly, policy: applyPolicy)
            existence = CanonicalExistenceApplyRuntimeConfiguration(mode: .diagnosticsOnly, policy: existencePolicy)
            transfer = CanonicalTransferRuntimeConfiguration(mode: .diagnosticsOnly, policy: transferPolicy)
            audio = CanonicalAudioUploadRuntimeConfiguration(mode: .diagnosticsOnly, policy: audioPolicy)
            read = .disabled
            libraryPilot = .diagnosticsOnly()
            activeDomains = []
        case .canonicalShadow:
            connection = CanonicalConnectionRuntimeConfiguration(mode: .diagnosticsOnly, policy: connectionPolicy)
            sync = CanonicalSyncRuntimeConfiguration(mode: .canonicalPlanNoCommit, policy: syncPolicy)
            apply = CanonicalApplyRuntimeConfiguration(mode: .noCommit, policy: applyPolicy)
            existence = CanonicalExistenceApplyRuntimeConfiguration(mode: .noCommit, policy: existencePolicy)
            transfer = CanonicalTransferRuntimeConfiguration(mode: .diagnosticsOnly, policy: transferPolicy)
            audio = CanonicalAudioUploadRuntimeConfiguration(mode: .noCommit, policy: audioPolicy)
            read = CanonicalReadRuntimeConfiguration(mode: policy.shadowComparisonEnabled ? .parallelCompare : .disabled, policy: readPolicy)
            libraryPilot = .disabled
            activeDomains = []
        case .canonicalDecisionOnly:
            connection = CanonicalConnectionRuntimeConfiguration(mode: .diagnosticsOnly, policy: connectionPolicy)
            sync = CanonicalSyncRuntimeConfiguration(mode: .canonicalPlanPrimaryWithLegacyFallback, policy: syncPolicy)
            apply = .disabled
            existence = .disabled
            transfer = CanonicalTransferRuntimeConfiguration(mode: .noCommit, policy: transferPolicy)
            audio = .disabled
            read = .disabled
            libraryPilot = .disabled
            activeDomains = []
        case .canonicalApplyNoAudio:
            connection = CanonicalConnectionRuntimeConfiguration(mode: .diagnosticsOnly, policy: connectionPolicy)
            sync = CanonicalSyncRuntimeConfiguration(mode: .canonicalPlanPrimaryWithLegacyFallback, policy: syncPolicy)
            apply = CanonicalApplyRuntimeConfiguration(mode: .productionRootApplyWithLegacyFallback, policy: applyPolicy)
            existence = CanonicalExistenceApplyRuntimeConfiguration(mode: .productionRootApply, policy: existencePolicy)
            transfer = CanonicalTransferRuntimeConfiguration(mode: .blocked, policy: transferPolicy)
            audio = .disabled
            read = .disabled
            libraryPilot = .disabled
            activeDomains = [.recordingMetadata, .generatedArtifacts, .libraryMetadata, .tombstoneConflict]
        case .canonicalFullSync:
            connection = CanonicalConnectionRuntimeConfiguration(mode: .connectionOwnerWithLegacyFallback, policy: connectionPolicy)
            sync = CanonicalSyncRuntimeConfiguration(mode: .canonicalPlanPrimaryWithLegacyFallback, policy: syncPolicy)
            apply = CanonicalApplyRuntimeConfiguration(mode: .productionRootApplyWithLegacyFallback, policy: applyPolicy)
            existence = CanonicalExistenceApplyRuntimeConfiguration(mode: .productionRootApply, policy: existencePolicy)
            transfer = CanonicalTransferRuntimeConfiguration(mode: .canonicalTransferWithLegacyFallback, policy: transferPolicy)
            audio = CanonicalAudioUploadRuntimeConfiguration(mode: .canonicalUploadWithLegacyFallback, policy: audioPolicy)
            read = CanonicalReadRuntimeConfiguration(mode: .guardedCanonicalReadWithLegacyFallback, policy: readPolicy)
            libraryPilot = .disabled
            activeDomains = [.recordingMetadata, .generatedArtifacts, .libraryMetadata, .tombstoneConflict, .audioUpload, .uiProjection]
        case .blocked:
            connection = CanonicalConnectionRuntimeConfiguration(mode: .blocked)
            sync = CanonicalSyncRuntimeConfiguration(mode: .blocked)
            apply = CanonicalApplyRuntimeConfiguration(mode: .blocked)
            existence = CanonicalExistenceApplyRuntimeConfiguration(mode: .blocked)
            transfer = CanonicalTransferRuntimeConfiguration(mode: .blocked)
            audio = CanonicalAudioUploadRuntimeConfiguration(mode: .blocked)
            read = CanonicalReadRuntimeConfiguration(mode: .blocked)
            libraryPilot = CanonicalLibraryMetadataDebugPilotConfiguration(mode: .blocked)
            activeDomains = []
        }

        return CanonicalKernelSwitchEffectiveConfiguration(
            connectionRuntimeConfiguration: applyingOverrides ? (advancedOverrides.connectionRuntimeConfiguration ?? connection) : connection,
            inventoryRuntimeConfiguration: inventory,
            syncRuntimeConfiguration: applyingOverrides ? (advancedOverrides.syncRuntimeConfiguration ?? sync) : sync,
            applyRuntimeConfiguration: applyingOverrides ? (advancedOverrides.applyRuntimeConfiguration ?? apply) : apply,
            existenceApplyRuntimeConfiguration: applyingOverrides ? (advancedOverrides.existenceApplyRuntimeConfiguration ?? existence) : existence,
            transferRuntimeConfiguration: applyingOverrides ? (advancedOverrides.transferRuntimeConfiguration ?? transfer) : transfer,
            audioUploadRuntimeConfiguration: applyingOverrides ? (advancedOverrides.audioUploadRuntimeConfiguration ?? audio) : audio,
            readRuntimeConfiguration: applyingOverrides ? (advancedOverrides.readRuntimeConfiguration ?? read) : read,
            libraryMetadataDebugPilotConfiguration: applyingOverrides ? (advancedOverrides.libraryMetadataDebugPilotConfiguration ?? libraryPilot) : libraryPilot,
            migrationMatrixPolicy: .make(
                mode: mode,
                ownerState: ownerState(for: mode),
                activeCanonicalOwnershipDomains: activeDomains,
                policy: policy,
                proof: proof
            )
        )
    }

    nonisolated private func canonicalConnectionPolicy() -> CanonicalConnectionRuntimePolicy {
        CanonicalConnectionRuntimePolicy(
            debugInternalBuild: policy.debugInternalBuild,
            ownerApprovedCanonicalConnection: policy.ownerApproved,
            defaultReleaseOldKernel: policy.releaseDefaultBuild,
            legacyFallbackEnabled: policy.legacyFallbackAvailable,
            requireExistingCarrierRoutes: true,
            heartbeatCallbackEnqueueOnly: true,
            statusExchangeCarrierEnabled: true,
            macReverseConnectionAllowed: false
        )
    }

    nonisolated private func canonicalSyncPolicy() -> CanonicalSyncRuntimePolicy {
        CanonicalSyncRuntimePolicy(
            debugInternalBuild: policy.debugInternalBuild,
            ownerApproved: policy.ownerApproved,
            releaseDefaultBuild: policy.releaseDefaultBuild,
            legacyFallbackAvailable: policy.legacyFallbackAvailable,
            diagnosticsRedacted: policy.diagnosticsRedacted,
            runtimeSwitchEnabled: false,
            readPathLegacy: true,
            otherActiveMigrationDomainConflicting: false,
            allowDocumentedModifiedAtFallback: true,
            enabledScopes: [.recordingMetadata, .libraryMetadata, .generatedArtifacts, .tombstoneConflict, .audioUpload, .recordingExistence]
        )
    }

    nonisolated private func canonicalApplyPolicy() -> CanonicalApplyRuntimePolicy {
        CanonicalApplyRuntimePolicy(
            debugInternalBuild: policy.debugInternalBuild,
            ownerApproved: policy.ownerApproved,
            releaseDefaultBuild: policy.releaseDefaultBuild,
            legacyFallbackAvailable: policy.legacyFallbackAvailable,
            diagnosticsRedacted: policy.diagnosticsRedacted,
            runtimeSwitchEnabled: false,
            readPathLegacy: true,
            enabledDomains: [.recordingMetadata, .libraryMetadata, .generatedArtifacts, .tombstoneConflict, .recordingExistence],
            allowConflictRecordAction: true,
            allowTestRootApply: false
        )
    }

    nonisolated private func canonicalExistencePolicy() -> CanonicalExistenceApplyRuntimePolicy {
        CanonicalExistenceApplyRuntimePolicy(
            debugInternalBuild: policy.debugInternalBuild,
            ownerApproved: policy.ownerApproved,
            releaseDefaultBuild: policy.releaseDefaultBuild,
            diagnosticsRedacted: policy.diagnosticsRedacted,
            legacyFallbackAvailable: policy.legacyFallbackAvailable,
            rootBoundRequired: true,
            rollbackRequired: true,
            atomicWriteRequired: true,
            postconditionRequired: true,
            writeAudioAllowed: false,
            markAudioAvailableAllowed: false
        )
    }

    nonisolated private func canonicalTransferPolicy() -> CanonicalTransferRuntimePolicy {
        CanonicalTransferRuntimePolicy(
            debugInternalBuild: policy.debugInternalBuild,
            ownerApprovedCanonicalTransfer: policy.ownerApproved,
            defaultReleaseOldKernel: policy.releaseDefaultBuild,
            legacyFallbackEnabled: policy.legacyFallbackAvailable,
            requireExistingSecureUploadRoutes: true,
            retryDrainerRequiresExistingJob: true,
            chunkSize: 4 * 1024 * 1024,
            retryPolicy: CanonicalTransferRetryRuntimePolicy()
        )
    }

    nonisolated private func canonicalAudioPolicy() -> CanonicalAudioUploadRuntimePolicy {
        CanonicalAudioUploadRuntimePolicy(
            debugInternalBuild: policy.debugInternalBuild,
            ownerApprovedCanonicalCommit: policy.ownerApproved,
            allowTestTransportUpload: false,
            allowCanonicalUploadWithLegacyFallback: policy.debugInternalBuild
                && policy.ownerApproved
                && !policy.releaseDefaultBuild
                && policy.manualFullSyncConfirmation,
            legacyFallbackEnabled: policy.legacyFallbackAvailable,
            requireExistingSecureUploadRoutes: true,
            retryDrainerRequiresExistingRetry: true
        )
    }

    nonisolated private func canonicalReadPolicy() -> CanonicalReadRuntimePolicy {
        CanonicalReadRuntimePolicy(
            debugInternalBuild: policy.debugInternalBuild,
            ownerApproved: policy.ownerApproved,
            manualOwnerApproval: policy.manualFullSyncConfirmation,
            releaseDefaultBuild: policy.releaseDefaultBuild,
            legacyFallbackAvailable: policy.legacyFallbackAvailable,
            diagnosticsRedacted: policy.diagnosticsRedacted,
            applyRuntimeEvidenceValidForNonAudio: true,
            uploadRuntimeEvidenceValidForAudioStatus: true,
            inventorySnapshotAvailable: true,
            planAuthorityEvidenceValid: true,
            existenceTruthEvidenceValid: true,
            otherDomainsNotConflicting: true,
            readMustNotTriggerSyncUpload: true,
            readMustNotMutateStore: true
        )
    }

    nonisolated private func advancedOverrideBlockers(
        base: CanonicalKernelSwitchEffectiveConfiguration
    ) -> [CanonicalKernelSwitchBlocker] {
        var blockers: [CanonicalKernelSwitchBlocker] = []
        if let override = advancedOverrides.connectionRuntimeConfiguration,
           !Self.connectionOverrideAllowed(override, base: base.connectionRuntimeConfiguration) {
            blockers.append(.advancedOverrideContradictsMasterSwitch)
        }
        if let override = advancedOverrides.syncRuntimeConfiguration,
           !Self.syncOverrideAllowed(override, base: base.syncRuntimeConfiguration) {
            blockers.append(.advancedOverrideContradictsMasterSwitch)
        }
        if let override = advancedOverrides.applyRuntimeConfiguration,
           !Self.applyOverrideAllowed(override, base: base.applyRuntimeConfiguration) {
            blockers.append(.advancedOverrideContradictsMasterSwitch)
        }
        if let override = advancedOverrides.existenceApplyRuntimeConfiguration,
           !Self.existenceOverrideAllowed(override, base: base.existenceApplyRuntimeConfiguration) {
            blockers.append(.advancedOverrideContradictsMasterSwitch)
        }
        if let override = advancedOverrides.transferRuntimeConfiguration,
           !Self.transferOverrideAllowed(override, base: base.transferRuntimeConfiguration) {
            blockers.append(.advancedOverrideContradictsMasterSwitch)
        }
        if let override = advancedOverrides.audioUploadRuntimeConfiguration,
           !Self.audioOverrideAllowed(override, base: base.audioUploadRuntimeConfiguration) {
            blockers.append(.advancedOverrideContradictsMasterSwitch)
        }
        if let override = advancedOverrides.readRuntimeConfiguration,
           !Self.readOverrideAllowed(override, base: base.readRuntimeConfiguration) {
            blockers.append(.advancedOverrideContradictsMasterSwitch)
        }
        if let override = advancedOverrides.libraryMetadataDebugPilotConfiguration,
           !Self.libraryPilotOverrideAllowed(override, base: base.libraryMetadataDebugPilotConfiguration) {
            blockers.append(.advancedOverrideContradictsMasterSwitch)
        }
        return blockers
    }

    private nonisolated static func connectionOverrideAllowed(
        _ override: CanonicalConnectionRuntimeConfiguration,
        base: CanonicalConnectionRuntimeConfiguration
    ) -> Bool {
        connectionRank(override.mode) <= connectionRank(base.mode)
            && override.policy.legacyFallbackEnabled
            && override.policy.requireExistingCarrierRoutes
            && override.policy.heartbeatCallbackEnqueueOnly
            && override.policy.statusExchangeCarrierEnabled
            && !override.policy.macReverseConnectionAllowed
            && (!override.mode.ownsCarrierState || (override.policy.debugInternalBuild && override.policy.ownerApprovedCanonicalConnection))
    }

    private nonisolated static func syncOverrideAllowed(
        _ override: CanonicalSyncRuntimeConfiguration,
        base: CanonicalSyncRuntimeConfiguration
    ) -> Bool {
        guard syncRank(override.mode) <= syncRank(base.mode) else {
            return false
        }
        guard safeSyncPolicy(override.policy) else {
            return false
        }
        let baseScopes = Set(base.policy.enabledScopes)
        let overrideScopes = Set(override.policy.enabledScopes)
        return overrideScopes.isSubset(of: baseScopes)
    }

    private nonisolated static func applyOverrideAllowed(
        _ override: CanonicalApplyRuntimeConfiguration,
        base: CanonicalApplyRuntimeConfiguration
    ) -> Bool {
        guard applyRank(override.mode) <= applyRank(base.mode),
              safeApplyPolicy(override.policy) else {
            return false
        }
        let baseDomains = Set(base.policy.enabledDomains)
        let overrideDomains = Set(override.policy.enabledDomains)
        return overrideDomains.isSubset(of: baseDomains)
    }

    private nonisolated static func existenceOverrideAllowed(
        _ override: CanonicalExistenceApplyRuntimeConfiguration,
        base: CanonicalExistenceApplyRuntimeConfiguration
    ) -> Bool {
        existenceRank(override.mode) <= existenceRank(base.mode)
            && override.policy.diagnosticsRedacted
            && override.policy.legacyFallbackAvailable
            && override.policy.rootBoundRequired
            && override.policy.rollbackRequired
            && override.policy.atomicWriteRequired
            && override.policy.postconditionRequired
            && !override.policy.writeAudioAllowed
            && !override.policy.markAudioAvailableAllowed
    }

    private nonisolated static func transferOverrideAllowed(
        _ override: CanonicalTransferRuntimeConfiguration,
        base: CanonicalTransferRuntimeConfiguration
    ) -> Bool {
        transferRank(override.mode) <= transferRank(base.mode)
            && override.policy.legacyFallbackEnabled
            && override.policy.requireExistingSecureUploadRoutes
            && override.policy.retryDrainerRequiresExistingJob
            && (!override.mode.createsTransferJob || (override.policy.debugInternalBuild && override.policy.ownerApprovedCanonicalTransfer))
    }

    private nonisolated static func audioOverrideAllowed(
        _ override: CanonicalAudioUploadRuntimeConfiguration,
        base: CanonicalAudioUploadRuntimeConfiguration
    ) -> Bool {
        audioRank(override.mode) <= audioRank(base.mode)
            && override.policy.legacyFallbackEnabled
            && override.policy.requireExistingSecureUploadRoutes
            && override.policy.retryDrainerRequiresExistingRetry
            && (!override.mode.sendsNetworkOrTransport || (override.policy.debugInternalBuild && override.policy.ownerApprovedCanonicalCommit))
    }

    private nonisolated static func readOverrideAllowed(
        _ override: CanonicalReadRuntimeConfiguration,
        base: CanonicalReadRuntimeConfiguration
    ) -> Bool {
        readRank(override.mode) <= readRank(base.mode)
            && override.policy.legacyFallbackAvailable
            && override.policy.diagnosticsRedacted
            && override.policy.readMustNotTriggerSyncUpload
            && override.policy.readMustNotMutateStore
            && (!override.mode.buildsCanonicalCandidate || !override.policy.releaseDefaultBuild)
    }

    private nonisolated static func libraryPilotOverrideAllowed(
        _ override: CanonicalLibraryMetadataDebugPilotConfiguration,
        base: CanonicalLibraryMetadataDebugPilotConfiguration
    ) -> Bool {
        guard libraryPilotRank(override.mode) <= libraryPilotRank(base.mode) else {
            return false
        }
        if override.rootMode == .productionRootExplicit || override.allowProductionRootWrites {
            return base.rootMode == .productionRootExplicit
                && base.allowProductionRootWrites
                && override.rootMode == base.rootMode
        }
        return true
    }

    private nonisolated static func safeSyncPolicy(_ policy: CanonicalSyncRuntimePolicy) -> Bool {
        policy.legacyFallbackAvailable
            && policy.diagnosticsRedacted
            && !policy.runtimeSwitchEnabled
            && policy.readPathLegacy
            && !policy.otherActiveMigrationDomainConflicting
            && (!policy.releaseDefaultBuild || !policy.ownerApproved)
    }

    private nonisolated static func safeApplyPolicy(_ policy: CanonicalApplyRuntimePolicy) -> Bool {
        policy.legacyFallbackAvailable
            && policy.diagnosticsRedacted
            && !policy.runtimeSwitchEnabled
            && policy.readPathLegacy
            && !policy.enabledDomains.contains(.audioUpload)
    }

    private nonisolated static func connectionRank(_ mode: CanonicalConnectionRuntimeMode) -> Int {
        switch mode {
        case .blocked, .disabled: return 0
        case .diagnosticsOnly: return 1
        case .connectionOwnerWithLegacyFallback: return 3
        }
    }

    private nonisolated static func syncRank(_ mode: CanonicalSyncRuntimeMode) -> Int {
        switch mode {
        case .blocked, .disabled: return 0
        case .diagnosticsOnly: return 1
        case .canonicalPlanNoCommit: return 2
        case .canonicalPlanPrimaryWithLegacyFallback: return 3
        }
    }

    private nonisolated static func applyRank(_ mode: CanonicalApplyRuntimeMode) -> Int {
        switch mode {
        case .blocked, .disabled: return 0
        case .diagnosticsOnly: return 1
        case .noCommit: return 2
        case .testRootApply, .productionRootApplyWithLegacyFallback: return 3
        }
    }

    private nonisolated static func existenceRank(_ mode: CanonicalExistenceApplyRuntimeMode) -> Int {
        switch mode {
        case .blocked, .disabled: return 0
        case .diagnosticsOnly: return 1
        case .noCommit: return 2
        case .metadataOnlyBridge, .testRootApply, .productionRootApply: return 3
        }
    }

    private nonisolated static func transferRank(_ mode: CanonicalTransferRuntimeMode) -> Int {
        switch mode {
        case .blocked, .disabled: return 0
        case .diagnosticsOnly: return 1
        case .noCommit: return 2
        case .canonicalTransferWithLegacyFallback: return 3
        }
    }

    private nonisolated static func audioRank(_ mode: CanonicalAudioUploadRuntimeMode) -> Int {
        switch mode {
        case .blocked, .disabled: return 0
        case .diagnosticsOnly: return 1
        case .noCommit: return 2
        case .testTransportUpload, .canonicalUploadWithLegacyFallback: return 3
        }
    }

    private nonisolated static func readRank(_ mode: CanonicalReadRuntimeMode) -> Int {
        switch mode {
        case .blocked, .disabled: return 0
        case .parallelCompare: return 1
        case .canonicalReadCandidate: return 2
        case .guardedCanonicalReadWithLegacyFallback: return 3
        }
    }

    private nonisolated static func libraryPilotRank(_ mode: CanonicalLibraryMetadataDebugPilotMode) -> Int {
        switch mode {
        case .blocked, .disabled: return 0
        case .diagnosticsOnly: return 1
        case .armN1Canary: return 2
        case .executeN1Canary: return 3
        }
    }

    nonisolated private func ownerState(for mode: CanonicalKernelSwitchMode) -> CanonicalKernelSwitchOwnerState {
        switch mode {
        case .oldKernel:
            return .oldKernel
        case .diagnosticsOnly, .canonicalDecisionOnly:
            return .canonicalNoWrite
        case .canonicalShadow:
            return .shadow
        case .canonicalApplyNoAudio, .canonicalFullSync:
            return .canonicalReadWrite
        case .blocked:
            return .blocked
        }
    }

    nonisolated private static func unique(_ blockers: [CanonicalKernelSwitchBlocker]) -> [CanonicalKernelSwitchBlocker] {
        var seen: Set<CanonicalKernelSwitchBlocker> = []
        var unique: [CanonicalKernelSwitchBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }

    nonisolated private static func diagnosticsSummary(
        requestedMode: CanonicalKernelSwitchMode,
        effectiveMode: CanonicalKernelSwitchMode,
        ownerState: CanonicalKernelSwitchOwnerState,
        configuration: CanonicalKernelSwitchEffectiveConfiguration,
        blockers: [CanonicalKernelSwitchBlocker]
    ) -> String {
        [
            "canonicalKernelSwitch=v9.8",
            "requested=\(requestedMode.rawValue)",
            "effective=\(effectiveMode.rawValue)",
            "ownerState=\(ownerState.rawValue)",
            "connection=\(configuration.connectionRuntimeConfiguration.mode.rawValue)",
            "sync=\(configuration.syncRuntimeConfiguration.mode.rawValue)",
            "apply=\(configuration.applyRuntimeConfiguration.mode.rawValue)",
            "existence=\(configuration.existenceApplyRuntimeConfiguration.mode.rawValue)",
            "transfer=\(configuration.transferRuntimeConfiguration.mode.rawValue)",
            "audio=\(configuration.audioUploadRuntimeConfiguration.mode.rawValue)",
            "read=\(configuration.readRuntimeConfiguration.mode.rawValue)",
            "libraryMetadataPilot=\(configuration.libraryMetadataDebugPilotConfiguration.mode.rawValue)",
            "diskFormat=\(configuration.migrationMatrixPolicy.diskFormatPolicy)",
            "switchBackMigration=\(configuration.migrationMatrixPolicy.migrationRequiredToSwitchBack)",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated private static func diagnostics(
        requestedMode: CanonicalKernelSwitchMode,
        effectiveMode: CanonicalKernelSwitchMode,
        configuration: CanonicalKernelSwitchEffectiveConfiguration,
        blockers: [CanonicalKernelSwitchBlocker]
    ) -> [CanonicalKernelSwitchDiagnostic] {
        var diagnostics = [
            CanonicalKernelSwitchDiagnostic(
                kind: .canonicalKernelSwitchModeEvaluated,
                mode: requestedMode,
                detail: "effective=\(effectiveMode.rawValue)"
            ),
            CanonicalKernelSwitchDiagnostic(
                kind: .canonicalKernelSwitchEffectiveConfigBuilt,
                mode: effectiveMode,
                detail: [
                    "connection=\(configuration.connectionRuntimeConfiguration.mode.rawValue)",
                    "sync=\(configuration.syncRuntimeConfiguration.mode.rawValue)",
                    "apply=\(configuration.applyRuntimeConfiguration.mode.rawValue)",
                    "existence=\(configuration.existenceApplyRuntimeConfiguration.mode.rawValue)",
                    "transfer=\(configuration.transferRuntimeConfiguration.mode.rawValue)",
                    "audio=\(configuration.audioUploadRuntimeConfiguration.mode.rawValue)",
                    "read=\(configuration.readRuntimeConfiguration.mode.rawValue)"
                ].joined(separator: ";")
            ),
            CanonicalKernelSwitchDiagnostic(
                kind: blockers.isEmpty ? .canonicalKernelSwitchGateAllowed : .canonicalKernelSwitchGateBlocked,
                mode: effectiveMode,
                blocker: blockers.first,
                detail: Self.nonEmpty(blockers.map(\.rawValue).joined(separator: "|")) ?? "none"
            ),
            CanonicalKernelSwitchDiagnostic(
                kind: .canonicalKernelSwitchFallbackPreserved,
                mode: effectiveMode,
                detail: "legacyFallback=true"
            )
        ]
        switch requestedMode {
        case .oldKernel:
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchOldKernelSelected, mode: requestedMode))
        case .diagnosticsOnly:
            break
        case .canonicalShadow:
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchCanonicalShadowSelected, mode: requestedMode))
        case .canonicalDecisionOnly:
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchCanonicalDecisionOnlySelected, mode: requestedMode))
        case .canonicalApplyNoAudio:
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchCanonicalApplyNoAudioSelected, mode: requestedMode))
        case .canonicalFullSync:
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchCanonicalFullSyncRequested, mode: requestedMode))
            diagnostics.append(
                CanonicalKernelSwitchDiagnostic(
                    kind: blockers.isEmpty ? .canonicalKernelSwitchCanonicalFullSyncAllowed : .canonicalKernelSwitchCanonicalFullSyncBlocked,
                    mode: effectiveMode,
                    blocker: blockers.first
                )
            )
        case .blocked:
            break
        }
        if blockers.contains(.advancedOverrideContradictsMasterSwitch) {
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchContradictoryConfigBlocked, mode: requestedMode))
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchSpecializedConfigBypassBlocked, mode: requestedMode))
        }
        if blockers.contains(.releaseDefaultCannotUseCanonicalFullSync) {
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchReleaseDefaultBlocked, mode: requestedMode))
        }
        if blockers.contains(where: { blocker in
            switch blocker {
            case .connectionRuntimeReadinessMissing,
                 .inventoryRuntimeReadinessMissing,
                 .syncDecisionRuntimeReadinessMissing,
                 .nonAudioApplyRuntimeReadinessMissing,
                 .transferRuntimeReadinessMissing,
                 .audioUploadRuntimeReadinessMissing,
                 .readRuntimeReadinessMissing,
                 .recordingMetadataReadinessMissing,
                 .libraryMetadataReadinessMissing,
                 .generatedArtifactsReadinessMissing,
                 .tombstoneConflictReadinessMissing,
                 .audioUploadReadinessMissing:
                return true
            default:
                return false
            }
        }) {
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchReadinessMissing, mode: requestedMode))
        }
        if configuration.libraryMetadataDebugPilotConfiguration.mode != .disabled {
            diagnostics.append(CanonicalKernelSwitchDiagnostic(kind: .canonicalKernelSwitchSpecializedConfigRestricted, mode: effectiveMode))
        }
        return diagnostics
    }

    private nonisolated static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
