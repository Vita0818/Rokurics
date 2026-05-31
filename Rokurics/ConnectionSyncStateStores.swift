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
    static let shared = DeviceConnectionStatusStore()

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
        staleAfter: TimeInterval = 5,
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
        guard let status = statusesByDeviceID[deviceID] else {
            return nil
        }

        return evaluatedStatus(status, now: now)
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
        guard error == nil else {
            return recordSyncStatus(
                deviceID: deviceID,
                displayName: displayName,
                statusText: statusText,
                at: date
            )
        }

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
        status.state = .connected
        status.lastSeenAt = date
        status.lastHeartbeatAt = date
        status.lastSignedRequestSucceededAt = date
        status.presenceState = .online
        status.missedHeartbeatCount = 0
        status.consecutiveFailureCount = 0
        status.lastErrorCode = nil
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return status
    }

    @discardableResult
    func recordSyncStatus(
        deviceID: String,
        displayName: String,
        statusText: String,
        at date: Date = Date()
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
        status.lastSyncAt = date
        status.lastSyncStatus = statusText
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return evaluatedStatus(status, now: date)
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
        if isSecurityFailure {
            status.state = .offline
            status.presenceState = .securityError
        } else if missedCount >= missedHeartbeatLimit
                    || latestOnlineEvidenceDate(for: status).map({ now.timeIntervalSince($0) > disconnectedAfter }) == true {
            status.state = .offline
            status.presenceState = .disconnected
        } else if latestOnlineEvidenceDate(for: status).map({ now.timeIntervalSince($0) > staleAfter }) ?? true {
            status.state = .offline
            status.presenceState = .interrupted
        } else {
            status.state = .connected
            status.presenceState = .online
        }
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
    func markUserDisconnected(
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
        status.presenceState = .disconnected
        status.monitoringMode = .disabled
        status.lastErrorCode = "user_disconnected"
        status.lastError = "User disconnected."
        status.connectionStatusRevision = nextRevision(after: status)
        statusesByDeviceID[deviceID] = status
        save()
        return status
    }

    @discardableResult
    func markMonitoringResumed(
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
        status.monitoringMode = .foregroundActive
        if status.presenceState == .stale || status.presenceState == .unknown || status.presenceState == nil {
            status.presenceState = .connecting
            status.state = .connecting
        }
        if status.lastErrorCode == "not_actively_monitoring" {
            status.lastErrorCode = nil
            status.lastError = nil
        }
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
        if evaluated.presenceState == .securityError {
            evaluated.state = .offline
            return evaluated
        }
        if evaluated.monitoringMode == .suspended {
            evaluated.state = .offline
            evaluated.presenceState = .stale
            return evaluated
        }
        guard let lastEvidenceAt = latestOnlineEvidenceDate(for: status) else {
            if evaluated.presenceState == nil {
                evaluated.presenceState = .unknown
            }
            return evaluated
        }

        let age = now.timeIntervalSince(lastEvidenceAt)
        if (evaluated.missedHeartbeatCount ?? 0) >= missedHeartbeatLimit || age > disconnectedAfter {
            evaluated.state = .offline
            evaluated.presenceState = .disconnected
            evaluated.lastErrorCode = evaluated.lastErrorCode ?? "heartbeat_disconnected"
            evaluated.lastError = evaluated.lastError ?? "Heartbeat timed out."
        } else if age > staleAfter || age > offlineThreshold {
            evaluated.state = .offline
            evaluated.presenceState = .interrupted
            evaluated.lastErrorCode = evaluated.lastErrorCode ?? "heartbeat_interrupted"
            evaluated.lastError = evaluated.lastError ?? "Heartbeat is stale."
        } else {
            evaluated.state = .connected
            evaluated.presenceState = .online
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
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupportURL
            .appendingPathComponent("Rokurics", isDirectory: true)
            .appendingPathComponent("Sync", isDirectory: true)
    }
}

struct ConnectionDiagnosticEntry: Codable, Equatable {
    var timestamp: Date
    var phase: String
    var deviceIDPrefix: String?
    var heartbeatSequence: UInt64?
    var requestStartedAt: Date?
    var requestPath: String?
    var responseReceivedAt: Date?
    var responseSequence: UInt64?
    var result: String?
    var latencyMs: Double?
    var heartbeatMissCount: Int?
    var syncRunID: String?
    var uploadTestBlockedReason: String?
    var pendingUploadCount: Int?
    var pendingDownloadCount: Int?
    var errorCode: String?
    var errorMessage: String?
}

@MainActor
final class ConnectionDiagnosticsStore {
    static let shared = ConnectionDiagnosticsStore()

    private let fileManager: FileManager
    let logURL: URL
    private let maxEntries: Int

    init(fileManager: FileManager = .default, rootURL: URL? = nil, maxEntries: Int = 200) {
        self.fileManager = fileManager
        self.maxEntries = maxEntries
        let root = rootURL ?? Self.applicationSupportRootURL(fileManager: fileManager)
        logURL = root
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("connection-diagnostics.jsonl", isDirectory: false)
    }

    func record(
        phase: String,
        deviceID: String? = nil,
        heartbeatSequence: UInt64? = nil,
        requestStartedAt: Date? = nil,
        requestPath: String? = nil,
        responseReceivedAt: Date? = nil,
        responseSequence: UInt64? = nil,
        syncRunID: String? = nil,
        result: String? = nil,
        latencyMs: Double? = nil,
        heartbeatMissCount: Int? = nil,
        uploadTestBlockedReason: String? = nil,
        pendingUploadCount: Int? = nil,
        pendingDownloadCount: Int? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        timestamp: Date = Date()
    ) {
        let entry = ConnectionDiagnosticEntry(
            timestamp: timestamp,
            phase: phase,
            deviceIDPrefix: deviceID.map { String($0.prefix(12)) },
            heartbeatSequence: heartbeatSequence,
            requestStartedAt: requestStartedAt,
            requestPath: sanitized(requestPath),
            responseReceivedAt: responseReceivedAt,
            responseSequence: responseSequence,
            result: sanitized(result),
            latencyMs: latencyMs,
            heartbeatMissCount: heartbeatMissCount,
            syncRunID: sanitized(syncRunID),
            uploadTestBlockedReason: sanitized(uploadTestBlockedReason),
            pendingUploadCount: pendingUploadCount,
            pendingDownloadCount: pendingDownloadCount,
            errorCode: sanitized(errorCode),
            errorMessage: sanitized(errorMessage)
        )

        do {
            try fileManager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let nextEntries = Array((loadEntries() + [entry]).suffix(maxEntries))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let lines = try nextEntries
                .map { try String(data: encoder.encode($0), encoding: .utf8) ?? "{}" }
                .joined(separator: "\n")
            try Data((lines + "\n").utf8).write(to: logURL, options: .atomic)
        } catch {
            print("[RokuricsConnectionDiagnostics] write failed: \(error.localizedDescription)")
        }
    }

    func loadEntries() -> [ConnectionDiagnosticEntry] {
        guard fileManager.fileExists(atPath: logURL.path),
              let rawText = try? String(contentsOf: logURL, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return rawText
            .split(separator: "\n")
            .compactMap { try? decoder.decode(ConnectionDiagnosticEntry.self, from: Data($0.utf8)) }
    }

    private func sanitized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func applicationSupportRootURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return applicationSupportURL.appendingPathComponent("Rokurics", isDirectory: true)
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

    func recordControlPlane(
        deviceID: String,
        syncRunID: String,
        state controlPlaneState: LocalNetworkSyncControlPlaneState,
        at date: Date = Date()
    ) {
        state.deviceID = deviceID
        state.activeSyncRunID = syncRunID
        state.syncControlPlaneState = controlPlaneState
        state.syncControlPlaneUpdatedAt = date
        if controlPlaneState == .completed {
            state.lastSuccessfulSyncAt = date
        }
        if controlPlaneState != .failed {
            state.lastError = nil
        }
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
        localDeviceID: String? = nil,
        peerDeviceID: String?,
        localInventoryHash: String?,
        peerInventoryHash: String?,
        pendingUploadCount: Int,
        pendingDownloadCount: Int,
        planSummary: String? = nil,
        conflictCount: Int? = nil,
        at date: Date = Date()
    ) {
        state.localDeviceID = localDeviceID ?? state.localDeviceID
        state.peerDeviceID = peerDeviceID ?? state.peerDeviceID
        state.lastSyncStartedAt = date
        state.lastSyncAt = date
        state.lastPeerDeviceID = peerDeviceID ?? state.lastPeerDeviceID
        state.lastLocalInventoryHash = localInventoryHash ?? state.lastLocalInventoryHash
        state.lastPeerInventoryHash = peerInventoryHash ?? state.lastPeerInventoryHash
        state.pendingUploadCount = pendingUploadCount
        state.pendingDownloadCount = pendingDownloadCount
        state.lastPlanSummary = planSummary
        state.lastConflictCount = conflictCount
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
        state.peerDeviceID = peerDeviceID
        state.lastSyncCompletedAt = date
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
        if pendingUploadCount == 0, pendingDownloadCount == 0 {
            state.activeTransfers = []
        }
        save()
    }

    func recordActiveTransfers(_ transfers: [LocalNetworkTransferProgress]) {
        state.activeTransfers = transfers
        save()
    }

    func recordControlPlane(
        syncRunID: String,
        state controlPlaneState: LocalNetworkSyncControlPlaneState,
        at date: Date = Date()
    ) {
        state.activeSyncRunID = syncRunID
        state.controlPlaneState = controlPlaneState
        state.lastControlPlaneUpdatedAt = date
        if controlPlaneState == .completed {
            state.lastSyncCompletedAt = date
            state.lastSuccessfulSyncAt = date
        } else if controlPlaneState == .failed {
            state.lastSyncCompletedAt = date
        } else if controlPlaneState == .syncStartAcked || controlPlaneState == .inventoryExchanging {
            state.lastSyncStartedAt = state.lastSyncStartedAt ?? date
            state.lastSyncAt = date
        }
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
        state.lastSyncCompletedAt = date
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

enum LocalNetworkSyncTransferDirection: String, Codable, Equatable {
    case upload
    case download
}

struct LocalNetworkSyncTransferJob: Codable, Equatable, Identifiable {
    var id: String { transferID }

    var transferID: String
    var direction: LocalNetworkSyncTransferDirection
    var ownerID: String
    var artifactID: String
    var objectKind: String
    var fileName: String?
    var logicalName: String?
    var totalBytes: Int64?
    var transferredBytes: Int64
    var sha256: String?
    var chunkSize: Int?
    var nextOffset: Int64
    var state: LocalNetworkTransferState
    var createdAt: Date
    var updatedAt: Date
    var lastAttemptAt: Date?
    var nextRetryAfter: Date?
    var errorCode: String?
    var errorMessage: String?
    var peerDeviceID: String?
    var localTempPath: String?
    var syncRunID: String? = nil
    var objectID: String? = nil
    var logicalPathToken: String? = nil
    var relativePathToken: String? = nil
    var senderDeviceID: String? = nil
    var receiverDeviceID: String? = nil
    var confirmedBytes: Int64? = nil
    var retryCount: Int? = nil
    var sessionID: String? = nil
}

struct LocalNetworkSyncTransferLedger: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var jobs: [LocalNetworkSyncTransferJob]

    static var empty: LocalNetworkSyncTransferLedger {
        LocalNetworkSyncTransferLedger(version: currentVersion, jobs: [])
    }
}

final class LocalNetworkSyncTransferJobStore {
    private let fileManager: FileManager
    private let storeURL: URL
    private(set) var lastError: String?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        storeURL = Self.syncDirectoryURL(fileManager: fileManager, rootURL: rootURL)
            .appendingPathComponent("local-network-transfer-ledger.json", isDirectory: false)
            .standardizedFileURL
    }

    func loadJobs() throws -> [LocalNetworkSyncTransferJob] {
        try loadLedger().jobs
    }

    @discardableResult
    func upsert(_ job: LocalNetworkSyncTransferJob) throws -> LocalNetworkSyncTransferJob {
        var ledger = try loadLedger()
        ledger.jobs.removeAll { $0.transferID == job.transferID }
        ledger.jobs.append(job)
        ledger.jobs.sort { $0.updatedAt > $1.updatedAt }
        try saveLedger(ledger)
        return job
    }

    @discardableResult
    func update(
        transferID: String,
        now: Date = Date(),
        _ update: (inout LocalNetworkSyncTransferJob) -> Void
    ) throws -> LocalNetworkSyncTransferJob {
        var ledger = try loadLedger()
        guard let index = ledger.jobs.firstIndex(where: { $0.transferID == transferID }) else {
            throw StudyLibraryStoreError.writeFailed("sync_transfer_job_missing")
        }
        update(&ledger.jobs[index])
        ledger.jobs[index].updatedAt = now
        let job = ledger.jobs[index]
        try saveLedger(ledger)
        return job
    }

    @discardableResult
    func markComplete(transferID: String, now: Date = Date()) throws -> LocalNetworkSyncTransferJob {
        try update(transferID: transferID, now: now) { job in
            job.state = .complete
            job.transferredBytes = job.totalBytes ?? job.transferredBytes
            job.nextOffset = job.totalBytes ?? job.nextOffset
            job.confirmedBytes = job.totalBytes ?? job.confirmedBytes ?? job.transferredBytes
            job.nextRetryAfter = nil
            job.errorCode = nil
            job.errorMessage = nil
        }
    }

    private func loadLedger() throws -> LocalNetworkSyncTransferLedger {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            lastError = nil
            return .empty
        }

        do {
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let ledger = try decoder.decode(LocalNetworkSyncTransferLedger.self, from: data)
            lastError = nil
            return LocalNetworkSyncTransferLedger(
                version: LocalNetworkSyncTransferLedger.currentVersion,
                jobs: deduplicated(ledger.jobs)
            )
        } catch {
            lastError = error.localizedDescription
            return .empty
        }
    }

    private func saveLedger(_ ledger: LocalNetworkSyncTransferLedger) throws {
        try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let normalized = LocalNetworkSyncTransferLedger(
            version: LocalNetworkSyncTransferLedger.currentVersion,
            jobs: deduplicated(ledger.jobs)
        )
        let data = try encoder.encode(normalized)
        let temporaryURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent(".local-network-transfer-ledger-\(UUID().uuidString)")
            .appendingPathExtension("tmp")
        do {
            try data.write(to: temporaryURL, options: .atomic)
            if fileManager.fileExists(atPath: storeURL.path) {
                _ = try fileManager.replaceItemAt(storeURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: storeURL)
            }
            lastError = nil
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            lastError = error.localizedDescription
            throw error
        }
    }

    private func deduplicated(_ jobs: [LocalNetworkSyncTransferJob]) -> [LocalNetworkSyncTransferJob] {
        var latestByID: [String: LocalNetworkSyncTransferJob] = [:]
        for job in jobs {
            if latestByID[job.transferID].map({ job.updatedAt >= $0.updatedAt }) ?? true {
                latestByID[job.transferID] = job
            }
        }
        return latestByID.values.sorted { $0.updatedAt > $1.updatedAt }
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
