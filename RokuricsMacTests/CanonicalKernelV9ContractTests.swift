//
//  CanonicalKernelV9ContractTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import RokuricsMac

@Suite(.serialized)
struct CanonicalKernelV9ContractTests {
    @Test func realtimeStatusExchangeCodableRoundTrip() throws {
        let now = CanonicalTimestamp(Date(timeIntervalSince1970: 10))
        let macNode = CanonicalNodeID("mac-node")
        let objectID = CanonicalObjectID("recording-1")
        let proof = CanonicalStatusProof(
            kind: .peerHashSize,
            objectID: objectID,
            hash: CanonicalHash("abcdef"),
            byteSize: 4096,
            peerNodeID: macNode,
            observedAt: now
        )
        let fact = CanonicalStatusFact(
            factID: "fact-1",
            objectID: objectID,
            source: .peerHashSize,
            producerNodeID: macNode,
            logicalTime: CanonicalLogicalTime(counter: 4, nodeID: macNode),
            proof: proof
        )
        let envelope = CanonicalStatusExchangeEnvelope(
            envelopeID: "delta-1",
            kind: .delta,
            sourceNodeID: macNode,
            sequence: CanonicalSequence(4),
            logicalTime: CanonicalLogicalTime(counter: 4, nodeID: macNode),
            sentAt: now,
            delta: CanonicalStatusDelta(deltaID: "delta-1", facts: [fact])
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(CanonicalStatusExchangeEnvelope.self, from: data)

        #expect(decoded == envelope)
        #expect(decoded.delta?.facts.first?.proof.kind == .peerHashSize)
    }

    @Test func fileContractCodableRoundTripAndNoFreezeBudget() throws {
        let now = CanonicalTimestamp(Date(timeIntervalSince1970: 11))
        let snapshot = CanonicalFileTreeSnapshot(
            rootID: "study-root",
            capturedAt: now,
            entries: [
                CanonicalFileTreeEntry(
                    objectID: CanonicalObjectID("recording-1"),
                    relativePath: "Recordings/one.m4a",
                    kind: .file,
                    byteSize: 12,
                    modifiedAt: now,
                    contentHash: CanonicalHash("abcdef")
                )
            ],
            builtOffMainActor: true
        )
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CanonicalFileTreeSnapshot.self, from: data)
        let budget = CanonicalNoFreezeBudget()

        #expect(decoded == snapshot)
        #expect(decoded.builtOffMainActor)
        #expect(budget.fileTreeScanRequiresOffMainActor)
        #expect(budget.fullFileHashRequiresOffMainActor)
    }

    @Test func statusTruthHardRulesHoldOnMac() {
        let now = CanonicalTimestamp(Date(timeIntervalSince1970: 12))
        let objectID = CanonicalObjectID("recording-1")
        let localOnly = CanonicalStatusProof(kind: .localFileExists, objectID: objectID, observedAt: now)
        let manifestOnly = CanonicalStatusProof(
            kind: .expectedManifestHash,
            objectID: objectID,
            hash: CanonicalHash("abcdef"),
            observedAt: now
        )
        let differentAudio = CanonicalStatusProof(kind: .existingDifferentAudio, objectID: objectID, observedAt: now)
        let peerHashSize = CanonicalStatusProof(
            kind: .peerHashSize,
            objectID: objectID,
            hash: CanonicalHash("abcdef"),
            byteSize: 100,
            peerNodeID: CanonicalNodeID("iphone-node"),
            observedAt: now
        )

        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(localOnly).rule == .localFileExistsIsNotPeerHasFile)
        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(manifestOnly).rule == .expectedManifestHashIsNotPeerProof)
        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(differentAudio).effectiveStatus == .conflictNoOverwrite)
        #expect(CanonicalStatusTruthRules.evaluatePeerAudioProof(peerHashSize).effectiveStatus == .peerVerifiedCompleted)
    }

    @Test func diagnosticTaxonomyAndRedactionAreCompleteOnMac() {
        let performanceEvents = CanonicalKernelDiagnosticEventKind.allCases.filter { $0.category == .performance }
        let convergenceEvents = CanonicalKernelDiagnosticEventKind.allCases.filter { $0.category == .convergence }
        let unsafe = "response body /private/tmp/audio.m4a full summary provider response"
        let signals = Set(CanonicalKernelDiagnosticRedaction.detectForbiddenSignals(in: unsafe))

        #expect(performanceEvents.contains(.readProjectionRebuildDurationMs))
        #expect(performanceEvents.contains(.diagnosticsWriteDurationMs))
        #expect(convergenceEvents.contains(.syncRequestedHintAdvertised))
        #expect(convergenceEvents.contains(.completedLedgerRejectedAsPeerProof))
        #expect(signals.contains(.responseBody))
        #expect(signals.contains(.absolutePath))
        #expect(signals.contains(.fullSummary))
        #expect(signals.contains(.providerResponse))
    }

    @Test func readinessGateStatesAreDeterministicOnMac() {
        let ready = CanonicalKernelV9ContractReadinessGate.v900(Self.readyEvidence())
        let partial = CanonicalKernelV9ContractReadinessGate.v900(Self.readyEvidence(iPhoneTestsAdded: false))
        let notReady = CanonicalKernelV9ContractReadinessGate.v900(CanonicalKernelV9ContractEvidence(fileContractDefined: true))
        let unsafe = CanonicalKernelV9ContractReadinessGate.v900(Self.readyEvidence(mainActorHeavyWorkAllowed: true))

        #expect(ready.status == .readyForV9RuntimeImplementation)
        #expect(partial.status == .partialWithBlockers)
        #expect(partial.blockers.contains(.iPhoneTestsMissing))
        #expect(notReady.status == .notReady)
        #expect(unsafe.status == .unsafeToProceed)
        #expect(unsafe.blockers.contains(.mainActorHeavyWorkAllowed))
    }

    @Test func contractBoundaryDoesNotBindRuntimeOnMac() {
        #expect(CanonicalKernelPortableBoundary.mutatesApplicationRuntime == false)
        #expect(CanonicalKernelPortableBoundary.adapterSpecificRuntimeBindingCount == 0)
        #expect(CanonicalRealtimeStatusExchangeContract.mutatesFiles == false)
        #expect(CanonicalRealtimeStatusExchangeContract.createsUploadJobs == false)
        #expect(CanonicalKernelInvariantCatalog.v900Required.count >= 12)
    }

    private static func readyEvidence(
        iPhoneTestsAdded: Bool = true,
        mainActorHeavyWorkAllowed: Bool = false
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
            docsUpdated: true,
            iPhoneTestsAdded: iPhoneTestsAdded,
            macTestsAdded: true,
            transportIndependent: true,
            defaultReleaseOldKernel: true,
            legacyFallbackPreserved: true,
            noRouteOrSchemaChange: true,
            securityLayerUnchanged: true,
            peerProofRulesEnforced: true,
            mainActorHeavyWorkForbidden: true,
            diagnosticsRedactionEnforced: true,
            mainActorHeavyWorkAllowed: mainActorHeavyWorkAllowed
        )
    }
}
