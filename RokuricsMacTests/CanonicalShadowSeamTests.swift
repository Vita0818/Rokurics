//
//  CanonicalShadowSeamTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct CanonicalShadowSeamTests {
    @Test func macInventoryDefaultShadowConfigurationRecordsNoMigrationEvents() async throws {
        let harness = try makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            pairedDevice(),
            syncRunID: "mac-shadow-disabled"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory != nil)
        #expect(events.contains { $0.phase == "canonicalShadowMigrationStarted" } == false)
    }

    @Test func macInventoryDiagnosticsOnlyRecordsShadowEventsAndStillReturnsInventory() async throws {
        let harness = try makeHarness(configuration: .enabled(mode: .diagnosticsOnly))
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            pairedDevice(),
            syncRunID: "mac-shadow-diagnostics"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(events.contains { $0.phase == "canonicalShadowMigrationStarted" })
        #expect(events.contains { $0.phase == "canonicalShadowMigrationSuppressedSideEffects" })
        #expect(events.contains { $0.phase == "canonicalShadowMigrationCompleted" })
    }

    @Test func macInventoryDryRunCompareRecordsMissingPeerSnapshotAsNonFatal() async throws {
        let harness = try makeHarness(configuration: .enabled(mode: .dryRunCompare))
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            pairedDevice(),
            syncRunID: "mac-shadow-dry-run"
        )
        let events = harness.recorder.snapshot()
        let blockedEvent = events.first { $0.phase == "canonicalShadowMigrationBlocked" }

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(blockedEvent?.errorMessage?.contains("insufficientPeerSnapshot") == true)
        #expect(events.contains { $0.phase == "canonicalShadowMigrationCompleted" } == false)
    }

    @Test func macInventoryExecutionShadowRecordsReportAndStillReturnsSameResponseShape() async throws {
        let harness = try makeHarness(configuration: .enabled(mode: .executionShadowDryRun))
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            pairedDevice(),
            syncRunID: "mac-execution-shadow"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(events.contains { $0.phase == "canonicalExecutionShadowStarted" })
        #expect(events.contains { $0.phase == "canonicalExecutionShadowBlocked" })
        #expect(events.contains { $0.phase == "canonicalExecutionShadowCompleted" } == false)
    }

    @Test func macInventoryRecordingMetadataSingleDomainShadowReportsMissingPeerSnapshot() async throws {
        let harness = try makeHarness(
            singleDomainConfiguration: .enabled(domain: .recordingMetadata, mode: .executionShadowDryRun)
        )
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let response = await harness.server.localNetworkSyncInventoryResponseForVerifiedDevice(
            pairedDevice(),
            syncRunID: "mac-recording-metadata-shadow"
        )
        let events = harness.recorder.snapshot()

        #expect(response.ok)
        #expect(response.inventory?.canonicalManifest != nil)
        #expect(events.contains { $0.phase == "canonicalRecordingMetadataExecutionShadowStarted" })
        #expect(events.contains { $0.phase == "canonicalRecordingMetadataExecutionShadowBlocked" })
        #expect(events.first { $0.phase == "canonicalRecordingMetadataExecutionShadowBlocked" }?.errorMessage?.contains("insufficientPeerSnapshot") == true)
        #expect(events.contains { $0.phase == "canonicalExecutionShadowStarted" } == false)
    }

    private struct Harness {
        let rootURL: URL
        let server: SecureLocalHTTPSServer
        let recorder: ShadowSeamDiagnosticRecorder
    }

    private func makeHarness(
        configuration: CanonicalShadowMigrationConfiguration = .disabled,
        singleDomainConfiguration: CanonicalSingleDomainShadowConfiguration = .disabled
    ) throws -> Harness {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacShadowSeamTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let recorder = ShadowSeamDiagnosticRecorder()
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Recordings", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: MacIdentityManager(securityDirectoryURL: securityURL, tlsKeyTagNamespace: "shadow-seam-\(UUID().uuidString)"),
            pairingManager: PairingManager(pairedDeviceStore: pairedDeviceStore),
            requestVerifier: RequestVerifier(pairedDeviceStore: pairedDeviceStore),
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingFileStore,
            studyLibraryStore: studyLibraryStore,
            gitBackedStudyMetadataStore: nil,
            deviceConnectionStatusStore: DeviceConnectionStatusStore(rootURL: rootURL.appendingPathComponent("ConnectionStatus", isDirectory: true)),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL.appendingPathComponent("SyncState", isDirectory: true)),
            onReady: {},
            onFailed: { _ in },
            onPairingChanged: {},
            onUploadAccepted: { _ in },
            onRecordingAccepted: { _, _ in },
            onConnectionDiagnostic: { recorder.record($0) },
            canonicalShadowMigrationConfiguration: configuration,
            canonicalSingleDomainShadowConfiguration: singleDomainConfiguration,
            canonicalKernelMode: .canonicalShadow
        )
        return Harness(rootURL: rootURL, server: server, recorder: recorder)
    }

    private func pairedDevice() -> PairedDevice {
        PairedDevice(
            id: "iphone-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: Data("shadow-seam-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
    }
}

private final class ShadowSeamDiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SecureConnectionDiagnosticEvent] = []

    func record(_ event: SecureConnectionDiagnosticEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [SecureConnectionDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
