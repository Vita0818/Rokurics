//
//  CanonicalReadOnlyTransportProbeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalReadOnlyTransportProbeTests {
    @Test func defaultDisabledProbeSuppressesReadOnlyRequest() {
        let request = MacCanonicalShadowTransportPort().buildReadOnlyProbeRequest(
            route: .fingerprint,
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

    @Test func artifactRequestRequiresExplicitBoundedPolicy() {
        let request = MacCanonicalShadowTransportPort().buildReadOnlyProbeRequest(
            route: .artifactRequest,
            body: Data("{}".utf8),
            manifestHashPresent: true
        )
        let rejected = CanonicalReadOnlyTransportProbe().evaluate(
            request: request,
            policy: .enabled()
        )
        #expect(rejected.status == "blocked")
        #expect(rejected.failure == .artifactFetchNotAllowed)
        #expect(rejected.sentNetwork == false)

        let allowed = CanonicalReadOnlyTransportProbe().evaluate(
            request: request,
            policy: .enabled(allowBoundedArtifactFetch: true)
        )
        #expect(allowed.routeStatus == .allowedReadOnly)
        #expect(allowed.status == "suppressed")
        #expect(allowed.failure == .networkSuppressed)
        #expect(allowed.sentNetwork == false)
        #expect(allowed.authBoundaryPreserved)
    }

    @Test func mutatingUploadRouteAndMissingAuthBoundaryAreBlocked() {
        let mutating = CanonicalReadOnlyTransportProbeRequest(
            route: CanonicalReadOnlyTransportProbeRoute(method: "POST", path: "/upload-recording-audio-session/chunk"),
            bodyByteCount: 5,
            bodyHash: CanonicalTransportEnvelope.hash(Data("chunk".utf8))
        )
        let mutatingResult = CanonicalReadOnlyTransportProbe().evaluate(
            request: mutating,
            policy: .enabled()
        )
        #expect(mutatingResult.status == "blocked")
        #expect(mutatingResult.routeStatus == .rejectedMutating)
        #expect(mutatingResult.sentNetwork == false)
        #expect(mutatingResult.failure == .mutatingRouteRejected)

        let missingAuth = CanonicalReadOnlyTransportProbeRequest(
            route: .syncInventory,
            bodyByteCount: 2,
            bodyHash: CanonicalTransportEnvelope.hash(Data("{}".utf8)),
            hmacPreserved: false
        )
        let missingAuthResult = CanonicalReadOnlyTransportProbe().evaluate(
            request: missingAuth,
            policy: .enabled()
        )
        #expect(missingAuthResult.status == "blocked")
        #expect(missingAuthResult.failure == .authBoundaryMissing)
        #expect(missingAuthResult.authBoundaryPreserved == false)
        #expect(missingAuthResult.sentNetwork == false)
    }

    @Test func macSignedShadowRequestProjectsToReadOnlyProbeWithoutSendingNetwork() async throws {
        let port = MacCanonicalShadowTransportPort()
        let signed = try await port.buildSignedRequest(
            CanonicalProductionTransportBuildRequest(
                source: CanonicalProductionTestFixtures.node("mac-01", platform: "Mac"),
                destination: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"),
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
