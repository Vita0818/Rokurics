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

struct SecureLocalHTTPRouteResponse: Sendable {
    let statusCode: Int
    let reason: String
    let bodyData: Data
}

struct SecureConnectionDiagnosticEvent: Sendable {
    let phase: String
    let listenerState: String?
    let activePort: Int?
    let routeReceivedAt: Date?
    let routePath: String?
    let heartbeatSequence: UInt64?
    let requestDeviceIDPrefix: String?
    let verifierStartedAt: Date?
    let verifierSucceeded: Bool?
    let verifierFailed: Bool?
    let markDeviceSeenCalled: Bool?
    let pairedDeviceLastSeenBefore: Date?
    let pairedDeviceLastSeenAfter: Date?
    let connectionStatusStoreUpdated: Bool?
    let uiObservedLastSeenAt: Date?
    let syncRunID: String?
    let errorCode: String?
    let errorMessage: String?
    let errorCategory: String?
}

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
    let onRecordingAccepted: (String, SyncTriggerReason) -> Void

    func metadataUploadResponse(
        method: String,
        path: String,
        headers: [String: String],
        body: Data
    ) async -> SecureLocalHTTPRouteResponse {
        print("[RokuricsRecordingUpload] metadata upload request received")
        let traceID = UploadFlightRecorder.traceID(from: headers)
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "uploadRouteHandlerEntered",
            traceID: traceID,
            recordingID: Self.normalizedHeaders(headers)["x-rokurics-recording-id"],
            eventResult: "begin",
            httpPath: path,
            bodyBytes: body.count
        )

        switch await requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let metadata = try Self.recordingMetadataDecoder.decode(IncomingRecordingMetadata.self, from: body)
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "metadataPayloadDecoded",
                    traceID: traceID,
                    recordingID: metadata.id,
                    eventResult: "success",
                    httpPath: path,
                    bodyBytes: body.count
                )
                let result = try recordingFileStore.saveMetadata(metadata, sourceDevice: device, uploadTraceID: traceID)
                onRecordingAccepted(result.recordingID, .studyLibraryMetadataChanged)
                print("[RokuricsRecordingUpload] metadata accepted: \(result.recordingID)")
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "uploadRouteHandlerResponded",
                    traceID: traceID,
                    recordingID: result.recordingID,
                    eventResult: "success",
                    httpPath: path,
                    httpStatus: 200,
                    macReceiveState: result.receiveStatus,
                    audioRelativePathSet: result.audioFileName != nil
                )
                return Self.successResponse(message: "recording metadata received", result: result)
            } catch let error as MacRecordingFileStoreError {
                print("[RokuricsRecordingUpload] metadata rejected: \(error.localizedDescription)")
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "uploadRouteHandlerResponded",
                    traceID: traceID,
                    recordingID: Self.normalizedHeaders(headers)["x-rokurics-recording-id"],
                    eventResult: "fail",
                    reasonCode: error.localizedDescription,
                    httpPath: path,
                    httpStatus: error.responseStatusCode,
                    errorDomain: "MacRecordingFileStoreError",
                    safeErrorMessage: error.localizedDescription
                )
                return Self.errorResponse(
                    statusCode: error.responseStatusCode,
                    reason: error.responseReason,
                    error: error.localizedDescription
                )
            } catch {
                print("[RokuricsRecordingUpload] metadata rejected: bad_metadata")
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "uploadRouteHandlerResponded",
                    traceID: traceID,
                    recordingID: Self.normalizedHeaders(headers)["x-rokurics-recording-id"],
                    eventResult: "fail",
                    reasonCode: "bad_metadata",
                    httpPath: path,
                    httpStatus: 400,
                    errorDomain: "RecordingUploadRouteHandler"
                )
                return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "bad_metadata")
            }
        case .rejected(let reason):
            print("[RokuricsRecordingUpload] metadata rejected: \(reason)")
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "uploadRouteHandlerResponded",
                traceID: traceID,
                recordingID: Self.normalizedHeaders(headers)["x-rokurics-recording-id"],
                eventResult: "fail",
                reasonCode: reason,
                httpPath: path,
                httpStatus: reason == "body_too_large" ? 413 : 400,
                verifierResult: "rejected"
            )
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
    ) async -> SecureLocalHTTPRouteResponse {
        print("[RokuricsRecordingUpload] audio upload request received")
        let traceID = UploadFlightRecorder.traceID(from: headers)
        let normalizedHeaders = Self.normalizedHeaders(headers)
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "uploadRouteHandlerEntered",
            traceID: traceID,
            recordingID: normalizedHeaders["x-rokurics-recording-id"],
            eventResult: "begin",
            httpPath: path,
            bodyBytes: body.count
        )

        switch await requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                guard let recordingID = normalizedHeaders["x-rokurics-recording-id"],
                      !recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return Self.errorResponse(statusCode: 400, reason: "Bad Request", error: "missing_recording_id")
                }
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "audioRouteRecordingIDParsed",
                    traceID: traceID,
                    recordingID: recordingID,
                    eventResult: "success",
                    httpPath: path,
                    bodyBytes: body.count
                )

                let result = try await recordingFileStore.saveAudio(
                    body: body,
                    recordingID: recordingID,
                    requestedFileName: normalizedHeaders["x-rokurics-filename"],
                    sourceDevice: device,
                    uploadTraceID: traceID
                )
                onRecordingAccepted(result.recordingID, .macAudioReceiveFinalized)
                print("[RokuricsRecordingUpload] audio accepted: \(result.recordingID)")
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "uploadRouteHandlerResponded",
                    traceID: traceID,
                    recordingID: result.recordingID,
                    eventResult: "success",
                    httpPath: path,
                    httpStatus: 200,
                    macReceiveState: result.receiveStatus,
                    audioRelativePathSet: result.audioFileName != nil
                )
                return Self.successResponse(message: "recording audio received", result: result)
            } catch let error as MacRecordingFileStoreError {
                print("[RokuricsRecordingUpload] audio rejected: \(error.localizedDescription)")
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "audioReceiveFailedWithReason",
                    traceID: traceID,
                    recordingID: normalizedHeaders["x-rokurics-recording-id"],
                    eventResult: "fail",
                    reasonCode: error.localizedDescription,
                    httpPath: path,
                    httpStatus: error.responseStatusCode,
                    errorDomain: "MacRecordingFileStoreError",
                    safeErrorMessage: error.localizedDescription
                )
                return Self.errorResponse(
                    statusCode: error.responseStatusCode,
                    reason: error.responseReason,
                    error: error.localizedDescription
                )
            } catch {
                print("[RokuricsRecordingUpload] audio rejected: audio_storage_failed")
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "audioReceiveFailedWithReason",
                    traceID: traceID,
                    recordingID: normalizedHeaders["x-rokurics-recording-id"],
                    eventResult: "fail",
                    reasonCode: "audio_storage_failed",
                    httpPath: path,
                    httpStatus: 500,
                    errorDomain: "RecordingUploadRouteHandler"
                )
                return Self.errorResponse(statusCode: 500, reason: "Internal Server Error", error: "audio_storage_failed")
            }
        case .rejected(let reason):
            print("[RokuricsRecordingUpload] audio rejected: \(reason)")
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioReceiveFailedWithReason",
                traceID: traceID,
                recordingID: normalizedHeaders["x-rokurics-recording-id"],
                eventResult: "fail",
                reasonCode: reason,
                httpPath: path,
                httpStatus: reason == "body_too_large" ? 413 : 400,
                verifierResult: "rejected"
            )
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
    ) async -> SecureLocalHTTPRouteResponse {
        switch await requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let request = try Self.recordingMetadataDecoder.decode(ResumableAudioUploadStartRequest.self, from: body)
                let response = try await recordingFileStore.startResumableAudioUpload(request, sourceDevice: device)
                onRecordingAccepted(request.recordingID, .syncStatusRefreshRequested)
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
    ) async -> SecureLocalHTTPRouteResponse {
        switch await requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let request = try Self.recordingMetadataDecoder.decode(ResumableAudioUploadStatusRequest.self, from: body)
                let response = try await recordingFileStore.resumableAudioUploadStatus(request, sourceDevice: device)
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
    ) async -> SecureLocalHTTPRouteResponse {
        switch await requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
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

                let response = try await recordingFileStore.appendResumableAudioChunk(
                    recordingID: recordingID,
                    sessionID: sessionID,
                    offset: offset,
                    length: length,
                    chunkSHA256: chunkSHA256,
                    totalSHA256: totalSHA256,
                    body: body,
                    sourceDevice: device
                )
                onRecordingAccepted(recordingID, .syncStatusRefreshRequested)
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
    ) async -> SecureLocalHTTPRouteResponse {
        switch await requestVerifier.verify(method: method, path: path, headers: headers, body: body) {
        case .accepted(let device):
            do {
                let request = try Self.recordingMetadataDecoder.decode(ResumableAudioUploadFinalizeRequest.self, from: body)
                let response = try await recordingFileStore.finalizeResumableAudioUpload(request, sourceDevice: device)
                onRecordingAccepted(request.recordingID, .macAudioReceiveFinalized)
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
                let syncStartSignal = statusStore.consumePendingSyncStartSignal(deviceID: device.id)
                let syncRequested = syncStartSignal != nil
                let response = ConnectionHeartbeatResponse(
                    ok: true,
                    disposition: "ok",
                    peerDeviceID: localPeerDeviceID,
                    serverTime: now,
                    receivedSequenceNumber: request.sequenceNumber,
                    connectionStatusRevision: status.connectionStatusRevision ?? 0,
                    minimumSuggestedInterval: minimumSuggestedInterval,
                    syncRequested: syncRequested,
                    syncStartSignal: syncStartSignal,
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
        let syncRequested: Bool?
        let syncStartSignal: LocalNetworkSyncStartSignal?
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
                let syncStartSignal = statusStore?.consumePendingSyncStartSignal(deviceID: device.id)
                let syncRequested = syncStartSignal != nil
                let response = ProbeResponse(
                    ok: true,
                    disposition: "ok",
                    receivedSequenceNumber: request.sequenceNumber,
                    echoedClientPayload: request.clientPayload,
                    serverPayload: "rokurics-probe-ok",
                    serverTime: now,
                    syncRequested: syncRequested,
                    syncStartSignal: syncStartSignal
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

private nonisolated struct MacLocalNetworkSyncInventoryBackgroundInput {
    var manifest: StudyLibrarySyncManifest
    var inboxItems: [MacRecordingInboxItem]
    var existenceRecords: [CanonicalRecordingMetadataOnlyReceiveRecord]
    var rootURL: URL
    var recordingMetadataHashesByID: [String: String]
    var folderRevisionHashesByID: StudyFolderIDHashMap
    var studyItemRevisionHashesByID: StudyItemIDHashMap
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var diagnostics: CanonicalInventoryRuntimeDiagnostics
    var failures: [CanonicalInventoryRuntimeFailure]
}

private typealias StudyFolderIDHashMap = [StudyFolderID: String]
private typealias StudyItemIDHashMap = [StudyItemID: String]

private nonisolated struct MacLocalNetworkSyncBackgroundArtifactBuild {
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var hashComputedCount: Int
    var hashDurationMs: Int
}

private nonisolated enum MacLocalNetworkSyncBackgroundArtifactBuilder {
    static func makeArtifacts(
        from manifest: StudyLibrarySyncManifest,
        rootURL: URL,
        checksumRuntime: CanonicalChecksumRuntime,
        cacheDirectoryURL: URL,
        configuration: CanonicalInventoryRuntimeConfiguration,
        fileManager: FileManager = .default
    ) async -> MacLocalNetworkSyncBackgroundArtifactBuild {
        var artifacts: [LocalNetworkSyncArtifactEntry] = []
        var hashComputedCount = 0
        var hashDurationMs = 0
        for item in manifest.items {
            let ownerID = item.recordingID ?? item.itemID
            await appendArtifact(relativePath: item.receiveRelativePath, kind: .receiveJSON, ownerID: ownerID, rootURL: rootURL, checksumRuntime: checksumRuntime, cacheDirectoryURL: cacheDirectoryURL, configuration: configuration, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            await appendArtifact(relativePath: item.transcriptMarkdownRelativePath, kind: .transcriptMarkdown, ownerID: ownerID, rootURL: rootURL, checksumRuntime: checksumRuntime, cacheDirectoryURL: cacheDirectoryURL, configuration: configuration, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            await appendArtifact(relativePath: item.transcriptRelativePath, kind: .transcriptJSON, ownerID: ownerID, rootURL: rootURL, checksumRuntime: checksumRuntime, cacheDirectoryURL: cacheDirectoryURL, configuration: configuration, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
            await appendArtifact(
                relativePath: item.noteRelativePath,
                kind: item.noteRelativePath?.hasSuffix(".json") == true ? .noteJSON : .noteMarkdown,
                ownerID: ownerID,
                rootURL: rootURL,
                checksumRuntime: checksumRuntime,
                cacheDirectoryURL: cacheDirectoryURL,
                configuration: configuration,
                fileManager: fileManager,
                artifacts: &artifacts,
                hashComputedCount: &hashComputedCount,
                hashDurationMs: &hashDurationMs
            )
            await appendArtifact(relativePath: item.audioRelativePath, kind: .audio, ownerID: ownerID, rootURL: rootURL, checksumRuntime: checksumRuntime, cacheDirectoryURL: cacheDirectoryURL, configuration: configuration, includeChecksum: false, fileManager: fileManager, artifacts: &artifacts, hashComputedCount: &hashComputedCount, hashDurationMs: &hashDurationMs)
        }
        return MacLocalNetworkSyncBackgroundArtifactBuild(
            artifacts: artifacts,
            hashComputedCount: hashComputedCount,
            hashDurationMs: hashDurationMs
        )
    }

    private static func appendArtifact(
        relativePath: String?,
        kind: LocalNetworkSyncArtifactKind,
        ownerID: String,
        rootURL: URL,
        checksumRuntime: CanonicalChecksumRuntime,
        cacheDirectoryURL: URL,
        configuration: CanonicalInventoryRuntimeConfiguration,
        includeChecksum: Bool = true,
        fileManager: FileManager,
        artifacts: inout [LocalNetworkSyncArtifactEntry],
        hashComputedCount: inout Int,
        hashDurationMs: inout Int
    ) async {
        let fileURL: URL?
        if kind == .audio {
            fileURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: relativePath ?? "")
        } else {
            fileURL = try? LocalNetworkSyncArtifactFileService.safeFileURL(rootURL: rootURL, logicalPathToken: relativePath ?? "", kind: kind)
        }
        guard let relativePath,
              !relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = fileURL,
              fileManager.fileExists(atPath: url.path),
              let metadata = LocalNetworkSyncArtifactFileService.metadata(for: url) else {
            return
        }

        let checksum: String?
        if includeChecksum {
            let checksumResult = await checksumRuntime.checksum(
                fileURL: url,
                logicalToken: relativePath,
                nodeRole: .mac,
                cacheDirectoryURL: cacheDirectoryURL,
                configuration: configuration,
                metadataProvider: { _ in
                    CanonicalChecksumFileMetadata(byteSize: metadata.size, modifiedAt: metadata.updatedAt)
                }
            )
            checksum = checksumResult.sha256
            hashDurationMs += checksumResult.hashDurationMs
            if checksumResult.hashComputed {
                hashComputedCount += 1
            }
        } else {
            checksum = nil
        }

        artifacts.append(
            LocalNetworkSyncArtifactEntry(
                artifactID: LocalNetworkSyncArtifactID.make(kind: kind, ownerID: ownerID, logicalPathToken: relativePath),
                kind: kind,
                ownerID: ownerID,
                checksum: checksum,
                size: metadata.size,
                updatedAt: metadata.updatedAt,
                availability: .local,
                logicalPathToken: relativePath,
                localAvailability: .local,
                peerAvailability: nil,
                autoDownloadAllowed: kind.isAutoDownloadAllowed
            )
        )
    }
}

private nonisolated struct MacLocalNetworkSyncBackgroundStudyManifestBuilder {
    let fileManager: FileManager
    let rootURL: URL
    let inboxItems: [MacRecordingInboxItem]
    let deviceID: String
    let generatedAt: Date

    func build() -> StudyLibrarySyncManifest {
        let storedItems = loadAllStoredItemMetadata()
        let storedItemsByRecordingID = Dictionary(
            storedItems.compactMap { item -> (String, StudyItemMetadata)? in
                guard let recordingID = item.recordingID else {
                    return nil
                }
                return (recordingID, item)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let liveRecordingIDs = Set(inboxItems.map(\.id))

        var itemsByID: [StudyItemID: StudyItemMetadata] = [:]
        for inboxItem in inboxItems where !inboxItem.isDeleted {
            let fallback = StudyItemMetadata.defaultMetadata(for: inboxItem)
            let metadata = storedItemsByRecordingID[inboxItem.id]?.mergedWithCurrentInboxItem(inboxItem) ?? fallback
            itemsByID[metadata.itemID] = metadata
        }

        for item in storedItems where shouldIncludeStoredItem(item, liveRecordingIDs: liveRecordingIDs, alreadyLoaded: itemsByID) {
            itemsByID[item.itemID] = item
        }

        let noteStore = NoteStore(fileManager: fileManager, rootURL: rootURL)
        let items = itemsByID.values.map { item -> StudyItemMetadata in
            var sanitized = item.syncSanitized(modifiedByDeviceID: deviceID)
            attachNoteSummaryPreview(to: &sanitized, noteStore: noteStore)
            return sanitized
        }
        let folders = repairedFolders(loadAllFolderMetadata(), items: Array(itemsByID.values))
            .map { $0.syncSanitized(modifiedByDeviceID: deviceID) }
        let tombstones = makeSyncTombstones(items: items, folders: folders)
        return StudyLibrarySyncManifest.make(
            deviceID: deviceID,
            generatedAt: generatedAt,
            items: items,
            folders: folders,
            tombstones: tombstones,
            recordings: makeManifestRecordingEntries(
                inboxItems: inboxItems,
                itemsByRecordingID: storedItemsByRecordingID
            )
        )
    }

    private var studyURL: URL {
        rootURL.appendingPathComponent("study", isDirectory: true).standardizedFileURL
    }

    private var itemMetadataURL: URL {
        studyURL.appendingPathComponent("items", isDirectory: true).standardizedFileURL
    }

    private var legacyItemMetadataURL: URL {
        studyURL.appendingPathComponent("item-metadata", isDirectory: true).standardizedFileURL
    }

    private var folderMetadataURL: URL {
        studyURL.appendingPathComponent("folders", isDirectory: true).standardizedFileURL
    }

    private func loadAllStoredItemMetadata() -> [StudyItemMetadata] {
        loadMetadataFiles(from: itemMetadataURL, as: StudyItemMetadata.self)
            + loadMetadataFiles(from: legacyItemMetadataURL, as: StudyItemMetadata.self)
    }

    private func loadAllFolderMetadata() -> [StudyFolderMetadata] {
        loadMetadataFiles(from: folderMetadataURL, as: StudyFolderMetadata.self)
    }

    private func loadMetadataFiles<T: Decodable>(from directoryURL: URL, as type: T.Type) -> [T] {
        guard fileManager.fileExists(atPath: directoryURL.path),
              isInsideStudyDirectory(directoryURL),
              let urls = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "json" && isInsideStudyDirectory($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }
                return try? Self.jsonDecoder.decode(T.self, from: data)
            }
    }

    private func shouldIncludeStoredItem(
        _ item: StudyItemMetadata,
        liveRecordingIDs: Set<String>,
        alreadyLoaded: [StudyItemID: StudyItemMetadata]
    ) -> Bool {
        if alreadyLoaded[item.itemID] != nil {
            return false
        }
        if item.kind == .standaloneNote || item.recordingID == nil {
            return true
        }
        if item.customProperties["syncedMetadataOnly"] == "true" {
            return true
        }
        return item.recordingID.map { liveRecordingIDs.contains($0) } ?? false
    }

    private func repairedFolders(
        _ folders: [StudyFolderMetadata],
        items: [StudyItemMetadata]
    ) -> [StudyFolderMetadata] {
        let existingItemIDs = Set(items.map(\.itemID))
        var foldersByID = Dictionary(folders.map { ($0.folderID, $0) }, uniquingKeysWith: { first, _ in first })
        for (folderID, folder) in foldersByID {
            var repaired = folder
            repaired.itemIDs = StudyItemMetadata.uniqueIDs(repaired.itemIDs.filter { existingItemIDs.contains($0) })
            foldersByID[folderID] = repaired
        }
        for item in items {
            for folderID in item.folderIDs {
                guard var folder = foldersByID[folderID] else {
                    continue
                }
                if !folder.itemIDs.contains(item.itemID) {
                    folder.itemIDs.append(item.itemID)
                }
                foldersByID[folderID] = folder
            }
        }
        return foldersByID.values.sorted { left, right in
            if left.pathComponents == right.pathComponents {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            return left.pathComponents.lexicographicallyPrecedes(right.pathComponents) {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        }
    }

    private func makeSyncTombstones(
        items: [StudyItemMetadata],
        folders: [StudyFolderMetadata]
    ) -> [StudyLibrarySyncTombstone] {
        let itemTombstones = items.filter(\.isTrashed).map { item in
            StudyLibrarySyncTombstone(
                id: "item:\(item.itemID)",
                entityKind: .item,
                entityID: item.itemID,
                operation: .trash,
                updatedAt: item.trashedAt ?? item.updatedAt,
                modifiedByDeviceID: item.modifiedByDeviceID ?? deviceID
            )
        }
        let folderTombstones = folders.filter(\.isTrashed).map { folder in
            StudyLibrarySyncTombstone(
                id: "folder:\(folder.folderID)",
                entityKind: .folder,
                entityID: folder.folderID,
                operation: .trash,
                updatedAt: folder.trashedAt ?? folder.updatedAt,
                modifiedByDeviceID: folder.modifiedByDeviceID ?? deviceID
            )
        }
        return itemTombstones + folderTombstones
    }

    private func makeManifestRecordingEntries(
        inboxItems: [MacRecordingInboxItem],
        itemsByRecordingID: [String: StudyItemMetadata]
    ) -> [LocalNetworkSyncRecordingEntry] {
        inboxItems.map { item in
            let metadataHash = itemsByRecordingID[item.id].map(LocalNetworkSyncMetadataHash.hash)
            return LocalNetworkSyncRecordingEntry(
                recordingID: item.id,
                metadataHash: metadataHash,
                audioAvailable: item.hasAudio,
                audioChecksum: item.hasAudio ? item.audioChecksum : nil,
                audioSize: item.hasAudio ? item.fileSize : nil,
                uploadLedgerState: nil,
                receiveStatus: item.receiveStatus,
                processingStatus: item.hasAudio ? "notStarted" : "awaitingAudio",
                updatedAt: item.deletedAt ?? item.receivedAt,
                deleted: item.isDeleted,
                title: item.title,
                createdAt: item.receivedAt,
                tombstone: item.isDeleted,
                audioAvailability: item.hasAudio ? .local : .missing,
                uploadStatus: nil,
                transcriptionStatus: item.transcriptionStatus,
                noteStatus: item.noteStatus,
                sourceDeviceID: item.sourceDeviceID ?? deviceID,
                artifactRefs: nil,
                audioLogicalPathToken: item.hasAudio ? item.audioRelativePath : nil
            )
        }
    }

    private func attachNoteSummaryPreview(to item: inout StudyItemMetadata, noteStore: NoteStore) {
        item.customProperties.removeValue(forKey: "noteSummaryPreview")
        item.customProperties.removeValue(forKey: "noteKeyPointsPreview")

        guard let preview = noteStore.loadSummaryPreview(noteRelativePath: item.noteRelativePath),
              preview.isVisible else {
            return
        }
        let summary = preview.shortSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty {
            item.customProperties["noteSummaryPreview"] = summary
        }
        let keyPoints = preview.keyPoints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
        if !keyPoints.isEmpty {
            item.customProperties["noteKeyPointsPreview"] = keyPoints.joined(separator: "\n")
        }
    }

    private func isInsideStudyDirectory(_ url: URL) -> Bool {
        let studyPath = studyURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == studyPath || path.hasPrefix(studyPath + "/")
    }

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private nonisolated enum MacLocalNetworkSyncInventoryBackgroundIO {
    static func loadInboxItems(rootURL: URL) -> [MacRecordingInboxItem] {
        MacRecordingFileStore(rootURL: rootURL).loadInboxItems(includeDeleted: true)
    }

    static func loadExistenceRecords(rootURL: URL) -> [CanonicalRecordingMetadataOnlyReceiveRecord] {
        (try? MacCanonicalRecordingExistenceLedgerPort(rootURL: rootURL).loadRecords()) ?? []
    }

    static func probeUploadJobsLedger(rootURL: URL, fileManager: FileManager = .default) {
        let url = rootURL
            .appendingPathComponent("UploadJobs", isDirectory: true)
            .appendingPathComponent("upload-ledger")
            .appendingPathExtension("json")
            .standardizedFileURL
        _ = fileManager.fileExists(atPath: url.path)
    }

    static func uploadSessionCountForDiagnostics(rootURL: URL, fileManager: FileManager = .default) -> Int? {
        let sessionsURL = rootURL
            .appendingPathComponent("audio", isDirectory: true)
            .appendingPathComponent("upload-sessions", isDirectory: true)
            .standardizedFileURL
        guard fileManager.fileExists(atPath: sessionsURL.path),
              isInsideRoot(sessionsURL, rootURL: rootURL),
              let sessionDirectories = try? fileManager.contentsOfDirectory(
                at: sessionsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return 0
        }
        return sessionDirectories.filter { directoryURL in
            guard isInsideRoot(directoryURL.standardizedFileURL, rootURL: sessionsURL) else {
                return false
            }
            let sessionURL = directoryURL
                .appendingPathComponent("session.json", isDirectory: false)
                .standardizedFileURL
            return isInsideRoot(sessionURL, rootURL: sessionsURL)
                && fileManager.fileExists(atPath: sessionURL.path)
        }.count
    }

    private static func isInsideRoot(_ url: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }
}

nonisolated struct MacInventoryCanonicalBuildPolicy {
    let mode: CanonicalKernelSwitchMode
    let skipReason: String?
    let buildsCanonicalFacts: Bool
    let runsShadowSeams: Bool
    let runsDecisionSeams: Bool
    let runsNoCommitSeams: Bool
    let runsNonAudioApplySeams: Bool
    let runsAudioUploadSeams: Bool
    let runsReadSeams: Bool

    var runsAnySeam: Bool {
        runsShadowSeams
            || runsDecisionSeams
            || runsNoCommitSeams
            || runsNonAudioApplySeams
            || runsAudioUploadSeams
            || runsReadSeams
    }

    static func make(mode: CanonicalKernelSwitchMode) -> MacInventoryCanonicalBuildPolicy {
        switch mode {
        case .oldKernel:
            return MacInventoryCanonicalBuildPolicy(
                mode: mode,
                skipReason: "oldKernel",
                buildsCanonicalFacts: false,
                runsShadowSeams: false,
                runsDecisionSeams: false,
                runsNoCommitSeams: false,
                runsNonAudioApplySeams: false,
                runsAudioUploadSeams: false,
                runsReadSeams: false
            )
        case .blocked:
            return MacInventoryCanonicalBuildPolicy(
                mode: mode,
                skipReason: "blocked",
                buildsCanonicalFacts: false,
                runsShadowSeams: false,
                runsDecisionSeams: false,
                runsNoCommitSeams: false,
                runsNonAudioApplySeams: false,
                runsAudioUploadSeams: false,
                runsReadSeams: false
            )
        case .diagnosticsOnly, .canonicalShadow:
            return MacInventoryCanonicalBuildPolicy(
                mode: mode,
                skipReason: nil,
                buildsCanonicalFacts: true,
                runsShadowSeams: true,
                runsDecisionSeams: true,
                runsNoCommitSeams: true,
                runsNonAudioApplySeams: false,
                runsAudioUploadSeams: false,
                runsReadSeams: false
            )
        case .canonicalDecisionOnly:
            return MacInventoryCanonicalBuildPolicy(
                mode: mode,
                skipReason: nil,
                buildsCanonicalFacts: true,
                runsShadowSeams: false,
                runsDecisionSeams: true,
                runsNoCommitSeams: false,
                runsNonAudioApplySeams: false,
                runsAudioUploadSeams: false,
                runsReadSeams: false
            )
        case .canonicalApplyNoAudio:
            return MacInventoryCanonicalBuildPolicy(
                mode: mode,
                skipReason: nil,
                buildsCanonicalFacts: true,
                runsShadowSeams: false,
                runsDecisionSeams: true,
                runsNoCommitSeams: false,
                runsNonAudioApplySeams: true,
                runsAudioUploadSeams: false,
                runsReadSeams: false
            )
        case .canonicalFullSync:
            return MacInventoryCanonicalBuildPolicy(
                mode: mode,
                skipReason: nil,
                buildsCanonicalFacts: true,
                runsShadowSeams: true,
                runsDecisionSeams: true,
                runsNoCommitSeams: true,
                runsNonAudioApplySeams: true,
                runsAudioUploadSeams: true,
                runsReadSeams: true
            )
        }
    }
}

private nonisolated struct MacInventoryCanonicalBuildInput: @unchecked Sendable {
    var manifest: StudyLibrarySyncManifest
    var inboxItems: [MacRecordingInboxItem]
    var recordings: [LocalNetworkSyncRecordingEntry]
    var artifacts: [LocalNetworkSyncArtifactEntry]
    var nodeID: String
    var generatedAt: Date
}

private nonisolated struct MacInventoryCanonicalSnapshot: Sendable {
    var manifest: CanonicalManifest
    var coverage: CanonicalInventoryCoverageReport
    var buildDurationMs: Int
    var canonicalObjectCount: Int
    var canonicalArtifactCount: Int
    var recordingObjectCount: Int
    var libraryObjectCount: Int
    var tombstoneObjectCount: Int
    var unsupportedObjectCount: Int
    var mainActorBuildAttemptCount: Int
    var builtOffMain: Bool
}

private nonisolated struct MacInventoryRequestBuildContext {
    let requestID: String
    private(set) var canonicalSnapshot: MacInventoryCanonicalSnapshot?
    private(set) var fileRuntimeSnapshot: CanonicalFileRuntimeSnapshot?
    private(set) var fileRuntimeManifest: CanonicalFileManifestRuntimeResult?
    private(set) var fileRuntimeBuildCount = 0
    private(set) var canonicalBuildSkippedCount = 0
    private(set) var canonicalBuildReusedCount = 0
    private(set) var duplicateCanonicalBuildPreventedCount = 0

    mutating func markCanonicalSkipped() {
        canonicalBuildSkippedCount += 1
    }

    mutating func storeCanonicalSnapshot(_ snapshot: MacInventoryCanonicalSnapshot) {
        canonicalSnapshot = snapshot
    }

    mutating func storeFileRuntime(
        snapshot: CanonicalFileRuntimeSnapshot,
        manifest: CanonicalFileManifestRuntimeResult
    ) {
        fileRuntimeSnapshot = snapshot
        fileRuntimeManifest = manifest
        fileRuntimeBuildCount += 1
    }

    mutating func sharedCanonicalSnapshotForSeams() -> MacInventoryCanonicalSnapshot? {
        guard let snapshot = canonicalSnapshot else {
            return nil
        }
        canonicalBuildReusedCount += 1
        duplicateCanonicalBuildPreventedCount += 1
        return snapshot
    }
}

final class SecureLocalHTTPSServer {
    typealias ReadyHandler = @Sendable () -> Void
    typealias FailedHandler = @Sendable (String) -> Void
    typealias PairingChangedHandler = @Sendable () -> Void
    typealias UploadAcceptedHandler = @Sendable (String) -> Void
    typealias RecordingAcceptedHandler = @Sendable (String, SyncTriggerReason) -> Void
    typealias ConnectionDiagnosticHandler = @Sendable (SecureConnectionDiagnosticEvent) -> Void

    private struct HTTPRequest: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private struct HTTPHeaderRequest: Sendable {
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

    private struct DeviceUnpairRequest: Decodable {
        let deviceID: String
        let reason: String?
        let requestedAt: Date?
    }

    private struct DeviceUnpairResponse: Encodable {
        let ok: Bool
        let disposition: String
        let deviceID: String
        let error: String?
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
    private let canonicalShadowMigrationConfiguration: CanonicalShadowMigrationConfiguration
    private let canonicalSingleDomainShadowConfiguration: CanonicalSingleDomainShadowConfiguration
    private let canonicalV8CutoverAppSeamConfiguration: CanonicalCutoverAppSeamConfiguration
    private let canonicalGeneratedArtifactCutoverAppSeamConfiguration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration
    private let canonicalGeneratedArtifactReadSideConfiguration: CanonicalGeneratedArtifactReadSideConfiguration
    private let canonicalLibraryMetadataCutoverAppSeamConfiguration: CanonicalLibraryMetadataCutoverAppSeamConfiguration
    private let canonicalLibraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration
    private let canonicalLibraryMetadataReadSideCutoverConfiguration: CanonicalLibraryMetadataReadSideCutoverConfiguration
    private let canonicalAudioUploadCutoverAppSeamConfiguration: CanonicalAudioUploadCutoverAppSeamConfiguration
    private let canonicalTombstoneConflictCutoverAppSeamConfiguration: CanonicalTombstoneConflictCutoverAppSeamConfiguration
    private let canonicalSyncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration
    private let canonicalApplyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration
    private let canonicalExistenceApplyRuntimeConfiguration: CanonicalExistenceApplyRuntimeConfiguration
    private let canonicalReadRuntimeConfiguration: CanonicalReadRuntimeConfiguration
    private let canonicalKernelMode: CanonicalKernelSwitchMode
    private let canonicalRecordingExistenceApplyPort: (any MacCanonicalRecordingExistenceApplyPort)?
    private let canonicalLiveReadOnlyTransportProbePolicy: CanonicalLiveReadOnlyTransportProbePolicy
    private let canonicalRecordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)?
    private let canonicalGeneratedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)?
    private let canonicalLibraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)?
    private let canonicalTombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)?
    private let canonicalAudioUploadCutoverExecutor: MacAudioUploadCutoverExecutor?
    private let canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime
    private let canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime
    private let canonicalConnectionRuntime: CanonicalConnectionRuntime
    private let onReady: ReadyHandler
    private let onFailed: FailedHandler
    private let onPairingChanged: PairingChangedHandler
    private let onUploadAccepted: UploadAcceptedHandler
    private let onRecordingAccepted: RecordingAcceptedHandler
    private let onConnectionDiagnostic: ConnectionDiagnosticHandler
    private let queue = DispatchQueue(label: "RokuricsMac.SecureLocalHTTPSServer")
    private let backgroundWriteQueue = DispatchQueue(label: "RokuricsMac.SecureLocalHTTPSServer.BackgroundWrite", qos: .utility)
    private let maxHeaderBytes = 16 * 1024
    private let maxAllowedBodyBytes = MacRecordingFileStore.audioMaxBytes
    private let syncArtifactChunkBytes = 2 * 1024 * 1024
    private let canonicalChecksumRuntime = CanonicalChecksumRuntime()
    private let inventoryRuntimeConfiguration = CanonicalInventoryRuntimeConfiguration()
    private var listener: NWListener?
    private var activeConnections: [UUID: NWConnection] = [:]
    private let listenerStateLock = NSLock()
    private var listenerIsReady = false
    private var listenerActivePort: Int?
    private var listenerAddressInUseRetryAttempted = false

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
        canonicalLibraryMetadataDebugPilotConfiguration: CanonicalLibraryMetadataDebugPilotConfiguration = .disabled,
        canonicalRecordingMetadataCutoverExecutor: (any CanonicalRecordingMetadataCutoverExecutor)? = nil,
        canonicalGeneratedArtifactCutoverExecutor: (any CanonicalGeneratedArtifactCutoverExecutor)? = nil,
        canonicalLibraryMetadataCutoverExecutor: (any CanonicalLibraryMetadataCutoverExecutor)? = nil,
        canonicalTombstoneConflictCutoverExecutor: (any CanonicalTombstoneConflictCutoverExecutor)? = nil,
        onReady: @escaping ReadyHandler,
        onFailed: @escaping FailedHandler,
        onPairingChanged: @escaping PairingChangedHandler,
        onUploadAccepted: @escaping UploadAcceptedHandler,
        onRecordingAccepted: @escaping RecordingAcceptedHandler,
        onConnectionDiagnostic: @escaping ConnectionDiagnosticHandler = { _ in },
        canonicalShadowMigrationConfiguration: CanonicalShadowMigrationConfiguration = .disabled,
        canonicalSingleDomainShadowConfiguration: CanonicalSingleDomainShadowConfiguration = .disabled,
        canonicalV8CutoverAppSeamConfiguration: CanonicalCutoverAppSeamConfiguration = .disabled,
        canonicalGeneratedArtifactCutoverAppSeamConfiguration: CanonicalGeneratedArtifactCutoverAppSeamConfiguration = .disabled,
        canonicalGeneratedArtifactReadSideConfiguration: CanonicalGeneratedArtifactReadSideConfiguration = .disabled,
        canonicalLibraryMetadataCutoverAppSeamConfiguration: CanonicalLibraryMetadataCutoverAppSeamConfiguration = .disabled,
        canonicalLibraryMetadataReadSideCutoverConfiguration: CanonicalLibraryMetadataReadSideCutoverConfiguration = .disabled,
        canonicalAudioUploadCutoverAppSeamConfiguration: CanonicalAudioUploadCutoverAppSeamConfiguration = .disabled,
        canonicalTombstoneConflictCutoverAppSeamConfiguration: CanonicalTombstoneConflictCutoverAppSeamConfiguration = .disabled,
        canonicalSyncRuntimeConfiguration: CanonicalSyncRuntimeConfiguration = .disabled,
        canonicalApplyRuntimeConfiguration: CanonicalApplyRuntimeConfiguration = .disabled,
        canonicalExistenceApplyRuntimeConfiguration: CanonicalExistenceApplyRuntimeConfiguration = .disabled,
        canonicalReadRuntimeConfiguration: CanonicalReadRuntimeConfiguration = .disabled,
        canonicalKernelMode: CanonicalKernelSwitchMode = .canonicalFullSync,
        canonicalRecordingExistenceApplyPort: (any MacCanonicalRecordingExistenceApplyPort)? = nil,
        canonicalLiveReadOnlyTransportProbePolicy: CanonicalLiveReadOnlyTransportProbePolicy = .disabled,
        canonicalAudioUploadCutoverExecutor: MacAudioUploadCutoverExecutor? = nil,
        canonicalStatusTruthRuntime: CanonicalStatusTruthRuntime? = nil,
        canonicalStatusExchangeRuntime: CanonicalStatusExchangeRuntime? = nil,
        canonicalConnectionRuntime: CanonicalConnectionRuntime? = nil
    ) {
        let resolvedStatusTruthRuntime = canonicalStatusTruthRuntime ?? CanonicalStatusTruthRuntime()
        let resolvedConnectionRuntime = canonicalConnectionRuntime ?? CanonicalConnectionRuntime(
            configuration: .disabled,
            localNode: CanonicalNodeIdentity(
                nodeID: CanonicalNodeID("mac-local"),
                role: .mac,
                displayName: "Rokurics Mac"
            )
        )
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
        self.canonicalShadowMigrationConfiguration = canonicalShadowMigrationConfiguration
        self.canonicalSingleDomainShadowConfiguration = canonicalSingleDomainShadowConfiguration
        self.canonicalV8CutoverAppSeamConfiguration = canonicalV8CutoverAppSeamConfiguration
        self.canonicalGeneratedArtifactCutoverAppSeamConfiguration = canonicalGeneratedArtifactCutoverAppSeamConfiguration
        self.canonicalGeneratedArtifactReadSideConfiguration = canonicalGeneratedArtifactReadSideConfiguration
        self.canonicalLibraryMetadataCutoverAppSeamConfiguration = canonicalLibraryMetadataCutoverAppSeamConfiguration
        self.canonicalLibraryMetadataDebugPilotConfiguration = canonicalLibraryMetadataDebugPilotConfiguration
        self.canonicalLibraryMetadataReadSideCutoverConfiguration = canonicalLibraryMetadataReadSideCutoverConfiguration
        self.canonicalAudioUploadCutoverAppSeamConfiguration = canonicalAudioUploadCutoverAppSeamConfiguration
        self.canonicalTombstoneConflictCutoverAppSeamConfiguration = canonicalTombstoneConflictCutoverAppSeamConfiguration
        self.canonicalSyncRuntimeConfiguration = canonicalSyncRuntimeConfiguration
        self.canonicalApplyRuntimeConfiguration = canonicalApplyRuntimeConfiguration
        self.canonicalExistenceApplyRuntimeConfiguration = canonicalExistenceApplyRuntimeConfiguration
        self.canonicalReadRuntimeConfiguration = canonicalReadRuntimeConfiguration
        self.canonicalKernelMode = canonicalKernelMode
        self.canonicalRecordingExistenceApplyPort = canonicalRecordingExistenceApplyPort
        self.canonicalLiveReadOnlyTransportProbePolicy = canonicalLiveReadOnlyTransportProbePolicy
        self.canonicalRecordingMetadataCutoverExecutor = canonicalRecordingMetadataCutoverExecutor
        self.canonicalGeneratedArtifactCutoverExecutor = canonicalGeneratedArtifactCutoverExecutor
        self.canonicalLibraryMetadataCutoverExecutor = canonicalLibraryMetadataCutoverExecutor
        self.canonicalTombstoneConflictCutoverExecutor = canonicalTombstoneConflictCutoverExecutor
        self.canonicalAudioUploadCutoverExecutor = canonicalAudioUploadCutoverExecutor
        self.canonicalStatusTruthRuntime = resolvedStatusTruthRuntime
        self.canonicalStatusExchangeRuntime = canonicalStatusExchangeRuntime ?? CanonicalStatusExchangeRuntime(
            nodeID: CanonicalNodeID("mac-local"),
            truthRuntime: resolvedStatusTruthRuntime
        )
        self.canonicalConnectionRuntime = resolvedConnectionRuntime
        self.onReady = onReady
        self.onFailed = onFailed
        self.onPairingChanged = onPairingChanged
        self.onUploadAccepted = onUploadAccepted
        self.onRecordingAccepted = onRecordingAccepted
        self.onConnectionDiagnostic = onConnectionDiagnostic
        studyLibraryStore.setCanonicalReadRuntimeConfiguration(canonicalReadRuntimeConfiguration)
    }

    var canonicalStatusTruthReadPathAvailable: Bool {
        true
    }

    func produceCanonicalStatusFact(_ fact: CanonicalStatusFact) async -> CanonicalStatusFactMergeResult {
        await studyLibraryStore.produceCanonicalStatusFact(fact)
    }

    func canonicalEffectiveStatus(for facts: [CanonicalStatusFact]) async -> CanonicalEffectiveSyncStatus {
        await canonicalStatusTruthRuntime.effectiveStatus(for: facts)
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
        print("[RokuricsHTTPS] requiredLocalEndpoint: nil")
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw SecureHTTPSServerError.tlsIdentityUnavailable("Invalid HTTPS port.")
        }

        listenerAddressInUseRetryAttempted = false
        cancelCurrentListenerForRestart()
        do {
            try startListener(parameters: parameters, endpointPort: endpointPort)
        } catch {
            guard isAddressInUse(error), !listenerAddressInUseRetryAttempted else {
                throw error
            }
            listenerAddressInUseRetryAttempted = true
            emitConnectionDiagnostic(
                phase: "listener_address_in_use_retry",
                listenerState: "retrying",
                errorCode: "address_in_use",
                errorMessage: "HTTPS listener bind failed with address in use; retrying once."
            )
            cancelCurrentListenerForRestart()
            try startListener(parameters: parameters, endpointPort: endpointPort)
        }
    }

    private func startListener(parameters: NWParameters, endpointPort: NWEndpoint.Port) throws {
        parameters.allowLocalEndpointReuse = true
        print("[RokuricsHTTPS] allowLocalEndpointReuse: true")
        print("[RokuricsHTTPS] listener starting on port \(port)")
        let newListener = try NWListener(using: parameters, on: endpointPort)
        listener = newListener
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self else {
                return
            }
            guard let newListener, self.listener === newListener else {
                return
            }

            switch state {
            case .ready:
                let activePort = newListener.port.map { Int($0.rawValue) } ?? self.port
                self.updateListenerState(isReady: true, activePort: activePort)
                print("[RokuricsHTTPS] listener state: ready")
                self.emitConnectionDiagnostic(phase: "listener_ready", listenerState: "ready", activePort: activePort)
                self.onReady()
            case .failed(let error):
                self.updateListenerState(isReady: false, activePort: nil)
                let message = "HTTPS listener failed: \(error)"
                if self.isAddressInUse(error), !self.listenerAddressInUseRetryAttempted {
                    self.listenerAddressInUseRetryAttempted = true
                    print("[RokuricsHTTPS][WARN] \(message); retrying listener once")
                    self.emitConnectionDiagnostic(
                        phase: "listener_address_in_use_retry",
                        listenerState: "retrying",
                        errorCode: "address_in_use",
                        errorMessage: message
                    )
                    self.cancelCurrentListenerForRestart()
                    self.queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self else {
                            return
                        }
                        do {
                            try self.startListener(parameters: parameters, endpointPort: endpointPort)
                        } catch {
                            let retryMessage = "HTTPS listener retry failed: \(error)"
                            print("[RokuricsHTTPS][ERROR] \(retryMessage)")
                            self.emitConnectionDiagnostic(
                                phase: "listener_retry_failed",
                                listenerState: "failed",
                                errorCode: self.isAddressInUse(error) ? "address_in_use" : "server_unreachable",
                                errorMessage: retryMessage
                            )
                            self.onFailed(retryMessage)
                        }
                    }
                    return
                }
                print("[RokuricsHTTPS][ERROR] \(message)")
                self.emitConnectionDiagnostic(
                    phase: "listener_failed",
                    listenerState: "failed",
                    errorCode: self.isAddressInUse(error) ? "address_in_use" : "server_unreachable",
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
        newListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        newListener.start(queue: queue)
    }

    func stop() {
        updateListenerState(isReady: false, activePort: nil)
        listenerAddressInUseRetryAttempted = false
        listener?.cancel()
        listener = nil
        activeConnections.values.forEach { $0.cancel() }
        activeConnections.removeAll()
        emitConnectionDiagnostic(phase: "listener_stop_requested", listenerState: "cancelled")
        print("[RokuricsHTTPS] secure server stopped")
    }

    private func cancelCurrentListenerForRestart() {
        updateListenerState(isReady: false, activePort: nil)
        listener?.cancel()
        listener = nil
    }

    private func isAddressInUse(_ error: Error) -> Bool {
        if let nwError = error as? NWError {
            return isAddressInUse(nwError)
        }
        return errorTextIndicatesAddressInUse(error)
    }

    private func isAddressInUse(_ error: NWError) -> Bool {
        switch error {
        case .posix(let code):
            return code == .EADDRINUSE || code.rawValue == 48
        default:
            return errorTextIndicatesAddressInUse(error)
        }
    }

    private func errorTextIndicatesAddressInUse(_ error: Error) -> Bool {
        let text = "\(error) \(error.localizedDescription)".lowercased()
        return text.contains("address already in use")
            || text.contains("eaddrinuse")
            || text.contains("posixerrorcode 48")
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
        routeReceivedAt: Date? = nil,
        routePath: String? = nil,
        heartbeatSequence: UInt64? = nil,
        requestDeviceIDPrefix: String? = nil,
        verifierStartedAt: Date? = nil,
        verifierSucceeded: Bool? = nil,
        verifierFailed: Bool? = nil,
        markDeviceSeenCalled: Bool? = nil,
        pairedDeviceLastSeenBefore: Date? = nil,
        pairedDeviceLastSeenAfter: Date? = nil,
        connectionStatusStoreUpdated: Bool? = nil,
        uiObservedLastSeenAt: Date? = nil,
        syncRunID: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        errorCategory: String? = nil
    ) {
        onConnectionDiagnostic(
            SecureConnectionDiagnosticEvent(
                phase: phase,
                listenerState: listenerState,
                activePort: activePort,
                routeReceivedAt: routeReceivedAt,
                routePath: routePath,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: requestDeviceIDPrefix,
                verifierStartedAt: verifierStartedAt,
                verifierSucceeded: verifierSucceeded,
                verifierFailed: verifierFailed,
                markDeviceSeenCalled: markDeviceSeenCalled,
                pairedDeviceLastSeenBefore: pairedDeviceLastSeenBefore,
                pairedDeviceLastSeenAfter: pairedDeviceLastSeenAfter,
                connectionStatusStoreUpdated: connectionStatusStoreUpdated,
                uiObservedLastSeenAt: uiObservedLastSeenAt,
                syncRunID: syncRunID,
                errorCode: errorCode,
                errorMessage: errorMessage,
                errorCategory: errorCategory
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
        let pathWithoutQuery = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        
        let path: String
        if pathWithoutQuery.hasPrefix("http://") || pathWithoutQuery.hasPrefix("https://") {
            if let url = URL(string: pathWithoutQuery), !url.path.isEmpty {
                path = url.path
            } else {
                path = pathWithoutQuery
            }
        } else {
            path = pathWithoutQuery
        }
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
        let traceID = UploadFlightRecorder.traceID(from: request.headers)
        guard let recordingID = headers["x-rokurics-recording-id"], !recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            sendError(statusCode: 400, reason: "Bad Request", error: "missing_recording_id", on: connection)
            return
        }
        UploadFlightRecorder.record(
            side: .Mac,
            stage: "uploadAudioRouteMatched",
            traceID: traceID,
            recordingID: recordingID,
            eventResult: "success",
            httpPath: request.path,
            routeMatched: true,
            bodyBytes: request.contentLength
        )

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
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "audioTempFileCreated",
                    traceID: traceID,
                    recordingID: recordingID,
                    eventResult: "success",
                    httpPath: request.path,
                    bodyBytes: request.contentLength
                )
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
            let traceID = UploadFlightRecorder.traceID(from: request.headers)
            let headers = Self.normalizedHeaders(request.headers)
            let recordingIDForTrace = headers["x-rokurics-recording-id"]
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "audioChecksumComputed",
                traceID: traceID,
                recordingID: recordingIDForTrace,
                eventResult: "success",
                httpPath: request.path,
                fileSize: Int64(writer.bytesWritten),
                bodyBytes: writer.bytesWritten
            )

            switch requestVerifier.verify(
                method: request.method,
                path: request.path,
                headers: request.headers,
                bodySHA256: bodySHA256,
                bodyByteCount: writer.bytesWritten
            ) {
            case .accepted(let device):
                do {
                    guard let recordingID = headers["x-rokurics-recording-id"], !recordingID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        recordingFileStore.discardTemporaryUpload(at: writer.fileURL)
                        sendError(statusCode: 400, reason: "Bad Request", error: "missing_recording_id", on: connection)
                        return
                    }

                    let result = try await recordingFileStore.saveAudio(
                        temporaryFileURL: writer.fileURL,
                        recordingID: recordingID,
                        requestedFileName: headers["x-rokurics-filename"],
                        sourceDevice: device,
                        checksum: bodySHA256,
                        fileSize: Int64(writer.bytesWritten),
                        uploadTraceID: traceID
                    )
                    onRecordingAccepted(result.recordingID, .macAudioReceiveFinalized)
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
        let traceID = UploadFlightRecorder.traceID(from: request.headers)
        let traceRecordingID = Self.normalizedHeaders(request.headers)["x-rokurics-recording-id"]
        if traceID != nil {
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "httpRequestReceived",
                traceID: traceID,
                recordingID: traceRecordingID,
                eventResult: "begin",
                httpPath: request.path,
                bodyBytes: request.body.count
            )
        }
        if CanonicalLiveReadOnlyTransportProbeHTTP.isMarked(headers: request.headers),
           shouldBlockCanonicalLiveReadOnlyProbe(request) {
            Task(priority: .utility) { [weak self] in
                await self?.handleBlockedCanonicalLiveReadOnlyProbeRequest(request, on: connection)
            }
            return
        }
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
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "uploadMetadataRouteMatched",
                traceID: traceID,
                recordingID: traceRecordingID,
                eventResult: "success",
                httpPath: request.path,
                routeMatched: true,
                bodyBytes: request.body.count
            )
            Task(priority: .utility) { [weak self] in
                await self?.handleRecordingMetadataUploadRequest(request, on: connection)
            }
        case ("POST", "/upload-recording-audio"):
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "uploadAudioRouteMatched",
                traceID: traceID,
                recordingID: traceRecordingID,
                eventResult: "success",
                httpPath: request.path,
                routeMatched: true,
                bodyBytes: request.body.count
            )
            Task(priority: .utility) { [weak self] in
                await self?.handleRecordingAudioUploadRequest(request, on: connection)
            }
        case ("POST", "/upload-recording-audio-session/start"):
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "resumableStartRouteMatched",
                traceID: traceID,
                recordingID: traceRecordingID,
                eventResult: "success",
                httpPath: request.path,
                routeMatched: true,
                bodyBytes: request.body.count
            )
            Task(priority: .utility) { [weak self] in
                await self?.handleResumableAudioStartRequest(request, on: connection)
            }
        case ("POST", "/upload-recording-audio-session/status"):
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "resumableStatusRouteMatched",
                traceID: traceID,
                recordingID: traceRecordingID,
                eventResult: "success",
                httpPath: request.path,
                routeMatched: true,
                bodyBytes: request.body.count
            )
            Task(priority: .utility) { [weak self] in
                await self?.handleResumableAudioStatusRequest(request, on: connection)
            }
        case ("POST", "/upload-recording-audio-session/chunk"):
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "resumableChunkRouteMatched",
                traceID: traceID,
                recordingID: traceRecordingID,
                eventResult: "success",
                httpPath: request.path,
                routeMatched: true,
                bodyBytes: request.body.count
            )
            Task(priority: .utility) { [weak self] in
                await self?.handleResumableAudioChunkRequest(request, on: connection)
            }
        case ("POST", "/upload-recording-audio-session/finalize"):
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "resumableFinalizeRouteMatched",
                traceID: traceID,
                recordingID: traceRecordingID,
                eventResult: "success",
                httpPath: request.path,
                routeMatched: true,
                bodyBytes: request.body.count
            )
            Task(priority: .utility) { [weak self] in
                await self?.handleResumableAudioFinalizeRequest(request, on: connection)
            }
        case ("POST", "/device/status"):
            Task(priority: .utility) { [weak self] in
                await self?.handleDeviceStatusRequest(request, on: connection)
            }
        case ("POST", "/device/unpair"):
            Task { @MainActor [weak self] in
                self?.handleDeviceUnpairRequest(request, on: connection)
            }
        case ("POST", "/connection/heartbeat"):
            Task(priority: .utility) { [weak self] in
                await self?.handleConnectionHeartbeatRequest(request, on: connection)
            }
        case ("POST", "/connection/probe"):
            Task { @MainActor [weak self] in
                self?.handleConnectionProbeRequest(request, on: connection)
            }
        case ("POST", "/sync/device-status"):
            Task(priority: .utility) { [weak self] in
                await self?.handleDeviceStatusRequest(request, on: connection)
            }
        case ("POST", "/sync/status"):
            Task { @MainActor [weak self] in
                self?.handleSyncStatusRequest(request, on: connection)
            }
        case ("POST", "/sync/manifest"):
            Task(priority: .utility) { [weak self] in
                await self?.handleSyncManifestRequest(request, on: connection)
            }
        case ("POST", "/sync/apply"):
            Task(priority: .utility) { [weak self] in
                await self?.handleSyncApplyRequest(request, on: connection)
            }
        case ("POST", "/sync/inventory"):
            Task(priority: .utility) { [weak self] in
                await self?.handleLocalNetworkSyncInventoryRequest(request, on: connection)
            }
        case ("POST", "/sync/apply-metadata"):
            Task(priority: .utility) { [weak self] in
                await self?.handleLocalNetworkSyncApplyMetadataRequest(request, on: connection)
            }
        case ("POST", "/sync/start"):
            Task { @MainActor [weak self] in
                self?.handleLocalNetworkSyncStartRequest(request, on: connection)
            }
        case ("POST", "/sync/start-ack"):
            Task { @MainActor [weak self] in
                self?.handleLocalNetworkSyncStartAckRequest(request, on: connection)
            }
        case ("POST", "/sync/artifact-status"):
            Task(priority: .utility) { [weak self] in
                await self?.handleLocalNetworkSyncArtifactStatusRequest(request, on: connection)
            }
        case ("POST", "/sync/artifact-request"):
            Task(priority: .utility) { [weak self] in
                await self?.handleLocalNetworkSyncArtifactRequest(request, on: connection)
            }
        case ("POST", "/sync/artifact-put"):
            Task(priority: .utility) { [weak self] in
                await self?.handleLocalNetworkSyncArtifactPutRequest(request, on: connection)
            }
        default:
            UploadFlightRecorder.record(
                side: .Mac,
                stage: "uploadRouteNotMatched",
                traceID: traceID,
                recordingID: traceRecordingID,
                eventResult: "fail",
                reasonCode: "route_not_matched",
                httpPath: request.path,
                routeMatched: false
            )
            if request.method != "GET" && request.method != "POST" {
                sendError(statusCode: 405, reason: "Method Not Allowed", error: "method_not_allowed", on: connection)
            } else {
                sendError(statusCode: 404, reason: "Not Found", error: "not_found", on: connection)
            }
        }
    }

    private func canonicalLiveReadOnlyProbeGate(for request: HTTPRequest) -> CanonicalLiveReadOnlyTransportProbeGate {
        MacCanonicalReadOnlyProbeClassifier().gate(
            policy: canonicalLiveReadOnlyTransportProbePolicy,
            method: request.method,
            path: request.path,
            bodyByteCount: request.body.count
        )
    }

    private func shouldBlockCanonicalLiveReadOnlyProbe(_ request: HTTPRequest) -> Bool {
        let gate = canonicalLiveReadOnlyProbeGate(for: request)
        return request.method != "POST" || gate.routeStatus != .allowedReadOnly || gate.shouldSend == false
    }

    @MainActor
    private func handleBlockedCanonicalLiveReadOnlyProbeRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        let gate = canonicalLiveReadOnlyProbeGate(for: request)
        let syncRunID = CanonicalLiveReadOnlyTransportProbeHTTP.syncRunID(headers: request.headers)
        let snapshotDate = Date(timeIntervalSince1970: 0)
        let before = await captureReadOnlyProbeStateSnapshotInBackground(
            manifestGeneratedAt: snapshotDate,
            syncRunID: syncRunID,
            context: "blockedProbeBefore"
        )
        emitConnectionDiagnostic(
            phase: CanonicalLiveReadOnlyTransportProbeDiagnosticKind.canonicalLiveReadOnlyProbeMacAuditStarted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            routePath: request.path,
            requestDeviceIDPrefix: Self.deviceIDPrefix(from: request.headers),
            syncRunID: syncRunID,
            errorMessage: "route=\(gate.route.method) \(gate.route.path),routeStatus=\(gate.routeStatus.rawValue),reason=\(gate.reason)"
        )
        let verification = requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body)
        let after = await captureReadOnlyProbeStateSnapshotInBackground(
            manifestGeneratedAt: snapshotDate,
            syncRunID: syncRunID,
            context: "blockedProbeAfter"
        )
        let audit = MacCanonicalReadOnlyTransportProbeAudit(gate: gate, before: before, after: after)
        emitConnectionDiagnostic(
            phase: CanonicalLiveReadOnlyTransportProbeDiagnosticKind.canonicalLiveReadOnlyProbeMutationRiskBlocked.rawValue,
            listenerState: "ready",
            activePort: activePort,
            routePath: request.path,
            requestDeviceIDPrefix: Self.deviceIDPrefix(from: request.headers),
            verifierStartedAt: requestVerifier.lastTrace?.verifierStartedAt,
            verifierSucceeded: requestVerifier.lastTrace?.verifierSucceeded,
            verifierFailed: requestVerifier.lastTrace?.verifierFailedReason != nil,
            markDeviceSeenCalled: requestVerifier.lastTrace?.markDeviceSeenCalled,
            pairedDeviceLastSeenBefore: requestVerifier.lastTrace?.pairedDeviceLastSeenBefore,
            pairedDeviceLastSeenAfter: requestVerifier.lastTrace?.pairedDeviceLastSeenAfter,
            syncRunID: syncRunID,
            errorCode: gate.failure?.rawValue,
            errorMessage: audit.diagnosticsSummary
        )
        emitConnectionDiagnostic(
            phase: CanonicalLiveReadOnlyTransportProbeDiagnosticKind.canonicalLiveReadOnlyProbeMacAuditCompleted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            routePath: request.path,
            requestDeviceIDPrefix: Self.deviceIDPrefix(from: request.headers),
            syncRunID: syncRunID,
            errorMessage: audit.diagnosticsSummary
        )
        switch verification {
        case .accepted:
            sendError(statusCode: 400, reason: "Bad Request", error: "canonical_live_probe_route_blocked", on: connection)
        case .rejected(let reason):
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    @discardableResult
    private func consumeCanonicalStatusExchangeEnvelope(
        _ envelope: CanonicalStatusExchangeEnvelope?,
        carrier: CanonicalStatusExchangeCarrier,
        deviceIDPrefix: String?,
        syncRunID: String?,
        routePath: String,
        heartbeatSequence: UInt64? = nil
    ) async -> CanonicalStatusExchangeReceiveResult {
        let result = await canonicalStatusExchangeRuntime.consumeIncomingEnvelope(envelope, carrier: carrier)
        guard envelope != nil else {
            return result
        }
        emitConnectionDiagnostic(
            phase: carrier == .heartbeat ? "statusEnvelopeCarriedOverHeartbeat" : "statusEnvelopeCarriedOverInventory",
            listenerState: "ready",
            activePort: activePort,
            routePath: routePath,
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: deviceIDPrefix,
            syncRunID: syncRunID,
            errorCategory: "received"
        )
        if envelope?.delta != nil {
            emitConnectionDiagnostic(
                phase: "statusDeltaReceived",
                listenerState: "ready",
                activePort: activePort,
                routePath: routePath,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: deviceIDPrefix,
                syncRunID: syncRunID,
                errorCategory: "facts=\(result.incorporatedFactCount),rejected=\(result.rejectedFactCount)"
            )
        }
        if envelope?.ack != nil {
            emitConnectionDiagnostic(
                phase: "statusAckReceived",
                listenerState: "ready",
                activePort: activePort,
                routePath: routePath,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: deviceIDPrefix,
                syncRunID: syncRunID,
                errorCategory: envelope?.ack?.disposition.rawValue
            )
        }
        if envelope?.request != nil {
            emitConnectionDiagnostic(
                phase: "statusRequestReceived",
                listenerState: "ready",
                activePort: activePort,
                routePath: routePath,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: deviceIDPrefix,
                syncRunID: syncRunID,
                errorCategory: envelope?.request?.kind.rawValue
            )
        }
        if !result.accepted || result.rejectedFactCount > 0 {
            emitConnectionDiagnostic(
                phase: "statusFactRejected",
                listenerState: "ready",
                activePort: activePort,
                routePath: routePath,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: deviceIDPrefix,
                syncRunID: syncRunID,
                errorCode: result.stale ? "stale_status_envelope" : "status_fact_rejected",
                errorCategory: result.reason
            )
        }
        for action in result.requestedActions {
            switch action {
            case .enqueueRunSyncSoon:
                if let deviceID = pairedDeviceID(forPrefix: deviceIDPrefix) {
                    _ = deviceConnectionStatusStore.recordStatusExchangeRunSyncSoonRequest(
                        deviceID: deviceID,
                        displayName: "iPhone",
                        syncRunID: syncRunID ?? UUID().uuidString
                    )
                }
                emitConnectionDiagnostic(
                    phase: "syncRequestedHintAdvertised",
                    listenerState: "ready",
                    activePort: activePort,
                    routePath: routePath,
                    heartbeatSequence: heartbeatSequence,
                    requestDeviceIDPrefix: deviceIDPrefix,
                    syncRunID: syncRunID,
                    errorCategory: "runSyncSoonQueued"
                )
            case .requestLightweightAudioProof:
                emitConnectionDiagnostic(
                    phase: "peerProofUnavailable",
                    listenerState: "ready",
                    activePort: activePort,
                    routePath: routePath,
                    heartbeatSequence: heartbeatSequence,
                    requestDeviceIDPrefix: deviceIDPrefix,
                    syncRunID: syncRunID,
                    errorCategory: "sendAudioProofRequestObserved"
                )
            case .requestFullInventory:
                emitConnectionDiagnostic(
                    phase: "fullInventoryRequested",
                    listenerState: "ready",
                    activePort: activePort,
                    routePath: routePath,
                    heartbeatSequence: heartbeatSequence,
                    requestDeviceIDPrefix: deviceIDPrefix,
                    syncRunID: syncRunID,
                    errorCategory: "requestOnly"
                )
            }
        }
        return result
    }

    @MainActor
    private func makeOutgoingCanonicalStatusExchangeEnvelope(
        destinationNodeID: CanonicalNodeID?,
        carrier: CanonicalStatusExchangeCarrier,
        requestDeviceIDPrefix: String?,
        syncRunID: String?,
        routePath: String,
        heartbeatSequence: UInt64? = nil
    ) async -> CanonicalStatusExchangeEnvelope? {
        let envelope = await canonicalStatusExchangeRuntime.makeOutgoingEnvelope(
            destinationNodeID: destinationNodeID,
            carrier: carrier
        )
        guard let envelope else {
            return nil
        }
        emitConnectionDiagnostic(
            phase: carrier == .heartbeat ? "statusEnvelopeCarriedOverHeartbeat" : "statusEnvelopeCarriedOverInventory",
            listenerState: "ready",
            activePort: activePort,
            routePath: routePath,
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: requestDeviceIDPrefix,
            syncRunID: syncRunID,
            errorCategory: "sent"
        )
        if envelope.delta != nil {
            emitConnectionDiagnostic(phase: "statusDeltaSent", listenerState: "ready", activePort: activePort, routePath: routePath, heartbeatSequence: heartbeatSequence, requestDeviceIDPrefix: requestDeviceIDPrefix, syncRunID: syncRunID)
        }
        if envelope.ack != nil {
            emitConnectionDiagnostic(phase: "statusAckSent", listenerState: "ready", activePort: activePort, routePath: routePath, heartbeatSequence: heartbeatSequence, requestDeviceIDPrefix: requestDeviceIDPrefix, syncRunID: syncRunID)
        }
        if envelope.request != nil {
            emitConnectionDiagnostic(phase: "statusRequestSent", listenerState: "ready", activePort: activePort, routePath: routePath, heartbeatSequence: heartbeatSequence, requestDeviceIDPrefix: requestDeviceIDPrefix, syncRunID: syncRunID)
        }
        return envelope
    }

    @MainActor
    private func pairedDeviceID(forPrefix prefix: String?) -> String? {
        guard let prefix else {
            return nil
        }
        return deviceConnectionStatusStore.statusesByDeviceID.keys.first { $0.hasPrefix(prefix) }
    }

    @MainActor
    private func produceCanonicalStatusFactsFromInventory(
        _ inventory: LocalNetworkSyncInventory,
        device: PairedDevice,
        syncRunID: String?
    ) async {
        let producer = CanonicalNodeID("mac-\(inventory.sourceDeviceID)")
        var facts: [CanonicalStatusFact] = []
        for recording in inventory.recordings {
            let objectID = CanonicalObjectID("recordingAudio:\(recording.recordingID)")
            let counter = logicalCounter(recording.updatedAt)
            if recording.audioAvailable,
               let checksum = recording.audioChecksum,
               let audioSize = recording.audioSize {
                facts.append(
                    statusFact(
                        id: "mac-peer-\(safePrefix(recording.recordingID))-\(safePrefix(checksum))-\(audioSize)",
                        objectID: objectID,
                        source: .peerInventory,
                        producer: producer,
                        counter: counter,
                        proofKind: .peerInventoryHashSizeMatch,
                        phase: .peerVerified,
                        hash: checksum,
                        byteSize: audioSize,
                        peerNodeID: producer
                    )
                )
            } else {
                facts.append(
                    statusFact(
                        id: "mac-metadataOnly-\(safePrefix(recording.recordingID))-\(counter)",
                        objectID: objectID,
                        source: .metadataOnlyLedger,
                        producer: producer,
                        counter: counter,
                        proofKind: .metadataOnly,
                        phase: .metadataOnly,
                        peerNodeID: producer
                    )
                )
            }
        }
        for artifact in inventory.artifacts where artifact.availability == .local || artifact.availability == .complete || artifact.availability == .availableOnPeer {
            guard let checksum = artifact.checksum, let size = artifact.size else {
                continue
            }
            facts.append(
                statusFact(
                    id: "mac-artifact-\(safePrefix(artifact.artifactID))-\(safePrefix(checksum))-\(size)",
                    objectID: CanonicalObjectID("generatedArtifact:\(artifact.artifactID)"),
                    domain: .generatedArtifacts,
                    source: .fileObservation,
                    producer: producer,
                    counter: logicalCounter(artifact.updatedAt),
                    proofKind: .sameHashAndByteSize,
                    phase: .peerVerified,
                    hash: checksum,
                    byteSize: size,
                    peerNodeID: producer
                )
            )
        }
        guard !facts.isEmpty else {
            return
        }
        var results: [CanonicalStatusFactMergeResult] = []
        for fact in facts {
            results.append(await studyLibraryStore.produceCanonicalStatusFact(fact))
        }
        let rejectedCount = results.filter {
            $0.decision == .rejectedExpired || $0.decision == .rejectedStale
        }.count
        if rejectedCount > 0 {
            emitConnectionDiagnostic(
                phase: "statusFactRejected",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: device.idPrefix,
                syncRunID: syncRunID,
                errorCode: "status_fact_rejected",
                errorCategory: "rejected=\(rejectedCount)"
            )
        }
    }

    private func statusFact(
        id: String,
        objectID: CanonicalObjectID,
        domain: CanonicalStatusDomain = .audioUpload,
        source: CanonicalStatusSource,
        producer: CanonicalNodeID,
        counter: UInt64,
        proofKind: CanonicalStatusProofKind,
        phase: CanonicalStatusPhase,
        hash: String? = nil,
        byteSize: Int64? = nil,
        peerNodeID: CanonicalNodeID? = nil
    ) -> CanonicalStatusFact {
        CanonicalStatusFact(
            factID: id,
            objectID: objectID,
            source: source,
            producerNodeID: producer,
            logicalTime: CanonicalLogicalTime(counter: counter, nodeID: producer),
            proof: CanonicalStatusProof(
                kind: proofKind,
                objectID: objectID,
                hash: hash.map { CanonicalHash($0) },
                byteSize: byteSize,
                peerNodeID: peerNodeID,
                observedAt: CanonicalTimestamp(Date())
            ),
            domain: domain,
            phase: phase
        )
    }

    private func logicalCounter(_ date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince1970.rounded()))
    }

    private func safePrefix(_ value: String) -> String {
        String(value.prefix(12))
    }

    private nonisolated static func decodeSyncBodyOffMain<T: Decodable>(
        _ type: T.Type,
        from body: Data
    ) async throws -> T {
        try await Task.detached(priority: .utility) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: body)
        }.value
    }

    private nonisolated static func encodeSyncBodyOffMain<T: Encodable>(_ value: T) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(value)
        }.value
    }

    @MainActor
    private func handleDeviceStatusRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            guard let statusRequest = try? await Self.decodeSyncBodyOffMain(DeviceStatusRequest.self, from: request.body) else {
                sendError(statusCode: 400, reason: "Bad Request", error: "bad_status_payload", on: connection)
                return
            }

            let status = markDeviceOnline(
                device: device,
                displayName: statusRequest.displayName,
                syncStatus: statusRequest.syncSummary?.statusText
            )
            let syncStartSignal = deviceConnectionStatusStore.consumePendingSyncStartSignal(deviceID: device.id)
            let syncRequested = syncStartSignal != nil
            let manualSyncMetric = syncStartSignal.map {
                "manualSyncRequestConsumedCount=1,pendingSyncRequestedAgeMs=\(max(0, Int(Date().timeIntervalSince($0.requestedAt) * 1_000)))"
            }
            if syncRequested {
                if let syncStartSignal, syncStartSignal.reason != "manual" {
                    emitConnectionDiagnostic(
                        phase: "macSyncRequestedHintConsumedAfterEvent",
                        listenerState: "ready",
                        activePort: activePort,
                        routePath: request.path,
                        requestDeviceIDPrefix: device.idPrefix,
                        syncRunID: syncStartSignal.syncRunID,
                        errorCategory: "reason=\(String(syncStartSignal.reason.prefix(240)))"
                    )
                }
                emitConnectionDiagnostic(
                    phase: "manualSyncRequestedAdvertisedInHeartbeat",
                    listenerState: "ready",
                    activePort: activePort,
                    routePath: request.path,
                    requestDeviceIDPrefix: device.idPrefix,
                    syncRunID: syncStartSignal?.syncRunID,
                    errorCategory: manualSyncMetric
                )
                emitConnectionDiagnostic(
                    phase: "manualSyncRequestedConsumedByPeer",
                    listenerState: "ready",
                    activePort: activePort,
                    routePath: request.path,
                    requestDeviceIDPrefix: device.idPrefix,
                    syncRunID: syncStartSignal?.syncRunID,
                    errorCategory: manualSyncMetric
                )
                emitConnectionDiagnostic(
                    phase: "manualSyncRequestedCleared",
                    listenerState: "ready",
                    activePort: activePort,
                    routePath: request.path,
                    requestDeviceIDPrefix: device.idPrefix,
                    syncRunID: syncStartSignal?.syncRunID,
                    errorCategory: manualSyncMetric
                )
            }
            await consumeCanonicalStatusExchangeEnvelope(
                statusRequest.statusExchangeEnvelope,
                carrier: .heartbeat,
                deviceIDPrefix: device.idPrefix,
                syncRunID: syncStartSignal?.syncRunID,
                routePath: request.path
            )
            if syncRequested {
                await canonicalStatusExchangeRuntime.enqueueRequest(kind: .runSyncSoon)
            }
            let responseEnvelope = await makeOutgoingCanonicalStatusExchangeEnvelope(
                destinationNodeID: nil,
                carrier: .heartbeat,
                requestDeviceIDPrefix: device.idPrefix,
                syncRunID: syncStartSignal?.syncRunID,
                routePath: request.path
            )
            let responseStatus = deviceConnectionStatusStore.status(for: device.id) ?? status
            sendJSON(
                statusCode: 200,
                reason: "OK",
                body: DeviceStatusResponse(
                    ok: true,
                    status: responseStatus,
                    syncState: syncStateStore.state,
                    syncRequested: syncRequested,
                    syncStartSignal: syncStartSignal,
                    statusExchangeEnvelope: responseEnvelope,
                    error: nil
                ),
                on: connection
            )
        case .rejected(let reason):
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleDeviceUnpairRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            guard let unpairRequest = try? Self.syncJSONDecoder.decode(DeviceUnpairRequest.self, from: request.body) else {
                sendError(statusCode: 400, reason: "Bad Request", error: "bad_unpair_payload", on: connection)
                return
            }

            guard unpairRequest.deviceID == device.id else {
                sendError(statusCode: 400, reason: "Bad Request", error: "device_id_mismatch", on: connection)
                return
            }

            let removed = pairingManager.unpairDevice(id: device.id)
            _ = deviceConnectionStatusStore.markUnpaired(displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName)
            onPairingChanged()
            emitConnectionDiagnostic(
                phase: "localCredentialsDeleted",
                listenerState: "ready",
                activePort: activePort,
                routePath: request.path,
                requestDeviceIDPrefix: device.idPrefix,
                errorMessage: unpairRequest.reason
            )
            sendJSON(
                statusCode: 200,
                reason: "OK",
                body: DeviceUnpairResponse(
                    ok: true,
                    disposition: removed ? "unpaired" : "acceptedExisting",
                    deviceID: device.id,
                    error: nil
                ),
                on: connection
            )
        case .rejected(let reason):
            emitConnectionDiagnostic(
                phase: "oldHMACRejectedAfterUnpair",
                listenerState: "ready",
                activePort: activePort,
                routePath: request.path,
                requestDeviceIDPrefix: Self.deviceIDPrefix(from: request.headers),
                errorCode: reason
            )
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleConnectionHeartbeatRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        let routeReceivedAt = Date()
        let heartbeatSequence = Self.heartbeatSequence(from: request.body)
        let requestDeviceIDPrefix = Self.deviceIDPrefix(from: request.headers)
        var response = connectionHeartbeatRouteHandler.heartbeatResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        let trace = requestVerifier.lastTrace
        let uiObservedLastSeenAt = trace?.deviceIDPrefix.flatMap { prefix in
            deviceConnectionStatusStore.statusesByDeviceID.values.first { $0.deviceID.hasPrefix(prefix) }?.lastSeenAt
        }
        let decodedHeartbeatResponse = try? await Self.decodeSyncBodyOffMain(ConnectionHeartbeatResponse.self, from: response.bodyData)
        if response.statusCode == 200,
           var heartbeatResponse = decodedHeartbeatResponse {
            let heartbeatRequest = try? await Self.decodeSyncBodyOffMain(ConnectionHeartbeatRequest.self, from: request.body)
            if let heartbeatRequest {
                _ = await canonicalConnectionRuntime.recordIncomingHeartbeat(
                    from: Self.canonicalIPhonePeerIdentity(from: heartbeatRequest),
                    sequence: CanonicalSequence(heartbeatRequest.sequenceNumber),
                    syncRequested: heartbeatResponse.syncRequested == true || heartbeatResponse.syncStartSignal != nil,
                    observedAt: routeReceivedAt
                )
                if heartbeatResponse.syncRequested == true || heartbeatResponse.syncStartSignal != nil {
                    _ = await canonicalConnectionRuntime.makeSyncRequestedEnvelope(
                        destinationNodeID: CanonicalNodeID("iphone-\(heartbeatRequest.deviceID)"),
                        requestedDomains: [.sync],
                        reason: "heartbeatSyncRequested",
                        now: routeReceivedAt
                    )
                    _ = await canonicalConnectionRuntime.makeStatusRequest(
                        kind: .runSyncSoon,
                        requestedDomains: [.sync]
                    )
                }
            }
            await consumeCanonicalStatusExchangeEnvelope(
                heartbeatRequest?.statusExchangeEnvelope,
                carrier: .heartbeat,
                deviceIDPrefix: requestDeviceIDPrefix,
                syncRunID: heartbeatResponse.syncStartSignal?.syncRunID,
                routePath: request.path,
                heartbeatSequence: heartbeatSequence
            )
            if heartbeatResponse.syncRequested == true {
                await canonicalStatusExchangeRuntime.enqueueRequest(kind: .runSyncSoon)
            }
            heartbeatResponse.statusExchangeEnvelope = await makeOutgoingCanonicalStatusExchangeEnvelope(
                destinationNodeID: nil,
                carrier: .heartbeat,
                requestDeviceIDPrefix: requestDeviceIDPrefix,
                syncRunID: heartbeatResponse.syncStartSignal?.syncRunID,
                routePath: request.path,
                heartbeatSequence: heartbeatSequence
            )
            if let bodyData = try? await Self.encodeSyncBodyOffMain(heartbeatResponse) {
                response = SecureLocalHTTPRouteResponse(
                    statusCode: response.statusCode,
                    reason: response.reason,
                    bodyData: bodyData
                )
            }
        }
        if decodedHeartbeatResponse?.syncRequested == true {
            let manualSyncMetric = decodedHeartbeatResponse?.syncStartSignal.map {
                "manualSyncRequestConsumedCount=1,pendingSyncRequestedAgeMs=\(max(0, Int(Date().timeIntervalSince($0.requestedAt) * 1_000)))"
            }
            if let syncStartSignal = decodedHeartbeatResponse?.syncStartSignal,
               syncStartSignal.reason != "manual" {
                emitConnectionDiagnostic(
                    phase: "macSyncRequestedHintConsumedAfterEvent",
                    listenerState: "ready",
                    activePort: activePort,
                    routeReceivedAt: routeReceivedAt,
                    routePath: request.path,
                    heartbeatSequence: heartbeatSequence,
                    requestDeviceIDPrefix: requestDeviceIDPrefix,
                    syncRunID: syncStartSignal.syncRunID,
                    errorCategory: "reason=\(String(syncStartSignal.reason.prefix(240)))"
                )
            }
            emitConnectionDiagnostic(
                phase: "manualSyncRequestedAdvertisedInHeartbeat",
                listenerState: "ready",
                activePort: activePort,
                routeReceivedAt: routeReceivedAt,
                routePath: request.path,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: requestDeviceIDPrefix,
                syncRunID: decodedHeartbeatResponse?.syncStartSignal?.syncRunID,
                errorCategory: manualSyncMetric
            )
            emitConnectionDiagnostic(
                phase: "manualSyncRequestedConsumedByPeer",
                listenerState: "ready",
                activePort: activePort,
                routeReceivedAt: routeReceivedAt,
                routePath: request.path,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: requestDeviceIDPrefix,
                syncRunID: decodedHeartbeatResponse?.syncStartSignal?.syncRunID,
                errorCategory: manualSyncMetric
            )
            emitConnectionDiagnostic(
                phase: "manualSyncRequestedCleared",
                listenerState: "ready",
                activePort: activePort,
                routeReceivedAt: routeReceivedAt,
                routePath: request.path,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: requestDeviceIDPrefix,
                syncRunID: decodedHeartbeatResponse?.syncStartSignal?.syncRunID,
                errorCategory: manualSyncMetric
            )
        }
        emitConnectionDiagnostic(
            phase: "heartbeatRouteReceived",
            listenerState: "ready",
            activePort: activePort,
            routeReceivedAt: routeReceivedAt,
            routePath: request.path,
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: requestDeviceIDPrefix
        )
        emitConnectionDiagnostic(
            phase: response.statusCode == 200 ? "heartbeat_success" : "heartbeat_failure",
            listenerState: "ready",
            activePort: activePort,
            routeReceivedAt: routeReceivedAt,
            routePath: request.path,
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: requestDeviceIDPrefix,
            verifierStartedAt: trace?.verifierStartedAt,
            verifierSucceeded: trace?.verifierSucceeded,
            verifierFailed: trace?.verifierFailedReason != nil,
            markDeviceSeenCalled: trace?.markDeviceSeenCalled,
            pairedDeviceLastSeenBefore: trace?.pairedDeviceLastSeenBefore,
            pairedDeviceLastSeenAfter: trace?.pairedDeviceLastSeenAfter,
            connectionStatusStoreUpdated: response.statusCode == 200,
            uiObservedLastSeenAt: uiObservedLastSeenAt,
            errorCode: response.statusCode == 200 ? nil : "request_verifier_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason,
            errorCategory: response.statusCode == 200 ? nil : trace?.errorCategory
        )
        emitConnectionDiagnostic(
            phase: response.statusCode == 200 ? "heartbeatSuccess" : "heartbeatFailure",
            listenerState: "ready",
            activePort: activePort,
            routeReceivedAt: routeReceivedAt,
            routePath: request.path,
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: requestDeviceIDPrefix,
            verifierStartedAt: trace?.verifierStartedAt,
            verifierSucceeded: trace?.verifierSucceeded,
            verifierFailed: trace?.verifierFailedReason != nil,
            markDeviceSeenCalled: trace?.markDeviceSeenCalled,
            pairedDeviceLastSeenBefore: trace?.pairedDeviceLastSeenBefore,
            pairedDeviceLastSeenAfter: trace?.pairedDeviceLastSeenAfter,
            connectionStatusStoreUpdated: response.statusCode == 200,
            uiObservedLastSeenAt: uiObservedLastSeenAt,
            errorCode: response.statusCode == 200 ? nil : "request_verifier_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason,
            errorCategory: response.statusCode == 200 ? nil : trace?.errorCategory
        )
        if response.statusCode == 200 {
            emitConnectionDiagnostic(phase: "signedRequestRefreshedLastSeen", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(
                phase: "lastSeenUpdated",
                listenerState: "ready",
                activePort: activePort,
                routeReceivedAt: routeReceivedAt,
                routePath: request.path,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: requestDeviceIDPrefix,
                pairedDeviceLastSeenBefore: trace?.pairedDeviceLastSeenBefore,
                pairedDeviceLastSeenAfter: trace?.pairedDeviceLastSeenAfter,
                connectionStatusStoreUpdated: true,
                uiObservedLastSeenAt: uiObservedLastSeenAt
            )
        }
        sendRouteResponse(response, on: connection)
    }

    private nonisolated static func canonicalIPhonePeerIdentity(
        from request: ConnectionHeartbeatRequest
    ) -> CanonicalNodeIdentity {
        CanonicalNodeIdentity(
            nodeID: CanonicalNodeID("iphone-\(request.deviceID)"),
            role: .iPhone,
            displayName: request.deviceName
        )
    }

    @MainActor
    private func handleConnectionProbeRequest(_ request: HTTPRequest, on connection: NWConnection) {
        let routeReceivedAt = Date()
        let heartbeatSequence = Self.probeSequence(from: request.body)
        let requestDeviceIDPrefix = Self.deviceIDPrefix(from: request.headers)
        let response = connectionProbeRouteHandler.probeResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        let trace = requestVerifier.lastTrace
        let uiObservedLastSeenAt = trace?.deviceIDPrefix.flatMap { prefix in
            deviceConnectionStatusStore.statusesByDeviceID.values.first { $0.deviceID.hasPrefix(prefix) }?.lastSeenAt
        }
        emitConnectionDiagnostic(
            phase: "heartbeatRouteReceived",
            listenerState: "ready",
            activePort: activePort,
            routeReceivedAt: routeReceivedAt,
            routePath: request.path,
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: requestDeviceIDPrefix
        )
        emitConnectionDiagnostic(
            phase: response.statusCode == 200 ? "probe_success" : "probe_failure",
            listenerState: "ready",
            activePort: activePort,
            routeReceivedAt: routeReceivedAt,
            routePath: request.path,
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: requestDeviceIDPrefix,
            verifierStartedAt: trace?.verifierStartedAt,
            verifierSucceeded: trace?.verifierSucceeded,
            verifierFailed: trace?.verifierFailedReason != nil,
            markDeviceSeenCalled: trace?.markDeviceSeenCalled,
            pairedDeviceLastSeenBefore: trace?.pairedDeviceLastSeenBefore,
            pairedDeviceLastSeenAfter: trace?.pairedDeviceLastSeenAfter,
            connectionStatusStoreUpdated: response.statusCode == 200,
            uiObservedLastSeenAt: uiObservedLastSeenAt,
            errorCode: response.statusCode == 200 ? nil : "request_verifier_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason,
            errorCategory: response.statusCode == 200 ? nil : trace?.errorCategory
        )
        emitConnectionDiagnostic(
            phase: response.statusCode == 200 ? "probeSuccess" : "probeFailure",
            listenerState: "ready",
            activePort: activePort,
            routeReceivedAt: routeReceivedAt,
            routePath: request.path,
            heartbeatSequence: heartbeatSequence,
            requestDeviceIDPrefix: requestDeviceIDPrefix,
            verifierStartedAt: trace?.verifierStartedAt,
            verifierSucceeded: trace?.verifierSucceeded,
            verifierFailed: trace?.verifierFailedReason != nil,
            markDeviceSeenCalled: trace?.markDeviceSeenCalled,
            pairedDeviceLastSeenBefore: trace?.pairedDeviceLastSeenBefore,
            pairedDeviceLastSeenAfter: trace?.pairedDeviceLastSeenAfter,
            connectionStatusStoreUpdated: response.statusCode == 200,
            uiObservedLastSeenAt: uiObservedLastSeenAt,
            errorCode: response.statusCode == 200 ? nil : "request_verifier_rejected",
            errorMessage: response.statusCode == 200 ? nil : response.reason,
            errorCategory: response.statusCode == 200 ? nil : trace?.errorCategory
        )
        if response.statusCode == 200 {
            emitConnectionDiagnostic(phase: "signedRequestRefreshedLastSeen", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(
                phase: "lastSeenUpdated",
                listenerState: "ready",
                activePort: activePort,
                routeReceivedAt: routeReceivedAt,
                routePath: request.path,
                heartbeatSequence: heartbeatSequence,
                requestDeviceIDPrefix: requestDeviceIDPrefix,
                pairedDeviceLastSeenBefore: trace?.pairedDeviceLastSeenBefore,
                pairedDeviceLastSeenAfter: trace?.pairedDeviceLastSeenAfter,
                connectionStatusStoreUpdated: true,
                uiObservedLastSeenAt: uiObservedLastSeenAt
            )
        }
        sendRouteResponse(response, on: connection)
    }

    private static func heartbeatSequence(from body: Data) -> UInt64? {
        try? syncJSONDecoder.decode(ConnectionHeartbeatRequest.self, from: body).sequenceNumber
    }

    private struct ProbeSequenceEnvelope: Decodable {
        let sequenceNumber: UInt64
    }

    private static func probeSequence(from body: Data) -> UInt64? {
        try? syncJSONDecoder.decode(ProbeSequenceEnvelope.self, from: body).sequenceNumber
    }

    private static func deviceIDPrefix(from headers: [String: String]) -> String? {
        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, header in
            result[header.key.lowercased()] = header.value
        }
        return normalizedHeaders["x-rokurics-device-id"].map { String($0.prefix(12)) }
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

        var manifest = makeLegacySyncManifestSynchronouslyOffMain(context: "syncManifest").manifest
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
    func syncManifestResponseForVerifiedDeviceInBackground(_ device: PairedDevice) async throws -> StudyLibrarySyncManifestResponse {
        guard let gitBackedStudyMetadataStore = activeGitBackedStudyMetadataStore else {
            return disabledSyncManifestResponse(for: device)
        }

        var manifest = await makeLegacySyncManifestInBackground(context: "syncManifest").manifest
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
    ) async throws -> StudyLibrarySyncManifestResponse {
        guard let gitBackedStudyMetadataStore = activeGitBackedStudyMetadataStore else {
            return disabledSyncManifestResponse(for: device)
        }

        let syncRequest = try Self.syncJSONDecoder.decode(StudyLibrarySyncManifestRequest.self, from: requestBody)
        var applyResult = try await applyStudyLibrarySyncManifestWithoutInlineExistenceLedger(
            syncRequest.manifest,
            localDeviceID: localSyncDeviceID
        )
        let existenceResults = applyCanonicalRecordingExistenceBridgeIfNeededSynchronously(
            manifest: syncRequest.manifest,
            sourceDeviceID: device.id,
            syncRunID: nil
        )
        applyResult.failedChanges += existenceResults.filter { $0.action == .rollbackFailed || $0.action == .conflict }.count
        var manifest = makeLegacySyncManifestSynchronouslyOffMain(context: "syncApply").manifest
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
    func syncApplyResponseForVerifiedDeviceInBackground(
        _ device: PairedDevice,
        requestBody: Data
    ) async throws -> StudyLibrarySyncManifestResponse {
        guard let gitBackedStudyMetadataStore = activeGitBackedStudyMetadataStore else {
            return disabledSyncManifestResponse(for: device)
        }

        let syncRequest = try await Self.decodeSyncBodyOffMain(StudyLibrarySyncManifestRequest.self, from: requestBody)
        var applyResult = try await applyStudyLibrarySyncManifestWithoutInlineExistenceLedger(
            syncRequest.manifest,
            localDeviceID: localSyncDeviceID
        )
        let existenceResults = await applyCanonicalRecordingExistenceBridgeIfNeeded(
            manifest: syncRequest.manifest,
            sourceDeviceID: device.id,
            syncRunID: nil
        )
        applyResult.failedChanges += existenceResults.filter { $0.action == .rollbackFailed || $0.action == .conflict }.count
        var manifest = await makeLegacySyncManifestInBackground(context: "syncApply").manifest
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

    private func makeLegacySyncManifestInBackground(
        context: String,
        generatedAt: Date = Date(),
        syncRunID: String? = nil
    ) async -> (manifest: StudyLibrarySyncManifest, manifestBuildDurationMs: Int, mainActorLongTaskDurationMs: Int) {
        let rootURL = recordingFileStore.libraryRootURL
        let deviceID = localSyncDeviceID
        let detachedStartedAt = Date()
        let result = await Task.detached(priority: .utility) {
            let startedAt = Date()
            let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
            let inboxItems = MacLocalNetworkSyncInventoryBackgroundIO.loadInboxItems(rootURL: rootURL)
            let manifest = MacLocalNetworkSyncBackgroundStudyManifestBuilder(
                fileManager: .default,
                rootURL: rootURL,
                inboxItems: inboxItems,
                deviceID: deviceID,
                generatedAt: generatedAt
            ).build()
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            return (
                manifest: manifest,
                manifestBuildDurationMs: durationMs,
                mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
            )
        }.value
        Task { @MainActor in
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .inventoryBuildMs,
                    durationMs: CanonicalPerfLog.elapsedMs(since: detachedStartedAt),
                    result: "legacyManifestBuild"
                )
            )
        }
        emitConnectionDiagnostic(
            phase: "legacyManifestBuildCompleted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "context=\(context)",
                "recordings=\(result.manifest.recordings.count)",
                "items=\(result.manifest.items.count)",
                "folders=\(result.manifest.folders.count)",
                "manifestBuildDurationMs=\(result.manifestBuildDurationMs)",
                "mainActorLongTaskDurationMs=\(result.mainActorLongTaskDurationMs)"
            ].joined(separator: ",")
        )
        return result
    }

    private func makeLegacySyncManifestSynchronouslyOffMain(
        context: String,
        generatedAt: Date = Date(),
        syncRunID: String? = nil
    ) -> (manifest: StudyLibrarySyncManifest, manifestBuildDurationMs: Int, mainActorLongTaskDurationMs: Int) {
        let rootURL = recordingFileStore.libraryRootURL
        let deviceID = localSyncDeviceID
        let semaphore = DispatchSemaphore(value: 0)
        var result: (manifest: StudyLibrarySyncManifest, manifestBuildDurationMs: Int, mainActorLongTaskDurationMs: Int)?
        DispatchQueue.global(qos: .utility).async {
            let startedAt = Date()
            let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
            let inboxItems = MacLocalNetworkSyncInventoryBackgroundIO.loadInboxItems(rootURL: rootURL)
            let manifest = MacLocalNetworkSyncBackgroundStudyManifestBuilder(
                fileManager: .default,
                rootURL: rootURL,
                inboxItems: inboxItems,
                deviceID: deviceID,
                generatedAt: generatedAt
            ).build()
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            result = (
                manifest: manifest,
                manifestBuildDurationMs: durationMs,
                mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
            )
            semaphore.signal()
        }
        semaphore.wait()
        let output = result!
        emitConnectionDiagnostic(
            phase: "legacyManifestBuildCompleted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "context=\(context)",
                "recordings=\(output.manifest.recordings.count)",
                "items=\(output.manifest.items.count)",
                "folders=\(output.manifest.folders.count)",
                "manifestBuildDurationMs=\(output.manifestBuildDurationMs)",
                "mainActorLongTaskDurationMs=\(output.mainActorLongTaskDurationMs)"
            ].joined(separator: ",")
        )
        return output
    }

    private func captureReadOnlyProbeStateSnapshotInBackground(
        manifestGeneratedAt: Date,
        syncRunID: String?,
        context: String
    ) async -> MacCanonicalReadOnlyProbeStateSnapshot {
        let rootURL = recordingFileStore.libraryRootURL
        let deviceID = localSyncDeviceID
        let pendingSyncCount = deviceConnectionStatusStore.pendingSyncRequestCountForDiagnostics
        let detachedStartedAt = Date()
        let result = await Task.detached(priority: .utility) {
            var unavailable: [String] = []
            let startedAt = Date()
            let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
            let inboxItems = MacLocalNetworkSyncInventoryBackgroundIO.loadInboxItems(rootURL: rootURL)
            let uploadSessionCount = MacLocalNetworkSyncInventoryBackgroundIO.uploadSessionCountForDiagnostics(rootURL: rootURL)
            if uploadSessionCount == nil {
                unavailable.append("uploadSessionCount")
            }
            let manifest = MacLocalNetworkSyncBackgroundStudyManifestBuilder(
                fileManager: .default,
                rootURL: rootURL,
                inboxItems: inboxItems,
                deviceID: deviceID,
                generatedAt: manifestGeneratedAt
            ).build()
            let checksum = manifest.checksum.trimmingCharacters(in: .whitespacesAndNewlines)
            if checksum.isEmpty {
                unavailable.append("studyManifestChecksum")
            }
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            let snapshot = MacCanonicalReadOnlyProbeStateSnapshot(
                receiveRecordCount: inboxItems.count,
                uploadSessionCount: uploadSessionCount,
                pendingSyncRequestCount: pendingSyncCount,
                studyManifestChecksum: checksum.isEmpty ? nil : checksum,
                unavailableReasons: unavailable.sorted()
            )
            return (
                snapshot: snapshot,
                manifestBuildDurationMs: durationMs,
                mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
            )
        }.value
        Task { @MainActor in
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .inventoryBuildMs,
                    durationMs: CanonicalPerfLog.elapsedMs(since: detachedStartedAt),
                    result: "readOnlyProbeSnapshot"
                )
            )
        }
        emitConnectionDiagnostic(
            phase: "readOnlyProbeSnapshotBuilt",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "context=\(context)",
                "manifestBuildDurationMs=\(result.manifestBuildDurationMs)",
                "mainActorLongTaskDurationMs=\(result.mainActorLongTaskDurationMs)"
            ].joined(separator: ",")
        )
        return result.snapshot
    }

    private func applyStudyLibrarySyncManifestWithoutInlineExistenceLedger(
        _ manifest: StudyLibrarySyncManifest,
        localDeviceID: String
    ) async throws -> StudyLibrarySyncApplyResult {
        studyLibraryStore.configureCanonicalExistenceApplyRuntime(configuration: .disabled, port: nil)
        defer {
            studyLibraryStore.configureCanonicalExistenceApplyRuntime(
                configuration: canonicalExistenceApplyRuntimeConfiguration,
                port: canonicalRecordingExistenceApplyPort
            )
        }
        return try await studyLibraryStore.applySyncManifest(manifest, localDeviceID: localDeviceID)
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
    private func handleSyncManifestRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            do {
                let response = try await syncManifestResponseForVerifiedDeviceInBackground(device)
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
    private func handleSyncApplyRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            do {
                let response = try await syncApplyResponseForVerifiedDeviceInBackground(device, requestBody: request.body)
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
    func localNetworkSyncInventoryResponseForVerifiedDevice(
        _ device: PairedDevice,
        syncRunID: String? = nil,
        requestEnvelope: CanonicalStatusExchangeEnvelope? = nil
    ) async -> LocalNetworkSyncInventoryResponse {
        _ = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: "inventory")
        await consumeCanonicalStatusExchangeEnvelope(
            requestEnvelope,
            carrier: .inventory,
            deviceIDPrefix: device.idPrefix,
            syncRunID: syncRunID,
            routePath: "/sync/inventory"
        )
        if let syncRunID {
            _ = deviceConnectionStatusStore.recordPendingSyncInventoryObserved(
                deviceID: device.id,
                displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
                syncRunID: syncRunID
            )
            syncStateStore.recordControlPlane(deviceID: device.id, syncRunID: syncRunID, state: .inventoryExchanging)
            emitConnectionDiagnostic(phase: "manualSyncRequestedInventoryObserved", listenerState: "ready", activePort: activePort, requestDeviceIDPrefix: device.idPrefix, syncRunID: syncRunID, errorCategory: "manualSyncRequestConsumedCount=1")
            emitConnectionDiagnostic(phase: "manualSyncRequestedConsumedByPeer", listenerState: "ready", activePort: activePort, requestDeviceIDPrefix: device.idPrefix, syncRunID: syncRunID, errorCategory: "manualSyncRequestConsumedCount=1")
            emitConnectionDiagnostic(phase: "manualSyncTickStarted", listenerState: "ready", activePort: activePort, requestDeviceIDPrefix: device.idPrefix, syncRunID: syncRunID)
        }
        emitConnectionDiagnostic(phase: "localInventoryBuilt", listenerState: "ready", activePort: activePort, requestDeviceIDPrefix: device.idPrefix, syncRunID: syncRunID)
        let inventory = await makeLocalNetworkSyncInventory(shadowTrigger: "sync-inventory", shadowSyncRunID: syncRunID, sourceKind: .inventoryRequest)
        await produceCanonicalStatusFactsFromInventory(inventory, device: device, syncRunID: syncRunID)
        let responseEnvelope = await makeOutgoingCanonicalStatusExchangeEnvelope(
            destinationNodeID: nil,
            carrier: .inventory,
            requestDeviceIDPrefix: device.idPrefix,
            syncRunID: syncRunID,
            routePath: "/sync/inventory"
        )
        return LocalNetworkSyncInventoryResponse(
            ok: true,
            inventory: inventory,
            statusExchangeEnvelope: responseEnvelope,
            error: nil
        )
    }

    @MainActor
    func localNetworkSyncApplyMetadataResponseForVerifiedDevice(
        _ device: PairedDevice,
        requestBody: Data
    ) async throws -> StudyLibrarySyncManifestResponse {
        let syncRequest = try Self.syncJSONDecoder.decode(StudyLibrarySyncManifestRequest.self, from: requestBody)
        var applyResult = try await applyStudyLibrarySyncManifestWithoutInlineExistenceLedger(
            syncRequest.manifest,
            localDeviceID: localSyncDeviceID
        )
        let existenceResults = applyCanonicalRecordingExistenceBridgeIfNeededSynchronously(
            manifest: syncRequest.manifest,
            sourceDeviceID: device.id,
            syncRunID: nil
        )
        applyResult.failedChanges += existenceResults.filter { $0.action == .rollbackFailed || $0.action == .conflict }.count
        let manifest = makeLegacySyncManifestSynchronouslyOffMain(context: "syncApplyMetadata").manifest
        let pendingUploadCount = syncRequest.manifest.pendingUploads.filter { $0.status != .uploaded }.count
        let status = deviceConnectionStatusStore.recordSyncResult(
            deviceID: device.id,
            displayName: device.deviceName.isEmpty ? "iPhone" : device.deviceName,
            statusText: applyResult.summaryText,
            error: applyResult.failedChanges == 0 ? nil : "sync_apply_metadata_partial_failure"
        )
        emitConnectionDiagnostic(
            phase: applyResult.failedChanges == 0 ? "metadataApplied" : "syncTickFailed",
            listenerState: "ready",
            activePort: activePort,
            errorCode: applyResult.failedChanges == 0 ? nil : "sync_apply_metadata_partial_failure"
        )
        emitConnectionDiagnostic(
            phase: applyResult.failedChanges == 0 ? "manualSyncTickCompleted" : "manualSyncTickFailed",
            listenerState: "ready",
            activePort: activePort,
            requestDeviceIDPrefix: device.idPrefix,
            errorCode: applyResult.failedChanges == 0 ? nil : "sync_apply_metadata_partial_failure"
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

    func localNetworkSyncApplyMetadataResponseForVerifiedDeviceInBackground(
        _ device: PairedDevice,
        requestBody: Data
    ) async throws -> StudyLibrarySyncManifestResponse {
        let syncRequest = try await Self.decodeSyncBodyOffMain(StudyLibrarySyncManifestRequest.self, from: requestBody)
        var applyResult = try await applyStudyLibrarySyncManifestWithoutInlineExistenceLedger(
            syncRequest.manifest,
            localDeviceID: localSyncDeviceID
        )
        scheduleCanonicalRecordingExistenceBridgeAfterMetadataResponse(
            manifest: syncRequest.manifest,
            sourceDeviceID: device.id,
            syncRunID: nil
        )
        let manifest = await makeLegacySyncManifestInBackground(context: "syncApplyMetadata").manifest
        let pendingUploadCount = syncRequest.manifest.pendingUploads.filter { $0.status != .uploaded }.count
        let stateAndStatus = await MainActor.run {
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
            return (state: syncStateStore.state, status: status)
        }
        emitConnectionDiagnostic(
            phase: applyResult.failedChanges == 0 ? "metadataApplied" : "syncTickFailed",
            listenerState: "ready",
            activePort: activePort,
            errorCode: applyResult.failedChanges == 0 ? nil : "sync_apply_metadata_partial_failure"
        )
        emitConnectionDiagnostic(
            phase: applyResult.failedChanges == 0 ? "manualSyncTickCompleted" : "manualSyncTickFailed",
            listenerState: "ready",
            activePort: activePort,
            requestDeviceIDPrefix: device.idPrefix,
            errorCode: applyResult.failedChanges == 0 ? nil : "sync_apply_metadata_partial_failure"
        )

        return StudyLibrarySyncManifestResponse(
            ok: true,
            manifest: manifest,
            syncState: stateAndStatus.state,
            deviceStatus: stateAndStatus.status,
            applyResult: applyResult,
            baseCommitID: syncRequest.manifest.baseCommitID,
            newCommitID: nil,
            remoteChanges: manifest.changesApproximation,
            rejectedChanges: applyResult.failedChanges == 0 ? nil : syncRequest.manifest.changesApproximation,
            error: applyResult.failedChanges == 0 ? nil : "sync_apply_metadata_partial_failure"
        )
    }

    private func scheduleCanonicalRecordingExistenceBridgeAfterMetadataResponse(
        manifest: StudyLibrarySyncManifest,
        sourceDeviceID: String,
        syncRunID: String?
    ) {
        guard !manifest.recordings.isEmpty else {
            return
        }
        Task(priority: .utility) { [weak self] in
            guard let self else {
                return
            }
            let results = await self.applyCanonicalRecordingExistenceBridgeIfNeeded(
                manifest: manifest,
                sourceDeviceID: sourceDeviceID,
                syncRunID: syncRunID
            )
            let blockedCount = results.filter { $0.action == .rollbackFailed || $0.action == .conflict }.count
            guard blockedCount > 0 else {
                return
            }
            self.emitConnectionDiagnostic(
                phase: "metadataExistenceBridgeCompletedAfterResponse",
                listenerState: "ready",
                activePort: self.activePort,
                syncRunID: syncRunID,
                errorCode: "sync_apply_metadata_existence_conflict",
                errorMessage: "blocked=\(blockedCount)"
            )
            await MainActor.run {
                self.syncStateStore.recordFailure(
                    deviceID: sourceDeviceID,
                    error: "sync_apply_metadata_existence_conflict",
                    failedChanges: blockedCount
                )
            }
        }
    }

    @MainActor
    func localNetworkSyncStartResponseForVerifiedDevice(
        _ device: PairedDevice,
        requestBody: Data
    ) -> LocalNetworkSyncStartResponse {
        do {
            let request = try Self.syncJSONDecoder.decode(LocalNetworkSyncStartRequest.self, from: requestBody)
            guard request.deviceID == device.id else {
                throw NSError(domain: "RokuricsSync", code: 400, userInfo: [NSLocalizedDescriptionKey: "device_id_mismatch"])
            }
            syncStateStore.recordControlPlane(
                deviceID: device.id,
                syncRunID: request.syncRunID,
                state: .syncStartAcked
            )
            _ = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: "sync-start")
            emitConnectionDiagnostic(phase: "syncStartSignalReceived", listenerState: "ready", activePort: activePort, requestDeviceIDPrefix: device.idPrefix, syncRunID: request.syncRunID)
            emitConnectionDiagnostic(phase: "syncStartAckSent", listenerState: "ready", activePort: activePort, requestDeviceIDPrefix: device.idPrefix, syncRunID: request.syncRunID)
            return LocalNetworkSyncStartResponse(
                ok: true,
                syncRunID: request.syncRunID,
                peerDeviceID: localSyncDeviceID,
                ackAt: Date(),
                disposition: "ack",
                error: nil
            )
        } catch {
            return LocalNetworkSyncStartResponse(
                ok: false,
                syncRunID: nil,
                peerDeviceID: localSyncDeviceID,
                ackAt: nil,
                disposition: "rejected",
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    @MainActor
    func localNetworkSyncStartAckResponseForVerifiedDevice(
        _ device: PairedDevice,
        requestBody: Data
    ) -> LocalNetworkSyncStartAckResponse {
        do {
            let request = try Self.syncJSONDecoder.decode(LocalNetworkSyncStartAckRequest.self, from: requestBody)
            guard request.deviceID == device.id else {
                throw NSError(domain: "RokuricsSync", code: 400, userInfo: [NSLocalizedDescriptionKey: "device_id_mismatch"])
            }
            syncStateStore.recordControlPlane(
                deviceID: device.id,
                syncRunID: request.syncRunID,
                state: .syncStartAcked
            )
            _ = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: "sync-ack")
            emitConnectionDiagnostic(phase: "syncStartAckReceived", listenerState: "ready", activePort: activePort, requestDeviceIDPrefix: device.idPrefix, syncRunID: request.syncRunID)
            emitConnectionDiagnostic(phase: "manualSyncAckReceived", listenerState: "ready", activePort: activePort, requestDeviceIDPrefix: device.idPrefix, syncRunID: request.syncRunID)
            return LocalNetworkSyncStartAckResponse(
                ok: true,
                syncRunID: request.syncRunID,
                peerDeviceID: localSyncDeviceID,
                ackReceivedAt: Date(),
                error: nil
            )
        } catch {
            return LocalNetworkSyncStartAckResponse(
                ok: false,
                syncRunID: nil,
                peerDeviceID: localSyncDeviceID,
                ackReceivedAt: nil,
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    @MainActor
    func localNetworkSyncArtifactResponseForVerifiedDevice(
        _ device: PairedDevice,
        requestBody: Data
    ) async -> LocalNetworkSyncArtifactResponse {
        _ = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: "artifact")
        emitConnectionDiagnostic(phase: "downloadActionStarted", listenerState: "ready", activePort: activePort)

        do {
            let request = try await Self.decodeSyncBodyOffMain(LocalNetworkSyncArtifactRequest.self, from: requestBody)
            try LocalNetworkSyncArtifactID.validate(request.artifactID)
            let inventory = await makeLocalNetworkSyncInventory(sourceKind: .artifactLookup)
            guard let artifact = inventory.artifacts.first(where: { $0.artifactID == request.artifactID }) else {
                throw LocalNetworkSyncArtifactValidationError.artifactNotFound
            }
            guard artifact.kind.isAutoDownloadAllowed else {
                throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
            }

            let artifactURL = try LocalNetworkSyncArtifactFileService.safeFileURL(
                rootURL: recordingFileStore.libraryRootURL,
                logicalPathToken: artifact.logicalPathToken,
                kind: artifact.kind
            )
            let metadataResult = await Self.artifactFileMetadataOffMain(fileURL: artifactURL)
            guard let fileMetadata = metadataResult.metadata else {
                throw LocalNetworkSyncArtifactValidationError.artifactNotFound
            }
            let isChunkRequest = request.offset != nil || request.length != nil
            let maxResponseBytes = isChunkRequest ? syncArtifactChunkBytes : 4 * 1024 * 1024
            let offset = request.offset ?? 0
            let length = request.length ?? Int(fileMetadata.size)
            guard offset >= 0,
                  length > 0,
                  length <= maxResponseBytes,
                  offset < fileMetadata.size else {
                throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
            }
            let chunkResult = try await Self.artifactChunkDataAndChecksumOffMain(fileURL: artifactURL, offset: offset, length: length)
            emitConnectionDiagnostic(
                phase: "artifactReadCompleted",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: request.syncRunID,
                errorMessage: [
                    "metadataDurationMs=\(metadataResult.ioDurationMs)",
                    "readHashDurationMs=\(chunkResult.ioDurationMs)",
                    "mainActorLongTaskDurationMs=\(metadataResult.mainActorLongTaskDurationMs + chunkResult.mainActorLongTaskDurationMs)"
                ].joined(separator: ",")
            )
            emitConnectionDiagnostic(phase: "artifactChecksumVerified", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(phase: "checksumVerified", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(phase: "fileTransferStarted", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(phase: "fileTransferProgressUpdated", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(phase: "downloadActionCompleted", listenerState: "ready", activePort: activePort)
            return LocalNetworkSyncArtifactResponse(
                ok: true,
                artifactID: artifact.artifactID,
                kind: artifact.kind,
                checksum: chunkResult.checksum,
                size: Int64(chunkResult.byteCount),
                logicalPathToken: artifact.logicalPathToken,
                dataBase64: chunkResult.dataBase64,
                offset: offset,
                totalSize: fileMetadata.size,
                isFinalChunk: offset + Int64(chunkResult.byteCount) >= fileMetadata.size,
                error: nil
            )
        } catch {
            emitConnectionDiagnostic(
                phase: "downloadActionFailed",
                listenerState: "ready",
                activePort: activePort,
                errorCode: "sync_artifact_request_failed",
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
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
    func localNetworkSyncArtifactStatusResponseForVerifiedDevice(
        _ device: PairedDevice,
        requestBody: Data
    ) async -> LocalNetworkSyncArtifactStatusResponse {
        _ = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: "artifact-status")
        do {
            let request = try await Self.decodeSyncBodyOffMain(LocalNetworkSyncArtifactStatusRequest.self, from: requestBody)
            try LocalNetworkSyncArtifactID.validate(request.artifactID)
            emitConnectionDiagnostic(phase: "transferSessionStatusFetched", listenerState: "ready", activePort: activePort, requestDeviceIDPrefix: device.idPrefix, syncRunID: request.syncRunID)

            if let kind = request.kind,
               let ownerID = request.ownerID,
               let logicalPathToken = request.logicalPathToken {
                try LocalNetworkSyncArtifactID.validateLogicalPathToken(logicalPathToken, for: kind)
                guard kind.isAutoDownloadAllowed,
                      request.artifactID == LocalNetworkSyncArtifactID.make(kind: kind, ownerID: ownerID, logicalPathToken: logicalPathToken) else {
                    throw LocalNetworkSyncArtifactValidationError.invalidArtifactID
                }
                let finalURL = try LocalNetworkSyncArtifactFileService.safeFileURL(
                    rootURL: recordingFileStore.libraryRootURL,
                    logicalPathToken: logicalPathToken,
                    kind: kind
                )
                let finalResult = await Self.artifactFileMetadataAndChecksumOffMain(
                    fileURL: finalURL,
                    logicalToken: logicalPathToken,
                    checksumRuntime: canonicalChecksumRuntime,
                    cacheDirectoryURL: canonicalChecksumCacheDirectory(),
                    configuration: inventoryRuntimeConfiguration
                )
                if let finalMetadata = finalResult.metadata,
                   request.size == nil || request.size == finalMetadata.size {
                    let finalChecksum = finalResult.checksum
                    if request.checksum == nil || request.checksum == finalChecksum {
                        emitConnectionDiagnostic(
                            phase: "artifactStatusReadCompleted",
                            listenerState: "ready",
                            activePort: activePort,
                            syncRunID: request.syncRunID,
                            errorMessage: [
                                "readHashDurationMs=\(finalResult.ioDurationMs)",
                                "mainActorLongTaskDurationMs=\(finalResult.mainActorLongTaskDurationMs)"
                            ].joined(separator: ",")
                        )
                        return LocalNetworkSyncArtifactStatusResponse(
                            ok: true,
                            artifactID: request.artifactID,
                            checksum: finalChecksum,
                            size: finalMetadata.size,
                            confirmedBytes: finalMetadata.size,
                            nextOffset: finalMetadata.size,
                            state: .complete,
                            error: nil
                        )
                    }
                }
                let tempURL = try syncArtifactIncomingTempURL(artifactID: request.artifactID)
                let tempResult = await Self.artifactFileMetadataOffMain(fileURL: tempURL)
                let confirmedBytes = tempResult.metadata?.size ?? 0
                emitConnectionDiagnostic(
                    phase: "artifactStatusReadCompleted",
                    listenerState: "ready",
                    activePort: activePort,
                    syncRunID: request.syncRunID,
                    errorMessage: [
                        "readHashDurationMs=\(finalResult.ioDurationMs + tempResult.ioDurationMs)",
                        "mainActorLongTaskDurationMs=\(finalResult.mainActorLongTaskDurationMs + tempResult.mainActorLongTaskDurationMs)"
                    ].joined(separator: ",")
                )
                return LocalNetworkSyncArtifactStatusResponse(
                    ok: true,
                    artifactID: request.artifactID,
                    checksum: request.checksum,
                    size: request.size,
                    confirmedBytes: confirmedBytes,
                    nextOffset: confirmedBytes,
                    state: confirmedBytes > 0 ? .resuming : .pending,
                    error: nil
                )
            }

            let inventory = await makeLocalNetworkSyncInventory(sourceKind: .artifactLookup)
            guard let artifact = inventory.artifacts.first(where: { $0.artifactID == request.artifactID }) else {
                throw LocalNetworkSyncArtifactValidationError.artifactNotFound
            }
            let artifactURL = try LocalNetworkSyncArtifactFileService.safeFileURL(
                rootURL: recordingFileStore.libraryRootURL,
                logicalPathToken: artifact.logicalPathToken,
                kind: artifact.kind
            )
            let artifactResult = await Self.artifactFileMetadataAndChecksumOffMain(
                fileURL: artifactURL,
                logicalToken: artifact.logicalPathToken,
                checksumRuntime: canonicalChecksumRuntime,
                cacheDirectoryURL: canonicalChecksumCacheDirectory(),
                configuration: inventoryRuntimeConfiguration
            )
            guard let metadata = artifactResult.metadata else {
                throw LocalNetworkSyncArtifactValidationError.artifactNotFound
            }
            emitConnectionDiagnostic(
                phase: "artifactStatusReadCompleted",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: request.syncRunID,
                errorMessage: [
                    "readHashDurationMs=\(artifactResult.ioDurationMs)",
                    "mainActorLongTaskDurationMs=\(artifactResult.mainActorLongTaskDurationMs)"
                ].joined(separator: ",")
            )
            return LocalNetworkSyncArtifactStatusResponse(
                ok: true,
                artifactID: artifact.artifactID,
                checksum: artifactResult.checksum,
                size: metadata.size,
                confirmedBytes: metadata.size,
                nextOffset: metadata.size,
                state: .complete,
                error: nil
            )
        } catch {
            emitConnectionDiagnostic(
                phase: "transferSessionStatusFailed",
                listenerState: "ready",
                activePort: activePort,
                errorCode: "sync_artifact_status_failed",
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
            return LocalNetworkSyncArtifactStatusResponse(
                ok: false,
                artifactID: nil,
                checksum: nil,
                size: nil,
                confirmedBytes: nil,
                nextOffset: nil,
                state: nil,
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    @MainActor
    func localNetworkSyncArtifactPutResponseForVerifiedDevice(
        _ device: PairedDevice,
        requestBody: Data
    ) async -> LocalNetworkSyncArtifactPutResponse {
        _ = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: "artifact-put")
        emitConnectionDiagnostic(phase: "uploadActionStarted", listenerState: "ready", activePort: activePort)

        do {
            let request = try await Self.decodeSyncBodyOffMain(LocalNetworkSyncArtifactPutRequest.self, from: requestBody)
            try LocalNetworkSyncArtifactID.validate(request.artifactID)
            try LocalNetworkSyncArtifactID.validateLogicalPathToken(request.logicalPathToken, for: request.kind)
            guard request.kind.isAutoDownloadAllowed else {
                throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
            }
            guard request.artifactID == LocalNetworkSyncArtifactID.make(
                kind: request.kind,
                ownerID: request.ownerID,
                logicalPathToken: request.logicalPathToken
            ) else {
                throw LocalNetworkSyncArtifactValidationError.invalidArtifactID
            }
            guard request.size >= 0 else {
                throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
            }

            let artifactURL = try LocalNetworkSyncArtifactFileService.safeFileURL(
                rootURL: recordingFileStore.libraryRootURL,
                logicalPathToken: request.logicalPathToken,
                kind: request.kind
            )
            let writeResult = try await performArtifactPutIO(
                request: request,
                artifactURL: artifactURL
            )
            emitConnectionDiagnostic(phase: "fileTransferStarted", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(phase: "fileTransferProgressUpdated", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(
                phase: "artifactBackgroundWriteCompleted",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: request.syncRunID,
                errorMessage: [
                    "writeDurationMs=\(writeResult.ioDurationMs)",
                    "mainActorLongTaskDurationMs=\(writeResult.mainActorLongTaskDurationMs)"
                ].joined(separator: ",")
            )
            if writeResult.didFinalize {
                emitConnectionDiagnostic(phase: "artifactChecksumVerified", listenerState: "ready", activePort: activePort)
                emitConnectionDiagnostic(phase: "checksumVerified", listenerState: "ready", activePort: activePort)
                emitConnectionDiagnostic(phase: "atomicReplaceCompleted", listenerState: "ready", activePort: activePort)
                emitConnectionDiagnostic(phase: "peerFileApplied", listenerState: "ready", activePort: activePort)
                emitConnectionDiagnostic(phase: "fileTransferCompleted", listenerState: "ready", activePort: activePort)
            }

            emitConnectionDiagnostic(phase: "uploadActionCompleted", listenerState: "ready", activePort: activePort)
            return LocalNetworkSyncArtifactPutResponse(
                ok: true,
                artifactID: request.artifactID,
                disposition: writeResult.disposition,
                checksum: request.checksum,
                size: request.size,
                confirmedBytes: writeResult.confirmedBytes,
                error: nil
            )
        } catch {
            if error.localizedDescription == "sync_artifact_offset_mismatch" {
                emitConnectionDiagnostic(
                    phase: "transferOffsetMismatch",
                    listenerState: "ready",
                    activePort: activePort,
                    requestDeviceIDPrefix: device.idPrefix,
                    errorCode: "sync_artifact_offset_mismatch"
                )
            }
            emitConnectionDiagnostic(
                phase: "uploadActionFailed",
                listenerState: "ready",
                activePort: activePort,
                errorCode: "sync_artifact_put_failed",
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
            return LocalNetworkSyncArtifactPutResponse(
                ok: false,
                artifactID: nil,
                disposition: nil,
                checksum: nil,
                size: nil,
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    @MainActor
    func localNetworkSyncArtifactPutResponseForVerifiedDeviceInBackground(
        _ device: PairedDevice,
        requestBody: Data
    ) async -> LocalNetworkSyncArtifactPutResponse {
        _ = markDeviceOnline(device: device, displayName: device.deviceName, syncStatus: "artifact-put")
        emitConnectionDiagnostic(phase: "uploadActionStarted", listenerState: "ready", activePort: activePort)

        do {
            let request = try await Self.decodeSyncBodyOffMain(LocalNetworkSyncArtifactPutRequest.self, from: requestBody)
            try LocalNetworkSyncArtifactID.validate(request.artifactID)
            try LocalNetworkSyncArtifactID.validateLogicalPathToken(request.logicalPathToken, for: request.kind)
            guard request.kind.isAutoDownloadAllowed else {
                throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
            }
            guard request.artifactID == LocalNetworkSyncArtifactID.make(
                kind: request.kind,
                ownerID: request.ownerID,
                logicalPathToken: request.logicalPathToken
            ) else {
                throw LocalNetworkSyncArtifactValidationError.invalidArtifactID
            }
            guard request.size >= 0 else {
                throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
            }

            let artifactURL = try LocalNetworkSyncArtifactFileService.safeFileURL(
                rootURL: recordingFileStore.libraryRootURL,
                logicalPathToken: request.logicalPathToken,
                kind: request.kind
            )
            let writeResult = try await performArtifactPutIO(
                request: request,
                artifactURL: artifactURL
            )
            emitConnectionDiagnostic(phase: "fileTransferStarted", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(phase: "fileTransferProgressUpdated", listenerState: "ready", activePort: activePort)
            emitConnectionDiagnostic(
                phase: "artifactBackgroundWriteCompleted",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: request.syncRunID,
                errorMessage: [
                    "writeDurationMs=\(writeResult.ioDurationMs)",
                    "mainActorLongTaskDurationMs=\(writeResult.mainActorLongTaskDurationMs)"
                ].joined(separator: ",")
            )
            if writeResult.didFinalize {
                emitConnectionDiagnostic(phase: "artifactChecksumVerified", listenerState: "ready", activePort: activePort)
                emitConnectionDiagnostic(phase: "checksumVerified", listenerState: "ready", activePort: activePort)
                emitConnectionDiagnostic(phase: "atomicReplaceCompleted", listenerState: "ready", activePort: activePort)
                emitConnectionDiagnostic(phase: "peerFileApplied", listenerState: "ready", activePort: activePort)
                emitConnectionDiagnostic(phase: "fileTransferCompleted", listenerState: "ready", activePort: activePort)
            }

            emitConnectionDiagnostic(phase: "uploadActionCompleted", listenerState: "ready", activePort: activePort)
            return LocalNetworkSyncArtifactPutResponse(
                ok: true,
                artifactID: request.artifactID,
                disposition: writeResult.disposition,
                checksum: request.checksum,
                size: request.size,
                confirmedBytes: writeResult.confirmedBytes,
                error: nil
            )
        } catch {
            if error.localizedDescription == "sync_artifact_offset_mismatch" {
                emitConnectionDiagnostic(
                    phase: "transferOffsetMismatch",
                    listenerState: "ready",
                    activePort: activePort,
                    requestDeviceIDPrefix: device.idPrefix,
                    errorCode: "sync_artifact_offset_mismatch"
                )
            }
            emitConnectionDiagnostic(
                phase: "uploadActionFailed",
                listenerState: "ready",
                activePort: activePort,
                errorCode: "sync_artifact_put_failed",
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
            return LocalNetworkSyncArtifactPutResponse(
                ok: false,
                artifactID: nil,
                disposition: nil,
                checksum: nil,
                size: nil,
                error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
    }

    private nonisolated static func artifactFileMetadataOffMain(
        fileURL: URL
    ) async -> (metadata: (size: Int64, updatedAt: Date)?, ioDurationMs: Int, mainActorLongTaskDurationMs: Int) {
        let detachedStartedAt = Date()
        let result = await Task.detached(priority: .utility) {
            let startedAt = Date()
            let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
            let metadata = LocalNetworkSyncArtifactFileService.metadata(for: fileURL)
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            return (
                metadata: metadata,
                ioDurationMs: durationMs,
                mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
            )
        }.value
        Task { @MainActor in
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .waitBackgroundMs,
                    durationMs: CanonicalPerfLog.elapsedMs(since: detachedStartedAt),
                    result: "artifactMetadata"
                )
            )
        }
        return result
    }

    private nonisolated static func artifactFileMetadataAndChecksumOffMain(
        fileURL: URL,
        logicalToken: String?,
        checksumRuntime: CanonicalChecksumRuntime,
        cacheDirectoryURL: URL,
        configuration: CanonicalInventoryRuntimeConfiguration
    ) async -> (metadata: (size: Int64, updatedAt: Date)?, checksum: String?, ioDurationMs: Int, mainActorLongTaskDurationMs: Int) {
        let metadataStartedAt = Date()
        let metadataResult = await Task.detached(priority: .utility) {
            let startedAt = Date()
            let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
            let metadata = LocalNetworkSyncArtifactFileService.metadata(for: fileURL)
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            return (
                metadata: metadata,
                ioDurationMs: durationMs,
                mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
            )
        }.value
        Task { @MainActor in
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .waitBackgroundMs,
                    durationMs: CanonicalPerfLog.elapsedMs(since: metadataStartedAt),
                    result: "artifactMetadata"
                )
            )
        }
        guard let metadata = metadataResult.metadata else {
            return (
                metadata: nil,
                checksum: nil,
                ioDurationMs: metadataResult.ioDurationMs,
                mainActorLongTaskDurationMs: metadataResult.mainActorLongTaskDurationMs
            )
        }
        let checksumResult = await checksumRuntime.checksum(
            fileURL: fileURL,
            logicalToken: logicalToken,
            nodeRole: .mac,
            cacheDirectoryURL: cacheDirectoryURL,
            configuration: configuration,
            metadataProvider: { _ in
                CanonicalChecksumFileMetadata(byteSize: metadata.size, modifiedAt: metadata.updatedAt)
            }
        )
        let checksumDurationMs = checksumResult.hashDurationMs
            + checksumResult.cacheLoadDurationMs
            + checksumResult.cacheWriteDurationMs
            + checksumResult.cachePruneDurationMs
        if checksumDurationMs > 0 {
            Task { @MainActor in
                ConnectionDiagnosticsStore.shared.recordPerfLog(
                    CanonicalPerfLog.subphaseMeasured(
                        operation: .immediateSync,
                        subphase: .hashMs,
                        durationMs: checksumDurationMs,
                        result: "artifactChecksum"
                    )
                )
            }
        }
        return (
            metadata: metadata,
            checksum: checksumResult.sha256,
            ioDurationMs: metadataResult.ioDurationMs + checksumDurationMs,
            mainActorLongTaskDurationMs: metadataResult.mainActorLongTaskDurationMs + (checksumResult.mainActorHashAttemptCount > 0 ? checksumDurationMs : 0)
        )
    }

    private nonisolated static func artifactChunkDataAndChecksumOffMain(
        fileURL: URL,
        offset: Int64,
        length: Int
    ) async throws -> (dataBase64: String, byteCount: Int, checksum: String, ioDurationMs: Int, mainActorLongTaskDurationMs: Int) {
        let detachedStartedAt = Date()
        let result = try await Task.detached(priority: .utility) {
            let startedAt = Date()
            let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
            let data = try readArtifactChunk(fileURL: fileURL, offset: offset, length: length)
            let checksum = Self.sha256Hex(data)
            let dataBase64 = data.base64EncodedString()
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            return (
                dataBase64: dataBase64,
                byteCount: data.count,
                checksum: checksum,
                ioDurationMs: durationMs,
                mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
            )
        }.value
        Task { @MainActor in
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .hashMs,
                    durationMs: CanonicalPerfLog.elapsedMs(since: detachedStartedAt),
                    result: "artifactChunkChecksum"
                )
            )
        }
        return result
    }

    private nonisolated static func readArtifactChunk(fileURL: URL, offset: Int64, length: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: length) ?? Data()
        guard !data.isEmpty else {
            throw LocalNetworkSyncArtifactValidationError.artifactNotFound
        }
        return data
    }

    private func syncArtifactIncomingTempURL(artifactID: String) throws -> URL {
        try Self.syncArtifactIncomingTempURL(rootURL: recordingFileStore.libraryRootURL, artifactID: artifactID)
    }

    private nonisolated static func syncArtifactIncomingTempURL(rootURL: URL, artifactID: String) throws -> URL {
        try LocalNetworkSyncArtifactID.validate(artifactID)
        return rootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("Incoming", isDirectory: true)
            .appendingPathComponent("\(artifactID).part", isDirectory: false)
    }

    private func performArtifactPutIO(
        request: LocalNetworkSyncArtifactPutRequest,
        artifactURL: URL
    ) async throws -> (disposition: String, confirmedBytes: Int64, didFinalize: Bool, ioDurationMs: Int, mainActorLongTaskDurationMs: Int) {
        let startedAt = Date()
        let rootURL = recordingFileStore.libraryRootURL
        let maxChunkBytes = syncArtifactChunkBytes
        let writeQueue = backgroundWriteQueue
        let checksumRuntime = canonicalChecksumRuntime
        let cacheDirectoryURL = canonicalChecksumCacheDirectory()
        let configuration = inventoryRuntimeConfiguration
        let writeResult = try await Self.performArtifactPutWritePhase(
            request: request,
            rootURL: rootURL,
            maxChunkBytes: maxChunkBytes,
            writeQueue: writeQueue
        )
        if !writeResult.didFinalize {
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            return (
                disposition: writeResult.disposition ?? "acceptedChunk",
                confirmedBytes: writeResult.confirmedBytes,
                didFinalize: false,
                ioDurationMs: durationMs,
                mainActorLongTaskDurationMs: writeResult.mainActorLongTaskDurationMs
            )
        }

        var verificationConfiguration = configuration
        verificationConfiguration.persistentChecksumCacheEnabled = false
        let tempChecksum = await checksumRuntime.checksum(
            fileURL: writeResult.tempURL,
            logicalToken: "Sync/Incoming/\(request.artifactID).part",
            nodeRole: .mac,
            cacheDirectoryURL: cacheDirectoryURL,
            configuration: verificationConfiguration
        )
        guard tempChecksum.sha256 == request.checksum else {
            throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
        }

        let existingChecksum = await checksumRuntime.checksum(
            fileURL: artifactURL,
            logicalToken: request.logicalPathToken,
            nodeRole: .mac,
            cacheDirectoryURL: cacheDirectoryURL,
            configuration: configuration
        ).sha256
        let disposition = try await Self.applySyncedArtifactOnQueue(
            tempURL: writeResult.tempURL,
            artifactURL: artifactURL,
            checksum: request.checksum,
            existingChecksum: existingChecksum,
            writeQueue: writeQueue
        )
        let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        return (
            disposition: disposition,
            confirmedBytes: writeResult.confirmedBytes,
            didFinalize: true,
            ioDurationMs: durationMs,
            mainActorLongTaskDurationMs: writeResult.mainActorLongTaskDurationMs + (tempChecksum.mainActorHashAttemptCount > 0 ? tempChecksum.hashDurationMs : 0)
        )
    }

    private nonisolated static func performArtifactPutWritePhase(
        request: LocalNetworkSyncArtifactPutRequest,
        rootURL: URL,
        maxChunkBytes: Int,
        writeQueue: DispatchQueue
    ) async throws -> (tempURL: URL, disposition: String?, confirmedBytes: Int64, didFinalize: Bool, mainActorLongTaskDurationMs: Int) {
        try await withCheckedThrowingContinuation { continuation in
            writeQueue.async {
                let startedAt = Date()
                let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
                do {
                    let result = try Self.performArtifactPutWritePhaseBody(
                        request: request,
                        rootURL: rootURL,
                        maxChunkBytes: maxChunkBytes
                    )
                    let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                    continuation.resume(returning: (
                        tempURL: result.tempURL,
                        disposition: result.disposition,
                        confirmedBytes: result.confirmedBytes,
                        didFinalize: result.didFinalize,
                        mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func performArtifactPutWritePhaseBody(
        request: LocalNetworkSyncArtifactPutRequest,
        rootURL: URL,
        maxChunkBytes: Int
    ) throws -> (tempURL: URL, disposition: String?, confirmedBytes: Int64, didFinalize: Bool) {
        guard let data = Data(base64Encoded: request.dataBase64) else {
            throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
        }
        let isChunked = request.offset != nil || request.chunkSize != nil || request.totalSize != nil || request.isFinalChunk != nil
        let tempURL = try syncArtifactIncomingTempURL(rootURL: rootURL, artifactID: request.artifactID)
        if isChunked {
            let offset = request.offset ?? 0
            let chunkSize = request.chunkSize ?? data.count
            guard offset >= 0,
                  chunkSize == data.count,
                  data.count <= maxChunkBytes,
                  request.totalSize == request.size,
                  offset + Int64(data.count) <= request.size else {
                throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
            }
            try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if offset == 0, FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            if offset > 0 {
                guard let tempSize = LocalNetworkSyncArtifactFileService.metadata(for: tempURL)?.size,
                      tempSize == offset else {
                    throw NSError(domain: "RokuricsSync", code: 409, userInfo: [NSLocalizedDescriptionKey: "sync_artifact_offset_mismatch"])
                }
            }
            if !FileManager.default.fileExists(atPath: tempURL.path) {
                _ = FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: tempURL)
            defer {
                try? handle.close()
            }
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
            let confirmedBytes = offset + Int64(data.count)
            if request.isFinalChunk == true {
                guard confirmedBytes == request.size,
                      LocalNetworkSyncArtifactFileService.metadata(for: tempURL)?.size == request.size else {
                    throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
                }
                return (tempURL: tempURL, disposition: nil, confirmedBytes: confirmedBytes, didFinalize: true)
            }
            return (tempURL: tempURL, disposition: "acceptedChunk", confirmedBytes: confirmedBytes, didFinalize: false)
        }

        guard request.size <= 4 * 1024 * 1024,
              data.count == Int(request.size),
              sha256Hex(data) == request.checksum else {
            throw LocalNetworkSyncArtifactValidationError.unsupportedArtifactKind
        }
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        try FileManager.default.createDirectory(at: tempURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: tempURL, options: .atomic)
        return (tempURL: tempURL, disposition: nil, confirmedBytes: Int64(data.count), didFinalize: true)
    }

    private nonisolated static func applySyncedArtifactOnQueue(
        tempURL: URL,
        artifactURL: URL,
        checksum: String,
        existingChecksum: String?,
        writeQueue: DispatchQueue
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            writeQueue.async {
                do {
                    continuation.resume(returning: try applySyncedArtifact(
                        tempURL: tempURL,
                        artifactURL: artifactURL,
                        checksum: checksum,
                        existingChecksum: existingChecksum
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated static func applySyncedArtifact(
        tempURL: URL,
        artifactURL: URL,
        checksum: String,
        existingChecksum: String?
    ) throws -> String {
        let disposition = existingChecksum == checksum ? "acceptedExisting" : "acceptedNew"
        try FileManager.default.createDirectory(at: artifactURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if existingChecksum == checksum {
            try? FileManager.default.removeItem(at: tempURL)
        } else if FileManager.default.fileExists(atPath: artifactURL.path) {
            _ = try FileManager.default.replaceItemAt(artifactURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: artifactURL)
        }
        return disposition
    }

    private nonisolated static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).hexString
    }

    @MainActor
    private func handleLocalNetworkSyncInventoryRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            let inventoryRequest = try? await Self.decodeSyncBodyOffMain(LocalNetworkSyncInventoryRequest.self, from: request.body)
            let syncRunID = inventoryRequest?.syncRunID
            if CanonicalLiveReadOnlyTransportProbeHTTP.isMarked(headers: request.headers) {
                await handleCanonicalLiveReadOnlyInventoryProbeRequest(
                    request,
                    device: device,
                    syncRunID: syncRunID,
                    on: connection
                )
                return
            }
            emitConnectionDiagnostic(phase: "syncTickStarted", listenerState: "ready", activePort: activePort, syncRunID: syncRunID)
            sendJSON(
                statusCode: 200,
                reason: "OK",
                body: await localNetworkSyncInventoryResponseForVerifiedDevice(
                    device,
                    syncRunID: syncRunID,
                    requestEnvelope: inventoryRequest?.statusExchangeEnvelope
                ),
                on: connection
            )
            emitConnectionDiagnostic(phase: "peerInventoryFetched", listenerState: "ready", activePort: activePort, syncRunID: syncRunID)
        case .rejected(let reason):
            emitConnectionDiagnostic(phase: "syncTickFailed", listenerState: "ready", activePort: activePort, errorCode: reason)
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleCanonicalLiveReadOnlyInventoryProbeRequest(
        _ request: HTTPRequest,
        device: PairedDevice,
        syncRunID: String?,
        on connection: NWConnection
    ) async {
        let gate = canonicalLiveReadOnlyProbeGate(for: request)
        let snapshotDate = Date(timeIntervalSince1970: 0)
        let before = await captureReadOnlyProbeStateSnapshotInBackground(
            manifestGeneratedAt: snapshotDate,
            syncRunID: syncRunID,
            context: "probeBefore"
        )
        emitConnectionDiagnostic(
            phase: CanonicalLiveReadOnlyTransportProbeDiagnosticKind.canonicalLiveReadOnlyProbeMacAuditStarted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            routePath: request.path,
            requestDeviceIDPrefix: device.idPrefix,
            verifierStartedAt: requestVerifier.lastTrace?.verifierStartedAt,
            verifierSucceeded: requestVerifier.lastTrace?.verifierSucceeded,
            verifierFailed: requestVerifier.lastTrace?.verifierFailedReason != nil,
            markDeviceSeenCalled: requestVerifier.lastTrace?.markDeviceSeenCalled,
            pairedDeviceLastSeenBefore: requestVerifier.lastTrace?.pairedDeviceLastSeenBefore,
            pairedDeviceLastSeenAfter: requestVerifier.lastTrace?.pairedDeviceLastSeenAfter,
            syncRunID: syncRunID,
            errorMessage: "route=\(gate.route.method) \(gate.route.path),routeStatus=\(gate.routeStatus.rawValue),reason=\(gate.reason)"
        )
        guard gate.routeStatus == .allowedReadOnly, gate.shouldSend else {
            let after = await captureReadOnlyProbeStateSnapshotInBackground(
                manifestGeneratedAt: snapshotDate,
                syncRunID: syncRunID,
                context: "probeRejectedAfter"
            )
            let audit = MacCanonicalReadOnlyTransportProbeAudit(gate: gate, before: before, after: after)
            emitConnectionDiagnostic(
                phase: CanonicalLiveReadOnlyTransportProbeDiagnosticKind.canonicalLiveReadOnlyProbeMutationRiskBlocked.rawValue,
                listenerState: "ready",
                activePort: activePort,
                routePath: request.path,
                requestDeviceIDPrefix: device.idPrefix,
                syncRunID: syncRunID,
                errorCode: gate.failure?.rawValue,
                errorMessage: audit.diagnosticsSummary
            )
            sendError(statusCode: 400, reason: "Bad Request", error: "canonical_live_probe_route_blocked", on: connection)
            return
        }

        let inventory = await makeLocalNetworkSyncInventory(sourceKind: .inventoryRequest)
        sendJSON(
            statusCode: 200,
            reason: "OK",
            body: LocalNetworkSyncInventoryResponse(ok: true, inventory: inventory, error: nil),
            on: connection
        )
        let after = await captureReadOnlyProbeStateSnapshotInBackground(
            manifestGeneratedAt: snapshotDate,
            syncRunID: syncRunID,
            context: "probeAfter"
        )
        let audit = MacCanonicalReadOnlyTransportProbeAudit(gate: gate, before: before, after: after)
        emitConnectionDiagnostic(
            phase: CanonicalLiveReadOnlyTransportProbeDiagnosticKind.canonicalLiveReadOnlyProbeMacAuditCompleted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            routePath: request.path,
            requestDeviceIDPrefix: device.idPrefix,
            syncRunID: syncRunID,
            errorMessage: audit.diagnosticsSummary
        )
        if audit.stateSnapshotUnavailable {
            emitConnectionDiagnostic(
                phase: CanonicalLiveReadOnlyTransportProbeDiagnosticKind.canonicalLiveReadOnlyProbeStateSnapshotUnavailable.rawValue,
                listenerState: "ready",
                activePort: activePort,
                routePath: request.path,
                requestDeviceIDPrefix: device.idPrefix,
                syncRunID: syncRunID,
                errorMessage: audit.diagnosticsSummary
            )
        } else if audit.noMutationVerified {
            emitConnectionDiagnostic(
                phase: CanonicalLiveReadOnlyTransportProbeDiagnosticKind.canonicalLiveReadOnlyProbeNoMutationVerified.rawValue,
                listenerState: "ready",
                activePort: activePort,
                routePath: request.path,
                requestDeviceIDPrefix: device.idPrefix,
                syncRunID: syncRunID,
                errorMessage: audit.diagnosticsSummary
            )
        } else {
            emitConnectionDiagnostic(
                phase: CanonicalLiveReadOnlyTransportProbeDiagnosticKind.canonicalLiveReadOnlyProbeMutationRiskBlocked.rawValue,
                listenerState: "ready",
                activePort: activePort,
                routePath: request.path,
                requestDeviceIDPrefix: device.idPrefix,
                syncRunID: syncRunID,
                errorCode: "read_only_probe_mutation_detected",
                errorMessage: audit.diagnosticsSummary
            )
        }
    }

    private func handleLocalNetworkSyncApplyMetadataRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        switch await requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            do {
                emitConnectionDiagnostic(phase: "uploadActionStarted", listenerState: "ready", activePort: activePort)
                let response = try await localNetworkSyncApplyMetadataResponseForVerifiedDeviceInBackground(device, requestBody: request.body)
                sendJSON(statusCode: 200, reason: "OK", body: response, on: connection)
                emitConnectionDiagnostic(phase: "uploadActionCompleted", listenerState: "ready", activePort: activePort)
            } catch {
                await MainActor.run {
                    syncStateStore.recordFailure(deviceID: device.id, error: error.localizedDescription)
                }
                emitConnectionDiagnostic(phase: "uploadActionFailed", listenerState: "ready", activePort: activePort, errorCode: "sync_apply_metadata_failed", errorMessage: error.localizedDescription)
                sendError(statusCode: 400, reason: "Bad Request", error: error.localizedDescription, on: connection)
            }
        case .rejected(let reason):
            emitConnectionDiagnostic(phase: "uploadActionFailed", listenerState: "ready", activePort: activePort, errorCode: reason)
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleLocalNetworkSyncStartRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            let response = localNetworkSyncStartResponseForVerifiedDevice(device, requestBody: request.body)
            sendJSON(
                statusCode: response.ok ? 200 : 400,
                reason: response.ok ? "OK" : "Bad Request",
                body: response,
                on: connection
            )
        case .rejected(let reason):
            emitConnectionDiagnostic(phase: "syncStartSignalRejected", listenerState: "ready", activePort: activePort, errorCode: reason)
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleLocalNetworkSyncStartAckRequest(_ request: HTTPRequest, on connection: NWConnection) {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            let response = localNetworkSyncStartAckResponseForVerifiedDevice(device, requestBody: request.body)
            sendJSON(
                statusCode: response.ok ? 200 : 400,
                reason: response.ok ? "OK" : "Bad Request",
                body: response,
                on: connection
            )
        case .rejected(let reason):
            emitConnectionDiagnostic(phase: "syncStartAckRejected", listenerState: "ready", activePort: activePort, errorCode: reason)
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleLocalNetworkSyncArtifactStatusRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            let response = await localNetworkSyncArtifactStatusResponseForVerifiedDevice(device, requestBody: request.body)
            sendJSON(
                statusCode: response.ok ? 200 : 400,
                reason: response.ok ? "OK" : "Bad Request",
                body: response,
                on: connection
            )
        case .rejected(let reason):
            emitConnectionDiagnostic(phase: "transferSessionStatusFailed", listenerState: "ready", activePort: activePort, errorCode: reason)
            sendError(statusCode: 400, reason: "Bad Request", error: reason, on: connection)
        }
    }

    @MainActor
    private func handleLocalNetworkSyncArtifactRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            let response = await localNetworkSyncArtifactResponseForVerifiedDevice(device, requestBody: request.body)
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
    private func handleLocalNetworkSyncArtifactPutRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        switch requestVerifier.verify(method: request.method, path: request.path, headers: request.headers, body: request.body) {
        case .accepted(let device):
            let response = await localNetworkSyncArtifactPutResponseForVerifiedDeviceInBackground(device, requestBody: request.body)
            sendJSON(
                statusCode: response.ok ? 200 : 400,
                reason: response.ok ? "OK" : "Bad Request",
                body: response,
                on: connection
            )
        case .rejected(let reason):
            emitConnectionDiagnostic(phase: "uploadActionFailed", listenerState: "ready", activePort: activePort, errorCode: reason)
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

    private func handleRecordingMetadataUploadRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        let response = await recordingUploadRouteHandler.metadataUploadResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    private func handleRecordingAudioUploadRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        let response = await recordingUploadRouteHandler.audioUploadResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    private func handleResumableAudioStartRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        let response = await recordingUploadRouteHandler.resumableAudioStartResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    private func handleResumableAudioStatusRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        let response = await recordingUploadRouteHandler.resumableAudioStatusResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    private func handleResumableAudioChunkRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        let response = await recordingUploadRouteHandler.resumableAudioChunkResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        sendRouteResponse(response, on: connection)
    }

    private func handleResumableAudioFinalizeRequest(_ request: HTTPRequest, on connection: NWConnection) async {
        let response = await recordingUploadRouteHandler.resumableAudioFinalizeResponse(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: request.body
        )
        let requestBody = request.body
        sendRouteResponse(response, on: connection)
        Task { [weak self, requestBody, response] in
            await self?.produceMacTransferFinalizeProofFactIfPresent(
                requestBody: requestBody,
                response: response
            )
        }
    }

    private func produceMacTransferFinalizeProofFactIfPresent(
        requestBody: Data,
        response: SecureLocalHTTPRouteResponse
    ) async {
        guard canonicalKernelMode == .canonicalFullSync,
              response.statusCode == 200,
              let finalizeRequest = try? Self.syncJSONDecoder.decode(ResumableAudioUploadFinalizeRequest.self, from: requestBody),
              let finalizeResponse = try? Self.syncJSONDecoder.decode(ResumableAudioUploadSessionResponse.self, from: response.bodyData),
              finalizeResponse.completed,
              let checksum = finalizeResponse.checksum,
              let fileSize = finalizeResponse.fileSize else {
            return
        }
        let objectID = Self.canonicalAudioObjectID(recordingID: finalizeRequest.recordingID)
        let receiverNodeID = CanonicalNodeID("mac-local")
        let proof = CanonicalTransferFinalizeProof.v930(
            receiverNodeID: receiverNodeID,
            sessionID: CanonicalTransferSessionID(finalizeRequest.sessionID),
            objectID: objectID,
            byteSize: fileSize,
            contentHash: CanonicalHash(checksum),
            finalizedAt: CanonicalTimestamp(Date()),
            verified: fileSize == finalizeRequest.totalBytes && checksum == finalizeRequest.totalSHA256
        )
        guard proof.isReceiverAcceptedProof else {
            return
        }
        let fact = CanonicalStatusFact(
            factID: "mac-transfer-finalize-\(Self.safeFactToken(finalizeRequest.sessionID))-\(Self.safeFactToken(finalizeRequest.recordingID))",
            objectID: objectID,
            source: .transferFinalizeProof,
            producerNodeID: receiverNodeID,
            logicalTime: CanonicalLogicalTime(
                counter: UInt64(max(0, proof.finalizedAt.date.timeIntervalSince1970.rounded())),
                nodeID: receiverNodeID
            ),
            proof: CanonicalStatusProof(
                kind: .finalizeProof,
                objectID: objectID,
                hash: proof.contentHash,
                byteSize: proof.byteSize,
                peerNodeID: receiverNodeID,
                finalizeProof: proof,
                observedAt: proof.finalizedAt
            ),
            domain: .audioUpload,
            phase: .completed,
            causality: CanonicalStatusCausality(trigger: .transferFinalize)
        )
        _ = await produceCanonicalStatusFact(fact)
    }

    private nonisolated static func safeFactToken(_ value: String) -> String {
        let allowed = value.filter { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
        return String((allowed.isEmpty ? "unknown" : allowed).prefix(48))
    }

    private nonisolated static func canonicalAudioObjectID(recordingID: String) -> CanonicalObjectID {
        CanonicalObjectID("recordingAudio:\(recordingID)")
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
        case "/sync/start", "/sync/start-ack":
            return 64 * 1024
        case "/sync/artifact-status":
            return 256 * 1024
        case "/sync/artifact-request":
            return 256 * 1024
        case "/sync/artifact-put":
            return 6 * 1024 * 1024
        default:
            return 1 * 1024 * 1024
        }
    }

    private func loadMacInventoryBackgroundInput(
        generatedAt: Date
    ) async -> MacLocalNetworkSyncInventoryBackgroundInput {
        let rootURL = recordingFileStore.libraryRootURL
        let deviceID = localSyncDeviceID
        let checksumRuntime = canonicalChecksumRuntime
        let cacheDirectoryURL = canonicalChecksumCacheDirectory()
        let runtimeConfiguration = inventoryRuntimeConfiguration
        let startedAt = Date()
        let input = await Task.detached(priority: .utility) {
            let scanStartedAt = Date()
            let scanMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            let metadataStartedAt = Date()
            let metadataMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            let inboxItems = MacLocalNetworkSyncInventoryBackgroundIO.loadInboxItems(rootURL: rootURL)
            let existenceRecords = MacLocalNetworkSyncInventoryBackgroundIO.loadExistenceRecords(rootURL: rootURL)
            let manifestStartedAt = Date()
            let manifestBuildMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            let manifest = MacLocalNetworkSyncBackgroundStudyManifestBuilder(
                fileManager: .default,
                rootURL: rootURL,
                inboxItems: inboxItems,
                deviceID: deviceID,
                generatedAt: generatedAt
            ).build()
            let manifestBuildDurationMs = max(0, Int(Date().timeIntervalSince(manifestStartedAt) * 1_000))
            let metadataLoadDurationMs = max(0, Int(Date().timeIntervalSince(metadataStartedAt) * 1_000))
            let jobsStartedAt = Date()
            let jobsMainActorAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            MacLocalNetworkSyncInventoryBackgroundIO.probeUploadJobsLedger(rootURL: rootURL)
            let jobsLoadDurationMs = max(0, Int(Date().timeIntervalSince(jobsStartedAt) * 1_000))
            let hashStartedAt = Date()
            let recordingMetadataHashesByID = Dictionary(
                manifest.recordings.compactMap { entry -> (String, String)? in
                    guard let hash = entry.metadataHash else {
                        return nil
                    }
                    return (entry.recordingID, hash)
                },
                uniquingKeysWith: { _, latest in latest }
            )
            let folderRevisionHashesByID = Dictionary(
                manifest.folders.map { folder in
                    (folder.folderID, LocalNetworkSyncMetadataHash.hash(folder))
                },
                uniquingKeysWith: { _, latest in latest }
            )
            let studyItemRevisionHashesByID = Dictionary(
                manifest.items.map { item in
                    (item.itemID, LocalNetworkSyncMetadataHash.hash(item))
                },
                uniquingKeysWith: { _, latest in latest }
            )
            let artifactBuild = await MacLocalNetworkSyncBackgroundArtifactBuilder.makeArtifacts(
                from: manifest,
                rootURL: rootURL,
                checksumRuntime: checksumRuntime,
                cacheDirectoryURL: cacheDirectoryURL,
                configuration: runtimeConfiguration
            )
            let metadataHashDurationMs = max(0, Int(Date().timeIntervalSince(hashStartedAt) * 1_000))
            let scanDurationMs = max(0, Int(Date().timeIntervalSince(scanStartedAt) * 1_000))
            return MacLocalNetworkSyncInventoryBackgroundInput(
                manifest: manifest,
                inboxItems: inboxItems,
                existenceRecords: existenceRecords,
                rootURL: rootURL,
                recordingMetadataHashesByID: recordingMetadataHashesByID,
                folderRevisionHashesByID: folderRevisionHashesByID,
                studyItemRevisionHashesByID: studyItemRevisionHashesByID,
                artifacts: artifactBuild.artifacts,
                diagnostics: CanonicalInventoryRuntimeDiagnostics(
                    fileScanCount: inboxItems.count,
                    hashComputedCount: recordingMetadataHashesByID.count
                        + folderRevisionHashesByID.count
                        + studyItemRevisionHashesByID.count
                        + artifactBuild.hashComputedCount,
                    mainActorHashAttemptCount: 0,
                    mainActorScanAttemptCount: scanMainActorAttemptCount,
                    mainActorMetadataLoadAttemptCount: metadataMainActorAttemptCount,
                    mainActorJobsLoadAttemptCount: jobsMainActorAttemptCount,
                    mainActorManifestBuildAttemptCount: manifestBuildMainActorAttemptCount,
                    mainActorHashBlockedCount: 0,
                    mainActorScanBlockedCount: scanMainActorAttemptCount,
                    scanDurationMs: scanDurationMs,
                    manifestBuildDurationMs: manifestBuildDurationMs,
                    metadataLoadDurationMs: metadataLoadDurationMs,
                    jobsLoadDurationMs: jobsLoadDurationMs,
                    hashDurationMs: metadataHashDurationMs
                ),
                failures: []
            )
        }.value
        let inventoryBuildDurationMs = CanonicalPerfLog.elapsedMs(since: startedAt)
        let hashDurationMs = input.diagnostics.hashDurationMs
        Task { @MainActor in
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .inventoryBuildMs,
                    durationMs: inventoryBuildDurationMs,
                    result: "macInventoryInput"
                )
            )
            if hashDurationMs > 0 {
                ConnectionDiagnosticsStore.shared.recordPerfLog(
                    CanonicalPerfLog.subphaseMeasured(
                        operation: .immediateSync,
                        subphase: .hashMs,
                        durationMs: hashDurationMs,
                        result: "macInventoryHash"
                    )
                )
            }
        }
        return input
    }

    private func makeMacInventoryCanonicalSnapshotOffMain(
        input: MacInventoryCanonicalBuildInput
    ) async -> MacInventoryCanonicalSnapshot {
        let detachedStartedAt = Date()
        let snapshot = await Task.detached(priority: .utility) {
            let startedAt = Date()
            let mainActorBuildAttemptCount = CanonicalInventoryRuntimeExecutionProbe.isMainThread() ? 1 : 0
            let artifactFactsByRecordingID = Dictionary(
                grouping: input.recordings.map { entry in
                    Self.canonicalAudioFact(from: entry).makeArtifact(
                        objectID: entry.recordingID,
                        producedByNodeID: entry.sourceDeviceID
                    )
                } + input.artifacts.compactMap { artifact in
                    Self.canonicalGeneratedArtifact(
                        from: artifact,
                        nodeID: input.nodeID,
                        platform: "Mac"
                    )
                }
            ) { $0.objectID }
            let canonicalNode = CanonicalNode(
                nodeID: input.nodeID,
                platform: "Mac",
                capabilities: [
                    .recordingMetadata,
                    .audioArtifact,
                    .receiveRecord,
                    .transcriptArtifact,
                    .noteArtifact,
                    .summaryArtifact,
                    .objectProjection,
                    .canonicalLibraryObjectsV1,
                    .canonicalFolderObjectsV1,
                    .canonicalStudyItemObjectsV1,
                    .canonicalTransferStateV1,
                    .canonicalObjectProjectionV1,
                    .canonicalInventoryBuilderV1,
                    .canonicalRetirementReadinessV1
                ]
            )
            let canonicalRecordingObjects = MacCanonicalRecordingAdapter().makeObjects(
                inboxItems: input.inboxItems,
                studyItems: input.manifest.items,
                artifactFactsByRecordingID: artifactFactsByRecordingID,
                nodeID: input.nodeID
            )
            let libraryAdapter = MacCanonicalLibraryAdapter()
            let canonicalLibraryObjects = libraryAdapter.makeLibraryObjects(from: input.manifest)
            let canonicalLibraryTombstones = libraryAdapter.makeTombstones(from: input.manifest)
            let unsupportedObjects = libraryAdapter.makeUnsupportedObjects(from: input.manifest)
            let canonicalInventoryBuild = CanonicalInventoryBuilderContract().build(
                from: CanonicalInventoryInputSnapshot(
                    node: canonicalNode,
                    generatedAt: input.generatedAt,
                    recordingObjects: canonicalRecordingObjects,
                    libraryObjects: canonicalLibraryObjects,
                    libraryTombstones: canonicalLibraryTombstones,
                    unsupportedObjects: unsupportedObjects
                )
            )
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            let canonicalArtifactCount = canonicalRecordingObjects.reduce(0) { partial, object in
                partial + object.artifacts.count
            }
            return MacInventoryCanonicalSnapshot(
                manifest: canonicalInventoryBuild.manifest,
                coverage: canonicalInventoryBuild.coverage,
                buildDurationMs: durationMs,
                canonicalObjectCount: canonicalRecordingObjects.count
                    + canonicalLibraryObjects.count
                    + canonicalLibraryTombstones.count
                    + unsupportedObjects.count,
                canonicalArtifactCount: canonicalArtifactCount,
                recordingObjectCount: canonicalRecordingObjects.count,
                libraryObjectCount: canonicalLibraryObjects.count,
                tombstoneObjectCount: canonicalLibraryTombstones.count,
                unsupportedObjectCount: unsupportedObjects.count,
                mainActorBuildAttemptCount: mainActorBuildAttemptCount,
                builtOffMain: mainActorBuildAttemptCount == 0
            )
        }.value
        Task { @MainActor in
            ConnectionDiagnosticsStore.shared.recordPerfLog(
                CanonicalPerfLog.subphaseMeasured(
                    operation: .immediateSync,
                    subphase: .inventoryBuildMs,
                    durationMs: CanonicalPerfLog.elapsedMs(since: detachedStartedAt),
                    result: "macCanonicalInventoryBuild"
                )
            )
        }
        return snapshot
    }

    private func makeLocalNetworkSyncInventory(
        generatedAt: Date = Date(),
        shadowTrigger: String? = nil,
        shadowSyncRunID: String? = nil,
        sourceKind: CanonicalInventoryRuntimeSourceKind = .inventoryRequest
    ) async -> LocalNetworkSyncInventory {
        let startedAt = Date()
        let policy = MacInventoryCanonicalBuildPolicy.make(mode: canonicalKernelMode)
        var requestContext = MacInventoryRequestBuildContext(requestID: shadowSyncRunID ?? UUID().uuidString)
        emitConnectionDiagnostic(phase: "inventoryBuildStarted", listenerState: "ready", activePort: activePort, syncRunID: shadowSyncRunID)
        emitConnectionDiagnostic(
            phase: "macInventoryRouteStarted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: shadowSyncRunID,
            errorMessage: "requestID=\(String(requestContext.requestID.prefix(12))),mode=\(policy.mode.rawValue)"
        )
        emitConnectionDiagnostic(
            phase: "macInventoryManifestBuildStarted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: shadowSyncRunID
        )
        let input = await loadMacInventoryBackgroundInput(generatedAt: generatedAt)
        let manifest = input.manifest
        let inboxItems = input.inboxItems
        let recordingMetadataHashesByID = input.recordingMetadataHashesByID
        let folderRevisionHashesByID = input.folderRevisionHashesByID
        let studyItemRevisionHashesByID = input.studyItemRevisionHashesByID
        let artifacts = input.artifacts
        var runtimeDiagnostics = input.diagnostics
        emitConnectionDiagnostic(
            phase: "macInventoryManifestBuildOffMain",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: shadowSyncRunID,
            errorMessage: "offMain=\(input.diagnostics.mainActorManifestBuildAttemptCount == 0),durationMs=\(input.diagnostics.manifestBuildDurationMs)"
        )
        emitConnectionDiagnostic(
            phase: "macInventoryManifestBuildCompleted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: shadowSyncRunID,
            errorMessage: "recordings=\(manifest.recordings.count),items=\(manifest.items.count),folders=\(manifest.folders.count),manifestBuildDurationMs=\(input.diagnostics.manifestBuildDurationMs)"
        )
        emitConnectionDiagnostic(
            phase: "macInventoryMainActorManifestBuildAttempt",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: shadowSyncRunID,
            errorMessage: "count=\(input.diagnostics.mainActorManifestBuildAttemptCount)"
        )
        let cacheDirectoryURL = canonicalChecksumCacheDirectory()
        var recordings: [LocalNetworkSyncRecordingEntry] = []
        recordings.reserveCapacity(inboxItems.count)
        for item in inboxItems {
            let metadataHash = recordingMetadataHashesByID[item.id]
            let audioURL = item.audioRelativePath.flatMap { relativePath in
                try? LocalNetworkSyncArtifactFileService.safeFileURL(
                    rootURL: recordingFileStore.libraryRootURL,
                    logicalPathToken: relativePath
                )
            }
            let storedChecksum = item.audioChecksum?.trimmingCharacters(in: .whitespacesAndNewlines)
            let checksumResult: LocalNetworkChecksumCacheResult?
            if item.hasAudio, let audioURL {
                let runtimeResult = await cachedRuntimeChecksum(
                    fileURL: audioURL,
                    pathToken: item.audioRelativePath,
                    recordingID: item.id,
                    syncRunID: shadowSyncRunID,
                    cacheDirectoryURL: cacheDirectoryURL
                )
                runtimeDiagnostics.merge(runtimeResult.runtimeResult)
                checksumResult = runtimeResult.legacyResult
            } else {
                checksumResult = nil
            }
            let recomputedChecksum = checksumResult?.sha256
            let audioChecksum = recomputedChecksum ?? (storedChecksum?.isEmpty == false ? storedChecksum : nil)
            let audioSize = item.hasAudio ? (checksumResult?.size ?? item.fileSize) : nil
            let traceID = UploadFlightRecorder.traceID(forRecordingID: item.id) ?? UploadFlightRecorder.makeTraceID()
            UploadFlightRecorder.record(
                side: .Mac,
                stage: item.hasAudio ? "macInventoryReportsAudioAvailable" : "macInventoryReportsAudioMissing",
                traceID: traceID,
                recordingID: item.id,
                eventResult: "success",
                fileExists: item.hasAudio,
                fileSize: audioSize,
                resolvedRelativePathToken: item.audioRelativePath,
                macReceiveState: item.receiveStatus,
                audioRelativePathSet: item.audioRelativePath != nil
            )
            if item.hasAudio, recomputedChecksum != nil, checksumResult?.event != .hit {
                UploadFlightRecorder.record(
                    side: .Mac,
                    stage: "macInventoryChecksumRecomputed",
                    traceID: traceID,
                    recordingID: item.id,
                    eventResult: "success",
                    reasonCode: storedChecksum?.isEmpty == false ? "checksum_refreshed" : "checksum_missing",
                    fileExists: true,
                    fileSize: audioSize,
                    resolvedRelativePathToken: item.audioRelativePath,
                    macReceiveState: item.receiveStatus,
                    audioRelativePathSet: item.audioRelativePath != nil
                )
            }
            recordings.append(
                LocalNetworkSyncRecordingEntry(
                    recordingID: item.id,
                    metadataHash: metadataHash,
                    audioAvailable: item.hasAudio,
                    audioChecksum: audioChecksum,
                    audioSize: audioSize,
                    uploadLedgerState: nil,
                    receiveStatus: item.receiveStatus,
                    processingStatus: item.hasAudio ? "notStarted" : "awaitingAudio",
                    updatedAt: item.deletedAt ?? item.receivedAt,
                    deleted: item.isDeleted,
                    title: item.title,
                    createdAt: item.receivedAt,
                    tombstone: item.isDeleted,
                    audioAvailability: item.hasAudio ? .local : .missing,
                    uploadStatus: nil,
                    transcriptionStatus: item.transcriptionStatus,
                    noteStatus: item.noteStatus,
                    sourceDeviceID: item.sourceDeviceID,
                    artifactRefs: nil,
                    audioLogicalPathToken: item.audioRelativePath
                )
            )
        }
        mergeCanonicalRecordingExistenceRecords(input.existenceRecords, into: &recordings, syncRunID: shadowSyncRunID)
        let folders = manifest.folders.map { folder in
            LocalNetworkSyncFolderEntry(
                folderID: folder.folderID,
                parentID: folder.parentFolderID,
                path: folder.path.displaySummary,
                name: folder.name,
                colorToken: folder.colorToken?.rawValue,
                updatedAt: folder.updatedAt,
                revisionHash: folderRevisionHashesByID[folder.folderID, default: ""],
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
                revisionHash: studyItemRevisionHashesByID[item.itemID, default: ""],
                deleted: item.isTrashed,
                path: item.filing.displaySummary,
                conflictStatus: item.syncConflictStatus
            )
        }
        let device = LocalNetworkSyncDeviceSection(
            deviceID: localSyncDeviceID,
            deviceName: MacSystemInfoProvider.macName,
            platform: .Mac,
            generatedAt: generatedAt,
            lastKnownPeerRevision: syncStateStore.state.lastRemoteManifestHash,
            appSchemaVersion: LocalNetworkSyncInventory.appSchemaVersion
        )
        if policy.buildsCanonicalFacts {
            emitConnectionDiagnostic(
                phase: "macInventoryCanonicalBuildStarted",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: shadowSyncRunID,
                errorMessage: "mode=\(policy.mode.rawValue),requestID=\(String(requestContext.requestID.prefix(12)))"
            )
            let snapshot = await makeMacInventoryCanonicalSnapshotOffMain(
                input: MacInventoryCanonicalBuildInput(
                    manifest: manifest,
                    inboxItems: inboxItems,
                    recordings: recordings,
                    artifacts: artifacts,
                    nodeID: localSyncDeviceID,
                    generatedAt: generatedAt
                )
            )
            requestContext.storeCanonicalSnapshot(snapshot)
            let fileRuntime = await Self.makeMacFileKernelRuntime(
                rootToken: CanonicalRootToken("mac-library-root"),
                adapter: MacCanonicalFileRuntimeAdapter(
                    entries: Self.fileSnapshotEntries(from: artifacts)
                )
            )
            if let fileSnapshot = fileRuntime.snapshot,
               let fileManifest = fileRuntime.manifest {
                requestContext.storeFileRuntime(snapshot: fileSnapshot, manifest: fileManifest)
                recordFileKernelRuntimeDiagnostics(
                    snapshot: fileSnapshot,
                    manifest: fileManifest,
                    buildCount: requestContext.fileRuntimeBuildCount,
                    syncRunID: shadowSyncRunID
                )
            }
            emitConnectionDiagnostic(
                phase: "macInventoryCanonicalBuildOffMain",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: shadowSyncRunID,
                errorMessage: "offMain=\(snapshot.builtOffMain),durationMs=\(snapshot.buildDurationMs),mainActorCanonicalBuildAttemptCount=\(snapshot.mainActorBuildAttemptCount)"
            )
            emitConnectionDiagnostic(
                phase: "macInventoryMainActorCanonicalBuildAttempt",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: shadowSyncRunID,
                errorMessage: "count=\(snapshot.mainActorBuildAttemptCount)"
            )
            emitConnectionDiagnostic(
                phase: "macInventoryCanonicalBuildCompleted",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: shadowSyncRunID,
                errorMessage: [
                    "mode=\(policy.mode.rawValue)",
                    "durationMs=\(snapshot.buildDurationMs)",
                    "canonicalObjectCount=\(snapshot.canonicalObjectCount)",
                    "canonicalArtifactCount=\(snapshot.canonicalArtifactCount)",
                    "recordingObjects=\(snapshot.recordingObjectCount)",
                    "libraryObjects=\(snapshot.libraryObjectCount)",
                    "tombstones=\(snapshot.tombstoneObjectCount)",
                    "unsupported=\(snapshot.unsupportedObjectCount)"
                ].joined(separator: ",")
            )
            recordCanonicalInventoryCoverage(snapshot.coverage, syncRunID: shadowSyncRunID)
        } else {
            requestContext.markCanonicalSkipped()
            switch policy.skipReason {
            case "oldKernel":
                emitConnectionDiagnostic(
                    phase: "macInventoryCanonicalBuildSkippedBecauseOldKernel",
                    listenerState: "ready",
                    activePort: activePort,
                    syncRunID: shadowSyncRunID,
                    errorMessage: "mode=\(policy.mode.rawValue),canonicalBuildSkippedCount=\(requestContext.canonicalBuildSkippedCount)"
                )
            case "blocked":
                emitConnectionDiagnostic(
                    phase: "macInventoryCanonicalBuildSkippedBecauseBlocked",
                    listenerState: "ready",
                    activePort: activePort,
                    syncRunID: shadowSyncRunID,
                    errorMessage: "mode=\(policy.mode.rawValue),canonicalBuildSkippedCount=\(requestContext.canonicalBuildSkippedCount)"
                )
            default:
                break
            }
            emitConnectionDiagnostic(
                phase: "macInventoryMainActorCanonicalBuildAttempt",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: shadowSyncRunID,
                errorMessage: "count=0"
            )
        }

        let seamSnapshot = policy.runsAnySeam ? requestContext.sharedCanonicalSnapshotForSeams() : requestContext.canonicalSnapshot
        if seamSnapshot != nil, policy.runsAnySeam {
            emitConnectionDiagnostic(
                phase: "macInventoryCanonicalBuildReused",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: shadowSyncRunID,
                errorMessage: "requestID=\(String(requestContext.requestID.prefix(12))),canonicalBuildReusedCount=\(requestContext.canonicalBuildReusedCount)"
            )
            emitConnectionDiagnostic(
                phase: "macInventoryCanonicalDuplicateBuildPrevented",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: shadowSyncRunID,
                errorMessage: "requestID=\(String(requestContext.requestID.prefix(12))),duplicateCanonicalBuildPreventedCount=\(requestContext.duplicateCanonicalBuildPreventedCount)"
            )
            emitConnectionDiagnostic(
                phase: "macInventorySeamUsedSharedSnapshot",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: shadowSyncRunID,
                errorMessage: "mode=\(policy.mode.rawValue),snapshotReused=true"
            )
        }
        let canonicalSnapshot = seamSnapshot ?? requestContext.canonicalSnapshot

        let inventory = LocalNetworkSyncInventory.make(
            device: device,
            recordings: recordings,
            folders: folders,
            studyItems: studyItems,
            artifacts: artifacts,
            studyManifest: manifest,
            canonicalManifest: canonicalSnapshot?.manifest
        )
        let safeTrigger = shadowTrigger ?? "sync-inventory"
        if policy.runsShadowSeams {
            recordCanonicalShadowMigrationIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID,
                generatedAt: generatedAt
            )
        }
        if policy.runsNoCommitSeams {
            recordCanonicalV8CutoverNoCommitSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
            recordCanonicalGeneratedArtifactNoCommitSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
            recordCanonicalLibraryMetadataNoCommitSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
        }
        if policy.runsAudioUploadSeams {
            recordCanonicalAudioUploadCutoverPreparationSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
        }
        if policy.runsNonAudioApplySeams {
            recordCanonicalV86GuardedCommitSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
            recordCanonicalGeneratedArtifactCutoverSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
            recordCanonicalGeneratedArtifactGuardedCommitSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
            recordCanonicalTombstoneConflictGuardedSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
            recordCanonicalLibraryMetadataCutoverSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
        }
        if policy.runsReadSeams {
            recordCanonicalGeneratedArtifactReadSideSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
            recordCanonicalLibraryMetadataReadSideSeamIfEnabled(
                localInventory: inventory,
                trigger: safeTrigger,
                syncRunID: shadowSyncRunID
            )
        }
        if policy.runsShadowSeams, let canonicalManifest = canonicalSnapshot?.manifest, shadowTrigger != nil || shadowSyncRunID != nil {
            writeCanonicalShadowReport(
                generatedAt: generatedAt,
                trigger: shadowTrigger,
                syncRunID: shadowSyncRunID,
                canonicalManifest: canonicalManifest,
                recordingEntries: recordings,
                studyItems: manifest.items,
                artifacts: artifacts
            )
        }
        let durationMs = max(0, Date().timeIntervalSince(startedAt) * 1_000)
        let endedAt = Date()
        let runtimeSnapshot = CanonicalInventoryRuntimeSnapshot(
            syncRunID: shadowSyncRunID ?? "unspecified",
            nodeRole: .mac,
            buildStartedAt: startedAt,
            buildEndedAt: endedAt,
            sourceKind: sourceKind,
            objectCounts: CanonicalInventoryObjectCounts(
                recordingMetadataCount: recordings.count,
                libraryFolderCount: folders.count,
                libraryItemCount: studyItems.count,
                artifactCount: artifacts.count,
                audioDescriptorCount: recordings.filter { $0.audioAvailable || $0.audioLogicalPathToken != nil }.count
            ),
            diagnostics: runtimeDiagnostics,
            mainActorBlocked: runtimeDiagnostics.mainActorHashBlockedCount > 0
                || runtimeDiagnostics.mainActorScanBlockedCount > 0
                || runtimeDiagnostics.mainActorMetadataLoadAttemptCount > 0
                || runtimeDiagnostics.mainActorJobsLoadAttemptCount > 0
                || runtimeDiagnostics.mainActorManifestBuildAttemptCount > 0,
            reusedWithinTick: requestContext.canonicalBuildReusedCount > 0,
            redacted: true
        )
        if policy.runsDecisionSeams, let canonicalSnapshot {
            recordCanonicalSyncRuntimeInventoryEvaluation(
                runtimeSnapshot: runtimeSnapshot,
                localManifest: canonicalSnapshot.manifest,
                coverage: canonicalSnapshot.coverage,
                syncRunID: shadowSyncRunID
            )
        }
        recordRuntimeSnapshotDiagnostics(runtimeSnapshot, syncRunID: shadowSyncRunID)
        emitConnectionDiagnostic(
            phase: "macInventoryMainActorHashAttempt",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: shadowSyncRunID,
            errorMessage: "count=\(runtimeDiagnostics.mainActorHashAttemptCount)"
        )
        emitConnectionDiagnostic(
            phase: "macInventoryMainActorScanAttempt",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: shadowSyncRunID,
            errorMessage: "count=\(runtimeDiagnostics.mainActorScanAttemptCount)"
        )
        emitConnectionDiagnostic(
            phase: "macInventoryRouteCompleted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: shadowSyncRunID,
            errorMessage: [
                "routeDurationMs=\(Int(durationMs.rounded()))",
                "manifestBuildDurationMs=\(runtimeDiagnostics.manifestBuildDurationMs)",
                "canonicalBuildDurationMs=\(canonicalSnapshot?.buildDurationMs ?? 0)",
                "canonicalObjectCount=\(canonicalSnapshot?.canonicalObjectCount ?? 0)",
                "canonicalArtifactCount=\(canonicalSnapshot?.canonicalArtifactCount ?? 0)",
                "canonicalBuildSkippedCount=\(requestContext.canonicalBuildSkippedCount)",
                "canonicalBuildReusedCount=\(requestContext.canonicalBuildReusedCount)",
                "duplicateCanonicalBuildPreventedCount=\(requestContext.duplicateCanonicalBuildPreventedCount)",
                "mainActorManifestBuildAttemptCount=\(runtimeDiagnostics.mainActorManifestBuildAttemptCount)",
                "mainActorCanonicalBuildAttemptCount=\(canonicalSnapshot?.mainActorBuildAttemptCount ?? 0)",
                "mainActorHashAttemptCount=\(runtimeDiagnostics.mainActorHashAttemptCount)",
                "mainActorScanAttemptCount=\(runtimeDiagnostics.mainActorScanAttemptCount)"
            ].joined(separator: ",")
        )
        emitConnectionDiagnostic(
            phase: "inventoryBuildCompleted",
            listenerState: "ready",
            activePort: activePort,
            errorMessage: "recordings=\(recordings.count),durationMs=\(Int(durationMs.rounded()))"
        )
        emitConnectionDiagnostic(
            phase: "inventoryBuildDurationMs",
            listenerState: "ready",
            activePort: activePort,
            errorMessage: "\(Int(durationMs.rounded()))"
        )
        return inventory
    }

    private func recordCanonicalV86GuardedCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalV8CutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let canonicalTrigger = canonicalSyncPlanTrigger(from: safeTrigger)
        let context = CanonicalRecordingMetadataGuardedCommitContext(
            syncRunID: syncRunID,
            trigger: canonicalTrigger,
            nodeRole: .mac,
            localManifest: localInventory.canonicalManifest,
            peerManifest: nil,
            applyPlan: nil,
            legacyActionSnapshot: .empty,
            evidence: configuration.evidence,
            unresolvedConflictCount: 0,
            canaryPolicy: CanonicalRecordingMetadataCanaryPolicy(
                maxObjectsPerSyncRun: configuration.policy.effectiveCanaryMaxObjectsPerSyncRun,
                runtimeSwitchEnabled: false,
                allowsV87CanaryN1InternalExecution: configuration.policy.allowsV87CanaryN1InternalExecution,
                recordingMetadataCanaryStagePolicy: configuration.policy.recordingMetadataCanaryStagePolicy
            ),
            legacyFallbackAvailable: configuration.evidence.legacyFallbackAvailable,
            cutoverToken: configuration.cutoverToken,
            candidates: [],
            localSnapshotAvailable: localInventory.canonicalManifest != nil,
            peerSnapshotAvailable: false
        )
        let result = CanonicalRecordingMetadataGuardedCommitSeam().evaluate(
            configuration: configuration,
            context: context
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: event.diagnosticsSummary
            )
        }
    }

    private func recordCanonicalGeneratedArtifactCutoverSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalGeneratedArtifactCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let canonicalTrigger = canonicalSyncPlanTrigger(from: safeTrigger)
        let mode: CanonicalCutoverMode = configuration.effectiveMode == .canaryCommit ? .canary : .guardedExecuteCommit
        let evaluatedGate = CanonicalGeneratedArtifactCutoverRunner().evaluateGate(
            mode: mode,
            policy: configuration.policy.canaryPolicy,
            token: configuration.cutoverToken,
            evidence: configuration.evidence,
            candidates: [],
            peerNode: nil,
            trigger: canonicalTrigger
        )
        let gate = CanonicalGeneratedArtifactCutoverGate(
            domain: .generatedArtifacts,
            mode: mode,
            failures: evaluatedGate.failures + [.peerUnknown],
            legacyFallbackAvailable: configuration.evidence.legacyFallbackAvailable,
            reason: "generatedArtifactMacInventoryPeerSnapshotUnavailable"
        )
        var diagnostics = [
            CanonicalGeneratedArtifactCutoverDiagnostic(
                kind: .canonicalGeneratedArtifactCutoverGateEvaluated,
                syncRunID: syncRunID,
                trigger: canonicalTrigger,
                nodeRole: .mac,
                result: "blocked",
                reason: gate.reason
            ),
            CanonicalGeneratedArtifactCutoverDiagnostic(
                kind: .canonicalGeneratedArtifactCutoverGateBlocked,
                syncRunID: syncRunID,
                trigger: canonicalTrigger,
                nodeRole: .mac,
                result: "blocked",
                reason: gate.failures.map(\.rawValue).joined(separator: ",")
            ),
            CanonicalGeneratedArtifactCutoverDiagnostic(
                kind: .canonicalGeneratedArtifactLegacyFallbackPreserved,
                syncRunID: syncRunID,
                trigger: canonicalTrigger,
                nodeRole: .mac,
                result: "legacyFallbackPreserved",
                reason: "peerSnapshotUnavailable"
            )
        ]
        let canaryPolicy = configuration.policy.canaryPolicy
        let requestedStage = canaryPolicy.stagePolicy.requestedStage
        let expandedStageCanaryEnabled = requestedStage.isExecutable && requestedStage != .n1
        if configuration.effectiveMode == .canaryCommit, expandedStageCanaryEnabled {
            let stageGate = CanonicalGeneratedArtifactCanaryStageGate(
                policy: canaryPolicy.stagePolicy,
                domain: .generatedArtifacts,
                token: configuration.cutoverToken,
                cutoverEvidence: configuration.evidence
            )
            diagnostics.append(contentsOf: [
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactCanaryStageEvaluated,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: requestedStage.rawValue,
                    reason: "candidateCount=0;peerSnapshotAvailable=false;evidence=\(stageGate.evidenceReport.diagnosticsSummary)"
                ),
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactCanaryStageBlocked,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: "peerSnapshotUnavailable;legacyFallbackPreserved"
                ),
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactN1MacPeerSnapshotUnavailable,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: "peerSnapshotUnavailable"
                ),
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactCanaryStageObservationRecorded,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: requestedStage.rawValue,
                    reason: "noCommit;noDuplicateSuppression;peerSnapshotUnavailable;runtimeSwitch=false;domain=generatedArtifacts"
                )
            ])
        }
        if configuration.effectiveMode == .canaryCommit,
           !expandedStageCanaryEnabled,
           canaryPolicy.canaryMaxObjectsPerSyncRun == 1 {
            let canaryConfiguration = CanonicalGeneratedArtifactCanaryConfiguration(appSeamConfiguration: configuration)
            diagnostics.append(contentsOf: [
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactN1CanaryConfigured,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: [
                        "mode=\(canaryConfiguration.mode.rawValue)",
                        "domain=\(canaryConfiguration.domain.rawValue)",
                        "budget=\(canaryConfiguration.canaryMaxObjectsPerSyncRun)",
                        "peerSnapshotAvailable=false"
                    ].joined(separator: ";")
                ),
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactN1CandidateSelectionStarted,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: "peerSnapshotUnavailable"
                ),
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactN1NoEligibleCandidate,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "noEligibleCandidate",
                    reason: "peerSnapshotUnavailable"
                ),
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactN1MacPeerSnapshotUnavailable,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: "peerSnapshotUnavailable"
                ),
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactN1LegacyFallbackUsed,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "legacyFallbackPreserved",
                    reason: "peerSnapshotUnavailable"
                ),
                CanonicalGeneratedArtifactCutoverDiagnostic(
                    kind: .canonicalGeneratedArtifactN1ObservationRecorded,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: CanonicalGeneratedArtifactCanaryObservationStatus.noEligibleCandidate.rawValue,
                    reason: "peerSnapshotUnavailable"
                )
            ])
        }
        for event in diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: canonicalGeneratedArtifactCutoverDiagnosticSummary(event)
            )
        }
        _ = localInventory
        _ = canonicalGeneratedArtifactCutoverExecutor
    }

    private func recordCanonicalGeneratedArtifactNoCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalGeneratedArtifactCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              configuration.effectiveMode == .guardedExecuteNoCommit else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let canonicalTrigger = canonicalSyncPlanTrigger(from: safeTrigger)
        emitConnectionDiagnostic(
            phase: CanonicalGeneratedArtifactCutoverDiagnosticKind.canonicalGeneratedArtifactNoCommitStarted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "trigger=\(canonicalTrigger.rawValue),candidateCount=0,peerSnapshotAvailable=false,productionCommitSuppressed=true"
        )
        emitConnectionDiagnostic(
            phase: CanonicalGeneratedArtifactCutoverDiagnosticKind.canonicalGeneratedArtifactNoCommitCompleted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "trigger=\(canonicalTrigger.rawValue),candidateCount=0,stagedCount=0,stagingOnly=true,legacyDuplicateSuppressed=false"
        )
        _ = localInventory
    }

    private func recordCanonicalGeneratedArtifactReadSideSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalGeneratedArtifactReadSideConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let result = MacGeneratedArtifactReadSideSeam(configuration: configuration).evaluate(
            localInventory: localInventory,
            trigger: canonicalSyncPlanTrigger(from: safeTrigger),
            syncRunID: syncRunID
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: event.diagnosticsSummary
            )
        }
    }

    private func recordCanonicalGeneratedArtifactGuardedCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalGeneratedArtifactCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let canonicalTrigger = canonicalSyncPlanTrigger(from: safeTrigger)
        let context = CanonicalGeneratedArtifactGuardedCommitContext(
            syncRunID: syncRunID,
            trigger: canonicalTrigger,
            nodeRole: .mac,
            localManifest: localInventory.canonicalManifest,
            peerManifest: nil,
            legacyActionSnapshot: .empty,
            matrix: .v822GeneratedArtifactsActivePilot(libraryMetadataObservationCompleteOrRetirementCandidateReady: true),
            evidence: configuration.evidence,
            canaryPolicy: configuration.policy.canaryPolicy,
            cutoverToken: configuration.cutoverToken,
            candidates: [],
            localSnapshotAvailable: localInventory.canonicalManifest != nil,
            peerSnapshotAvailable: false,
            unresolvedConflictCount: 0
        )
        let result = CanonicalGeneratedArtifactGuardedCommitSeam().evaluate(
            configuration: configuration,
            context: context
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: event.diagnosticsSummary
            )
        }
    }

    private func recordCanonicalTombstoneConflictGuardedSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalTombstoneConflictCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let canonicalTrigger = canonicalSyncPlanTrigger(from: safeTrigger)
        let context = CanonicalTombstoneConflictGuardedContext(
            syncRunID: syncRunID,
            trigger: canonicalTrigger,
            nodeRole: .mac,
            localManifest: localInventory.canonicalManifest,
            peerManifest: nil,
            candidates: [],
            legacyActionSnapshot: .empty,
            matrix: .v827TombstoneConflictActivePilot(
                libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
                generatedArtifactsTemplateCompleteOrObservationReady: true
            ),
            evidence: configuration.evidence,
            canaryPolicy: configuration.policy.canaryPolicy,
            cutoverToken: configuration.cutoverToken,
            localSnapshotAvailable: localInventory.canonicalManifest != nil,
            peerSnapshotAvailable: false
        )
        let result = CanonicalTombstoneConflictGuardedSeam().evaluate(
            configuration: configuration,
            context: context
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: event.diagnosticsSummary
            )
        }
    }

    private func recordCanonicalLibraryMetadataCutoverSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        if canonicalLibraryMetadataDebugPilotConfiguration.mode.isConfigured {
            recordCanonicalLibraryMetadataLandingPilotIfConfigured(
                localInventory: localInventory,
                trigger: trigger,
                syncRunID: syncRunID
            )
            return
        }

        let configuration = canonicalLibraryMetadataCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              (configuration.effectiveMode == .guardedExecuteCommit || configuration.effectiveMode == .canaryCommit) else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let canonicalTrigger = canonicalSyncPlanTrigger(from: safeTrigger)
        let localManifest = localInventory.canonicalManifest
        let canaryConfiguration = CanonicalLibraryMetadataCanaryConfiguration(appSeamConfiguration: configuration)
        let requestedStage = configuration.policy.canaryPolicy.stagePolicy.requestedStage
        let expandedStageCanaryEnabled = requestedStage.isExecutable && requestedStage != .n1
        if expandedStageCanaryEnabled, configuration.effectiveMode == .canaryCommit {
            let evidenceReport = CanonicalLibraryMetadataStageEvidenceReport.from(
                evidence: configuration.evidence,
                policy: configuration.policy.canaryPolicy.stagePolicy
            )
            let diagnostics = [
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataCanaryStageEvaluated,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: requestedStage.rawValue,
                    reason: "candidateCount=0;peerSnapshotAvailable=false;evidence=\(evidenceReport.diagnosticsSummary)"
                ),
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataCanaryStageBlocked,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: "peerSnapshotUnavailable;legacyFallbackPreserved"
                ),
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataLegacyFallbackUsed,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "legacyFallbackPreserved",
                    reason: "peerSnapshotUnavailable"
                ),
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataCanaryStageObservationRecorded,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: requestedStage.rawValue,
                    reason: "noCommit;noDuplicateSuppression;peerSnapshotUnavailable;runtimeSwitch=false;domain=libraryMetadata"
                )
            ]
            for event in diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
                emitConnectionDiagnostic(
                    phase: event.kind.rawValue,
                    listenerState: "ready",
                    activePort: activePort,
                    syncRunID: syncRunID,
                    errorMessage: canonicalLibraryMetadataCutoverDiagnosticSummary(event)
                )
            }
            return
        }
        if canaryConfiguration.mode == .n1 {
            let diagnostics = [
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataN1CanaryConfigured,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: "mode=n1;domain=libraryMetadata;budget=\(canaryConfiguration.canaryMaxObjectsPerSyncRun);peerSnapshotAvailable=false"
                ),
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataN1MacPeerSnapshotUnavailable,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: "macInventoryPeerSnapshotUnavailable"
                ),
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataN1LegacyFallbackUsed,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "legacyFallbackPreserved",
                    reason: "peerSnapshotUnavailable"
                ),
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalLibraryMetadataN1ObservationRecorded,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: "noCommit;noDuplicateSuppression;peerSnapshotUnavailable"
                )
            ]
            for event in diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
                emitConnectionDiagnostic(
                    phase: event.kind.rawValue,
                    listenerState: "ready",
                    activePort: activePort,
                    syncRunID: syncRunID,
                    errorMessage: canonicalLibraryMetadataCutoverDiagnosticSummary(event)
                )
            }
            return
        }
        let context = CanonicalLibraryMetadataGuardedCommitContext(
            syncRunID: syncRunID,
            trigger: canonicalTrigger,
            nodeRole: .mac,
            localManifest: localManifest,
            peerManifest: nil,
            libraryPlan: nil,
            legacyActionSnapshot: .empty,
            evidence: configuration.evidence,
            canaryPolicy: configuration.policy.canaryPolicy,
            cutoverToken: configuration.cutoverToken,
            candidates: [],
            localSnapshotAvailable: localManifest != nil,
            peerSnapshotAvailable: false,
            unresolvedConflictCount: 0
        )
        let result = CanonicalLibraryMetadataGuardedCommitSeam().evaluate(
            configuration: configuration,
            context: context
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: canonicalLibraryMetadataGuardedCommitDiagnosticSummary(event)
            )
        }
    }

    private func recordCanonicalLibraryMetadataLandingPilotIfConfigured(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalLibraryMetadataDebugPilotConfiguration
        guard configuration.mode.isConfigured, configuration.recordDiagnostics else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let canonicalTrigger = canonicalSyncPlanTrigger(from: safeTrigger)
        let freeze = CanonicalMigrationLandingFreeze().evaluate(
            matrix: .defaultV813(),
            releaseDefaultEnabled: configuration.policy.releaseDefaultEnabled,
            runtimeSwitchEnabled: configuration.policy.runtimeSwitchEnabled
        )
        var diagnostics = [
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataLandingConfigEvaluated,
                syncRunID: syncRunID,
                trigger: canonicalTrigger,
                nodeRole: .mac,
                result: configuration.mode.rawValue,
                reason: "macInventoryPeerSnapshotUnavailable;\(freeze.diagnosticsSummary)"
            )
        ]
        if !freeze.allowed {
            diagnostics.append(
                CanonicalLibraryMetadataCutoverDiagnostic(
                    kind: .canonicalMigrationLandingFreezeViolation,
                    syncRunID: syncRunID,
                    trigger: canonicalTrigger,
                    nodeRole: .mac,
                    result: "blocked",
                    reason: freeze.violations.map(\.rawValue).joined(separator: ",")
                )
            )
        }
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataLandingBlocked,
                syncRunID: syncRunID,
                trigger: canonicalTrigger,
                nodeRole: .mac,
                result: "blocked",
                reason: "peerSnapshotUnavailable;commitSuppressed=true;legacyFallbackPreserved"
            )
        )
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataLandingLegacyFallbackUsed,
                syncRunID: syncRunID,
                trigger: canonicalTrigger,
                nodeRole: .mac,
                result: "legacyFallbackPreserved",
                reason: "macInventoryPeerSnapshotUnavailable"
            )
        )
        diagnostics.append(
            CanonicalLibraryMetadataCutoverDiagnostic(
                kind: .canonicalLibraryMetadataLandingReportBuilt,
                syncRunID: syncRunID,
                trigger: canonicalTrigger,
                nodeRole: .mac,
                result: "blocked",
                reason: "mode=\(configuration.mode.rawValue);rootMode=\(configuration.rootMode.rawValue);candidateSelected=false;commitAttempted=false;fallback=true;runtimeSwitch=false;uiReadPathSwitched=false"
            )
        )
        for event in diagnostics.prefix(configuration.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: canonicalLibraryMetadataCutoverDiagnosticSummary(event)
            )
        }
        _ = localInventory
    }

    private func recordCanonicalLibraryMetadataNoCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalLibraryMetadataCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              configuration.effectiveMode == .guardedExecuteNoCommit else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let canonicalTrigger = canonicalSyncPlanTrigger(from: safeTrigger)
        emitConnectionDiagnostic(
            phase: CanonicalLibraryMetadataCutoverDiagnosticKind.canonicalLibraryMetadataNoCommitStarted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "trigger=\(canonicalTrigger.rawValue),candidateCount=0,peerSnapshotAvailable=false,productionCommitSuppressed=true"
        )
        emitConnectionDiagnostic(
            phase: CanonicalLibraryMetadataCutoverDiagnosticKind.canonicalLibraryMetadataNoCommitCompleted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "trigger=\(canonicalTrigger.rawValue),candidateCount=0,stagedCount=0,stagingOnly=true,legacyDuplicateSuppressed=false"
        )
        _ = localInventory
    }

    private func recordCanonicalAudioUploadCutoverPreparationSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalAudioUploadCutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let audioTrigger = CanonicalAudioUploadTriggerSource.from(canonicalSyncPlanTrigger(from: safeTrigger))
        let candidates: [CanonicalAudioUploadCutoverCandidate]
        if let localManifest = localInventory.canonicalManifest {
            candidates = CanonicalAudioUploadCutoverCandidate.candidates(
                localManifest: localManifest,
                peerManifest: nil,
                trigger: audioTrigger
            )
        } else {
            candidates = []
        }
        var evidence = configuration.evidence
        if evidence.evidenceReport == nil {
            evidence.evidenceReport = CanonicalAudioUploadEvidenceReport(candidates: candidates)
        }

        let result: CanonicalAudioUploadCutoverResult
        if configuration.effectiveMode == .guardedExecuteNoCommit {
            result = CanonicalAudioUploadNoCommitRunner().run(
                mode: configuration.cutoverMode,
                policy: configuration.policy.canaryPolicy,
                token: configuration.cutoverToken,
                evidence: evidence,
                candidates: candidates.map { CanonicalAudioUploadNoCommitCandidate(cutoverCandidate: $0) },
                trigger: audioTrigger,
                nodeRole: .mac,
                syncRunID: syncRunID,
                executor: MacAudioUploadNoCommitExecutor()
            )
        } else {
            let gate = CanonicalAudioUploadCutoverRunner().evaluateGate(
                mode: configuration.cutoverMode,
                policy: configuration.policy.canaryPolicy,
                token: configuration.cutoverToken,
                evidence: evidence,
                candidates: candidates,
                trigger: audioTrigger
            )
            result = CanonicalAudioUploadCutoverResult(
                gate: gate,
                candidates: candidates,
                diagnostics: [
                    CanonicalAudioUploadDiagnostic(
                        kind: .canonicalAudioUploadCutoverGateEvaluated,
                        syncRunID: syncRunID,
                        trigger: audioTrigger,
                        nodeRole: .mac,
                        result: "blocked",
                        reason: "macInventoryPeerSnapshotUnavailable,\(gate.reason)"
                    ),
                    CanonicalAudioUploadDiagnostic(
                        kind: .canonicalAudioUploadCutoverGateBlocked,
                        syncRunID: syncRunID,
                        trigger: audioTrigger,
                        nodeRole: .mac,
                        result: "blocked",
                        reason: gate.failures.map(\.rawValue).joined(separator: ",")
                    ),
                    CanonicalAudioUploadDiagnostic(
                        kind: .canonicalAudioUploadLegacyFallbackPreserved,
                        syncRunID: syncRunID,
                        trigger: audioTrigger,
                        nodeRole: .mac,
                        result: "true",
                        reason: "v812PreparationOnly"
                    )
                ]
            )
        }

        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: canonicalAudioUploadCutoverDiagnosticSummary(event)
            )
        }
    }

    private func canonicalAudioUploadCutoverDiagnosticSummary(
        _ event: CanonicalAudioUploadDiagnostic
    ) -> String {
        event.diagnosticsSummary
    }

    private func canonicalGeneratedArtifactCutoverDiagnosticSummary(
        _ event: CanonicalGeneratedArtifactCutoverDiagnostic
    ) -> String {
        [
            "trigger=\(event.trigger.rawValue)",
            "nodeRole=\(event.nodeRole.rawValue)",
            "domain=\(event.domain.rawValue)",
            event.objectID.map { "objectID=\($0)" },
            event.artifactID.map { "artifactID=\($0)" },
            event.artifactKind.map { "artifactKind=\($0.rawValue)" },
            event.action.map { "action=\($0)" },
            event.result.map { "result=\($0)" },
            event.reason.map { "reason=\($0)" },
            event.hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    private func canonicalLibraryMetadataCutoverDiagnosticSummary(
        _ event: CanonicalLibraryMetadataCutoverDiagnostic
    ) -> String {
        [
            "trigger=\(event.trigger.rawValue)",
            "nodeRole=\(event.nodeRole.rawValue)",
            "domain=\(event.domain?.rawValue ?? "none")",
            event.objectID.map { "objectID=\($0)" },
            event.objectKind.map { "objectKind=\($0.rawValue)" },
            event.action.map { "action=\($0)" },
            event.result.map { "result=\($0)" },
            event.reason.map { "reason=\($0)" },
            event.hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    private func recordCanonicalLibraryMetadataReadSideSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalLibraryMetadataReadSideCutoverConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let result = MacLibraryMetadataReadSideSeam(configuration: configuration).evaluate(
            legacyManifest: localInventory.studyManifest,
            canonicalManifest: localInventory.canonicalManifest,
            trigger: canonicalSyncPlanTrigger(from: safeTrigger),
            syncRunID: syncRunID
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: canonicalLibraryMetadataCutoverDiagnosticSummary(event)
            )
        }
    }

    private func canonicalLibraryMetadataGuardedCommitDiagnosticSummary(
        _ event: CanonicalLibraryMetadataGuardedCommitDiagnostic
    ) -> String {
        [
            "trigger=\(event.trigger.rawValue)",
            "nodeRole=\(event.nodeRole.rawValue)",
            "mode=\(event.mode.rawValue)",
            event.objectID.map { "objectID=\($0)" },
            event.objectKind.map { "objectKind=\($0.rawValue)" },
            "candidateCount=\(event.candidateCount)",
            "gateFailureCount=\(event.gateFailureCount)",
            "canaryBudget=\(event.canaryBudget)",
            "commitAttemptedCount=\(event.commitAttemptedCount)",
            "duplicateSuppressionCandidateCount=\(event.duplicateSuppressionCandidateCount)",
            event.result.map { "result=\($0)" },
            event.reason.map { "reason=\($0)" },
            event.hashPrefix.map { "hashPrefix=\($0)" }
        ].compactMap { $0 }.joined(separator: ",")
    }

    private func recordCanonicalV8CutoverNoCommitSeamIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?
    ) {
        let configuration = canonicalV8CutoverAppSeamConfiguration
        guard configuration.isEnabled,
              configuration.policy.recordDiagnostics,
              configuration.effectiveMode == .guardedExecuteNoCommit else {
            return
        }
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "sync-inventory"
        let canonicalTrigger = canonicalSyncPlanTrigger(from: safeTrigger)
        let result = CanonicalRecordingMetadataNoCommitRunner().run(
            configuration: configuration,
            candidates: [],
            trigger: canonicalTrigger,
            nodeRole: .mac,
            syncRunID: syncRunID,
            localSnapshotAvailable: localInventory.canonicalManifest != nil,
            peerSnapshotAvailable: false,
            executor: MacRecordingMetadataNoCommitExecutor()
        )
        for event in result.diagnostics.prefix(configuration.policy.maxDiagnosticsEvents) {
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: event.diagnosticsSummary
            )
        }
    }

    private func recordCanonicalShadowMigrationIfEnabled(
        localInventory: LocalNetworkSyncInventory,
        trigger: String,
        syncRunID: String?,
        generatedAt: Date
    ) {
        let shouldRecordGenericShadow = canonicalShadowMigrationConfiguration.isEnabled
            && canonicalShadowMigrationConfiguration.policy.recordDiagnostics
        let shouldRecordSingleDomainShadow = canonicalSingleDomainShadowConfiguration.isEnabled
            && canonicalSingleDomainShadowConfiguration.policy.recordDiagnostics
        guard shouldRecordGenericShadow || shouldRecordSingleDomainShadow else {
            return
        }
        let factoryOutput = MacCanonicalShadowPortFactory(
            configuration: canonicalShadowMigrationConfiguration
        ).makeOutput(
            localInventory: localInventory,
            peerInventory: nil,
            legacyPlan: nil,
            generatedAt: generatedAt
        )
        recordCanonicalRecordingMetadataShadowIfEnabled(
            factoryOutput: factoryOutput,
            trigger: trigger,
            syncRunID: syncRunID,
            generatedAt: generatedAt
        )
        guard shouldRecordGenericShadow else {
            return
        }
        if canonicalShadowMigrationConfiguration.effectiveMode.runsExecutionShadowPreparation {
            let realDataCopyResult = makeMacRealDataShadowCopyIfEnabled(
                factoryOutput: factoryOutput,
                localInventory: localInventory,
                syncRunID: syncRunID
            )
            let readOnlyProbeResult = makeMacReadOnlyTransportProbeIfEnabled(
                factoryOutput: factoryOutput
            )
            let result = CanonicalExecutionShadowPreparationRunner().run(
                configuration: canonicalShadowMigrationConfiguration,
                trigger: .macInventory,
                nodeRole: .mac,
                domain: .inventory,
                localSnapshot: factoryOutput.localSnapshot,
                peerSnapshot: nil,
                ports: factoryOutput.portSet,
                context: CanonicalDryRunMigrationContext(dryRunID: "mac-execution-shadow-\(syncRunID ?? UUID().uuidString)"),
                syncRunID: syncRunID,
                shadowRootKind: canonicalShadowMigrationConfiguration.effectiveMode == .executionShadowWithShadowFileStore ? .shadowCopy : .temporary,
                realDataShadowCopyResult: realDataCopyResult,
                readOnlyTransportProbeResult: readOnlyProbeResult,
                generatedAt: generatedAt
            )
            let safeFactorySummary = String(factoryOutput.diagnosticsSafeSummary.prefix(240))
            let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "unknown"
            for event in result.report.events.prefix(canonicalShadowMigrationConfiguration.policy.maxDiagnosticsEvents) {
                let summary = [
                    event.diagnosticsSummary,
                    "source=\(safeTrigger)",
                    "factory=\(safeFactorySummary)"
                ].joined(separator: ",")
                emitConnectionDiagnostic(
                    phase: event.kind.rawValue,
                    listenerState: "ready",
                    activePort: activePort,
                    syncRunID: syncRunID,
                    errorMessage: summary
                )
            }
            cleanupMacExecutionShadowRootIfNeeded(
                factoryOutput: factoryOutput,
                syncRunID: syncRunID
            )
            return
        }
        let result = CanonicalShadowMigrationRunner().run(
            configuration: canonicalShadowMigrationConfiguration,
            trigger: .macInventory,
            nodeRole: .mac,
            domain: .inventory,
            localSnapshot: factoryOutput.localSnapshot,
            peerSnapshot: nil,
            ports: factoryOutput.portSet,
            context: CanonicalDryRunMigrationContext(dryRunID: "mac-shadow-\(syncRunID ?? UUID().uuidString)"),
            syncRunID: syncRunID,
            generatedAt: generatedAt
        )
        let safeFactorySummary = String(factoryOutput.diagnosticsSafeSummary.prefix(240))
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "unknown"
        for event in result.report.events.prefix(canonicalShadowMigrationConfiguration.policy.maxDiagnosticsEvents) {
            let summary = [
                event.diagnosticsSummary,
                "source=\(safeTrigger)",
                "factory=\(safeFactorySummary)"
            ].joined(separator: ",")
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: summary
            )
        }
    }

    private func canonicalSyncPlanTrigger(from trigger: String) -> CanonicalSyncPlanTrigger {
        let normalized = trigger.lowercased()
        if normalized.contains("retry") {
            return .retryDrainer
        }
        if normalized.contains("view") || normalized.contains("refresh") {
            return .viewRefresh
        }
        if normalized.contains("manual") || normalized.contains("sync-requested") {
            return .manual
        }
        if normalized.contains("activation") || normalized.contains("foreground") {
            return .appActivation
        }
        return .periodic
    }

    private func makeMacRealDataShadowCopyIfEnabled(
        factoryOutput: CanonicalShadowPortFactoryOutput,
        localInventory: LocalNetworkSyncInventory,
        syncRunID: String?
    ) -> CanonicalRealDataShadowCopyResult? {
        let copyPolicy = canonicalShadowMigrationConfiguration.policy.realDataShadowCopyPolicy
        guard copyPolicy.isEnabled,
              canonicalShadowMigrationConfiguration.effectiveMode == .executionShadowWithShadowFileStore,
              let lifecycle = factoryOutput.shadowRootLifecycle else {
            return nil
        }
        let input = MacCanonicalRealDataShadowCopyAdapter.Input(
            productionRootURL: recordingFileStore.libraryRootURL,
            shadowRootURL: lifecycle.rootURL,
            cleanupRootID: lifecycle.rootID,
            inventory: localInventory,
            studyManifest: localInventory.studyManifest,
            policy: copyPolicy
        )
        let result = MacCanonicalRealDataShadowCopyAdapter().copy(input)
        emitConnectionDiagnostic(
            phase: result.completed ? "canonicalRealDataShadowCopyCompleted" : "canonicalRealDataShadowCopyFailed",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorCode: result.failure?.rawValue,
            errorMessage: result.diagnosticsSummary
        )
        return result
    }

    private func makeMacReadOnlyTransportProbeIfEnabled(
        factoryOutput: CanonicalShadowPortFactoryOutput
    ) -> CanonicalReadOnlyTransportProbeResult? {
        let policy = canonicalShadowMigrationConfiguration.policy.readOnlyTransportProbePolicy
        guard policy.isEnabled,
              canonicalShadowMigrationConfiguration.effectiveMode == .executionShadowWithReadOnlyTransportProbe else {
            return nil
        }
        let body = Data("{}".utf8)
        let request = CanonicalReadOnlyTransportProbeRequest(
            route: .syncInventory,
            bodyByteCount: body.count,
            bodyHash: CanonicalTransportEnvelope.hash(body),
            timestampPresent: true,
            noncePresent: true,
            signaturePresent: true,
            tlsPinningPreserved: true,
            hmacPreserved: true,
            bodyHashPreserved: true,
            manifestHashPresent: factoryOutput.localSnapshot != nil,
            manifestHashUsedAsAuth: false
        )
        return CanonicalReadOnlyTransportProbe().evaluate(request: request, policy: policy)
    }

    private func cleanupMacExecutionShadowRootIfNeeded(
        factoryOutput: CanonicalShadowPortFactoryOutput,
        syncRunID: String?
    ) {
        guard let lifecycle = factoryOutput.shadowRootLifecycle else {
            return
        }
        emitConnectionDiagnostic(
            phase: "canonicalRealDataShadowCopyCleanupStarted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "rootKind=\(lifecycle.rootKind.rawValue),rootID=\(lifecycle.rootID)"
        )
        let cleanup = lifecycle.cleanup(
            policy: canonicalShadowMigrationConfiguration.policy.realDataShadowCopyPolicy.cleanupPolicy
        )
        let phase: String
        switch cleanup.status {
        case .removed:
            phase = "canonicalRealDataShadowCopyCleanupCompleted"
        case .retainedForDiagnostics, .retainedForNextLaunch:
            phase = "canonicalRealDataShadowCopyRetainedForDiagnostics"
        case .refusedProductionRoot, .failed:
            phase = "canonicalRealDataShadowCopyCleanupFailed"
        }
        emitConnectionDiagnostic(
            phase: phase,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorCode: cleanup.status == .failed || cleanup.status == .refusedProductionRoot ? cleanup.status.rawValue : nil,
            errorMessage: cleanup.diagnosticsSummary
        )
    }

    private func recordCanonicalRecordingMetadataShadowIfEnabled(
        factoryOutput: CanonicalShadowPortFactoryOutput,
        trigger: String,
        syncRunID: String?,
        generatedAt: Date
    ) {
        guard canonicalSingleDomainShadowConfiguration.isEnabled,
              canonicalSingleDomainShadowConfiguration.policy.recordDiagnostics else {
            return
        }
        let report = CanonicalRecordingMetadataExecutionShadowPlanner().run(
            configuration: canonicalSingleDomainShadowConfiguration,
            trigger: .macInventory,
            nodeRole: .mac,
            localManifest: factoryOutput.localSnapshot?.manifest,
            peerManifest: nil,
            syncPlan: nil,
            applyPlan: nil,
            legacyActions: factoryOutput.localSnapshot?.legacyActions ?? .empty,
            syncRunID: syncRunID,
            generatedAt: generatedAt
        )
        let safeFactorySummary = String(factoryOutput.diagnosticsSafeSummary.prefix(240))
        let safeTrigger = CanonicalShadowMigrationRedaction.safeText(trigger) ?? "unknown"
        for event in report.events.prefix(canonicalSingleDomainShadowConfiguration.policy.maxDiagnosticsEvents) {
            let summary = [
                event.diagnosticsSummary,
                "source=\(safeTrigger)",
                "factory=\(safeFactorySummary)"
            ].joined(separator: ",")
            emitConnectionDiagnostic(
                phase: event.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: summary
            )
        }
    }

    private func writeCanonicalShadowReport(
        generatedAt: Date,
        trigger: String?,
        syncRunID: String?,
        canonicalManifest: CanonicalManifest,
        recordingEntries: [LocalNetworkSyncRecordingEntry],
        studyItems: [StudyItemMetadata],
        artifacts: [LocalNetworkSyncArtifactEntry]
    ) {
        let startedAt = Date()
        emitConnectionDiagnostic(
            phase: "canonicalShadowBuildStarted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: trigger
        )
        let legacy = CanonicalShadowLegacySnapshot(
            recordingCount: recordingEntries.count,
            studyItemCount: studyItems.count,
            artifactCount: artifacts.count,
            objects: legacyObjectFacts(recordingEntries: recordingEntries, studyItems: studyItems)
        )
        let durationMs = max(0, Date().timeIntervalSince(startedAt) * 1_000)
        let report = CanonicalShadowReportBuilder().build(
            runID: syncRunID,
            syncRunID: syncRunID,
            trigger: trigger,
            nodeID: localSyncDeviceID,
            nodeRole: .mac,
            generatedAt: generatedAt,
            durationMs: durationMs,
            manifest: canonicalManifest,
            legacy: legacy
        )

        do {
            let logURL = recordingFileStore.libraryRootURL
                .appendingPathComponent("Diagnostics", isDirectory: true)
                .appendingPathComponent("canonical-shadow.jsonl", isDirectory: false)
            try CanonicalShadowReportJSONLWriter().append(report, to: logURL)
            emitConnectionDiagnostic(
                phase: "canonicalShadowReportWritten",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: "objects=\(report.canonicalObjectCount),mismatches=\(report.comparison.mismatches.count)"
            )
        } catch {
            emitConnectionDiagnostic(
                phase: "canonicalShadowReportWriteFailed",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorCode: "canonical_shadow_write_failed",
                errorMessage: error.localizedDescription
            )
        }

        emitConnectionDiagnostic(
            phase: "canonicalShadowBuildCompleted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "objects=\(report.canonicalObjectCount),legacyRecordings=\(report.legacyRecordingCount)"
        )
        emitConnectionDiagnostic(
            phase: "canonicalShadowBuildDurationMs",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "\(Int(durationMs.rounded()))"
        )
        recordCanonicalShadowDiagnostics(report, syncRunID: syncRunID)
    }

    private nonisolated static func canonicalAudioFact(from entry: LocalNetworkSyncRecordingEntry) -> CanonicalArtifactFact {
        let availability: CanonicalArtifact.Availability
        if entry.audioAvailability == .missing || (!entry.audioAvailable && entry.audioSize == nil && entry.audioChecksum == nil) {
            availability = .missing
        } else if entry.audioAvailable, entry.audioChecksum != nil, entry.audioSize != nil {
            availability = .available
        } else {
            availability = .availableWithoutHash
        }
        let contentHash = entry.audioChecksum.map { CanonicalHash($0) }
        return CanonicalArtifactFact.audio(
            availability: availability,
            contentHash: contentHash,
            byteSize: entry.audioSize,
            logicalName: Self.logicalName(from: entry.audioLogicalPathToken),
            logicalPathToken: entry.audioLogicalPathToken,
            producedByNodeID: entry.sourceDeviceID
        )
    }

    private nonisolated static func canonicalGeneratedArtifact(
        from artifact: LocalNetworkSyncArtifactEntry,
        nodeID: String,
        platform: String
    ) -> CanonicalArtifact? {
        guard let kind = Self.canonicalGeneratedArtifactKind(from: artifact.kind) else {
            return nil
        }
        let availability = Self.canonicalAvailability(from: artifact.availability, checksum: artifact.checksum, size: artifact.size)
        return CanonicalProjectionContract.makeArtifact(
            objectID: artifact.ownerID,
            kind: kind,
            availability: availability,
            contentHash: artifact.checksum.map { CanonicalHash($0) },
            byteSize: artifact.size,
            logicalPathToken: artifact.logicalPathToken,
            modifiedAt: CanonicalTimestamp(artifact.updatedAt),
            observedAt: CanonicalTimestamp(artifact.updatedAt),
            producedByNodeID: nodeID,
            platform: platform
        )
    }

    private nonisolated static func canonicalGeneratedArtifactKind(from kind: LocalNetworkSyncArtifactKind) -> CanonicalArtifact.Kind? {
        switch kind {
        case .transcriptJSON:
            return .transcriptJSON
        case .transcriptMarkdown:
            return .transcriptMarkdown
        case .noteMarkdown:
            return .noteMarkdown
        case .noteJSON:
            return .noteJSON
        case .summaryJSON:
            return .summaryJSON
        case .metadataJSON, .receiveJSON, .summaryMarkdown, .audio:
            return nil
        }
    }

    private nonisolated static func canonicalAvailability(
        from availability: LocalNetworkSyncArtifactAvailability,
        checksum: String?,
        size: Int64?
    ) -> CanonicalArtifact.Availability {
        switch availability {
        case .local, .availableOnPeer, .complete:
            return checksum != nil && size != nil ? .available : .availableWithoutHash
        case .missing:
            return .missing
        case .transferring:
            return .unknown
        }
    }

    private func legacyObjectFacts(
        recordingEntries: [LocalNetworkSyncRecordingEntry],
        studyItems: [StudyItemMetadata]
    ) -> [CanonicalShadowLegacyObjectFact] {
        let itemIDsByRecordingID = Dictionary(grouping: studyItems.compactMap { item -> String? in
            Self.normalizedNonEmpty(item.recordingID)
        }) { $0 }
        let recordingFacts = recordingEntries.map { entry in
            CanonicalShadowLegacyObjectFact(
                objectID: entry.recordingID,
                legacyMetadataHash: entry.metadataHash,
                audioHash: entry.audioChecksum,
                audioByteSize: entry.audioSize,
                audioAvailability: entry.audioAvailability?.rawValue ?? (entry.audioAvailable ? "local" : "missing"),
                hasRecordingMetadata: false,
                hasReceiveRecord: true,
                hasStudyItem: itemIDsByRecordingID[entry.recordingID] != nil
            )
        }
        let studyItemFacts = studyItems.compactMap { item -> CanonicalShadowLegacyObjectFact? in
            guard let recordingID = Self.normalizedNonEmpty(item.recordingID) else {
                return nil
            }
            return CanonicalShadowLegacyObjectFact(
                objectID: recordingID,
                legacyMetadataHash: LocalNetworkSyncMetadataHash.hash(item),
                hasStudyItem: true
            )
        }
        return recordingFacts + studyItemFacts
    }

    private func recordCanonicalShadowDiagnostics(
        _ report: CanonicalShadowReport,
        syncRunID: String?
    ) {
        if !report.comparison.metadataHashConvergedObjectIDs.isEmpty {
            emitConnectionDiagnostic(
                phase: "canonicalShadowMetadataHashConverged",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: "count=\(report.comparison.metadataHashConvergedObjectIDs.count)"
            )
        }
        let grouped = Dictionary(grouping: report.comparison.mismatches) { $0.category }
        for (category, mismatches) in grouped {
            emitConnectionDiagnostic(
                phase: "canonicalShadowLegacyMismatchDetected",
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: "category=\(category.rawValue),count=\(mismatches.count)"
            )
            switch category {
            case .studyItemOnlyWithoutReceiveRecord:
                emitConnectionDiagnostic(phase: "canonicalShadowStudyItemOnlyWithoutReceiveRecord", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            case .canonicalMetadataHashConverged:
                emitConnectionDiagnostic(phase: "canonicalShadowMetadataHashConverged", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            case .canonicalCreatedAtIgnoredForMetadataHash:
                emitConnectionDiagnostic(phase: "canonicalShadowCreatedAtIgnoredForMetadataHash", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            case .canonicalModifiedAtIgnoredProcessingState:
                emitConnectionDiagnostic(phase: "canonicalShadowModifiedAtIgnoredProcessingState", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            case .canonicalMacUpdatedAtRejectedAsProcessingClock:
                emitConnectionDiagnostic(phase: "canonicalShadowMacUpdatedAtRejectedAsProcessingClock", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            case .canonicalBusinessModifiedAtUsed:
                emitConnectionDiagnostic(phase: "canonicalShadowBusinessModifiedAtUsed", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            case .canonicalMetadataHashMismatch, .legacyMetadataHashMismatchButCanonicalHashMatch:
                emitConnectionDiagnostic(phase: "canonicalShadowMetadataHashDiverged", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "category=\(category.rawValue),count=\(mismatches.count)")
            case .canonicalAudioConflict:
                emitConnectionDiagnostic(phase: "canonicalShadowAudioConflictDetected", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            case .canonicalGeneratedArtifactPeerSameNoOp:
                emitConnectionDiagnostic(phase: "canonicalShadowGeneratedArtifactPeerSameNoOp", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            case .canonicalGeneratedArtifactPeerUnknownDeferred:
                emitConnectionDiagnostic(phase: "canonicalShadowGeneratedArtifactPeerUnknownDeferred", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            case .canonicalGeneratedArtifactConflict:
                emitConnectionDiagnostic(phase: "canonicalShadowGeneratedArtifactConflict", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(mismatches.count)")
            default:
                break
            }
        }
    }

    private func recordCanonicalInventoryCoverage(
        _ coverage: CanonicalInventoryCoverageReport,
        syncRunID: String?
    ) {
        emitConnectionDiagnostic(
            phase: "canonicalInventoryCoverageReportWritten",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "recordings=\(coverage.recordingCoverage)",
                "audio=\(coverage.audioCoverage)",
                "generatedArtifacts=\(coverage.generatedArtifactCoverage)",
                "folders=\(coverage.folderCoverage)",
                "studyItems=\(coverage.studyItemCoverage)",
                "tombstones=\(coverage.tombstoneCoverage)",
                "unsupported=\(coverage.unsupportedLegacyObjectCount)",
                "fallbackRequired=\(coverage.fallbackRequiredCount)"
            ].joined(separator: ",")
        )
        if coverage.folderCoverage > 0 {
            emitConnectionDiagnostic(phase: "canonicalFolderProjected", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(coverage.folderCoverage)")
        }
        if coverage.studyItemCoverage > 0 {
            emitConnectionDiagnostic(phase: "canonicalStudyItemProjected", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(coverage.studyItemCoverage)")
        }
        if coverage.tombstoneCoverage > 0 {
            emitConnectionDiagnostic(phase: "canonicalLibraryTombstoneProjected", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(coverage.tombstoneCoverage)")
        }
        if coverage.unsupportedLegacyObjectCount > 0 {
            emitConnectionDiagnostic(phase: "canonicalLibraryObjectUnsupported", listenerState: "ready", activePort: activePort, syncRunID: syncRunID, errorMessage: "count=\(coverage.unsupportedLegacyObjectCount)")
        }
    }

    private func recordFileKernelRuntimeDiagnostics(
        snapshot: CanonicalFileRuntimeSnapshot,
        manifest: CanonicalFileManifestRuntimeResult,
        buildCount: Int,
        syncRunID: String?
    ) {
        emitConnectionDiagnostic(
            phase: "canonicalFileKernelSnapshotBuilt",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "rootToken=\(snapshot.scope.rootToken.rawValue)",
                "entryCount=\(snapshot.entries.count)",
                "durationMs=\(snapshot.durationMs)",
                "builtOffMain=\(snapshot.builtOffMainActor)",
                "mainActorFileTreeAttemptCount=\(snapshot.mainActorAttemptCount)",
                "requestBuildCount=\(buildCount)",
                "redacted=\(snapshot.redacted)"
            ].joined(separator: ",")
        )
        emitConnectionDiagnostic(
            phase: "canonicalFileKernelManifestBuilt",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "rootToken=\(manifest.cacheKey.rootToken.rawValue)",
                "cacheKeyPrefix=\(manifest.cacheKey.cacheKeyHashPrefix)",
                "entryCount=\(manifest.manifest.entries.count)",
                "durationMs=\(manifest.durationMs)",
                "builtOffMain=\(manifest.builtOffMainActor)",
                "mainActorManifestAttemptCount=\(manifest.mainActorAttemptCount)"
            ].joined(separator: ",")
        )
    }

    private static func makeMacFileKernelRuntime(
        rootToken: CanonicalRootToken,
        adapter: any CanonicalFileSnapshotRuntimeAdapter
    ) async -> (snapshot: CanonicalFileRuntimeSnapshot?, manifest: CanonicalFileManifestRuntimeResult?) {
        guard let scope = try? CanonicalFileSnapshotScope(
            rootToken: rootToken,
            logicalScopeToken: ".",
            domainHint: .studyLibraryMetadata
        ) else {
            return (nil, nil)
        }
        do {
            let snapshot = try await CanonicalFileTreeSnapshotBuilder(adapter: adapter).buildSnapshot(scope: scope)
            let manifestStartedAt = Date()
            let manifest = await Task.detached(priority: .utility) {
                CanonicalManifestRuntimeBuilder().buildFileManifest(from: snapshot)
            }.value
            Task { @MainActor in
                ConnectionDiagnosticsStore.shared.recordPerfLog(
                    CanonicalPerfLog.subphaseMeasured(
                        operation: .immediateSync,
                        subphase: .inventoryBuildMs,
                        durationMs: CanonicalPerfLog.elapsedMs(since: manifestStartedAt),
                        result: "macFileKernelManifestBuild"
                    )
                )
            }
            return (snapshot, manifest)
        } catch {
            return (nil, nil)
        }
    }

    private static func fileSnapshotEntries(
        from artifacts: [LocalNetworkSyncArtifactEntry]
    ) -> [CanonicalFileSnapshotSourceEntry] {
        artifacts.compactMap { artifact in
            guard let logicalPathToken = normalizedNonEmpty(artifact.logicalPathToken) else {
                return nil
            }
            return try? CanonicalFileSnapshotSourceEntry(
                logicalToken: logicalPathToken,
                kind: .file,
                byteSize: artifact.size ?? 0,
                modifiedAt: CanonicalTimestamp(artifact.updatedAt),
                contentVersion: artifact.checksum.map { String($0.prefix(12)) },
                stableFileIdentity: artifact.artifactID,
                domainHint: fileDomainHint(for: artifact.kind),
                hashProof: artifact.checksum.map { CanonicalHash($0) }
            )
        }
    }

    private static func fileDomainHint(for kind: LocalNetworkSyncArtifactKind) -> CanonicalFileDomainHint {
        switch kind {
        case .audio:
            return .recordingAudio
        case .metadataJSON:
            return .recordingMetadata
        case .receiveJSON:
            return .receiveRecord
        case .transcriptMarkdown, .transcriptJSON, .noteMarkdown, .noteJSON, .summaryMarkdown, .summaryJSON:
            return .generatedArtifact
        }
    }

    private nonisolated static func logicalName(from token: String?) -> String? {
        Self.normalizedNonEmpty(token)?
            .split(separator: "/")
            .last
            .map(String.init)
    }

    private nonisolated static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func cachedRuntimeChecksum(
        fileURL: URL,
        pathToken: String?,
        recordingID: String,
        syncRunID: String?,
        cacheDirectoryURL: URL
    ) async -> (legacyResult: LocalNetworkChecksumCacheResult?, runtimeResult: CanonicalChecksumCacheResult) {
        let result = await canonicalChecksumRuntime.checksum(
            fileURL: fileURL,
            logicalToken: pathToken,
            nodeRole: .mac,
            cacheDirectoryURL: cacheDirectoryURL,
            configuration: inventoryRuntimeConfiguration
        )
        let safeRecording = String(recordingID.prefix(12))
        let safePath = String((pathToken ?? "missing").prefix(12))
        switch result.event {
        case .hit:
            emitConnectionDiagnostic(
                phase: "canonicalInventoryRuntimeCacheHit",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath),size=\(result.byteSize)"
            )
            emitConnectionDiagnostic(
                phase: "canonicalInventoryRuntimeHashSkippedDueToCacheHit",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath),hashPrefix=\(result.redactedHashPrefix ?? "missing")"
            )
            emitConnectionDiagnostic(
                phase: "checksumCacheHit",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath),size=\(result.byteSize)"
            )
        case .miss:
            emitConnectionDiagnostic(
                phase: "canonicalInventoryRuntimeCacheMiss",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath),size=\(result.byteSize)"
            )
            emitConnectionDiagnostic(
                phase: "checksumCacheMiss",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath),size=\(result.byteSize)"
            )
        case .stale:
            emitConnectionDiagnostic(
                phase: "canonicalInventoryRuntimeCacheStale",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath),size=\(result.byteSize)"
            )
            emitConnectionDiagnostic(
                phase: "checksumCacheInvalidated",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath),size=\(result.byteSize)"
            )
        case .error:
            emitConnectionDiagnostic(
                phase: "canonicalInventoryRuntimeCacheError",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorCode: result.failure?.rawValue ?? "cache_error",
                errorMessage: "path=\(safePath)"
            )
            emitConnectionDiagnostic(
                phase: "canonicalInventoryRuntimeHashFailed",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorCode: result.failure?.rawValue ?? "hash_unavailable",
                errorMessage: "path=\(safePath)"
            )
            emitConnectionDiagnostic(
                phase: "checksumCacheMiss",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorCode: "checksum_failed",
                errorMessage: "path=\(safePath)"
            )
        }
        if result.hashComputed {
            emitConnectionDiagnostic(
                phase: "canonicalInventoryRuntimeHashComputed",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath),durationMs=\(result.hashDurationMs),hashPrefix=\(result.redactedHashPrefix ?? "missing")"
            )
            emitConnectionDiagnostic(
                phase: "canonicalInventoryRuntimeHashStarted",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath)"
            )
            emitConnectionDiagnostic(
                phase: "canonicalInventoryRuntimeHashCompleted",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath),durationMs=\(result.hashDurationMs)"
            )
            emitConnectionDiagnostic(
                phase: "checksumComputedOffMainActor",
                listenerState: "ready",
                activePort: activePort,
                requestDeviceIDPrefix: safeRecording,
                syncRunID: syncRunID,
                errorMessage: "path=\(safePath)"
            )
            if result.cachePersisted {
                emitConnectionDiagnostic(
                    phase: "canonicalInventoryRuntimeCachePersisted",
                    listenerState: "ready",
                    activePort: activePort,
                    requestDeviceIDPrefix: safeRecording,
                    syncRunID: syncRunID,
                    errorMessage: "path=\(safePath),durationMs=\(result.cacheWriteDurationMs),recordCount=\(result.cacheRecordCount)"
                )
            }
            if result.cachePrunedRecordCount > 0 {
                emitConnectionDiagnostic(
                    phase: "canonicalInventoryRuntimeCachePruned",
                    listenerState: "ready",
                    activePort: activePort,
                    syncRunID: syncRunID,
                    errorMessage: "prunedRecordCount=\(result.cachePrunedRecordCount),durationMs=\(result.cachePruneDurationMs)"
                )
            }
        }
        guard let sha256 = result.sha256 else {
            return (nil, result)
        }
        let legacyEvent: LocalNetworkChecksumCacheEvent
        switch result.event {
        case .hit:
            legacyEvent = .hit
        case .miss, .error:
            legacyEvent = .miss
        case .stale:
            legacyEvent = .invalidated
        }
        let legacy = LocalNetworkChecksumCacheResult(
            sha256: sha256,
            size: result.byteSize,
            modifiedAt: result.modifiedAt,
            computedAt: Date(),
            event: legacyEvent
        )
        return (legacy, result)
    }

    private func canonicalChecksumCacheDirectory() -> URL {
        recordingFileStore.libraryRootURL
            .appendingPathComponent("Sync", isDirectory: true)
            .appendingPathComponent("CanonicalChecksumCache", isDirectory: true)
    }

    private func recordCanonicalSyncRuntimeInventoryEvaluation(
        runtimeSnapshot: CanonicalInventoryRuntimeSnapshot,
        localManifest: CanonicalManifest,
        coverage: CanonicalInventoryCoverageReport,
        syncRunID: String?
    ) {
        let configuration = canonicalSyncRuntimeConfiguration
        let context = CanonicalSyncPlanAuthorityGateContext(
            inventorySnapshotAvailable: true,
            localManifest: localManifest,
            peerManifest: nil,
            peerAbsenceExplicitlyModeled: false,
            localMetadataHashSchemaVersion: CanonicalRecordingMetadata.businessMetadataHashSchemaVersion,
            peerMetadataHashSchemaVersion: nil,
            localLibraryMetadataHashSchemaVersion: CanonicalLibraryMetadataHashSchema.version,
            peerLibraryMetadataHashSchemaVersion: nil,
            localGeneratedArtifactHashSchemaVersion: CanonicalGeneratedArtifactHashSchema.version,
            peerGeneratedArtifactHashSchemaVersion: nil,
            canonicalModifiedAtSemanticsAvailable: true,
            unsupportedLegacyObjectCount: coverage.unsupportedLegacyObjectCount,
            libraryFallbackRequiredObjectCount: coverage.fallbackRequiredCount,
            conflictCount: 0,
            peerUnknownAudioCount: 0,
            legacyFallbackAvailable: true,
            diagnosticsRedacted: runtimeSnapshot.redacted,
            runtimeSwitchEnabled: false,
            readPathLegacy: true,
            otherActiveMigrationDomainConflicting: false,
            debugInternalBuild: configuration.policy.debugInternalBuild,
            ownerApproved: configuration.policy.ownerApproved,
            releaseDefaultBuild: configuration.policy.releaseDefaultBuild
        )
        let gateResult = CanonicalSyncPlanAuthorityGate().evaluate(
            configuration: configuration,
            context: context
        )
        var extraDiagnostics = canonicalSyncRuntimeBlockerDiagnostics(
            gateResult: gateResult,
            syncRunID: syncRunID,
            mode: configuration.mode
        )
        if gateResult.blockers.contains(.peerUnavailable) {
            extraDiagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalSyncRuntimePlanFallback,
                    syncRunID: syncRunID,
                    mode: configuration.mode,
                    detail: "legacyReportOnly"
                )
            )
        }
        recordCanonicalSyncRuntimeDiagnostics(
            CanonicalSyncRuntimeResult.make(
                mode: configuration.mode,
                gateResult: gateResult,
                syncRunID: syncRunID,
                extraDiagnostics: extraDiagnostics
            )
        )
    }

    private func canonicalSyncRuntimeBlockerDiagnostics(
        gateResult: CanonicalSyncPlanAuthorityGateResult,
        syncRunID: String?,
        mode: CanonicalSyncRuntimeMode
    ) -> [CanonicalSyncRuntimeDiagnostic] {
        var diagnostics: [CanonicalSyncRuntimeDiagnostic] = []
        if gateResult.blockers.contains(.unsupportedObjects) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimeUnsupportedObjectBlocked, syncRunID: syncRunID, mode: mode, detail: gateResult.state.rawValue))
        }
        if gateResult.blockers.contains(.unresolvedConflicts) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimeConflictBlocked, syncRunID: syncRunID, mode: mode, detail: gateResult.state.rawValue))
        }
        if gateResult.blockers.contains(.peerUnavailable) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimePeerSnapshotUnavailable, syncRunID: syncRunID, mode: mode, detail: gateResult.state.rawValue))
        }
        if gateResult.blockers.contains(.schemaMismatch) {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalSyncRuntimeSchemaMismatch, syncRunID: syncRunID, mode: mode, detail: gateResult.state.rawValue))
        }
        return diagnostics
    }

    private func recordCanonicalSyncRuntimeDiagnostics(_ result: CanonicalSyncRuntimeResult) {
        for diagnostic in result.diagnostics where diagnostic.isRedacted {
            emitConnectionDiagnostic(
                phase: diagnostic.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: diagnostic.syncRunID,
                errorMessage: diagnostic.summary()
            )
        }
    }

    private func recordRuntimeSnapshotDiagnostics(
        _ snapshot: CanonicalInventoryRuntimeSnapshot,
        syncRunID: String?
    ) {
        let report = CanonicalInventoryRuntimeReportExporter.report(from: snapshot)
        emitConnectionDiagnostic(
            phase: "canonicalInventoryRuntimeSnapshotBuilt",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: CanonicalInventoryRuntimeReportExporter.diagnosticsSummary(from: snapshot)
        )
        emitConnectionDiagnostic(
            phase: "canonicalInventoryRuntimeSnapshotReused",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "source=\(snapshot.sourceKind.rawValue),reused=\(snapshot.reusedWithinTick)"
        )
        emitConnectionDiagnostic(
            phase: "canonicalInventoryRuntimeDuplicateBuildSuppressed",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "source=\(snapshot.sourceKind.rawValue),duplicateBuildCount=\(report.duplicateBuildCount)"
        )
        emitConnectionDiagnostic(
            phase: "canonicalInventoryRuntimeDuplicateBuildDetected",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "count=\(report.duplicateBuildCount)"
        )
        emitConnectionDiagnostic(
            phase: "canonicalInventoryRuntimeReportWritten",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "buildDurationMs=\(report.buildDurationMs)",
                "scanDurationMs=\(report.scanDurationMs)",
                "manifestBuildDurationMs=\(report.manifestBuildDurationMs)",
                "metadataLoadDurationMs=\(report.metadataLoadDurationMs)",
                "jobsLoadDurationMs=\(report.jobsLoadDurationMs)",
                "fileScanDurationMs=\(report.fileScanDurationMs)",
                "hashDurationMs=\(report.hashDurationMs)",
                "cacheLoadDurationMs=\(report.cacheLoadDurationMs)",
                "cacheWriteDurationMs=\(report.cacheWriteDurationMs)",
                "cachePruneDurationMs=\(report.cachePruneDurationMs)",
                "cacheHitCount=\(report.cacheHitCount)",
                "cacheMissCount=\(report.cacheMissCount)",
                "cacheStaleCount=\(report.cacheStaleCount)",
                "cacheErrorCount=\(report.cacheErrorCount)",
                "hashComputedCount=\(report.hashComputedCount)",
                "hashSkippedByCacheHitCount=\(report.hashSkippedByCacheHitCount)",
                "hashFailedCount=\(report.hashFailedCount)",
                "hashUnavailableCount=\(report.hashUnavailableCount)",
                "duplicateBuildCount=\(report.duplicateBuildCount)",
                "duplicateSnapshotBuildCount=\(report.duplicateBuildCount)",
                "snapshotReuseCount=\(report.snapshotReuseCount)",
                "mainActorHashAttemptCount=\(report.mainActorHashAttemptCount)",
                "mainActorScanAttemptCount=\(report.mainActorScanAttemptCount)",
                "mainActorMetadataLoadAttemptCount=\(report.mainActorMetadataLoadAttemptCount)",
                "mainActorJobsLoadAttemptCount=\(report.mainActorJobsLoadAttemptCount)",
                "mainActorManifestBuildAttemptCount=\(report.mainActorManifestBuildAttemptCount)",
                "mainActorHashBlockedCount=\(report.mainActorHashBlockedCount)",
                "mainActorScanBlockedCount=\(report.mainActorScanBlockedCount)",
                "redactionViolationCount=\(report.redactionViolationCount)",
                "redacted=\(report.redacted)"
            ].joined(separator: ",")
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
            lastSyncStatus: Self.displaySyncStatus(syncStatus) ?? syncStateStore.state.lastError ?? syncStateStore.state.lastSuccessfulSyncAt.map { _ in "已同步" }
        )
    }

    private static func displaySyncStatus(_ rawStatus: String?) -> String? {
        switch rawStatus {
        case "sync-start", "sync-ack":
            return "iPhone 已收到同步请求"
        case "inventory":
            return "正在同步"
        case "metadata", "artifact":
            return "正在同步"
        case let status?:
            return status
        case nil:
            return nil
        }
    }

    private var localSyncDeviceID: String {
        let fingerprint = identityManager.status.displayFingerprint
        guard fingerprint != "未生成", !fingerprint.isEmpty else {
            return "mac-local"
        }
        return "mac-\(String(fingerprint.prefix(16)))"
    }

    @discardableResult
    private func applyCanonicalRecordingExistenceBridgeIfNeededSynchronously(
        manifest: StudyLibrarySyncManifest,
        sourceDeviceID: String,
        syncRunID: String?
    ) -> [CanonicalRecordingExistenceApplyResult] {
        guard !manifest.recordings.isEmpty else {
            return []
        }
        emitConnectionDiagnostic(
            phase: CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyStarted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "count=\(manifest.recordings.count)"
        )
        emitConnectionDiagnostic(
            phase: CanonicalSyncRuntimeDiagnosticKind.canonicalExistenceManifestRecordingsConsumed.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "count=\(manifest.recordings.count)"
        )
        if canonicalApplyRuntimeConfiguration.mode != .disabled {
            if let runtimeResults = applyCanonicalRecordingExistenceWithApplyRuntimeGateSynchronously(
                manifest: manifest,
                sourceDeviceID: sourceDeviceID,
                syncRunID: syncRunID
            ) {
                return runtimeResults
            }
        }
        let bridgeConfiguration = manifestRecordingsExistenceApplyConfiguration()
        guard bridgeConfiguration.mode != .disabled,
              bridgeConfiguration.mode != .blocked,
              bridgeConfiguration.canWriteMetadataOnlyRecord else {
            emitConnectionDiagnostic(
                phase: CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyNoOp.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: "existenceApplyDisabled"
            )
            return []
        }
        guard let port = canonicalRecordingExistenceApplyPort else {
            let results = missingCanonicalExistenceApplyPortResults(
                recordings: manifest.recordings,
                syncRunID: syncRunID
            )
            for result in results {
                recordCanonicalExistenceDiagnostics(result.diagnostics)
            }
            emitConnectionDiagnostic(
                phase: CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyBlocked.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorCode: "canonical_existence_apply_port_missing",
                errorMessage: "count=\(results.count),blocked=\(results.count)"
            )
            return results
        }
        let bridgeResult = applyRecordingExistenceBridgeSynchronouslyInBackground(
            configuration: bridgeConfiguration,
            port: port,
            recordings: manifest.recordings,
            sourceDeviceID: sourceDeviceID,
            syncRunID: syncRunID
        )
        let results = bridgeResult.results
        emitConnectionDiagnostic(
            phase: "canonicalExistenceLedgerBackgroundWriteCompleted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "context=manifestRecordingExistenceBridge",
                "ledgerWriteDurationMs=\(bridgeResult.ioDurationMs)",
                "mainActorLongTaskDurationMs=\(bridgeResult.mainActorLongTaskDurationMs)"
            ].joined(separator: ",")
        )
        for result in results {
            recordCanonicalExistenceDiagnostics(result.diagnostics)
        }
        let blockedCount = results.filter { $0.action == .blocked || $0.action == .conflict || $0.action == .rollbackFailed }.count
        emitConnectionDiagnostic(
            phase: blockedCount == 0
                ? CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyCompleted.rawValue
                : CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyBlocked.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "count=\(results.count),blocked=\(blockedCount)"
        )
        return results
    }

    @discardableResult
    private func applyCanonicalRecordingExistenceBridgeIfNeeded(
        manifest: StudyLibrarySyncManifest,
        sourceDeviceID: String,
        syncRunID: String?
    ) async -> [CanonicalRecordingExistenceApplyResult] {
        guard !manifest.recordings.isEmpty else {
            return []
        }
        emitConnectionDiagnostic(
            phase: CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyStarted.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "count=\(manifest.recordings.count)"
        )
        emitConnectionDiagnostic(
            phase: CanonicalSyncRuntimeDiagnosticKind.canonicalExistenceManifestRecordingsConsumed.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "count=\(manifest.recordings.count)"
        )
        if canonicalApplyRuntimeConfiguration.mode != .disabled {
            if let runtimeResults = await applyCanonicalRecordingExistenceWithApplyRuntimeGate(
                manifest: manifest,
                sourceDeviceID: sourceDeviceID,
                syncRunID: syncRunID
            ) {
                return runtimeResults
            }
        }
        let bridgeConfiguration = manifestRecordingsExistenceApplyConfiguration()
        guard bridgeConfiguration.mode != .disabled,
              bridgeConfiguration.mode != .blocked,
              bridgeConfiguration.canWriteMetadataOnlyRecord else {
            emitConnectionDiagnostic(
                phase: CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyNoOp.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorMessage: "existenceApplyDisabled"
            )
            return []
        }
        guard let port = canonicalRecordingExistenceApplyPort else {
            let results = missingCanonicalExistenceApplyPortResults(
                recordings: manifest.recordings,
                syncRunID: syncRunID
            )
            for result in results {
                recordCanonicalExistenceDiagnostics(result.diagnostics)
            }
            emitConnectionDiagnostic(
                phase: CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyBlocked.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: syncRunID,
                errorCode: "canonical_existence_apply_port_missing",
                errorMessage: "count=\(results.count),blocked=\(results.count)"
            )
            return results
        }
        let bridgeResult = await applyRecordingExistenceBridgeInBackground(
            configuration: bridgeConfiguration,
            port: port,
            recordings: manifest.recordings,
            sourceDeviceID: sourceDeviceID,
            syncRunID: syncRunID
        )
        let results = bridgeResult.results
        emitConnectionDiagnostic(
            phase: "canonicalExistenceLedgerBackgroundWriteCompleted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "context=manifestRecordingExistenceBridge",
                "ledgerWriteDurationMs=\(bridgeResult.ioDurationMs)",
                "mainActorLongTaskDurationMs=\(bridgeResult.mainActorLongTaskDurationMs)"
            ].joined(separator: ",")
        )
        for result in results {
            recordCanonicalExistenceDiagnostics(result.diagnostics)
        }
        let blockedCount = results.filter { $0.action == .blocked || $0.action == .conflict || $0.action == .rollbackFailed }.count
        emitConnectionDiagnostic(
            phase: blockedCount == 0
                ? CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyCompleted.rawValue
                : CanonicalSyncRuntimeDiagnosticKind.canonicalManifestRecordingsApplyBlocked.rawValue,
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: "count=\(results.count),blocked=\(blockedCount)"
        )
        return results
    }

    @discardableResult
    private func applyCanonicalRecordingExistenceWithApplyRuntimeGateSynchronously(
        manifest: StudyLibrarySyncManifest,
        sourceDeviceID: String,
        syncRunID: String?
    ) -> [CanonicalRecordingExistenceApplyResult]? {
        let actions = manifest.recordings.map { recording in
            CanonicalApplyAction(
                kind: .recordingMetadataApply,
                source: .peer,
                target: CanonicalApplyTarget(objectID: recording.recordingID),
                bridgeHint: .legacyMetadataManifestApply,
                preconditions: [CanonicalApplyPrecondition(kind: .legacyBridge, value: "metadataOnly")],
                reason: CanonicalApplyRuntimeOwner.recordingExistenceBridgeReason
            )
        }
        let applyPlan = CanonicalApplyPlan(
            trigger: .manual,
            actions: actions
        )
        let registry = CanonicalApplyRuntimeExecutorRegistry(entries: [
            CanonicalApplyRuntimeExecutorEntry(
                domain: .recordingExistence,
                dryRunOnly: false,
                rollbackAvailable: true,
                postconditionAvailable: true,
                rootBoundApplyPortAvailable: true
            ) { context in
                CanonicalApplyRuntimeExecutorResult.success(
                    action: context.action,
                    domain: .recordingExistence,
                    detail: "metadataOnlyBridge"
                )
            }
        ])
        let gateResult = CanonicalApplyRuntimeGate().evaluate(
            CanonicalApplyRuntimeOwnerContext(
                configuration: canonicalApplyRuntimeConfiguration,
                applyPlan: applyPlan,
                localManifest: minimalCanonicalManifest(nodeID: localSyncDeviceID, platform: "Mac"),
                peerManifest: minimalCanonicalManifest(nodeID: sourceDeviceID, platform: "iPhone"),
                inventorySnapshotValid: true,
                canonicalPlanAuthorityAllowed: canonicalSyncRuntimeConfiguration.mode == .canonicalPlanPrimaryWithLegacyFallback
                    && canonicalSyncRuntimeConfiguration.policy.debugInternalBuild
                    && canonicalSyncRuntimeConfiguration.policy.ownerApproved
                    && canonicalSyncRuntimeConfiguration.policy.releaseDefaultBuild == false,
                legacyFallbackAvailable: true,
                registry: registry,
                syncRunID: syncRunID
            )
        )
        let diagnostics = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalApplyRuntimeModeEvaluated,
                syncRunID: syncRunID,
                mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                count: actions.count,
                detail: gateResult.state.rawValue
            ),
            CanonicalSyncRuntimeDiagnostic(
                kind: gateResult.isAllowed ? .canonicalApplyRuntimeGateAllowed : .canonicalApplyRuntimeGateBlocked,
                syncRunID: syncRunID,
                mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                count: gateResult.blockers.count,
                detail: gateResult.blockers.map(\.rawValue).joined(separator: "+").nilIfEmpty ?? "none"
            )
        ]
        recordCanonicalExistenceDiagnostics(diagnostics)
        guard gateResult.executesCommit else {
            recordCanonicalExistenceDiagnostics([
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalApplyRuntimeLegacyFallbackUsed,
                    syncRunID: syncRunID,
                    mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                    count: gateResult.blockers.count,
                    detail: gateResult.blockers.map(\.rawValue).joined(separator: "+").nilIfEmpty ?? "legacyFallback"
                )
            ])
            return nil
        }
        guard let port = canonicalRecordingExistenceApplyPort else {
            let results = missingCanonicalExistenceApplyPortResults(
                recordings: manifest.recordings,
                syncRunID: syncRunID
            )
            for result in results {
                recordCanonicalExistenceDiagnostics(result.diagnostics)
            }
            return results
        }
        let bridgeResult = applyRecordingExistenceBridgeSynchronouslyInBackground(
            configuration: canonicalExistenceApplyConfigurationForApplyRuntime(),
            port: port,
            recordings: manifest.recordings,
            sourceDeviceID: sourceDeviceID,
            syncRunID: syncRunID
        )
        let results = bridgeResult.results
        emitConnectionDiagnostic(
            phase: "canonicalExistenceLedgerBackgroundWriteCompleted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "context=canonicalApplyRuntimeRecordingExistenceBridge",
                "ledgerWriteDurationMs=\(bridgeResult.ioDurationMs)",
                "mainActorLongTaskDurationMs=\(bridgeResult.mainActorLongTaskDurationMs)"
            ].joined(separator: ",")
        )
        for result in results {
            recordCanonicalExistenceDiagnostics(result.diagnostics)
            recordCanonicalExistenceDiagnostics([
                CanonicalSyncRuntimeDiagnostic(
                    kind: result.action == .written || result.action == .noOp ? .canonicalApplyRuntimeActionCompleted : .canonicalApplyRuntimeActionFailed,
                    syncRunID: syncRunID,
                    mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                    objectID: result.objectID,
                    actionKind: CanonicalApplyActionKind.recordingMetadataApply.rawValue,
                    detail: result.action.rawValue
                )
            ])
        }
        recordCanonicalExistenceDiagnostics([
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalApplyRuntimeReportBuilt,
                syncRunID: syncRunID,
                mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                count: results.count,
                detail: "recordingExistenceBridge"
            )
        ])
        return results
    }

    @discardableResult
    private func applyCanonicalRecordingExistenceWithApplyRuntimeGate(
        manifest: StudyLibrarySyncManifest,
        sourceDeviceID: String,
        syncRunID: String?
    ) async -> [CanonicalRecordingExistenceApplyResult]? {
        let actions = manifest.recordings.map { recording in
            CanonicalApplyAction(
                kind: .recordingMetadataApply,
                source: .peer,
                target: CanonicalApplyTarget(objectID: recording.recordingID),
                bridgeHint: .legacyMetadataManifestApply,
                preconditions: [CanonicalApplyPrecondition(kind: .legacyBridge, value: "metadataOnly")],
                reason: CanonicalApplyRuntimeOwner.recordingExistenceBridgeReason
            )
        }
        let applyPlan = CanonicalApplyPlan(
            trigger: .manual,
            actions: actions
        )
        let registry = CanonicalApplyRuntimeExecutorRegistry(entries: [
            CanonicalApplyRuntimeExecutorEntry(
                domain: .recordingExistence,
                dryRunOnly: false,
                rollbackAvailable: true,
                postconditionAvailable: true,
                rootBoundApplyPortAvailable: true
            ) { context in
                CanonicalApplyRuntimeExecutorResult.success(
                    action: context.action,
                    domain: .recordingExistence,
                    detail: "metadataOnlyBridge"
                )
            }
        ])
        let gateResult = CanonicalApplyRuntimeGate().evaluate(
            CanonicalApplyRuntimeOwnerContext(
                configuration: canonicalApplyRuntimeConfiguration,
                applyPlan: applyPlan,
                localManifest: minimalCanonicalManifest(nodeID: localSyncDeviceID, platform: "Mac"),
                peerManifest: minimalCanonicalManifest(nodeID: sourceDeviceID, platform: "iPhone"),
                inventorySnapshotValid: true,
                canonicalPlanAuthorityAllowed: canonicalSyncRuntimeConfiguration.mode == .canonicalPlanPrimaryWithLegacyFallback
                    && canonicalSyncRuntimeConfiguration.policy.debugInternalBuild
                    && canonicalSyncRuntimeConfiguration.policy.ownerApproved
                    && canonicalSyncRuntimeConfiguration.policy.releaseDefaultBuild == false,
                legacyFallbackAvailable: true,
                registry: registry,
                syncRunID: syncRunID
            )
        )
        let diagnostics = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalApplyRuntimeModeEvaluated,
                syncRunID: syncRunID,
                mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                count: actions.count,
                detail: gateResult.state.rawValue
            ),
            CanonicalSyncRuntimeDiagnostic(
                kind: gateResult.isAllowed ? .canonicalApplyRuntimeGateAllowed : .canonicalApplyRuntimeGateBlocked,
                syncRunID: syncRunID,
                mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                count: gateResult.blockers.count,
                detail: gateResult.blockers.map(\.rawValue).joined(separator: "+").nilIfEmpty ?? "none"
            )
        ]
        recordCanonicalExistenceDiagnostics(diagnostics)
        guard gateResult.executesCommit else {
            recordCanonicalExistenceDiagnostics([
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalApplyRuntimeLegacyFallbackUsed,
                    syncRunID: syncRunID,
                    mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                    count: gateResult.blockers.count,
                    detail: gateResult.blockers.map(\.rawValue).joined(separator: "+").nilIfEmpty ?? "legacyFallback"
                )
            ])
            return nil
        }
        guard let port = canonicalRecordingExistenceApplyPort else {
            let results = missingCanonicalExistenceApplyPortResults(
                recordings: manifest.recordings,
                syncRunID: syncRunID
            )
            for result in results {
                recordCanonicalExistenceDiagnostics(result.diagnostics)
            }
            return results
        }
        let bridgeResult = await applyRecordingExistenceBridgeInBackground(
            configuration: canonicalExistenceApplyConfigurationForApplyRuntime(),
            port: port,
            recordings: manifest.recordings,
            sourceDeviceID: sourceDeviceID,
            syncRunID: syncRunID
        )
        let results = bridgeResult.results
        emitConnectionDiagnostic(
            phase: "canonicalExistenceLedgerBackgroundWriteCompleted",
            listenerState: "ready",
            activePort: activePort,
            syncRunID: syncRunID,
            errorMessage: [
                "context=canonicalApplyRuntimeRecordingExistenceBridge",
                "ledgerWriteDurationMs=\(bridgeResult.ioDurationMs)",
                "mainActorLongTaskDurationMs=\(bridgeResult.mainActorLongTaskDurationMs)"
            ].joined(separator: ",")
        )
        for result in results {
            recordCanonicalExistenceDiagnostics(result.diagnostics)
            recordCanonicalExistenceDiagnostics([
                CanonicalSyncRuntimeDiagnostic(
                    kind: result.action == .written || result.action == .noOp ? .canonicalApplyRuntimeActionCompleted : .canonicalApplyRuntimeActionFailed,
                    syncRunID: syncRunID,
                    mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                    objectID: result.objectID,
                    actionKind: CanonicalApplyActionKind.recordingMetadataApply.rawValue,
                    detail: result.action.rawValue
                )
            ])
        }
        recordCanonicalExistenceDiagnostics([
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalApplyRuntimeReportBuilt,
                syncRunID: syncRunID,
                mode: canonicalApplyRuntimeConfiguration.mode.syncDiagnosticMode,
                count: results.count,
                detail: "recordingExistenceBridge"
            )
        ])
        return results
    }

    private func applyRecordingExistenceBridgeInBackground(
        configuration: CanonicalExistenceApplyRuntimeConfiguration,
        port: any MacCanonicalRecordingExistenceApplyPort,
        recordings: [LocalNetworkSyncRecordingEntry],
        sourceDeviceID: String,
        syncRunID: String?
    ) async -> (results: [CanonicalRecordingExistenceApplyResult], ioDurationMs: Int, mainActorLongTaskDurationMs: Int) {
        let writeQueue = backgroundWriteQueue
        return await withCheckedContinuation { continuation in
            writeQueue.async {
                let startedAt = Date()
                let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
                let bridge = CanonicalRecordingManifestApplyBridge(
                    configuration: configuration,
                    port: port
                )
                let results = bridge.apply(
                    recordings: recordings,
                    sourceDeviceID: sourceDeviceID,
                    syncRunID: syncRunID
                )
                let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
                continuation.resume(returning: (
                    results: results,
                    ioDurationMs: durationMs,
                    mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
                ))
            }
        }
    }

    private func applyRecordingExistenceBridgeSynchronouslyInBackground(
        configuration: CanonicalExistenceApplyRuntimeConfiguration,
        port: any MacCanonicalRecordingExistenceApplyPort,
        recordings: [LocalNetworkSyncRecordingEntry],
        sourceDeviceID: String,
        syncRunID: String?
    ) -> (results: [CanonicalRecordingExistenceApplyResult], ioDurationMs: Int, mainActorLongTaskDurationMs: Int) {
        backgroundWriteQueue.sync {
            let startedAt = Date()
            let startedOnMainActor = CanonicalInventoryRuntimeExecutionProbe.isMainThread()
            let bridge = CanonicalRecordingManifestApplyBridge(
                configuration: configuration,
                port: port
            )
            let results = bridge.apply(
                recordings: recordings,
                sourceDeviceID: sourceDeviceID,
                syncRunID: syncRunID
            )
            let durationMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            return (
                results: results,
                ioDurationMs: durationMs,
                mainActorLongTaskDurationMs: startedOnMainActor ? durationMs : 0
            )
        }
    }

    private func canonicalExistenceApplyConfigurationForApplyRuntime() -> CanonicalExistenceApplyRuntimeConfiguration {
        let mode: CanonicalExistenceApplyRuntimeMode
        switch canonicalApplyRuntimeConfiguration.mode {
        case .disabled:
            mode = .disabled
        case .diagnosticsOnly:
            mode = .diagnosticsOnly
        case .noCommit:
            mode = .noCommit
        case .testRootApply:
            mode = .testRootApply
        case .productionRootApplyWithLegacyFallback:
            mode = .productionRootApply
        case .blocked:
            mode = .blocked
        }
        return CanonicalExistenceApplyRuntimeConfiguration(
            mode: mode,
            policy: CanonicalExistenceApplyRuntimePolicy(
                debugInternalBuild: canonicalApplyRuntimeConfiguration.policy.debugInternalBuild,
                ownerApproved: canonicalApplyRuntimeConfiguration.policy.ownerApproved,
                releaseDefaultBuild: canonicalApplyRuntimeConfiguration.policy.releaseDefaultBuild,
                diagnosticsRedacted: canonicalApplyRuntimeConfiguration.policy.diagnosticsRedacted,
                legacyFallbackAvailable: canonicalApplyRuntimeConfiguration.policy.legacyFallbackAvailable,
                rootBoundRequired: true,
                rollbackRequired: true,
                atomicWriteRequired: true,
                postconditionRequired: true,
                writeAudioAllowed: false,
                markAudioAvailableAllowed: false
            )
        )
    }

    private func manifestRecordingsExistenceApplyConfiguration() -> CanonicalExistenceApplyRuntimeConfiguration {
        if canonicalExistenceApplyRuntimeConfiguration.canWriteMetadataOnlyRecord {
            return canonicalExistenceApplyRuntimeConfiguration
        }
        return .disabled
    }

    private func missingCanonicalExistenceApplyPortResults(
        recordings: [LocalNetworkSyncRecordingEntry],
        syncRunID: String?
    ) -> [CanonicalRecordingExistenceApplyResult] {
        recordings.map { recording in
            let hashPrefix = recording.metadataHash.map { String($0.prefix(12)) }
            let diagnostics = [
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalExistenceApplyBridgeBlocked,
                    syncRunID: syncRunID,
                    mode: .diagnosticsOnly,
                    objectID: recording.recordingID,
                    hashPrefix: hashPrefix,
                    count: recording.audioSize.map(Int.init),
                    detail: "portMissing"
                ),
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalManifestRecordingsApplyBlocked,
                    syncRunID: syncRunID,
                    mode: .diagnosticsOnly,
                    objectID: recording.recordingID,
                    detail: "portMissing"
                ),
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalExistenceManifestRecordingsIgnoredBlocked,
                    syncRunID: syncRunID,
                    mode: .diagnosticsOnly,
                    objectID: recording.recordingID,
                    detail: "portMissing"
                )
            ]
            return CanonicalRecordingExistenceApplyResult(
                objectID: recording.recordingID,
                action: .blocked,
                state: .unsupported,
                reason: "portMissing",
                metadataHashPrefix: hashPrefix,
                byteCount: recording.audioSize,
                didWriteAudio: false,
                didMarkAudioAvailable: false,
                checkpoint: nil,
                diagnostics: diagnostics
            )
        }
    }

    private func minimalCanonicalManifest(nodeID: String, platform: String) -> CanonicalManifest {
        CanonicalManifest.make(
            node: CanonicalNode(
                nodeID: nodeID,
                platform: platform,
                capabilities: [.recordingMetadata]
            ),
            objects: [],
            manifestCapabilities: [.recordingMetadata]
        )
    }

    private func mergeCanonicalRecordingExistenceLedger(
        into recordings: inout [LocalNetworkSyncRecordingEntry],
        syncRunID: String?
    ) {
        guard let canonicalRecordingExistenceApplyPort else {
            let diagnostic = CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalExistenceApplyBridgeBlocked,
                syncRunID: syncRunID,
                mode: .diagnosticsOnly,
                detail: "inventoryLedgerPortMissing"
            )
            recordCanonicalExistenceDiagnostics([diagnostic])
            return
        }
        do {
            let records = try canonicalRecordingExistenceApplyPort.loadRecords()
            guard !records.isEmpty else {
                return
            }
            let mergeResult = MacCanonicalRecordingExistenceInventoryMerger.merge(
                records: records,
                into: recordings,
                syncRunID: syncRunID
            )
            recordings = mergeResult.recordings
            recordCanonicalExistenceDiagnostics(mergeResult.diagnostics)
        } catch {
            let diagnostic = CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalExistenceApplyBridgeBlocked,
                syncRunID: syncRunID,
                mode: .diagnosticsOnly,
                detail: "inventoryLedgerReadFailed"
            )
            recordCanonicalExistenceDiagnostics([diagnostic])
        }
    }

    private func mergeCanonicalRecordingExistenceRecords(
        _ records: [CanonicalRecordingMetadataOnlyReceiveRecord],
        into recordings: inout [LocalNetworkSyncRecordingEntry],
        syncRunID: String?
    ) {
        guard !records.isEmpty else {
            return
        }
        let mergeResult = MacCanonicalRecordingExistenceInventoryMerger.merge(
            records: records,
            into: recordings,
            syncRunID: syncRunID
        )
        recordings = mergeResult.recordings
        recordCanonicalExistenceDiagnostics(mergeResult.diagnostics)
    }

    private func recordCanonicalExistenceDiagnostics(_ diagnostics: [CanonicalSyncRuntimeDiagnostic]) {
        for diagnostic in diagnostics where diagnostic.isRedacted {
            emitConnectionDiagnostic(
                phase: diagnostic.kind.rawValue,
                listenerState: "ready",
                activePort: activePort,
                syncRunID: diagnostic.syncRunID,
                errorMessage: diagnostic.summary()
            )
        }
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

    private static let syncJSONEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

enum CanonicalRecordingExistenceApplyAction: String, Codable, Equatable {
    case blocked
    case diagnosticsOnly
    case noCommit
    case written
    case updated
    case noOp
    case conflict
    case rollbackFailed
}

struct CanonicalRecordingMetadataOnlyReceiveRecord: Codable, Equatable, Identifiable {
    static let schemaVersion = 1

    var id: String { objectID }
    var schemaVersion: Int
    var objectID: String
    var sourceDeviceID: String
    var title: String?
    var createdAt: Date?
    var updatedAt: Date
    var metadataHash: String
    var declaredAudioHash: String?
    var declaredAudioByteSize: Int64?
    var audioAvailable: Bool
    var audioHash: String?
    var audioByteSize: Int64?
    var receiveStatus: String
    var processingStatus: String

    init(
        objectID: String,
        sourceDeviceID: String,
        title: String?,
        createdAt: Date?,
        updatedAt: Date,
        metadataHash: String,
        declaredAudioHash: String? = nil,
        declaredAudioByteSize: Int64? = nil
    ) {
        self.schemaVersion = Self.schemaVersion
        self.objectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.sourceDeviceID = sourceDeviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadataHash = metadataHash.trimmingCharacters(in: .whitespacesAndNewlines)
        self.declaredAudioHash = declaredAudioHash?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.declaredAudioByteSize = declaredAudioByteSize
        self.audioAvailable = false
        self.audioHash = nil
        self.audioByteSize = nil
        self.receiveStatus = "canonicalMetadataOnly"
        self.processingStatus = "awaitingAudio"
    }

    init?(manifestRecording recording: LocalNetworkSyncRecordingEntry, sourceDeviceID: String) {
        let objectID = recording.recordingID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !objectID.isEmpty,
              let metadataHash = recording.metadataHash?.trimmingCharacters(in: .whitespacesAndNewlines),
              !metadataHash.isEmpty else {
            return nil
        }
        self.init(
            objectID: objectID,
            sourceDeviceID: recording.sourceDeviceID ?? sourceDeviceID,
            title: recording.title,
            createdAt: recording.createdAt,
            updatedAt: recording.updatedAt,
            metadataHash: metadataHash,
            declaredAudioHash: recording.audioChecksum,
            declaredAudioByteSize: recording.audioSize
        )
    }

    var metadataHashPrefix: String {
        String(metadataHash.prefix(12))
    }
}

struct CanonicalRecordingExistenceRollbackCheckpoint: Codable, Equatable {
    var objectID: String
    var hadExistingRecord: Bool
    var previousRecordData: Data?
}

struct CanonicalRecordingExistenceApplyResult: Codable, Equatable {
    var objectID: String
    var action: CanonicalRecordingExistenceApplyAction
    var state: CanonicalRecordingExistenceState
    var reason: String
    var metadataHashPrefix: String?
    var byteCount: Int64?
    var didWriteAudio: Bool
    var didMarkAudioAvailable: Bool
    var checkpoint: CanonicalRecordingExistenceRollbackCheckpoint?
    var diagnostics: [CanonicalSyncRuntimeDiagnostic]
}

protocol MacCanonicalRecordingExistenceApplyPort {
    var rootURL: URL { get }

    func checkpoint(for objectID: String) throws -> CanonicalRecordingExistenceRollbackCheckpoint
    func readRecord(objectID: String) throws -> CanonicalRecordingMetadataOnlyReceiveRecord?
    func writeRecord(_ record: CanonicalRecordingMetadataOnlyReceiveRecord) throws
    func rollback(_ checkpoint: CanonicalRecordingExistenceRollbackCheckpoint) throws
    func loadRecords() throws -> [CanonicalRecordingMetadataOnlyReceiveRecord]
}

struct CanonicalRecordingManifestApplyBridge {
    var configuration: CanonicalExistenceApplyRuntimeConfiguration
    var port: any MacCanonicalRecordingExistenceApplyPort

    init(
        configuration: CanonicalExistenceApplyRuntimeConfiguration,
        port: any MacCanonicalRecordingExistenceApplyPort
    ) {
        self.configuration = configuration
        self.port = port
    }

    func apply(
        recordings: [LocalNetworkSyncRecordingEntry],
        sourceDeviceID: String,
        syncRunID: String? = nil
    ) -> [CanonicalRecordingExistenceApplyResult] {
        guard !recordings.isEmpty else {
            return []
        }

        return recordings.map { recording in
            guard let record = CanonicalRecordingMetadataOnlyReceiveRecord(
                manifestRecording: recording,
                sourceDeviceID: sourceDeviceID
            ) else {
                return result(
                    objectID: recording.recordingID,
                    action: .blocked,
                    state: .unsupported,
                    reason: "missingMetadataHash",
                    metadataHashPrefix: recording.metadataHash.map { String($0.prefix(12)) },
                    byteCount: recording.audioSize,
                    syncRunID: syncRunID
                )
            }

            guard recording.deleted == false,
                  recording.tombstone != true else {
                return result(
                    objectID: record.objectID,
                    action: .blocked,
                    state: .tombstoned,
                    reason: "tombstoned",
                    metadataHashPrefix: record.metadataHashPrefix,
                    byteCount: record.declaredAudioByteSize,
                    syncRunID: syncRunID
                )
            }

            switch configuration.mode {
            case .disabled, .blocked:
                return result(
                    objectID: record.objectID,
                    action: .blocked,
                    state: .metadataOnly,
                    reason: configuration.mode.rawValue,
                    metadataHashPrefix: record.metadataHashPrefix,
                    byteCount: record.declaredAudioByteSize,
                    syncRunID: syncRunID
                )
            case .diagnosticsOnly:
                return result(
                    objectID: record.objectID,
                    action: .diagnosticsOnly,
                    state: .metadataOnly,
                    reason: "wouldWriteMetadataOnly",
                    metadataHashPrefix: record.metadataHashPrefix,
                    byteCount: record.declaredAudioByteSize,
                    syncRunID: syncRunID
                )
            case .noCommit:
                return result(
                    objectID: record.objectID,
                    action: .noCommit,
                    state: .metadataOnly,
                    reason: "commitSuppressed",
                    metadataHashPrefix: record.metadataHashPrefix,
                    byteCount: record.declaredAudioByteSize,
                    syncRunID: syncRunID
                )
            case .metadataOnlyBridge, .testRootApply, .productionRootApply:
                guard configuration.canWriteMetadataOnlyRecord else {
                    return result(
                        objectID: record.objectID,
                        action: .blocked,
                        state: .metadataOnly,
                        reason: "policyBlocked",
                        metadataHashPrefix: record.metadataHashPrefix,
                        byteCount: record.declaredAudioByteSize,
                        syncRunID: syncRunID
                    )
                }
                return applyRecord(record, syncRunID: syncRunID)
            }
        }
    }

    private func applyRecord(
        _ record: CanonicalRecordingMetadataOnlyReceiveRecord,
        syncRunID: String?
    ) -> CanonicalRecordingExistenceApplyResult {
        do {
            let existingRecord = try port.readRecord(objectID: record.objectID)
            if let existing = existingRecord {
                if existing.audioAvailable {
                    let sameHash = existing.audioHash != nil
                        && existing.audioHash == record.declaredAudioHash
                    let sameSize = existing.audioByteSize != nil
                        && existing.audioByteSize == record.declaredAudioByteSize
                    return result(
                        objectID: record.objectID,
                        action: sameHash && sameSize ? .noOp : .conflict,
                        state: sameHash && sameSize ? .audioHashSizeMatched : .audioConflict,
                        reason: sameHash && sameSize ? "existingAudioSameHashSize" : "existingAudioConflict",
                        metadataHashPrefix: record.metadataHashPrefix,
                        byteCount: record.declaredAudioByteSize,
                        syncRunID: syncRunID
                    )
                }
                if existing.metadataHash == record.metadataHash {
                    return result(
                        objectID: record.objectID,
                        action: .noOp,
                        state: .metadataOnly,
                        reason: "sameMetadataOnlyRecord",
                        metadataHashPrefix: record.metadataHashPrefix,
                        byteCount: record.declaredAudioByteSize,
                        syncRunID: syncRunID
                    )
                }
            }

            let checkpoint = try port.checkpoint(for: record.objectID)
            do {
                try port.writeRecord(record)
                guard let postcondition = try port.readRecord(objectID: record.objectID),
                      postcondition.objectID == record.objectID,
                      postcondition.metadataHash == record.metadataHash,
                      postcondition.audioAvailable == false,
                      postcondition.audioHash == nil,
                      postcondition.audioByteSize == nil else {
                    try port.rollback(checkpoint)
                    return result(
                        objectID: record.objectID,
                        action: .blocked,
                        state: .unsupported,
                        reason: "postconditionFailedRolledBack",
                        metadataHashPrefix: record.metadataHashPrefix,
                        byteCount: record.declaredAudioByteSize,
                        syncRunID: syncRunID,
                        checkpoint: checkpoint
                    )
                }
                return result(
                    objectID: record.objectID,
                    action: existingRecord == nil ? .written : .updated,
                    state: .metadataOnly,
                    reason: existingRecord == nil ? "metadataOnlyRecordWritten" : "metadataOnlyRecordUpdated",
                    metadataHashPrefix: record.metadataHashPrefix,
                    byteCount: record.declaredAudioByteSize,
                    syncRunID: syncRunID,
                    checkpoint: checkpoint
                )
            } catch {
                do {
                    try port.rollback(checkpoint)
                    return result(
                        objectID: record.objectID,
                        action: .blocked,
                        state: .metadataOnly,
                        reason: "writeFailedRolledBack",
                        metadataHashPrefix: record.metadataHashPrefix,
                        byteCount: record.declaredAudioByteSize,
                        syncRunID: syncRunID,
                        checkpoint: checkpoint
                    )
                } catch {
                    return result(
                        objectID: record.objectID,
                        action: .rollbackFailed,
                        state: .unsupported,
                        reason: "rollbackFailed",
                        metadataHashPrefix: record.metadataHashPrefix,
                        byteCount: record.declaredAudioByteSize,
                        syncRunID: syncRunID,
                        checkpoint: checkpoint
                    )
                }
            }
        } catch {
            return result(
                objectID: record.objectID,
                action: .blocked,
                state: .unsupported,
                reason: "portFailed",
                metadataHashPrefix: record.metadataHashPrefix,
                byteCount: record.declaredAudioByteSize,
                syncRunID: syncRunID
            )
        }
    }

    private func result(
        objectID: String,
        action: CanonicalRecordingExistenceApplyAction,
        state: CanonicalRecordingExistenceState,
        reason: String,
        metadataHashPrefix: String?,
        byteCount: Int64?,
        syncRunID: String?,
        checkpoint: CanonicalRecordingExistenceRollbackCheckpoint? = nil
    ) -> CanonicalRecordingExistenceApplyResult {
        let mode = CanonicalSyncRuntimeMode.diagnosticsOnly
        var diagnostics = [
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalExistenceApplyBridgeEvaluated,
                syncRunID: syncRunID,
                mode: mode,
                objectID: objectID,
                actionKind: action.rawValue,
                hashPrefix: metadataHashPrefix,
                count: byteCount.map(Int.init),
                detail: "\(state.rawValue):\(reason)"
            ),
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalExistenceDidNotWriteAudio,
                syncRunID: syncRunID,
                mode: mode,
                objectID: objectID,
                actionKind: action.rawValue,
                detail: "true"
            ),
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalExistenceDidNotMarkAudioAvailable,
                syncRunID: syncRunID,
                mode: mode,
                objectID: objectID,
                actionKind: action.rawValue,
                detail: "true"
            ),
            CanonicalSyncRuntimeDiagnostic(
                kind: .canonicalExistenceDidNotMarkUploadCompleted,
                syncRunID: syncRunID,
                mode: mode,
                objectID: objectID,
                actionKind: action.rawValue,
                detail: "true"
            )
        ]
        switch action {
        case .written:
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceMetadataOnlyRecordWritten, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalRecordingExistenceMetadataOnlyWritten, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalManifestRecordingsApplyCompleted, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: "written"))
        case .updated:
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceMetadataOnlyRecordWritten, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalRecordingExistenceMetadataOnlyUpdated, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalManifestRecordingsApplyCompleted, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: "updated"))
        case .noOp:
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceMetadataOnlyRecordNoOp, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalRecordingExistenceMetadataOnlyNoOp, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            if state == .audioHashSizeMatched {
                diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalRecordingExistenceAudioSameNoOp, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            }
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalManifestRecordingsApplyNoOp, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
        case .blocked:
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceApplyBridgeBlocked, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: reason == "missingMetadataHash" ? .canonicalManifestRecordingsMalformedBlocked : .canonicalManifestRecordingsApplyBlocked, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceManifestRecordingsIgnoredBlocked, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: reason))
        case .conflict:
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceApplyBridgeBlocked, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalRecordingExistenceAudioConflictBlocked, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalManifestRecordingsApplyBlocked, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceManifestRecordingsIgnoredBlocked, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: reason))
        case .rollbackFailed:
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceApplyBridgeRollbackFailed, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalRecordingExistenceRollbackFailed, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: reason))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalManifestRecordingsApplyFailed, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: reason))
        case .diagnosticsOnly, .noCommit:
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceManifestRecordingsConsumed, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: action.rawValue))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalManifestRecordingsApplyNoOp, syncRunID: syncRunID, mode: mode, objectID: objectID, hashPrefix: metadataHashPrefix, count: byteCount.map(Int.init), detail: action.rawValue))
        }
        if checkpoint != nil, action == .written || action == .updated {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalRecordingExistenceRollbackStarted, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: "checkpointCreated"))
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalExistenceApplyBridgeRollbackCompleted, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: "checkpointCreated"))
        } else if checkpoint != nil, action == .blocked {
            diagnostics.append(CanonicalSyncRuntimeDiagnostic(kind: .canonicalRecordingExistenceRollbackCompleted, syncRunID: syncRunID, mode: mode, objectID: objectID, detail: reason))
        }
        return CanonicalRecordingExistenceApplyResult(
            objectID: objectID,
            action: action,
            state: state,
            reason: reason,
            metadataHashPrefix: metadataHashPrefix,
            byteCount: byteCount,
            didWriteAudio: false,
            didMarkAudioAvailable: false,
            checkpoint: checkpoint,
            diagnostics: diagnostics
        )
    }
}

