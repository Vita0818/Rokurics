//
//  SecureMacUploadClient.swift
//  Rokurics
//
//  Created by Codex on 2026/5/10.
//

import Combine
import Foundation
import Security
import UIKit

struct SecureUploadPreparedRequest {
    let url: URL
    let body: Data
    let headers: [String: String]
}

struct SecureUploadRawResponse {
    let statusCode: Int
    let responseByteCount: Int
}

struct SecurePairingResult {
    let deviceID: String
    let sharedSecretBase64URL: String
    let pairedAt: String
    var macName: String = ""
    var macModel: String = ""
    var confirmationToken: String = ""

    var deviceIDPrefix: String {
        String(deviceID.prefix(12))
    }
}

struct SecureUploadResult {
    let fileName: String
}

struct SecureUploadServerResponse: Decodable {
    let ok: Bool
    let message: String?
    let disposition: String?
    let fileName: String?
    let recordingID: String?
    let metadataFileName: String?
    let audioFileName: String?
    let receiveStatus: String?
    let processingStatus: String?
    let error: String?
    let reason: String?
}

struct SecureHTTPSHealthCheckResult {
    let statusCode: Int
    let body: String
}

struct ConnectionProbeRequest: Codable, Equatable {
    var sequenceNumber: UInt64
    var clientPayload: String
    var sentAt: Date
}

struct ConnectionProbeResponse: Codable, Equatable {
    var ok: Bool
    var disposition: String
    var receivedSequenceNumber: UInt64
    var echoedClientPayload: String
    var serverPayload: String
    var serverTime: Date
    var syncRequested: Bool?
    var syncStartSignal: LocalNetworkSyncStartSignal? = nil
}

enum SecureMacUploadError: LocalizedError {
    case notPaired
    case invalidURL
    case invalidSecret
    case invalidFingerprint
    case fingerprintMismatch
    case invalidResponse
    case serverRejected(String)
    case httpsUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notPaired:
            return RokuricsCopy.text("请先完成安全配对。", "Complete secure pairing first.")
        case .invalidURL:
            return RokuricsCopy.text("Mac 地址或端口无效。", "Mac address or port is invalid.")
        case .invalidSecret:
            return RokuricsCopy.text("配对密钥无效，请重新配对。", "Pairing secret is invalid. Pair again.")
        case .invalidFingerprint:
            return RokuricsCopy.text("请输入完整的 Mac 证书 SHA256 指纹。", "Enter the full Mac certificate SHA256 fingerprint.")
        case .fingerprintMismatch:
            return RokuricsCopy.text("Mac 指纹不匹配，已阻断连接。", "Mac fingerprint mismatch. Connection blocked.")
        case .invalidResponse:
            return RokuricsCopy.text("Mac 响应无法解析。", "Mac response could not be parsed.")
        case .serverRejected(let reason):
            return reason
        case .httpsUnavailable(let reason):
            return reason
        }
    }
}

final class SecureMacUploadClient: ObservableObject {
    static let isHTTPSUploadEnabled = true

    private let canonicalChecksumRuntime: CanonicalChecksumRuntime
    private let canonicalChecksumCacheDirectoryURL: URL?

    init(
        canonicalChecksumRuntime: CanonicalChecksumRuntime? = nil,
        canonicalChecksumCacheDirectoryURL: URL? = nil
    ) {
        self.canonicalChecksumRuntime = canonicalChecksumRuntime ?? CanonicalChecksumRuntime()
        self.canonicalChecksumCacheDirectoryURL = canonicalChecksumCacheDirectoryURL
    }

    private struct PairRequest: Encodable {
        let pairingCode: String
        let deviceName: String
        let deviceType: String
    }

    private struct PairResponse: Decodable {
        let ok: Bool
        let deviceID: String?
        let sharedSecret: String?
        let confirmationToken: String?
        let pairedAt: String?
        let macName: String?
        let macModel: String?
        let macDisplayName: String?
        let macDeviceModel: String?
        let error: String?
    }

    private struct PairConfirmationRequest: Encodable {
        let deviceID: String
        let confirmationToken: String
    }

    private struct PairConfirmationResponse: Decodable {
        let ok: Bool
        let deviceID: String?
        let disposition: String?
        let error: String?
    }

    private struct UploadResponse: Decodable {
        let ok: Bool
        let message: String?
        let fileName: String?
        let error: String?
    }

    private struct DeviceUnpairRequest: Encodable {
        let deviceID: String
        let reason: String
        let requestedAt: Date
    }

    func healthCheck(
        host: String,
        port: Int,
        macFingerprint: String,
        diagnostics: ((String) -> Void)? = nil
    ) async throws -> SecureHTTPSHealthCheckResult {
        print("[RokuricsHTTPSCheck] health check started")
        let expectedFingerprint = try normalizedExpectedFingerprint(macFingerprint)
        let url = try secureURL(host: host, port: port, path: "/health")
        let pinnedSession = makePinnedSession(expectedFingerprint: expectedFingerprint, diagnostics: diagnostics)
        defer {
            pinnedSession.session.invalidateAndCancel()
        }

        print("[RokuricsHTTPSCheck] url: \(url.absoluteString)")
        pinnedSession.context.emitDiagnosticStep("开始连接")
        pinnedSession.context.emitDiagnosticStep("请求地址：\(url.absoluteString)")
        pinnedSession.context.emitDiagnosticStep("等待 TLS challenge")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("close", forHTTPHeaderField: "Connection")
        DevelopmentDiagnostics.requestHeaderFields().forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        pinnedSession.context.emitDiagnosticStep("已发送 /health")

        do {
            let (data, response) = try await pinnedSession.session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[RokuricsHTTPSCheck] response status code: \(statusCode)")
            print("[RokuricsHTTPSCheck] response body: \(responseBody)")
            pinnedSession.context.emitDiagnosticStep("收到 \(statusCode)")

            guard pinnedSession.context.didReceiveTLSChallenge else {
                let reason = "未收到 TLS challenge。"
                pinnedSession.context.emitDiagnosticStep(reason)
                throw SecureMacUploadError.httpsUnavailable(reason)
            }

            guard statusCode == 200 else {
                throw SecureMacUploadError.serverRejected("响应非 200：\(statusCode)")
            }

            return SecureHTTPSHealthCheckResult(statusCode: statusCode, body: responseBody)
        } catch {
            if let pinningError = pinnedSession.context.currentPinningError {
                print("[RokuricsHTTPSCheck][ERROR] \(pinningError.localizedDescription)")
                pinnedSession.context.emitDiagnosticStep("失败：\(pinningError.localizedDescription)")
                throw pinningError
            }

            let mappedError = mapHealthCheckError(error, context: pinnedSession.context)
            print("[RokuricsHTTPSCheck][ERROR] \(mappedError.localizedDescription)")
            pinnedSession.context.emitDiagnosticStep("失败：\(mappedError.localizedDescription)")
            throw mappedError
        }
    }

    func checkHTTPSHealth(host: String, port: Int, macFingerprint: String) async throws -> SecureHTTPSHealthCheckResult {
        try await healthCheck(host: host, port: port, macFingerprint: macFingerprint)
    }

