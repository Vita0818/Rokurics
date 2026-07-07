//
//  WhisperCppSettingsDraft.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/15.
//

import Foundation

enum WhisperCppSettingsFileSelection {
    case executable
    case model
    case whisperCppRootDirectory
    case ffmpeg
}

enum WhisperCppFileAuthorizationState: Equatable {
    case authorized(WhisperCppFileAuthorizationScope)
    case unauthorized

    var displayText: String {
        switch self {
        case .authorized(.file):
            return RokuricsCopy.text("已授权", "Allowed")
        case .authorized(.parentDirectory):
            return RokuricsCopy.text("已授权（文件夹）", "Folder access")
        case .unauthorized:
            return RokuricsCopy.text("未授权", "No access")
        }
    }
}

enum WhisperCppFileAuthorizationScope: Equatable {
    case file
    case parentDirectory
}

enum WhisperCppFileSelectionResult {
    case selected(url: URL, bookmarkData: Data)
    case cancelled
    case failed
}

struct WhisperCppSettingsDraft: Equatable {
    private(set) var configuration: WhisperCppTranscriptionConfiguration

    init(configuration: WhisperCppTranscriptionConfiguration) {
        self.configuration = configuration
    }

    var executableAuthorizationState: WhisperCppFileAuthorizationState {
        authorizationState(for: .executable)
    }

    var modelAuthorizationState: WhisperCppFileAuthorizationState {
        authorizationState(for: .model)
    }

    var ffmpegAuthorizationState: WhisperCppFileAuthorizationState {
        authorizationState(for: .ffmpeg)
    }

    var whisperCppRootDirectoryAuthorizationState: WhisperCppFileAuthorizationState {
        authorizationState(for: .whisperCppRootDirectory)
    }

    func authorizationState(for selection: WhisperCppSettingsFileSelection) -> WhisperCppFileAuthorizationState {
        let bookmarkData: Data?
        let parentDirectoryPath: String?
        let parentDirectoryBookmarkData: Data?
        let executablePath: String?
        switch selection {
        case .executable:
            bookmarkData = configuration.executableBookmarkData
            parentDirectoryPath = configuration.executableParentDirectoryPath
            parentDirectoryBookmarkData = configuration.executableParentDirectoryBookmarkData
            executablePath = configuration.normalizedExecutablePath
        case .model:
            bookmarkData = configuration.modelBookmarkData
            parentDirectoryPath = nil
            parentDirectoryBookmarkData = nil
            executablePath = nil
        case .whisperCppRootDirectory:
            bookmarkData = configuration.whisperCppRootDirectoryBookmarkData
            parentDirectoryPath = nil
            parentDirectoryBookmarkData = nil
            executablePath = nil
        case .ffmpeg:
            bookmarkData = configuration.ffmpegExecutableBookmarkData
            parentDirectoryPath = configuration.ffmpegExecutableParentDirectoryPath
            parentDirectoryBookmarkData = configuration.ffmpegExecutableParentDirectoryBookmarkData
            executablePath = configuration.normalizedFFmpegExecutablePath
        }

        if bookmarkData?.isEmpty == false {
            return .authorized(.file)
        }

        if parentDirectoryBookmarkData?.isEmpty == false,
           let parentDirectoryPath,
           let executablePath,
           ExecutableParentDirectoryAuthorization.isDirectParentDirectory(
            parentDirectoryPath,
            ofExecutableAtPath: executablePath
           ) {
            return .authorized(.parentDirectory)
        }

        return .unauthorized
    }

    mutating func applyManualPathEdit(_ path: String, for selection: WhisperCppSettingsFileSelection) {
        switch selection {
        case .executable:
            configuration.executablePath = path
            configuration.executableBookmarkData = nil
            configuration.executableParentDirectoryPath = nil
            configuration.executableParentDirectoryBookmarkData = nil
        case .model:
            configuration.modelPath = path
            configuration.modelBookmarkData = nil
        case .whisperCppRootDirectory:
            configuration.whisperCppRootDirectoryPath = path
            configuration.whisperCppRootDirectoryBookmarkData = nil
        case .ffmpeg:
            configuration.ffmpegExecutablePath = path
            configuration.ffmpegExecutableBookmarkData = nil
            configuration.ffmpegExecutableParentDirectoryPath = nil
            configuration.ffmpegExecutableParentDirectoryBookmarkData = nil
        }
    }

