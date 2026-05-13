//
//  TranscriptionProviderKind.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

enum TranscriptionProviderKind: String, Codable, CaseIterable, Identifiable {
    case mock
    case whisperCpp
    case mlxWhisper
    case localHTTP
    case cloudAPI
    case customCommand

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mock:
            return "Mock Transcription"
        case .whisperCpp:
            return "whisper.cpp"
        case .mlxWhisper:
            return "mlx-whisper"
        case .localHTTP:
            return "Local HTTP"
        case .cloudAPI:
            return "Cloud API"
        case .customCommand:
            return "Custom Command"
        }
    }

    var isEnabledInCurrentBuild: Bool {
        switch self {
        case .mock, .whisperCpp:
            return true
        case .mlxWhisper, .localHTTP, .cloudAPI, .customCommand:
            return false
        }
    }
}

