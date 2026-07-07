//
//  CanonicalKernelV9ContractTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalKernelV9ContractTests {
    @Test func connectionEnvelopeCodableRoundTrip() throws {
        let now = CanonicalTimestamp(Date(timeIntervalSince1970: 1))
        let nodeID = CanonicalNodeID("iphone-node")
        let identity = CanonicalNodeIdentity(nodeID: nodeID, role: .iPhone)
        let envelope = CanonicalConnectionEnvelope(
            envelopeID: "heartbeat-1",
            source: identity,
            sequence: CanonicalSequence(7),
            logicalTime: CanonicalLogicalTime(counter: 3, nodeID: nodeID),
            sentAt: now,
            payload: CanonicalHeartbeatPayload(syncRequested: true)
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(CanonicalConnectionEnvelope<CanonicalHeartbeatPayload>.self, from: data)

        #expect(decoded == envelope)
        #expect(decoded.payload.syncRequested)
        #expect(CanonicalKernelModeMirror(switchMode: .oldKernel).switchMode == .oldKernel)
    }

    @Test func transferFinalizeProofIsReceiverAcceptedProof() throws {
        let now = CanonicalTimestamp(Date(timeIntervalSince1970: 2))
        let proof = CanonicalTransferFinalizeProof(
            sessionID: CanonicalTransferSessionID("session-1"),
            objectID: CanonicalObjectID("recording-1"),
            receiverNodeID: CanonicalNodeID("mac-node"),
            contentHash: CanonicalHash("abcdef"),
            byteSize: 42,
            acceptedAt: now
        )

        let data = try JSONEncoder().encode(proof)
        let decoded = try JSONDecoder().decode(CanonicalTransferFinalizeProof.self, from: data)

        #expect(decoded == proof)
        #expect(decoded.isReceiverAcceptedProof)
        #expect(CanonicalTransferProofRule.finalizeProofIsReceiverAcceptedProof)
        #expect(CanonicalTransferProofRule.completedLedgerAloneIsPeerProof == false)
    }

    @Test func statusTruthHardProofRulesRejectSoftEvidence() {
        let now = CanonicalTimestamp(Date(timeIntervalSince1970: 3))
        let objectID = CanonicalObjectID("recording-1")
        let metadataOnly = CanonicalStatusProof(kind: .metadataOnly, objectID: objectID, observedAt: now)
        let receiveOnly = CanonicalStatusProof(kind: .receiveRecordOnly, objectID: objectID, observedAt: now)
        let completedLedger = CanonicalStatusProof(kind: .completedLedgerOnly, objectID: objectID, observedAt: now)
        let partialReceive = CanonicalStatusProof(kind: .partialReceive, objectID: objectID, observedAt: now)
        let peerUnknown = CanonicalStatusProof(kind: .peerUnknown, objectID: objectID, observedAt: now)

        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(metadataOnly).acceptedAsPeerAudioProof == false)
        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(metadataOnly).rule == .metadataOnlyIsNotAudioAvailable)
        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(receiveOnly).rule == .receiveRecordOnlyIsNotAudioAvailable)
        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(completedLedger).rule == .completedLedgerAloneIsNotPeerProof)
        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(partialReceive).effectiveStatus == .partialReceiveNotCompleted)
        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(peerUnknown).effectiveStatus == .peerUnknownDeferred)
        #expect(CanonicalStatusTruthRules.viewRefreshMayCreateUploadJob() == false)
        #expect(CanonicalStatusTruthRules.retryDrainerMayCreateFreshUploadJob() == false)
    }

    @Test func statusTruthAcceptsFinalizeProofAndSameHashSizeNoOp() {
        let now = CanonicalTimestamp(Date(timeIntervalSince1970: 4))
        let objectID = CanonicalObjectID("recording-1")
        let hash = CanonicalHash("abcdef")
        let finalizeProof = CanonicalTransferFinalizeProof(
            sessionID: CanonicalTransferSessionID("session-1"),
            objectID: objectID,
            receiverNodeID: CanonicalNodeID("mac-node"),
            contentHash: hash,
            byteSize: 1024,
            acceptedAt: now
        )
        let proof = CanonicalStatusProof(
            kind: .finalizeProof,
            objectID: objectID,
            peerNodeID: CanonicalNodeID("mac-node"),
            finalizeProof: finalizeProof,
            observedAt: now
        )

        let accepted = CanonicalStatusTruthRules.evaluatePeerAudioProof(proof)
        let noOp = CanonicalStatusTruthRules.evaluateAudioNoOp(
            localHash: hash,
            localByteSize: 1024,
            peerHash: hash,
            peerByteSize: 1024
        )
        let conflict = CanonicalStatusTruthRules.evaluateAudioNoOp(
            localHash: hash,
            localByteSize: 1024,
            peerHash: CanonicalHash("123456"),
            peerByteSize: 1024
        )

        #expect(accepted.acceptedAsPeerAudioProof)
        #expect(accepted.effectiveStatus == .peerVerifiedCompleted)
        #expect(noOp.effectiveStatus == .audioNoOpSameHashAndSize)
        #expect(conflict.effectiveStatus == .conflictNoOverwrite)
    }

    @Test func diagnosticRedactionDetectorCoversForbiddenSignals() {
        let fullHash = String(repeating: "a", count: 64)
        let fingerprint = Array(repeating: "AA", count: 16).joined(separator: ":")
        let unsafe = """
        path=/Users/vita/private/file.m4a hash=\(fullHash) secret token=value fingerprint=\(fingerprint)
        {"metadata":{"title":"raw"}} request body response body raw audio full transcript full note full summary provider response
        """
        let signals = Set(CanonicalKernelDiagnosticRedaction.detectForbiddenSignals(in: unsafe))

        #expect(signals == Set(CanonicalDiagnosticForbiddenSignal.allCases))
        #expect(CanonicalKernelDiagnosticRedaction.isSafeForDiagnostics("kind=statusFactProduced,objectID=recording-1,hashPrefix=abcdef") == true)
    }

    @Test func readinessGateProducesReadyPartialNotReadyAndUnsafe() {
        let ready = CanonicalKernelV9ContractReadinessGate.v900(Self.readyEvidence())
        let partial = CanonicalKernelV9ContractReadinessGate.v900(Self.readyEvidence(docsUpdated: false))
        let notReady = CanonicalKernelV9ContractReadinessGate.v900(CanonicalKernelV9ContractEvidence(baseTypesDefined: true))
        let unsafe = CanonicalKernelV9ContractReadinessGate.v900(Self.readyEvidence(diagnosticsLeakDetected: true))

        #expect(ready.status == .readyForV9RuntimeImplementation)
        #expect(ready.readyForRuntimeImplementation)
        #expect(partial.status == .partialWithBlockers)
        #expect(partial.blockers.contains(.docsMissing))
        #expect(notReady.status == .notReady)
        #expect(notReady.blockers.contains(.connectionContractMissing))
        #expect(unsafe.status == .unsafeToProceed)
        #expect(unsafe.blockers.contains(.diagnosticsLeakDetected))
    }

    @Test func transportIndependentCompileBoundaryHasNoRuntimeBindings() {
        #expect(CanonicalKernelPortableBoundary.requiredImports == ["Foundation"])
        #expect(CanonicalKernelPortableBoundary.adapterSpecificRuntimeBindingCount == 0)
        #expect(CanonicalRealtimeStatusExchangeContract.adapterSpecificRuntimeBindingCount == 0)
        #expect(CanonicalConnectionContract.createsUploadJobs == false)
        #expect(CanonicalConnectionContract.mutatesFileTree == false)
    }

    private static func readyEvidence(
        docsUpdated: Bool = true,
        diagnosticsLeakDetected: Bool = false
    ) -> CanonicalKernelV9ContractEvidence {
        CanonicalKernelV9ContractEvidence(
            baseTypesDefined: true,
            connectionContractDefined: true,
            transferContractDefined: true,
            syncTruthContractDefined: true,
            realtimeExchangeContractDefined: true,
            fileContractDefined: true,
            diagnosticsTaxonomyDefined: true,
            invariantsDefined: true,
            docsUpdated: docsUpdated,
            iPhoneTestsAdded: true,
            macTestsAdded: true,
            transportIndependent: true,
            defaultReleaseOldKernel: true,
            legacyFallbackPreserved: true,
            noRouteOrSchemaChange: true,
            securityLayerUnchanged: true,
            peerProofRulesEnforced: true,
            mainActorHeavyWorkForbidden: true,
            diagnosticsRedactionEnforced: true,
            diagnosticsLeakDetected: diagnosticsLeakDetected
        )
    }
}
