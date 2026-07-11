//
//  CanonicalStatusExchangeRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalStatusExchangeCarrier: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case heartbeat
    case inventory
}

nonisolated enum CanonicalStatusExchangeRequestedAction: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case enqueueRunSyncSoon
    case requestLightweightAudioProof
    case requestFullInventory
}

nonisolated struct CanonicalStatusExchangeReceiveResult: Codable, Equatable, Hashable, Sendable {
    var accepted: Bool
    var duplicate: Bool
    var stale: Bool
    var incorporatedFactCount: Int
    var rejectedFactCount: Int
    var ackToSend: CanonicalStatusAck?
    var requestedActions: [CanonicalStatusExchangeRequestedAction]
    var reason: String?

    nonisolated init(
        accepted: Bool,
        duplicate: Bool = false,
        stale: Bool = false,
        incorporatedFactCount: Int = 0,
        rejectedFactCount: Int = 0,
        ackToSend: CanonicalStatusAck? = nil,
        requestedActions: [CanonicalStatusExchangeRequestedAction] = [],
        reason: String? = nil
    ) {
        self.accepted = accepted
        self.duplicate = duplicate
        self.stale = stale
        self.incorporatedFactCount = max(0, incorporatedFactCount)
        self.rejectedFactCount = max(0, rejectedFactCount)
        self.ackToSend = ackToSend
        self.requestedActions = Array(Set(requestedActions)).sorted { $0.rawValue < $1.rawValue }
        self.reason = CanonicalKernelStringSanitizer.optional(reason)
    }
}

nonisolated struct CanonicalStatusExchangeDiagnosticRecord: Codable, Equatable, Hashable, Sendable {
    var event: CanonicalKernelDiagnosticEventKind
    var carrier: CanonicalStatusExchangeCarrier?
    var sourceNodeID: CanonicalNodeID?
    var destinationNodeID: CanonicalNodeID?
    var sequence: CanonicalSequence?
    var objectID: CanonicalObjectID?
    var count: Int?
    var redactedDetail: String?

    nonisolated init(
        event: CanonicalKernelDiagnosticEventKind,
        carrier: CanonicalStatusExchangeCarrier? = nil,
        sourceNodeID: CanonicalNodeID? = nil,
        destinationNodeID: CanonicalNodeID? = nil,
        sequence: CanonicalSequence? = nil,
        objectID: CanonicalObjectID? = nil,
        count: Int? = nil,
        detail: String? = nil
    ) {
        let safeDetail = CanonicalStatusTruthRedaction.safeDetail(detail)
        self.event = safeDetail == "redactionRejected" ? .redactionViolationBlocked : event
        self.carrier = carrier
        self.sourceNodeID = sourceNodeID
        self.destinationNodeID = destinationNodeID
        self.sequence = sequence
        self.objectID = objectID
        self.count = count.map { max(0, $0) }
        self.redactedDetail = safeDetail
    }
}

