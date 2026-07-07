//
//  CanonicalLiveReadOnlyTransportProbeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalLiveReadOnlyTransportProbeTests {
    @Test func liveProbePolicyIsDisabledByDefault() {
        let policy = CanonicalLiveReadOnlyTransportProbePolicy()
        let gate = CanonicalLiveReadOnlyTransportProbeGate.evaluate(policy: policy, bodyByteCount: 0)

        #expect(policy.mode == .disabled)
        #expect(gate.shouldClassify == false)
        #expect(gate.shouldBuildEnvelope == false)
        #expect(gate.shouldSend == false)
        #expect(gate.failure == .disabled)
    }

    @Test func classifyOnlyAndBuildEnvelopeOnlyDoNotSend() async throws {
        let inventory = Self.emptyInventory(deviceID: "iphone-01", platform: .iPhone)
        let classify = await IPhoneCanonicalReadOnlyTransportProbeSender().evaluateAndMaybeSend(
            settings: Self.pairedSnapshot(),
            policy: .classifyOnly(),
            localInventory: inventory,
            syncRunID: "classify-only",
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let buildOnly = await IPhoneCanonicalReadOnlyTransportProbeSender().evaluateAndMaybeSend(
            settings: Self.pairedSnapshot(),
            policy: .buildSignedEnvelopeOnly(),
            localInventory: inventory,
            syncRunID: "build-only",
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(classify.routeStatus == .allowedReadOnly)
        #expect(classify.envelopeBuilt == false)
        #expect(classify.sentNetwork == false)
        #expect(classify.failure == .networkSuppressed)
        #expect(buildOnly.envelopeBuilt)
        #expect(buildOnly.sentNetwork == false)
        #expect(buildOnly.failure == .networkSuppressed)
        #expect(buildOnly.authBoundaryPreserved)
    }

    @Test func mutatingUnknownAndArtifactRoutesAreBlockedBeforeSend() async throws {
        let inventory = Self.emptyInventory(deviceID: "iphone-01", platform: .iPhone)
        let mutating = await IPhoneCanonicalReadOnlyTransportProbeSender().evaluateAndMaybeSend(
            settings: Self.pairedSnapshot(),
            policy: .sendReadOnlyProbe(
                route: CanonicalLiveReadOnlyTransportProbeRoute(method: "POST", path: "/sync/apply"),
                internalConfigurationEnabled: true
            ),
            localInventory: inventory,
            syncRunID: "mutating",
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let unknownGate = CanonicalLiveReadOnlyTransportProbeGate.evaluate(
            policy: .sendReadOnlyProbe(
                route: CanonicalLiveReadOnlyTransportProbeRoute(method: "POST", path: "/unknown"),
                internalConfigurationEnabled: true
            ),
            bodyByteCount: 0
        )
        let artifactDefault = CanonicalLiveReadOnlyTransportProbeGate.evaluate(
            policy: .sendReadOnlyProbe(route: .artifactRequest, internalConfigurationEnabled: true),
            bodyByteCount: 2
        )
        let artifactBounded = CanonicalLiveReadOnlyTransportProbeGate.evaluate(
            policy: .sendReadOnlyProbe(route: .artifactRequest, allowBoundedArtifactFetch: true, internalConfigurationEnabled: true),
            bodyByteCount: 2
        )

        #expect(mutating.blocked)
        #expect(mutating.envelopeBuilt == false)
        #expect(mutating.sentNetwork == false)
        #expect(mutating.failure == .mutatingRouteRejected)
        #expect(unknownGate.failure == .unknownRouteRejected)
        #expect(artifactDefault.failure == .artifactFetchNotAllowed)
        #expect(artifactBounded.routeStatus == .allowedReadOnly)
    }

    @Test func signedEnvelopeUsesExistingHMACShapeAndMarkerHeaders() throws {
        let client = SecureMacUploadClient()
        let settings = Self.pairedSnapshot()
        let policy = CanonicalLiveReadOnlyTransportProbePolicy.buildSignedEnvelopeOnly(internalConfigurationEnabled: true)
        let body = LocalNetworkSyncInventoryRequest(
            deviceID: "iphone-01",
            generatedAt: Date(timeIntervalSince1970: 1_000),
            localInventoryHash: "inventory-hash",
            syncRunID: "shape-test"
        )
        let prepared = try client.prepareCanonicalLiveReadOnlyProbeRequest(
            settings: settings,
            policy: policy,
            body: body,
            syncRunID: "shape-test",
            now: Date(timeIntervalSince1970: 2_000)
        )
        let normalized = prepared.headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }
        let bodyHash = SecureUploadUtilities.sha256Hex(prepared.body)
        let payload = [
            "POST",
            "/sync/inventory",
            try #require(normalized["x-rokurics-timestamp"]),
            try #require(normalized["x-rokurics-nonce"]),
            bodyHash
        ].joined(separator: "\n")

        #expect(normalized["x-rokurics-body-sha256"] == bodyHash)
        #expect(normalized["x-rokurics-signature"] == SecureUploadUtilities.hmacSHA256Base64URL(message: payload, secretBase64URL: settings.sharedSecretBase64URL))
        #expect(normalized[CanonicalLiveReadOnlyTransportProbeHTTP.markerHeader.lowercased()] == CanonicalLiveReadOnlyTransportProbeHTTP.markerValue)
        #expect(normalized[CanonicalLiveReadOnlyTransportProbeHTTP.routeHeader.lowercased()] == "POST /sync/inventory")
    }

    @Test func performTickLiveProbeDisabledByDefaultAndBuildOnlyDoesNotChangePlan() async throws {
        let disabledHarness = try Self.makeHarness(
            peerInventory: Self.emptyInventory(deviceID: "mac-01", platform: .Mac)
        )
        defer { try? FileManager.default.removeItem(at: disabledHarness.rootURL) }
        let disabledPlan = await disabledHarness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 3_000),
            bypassBackoff: true,
            syncRunID: "live-disabled"
        )
        #expect(disabledPlan != nil)
        #expect(disabledHarness.liveProbeSender.callCount == 0)
        #expect(disabledHarness.diagnosticsStore.loadEntries().contains { $0.phase == "canonicalLiveReadOnlyProbePolicyEvaluated" } == false)

        let enabledHarness = try Self.makeHarness(
            peerInventory: Self.emptyInventory(deviceID: "mac-01", platform: .Mac),
            livePolicy: .buildSignedEnvelopeOnly(internalConfigurationEnabled: true)
        )
        defer { try? FileManager.default.removeItem(at: enabledHarness.rootURL) }
        let enabledPlan = await enabledHarness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 3_100),
            bypassBackoff: true,
            syncRunID: "live-build-only"
        )
        let entries = enabledHarness.diagnosticsStore.loadEntries()

        #expect(enabledPlan != nil)
        #expect(enabledPlan?.uploadMetadataActions.isEmpty == true)
        #expect(enabledPlan?.uploadRecordingAudioActions.isEmpty == true)
        #expect(enabledHarness.liveProbeSender.callCount == 1)
        #expect(entries.contains { $0.phase == "canonicalLiveReadOnlyProbeEnvelopeBuilt" })
        #expect(entries.contains { $0.phase == "canonicalLiveReadOnlyProbeSendStarted" } == false)
    }

    private struct Harness {
        let rootURL: URL
        let diagnosticsStore: ConnectionDiagnosticsStore
        let client: LiveProbeFakeLocalNetworkSyncClient
        let liveProbeSender: LiveProbeFakeSender
        let engine: LocalNetworkSyncEngine
    }

    private static func makeHarness(
        peerInventory: LocalNetworkSyncInventory,
        livePolicy: CanonicalLiveReadOnlyTransportProbePolicy = .disabled
    ) throws -> Harness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsLiveProbeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let audioStore = AudioFileStore(rootDirectoryURL: rootURL)
        try audioStore.ensureStorageDirectories()
        let studyStore = StudyLibraryStore(rootURL: rootURL.appendingPathComponent("Study", isDirectory: true), audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL.appendingPathComponent("Diagnostics", isDirectory: true))
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true))
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let client = LiveProbeFakeLocalNetworkSyncClient(peerInventory: peerInventory)
        let liveProbeSender = LiveProbeFakeSender()
        let engine = LocalNetworkSyncEngine(
            connectionStore: LiveProbeFakeSecureMacConnectionSnapshotProvider(snapshot: Self.pairedSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: client,
            stateStore: stateStore,
            diagnosticsStore: diagnosticsStore,
            canonicalLiveReadOnlyTransportProbePolicy: livePolicy,
            canonicalLiveReadOnlyTransportProbeSender: liveProbeSender
        )
        return Harness(rootURL: rootURL, diagnosticsStore: diagnosticsStore, client: client, liveProbeSender: liveProbeSender, engine: engine)
    }

    private static func pairedSnapshot() -> SecureMacConnectionSnapshot {
        SecureMacConnectionSnapshot(
            macHost: "127.0.0.1",
            macPort: 8787,
            macFingerprint: String(repeating: "a", count: 64),
            macName: "Rokurics Mac",
            macModel: "Mac",
            deviceID: "iphone-01",
            sharedSecretBase64URL: Data("live-probe-secret".utf8).base64URLEncodedString(),
            pairedAt: "2026-06-03T00:00:00Z"
        )
    }

    private static func emptyInventory(deviceID: String, platform: LocalNetworkSyncPlatform) -> LocalNetworkSyncInventory {
        LocalNetworkSyncInventory.make(
            device: LocalNetworkSyncDeviceSection(
                deviceID: deviceID,
                deviceName: platform.rawValue,
                platform: platform,
                generatedAt: Date(timeIntervalSince1970: 1_000),
                lastKnownPeerRevision: nil,
                appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
            )
        )
    }
}

