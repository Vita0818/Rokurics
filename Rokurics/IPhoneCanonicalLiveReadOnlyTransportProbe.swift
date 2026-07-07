//
//  IPhoneCanonicalLiveReadOnlyTransportProbe.swift
//  Rokurics
//
//  Created by Codex on 2026/6/3.
//

import Foundation

protocol IPhoneCanonicalReadOnlyProbeSending {
    func evaluateAndMaybeSend(
        settings: SecureMacConnectionSnapshot,
        policy: CanonicalLiveReadOnlyTransportProbePolicy,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String,
        generatedAt: Date
    ) async -> CanonicalLiveReadOnlyTransportProbeResult
}

struct IPhoneCanonicalReadOnlyProbeRequestBuilder {
    private let encoder: JSONEncoder

    init() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func body(
        route: CanonicalLiveReadOnlyTransportProbeRoute,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String,
        generatedAt: Date
    ) throws -> LocalNetworkSyncInventoryRequest {
        guard route == .syncInventory else {
            throw SecureMacUploadError.serverRejected("unsupported_read_only_probe_route")
        }
        return LocalNetworkSyncInventoryRequest(
            deviceID: localInventory.device.deviceID,
            generatedAt: generatedAt,
            localInventoryHash: localInventory.inventoryHash,
            syncRunID: syncRunID
        )
    }

    func encodedBody(_ body: LocalNetworkSyncInventoryRequest) throws -> Data {
        try encoder.encode(body)
    }
}

struct IPhoneCanonicalReadOnlyProbeAudit {
    var requestBuilt: Bool
    var bodyByteCount: Int
    var bodyHashPrefix: String?
    var authBoundaryPreserved: Bool

    init(preparedRequest: SecureUploadPreparedRequest?) {
        guard let preparedRequest else {
            self.requestBuilt = false
            self.bodyByteCount = 0
            self.bodyHashPrefix = nil
            self.authBoundaryPreserved = false
            return
        }
        let normalizedHeaders = preparedRequest.headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }
        let bodyHash = SecureUploadUtilities.sha256Hex(preparedRequest.body)
        self.requestBuilt = true
        self.bodyByteCount = preparedRequest.body.count
        self.bodyHashPrefix = String(bodyHash.prefix(12))
        self.authBoundaryPreserved =
            normalizedHeaders["x-rokurics-device-id"] != nil &&
            normalizedHeaders["x-rokurics-timestamp"] != nil &&
            normalizedHeaders["x-rokurics-nonce"] != nil &&
            normalizedHeaders["x-rokurics-signature"] != nil &&
            normalizedHeaders["x-rokurics-body-sha256"] == bodyHash &&
            normalizedHeaders[CanonicalLiveReadOnlyTransportProbeHTTP.markerHeader.lowercased()] == CanonicalLiveReadOnlyTransportProbeHTTP.markerValue
    }
}

struct IPhoneCanonicalReadOnlyTransportProbeSender: IPhoneCanonicalReadOnlyProbeSending {
    private let client: SecureMacUploadClient
    private let requestBuilder: IPhoneCanonicalReadOnlyProbeRequestBuilder

    init(
        client: SecureMacUploadClient = SecureMacUploadClient(),
        requestBuilder: IPhoneCanonicalReadOnlyProbeRequestBuilder = IPhoneCanonicalReadOnlyProbeRequestBuilder()
    ) {
        self.client = client
        self.requestBuilder = requestBuilder
    }

