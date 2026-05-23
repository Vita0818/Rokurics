//
//  ConnectionSyncStateStores.swift
//  Rokurics
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

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        offlineThreshold: TimeInterval = 12
    ) {
        self.fileManager = fileManager
        self.offlineThreshold = offlineThreshold
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

        if status.state == .connected,
           let lastHeartbeatAt = status.lastHeartbeatAt,
           now.timeIntervalSince(lastHeartbeatAt) > offlineThreshold {
            status.state = .offline
            status.lastError = status.lastError ?? "heartbeat_timeout"
        }

        return status
    }

    @discardableResult
    func markUnpaired(displayName: String = "Mac") -> DeviceConnectionStatus {
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
        status.lastError = nil
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
        status.lastSyncAt = lastSyncAt ?? status.lastSyncAt
        status.lastSyncStatus = lastSyncStatus ?? status.lastSyncStatus
        status.lastError = nil
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
        status.lastError = error
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
        }
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
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupportURL
            .appendingPathComponent("Rokurics", isDirectory: true)
            .appendingPathComponent("Sync", isDirectory: true)
    }
}