@MainActor
private final class LiveProbeFakeSender: IPhoneCanonicalReadOnlyProbeSending {
    private(set) var callCount = 0

    func evaluateAndMaybeSend(
        settings: SecureMacConnectionSnapshot,
        policy: CanonicalLiveReadOnlyTransportProbePolicy,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String,
        generatedAt: Date
    ) async -> CanonicalLiveReadOnlyTransportProbeResult {
        callCount += 1
        return CanonicalLiveReadOnlyTransportProbeResult(
            mode: policy.mode,
            route: policy.route,
            routeStatus: .allowedReadOnly,
            envelopeBuilt: true,
            sentNetwork: false,
            completed: false,
            blocked: false,
            suppressed: true,
            authBoundaryPreserved: true,
            failure: .networkSuppressed,
            diagnostics: [
                .canonicalLiveReadOnlyProbePolicyEvaluated,
                .canonicalLiveReadOnlyProbeRouteAllowed,
                .canonicalLiveReadOnlyProbeEnvelopeBuilt,
                .canonicalLiveReadOnlyProbeSendSuppressed,
                .canonicalLiveReadOnlyProbeAuthBoundaryPreserved
            ],
            reason: "fakeBuildOnly"
        )
    }
}

private final class LiveProbeFakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding {
    let snapshot: SecureMacConnectionSnapshot

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
}

