//
//  WhisperCppSettingsDraftTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/15.
//

import Darwin
import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct WhisperCppSettingsDraftTests {
    @Test func applyExecutableSelectionUpdatesPathAndBookmarkData() {
        let selectedURL = URL(fileURLWithPath: "/tmp/whisper-cli")
        let bookmarkData = Data([1, 2, 3, 4])
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyExecutableSelection(url: selectedURL, bookmarkData: bookmarkData)

        #expect(selectedURL.pathExtension.isEmpty)
        #expect(draft.configuration.executablePath == selectedURL.path)
        #expect(draft.configuration.executableBookmarkData == bookmarkData)
        #expect(draft.executableAuthorizationState == .authorized(.file))
    }

    @Test func applyModelSelectionUpdatesPathAndBookmarkData() {
        let selectedURL = URL(fileURLWithPath: "/tmp/ggml-base.bin")
        let bookmarkData = Data([4, 5, 6, 7])
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyModelSelection(url: selectedURL, bookmarkData: bookmarkData)

        #expect(draft.configuration.modelPath == selectedURL.path)
        #expect(draft.configuration.modelBookmarkData == bookmarkData)
        #expect(draft.modelAuthorizationState == .authorized(.file))
    }

    @Test func applyFFmpegSelectionUpdatesPathAndBookmarkData() {
        let selectedURL = URL(fileURLWithPath: "/tmp/ffmpeg")
        let bookmarkData = Data([7, 8, 9, 10])
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyFFmpegSelection(url: selectedURL, bookmarkData: bookmarkData)

        #expect(selectedURL.pathExtension.isEmpty)
        #expect(draft.configuration.ffmpegExecutablePath == selectedURL.path)
        #expect(draft.configuration.ffmpegExecutableBookmarkData == bookmarkData)
        #expect(draft.ffmpegAuthorizationState == .authorized(.file))
    }

    @Test func applyWhisperCppRootDirectorySelectionUpdatesPathAndBookmarkData() {
        let selectedURL = URL(fileURLWithPath: "/tmp/whisper.cpp", isDirectory: true)
        let bookmarkData = Data([14, 15, 16, 17])
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyWhisperCppRootDirectorySelection(url: selectedURL, bookmarkData: bookmarkData)

        #expect(draft.configuration.whisperCppRootDirectoryPath == selectedURL.path)
        #expect(draft.configuration.whisperCppRootDirectoryBookmarkData == bookmarkData)
        #expect(draft.whisperCppRootDirectoryAuthorizationState == .authorized(.file))
    }

    @Test func manualExecutablePathEditClearsOnlyExecutableBookmarkData() {
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyManualPathEdit("/tmp/manual-whisper-cli", for: .executable)

        #expect(draft.configuration.executablePath == "/tmp/manual-whisper-cli")
        #expect(draft.configuration.executableBookmarkData == nil)
        #expect(draft.configuration.executableParentDirectoryPath == nil)
        #expect(draft.configuration.executableParentDirectoryBookmarkData == nil)
        #expect(draft.executableAuthorizationState == .unauthorized)
        #expect(draft.configuration.modelBookmarkData == Data([4, 5, 6]))
        #expect(draft.configuration.ffmpegExecutableBookmarkData == Data([7, 8, 9]))
    }

    @Test func manualModelPathEditClearsOnlyModelBookmarkData() {
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyManualPathEdit("/tmp/manual-model.bin", for: .model)

        #expect(draft.configuration.modelPath == "/tmp/manual-model.bin")
        #expect(draft.configuration.executableBookmarkData == Data([1, 2, 3]))
        #expect(draft.configuration.executableParentDirectoryBookmarkData == Data([10, 11, 12]))
        #expect(draft.configuration.modelBookmarkData == nil)
        #expect(draft.configuration.ffmpegExecutableBookmarkData == Data([7, 8, 9]))
        #expect(draft.configuration.ffmpegExecutableParentDirectoryBookmarkData == Data([13, 14, 15]))
    }

    @Test func manualFFmpegPathEditClearsOnlyFFmpegBookmarkData() {
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyManualPathEdit("/tmp/manual-ffmpeg", for: .ffmpeg)

        #expect(draft.configuration.ffmpegExecutablePath == "/tmp/manual-ffmpeg")
        #expect(draft.configuration.executableBookmarkData == Data([1, 2, 3]))
        #expect(draft.configuration.modelBookmarkData == Data([4, 5, 6]))
        #expect(draft.configuration.ffmpegExecutableBookmarkData == nil)
        #expect(draft.configuration.ffmpegExecutableParentDirectoryPath == nil)
        #expect(draft.configuration.ffmpegExecutableParentDirectoryBookmarkData == nil)
    }

    @Test func manualRootDirectoryPathEditClearsOnlyRootDirectoryBookmarkData() {
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyManualPathEdit("/tmp/manual-whisper-root", for: .whisperCppRootDirectory)

        #expect(draft.configuration.whisperCppRootDirectoryPath == "/tmp/manual-whisper-root")
        #expect(draft.configuration.whisperCppRootDirectoryBookmarkData == nil)
        #expect(draft.configuration.executableBookmarkData == Data([1, 2, 3]))
        #expect(draft.configuration.modelBookmarkData == Data([4, 5, 6]))
        #expect(draft.configuration.ffmpegExecutableBookmarkData == Data([7, 8, 9]))
    }

    @Test func programmaticSelectionIsNotTreatedAsManualPathEdit() {
        let selectedURL = URL(fileURLWithPath: "/tmp/programmatic-whisper-cli")
        let bookmarkData = Data([9, 8, 7])
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyExecutableSelection(url: selectedURL, bookmarkData: bookmarkData)

        #expect(draft.configuration.executablePath == selectedURL.path)
        #expect(draft.configuration.executableBookmarkData == bookmarkData)
        #expect(draft.configuration.executableParentDirectoryBookmarkData == nil)
        #expect(draft.executableAuthorizationState == .authorized(.file))
    }

    @Test func executableParentDirectorySelectionAuthorizesAsFolderAndClearsFileBookmark() {
        let executableURL = URL(fileURLWithPath: "/tmp/whisper/bin/whisper-cli")
        let directoryURL = URL(fileURLWithPath: "/tmp/whisper/bin", isDirectory: true)
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyExecutableParentDirectorySelection(
            executableURL: executableURL,
            directoryURL: directoryURL,
            bookmarkData: Data([10, 11, 12])
        )

        #expect(draft.configuration.executablePath == executableURL.path)
        #expect(draft.configuration.executableBookmarkData == nil)
        #expect(draft.configuration.executableParentDirectoryPath == directoryURL.path)
        #expect(draft.configuration.executableParentDirectoryBookmarkData == Data([10, 11, 12]))
        #expect(draft.executableAuthorizationState == .authorized(.parentDirectory))
        #expect(draft.executableAuthorizationState.displayText == "已授权（文件夹）")
    }

    @Test func ffmpegParentDirectorySelectionAuthorizesAsFolderAndClearsFileBookmark() {
        let executableURL = URL(fileURLWithPath: "/tmp/ffmpeg/bin/ffmpeg")
        let directoryURL = URL(fileURLWithPath: "/tmp/ffmpeg/bin", isDirectory: true)
        var draft = WhisperCppSettingsDraft(configuration: makeConfiguration())

        draft.applyFFmpegParentDirectorySelection(
            executableURL: executableURL,
            directoryURL: directoryURL,
            bookmarkData: Data([13, 14, 15])
        )

        #expect(draft.configuration.ffmpegExecutablePath == executableURL.path)
        #expect(draft.configuration.ffmpegExecutableBookmarkData == nil)
        #expect(draft.configuration.ffmpegExecutableParentDirectoryPath == directoryURL.path)
        #expect(draft.configuration.ffmpegExecutableParentDirectoryBookmarkData == Data([13, 14, 15]))
        #expect(draft.ffmpegAuthorizationState == .authorized(.parentDirectory))
    }

    @Test func cancelledSelectionDoesNotClearPreviousBookmark() {
        let originalConfiguration = makeConfiguration()
        var draft = WhisperCppSettingsDraft(configuration: originalConfiguration)

        draft.applyFileSelectionResult(.cancelled, for: .executable)
        draft.applyFileSelectionResult(.cancelled, for: .model)
        draft.applyFileSelectionResult(.cancelled, for: .ffmpeg)

        #expect(draft.configuration == originalConfiguration)
        #expect(draft.executableAuthorizationState == .authorized(.file))
        #expect(draft.modelAuthorizationState == .authorized(.file))
        #expect(draft.ffmpegAuthorizationState == .authorized(.file))
    }

    @Test func executablePickerAllowsExtensionlessUnixExecutableSelection() {
        let configuration = WhisperCppFilePickerConfiguration.executable

        switch configuration.role {
        case .executable:
            break
        case .model:
            Issue.record("Expected executable picker role")
        }
        #expect(configuration.canChooseFiles)
        #expect(!configuration.canChooseDirectories)
        #expect(!configuration.allowsMultipleSelection)
        #expect(!configuration.treatsFilePackagesAsDirectories)
        #expect(!configuration.hasRestrictiveAllowedContentTypes)
        #expect(configuration.diagnosticRole == "whisper-cli")
        #expect(configuration.bookmarkMode == .executable)
        #expect(configuration.bookmarkMode.creationOptions.contains(.securityScopeAllowOnlyReadAccess))
    }

    @Test func ffmpegPickerUsesExecutableSelectionRules() {
        let configuration = WhisperCppFilePickerConfiguration.ffmpeg

        switch configuration.role {
        case .executable:
            break
        case .model:
            Issue.record("Expected ffmpeg to use executable picker role")
        }
        #expect(!configuration.hasRestrictiveAllowedContentTypes)
        #expect(configuration.diagnosticRole == "ffmpeg")
        #expect(configuration.bookmarkMode == .executable)
        #expect(configuration.bookmarkMode.creationOptions.contains(.securityScopeAllowOnlyReadAccess))
    }

    @Test func modelPickerUsesReadOnlyBookmarkRulesWithoutBlockingUnknownTypes() {
        let configuration = WhisperCppFilePickerConfiguration.model

        switch configuration.role {
        case .model:
            break
        case .executable:
            Issue.record("Expected model picker role")
        }
        #expect(configuration.canChooseFiles)
        #expect(!configuration.canChooseDirectories)
        #expect(!configuration.allowsMultipleSelection)
        #expect(!configuration.hasRestrictiveAllowedContentTypes)
        #expect(configuration.diagnosticRole == "model")
        #expect(configuration.bookmarkMode == .modelReadOnly)
        #expect(configuration.bookmarkMode.creationOptions.contains(.securityScopeAllowOnlyReadAccess))
    }

    @Test func failedSelectionDoesNotClearPreviousBookmark() {
        let originalConfiguration = makeConfiguration()
        var draft = WhisperCppSettingsDraft(configuration: originalConfiguration)

        draft.applyFileSelectionResult(.failed, for: .executable)

        #expect(draft.configuration == originalConfiguration)
        #expect(draft.executableAuthorizationState == .authorized(.file))
    }

    @Test func bookmarkCreationFailureDiagnosticIncludesSafeRoleAndNSErrorFields() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileNoSuchFile.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "could not create bookmark"]
        )
        let diagnostic = WhisperCppBookmarkCreationFailureDiagnostic(
            role: "whisper-cli",
            bookmarkMode: .executable,
            url: URL(fileURLWithPath: "/tmp/whisper-cli"),
            error: error
        )

        #expect(diagnostic.role == "whisper-cli")
        #expect(diagnostic.bookmarkOptionsType == "withSecurityScope+securityScopeAllowOnlyReadAccess")
        #expect(diagnostic.nsErrorDomain == NSCocoaErrorDomain)
        #expect(diagnostic.nsErrorCode == CocoaError.Code.fileNoSuchFile.rawValue)
        #expect(diagnostic.localizedDescription == "could not create bookmark")
        #expect(diagnostic.selectedPath == "/tmp/whisper-cli")
        #expect(diagnostic.standardizedPath == "/tmp/whisper-cli")
        #expect(diagnostic.symlinkResolvedPath == "/tmp/whisper-cli")
        #expect(diagnostic.lastPathComponent == "whisper-cli")
        #expect(diagnostic.debugLogMessage.contains("role=whisper-cli"))
        #expect(diagnostic.debugLogMessage.contains("options=withSecurityScope+securityScopeAllowOnlyReadAccess"))
        #expect(diagnostic.debugLogMessage.contains("nsErrorDomain=\(NSCocoaErrorDomain)"))
        #expect(diagnostic.debugLogMessage.contains("nsErrorCode=\(CocoaError.Code.fileNoSuchFile.rawValue)"))
        #expect(diagnostic.userMessage.contains("NSCocoaErrorDomain"))
        #expect(diagnostic.userMessage.contains("code=\(CocoaError.Code.fileNoSuchFile.rawValue)"))
    }

    @Test func selectionFailureUsesSelectionSpecificErrorMessage() {
        #expect(
            WhisperCppFileSelectionError.bookmarkCreationFailed.localizedDescription
                == "无法为所选文件创建 sandbox 授权，请重新选择。"
        )
        #expect(
            !WhisperCppFileSelectionError.bookmarkCreationFailed.localizedDescription
                .contains("尚未获得 sandbox 授权")
        )
    }

    @Test func directorySelectionUsesFilePickerSpecificMessage() {
        #expect(
            WhisperCppFileSelectionError.directorySelected(.executable).localizedDescription
                == "请选择可执行文件，不要选择文件夹。"
        )
        #expect(
            WhisperCppFileSelectionError.directorySelected(.model).localizedDescription
                == "请选择模型文件，不要选择文件夹。"
        )
    }

    @Test func authorizationStateUsesBookmarkBytesNotPath() {
        var configuration = makeConfiguration()
        configuration.executablePath = "/tmp/path-still-visible"
        configuration.executableBookmarkData = nil
        configuration.executableParentDirectoryPath = nil
        configuration.executableParentDirectoryBookmarkData = nil
        configuration.modelPath = ""
        configuration.modelBookmarkData = Data([1])
        configuration.ffmpegExecutablePath = "/tmp/ffmpeg"
        configuration.ffmpegExecutableBookmarkData = Data()
        configuration.ffmpegExecutableParentDirectoryPath = nil
        configuration.ffmpegExecutableParentDirectoryBookmarkData = nil

        let draft = WhisperCppSettingsDraft(configuration: configuration)

        #expect(draft.executableAuthorizationState == .unauthorized)
        #expect(draft.modelAuthorizationState == .authorized(.file))
        #expect(draft.ffmpegAuthorizationState == .unauthorized)
    }

    @Test func draftConfigurationDoesNotDropBookmarkData() {
        let configuration = makeConfiguration()
        let draft = WhisperCppSettingsDraft(configuration: configuration)

        #expect(draft.configuration.executableBookmarkData == Data([1, 2, 3]))
        #expect(draft.configuration.executableParentDirectoryBookmarkData == Data([10, 11, 12]))
        #expect(draft.configuration.whisperCppRootDirectoryBookmarkData == Data([16, 17, 18]))
        #expect(draft.configuration.modelBookmarkData == Data([4, 5, 6]))
        #expect(draft.configuration.ffmpegExecutableBookmarkData == Data([7, 8, 9]))
        #expect(draft.configuration.ffmpegExecutableParentDirectoryBookmarkData == Data([13, 14, 15]))
    }

    @Test func storeSaveAndReloadKeepsBookmarkData() {
        let defaults = InMemoryTranscriptionSettingsDefaults()
        let store = TranscriptionSettingsStore(defaults: defaults)
        let configuration = makeConfiguration()

        store.updateWhisperConfiguration { $0 = configuration }
        store.persist()

        let reloadedStore = TranscriptionSettingsStore(defaults: defaults)
        #expect(reloadedStore.whisperConfiguration.executableBookmarkData?.count == 3)
        #expect(reloadedStore.whisperConfiguration.executableParentDirectoryBookmarkData?.count == 3)
        #expect(reloadedStore.whisperConfiguration.whisperCppRootDirectoryBookmarkData?.count == 3)
        #expect(reloadedStore.whisperConfiguration.modelBookmarkData?.count == 3)
        #expect(reloadedStore.whisperConfiguration.ffmpegExecutableBookmarkData?.count == 3)
        #expect(reloadedStore.whisperConfiguration.ffmpegExecutableParentDirectoryBookmarkData?.count == 3)
        #expect(reloadedStore.whisperConfiguration == configuration)
    }

    @Test func resetAuthorizationsClearsPathAndBookmarkData() {
        let defaults = InMemoryTranscriptionSettingsDefaults()
        let store = TranscriptionSettingsStore(defaults: defaults)
        store.updateWhisperConfiguration { $0 = makeConfiguration() }

        store.resetWhisperCppAuthorizations()

        #expect(store.whisperConfiguration.executablePath.isEmpty)
        #expect(store.whisperConfiguration.modelPath.isEmpty)
        #expect(store.whisperConfiguration.ffmpegExecutablePath?.isEmpty == true)
        #expect(store.whisperConfiguration.whisperCppRootDirectoryPath == nil)
        #expect(store.whisperConfiguration.executableBookmarkData == nil)
        #expect(store.whisperConfiguration.executableParentDirectoryPath == nil)
        #expect(store.whisperConfiguration.executableParentDirectoryBookmarkData == nil)
        #expect(store.whisperConfiguration.whisperCppRootDirectoryBookmarkData == nil)
        #expect(store.whisperConfiguration.modelBookmarkData == nil)
        #expect(store.whisperConfiguration.ffmpegExecutableBookmarkData == nil)
        #expect(store.whisperConfiguration.ffmpegExecutableParentDirectoryPath == nil)
        #expect(store.whisperConfiguration.ffmpegExecutableParentDirectoryBookmarkData == nil)
        #expect(WhisperCppSettingsDraft(configuration: store.whisperConfiguration).executableAuthorizationState == .unauthorized)
    }

    @Test func validatorUsesPassedConfigurationBookmarkData() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        var configuration = makeConfiguration()
        configuration.executablePath = executableURL.path
        configuration.executableBookmarkData = Data([9, 9, 9])
        let environment = SecurityScopedFileAccessEnvironment(
            hasEntitlement: { name in
                switch name {
                case SecurityScopedFileAccess.appSandboxEntitlementName,
                     SecurityScopedFileAccess.appScopeBookmarkEntitlementName,
                     SecurityScopedFileAccess.userSelectedExecutableEntitlementName:
                    return true
                default:
                    return false
                }
            },
            resolveBookmark: { _ in throw CocoaError(.fileReadCorruptFile) },
            startAccessing: { _ in true },
            stopAccessing: { _ in }
        )
        let validator = TranscriptionConfigurationValidator(
            securityScopedEnvironment: environment,
            runtimeResolver: ExternalDebugWhisperSettingsRuntimeResolver()
        )

        let result = await validator.validateWhisperCpp(configuration)

        #expect(result.status == .executableAccessDenied)
        #expect(result.message == "已保存的 sandbox 授权无法恢复，请重新选择文件。")
    }

    @Test func validatorDoesNotRequireFFmpegForNativeAudioConversion() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let executableBookmark = Data([1])
        let modelBookmark = Data([2])
        let rootBookmark = Data([3])
        let configuration = WhisperCppTranscriptionConfiguration(
            executablePath: executableURL.path,
            modelPath: modelURL.path,
            ffmpegExecutablePath: "/missing/ffmpeg",
            whisperCppRootDirectoryPath: scratchURL.path,
            whisperCppRootDirectoryBookmarkData: rootBookmark,
            executableBookmarkData: executableBookmark,
            modelBookmarkData: modelBookmark,
            ffmpegExecutableBookmarkData: nil,
            defaultLanguage: "auto",
            preferSegmentOutput: false
        )
        let environment = SecurityScopedFileAccessEnvironment(
            hasEntitlement: { name in
                switch name {
                case SecurityScopedFileAccess.appSandboxEntitlementName,
                     SecurityScopedFileAccess.appScopeBookmarkEntitlementName,
                     SecurityScopedFileAccess.userSelectedExecutableEntitlementName,
                     SecurityScopedFileAccess.userSelectedReadOnlyEntitlementName:
                    return true
                default:
                    return false
                }
            },
            resolveBookmark: { data in
                if data == executableBookmark {
                    return SecurityScopedBookmarkResolution(url: executableURL, isStale: false)
                }
                if data == modelBookmark {
                    return SecurityScopedBookmarkResolution(url: modelURL, isStale: false)
                }
                if data == rootBookmark {
                    return SecurityScopedBookmarkResolution(url: scratchURL, isStale: false)
                }
                throw CocoaError(.fileReadCorruptFile)
            },
            startAccessing: { _ in true },
            stopAccessing: { _ in }
        )
        let validator = TranscriptionConfigurationValidator(
            securityScopedEnvironment: environment,
            runtimeResolver: ExternalDebugWhisperSettingsRuntimeResolver()
        )

        let result = await validator.validateWhisperCpp(configuration)

        #expect(result.status == .valid)
        #expect(result.message == "配置有效")
    }

    @Test func validatorRequiresRootDirectoryToBeDirectory() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let rootFileURL = try makeFile(named: "not-a-directory", in: scratchURL, permissions: 0o644)
        let configuration = makeValidatingConfiguration(
            executableURL: executableURL,
            modelURL: modelURL,
            rootDirectoryURL: rootFileURL
        )
        let validator = TranscriptionConfigurationValidator(
            securityScopedEnvironment: makeValidationEnvironment(
                executableURL: executableURL,
                modelURL: modelURL,
                rootDirectoryURL: rootFileURL
            ),
            runtimeResolver: ExternalDebugWhisperSettingsRuntimeResolver()
        )

        let result = await validator.validateWhisperCpp(configuration)

        #expect(result.status == .whisperCppRootDirectoryIsFile)
    }

    @Test func validatorRejectsRootDirectoryWhenExecutableIsOutsideAndDefaultExecutableMissing() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let rootURL = scratchURL.appendingPathComponent("whisper.cpp", isDirectory: true)
        let outsideURL = scratchURL.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        let executableURL = try makeFile(named: "whisper-cli", in: outsideURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: rootURL, permissions: 0o644)
        let configuration = makeValidatingConfiguration(
            executableURL: executableURL,
            modelURL: modelURL,
            rootDirectoryURL: rootURL
        )
        let validator = TranscriptionConfigurationValidator(
            securityScopedEnvironment: makeValidationEnvironment(
                executableURL: executableURL,
                modelURL: modelURL,
                rootDirectoryURL: rootURL
            ),
            runtimeResolver: ExternalDebugWhisperSettingsRuntimeResolver()
        )

        let result = await validator.validateWhisperCpp(configuration)

        #expect(result.status == .whisperCppRootDirectoryInvalid)
        #expect(result.message.contains("build/bin/whisper-cli"))
    }

    @Test func validatorRejectsRootDirectoryWhenModelIsOutsideAndModelsDirectoryMissing() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let rootURL = scratchURL.appendingPathComponent("whisper.cpp", isDirectory: true)
        let outsideURL = scratchURL.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideURL, withIntermediateDirectories: true)
        let executableURL = try makeFile(named: "whisper-cli", in: rootURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: outsideURL, permissions: 0o644)
        let configuration = makeValidatingConfiguration(
            executableURL: executableURL,
            modelURL: modelURL,
            rootDirectoryURL: rootURL
        )
        let validator = TranscriptionConfigurationValidator(
            securityScopedEnvironment: makeValidationEnvironment(
                executableURL: executableURL,
                modelURL: modelURL,
                rootDirectoryURL: rootURL
            ),
            runtimeResolver: ExternalDebugWhisperSettingsRuntimeResolver()
        )

        let result = await validator.validateWhisperCpp(configuration)

        #expect(result.status == .whisperCppRootDirectoryInvalid)
        #expect(result.message.contains("models"))
    }

    private func makeConfiguration() -> WhisperCppTranscriptionConfiguration {
        WhisperCppTranscriptionConfiguration(
            executablePath: "/tmp/whisper-cli",
            modelPath: "/tmp/ggml-small.bin",
            ffmpegExecutablePath: "/tmp/ffmpeg",
            whisperCppRootDirectoryPath: "/tmp",
            whisperCppRootDirectoryBookmarkData: Data([16, 17, 18]),
            executableBookmarkData: Data([1, 2, 3]),
            executableParentDirectoryPath: "/tmp",
            executableParentDirectoryBookmarkData: Data([10, 11, 12]),
            modelBookmarkData: Data([4, 5, 6]),
            ffmpegExecutableBookmarkData: Data([7, 8, 9]),
            ffmpegExecutableParentDirectoryPath: "/tmp",
            ffmpegExecutableParentDirectoryBookmarkData: Data([13, 14, 15]),
            defaultLanguage: "auto",
            preferSegmentOutput: false
        )
    }

    private func makeValidatingConfiguration(
        executableURL: URL,
        modelURL: URL,
        rootDirectoryURL: URL
    ) -> WhisperCppTranscriptionConfiguration {
        WhisperCppTranscriptionConfiguration(
            executablePath: executableURL.path,
            modelPath: modelURL.path,
            ffmpegExecutablePath: nil,
            whisperCppRootDirectoryPath: rootDirectoryURL.path,
            whisperCppRootDirectoryBookmarkData: Data([3]),
            executableBookmarkData: Data([1]),
            modelBookmarkData: Data([2]),
            ffmpegExecutableBookmarkData: nil,
            defaultLanguage: "auto",
            preferSegmentOutput: false
        )
    }

    private func makeValidationEnvironment(
        executableURL: URL,
        modelURL: URL,
        rootDirectoryURL: URL
    ) -> SecurityScopedFileAccessEnvironment {
        SecurityScopedFileAccessEnvironment(
            hasEntitlement: { name in
                switch name {
                case SecurityScopedFileAccess.appSandboxEntitlementName,
                     SecurityScopedFileAccess.appScopeBookmarkEntitlementName,
                     SecurityScopedFileAccess.userSelectedExecutableEntitlementName,
                     SecurityScopedFileAccess.userSelectedReadOnlyEntitlementName:
                    return true
                default:
                    return false
                }
            },
            resolveBookmark: { data in
                switch data {
                case Data([1]):
                    return SecurityScopedBookmarkResolution(url: executableURL, isStale: false)
                case Data([2]):
                    return SecurityScopedBookmarkResolution(url: modelURL, isStale: false)
                case Data([3]):
                    return SecurityScopedBookmarkResolution(url: rootDirectoryURL, isStale: false)
                default:
                    throw CocoaError(.fileReadCorruptFile)
                }
            },
            startAccessing: { _ in true },
            stopAccessing: { _ in }
        )
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
}

private final class InMemoryTranscriptionSettingsDefaults: TranscriptionSettingsDefaults {
    private var storage: [String: Data] = [:]

    func data(forKey defaultName: String) -> Data? {
        storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value as? Data
    }
}

private struct ExternalDebugWhisperSettingsRuntimeResolver: WhisperCppRuntimeResolving {
    func resolveRuntime(configuration: WhisperCppTranscriptionConfiguration) -> WhisperCppRuntimeResolution {
        WhisperCppRuntimeResolution(
            mode: .externalDebugFallback,
            bundledHelperURL: URL(fileURLWithPath: "/missing/RokuricsMac.app/Contents/Helpers/rokurics-whisper"),
            bundledHelperExists: false,
            bundledHelperIsDirectory: false,
            bundledHelperIsExecutable: false,
            executableURL: URL(fileURLWithPath: configuration.normalizedExecutablePath, isDirectory: false)
                .standardizedFileURL,
            currentDirectoryURL: nil
        )
    }
}
