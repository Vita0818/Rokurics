//
//  SecureLocalHTTPSServer.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import Network

enum SecureHTTPSServerError: LocalizedError {
    case tlsIdentityUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .tlsIdentityUnavailable(let reason):
            return reason
        }
    }
}

final class SecureLocalHTTPSServer {
    typealias ReadyHandler = @Sendable () -> Void
    typealias FailedHandler = @Sendable (String) -> Void
    typealias PairingChangedHandler = @Sendable () -> Void
    typealias UploadAcceptedHandler = @Sendable (String) -> Void

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private enum ParseResult {
        case complete(HTTPRequest)
        case incomplete
        case invalid(String)
    }

    private struct PairRequest: Decodable {
        let pairingCode: String
        let deviceName: String
        let deviceType: String
    }

    private struct PairSuccessResponse: Encodable {
        let ok: Bool
        let deviceID: String
        let sharedSecret: String
        let pairedAt: String
    }

    private struct HealthResponse: Encodable {
        let ok: Bool
        let service: String
        let https: Bool
    }

    private struct FingerprintResponse: Encodable {
        let ok: Bool
        let fingerprint: String
        let type: String
    }

    private struct ErrorResponse: Encodable {
        let ok: Bool
        let error: String
    }

    private struct UploadSuccessResponse: Encodable {
        let ok: Bool
        let message: String
        let fileName: String
    }

    private let port: Int
    private let identityManager: MacIdentityManager
    private let pairingManager: PairingManager
    private let requestVerifier: RequestVerifier
    private let receivedFileStore: ReceivedFileStore
    private let onReady: ReadyHandler
    private let onFailed: FailedHandler
    private let onPairingChanged: PairingChangedHandler
    private let onUploadAccepted: UploadAcceptedHandler
    private let queue = DispatchQueue(label: "RokuricsMac.SecureLocalHTTPSServer")
    private let maxHeaderBytes = 16 * 1024
    private let maxBodyBytes = 1 * 1024 * 1024
    private var listener: NWListener?
    private var activeConnections: [UUID: NWConnection] = [:]

    init(
        port: Int,
        identityManager: MacIdentityManager,
        pairingManager: PairingManager,
        requestVerifier: RequestVerifier,
        receivedFileStore: ReceivedFileStore,
        onReady: @escaping ReadyHandler,
        onFailed: @escaping FailedHandler,
        onPairingChanged: @escaping PairingChangedHandler,
        onUploadAccepted: @escaping UploadAcceptedHandler
    ) {
        self.port = port
        self.identityManager = identityManager
        self.pairingManager = pairingManager
        self.requestVerifier = requestVerifier
        self.receivedFileStore = receivedFileStore
        self.onReady = onReady
        self.onFailed = onFailed
        self.onPairingChanged = onPairingChanged
        self.onUploadAccepted = onUploadAccepted
    }

    func start() throws {
        print("[RokuricsHTTPS] HTTPS listener starting")

        guard identityManager.status.hasTLSIdentity, let tlsOptions = identityManager.tlsOptions() else {
            let reason = identityManager.status.tlsBlocker ?? "TLS identity unavailable."
            print("[RokuricsHTTPS] rejected reason: \(reason)")
            throw SecureHTTPSServerError.tlsIdentityUnavailable(reason)
        }

        print("[RokuricsHTTPS] creating minimal TLS parameters")
        let tcpOptions = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        print("[RokuricsHTTPS] allowLocalEndpointReuse: false")
        print("[RokuricsHTTPS] requiredLocalEndpoint: nil")
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw SecureHTTPSServerError.tlsIdentityUnavailable("Invalid HTTPS port.")
        }

        print("[RokuricsHTTPS] listener starting on port \(port)")
        listener = try NWListener(using: parameters, on: endpointPort)
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else {
                return
            }

