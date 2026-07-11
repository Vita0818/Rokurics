//
//  RokuricsMacTests.swift
//  RokuricsMacTests
//
//  Created by Vita on 2026/5/10.
//

import Foundation
import Network
import Security
import Testing
@testable import RokuricsMac

struct RokuricsMacTests {
    @Test func iPhoneConnectionCardLayoutKeepsStableWidthAcrossSidebarChanges() {
        #expect(MacIPhoneConnectionCardLayout.cardMaxWidth(isSidebarCollapsed: false) == MacIPhoneConnectionCardLayout.stableMaxWidth)
        #expect(MacIPhoneConnectionCardLayout.cardMaxWidth(isSidebarCollapsed: true) == MacIPhoneConnectionCardLayout.stableMaxWidth)
        #expect(MacIPhoneConnectionCardLayout.cardMaxWidth(isSidebarCollapsed: false) == MacIPhoneConnectionCardLayout.cardMaxWidth(isSidebarCollapsed: true))
        #expect(MacIPhoneConnectionCardLayout.isCentered(isSidebarCollapsed: false))
        #expect(MacIPhoneConnectionCardLayout.isCentered(isSidebarCollapsed: true))
        #expect(MacIPhoneConnectionCardLayout.disablesWidthAnimation)
    }

    @Test func receiverPortPersistenceKeepsDynamicPairingPortAcrossLaunches() throws {
        let suiteName = "RokuricsMacTests.ReceiverPort.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(MacAppStorageProfile.persistedReceiverPort(userDefaults: defaults) == nil)
        MacAppStorageProfile.persistReceiverPort(8_788, userDefaults: defaults)
        #expect(MacAppStorageProfile.persistedReceiverPort(userDefaults: defaults) == 8_788)

        MacAppStorageProfile.persistReceiverPort(0, userDefaults: defaults)
        #expect(MacAppStorageProfile.persistedReceiverPort(userDefaults: defaults) == 8_788)
    }

    @MainActor
    @Test func manualStudyLibrarySyncPendingLifecyclePublishesVisibleStatuses() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-manual-sync-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = DeviceConnectionStatusStore(
            rootURL: rootURL,
            pendingSyncRequestTimeout: 1
        )
        let deviceID = "iphone-manual-sync"
        let requestedAt = Date(timeIntervalSince1970: 1_000)

        let requested = store.recordPendingSyncRequest(
            deviceID: deviceID,
            displayName: "iPhone",
            statusText: "等待 iPhone 执行同步",
            syncRunID: "sync-1",
            initiatorDeviceID: "mac-local",
            at: requestedAt
        )
        #expect(requested.lastSyncStatus == "等待 iPhone 执行同步")
        #expect(store.statusesByDeviceID[deviceID]?.lastSyncStatus == "等待 iPhone 执行同步")
        #expect(store.pendingSyncRequestCountForDiagnostics == 1)

        let duplicate = store.recordPendingSyncRequest(
            deviceID: deviceID,
            displayName: "iPhone",
            statusText: "等待 iPhone 执行同步",
            syncRunID: "sync-duplicate",
            initiatorDeviceID: "mac-local",
            at: requestedAt.addingTimeInterval(0.5)
        )
        #expect(duplicate.lastSyncStatus == "已请求，等待 iPhone 前台响应")
        #expect(store.pendingSyncRequestCountForDiagnostics == 1)
        let duplicateDetails = store.recordPendingSyncRequestDetails(
            deviceID: deviceID,
            displayName: "iPhone",
            statusText: "等待 iPhone 执行同步",
            syncRunID: "sync-duplicate-2",
            initiatorDeviceID: "mac-local",
            at: requestedAt.addingTimeInterval(0.6)
        )
        #expect(duplicateDetails.isDuplicate)
        #expect(duplicateDetails.signal.syncRunID == "sync-1")

        let signal = try #require(store.consumePendingSyncStartSignal(deviceID: deviceID))
        #expect(signal.syncRunID == "sync-1")
        #expect(store.statusesByDeviceID[deviceID]?.lastSyncStatus == "iPhone 已收到同步请求")
        #expect(store.pendingSyncRequestCountForDiagnostics == 0)

        _ = store.recordPendingSyncRequest(
            deviceID: deviceID,
            displayName: "iPhone",
            statusText: "等待 iPhone 执行同步",
            syncRunID: "sync-2",
            initiatorDeviceID: "mac-local",
            at: requestedAt.addingTimeInterval(2)
        )
        let observed = store.recordPendingSyncInventoryObserved(
            deviceID: deviceID,
            displayName: "iPhone",
            syncRunID: "sync-2",
            at: requestedAt.addingTimeInterval(2.2)
        )
        #expect(observed.lastSyncStatus == "iPhone 已开始同步")
        #expect(store.pendingSyncRequestCountForDiagnostics == 1)
        #expect(store.pendingSyncStartSignal(deviceID: deviceID)?.syncRunID == "sync-2")
        let reloadedStore = DeviceConnectionStatusStore(
            rootURL: rootURL,
            pendingSyncRequestTimeout: 1
        )
        #expect(reloadedStore.pendingSyncStartSignal(deviceID: deviceID)?.syncRunID == "sync-2")
        #expect(reloadedStore.acknowledgePendingSyncStartSignal(deviceID: deviceID, syncRunID: "sync-2"))
        #expect(reloadedStore.pendingSyncRequestCountForDiagnostics == 0)

