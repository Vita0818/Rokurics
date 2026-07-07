//
//  CanonicalAudioUploadCutoverPreparationTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalAudioUploadCutoverPreparationTests {
    @Test func appSeamDefaultsDisabledAndCanaryBudgetZero() {
        let config = CanonicalAudioUploadCutoverAppSeamConfiguration()

        #expect(config.isEnabled == false)
        #expect(config.effectiveMode == .disabled)
        #expect(config.cutoverMode == .disabled)
        #expect(config.policy.canaryPolicy.canaryMaxObjectsPerSyncRun == 0)
        #expect(config.policy.canaryPolicy.productionCommitAllowedInV812 == false)
    }

    @Test func peerSameNoOpRequiresHashAndSizeAndLedgerAloneIsRejected() {
        let hash = AudioUploadCutoverTestSupport.hash("same")
        let local = CanonicalAudioUploadLocalTruth.available(hash: hash, byteSize: 12, logicalPathToken: "audio/recording-01.m4a")
        let noOp = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: local,
            peerTruth: CanonicalAudioUploadPeerTruth(state: .available, contentHash: hash, byteSize: 12),
            trigger: .ordinarySync
        )

        #expect(noOp.actionKind == .audioUploadNoOp)
        #expect(noOp.evidenceStatus == .complete)
        #expect(noOp.evidenceBlockers.isEmpty)

        let ledgerOnly = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: local,
            peerTruth: CanonicalAudioUploadPeerTruth(
                state: .missing,
                receiveRecordExists: true,
                metadataUploaded: true,
                uiUploaded: true
            ),
            ledgerTruth: CanonicalAudioUploadLedgerTruth(
                phase: .completed,
                contentHash: hash,
                byteSize: 12,
                metadataUploaded: true,
                uiUploaded: true,
                receiveRecordExists: true
            ),
            trigger: .ordinarySync
        )

        #expect(ledgerOnly.actionKind == .audioUploadCanaryCandidate)
        #expect(ledgerOnly.evidenceStatus == .blocked)
        #expect(ledgerOnly.evidenceBlockers.contains(.completedLedgerWithoutPeerMatch))
        #expect(ledgerOnly.evidenceBlockers.contains(.metadataUploadedNotAudioProof))
        #expect(ledgerOnly.evidenceBlockers.contains(.receiveRecordNotAudioProof))
        #expect(ledgerOnly.evidenceBlockers.contains(.uiUploadedNotAudioProof))
        #expect(ledgerOnly.diagnostics.contains(.canonicalAudioUploadCompletedLedgerRejectedAsNoOp))
    }

    @Test func peerUnknownViewRefreshRetryAndManualUploadRemainDeferredOrLegacy() {
        let local = CanonicalAudioUploadLocalTruth.available(
            hash: AudioUploadCutoverTestSupport.hash("local"),
            byteSize: 20
        )
        let unknown = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: local,
            peerTruth: CanonicalAudioUploadPeerTruth(state: .unknown),
            trigger: .ordinarySync
        )
        let viewRefresh = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: local,
            peerTruth: CanonicalAudioUploadPeerTruth(state: .missing),
            trigger: .viewRefresh
        )
        let retryDrainer = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: local,
            peerTruth: CanonicalAudioUploadPeerTruth(state: .missing),
            retryTruth: CanonicalAudioUploadRetryTruth(hasExistingEligibleRetry: false, retryPending: false, canFreshCreateJob: false),
            trigger: .retryDrainer
        )
        let manualButton = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: local,
            peerTruth: CanonicalAudioUploadPeerTruth(state: .unknown),
            trigger: .manualUploadButton
        )

        #expect(unknown.actionKind == .audioUploadDeferredPeerUnknown)
        #expect(unknown.evidenceBlockers.contains(.peerUnknown))
        #expect(viewRefresh.actionKind == .unsupported)
        #expect(viewRefresh.evidenceBlockers.contains(.viewRefreshSuppressed))
        #expect(retryDrainer.actionKind == .unsupported)
        #expect(retryDrainer.evidenceBlockers.contains(.retryDrainerFreshJobSuppressed))
        #expect(manualButton.actionKind == .unsupported)
        #expect(manualButton.evidenceBlockers.contains(.manualUploadButtonLegacyOwned))
    }

    @Test func noCommitExecutorStagesOnlySuppressedSummaryAndPreservesFallback() {
        let candidate = AudioUploadCutoverTestSupport.candidate(peerState: .missing)
        let report = CanonicalAudioUploadEvidenceReport(candidates: [candidate])
        let result = CanonicalAudioUploadNoCommitRunner().run(
            mode: .guardedExecuteNoCommit,
            policy: CanonicalAudioUploadCanaryPolicy(requestedStage: .shadowOnly),
            token: nil,
            evidence: .passing(report: report),
            candidates: [CanonicalAudioUploadNoCommitCandidate(cutoverCandidate: candidate)],
            trigger: .ordinarySync,
            nodeRole: .iPhone,
            syncRunID: "audio-v812-no-commit",
            executor: IPhoneAudioUploadNoCommitExecutor()
        )
        let staged = result.noCommitResults.first

        #expect(result.gate.allowed)
        #expect(result.gate.productionUploadAllowed == false)
        #expect(result.runtimeSwitchEnabled == false)
        #expect(result.legacyFallbackPreserved)
        #expect(result.calledProductionUploadCoordinator == false)
        #expect(result.calledRecordingUploadClient == false)
        #expect(result.calledSecureMacUploadClient == false)
        #expect(result.wroteProductionInbox == false)
        #expect(result.wroteReceiveJSON == false)
        #expect(result.createdUploadJob == false)
        #expect(result.mutatedUploadLedger == false)
        #expect(result.mutatedRetryDrainer == false)
        #expect(result.suppressedLegacyDuplicate == false)
        #expect(staged?.staged == true)
        #expect(staged?.wouldRequestRoute == "/upload-recording-audio-session/start")
        #expect(staged?.productionUploadSuppressed == true)
        #expect(staged?.didNotCreateUploadJob == true)
        #expect(staged?.didNotWriteInbox == true)
        #expect(staged?.didNotWriteReceiveJSON == true)
        #expect(staged?.didNotMutateUploadLedger == true)
        #expect(staged?.didNotMutateRetryDrainer == true)
    }

    @Test func canaryN1IsBlockedInV812EvenWithEvidence() {
        let candidate = AudioUploadCutoverTestSupport.candidate(peerState: .missing)
        let gate = CanonicalAudioUploadCutoverRunner().evaluateGate(
            mode: .canary,
            policy: CanonicalAudioUploadCanaryPolicy(requestedStage: .n1),
            token: AudioUploadCutoverTestSupport.token(),
            evidence: .passing(report: CanonicalAudioUploadEvidenceReport(candidates: [candidate])),
            candidates: [candidate],
            trigger: .ordinarySync
        )

        #expect(gate.allowed == false)
        #expect(gate.productionUploadAllowed == false)
        #expect(gate.failures.contains(.productionCommitBlockedV812))
        #expect(gate.failures.contains(.futureCanaryStageBlocked))
    }

    @Test func shadowReceiverRehearsesResumeNoOpAndConflictWithoutProductionWrites() async throws {
        let bytes = Data("abcdefghi".utf8)
        let receiver = CanonicalAudioUploadShadowReceiver(rootToken: CanonicalRootToken("audio-shadow-test"))
        let rehearsal = await CanonicalAudioUploadShadowRehearsal().run(
            input: CanonicalAudioUploadShadowRehearsalInput(
                objectID: "recording-01",
                logicalPathToken: "audio/recording-01.m4a",
                bytes: bytes,
                chunkSize: 4,
                simulateInterruptionAfterFirstChunk: true
            ),
            receiver: receiver,
            syncRunID: "shadow-rehearsal",
            trigger: .ordinarySync,
            nodeRole: .iPhone
        )
        let reference = CanonicalFileReference(
            rootToken: receiver.rootToken,
            logicalPathToken: "audio/recording-01.m4a",
            artifactID: CanonicalProjectionContract.artifactID(objectID: "recording-01", kind: .audio),
            artifactKind: .audio
        )
        let stored = try await receiver.read(reference: reference)

        #expect(rehearsal.shadowResult.completed)
        #expect(rehearsal.shadowResult.divergence == .interruptedAndResumed)
        #expect(stored.bytes == bytes)
        #expect(rehearsal.productionUploadSuppressed)
        #expect(rehearsal.calledProductionUploadCoordinator == false)
        #expect(rehearsal.calledRecordingUploadClient == false)
        #expect(rehearsal.calledSecureMacUploadClient == false)
        #expect(rehearsal.wroteProductionInbox == false)
        #expect(rehearsal.wroteReceiveJSON == false)

        let noOp = await CanonicalAudioUploadShadowRehearsal().run(
            input: CanonicalAudioUploadShadowRehearsalInput(
                objectID: "recording-01",
                logicalPathToken: "audio/recording-01.m4a",
                bytes: bytes,
                existingReceiverBytes: bytes
            ),
            receiver: CanonicalAudioUploadShadowReceiver(rootToken: CanonicalRootToken("audio-shadow-noop"))
        )
        let conflict = await CanonicalAudioUploadShadowRehearsal().run(
            input: CanonicalAudioUploadShadowRehearsalInput(
                objectID: "recording-01",
                logicalPathToken: "audio/recording-01.m4a",
                bytes: bytes,
                existingReceiverBytes: Data("different".utf8)
            ),
            receiver: CanonicalAudioUploadShadowReceiver(rootToken: CanonicalRootToken("audio-shadow-conflict"))
        )

        #expect(noOp.shadowResult.completed)
        #expect(noOp.shadowResult.divergence == .sameHashNoOp)
        #expect(noOp.shadowResult.wroteShadowReceiver == false)
        #expect(conflict.shadowResult.completed == false)
        #expect(conflict.shadowResult.divergence == .differentHashConflict)
    }

    @Test func rollbackPolicyAndReadSideProjectionAreNonMutating() {
        let candidate = AudioUploadCutoverTestSupport.candidate(peerState: .missing)
        let rollback = CanonicalAudioUploadRollbackPolicy()
        let cleanup = rollback.cleanupPartialShadowSession()
        let projection = CanonicalAudioUploadReadSideParallelProjection.project(
            candidates: [candidate],
            syncRunID: "projection",
            trigger: .ordinarySync,
            nodeRole: .iPhone
        )

        #expect(rollback.preFinalizeAbort.canCancelSession)
        #expect(rollback.postFinalizeRollback.canDeleteProductionAudio == false)
        #expect(rollback.neverDeleteProductionAudio)
        #expect(rollback.neverDeleteReceiveJSON)
        #expect(cleanup.shadowPartialSessionCleaned)
        #expect(cleanup.productionAudioDeleted == false)
        #expect(cleanup.receiveJSONDeleted == false)
        #expect(cleanup.legacyFallbackPreserved)
        #expect(projection.equivalent)
        #expect(projection.mutatedUI == false)
        #expect(projection.wroteUIState == false)
        #expect(projection.createdUploadJob == false)
    }
}

enum AudioUploadCutoverTestSupport {
    static func hash(_ seed: String) -> CanonicalHash {
        CanonicalHash(String(repeating: seed.prefix(1).isEmpty ? "a" : String(seed.prefix(1)), count: 64))
    }

    static func token() -> CanonicalCutoverToken {
        CanonicalCutoverToken(tokenID: "audio-upload-v812-token", syncRunID: "audio-upload-v812", ownerApproved: true)
    }

    static func candidate(peerState: CanonicalAudioUploadPeerState) -> CanonicalAudioUploadCutoverCandidate {
        CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: .available(
                hash: hash("a"),
                byteSize: 32,
                logicalPathToken: "audio/recording-01.m4a",
                sourceDeviceID: "iphone-01"
            ),
            peerTruth: CanonicalAudioUploadPeerTruth(state: peerState),
            trigger: .ordinarySync
        )
    }
}
