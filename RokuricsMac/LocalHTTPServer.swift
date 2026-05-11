//
//  LocalHTTPServer.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/10.
//

import Foundation
import Network

final class LocalHTTPServer {
    typealias ReceivedHandler = @Sendable (ReceivedFileRecord) -> Void
    typealias ErrorHandler = @Sendable (String) -> Void
    typealias RunningStateHandler = @Sendable (Bool) -> Void

    private struct HTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private enum HTTPParseError: Error {
        case badRequest
    }

    private let port: Int
    private let store: ReceivedFileStore
    private let onReceived: ReceivedHandler
    private let onError: ErrorHandler
    private let onRunningStateChanged: RunningStateHandler
    private let queue = DispatchQueue(label: "RokuricsMac.LocalHTTPServer")
    private let maxBodyBytes = 512 * 1024
    private let maxHeaderBytes = 16 * 1024

    private var listener: NWListener?

    init(
        port: Int,
        store: ReceivedFileStore,
        onReceived: @escaping ReceivedHandler,
        onError: @escaping ErrorHandler,
        onRunningStateChanged: @escaping RunningStateHandler
    ) {
        self.port = port
        self.store = store
        self.onReceived = onReceived
        self.onError = onError
        self.onRunningStateChanged = onRunningStateChanged
    }

    func start() throws {
        guard listener == nil else {
            return
        }

        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw HTTPParseError.badRequest
        }

        let listener = try NWListener(using: .tcp, on: endpointPort)
        listener.stateUpdateHandler = { [weak self] state in
            self?.handleListenerState(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        onRunningStateChanged(false)
        print("[RokuricsMacReceiver] server stopped")
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("[RokuricsMacReceiver] listening on port \(port)")
            onRunningStateChanged(true)
        case .failed(let error):
            let message = "listener failed: \(error)"
            print("[RokuricsMacReceiver] errors: \(message)")
            onError(message)
            onRunningStateChanged(false)
            listener?.cancel()
            listener = nil
        case .cancelled:
            onRunningStateChanged(false)
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        print("[RokuricsMacReceiver] connection received")
        connection.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[RokuricsMacReceiver] errors: connection failed: \(error)")
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                let message = "receive failed: \(error)"
                print("[RokuricsMacReceiver] errors: \(message)")
                self.onError(message)
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let chunk {
                nextBuffer.append(chunk)
            }

            do {
                if let request = try self.parseRequest(from: nextBuffer) {
                    self.handleRequest(request, on: connection)
                    return
                }

                if nextBuffer.count > self.maxHeaderBytes + self.maxBodyBytes {
                    throw HTTPParseError.badRequest
                }

                if isComplete {
                    self.sendBadRequest(on: connection)
                    return
                }

                self.receiveRequest(on: connection, buffer: nextBuffer)
            } catch {
                print("[RokuricsMacReceiver] errors: bad request: \(error)")
                self.sendBadRequest(on: connection)
            }
        }
    }

    private func parseRequest(from buffer: Data) throws -> HTTPRequest? {
        let headerSeparator = Data([13, 10, 13, 10])
        guard let headerRange = buffer.range(of: headerSeparator) else {
            if buffer.count > maxHeaderBytes {
                throw HTTPParseError.badRequest
            }

            return nil
        }

        let headerData = buffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw HTTPParseError.badRequest
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw HTTPParseError.badRequest
        }

        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            throw HTTPParseError.badRequest
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        guard
            let contentLengthValue = headers["content-length"],
            let contentLength = Int(contentLengthValue),
            contentLength >= 0,
            contentLength <= maxBodyBytes
        else {
            throw HTTPParseError.badRequest
        }

        let bodyStart = headerRange.upperBound
        let bodyBytesAvailable = buffer.distance(from: bodyStart, to: buffer.endIndex)
        guard bodyBytesAvailable >= contentLength else {
            return nil
        }

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = Data(buffer[bodyStart..<bodyEnd])

        print("[RokuricsMacReceiver] request method/path: \(requestParts[0]) \(requestParts[1])")
        print("[RokuricsMacReceiver] content length: \(contentLength)")

        return HTTPRequest(method: requestParts[0], path: requestParts[1], headers: headers, body: body)
    }

    private func handleRequest(_ request: HTTPRequest, on connection: NWConnection) {
        guard request.method == "POST", request.path == "/upload-test" else {
            sendBadRequest(on: connection)
            return
        }

        do {
            let record = try store.saveTestUpload(
                body: request.body,
                requestedFileName: request.headers["x-rokurics-filename"]
            )
            onReceived(record)
            sendOK(fileName: record.fileName, on: connection)
        } catch {
            let message = "save failed: \(error)"
            print("[RokuricsMacReceiver] errors: \(message)")
            onError(message)
            sendBadRequest(on: connection)
        }
    }

    private func sendOK(fileName: String, on connection: NWConnection) {
        let escapedFileName = fileName.jsonEscaped
        let body = """
        {"ok":true,"message":"received","fileName":"\(escapedFileName)"}
        """
        sendResponse(statusCode: 200, reason: "OK", body: body, on: connection)
    }

    private func sendBadRequest(on connection: NWConnection) {
        let body = """
        {"ok":false,"error":"bad_request"}
        """
        sendResponse(statusCode: 400, reason: "Bad Request", body: body, on: connection)
    }

    private func sendResponse(statusCode: Int, reason: String, body: String, on connection: NWConnection) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(statusCode) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var responseData = Data(header.utf8)
        responseData.append(bodyData)

        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error {
                print("[RokuricsMacReceiver] errors: response failed: \(error)")
            } else {
                print("[RokuricsMacReceiver] response sent")
            }

            connection.cancel()
        })
    }
}

private extension String {
    var jsonEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}
