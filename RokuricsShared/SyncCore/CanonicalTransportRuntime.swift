//
//  CanonicalTransportRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import CryptoKit
import Foundation

nonisolated enum CanonicalTransportRoute: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case manifestExchange
    case applyPlan
    case applyMetadata
    case fileRead
    case uploadStart
    case uploadStatus
    case uploadChunk
    case uploadFinalize
}

nonisolated struct CanonicalTransportEnvelope: Codable, Equatable, Identifiable, Sendable {
    var id: String { requestID }

    var requestID: String
    var sourceNodeID: String
    var destinationNodeID: String
    var route: CanonicalTransportRoute
    var body: Data
    var bodyHash: CanonicalHash
    var idempotencyKey: String?
    var sentAt: CanonicalTimestamp

    nonisolated init(
        requestID: String = UUID().uuidString,
        sourceNodeID: String,
        destinationNodeID: String,
        route: CanonicalTransportRoute,
        body: Data = Data(),
        idempotencyKey: String? = nil,
        sentAt: Date = Date()
    ) {
        self.requestID = requestID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? UUID().uuidString
        self.sourceNodeID = sourceNodeID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "source:unknown"
        self.destinationNodeID = destinationNodeID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "destination:unknown"
        self.route = route
        self.body = body
        self.bodyHash = Self.hash(body)
        self.idempotencyKey = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.sentAt = CanonicalTimestamp(sentAt)
    }

    nonisolated var hasValidBodyHash: Bool {
        Self.hash(body) == bodyHash
    }

    nonisolated static func hash(_ data: Data) -> CanonicalHash {
        let digest = SHA256.hash(data: data)
        return CanonicalHash(digest.map { String(format: "%02x", $0) }.joined())
    }
}