final class MacCanonicalRecordingExistenceLedgerPort: MacCanonicalRecordingExistenceApplyPort {
    enum LedgerError: Error {
        case unsafeDestination
        case invalidObjectID
    }

    let rootURL: URL
    private let fileManager: FileManager
    private let recordsDirectoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    nonisolated init(fileManager: FileManager = .default, rootURL: URL) {
        self.fileManager = fileManager
        self.rootURL = rootURL.standardizedFileURL
        self.recordsDirectoryURL = self.rootURL
            .appendingPathComponent("sync", isDirectory: true)
            .appendingPathComponent("canonical-recording-existence", isDirectory: true)
            .appendingPathComponent("records", isDirectory: true)
            .standardizedFileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func checkpoint(for objectID: String) throws -> CanonicalRecordingExistenceRollbackCheckpoint {
        let url = try recordURL(for: objectID)
        let exists = fileManager.fileExists(atPath: url.path)
        return CanonicalRecordingExistenceRollbackCheckpoint(
            objectID: objectID,
            hadExistingRecord: exists,
            previousRecordData: exists ? try Data(contentsOf: url) : nil
        )
    }

    func readRecord(objectID: String) throws -> CanonicalRecordingMetadataOnlyReceiveRecord? {
        let url = try recordURL(for: objectID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return try decoder.decode(CanonicalRecordingMetadataOnlyReceiveRecord.self, from: Data(contentsOf: url))
    }

    func writeRecord(_ record: CanonicalRecordingMetadataOnlyReceiveRecord) throws {
        try ensureRecordsDirectory()
        let url = try recordURL(for: record.objectID)
        guard !record.audioAvailable,
              record.audioHash == nil,
              record.audioByteSize == nil else {
            throw LedgerError.unsafeDestination
        }
        try encoder.encode(record).write(to: url, options: .atomic)
    }

    func rollback(_ checkpoint: CanonicalRecordingExistenceRollbackCheckpoint) throws {
        let url = try recordURL(for: checkpoint.objectID)
        if checkpoint.hadExistingRecord {
            guard let data = checkpoint.previousRecordData else {
                throw LedgerError.unsafeDestination
            }
            try ensureRecordsDirectory()
            try data.write(to: url, options: .atomic)
        } else if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    nonisolated func loadRecords() throws -> [CanonicalRecordingMetadataOnlyReceiveRecord] {
        guard fileManager.fileExists(atPath: recordsDirectoryURL.path) else {
            return []
        }
        guard isInsideRoot(recordsDirectoryURL) else {
            throw LedgerError.unsafeDestination
        }
        return try fileManager.contentsOfDirectory(
            at: recordsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { url in
            guard isInsideRoot(url) else {
                return nil
            }
            return try? decoder.decode(CanonicalRecordingMetadataOnlyReceiveRecord.self, from: Data(contentsOf: url))
        }
        .sorted { $0.objectID.localizedStandardCompare($1.objectID) == .orderedAscending }
    }

    private func ensureRecordsDirectory() throws {
        guard isInsideRoot(recordsDirectoryURL) else {
            throw LedgerError.unsafeDestination
        }
        try fileManager.createDirectory(at: recordsDirectoryURL, withIntermediateDirectories: true)
    }

    private func recordURL(for objectID: String) throws -> URL {
        let sanitized = Self.sanitizedFileStem(objectID)
        guard !sanitized.isEmpty else {
            throw LedgerError.invalidObjectID
        }
        let url = recordsDirectoryURL.appendingPathComponent("\(sanitized).json", isDirectory: false).standardizedFileURL
        guard isInsideRoot(url) else {
            throw LedgerError.unsafeDestination
        }
        return url
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    private static func sanitizedFileStem(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .map { scalar -> Character in
                let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
                return allowed.contains(scalar) ? Character(String(scalar)) : "_"
            }
            .reduce(into: "") { $0.append($1) }
    }
}

struct MacCanonicalRecordingExistenceInventoryMergeResult {
    var recordings: [LocalNetworkSyncRecordingEntry]
    var diagnostics: [CanonicalSyncRuntimeDiagnostic]
}

enum MacCanonicalRecordingExistenceInventoryMerger {
    static func merge(
        records: [CanonicalRecordingMetadataOnlyReceiveRecord],
        into recordings: [LocalNetworkSyncRecordingEntry],
        syncRunID: String? = nil
    ) -> MacCanonicalRecordingExistenceInventoryMergeResult {
        var byID = Dictionary(recordings.map { ($0.recordingID, $0) }, uniquingKeysWith: { existing, _ in existing })
        var diagnostics: [CanonicalSyncRuntimeDiagnostic] = []
        let mode = CanonicalSyncRuntimeMode.diagnosticsOnly

        for record in records {
            if var existing = byID[record.objectID] {
                if existing.audioAvailable {
                    let sameHash = existing.audioChecksum != nil
                        && existing.audioChecksum == record.declaredAudioHash
                    let sameSize = existing.audioSize != nil
                        && existing.audioSize == record.declaredAudioByteSize
                    diagnostics.append(
                        CanonicalSyncRuntimeDiagnostic(
                            kind: sameHash && sameSize ? .canonicalExistenceAudioSameNoOp : .canonicalExistenceAudioConflict,
                            syncRunID: syncRunID,
                            mode: mode,
                            objectID: record.objectID,
                            hashPrefix: record.declaredAudioHash,
                            count: record.declaredAudioByteSize.map(Int.init),
                            detail: sameHash && sameSize ? "existingInboxAudioWins" : "existingInboxAudioDiverged"
                        )
                    )
                    diagnostics.append(
                        CanonicalSyncRuntimeDiagnostic(
                            kind: sameHash && sameSize ? .canonicalRecordingExistenceAudioSameNoOp : .canonicalRecordingExistenceInventoryConflict,
                            syncRunID: syncRunID,
                            mode: mode,
                            objectID: record.objectID,
                            hashPrefix: record.declaredAudioHash,
                            count: record.declaredAudioByteSize.map(Int.init),
                            detail: sameHash && sameSize ? "existingInboxAudioWins" : "existingInboxAudioDiverged"
                        )
                    )
                    continue
                }
                existing.metadataHash = existing.metadataHash ?? record.metadataHash
                existing.receiveStatus = existing.receiveStatus ?? record.receiveStatus
                existing.processingStatus = existing.processingStatus ?? record.processingStatus
                existing.audioAvailable = false
                existing.audioChecksum = nil
                existing.audioSize = nil
                existing.audioLogicalPathToken = nil
                existing.audioAvailability = nil
                byID[record.objectID] = existing
            } else {
                byID[record.objectID] = LocalNetworkSyncRecordingEntry(
                    recordingID: record.objectID,
                    metadataHash: record.metadataHash,
                    audioAvailable: false,
                    audioChecksum: nil,
                    audioSize: nil,
                    uploadLedgerState: nil,
                    receiveStatus: record.receiveStatus,
                    processingStatus: record.processingStatus,
                    updatedAt: record.updatedAt,
                    deleted: false,
                    title: record.title,
                    createdAt: record.createdAt,
                    tombstone: false,
                    audioAvailability: nil,
                    uploadStatus: nil,
                    transcriptionStatus: nil,
                    noteStatus: nil,
                    sourceDeviceID: record.sourceDeviceID,
                    artifactRefs: nil,
                    audioLogicalPathToken: nil
                )
            }
            diagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalExistenceManifestRecordingsConsumed,
                    syncRunID: syncRunID,
                    mode: mode,
                    objectID: record.objectID,
                    hashPrefix: record.metadataHashPrefix,
                    detail: "inventoryMetadataOnly"
                )
            )
            diagnostics.append(
                CanonicalSyncRuntimeDiagnostic(
                    kind: .canonicalRecordingExistenceInventoryMerged,
                    syncRunID: syncRunID,
                    mode: mode,
                    objectID: record.objectID,
                    hashPrefix: record.metadataHashPrefix,
                    detail: "metadataOnlyAudioUnavailable"
                )
            )
        }

        return MacCanonicalRecordingExistenceInventoryMergeResult(
            recordings: byID.values.sorted { $0.recordingID.localizedStandardCompare($1.recordingID) == .orderedAscending },
            diagnostics: diagnostics
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
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
