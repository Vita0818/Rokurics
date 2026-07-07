//
//  UploadFlightRecorder.swift
//  Rokurics
//
//  Created by Codex on 2026/5/31.
//

import Foundation
import OSLog

enum UploadTraceSide: String, Codable, Sendable {
    case iPhone
    case Mac
}

struct UploadTraceEvent: Codable, Equatable, Sendable {
    var traceID: String
    var side: UploadTraceSide
    var stage: String
    var timestamp: Date
    var recordingIDPrefix: String?
    var eventResult: String?
    var reasonCode: String?
    var uploadStatus: String?
    var ledgerState: String?
    var jobIDPrefix: String?
    var sessionIDPrefix: String?
    var httpPath: String?
    var httpStatus: Int?
    var routeMatched: Bool?
    var verifierResult: String?
    var fileExists: Bool?
    var fileSize: Int64?
    var resolvedRelativePathToken: String?
    var bodyBytes: Int?
    var chunkOffset: Int64?
    var chunkLength: Int?
    var confirmedBytes: Int64?
    var totalBytes: Int64?
    var macReceiveState: String?
    var audioRelativePathSet: Bool?
    var inboxItemState: String?
    var errorDomain: String?
    var errorCode: String?
    var safeErrorMessage: String?
}

enum UploadFlightRecorder {
    static let logPrefix = "ROKURICS_UPLOAD_TRACE"
    static let traceHeaderName = "X-Rokurics-Upload-Trace-ID"

    @TaskLocal static var currentTraceID: String?

    private struct PendingUploadTraceEvent: Sendable {
        var traceID: String
        var side: UploadTraceSide
        var stage: String
        var timestamp: Date
        var recordingID: String?
        var eventResult: String?
        var reasonCode: String?
        var uploadStatus: String?
        var ledgerState: String?
        var jobID: String?
        var sessionID: String?
        var httpPath: String?
        var httpStatus: Int?
        var routeMatched: Bool?
        var verifierResult: String?
        var fileExists: Bool?
        var fileSize: Int64?
        var resolvedRelativePathToken: String?
        var bodyBytes: Int?
        var chunkOffset: Int64?
        var chunkLength: Int?
        var confirmedBytes: Int64?
        var totalBytes: Int64?
        var macReceiveState: String?
        var audioRelativePathSet: Bool?
        var inboxItemState: String?
        var errorDomain: String?
        var errorCode: String?
        var safeErrorMessage: String?
    }

    private static let logger = Logger(subsystem: "Rokurics", category: "UploadTrace")
    private static let lock = NSLock()
    private static let writer = UploadTraceAsyncFileWriter()
    private static var overrideLogURL: URL?
    private static var traceIDsByRecordingID: [String: String] = [:]

    static func makeTraceID() -> String {
        "upl-\(UUID().uuidString.lowercased())"
    }

