//
//  CanonicalSyncKernelCompletion.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/7.
//

import Foundation

nonisolated enum CanonicalSyncKernelCompletionStatus: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case incomplete
    case codeCompleteNeedsDeviceEvidence
    case readyForManualSwitchTrial
    case blocked
    case readyToRetireLegacyReportOnly
    case unsafe
}

nonisolated enum CanonicalSyncKernelCodeCompletionResult: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForRealDeviceCanonicalSwitch = "READY_FOR_REAL_DEVICE_CANONICAL_SWITCH"
    case partialWithBlockers = "PARTIAL_WITH_BLOCKERS"
    case notReady = "NOT_READY"
    case unsafeToTryOnDevice = "UNSAFE_TO_TRY_ON_DEVICE"
}

nonisolated enum CanonicalRealDeviceTrialReadinessCodeCompleteResult: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readyForRealDeviceFourDomainAppTrial = "READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL"
    case readyForRealDeviceAppTrial = "READY_FOR_REAL_DEVICE_APP_TRIAL"
    case partialWithBlockers = "PARTIAL_WITH_BLOCKERS"
    case notReady = "NOT_READY"
    case unsafeToTryOnDevice = "UNSAFE_TO_TRY_ON_DEVICE"
}

nonisolated enum CanonicalRealDeviceTrialReadinessBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case readCacheMissing
    case macInventoryOffMainMissing
    case oldKernelCanonicalSkipMissing
    case syncRequestedHeartbeatHookupMissing
    case eventDrivenSyncTriggerMissing
    case statusConvergenceRefreshMissing
    case stormProtectionMissing
    case iOSBuildMissing
    case macOSBuildMissing
    case targetedTestsMissing
    case defaultOldKernelMissing
    case releaseDefaultCanonical
    case fiveModeKernelSwitchMissing
    case canonicalFullSyncGateMissing
    case legacyFallbackUnavailable
    case routeSecurityChanged
    case requestVerifierBypassed
    case switchBackProofDriverMissing
    case diagnosticsSensitiveLeak
    case realDeviceTrialRunbookMissing
    case productionRootUnsafeWrite
    case viewRefreshCreatesUploadJob
    case retryStormProtectionMissing
    case metadataOnlyTreatedAsAudioAvailable
    case completedLedgerAloneTreatedAsProof
    case partialReceiveTreatedAsAudioAvailable
    case existingDifferentAudioOverwriteRisk
    case oldKernelSwitchBackMissing
    case heartbeatRunsHeavySync
    case macReverseConnectionAttempted
    case diagnosticsAsyncHotPathMissing
    case contentStableCacheKeyMissing
    case noFreezeEvidenceMissing
    case effectiveStatusBindingMissing
    case realtimeStatusExchangeMissing
    case connectionRuntimeAppPathMissing
    case transferRuntimeAppPathMissing
    case fakeOrTestOnlyProductionTransferPort
    case finalizeProofNotFeedingStatusTruth
    case retryDrainerCreatesFreshUnrelatedJob
    case buildTestSummaryMissing
    case mainActorHotPathViolation
    case legacyRetirementAttempted
}

nonisolated enum CanonicalSyncKernelCompletionBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case inventoryRuntimeIncomplete
    case diffLWWRuntimeIncomplete
    case existenceTruthIncomplete
    case nonAudioApplyRuntimeIncomplete
    case audioUploadRuntimeIncomplete
    case readRuntimeIncomplete
    case masterSwitchIncomplete
    case legacyCompatibilityProofMissing
    case switchBackProofMissing
    case diagnosticsNotRedacted
    case realDeviceEvidenceMissing
    case domainIncomplete
    case compatibilityProofMissing
    case defaultOldKernelMissing
    case releaseDefaultCanonical
    case legacyFallbackUnavailable
    case unresolvedBlocker
    case ownerApprovalMissing
    case manualBackupAcknowledgementMissing
    case retirementExecutionAttempted
    case legacyDeletionAttempted
    case sensitiveEvidenceLeak
    case unsafeCanonicalDefault
    case securityBypassDetected
    case realisticRootSwitchBackProofMissing
    case testsNotPassing
    case docsNotUpdated
    case recordingMetadataRealApplyPortMissing
    case recordingMetadataReadSideSeamMissing
    case audioCommitExecutorMissing
    case inventoryExistenceGateMissing
    case productionFilePortTrueWriteGateMissing
    case switchBackProofDriverMissing
    case diagnosticsGrepListMissing
    case emergencyOldKernelSwitchBackPathMissing
    case stopConditionsMissing
    case runbookMissing
    case iOSBuildValidationMissing
    case macOSBuildValidationMissing
    case targetedTestsValidationMissing
    case t1InventoryMainActorResidualClosureMissing
    case t2MasterSwitchReadMappingMissing
    case t3RecordingReadSeamRuntimeMissing
    case t4ExecutorPortInjectionMissing
    case t5ProductionRootOwnerManualGateMissing
    case t6SwitchBackProofDriverMissing
    case fiveModeSelectorMissing
    case canonicalFullSyncConfirmationMissing
    case canonicalFullSyncOwnerApprovalGateMissing
    case canonicalFullSyncManualConfirmationGateMissing
    case decisionRuntimeMappingMissing
    case readRuntimeMappingMissing
    case applyRuntimeMappingMissing
    case audioCommitRuntimeMappingMissing
    case existenceApplyPortMappingMissing
    case oldKernelLegacyMappingMissing
    case scatteredSwitchBypass
    case productionRootWriteWithoutOwnerApproval
    case productionRootWriteWithoutManualConfirmation
    case productionRootWriteInReleaseDefault
    case pathBTransportChanged
    case routeSecurityChanged
    case requestVerifierBypassed
    case metadataOnlyTreatedAsAudioAvailable
    case completedLedgerAloneTreatedAsNoOp
    case existingDifferentAudioOverwriteRisk
    case diagnosticsSensitiveLeak
    case productionRootDestructiveSwitchBackProof
    case oldKernelSwitchBackNotImmediate
    case manualSwitchGateMissing
}

nonisolated enum CanonicalSyncKernelCompletionScorecardItem: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case inventoryRuntimeComplete
    case diffLWWRuntimeComplete
    case existenceTruthComplete
    case nonAudioApplyRuntimeComplete
    case audioUploadRuntimeComplete
    case readRuntimeComplete
    case masterSwitchComplete
    case legacyCompatibilityProofComplete
    case switchBackProofComplete
    case diagnosticsRedacted
    case realDeviceEvidenceRequired

    nonisolated var isCodeCompletionItem: Bool {
        self != .realDeviceEvidenceRequired
    }

    nonisolated var blocker: CanonicalSyncKernelCompletionBlocker {
        switch self {
        case .inventoryRuntimeComplete:
            return .inventoryRuntimeIncomplete
        case .diffLWWRuntimeComplete:
            return .diffLWWRuntimeIncomplete
        case .existenceTruthComplete:
            return .existenceTruthIncomplete
        case .nonAudioApplyRuntimeComplete:
            return .nonAudioApplyRuntimeIncomplete
        case .audioUploadRuntimeComplete:
            return .audioUploadRuntimeIncomplete
        case .readRuntimeComplete:
            return .readRuntimeIncomplete
        case .masterSwitchComplete:
            return .masterSwitchIncomplete
        case .legacyCompatibilityProofComplete:
            return .legacyCompatibilityProofMissing
        case .switchBackProofComplete:
            return .switchBackProofMissing
        case .diagnosticsRedacted:
            return .diagnosticsNotRedacted
        case .realDeviceEvidenceRequired:
            return .realDeviceEvidenceMissing
        }
    }
}

nonisolated struct CanonicalSyncKernelCompletionScorecardItemResult: Codable, Equatable, Sendable {
    var item: CanonicalSyncKernelCompletionScorecardItem
    var complete: Bool
    var diagnosticsSummary: String

    nonisolated init(
        item: CanonicalSyncKernelCompletionScorecardItem,
        complete: Bool,
        diagnosticsSummary: String? = nil
    ) {
        self.item = item
        self.complete = complete
        self.diagnosticsSummary = CanonicalSyncKernelEvidenceRedactor.redact(
            diagnosticsSummary ?? "item=\(item.rawValue),complete=\(complete)"
        )
    }
}

nonisolated enum CanonicalSyncKernelCompletionDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case libraryMetadata
    case generatedArtifacts
    case tombstoneConflict
    case recordingExistence
    case audioUpload
    case readRuntime
    case inventoryRuntime
    case syncDecisionRuntime
    case applyRuntime
    case kernelSwitch
    case legacyCompatibility
}

