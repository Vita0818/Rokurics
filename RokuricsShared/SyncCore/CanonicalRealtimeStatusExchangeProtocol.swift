//
//  CanonicalRealtimeStatusExchangeProtocol.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalStatusExchangeMessageKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case delta
    case ack
    case request
}

nonisolated enum CanonicalStatusAckDisposition: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case observed
    case incorporated
    case rejected
}

nonisolated enum CanonicalStatusRequestKind: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case sendFacts
    case fullInventory
    case runSyncSoon
    case sendAudioProof
}

nonisolated enum CanonicalStatusStalenessPolicy: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case rejectOlderSequence
    case rejectOlderLogicalTime
    case acceptIdempotentDuplicate
    case deferPeerUnknown
}

nonisolated enum CanonicalStatusExpirationPolicy: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case expireAtTimestamp
    case expireOnNewerSequence
    case retainUntilFinalizeProof
}

nonisolated enum CanonicalStatusConflictPolicy: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case lastWriterWinsByLogicalTime
    case conflictNoOverwrite
    case requirePeerProof
    case deferDecision
}

nonisolated struct CanonicalStatusDelta: Codable, Equatable, Hashable, Sendable {
    var deltaID: String
    var facts: [CanonicalStatusFact]
    var conflictPolicy: CanonicalStatusConflictPolicy

    nonisolated init(
        deltaID: String,
        facts: [CanonicalStatusFact],
        conflictPolicy: CanonicalStatusConflictPolicy = .requirePeerProof
    ) {
        self.deltaID = CanonicalKernelStringSanitizer.required(deltaID, fallback: "status-delta")
        self.facts = facts
        self.conflictPolicy = conflictPolicy
    }
}

nonisolated struct CanonicalStatusAck: Codable, Equatable, Hashable, Sendable {
    var ackID: String
    var acknowledgedSequence: CanonicalSequence
    var disposition: CanonicalStatusAckDisposition
    var accepted: Bool
    var stale: Bool
    var reason: String?

    nonisolated init(
        ackID: String,
        acknowledgedSequence: CanonicalSequence,
        disposition: CanonicalStatusAckDisposition? = nil,
        accepted: Bool,
        stale: Bool = false,
        reason: String? = nil
    ) {
        self.ackID = CanonicalKernelStringSanitizer.required(ackID, fallback: "status-ack")
        self.acknowledgedSequence = acknowledgedSequence
        self.disposition = disposition ?? (accepted ? .incorporated : .rejected)
        self.accepted = accepted
        self.stale = stale
        self.reason = CanonicalKernelStringSanitizer.optional(reason)
    }

    private enum CodingKeys: String, CodingKey {
        case ackID
        case acknowledgedSequence
        case disposition
        case accepted
        case stale
        case reason
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ackID = CanonicalKernelStringSanitizer.required(
            try container.decodeIfPresent(String.self, forKey: .ackID) ?? "status-ack",
            fallback: "status-ack"
        )
        acknowledgedSequence = try container.decodeIfPresent(CanonicalSequence.self, forKey: .acknowledgedSequence)
            ?? CanonicalSequence()
        accepted = try container.decodeIfPresent(Bool.self, forKey: .accepted) ?? false
        stale = try container.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        disposition = try container.decodeIfPresent(CanonicalStatusAckDisposition.self, forKey: .disposition)
            ?? (accepted ? .incorporated : .rejected)
        reason = CanonicalKernelStringSanitizer.optional(try container.decodeIfPresent(String.self, forKey: .reason))
    }
}