    func pair(host: String, port: Int, pairingCode: String, macFingerprint: String) async throws -> SecurePairingResult {
        let expectedFingerprint = try normalizedExpectedFingerprint(macFingerprint)
        let url = try secureURL(host: host, port: port, path: "/pair")
        let pinnedSession = makePinnedSession(expectedFingerprint: expectedFingerprint, diagnostics: nil)
        defer {
            pinnedSession.session.invalidateAndCancel()
        }

        let pairRequest = PairRequest(
            pairingCode: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceName: UIDevice.current.name,
            deviceType: "iPhone"
        )
        let body = try JSONEncoder().encode(pairRequest)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        DevelopmentDiagnostics.requestHeaderFields().forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        print("[RokuricsPairing] target URL: \(url.absoluteString)")
        print("[RokuricsPairing] pairing payload size: \(body.count)")

        do {
            let (data, response) = try await pinnedSession.session.upload(for: request, from: body)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[RokuricsPairing] response status code: \(statusCode)")

            let pairResponse = try JSONDecoder().decode(PairResponse.self, from: data)
            guard pairResponse.ok,
                  let deviceID = pairResponse.deviceID,
                  let sharedSecret = pairResponse.sharedSecret,
                  let pairedAt = pairResponse.pairedAt,
                  let confirmationToken = pairResponse.confirmationToken,
                  !confirmationToken.isEmpty else {
                throw SecureMacUploadError.serverRejected(pairResponse.error ?? "pairing_failed")
            }

            let result = SecurePairingResult(
                deviceID: deviceID,
                sharedSecretBase64URL: sharedSecret,
                pairedAt: pairedAt,
                macName: pairResponse.macName ?? pairResponse.macDisplayName ?? "",
                macModel: pairResponse.macModel ?? pairResponse.macDeviceModel ?? "",
                confirmationToken: confirmationToken
            )
            print("[RokuricsPairing] pairing success: deviceIDPrefix=\(result.deviceIDPrefix)")
            return result
        } catch {
            if let pinningError = pinnedSession.context.currentPinningError {
                throw pinningError
            }
            print("[RokuricsPairing] pairing error: \(error.localizedDescription)")
            throw error
        }
    }

    func confirmPairing(
        host: String,
        port: Int,
        macFingerprint: String,
        result: SecurePairingResult
    ) async throws {
        let expectedFingerprint = try normalizedExpectedFingerprint(macFingerprint)
        let url = try secureURL(host: host, port: port, path: "/pair/confirm")
        let body = try JSONEncoder().encode(
            PairConfirmationRequest(
                deviceID: result.deviceID,
                confirmationToken: result.confirmationToken
            )
        )
        var lastError: Error?
        for _ in 0..<3 {
            let pinnedSession = makePinnedSession(expectedFingerprint: expectedFingerprint, diagnostics: nil)
            defer { pinnedSession.session.invalidateAndCancel() }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            DevelopmentDiagnostics.requestHeaderFields().forEach { key, value in
                request.setValue(value, forHTTPHeaderField: key)
            }
            do {
                let (data, response) = try await pinnedSession.session.upload(for: request, from: body)
                if let pinningError = pinnedSession.context.currentPinningError {
                    throw pinningError
                }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let confirmation = try JSONDecoder().decode(PairConfirmationResponse.self, from: data)
                guard statusCode == 200,
                      confirmation.ok,
                      confirmation.deviceID == result.deviceID else {
                    throw SecureMacUploadError.serverRejected(confirmation.error ?? "pairing_confirmation_failed")
                }
                return
            } catch {
                lastError = pinnedSession.context.currentPinningError ?? error
            }
        }

        // The confirm response may be lost after the Mac committed, or the
        // confirm request itself may be lost while the prepared credential is
        // still pending. A valid pinned + HMAC heartbeat proves possession of
        // the returned secret and lets RequestVerifier commit either state.
        do {
            let proofSettings = SecureMacConnectionSnapshot(
                macHost: host,
                macPort: port,
                macFingerprint: expectedFingerprint,
                macName: result.macName,
                macModel: result.macModel,
                deviceID: result.deviceID,
                sharedSecretBase64URL: result.sharedSecretBase64URL,
                pairedAt: result.pairedAt
            )
            let proofResponse = try await sendConnectionHeartbeat(
                settings: proofSettings,
                request: ConnectionHeartbeatRequest(
                    deviceID: result.deviceID,
                    deviceName: UIDevice.current.name,
                    platform: .iPhone,
                    appInstanceID: nil,
                    sequenceNumber: 1,
                    sentAt: Date(),
                    lastKnownPeerStatusRevision: nil
                ),
                requestTimeout: 3
            )
            guard proofResponse.ok else {
                throw SecureMacUploadError.serverRejected(proofResponse.error ?? "pairing_credential_proof_failed")
            }
            return
        } catch {
            lastError = error
        }
        throw lastError ?? SecureMacUploadError.serverRejected("pairing_confirmation_failed")
    }

    func prepareSignedTestUpload(settings: SecureMacConnectionSnapshot, now: Date = Date()) throws -> SecureUploadPreparedRequest {
        guard settings.isPaired else {
            throw SecureMacUploadError.notPaired
        }

        let url = try secureURL(host: settings.macHost, port: settings.macPort, path: "/upload-secure-test")
        let payload = UploadTestPayload.makeSecureTestPayload(createdAt: now)
        let body = try JSONEncoder().encode(payload)
        let bodySHA256 = SecureUploadUtilities.sha256Hex(body)
        let timestamp = String(format: "%.0f", now.timeIntervalSince1970)
        let nonce = SecureUploadUtilities.randomBase64URLToken()
        let path = "/upload-secure-test"
        let signaturePayload = [
            "POST",
            path,
            timestamp,
            nonce,
            bodySHA256
        ].joined(separator: "\n")

        guard let signature = SecureUploadUtilities.hmacSHA256Base64URL(
            message: signaturePayload,
            secretBase64URL: settings.sharedSecretBase64URL
        ) else {
            throw SecureMacUploadError.invalidSecret
        }

        var headers = [
            "Content-Type": "application/json",
            "X-Rokurics-Device-ID": settings.deviceID,
            "X-Rokurics-Timestamp": timestamp,
            "X-Rokurics-Nonce": nonce,
            "X-Rokurics-Body-SHA256": bodySHA256,
            "X-Rokurics-Signature": signature,
            "X-Rokurics-Filename": Self.secureTestFileName(createdAt: now)
        ]
        DevelopmentDiagnostics.requestHeaderFields().forEach { key, value in
            headers[key] = value
        }

        return SecureUploadPreparedRequest(url: url, body: body, headers: headers)
    }

