//
//  CanonicalConnectionRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/15.
//

import Foundation

nonisolated enum CanonicalConnectionRuntimeMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case diagnosticsOnly
    case connectionOwnerWithLegacyFallback
    case blocked

    nonisolated var ownsCarrierState: Bool {
        self == .connectionOwnerWithLegacyFallback
    }
}

nonisolated struct CanonicalConnectionRuntimePolicy: Codable, Equatable, Hashable, Sendable {
    var debugInternalBuild: Bool
    var ownerApprovedCanonicalConnection: Bool
    var defaultReleaseOldKernel: Bool
    var legacyFallbackEnabled: Bool
    var requireExistingCarrierRoutes: Bool
    var heartbeatCallbackEnqueueOnly: Bool
    var statusExchangeCarrierEnabled: Bool
    var macReverseConnectionAllowed: Bool
    var livenessTTLSeconds: TimeInterval

    nonisolated init(
        debugInternalBuild: Bool = false,
        ownerApprovedCanonicalConnection: Bool = false,
        defaultReleaseOldKernel: Bool = true,
        legacyFallbackEnabled: Bool = true,
        requireExistingCarrierRoutes: Bool = true,
        heartbeatCallbackEnqueueOnly: Bool = true,
        statusExchangeCarrierEnabled: Bool = true,
        macReverseConnectionAllowed: Bool = false,
        livenessTTLSeconds: TimeInterval = 10
    ) {
        self.debugInternalBuild = debugInternalBuild
        self.ownerApprovedCanonicalConnection = ownerApprovedCanonicalConnection
        self.defaultReleaseOldKernel = defaultReleaseOldKernel
        self.legacyFallbackEnabled = legacyFallbackEnabled
        self.requireExistingCarrierRoutes = requireExistingCarrierRoutes
        self.heartbeatCallbackEnqueueOnly = heartbeatCallbackEnqueueOnly
        self.statusExchangeCarrierEnabled = statusExchangeCarrierEnabled
        self.macReverseConnectionAllowed = macReverseConnectionAllowed
        self.livenessTTLSeconds = max(1, livenessTTLSeconds)
    }

    nonisolated static let releaseDefault = CanonicalConnectionRuntimePolicy()
}

nonisolated struct CanonicalConnectionRuntimeConfiguration: Codable, Equatable, Hashable, Sendable {
    var mode: CanonicalConnectionRuntimeMode
    var policy: CanonicalConnectionRuntimePolicy

    nonisolated init(
        mode: CanonicalConnectionRuntimeMode = .disabled,
        policy: CanonicalConnectionRuntimePolicy = .releaseDefault
    ) {
        self.mode = mode
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalConnectionRuntimeConfiguration()
}

nonisolated enum CanonicalConnectionEnqueuedAction: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case enqueueRunSyncSoon
    case requestFullInventory
    case requestLightweightAudioProof
}

nonisolated struct CanonicalConnectionRuntimeSnapshot: Codable, Equatable, Hashable, Sendable {
    var mode: CanonicalConnectionRuntimeMode
    var localNode: CanonicalNodeIdentity
    var peers: [CanonicalPeerLiveness]
    var outboundSequence: CanonicalSequence
    var heartbeatCallbackEnqueueOnly: Bool
    var macReverseConnectionAllowed: Bool

    nonisolated init(
        mode: CanonicalConnectionRuntimeMode,
        localNode: CanonicalNodeIdentity,
        peers: [CanonicalPeerLiveness],
        outboundSequence: CanonicalSequence,
        heartbeatCallbackEnqueueOnly: Bool,
        macReverseConnectionAllowed: Bool
    ) {
        self.mode = mode
        self.localNode = localNode
        self.peers = peers.sorted { $0.peer.nodeID < $1.peer.nodeID }
        self.outboundSequence = outboundSequence
        self.heartbeatCallbackEnqueueOnly = heartbeatCallbackEnqueueOnly
        self.macReverseConnectionAllowed = macReverseConnectionAllowed
    }
}

