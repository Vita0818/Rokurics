//
//  OpenAICompatibleNoteGenerationClient.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

protocol OpenAICompatibleHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: OpenAICompatibleHTTPTransport {}

struct OpenAICompatibleModel: Codable, Equatable, Identifiable {
    let id: String
}

struct OpenAICompatibleMessage: Codable, Equatable {
    let role: String
    let content: String
}

struct OpenAICompatibleChatResult: Equatable {
    let content: String
    let finishReason: String?

    var isLengthLimited: Bool {
        finishReason == "length"
    }
}

struct OpenAICompatibleChatDiagnostics {
    let statusCode: Int?
    let bodyByteCount: Int
    let choicesCount: Int
    let finishReason: String?
    let messageContentWasPresent: Bool
    let contentLength: Int
    let reasoningContentWasPresent: Bool
    let reasoningContentLength: Int
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let reasoningTokens: Int?

    var summary: String {
        var fields: [String] = []

        if let statusCode {
            fields.append("status=\(statusCode)")
        }

        fields.append("bodyBytes=\(bodyByteCount)")
        fields.append("choices=\(choicesCount)")

        if let finishReason {
            fields.append("finish_reason=\(finishReason)")
        }

        fields.append("contentPresent=\(messageContentWasPresent)")
        fields.append("contentLength=\(contentLength)")
        fields.append("reasoningContentPresent=\(reasoningContentWasPresent)")
        fields.append("reasoningContentLength=\(reasoningContentLength)")

        if let promptTokens {
            fields.append("promptTokens=\(promptTokens)")
        }
        if let completionTokens {
            fields.append("completionTokens=\(completionTokens)")
        }
        if let totalTokens {
            fields.append("totalTokens=\(totalTokens)")
        }
        if let reasoningTokens {
            fields.append("reasoningTokens=\(reasoningTokens)")
        }

        return fields.joined(separator: ", ")
    }
}

enum OpenAICompatibleNoteGenerationClientError: LocalizedError {
    case invalidBaseURL
    case invalidEndpointURL
    case connectionUnavailable
    case timedOut
    case httpFailure(Int)
    case responseDecodeFailed
    case emptyModels
    case emptyContent(OpenAICompatibleChatDiagnostics)
    case reasoningContentWithoutFinalContent(OpenAICompatibleChatDiagnostics)
    case finalContentStoppedByLength(OpenAICompatibleChatDiagnostics)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Base URL 无效"
        case .invalidEndpointURL:
            return "OpenAI-compatible endpoint 无效"
        case .connectionUnavailable:
            return "无法连接本地 AI 服务，请确认 LM Studio Local Server 已启动"
        case .timedOut:
            return "请求超时"
        case .httpFailure(let statusCode):
            if statusCode == 400 || statusCode == 404 {
                return "模型名不可用，请确认 modelName 是否为 google/gemma-4-e4b 或 /models 返回的真实 id"
            }
            return "AI 服务请求失败：HTTP \(statusCode)"
        case .responseDecodeFailed:
            return "JSON 解析失败"
        case .emptyModels:
            return "模型列表为空"
        case .emptyContent(let diagnostics):
            return "模型返回为空：\(diagnostics.summary)。请增大 max_tokens 或确认模型最终内容输出设置。"
        case .reasoningContentWithoutFinalContent(let diagnostics):
            return "模型只返回了 reasoning_content，没有返回最终 content。请增大 max_tokens，或调整模型/提示词，确保模型输出最终答案。\(diagnostics.summary)"
        case .finalContentStoppedByLength(let diagnostics):
            return "模型输出在生成最终内容前达到长度限制。请增大 max_tokens。\(diagnostics.summary)"
        }
    }
}

struct OpenAICompatibleNoteGenerationClient {
    private let transport: any OpenAICompatibleHTTPTransport
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    init(
        transport: any OpenAICompatibleHTTPTransport = URLSession.shared,
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder()
    ) {
        self.transport = transport
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
    }

    func models(
        configuration: OpenAICompatibleNoteGenerationConfiguration,
        timeout: TimeInterval = 10
    ) async throws -> [OpenAICompatibleModel] {
        let request = try makeRequest(
            path: "models",
            method: "GET",
            configuration: configuration,
            timeout: timeout,
            body: nil
        )
        let responseData = try await data(for: request)

        do {
            let response = try jsonDecoder.decode(ModelsResponse.self, from: responseData.data)
            guard !response.data.isEmpty else {
                throw OpenAICompatibleNoteGenerationClientError.emptyModels
            }
            return response.data
        } catch let error as OpenAICompatibleNoteGenerationClientError {
            throw error
        } catch {
            throw OpenAICompatibleNoteGenerationClientError.responseDecodeFailed
        }
    }

