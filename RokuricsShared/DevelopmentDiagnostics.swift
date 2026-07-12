//
//  DevelopmentDiagnostics.swift
//  RokuricsShared
//
//  Development-only, redacted, session-scoped diagnostics.
//

import Foundation
import OSLog

nonisolated enum DevelopmentDiagnosticsNode: String, Codable, Sendable {
    case iPhone
    case Mac
}

nonisolated enum DevelopmentDiagnosticsSeverity: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error
    case critical
}

nonisolated struct DevelopmentDiagnosticEvent: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var timestamp: Date
    var sessionID: String
    var node: DevelopmentDiagnosticsNode
    var subsystem: String
    var event: String
    var severity: DevelopmentDiagnosticsSeverity
    var syncRunID: String?
    var traceID: String?
    var details: [String: String]
}

nonisolated struct DevelopmentDiagnosticsWriterHealth: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var sessionID: String
    var node: DevelopmentDiagnosticsNode
    var queuedCount: Int
    var writtenCount: Int
    var droppedCount: Int
    var redactionRejectedCount: Int
    var writeFailureCount: Int
    var pendingCount: Int
    var lastWriteAt: Date?
    var lastFailureCategory: String?
}

nonisolated struct DevelopmentDiagnosticsSessionManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    var sessionID: String
    var node: DevelopmentDiagnosticsNode
    var processStartedAt: Date
    var bundleIdentifier: String
    var appVersion: String
    var appBuild: String
    var operatingSystemVersion: String
}

