//
//  CanonicalKernelSwitchTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import RokuricsMac

@Suite(.serialized)
struct CanonicalKernelSwitchTests {
    @Test func defaultModeIsOldKernelOnMac() {
        let result = CanonicalKernelSwitchConfiguration.default.resolve()

        #expect(result.effectiveMode == .oldKernel)
        #expect(result.ownerState == .oldKernel)
        #expect(result.blockers.isEmpty)
    }

    @Test func manualSwitchModeChoicesExposeExactlyFiveModesOnMac() {
        let choices = CanonicalKernelSwitchConfiguration.manualSwitchModeChoices.map(\.rawValue)

        #expect(choices == [
            CanonicalKernelSwitchMode.oldKernel.rawValue,
            CanonicalKernelSwitchMode.canonicalShadow.rawValue,
            CanonicalKernelSwitchMode.canonicalDecisionOnly.rawValue,
            CanonicalKernelSwitchMode.canonicalApplyNoAudio.rawValue,
            CanonicalKernelSwitchMode.canonicalFullSync.rawValue
        ])
        #expect(choices.contains(CanonicalKernelSwitchMode.diagnosticsOnly.rawValue) == false)
        #expect(choices.contains(CanonicalKernelSwitchMode.blocked.rawValue) == false)
    }

    @Test func oldKernelDisablesCanonicalOwnersOnMac() {
        let result = CanonicalKernelSwitchConfiguration(mode: .oldKernel).resolve()
        let effective = result.effectiveConfiguration

        #expect(effective.connectionRuntimeConfiguration.mode == .disabled)
        #expect(effective.syncRuntimeConfiguration.mode == .disabled)
        #expect(effective.applyRuntimeConfiguration.mode == .disabled)
        #expect(effective.existenceApplyRuntimeConfiguration.mode == .disabled)
        #expect(effective.audioUploadRuntimeConfiguration.mode == .disabled)
        #expect(effective.readRuntimeConfiguration.mode == .disabled)
        #expect(effective.libraryMetadataDebugPilotConfiguration.mode == .disabled)
    }

    @Test func decisionAndApplyNoAudioKeepConnectionCarrierWithoutAudioTransferOnMac() {
        let decisionOnly = CanonicalKernelSwitchConfiguration(
            mode: .canonicalDecisionOnly,
            policy: .debugInternal()
        ).resolve()
        let applyNoAudio = CanonicalKernelSwitchConfiguration(
            mode: .canonicalApplyNoAudio,
            policy: .debugInternal()
        ).resolve()

        #expect(decisionOnly.effectiveConfiguration.connectionRuntimeConfiguration.mode == .diagnosticsOnly)
        #expect(decisionOnly.effectiveConfiguration.transferRuntimeConfiguration.mode == .noCommit)
        #expect(decisionOnly.effectiveConfiguration.audioUploadRuntimeConfiguration.mode == .disabled)
        #expect(applyNoAudio.effectiveConfiguration.connectionRuntimeConfiguration.mode == .diagnosticsOnly)
        #expect(applyNoAudio.effectiveConfiguration.transferRuntimeConfiguration.mode == .blocked)
        #expect(applyNoAudio.effectiveConfiguration.audioUploadRuntimeConfiguration.mode == .disabled)
    }

    @Test func macInventoryCanonicalBuildPolicyGatesFactsAndSeamsByKernelMode() {
        let oldKernel = MacInventoryCanonicalBuildPolicy.make(mode: .oldKernel)
        let blocked = MacInventoryCanonicalBuildPolicy.make(mode: .blocked)
        let shadow = MacInventoryCanonicalBuildPolicy.make(mode: .canonicalShadow)
        let decisionOnly = MacInventoryCanonicalBuildPolicy.make(mode: .canonicalDecisionOnly)
        let applyNoAudio = MacInventoryCanonicalBuildPolicy.make(mode: .canonicalApplyNoAudio)
        let fullSync = MacInventoryCanonicalBuildPolicy.make(mode: .canonicalFullSync)

        #expect(oldKernel.buildsCanonicalFacts == false)
        #expect(oldKernel.runsAnySeam == false)
        #expect(oldKernel.skipReason == "oldKernel")
        #expect(blocked.buildsCanonicalFacts == false)
        #expect(blocked.runsAnySeam == false)
        #expect(blocked.skipReason == "blocked")
        #expect(shadow.buildsCanonicalFacts)
        #expect(shadow.runsShadowSeams)
        #expect(shadow.runsNoCommitSeams)
        #expect(shadow.runsAudioUploadSeams == false)
        #expect(decisionOnly.buildsCanonicalFacts)
        #expect(decisionOnly.runsDecisionSeams)
        #expect(decisionOnly.runsNoCommitSeams == false)
        #expect(decisionOnly.runsNonAudioApplySeams == false)
        #expect(decisionOnly.runsAudioUploadSeams == false)
        #expect(decisionOnly.runsReadSeams == false)
        #expect(applyNoAudio.buildsCanonicalFacts)
        #expect(applyNoAudio.runsDecisionSeams)
        #expect(applyNoAudio.runsNonAudioApplySeams)
        #expect(applyNoAudio.runsAudioUploadSeams == false)
        #expect(applyNoAudio.runsReadSeams == false)
        #expect(fullSync.buildsCanonicalFacts)
        #expect(fullSync.runsShadowSeams)
        #expect(fullSync.runsDecisionSeams)
        #expect(fullSync.runsNoCommitSeams)
        #expect(fullSync.runsNonAudioApplySeams)
        #expect(fullSync.runsAudioUploadSeams)
        #expect(fullSync.runsReadSeams)
    }

    @Test func diagnosticsOnlyKeepsMacSideEffectsOff() {
        let result = CanonicalKernelSwitchConfiguration(
            mode: .diagnosticsOnly,
            policy: .debugInternal()
        ).resolve()
        let effective = result.effectiveConfiguration

        #expect(result.ownerState == .canonicalNoWrite)
        #expect(effective.syncRuntimeConfiguration.mode == .diagnosticsOnly)
        #expect(effective.applyRuntimeConfiguration.mode.executesCommit == false)
        #expect(effective.audioUploadRuntimeConfiguration.mode.sendsNetworkOrTransport == false)
        #expect(effective.readRuntimeConfiguration.mode == .disabled)
    }

    @Test func fullSyncIsDebugInternalOnlyOnMac() {
        let result = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy(
                debugInternalBuild: false,
                ownerApproved: true,
                releaseDefaultBuild: false,
                manualFullSyncConfirmation: true
            )
        ).resolve()

        #expect(result.effectiveMode == .blocked)
        #expect(result.blockers.contains(.canonicalFullSyncRequiresDebugInternalBuild))
        #expect(result.gateResult.state == .blockedMissingOwnerApproval)
    }

    @Test func fullSyncRequiresConfirmationAndOwnerApprovalOnMac() {
        let missingConfirmation = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(ownerApproved: true, manualFullSyncConfirmation: false)
        ).resolve()
        let missingOwner = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(ownerApproved: false, manualFullSyncConfirmation: true)
        ).resolve()

        #expect(missingConfirmation.effectiveMode == .blocked)
        #expect(missingConfirmation.blockers.contains(.canonicalFullSyncRequiresManualConfirmation))
        #expect(missingConfirmation.gateResult.state == .blockedMissingConfirmation)
        #expect(missingOwner.effectiveMode == .blocked)
        #expect(missingOwner.blockers.contains(.canonicalFullSyncRequiresOwnerApproval))
        #expect(missingOwner.gateResult.state == .blockedMissingOwnerApproval)
    }

    @Test func releaseBuildBlocksFullSyncOnMac() {
        let result = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy(
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: true,
                manualFullSyncConfirmation: true
            )
        ).resolve()

        #expect(result.effectiveMode == .blocked)
        #expect(result.blockers.contains(.releaseDefaultCannotUseCanonicalFullSync))
    }

    @Test func fullSyncCanSwitchBackWithoutMigrationOnMac() {
        let newKernel = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        let oldKernel = CanonicalKernelSwitchConfiguration(mode: .oldKernel).resolve()

        #expect(newKernel.isBlocked == false)
        #expect(newKernel.reversibilityProof.isReversible)
        #expect(newKernel.effectiveConfiguration.migrationMatrixPolicy.migrationRequiredToSwitchBack == false)
        #expect(oldKernel.effectiveMode == .oldKernel)
    }

    @Test func mixedAdvancedOverrideIsBlockedOnMac() {
        let result = CanonicalKernelSwitchConfiguration(
            mode: .oldKernel,
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                readRuntimeConfiguration: CanonicalReadRuntimeConfiguration(mode: .guardedCanonicalReadWithLegacyFallback)
            )
        ).resolve()

        #expect(result.effectiveMode == .blocked)
        #expect(result.blockers.contains(.advancedOverrideContradictsMasterSwitch))
        #expect(result.diagnostics.contains { $0.kind == .canonicalKernelSwitchSpecializedConfigBypassBlocked })
    }

    @Test func readRuntimeOverrideCannotUpgradeDecisionOnlyOnMac() {
        let decisionOnly = CanonicalKernelSwitchConfiguration(
            mode: .canonicalDecisionOnly,
            policy: .debugInternal(),
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                readRuntimeConfiguration: .explicitGuardedCanonicalRead()
            )
        ).resolve()
        let restrictiveFullSync = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true),
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                readRuntimeConfiguration: CanonicalReadRuntimeConfiguration(
                    mode: .parallelCompare,
                    policy: .explicitGuardedDebugInternal()
                )
            )
        ).resolve()

        #expect(decisionOnly.effectiveMode == .blocked)
        #expect(decisionOnly.blockers.contains(.advancedOverrideContradictsMasterSwitch))
        #expect(restrictiveFullSync.effectiveMode == .canonicalFullSync)
        #expect(restrictiveFullSync.effectiveConfiguration.readRuntimeConfiguration.mode == .parallelCompare)
    }

    @Test func restrictiveOverrideAllowedButUnsafePolicyBlockedOnMac() {
        let restrictive = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true),
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                readRuntimeConfiguration: .disabled
            )
        ).resolve()
        let unsafeRead = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true),
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                readRuntimeConfiguration: CanonicalReadRuntimeConfiguration(
                    mode: .guardedCanonicalReadWithLegacyFallback,
                    policy: CanonicalReadRuntimePolicy(
                        debugInternalBuild: true,
                        ownerApproved: true,
                        manualOwnerApproval: true,
                        releaseDefaultBuild: false,
                        legacyFallbackAvailable: false,
                        diagnosticsRedacted: true,
                        applyRuntimeEvidenceValidForNonAudio: true,
                        uploadRuntimeEvidenceValidForAudioStatus: true,
                        inventorySnapshotAvailable: true,
                        planAuthorityEvidenceValid: true,
                        existenceTruthEvidenceValid: true
                    )
                )
            )
        ).resolve()

        #expect(restrictive.effectiveMode == .canonicalFullSync)
        #expect(restrictive.effectiveConfiguration.readRuntimeConfiguration.mode == .disabled)
        #expect(unsafeRead.effectiveMode == .blocked)
        #expect(unsafeRead.blockers.contains(.advancedOverrideContradictsMasterSwitch))
    }

    @Test func fullSyncBlocksMissingReadinessAndSwitchBackOnMac() {
        let missingDomain = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy.debugInternal(manualFullSyncConfirmation: true).with {
                $0.libraryMetadataReadiness = false
            }
        ).resolve()
        let missingApply = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy.debugInternal(manualFullSyncConfirmation: true).with {
                $0.nonAudioApplyRuntimeReady = false
            }
        ).resolve()
        let diskFormatBlocked = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy.debugInternal(manualFullSyncConfirmation: true).with {
                $0.canonicalOnlyDiskFormatBlocker = true
            }
        ).resolve()

        #expect(missingDomain.blockers.contains(.libraryMetadataReadinessMissing))
        #expect(missingDomain.gateResult.state == .blockedMissingDomainReadiness)
        #expect(missingApply.blockers.contains(.nonAudioApplyRuntimeReadinessMissing))
        #expect(missingApply.gateResult.state == .blockedMissingApplyReadiness)
        #expect(diskFormatBlocked.blockers.contains(.canonicalOnlyDiskFormatBlocker))
        #expect(diskFormatBlocked.gateResult.state == .blockedMissingSwitchBackReadiness)
    }

    @Test func libraryMetadataDebugPilotCannotOverrideOldKernelOnMac() {
        let token = CanonicalCutoverToken(tokenID: "token", syncRunID: "run", ownerApproved: true)
        let result = CanonicalKernelSwitchConfiguration(
            mode: .oldKernel,
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                libraryMetadataDebugPilotConfiguration: .executeProductionRootN1(
                    token: token,
                    evidence: CanonicalLibraryMetadataCutoverEvidence(),
                    allowProductionRootWrites: true
                )
            )
        ).resolve()

        #expect(result.effectiveMode == .blocked)
        #expect(result.effectiveConfiguration.libraryMetadataDebugPilotConfiguration.mode == .blocked)
        #expect(result.blockers.contains(.advancedOverrideContradictsMasterSwitch))
    }

    @Test func fallbackAndLegacyReadableFormatRemainOnMac() {
        let result = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        let effective = result.effectiveConfiguration

        #expect(effective.syncRuntimeConfiguration.policy.legacyFallbackAvailable)
        #expect(effective.applyRuntimeConfiguration.policy.legacyFallbackAvailable)
        #expect(effective.existenceApplyRuntimeConfiguration.policy.legacyFallbackAvailable)
        #expect(effective.audioUploadRuntimeConfiguration.policy.legacyFallbackEnabled)
        #expect(effective.readRuntimeConfiguration.policy.legacyFallbackAvailable)
        #expect(effective.migrationMatrixPolicy.diskFormatPolicy == "legacy-readable-or-dual-write-compatible")
    }

    @Test func fullSyncEnablesAudioUploadScopeWhileApplyNoAudioBlocksUploadOnMac() {
        let fullSync = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        let applyNoAudio = CanonicalKernelSwitchConfiguration(
            mode: .canonicalApplyNoAudio,
            policy: .debugInternal()
        ).resolve()

        #expect(fullSync.effectiveConfiguration.syncRuntimeConfiguration.policy.enabledScopes.contains(.audioUpload))
        #expect(fullSync.effectiveConfiguration.existenceApplyRuntimeConfiguration.mode == .productionRootApply)
        #expect(fullSync.effectiveConfiguration.existenceApplyRuntimeConfiguration.canWriteMetadataOnlyRecord)
        #expect(fullSync.effectiveConfiguration.existenceApplyRuntimeConfiguration.policy.writeAudioAllowed == false)
        #expect(fullSync.effectiveConfiguration.audioUploadRuntimeConfiguration.mode == .canonicalUploadWithLegacyFallback)
        #expect(fullSync.effectiveConfiguration.readRuntimeConfiguration.mode == .guardedCanonicalReadWithLegacyFallback)
        #expect(fullSync.effectiveConfiguration.migrationMatrixPolicy.activeCanonicalOwnershipDomains.contains(.audioUpload))
        #expect(applyNoAudio.effectiveConfiguration.existenceApplyRuntimeConfiguration.mode == .productionRootApply)
        #expect(applyNoAudio.effectiveConfiguration.existenceApplyRuntimeConfiguration.canWriteMetadataOnlyRecord)
        #expect(applyNoAudio.effectiveConfiguration.existenceApplyRuntimeConfiguration.policy.writeAudioAllowed == false)
        #expect(applyNoAudio.effectiveConfiguration.audioUploadRuntimeConfiguration.mode == .disabled)
        #expect(applyNoAudio.effectiveConfiguration.migrationMatrixPolicy.activeCanonicalOwnershipDomains.contains(.audioUpload) == false)
        #expect(applyNoAudio.effectiveConfiguration.readRuntimeConfiguration.mode == .disabled)
    }

    @Test func shadowCompareCanStayEnabledOnMac() {
        let shadow = CanonicalKernelSwitchConfiguration(
            mode: .canonicalShadow,
            policy: .debugInternal()
        ).resolve()
        let fullSync = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()

        #expect(shadow.effectiveConfiguration.readRuntimeConfiguration.mode == .parallelCompare)
        #expect(fullSync.reversibilityProof.shadowCompareCanStayOnWhileCanonicalOwnerActive)
    }

    @Test func settingsPersistenceMapsOnMac() {
        let suiteName = "CanonicalKernelSwitchMacTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CanonicalKernelSwitchConfiguration.setDebugStoredMode(
            CanonicalKernelSwitchMode.canonicalDecisionOnly.rawValue,
            userDefaults: defaults,
            postNotification: false
        )
        let decision = CanonicalKernelSwitchConfiguration.debugStoredConfiguration(userDefaults: defaults).resolve()

        #expect(decision.effectiveMode == .canonicalDecisionOnly)
        #expect(decision.effectiveConfiguration.syncRuntimeConfiguration.mode == .canonicalPlanPrimaryWithLegacyFallback)

        CanonicalKernelSwitchConfiguration.setDebugStoredMode(
            CanonicalKernelSwitchMode.oldKernel.rawValue,
            userDefaults: defaults,
            postNotification: false
        )
        let old = CanonicalKernelSwitchConfiguration.debugStoredConfiguration(userDefaults: defaults).resolve()

        #expect(old.effectiveMode == .oldKernel)
        #expect(defaults.bool(forKey: CanonicalKernelSwitchConfiguration.debugFullSyncConfirmedKey) == false)
    }

    @Test func reportDiagnosticsAreRedactedOnMac() {
        let result = CanonicalKernelSwitchEffectiveConfigurationBuilder().build(
            configuration: CanonicalKernelSwitchConfiguration(mode: .canonicalShadow, policy: .debugInternal())
        )
        let report = CanonicalKernelSwitchReport(result: result)

        #expect(result.effectiveMode == .canonicalShadow)
        #expect(result.diagnostics.allSatisfy { $0.isRedacted })
        #expect(report.diagnostics.contains { $0.kind == .canonicalKernelSwitchReportBuilt })
        #expect(CanonicalKernelSwitchGate().evaluate(configuration: .oldKernel).allowed)
    }

    @Test func statusSourceUsesEffectiveModeInsteadOfRequestedModeOnMac() {
        let blocked = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: false)
        ).resolve()
        let allowed = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()

        #expect(blocked.effectiveMode == .blocked)
        #expect(blocked.effectiveStatusSourceText.contains("legacy fallback"))
        #expect(blocked.effectiveStatusSourceText.contains("canonical guarded") == false)
        #expect(allowed.effectiveMode == .canonicalFullSync)
        #expect(allowed.effectiveStatusSourceText.contains("canonical guarded"))
    }

    @MainActor
    @Test func macProductionPortInjectionDisablesCanonicalPortsForOldAndDecisionModes() {
        let oldKernel = MacCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(mode: .oldKernel).resolve(),
            productionRootURL: Self.safeProductionRootURL(),
            recordingFileStore: MacRecordingFileStore()
        )
        let decisionOnly = MacCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalDecisionOnly,
                policy: .debugInternal()
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL(),
            recordingFileStore: MacRecordingFileStore()
        )

        #expect(oldKernel.hasNonAudioApplyExecutors == false)
        #expect(oldKernel.recordingExistenceApplyPort == nil)
        #expect(oldKernel.audioUploadCutoverExecutor == nil)
        #expect(oldKernel.allowProductionRootWrites == false)
        #expect(decisionOnly.hasNonAudioApplyExecutors == false)
        #expect(decisionOnly.recordingExistenceApplyPort == nil)
        #expect(decisionOnly.audioUploadCutoverExecutor == nil)
        #expect(decisionOnly.allowProductionRootWrites == false)
    }

    @MainActor
    @Test func macApplyNoAudioInjectsNonAudioAndExistenceButBlocksAudio() {
        let output = MacCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalApplyNoAudio,
                policy: .debugInternal()
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL(),
            recordingFileStore: MacRecordingFileStore()
        )

        #expect(output.hasNonAudioApplyExecutors)
        #expect(output.recordingExistenceApplyPort != nil)
        #expect(output.audioUploadCutoverExecutor == nil)
        #expect(output.allowProductionRootWrites == false)
    }

    @MainActor
    @Test func macFullSyncConstructsProductionPortsOnlyAfterConfirmationAndSafeRoot() {
        let missingConfirmation = MacCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: .debugInternal(ownerApproved: true, manualFullSyncConfirmation: false)
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL(),
            recordingFileStore: MacRecordingFileStore()
        )
        let missingOwner = MacCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: .debugInternal(ownerApproved: false, manualFullSyncConfirmation: true)
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL(),
            recordingFileStore: MacRecordingFileStore()
        )
        let releaseDefault = MacCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: CanonicalKernelSwitchPolicy(
                    debugInternalBuild: true,
                    ownerApproved: true,
                    releaseDefaultBuild: true,
                    manualFullSyncConfirmation: true
                )
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL(),
            recordingFileStore: MacRecordingFileStore()
        )
        let unsafeRoot = MacCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: .debugInternal(manualFullSyncConfirmation: true)
            ).resolve(),
            productionRootURL: URL(fileURLWithPath: "/"),
            recordingFileStore: MacRecordingFileStore()
        )
        let allowed = MacCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: .debugInternal(manualFullSyncConfirmation: true)
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL(),
            recordingFileStore: MacRecordingFileStore()
        )

        #expect(missingConfirmation.hasNonAudioApplyExecutors == false)
        #expect(missingConfirmation.recordingExistenceApplyPort == nil)
        #expect(missingConfirmation.allowProductionRootWrites == false)
        #expect(missingOwner.hasNonAudioApplyExecutors == false)
        #expect(missingOwner.recordingExistenceApplyPort == nil)
        #expect(releaseDefault.hasNonAudioApplyExecutors == false)
        #expect(releaseDefault.allowProductionRootWrites == false)
        #expect(unsafeRoot.hasNonAudioApplyExecutors == false)
        #expect(unsafeRoot.decision.blockerCode == "productionRootSafetyBlocked")
        #expect(allowed.hasNonAudioApplyExecutors)
        #expect(allowed.recordingExistenceApplyPort != nil)
        #expect(allowed.audioUploadCutoverExecutor != nil)
        #expect(allowed.allowProductionRootWrites)
    }

    @MainActor
    @Test func macSpecializedConfigCannotBypassOldKernelFactory() {
        let token = CanonicalCutoverToken(tokenID: "token", syncRunID: "run", ownerApproved: true)
        let result = CanonicalKernelSwitchConfiguration(
            mode: .oldKernel,
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                libraryMetadataDebugPilotConfiguration: .executeProductionRootN1(
                    token: token,
                    evidence: CanonicalLibraryMetadataCutoverEvidence(),
                    allowProductionRootWrites: true
                )
            )
        ).resolve()
        let output = MacCanonicalProductionPortFactory.make(
            result: result,
            productionRootURL: Self.safeProductionRootURL(),
            recordingFileStore: MacRecordingFileStore()
        )

        #expect(result.effectiveMode == .blocked)
        #expect(output.hasNonAudioApplyExecutors == false)
        #expect(output.recordingExistenceApplyPort == nil)
        #expect(output.audioUploadCutoverExecutor == nil)
        #expect(output.allowProductionRootWrites == false)
    }

    @Test func macExistenceRecordAndAudioRoutesPreserveTruthInvariants() {
        let record = CanonicalRecordingMetadataOnlyReceiveRecord(
            objectID: "recording-1",
            sourceDeviceID: "iphone-1",
            title: "Metadata only",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            metadataHash: "metadata-hash",
            declaredAudioHash: "audio-hash",
            declaredAudioByteSize: 42
        )

        #expect(record.audioAvailable == false)
        #expect(record.audioHash == nil)
        #expect(record.audioByteSize == nil)
        #expect(record.receiveStatus == "canonicalMetadataOnly")
        #expect(MacAudioUploadCutoverExecutor.existingResumableRoutePaths == [
            "/upload-recording-audio-session/start",
            "/upload-recording-audio-session/status",
            "/upload-recording-audio-session/chunk",
            "/upload-recording-audio-session/finalize"
        ])
    }

    private static func safeProductionRootURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RokuricsCanonicalProductionPortInjectionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private extension CanonicalKernelSwitchPolicy {
    func with(_ mutate: (inout CanonicalKernelSwitchPolicy) -> Void) -> CanonicalKernelSwitchPolicy {
        var copy = self
        mutate(&copy)
        return copy
    }
}