    func evaluateAndMaybeSend(
        settings: SecureMacConnectionSnapshot,
        policy: CanonicalLiveReadOnlyTransportProbePolicy,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String,
        generatedAt: Date
    ) async -> CanonicalLiveReadOnlyTransportProbeResult {
        if policy.route != .syncInventory {
            let gate = CanonicalLiveReadOnlyTransportProbeGate.evaluate(policy: policy, bodyByteCount: 0)
            var diagnostics: [CanonicalLiveReadOnlyTransportProbeDiagnosticKind] = [
                .canonicalLiveReadOnlyProbePolicyEvaluated
            ]
            diagnostics.append(gate.routeStatus == .allowedReadOnly ? .canonicalLiveReadOnlyProbeRouteAllowed : .canonicalLiveReadOnlyProbeRouteRejected)
            if !gate.shouldBuildEnvelope {
                diagnostics.append(.canonicalLiveReadOnlyProbeSendSuppressed)
                return CanonicalLiveReadOnlyTransportProbeResult(
                    mode: gate.mode,
                    route: gate.route,
                    routeStatus: gate.routeStatus,
                    blocked: gate.blocked,
                    suppressed: gate.suppressed,
                    failure: gate.failure,
                    diagnostics: diagnostics,
                    reason: gate.reason
                )
            }
            diagnostics.append(.canonicalLiveReadOnlyProbeSendFailed)
            return CanonicalLiveReadOnlyTransportProbeResult(
                mode: gate.mode,
                route: gate.route,
                routeStatus: gate.routeStatus,
                blocked: true,
                failure: .signedEnvelopeBuildFailed,
                diagnostics: diagnostics,
                reason: "unsupportedSignedReadOnlyProbeRoute"
            )
        }

        let body: LocalNetworkSyncInventoryRequest
        let encodedBody: Data
        do {
            body = try requestBuilder.body(
                route: policy.route,
                localInventory: localInventory,
                syncRunID: syncRunID,
                generatedAt: generatedAt
            )
            encodedBody = try requestBuilder.encodedBody(body)
        } catch {
            let gate = CanonicalLiveReadOnlyTransportProbeGate.evaluate(policy: policy, bodyByteCount: 0)
            return CanonicalLiveReadOnlyTransportProbeResult(
                mode: gate.mode,
                route: gate.route,
                routeStatus: gate.routeStatus,
                blocked: true,
                failure: .signedEnvelopeBuildFailed,
                diagnostics: [
                    .canonicalLiveReadOnlyProbePolicyEvaluated,
                    .canonicalLiveReadOnlyProbeRouteRejected,
                    .canonicalLiveReadOnlyProbeSendFailed
                ],
                reason: "unsupportedLiveReadOnlyProbeRoute"
            )
        }

        let gate = CanonicalLiveReadOnlyTransportProbeGate.evaluate(
            policy: policy,
            bodyByteCount: encodedBody.count
        )
        var diagnostics: [CanonicalLiveReadOnlyTransportProbeDiagnosticKind] = [
            .canonicalLiveReadOnlyProbePolicyEvaluated
        ]
        diagnostics.append(gate.routeStatus == .allowedReadOnly ? .canonicalLiveReadOnlyProbeRouteAllowed : .canonicalLiveReadOnlyProbeRouteRejected)

        guard gate.shouldBuildEnvelope else {
            if gate.suppressed {
                diagnostics.append(.canonicalLiveReadOnlyProbeSendSuppressed)
            }
            return CanonicalLiveReadOnlyTransportProbeResult(
                mode: gate.mode,
                route: gate.route,
                routeStatus: gate.routeStatus,
                blocked: gate.blocked,
                suppressed: gate.suppressed,
                failure: gate.failure,
                diagnostics: diagnostics,
                reason: gate.reason
            )
        }

        let preparedRequest: SecureUploadPreparedRequest
        do {
            preparedRequest = try client.prepareCanonicalLiveReadOnlyProbeRequest(
                settings: settings,
                policy: policy,
                body: body,
                syncRunID: syncRunID,
                now: generatedAt
            )
        } catch {
            diagnostics.append(.canonicalLiveReadOnlyProbeSendFailed)
            return CanonicalLiveReadOnlyTransportProbeResult(
                mode: gate.mode,
                route: gate.route,
                routeStatus: gate.routeStatus,
                blocked: true,
                failure: .signedEnvelopeBuildFailed,
                diagnostics: diagnostics,
                reason: "signedEnvelopeBuildFailed"
            )
        }

        let audit = IPhoneCanonicalReadOnlyProbeAudit(preparedRequest: preparedRequest)
        diagnostics.append(.canonicalLiveReadOnlyProbeEnvelopeBuilt)
        if audit.authBoundaryPreserved {
            diagnostics.append(.canonicalLiveReadOnlyProbeAuthBoundaryPreserved)
        }

        guard gate.shouldSend else {
            diagnostics.append(.canonicalLiveReadOnlyProbeSendSuppressed)
            return CanonicalLiveReadOnlyTransportProbeResult(
                mode: gate.mode,
                route: gate.route,
                routeStatus: gate.routeStatus,
                envelopeBuilt: true,
                suppressed: true,
                authBoundaryPreserved: audit.authBoundaryPreserved,
                failure: .networkSuppressed,
                diagnostics: diagnostics,
                reason: gate.reason
            )
        }

        diagnostics.append(.canonicalLiveReadOnlyProbeSendStarted)
        do {
            let response = try await client.sendCanonicalLiveReadOnlyProbe(
                settings: settings,
                preparedRequest: preparedRequest,
                route: policy.route,
                requestTimeout: policy.requestTimeoutSeconds,
                resourceTimeout: policy.resourceTimeoutSeconds
            )
            diagnostics.append(.canonicalLiveReadOnlyProbeSendCompleted)
            return CanonicalLiveReadOnlyTransportProbeResult(
                mode: gate.mode,
                route: gate.route,
                routeStatus: gate.routeStatus,
                envelopeBuilt: true,
                sentNetwork: true,
                completed: true,
                suppressed: false,
                authBoundaryPreserved: audit.authBoundaryPreserved,
                httpStatusCode: response.statusCode,
                responseByteCount: response.responseByteCount,
                diagnostics: diagnostics,
                reason: "readOnlyProbeCompleted"
            )
        } catch {
            diagnostics.append(.canonicalLiveReadOnlyProbeSendFailed)
            return CanonicalLiveReadOnlyTransportProbeResult(
                mode: gate.mode,
                route: gate.route,
                routeStatus: gate.routeStatus,
                envelopeBuilt: true,
                sentNetwork: false,
                completed: false,
                blocked: false,
                suppressed: false,
                authBoundaryPreserved: audit.authBoundaryPreserved,
                failure: .sendFailed,
                diagnostics: diagnostics,
                reason: "readOnlyProbeSendFailed"
            )
        }
    }
}
