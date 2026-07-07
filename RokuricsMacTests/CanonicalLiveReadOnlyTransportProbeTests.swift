//
//  CanonicalLiveReadOnlyTransportProbeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalLiveReadOnlyTransportProbeTests {
    @Test func macLiveProbePolicyIsDisabledByDefault() {
        let policy = CanonicalLiveReadOnlyTransportProbePolicy()
        let gate = CanonicalLiveReadOnlyTransportProbeGate.evaluate(policy: policy, bodyByteCount: 0)

        #expect(policy.mode == .disabled)
        #expect(gate.shouldClassify == false)
        #expect(gate.shouldBuildEnvelope == false)
        #expect(gate.shouldSend == false)
        #expect(gate.failure == .disabled)
    }

    @Test func macClassifierRejectsMutatingAndUnknownRoutes() {
        let classifier = MacCanonicalReadOnlyProbeClassifier()
        let policy = CanonicalLiveReadOnlyTransportProbePolicy.sendReadOnlyProbe(internalConfigurationEnabled: true)
        let uploadGate = classifier.gate(
            policy: policy,
            method: "POST",
            path: "/upload-recording-audio-session/chunk",
            bodyByteCount: 16
        )
        let applyGate = classifier.gate(
            policy: policy,
            method: "POST",
            path: "/sync/apply",
            bodyByteCount: 16
        )
        let pairGate = classifier.gate(
            policy: policy,
            method: "POST",
            path: "/pair",
            bodyByteCount: 16
        )
        let unknownGate = classifier.gate(
            policy: policy,
            method: "POST",
            path: "/not-a-read-only-route",
            bodyByteCount: 16
        )

        #expect(uploadGate.blocked)
        #expect(uploadGate.failure == .mutatingRouteRejected)
        #expect(applyGate.blocked)
        #expect(applyGate.failure == .mutatingRouteRejected)
        #expect(pairGate.blocked)
        #expect(pairGate.failure == .mutatingRouteRejected)
        #expect(unknownGate.blocked)
        #expect(unknownGate.failure == .unknownRouteRejected)
    }

    @Test func markedHealthProbeDoesNotBypassRequestVerifierBoundary() {
        let device = Self.pairedDevice()
        let verifier = RequestVerifier(pairedDeviceProvider: { requestedID in
            requestedID == device.id ? device : nil
        })
        var headers = CanonicalLiveReadOnlyTransportProbeHTTP.markerHeaders(
            mode: .sendReadOnlyProbe,
            route: .health,
            syncRunID: "health"
        )
        headers["X-Rokurics-Device-ID"] = device.id
        let gate = MacCanonicalReadOnlyProbeClassifier().gate(
            policy: .sendReadOnlyProbe(route: .health, internalConfigurationEnabled: true),
            method: "GET",
            path: "/health",
            bodyByteCount: 0
        )
        let result = verifier.verify(method: "GET", path: "/health", headers: headers, body: Data())

        #expect(gate.routeStatus == .allowedReadOnly)
        guard case .rejected(let reason) = result else {
            Issue.record("expected marked GET probe to be rejected by RequestVerifier boundary")
            return
        }
        #expect(reason == "method_not_allowed")
        #expect(verifier.lastTrace?.verifierSucceeded == false)
    }

    @Test func markedSyncInventoryProbeStillPassesRequestVerifierAndNoMutationAudit() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacLiveProbeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let recordingStore = MacRecordingFileStore(rootURL: rootURL)
        let studyStore = StudyLibraryStore(rootURL: rootURL.appendingPathComponent("Study", isDirectory: true))
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL.appendingPathComponent("Connection", isDirectory: true))
        let device = Self.pairedDevice()
        let verifier = RequestVerifier(pairedDeviceProvider: { requestedID in
            requestedID == device.id ? device : nil
        })
        let body = Data(#"{"deviceID":"iphone-01","generatedAt":"2026-06-03T00:00:00Z","localInventoryHash":"hash","syncRunID":"probe"}"#.utf8)
        let now = Date(timeIntervalSince1970: 2_000)
        let headers = try Self.signedProbeHeaders(
            device: device,
            method: "POST",
            path: "/sync/inventory",
            body: body,
            timestamp: "\(now.timeIntervalSince1970)",
            nonce: "nonce-live-probe"
        )
        let gate = MacCanonicalReadOnlyProbeClassifier().gate(
            policy: .sendReadOnlyProbe(internalConfigurationEnabled: true),
            method: "POST",
            path: "/sync/inventory",
            bodyByteCount: body.count
        )
        let before = MacCanonicalReadOnlyProbeStateSnapshot.capture(
            recordingFileStore: recordingStore,
            studyLibraryStore: studyStore,
            deviceConnectionStatusStore: statusStore,
            localSyncDeviceID: "mac-01",
            manifestGeneratedAt: Date(timeIntervalSince1970: 0)
        )
        let result = verifier.verify(method: "POST", path: "/sync/inventory", headers: headers, body: body, now: now)
        let after = MacCanonicalReadOnlyProbeStateSnapshot.capture(
            recordingFileStore: recordingStore,
            studyLibraryStore: studyStore,
            deviceConnectionStatusStore: statusStore,
            localSyncDeviceID: "mac-01",
            manifestGeneratedAt: Date(timeIntervalSince1970: 0)
        )
        let audit = MacCanonicalReadOnlyTransportProbeAudit(gate: gate, before: before, after: after)

        guard case .accepted = result else {
            Issue.record("expected signed marked probe to pass RequestVerifier")
            return
        }
        #expect(verifier.lastTrace?.verifierSucceeded == true)
        #expect(verifier.lastTrace?.markDeviceSeenCalled == true)
        #expect(gate.routeStatus == .allowedReadOnly)
        #expect(audit.noMutationVerified)
        #expect(audit.stateSnapshotUnavailable == false)
    }

    @Test func stateSnapshotUnavailableIsDiagnosticOnlyNotSuccess() {
        let gate = CanonicalLiveReadOnlyTransportProbeGate.evaluate(
            policy: .sendReadOnlyProbe(internalConfigurationEnabled: true),
            bodyByteCount: 2
        )
        let before = MacCanonicalReadOnlyProbeStateSnapshot(
            receiveRecordCount: 0,
            uploadSessionCount: nil,
            pendingSyncRequestCount: 0,
            studyManifestChecksum: "manifest",
            unavailableReasons: ["uploadSessionCount"]
        )
        let after = MacCanonicalReadOnlyProbeStateSnapshot(
            receiveRecordCount: 0,
            uploadSessionCount: nil,
            pendingSyncRequestCount: 0,
            studyManifestChecksum: "manifest",
            unavailableReasons: ["uploadSessionCount"]
        )
        let audit = MacCanonicalReadOnlyTransportProbeAudit(gate: gate, before: before, after: after)

        #expect(audit.noMutationVerified == false)
        #expect(audit.stateSnapshotUnavailable)
        #expect(audit.diagnosticsSummary.contains("unavailable=uploadSessionCount"))
    }

    private static func pairedDevice() -> PairedDevice {
        PairedDevice(
            id: "iphone-01",
            deviceName: "iPhone",
            sharedSecretBase64URL: Data("live-probe-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil,
            userConnectionIntent: .wantsConnected
        )
    }

    private static func signedProbeHeaders(
        device: PairedDevice,
        method: String,
        path: String,
        body: Data,
        timestamp: String,
        nonce: String
    ) throws -> [String: String] {
        let bodyHash = MacSecurityUtilities.sha256Hex(body)
        let payload = [
            method,
            path,
            timestamp,
            nonce,
            bodyHash
        ].joined(separator: "\n")
        let signature = try #require(MacSecurityUtilities.hmacSHA256Base64URL(
            message: payload,
            secretBase64URL: device.sharedSecretBase64URL
        ))
        var headers = [
            "Content-Type": "application/json",
            "X-Rokurics-Device-ID": device.id,
            "X-Rokurics-Timestamp": timestamp,
            "X-Rokurics-Nonce": nonce,
            "X-Rokurics-Body-SHA256": bodyHash,
            "X-Rokurics-Signature": signature
        ]
        CanonicalLiveReadOnlyTransportProbeHTTP.markerHeaders(
            mode: .sendReadOnlyProbe,
            route: .syncInventory,
            syncRunID: "probe"
        ).forEach { key, value in
            headers[key] = value
        }
        return headers
    }
}
