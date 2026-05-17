//
//  AnthropicMessagesNoteGenerationClient.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

protocol AnthropicMessagesHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: AnthropicMessagesHTTPTransport {}

struct AnthropicModel: Codable, Equatable, Identifiable {
    let id: String
}

struct AnthropicMessageResult: Equatable {
    let content: String
    let stopReason: String?

    var isLengthLimited: Bool {
        stopReason == "max_tokens"
    }
}

struct AnthropicMessagesDiagnostics {
    let statusCode: Int?
    let bodyByteCount: Int
    let contentBlockCount: Int
    let textLength: Int
    let stopReason: String?
    let inputTokens: Int?
    let outputTokens: Int?

    var summary: String {
        var fields: [String] = []
        if let statusCode {
            fields.append("status=\(statusCode)")
        }
        fields.append("bodyBytes=\(bodyByteCount)")
        fields.append("contentBlocks=\(contentBlockCount)")
        fields.append("textLength=\(textLength)")
        if let stopReason {
            fields.append("stop_reason=\(stopReason)")
        }
        if let inputTokens {
            fields.append("inputTokens=\(inputTokens)")
        }
        if let outputTokens {
            fields.append("outputTokens=\(outputTokens)")
        }
        return fields.joined(separator: ", ")
    }
}

enum AnthropicMessagesClientError: LocalizedError {
    case invalidBaseURL
    case invalidEndpointURL
    case apiKeyMissing
    case anthropicVersionMissing
    case connectionUnavailable
    case timedOut
    case httpFailure(Int)
    case responseDecodeFailed
    case emptyModels
    case emptyContent(AnthropicMessagesDiagnostics)
    case finalContentStoppedByMaxTokens(AnthropicMessagesDiagnostics)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Claude Base URL 无效"
        case .invalidEndpointURL:
            return "Claude endpoint 无效"
        case .apiKeyMissing:
            return "Claude API Key 为空"
        case .anthropicVersionMissing:
            return "Anthropic Version 为空"
        case .connectionUnavailable:
            return "无法连接 Claude API"
        case .timedOut:
            return "Claude 请求超时"
        case .httpFailure(let statusCode):
            return "Claude API 请求失败：HTTP \(statusCode)"
        case .responseDecodeFailed:
            return "Claude JSON 解析失败"
        case .emptyModels:
            return "未读取到 Claude 模型"
        case .emptyContent(let diagnostics):
            return "Claude 返回内容为空：\(diagnostics.summary)"
        case .finalContentStoppedByMaxTokens(let diagnostics):
            return "Claude 输出在生成最终内容前达到长度限制。请增大 max_tokens。\(diagnostics.summary)"
        }
    }
}

struct AnthropicMessagesNoteGenerationClient {
    private let transport: any AnthropicMessagesHTTPTransport
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(
        transport: any AnthropicMessagesHTTPTransport = URLSession.shared,
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.transport = transport
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
    }

    func models(
        configuration: AnthropicMessagesConfiguration,
        timeout: TimeInterval = 10
    ) async throws -> [AnthropicModel] {
        let request = try makeRequest(
            path: "v1/models",
            method: "GET",
            configuration: configuration,
            timeout: timeout,
            body: nil
        )
        let responseData = try await data(for: request)

        do {
            let response = try jsonDecoder.decode(ModelsResponse.self, from: responseData.data)
            guard !response.data.isEmpty else {
                throw AnthropicMessagesClientError.emptyModels
            }
            return response.data
        } catch let error as AnthropicMessagesClientError {
            throw error
        } catch {
            throw AnthropicMessagesClientError.responseDecodeFailed
        }
    }

