//
//  TranscriptionConfigurationValidator.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct TranscriptionConfigurationValidator {
    private let fileManager: FileManager
    private let securityScopedEnvironment: SecurityScopedFileAccessEnvironment
    private let runtimeResolver: (any WhisperCppRuntimeResolving)?

    init(
        fileManager: FileManager = .default,
        securityScopedEnvironment: SecurityScopedFileAccessEnvironment = .live,
        runtimeResolver: (any WhisperCppRuntimeResolving)? = nil
    ) {
        self.fileManager = fileManager
        self.securityScopedEnvironment = securityScopedEnvironment
        self.runtimeResolver = runtimeResolver
    }

    func validateWhisperCpp(_ configuration: WhisperCppTranscriptionConfiguration) async -> ValidationResult {
        debugLogInputConfiguration(configuration)

        do {
            let provider = WhisperCppTranscriptionProvider(
                configuration: configuration,
                fileManager: fileManager,
                securityScopedEnvironment: securityScopedEnvironment,
                runtimeResolver: runtimeResolver
            )
            try await provider.validateConfiguration()
            return ValidationResult(status: .valid, message: RokuricsCopy.text("配置有效", "Valid"))
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
        case .executablePathMissing, .modelPathMissing, .ffmpegPathMissing, .providerNotConfigured:
            return .notConfigured
        case .executableNotFound:
            return .executableNotFound
        case .executableIsDirectory:
            return .executableIsDirectory
        case .executableNotExecutable:
            return .executableNotExecutable
        case .executableBookmarkMissing,
             .executableBookmarkRestoreFailed,
             .executableBookmarkStale,
             .executableSandboxAccessDenied:
            return .executableAccessDenied
        case .executableEntitlementMissing:
            return .executableEntitlementMissing
        case .bookmarkEntitlementMissing:
            return .bookmarkEntitlementMissing
        case .modelNotFound:
            return .modelNotFound
        case .modelIsDirectory:
            return .modelIsDirectory
        case .modelBookmarkMissing,
             .modelBookmarkRestoreFailed,
             .modelBookmarkStale,
             .modelSandboxAccessDenied:
            return .modelAccessDenied
        case .whisperCppRootDirectoryPathMissing,
             .whisperCppRootDirectoryBookmarkMissing,
             .whisperCppRootDirectoryBookmarkRestoreFailed,
             .whisperCppRootDirectoryBookmarkStale,
             .whisperCppRootDirectorySandboxAccessDenied,
             .whisperCppRootDirectoryAccessFailed(_):
            return .whisperCppRootDirectoryAccessDenied
        case .whisperCppRootDirectoryNotFound:
            return .whisperCppRootDirectoryNotFound
        case .whisperCppRootDirectoryIsFile:
            return .whisperCppRootDirectoryIsFile
        case .whisperCppRootDirectoryInvalid(_):
            return .whisperCppRootDirectoryInvalid
        case .ffmpegNotFound:
            return .ffmpegNotFound
        case .ffmpegIsDirectory:
            return .ffmpegIsDirectory
        case .ffmpegNotExecutable:
            return .ffmpegNotExecutable
        case .ffmpegBookmarkMissing,
             .ffmpegBookmarkRestoreFailed,
             .ffmpegBookmarkStale,
             .ffmpegSandboxAccessDenied:
            return .ffmpegAccessDenied
        case .ffmpegEntitlementMissing:
            return .ffmpegEntitlementMissing
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

    private func debugLogInputConfiguration(_ configuration: WhisperCppTranscriptionConfiguration) {
        #if DEBUG
        print(
            "[Rokurics][TranscriptionConfigurationValidator] input bookmark bytes: " +
            "executable=\(configuration.executableBookmarkData?.count ?? 0), " +
            "executableParentDirectory=\(configuration.executableParentDirectoryBookmarkData?.count ?? 0), " +
            "whisperCppRootDirectory=\(configuration.whisperCppRootDirectoryBookmarkData?.count ?? 0), " +
            "model=\(configuration.modelBookmarkData?.count ?? 0), " +
            "ffmpeg=\(configuration.ffmpegExecutableBookmarkData?.count ?? 0), " +
            "ffmpegParentDirectory=\(configuration.ffmpegExecutableParentDirectoryBookmarkData?.count ?? 0)"
        )
        #endif
    }
}
