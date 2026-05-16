//
//  AudioPreprocessorTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/15.
//

import Darwin
import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct AudioPreprocessorTests {
    @Test func wavInputSkipsConversion() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let audioURL = scratchURL.appendingPathComponent("sample.wav", isDirectory: false)
        let outputDirectoryURL = scratchURL.appendingPathComponent("output", isDirectory: true)
        try Data("wav".utf8).write(to: audioURL)

        let converter = SpyAudioConverter()
        let preprocessor = AudioPreprocessor(
            configuration: AudioPreprocessorConfiguration(ffmpegExecutablePath: nil),
            converter: converter
        )

        let result = try await preprocessor.prepareAudio(
            for: makeRequest(audioFileURL: audioURL, outputDirectory: outputDirectoryURL)
        )

        #expect(result.didConvert == false)
        #expect(result.preparedAudioFileURL == audioURL)
        #expect(result.workingDirectoryURL == nil)
        #expect(converter.calls.isEmpty)
    }

    @Test func m4aInputConvertsIntoTaskWorkingDirectory() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let audioURL = scratchURL.appendingPathComponent("sample.m4a", isDirectory: false)
        let outputDirectoryURL = scratchURL.appendingPathComponent("output", isDirectory: true)
        try Data("m4a".utf8).write(to: audioURL)

        let converter = SpyAudioConverter()
        let preprocessor = AudioPreprocessor(
            configuration: AudioPreprocessorConfiguration(ffmpegExecutablePath: nil),
            converter: converter
        )

        let result = try await preprocessor.prepareAudio(
            for: makeRequest(
                taskID: "task/../01",
                recordingID: "recording:01",
                audioFileURL: audioURL,
                outputDirectory: outputDirectoryURL
            )
        )

        #expect(result.didConvert == true)
        #expect(result.preparedAudioFileURL.lastPathComponent == "audio.wav")
        #expect(result.workingDirectoryURL?.lastPathComponent == "recording_01-task_.._01")
        #expect(result.workingDirectoryURL?.deletingLastPathComponent().lastPathComponent == "working")
        #expect(result.preparedAudioFileURL.path == outputDirectoryURL
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent("recording_01-task_.._01", isDirectory: true)
            .appendingPathComponent("audio.wav", isDirectory: false)
            .standardizedFileURL
            .path)
        #expect(FileManager.default.fileExists(atPath: result.preparedAudioFileURL.path))
        #expect(converter.calls.count == 1)
        #expect(converter.calls.first?.inputURL == audioURL)
        #expect(converter.calls.first?.outputURL == result.preparedAudioFileURL)
    }

    @Test func aacInputRequiresConversion() {
        #expect(AudioPreprocessor.requiresConversion(URL(fileURLWithPath: "/tmp/audio.aac")))
        #expect(AudioPreprocessor.requiresConversion(URL(fileURLWithPath: "/tmp/audio.m4a")))
        #expect(AudioPreprocessor.requiresConversion(URL(fileURLWithPath: "/tmp/audio.mp4")))
        #expect(!AudioPreprocessor.requiresConversion(URL(fileURLWithPath: "/tmp/audio.wav")))
        #expect(!AudioPreprocessor.requiresConversion(URL(fileURLWithPath: "/tmp/audio.wave")))
    }

    @Test func defaultConfigurationUsesNativePreferredStrategy() {
        let configuration = AudioPreprocessorConfiguration(ffmpegExecutablePath: nil)

        #expect(configuration.conversionStrategy == .nativePreferred)
    }

    @Test func nativePreferredValidationDoesNotRequireFFmpeg() {
        let configuration = AudioPreprocessorConfiguration(
            conversionStrategy: .nativePreferred,
            ffmpegExecutablePath: nil
        )
        let preprocessor = AudioPreprocessor(configuration: configuration)

        do {
            try preprocessor.validateConfigurationForConvertibleInput()
        } catch {
            Issue.record("Native preferred preprocessing should not require ffmpeg: \(error)")
        }
    }

    @Test func ffmpegOnlyValidationStillRequiresFFmpeg() {
        let configuration = AudioPreprocessorConfiguration(
            conversionStrategy: .ffmpegOnly,
            ffmpegExecutablePath: nil
        )
        let preprocessor = AudioPreprocessor(configuration: configuration)

        do {
            try preprocessor.validateConfigurationForConvertibleInput()
            Issue.record("Expected ffmpeg-only preprocessing to require ffmpeg")
        } catch TranscriptionError.ffmpegPathMissing,
                TranscriptionError.ffmpegBookmarkMissing,
                TranscriptionError.ffmpegNotFound {
            #expect(true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func nativeConversionMissingOutputHasClearError() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let audioURL = scratchURL.appendingPathComponent("sample.m4a", isDirectory: false)
        let outputDirectoryURL = scratchURL.appendingPathComponent("output", isDirectory: true)
        try Data("m4a".utf8).write(to: audioURL)

        let preprocessor = AudioPreprocessor(
            configuration: AudioPreprocessorConfiguration(ffmpegExecutablePath: nil),
            converter: NoOutputAudioConverter()
        )

        do {
            _ = try await preprocessor.prepareAudio(
                for: makeRequest(audioFileURL: audioURL, outputDirectory: outputDirectoryURL)
            )
            Issue.record("Expected native output validation to throw")
        } catch TranscriptionError.nativeOutputWAVMissing(let message) {
            #expect(message.contains("native audio conversion failed"))
            #expect(message.contains("stage=audio preprocessing"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func ffmpegArgumentsUseWhisperCompatibleWAVSettings() {
        let inputURL = URL(fileURLWithPath: "/tmp/input.m4a")
        let outputURL = URL(fileURLWithPath: "/tmp/output.wav")

        let arguments = FFmpegAudioConverter.conversionArguments(inputURL: inputURL, outputURL: outputURL)

        #expect(arguments == [
            "-y",
            "-i", "/tmp/input.m4a",
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            "/tmp/output.wav"
        ])
    }

    @Test func missingFFmpegPathHasReadableError() {
        do {
            try FFmpegAudioConverter.validateExecutable(atPath: "")
            Issue.record("Expected missing ffmpeg path to throw")
        } catch TranscriptionError.ffmpegPathMissing {
            #expect(TranscriptionError.ffmpegPathMissing.localizedDescription.contains("m4a"))
            #expect(TranscriptionError.ffmpegPathMissing.localizedDescription.contains("ffmpeg"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func whisperConfigurationPassesFFmpegBookmarkDataIntoAudioPreprocessorConfiguration() {
        let bookmarkData = Data([7, 8, 9])
        let parentBookmarkData = Data([10, 11, 12])
        let configuration = WhisperCppTranscriptionConfiguration(
            executablePath: "/tmp/whisper-cli",
            modelPath: "/tmp/ggml-small.bin",
            ffmpegExecutablePath: "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg",
            executableBookmarkData: Data([1]),
            modelBookmarkData: Data([2]),
            ffmpegExecutableBookmarkData: bookmarkData,
            ffmpegExecutableParentDirectoryPath: "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin",
            ffmpegExecutableParentDirectoryBookmarkData: parentBookmarkData,
            defaultLanguage: "auto",
            preferSegmentOutput: false
        )

        #expect(configuration.audioPreprocessorConfiguration.resolvedFFmpegExecutablePath == "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg")
        #expect(configuration.audioPreprocessorConfiguration.ffmpegExecutableBookmarkData == bookmarkData)
        #expect(configuration.audioPreprocessorConfiguration.ffmpegExecutableParentDirectoryPath == "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin")
        #expect(configuration.audioPreprocessorConfiguration.ffmpegExecutableParentDirectoryBookmarkData == parentBookmarkData)
    }

    @Test func ffmpegConverterUsesBookmarkResolvedURLForProcessLaunch() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let configuredURL = scratchURL.appendingPathComponent("configured-ffmpeg", isDirectory: false)
        let authorizedURL = try makeExecutable(named: "authorized-ffmpeg", in: scratchURL)
        let runner = RecordingFFmpegProcessRunner(result: FFmpegProcessOutput(exitCode: 0, stdout: "", stderr: ""))
        let converter = FFmpegAudioConverter(
            executablePath: configuredURL.path,
            executableBookmarkData: Data([1, 2, 3]),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                resolvedURL: authorizedURL,
                startAccessing: { $0 == authorizedURL }
            ),
            processRunner: runner
        )

        try await converter.convertToWhisperWAV(
            inputURL: scratchURL.appendingPathComponent("input.m4a", isDirectory: false),
            outputURL: scratchURL.appendingPathComponent("audio.wav", isDirectory: false)
        )

        #expect(runner.calls.count == 1)
        #expect(runner.calls.first?.executableURL == authorizedURL)
        #expect(runner.calls.first?.executableURL != configuredURL)
        #expect(runner.calls.first?.executableURL.path != authorizedURL.lastPathComponent)
    }

    @Test func ffmpegConverterUsesConfiguredCellarAbsolutePathForProcessLaunch() async throws {
        let ffmpegURL = URL(fileURLWithPath: "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg", isDirectory: false)
        let runner = RecordingFFmpegProcessRunner(result: FFmpegProcessOutput(exitCode: 0, stdout: "", stderr: ""))
        let converter = FFmpegAudioConverter(
            executablePath: ffmpegURL.path,
            executableBookmarkData: Data([1, 2, 3]),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                resolvedURL: ffmpegURL,
                startAccessing: { $0 == ffmpegURL }
            ),
            processRunner: runner
        )

        try await converter.convertToWhisperWAV(
            inputURL: URL(fileURLWithPath: "/tmp/input.m4a", isDirectory: false),
            outputURL: URL(fileURLWithPath: "/tmp/audio.wav", isDirectory: false)
        )

        #expect(runner.calls.count == 1)
        #expect(runner.calls.first?.executableURL.path == "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg")
        #expect(runner.calls.first?.executableURL.path != "ffmpeg")
        #expect(runner.calls.first?.executableURL.path != runner.calls.first?.executableURL.lastPathComponent)
    }

    @Test func ffmpegConverterWithoutBookmarkRequestsFFmpegAuthorization() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeExecutable(named: "ffmpeg", in: scratchURL)
        let runner = RecordingFFmpegProcessRunner(result: FFmpegProcessOutput(exitCode: 0, stdout: "", stderr: ""))
        let converter = FFmpegAudioConverter(
            executablePath: executableURL.path,
            executableBookmarkData: nil,
            processRunner: runner
        )

        do {
            try await converter.convertToWhisperWAV(
                inputURL: scratchURL.appendingPathComponent("input.m4a", isDirectory: false),
                outputURL: scratchURL.appendingPathComponent("audio.wav", isDirectory: false)
            )
            Issue.record("Expected missing ffmpeg bookmark to throw")
        } catch TranscriptionError.ffmpegBookmarkMissing {
            #expect(TranscriptionError.ffmpegBookmarkMissing.localizedDescription.contains("重新选择 ffmpeg"))
            #expect(runner.calls.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func ffmpegConverterFallsBackToParentDirectoryBookmarkForProcessLaunch() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let binURL = scratchURL.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        let executableURL = try makeExecutable(named: "ffmpeg", in: binURL)
        let runner = RecordingFFmpegProcessRunner(result: FFmpegProcessOutput(exitCode: 0, stdout: "", stderr: ""))
        let converter = FFmpegAudioConverter(
            executablePath: executableURL.path,
            executableBookmarkData: nil,
            executableParentDirectoryPath: binURL.path,
            executableParentDirectoryBookmarkData: Data([9, 9, 9]),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                resolvedURL: binURL,
                startAccessing: { $0 == binURL }
            ),
            processRunner: runner
        )

        try await converter.convertToWhisperWAV(
            inputURL: scratchURL.appendingPathComponent("input.m4a", isDirectory: false),
            outputURL: scratchURL.appendingPathComponent("audio.wav", isDirectory: false)
        )

        #expect(runner.calls.count == 1)
        #expect(runner.calls.first?.executableURL == executableURL.standardizedFileURL)
        #expect(runner.calls.first?.executableURL.path != executableURL.lastPathComponent)
    }

    @Test func ffmpegConverterPrefersFileBookmarkOverParentDirectoryBookmark() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let binURL = scratchURL.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        let fileAuthorizedURL = try makeExecutable(named: "file-authorized-ffmpeg", in: scratchURL)
        let executableURL = try makeExecutable(named: "ffmpeg", in: binURL)
        let fileBookmarkData = Data([1, 2, 3])
        let parentBookmarkData = Data([9, 9, 9])
        let runner = RecordingFFmpegProcessRunner(result: FFmpegProcessOutput(exitCode: 0, stdout: "", stderr: ""))
        let converter = FFmpegAudioConverter(
            executablePath: executableURL.path,
            executableBookmarkData: fileBookmarkData,
            executableParentDirectoryPath: binURL.path,
            executableParentDirectoryBookmarkData: parentBookmarkData,
            securityScopedEnvironment: SecurityScopedFileAccessEnvironment(
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
                resolveBookmark: { data in
                    if data == fileBookmarkData {
                        return SecurityScopedBookmarkResolution(url: fileAuthorizedURL, isStale: false)
                    }

                    return SecurityScopedBookmarkResolution(url: binURL, isStale: false)
                },
                startAccessing: { _ in true },
                stopAccessing: { _ in }
            ),
            processRunner: runner
        )

        try await converter.convertToWhisperWAV(
            inputURL: scratchURL.appendingPathComponent("input.m4a", isDirectory: false),
            outputURL: scratchURL.appendingPathComponent("audio.wav", isDirectory: false)
        )

        #expect(runner.calls.count == 1)
        #expect(runner.calls.first?.executableURL == fileAuthorizedURL)
    }

    @Test func ffmpegLaunchFailureIncludesNSErrorDetailsAndNoSecrets() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let authorizedURL = try makeExecutable(named: "authorized-ffmpeg", in: scratchURL)
        let launchError = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileNoSuchFile.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "The file “ffmpeg” doesn’t exist."]
        )
        let runner = RecordingFFmpegProcessRunner(error: launchError)
        let converter = FFmpegAudioConverter(
            executablePath: "/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg",
            executableBookmarkData: Data("secret".utf8),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                resolvedURL: authorizedURL,
                startAccessing: { _ in true }
            ),
            processRunner: runner
        )

        do {
            try await converter.convertToWhisperWAV(
                inputURL: scratchURL.appendingPathComponent("input.m4a", isDirectory: false),
                outputURL: scratchURL.appendingPathComponent("audio.wav", isDirectory: false)
            )
            Issue.record("Expected ffmpeg process launch to throw")
        } catch TranscriptionError.audioConversionLaunchFailed(let message) {
            #expect(message.contains("stage=ffmpeg process launch"))
            #expect(message.contains("configuredExecutablePath=/opt/homebrew/Cellar/ffmpeg/8.1.1/bin/ffmpeg"))
            #expect(message.contains("restoredAuthorizedURLPath=\(authorizedURL.path)"))
            #expect(message.contains("processExecutableURLPath=\(authorizedURL.path)"))
            #expect(message.contains("processExecutableURLIsAbsolute=true"))
            #expect(message.contains("processExecutableURLLastPathComponent=authorized-ffmpeg"))
            #expect(message.contains("bookmarkDataExists=yes"))
            #expect(message.contains("accessStarted=true"))
            #expect(message.contains("nsErrorDomain=\(NSCocoaErrorDomain)"))
            #expect(message.contains("nsErrorCode=\(CocoaError.Code.fileNoSuchFile.rawValue)"))
            #expect(message.contains("The file “ffmpeg” doesn’t exist."))
            #expect(!message.contains("secret"))
            #expect(!message.contains("Data(["))
            #expect(!message.contains("bookmarkData="))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeRequest(
        taskID: String = "task-01",
        recordingID: String = "recording-01",
        audioFileURL: URL,
        outputDirectory: URL
    ) -> TranscriptionRequest {
        TranscriptionRequest(
            taskID: taskID,
            recordingID: recordingID,
            audioFileURL: audioFileURL,
            metadataFileURL: nil,
            language: "zh",
            prompt: nil,
            outputDirectory: outputDirectory,
            createdAt: Date()
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let scratchURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RokuricsMacTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: scratchURL, withIntermediateDirectories: true)
        return scratchURL
    }

    private func makeExecutable(named name: String, in directoryURL: URL) throws -> URL {
        let url = directoryURL.appendingPathComponent(name, isDirectory: false)
        try Data("test".utf8).write(to: url)
        chmod(url.path, 0o755)
        return url
    }

    private func makeSecurityScopedEnvironment(
        resolvedURL: URL,
        startAccessing: @escaping (URL) -> Bool
    ) -> SecurityScopedFileAccessEnvironment {
        SecurityScopedFileAccessEnvironment(
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
            resolveBookmark: { _ in SecurityScopedBookmarkResolution(url: resolvedURL, isStale: false) },
            startAccessing: startAccessing,
            stopAccessing: { _ in }
        )
    }
}

private final class SpyAudioConverter: AudioConverting {
    private(set) var calls: [(inputURL: URL, outputURL: URL)] = []

    func convertToWhisperWAV(inputURL: URL, outputURL: URL) async throws {
        calls.append((inputURL, outputURL))
        try Data("RIFF".utf8).write(to: outputURL)
    }
}

private final class NoOutputAudioConverter: AudioConverting {
    func convertToWhisperWAV(inputURL: URL, outputURL: URL) async throws {}
}

private final class RecordingFFmpegProcessRunner: FFmpegProcessRunning {
    private(set) var calls: [(executableURL: URL, arguments: [String], timeout: TimeInterval)] = []
    private let result: FFmpegProcessOutput?
    private let error: Error?

    init(result: FFmpegProcessOutput) {
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.result = nil
        self.error = error
    }

    func run(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> FFmpegProcessOutput {
        calls.append((executableURL, arguments, timeout))
        if let error {
            throw error
        }

        return try #require(result)
    }
}