    func message(
        configuration: AnthropicMessagesConfiguration,
        system: String,
        userContent: String,
        timeout: TimeInterval,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> AnthropicMessageResult {
        let body = MessageRequest(
            model: configuration.trimmedModelName,
            maxTokens: maxTokens ?? configuration.maxTokens,
            temperature: temperature ?? configuration.temperature,
            system: system,
            messages: [
                RequestMessage(role: "user", content: userContent)
            ]
        )
        let encodedBody = try jsonEncoder.encode(body)
        let request = try makeRequest(
            path: "v1/messages",
            method: "POST",
            configuration: configuration,
            timeout: timeout,
            body: encodedBody
        )
        let response = try await data(for: request)
        return try Self.parseMessage(
            data: response.data,
            statusCode: response.statusCode,
            decoder: jsonDecoder
        )
    }

    func makeRequest(
        path: String,
        method: String,
        configuration: AnthropicMessagesConfiguration,
        timeout: TimeInterval,
        body: Data?
    ) throws -> URLRequest {
        let apiKey = configuration.trimmedAPIKey
        guard !apiKey.isEmpty else {
            throw AnthropicMessagesClientError.apiKeyMissing
        }

        let anthropicVersion = configuration.trimmedAnthropicVersion
        guard !anthropicVersion.isEmpty else {
            throw AnthropicMessagesClientError.anthropicVersionMissing
        }

        let url = try Self.endpointURL(baseURLString: configuration.baseURLString, path: path)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    static func endpointURL(baseURLString: String, path: String) throws -> URL {
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty,
              let baseURL = URL(string: trimmedBaseURL),
              baseURL.scheme == "http" || baseURL.scheme == "https" else {
            throw AnthropicMessagesClientError.invalidBaseURL
        }

        let normalizedBaseURL = trimmedBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "v1",
           normalizedPath.hasPrefix("v1/") {
            normalizedPath = String(normalizedPath.dropFirst("v1/".count))
        }

        guard let url = URL(string: "\(normalizedBaseURL)/\(normalizedPath)") else {
            throw AnthropicMessagesClientError.invalidEndpointURL
        }

        return url
    }

    static func parseMessage(
        data: Data,
        statusCode: Int? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> AnthropicMessageResult {
        do {
            let response = try decoder.decode(MessageResponse.self, from: data)
            let text = response.content
                .filter { $0.type == "text" }
                .compactMap(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let diagnostics = AnthropicMessagesDiagnostics(
                statusCode: statusCode,
                bodyByteCount: data.count,
                contentBlockCount: response.content.count,
                textLength: text.count,
                stopReason: response.stopReason,
                inputTokens: response.usage?.inputTokens,
                outputTokens: response.usage?.outputTokens
            )

            guard !text.isEmpty else {
                if response.stopReason == "max_tokens" {
                    throw AnthropicMessagesClientError.finalContentStoppedByMaxTokens(diagnostics)
                }
                throw AnthropicMessagesClientError.emptyContent(diagnostics)
            }

            return AnthropicMessageResult(
                content: text,
                stopReason: response.stopReason
            )
        } catch let error as AnthropicMessagesClientError {
            throw error
        } catch {
            throw AnthropicMessagesClientError.responseDecodeFailed
        }
    }

    private func data(for request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        do {
            let (data, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AnthropicMessagesClientError.connectionUnavailable
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw AnthropicMessagesClientError.httpFailure(httpResponse.statusCode)
            }

            return (data, httpResponse.statusCode)
        } catch let error as AnthropicMessagesClientError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw AnthropicMessagesClientError.timedOut
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                throw AnthropicMessagesClientError.connectionUnavailable
            default:
                throw AnthropicMessagesClientError.connectionUnavailable
            }
        } catch {
            throw AnthropicMessagesClientError.connectionUnavailable
        }
    }

    private struct ModelsResponse: Codable {
        let data: [AnthropicModel]
    }

    private struct MessageRequest: Codable {
        let model: String
        let maxTokens: Int
        let temperature: Double
        let system: String
        let messages: [RequestMessage]

        private enum CodingKeys: String, CodingKey {
            case model
            case maxTokens = "max_tokens"
            case temperature
            case system
            case messages
        }
    }

    private struct RequestMessage: Codable, Equatable {
        let role: String
        let content: String
    }

    private struct MessageResponse: Codable {
        let content: [ContentBlock]
        let stopReason: String?
        let usage: Usage?

        private enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
            case usage
        }

        struct ContentBlock: Codable {
            let type: String
            let text: String?
        }

        struct Usage: Codable {
            let inputTokens: Int?
            let outputTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
            }
        }
    }
}
