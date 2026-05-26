//
//  ConnectionSyncStateStores.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/21.
//

import Combine
import Foundation

@MainActor
final class DeviceConnectionStatusStore: ObservableObject {
    @Published private(set) var statusesByDeviceID: [String: DeviceConnectionStatus] = [:]
    @Published private(set) var lastError: String?

    private let fileManager: FileManager
    private let storeURL: URL
    private let offlineThreshold: TimeInterval
    private let staleAfter: TimeInterval
    private let disconnectedAfter: TimeInterval
    private let missedHeartbeatLimit: Int

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        offlineThreshold: TimeInterval = 12,
        staleAfter: TimeInterval = 6,
        disconnectedAfter: TimeInterval = 10,
        missedHeartbeatLimit: Int = 3
    ) {
        self.fileManager = fileManager
        self.offlineThreshold = offlineThreshold
        self.staleAfter = staleAfter
        self.disconnectedAfter = disconnectedAfter
        self.missedHeartbeatLimit = missedHeartbeatLimit
        storeURL = Self.syncDirectoryURL(fileManager: fileManager, rootURL: rootURL)
            .appendingPathComponent("device-connection-status.json", isDirectory: false)
        load()
    }

    var latestStatus: DeviceConnectionStatus? {
        statusesByDeviceID.values.sorted { left, right in
            (left.lastSeenAt ?? left.lastHeartbeatAt ?? .distantPast) > (right.lastSeenAt ?? right.lastHeartbeatAt ?? .distantPast)
        }.first
    }

    func status(for deviceID: String, now: Date = Date()) -> DeviceConnectionStatus? {
        guard var status = statusesByDeviceID[deviceID] else {
            return nil
        }

        return evaluatedStatus(status, now: now)
    }

    @discardableResult
    func markUnpaired(displayName: String = "iPhone") -> DeviceConnectionStatus {
        let status = DeviceConnectionStatus.unpaired(displayName: displayName)
        statusesByDeviceID = [:]
        save()
        return status
    }

    @discardableResult
    func markConnecting(deviceID: String, displayName: String, now: Date = Date()) -> DeviceConnectionStatus {
        var status = statusesByDeviceID[deviceID] ?? DeviceConnectionStatus(
            deviceID: deviceID,
            displayName: displayName,
            state: .connecting,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
        )
        status.displayName = displayName
        status.state = .connecting
        status.presenceState = .connecting
        status.monitoringMode = .foregroundActive
        status.lastError = nil
        status.lastErrorCode = nil
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return status
    }

    @discardableResult
    func markConnected(
        deviceID: String,
        displayName: String,
        now: Date = Date(),
        lastSyncAt: Date? = nil,
        lastSyncStatus: String? = nil
    ) -> DeviceConnectionStatus {
        var status = statusesByDeviceID[deviceID] ?? DeviceConnectionStatus(
            deviceID: deviceID,
            displayName: displayName,
            state: .connected,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
        )
        status.displayName = displayName
        status.state = .connected
        status.lastSeenAt = now
        status.lastHeartbeatAt = now
        status.presenceState = .online
        status.monitoringMode = status.monitoringMode ?? .foregroundActive
        status.lastSignedRequestSucceededAt = now
        status.missedHeartbeatCount = 0
        status.consecutiveFailureCount = 0
        status.lastSyncAt = lastSyncAt ?? status.lastSyncAt
        status.lastSyncStatus = lastSyncStatus ?? status.lastSyncStatus
        status.lastError = nil
        status.lastErrorCode = nil
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return status
    }

    @discardableResult
    func markOffline(deviceID: String, displayName: String, error: String?, now: Date = Date()) -> DeviceConnectionStatus {
        var status = statusesByDeviceID[deviceID] ?? DeviceConnectionStatus(
            deviceID: deviceID,
            displayName: displayName,
            state: .offline,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
        )
        status.displayName = displayName
        status.state = .offline
        status.presenceState = .disconnected
        status.lastError = error
        status.lastErrorCode = error
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return status
    }

    @discardableResult
    func recordSyncResult(
        deviceID: String,
        displayName: String,
        statusText: String,
        at date: Date = Date(),
        error: String? = nil
    ) -> DeviceConnectionStatus {
        var status = statusesByDeviceID[deviceID] ?? DeviceConnectionStatus(
            deviceID: deviceID,
            displayName: displayName,
            state: error == nil ? .connected : .offline,
            lastSeenAt: error == nil ? date : nil,
            lastHeartbeatAt: error == nil ? date : nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
        )
        status.displayName = displayName
        status.lastSyncAt = date
        status.lastSyncStatus = statusText
        status.lastError = error
        if error == nil {
            status.state = .connected
            status.lastSeenAt = date
            status.lastHeartbeatAt = date
            status.lastSignedRequestSucceededAt = date
            status.presenceState = .online
            status.missedHeartbeatCount = 0
            status.consecutiveFailureCount = 0
            status.lastErrorCode = nil
        } else {
            status.presenceState = .disconnected
            status.lastErrorCode = error
        }
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return status
    }

    @discardableResult
    func markHeartbeatSent(
        deviceID: String,
        displayName: String,
        now: Date = Date()
    ) -> DeviceConnectionStatus {
        var status = statusesByDeviceID[deviceID] ?? DeviceConnectionStatus(
            deviceID: deviceID,
            displayName: displayName,
            state: .connecting,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
        )
        status.displayName = displayName
        status.state = status.presenceState == .online ? .connected : .connecting
        status.presenceState = status.presenceState == .online ? .online : .connecting
        status.monitoringMode = .foregroundActive
        status.lastHeartbeatSentAt = now
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return status
    }

    @discardableResult
    func recordHeartbeatSuccess(
        deviceID: String,
        displayName: String,
        sentAt: Date?,
        receivedAt: Date = Date(),
        latencyMilliseconds: Double? = nil
    ) -> DeviceConnectionStatus {
        var status = statusesByDeviceID[deviceID] ?? DeviceConnectionStatus(
            deviceID: deviceID,
            displayName: displayName,
            state: .connected,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
        )
        status.displayName = displayName
        status.state = .connected
        status.presenceState = .online
        status.monitoringMode = .foregroundActive
        status.lastSeenAt = receivedAt
        status.lastHeartbeatAt = receivedAt
        status.lastHeartbeatSentAt = sentAt ?? status.lastHeartbeatSentAt
        status.lastHeartbeatReceivedAt = receivedAt
        status.lastSuccessfulHeartbeatAt = receivedAt
        status.missedHeartbeatCount = 0
        status.consecutiveFailureCount = 0
        status.latencyMilliseconds = latencyMilliseconds
        status.lastError = nil
        status.lastErrorCode = nil
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return status
    }

    @discardableResult
    func recordHeartbeatFailure(
        deviceID: String,
        displayName: String,
        errorCode: String,
        errorMessage: String,
        isSecurityFailure: Bool = false,
        now: Date = Date()
    ) -> DeviceConnectionStatus {
        var status = statusesByDeviceID[deviceID] ?? DeviceConnectionStatus(
            deviceID: deviceID,
            displayName: displayName,
            state: .offline,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
        )
        let missedCount = (status.missedHeartbeatCount ?? 0) + 1
        let failureCount = (status.consecutiveFailureCount ?? 0) + 1
        status.displayName = displayName
        status.state = .offline
        status.presenceState = isSecurityFailure
            ? .securityError
            : (missedCount >= missedHeartbeatLimit ? .disconnected : .stale)
        status.monitoringMode = .foregroundActive
        status.missedHeartbeatCount = missedCount
        status.consecutiveFailureCount = failureCount
        status.lastError = errorMessage
        status.lastErrorCode = errorCode
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return evaluatedStatus(status, now: now)
    }

    @discardableResult
    func markMonitoringSuspended(
        deviceID: String,
        displayName: String,
        now: Date = Date()
    ) -> DeviceConnectionStatus {
        var status = statusesByDeviceID[deviceID] ?? DeviceConnectionStatus(
            deviceID: deviceID,
            displayName: displayName,
            state: .offline,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
        )
        status.displayName = displayName
        status.state = .offline
        status.presenceState = .stale
        status.monitoringMode = .suspended
        status.lastErrorCode = "not_actively_monitoring"
        status.lastError = "Heartbeat monitoring is suspended."
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return evaluatedStatus(status, now: now)
    }

    @discardableResult
    func recordSignedRequestSucceeded(
        deviceID: String,
        displayName: String,
        now: Date = Date()
    ) -> DeviceConnectionStatus {
        var status = statusesByDeviceID[deviceID] ?? DeviceConnectionStatus(
            deviceID: deviceID,
            displayName: displayName,
            state: .connected,
            lastSeenAt: nil,
            lastHeartbeatAt: nil,
            lastSyncAt: nil,
            lastSyncStatus: nil,
            lastError: nil
        )
        status.displayName = displayName
        status.state = .connected
        status.presenceState = .online
        status.lastSeenAt = now
        status.lastSignedRequestSucceededAt = now
        status.missedHeartbeatCount = 0
        status.consecutiveFailureCount = 0
        status.lastError = nil
        status.lastErrorCode = nil
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return status
    }

    private func load() {
        do {
            guard fileManager.fileExists(atPath: storeURL.path) else {
                statusesByDeviceID = [:]
                return
            }
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            statusesByDeviceID = try decoder.decode([String: DeviceConnectionStatus].self, from: data)
        } catch {
            statusesByDeviceID = [:]
            lastError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(statusesByDeviceID).write(to: storeURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func evaluatedStatus(_ status: DeviceConnectionStatus, now: Date) -> DeviceConnectionStatus {
        guard status.state != .unpaired else {
            return status
        }

        var evaluated = status
        guard let lastEvidenceAt = latestOnlineEvidenceDate(for: status) else {
            if evaluated.presenceState == nil {
                evaluated.presenceState = .unknown
            }
            return evaluated
        }

        let age = now.timeIntervalSince(lastEvidenceAt)
        if age > disconnectedAfter {
            evaluated.state = .offline
            evaluated.presenceState = .disconnected
            evaluated.lastErrorCode = evaluated.lastErrorCode ?? "heartbeat_disconnected"
            evaluated.lastError = evaluated.lastError ?? "Heartbeat timed out."
        } else if age > staleAfter || age > offlineThreshold {
            evaluated.state = .offline
            evaluated.presenceState = .stale
            evaluated.lastErrorCode = evaluated.lastErrorCode ?? "heartbeat_stale"
            evaluated.lastError = evaluated.lastError ?? "Heartbeat is stale."
        }
        return evaluated
    }

    private func latestOnlineEvidenceDate(for status: DeviceConnectionStatus) -> Date? {
        [
            status.lastSuccessfulHeartbeatAt,
            status.lastSignedRequestSucceededAt,
            status.lastSeenAt,
            status.lastHeartbeatAt
        ]
        .compactMap { $0 }
        .max()
    }

    private func nextRevision(after status: DeviceConnectionStatus) -> Int {
        (status.connectionStatusRevision ?? 0) + 1
    }

    private static func syncDirectoryURL(fileManager: FileManager, rootURL: URL?) -> URL {
        if let rootURL {
            return rootURL.appendingPathComponent("Sync", isDirectory: true)
        }
        return MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
            .appendingPathComponent("Sync", isDirectory: true)
    }
}

@MainActor
final class StudyLibrarySyncStateStore: ObservableObject {
    @Published private(set) var state: StudyLibrarySyncState = StudyLibrarySyncState()
    @Published private(set) var lastError: String?

    private let fileManager: FileManager
    private let storeURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        storeURL = Self.syncDirectoryURL(fileManager: fileManager, rootURL: rootURL)
            .appendingPathComponent("study-library-sync-state.json", isDirectory: false)
        load()
    }

    func recordPull(deviceID: String, remoteManifestHash: String?, remoteCommitID: String? = nil, at date: Date = Date()) {
        state.deviceID = deviceID
        state.lastPulledAt = date
        state.lastRemoteManifestHash = remoteManifestHash
        state.lastKnownRemoteCommitID = remoteCommitID ?? state.lastKnownRemoteCommitID
        state.lastError = nil
        save()
    }

    func recordPush(deviceID: String, remoteManifestHash: String?, remoteCommitID: String? = nil, pendingUploads: Int = 0, at date: Date = Date()) {
        state.deviceID = deviceID
        state.lastPushedAt = date
        state.lastRemoteManifestHash = remoteManifestHash ?? state.lastRemoteManifestHash
        state.lastKnownRemoteCommitID = remoteCommitID ?? state.lastKnownRemoteCommitID
        state.lastSuccessfulSyncAt = date
        state.pendingLocalChanges = 0
        state.pendingUploads = pendingUploads
        state.failedChanges = 0
        state.lastError = nil
        save()
    }

    func recordPendingUploads(deviceID: String, pendingUploads: Int, failedChanges: Int = 0, error: String? = nil) {
        state.deviceID = deviceID
        state.pendingUploads = pendingUploads
        state.failedChanges = max(state.failedChanges, failedChanges)
        state.lastError = error ?? state.lastError
        save()
    }

    func recordFailure(deviceID: String, error: String, failedChanges: Int = 1, pendingUploads: Int? = nil) {
        state.deviceID = deviceID
        state.pendingLocalChanges = max(state.pendingLocalChanges, failedChanges)
        if let pendingUploads {
            state.pendingUploads = pendingUploads
        }
        state.failedChanges = max(state.failedChanges, failedChanges)
        state.lastError = error
        save()
    }

    func replace(_ nextState: StudyLibrarySyncState) {
        state = nextState
        save()
    }

    private func load() {
        do {
            guard fileManager.fileExists(atPath: storeURL.path) else {
                state = StudyLibrarySyncState()
                return
            }
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try decoder.decode(StudyLibrarySyncState.self, from: data)
        } catch {
            state = StudyLibrarySyncState(lastError: error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: storeURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func syncDirectoryURL(fileManager: FileManager, rootURL: URL?) -> URL {
        if let rootURL {
            return rootURL.appendingPathComponent("Sync", isDirectory: true)
        }
        return MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
            .appendingPathComponent("Sync", isDirectory: true)
    }
}

@MainActor
final class LocalNetworkSyncStateStore: ObservableObject {
    @Published private(set) var state: LocalNetworkSyncState = .empty
    @Published private(set) var lastError: String?

    private let fileManager: FileManager
    private let storeURL: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        storeURL = Self.syncDirectoryURL(fileManager: fileManager, rootURL: rootURL)
            .appendingPathComponent("local-network-sync-state.json", isDirectory: false)
            .standardizedFileURL
        load()
    }

    func recordAttempt(
        peerDeviceID: String?,
        localInventoryHash: String?,
        peerInventoryHash: String?,
        pendingUploadCount: Int,
        pendingDownloadCount: Int,
        at date: Date = Date()
    ) {
        state.lastSyncAt = date
        state.lastPeerDeviceID = peerDeviceID ?? state.lastPeerDeviceID
        state.lastLocalInventoryHash = localInventoryHash ?? state.lastLocalInventoryHash
        state.lastPeerInventoryHash = peerInventoryHash ?? state.lastPeerInventoryHash
        state.pendingUploadCount = pendingUploadCount
        state.pendingDownloadCount = pendingDownloadCount
        save()
    }

    func recordSuccess(
        peerDeviceID: String,
        localInventoryHash: String,
        peerInventoryHash: String,
        appliedPeerRevision: String?,
        pendingUploadCount: Int,
        pendingDownloadCount: Int,
        at date: Date = Date()
    ) {
        state.version = LocalNetworkSyncState.currentVersion
        state.lastSyncAt = date
        state.lastSuccessfulSyncAt = date
        state.lastPeerDeviceID = peerDeviceID
        state.lastLocalInventoryHash = localInventoryHash
        state.lastPeerInventoryHash = peerInventoryHash
        state.lastAppliedPeerRevision = appliedPeerRevision ?? state.lastAppliedPeerRevision
        state.consecutiveFailureCount = 0
        state.nextAllowedSyncAt = nil
        state.lastErrorCode = nil
        state.lastErrorMessage = nil
        state.pendingUploadCount = pendingUploadCount
        state.pendingDownloadCount = pendingDownloadCount
        save()
    }

    func recordFailure(
        code: String,
        message: String,
        at date: Date = Date(),
        minimumBackoff: TimeInterval = 30,
        maximumBackoff: TimeInterval = 600
    ) {
        state.version = LocalNetworkSyncState.currentVersion
        state.lastSyncAt = date
        state.consecutiveFailureCount += 1
        let exponent = max(0, state.consecutiveFailureCount - 1)
        let delay = min(minimumBackoff * pow(2.0, Double(exponent)), maximumBackoff)
        state.nextAllowedSyncAt = date.addingTimeInterval(delay)
        state.lastErrorCode = code
        state.lastErrorMessage = message
        save()
    }

    func replace(_ nextState: LocalNetworkSyncState) {
        state = nextState
        save()
    }

    private func load() {
        do {
            guard fileManager.fileExists(atPath: storeURL.path) else {
                state = .empty
                lastError = nil
                return
            }

            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try decoder.decode(LocalNetworkSyncState.self, from: data)
            lastError = nil
        } catch {
            state = .empty
            lastError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            let temporaryURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent(".local-network-sync-state-\(UUID().uuidString)")
                .appendingPathExtension("tmp")
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: storeURL.path) {
                _ = try fileManager.replaceItemAt(storeURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: storeURL)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func syncDirectoryURL(fileManager: FileManager, rootURL: URL?) -> URL {
        if let rootURL {
            return rootURL.appendingPathComponent("Sync", isDirectory: true)
        }
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupportURL
            .appendingPathComponent("Rokurics", isDirectory: true)
            .appendingPathComponent("Sync", isDirectory: true)
    }
}
