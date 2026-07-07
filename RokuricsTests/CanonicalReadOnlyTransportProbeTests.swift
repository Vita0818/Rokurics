//
//  CanonicalReadOnlyTransportProbeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalReadOnlyTransportProbeTests {
    @Test func defaultDisabledProbeSuppressesReadOnlyRequest() {
        let request = IPhoneCanonicalShadowTransportPort().buildReadOnlyProbeRequest(
            route: .health,
            body: Data(),
            manifestHashPresent: false
        )
        let result = CanonicalReadOnlyTransportProbe().evaluate(request: request)

        #expect(result.status == "disabled")
        #expect(result.routeStatus == .suppressedDisabled)
        #expect(result.sentNetwork == false)
        #expect(result.suppressed)
        #expect(result.blocked == false)
        #expect(result.failure == .disabled)
        #expect(result.authBoundaryPreserved)
    }

    @Test func enabledProbeAcceptsReadOnlyInventoryAndSuppressesNetworkByDefault() {
        let request = IPhoneCanonicalShadowTransportPort().buildReadOnlyProbeRequest(
            route: .syncInventory,
            body: Data("{}".utf8),
            manifestHashPresent: true
        )
        let result = CanonicalReadOnlyTransportProbe().evaluate(
            request: request,
            policy: .enabled()
        )

        #expect(result.status == "suppressed")
        #expect(result.routeStatus == .allowedReadOnly)
        #expect(result.sentNetwork == false)
        #expect(result.suppressed)
        #expect(result.blocked == false)
        #expect(result.failure == .networkSuppressed)
        #expect(result.authBoundaryPreserved)
        #expect(result.audit.manifestHashUsedAsAuth == false)
        #expect(result.diagnosticsSummary.contains("POST /sync/inventory"))
    }

    @Test func mutatingRoutesAndManifestHashAuthAreBlocked() {
        let mutating = CanonicalReadOnlyTransportProbeRequest(
            route: CanonicalReadOnlyTransportProbeRoute(method: "POST", path: "/sync/apply"),
            bodyByteCount: 2,
            bodyHash: CanonicalTransportEnvelope.hash(Data("{}".utf8))
        )
        let mutatingResult = CanonicalReadOnlyTransportProbe().evaluate(
            request: mutating,
            policy: .enabled()
        )
        #expect(mutatingResult.status == "blocked")
        #expect(mutatingResult.routeStatus == .rejectedMutating)
        #expect(mutatingResult.sentNetwork == false)
        #expect(mutatingResult.failure == .mutatingRouteRejected)

        let manifestHashAsAuth = CanonicalReadOnlyTransportProbeRequest(
            route: .syncInventory,
            bodyByteCount: 2,
            bodyHash: CanonicalTransportEnvelope.hash(Data("{}".utf8)),
            manifestHashPresent: true,
            manifestHashUsedAsAuth: true
        )
        let authResult = CanonicalReadOnlyTransportProbe().evaluate(
            request: manifestHashAsAuth,
            policy: .enabled()
        )
        #expect(authResult.status == "blocked")
        #expect(authResult.failure == .manifestHashUsedAsAuth)
        #expect(authResult.sentNetwork == false)
        #expect(authResult.authBoundaryPreserved == false)
    }

    @Test func signedShadowRequestProjectsToReadOnlyProbeWithoutSendingNetwork() async throws {
        let port = IPhoneCanonicalShadowTransportPort()
        let signed = try await port.buildSignedRequest(
            CanonicalProductionTransportBuildRequest(
                source: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"),
                destination: CanonicalProductionTestFixtures.node("mac-01", platform: "Mac"),
                route: .manifestExchange,
                existingRoutePath: port.existingRoutePath(for: .manifestExchange),
                body: Data("{}".utf8),
                nonce: "nonce-shadow"
            )
        )
        let result = CanonicalShadowTransportProbe().projectReadOnly(
            signedRequest: signed,
            route: .syncInventory,
            policy: .enabled()
        )

        #expect(result.routeStatus == .allowedReadOnly)
        #expect(result.sentNetwork == false)
        #expect(result.failure == .networkSuppressed)
        #expect(result.authBoundaryPreserved)
        #expect(result.audit.requestSuppressed)
    }
}
