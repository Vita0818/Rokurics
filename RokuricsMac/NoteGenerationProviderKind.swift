//
//  NoteGenerationProviderKind.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/17.
//

import Foundation

enum NoteGenerationProviderKind: String, CaseIterable, Codable, Identifiable {
    case mock
    case openAICompatible
    case anthropicMessages

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mock:
            return "Mock"
        case .openAICompatible:
            return "OpenAI-compatible"
        case .anthropicMessages:
            return "Claude / Anthropic"
        }
    }
}

enum AIProviderPreset: String, CaseIterable, Codable, Identifiable {
    case customOpenAICompatible
    case lmStudioLocal
    case deepSeek
    case openAI
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .customOpenAICompatible:
            return "Custom"
        case .lmStudioLocal:
            return "LM Studio"
        case .deepSeek:
            return "DeepSeek"
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }

    var defaultBaseURLString: String {
        switch self {
        case .customOpenAICompatible, .lmStudioLocal:
            return "http://127.0.0.1:1234/v1"
        case .deepSeek:
            return "https://api.deepseek.com"
        case .openAI:
            return "https://api.openai.com/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai"
        }
    }

    var defaultModelCandidates: [String] {
        switch self {
        case .customOpenAICompatible:
            return []
        case .lmStudioLocal:
            return ["google/gemma-4-e4b"]
        case .deepSeek:
            return ["deepseek-v4-flash", "deepseek-v4-pro"]
        case .openAI:
            return ["gpt-5.5", "gpt-5.5-mini", "gpt-5.5-nano"]
        case .gemini:
            return ["gemini-3-flash-preview"]
        }
    }

    var supportsModelRefresh: Bool {
        switch self {
        case .gemini:
            return false
        case .customOpenAICompatible, .lmStudioLocal, .deepSeek, .openAI:
            return true
        }
    }

    func applyingDefaults(to configuration: OpenAICompatibleNoteGenerationConfiguration) -> OpenAICompatibleNoteGenerationConfiguration {
        let currentBaseURL = configuration.trimmedBaseURLString
        let currentModelName = configuration.trimmedModelName

        if self == .customOpenAICompatible {
            return OpenAICompatibleNoteGenerationConfiguration(
                baseURLString: currentBaseURL.isEmpty ? defaultBaseURLString : currentBaseURL,
                modelName: currentModelName,
                apiKey: configuration.trimmedAPIKey,
                temperature: configuration.temperature,
                maxTokens: configuration.maxTokens,
                maxTranscriptCharacters: configuration.maxTranscriptCharacters
            )
        }

        return OpenAICompatibleNoteGenerationConfiguration(
            baseURLString: defaultBaseURLString,
            modelName: defaultModelCandidates.first ?? currentModelName,
            apiKey: configuration.trimmedAPIKey,
            temperature: configuration.temperature,
            maxTokens: configuration.maxTokens,
            maxTranscriptCharacters: configuration.maxTranscriptCharacters
        )
    }

    static func inferred(from baseURLString: String) -> AIProviderPreset {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return .customOpenAICompatible
        }

        if (host == "127.0.0.1" || host == "localhost"), url.port == 1234 {
            return .lmStudioLocal
        }
        if host == "api.deepseek.com" {
            return .deepSeek
        }
        if host == "api.openai.com" {
            return .openAI
        }
        if host == "generativelanguage.googleapis.com" {
            return .gemini
        }

        return .customOpenAICompatible
    }
}
