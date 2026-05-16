//
//  FFmpegAudioConverter.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/15.
//

import Foundation

struct FFmpegProcessOutput: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol FFmpegProcessRunning {
    func run(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> FFmpegProcessOutput
}

struct FFmpegProcessLaunchContext: Equatable {
    let configuredExecutablePath: String
    let authorizedExecutableURL: URL
    let authorizationSource: SecurityScopedExecutableAuthorizationSource
    let scopeURL: URL
    let processExecutableURL: URL
    let currentDirectoryPath: String
    let bookmarkDataExists: Bool
    let bookmarkDataByteCount: Int
    let parentDirectoryBookmarkDataExists: Bool
    let parentDirectoryBookmarkDataByteCount: Int
    let didStartAccessing: Bool
    let arguments: [String]
}

struct FFmpegAudioConverter: AudioConverting {
    private let executablePath: String
    private let executableBookmarkData: Data?
    private let executableParentDirectoryPath: String?
    private let executableParentDirectoryBookmarkData: Data?
    private let fileManager: FileManager
    private let securityScopedEnvironment: SecurityScopedFileAccessEnvironment
    private let processRunner: any FFmpegProcessRunning
    private let timeout: TimeInterval

    init(
        executablePath: String,
        executableBookmarkData: Data? = nil,
        executableParentDirectoryPath: String? = nil,
        executableParentDirectoryBookmarkData: Data? = nil,
        fileManager: FileManager = .default,
        securityScopedEnvironment: SecurityScopedFileAccessEnvironment = .live,
        processRunner: (any FFmpegProcessRunning)? = nil,
        timeout: TimeInterval = 5 * 60
    ) {
        self.executablePath = (executablePath as NSString).expandingTildeInPath
        self.executableBookmarkData = executableBookmarkData
        self.executableParentDirectoryPath = executableParentDirectoryPath
        self.executableParentDirectoryBookmarkData = executableParentDirectoryBookmarkData
        self.fileManager = fileManager
        self.securityScopedEnvironment = securityScopedEnvironment
        self.processRunner = processRunner ?? LiveFFmpegProcessRunner()
        self.timeout = timeout
    }

    func convertToWhisperWAV(inputURL: URL, outputURL: URL) async throws {
        let executableAccess = try SecurityScopedFileAccess.startAccessingExecutable(
            reference: executableReference,
            errors: Self.ffmpegExecutableErrors,
            fileManager: fileManager,
            environment: securityScopedEnvironment
        )
        defer { executableAccess.stop() }

        let arguments = Self.conversionArguments(inputURL: inputURL, outputURL: outputURL)
        let launchContext = FFmpegProcessLaunchContext(
            configuredExecutablePath: executablePath,
            authorizedExecutableURL: executableAccess.executableURL,
            authorizationSource: executableAccess.authorizationSource,
            scopeURL: executableAccess.scopeURL,
            processExecutableURL: executableAccess.executableURL,
            currentDirectoryPath: fileManager.currentDirectoryPath,
            bookmarkDataExists: executableBookmarkData?.isEmpty == false,
            bookmarkDataByteCount: executableBookmarkData?.count ?? 0,
            parentDirectoryBookmarkDataExists: executableParentDirectoryBookmarkData?.isEmpty == false,
            parentDirectoryBookmarkDataByteCount: executableParentDirectoryBookmarkData?.count ?? 0,
            didStartAccessing: executableAccess.didStartAccessing,
            arguments: arguments
        )
        Self.debugLogProcessStart(context: launchContext)
        let output: FFmpegProcessOutput
        do {
            output = try await processRunner.run(
                executableURL: executableAccess.executableURL,
                arguments: arguments,
                timeout: timeout
            )
        } catch let error as TranscriptionError {
            throw error
        } catch {
            Self.debugLogProcessLaunchFailure(error: error, context: launchContext)
            throw TranscriptionError.audioConversionLaunchFailed(
                Self.processLaunchFailureMessage(error: error, context: launchContext)
            )
        }
        Self.debugLogProcessExit(exitCode: output.exitCode, stdout: output.stdout, stderr: output.stderr)

        guard output.exitCode == 0 else {
            throw TranscriptionError.audioConversionFailed(
                exitCode: output.exitCode,
                message: Self.processFailureMessage(
                    exitCode: output.exitCode,
                    context: launchContext,
                    stdout: output.stdout,
                    stderr: output.stderr
                )
            )
        }
    }