    func uploadTestFile(settings: SecureMacConnectionSnapshot) async throws -> SecureUploadResult {
        let expectedFingerprint = try normalizedExpectedFingerprint(settings.macFingerprint)
        let preparedRequest = try prepareSignedTestUpload(settings: settings)
        let pinnedSession = makePinnedSession(expectedFingerprint: expectedFingerprint, diagnostics: nil)
        defer {
            pinnedSession.session.invalidateAndCancel()
        }

        print("[RokuricsSecureUpload] target URL: \(preparedRequest.url.absoluteString)")
        print("[RokuricsSecureUpload] payload size: \(preparedRequest.body.count)")
        print("[RokuricsSecureUpload] request headers: \(preparedRequest.headers.keys.sorted())")

        var request = URLRequest(url: preparedRequest.url)
        request.httpMethod = "POST"
        preparedRequest.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await pinnedSession.session.upload(for: request, from: preparedRequest.body)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[RokuricsSecureUpload] response status code: \(statusCode)")
            print("[RokuricsSecureUpload] response body: \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")

            let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
            guard uploadResponse.ok, let fileName = uploadResponse.fileName else {
                throw SecureMacUploadError.serverRejected(uploadResponse.error ?? "secure_upload_failed")
            }

            print("[RokuricsSecureUpload] secure upload success: \(fileName)")
            return SecureUploadResult(fileName: fileName)
        } catch {
            if let pinningError = pinnedSession.context.currentPinningError {
                throw pinningError
            }
            print("[RokuricsSecureUpload] errors: \(error.localizedDescription)")
            throw error
        }
    }

    func sendDeviceStatus(settings: SecureMacConnectionSnapshot, statusRequest: DeviceStatusRequest) async throws -> DeviceStatusResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/device/status",
            body: statusRequest,
            requestTimeout: 5,
            resourceTimeout: 8
        )
    }

    func sendLocalNetworkSyncDeviceStatus(settings: SecureMacConnectionSnapshot, statusRequest: DeviceStatusRequest) async throws -> DeviceStatusResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/device-status",
            body: statusRequest,
            requestTimeout: 5,
            resourceTimeout: 8
        )
    }

    func sendConnectionHeartbeat(
        settings: SecureMacConnectionSnapshot,
        request: ConnectionHeartbeatRequest,
        requestTimeout: TimeInterval = 2
    ) async throws -> ConnectionHeartbeatResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/connection/heartbeat",
            body: request,
            requestTimeout: requestTimeout,
            resourceTimeout: max(requestTimeout, 3)
        )
    }

    func pullMacToIPhoneUploadChunk(
        settings: SecureMacConnectionSnapshot,
        request: MacToIPhoneUploadChunkRequest
    ) async throws -> MacToIPhoneUploadChunkResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/upload/mac-to-iphone/chunk",
            body: request,
            requestTimeout: 10,
            resourceTimeout: 20
        )
    }

    func acknowledgeMacToIPhoneUpload(
        settings: SecureMacConnectionSnapshot,
        request: MacToIPhoneUploadAckRequest
    ) async throws -> MacToIPhoneUploadAckResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/upload/mac-to-iphone/ack",
            body: request,
            requestTimeout: 5,
            resourceTimeout: 8
        )
    }

    func sendConnectionProbe(
        settings: SecureMacConnectionSnapshot,
        request: ConnectionProbeRequest,
        requestTimeout: TimeInterval = 2
    ) async throws -> ConnectionProbeResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/connection/probe",
            body: request,
            requestTimeout: requestTimeout,
            resourceTimeout: max(requestTimeout, 3)
        )
    }

    func sendDeviceUnpair(
        settings: SecureMacConnectionSnapshot,
        reason: String = "user_disconnect"
    ) async throws -> SecureUploadServerResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/device/unpair",
            body: DeviceUnpairRequest(deviceID: settings.deviceID, reason: reason, requestedAt: Date()),
            requestTimeout: 2,
            resourceTimeout: 3
        )
    }

    func fetchStudyLibraryManifest(settings: SecureMacConnectionSnapshot) async throws -> StudyLibrarySyncManifestResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/manifest",
            body: SyncEmptyRequest(),
            requestTimeout: 10,
            resourceTimeout: 20
        )
    }

    func applyStudyLibraryManifest(
        settings: SecureMacConnectionSnapshot,
        manifest: StudyLibrarySyncManifest,
        syncRunID: String? = nil
    ) async throws -> StudyLibrarySyncManifestResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/apply",
            body: StudyLibrarySyncManifestRequest(manifest: manifest, syncRunID: syncRunID),
            requestTimeout: 15,
            resourceTimeout: 30
        )
    }

    func fetchLocalNetworkSyncInventory(
        settings: SecureMacConnectionSnapshot,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String? = nil
    ) async throws -> LocalNetworkSyncInventoryResponse {
        try await fetchLocalNetworkSyncInventory(
            settings: settings,
            localInventory: localInventory,
            syncRunID: syncRunID,
            statusExchangeEnvelope: nil
        )
    }

    func fetchLocalNetworkSyncInventory(
        settings: SecureMacConnectionSnapshot,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String? = nil,
        statusExchangeEnvelope: CanonicalStatusExchangeEnvelope?
    ) async throws -> LocalNetworkSyncInventoryResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/inventory",
            body: LocalNetworkSyncInventoryRequest(
                deviceID: localInventory.device.deviceID,
                generatedAt: Date(),
                localInventoryHash: localInventory.inventoryHash,
                localInventory: localInventory,
                syncRunID: syncRunID,
                statusExchangeEnvelope: statusExchangeEnvelope
            ),
            requestTimeout: 10,
            resourceTimeout: 20
        )
    }

    func sendLocalNetworkSyncStartSignal(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartRequest
    ) async throws -> LocalNetworkSyncStartResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/start",
            body: request,
            requestTimeout: 5,
            resourceTimeout: 8
        )
    }

    func sendLocalNetworkSyncStartAck(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncStartAckRequest
    ) async throws -> LocalNetworkSyncStartAckResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/start-ack",
            body: request,
            requestTimeout: 5,
            resourceTimeout: 8
        )
    }

    func applyLocalNetworkSyncMetadata(
        settings: SecureMacConnectionSnapshot,
        manifest: StudyLibrarySyncManifest
    ) async throws -> StudyLibrarySyncManifestResponse {
        try await applyLocalNetworkSyncMetadata(settings: settings, manifest: manifest, syncRunID: nil)
    }

    func applyLocalNetworkSyncMetadata(
        settings: SecureMacConnectionSnapshot,
        manifest: StudyLibrarySyncManifest,
        syncRunID: String?
    ) async throws -> StudyLibrarySyncManifestResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/apply-metadata",
            body: StudyLibrarySyncManifestRequest(manifest: manifest, syncRunID: syncRunID),
            requestTimeout: 15,
            resourceTimeout: 30
        )
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        artifactID: String
    ) async throws -> LocalNetworkSyncArtifactResponse {
        try await requestLocalNetworkSyncArtifact(
            settings: settings,
            request: LocalNetworkSyncArtifactRequest(artifactID: artifactID)
        )
    }

    func requestLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactRequest
    ) async throws -> LocalNetworkSyncArtifactResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/artifact-request",
            body: request,
            requestTimeout: 10,
            resourceTimeout: 30
        )
    }

    func fetchLocalNetworkSyncArtifactStatus(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactStatusRequest
    ) async throws -> LocalNetworkSyncArtifactStatusResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/artifact-status",
            body: request,
            requestTimeout: 10,
            resourceTimeout: 20
        )
    }

    func putLocalNetworkSyncArtifact(
        settings: SecureMacConnectionSnapshot,
        request: LocalNetworkSyncArtifactPutRequest
    ) async throws -> LocalNetworkSyncArtifactPutResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/sync/artifact-put",
            body: request,
            requestTimeout: 15,
            resourceTimeout: 30
        )
    }

    func uploadSignedData(
        settings: SecureMacConnectionSnapshot,
        path: String,
        body: Data,
        contentType: String,
        uploadType: String,
        recordingID: String,
        fileName: String,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> SecureUploadServerResponse {
        guard settings.isPaired else {
            throw SecureMacUploadError.notPaired
        }

        let expectedFingerprint = try normalizedExpectedFingerprint(settings.macFingerprint)
        let url = try secureURL(host: settings.macHost, port: settings.macPort, path: path)
        let now = Date()
        let bodySHA256 = SecureUploadUtilities.sha256Hex(body)
        let traceID = UploadFlightRecorder.currentTraceID
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureUploadClientEntered",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "begin",
            httpPath: path,
            bodyBytes: body.count
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureConnectionSettingsLoaded",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestBodyHashComputed",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path,
            bodyBytes: body.count
        )
        let timestamp = String(format: "%.0f", now.timeIntervalSince1970)
        let nonce = SecureUploadUtilities.randomBase64URLToken()
        let signaturePayload = [
            "POST",
            path,
            timestamp,
            nonce,
            bodySHA256
        ].joined(separator: "\n")

        guard let signature = SecureUploadUtilities.hmacSHA256Base64URL(
            message: signaturePayload,
            secretBase64URL: settings.sharedSecretBase64URL
        ) else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureCredentialMissing",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "invalid_secret",
                httpPath: path
            )
            throw SecureMacUploadError.invalidSecret
        }
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureCredentialLoaded",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestSigned",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path
        )

        let pinnedSession = makePinnedSession(
            expectedFingerprint: expectedFingerprint,
            diagnostics: nil,
            traceID: traceID,
            recordingID: recordingID,
            httpPath: path,
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout
        )
        defer {
            pinnedSession.session.invalidateAndCancel()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(settings.deviceID, forHTTPHeaderField: "X-Rokurics-Device-ID")
        request.setValue(timestamp, forHTTPHeaderField: "X-Rokurics-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-Rokurics-Nonce")
        request.setValue(bodySHA256, forHTTPHeaderField: "X-Rokurics-Body-SHA256")
        request.setValue(signature, forHTTPHeaderField: "X-Rokurics-Signature")
        request.setValue(recordingID, forHTTPHeaderField: "X-Rokurics-Recording-ID")
        request.setValue(fileName, forHTTPHeaderField: "X-Rokurics-Filename")
        request.setValue(uploadType, forHTTPHeaderField: "X-Rokurics-Upload-Type")
        if let traceID {
            request.setValue(traceID, forHTTPHeaderField: UploadFlightRecorder.traceHeaderName)
        }
        DevelopmentDiagnostics.requestHeaderFields().forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestBuilt",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path,
            bodyBytes: body.count
        )

        print("[RokuricsRecordingUpload] target URL: \(url.absoluteString)")
        print("[RokuricsRecordingUpload] uploadType=\(uploadType), bodySize=\(body.count), recordingIDPrefix=\(String(recordingID.prefix(12)))")

        do {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestStarted",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "begin",
                httpPath: path,
                bodyBytes: body.count
            )
            let (data, response) = try await pinnedSession.session.upload(for: request, from: body)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestResponseReceived",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: (200..<300).contains(statusCode) ? "success" : "fail",
                httpPath: path,
                httpStatus: statusCode,
                bodyBytes: data.count
            )
            print("[RokuricsRecordingUpload] response status code: \(statusCode)")
            print("[RokuricsRecordingUpload] response body: \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")

            let uploadResponse = try JSONDecoder().decode(SecureUploadServerResponse.self, from: data)
            guard uploadResponse.ok else {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "secureRequestFailed",
                    traceID: traceID,
                    recordingID: recordingID,
                    eventResult: "fail",
                    reasonCode: uploadResponse.error ?? "recording_upload_failed",
                    httpPath: path,
                    httpStatus: statusCode,
                    macReceiveState: uploadResponse.receiveStatus,
                    safeErrorMessage: uploadResponse.error
                )
                throw SecureMacUploadError.serverRejected(uploadResponse.error ?? "recording_upload_failed")
            }

            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestCompleted",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "success",
                reasonCode: uploadResponse.disposition,
                httpPath: path,
                httpStatus: statusCode,
                macReceiveState: uploadResponse.receiveStatus
            )
            return uploadResponse
        } catch {
            if let pinningError = pinnedSession.context.currentPinningError {
                throw pinningError
            }
            print("[RokuricsRecordingUpload] errors: \(error.localizedDescription)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestFailed",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "network_or_decode_error",
                httpPath: path,
                errorDomain: "SecureMacUploadClient",
                safeErrorMessage: error.localizedDescription
            )
            throw error
        }
    }

    private func canonicalUploadChecksum(
        fileURL: URL,
        uploadType: String,
        recordingID: String,
        fileName: String,
        httpPath: String
    ) async throws -> String {
        let safeUploadType = uploadType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "upload" : uploadType
        let safeRecordingID = recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown-recording" : recordingID
        let safeFileName = fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fileURL.lastPathComponent : fileName
        let result = await canonicalChecksumRuntime.checksum(
            fileURL: fileURL,
            logicalToken: "\(safeUploadType)-\(safeRecordingID)-\(safeFileName)",
            nodeRole: .iPhone,
            cacheDirectoryURL: canonicalChecksumCacheDirectoryURL ?? Self.defaultCanonicalChecksumCacheDirectoryURL()
        )
        if let checksum = result.sha256 {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureUploadFileChecksumResolved",
                recordingID: recordingID,
                eventResult: result.hashComputed ? "computed" : "cacheHit",
                reasonCode: result.event.rawValue,
                httpPath: httpPath,
                fileSize: result.byteSize,
                safeErrorMessage: "hashDurationMs=\(result.hashDurationMs);cachePersisted=\(result.cachePersisted)"
            )
            return checksum
        }
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureUploadFileChecksumResolved",
            recordingID: recordingID,
            eventResult: "fail",
            reasonCode: result.failure.map(String.init(describing:)) ?? "checksum_unavailable",
            httpPath: httpPath,
            fileSize: result.byteSize,
            safeErrorMessage: "hashDurationMs=\(result.hashDurationMs);cacheState=\(result.event.rawValue)"
        )
        throw SecureMacUploadError.invalidResponse
    }

    private static func defaultCanonicalChecksumCacheDirectoryURL() -> URL {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
            .standardizedFileURL
    }

    func uploadSignedFile(
        settings: SecureMacConnectionSnapshot,
        path: String,
        fileURL: URL,
        contentType: String,
        uploadType: String,
        recordingID: String,
        fileName: String,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> SecureUploadServerResponse {
        guard settings.isPaired else {
            throw SecureMacUploadError.notPaired
        }

        let expectedFingerprint = try normalizedExpectedFingerprint(settings.macFingerprint)
        let url = try secureURL(host: settings.macHost, port: settings.macPort, path: path)
        let now = Date()
        let bodySHA256 = try await canonicalUploadChecksum(
            fileURL: fileURL,
            uploadType: uploadType,
            recordingID: recordingID,
            fileName: fileName,
            httpPath: path
        )
        let traceID = UploadFlightRecorder.currentTraceID
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.int64Value ?? -1
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureUploadClientEntered",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "begin",
            httpPath: path,
            fileExists: FileManager.default.fileExists(atPath: fileURL.path),
            fileSize: fileSize
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureConnectionSettingsLoaded",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestBodyHashComputed",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path,
            fileSize: fileSize
        )
        let timestamp = String(format: "%.0f", now.timeIntervalSince1970)
        let nonce = SecureUploadUtilities.randomBase64URLToken()
        let signaturePayload = [
            "POST",
            path,
            timestamp,
            nonce,
            bodySHA256
        ].joined(separator: "\n")

        guard let signature = SecureUploadUtilities.hmacSHA256Base64URL(
            message: signaturePayload,
            secretBase64URL: settings.sharedSecretBase64URL
        ) else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureCredentialMissing",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "invalid_secret",
                httpPath: path
            )
            throw SecureMacUploadError.invalidSecret
        }
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureCredentialLoaded",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestSigned",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path
        )

        let pinnedSession = makePinnedSession(
            expectedFingerprint: expectedFingerprint,
            diagnostics: nil,
            traceID: traceID,
            recordingID: recordingID,
            httpPath: path,
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout
        )
        defer {
            pinnedSession.session.invalidateAndCancel()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(settings.deviceID, forHTTPHeaderField: "X-Rokurics-Device-ID")
        request.setValue(timestamp, forHTTPHeaderField: "X-Rokurics-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-Rokurics-Nonce")
        request.setValue(bodySHA256, forHTTPHeaderField: "X-Rokurics-Body-SHA256")
        request.setValue(signature, forHTTPHeaderField: "X-Rokurics-Signature")
        request.setValue(recordingID, forHTTPHeaderField: "X-Rokurics-Recording-ID")
        request.setValue(fileName, forHTTPHeaderField: "X-Rokurics-Filename")
        request.setValue(uploadType, forHTTPHeaderField: "X-Rokurics-Upload-Type")
        if let traceID {
            request.setValue(traceID, forHTTPHeaderField: UploadFlightRecorder.traceHeaderName)
        }
        DevelopmentDiagnostics.requestHeaderFields().forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestBuilt",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: path,
            fileSize: fileSize
        )

        print("[RokuricsRecordingUpload] target URL: \(url.absoluteString)")
        print("[RokuricsRecordingUpload] uploadType=\(uploadType), fileSize=\(fileSize), recordingIDPrefix=\(String(recordingID.prefix(12)))")

        do {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestStarted",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "begin",
                httpPath: path,
                fileSize: fileSize
            )
            let (data, response) = try await pinnedSession.session.upload(for: request, fromFile: fileURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestResponseReceived",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: (200..<300).contains(statusCode) ? "success" : "fail",
                httpPath: path,
                httpStatus: statusCode,
                bodyBytes: data.count
            )
            print("[RokuricsRecordingUpload] response status code: \(statusCode)")
            print("[RokuricsRecordingUpload] response body: \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")

            let uploadResponse = try JSONDecoder().decode(SecureUploadServerResponse.self, from: data)
            guard uploadResponse.ok else {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "secureRequestFailed",
                    traceID: traceID,
                    recordingID: recordingID,
                    eventResult: "fail",
                    reasonCode: uploadResponse.error ?? "recording_upload_failed",
                    httpPath: path,
                    httpStatus: statusCode,
                    macReceiveState: uploadResponse.receiveStatus,
                    safeErrorMessage: uploadResponse.error
                )
                throw SecureMacUploadError.serverRejected(uploadResponse.error ?? "recording_upload_failed")
            }

            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestCompleted",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "success",
                reasonCode: uploadResponse.disposition,
                httpPath: path,
                httpStatus: statusCode,
                macReceiveState: uploadResponse.receiveStatus
            )
            return uploadResponse
        } catch {
            if let pinningError = pinnedSession.context.currentPinningError {
                throw pinningError
            }
            print("[RokuricsRecordingUpload] errors: \(error.localizedDescription)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestFailed",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "network_or_decode_error",
                httpPath: path,
                errorDomain: "SecureMacUploadClient",
                safeErrorMessage: error.localizedDescription
            )
            throw error
        }
    }

    func startResumableAudioUpload(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadStartRequest
    ) async throws -> ResumableAudioUploadSessionResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/upload-recording-audio-session/start",
            body: request,
            requestTimeout: 15,
            resourceTimeout: 30
        )
    }

    func fetchResumableAudioUploadStatus(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadStatusRequest
    ) async throws -> ResumableAudioUploadSessionResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/upload-recording-audio-session/status",
            body: request,
            requestTimeout: 10,
            resourceTimeout: 20
        )
    }

    func uploadResumableAudioChunk(
        settings: SecureMacConnectionSnapshot,
        recordingID: String,
        sessionID: String,
        offset: Int64,
        totalSHA256: String,
        chunk: Data
    ) async throws -> ResumableAudioUploadSessionResponse {
        guard settings.isPaired else {
            throw SecureMacUploadError.notPaired
        }

        let path = "/upload-recording-audio-session/chunk"
        let expectedFingerprint = try normalizedExpectedFingerprint(settings.macFingerprint)
        let url = try secureURL(host: settings.macHost, port: settings.macPort, path: path)
        let now = Date()
        let bodySHA256 = SecureUploadUtilities.sha256Hex(chunk)
        let traceID = UploadFlightRecorder.currentTraceID
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureUploadClientEntered",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "begin",
            sessionID: sessionID,
            httpPath: path,
            bodyBytes: chunk.count,
            chunkOffset: offset,
            chunkLength: chunk.count
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestBodyHashComputed",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            sessionID: sessionID,
            httpPath: path,
            bodyBytes: chunk.count,
            chunkOffset: offset,
            chunkLength: chunk.count
        )
        let timestamp = String(format: "%.0f", now.timeIntervalSince1970)
        let nonce = SecureUploadUtilities.randomBase64URLToken()
        let signaturePayload = [
            "POST",
            path,
            timestamp,
            nonce,
            bodySHA256
        ].joined(separator: "\n")

        guard let signature = SecureUploadUtilities.hmacSHA256Base64URL(
            message: signaturePayload,
            secretBase64URL: settings.sharedSecretBase64URL
        ) else {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureCredentialMissing",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "invalid_secret",
                sessionID: sessionID,
                httpPath: path
            )
            throw SecureMacUploadError.invalidSecret
        }
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureCredentialLoaded",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            sessionID: sessionID,
            httpPath: path
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestSigned",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            sessionID: sessionID,
            httpPath: path
        )

        let pinnedSession = makePinnedSession(
            expectedFingerprint: expectedFingerprint,
            diagnostics: nil,
            traceID: traceID,
            recordingID: recordingID,
            httpPath: path,
            requestTimeout: 30,
            resourceTimeout: 60
        )
        defer {
            pinnedSession.session.invalidateAndCancel()
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.deviceID, forHTTPHeaderField: "X-Rokurics-Device-ID")
        request.setValue(timestamp, forHTTPHeaderField: "X-Rokurics-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-Rokurics-Nonce")
        request.setValue(bodySHA256, forHTTPHeaderField: "X-Rokurics-Body-SHA256")
        request.setValue(signature, forHTTPHeaderField: "X-Rokurics-Signature")
        request.setValue(recordingID, forHTTPHeaderField: "X-Rokurics-Recording-ID")
        request.setValue("audio.m4a.part", forHTTPHeaderField: "X-Rokurics-Filename")
        request.setValue("recording-audio-chunk", forHTTPHeaderField: "X-Rokurics-Upload-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Rokurics-Session-ID")
        request.setValue(String(offset), forHTTPHeaderField: "X-Rokurics-Chunk-Offset")
        request.setValue(String(chunk.count), forHTTPHeaderField: "X-Rokurics-Chunk-Length")
        request.setValue(bodySHA256, forHTTPHeaderField: "X-Rokurics-Chunk-SHA256")
        request.setValue(totalSHA256, forHTTPHeaderField: "X-Rokurics-Total-SHA256")
        if let traceID {
            request.setValue(traceID, forHTTPHeaderField: UploadFlightRecorder.traceHeaderName)
        }
        DevelopmentDiagnostics.requestHeaderFields().forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestBuilt",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            sessionID: sessionID,
            httpPath: path,
            bodyBytes: chunk.count,
            chunkOffset: offset,
            chunkLength: chunk.count
        )

        print("[RokuricsRecordingUpload] POST \(path), chunkSize=\(chunk.count), offset=\(offset), recordingIDPrefix=\(String(recordingID.prefix(12)))")

        do {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestStarted",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "begin",
                sessionID: sessionID,
                httpPath: path,
                bodyBytes: chunk.count,
                chunkOffset: offset,
                chunkLength: chunk.count
            )
            let (data, response) = try await pinnedSession.session.upload(for: request, from: chunk)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[RokuricsRecordingUpload] chunk response status code: \(statusCode)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestResponseReceived",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: (200..<300).contains(statusCode) ? "success" : "fail",
                sessionID: sessionID,
                httpPath: path,
                httpStatus: statusCode,
                bodyBytes: data.count,
                chunkOffset: offset,
                chunkLength: chunk.count
            )

            guard (200..<300).contains(statusCode) else {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "secureRequestFailed",
                    traceID: traceID,
                    recordingID: recordingID,
                    eventResult: "fail",
                    reasonCode: Self.serverErrorMessage(from: data) ?? "resumable_chunk_failed",
                    sessionID: sessionID,
                    httpPath: path,
                    httpStatus: statusCode,
                    chunkOffset: offset,
                    chunkLength: chunk.count
                )
                throw SecureMacUploadError.serverRejected(Self.serverErrorMessage(from: data) ?? "resumable_chunk_failed")
            }

            do {
                let uploadResponse = try Self.jsonDecoder.decode(ResumableAudioUploadSessionResponse.self, from: data)
                guard uploadResponse.ok else {
                    UploadFlightRecorder.record(
                        side: .iPhone,
                        stage: "secureRequestFailed",
                        traceID: traceID,
                        recordingID: recordingID,
                        eventResult: "fail",
                        reasonCode: uploadResponse.error ?? "resumable_chunk_failed",
                        sessionID: sessionID,
                        httpPath: path,
                        httpStatus: statusCode,
                        chunkOffset: offset,
                        chunkLength: chunk.count,
                        safeErrorMessage: uploadResponse.error
                    )
                    throw SecureMacUploadError.serverRejected(uploadResponse.error ?? "resumable_chunk_failed")
                }
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "secureRequestCompleted",
                    traceID: traceID,
                    recordingID: recordingID,
                    eventResult: "success",
                    reasonCode: uploadResponse.disposition,
                    sessionID: sessionID,
                    httpPath: path,
                    httpStatus: statusCode,
                    chunkOffset: offset,
                    chunkLength: chunk.count,
                    confirmedBytes: uploadResponse.confirmedBytes,
                    totalBytes: uploadResponse.fileSize
                )
                return uploadResponse
            } catch let error as SecureMacUploadError {
                throw error
            } catch {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "secureRequestFailed",
                    traceID: traceID,
                    recordingID: recordingID,
                    eventResult: "fail",
                    reasonCode: "invalid_response",
                    sessionID: sessionID,
                    httpPath: path,
                    httpStatus: statusCode,
                    safeErrorMessage: error.localizedDescription
                )
                throw SecureMacUploadError.invalidResponse
            }
        } catch {
            if let pinningError = pinnedSession.context.currentPinningError {
                throw pinningError
            }
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestFailed",
                traceID: traceID,
                recordingID: recordingID,
                eventResult: "fail",
                reasonCode: "network_or_decode_error",
                sessionID: sessionID,
                httpPath: path,
                errorDomain: "SecureMacUploadClient",
                safeErrorMessage: error.localizedDescription
            )
            throw error
        }
    }

    func finalizeResumableAudioUpload(
        settings: SecureMacConnectionSnapshot,
        request: ResumableAudioUploadFinalizeRequest
    ) async throws -> ResumableAudioUploadSessionResponse {
        try await postSignedJSON(
            settings: settings,
            path: "/upload-recording-audio-session/finalize",
            body: request,
            requestTimeout: 15,
            resourceTimeout: 60
        )
    }

    private struct PinnedSession {
        let session: URLSession
        let context: PinnedRequestContext
        let delegate: PinnedURLSessionDelegate
    }

    private struct SyncEmptyRequest: Encodable {}

    func prepareSignedJSONRequest<Body: Encodable>(
        settings: SecureMacConnectionSnapshot,
        path: String,
        body: Body,
        now: Date = Date(),
        additionalHeaders: [String: String] = [:]
    ) throws -> SecureUploadPreparedRequest {
        guard settings.isPaired else {
            throw SecureMacUploadError.notPaired
        }

        let url = try secureURL(host: settings.macHost, port: settings.macPort, path: path)
        let bodyData = try Self.jsonEncoder.encode(body)
        let bodySHA256 = SecureUploadUtilities.sha256Hex(bodyData)
        let timestamp = String(format: "%.0f", now.timeIntervalSince1970)
        let nonce = SecureUploadUtilities.randomBase64URLToken()
        let signaturePayload = [
            "POST",
            path,
            timestamp,
            nonce,
            bodySHA256
        ].joined(separator: "\n")

        guard let signature = SecureUploadUtilities.hmacSHA256Base64URL(
            message: signaturePayload,
            secretBase64URL: settings.sharedSecretBase64URL
        ) else {
            throw SecureMacUploadError.invalidSecret
        }

        var headers = [
            "Content-Type": "application/json",
            "X-Rokurics-Device-ID": settings.deviceID,
            "X-Rokurics-Timestamp": timestamp,
            "X-Rokurics-Nonce": nonce,
            "X-Rokurics-Body-SHA256": bodySHA256,
            "X-Rokurics-Signature": signature
        ]
        additionalHeaders.forEach { key, value in
            headers[key] = value
        }
        var tracedHeaders = headers
        DevelopmentDiagnostics.requestHeaderFields().forEach { key, value in
            tracedHeaders[key] = value
        }
        if let traceID = UploadFlightRecorder.currentTraceID {
            tracedHeaders[UploadFlightRecorder.traceHeaderName] = traceID
        }

        return SecureUploadPreparedRequest(url: url, body: bodyData, headers: tracedHeaders)
    }

    func prepareCanonicalLiveReadOnlyProbeRequest<Body: Encodable>(
        settings: SecureMacConnectionSnapshot,
        policy: CanonicalLiveReadOnlyTransportProbePolicy,
        body: Body,
        syncRunID: String?,
        now: Date = Date()
    ) throws -> SecureUploadPreparedRequest {
        guard policy.route.method == "POST" else {
            throw SecureMacUploadError.serverRejected("read_only_probe_requires_signed_post_route")
        }
        return try prepareSignedJSONRequest(
            settings: settings,
            path: policy.route.path,
            body: body,
            now: now,
            additionalHeaders: CanonicalLiveReadOnlyTransportProbeHTTP.markerHeaders(
                mode: policy.mode,
                route: policy.route,
                syncRunID: syncRunID
            )
        )
    }

    func sendCanonicalLiveReadOnlyProbe(
        settings: SecureMacConnectionSnapshot,
        preparedRequest: SecureUploadPreparedRequest,
        route: CanonicalLiveReadOnlyTransportProbeRoute,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> SecureUploadRawResponse {
        let expectedFingerprint = try normalizedExpectedFingerprint(settings.macFingerprint)
        let pinnedSession = makePinnedSession(
            expectedFingerprint: expectedFingerprint,
            diagnostics: nil,
            traceID: UploadFlightRecorder.currentTraceID,
            recordingID: nil,
            httpPath: route.path,
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout
        )
        defer {
            pinnedSession.session.invalidateAndCancel()
        }

        var request = URLRequest(url: preparedRequest.url)
        request.httpMethod = route.method
        preparedRequest.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await pinnedSession.session.upload(for: request, from: preparedRequest.body)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(statusCode) else {
                throw SecureMacUploadError.serverRejected(Self.serverErrorMessage(from: data) ?? "read_only_probe_failed")
            }
            return SecureUploadRawResponse(statusCode: statusCode, responseByteCount: data.count)
        } catch {
            if let pinningError = pinnedSession.context.currentPinningError {
                throw pinningError
            }
            throw error
        }
    }

    private func postSignedJSON<Body: Encodable, Response: Decodable>(
        settings: SecureMacConnectionSnapshot,
        path: String,
        body: Body,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) async throws -> Response {
        let expectedFingerprint = try normalizedExpectedFingerprint(settings.macFingerprint)
        let preparedRequest = try prepareSignedJSONRequest(settings: settings, path: path, body: body)
        let traceID = UploadFlightRecorder.currentTraceID
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureUploadClientEntered",
            traceID: traceID,
            eventResult: "begin",
            httpPath: path,
            bodyBytes: preparedRequest.body.count
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureConnectionSettingsLoaded",
            traceID: traceID,
            eventResult: "success",
            httpPath: path
        )
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: "secureRequestBuilt",
            traceID: traceID,
            eventResult: "success",
            httpPath: path,
            bodyBytes: preparedRequest.body.count
        )
        let pinnedSession = makePinnedSession(
            expectedFingerprint: expectedFingerprint,
            diagnostics: nil,
            traceID: traceID,
            recordingID: nil,
            httpPath: path,
            requestTimeout: requestTimeout,
            resourceTimeout: resourceTimeout
        )
        defer {
            pinnedSession.session.invalidateAndCancel()
        }

        var request = URLRequest(url: preparedRequest.url)
        request.httpMethod = "POST"
        preparedRequest.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        print("[RokuricsSync] POST \(path), bodySize=\(preparedRequest.body.count), deviceIDPrefix=\(String(settings.deviceID.prefix(12)))")

        do {
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestStarted",
                traceID: traceID,
                eventResult: "begin",
                httpPath: path,
                bodyBytes: preparedRequest.body.count
            )
            let (data, response) = try await pinnedSession.session.upload(for: request, from: preparedRequest.body)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[RokuricsSync] response status code: \(statusCode)")
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestResponseReceived",
                traceID: traceID,
                eventResult: (200..<300).contains(statusCode) ? "success" : "fail",
                httpPath: path,
                httpStatus: statusCode,
                bodyBytes: data.count
            )

            guard (200..<300).contains(statusCode) else {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "secureRequestFailed",
                    traceID: traceID,
                    eventResult: "fail",
                    reasonCode: Self.serverErrorMessage(from: data) ?? "signed_json_request_failed",
                    httpPath: path,
                    httpStatus: statusCode
                )
                throw SecureMacUploadError.serverRejected(Self.serverErrorMessage(from: data) ?? "sync_request_failed")
            }

            do {
                let decoded = try Self.jsonDecoder.decode(Response.self, from: data)
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "secureRequestCompleted",
                    traceID: traceID,
                    eventResult: "success",
                    httpPath: path,
                    httpStatus: statusCode
                )
                return decoded
            } catch {
                UploadFlightRecorder.record(
                    side: .iPhone,
                    stage: "secureRequestFailed",
                    traceID: traceID,
                    eventResult: "fail",
                    reasonCode: "invalid_response",
                    httpPath: path,
                    httpStatus: statusCode,
                    safeErrorMessage: error.localizedDescription
                )
                throw SecureMacUploadError.invalidResponse
            }
        } catch {
            if let pinningError = pinnedSession.context.currentPinningError {
                throw pinningError
            }
            UploadFlightRecorder.record(
                side: .iPhone,
                stage: "secureRequestFailed",
                traceID: traceID,
                eventResult: "fail",
                reasonCode: "network_or_decode_error",
                httpPath: path,
                errorDomain: "SecureMacUploadClient",
                safeErrorMessage: error.localizedDescription
            )
            throw error
        }
    }

    private func makePinnedSession(
        expectedFingerprint: String,
        diagnostics: ((String) -> Void)?,
        traceID: String? = nil,
        recordingID: String? = nil,
        httpPath: String? = nil,
        requestTimeout: TimeInterval = 10,
        resourceTimeout: TimeInterval = 15
    ) -> PinnedSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = false

        let context = PinnedRequestContext(
            expectedFingerprint: expectedFingerprint,
            diagnostics: diagnostics,
            traceID: traceID,
            recordingID: recordingID,
            httpPath: httpPath
        )
        let delegate = PinnedURLSessionDelegate(context: context)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        return PinnedSession(session: session, context: context, delegate: delegate)
    }

    private func secureURL(host: String, port: Int, path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port
        components.path = path

        guard let url = components.url else {
            throw SecureMacUploadError.invalidURL
        }

        return url
    }

    private func normalizedExpectedFingerprint(_ fingerprint: String) throws -> String {
        let normalized = SecureUploadUtilities.normalizedCertificateFingerprint(fingerprint)
        guard normalized.count == 64 else {
            throw SecureMacUploadError.invalidFingerprint
        }
        return normalized
    }

    private static func secureTestFileName(createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return "rokurics_secure_test_\(formatter.string(from: createdAt)).json"
    }

    private static func serverErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["error"] as? String
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func mapHealthCheckError(_ error: Error, context: PinnedRequestContext) -> Error {
        if let secureError = error as? SecureMacUploadError {
            return secureError
        }

        guard let urlError = error as? URLError else {
            return error
        }

        switch urlError.code {
        case .timedOut where !context.didReceiveTLSChallenge:
            return SecureMacUploadError.httpsUnavailable("连接超时，未收到 TLS challenge。")
        case .timedOut:
            return SecureMacUploadError.httpsUnavailable("连接超时。")
        case .cannotConnectToHost:
            return SecureMacUploadError.httpsUnavailable("连接被拒绝或 Mac 未监听该地址。")
        case .notConnectedToInternet, .networkConnectionLost:
            return SecureMacUploadError.httpsUnavailable("网络连接中断。")
        default:
            return urlError
        }
    }
}