            switch state {
            case .ready:
                print("[RokuricsHTTPS] listener state: ready")
                self.onReady()
            case .failed(let error):
                let message = "HTTPS listener failed: \(error)"
                print("[RokuricsHTTPS][ERROR] \(message)")
                self.onFailed(message)
            case .cancelled:
                print("[RokuricsHTTPS] listener state: cancelled")
            default:
                print("[RokuricsHTTPS] listener state: \(state)")
            }
        }
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        activeConnections.values.forEach { $0.cancel() }
        activeConnections.removeAll()
        print("[RokuricsHTTPS] secure server stopped")
    }

    private func handleConnection(_ connection: NWConnection) {
        let connectionID = UUID()
        activeConnections[connectionID] = connection
        print("[RokuricsHTTPS] incoming connection received from \(connection.endpoint)")

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self else {
                return
            }

            print("[RokuricsHTTPS] connection state: \(state)")

            switch state {
            case .ready:
                guard let connection else {
                    self.activeConnections.removeValue(forKey: connectionID)
                    return
                }
                self.receiveRequest(on: connection, buffer: Data())
            case .failed(let error):
                print("[RokuricsHTTPS][ERROR] connection failed: \(error)")
                self.activeConnections.removeValue(forKey: connectionID)
                connection?.cancel()
            case .cancelled:
                self.activeConnections.removeValue(forKey: connectionID)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                print("[RokuricsHTTPS] request receive failed: \(error)")
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let chunk {
                nextBuffer.append(chunk)
            }

            if nextBuffer.count > self.maxHeaderBytes + self.maxBodyBytes {
                self.sendError(statusCode: 413, reason: "Payload Too Large", error: "body_too_large", on: connection)
                return
            }

            switch self.parseRequest(from: nextBuffer) {
            case .complete(let request):
                self.handleRequest(request, on: connection)
            case .invalid(let reason):
                self.sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
            case .incomplete:
                if isComplete {
                    self.sendError(statusCode: 400, reason: "Bad Request", error: "bad_request", on: connection)
                } else {
                    self.receiveRequest(on: connection, buffer: nextBuffer)
                }
            }
        }
    }

    private func parseRequest(from buffer: Data) -> ParseResult {
        let headerSeparator = Data([13, 10, 13, 10])
        guard let headerRange = buffer.range(of: headerSeparator) else {
            if buffer.count > maxHeaderBytes {
                return .invalid("headers_too_large")
            }
            return .incomplete
        }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .invalid("bad_headers")
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return .invalid("bad_request")
        }
        print("[RokuricsHTTPS] request line: \(requestLine)")

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            return .invalid("bad_request")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else {
                continue
            }
            headers[parts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let normalizedHeaders = Self.normalizedHeaders(headers)
        let contentLengthText = normalizedHeaders["content-length"] ?? "0"
        guard let contentLength = Int(contentLengthText), contentLength >= 0 else {
            return .invalid("bad_content_length")
        }

        guard contentLength <= maxBodyBytes else {
            return .invalid("body_too_large")
        }

        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + contentLength
        guard buffer.count >= bodyEnd else {
            return .incomplete
        }

        let rawPath = requestParts[1]
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        print("[RokuricsHTTPS] request path: \(path)")

        return .complete(HTTPRequest(
            method: requestParts[0],
            path: path,
            headers: headers,
            body: Data(buffer[bodyStart..<bodyEnd])
        ))
    }

    private func handleRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            sendJSON(
                statusCode: 200,
                reason: "OK",
                body: HealthResponse(ok: true, service: "Rokurics Secure Receiver", https: true),
                on: connection
            )
        case ("GET", "/fingerprint"):
            sendJSON(
                statusCode: 200,
                reason: "OK",
                body: FingerprintResponse(ok: true, fingerprint: identityManager.status.certificateFingerprint, type: "certificate-sha256"),
                on: connection
            )
        case ("POST", "/pair"):
            Task { @MainActor [weak self] in
                self?.handlePairRequest(request, on: connection)
            }
        case ("POST", "/upload-secure-test"):
            Task { @MainActor [weak self] in
                self?.handleSecureUploadRequest(request, on: connection)
            }
        default:
            if request.method != "GET" && request.method != "POST" {
                sendError(statusCode: 405, reason: "Method Not Allowed", error: "method_not_allowed", on: connection)
            } else {
                sendError(statusCode: 404, reason: "Not Found", error: "not_found", on: connection)
            }
        }
    }

    @MainActor
    private func handlePairRequest(_ request: HTTPRequest, on connection: NWConnection) {
        print("[RokuricsPairing] pairing request received")

        guard Self.normalizedHeaders(request.headers)["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            print("[RokuricsPairing] pairing failure: content_type_not_allowed")
            sendError(statusCode: 400, reason: "Bad Request", error: "bad_request", on: connection)
            return
        }

        do {
            let pairRequest = try JSONDecoder().decode(PairRequest.self, from: request.body)
            let code = pairRequest.pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let deviceName = pairRequest.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "iPhone"
                : pairRequest.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            let deviceType = pairRequest.deviceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "iPhone"
                : pairRequest.deviceType.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let result = pairingManager.completePairing(deviceName: deviceName, deviceType: deviceType, code: code) else {
                onPairingChanged()
                sendError(statusCode: 400, reason: "Bad Request", error: "invalid_pairing_code", on: connection)
                return
            }

            onPairingChanged()
            print("[RokuricsPairing] pairing success response prepared: deviceIDPrefix=\(result.device.idPrefix), tokenPrefix=\(result.device.tokenPrefix)")
            sendJSON(
                statusCode: 200,
                reason: "OK",
                body: PairSuccessResponse(
                    ok: true,
                    deviceID: result.device.id,
                    sharedSecret: result.sharedSecretBase64URL,
                    pairedAt: ISO8601DateFormatter().string(from: result.device.pairedAt)
                ),
                on: connection
            )
        } catch {
            print("[RokuricsPairing] pairing failure: bad_request")
            sendError(statusCode: 400, reason: "Bad Request", error: "bad_request", on: connection)
        }
    }

    @MainActor
    private func handleSecureUploadRequest(_ request: HTTPRequest, on connection: NWConnection) {
        print("[RokuricsSecureUpload] upload request received")

        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted:
            do {
                let filename = Self.normalizedHeaders(request.headers)["x-rokurics-filename"]
                let record = try receivedFileStore.saveTestUpload(body: request.body, requestedFileName: filename)
                onUploadAccepted(record.fileName)
                print("[RokuricsSecureUpload] upload accepted: \(record.fileName)")
                sendJSON(
                    statusCode: 200,
                    reason: "OK",
                    body: UploadSuccessResponse(ok: true, message: "secure upload received", fileName: record.fileName),
                    on: connection
                )
            } catch {
                print("[RokuricsSecureUpload] upload rejected: storage_failed")
                sendError(statusCode: 500, reason: "Internal Server Error", error: "storage_failed", on: connection)
            }
        case .rejected(let reason):
            print("[RokuricsSecureUpload] upload rejected: \(reason)")
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    private func sendError(statusCode: Int, reason: String, error: String, on connection: NWConnection) {
        sendJSON(statusCode: statusCode, reason: reason, body: ErrorResponse(ok: false, error: error), on: connection)
    }

    private func sendJSON<Response: Encodable>(statusCode: Int, reason: String, body: Response, on connection: NWConnection) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let bodyData = try encoder.encode(body)
            sendJSONData(statusCode: statusCode, reason: reason, bodyData: bodyData, on: connection)
        } catch {
            sendJSONData(
                statusCode: 500,
                reason: "Internal Server Error",
                bodyData: Data(#"{"error":"response_encoding_failed","ok":false}"#.utf8),
                on: connection
            )
        }
    }

    private func sendJSONData(statusCode: Int, reason: String, bodyData: Data, on connection: NWConnection) {
        let header = "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)

        connection.send(content: response, completion: .contentProcessed { error in
            if let error {
                print("[RokuricsHTTPS] response failed: \(error)")
            } else {
                print("[RokuricsHTTPS] response sent")
            }
            connection.cancel()
        })
    }

    private static func normalizedHeaders(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }
    }
}