    static func conversionArguments(inputURL: URL, outputURL: URL) -> [String] {
        [
            "-y",
            "-i", inputURL.path,
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            outputURL.path
        ]
    }

    static func validateExecutable(
        atPath path: String,
        bookmarkData: Data? = nil,
        parentDirectoryPath: String? = nil,
        parentDirectoryBookmarkData: Data? = nil,
        fileManager: FileManager = .default,
        securityScopedEnvironment: SecurityScopedFileAccessEnvironment = .live
    ) throws {
        try SecurityScopedFileAccess.validateExecutable(
            reference: SecurityScopedExecutableReference(
                executablePath: path,
                fileBookmarkData: bookmarkData,
                parentDirectoryPath: parentDirectoryPath,
                parentDirectoryBookmarkData: parentDirectoryBookmarkData
            ),
            errors: Self.ffmpegExecutableErrors,
            fileManager: fileManager,
            environment: securityScopedEnvironment
        )
    }

    private var executableReference: SecurityScopedExecutableReference {
        SecurityScopedExecutableReference(
            executablePath: executablePath,
            fileBookmarkData: executableBookmarkData,
            parentDirectoryPath: executableParentDirectoryPath,
            parentDirectoryBookmarkData: executableParentDirectoryBookmarkData
        )
    }

    private static func processFailureMessage(
        exitCode: Int32,
        context: FFmpegProcessLaunchContext,
        stdout: String,
        stderr: String
    ) -> String {
        diagnosticMessage(
            title: "ffmpeg 转码失败",
            fields: [
                ("stage", "ffmpeg conversion"),
                ("exitCode", "\(exitCode)"),
                ("configuredExecutablePath", context.configuredExecutablePath),
                ("restoredAuthorizedURLPath", context.authorizedExecutableURL.path),
                ("authorizationSource", context.authorizationSource.rawValue),
                ("scopeURL", context.scopeURL.path),
                ("processExecutableURLPath", context.processExecutableURL.path),
                ("processExecutableURLIsAbsolute", "\(isAbsoluteFileURL(context.processExecutableURL))"),
                ("processExecutableURLLastPathComponent", context.processExecutableURL.lastPathComponent),
                ("processExecutableURLIsFileURL", "\(context.processExecutableURL.isFileURL)"),
                ("processExecutableURLAbsoluteString", context.processExecutableURL.absoluteString),
                ("bookmarkDataExists", context.bookmarkDataExists ? "yes" : "no"),
                ("bookmarkDataByteCount", "\(context.bookmarkDataByteCount)"),
                ("parentDirectoryBookmark", context.parentDirectoryBookmarkDataExists ? "yes" : "no"),
                ("parentDirectoryBookmarkBytes", "\(context.parentDirectoryBookmarkDataByteCount)"),
                ("accessStarted", "\(context.didStartAccessing)"),
                ("currentDirectoryPath", context.currentDirectoryPath),
                ("arguments", argumentsDescription(context.arguments)),
                ("stdout", limited(stdout.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000)),
                ("stderr", limited(stderr.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000))
            ]
        )
    }

