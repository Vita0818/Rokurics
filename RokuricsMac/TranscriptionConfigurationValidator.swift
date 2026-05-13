//
//  TranscriptionConfigurationValidator.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct TranscriptionConfigurationValidator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validateWhisperCpp(_ configuration: WhisperCppTranscriptionConfiguration) async -> ValidationResult {
        do {
            let provider = WhisperCppTranscriptionProvider(configuration: configuration, fileManager: fileManager)
            try await provider.validateConfiguration()
            return ValidationResult(status: .valid, message: "配置有效")
        } catch {
            let status = status(for: error)
            return ValidationResult(status: status, message: error.localizedDescription)
        }
    }

    private func status(for error: Error) -> TranscriptionConfigurationValidationStatus {
        guard let transcriptionError = error as? TranscriptionError else {
            return .checkFailed
        }

        switch transcriptionError {
        case .executablePathMissing, .modelPathMissing, .providerNotConfigured:
            return .notConfigured
        case .executableNotFound:
            return .executableNotFound
        case .executableIsDirectory:
            return .executableIsDirectory
        case .executableNotExecutable:
            return .executableNotExecutable
        case .modelNotFound:
            return .modelNotFound
        case .modelIsDirectory:
            return .modelIsDirectory
        case .outputDirectoryNotWritable, .outputDirectoryUnavailable:
            return .outputDirectoryNotWritable
        default:
            return .checkFailed
        }
    }

    struct ValidationResult {
        let status: TranscriptionConfigurationValidationStatus
        let message: String
    }
}

