//
//  CanonicalShadowSeamTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import Rokurics

@MainActor
struct CanonicalShadowSeamTests {
    @Test func performTickDefaultShadowConfigurationRecordsNoMigrationEvents() async throws {
        let harness = try makeHarness(peerInventory: emptyInventory(deviceID: "mac-01", platform: .Mac))
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 1_000),
            bypassBackoff: true,
            syncRunID: "sync-shadow-disabled"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(harness.client.inventoryRequestCount == 1)
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
        #expect(entries.contains { $0.phase == "canonicalShadowMigrationStarted" } == false)
    }

    @Test func performTickDiagnosticsOnlyRecordsShadowEventsWithoutSideEffects() async throws {
        let harness = try makeHarness(
            peerInventory: emptyInventory(deviceID: "mac-01", platform: .Mac),
            configuration: .enabled(mode: .diagnosticsOnly)
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 1_100),
            bypassBackoff: true,
            syncRunID: "sync-shadow-diagnostics"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(entries.contains { $0.phase == "canonicalShadowMigrationStarted" })
        #expect(entries.contains { $0.phase == "canonicalShadowMigrationSuppressedSideEffects" })
        #expect(entries.contains { $0.phase == "canonicalShadowMigrationCompleted" })
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    @Test func performTickDryRunCompareDoesNotChangeLegacyPlanOrExecuteTransfers() async throws {
        let peerInventory = inventoryWithCanonicalManifest(
            deviceID: "mac-01",
            platform: .Mac,
            manifest: CanonicalProductionTestFixtures.snapshot(
                node: CanonicalProductionTestFixtures.node("mac-01", platform: "Mac")
            ).manifest
        )
        let harness = try makeHarness(
            peerInventory: peerInventory,
            configuration: .enabled(mode: .dryRunCompare)
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 1_200),
            bypassBackoff: true,
            syncRunID: "sync-shadow-dry-run"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(plan?.uploadMetadataActions.isEmpty == true)
        #expect(plan?.uploadArtifactActions.isEmpty == true)
        #expect(plan?.uploadRecordingAudioActions.isEmpty == true)
        #expect(entries.contains { $0.phase == "canonicalShadowMigrationStarted" })
        #expect(entries.contains { $0.phase == "canonicalShadowMigrationCompleted" })
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    @Test func performTickExecutionShadowRecordsReportWithoutChangingLegacyPlan() async throws {
        let peerInventory = inventoryWithCanonicalManifest(
            deviceID: "mac-01",
            platform: .Mac,
            manifest: CanonicalProductionTestFixtures.snapshot(
                node: CanonicalProductionTestFixtures.node("mac-01", platform: "Mac")
            ).manifest
        )
        let harness = try makeHarness(
            peerInventory: peerInventory,
            configuration: .enabled(mode: .executionShadowDryRun)
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 1_300),
            bypassBackoff: true,
            syncRunID: "sync-execution-shadow"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(plan?.uploadMetadataActions.isEmpty == true)
        #expect(plan?.uploadArtifactActions.isEmpty == true)
        #expect(plan?.uploadRecordingAudioActions.isEmpty == true)
        #expect(entries.contains { $0.phase == "canonicalExecutionShadowStarted" })
        #expect(entries.contains { $0.phase == "canonicalExecutionShadowCompleted" })
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    @Test func performTickRecordingMetadataSingleDomainShadowRecordsDiagnosticsWithoutClientSideEffects() async throws {
        let peerInventory = inventoryWithCanonicalManifest(
            deviceID: "mac-01",
            platform: .Mac,
            manifest: CanonicalProductionTestFixtures.snapshot(
                node: CanonicalProductionTestFixtures.node("mac-01", platform: "Mac")
            ).manifest
        )
        let harness = try makeHarness(
            peerInventory: peerInventory,
            singleDomainConfiguration: .enabled(domain: .recordingMetadata, mode: .executionShadowDryRun)
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let plan = await harness.engine.performTick(
            trigger: "manual",
            now: Date(timeIntervalSince1970: 1_350),
            bypassBackoff: true,
            syncRunID: "sync-recording-metadata-shadow"
        )
        let entries = harness.diagnosticsStore.loadEntries()

        #expect(plan != nil)
        #expect(entries.contains { $0.phase == "canonicalRecordingMetadataExecutionShadowStarted" })
        #expect(entries.contains { $0.phase == "canonicalRecordingMetadataExecutionShadowBlocked" })
        #expect(entries.contains { $0.phase == "canonicalRecordingMetadataShadowProductionExecuteBlocked" })
        #expect(entries.contains { $0.phase == "canonicalExecutionShadowStarted" } == false)
        #expect(harness.client.applyMetadataCount == 0)
        #expect(harness.client.artifactRequestCount == 0)
        #expect(harness.client.artifactPutCount == 0)
    }

    private struct Harness {
        let rootURL: URL
        let diagnosticsStore: ConnectionDiagnosticsStore
        let client: SeamFakeLocalNetworkSyncClient
        let engine: LocalNetworkSyncEngine
    }

    private func makeHarness(
        peerInventory: LocalNetworkSyncInventory,
        configuration: CanonicalShadowMigrationConfiguration = .disabled,
        singleDomainConfiguration: CanonicalSingleDomainShadowConfiguration = .disabled
    ) throws -> Harness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsShadowSeamTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let audioStore = AudioFileStore(rootDirectoryURL: rootURL)
        try audioStore.ensureStorageDirectories()
        let studyStore = StudyLibraryStore(rootURL: rootURL.appendingPathComponent("Study", isDirectory: true), audioFileStore: audioStore)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL.appendingPathComponent("Diagnostics", isDirectory: true))
        let stateStore = LocalNetworkSyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true))
        let uploadJobStore = RecordingUploadJobStore(audioFileStore: audioStore)
        let client = SeamFakeLocalNetworkSyncClient(peerInventory: peerInventory)
        let engine = LocalNetworkSyncEngine(
            connectionStore: SeamFakeSecureMacConnectionSnapshotProvider(snapshot: pairedSnapshot()),
            audioFileStore: audioStore,
            studyLibraryStore: studyStore,
            uploadJobStore: uploadJobStore,
            client: client,
            stateStore: stateStore,
            diagnosticsStore: diagnosticsStore,
            canonicalShadowMigrationConfiguration: configuration,
            canonicalSingleDomainShadowConfiguration: singleDomainConfiguration
        )
        return Harness(rootURL: rootURL, diagnosticsStore: diagnosticsStore, client: client, engine: engine)
    }

    private func pairedSnapshot() -> SecureMacConnectionSnapshot {
        SecureMacConnectionSnapshot(
            macHost: "127.0.0.1",
            macPort: 8787,
            macFingerprint: String(repeating: "a", count: 64),
            macName: "Rokurics Mac",
            macModel: "Mac",
            deviceID: "mac-01",
            sharedSecretBase64URL: "c2hhZG93LXNlYW0tc2VjcmV0",
            pairedAt: "2026-06-02T00:00:00Z"
        )
    }

    private func emptyInventory(deviceID: String, platform: LocalNetworkSyncPlatform) -> LocalNetworkSyncInventory {
        LocalNetworkSyncInventory.make(device: device(deviceID: deviceID, platform: platform))
    }

    private func inventoryWithCanonicalManifest(
        deviceID: String,
        platform: LocalNetworkSyncPlatform,
        manifest: CanonicalManifest
    ) -> LocalNetworkSyncInventory {
        LocalNetworkSyncInventory.make(
            device: device(deviceID: deviceID, platform: platform),
            canonicalManifest: manifest
        )
    }

    private func device(deviceID: String, platform: LocalNetworkSyncPlatform) -> LocalNetworkSyncDeviceSection {
        LocalNetworkSyncDeviceSection(
            deviceID: deviceID,
            deviceName: platform.rawValue,
            platform: platform,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            lastKnownPeerRevision: nil,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
    }
}