    private static func processLaunchFailureMessage(error: Error, context: FFmpegProcessLaunchContext) -> String {
        let nsError = error as NSError
        return diagnosticMessage(
            title: "ffmpeg 启动失败",
            fields: [
                ("stage", "ffmpeg process launch"),
                ("nsErrorDomain", nsError.domain),
                ("nsErrorCode", "\(nsError.code)"),
                ("description", nsError.localizedDescription),
                ("hint", "请在设置页重新选择 ffmpeg 文件，或选择它的所在文件夹授权"),
                ("configuredExecutablePath", context.configuredExecutablePath),
                ("restoredAuthorizedURLPath", context.authorizedExecutableURL.path),
                ("authorizationSource", context.authorizationSource.rawValue),
                ("scopeURL", context.scopeURL.path),
                ("processExecutableURLPath", context.processExecutableURL.path),
                ("processExecutableURLIsAbsolute", "\(isAbsoluteFileURL(context.processExecutableURL))"),
                ("processExecutableURLLastPathComponent", context.processExecutableURL.lastPathComponent),
                ("processExecutableURLIsFileURL", "\(context.processExecutableURL.isFileURL)"),
                ("processExecutableURLAbsoluteString", context.processExecutableURL.absoluteString),
                ("bookmarkDataExists", context.bookmarkDataExists ? "yes" : "no"),
                ("bookmarkDataByteCount", "\(context.bookmarkDataByteCount)"),
                ("parentDirectoryBookmark", context.parentDirectoryBookmarkDataExists ? "yes" : "no"),
                ("parentDirectoryBookmarkBytes", "\(context.parentDirectoryBookmarkDataByteCount)"),
                ("accessStarted", "\(context.didStartAccessing)"),
                ("currentDirectoryPath", context.currentDirectoryPath),
                ("arguments", argumentsDescription(context.arguments))
            ]
        )
    }

    private static func diagnosticMessage(title: String, fields: [(String, String)]) -> String {
        let fieldText = fields
            .map { key, value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : "\(key)=\(trimmed)"
            }
            .compactMap { $0 }
            .joined(separator: "; ")

        return fieldText.isEmpty ? title : "\(title)：\(fieldText)"
    }

    private static func argumentsDescription(_ arguments: [String]) -> String {
        arguments.joined(separator: " ")
    }

    private static func isAbsoluteFileURL(_ url: URL) -> Bool {
        url.isFileURL && url.path.hasPrefix("/")
    }

    private static func limited(_ string: String, maxCharacters: Int) -> String {
        guard string.count > maxCharacters else {
            return string
        }

        return String(string.prefix(maxCharacters)) + "..."
    }

    private static func debugLogProcessStart(context: FFmpegProcessLaunchContext) {
        #if DEBUG
        print(
            "[Rokurics][FFmpegAudioConverter] run: " +
            "configuredExecutable=\(context.configuredExecutablePath), " +
            "authorizedExecutable=\(context.authorizedExecutableURL.path), " +
            "authorizationSource=\(context.authorizationSource.rawValue), " +
            "scopeURL=\(context.scopeURL.path), " +
            "processExecutableURL=\(context.processExecutableURL.path), " +
            "processExecutableURLIsAbsolute=\(isAbsoluteFileURL(context.processExecutableURL)), " +
            "processExecutableURLIsFileURL=\(context.processExecutableURL.isFileURL), " +
            "processExecutableURLAbsoluteString=\(context.processExecutableURL.absoluteString), " +
            "bookmarkBytes=\(context.bookmarkDataByteCount), " +
            "parentDirectoryBookmarkBytes=\(context.parentDirectoryBookmarkDataByteCount), " +
            "accessStarted=\(context.didStartAccessing), " +
            "currentDirectoryPath=\(context.currentDirectoryPath), " +
            "arguments=\(argumentsDescription(context.arguments))"
        )
        #endif
    }

    private static func debugLogProcessLaunchFailure(error: Error, context: FFmpegProcessLaunchContext) {
        #if DEBUG
        let nsError = error as NSError
        print(
            "[Rokurics][FFmpegAudioConverter] process.run threw: " +
            "configuredExecutable=\(context.configuredExecutablePath), " +
            "authorizedExecutable=\(context.authorizedExecutableURL.path), " +
            "authorizationSource=\(context.authorizationSource.rawValue), " +
            "scopeURL=\(context.scopeURL.path), " +
            "processExecutableURL=\(context.processExecutableURL.path), " +
            "processExecutableURLIsAbsolute=\(isAbsoluteFileURL(context.processExecutableURL)), " +
            "processExecutableURLIsFileURL=\(context.processExecutableURL.isFileURL), " +
            "processExecutableURLAbsoluteString=\(context.processExecutableURL.absoluteString), " +
            "bookmarkBytes=\(context.bookmarkDataByteCount), " +
            "parentDirectoryBookmarkBytes=\(context.parentDirectoryBookmarkDataByteCount), " +
            "accessStarted=\(context.didStartAccessing), " +
            "currentDirectoryPath=\(context.currentDirectoryPath), " +
            "nsErrorDomain=\(nsError.domain), " +
            "nsErrorCode=\(nsError.code), " +
            "localizedDescription=\(nsError.localizedDescription)"
        )
        #endif
    }

