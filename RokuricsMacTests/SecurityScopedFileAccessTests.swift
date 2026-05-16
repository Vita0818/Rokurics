//
//  SecurityScopedFileAccessTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/15.
//

import Darwin
import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct SecurityScopedFileAccessTests {
    @Test func macEntitlementsIncludeSecurityScopedBookmarkKeys() throws {
        let entitlementsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("RokuricsMac", isDirectory: true)
            .appendingPathComponent("RokuricsMac.entitlements", isDirectory: false)
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )

        #expect(plist[SecurityScopedFileAccess.appSandboxEntitlementName] as? Bool == true)
        #expect(plist[SecurityScopedFileAccess.userSelectedExecutableEntitlementName] as? Bool == true)
        #expect(plist[SecurityScopedFileAccess.userSelectedReadOnlyEntitlementName] as? Bool == true)
        #expect(plist[SecurityScopedFileAccess.appScopeBookmarkEntitlementName] as? Bool == true)
        #expect(plist[SecurityScopedFileAccess.userSelectedReadWriteEntitlementName] == nil)
    }

    @Test func macTargetBuildSettingsPointAtEntitlementsFile() throws {
        let projectURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Rokurics.xcodeproj", isDirectory: true)
            .appendingPathComponent("project.pbxproj", isDirectory: false)
        let project = try String(contentsOf: projectURL, encoding: .utf8)

        #expect(project.contains("CODE_SIGN_ENTITLEMENTS = RokuricsMac/RokuricsMac.entitlements;"))
    }

    @Test func bookmarkCreationOptionsUseSecurityScope() {
        let executableOptions = SecurityScopedFileAccess.BookmarkMode.executable.creationOptions
        let modelOptions = SecurityScopedFileAccess.BookmarkMode.modelReadOnly.creationOptions

        #expect(executableOptions.contains(.withSecurityScope))
        #expect(executableOptions.contains(.securityScopeAllowOnlyReadAccess))
        #expect(modelOptions.contains(.withSecurityScope))
        #expect(modelOptions.contains(.securityScopeAllowOnlyReadAccess))
    }

    @Test func executableBookmarkCreationAttemptsReadOnlyBeforeExecutableScopeFallback() {
        let attempts = SecurityScopedFileAccess.BookmarkMode.executable.creationOptionAttempts

        #expect(attempts.count == 2)
        #expect(attempts[0].contains(.withSecurityScope))
        #expect(attempts[0].contains(.securityScopeAllowOnlyReadAccess))
        #expect(attempts[1].contains(.withSecurityScope))
        #expect(!attempts[1].contains(.securityScopeAllowOnlyReadAccess))
    }

    @Test func bookmarkModesHaveDiagnosticNames() {
        #expect(SecurityScopedFileAccess.BookmarkMode.executable.diagnosticName == "executable")
        #expect(SecurityScopedFileAccess.BookmarkMode.directoryReadOnly.diagnosticName == "directoryReadOnly")
        #expect(SecurityScopedFileAccess.BookmarkMode.modelReadOnly.diagnosticName == "modelReadOnly")
    }

    @Test func bookmarkDataRoundTripsThroughWhisperConfigurationCodable() throws {
        let configuration = WhisperCppTranscriptionConfiguration(
            executablePath: "/tmp/whisper-cli",
            modelPath: "/tmp/ggml-small.bin",
            ffmpegExecutablePath: "/tmp/ffmpeg",
            whisperCppRootDirectoryPath: "/tmp/whisper.cpp",
            whisperCppRootDirectoryBookmarkData: Data([16, 17, 18]),
            executableBookmarkData: Data([1, 2, 3]),
            executableParentDirectoryPath: "/tmp",
            executableParentDirectoryBookmarkData: Data([10, 11, 12]),
            modelBookmarkData: Data([4, 5, 6]),
            ffmpegExecutableBookmarkData: Data([7, 8, 9]),
            ffmpegExecutableParentDirectoryPath: "/tmp",
            ffmpegExecutableParentDirectoryBookmarkData: Data([13, 14, 15]),
            defaultLanguage: "zh",
            preferSegmentOutput: true
        )

        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(WhisperCppTranscriptionConfiguration.self, from: encoded)

        #expect(decoded == configuration)
    }

    @Test func bookmarkDataIsCarriedIntoFileReferencesAndPreprocessorConfiguration() {
        let executableBookmarkData = Data([1, 2, 3])
        let modelBookmarkData = Data([4, 5, 6])
        let rootDirectoryBookmarkData = Data([16, 17, 18])
        let ffmpegBookmarkData = Data([7, 8, 9])
        let configuration = WhisperCppTranscriptionConfiguration(
            executablePath: "/tmp/whisper-cli",
            modelPath: "/tmp/ggml-small.bin",
            ffmpegExecutablePath: "/tmp/ffmpeg",
            whisperCppRootDirectoryPath: "/tmp/whisper.cpp",
            whisperCppRootDirectoryBookmarkData: rootDirectoryBookmarkData,
            executableBookmarkData: executableBookmarkData,
            executableParentDirectoryPath: "/tmp",
            executableParentDirectoryBookmarkData: Data([10, 11, 12]),
            modelBookmarkData: modelBookmarkData,
            ffmpegExecutableBookmarkData: ffmpegBookmarkData,
            ffmpegExecutableParentDirectoryPath: "/tmp",
            ffmpegExecutableParentDirectoryBookmarkData: Data([13, 14, 15]),
            defaultLanguage: "auto",
            preferSegmentOutput: false
        )

        #expect(configuration.executableFileReference.bookmarkData == executableBookmarkData)
        #expect(configuration.executableReference.fileBookmarkData == executableBookmarkData)
        #expect(configuration.executableReference.parentDirectoryBookmarkData == Data([10, 11, 12]))
        #expect(configuration.modelFileReference.bookmarkData == modelBookmarkData)
        #expect(configuration.whisperCppRootDirectoryReference.bookmarkData == rootDirectoryBookmarkData)
        #expect(configuration.audioPreprocessorConfiguration.ffmpegExecutableBookmarkData == ffmpegBookmarkData)
        #expect(configuration.audioPreprocessorConfiguration.ffmpegExecutableParentDirectoryBookmarkData == Data([13, 14, 15]))
    }

    @Test func executableParentDirectoryBookmarkCanAuthorizeExecutable() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let binURL = scratchURL.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        let executableURL = try makeFile(named: "whisper-cli", in: binURL, permissions: 0o755)
        let environment = makeSecurityScopedEnvironment(
            resolveBookmark: { _ in SecurityScopedBookmarkResolution(url: binURL, isStale: false) },
            startAccessing: { $0 == binURL }
        )

        let access = try SecurityScopedFileAccess.startAccessingExecutable(
            reference: SecurityScopedExecutableReference(
                executablePath: executableURL.path,
                fileBookmarkData: nil,
                parentDirectoryPath: binURL.path,
                parentDirectoryBookmarkData: Data([1, 2, 3])
            ),
            errors: Self.whisperErrors,
            environment: environment
        )
        defer { access.stop() }

        #expect(access.authorizationSource == .parentDirectoryBookmark)
        #expect(access.scopeURL == binURL)
        #expect(access.executableURL == executableURL.standardizedFileURL)
    }

    @Test func executableParentDirectoryBookmarkMustBeDirectParent() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let binURL = scratchURL.appendingPathComponent("bin", isDirectory: true)
        let otherURL = scratchURL.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherURL, withIntermediateDirectories: true)
        let executableURL = try makeFile(named: "whisper-cli", in: binURL, permissions: 0o755)
        let environment = makeSecurityScopedEnvironment(
            resolveBookmark: { _ in SecurityScopedBookmarkResolution(url: otherURL, isStale: false) },
            startAccessing: { _ in true }
        )

        do {
            try SecurityScopedFileAccess.validateExecutable(
                reference: SecurityScopedExecutableReference(
                    executablePath: executableURL.path,
                    fileBookmarkData: nil,
                    parentDirectoryPath: otherURL.path,
                    parentDirectoryBookmarkData: Data([1, 2, 3])
                ),
                errors: Self.whisperErrors,
                environment: environment
            )
            Issue.record("Expected non-parent directory bookmark to throw")
        } catch TranscriptionError.executableSandboxAccessDenied {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func executableParentDirectoryBookmarkRejectsBroadDirectories() {
        #expect(!ExecutableParentDirectoryAuthorization.isAllowedParentDirectoryPath("/opt/homebrew"))
        #expect(!ExecutableParentDirectoryAuthorization.isDirectParentDirectory(
            "/opt/homebrew",
            ofExecutableAtPath: "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg"
        ))
        #expect(ExecutableParentDirectoryAuthorization.isAllowedParentDirectoryPath(
            "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin"
        ))
        #expect(ExecutableParentDirectoryAuthorization.isDirectParentDirectory(
            "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin",
            ofExecutableAtPath: "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg"
        ))
    }

    @Test func executableWithoutBookmarkReportsSandboxAccessAfterPOSIXPasses() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)

        do {
            try SecurityScopedFileAccess.validateExecutable(
                reference: SecurityScopedFileReference(path: executableURL.path, bookmarkData: nil),
                errors: Self.whisperErrors
            )
            Issue.record("Expected missing bookmark to throw sandbox access error")
        } catch TranscriptionError.executableBookmarkMissing {
            #expect(TranscriptionError.executableBookmarkMissing.localizedDescription.contains("路径已填写"))
            #expect(TranscriptionError.executableBookmarkMissing.localizedDescription.contains("不要手动输入路径"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func executableWithoutExecuteBitReportsPOSIXPermissionError() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o644)

        do {
            try SecurityScopedFileAccess.validateExecutable(
                reference: SecurityScopedFileReference(path: executableURL.path, bookmarkData: nil),
                errors: Self.whisperErrors
            )
            Issue.record("Expected non-executable file to throw POSIX permission error")
        } catch TranscriptionError.executableNotExecutable {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func modelWithoutBookmarkOnlyRequiresReadThenReportsSandboxAccess() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)

        do {
            try SecurityScopedFileAccess.validateReadableFile(
                reference: SecurityScopedFileReference(path: modelURL.path, bookmarkData: nil),
                errors: Self.modelErrors
            )
            Issue.record("Expected readable model without bookmark to throw sandbox access error")
        } catch TranscriptionError.modelBookmarkMissing {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func bookmarkRestoreFailureHasSpecificErrorMessage() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let environment = makeSecurityScopedEnvironment(
            resolveBookmark: { _ in throw CocoaError(.fileReadCorruptFile) },
            startAccessing: { _ in true }
        )

        do {
            try SecurityScopedFileAccess.validateExecutable(
                reference: SecurityScopedFileReference(path: executableURL.path, bookmarkData: Data([1, 2, 3])),
                errors: Self.whisperErrors,
                environment: environment
            )
            Issue.record("Expected corrupt bookmark to throw restore failure")
        } catch TranscriptionError.executableBookmarkRestoreFailed {
            #expect(TranscriptionError.executableBookmarkRestoreFailed.localizedDescription == "已保存的 sandbox 授权无法恢复，请重新选择文件。")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func staleBookmarkHasSpecificErrorMessage() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let environment = makeSecurityScopedEnvironment(
            resolveBookmark: { _ in SecurityScopedBookmarkResolution(url: modelURL, isStale: true) },
            startAccessing: { _ in true }
        )

        do {
            try SecurityScopedFileAccess.validateReadableFile(
                reference: SecurityScopedFileReference(path: modelURL.path, bookmarkData: Data([4, 5, 6])),
                errors: Self.modelErrors,
                environment: environment
            )
            Issue.record("Expected stale bookmark to throw stale failure")
        } catch TranscriptionError.modelBookmarkStale {
            #expect(TranscriptionError.modelBookmarkStale.localizedDescription == "已保存的 sandbox 授权已过期，请重新选择文件。")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func startAccessingFalseHasSpecificErrorMessage() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let ffmpegURL = try makeFile(named: "ffmpeg", in: scratchURL, permissions: 0o755)
        let environment = makeSecurityScopedEnvironment(
            resolveBookmark: { _ in SecurityScopedBookmarkResolution(url: ffmpegURL, isStale: false) },
            startAccessing: { _ in false }
        )

        do {
            try SecurityScopedFileAccess.validateExecutable(
                reference: SecurityScopedFileReference(path: ffmpegURL.path, bookmarkData: Data([7, 8, 9])),
                errors: Self.ffmpegErrors,
                environment: environment
            )
            Issue.record("Expected startAccessing false to throw sandbox access error")
        } catch TranscriptionError.ffmpegSandboxAccessDenied {
            #expect(TranscriptionError.ffmpegSandboxAccessDenied.localizedDescription.contains("重置授权"))
            #expect(TranscriptionError.ffmpegSandboxAccessDenied.localizedDescription.contains("最新构建"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func missingAppScopeBookmarkEntitlementHasSpecificErrorMessage() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let environment = makeSecurityScopedEnvironment(
            appScopeBookmarkEntitlement: false,
            resolveBookmark: { _ in SecurityScopedBookmarkResolution(url: executableURL, isStale: false) },
            startAccessing: { _ in true }
        )

        do {
            try SecurityScopedFileAccess.validateExecutable(
                reference: SecurityScopedFileReference(path: executableURL.path, bookmarkData: Data([1, 2, 3])),
                errors: Self.whisperErrors,
                environment: environment
            )
            Issue.record("Expected missing app-scope entitlement to throw")
        } catch TranscriptionError.bookmarkEntitlementMissing {
            #expect(TranscriptionError.bookmarkEntitlementMissing.localizedDescription == "当前 App 缺少 app-scope bookmark entitlement。")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func ffmpegMissingPathUsesFFmpegSpecificError() {
        do {
            try SecurityScopedFileAccess.validateExecutable(
                reference: SecurityScopedFileReference(path: "", bookmarkData: nil),
                errors: Self.ffmpegErrors
            )
            Issue.record("Expected missing ffmpeg path to throw")
        } catch TranscriptionError.ffmpegPathMissing {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func executableMissingPathHasChooseFileAuthorizationMessage() {
        do {
            try SecurityScopedFileAccess.validateExecutable(
                reference: SecurityScopedFileReference(path: "", bookmarkData: nil),
                errors: Self.whisperErrors
            )
            Issue.record("Expected missing executable path to throw")
        } catch TranscriptionError.executablePathMissing {
            #expect(TranscriptionError.executablePathMissing.localizedDescription == "尚未选择文件，请通过“选择文件”授权。")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeScratchDirectory() throws -> URL {
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        return scratchURL
    }

    private func makeFile(named name: String, in directoryURL: URL, permissions: mode_t) throws -> URL {
        let url = directoryURL.appendingPathComponent(name, isDirectory: false)
        try Data("test".utf8).write(to: url)
        chmod(url.path, permissions)
        return url
    }

    private func makeSecurityScopedEnvironment(
        appScopeBookmarkEntitlement: Bool = true,
        resolveBookmark: @escaping (Data) throws -> SecurityScopedBookmarkResolution,
        startAccessing: @escaping (URL) -> Bool
    ) -> SecurityScopedFileAccessEnvironment {
        SecurityScopedFileAccessEnvironment(
            hasEntitlement: { name in
                switch name {
                case SecurityScopedFileAccess.appSandboxEntitlementName:
                    return true
                case SecurityScopedFileAccess.appScopeBookmarkEntitlementName:
                    return appScopeBookmarkEntitlement
                case SecurityScopedFileAccess.userSelectedExecutableEntitlementName:
                    return true
                default:
                    return false
                }
            },
            resolveBookmark: resolveBookmark,
            startAccessing: startAccessing,
            stopAccessing: { _ in }
        )
    }

    private static let whisperErrors = ExecutableValidationErrors(
        pathMissing: .executablePathMissing,
        notFound: .executableNotFound,
        isDirectory: .executableIsDirectory,
        notExecutable: .executableNotExecutable,
        sandboxAccessDenied: .executableSandboxAccessDenied,
        executableEntitlementMissing: .executableEntitlementMissing,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )

    private static let ffmpegErrors = ExecutableValidationErrors(
        pathMissing: .ffmpegPathMissing,
        notFound: .ffmpegNotFound,
        isDirectory: .ffmpegIsDirectory,
        notExecutable: .ffmpegNotExecutable,
        sandboxAccessDenied: .ffmpegSandboxAccessDenied,
        executableEntitlementMissing: .ffmpegEntitlementMissing,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )

    private static let modelErrors = ReadableFileValidationErrors(
        pathMissing: .modelPathMissing,
        notFound: .modelNotFound,
        isDirectory: .modelIsDirectory,
        sandboxAccessDenied: .modelSandboxAccessDenied,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )
}