    func chatCompletion(
        configuration: OpenAICompatibleNoteGenerationConfiguration,
        messages: [OpenAICompatibleMessage],
        timeout: TimeInterval,
        maxTokens: Int? = nil,
        temperature: Double? = nil
    ) async throws -> OpenAICompatibleChatResult {
        let body = ChatCompletionRequest(
            model: configuration.trimmedModelName,
            messages: messages,
            temperature: temperature ?? configuration.temperature,
            maxTokens: maxTokens ?? configuration.maxTokens,
            stream: false
        )
        let encodedBody = try jsonEncoder.encode(body)
        let request = try makeRequest(
            path: "chat/completions",
            method: "POST",
            configuration: configuration,
            timeout: timeout,
            body: encodedBody
        )
        let response = try await data(for: request)
        return try Self.parseChatCompletion(
            data: response.data,
            statusCode: response.statusCode,
            decoder: jsonDecoder
        )
    }

    func makeRequest(
        path: String,
        method: String,
        configuration: OpenAICompatibleNoteGenerationConfiguration,
        timeout: TimeInterval,
        body: Data?
    ) throws -> URLRequest {
        let url = try Self.endpointURL(baseURLString: configuration.baseURLString, path: path)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let apiKey = configuration.trimmedAPIKey
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    static func endpointURL(baseURLString: String, path: String) throws -> URL {
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty,
              let baseURL = URL(string: trimmedBaseURL),
              baseURL.scheme == "http" || baseURL.scheme == "https" else {
            throw OpenAICompatibleNoteGenerationClientError.invalidBaseURL
        }

        let normalizedBaseURL = trimmedBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(normalizedBaseURL)/\(normalizedPath)") else {
            throw OpenAICompatibleNoteGenerationClientError.invalidEndpointURL
        }

        return url
    }

    static func parseChatCompletion(
        data: Data,
        statusCode: Int? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> OpenAICompatibleChatResult {
        do {
            let response = try decoder.decode(ChatCompletionResponse.self, from: data)
            let firstChoice = response.choices.first
            let content = firstChoice?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reasoningContent = firstChoice?.message.reasoningContent?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let diagnostics = OpenAICompatibleChatDiagnostics(
                statusCode: statusCode,
                bodyByteCount: data.count,
                choicesCount: response.choices.count,
                finishReason: firstChoice?.finishReason,
                messageContentWasPresent: firstChoice?.message.content != nil,
                contentLength: content.count,
                reasoningContentWasPresent: firstChoice?.message.reasoningContent != nil,
                reasoningContentLength: reasoningContent.count,
                promptTokens: response.usage?.promptTokens,
                completionTokens: response.usage?.completionTokens,
                totalTokens: response.usage?.totalTokens,
                reasoningTokens: response.usage?.completionTokensDetails?.reasoningTokens
            )

            guard firstChoice != nil else {
                throw OpenAICompatibleNoteGenerationClientError.emptyContent(diagnostics)
            }

            guard !content.isEmpty else {
                if firstChoice?.finishReason == "length" {
                    throw OpenAICompatibleNoteGenerationClientError.finalContentStoppedByLength(diagnostics)
                }

                if !reasoningContent.isEmpty {
                    throw OpenAICompatibleNoteGenerationClientError.reasoningContentWithoutFinalContent(diagnostics)
                }

                throw OpenAICompatibleNoteGenerationClientError.emptyContent(diagnostics)
            }

            return OpenAICompatibleChatResult(
                content: content,
                finishReason: firstChoice?.finishReason
            )
        } catch let error as OpenAICompatibleNoteGenerationClientError {
            throw error
        } catch {
            throw OpenAICompatibleNoteGenerationClientError.responseDecodeFailed
        }
    }

    private func data(for request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        do {
            let (data, response) = try await transport.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAICompatibleNoteGenerationClientError.connectionUnavailable
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw OpenAICompatibleNoteGenerationClientError.httpFailure(httpResponse.statusCode)
            }

            return (data, httpResponse.statusCode)
        } catch let error as OpenAICompatibleNoteGenerationClientError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw OpenAICompatibleNoteGenerationClientError.timedOut
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                throw OpenAICompatibleNoteGenerationClientError.connectionUnavailable
            default:
                throw OpenAICompatibleNoteGenerationClientError.connectionUnavailable
            }
        } catch {
            throw OpenAICompatibleNoteGenerationClientError.connectionUnavailable
        }
    }

    private struct ModelsResponse: Codable {
        let data: [OpenAICompatibleModel]
    }

    private struct ChatCompletionRequest: Codable {
        let model: String
        let messages: [OpenAICompatibleMessage]
        let temperature: Double
        let maxTokens: Int
        let stream: Bool

        private enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
            case stream
        }
    }

    private struct ChatCompletionResponse: Codable {
        let choices: [Choice]
        let usage: Usage?

        struct Choice: Codable {
            let message: Message
            let finishReason: String?

            private enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        struct Message: Codable {
            let content: String?
            let reasoningContent: String?

            private enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        struct Usage: Codable {
            let promptTokens: Int?
            let completionTokens: Int?
            let totalTokens: Int?
            let completionTokensDetails: CompletionTokensDetails?

            private enum CodingKeys: String, CodingKey {
                case promptTokens = "prompt_tokens"
                case completionTokens = "completion_tokens"
                case totalTokens = "total_tokens"
                case completionTokensDetails = "completion_tokens_details"
            }
        }

        struct CompletionTokensDetails: Codable {
            let reasoningTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }
    }
}
