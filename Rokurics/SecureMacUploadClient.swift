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

struct SecurePairingResult {
    let deviceID: String
    let sharedSecretBase64URL: String
    let pairedAt: String

    var deviceIDPrefix: String {
        String(deviceID.prefix(12))
    }

    var secretPrefix: String {
        String(sharedSecretBase64URL.prefix(8))
    }
}

struct SecureUploadResult {
    let fileName: String
}

struct SecureHTTPSHealthCheckResult {
    let statusCode: Int
    let body: String
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
            return "请先完成安全配对。"
        case .invalidURL:
            return "Mac 地址或端口无效。"
        case .invalidSecret:
            return "配对密钥无效，请重新配对。"
        case .invalidFingerprint:
            return "请输入完整的 Mac 证书 SHA256 指纹。"
        case .fingerprintMismatch:
            return "Mac 指纹不匹配，已阻断连接。"
        case .invalidResponse:
            return "Mac 响应无法解析。"
        case .serverRejected(let reason):
            return reason
        case .httpsUnavailable(let reason):
            return reason
        }
    }
}

final class SecureMacUploadClient: NSObject, ObservableObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let isHTTPSUploadEnabled = true

    private let pinningLock = NSLock()
    private var expectedFingerprint = ""
    private var lastPinningError: SecureMacUploadError?
    private var didReceiveServerTrustChallenge = false
    private var diagnosticHandler: ((String) -> Void)?
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    private struct PairRequest: Encodable {
        let pairingCode: String
        let deviceName: String
        let deviceType: String
    }

    private struct PairResponse: Decodable {
        let ok: Bool
        let deviceID: String?
        let sharedSecret: String?
        let pairedAt: String?
        let error: String?
    }

    private struct UploadResponse: Decodable {
        let ok: Bool
        let message: String?
        let fileName: String?
        let error: String?
    }

    override init() {
        super.init()
    }

    deinit {
        session.invalidateAndCancel()
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
        print("[RokuricsHTTPSCheck] url: \(url.absoluteString)")
        preparePinning(expectedFingerprint: expectedFingerprint, diagnostics: diagnostics)
        emitDiagnosticStep("开始连接")
        emitDiagnosticStep("请求地址：\(url.absoluteString)")
        emitDiagnosticStep("等待 TLS challenge")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("close", forHTTPHeaderField: "Connection")
        emitDiagnosticStep("已发送 /health")

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let responseBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("[RokuricsHTTPSCheck] response status code: \(statusCode)")
            print("[RokuricsHTTPSCheck] response body: \(responseBody)")
            emitDiagnosticStep("收到 \(statusCode)")

            guard didReceiveTLSChallenge else {
                let reason = "未收到 TLS challenge。"
                emitDiagnosticStep(reason)
                throw SecureMacUploadError.httpsUnavailable(reason)
            }

            guard statusCode == 200 else {
                throw SecureMacUploadError.serverRejected("响应非 200：\(statusCode)")
            }

            return SecureHTTPSHealthCheckResult(statusCode: statusCode, body: responseBody)
        } catch {
            if let pinningError = currentPinningError {
                print("[RokuricsHTTPSCheck][ERROR] \(pinningError.localizedDescription)")
                emitDiagnosticStep("失败：\(pinningError.localizedDescription)")
                throw pinningError
            }

            let mappedError = mapHealthCheckError(error)
            print("[RokuricsHTTPSCheck][ERROR] \(mappedError.localizedDescription)")
            emitDiagnosticStep("失败：\(mappedError.localizedDescription)")
            throw mappedError
        }
    }

    func checkHTTPSHealth(host: String, port: Int, macFingerprint: String) async throws -> SecureHTTPSHealthCheckResult {
        try await healthCheck(host: host, port: port, macFingerprint: macFingerprint)
    }

    func pair(host: String, port: Int, pairingCode: String, macFingerprint: String) async throws -> SecurePairingResult {
        let expectedFingerprint = try normalizedExpectedFingerprint(macFingerprint)
        let url = try secureURL(host: host, port: port, path: "/pair")
        preparePinning(expectedFingerprint: expectedFingerprint, diagnostics: nil)
        let pairRequest = PairRequest(
            pairingCode: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceName: UIDevice.current.name,
            deviceType: "iPhone"
        )
        let body = try JSONEncoder().encode(pairRequest)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        print("[RokuricsPairing] target URL: \(url.absoluteString)")
        print("[RokuricsPairing] pairing payload size: \(body.count)")

        do {
            let (data, response) = try await session.upload(for: request, from: body)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[RokuricsPairing] response status code: \(statusCode)")

            let pairResponse = try JSONDecoder().decode(PairResponse.self, from: data)
            guard pairResponse.ok, let deviceID = pairResponse.deviceID, let sharedSecret = pairResponse.sharedSecret, let pairedAt = pairResponse.pairedAt else {
                throw SecureMacUploadError.serverRejected(pairResponse.error ?? "pairing_failed")
            }

            let result = SecurePairingResult(deviceID: deviceID, sharedSecretBase64URL: sharedSecret, pairedAt: pairedAt)
            print("[RokuricsPairing] pairing success: deviceIDPrefix=\(result.deviceIDPrefix), secretPrefix=\(result.secretPrefix)")
            return result
        } catch {
            if let pinningError = currentPinningError {
                throw pinningError
            }
            print("[RokuricsPairing] pairing error: \(error.localizedDescription)")
            throw error
        }
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

        let headers = [
            "Content-Type": "application/json",
            "X-Rokurics-Device-ID": settings.deviceID,
            "X-Rokurics-Timestamp": timestamp,
            "X-Rokurics-Nonce": nonce,
            "X-Rokurics-Body-SHA256": bodySHA256,
            "X-Rokurics-Signature": signature,
            "X-Rokurics-Filename": Self.secureTestFileName(createdAt: now)
        ]

        return SecureUploadPreparedRequest(url: url, body: body, headers: headers)
    }

    func uploadTestFile(settings: SecureMacConnectionSnapshot) async throws -> SecureUploadResult {
        let expectedFingerprint = try normalizedExpectedFingerprint(settings.macFingerprint)
        let preparedRequest = try prepareSignedTestUpload(settings: settings)
        preparePinning(expectedFingerprint: expectedFingerprint, diagnostics: nil)
        print("[RokuricsSecureUpload] target URL: \(preparedRequest.url.absoluteString)")
        print("[RokuricsSecureUpload] payload size: \(preparedRequest.body.count)")
        print("[RokuricsSecureUpload] request headers: \(preparedRequest.headers.keys.sorted())")

        var request = URLRequest(url: preparedRequest.url)
        request.httpMethod = "POST"
        preparedRequest.headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await session.upload(for: request, from: preparedRequest.body)
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
            if let pinningError = currentPinningError {
                throw pinningError
            }
            print("[RokuricsSecureUpload] errors: \(error.localizedDescription)")
            throw error
        }
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

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            print("[RokuricsPinning] completionHandler default handling")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        markServerTrustChallengeReceived()
        emitDiagnosticStep("已收到 TLS challenge")

        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            setPinningError(.fingerprintMismatch)
            print("[RokuricsPinning] fingerprint mismatch: no_server_trust")
            print("[RokuricsPinning] completionHandler cancel")
            emitDiagnosticStep("失败：未收到 serverTrust")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certificateChain = (SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate]) ?? []
        print("[RokuricsPinning] certificate count: \(certificateChain.count)")

        guard let certificate = certificateChain.first else {
            setPinningError(.fingerprintMismatch)
            print("[RokuricsPinning] fingerprint mismatch: no_server_certificate")
            print("[RokuricsPinning] completionHandler cancel")
            emitDiagnosticStep("失败：未收到服务器证书")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let certificateData = SecCertificateCopyData(certificate) as Data
        let calculatedFingerprint = SecureUploadUtilities.normalizedCertificateFingerprint(
            SecureUploadUtilities.sha256Hex(certificateData)
        )
        let expectedFingerprint = currentExpectedFingerprint
        emitDiagnosticStep("已计算证书指纹")
        print("[RokuricsPinning] calculated fingerprint prefix/suffix: \(calculatedFingerprint.shortFingerprintForLog)")
        print("[RokuricsPinning] expected fingerprint prefix/suffix: \(expectedFingerprint.shortFingerprintForLog)")
        print("[RokuricsPinning] normalized calculated length: \(calculatedFingerprint.count)")
        print("[RokuricsPinning] normalized expected length: \(expectedFingerprint.count)")

        guard calculatedFingerprint == expectedFingerprint else {
            setPinningError(.fingerprintMismatch)
            print("[RokuricsPinning] fingerprint mismatch")
            print("[RokuricsPinning] completionHandler cancel")
            emitDiagnosticStep("指纹不匹配")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        print("[RokuricsPinning] fingerprint match")
        print("[RokuricsPinning] completionHandler useCredential")
        emitDiagnosticStep("指纹匹配")
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
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

    private func preparePinning(expectedFingerprint: String, diagnostics: ((String) -> Void)?) {
        pinningLock.lock()
        self.expectedFingerprint = expectedFingerprint
        self.lastPinningError = nil
        self.didReceiveServerTrustChallenge = false
        self.diagnosticHandler = diagnostics
        pinningLock.unlock()
    }

    private var currentExpectedFingerprint: String {
        pinningLock.lock()
        defer { pinningLock.unlock() }
        return expectedFingerprint
    }

    private var currentPinningError: SecureMacUploadError? {
        pinningLock.lock()
        defer { pinningLock.unlock() }
        return lastPinningError
    }

    private var didReceiveTLSChallenge: Bool {
        pinningLock.lock()
        defer { pinningLock.unlock() }
        return didReceiveServerTrustChallenge
    }

    private func setPinningError(_ error: SecureMacUploadError) {
        pinningLock.lock()
        lastPinningError = error
        pinningLock.unlock()
    }

    private func markServerTrustChallengeReceived() {
        pinningLock.lock()
        didReceiveServerTrustChallenge = true
        pinningLock.unlock()
    }

    private func emitDiagnosticStep(_ step: String) {
        pinningLock.lock()
        let handler = diagnosticHandler
        pinningLock.unlock()
        handler?(step)
    }

    private func mapHealthCheckError(_ error: Error) -> Error {
        if let secureError = error as? SecureMacUploadError {
            return secureError
        }

        guard let urlError = error as? URLError else {
            return error
        }

        switch urlError.code {
        case .timedOut where !didReceiveTLSChallenge:
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

private extension String {
    var shortFingerprintForLog: String {
        "\(String(prefix(12)))...\(String(suffix(12)))"
    }
}