actor CanonicalStatusExchangeRuntime {
    private struct PendingOutgoingEnvelope {
        var envelope: CanonicalStatusExchangeEnvelope
        var factSignatures: [String]
        var ackID: String?
        var requestID: String?
    }

    private let nodeID: CanonicalNodeID
    private let truthRuntime: CanonicalStatusTruthRuntime
    private let nowProvider: @Sendable () -> CanonicalTimestamp
    private let maxEnvelopeAgeSeconds: TimeInterval
    private let maxDiagnosticRecords: Int
    private let maxFactsPerEnvelope: Int
    private let maxFactPayloadBytes: Int
    private var incarnationID: String
    private var nextSequence = CanonicalSequence(1)
    private var lastSequenceBySender: [String: CanonicalSequence] = [:]
    private var seenDeltaIDs: Set<String> = []
    private var sentFactSignatures: Set<String> = []
    private var pendingAcks: [CanonicalStatusAck] = []
    private var pendingRequests: [CanonicalStatusRequest] = []
    private var diagnostics: [CanonicalStatusExchangeDiagnosticRecord] = []
    private var pendingOutgoingEnvelope: PendingOutgoingEnvelope?

    init(
        nodeID: CanonicalNodeID,
        truthRuntime: CanonicalStatusTruthRuntime,
        nowProvider: @escaping @Sendable () -> CanonicalTimestamp = { CanonicalTimestamp(Date()) },
        maxEnvelopeAgeSeconds: TimeInterval = 120,
        maxDiagnosticRecords: Int = 128,
        maxFactsPerEnvelope: Int = 16,
        maxFactPayloadBytes: Int = 6 * 1024
    ) {
        self.nodeID = nodeID
        self.truthRuntime = truthRuntime
        self.nowProvider = nowProvider
        self.maxEnvelopeAgeSeconds = max(1, maxEnvelopeAgeSeconds)
        self.maxDiagnosticRecords = max(1, maxDiagnosticRecords)
        self.maxFactsPerEnvelope = max(1, maxFactsPerEnvelope)
        self.maxFactPayloadBytes = max(512, maxFactPayloadBytes)
        self.incarnationID = UUID().uuidString.lowercased()
    }

    func enqueueRequest(
        kind: CanonicalStatusRequestKind,
        objectIDs: [CanonicalObjectID] = [],
        requestedDomains: [CanonicalDomain] = [.sync]
    ) {
        pendingRequests.append(
            CanonicalStatusRequest(
                requestID: "\(nodeID.rawValue)-\(incarnationID)-request-\(nextSequence.rawValue)-\(pendingRequests.count)-\(kind.rawValue)",
                kind: kind,
                objectIDs: objectIDs,
                requestedDomains: requestedDomains
            )
        )
    }

    func makeOutgoingEnvelope(
        destinationNodeID: CanonicalNodeID? = nil,
        carrier: CanonicalStatusExchangeCarrier
    ) async -> CanonicalStatusExchangeEnvelope? {
        let now = nowProvider()
        if let pending = pendingOutgoingEnvelope {
            if pending.envelope.expiresAt.map({ $0 > now }) ?? true {
                return pending.envelope
            }
            pendingOutgoingEnvelope = nil
        }
        let facts = await truthRuntime.allFactsSnapshot()
        let allUnsentFacts = CanonicalStatusFactStore.deterministicOrder(facts).filter { fact in
            !sentFactSignatures.contains(Self.factSignature(fact))
        }
        let unsentFacts = Self.boundedFacts(
            allUnsentFacts,
            maximumCount: maxFactsPerEnvelope,
            maximumEncodedBytes: maxFactPayloadBytes
        )

        let sequence = nextSequence
        let logicalTime = CanonicalLogicalTime(counter: sequence.rawValue, nodeID: nodeID)
        var delta: CanonicalStatusDelta?
        var ack: CanonicalStatusAck?
        var request: CanonicalStatusRequest?
        var kind: CanonicalStatusExchangeMessageKind?

        if !unsentFacts.isEmpty {
            delta = CanonicalStatusDelta(
                deltaID: "\(nodeID.rawValue)-\(incarnationID)-delta-\(sequence.rawValue)",
                facts: unsentFacts
            )
            kind = .delta
        }
        if !pendingAcks.isEmpty {
            ack = pendingAcks.first
            kind = kind ?? .ack
        }
        if !pendingRequests.isEmpty {
            request = pendingRequests.first
            kind = kind ?? .request
        }

        guard let kind else {
            return nil
        }

        let envelope = CanonicalStatusExchangeEnvelope(
            envelopeID: "\(nodeID.rawValue)-\(incarnationID)-envelope-\(sequence.rawValue)",
            kind: kind,
            sourceNodeID: nodeID,
            sourceIncarnationID: incarnationID,
            destinationNodeID: destinationNodeID,
            sequence: sequence,
            logicalTime: logicalTime,
            sentAt: now,
            expiresAt: CanonicalTimestamp(now.date.addingTimeInterval(maxEnvelopeAgeSeconds)),
            delta: delta,
            ack: ack,
            request: request
        )
        let isPureAck = delta == nil && request == nil && ack != nil
        if isPureAck {
            // A pure ACK is deliberately best-effort: if it is lost, the peer
            // retransmits the original delta/request and we regenerate the ACK.
            // Requiring ACK-of-ACK would create an endless acknowledgement loop.
            if let ackID = ack?.ackID {
                pendingAcks.removeAll { $0.ackID == ackID }
            }
            nextSequence = sequence.next
        } else {
            pendingOutgoingEnvelope = PendingOutgoingEnvelope(
                envelope: envelope,
                factSignatures: unsentFacts.map(Self.factSignature),
                ackID: ack?.ackID,
                requestID: request?.requestID
            )
        }

        if delta != nil {
            appendDiagnostic(
                CanonicalStatusExchangeDiagnosticRecord(
                    event: .statusDeltaSent,
                    carrier: carrier,
                    sourceNodeID: nodeID,
                    destinationNodeID: destinationNodeID,
                    sequence: sequence,
                    count: delta?.facts.count,
                    detail: "delta"
                )
            )
        }
        if ack != nil {
            appendDiagnostic(
                CanonicalStatusExchangeDiagnosticRecord(
                    event: .statusAckSent,
                    carrier: carrier,
                    sourceNodeID: nodeID,
                    destinationNodeID: destinationNodeID,
                    sequence: sequence,
                    detail: ack?.disposition.rawValue
                )
            )
        }
        if request != nil {
            appendDiagnostic(
                CanonicalStatusExchangeDiagnosticRecord(
                    event: .statusRequestSent,
                    carrier: carrier,
                    sourceNodeID: nodeID,
                    destinationNodeID: destinationNodeID,
                    sequence: sequence,
                    detail: request?.kind.rawValue
                )
            )
        }
        appendDiagnostic(
            CanonicalStatusExchangeDiagnosticRecord(
                event: carrier == .heartbeat ? .statusEnvelopeCarriedOverHeartbeat : .statusEnvelopeCarriedOverInventory,
                carrier: carrier,
                sourceNodeID: nodeID,
                destinationNodeID: destinationNodeID,
                sequence: sequence,
                count: unsentFacts.count
            )
        )
        return envelope
    }

    func consumeIncomingEnvelope(
        _ envelope: CanonicalStatusExchangeEnvelope?,
        carrier: CanonicalStatusExchangeCarrier
    ) async -> CanonicalStatusExchangeReceiveResult {
        guard let envelope else {
            return CanonicalStatusExchangeReceiveResult(accepted: true, reason: "missingOptionalEnvelope")
        }

        let now = nowProvider()
        guard envelope.destinationNodeID == nil || envelope.destinationNodeID == nodeID else {
            return reject(envelope, reason: "wrongDestination", carrier: carrier)
        }
        if let expiresAt = envelope.expiresAt, expiresAt <= now {
            return reject(envelope, reason: "expiredEnvelope", carrier: carrier)
        }
        if now.date.timeIntervalSince(envelope.sentAt.date) > maxEnvelopeAgeSeconds {
            return reject(envelope, reason: "staleEnvelope", carrier: carrier)
        }
        let senderSequenceKey = Self.senderSequenceKey(envelope)
        if let last = lastSequenceBySender[senderSequenceKey] {
            if envelope.sequence < last {
                return reject(envelope, reason: "olderSequence", carrier: carrier)
            }
            if envelope.sequence == last,
               let delta = envelope.delta,
               seenDeltaIDs.contains(delta.deltaID) {
                let ack = makeAck(for: envelope, disposition: .observed, stale: false, reason: "duplicate")
                pendingAcks.append(ack)
                return CanonicalStatusExchangeReceiveResult(
                    accepted: true,
                    duplicate: true,
                    ackToSend: ack,
                    reason: "duplicate"
                )
            }
            if envelope.sequence == last {
                return reject(envelope, reason: "nonMonotonicSequence", carrier: carrier)
            }
        }
        lastSequenceBySender[senderSequenceKey] = envelope.sequence

        var incorporatedCount = 0
        var rejectedCount = 0
        var actions: [CanonicalStatusExchangeRequestedAction] = []
        var disposition: CanonicalStatusAckDisposition = .observed
        var reason: String?

        if let delta = envelope.delta {
            if seenDeltaIDs.contains(delta.deltaID) {
                disposition = .observed
                reason = "duplicateDelta"
            } else {
                seenDeltaIDs.insert(delta.deltaID)
                let mergeResults = await truthRuntime.produce(delta.facts)
                incorporatedCount = mergeResults.filter {
                    $0.decision == .merged || $0.decision == .replaced
                }.count
                rejectedCount = mergeResults.count - incorporatedCount
                disposition = rejectedCount == 0 ? .incorporated : .rejected
                reason = rejectedCount == 0 ? "incorporated" : "rejectedFact"
                appendDiagnostic(
                    CanonicalStatusExchangeDiagnosticRecord(
                        event: .statusDeltaReceived,
                        carrier: carrier,
                        sourceNodeID: envelope.sourceNodeID,
                        destinationNodeID: envelope.destinationNodeID,
                        sequence: envelope.sequence,
                        count: delta.facts.count,
                        detail: reason
                    )
                )
                if rejectedCount > 0 {
                    appendDiagnostic(
                        CanonicalStatusExchangeDiagnosticRecord(
                            event: .statusFactRejected,
                            carrier: carrier,
                            sourceNodeID: envelope.sourceNodeID,
                            sequence: envelope.sequence,
                            count: rejectedCount,
                            detail: "statusFactRejected"
                        )
                    )
                }
            }
        }

        if let incomingAck = envelope.ack {
            acknowledgePendingOutgoingEnvelope(with: incomingAck)
            appendDiagnostic(
                CanonicalStatusExchangeDiagnosticRecord(
                    event: .statusAckReceived,
                    carrier: carrier,
                    sourceNodeID: envelope.sourceNodeID,
                    sequence: envelope.sequence,
                    detail: incomingAck.disposition.rawValue
                )
            )
        }

        if let incomingRequest = envelope.request {
            appendDiagnostic(
                CanonicalStatusExchangeDiagnosticRecord(
                    event: .statusRequestReceived,
                    carrier: carrier,
                    sourceNodeID: envelope.sourceNodeID,
                    sequence: envelope.sequence,
                    detail: incomingRequest.kind.rawValue
                )
            )
            switch incomingRequest.kind {
            case .sendFacts:
                break
            case .fullInventory:
                actions.append(.requestFullInventory)
                appendDiagnostic(
                    CanonicalStatusExchangeDiagnosticRecord(
                        event: .fullInventoryRequested,
                        carrier: carrier,
                        sourceNodeID: envelope.sourceNodeID,
                        sequence: envelope.sequence,
                        detail: "requestOnly"
                    )
                )
            case .runSyncSoon:
                actions.append(.enqueueRunSyncSoon)
            case .sendAudioProof:
                actions.append(.requestLightweightAudioProof)
                appendDiagnostic(
                    CanonicalStatusExchangeDiagnosticRecord(
                        event: .peerProofUnavailable,
                        carrier: carrier,
                        sourceNodeID: envelope.sourceNodeID,
                        sequence: envelope.sequence,
                        detail: "lightweightProofRequested"
                    )
                )
            }
        }

        if envelope.delta == nil, envelope.request == nil, envelope.ack != nil {
            return CanonicalStatusExchangeReceiveResult(
                accepted: true,
                incorporatedFactCount: incorporatedCount,
                rejectedFactCount: rejectedCount,
                requestedActions: actions,
                reason: "ackObserved"
            )
        }

        let ack = makeAck(for: envelope, disposition: disposition, stale: false, reason: reason)
        pendingAcks.append(ack)
        return CanonicalStatusExchangeReceiveResult(
            accepted: disposition != .rejected,
            incorporatedFactCount: incorporatedCount,
            rejectedFactCount: rejectedCount,
            ackToSend: ack,
            requestedActions: actions,
            reason: reason
        )
    }

    func diagnosticRecords() -> [CanonicalStatusExchangeDiagnosticRecord] {
        diagnostics
    }

    func reset() {
        incarnationID = UUID().uuidString.lowercased()
        nextSequence = CanonicalSequence(1)
        lastSequenceBySender.removeAll()
        seenDeltaIDs.removeAll()
        sentFactSignatures.removeAll()
        pendingAcks.removeAll()
        pendingRequests.removeAll()
        pendingOutgoingEnvelope = nil
        diagnostics.removeAll()
    }

    /// A transport failure does not consume facts, ACKs, requests, or sequence.
    /// Clearing only the cached wire image lets the next carrier rebuild it with
    /// a fresh expiry while preserving delivery semantics.
    func markOutgoingEnvelopeTransportFailed(envelopeID: String) {
        guard pendingOutgoingEnvelope?.envelope.envelopeID == envelopeID else {
            return
        }
        pendingOutgoingEnvelope = nil
    }

    private func reject(
        _ envelope: CanonicalStatusExchangeEnvelope,
        reason: String,
        carrier: CanonicalStatusExchangeCarrier
    ) -> CanonicalStatusExchangeReceiveResult {
        let ack = makeAck(for: envelope, disposition: .rejected, stale: true, reason: reason)
        pendingAcks.append(ack)
        appendDiagnostic(
            CanonicalStatusExchangeDiagnosticRecord(
                event: .statusFactRejected,
                carrier: carrier,
                sourceNodeID: envelope.sourceNodeID,
                destinationNodeID: envelope.destinationNodeID,
                sequence: envelope.sequence,
                detail: reason
            )
        )
        return CanonicalStatusExchangeReceiveResult(
            accepted: false,
            stale: true,
            ackToSend: ack,
            reason: reason
        )
    }

    private func makeAck(
        for envelope: CanonicalStatusExchangeEnvelope,
        disposition: CanonicalStatusAckDisposition,
        stale: Bool,
        reason: String?
    ) -> CanonicalStatusAck {
        CanonicalStatusAck(
            ackID: "\(nodeID.rawValue)-ack-\(envelope.sequence.rawValue)",
            acknowledgedSequence: envelope.sequence,
            disposition: disposition,
            accepted: disposition != .rejected,
            stale: stale,
            reason: reason
        )
    }

    private func appendDiagnostic(_ record: CanonicalStatusExchangeDiagnosticRecord) {
        diagnostics.append(record)
        if diagnostics.count > maxDiagnosticRecords {
            diagnostics.removeFirst(diagnostics.count - maxDiagnosticRecords)
        }
    }

    private func acknowledgePendingOutgoingEnvelope(with ack: CanonicalStatusAck) {
        guard let pending = pendingOutgoingEnvelope,
              pending.envelope.sequence == ack.acknowledgedSequence else {
            return
        }

        if ack.accepted && ack.disposition != .rejected {
            sentFactSignatures.formUnion(pending.factSignatures)
            if let ackID = pending.ackID {
                pendingAcks.removeAll { $0.ackID == ackID }
            }
            if let requestID = pending.requestID {
                pendingRequests.removeAll { $0.requestID == requestID }
            }
        }
        // A rejected envelope must use a new sequence when retried because the
        // receiver has already consumed the previous sequence. Its facts remain
        // unsent so they are eligible for the next bounded envelope.
        nextSequence = pending.envelope.sequence.next
        pendingOutgoingEnvelope = nil
    }

    private nonisolated static func senderSequenceKey(_ envelope: CanonicalStatusExchangeEnvelope) -> String {
        "\(envelope.sourceNodeID.rawValue)#\(envelope.sourceIncarnationID ?? "legacy")"
    }

    private nonisolated static func boundedFacts(
        _ facts: [CanonicalStatusFact],
        maximumCount: Int,
        maximumEncodedBytes: Int
    ) -> [CanonicalStatusFact] {
        var result: [CanonicalStatusFact] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for fact in facts.prefix(maximumCount) {
            let candidate = result + [fact]
            let encodedSize = (try? encoder.encode(candidate).count) ?? Int.max
            guard encodedSize <= maximumEncodedBytes else {
                break
            }
            result = candidate
        }
        return result
    }

    private nonisolated static func factSignature(_ fact: CanonicalStatusFact) -> String {
        [
            fact.factID.rawValue,
            fact.objectID.rawValue,
            fact.domain.rawValue,
            fact.phase.rawValue,
            fact.source.rawValue,
            fact.producerNodeID.rawValue,
            "\(fact.logicalTime.counter)",
            fact.logicalTime.nodeID.rawValue,
            fact.proof.kind.rawValue,
            fact.proof.hash?.value ?? "hash=none",
            fact.proof.byteSize.map(String.init) ?? "bytes=none",
            fact.proof.finalizeProof?.sessionID.rawValue ?? "session=none"
        ].joined(separator: "|")
    }
}