@MainActor
private final class SeamFakeSecureMacConnectionSnapshotProvider: SecureMacConnectionSnapshotProviding, SecureMacConnectionIntentProviding {
    var snapshot: SecureMacConnectionSnapshot
    var userConnectionIntent: UserConnectionIntent = .wantsConnected

    init(snapshot: SecureMacConnectionSnapshot) {
        self.snapshot = snapshot
    }
}

private final class SeamFakeLocalNetworkSyncClient: LocalNetworkSyncClientProtocol {
    let peerInventory: LocalNetworkSyncInventory
    private(set) var inventoryRequestCount = 0
    private(set) var applyMetadataCount = 0
    private(set) var artifactRequestCount = 0
    private(set) var artifactPutCount = 0

    init(peerInventory: LocalNetworkSyncInventory) {
        self.peerInventory = peerInventory
    }

    func sendDeviceStatus(
        settings: SecureMacConnectionSnapshot,
        statusRequest: DeviceStatusRequest
    ) async throws -> DeviceStatusResponse {
        DeviceStatusResponse(ok: true, status: nil, syncState: nil, error: nil)
    }

    func fetchLocalNetworkSyncInventory(
        settings: SecureMacConnectionSnapshot,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String?
    ) async throws -> LocalNetworkSyncInventoryResponse {
        inventoryRequestCount += 1
        return LocalNetworkSyncInventoryResponse(ok: true, inventory: peerInventory, error: nil)
    }