nonisolated struct CanonicalTransportResponse: Codable, Equatable, Sendable {
    var ok: Bool
    var status: String
    var body: Data
    var bodyHash: CanonicalHash
    var error: String?

    nonisolated init(ok: Bool, status: String, body: Data = Data(), error: String? = nil) {
        self.ok = ok
        self.status = status.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (ok ? "ok" : "failed")
        self.body = body
        self.bodyHash = CanonicalTransportEnvelope.hash(body)
        self.error = error?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    nonisolated var hasValidBodyHash: Bool {
        CanonicalTransportEnvelope.hash(body) == bodyHash
    }
}

nonisolated enum CanonicalTransportRuntimeError: Error, Equatable, Sendable {
    case nodeNotRegistered(String)
    case routeNotAllowed(CanonicalTransportRoute)
    case capabilityMissing(nodeID: String, capability: CanonicalCapability)
    case invalidBodyHash(String)
    case invalidManifestHash(String)
    case incompatibleSchema(Int)
    case handlerMissing(CanonicalTransportRoute)
}

nonisolated protocol CanonicalTransportPort: Sendable {
    func register(node: CanonicalNode, allowedRoutes: Set<CanonicalTransportRoute>) async
    func send(_ envelope: CanonicalTransportEnvelope) async throws -> CanonicalTransportResponse
}

actor InMemoryCanonicalTransportRuntime: CanonicalTransportPort {
    typealias Handler = @Sendable (CanonicalTransportEnvelope) async throws -> CanonicalTransportResponse

    private var nodes: [String: CanonicalNode] = [:]
    private var routesByNodeID: [String: Set<CanonicalTransportRoute>] = [:]
    private var handlers: [String: Handler] = [:]
    private var idempotencyResponses: [String: CanonicalTransportResponse] = [:]

    func register(node: CanonicalNode, allowedRoutes: Set<CanonicalTransportRoute> = Set(CanonicalTransportRoute.allCases)) async {
        nodes[node.nodeID] = node
        routesByNodeID[node.nodeID] = allowedRoutes
    }

    func registerHandler(
        nodeID: String,
        route: CanonicalTransportRoute,
        handler: @escaping Handler
    ) async {
        handlers[handlerKey(nodeID: nodeID, route: route)] = handler
    }

    func send(_ envelope: CanonicalTransportEnvelope) async throws -> CanonicalTransportResponse {
        guard envelope.hasValidBodyHash else {
            throw CanonicalTransportRuntimeError.invalidBodyHash(envelope.requestID)
        }
        guard let source = nodes[envelope.sourceNodeID] else {
            throw CanonicalTransportRuntimeError.nodeNotRegistered(envelope.sourceNodeID)
        }
        guard let destination = nodes[envelope.destinationNodeID] else {
            throw CanonicalTransportRuntimeError.nodeNotRegistered(envelope.destinationNodeID)
        }
        guard routesByNodeID[envelope.destinationNodeID]?.contains(envelope.route) == true else {
            throw CanonicalTransportRuntimeError.routeNotAllowed(envelope.route)
        }
        try validateCapabilities(source: source, destination: destination, route: envelope.route)

        if let idempotencyKey = envelope.idempotencyKey {
            let replayKey = idempotencyResponseKey(envelope: envelope, idempotencyKey: idempotencyKey)
            if let response = idempotencyResponses[replayKey] {
                return response
            }
            let response = try await dispatch(envelope)
            idempotencyResponses[replayKey] = response
            return response
        }
        return try await dispatch(envelope)
    }

    func validateManifest(_ manifest: CanonicalManifest) throws {
        guard manifest.schemaVersion == CanonicalManifest.currentSchemaVersion else {
            throw CanonicalTransportRuntimeError.incompatibleSchema(manifest.schemaVersion)
        }
        guard manifest.hasValidManifestHash else {
            throw CanonicalTransportRuntimeError.invalidManifestHash(manifest.node.nodeID)
        }
    }

    private func dispatch(_ envelope: CanonicalTransportEnvelope) async throws -> CanonicalTransportResponse {
        guard let handler = handlers[handlerKey(nodeID: envelope.destinationNodeID, route: envelope.route)] else {
            throw CanonicalTransportRuntimeError.handlerMissing(envelope.route)
        }
        let response = try await handler(envelope)
        guard response.hasValidBodyHash else {
            throw CanonicalTransportRuntimeError.invalidBodyHash(envelope.requestID)
        }
        return response
    }

    private func validateCapabilities(
        source: CanonicalNode,
        destination: CanonicalNode,
        route: CanonicalTransportRoute
    ) throws {
        for capability in requiredCapabilities(for: route) {
            guard source.capabilities.contains(capability) else {
                throw CanonicalTransportRuntimeError.capabilityMissing(nodeID: source.nodeID, capability: capability)
            }
            guard destination.capabilities.contains(capability) else {
                throw CanonicalTransportRuntimeError.capabilityMissing(nodeID: destination.nodeID, capability: capability)
            }
        }
    }

    private func requiredCapabilities(for route: CanonicalTransportRoute) -> [CanonicalCapability] {
        switch route {
        case .manifestExchange:
            return [.recordingMetadata]
        case .applyPlan, .applyMetadata:
            return [.recordingMetadata]
        case .fileRead:
            return [.objectProjection]
        case .uploadStart, .uploadStatus, .uploadChunk, .uploadFinalize:
            return [.audioArtifact]
        }
    }

    private func handlerKey(nodeID: String, route: CanonicalTransportRoute) -> String {
        "\(nodeID)|\(route.rawValue)"
    }

    private func idempotencyResponseKey(envelope: CanonicalTransportEnvelope, idempotencyKey: String) -> String {
        [
            envelope.sourceNodeID,
            envelope.destinationNodeID,
            envelope.route.rawValue,
            idempotencyKey
        ].joined(separator: "|")
    }
}

nonisolated enum CanonicalTransportJSON {
    nonisolated static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestampString(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    nonisolated static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let seconds = Double(value) {
                return Date(timeIntervalSince1970: seconds)
            }
            if let date = fractionalDateFormatter.date(from: value) ?? wholeSecondDateFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
        }
        return try decoder.decode(type, from: data)
    }

    nonisolated private static func timestampString(_ date: Date) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), date.timeIntervalSince1970)
    }

    nonisolated private static var fractionalDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    nonisolated private static var wholeSecondDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