private final class PinnedRequestContext {
    private let lock = NSLock()
    private let expectedFingerprint: String
    private let diagnosticHandler: ((String) -> Void)?
    private let traceID: String?
    private let recordingID: String?
    private let httpPath: String?
    private var pinningError: SecureMacUploadError?
    private var receivedServerTrustChallenge = false

    init(
        expectedFingerprint: String,
        diagnostics: ((String) -> Void)?,
        traceID: String?,
        recordingID: String?,
        httpPath: String?
    ) {
        self.expectedFingerprint = expectedFingerprint
        self.diagnosticHandler = diagnostics
        self.traceID = traceID
        self.recordingID = recordingID
        self.httpPath = httpPath
    }

    var currentExpectedFingerprint: String {
        lock.lock()
        defer { lock.unlock() }
        return expectedFingerprint
    }

    var currentPinningError: SecureMacUploadError? {
        lock.lock()
        defer { lock.unlock() }
        return pinningError
    }

    var didReceiveTLSChallenge: Bool {
        lock.lock()
        defer { lock.unlock() }
        return receivedServerTrustChallenge
    }

    func markServerTrustChallengeReceived() {
        lock.lock()
        receivedServerTrustChallenge = true
        lock.unlock()
    }

    func setPinningError(_ error: SecureMacUploadError) {
        lock.lock()
        pinningError = error
        lock.unlock()
    }

