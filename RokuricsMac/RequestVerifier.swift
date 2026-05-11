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
    private let pairedDeviceStore: PairedDeviceStore
    private var recentNoncesByDeviceID: [String: [String: Date]] = [:]
    private let timestampWindow: TimeInterval = 5 * 60
    private let maxBodyBytes = 1 * 1024 * 1024
    private let allowedContentType = "application/json"
    private let allowedPaths: Set<String> = ["/upload-secure-test"]

    init(pairedDeviceStore: PairedDeviceStore) {
        self.pairedDeviceStore = pairedDeviceStore
    }

    func verify(method: String, path: String, headers: [String: String], body: Data, now: Date = Date()) -> RequestVerificationResult {
        guard method == "POST" else {
            return reject("method_not_allowed")
        }

        guard allowedPaths.contains(path) else {
            return reject("path_not_allowed")
        }

        guard body.count <= maxBodyBytes else {
            return reject("body_too_large")
        }

        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }

        guard normalizedHeaders["content-type"]?.lowercased().hasPrefix(allowedContentType) == true else {
            return reject("content_type_not_allowed")
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

        guard let device = pairedDeviceStore.device(for: deviceID) else {
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

        let actualBodyHash = MacSecurityUtilities.sha256Hex(body)
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
        pairedDeviceStore.markSeen(deviceID: deviceID, at: now)
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
