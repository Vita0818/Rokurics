//
//  CanonicalStatusExchangeRuntimeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import RokuricsMac

@Suite(.serialized)
struct CanonicalStatusExchangeRuntimeTests {
    private static let now = CanonicalTimestamp(Date(timeIntervalSince1970: 9_700))
    private static let later = CanonicalTimestamp(Date(timeIntervalSince1970: 9_701))
    private static let objectID = CanonicalObjectID("recording-v970-mac")
    private static let iPhoneNode = CanonicalNodeID("iphone-v970")
    private static let macNode = CanonicalNodeID("mac-v970")
    private static let hashA = CanonicalHash(String(repeating: "d", count: 64))

    @Test func incomingFinalizeProofDeltaCompletesTruthEngine() async throws {
        let truth = Self.runtime()
        let exchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.macNode,
            truthRuntime: truth,
            nowProvider: { Self.now }
        )
        let finalize = Self.fact(
            "finalize-proof-delta",
            source: .transferFinalizeProof,
            kind: .finalizeProof,
            phase: .completed,
            proof: Self.finalizeProof()
        )
        let envelope = Self.envelope(
            sequence: 1,
            kind: .delta,
            source: Self.iPhoneNode,
            destination: Self.macNode,
            delta: CanonicalStatusDelta(deltaID: "finalize-delta", facts: [finalize])
        )

        let result = await exchange.consumeIncomingEnvelope(envelope, carrier: .heartbeat)
        let status = try await truth.reconcile(facts: await truth.facts(for: Self.objectID)).effectiveStatus

