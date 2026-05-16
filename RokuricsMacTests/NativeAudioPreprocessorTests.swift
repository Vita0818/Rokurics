//
//  NativeAudioPreprocessorTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/16.
//

import AVFoundation
import Darwin
import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct NativeAudioPreprocessorTests {
    @Test func whisperProviderPassesNativePreparedWAVPathToWhisperCLI() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let inputURL = scratchURL.appendingPathComponent("inbox-audio.m4a", isDirectory: false)
        let outputDirectoryURL = scratchURL.appendingPathComponent("transcripts", isDirectory: true)
        try makeM4AFixture(at: inputURL)

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let executableBookmark = Data([1])
        let modelBookmark = Data([2])
        let rootBookmark = Data([3])
        let runner = RecordingWhisperProcessRunner()
        let provider = WhisperCppTranscriptionProvider(
            configuration: WhisperCppTranscriptionConfiguration(
                executablePath: executableURL.path,
                modelPath: modelURL.path,
                ffmpegExecutablePath: nil,
                whisperCppRootDirectoryPath: scratchURL.path,
                whisperCppRootDirectoryBookmarkData: rootBookmark,
                executableBookmarkData: executableBookmark,
                modelBookmarkData: modelBookmark,
                ffmpegExecutableBookmarkData: nil,
                defaultLanguage: "zh",
                preferSegmentOutput: false
            ),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                executableBookmark: executableBookmark,
                executableURL: executableURL,
                modelBookmark: modelBookmark,
                modelURL: modelURL,
                rootDirectoryBookmark: rootBookmark,
                rootDirectoryURL: scratchURL
            ),
            processRunner: runner,
            runtimeResolver: ExternalDebugWhisperRuntimeResolver()
        )

        let result = try await provider.transcribe(request: TranscriptionRequest(
            taskID: "task/01",
            recordingID: "recording:01",
            audioFileURL: inputURL,
            metadataFileURL: nil,
            language: "zh",
            prompt: nil,
            outputDirectory: outputDirectoryURL,
            createdAt: Date()
        ))

        let call = try #require(runner.calls.first)
        let fileFlagIndex = try #require(call.arguments.firstIndex(of: "-f"))
        let audioPath = call.arguments[fileFlagIndex + 1]
        let expectedAudioURL = outputDirectoryURL
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent("recording_01-task_01", isDirectory: true)
            .appendingPathComponent("audio.wav", isDirectory: false)
            .standardizedFileURL

        #expect(result.text == "native ok")
        #expect(call.executableURL == executableURL)
        #expect(call.executableURL.isFileURL)
        #expect(call.executableURL.path.hasPrefix("/"))
        #expect(call.currentDirectoryURL == scratchURL)
        #expect(call.authorizationSource == .fileBookmark)
        #expect(audioPath == expectedAudioURL.path)
        #expect(audioPath != inputURL.path)
        #expect(FileManager.default.fileExists(atPath: expectedAudioURL.path))

        let modelFlagIndex = try #require(call.arguments.firstIndex(of: "-m"))
        #expect(call.arguments[modelFlagIndex + 1] == modelURL.path)
        #expect(call.arguments[modelFlagIndex + 1].hasPrefix("/"))

        let outputFlagIndex = try #require(call.arguments.firstIndex(of: "-of"))
        let outputPrefix = outputDirectoryURL
            .appendingPathComponent("whisper-task_01", isDirectory: false)
            .standardizedFileURL
        #expect(call.arguments[outputFlagIndex + 1] == outputPrefix.path)
        #expect(WhisperCppOutputPaths.expectedTextOutputURL(outputPrefix: outputPrefix).path == outputPrefix.path + ".txt")
    }

    @Test func whisperLaunchFailureIncludesProcessExecutableDiagnostics() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let inputURL = try makeFile(named: "audio.wav", in: scratchURL, permissions: 0o644)
        let outputDirectoryURL = scratchURL.appendingPathComponent("transcripts", isDirectory: true)
        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let executableBookmark = Data([1])
        let modelBookmark = Data([2])
        let rootBookmark = Data([3])
        let runner = RecordingWhisperProcessRunner()
        runner.launchError = CocoaError(.fileNoSuchFile)
        let provider = WhisperCppTranscriptionProvider(
            configuration: WhisperCppTranscriptionConfiguration(
                executablePath: executableURL.path,
                modelPath: modelURL.path,
                ffmpegExecutablePath: nil,
                whisperCppRootDirectoryPath: scratchURL.path,
                whisperCppRootDirectoryBookmarkData: rootBookmark,
                executableBookmarkData: executableBookmark,
                modelBookmarkData: modelBookmark,
                ffmpegExecutableBookmarkData: nil,
                defaultLanguage: "zh",
                preferSegmentOutput: false
            ),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                executableBookmark: executableBookmark,
                executableURL: executableURL,
                modelBookmark: modelBookmark,
                modelURL: modelURL,
                rootDirectoryBookmark: rootBookmark,
                rootDirectoryURL: scratchURL
            ),
            processRunner: runner,
            runtimeResolver: ExternalDebugWhisperRuntimeResolver()
        )

        do {
            _ = try await provider.transcribe(request: TranscriptionRequest(
                taskID: "launch-failure",
                recordingID: "recording-01",
                audioFileURL: inputURL,
                metadataFileURL: nil,
                language: "zh",
                prompt: nil,
                outputDirectory: outputDirectoryURL,
                createdAt: Date()
            ))
            Issue.record("Expected whisper-cli launch failure to throw")
        } catch TranscriptionError.processLaunchFailed(let message) {
            #expect(message.contains("stage=whisper-cli process launch"))
            #expect(message.contains("configuredExecutablePath=\(executableURL.path)"))
            #expect(message.contains("restoredAuthorizedExecutableURLPath=\(executableURL.path)"))
            #expect(message.contains("processExecutableURLPath=\(executableURL.path)"))
            #expect(message.contains("processExecutableURLIsAbsolute=true"))
            #expect(message.contains("currentDirectoryURLPath=\(scratchURL.path)"))
            #expect(message.contains("executableBookmarkDataExists=yes"))
            #expect(message.contains("executableBookmarkDataByteCount=1"))
            #expect(message.contains("executableAccessStarted=true"))
            #expect(message.contains("executableAccessMode=file bookmark"))
            #expect(message.contains("modelPath=\(modelURL.path)"))
            #expect(message.contains("modelBookmarkDataExists=yes"))
            #expect(message.contains("modelAccessStarted=true"))
            #expect(message.contains("rootDirectoryPath=\(scratchURL.path)"))
            #expect(message.contains("rootDirectoryBookmarkDataExists=yes"))
            #expect(message.contains("rootDirectoryBookmarkDataByteCount=1"))
            #expect(message.contains("rootDirectoryAccessStarted=true"))
            #expect(message.contains("inputAudioPath=\(inputURL.path)"))
            #expect(message.contains("inputAudioExists=true"))
            #expect(message.contains("outputPrefix=\(outputDirectoryURL.appendingPathComponent("whisper-launch-failure").path)"))
            #expect(message.contains("expectedTxtPath=\(outputDirectoryURL.appendingPathComponent("whisper-launch-failure.txt").path)"))
            #expect(message.contains("nsErrorDomain=NSCocoaErrorDomain"))
            #expect(message.contains("nsErrorCode="))
            #expect(message.contains("description="))
        }
    }

    @Test func whisperProviderRetriesParentDirectoryBookmarkAfterFileBookmarkLaunchFailure() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let inputURL = try makeFile(named: "audio.wav", in: scratchURL, permissions: 0o644)
        let outputDirectoryURL = scratchURL.appendingPathComponent("transcripts", isDirectory: true)
        let binURL = scratchURL.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binURL, withIntermediateDirectories: true)
        let executableURL = try makeFile(named: "whisper-cli", in: binURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let executableBookmark = Data([1])
        let modelBookmark = Data([2])
        let parentBookmark = Data([3])
        let rootBookmark = Data([4])
        var configuration = WhisperCppTranscriptionConfiguration(
            executablePath: executableURL.path,
            modelPath: modelURL.path,
            ffmpegExecutablePath: nil,
            whisperCppRootDirectoryPath: scratchURL.path,
            whisperCppRootDirectoryBookmarkData: rootBookmark,
            executableBookmarkData: executableBookmark,
            modelBookmarkData: modelBookmark,
            ffmpegExecutableBookmarkData: nil,
            defaultLanguage: "zh",
            preferSegmentOutput: false
        )
        configuration.executableParentDirectoryPath = binURL.path
        configuration.executableParentDirectoryBookmarkData = parentBookmark

        let runner = RecordingWhisperProcessRunner()
        runner.failFileBookmarkLaunchOnce = true
        let provider = WhisperCppTranscriptionProvider(
            configuration: configuration,
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                executableBookmark: executableBookmark,
                executableURL: executableURL,
                modelBookmark: modelBookmark,
                modelURL: modelURL,
                parentDirectoryBookmark: parentBookmark,
                parentDirectoryURL: binURL,
                rootDirectoryBookmark: rootBookmark,
                rootDirectoryURL: scratchURL
            ),
            processRunner: runner,
            runtimeResolver: ExternalDebugWhisperRuntimeResolver()
        )

        let result = try await provider.transcribe(request: TranscriptionRequest(
            taskID: "parent-fallback",
            recordingID: "recording-01",
            audioFileURL: inputURL,
            metadataFileURL: nil,
            language: "zh",
            prompt: nil,
            outputDirectory: outputDirectoryURL,
            createdAt: Date()
        ))

        #expect(result.text == "native ok")
        #expect(runner.calls.count == 2)
        #expect(runner.calls[0].authorizationSource == .fileBookmark)
        #expect(runner.calls[0].executableURL == executableURL)
        #expect(runner.calls[1].authorizationSource == .parentDirectoryBookmark)
        #expect(runner.calls[1].executableURL == executableURL.standardizedFileURL)
        #expect(runner.calls[1].scopeURL == binURL)
        #expect(runner.calls[1].currentDirectoryURL == scratchURL)
    }

    @Test func whisperLaunchProbeUsesRootCurrentDirectoryAndHelpArgument() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let executableBookmark = Data([1])
        let modelBookmark = Data([2])
        let rootBookmark = Data([3])
        let accessRecorder = SecurityAccessRecorder()
        let runner = RecordingWhisperProcessRunner()
        runner.output = WhisperCppProcessOutput(exitCode: 0, stdout: "usage: whisper-cli", stderr: "")
        let provider = WhisperCppTranscriptionProvider(
            configuration: WhisperCppTranscriptionConfiguration(
                executablePath: executableURL.path,
                modelPath: modelURL.path,
                ffmpegExecutablePath: nil,
                whisperCppRootDirectoryPath: scratchURL.path,
                whisperCppRootDirectoryBookmarkData: rootBookmark,
                executableBookmarkData: executableBookmark,
                modelBookmarkData: modelBookmark,
                ffmpegExecutableBookmarkData: nil,
                defaultLanguage: "zh",
                preferSegmentOutput: false
            ),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                executableBookmark: executableBookmark,
                executableURL: executableURL,
                modelBookmark: modelBookmark,
                modelURL: modelURL,
                rootDirectoryBookmark: rootBookmark,
                rootDirectoryURL: scratchURL,
                accessRecorder: accessRecorder
            ),
            processRunner: runner,
            runtimeResolver: ExternalDebugWhisperRuntimeResolver()
        )

        let result = await provider.launchHelpProbe()

        let call = try #require(runner.calls.first)
        #expect(result.succeeded)
        #expect(result.processExecutableURLPath == executableURL.path)
        #expect(result.currentDirectoryURLPath == scratchURL.path)
        #expect(result.rootDirectoryAccessStarted)
        #expect(result.stdoutSummary == "usage: whisper-cli")
        #expect(runner.calls.count == 5)
        #expect(call.arguments == ["--help"])
        #expect(call.executableURL == executableURL)
        #expect(call.executableURL.path.hasPrefix("/"))
        #expect(call.currentDirectoryURL == scratchURL)
        #expect(accessRecorder.startedURLs.contains(scratchURL))
        #expect(result.diagnosticMessage.contains("variantsAttempted=bookmarkRestoredURL,fileURLWithRestoredPath,restoredStandardizedFileURL,restoredResolvingSymlinks,configuredStandardizedFileURL"))
        #expect(result.diagnosticMessage.contains("variant.bookmarkRestoredURL.fileManagerFileExists=true"))
        #expect(result.diagnosticMessage.contains("variant.bookmarkRestoredURL.fileManagerIsExecutableFile=true"))
        #expect(result.diagnosticMessage.contains("variant.bookmarkRestoredURL.posixAccessXOKResult=0"))
        #expect(result.diagnosticMessage.contains("variant.bookmarkRestoredURL.posixStatResult=0"))
        #expect(result.diagnosticMessage.contains("variant.bookmarkRestoredURL.posixStatMode="))
    }

    @Test func whisperLaunchProbeFailureIncludesNSErrorDetails() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let executableBookmark = Data([1])
        let modelBookmark = Data([2])
        let rootBookmark = Data([3])
        let runner = RecordingWhisperProcessRunner()
        let underlyingError = NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(EACCES),
            userInfo: [NSLocalizedDescriptionKey: "Permission denied"]
        )
        runner.launchError = NSError(
            domain: NSCocoaErrorDomain,
            code: 4,
            userInfo: [
                NSLocalizedDescriptionKey: "The file “whisper-cli” doesn’t exist.",
                NSFilePathErrorKey: executableURL.path,
                NSUnderlyingErrorKey: underlyingError
            ]
        )
        let provider = WhisperCppTranscriptionProvider(
            configuration: WhisperCppTranscriptionConfiguration(
                executablePath: executableURL.path,
                modelPath: modelURL.path,
                ffmpegExecutablePath: nil,
                whisperCppRootDirectoryPath: scratchURL.path,
                whisperCppRootDirectoryBookmarkData: rootBookmark,
                executableBookmarkData: executableBookmark,
                modelBookmarkData: modelBookmark,
                ffmpegExecutableBookmarkData: nil,
                defaultLanguage: "zh",
                preferSegmentOutput: false
            ),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                executableBookmark: executableBookmark,
                executableURL: executableURL,
                modelBookmark: modelBookmark,
                modelURL: modelURL,
                rootDirectoryBookmark: rootBookmark,
                rootDirectoryURL: scratchURL
            ),
            processRunner: runner,
            runtimeResolver: ExternalDebugWhisperRuntimeResolver()
        )

        let result = await provider.launchHelpProbe()

        #expect(!result.succeeded)
        #expect(result.diagnosticMessage.contains("stage=whisper-cli launch probe variants"))
        #expect(result.diagnosticMessage.contains("variant.bookmarkRestoredURL.executableURLPath=\(executableURL.path)"))
        #expect(result.diagnosticMessage.contains("currentDirectoryURLPath=\(scratchURL.path)"))
        #expect(result.diagnosticMessage.contains("rootDirectoryAccessStarted=true"))
        #expect(result.diagnosticMessage.contains("nsErrorDomain=NSCocoaErrorDomain"))
        #expect(result.diagnosticMessage.contains("nsErrorCode="))
        #expect(result.diagnosticMessage.contains("variant.bookmarkRestoredURL.NSFilePathErrorKey=\(executableURL.path)"))
        #expect(result.diagnosticMessage.contains("variant.bookmarkRestoredURL.underlying.domain=NSPOSIXErrorDomain"))
        #expect(result.diagnosticMessage.contains("variant.bookmarkRestoredURL.underlying.code=\(EACCES)"))
        #expect(result.diagnosticMessage.contains("bookmarkData=") == false)
        #expect(result.diagnosticMessage.contains("sharedSecret") == false)
        #expect(result.diagnosticMessage.contains("HMAC") == false)
        #expect(result.userMessage.contains("NSCocoaErrorDomain"))
    }

    @Test func whisperLaunchProbeTruncatesStdoutAndStderr() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let executableBookmark = Data([1])
        let modelBookmark = Data([2])
        let rootBookmark = Data([3])
        let runner = RecordingWhisperProcessRunner()
        runner.output = WhisperCppProcessOutput(
            exitCode: 0,
            stdout: String(repeating: "s", count: 420),
            stderr: String(repeating: "e", count: 420)
        )
        let provider = WhisperCppTranscriptionProvider(
            configuration: WhisperCppTranscriptionConfiguration(
                executablePath: executableURL.path,
                modelPath: modelURL.path,
                ffmpegExecutablePath: nil,
                whisperCppRootDirectoryPath: scratchURL.path,
                whisperCppRootDirectoryBookmarkData: rootBookmark,
                executableBookmarkData: executableBookmark,
                modelBookmarkData: modelBookmark,
                ffmpegExecutableBookmarkData: nil,
                defaultLanguage: "zh",
                preferSegmentOutput: false
            ),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                executableBookmark: executableBookmark,
                executableURL: executableURL,
                modelBookmark: modelBookmark,
                modelURL: modelURL,
                rootDirectoryBookmark: rootBookmark,
                rootDirectoryURL: scratchURL
            ),
            processRunner: runner,
            runtimeResolver: ExternalDebugWhisperRuntimeResolver()
        )

        let result = await provider.launchHelpProbe()

        #expect(result.succeeded)
        #expect(result.stdoutSummary.count == 303)
        #expect(result.stderrSummary.count == 303)
        #expect(result.stdoutSummary.hasSuffix("..."))
        #expect(result.stderrSummary.hasSuffix("..."))
    }

    @Test func whisperProviderStartsRootDirectoryAccessBeforeLaunchingProcess() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let inputURL = try makeFile(named: "audio.wav", in: scratchURL, permissions: 0o644)
        let outputDirectoryURL = scratchURL.appendingPathComponent("transcripts", isDirectory: true)
        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let executableBookmark = Data([1])
        let modelBookmark = Data([2])
        let rootBookmark = Data([3])
        let accessRecorder = SecurityAccessRecorder()
        let runner = RecordingWhisperProcessRunner()
        let provider = WhisperCppTranscriptionProvider(
            configuration: WhisperCppTranscriptionConfiguration(
                executablePath: executableURL.path,
                modelPath: modelURL.path,
                ffmpegExecutablePath: nil,
                whisperCppRootDirectoryPath: scratchURL.path,
                whisperCppRootDirectoryBookmarkData: rootBookmark,
                executableBookmarkData: executableBookmark,
                modelBookmarkData: modelBookmark,
                ffmpegExecutableBookmarkData: nil,
                defaultLanguage: "zh",
                preferSegmentOutput: false
            ),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                executableBookmark: executableBookmark,
                executableURL: executableURL,
                modelBookmark: modelBookmark,
                modelURL: modelURL,
                rootDirectoryBookmark: rootBookmark,
                rootDirectoryURL: scratchURL,
                accessRecorder: accessRecorder
            ),
            processRunner: runner,
            runtimeResolver: ExternalDebugWhisperRuntimeResolver()
        )

        _ = try await provider.transcribe(request: TranscriptionRequest(
            taskID: "root-access",
            recordingID: "recording-01",
            audioFileURL: inputURL,
            metadataFileURL: nil,
            language: "zh",
            prompt: nil,
            outputDirectory: outputDirectoryURL,
            createdAt: Date()
        ))

        #expect(runner.calls.count == 1)
        #expect(accessRecorder.startedURLs.contains(scratchURL))
    }

    @Test func rootDirectoryAccessFailureIncludesClearDiagnostics() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let inputURL = try makeFile(named: "audio.wav", in: scratchURL, permissions: 0o644)
        let outputDirectoryURL = scratchURL.appendingPathComponent("transcripts", isDirectory: true)
        let executableURL = try makeFile(named: "whisper-cli", in: scratchURL, permissions: 0o755)
        let modelURL = try makeFile(named: "ggml-small.bin", in: scratchURL, permissions: 0o644)
        let executableBookmark = Data([1])
        let modelBookmark = Data([2])
        let rootBookmark = Data([3])
        let accessRecorder = SecurityAccessRecorder(failingURL: scratchURL)
        let runner = RecordingWhisperProcessRunner()
        let provider = WhisperCppTranscriptionProvider(
            configuration: WhisperCppTranscriptionConfiguration(
                executablePath: executableURL.path,
                modelPath: modelURL.path,
                ffmpegExecutablePath: nil,
                whisperCppRootDirectoryPath: scratchURL.path,
                whisperCppRootDirectoryBookmarkData: rootBookmark,
                executableBookmarkData: executableBookmark,
                modelBookmarkData: modelBookmark,
                ffmpegExecutableBookmarkData: nil,
                defaultLanguage: "zh",
                preferSegmentOutput: false
            ),
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                executableBookmark: executableBookmark,
                executableURL: executableURL,
                modelBookmark: modelBookmark,
                modelURL: modelURL,
                rootDirectoryBookmark: rootBookmark,
                rootDirectoryURL: scratchURL,
                accessRecorder: accessRecorder
            ),
            processRunner: runner,
            runtimeResolver: ExternalDebugWhisperRuntimeResolver()
        )

        do {
            _ = try await provider.transcribe(request: TranscriptionRequest(
                taskID: "root-access-failure",
                recordingID: "recording-01",
                audioFileURL: inputURL,
                metadataFileURL: nil,
                language: "zh",
                prompt: nil,
                outputDirectory: outputDirectoryURL,
                createdAt: Date()
            ))
            Issue.record("Expected root directory access failure to throw")
        } catch TranscriptionError.whisperCppRootDirectoryAccessFailed(let message) {
            #expect(message.contains("stage=whisper.cpp root directory access"))
            #expect(message.contains("rootDirectoryPath=\(scratchURL.path)"))
            #expect(message.contains("rootDirectoryBookmarkDataExists=yes"))
            #expect(message.contains("rootDirectoryBookmarkDataByteCount=1"))
            #expect(message.contains("rootDirectoryAccessStarted=false"))
            #expect(runner.calls.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeM4AFixture(at url: URL) throws {
        let sampleRate = 44_100.0
        let frameCount: AVAudioFrameCount = 4_410
        let sourceFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let audioFile = try AVAudioFile(forWriting: url, settings: outputSettings)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount))
        buffer.frameLength = frameCount

        let channelData = try #require(buffer.floatChannelData?[0])
        for frame in 0..<Int(frameCount) {
            let phase = 2.0 * Double.pi * 220.0 * Double(frame) / sampleRate
            channelData[frame] = Float(sin(phase) * 0.2)
        }

        try audioFile.write(from: buffer)
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
        executableBookmark: Data,
        executableURL: URL,
        modelBookmark: Data,
        modelURL: URL,
        parentDirectoryBookmark: Data? = nil,
        parentDirectoryURL: URL? = nil,
        rootDirectoryBookmark: Data? = nil,
        rootDirectoryURL: URL? = nil,
        accessRecorder: SecurityAccessRecorder? = nil
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
                if data == executableBookmark {
                    return SecurityScopedBookmarkResolution(url: executableURL, isStale: false)
                }
                if data == modelBookmark {
                    return SecurityScopedBookmarkResolution(url: modelURL, isStale: false)
                }
                if let parentDirectoryBookmark,
                   data == parentDirectoryBookmark,
                   let parentDirectoryURL {
                    return SecurityScopedBookmarkResolution(url: parentDirectoryURL, isStale: false)
                }
                if let rootDirectoryBookmark,
                   data == rootDirectoryBookmark,
                   let rootDirectoryURL {
                    return SecurityScopedBookmarkResolution(url: rootDirectoryURL, isStale: false)
                }
                throw CocoaError(.fileReadCorruptFile)
            },
            startAccessing: { url in
                accessRecorder?.recordStart(url)
                return accessRecorder?.shouldStartAccessing(url) ?? true
            },
            stopAccessing: { url in
                accessRecorder?.recordStop(url)
            }
        )
    }
}

