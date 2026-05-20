//
//  SecureLocalHTTPSServer.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import CryptoKit
import Foundation
import Network
import SystemConfiguration

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
    typealias RecordingAcceptedHandler = @Sendable (String) -> Void

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private struct HTTPHeaderRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let bodyStart: Int
        let contentLength: Int
    }

    private enum ParseResult {
        case complete(HTTPRequest)
        case incomplete
        case invalid(String)
    }

    private enum HeaderParseResult {
        case complete(HTTPHeaderRequest)
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
        let macName: String
        let macModel: String?
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

    private struct RecordingUploadSuccessResponse: Encodable {
        let ok: Bool
        let message: String
        let recordingID: String
        let metadataFileName: String?
        let audioFileName: String?
        let receiveFileName: String
    }

    private let port: Int
    private let identityManager: MacIdentityManager
    private let pairingManager: PairingManager
    private let requestVerifier: RequestVerifier
    private let receivedFileStore: ReceivedFileStore
    private let recordingFileStore: MacRecordingFileStore
    private let onReady: ReadyHandler
    private let onFailed: FailedHandler
    private let onPairingChanged: PairingChangedHandler
    private let onUploadAccepted: UploadAcceptedHandler
    private let onRecordingAccepted: RecordingAcceptedHandler
    private let queue = DispatchQueue(label: "RokuricsMac.SecureLocalHTTPSServer")
    private let maxHeaderBytes = 16 * 1024
    private let maxAllowedBodyBytes = MacRecordingFileStore.audioMaxBytes
    private var listener: NWListener?
    private var activeConnections: [UUID: NWConnection] = [:]

    init(
        port: Int,
        identityManager: MacIdentityManager,
        pairingManager: PairingManager,
        requestVerifier: RequestVerifier,
        receivedFileStore: ReceivedFileStore,
        recordingFileStore: MacRecordingFileStore,
        onReady: @escaping ReadyHandler,
        onFailed: @escaping FailedHandler,
        onPairingChanged: @escaping PairingChangedHandler,
        onUploadAccepted: @escaping UploadAcceptedHandler,
        onRecordingAccepted: @escaping RecordingAcceptedHandler
    ) {
        self.port = port
        self.identityManager = identityManager
        self.pairingManager = pairingManager
        self.requestVerifier = requestVerifier
        self.receivedFileStore = receivedFileStore
        self.recordingFileStore = recordingFileStore
        self.onReady = onReady
        self.onFailed = onFailed
        self.onPairingChanged = onPairingChanged
        self.onUploadAccepted = onUploadAccepted
        self.onRecordingAccepted = onRecordingAccepted
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

            if nextBuffer.count > self.maxHeaderBytes + self.maxAllowedBodyBytes {
                self.sendError(statusCode: 413, reason: "Payload Too Large", error: "body_too_large", on: connection)
                return
            }

            switch self.parseHeaderRequest(from: nextBuffer) {
            case .complete(let headerRequest) where self.shouldStreamBody(for: headerRequest):
                self.startStreamingRecordingAudioBody(headerRequest, initialBuffer: nextBuffer, on: connection)
                return
            case .invalid(let reason):
                if reason == "body_too_large" {
                    self.sendError(statusCode: 413, reason: "Payload Too Large", error: reason, on: connection)
                    return
                }
                self.sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
                return
            case .complete, .incomplete:
                break
            }

            switch self.parseRequest(from: nextBuffer) {
            case .complete(let request):
                self.handleRequest(request, on: connection)
            case .invalid(let reason):
                if reason == "body_too_large" {
                    self.sendError(statusCode: 413, reason: "Payload Too Large", error: reason, on: connection)
                } else {
                    self.sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
                }
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
        switch parseHeaderRequest(from: buffer) {
        case .complete(let headerRequest):
            let bodyEnd = headerRequest.bodyStart + headerRequest.contentLength
            guard buffer.count >= bodyEnd else {
                return .incomplete
            }

            return .complete(HTTPRequest(
                method: headerRequest.method,
                path: headerRequest.path,
                headers: headerRequest.headers,
                body: Data(buffer[headerRequest.bodyStart..<bodyEnd])
            ))
        case .incomplete:
            return .incomplete
        case .invalid(let reason):
            return .invalid(reason)
        }
    }

    private func parseHeaderRequest(from buffer: Data) -> HeaderParseResult {
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

        let bodyStart = headerRange.upperBound
        let rawPath = requestParts[1]
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        print("[RokuricsHTTPS] request path: \(path)")

        guard contentLength <= bodyLimit(for: path) else {
            return .invalid("body_too_large")
        }

        return .complete(HTTPHeaderRequest(
            method: requestParts[0],
            path: path,
            headers: headers,
            bodyStart: bodyStart,
            contentLength: contentLength
        ))
    }

    private func shouldStreamBody(for request: HTTPHeaderRequest) -> Bool {
        request.method == "POST" && request.path == "/upload-recording-audio"
    }

    private func startStreamingRecordingAudioBody(_ request: HTTPHeaderRequest, initialBuffer: Data, on connection: NWConnection) {
        let headers = Self.normalizedHeaders(request.headers)
        guard let recordingID = headers["x-rokurics-recording-id"], !recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendError(statusCode: 400, reason: "Bad Request", error: "missing_recording_id", on: connection)
            return
        }

        guard request.contentLength > 0 else {
            sendError(statusCode: 400, reason: "Bad Request", error: "empty_body", on: connection)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                connection.cancel()
                return
            }

            do {
                let temporaryURL = try recordingFileStore.temporaryAudioUploadURL(recordingID: recordingID)
                let writer = try StreamingBodyWriter(fileURL: temporaryURL)
                let initialEnd = min(initialBuffer.count, request.bodyStart + request.contentLength)
                let initialBody = initialEnd > request.bodyStart ? Data(initialBuffer[request.bodyStart..<initialEnd]) : Data()
                try writer.append(initialBody)
                let remainingBytes = request.contentLength - initialBody.count
                streamRemainingRecordingAudioBody(
                    request,
                    writer: writer,
                    remainingBytes: remainingBytes,
                    on: connection
                )
            } catch let error as MacRecordingFileStoreError {
                sendError(statusCode: error.responseStatusCode, reason: error.responseReason, error: error.localizedDescription, on: connection)
            } catch {
                sendError(statusCode: 500, reason: "Internal Server Error", error: "audio_storage_failed", on: connection)
            }
        }
    }

    private func streamRemainingRecordingAudioBody(
        _ request: HTTPHeaderRequest,
        writer: StreamingBodyWriter,
        remainingBytes: Int,
        on connection: NWConnection
    ) {
        guard remainingBytes > 0 else {
            finishStreamingRecordingAudioBody(request, writer: writer, on: connection)
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: min(64 * 1024, remainingBytes)) { [weak self] chunk, _, isComplete, error in
            guard let self else {
                writer.close()
                connection.cancel()
                return
            }

            if let error {
                print("[RokuricsHTTPS] streaming audio receive failed: \(error)")
                writer.close()
                Task { @MainActor [weak self] in
                    self?.recordingFileStore.discardTemporaryUpload(at: writer.fileURL)
                }
                connection.cancel()
                return
            }

            let data = chunk ?? Data()
            do {
                try writer.append(data)
            } catch {
                writer.close()
                Task { @MainActor [weak self] in
                    self?.recordingFileStore.discardTemporaryUpload(at: writer.fileURL)
                    self?.sendError(statusCode: 500, reason: "Internal Server Error", error: "audio_storage_failed", on: connection)
                }
                return
            }

            let nextRemainingBytes = remainingBytes - data.count
            if nextRemainingBytes <= 0 {
                self.finishStreamingRecordingAudioBody(request, writer: writer, on: connection)
            } else if isComplete {
                writer.close()
                Task { @MainActor [weak self] in
                    self?.recordingFileStore.discardTemporaryUpload(at: writer.fileURL)
                    self?.sendError(statusCode: 400, reason: "Bad Request", error: "body_incomplete", on: connection)
                }
            } else {
                self.streamRemainingRecordingAudioBody(request, writer: writer, remainingBytes: nextRemainingBytes, on: connection)
            }
        }
    }

    private func finishStreamingRecordingAudioBody(
        _ request: HTTPHeaderRequest,
        writer: StreamingBodyWriter,
        on connection: NWConnection
    ) {
        let bodySHA256 = writer.finalizeHashHex()
        Task { @MainActor [weak self] in
            guard let self else {
                connection.cancel()
                return
            }

            switch requestVerifier.verify(
                method: request.method,
                path: request.path,
                headers: request.headers,
                bodySHA256: bodySHA256,
                bodyByteCount: writer.bytesWritten
            ) {
            case .accepted(let device):
                do {
                    let headers = Self.normalizedHeaders(request.headers)
                    guard let recordingID = headers["x-rokurics-recording-id"], !recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        recordingFileStore.discardTemporaryUpload(at: writer.fileURL)
                        sendError(statusCode: 400, reason: "Bad Request", error: "missing_recording_id", on: connection)
                        return
                    }

                    let result = try recordingFileStore.saveAudio(
                        temporaryFileURL: writer.fileURL,
                        recordingID: recordingID,
                        requestedFileName: headers["x-rokurics-filename"],
                        sourceDevice: device,
                        checksum: bodySHA256,
                        fileSize: Int64(writer.bytesWritten)
                    )
                    onRecordingAccepted(result.recordingID)
                    print("[RokuricsRecordingUpload] streaming audio accepted: \(result.recordingID)")
                    sendJSON(
                        statusCode: 200,
                        reason: "OK",
                        body: RecordingUploadSuccessResponse(
                            ok: true,
                            message: "recording audio received",
                            recordingID: result.recordingID,
                            metadataFileName: result.metadataFileName,
                            audioFileName: result.audioFileName,
                            receiveFileName: result.receiveFileName
                        ),
                        on: connection
                    )
                } catch let error as MacRecordingFileStoreError {
                    recordingFileStore.discardTemporaryUpload(at: writer.fileURL)
                    sendError(statusCode: error.responseStatusCode, reason: error.responseReason, error: error.localizedDescription, on: connection)
                } catch {
                    recordingFileStore.discardTemporaryUpload(at: writer.fileURL)
                    sendError(statusCode: 500, reason: "Internal Server Error", error: "audio_storage_failed", on: connection)
                }
            case .rejected(let reason):
                recordingFileStore.discardTemporaryUpload(at: writer.fileURL)
                sendError(statusCode: reason == "body_too_large" ? 413 : 400, reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request", error: reason, on: connection)
            }
        }
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
        case ("POST", "/upload-recording-metadata"):
            Task { @MainActor [weak self] in
                self?.handleRecordingMetadataUploadRequest(request, on: connection)
            }
        case ("POST", "/upload-recording-audio"):
            Task { @MainActor [weak self] in
                self?.handleRecordingAudioUploadRequest(request, on: connection)
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
                    pairedAt: ISO8601DateFormatter().string(from: result.device.pairedAt),
                    macName: MacSystemInfoProvider.macName,
                    macModel: MacSystemInfoProvider.macModel
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

    @MainActor
    private func handleRecordingMetadataUploadRequest(_ request: HTTPRequest, on connection: NWConnection) {
        print("[RokuricsRecordingUpload] metadata upload request received")

        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            do {
                let metadata = try Self.recordingMetadataDecoder.decode(IncomingRecordingMetadata.self, from: request.body)
                let result = try recordingFileStore.saveMetadata(metadata, sourceDevice: device)
                onRecordingAccepted(result.recordingID)
                print("[RokuricsRecordingUpload] metadata accepted: \(result.recordingID)")
                sendJSON(
                    statusCode: 200,
                    reason: "OK",
                    body: RecordingUploadSuccessResponse(
                        ok: true,
                        message: "recording metadata received",
                        recordingID: result.recordingID,
                        metadataFileName: result.metadataFileName,
                        audioFileName: result.audioFileName,
                        receiveFileName: result.receiveFileName
                    ),
                    on: connection
                )
            } catch let error as MacRecordingFileStoreError {
                print("[RokuricsRecordingUpload] metadata rejected: \(error.localizedDescription)")
                sendError(statusCode: error.responseStatusCode, reason: error.responseReason, error: error.localizedDescription, on: connection)
            } catch {
                print("[RokuricsRecordingUpload] metadata rejected: bad_metadata")
                sendError(statusCode: 400, reason: "Bad Request", error: "bad_metadata", on: connection)
            }
        case .rejected(let reason):
            print("[RokuricsRecordingUpload] metadata rejected: \(reason)")
            sendError(statusCode: reason == "body_too_large" ? 413 : 400, reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleRecordingAudioUploadRequest(_ request: HTTPRequest, on connection: NWConnection) {
        print("[RokuricsRecordingUpload] audio upload request received")

        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            do {
                let headers = Self.normalizedHeaders(request.headers)
                guard let recordingID = headers["x-rokurics-recording-id"], !recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    sendError(statusCode: 400, reason: "Bad Request", error: "missing_recording_id", on: connection)
                    return
                }

                let result = try recordingFileStore.saveAudio(
                    body: request.body,
                    recordingID: recordingID,
                    requestedFileName: headers["x-rokurics-filename"],
                    sourceDevice: device
                )
                onRecordingAccepted(result.recordingID)
                print("[RokuricsRecordingUpload] audio accepted: \(result.recordingID)")
                sendJSON(
                    statusCode: 200,
                    reason: "OK",
                    body: RecordingUploadSuccessResponse(
                        ok: true,
                        message: "recording audio received",
                        recordingID: result.recordingID,
                        metadataFileName: result.metadataFileName,
                        audioFileName: result.audioFileName,
                        receiveFileName: result.receiveFileName
                    ),
                    on: connection
                )
            } catch let error as MacRecordingFileStoreError {
                print("[RokuricsRecordingUpload] audio rejected: \(error.localizedDescription)")
                sendError(statusCode: error.responseStatusCode, reason: error.responseReason, error: error.localizedDescription, on: connection)
            } catch {
                print("[RokuricsRecordingUpload] audio rejected: audio_storage_failed")
                sendError(statusCode: 500, reason: "Internal Server Error", error: "audio_storage_failed", on: connection)
            }
        case .rejected(let reason):
            print("[RokuricsRecordingUpload] audio rejected: \(reason)")
            sendError(statusCode: reason == "body_too_large" ? 413 : 400, reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request", error: reason, on: connection)
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

    private func bodyLimit(for path: String) -> Int {
        switch path {
        case "/upload-recording-audio":
            return MacRecordingFileStore.audioMaxBytes
        default:
            return 1 * 1024 * 1024
        }
    }

    private static let recordingMetadataDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private final class StreamingBodyWriter {
    let fileURL: URL
    private let fileHandle: FileHandle
    private var hasher = SHA256()
    private(set) var bytesWritten = 0
    private var isClosed = false

    init(fileURL: URL) throws {
        self.fileURL = fileURL.standardizedFileURL
        FileManager.default.createFile(atPath: self.fileURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: self.fileURL)
    }

    func append(_ data: Data) throws {
        guard !data.isEmpty else {
            return
        }

        try fileHandle.write(contentsOf: data)
        hasher.update(data: data)
        bytesWritten += data.count
    }

    func finalizeHashHex() -> String {
        close()
        return Data(hasher.finalize()).hexString
    }

    func close() {
        guard !isClosed else {
            return
        }

        try? fileHandle.close()
        isClosed = true
    }

    deinit {
        close()
    }
}

private enum MacSystemInfoProvider {
    static var macName: String {
        [
            computerName(),
            Host.current().localizedName,
            sanitizedHostName(ProcessInfo.processInfo.hostName)
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    static var macModel: String? {
        let normalizedName = macName.lowercased()

        if normalizedName.contains("macbook pro") {
            return "MacBook Pro"
        }

        if normalizedName.contains("macbook air") {
            return "MacBook Air"
        }

        if normalizedName.contains("macbook") {
            return "MacBook"
        }

        if normalizedName.contains("imac") {
            return "iMac"
        }

        if normalizedName.contains("mac mini") || normalizedName.contains("mac-mini") {
            return "Mac mini"
        }

        if normalizedName.contains("mac studio") || normalizedName.contains("mac-studio") {
            return "Mac Studio"
        }

        return nil
    }

    private static func computerName() -> String? {
        SCDynamicStoreCopyComputerName(nil, nil) as String?
    }

    private static func sanitizedHostName(_ hostName: String) -> String {
        hostName
            .replacingOccurrences(of: ".local", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}