        #expect(result.accepted)
        #expect(result.incorporatedFactCount == 1)
        #expect(status.phase == .completed)
        #expect(status.canDisplayAsComplete)
        #expect(status.proof?.hasAcceptedFinalizeProof == true)
    }

    @Test func metadataOnlyDeltaDoesNotMarkAudioComplete() async throws {
        let truth = Self.runtime()
        let exchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.macNode,
            truthRuntime: truth,
            nowProvider: { Self.now }
        )
        let metadataOnly = Self.fact("metadata-only-delta", source: .metadataOnlyLedger, kind: .metadataOnly, phase: .metadataOnly)
        let envelope = Self.envelope(
            sequence: 1,
            kind: .delta,
            source: Self.iPhoneNode,
            destination: Self.macNode,
            delta: CanonicalStatusDelta(deltaID: "metadata-only-delta", facts: [metadataOnly])
        )

        let result = await exchange.consumeIncomingEnvelope(envelope, carrier: .inventory)
        let status = try await truth.reconcile(facts: await truth.facts(for: Self.objectID)).effectiveStatus

        #expect(result.accepted)
        #expect(status.canDisplayAsComplete == false)
        #expect(status.phase == .peerKnownMetadataOnly)
        #expect(status.blocker == .metadataOnlyRejectedAsAudioProof)
    }

    @Test func lowerProofConflictCannotOverrideFinalizeProof() async throws {
        let truth = Self.runtime()
        let exchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.macNode,
            truthRuntime: truth,
            nowProvider: { Self.now }
        )
        let finalizeEnvelope = Self.envelope(
            sequence: 1,
            kind: .delta,
            source: Self.iPhoneNode,
            destination: Self.macNode,
            delta: CanonicalStatusDelta(
                deltaID: "finalize-delta",
                facts: [
                    Self.fact(
                        "finalize-proof-delta",
                        source: .transferFinalizeProof,
                        kind: .finalizeProof,
                        phase: .completed,
                        proof: Self.finalizeProof()
                    )
                ]
            )
        )
        let metadataEnvelope = Self.envelope(
            sequence: 2,
            kind: .delta,
            source: Self.iPhoneNode,
            destination: Self.macNode,
            delta: CanonicalStatusDelta(
                deltaID: "metadata-only-delta",
                facts: [
                    Self.fact(
                        "metadata-only-lower-proof",
                        source: .metadataOnlyLedger,
                        kind: .metadataOnly,
                        phase: .metadataOnly,
                        counter: 2
                    )
                ]
            )
        )

        _ = await exchange.consumeIncomingEnvelope(finalizeEnvelope, carrier: .heartbeat)
        _ = await exchange.consumeIncomingEnvelope(metadataEnvelope, carrier: .heartbeat)
        let status = try await truth.reconcile(facts: await truth.facts(for: Self.objectID)).effectiveStatus

        #expect(status.phase == .completed)
        #expect(status.canDisplayAsComplete)
        #expect(status.proof?.hasAcceptedFinalizeProof == true)
    }

    @Test func runSyncSoonAndSendAudioProofRequestsAreActionsOnly() async {
        let truth = Self.runtime()
        let exchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.macNode,
            truthRuntime: truth,
            nowProvider: { Self.now }
        )
        let runSyncSoon = Self.envelope(
            sequence: 1,
            kind: .request,
            source: Self.iPhoneNode,
            destination: Self.macNode,
            request: CanonicalStatusRequest(requestID: "run-sync-soon", kind: .runSyncSoon)
        )
        let sendAudioProof = Self.envelope(
            sequence: 2,
            kind: .request,
            source: Self.iPhoneNode,
            destination: Self.macNode,
            request: CanonicalStatusRequest(requestID: "send-audio-proof", kind: .sendAudioProof)
        )

        let runSyncResult = await exchange.consumeIncomingEnvelope(runSyncSoon, carrier: .heartbeat)
        let proofResult = await exchange.consumeIncomingEnvelope(sendAudioProof, carrier: .heartbeat)
        let facts = await truth.facts(for: Self.objectID)

        #expect(runSyncResult.requestedActions == [.enqueueRunSyncSoon])
        #expect(proofResult.requestedActions == [.requestLightweightAudioProof])
        #expect(facts.isEmpty)
    }

    @Test func macAdaptersCarryExchangeWithoutChangingRoutesOrSecurityGate() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let server = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/SecureLocalHTTPSServer.swift"),
            encoding: .utf8
        )
        let receiver = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/SecureReceiverService.swift"),
            encoding: .utf8
        )
        let stores = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/ConnectionSyncStateStores.swift"),
            encoding: .utf8
        )

        #expect(server.contains("case (\"POST\", \"/device/status\")"))
        #expect(server.contains("case (\"POST\", \"/connection/heartbeat\")"))
        #expect(server.contains("case (\"POST\", \"/sync/inventory\")"))
        #expect(server.contains("/status-exchange") == false)
        #expect(server.contains("requestVerifier.verify(method: request.method, path: request.path"))
        #expect(server.contains("statusExchangeEnvelope"))
        #expect(server.contains("CanonicalStatusExchangeRuntime"))
        #expect(receiver.contains("CanonicalStatusExchangeRuntime"))
        #expect(stores.contains("recordStatusExchangeRunSyncSoonRequest"))
    }

    private static func runtime() -> CanonicalStatusTruthRuntime {
        CanonicalStatusTruthRuntime(nowProvider: { Self.later })
    }

    private static func envelope(
        sequence: UInt64,
        kind: CanonicalStatusExchangeMessageKind,
        source: CanonicalNodeID,
        destination: CanonicalNodeID?,
        delta: CanonicalStatusDelta? = nil,
        ack: CanonicalStatusAck? = nil,
        request: CanonicalStatusRequest? = nil
    ) -> CanonicalStatusExchangeEnvelope {
        CanonicalStatusExchangeEnvelope(
            envelopeID: "\(source.rawValue)-envelope-\(sequence)",
            kind: kind,
            sourceNodeID: source,
            destinationNodeID: destination,
            sequence: CanonicalSequence(sequence),
            logicalTime: CanonicalLogicalTime(counter: sequence, nodeID: source),
            sentAt: Self.now,
            expiresAt: CanonicalTimestamp(Self.now.date.addingTimeInterval(60)),
            delta: delta,
            ack: ack,
            request: request
        )
    }

    private static func fact(
        _ id: String,
        source: CanonicalStatusSource,
        kind: CanonicalStatusProofKind,
        phase: CanonicalStatusPhase? = nil,
        counter: UInt64 = 1,
        proof: CanonicalStatusProof? = nil
    ) -> CanonicalStatusFact {
        CanonicalStatusFact(
            factID: id,
            objectID: Self.objectID,
            source: source,
            producerNodeID: Self.iPhoneNode,
            logicalTime: CanonicalLogicalTime(counter: counter, nodeID: Self.iPhoneNode),
            proof: proof ?? CanonicalStatusProof(
                kind: kind,
                objectID: Self.objectID,
                peerNodeID: Self.iPhoneNode,
                observedAt: Self.now
            ),
            domain: .audioUpload,
            phase: phase,
            causality: CanonicalStatusCausality(trigger: .statusExchange)
        )
    }

    private static func finalizeProof() -> CanonicalStatusProof {
        CanonicalStatusProof(
            kind: .finalizeProof,
            objectID: Self.objectID,
            peerNodeID: Self.iPhoneNode,
            finalizeProof: CanonicalTransferFinalizeProof.v930(
                receiverNodeID: Self.macNode,
                sessionID: CanonicalTransferSessionID("session-v970-mac"),
                objectID: Self.objectID,
                byteSize: 512,
                contentHash: Self.hashA,
                finalizedAt: Self.now
            ),
            observedAt: Self.now
        )
    }
}