    func sendLocalNetworkSyncStartSignal(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartRequest
    ) async throws -> LocalNetworkSyncStartResponse {
        LocalNetworkSyncStartResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: "mac-01",
            ackAt: Date(),
            disposition: "ack",
            error: nil
        )
    }

    func sendLocalNetworkSyncStartAck(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartAckRequest
    ) async throws -> LocalNetworkSyncStartAckResponse {
        LocalNetworkSyncStartAckResponse(
            ok: true,
            syncRunID: request.syncRunID,
            peerDeviceID: "mac-01",
            ackReceivedAt: Date(),
            error: nil
        )
    }

    func applyLocalNetworkSyncMetadata(
        settings: SecureMacConnectionSnapshot,
        manifest: StudyLibrarySyncManifest
    ) async throws -> StudyLibrarySyncManifestResponse {
        applyMetadataCount += 1
        return StudyLibrarySyncManifestResponse(
            ok: true,
            manifest: nil,
            syncState: nil,
            deviceStatus: nil,
            applyResult: StudyLibrarySyncApplyResult(),
            baseCommitID: nil,
            newCommitID: nil,
            remoteChanges: nil,
            rejectedChanges: nil,
            error: nil
        )
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactRequest
    ) async throws -> LocalNetworkSyncArtifactResponse {
        artifactRequestCount += 1
        return LocalNetworkSyncArtifactResponse(
            ok: false,
            artifactID: nil,
            kind: nil,
            checksum: nil,
            size: nil,
            logicalPathToken: nil,
            dataBase64: nil,
            error: "not_expected"
        )
    }

    func fetchLocalNetworkSyncArtifactStatus(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactStatusRequest
    ) async throws -> LocalNetworkSyncArtifactStatusResponse {
        LocalNetworkSyncArtifactStatusResponse(
            ok: true,
            artifactID: request.artifactID,
            checksum: request.checksum,
            size: request.size,
            confirmedBytes: 0,
            nextOffset: 0,
            state: .pending,
            error: nil
        )
    }

    func putLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactPutRequest
    ) async throws -> LocalNetworkSyncArtifactPutResponse {
        artifactPutCount += 1
        return LocalNetworkSyncArtifactPutResponse(
            ok: true,
            artifactID: request.artifactID,
            disposition: "acceptedNew",
            checksum: request.checksum,
            size: request.size,
            confirmedBytes: request.size,
            error: nil
        )
    }
}
