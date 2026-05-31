//
//  RequestVerifier.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Foundation

enum RequestVerificationResult {
    case accepted(device: PairedDevice)
    case rejected(String)
}

struct RequestVerificationTrace: Equatable {
    var verifierStartedAt: Date
    var routePath: String
    var deviceIDPrefix: String?
    var verifierSucceeded: Bool
    var verifierFailedReason: String?
    var markDeviceSeenCalled: Bool
    var pairedDeviceLastSeenBefore: Date?
    var pairedDeviceLastSeenAfter: Date?
    var errorCategory: String?
}

@MainActor
final class RequestVerifier {
    private struct PathRule {
        let maxBodyBytes: Int
        let allowedContentTypePrefixes: [String]
        let requiredUploadType: String?
    }

    private let pairedDeviceProvider: @MainActor (String) -> PairedDevice?
    private let markDeviceSeen: @MainActor (String, Date) -> Void
    private var recentNoncesByDeviceID: [String: [String: Date]] = [:]
    private(set) var lastTrace: RequestVerificationTrace?
    private let timestampWindow: TimeInterval = 5 * 60
    private let pathRules: [String: PathRule] = [
        "/upload-secure-test": PathRule(
            maxBodyBytes: 1 * 1024 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/upload-recording-metadata": PathRule(
            maxBodyBytes: MacRecordingFileStore.metadataMaxBytes,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: "recording-metadata"
        ),
        "/upload-recording-audio": PathRule(
            maxBodyBytes: MacRecordingFileStore.audioMaxBytes,
            allowedContentTypePrefixes: ["audio/mp4", "audio/m4a", "application/octet-stream"],
            requiredUploadType: "recording-audio"
        ),
        "/upload-recording-audio-session/start": PathRule(
            maxBodyBytes: 256 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/upload-recording-audio-session/status": PathRule(
            maxBodyBytes: 256 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/upload-recording-audio-session/chunk": PathRule(
            maxBodyBytes: MacRecordingFileStore.resumableChunkMaxBytes,
            allowedContentTypePrefixes: ["application/octet-stream", "audio/mp4", "audio/m4a"],
            requiredUploadType: "recording-audio-chunk"
        ),
        "/upload-recording-audio-session/finalize": PathRule(
            maxBodyBytes: 256 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/device/status": PathRule(
            maxBodyBytes: 256 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/device/unpair": PathRule(
            maxBodyBytes: 16 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/connection/heartbeat": PathRule(
            maxBodyBytes: 16 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/connection/probe": PathRule(
            maxBodyBytes: 4 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/status": PathRule(
            maxBodyBytes: 256 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/device-status": PathRule(
            maxBodyBytes: 256 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/manifest": PathRule(
            maxBodyBytes: 256 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/apply": PathRule(
            maxBodyBytes: 4 * 1024 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/inventory": PathRule(
            maxBodyBytes: 1 * 1024 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/apply-metadata": PathRule(
            maxBodyBytes: 4 * 1024 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/start": PathRule(
            maxBodyBytes: 64 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/start-ack": PathRule(
            maxBodyBytes: 64 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/artifact-status": PathRule(
            maxBodyBytes: 256 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/artifact-request": PathRule(
            maxBodyBytes: 256 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        ),
        "/sync/artifact-put": PathRule(
            maxBodyBytes: 6 * 1024 * 1024,
            allowedContentTypePrefixes: ["application/json"],
            requiredUploadType: nil
        )
    ]

    init(pairedDeviceStore: PairedDeviceStore) {
        self.pairedDeviceProvider = { pairedDeviceStore.device(for: $0) }
        self.markDeviceSeen = { deviceID, date in
            pairedDeviceStore.markSeen(deviceID: deviceID, at: date)
        }
    }

    init(
        pairedDeviceProvider: @escaping @MainActor (String) -> PairedDevice?,
        markDeviceSeen: @escaping @MainActor (String, Date) -> Void = { _, _ in }
    ) {
        self.pairedDeviceProvider = pairedDeviceProvider
        self.markDeviceSeen = markDeviceSeen
    }

    func verify(method: String, path: String, headers: [String: String], body: Data, now: Date = Date()) -> RequestVerificationResult {
        let actualBodyHash = MacSecurityUtilities.sha256Hex(body)
        return verify(
            method: method,
            path: path,
            headers: headers,
            bodySHA256: actualBodyHash,
            bodyByteCount: body.count,
            now: now
        )
    }