    func emitDiagnosticStep(_ step: String) {
        lock.lock()
        let handler = diagnosticHandler
        lock.unlock()
        handler?(step)
    }

    func recordPinning(stage: String, eventResult: String, reasonCode: String? = nil) {
        UploadFlightRecorder.record(
            side: .iPhone,
            stage: stage,
            traceID: traceID,
            recordingID: recordingID,
            eventResult: eventResult,
            reasonCode: reasonCode,
            httpPath: httpPath
        )
    }
}

private final class PinnedURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let context: PinnedRequestContext

    init(context: PinnedRequestContext) {
        self.context = context
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
        print("[RokuricsPinning] challenge received")
        print("[RokuricsPinning] authentication method: \(challenge.protectionSpace.authenticationMethod)")
        print("[RokuricsPinning] serverTrust exists: \(challenge.protectionSpace.serverTrust != nil)")
        context.recordPinning(stage: "secureRequestTLSChallengeReceived", eventResult: "begin")

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            print("[RokuricsPinning] completionHandler default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        context.markServerTrustChallengeReceived()
        context.emitDiagnosticStep("已收到 TLS challenge")

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            context.setPinningError(.fingerprintMismatch)
            print("[RokuricsPinning] fingerprint mismatch: no_server_trust")
            print("[RokuricsPinning] completionHandler cancel")
            context.emitDiagnosticStep("失败：未收到 serverTrust")
            context.recordPinning(stage: "secureRequestPinningRejected", eventResult: "fail", reasonCode: "no_server_trust")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certificateChain = (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate]) ?? []
        print("[RokuricsPinning] certificate count: \(certificateChain.count)")

        guard let certificate = certificateChain.first else {
            context.setPinningError(.fingerprintMismatch)
            print("[RokuricsPinning] fingerprint mismatch: no_server_certificate")
            print("[RokuricsPinning] completionHandler cancel")
            context.emitDiagnosticStep("失败：未收到服务器证书")
            context.recordPinning(stage: "secureRequestPinningRejected", eventResult: "fail", reasonCode: "no_server_certificate")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certificateData = SecCertificateCopyData(certificate) as Data
        let calculatedFingerprint = SecureUploadUtilities.normalizedCertificateFingerprint(
            SecureUploadUtilities.sha256Hex(certificateData)
        )
        let expectedFingerprint = context.currentExpectedFingerprint
        context.emitDiagnosticStep("已计算证书指纹")
        print("[RokuricsPinning] calculated fingerprint prefix/suffix: \(calculatedFingerprint.shortFingerprintForLog)")
        print("[RokuricsPinning] expected fingerprint prefix/suffix: \(expectedFingerprint.shortFingerprintForLog)")
        print("[RokuricsPinning] normalized calculated length: \(calculatedFingerprint.count)")
        print("[RokuricsPinning] normalized expected length: \(expectedFingerprint.count)")

        guard calculatedFingerprint == expectedFingerprint else {
            context.setPinningError(.fingerprintMismatch)
            print("[RokuricsPinning] fingerprint mismatch")
            print("[RokuricsPinning] completionHandler cancel")
            context.emitDiagnosticStep("指纹不匹配")
            context.recordPinning(stage: "secureRequestPinningRejected", eventResult: "fail", reasonCode: "fingerprint_mismatch")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        print("[RokuricsPinning] fingerprint match")
        print("[RokuricsPinning] completionHandler useCredential")
        context.emitDiagnosticStep("指纹匹配")
        context.recordPinning(stage: "secureRequestPinningAccepted", eventResult: "success")
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

private extension String {
    var shortFingerprintForLog: String {
        "\(String(prefix(12)))...\(String(suffix(12)))"
    }
}
