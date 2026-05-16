//
//  AudioPreprocessorConfiguration.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/15.
//

import Foundation

enum AudioPreprocessorConversionStrategy: String, Equatable {
    case nativePreferred
    case ffmpegOnly
    case nativeThenFFmpegFallback

    var displayText: String {
        switch self {
        case .nativePreferred:
            return "native"
        case .ffmpegOnly:
            return "ffmpeg"
        case .nativeThenFFmpegFallback:
            return "nativeThenFFmpegFallback"
        }
    }

    var requiresFFmpegForConfigurationValidation: Bool {
        self == .ffmpegOnly
    }
}

struct AudioPreprocessorConfiguration: Equatable {
    var conversionStrategy: AudioPreprocessorConversionStrategy = .nativePreferred
    var ffmpegExecutablePath: String? = nil
    var ffmpegExecutableBookmarkData: Data? = nil
    var ffmpegExecutableParentDirectoryPath: String? = nil
    var ffmpegExecutableParentDirectoryBookmarkData: Data? = nil

    static let commonFFmpegExecutablePaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]

    var normalizedFFmpegExecutablePath: String {
        (ffmpegExecutablePath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedFFmpegExecutablePath: String {
        let configuredPath = normalizedFFmpegExecutablePath
        guard configuredPath.isEmpty else {
            return expandedPath(configuredPath)
        }

        return Self.discoveredFFmpegExecutablePath() ?? ""
    }

    var ffmpegFileReference: SecurityScopedFileReference {
        SecurityScopedFileReference(
            path: resolvedFFmpegExecutablePath,
            bookmarkData: ffmpegExecutableBookmarkData
        )
    }

    var ffmpegExecutableReference: SecurityScopedExecutableReference {
        SecurityScopedExecutableReference(
            executablePath: resolvedFFmpegExecutablePath,
            fileBookmarkData: ffmpegExecutableBookmarkData,
            parentDirectoryPath: ffmpegExecutableParentDirectoryPath,
            parentDirectoryBookmarkData: ffmpegExecutableParentDirectoryBookmarkData
        )
    }

    static func discoveredFFmpegExecutablePath(fileManager: FileManager = .default) -> String? {
        commonFFmpegExecutablePaths.first { path in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && fileManager.isExecutableFile(atPath: path)
        }
    }

    private func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