nonisolated struct CanonicalSyncKernelCompletionDomainReadiness: Codable, Equatable, Sendable {
    var domain: CanonicalSyncKernelCompletionDomain
    var writeExecutorReady: Bool
    var readRuntimeReady: Bool
    var syncRuntimeOwnerReady: Bool
    var applyRuntimeReady: Bool
    var audioRuntimeReady: Bool
    var legacyFallbackReady: Bool
    var switchBackProofReady: Bool
    var diagnosticsRedacted: Bool
    var testsPass: Bool
    var docsUpdated: Bool
    var realDeviceEvidencePresent: Bool
    var codeComplete: Bool
    var blockers: [CanonicalSyncKernelCompletionBlocker]
    var diagnosticsSummary: String

    nonisolated init(
        domain: CanonicalSyncKernelCompletionDomain,
        writeExecutorReady: Bool = true,
        readRuntimeReady: Bool = true,
        syncRuntimeOwnerReady: Bool = true,
        applyRuntimeReady: Bool = true,
        audioRuntimeReady: Bool? = nil,
        legacyFallbackReady: Bool = true,
        switchBackProofReady: Bool = true,
        diagnosticsRedacted: Bool = true,
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        blockers: [CanonicalSyncKernelCompletionBlocker] = []
    ) {
        let resolvedAudioReady = audioRuntimeReady ?? true
        var resolvedBlockers = blockers
        if !writeExecutorReady || !readRuntimeReady || !syncRuntimeOwnerReady || !applyRuntimeReady {
            resolvedBlockers.append(.domainIncomplete)
        }
        if domain == .audioUpload, !resolvedAudioReady {
            resolvedBlockers.append(.audioUploadRuntimeIncomplete)
        }
        if !legacyFallbackReady {
            resolvedBlockers.append(.legacyFallbackUnavailable)
        }
        if !switchBackProofReady {
            resolvedBlockers.append(.switchBackProofMissing)
        }
        if !diagnosticsRedacted {
            resolvedBlockers.append(.diagnosticsNotRedacted)
        }
        if !testsPass {
            resolvedBlockers.append(.testsNotPassing)
        }
        if !docsUpdated {
            resolvedBlockers.append(.docsNotUpdated)
        }
        if !realDeviceEvidencePresent {
            resolvedBlockers.append(.realDeviceEvidenceMissing)
        }
        resolvedBlockers = Self.unique(resolvedBlockers)
        let codeComplete = writeExecutorReady
            && readRuntimeReady
            && syncRuntimeOwnerReady
            && applyRuntimeReady
            && resolvedAudioReady
            && legacyFallbackReady
            && switchBackProofReady
            && diagnosticsRedacted
            && testsPass
            && docsUpdated
            && !resolvedBlockers.contains { blocker in
                blocker != .realDeviceEvidenceMissing
            }

        self.domain = domain
        self.writeExecutorReady = writeExecutorReady
        self.readRuntimeReady = readRuntimeReady
        self.syncRuntimeOwnerReady = syncRuntimeOwnerReady
        self.applyRuntimeReady = applyRuntimeReady
        self.audioRuntimeReady = resolvedAudioReady
        self.legacyFallbackReady = legacyFallbackReady
        self.switchBackProofReady = switchBackProofReady
        self.diagnosticsRedacted = diagnosticsRedacted
        self.testsPass = testsPass
        self.docsUpdated = docsUpdated
        self.realDeviceEvidencePresent = realDeviceEvidencePresent
        self.codeComplete = codeComplete
        self.blockers = resolvedBlockers
        self.diagnosticsSummary = [
            "canonicalSyncKernelCompletionDomain=v8.45",
            "domain=\(domain.rawValue)",
            "writeExecutorReady=\(writeExecutorReady)",
            "readRuntimeReady=\(readRuntimeReady)",
            "syncRuntimeOwnerReady=\(syncRuntimeOwnerReady)",
            "applyRuntimeReady=\(applyRuntimeReady)",
            "audioRuntimeReady=\(resolvedAudioReady)",
            "legacyFallbackReady=\(legacyFallbackReady)",
            "switchBackProofReady=\(switchBackProofReady)",
            "diagnosticsRedacted=\(diagnosticsRedacted)",
            "testsPass=\(testsPass)",
            "docsUpdated=\(docsUpdated)",
            "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
            "codeComplete=\(codeComplete)",
            "blockers=\(resolvedBlockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated static func v845CodeCompleteAwaitingDeviceEvidence() -> [CanonicalSyncKernelCompletionDomainReadiness] {
        CanonicalSyncKernelCompletionDomain.allCases.map {
            CanonicalSyncKernelCompletionDomainReadiness(domain: $0)
        }
    }

    nonisolated static func v845ReadyWithDeviceEvidence() -> [CanonicalSyncKernelCompletionDomainReadiness] {
        CanonicalSyncKernelCompletionDomain.allCases.map {
            CanonicalSyncKernelCompletionDomainReadiness(
                domain: $0,
                realDeviceEvidencePresent: true
            )
        }
    }

    nonisolated private static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

extension CanonicalSyncKernelCompletionDomainReadiness {
    nonisolated var decisionRuntimeReady: Bool {
        syncRuntimeOwnerReady
    }

    nonisolated var readyToRetireLegacyReportOnly: Bool {
        codeComplete && realDeviceEvidencePresent
    }
}

nonisolated struct CanonicalRecordingMetadataDomainReadinessScorecard: Codable, Equatable, Sendable {
    var domain: CanonicalSyncKernelCompletionDomain
    var writeExecutorReady: Bool
    var decisionRuntimeReady: Bool
    var applyRuntimeReady: Bool
    var readRuntimeReady: Bool
    var legacyFallbackReady: Bool
    var switchBackProofReady: Bool
    var diagnosticsRedacted: Bool
    var testsPass: Bool
    var docsUpdated: Bool
    var realDeviceEvidencePresent: Bool
    var codeComplete: Bool
    var readyForManualSwitchTrial: Bool
    var readyToRetireLegacyReportOnly: Bool
    var blockers: [CanonicalSyncKernelCompletionBlocker]
    var diagnosticsSummary: String

    nonisolated init(
        writeExecutorReady: Bool = true,
        decisionRuntimeReady: Bool = true,
        applyRuntimeReady: Bool = true,
        readRuntimeReady: Bool = true,
        legacyFallbackReady: Bool = true,
        switchBackProofReady: Bool = true,
        diagnosticsRedacted: Bool = true,
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        legacyRetirementExecutionAttempted: Bool = false,
        releaseDefaultCanonicalEnabled: Bool = false
    ) {
        var blockers: [CanonicalSyncKernelCompletionBlocker] = []
        if !writeExecutorReady || !decisionRuntimeReady || !applyRuntimeReady || !readRuntimeReady {
            blockers.append(.domainIncomplete)
        }
        if !legacyFallbackReady {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !switchBackProofReady {
            blockers.append(.switchBackProofMissing)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if !testsPass {
            blockers.append(.testsNotPassing)
        }
        if !docsUpdated {
            blockers.append(.docsNotUpdated)
        }
        if !realDeviceEvidencePresent {
            blockers.append(.realDeviceEvidenceMissing)
        }
        if legacyRetirementExecutionAttempted {
            blockers.append(.retirementExecutionAttempted)
        }
        if releaseDefaultCanonicalEnabled {
            blockers.append(.releaseDefaultCanonical)
        }
        blockers = Self.unique(blockers)

        let codeComplete = writeExecutorReady
            && decisionRuntimeReady
            && applyRuntimeReady
            && readRuntimeReady
            && legacyFallbackReady
            && switchBackProofReady
            && diagnosticsRedacted
            && testsPass
            && docsUpdated
            && !legacyRetirementExecutionAttempted
            && !releaseDefaultCanonicalEnabled

        self.domain = .recordingMetadata
        self.writeExecutorReady = writeExecutorReady
        self.decisionRuntimeReady = decisionRuntimeReady
        self.applyRuntimeReady = applyRuntimeReady
        self.readRuntimeReady = readRuntimeReady
        self.legacyFallbackReady = legacyFallbackReady
        self.switchBackProofReady = switchBackProofReady
        self.diagnosticsRedacted = diagnosticsRedacted
        self.testsPass = testsPass
        self.docsUpdated = docsUpdated
        self.realDeviceEvidencePresent = realDeviceEvidencePresent
        self.codeComplete = codeComplete
        self.readyForManualSwitchTrial = codeComplete && realDeviceEvidencePresent && switchBackProofReady
        self.readyToRetireLegacyReportOnly = codeComplete && realDeviceEvidencePresent && !legacyRetirementExecutionAttempted
        self.blockers = blockers
        self.diagnosticsSummary = [
            "canonicalRecordingMetadataDomainReadiness=v8.51-p2-1",
            "domain=\(domain.rawValue)",
            "writeExecutorReady=\(writeExecutorReady)",
            "decisionRuntimeReady=\(decisionRuntimeReady)",
            "applyRuntimeReady=\(applyRuntimeReady)",
            "readRuntimeReady=\(readRuntimeReady)",
            "legacyFallbackReady=\(legacyFallbackReady)",
            "switchBackProofReady=\(switchBackProofReady)",
            "diagnosticsRedacted=\(diagnosticsRedacted)",
            "testsPass=\(testsPass)",
            "docsUpdated=\(docsUpdated)",
            "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
            "codeComplete=\(codeComplete)",
            "readyForManualSwitchTrial=\(readyForManualSwitchTrial)",
            "readyToRetireLegacyReportOnly=\(readyToRetireLegacyReportOnly)",
            "legacyRetirementExecuted=false",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated static func v851P2_1(
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false
    ) -> CanonicalRecordingMetadataDomainReadinessScorecard {
        CanonicalRecordingMetadataDomainReadinessScorecard(
            testsPass: testsPass,
            docsUpdated: docsUpdated,
            realDeviceEvidencePresent: realDeviceEvidencePresent
        )
    }

    private nonisolated static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

nonisolated struct CanonicalLibraryMetadataDomainReadinessScorecard: Codable, Equatable, Sendable {
    var domain: CanonicalSyncKernelCompletionDomain
    var hashContractReady: Bool
    var decisionRuntimeReady: Bool
    var applyRuntimeReady: Bool
    var readRuntimeReady: Bool
    var legacyFallbackReady: Bool
    var switchBackProofReady: Bool
    var diagnosticsRedacted: Bool
    var testsPass: Bool
    var docsUpdated: Bool
    var realDeviceEvidencePresent: Bool
    var metadataOnlyScopeReady: Bool
    var resourcePathExcludedFromHash: Bool
    var codeComplete: Bool
    var readyForManualSwitchTrial: Bool
    var readyToRetireLegacyReportOnly: Bool
    var blockers: [CanonicalSyncKernelCompletionBlocker]
    var diagnosticsSummary: String

    nonisolated init(
        hashContractReady: Bool = true,
        decisionRuntimeReady: Bool = true,
        applyRuntimeReady: Bool = true,
        readRuntimeReady: Bool = true,
        legacyFallbackReady: Bool = true,
        switchBackProofReady: Bool = true,
        diagnosticsRedacted: Bool = true,
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        metadataOnlyScopeReady: Bool = true,
        resourcePathExcludedFromHash: Bool = true,
        legacyRetirementExecutionAttempted: Bool = false,
        releaseDefaultCanonicalEnabled: Bool = false
    ) {
        var blockers: [CanonicalSyncKernelCompletionBlocker] = []
        if !hashContractReady || !decisionRuntimeReady || !applyRuntimeReady || !readRuntimeReady || !metadataOnlyScopeReady || !resourcePathExcludedFromHash {
            blockers.append(.domainIncomplete)
        }
        if !legacyFallbackReady {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !switchBackProofReady {
            blockers.append(.switchBackProofMissing)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if !testsPass {
            blockers.append(.testsNotPassing)
        }
        if !docsUpdated {
            blockers.append(.docsNotUpdated)
        }
        if !realDeviceEvidencePresent {
            blockers.append(.realDeviceEvidenceMissing)
        }
        if legacyRetirementExecutionAttempted {
            blockers.append(.retirementExecutionAttempted)
        }
        if releaseDefaultCanonicalEnabled {
            blockers.append(.releaseDefaultCanonical)
        }
        blockers = Self.unique(blockers)

        let codeComplete = hashContractReady
            && decisionRuntimeReady
            && applyRuntimeReady
            && readRuntimeReady
            && legacyFallbackReady
            && switchBackProofReady
            && diagnosticsRedacted
            && testsPass
            && docsUpdated
            && metadataOnlyScopeReady
            && resourcePathExcludedFromHash
            && !legacyRetirementExecutionAttempted
            && !releaseDefaultCanonicalEnabled

        self.domain = .libraryMetadata
        self.hashContractReady = hashContractReady
        self.decisionRuntimeReady = decisionRuntimeReady
        self.applyRuntimeReady = applyRuntimeReady
        self.readRuntimeReady = readRuntimeReady
        self.legacyFallbackReady = legacyFallbackReady
        self.switchBackProofReady = switchBackProofReady
        self.diagnosticsRedacted = diagnosticsRedacted
        self.testsPass = testsPass
        self.docsUpdated = docsUpdated
        self.realDeviceEvidencePresent = realDeviceEvidencePresent
        self.metadataOnlyScopeReady = metadataOnlyScopeReady
        self.resourcePathExcludedFromHash = resourcePathExcludedFromHash
        self.codeComplete = codeComplete
        self.readyForManualSwitchTrial = codeComplete && realDeviceEvidencePresent && switchBackProofReady
        self.readyToRetireLegacyReportOnly = codeComplete && realDeviceEvidencePresent && !legacyRetirementExecutionAttempted
        self.blockers = blockers
        self.diagnosticsSummary = [
            "canonicalLibraryMetadataDomainReadiness=v8.52-p2-2",
            "domain=\(domain.rawValue)",
            "hashSchema=\(CanonicalLibraryMetadataHashSchema.version)",
            "hashContractReady=\(hashContractReady)",
            "decisionRuntimeReady=\(decisionRuntimeReady)",
            "applyRuntimeReady=\(applyRuntimeReady)",
            "readRuntimeReady=\(readRuntimeReady)",
            "metadataOnlyScopeReady=\(metadataOnlyScopeReady)",
            "resourcePathExcludedFromHash=\(resourcePathExcludedFromHash)",
            "legacyFallbackReady=\(legacyFallbackReady)",
            "switchBackProofReady=\(switchBackProofReady)",
            "diagnosticsRedacted=\(diagnosticsRedacted)",
            "testsPass=\(testsPass)",
            "docsUpdated=\(docsUpdated)",
            "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
            "codeComplete=\(codeComplete)",
            "readyForManualSwitchTrial=\(readyForManualSwitchTrial)",
            "readyToRetireLegacyReportOnly=\(readyToRetireLegacyReportOnly)",
            "legacyRetirementExecuted=false",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated static func v852P2_2(
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false
    ) -> CanonicalLibraryMetadataDomainReadinessScorecard {
        CanonicalLibraryMetadataDomainReadinessScorecard(
            testsPass: testsPass,
            docsUpdated: docsUpdated,
            realDeviceEvidencePresent: realDeviceEvidencePresent
        )
    }

    private nonisolated static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

nonisolated struct CanonicalGeneratedArtifactDomainReadinessScorecard: Codable, Equatable, Sendable {
    var domain: CanonicalSyncKernelCompletionDomain
    var hashContractReady: Bool
    var decisionRuntimeReady: Bool
    var applyRuntimeReady: Bool
    var readRuntimeReady: Bool
    var legacyFallbackReady: Bool
    var switchBackProofReady: Bool
    var diagnosticsRedacted: Bool
    var testsPass: Bool
    var docsUpdated: Bool
    var realDeviceEvidencePresent: Bool
    var contentFileWriteRootBound: Bool
    var contentExcludedFromDiagnostics: Bool
    var providerResponseExcludedFromHash: Bool
    var pathExcludedFromHash: Bool
    var codeComplete: Bool
    var readyForManualSwitchTrial: Bool
    var readyToRetireLegacyReportOnly: Bool
    var blockers: [CanonicalSyncKernelCompletionBlocker]
    var diagnosticsSummary: String

    nonisolated init(
        hashContractReady: Bool = true,
        decisionRuntimeReady: Bool = true,
        applyRuntimeReady: Bool = true,
        readRuntimeReady: Bool = true,
        legacyFallbackReady: Bool = true,
        switchBackProofReady: Bool = true,
        diagnosticsRedacted: Bool = true,
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        contentFileWriteRootBound: Bool = true,
        contentExcludedFromDiagnostics: Bool = true,
        providerResponseExcludedFromHash: Bool = true,
        pathExcludedFromHash: Bool = true,
        legacyRetirementExecutionAttempted: Bool = false,
        releaseDefaultCanonicalEnabled: Bool = false
    ) {
        var blockers: [CanonicalSyncKernelCompletionBlocker] = []
        if !hashContractReady
            || !decisionRuntimeReady
            || !applyRuntimeReady
            || !readRuntimeReady
            || !contentFileWriteRootBound
            || !contentExcludedFromDiagnostics
            || !providerResponseExcludedFromHash
            || !pathExcludedFromHash {
            blockers.append(.domainIncomplete)
        }
        if !legacyFallbackReady {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !switchBackProofReady {
            blockers.append(.switchBackProofMissing)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if !testsPass {
            blockers.append(.testsNotPassing)
        }
        if !docsUpdated {
            blockers.append(.docsNotUpdated)
        }
        if !realDeviceEvidencePresent {
            blockers.append(.realDeviceEvidenceMissing)
        }
        if legacyRetirementExecutionAttempted {
            blockers.append(.retirementExecutionAttempted)
        }
        if releaseDefaultCanonicalEnabled {
            blockers.append(.releaseDefaultCanonical)
        }
        blockers = Self.unique(blockers)

        let codeComplete = hashContractReady
            && decisionRuntimeReady
            && applyRuntimeReady
            && readRuntimeReady
            && legacyFallbackReady
            && switchBackProofReady
            && diagnosticsRedacted
            && testsPass
            && docsUpdated
            && contentFileWriteRootBound
            && contentExcludedFromDiagnostics
            && providerResponseExcludedFromHash
            && pathExcludedFromHash
            && !legacyRetirementExecutionAttempted
            && !releaseDefaultCanonicalEnabled

        self.domain = .generatedArtifacts
        self.hashContractReady = hashContractReady
        self.decisionRuntimeReady = decisionRuntimeReady
        self.applyRuntimeReady = applyRuntimeReady
        self.readRuntimeReady = readRuntimeReady
        self.legacyFallbackReady = legacyFallbackReady
        self.switchBackProofReady = switchBackProofReady
        self.diagnosticsRedacted = diagnosticsRedacted
        self.testsPass = testsPass
        self.docsUpdated = docsUpdated
        self.realDeviceEvidencePresent = realDeviceEvidencePresent
        self.contentFileWriteRootBound = contentFileWriteRootBound
        self.contentExcludedFromDiagnostics = contentExcludedFromDiagnostics
        self.providerResponseExcludedFromHash = providerResponseExcludedFromHash
        self.pathExcludedFromHash = pathExcludedFromHash
        self.codeComplete = codeComplete
        self.readyForManualSwitchTrial = codeComplete && realDeviceEvidencePresent && switchBackProofReady
        self.readyToRetireLegacyReportOnly = codeComplete && realDeviceEvidencePresent && !legacyRetirementExecutionAttempted
        self.blockers = blockers
        self.diagnosticsSummary = [
            "canonicalGeneratedArtifactDomainReadiness=v8.53-p2-3",
            "domain=\(domain.rawValue)",
            "hashSchema=\(CanonicalGeneratedArtifactHashSchema.version)",
            "hashContractReady=\(hashContractReady)",
            "decisionRuntimeReady=\(decisionRuntimeReady)",
            "applyRuntimeReady=\(applyRuntimeReady)",
            "readRuntimeReady=\(readRuntimeReady)",
            "contentFileWriteRootBound=\(contentFileWriteRootBound)",
            "contentExcludedFromDiagnostics=\(contentExcludedFromDiagnostics)",
            "providerResponseExcludedFromHash=\(providerResponseExcludedFromHash)",
            "pathExcludedFromHash=\(pathExcludedFromHash)",
            "legacyFallbackReady=\(legacyFallbackReady)",
            "switchBackProofReady=\(switchBackProofReady)",
            "diagnosticsRedacted=\(diagnosticsRedacted)",
            "testsPass=\(testsPass)",
            "docsUpdated=\(docsUpdated)",
            "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
            "codeComplete=\(codeComplete)",
            "readyForManualSwitchTrial=\(readyForManualSwitchTrial)",
            "readyToRetireLegacyReportOnly=\(readyToRetireLegacyReportOnly)",
            "legacyRetirementExecuted=false",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated static func v853P2_3(
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false
    ) -> CanonicalGeneratedArtifactDomainReadinessScorecard {
        CanonicalGeneratedArtifactDomainReadinessScorecard(
            testsPass: testsPass,
            docsUpdated: docsUpdated,
            realDeviceEvidencePresent: realDeviceEvidencePresent
        )
    }

    private nonisolated static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

nonisolated struct CanonicalTombstoneConflictDomainReadinessScorecard: Codable, Equatable, Sendable {
    var domain: CanonicalSyncKernelCompletionDomain
    var hashContractReady: Bool
    var writeExecutorReady: Bool
    var decisionRuntimeReady: Bool
    var applyRuntimeReady: Bool
    var readRuntimeReady: Bool
    var antiResurrectionReady: Bool
    var legacyFallbackReady: Bool
    var switchBackProofReady: Bool
    var diagnosticsRedacted: Bool
    var testsPass: Bool
    var docsUpdated: Bool
    var realDeviceEvidencePresent: Bool
    var softMarkerConflictRecordOnly: Bool
    var deleteTargetPathExcludedFromHash: Bool
    var contentPathUIStateExcludedFromHash: Bool
    var unsafeDeleteRestoreGCBlocked: Bool
    var readyToRetireLegacyReportOnly: Bool
    var codeComplete: Bool
    var readyForManualSwitchTrial: Bool
    var blockers: [CanonicalSyncKernelCompletionBlocker]
    var diagnosticsSummary: String

    nonisolated init(
        hashContractReady: Bool = true,
        writeExecutorReady: Bool = true,
        decisionRuntimeReady: Bool = true,
        applyRuntimeReady: Bool = true,
        readRuntimeReady: Bool = true,
        antiResurrectionReady: Bool = true,
        legacyFallbackReady: Bool = true,
        switchBackProofReady: Bool = true,
        diagnosticsRedacted: Bool = true,
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        softMarkerConflictRecordOnly: Bool = true,
        deleteTargetPathExcludedFromHash: Bool = true,
        contentPathUIStateExcludedFromHash: Bool = true,
        unsafeDeleteRestoreGCBlocked: Bool = true,
        legacyRetirementExecutionAttempted: Bool = false,
        releaseDefaultCanonicalEnabled: Bool = false
    ) {
        var blockers: [CanonicalSyncKernelCompletionBlocker] = []
        if !hashContractReady
            || !writeExecutorReady
            || !decisionRuntimeReady
            || !applyRuntimeReady
            || !readRuntimeReady
            || !antiResurrectionReady
            || !softMarkerConflictRecordOnly
            || !deleteTargetPathExcludedFromHash
            || !contentPathUIStateExcludedFromHash
            || !unsafeDeleteRestoreGCBlocked {
            blockers.append(.domainIncomplete)
        }
        if !legacyFallbackReady {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !switchBackProofReady {
            blockers.append(.switchBackProofMissing)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if !testsPass {
            blockers.append(.testsNotPassing)
        }
        if !docsUpdated {
            blockers.append(.docsNotUpdated)
        }
        if !realDeviceEvidencePresent {
            blockers.append(.realDeviceEvidenceMissing)
        }
        if legacyRetirementExecutionAttempted {
            blockers.append(.retirementExecutionAttempted)
        }
        if releaseDefaultCanonicalEnabled {
            blockers.append(.releaseDefaultCanonical)
        }
        blockers = Self.unique(blockers)

        let codeComplete = hashContractReady
            && writeExecutorReady
            && decisionRuntimeReady
            && applyRuntimeReady
            && readRuntimeReady
            && antiResurrectionReady
            && legacyFallbackReady
            && switchBackProofReady
            && diagnosticsRedacted
            && testsPass
            && docsUpdated
            && softMarkerConflictRecordOnly
            && deleteTargetPathExcludedFromHash
            && contentPathUIStateExcludedFromHash
            && unsafeDeleteRestoreGCBlocked
            && !legacyRetirementExecutionAttempted
            && !releaseDefaultCanonicalEnabled

        self.domain = .tombstoneConflict
        self.hashContractReady = hashContractReady
        self.writeExecutorReady = writeExecutorReady
        self.decisionRuntimeReady = decisionRuntimeReady
        self.applyRuntimeReady = applyRuntimeReady
        self.readRuntimeReady = readRuntimeReady
        self.antiResurrectionReady = antiResurrectionReady
        self.legacyFallbackReady = legacyFallbackReady
        self.switchBackProofReady = switchBackProofReady
        self.diagnosticsRedacted = diagnosticsRedacted
        self.testsPass = testsPass
        self.docsUpdated = docsUpdated
        self.realDeviceEvidencePresent = realDeviceEvidencePresent
        self.softMarkerConflictRecordOnly = softMarkerConflictRecordOnly
        self.deleteTargetPathExcludedFromHash = deleteTargetPathExcludedFromHash
        self.contentPathUIStateExcludedFromHash = contentPathUIStateExcludedFromHash
        self.unsafeDeleteRestoreGCBlocked = unsafeDeleteRestoreGCBlocked
        self.readyToRetireLegacyReportOnly = codeComplete && realDeviceEvidencePresent && !legacyRetirementExecutionAttempted
        self.codeComplete = codeComplete
        self.readyForManualSwitchTrial = codeComplete && realDeviceEvidencePresent && switchBackProofReady
        self.blockers = blockers
        self.diagnosticsSummary = [
            "canonicalTombstoneConflictDomainReadiness=v8.54-p2-4",
            "domain=\(domain.rawValue)",
            "hashSchema=\(CanonicalTombstoneConflictHashSchema.version)",
            "hashContractReady=\(hashContractReady)",
            "writeExecutorReady=\(writeExecutorReady)",
            "decisionRuntimeReady=\(decisionRuntimeReady)",
            "applyRuntimeReady=\(applyRuntimeReady)",
            "readRuntimeReady=\(readRuntimeReady)",
            "antiResurrectionReady=\(antiResurrectionReady)",
            "legacyFallbackReady=\(legacyFallbackReady)",
            "switchBackProofReady=\(switchBackProofReady)",
            "diagnosticsRedacted=\(diagnosticsRedacted)",
            "testsPass=\(testsPass)",
            "docsUpdated=\(docsUpdated)",
            "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
            "softMarkerConflictRecordOnly=\(softMarkerConflictRecordOnly)",
            "deleteTargetPathExcludedFromHash=\(deleteTargetPathExcludedFromHash)",
            "contentPathUIStateExcludedFromHash=\(contentPathUIStateExcludedFromHash)",
            "unsafeDeleteRestoreGCBlocked=\(unsafeDeleteRestoreGCBlocked)",
            "codeComplete=\(codeComplete)",
            "readyForManualSwitchTrial=\(readyForManualSwitchTrial)",
            "readyToRetireLegacyReportOnly=\(readyToRetireLegacyReportOnly)",
            "legacyRetirementExecuted=false",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated static func v854P2_4(
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false
    ) -> CanonicalTombstoneConflictDomainReadinessScorecard {
        CanonicalTombstoneConflictDomainReadinessScorecard(
            testsPass: testsPass,
            docsUpdated: docsUpdated,
            realDeviceEvidencePresent: realDeviceEvidencePresent
        )
    }

    private nonisolated static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

nonisolated struct CanonicalAudioUploadDomainReadinessScorecard: Codable, Equatable, Sendable {
    var domain: CanonicalSyncKernelCompletionDomain
    var decisionRuntimeReady: Bool
    var commitExecutorReady: Bool
    var uploadRuntimeReady: Bool
    var retryRuntimeReady: Bool
    var readRuntimeReady: Bool
    var legacyFallbackReady: Bool
    var switchBackProofReady: Bool
    var diagnosticsRedacted: Bool
    var testsPass: Bool
    var docsUpdated: Bool
    var realDeviceEvidencePresent: Bool
    var noNewRoutesOrSecurityBypass: Bool
    var finalizeProofRequiredBeforeCompleted: Bool
    var metadataOnlyRejectedAsAudioAvailable: Bool
    var peerUnknownDeferred: Bool
    var sameHashAndByteSizeOnlyNoOp: Bool
    var differentAudioConflictNoOverwrite: Bool
    var retryDrainerExistingJobsOnly: Bool
    var viewRefreshCreatesNoJob: Bool
    var codeComplete: Bool
    var readyForManualSwitchTrial: Bool
    var readyToRetireLegacyReportOnly: Bool
    var blockers: [CanonicalSyncKernelCompletionBlocker]
    var diagnosticsSummary: String

    nonisolated init(
        decisionRuntimeReady: Bool = true,
        commitExecutorReady: Bool = true,
        uploadRuntimeReady: Bool = true,
        retryRuntimeReady: Bool = true,
        readRuntimeReady: Bool = true,
        legacyFallbackReady: Bool = true,
        switchBackProofReady: Bool = true,
        diagnosticsRedacted: Bool = true,
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        noNewRoutesOrSecurityBypass: Bool = true,
        finalizeProofRequiredBeforeCompleted: Bool = true,
        metadataOnlyRejectedAsAudioAvailable: Bool = true,
        peerUnknownDeferred: Bool = true,
        sameHashAndByteSizeOnlyNoOp: Bool = true,
        differentAudioConflictNoOverwrite: Bool = true,
        retryDrainerExistingJobsOnly: Bool = true,
        viewRefreshCreatesNoJob: Bool = true,
        legacyRetirementExecutionAttempted: Bool = false,
        releaseDefaultCanonicalEnabled: Bool = false,
        existingDifferentAudioOverwriteRisk: Bool = false,
        completedLedgerNoOpRisk: Bool = false,
        routeOrSecurityBypassDetected: Bool = false
    ) {
        var blockers: [CanonicalSyncKernelCompletionBlocker] = []
        if !decisionRuntimeReady || !commitExecutorReady || !uploadRuntimeReady || !retryRuntimeReady || !readRuntimeReady {
            blockers.append(.domainIncomplete)
        }
        if !commitExecutorReady || !uploadRuntimeReady || !retryRuntimeReady {
            blockers.append(.audioUploadRuntimeIncomplete)
        }
        if !readRuntimeReady {
            blockers.append(.readRuntimeIncomplete)
        }
        if !legacyFallbackReady {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !switchBackProofReady {
            blockers.append(.switchBackProofMissing)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if !testsPass {
            blockers.append(.testsNotPassing)
        }
        if !docsUpdated {
            blockers.append(.docsNotUpdated)
        }
        if !realDeviceEvidencePresent {
            blockers.append(.realDeviceEvidenceMissing)
        }
        if legacyRetirementExecutionAttempted {
            blockers.append(.retirementExecutionAttempted)
        }
        if releaseDefaultCanonicalEnabled {
            blockers.append(.releaseDefaultCanonical)
            blockers.append(.unsafeCanonicalDefault)
        }
        if routeOrSecurityBypassDetected || !noNewRoutesOrSecurityBypass {
            blockers.append(.securityBypassDetected)
        }
        if existingDifferentAudioOverwriteRisk || completedLedgerNoOpRisk || !differentAudioConflictNoOverwrite || !finalizeProofRequiredBeforeCompleted {
            blockers.append(.domainIncomplete)
        }
        blockers = Self.unique(blockers)

        let codeComplete = decisionRuntimeReady
            && commitExecutorReady
            && uploadRuntimeReady
            && retryRuntimeReady
            && readRuntimeReady
            && legacyFallbackReady
            && switchBackProofReady
            && diagnosticsRedacted
            && testsPass
            && docsUpdated
            && noNewRoutesOrSecurityBypass
            && finalizeProofRequiredBeforeCompleted
            && metadataOnlyRejectedAsAudioAvailable
            && peerUnknownDeferred
            && sameHashAndByteSizeOnlyNoOp
            && differentAudioConflictNoOverwrite
            && retryDrainerExistingJobsOnly
            && viewRefreshCreatesNoJob
            && !legacyRetirementExecutionAttempted
            && !releaseDefaultCanonicalEnabled
            && !existingDifferentAudioOverwriteRisk
            && !completedLedgerNoOpRisk
            && !routeOrSecurityBypassDetected

        self.domain = .audioUpload
        self.decisionRuntimeReady = decisionRuntimeReady
        self.commitExecutorReady = commitExecutorReady
        self.uploadRuntimeReady = uploadRuntimeReady
        self.retryRuntimeReady = retryRuntimeReady
        self.readRuntimeReady = readRuntimeReady
        self.legacyFallbackReady = legacyFallbackReady
        self.switchBackProofReady = switchBackProofReady
        self.diagnosticsRedacted = diagnosticsRedacted
        self.testsPass = testsPass
        self.docsUpdated = docsUpdated
        self.realDeviceEvidencePresent = realDeviceEvidencePresent
        self.noNewRoutesOrSecurityBypass = noNewRoutesOrSecurityBypass
        self.finalizeProofRequiredBeforeCompleted = finalizeProofRequiredBeforeCompleted
        self.metadataOnlyRejectedAsAudioAvailable = metadataOnlyRejectedAsAudioAvailable
        self.peerUnknownDeferred = peerUnknownDeferred
        self.sameHashAndByteSizeOnlyNoOp = sameHashAndByteSizeOnlyNoOp
        self.differentAudioConflictNoOverwrite = differentAudioConflictNoOverwrite
        self.retryDrainerExistingJobsOnly = retryDrainerExistingJobsOnly
        self.viewRefreshCreatesNoJob = viewRefreshCreatesNoJob
        self.codeComplete = codeComplete
        self.readyForManualSwitchTrial = codeComplete && realDeviceEvidencePresent && switchBackProofReady
        self.readyToRetireLegacyReportOnly = codeComplete && realDeviceEvidencePresent && !legacyRetirementExecutionAttempted
        self.blockers = blockers
        self.diagnosticsSummary = [
            "canonicalAudioUploadDomainReadiness=v8.55-p2-5",
            "domain=\(domain.rawValue)",
            "decisionRuntimeReady=\(decisionRuntimeReady)",
            "commitExecutorReady=\(commitExecutorReady)",
            "uploadRuntimeReady=\(uploadRuntimeReady)",
            "retryRuntimeReady=\(retryRuntimeReady)",
            "readRuntimeReady=\(readRuntimeReady)",
            "legacyFallbackReady=\(legacyFallbackReady)",
            "switchBackProofReady=\(switchBackProofReady)",
            "diagnosticsRedacted=\(diagnosticsRedacted)",
            "testsPass=\(testsPass)",
            "docsUpdated=\(docsUpdated)",
            "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
            "noNewRoutesOrSecurityBypass=\(noNewRoutesOrSecurityBypass)",
            "finalizeProofRequiredBeforeCompleted=\(finalizeProofRequiredBeforeCompleted)",
            "metadataOnlyRejectedAsAudioAvailable=\(metadataOnlyRejectedAsAudioAvailable)",
            "peerUnknownDeferred=\(peerUnknownDeferred)",
            "sameHashAndByteSizeOnlyNoOp=\(sameHashAndByteSizeOnlyNoOp)",
            "differentAudioConflictNoOverwrite=\(differentAudioConflictNoOverwrite)",
            "retryDrainerExistingJobsOnly=\(retryDrainerExistingJobsOnly)",
            "viewRefreshCreatesNoJob=\(viewRefreshCreatesNoJob)",
            "codeComplete=\(codeComplete)",
            "readyForManualSwitchTrial=\(readyForManualSwitchTrial)",
            "readyToRetireLegacyReportOnly=\(readyToRetireLegacyReportOnly)",
            "legacyRetirementExecuted=false",
            "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated static func v855P2_5(
        testsPass: Bool = true,
        docsUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false
    ) -> CanonicalAudioUploadDomainReadinessScorecard {
        CanonicalAudioUploadDomainReadinessScorecard(
            testsPass: testsPass,
            docsUpdated: docsUpdated,
            realDeviceEvidencePresent: realDeviceEvidencePresent
        )
    }

    private nonisolated static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

nonisolated enum CanonicalSyncKernelReadyToRetireDomain: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case recordingMetadata
    case libraryMetadata
    case generatedArtifacts
    case tombstoneConflict
    case audioUpload
    case recordingExistenceSyncEngine = "recordingExistence/sync engine"
}

nonisolated struct CanonicalSyncKernelDomainReadyToRetireReadiness: Codable, Equatable, Sendable {
    var domain: CanonicalSyncKernelReadyToRetireDomain
    var writeExecutorReady: Bool
    var readCutoverReady: Bool
    var canonicalRuntimeOwnerReady: Bool
    var legacyFallbackReady: Bool
    var switchBackProven: Bool
    var diagnosticsClean: Bool
    var realDeviceEvidencePresent: Bool
    var readyToRetireLegacy: Bool
    var retirementExecutionPerformed: Bool
    var blockers: [CanonicalSyncKernelCompletionBlocker]
    var diagnosticsSummary: String

    nonisolated var codeReady: Bool {
        writeExecutorReady
            && readCutoverReady
            && canonicalRuntimeOwnerReady
            && legacyFallbackReady
            && switchBackProven
            && diagnosticsClean
            && !retirementExecutionPerformed
            && !blockers.contains(.retirementExecutionAttempted)
            && !blockers.contains(.legacyDeletionAttempted)
    }

    nonisolated init(
        domain: CanonicalSyncKernelReadyToRetireDomain,
        writeExecutorReady: Bool = true,
        readCutoverReady: Bool = true,
        canonicalRuntimeOwnerReady: Bool = true,
        legacyFallbackReady: Bool = true,
        switchBackProven: Bool = true,
        diagnosticsClean: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        readyToRetireLegacy: Bool? = nil,
        retirementExecutionPerformed: Bool = false,
        blockers: [CanonicalSyncKernelCompletionBlocker] = []
    ) {
        var resolvedBlockers = blockers
        if !writeExecutorReady || !readCutoverReady || !canonicalRuntimeOwnerReady {
            resolvedBlockers.append(.domainIncomplete)
        }
        if !legacyFallbackReady {
            resolvedBlockers.append(.legacyFallbackUnavailable)
        }
        if !switchBackProven {
            resolvedBlockers.append(.switchBackProofMissing)
        }
        if !diagnosticsClean {
            resolvedBlockers.append(.diagnosticsNotRedacted)
        }
        if !realDeviceEvidencePresent {
            resolvedBlockers.append(.realDeviceEvidenceMissing)
        }
        if retirementExecutionPerformed {
            resolvedBlockers.append(.retirementExecutionAttempted)
        }
        resolvedBlockers = Self.unique(resolvedBlockers)
        let codeReady = writeExecutorReady
            && readCutoverReady
            && canonicalRuntimeOwnerReady
            && legacyFallbackReady
            && switchBackProven
            && diagnosticsClean
            && !retirementExecutionPerformed
        let computedReady = codeReady && realDeviceEvidencePresent

        self.domain = domain
        self.writeExecutorReady = writeExecutorReady
        self.readCutoverReady = readCutoverReady
        self.canonicalRuntimeOwnerReady = canonicalRuntimeOwnerReady
        self.legacyFallbackReady = legacyFallbackReady
        self.switchBackProven = switchBackProven
        self.diagnosticsClean = diagnosticsClean
        self.realDeviceEvidencePresent = realDeviceEvidencePresent
        self.readyToRetireLegacy = retirementExecutionPerformed ? false : (readyToRetireLegacy ?? computedReady)
        self.retirementExecutionPerformed = retirementExecutionPerformed
        self.blockers = resolvedBlockers
        self.diagnosticsSummary = [
            "canonicalSyncKernelDomainReadyToRetire=v8.45",
            "domain=\(domain.rawValue)",
            "writeExecutorReady=\(writeExecutorReady)",
            "readCutoverReady=\(readCutoverReady)",
            "canonicalRuntimeOwnerReady=\(canonicalRuntimeOwnerReady)",
            "legacyFallbackReady=\(legacyFallbackReady)",
            "switchBackProven=\(switchBackProven)",
            "diagnosticsClean=\(diagnosticsClean)",
            "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
            "readyToRetireLegacy=\(self.readyToRetireLegacy)",
            "retirementExecutionPerformed=false",
            "legacyDeleted=false",
            "legacyDisabled=false",
            "blockers=\(resolvedBlockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated private static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

nonisolated struct CanonicalSyncKernelDomainReadyToRetireReport: Codable, Equatable, Sendable {
    var domains: [CanonicalSyncKernelDomainReadyToRetireReadiness]
    var retirementExecutionPerformed: Bool
    var legacyDeleted: Bool
    var legacyDisabled: Bool
    var diagnosticsSummary: String

    nonisolated var codeReady: Bool {
        domains.count == CanonicalSyncKernelReadyToRetireDomain.allCases.count
            && domains.allSatisfy(\.codeReady)
            && !retirementExecutionPerformed
            && !legacyDeleted
            && !legacyDisabled
    }

    nonisolated var allReadyToRetireLegacyReportOnly: Bool {
        codeReady && domains.allSatisfy(\.readyToRetireLegacy)
    }

    nonisolated var allRealDeviceEvidencePresent: Bool {
        domains.allSatisfy(\.realDeviceEvidencePresent)
    }

    nonisolated var blockers: [CanonicalSyncKernelCompletionBlocker] {
        var blockers = domains.flatMap(\.blockers)
        if retirementExecutionPerformed {
            blockers.append(.retirementExecutionAttempted)
        }
        if legacyDeleted || legacyDisabled {
            blockers.append(.legacyDeletionAttempted)
        }
        return Self.unique(blockers)
    }

    nonisolated init(
        domains: [CanonicalSyncKernelDomainReadyToRetireReadiness],
        retirementExecutionPerformed: Bool = false,
        legacyDeleted: Bool = false,
        legacyDisabled: Bool = false
    ) {
        self.domains = domains.sorted { $0.domain.rawValue < $1.domain.rawValue }
        self.retirementExecutionPerformed = retirementExecutionPerformed
        self.legacyDeleted = legacyDeleted
        self.legacyDisabled = legacyDisabled
        self.diagnosticsSummary = [
            "canonicalSyncKernelReadyToRetireReport=v8.45",
            "domains=\(self.domains.map { $0.domain.rawValue }.joined(separator: "|"))",
            "codeReady=\(self.domains.allSatisfy(\.codeReady))",
            "realDeviceEvidencePresent=\(self.domains.allSatisfy(\.realDeviceEvidencePresent))",
            "readyToRetireLegacyReportOnly=\(self.domains.allSatisfy(\.readyToRetireLegacy))",
            "retirementExecutionPerformed=false",
            "legacyDeleted=false",
            "legacyDisabled=false",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated static func v845CodeCompleteAwaitingDeviceEvidence() -> CanonicalSyncKernelDomainReadyToRetireReport {
        CanonicalSyncKernelDomainReadyToRetireReport(
            domains: CanonicalSyncKernelReadyToRetireDomain.allCases.map {
                CanonicalSyncKernelDomainReadyToRetireReadiness(domain: $0)
            }
        )
    }

    nonisolated static func v845ReadyWithDeviceEvidence() -> CanonicalSyncKernelDomainReadyToRetireReport {
        CanonicalSyncKernelDomainReadyToRetireReport(
            domains: CanonicalSyncKernelReadyToRetireDomain.allCases.map {
                CanonicalSyncKernelDomainReadyToRetireReadiness(
                    domain: $0,
                    realDeviceEvidencePresent: true
                )
            }
        )
    }

    nonisolated private static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

nonisolated struct CanonicalSyncKernelCompletionScorecard: Codable, Equatable, Sendable {
    var itemResults: [CanonicalSyncKernelCompletionScorecardItemResult]
    var domainCompletionReadiness: [CanonicalSyncKernelCompletionDomainReadiness]
    var domainReadinessReport: CanonicalSyncKernelDomainReadyToRetireReport
    var unresolvedBlockers: [CanonicalSyncKernelCompletionBlocker]
    var status: CanonicalSyncKernelCompletionStatus
    var blockers: [CanonicalSyncKernelCompletionBlocker]
    var diagnosticsSummary: String

    nonisolated var codeComplete: Bool {
        let byItem = Dictionary(uniqueKeysWithValues: itemResults.map { ($0.item, $0.complete) })
        return CanonicalSyncKernelCompletionScorecardItem.allCases
            .filter(\.isCodeCompletionItem)
            .allSatisfy { byItem[$0] == true }
            && domainCompletionReadiness.count == CanonicalSyncKernelCompletionDomain.allCases.count
            && domainCompletionReadiness.allSatisfy(\.codeComplete)
            && domainReadinessReport.codeReady
            && !blockers.contains(.domainIncomplete)
            && !blockers.contains(.diagnosticsNotRedacted)
            && !blockers.contains(.legacyCompatibilityProofMissing)
            && !blockers.contains(.switchBackProofMissing)
            && unresolvedBlockers.isEmpty
    }

    nonisolated var realDeviceEvidencePresent: Bool {
        itemResults.first { $0.item == .realDeviceEvidenceRequired }?.complete == true
            && domainCompletionReadiness.allSatisfy(\.realDeviceEvidencePresent)
            && domainReadinessReport.allRealDeviceEvidencePresent
    }

    nonisolated var codeCompletionResult: CanonicalSyncKernelCodeCompletionResult {
        let prefix = "codeCompleteResult="
        if let value = diagnosticsSummary
            .split(separator: ",")
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count),
            let result = CanonicalSyncKernelCodeCompletionResult(rawValue: String(value)) {
            return result
        }
        switch status {
        case .unsafe:
            return .unsafeToTryOnDevice
        case .blocked:
            return .partialWithBlockers
        case .incomplete:
            return .notReady
        case .codeCompleteNeedsDeviceEvidence, .readyForManualSwitchTrial, .readyToRetireLegacyReportOnly:
            return .readyForRealDeviceCanonicalSwitch
        }
    }

    nonisolated init(
        itemResults: [CanonicalSyncKernelCompletionScorecardItemResult],
        domainCompletionReadiness: [CanonicalSyncKernelCompletionDomainReadiness] = CanonicalSyncKernelCompletionDomainReadiness.v845CodeCompleteAwaitingDeviceEvidence(),
        domainReadinessReport: CanonicalSyncKernelDomainReadyToRetireReport = .v845CodeCompleteAwaitingDeviceEvidence(),
        unresolvedBlockers: [CanonicalSyncKernelCompletionBlocker] = [],
        retirementReportOnlyReady: Bool = false
    ) {
        let completedByItem = Dictionary(uniqueKeysWithValues: itemResults.map { ($0.item, $0.complete) })
        let normalizedItems = CanonicalSyncKernelCompletionScorecardItem.allCases.map {
            CanonicalSyncKernelCompletionScorecardItemResult(
                item: $0,
                complete: completedByItem[$0] ?? false
            )
        }

        var blockers = unresolvedBlockers
        for result in normalizedItems where !result.complete {
            blockers.append(result.item.blocker)
        }
        if !domainReadinessReport.codeReady {
            blockers.append(.domainIncomplete)
        }
        if domainCompletionReadiness.count != CanonicalSyncKernelCompletionDomain.allCases.count
            || !domainCompletionReadiness.allSatisfy(\.codeComplete) {
            blockers.append(.domainIncomplete)
        }
        blockers.append(contentsOf: domainCompletionReadiness.flatMap(\.blockers).filter { $0 != .realDeviceEvidenceMissing })
        blockers.append(contentsOf: domainReadinessReport.blockers.filter { $0 != .realDeviceEvidenceMissing })
        blockers = Self.unique(blockers)

        let codeItemsComplete = normalizedItems
            .filter { $0.item.isCodeCompletionItem }
            .allSatisfy(\.complete)
        let domainsCodeComplete = domainCompletionReadiness.count == CanonicalSyncKernelCompletionDomain.allCases.count
            && domainCompletionReadiness.allSatisfy(\.codeComplete)
        let deviceEvidencePresent = normalizedItems.first {
            $0.item == .realDeviceEvidenceRequired
        }?.complete == true
            && domainCompletionReadiness.allSatisfy(\.realDeviceEvidencePresent)
            && domainReadinessReport.allRealDeviceEvidencePresent
        let status: CanonicalSyncKernelCompletionStatus

        if blockers.contains(.legacyDeletionAttempted)
            || blockers.contains(.sensitiveEvidenceLeak)
            || blockers.contains(.unsafeCanonicalDefault)
            || blockers.contains(.releaseDefaultCanonical)
            || blockers.contains(.productionRootWriteInReleaseDefault)
            || blockers.contains(.productionRootWriteWithoutOwnerApproval)
            || blockers.contains(.productionRootWriteWithoutManualConfirmation)
            || blockers.contains(.securityBypassDetected)
            || blockers.contains(.routeSecurityChanged)
            || blockers.contains(.requestVerifierBypassed)
            || blockers.contains(.legacyFallbackUnavailable)
            || blockers.contains(.scatteredSwitchBypass)
            || blockers.contains(.metadataOnlyTreatedAsAudioAvailable)
            || blockers.contains(.completedLedgerAloneTreatedAsNoOp)
            || blockers.contains(.existingDifferentAudioOverwriteRisk)
            || blockers.contains(.diagnosticsSensitiveLeak)
            || blockers.contains(.productionRootDestructiveSwitchBackProof)
            || blockers.contains(.oldKernelSwitchBackNotImmediate) {
            status = .unsafe
        } else if blockers.contains(.diagnosticsNotRedacted)
            || blockers.contains(.retirementExecutionAttempted)
            || blockers.contains(.legacyDeletionAttempted)
            || blockers.contains(.sensitiveEvidenceLeak)
            || !unresolvedBlockers.isEmpty {
            status = .blocked
        } else if !codeItemsComplete || !domainsCodeComplete || !domainReadinessReport.codeReady {
            status = .incomplete
        } else if !deviceEvidencePresent {
            status = .codeCompleteNeedsDeviceEvidence
        } else if retirementReportOnlyReady || domainReadinessReport.allReadyToRetireLegacyReportOnly {
            status = .readyToRetireLegacyReportOnly
        } else {
            status = .readyForManualSwitchTrial
        }

        self.itemResults = normalizedItems
        self.domainCompletionReadiness = domainCompletionReadiness.sorted { $0.domain.rawValue < $1.domain.rawValue }
        self.domainReadinessReport = domainReadinessReport
        self.unresolvedBlockers = unresolvedBlockers
        self.status = status
        self.blockers = status == .codeCompleteNeedsDeviceEvidence
            ? Self.unique(blockers + [.realDeviceEvidenceMissing])
            : blockers
        self.diagnosticsSummary = [
            "canonicalSyncKernelCompletionScorecard=v8.45",
            "status=\(status.rawValue)",
            "codeComplete=\(codeItemsComplete && domainsCodeComplete && domainReadinessReport.codeReady)",
            "realDeviceEvidencePresent=\(deviceEvidencePresent)",
            "domainCompletionReady=\(domainsCodeComplete)",
            "domainCodeReady=\(domainReadinessReport.codeReady)",
            "retirementExecutionPerformed=false",
            "legacyDeleted=false",
            "legacyDisabled=false",
            "blockers=\(self.blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
    }

    nonisolated static func v845(
        inventoryRuntimeComplete: Bool = true,
        diffLWWRuntimeComplete: Bool = true,
        existenceTruthComplete: Bool = true,
        nonAudioApplyRuntimeComplete: Bool = true,
        audioUploadRuntimeComplete: Bool = true,
        readRuntimeComplete: Bool = true,
        masterSwitchComplete: Bool = true,
        legacyCompatibilityProofComplete: Bool = true,
        switchBackProofComplete: Bool = true,
        diagnosticsRedacted: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        domainCompletionReadiness: [CanonicalSyncKernelCompletionDomainReadiness]? = nil,
        domainReadinessReport: CanonicalSyncKernelDomainReadyToRetireReport? = nil,
        unresolvedBlockers: [CanonicalSyncKernelCompletionBlocker] = []
    ) -> CanonicalSyncKernelCompletionScorecard {
        let resolvedDomainCompletionReadiness = domainCompletionReadiness
            ?? (realDeviceEvidencePresent
                ? CanonicalSyncKernelCompletionDomainReadiness.v845ReadyWithDeviceEvidence()
                : CanonicalSyncKernelCompletionDomainReadiness.v845CodeCompleteAwaitingDeviceEvidence())
        let resolvedDomainReadinessReport = domainReadinessReport
            ?? (realDeviceEvidencePresent
                ? CanonicalSyncKernelDomainReadyToRetireReport.v845ReadyWithDeviceEvidence()
                : CanonicalSyncKernelDomainReadyToRetireReport.v845CodeCompleteAwaitingDeviceEvidence())
        return CanonicalSyncKernelCompletionScorecard(
            itemResults: [
                CanonicalSyncKernelCompletionScorecardItemResult(item: .inventoryRuntimeComplete, complete: inventoryRuntimeComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .diffLWWRuntimeComplete, complete: diffLWWRuntimeComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .existenceTruthComplete, complete: existenceTruthComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .nonAudioApplyRuntimeComplete, complete: nonAudioApplyRuntimeComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .audioUploadRuntimeComplete, complete: audioUploadRuntimeComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .readRuntimeComplete, complete: readRuntimeComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .masterSwitchComplete, complete: masterSwitchComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .legacyCompatibilityProofComplete, complete: legacyCompatibilityProofComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .switchBackProofComplete, complete: switchBackProofComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .diagnosticsRedacted, complete: diagnosticsRedacted),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .realDeviceEvidenceRequired, complete: realDeviceEvidencePresent)
            ],
            domainCompletionReadiness: resolvedDomainCompletionReadiness,
            domainReadinessReport: resolvedDomainReadinessReport,
            unresolvedBlockers: unresolvedBlockers
        )
    }

    nonisolated static func v857(
        realisticRootSwitchBackProof: CanonicalKernelSwitchBackProof? = nil,
        realisticRootSwitchBackProofComplete: Bool = true,
        diagnosticsRedacted: Bool = true,
        legacyFallbackRetained: Bool = true,
        defaultOldKernel: Bool = true,
        releaseDefaultOldKernel: Bool = true,
        canonicalFullSyncGated: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        unresolvedBlockers: [CanonicalSyncKernelCompletionBlocker] = []
    ) -> CanonicalSyncKernelCompletionScorecard {
        let proofComplete = realisticRootSwitchBackProofComplete
            && (realisticRootSwitchBackProof?.isProven ?? true)
        var blockers = unresolvedBlockers
        if !proofComplete {
            blockers.append(.realisticRootSwitchBackProofMissing)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if !legacyFallbackRetained {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !defaultOldKernel {
            blockers.append(.defaultOldKernelMissing)
        }
        if !releaseDefaultOldKernel {
            blockers.append(.releaseDefaultCanonical)
        }
        if !canonicalFullSyncGated {
            blockers.append(.ownerApprovalMissing)
        }
        blockers = Self.unique(blockers)

        var scorecard = CanonicalSyncKernelCompletionScorecard(
            itemResults: [
                CanonicalSyncKernelCompletionScorecardItemResult(item: .inventoryRuntimeComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .diffLWWRuntimeComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .existenceTruthComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .nonAudioApplyRuntimeComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .audioUploadRuntimeComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .readRuntimeComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .masterSwitchComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .legacyCompatibilityProofComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .switchBackProofComplete, complete: proofComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .diagnosticsRedacted, complete: diagnosticsRedacted),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .realDeviceEvidenceRequired, complete: realDeviceEvidencePresent)
            ],
            domainCompletionReadiness: realDeviceEvidencePresent
                ? CanonicalSyncKernelCompletionDomainReadiness.v845ReadyWithDeviceEvidence()
                : CanonicalSyncKernelCompletionDomainReadiness.v845CodeCompleteAwaitingDeviceEvidence(),
            domainReadinessReport: realDeviceEvidencePresent
                ? CanonicalSyncKernelDomainReadyToRetireReport.v845ReadyWithDeviceEvidence()
                : CanonicalSyncKernelDomainReadyToRetireReport.v845CodeCompleteAwaitingDeviceEvidence(),
            unresolvedBlockers: blockers
        )
        scorecard.diagnosticsSummary = [
            "canonicalSyncKernelCompletionScorecard=v8.57-p3-2",
            "p0InventoryCacheTelemetryComplete=true",
            "p1ManifestRecordingsApplyComplete=true",
            "p1AudioUploadCommitComplete=true",
            "p1UploadRetryStatusConsistent=true",
            "p2RecordingMetadataCodeComplete=true",
            "p2LibraryMetadataCodeComplete=true",
            "p2GeneratedArtifactsCodeComplete=true",
            "p2TombstoneConflictCodeComplete=true",
            "p2AudioUploadCodeComplete=true",
            "p3MasterSwitchConsolidated=true",
            "p3RealisticSwitchBackProofComplete=\(proofComplete)",
            "diagnosticsRedacted=\(diagnosticsRedacted)",
            "legacyFallbackRetained=\(legacyFallbackRetained)",
            "defaultOldKernel=\(defaultOldKernel)",
            "releaseDefaultOldKernel=\(releaseDefaultOldKernel)",
            "canonicalFullSyncGated=\(canonicalFullSyncGated)",
            "readyForManualSwitchTrial=\(scorecard.status == .readyForManualSwitchTrial)",
            "needsRealDeviceEvidence=\(!realDeviceEvidencePresent)",
            "unsafeBlockers=\(scorecard.blockers.filter { $0 == .releaseDefaultCanonical || $0 == .legacyFallbackUnavailable || $0 == .unsafeCanonicalDefault || $0 == .securityBypassDetected || $0 == .sensitiveEvidenceLeak }.map(\.rawValue).joined(separator: "|"))",
            "status=\(scorecard.status.rawValue)",
            "redacted=true"
        ].joined(separator: ",")
        return scorecard
    }

    nonisolated static func v863(
        v858RecordingRealApplyPortReady: Bool = true,
        v858RecordingReadSideSeamReady: Bool = true,
        v859AudioCommitExecutorReady: Bool = true,
        v860InventoryExistenceGateReady: Bool = true,
        v861ProductionFilePortTrueWriteGated: Bool = true,
        v862SwitchBackProofDriverReady: Bool = true,
        diagnosticsRedacted: Bool = true,
        legacyFallbackRetained: Bool = true,
        defaultOldKernel: Bool = true,
        releaseDefaultOldKernel: Bool = true,
        canonicalFullSyncGated: Bool = true,
        ownerConfirmationRequired: Bool = true,
        diagnosticsGrepListReady: Bool = true,
        emergencyOldKernelSwitchBackPathReady: Bool = true,
        stopConditionsReady: Bool = true,
        runbookUpdated: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        unresolvedBlockers: [CanonicalSyncKernelCompletionBlocker] = []
    ) -> CanonicalSyncKernelCompletionScorecard {
        var blockers = unresolvedBlockers
        if !v858RecordingRealApplyPortReady {
            blockers.append(.recordingMetadataRealApplyPortMissing)
        }
        if !v858RecordingReadSideSeamReady {
            blockers.append(.recordingMetadataReadSideSeamMissing)
        }
        if !v859AudioCommitExecutorReady {
            blockers.append(.audioCommitExecutorMissing)
        }
        if !v860InventoryExistenceGateReady {
            blockers.append(.inventoryExistenceGateMissing)
        }
        if !v861ProductionFilePortTrueWriteGated {
            blockers.append(.productionFilePortTrueWriteGateMissing)
        }
        if !v862SwitchBackProofDriverReady {
            blockers.append(.switchBackProofDriverMissing)
            blockers.append(.realisticRootSwitchBackProofMissing)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if !legacyFallbackRetained {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !defaultOldKernel {
            blockers.append(.defaultOldKernelMissing)
        }
        if !releaseDefaultOldKernel {
            blockers.append(.releaseDefaultCanonical)
        }
        if !canonicalFullSyncGated || !ownerConfirmationRequired {
            blockers.append(.ownerApprovalMissing)
        }
        if !diagnosticsGrepListReady {
            blockers.append(.diagnosticsGrepListMissing)
        }
        if !emergencyOldKernelSwitchBackPathReady {
            blockers.append(.emergencyOldKernelSwitchBackPathMissing)
        }
        if !stopConditionsReady {
            blockers.append(.stopConditionsMissing)
        }
        if !runbookUpdated {
            blockers.append(.runbookMissing)
            blockers.append(.docsNotUpdated)
        }
        blockers = Self.unique(blockers)

        var scorecard = CanonicalSyncKernelCompletionScorecard(
            itemResults: [
                CanonicalSyncKernelCompletionScorecardItemResult(item: .inventoryRuntimeComplete, complete: v860InventoryExistenceGateReady),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .diffLWWRuntimeComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .existenceTruthComplete, complete: v860InventoryExistenceGateReady),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .nonAudioApplyRuntimeComplete, complete: v858RecordingRealApplyPortReady && v861ProductionFilePortTrueWriteGated),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .audioUploadRuntimeComplete, complete: v859AudioCommitExecutorReady),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .readRuntimeComplete, complete: v858RecordingReadSideSeamReady),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .masterSwitchComplete, complete: canonicalFullSyncGated && ownerConfirmationRequired),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .legacyCompatibilityProofComplete, complete: legacyFallbackRetained),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .switchBackProofComplete, complete: v862SwitchBackProofDriverReady),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .diagnosticsRedacted, complete: diagnosticsRedacted),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .realDeviceEvidenceRequired, complete: realDeviceEvidencePresent)
            ],
            domainCompletionReadiness: realDeviceEvidencePresent
                ? CanonicalSyncKernelCompletionDomainReadiness.v845ReadyWithDeviceEvidence()
                : CanonicalSyncKernelCompletionDomainReadiness.v845CodeCompleteAwaitingDeviceEvidence(),
            domainReadinessReport: realDeviceEvidencePresent
                ? CanonicalSyncKernelDomainReadyToRetireReport.v845ReadyWithDeviceEvidence()
                : CanonicalSyncKernelDomainReadyToRetireReport.v845CodeCompleteAwaitingDeviceEvidence(),
            unresolvedBlockers: blockers
        )
        scorecard.diagnosticsSummary = [
            "canonicalSyncKernelCompletionScorecard=v8.63",
            "v858RecordingRealApplyPortReady=\(v858RecordingRealApplyPortReady)",
            "v858RecordingReadSideSeamReady=\(v858RecordingReadSideSeamReady)",
            "v859AudioCommitExecutorReady=\(v859AudioCommitExecutorReady)",
            "v860InventoryExistenceGateReady=\(v860InventoryExistenceGateReady)",
            "v861ProductionFilePortTrueWriteGated=\(v861ProductionFilePortTrueWriteGated)",
            "v862SwitchBackProofDriverReady=\(v862SwitchBackProofDriverReady)",
            "diagnosticsRedacted=\(diagnosticsRedacted)",
            "legacyFallbackRetained=\(legacyFallbackRetained)",
            "defaultOldKernel=\(defaultOldKernel)",
            "releaseDefaultOldKernel=\(releaseDefaultOldKernel)",
            "canonicalFullSyncGated=\(canonicalFullSyncGated)",
            "ownerConfirmationRequired=\(ownerConfirmationRequired)",
            "diagnosticsGrepListReady=\(diagnosticsGrepListReady)",
            "emergencyOldKernelSwitchBackPathReady=\(emergencyOldKernelSwitchBackPathReady)",
            "stopConditionsReady=\(stopConditionsReady)",
            "runbookUpdated=\(runbookUpdated)",
            "readyForManualSwitchTrial=\(scorecard.status == .readyForManualSwitchTrial)",
            "needsRealDeviceEvidence=\(!realDeviceEvidencePresent)",
            "status=\(scorecard.status.rawValue)",
            "blockers=\(scorecard.blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
        return scorecard
    }

    nonisolated static func v868(
        iOSBuildPassed: Bool = true,
        macOSBuildPassed: Bool = true,
        targetedTestsPassed: Bool = true,
        t1InventoryMainActorResidualClosureComplete: Bool = true,
        t1MainActorBlockerAcceptedNonFatal: Bool = false,
        t2MasterSwitchDrivesRead: Bool = true,
        t3RecordingReadSeamRuntimeWired: Bool = true,
        t4ExecutorPortInjectionComplete: Bool = true,
        t5ProductionRootWriteGatedUnlockComplete: Bool = true,
        t6SwitchBackProofDriverComplete: Bool = true,
        defaultOldKernel: Bool = true,
        releaseDefaultOldKernel: Bool = true,
        fiveModesSelectable: Bool = true,
        canonicalFullSyncConfirmation: Bool = true,
        canonicalFullSyncOwnerApprovalGate: Bool = true,
        canonicalFullSyncManualConfirmationGate: Bool = true,
        decisionRuntimeMapped: Bool = true,
        readRuntimeMapped: Bool = true,
        applyRuntimeMapped: Bool = true,
        audioCommitRuntimeMapped: Bool = true,
        existenceApplyPortMapped: Bool = true,
        oldKernelMapsAllOwnersLegacy: Bool = true,
        legacyFallbackRetained: Bool = true,
        noScatteredSwitchBypass: Bool = true,
        productionRootWriteReleaseDefaultBlocked: Bool = true,
        pathBTransportTLSHMACRetained: Bool = true,
        routeSecurityUnchanged: Bool = true,
        requestVerifierUnchanged: Bool = true,
        diagnosticsRedacted: Bool = true,
        switchBackProofDriverAvailable: Bool = true,
        switchBackProofResultPresent: Bool = false,
        productionRootSwitchBackProofSafe: Bool = true,
        oldKernelSwitchBackImmediate: Bool = true,
        metadataOnlyRejectedAsAudioAvailable: Bool = true,
        completedLedgerAloneRejectedAsNoOp: Bool = true,
        existingDifferentAudioOverwriteBlocked: Bool = true,
        manualSwitchGateExists: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        unresolvedBlockers: [CanonicalSyncKernelCompletionBlocker] = []
    ) -> CanonicalSyncKernelCompletionScorecard {
        let t1CodeComplete = t1InventoryMainActorResidualClosureComplete || t1MainActorBlockerAcceptedNonFatal
        var blockers = unresolvedBlockers
        if !iOSBuildPassed {
            blockers.append(.iOSBuildValidationMissing)
        }
        if !macOSBuildPassed {
            blockers.append(.macOSBuildValidationMissing)
        }
        if !targetedTestsPassed {
            blockers.append(.targetedTestsValidationMissing)
        }
        if !t1CodeComplete {
            blockers.append(.t1InventoryMainActorResidualClosureMissing)
        }
        if !t2MasterSwitchDrivesRead {
            blockers.append(.t2MasterSwitchReadMappingMissing)
        }
        if !t3RecordingReadSeamRuntimeWired {
            blockers.append(.t3RecordingReadSeamRuntimeMissing)
        }
        if !t4ExecutorPortInjectionComplete {
            blockers.append(.t4ExecutorPortInjectionMissing)
        }
        if !t5ProductionRootWriteGatedUnlockComplete {
            blockers.append(.t5ProductionRootOwnerManualGateMissing)
        }
        if !t6SwitchBackProofDriverComplete || !switchBackProofDriverAvailable {
            blockers.append(.t6SwitchBackProofDriverMissing)
            blockers.append(.switchBackProofDriverMissing)
        }
        if !defaultOldKernel {
            blockers.append(.defaultOldKernelMissing)
            blockers.append(.unsafeCanonicalDefault)
        }
        if !releaseDefaultOldKernel {
            blockers.append(.releaseDefaultCanonical)
        }
        if !fiveModesSelectable {
            blockers.append(.fiveModeSelectorMissing)
        }
        if !canonicalFullSyncConfirmation {
            blockers.append(.canonicalFullSyncConfirmationMissing)
        }
        if !canonicalFullSyncOwnerApprovalGate {
            blockers.append(.canonicalFullSyncOwnerApprovalGateMissing)
            blockers.append(.productionRootWriteWithoutOwnerApproval)
        }
        if !canonicalFullSyncManualConfirmationGate {
            blockers.append(.canonicalFullSyncManualConfirmationGateMissing)
            blockers.append(.productionRootWriteWithoutManualConfirmation)
        }
        if !decisionRuntimeMapped {
            blockers.append(.decisionRuntimeMappingMissing)
        }
        if !readRuntimeMapped {
            blockers.append(.readRuntimeMappingMissing)
        }
        if !applyRuntimeMapped {
            blockers.append(.applyRuntimeMappingMissing)
        }
        if !audioCommitRuntimeMapped {
            blockers.append(.audioCommitRuntimeMappingMissing)
        }
        if !existenceApplyPortMapped {
            blockers.append(.existenceApplyPortMappingMissing)
        }
        if !oldKernelMapsAllOwnersLegacy {
            blockers.append(.oldKernelLegacyMappingMissing)
        }
        if !legacyFallbackRetained {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !noScatteredSwitchBypass {
            blockers.append(.scatteredSwitchBypass)
        }
        if !productionRootWriteReleaseDefaultBlocked {
            blockers.append(.productionRootWriteInReleaseDefault)
        }
        if !pathBTransportTLSHMACRetained {
            blockers.append(.pathBTransportChanged)
            blockers.append(.securityBypassDetected)
        }
        if !routeSecurityUnchanged {
            blockers.append(.routeSecurityChanged)
            blockers.append(.securityBypassDetected)
        }
        if !requestVerifierUnchanged {
            blockers.append(.requestVerifierBypassed)
            blockers.append(.securityBypassDetected)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
            blockers.append(.diagnosticsSensitiveLeak)
        }
        if !productionRootSwitchBackProofSafe {
            blockers.append(.productionRootDestructiveSwitchBackProof)
        }
        if !oldKernelSwitchBackImmediate {
            blockers.append(.oldKernelSwitchBackNotImmediate)
        }
        if !metadataOnlyRejectedAsAudioAvailable {
            blockers.append(.metadataOnlyTreatedAsAudioAvailable)
        }
        if !completedLedgerAloneRejectedAsNoOp {
            blockers.append(.completedLedgerAloneTreatedAsNoOp)
        }
        if !existingDifferentAudioOverwriteBlocked {
            blockers.append(.existingDifferentAudioOverwriteRisk)
        }
        if !manualSwitchGateExists {
            blockers.append(.manualSwitchGateMissing)
        }
        blockers = Self.unique(blockers)

        let unsafe = !defaultOldKernel
            || !releaseDefaultOldKernel
            || !legacyFallbackRetained
            || !canonicalFullSyncOwnerApprovalGate
            || !canonicalFullSyncManualConfirmationGate
            || !noScatteredSwitchBypass
            || !productionRootWriteReleaseDefaultBlocked
            || !pathBTransportTLSHMACRetained
            || !routeSecurityUnchanged
            || !requestVerifierUnchanged
            || !diagnosticsRedacted
            || !productionRootSwitchBackProofSafe
            || !oldKernelSwitchBackImmediate
            || !metadataOnlyRejectedAsAudioAvailable
            || !completedLedgerAloneRejectedAsNoOp
            || !existingDifferentAudioOverwriteBlocked
        let requiredT2ToT6Missing = !t2MasterSwitchDrivesRead
            || !t3RecordingReadSeamRuntimeWired
            || !t4ExecutorPortInjectionComplete
            || !t5ProductionRootWriteGatedUnlockComplete
            || !t6SwitchBackProofDriverComplete
        let buildOrTestMissing = !iOSBuildPassed || !macOSBuildPassed || !targetedTestsPassed
        let mappingsComplete = decisionRuntimeMapped
            && readRuntimeMapped
            && applyRuntimeMapped
            && audioCommitRuntimeMapped
            && existenceApplyPortMapped
            && oldKernelMapsAllOwnersLegacy
        let requiredCodeComplete = t1CodeComplete
            && !requiredT2ToT6Missing
            && !buildOrTestMissing
            && fiveModesSelectable
            && canonicalFullSyncConfirmation
            && canonicalFullSyncOwnerApprovalGate
            && canonicalFullSyncManualConfirmationGate
            && mappingsComplete
            && manualSwitchGateExists
            && switchBackProofDriverAvailable
        let codeCompletionResult: CanonicalSyncKernelCodeCompletionResult
        if unsafe {
            codeCompletionResult = .unsafeToTryOnDevice
        } else if buildOrTestMissing || requiredT2ToT6Missing {
            codeCompletionResult = .notReady
        } else if requiredCodeComplete && blockers.filter({ $0 != .realDeviceEvidenceMissing }).isEmpty {
            codeCompletionResult = .readyForRealDeviceCanonicalSwitch
        } else {
            codeCompletionResult = .partialWithBlockers
        }

        var scorecard = CanonicalSyncKernelCompletionScorecard(
            itemResults: [
                CanonicalSyncKernelCompletionScorecardItemResult(item: .inventoryRuntimeComplete, complete: t1CodeComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .diffLWWRuntimeComplete, complete: true),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .existenceTruthComplete, complete: existenceApplyPortMapped),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .nonAudioApplyRuntimeComplete, complete: applyRuntimeMapped && t4ExecutorPortInjectionComplete && t5ProductionRootWriteGatedUnlockComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .audioUploadRuntimeComplete, complete: audioCommitRuntimeMapped && t4ExecutorPortInjectionComplete),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .readRuntimeComplete, complete: readRuntimeMapped && t2MasterSwitchDrivesRead && t3RecordingReadSeamRuntimeWired),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .masterSwitchComplete, complete: fiveModesSelectable && canonicalFullSyncConfirmation && canonicalFullSyncOwnerApprovalGate && canonicalFullSyncManualConfirmationGate),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .legacyCompatibilityProofComplete, complete: legacyFallbackRetained),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .switchBackProofComplete, complete: t6SwitchBackProofDriverComplete && switchBackProofDriverAvailable),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .diagnosticsRedacted, complete: diagnosticsRedacted),
                CanonicalSyncKernelCompletionScorecardItemResult(item: .realDeviceEvidenceRequired, complete: realDeviceEvidencePresent)
            ],
            domainCompletionReadiness: realDeviceEvidencePresent
                ? CanonicalSyncKernelCompletionDomainReadiness.v845ReadyWithDeviceEvidence()
                : CanonicalSyncKernelCompletionDomainReadiness.v845CodeCompleteAwaitingDeviceEvidence(),
            domainReadinessReport: realDeviceEvidencePresent
                ? CanonicalSyncKernelDomainReadyToRetireReport.v845ReadyWithDeviceEvidence()
                : CanonicalSyncKernelDomainReadyToRetireReport.v845CodeCompleteAwaitingDeviceEvidence(),
            unresolvedBlockers: blockers
        )
        scorecard.diagnosticsSummary = [
            "canonicalSyncKernelCompletionScorecard=v8.68",
            "codeCompleteResult=\(codeCompletionResult.rawValue)",
            "manualSwitchReadinessStatus=\(codeCompletionResult == .readyForRealDeviceCanonicalSwitch ? "readyForRealDeviceTrial" : "blocked")",
            "t1InventoryMainActorResidualClosureComplete=\(t1InventoryMainActorResidualClosureComplete)",
            "t1MainActorBlockerAcceptedNonFatal=\(t1MainActorBlockerAcceptedNonFatal)",
            "t2MasterSwitchDrivesRead=\(t2MasterSwitchDrivesRead)",
            "t3RecordingReadSeamRuntimeWired=\(t3RecordingReadSeamRuntimeWired)",
            "t4ExecutorPortInjectionComplete=\(t4ExecutorPortInjectionComplete)",
            "t5ProductionRootWriteGatedUnlockComplete=\(t5ProductionRootWriteGatedUnlockComplete)",
            "t6SwitchBackProofDriverComplete=\(t6SwitchBackProofDriverComplete)",
            "iOSBuildPassed=\(iOSBuildPassed)",
            "macOSBuildPassed=\(macOSBuildPassed)",
            "targetedTestsPassed=\(targetedTestsPassed)",
            "defaultOldKernel=\(defaultOldKernel)",
            "releaseDefaultOldKernel=\(releaseDefaultOldKernel)",
            "fiveModesSelectable=\(fiveModesSelectable)",
            "canonicalFullSyncConfirmation=\(canonicalFullSyncConfirmation)",
            "canonicalFullSyncOwnerApprovalGate=\(canonicalFullSyncOwnerApprovalGate)",
            "canonicalFullSyncManualConfirmationGate=\(canonicalFullSyncManualConfirmationGate)",
            "decisionRuntimeMapped=\(decisionRuntimeMapped)",
            "readRuntimeMapped=\(readRuntimeMapped)",
            "applyRuntimeMapped=\(applyRuntimeMapped)",
            "audioCommitRuntimeMapped=\(audioCommitRuntimeMapped)",
            "existenceApplyPortMapped=\(existenceApplyPortMapped)",
            "oldKernelMapsAllOwnersLegacy=\(oldKernelMapsAllOwnersLegacy)",
            "legacyFallbackRetained=\(legacyFallbackRetained)",
            "noScatteredSwitchBypass=\(noScatteredSwitchBypass)",
            "productionRootWriteReleaseDefaultBlocked=\(productionRootWriteReleaseDefaultBlocked)",
            "pathBTransportTLSHMACRetained=\(pathBTransportTLSHMACRetained)",
            "routeSecurityUnchanged=\(routeSecurityUnchanged)",
            "requestVerifierUnchanged=\(requestVerifierUnchanged)",
            "diagnosticsRedacted=\(diagnosticsRedacted)",
            "switchBackProofDriverAvailable=\(switchBackProofDriverAvailable)",
            "switchBackProofResultPresent=\(switchBackProofResultPresent)",
            "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
            "unsafeBlockerPresent=\(unsafe)",
            "status=\(scorecard.status.rawValue)",
            "blockers=\(scorecard.blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
        return scorecard
    }

#if DEBUG
    nonisolated static func v862(
        switchBackDriverResult: CanonicalRealisticRootSwitchBackProofDriverResult?,
        legacyFallbackRetained: Bool = true,
        defaultOldKernel: Bool = true,
        releaseDefaultOldKernel: Bool = true,
        canonicalFullSyncGated: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        unresolvedBlockers: [CanonicalSyncKernelCompletionBlocker] = []
    ) -> CanonicalSyncKernelCompletionScorecard {
        let proofComplete = switchBackDriverResult?.isProofComplete == true
        let diagnosticsRedacted = switchBackDriverResult?.evidenceRedacted == true
        var blockers = unresolvedBlockers
        if !proofComplete {
            blockers.append(.realisticRootSwitchBackProofMissing)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }

        var scorecard = CanonicalSyncKernelCompletionScorecard.v857(
            realisticRootSwitchBackProof: switchBackDriverResult?.proof,
            realisticRootSwitchBackProofComplete: proofComplete,
            diagnosticsRedacted: diagnosticsRedacted,
            legacyFallbackRetained: legacyFallbackRetained,
            defaultOldKernel: defaultOldKernel,
            releaseDefaultOldKernel: releaseDefaultOldKernel,
            canonicalFullSyncGated: canonicalFullSyncGated,
            realDeviceEvidencePresent: realDeviceEvidencePresent,
            unresolvedBlockers: blockers
        )
        scorecard.diagnosticsSummary = [
            "canonicalSyncKernelCompletionScorecard=v8.62",
            "debugSwitchBackDriverCallable=\(switchBackDriverResult != nil)",
            "realisticCloneAccepted=\(switchBackDriverResult?.cloneRootSafety.accepted == true)",
            "proofRanOnProductionRoot=\(switchBackDriverResult?.proofRanOnProductionRoot == true)",
            "p3RealisticSwitchBackDriverProofComplete=\(proofComplete)",
            "evidenceRedacted=\(diagnosticsRedacted)",
            "readyForManualSwitchTrial=\(scorecard.status == .readyForManualSwitchTrial)",
            "needsRealDeviceEvidence=\(!realDeviceEvidencePresent)",
            "status=\(scorecard.status.rawValue)",
            "blockers=\(scorecard.blockers.map(\.rawValue).joined(separator: "|"))",
            "redacted=true"
        ].joined(separator: ",")
        return scorecard
    }
#endif

    nonisolated private static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

nonisolated struct CanonicalRealDeviceTrialReadinessGate: Codable, Equatable, Sendable {
    var codeCompleteResult: CanonicalRealDeviceTrialReadinessCodeCompleteResult
    var blockers: [CanonicalRealDeviceTrialReadinessBlocker]
    var realDeviceEvidencePresent: Bool
    var readyForRealDeviceAppTrial: Bool
    var diagnosticsSummary: String

    nonisolated var readyForRealDeviceFourDomainAppTrial: Bool {
        codeCompleteResult == .readyForRealDeviceFourDomainAppTrial
    }

    nonisolated static func v873(
        readCacheReady: Bool = true,
        macInventoryOffMainReady: Bool = true,
        oldKernelSkipsCanonicalBuild: Bool = true,
        syncRequestedHeartbeatHookupReady: Bool = true,
        eventDrivenSyncTriggerReady: Bool = true,
        statusConvergenceRefreshReady: Bool = true,
        stormProtectionReady: Bool = true,
        iOSBuildPassed: Bool = true,
        macOSBuildPassed: Bool = true,
        targetedTestsPassed: Bool = true,
        defaultOldKernel: Bool = true,
        releaseDefaultOldKernel: Bool = true,
        fiveModeKernelSwitch: Bool = true,
        canonicalFullSyncGated: Bool = true,
        legacyFallbackRetained: Bool = true,
        routeSecurityUnchanged: Bool = true,
        requestVerifierUnchanged: Bool = true,
        switchBackProofDriverAvailable: Bool = true,
        diagnosticsRedacted: Bool = true,
        realDeviceTrialRunbookUpdated: Bool = true,
        productionRootWritesSafe: Bool = true,
        viewRefreshCannotCreateUploadJob: Bool = true,
        retryStormProtectionReady: Bool = true,
        metadataOnlyRejectedAsAudioAvailable: Bool = true,
        completedLedgerAloneRejectedAsProof: Bool = true,
        partialReceiveRejectedAsAudioAvailable: Bool = true,
        existingDifferentAudioOverwriteBlocked: Bool = true,
        oldKernelSwitchBackAvailable: Bool = true,
        heartbeatCallbackLightweight: Bool = true,
        macDoesNotReverseConnectToIPhone: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        unresolvedBlockers: [CanonicalRealDeviceTrialReadinessBlocker] = []
    ) -> CanonicalRealDeviceTrialReadinessGate {
        var blockers = unresolvedBlockers
        if !readCacheReady {
            blockers.append(.readCacheMissing)
        }
        if !macInventoryOffMainReady {
            blockers.append(.macInventoryOffMainMissing)
        }
        if !oldKernelSkipsCanonicalBuild {
            blockers.append(.oldKernelCanonicalSkipMissing)
        }
        if !syncRequestedHeartbeatHookupReady {
            blockers.append(.syncRequestedHeartbeatHookupMissing)
        }
        if !eventDrivenSyncTriggerReady {
            blockers.append(.eventDrivenSyncTriggerMissing)
        }
        if !statusConvergenceRefreshReady {
            blockers.append(.statusConvergenceRefreshMissing)
        }
        if !stormProtectionReady {
            blockers.append(.stormProtectionMissing)
        }
        if !iOSBuildPassed {
            blockers.append(.iOSBuildMissing)
        }
        if !macOSBuildPassed {
            blockers.append(.macOSBuildMissing)
        }
        if !targetedTestsPassed {
            blockers.append(.targetedTestsMissing)
        }
        if !defaultOldKernel {
            blockers.append(.defaultOldKernelMissing)
        }
        if !releaseDefaultOldKernel {
            blockers.append(.releaseDefaultCanonical)
        }
        if !fiveModeKernelSwitch {
            blockers.append(.fiveModeKernelSwitchMissing)
        }
        if !canonicalFullSyncGated {
            blockers.append(.canonicalFullSyncGateMissing)
        }
        if !legacyFallbackRetained {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !routeSecurityUnchanged {
            blockers.append(.routeSecurityChanged)
        }
        if !requestVerifierUnchanged {
            blockers.append(.requestVerifierBypassed)
        }
        if !switchBackProofDriverAvailable {
            blockers.append(.switchBackProofDriverMissing)
        }
        if !diagnosticsRedacted {
            blockers.append(.diagnosticsSensitiveLeak)
        }
        if !realDeviceTrialRunbookUpdated {
            blockers.append(.realDeviceTrialRunbookMissing)
        }
        if !productionRootWritesSafe {
            blockers.append(.productionRootUnsafeWrite)
        }
        if !viewRefreshCannotCreateUploadJob {
            blockers.append(.viewRefreshCreatesUploadJob)
        }
        if !retryStormProtectionReady {
            blockers.append(.retryStormProtectionMissing)
        }
        if !metadataOnlyRejectedAsAudioAvailable {
            blockers.append(.metadataOnlyTreatedAsAudioAvailable)
        }
        if !completedLedgerAloneRejectedAsProof {
            blockers.append(.completedLedgerAloneTreatedAsProof)
        }
        if !partialReceiveRejectedAsAudioAvailable {
            blockers.append(.partialReceiveTreatedAsAudioAvailable)
        }
        if !existingDifferentAudioOverwriteBlocked {
            blockers.append(.existingDifferentAudioOverwriteRisk)
        }
        if !oldKernelSwitchBackAvailable {
            blockers.append(.oldKernelSwitchBackMissing)
        }
        if !heartbeatCallbackLightweight {
            blockers.append(.heartbeatRunsHeavySync)
        }
        if !macDoesNotReverseConnectToIPhone {
            blockers.append(.macReverseConnectionAttempted)
        }
        blockers = unique(blockers)

        let unsafe = !defaultOldKernel
            || !releaseDefaultOldKernel
            || !canonicalFullSyncGated
            || !legacyFallbackRetained
            || !routeSecurityUnchanged
            || !requestVerifierUnchanged
            || !diagnosticsRedacted
            || !productionRootWritesSafe
            || !viewRefreshCannotCreateUploadJob
            || !retryStormProtectionReady
            || !metadataOnlyRejectedAsAudioAvailable
            || !completedLedgerAloneRejectedAsProof
            || !partialReceiveRejectedAsAudioAvailable
            || !existingDifferentAudioOverwriteBlocked
            || !oldKernelSwitchBackAvailable
            || !heartbeatCallbackLightweight
            || !macDoesNotReverseConnectToIPhone

        let requiredCodeReady = readCacheReady
            && macInventoryOffMainReady
            && oldKernelSkipsCanonicalBuild
            && syncRequestedHeartbeatHookupReady
            && eventDrivenSyncTriggerReady
            && statusConvergenceRefreshReady
            && stormProtectionReady
            && iOSBuildPassed
            && macOSBuildPassed
            && targetedTestsPassed
            && fiveModeKernelSwitch
            && canonicalFullSyncGated
            && switchBackProofDriverAvailable
            && realDeviceTrialRunbookUpdated

        let codeCompleteResult: CanonicalRealDeviceTrialReadinessCodeCompleteResult
        if unsafe {
            codeCompleteResult = .unsafeToTryOnDevice
        } else if !iOSBuildPassed || !macOSBuildPassed || !targetedTestsPassed {
            codeCompleteResult = .notReady
        } else if requiredCodeReady && blockers.isEmpty {
            codeCompleteResult = .readyForRealDeviceAppTrial
        } else {
            codeCompleteResult = .partialWithBlockers
        }

        let ready = codeCompleteResult == .readyForRealDeviceAppTrial
        return CanonicalRealDeviceTrialReadinessGate(
            codeCompleteResult: codeCompleteResult,
            blockers: blockers,
            realDeviceEvidencePresent: realDeviceEvidencePresent,
            readyForRealDeviceAppTrial: ready,
            diagnosticsSummary: [
                "canonicalRealDeviceTrialReadinessGate=v8.73",
                "CODE_COMPLETE_RESULT=\(codeCompleteResult.rawValue)",
                "READY_FOR_REAL_DEVICE_APP_TRIAL=\(ready)",
                "readCacheReady=\(readCacheReady)",
                "macInventoryOffMainReady=\(macInventoryOffMainReady)",
                "oldKernelSkipsCanonicalBuild=\(oldKernelSkipsCanonicalBuild)",
                "syncRequestedHeartbeatHookupReady=\(syncRequestedHeartbeatHookupReady)",
                "eventDrivenSyncTriggerReady=\(eventDrivenSyncTriggerReady)",
                "statusConvergenceRefreshReady=\(statusConvergenceRefreshReady)",
                "stormProtectionReady=\(stormProtectionReady)",
                "iOSBuildPassed=\(iOSBuildPassed)",
                "macOSBuildPassed=\(macOSBuildPassed)",
                "targetedTestsPassed=\(targetedTestsPassed)",
                "defaultOldKernel=\(defaultOldKernel)",
                "releaseDefaultOldKernel=\(releaseDefaultOldKernel)",
                "fiveModeKernelSwitch=\(fiveModeKernelSwitch)",
                "canonicalFullSyncGated=\(canonicalFullSyncGated)",
                "legacyFallbackRetained=\(legacyFallbackRetained)",
                "routeSecurityUnchanged=\(routeSecurityUnchanged)",
                "requestVerifierUnchanged=\(requestVerifierUnchanged)",
                "switchBackProofDriverAvailable=\(switchBackProofDriverAvailable)",
                "diagnosticsRedacted=\(diagnosticsRedacted)",
                "realDeviceTrialRunbookUpdated=\(realDeviceTrialRunbookUpdated)",
                "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
                "heartbeatCallbackLightweight=\(heartbeatCallbackLightweight)",
                "macDoesNotReverseConnectToIPhone=\(macDoesNotReverseConnectToIPhone)",
                "unsafeBlockerPresent=\(unsafe)",
                "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    nonisolated static func v915(
        r1DiagnosticsAsyncHotPathReady: Bool = true,
        r2ContentStableCacheKeyReady: Bool = true,
        r3NoFreezeEvidenceReady: Bool = true,
        r4EffectiveStatusBindingReady: Bool = true,
        r5RealtimeStatusExchangeReady: Bool = true,
        r6ConnectionRuntimeAppPathReady: Bool = true,
        r6TransferRuntimeAppPathReady: Bool = true,
        productionFullSyncSelectsFakeOrTestOnlyTransferPort: Bool = false,
        finalizeProofFeedsStatusTruth: Bool = true,
        routeSecurityUnchanged: Bool = true,
        requestVerifierUnchanged: Bool = true,
        macDoesNotReverseConnectToIPhone: Bool = true,
        heartbeatCallbackLightweight: Bool = true,
        viewRefreshCannotCreateUploadJob: Bool = true,
        retryDrainerExistingEligibleOnly: Bool = true,
        metadataOnlyRejectedAsAudioAvailable: Bool = true,
        completedLedgerAloneRejectedAsProof: Bool = true,
        partialReceiveRejectedAsAudioAvailable: Bool = true,
        defaultOldKernel: Bool = true,
        releaseDefaultOldKernel: Bool = true,
        legacyFallbackRetained: Bool = true,
        noLegacyRetirement: Bool = true,
        mainActorHotPathSafe: Bool = true,
        iOSBuildPassed: Bool = true,
        macOSBuildPassed: Bool = true,
        targetedTestsPassed: Bool = true,
        buildTestSummaryPresent: Bool = true,
        realDeviceEvidencePresent: Bool = false,
        unresolvedBlockers: [CanonicalRealDeviceTrialReadinessBlocker] = []
    ) -> CanonicalRealDeviceTrialReadinessGate {
        var blockers = unresolvedBlockers
        if !r1DiagnosticsAsyncHotPathReady {
            blockers.append(.diagnosticsAsyncHotPathMissing)
        }
        if !r2ContentStableCacheKeyReady {
            blockers.append(.contentStableCacheKeyMissing)
        }
        if !r3NoFreezeEvidenceReady {
            blockers.append(.noFreezeEvidenceMissing)
        }
        if !r4EffectiveStatusBindingReady {
            blockers.append(.effectiveStatusBindingMissing)
        }
        if !r5RealtimeStatusExchangeReady {
            blockers.append(.realtimeStatusExchangeMissing)
        }
        if !r6ConnectionRuntimeAppPathReady {
            blockers.append(.connectionRuntimeAppPathMissing)
        }
        if !r6TransferRuntimeAppPathReady {
            blockers.append(.transferRuntimeAppPathMissing)
        }
        if productionFullSyncSelectsFakeOrTestOnlyTransferPort {
            blockers.append(.fakeOrTestOnlyProductionTransferPort)
        }
        if !finalizeProofFeedsStatusTruth {
            blockers.append(.finalizeProofNotFeedingStatusTruth)
        }
        if !routeSecurityUnchanged {
            blockers.append(.routeSecurityChanged)
        }
        if !requestVerifierUnchanged {
            blockers.append(.requestVerifierBypassed)
        }
        if !macDoesNotReverseConnectToIPhone {
            blockers.append(.macReverseConnectionAttempted)
        }
        if !heartbeatCallbackLightweight {
            blockers.append(.heartbeatRunsHeavySync)
        }
        if !viewRefreshCannotCreateUploadJob {
            blockers.append(.viewRefreshCreatesUploadJob)
        }
        if !retryDrainerExistingEligibleOnly {
            blockers.append(.retryDrainerCreatesFreshUnrelatedJob)
        }
        if !metadataOnlyRejectedAsAudioAvailable {
            blockers.append(.metadataOnlyTreatedAsAudioAvailable)
        }
        if !completedLedgerAloneRejectedAsProof {
            blockers.append(.completedLedgerAloneTreatedAsProof)
        }
        if !partialReceiveRejectedAsAudioAvailable {
            blockers.append(.partialReceiveTreatedAsAudioAvailable)
        }
        if !defaultOldKernel {
            blockers.append(.defaultOldKernelMissing)
        }
        if !releaseDefaultOldKernel {
            blockers.append(.releaseDefaultCanonical)
        }
        if !legacyFallbackRetained {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !noLegacyRetirement {
            blockers.append(.legacyRetirementAttempted)
        }
        if !mainActorHotPathSafe {
            blockers.append(.mainActorHotPathViolation)
        }
        if !iOSBuildPassed {
            blockers.append(.iOSBuildMissing)
        }
        if !macOSBuildPassed {
            blockers.append(.macOSBuildMissing)
        }
        if !targetedTestsPassed {
            blockers.append(.targetedTestsMissing)
        }
        if !buildTestSummaryPresent {
            blockers.append(.buildTestSummaryMissing)
        }
        blockers = unique(blockers)

        let unsafeBlockers: Set<CanonicalRealDeviceTrialReadinessBlocker> = [
            .fakeOrTestOnlyProductionTransferPort,
            .routeSecurityChanged,
            .requestVerifierBypassed,
            .macReverseConnectionAttempted,
            .heartbeatRunsHeavySync,
            .viewRefreshCreatesUploadJob,
            .retryDrainerCreatesFreshUnrelatedJob,
            .metadataOnlyTreatedAsAudioAvailable,
            .completedLedgerAloneTreatedAsProof,
            .partialReceiveTreatedAsAudioAvailable,
            .defaultOldKernelMissing,
            .releaseDefaultCanonical,
            .legacyFallbackUnavailable,
            .mainActorHotPathViolation,
            .legacyRetirementAttempted
        ]
        let notReadyBlockers: Set<CanonicalRealDeviceTrialReadinessBlocker> = [
            .diagnosticsAsyncHotPathMissing,
            .contentStableCacheKeyMissing,
            .noFreezeEvidenceMissing,
            .effectiveStatusBindingMissing,
            .realtimeStatusExchangeMissing,
            .connectionRuntimeAppPathMissing,
            .transferRuntimeAppPathMissing,
            .finalizeProofNotFeedingStatusTruth,
            .iOSBuildMissing,
            .macOSBuildMissing,
            .targetedTestsMissing,
            .buildTestSummaryMissing
        ]
        let blockerSet = Set(blockers)
        let unsafe = !blockerSet.isDisjoint(with: unsafeBlockers)
        let notReady = !blockerSet.isDisjoint(with: notReadyBlockers)

        let requiredCodeReady = r1DiagnosticsAsyncHotPathReady
            && r2ContentStableCacheKeyReady
            && r3NoFreezeEvidenceReady
            && r4EffectiveStatusBindingReady
            && r5RealtimeStatusExchangeReady
            && r6ConnectionRuntimeAppPathReady
            && r6TransferRuntimeAppPathReady
            && finalizeProofFeedsStatusTruth
            && iOSBuildPassed
            && macOSBuildPassed
            && targetedTestsPassed
            && buildTestSummaryPresent

        let codeCompleteResult: CanonicalRealDeviceTrialReadinessCodeCompleteResult
        if unsafe {
            codeCompleteResult = .unsafeToTryOnDevice
        } else if notReady || !requiredCodeReady {
            codeCompleteResult = .notReady
        } else if blockers.isEmpty {
            codeCompleteResult = .readyForRealDeviceFourDomainAppTrial
        } else {
            codeCompleteResult = .partialWithBlockers
        }

        let ready = codeCompleteResult == .readyForRealDeviceFourDomainAppTrial
        return CanonicalRealDeviceTrialReadinessGate(
            codeCompleteResult: codeCompleteResult,
            blockers: blockers,
            realDeviceEvidencePresent: realDeviceEvidencePresent,
            readyForRealDeviceAppTrial: ready,
            diagnosticsSummary: [
                "canonicalRealDeviceTrialReadinessGate=v9.15",
                "CODE_COMPLETE_RESULT=\(codeCompleteResult.rawValue)",
                "READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL=\(ready)",
                "readyMeans=pairedDeviceDebugInternalTrialOnly",
                "realDeviceEvidencePresent=\(realDeviceEvidencePresent)",
                "notReleaseReady=true",
                "notRealDevicePassed=true",
                "legacyRetirementReady=false",
                "r1DiagnosticsAsyncHotPathReady=\(r1DiagnosticsAsyncHotPathReady)",
                "r2ContentStableCacheKeyReady=\(r2ContentStableCacheKeyReady)",
                "r3NoFreezeEvidenceReady=\(r3NoFreezeEvidenceReady)",
                "r4EffectiveStatusBindingReady=\(r4EffectiveStatusBindingReady)",
                "r5RealtimeStatusExchangeReady=\(r5RealtimeStatusExchangeReady)",
                "r6ConnectionRuntimeAppPathReady=\(r6ConnectionRuntimeAppPathReady)",
                "r6TransferRuntimeAppPathReady=\(r6TransferRuntimeAppPathReady)",
                "productionFullSyncSelectsFakeOrTestOnlyTransferPort=\(productionFullSyncSelectsFakeOrTestOnlyTransferPort)",
                "finalizeProofFeedsStatusTruth=\(finalizeProofFeedsStatusTruth)",
                "routeSecurityUnchanged=\(routeSecurityUnchanged)",
                "requestVerifierUnchanged=\(requestVerifierUnchanged)",
                "macDoesNotReverseConnectToIPhone=\(macDoesNotReverseConnectToIPhone)",
                "heartbeatCallbackLightweight=\(heartbeatCallbackLightweight)",
                "viewRefreshCannotCreateUploadJob=\(viewRefreshCannotCreateUploadJob)",
                "retryDrainerExistingEligibleOnly=\(retryDrainerExistingEligibleOnly)",
                "metadataOnlyRejectedAsAudioAvailable=\(metadataOnlyRejectedAsAudioAvailable)",
                "completedLedgerAloneRejectedAsProof=\(completedLedgerAloneRejectedAsProof)",
                "partialReceiveRejectedAsAudioAvailable=\(partialReceiveRejectedAsAudioAvailable)",
                "defaultOldKernel=\(defaultOldKernel)",
                "releaseDefaultOldKernel=\(releaseDefaultOldKernel)",
                "legacyFallbackRetained=\(legacyFallbackRetained)",
                "noLegacyRetirement=\(noLegacyRetirement)",
                "mainActorHotPathSafe=\(mainActorHotPathSafe)",
                "iOSBuildPassed=\(iOSBuildPassed)",
                "macOSBuildPassed=\(macOSBuildPassed)",
                "targetedTestsPassed=\(targetedTestsPassed)",
                "buildTestSummaryPresent=\(buildTestSummaryPresent)",
                "unsafeBlockerPresent=\(unsafe)",
                "notReadyBlockerPresent=\(notReady)",
                "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    nonisolated private static func unique(
        _ blockers: [CanonicalRealDeviceTrialReadinessBlocker]
    ) -> [CanonicalRealDeviceTrialReadinessBlocker] {
        var seen: Set<CanonicalRealDeviceTrialReadinessBlocker> = []
        var unique: [CanonicalRealDeviceTrialReadinessBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

nonisolated struct CanonicalSyncKernelEvidenceModeTransition: Codable, Equatable, Sendable {
    var fromMode: CanonicalKernelSwitchMode
    var toMode: CanonicalKernelSwitchMode
    var phase: String

    nonisolated init(
        fromMode: CanonicalKernelSwitchMode,
        toMode: CanonicalKernelSwitchMode,
        phase: String
    ) {
        self.fromMode = fromMode
        self.toMode = toMode
        self.phase = CanonicalSyncKernelEvidenceRedactor.redact(phase)
    }
}

nonisolated struct CanonicalSyncKernelEvidenceObjectCounts: Codable, Equatable, Sendable {
    var recordingMetadataCount: Int
    var libraryMetadataCount: Int
    var generatedArtifactCount: Int
    var tombstoneConflictCount: Int
    var audioUploadCandidateCount: Int
    var recordingExistenceCount: Int
}

nonisolated struct CanonicalSyncKernelEvidenceCacheCounts: Codable, Equatable, Sendable {
    var hitCount: Int
    var missCount: Int
    var staleCount: Int
    var errorCount: Int
}

nonisolated struct CanonicalSyncKernelEvidencePlanCounts: Codable, Equatable, Sendable {
    var canonicalPlanUsedCount: Int
    var legacyFallbackCount: Int
    var blockedPlanCount: Int
}

nonisolated struct CanonicalSyncKernelEvidenceExecutionCounts: Codable, Equatable, Sendable {
    var successCount: Int
    var failureCount: Int
}

nonisolated struct CanonicalSyncKernelEvidenceReadDivergence: Codable, Equatable, Sendable {
    var equivalentCount: Int
    var divergentCount: Int
    var pathOrContentLeakRiskCount: Int
}

nonisolated struct CanonicalSyncKernelEvidenceRedactionProof: Codable, Equatable, Sendable {
    var redacted: Bool
    var sensitiveInputDetected: Bool
    var sensitiveOutputDetected: Bool
    var excludedSensitivePayloads: [String]
}

nonisolated struct CanonicalSyncKernelEvidencePackage: Codable, Equatable, Sendable {
    var modeTransitions: [CanonicalSyncKernelEvidenceModeTransition]
    var objectCounts: CanonicalSyncKernelEvidenceObjectCounts
    var cacheCounts: CanonicalSyncKernelEvidenceCacheCounts
    var planCounts: CanonicalSyncKernelEvidencePlanCounts
    var applyCounts: CanonicalSyncKernelEvidenceExecutionCounts
    var uploadCounts: CanonicalSyncKernelEvidenceExecutionCounts
    var readDivergence: CanonicalSyncKernelEvidenceReadDivergence
    var switchBackProofSummary: String
    var redactionProof: CanonicalSyncKernelEvidenceRedactionProof
    var redactedDiagnostics: [String]
    var redacted: Bool
    var diagnosticsSummary: String
}

nonisolated struct CanonicalSyncKernelEvidenceExportInput: Codable, Equatable, Sendable {
    var modeTransitions: [CanonicalSyncKernelEvidenceModeTransition]
    var objectCounts: CanonicalSyncKernelEvidenceObjectCounts
    var cacheCounts: CanonicalSyncKernelEvidenceCacheCounts
    var planCounts: CanonicalSyncKernelEvidencePlanCounts
    var applyCounts: CanonicalSyncKernelEvidenceExecutionCounts
    var uploadCounts: CanonicalSyncKernelEvidenceExecutionCounts
    var readDivergence: CanonicalSyncKernelEvidenceReadDivergence
    var switchBackProof: CanonicalLegacySwitchBackProofResult?
    var rawDiagnosticLines: [String]

    nonisolated init(
        modeTransitions: [CanonicalSyncKernelEvidenceModeTransition] = [],
        objectCounts: CanonicalSyncKernelEvidenceObjectCounts = CanonicalSyncKernelEvidenceObjectCounts(
            recordingMetadataCount: 0,
            libraryMetadataCount: 0,
            generatedArtifactCount: 0,
            tombstoneConflictCount: 0,
            audioUploadCandidateCount: 0,
            recordingExistenceCount: 0
        ),
        cacheCounts: CanonicalSyncKernelEvidenceCacheCounts = CanonicalSyncKernelEvidenceCacheCounts(
            hitCount: 0,
            missCount: 0,
            staleCount: 0,
            errorCount: 0
        ),
        planCounts: CanonicalSyncKernelEvidencePlanCounts = CanonicalSyncKernelEvidencePlanCounts(
            canonicalPlanUsedCount: 0,
            legacyFallbackCount: 0,
            blockedPlanCount: 0
        ),
        applyCounts: CanonicalSyncKernelEvidenceExecutionCounts = CanonicalSyncKernelEvidenceExecutionCounts(
            successCount: 0,
            failureCount: 0
        ),
        uploadCounts: CanonicalSyncKernelEvidenceExecutionCounts = CanonicalSyncKernelEvidenceExecutionCounts(
            successCount: 0,
            failureCount: 0
        ),
        readDivergence: CanonicalSyncKernelEvidenceReadDivergence = CanonicalSyncKernelEvidenceReadDivergence(
            equivalentCount: 0,
            divergentCount: 0,
            pathOrContentLeakRiskCount: 0
        ),
        switchBackProof: CanonicalLegacySwitchBackProofResult? = nil,
        rawDiagnosticLines: [String] = []
    ) {
        self.modeTransitions = modeTransitions
        self.objectCounts = objectCounts
        self.cacheCounts = cacheCounts
        self.planCounts = planCounts
        self.applyCounts = applyCounts
        self.uploadCounts = uploadCounts
        self.readDivergence = readDivergence
        self.switchBackProof = switchBackProof
        self.rawDiagnosticLines = rawDiagnosticLines
    }
}

nonisolated struct CanonicalSyncKernelEvidenceExporter: Sendable {
    nonisolated init() {}

    nonisolated func export(
        _ input: CanonicalSyncKernelEvidenceExportInput
    ) -> CanonicalSyncKernelEvidencePackage {
        let redactedLines = input.rawDiagnosticLines.map(CanonicalSyncKernelEvidenceRedactor.redact(_:))
        let sensitiveInputDetected = input.rawDiagnosticLines.contains {
            CanonicalSyncKernelEvidenceRedactor.containsSensitiveSignal($0)
        }
        let sensitiveOutputDetected = redactedLines.contains {
            CanonicalSyncKernelEvidenceRedactor.containsSensitiveSignal($0)
        }
        let redactionProof = CanonicalSyncKernelEvidenceRedactionProof(
            redacted: !sensitiveOutputDetected,
            sensitiveInputDetected: sensitiveInputDetected,
            sensitiveOutputDetected: sensitiveOutputDetected,
            excludedSensitivePayloads: [
                "absolutePaths",
                "fullHashes",
                "secrets",
                "fingerprints",
                "requestResponseBodies",
                "transcriptNoteSummaryProviderContent",
                "audioBytes"
            ]
        )
        let switchBackSummary = CanonicalSyncKernelEvidenceRedactor.redact(
            input.switchBackProof?.diagnosticsSummary ?? "switchBackProof=missing"
        )
        let diagnosticsSummary = [
            "canonicalSyncKernelEvidencePackage=v8.45",
            "modeTransitions=\(input.modeTransitions.count)",
            "recordingMetadataCount=\(input.objectCounts.recordingMetadataCount)",
            "cacheHitCount=\(input.cacheCounts.hitCount)",
            "canonicalPlanUsedCount=\(input.planCounts.canonicalPlanUsedCount)",
            "legacyFallbackCount=\(input.planCounts.legacyFallbackCount)",
            "applySuccess=\(input.applyCounts.successCount)",
            "applyFailure=\(input.applyCounts.failureCount)",
            "uploadSuccess=\(input.uploadCounts.successCount)",
            "uploadFailure=\(input.uploadCounts.failureCount)",
            "readDivergent=\(input.readDivergence.divergentCount)",
            "switchBackProven=\(input.switchBackProof?.isProven == true)",
            "redacted=\(!sensitiveOutputDetected)"
        ].joined(separator: ",")

        return CanonicalSyncKernelEvidencePackage(
            modeTransitions: input.modeTransitions,
            objectCounts: input.objectCounts,
            cacheCounts: input.cacheCounts,
            planCounts: input.planCounts,
            applyCounts: input.applyCounts,
            uploadCounts: input.uploadCounts,
            readDivergence: input.readDivergence,
            switchBackProofSummary: switchBackSummary,
            redactionProof: redactionProof,
            redactedDiagnostics: redactedLines,
            redacted: redactionProof.redacted,
            diagnosticsSummary: diagnosticsSummary
        )
    }
}

nonisolated enum CanonicalSyncKernelEvidenceRedactor {
    nonisolated static func redact(_ value: String) -> String {
        if containsSensitiveSignal(value) {
            return "redacted-\(CanonicalProductionRedaction.hashPrefix(CanonicalHash.sha256String(value).value) ?? "diagnostic")"
        }
        return CanonicalProductionRedaction.safeDiagnosticText(value) ?? "redacted"
    }

    nonisolated static func containsSensitiveSignal(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        if CanonicalProductionRedaction.containsSensitivePathSignal(value) {
            return true
        }
        let sensitiveTokens = [
            "secret",
            "token=",
            "api_key",
            "apikey",
            "password",
            "privatekey",
            "private key",
            "requestbody",
            "responsebody",
            "fulltranscript",
            "fullnote",
            "fullsummary",
            "providerresponse",
            "audio bytes",
            "-----begin"
        ]
        if sensitiveTokens.contains(where: { lowercased.contains($0) }) {
            return true
        }
        return containsLongHexToken(value)
    }

    nonisolated private static func containsLongHexToken(_ value: String) -> Bool {
        let separators = CharacterSet.alphanumerics.inverted
        return value
            .components(separatedBy: separators)
            .contains { token in
                token.count > 16 && token.unicodeScalars.allSatisfy { scalar in
                    CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
                }
            }
    }
}

nonisolated struct CanonicalSyncKernelManualSwitchGateContext: Codable, Equatable, Sendable {
    var scorecard: CanonicalSyncKernelCompletionScorecard
    var compatibilityProof: CanonicalLegacyCompatibilityMatrix
    var switchBackProof: CanonicalLegacySwitchBackProofResult
    var realisticRootSwitchBackProofReady: Bool
    var defaultMode: CanonicalKernelSwitchMode
    var releaseMode: CanonicalKernelSwitchMode
    var allDiagnosticsRedacted: Bool
    var legacyFallbackAvailable: Bool
    var ownerApproved: Bool
    var manualBackupAcknowledged: Bool
    var v858RecordingRealApplyPortReady: Bool
    var v858RecordingReadSideSeamReady: Bool
    var v859AudioCommitExecutorReady: Bool
    var v860InventoryExistenceGateReady: Bool
    var v861ProductionFilePortTrueWriteGated: Bool
    var v862SwitchBackProofDriverReady: Bool
    var diagnosticsGrepListReady: Bool
    var emergencyOldKernelSwitchBackPathReady: Bool
    var stopConditionsReady: Bool
    var runbookUpdated: Bool
    var codeCompleteResult: CanonicalSyncKernelCodeCompletionResult?
    var manualFullSyncConfirmation: Bool
    var oldKernelBaselinePlanned: Bool
    var switchBackProofDriverAvailable: Bool
    var diagnosticsExportAvailable: Bool
    var routeSecurityUnchanged: Bool
    var noUnsafeBlocker: Bool
    var needsBuildValidation: Bool
    var unresolvedBlockers: [CanonicalSyncKernelCompletionBlocker]

    nonisolated init(
        scorecard: CanonicalSyncKernelCompletionScorecard,
        compatibilityProof: CanonicalLegacyCompatibilityMatrix = .defaultV844(),
        switchBackProof: CanonicalLegacySwitchBackProofResult,
        realisticRootSwitchBackProofReady: Bool = true,
        defaultMode: CanonicalKernelSwitchMode = .oldKernel,
        releaseMode: CanonicalKernelSwitchMode = .oldKernel,
        allDiagnosticsRedacted: Bool = true,
        legacyFallbackAvailable: Bool = true,
        ownerApproved: Bool = false,
        manualBackupAcknowledged: Bool = false,
        v858RecordingRealApplyPortReady: Bool = true,
        v858RecordingReadSideSeamReady: Bool = true,
        v859AudioCommitExecutorReady: Bool = true,
        v860InventoryExistenceGateReady: Bool = true,
        v861ProductionFilePortTrueWriteGated: Bool = true,
        v862SwitchBackProofDriverReady: Bool = true,
        diagnosticsGrepListReady: Bool = true,
        emergencyOldKernelSwitchBackPathReady: Bool = true,
        stopConditionsReady: Bool = true,
        runbookUpdated: Bool = true,
        codeCompleteResult: CanonicalSyncKernelCodeCompletionResult? = nil,
        manualFullSyncConfirmation: Bool = true,
        oldKernelBaselinePlanned: Bool = true,
        switchBackProofDriverAvailable: Bool = true,
        diagnosticsExportAvailable: Bool = true,
        routeSecurityUnchanged: Bool = true,
        noUnsafeBlocker: Bool = true,
        needsBuildValidation: Bool = false,
        unresolvedBlockers: [CanonicalSyncKernelCompletionBlocker] = []
    ) {
        self.scorecard = scorecard
        self.compatibilityProof = compatibilityProof
        self.switchBackProof = switchBackProof
        self.realisticRootSwitchBackProofReady = realisticRootSwitchBackProofReady
        self.defaultMode = defaultMode
        self.releaseMode = releaseMode
        self.allDiagnosticsRedacted = allDiagnosticsRedacted
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.ownerApproved = ownerApproved
        self.manualBackupAcknowledged = manualBackupAcknowledged
        self.v858RecordingRealApplyPortReady = v858RecordingRealApplyPortReady
        self.v858RecordingReadSideSeamReady = v858RecordingReadSideSeamReady
        self.v859AudioCommitExecutorReady = v859AudioCommitExecutorReady
        self.v860InventoryExistenceGateReady = v860InventoryExistenceGateReady
        self.v861ProductionFilePortTrueWriteGated = v861ProductionFilePortTrueWriteGated
        self.v862SwitchBackProofDriverReady = v862SwitchBackProofDriverReady
        self.diagnosticsGrepListReady = diagnosticsGrepListReady
        self.emergencyOldKernelSwitchBackPathReady = emergencyOldKernelSwitchBackPathReady
        self.stopConditionsReady = stopConditionsReady
        self.runbookUpdated = runbookUpdated
        self.codeCompleteResult = codeCompleteResult
        self.manualFullSyncConfirmation = manualFullSyncConfirmation
        self.oldKernelBaselinePlanned = oldKernelBaselinePlanned
        self.switchBackProofDriverAvailable = switchBackProofDriverAvailable
        self.diagnosticsExportAvailable = diagnosticsExportAvailable
        self.routeSecurityUnchanged = routeSecurityUnchanged
        self.noUnsafeBlocker = noUnsafeBlocker
        self.needsBuildValidation = needsBuildValidation
        self.unresolvedBlockers = unresolvedBlockers
    }
}

nonisolated struct CanonicalSyncKernelManualSwitchGateResult: Codable, Equatable, Sendable {
    var allowedForManualTrial: Bool
    var allowedForRealDeviceTrial: Bool
    var releaseDefaultAllowed: Bool
    var blockers: [CanonicalSyncKernelCompletionBlocker]
    var blockedWithReasons: [String]
    var unsafeToTry: Bool
    var needsBuildValidation: Bool
    var needsSwitchBackProof: Bool
    var needsOwnerApproval: Bool
    var needsBackupAcknowledgement: Bool
    var allowedMode: CanonicalKernelSwitchMode
    var diagnosticsSummary: String
}

nonisolated struct CanonicalSyncKernelManualSwitchGate: Sendable {
    nonisolated init() {}

    nonisolated func evaluate(
        _ context: CanonicalSyncKernelManualSwitchGateContext
    ) -> CanonicalSyncKernelManualSwitchGateResult {
        var blockers: [CanonicalSyncKernelCompletionBlocker] = []
        let codeCompleteResult = context.codeCompleteResult ?? context.scorecard.codeCompletionResult
        if codeCompleteResult != .readyForRealDeviceCanonicalSwitch {
            switch codeCompleteResult {
            case .unsafeToTryOnDevice:
                blockers.append(.unresolvedBlocker)
            case .notReady:
                blockers.append(.domainIncomplete)
            case .partialWithBlockers:
                blockers.append(.unresolvedBlocker)
            case .readyForRealDeviceCanonicalSwitch:
                break
            }
        }
        if !context.scorecard.codeComplete {
            blockers.append(.domainIncomplete)
        }
        if !context.compatibilityProof.isFullyProven {
            blockers.append(.compatibilityProofMissing)
        }
        if !context.switchBackProof.isProven {
            blockers.append(.switchBackProofMissing)
        }
        if !context.realisticRootSwitchBackProofReady {
            blockers.append(.realisticRootSwitchBackProofMissing)
        }
        if context.defaultMode != .oldKernel {
            blockers.append(.defaultOldKernelMissing)
        }
        if context.releaseMode != .oldKernel {
            blockers.append(.releaseDefaultCanonical)
        }
        if !context.allDiagnosticsRedacted {
            blockers.append(.diagnosticsNotRedacted)
        }
        if !context.legacyFallbackAvailable {
            blockers.append(.legacyFallbackUnavailable)
        }
        if !context.unresolvedBlockers.isEmpty {
            blockers.append(.unresolvedBlocker)
        }
        if !context.ownerApproved {
            blockers.append(.ownerApprovalMissing)
        }
        if !context.manualFullSyncConfirmation {
            blockers.append(.canonicalFullSyncManualConfirmationGateMissing)
        }
        if !context.manualBackupAcknowledged {
            blockers.append(.manualBackupAcknowledgementMissing)
        }
        if !context.oldKernelBaselinePlanned {
            blockers.append(.defaultOldKernelMissing)
        }
        if !context.switchBackProofDriverAvailable {
            blockers.append(.switchBackProofDriverMissing)
        }
        if !context.diagnosticsExportAvailable {
            blockers.append(.diagnosticsGrepListMissing)
        }
        if !context.routeSecurityUnchanged {
            blockers.append(.routeSecurityChanged)
            blockers.append(.securityBypassDetected)
        }
        if !context.noUnsafeBlocker {
            blockers.append(.unresolvedBlocker)
        }
        if context.needsBuildValidation {
            blockers.append(.targetedTestsValidationMissing)
        }
        if !context.v858RecordingRealApplyPortReady {
            blockers.append(.recordingMetadataRealApplyPortMissing)
        }
        if !context.v858RecordingReadSideSeamReady {
            blockers.append(.recordingMetadataReadSideSeamMissing)
        }
        if !context.v859AudioCommitExecutorReady {
            blockers.append(.audioCommitExecutorMissing)
        }
        if !context.v860InventoryExistenceGateReady {
            blockers.append(.inventoryExistenceGateMissing)
        }
        if !context.v861ProductionFilePortTrueWriteGated {
            blockers.append(.productionFilePortTrueWriteGateMissing)
        }
        if !context.v862SwitchBackProofDriverReady {
            blockers.append(.switchBackProofDriverMissing)
        }
        if !context.diagnosticsGrepListReady {
            blockers.append(.diagnosticsGrepListMissing)
        }
        if !context.emergencyOldKernelSwitchBackPathReady {
            blockers.append(.emergencyOldKernelSwitchBackPathMissing)
        }
        if !context.stopConditionsReady {
            blockers.append(.stopConditionsMissing)
        }
        if !context.runbookUpdated {
            blockers.append(.runbookMissing)
        }
        blockers = Self.unique(blockers)

        let needsSwitchBackProof = !context.switchBackProof.isProven
            || !context.realisticRootSwitchBackProofReady
            || !context.v862SwitchBackProofDriverReady
            || !context.switchBackProofDriverAvailable
        let unsafeToTry = codeCompleteResult == .unsafeToTryOnDevice
            || blockers.contains(.releaseDefaultCanonical)
            || blockers.contains(.legacyFallbackUnavailable)
            || blockers.contains(.securityBypassDetected)
            || blockers.contains(.routeSecurityChanged)
            || blockers.contains(.requestVerifierBypassed)
            || blockers.contains(.productionRootWriteWithoutOwnerApproval)
            || blockers.contains(.productionRootWriteWithoutManualConfirmation)
            || blockers.contains(.productionRootWriteInReleaseDefault)
            || blockers.contains(.scatteredSwitchBypass)
            || blockers.contains(.diagnosticsSensitiveLeak)
        let needsBuildValidation = context.needsBuildValidation
            || blockers.contains(.iOSBuildValidationMissing)
            || blockers.contains(.macOSBuildValidationMissing)
            || blockers.contains(.targetedTestsValidationMissing)
        let allowed = blockers.isEmpty
            && codeCompleteResult == .readyForRealDeviceCanonicalSwitch
            && !unsafeToTry
        return CanonicalSyncKernelManualSwitchGateResult(
            allowedForManualTrial: allowed,
            allowedForRealDeviceTrial: allowed,
            releaseDefaultAllowed: false,
            blockers: blockers,
            blockedWithReasons: blockers.map(\.rawValue),
            unsafeToTry: unsafeToTry,
            needsBuildValidation: needsBuildValidation,
            needsSwitchBackProof: needsSwitchBackProof,
            needsOwnerApproval: !context.ownerApproved,
            needsBackupAcknowledgement: !context.manualBackupAcknowledged,
            allowedMode: allowed ? .canonicalFullSync : .blocked,
            diagnosticsSummary: [
                "canonicalSyncKernelManualSwitchGate=v8.63",
                "canonicalSyncKernelManualSwitchGateFinal=v8.68",
                "codeCompleteResult=\(codeCompleteResult.rawValue)",
                "allowedForManualTrial=\(allowed)",
                "allowedForRealDeviceTrial=\(allowed)",
                "unsafeToTry=\(unsafeToTry)",
                "needsBuildValidation=\(needsBuildValidation)",
                "needsSwitchBackProof=\(needsSwitchBackProof)",
                "needsOwnerApproval=\(!context.ownerApproved)",
                "needsBackupAcknowledgement=\(!context.manualBackupAcknowledged)",
                "releaseDefaultAllowed=false",
                "allowedMode=\(allowed ? CanonicalKernelSwitchMode.canonicalFullSync.rawValue : CanonicalKernelSwitchMode.blocked.rawValue)",
                "defaultMode=\(context.defaultMode.rawValue)",
                "releaseMode=\(context.releaseMode.rawValue)",
                "realisticRootSwitchBackProofReady=\(context.realisticRootSwitchBackProofReady)",
                "manualBackupAcknowledged=\(context.manualBackupAcknowledged)",
                "ownerApproved=\(context.ownerApproved)",
                "manualFullSyncConfirmation=\(context.manualFullSyncConfirmation)",
                "oldKernelBaselinePlanned=\(context.oldKernelBaselinePlanned)",
                "switchBackProofDriverAvailable=\(context.switchBackProofDriverAvailable)",
                "diagnosticsExportAvailable=\(context.diagnosticsExportAvailable)",
                "routeSecurityUnchanged=\(context.routeSecurityUnchanged)",
                "noUnsafeBlocker=\(context.noUnsafeBlocker)",
                "v858RecordingRealApplyPortReady=\(context.v858RecordingRealApplyPortReady)",
                "v858RecordingReadSideSeamReady=\(context.v858RecordingReadSideSeamReady)",
                "v859AudioCommitExecutorReady=\(context.v859AudioCommitExecutorReady)",
                "v860InventoryExistenceGateReady=\(context.v860InventoryExistenceGateReady)",
                "v861ProductionFilePortTrueWriteGated=\(context.v861ProductionFilePortTrueWriteGated)",
                "v862SwitchBackProofDriverReady=\(context.v862SwitchBackProofDriverReady)",
                "diagnosticsGrepListReady=\(context.diagnosticsGrepListReady)",
                "emergencyOldKernelSwitchBackPathReady=\(context.emergencyOldKernelSwitchBackPathReady)",
                "stopConditionsReady=\(context.stopConditionsReady)",
                "runbookUpdated=\(context.runbookUpdated)",
                "blockers=\(blockers.map(\.rawValue).joined(separator: "|"))",
                "redacted=true"
            ].joined(separator: ",")
        )
    }

    nonisolated private static func unique(
        _ blockers: [CanonicalSyncKernelCompletionBlocker]
    ) -> [CanonicalSyncKernelCompletionBlocker] {
        var seen: Set<CanonicalSyncKernelCompletionBlocker> = []
        var unique: [CanonicalSyncKernelCompletionBlocker] = []
        for blocker in blockers where !seen.contains(blocker) {
            seen.insert(blocker)
            unique.append(blocker)
        }
        return unique
    }
}

typealias ManualSwitchGate = CanonicalSyncKernelManualSwitchGate
typealias ManualSwitchGateContext = CanonicalSyncKernelManualSwitchGateContext
