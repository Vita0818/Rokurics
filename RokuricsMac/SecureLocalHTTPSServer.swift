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

struct SecureLocalHTTPRouteResponse {
    let statusCode: Int
    let reason: String
    let bodyData: Data
}

struct SecureConnectionDiagnosticEvent: Sendable {
    let phase: String
    let listenerState: String?
    let activePort: Int?
    let errorCode: String?
    let errorMessage: String?
}

@MainActor
struct RecordingUploadRouteHandler {
    private struct ErrorResponse: Encodable {
        let ok: Bool
        let error: String
        let disposition: String?
        let reason: String?
    }

    private struct SuccessResponse: Encodable {
        let ok: Bool
        let message: String
        let disposition: String
        let recordingID: String
        let metadataFileName: String?
        let audioFileName: String?
        let receiveFileName: String
        let receiveStatus: String
        let processingStatus: String
    }

    let requestVerifier: RequestVerifier
    let recordingFileStore: MacRecordingFileStore
    let onRecordingAccepted: (String) -> Void

    func metadataUploadResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) -> SecureLocalHTTPRouteResponse {
        print("[RokuricsRecordingUpload] metadata upload request received")

        switch requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let metadata = try Self.recordingMetadataDecoder.decode(IncomingRecordingMetadata.self, from: body)
                let result = try recordingFileStore.saveMetadata(metadata, sourceDevice: device)
                onRecordingAccepted(result.recordingID)
                print("[RokuricsRecordingUpload] metadata accepted: \(result.recordingID)")
                return Self.successResponse(message: "recording metadata received", result: result)
            } catch let error as MacRecordingFileStoreError {
                print("[RokuricsRecordingUpload] metadata rejected: \(error.localizedDescription)")
                return Self.errorResponse(
                    statusCode: error.responseStatusCode,
                    reason: error.responseReason,
                    error: error.localizedDescription
                )
            } catch {
                print("[RokuricsRecordingUpload] metadata rejected: bad_metadata")
                return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "bad_metadata")
            }
        case .rejected(let reason):
            print("[RokuricsRecordingUpload] metadata rejected: \(reason)")
            return Self.errorResponse(
                statusCode: reason == "body_too_large" ? 413 : 400,
                reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request",
                error: reason
            )
        }
    }

    func audioUploadResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) -> SecureLocalHTTPRouteResponse {
        print("[RokuricsRecordingUpload] audio upload request received")

        switch requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let normalizedHeaders = Self.normalizedHeaders(headers)
                guard let recordingID = normalizedHeaders["x-rokurics-recording-id"],
                      !recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "missing_recording_id")
                }

                let result = try recordingFileStore.saveAudio(
                    body: body,
                    recordingID: recordingID,
                    requestedFileName: normalizedHeaders["x-rokurics-filename"],
                    sourceDevice: device
                )
                onRecordingAccepted(result.recordingID)
                print("[RokuricsRecordingUpload] audio accepted: \(result.recordingID)")
                return Self.successResponse(message: "recording audio received", result: result)
            } catch let error as MacRecordingFileStoreError {
                print("[RokuricsRecordingUpload] audio rejected: \(error.localizedDescription)")
                return Self.errorResponse(
                    statusCode: error.responseStatusCode,
                    reason: error.responseReason,
                    error: error.localizedDescription
                )
            } catch {
                print("[RokuricsRecordingUpload] audio rejected: audio_storage_failed")
                return Self.errorResponse(statusCode: 500, reason: "Internal Server Error", error: "audio_storage_failed")
            }
        case .rejected(let reason):
            print("[RokuricsRecordingUpload] audio rejected: \(reason)")
            return Self.errorResponse(
                statusCode: reason == "body_too_large" ? 413 : 400,
                reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request",
                error: reason
            )
        }
    }

    func resumableAudioStartResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) -> SecureLocalHTTPRouteResponse {
        switch requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let request = try Self.recordingMetadataDecoder.decode(ResumableAudioUploadStartRequest.self, from: body)
                let response = try recordingFileStore.startResumableAudioUpload(request, sourceDevice: device)
                onRecordingAccepted(request.recordingID)
                return Self.jsonResponse(statusCode: 200, reason: "OK", body: response)
            } catch let error as MacRecordingFileStoreError {
                return Self.errorResponse(
                    statusCode: error.responseStatusCode,
                    reason: error.responseReason,
                    error: error.localizedDescription
                )
            } catch {
                return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "bad_resumable_start")
            }
        case .rejected(let reason):
            return Self.errorResponse(
                statusCode: reason == "body_too_large" ? 413 : 400,
                reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request",
                error: reason
            )
        }
    }

    func resumableAudioStatusResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) -> SecureLocalHTTPRouteResponse {
        switch requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let request = try Self.recordingMetadataDecoder.decode(ResumableAudioUploadStatusRequest.self, from: body)
                let response = try recordingFileStore.resumableAudioUploadStatus(request, sourceDevice: device)
                return Self.jsonResponse(statusCode: 200, reason: "OK", body: response)
            } catch let error as MacRecordingFileStoreError {
                return Self.errorResponse(
                    statusCode: error.responseStatusCode,
                    reason: error.responseReason,
                    error: error.localizedDescription
                )
            } catch {
                return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "bad_resumable_status")
            }
        case .rejected(let reason):
            return Self.errorResponse(
                statusCode: reason == "body_too_large" ? 413 : 400,
                reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request",
                error: reason
            )
        }
    }

    func resumableAudioChunkResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) -> SecureLocalHTTPRouteResponse {
        switch requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let normalizedHeaders = Self.normalizedHeaders(headers)
                guard let recordingID = normalizedHeaders["x-rokurics-recording-id"],
                      let sessionID = normalizedHeaders["x-rokurics-session-id"],
                      let offsetValue = normalizedHeaders["x-rokurics-chunk-offset"],
                      let offset = Int64(offsetValue),
                      let lengthValue = normalizedHeaders["x-rokurics-chunk-length"],
                      let length = Int(lengthValue),
                      let chunkSHA256 = normalizedHeaders["x-rokurics-chunk-sha256"],
                      let totalSHA256 = normalizedHeaders["x-rokurics-total-sha256"] else {
                    return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "missing_chunk_headers")
                }

                let response = try recordingFileStore.appendResumableAudioChunk(
                    recordingID: recordingID,
                    sessionID: sessionID,
                    offset: offset,
                    length: length,
                    chunkSHA256: chunkSHA256,
                    totalSHA256: totalSHA256,
                    body: body,
                    sourceDevice: device
                )
                onRecordingAccepted(recordingID)
                return Self.jsonResponse(statusCode: 200, reason: "OK", body: response)
            } catch let error as MacRecordingFileStoreError {
                return Self.errorResponse(
                    statusCode: error.responseStatusCode,
                    reason: error.responseReason,
                    error: error.localizedDescription
                )
            } catch {
                return Self.errorResponse(statusCode: 500, reason: "Internal Server Error", error: "resumable_chunk_failed")
            }
        case .rejected(let reason):
            return Self.errorResponse(
                statusCode: reason == "body_too_large" ? 413 : 400,
                reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request",
                error: reason
            )
        }
    }

    func resumableAudioFinalizeResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) -> SecureLocalHTTPRouteResponse {
        switch requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let request = try Self.recordingMetadataDecoder.decode(ResumableAudioUploadFinalizeRequest.self, from: body)
                let response = try recordingFileStore.finalizeResumableAudioUpload(request, sourceDevice: device)
                onRecordingAccepted(request.recordingID)
                return Self.jsonResponse(statusCode: 200, reason: "OK", body: response)
            } catch let error as MacRecordingFileStoreError {
                return Self.errorResponse(
                    statusCode: error.responseStatusCode,
                    reason: error.responseReason,
                    error: error.localizedDescription
                )
            } catch {
                return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "bad_resumable_finalize")
            }
        case .rejected(let reason):
            return Self.errorResponse(
                statusCode: reason == "body_too_large" ? 413 : 400,
                reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request",
                error: reason
            )
        }
    }

    private static func successResponse(
        message: String,
        result: RecordingReceiveResult
    ) -> SecureLocalHTTPRouteResponse {
        jsonResponse(
            statusCode: 200,
            reason: "OK",
            body: SuccessResponse(
                ok: true,
                message: message,
                disposition: result.disposition.rawValue,
                recordingID: result.recordingID,
                metadataFileName: result.metadataFileName,
                audioFileName: result.audioFileName,
                receiveFileName: result.receiveFileName,
                receiveStatus: result.receiveStatus,
                processingStatus: result.processingStatus
            )
        )
    }

    static func errorResponse(statusCode: Int, reason: String, error: String) -> SecureLocalHTTPRouteResponse {
        jsonResponse(
            statusCode: statusCode,
            reason: reason,
            body: ErrorResponse(
                ok: false,
                error: error,
                disposition: error.contains("conflict") ? RecordingUploadDisposition.rejectedConflict.rawValue : nil,
                reason: reason
            )
        )
    }

    private static func jsonResponse<Response: Encodable>(
        statusCode: Int,
        reason: String,
        body: Response
    ) -> SecureLocalHTTPRouteResponse {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return SecureLocalHTTPRouteResponse(
                statusCode: statusCode,
                reason: reason,
                bodyData: try encoder.encode(body)
            )
        } catch {
            return SecureLocalHTTPRouteResponse(
                statusCode: 500,
                reason: "Internal Server Error",
                bodyData: Data(#"{"error":"response_encoding_failed","ok":false,"reason":"Internal Server Error"}"#.utf8)
            )
        }
    }

    private static func normalizedHeaders(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }
    }

    private static let recordingMetadataDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@MainActor
