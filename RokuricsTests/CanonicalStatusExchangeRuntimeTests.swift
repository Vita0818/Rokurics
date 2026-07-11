//
//  CanonicalStatusExchangeRuntimeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalStatusExchangeRuntimeTests {
    private static let now = CanonicalTimestamp(Date(timeIntervalSince1970: 9_700))
    private static let later = CanonicalTimestamp(Date(timeIntervalSince1970: 9_701))
    private static let objectID = CanonicalObjectID("recording-v970-iphone")
    private static let iPhoneNode = CanonicalNodeID("iphone-v970")
    private static let macNode = CanonicalNodeID("mac-v970")
    private static let hashA = CanonicalHash(String(repeating: "a", count: 64))

    @Test func optionalStatusExchangeEnvelopeDecodesOldPeerPayloads() throws {
        let decoder = JSONDecoder()
        let deviceStatus = try decoder.decode(
            DeviceStatusResponse.self,
            from: Data(#"{"ok":true,"status":null,"syncState":null,"syncRequested":false,"error":null}"#.utf8)
        )
        let heartbeat = try decoder.decode(
            ConnectionHeartbeatResponse.self,
            from: Data(#"{"ok":true,"disposition":"accepted","peerDeviceID":"mac-v970","serverTime":0,"receivedSequenceNumber":7,"connectionStatusRevision":1,"minimumSuggestedInterval":null,"syncRequested":false,"status":null,"error":null}"#.utf8)
        )
        let inventory = try decoder.decode(
            LocalNetworkSyncInventoryResponse.self,
            from: Data(#"{"ok":true,"inventory":null,"error":null}"#.utf8)
        )

        #expect(deviceStatus.statusExchangeEnvelope == nil)
        #expect(heartbeat.statusExchangeEnvelope == nil)
        #expect(inventory.statusExchangeEnvelope == nil)
    }

    @Test func inventoryCarrierSendsUploadNeededDeltaAndPeerRuntimeMergesIt() async throws {
        let iPhoneTruth = Self.runtime()
        let macTruth = Self.runtime()
        let iPhoneExchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.iPhoneNode,
            truthRuntime: iPhoneTruth,
            nowProvider: { Self.now }
        )
        let macExchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.macNode,
            truthRuntime: macTruth,
            nowProvider: { Self.now }
        )
        let uploadNeeded = Self.fact(
            "iphone-upload-needed",
            source: .syncRuntime,
            kind: .localFileExists,
            phase: .uploadNeeded,
            counter: 2,
            hash: Self.hashA,
            byteSize: 100
        )

        _ = await iPhoneTruth.produce(uploadNeeded)
        let envelope = try #require(await iPhoneExchange.makeOutgoingEnvelope(destinationNodeID: Self.macNode, carrier: .inventory))
        let result = await macExchange.consumeIncomingEnvelope(envelope, carrier: .inventory)
        let merged = await macTruth.facts(for: Self.objectID)

        #expect(envelope.delta?.facts.contains { $0.phase == .uploadNeeded } == true)
        #expect(result.accepted)
        #expect(result.incorporatedFactCount == 1)
        #expect(merged.contains { $0.factID == uploadNeeded.factID && $0.phase == .uploadNeeded })
    }

    @Test func runSyncSoonRequestOnlyReturnsQueuedAction() async {
        let truth = Self.runtime()
        let exchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.iPhoneNode,
            truthRuntime: truth,
            nowProvider: { Self.now }
        )
        let envelope = Self.envelope(
            sequence: 1,
            kind: .request,
            source: Self.macNode,
            destination: Self.iPhoneNode,
            request: CanonicalStatusRequest(requestID: "run-sync-soon", kind: .runSyncSoon)
        )

        let result = await exchange.consumeIncomingEnvelope(envelope, carrier: .heartbeat)
        let facts = await truth.facts(for: Self.objectID)

        #expect(result.accepted)
        #expect(result.requestedActions == [.enqueueRunSyncSoon])
        #expect(facts.isEmpty)
    }

    @Test func duplicateAndStaleEnvelopePolicyIsDeterministic() async {
        let truth = Self.runtime()
        let exchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.iPhoneNode,
            truthRuntime: truth,
            nowProvider: { Self.now }
        )
        let delta = CanonicalStatusDelta(deltaID: "delta-1", facts: [Self.fact("metadata-only", source: .peerMetadata, kind: .metadataOnly)])
        let firstEnvelope = Self.envelope(
            sequence: 1,
            kind: .delta,
            source: Self.macNode,
            destination: Self.iPhoneNode,
            delta: delta
        )
        let olderEnvelope = Self.envelope(
            sequence: 0,
            kind: .ack,
            source: Self.macNode,
            destination: Self.iPhoneNode,
            ack: CanonicalStatusAck(ackID: "older-ack", acknowledgedSequence: CanonicalSequence(0), accepted: true)
        )

        let first = await exchange.consumeIncomingEnvelope(firstEnvelope, carrier: .heartbeat)
        let duplicate = await exchange.consumeIncomingEnvelope(firstEnvelope, carrier: .heartbeat)
        let stale = await exchange.consumeIncomingEnvelope(olderEnvelope, carrier: .heartbeat)

        #expect(first.accepted)
        #expect(duplicate.accepted)
        #expect(duplicate.duplicate)
        #expect(stale.accepted == false)
        #expect(stale.stale)
        #expect(stale.reason == "olderSequence")
    }

    @Test func ackAloneDoesNotCreatePeerAudioProof() async {
        let truth = Self.runtime()
        let exchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.iPhoneNode,
            truthRuntime: truth,
            nowProvider: { Self.now }
        )
        let ackOnly = Self.envelope(
            sequence: 1,
            kind: .ack,
            source: Self.macNode,
            destination: Self.iPhoneNode,
            ack: CanonicalStatusAck(ackID: "ack-only", acknowledgedSequence: CanonicalSequence(1), accepted: true)
        )

        let result = await exchange.consumeIncomingEnvelope(ackOnly, carrier: .heartbeat)
        let facts = await truth.facts(for: Self.objectID)

        #expect(result.accepted)
        #expect(result.incorporatedFactCount == 0)
        #expect(facts.isEmpty)
    }

    @Test func statusExchangeDiagnosticsBlockUnsafeDetail() {
        let fullHash = String(repeating: "f", count: 64)
        let record = CanonicalStatusExchangeDiagnosticRecord(
            event: .statusDeltaSent,
            detail: "path=/Users/vita/private/audio.m4a hash=\(fullHash) request body raw audio"
        )

        #expect(record.event == .redactionViolationBlocked)
        #expect(record.redactedDetail == "redactionRejected")
    }

    @Test func outgoingEnvelopeIsRetriedUntilExplicitPeerAck() async throws {
        let truth = Self.runtime()
        let exchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.iPhoneNode,
            truthRuntime: truth,
            nowProvider: { Self.now }
        )
        _ = await truth.produce(Self.fact("retry-fact", source: .syncRuntime, kind: .localFileExists))

        let first = try #require(await exchange.makeOutgoingEnvelope(destinationNodeID: Self.macNode, carrier: .heartbeat))
        let retry = try #require(await exchange.makeOutgoingEnvelope(destinationNodeID: Self.macNode, carrier: .inventory))

        #expect(retry.envelopeID == first.envelopeID)
        #expect(retry.delta?.facts.map(\.factID) == first.delta?.facts.map(\.factID))

        let ackEnvelope = Self.envelope(
            sequence: 1,
            kind: .ack,
            source: Self.macNode,
            destination: Self.iPhoneNode,
            ack: CanonicalStatusAck(
                ackID: "peer-ack",
                acknowledgedSequence: first.sequence,
                accepted: true
            )
        )
        _ = await exchange.consumeIncomingEnvelope(ackEnvelope, carrier: .heartbeat)
        #expect(await exchange.makeOutgoingEnvelope(destinationNodeID: Self.macNode, carrier: .heartbeat)?.delta == nil)
    }

    @Test func statusFactsAreBatchedAndRestartIncarnationResetsPeerSequenceScope() async throws {
        let truth = Self.runtime()
        let exchange = CanonicalStatusExchangeRuntime(
            nodeID: Self.iPhoneNode,
            truthRuntime: truth,
            nowProvider: { Self.now },
            maxFactsPerEnvelope: 1
        )
        _ = await truth.produce(Self.fact("batch-a", source: .syncRuntime, kind: .localFileExists, counter: 1))
        _ = await truth.produce(Self.fact("batch-b", source: .peerMetadata, kind: .metadataOnly, counter: 2))
        let firstBatch = try #require(await exchange.makeOutgoingEnvelope(destinationNodeID: Self.macNode, carrier: .heartbeat))
        #expect(firstBatch.delta?.facts.count == 1)

        let receiver = CanonicalStatusExchangeRuntime(
            nodeID: Self.macNode,
            truthRuntime: Self.runtime(),
            nowProvider: { Self.now }
        )
        let senderBeforeRestart = CanonicalStatusExchangeRuntime(
            nodeID: Self.iPhoneNode,
            truthRuntime: Self.runtime(),
            nowProvider: { Self.now }
        )
        let senderAfterRestart = CanonicalStatusExchangeRuntime(
            nodeID: Self.iPhoneNode,
            truthRuntime: Self.runtime(),
            nowProvider: { Self.now }
        )
        await senderBeforeRestart.enqueueRequest(kind: .runSyncSoon)
        await senderAfterRestart.enqueueRequest(kind: .runSyncSoon)
        let before = try #require(await senderBeforeRestart.makeOutgoingEnvelope(destinationNodeID: Self.macNode, carrier: .heartbeat))
        let after = try #require(await senderAfterRestart.makeOutgoingEnvelope(destinationNodeID: Self.macNode, carrier: .heartbeat))

        #expect(before.sequence == after.sequence)
        #expect(before.sourceIncarnationID != after.sourceIncarnationID)
        #expect((await receiver.consumeIncomingEnvelope(before, carrier: .heartbeat)).accepted)
        #expect((await receiver.consumeIncomingEnvelope(after, carrier: .heartbeat)).accepted)
    }

    @Test func pureAckTerminatesWithoutAckOfAckLoop() async throws {
        let senderTruth = CanonicalStatusTruthRuntime()
        let receiverTruth = CanonicalStatusTruthRuntime()
        let sender = CanonicalStatusExchangeRuntime(
            nodeID: Self.iPhoneNode,
            truthRuntime: senderTruth,
            nowProvider: { Self.now }
        )
        let receiver = CanonicalStatusExchangeRuntime(
            nodeID: Self.macNode,
            truthRuntime: receiverTruth,
            nowProvider: { Self.now }
        )
        await sender.enqueueRequest(kind: .runSyncSoon)
        let dataEnvelope = try #require(await sender.makeOutgoingEnvelope(
            destinationNodeID: Self.macNode,
            carrier: .heartbeat
        ))
        _ = await receiver.consumeIncomingEnvelope(dataEnvelope, carrier: .heartbeat)
        let pureAck = try #require(await receiver.makeOutgoingEnvelope(
            destinationNodeID: Self.iPhoneNode,
            carrier: .heartbeat
        ))

        let result = await sender.consumeIncomingEnvelope(pureAck, carrier: .heartbeat)

        #expect(result.accepted)
        #expect(result.ackToSend == nil)
        #expect(await sender.makeOutgoingEnvelope(destinationNodeID: Self.macNode, carrier: .heartbeat) == nil)
        #expect(await receiver.makeOutgoingEnvelope(destinationNodeID: Self.iPhoneNode, carrier: .heartbeat) == nil)
    }

    @Test func iPhoneAdaptersCarryExchangeOverExistingStatusAndInventoryPaths() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let coordinator = try String(
            contentsOf: root.appendingPathComponent("Rokurics/StudyLibrarySyncCoordinator.swift"),
            encoding: .utf8
        )
        let client = try String(
            contentsOf: root.appendingPathComponent("Rokurics/SecureMacUploadClient.swift"),
            encoding: .utf8
        )

        #expect(coordinator.contains("CanonicalStatusExchangeRuntime"))
        #expect(coordinator.contains("statusEnvelopeCarriedOverHeartbeat"))
        #expect(coordinator.contains("statusEnvelopeCarriedOverInventory"))
        #expect(coordinator.contains("statusExchangeEnvelope"))
        #expect(client.contains("statusExchangeEnvelope: CanonicalStatusExchangeEnvelope?"))
        #expect(client.contains("LocalNetworkSyncInventoryRequest("))
        #expect(client.contains("\"/sync/inventory\""))
    }

    @Test func canonicalConnectionRuntimeOwnsLivenessAndOnlyReturnsQueuedActions() async throws {
        let runtime = CanonicalConnectionRuntime(
            configuration: CanonicalConnectionRuntimeConfiguration(
                mode: .connectionOwnerWithLegacyFallback,
                policy: CanonicalConnectionRuntimePolicy(
                    debugInternalBuild: true,
                    ownerApprovedCanonicalConnection: true,
                    defaultReleaseOldKernel: false
                )
            ),
            localNode: CanonicalNodeIdentity(nodeID: Self.iPhoneNode, role: .iPhone, displayName: "iPhone")
        )
        let peer = CanonicalNodeIdentity(nodeID: Self.macNode, role: .mac, displayName: "Mac")
        let envelope = try #require(await runtime.makeHeartbeatEnvelope(destinationNodeID: peer.nodeID, syncRequested: true))
        _ = await runtime.recordHeartbeatAcknowledged(
            peer: peer,
            acknowledgedSequence: envelope.sequence,
            syncRequested: true,
            observedAt: Self.now.date
        )
        let snapshot = await runtime.snapshot(now: Self.now.date)
        let actions = runtime.enqueuedActions(syncRequested: true, requestedStatusActions: [.enqueueRunSyncSoon])

        #expect(envelope.payload.syncRequested)
        #expect(snapshot.peers.first?.state == .alive)
        #expect(snapshot.peers.first?.syncRequested == true)
        #expect(snapshot.heartbeatCallbackEnqueueOnly)
        #expect(snapshot.macReverseConnectionAllowed == false)
        #expect(actions == [.enqueueRunSyncSoon])
        #expect(CanonicalConnectionContract.createsUploadJobs == false)
    }

    @Test func iPhoneConnectionOwnerUsesExistingHeartbeatCarrier() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let coordinator = try String(
            contentsOf: root.appendingPathComponent("Rokurics/StudyLibrarySyncCoordinator.swift"),
            encoding: .utf8
        )
        let client = try String(
            contentsOf: root.appendingPathComponent("Rokurics/SecureMacUploadClient.swift"),
            encoding: .utf8
        )

        #expect(coordinator.contains("CanonicalConnectionRuntime"))
        #expect(coordinator.contains("makeHeartbeatEnvelope"))
        #expect(coordinator.contains("recordHeartbeatAcknowledged"))
        #expect(coordinator.contains("recordHeartbeatFailed"))
        #expect(coordinator.contains("onSyncRequested?(nil)"))
        #expect(client.contains("sendConnectionHeartbeat"))
        #expect(client.contains("\"/connection/heartbeat\""))
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
        hash: CanonicalHash? = nil,
        byteSize: Int64? = nil
    ) -> CanonicalStatusFact {
        CanonicalStatusFact(
            factID: id,
            objectID: Self.objectID,
            source: source,
            producerNodeID: Self.iPhoneNode,
            logicalTime: CanonicalLogicalTime(counter: counter, nodeID: Self.iPhoneNode),
            proof: CanonicalStatusProof(
                kind: kind,
                objectID: Self.objectID,
                hash: hash,
                byteSize: byteSize,
                peerNodeID: Self.macNode,
                observedAt: Self.now
            ),
            domain: .audioUpload,
            phase: phase,
            causality: CanonicalStatusCausality(trigger: .statusExchange)
        )
    }
}
