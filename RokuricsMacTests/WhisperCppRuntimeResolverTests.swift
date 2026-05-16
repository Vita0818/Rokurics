//
//  WhisperCppRuntimeResolverTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/16.
//

import Darwin
import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct WhisperCppRuntimeResolverTests {
    @Test func runtimeResolverPrefersBundledHelperWhenItExistsAndIsExecutable() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let bundleURL = scratchURL.appendingPathComponent("RokuricsMac.app", isDirectory: true)
        let helperURL = try makeBundledHelper(in: bundleURL)
        let externalURL = scratchURL.appendingPathComponent("external-whisper-cli", isDirectory: false)
        let configuration = makeConfiguration(executablePath: externalURL.path)

        let resolution = WhisperCppRuntimeResolver(bundleURL: bundleURL).resolveRuntime(
            configuration: configuration
        )

        #expect(resolution.mode == .bundled)
        #expect(resolution.executableURL == helperURL)
        #expect(resolution.currentDirectoryURL == helperURL.deletingLastPathComponent().standardizedFileURL)
        #expect(resolution.bundledHelperExists)
        #expect(resolution.bundledHelperIsExecutable)
    }

    @Test func runtimeResolverFallsBackToExternalDebugConfigWhenBundledHelperIsMissing() throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let bundleURL = scratchURL.appendingPathComponent("RokuricsMac.app", isDirectory: true)
        let externalURL = scratchURL.appendingPathComponent("external-whisper-cli", isDirectory: false)
        let configuration = makeConfiguration(executablePath: externalURL.path)

        let resolution = WhisperCppRuntimeResolver(bundleURL: bundleURL).resolveRuntime(
            configuration: configuration
        )

        #expect(resolution.mode == .externalDebugFallback)
        #expect(resolution.executableURL == externalURL.standardizedFileURL)
        #expect(!resolution.bundledHelperExists)
        #expect(!resolution.bundledHelperIsExecutable)
    }

    @Test func providerUsesBundledHelperAndUserSelectedModelBookmark() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let bundleURL = scratchURL.appendingPathComponent("RokuricsMac.app", isDirectory: true)
        let helperURL = try makeBundledHelper(in: bundleURL)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let inputURL = try makeFile(named: "audio.wav", in: scratchURL, permissions: 0o644)
        let outputDirectoryURL = scratchURL.appendingPathComponent("transcripts", isDirectory: true)
        let modelBookmark = Data([2])
        let runner = RecordingBundledWhisperProcessRunner()
        let runtime = WhisperCppRuntimeResolver(bundleURL: bundleURL).resolveRuntime(
            configuration: makeConfiguration(modelPath: modelURL.path, modelBookmarkData: modelBookmark)
        )
        let provider = WhisperCppTranscriptionProvider(
            configuration: makeConfiguration(modelPath: modelURL.path, modelBookmarkData: modelBookmark),
            securityScopedEnvironment: makeModelSecurityScopedEnvironment(
                modelBookmark: modelBookmark,
                modelURL: modelURL
            ),
            processRunner: runner,
            runtimeResolver: FixedWhisperRuntimeResolver(runtime: runtime)
        )

        let result = try await provider.transcribe(request: TranscriptionRequest(
            taskID: "bundled-helper",
            recordingID: "recording-01",
            audioFileURL: inputURL,
            metadataFileURL: nil,
            language: "zh",
            prompt: nil,
            outputDirectory: outputDirectoryURL,
            createdAt: Date()
        ))

        let call = try #require(runner.calls.first)
        let modelFlagIndex = try #require(call.arguments.firstIndex(of: "-m"))
        #expect(result.text == "bundled ok")
        #expect(call.executableURL == helperURL)
        #expect(call.authorizationSource == .bundledHelper)
        #expect(call.scopeURL == helperURL.deletingLastPathComponent().standardizedFileURL)
        #expect(call.currentDirectoryURL == helperURL.deletingLastPathComponent().standardizedFileURL)
        #expect(call.arguments[modelFlagIndex + 1] == modelURL.path)
    }

    @Test func launchProbeReportsBundledRuntimeMode() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let bundleURL = scratchURL.appendingPathComponent("RokuricsMac.app", isDirectory: true)
        _ = try makeBundledHelper(in: bundleURL)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let modelBookmark = Data([2])
        let configuration = makeConfiguration(modelPath: modelURL.path, modelBookmarkData: modelBookmark)
        let runtime = WhisperCppRuntimeResolver(bundleURL: bundleURL).resolveRuntime(configuration: configuration)
        let runner = RecordingBundledWhisperProcessRunner()
        runner.output = WhisperCppProcessOutput(exitCode: 0, stdout: "usage: rokurics-whisper", stderr: "")
        let provider = WhisperCppTranscriptionProvider(
            configuration: configuration,
            securityScopedEnvironment: makeModelSecurityScopedEnvironment(
                modelBookmark: modelBookmark,
                modelURL: modelURL
            ),
            processRunner: runner,
            runtimeResolver: FixedWhisperRuntimeResolver(runtime: runtime)
        )

        let result = await provider.launchHelpProbe()

        #expect(result.succeeded)
        #expect(result.runtimeMode == .bundled)
        #expect(result.bundledHelperExists)
        #expect(result.userMessage.contains("runtimeMode=bundled"))
        #expect(result.diagnosticMessage.contains("runtimeMode=bundled"))
        #expect(result.processExecutableURLPath == runtime.executableURL.path)
        #expect(runner.calls.first?.arguments == ["--help"])
    }

    @Test func validatorDoesNotRequireExternalExecutableOrRootWhenBundledHelperExists() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let bundleURL = scratchURL.appendingPathComponent("RokuricsMac.app", isDirectory: true)
        _ = try makeBundledHelper(in: bundleURL)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let modelBookmark = Data([2])
        let configuration = makeConfiguration(
            executablePath: "",
            modelPath: modelURL.path,
            modelBookmarkData: modelBookmark
        )
        let runtime = WhisperCppRuntimeResolver(bundleURL: bundleURL).resolveRuntime(configuration: configuration)
        let validator = TranscriptionConfigurationValidator(
            securityScopedEnvironment: makeModelSecurityScopedEnvironment(
                modelBookmark: modelBookmark,
                modelURL: modelURL
            ),
            runtimeResolver: FixedWhisperRuntimeResolver(runtime: runtime)
        )

        let result = await validator.validateWhisperCpp(configuration)

        #expect(result.status == .valid)
        #expect(result.message == "配置有效")
    }

    @Test func bundledLaunchFailureDiagnosticsIncludeRuntimeAndProcessPath() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let bundleURL = scratchURL.appendingPathComponent("RokuricsMac.app", isDirectory: true)
        let helperURL = try makeBundledHelper(in: bundleURL)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let inputURL = try makeFile(named: "audio.wav", in: scratchURL, permissions: 0o644)
        let outputDirectoryURL = scratchURL.appendingPathComponent("transcripts", isDirectory: true)
        let modelBookmark = Data([2])
        let configuration = makeConfiguration(modelPath: modelURL.path, modelBookmarkData: modelBookmark)
        let runtime = WhisperCppRuntimeResolver(bundleURL: bundleURL).resolveRuntime(configuration: configuration)
        let runner = RecordingBundledWhisperProcessRunner()
        runner.launchError = NSError(
            domain: NSCocoaErrorDomain,
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "The file “rokurics-whisper” doesn’t exist."]
        )
        let provider = WhisperCppTranscriptionProvider(
            configuration: configuration,
            securityScopedEnvironment: makeModelSecurityScopedEnvironment(
                modelBookmark: modelBookmark,
                modelURL: modelURL
            ),
            processRunner: runner,
            runtimeResolver: FixedWhisperRuntimeResolver(runtime: runtime)
        )

        do {
            _ = try await provider.transcribe(request: TranscriptionRequest(
                taskID: "bundled-launch-failure",
                recordingID: "recording-01",
                audioFileURL: inputURL,
                metadataFileURL: nil,
                language: "zh",
                prompt: nil,
                outputDirectory: outputDirectoryURL,
                createdAt: Date()
            ))
            Issue.record("Expected bundled helper launch failure to throw")
        } catch TranscriptionError.processLaunchFailed(let message) {
            #expect(message.contains("runtimeMode=bundled"))
            #expect(message.contains("bundledHelperExists=true"))
            #expect(message.contains("processExecutableURLPath=\(helperURL.path)"))
            #expect(message.contains("currentDirectoryURLPath=\(helperURL.deletingLastPathComponent().path)"))
            #expect(message.contains("modelAccessStarted=true"))
            #expect(message.contains("inputAudioPath=\(inputURL.path)"))
            #expect(message.contains("inputAudioExists=true"))
            #expect(message.contains("outputPrefix=\(outputDirectoryURL.appendingPathComponent("whisper-bundled-launch-failure").path)"))
            #expect(message.contains("expectedTxtPath=\(outputDirectoryURL.appendingPathComponent("whisper-bundled-launch-failure.txt").path)"))
            #expect(message.contains("nsErrorDomain=NSCocoaErrorDomain"))
            #expect(message.contains("nsErrorCode=4"))
        }
    }

    private func makeScratchDirectory() throws -> URL {
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        return scratchURL
    }

    private func makeBundledHelper(in bundleURL: URL) throws -> URL {
        let helperURL = WhisperCppRuntimeResolver.bundledHelperURL(bundleURL: bundleURL)
        try FileManager.default.createDirectory(
            at: helperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("helper".utf8).write(to: helperURL)
        chmod(helperURL.path, 0o755)
        return helperURL
    }

    private func makeFile(named name: String, in directoryURL: URL, permissions: mode_t) throws -> URL {
        let url = directoryURL.appendingPathComponent(name, isDirectory: false)
        try Data("test".utf8).write(to: url)
        chmod(url.path, permissions)
        return url
    }

    private func makeConfiguration(
        executablePath: String = "/debug/whisper-cli",
        modelPath: String = "/debug/ggml-small.bin",
        modelBookmarkData: Data? = nil
    ) -> WhisperCppTranscriptionConfiguration {
        WhisperCppTranscriptionConfiguration(
            executablePath: executablePath,
            modelPath: modelPath,
            ffmpegExecutablePath: nil,
            whisperCppRootDirectoryPath: nil,
            whisperCppRootDirectoryBookmarkData: nil,
            executableBookmarkData: nil,
            modelBookmarkData: modelBookmarkData,
            ffmpegExecutableBookmarkData: nil,
            defaultLanguage: "zh",
            preferSegmentOutput: false
        )
    }

    private func makeModelSecurityScopedEnvironment(
        modelBookmark: Data,
        modelURL: URL
    ) -> SecurityScopedFileAccessEnvironment {
        SecurityScopedFileAccessEnvironment(
            hasEntitlement: { name in
                switch name {
                case SecurityScopedFileAccess.appSandboxEntitlementName,
                     SecurityScopedFileAccess.appScopeBookmarkEntitlementName,
                     SecurityScopedFileAccess.userSelectedReadOnlyEntitlementName,
                     SecurityScopedFileAccess.userSelectedExecutableEntitlementName:
                    return true
                default:
                    return false
                }
            },
            resolveBookmark: { data in
                guard data == modelBookmark else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                return SecurityScopedBookmarkResolution(url: modelURL, isStale: false)
            },
            startAccessing: { _ in true },
            stopAccessing: { _ in }
        )
    }
}

