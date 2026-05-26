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
        "/sync/artifact-request": PathRule(
            maxBodyBytes: 256 * 1024,
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
        guard method == "POST" else {
            return reject("method_not_allowed")
        }

        guard let pathRule = pathRules[path] else {
            return reject("path_not_allowed")
        }

        guard bodyByteCount <= pathRule.maxBodyBytes else {
            return reject("body_too_large")
        }

        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }

        let contentType = normalizedHeaders["content-type"]?.lowercased() ?? ""
        guard pathRule.allowedContentTypePrefixes.contains(where: { contentType.hasPrefix($0) }) else {
            return reject("content_type_not_allowed")
        }

        if let requiredUploadType = pathRule.requiredUploadType {
            guard normalizedHeaders["x-rokurics-upload-type"] == requiredUploadType else {
                return reject("upload_type_mismatch")
            }
        }

        guard
            let deviceID = normalizedHeaders["x-rokurics-device-id"],
            let timestamp = normalizedHeaders["x-rokurics-timestamp"],
            let nonce = normalizedHeaders["x-rokurics-nonce"],
            let bodySHA256 = normalizedHeaders["x-rokurics-body-sha256"],
            let signature = normalizedHeaders["x-rokurics-signature"]
        else {
            return reject("missing_security_headers")
        }

        guard let device = pairedDeviceProvider(deviceID) else {
            return reject("unknown_device")
        }

        guard isTimestampValid(timestamp, now: now) else {
            print("[RokuricsVerifier] timestamp rejected")
            return reject("timestamp_out_of_window")
        }
        print("[RokuricsVerifier] timestamp accepted")

        pruneNonces(now: now)
        guard !hasSeenNonce(nonce, for: deviceID) else {
            print("[RokuricsVerifier] nonce rejected")
            return reject("nonce_replay")
        }
        print("[RokuricsVerifier] nonce accepted")

        guard MacSecurityUtilities.constantTimeEquals(actualBodyHash, bodySHA256.lowercased()) else {
            return reject("body_hash_mismatch")
        }

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
            return reject("signature_mismatch")
        }

        rememberNonce(nonce, for: deviceID, now: now)
        markDeviceSeen(deviceID, now)
        print("[RokuricsVerifier] request signature verification success: deviceIDPrefix=\(String(deviceID.prefix(12)))")
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

    private func reject(_ reason: String) -> RequestVerificationResult {
        print("[RokuricsVerifier] request signature verification failure: \(reason)")
        print("[RokuricsVerifier] rejected reason: \(reason)")
        return .rejected(reason)
    }
}
