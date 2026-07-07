//
//  CanonicalUploadStateTruthTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalUploadStateTruthTests {
    @Test func metadataOnlyReceiveRecordOnlyAndCompletedLedgerAreNotAudioProof() {
        let metadataOnly = Self.truth(peer: .metadataOnly).reconcile()
        let receiveRecordOnly = Self.truth(peer: .receiveRecordOnly).reconcile()
        let ledgerOnly = Self.truth(
            peer: .metadataOnly,
            ledger: CanonicalAudioUploadLedgerTruth(phase: .completed, contentHash: Self.hashA, byteSize: 12, uiUploaded: true)
        ).reconcile()

        #expect(metadataOnly.decision == .peerMetadataOnlyNeedsUpload)
        #expect(receiveRecordOnly.decision == .peerReceiveRecordOnlyNeedsUpload)
        #expect(ledgerOnly.verifiedCompleted == false)
        #expect(metadataOnly.blockers.contains(.metadataOnlyNotAudioAvailable))
        #expect(receiveRecordOnly.blockers.contains(.receiveRecordOnlyNotAudioAvailable))
        #expect(ledgerOnly.blockers.contains(.completedLedgerRejectedAsProof))
    }

    @Test func sameAudioVerifiedAndDifferentAudioConflicts() {
        let same = Self.truth(peer: .audioAvailable, peerHash: Self.hashA, peerSize: 12, peerProof: true).reconcile()
        let different = Self.truth(peer: .audioAvailable, peerHash: Self.hashB, peerSize: 12, peerProof: true).reconcile()

        #expect(same.decision == .uploadNoOpSameAudio)
        #expect(different.decision == .uploadConflictDifferentAudio)
        #expect(different.blockers.contains(.differentHashOrSizeConflict))
    }

    @Test func finalizedProofIsRequiredForCompletedState() {
        let proofMissing = Self.truth(peer: .audioAvailable, peerHash: Self.hashA, peerSize: 12, peerProof: false).reconcile()
        let proofAccepted = Self.truth(
            peer: .metadataOnly,
            proof: CanonicalAudioUploadFinalizeProof(
                objectID: "mac-recording-v850",
                sessionID: CanonicalAudioUploadSessionID("mac-session-v850"),
                byteSize: 12,
                contentHash: Self.hashA,
                macFileSizeVerified: true,
                macHashVerified: true,
                macProofReceived: true,
                receiveRecordMatchesAudioAvailability: true
            )
        ).reconcile()

        #expect(proofMissing.decision == .uploadFinalizedProofPending)
        #expect(proofMissing.verifiedCompleted == false)
        #expect(proofAccepted.decision == .uploadCompletedVerified)
        #expect(proofAccepted.verifiedCompleted)
    }

    @Test func peerUnknownMissingLocalAndTombstonedDoNotRetry() {
        let unknown = Self.truth(peer: .unknown).reconcile()
        let missing = Self.truth(localExists: false, peer: .metadataOnly).reconcile()
        let tombstoned = Self.truth(peer: .metadataOnly, tombstoned: true).reconcile()

        #expect(unknown.decision == .peerUnknownDeferred)
        #expect(missing.decision == .absentLocalAudio)
        #expect(tombstoned.decision == .uploadBlockedTombstoned)
        #expect(unknown.shouldRetry == false)
        #expect(missing.shouldRetry == false)
        #expect(tombstoned.shouldRetry == false)
    }

    @Test func v855DecisionContractBuildsMacReadStatusAndRejectsPeerUnknownFallback() {
        let metadataOnly = CanonicalAudioUploadDecisionResult(input: CanonicalAudioUploadDecisionInput(
            truth: Self.truth(peer: .metadataOnly),
            ownershipPolicy: CanonicalAudioUploadOwnershipPolicy(mode: .canonicalFullSync, gateAllowsCanonical: true)
        ))
        let unknown = CanonicalAudioUploadDecisionResult(input: CanonicalAudioUploadDecisionInput(
            truth: Self.truth(peer: .unknown),
            ownershipPolicy: CanonicalAudioUploadOwnershipPolicy(mode: .canonicalFullSync, gateAllowsCanonical: true)
        ))

        #expect(metadataOnly.proofSchema.isV855Frozen)
        #expect(metadataOnly.fields.schemaVersion == "canonical-audio-upload-v1")
        #expect(metadataOnly.fields.localAudioHashPrefix == String(Self.hashA.value.prefix(12)))
        #expect(metadataOnly.readStatus == .metadataOnly)
        #expect(metadataOnly.canonicalCommitAllowed)
        #expect(unknown.readStatus == .deferredPeerUnknown)
        #expect(unknown.legacyFallbackAllowed == false)
        #expect(unknown.ownershipDecision.owner == .none)
    }

    static func truth(
        localExists: Bool = true,
        peer: CanonicalUploadPeerInventoryState,
        peerHash: CanonicalHash? = nil,
        peerSize: Int64? = nil,
        peerProof: Bool = false,
        ledger: CanonicalAudioUploadLedgerTruth = CanonicalAudioUploadLedgerTruth(),
        proof: CanonicalAudioUploadFinalizeProof? = nil,
        tombstoned: Bool = false
    ) -> CanonicalUploadStateTruth {
        CanonicalUploadStateTruth(
            objectID: "mac-recording-v850",
            localAudioExists: localExists,
            localContentHash: localExists ? hashA : nil,
            localByteSize: localExists ? 12 : nil,
            legacyLedgerTruth: ledger,
            peerInventoryState: peer,
            peerContentHash: peerHash,
            peerByteSize: peerSize,
            peerHashSizeProven: peerProof,
            macFinalizedProof: proof,
            tombstoned: tombstoned
        )
    }

    static let hashA = CanonicalHash(String(repeating: "a", count: 64))
    static let hashB = CanonicalHash(String(repeating: "b", count: 64))
}
