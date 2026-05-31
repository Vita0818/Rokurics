//
//  UploadFlightRecorder.swift
//  Rokurics
//
//  Created by Codex on 2026/5/31.
//

import Foundation
import OSLog

enum UploadTraceSide: String, Codable {
    case iPhone
    case Mac
}

struct UploadTraceEvent: Codable, Equatable {
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

    private static let logger = Logger(subsystem: "Rokurics", category: "UploadTrace")
    private static let lock = NSLock()
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

        let event = UploadTraceEvent(
            traceID: traceID,
            side: side,
            stage: sanitizeToken(stage) ?? "unknown",
            timestamp: timestamp,
            recordingIDPrefix: recordingID.map { String($0.prefix(12)) },
            eventResult: sanitizeToken(eventResult),
            reasonCode: sanitizeToken(reasonCode),
            uploadStatus: sanitizeToken(uploadStatus),
            ledgerState: sanitizeToken(ledgerState),
            jobIDPrefix: jobID.map { String($0.prefix(12)) },
            sessionIDPrefix: sessionID.map { String($0.prefix(12)) },
            httpPath: sanitizeHTTPPath(httpPath),
            httpStatus: httpStatus,
            routeMatched: routeMatched,
            verifierResult: sanitizeToken(verifierResult),
            fileExists: fileExists,
            fileSize: fileSize,
            resolvedRelativePathToken: sanitizeRelativePathToken(resolvedRelativePathToken),
            bodyBytes: bodyBytes,
            chunkOffset: chunkOffset,
            chunkLength: chunkLength,
            confirmedBytes: confirmedBytes,
            totalBytes: totalBytes,
            macReceiveState: sanitizeToken(macReceiveState),
            audioRelativePathSet: audioRelativePathSet,
            inboxItemState: sanitizeToken(inboxItemState),
            errorDomain: sanitizeToken(errorDomain),
            errorCode: sanitizeToken(errorCode),
            safeErrorMessage: sanitizeErrorMessage(safeErrorMessage)
        )

        guard let line = encodedLine(for: event) else {
            return
        }

        print(line)
        logger.info("\(line, privacy: .public)")
        append(line: line, side: side)
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

    private static func append(line: String, side: UploadTraceSide) {
        lock.lock()
        let url = overrideLogURL ?? defaultLogURL(side: side)
        lock.unlock()

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = Data()
            if FileManager.default.fileExists(atPath: url.path) {
                data = try Data(contentsOf: url)
            }
            data.append(Data((line + "\n").utf8))
            try data.write(to: url, options: .atomic)
        } catch {
            print("[RokuricsUploadTrace] write failed: \(sanitizeErrorMessage(error.localizedDescription) ?? "unknown")")
        }
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
        guard let value = sanitizeToken(value, maxLength: 160) else {
            return nil
        }
        guard value.hasPrefix("/") else {
            return nil
        }
        return value.components(separatedBy: "?").first
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
}
