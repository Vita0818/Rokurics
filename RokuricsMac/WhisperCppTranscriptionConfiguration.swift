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
    var ffmpegExecutablePath: String?
    var whisperCppRootDirectoryPath: String? = nil
    var whisperCppRootDirectoryBookmarkData: Data? = nil
    var executableBookmarkData: Data?
    var executableParentDirectoryPath: String? = nil
    var executableParentDirectoryBookmarkData: Data? = nil
    var modelBookmarkData: Data?
    var ffmpegExecutableBookmarkData: Data?
    var ffmpegExecutableParentDirectoryPath: String? = nil
    var ffmpegExecutableParentDirectoryBookmarkData: Data? = nil
    var defaultLanguage: String
    var preferSegmentOutput: Bool

    static let `default` = WhisperCppTranscriptionConfiguration(
        executablePath: "",
        modelPath: "",
        ffmpegExecutablePath: AudioPreprocessorConfiguration.discoveredFFmpegExecutablePath(),
        whisperCppRootDirectoryPath: nil,
        whisperCppRootDirectoryBookmarkData: nil,
        executableBookmarkData: nil,
        executableParentDirectoryPath: nil,
        executableParentDirectoryBookmarkData: nil,
        modelBookmarkData: nil,
        ffmpegExecutableBookmarkData: nil,
        ffmpegExecutableParentDirectoryPath: nil,
        ffmpegExecutableParentDirectoryBookmarkData: nil,
        defaultLanguage: "auto",
        preferSegmentOutput: false
    )

    var normalizedExecutablePath: String {
        executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedModelPath: String {
        modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedFFmpegExecutablePath: String {
        (ffmpegExecutablePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedWhisperCppRootDirectoryPath: String {
        (whisperCppRootDirectoryPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedExecutableParentDirectoryPath: String {
        (executableParentDirectoryPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedFFmpegExecutableParentDirectoryPath: String {
        (ffmpegExecutableParentDirectoryPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var audioPreprocessorConfiguration: AudioPreprocessorConfiguration {
        AudioPreprocessorConfiguration(
            ffmpegExecutablePath: ffmpegExecutablePath,
            ffmpegExecutableBookmarkData: ffmpegExecutableBookmarkData,
            ffmpegExecutableParentDirectoryPath: ffmpegExecutableParentDirectoryPath,
            ffmpegExecutableParentDirectoryBookmarkData: ffmpegExecutableParentDirectoryBookmarkData
        )
    }

    var executableFileReference: SecurityScopedFileReference {
        SecurityScopedFileReference(path: normalizedExecutablePath, bookmarkData: executableBookmarkData)
    }

    var executableReference: SecurityScopedExecutableReference {
        SecurityScopedExecutableReference(
            executablePath: normalizedExecutablePath,
            fileBookmarkData: executableBookmarkData,
            parentDirectoryPath: normalizedExecutableParentDirectoryPath,
            parentDirectoryBookmarkData: executableParentDirectoryBookmarkData
        )
    }

    var modelFileReference: SecurityScopedFileReference {
        SecurityScopedFileReference(path: normalizedModelPath, bookmarkData: modelBookmarkData)
    }

    var whisperCppRootDirectoryReference: SecurityScopedFileReference {
        SecurityScopedFileReference(
            path: normalizedWhisperCppRootDirectoryPath,
            bookmarkData: whisperCppRootDirectoryBookmarkData
        )
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

    var modelKind: WhisperModelKind {
        WhisperModelKind.infer(fromModelFileName: modelFileName)
    }

    var currentModelDisplayName: String {
        guard let modelFileName else {
            return "未选择模型"
        }

        return "\(modelFileName) (\(modelKind.displayName))"
    }

    var preferredLargeModel: Bool {
        modelKind.isLargePreferred
    }
}