    private static func debugLogLiveProcessConfiguration(_ process: Process) {
        #if DEBUG
        let executableURL = process.executableURL
        print(
            "[Rokurics][FFmpegAudioConverter] process.configuration: " +
            "processExecutableURLPath=\(executableURL?.path ?? "nil"), " +
            "processExecutableURLIsFileURL=\(executableURL?.isFileURL ?? false), " +
            "processExecutableURLAbsoluteString=\(executableURL?.absoluteString ?? "nil"), " +
            "currentDirectoryURL=\(process.currentDirectoryURL?.path ?? "nil"), " +
            "currentDirectoryPath=\(FileManager.default.currentDirectoryPath)"
        )
        #endif
    }

    private static func debugLogProcessExit(exitCode: Int32, stdout: String, stderr: String) {
        #if DEBUG
        print(
            "[Rokurics][FFmpegAudioConverter] exit: " +
            "exitCode=\(exitCode), " +
            "stdout=\(limited(stdout.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000)), " +
            "stderr=\(limited(stderr.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000))"
        )
        #endif
    }

    private struct LiveFFmpegProcessRunner: FFmpegProcessRunning {
        func run(executableURL: URL, arguments: [String], timeout: TimeInterval) async throws -> FFmpegProcessOutput {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            FFmpegAudioConverter.debugLogLiveProcessConfiguration(process)

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutCapture = PipeCapture()
            let stderrCapture = PipeCapture()
            let cancellationToken = ProcessCancellationToken()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                stdoutCapture.append(handle.availableData)
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                stderrCapture.append(handle.availableData)
            }

            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let completion = ProcessCompletion()

                    func finish(_ result: Result<FFmpegProcessOutput, Error>) {
                        guard completion.markCompleted() else {
                            return
                        }

                        stdoutPipe.fileHandleForReading.readabilityHandler = nil
                        stderrPipe.fileHandleForReading.readabilityHandler = nil

                        switch result {
                        case .success(let output):
                            continuation.resume(returning: output)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }

                    process.terminationHandler = { terminatedProcess in
                        if cancellationToken.isCancelled {
                            finish(.failure(TranscriptionError.cancelled))
                            return
                        }

                        let output = FFmpegProcessOutput(
                            exitCode: terminatedProcess.terminationStatus,
                            stdout: stdoutCapture.stringValue(),
                            stderr: stderrCapture.stringValue()
                        )
                        finish(.success(output))
                    }

                    do {
                        try process.run()
                    } catch {
                        finish(.failure(error))
                        return
                    }

                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                        guard process.isRunning else {
                            return
                        }

                        process.terminate()
                        finish(.failure(TranscriptionError.audioConversionTimedOut))
                    }
                }
            } onCancel: {
                cancellationToken.cancel()
                if process.isRunning {
                    process.terminate()
                }
            }
        }
    }

    private static let ffmpegExecutableErrors = ExecutableValidationErrors(
        pathMissing: .ffmpegPathMissing,
        notFound: .ffmpegNotFound,
        isDirectory: .ffmpegIsDirectory,
        notExecutable: .ffmpegNotExecutable,
        sandboxAccessDenied: .ffmpegSandboxAccessDenied,
        executableEntitlementMissing: .ffmpegEntitlementMissing,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )

    private final class PipeCapture {
        private let lock = NSLock()
        private let maxBytes = 64 * 1024
        private var data = Data()

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else {
                return
            }

            lock.lock()
            defer { lock.unlock() }

            let remainingBytes = max(0, maxBytes - data.count)
            guard remainingBytes > 0 else {
                return
            }

            data.append(chunk.prefix(remainingBytes))
        }

        func stringValue() -> String {
            lock.lock()
            defer { lock.unlock() }

            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    private final class ProcessCompletion {
        private let lock = NSLock()
        private var completed = false

        func markCompleted() -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard !completed else {
                return false
            }

            completed = true
            return true
        }
    }

    private final class ProcessCancellationToken {
        private let lock = NSLock()
        private var value = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func cancel() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }
}