private final class SecurityAccessRecorder {
    private let failingURL: URL?
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []

    init(failingURL: URL? = nil) {
        self.failingURL = failingURL
    }

    func recordStart(_ url: URL) {
        startedURLs.append(url)
    }

    func recordStop(_ url: URL) {
        stoppedURLs.append(url)
    }

    func shouldStartAccessing(_ url: URL) -> Bool {
        guard let failingURL else {
            return true
        }

        return url != failingURL
    }
}

private final class RecordingWhisperProcessRunner: WhisperCppProcessRunning {
    private(set) var calls: [Call] = []
    var launchError: Error?
    var output = WhisperCppProcessOutput(exitCode: 0, stdout: "", stderr: "")
    var failFileBookmarkLaunchOnce = false
    private var didFailFileBookmarkLaunch = false

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

        if failFileBookmarkLaunchOnce,
           authorizationSource == .fileBookmark,
           !didFailFileBookmarkLaunch {
            didFailFileBookmarkLaunch = true
            throw CocoaError(.fileNoSuchFile)
        }

        if let launchError {
            throw launchError
        }

        if let outputFlagIndex = arguments.firstIndex(of: "-of"),
           arguments.indices.contains(outputFlagIndex + 1) {
            let outputPrefix = URL(fileURLWithPath: arguments[outputFlagIndex + 1], isDirectory: false)
            try "native ok".write(
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

private struct ExternalDebugWhisperRuntimeResolver: WhisperCppRuntimeResolving {
    func resolveRuntime(configuration: WhisperCppTranscriptionConfiguration) -> WhisperCppRuntimeResolution {
        let helperURL = URL(fileURLWithPath: "/missing/RokuricsMac.app/Contents/Helpers/rokurics-whisper", isDirectory: false)
        let executableURL = URL(fileURLWithPath: configuration.normalizedExecutablePath, isDirectory: false)
            .standardizedFileURL
        return WhisperCppRuntimeResolution(
            mode: .externalDebugFallback,
            bundledHelperURL: helperURL,
            bundledHelperExists: false,
            bundledHelperIsDirectory: false,
            bundledHelperIsExecutable: false,
            executableURL: executableURL,
            currentDirectoryURL: nil
        )
    }
}