struct ConnectionHeartbeatRouteHandler {
    private struct ErrorResponse: Encodable {
        let ok: Bool
        let disposition: String
        let error: String
        let reason: String?
    }

    let requestVerifier: RequestVerifier
    let statusStore: DeviceConnectionStatusStore
    let localPeerDeviceID: String
    var minimumSuggestedInterval: TimeInterval = 2

    func heartbeatResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data,
        now: Date = Date()
    ) -> SecureLocalHTTPRouteResponse {
        switch requestVerifier.verify(method: method, path: path, headers: headers, body: body, now: now) {
        case .accepted(let device):
            do {
                let request = try Self.decoder.decode(ConnectionHeartbeatRequest.self, from: body)
                guard request.deviceID == device.id else {
                    return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "device_id_mismatch")
                }

                let requestDisplayName = request.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayName = requestDisplayName.isEmpty ? device.deviceName : requestDisplayName
                let status = statusStore.recordHeartbeatSuccess(
                    deviceID: device.id,
                    displayName: displayName.isEmpty ? "iPhone" : displayName,
                    sentAt: request.sentAt,
                    receivedAt: now,
                    latencyMilliseconds: max(0, now.timeIntervalSince(request.sentAt) * 1_000)
                )
                let response = ConnectionHeartbeatResponse(
                    ok: true,
                    disposition: "ok",
                    peerDeviceID: localPeerDeviceID,
                    serverTime: now,
                    receivedSequenceNumber: request.sequenceNumber,
                    connectionStatusRevision: status.connectionStatusRevision ?? 0,
                    minimumSuggestedInterval: minimumSuggestedInterval,
                    status: status,
                    error: nil
                )
                return Self.jsonResponse(statusCode: 200, reason: "OK", body: response)
            } catch {
                return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "bad_heartbeat_payload")
            }
        case .rejected(let reason):
            return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: reason)
        }
    }

    private static func errorResponse(statusCode: Int, reason: String, error: String) -> SecureLocalHTTPRouteResponse {
        jsonResponse(
            statusCode: statusCode,
            reason: reason,
            body: ErrorResponse(ok: false, disposition: "rejected", error: error, reason: reason)
        )
    }

    private static func jsonResponse<Response: Encodable>(
        statusCode: Int,
        reason: String,
        body: Response
    ) -> SecureLocalHTTPRouteResponse {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return SecureLocalHTTPRouteResponse(
                statusCode: statusCode,
                reason: reason,
                bodyData: try encoder.encode(body)
            )
        } catch {
            return SecureLocalHTTPRouteResponse(
                statusCode: 500,
                reason: "Internal Server Error",
                bodyData: Data(#"{"disposition":"rejected","error":"response_encoding_failed","ok":false}"#.utf8)
            )
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@MainActor
struct ConnectionProbeRouteHandler {
    private struct ProbeRequest: Decodable {
        let sequenceNumber: UInt64
        let clientPayload: String
        let sentAt: Date
    }

    private struct ProbeResponse: Encodable {
        let ok: Bool
        let disposition: String
        let receivedSequenceNumber: UInt64
        let echoedClientPayload: String
        let serverPayload: String
        let serverTime: Date
    }

    private struct ErrorResponse: Encodable {
        let ok: Bool
        let disposition: String
        let error: String
        let reason: String?
    }

    let requestVerifier: RequestVerifier
    var statusStore: DeviceConnectionStatusStore? = nil

    func probeResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data,
        now: Date = Date()
    ) -> SecureLocalHTTPRouteResponse {
        switch requestVerifier.verify(method: method, path: path, headers: headers, body: body, now: now) {
        case .accepted(let device):
            do {
                let request = try Self.decoder.decode(ProbeRequest.self, from: body)
                guard request.clientPayload.utf8.count <= 1024 else {
                    return Self.errorResponse(statusCode: 413, reason: "Payload Too Large", error: "probe_payload_too_large")
                }

                _ = statusStore?.recordSignedRequestSucceeded(
                    deviceID: device.id,
                    displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
                    now: now
                )
                let response = ProbeResponse(
                    ok: true,
                    disposition: "ok",
                    receivedSequenceNumber: request.sequenceNumber,
                    echoedClientPayload: request.clientPayload,
                    serverPayload: "rokurics-probe-ok",
                    serverTime: now
                )
                return Self.jsonResponse(statusCode: 200, reason: "OK", body: response)
            } catch {
                return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "bad_probe_payload")
            }
        case .rejected(let reason):
            return Self.errorResponse(statusCode: reason == "body_too_large" ? 413 : 400, reason: reason == "body_too_large" ? "Payload Too Large" : "Bad Request", error: reason)
        }
    }

    private static func errorResponse(statusCode: Int, reason: String, error: String) -> SecureLocalHTTPRouteResponse {
        jsonResponse(
            statusCode: statusCode,
            reason: reason,
            body: ErrorResponse(ok: false, disposition: "rejected", error: error, reason: reason)
        )
    }

    private static func jsonResponse<Response: Encodable>(
        statusCode: Int,
        reason: String,
        body: Response
    ) -> SecureLocalHTTPRouteResponse {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return SecureLocalHTTPRouteResponse(
                statusCode: statusCode,
                reason: reason,
                bodyData: try encoder.encode(body)
            )
        } catch {
            return SecureLocalHTTPRouteResponse(
                statusCode: 500,
                reason: "Internal Server Error",
                bodyData: Data(#"{"disposition":"rejected","error":"response_encoding_failed","ok":false}"#.utf8)
            )
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

@MainActor
struct PairingBootstrapRouteHandler {
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

    private struct PairErrorResponse: Encodable {
        let ok: Bool
        let error: String
    }

    let pairingManager: PairingManager
    let macName: String
    let macModel: String?
    let onPairingChanged: () -> Void

    func pairingResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data,
        now: Date = Date()
    ) -> SecureLocalHTTPRouteResponse {
        print("[RokuricsPairing] pairing request received")

        guard method == "POST", path == "/pair" else {
            return Self.errorResponse(statusCode: 404, reason: "Not Found", error: "not_found")
        }

        guard Self.normalizedHeaders(headers)["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            print("[RokuricsPairing] pairing failure: content_type_not_allowed")
            return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "bad_request")
        }

        do {
            let pairRequest = try JSONDecoder().decode(PairRequest.self, from: body)
            let code = pairRequest.pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let deviceName = pairRequest.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "iPhone"
                : pairRequest.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
            let deviceType = pairRequest.deviceType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "iPhone"
                : pairRequest.deviceType.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let result = pairingManager.completePairing(deviceName: deviceName, deviceType: deviceType, code: code, now: now) else {
                onPairingChanged()
                return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "invalid_pairing_code")
            }

            onPairingChanged()
            print("[RokuricsPairing] pairing success response prepared: deviceIDPrefix=\(result.device.idPrefix)")
            return Self.jsonResponse(
                statusCode: 200,
                reason: "OK",
                body: PairSuccessResponse(
                    ok: true,
                    deviceID: result.device.id,
                    sharedSecret: result.sharedSecretBase64URL,
                    pairedAt: ISO8601DateFormatter().string(from: result.device.pairedAt),
                    macName: macName,
                    macModel: macModel
                )
            )
        } catch {
            print("[RokuricsPairing] pairing failure: bad_request")
            return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "bad_request")
        }
    }

    private static func errorResponse(statusCode: Int, reason: String, error: String) -> SecureLocalHTTPRouteResponse {
        jsonResponse(statusCode: statusCode, reason: reason, body: PairErrorResponse(ok: false, error: error))
    }

    private static func jsonResponse<Response: Encodable>(
        statusCode: Int,
        reason: String,
        body: Response
    ) -> SecureLocalHTTPRouteResponse {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return SecureLocalHTTPRouteResponse(
                statusCode: statusCode,
                reason: reason,
                bodyData: try encoder.encode(body)
            )
        } catch {
            return SecureLocalHTTPRouteResponse(
                statusCode: 500,
                reason: "Internal Server Error",
                bodyData: Data(#"{"error":"response_encoding_failed","ok":false}"#.utf8)
            )
        }
    }

    private static func normalizedHeaders(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }
    }
}