actor CanonicalConnectionRuntime {
    private let configuration: CanonicalConnectionRuntimeConfiguration
    private let localNode: CanonicalNodeIdentity
    private var outboundSequence = CanonicalSequence()
    private var peersByID: [CanonicalNodeID: CanonicalPeerLiveness] = [:]

    init(
        configuration: CanonicalConnectionRuntimeConfiguration = .disabled,
        localNode: CanonicalNodeIdentity
    ) {
        self.configuration = configuration
        self.localNode = localNode
    }

    var mode: CanonicalConnectionRuntimeMode {
        configuration.mode
    }

    func makeHeartbeatEnvelope(
        destinationNodeID: CanonicalNodeID? = nil,
        syncRequested: Bool = false,
        now: Date = Date()
    ) -> CanonicalConnectionEnvelope<CanonicalHeartbeatPayload>? {
        guard configuration.mode != .disabled, configuration.mode != .blocked else {
            return nil
        }
        let sequence = nextSequence()
        let timestamp = CanonicalTimestamp(now)
        return CanonicalConnectionEnvelope(
            envelopeID: envelopeID(prefix: "connection-heartbeat", sequence: sequence),
            source: localNode,
            destination: destinationNodeID,
            sequence: sequence,
            logicalTime: CanonicalLogicalTime(counter: sequence.rawValue, nodeID: localNode.nodeID),
            sentAt: timestamp,
            payload: CanonicalHeartbeatPayload(
                liveness: .alive,
                capabilities: localNode.domains,
                syncRequested: syncRequested
            )
        )
    }

    func makeStatusEnvelope(
        peer: CanonicalNodeIdentity,
        destinationNodeID: CanonicalNodeID? = nil,
        advertisedMode: CanonicalKernelModeMirror,
        statusSummary: String? = nil,
        now: Date = Date()
    ) -> CanonicalConnectionEnvelope<CanonicalConnectionStatusPayload>? {
        guard configuration.mode != .disabled, configuration.mode != .blocked else {
            return nil
        }
        let sequence = nextSequence()
        let liveness = peersByID[peer.nodeID] ?? CanonicalPeerLiveness(
            peer: peer,
            state: .unknown,
            observedAt: CanonicalTimestamp(now),
            expiresAt: expiresAt(from: now),
            lastSequence: nil,
            syncRequested: false
        )
        return CanonicalConnectionEnvelope(
            envelopeID: envelopeID(prefix: "connection-status", sequence: sequence),
            source: localNode,
            destination: destinationNodeID,
            sequence: sequence,
            logicalTime: CanonicalLogicalTime(counter: sequence.rawValue, nodeID: localNode.nodeID),
            sentAt: CanonicalTimestamp(now),
            payload: CanonicalConnectionStatusPayload(
                peerLiveness: liveness,
                advertisedMode: advertisedMode,
                statusSummary: statusSummary
            )
        )
    }

    func makeSyncRequestedEnvelope(
        destinationNodeID: CanonicalNodeID? = nil,
        requestedDomains: [CanonicalDomain] = [.sync],
        reason: String = "syncRequested",
        now: Date = Date()
    ) -> CanonicalConnectionEnvelope<CanonicalSyncRequestedPayload>? {
        guard configuration.mode != .disabled, configuration.mode != .blocked else {
            return nil
        }
        let sequence = nextSequence()
        return CanonicalConnectionEnvelope(
            envelopeID: envelopeID(prefix: "connection-sync-requested", sequence: sequence),
            source: localNode,
            destination: destinationNodeID,
            sequence: sequence,
            logicalTime: CanonicalLogicalTime(counter: sequence.rawValue, nodeID: localNode.nodeID),
            sentAt: CanonicalTimestamp(now),
            payload: CanonicalSyncRequestedPayload(
                requestedDomains: requestedDomains,
                reason: reason,
                requestedAt: CanonicalTimestamp(now)
            )
        )
    }

    func makeStatusRequest(
        kind: CanonicalStatusRequestKind = .runSyncSoon,
        objectIDs: [CanonicalObjectID] = [],
        requestedDomains: [CanonicalDomain] = [.sync],
        sinceSequence: CanonicalSequence? = nil
    ) -> CanonicalStatusRequest? {
        guard configuration.mode != .disabled, configuration.mode != .blocked else {
            return nil
        }
        let sequence = nextSequence()
        return CanonicalStatusRequest(
            requestID: envelopeID(prefix: "connection-status-request", sequence: sequence),
            kind: kind,
            objectIDs: objectIDs,
            requestedDomains: requestedDomains,
            sinceSequence: sinceSequence
        )
    }

    @discardableResult
    func recordIncomingHeartbeat(
        from peer: CanonicalNodeIdentity,
        sequence: CanonicalSequence,
        syncRequested: Bool,
        observedAt: Date = Date()
    ) -> CanonicalPeerLiveness {
        let liveness = CanonicalPeerLiveness(
            peer: peer,
            state: .alive,
            observedAt: CanonicalTimestamp(observedAt),
            expiresAt: expiresAt(from: observedAt),
            lastSequence: sequence,
            syncRequested: syncRequested
        )
        peersByID[peer.nodeID] = liveness
        return liveness
    }

    @discardableResult
    func recordHeartbeatAcknowledged(
        peer: CanonicalNodeIdentity,
        acknowledgedSequence: CanonicalSequence,
        syncRequested: Bool,
        observedAt: Date = Date()
    ) -> CanonicalPeerLiveness {
        recordIncomingHeartbeat(
            from: peer,
            sequence: acknowledgedSequence,
            syncRequested: syncRequested,
            observedAt: observedAt
        )
    }

    @discardableResult
    func recordHeartbeatFailed(
        peer: CanonicalNodeIdentity,
        observedAt: Date = Date()
    ) -> CanonicalPeerLiveness {
        let previous = peersByID[peer.nodeID]
        let state: CanonicalPeerLivenessState = previous?.state == .expired ? .unreachable : .stale
        let liveness = CanonicalPeerLiveness(
            peer: peer,
            state: state,
            observedAt: CanonicalTimestamp(observedAt),
            expiresAt: previous?.expiresAt ?? expiresAt(from: observedAt),
            lastSequence: previous?.lastSequence,
            syncRequested: previous?.syncRequested ?? false
        )
        peersByID[peer.nodeID] = liveness
        return liveness
    }

    func peerLiveness(for peerID: CanonicalNodeID, now: Date = Date()) -> CanonicalPeerLiveness? {
        guard var liveness = peersByID[peerID] else {
            return nil
        }
        if let expiresAt = liveness.expiresAt, expiresAt.date <= now, liveness.state == .alive {
            liveness.state = .expired
            peersByID[peerID] = liveness
        }
        return liveness
    }

    func snapshot(now: Date = Date()) -> CanonicalConnectionRuntimeSnapshot {
        for peerID in peersByID.keys {
            _ = peerLiveness(for: peerID, now: now)
        }
        return CanonicalConnectionRuntimeSnapshot(
            mode: configuration.mode,
            localNode: localNode,
            peers: Array(peersByID.values),
            outboundSequence: outboundSequence,
            heartbeatCallbackEnqueueOnly: configuration.policy.heartbeatCallbackEnqueueOnly,
            macReverseConnectionAllowed: configuration.policy.macReverseConnectionAllowed
        )
    }

    nonisolated func enqueuedActions(
        syncRequested: Bool,
        requestedStatusActions: [CanonicalStatusExchangeRequestedAction] = []
    ) -> [CanonicalConnectionEnqueuedAction] {
        var actions: Set<CanonicalConnectionEnqueuedAction> = []
        if syncRequested {
            actions.insert(.enqueueRunSyncSoon)
        }
        if requestedStatusActions.contains(.enqueueRunSyncSoon) {
            actions.insert(.enqueueRunSyncSoon)
        }
        if requestedStatusActions.contains(.requestFullInventory) {
            actions.insert(.requestFullInventory)
        }
        if requestedStatusActions.contains(.requestLightweightAudioProof) {
            actions.insert(.requestLightweightAudioProof)
        }
        return actions.sorted { $0.rawValue < $1.rawValue }
    }

    private func nextSequence() -> CanonicalSequence {
        outboundSequence = outboundSequence.next
        return outboundSequence
    }

    private nonisolated func envelopeID(prefix: String, sequence: CanonicalSequence) -> String {
        "\(prefix)-\(localNode.nodeID.rawValue)-\(sequence.rawValue)"
    }

    private nonisolated func expiresAt(from date: Date) -> CanonicalTimestamp {
        CanonicalTimestamp(date.addingTimeInterval(configuration.policy.livenessTTLSeconds))
    }
}