private final class LiveProbeFakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
    private let peerInventory: LocalNetworkSyncInventory

    init(peerInventory: LocalNetworkSyncInventory) {
        self.peerInventory = peerInventory
    }

    func sendDeviceStatus(settings: SecureMacConnectionSnapshot, statusRequest: DeviceStatusRequest) async throws -> DeviceStatusResponse {
        DeviceStatusResponse(ok: true, status: nil, syncState: nil, error: nil)
    }

    func fetchLocalNetworkSyncInventory(settings: SecureMacConnectionSnapshot, localInventory: LocalNetworkSyncInventory, syncRunID: String?) async throws -> LocalNetworkSyncInventoryResponse {
        LocalNetworkSyncInventoryResponse(ok: true, inventory: peerInventory, error: nil)
    }

    func sendLocalNetworkSyncStartSignal(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncStartRequest) async throws -> LocalNetworkSyncStartResponse {
        LocalNetworkSyncStartResponse(ok: true, syncRunID: request.syncRunID, peerDeviceID: request.deviceID, ackAt: Date(), disposition: "ack", error: nil)
    }

    func sendLocalNetworkSyncStartAck(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncStartAckRequest) async throws -> LocalNetworkSyncStartAckResponse {
        LocalNetworkSyncStartAckResponse(ok: true, syncRunID: request.syncRunID, peerDeviceID: request.deviceID, ackReceivedAt: Date(), error: nil)
    }

    func applyLocalNetworkSyncMetadata(settings: SecureMacConnectionSnapshot, manifest: StudyLibrarySyncManifest) async throws -> StudyLibrarySyncManifestResponse {
        StudyLibrarySyncManifestResponse(ok: true, manifest: manifest, syncState: nil, deviceStatus: nil, applyResult: nil, baseCommitID: nil, newCommitID: nil, remoteChanges: nil, rejectedChanges: nil, error: nil)
    }

    func requestLocalNetworkSyncArtifact(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactRequest) async throws -> LocalNetworkSyncArtifactResponse {
        LocalNetworkSyncArtifactResponse(ok: false, artifactID: nil, kind: nil, checksum: nil, size: nil, logicalPathToken: nil, dataBase64: nil, error: "not_implemented")
    }

    func fetchLocalNetworkSyncArtifactStatus(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactStatusRequest) async throws -> LocalNetworkSyncArtifactStatusResponse {
        LocalNetworkSyncArtifactStatusResponse(ok: false, artifactID: nil, checksum: nil, size: nil, confirmedBytes: nil, nextOffset: nil, state: nil, error: "not_implemented")
    }

    func putLocalNetworkSyncArtifact(settings: SecureMacConnectionSnapshot, request: LocalNetworkSyncArtifactPutRequest) async throws -> LocalNetworkSyncArtifactPutResponse {
        LocalNetworkSyncArtifactPutResponse(ok: false, artifactID: nil, disposition: nil, checksum: nil, size: nil, confirmedBytes: nil, error: "not_implemented")
    }
}
