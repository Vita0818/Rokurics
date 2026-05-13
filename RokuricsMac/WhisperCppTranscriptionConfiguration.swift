//
//  WhisperCppTranscriptionConfiguration.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct WhisperCppTranscriptionConfiguration: Codable, Equatable {
    var executablePath: String
    var modelPath: String
    var defaultLanguage: String
    var preferSegmentOutput: Bool

    static let `default` = WhisperCppTranscriptionConfiguration(
        executablePath: "",
        modelPath: "",
        defaultLanguage: "auto",
        preferSegmentOutput: false
    )

    var normalizedExecutablePath: String {
        executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedModelPath: String {
        modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedLanguage: String {
        let value = defaultLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "auto" : value
    }

    var modelFileName: String? {
        let path = normalizedModelPath
        guard !path.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: path).lastPathComponent
    }
}

