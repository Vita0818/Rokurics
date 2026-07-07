//
//  CanonicalRecordingMetadataCanaryTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalRecordingMetadataCanaryTests {
    @Test func selectorUsesStableN1OrderAndPrefersApplyBeforeSend() {
        let sendB = RecordingMetadataCutoverTestSupport.candidate(id: "recording-b", kind: .recordingMetadataSend)
        let sendA = RecordingMetadataCutoverTestSupport.candidate(id: "recording-a", kind: .recordingMetadataSend)
        let applyA = RecordingMetadataCutoverTestSupport.candidate(id: "recording-a", kind: .recordingMetadataApply)

        let selection = CanonicalRecordingMetadataCanarySelector().select(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            trigger: .periodic,
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [sendB, sendA, applyA]
        )

        #expect(selection.selectedCandidates.map(\.cutoverCandidate.action.actionID) == [applyA.action.actionID])
        #expect(selection.selectedCandidates.first?.actionKind == .apply)
        #expect(selection.evaluatedCandidateCount == 3)
    }

    @Test func selectorBlocksUnsupportedTriggerAndMissingRootBoundPort() {
        var evidence = RecordingMetadataCutoverTestSupport.evidence()
        evidence.realRootBoundApplyPortAvailable = false
        evidence.applyPortMode = .dryRun

        let selection = CanonicalRecordingMetadataCanarySelector().select(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            trigger: .viewRefresh,
            evidence: evidence,
            candidates: [RecordingMetadataCutoverTestSupport.candidate()]
        )
        let reasons = Set(selection.blockers.map(\.reason))

        #expect(selection.selectedCandidates.isEmpty)
        #expect(reasons.contains(.unsupportedTrigger))
        #expect(reasons.contains(.realApplyPortUnavailable))
    }

    @Test func selectorBlocksPriorFailedCandidateWithoutTryingNextOne() {
        let first = RecordingMetadataCutoverTestSupport.candidate(id: "recording-a")
        let second = RecordingMetadataCutoverTestSupport.candidate(id: "recording-b")

        let selection = CanonicalRecordingMetadataCanarySelector().select(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            trigger: .manual,
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [first, second],
            attemptedFailedActionIDs: [first.action.actionID]
        )

        #expect(selection.selectedCandidates.map(\.cutoverCandidate.action.actionID) == [second.action.actionID])
        #expect(selection.blockers.contains { $0.reason == .alreadyAttemptedFailedCandidate })
    }

    @Test func observationReportIsRedactedAndMarksNoRuntimeSwitchOrUploadJob() async throws {
        let result = await RecordingMetadataCutoverTestSupport.run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true)
        )
        let report = try #require(result.observationReport)
        let summary = report.diagnosticsSummary

        #expect(report.status == .completed)
        #expect(report.canaryBudget == 1)
        #expect(report.selectedCandidateCount == 1)
        #expect(report.executedCandidateCount == 1)
        #expect(report.runtimeSwitch == false)
        #expect(report.uiMutated == false)
        #expect(report.uploadJobCreated == false)
        #expect(report.sensitiveFieldsRedacted)
        #expect(summary.contains("/Users/") == false)
        #expect(summary.contains("/private/") == false)
        #expect(summary.contains(String(repeating: "a", count: 64)) == false)
    }

    @Test func stagedN3SelectorRequiresN1EvidenceAndKeepsDeterministicOrder() {
        var evidence = RecordingMetadataCutoverTestSupport.evidence(
            stageEvidence: .passing(
                previousStage: .n1,
                requestedStage: .n3,
                previousStageSuccessCount: 1,
                previousStageSuppressedLegacyDuplicateCount: 1,
                observationWindowID: "n1-window"
            )
        )
        let configuration = CanonicalSingleDomainCutoverConfiguration.stagedCanary(stage: .n3)
        let fourth = RecordingMetadataCutoverTestSupport.candidate(id: "recording-d")
        let first = RecordingMetadataCutoverTestSupport.candidate(id: "recording-a")
        let third = RecordingMetadataCutoverTestSupport.candidate(id: "recording-c")
        let second = RecordingMetadataCutoverTestSupport.candidate(id: "recording-b")

        let selection = CanonicalRecordingMetadataCanarySelector().select(
            configuration: configuration,
            trigger: .periodic,
            evidence: evidence,
            candidates: [fourth, first, third, second]
        )

        #expect(selection.selectedCandidates.map(\.objectID) == ["recording-a", "recording-b", "recording-c"])
        #expect(selection.selectedCandidates.count == 3)

        evidence.canaryStageEvidence = nil
        let missingEvidence = CanonicalRecordingMetadataCanarySelector().select(
            configuration: configuration,
            trigger: .periodic,
            evidence: evidence,
            candidates: [first]
        )
        #expect(missingEvidence.selectedCandidates.isEmpty)
        #expect(missingEvidence.blockers.contains { $0.reason == .canaryStageEvidenceMissing })
    }

    @Test func allEligibleSelectorSelectsEveryEligibleRecordingMetadataCandidateOnly() {
        var evidence = RecordingMetadataCutoverTestSupport.evidence(
            stageEvidence: .passing(
                previousStage: .n10,
                requestedStage: .allEligible,
                previousStageSuccessCount: 10,
                previousStageSuppressedLegacyDuplicateCount: 10,
                observationWindowID: "n10-window"
            )
        )
        let eligibleB = RecordingMetadataCutoverTestSupport.candidate(id: "recording-b")
        let unsupported = RecordingMetadataCutoverTestSupport.candidate(id: "recording-a", kind: .generatedArtifactDownloadApply)
        let conflict = RecordingMetadataCutoverTestSupport.candidate(id: "recording-c", unresolvedConflict: true)
        let eligibleA = RecordingMetadataCutoverTestSupport.candidate(id: "recording-a")

        let selection = CanonicalRecordingMetadataCanarySelector().select(
            configuration: .stagedCanary(stage: .allEligible),
            trigger: .manual,
            evidence: evidence,
            candidates: [eligibleB, unsupported, conflict, eligibleA]
        )

        #expect(selection.selectedCandidates.map(\.objectID) == ["recording-a", "recording-b"])
        #expect(selection.blockers.contains { $0.reason == .unsupportedAction })
        #expect(selection.blockers.contains { $0.reason == .unresolvedConflict })

        evidence.readOnlyTransportProbePassed = false
        let sendSelection = CanonicalRecordingMetadataCanarySelector().select(
            configuration: .stagedCanary(stage: .n3),
            trigger: .manual,
            evidence: evidence,
            candidates: [RecordingMetadataCutoverTestSupport.candidate(id: "recording-send", kind: .recordingMetadataSend)]
        )
        #expect(sendSelection.selectedCandidates.isEmpty)
        #expect(sendSelection.blockers.contains { $0.reason == .canaryStageBlocked })
    }

    @Test func stageEvidenceReportIsRedactedAndBlocksIncompleteObservationWindow() {
        var evidence = CanonicalRecordingMetadataCanaryStageEvidence.passing(
            previousStage: .n3,
            requestedStage: .n10,
            previousStageSuccessCount: 3,
            observationWindowID: "n3-window"
        )
        evidence.observationWindowComplete = false
        let cutoverEvidence = RecordingMetadataCutoverTestSupport.evidence(stageEvidence: evidence)
        let gate = CanonicalRecordingMetadataCanaryStageGate(
            policy: CanonicalRecordingMetadataCanaryStagePolicy(requestedStage: .n10, allowCandidateExecution: true),
            domain: .recordingMetadata,
            token: RecordingMetadataCutoverTestSupport.token(),
            cutoverEvidence: cutoverEvidence
        )
        let summary = gate.evidenceReport.diagnosticsSummary

        #expect(gate.allowed == false)
        #expect(gate.blockers.contains(.observationWindowIncomplete))
        #expect(gate.evidenceReport.status == .incomplete)
        #expect(summary.contains("/Users/") == false)
        #expect(summary.contains("/private/") == false)
        #expect(gate.evidenceReport.sensitiveFieldsRedacted)
    }
}