    static func traceID(from headers: [String: String]) -> String? {
        let normalized = headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }
        return sanitizedTraceID(normalized[traceHeaderName.lowercased()])
    }

    static func traceID(forRecordingID recordingID: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return traceIDsByRecordingID[recordingID]
    }

    static func configureLogURL(_ url: URL?) {
        lock.lock()
        overrideLogURL = url?.standardizedFileURL
        lock.unlock()
    }

    static func flushForTests() {
        writer.flushForTests()
    }

    static func loadEvents(from url: URL) throws -> [UploadTraceEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let rawText = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return rawText
            .split(separator: "\n")
            .compactMap { line in
                var text = String(line)
                if text.hasPrefix("\(logPrefix) ") {
                    text.removeFirst(logPrefix.count + 1)
                }
                return try? decoder.decode(UploadTraceEvent.self, from: Data(text.utf8))
            }
    }

    static func record(
        side: UploadTraceSide,
        stage: String,
        traceID explicitTraceID: String? = nil,
        recordingID: String? = nil,
        eventResult: String? = nil,
        reasonCode: String? = nil,
        uploadStatus: String? = nil,
        ledgerState: String? = nil,
        jobID: String? = nil,
        sessionID: String? = nil,
        httpPath: String? = nil,
        httpStatus: Int? = nil,
        routeMatched: Bool? = nil,
        verifierResult: String? = nil,
        fileExists: Bool? = nil,
        fileSize: Int64? = nil,
        resolvedRelativePathToken: String? = nil,
        bodyBytes: Int? = nil,
        chunkOffset: Int64? = nil,
        chunkLength: Int? = nil,
        confirmedBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        macReceiveState: String? = nil,
        audioRelativePathSet: Bool? = nil,
        inboxItemState: String? = nil,
        errorDomain: String? = nil,
        errorCode: String? = nil,
        safeErrorMessage: String? = nil,
        timestamp: Date = Date()
    ) {
        guard let traceID = sanitizedTraceID(explicitTraceID ?? currentTraceID) else {
            return
        }

        if let recordingID {
            remember(traceID: traceID, recordingID: recordingID)
        }

        let event = PendingUploadTraceEvent(
            traceID: traceID,
            side: side,
            stage: stage,
            timestamp: timestamp,
            recordingID: recordingID,
            eventResult: eventResult,
            reasonCode: reasonCode,
            uploadStatus: uploadStatus,
            ledgerState: ledgerState,
            jobID: jobID,
            sessionID: sessionID,
            httpPath: httpPath,
            httpStatus: httpStatus,
            routeMatched: routeMatched,
            verifierResult: verifierResult,
            fileExists: fileExists,
            fileSize: fileSize,
            resolvedRelativePathToken: resolvedRelativePathToken,
            bodyBytes: bodyBytes,
            chunkOffset: chunkOffset,
            chunkLength: chunkLength,
            confirmedBytes: confirmedBytes,
            totalBytes: totalBytes,
            macReceiveState: macReceiveState,
            audioRelativePathSet: audioRelativePathSet,
            inboxItemState: inboxItemState,
            errorDomain: errorDomain,
            errorCode: errorCode,
            safeErrorMessage: safeErrorMessage
        )
        writer.enqueue(event, logURL: logURL(for: side))
    }

    private static func remember(traceID: String, recordingID: String) {
        lock.lock()
        traceIDsByRecordingID[recordingID] = traceID
        lock.unlock()
    }

    private static func encodedLine(for event: UploadTraceEvent) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(event),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return "\(logPrefix) \(json)"
    }

    private static func logURL(for side: UploadTraceSide) -> URL {
        lock.lock()
        let url = overrideLogURL ?? defaultLogURL(side: side)
        lock.unlock()
        return url
    }

    private static func traceEvent(from event: PendingUploadTraceEvent) -> UploadTraceEvent {
        UploadTraceEvent(
            traceID: event.traceID,
            side: event.side,
            stage: sanitizeToken(event.stage) ?? "unknown",
            timestamp: event.timestamp,
            recordingIDPrefix: event.recordingID.map { String($0.prefix(12)) },
            eventResult: sanitizeToken(event.eventResult),
            reasonCode: sanitizeToken(event.reasonCode),
            uploadStatus: sanitizeToken(event.uploadStatus),
            ledgerState: sanitizeToken(event.ledgerState),
            jobIDPrefix: event.jobID.map { String($0.prefix(12)) },
            sessionIDPrefix: event.sessionID.map { String($0.prefix(12)) },
            httpPath: sanitizeHTTPPath(event.httpPath),
            httpStatus: event.httpStatus,
            routeMatched: event.routeMatched,
            verifierResult: sanitizeToken(event.verifierResult),
            fileExists: event.fileExists,
            fileSize: event.fileSize,
            resolvedRelativePathToken: sanitizeRelativePathToken(event.resolvedRelativePathToken),
            bodyBytes: event.bodyBytes,
            chunkOffset: event.chunkOffset,
            chunkLength: event.chunkLength,
            confirmedBytes: event.confirmedBytes,
            totalBytes: event.totalBytes,
            macReceiveState: sanitizeToken(event.macReceiveState),
            audioRelativePathSet: event.audioRelativePathSet,
            inboxItemState: sanitizeToken(event.inboxItemState),
            errorDomain: sanitizeToken(event.errorDomain),
            errorCode: sanitizeToken(event.errorCode),
            safeErrorMessage: sanitizeErrorMessage(event.safeErrorMessage)
        )
    }

    private static func defaultLogURL(side: UploadTraceSide) -> URL {
        let fileManager = FileManager.default
        #if os(iOS)
        let root = (fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory)
            .appendingPathComponent("Rokurics", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        return root.appendingPathComponent("upload-trace.jsonl", isDirectory: false).standardizedFileURL
        #elseif os(macOS)
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let folderName = bundleID == "com.Vita0818.RokuricsMac.local" ? "RokuricsLocal" : "Rokurics"
        let root = (fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory)
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("system", isDirectory: true)
        return root.appendingPathComponent("upload-trace.jsonl", isDirectory: false).standardizedFileURL
        #else
        return fileManager.temporaryDirectory.appendingPathComponent("upload-trace.jsonl", isDirectory: false)
        #endif
    }

    private static func sanitizedTraceID(_ value: String?) -> String? {
        guard let sanitized = sanitizeToken(value, maxLength: 96),
              sanitized.hasPrefix("upl-") || sanitized.hasPrefix("recording-") || sanitized.hasPrefix("test-") else {
            return nil
        }
        return sanitized
    }

    private static func sanitizeToken(_ value: String?, maxLength: Int = 160) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let scalars = trimmed.unicodeScalars.map { scalar -> String in
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-+/= "))
            return allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
        return String(scalars.prefix(maxLength))
    }

    private static func sanitizeHTTPPath(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let pathOnly = value.components(separatedBy: "?").first
        guard let sanitized = sanitizeToken(pathOnly, maxLength: 160), sanitized.hasPrefix("/") else {
            return nil
        }
        return sanitized
    }

    private static func sanitizeRelativePathToken(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else {
            return "absolute_path_redacted"
        }
        if trimmed.contains("..") {
            return "relative_path_redacted"
        }
        return sanitizeToken(trimmed, maxLength: 180)
    }

    private static func sanitizeErrorMessage(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.contains("/Users/") || trimmed.contains("/private/") || trimmed.contains("file://") {
            return "private_path_redacted"
        }
        return sanitizeToken(trimmed, maxLength: 180)
    }

    private final class UploadTraceAsyncFileWriter: @unchecked Sendable {
        private struct Configuration: Sendable {
            var maxQueuedEvents: Int = 1_024
            var maxLogFileBytes: UInt64 = 5 * 1_024 * 1_024
            var rotatedFileCount: Int = 1
        }

        private let configuration: Configuration
        private let queue: DispatchQueue
        private let specificKey = DispatchSpecificKey<Void>()
        private let stateLock = NSLock()
        private var pendingEventCount = 0

        init(queueLabel: String = "com.rokurics.upload-flight-recorder.writer") {
            self.configuration = Configuration()
            self.queue = DispatchQueue(label: queueLabel, qos: .utility)
            queue.setSpecific(key: specificKey, value: ())
        }

        func enqueue(_ event: PendingUploadTraceEvent, logURL: URL) {
            stateLock.lock()
            guard pendingEventCount < configuration.maxQueuedEvents else {
                stateLock.unlock()
                return
            }
            pendingEventCount += 1
            stateLock.unlock()

            queue.async { [weak self] in
                guard let self else {
                    return
                }
                defer { self.finishQueuedEvent() }
                self.write(event, to: logURL)
            }
        }

        func flushForTests() {
            guard DispatchQueue.getSpecific(key: specificKey) == nil else {
                return
            }
            queue.sync {}
        }

        private func finishQueuedEvent() {
            stateLock.lock()
            pendingEventCount = max(0, pendingEventCount - 1)
            stateLock.unlock()
        }

        private func write(_ pendingEvent: PendingUploadTraceEvent, to logURL: URL) {
            let event = UploadFlightRecorder.traceEvent(from: pendingEvent)
            guard let line = UploadFlightRecorder.encodedLine(for: event) else {
                return
            }

            #if DEBUG
            print(line)
            #endif
            UploadFlightRecorder.logger.info("\(line, privacy: .public)")

            let lineData = Data((line + "\n").utf8)
            do {
                try FileManager.default.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try rotateIfNeeded(logURL: logURL, incomingByteCount: UInt64(lineData.count))
                if FileManager.default.fileExists(atPath: logURL.path) {
                    let handle = try FileHandle(forWritingTo: logURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: lineData)
                } else {
                    try lineData.write(to: logURL)
                }
            } catch {
                let message = UploadFlightRecorder.sanitizeErrorMessage(error.localizedDescription) ?? "unknown"
                #if DEBUG
                print("[RokuricsUploadTrace] write failed: \(message)")
                #endif
                UploadFlightRecorder.logger.error("upload trace write failed: \(message, privacy: .public)")
            }
        }

        private func rotateIfNeeded(logURL: URL, incomingByteCount: UInt64) throws {
            guard configuration.maxLogFileBytes > 0,
                  currentFileSize(at: logURL) + incomingByteCount > configuration.maxLogFileBytes else {
                return
            }

            let backupCount = max(1, configuration.rotatedFileCount)
            for index in stride(from: backupCount, through: 1, by: -1) {
                let sourceURL = index == 1 ? logURL : rotatedLogURL(for: logURL, index: index - 1)
                let destinationURL = rotatedLogURL(for: logURL, index: index)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                }
            }
        }

        private func currentFileSize(at url: URL) -> UInt64 {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else {
                return 0
            }
            return size.uint64Value
        }

        private func rotatedLogURL(for logURL: URL, index: Int) -> URL {
            URL(fileURLWithPath: "\(logURL.path).\(index)", isDirectory: false)
        }
    }
}