final class SecureLocalHTTPSServer {
    typealias ReadyHandler = @Sendable () -> Void
    typealias FailedHandler = @Sendable (String) -> Void
    typealias PairingChangedHandler = @Sendable () -> Void
    typealias UploadAcceptedHandler = @Sendable (String) -> Void
    typealias RecordingAcceptedHandler = @Sendable (String) -> Void
    typealias ConnectionDiagnosticHandler = @Sendable (SecureConnectionDiagnosticEvent) -> Void

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
        let disposition: String?
        let reason: String?
    }

    private struct UploadSuccessResponse: Encodable {
        let ok: Bool
        let message: String
        let fileName: String
    }

    private struct RecordingUploadSuccessResponse: Encodable {
        let ok: Bool
        let message: String
        let disposition: String
        let recordingID: String
        let metadataFileName: String?
        let audioFileName: String?
        let receiveFileName: String
        let receiveStatus: String
        let processingStatus: String
    }

    private let port: Int
    private let identityManager: MacIdentityManager
    private let pairingManager: PairingManager
    private let requestVerifier: RequestVerifier
    private let receivedFileStore: ReceivedFileStore
    private let recordingFileStore: MacRecordingFileStore
    private let studyLibraryStore: StudyLibraryStore
    private let gitBackedStudyMetadataStore: GitBackedStudyMetadataStore?
    private let deviceConnectionStatusStore: DeviceConnectionStatusStore
    private let syncStateStore: StudyLibrarySyncStateStore
    private let syncRuntimeConfiguration: StudyLibrarySyncRuntimeConfiguration
    private let onReady: ReadyHandler
    private let onFailed: FailedHandler
    private let onPairingChanged: PairingChangedHandler
    private let onUploadAccepted: UploadAcceptedHandler
    private let onRecordingAccepted: RecordingAcceptedHandler
    private let onConnectionDiagnostic: ConnectionDiagnosticHandler
    private let queue = DispatchQueue(label: "RokuricsMac.SecureLocalHTTPSServer")
    private let maxHeaderBytes = 16 * 1024
    private let maxAllowedBodyBytes = MacRecordingFileStore.audioMaxBytes
    private var listener: NWListener?
    private var activeConnections: [UUID: NWConnection] = [:]
    private let listenerStateLock = NSLock()
    private var listenerIsReady = false
    private var listenerActivePort: Int?

    init(
        port: Int,
        identityManager: MacIdentityManager,
        pairingManager: PairingManager,
        requestVerifier: RequestVerifier,
        receivedFileStore: ReceivedFileStore,
        recordingFileStore: MacRecordingFileStore,
        studyLibraryStore: StudyLibraryStore,
        gitBackedStudyMetadataStore: GitBackedStudyMetadataStore?,
        deviceConnectionStatusStore: DeviceConnectionStatusStore,
        syncStateStore: StudyLibrarySyncStateStore,
        syncRuntimeConfiguration: StudyLibrarySyncRuntimeConfiguration = StudyLibrarySyncRuntimeConfiguration(gitBackedSyncEnabled: false),
        onReady: @escaping ReadyHandler,
        onFailed: @escaping FailedHandler,
        onPairingChanged: @escaping PairingChangedHandler,
        onUploadAccepted: @escaping UploadAcceptedHandler,
        onRecordingAccepted: @escaping RecordingAcceptedHandler,
        onConnectionDiagnostic: @escaping ConnectionDiagnosticHandler = { _ in }
    ) {
        self.port = port
        self.identityManager = identityManager
        self.pairingManager = pairingManager
        self.requestVerifier = requestVerifier
        self.receivedFileStore = receivedFileStore
        self.recordingFileStore = recordingFileStore
        self.studyLibraryStore = studyLibraryStore
        self.gitBackedStudyMetadataStore = gitBackedStudyMetadataStore
        self.deviceConnectionStatusStore = deviceConnectionStatusStore
        self.syncStateStore = syncStateStore
        self.syncRuntimeConfiguration = syncRuntimeConfiguration
        self.onReady = onReady
        self.onFailed = onFailed
        self.onPairingChanged = onPairingChanged
        self.onUploadAccepted = onUploadAccepted
        self.onRecordingAccepted = onRecordingAccepted
        self.onConnectionDiagnostic = onConnectionDiagnostic
    }

    func start() throws {
        print("[RokuricsHTTPS] HTTPS listener starting")
        emitConnectionDiagnostic(phase: "listener_starting", listenerState: "starting")

        guard identityManager.status.hasTLSIdentity, let tlsOptions = identityManager.tlsOptions() else {
            let reason = identityManager.status.tlsBlocker ?? "TLS identity unavailable."
            print("[RokuricsHTTPS] rejected reason: \(reason)")
            emitConnectionDiagnostic(
                phase: "listener_start_rejected",
                listenerState: "failed",
                errorCode: "tls_identity_unavailable",
                errorMessage: reason
            )
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
                let activePort = self.listener?.port.map { Int($0.rawValue) } ?? self.port
                self.updateListenerState(isReady: true, activePort: activePort)
                print("[RokuricsHTTPS] listener state: ready")
                self.emitConnectionDiagnostic(phase: "listener_ready", listenerState: "ready", activePort: activePort)
                self.onReady()
            case .failed(let error):
                self.updateListenerState(isReady: false, activePort: nil)
                let message = "HTTPS listener failed: \(error)"
                print("[RokuricsHTTPS][ERROR] \(message)")
                self.emitConnectionDiagnostic(
                    phase: "listener_failed",
                    listenerState: "failed",
                    errorCode: "server_unreachable",
                    errorMessage: message
                )
                self.onFailed(message)
            case .cancelled:
                self.updateListenerState(isReady: false, activePort: nil)
                print("[RokuricsHTTPS] listener state: cancelled")
                self.emitConnectionDiagnostic(phase: "listener_cancelled", listenerState: "cancelled")
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
        updateListenerState(isReady: false, activePort: nil)
        listener?.cancel()
        listener = nil
        activeConnections.values.forEach { $0.cancel() }
        activeConnections.removeAll()
        emitConnectionDiagnostic(phase: "listener_stop_requested", listenerState: "cancelled")
        print("[RokuricsHTTPS] secure server stopped")
    }

    var isReady: Bool {
        listenerStateLock.lock()
        defer { listenerStateLock.unlock() }
        return listenerIsReady
    }

    var activePort: Int? {
        listenerStateLock.lock()
        defer { listenerStateLock.unlock() }
        return listenerActivePort
    }

    private func updateListenerState(isReady: Bool, activePort: Int?) {
        listenerStateLock.lock()
        listenerIsReady = isReady
        listenerActivePort = activePort
        listenerStateLock.unlock()
    }

    private func emitConnectionDiagnostic(
        phase: String,
        listenerState: String? = nil,
        activePort: Int? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        onConnectionDiagnostic(
            SecureConnectionDiagnosticEvent(
                phase: phase,
                listenerState: listenerState,
                activePort: activePort,
                errorCode: errorCode,
                errorMessage: errorMessage
            )
        )
    }

    private var recordingUploadRouteHandler: RecordingUploadRouteHandler {
        RecordingUploadRouteHandler(
            requestVerifier: requestVerifier,
            recordingFileStore: recordingFileStore,
            onRecordingAccepted: onRecordingAccepted
        )
    }

    private var connectionHeartbeatRouteHandler: ConnectionHeartbeatRouteHandler {
        ConnectionHeartbeatRouteHandler(
            requestVerifier: requestVerifier,
            statusStore: deviceConnectionStatusStore,
            localPeerDeviceID: localSyncDeviceID
        )
    }

    private var connectionProbeRouteHandler: ConnectionProbeRouteHandler {
        ConnectionProbeRouteHandler(
            requestVerifier: requestVerifier,
            statusStore: deviceConnectionStatusStore
        )
    }

    private var pairingBootstrapRouteHandler: PairingBootstrapRouteHandler {
        PairingBootstrapRouteHandler(
            pairingManager: pairingManager,
            macName: MacSystemInfoProvider.macName,
            macModel: MacSystemInfoProvider.macModel,
            onPairingChanged: onPairingChanged
        )
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
                            disposition: result.disposition.rawValue,
                            recordingID: result.recordingID,
                            metadataFileName: result.metadataFileName,
                            audioFileName: result.audioFileName,
                            receiveFileName: result.receiveFileName,
                            receiveStatus: result.receiveStatus,
                            processingStatus: result.processingStatus
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
            emitConnectionDiagnostic(phase: "fingerprint_endpoint_reached", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(phase: "fingerprintEndpointReached", listenerState: "ready", activePort: activePort)
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
        case ("POST", "/upload-recording-audio-session/start"):
            Task { @MainActor [weak self] in
                self?.handleResumableAudioStartRequest(request, on: connection)
            }
        case ("POST", "/upload-recording-audio-session/status"):
            Task { @MainActor [weak self] in
                self?.handleResumableAudioStatusRequest(request, on: connection)
            }
        case ("POST", "/upload-recording-audio-session/chunk"):
            Task { @MainActor [weak self] in
                self?.handleResumableAudioChunkRequest(request, on: connection)
            }
        case ("POST", "/upload-recording-audio-session/finalize"):
            Task { @MainActor [weak self] in
                self?.handleResumableAudioFinalizeRequest(request, on: connection)
            }
        case ("POST", "/device/status"):
            Task { @MainActor [weak self] in
                self?.handleDeviceStatusRequest(request, on: connection)
            }
        case ("POST", "/connection/heartbeat"):
            Task { @MainActor [weak self] in
                self?.handleConnectionHeartbeatRequest(request, on: connection)
            }
        case ("POST", "/connection/probe"):
            Task { @MainActor [weak self] in
                self?.handleConnectionProbeRequest(request, on: connection)
            }
        case ("POST", "/sync/device-status"):
            Task { @MainActor [weak self] in
                self?.handleDeviceStatusRequest(request, on: connection)
            }
        case ("POST", "/sync/status"):
            Task { @MainActor [weak self] in
                self?.handleSyncStatusRequest(request, on: connection)
            }
        case ("POST", "/sync/manifest"):
            Task { @MainActor [weak self] in
                self?.handleSyncManifestRequest(request, on: connection)
            }
        case ("POST", "/sync/apply"):
            Task { @MainActor [weak self] in
                self?.handleSyncApplyRequest(request, on: connection)
            }
        case ("POST", "/sync/inventory"):
            Task { @MainActor [weak self] in
                self?.handleLocalNetworkSyncInventoryRequest(request, on: connection)
            }
        case ("POST", "/sync/apply-metadata"):
            Task { @MainActor [weak self] in
                self?.handleLocalNetworkSyncApplyMetadataRequest(request, on: connection)
            }
        case ("POST", "/sync/artifact-request"):
            Task { @MainActor [weak self] in
                self?.handleLocalNetworkSyncArtifactRequest(request, on: connection)
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
    private func handleDeviceStatusRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            guard let statusRequest = try? Self.syncJSONDecoder.decode(DeviceStatusRequest.self, from: request.body) else {
                sendError(statusCode: 400, reason: "Bad Request", error: "bad_status_payload", on: connection)
                return
            }

            let status = markDeviceOnline(
                device: device,
                displayName: statusRequest.displayName,
                syncStatus: statusRequest.syncSummary?.statusText
            )
            sendJSON(
                statusCode: 200,
                reason: "OK",
                body: DeviceStatusResponse(ok: true, status: status, syncState: syncStateStore.state, error: nil),
                on: connection
            )
        case .rejected(let reason):
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleConnectionHeartbeatRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let response = connectionHeartbeatRouteHandler.heartbeatResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        emitConnectionDiagnostic(
            phase: response.statusCode == 200 ? "heartbeat_success" : "heartbeat_failure",
            listenerState: "ready",
            activePort: activePort,
            errorCode: response.statusCode == 200 ? nil : "request_verifier_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason
        )
        emitConnectionDiagnostic(
            phase: response.statusCode == 200 ? "heartbeatSuccess" : "heartbeatFailure",
            listenerState: "ready",
            activePort: activePort,
            errorCode: response.statusCode == 200 ? nil : "request_verifier_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason
        )
        if response.statusCode == 200 {
            emitConnectionDiagnostic(phase: "signedRequestRefreshedLastSeen", listenerState: "ready", activePort: activePort)
        }
        sendRouteResponse(response, on: connection)
    }

    @MainActor
    private func handleConnectionProbeRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let response = connectionProbeRouteHandler.probeResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        emitConnectionDiagnostic(
            phase: response.statusCode == 200 ? "probe_success" : "probe_failure",
            listenerState: "ready",
            activePort: activePort,
            errorCode: response.statusCode == 200 ? nil : "request_verifier_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason
        )
        emitConnectionDiagnostic(
            phase: response.statusCode == 200 ? "probeSuccess" : "probeFailure",
            listenerState: "ready",
            activePort: activePort,
            errorCode: response.statusCode == 200 ? nil : "request_verifier_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason
        )
        if response.statusCode == 200 {
            emitConnectionDiagnostic(phase: "signedRequestRefreshedLastSeen", listenerState: "ready", activePort: activePort)
        }
        sendRouteResponse(response, on: connection)
    }

    @MainActor
    func syncStatusResponseForVerifiedDevice(_ device: PairedDevice) -> DeviceStatusResponse {
        let statusText = activeGitBackedStudyMetadataStore == nil
            ? StudyLibrarySyncRuntimeConfiguration.disabledStatusText
            : (syncStateStore.state.lastError == nil ? "待同步" : "同步失败")
        let status = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: statusText)
        return DeviceStatusResponse(
            ok: true,
            status: status,
            syncState: syncStateStore.state,
            error: activeGitBackedStudyMetadataStore == nil
                ? StudyLibrarySyncRuntimeConfiguration.disabledReason
                : nil
        )
    }

    @MainActor
    func syncManifestResponseForVerifiedDevice(_ device: PairedDevice) throws -> StudyLibrarySyncManifestResponse {
        guard let gitBackedStudyMetadataStore = activeGitBackedStudyMetadataStore else {
            return disabledSyncManifestResponse(for: device)
        }

        var manifest = studyLibraryStore.makeSyncManifest(deviceID: localSyncDeviceID)
        let commitResult = try gitBackedStudyMetadataStore.commitManifest(
            manifest,
            deviceDisplayName: "Rokurics Mac",
            message: "sync study library snapshot"
        )
        manifest.commitID = commitResult.commitID
        syncStateStore.recordPush(
            deviceID: device.id,
            remoteManifestHash: nil,
            remoteCommitID: manifest.commitID,
            pendingUploads: manifest.pendingUploads.count
        )
        let status = deviceConnectionStatusStore.recordSyncResult(
            deviceID: device.id,
            displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            statusText: "已发送 \(manifest.summaryText)"
        )
        return StudyLibrarySyncManifestResponse(
            ok: true,
            manifest: manifest,
            syncState: syncStateStore.state,
            deviceStatus: status,
            applyResult: nil,
            baseCommitID: nil,
            newCommitID: manifest.commitID,
            remoteChanges: manifest.changesApproximation,
            rejectedChanges: nil,
            error: nil
        )
    }

    @MainActor
    func syncApplyResponseForVerifiedDevice(
        _ device: PairedDevice,
        requestBody: Data
    ) throws -> StudyLibrarySyncManifestResponse {
        guard let gitBackedStudyMetadataStore = activeGitBackedStudyMetadataStore else {
            return disabledSyncManifestResponse(for: device)
        }

        let syncRequest = try Self.syncJSONDecoder.decode(StudyLibrarySyncManifestRequest.self, from: requestBody)
        let applyResult = try studyLibraryStore.applySyncManifest(syncRequest.manifest, localDeviceID: localSyncDeviceID)
        var manifest = studyLibraryStore.makeSyncManifest(deviceID: localSyncDeviceID)
        let commitResult = try gitBackedStudyMetadataStore.commitManifest(
            manifest,
            deviceDisplayName: device.deviceName.isEmpty ? device.id : device.deviceName,
            message: "sync study library from \(device.deviceName.isEmpty ? device.id : device.deviceName)"
        )
        manifest.baseCommitID = syncRequest.manifest.baseCommitID
        manifest.commitID = commitResult.commitID
        let pendingUploadCount = syncRequest.manifest.pendingUploads.filter { $0.status != .uploaded }.count
        if applyResult.failedChanges == 0 {
            syncStateStore.recordPull(
                deviceID: device.id,
                remoteManifestHash: syncRequest.manifest.checksum,
                remoteCommitID: syncRequest.manifest.baseCommitID
            )
            syncStateStore.recordPush(
                deviceID: device.id,
                remoteManifestHash: syncRequest.manifest.checksum,
                remoteCommitID: commitResult.commitID,
                pendingUploads: pendingUploadCount
            )
        } else {
            syncStateStore.recordFailure(
                deviceID: device.id,
                error: "sync_apply_partial_failure",
                failedChanges: applyResult.failedChanges,
                pendingUploads: pendingUploadCount
            )
        }
        let statusText = pendingUploadCount > 0
            ? "\(applyResult.summaryText) · 待上传 \(pendingUploadCount)"
            : applyResult.summaryText
        let status = deviceConnectionStatusStore.recordSyncResult(
            deviceID: device.id,
            displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            statusText: statusText,
            error: applyResult.failedChanges == 0 ? nil : "sync_apply_partial_failure"
        )

        return StudyLibrarySyncManifestResponse(
            ok: true,
            manifest: manifest,
            syncState: syncStateStore.state,
            deviceStatus: status,
            applyResult: applyResult,
            baseCommitID: syncRequest.manifest.baseCommitID,
            newCommitID: commitResult.commitID,
            remoteChanges: manifest.changesApproximation,
            rejectedChanges: applyResult.failedChanges == 0 ? nil : syncRequest.manifest.changesApproximation,
            error: nil
        )
    }

    @MainActor
    private func disabledSyncManifestResponse(for device: PairedDevice) -> StudyLibrarySyncManifestResponse {
        let status = deviceConnectionStatusStore.recordSyncResult(
            deviceID: device.id,
            displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            statusText: StudyLibrarySyncRuntimeConfiguration.disabledStatusText,
            error: StudyLibrarySyncRuntimeConfiguration.disabledReason
        )
        return StudyLibrarySyncManifestResponse(
            ok: false,
            manifest: nil,
            syncState: syncStateStore.state,
            deviceStatus: status,
            applyResult: nil,
            baseCommitID: nil,
            newCommitID: nil,
            remoteChanges: nil,
            rejectedChanges: nil,
            error: StudyLibrarySyncRuntimeConfiguration.disabledReason
        )
    }

    private var activeGitBackedStudyMetadataStore: GitBackedStudyMetadataStore? {
        guard syncRuntimeConfiguration.gitBackedSyncEnabled else {
            return nil
        }
        return gitBackedStudyMetadataStore
    }

    @MainActor
    private func handleSyncStatusRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            sendJSON(
                statusCode: 200,
                reason: "OK",
                body: syncStatusResponseForVerifiedDevice(device),
                on: connection
            )
        case .rejected(let reason):
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleSyncManifestRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            do {
                let response = try syncManifestResponseForVerifiedDevice(device)
                sendJSON(statusCode: 200, reason: "OK", body: response, on: connection)
            } catch {
                syncStateStore.recordFailure(deviceID: device.id, error: error.localizedDescription)
                sendError(statusCode: 500, reason: "Internal Server Error", error: "git_metadata_commit_failed", on: connection)
            }
        case .rejected(let reason):
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleSyncApplyRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            do {
                let response = try syncApplyResponseForVerifiedDevice(device, requestBody: request.body)
                sendJSON(statusCode: 200, reason: "OK", body: response, on: connection)
            } catch {
                syncStateStore.recordFailure(deviceID: device.id, error: error.localizedDescription)
                sendError(statusCode: 400, reason: "Bad Request", error: error.localizedDescription, on: connection)
            }
        case .rejected(let reason):
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    func localNetworkSyncInventoryResponseForVerifiedDevice(_ device: PairedDevice) -> LocalNetworkSyncInventoryResponse {
        _ = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: "inventory")
        return LocalNetworkSyncInventoryResponse(
            ok: true,
            inventory: makeLocalNetworkSyncInventory(),
            error: nil
        )
    }

    @MainActor
    func localNetworkSyncApplyMetadataResponseForVerifiedDevice(
        _ device: PairedDevice,
        requestBody: Data
    ) throws -> StudyLibrarySyncManifestResponse {
        let syncRequest = try Self.syncJSONDecoder.decode(StudyLibrarySyncManifestRequest.self, from: requestBody)
        let applyResult = try studyLibraryStore.applySyncManifest(syncRequest.manifest, localDeviceID: localSyncDeviceID)
        let manifest = studyLibraryStore.makeSyncManifest(deviceID: localSyncDeviceID)
        let pendingUploadCount = syncRequest.manifest.pendingUploads.filter { $0.status != .uploaded }.count
        let status = deviceConnectionStatusStore.recordSyncResult(
            deviceID: device.id,
            displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            statusText: applyResult.summaryText,
            error: applyResult.failedChanges == 0 ? nil : "sync_apply_metadata_partial_failure"
        )

        if applyResult.failedChanges == 0 {
            syncStateStore.recordPull(
                deviceID: device.id,
                remoteManifestHash: syncRequest.manifest.checksum,
                remoteCommitID: syncRequest.manifest.baseCommitID
            )
            syncStateStore.recordPush(
                deviceID: device.id,
                remoteManifestHash: syncRequest.manifest.checksum,
                remoteCommitID: nil,
                pendingUploads: pendingUploadCount
            )
        } else {
            syncStateStore.recordFailure(
                deviceID: device.id,
                error: "sync_apply_metadata_partial_failure",
                failedChanges: applyResult.failedChanges,
                pendingUploads: pendingUploadCount
            )
        }

        return StudyLibrarySyncManifestResponse(
            ok: true,
            manifest: manifest,
            syncState: syncStateStore.state,
            deviceStatus: status,
            applyResult: applyResult,
            baseCommitID: syncRequest.manifest.baseCommitID,
            newCommitID: nil,
            remoteChanges: manifest.changesApproximation,
            rejectedChanges: applyResult.failedChanges == 0 ? nil : syncRequest.manifest.changesApproximation,
            error: applyResult.failedChanges == 0 ? nil : "sync_apply_metadata_partial_failure"
        )
    }

    @MainActor
    func localNetworkSyncArtifactResponseForVerifiedDevice(
        _ device: PairedDevice,
        requestBody: Data
    ) -> LocalNetworkSyncArtifactResponse {
        _ = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: "artifact")

        do {
            let request = try Self.syncJSONDecoder.decode(LocalNetworkSyncArtifactRequest.self, from: requestBody)
            try LocalNetworkSyncArtifactID.validate(request.artifactID)
            let inventory = makeLocalNetworkSyncInventory()
            guard let artifact = inventory.artifacts.first(where: { $0.artifactID == request.artifactID }) else {
                throw LocalNetworkSyncArtifactValidationError.artifactNotFound
            }
            guard artifact.kind.isAutoDownloadAllowed else {
                throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
            }

            let artifactURL = try LocalNetworkSyncArtifactFileService.safeFileURL(
                rootURL: recordingFileStore.libraryRootURL,
                logicalPathToken: artifact.logicalPathToken
            )
            guard FileManager.default.fileExists(atPath: artifactURL.path) else {
                throw LocalNetworkSyncArtifactValidationError.artifactNotFound
            }
            if let size = LocalNetworkSyncArtifactFileService.metadata(for: artifactURL)?.size,
               size > 4 * 1024 * 1024 {
                throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
            }

            let data = try Data(contentsOf: artifactURL)
            return LocalNetworkSyncArtifactResponse(
                ok: true,
                artifactID: artifact.artifactID,
                kind: artifact.kind,
                checksum: try LocalNetworkSyncArtifactFileService.sha256Hex(fileURL: artifactURL),
                size: Int64(data.count),
                logicalPathToken: artifact.logicalPathToken,
                dataBase64: data.base64EncodedString(),
                error: nil
            )
        } catch {
            return LocalNetworkSyncArtifactResponse(
                ok: false,
                artifactID: nil,
                kind: nil,
                checksum: nil,
                size: nil,
                logicalPathToken: nil,
                dataBase64: nil,
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    @MainActor
    private func handleLocalNetworkSyncInventoryRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            sendJSON(
                statusCode: 200,
                reason: "OK",
                body: localNetworkSyncInventoryResponseForVerifiedDevice(device),
                on: connection
            )
        case .rejected(let reason):
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleLocalNetworkSyncApplyMetadataRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            do {
                let response = try localNetworkSyncApplyMetadataResponseForVerifiedDevice(device, requestBody: request.body)
                sendJSON(statusCode: 200, reason: "OK", body: response, on: connection)
            } catch {
                syncStateStore.recordFailure(deviceID: device.id, error: error.localizedDescription)
                sendError(statusCode: 400, reason: "Bad Request", error: error.localizedDescription, on: connection)
            }
        case .rejected(let reason):
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleLocalNetworkSyncArtifactRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            let response = localNetworkSyncArtifactResponseForVerifiedDevice(device, requestBody: request.body)
            let statusCode = response.ok ? 200 : 400
            sendJSON(
                statusCode: statusCode,
                reason: response.ok ? "OK" : "Bad Request",
                body: response,
                on: connection
            )
        case .rejected(let reason):
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handlePairRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let response = pairingBootstrapRouteHandler.pairingResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        emitConnectionDiagnostic(
            phase: "pair_request_reached",
            listenerState: "ready",
            activePort: activePort,
            errorCode: response.statusCode == 200 ? nil : "pairing_code_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason
        )
        emitConnectionDiagnostic(
            phase: "pairRequestReached",
            listenerState: "ready",
            activePort: activePort,
            errorCode: response.statusCode == 200 ? nil : "pairing_code_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason
        )
        sendRouteResponse(response, on: connection)
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
        let response = recordingUploadRouteHandler.metadataUploadResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    @MainActor
    private func handleRecordingAudioUploadRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let response = recordingUploadRouteHandler.audioUploadResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    @MainActor
    private func handleResumableAudioStartRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let response = recordingUploadRouteHandler.resumableAudioStartResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    @MainActor
    private func handleResumableAudioStatusRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let response = recordingUploadRouteHandler.resumableAudioStatusResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    @MainActor
    private func handleResumableAudioChunkRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let response = recordingUploadRouteHandler.resumableAudioChunkResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    @MainActor
    private func handleResumableAudioFinalizeRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let response = recordingUploadRouteHandler.resumableAudioFinalizeResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    private func sendError(statusCode: Int, reason: String, error: String, on connection: NWConnection) {
        let disposition = error.contains("conflict") ? RecordingUploadDisposition.rejectedConflict.rawValue : nil
        sendJSON(
            statusCode: statusCode,
            reason: reason,
            body: ErrorResponse(ok: false, error: error, disposition: disposition, reason: reason),
            on: connection
        )
    }

    private func sendRouteResponse(_ response: SecureLocalHTTPRouteResponse, on connection: NWConnection) {
        sendJSONData(statusCode: response.statusCode, reason: response.reason, bodyData: response.bodyData, on: connection)
    }

    private func sendJSON<Response: Encodable>(statusCode: Int, reason: String, body: Response, on connection: NWConnection) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
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
        case "/connection/probe":
            return 4 * 1024
        case "/upload-recording-audio":
            return MacRecordingFileStore.audioMaxBytes
        case "/upload-recording-audio-session/chunk":
            return MacRecordingFileStore.resumableChunkMaxBytes
        case "/upload-recording-audio-session/start",
             "/upload-recording-audio-session/status",
             "/upload-recording-audio-session/finalize":
            return 256 * 1024
        case "/sync/apply", "/sync/apply-metadata":
            return 4 * 1024 * 1024
        case "/sync/artifact-request":
            return 256 * 1024
        default:
            return 1 * 1024 * 1024
        }
    }

    @MainActor
    private func makeLocalNetworkSyncInventory(generatedAt: Date = Date()) -> LocalNetworkSyncInventory {
        let manifest = studyLibraryStore.makeSyncManifest(deviceID: localSyncDeviceID, generatedAt: generatedAt)
        let itemsByRecordingID = Dictionary(
            manifest.items.compactMap { item -> (String, StudyItemMetadata)? in
                guard let recordingID = item.recordingID else {
                    return nil
                }
                return (recordingID, item)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        let inboxItems = recordingFileStore.loadInboxItems(includeDeleted: true)
        let recordings = inboxItems.map { item in
            let metadataHash = itemsByRecordingID[item.id].map(LocalNetworkSyncMetadataHash.hash)
            return LocalNetworkSyncRecordingEntry(
                recordingID: item.id,
                metadataHash: metadataHash,
                audioAvailable: item.hasAudio,
                audioChecksum: nil,
                audioSize: item.hasAudio ? item.fileSize : nil,
                uploadLedgerState: nil,
                receiveStatus: item.receiveStatus,
                processingStatus: item.hasAudio ? "notStarted" : "awaitingAudio",
                updatedAt: item.deletedAt ?? item.receivedAt,
                deleted: item.isDeleted
            )
        }
        let folders = manifest.folders.map { folder in
            LocalNetworkSyncFolderEntry(
                folderID: folder.folderID,
                parentID: folder.parentFolderID,
                path: folder.path.displaySummary,
                name: folder.name,
                colorToken: folder.colorToken?.rawValue,
                updatedAt: folder.updatedAt,
                revisionHash: LocalNetworkSyncMetadataHash.hash(folder),
                deleted: folder.isTrashed
            )
        }
        let studyItems = manifest.items.map { item in
            LocalNetworkSyncStudyItemEntry(
                itemID: item.itemID,
                kind: item.kind,
                title: item.title,
                folderIDs: item.folderIDs,
                recordingID: item.recordingID,
                updatedAt: item.updatedAt,
                revisionHash: LocalNetworkSyncMetadataHash.hash(item),
                deleted: item.isTrashed
            )
        }
        let artifacts = makeLocalNetworkSyncArtifacts(from: manifest)
        let device = LocalNetworkSyncDeviceSection(
            deviceID: localSyncDeviceID,
            deviceName: MacSystemInfoProvider.macName,
            platform: .Mac,
            generatedAt: generatedAt,
            lastKnownPeerRevision: syncStateStore.state.lastRemoteManifestHash,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )

        return LocalNetworkSyncInventory.make(
            device: device,
            recordings: recordings,
            folders: folders,
            studyItems: studyItems,
            artifacts: artifacts,
            studyManifest: manifest
        )
    }

    private func makeLocalNetworkSyncArtifacts(from manifest: StudyLibrarySyncManifest) -> [LocalNetworkSyncArtifactEntry] {
        var artifacts: [LocalNetworkSyncArtifactEntry] = []
        for item in manifest.items {
            let ownerID = item.recordingID ?? item.itemID
            appendLocalNetworkSyncArtifact(
                relativePath: item.transcriptMarkdownRelativePath,
                kind: .transcriptMarkdown,
                ownerID: ownerID,
                artifacts: &artifacts
            )
            appendLocalNetworkSyncArtifact(
                relativePath: item.transcriptRelativePath,
                kind: .transcriptJSON,
                ownerID: ownerID,
                artifacts: &artifacts
            )
            appendLocalNetworkSyncArtifact(
                relativePath: item.noteRelativePath,
                kind: item.noteRelativePath?.hasSuffix(".json") == true ? .noteJSON : .noteMarkdown,
                ownerID: ownerID,
                artifacts: &artifacts
            )
            appendLocalNetworkSyncArtifact(
                relativePath: item.audioRelativePath,
                kind: .audio,
                ownerID: ownerID,
                includeChecksum: false,
                artifacts: &artifacts
            )
        }
        return artifacts
    }

    private func appendLocalNetworkSyncArtifact(
        relativePath: String?,
        kind: LocalNetworkSyncArtifactKind,
        ownerID: String,
        includeChecksum: Bool = true,
        artifacts: inout [LocalNetworkSyncArtifactEntry]
    ) {
        guard let relativePath,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = try? LocalNetworkSyncArtifactFileService.safeFileURL(
                rootURL: recordingFileStore.libraryRootURL,
                logicalPathToken: relativePath
              ),
              FileManager.default.fileExists(atPath: url.path),
              let metadata = LocalNetworkSyncArtifactFileService.metadata(for: url) else {
            return
        }

        let checksum = includeChecksum ? try? LocalNetworkSyncArtifactFileService.sha256Hex(fileURL: url) : nil
        let artifactID = LocalNetworkSyncArtifactID.make(kind: kind, ownerID: ownerID, logicalPathToken: relativePath)
        artifacts.append(
            LocalNetworkSyncArtifactEntry(
                artifactID: artifactID,
                kind: kind,
                ownerID: ownerID,
                checksum: checksum,
                size: metadata.size,
                updatedAt: metadata.updatedAt,
                availability: .local,
                logicalPathToken: relativePath
            )
        )
    }

    @MainActor
    private func markDeviceOnline(
        device: PairedDevice,
        displayName: String,
        syncStatus: String?
    ) -> DeviceConnectionStatus {
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return deviceConnectionStatusStore.markConnected(
            deviceID: device.id,
            displayName: normalizedDisplayName.isEmpty ? device.deviceName : normalizedDisplayName,
            lastSyncAt: syncStateStore.state.lastSuccessfulSyncAt,
            lastSyncStatus: syncStatus ?? syncStateStore.state.lastError ?? syncStateStore.state.lastSuccessfulSyncAt.map { _ in "已同步" }
        )
    }

    private var localSyncDeviceID: String {
        let fingerprint = identityManager.status.displayFingerprint
        guard fingerprint != "未生成", !fingerprint.isEmpty else {
            return "mac-local"
        }
        return "mac-\(String(fingerprint.prefix(16)))"
    }

    private static let recordingMetadataDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let syncJSONDecoder: JSONDecoder = {
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
