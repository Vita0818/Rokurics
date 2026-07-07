//
//  CanonicalConnectionProtocol.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalPeerLivenessState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case unknown
    case alive
    case stale
    case expired
    case unreachable
}

nonisolated struct CanonicalPeerLiveness: Codable, Equatable, Hashable, Sendable {
    var peer: CanonicalNodeIdentity
    var state: CanonicalPeerLivenessState
    var observedAt: CanonicalTimestamp
    var expiresAt: CanonicalTimestamp?
    var lastSequence: CanonicalSequence?
    var syncRequested: Bool

    nonisolated init(
        peer: CanonicalNodeIdentity,
        state: CanonicalPeerLivenessState,
        observedAt: CanonicalTimestamp,
        expiresAt: CanonicalTimestamp? = nil,
        lastSequence: CanonicalSequence? = nil,
        syncRequested: Bool = false
    ) {
        self.peer = peer
        self.state = state
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.lastSequence = lastSequence
        self.syncRequested = syncRequested
    }
}

nonisolated struct CanonicalConnectionEnvelope<Payload: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    var envelopeID: String
    var protocolVersion: CanonicalProtocolVersion
    var source: CanonicalNodeIdentity
    var destination: CanonicalNodeID?
    var sequence: CanonicalSequence
    var logicalTime: CanonicalLogicalTime
    var sentAt: CanonicalTimestamp
    var payload: Payload

    nonisolated init(
        envelopeID: String,
        source: CanonicalNodeIdentity,
        destination: CanonicalNodeID? = nil,
        sequence: CanonicalSequence,
        logicalTime: CanonicalLogicalTime,
        sentAt: CanonicalTimestamp,
        payload: Payload,
        protocolVersion: CanonicalProtocolVersion = .v900
    ) {
        self.envelopeID = CanonicalKernelStringSanitizer.required(envelopeID, fallback: "connection-envelope")
        self.protocolVersion = protocolVersion
        self.source = source
        self.destination = destination
        self.sequence = sequence
        self.logicalTime = logicalTime
        self.sentAt = sentAt
        self.payload = payload
    }
}

nonisolated enum CanonicalConnectionAckState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case accepted
    case deferred
    case stale
    case rejected
}

nonisolated struct CanonicalConnectionAck: Codable, Equatable, Hashable, Sendable {
    var acknowledgedEnvelopeID: String
    var acknowledgedSequence: CanonicalSequence
    var state: CanonicalConnectionAckState
    var acknowledgedAt: CanonicalTimestamp
    var reason: String?

    nonisolated init(
        acknowledgedEnvelopeID: String,
        acknowledgedSequence: CanonicalSequence,
        state: CanonicalConnectionAckState,
        acknowledgedAt: CanonicalTimestamp,
        reason: String? = nil
    ) {
        self.acknowledgedEnvelopeID = acknowledgedEnvelopeID
        self.acknowledgedSequence = acknowledgedSequence
        self.state = state
        self.acknowledgedAt = acknowledgedAt
        self.reason = CanonicalKernelStringSanitizer.optional(reason)
    }
}

nonisolated struct CanonicalHeartbeatPayload: Codable, Equatable, Hashable, Sendable {
    var liveness: CanonicalPeerLivenessState
    var capabilities: [CanonicalDomain]
    var syncRequested: Bool

    nonisolated init(
        liveness: CanonicalPeerLivenessState = .alive,
        capabilities: [CanonicalDomain] = CanonicalDomain.allCases,
        syncRequested: Bool = false
    ) {
        self.liveness = liveness
        self.capabilities = Array(Set(capabilities)).sorted { $0.rawValue < $1.rawValue }
        self.syncRequested = syncRequested
    }
}

nonisolated struct CanonicalConnectionStatusPayload: Codable, Equatable, Hashable, Sendable {
    var peerLiveness: CanonicalPeerLiveness
    var advertisedMode: CanonicalKernelModeMirror
    var statusSummary: String?

    nonisolated init(
        peerLiveness: CanonicalPeerLiveness,
        advertisedMode: CanonicalKernelModeMirror,
        statusSummary: String? = nil
    ) {
        self.peerLiveness = peerLiveness
        self.advertisedMode = advertisedMode
        self.statusSummary = CanonicalKernelStringSanitizer.optional(statusSummary)
    }
}

nonisolated struct CanonicalSyncRequestedPayload: Codable, Equatable, Hashable, Sendable {
    var requestedDomains: [CanonicalDomain]
    var reason: String
    var requestedAt: CanonicalTimestamp

    nonisolated init(
        requestedDomains: [CanonicalDomain],
        reason: String,
        requestedAt: CanonicalTimestamp
    ) {
        self.requestedDomains = Array(Set(requestedDomains)).sorted { $0.rawValue < $1.rawValue }
        self.reason = CanonicalKernelStringSanitizer.required(reason, fallback: "syncRequested")
        self.requestedAt = requestedAt
    }
}

nonisolated enum CanonicalConnectionNonGoal: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case markUploaded
    case scanFileTree
    case writeMetadata
    case createUploadJob
}

nonisolated protocol CanonicalConnectionCarrier: Sendable {
    func sendHeartbeat(
        _ envelope: CanonicalConnectionEnvelope<CanonicalHeartbeatPayload>
    ) async throws -> CanonicalConnectionAck

    func sendStatus(
        _ envelope: CanonicalConnectionEnvelope<CanonicalConnectionStatusPayload>
    ) async throws -> CanonicalConnectionAck

    func sendSyncRequested(
        _ envelope: CanonicalConnectionEnvelope<CanonicalSyncRequestedPayload>
    ) async throws -> CanonicalConnectionAck
}

nonisolated enum CanonicalConnectionContract {
    nonisolated static let domain: CanonicalDomain = .connection
    nonisolated static let nonGoals: [CanonicalConnectionNonGoal] = CanonicalConnectionNonGoal.allCases
    nonisolated static let mutatesTransferState = false
    nonisolated static let mutatesFileTree = false
    nonisolated static let createsUploadJobs = false
}
