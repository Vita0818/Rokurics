//
//  CanonicalUploadStateTruthTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalUploadStateTruthTests {
    @Test func metadataOnlyRejectedAsAudioAvailable() {
        let report = Self.truth(peer: .metadataOnly).reconcile()

        #expect(report.decision == .peerMetadataOnlyNeedsUpload)
        #expect(report.verifiedCompleted == false)
        #expect(report.blockers.contains(.metadataOnlyNotAudioAvailable))
        #expect(report.diagnostics.contains { $0.kind == .canonicalUploadMetadataOnlyRejectedAsAudioAvailable })
    }

    @Test func receiveRecordOnlyRejectedAsAudioAvailable() {
        let report = Self.truth(peer: .receiveRecordOnly).reconcile()

        #expect(report.decision == .peerReceiveRecordOnlyNeedsUpload)
        #expect(report.verifiedCompleted == false)
        #expect(report.blockers.contains(.receiveRecordOnlyNotAudioAvailable))
    }

    @Test func completedLedgerAloneRejectedAsCompletedProof() {
        let report = Self.truth(
            peer: .metadataOnly,
            ledger: CanonicalAudioUploadLedgerTruth(phase: .completed, contentHash: Self.hashA, byteSize: 12, uiUploaded: true)
        ).reconcile()

        #expect(report.decision == .peerMetadataOnlyNeedsUpload)
        #expect(report.verifiedCompleted == false)
        #expect(report.blockers.contains(.completedLedgerRejectedAsProof))
        #expect(report.diagnostics.contains { $0.kind == .canonicalUploadCompletedLedgerRejectedAsProof })
    }

    @Test func finalizedMacProofAccepted() {
        let report = Self.truth(
            peer: .metadataOnly,
            proof: CanonicalAudioUploadFinalizeProof(
                objectID: "recording-v850",
                sessionID: CanonicalAudioUploadSessionID("session-v850-final"),
                byteSize: 12,
                contentHash: Self.hashA,
                macFileSizeVerified: true,
                macHashVerified: true,
                macProofReceived: true,
                receiveRecordMatchesAudioAvailability: true
            )
        ).reconcile()

        #expect(report.decision == .uploadCompletedVerified)
        #expect(report.verifiedCompleted)
        #expect(report.blockers.contains(.completedLedgerRejectedAsProof) == false)
        #expect(report.diagnostics.contains { $0.kind == .canonicalUploadFinalizedProofAccepted })
    }

    @Test func sameHashAndByteSizeIsNoOpOnlyWhenBothMatch() {
        let report = Self.truth(peer: .audioAvailable, peerHash: Self.hashA, peerSize: 12, peerProof: true).reconcile()

        #expect(report.decision == .uploadNoOpSameAudio)
        #expect(report.blockers.contains(.differentHashOrSizeConflict) == false)
    }

    @Test func differentHashOrSizeIsConflict() {
        let differentHash = Self.truth(peer: .audioAvailable, peerHash: Self.hashB, peerSize: 12, peerProof: true).reconcile()
        let differentSize = Self.truth(peer: .audioAvailable, peerHash: Self.hashA, peerSize: 99, peerProof: true).reconcile()

        #expect(differentHash.decision == .uploadConflictDifferentAudio)
        #expect(differentSize.decision == .uploadConflictDifferentAudio)
        #expect(differentHash.blockers.contains(.differentHashOrSizeConflict))
        #expect(differentSize.blockers.contains(.differentHashOrSizeConflict))
    }

    @Test func peerUnknownDeferred() {
        let report = Self.truth(peer: .unknown).reconcile()

        #expect(report.decision == .peerUnknownDeferred)
        #expect(report.shouldCreateUploadJob == false)
        #expect(report.blockers.contains(.peerUnknown))
        #expect(report.diagnostics.contains { $0.kind == .canonicalUploadPeerUnknownDeferred })
    }

    @Test func localMissingAudioBlocksCandidate() {
        let report = Self.truth(localExists: false, peer: .metadataOnly).reconcile()

        #expect(report.decision == .absentLocalAudio)
        #expect(report.shouldCreateUploadJob == false)
        #expect(report.blockers.contains(.missingLocalAudio))
    }

    @Test func tombstonedParentBlocksUpload() {
        let report = Self.truth(peer: .metadataOnly, tombstoned: true).reconcile()

        #expect(report.decision == .uploadBlockedTombstoned)
        #expect(report.shouldRetry == false)
        #expect(report.blockers.contains(.tombstonedParent))
    }

    @Test func expectedManifestHashAndSizeAreNotPeerProof() {
        let report = Self.truth(
            peer: .metadataOnly,
            expectedManifestHash: Self.hashA,
            expectedManifestByteSize: 12
        ).reconcile()

        #expect(report.decision == .peerMetadataOnlyNeedsUpload)
        #expect(report.verifiedCompleted == false)
        #expect(report.blockers.contains(.expectedManifestHashNotPeerProof))
    }

    @Test func diagnosticsRedactHashesAndUnsafeIdentifiers() {
        let fullHash = String(repeating: "f", count: 64)
        let report = CanonicalUploadStateTruth(
            objectID: "/Users/vita/private/recording-v850",
            localAudioExists: true,
            localContentHash: CanonicalHash(fullHash),
            localByteSize: 12,
            peerInventoryState: .metadataOnly
        ).reconcile()
        let text = report.diagnostics.map(\.diagnosticsSummary).joined(separator: "\n")

        #expect(text.contains(fullHash) == false)
        #expect(text.contains("/Users/vita") == false)
        #expect(text.contains(String(fullHash.prefix(12))))
    }

    @Test func v855DecisionContractBuildsRedactedFieldsAndReadStatus() {
        let input = CanonicalAudioUploadDecisionInput(
            truth: Self.truth(peer: .metadataOnly),
            ownershipPolicy: CanonicalAudioUploadOwnershipPolicy(
                mode: .canonicalFullSync,
                gateAllowsCanonical: true
            )
        )
        let result = CanonicalAudioUploadDecisionResult(input: input)
        let projection = CanonicalUploadStatusProjectionResult(report: result.stateReport)

        #expect(result.proofSchema.version == CanonicalAudioUploadProofSchema.version)
        #expect(result.proofSchema.isV855Frozen)
        #expect(result.fields.schemaVersion == "canonical-audio-upload-v1")
        #expect(result.fields.localAudioHashPrefix == String(Self.hashA.value.prefix(12)))
        #expect(result.fields.diagnosticsSummary.contains(Self.hashA.value) == false)
        #expect(result.availability == .metadataOnly)
        #expect(result.readStatus == .metadataOnly)
        #expect(projection.readStatus == .metadataOnly)
        #expect(result.canonicalDecisionEvaluated)
        #expect(result.canonicalDecisionUsed)
        #expect(result.canonicalCommitAllowed)
        #expect(result.ownershipDecision.owner == .canonical)
    }

    @Test func v855PeerUnknownDefersWithoutFallbackOverwrite() {
        let input = CanonicalAudioUploadDecisionInput(
            truth: Self.truth(peer: .unknown),
            ownershipPolicy: CanonicalAudioUploadOwnershipPolicy(
                mode: .canonicalFullSync,
                gateAllowsCanonical: true
            )
        )
        let result = CanonicalAudioUploadDecisionResult(input: input)

        #expect(result.readStatus == .deferredPeerUnknown)
        #expect(result.canonicalCommitAllowed == false)
        #expect(result.legacyFallbackAllowed == false)
        #expect(result.ownershipDecision.owner == .none)
        #expect(result.ownershipDecision.blockers.contains(.peerUnknown))
    }

    static func truth(
        localExists: Bool = true,
        peer: CanonicalUploadPeerInventoryState,
        peerHash: CanonicalHash? = nil,
        peerSize: Int64? = nil,
        peerProof: Bool = false,
        ledger: CanonicalAudioUploadLedgerTruth = CanonicalAudioUploadLedgerTruth(),
        proof: CanonicalAudioUploadFinalizeProof? = nil,
        expectedManifestHash: CanonicalHash? = nil,
        expectedManifestByteSize: Int64? = nil,
        tombstoned: Bool = false
    ) -> CanonicalUploadStateTruth {
        CanonicalUploadStateTruth(
            objectID: "recording-v850",
            localAudioExists: localExists,
            localContentHash: localExists ? hashA : nil,
            localByteSize: localExists ? 12 : nil,
            legacyLedgerTruth: ledger,
            peerInventoryState: peer,
            peerContentHash: peerHash,
            peerByteSize: peerSize,
            peerHashSizeProven: peerProof,
            macFinalizedProof: proof,
            expectedManifestHash: expectedManifestHash,
            expectedManifestByteSize: expectedManifestByteSize,
            tombstoned: tombstoned
        )
    }

    static let hashA = CanonicalHash(String(repeating: "a", count: 64))
    static let hashB = CanonicalHash(String(repeating: "b", count: 64))
}