    func verify(
        method: String,
        path: String,
        headers: [String: String],
        bodySHA256 actualBodyHash: String,
        bodyByteCount: Int,
        now: Date = Date()
    ) -> RequestVerificationResult {
        let traceID = UploadFlightRecorder.traceID(from: headers)
        let headerRecordingID = headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }["x-rokurics-recording-id"]
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "requestVerifierEntered",
            traceID: traceID,
            recordingID: headerRecordingID,
            eventResult: "begin",
            httpPath: path,
            bodyBytes: bodyByteCount
        )
        var trace = RequestVerificationTrace(
            verifierStartedAt: now,
            routePath: path,
            deviceIDPrefix: nil,
            verifierSucceeded: false,
            verifierFailedReason: nil,
            markDeviceSeenCalled: false,
            pairedDeviceLastSeenBefore: nil,
            pairedDeviceLastSeenAfter: nil,
            errorCategory: nil
        )

        guard method == "POST" else {
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierRouteRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "method_not_allowed", httpPath: path, verifierResult: "rejected", bodyBytes: bodyByteCount)
            return reject("method_not_allowed", trace: trace)
        }

        guard let pathRule = pathRules[path] else {
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierRouteRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "path_not_allowed", httpPath: path, verifierResult: "rejected", bodyBytes: bodyByteCount)
            return reject("path_not_allowed", trace: trace)
        }
        UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierRouteAllowed", traceID: traceID, recordingID: headerRecordingID, eventResult: "success", httpPath: path, verifierResult: "route_allowed", bodyBytes: bodyByteCount)

        guard bodyByteCount <= pathRule.maxBodyBytes else {
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierBodySizeRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "body_too_large", httpPath: path, verifierResult: "rejected", bodyBytes: bodyByteCount)
            return reject("body_too_large", trace: trace)
        }
        UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierBodySizeAccepted", traceID: traceID, recordingID: headerRecordingID, eventResult: "success", httpPath: path, verifierResult: "body_size_accepted", bodyBytes: bodyByteCount)

        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }

        let contentType = normalizedHeaders["content-type"]?.lowercased() ?? ""
        guard pathRule.allowedContentTypePrefixes.contains(where: { contentType.hasPrefix($0) }) else {
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierContentTypeRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "content_type_not_allowed", httpPath: path, verifierResult: "rejected")
            return reject("content_type_not_allowed", trace: trace)
        }
        UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierContentTypeAccepted", traceID: traceID, recordingID: headerRecordingID, eventResult: "success", httpPath: path, verifierResult: "content_type_accepted")

        if let requiredUploadType = pathRule.requiredUploadType {
            guard normalizedHeaders["x-rokurics-upload-type"] == requiredUploadType else {
                UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierRouteRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "upload_type_mismatch", httpPath: path, verifierResult: "rejected")
                return reject("upload_type_mismatch", trace: trace)
            }
        }

        guard
            let deviceID = normalizedHeaders["x-rokurics-device-id"],
            let timestamp = normalizedHeaders["x-rokurics-timestamp"],
            let nonce = normalizedHeaders["x-rokurics-nonce"],
            let bodySHA256 = normalizedHeaders["x-rokurics-body-sha256"],
            let signature = normalizedHeaders["x-rokurics-signature"]
        else {
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierRejectedWithReason", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "missing_security_headers", httpPath: path, verifierResult: "rejected")
            return reject("missing_security_headers", trace: trace)
        }
        trace.deviceIDPrefix = String(deviceID.prefix(12))

        guard let device = pairedDeviceProvider(deviceID) else {
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierDeviceRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "unknown_device", httpPath: path, verifierResult: "rejected")
            return reject("unknown_device", trace: trace)
        }
        UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierDeviceAccepted", traceID: traceID, recordingID: headerRecordingID, eventResult: "success", httpPath: path, verifierResult: "device_accepted")
        trace.pairedDeviceLastSeenBefore = device.lastSeenAt

        guard isTimestampValid(timestamp, now: now) else {
            print("[RokuricsVerifier] timestamp rejected")
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierTimestampRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "timestamp_out_of_window", httpPath: path, verifierResult: "rejected")
            return reject("timestamp_out_of_window", trace: trace)
        }
        print("[RokuricsVerifier] timestamp accepted")
        UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierTimestampAccepted", traceID: traceID, recordingID: headerRecordingID, eventResult: "success", httpPath: path, verifierResult: "timestamp_accepted")

        pruneNonces(now: now)
        guard !hasSeenNonce(nonce, for: deviceID) else {
            print("[RokuricsVerifier] nonce rejected")
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierNonceRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "nonce_replay", httpPath: path, verifierResult: "rejected")
            return reject("nonce_replay", trace: trace)
        }
        print("[RokuricsVerifier] nonce accepted")
        UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierNonceAccepted", traceID: traceID, recordingID: headerRecordingID, eventResult: "success", httpPath: path, verifierResult: "nonce_accepted")

        guard MacSecurityUtilities.constantTimeEquals(actualBodyHash, bodySHA256.lowercased()) else {
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierBodyHashRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "body_hash_mismatch", httpPath: path, verifierResult: "rejected")
            return reject("body_hash_mismatch", trace: trace)
        }
        UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierBodyHashAccepted", traceID: traceID, recordingID: headerRecordingID, eventResult: "success", httpPath: path, verifierResult: "body_hash_accepted")

        let signaturePayload = [
            method,
            path,
            timestamp,
            nonce,
            actualBodyHash
        ].joined(separator: "\n")

        guard
            let expectedSignature = MacSecurityUtilities.hmacSHA256Base64URL(
                message: signaturePayload,
                secretBase64URL: device.sharedSecretBase64URL
            ),
            MacSecurityUtilities.constantTimeEquals(expectedSignature, signature)
        else {
            UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierHMACRejected", traceID: traceID, recordingID: headerRecordingID, eventResult: "fail", reasonCode: "signature_mismatch", httpPath: path, verifierResult: "rejected")
            return reject("signature_mismatch", trace: trace)
        }
        UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierHMACAccepted", traceID: traceID, recordingID: headerRecordingID, eventResult: "success", httpPath: path, verifierResult: "hmac_accepted")

        rememberNonce(nonce, for: deviceID, now: now)
        markDeviceSeen(deviceID, now)
        trace.markDeviceSeenCalled = true
        trace.pairedDeviceLastSeenAfter = pairedDeviceProvider(deviceID)?.lastSeenAt
        trace.verifierSucceeded = true
        lastTrace = trace
        print("[RokuricsVerifier] request signature verification success: deviceIDPrefix=\(String(deviceID.prefix(12)))")
        UploadFlightRecorder.record(side: .Mac, stage: "requestVerifierAccepted", traceID: traceID, recordingID: headerRecordingID, eventResult: "success", httpPath: path, verifierResult: "accepted")
        return .accepted(device: device)
    }

    private func isTimestampValid(_ timestamp: String, now: Date) -> Bool {
        if let seconds = TimeInterval(timestamp) {
            return abs(now.timeIntervalSince1970 - seconds) <= timestampWindow
        }

        if let date = ISO8601DateFormatter().date(from: timestamp) {
            return abs(now.timeIntervalSince(date)) <= timestampWindow
        }

        return false
    }

    private func hasSeenNonce(_ nonce: String, for deviceID: String) -> Bool {
        recentNoncesByDeviceID[deviceID]?[nonce] != nil
    }

    private func rememberNonce(_ nonce: String, for deviceID: String, now: Date) {
        var nonces = recentNoncesByDeviceID[deviceID] ?? [:]
        nonces[nonce] = now
        recentNoncesByDeviceID[deviceID] = nonces
    }

    private func pruneNonces(now: Date) {
        for deviceID in recentNoncesByDeviceID.keys {
            recentNoncesByDeviceID[deviceID] = recentNoncesByDeviceID[deviceID]?.filter { _, date in
                now.timeIntervalSince(date) <= timestampWindow
            }
        }
    }

    private func reject(_ reason: String, trace: RequestVerificationTrace) -> RequestVerificationResult {
        var trace = trace
        trace.verifierFailedReason = reason
        trace.errorCategory = reason
        lastTrace = trace
        print("[RokuricsVerifier] request signature verification failure: \(reason)")
        print("[RokuricsVerifier] rejected reason: \(reason)")
        return .rejected(reason)
    }
}
