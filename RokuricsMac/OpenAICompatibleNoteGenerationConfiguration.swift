//
//  OpenAICompatibleNoteGenerationConfiguration.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

struct OpenAICompatibleNoteGenerationConfiguration: Codable, Equatable {
    var baseURLString: String
    var modelName: String
    var apiKey: String
    var temperature: Double
    var maxTokens: Int
    var maxTranscriptCharacters: Int

    init(
        baseURLString: String = "http://127.0.0.1:1234/v1",
        modelName: String = "google/gemma-4-e4b",
        apiKey: String = "",
        temperature: Double = 0.3,
        maxTokens: Int = 2_000,
        maxTranscriptCharacters: Int = 12_000
    ) {
        self.baseURLString = baseURLString
        self.modelName = modelName
        self.apiKey = apiKey
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

    var endpointDescription: String {
        URL(string: trimmedBaseURLString)?.host ?? trimmedBaseURLString
    }
}
