//
//  CanonicalSyncKernelCompletionTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalSyncKernelCompletionTests {
    @Test func completionScorecardBlocksIfAnyDomainIncomplete() {
        let domains = CanonicalSyncKernelReadyToRetireDomain.allCases.map { domain in
            CanonicalSyncKernelDomainReadyToRetireReadiness(
                domain: domain,
                writeExecutorReady: domain != .audioUpload
            )
        }
        let report = CanonicalSyncKernelDomainReadyToRetireReport(domains: domains)
        let scorecard = CanonicalSyncKernelCompletionScorecard.v845(
            domainReadinessReport: report
        )

        #expect(scorecard.status == .incomplete)
        #expect(scorecard.codeComplete == false)
        #expect(scorecard.blockers.contains(.domainIncomplete))
    }

    @Test func scorecardMarksCodeCompleteNeedsDeviceEvidence() {
        let scorecard = CanonicalSyncKernelCompletionScorecard.v845()

        #expect(scorecard.status == .codeCompleteNeedsDeviceEvidence)
        #expect(scorecard.codeComplete)
        #expect(scorecard.realDeviceEvidencePresent == false)
        #expect(scorecard.blockers.contains(.realDeviceEvidenceMissing))
    }

    @Test func scorecardBlocksIfCompletionDomainIncomplete() {
        let domains = CanonicalSyncKernelCompletionDomain.allCases.map { domain in
            CanonicalSyncKernelCompletionDomainReadiness(
                domain: domain,
                readRuntimeReady: domain != .readRuntime
            )
        }
        let scorecard = CanonicalSyncKernelCompletionScorecard.v845(
            domainCompletionReadiness: domains
        )

        #expect(scorecard.status == .incomplete)
        #expect(scorecard.codeComplete == false)
        #expect(scorecard.blockers.contains(.domainIncomplete))
    }

    @Test func scorecardReportsUnsafeForCanonicalDefaultBlocker() {
        let scorecard = CanonicalSyncKernelCompletionScorecard.v845(
            unresolvedBlockers: [.unsafeCanonicalDefault]
        )

        #expect(scorecard.status == .unsafe)
        #expect(scorecard.blockers.contains(.unsafeCanonicalDefault))
    }

    @Test func libraryMetadataV852ReadinessScorecardIsReportOnlyUntilDeviceEvidence() {
        let scorecard = CanonicalLibraryMetadataDomainReadinessScorecard.v852P2_2()

        #expect(scorecard.domain == .libraryMetadata)
        #expect(scorecard.hashContractReady)
        #expect(scorecard.decisionRuntimeReady)
        #expect(scorecard.applyRuntimeReady)
        #expect(scorecard.readRuntimeReady)
        #expect(scorecard.metadataOnlyScopeReady)
        #expect(scorecard.resourcePathExcludedFromHash)
        #expect(scorecard.codeComplete)
        #expect(scorecard.readyForManualSwitchTrial == false)
        #expect(scorecard.readyToRetireLegacyReportOnly == false)
        #expect(scorecard.blockers == [.realDeviceEvidenceMissing])
        #expect(scorecard.diagnosticsSummary.contains("canonicalLibraryMetadataDomainReadiness=v8.52-p2-2"))
        #expect(scorecard.diagnosticsSummary.contains("hashSchema=canonical-library-metadata-v1"))
        #expect(scorecard.diagnosticsSummary.contains("legacyRetirementExecuted=false"))
    }

    @Test func generatedArtifactV853ReadinessScorecardIsReportOnlyUntilDeviceEvidence() {
        let scorecard = CanonicalGeneratedArtifactDomainReadinessScorecard.v853P2_3()

        #expect(scorecard.domain == .generatedArtifacts)
        #expect(scorecard.hashContractReady)
        #expect(scorecard.decisionRuntimeReady)
        #expect(scorecard.applyRuntimeReady)
        #expect(scorecard.readRuntimeReady)
        #expect(scorecard.contentFileWriteRootBound)
        #expect(scorecard.contentExcludedFromDiagnostics)
        #expect(scorecard.providerResponseExcludedFromHash)
        #expect(scorecard.pathExcludedFromHash)
        #expect(scorecard.codeComplete)
        #expect(scorecard.readyForManualSwitchTrial == false)
        #expect(scorecard.readyToRetireLegacyReportOnly == false)
        #expect(scorecard.blockers == [.realDeviceEvidenceMissing])
        #expect(scorecard.diagnosticsSummary.contains("canonicalGeneratedArtifactDomainReadiness=v8.53-p2-3"))
        #expect(scorecard.diagnosticsSummary.contains("hashSchema=canonical-generated-artifact-v1"))
        #expect(scorecard.diagnosticsSummary.contains("legacyRetirementExecuted=false"))
    }

    @Test func audioUploadV855ReadinessScorecardIsReportOnlyUntilDeviceEvidence() {
        let scorecard = CanonicalAudioUploadDomainReadinessScorecard.v855P2_5()

        #expect(scorecard.domain == .audioUpload)
        #expect(scorecard.decisionRuntimeReady)
        #expect(scorecard.commitExecutorReady)
        #expect(scorecard.uploadRuntimeReady)
        #expect(scorecard.retryRuntimeReady)
        #expect(scorecard.readRuntimeReady)
        #expect(scorecard.legacyFallbackReady)
        #expect(scorecard.switchBackProofReady)
        #expect(scorecard.noNewRoutesOrSecurityBypass)
        #expect(scorecard.finalizeProofRequiredBeforeCompleted)
        #expect(scorecard.metadataOnlyRejectedAsAudioAvailable)
        #expect(scorecard.peerUnknownDeferred)
        #expect(scorecard.sameHashAndByteSizeOnlyNoOp)
        #expect(scorecard.differentAudioConflictNoOverwrite)
        #expect(scorecard.retryDrainerExistingJobsOnly)
        #expect(scorecard.viewRefreshCreatesNoJob)
        #expect(scorecard.codeComplete)
        #expect(scorecard.readyForManualSwitchTrial == false)
        #expect(scorecard.readyToRetireLegacyReportOnly == false)
        #expect(scorecard.blockers == [.realDeviceEvidenceMissing])
        #expect(scorecard.diagnosticsSummary.contains("canonicalAudioUploadDomainReadiness=v8.55-p2-5"))
        #expect(scorecard.diagnosticsSummary.contains("legacyRetirementExecuted=false"))
    }

    @Test func finalGateV863ScorecardIsCodeCompleteUntilDeviceEvidence() {
        let scorecard = CanonicalSyncKernelCompletionScorecard.v863()

        #expect(scorecard.status == .codeCompleteNeedsDeviceEvidence)
        #expect(scorecard.codeComplete)
        #expect(scorecard.blockers.contains(.realDeviceEvidenceMissing))
        #expect(scorecard.diagnosticsSummary.contains("canonicalSyncKernelCompletionScorecard=v8.63"))
        #expect(scorecard.diagnosticsSummary.contains("v858RecordingRealApplyPortReady=true"))
        #expect(scorecard.diagnosticsSummary.contains("v862SwitchBackProofDriverReady=true"))
    }

    @Test func finalGateV863BlocksMissingRequiredReadiness() {
        let scorecard = CanonicalSyncKernelCompletionScorecard.v863(
            v859AudioCommitExecutorReady: false,
            v861ProductionFilePortTrueWriteGated: false
        )

        #expect(scorecard.status == .blocked)
        #expect(scorecard.codeComplete == false)
        #expect(scorecard.blockers.contains(.audioCommitExecutorMissing))
        #expect(scorecard.blockers.contains(.productionFilePortTrueWriteGateMissing))
    }

    @Test func finalGateV868ReadyForRealDeviceCanonicalSwitchWithoutDeviceEvidence() {
        let scorecard = CanonicalSyncKernelCompletionScorecard.v868()

        #expect(scorecard.codeCompletionResult == .readyForRealDeviceCanonicalSwitch)
        #expect(scorecard.realDeviceEvidencePresent == false)
        #expect(scorecard.blockers.contains(.realDeviceEvidenceMissing))
        #expect(scorecard.diagnosticsSummary.contains("canonicalSyncKernelCompletionScorecard=v8.68"))
        #expect(scorecard.diagnosticsSummary.contains("codeCompleteResult=READY_FOR_REAL_DEVICE_CANONICAL_SWITCH"))
        #expect(scorecard.diagnosticsSummary.contains("t1InventoryMainActorResidualClosureComplete=true"))
        #expect(scorecard.diagnosticsSummary.contains("t6SwitchBackProofDriverComplete=true"))
    }

    @Test func finalGateV868PartialWhenT1ResidualMissingButNoUnsafeBypass() {
        let scorecard = CanonicalSyncKernelCompletionScorecard.v868(
            t1InventoryMainActorResidualClosureComplete: false
        )

        #expect(scorecard.codeCompletionResult == .partialWithBlockers)
        #expect(scorecard.blockers.contains(.t1InventoryMainActorResidualClosureMissing))
    }

    @Test func finalGateV868NotReadyWhenBuildOrT2ToT6Missing() {
        let buildMissing = CanonicalSyncKernelCompletionScorecard.v868(iOSBuildPassed: false)
        let t3Missing = CanonicalSyncKernelCompletionScorecard.v868(
            t3RecordingReadSeamRuntimeWired: false
        )

        #expect(buildMissing.codeCompletionResult == .notReady)
        #expect(buildMissing.blockers.contains(.iOSBuildValidationMissing))
        #expect(t3Missing.codeCompletionResult == .notReady)
        #expect(t3Missing.blockers.contains(.t3RecordingReadSeamRuntimeMissing))
    }

    @Test func finalGateV868UnsafeForReleaseCanonicalLegacyLossAndBypass() {
        let releaseCanonical = CanonicalSyncKernelCompletionScorecard.v868(
            releaseDefaultOldKernel: false
        )
        let scatteredBypass = CanonicalSyncKernelCompletionScorecard.v868(
            noScatteredSwitchBypass: false
        )
        let diagnosticsLeak = CanonicalSyncKernelCompletionScorecard.v868(
            diagnosticsRedacted: false
        )

        #expect(releaseCanonical.codeCompletionResult == .unsafeToTryOnDevice)
        #expect(releaseCanonical.blockers.contains(.releaseDefaultCanonical))
        #expect(scatteredBypass.codeCompletionResult == .unsafeToTryOnDevice)
        #expect(scatteredBypass.blockers.contains(.scatteredSwitchBypass))
        #expect(diagnosticsLeak.codeCompletionResult == .unsafeToTryOnDevice)
        #expect(diagnosticsLeak.blockers.contains(.diagnosticsSensitiveLeak))
    }

    @Test func appStateGateV873ReadyForRealDeviceAppTrialTracksMissingRealDeviceEvidence() {
        let gate = CanonicalRealDeviceTrialReadinessGate.v873()

        #expect(gate.codeCompleteResult == .readyForRealDeviceAppTrial)
        #expect(gate.readyForRealDeviceAppTrial)
        #expect(gate.realDeviceEvidencePresent == false)
        #expect(gate.blockers.isEmpty)
        #expect(gate.diagnosticsSummary.contains("canonicalRealDeviceTrialReadinessGate=v8.73"))
        #expect(gate.diagnosticsSummary.contains("CODE_COMPLETE_RESULT=READY_FOR_REAL_DEVICE_APP_TRIAL"))
        #expect(gate.diagnosticsSummary.contains("realDeviceEvidencePresent=false"))
        #expect(gate.diagnosticsSummary.contains("redacted=true"))
    }

    @Test func appStateGateV873PartialWhenConvergenceRepairIsMissing() {
        let gate = CanonicalRealDeviceTrialReadinessGate.v873(
            eventDrivenSyncTriggerReady: false
        )

        #expect(gate.codeCompleteResult == .partialWithBlockers)
        #expect(gate.readyForRealDeviceAppTrial == false)
        #expect(gate.blockers.contains(.eventDrivenSyncTriggerMissing))
    }

    @Test func appStateGateV873NotReadyWhenBuildOrTargetedTestsMissing() {
        let buildMissing = CanonicalRealDeviceTrialReadinessGate.v873(
            iOSBuildPassed: false
        )
        let testsMissing = CanonicalRealDeviceTrialReadinessGate.v873(
            targetedTestsPassed: false
        )

        #expect(buildMissing.codeCompleteResult == .notReady)
        #expect(buildMissing.blockers.contains(.iOSBuildMissing))
        #expect(testsMissing.codeCompleteResult == .notReady)
        #expect(testsMissing.blockers.contains(.targetedTestsMissing))
    }

    @Test func appStateGateV873UnsafeForSecurityOrStateTruthRegression() {
        let routeChanged = CanonicalRealDeviceTrialReadinessGate.v873(
            routeSecurityUnchanged: false
        )
        let heartbeatHeavy = CanonicalRealDeviceTrialReadinessGate.v873(
            heartbeatCallbackLightweight: false
        )
        let metadataOnlyWrong = CanonicalRealDeviceTrialReadinessGate.v873(
            metadataOnlyRejectedAsAudioAvailable: false
        )

        #expect(routeChanged.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(routeChanged.blockers.contains(.routeSecurityChanged))
        #expect(heartbeatHeavy.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(heartbeatHeavy.blockers.contains(.heartbeatRunsHeavySync))
        #expect(metadataOnlyWrong.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(metadataOnlyWrong.blockers.contains(.metadataOnlyTreatedAsAudioAvailable))
    }

    @Test func manualSwitchGateV868AllowsOnlyReadyScorecardWithOwnerBackupAndProof() {
        var harness = CanonicalLegacySwitchBackHarness()
        let result = CanonicalSyncKernelManualSwitchGate().evaluate(
            CanonicalSyncKernelManualSwitchGateContext(
                scorecard: CanonicalSyncKernelCompletionScorecard.v868(),
                switchBackProof: harness.runSwitchBackProof(),
                ownerApproved: true,
                manualBackupAcknowledged: true,
                codeCompleteResult: .readyForRealDeviceCanonicalSwitch
            )
        )

        #expect(result.allowedForRealDeviceTrial)
        #expect(result.allowedForManualTrial)
        #expect(result.unsafeToTry == false)
        #expect(result.needsOwnerApproval == false)
        #expect(result.needsBackupAcknowledgement == false)
    }

    @Test func manualSwitchGateV868BlocksWithoutBackupSwitchBackOrSafeScorecard() {
        var harness = CanonicalLegacySwitchBackHarness()
        let noBackup = CanonicalSyncKernelManualSwitchGate().evaluate(
            CanonicalSyncKernelManualSwitchGateContext(
                scorecard: CanonicalSyncKernelCompletionScorecard.v868(),
                switchBackProof: harness.runSwitchBackProof(),
                ownerApproved: true,
                manualBackupAcknowledged: false,
                codeCompleteResult: .readyForRealDeviceCanonicalSwitch
            )
        )
        var failedProof = harness.runSwitchBackProof()
        failedProof.switchBackNoMigration = false
        failedProof.blockers = [.switchBackRequiresMigration]
        let noSwitchBack = CanonicalSyncKernelManualSwitchGate().evaluate(
            CanonicalSyncKernelManualSwitchGateContext(
                scorecard: CanonicalSyncKernelCompletionScorecard.v868(),
                switchBackProof: failedProof,
                ownerApproved: true,
                manualBackupAcknowledged: true,
                codeCompleteResult: .readyForRealDeviceCanonicalSwitch,
                switchBackProofDriverAvailable: false
            )
        )
        let unsafe = CanonicalSyncKernelManualSwitchGate().evaluate(
            CanonicalSyncKernelManualSwitchGateContext(
                scorecard: CanonicalSyncKernelCompletionScorecard.v868(
                    releaseDefaultOldKernel: false
                ),
                switchBackProof: harness.runSwitchBackProof(),
                ownerApproved: true,
                manualBackupAcknowledged: true,
                codeCompleteResult: .unsafeToTryOnDevice
            )
        )

        #expect(noBackup.allowedForRealDeviceTrial == false)
        #expect(noBackup.needsBackupAcknowledgement)
        #expect(noBackup.blockers.contains(.manualBackupAcknowledgementMissing))
        #expect(noSwitchBack.allowedForRealDeviceTrial == false)
        #expect(noSwitchBack.needsSwitchBackProof)
        #expect(noSwitchBack.blockers.contains(CanonicalSyncKernelCompletionBlocker.switchBackProofDriverMissing))
        #expect(unsafe.allowedForRealDeviceTrial == false)
        #expect(unsafe.unsafeToTry)
    }

    @Test func manualSwitchGateBlocksWithoutBackupAcknowledgement() {
        let context = gateContext(manualBackupAcknowledged: false)
        let result = CanonicalSyncKernelManualSwitchGate().evaluate(context)

        #expect(result.allowedForManualTrial == false)
        #expect(result.releaseDefaultAllowed == false)
        #expect(result.blockers.contains(.manualBackupAcknowledgementMissing))
    }

    @Test func manualSwitchGateBlocksWithoutSwitchBackProof() {
        var harness = CanonicalLegacySwitchBackHarness()
        var proof = harness.runSwitchBackProof()
        proof.switchBackNoMigration = false
        proof.blockers = [.switchBackRequiresMigration]

        let context = gateContext(switchBackProof: proof)
        let result = CanonicalSyncKernelManualSwitchGate().evaluate(context)

        #expect(result.allowedForManualTrial == false)
        #expect(result.blockers.contains(.switchBackProofMissing))
    }

    @Test func manualSwitchGateBlocksWithoutRealisticRootSwitchBackProof() {
        let context = gateContext(realisticRootSwitchBackProofReady: false)
        let result = CanonicalSyncKernelManualSwitchGate().evaluate(context)

        #expect(result.allowedForManualTrial == false)
        #expect(result.blockers.contains(.realisticRootSwitchBackProofMissing))
    }

    @Test func manualSwitchGateBlocksIfReleaseDefaultIsCanonical() {
        let context = gateContext(releaseMode: .canonicalFullSync)
        let result = CanonicalSyncKernelManualSwitchGate().evaluate(context)

        #expect(result.allowedForManualTrial == false)
        #expect(result.releaseDefaultAllowed == false)
        #expect(result.blockers.contains(.releaseDefaultCanonical))
    }

    @Test func manualSwitchGateBlocksMissingV863FinalGateInputs() {
        let context = gateContext(
            v858RecordingReadSideSeamReady: false,
            diagnosticsGrepListReady: false,
            stopConditionsReady: false
        )
        let result = CanonicalSyncKernelManualSwitchGate().evaluate(context)

        #expect(result.allowedForManualTrial == false)
        #expect(result.blockers.contains(.recordingMetadataReadSideSeamMissing))
        #expect(result.blockers.contains(.diagnosticsGrepListMissing))
        #expect(result.blockers.contains(.stopConditionsMissing))
        #expect(result.diagnosticsSummary.contains("canonicalSyncKernelManualSwitchGate=v8.63"))
    }

    @Test func evidenceExporterRedactsSensitiveSignals() {
        var harness = CanonicalLegacySwitchBackHarness()
        let package = CanonicalSyncKernelEvidenceExporter().export(
            CanonicalSyncKernelEvidenceExportInput(
                modeTransitions: [
                    CanonicalSyncKernelEvidenceModeTransition(
                        fromMode: .oldKernel,
                        toMode: .diagnosticsOnly,
                        phase: "phase-1"
                    )
                ],
                switchBackProof: harness.runSwitchBackProof(),
                rawDiagnosticLines: [
                    "canonicalSyncRuntimePlanUsed objectID=r1",
                    "path=/Users/vita/Project/Rokurics hash=0123456789abcdef0123456789abcdef"
                ]
            )
        )

        #expect(package.redacted)
        #expect(package.redactionProof.sensitiveInputDetected)
        #expect(package.redactionProof.sensitiveOutputDetected == false)
        #expect(package.redactedDiagnostics.joined(separator: "\n").contains("/Users/") == false)
        #expect(package.redactedDiagnostics.joined(separator: "\n").contains("0123456789abcdef0123456789abcdef") == false)
    }

    @Test func runbookMentionsNoLegacyRetirement() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let runbook = root.appendingPathComponent("docs/Rokurics_Canonical_SyncKernel_ManualSwitch_Runbook_v8_45.md")
        let text = try String(contentsOf: runbook, encoding: .utf8)

        #expect(text.contains("No legacy retirement"))
        #expect(text.contains("retirementExecutionPerformed=false"))
        #expect(text.contains("Do not delete legacy"))
    }

    @Test func onDeviceTrialRunbookV863ContainsFinalGateAndStopConditions() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let runbook = root.appendingPathComponent("docs/Rokurics_Canonical_SyncKernel_On_Device_Trial_Runbook_v8_63.md")
        let text = try String(contentsOf: runbook, encoding: .utf8)

        #expect(text.contains("CanonicalSyncKernelCompletionScorecard.v863"))
        #expect(text.contains("diagnosticsOnly"))
        #expect(text.contains("canonicalShadow"))
        #expect(text.contains("canonicalDecisionOnly"))
        #expect(text.contains("canonicalApplyNoAudio"))
        #expect(text.contains("canonicalFullSync"))
        #expect(text.contains("Recording Metadata Modification"))
        #expect(text.contains("Mac MetadataOnly Existence"))
        #expect(text.contains("Audio Upload Finalize"))
        #expect(text.contains("generatedArtifacts Read/Apply"))
        #expect(text.contains("Tombstone/Conflict No Destructive Test"))
        #expect(text.contains("Switch Back oldKernel"))
        #expect(text.contains("Export jsonl"))
        #expect(text.contains("Divergent"))
        #expect(text.contains("FreezeViolation"))
        #expect(text.contains("RollbackFailed"))
        #expect(text.contains("SecurityFailure"))
        #expect(text.contains("ExistingDifferentAudioBlocked"))
    }

    @Test func retirementReportNeverDeletesLegacy() {
        let report = CanonicalSyncKernelDomainReadyToRetireReport.v845ReadyWithDeviceEvidence()

        #expect(report.retirementExecutionPerformed == false)
        #expect(report.legacyDeleted == false)
        #expect(report.legacyDisabled == false)
        #expect(report.allReadyToRetireLegacyReportOnly)
        #expect(report.diagnosticsSummary.contains("retirementExecutionPerformed=false"))
    }

    @Test func appStateGateV915ReadyForFourDomainTrialAllowsMissingRealDeviceEvidence() {
        let gate = CanonicalRealDeviceTrialReadinessGate.v915()

        #expect(gate.codeCompleteResult == .readyForRealDeviceFourDomainAppTrial)
        #expect(gate.readyForRealDeviceFourDomainAppTrial)
        #expect(gate.readyForRealDeviceAppTrial)
        #expect(gate.realDeviceEvidencePresent == false)
        #expect(gate.blockers.isEmpty)
        #expect(gate.diagnosticsSummary.contains("canonicalRealDeviceTrialReadinessGate=v9.15"))
        #expect(gate.diagnosticsSummary.contains("CODE_COMPLETE_RESULT=READY_FOR_REAL_DEVICE_FOUR_DOMAIN_APP_TRIAL"))
        #expect(gate.diagnosticsSummary.contains("realDeviceEvidencePresent=false"))
        #expect(gate.diagnosticsSummary.contains("notReleaseReady=true"))
        #expect(gate.diagnosticsSummary.contains("notRealDevicePassed=true"))
        #expect(gate.diagnosticsSummary.contains("legacyRetirementReady=false"))
    }

    @Test func appStateGateV915NotReadyWhenAnyR1ThroughR7OrBuildSummaryIsMissing() {
        let r1Missing = CanonicalRealDeviceTrialReadinessGate.v915(r1DiagnosticsAsyncHotPathReady: false)
        let r2Missing = CanonicalRealDeviceTrialReadinessGate.v915(r2ContentStableCacheKeyReady: false)
        let r3Missing = CanonicalRealDeviceTrialReadinessGate.v915(r3NoFreezeEvidenceReady: false)
        let r4Missing = CanonicalRealDeviceTrialReadinessGate.v915(r4EffectiveStatusBindingReady: false)
        let r5Missing = CanonicalRealDeviceTrialReadinessGate.v915(r5RealtimeStatusExchangeReady: false)
        let r6ConnectionMissing = CanonicalRealDeviceTrialReadinessGate.v915(r6ConnectionRuntimeAppPathReady: false)
        let r6TransferMissing = CanonicalRealDeviceTrialReadinessGate.v915(r6TransferRuntimeAppPathReady: false)
        let finalizeMissing = CanonicalRealDeviceTrialReadinessGate.v915(finalizeProofFeedsStatusTruth: false)
        let buildSummaryMissing = CanonicalRealDeviceTrialReadinessGate.v915(buildTestSummaryPresent: false)

        #expect(r1Missing.codeCompleteResult == .notReady)
        #expect(r1Missing.blockers.contains(.diagnosticsAsyncHotPathMissing))
        #expect(r2Missing.codeCompleteResult == .notReady)
        #expect(r2Missing.blockers.contains(.contentStableCacheKeyMissing))
        #expect(r3Missing.codeCompleteResult == .notReady)
        #expect(r3Missing.blockers.contains(.noFreezeEvidenceMissing))
        #expect(r4Missing.codeCompleteResult == .notReady)
        #expect(r4Missing.blockers.contains(.effectiveStatusBindingMissing))
        #expect(r5Missing.codeCompleteResult == .notReady)
        #expect(r5Missing.blockers.contains(.realtimeStatusExchangeMissing))
        #expect(r6ConnectionMissing.codeCompleteResult == .notReady)
        #expect(r6ConnectionMissing.blockers.contains(.connectionRuntimeAppPathMissing))
        #expect(r6TransferMissing.codeCompleteResult == .notReady)
        #expect(r6TransferMissing.blockers.contains(.transferRuntimeAppPathMissing))
        #expect(finalizeMissing.codeCompleteResult == .notReady)
        #expect(finalizeMissing.blockers.contains(.finalizeProofNotFeedingStatusTruth))
        #expect(buildSummaryMissing.codeCompleteResult == .notReady)
        #expect(buildSummaryMissing.blockers.contains(.buildTestSummaryMissing))
    }

    @Test func appStateGateV915UnsafeForProductionSafetyRegressions() {
        let fakeTransfer = CanonicalRealDeviceTrialReadinessGate.v915(
            productionFullSyncSelectsFakeOrTestOnlyTransferPort: true
        )
        let routeBypass = CanonicalRealDeviceTrialReadinessGate.v915(routeSecurityUnchanged: false)
        let verifierBypass = CanonicalRealDeviceTrialReadinessGate.v915(requestVerifierUnchanged: false)
        let reverseConnection = CanonicalRealDeviceTrialReadinessGate.v915(macDoesNotReverseConnectToIPhone: false)
        let heavyHeartbeat = CanonicalRealDeviceTrialReadinessGate.v915(heartbeatCallbackLightweight: false)
        let viewRefreshJob = CanonicalRealDeviceTrialReadinessGate.v915(viewRefreshCannotCreateUploadJob: false)
        let freshRetryJob = CanonicalRealDeviceTrialReadinessGate.v915(retryDrainerExistingEligibleOnly: false)
        let metadataOnlyProof = CanonicalRealDeviceTrialReadinessGate.v915(metadataOnlyRejectedAsAudioAvailable: false)
        let completedLedgerProof = CanonicalRealDeviceTrialReadinessGate.v915(completedLedgerAloneRejectedAsProof: false)
        let partialReceiveProof = CanonicalRealDeviceTrialReadinessGate.v915(partialReceiveRejectedAsAudioAvailable: false)
        let defaultCanonical = CanonicalRealDeviceTrialReadinessGate.v915(defaultOldKernel: false)
        let releaseCanonical = CanonicalRealDeviceTrialReadinessGate.v915(releaseDefaultOldKernel: false)
        let missingFallback = CanonicalRealDeviceTrialReadinessGate.v915(legacyFallbackRetained: false)
        let mainActorHotPath = CanonicalRealDeviceTrialReadinessGate.v915(mainActorHotPathSafe: false)
        let retirementAttempt = CanonicalRealDeviceTrialReadinessGate.v915(noLegacyRetirement: false)

        #expect(fakeTransfer.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(fakeTransfer.blockers.contains(.fakeOrTestOnlyProductionTransferPort))
        #expect(routeBypass.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(routeBypass.blockers.contains(.routeSecurityChanged))
        #expect(verifierBypass.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(verifierBypass.blockers.contains(.requestVerifierBypassed))
        #expect(reverseConnection.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(reverseConnection.blockers.contains(.macReverseConnectionAttempted))
        #expect(heavyHeartbeat.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(heavyHeartbeat.blockers.contains(.heartbeatRunsHeavySync))
        #expect(viewRefreshJob.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(viewRefreshJob.blockers.contains(.viewRefreshCreatesUploadJob))
        #expect(freshRetryJob.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(freshRetryJob.blockers.contains(.retryDrainerCreatesFreshUnrelatedJob))
        #expect(metadataOnlyProof.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(metadataOnlyProof.blockers.contains(.metadataOnlyTreatedAsAudioAvailable))
        #expect(completedLedgerProof.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(completedLedgerProof.blockers.contains(.completedLedgerAloneTreatedAsProof))
        #expect(partialReceiveProof.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(partialReceiveProof.blockers.contains(.partialReceiveTreatedAsAudioAvailable))
        #expect(defaultCanonical.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(defaultCanonical.blockers.contains(.defaultOldKernelMissing))
        #expect(releaseCanonical.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(releaseCanonical.blockers.contains(.releaseDefaultCanonical))
        #expect(missingFallback.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(missingFallback.blockers.contains(.legacyFallbackUnavailable))
        #expect(mainActorHotPath.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(mainActorHotPath.blockers.contains(.mainActorHotPathViolation))
        #expect(retirementAttempt.codeCompleteResult == .unsafeToTryOnDevice)
        #expect(retirementAttempt.blockers.contains(.legacyRetirementAttempted))
    }

    private func gateContext(
        switchBackProof: CanonicalLegacySwitchBackProofResult? = nil,
        releaseMode: CanonicalKernelSwitchMode = .oldKernel,
        manualBackupAcknowledged: Bool = true,
        realisticRootSwitchBackProofReady: Bool = true,
        v858RecordingReadSideSeamReady: Bool = true,
        diagnosticsGrepListReady: Bool = true,
        stopConditionsReady: Bool = true
    ) -> CanonicalSyncKernelManualSwitchGateContext {
        var harness = CanonicalLegacySwitchBackHarness()
        return CanonicalSyncKernelManualSwitchGateContext(
            scorecard: CanonicalSyncKernelCompletionScorecard.v845(),
            switchBackProof: switchBackProof ?? harness.runSwitchBackProof(),
            realisticRootSwitchBackProofReady: realisticRootSwitchBackProofReady,
            releaseMode: releaseMode,
            ownerApproved: true,
            manualBackupAcknowledged: manualBackupAcknowledged,
            v858RecordingReadSideSeamReady: v858RecordingReadSideSeamReady,
            diagnosticsGrepListReady: diagnosticsGrepListReady,
            stopConditionsReady: stopConditionsReady
        )
    }
}
