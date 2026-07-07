//
//  IPhoneCanonicalShadowTransportPort.swift
//  Rokurics
//
//  Created by Codex on 2026/6/2.
//

import Foundation

struct IPhoneCanonicalShadowTransportPort: CanonicalProductionTransportPort {
    nonisolated let isDryRunOnly = false
    nonisolated let realNetworkExecutionEnabled = false
    nonisolated let routeCapabilities: [CanonicalProductionTransportRouteCapability]

    private let signerDescription = "SecureMacUploadClient shadow envelope projection; network send suppressed"
    private let signatureProjection: String

    init(signatureProjection: String = "iphone-shadow-signature-projection") {
        self.signatureProjection = signatureProjection
        self.routeCapabilities = CanonicalTransportRoute.allCases.map {
            CanonicalProductionTransportRouteCapability(route: $0, requiresSigning: true, requiresVerification: true, dryRunOnly: false)
        }
    }

    func buildSignedRequest(_ request: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionSignedRequest {
        try validateExistingRoutePath(request.existingRoutePath, route: request.route)
        return CanonicalProductionSignedRequest(
            buildRequest: request,
            signature: signatureProjection,
            signerDescription: signerDescription
        )
    }

    func sendRequest(_ request: CanonicalProductionSignedRequest) async throws -> CanonicalProductionTransportExchangeResult {
        throw CanonicalProductionPortError.networkExecutionSuppressed("iphoneShadowTransportSendSuppressed")
    }

    func receiveResponse(
        _ response: CanonicalTransportResponse,
        for request: CanonicalProductionSignedRequest
    ) async throws -> CanonicalProductionTransportExchangeResult {
        guard response.hasValidBodyHash else {
            throw CanonicalTransportRuntimeError.invalidBodyHash("iphone-shadow-response")
        }
        return CanonicalProductionTransportExchangeResult(
            request: request,
            response: response,
            responseVerified: true,
            usedExistingRoute: true,
            sideEffect: nil
        )
    }

    func verifyResponse(_ exchange: CanonicalProductionTransportExchangeResult) async throws -> CanonicalProductionTransportVerification {
        CanonicalProductionTransportVerification(
            route: exchange.request.buildRequest.route,
            bodyHashVerified: CanonicalTransportEnvelope.hash(exchange.request.buildRequest.body) == exchange.request.bodyHash,
            responseHashVerified: exchange.response.hasValidBodyHash,
            timestampAccepted: true,
            externalVerifierRequired: true
        )
    }

    func exchangeManifest(_ request: CanonicalProductionManifestExchangeRequest) async throws -> CanonicalProductionTransportExchangeResult {
        let body = try CanonicalTransportJSON.encode(request.localManifest)
        let build = CanonicalProductionTransportBuildRequest(
            source: request.localManifest.node,
            destination: request.peerNode,
            route: .manifestExchange,
            existingRoutePath: existingRoutePath(for: .manifestExchange),
            body: body,
            nonce: "shadow-nonce-projection"
        )
        return try await sendRequest(try await buildSignedRequest(build))
    }

    func requestArtifact(
        _ request: CanonicalProductionArtifactRequest,
        envelope: CanonicalProductionTransportBuildRequest
    ) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    func sendApplyMetadata(
        _ action: CanonicalApplyAction,
        envelope: CanonicalProductionTransportBuildRequest
    ) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    func startUploadSession(
        _ request: CanonicalUploadStartRequest,
        envelope: CanonicalProductionTransportBuildRequest
    ) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    func queryUploadSession(
        _ request: CanonicalUploadStatusRequest,
        envelope: CanonicalProductionTransportBuildRequest
    ) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    func sendUploadChunk(
        _ chunk: CanonicalUploadChunk,
        envelope: CanonicalProductionTransportBuildRequest
    ) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    func finalizeUploadSession(
        _ request: CanonicalUploadFinalizeRequest,
        envelope: CanonicalProductionTransportBuildRequest
    ) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    func cancelUploadSession(
        _ request: CanonicalProductionUploadCancelRequest,
        envelope: CanonicalProductionTransportBuildRequest
    ) async throws -> CanonicalProductionTransportExchangeResult {
        try await sendRequest(try await buildSignedRequest(envelope))
    }

    func buildEnvelopeDryRun(
        source: CanonicalNode,
        destination: CanonicalNode,
        route: CanonicalTransportRoute,
        body: Data
    ) async throws -> CanonicalProductionTransportEnvelopeDryRun {
        guard routeCapabilities.contains(where: { $0.route == route }) else {
            throw CanonicalProductionPortError.routeBypassRisk(route.rawValue)
        }
        return CanonicalProductionTransportEnvelopeDryRun(
            route: route,
            sourceNodeID: source.nodeID,
            destinationNodeID: destination.nodeID,
            bodyHash: CanonicalTransportEnvelope.hash(body),
            requiresSigning: true,
            requiresVerification: true,
            reason: "iphoneShadowTransportProjected"
        )
    }

    func decodeResponseDryRun(_ response: CanonicalTransportResponse) async throws -> CanonicalTransportResponse {
        guard response.hasValidBodyHash else {
            throw CanonicalTransportRuntimeError.invalidBodyHash("iphone-shadow-dry-run-response")
        }
        return response
    }

    func buildReadOnlyProbeRequest(
        route: CanonicalReadOnlyTransportProbeRoute,
        body: Data = Data(),
        manifestHashPresent: Bool = false
    ) -> CanonicalReadOnlyTransportProbeRequest {
        CanonicalReadOnlyTransportProbeRequest(
            route: route,
            bodyByteCount: body.count,
            bodyHash: CanonicalTransportEnvelope.hash(body),
            timestampPresent: true,
            noncePresent: true,
            signaturePresent: true,
            tlsPinningPreserved: true,
            hmacPreserved: true,
            bodyHashPreserved: true,
            manifestHashPresent: manifestHashPresent,
            manifestHashUsedAsAuth: false
        )
    }

    nonisolated func existingRoutePath(for route: CanonicalTransportRoute) -> String {
        Self.existingRoutePaths[route] ?? "/sync/inventory"
    }

    private func validateExistingRoutePath(_ path: String, route: CanonicalTransportRoute) throws {
        let sanitized = CanonicalProductionRedaction.safeDiagnosticText(path) ?? ""
        guard let allowed = Self.existingRoutePaths[route], sanitized == allowed else {
            throw CanonicalProductionPortError.routeBypassRisk("iphoneShadowRouteNotMapped:\(route.rawValue)")
        }
    }

    private nonisolated static let existingRoutePaths: [CanonicalTransportRoute: String] = [
        .manifestExchange: "/sync/inventory",
        .applyPlan: "/sync/apply",
        .fileRead: "/sync/artifact-request",
        .uploadStart: "/upload-recording-audio-session/start",
        .uploadStatus: "/upload-recording-audio-session/status",
        .uploadChunk: "/upload-recording-audio-session/chunk",
        .uploadFinalize: "/upload-recording-audio-session/finalize"
    ]
}