nonisolated struct CanonicalStatusRequest: Codable, Equatable, Hashable, Sendable {
    var requestID: String
    var kind: CanonicalStatusRequestKind
    var objectIDs: [CanonicalObjectID]
    var requestedDomains: [CanonicalDomain]
    var sinceSequence: CanonicalSequence?

    nonisolated init(
        requestID: String,
        kind: CanonicalStatusRequestKind = .sendFacts,
        objectIDs: [CanonicalObjectID] = [],
        requestedDomains: [CanonicalDomain] = [.sync],
        sinceSequence: CanonicalSequence? = nil
    ) {
        self.requestID = CanonicalKernelStringSanitizer.required(requestID, fallback: "status-request")
        self.kind = kind
        self.objectIDs = Array(Set(objectIDs)).sorted()
        self.requestedDomains = Array(Set(requestedDomains)).sorted { $0.rawValue < $1.rawValue }
        self.sinceSequence = sinceSequence
    }

    private enum CodingKeys: String, CodingKey {
        case requestID
        case kind
        case objectIDs
        case requestedDomains
        case sinceSequence
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = CanonicalKernelStringSanitizer.required(
            try container.decodeIfPresent(String.self, forKey: .requestID) ?? "status-request",
            fallback: "status-request"
        )
        kind = try container.decodeIfPresent(CanonicalStatusRequestKind.self, forKey: .kind) ?? .sendFacts
        objectIDs = Array(Set(try container.decodeIfPresent([CanonicalObjectID].self, forKey: .objectIDs) ?? [])).sorted()
        requestedDomains = Array(Set(try container.decodeIfPresent([CanonicalDomain].self, forKey: .requestedDomains) ?? [.sync]))
            .sorted { $0.rawValue < $1.rawValue }
        sinceSequence = try container.decodeIfPresent(CanonicalSequence.self, forKey: .sinceSequence)
    }
}

nonisolated struct CanonicalStatusExchangeEnvelope: Codable, Equatable, Hashable, Sendable {
    var envelopeID: String
    var protocolVersion: CanonicalProtocolVersion
    var kind: CanonicalStatusExchangeMessageKind
    var sourceNodeID: CanonicalNodeID
    var destinationNodeID: CanonicalNodeID?
    var sequence: CanonicalSequence
    var logicalTime: CanonicalLogicalTime
    var sentAt: CanonicalTimestamp
    var expiresAt: CanonicalTimestamp?
    var stalenessPolicy: CanonicalStatusStalenessPolicy
    var expirationPolicy: CanonicalStatusExpirationPolicy
    var delta: CanonicalStatusDelta?
    var ack: CanonicalStatusAck?
    var request: CanonicalStatusRequest?

    nonisolated init(
        envelopeID: String,
        kind: CanonicalStatusExchangeMessageKind,
        sourceNodeID: CanonicalNodeID,
        destinationNodeID: CanonicalNodeID? = nil,
        sequence: CanonicalSequence,
        logicalTime: CanonicalLogicalTime,
        sentAt: CanonicalTimestamp,
        expiresAt: CanonicalTimestamp? = nil,
        stalenessPolicy: CanonicalStatusStalenessPolicy = .rejectOlderSequence,
        expirationPolicy: CanonicalStatusExpirationPolicy = .expireOnNewerSequence,
        delta: CanonicalStatusDelta? = nil,
        ack: CanonicalStatusAck? = nil,
        request: CanonicalStatusRequest? = nil,
        protocolVersion: CanonicalProtocolVersion = .v900
    ) {
        self.envelopeID = CanonicalKernelStringSanitizer.required(envelopeID, fallback: "status-exchange-envelope")
        self.protocolVersion = protocolVersion
        self.kind = kind
        self.sourceNodeID = sourceNodeID
        self.destinationNodeID = destinationNodeID
        self.sequence = sequence
        self.logicalTime = logicalTime
        self.sentAt = sentAt
        self.expiresAt = expiresAt
        self.stalenessPolicy = stalenessPolicy
        self.expirationPolicy = expirationPolicy
        self.delta = delta
        self.ack = ack
        self.request = request
    }
}

nonisolated enum CanonicalRealtimeStatusExchangeContract {
    nonisolated static let domain: CanonicalDomain = .sync
    nonisolated static let adapterSpecificRuntimeBindingCount = 0
    nonisolated static let mutatesFiles = false
    nonisolated static let createsUploadJobs = false
}