    mutating func applyExecutableSelection(url: URL, bookmarkData: Data) {
        applyFileSelectionResult(.selected(url: url, bookmarkData: bookmarkData), for: .executable)
    }

    mutating func applyModelSelection(url: URL, bookmarkData: Data) {
        applyFileSelectionResult(.selected(url: url, bookmarkData: bookmarkData), for: .model)
    }

    mutating func applyFFmpegSelection(url: URL, bookmarkData: Data) {
        applyFileSelectionResult(.selected(url: url, bookmarkData: bookmarkData), for: .ffmpeg)
    }

    mutating func applyWhisperCppRootDirectorySelection(url: URL, bookmarkData: Data) {
        configuration.whisperCppRootDirectoryPath = url.path
        configuration.whisperCppRootDirectoryBookmarkData = bookmarkData
    }

    mutating func applyExecutableParentDirectorySelection(
        executableURL: URL,
        directoryURL: URL,
        bookmarkData: Data
    ) {
        configuration.executablePath = executableURL.path
        configuration.executableBookmarkData = nil
        configuration.executableParentDirectoryPath = directoryURL.path
        configuration.executableParentDirectoryBookmarkData = bookmarkData
    }

    mutating func applyFFmpegParentDirectorySelection(
        executableURL: URL,
        directoryURL: URL,
        bookmarkData: Data
    ) {
        configuration.ffmpegExecutablePath = executableURL.path
        configuration.ffmpegExecutableBookmarkData = nil
        configuration.ffmpegExecutableParentDirectoryPath = directoryURL.path
        configuration.ffmpegExecutableParentDirectoryBookmarkData = bookmarkData
    }

    mutating func applyFileSelectionResult(
        _ result: WhisperCppFileSelectionResult,
        for selection: WhisperCppSettingsFileSelection
    ) {
        switch result {
        case let .selected(url, bookmarkData):
            applyFileSelection(url: url, bookmarkData: bookmarkData, for: selection)
        case .cancelled, .failed:
            return
        }
    }

    mutating func applyFileSelection(
        url: URL,
        bookmarkData: Data,
        for selection: WhisperCppSettingsFileSelection
    ) {
        switch selection {
        case .executable:
            configuration.executablePath = url.path
            configuration.executableBookmarkData = bookmarkData
            configuration.executableParentDirectoryPath = nil
            configuration.executableParentDirectoryBookmarkData = nil
        case .model:
            configuration.modelPath = url.path
            configuration.modelBookmarkData = bookmarkData
        case .whisperCppRootDirectory:
            applyWhisperCppRootDirectorySelection(url: url, bookmarkData: bookmarkData)
        case .ffmpeg:
            configuration.ffmpegExecutablePath = url.path
            configuration.ffmpegExecutableBookmarkData = bookmarkData
            configuration.ffmpegExecutableParentDirectoryPath = nil
            configuration.ffmpegExecutableParentDirectoryBookmarkData = nil
        }
    }

    mutating func clearAuthorizations() {
        resetAuthorizations()
    }

    mutating func resetAuthorizations() {
        configuration.executablePath = ""
        configuration.modelPath = ""
        configuration.ffmpegExecutablePath = ""
        configuration.whisperCppRootDirectoryPath = nil
        configuration.whisperCppRootDirectoryBookmarkData = nil
        configuration.executableBookmarkData = nil
        configuration.executableParentDirectoryPath = nil
        configuration.executableParentDirectoryBookmarkData = nil
        configuration.modelBookmarkData = nil
        configuration.ffmpegExecutableBookmarkData = nil
        configuration.ffmpegExecutableParentDirectoryPath = nil
        configuration.ffmpegExecutableParentDirectoryBookmarkData = nil
    }
}
