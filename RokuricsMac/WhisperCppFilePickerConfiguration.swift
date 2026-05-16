//
//  WhisperCppFilePickerConfiguration.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/16.
//

import AppKit
import Foundation

enum WhisperCppFilePickerRole {
    case executable
    case model
}

struct WhisperCppFilePickerConfiguration {
    let role: WhisperCppFilePickerRole
    let diagnosticRole: String
    let canChooseFiles: Bool
    let canChooseDirectories: Bool
    let allowsMultipleSelection: Bool
    let canCreateDirectories: Bool
    let treatsFilePackagesAsDirectories: Bool
    let hasRestrictiveAllowedContentTypes: Bool
    let bookmarkMode: SecurityScopedFileAccess.BookmarkMode

    static let executable = WhisperCppFilePickerConfiguration(
        role: .executable,
        diagnosticRole: "whisper-cli",
        canChooseFiles: true,
        canChooseDirectories: false,
        allowsMultipleSelection: false,
        canCreateDirectories: false,
        treatsFilePackagesAsDirectories: false,
        hasRestrictiveAllowedContentTypes: false,
        bookmarkMode: .executable
    )

    static let model = WhisperCppFilePickerConfiguration(
        role: .model,
        diagnosticRole: "model",
        canChooseFiles: true,
        canChooseDirectories: false,
        allowsMultipleSelection: false,
        canCreateDirectories: false,
        treatsFilePackagesAsDirectories: false,
        hasRestrictiveAllowedContentTypes: false,
        bookmarkMode: .modelReadOnly
    )

    static let ffmpeg = WhisperCppFilePickerConfiguration(
        role: .executable,
        diagnosticRole: "ffmpeg",
        canChooseFiles: true,
        canChooseDirectories: false,
        allowsMultipleSelection: false,
        canCreateDirectories: false,
        treatsFilePackagesAsDirectories: false,
        hasRestrictiveAllowedContentTypes: false,
        bookmarkMode: .executable
    )

    @MainActor
    func apply(to panel: NSOpenPanel) {
        panel.canChooseFiles = canChooseFiles
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canCreateDirectories = canCreateDirectories
        panel.treatsFilePackagesAsDirectories = treatsFilePackagesAsDirectories
        panel.prompt = "选择"
    }
}

enum WhisperCppFileSelectionError: LocalizedError {
    case directorySelected(WhisperCppFilePickerRole)
    case bookmarkCreationFailed

    var errorDescription: String? {
        switch self {
        case .directorySelected(.executable):
            return "请选择可执行文件，不要选择文件夹。"
        case .directorySelected(.model):
            return "请选择模型文件，不要选择文件夹。"
        case .bookmarkCreationFailed:
            return "无法为所选文件创建 sandbox 授权，请重新选择。"
        }
    }
}

struct WhisperCppBookmarkCreationFailureDiagnostic {
    let role: String
    let bookmarkOptionsType: String
    let selectedPath: String
    let standardizedPath: String
    let symlinkResolvedPath: String
    let nsErrorDomain: String
    let nsErrorCode: Int
    let localizedDescription: String
    let failureReason: String?
    let recoverySuggestion: String?
    let lastPathComponent: String

    init(
        role: String,
        bookmarkMode: SecurityScopedFileAccess.BookmarkMode,
        url: URL,
        error: Error
    ) {
        self.role = role
        if let diagnostic = error as? SecurityScopedBookmarkCreationFailureDiagnostic {
            self.bookmarkOptionsType = diagnostic.bookmarkOptions
            self.selectedPath = diagnostic.selectedPath
            self.standardizedPath = diagnostic.standardizedPath
            self.symlinkResolvedPath = diagnostic.symlinkResolvedPath
            self.nsErrorDomain = diagnostic.nsErrorDomain
            self.nsErrorCode = diagnostic.nsErrorCode
            self.localizedDescription = diagnostic.localizedDescription
            self.failureReason = diagnostic.failureReason
            self.recoverySuggestion = diagnostic.recoverySuggestion
            self.lastPathComponent = URL(fileURLWithPath: diagnostic.selectedPath).lastPathComponent
            return
        }

        let nsError = error as NSError
        self.bookmarkOptionsType = SecurityScopedFileAccess.bookmarkOptionsDescription(bookmarkMode.creationOptions)
        self.selectedPath = url.path
        self.standardizedPath = url.standardizedFileURL.path
        self.symlinkResolvedPath = url.resolvingSymlinksInPath().path
        self.nsErrorDomain = nsError.domain
        self.nsErrorCode = nsError.code
        self.localizedDescription = nsError.localizedDescription
        self.failureReason = nsError.localizedFailureReason
        self.recoverySuggestion = nsError.localizedRecoverySuggestion
        self.lastPathComponent = url.lastPathComponent
    }

    var userMessage: String {
        let hint = role == "model" ? "" : "；可改选其所在文件夹授权"
        return limited(
            "无法创建 sandbox 授权：domain=\(nsErrorDomain) code=\(nsErrorCode) \(localizedDescription)\(hint)",
            maxCharacters: 240
        )
    }

    var debugLogMessage: String {
        var fields = [
            "role=\(role)",
            "options=\(bookmarkOptionsType)",
            "selectedPath=\(selectedPath)",
            "standardizedPath=\(standardizedPath)",
            "symlinkResolvedPath=\(symlinkResolvedPath)",
            "lastPathComponent=\(lastPathComponent)",
            "nsErrorDomain=\(nsErrorDomain)",
            "nsErrorCode=\(nsErrorCode)",
            "localizedDescription=\(localizedDescription)"
        ]

        if let failureReason, !failureReason.isEmpty {
            fields.append("failureReason=\(failureReason)")
        }

        if let recoverySuggestion, !recoverySuggestion.isEmpty {
            fields.append("recoverySuggestion=\(recoverySuggestion)")
        }

        return "[Rokurics][MacWhisperCppSettingsView] bookmark creation failed: "
            + fields.joined(separator: ", ")
    }

    private func limited(_ string: String, maxCharacters: Int) -> String {
        guard string.count > maxCharacters else {
            return string
        }

        return String(string.prefix(maxCharacters)) + "..."
    }
}