nonisolated final class DevelopmentDiagnosticsFileStore: @unchecked Sendable {
    struct Configuration: Sendable {
        var maxQueuedEvents: Int = 8_192
        var maxLogFileBytes: UInt64 = 10 * 1_024 * 1_024
        var rotatedFileCount: Int = 4
        var maxRetainedSessions: Int = 20
        var maxSessionAge: TimeInterval = 14 * 24 * 60 * 60
    }

    private static let cleanupLock = NSLock()
    private let rootURL: URL
    private let sessionID: String
    private let node: DevelopmentDiagnosticsNode
    private let configuration: Configuration
    private let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let stateLock = NSLock()
    private var health: DevelopmentDiagnosticsWriterHealth
    private var manifestWritten = false

    init(
        rootURL: URL,
        sessionID: String,
        node: DevelopmentDiagnosticsNode,
        configuration: Configuration = Configuration(),
        queueLabel: String = "com.rokurics.development-diagnostics.writer"
    ) {
        self.rootURL = rootURL
        self.sessionID = sessionID
        self.node = node
        self.configuration = configuration
        queue = DispatchQueue(label: "\(queueLabel).\(node.rawValue).\(sessionID)", qos: .utility)
        queue.setSpecific(key: queueKey, value: ())
        health = DevelopmentDiagnosticsWriterHealth(
            sessionID: sessionID,
            node: node,
            queuedCount: 0,
            writtenCount: 0,
            droppedCount: 0,
            redactionRejectedCount: 0,
            writeFailureCount: 0,
            pendingCount: 0,
            lastWriteAt: nil,
            lastFailureCategory: nil
        )
    }

    func enqueue(_ event: DevelopmentDiagnosticEvent) {
        guard let lineData = Self.encodedJSONLData(for: event) else {
            updateHealth { $0.redactionRejectedCount += 1 }
            return
        }

        stateLock.lock()
        guard health.pendingCount < configuration.maxQueuedEvents else {
            health.droppedCount += 1
            stateLock.unlock()
            return
        }
        health.pendingCount += 1
        health.queuedCount += 1
        stateLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            defer { self.updateHealth { $0.pendingCount = max(0, $0.pendingCount - 1) } }
            self.write(lineData)
        }
    }

    func flush() {
        guard DispatchQueue.getSpecific(key: queueKey) == nil else { return }
        queue.sync {
            writeHealthFile()
        }
    }

    func healthSnapshot() -> DevelopmentDiagnosticsWriterHealth {
        stateLock.lock()
        defer { stateLock.unlock() }
        return health
    }

    private var sessionDirectoryURL: URL {
        rootURL
            .appendingPathComponent("DevelopmentSessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }

    private var logURL: URL {
        sessionDirectoryURL.appendingPathComponent("\(node.rawValue.lowercased())-events.jsonl")
    }

    private var healthURL: URL {
        sessionDirectoryURL.appendingPathComponent("\(node.rawValue.lowercased())-writer-health.json")
    }

    private var manifestURL: URL {
        sessionDirectoryURL.appendingPathComponent("\(node.rawValue.lowercased())-session.json")
    }

    private func write(_ lineData: Data) {
        do {
            try FileManager.default.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true)
            cleanupExpiredSessionsIfNeeded()
            try writeManifestIfNeeded()
            try rotateIfNeeded(incomingByteCount: UInt64(lineData.count))
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: lineData)
            } else {
                try lineData.write(to: logURL, options: .atomic)
            }
            updateHealth {
                $0.writtenCount += 1
                $0.lastWriteAt = Date()
                $0.lastFailureCategory = nil
            }
            if healthSnapshot().writtenCount % 100 == 0 {
                writeHealthFile()
            }
        } catch {
            updateHealth {
                $0.writeFailureCount += 1
                $0.lastFailureCategory = Self.safeToken(String(describing: type(of: error))) ?? "write_failure"
            }
        }
    }

    private func writeManifestIfNeeded() throws {
        guard !manifestWritten else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        let manifest = DevelopmentDiagnosticsSessionManifest(
            sessionID: sessionID,
            node: node,
            processStartedAt: DevelopmentDiagnostics.processStartedAt,
            bundleIdentifier: Self.safeToken(Bundle.main.bundleIdentifier) ?? "unknown",
            appVersion: Self.safeToken(info["CFBundleShortVersionString"] as? String) ?? "unknown",
            appBuild: Self.safeToken(info["CFBundleVersion"] as? String) ?? "unknown",
            operatingSystemVersion: Self.safeToken(ProcessInfo.processInfo.operatingSystemVersionString) ?? "unknown"
        )
        try Self.encodedJSONData(manifest).write(to: manifestURL, options: .atomic)
        manifestWritten = true
    }

    private func cleanupExpiredSessionsIfNeeded(now: Date = Date()) {
        guard !manifestWritten else { return }
        Self.cleanupLock.lock()
        defer { Self.cleanupLock.unlock() }

        let sessionsRoot = sessionDirectoryURL.deletingLastPathComponent()
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: sessionsRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let sessions = candidates.compactMap { url -> (url: URL, date: Date)? in
            guard url.lastPathComponent != sessionID,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory == true else {
                return nil
            }
            return (url, values.contentModificationDate ?? values.creationDate ?? .distantPast)
        }.sorted { $0.date > $1.date }

        let retainedOtherSessionCount = max(0, configuration.maxRetainedSessions - 1)
        for (index, session) in sessions.enumerated() {
            let expired = now.timeIntervalSince(session.date) > configuration.maxSessionAge
            let exceedsCount = index >= retainedOtherSessionCount
            if expired || exceedsCount {
                try? FileManager.default.removeItem(at: session.url)
            }
        }
    }

    private func writeHealthFile() {
        do {
            try FileManager.default.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true)
            try Self.encodedJSONData(healthSnapshot()).write(to: healthURL, options: .atomic)
        } catch {
            updateHealth {
                $0.writeFailureCount += 1
                $0.lastFailureCategory = "health_write_failure"
            }
        }
    }

    private func rotateIfNeeded(incomingByteCount: UInt64) throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path)
        let currentSize = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        guard currentSize + incomingByteCount > configuration.maxLogFileBytes else { return }

        for index in stride(from: max(1, configuration.rotatedFileCount), through: 1, by: -1) {
            let source = index == 1 ? logURL : rotatedLogURL(index: index - 1)
            let destination = rotatedLogURL(index: index)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.moveItem(at: source, to: destination)
            }
        }
    }

    private func rotatedLogURL(index: Int) -> URL {
        URL(fileURLWithPath: logURL.path + ".\(index)")
    }

    private func updateHealth(_ update: (inout DevelopmentDiagnosticsWriterHealth) -> Void) {
        stateLock.lock()
        update(&health)
        stateLock.unlock()
    }

    private static func encodedJSONLData(for event: DevelopmentDiagnosticEvent) -> Data? {
        guard isSafe(event) else { return nil }
        guard var data = try? encodedJSONData(event) else { return nil }
        data.append(0x0A)
        return data
    }

    private static func encodedJSONData<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func isSafe(_ event: DevelopmentDiagnosticEvent) -> Bool {
        safeToken(event.sessionID) == event.sessionID
            && safeToken(event.subsystem) == event.subsystem
            && safeToken(event.event) == event.event
            && event.syncRunID.map { safeToken($0) == $0 } ?? true
            && event.traceID.map { safeToken($0) == $0 } ?? true
            && event.details.allSatisfy { safeToken($0.key) == $0.key && safeToken($0.value) == $0.value }
    }

    static func safeToken(_ value: String?, maxLength: Int = 240) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/Users/"),
              !trimmed.contains("/private/"),
              !trimmed.contains("file://"),
              !trimmed.localizedCaseInsensitiveContains("BEGIN PRIVATE KEY"),
              !trimmed.localizedCaseInsensitiveContains("sharedSecret"),
              !trimmed.localizedCaseInsensitiveContains("apiKey") else {
            return nil
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-+=,()[]@ "))
        let sanitized = trimmed.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        return String(sanitized.prefix(maxLength))
    }
}

