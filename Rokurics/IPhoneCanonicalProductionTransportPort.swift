//
//  IPhoneCanonicalProductionTransportPort.swift
//  Rokurics
//
//  Created by Codex on 2026/6/2.
//

import Foundation

struct IPhoneCanonicalProductionTransportPort: CanonicalProductionTransportPort {
    typealias FakeResponder = @Sendable (CanonicalProductionSignedRequest) async throws -> CanonicalTransportResponse

    nonisolated let isDryRunOnly: Bool
    nonisolated let realNetworkExecutionEnabled: Bool
    nonisolated let routeCapabilities: [CanonicalProductionTransportRouteCapability]

    private let signerDescription: String
    private let fakeSignature: String?
    private let fakeResponder: FakeResponder?

    init() {
        self.init(
            mode: .disabled,
            signerDescription: "SecureMacUploadClient boundary only; production send suppressed",
            fakeSignature: nil,
            fakeResponder: nil
        )
    }

    init(
        fakeSignature: String = "iphone-production-adapter-test-signature",
        fakeResponder: @escaping FakeResponder
    ) {
        self.init(
            mode: .fakeLoopback,
            signerDescription: "SecureMacUploadClient fake signer; no URLSession",
            fakeSignature: fakeSignature,
            fakeResponder: fakeResponder
        )
    }

    func buildSignedRequest(_ request: CanonicalProductionTransportBuildRequest) async throws -> CanonicalProductionSignedRequest {
        try validateExistingRoutePath(request.existingRoutePath, route: request.route)
        return CanonicalProductionSignedRequest(
            buildRequest: request,
            signature: fakeSignature,
            signerDescription: signerDescription
        )
    }

    func sendRequest(_ request: CanonicalProductionSignedRequest) async throws -> CanonicalProductionTransportExchangeResult {
        guard let fakeResponder else {
            throw CanonicalProductionPortError.networkExecutionSuppressed("iphoneProductionTransportSendSuppressed")
        }
        try validateExistingRoutePath(request.buildRequest.existingRoutePath, route: request.buildRequest.route)
        let response = try await fakeResponder(request)
        guard response.hasValidBodyHash else {
            throw CanonicalTransportRuntimeError.invalidBodyHash("iphone-production-fake-response")
        }
        return CanonicalProductionTransportExchangeResult(
            request: request,
            response: response,
            responseVerified: true,
            usedExistingRoute: true,
            sideEffect: CanonicalProductionSideEffect(
                kind: .networkRequest,
                domain: .transportRuntime,
                route: request.buildRequest.route,
                byteSize: Int64(request.buildRequest.body.count),
                hash: request.bodyHash,
                summary: "iphoneFakeTransport:\(request.buildRequest.route.rawValue)"
            )
        )
    }

    func receiveResponse(
        _ response: CanonicalTransportResponse,
        for request: CanonicalProductionSignedRequest
    ) async throws -> CanonicalProductionTransportExchangeResult {
        guard response.hasValidBodyHash else {
            throw CanonicalTransportRuntimeError.invalidBodyHash("iphone-production-response")
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
            nonce: "external-nonce-required"
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
            reason: isDryRunOnly ? "iphoneProductionTransportDisabled" : "iphoneFakeTransportProjected"
        )
    }

    func decodeResponseDryRun(_ response: CanonicalTransportResponse) async throws -> CanonicalTransportResponse {
        guard response.hasValidBodyHash else {
            throw CanonicalTransportRuntimeError.invalidBodyHash("iphone-production-dry-run-response")
        }
        return response
    }

    nonisolated func existingRoutePath(for route: CanonicalTransportRoute) -> String {
        Self.existingRoutePaths[route] ?? "/sync/inventory"
    }

    private enum Mode: Sendable {
        case disabled
        case fakeLoopback
    }

    private init(
        mode: Mode,
        signerDescription: String,
        fakeSignature: String?,
        fakeResponder: FakeResponder?
    ) {
        self.isDryRunOnly = mode == .disabled
        self.realNetworkExecutionEnabled = false
        self.routeCapabilities = CanonicalTransportRoute.allCases.map {
            CanonicalProductionTransportRouteCapability(
                route: $0,
                requiresSigning: true,
                requiresVerification: true,
                dryRunOnly: mode == .disabled
            )
        }
        self.signerDescription = signerDescription
        self.fakeSignature = fakeSignature
        self.fakeResponder = fakeResponder
    }

    private func validateExistingRoutePath(_ path: String, route: CanonicalTransportRoute) throws {
        let sanitized = CanonicalProductionRedaction.safeDiagnosticText(path) ?? ""
        guard let allowed = Self.existingRoutePaths[route], sanitized == allowed else {
            throw CanonicalProductionPortError.routeBypassRisk("iphoneRouteNotMapped:\(route.rawValue)")
        }
    }

    private nonisolated static let existingRoutePaths: [CanonicalTransportRoute: String] = [
        .manifestExchange: "/sync/inventory",
        .applyPlan: "/sync/apply",
        .applyMetadata: "/sync/apply-metadata",
        .fileRead: "/sync/artifact-request",
        .uploadStart: "/upload-recording-audio-session/start",
        .uploadStatus: "/upload-recording-audio-session/status",
        .uploadChunk: "/upload-recording-audio-session/chunk",
        .uploadFinalize: "/upload-recording-audio-session/finalize"
    ]
}
