//
//  CanonicalAudioUploadCutoverPreparationTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalAudioUploadCutoverPreparationTests {
    @Test func macAppSeamDefaultsDisabledAndCanaryBudgetZero() {
        let config = CanonicalAudioUploadCutoverAppSeamConfiguration()

        #expect(config.isEnabled == false)
        #expect(config.effectiveMode == .disabled)
        #expect(config.cutoverMode == .disabled)
        #expect(config.policy.canaryPolicy.canaryMaxObjectsPerSyncRun == 0)
        #expect(config.policy.canaryPolicy.productionCommitAllowedInV812 == false)
    }

    @Test func macNoCommitExecutorDoesNotWriteReceiverInboxLedgerOrRetryState() {
        let candidate = MacAudioUploadCutoverTestSupport.candidate(peerState: .missing)
        let result = CanonicalAudioUploadNoCommitRunner().run(
            mode: .guardedExecuteNoCommit,
            policy: CanonicalAudioUploadCanaryPolicy(requestedStage: .shadowOnly),
            token: nil,
            evidence: .passing(report: CanonicalAudioUploadEvidenceReport(candidates: [candidate])),
            candidates: [CanonicalAudioUploadNoCommitCandidate(cutoverCandidate: candidate)],
            trigger: .ordinarySync,
            nodeRole: .mac,
            syncRunID: "mac-audio-v812-no-commit",
            executor: MacAudioUploadNoCommitExecutor()
        )
        let staged = result.noCommitResults.first

        #expect(result.gate.allowed)
        #expect(result.gate.productionUploadAllowed == false)
        #expect(result.runtimeSwitchEnabled == false)
        #expect(result.calledProductionUploadCoordinator == false)
        #expect(result.calledRecordingUploadClient == false)
        #expect(result.calledSecureMacUploadClient == false)
        #expect(result.wroteProductionInbox == false)
        #expect(result.wroteReceiveJSON == false)
        #expect(result.createdUploadJob == false)
        #expect(result.mutatedUploadLedger == false)
        #expect(result.mutatedRetryDrainer == false)
        #expect(staged?.nodeRole == .mac)
        #expect(staged?.productionUploadSuppressed == true)
        #expect(staged?.didNotWriteInbox == true)
        #expect(staged?.didNotWriteReceiveJSON == true)
        #expect(staged?.didNotMutateUploadLedger == true)
        #expect(staged?.didNotMutateRetryDrainer == true)
    }

    @Test func macInventoryPeerUnknownIsDeferredAndCompletedLedgerIsNotNoOp() {
        let local = CanonicalAudioUploadLocalTruth.available(
            hash: MacAudioUploadCutoverTestSupport.hash("a"),
            byteSize: 64,
            logicalPathToken: "audio/recording-01.m4a",
            sourceDeviceID: "mac-01"
        )
        let unknown = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: local,
            peerTruth: CanonicalAudioUploadPeerTruth(state: .unknown, diagnosticsSummary: "peerManifestUnavailable"),
            trigger: .ordinarySync
        )
        let ledgerOnly = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: local,
            peerTruth: CanonicalAudioUploadPeerTruth(state: .missing, receiveRecordExists: true),
            ledgerTruth: CanonicalAudioUploadLedgerTruth(phase: .completed, receiveRecordExists: true),
            trigger: .ordinarySync
        )

        #expect(unknown.actionKind == .audioUploadDeferredPeerUnknown)
        #expect(unknown.evidenceStatus == .deferred)
        #expect(unknown.evidenceBlockers.contains(.peerUnknown))
        #expect(ledgerOnly.actionKind == .audioUploadCanaryCandidate)
        #expect(ledgerOnly.evidenceStatus == .blocked)
        #expect(ledgerOnly.evidenceBlockers.contains(.completedLedgerWithoutPeerMatch))
        #expect(ledgerOnly.evidenceBlockers.contains(.receiveRecordNotAudioProof))
    }

    @Test func macCanaryN1RemainsBlockedInV812() {
        let candidate = MacAudioUploadCutoverTestSupport.candidate(peerState: .missing)
        let gate = CanonicalAudioUploadCutoverRunner().evaluateGate(
            mode: .canary,
            policy: CanonicalAudioUploadCanaryPolicy(requestedStage: .n1),
            token: MacAudioUploadCutoverTestSupport.token(),
            evidence: .passing(report: CanonicalAudioUploadEvidenceReport(candidates: [candidate])),
            candidates: [candidate],
            trigger: .ordinarySync
        )

        #expect(gate.allowed == false)
        #expect(gate.productionUploadAllowed == false)
        #expect(gate.failures.contains(.productionCommitBlockedV812))
        #expect(gate.failures.contains(.futureCanaryStageBlocked))
    }

    @Test func macReadSideProjectionAndRollbackPolicyAreDiagnosticsOnly() {
        let candidate = MacAudioUploadCutoverTestSupport.candidate(peerState: .missing)
        let projection = CanonicalAudioUploadReadSideParallelProjection.project(
            candidates: [candidate],
            syncRunID: "mac-audio-projection",
            trigger: .ordinarySync,
            nodeRole: .mac
        )
        let cleanup = CanonicalAudioUploadRollbackPolicy().cleanupPartialShadowSession()

        #expect(projection.equivalent)
        #expect(projection.mutatedUI == false)
        #expect(projection.wroteUIState == false)
        #expect(projection.createdUploadJob == false)
        #expect(cleanup.shadowPartialSessionCleaned)
        #expect(cleanup.productionAudioDeleted == false)
        #expect(cleanup.receiveJSONDeleted == false)
    }
}

enum MacAudioUploadCutoverTestSupport {
    static func hash(_ seed: String) -> CanonicalHash {
        CanonicalHash(String(repeating: seed.prefix(1).isEmpty ? "a" : String(seed.prefix(1)), count: 64))
    }

    static func token() -> CanonicalCutoverToken {
        CanonicalCutoverToken(tokenID: "mac-audio-upload-v812-token", syncRunID: "mac-audio-upload-v812", ownerApproved: true)
    }

    static func candidate(peerState: CanonicalAudioUploadPeerState) -> CanonicalAudioUploadCutoverCandidate {
        CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: .available(
                hash: hash("a"),
                byteSize: 64,
                logicalPathToken: "audio/recording-01.m4a",
                sourceDeviceID: "mac-01"
            ),
            peerTruth: CanonicalAudioUploadPeerTruth(state: peerState),
            trigger: .ordinarySync
        )
    }
}
