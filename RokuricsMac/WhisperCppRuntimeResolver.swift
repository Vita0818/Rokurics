//
//  WhisperCppRuntimeResolver.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/16.
//

import Foundation

enum WhisperCppRuntimeMode: String, Codable, Equatable {
    case bundled
    case externalDebugFallback

    var displayText: String {
        switch self {
        case .bundled:
            return "内置 helper"
        case .externalDebugFallback:
            return "外部调试路径"
        }
    }
}

struct WhisperCppRuntimeResolution: Equatable {
    let mode: WhisperCppRuntimeMode
    let bundledHelperURL: URL
    let bundledHelperExists: Bool
    let bundledHelperIsDirectory: Bool
    let bundledHelperIsExecutable: Bool
    let executableURL: URL
    let currentDirectoryURL: URL?

    var statusText: String {
        switch mode {
        case .bundled:
            return "whisper runtime：内置 helper"
        case .externalDebugFallback:
            return bundledHelperExists
                ? "whisper runtime：外部调试路径（内置 helper 不可执行）"
                : "whisper runtime：外部调试路径（未找到内置 helper）"
        }
    }
}

protocol WhisperCppRuntimeResolving {
    func resolveRuntime(configuration: WhisperCppTranscriptionConfiguration) -> WhisperCppRuntimeResolution
}

struct WhisperCppRuntimeResolver: WhisperCppRuntimeResolving {
    static let bundledHelperRelativePath = "Contents/Helpers/rokurics-whisper"

    private let bundleURL: URL
    private let fileManager: FileManager

    init(bundle: Bundle = .main, fileManager: FileManager = .default) {
        self.bundleURL = bundle.bundleURL
        self.fileManager = fileManager
    }

    init(bundleURL: URL, fileManager: FileManager = .default) {
        self.bundleURL = bundleURL
        self.fileManager = fileManager
    }

    func resolveRuntime(configuration: WhisperCppTranscriptionConfiguration) -> WhisperCppRuntimeResolution {
        let helperURL = Self.bundledHelperURL(bundleURL: bundleURL)
        var isDirectory: ObjCBool = false
        let helperExists = fileManager.fileExists(atPath: helperURL.path, isDirectory: &isDirectory)
        let helperIsExecutable = helperExists
            && !isDirectory.boolValue
            && fileManager.isExecutableFile(atPath: helperURL.path)

        if helperIsExecutable {
            return WhisperCppRuntimeResolution(
                mode: .bundled,
                bundledHelperURL: helperURL,
                bundledHelperExists: helperExists,
                bundledHelperIsDirectory: isDirectory.boolValue,
                bundledHelperIsExecutable: helperIsExecutable,
                executableURL: helperURL,
                currentDirectoryURL: helperURL.deletingLastPathComponent().standardizedFileURL
            )
        }

        let externalURL = URL(
            fileURLWithPath: configuration.normalizedExecutablePath,
            isDirectory: false
        ).standardizedFileURL

        return WhisperCppRuntimeResolution(
            mode: .externalDebugFallback,
            bundledHelperURL: helperURL,
            bundledHelperExists: helperExists,
            bundledHelperIsDirectory: isDirectory.boolValue,
            bundledHelperIsExecutable: helperIsExecutable,
            executableURL: externalURL,
            currentDirectoryURL: nil
        )
    }

    static func bundledHelperURL(bundleURL: URL) -> URL {
        bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("rokurics-whisper", isDirectory: false)
            .standardizedFileURL
    }
}
