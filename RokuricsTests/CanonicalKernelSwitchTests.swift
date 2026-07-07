//
//  CanonicalKernelSwitchTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalKernelSwitchTests {
    @Test func defaultModeIsOldKernel() {
        let result = CanonicalKernelSwitchConfiguration.default.resolve()

        #expect(result.effectiveMode == .oldKernel)
        #expect(result.ownerState == .oldKernel)
        #expect(result.blockers.isEmpty)
    }

    @Test func manualSwitchModeChoicesExposeExactlyFiveModes() {
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

    @Test func oldKernelMapsAllCanonicalOwnersDisabled() {
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

    @Test func decisionAndApplyNoAudioKeepConnectionCarrierWithoutAudioTransfer() {
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

    @Test func diagnosticsOnlyHasNoSideEffects() {
        let result = CanonicalKernelSwitchConfiguration(
            mode: .diagnosticsOnly,
            policy: .debugInternal()
        ).resolve()
        let effective = result.effectiveConfiguration

        #expect(result.ownerState == .canonicalNoWrite)
        #expect(effective.syncRuntimeConfiguration.mode == .diagnosticsOnly)
        #expect(effective.applyRuntimeConfiguration.mode == .diagnosticsOnly)
        #expect(effective.existenceApplyRuntimeConfiguration.mode == .diagnosticsOnly)
        #expect(effective.audioUploadRuntimeConfiguration.mode == .diagnosticsOnly)
        #expect(effective.readRuntimeConfiguration.mode == .disabled)
        #expect(effective.applyRuntimeConfiguration.mode.executesCommit == false)
        #expect(effective.audioUploadRuntimeConfiguration.mode.sendsNetworkOrTransport == false)
    }

    @Test func canonicalFullSyncRequiresDebugInternalBuild() {
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

    @Test func canonicalFullSyncRequiresManualConfirmationAndOwnerApproval() {
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

    @Test func releaseBlocksCanonicalFullSync() {
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

    @Test func switchingCanonicalFullSyncBackToOldRequiresNoMigration() {
        let newKernel = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        let oldKernel = CanonicalKernelSwitchConfiguration(mode: .oldKernel).resolve()

        #expect(newKernel.isBlocked == false)
        #expect(newKernel.reversibilityProof.requiresDataMigrationToSwitchBack == false)
        #expect(newKernel.effectiveConfiguration.migrationMatrixPolicy.migrationRequiredToSwitchBack == false)
        #expect(oldKernel.effectiveMode == .oldKernel)
        #expect(oldKernel.effectiveConfiguration.migrationMatrixPolicy.migrationRequiredToSwitchBack == false)
    }

    @Test func invalidMixedAdvancedOverrideIsBlocked() {
        let result = CanonicalKernelSwitchConfiguration(
            mode: .oldKernel,
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                syncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration(mode: .canonicalPlanPrimaryWithLegacyFallback)
            )
        ).resolve()

        #expect(result.effectiveMode == .blocked)
        #expect(result.blockers.contains(.advancedOverrideContradictsMasterSwitch))
        #expect(result.diagnostics.contains { $0.kind == .canonicalKernelSwitchSpecializedConfigBypassBlocked })
    }

    @Test func readRuntimeOverrideCannotUpgradeMasterSwitchMode() {
        let oldKernel = CanonicalKernelSwitchConfiguration(
            mode: .oldKernel,
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                readRuntimeConfiguration: .explicitGuardedCanonicalRead()
            )
        ).resolve()
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

        #expect(oldKernel.effectiveMode == .blocked)
        #expect(oldKernel.blockers.contains(.advancedOverrideContradictsMasterSwitch))
        #expect(decisionOnly.effectiveMode == .blocked)
        #expect(decisionOnly.blockers.contains(.advancedOverrideContradictsMasterSwitch))
        #expect(restrictiveFullSync.effectiveMode == .canonicalFullSync)
        #expect(restrictiveFullSync.effectiveConfiguration.readRuntimeConfiguration.mode == .parallelCompare)
    }

    @Test func restrictiveAdvancedOverrideIsAllowedButCannotEscalatePolicy() {
        let restrictive = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true),
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                audioUploadRuntimeConfiguration: .disabled
            )
        ).resolve()
        let sameModeUnsafePolicy = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: .debugInternal(manualFullSyncConfirmation: true),
            advancedOverrides: CanonicalKernelSwitchAdvancedOverrides(
                audioUploadRuntimeConfiguration: CanonicalAudioUploadRuntimeConfiguration(
                    mode: .canonicalUploadWithLegacyFallback,
                    policy: CanonicalAudioUploadRuntimePolicy(
                        debugInternalBuild: true,
                        ownerApprovedCanonicalCommit: true,
                        allowCanonicalUploadWithLegacyFallback: true,
                        legacyFallbackEnabled: false
                    )
                )
            )
        ).resolve()

        #expect(restrictive.effectiveMode == .canonicalFullSync)
        #expect(restrictive.effectiveConfiguration.audioUploadRuntimeConfiguration.mode == .disabled)
        #expect(sameModeUnsafePolicy.effectiveMode == .blocked)
        #expect(sameModeUnsafePolicy.blockers.contains(.advancedOverrideContradictsMasterSwitch))
    }

    @Test func fullSyncBlocksMissingReadinessAndSwitchBackPreconditions() {
        let missingAudioReadiness = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy.debugInternal(manualFullSyncConfirmation: true).with {
                $0.audioUploadReadiness = false
            }
        ).resolve()
        let missingReadRuntime = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy.debugInternal(manualFullSyncConfirmation: true).with {
                $0.readRuntimeReady = false
            }
        ).resolve()
        let switchBackBlocked = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy.debugInternal(manualFullSyncConfirmation: true).with {
                $0.switchBackHardBlocker = true
            }
        ).resolve()

        #expect(missingAudioReadiness.blockers.contains(.audioUploadReadinessMissing))
        #expect(missingAudioReadiness.gateResult.state == .blockedMissingAudioUploadReadiness)
        #expect(missingReadRuntime.blockers.contains(.readRuntimeReadinessMissing))
        #expect(missingReadRuntime.gateResult.state == .blockedMissingReadPath)
        #expect(switchBackBlocked.blockers.contains(.switchBackHardBlocker))
        #expect(switchBackBlocked.gateResult.state == .blockedMissingSwitchBackReadiness)
    }

    @Test func libraryMetadataDebugPilotCannotOverrideOldKernelProductionRoot() {
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

    @Test func legacyFallbackIsRetainedInCanonicalFullSync() {
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

    @Test func fullSyncEnablesAudioUploadScopeWhileApplyNoAudioBlocksUpload() {
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

    @Test func shadowCompareRemainsEnabled() {
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

    @Test func settingsPersistenceNormalizesAndMaps() {
        let suiteName = "CanonicalKernelSwitchTests.\(UUID().uuidString)"
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
            "unknown-mode",
            userDefaults: defaults,
            postNotification: false
        )
        let normalized = CanonicalKernelSwitchConfiguration.debugStoredConfiguration(userDefaults: defaults).resolve()

        #expect(normalized.effectiveMode == .oldKernel)

        defaults.set(true, forKey: CanonicalKernelSwitchConfiguration.debugFullSyncConfirmedKey)
        CanonicalKernelSwitchConfiguration.setDebugStoredMode(
            CanonicalKernelSwitchMode.oldKernel.rawValue,
            userDefaults: defaults,
            postNotification: false
        )
        #expect(defaults.bool(forKey: CanonicalKernelSwitchConfiguration.debugFullSyncConfirmedKey) == false)
    }

    @Test func reportDiagnosticsAreRedactedAndGateUsesBuilder() {
        let result = CanonicalKernelSwitchEffectiveConfigurationBuilder().build(
            configuration: CanonicalKernelSwitchConfiguration(mode: .canonicalShadow, policy: .debugInternal())
        )
        let report = CanonicalKernelSwitchReport(result: result)

        #expect(result.effectiveMode == .canonicalShadow)
        #expect(result.diagnostics.allSatisfy { $0.isRedacted })
        #expect(report.diagnostics.contains { $0.kind == .canonicalKernelSwitchReportBuilt })
        #expect(CanonicalKernelSwitchGate().evaluate(configuration: .oldKernel).allowed)
    }

    @Test func statusSourceUsesEffectiveModeInsteadOfRequestedMode() {
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

    @Test func iPhoneProductionPortInjectionDisablesCanonicalPortsForOldAndDecisionModes() {
        let oldKernel = IPhoneCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(mode: .oldKernel).resolve(),
            productionRootURL: Self.safeProductionRootURL()
        )
        let decisionOnly = IPhoneCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalDecisionOnly,
                policy: .debugInternal()
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL()
        )

        #expect(oldKernel.hasNonAudioApplyExecutors == false)
        #expect(oldKernel.audioUploadExecutorEnabled == false)
        #expect(oldKernel.allowProductionRootWrites == false)
        #expect(decisionOnly.hasNonAudioApplyExecutors == false)
        #expect(decisionOnly.audioUploadExecutorEnabled == false)
        #expect(decisionOnly.allowProductionRootWrites == false)
    }

    @Test func iPhoneApplyNoAudioInjectsNonAudioExecutorsButBlocksAudioUpload() {
        let output = IPhoneCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalApplyNoAudio,
                policy: .debugInternal()
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL()
        )

        #expect(output.hasNonAudioApplyExecutors)
        #expect(output.allowProductionRootWrites == false)
        #expect(output.audioUploadExecutorEnabled == false)
        #expect(output.decision.injectExistenceApplyPort)
    }

    @Test func iPhoneFullSyncConstructsProductionPortsOnlyAfterConfirmationAndSafeRoot() {
        let missingConfirmation = IPhoneCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: .debugInternal(ownerApproved: true, manualFullSyncConfirmation: false)
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL()
        )
        let missingOwner = IPhoneCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: .debugInternal(ownerApproved: false, manualFullSyncConfirmation: true)
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL()
        )
        let releaseDefault = IPhoneCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: CanonicalKernelSwitchPolicy(
                    debugInternalBuild: true,
                    ownerApproved: true,
                    releaseDefaultBuild: true,
                    manualFullSyncConfirmation: true
                )
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL()
        )
        let unsafeRoot = IPhoneCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: .debugInternal(manualFullSyncConfirmation: true)
            ).resolve(),
            productionRootURL: URL(fileURLWithPath: "/")
        )
        let allowed = IPhoneCanonicalProductionPortFactory.make(
            result: CanonicalKernelSwitchConfiguration(
                mode: .canonicalFullSync,
                policy: .debugInternal(manualFullSyncConfirmation: true)
            ).resolve(),
            productionRootURL: Self.safeProductionRootURL()
        )

        #expect(missingConfirmation.hasNonAudioApplyExecutors == false)
        #expect(missingConfirmation.allowProductionRootWrites == false)
        #expect(missingOwner.hasNonAudioApplyExecutors == false)
        #expect(missingOwner.allowProductionRootWrites == false)
        #expect(releaseDefault.hasNonAudioApplyExecutors == false)
        #expect(releaseDefault.allowProductionRootWrites == false)
        #expect(unsafeRoot.hasNonAudioApplyExecutors == false)
        #expect(unsafeRoot.decision.blockerCode == "productionRootSafetyBlocked")
        #expect(allowed.hasNonAudioApplyExecutors)
        #expect(allowed.allowProductionRootWrites)
        #expect(allowed.audioUploadExecutorEnabled)
    }

    @Test func iPhoneSpecializedConfigCannotBypassOldKernelFactory() {
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
        let output = IPhoneCanonicalProductionPortFactory.make(
            result: result,
            productionRootURL: Self.safeProductionRootURL()
        )

        #expect(result.effectiveMode == .blocked)
        #expect(output.hasNonAudioApplyExecutors == false)
        #expect(output.allowProductionRootWrites == false)
        #expect(output.audioUploadExecutorEnabled == false)
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
