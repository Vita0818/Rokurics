//
//  TranscriptionProviderConfiguration.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct TranscriptionProviderConfiguration: Codable, Equatable {
    let providerID: String
    let displayName: String
    var modelName: String?
    var language: String?
    var prompt: String?
    var executablePath: String?
    var modelPath: String?
    var endpointURLString: String?

    static let mock = TranscriptionProviderConfiguration(
        providerID: "mock",
        displayName: "Mock Transcription",
        modelName: "mock-local",
        language: "auto",
        prompt: nil,
        executablePath: nil,
        modelPath: nil,
        endpointURLString: nil
    )
}