nonisolated enum DevelopmentDiagnostics {
    static let sessionHeaderName = "X-Rokurics-Development-Session-ID"
    static let processStartedAt = Date()

    private static let lock = NSLock()
    private static let logger = Logger(subsystem: "Rokurics", category: "DevelopmentDiagnostics")
    private static var activeSessionIDStorage = makeInitialSessionID()
    private static var storesByKey: [String: DevelopmentDiagnosticsFileStore] = [:]

    static var activeSessionID: String {
        lock.lock()
        defer { lock.unlock() }
        return activeSessionIDStorage
    }

    static var activeSessionIDForLogging: String? {
        #if DEBUG
        return activeSessionID
        #else
        return nil
        #endif
    }

    static func requestHeaderFields() -> [String: String] {
        #if DEBUG
        [sessionHeaderName: activeSessionID]
        #else
        [:]
        #endif
    }

    static func adoptSessionID(from headers: [String: String]) {
        #if DEBUG
        let value = headers.first { $0.key.caseInsensitiveCompare(sessionHeaderName) == .orderedSame }?.value
        guard let safe = sanitizedSessionID(value) else { return }
        lock.lock()
        activeSessionIDStorage = safe
        lock.unlock()
        #endif
    }

    static func record(
        node: DevelopmentDiagnosticsNode,
        subsystem: String,
        event: String,
        severity: DevelopmentDiagnosticsSeverity = .info,
        syncRunID: String? = nil,
        traceID: String? = nil,
        details: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        #if DEBUG
        let sessionID = activeSessionID
        let safeSubsystem = DevelopmentDiagnosticsFileStore.safeToken(subsystem) ?? "redactionRejected"
        let safeEvent = DevelopmentDiagnosticsFileStore.safeToken(event) ?? "redactionRejected"
        let safeSyncRunID = DevelopmentDiagnosticsFileStore.safeToken(syncRunID)
        let safeTraceID = DevelopmentDiagnosticsFileStore.safeToken(traceID)
        let safeDetails = details.reduce(into: [String: String]()) { result, pair in
            guard let key = DevelopmentDiagnosticsFileStore.safeToken(pair.key),
                  let value = DevelopmentDiagnosticsFileStore.safeToken(pair.value) else {
                result["redaction"] = "rejected"
                return
            }
            result[key] = value
        }
        let diagnosticEvent = DevelopmentDiagnosticEvent(
            timestamp: timestamp,
            sessionID: sessionID,
            node: node,
            subsystem: safeSubsystem,
            event: safeEvent,
            severity: severity,
            syncRunID: safeSyncRunID,
            traceID: safeTraceID,
            details: safeDetails
        )
        store(sessionID: sessionID, node: node).enqueue(diagnosticEvent)
        logger.debug("\(node.rawValue, privacy: .public) \(safeSubsystem, privacy: .public) \(safeEvent, privacy: .public)")
        #endif
    }

    static func flushForTests() {
        #if DEBUG
        lock.lock()
        let stores = Array(storesByKey.values)
        lock.unlock()
        stores.forEach { $0.flush() }
        #endif
    }

    static func configureSessionForTests(_ sessionID: String) {
        guard let safe = sanitizedSessionID(sessionID) else { return }
        lock.lock()
        activeSessionIDStorage = safe
        lock.unlock()
    }

    private static func store(sessionID: String, node: DevelopmentDiagnosticsNode) -> DevelopmentDiagnosticsFileStore {
        let key = "\(sessionID)|\(node.rawValue)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = storesByKey[key] { return existing }
        let store = DevelopmentDiagnosticsFileStore(
            rootURL: diagnosticsRootURL(node: node),
            sessionID: sessionID,
            node: node
        )
        storesByKey[key] = store
        return store
    }

    private static func diagnosticsRootURL(node: DevelopmentDiagnosticsNode) -> URL {
        let fileManager = FileManager.default
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        switch node {
        case .iPhone:
            return applicationSupport
                .appendingPathComponent("Rokurics", isDirectory: true)
                .appendingPathComponent("Diagnostics", isDirectory: true)
        case .Mac:
            let folderName = Bundle.main.bundleIdentifier == "com.Vita0818.RokuricsMac.local" ? "RokuricsLocal" : "Rokurics"
            return applicationSupport
                .appendingPathComponent(folderName, isDirectory: true)
                .appendingPathComponent("Diagnostics", isDirectory: true)
        }
    }

    private static func makeInitialSessionID() -> String {
        if let override = sanitizedSessionID(ProcessInfo.processInfo.environment["ROKURICS_DIAGNOSTICS_SESSION_ID"]) {
            return override
        }
        let timestamp = ISO8601DateFormatter().string(from: processStartedAt)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return "test-\(timestamp)-\(UUID().uuidString.lowercased().prefix(8))"
    }

    private static func sanitizedSessionID(_ value: String?) -> String? {
        guard let value,
              value.hasPrefix("test-"),
              value.count <= 96,
              DevelopmentDiagnosticsFileStore.safeToken(value, maxLength: 96) == value else {
            return nil
        }
        return value
    }
}