        _ = store.recordPendingSyncRequest(
            deviceID: deviceID,
            displayName: "iPhone",
            statusText: "等待 iPhone 执行同步",
            syncRunID: "sync-timeout",
            initiatorDeviceID: "mac-local",
            at: requestedAt.addingTimeInterval(10)
        )
        let timedOut = try #require(store.status(for: deviceID, now: requestedAt.addingTimeInterval(12)))
        #expect(timedOut.lastSyncStatus == "等待 iPhone 前台响应超时")
        #expect(timedOut.lastErrorCode == "manual_sync_pending_timed_out")
        #expect(store.pendingSyncRequestCountForDiagnostics == 0)
    }

    @MainActor
    @Test func macSyncControlPlaneSupersedesFreshRunsAndRejectsStaleUpdates() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-control-plane-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(
            rootURL: rootURL,
            controlPlaneInactivityTimeout: 30
        )
        let startedAt = Date(timeIntervalSince1970: 2_000)

        #expect(store.recordControlPlane(
            deviceID: "iphone-control-plane",
            syncRunID: "old-run",
            state: .inventoryExchanging,
            at: startedAt
        ))
        #expect(!store.recordControlPlane(
            deviceID: "iphone-control-plane",
            syncRunID: "old-run",
            state: .syncStartSignalSent,
            at: startedAt.addingTimeInterval(1)
        ))
        #expect(store.state.activeSyncRunID == "old-run")
        #expect(store.state.syncControlPlaneState == .inventoryExchanging)

        #expect(store.recordControlPlane(
            deviceID: "iphone-control-plane",
            syncRunID: "new-start-run",
            state: .syncStartSignalSent,
            at: startedAt.addingTimeInterval(2)
        ))
        #expect(store.state.activeSyncRunID == "new-start-run")
        #expect(store.state.syncControlPlaneState == .syncStartSignalSent)

        #expect(store.recordControlPlane(
            deviceID: "iphone-control-plane",
            syncRunID: "new-inventory-run",
            state: .inventoryExchanging,
            at: startedAt.addingTimeInterval(3)
        ))
        #expect(store.state.activeSyncRunID == "new-inventory-run")
        #expect(store.state.syncControlPlaneState == .inventoryExchanging)

        #expect(!store.recordControlPlane(
            deviceID: "iphone-control-plane",
            syncRunID: "new-inventory-run",
            state: .syncStartAcked,
            at: startedAt.addingTimeInterval(4)
        ))
        #expect(!store.recordControlPlane(
            deviceID: "iphone-control-plane",
            syncRunID: "old-run",
            state: .planningTransfers,
            at: startedAt.addingTimeInterval(5)
        ))
        #expect(!store.recordControlPlane(
            deviceID: "iphone-control-plane",
            syncRunID: "old-run",
            state: .completed,
            at: startedAt.addingTimeInterval(6)
        ))
        #expect(!store.recordControlPlane(
            deviceID: "iphone-control-plane",
            syncRunID: "new-start-run",
            state: .failed,
            at: startedAt.addingTimeInterval(7)
        ))
        #expect(!store.recordPush(
            deviceID: "iphone-control-plane",
            remoteManifestHash: "stale-hash",
            remoteCommitID: "stale-commit",
            syncRunID: "old-run",
            at: startedAt.addingTimeInterval(8)
        ))
        #expect(!store.recordFailure(
            deviceID: "iphone-control-plane",
            error: "unrelated failure",
            syncRunID: "never-active-run"
        ))

        #expect(store.state.activeSyncRunID == "new-inventory-run")
        #expect(store.state.syncControlPlaneState == .inventoryExchanging)
        #expect(store.state.lastSuccessfulSyncAt == nil)
        #expect(store.state.lastRemoteManifestHash == nil)
        #expect(store.state.lastError == nil)
    }

    @MainActor
    @Test func macSyncControlPlaneWatchdogExpiresStartAckWithoutNextRequest() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-control-plane-watchdog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(
            rootURL: rootURL,
            controlPlaneInactivityTimeout: 0.02
        )

        store.recordControlPlane(
            deviceID: "iphone-control-plane",
            syncRunID: "sync-start-ack",
            state: .syncStartAcked
        )

        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline,
              store.state.syncControlPlaneState != .failed {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(store.state.activeSyncRunID == "sync-start-ack")
        #expect(store.state.syncControlPlaneState == .failed)
        #expect(store.state.lastError == "sync_control_plane_timeout")
    }

    @MainActor
    @Test func metadataApplyLeaseBlocksSupersessionUntilPostconditionCheck() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-apply-lease-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(rootURL: rootURL)

        #expect(store.recordControlPlane(
            deviceID: "iphone-apply-lease",
            syncRunID: "apply-run",
            state: .inventoryExchanging
        ))
        let lease = try #require(store.beginMetadataApplyLease(
            deviceID: "iphone-apply-lease",
            syncRunID: "apply-run"
        ))

        #expect(store.state.activeSyncRunID == "apply-run")
        #expect(store.state.syncControlPlaneState == .transferring)
        #expect(store.isMetadataApplyLeaseValid(lease, syncRunID: "apply-run"))
        #expect(!store.recordControlPlane(
            deviceID: "iphone-apply-lease",
            syncRunID: "superseding-run",
            state: .inventoryExchanging
        ))
        #expect(!store.recordPush(
            deviceID: "iphone-apply-lease",
            remoteManifestHash: "premature-terminal",
            syncRunID: "apply-run"
        ))

        store.endMetadataApplyLease(lease)
        #expect(store.recordControlPlane(
            deviceID: "iphone-apply-lease",
            syncRunID: "superseding-run",
            state: .inventoryExchanging
        ))
        #expect(!store.isMetadataApplyLeaseValid(lease, syncRunID: "apply-run"))

        let supersedingLease = try #require(store.beginMetadataApplyLease(
            deviceID: "iphone-apply-lease",
            syncRunID: "superseding-run"
        ))
        store.replace(StudyLibrarySyncState(
            deviceID: "iphone-apply-lease",
            activeSyncRunID: "externally-replaced-run",
            syncControlPlaneState: .inventoryExchanging,
            syncControlPlaneUpdatedAt: Date()
        ))
        #expect(!store.isMetadataApplyLeaseValid(
            supersedingLease,
            syncRunID: "superseding-run"
        ))
        store.endMetadataApplyLease(supersedingLease)
    }

    @MainActor
    @Test func metadataApplyLeaseSuppressesWatchdogUntilApplyFinishes() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-apply-lease-watchdog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(
            rootURL: rootURL,
            controlPlaneInactivityTimeout: 0.02
        )

        #expect(store.recordControlPlane(
            deviceID: "iphone-apply-lease-watchdog",
            syncRunID: "long-apply-run",
            state: .inventoryExchanging
        ))
        let lease = try #require(store.beginMetadataApplyLease(
            deviceID: "iphone-apply-lease-watchdog",
            syncRunID: "long-apply-run"
        ))

        try? await Task.sleep(nanoseconds: 80_000_000)

        #expect(store.state.syncControlPlaneState == .transferring)
        #expect(store.state.lastError == nil)
        #expect(store.isMetadataApplyLeaseValid(lease, syncRunID: "long-apply-run"))

        store.endMetadataApplyLease(lease)
        #expect(store.state.syncControlPlaneState == .transferring)
        #expect(store.recordPush(
            deviceID: "iphone-apply-lease-watchdog",
            remoteManifestHash: "long-apply-hash",
            syncRunID: "long-apply-run"
        ))
        #expect(store.state.syncControlPlaneState == .completed)
    }

    @MainActor
    @Test func syncControlPlaneKeepsFirstTerminalStateForCorrelatedRun() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-first-terminal-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = StudyLibrarySyncStateStore(rootURL: rootURL)
        let completedAt = Date(timeIntervalSince1970: 2_050)

        #expect(store.recordControlPlane(
            deviceID: "iphone-first-terminal",
            syncRunID: "terminal-run",
            state: .transferring
        ))
        #expect(store.recordPush(
            deviceID: "iphone-first-terminal",
            remoteManifestHash: "terminal-hash",
            syncRunID: "terminal-run",
            at: completedAt
        ))
        #expect(!store.recordFailure(
            deviceID: "iphone-first-terminal",
            error: "late-failure",
            syncRunID: "terminal-run",
            at: completedAt.addingTimeInterval(1)
        ))
        #expect(!store.recordControlPlane(
            deviceID: "iphone-first-terminal",
            syncRunID: "terminal-run",
            state: .cancelled,
            at: completedAt.addingTimeInterval(2)
        ))

        #expect(store.state.activeSyncRunID == "terminal-run")
        #expect(store.state.syncControlPlaneState == .completed)
        #expect(store.state.lastSuccessfulSyncAt == completedAt)
        #expect(store.state.lastError == nil)
    }

    @MainActor
    @Test func syncRunCorrelatedRequestsCodableRoundTrip() throws {
        let timestamp = Date(timeIntervalSince1970: 2_100)
        let heartbeatRequest = ConnectionHeartbeatRequest(
            deviceID: "iphone-run-roundtrip",
            deviceName: "Run iPhone",
            platform: .iPhone,
            appInstanceID: "run-roundtrip-instance",
            sequenceNumber: 9,
            sentAt: timestamp,
            lastKnownPeerStatusRevision: 4,
            syncRunStatus: LocalNetworkSyncRunStatus(
                syncRunID: "heartbeat-run-roundtrip",
                state: .completed,
                updatedAt: timestamp,
                errorCode: nil
            )
        )
        let manifestRequest = StudyLibrarySyncManifestRequest(
            manifest: StudyLibrarySyncManifest.make(
                deviceID: heartbeatRequest.deviceID,
                generatedAt: timestamp,
                items: [],
                folders: []
            ),
            syncRunID: "manifest-run-roundtrip"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decodedHeartbeat = try decoder.decode(
            ConnectionHeartbeatRequest.self,
            from: encoder.encode(heartbeatRequest)
        )
        let decodedManifest = try decoder.decode(
            StudyLibrarySyncManifestRequest.self,
            from: encoder.encode(manifestRequest)
        )

        #expect(decodedHeartbeat == heartbeatRequest)
        #expect(decodedHeartbeat.syncRunStatus?.syncRunID == "heartbeat-run-roundtrip")
        #expect(decodedHeartbeat.syncRunStatus?.state == .completed)
        #expect(decodedManifest == manifestRequest)
        #expect(decodedManifest.syncRunID == "manifest-run-roundtrip")
    }

    @MainActor
    @Test func macServerHeartbeatAcceptsMatchingTerminalRunAndRejectsSupersededRun() async throws {
        let fileManager = FileManager.default
        let rootURL = try makeScratchDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let identityManager = MacIdentityManager(
            securityDirectoryURL: securityURL,
            tlsKeyTagNamespace: "heartbeat-run-status-\(UUID().uuidString)"
        )
        identityManager.loadOrCreateIdentity()
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let device = makeHeartbeatDevice()
        pairedDeviceStore.upsert(device)
        let pairingManager = PairingManager(pairedDeviceStore: pairedDeviceStore)
        let recordingFileStore = MacRecordingFileStore(
            rootURL: rootURL.appendingPathComponent("Library", isDirectory: true)
        )
        let studyLibraryStore = StudyLibraryStore(
            rootURL: recordingFileStore.libraryRootURL,
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let readySignal = ListenerReadySignal()
        let diagnosticRecorder = SecureConnectionDiagnosticRecorder()
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: identityManager,
            pairingManager: pairingManager,
            requestVerifier: RequestVerifier(pairedDeviceStore: pairedDeviceStore),
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingFileStore,
            studyLibraryStore: studyLibraryStore,
            gitBackedStudyMetadataStore: nil,
            deviceConnectionStatusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            syncStateStore: syncStateStore,
            onReady: { readySignal.markReady() },
            onFailed: { readySignal.markFailed($0.message) },
            onPairingChanged: {},
            onUploadAccepted: { _ in },
            onRecordingAccepted: { _, _ in },
            onConnectionDiagnostic: { diagnosticRecorder.record($0) }
        )
        defer { server.stop() }

        try server.start()
        try await waitForListenerReady(readySignal)
        let activePort = try #require(server.activePort)
        let client = RealListenerPinnedHTTPSClient(
            expectedFingerprint: identityManager.status.certificateFingerprint
        )
        defer { client.invalidate() }

        let matchingRunID = "heartbeat-matching-run"
        #expect(syncStateStore.recordControlPlane(
            deviceID: device.id,
            syncRunID: matchingRunID,
            state: .transferring
        ))
        let applyEncoder = JSONEncoder()
        applyEncoder.dateEncodingStrategy = .iso8601
        applyEncoder.outputFormatting = [.sortedKeys]
        let matchingApplyBody = try applyEncoder.encode(StudyLibrarySyncManifestRequest(
            manifest: StudyLibrarySyncManifest.make(
                deviceID: device.id,
                generatedAt: Date(timeIntervalSince1970: 2_190),
                items: [],
                folders: []
            ),
            syncRunID: matchingRunID
        ))
        let matchingApplyResponse = try await client.postData(
            port: activePort,
            path: "/sync/apply-metadata",
            headers: try signedJSONHeaders(
                device: device,
                path: "/sync/apply-metadata",
                body: matchingApplyBody,
                nonce: "heartbeat-run-matching-apply"
            ),
            body: matchingApplyBody
        )
        let decodedMatchingApply = try Self.connectionJSONDecoder.decode(
            StudyLibrarySyncManifestResponse.self,
            from: matchingApplyResponse.body
        )

        #expect(matchingApplyResponse.statusCode == 200)
        #expect(decodedMatchingApply.ok)
        #expect(syncStateStore.state.activeSyncRunID == matchingRunID)
        #expect(syncStateStore.state.syncControlPlaneState == .transferring)
        #expect(syncStateStore.state.lastSuccessfulSyncAt == nil)

        var completedHeartbeat = makeHeartbeatRequest(device: device, sequenceNumber: 1)
        completedHeartbeat.syncRunStatus = LocalNetworkSyncRunStatus(
            syncRunID: matchingRunID,
            state: .completed,
            updatedAt: Date(timeIntervalSince1970: 2_200),
            errorCode: nil
        )
        let completedBody = try encodedHeartbeatRequest(completedHeartbeat)
        let completedResponse = try await client.postData(
            port: activePort,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: device,
                path: "/connection/heartbeat",
                body: completedBody,
                nonce: "heartbeat-run-completed"
            ),
            body: completedBody
        )

        #expect(completedResponse.statusCode == 200)
        #expect(syncStateStore.state.activeSyncRunID == matchingRunID)
        #expect(syncStateStore.state.syncControlPlaneState == .completed)
        let completedAt = try #require(syncStateStore.state.lastSuccessfulSyncAt)

        var lateTerminalHeartbeat = makeHeartbeatRequest(device: device, sequenceNumber: 2)
        lateTerminalHeartbeat.syncRunStatus = LocalNetworkSyncRunStatus(
            syncRunID: matchingRunID,
            state: .failed,
            updatedAt: Date(timeIntervalSince1970: 2_200),
            errorCode: "late_same_run_failure"
        )
        let lateTerminalBody = try encodedHeartbeatRequest(lateTerminalHeartbeat)
        let lateTerminalResponse = try await client.postData(
            port: activePort,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: device,
                path: "/connection/heartbeat",
                body: lateTerminalBody,
                nonce: "heartbeat-run-late-terminal"
            ),
            body: lateTerminalBody
        )

        #expect(lateTerminalResponse.statusCode == 200)
        #expect(syncStateStore.state.syncControlPlaneState == .completed)
        #expect(syncStateStore.state.lastSuccessfulSyncAt == completedAt)
        #expect(syncStateStore.state.lastError == nil)

        let newerRunID = "heartbeat-newer-run"
        #expect(syncStateStore.recordControlPlane(
            deviceID: device.id,
            syncRunID: newerRunID,
            state: .inventoryExchanging
        ))
        var staleHeartbeat = makeHeartbeatRequest(device: device, sequenceNumber: 3)
        staleHeartbeat.syncRunStatus = LocalNetworkSyncRunStatus(
            syncRunID: matchingRunID,
            state: .failed,
            updatedAt: Date(timeIntervalSince1970: 2_201),
            errorCode: "stale_peer_failure"
        )
        let staleBody = try encodedHeartbeatRequest(staleHeartbeat)
        let staleResponse = try await client.postData(
            port: activePort,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: device,
                path: "/connection/heartbeat",
                body: staleBody,
                nonce: "heartbeat-run-stale"
            ),
            body: staleBody
        )

        #expect(staleResponse.statusCode == 200)
        #expect(syncStateStore.state.activeSyncRunID == newerRunID)
        #expect(syncStateStore.state.syncControlPlaneState == .inventoryExchanging)
        #expect(syncStateStore.state.lastSuccessfulSyncAt == completedAt)
        #expect(syncStateStore.state.lastError == nil)
        let runEvents = diagnosticRecorder.snapshot().filter {
            $0.phase == "peerSyncRunStatusAccepted" || $0.phase == "peerSyncRunStatusRejected"
        }
        #expect(runEvents.contains {
            $0.phase == "peerSyncRunStatusAccepted" && $0.syncRunID == matchingRunID
        })
        #expect(runEvents.contains {
            $0.phase == "peerSyncRunStatusRejected"
                && $0.syncRunID == matchingRunID
                && $0.errorCode == "stale_sync_run"
        })

        let staleRunItem = StudyItemMetadata(
            recordingID: "stale-run-must-not-write",
            title: "Stale run metadata",
            createdAt: Date(timeIntervalSince1970: 2_201),
            duration: 1,
            updatedAt: Date(timeIntervalSince1970: 2_202),
            modifiedByDeviceID: device.id
        )
        let staleApplyBody = try applyEncoder.encode(StudyLibrarySyncManifestRequest(
            manifest: StudyLibrarySyncManifest.make(
                deviceID: device.id,
                generatedAt: Date(timeIntervalSince1970: 2_202),
                items: [staleRunItem],
                folders: []
            ),
            syncRunID: matchingRunID
        ))
        let staleApplyResponse = try await server.localNetworkSyncApplyMetadataResponseForVerifiedDevice(
            device,
            requestBody: staleApplyBody
        )

        #expect(!staleApplyResponse.ok)
        #expect(staleApplyResponse.error == "stale_sync_run")
        #expect(syncStateStore.state.activeSyncRunID == newerRunID)
        #expect(syncStateStore.state.syncControlPlaneState == .inventoryExchanging)
        #expect(studyLibraryStore.item(recordingID: staleRunItem.recordingID ?? "") == nil)

        let malformedApplyBody = Data("{}".utf8)
        let malformedApplyResponse = try await client.postData(
            port: activePort,
            path: "/sync/apply-metadata",
            headers: try signedJSONHeaders(
                device: device,
                path: "/sync/apply-metadata",
                body: malformedApplyBody,
                nonce: "heartbeat-run-malformed-apply"
            ),
            body: malformedApplyBody
        )

        #expect(malformedApplyResponse.statusCode == 400)
        #expect(syncStateStore.state.activeSyncRunID == newerRunID)
        #expect(syncStateStore.state.syncControlPlaneState == .inventoryExchanging)
        #expect(syncStateStore.state.lastError == nil)

        var invalidManifest = StudyLibrarySyncManifest.make(
            deviceID: device.id,
            generatedAt: Date(timeIntervalSince1970: 2_203),
            items: [],
            folders: []
        )
        invalidManifest.checksum = "invalid-checksum"
        let invalidApplyBody = try applyEncoder.encode(StudyLibrarySyncManifestRequest(
            manifest: invalidManifest,
            syncRunID: newerRunID
        ))
        let invalidApplyResponse = try await client.postData(
            port: activePort,
            path: "/sync/apply-metadata",
            headers: try signedJSONHeaders(
                device: device,
                path: "/sync/apply-metadata",
                body: invalidApplyBody,
                nonce: "heartbeat-run-invalid-apply"
            ),
            body: invalidApplyBody
        )

        #expect(invalidApplyResponse.statusCode == 400)
        #expect(syncStateStore.state.activeSyncRunID == newerRunID)
        #expect(syncStateStore.state.syncControlPlaneState == .failed)
        #expect(syncStateStore.state.lastError?.contains("sync_manifest_checksum_mismatch") == true)
    }

    @Test func macManualSyncViewConsumesReturnedStatusWithoutReverseClient() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let viewSource = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/MacIPhoneConnectionView.swift"),
            encoding: .utf8
        )
        let serviceSource = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/SecureReceiverService.swift"),
            encoding: .utf8
        )
        let prepareRange = try #require(serviceSource.range(of: "func prepareManualStudyLibrarySync"))
        let prepareSource = String(serviceSource[prepareRange.lowerBound...])
            .components(separatedBy: "func refreshSecurityState")
            .first ?? ""

        #expect(viewSource.contains("manualSyncStatusRevision = status.connectionStatusRevision"))
        #expect(serviceSource.contains("publishManualSyncStatus(status)"))
        #expect(prepareSource.contains("recordPendingSyncRequestDetails("))
        #expect(!prepareSource.contains("URLSession"))
        #expect(!prepareSource.contains("NWConnection"))
        #expect(!prepareSource.contains(".connect("))
    }

    @Test func macSyncButtonKeepsRecentTerminalControlPlaneStatusVisible() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("RokuricsMac/MacIPhoneConnectionView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("state.isSyncProgressActive || shouldShowRecentTerminalSyncState(state)"))
        #expect(source.contains("syncControlPlaneUpdatedAt"))
        #expect(source.contains("case .completed, .failed, .cancelled:"))
    }

    @Test func failedInboxItemShowsShortTranscriptionErrorSummary() {
        let item = makeInboxItem(
            transcriptionStatus: "failed",
            transcriptionError: "ffmpeg 转码失败：exitCode=1\nstderr=invalid data"
        )

        #expect(item.failureReasonSummary == "失败原因：ffmpeg 转码失败：exitCode=1 stderr=invalid data")
    }

    @Test func failureReasonSummaryIsHiddenForSuccessfulItems() {
        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: "old error"
        )

        #expect(item.failureReasonSummary == nil)
    }

    @Test func longFailureReasonSummaryIsTruncated() {
        let summary = TranscriptionFailureReasonFormatter.summary(
            for: String(repeating: "a", count: 260),
            transcriptionStatus: "failed",
            maxCharacters: 160
        )

        #expect(summary?.hasPrefix("失败原因：") == true)
        #expect(summary?.hasSuffix("...") == true)
        #expect((summary?.count ?? 0) <= 168)
    }

    @Test func ffmpegLaunchFailureSummaryHighlightsNSErrorDetails() {
        let error = """
        ffmpeg 启动失败：
        stage=ffmpeg process launch
        configuredExecutable=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg
        authorizedExecutable=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg
        processExecutableURLPath=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg
        nsErrorDomain=NSCocoaErrorDomain
        nsErrorCode=260
        description=The file “ffmpeg” doesn’t exist.
        """

        let summary = TranscriptionFailureReasonFormatter.summary(
            for: error,
            transcriptionStatus: "failed",
            maxCharacters: 220
        )

        #expect(summary?.contains("processExecutableURL=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg") == true)
        #expect(summary?.contains("NSCocoaErrorDomain") == true)
        #expect(summary?.contains("code=260") == true)
    }

    @Test func ffmpegLaunchFailureSummaryParsesSemicolonDiagnostics() {
        let error = "ffmpeg 启动失败：stage=ffmpeg process launch; processExecutableURLPath=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg; nsErrorDomain=NSCocoaErrorDomain; nsErrorCode=4; description=The file “ffmpeg” doesn’t exist.; bookmarkDataByteCount=6"

        let summary = TranscriptionFailureReasonFormatter.summary(
            for: error,
            transcriptionStatus: "failed",
            maxCharacters: 220
        )

        #expect(summary?.contains("processExecutableURL=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg") == true)
        #expect(summary?.contains("NSCocoaErrorDomain") == true)
        #expect(summary?.contains("code=4") == true)
        #expect(summary?.contains("bookmarkDataByteCount") == false)
    }

    @Test func whisperLaunchFailureSummaryHighlightsProcessExecutableURL() {
        let error = """
        whisper-cli 启动失败：
        stage=whisper-cli process launch
        processExecutableURLPath=/Users/vita/ThirdParty/whisper.cpp/build/bin/whisper-cli
        currentDirectoryURLPath=/Users/vita/ThirdParty/whisper.cpp
        rootDirectoryAccessStarted=true
        nsErrorDomain=NSCocoaErrorDomain
        nsErrorCode=4
        description=The file “whisper-cli” doesn’t exist.
        executableBookmarkDataByteCount=944
        """

        let summary = TranscriptionFailureReasonFormatter.summary(
            for: error,
            transcriptionStatus: "failed",
            maxCharacters: 260
        )

        #expect(summary?.contains("processExecutableURL=/Users/vita/ThirdParty/whisper.cpp/build/bin/whisper-cli") == true)
        #expect(summary?.contains("currentDirectoryURL=/Users/vita/ThirdParty/whisper.cpp") == true)
        #expect(summary?.contains("rootDirectoryAccessStarted=true") == true)
        #expect(summary?.contains("NSCocoaErrorDomain") == true)
        #expect(summary?.contains("code=4") == true)
        #expect(summary?.contains("executableBookmarkDataByteCount") == false)
    }

    @Test func nativeConversionFailureSummaryStaysShort() {
        let summary = TranscriptionFailureReasonFormatter.summary(
            for: "native audio conversion failed: stage=wav writing message=The operation could not be completed.",
            transcriptionStatus: "failed",
            maxCharacters: 220
        )

        #expect(summary == "失败原因：native audio conversion failed: stage=wav writing message=The operation could not be completed.")
    }

    @Test func whisperTextOutputPathMatchesOutputPrefixRule() {
        let outputPrefix = URL(fileURLWithPath: "/tmp/rokurics/whisper-task-01")

        #expect(WhisperCppOutputPaths.expectedTextOutputURL(outputPrefix: outputPrefix).path == "/tmp/rokurics/whisper-task-01.txt")
        #expect(WhisperCppOutputPaths.alternateWavTextOutputURL(outputPrefix: outputPrefix).path == "/tmp/rokurics/whisper-task-01.wav.txt")
    }

    @Test func audioInboxActionLabelsMatchTranscriptionState() {
        let notStartedItem = makeInboxItem(transcriptionStatus: "notStarted", transcriptionError: nil)
        #expect(MacAudioInboxRowAction.resolve(
            for: notStartedItem,
            displaySyncState: notStartedItem.canonicalDisplaySyncState,
            isTranscribing: false
        ).label == "转写")

        let failedItem = makeInboxItem(transcriptionStatus: "failed", transcriptionError: "boom")
        #expect(MacAudioInboxRowAction.resolve(
            for: failedItem,
            displaySyncState: failedItem.canonicalDisplaySyncState,
            isTranscribing: false
        ).label == "转写")

        let queuedItem = makeInboxItem(transcriptionStatus: "queued", transcriptionError: nil)
        #expect(MacAudioInboxRowAction.resolve(
            for: queuedItem,
            displaySyncState: queuedItem.canonicalDisplaySyncState,
            isTranscribing: false
        ).label == "转写中")

        let transcribingItem = makeInboxItem(transcriptionStatus: "transcribing", transcriptionError: nil)
        #expect(MacAudioInboxRowAction.resolve(
            for: transcribingItem,
            displaySyncState: transcribingItem.canonicalDisplaySyncState,
            isTranscribing: false
        ).label == "转写中")

        let transcribedItem = makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil)
        #expect(MacAudioInboxRowAction.resolve(
            for: transcribedItem,
            displaySyncState: transcribedItem.canonicalDisplaySyncState,
            isTranscribing: false
        ).label == "查看转写")
    }

    @Test func transcribedInboxActionRequestsTranscriptDetail() {
        let item = makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil)
        let action = MacAudioInboxRowAction.resolve(
            for: item,
            displaySyncState: item.canonicalDisplaySyncState,
            isTranscribing: false
        )

        #expect(action.intent == .viewTranscript)
        #expect(action.isEnabled)
    }

    @Test func failedInboxActionUsesSingleRetryCapsuleIntent() {
        let item = makeInboxItem(transcriptionStatus: "failed", transcriptionError: "launch failed")
        let action = MacAudioInboxRowAction.resolve(
            for: item,
            displaySyncState: item.canonicalDisplaySyncState,
            isTranscribing: false
        )

        #expect(action.label == "转写")
        #expect(action.intent == .startTranscription)
    }

    @Test func missingIncomingAudioUsesTransferProgressModelInActionArea() {
        let item = MacRecordingInboxItem(
            id: "incoming-audio-progress",
            title: "正在接收",
            receivedAt: Date(timeIntervalSince1970: 10),
            duration: 5,
            fileSize: 2048,
            sourceDeviceName: "iPhone",
            transcriptionStatus: "notStarted",
            noteStatus: "notGenerated",
            receiveStatus: "metadataReceived",
            hasAudio: false,
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            transcriptionError: nil
        )
        let completed = makeInboxItem(transcriptionStatus: "notStarted", transcriptionError: nil, hasAudio: true)
        let explicitProgressItem = MacRecordingInboxItem(
            id: "incoming-audio-transfer",
            title: "接收中",
            receivedAt: Date(timeIntervalSince1970: 11),
            duration: 5,
            fileSize: 2048,
            sourceDeviceName: "iPhone",
            transcriptionStatus: "notStarted",
            noteStatus: "notGenerated",
            receiveStatus: "metadataReceived",
            hasAudio: false,
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            transcriptionError: nil,
            transferProgress: LocalNetworkTransferProgress(
                objectID: "recordingAudio:incoming-audio-transfer",
                objectKind: LocalNetworkSyncObjectKind.recordingAudio.rawValue,
                state: .transferring,
                progressFraction: 0.5,
                receivedBytes: 1024,
                totalBytes: 2048,
                sourceDeviceID: "iphone-01",
                statusText: "传输中 50%"
            )
        )

        #expect(item.localNetworkReceiveTransferProgress?.state == .transferring)
        #expect(item.localNetworkReceiveTransferProgress?.isVisibleInActionArea == true)
        #expect(item.localNetworkReceiveTransferProgress?.totalBytes == 2048)
        #expect(item.localNetworkReceiveTransferProgress?.statusText == "正在接收")
        #expect(explicitProgressItem.localNetworkReceiveTransferProgress?.state == .transferring)
        #expect(explicitProgressItem.localNetworkReceiveTransferProgress?.progressFraction == 0.5)
        #expect(explicitProgressItem.localNetworkReceiveTransferProgress?.receivedBytes == 1024)
        #expect(explicitProgressItem.localNetworkReceiveTransferProgress?.statusText == "传输中 50%")
        #expect(completed.localNetworkReceiveTransferProgress == nil)
    }

    @Test func noteStoreWritesNoteMarkdownToDatedRecordingDirectory() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let request = makeNoteGenerationRequest(recordingID: "note-store-01", sanitizedRecordingID: "note-store-01")
        let result = NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: "mockNoteGenerationProvider",
            providerName: "Mock Note Generation",
            modelName: "mock-note-local",
            markdown: "# 录音笔记\n\n## 摘要\n\nHello Rokurics\n\n## 重点\n\n- 第一条",
            startedAt: Date(timeIntervalSince1970: 2_000),
            completedAt: Date(timeIntervalSince1970: 2_001),
            status: "generated"
        )

        let store = NoteStore(rootURL: scratchURL)
        let saveResult = try store.save(result: result, request: request)
        let noteURL = scratchURL.appendingPathComponent(saveResult.noteRelativePath, isDirectory: false)

        #expect(saveResult.noteRelativePath == "notes/1970-01-01/note-store-01/note.md")
        #expect(saveResult.summaryPreviewRelativePath == "notes/1970-01-01/note-store-01/summary.json")
        #expect(try String(contentsOf: noteURL, encoding: .utf8).contains("Hello Rokurics"))

        let preview = try #require(store.loadSummaryPreview(noteRelativePath: saveResult.noteRelativePath))
        #expect(preview.recordingID == "note-store-01")
        #expect(preview.shortSummary == "Hello Rokurics")
        #expect(preview.keyPoints == ["第一条"])
        #expect(preview.providerDisplayName == "Mock Note Generation")
    }

    @Test func mockNoteGenerationProviderGeneratesNonEmptyNote() async throws {
        let provider = MockNoteGenerationProvider()
        let request = makeNoteGenerationRequest(
            recordingID: "mock-note-01",
            sanitizedRecordingID: "mock-note-01",
            transcriptMarkdown: "# 转写\n\n今天讨论了本地 AI 总结。"
        )

        let result = try await provider.generateNote(request: request)

        #expect(result.providerID == "mockNoteGenerationProvider")
        #expect(result.status == "generated")
        #expect(result.markdown.contains("# 录音笔记"))
        #expect(result.markdown.contains("MockNoteGenerationProvider"))
        #expect(result.markdown.contains("今天讨论了本地 AI 总结。"))
        #expect(NoteSummaryPreview.make(result: result, noteRelativePath: "notes/mock/note.md").shortSummary.contains("占位笔记"))
    }

    @Test func receiveRecordMissingNoteFieldsDefaultsToNotGenerated() throws {
        let record = RecordingReceiveRecord(
            recordingID: "legacy-note",
            sanitizedRecordingID: "legacy-note",
            receivedAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            sourceDeviceID: "device",
            sourceDeviceName: "iPhone",
            originalTitle: "旧录音",
            normalizedTitle: "旧录音",
            audioFileName: "audio.m4a",
            originalAudioFileName: "legacy.m4a",
            metadataFileName: "metadata.json",
            status: "received",
            transcriptionStatus: "transcribed",
            noteStatus: "generated",
            noteRelativePath: "notes/1970-01-01/legacy-note/note.md",
            noteGeneratedAt: Date(timeIntervalSince1970: 3),
            noteProviderID: "mockNoteGenerationProvider",
            noteError: nil,
            processingStatus: "transcribed",
            suggestedCategory: nil,
            course: nil,
            category: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 6,
            fileSize: 5,
            suggestedFolder: nil,
            userConfirmedFolder: nil,
            checksum: nil,
            audioRelativePath: "audio/inbox/1970-01-01/legacy-note/audio.m4a",
            metadataRelativePath: "audio/inbox/1970-01-01/legacy-note/metadata.json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: try encoder.encode(record)) as? [String: Any])
        object.removeValue(forKey: "noteStatus")
        object.removeValue(forKey: "noteRelativePath")
        object.removeValue(forKey: "noteGeneratedAt")
        object.removeValue(forKey: "noteProviderID")
        object.removeValue(forKey: "noteModelName")
        object.removeValue(forKey: "noteEndpointDescription")
        object.removeValue(forKey: "noteError")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingReceiveRecord.self, from: data)

        #expect(decoded.noteStatus == "notGenerated")
        #expect(decoded.noteRelativePath == nil)
        #expect(decoded.noteGeneratedAt == nil)
        #expect(decoded.noteProviderID == nil)
        #expect(decoded.noteModelName == nil)
        #expect(decoded.noteEndpointDescription == nil)
        #expect(decoded.noteError == nil)
    }

    @Test func noteGenerationStatusWritePreservesTranscriptFields() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-note-01", title: "笔记", store: store)
        try store.updateTranscriptionStatus(
            recordingID: "mac-note-01",
            status: "transcribed",
            transcriptRelativePath: "transcripts/1970-01-01/mac-note-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/mac-note-01/transcript.md",
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            errorMessage: nil
        )

        try store.updateNoteGenerationStatus(
            recordingID: "mac-note-01",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/mac-note-01/note.md",
            generatedAt: Date(timeIntervalSince1970: 2_000),
            providerID: "openAICompatible",
            modelName: "google/gemma-4-e4b",
            endpointDescription: "127.0.0.1",
            errorMessage: nil
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-note-01")

        #expect(record.noteStatus == "generated")
        #expect(record.noteRelativePath == "notes/1970-01-01/mac-note-01/note.md")
        #expect(record.noteProviderID == "openAICompatible")
        #expect(record.noteModelName == "google/gemma-4-e4b")
        #expect(record.noteEndpointDescription == "127.0.0.1")
        #expect(record.transcriptRelativePath == "transcripts/1970-01-01/mac-note-01/transcript.json")
        #expect(record.transcriptMarkdownRelativePath == "transcripts/1970-01-01/mac-note-01/transcript.md")
    }

    @Test func failedNoteGenerationPreservesExistingNotePath() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-note-failed", title: "失败保留", store: store)
        let generatedAt = Date(timeIntervalSince1970: 2_000)
        try store.updateNoteGenerationStatus(
            recordingID: "mac-note-failed",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/mac-note-failed/note.md",
            generatedAt: generatedAt,
            providerID: "openAICompatible",
            modelName: "google/gemma-4-e4b",
            endpointDescription: "127.0.0.1",
            errorMessage: nil
        )

        try store.updateNoteGenerationStatus(
            recordingID: "mac-note-failed",
            status: "failed",
            noteRelativePath: nil,
            generatedAt: nil,
            providerID: "openAICompatible",
            modelName: "google/gemma-4-e4b",
            endpointDescription: "127.0.0.1",
            errorMessage: "请求超时"
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-note-failed")

        #expect(record.noteStatus == "failed")
        #expect(record.noteRelativePath == "notes/1970-01-01/mac-note-failed/note.md")
        #expect(record.noteGeneratedAt == generatedAt)
        #expect(record.noteError == "请求超时")
    }

    @Test func anthropicNoteGenerationStatusWritesProviderAndModel() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-note-claude", title: "Claude 笔记", store: store)

        try store.updateNoteGenerationStatus(
            recordingID: "mac-note-claude",
            status: "generated",
            noteRelativePath: "notes/1970-01-01/mac-note-claude/note.md",
            generatedAt: Date(timeIntervalSince1970: 2_400),
            providerID: "anthropicMessages",
            modelName: "claude-sonnet-4-6",
            endpointDescription: "api.anthropic.com",
            errorMessage: nil
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-note-claude")

        #expect(record.noteStatus == "generated")
        #expect(record.noteProviderID == "anthropicMessages")
        #expect(record.noteModelName == "claude-sonnet-4-6")
        #expect(record.noteRelativePath == "notes/1970-01-01/mac-note-claude/note.md")
        #expect(record.noteEndpointDescription == "api.anthropic.com")
        #expect(record.noteGeneratedAt != nil)
    }

    @Test @MainActor func noteGenerationSettingsPersistProviderAndOpenAIConfiguration() throws {
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults)

        store.update(
            providerKind: .openAICompatible,
            providerPreset: .lmStudioLocal,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(
                baseURLString: " http://127.0.0.1:1234/v1/ ",
                modelName: " google/gemma-4-e4b ",
                apiKey: " local-secret "
            ),
            cachedModelCandidates: [" google/gemma-4-e4b "]
        )

        let reloaded = NoteGenerationSettingsStore(userDefaults: defaults)

        #expect(reloaded.selectedProviderKind == .openAICompatible)
        #expect(reloaded.selectedProviderPreset == .lmStudioLocal)
        #expect(reloaded.openAIConfiguration.baseURLString == "http://127.0.0.1:1234/v1/")
        #expect(reloaded.openAIConfiguration.modelName == "google/gemma-4-e4b")
        #expect(reloaded.openAIConfiguration.apiKey == "local-secret")
        #expect(reloaded.cachedModelCandidates == ["google/gemma-4-e4b"])
    }

    @Test func aiProviderPresetDefaultsMatchSupportedProviders() {
        #expect(AIProviderPreset.lmStudioLocal.defaultBaseURLString == "http://127.0.0.1:1234/v1")
        #expect(AIProviderPreset.lmStudioLocal.defaultModelCandidates == ["google/gemma-4-e4b"])
        #expect(AIProviderPreset.deepSeek.defaultBaseURLString == "https://api.deepseek.com")
        #expect(AIProviderPreset.deepSeek.defaultModelCandidates == ["deepseek-v4-flash", "deepseek-v4-pro"])
        #expect(AIProviderPreset.openAI.defaultBaseURLString == "https://api.openai.com/v1")
        #expect(AIProviderPreset.openAI.defaultModelCandidates == ["gpt-5.5", "gpt-5.5-mini", "gpt-5.5-nano"])
        #expect(AIProviderPreset.gemini.defaultBaseURLString == "https://generativelanguage.googleapis.com/v1beta/openai")
        #expect(AIProviderPreset.gemini.defaultModelCandidates == ["gemini-3-flash-preview"])
    }

    @Test func aiProviderPresetAppliesDefaultsAndCustomPreservesManualValues() {
        let manual = OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: "https://example.local/v1",
            modelName: "manual-model",
            apiKey: "secret"
        )
        let deepSeek = AIProviderPreset.deepSeek.applyingDefaults(to: manual)
        let custom = AIProviderPreset.customOpenAICompatible.applyingDefaults(to: manual)

        #expect(deepSeek.baseURLString == "https://api.deepseek.com")
        #expect(deepSeek.modelName == "deepseek-v4-flash")
        #expect(deepSeek.apiKey == "secret")
        #expect(custom.baseURLString == "https://example.local/v1")
        #expect(custom.modelName == "manual-model")
        #expect(custom.apiKey == "secret")
    }

    @Test func aiProviderPresetCanInferFromLegacyBaseURL() {
        #expect(AIProviderPreset.inferred(from: "http://127.0.0.1:1234/v1") == .lmStudioLocal)
        #expect(AIProviderPreset.inferred(from: "https://api.deepseek.com") == .deepSeek)
        #expect(AIProviderPreset.inferred(from: "https://api.openai.com/v1") == .openAI)
        #expect(AIProviderPreset.inferred(from: "https://generativelanguage.googleapis.com/v1beta/openai") == .gemini)
        #expect(AIProviderPreset.inferred(from: "https://example.local/v1") == .customOpenAICompatible)
    }

    @Test @MainActor func legacySettingsWithoutProviderPresetInferPresetFromBaseURL() throws {
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let config = OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: "https://api.deepseek.com",
            modelName: "deepseek-chat"
        )
        let data = try JSONEncoder().encode(config)
        defaults.set(NoteGenerationProviderKind.openAICompatible.rawValue, forKey: "noteGeneration.providerKind")
        defaults.set(data, forKey: "noteGeneration.openAICompatible.configuration")

        let store = NoteGenerationSettingsStore(userDefaults: defaults)

        #expect(store.selectedProviderKind == .openAICompatible)
        #expect(store.selectedProviderPreset == .deepSeek)
        #expect(store.openAIConfiguration.modelName == "deepseek-chat")
        #expect(store.cachedModelCandidates.contains("deepseek-chat"))
    }

    @Test @MainActor func modelRefreshReadsModelIDsAndCanPersistCandidates() async throws {
        let response = Data("""
        {
          "object": "list",
          "data": [
            { "id": "model-a" },
            { "id": "model-b" }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, client: client)

        let result = await store.refreshModels(configuration: OpenAICompatibleNoteGenerationConfiguration(apiKey: "secret"))
        store.update(
            providerKind: .openAICompatible,
            providerPreset: .customOpenAICompatible,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(modelName: "model-b", apiKey: "secret"),
            cachedModelCandidates: result.modelIDs
        )
        let reloaded = NoteGenerationSettingsStore(userDefaults: defaults, client: client)

        #expect(result.isSuccess)
        #expect(result.modelIDs == ["model-a", "model-b"])
        #expect(reloaded.openAIConfiguration.modelName == "model-b")
        #expect(reloaded.cachedModelCandidates == ["model-a", "model-b"])
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }

    @Test @MainActor func failedModelRefreshDoesNotClearCurrentModelName() async throws {
        let transport = OpenAICompatibleTransportStub(data: Data("{}".utf8), statusCode: 500)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, client: client)
        store.update(
            providerKind: .openAICompatible,
            providerPreset: .customOpenAICompatible,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(modelName: "manual-model"),
            cachedModelCandidates: ["manual-model"]
        )

        let result = await store.refreshModels(configuration: store.openAIConfiguration)

        #expect(!result.isSuccess)
        #expect(store.openAIConfiguration.modelName == "manual-model")
        #expect(store.cachedModelCandidates == ["manual-model"])
    }

    @Test @MainActor func modelCandidateSelectionPersistsAsModelName() throws {
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults)

        store.update(
            providerKind: .openAICompatible,
            providerPreset: .deepSeek,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(
                baseURLString: AIProviderPreset.deepSeek.defaultBaseURLString,
                modelName: "deepseek-v4-pro"
            ),
            cachedModelCandidates: AIProviderPreset.deepSeek.defaultModelCandidates
        )

        let reloaded = NoteGenerationSettingsStore(userDefaults: defaults)

        #expect(reloaded.openAIConfiguration.modelName == "deepseek-v4-pro")
        #expect(reloaded.cachedModelCandidates.contains("deepseek-v4-pro"))
    }

    @Test func anthropicEndpointURLHandlesTrailingSlashAndV1Base() throws {
        let noSlash = try AnthropicMessagesNoteGenerationClient.endpointURL(
            baseURLString: "https://api.anthropic.com",
            path: "v1/messages"
        )
        let slash = try AnthropicMessagesNoteGenerationClient.endpointURL(
            baseURLString: "https://api.anthropic.com/",
            path: "/v1/models"
        )
        let v1Base = try AnthropicMessagesNoteGenerationClient.endpointURL(
            baseURLString: "https://api.anthropic.com/v1/",
            path: "v1/messages"
        )

        #expect(noSlash.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(slash.absoluteString == "https://api.anthropic.com/v1/models")
        #expect(v1Base.absoluteString == "https://api.anthropic.com/v1/messages")
    }

    @Test func anthropicRequestUsesRequiredHeadersAndDoesNotUseBearer() throws {
        let client = AnthropicMessagesNoteGenerationClient()
        let request = try client.makeRequest(
            path: "v1/messages",
            method: "POST",
            configuration: AnthropicMessagesConfiguration(
                apiKey: " claude-secret ",
                anthropicVersion: " 2023-06-01 "
            ),
            timeout: 10,
            body: Data("{}".utf8)
        )

        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "claude-secret")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test @MainActor func anthropicSettingsPersistProviderAndConfiguration() throws {
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults)

        store.update(
            providerKind: .anthropicMessages,
            providerPreset: .customOpenAICompatible,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(),
            cachedModelCandidates: [],
            anthropicConfiguration: AnthropicMessagesConfiguration(
                baseURLString: " https://api.anthropic.com/ ",
                modelName: " claude-haiku-4-5 ",
                apiKey: " claude-secret ",
                anthropicVersion: " 2023-06-01 "
            ),
            cachedAnthropicModelCandidates: [" claude-haiku-4-5 "]
        )

        let reloaded = NoteGenerationSettingsStore(userDefaults: defaults)

        #expect(reloaded.selectedProviderKind == .anthropicMessages)
        #expect(reloaded.currentProviderID == "anthropicMessages")
        #expect(reloaded.anthropicConfiguration.baseURLString == "https://api.anthropic.com/")
        #expect(reloaded.anthropicConfiguration.modelName == "claude-haiku-4-5")
        #expect(reloaded.anthropicConfiguration.apiKey == "claude-secret")
        #expect(reloaded.anthropicConfiguration.anthropicVersion == "2023-06-01")
        #expect(reloaded.cachedAnthropicModelCandidates == ["claude-haiku-4-5"])
    }

    @Test @MainActor func anthropicModelRefreshReadsModelIDsAndDoesNotClearOnFailure() async throws {
        let response = Data("""
        {
          "data": [
            { "id": "claude-sonnet-4-6" },
            { "id": "claude-haiku-4-5" }
          ]
        }
        """.utf8)
        let transport = AnthropicMessagesTransportStub(data: response, statusCode: 200)
        let client = AnthropicMessagesNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, anthropicClient: client)
        let configuration = AnthropicMessagesConfiguration(modelName: "claude-haiku-4-5", apiKey: "claude-secret")

        let result = await store.refreshAnthropicModels(configuration: configuration)
        store.update(
            providerKind: .anthropicMessages,
            providerPreset: .customOpenAICompatible,
            openAIConfiguration: OpenAICompatibleNoteGenerationConfiguration(),
            cachedModelCandidates: [],
            anthropicConfiguration: configuration,
            cachedAnthropicModelCandidates: result.modelIDs
        )
        let failedTransport = AnthropicMessagesTransportStub(data: Data("{}".utf8), statusCode: 500)
        let failedStore = NoteGenerationSettingsStore(userDefaults: defaults, anthropicClient: AnthropicMessagesNoteGenerationClient(transport: failedTransport))
        let failedResult = await failedStore.refreshAnthropicModels(configuration: failedStore.anthropicConfiguration)

        #expect(result.isSuccess)
        #expect(result.modelIDs == ["claude-sonnet-4-6", "claude-haiku-4-5"])
        #expect(transport.lastRequest?.url?.absoluteString == "https://api.anthropic.com/v1/models")
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "x-api-key") == "claude-secret")
        #expect(failedResult.isSuccess == false)
        #expect(failedStore.anthropicConfiguration.modelName == "claude-haiku-4-5")
        #expect(failedStore.cachedAnthropicModelCandidates == ["claude-sonnet-4-6", "claude-haiku-4-5"])
    }

    @Test @MainActor func anthropicTestModelUsesMessagesAPIShape() async throws {
        let response = Data("""
        {
          "content": [
            { "type": "text", "text": "Rokurics Claude OK" }
          ],
          "stop_reason": "end_turn"
        }
        """.utf8)
        let transport = AnthropicMessagesTransportStub(data: response, statusCode: 200)
        let client = AnthropicMessagesNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, anthropicClient: client)

        let result = await store.testAnthropicModel(configuration: AnthropicMessagesConfiguration(apiKey: "claude-secret"))
        let body = try requestBodyJSON(from: try #require(transport.lastRequest))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let firstMessage = try #require(messages.first)

        #expect(result.isSuccess)
        #expect(body["model"] as? String == "claude-sonnet-4-6")
        #expect((body["max_tokens"] as? NSNumber)?.intValue == 256)
        #expect((body["temperature"] as? NSNumber)?.doubleValue == 0.1)
        #expect(body["system"] as? String != nil)
        #expect(!body.keys.contains("stream"))
        #expect(firstMessage["role"] as? String == "user")
        #expect((firstMessage["content"] as? String)?.contains("Rokurics Claude OK") == true)
    }

    @Test func anthropicMessageResponseParsesTextBlocksAndRejectsEmptyContent() throws {
        let data = Data("""
        {
          "content": [
            { "type": "text", "text": "第一段" },
            { "type": "tool_use", "id": "tool-1" },
            { "type": "text", "text": "第二段" }
          ],
          "stop_reason": "end_turn",
          "usage": { "input_tokens": 12, "output_tokens": 8 }
        }
        """.utf8)

        let result = try AnthropicMessagesNoteGenerationClient.parseMessage(data: data, statusCode: 200)

        #expect(result.content == "第一段\n第二段")
        #expect(result.stopReason == "end_turn")

        let emptyData = Data("""
        {
          "content": [
            { "type": "text", "text": "   " }
          ],
          "stop_reason": "end_turn"
        }
        """.utf8)
        do {
            _ = try AnthropicMessagesNoteGenerationClient.parseMessage(data: emptyData, statusCode: 200)
            Issue.record("Expected empty Claude content to fail")
        } catch let error as AnthropicMessagesClientError {
            if case .emptyContent(let diagnostics) = error {
                #expect(diagnostics.statusCode == 200)
                #expect(diagnostics.textLength == 0)
            } else {
                Issue.record("Expected empty content error")
            }
        }
    }

    @Test func anthropicMessageResponseAllowsMaxTokensWhenContentExists() throws {
        let data = Data("""
        {
          "content": [
            { "type": "text", "text": "# 录音笔记\\n\\n## 摘要\\nClaude 笔记" }
          ],
          "stop_reason": "max_tokens"
        }
        """.utf8)

        let result = try AnthropicMessagesNoteGenerationClient.parseMessage(data: data)

        #expect(result.content.contains("Claude 笔记"))
        #expect(result.isLengthLimited)
    }

    @Test func anthropicErrorsDoNotExposeResponseBodyOrAPIKey() async throws {
        let response = Data("""
        {
          "content": [
            { "type": "text", "text": "" }
          ],
          "stop_reason": "end_turn",
          "debug": "private response body"
        }
        """.utf8)
        let transport = AnthropicMessagesTransportStub(data: response, statusCode: 200)
        let client = AnthropicMessagesNoteGenerationClient(transport: transport)

        do {
            _ = try await client.message(
                configuration: AnthropicMessagesConfiguration(apiKey: "claude-secret"),
                system: "system",
                userContent: "ping",
                timeout: 30,
                maxTokens: 256
            )
            Issue.record("Expected empty Claude content to fail")
        } catch {
            #expect(error.localizedDescription.contains("status=200"))
            #expect(!error.localizedDescription.contains("private response body"))
            #expect(!error.localizedDescription.contains("claude-secret"))
            #expect(!error.localizedDescription.contains("\"content\""))
        }
    }

    @Test func anthropicProviderCreatesMetadataNoteAndDoesNotPersistUsageOrAPIKey() async throws {
        let response = Data("""
        {
          "content": [
            { "type": "text", "text": "# 录音笔记\\n\\n## 摘要\\nClaude 公开笔记" }
          ],
          "stop_reason": "max_tokens",
          "usage": { "input_tokens": 999, "output_tokens": 888 }
        }
        """.utf8)
        let transport = AnthropicMessagesTransportStub(data: response, statusCode: 200)
        let client = AnthropicMessagesNoteGenerationClient(transport: transport)
        let provider = AnthropicMessagesNoteGenerationProvider(
            configuration: AnthropicMessagesConfiguration(apiKey: "claude-secret"),
            client: client
        )

        let result = try await provider.generateNote(request: makeNoteGenerationRequest(
            recordingID: "claude-note",
            sanitizedRecordingID: "claude-note",
            transcriptMarkdown: "高斯公式和向量场积分有关。"
        ))

        #expect(result.providerID == "anthropicMessages")
        #expect(result.modelName == "claude-sonnet-4-6")
        #expect(result.modelOutputWasTruncated)
        #expect(result.markdown.contains("Provider: Claude / Anthropic"))
        #expect(result.markdown.contains("Claude 公开笔记"))
        #expect(result.markdown.contains("模型输出可能因长度限制被截断"))
        #expect(!result.markdown.contains("input_tokens"))
        #expect(!result.markdown.contains("output_tokens"))
        #expect(!result.markdown.contains("claude-secret"))
    }

    @Test func openAICompatibleEndpointURLHandlesTrailingSlash() throws {
        let noSlash = try OpenAICompatibleNoteGenerationClient.endpointURL(
            baseURLString: "http://127.0.0.1:1234/v1",
            path: "models"
        )
        let slash = try OpenAICompatibleNoteGenerationClient.endpointURL(
            baseURLString: "http://127.0.0.1:1234/v1/",
            path: "/chat/completions"
        )

        #expect(noSlash.absoluteString == "http://127.0.0.1:1234/v1/models")
        #expect(slash.absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
    }

    @Test func openAICompatibleRequestOmitsAuthorizationWhenAPIKeyIsEmpty() throws {
        let client = OpenAICompatibleNoteGenerationClient()
        let request = try client.makeRequest(
            path: "models",
            method: "GET",
            configuration: OpenAICompatibleNoteGenerationConfiguration(apiKey: " "),
            timeout: 10,
            body: nil
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func openAICompatibleRequestSendsBearerAuthorizationWhenAPIKeyExists() throws {
        let client = OpenAICompatibleNoteGenerationClient()
        let request = try client.makeRequest(
            path: "models",
            method: "GET",
            configuration: OpenAICompatibleNoteGenerationConfiguration(apiKey: " local-secret "),
            timeout: 10,
            body: nil
        )

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer local-secret")
    }

    @Test @MainActor func noteGenerationTestModelRequestUsesReasoningSafeOptions() async throws {
        let response = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "Rokurics AI OK" },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let suiteName = "RokuricsMacTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteGenerationSettingsStore(userDefaults: defaults, client: client)

        let result = await store.testModel(configuration: OpenAICompatibleNoteGenerationConfiguration())
        let body = try requestBodyJSON(from: try #require(transport.lastRequest))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let systemMessage = try #require(messages.first?["content"] as? String)
        let userMessage = try #require(messages.dropFirst().first?["content"] as? String)

        #expect(result.isSuccess)
        #expect((body["max_tokens"] as? NSNumber)?.intValue == 512)
        #expect((body["temperature"] as? NSNumber)?.doubleValue == 0.1)
        #expect((body["stream"] as? Bool) == false)
        #expect(systemMessage.contains("不要输出思考过程"))
        #expect(userMessage.contains("Rokurics AI OK"))
    }

    @Test func openAICompatibleChatResponseParsesFirstChoiceContent() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "# 录音笔记\\n\\n## 摘要" },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)

        let result = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data)

        #expect(result.content.contains("# 录音笔记"))
        #expect(result.finishReason == "stop")
    }

    @Test func openAICompatibleChatResponseRejectsEmptyContent() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "   " },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)

        do {
            _ = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data)
            Issue.record("Expected empty content to fail")
        } catch let error as OpenAICompatibleNoteGenerationClientError {
            if case .emptyContent(let diagnostics) = error {
                #expect(diagnostics.messageContentWasPresent)
                #expect(diagnostics.contentLength == 0)
                #expect(diagnostics.choicesCount == 1)
            } else {
                Issue.record("Expected empty content error")
            }
        }
    }

    @Test func openAICompatibleChatResponseRejectsReasoningOnlyContent() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "",
                "reasoning_content": "private reasoning should not appear"
              },
              "finish_reason": "stop"
            }
          ],
          "usage": {
            "prompt_tokens": 12,
            "completion_tokens": 413,
            "total_tokens": 425,
            "completion_tokens_details": { "reasoning_tokens": 413 }
          }
        }
        """.utf8)

        do {
            _ = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data, statusCode: 200)
            Issue.record("Expected reasoning-only content to fail")
        } catch let error as OpenAICompatibleNoteGenerationClientError {
            if case .reasoningContentWithoutFinalContent(let diagnostics) = error {
                #expect(diagnostics.statusCode == 200)
                #expect(diagnostics.reasoningContentLength > 0)
                #expect(diagnostics.reasoningTokens == 413)
                #expect(!error.localizedDescription.contains("private reasoning should not appear"))
            } else {
                Issue.record("Expected reasoning-only error")
            }
        }
    }

    @Test func openAICompatibleChatResponseRejectsLengthBeforeFinalContent() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "   " },
              "finish_reason": "length"
            }
          ],
          "usage": {
            "prompt_tokens": 8,
            "completion_tokens": 512,
            "total_tokens": 520,
            "completion_tokens_details": { "reasoning_tokens": 413 }
          }
        }
        """.utf8)

        do {
            _ = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data, statusCode: 200)
            Issue.record("Expected length-limited empty content to fail")
        } catch let error as OpenAICompatibleNoteGenerationClientError {
            if case .finalContentStoppedByLength(let diagnostics) = error {
                #expect(diagnostics.finishReason == "length")
                #expect(diagnostics.contentLength == 0)
                #expect(diagnostics.reasoningTokens == 413)
                #expect(error.localizedDescription.contains("请增大 max_tokens"))
            } else {
                Issue.record("Expected length-before-content error")
            }
        }
    }

    @Test func openAICompatibleChatResponseAllowsLengthWhenContentExists() throws {
        let data = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "Rokurics AI OK" },
              "finish_reason": "length"
            }
          ]
        }
        """.utf8)

        let result = try OpenAICompatibleNoteGenerationClient.parseChatCompletion(data: data)

        #expect(result.content == "Rokurics AI OK")
        #expect(result.isLengthLimited)
    }

    @Test func openAICompatibleEmptyContentDiagnosticsDoNotExposeBodyOrAPIKey() async throws {
        let response = Data("""
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "",
                "reasoning_content": "secret reasoning trace"
              },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)

        do {
            _ = try await client.chatCompletion(
                configuration: OpenAICompatibleNoteGenerationConfiguration(apiKey: "local-secret"),
                messages: [OpenAICompatibleMessage(role: "user", content: "ping")],
                timeout: 30,
                maxTokens: 512
            )
            Issue.record("Expected empty content to fail")
        } catch {
            #expect(error.localizedDescription.contains("status=200"))
            #expect(!error.localizedDescription.contains("secret reasoning trace"))
            #expect(!error.localizedDescription.contains("local-secret"))
            #expect(!error.localizedDescription.contains("\"choices\""))
        }
    }

    @Test func openAICompatibleLengthFinishReasonMarksTruncatedNote() async throws {
        let response = Data("""
        {
          "choices": [
            {
              "message": { "role": "assistant", "content": "# 录音笔记\\n\\n## 摘要\\n测试" },
              "finish_reason": "length"
            }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let provider = OpenAICompatibleNoteGenerationProvider(
            configuration: OpenAICompatibleNoteGenerationConfiguration(modelName: "google/gemma-4-e4b"),
            client: client
        )

        let result = try await provider.generateNote(request: makeNoteGenerationRequest(
            recordingID: "openai-length",
            sanitizedRecordingID: "openai-length",
            transcriptMarkdown: "高斯公式和向量场积分有关。"
        ))

        #expect(result.modelOutputWasTruncated)
        #expect(result.markdown.contains("模型输出可能因长度限制被截断"))
    }

    @Test func openAICompatibleProviderDoesNotPersistReasoningContent() async throws {
        let response = Data("""
        {
          "choices": [
            {
              "message": {
                "role": "assistant",
                "content": "# 录音笔记\\n\\n## 摘要\\n公开笔记",
                "reasoning_content": "hidden reasoning should never be saved"
              },
              "finish_reason": "stop"
            }
          ]
        }
        """.utf8)
        let transport = OpenAICompatibleTransportStub(data: response, statusCode: 200)
        let client = OpenAICompatibleNoteGenerationClient(transport: transport)
        let provider = OpenAICompatibleNoteGenerationProvider(
            configuration: OpenAICompatibleNoteGenerationConfiguration(modelName: "google/gemma-4-e4b"),
            client: client
        )

        let result = try await provider.generateNote(request: makeNoteGenerationRequest(
            recordingID: "openai-reasoning",
            sanitizedRecordingID: "openai-reasoning",
            transcriptMarkdown: "高斯公式和向量场积分有关。"
        ))

        #expect(result.markdown.contains("公开笔记"))
        #expect(!result.markdown.contains("hidden reasoning"))
    }

    @Test func openAICompatibleProviderPrefersTranscriptMarkdownOverJSONText() {
        let request = NoteGenerationRequest(
            taskID: "task-transcript-priority",
            recordingID: "transcript-priority",
            sanitizedRecordingID: "transcript-priority",
            title: "优先级",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 6,
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            transcriptionProviderID: "whisper.cpp",
            transcriptionModelName: "small",
            transcriptResult: makeTranscriptionResult(text: "JSON 正文"),
            transcriptMarkdown: "Markdown 正文",
            requestedAt: Date(timeIntervalSince1970: 2_000)
        )

        #expect(OpenAICompatibleNoteGenerationProvider.transcriptInput(from: request) == "Markdown 正文")
    }

    @Test func noteGenerationTranscriptLoaderAllowsJSONTextWithoutMarkdown() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let transcriptURL = scratchURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("1970-01-01", isDirectory: true)
            .appendingPathComponent("json-only", isDirectory: true)
            .appendingPathComponent("transcript.json", isDirectory: false)
        try FileManager.default.createDirectory(at: transcriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(makeTranscriptionResult(text: "只有 JSON 的转写正文")).write(to: transcriptURL)

        let loaded = try NoteGenerationTranscriptLoader().load(source: makeNoteSource(
            transcriptURL: transcriptURL,
            transcriptMarkdownURL: transcriptURL.deletingLastPathComponent().appendingPathComponent("missing.md")
        ))

        #expect(loaded.transcriptMarkdown == nil)
        #expect(loaded.transcriptResult?.text == "只有 JSON 的转写正文")
    }

    @Test func openAICompatibleTranscriptInputIsTruncatedConservatively() {
        let result = OpenAICompatibleNoteGenerationProvider.truncatedTranscript(
            String(repeating: "课", count: 12_010),
            maxCharacters: 12_000
        )

        #expect(result.text.count == 12_000)
        #expect(result.wasTruncated)
    }

    @Test func noteGenerationTranscriptLoaderReportsMissingDocuments() throws {
        let loader = NoteGenerationTranscriptLoader()
        let source = makeNoteSource(
            transcriptURL: nil,
            transcriptMarkdownURL: nil
        )

        do {
            _ = try loader.load(source: source)
            Issue.record("Expected missing transcript documents to fail")
        } catch let error as NoteGenerationError {
            #expect(error == .transcriptDocumentMissing)
        }
    }

    @Test func noteGenerationTranscriptLoaderAllowsMarkdownWithoutJSON() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let markdownURL = scratchURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("1970-01-01", isDirectory: true)
            .appendingPathComponent("md-only", isDirectory: true)
            .appendingPathComponent("transcript.md", isDirectory: false)
        try FileManager.default.createDirectory(at: markdownURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "只有 Markdown 的转写正文".write(to: markdownURL, atomically: true, encoding: .utf8)

        let loader = NoteGenerationTranscriptLoader()
        let loaded = try loader.load(source: makeNoteSource(
            transcriptURL: markdownURL.deletingLastPathComponent().appendingPathComponent("missing.json"),
            transcriptMarkdownURL: markdownURL
        ))

        #expect(loaded.transcriptResult == nil)
        #expect(loaded.transcriptMarkdown == "只有 Markdown 的转写正文")
    }

    @Test func noteInboxActionLabelsMatchNoteState() {
        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "notStarted", transcriptionError: nil),
            isGenerating: false
        ) == nil)

        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil),
            isGenerating: false
        )?.label == "生成笔记")

        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil),
            isGenerating: true
        )?.label == "生成中")

        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(
                transcriptionStatus: "transcribed",
                transcriptionError: nil,
                noteStatus: "generated",
                noteRelativePath: "notes/1970-01-01/recording-01/note.md"
            ),
            isGenerating: false
        )?.label == "查看笔记")

        #expect(MacAudioInboxNoteRowAction.regenerateAction(
            for: makeInboxItem(
                transcriptionStatus: "transcribed",
                transcriptionError: nil,
                noteStatus: "generated",
                noteRelativePath: "notes/1970-01-01/recording-01/note.md"
            ),
            isGenerating: false
        )?.label == "重新生成")

        #expect(MacAudioInboxNoteRowAction.resolve(
            for: makeInboxItem(
                transcriptionStatus: "transcribed",
                transcriptionError: nil,
                noteStatus: "failed",
                noteError: "未找到可用于生成笔记的转写文档"
            ),
            isGenerating: false
        )?.label == "重试笔记")
    }

    @Test func hoverDeleteIconPresentationSwitchesOnlyWhenIconHovered() {
        let regular = MacAudioInboxIconPresentation.resolve(isDeleteIconHovered: false)
        let destructive = MacAudioInboxIconPresentation.resolve(isDeleteIconHovered: true)

        #expect(regular.systemImage == "waveform")
        #expect(regular.isDestructive == false)
        #expect(regular.containerSize == destructive.containerSize)
        #expect(regular.containerSize == 38)
        #expect(destructive.systemImage == "trash.fill")
        #expect(destructive.isDestructive)
        #expect(destructive.glyphSize <= regular.glyphSize)
    }

    @Test func transcriptMarkdownLoaderReadsExistingMarkdown() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let transcriptURL = scratchURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("2026-05-17", isDirectory: true)
            .appendingPathComponent("recording-01", isDirectory: true)
            .appendingPathComponent("transcript.md", isDirectory: false)
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# 录音\n\n你好 Rokurics".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptMarkdownRelativePath: "transcripts/2026-05-17/recording-01/transcript.md"
        )
        let loader = TranscriptMarkdownDocumentLoader(rootURL: scratchURL)

        #expect(loader.load(item: item) == .loaded("# 录音\n\n你好 Rokurics"))
    }

    @Test func transcriptMarkdownLoaderFallsBackFromTranscriptJSONPath() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let transcriptURL = scratchURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("2026-05-17", isDirectory: true)
            .appendingPathComponent("recording-02", isDirectory: true)
            .appendingPathComponent("transcript.md", isDirectory: false)
        try FileManager.default.createDirectory(
            at: transcriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "fallback markdown".write(to: transcriptURL, atomically: true, encoding: .utf8)

        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptRelativePath: "transcripts/2026-05-17/recording-02/transcript.json",
            transcriptMarkdownRelativePath: nil
        )
        let loader = TranscriptMarkdownDocumentLoader(rootURL: scratchURL)

        #expect(loader.load(item: item) == .loaded("fallback markdown"))
    }

    @Test func transcriptMarkdownLoaderReportsFriendlyMissingDocument() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptMarkdownRelativePath: "transcripts/missing/transcript.md"
        )
        let loader = TranscriptMarkdownDocumentLoader(rootURL: scratchURL)

        #expect(loader.load(item: item) == .failed("未找到转写文档"))
    }

    @Test func transcriptCleanerExtractsBodyWithoutMarkdownMetadata() {
        let markdown = """
        # 录音 2026-05-19

        - Provider: whisper.cpp
        - Transcribed At: 2026-05-19T08:00:00Z
        - Language: zh

        ## Transcript
        今天学习矩阵乘法。
        第二句。

        ## Segments
        - [00:00.000 --> 00:03.000] 今天学习矩阵乘法。
        """

        let body = RokuricsTranscriptMarkdownCleaner.cleanedBody(from: markdown)
        let metadata = RokuricsTranscriptMarkdownCleaner.metadata(from: markdown)

        #expect(body == "今天学习矩阵乘法。\n第二句。")
        #expect(metadata["provider"] == "whisper.cpp")
        #expect(metadata["language"] == "zh")
        #expect(!body.contains("Provider"))
        #expect(!body.contains("Transcribed At"))
        #expect(!body.contains("Language"))
        #expect(!body.contains("## Transcript"))
        #expect(!body.contains("## Segments"))
    }

    @Test func noteCleanerRemovesTopMetadataAndKeepsStudyContent() {
        let markdown = """
        # 录音笔记

        > 由 Rokurics 生成
        > Provider: OpenAI-compatible
        > Model: deepseek-v4-pro

        ## 基本信息
        - 生成时间：2026-05-19 08:00
        - 转写来源：transcript.md
        - 转写模型：small

        ## 摘要
        这是摘要。

        ## 重点
        - 第一条
        """

        let body = RokuricsNoteMarkdownCleaner.cleanedBody(from: markdown)
        let metadata = RokuricsNoteMarkdownCleaner.metadata(from: markdown)

        #expect(metadata["provider"] == "OpenAI-compatible")
        #expect(metadata["model"] == "deepseek-v4-pro")
        #expect(body.contains("## 摘要"))
        #expect(body.contains("这是摘要。"))
        #expect(body.contains("- 第一条"))
        #expect(!body.contains("Provider"))
        #expect(!body.contains("Model"))
        #expect(!body.contains("## 基本信息"))
    }

    @Test func noteSummaryPreviewExtractsSummaryAndFallsBackToBodyPreview() {
        let markdown = """
        # 录音笔记

        > Provider: Mock

        ## 摘要

        这是一段适合卡片显示的摘要。

        ## 重点

        - 第一个重点
        - 第二个重点
        """
        let fallbackMarkdown = "# 录音笔记\n\n## 大纲\n\n没有摘要时使用正文预览。"

        #expect(NoteSummaryPreview.shortSummary(from: markdown) == "这是一段适合卡片显示的摘要。")
        #expect(NoteSummaryPreview.keyPoints(from: markdown) == ["第一个重点", "第二个重点"])
        #expect(NoteSummaryPreview.shortSummary(from: fallbackMarkdown) == nil)
        #expect(NoteSummaryPreview.fallbackSummary(from: fallbackMarkdown).contains("没有摘要时使用正文预览"))
    }

    @Test func noteSummaryPreviewDoesNotKeepSensitiveDebugText() {
        let markdown = """
        # 录音笔记

        ## 摘要

        API Key: sk-secret
        response JSON should not appear
        安全摘要
        """

        let summary = NoteSummaryPreview.shortSummary(from: markdown)

        #expect(summary == "安全摘要")
        #expect(summary?.contains("sk-secret") == false)
        #expect(summary?.contains("response JSON") == false)
    }

    @Test func noteStoreRegeneratingNoteUpdatesSummaryPreview() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let request = makeNoteGenerationRequest(recordingID: "summary-update-01", sanitizedRecordingID: "summary-update-01")
        let store = NoteStore(rootURL: scratchURL)
        let first = NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: "mockNoteGenerationProvider",
            providerName: "Mock",
            modelName: "mock-1",
            markdown: "# 录音笔记\n\n## 摘要\n\n第一版摘要",
            startedAt: Date(timeIntervalSince1970: 10),
            completedAt: Date(timeIntervalSince1970: 11),
            status: "generated"
        )
        let second = NoteGenerationResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: "mockNoteGenerationProvider",
            providerName: "Mock",
            modelName: "mock-2",
            markdown: "# 录音笔记\n\n## 摘要\n\n第二版摘要",
            startedAt: Date(timeIntervalSince1970: 12),
            completedAt: Date(timeIntervalSince1970: 13),
            status: "generated"
        )

        let saveResult = try store.save(result: first, request: request)
        _ = try store.save(result: second, request: request)
        let preview = try #require(store.loadSummaryPreview(noteRelativePath: saveResult.noteRelativePath))

        #expect(preview.shortSummary == "第二版摘要")
        #expect(preview.modelName == "mock-2")
    }

    @Test func markdownRendererParsesHeadingsBulletsAndParagraphs() {
        let blocks = RokuricsMarkdownRenderer.blocks(from: "# 摘要\n\n- 第一条\n普通段落")

        #expect(blocks == [
            .heading(level: 1, text: "摘要"),
            .bullet("第一条"),
            .paragraph("普通段落")
        ])
    }

    @Test func macContentPagesUseIconOnlyBackButton() throws {
        #expect(RokuricsBackButton.visibleTitle.isEmpty)
        #expect(RokuricsBackButton.accessibilityTitle == "返回")
        #expect(RokuricsInfoButton.visibleTitle.isEmpty)
        #expect(RokuricsInfoButton.accessibilityTitle == "信息")
        #expect(RokuricsCircleIconButton.size == RokuricsCircleIconButtonConfiguration.size)

        let repoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "RokuricsMac/MacAudioInboxView.swift",
            "RokuricsMac/MacNoteDetailView.swift",
            "RokuricsMac/MacStudyLibraryView.swift"
        ]

        for relativePath in relativePaths {
            let text = try String(contentsOf: repoURL.appendingPathComponent(relativePath), encoding: .utf8)
            #expect(!text.contains("Label(\"返回\""))
            #expect(!text.contains("Button(\"返回\""))
            #expect(!text.contains("Text(\"返回\""))
        }

        let transcriptText = try String(contentsOf: repoURL.appendingPathComponent("RokuricsMac/MacAudioInboxView.swift"), encoding: .utf8)
        let noteText = try String(contentsOf: repoURL.appendingPathComponent("RokuricsMac/MacNoteDetailView.swift"), encoding: .utf8)
        #expect(transcriptText.contains("RokuricsDocumentPageHeader"))
        #expect(transcriptText.contains("RokuricsInfoButton"))
        #expect(noteText.contains("RokuricsDocumentPageHeader"))
        #expect(noteText.contains("RokuricsInfoButton"))
    }

    @Test func fileRevealServiceRevealsFilesAndOpensFolders() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }
        let directoryURL = scratchURL.appendingPathComponent("notes", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("note.md", isDirectory: false)
        try "note".write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(FileRevealService.action(for: directoryURL.path) == .open(directoryURL.standardizedFileURL))
        #expect(FileRevealService.action(for: fileURL.path) == .reveal(fileURL.standardizedFileURL))
        #expect(FileRevealService.action(for: "notes/note.md", rootURL: scratchURL) == .reveal(fileURL.standardizedFileURL))
        #expect(FileRevealService.looksOpenablePath("transcripts/2026-05-19/a/transcript.md"))
    }

    @Test func macStudyLibraryBreadcrumbNavigationTruncatesBrowsePath() {
        let fullPath = StudyBrowsePath(components: ["数学", "线性代数", "Ch1", "矩阵"])
        let breadcrumbs = StudyLibraryBrowser.breadcrumbs(for: fullPath)
        var state = MacStudyLibraryNavigationState(browsePath: fullPath)

        state.navigate(to: breadcrumbs[0].path)
        #expect(state.browsePath.components == [])

        state.navigate(to: breadcrumbs[1].path)
        #expect(state.browsePath.components == ["数学"])

        state.navigate(to: breadcrumbs[2].path)
        #expect(state.browsePath.components == ["数学", "线性代数"])

        state.navigate(to: breadcrumbs[3].path)
        #expect(state.browsePath.components == ["数学", "线性代数", "Ch1"])
    }

    @Test func sharedFolderTileUsesSharedFolderAccentPalette() {
        #expect(StudyFolderColorToken.blue.sharedAccentColor != nil)
        #expect(StudyFolderColorToken.default.sharedAccentColor == nil)
    }

    @Test func folderContextMenuUsesFinderLikeActionAndTwoColorRows() {
        #expect(MacFolderContextMenuModel.primaryActionTitles == ["重命名", "移入废纸篓"])
        #expect(MacFolderContextMenuModel.colorTokens == [.default, .red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .gray])
        #expect(MacFolderContextMenuModel.colorTokens.count == 12)
        #expect(MacFolderContextMenuModel.colorRows.count == 2)
        #expect(MacFolderContextMenuModel.colorRows.allSatisfy { $0.count == 6 })
        #expect(MacFolderContextMenuModel.colorRows.flatMap { $0 } == MacFolderContextMenuModel.colorTokens)
    }

    @Test func legacyFolderColorTokensStillDecode() throws {
        let data = try #require("\"blue\"".data(using: .utf8))
        let decoded = try JSONDecoder().decode(StudyFolderColorToken.self, from: data)

        #expect(decoded == .blue)
    }

    @Test func noteDefaultInfoHidesTranscriptPathAndRawProviderID() {
        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptMarkdownRelativePath: "transcripts/2026-05-16/recording-01/transcript.md",
            noteStatus: "generated",
            noteRelativePath: "notes/2026-05-16/recording-01/note.md"
        )
        let markdown = """
        # 录音笔记

        > Provider: mockNoteGenerationProvider
        > Model: deepseek-v4-pro

        ## 基本信息
        - 转写来源：transcripts/2026-05-16/recording-01/transcript.md

        ## 摘要
        内容
        """

        let metadata = StudyItemMetadata.defaultMetadata(for: item)
        let defaultText = StudyReadingMetadataRows.noteInfoRows(item: metadata, markdown: markdown, receiveRecord: nil)
            .map(\.value)
            .joined(separator: " ")
        let advancedText = StudyReadingMetadataRows.noteAdvancedRows(item: metadata, markdown: markdown, receiveRecord: nil)
            .map(\.value)
            .joined(separator: " ")

        #expect(defaultText.contains("deepseek-v4-pro"))
        #expect(defaultText.contains("Mock"))
        #expect(!defaultText.contains("transcripts/2026-05-16"))
        #expect(!defaultText.contains("mockNoteGenerationProvider"))
        #expect(advancedText.contains("transcripts/2026-05-16/recording-01/transcript.md"))
        #expect(!advancedText.contains("mockNoteGenerationProvider"))
    }

    @Test func transcriptDefaultInfoHidesTranscriptPathAndAdvancedKeepsIt() {
        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptRelativePath: "transcripts/2026-05-16/recording-01/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/2026-05-16/recording-01/transcript.md"
        )
        let markdown = """
        - Provider: whisper.cpp
        - Language: zh

        ## Transcript
        内容
        """

        let metadata = StudyItemMetadata.defaultMetadata(for: item)
        let defaultText = StudyReadingMetadataRows.transcriptInfoRows(item: metadata, markdown: markdown, transcriptResult: nil, receiveRecord: nil)
            .map(\.value)
            .joined(separator: " ")
        let advancedText = StudyReadingMetadataRows.transcriptAdvancedRows(item: metadata, markdown: markdown, transcriptResult: nil, receiveRecord: nil)
            .map(\.value)
            .joined(separator: " ")

        #expect(defaultText.contains("zh"))
        #expect(!defaultText.contains("transcripts/2026-05-16"))
        #expect(advancedText.contains("transcripts/2026-05-16/recording-01/transcript.md"))
    }

    @Test func transcriptInfoPanelRowsContainReadableTranscriptionMetadata() {
        let item = makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil)
        let result = TranscriptionResult(
            taskID: "task",
            recordingID: item.id,
            providerID: "whisperCppTranscriptionProvider",
            providerName: "WhisperCppTranscriptionProvider",
            modelName: "/models/ggml-small.bin",
            language: "zh",
            text: "正文",
            segments: [],
            startedAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            status: "transcribed"
        )
        let rows = StudyReadingMetadataRows.transcriptInfoRows(
            item: StudyItemMetadata.defaultMetadata(for: item),
            markdown: "## Transcript\n正文",
            transcriptResult: result,
            receiveRecord: nil
        )
        let text = rows.map { "\($0.label)=\($0.value)" }.joined(separator: " ")

        #expect(text.contains("录音时间"))
        #expect(text.contains("时长"))
        #expect(text.contains("语言=zh"))
        #expect(text.contains("转写 Provider=whisper.cpp"))
        #expect(text.contains("转写模型=ggml-small.bin"))
    }

    @Test func noteInfoPanelRowsContainReadableGenerationMetadata() {
        let item = makeInboxItem(transcriptionStatus: "transcribed", transcriptionError: nil)
        let rows = StudyReadingMetadataRows.noteInfoRows(
            item: StudyItemMetadata.defaultMetadata(for: item),
            markdown: "> Provider: mockNoteGenerationProvider\n> Model: mock-note-local\n\n## 基本信息\n- 生成时间：2026-05-19 20:00\n\n## 摘要\n摘要",
            receiveRecord: nil
        )
        let text = rows.map { "\($0.label)=\($0.value)" }.joined(separator: " ")

        #expect(text.contains("生成时间=2026-05-19 20:00"))
        #expect(text.contains("Note Provider=Mock"))
        #expect(text.contains("模型=mock-note-local"))
    }

    @Test func aiNotePromptsRequireShortSummarySection() {
        let request = makeNoteGenerationRequest(transcriptMarkdown: "今天学习矩阵。")
        let openAIMessages = OpenAICompatibleNoteGenerationProvider.messages(
            request: request,
            transcript: "今天学习矩阵。",
            configuration: OpenAICompatibleNoteGenerationConfiguration(),
            wasTruncated: false
        )
        let anthropicPrompt = AnthropicMessagesNoteGenerationProvider.prompt(
            request: request,
            transcript: "今天学习矩阵。",
            configuration: AnthropicMessagesConfiguration(),
            wasTruncated: false
        )
        let openAIText = openAIMessages.map { $0.content }.joined(separator: "\n")

        #expect(openAIText.contains("## 摘要"))
        #expect(openAIText.contains("1～3 句简短摘要"))
        #expect(anthropicPrompt.contains("## 摘要"))
        #expect(anthropicPrompt.contains("1～3 句简短摘要"))
    }

    @Test func documentReadingPagesDefaultToContentOnlyMetadataBehindInfoButton() {
        #expect(RokuricsDocumentReadingLayout.defaultShowsMetadataCards == false)
    }

    @Test func recordingDetailDefaultInfoHidesRecordingIDButAdvancedKeepsFileState() {
        let item = makeInboxItem(
            transcriptionStatus: "transcribed",
            transcriptionError: nil,
            transcriptMarkdownRelativePath: "transcripts/2026-05-16/recording-01/transcript.md",
            noteStatus: "generated",
            noteRelativePath: "notes/2026-05-16/recording-01/note.md"
        )

        let rows = StudyRecordingFileStatusRows.rows(for: StudyItemMetadata.defaultMetadata(for: item))
        let defaultText = rows
            .filter { !$0.isTechnical }
            .map(\.value)
            .joined(separator: " ")
        let advancedText = rows
            .map(\.value)
            .joined(separator: " ")

        #expect(!defaultText.contains(item.id))
        #expect(advancedText.contains(item.id))
        #expect(advancedText.contains("transcripts/2026-05-16/recording-01/transcript.md"))
        #expect(advancedText.contains("notes/2026-05-16/recording-01/note.md"))
    }

    @Test func rawProviderIDsMapToUserFacingDisplayNames() {
        #expect(RokuricsProviderDisplayName.note("mockNoteGenerationProvider") == "Mock")
        #expect(RokuricsProviderDisplayName.note("openAICompatible") == "OpenAI-compatible")
        #expect(RokuricsProviderDisplayName.note("anthropicMessages") == "Claude / Anthropic")
        #expect(RokuricsProviderDisplayName.transcription("mockTranscriptionProvider") == "Mock")
        #expect(RokuricsProviderDisplayName.transcription("whisper.cpp") == "whisper.cpp")
    }

    @Test func sidebarDoesNotContainTopLevelTranscriptionItem() {
        #expect(!MacSidebarItem.allCases.map(\.title).contains("转写"))
    }

    @Test func sidebarDoesNotContainTopLevelNotesItem() {
        #expect(!MacSidebarItem.allCases.map(\.title).contains("笔记"))
        #expect(!MacSidebarItem.allCases.map(\.title).contains("仪表盘"))
        #expect(MacSidebarItem.allCases.map(\.title) == ["学习库", "AI 对话", "iPhone 连接"])
    }

    @Test func temporaryDebugMarkersAreRemovedFromPrimaryUIFiles() throws {
        let markers = [
            "09" + "19", "09" + "21", "10" + "03", "10" + "25", "10" + "51", "11" + "21",
            "11" + "36", "13" + "22", "14" + "58", "17" + "18", "17" + "42"
        ]
        let repoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let relativePaths = [
            "RokuricsMac/MacSettingsView.swift",
            "RokuricsMac/MacStudyLibraryView.swift",
            "Rokurics/RecordingLibraryView.swift"
        ]

        for relativePath in relativePaths {
            let text = try String(contentsOf: repoURL.appendingPathComponent(relativePath), encoding: .utf8)
            for marker in markers {
                #expect(!text.contains("Text(\"\(marker)\")"))
            }
        }
    }

    @Test func macSettingsSectionsUseKikariaStyleHomeGroups() {
        #expect(MacSettingsSection.allCases.map(\.rawValue) == [
            "userProfile",
            "transcription",
            "ai",
            "about"
        ])
        #expect(MacSettingsHomeSummary.sectionOrder.map(\.title) == [
            "用户资料",
            "转写",
            "AI",
            "关于"
        ])
        #expect(!MacSettingsSection.allCases.map(\.title).contains("连接"))
    }

    @Test func macSettingsHomeUsesReducedRowArchitecture() {
        #expect(MacSettingsHomeSummary.transcriptionRows == [
            "Provider",
            "模型",
            "授权与测试"
        ])
        #expect(MacSettingsHomeSummary.aiRows == [
            "Provider",
            "模型",
            "API 设置",
            "测试"
        ])
        #expect(MacSettingsHomeSummary.aboutRows == [
            "存储",
            "隐私政策",
            "版权"
        ])
    }

    @Test func macSettingsHomeCanOpenPrimaryDetailPages() {
        #expect(MacSettingsDetail.allCases.map(\.rawValue) == [
            "profile",
            "transcriptionProvider",
            "transcriptionModel",
            "transcriptionAuthorization",
            "aiProvider",
            "aiModel",
            "aiAPI",
            "aiTest",
            "privacyPolicy",
            "copyright"
        ])
        #expect(MacSettingsDetail.allCases.map(\.title) == [
            "编辑个人资料",
            "转写 Provider",
            "转写模型",
            "授权与测试",
            "AI Provider",
            "AI 模型",
            "API 设置",
            "测试",
            "隐私政策",
            "版权"
        ])
    }

    @Test func macSettingsStorageLocationUsesRokuricsApplicationSupportRoot() throws {
        let rootURL = MacSettingsStorageLocation.rootURL()

        #expect(rootURL.lastPathComponent == MacAppStorageProfile.applicationSupportFolderName)
        #expect(rootURL.path.contains("Application Support"))
        #expect(!rootURL.path.contains("/Desktop/"))
        #expect(!rootURL.path.contains("/Downloads/"))
        #expect(!rootURL.path.contains("/Documents/"))
    }

    @Test func macSettingsHomeSummaryHidesSensitiveAndVerboseConfiguration() {
        var whisperConfiguration = WhisperCppTranscriptionConfiguration.default
        whisperConfiguration.modelPath = "/tmp/rokurics/models/ggml-large-v3.bin"
        whisperConfiguration.defaultLanguage = "zh"
        let openAIConfiguration = OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: "https://secret.example/v1",
            modelName: "deepseek-v4-pro",
            apiKey: "visible-secret"
        )
        let anthropicConfiguration = AnthropicMessagesConfiguration(
            baseURLString: "https://api.anthropic.com",
            modelName: "claude-sonnet-4-6",
            apiKey: "claude-secret"
        )

        let homepageText = MacSettingsHomeSummary.homepageSummaryTexts(
            transcriptionProviderKind: .whisperCpp,
            whisperConfiguration: whisperConfiguration,
            noteProviderKind: .openAICompatible,
            openAIConfiguration: openAIConfiguration,
            anthropicConfiguration: anthropicConfiguration
        ).joined(separator: " ")

        #expect(homepageText.contains("ggml-large-v3.bin"))
        #expect(homepageText.contains("deepseek-v4-pro"))
        #expect(!homepageText.contains("/tmp/rokurics/models"))
        #expect(!homepageText.contains("https://secret.example/v1"))
        #expect(!homepageText.contains("visible-secret"))
        #expect(!homepageText.contains("claude-secret"))
    }

    @Test func macProfileDefaultsUseSeparateLocalProfileKeys() {
        #expect(MacSettingsProfileDefaults.displayName == MacUserProfile.defaultDisplayName)
        #expect(MacSettingsProfileDefaults.handle == MacUserProfile.defaultHandle)
        #expect(MacSettingsProfileDefaults.displayHandle(MacUserProfile.defaultHandle) == "@\(MacUserProfile.defaultHandle)")
        #expect(MacSettingsProfileDefaults.normalizedHandle(" @Custom ") == "Custom")
        #expect(MacSettingsProfileDefaults.displayNameKey.contains("profile"))
        #expect(!MacSettingsProfileDefaults.displayNameKey.contains("apiKey"))
        #expect(MacUserProfile.defaultDisplayName != "Vita")
        #expect(MacUserProfile.defaultHandle != "Vita_0818")
    }

    @Test func macDesignSystemCircleIconConfigurationIsUnifiedGlass() {
        #expect(RokuricsCircleIconButtonConfiguration.size >= 34)
        #expect(RokuricsCircleIconButtonConfiguration.size <= 38)
        #expect(RokuricsCircleIconButtonConfiguration.iconSize > 0)
        #expect(RokuricsCircleIconButtonConfiguration.usesGlassBackground)
        #expect(RokuricsCircleIconButtonConfiguration.borderWidth == 1)
        #expect(RokuricsCircleIconButton.size == RokuricsCircleIconButtonConfiguration.size)
    }

    @Test func macNavigationIconButtonsUseSystemSymbolsWithoutVisibleBackText() {
        #expect(RokuricsBackButton.systemImage == "chevron.left")
        #expect(RokuricsBackButton.visibleTitle.isEmpty)
        #expect(RokuricsBackButton.accessibilityTitle == "返回")
        #expect(RokuricsInfoButton.systemImage == "info")
        #expect(RokuricsInfoButton.visibleTitle.isEmpty)
        #expect(RokuricsCircleIconButtonConfiguration.usesSystemSymbols)
    }

    @Test func mixedTypographyKeepsTechnicalRunsScoped() {
        let fragments: [RokuricsTextFragment] = [
            .text("Provider: ", style: .body),
            .technical("OpenAI-compatible"),
            .text(" 已启用", style: .body)
        ]

        #expect(fragments[0].kind == .normal(.body))
        #expect(fragments[1].kind == .technical)
        #expect(fragments[2].kind == .normal(.body))
    }

    @Test func macStudyLibraryTitleUsesPageTitleToken() {
        #expect(MacStudyLibraryHeaderModel.title == "学习库")
        #expect(MacStudyLibraryHeaderModel.titleStyle == .pageTitle)
    }

    @Test func macSettingsProfileSummaryMatchesKikariaMinimalText() {
        let summary = MacSettingsProfileDefaults.profileSummaryTexts(
            displayName: "Mira",
            handle: "mira_01"
        )
        let visibleText = summary.joined(separator: " ")

        #expect(summary == ["Mira", "@mira_01"])
        #expect(!visibleText.contains("Local" + "-first"))
        #expect(!visibleText.contains("学习" + "助手"))
        #expect(!visibleText.contains("Rokurics" + " Mac"))
    }

    @Test func macEditProfileFieldsMatchKikariaTwoFieldStructure() {
        let fieldTitles = MacSettingsProfileDefaults.editFieldTitles

        #expect(fieldTitles == ["显示名称", "用户 ID"])
        #expect(!fieldTitles.contains("身" + "份"))
        #expect(!fieldTitles.contains("说" + "明"))
    }

    @Test func macProfileSaveNormalizationKeepsDisplayNameAndHandle() {
        #expect(MacSettingsProfileDefaults.normalized("  Vivian  ", fallback: MacSettingsProfileDefaults.displayName) == "Vivian")
        #expect(MacSettingsProfileDefaults.normalizedHandle(" @vivian_01 ") == "vivian_01")
    }

    @Test @MainActor func macUserProfileStorePersistsDisplayNameAndHandle() {
        let suiteName = "RokuricsMacTests.Profile.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MacUserProfileStore(userDefaults: defaults)

        store.update(displayName: "  Vivian  ", handle: " @vivian ")
        let reloaded = MacUserProfileStore(userDefaults: defaults)

        #expect(reloaded.profile.displayName == "Vivian")
        #expect(reloaded.profile.handle == "vivian")
        #expect(reloaded.profile.displayHandle == "@vivian")
    }

    @Test func studyLibraryHeaderUsesPageTitleTypography() {
        #expect(MacStudyLibraryHeaderModel.title == "学习库")
        #expect(!MacStudyLibraryHeaderModel.showsLeadingIcon)
        #expect(MacStudyLibraryHeaderModel.titleStyle == .pageTitle)
    }

    @Test func macTypographyDefinesSeparateChatAndPageTokens() {
        #expect(RokuricsTextStyle.pageTitle != .chatGreeting)
        #expect(RokuricsTextStyle.chatInput != .pageTitle)
        #expect(RokuricsTextStyle.technical != .body)
    }

    @Test func primaryMacUIFilesDoNotHardcodeDefaultUserName() throws {
        let repoURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let literal = "Vi" + "ta"
        let relativePaths = [
            "RokuricsMac/MacAIChatView.swift",
            "RokuricsMac/MacSidebarView.swift",
            "RokuricsMac/MacSettingsView.swift"
        ]

        for relativePath in relativePaths {
            let text = try String(contentsOf: repoURL.appendingPathComponent(relativePath), encoding: .utf8)
            #expect(!text.contains("\"\(literal)\""))
        }
    }

    @Test func studyLibraryRecordingDetailNavigationRestoresBrowsePath() {
        let originalPath = StudyBrowsePath(components: ["课堂", "线性代数", "矩阵", "矩阵乘法"])
        var state = MacStudyLibraryNavigationState(browsePath: originalPath)

        state.openRecordingDetail(recordingID: "recording-01")

        #expect(state.isShowingRecordingDetail)
        #expect(state.selectedRecordingDetailID == "recording-01")
        #expect(state.detailReturnPath == originalPath)

        state.browsePath = StudyBrowsePath()
        state.closeRecordingDetail()

        #expect(!state.isShowingRecordingDetail)
        #expect(state.selectedRecordingDetailID == nil)
        #expect(state.browsePath == originalPath)
    }

    @Test func dashboardDoesNotContainTranscriptionQueueCard() {
        #expect(!MacDashboardCardKind.visibleCards.map(\.title).contains("转写队列"))
    }

    @Test func macRenameInboxItemUpdatesNormalizedTitle() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-rename-01", title: "原始标题", store: store)

        let item = try store.updateDisplayTitle(recordingID: "mac-rename-01", rawTitle: " 新标题 ")
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-rename-01")

        #expect(item.title == "新标题")
        #expect(record.normalizedTitle == "新标题")
    }

    @Test func macRenameDoesNotOverwriteOriginalTitle() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-rename-02", title: "上传标题", store: store)

        _ = try store.updateDisplayTitle(recordingID: "mac-rename-02", rawTitle: "Mac 标题")
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-rename-02")

        #expect(record.originalTitle == "上传标题")
        #expect(record.normalizedTitle == "Mac 标题")
    }

    @Test func metadataFirstUploadCreatesMetadataOnlyReceiveState() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "idempotent-01")

        let result = try store.saveMetadata(metadata, sourceDevice: device)
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)

        #expect(result.disposition == .acceptedNew)
        #expect(record.status == "metadataReceived")
        #expect(record.processingStatus == "awaitingAudio")
        #expect(record.audioRelativePath == nil)
        #expect(record.checksum == nil)
        #expect(record.lastUploadError == nil)
        #expect(record.lastUploadAttemptAt != nil)
    }

    @Test func macMetadataOnlyInboxItemShowsWaitingAudioActionState() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "ui-waiting-audio")

        _ = try store.saveMetadata(metadata, sourceDevice: device)

        let item = try #require(store.loadInboxItems().first { $0.id == metadata.id })
        let progress = try #require(item.localNetworkReceiveTransferProgress)
        #expect(!item.hasAudio)
        #expect(item.audioRelativePath == nil)
        #expect(progress.state == .transferring)
        #expect(progress.statusText == "正在接收")
        #expect(progress.totalBytes == metadata.fileSize)
    }

    @Test func repeatedIdenticalMetadataIsIdempotentSuccess() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "idempotent-02", title: "原始标题")
        let compatibleUpdate = makeIncomingUploadMetadata(id: "idempotent-02", title: "不应覆盖的标题")

        let firstResult = try store.saveMetadata(metadata, sourceDevice: device)
        let metadataURL = firstResult.directoryURL.appendingPathComponent("metadata.json", isDirectory: false)
        let storedBeforeRetry = try readIncomingMetadata(at: metadataURL)
        let firstRecord = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
        Thread.sleep(forTimeInterval: 0.01)
        let result = try store.saveMetadata(compatibleUpdate, sourceDevice: device)
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
        let storedAfterRetry = try readIncomingMetadata(at: metadataURL)

        #expect(result.disposition == .acceptedExisting)
        #expect(record.originalTitle == "原始标题")
        #expect(record.status == "metadataReceived")
        #expect(record.processingStatus == "awaitingAudio")
        #expect(record.lastUploadError == nil)
        #expect((record.lastUploadAttemptAt?.timeIntervalSince(firstRecord.lastUploadAttemptAt ?? .distantPast) ?? -1) > 0)
        #expect(storedBeforeRetry.title == "原始标题")
        #expect(storedAfterRetry.title == "原始标题")
    }

    @Test func repeatedConflictingMetadataIsRejected() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "idempotent-03", fileSize: 5)
        let conflicting = makeIncomingUploadMetadata(id: "idempotent-03", fileSize: 6)

        _ = try store.saveMetadata(metadata, sourceDevice: device)
        let firstRecord = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
        Thread.sleep(forTimeInterval: 0.01)

        do {
            _ = try store.saveMetadata(conflicting, sourceDevice: device)
            Issue.record("Expected conflicting metadata to be rejected")
        } catch MacRecordingFileStoreError.metadataConflict {
            let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
            #expect(record.lastUploadError == "metadata_conflict")
            #expect(record.lastUploadError?.contains(device.sharedSecretBase64URL) == false)
            #expect((record.lastUploadAttemptAt?.timeIntervalSince(firstRecord.lastUploadAttemptAt ?? .distantPast) ?? -1) > 0)
        }
    }

    @Test func audioUploadAfterMetadataOnlyRecordCompletesReceiveState() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "idempotent-04")
        let audio = Data("audio".utf8)

        _ = try store.saveMetadata(metadata, sourceDevice: device)
        let result = try await store.saveAudio(body: audio, recordingID: metadata.id, requestedFileName: metadata.originalFileName, sourceDevice: device)
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)

        #expect(result.disposition == .acceptedNew)
        #expect(record.status == "completed")
        #expect(record.processingStatus == "notStarted")
        #expect(record.audioRelativePath?.hasSuffix("/audio.m4a") == true)
        #expect(record.checksum == MacSecurityUtilities.sha256Hex(audio))
        #expect(record.lastUploadError == nil)
    }

    @MainActor
    @Test func macSyncInventoryReportsReceivedAudioAvailableWithChecksumAndSize() async throws {
        let fileManager = FileManager.default
        let rootURL = try makeScratchDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Library", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let pairingManager = PairingManager(pairedDeviceStore: pairedDeviceStore)
        let identityManager = MacIdentityManager(
            securityDirectoryURL: securityURL,
            tlsKeyTagNamespace: "inventory-test-\(UUID().uuidString)"
        )
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: identityManager,
            pairingManager: pairingManager,
            requestVerifier: RequestVerifier(pairedDeviceStore: pairedDeviceStore),
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingFileStore,
            studyLibraryStore: studyLibraryStore,
            gitBackedStudyMetadataStore: nil,
            deviceConnectionStatusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL),
            onReady: {},
            onFailed: { _ in },
            onPairingChanged: {},
            onUploadAccepted: { _ in },
            onRecordingAccepted: { _, _ in }
        )
        defer { server.stop() }
        let device = makeUploadDevice()
        let audio = Data("inventory-audio".utf8)
        let metadata = makeIncomingUploadMetadata(id: "inventory-audio-available", fileSize: Int64(audio.count))

        _ = try recordingFileStore.saveMetadata(metadata, sourceDevice: device)
        _ = try await recordingFileStore.saveAudio(body: audio, recordingID: metadata.id, requestedFileName: metadata.originalFileName, sourceDevice: device)

        let inventory = try #require(await server.localNetworkSyncInventoryResponseForVerifiedDevice(device, syncRunID: "inventory-test").inventory)
        let recording = try #require(inventory.recordings.first { $0.recordingID == metadata.id })
        let audioObject = try #require(inventory.objects.first { $0.objectID == "recordingAudio:\(metadata.id)" })

        #expect(recording.audioAvailable)
        #expect(recording.audioAvailability == .local)
        #expect(recording.audioChecksum == MacSecurityUtilities.sha256Hex(audio))
        #expect(recording.audioSize == Int64(audio.count))
        #expect(recording.sourceDeviceID == device.id)
        #expect(recording.audioLogicalPathToken?.hasSuffix("/audio.m4a") == true)
        #expect(audioObject.availability == .local)
        #expect(audioObject.sha256 == MacSecurityUtilities.sha256Hex(audio))
        #expect(audioObject.size == Int64(audio.count))
        #expect(audioObject.sourceDeviceID == device.id)
        #expect(audioObject.logicalPathToken?.hasSuffix("/audio.m4a") == true)
    }

    @MainActor
    @Test func macInventoryRequestMarksManualSyncPendingAsStarted() async throws {
        let fileManager = FileManager.default
        let rootURL = try makeScratchDirectory()
        defer { try? fileManager.removeItem(at: rootURL) }
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Library", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let pairingManager = PairingManager(pairedDeviceStore: pairedDeviceStore)
        let identityManager = MacIdentityManager(
            securityDirectoryURL: securityURL,
            tlsKeyTagNamespace: "inventory-observed-\(UUID().uuidString)"
        )
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        var diagnosticPhases: [String] = []
        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: identityManager,
            pairingManager: pairingManager,
            requestVerifier: RequestVerifier(pairedDeviceStore: pairedDeviceStore),
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingFileStore,
            studyLibraryStore: studyLibraryStore,
            gitBackedStudyMetadataStore: nil,
            deviceConnectionStatusStore: statusStore,
            syncStateStore: syncStateStore,
            onReady: {},
            onFailed: { _ in },
            onPairingChanged: {},
            onUploadAccepted: { _ in },
            onRecordingAccepted: { _, _ in },
            onConnectionDiagnostic: { event in
                diagnosticPhases.append(event.phase)
            }
        )
        defer { server.stop() }
        let device = makeHeartbeatDevice()
        let syncRunID = "inventory-observed-sync"
        _ = statusStore.recordPendingSyncRequest(
            deviceID: device.id,
            displayName: device.deviceName,
            syncRunID: syncRunID,
            initiatorDeviceID: "mac-test"
        )

        _ = await server.localNetworkSyncInventoryResponseForVerifiedDevice(device, syncRunID: syncRunID)

        #expect(statusStore.status(for: device.id)?.lastSyncStatus == "iPhone 已开始同步")
        #expect(syncStateStore.state.syncControlPlaneState == .inventoryExchanging)
        #expect(diagnosticPhases.contains("manualSyncRequestedInventoryObserved"))
        #expect(diagnosticPhases.contains("manualSyncRequestedConsumedByPeer"))
    }

    @Test func macAudioAvailableInboxItemClearsWaitingActionState() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "ui-audio-available")

        _ = try store.saveMetadata(metadata, sourceDevice: device)
        _ = try await store.saveAudio(body: Data("audio".utf8), recordingID: metadata.id, requestedFileName: metadata.originalFileName, sourceDevice: device)

        let item = try #require(store.loadInboxItems().first { $0.id == metadata.id })
        #expect(item.hasAudio)
        #expect(item.audioRelativePath?.hasSuffix("/audio.m4a") == true)
        #expect(item.localNetworkReceiveTransferProgress == nil)
    }

    @MainActor
    @Test func macReceiveUpdateRefreshesAudioInboxStoreWithoutRestart() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "ui-receive-refresh")

        _ = try store.saveMetadata(metadata, sourceDevice: device)
        let inboxStore = AudioInboxStore(recordingFileStore: store)
        let waitingItem = try #require(inboxStore.recordingItems.first { $0.id == metadata.id })
        #expect(waitingItem.localNetworkReceiveTransferProgress?.state == .transferring)
        #expect(waitingItem.localNetworkReceiveTransferProgress?.statusText?.isEmpty == false)

        _ = try await store.saveAudio(body: Data("audio".utf8), recordingID: metadata.id, requestedFileName: metadata.originalFileName, sourceDevice: device)
        let deadline = Date().addingTimeInterval(0.2)
        while Date() < deadline,
              inboxStore.recordingItems.first(where: { $0.id == metadata.id })?.hasAudio != true {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        let refreshedItem = try #require(inboxStore.recordingItems.first { $0.id == metadata.id })
        #expect(refreshedItem.hasAudio)
        #expect(refreshedItem.localNetworkReceiveTransferProgress == nil)
    }

    @Test func repeatedIdenticalAudioIsIdempotentSuccess() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "idempotent-05")
        let audio = Data("audio".utf8)

        _ = try store.saveMetadata(metadata, sourceDevice: device)
        _ = try await store.saveAudio(body: audio, recordingID: metadata.id, requestedFileName: metadata.originalFileName, sourceDevice: device)
        let firstRecord = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
        Thread.sleep(forTimeInterval: 0.01)
        let result = try await store.saveAudio(body: audio, recordingID: metadata.id, requestedFileName: "retry-name.m4a", sourceDevice: device)
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
        let audioURL = rootURL.appendingPathComponent(record.audioRelativePath ?? "", isDirectory: false)

        #expect(result.disposition == .acceptedExisting)
        #expect(record.status == "completed")
        #expect(record.checksum == MacSecurityUtilities.sha256Hex(audio))
        #expect(record.fileSize == Int64(audio.count))
        #expect(record.lastUploadError == nil)
        #expect(record.originalAudioFileName == metadata.originalFileName)
        #expect((record.lastUploadAttemptAt?.timeIntervalSince(firstRecord.lastUploadAttemptAt ?? .distantPast) ?? -1) > 0)
        #expect(try Data(contentsOf: audioURL) == audio)
    }

    @Test func repeatedConflictingAudioIsRejected() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "idempotent-06")

        _ = try store.saveMetadata(metadata, sourceDevice: device)
        _ = try await store.saveAudio(body: Data("audio".utf8), recordingID: metadata.id, requestedFileName: metadata.originalFileName, sourceDevice: device)
        let firstRecord = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
        Thread.sleep(forTimeInterval: 0.01)

        do {
            _ = try await store.saveAudio(body: Data("different-audio".utf8), recordingID: metadata.id, requestedFileName: metadata.originalFileName, sourceDevice: device)
            Issue.record("Expected conflicting audio to be rejected")
        } catch MacRecordingFileStoreError.audioConflict {
            let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
            #expect(record.lastUploadError == "audio_conflict")
            #expect(record.lastUploadError?.contains(device.sharedSecretBase64URL) == false)
            #expect((record.lastUploadAttemptAt?.timeIntervalSince(firstRecord.lastUploadAttemptAt ?? .distantPast) ?? -1) > 0)
        }
    }

    @MainActor
    @Test func metadataConflictRouteReturns409JSONWithoutSecret() async throws {
        let (handler, store, rootURL, device) = try makeRecordingUploadRouteHandler()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = makeIncomingUploadMetadata(id: "route-metadata-conflict", fileSize: 5)
        let conflicting = makeIncomingUploadMetadata(id: "route-metadata-conflict", fileSize: 6)
        let metadataBody = try encodedMetadata(metadata)
        let conflictingBody = try encodedMetadata(conflicting)

        _ = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-metadata", body: metadataBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-metadata-first"),
            body: metadataBody
        )
        let response = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-metadata", body: conflictingBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: conflicting.id, fileName: conflicting.originalFileName, nonce: "nonce-route-metadata-conflict"),
            body: conflictingBody
        )
        let json = try routeResponseJSON(response)
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)

        #expect(response.statusCode == 409)
        #expect(json["ok"] as? Bool == false)
        #expect(json["error"] as? String == "recording_metadata_conflict")
        #expect(json["disposition"] as? String == RecordingUploadDisposition.rejectedConflict.rawValue)
        #expect(json["reason"] as? String == "Conflict")
        #expect(String(data: response.bodyData, encoding: .utf8)?.contains(device.sharedSecretBase64URL) == false)
        #expect(record.lastUploadError == "metadata_conflict")
        #expect(store.loadInboxItems().count == 1)
    }

    @MainActor
    @Test func audioConflictRouteReturns409JSONWithoutSecret() async throws {
        let (handler, _, rootURL, device) = try makeRecordingUploadRouteHandler()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = makeIncomingUploadMetadata(id: "route-audio-conflict")
        let metadataBody = try encodedMetadata(metadata)
        let audio = Data("audio".utf8)
        let conflictingAudio = Data("different-audio".utf8)

        _ = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-metadata", body: metadataBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-audio-metadata"),
            body: metadataBody
        )
        _ = await handler.audioUploadResponse(
            method: "POST",
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio", body: audio, contentType: "audio/m4a", uploadType: "recording-audio", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-audio-first"),
            body: audio
        )
        let response = await handler.audioUploadResponse(
            method: "POST",
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio", body: conflictingAudio, contentType: "audio/m4a", uploadType: "recording-audio", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-audio-conflict"),
            body: conflictingAudio
        )
        let json = try routeResponseJSON(response)
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)

        #expect(response.statusCode == 409)
        #expect(json["ok"] as? Bool == false)
        #expect(json["error"] as? String == "recording_audio_conflict")
        #expect(json["disposition"] as? String == RecordingUploadDisposition.rejectedConflict.rawValue)
        #expect(json["reason"] as? String == "Conflict")
        #expect(String(data: response.bodyData, encoding: .utf8)?.contains(device.sharedSecretBase64URL) == false)
        #expect(record.lastUploadError == "audio_conflict")
    }

    @MainActor
    @Test func repeatedIdenticalMetadataRouteReturnsAcceptedExisting() async throws {
        let (handler, _, rootURL, device) = try makeRecordingUploadRouteHandler()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = makeIncomingUploadMetadata(id: "route-metadata-existing")
        let body = try encodedMetadata(metadata)

        _ = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-metadata", body: body, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-existing-first"),
            body: body
        )
        let response = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-metadata", body: body, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-existing-second"),
            body: body
        )
        let json = try routeResponseJSON(response)

        #expect(response.statusCode == 200)
        #expect(json["ok"] as? Bool == true)
        #expect(json["disposition"] as? String == RecordingUploadDisposition.acceptedExisting.rawValue)
        #expect(json["receiveStatus"] as? String == "metadataReceived")
        #expect(json["processingStatus"] as? String == "awaitingAudio")
    }

    @MainActor
    @Test func repeatedIdenticalAudioRouteReturnsAcceptedExisting() async throws {
        let (handler, _, rootURL, device) = try makeRecordingUploadRouteHandler()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = makeIncomingUploadMetadata(id: "route-audio-existing")
        let metadataBody = try encodedMetadata(metadata)
        let audio = Data("audio".utf8)

        _ = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-metadata", body: metadataBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-audio-existing-metadata"),
            body: metadataBody
        )
        _ = await handler.audioUploadResponse(
            method: "POST",
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio", body: audio, contentType: "audio/m4a", uploadType: "recording-audio", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-audio-existing-first"),
            body: audio
        )
        let response = await handler.audioUploadResponse(
            method: "POST",
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio", body: audio, contentType: "audio/m4a", uploadType: "recording-audio", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-audio-existing-second"),
            body: audio
        )
        let json = try routeResponseJSON(response)

        #expect(response.statusCode == 200)
        #expect(json["ok"] as? Bool == true)
        #expect(json["disposition"] as? String == RecordingUploadDisposition.acceptedExisting.rawValue)
        #expect(json["receiveStatus"] as? String == "completed")
        #expect(json["processingStatus"] as? String == "notStarted")
    }

    @MainActor
    @Test func tracedMetadataAndAudioRouteCompletesInboxAvailability() async throws {
        let (handler, store, rootURL, device) = try makeRecordingUploadRouteHandler()
        defer {
            UploadFlightRecorder.configureLogURL(nil)
            try? FileManager.default.removeItem(at: rootURL)
        }
        let traceID = "upl-test-mac-route-complete"
        let traceURL = rootURL.appendingPathComponent("upload-trace.jsonl", isDirectory: false)
        UploadFlightRecorder.configureLogURL(traceURL)
        let metadata = makeIncomingUploadMetadata(id: "route-trace-complete")
        let metadataBody = try encodedMetadata(metadata)
        let audio = Data("audio".utf8)
        var metadataHeaders = try signedUploadHeaders(
            device: device,
            path: "/upload-recording-metadata",
            body: metadataBody,
            contentType: "application/json",
            uploadType: "recording-metadata",
            recordingID: metadata.id,
            fileName: metadata.originalFileName,
            nonce: "nonce-route-trace-metadata"
        )
        metadataHeaders[UploadFlightRecorder.traceHeaderName] = traceID
        var audioHeaders = try signedUploadHeaders(
            device: device,
            path: "/upload-recording-audio",
            body: audio,
            contentType: "audio/m4a",
            uploadType: "recording-audio",
            recordingID: metadata.id,
            fileName: metadata.originalFileName,
            nonce: "nonce-route-trace-audio"
        )
        audioHeaders[UploadFlightRecorder.traceHeaderName] = traceID

        let metadataResponse = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: metadataHeaders,
            body: metadataBody
        )
        let audioResponse = await handler.audioUploadResponse(
            method: "POST",
            path: "/upload-recording-audio",
            headers: audioHeaders,
            body: audio
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
        let inboxStore = AudioInboxStore(recordingFileStore: store)
        let inboxItem = try #require(inboxStore.recordingItems.first(where: { $0.id == metadata.id }))
        UploadFlightRecorder.flushForTests()
        let events = try UploadFlightRecorder.loadEvents(from: traceURL)
        let stages = Set(events.map(\.stage))
        let rawTrace = try String(contentsOf: traceURL, encoding: .utf8)

        #expect(metadataResponse.statusCode == 200)
        #expect(audioResponse.statusCode == 200)
        #expect(record.status == "completed")
        #expect(record.processingStatus == "notStarted")
        #expect(record.audioRelativePath != nil)
        #expect(record.checksum == MacSecurityUtilities.sha256Hex(audio))
        #expect(inboxItem.hasAudio)
        #expect(stages.contains("requestVerifierAccepted"))
        #expect(stages.contains("uploadRouteHandlerEntered"))
        #expect(stages.contains("metadataPayloadDecoded"))
        #expect(stages.contains("receiveRecordWaitingForAudio"))
        #expect(stages.contains("audioRouteRecordingIDParsed"))
        #expect(stages.contains("audioChecksumComputed"))
        #expect(stages.contains("audioFileWriteCompleted"))
        #expect(stages.contains("receiveRecordAudioPathUpdated"))
        #expect(stages.contains("receiveRecordSavedAfterAudio"))
        #expect(stages.contains("audioInboxItemMarkedAvailable"))
        #expect(stages.contains("macUICardStateUpdated"))
        #expect(events.allSatisfy { $0.traceID == traceID })
        #expect(!rawTrace.contains(device.sharedSecretBase64URL))
        #expect(!rawTrace.contains(rootURL.path))
    }

    @MainActor
    @Test func tracedBadHMACUploadRouteRecordsVerifierRejectionWithoutStoreWrite() async throws {
        let (handler, store, rootURL, device) = try makeRecordingUploadRouteHandler()
        defer {
            UploadFlightRecorder.configureLogURL(nil)
            try? FileManager.default.removeItem(at: rootURL)
        }
        let traceID = "upl-test-mac-bad-hmac"
        let traceURL = rootURL.appendingPathComponent("upload-trace.jsonl", isDirectory: false)
        UploadFlightRecorder.configureLogURL(traceURL)
        let metadata = makeIncomingUploadMetadata(id: "route-trace-bad-hmac")
        let body = try encodedMetadata(metadata)
        var headers = try signedUploadHeaders(
            device: device,
            path: "/upload-recording-metadata",
            body: body,
            contentType: "application/json",
            uploadType: "recording-metadata",
            recordingID: metadata.id,
            fileName: metadata.originalFileName,
            nonce: "nonce-route-trace-bad-hmac"
        )
        headers["X-Rokurics-Signature"] = "bad-signature"
        headers[UploadFlightRecorder.traceHeaderName] = traceID

        let response = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: headers,
            body: body
        )
        UploadFlightRecorder.flushForTests()
        let stages = Set(try UploadFlightRecorder.loadEvents(from: traceURL).map(\.stage))
        let rawTrace = try String(contentsOf: traceURL, encoding: .utf8)

        #expect(response.statusCode == 400)
        #expect((try routeResponseJSON(response))["error"] as? String == "signature_mismatch")
        #expect(stages.contains("requestVerifierEntered"))
        #expect(stages.contains("requestVerifierHMACRejected"))
        #expect(!stages.contains("metadataPayloadDecoded"))
        #expect(store.loadInboxItems().isEmpty)
        #expect(!rawTrace.contains(device.sharedSecretBase64URL))
        #expect(!rawTrace.contains(rootURL.path))
    }

    @MainActor
    @Test func badSignatureAndUnpairedUploadRoutesAreRejectedBeforeStoreWrite() async throws {
        let (handler, store, rootURL, device) = try makeRecordingUploadRouteHandler()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let metadata = makeIncomingUploadMetadata(id: "route-security-rejected")
        let body = try encodedMetadata(metadata)
        var badSignatureHeaders = try signedUploadHeaders(
            device: device,
            path: "/upload-recording-metadata",
            body: body,
            contentType: "application/json",
            uploadType: "recording-metadata",
            recordingID: metadata.id,
            fileName: metadata.originalFileName,
            nonce: "nonce-route-bad-signature"
        )
        badSignatureHeaders["X-Rokurics-Signature"] = "bad-signature"

        let badSignatureResponse = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: badSignatureHeaders,
            body: body
        )
        let unpairedDevice = PairedDevice(
            id: "unknown-device",
            deviceName: "Unknown",
            sharedSecretBase64URL: Data("unknown-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
        let unpairedResponse = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: unpairedDevice, path: "/upload-recording-metadata", body: body, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-unpaired"),
            body: body
        )

        #expect(badSignatureResponse.statusCode == 400)
        #expect((try routeResponseJSON(badSignatureResponse))["error"] as? String == "signature_mismatch")
        #expect(unpairedResponse.statusCode == 400)
        #expect((try routeResponseJSON(unpairedResponse))["error"] as? String == "unknown_device")
        #expect(store.loadInboxItems().isEmpty)
    }

    @MainActor
    @Test func freshPairingBootstrapDoesNotRequireExistingHMACSharedSecret() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = PairedDeviceStore(rootURL: rootURL)
        let manager = PairingManager(pairedDeviceStore: store)
        let now = Date(timeIntervalSince1970: 3_000)
        manager.beginPairing(now: now)
        let code = try #require(manager.activeChallenge?.code)
        var pairingChangedCount = 0
        let handler = PairingBootstrapRouteHandler(
            pairingManager: manager,
            macName: "Test Mac",
            macModel: "Mac",
            onPairingChanged: { pairingChangedCount += 1 }
        )
        let body = Data(#"{"pairingCode":"\#(code)","deviceName":"Vita iPhone","deviceType":"iPhone"}"#.utf8)

        let response = handler.pairingResponse(
            method: "POST",
            path: "/pair",
            headers: ["Content-Type": "application/json"],
            body: body,
            now: now.addingTimeInterval(1)
        )
        let json = try routeResponseJSON(response)

        #expect(response.statusCode == 200)
        #expect(json["ok"] as? Bool == true)
        #expect(json["deviceID"] as? String != nil)
        #expect(json["sharedSecret"] as? String != nil)
        #expect(json["confirmationToken"] as? String != nil)
        #expect(pairingChangedCount == 0)
        #expect(store.devices.isEmpty)

        let deviceID = try #require(json["deviceID"] as? String)
        let confirmationToken = try #require(json["confirmationToken"] as? String)
        let confirmationBody = try JSONSerialization.data(withJSONObject: [
            "deviceID": deviceID,
            "confirmationToken": confirmationToken
        ])
        let confirmation = handler.pairingConfirmationResponse(
            method: "POST",
            path: "/pair/confirm",
            headers: ["Content-Type": "application/json"],
            body: confirmationBody,
            now: now.addingTimeInterval(2)
        )
        #expect(confirmation.statusCode == 200)
        #expect(pairingChangedCount == 1)
        #expect(store.devices.count == 1)
    }

    @MainActor
    @Test func preparedPairingCanCommitThroughSignedCredentialProofAfterConfirmLoss() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let manager = PairingManager(pairedDeviceStore: store)
        let now = Date()
        manager.beginPairing(now: now)
        let code = try #require(manager.activeChallenge?.code)
        let prepared = try #require(manager.preparePairing(
            deviceName: "Proof iPhone",
            deviceType: "iPhone",
            code: code,
            now: now.addingTimeInterval(1)
        ))
        #expect(store.device(for: prepared.device.id) == nil)

        let verifier = RequestVerifier(pairedDeviceStore: store, pairingManager: manager)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let handler = ConnectionHeartbeatRouteHandler(
            requestVerifier: verifier,
            statusStore: statusStore,
            localPeerDeviceID: "mac-proof-test"
        )
        let body = try encodedHeartbeatRequest(makeHeartbeatRequest(device: prepared.device, sequenceNumber: 1))
        let response = handler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: prepared.device,
                path: "/connection/heartbeat",
                body: body,
                nonce: "pairing-proof-heartbeat",
                now: now.addingTimeInterval(2)
            ),
            body: body,
            now: now.addingTimeInterval(2)
        )

        #expect(response.statusCode == 200)
        #expect(store.device(for: prepared.device.id)?.sharedSecretBase64URL == prepared.sharedSecretBase64URL)
        #expect(manager.state == .paired(deviceName: "Proof iPhone"))
    }

    @MainActor
    @Test func freshPairingBootstrapRejectsInvalidCodeWithoutCreatingSharedSecret() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = PairedDeviceStore(rootURL: rootURL)
        let manager = PairingManager(pairedDeviceStore: store)
        let now = Date(timeIntervalSince1970: 3_100)
        manager.beginPairing(now: now)
        var pairingChangedCount = 0
        let handler = PairingBootstrapRouteHandler(
            pairingManager: manager,
            macName: "Test Mac",
            macModel: "Mac",
            onPairingChanged: { pairingChangedCount += 1 }
        )
        let body = Data(#"{"pairingCode":"000000","deviceName":"Vita iPhone","deviceType":"iPhone"}"#.utf8)

        let response = handler.pairingResponse(
            method: "POST",
            path: "/pair",
            headers: ["Content-Type": "application/json"],
            body: body,
            now: now.addingTimeInterval(1)
        )
        let json = try routeResponseJSON(response)
        let rawBody = String(data: response.bodyData, encoding: .utf8) ?? ""

        #expect(response.statusCode == 400)
        #expect(json["ok"] as? Bool == false)
        #expect(json["error"] as? String == "invalid_pairing_code")
        #expect(rawBody.contains("sharedSecret") == false)
        #expect(pairingChangedCount == 1)
        #expect(store.devices.isEmpty)
    }

    @MainActor
    @Test func realHTTPSListenerFingerprintPairingAndHeartbeatSmoke() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("RokuricsRealListener-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        let identityManager = MacIdentityManager(
            securityDirectoryURL: rootURL.appendingPathComponent("Security", isDirectory: true),
            tlsKeyTagNamespace: "real-listener-\(UUID().uuidString)"
        )
        identityManager.loadOrCreateIdentity()
        #expect(identityManager.status.hasTLSIdentity)
        #expect(identityManager.status.certificateFingerprint.count == 64)

        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let pairingManager = PairingManager(pairedDeviceStore: pairedDeviceStore)
        let requestVerifier = RequestVerifier(
            pairedDeviceStore: pairedDeviceStore,
            pairingManager: pairingManager
        )
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Library", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let readySignal = ListenerReadySignal()
        let diagnosticRecorder = SecureConnectionDiagnosticRecorder()

        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: identityManager,
            pairingManager: pairingManager,
            requestVerifier: requestVerifier,
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingFileStore,
            studyLibraryStore: studyLibraryStore,
            gitBackedStudyMetadataStore: nil,
            deviceConnectionStatusStore: statusStore,
            syncStateStore: syncStateStore,
            onReady: {
                readySignal.markReady()
            },
            onFailed: { failure in
                readySignal.markFailed(failure.message)
            },
            onPairingChanged: {},
            onUploadAccepted: { _ in },
            onRecordingAccepted: { _, _ in },
            onConnectionDiagnostic: { diagnosticRecorder.record($0) }
        )
        defer {
            server.stop()
        }

        try server.start()
        try await waitForListenerReady(readySignal)
        #expect(readySignal.failureMessage == nil)
        #expect(server.isReady)
        let activePort = try #require(server.activePort)
        #expect(activePort > 0)

        let expectedFingerprint = identityManager.status.certificateFingerprint
        let client = RealListenerPinnedHTTPSClient(expectedFingerprint: expectedFingerprint)
        defer {
            client.invalidate()
        }

        let fingerprintResponse = try await client.getJSON(port: activePort, path: "/fingerprint")
        #expect(fingerprintResponse.statusCode == 200)
        let fingerprint = try #require(fingerprintResponse.json["fingerprint"] as? String)
        #expect(fingerprint == expectedFingerprint)
        #expect(fingerprint == identityManager.status.displayFingerprint)
        #expect(fingerprintResponse.json["type"] as? String == "certificate-sha256")

        let staleFingerprintClient = RealListenerPinnedHTTPSClient(expectedFingerprint: String(repeating: "0", count: 64))
        defer {
            staleFingerprintClient.invalidate()
        }
        do {
            _ = try await staleFingerprintClient.getJSON(port: activePort, path: "/fingerprint")
            Issue.record("Expected stale fingerprint to be reported as a pinning mismatch")
        } catch RealListenerHTTPSClientError.fingerprintMismatch {
            #expect(true)
        }

        let fakeDevice = PairedDevice(
            id: "iphone-unpaired",
            deviceName: "Unpaired iPhone",
            sharedSecretBase64URL: MacSecurityUtilities.randomBase64URLToken(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
        let unpairedHeartbeatBody = try encodedHeartbeatRequest(ConnectionHeartbeatRequest(
            deviceID: fakeDevice.id,
            deviceName: fakeDevice.deviceName,
            platform: .iPhone,
            appInstanceID: nil,
            sequenceNumber: 1,
            sentAt: Date(),
            lastKnownPeerStatusRevision: nil
        ))
        let unpairedHeartbeatHeaders = try signedJSONHeaders(
            device: fakeDevice,
            path: "/connection/heartbeat",
            body: unpairedHeartbeatBody,
            nonce: "real-listener-unpaired-heartbeat"
        )
        let unpairedHeartbeatResponse = try await client.postJSON(
            port: activePort,
            path: "/connection/heartbeat",
            headers: unpairedHeartbeatHeaders,
            body: unpairedHeartbeatBody
        )
        #expect(unpairedHeartbeatResponse.statusCode == 400)
        #expect(unpairedHeartbeatResponse.json["error"] as? String == "unknown_device")
        #expect(statusStore.latestStatus == nil)
        #expect(pairedDeviceStore.deviceCount == 0)

        let unpairedProbeBody = try encodedConnectionProbeRequest(
            sequenceNumber: 2,
            clientPayload: "unpaired tiny probe"
        )
        let unpairedProbeResponse = try await client.postJSON(
            port: activePort,
            path: "/connection/probe",
            headers: try signedJSONHeaders(
                device: fakeDevice,
                path: "/connection/probe",
                body: unpairedProbeBody,
                nonce: "real-listener-unpaired-probe"
            ),
            body: unpairedProbeBody
        )
        #expect(unpairedProbeResponse.statusCode == 400)
        #expect(unpairedProbeResponse.json["error"] as? String == "unknown_device")
        #expect(pairedDeviceStore.deviceCount == 0)

        pairingManager.beginPairing()
        let pairingCode = try #require(pairingManager.activeChallenge?.code)
        let pairBody = try JSONSerialization.data(withJSONObject: [
            "pairingCode": pairingCode,
            "deviceName": "Deviceless iPhone",
            "deviceType": "iPhone"
        ], options: [.sortedKeys])
        let pairResponse = try await client.postJSON(
            port: activePort,
            path: "/pair",
            headers: ["Content-Type": "application/json"],
            body: pairBody
        )
        #expect(pairResponse.statusCode == 200)
        #expect(pairResponse.json["ok"] as? Bool == true)
        let deviceID = try #require(pairResponse.json["deviceID"] as? String)
        let sharedSecret = try #require(pairResponse.json["sharedSecret"] as? String)
        let pairedDevice = PairedDevice(
            id: deviceID,
            deviceName: "Deviceless iPhone",
            sharedSecretBase64URL: sharedSecret,
            pairedAt: Date(),
            lastSeenAt: nil
        )
        #expect(pairedDeviceStore.device(for: deviceID) == nil)

        var lastKnownPeerStatusRevision: Int?
        var heartbeatLastSeenDates: [Date] = []
        for sequence in UInt64(1)...UInt64(3) {
            let heartbeatBody = try encodedHeartbeatRequest(ConnectionHeartbeatRequest(
                deviceID: deviceID,
                deviceName: "Deviceless iPhone",
                platform: .iPhone,
                appInstanceID: nil,
                sequenceNumber: sequence,
                sentAt: Date(),
                lastKnownPeerStatusRevision: lastKnownPeerStatusRevision
            ))
            let heartbeatRawResponse = try await client.postData(
                port: activePort,
                path: "/connection/heartbeat",
                headers: try signedJSONHeaders(
                    device: pairedDevice,
                    path: "/connection/heartbeat",
                    body: heartbeatBody,
                    nonce: "real-listener-paired-heartbeat-\(sequence)"
                ),
                body: heartbeatBody
            )
            #expect(heartbeatRawResponse.statusCode == 200)
            let heartbeatResponse = try Self.connectionJSONDecoder.decode(ConnectionHeartbeatResponse.self, from: heartbeatRawResponse.body)
            #expect(heartbeatResponse.ok)
            #expect(heartbeatResponse.receivedSequenceNumber == sequence)
            #expect(heartbeatResponse.status?.presenceState == .online)
            #expect(pairedDeviceStore.device(for: deviceID)?.lastSeenAt != nil)
            let statusLastSeen = try #require(statusStore.status(for: deviceID)?.lastSeenAt)
            if let previousLastSeen = heartbeatLastSeenDates.last {
                #expect(statusLastSeen > previousLastSeen)
            }
            heartbeatLastSeenDates.append(statusLastSeen)
            lastKnownPeerStatusRevision = heartbeatResponse.connectionStatusRevision
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        let thirdLastSeen = try #require(heartbeatLastSeenDates.last)
        let heartbeatEvents = diagnosticRecorder.snapshot()
            .filter { $0.phase == "heartbeat_success" }
        let receivedSequences = heartbeatEvents.compactMap(\.heartbeatSequence)
        #expect(receivedSequences == [1, 2, 3])
        let finalHeartbeatEvent = try #require(heartbeatEvents.last)
        #expect(finalHeartbeatEvent.routePath == "/connection/heartbeat")
        #expect(finalHeartbeatEvent.requestDeviceIDPrefix == String(deviceID.prefix(12)))
        #expect(finalHeartbeatEvent.verifierSucceeded == true)
        #expect(finalHeartbeatEvent.verifierFailed == false)
        #expect(finalHeartbeatEvent.markDeviceSeenCalled == true)
        #expect(finalHeartbeatEvent.connectionStatusStoreUpdated == true)
        #expect(finalHeartbeatEvent.pairedDeviceLastSeenBefore == heartbeatLastSeenDates[1])
        #expect(finalHeartbeatEvent.pairedDeviceLastSeenAfter == thirdLastSeen)
        #expect(finalHeartbeatEvent.uiObservedLastSeenAt == thirdLastSeen)

        let probeBody = try encodedConnectionProbeRequest(
            sequenceNumber: 99,
            clientPayload: "tiny probe payload"
        )
        let probeResponse = try await client.postJSON(
            port: activePort,
            path: "/connection/probe",
            headers: try signedJSONHeaders(
                device: pairedDevice,
                path: "/connection/probe",
                body: probeBody,
                nonce: "real-listener-paired-probe"
            ),
            body: probeBody
        )
        #expect(probeResponse.statusCode == 200)
        #expect(probeResponse.json["ok"] as? Bool == true)
        #expect(probeResponse.json["disposition"] as? String == "ok")
        #expect(probeResponse.json["receivedSequenceNumber"] as? Int == 99)
        #expect(probeResponse.json["echoedClientPayload"] as? String == "tiny probe payload")
        let probeStatus = try #require(statusStore.status(for: deviceID))
        #expect(probeStatus.lastSignedRequestSucceededAt != nil)
        #expect(probeStatus.lastSeenAt != nil)

        let disconnectedStatus = try #require(statusStore.status(for: deviceID, now: thirdLastSeen.addingTimeInterval(11)))
        #expect(disconnectedStatus.presenceState == .disconnected)

        let resumeHeartbeatBody = try encodedHeartbeatRequest(ConnectionHeartbeatRequest(
            deviceID: deviceID,
            deviceName: "Deviceless iPhone",
            platform: .iPhone,
            appInstanceID: nil,
            sequenceNumber: 4,
            sentAt: Date(),
            lastKnownPeerStatusRevision: lastKnownPeerStatusRevision
        ))
        let resumeHeartbeatRawResponse = try await client.postData(
            port: activePort,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: pairedDevice,
                path: "/connection/heartbeat",
                body: resumeHeartbeatBody,
                nonce: "real-listener-resume-heartbeat"
            ),
            body: resumeHeartbeatBody
        )
        let resumeHeartbeatResponse = try Self.connectionJSONDecoder.decode(ConnectionHeartbeatResponse.self, from: resumeHeartbeatRawResponse.body)
        let resumedStatus = try #require(statusStore.status(for: deviceID))
        #expect(resumeHeartbeatRawResponse.statusCode == 200)
        #expect(resumeHeartbeatResponse.receivedSequenceNumber == 4)
        #expect(resumedStatus.presenceState == .online)
        #expect(resumedStatus.missedHeartbeatCount == 0)
    }

    @MainActor
    @Test func realHTTPSLocalNetworkSyncInventoryArtifactAndMetadataSmoke() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("RokuricsRealSyncListener-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: rootURL)
        }

        let identityManager = MacIdentityManager(
            securityDirectoryURL: rootURL.appendingPathComponent("Security", isDirectory: true),
            tlsKeyTagNamespace: "real-sync-listener-\(UUID().uuidString)"
        )
        identityManager.loadOrCreateIdentity()
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let pairingManager = PairingManager(pairedDeviceStore: pairedDeviceStore)
        let requestVerifier = RequestVerifier(pairedDeviceStore: pairedDeviceStore)
        let recordingFileStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Library", isDirectory: true))
        let studyLibraryStore = StudyLibraryStore(
            rootURL: recordingFileStore.libraryRootURL,
            recordingFileStore: recordingFileStore,
            listenForInboxChanges: false
        )
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let readySignal = ListenerReadySignal()

        let transcriptPath = "transcripts/real-sync-recording/transcript.md"
        let transcriptURL = recordingFileStore.libraryRootURL.appendingPathComponent(transcriptPath, isDirectory: false)
        try fileManager.createDirectory(at: transcriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("real sync transcript".utf8).write(to: transcriptURL)
        let macItem = StudyItemMetadata(
            recordingID: "real-sync-recording",
            title: "Mac transcript",
            createdAt: Date(timeIntervalSince1970: 2_000),
            duration: 4,
            transcriptMarkdownRelativePath: transcriptPath,
            updatedAt: Date(timeIntervalSince1970: 2_010),
            transcriptionStatus: "transcribed",
            noteStatus: "notStarted",
            modifiedByDeviceID: "mac-seed"
        )
        _ = try await studyLibraryStore.applySyncManifest(
            StudyLibrarySyncManifest.make(
                deviceID: "mac-seed",
                generatedAt: Date(timeIntervalSince1970: 2_020),
                items: [macItem],
                folders: []
            ),
            localDeviceID: "mac-seed"
        )

        let server = SecureLocalHTTPSServer(
            port: 0,
            identityManager: identityManager,
            pairingManager: pairingManager,
            requestVerifier: requestVerifier,
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingFileStore,
            studyLibraryStore: studyLibraryStore,
            gitBackedStudyMetadataStore: nil,
            deviceConnectionStatusStore: statusStore,
            syncStateStore: syncStateStore,
            onReady: {
                readySignal.markReady()
            },
            onFailed: { failure in
                readySignal.markFailed(failure.message)
            },
            onPairingChanged: {},
            onUploadAccepted: { _ in },
            onRecordingAccepted: { _, _ in }
        )
        defer {
            server.stop()
        }

        try server.start()
        try await waitForListenerReady(readySignal)
        let activePort = try #require(server.activePort)
        let client = RealListenerPinnedHTTPSClient(expectedFingerprint: identityManager.status.certificateFingerprint)
        defer {
            client.invalidate()
        }

        let syncEncoder = JSONEncoder()
        syncEncoder.dateEncodingStrategy = .iso8601
        syncEncoder.outputFormatting = [.sortedKeys]
        let unpairedDevice = PairedDevice(
            id: "iphone-real-sync-unpaired",
            deviceName: "Unpaired iPhone",
            sharedSecretBase64URL: MacSecurityUtilities.randomBase64URLToken(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
        let inventoryBody = try syncEncoder.encode(LocalNetworkSyncInventoryRequest(deviceID: unpairedDevice.id, generatedAt: Date(timeIntervalSince1970: 3_000), localInventoryHash: nil))
        let unpairedSync = try await client.postJSON(
            port: activePort,
            path: "/sync/inventory",
            headers: try signedJSONHeaders(device: unpairedDevice, path: "/sync/inventory", body: inventoryBody, nonce: "real-sync-unpaired"),
            body: inventoryBody
        )
        #expect(unpairedSync.statusCode == 400)
        #expect(unpairedSync.json["error"] as? String == "unknown_device")

        let pairedDevice = PairedDevice(
            id: "iphone-real-sync",
            deviceName: "Real Sync iPhone",
            sharedSecretBase64URL: MacSecurityUtilities.randomBase64URLToken(),
            pairedAt: Date(timeIntervalSince1970: 3_010),
            lastSeenAt: nil
        )
        pairedDeviceStore.upsert(pairedDevice)

        let probeBody = try encodedConnectionProbeRequest(sequenceNumber: 1, clientPayload: "sync probe")
        let probeResponse = try await client.postJSON(
            port: activePort,
            path: "/connection/probe",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/connection/probe", body: probeBody, nonce: "real-sync-probe"),
            body: probeBody
        )
        #expect(probeResponse.statusCode == 200)

        let pairedInventoryBody = try syncEncoder.encode(LocalNetworkSyncInventoryRequest(deviceID: pairedDevice.id, generatedAt: Date(timeIntervalSince1970: 3_020), localInventoryHash: nil))
        var badHeaders = try signedJSONHeaders(device: pairedDevice, path: "/sync/inventory", body: pairedInventoryBody, nonce: "real-sync-bad-hmac")
        badHeaders["X-Rokurics-Signature"] = "bad-signature"
        let badHMACResponse = try await client.postJSON(
            port: activePort,
            path: "/sync/inventory",
            headers: badHeaders,
            body: pairedInventoryBody
        )
        #expect(badHMACResponse.statusCode == 400)
        #expect(badHMACResponse.json["error"] as? String == "signature_mismatch")

        let inventoryResponseRaw = try await client.postData(
            port: activePort,
            path: "/sync/inventory",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/sync/inventory", body: pairedInventoryBody, nonce: "real-sync-inventory"),
            body: pairedInventoryBody
        )
        #expect(inventoryResponseRaw.statusCode == 200)
        let inventoryResponse = try Self.connectionJSONDecoder.decode(LocalNetworkSyncInventoryResponse.self, from: inventoryResponseRaw.body)
        let inventory = try #require(inventoryResponse.inventory)
        let transcriptArtifact = try #require(inventory.artifacts.first { $0.kind == .transcriptMarkdown })
        #expect(inventory.schemaVersion == LocalNetworkSyncInventory.appSchemaVersion)
        #expect(inventory.sourcePlatform == .Mac)

        let artifactBody = try syncEncoder.encode(LocalNetworkSyncArtifactRequest(artifactID: transcriptArtifact.artifactID))
        let artifactResponseRaw = try await client.postData(
            port: activePort,
            path: "/sync/artifact-request",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/sync/artifact-request", body: artifactBody, nonce: "real-sync-artifact"),
            body: artifactBody
        )
        #expect(artifactResponseRaw.statusCode == 200)
        let artifactResponse = try Self.connectionJSONDecoder.decode(LocalNetworkSyncArtifactResponse.self, from: artifactResponseRaw.body)
        #expect(artifactResponse.ok)
        #expect(artifactResponse.checksum == MacSecurityUtilities.sha256Hex(Data("real sync transcript".utf8)))
        #expect(String(data: Data(base64Encoded: try #require(artifactResponse.dataBase64)) ?? Data(), encoding: .utf8) == "real sync transcript")

        let incomingArtifactPath = "transcripts/real-sync-incoming/transcript.md"
        let incomingArtifactData = Data("incoming real sync transcript".utf8)
        let incomingArtifactID = LocalNetworkSyncArtifactID.make(
            kind: .transcriptMarkdown,
            ownerID: "real-sync-incoming",
            logicalPathToken: incomingArtifactPath
        )
        let artifactPutBody = try syncEncoder.encode(LocalNetworkSyncArtifactPutRequest(
            artifactID: incomingArtifactID,
            kind: .transcriptMarkdown,
            ownerID: "real-sync-incoming",
            checksum: MacSecurityUtilities.sha256Hex(incomingArtifactData),
            size: Int64(incomingArtifactData.count),
            updatedAt: Date(timeIntervalSince1970: 3_030),
            logicalPathToken: incomingArtifactPath,
            dataBase64: incomingArtifactData.base64EncodedString()
        ))
        let artifactPutResponseRaw = try await client.postData(
            port: activePort,
            path: "/sync/artifact-put",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/sync/artifact-put", body: artifactPutBody, nonce: "real-sync-artifact-put"),
            body: artifactPutBody
        )
        #expect(artifactPutResponseRaw.statusCode == 200)
        let artifactPutResponse = try Self.connectionJSONDecoder.decode(LocalNetworkSyncArtifactPutResponse.self, from: artifactPutResponseRaw.body)
        let storedIncomingArtifactURL = recordingFileStore.libraryRootURL.appendingPathComponent(incomingArtifactPath, isDirectory: false)
        #expect(artifactPutResponse.ok)
        #expect(artifactPutResponse.disposition == "acceptedNew")
        #expect(String(data: try Data(contentsOf: storedIncomingArtifactURL), encoding: .utf8) == "incoming real sync transcript")

        let incomingItem = StudyItemMetadata(
            recordingID: "real-sync-incoming",
            title: "Incoming metadata",
            createdAt: Date(timeIntervalSince1970: 4_000),
            duration: 7,
            updatedAt: Date(timeIntervalSince1970: 4_010),
            modifiedByDeviceID: pairedDevice.id
        )
        let applyBody = try syncEncoder.encode(StudyLibrarySyncManifestRequest(
            manifest: StudyLibrarySyncManifest.make(
                deviceID: pairedDevice.id,
                generatedAt: Date(timeIntervalSince1970: 4_020),
                items: [incomingItem],
                folders: []
            )
        ))
        let applyResponseRaw = try await client.postData(
            port: activePort,
            path: "/sync/apply-metadata",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/sync/apply-metadata", body: applyBody, nonce: "real-sync-apply"),
            body: applyBody
        )
        #expect(applyResponseRaw.statusCode == 200)
        let applyResponse = try Self.connectionJSONDecoder.decode(StudyLibrarySyncManifestResponse.self, from: applyResponseRaw.body)
        #expect(applyResponse.ok)
        #expect(studyLibraryStore.item(recordingID: "real-sync-incoming")?.title == "Incoming metadata")

        let heartbeatBody = try encodedHeartbeatRequest(ConnectionHeartbeatRequest(
            deviceID: pairedDevice.id,
            deviceName: pairedDevice.deviceName,
            platform: .iPhone,
            appInstanceID: nil,
            sequenceNumber: 7,
            sentAt: Date(),
            lastKnownPeerStatusRevision: nil
        ))
        let heartbeatResponse = try await client.postData(
            port: activePort,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/connection/heartbeat", body: heartbeatBody, nonce: "real-sync-heartbeat"),
            body: heartbeatBody
        )
        #expect(heartbeatResponse.statusCode == 200)
        #expect(statusStore.status(for: pairedDevice.id)?.presenceState == .online)
    }

    @MainActor
    @Test func realConnectionBeginPairingFromStoppedStateProducesUsablePayloadAndPairsThroughTLS() async throws {
        let harness = try makeSecureReceiverServiceHarness()
        defer {
            harness.service.stopSecureReceiving()
            try? FileManager.default.removeItem(at: harness.rootURL)
        }

        _ = harness.statusStore.recordHeartbeatFailure(
            deviceID: "stale-device",
            displayName: "Old iPhone",
            errorCode: "certificate_pinning_failed",
            errorMessage: "Previous fingerprint mismatch",
            isSecurityFailure: true
        )

        harness.service.beginPairing()
        let payload = try await waitForPairingPayload(harness.service)
        try assertPairingPayload(payload, matches: harness.service, identityManager: harness.identityManager)
        #expect(harness.service.pairingFlowState == .pairingCodeIssued)
        #expect(harness.service.canCopyPairingInfo)
        #expect(harness.pairedDeviceStore.deviceCount == 0)

        let client = RealListenerPinnedHTTPSClient(expectedFingerprint: payload.fingerprint)
        defer {
            client.invalidate()
        }

        let fingerprintResponse = try await client.getJSON(host: payload.host, port: payload.port, path: "/fingerprint")
        #expect(fingerprintResponse.statusCode == 200)
        #expect(fingerprintResponse.json["fingerprint"] as? String == payload.fingerprint)
        #expect(fingerprintResponse.json["type"] as? String == payload.fingerprintType)

        let unpairedDevice = PairedDevice(
            id: "iphone-unpaired-service",
            deviceName: "Unpaired iPhone",
            sharedSecretBase64URL: MacSecurityUtilities.randomBase64URLToken(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
        let unpairedHeartbeatBody = try encodedHeartbeatRequest(makeHeartbeatRequest(device: unpairedDevice, sequenceNumber: 1))
        let unpairedHeartbeatResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: unpairedDevice,
                path: "/connection/heartbeat",
                body: unpairedHeartbeatBody,
                nonce: "service-unpaired-heartbeat"
            ),
            body: unpairedHeartbeatBody
        )
        #expect(unpairedHeartbeatResponse.statusCode == 400)
        #expect(unpairedHeartbeatResponse.json["error"] as? String == "unknown_device")
        #expect(harness.statusStore.status(for: unpairedDevice.id) == nil)

        let pairResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/pair",
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: [
                "pairingCode": payload.pairingCode,
                "deviceName": "Deviceless iPhone",
                "deviceType": "iPhone"
            ], options: [.sortedKeys])
        )
        #expect(pairResponse.statusCode == 200)
        #expect(pairResponse.json["ok"] as? Bool == true)
        let deviceID = try #require(pairResponse.json["deviceID"] as? String)
        let sharedSecret = try #require(pairResponse.json["sharedSecret"] as? String)
        let confirmationToken = try #require(pairResponse.json["confirmationToken"] as? String)
        #expect(harness.pairedDeviceStore.device(for: deviceID) == nil)
        let confirmationResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/pair/confirm",
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: [
                "deviceID": deviceID,
                "confirmationToken": confirmationToken
            ], options: [.sortedKeys])
        )
        #expect(confirmationResponse.statusCode == 200)
        #expect(confirmationResponse.json["ok"] as? Bool == true)
        let pairedDevice = try #require(harness.pairedDeviceStore.device(for: deviceID))
        #expect(pairedDevice.sharedSecretBase64URL == sharedSecret)

        let heartbeatBody = try encodedHeartbeatRequest(ConnectionHeartbeatRequest(
            deviceID: pairedDevice.id,
            deviceName: pairedDevice.deviceName,
            platform: .iPhone,
            appInstanceID: nil,
            sequenceNumber: 42,
            sentAt: Date(),
            lastKnownPeerStatusRevision: nil
        ))
        let heartbeatResponse = try await client.postData(
            host: payload.host,
            port: payload.port,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: pairedDevice,
                path: "/connection/heartbeat",
                body: heartbeatBody,
                nonce: "service-paired-heartbeat"
            ),
            body: heartbeatBody
        )
        #expect(heartbeatResponse.statusCode == 200)
        let decodedHeartbeat = try Self.connectionJSONDecoder.decode(ConnectionHeartbeatResponse.self, from: heartbeatResponse.body)
        #expect(decodedHeartbeat.ok)
        #expect(decodedHeartbeat.receivedSequenceNumber == 42)
        #expect(harness.statusStore.status(for: pairedDevice.id)?.presenceState == .online)

        let probeBody = try encodedConnectionProbeRequest(
            sequenceNumber: 77,
            clientPayload: "goal-mode tiny probe"
        )
        let probeResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/connection/probe",
            headers: try signedJSONHeaders(
                device: pairedDevice,
                path: "/connection/probe",
                body: probeBody,
                nonce: "service-paired-probe"
            ),
            body: probeBody
        )
        #expect(probeResponse.statusCode == 200)
        #expect(probeResponse.json["disposition"] as? String == "ok")
        #expect(probeResponse.json["receivedSequenceNumber"] as? Int == 77)
        #expect(probeResponse.json["echoedClientPayload"] as? String == "goal-mode tiny probe")

        var badProbeHeaders = try signedJSONHeaders(
            device: pairedDevice,
            path: "/connection/probe",
            body: probeBody,
            nonce: "service-bad-hmac-probe"
        )
        badProbeHeaders["X-Rokurics-Signature"] = "bad-signature"
        let badProbeResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/connection/probe",
            headers: badProbeHeaders,
            body: probeBody
        )
        #expect(badProbeResponse.statusCode == 400)
        #expect(badProbeResponse.json["error"] as? String == "signature_mismatch")

        try await performRealSocketShortUploadSmoke(
            client: client,
            host: payload.host,
            port: payload.port,
            device: pairedDevice,
            recordingStore: harness.recordingFileStore
        )

        let diagnostics = harness.diagnosticsStore.loadEntries()
        let phases = Set(diagnostics.map(\.phase))
        #expect(phases.contains("begin_pairing_requested"))
        #expect(phases.contains("listener_ready"))
        #expect(phases.contains("pairing_code_issued"))
        #expect(phases.contains("fingerprint_endpoint_reached"))
        #expect(phases.contains("pair_request_reached"))
        #expect(phases.contains("heartbeat_success"))
        #expect(phases.contains("probe_success"))
        let diagnosticsText = try String(contentsOf: harness.diagnosticsStore.logURL, encoding: .utf8)
        #expect(!diagnosticsText.contains(payload.pairingCode))
        #expect(!diagnosticsText.contains(sharedSecret))
        #expect(!diagnosticsText.lowercased().contains("privatekey"))
        #expect(!diagnosticsText.lowercased().contains("hmac"))

        harness.service.stopSecureReceiving()
        #expect(!harness.service.isHTTPSRunning)
        #expect(harness.service.pairingPayload == nil)
        let disconnectedStatus = try #require(harness.statusStore.status(for: pairedDevice.id, now: Date().addingTimeInterval(20)))
        #expect(disconnectedStatus.presenceState == .disconnected)

        harness.service.startSecureReceiving()
        try await waitForHTTPSReady(harness.service)
        let reopenedPort = try #require(harness.service.activeHTTPSPort)
        let reopenedClient = RealListenerPinnedHTTPSClient(expectedFingerprint: harness.identityManager.status.certificateFingerprint)
        defer {
            reopenedClient.invalidate()
        }
        let reconnectHeartbeatBody = try encodedHeartbeatRequest(ConnectionHeartbeatRequest(
            deviceID: pairedDevice.id,
            deviceName: pairedDevice.deviceName,
            platform: .iPhone,
            appInstanceID: nil,
            sequenceNumber: 43,
            sentAt: Date(),
            lastKnownPeerStatusRevision: disconnectedStatus.connectionStatusRevision
        ))
        let reconnectResponse = try await reopenedClient.postData(
            host: payload.host,
            port: reopenedPort,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: pairedDevice,
                path: "/connection/heartbeat",
                body: reconnectHeartbeatBody,
                nonce: "service-reconnect-heartbeat"
            ),
            body: reconnectHeartbeatBody
        )
        #expect(reconnectResponse.statusCode == 200)
        #expect(harness.statusStore.status(for: pairedDevice.id)?.presenceState == .online)
    }

    @MainActor
    @Test func realConnectionBeginPairingFromReadyStateProducesUsablePayloadImmediately() async throws {
        let harness = try makeSecureReceiverServiceHarness()
        defer {
            harness.service.stopSecureReceiving()
            try? FileManager.default.removeItem(at: harness.rootURL)
        }

        harness.service.startSecureReceiving()
        try await waitForHTTPSReady(harness.service)
        #expect(harness.service.pairingFlowState == .readyForPairing)

        harness.service.beginPairing()

        let payload = try #require(harness.service.pairingPayload)
        try assertPairingPayload(payload, matches: harness.service, identityManager: harness.identityManager)
        #expect(harness.service.pairingFlowState == .pairingCodeIssued)
        #expect(harness.service.pairingCode == payload.pairingCode)
        #expect(harness.service.canCopyPairingInfo)
    }

    @MainActor
    @Test func realMacConnectionPageEntryActionPublishesCodeAndEnablesCopyFromSameService() async throws {
        let harness = try makeSecureReceiverServiceHarness()
        defer {
            harness.service.stopSecureReceiving()
            try? FileManager.default.removeItem(at: harness.rootURL)
        }

        #expect(harness.service.canBeginPairingFromUI)
        harness.service.recordAppLaunch()
        harness.service.recordConnectionPageLoaded(
            beginPairingButtonEnabled: harness.service.canBeginPairingFromUI,
            copyEnabled: harness.service.canCopyPairingInfo
        )
        harness.service.recordBeginPairingButtonTapped(
            beginPairingButtonEnabled: harness.service.canBeginPairingFromUI,
            copyEnabled: harness.service.canCopyPairingInfo
        )

        harness.service.beginPairing()

        let payload = try await waitForPairingPayload(harness.service)
        try assertPairingPayload(payload, matches: harness.service, identityManager: harness.identityManager)
        #expect(harness.service.pairingCode == payload.pairingCode)
        #expect(harness.service.pairingPayload == payload)
        #expect(harness.service.canCopyPairingInfo)

        let diagnostics = harness.diagnosticsStore.loadEntries()
        let phases = Set(diagnostics.map(\.phase))
        #expect(phases.contains("appLaunch"))
        #expect(phases.contains("connectionPageLoaded"))
        #expect(phases.contains("beginPairingButtonTapped"))
        #expect(phases.contains("beginPairingRequested"))
        #expect(phases.contains("listenerStarting"))
        #expect(phases.contains("listenerReady"))
        #expect(phases.contains("payloadPublished"))
        #expect(phases.contains("codeIssued"))
        #expect(diagnostics.contains { $0.beginPairingButtonEnabled == true })
        #expect(diagnostics.contains { $0.payloadPublished == true })
        #expect(diagnostics.contains { $0.copyEnabled == true })

        let diagnosticsText = try String(contentsOf: harness.diagnosticsStore.logURL, encoding: .utf8)
        #expect(!diagnosticsText.contains(payload.pairingCode))
        #expect(!diagnosticsText.lowercased().contains("sharedsecret"))
        #expect(!diagnosticsText.lowercased().contains("privatekey"))
        #expect(!diagnosticsText.lowercased().contains("hmac"))
    }

    @MainActor
    @Test func realListenerUnpairDeletesCredentialsRejectsOldHMACAndAllowsFreshPairing() async throws {
        let harness = try makeSecureReceiverServiceHarness()
        defer {
            harness.service.stopSecureReceiving()
            try? FileManager.default.removeItem(at: harness.rootURL)
        }

        harness.service.beginPairing()
        let payload = try await waitForPairingPayload(harness.service)
        let client = RealListenerPinnedHTTPSClient(expectedFingerprint: payload.fingerprint)
        defer {
            client.invalidate()
        }

        let pairResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/pair",
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: [
                "pairingCode": payload.pairingCode,
                "deviceName": "Unpair Test iPhone",
                "deviceType": "iPhone"
            ], options: [.sortedKeys])
        )
        #expect(pairResponse.statusCode == 200)
        let deviceID = try #require(pairResponse.json["deviceID"] as? String)
        let confirmationToken = try #require(pairResponse.json["confirmationToken"] as? String)
        let confirmationResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/pair/confirm",
            headers: ["Content-Type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: [
                "deviceID": deviceID,
                "confirmationToken": confirmationToken
            ], options: [.sortedKeys])
        )
        #expect(confirmationResponse.statusCode == 200)
        #expect(confirmationResponse.json["ok"] as? Bool == true)
        let pairedDevice = try #require(harness.pairedDeviceStore.device(for: deviceID))

        let heartbeatBody = try encodedHeartbeatRequest(makeHeartbeatRequest(device: pairedDevice, sequenceNumber: 1))
        let heartbeatResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/connection/heartbeat", body: heartbeatBody, nonce: "unpair-before-heartbeat"),
            body: heartbeatBody
        )
        #expect(heartbeatResponse.statusCode == 200)

        let unpairBody = try JSONSerialization.data(withJSONObject: [
            "deviceID": pairedDevice.id,
            "reason": "test_disconnect"
        ], options: [.sortedKeys])
        let unpairResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/device/unpair",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/device/unpair", body: unpairBody, nonce: "unpair-route"),
            body: unpairBody
        )
        #expect(unpairResponse.statusCode == 200)
        #expect(unpairResponse.json["ok"] as? Bool == true)
        #expect(harness.pairedDeviceStore.deviceCount == 0)
        #expect(harness.statusStore.status(for: pairedDevice.id) == nil)

        let oldHeartbeatBody = try encodedHeartbeatRequest(makeHeartbeatRequest(device: pairedDevice, sequenceNumber: 2))
        let oldHeartbeatResponse = try await client.postJSON(
            host: payload.host,
            port: payload.port,
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/connection/heartbeat", body: oldHeartbeatBody, nonce: "unpair-old-heartbeat"),
            body: oldHeartbeatBody
        )
        #expect(oldHeartbeatResponse.statusCode == 400)
        #expect(oldHeartbeatResponse.json["error"] as? String == "unknown_device")

        harness.service.beginPairing()
        let newPayload = try await waitForPairingPayload(harness.service)
        #expect(newPayload.pairingCode.count == 6)
        #expect(newPayload.pairingCode != payload.pairingCode)
    }

    @MainActor
    @Test func disconnectedOrSecurityErrorDoesNotBlockFreshBeginPairing() async throws {
        let harness = try makeSecureReceiverServiceHarness()
        defer {
            harness.service.stopSecureReceiving()
            try? FileManager.default.removeItem(at: harness.rootURL)
        }

        let pairedDevice = PairedDevice(
            id: "iphone-\(UUID().uuidString)",
            deviceName: "iPhone",
            sharedSecretBase64URL: MacSecurityUtilities.randomBase64URLToken(),
            pairedAt: Date()
        )
        harness.pairedDeviceStore.upsert(pairedDevice)

        let disconnectedStatus = harness.statusStore.markOffline(
            deviceID: pairedDevice.id,
            displayName: pairedDevice.deviceName,
            error: "manual_disconnect"
        )
        #expect(disconnectedStatus.presenceState == .disconnected)
        #expect(harness.service.canBeginPairingFromUI)

        harness.service.beginPairing()

        let disconnectedPayload = try await waitForPairingPayload(harness.service)
        try assertPairingPayload(disconnectedPayload, matches: harness.service, identityManager: harness.identityManager)
        #expect(harness.service.canCopyPairingInfo)

        let securityStatus = harness.statusStore.recordHeartbeatFailure(
            deviceID: pairedDevice.id,
            displayName: pairedDevice.deviceName,
            errorCode: "fingerprint_mismatch",
            errorMessage: "fingerprint mismatch",
            isSecurityFailure: true
        )
        #expect(securityStatus.presenceState == .securityError)
        #expect(harness.service.canBeginPairingFromUI)

        harness.service.beginPairing()

        let securityPayload = try await waitForPairingPayload(harness.service)
        try assertPairingPayload(securityPayload, matches: harness.service, identityManager: harness.identityManager)
        #expect(harness.service.canCopyPairingInfo)
    }

    @MainActor
    @Test func realConnectionBeginPairingWhileListenerStartingPublishesPayloadAfterReady() async throws {
        let harness = try makeSecureReceiverServiceHarness()
        defer {
            harness.service.stopSecureReceiving()
            try? FileManager.default.removeItem(at: harness.rootURL)
        }

        harness.service.startSecureReceiving()
        harness.service.beginPairing()

        let payload = try await waitForPairingPayload(harness.service)
        try assertPairingPayload(payload, matches: harness.service, identityManager: harness.identityManager)
        #expect(harness.service.pairingFlowState == .pairingCodeIssued)
        #expect(harness.service.canCopyPairingInfo)
    }

    @MainActor
    @Test func beginPairingFailureReportsErrorInsteadOfSilentNoop() throws {
        let rootURL = try makeScratchDirectory()
        defer {
            try? FileManager.default.removeItem(at: rootURL)
        }
        let identityManager = MacIdentityManager(
            securityDirectoryURL: rootURL.appendingPathComponent("Security", isDirectory: true),
            tlsKeyTagNamespace: "unloaded-\(UUID().uuidString)"
        )
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let recordingStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Library", isDirectory: true))
        let service = SecureReceiverService(
            port: 0,
            identityManager: identityManager,
            pairedDeviceStore: pairedDeviceStore,
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingStore,
            studyLibraryStore: StudyLibraryStore(
                rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
                recordingFileStore: recordingStore,
                listenForInboxChanges: false
            ),
            deviceConnectionStatusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            syncStateStore: StudyLibrarySyncStateStore(rootURL: rootURL),
            connectionDiagnosticsStore: ConnectionDiagnosticsStore(rootURL: rootURL),
            loadIdentityOnInit: false,
            preferredIPAddressProvider: { "127.0.0.1" }
        )

        service.beginPairing()

        #expect(service.pairingFlowState == .failed)
        #expect(service.pairingPayload == nil)
        #expect(service.connectionErrorCode == .tlsHandshakeFailed)
        #expect(service.lastError != nil)
    }

    @MainActor
    @Test func occupiedPairingPortAdvancesOnceAndNextClickPublishesNewPort() async throws {
        let blockerReady = ListenerReadySignal()
        let blockerQueue = DispatchQueue(label: "RokuricsMacTests.OccupiedPortBlocker")
        let blocker = try NWListener(using: .tcp, on: .any)
        blocker.stateUpdateHandler = { state in
            switch state {
            case .ready:
                blockerReady.markReady()
            case .failed(let error):
                blockerReady.markFailed(error.localizedDescription)
            default:
                break
            }
        }
        blocker.newConnectionHandler = { connection in
            connection.cancel()
        }
        blocker.start(queue: blockerQueue)
        defer { blocker.cancel() }
        try await waitForListenerReady(blockerReady)

        let occupiedPort = try #require(blocker.port.map { Int($0.rawValue) })
        _ = try #require(occupiedPort < 65_535)
        let expectedNextPort = SecureReceiverService.nextPort(afterAddressInUse: occupiedPort)
        let harness = try makeSecureReceiverServiceHarness(port: occupiedPort)
        defer {
            harness.service.stopSecureReceiving()
            try? FileManager.default.removeItem(at: harness.rootURL)
        }

        harness.service.beginPairing()
        let failureDeadline = Date().addingTimeInterval(5)
        while Date() < failureDeadline,
              harness.service.connectionErrorCode != .portInUse {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(harness.service.connectionErrorCode == .portInUse)
        #expect(harness.service.port == expectedNextPort)
        #expect(harness.service.pairingPayload == nil)
        #expect(harness.service.lastError?.contains("\(expectedNextPort)") == true)
        #expect(harness.diagnosticsStore.loadEntries().contains {
            $0.phase == "listener_port_advanced_after_address_in_use"
                && $0.errorCode == SecureReceiverConnectionErrorCode.portInUse.rawValue
        })

        harness.service.beginPairing()
        let payload = try await waitForPairingPayload(harness.service)

        #expect(payload.port == expectedNextPort)
        #expect(harness.service.activeHTTPSPort == expectedNextPort)
        #expect(harness.service.port == expectedNextPort)
    }

    @MainActor
    @Test func devicelessFreshPairingHeartbeatAndSmallRecordingUploadSmoke() async throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let securityRootURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let libraryRootURL = rootURL.appendingPathComponent("Library", isDirectory: true)
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityRootURL)
        let pairingManager = PairingManager(pairedDeviceStore: pairedDeviceStore)
        let pairingNow = Date(timeIntervalSince1970: 4_000)
        pairingManager.beginPairing(now: pairingNow)
        let pairingCode = try #require(pairingManager.activeChallenge?.code)
        var pairingChangedCount = 0
        let pairingHandler = PairingBootstrapRouteHandler(
            pairingManager: pairingManager,
            macName: "Smoke Mac",
            macModel: "Mac",
            onPairingChanged: { pairingChangedCount += 1 }
        )
        let pairBody = Data(#"{"pairingCode":"\#(pairingCode)","deviceName":"Smoke iPhone","deviceType":"iPhone"}"#.utf8)

        let pairResponse = pairingHandler.pairingResponse(
            method: "POST",
            path: "/pair",
            headers: ["Content-Type": "application/json"],
            body: pairBody,
            now: pairingNow.addingTimeInterval(1)
        )
        let pairJSON = try routeResponseJSON(pairResponse)
        let pendingDeviceID = try #require(pairJSON["deviceID"] as? String)
        let confirmationToken = try #require(pairJSON["confirmationToken"] as? String)
        let confirmationBody = try JSONSerialization.data(withJSONObject: [
            "deviceID": pendingDeviceID,
            "confirmationToken": confirmationToken
        ])
        let confirmationResponse = pairingHandler.pairingConfirmationResponse(
            method: "POST",
            path: "/pair/confirm",
            headers: ["Content-Type": "application/json"],
            body: confirmationBody,
            now: pairingNow.addingTimeInterval(2)
        )
        let pairedDevice = try #require(pairedDeviceStore.devices.first)

        #expect(pairResponse.statusCode == 200)
        #expect(confirmationResponse.statusCode == 200)
        #expect(pairJSON["ok"] as? Bool == true)
        #expect(pairJSON["deviceID"] as? String == pairedDevice.id)
        #expect(pairJSON["sharedSecret"] as? String == pairedDevice.sharedSecretBase64URL)
        #expect(pairingChangedCount == 1)

        let requestVerifier = RequestVerifier(pairedDeviceStore: pairedDeviceStore)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL.appendingPathComponent("ConnectionStatus", isDirectory: true))
        let heartbeatHandler = ConnectionHeartbeatRouteHandler(
            requestVerifier: requestVerifier,
            statusStore: statusStore,
            localPeerDeviceID: "mac-smoke-peer"
        )
        let heartbeatRequest = makeHeartbeatRequest(device: pairedDevice, sequenceNumber: 42)
        let heartbeatBody = try encodedHeartbeatRequest(heartbeatRequest)
        let heartbeatNow = Date()
        let heartbeatResponse = heartbeatHandler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/connection/heartbeat", body: heartbeatBody, nonce: "smoke-heartbeat", now: heartbeatNow),
            body: heartbeatBody,
            now: heartbeatNow
        )
        let decodedHeartbeat = try decodeHeartbeatResponse(heartbeatResponse)

        #expect(heartbeatResponse.statusCode == 200)
        #expect(decodedHeartbeat.ok)
        #expect(decodedHeartbeat.receivedSequenceNumber == 42)
        #expect(pairedDeviceStore.device(for: pairedDevice.id)?.lastSeenAt != nil)

        let probeHandler = ConnectionProbeRouteHandler(requestVerifier: requestVerifier)
        let probeBody = try encodedConnectionProbeRequest(sequenceNumber: 43, clientPayload: "route tiny probe")
        let probeResponse = probeHandler.probeResponse(
            method: "POST",
            path: "/connection/probe",
            headers: try signedJSONHeaders(
                device: pairedDevice,
                path: "/connection/probe",
                body: probeBody,
                nonce: "smoke-probe",
                now: heartbeatNow.addingTimeInterval(1)
            ),
            body: probeBody,
            now: heartbeatNow.addingTimeInterval(1)
        )
        let probeJSON = try routeResponseJSON(probeResponse)

        #expect(probeResponse.statusCode == 200)
        #expect(probeJSON["ok"] as? Bool == true)
        #expect(probeJSON["disposition"] as? String == "ok")
        #expect(probeJSON["receivedSequenceNumber"] as? Int == 43)
        #expect(probeJSON["echoedClientPayload"] as? String == "route tiny probe")

        let recordingStore = MacRecordingFileStore(rootURL: libraryRootURL)
        var acceptedRecordingIDs: [String] = []
        var acceptedReasons: [SyncTriggerReason] = []
        let uploadHandler = RecordingUploadRouteHandler(
            requestVerifier: requestVerifier,
            recordingFileStore: recordingStore,
            onRecordingAccepted: { recordingID, reason in
                acceptedRecordingIDs.append(recordingID)
                acceptedReasons.append(reason)
            }
        )
        let audio = Data("fake ten second m4a audio".utf8)
        let metadata = makeIncomingUploadMetadata(id: "deviceless-smoke-01", fileSize: Int64(audio.count))
        let metadataBody = try encodedMetadata(metadata)

        let metadataResponse = await uploadHandler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: pairedDevice, path: "/upload-recording-metadata", body: metadataBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "smoke-metadata-new"),
            body: metadataBody
        )
        let metadataJSON = try routeResponseJSON(metadataResponse)

        #expect(metadataResponse.statusCode == 200)
        #expect(metadataJSON["ok"] as? Bool == true)
        #expect(metadataJSON["disposition"] as? String == RecordingUploadDisposition.acceptedNew.rawValue)

        let audioResponse = await uploadHandler.audioUploadResponse(
            method: "POST",
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(device: pairedDevice, path: "/upload-recording-audio", body: audio, contentType: "audio/m4a", uploadType: "recording-audio", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "smoke-audio-new"),
            body: audio
        )
        let audioJSON = try routeResponseJSON(audioResponse)
        let receiveRecord = try readReceiveRecord(rootURL: libraryRootURL, recordingID: metadata.id)
        let recordingDirectoryURL = libraryRootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("1970-01-01", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)
        let metadataURL = recordingDirectoryURL.appendingPathComponent("metadata.json", isDirectory: false)
        let audioURL = recordingDirectoryURL.appendingPathComponent("audio.m4a", isDirectory: false)
        let receiveURL = recordingDirectoryURL.appendingPathComponent("receive.json", isDirectory: false)

        #expect(audioResponse.statusCode == 200)
        #expect(audioJSON["ok"] as? Bool == true)
        #expect(audioJSON["disposition"] as? String == RecordingUploadDisposition.acceptedNew.rawValue)
        #expect(FileManager.default.fileExists(atPath: metadataURL.path))
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(FileManager.default.fileExists(atPath: receiveURL.path))
        #expect(try Data(contentsOf: audioURL) == audio)
        #expect(receiveRecord.status == "completed")
        #expect(receiveRecord.processingStatus == "notStarted")
        #expect(receiveRecord.checksum == MacSecurityUtilities.sha256Hex(audio))
        #expect(acceptedRecordingIDs.contains(metadata.id))
        #expect(acceptedReasons.contains(.studyLibraryMetadataChanged))
        #expect(acceptedReasons.contains(.macAudioReceiveFinalized))

        let repeatedMetadataResponse = await uploadHandler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: pairedDevice, path: "/upload-recording-metadata", body: metadataBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "smoke-metadata-repeat"),
            body: metadataBody
        )
        let repeatedAudioResponse = await uploadHandler.audioUploadResponse(
            method: "POST",
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(device: pairedDevice, path: "/upload-recording-audio", body: audio, contentType: "audio/m4a", uploadType: "recording-audio", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "smoke-audio-repeat"),
            body: audio
        )

        #expect((try routeResponseJSON(repeatedMetadataResponse))["disposition"] as? String == RecordingUploadDisposition.acceptedExisting.rawValue)
        #expect((try routeResponseJSON(repeatedAudioResponse))["disposition"] as? String == RecordingUploadDisposition.acceptedExisting.rawValue)

        let conflictingMetadata = makeIncomingUploadMetadata(id: metadata.id, fileSize: Int64(audio.count + 1))
        let conflictingMetadataBody = try encodedMetadata(conflictingMetadata)
        let metadataConflictResponse = await uploadHandler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: pairedDevice, path: "/upload-recording-metadata", body: conflictingMetadataBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "smoke-metadata-conflict"),
            body: conflictingMetadataBody
        )
        let conflictingAudio = Data("different fake m4a audio".utf8)
        let audioConflictResponse = await uploadHandler.audioUploadResponse(
            method: "POST",
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(device: pairedDevice, path: "/upload-recording-audio", body: conflictingAudio, contentType: "audio/m4a", uploadType: "recording-audio", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "smoke-audio-conflict"),
            body: conflictingAudio
        )

        #expect(metadataConflictResponse.statusCode == 409)
        #expect((try routeResponseJSON(metadataConflictResponse))["error"] as? String == "recording_metadata_conflict")
        #expect(String(data: metadataConflictResponse.bodyData, encoding: .utf8)?.contains(pairedDevice.sharedSecretBase64URL) == false)
        #expect(audioConflictResponse.statusCode == 409)
        #expect((try routeResponseJSON(audioConflictResponse))["error"] as? String == "recording_audio_conflict")
        #expect(String(data: audioConflictResponse.bodyData, encoding: .utf8)?.contains(pairedDevice.sharedSecretBase64URL) == false)
    }

    @MainActor
    @Test func pairedHeartbeatRouteWritebackUpdatesStoresAndMacStatusSource() async throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let securityRootURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityRootURL)
        let pairedDevice = makeHeartbeatDevice()
        pairedDeviceStore.upsert(pairedDevice)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let service = SecureReceiverService(
            pairedDeviceStore: pairedDeviceStore,
            deviceConnectionStatusStore: statusStore,
            loadIdentityOnInit: false,
            preferredIPAddressProvider: { "127.0.0.1" }
        )
        let handler = ConnectionHeartbeatRouteHandler(
            requestVerifier: service.requestVerifier,
            statusStore: statusStore,
            localPeerDeviceID: "mac-presence-test"
        )
        let initialRevision = service.presenceObservationRevision
        var lastSeenDates: [Date] = []

        for sequence in UInt64(1)...UInt64(3) {
            let now = Date(timeIntervalSince1970: 5_000 + TimeInterval(sequence))
            let request = ConnectionHeartbeatRequest(
                deviceID: pairedDevice.id,
                deviceName: pairedDevice.deviceName,
                platform: .iPhone,
                appInstanceID: "iphone-presence-test",
                sequenceNumber: sequence,
                sentAt: now,
                lastKnownPeerStatusRevision: statusStore.status(for: pairedDevice.id)?.connectionStatusRevision
            )
            let body = try encodedHeartbeatRequest(request)
            let response = handler.heartbeatResponse(
                method: "POST",
                path: "/connection/heartbeat",
                headers: try signedJSONHeaders(
                    device: pairedDevice,
                    path: "/connection/heartbeat",
                    body: body,
                    nonce: "writeback-heartbeat-\(sequence)",
                    now: now
                ),
                body: body,
                now: now
            )
            let decoded = try decodeHeartbeatResponse(response)

            #expect(response.statusCode == 200)
            #expect(decoded.receivedSequenceNumber == sequence)
            #expect(service.requestVerifier.lastTrace?.markDeviceSeenCalled == true)
            #expect(service.requestVerifier.lastTrace?.verifierSucceeded == true)
            let pairedLastSeen = try #require(pairedDeviceStore.device(for: pairedDevice.id)?.lastSeenAt)
            let statusLastSeen = try #require(statusStore.status(for: pairedDevice.id)?.lastSeenAt)
            let uiStatusLastSeen = try #require(service.connectionStatus(for: pairedDevice).lastSeenAt)
            #expect(pairedLastSeen == now)
            #expect(statusLastSeen == now)
            #expect(uiStatusLastSeen == now)
            lastSeenDates.append(statusLastSeen)
            await Task.yield()
        }

        #expect(lastSeenDates == lastSeenDates.sorted())
        #expect(lastSeenDates[1] > lastSeenDates[0])
        #expect(lastSeenDates[2] > lastSeenDates[1])
        #expect(pairedDeviceStore.devices.count == 1)
        #expect(service.presenceObservationRevision > initialRevision)
    }

    @MainActor
    @Test func pendingManualSyncRequestRedeliversUntilAcknowledgedAcrossHeartbeatAndProbe() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let pairedDevice = makeHeartbeatDevice()
        pairedDeviceStore.upsert(pairedDevice)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let requestVerifier = RequestVerifier(pairedDeviceStore: pairedDeviceStore)
        let heartbeatHandler = ConnectionHeartbeatRouteHandler(
            requestVerifier: requestVerifier,
            statusStore: statusStore,
            localPeerDeviceID: "mac-pending-sync-test"
        )

        let heartbeatSyncRunID = "sync-run-heartbeat"
        _ = statusStore.recordPendingSyncRequest(
            deviceID: pairedDevice.id,
            displayName: pairedDevice.deviceName,
            syncRunID: heartbeatSyncRunID,
            initiatorDeviceID: "mac-test"
        )
        let heartbeatBody = try encodedHeartbeatRequest(makeHeartbeatRequest(device: pairedDevice, sequenceNumber: 41))
        let heartbeatResponse = heartbeatHandler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/connection/heartbeat", body: heartbeatBody, nonce: "pending-sync-heartbeat"),
            body: heartbeatBody
        )
        let decodedHeartbeat = try decodeHeartbeatResponse(heartbeatResponse)
        let secondHeartbeatBody = try encodedHeartbeatRequest(makeHeartbeatRequest(device: pairedDevice, sequenceNumber: 42))
        let secondHeartbeatResponse = heartbeatHandler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/connection/heartbeat", body: secondHeartbeatBody, nonce: "pending-sync-heartbeat-second"),
            body: secondHeartbeatBody
        )
        let decodedSecondHeartbeat = try decodeHeartbeatResponse(secondHeartbeatResponse)

        #expect(decodedHeartbeat.syncRequested == true)
        #expect(decodedHeartbeat.syncStartSignal?.syncRunID == heartbeatSyncRunID)
        #expect(statusStore.status(for: pairedDevice.id)?.lastSyncStatus == "同步请求已投递，等待 iPhone 确认")
        #expect(decodedSecondHeartbeat.syncRequested == true)
        #expect(decodedSecondHeartbeat.syncStartSignal?.syncRunID == heartbeatSyncRunID)
        #expect(statusStore.acknowledgePendingSyncStartSignal(deviceID: pairedDevice.id, syncRunID: heartbeatSyncRunID))

        let probeSyncRunID = "sync-run-probe"
        _ = statusStore.recordPendingSyncRequest(
            deviceID: pairedDevice.id,
            displayName: pairedDevice.deviceName,
            syncRunID: probeSyncRunID,
            initiatorDeviceID: "mac-test"
        )
        let probeHandler = ConnectionProbeRouteHandler(requestVerifier: requestVerifier, statusStore: statusStore)
        let probeBody = try encodedConnectionProbeRequest(sequenceNumber: 43, clientPayload: "pending sync probe")
        let probeResponse = probeHandler.probeResponse(
            method: "POST",
            path: "/connection/probe",
            headers: try signedJSONHeaders(device: pairedDevice, path: "/connection/probe", body: probeBody, nonce: "pending-sync-probe"),
            body: probeBody
        )
        let probeJSON = try routeResponseJSON(probeResponse)

        #expect(probeJSON["syncRequested"] as? Bool == true)
        #expect((probeJSON["syncStartSignal"] as? [String: Any])?["syncRunID"] as? String == probeSyncRunID)
        #expect(statusStore.status(for: pairedDevice.id)?.lastSyncAt == nil)
    }

    @MainActor
    @Test func deviceStatusResponseMissingSyncRequestedDecodesFalse() throws {
        let response = try Self.connectionJSONDecoder.decode(DeviceStatusResponse.self, from: Data(#"{"ok":true}"#.utf8))

        #expect(response.ok)
        #expect(response.syncRequested == false)
        #expect(response.syncStartSignal == nil)
    }

    @MainActor
    @Test func pendingManualSyncRequestDeduplicatesAndTimesOut() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeHeartbeatDevice()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, pendingSyncRequestTimeout: 10)
        let startedAt = Date(timeIntervalSince1970: 10_000)

        _ = statusStore.recordPendingSyncRequest(
            deviceID: device.id,
            displayName: device.deviceName,
            syncRunID: "sync-first",
            initiatorDeviceID: "mac-test",
            reason: SyncTriggerReason.macAudioReceiveFinalized.rawValue,
            at: startedAt
        )
        _ = statusStore.recordPendingSyncRequest(
            deviceID: device.id,
            displayName: device.deviceName,
            syncRunID: "sync-duplicate",
            initiatorDeviceID: "mac-test",
            at: startedAt.addingTimeInterval(1)
        )

        let consumed = try #require(statusStore.consumePendingSyncStartSignal(deviceID: device.id))
        #expect(consumed.syncRunID == "sync-first")
        #expect(consumed.reason == SyncTriggerReason.macAudioReceiveFinalized.rawValue)

        _ = statusStore.recordPendingSyncRequest(
            deviceID: device.id,
            displayName: device.deviceName,
            syncRunID: "sync-timeout",
            initiatorDeviceID: "mac-test",
            at: startedAt
        )
        let timedOut = try #require(statusStore.status(for: device.id, now: startedAt.addingTimeInterval(11)))
        #expect(timedOut.lastSyncStatus == "等待 iPhone 前台响应超时")
        #expect(timedOut.lastErrorCode == "manual_sync_pending_timed_out")

        _ = statusStore.recordPendingSyncRequest(
            deviceID: device.id,
            displayName: device.deviceName,
            syncRunID: "sync-after-timeout",
            initiatorDeviceID: "mac-test",
            at: startedAt.addingTimeInterval(12)
        )
        let afterTimeout = try #require(statusStore.consumePendingSyncStartSignal(deviceID: device.id))
        #expect(afterTimeout.syncRunID == "sync-after-timeout")
    }

    @Test func macChecksumCacheHitsAndInvalidatesByFileAttributes() async throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let fileURL = rootURL.appendingPathComponent("audio.m4a", isDirectory: false)
        try Data("mac-audio".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: fileURL.path)

        let runtime = CanonicalChecksumRuntime()
        let cacheDirectoryURL = rootURL.appendingPathComponent("ChecksumCache", isDirectory: true)
        let logicalToken = "audio/inbox/audio.m4a"
        let first = await runtime.checksum(
            fileURL: fileURL,
            logicalToken: logicalToken,
            nodeRole: .mac,
            cacheDirectoryURL: cacheDirectoryURL
        )
        let second = await runtime.checksum(
            fileURL: fileURL,
            logicalToken: logicalToken,
            nodeRole: .mac,
            cacheDirectoryURL: cacheDirectoryURL
        )

        #expect(first.sha256 == MacSecurityUtilities.sha256Hex(Data("mac-audio".utf8)))
        #expect(first.event == CanonicalChecksumCacheEvent.miss)
        #expect(first.hashComputed)
        #expect(second.event == CanonicalChecksumCacheEvent.hit)
        #expect(!second.hashComputed)
        #expect(second.sha256 == first.sha256)

        try Data("mac-audio-changed".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 101)], ofItemAtPath: fileURL.path)
        let third = await runtime.checksum(
            fileURL: fileURL,
            logicalToken: logicalToken,
            nodeRole: .mac,
            cacheDirectoryURL: cacheDirectoryURL
        )

        #expect(third.event == CanonicalChecksumCacheEvent.stale)
        #expect(third.hashComputed)
        #expect(third.sha256 == MacSecurityUtilities.sha256Hex(Data("mac-audio-changed".utf8)))
        #expect(third.sha256 != first.sha256)
    }

    @MainActor
    @Test func unpairedAndBadHMACHeartbeatDoNotUpdatePresenceWriteback() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let pairedDevice = makeHeartbeatDevice()
        pairedDeviceStore.upsert(pairedDevice)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let handler = ConnectionHeartbeatRouteHandler(
            requestVerifier: RequestVerifier(pairedDeviceStore: pairedDeviceStore),
            statusStore: statusStore,
            localPeerDeviceID: "mac-presence-test"
        )
        let unknownDevice = PairedDevice(
            id: "unknown-iphone",
            deviceName: "Unknown iPhone",
            sharedSecretBase64URL: MacSecurityUtilities.randomBase64URLToken(),
            pairedAt: Date(timeIntervalSince1970: 1),
            lastSeenAt: nil
        )
        let unknownBody = try encodedHeartbeatRequest(makeHeartbeatRequest(device: unknownDevice, sequenceNumber: 1))
        let unknownResponse = handler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(device: unknownDevice, path: "/connection/heartbeat", body: unknownBody, nonce: "unknown-heartbeat"),
            body: unknownBody
        )
        #expect(unknownResponse.statusCode == 400)
        #expect(pairedDeviceStore.device(for: pairedDevice.id)?.lastSeenAt == nil)
        #expect(statusStore.latestStatus == nil)

        let badBody = try encodedHeartbeatRequest(makeHeartbeatRequest(device: pairedDevice, sequenceNumber: 2))
        var badHeaders = try signedJSONHeaders(device: pairedDevice, path: "/connection/heartbeat", body: badBody, nonce: "bad-hmac-heartbeat")
        badHeaders["X-Rokurics-Signature"] = "bad-signature"
        let badResponse = handler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: badHeaders,
            body: badBody
        )
        #expect(badResponse.statusCode == 400)
        #expect(pairedDeviceStore.device(for: pairedDevice.id)?.lastSeenAt == nil)
        #expect(statusStore.latestStatus == nil)
    }

    @MainActor
    @Test func devicelessUnpairedSecureRoutesRejectBeforeMutationSmoke() async throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let requestVerifier = RequestVerifier(pairedDeviceStore: pairedDeviceStore)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL.appendingPathComponent("ConnectionStatus", isDirectory: true))
        let heartbeatHandler = ConnectionHeartbeatRouteHandler(
            requestVerifier: requestVerifier,
            statusStore: statusStore,
            localPeerDeviceID: "mac-smoke-peer"
        )
        let probeHandler = ConnectionProbeRouteHandler(requestVerifier: requestVerifier)
        let recordingStore = MacRecordingFileStore(rootURL: rootURL.appendingPathComponent("Library", isDirectory: true))
        let uploadHandler = RecordingUploadRouteHandler(
            requestVerifier: requestVerifier,
            recordingFileStore: recordingStore,
            onRecordingAccepted: { _, _ in Issue.record("unpaired upload must not be accepted") }
        )
        let unpairedDevice = PairedDevice(
            id: "unpaired-smoke-device",
            deviceName: "Unpaired iPhone",
            sharedSecretBase64URL: Data("unpaired-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 4_000),
            lastSeenAt: nil
        )
        let heartbeatBody = try encodedHeartbeatRequest(makeHeartbeatRequest(device: unpairedDevice, sequenceNumber: 7))
        let probeBody = try encodedConnectionProbeRequest(sequenceNumber: 8, clientPayload: "unpaired smoke")
        let metadata = makeIncomingUploadMetadata(id: "unpaired-smoke-recording")
        let metadataBody = try encodedMetadata(metadata)
        let audio = Data("audio".utf8)

        let heartbeatResponse = heartbeatHandler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(device: unpairedDevice, path: "/connection/heartbeat", body: heartbeatBody, nonce: "unpaired-smoke-heartbeat"),
            body: heartbeatBody
        )
        let probeResponse = probeHandler.probeResponse(
            method: "POST",
            path: "/connection/probe",
            headers: try signedJSONHeaders(device: unpairedDevice, path: "/connection/probe", body: probeBody, nonce: "unpaired-smoke-probe"),
            body: probeBody
        )
        let syncInventoryResult = requestVerifier.verify(
            method: "POST",
            path: "/sync/inventory",
            headers: try signedJSONHeaders(device: unpairedDevice, path: "/sync/inventory", body: Data("{}".utf8), nonce: "unpaired-smoke-sync"),
            body: Data("{}".utf8)
        )
        let metadataResponse = await uploadHandler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: unpairedDevice, path: "/upload-recording-metadata", body: metadataBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "unpaired-smoke-metadata"),
            body: metadataBody
        )
        let audioResponse = await uploadHandler.audioUploadResponse(
            method: "POST",
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(device: unpairedDevice, path: "/upload-recording-audio", body: audio, contentType: "audio/m4a", uploadType: "recording-audio", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "unpaired-smoke-audio"),
            body: audio
        )

        #expect(heartbeatResponse.statusCode == 400)
        #expect((try routeResponseJSON(heartbeatResponse))["error"] as? String == "unknown_device")
        #expect(probeResponse.statusCode == 400)
        #expect((try routeResponseJSON(probeResponse))["error"] as? String == "unknown_device")
        switch syncInventoryResult {
        case .accepted:
            Issue.record("unpaired /sync/inventory unexpectedly accepted")
        case .rejected(let reason):
            #expect(reason == "unknown_device")
        }
        #expect(metadataResponse.statusCode == 400)
        #expect((try routeResponseJSON(metadataResponse))["error"] as? String == "unknown_device")
        #expect(audioResponse.statusCode == 400)
        #expect((try routeResponseJSON(audioResponse))["error"] as? String == "unknown_device")
        #expect(pairedDeviceStore.devices.isEmpty)
        #expect(statusStore.latestStatus == nil)
        #expect(recordingStore.loadInboxItems().isEmpty)
    }

    @MainActor
    @Test func pairingBootstrapPathIsNotMatchedByPairedHMACRouteRules() throws {
        let verifier = RequestVerifier(pairedDeviceProvider: { _ in nil })
        let result = verifier.verify(
            method: "POST",
            path: "/pair",
            headers: ["Content-Type": "application/json"],
            body: Data(#"{"pairingCode":"123456"}"#.utf8)
        )

        switch result {
        case .accepted:
            Issue.record("/pair must not be accepted by paired HMAC verifier")
        case .rejected(let reason):
            #expect(reason == "path_not_allowed")
        }
    }

    @MainActor
    @Test func unpairedHeartbeatSyncAndUploadSecureRoutesRemainRejected() throws {
        let device = makeHeartbeatDevice()
        let verifier = RequestVerifier(pairedDeviceProvider: { _ in nil })
        let now = Date(timeIntervalSince1970: 3_200)
        let jsonBody = Data("{}".utf8)

        let heartbeat = verifier.verify(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(device: device, path: "/connection/heartbeat", body: jsonBody, nonce: "unpaired-heartbeat", now: now),
            body: jsonBody,
            now: now
        )
        let probeBody = try encodedConnectionProbeRequest(sequenceNumber: 1, clientPayload: "unpaired verifier probe", sentAt: now)
        let probe = verifier.verify(
            method: "POST",
            path: "/connection/probe",
            headers: try signedJSONHeaders(device: device, path: "/connection/probe", body: probeBody, nonce: "unpaired-probe", now: now),
            body: probeBody,
            now: now
        )
        let sync = verifier.verify(
            method: "POST",
            path: "/sync/inventory",
            headers: try signedJSONHeaders(device: device, path: "/sync/inventory", body: jsonBody, nonce: "unpaired-sync", now: now),
            body: jsonBody,
            now: now
        )
        let audioBody = Data("audio".utf8)
        let upload = verifier.verify(
            method: "POST",
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio", body: audioBody, contentType: "audio/m4a", uploadType: "recording-audio", recordingID: "unpaired-audio", fileName: "audio.m4a", nonce: "unpaired-upload"),
            body: audioBody
        )

        for result in [heartbeat, probe, sync, upload] {
            switch result {
            case .accepted:
                Issue.record("unpaired secure route unexpectedly accepted")
            case .rejected(let reason):
                #expect(reason == "unknown_device")
            }
        }
    }

    @MainActor
    @Test func badHMACSecureRequestDoesNotMutatePairingPresenceState() throws {
        let device = makeHeartbeatDevice()
        var didMarkSeen = false
        let verifier = RequestVerifier(
            pairedDeviceProvider: { id in id == device.id ? device : nil },
            markDeviceSeen: { _, _ in didMarkSeen = true }
        )
        let now = Date(timeIntervalSince1970: 3_300)
        let body = Data("{}".utf8)
        var headers = try signedJSONHeaders(device: device, path: "/connection/heartbeat", body: body, nonce: "bad-hmac-mutation", now: now)
        headers["X-Rokurics-Signature"] = "bad-signature"

        let result = verifier.verify(
            method: "POST",
            path: "/connection/heartbeat",
            headers: headers,
            body: body,
            now: now
        )

        switch result {
        case .accepted:
            Issue.record("bad HMAC secure request unexpectedly accepted")
        case .rejected(let reason):
            #expect(reason == "signature_mismatch")
        }
        #expect(!didMarkSeen)

        let probeBody = try encodedConnectionProbeRequest(sequenceNumber: 2, clientPayload: "bad hmac probe", sentAt: now)
        var probeHeaders = try signedJSONHeaders(device: device, path: "/connection/probe", body: probeBody, nonce: "bad-hmac-probe", now: now)
        probeHeaders["X-Rokurics-Signature"] = "bad-signature"
        let probeResult = verifier.verify(
            method: "POST",
            path: "/connection/probe",
            headers: probeHeaders,
            body: probeBody,
            now: now
        )

        switch probeResult {
        case .accepted:
            Issue.record("bad HMAC probe unexpectedly accepted")
        case .rejected(let reason):
            #expect(reason == "signature_mismatch")
        }
        #expect(!didMarkSeen)
    }

    @Test func macTLSIdentityUsesAppLocalNonInteractiveIdentityWithoutProvisioningEntitlements() throws {
        let source = try sourceText("RokuricsMac/MacIdentityManager.swift")
        let profileSource = try sourceText("RokuricsMac/MacAppStorageProfile.swift")

        #expect(source.contains("tls-private-key.json"))
        #expect(source.contains("SecKeyCreateWithData"))
        #expect(source.contains("SecIdentityCreate(nil, certificate, privateKey)"))
        #expect(source.contains("certificate(existingCertificate, matches: key)"))
        #expect(!source.contains("kSecUseDataProtectionKeychain"))
        #expect(!source.contains("SecItemAdd"))
        #expect(!source.contains("SecItemCopyMatching"))
        #expect(!source.contains("SecAccessControlCreateWithFlags"))
        #expect(!source.contains(".privateKeyUsage"))
        #expect(!source.contains("kSecAttrAccessControl"))
        #expect(!source.contains("Apple Development"))
        #expect(!profileSource.contains(".tls.private-key.dp.noninteractive.v2"))
        #expect(!profileSource.contains("TLS Private Key DP v2"))
    }

    @Test func macHTTPSServerStartupSourceUsesNonInteractiveTLSIdentity() throws {
        let serverSource = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")
        let identitySource = try sourceText("RokuricsMac/MacIdentityManager.swift")

        #expect(serverSource.contains("identityManager.tlsOptions()"))
        #expect(serverSource.contains("NWParameters(tls: tlsOptions"))
        #expect(identitySource.contains("sec_protocol_options_set_local_identity"))
        #expect(identitySource.contains("SecIdentityCreate(nil, certificate, privateKey)"))
        #expect(!identitySource.contains("kSecUseDataProtectionKeychain"))
        #expect(!identitySource.contains("SecAccessControlCreateWithFlags"))
        #expect(!identitySource.contains(".privateKeyUsage"))
        #expect(!identitySource.contains("kSecAttrAccessControl"))
        #expect(!identitySource.contains("Apple Development"))
    }

    @Test func secureReceiverServiceDefersPairingPayloadUntilHTTPSListenerReady() throws {
        let source = try sourceText("RokuricsMac/SecureReceiverService.swift")

        #expect(source.contains("pendingPairingStartAfterHTTPSReady"))
        #expect(source.contains("completePendingPairingIfPossible(trigger: \"listener_ready\")"))
        #expect(source.contains("completePendingPairingIfPossible(trigger: \"begin_pairing_already_ready\")"))
        #expect(source.contains("pairing deferred until HTTPS listener ready"))
        #expect(source.contains("guard let httpsServer, httpsServer.isReady else"))
        #expect(source.contains("pairing_waiting_for_listener_ready"))
    }

    @Test func macTLSIdentityProviderDoesNotLogPrivateKeyMaterial() throws {
        let source = try sourceText("RokuricsMac/MacIdentityManager.swift")

        #expect(!source.contains("print(\"[RokuricsIdentity] privateKey"))
        #expect(!source.contains("print(\"[RokuricsIdentity] keyData"))
        #expect(!source.contains("print(\"[RokuricsIdentity] tlsPrivateKey"))
        #expect(!source.contains("print(\"[RokuricsSecurity] sharedSecret"))
    }

    @MainActor
    @Test func heartbeatRouteRejectsUnpairedAndBadSignatureBeforeLastSeenMutation() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeHeartbeatDevice()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let request = makeHeartbeatRequest(device: device, sequenceNumber: 1)
        let body = try encodedHeartbeatRequest(request)
        let handler = ConnectionHeartbeatRouteHandler(
            requestVerifier: RequestVerifier(pairedDeviceProvider: { id in id == device.id ? device : nil }),
            statusStore: statusStore,
            localPeerDeviceID: "mac-local"
        )
        let badSignatureNow = Date(timeIntervalSince1970: 2_000)
        var badHeaders = try signedJSONHeaders(
            device: device,
            path: "/connection/heartbeat",
            body: body,
            nonce: "heartbeat-bad-signature",
            now: badSignatureNow
        )
        badHeaders["X-Rokurics-Signature"] = "bad-signature"

        let badSignatureResponse = handler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: badHeaders,
            body: body,
            now: badSignatureNow
        )
        let unpairedHandler = ConnectionHeartbeatRouteHandler(
            requestVerifier: RequestVerifier(pairedDeviceProvider: { _ in nil }),
            statusStore: statusStore,
            localPeerDeviceID: "mac-local"
        )
        let unpairedNow = Date(timeIntervalSince1970: 2_001)
        let unpairedResponse = unpairedHandler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: device,
                path: "/connection/heartbeat",
                body: body,
                nonce: "heartbeat-unpaired",
                now: unpairedNow
            ),
            body: body,
            now: unpairedNow
        )

        #expect(badSignatureResponse.statusCode == 400)
        #expect((try routeResponseJSON(badSignatureResponse))["error"] as? String == "signature_mismatch")
        #expect(unpairedResponse.statusCode == 400)
        #expect((try routeResponseJSON(unpairedResponse))["error"] as? String == "unknown_device")
        #expect(statusStore.status(for: device.id) == nil)
    }

    @MainActor
    @Test func validHeartbeatReturnsPongAndUpdatesLastSeen() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeHeartbeatDevice()
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let request = makeHeartbeatRequest(device: device, sequenceNumber: 42)
        let body = try encodedHeartbeatRequest(request)
        let handler = ConnectionHeartbeatRouteHandler(
            requestVerifier: RequestVerifier(pairedDeviceProvider: { id in id == device.id ? device : nil }),
            statusStore: statusStore,
            localPeerDeviceID: "mac-local"
        )
        let now = Date(timeIntervalSince1970: 2_100)

        let response = handler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: device,
                path: "/connection/heartbeat",
                body: body,
                nonce: "heartbeat-valid",
                now: now
            ),
            body: body,
            now: now
        )
        let decoded = try decodeHeartbeatResponse(response)
        let status = try #require(statusStore.status(for: device.id, now: now))

        #expect(response.statusCode == 200)
        #expect(decoded.ok)
        #expect(decoded.disposition == "ok")
        #expect(decoded.receivedSequenceNumber == 42)
        #expect(decoded.peerDeviceID == "mac-local")
        #expect(status.presenceState == .online)
        #expect(status.lastSuccessfulHeartbeatAt == Date(timeIntervalSince1970: 2_100))
        #expect(String(data: response.bodyData, encoding: .utf8)?.contains(device.sharedSecretBase64URL) == false)
        #expect(!FileManager.default.fileExists(atPath: rootURL.appendingPathComponent("audio", isDirectory: true).path))
    }

    @MainActor
    @Test func pairedDevicePresenceBecomesStaleThenDisconnectedAfterThresholds() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = DeviceConnectionStatusStore(rootURL: rootURL, staleAfter: 6, disconnectedAfter: 10)
        let device = makeHeartbeatDevice()

        _ = store.recordHeartbeatSuccess(
            deviceID: device.id,
            displayName: device.deviceName,
            sentAt: Date(timeIntervalSince1970: 0),
            receivedAt: Date(timeIntervalSince1970: 0),
            latencyMilliseconds: 1
        )
        let stale = try #require(store.status(for: device.id, now: Date(timeIntervalSince1970: 7)))
        let disconnected = try #require(store.status(for: device.id, now: Date(timeIntervalSince1970: 11)))

        #expect(stale.presenceState == .interrupted)
        #expect(stale.state == .offline)
        #expect(disconnected.presenceState == .disconnected)
        #expect(disconnected.state == .offline)
    }

    @MainActor
    @Test func macPresenceEvaluationResumesWithoutFakingLastSeen() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let device = makeHeartbeatDevice()
        pairedDeviceStore.upsert(device)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let service = SecureReceiverService(
            pairedDeviceStore: pairedDeviceStore,
            deviceConnectionStatusStore: statusStore,
            connectionDiagnosticsStore: diagnosticsStore,
            loadIdentityOnInit: false,
            preferredIPAddressProvider: { "127.0.0.1" }
        )
        let lastSeen = Date()
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: device.id,
            displayName: device.deviceName,
            sentAt: lastSeen,
            receivedAt: lastSeen,
            latencyMilliseconds: 1
        )
        _ = statusStore.markMonitoringSuspended(deviceID: device.id, displayName: device.deviceName)

        service.appBecameActive()
        let resumed = try #require(statusStore.status(for: device.id, now: lastSeen))
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(resumed.monitoringMode == .foregroundActive)
        #expect(resumed.lastSeenAt == lastSeen)
        #expect(phases.contains("appBecameActive"))
        #expect(phases.contains("presenceEvaluatorResumed"))
    }

    @MainActor
    @Test func macManualSyncDisabledCreatesPendingRequestWithoutFakeSuccess() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let device = makeHeartbeatDevice()
        pairedDeviceStore.upsert(device)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let service = SecureReceiverService(
            pairedDeviceStore: pairedDeviceStore,
            deviceConnectionStatusStore: statusStore,
            syncStateStore: syncStateStore,
            connectionDiagnosticsStore: diagnosticsStore,
            loadIdentityOnInit: false,
            preferredIPAddressProvider: { "127.0.0.1" }
        )
        let lastSeen = Date()
        _ = statusStore.recordHeartbeatSuccess(
            deviceID: device.id,
            displayName: device.deviceName,
            sentAt: lastSeen,
            receivedAt: lastSeen,
            latencyMilliseconds: 1
        )

        let manualStatus = service.prepareManualStudyLibrarySync(for: device)
        let observedStatus = service.connectionStatus(for: device)
        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(manualStatus.presenceState == .online)
        #expect(observedStatus.presenceState == .online)
        #expect(observedStatus.lastSeenAt == lastSeen)
        #expect(observedStatus.lastSyncAt == nil)
        #expect(observedStatus.lastSyncStatus == "等待 iPhone 执行同步")
        #expect(phases.contains("manualSyncTapped"))
        #expect(phases.contains("manualSyncActionFired"))
        #expect(phases.contains("pendingSyncRequestCreated"))
        #expect(phases.contains("pendingSyncRequestSet"))
    }

    @MainActor
    @Test func macManualSyncDuplicateReusesPendingRunIDForControlPlane() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let device = makeHeartbeatDevice()
        pairedDeviceStore.upsert(device)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL, pendingSyncRequestTimeout: 30)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let service = SecureReceiverService(
            pairedDeviceStore: pairedDeviceStore,
            deviceConnectionStatusStore: statusStore,
            syncStateStore: syncStateStore,
            connectionDiagnosticsStore: diagnosticsStore,
            loadIdentityOnInit: false,
            preferredIPAddressProvider: { "127.0.0.1" }
        )

        _ = service.prepareManualStudyLibrarySync(for: device)
        let firstRunID = try #require(syncStateStore.state.activeSyncRunID)
        _ = service.prepareManualStudyLibrarySync(for: device)
        let phases = diagnosticsStore.loadEntries().map(\.phase)

        #expect(syncStateStore.state.activeSyncRunID == firstRunID)
        #expect(syncStateStore.state.syncControlPlaneState == .syncStartSignalSent)
        #expect(statusStore.pendingSyncRequestCountForDiagnostics == 1)
        #expect(phases.contains("pendingSyncRequestDuplicate"))
    }

    @MainActor
    @Test func macManualDisconnectDeletesCredentialsAndReturnsToUnpaired() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let device = makeHeartbeatDevice()
        pairedDeviceStore.upsert(device)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let service = SecureReceiverService(
            pairedDeviceStore: pairedDeviceStore,
            deviceConnectionStatusStore: statusStore,
            connectionDiagnosticsStore: diagnosticsStore,
            loadIdentityOnInit: false,
            preferredIPAddressProvider: { "127.0.0.1" }
        )

        service.disconnectPairedDevices()

        let phases = Set(diagnosticsStore.loadEntries().map(\.phase))

        #expect(pairedDeviceStore.deviceCount == 0)
        #expect(pairedDeviceStore.device(for: device.id) == nil)
        #expect(statusStore.status(for: device.id) == nil)
        #expect(service.latestPairedDevice == nil)
        #expect(phases.contains("disconnectTapped"))
        #expect(phases.contains("localCredentialsDeleted"))
        #expect(phases.contains("userConnectionIntentChanged"))
    }

    @MainActor
    @Test func macStartPairingAfterDisconnectDoesNotReuseOldCredentials() async throws {
        let harness = try makeSecureReceiverServiceHarness()
        defer {
            harness.service.stopSecureReceiving()
            try? FileManager.default.removeItem(at: harness.rootURL)
        }
        let pairedDeviceStore = harness.pairedDeviceStore
        var device = makeHeartbeatDevice()
        device.userConnectionIntent = .disconnectedByUser
        pairedDeviceStore.upsert(device)

        harness.service.beginPairing()
        let payload = try await waitForPairingPayload(harness.service)
        let phases = Set(harness.diagnosticsStore.loadEntries().map(\.phase))

        #expect(pairedDeviceStore.device(for: device.id) == nil)
        #expect(harness.service.latestPairedDevice == nil)
        #expect(payload.pairingCode.count == 6)
        #expect(phases.contains("startPairingAfterDisconnect"))
        #expect(phases.contains("pairing_code_issued"))
    }

    @MainActor
    @Test func macPairedDeviceIntentPersistsAcrossStoreReload() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let store = PairedDeviceStore(rootURL: securityURL)
        let device = makeHeartbeatDevice()
        store.upsert(device)
        store.setUserConnectionIntent(.disconnectedByUser, for: device.id)

        let reloaded = PairedDeviceStore(rootURL: securityURL)
        let stored = try #require(reloaded.device(for: device.id))

        #expect(reloaded.deviceCount == 1)
        #expect(stored.sharedSecretBase64URL == device.sharedSecretBase64URL)
        #expect(stored.resolvedConnectionIntent == .disconnectedByUser)
    }

    @MainActor
    @Test func macWindowClosePreservesCredentialsAndIntent() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let pairedDeviceStore = PairedDeviceStore(rootURL: rootURL.appendingPathComponent("Security", isDirectory: true))
        let device = makeHeartbeatDevice()
        pairedDeviceStore.upsert(device)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let service = SecureReceiverService(
            pairedDeviceStore: pairedDeviceStore,
            deviceConnectionStatusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            connectionDiagnosticsStore: diagnosticsStore,
            loadIdentityOnInit: false,
            preferredIPAddressProvider: { "127.0.0.1" }
        )

        service.recordWindowClosed()
        let stored = try #require(pairedDeviceStore.device(for: device.id))

        #expect(stored.sharedSecretBase64URL == device.sharedSecretBase64URL)
        #expect(stored.resolvedConnectionIntent == .wantsConnected)
        #expect(diagnosticsStore.loadEntries().contains { $0.phase == "windowClosed" })
    }

    @MainActor
    @Test func heartbeatPayloadAndResponseContainNoSecretsOrFileData() throws {
        let rootURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeHeartbeatDevice()
        let request = makeHeartbeatRequest(device: device, sequenceNumber: 9)
        let body = try encodedHeartbeatRequest(request)
        let handler = ConnectionHeartbeatRouteHandler(
            requestVerifier: RequestVerifier(pairedDeviceProvider: { id in id == device.id ? device : nil }),
            statusStore: DeviceConnectionStatusStore(rootURL: rootURL),
            localPeerDeviceID: "mac-local"
        )
        let now = Date(timeIntervalSince1970: 2_200)
        let response = handler.heartbeatResponse(
            method: "POST",
            path: "/connection/heartbeat",
            headers: try signedJSONHeaders(
                device: device,
                path: "/connection/heartbeat",
                body: body,
                nonce: "heartbeat-no-secret",
                now: now
            ),
            body: body,
            now: now
        )
        let combined = [
            String(data: body, encoding: .utf8) ?? "",
            String(data: response.bodyData, encoding: .utf8) ?? ""
        ].joined(separator: "\n").lowercased()

        #expect(!combined.contains(device.sharedSecretBase64URL.lowercased()))
        #expect(!combined.contains("sharedsecret"))
        #expect(!combined.contains("hmac"))
        #expect(!combined.contains("manifest"))
        #expect(!combined.contains("transcript"))
        #expect(!combined.contains("audio"))
        #expect(!combined.contains("note"))
    }

    @Test func resumableStartCreatesSessionAndRepeatedStartIsIdempotent() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let audio = Data("abcdef".utf8)
        let metadata = makeIncomingUploadMetadata(id: "resumable-start-01", fileSize: Int64(audio.count))
        _ = try store.saveMetadata(metadata, sourceDevice: device)
        let request = makeResumableStartRequest(metadata: metadata, audio: audio, chunkSize: 3)

        let first = try await store.startResumableAudioUpload(request, sourceDevice: device)
        let second = try await store.startResumableAudioUpload(request, sourceDevice: device)
        let sessionID = try #require(first.sessionID)
        let sessionURL = rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("upload-sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("session.json", isDirectory: false)
        let partURL = sessionURL.deletingLastPathComponent().appendingPathComponent("audio.part", isDirectory: false)

        #expect(first.disposition == RecordingUploadDisposition.acceptedNew.rawValue)
        #expect(second.disposition == RecordingUploadDisposition.acceptedExisting.rawValue)
        #expect(second.confirmedBytes == 0)
        #expect(FileManager.default.fileExists(atPath: sessionURL.path))
        #expect(FileManager.default.fileExists(atPath: partURL.path))
        #expect((try String(contentsOf: sessionURL)).contains(device.sharedSecretBase64URL) == false)
    }

    @Test func resumableChangedContentContractExpiresOldSessionAndStartsFresh() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let audio = Data("abcdef".utf8)
        let metadata = makeIncomingUploadMetadata(id: "resumable-start-conflict", fileSize: Int64(audio.count))
        _ = try store.saveMetadata(metadata, sourceDevice: device)
        let request = makeResumableStartRequest(metadata: metadata, audio: audio, chunkSize: 3)
        let first = try await store.startResumableAudioUpload(request, sourceDevice: device)
        let conflicting = ResumableAudioUploadStartRequest(
            recordingID: request.recordingID,
            fileName: request.fileName,
            totalBytes: request.totalBytes,
            totalSHA256: MacSecurityUtilities.sha256Hex(Data("xxxxxx".utf8)),
            chunkSize: request.chunkSize,
            metadataHash: nil,
            uploadJobID: nil
        )

        let restarted = try await store.startResumableAudioUpload(conflicting, sourceDevice: device)

        #expect(restarted.disposition == RecordingUploadDisposition.acceptedNew.rawValue)
        #expect(restarted.confirmedBytes == 0)
        #expect(restarted.sessionID != first.sessionID)
    }

    @Test func resumableChunkStatusFinalizeAndRepeatedFinalizeAreIdempotent() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let audio = Data("abcdef".utf8)
        let firstChunk = Data("abc".utf8)
        let secondChunk = Data("def".utf8)
        let metadata = makeIncomingUploadMetadata(id: "resumable-finalize-01", fileSize: Int64(audio.count))
        _ = try store.saveMetadata(metadata, sourceDevice: device)
        let request = makeResumableStartRequest(metadata: metadata, audio: audio, chunkSize: 3)
        let start = try await store.startResumableAudioUpload(request, sourceDevice: device)
        let sessionID = try #require(start.sessionID)

        let chunk1 = try await store.appendResumableAudioChunk(
            recordingID: metadata.id,
            sessionID: sessionID,
            offset: 0,
            length: firstChunk.count,
            chunkSHA256: MacSecurityUtilities.sha256Hex(firstChunk),
            totalSHA256: request.totalSHA256,
            body: firstChunk,
            sourceDevice: device
        )
        let duplicateChunk1 = try await store.appendResumableAudioChunk(
            recordingID: metadata.id,
            sessionID: sessionID,
            offset: 0,
            length: firstChunk.count,
            chunkSHA256: MacSecurityUtilities.sha256Hex(firstChunk),
            totalSHA256: request.totalSHA256,
            body: firstChunk,
            sourceDevice: device
        )
        let status = try await store.resumableAudioUploadStatus(
            ResumableAudioUploadStatusRequest(recordingID: metadata.id, sessionID: sessionID, totalSHA256: request.totalSHA256),
            sourceDevice: device
        )

        #expect(chunk1.disposition == RecordingUploadDisposition.acceptedNew.rawValue)
        #expect(chunk1.confirmedBytes == 3)
        #expect(duplicateChunk1.disposition == RecordingUploadDisposition.acceptedExisting.rawValue)
        #expect(status.confirmedBytes == 3)
        #expect(status.nextOffset == 3)

        do {
            _ = try await store.appendResumableAudioChunk(
                recordingID: metadata.id,
                sessionID: sessionID,
                offset: 5,
                length: secondChunk.count,
                chunkSHA256: MacSecurityUtilities.sha256Hex(secondChunk),
                totalSHA256: request.totalSHA256,
                body: secondChunk,
                sourceDevice: device
            )
            Issue.record("Expected offset gap to be rejected")
        } catch MacRecordingFileStoreError.chunkOffsetMismatch {
            #expect(true)
        }

        _ = try await store.appendResumableAudioChunk(
            recordingID: metadata.id,
            sessionID: sessionID,
            offset: 3,
            length: secondChunk.count,
            chunkSHA256: MacSecurityUtilities.sha256Hex(secondChunk),
            totalSHA256: request.totalSHA256,
            body: secondChunk,
            sourceDevice: device
        )
        let finalized = try await store.finalizeResumableAudioUpload(
            ResumableAudioUploadFinalizeRequest(recordingID: metadata.id, sessionID: sessionID, totalBytes: Int64(audio.count), totalSHA256: request.totalSHA256),
            sourceDevice: device
        )
        let repeatedFinalize = try await store.finalizeResumableAudioUpload(
            ResumableAudioUploadFinalizeRequest(recordingID: metadata.id, sessionID: sessionID, totalBytes: Int64(audio.count), totalSHA256: request.totalSHA256),
            sourceDevice: device
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)
        let finalAudioURL = rootURL.appendingPathComponent(record.audioRelativePath ?? "", isDirectory: false)

        #expect(finalized.disposition == RecordingUploadDisposition.acceptedNew.rawValue)
        #expect(repeatedFinalize.disposition == RecordingUploadDisposition.acceptedExisting.rawValue)
        #expect(record.status == "completed")
        #expect(record.processingStatus == "notStarted")
        #expect(record.checksum == request.totalSHA256)
        #expect(try Data(contentsOf: finalAudioURL) == audio)
    }

    @Test func resumableDuplicateConflictingChunkMarksSessionFatal() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let audio = Data("abcdef".utf8)
        let firstChunk = Data("abc".utf8)
        let metadata = makeIncomingUploadMetadata(id: "resumable-conflict-chunk", fileSize: Int64(audio.count))
        _ = try store.saveMetadata(metadata, sourceDevice: device)
        let request = makeResumableStartRequest(metadata: metadata, audio: audio, chunkSize: 3)
        let sessionID = try #require(try await store.startResumableAudioUpload(request, sourceDevice: device).sessionID)

        _ = try await store.appendResumableAudioChunk(
            recordingID: metadata.id,
            sessionID: sessionID,
            offset: 0,
            length: firstChunk.count,
            chunkSHA256: MacSecurityUtilities.sha256Hex(firstChunk),
            totalSHA256: request.totalSHA256,
            body: firstChunk,
            sourceDevice: device
        )

        do {
            let conflictingChunk = Data("zzz".utf8)
            _ = try await store.appendResumableAudioChunk(
                recordingID: metadata.id,
                sessionID: sessionID,
                offset: 0,
                length: conflictingChunk.count,
                chunkSHA256: MacSecurityUtilities.sha256Hex(conflictingChunk),
                totalSHA256: request.totalSHA256,
                body: conflictingChunk,
                sourceDevice: device
            )
            Issue.record("Expected duplicate conflicting chunk to be rejected")
        } catch MacRecordingFileStoreError.audioConflict {
            #expect(true)
        }

        do {
            let secondChunk = Data("def".utf8)
            _ = try await store.appendResumableAudioChunk(
                recordingID: metadata.id,
                sessionID: sessionID,
                offset: 3,
                length: secondChunk.count,
                chunkSHA256: MacSecurityUtilities.sha256Hex(secondChunk),
                totalSHA256: request.totalSHA256,
                body: secondChunk,
                sourceDevice: device
            )
            Issue.record("Expected conflicted session to reject later chunks")
        } catch MacRecordingFileStoreError.sessionConflict {
            #expect(true)
        }

        do {
            _ = try await store.finalizeResumableAudioUpload(
                ResumableAudioUploadFinalizeRequest(recordingID: metadata.id, sessionID: sessionID, totalBytes: Int64(audio.count), totalSHA256: request.totalSHA256),
                sourceDevice: device
            )
            Issue.record("Expected conflicted session to reject finalize")
        } catch MacRecordingFileStoreError.sessionConflict {
            #expect(true)
        }
    }

    @Test func resumableInvalidSessionIDIsRejected() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "resumable-invalid-session", fileSize: 6)
        _ = try store.saveMetadata(metadata, sourceDevice: device)

        do {
            _ = try await store.resumableAudioUploadStatus(
                ResumableAudioUploadStatusRequest(recordingID: metadata.id, sessionID: "../escape", totalSHA256: String(repeating: "a", count: 64)),
                sourceDevice: device
            )
            Issue.record("Expected path traversal sessionID to be rejected")
        } catch MacRecordingFileStoreError.invalidSession {
            #expect(true)
        }
    }

    @Test func resumableSessionSymlinkEscapeIsRejected() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let device = makeUploadDevice()
        let metadata = makeIncomingUploadMetadata(id: "resumable-symlink-session", fileSize: 6)
        _ = try store.saveMetadata(metadata, sourceDevice: device)
        let uploadSessionsURL = rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("upload-sessions", isDirectory: true)
        let outsideURL = rootURL.appendingPathComponent("outside-sessions", isDirectory: true)
        let symlinkURL = uploadSessionsURL.appendingPathComponent("session-escape", isDirectory: true)
        try FileManager.default.createDirectory(at: uploadSessionsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: outsideURL)

        do {
            _ = try await store.resumableAudioUploadStatus(
                ResumableAudioUploadStatusRequest(recordingID: metadata.id, sessionID: "session-escape", totalSHA256: String(repeating: "a", count: 64)),
                sourceDevice: device
            )
            Issue.record("Expected symlink session escape to be rejected")
        } catch MacRecordingFileStoreError.unsafeDestination {
            #expect(true)
        }
    }

    @MainActor
    @Test func resumableRouteHappyPathAndResumeStatusUseSignedRequests() async throws {
        let (handler, _, rootURL, device) = try makeRecordingUploadRouteHandler()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let audio = Data("abcdef".utf8)
        let firstChunk = Data("abc".utf8)
        let secondChunk = Data("def".utf8)
        let metadata = makeIncomingUploadMetadata(id: "route-resumable-happy", fileSize: Int64(audio.count))
        let metadataBody = try encodedMetadata(metadata)
        _ = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-metadata", body: metadataBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-resumable-metadata"),
            body: metadataBody
        )
        let startRequest = makeResumableStartRequest(metadata: metadata, audio: audio, chunkSize: 3)
        let startBody = try encodedResumableRequest(startRequest)
        let startResponse = await handler.resumableAudioStartResponse(
            method: "POST",
            path: "/upload-recording-audio-session/start",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio-session/start", body: startBody, contentType: "application/json", uploadType: "recording-audio-session", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-resumable-start"),
            body: startBody
        )
        let startJSON = try decodeResumableResponse(startResponse)
        let sessionID = try #require(startJSON.sessionID)

        let chunk1Response = await handler.resumableAudioChunkResponse(
            method: "POST",
            path: "/upload-recording-audio-session/chunk",
            headers: try signedChunkHeaders(device: device, recordingID: metadata.id, sessionID: sessionID, offset: 0, chunk: firstChunk, totalSHA256: startRequest.totalSHA256, nonce: "nonce-route-resumable-chunk-1"),
            body: firstChunk
        )
        let statusRequest = ResumableAudioUploadStatusRequest(recordingID: metadata.id, sessionID: sessionID, totalSHA256: startRequest.totalSHA256)
        let statusBody = try encodedResumableRequest(statusRequest)
        let statusResponse = await handler.resumableAudioStatusResponse(
            method: "POST",
            path: "/upload-recording-audio-session/status",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio-session/status", body: statusBody, contentType: "application/json", uploadType: "recording-audio-session", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-resumable-status"),
            body: statusBody
        )
        _ = await handler.resumableAudioChunkResponse(
            method: "POST",
            path: "/upload-recording-audio-session/chunk",
            headers: try signedChunkHeaders(device: device, recordingID: metadata.id, sessionID: sessionID, offset: 3, chunk: secondChunk, totalSHA256: startRequest.totalSHA256, nonce: "nonce-route-resumable-chunk-2"),
            body: secondChunk
        )
        let finalizeRequest = ResumableAudioUploadFinalizeRequest(recordingID: metadata.id, sessionID: sessionID, totalBytes: Int64(audio.count), totalSHA256: startRequest.totalSHA256)
        let finalizeBody = try encodedResumableRequest(finalizeRequest)
        let finalizeResponse = await handler.resumableAudioFinalizeResponse(
            method: "POST",
            path: "/upload-recording-audio-session/finalize",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio-session/finalize", body: finalizeBody, contentType: "application/json", uploadType: "recording-audio-session", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-resumable-finalize"),
            body: finalizeBody
        )
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: metadata.id)

        #expect(startResponse.statusCode == 200)
        #expect(chunk1Response.statusCode == 200)
        #expect((try decodeResumableResponse(statusResponse)).confirmedBytes == 3)
        #expect(finalizeResponse.statusCode == 200)
        #expect((try decodeResumableResponse(finalizeResponse)).completed)
        #expect(record.status == "completed")
        #expect(record.processingStatus == "notStarted")
    }

    @MainActor
    @Test func resumableChangedContractRestartsAndBadSignatureDoesNotLeakOrMutate() async throws {
        let (handler, store, rootURL, device) = try makeRecordingUploadRouteHandler()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let audio = Data("abcdef".utf8)
        let metadata = makeIncomingUploadMetadata(id: "route-resumable-conflict", fileSize: Int64(audio.count))
        let metadataBody = try encodedMetadata(metadata)
        _ = await handler.metadataUploadResponse(
            method: "POST",
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-metadata", body: metadataBody, contentType: "application/json", uploadType: "recording-metadata", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-resumable-conflict-metadata"),
            body: metadataBody
        )
        let startRequest = makeResumableStartRequest(metadata: metadata, audio: audio, chunkSize: 3)
        let startBody = try encodedResumableRequest(startRequest)
        let firstStartResponse = await handler.resumableAudioStartResponse(
            method: "POST",
            path: "/upload-recording-audio-session/start",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio-session/start", body: startBody, contentType: "application/json", uploadType: "recording-audio-session", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-resumable-conflict-start"),
            body: startBody
        )
        let firstStartJSON = try routeResponseJSON(firstStartResponse)
        let firstSessionID = try #require(firstStartJSON["sessionID"] as? String)
        let conflictingStart = ResumableAudioUploadStartRequest(
            recordingID: metadata.id,
            fileName: metadata.originalFileName,
            totalBytes: Int64(audio.count),
            totalSHA256: MacSecurityUtilities.sha256Hex(Data("xxxxxx".utf8)),
            chunkSize: 3,
            metadataHash: nil,
            uploadJobID: nil
        )
        let conflictingBody = try encodedResumableRequest(conflictingStart)
        let conflictResponse = await handler.resumableAudioStartResponse(
            method: "POST",
            path: "/upload-recording-audio-session/start",
            headers: try signedUploadHeaders(device: device, path: "/upload-recording-audio-session/start", body: conflictingBody, contentType: "application/json", uploadType: "recording-audio-session", recordingID: metadata.id, fileName: metadata.originalFileName, nonce: "nonce-route-resumable-conflict-start-2"),
            body: conflictingBody
        )

        var badChunkHeaders = try signedChunkHeaders(
            device: device,
            recordingID: "bad-signature-resumable",
            sessionID: "missing-session",
            offset: 0,
            chunk: Data("abc".utf8),
            totalSHA256: startRequest.totalSHA256,
            nonce: "nonce-route-resumable-bad-signature"
        )
        badChunkHeaders["X-Rokurics-Signature"] = "bad-signature"
        let badSignatureResponse = await handler.resumableAudioChunkResponse(
            method: "POST",
            path: "/upload-recording-audio-session/chunk",
            headers: badChunkHeaders,
            body: Data("abc".utf8)
        )
        let json = try routeResponseJSON(conflictResponse)
        let restartedSessionID = try #require(json["sessionID"] as? String)

        #expect(conflictResponse.statusCode == 200)
        #expect(json["error"] as? String == nil)
        #expect(json["disposition"] as? String == RecordingUploadDisposition.acceptedNew.rawValue)
        #expect(restartedSessionID != firstSessionID)
        #expect(String(data: conflictResponse.bodyData, encoding: .utf8)?.contains(device.sharedSecretBase64URL) == false)
        #expect(badSignatureResponse.statusCode == 400)
        #expect((try routeResponseJSON(badSignatureResponse))["error"] as? String == "signature_mismatch")
        #expect(store.loadInboxItems().count == 1)
    }

    @Test func receiveRecordMissingDeletedFieldsDefaultsToActive() throws {
        let record = RecordingReceiveRecord(
            recordingID: "legacy",
            sanitizedRecordingID: "legacy",
            receivedAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            sourceDeviceID: "device",
            sourceDeviceName: "iPhone",
            originalTitle: "旧录音",
            normalizedTitle: "旧录音",
            audioFileName: "audio.m4a",
            originalAudioFileName: "legacy.m4a",
            metadataFileName: "metadata.json",
            status: "received",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            processingStatus: "notStarted",
            suggestedCategory: nil,
            course: nil,
            category: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1),
            duration: 6,
            fileSize: 5,
            suggestedFolder: nil,
            userConfirmedFolder: nil,
            checksum: nil,
            audioRelativePath: "audio/inbox/1970-01-01/legacy/audio.m4a",
            metadataRelativePath: "audio/inbox/1970-01-01/legacy/metadata.json"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try #require(JSONSerialization.jsonObject(with: try encoder.encode(record)) as? [String: Any])
        object.removeValue(forKey: "isDeleted")
        object.removeValue(forKey: "deletedAt")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(RecordingReceiveRecord.self, from: data)

        #expect(decoded.isDeleted == false)
        #expect(decoded.deletedAt == nil)
    }

    @Test func macSoftDeleteInboxItemMarksDeletedWithoutRemovingDirectory() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let directoryURL = try await saveMacInboxRecording(id: "mac-delete-01", title: "删除", store: store)

        try store.deleteRecording(recordingID: "mac-delete-01")
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-delete-01")

        #expect(record.isDeleted)
        #expect(record.deletedAt != nil)
        #expect(FileManager.default.fileExists(atPath: directoryURL.path))
        #expect(store.loadInboxItems().isEmpty)
        #expect(store.loadTrashedInboxItems().map(\.id) == ["mac-delete-01"])
    }

    @Test func macRestoreClearsDeletedStateAndReturnsToInbox() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-restore-01", title: "恢复", store: store)

        try store.deleteRecording(recordingID: "mac-restore-01")
        try store.restoreRecording(recordingID: "mac-restore-01")
        let record = try readReceiveRecord(rootURL: rootURL, recordingID: "mac-restore-01")

        #expect(record.isDeleted == false)
        #expect(record.deletedAt == nil)
        #expect(store.loadInboxItems().map(\.id) == ["mac-restore-01"])
        #expect(store.loadTrashedInboxItems().isEmpty)
    }

    @Test func macPermanentDeleteTranscribedItemRemovesTranscriptDirectory() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        _ = try await saveMacInboxRecording(id: "mac-delete-02", title: "已转写", store: store)
        let transcriptDirectoryURL = rootURL
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent("2026-05-17", isDirectory: true)
            .appendingPathComponent("mac-delete-02", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptDirectoryURL, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: transcriptDirectoryURL.appendingPathComponent("transcript.json"))
        try Data("# transcript".utf8).write(to: transcriptDirectoryURL.appendingPathComponent("transcript.md"))
        try store.updateTranscriptionStatus(
            recordingID: "mac-delete-02",
            status: "transcribed",
            transcriptRelativePath: "transcripts/2026-05-17/mac-delete-02/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/2026-05-17/mac-delete-02/transcript.md",
            providerID: "whisper.cpp",
            modelName: "small",
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            errorMessage: nil
        )

        try store.permanentlyDeleteRecording(recordingID: "mac-delete-02")

        #expect(!FileManager.default.fileExists(atPath: transcriptDirectoryURL.path))
    }

    @Test func macPermanentDeleteRemovesRecordingDirectory() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let directoryURL = try await saveMacInboxRecording(id: "mac-permanent-01", title: "永久删除", store: store)

        try store.permanentlyDeleteRecording(recordingID: "mac-permanent-01")

        #expect(!FileManager.default.fileExists(atPath: directoryURL.path))
    }

    @Test func macDeleteRejectsIndexPathOutsideAudioInbox() throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        try FileManager.default.createDirectory(at: securityURL, withIntermediateDirectories: true)
        try Data("identity".utf8).write(to: securityURL.appendingPathComponent("identity.json"))
        let indexURL = rootURL
            .appendingPathComponent("metadata", isDirectory: true)
            .appendingPathComponent("recordings-index.json", isDirectory: false)
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"directoriesByRecordingID":{"evil-recording":"Security"}}"#.utf8).write(to: indexURL)

        do {
            try store.permanentlyDeleteRecording(recordingID: "evil-recording")
            Issue.record("Expected delete to reject an index path outside audio/inbox")
        } catch MacRecordingFileStoreError.unsafeDestination {
            #expect(FileManager.default.fileExists(atPath: securityURL.appendingPathComponent("identity.json").path))
        }
    }

    @Test func macDeleteDoesNotRemoveSecurityDirectory() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-delete-03", title: "安全目录", store: store)
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        try FileManager.default.createDirectory(at: securityURL, withIntermediateDirectories: true)
        try Data("paired".utf8).write(to: securityURL.appendingPathComponent("paired-devices.json"))

        try store.permanentlyDeleteRecording(recordingID: "mac-delete-03")

        #expect(FileManager.default.fileExists(atPath: securityURL.appendingPathComponent("paired-devices.json").path))
    }

    @Test func macDeleteWorksForFailedAndNotStartedItems() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-delete-failed", title: "失败", store: store, transcriptionStatus: "failed")
        try await saveMacInboxRecording(id: "mac-delete-not-started", title: "未转写", store: store, transcriptionStatus: "notStarted")

        try store.deleteRecording(recordingID: "mac-delete-failed")
        try store.deleteRecording(recordingID: "mac-delete-not-started")

        #expect(store.loadInboxItems().isEmpty)
        #expect(store.loadTrashedInboxItems().count == 2)
    }

    @Test func macTrashListOnlyIncludesDeletedItems() async throws {
        let (store, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-active-01", title: "未删除", store: store)
        try await saveMacInboxRecording(id: "mac-trash-01", title: "已删除", store: store)

        try store.deleteRecording(recordingID: "mac-trash-01")

        #expect(store.loadInboxItems().map(\.id) == ["mac-active-01"])
        #expect(store.loadTrashedInboxItems().map(\.id) == ["mac-trash-01"])
    }

    @Test func audioInboxStoreDeleteRefreshesCounts() async throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-count-01", title: "一", store: fileStore)
        try await saveMacInboxRecording(id: "mac-count-02", title: "二", store: fileStore, transcriptionStatus: "transcribed")
        let store = AudioInboxStore(recordingFileStore: fileStore)

        try store.deleteRecording(recordingID: "mac-count-02")

        #expect(store.pendingCount == 1)
        #expect(store.transcribedCount == 0)
        #expect(store.recordingItems.map(\.id) == ["mac-count-01"])
    }

    @Test func audioInboxStoreExposesPlayableAudioURL() async throws {
        let (fileStore, rootURL) = try makeMacStore()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        try await saveMacInboxRecording(id: "mac-play-01", title: "播放", store: fileStore)
        let store = AudioInboxStore(recordingFileStore: fileStore)

        let audioURL = try store.audioFileURL(recordingID: "mac-play-01")

        #expect(audioURL.lastPathComponent == "audio.m4a")
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(audioURL.path.hasPrefix(rootURL.path))
    }

    private func makeInboxItem(
        transcriptionStatus: String,
        transcriptionError: String?,
        hasAudio: Bool = true,
        transcriptRelativePath: String? = nil,
        transcriptMarkdownRelativePath: String? = nil,
        noteStatus: String = "notGenerated",
        noteRelativePath: String? = nil,
        noteError: String? = nil
    ) -> MacRecordingInboxItem {
        MacRecordingInboxItem(
            id: "recording-01",
            title: "录音 2026-05-16 12:46",
            receivedAt: Date(timeIntervalSince1970: 0),
            duration: 6,
            fileSize: 1024,
            sourceDeviceName: "iPhone",
            transcriptionStatus: transcriptionStatus,
            noteStatus: noteStatus,
            receiveStatus: "received",
            hasAudio: hasAudio,
            transcriptRelativePath: transcriptRelativePath,
            transcriptMarkdownRelativePath: transcriptMarkdownRelativePath,
            transcriptionError: transcriptionError,
            noteRelativePath: noteRelativePath,
            noteError: noteError
        )
    }

    private func makeNoteGenerationRequest(
        recordingID: String = "note-request-01",
        sanitizedRecordingID: String = "note-request-01",
        transcriptMarkdown: String = "测试转写正文"
    ) -> NoteGenerationRequest {
        NoteGenerationRequest(
            taskID: "task-\(recordingID)",
            recordingID: recordingID,
            sanitizedRecordingID: sanitizedRecordingID,
            title: "测试录音",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 90,
            transcriptRelativePath: "transcripts/1970-01-01/\(sanitizedRecordingID)/transcript.json",
            transcriptMarkdownRelativePath: "transcripts/1970-01-01/\(sanitizedRecordingID)/transcript.md",
            transcriptionProviderID: "whisper.cpp",
            transcriptionModelName: "small",
            transcriptResult: nil,
            transcriptMarkdown: transcriptMarkdown,
            requestedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    private func makeNoteSource(
        transcriptURL: URL?,
        transcriptMarkdownURL: URL?
    ) -> MacRecordingNoteGenerationSource {
        MacRecordingNoteGenerationSource(
            recordingID: "note-source-01",
            sanitizedRecordingID: "note-source-01",
            title: "测试录音",
            createdAt: Date(timeIntervalSince1970: 1_800),
            duration: 6,
            transcriptionStatus: "transcribed",
            transcriptRelativePath: transcriptURL?.path,
            transcriptMarkdownRelativePath: transcriptMarkdownURL?.path,
            transcriptionProviderID: "whisper.cpp",
            transcriptionModelName: "small",
            transcriptURL: transcriptURL,
            transcriptMarkdownURL: transcriptMarkdownURL
        )
    }

    private func makeTranscriptionResult(text: String) -> TranscriptionResult {
        TranscriptionResult(
            taskID: "task-transcription",
            recordingID: "recording-01",
            providerID: "whisper.cpp",
            providerName: "whisper.cpp",
            modelName: "small",
            language: "zh",
            text: text,
            segments: [],
            startedAt: Date(timeIntervalSince1970: 1_900),
            completedAt: Date(timeIntervalSince1970: 1_901),
            status: "transcribed"
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        return scratchURL
    }

    private func makeMacStore() throws -> (MacRecordingFileStore, URL) {
        let rootURL = try makeScratchDirectory()
            .appendingPathComponent("Rokurics", isDirectory: true)
        let store = MacRecordingFileStore(rootURL: rootURL)
        return (store, rootURL)
    }

    @MainActor
    private func makeRecordingUploadRouteHandler() throws -> (RecordingUploadRouteHandler, MacRecordingFileStore, URL, PairedDevice) {
        let (store, rootURL) = try makeMacStore()
        let device = PairedDevice(
            id: "route-device-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: Data("route-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
        let verifier = RequestVerifier(pairedDeviceProvider: { id in
            id == device.id ? device : nil
        })
        let handler = RecordingUploadRouteHandler(
            requestVerifier: verifier,
            recordingFileStore: store,
            onRecordingAccepted: { _, _ in }
        )
        return (handler, store, rootURL, device)
    }

    private func makeUploadDevice() -> PairedDevice {
        PairedDevice(
            id: "device-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: "secret",
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
    }

    private func makeHeartbeatDevice() -> PairedDevice {
        PairedDevice(
            id: "heartbeat-device-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: Data("heartbeat-secret".utf8).base64URLEncodedString(),
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
    }

    private func makeHeartbeatRequest(device: PairedDevice, sequenceNumber: UInt64) -> ConnectionHeartbeatRequest {
        ConnectionHeartbeatRequest(
            deviceID: device.id,
            deviceName: device.deviceName,
            platform: .iPhone,
            appInstanceID: "test-instance",
            sequenceNumber: sequenceNumber,
            sentAt: Date(timeIntervalSince1970: 2_000),
            lastKnownPeerStatusRevision: nil
        )
    }

    private func makeIncomingUploadMetadata(
        id: String,
        title: String = "课堂录音",
        fileSize: Int64 = 5
    ) -> IncomingRecordingMetadata {
        IncomingRecordingMetadata(
            id: id,
            title: title,
            originalFileName: "\(id).m4a",
            relativeAudioPath: "Recordings/\(id).m4a",
            createdAt: Date(timeIntervalSince1970: 1_800),
            endedAt: Date(timeIntervalSince1970: 1_806),
            duration: 6,
            format: "m4a",
            codec: "AAC",
            sampleRate: 16_000,
            channels: 1,
            bitrate: 64_000,
            fileSize: fileSize,
            uploadStatus: "uploaded",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            tags: [],
            sourceDeviceName: "Vita iPhone",
            sourceDeviceID: "device-01",
            uploadedAt: Date(timeIntervalSince1970: 1_807)
        )
    }

    private func encodedMetadata(_ metadata: IncomingRecordingMetadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(metadata)
    }

    private func makeResumableStartRequest(
        metadata: IncomingRecordingMetadata,
        audio: Data,
        chunkSize: Int
    ) -> ResumableAudioUploadStartRequest {
        ResumableAudioUploadStartRequest(
            recordingID: metadata.id,
            fileName: metadata.originalFileName,
            totalBytes: Int64(audio.count),
            totalSHA256: MacSecurityUtilities.sha256Hex(audio),
            chunkSize: chunkSize,
            metadataHash: nil,
            uploadJobID: metadata.id
        )
    }

    private func encodedResumableRequest<Request: Encodable>(_ request: Request) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(request)
    }

    private func encodedHeartbeatRequest(_ request: ConnectionHeartbeatRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(request)
    }

    private func encodedConnectionProbeRequest(
        sequenceNumber: UInt64,
        clientPayload: String,
        sentAt: Date = Date()
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(ConnectionProbeSmokeRequest(
            sequenceNumber: sequenceNumber,
            clientPayload: clientPayload,
            sentAt: sentAt
        ))
    }

    private func decodeResumableResponse(_ response: SecureLocalHTTPRouteResponse) throws -> ResumableAudioUploadSessionResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ResumableAudioUploadSessionResponse.self, from: response.bodyData)
    }

    private func decodeHeartbeatResponse(_ response: SecureLocalHTTPRouteResponse) throws -> ConnectionHeartbeatResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ConnectionHeartbeatResponse.self, from: response.bodyData)
    }

    private func readIncomingMetadata(at url: URL) throws -> IncomingRecordingMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IncomingRecordingMetadata.self, from: try Data(contentsOf: url))
    }

    private func signedUploadHeaders(
        device: PairedDevice,
        path: String,
        body: Data,
        contentType: String,
        uploadType: String,
        recordingID: String,
        fileName: String,
        nonce: String
    ) throws -> [String: String] {
        let bodyHash = MacSecurityUtilities.sha256Hex(body)
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let payload = ["POST", path, timestamp, nonce, bodyHash].joined(separator: "\n")
        let signature = try #require(MacSecurityUtilities.hmacSHA256Base64URL(
            message: payload,
            secretBase64URL: device.sharedSecretBase64URL
        ))

        return [
            "Content-Type": contentType,
            "X-Rokurics-Upload-Type": uploadType,
            "X-Rokurics-Device-ID": device.id,
            "X-Rokurics-Timestamp": timestamp,
            "X-Rokurics-Nonce": nonce,
            "X-Rokurics-Body-SHA256": bodyHash,
            "X-Rokurics-Signature": signature,
            "X-Rokurics-Recording-ID": recordingID,
            "X-Rokurics-Filename": fileName
        ]
    }

    private func signedJSONHeaders(
        device: PairedDevice,
        path: String,
        body: Data,
        nonce: String,
        now: Date = Date()
    ) throws -> [String: String] {
        let bodyHash = MacSecurityUtilities.sha256Hex(body)
        let timestamp = String(Int(now.timeIntervalSince1970))
        let payload = ["POST", path, timestamp, nonce, bodyHash].joined(separator: "\n")
        let signature = try #require(MacSecurityUtilities.hmacSHA256Base64URL(
            message: payload,
            secretBase64URL: device.sharedSecretBase64URL
        ))

        return [
            "Content-Type": "application/json",
            "X-Rokurics-Device-ID": device.id,
            "X-Rokurics-Timestamp": timestamp,
            "X-Rokurics-Nonce": nonce,
            "X-Rokurics-Body-SHA256": bodyHash,
            "X-Rokurics-Signature": signature
        ]
    }

    private func signedChunkHeaders(
        device: PairedDevice,
        recordingID: String,
        sessionID: String,
        offset: Int64,
        chunk: Data,
        totalSHA256: String,
        nonce: String
    ) throws -> [String: String] {
        var headers = try signedUploadHeaders(
            device: device,
            path: "/upload-recording-audio-session/chunk",
            body: chunk,
            contentType: "application/octet-stream",
            uploadType: "recording-audio-chunk",
            recordingID: recordingID,
            fileName: "audio.m4a.part",
            nonce: nonce
        )
        let chunkSHA256 = MacSecurityUtilities.sha256Hex(chunk)
        headers["X-Rokurics-Session-ID"] = sessionID
        headers["X-Rokurics-Chunk-Offset"] = String(offset)
        headers["X-Rokurics-Chunk-Length"] = String(chunk.count)
        headers["X-Rokurics-Chunk-SHA256"] = chunkSHA256
        headers["X-Rokurics-Total-SHA256"] = totalSHA256
        return headers
    }

    private func routeResponseJSON(_ response: SecureLocalHTTPRouteResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.bodyData) as? [String: Any])
    }

    @discardableResult
    private func saveMacInboxRecording(
        id: String,
        title: String,
        store: MacRecordingFileStore,
        transcriptionStatus: String = "notStarted"
    ) async throws -> URL {
        let sourceDevice = PairedDevice(
            id: "device-01",
            deviceName: "Vita iPhone",
            sharedSecretBase64URL: "secret",
            pairedAt: Date(timeIntervalSince1970: 1_000),
            lastSeenAt: nil
        )
        let metadata = IncomingRecordingMetadata(
            id: id,
            title: title,
            originalFileName: "\(id).m4a",
            relativeAudioPath: "Recordings/\(id).m4a",
            createdAt: Date(timeIntervalSince1970: 1_800),
            endedAt: Date(timeIntervalSince1970: 1_806),
            duration: 6,
            format: "m4a",
            codec: "AAC",
            sampleRate: 16_000,
            channels: 1,
            bitrate: 64_000,
            fileSize: 5,
            uploadStatus: "uploaded",
            transcriptionStatus: transcriptionStatus,
            noteStatus: "notStarted",
            tags: [],
            sourceDeviceName: "Vita iPhone",
            sourceDeviceID: "device-01",
            uploadedAt: Date(timeIntervalSince1970: 1_807)
        )

        let receiveResult = try store.saveMetadata(metadata, sourceDevice: sourceDevice)
        _ = try await store.saveAudio(body: Data("audio".utf8), recordingID: id, requestedFileName: "\(id).m4a", sourceDevice: sourceDevice)
        return receiveResult.directoryURL
    }

    private func readReceiveRecord(rootURL: URL, recordingID: String) throws -> RecordingReceiveRecord {
        let receiveURL = rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("1970-01-01", isDirectory: true)
            .appendingPathComponent(recordingID, isDirectory: true)
            .appendingPathComponent("receive.json", isDirectory: false)
        let data = try Data(contentsOf: receiveURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingReceiveRecord.self, from: data)
    }

    private func requestBodyJSON(from request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    @MainActor
    private func makeSecureReceiverServiceHarness(
        preferredHost: String = "127.0.0.1",
        port: Int = 0
    ) throws -> (
        rootURL: URL,
        service: SecureReceiverService,
        identityManager: MacIdentityManager,
        pairedDeviceStore: PairedDeviceStore,
        recordingFileStore: MacRecordingFileStore,
        statusStore: DeviceConnectionStatusStore,
        diagnosticsStore: ConnectionDiagnosticsStore
    ) {
        let rootURL = try makeScratchDirectory()
        let securityURL = rootURL.appendingPathComponent("Security", isDirectory: true)
        let libraryURL = rootURL.appendingPathComponent("Library", isDirectory: true)
        let identityManager = MacIdentityManager(
            securityDirectoryURL: securityURL,
            tlsKeyTagNamespace: "service-\(UUID().uuidString)"
        )
        identityManager.loadOrCreateIdentity()
        let pairedDeviceStore = PairedDeviceStore(rootURL: securityURL)
        let recordingFileStore = MacRecordingFileStore(rootURL: libraryURL)
        let statusStore = DeviceConnectionStatusStore(rootURL: rootURL)
        let syncStateStore = StudyLibrarySyncStateStore(rootURL: rootURL)
        let diagnosticsStore = ConnectionDiagnosticsStore(rootURL: rootURL)
        let service = SecureReceiverService(
            syncRuntimeConfiguration: StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false),
            port: port,
            identityManager: identityManager,
            pairedDeviceStore: pairedDeviceStore,
            receivedFileStore: ReceivedFileStore(),
            recordingFileStore: recordingFileStore,
            studyLibraryStore: StudyLibraryStore(
                rootURL: rootURL.appendingPathComponent("Study", isDirectory: true),
                recordingFileStore: recordingFileStore,
                listenForInboxChanges: false
            ),
            deviceConnectionStatusStore: statusStore,
            syncStateStore: syncStateStore,
            connectionDiagnosticsStore: diagnosticsStore,
            loadIdentityOnInit: false,
            receiverPortDidChange: { _ in },
            preferredIPAddressProvider: { preferredHost }
        )
        return (rootURL, service, identityManager, pairedDeviceStore, recordingFileStore, statusStore, diagnosticsStore)
    }

    @MainActor
    private func waitForPairingPayload(
        _ service: SecureReceiverService,
        timeout: TimeInterval = 5
    ) async throws -> SecureReceiverPairingPayload {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let payload = service.pairingPayload {
                return payload
            }
            if service.pairingFlowState == .failed {
                throw RealListenerSmokeTestError.servicePairingFailed(service.lastError ?? "pairing_failed")
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        throw RealListenerSmokeTestError.servicePairingTimedOut
    }

    @MainActor
    private func waitForHTTPSReady(
        _ service: SecureReceiverService,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if service.isHTTPSListenerReady, service.activeHTTPSPort != nil {
                return
            }
            if service.pairingFlowState == .failed {
                throw RealListenerSmokeTestError.servicePairingFailed(service.lastError ?? "listener_failed")
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        throw RealListenerSmokeTestError.listenerTimedOut
    }

    @MainActor
    private func assertPairingPayload(
        _ payload: SecureReceiverPairingPayload,
        matches service: SecureReceiverService,
        identityManager: MacIdentityManager
    ) throws {
        let activePort = try #require(service.activeHTTPSPort)
        #expect(payload.host == "127.0.0.1")
        #expect(payload.port == activePort)
        #expect(payload.port == service.port)
        #expect(payload.fingerprint == identityManager.status.certificateFingerprint)
        #expect(payload.fingerprint == service.fingerprint)
        #expect(payload.fingerprintType == "certificate-sha256")
        #expect(payload.pairingCode.count == 6)
        #expect(payload.pairingCode.allSatisfy { $0.isNumber })
    }

    @MainActor
    private func performRealSocketShortUploadSmoke(
        client: RealListenerPinnedHTTPSClient,
        host: String,
        port: Int,
        device: PairedDevice,
        recordingStore: MacRecordingFileStore
    ) async throws {
        let audio = Data("fake ten second m4a audio".utf8)
        let metadata = makeIncomingUploadMetadata(id: "real-service-upload-01", fileSize: Int64(audio.count))
        let metadataBody = try encodedMetadata(metadata)

        let metadataResponse = try await client.postJSON(
            host: host,
            port: port,
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(
                device: device,
                path: "/upload-recording-metadata",
                body: metadataBody,
                contentType: "application/json",
                uploadType: "recording-metadata",
                recordingID: metadata.id,
                fileName: "metadata.json",
                nonce: "real-service-upload-metadata"
            ),
            body: metadataBody
        )
        #expect(metadataResponse.statusCode == 200)
        #expect(metadataResponse.json["disposition"] as? String == "acceptedNew")

        let audioResponse = try await client.postJSON(
            host: host,
            port: port,
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(
                device: device,
                path: "/upload-recording-audio",
                body: audio,
                contentType: "audio/m4a",
                uploadType: "recording-audio",
                recordingID: metadata.id,
                fileName: metadata.originalFileName,
                nonce: "real-service-upload-audio"
            ),
            body: audio
        )
        #expect(audioResponse.statusCode == 200)
        #expect(audioResponse.json["disposition"] as? String == "acceptedNew")

        let recordingDirectory = recordingStore.libraryRootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("1970-01-01", isDirectory: true)
            .appendingPathComponent(metadata.id, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: recordingDirectory.appendingPathComponent("metadata.json").path))
        #expect(FileManager.default.fileExists(atPath: recordingDirectory.appendingPathComponent("audio.m4a").path))
        #expect(FileManager.default.fileExists(atPath: recordingDirectory.appendingPathComponent("receive.json").path))
        let receiveRecord = try readReceiveRecord(rootURL: recordingStore.libraryRootURL, recordingID: metadata.id)
        #expect(receiveRecord.status == "completed")
        #expect(receiveRecord.processingStatus == "notStarted")

        let repeatedMetadataResponse = try await client.postJSON(
            host: host,
            port: port,
            path: "/upload-recording-metadata",
            headers: try signedUploadHeaders(
                device: device,
                path: "/upload-recording-metadata",
                body: metadataBody,
                contentType: "application/json",
                uploadType: "recording-metadata",
                recordingID: metadata.id,
                fileName: "metadata.json",
                nonce: "real-service-upload-metadata-repeat"
            ),
            body: metadataBody
        )
        #expect(repeatedMetadataResponse.statusCode == 200)
        #expect(repeatedMetadataResponse.json["disposition"] as? String == "acceptedExisting")

        let repeatedAudioResponse = try await client.postJSON(
            host: host,
            port: port,
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(
                device: device,
                path: "/upload-recording-audio",
                body: audio,
                contentType: "audio/m4a",
                uploadType: "recording-audio",
                recordingID: metadata.id,
                fileName: metadata.originalFileName,
                nonce: "real-service-upload-audio-repeat"
            ),
            body: audio
        )
        #expect(repeatedAudioResponse.statusCode == 200)
        #expect(repeatedAudioResponse.json["disposition"] as? String == "acceptedExisting")

        let conflictingAudio = Data("different fake audio".utf8)
        let conflictResponse = try await client.postJSON(
            host: host,
            port: port,
            path: "/upload-recording-audio",
            headers: try signedUploadHeaders(
                device: device,
                path: "/upload-recording-audio",
                body: conflictingAudio,
                contentType: "audio/m4a",
                uploadType: "recording-audio",
                recordingID: metadata.id,
                fileName: metadata.originalFileName,
                nonce: "real-service-upload-audio-conflict"
            ),
            body: conflictingAudio
        )
        #expect(conflictResponse.statusCode == 409)
        #expect(conflictResponse.json["error"] as? String == "recording_audio_conflict")
    }

    private func waitForListenerReady(_ signal: ListenerReadySignal, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if signal.isReady {
                return
            }
            if let failureMessage = signal.failureMessage {
                throw RealListenerSmokeTestError.listenerFailed(failureMessage)
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        throw RealListenerSmokeTestError.listenerTimedOut
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRootURL.appendingPathComponent(relativePath, isDirectory: false)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static let connectionJSONDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

}

private enum RealListenerSmokeTestError: Error {
    case listenerFailed(String)
    case listenerTimedOut
    case servicePairingFailed(String)
    case servicePairingTimedOut
}

private enum RealListenerHTTPSClientError: Error {
    case fingerprintMismatch
}

private struct ConnectionProbeSmokeRequest: Encodable {
    let sequenceNumber: UInt64
    let clientPayload: String
    let sentAt: Date
}

private struct RealListenerHTTPSDataResponse {
    let statusCode: Int
    let body: Data
}

private struct RealListenerHTTPSJSONResponse {
    let statusCode: Int
    let body: Data
    let json: [String: Any]
}

private final class SecureConnectionDiagnosticRecorder: @unchecked Sendable {
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

private final class ListenerReadySignal: @unchecked Sendable {
    private enum State {
        case waiting
        case ready
        case failed(String)
    }

    private let lock = NSLock()
    private var state: State = .waiting

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .ready = state {
            return true
        }
        return false
    }

    var failureMessage: String? {
        lock.lock()
        defer { lock.unlock() }
        if case .failed(let message) = state {
            return message
        }
        return nil
    }

    func markReady() {
        lock.lock()
        state = .ready
        lock.unlock()
    }

    func markFailed(_ message: String) {
        lock.lock()
        state = .failed(message)
        lock.unlock()
    }
}

private final class RealListenerPinnedHTTPSClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let expectedFingerprint: String
    private let lock = NSLock()
    private var pinningError: RealListenerHTTPSClientError?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint
        super.init()
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    func getJSON(host: String = "127.0.0.1", port: Int, path: String) async throws -> RealListenerHTTPSJSONResponse {
        let response = try await request(method: "GET", host: host, port: port, path: path, headers: [:], body: nil)
        return try jsonResponse(from: response)
    }

    func postJSON(
        host: String = "127.0.0.1",
        port: Int,
        path: String,
        headers: [String: String],
        body: Data
    ) async throws -> RealListenerHTTPSJSONResponse {
        let response = try await postData(host: host, port: port, path: path, headers: headers, body: body)
        return try jsonResponse(from: response)
    }

    func postData(
        host: String = "127.0.0.1",
        port: Int,
        path: String,
        headers: [String: String],
        body: Data
    ) async throws -> RealListenerHTTPSDataResponse {
        try await request(method: "POST", host: host, port: port, path: path, headers: headers, body: body)
    }

    private func request(
        method: String,
        host: String,
        port: Int,
        path: String,
        headers: [String: String],
        body: Data?
    ) async throws -> RealListenerHTTPSDataResponse {
        clearPinningError()
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port
        components.path = path
        let url = try #require(components.url)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("close", forHTTPHeaderField: "Connection")
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let result: (Data, URLResponse)
            if let body {
                result = try await session.upload(for: request, from: body)
            } else {
                result = try await session.data(for: request)
            }
            let statusCode = (result.1 as? HTTPURLResponse)?.statusCode ?? -1
            return RealListenerHTTPSDataResponse(statusCode: statusCode, body: result.0)
        } catch {
            if let pinningError = currentPinningError() {
                throw pinningError
            }
            throw error
        }
    }

    private func jsonResponse(from response: RealListenerHTTPSDataResponse) throws -> RealListenerHTTPSJSONResponse {
        RealListenerHTTPSJSONResponse(
            statusCode: response.statusCode,
            body: response.body,
            json: try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        )
    }

    private func currentPinningError() -> RealListenerHTTPSClientError? {
        lock.lock()
        defer { lock.unlock() }
        return pinningError
    }

    private func clearPinningError() {
        lock.lock()
        pinningError = nil
        lock.unlock()
    }

    private func setPinningError(_ error: RealListenerHTTPSClientError) {
        lock.lock()
        pinningError = error
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let certificateChain = (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate]) ?? []
        guard let certificate = certificateChain.first else {
            setPinningError(.fingerprintMismatch)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certificateData = SecCertificateCopyData(certificate) as Data
        let calculatedFingerprint = MacSecurityUtilities.sha256Hex(certificateData)
        guard MacSecurityUtilities.constantTimeEquals(calculatedFingerprint, expectedFingerprint) else {
            setPinningError(.fingerprintMismatch)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

private final class OpenAICompatibleTransportStub: OpenAICompatibleHTTPTransport {
    let data: Data
    let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private final class AnthropicMessagesTransportStub: AnthropicMessagesHTTPTransport {
    let data: Data
    let statusCode: Int
    private(set) var lastRequest: URLRequest?

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.anthropic.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

struct CanonicalExistenceApplyBridgeTests {
    @Test func applyBridgeConsumesManifestRecordingsAndWritesMetadataOnlyPlaceholder() throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let results = harness.bridge.apply(
            recordings: [Self.manifestRecording()],
            sourceDeviceID: "iphone-01",
            syncRunID: "existence-bridge-test"
        )
        let record = try harness.port.readRecord(objectID: "recording-existence")

        #expect(results.count == 1)
        #expect(results.first?.action == .written)
        #expect(record?.objectID == "recording-existence")
        #expect(record?.audioAvailable == false)
        #expect(results.first?.diagnostics.contains { $0.kind == .canonicalRecordingExistenceMetadataOnlyWritten } == true)
        #expect(results.first?.diagnostics.contains { $0.kind == .canonicalExistenceDidNotMarkUploadCompleted } == true)
    }

    @Test func placeholderDoesNotCreateAudioFileOrMarkAudioAvailable() throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let result = harness.bridge.apply(recordings: [Self.manifestRecording()], sourceDeviceID: "iphone-01").first
        let audioInboxURL = harness.rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)

        #expect(result?.didWriteAudio == false)
        #expect(result?.didMarkAudioAvailable == false)
        #expect(FileManager.default.fileExists(atPath: audioInboxURL.path) == false)
    }

    @Test func existingSamePlaceholderNoOps() throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        _ = harness.bridge.apply(recordings: [Self.manifestRecording()], sourceDeviceID: "iphone-01")
        let second = harness.bridge.apply(recordings: [Self.manifestRecording()], sourceDeviceID: "iphone-01").first

        #expect(second?.action == .noOp)
        #expect(second?.state == .metadataOnly)
    }

    @Test func existingDifferentAudioConflicts() {
        let port = InMemoryExistencePort(existing: {
            var record = CanonicalRecordingMetadataOnlyReceiveRecord(
                objectID: "recording-existence",
                sourceDeviceID: "mac-01",
                title: "Existing",
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2),
                metadataHash: "metadata-hash"
            )
            record.audioAvailable = true
            record.audioHash = String(repeating: "b", count: 64)
            record.audioByteSize = 20
            return record
        }())
        let bridge = CanonicalRecordingManifestApplyBridge(configuration: Self.configuration(), port: port)

        let result = bridge.apply(recordings: [Self.manifestRecording(audioChecksum: String(repeating: "a", count: 64), audioSize: 10)], sourceDeviceID: "iphone-01").first

        #expect(result?.action == .conflict)
        #expect(result?.state == .audioConflict)
    }

    @Test func existingAudioWithIncompleteRemoteProofNoOpsAndPreservesAudio() throws {
        let existing = Self.existingAudioRecord()
        let port = InMemoryExistencePort(existing: existing)
        let bridge = CanonicalRecordingManifestApplyBridge(configuration: Self.configuration(), port: port)

        let result = bridge.apply(
            recordings: [Self.manifestRecording(audioChecksum: nil, audioSize: 10)],
            sourceDeviceID: "iphone-01"
        ).first
        let preserved = try port.readRecord(objectID: existing.objectID)

        #expect(result?.action == .noOp)
        #expect(result?.state == .audioAvailable)
        #expect(result?.reason == "existingAudioProofUnknownPreserved")
        #expect(preserved?.audioAvailable == true)
        #expect(preserved?.audioHash == existing.audioHash)
        #expect(preserved?.audioByteSize == existing.audioByteSize)
    }

    @Test func tombstoneWithoutMetadataHashRemovesDerivedLedgerAndRepeatedApplyNoOps() throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        _ = harness.bridge.apply(recordings: [Self.manifestRecording()], sourceDeviceID: "iphone-01")
        var tombstone = Self.manifestRecording(metadataHash: "")
        tombstone.metadataHash = nil
        tombstone.deleted = true
        tombstone.tombstone = true

        let first = harness.bridge.apply(recordings: [tombstone], sourceDeviceID: "iphone-01").first
        let second = harness.bridge.apply(recordings: [tombstone], sourceDeviceID: "iphone-01").first

        #expect(first?.action == .tombstoneApplied)
        #expect(first?.state == .tombstoned)
        #expect(second?.action == .noOp)
        #expect(second?.state == .tombstoned)
        #expect(try harness.port.readRecord(objectID: tombstone.recordingID) == nil)
    }

    @Test func rollbackRestoresPreviousAbsence() throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        let result = try #require(harness.bridge.apply(recordings: [Self.manifestRecording()], sourceDeviceID: "iphone-01").first)
        let checkpoint = try #require(result.checkpoint)
        try harness.port.rollback(checkpoint)
        let restored = try harness.port.readRecord(objectID: "recording-existence")

        #expect(restored == nil)
    }

    @Test func rollbackRestoresPreviousRecord() throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        _ = harness.bridge.apply(recordings: [Self.manifestRecording(metadataHash: "old-metadata-hash")], sourceDeviceID: "iphone-01")
        let result = try #require(harness.bridge.apply(recordings: [Self.manifestRecording(metadataHash: "new-metadata-hash")], sourceDeviceID: "iphone-01").first)
        let checkpoint = try #require(result.checkpoint)
        try harness.port.rollback(checkpoint)
        let restored = try harness.port.readRecord(objectID: "recording-existence")

        #expect(restored?.metadataHash == "old-metadata-hash")
    }

    @Test func inventoryIncludesMetadataOnlyRecordingWithoutAudioFacts() throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        _ = harness.bridge.apply(recordings: [Self.manifestRecording()], sourceDeviceID: "iphone-01")
        let records = try harness.port.loadRecords()
        let merge = MacCanonicalRecordingExistenceInventoryMerger.merge(records: records, into: [])
        let recording = merge.recordings.first

        #expect(recording?.recordingID == "recording-existence")
        #expect(recording?.audioAvailable == false)
        #expect(recording?.audioChecksum == nil)
        #expect(recording?.audioSize == nil)
        #expect(recording?.audioLogicalPathToken == nil)
    }

    @Test func inventoryMergerNeverLetsLedgerOverrideBaseTombstone() {
        let ledger = CanonicalRecordingMetadataOnlyReceiveRecord(
            objectID: "recording-existence",
            sourceDeviceID: "iphone-01",
            title: "Stale active title",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            metadataHash: "stale-ledger-hash"
        )
        var base = Self.manifestRecording(metadataHash: "current-tombstone-hash")
        base.deleted = true
        base.tombstone = true
        base.title = "Current tombstone"

        let merge = MacCanonicalRecordingExistenceInventoryMerger.merge(records: [ledger], into: [base])
        let recording = merge.recordings.first

        #expect(recording?.deleted == true)
        #expect(recording?.tombstone == true)
        #expect(recording?.title == "Current tombstone")
        #expect(recording?.metadataHash == "current-tombstone-hash")
    }

    @Test func inventoryMergerAggregatesUnknownAudioProofWithoutConflict() {
        let ledger = CanonicalRecordingMetadataOnlyReceiveRecord(
            objectID: "recording-existence",
            sourceDeviceID: "iphone-01",
            title: "Metadata",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            metadataHash: "metadata-hash",
            declaredAudioHash: nil,
            declaredAudioByteSize: 10
        )
        var base = Self.manifestRecording(audioChecksum: String(repeating: "b", count: 64), audioSize: 20)
        base.audioAvailable = true

        let merge = MacCanonicalRecordingExistenceInventoryMerger.merge(records: [ledger], into: [base])

        #expect(merge.recordings.first?.audioChecksum == String(repeating: "b", count: 64))
        #expect(merge.recordings.first?.audioSize == 20)
        #expect(!merge.diagnostics.contains { $0.kind == .canonicalExistenceAudioConflict || $0.kind == .canonicalRecordingExistenceInventoryConflict })
        #expect(merge.diagnostics.contains { $0.kind == .canonicalExistencePeerUnknownDeferred && $0.count == 1 })
    }

    @Test func receiveJSONBehaviorUsesCanonicalLedgerNotInboxReadPath() throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }

        _ = harness.bridge.apply(recordings: [Self.manifestRecording()], sourceDeviceID: "iphone-01")
        let record = try harness.port.readRecord(objectID: "recording-existence")
        let inboxReceiveURL = harness.rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("inbox", isDirectory: true)
            .appendingPathComponent("recording-existence", isDirectory: true)
            .appendingPathComponent("receive.json", isDirectory: false)

        #expect(record?.receiveStatus == "canonicalMetadataOnly")
        #expect(FileManager.default.fileExists(atPath: inboxReceiveURL.path) == false)
    }

    @Test func diagnosticsAreRedacted() throws {
        let harness = try Self.makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.rootURL) }
        let fullHash = String(repeating: "a", count: 64)

        let result = try #require(harness.bridge.apply(recordings: [Self.manifestRecording(metadataHash: fullHash)], sourceDeviceID: "iphone-01").first)
        let summary = result.diagnostics.map { $0.summary() }.joined(separator: "\n")
        let diagnosticsRedacted = result.diagnostics.allSatisfy(\.isRedacted)

        #expect(diagnosticsRedacted)
        #expect(!summary.contains(fullHash))
        #expect(!summary.contains(harness.rootURL.path))
    }

    @Test func disabledModeKeepsLegacyFallbackAndDoesNotWrite() throws {
        let rootURL = try Self.temporaryRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let port = MacCanonicalRecordingExistenceLedgerPort(rootURL: rootURL)
        let bridge = CanonicalRecordingManifestApplyBridge(configuration: .disabled, port: port)

        let result = bridge.apply(recordings: [Self.manifestRecording()], sourceDeviceID: "iphone-01").first
        let records = try port.loadRecords()

        #expect(result?.action == .blocked)
        #expect(records.isEmpty)
    }

    private struct Harness {
        let rootURL: URL
        let port: MacCanonicalRecordingExistenceLedgerPort
        let bridge: CanonicalRecordingManifestApplyBridge
    }

    private static func makeHarness() throws -> Harness {
        let rootURL = try temporaryRoot()
        let port = MacCanonicalRecordingExistenceLedgerPort(rootURL: rootURL)
        let bridge = CanonicalRecordingManifestApplyBridge(configuration: configuration(), port: port)
        return Harness(rootURL: rootURL, port: port, bridge: bridge)
    }

    private static func temporaryRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanonicalExistenceApplyBridgeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private static func configuration() -> CanonicalExistenceApplyRuntimeConfiguration {
        CanonicalExistenceApplyRuntimeConfiguration(mode: .testRootApply)
    }

    private static func existingAudioRecord() -> CanonicalRecordingMetadataOnlyReceiveRecord {
        var record = CanonicalRecordingMetadataOnlyReceiveRecord(
            objectID: "recording-existence",
            sourceDeviceID: "mac-01",
            title: "Existing",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            metadataHash: "metadata-hash"
        )
        record.audioAvailable = true
        record.audioHash = String(repeating: "b", count: 64)
        record.audioByteSize = 20
        return record
    }

    private static func manifestRecording(
        metadataHash: String = "metadata-hash",
        audioChecksum: String? = nil,
        audioSize: Int64? = 10
    ) -> LocalNetworkSyncRecordingEntry {
        LocalNetworkSyncRecordingEntry(
            recordingID: "recording-existence",
            metadataHash: metadataHash,
            audioAvailable: true,
            audioChecksum: audioChecksum,
            audioSize: audioSize,
            uploadLedgerState: nil,
            receiveStatus: nil,
            processingStatus: nil,
            updatedAt: Date(timeIntervalSince1970: 2),
            deleted: false,
            title: "Existence Test",
            createdAt: Date(timeIntervalSince1970: 1),
            tombstone: false,
            audioAvailability: .local,
            uploadStatus: nil,
            transcriptionStatus: nil,
            noteStatus: nil,
            sourceDeviceID: "iphone-01",
            artifactRefs: nil,
            audioLogicalPathToken: "recordings/existence.m4a"
        )
    }

    private final class InMemoryExistencePort: MacCanonicalRecordingExistenceApplyPort {
        let rootURL = URL(fileURLWithPath: "/tmp/canonical-existence-memory")
        private var records: [String: CanonicalRecordingMetadataOnlyReceiveRecord]

        init(existing: CanonicalRecordingMetadataOnlyReceiveRecord) {
            records = [existing.objectID: existing]
        }

        func checkpoint(for objectID: String) throws -> CanonicalRecordingExistenceRollbackCheckpoint {
            CanonicalRecordingExistenceRollbackCheckpoint(
                objectID: objectID,
                hadExistingRecord: records[objectID] != nil,
                previousRecordData: nil
            )
        }

        func readRecord(objectID: String) throws -> CanonicalRecordingMetadataOnlyReceiveRecord? {
            records[objectID]
        }

        func writeRecord(_ record: CanonicalRecordingMetadataOnlyReceiveRecord) throws {
            records[record.objectID] = record
        }

        func deleteRecord(objectID: String) throws {
            records.removeValue(forKey: objectID)
        }

        func rollback(_ checkpoint: CanonicalRecordingExistenceRollbackCheckpoint) throws {}

        func loadRecords() throws -> [CanonicalRecordingMetadataOnlyReceiveRecord] {
            Array(records.values)
        }
    }
}
