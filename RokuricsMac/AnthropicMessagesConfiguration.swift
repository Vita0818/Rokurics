//
//  AnthropicMessagesConfiguration.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct AnthropicMessagesConfiguration: Codable, Equatable {
    var baseURLString: String
    var modelName: String
    var apiKey: String
    var anthropicVersion: String
    var temperature: Double
    var maxTokens: Int
    var maxTranscriptCharacters: Int

    init(
        baseURLString: String = "https://api.anthropic.com",
        modelName: String = "claude-sonnet-4-6",
        apiKey: String = "",
        anthropicVersion: String = "2023-06-01",
        temperature: Double = 0.3,
        maxTokens: Int = 2_000,
        maxTranscriptCharacters: Int = 12_000
    ) {
        self.baseURLString = baseURLString
        self.modelName = modelName
        self.apiKey = apiKey
        self.anthropicVersion = anthropicVersion
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.maxTranscriptCharacters = maxTranscriptCharacters
    }

    var trimmedBaseURLString: String {
        baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModelName: String {
        modelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAnthropicVersion: String {
        anthropicVersion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var endpointDescription: String {
        URL(string: trimmedBaseURLString)?.host ?? trimmedBaseURLString
    }

    static let defaultModelCandidates = [
        "claude-sonnet-4-6",
        "claude-haiku-4-5",
        "claude-opus-4-7"
    ]
}