private struct FixedWhisperRuntimeResolver: WhisperCppRuntimeResolving {
    let runtime: WhisperCppRuntimeResolution

    func resolveRuntime(configuration: WhisperCppTranscriptionConfiguration) -> WhisperCppRuntimeResolution {
        runtime
    }
}

private final class RecordingBundledWhisperProcessRunner: WhisperCppProcessRunning {
    private(set) var calls: [Call] = []
    var launchError: Error?
    var output = WhisperCppProcessOutput(exitCode: 0, stdout: "", stderr: "")

    func run(
        arguments: [String],
        executableURL: URL,
        authorizationSource: SecurityScopedExecutableAuthorizationSource,
        scopeURL: URL,
        currentDirectoryURL: URL?,
        timeout: TimeInterval
    ) async throws -> WhisperCppProcessOutput {
        calls.append(Call(
            arguments: arguments,
            executableURL: executableURL,
            authorizationSource: authorizationSource,
            scopeURL: scopeURL,
            currentDirectoryURL: currentDirectoryURL
        ))

        if let launchError {
            throw launchError
        }

        if let outputFlagIndex = arguments.firstIndex(of: "-of"),
           arguments.indices.contains(outputFlagIndex + 1) {
            let outputPrefix = URL(fileURLWithPath: arguments[outputFlagIndex + 1], isDirectory: false)
            try "bundled ok".write(
                to: WhisperCppOutputPaths.expectedTextOutputURL(outputPrefix: outputPrefix),
                atomically: true,
                encoding: .utf8
            )
        }

        return output
    }

    struct Call {
        let arguments: [String]
        let executableURL: URL
        let authorizationSource: SecurityScopedExecutableAuthorizationSource
        let scopeURL: URL
        let currentDirectoryURL: URL?
    }
}
