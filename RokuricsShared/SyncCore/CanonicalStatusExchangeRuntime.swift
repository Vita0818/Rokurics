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
    private let nodeID: CanonicalNodeID
    private let truthRuntime: CanonicalStatusTruthRuntime
    private let nowProvider: @Sendable () -> CanonicalTimestamp
    private let maxEnvelopeAgeSeconds: TimeInterval
    private let maxDiagnosticRecords: Int
    private var nextSequence = CanonicalSequence(1)
    private var lastSequenceBySender: [CanonicalNodeID: CanonicalSequence] = [:]
    private var seenDeltaIDs: Set<String> = []
    private var sentFactSignatures: Set<String> = []
    private var pendingAcks: [CanonicalStatusAck] = []
    private var pendingRequests: [CanonicalStatusRequest] = []
    private var diagnostics: [CanonicalStatusExchangeDiagnosticRecord] = []

    init(
        nodeID: CanonicalNodeID,
        truthRuntime: CanonicalStatusTruthRuntime,
        nowProvider: @escaping @Sendable () -> CanonicalTimestamp = { CanonicalTimestamp(Date()) },
        maxEnvelopeAgeSeconds: TimeInterval = 120,
        maxDiagnosticRecords: Int = 128
    ) {
        self.nodeID = nodeID
        self.truthRuntime = truthRuntime
        self.nowProvider = nowProvider
        self.maxEnvelopeAgeSeconds = max(1, maxEnvelopeAgeSeconds)
        self.maxDiagnosticRecords = max(1, maxDiagnosticRecords)
    }

    func enqueueRequest(
        kind: CanonicalStatusRequestKind,
        objectIDs: [CanonicalObjectID] = [],
        requestedDomains: [CanonicalDomain] = [.sync]
    ) {
        pendingRequests.append(
            CanonicalStatusRequest(
                requestID: "\(nodeID.rawValue)-request-\(nextSequence.rawValue)-\(kind.rawValue)",
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
        let facts = await truthRuntime.allFactsSnapshot()
        let unsentFacts = CanonicalStatusFactStore.deterministicOrder(facts).filter { fact in
            !sentFactSignatures.contains(Self.factSignature(fact))
        }

        let sequence = nextSequence
        let logicalTime = CanonicalLogicalTime(counter: sequence.rawValue, nodeID: nodeID)
        var delta: CanonicalStatusDelta?
        var ack: CanonicalStatusAck?
        var request: CanonicalStatusRequest?
        var kind: CanonicalStatusExchangeMessageKind?

        if !unsentFacts.isEmpty {
            delta = CanonicalStatusDelta(
                deltaID: "\(nodeID.rawValue)-delta-\(sequence.rawValue)",
                facts: unsentFacts
            )
            kind = .delta
        }
        if !pendingAcks.isEmpty {
            ack = pendingAcks.removeFirst()
            kind = kind ?? .ack
        }
        if !pendingRequests.isEmpty {
            request = pendingRequests.removeFirst()
            kind = kind ?? .request
        }

        guard let kind else {
            return nil
        }

        nextSequence = sequence.next
        for fact in unsentFacts {
            sentFactSignatures.insert(Self.factSignature(fact))
        }

        let envelope = CanonicalStatusExchangeEnvelope(
            envelopeID: "\(nodeID.rawValue)-envelope-\(sequence.rawValue)",
            kind: kind,
            sourceNodeID: nodeID,
            destinationNodeID: destinationNodeID,
            sequence: sequence,
            logicalTime: logicalTime,
            sentAt: now,
            expiresAt: CanonicalTimestamp(now.date.addingTimeInterval(maxEnvelopeAgeSeconds)),
            delta: delta,
            ack: ack,
            request: request
        )

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
        if let last = lastSequenceBySender[envelope.sourceNodeID] {
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
        lastSequenceBySender[envelope.sourceNodeID] = envelope.sequence

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
        nextSequence = CanonicalSequence(1)
        lastSequenceBySender.removeAll()
        seenDeltaIDs.removeAll()
        sentFactSignatures.removeAll()
        pendingAcks.removeAll()
        pendingRequests.removeAll()
        diagnostics.removeAll()
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
