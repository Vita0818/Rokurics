//
//  WhisperCppTranscriptionProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Darwin
import Foundation

enum WhisperCppOutputPaths {
    static func expectedTextOutputURL(outputPrefix: URL) -> URL {
        outputPrefix.appendingPathExtension("txt").standardizedFileURL
    }

    static func alternateWavTextOutputURL(outputPrefix: URL) -> URL {
        URL(fileURLWithPath: outputPrefix.path + ".wav.txt").standardizedFileURL
    }

    static func textOutputCandidates(outputPrefix: URL) -> [URL] {
        [
            expectedTextOutputURL(outputPrefix: outputPrefix),
            alternateWavTextOutputURL(outputPrefix: outputPrefix)
        ]
    }
}

struct WhisperCppProcessOutput: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct WhisperCppLaunchProbeResult: Equatable {
    let succeeded: Bool
    let runtimeMode: WhisperCppRuntimeMode
    let userMessage: String
    let diagnosticMessage: String
    let bundledHelperExists: Bool
    let processExecutableURLPath: String
    let currentDirectoryURLPath: String
    let rootDirectoryAccessStarted: Bool
    let stdoutSummary: String
    let stderrSummary: String
}

protocol WhisperCppProcessRunning {
    func run(
        arguments: [String],
        executableURL: URL,
        authorizationSource: SecurityScopedExecutableAuthorizationSource,
        scopeURL: URL,
        currentDirectoryURL: URL?,
        timeout: TimeInterval
    ) async throws -> WhisperCppProcessOutput
}

private struct WhisperCppProcessExecutionRequest {
    let arguments: [String]
    let executableURL: URL
    let authorizationSource: SecurityScopedExecutableAuthorizationSource
    let scopeURL: URL
    let currentDirectoryURL: URL?
}

private struct WhisperCppLaunchProbeVariant {
    let name: String
    let executableURL: URL
}

private struct WhisperCppLaunchProbeVariantResult {
    let variant: WhisperCppLaunchProbeVariant
    let currentDirectoryURL: URL
    let diagnostics: [(String, String)]
    let output: WhisperCppProcessOutput?
    let error: Error?

    var succeeded: Bool {
        output?.exitCode == 0
    }
}

private struct WhisperCppProcessLaunchContext {
    let runtimeMode: WhisperCppRuntimeMode
    let bundledHelperURL: URL
    let bundledHelperExists: Bool
    let bundledHelperIsExecutable: Bool
    let configuredExecutablePath: String
    let restoredAuthorizedExecutableURL: URL
    let authorizationSource: SecurityScopedExecutableAuthorizationSource
    let scopeURL: URL
    let processExecutableURL: URL
    let currentDirectoryURL: URL?
    let executableBookmarkDataExists: Bool
    let executableBookmarkDataByteCount: Int
    let executableParentDirectoryBookmarkDataExists: Bool
    let executableParentDirectoryBookmarkDataByteCount: Int
    let executableAccessStarted: Bool
    let configuredModelPath: String
    let modelURL: URL
    let modelBookmarkDataExists: Bool
    let modelBookmarkDataByteCount: Int
    let modelAccessStarted: Bool
    let rootDirectoryURL: URL?
    let rootDirectoryConfiguredPath: String
    let rootDirectoryBookmarkDataExists: Bool
    let rootDirectoryBookmarkDataByteCount: Int
    let rootDirectoryAccessStarted: Bool
    let inputAudioURL: URL
    let inputAudioExists: Bool
    let inputAudioSize: Int
    let outputPrefix: URL
    let expectedTextURL: URL
    let arguments: [String]
    let fallbackNote: String?
}

struct WhisperCppTranscriptionProvider: TranscriptionProvider {
    let id = "whisperCpp"
    let displayName = "whisper.cpp"

    private let configuration: WhisperCppTranscriptionConfiguration
    private let fileManager: FileManager
    private let securityScopedEnvironment: SecurityScopedFileAccessEnvironment
    private let timeout: TimeInterval
    private let processRunner: (any WhisperCppProcessRunning)?
    private let runtimeResolver: any WhisperCppRuntimeResolving

    init(
        configuration: WhisperCppTranscriptionConfiguration,
        fileManager: FileManager = .default,
        securityScopedEnvironment: SecurityScopedFileAccessEnvironment = .live,
        timeout: TimeInterval = 30 * 60,
        processRunner: (any WhisperCppProcessRunning)? = nil,
        runtimeResolver: (any WhisperCppRuntimeResolving)? = nil
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.securityScopedEnvironment = securityScopedEnvironment
        self.timeout = timeout
        self.processRunner = processRunner
        self.runtimeResolver = runtimeResolver ?? WhisperCppRuntimeResolver(fileManager: fileManager)
    }

    func validateConfiguration() async throws {
        let runtime = resolveRuntime()
        try validateRuntime(runtime)
        try validateModel()
        try validateDefaultOutputDirectory()
    }

    func validateAudioPreprocessingForConvertibleInput() throws {
        try audioPreprocessor().validateConfigurationForConvertibleInput()
    }

    func launchHelpProbe() async -> WhisperCppLaunchProbeResult {
        let runtime = resolveRuntime()
        if runtime.mode == .bundled {
            return await launchBundledHelpProbe(runtime: runtime)
        }

        let rootAccess: SecurityScopedResourceAccess
        do {
            rootAccess = try startAccessingWhisperCppRootDirectoryForTranscription()
        } catch {
            let diagnostic = Self.launchProbeAccessFailureMessage(
                stage: "whisper.cpp root directory access",
                configuration: configuration,
                runtime: runtime,
                error: error
            )
            Self.debugLogLaunchProbe(diagnostic)
            return Self.launchProbeResult(
                succeeded: false,
                runtime: runtime,
                configuration: configuration,
                executableAccess: nil,
                rootAccess: nil,
                output: nil,
                error: error,
                diagnosticMessage: diagnostic
            )
        }
        defer { rootAccess.stop() }

        let modelAccess: SecurityScopedResourceAccess?
        let modelAccessError: Error?
        do {
            modelAccess = try SecurityScopedFileAccess.startAccessingReadableFile(
                reference: configuration.modelFileReference,
                errors: Self.modelFileErrors,
                fileManager: fileManager,
                environment: securityScopedEnvironment
            )
            modelAccessError = nil
        } catch {
            modelAccess = nil
            modelAccessError = error
        }
        defer { modelAccess?.stop() }

        let executableAccess: SecurityScopedExecutableAccess
        do {
            executableAccess = try SecurityScopedFileAccess.startAccessingExecutable(
                reference: configuration.executableReference,
                errors: Self.whisperExecutableErrors,
                fileManager: fileManager,
                environment: securityScopedEnvironment
            )
        } catch {
            let diagnostic = Self.launchProbeAccessFailureMessage(
                stage: "whisper-cli executable access",
                configuration: configuration,
                runtime: runtime,
                rootAccess: rootAccess,
                error: error
            )
            Self.debugLogLaunchProbe(diagnostic)
            return Self.launchProbeResult(
                succeeded: false,
                runtime: runtime,
                configuration: configuration,
                executableAccess: nil,
                rootAccess: rootAccess,
                output: nil,
                error: error,
                diagnosticMessage: diagnostic
            )
        }
        defer { executableAccess.stop() }

        let currentDirectoryURL = launchCurrentDirectoryURL(
            rootAccess: rootAccess,
            executableURL: executableAccess.executableURL
        )
        let variants = launchProbeVariants(restoredExecutableURL: executableAccess.executableURL)
        var results: [WhisperCppLaunchProbeVariantResult] = []

        for variant in variants {
            let result = await runLaunchProbeVariant(
                variant,
                executableAccess: executableAccess,
                rootAccess: rootAccess,
                modelAccess: modelAccess,
                modelAccessError: modelAccessError,
                currentDirectoryURL: currentDirectoryURL
            )
            results.append(result)
        }

        let diagnostic = Self.launchProbeVariantsMessage(
            configuration: configuration,
            runtime: runtime,
            executableAccess: executableAccess,
            rootAccess: rootAccess,
            modelAccess: modelAccess,
            modelAccessError: modelAccessError,
            currentDirectoryURL: currentDirectoryURL,
            results: results
        )
        Self.debugLogLaunchProbe(diagnostic)
        return Self.launchProbeResult(
            configuration: configuration,
            runtime: runtime,
            executableAccess: executableAccess,
            rootAccess: rootAccess,
            results: results,
            diagnosticMessage: diagnostic
        )
    }

    private func launchBundledHelpProbe(runtime: WhisperCppRuntimeResolution) async -> WhisperCppLaunchProbeResult {
        let modelAccess: SecurityScopedResourceAccess?
        let modelAccessError: Error?
        do {
            modelAccess = try SecurityScopedFileAccess.startAccessingReadableFile(
                reference: configuration.modelFileReference,
                errors: Self.modelFileErrors,
                fileManager: fileManager,
                environment: securityScopedEnvironment
            )
            modelAccessError = nil
        } catch {
            modelAccess = nil
            modelAccessError = error
        }
        defer { modelAccess?.stop() }

        let currentDirectoryURL = runtime.currentDirectoryURL
            ?? runtime.executableURL.deletingLastPathComponent().standardizedFileURL
        let request = WhisperCppProcessExecutionRequest(
            arguments: ["--help"],
            executableURL: runtime.executableURL,
            authorizationSource: .bundledHelper,
            scopeURL: currentDirectoryURL,
            currentDirectoryURL: currentDirectoryURL
        )

        do {
            let output = try await runProcess(request: request, timeout: min(timeout, 10))
            let diagnostic = Self.bundledLaunchProbeMessage(
                runtime: runtime,
                configuration: configuration,
                modelAccess: modelAccess,
                modelAccessError: modelAccessError,
                currentDirectoryURL: currentDirectoryURL,
                output: output,
                error: nil
            )
            Self.debugLogLaunchProbe(diagnostic)
            return Self.launchProbeResult(
                succeeded: output.exitCode == 0,
                runtime: runtime,
                currentDirectoryURL: currentDirectoryURL,
                rootDirectoryAccessStarted: false,
                output: output,
                error: nil,
                diagnosticMessage: diagnostic
            )
        } catch {
            let diagnostic = Self.bundledLaunchProbeMessage(
                runtime: runtime,
                configuration: configuration,
                modelAccess: modelAccess,
                modelAccessError: modelAccessError,
                currentDirectoryURL: currentDirectoryURL,
                output: nil,
                error: error
            )
            Self.debugLogLaunchProbe(diagnostic)
            return Self.launchProbeResult(
                succeeded: false,
                runtime: runtime,
                currentDirectoryURL: currentDirectoryURL,
                rootDirectoryAccessStarted: false,
                output: nil,
                error: error,
                diagnosticMessage: diagnostic
            )
        }
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult {
        try Task.checkCancellation()
        debugLogRequest(request)
        let runtime = resolveRuntime()
        switch runtime.mode {
        case .bundled:
            try validateBundledHelper(runtime)
        case .externalDebugFallback:
            try validateExecutable()
        }
        try validateModel()
        try validateDefaultOutputDirectory()
        try validateAudioFile(request.audioFileURL)
        try validateOutputDirectory(request.outputDirectory)

        let startedAt = Date()
        let preparedAudio = try await audioPreprocessor().prepareAudio(for: request)
        debugLogPreparedAudio(preparedAudio)

        var rootAccess: SecurityScopedResourceAccess?
        var executableAccess: SecurityScopedExecutableAccess?
        if runtime.mode == .externalDebugFallback {
            let startedRootAccess = try startAccessingWhisperCppRootDirectoryForTranscription()
            rootAccess = startedRootAccess
            do {
                executableAccess = try SecurityScopedFileAccess.startAccessingExecutable(
                    reference: configuration.executableReference,
                    errors: Self.whisperExecutableErrors,
                    fileManager: fileManager,
                    environment: securityScopedEnvironment
                )
            } catch {
                startedRootAccess.stop()
                throw error
            }
        }

        let modelAccess: SecurityScopedResourceAccess
        do {
            modelAccess = try SecurityScopedFileAccess.startAccessingReadableFile(
                reference: configuration.modelFileReference,
                errors: Self.modelFileErrors,
                fileManager: fileManager,
                environment: securityScopedEnvironment
            )
        } catch {
            executableAccess?.stop()
            rootAccess?.stop()
            throw error
        }
        defer {
            modelAccess.stop()
            executableAccess?.stop()
            rootAccess?.stop()
        }

        let outputPrefix = try outputPrefixURL(for: request)
        let arguments = whisperArguments(
            audioFileURL: preparedAudio.preparedAudioFileURL,
            modelURL: modelAccess.url,
            outputPrefix: outputPrefix,
            language: request.language ?? configuration.normalizedLanguage,
            chunk: request.chunkDescriptor,
            appliesChunkTimingInWhisper: !preparedAudio.didConvert
        )
        let processTimeout = transcriptionTimeout(for: request)
        let expectedTextURL = WhisperCppOutputPaths.expectedTextOutputURL(outputPrefix: outputPrefix)
        let launchContext: WhisperCppProcessLaunchContext
        if let executableAccess, let rootAccess {
            launchContext = makeProcessLaunchContext(
                runtime: runtime,
                executableAccess: executableAccess,
                modelAccess: modelAccess,
                rootAccess: rootAccess,
                audioFileURL: preparedAudio.preparedAudioFileURL,
                arguments: arguments,
                outputPrefix: outputPrefix,
                expectedTextURL: expectedTextURL,
                fallbackNote: nil
            )
        } else {
            launchContext = makeBundledProcessLaunchContext(
                runtime: runtime,
                modelAccess: modelAccess,
                audioFileURL: preparedAudio.preparedAudioFileURL,
                arguments: arguments,
                outputPrefix: outputPrefix,
                expectedTextURL: expectedTextURL
            )
        }
        debugLogWhisperProcessStart(context: launchContext)

        let output: WhisperCppProcessOutput
        if runtime.mode == .externalDebugFallback {
            output = try await runWhisperProcessWithParentDirectoryFallback(
                initialContext: launchContext,
                timeout: processTimeout
            )
        } else {
            output = try await runWhisperProcess(context: launchContext, timeout: processTimeout)
        }
        debugLogWhisperProcessExit(exitCode: output.exitCode, stdout: output.stdout, stderr: output.stderr)
        try Task.checkCancellation()

        guard output.exitCode == 0 else {
            throw TranscriptionError.processFailed(
                exitCode: output.exitCode,
                message: processFailureMessage(
                    exitCode: output.exitCode,
                    stdout: output.stdout,
                    stderr: output.stderr,
                    context: launchContext
                )
            )
        }

        let text = try readTextOutput(outputPrefix: outputPrefix, context: launchContext)
        let segments = configuration.preferSegmentOutput ? readSegmentsIfAvailable(outputPrefix: outputPrefix) : []

        return TranscriptionResult(
            taskID: request.taskID,
            recordingID: request.recordingID,
            providerID: id,
            providerName: displayName,
            modelName: configuration.modelFileName,
            language: request.language ?? configuration.normalizedLanguage,
            text: text,
            segments: segments,
            startedAt: startedAt,
            completedAt: Date(),
            status: "transcribed"
        )
    }

    private func validateExecutable() throws {
        try SecurityScopedFileAccess.validateExecutable(
            reference: configuration.executableReference,
            errors: Self.whisperExecutableErrors,
            fileManager: fileManager,
            environment: securityScopedEnvironment
        )
    }

    private func resolveRuntime() -> WhisperCppRuntimeResolution {
        runtimeResolver.resolveRuntime(configuration: configuration)
    }

    private func validateRuntime(_ runtime: WhisperCppRuntimeResolution) throws {
        switch runtime.mode {
        case .bundled:
            try validateBundledHelper(runtime)
        case .externalDebugFallback:
            try validateExecutable()
            try validateWhisperCppRootDirectory()
        }
    }

    private func validateBundledHelper(_ runtime: WhisperCppRuntimeResolution) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: runtime.bundledHelperURL.path, isDirectory: &isDirectory) else {
            throw TranscriptionError.executableNotFound
        }
        guard !isDirectory.boolValue else {
            throw TranscriptionError.executableIsDirectory
        }
        guard fileManager.isExecutableFile(atPath: runtime.bundledHelperURL.path) else {
            throw TranscriptionError.executableNotExecutable
        }
    }

    private func validateModel() throws {
        try SecurityScopedFileAccess.validateReadableFile(
            reference: configuration.modelFileReference,
            errors: Self.modelFileErrors,
            fileManager: fileManager,
            environment: securityScopedEnvironment
        )
    }

    private func validateWhisperCppRootDirectory() throws {
        let access = try SecurityScopedFileAccess.startAccessingReadableDirectory(
            reference: configuration.whisperCppRootDirectoryReference,
            errors: Self.whisperCppRootDirectoryErrors,
            fileManager: fileManager,
            environment: securityScopedEnvironment
        )
        defer { access.stop() }

        try validateWhisperCppRootDirectoryContents(access.url)
    }

    private func startAccessingWhisperCppRootDirectoryForTranscription() throws -> SecurityScopedResourceAccess {
        do {
            let access = try SecurityScopedFileAccess.startAccessingReadableDirectory(
                reference: configuration.whisperCppRootDirectoryReference,
                errors: Self.whisperCppRootDirectoryErrors,
                fileManager: fileManager,
                environment: securityScopedEnvironment
            )
            do {
                try validateWhisperCppRootDirectoryContents(access.url)
                return access
            } catch {
                access.stop()
                throw error
            }
        } catch {
            throw TranscriptionError.whisperCppRootDirectoryAccessFailed(
                rootDirectoryAccessFailureMessage(error: error)
            )
        }
    }

    private func validateWhisperCppRootDirectoryContents(_ rootURL: URL) throws {
        let rootDirectoryURL = rootURL.standardizedFileURL
        let executableURL = URL(fileURLWithPath: configuration.normalizedExecutablePath, isDirectory: false)
            .standardizedFileURL
        let modelURL = URL(fileURLWithPath: configuration.normalizedModelPath, isDirectory: false)
            .standardizedFileURL
        let defaultExecutableURL = rootDirectoryURL
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("whisper-cli", isDirectory: false)
            .standardizedFileURL
        let modelsURL = rootDirectoryURL
            .appendingPathComponent("models", isDirectory: true)
            .standardizedFileURL

        let executableInsideRoot = isInside(executableURL, parent: rootDirectoryURL)
        let defaultExecutableExists = fileExists(defaultExecutableURL, isDirectory: false)
        guard executableInsideRoot || defaultExecutableExists else {
            throw TranscriptionError.whisperCppRootDirectoryInvalid(
                "whisper.cpp 根目录结构不完整：缺少 build/bin/whisper-cli，且当前 whisper-cli 不在根目录内。rootDirectory=\(rootDirectoryURL.path); configuredExecutablePath=\(executableURL.path)"
            )
        }

        let modelInsideRoot = isInside(modelURL, parent: rootDirectoryURL)
        let modelsDirectoryExists = fileExists(modelsURL, isDirectory: true)
        guard modelInsideRoot || modelsDirectoryExists else {
            throw TranscriptionError.whisperCppRootDirectoryInvalid(
                "whisper.cpp 根目录结构不完整：缺少 models 目录，且当前模型不在根目录内。rootDirectory=\(rootDirectoryURL.path); configuredModelPath=\(modelURL.path)"
            )
        }
    }

    private func rootDirectoryAccessFailureMessage(error: Error) -> String {
        let nsError = error as NSError
        var fields: [(String, String)] = [
            ("stage", "whisper.cpp root directory access"),
            ("rootDirectoryPath", configuration.normalizedWhisperCppRootDirectoryPath),
            ("rootDirectoryBookmarkDataExists", Self.yesNo(configuration.whisperCppRootDirectoryBookmarkData?.isEmpty == false)),
            ("rootDirectoryBookmarkDataByteCount", "\(configuration.whisperCppRootDirectoryBookmarkData?.count ?? 0)"),
            ("rootDirectoryAccessStarted", "false"),
            ("message", error.localizedDescription),
            ("nsErrorDomain", nsError.domain),
            ("nsErrorCode", "\(nsError.code)"),
            ("description", nsError.localizedDescription)
        ]
        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            fields.append(("failureReason", failureReason))
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            fields.append(("recoverySuggestion", recoverySuggestion))
        }

        return Self.diagnosticMessage(title: "whisper.cpp 根目录授权失败", fields: fields)
    }

    private func validateDefaultOutputDirectory() throws {
        let outputURL = MacAppStorageProfile.applicationSupportRootURL(fileManager: fileManager)
            .appendingPathComponent("transcripts", isDirectory: true)
            .appendingPathComponent(".configuration-check", isDirectory: true)
            .standardizedFileURL

        try validateWritableDirectory(outputURL)
    }

    private func validateAudioFile(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw TranscriptionError.audioFileMissing
        }
    }

    private func validateOutputDirectory(_ url: URL) throws {
        try validateWritableDirectory(url.standardizedFileURL)
    }

    private func validateWritableDirectory(_ url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw TranscriptionError.outputDirectoryUnavailable
            }

            let probeURL = url.appendingPathComponent(".rokurics-write-check-\(UUID().uuidString)", isDirectory: false)
            try Data().write(to: probeURL, options: .atomic)
            try? fileManager.removeItem(at: probeURL)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.outputDirectoryNotWritable
        }
    }

    private func audioPreprocessor() -> AudioPreprocessor {
        AudioPreprocessor(
            configuration: configuration.audioPreprocessorConfiguration,
            fileManager: fileManager,
            securityScopedEnvironment: securityScopedEnvironment
        )
    }

    private func launchCurrentDirectoryURL(
        rootAccess: SecurityScopedResourceAccess?,
        executableURL: URL
    ) -> URL {
        if let rootURL = rootAccess?.url.standardizedFileURL {
            return rootURL
        }

        return executableURL.deletingLastPathComponent().standardizedFileURL
    }

    private func launchProbeVariants(restoredExecutableURL: URL) -> [WhisperCppLaunchProbeVariant] {
        [
            WhisperCppLaunchProbeVariant(
                name: "bookmarkRestoredURL",
                executableURL: restoredExecutableURL
            ),
            WhisperCppLaunchProbeVariant(
                name: "fileURLWithRestoredPath",
                executableURL: URL(fileURLWithPath: restoredExecutableURL.path, isDirectory: false)
            ),
            WhisperCppLaunchProbeVariant(
                name: "restoredStandardizedFileURL",
                executableURL: restoredExecutableURL.standardizedFileURL
            ),
            WhisperCppLaunchProbeVariant(
                name: "restoredResolvingSymlinks",
                executableURL: restoredExecutableURL.resolvingSymlinksInPath()
            ),
            WhisperCppLaunchProbeVariant(
                name: "configuredStandardizedFileURL",
                executableURL: URL(
                    fileURLWithPath: configuration.normalizedExecutablePath,
                    isDirectory: false
                ).standardizedFileURL
            )
        ]
    }

    private func runLaunchProbeVariant(
        _ variant: WhisperCppLaunchProbeVariant,
        executableAccess: SecurityScopedExecutableAccess,
        rootAccess: SecurityScopedResourceAccess,
        modelAccess: SecurityScopedResourceAccess?,
        modelAccessError: Error?,
        currentDirectoryURL: URL
    ) async -> WhisperCppLaunchProbeVariantResult {
        let diagnostics = launchProbeVariantDiagnostics(
            variant: variant,
            executableAccess: executableAccess,
            rootAccess: rootAccess,
            modelAccess: modelAccess,
            modelAccessError: modelAccessError,
            currentDirectoryURL: currentDirectoryURL
        )
        let request = WhisperCppProcessExecutionRequest(
            arguments: ["--help"],
            executableURL: variant.executableURL,
            authorizationSource: executableAccess.authorizationSource,
            scopeURL: executableAccess.scopeURL,
            currentDirectoryURL: currentDirectoryURL
        )

        do {
            let output = try await runProcess(request: request, timeout: min(timeout, 10))
            return WhisperCppLaunchProbeVariantResult(
                variant: variant,
                currentDirectoryURL: currentDirectoryURL,
                diagnostics: diagnostics,
                output: output,
                error: nil
            )
        } catch {
            return WhisperCppLaunchProbeVariantResult(
                variant: variant,
                currentDirectoryURL: currentDirectoryURL,
                diagnostics: diagnostics,
                output: nil,
                error: error
            )
        }
    }

    private func launchProbeVariantDiagnostics(
        variant: WhisperCppLaunchProbeVariant,
        executableAccess: SecurityScopedExecutableAccess,
        rootAccess: SecurityScopedResourceAccess,
        modelAccess: SecurityScopedResourceAccess?,
        modelAccessError: Error?,
        currentDirectoryURL: URL
    ) -> [(String, String)] {
        var currentDirectoryIsDirectory: ObjCBool = false
        let currentDirectoryExists = fileManager.fileExists(
            atPath: currentDirectoryURL.path,
            isDirectory: &currentDirectoryIsDirectory
        )
        let resourceReachability = Self.resourceReachabilityDescription(variant.executableURL)
        let executableStat = Self.posixStatDescription(path: variant.executableURL.path)
        let executableAccessCheck = Self.posixAccessDescription(path: variant.executableURL.path)

        var fields: [(String, String)] = [
            ("variant", variant.name),
            ("executablePathString", configuration.normalizedExecutablePath),
            ("executableURLPath", variant.executableURL.path),
            ("executableURLAbsoluteString", variant.executableURL.absoluteString),
            ("executableURLIsFileURL", "\(variant.executableURL.isFileURL)"),
            ("executableURLStandardizedPath", variant.executableURL.standardizedFileURL.path),
            ("executableURLResolvingSymlinksPath", variant.executableURL.resolvingSymlinksInPath().path),
            ("restoredAuthorizedExecutableURLPath", executableAccess.executableURL.path),
            ("processExecutableURLFinalPath", variant.executableURL.path),
            ("processArguments", "--help"),
            ("processCurrentDirectoryURLPath", currentDirectoryURL.path),
            ("currentDirectoryURLPath", currentDirectoryURL.path),
            ("currentDirectoryExists", "\(currentDirectoryExists)"),
            ("currentDirectoryIsDirectory", "\(currentDirectoryIsDirectory.boolValue)"),
            ("currentDirectoryIsReadable", "\(fileManager.isReadableFile(atPath: currentDirectoryURL.path))"),
            ("rootDirectoryPath", rootAccess.url.path),
            ("rootDirectoryAccessStarted", "\(rootAccess.didStartAccessing)"),
            ("executableAccessStarted", "\(executableAccess.didStartAccessing)"),
            ("executableAccessMode", Self.executableAccessModeDescription(executableAccess.authorizationSource)),
            ("modelPath", modelAccess?.url.path ?? configuration.normalizedModelPath),
            ("modelAccessStarted", "\(modelAccess?.didStartAccessing ?? false)"),
            ("fileManagerFileExists", "\(fileManager.fileExists(atPath: variant.executableURL.path))"),
            ("fileManagerIsExecutableFile", "\(fileManager.isExecutableFile(atPath: variant.executableURL.path))"),
            ("checkResourceIsReachable", resourceReachability.reachable),
            ("checkResourceIsReachableError", resourceReachability.errorDescription),
            ("posixAccessXOKResult", executableAccessCheck.result),
            ("posixAccessXOKErrno", executableAccessCheck.errno),
            ("posixAccessXOKErrnoDescription", executableAccessCheck.errnoDescription),
            ("posixStatResult", executableStat.result),
            ("posixStatErrno", executableStat.errno),
            ("posixStatErrnoDescription", executableStat.errnoDescription),
            ("posixStatMode", executableStat.mode),
            ("posixStatUID", executableStat.uid),
            ("posixStatGID", executableStat.gid)
        ]

        if let modelAccessError {
            fields.append(("modelAccessError", modelAccessError.localizedDescription))
            fields.append(contentsOf: Self.errorDiagnosticFields(error: modelAccessError, prefix: "modelAccess"))
        }

        return fields
    }

    private func outputPrefixURL(for request: TranscriptionRequest) throws -> URL {
        let safeTaskID = sanitizedPathComponent(request.taskID)
        guard !safeTaskID.isEmpty else {
            throw TranscriptionError.outputDirectoryUnavailable
        }

        let outputDirectory = request.outputDirectory.standardizedFileURL
        let outputPrefix = outputDirectory
            .appendingPathComponent("whisper-\(safeTaskID)", isDirectory: false)
            .standardizedFileURL

        guard isInside(outputPrefix, parent: outputDirectory) else {
            throw TranscriptionError.outputDirectoryUnavailable
        }

        return outputPrefix
    }

    private func whisperArguments(
        audioFileURL: URL,
        modelURL: URL,
        outputPrefix: URL,
        language: String,
        chunk: AudioChunkDescriptor?,
        appliesChunkTimingInWhisper: Bool
    ) -> [String] {
        var arguments = [
            "-m", modelURL.path,
            "-f", audioFileURL.path,
            "-l", normalizedLanguageArgument(language),
            "-otxt"
        ]

        if configuration.preferSegmentOutput {
            arguments.append("-oj")
        }

        if let chunk, appliesChunkTimingInWhisper {
            arguments.append(contentsOf: [
                "--offset-t", Self.timeArgument(chunk.startTime),
                "--duration", Self.timeArgument(chunk.duration)
            ])
        }

        arguments.append(contentsOf: ["-of", outputPrefix.path])
        return arguments
    }

    private func transcriptionTimeout(for request: TranscriptionRequest) -> TimeInterval {
        let audioDuration = request.chunkDescriptor?.duration ?? request.sourceDuration
        return max(
            timeout,
            WhisperTranscriptionTimeoutPolicy.timeout(
                audioDuration: audioDuration,
                modelKind: configuration.modelKind
            )
        )
    }

    private func makeProcessLaunchContext(
        runtime: WhisperCppRuntimeResolution,
        executableAccess: SecurityScopedExecutableAccess,
        modelAccess: SecurityScopedResourceAccess,
        rootAccess: SecurityScopedResourceAccess,
        audioFileURL: URL,
        arguments: [String],
        outputPrefix: URL,
        expectedTextURL: URL,
        fallbackNote: String?
    ) -> WhisperCppProcessLaunchContext {
        let inputAudioSize = fileSize(at: audioFileURL)
        return WhisperCppProcessLaunchContext(
            runtimeMode: runtime.mode,
            bundledHelperURL: runtime.bundledHelperURL,
            bundledHelperExists: runtime.bundledHelperExists,
            bundledHelperIsExecutable: runtime.bundledHelperIsExecutable,
            configuredExecutablePath: configuration.normalizedExecutablePath,
            restoredAuthorizedExecutableURL: executableAccess.executableURL,
            authorizationSource: executableAccess.authorizationSource,
            scopeURL: executableAccess.scopeURL,
            processExecutableURL: executableAccess.executableURL,
            currentDirectoryURL: launchCurrentDirectoryURL(
                rootAccess: rootAccess,
                executableURL: executableAccess.executableURL
            ),
            executableBookmarkDataExists: configuration.executableBookmarkData?.isEmpty == false,
            executableBookmarkDataByteCount: configuration.executableBookmarkData?.count ?? 0,
            executableParentDirectoryBookmarkDataExists: configuration.executableParentDirectoryBookmarkData?.isEmpty == false,
            executableParentDirectoryBookmarkDataByteCount: configuration.executableParentDirectoryBookmarkData?.count ?? 0,
            executableAccessStarted: executableAccess.didStartAccessing,
            configuredModelPath: configuration.normalizedModelPath,
            modelURL: modelAccess.url,
            modelBookmarkDataExists: configuration.modelBookmarkData?.isEmpty == false,
            modelBookmarkDataByteCount: configuration.modelBookmarkData?.count ?? 0,
            modelAccessStarted: modelAccess.didStartAccessing,
            rootDirectoryURL: rootAccess.url,
            rootDirectoryConfiguredPath: configuration.normalizedWhisperCppRootDirectoryPath,
            rootDirectoryBookmarkDataExists: configuration.whisperCppRootDirectoryBookmarkData?.isEmpty == false,
            rootDirectoryBookmarkDataByteCount: configuration.whisperCppRootDirectoryBookmarkData?.count ?? 0,
            rootDirectoryAccessStarted: rootAccess.didStartAccessing,
            inputAudioURL: audioFileURL,
            inputAudioExists: fileManager.fileExists(atPath: audioFileURL.path),
            inputAudioSize: inputAudioSize,
            outputPrefix: outputPrefix,
            expectedTextURL: expectedTextURL,
            arguments: arguments,
            fallbackNote: fallbackNote
        )
    }

    private func makeBundledProcessLaunchContext(
        runtime: WhisperCppRuntimeResolution,
        modelAccess: SecurityScopedResourceAccess,
        audioFileURL: URL,
        arguments: [String],
        outputPrefix: URL,
        expectedTextURL: URL
    ) -> WhisperCppProcessLaunchContext {
        let inputAudioSize = fileSize(at: audioFileURL)
        let currentDirectoryURL = runtime.currentDirectoryURL
            ?? runtime.executableURL.deletingLastPathComponent().standardizedFileURL

        return WhisperCppProcessLaunchContext(
            runtimeMode: runtime.mode,
            bundledHelperURL: runtime.bundledHelperURL,
            bundledHelperExists: runtime.bundledHelperExists,
            bundledHelperIsExecutable: runtime.bundledHelperIsExecutable,
            configuredExecutablePath: configuration.normalizedExecutablePath,
            restoredAuthorizedExecutableURL: runtime.executableURL,
            authorizationSource: .bundledHelper,
            scopeURL: currentDirectoryURL,
            processExecutableURL: runtime.executableURL,
            currentDirectoryURL: currentDirectoryURL,
            executableBookmarkDataExists: configuration.executableBookmarkData?.isEmpty == false,
            executableBookmarkDataByteCount: configuration.executableBookmarkData?.count ?? 0,
            executableParentDirectoryBookmarkDataExists: configuration.executableParentDirectoryBookmarkData?.isEmpty == false,
            executableParentDirectoryBookmarkDataByteCount: configuration.executableParentDirectoryBookmarkData?.count ?? 0,
            executableAccessStarted: false,
            configuredModelPath: configuration.normalizedModelPath,
            modelURL: modelAccess.url,
            modelBookmarkDataExists: configuration.modelBookmarkData?.isEmpty == false,
            modelBookmarkDataByteCount: configuration.modelBookmarkData?.count ?? 0,
            modelAccessStarted: modelAccess.didStartAccessing,
            rootDirectoryURL: nil,
            rootDirectoryConfiguredPath: configuration.normalizedWhisperCppRootDirectoryPath,
            rootDirectoryBookmarkDataExists: configuration.whisperCppRootDirectoryBookmarkData?.isEmpty == false,
            rootDirectoryBookmarkDataByteCount: configuration.whisperCppRootDirectoryBookmarkData?.count ?? 0,
            rootDirectoryAccessStarted: false,
            inputAudioURL: audioFileURL,
            inputAudioExists: fileManager.fileExists(atPath: audioFileURL.path),
            inputAudioSize: inputAudioSize,
            outputPrefix: outputPrefix,
            expectedTextURL: expectedTextURL,
            arguments: arguments,
            fallbackNote: nil
        )
    }

    private func makeFallbackLaunchContext(
        executableAccess: SecurityScopedExecutableAccess,
        basedOn context: WhisperCppProcessLaunchContext,
        fallbackNote: String
    ) -> WhisperCppProcessLaunchContext {
        WhisperCppProcessLaunchContext(
            runtimeMode: context.runtimeMode,
            bundledHelperURL: context.bundledHelperURL,
            bundledHelperExists: context.bundledHelperExists,
            bundledHelperIsExecutable: context.bundledHelperIsExecutable,
            configuredExecutablePath: context.configuredExecutablePath,
            restoredAuthorizedExecutableURL: executableAccess.executableURL,
            authorizationSource: executableAccess.authorizationSource,
            scopeURL: executableAccess.scopeURL,
            processExecutableURL: executableAccess.executableURL,
            currentDirectoryURL: context.currentDirectoryURL
                ?? executableAccess.executableURL.deletingLastPathComponent().standardizedFileURL,
            executableBookmarkDataExists: context.executableBookmarkDataExists,
            executableBookmarkDataByteCount: context.executableBookmarkDataByteCount,
            executableParentDirectoryBookmarkDataExists: context.executableParentDirectoryBookmarkDataExists,
            executableParentDirectoryBookmarkDataByteCount: context.executableParentDirectoryBookmarkDataByteCount,
            executableAccessStarted: executableAccess.didStartAccessing,
            configuredModelPath: context.configuredModelPath,
            modelURL: context.modelURL,
            modelBookmarkDataExists: context.modelBookmarkDataExists,
            modelBookmarkDataByteCount: context.modelBookmarkDataByteCount,
            modelAccessStarted: context.modelAccessStarted,
            rootDirectoryURL: context.rootDirectoryURL,
            rootDirectoryConfiguredPath: context.rootDirectoryConfiguredPath,
            rootDirectoryBookmarkDataExists: context.rootDirectoryBookmarkDataExists,
            rootDirectoryBookmarkDataByteCount: context.rootDirectoryBookmarkDataByteCount,
            rootDirectoryAccessStarted: context.rootDirectoryAccessStarted,
            inputAudioURL: context.inputAudioURL,
            inputAudioExists: context.inputAudioExists,
            inputAudioSize: context.inputAudioSize,
            outputPrefix: context.outputPrefix,
            expectedTextURL: context.expectedTextURL,
            arguments: context.arguments,
            fallbackNote: fallbackNote
        )
    }

    private func runWhisperProcessWithParentDirectoryFallback(
        initialContext: WhisperCppProcessLaunchContext,
        timeout: TimeInterval
    ) async throws -> WhisperCppProcessOutput {
        do {
            return try await runWhisperProcess(context: initialContext, timeout: timeout)
        } catch TranscriptionError.processLaunchFailed(let initialMessage) {
            guard initialContext.authorizationSource == .fileBookmark,
                  configuration.executableReference.hasParentDirectoryBookmark else {
                throw TranscriptionError.processLaunchFailed(initialMessage)
            }

            Self.debugLogWhisperExecutableParentFallback(previousFailure: initialMessage)
            let parentOnlyReference = SecurityScopedExecutableReference(
                executablePath: configuration.normalizedExecutablePath,
                fileBookmarkData: nil,
                parentDirectoryPath: configuration.normalizedExecutableParentDirectoryPath,
                parentDirectoryBookmarkData: configuration.executableParentDirectoryBookmarkData
            )

            let parentAccess: SecurityScopedExecutableAccess
            do {
                parentAccess = try SecurityScopedFileAccess.startAccessingExecutable(
                    reference: parentOnlyReference,
                    errors: Self.whisperExecutableErrors,
                    fileManager: fileManager,
                    environment: securityScopedEnvironment
                )
            } catch {
                throw TranscriptionError.processLaunchFailed(
                    initialMessage + "\nparentDirectoryFallbackAccessFailed=\(error.localizedDescription)"
                )
            }
            defer { parentAccess.stop() }

            let fallbackContext = makeFallbackLaunchContext(
                executableAccess: parentAccess,
                basedOn: initialContext,
                fallbackNote: "file bookmark launch failed; retrying with parent directory bookmark; previous=\(Self.limited(initialMessage, maxCharacters: 500))"
            )
            debugLogWhisperProcessStart(context: fallbackContext)
            return try await runWhisperProcess(context: fallbackContext, timeout: timeout)
        }
    }

    private func runWhisperProcess(
        context: WhisperCppProcessLaunchContext,
        timeout: TimeInterval
    ) async throws -> WhisperCppProcessOutput {
        let request = WhisperCppProcessExecutionRequest(
            arguments: context.arguments,
            executableURL: context.processExecutableURL,
            authorizationSource: context.authorizationSource,
            scopeURL: context.scopeURL,
            currentDirectoryURL: context.currentDirectoryURL
        )

        do {
            return try await runProcess(request: request, timeout: timeout)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            Self.debugLogWhisperProcessLaunchFailure(error: error, context: context)
            throw TranscriptionError.processLaunchFailed(
                Self.processLaunchFailureMessage(error: error, context: context)
            )
        }
    }

    private func runProcess(
        request: WhisperCppProcessExecutionRequest,
        timeout: TimeInterval
    ) async throws -> WhisperCppProcessOutput {
        if let processRunner {
            do {
                return try await processRunner.run(
                    arguments: request.arguments,
                    executableURL: request.executableURL,
                    authorizationSource: request.authorizationSource,
                    scopeURL: request.scopeURL,
                    currentDirectoryURL: request.currentDirectoryURL,
                    timeout: timeout
                )
            }
        }

        let process = Process()
        process.executableURL = request.executableURL
        process.currentDirectoryURL = request.currentDirectoryURL
        process.arguments = request.arguments
        Self.debugLogLiveProcessConfiguration(process)

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

                func finish(_ result: Result<WhisperCppProcessOutput, Error>) {
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

                    let output = WhisperCppProcessOutput(
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
                    finish(.failure(TranscriptionError.processTimedOut))
                }
            }
        } onCancel: {
            cancellationToken.cancel()
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func readTextOutput(outputPrefix: URL, context: WhisperCppProcessLaunchContext) throws -> String {
        let candidates = WhisperCppOutputPaths.textOutputCandidates(outputPrefix: outputPrefix)
        guard let textURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw TranscriptionError.outputMissing(
                textOutputMissingMessage(outputPrefix: outputPrefix, candidates: candidates, context: context)
            )
        }

        do {
            let data = try Data(contentsOf: textURL)
            guard let text = String(data: data, encoding: .utf8) else {
                throw TranscriptionError.outputDecodeFailed(
                    "转写文本读取失败：\nstage=transcript txt reading\nruntimeMode=\(context.runtimeMode.rawValue)\nprocessExecutableURLPath=\(context.processExecutableURL.path)\ntextPath=\(textURL.path)\nsize=\(data.count)"
                )
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw TranscriptionError.outputEmpty(
                    "转写文本为空：\nstage=transcript txt reading\nruntimeMode=\(context.runtimeMode.rawValue)\nprocessExecutableURLPath=\(context.processExecutableURL.path)\ntextPath=\(textURL.path)\nsize=\(data.count)"
                )
            }

            debugLogTextOutput(textURL)
            return trimmed
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.outputDecodeFailed(
                "转写文本读取失败：\nstage=transcript txt reading\nruntimeMode=\(context.runtimeMode.rawValue)\nprocessExecutableURLPath=\(context.processExecutableURL.path)\ntextPath=\(textURL.path)\nerror=\(error.localizedDescription)"
            )
        }
    }

    private func readSegmentsIfAvailable(outputPrefix: URL) -> [TranscriptionSegment] {
        let jsonURL = outputPrefix.appendingPathExtension("json").standardizedFileURL
        guard fileManager.fileExists(atPath: jsonURL.path),
              let data = try? Data(contentsOf: jsonURL),
              let decoded = try? Self.jsonDecoder.decode(WhisperCppJSONOutput.self, from: data),
              let entries = decoded.transcription else {
            return []
        }

        return entries.enumerated().compactMap { index, entry in
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return nil
            }

            let start = entry.offsets?.from.map { Double($0) / 1000.0 }
                ?? entry.timestamps?.from.flatMap(Self.seconds(from:))
                ?? 0
            let end = entry.offsets?.to.map { Double($0) / 1000.0 }
                ?? entry.timestamps?.to.flatMap(Self.seconds(from:))
                ?? start

            return TranscriptionSegment(
                id: "\(outputPrefix.lastPathComponent)-segment-\(index + 1)",
                startTime: start,
                endTime: max(end, start),
                text: text,
                confidence: nil
            )
        }
    }

    private func processFailureMessage(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        context: WhisperCppProcessLaunchContext
    ) -> String {
        var fields: [(String, String)] = [
            ("stage", "whisper-cli process"),
            ("runtimeMode", context.runtimeMode.rawValue),
            ("exitCode", "\(exitCode)"),
            ("bundledHelperPath", context.bundledHelperURL.path),
            ("bundledHelperExists", "\(context.bundledHelperExists)"),
            ("bundledHelperIsExecutable", "\(context.bundledHelperIsExecutable)"),
            ("processExecutableURLPath", context.processExecutableURL.path),
            ("processExecutableURLIsAbsolute", "\(Self.isAbsoluteFileURL(context.processExecutableURL))"),
            ("currentDirectoryURLPath", context.currentDirectoryURL?.path ?? "nil"),
            ("executableAccessStarted", "\(context.executableAccessStarted)"),
            ("executableAccessMode", Self.executableAccessModeDescription(context.authorizationSource)),
            ("rootDirectoryPath", context.rootDirectoryURL?.path ?? context.rootDirectoryConfiguredPath),
            ("rootDirectoryAccessStarted", "\(context.rootDirectoryAccessStarted)"),
            ("modelPath", context.modelURL.path),
            ("modelAccessStarted", "\(context.modelAccessStarted)"),
            ("inputAudioPath", context.inputAudioURL.path),
            ("inputAudioExists", "\(context.inputAudioExists)"),
            ("inputAudioSize", "\(context.inputAudioSize)"),
            ("outputPrefix", context.outputPrefix.path),
            ("expectedTxtPath", context.expectedTextURL.path),
            ("arguments", Self.argumentsDescription(context.arguments)),
            ("stdoutSummary", Self.limited(stdout.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000)),
            ("stderrSummary", Self.limited(stderr.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000))
        ]

        if context.inputAudioURL.pathExtension.lowercased() != "wav" {
            fields.append(("preprocessing", "whisper-cli received non-wav audio; check audio preprocessing"))
        }

        return Self.diagnosticMessage(title: "whisper-cli 执行失败", fields: fields)
    }

    private static func processLaunchFailureMessage(error: Error, context: WhisperCppProcessLaunchContext) -> String {
        let nsError = error as NSError
        var fields: [(String, String)] = [
            ("stage", "whisper-cli process launch"),
            ("runtimeMode", context.runtimeMode.rawValue),
            ("bundledHelperPath", context.bundledHelperURL.path),
            ("bundledHelperExists", "\(context.bundledHelperExists)"),
            ("bundledHelperIsExecutable", "\(context.bundledHelperIsExecutable)"),
            ("configuredExecutablePath", context.configuredExecutablePath),
            ("restoredAuthorizedExecutableURLPath", context.restoredAuthorizedExecutableURL.path),
            ("processExecutableURLPath", context.processExecutableURL.path),
            ("processExecutableURLIsAbsolute", "\(Self.isAbsoluteFileURL(context.processExecutableURL))"),
            ("processExecutableURLLastPathComponent", context.processExecutableURL.lastPathComponent),
            ("processExecutableURLIsFileURL", "\(context.processExecutableURL.isFileURL)"),
            ("processExecutableURLAbsoluteString", context.processExecutableURL.absoluteString),
            ("executableBookmarkDataExists", Self.yesNo(context.executableBookmarkDataExists)),
            ("executableBookmarkDataByteCount", "\(context.executableBookmarkDataByteCount)"),
            ("executableParentDirectoryBookmarkDataExists", Self.yesNo(context.executableParentDirectoryBookmarkDataExists)),
            ("executableParentDirectoryBookmarkDataByteCount", "\(context.executableParentDirectoryBookmarkDataByteCount)"),
            ("executableAccessStarted", "\(context.executableAccessStarted)"),
            ("executableAccessMode", Self.executableAccessModeDescription(context.authorizationSource)),
            ("scopeURL", context.scopeURL.path),
            ("currentDirectoryURLPath", context.currentDirectoryURL?.path ?? "nil"),
            ("modelPath", context.modelURL.path),
            ("configuredModelPath", context.configuredModelPath),
            ("modelBookmarkDataExists", Self.yesNo(context.modelBookmarkDataExists)),
            ("modelBookmarkDataByteCount", "\(context.modelBookmarkDataByteCount)"),
            ("modelAccessStarted", "\(context.modelAccessStarted)"),
            ("rootDirectoryPath", context.rootDirectoryURL?.path ?? context.rootDirectoryConfiguredPath),
            ("configuredRootDirectoryPath", context.rootDirectoryConfiguredPath),
            ("rootDirectoryBookmarkDataExists", Self.yesNo(context.rootDirectoryBookmarkDataExists)),
            ("rootDirectoryBookmarkDataByteCount", "\(context.rootDirectoryBookmarkDataByteCount)"),
            ("rootDirectoryAccessStarted", "\(context.rootDirectoryAccessStarted)"),
            ("inputAudioPath", context.inputAudioURL.path),
            ("inputAudioExists", "\(context.inputAudioExists)"),
            ("inputAudioSize", "\(context.inputAudioSize)"),
            ("outputPrefix", context.outputPrefix.path),
            ("expectedTxtPath", context.expectedTextURL.path),
            ("arguments", Self.argumentsDescription(context.arguments)),
            ("stdoutSummary", "unavailable_before_process_start"),
            ("stderrSummary", "unavailable_before_process_start"),
            ("nsErrorDomain", nsError.domain),
            ("nsErrorCode", "\(nsError.code)"),
            ("description", nsError.localizedDescription)
        ]

        if let fallbackNote = context.fallbackNote, !fallbackNote.isEmpty {
            fields.append(("fallback", fallbackNote))
        }
        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            fields.append(("failureReason", failureReason))
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            fields.append(("recoverySuggestion", recoverySuggestion))
        }
        fields.append(contentsOf: errorDiagnosticFields(error: error, prefix: "processRun"))

        return Self.diagnosticMessage(title: "whisper-cli 启动失败", fields: fields)
    }

    private static func launchProbeAccessFailureMessage(
        stage: String,
        configuration: WhisperCppTranscriptionConfiguration,
        runtime: WhisperCppRuntimeResolution,
        rootAccess: SecurityScopedResourceAccess? = nil,
        error: Error
    ) -> String {
        let nsError = error as NSError
        var fields: [(String, String)] = [
            ("stage", stage),
            ("runtimeMode", runtime.mode.rawValue),
            ("arguments", "--help"),
            ("bundledHelperPath", runtime.bundledHelperURL.path),
            ("bundledHelperExists", "\(runtime.bundledHelperExists)"),
            ("bundledHelperIsExecutable", "\(runtime.bundledHelperIsExecutable)"),
            ("configuredExecutablePath", configuration.normalizedExecutablePath),
            ("processExecutableURLPath", runtime.executableURL.path),
            ("currentDirectoryURLPath", rootAccess?.url.path ?? "nil"),
            ("executableBookmarkDataExists", Self.yesNo(configuration.executableBookmarkData?.isEmpty == false)),
            ("executableBookmarkDataByteCount", "\(configuration.executableBookmarkData?.count ?? 0)"),
            ("executableParentDirectoryBookmarkDataExists", Self.yesNo(configuration.executableParentDirectoryBookmarkData?.isEmpty == false)),
            ("executableParentDirectoryBookmarkDataByteCount", "\(configuration.executableParentDirectoryBookmarkData?.count ?? 0)"),
            ("rootDirectoryPath", rootAccess?.url.path ?? configuration.normalizedWhisperCppRootDirectoryPath),
            ("rootDirectoryBookmarkDataExists", Self.yesNo(configuration.whisperCppRootDirectoryBookmarkData?.isEmpty == false)),
            ("rootDirectoryBookmarkDataByteCount", "\(configuration.whisperCppRootDirectoryBookmarkData?.count ?? 0)"),
            ("rootDirectoryAccessStarted", "\(rootAccess?.didStartAccessing ?? false)"),
            ("modelBookmarkDataExists", Self.yesNo(configuration.modelBookmarkData?.isEmpty == false)),
            ("modelBookmarkDataByteCount", "\(configuration.modelBookmarkData?.count ?? 0)"),
            ("stdoutSummary", "unavailable_before_process_start"),
            ("stderrSummary", "unavailable_before_process_start"),
            ("nsErrorDomain", nsError.domain),
            ("nsErrorCode", "\(nsError.code)"),
            ("description", nsError.localizedDescription)
        ]

        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            fields.append(("failureReason", failureReason))
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            fields.append(("recoverySuggestion", recoverySuggestion))
        }
        fields.append(contentsOf: errorDiagnosticFields(error: error, prefix: "launchProbeAccess"))

        return Self.diagnosticMessage(title: "whisper-cli 启动测试失败", fields: fields)
    }

    private static func launchProbeCompletionMessage(
        succeeded: Bool,
        configuration: WhisperCppTranscriptionConfiguration,
        executableAccess: SecurityScopedExecutableAccess,
        rootAccess: SecurityScopedResourceAccess,
        currentDirectoryURL: URL,
        output: WhisperCppProcessOutput
    ) -> String {
        Self.diagnosticMessage(
            title: succeeded ? "whisper-cli 启动测试成功" : "whisper-cli 启动测试失败",
            fields: launchProbeBaseFields(
                configuration: configuration,
                executableAccess: executableAccess,
                rootAccess: rootAccess,
                currentDirectoryURL: currentDirectoryURL
            ) + [
                ("terminationStatus", "\(output.exitCode)"),
                ("stdoutSummary", Self.limited(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000)),
                ("stderrSummary", Self.limited(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000))
            ]
        )
    }

    private static func launchProbeLaunchFailureMessage(
        configuration: WhisperCppTranscriptionConfiguration,
        executableAccess: SecurityScopedExecutableAccess,
        rootAccess: SecurityScopedResourceAccess,
        currentDirectoryURL: URL,
        error: Error
    ) -> String {
        let nsError = error as NSError
        var fields = launchProbeBaseFields(
            configuration: configuration,
            executableAccess: executableAccess,
            rootAccess: rootAccess,
            currentDirectoryURL: currentDirectoryURL
        ) + [
            ("stdoutSummary", "unavailable_before_process_start"),
            ("stderrSummary", "unavailable_before_process_start"),
            ("nsErrorDomain", nsError.domain),
            ("nsErrorCode", "\(nsError.code)"),
            ("description", nsError.localizedDescription)
        ]

        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            fields.append(("failureReason", failureReason))
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            fields.append(("recoverySuggestion", recoverySuggestion))
        }
        fields.append(contentsOf: errorDiagnosticFields(error: error, prefix: "launchProbe"))

        return Self.diagnosticMessage(title: "whisper-cli 启动测试失败", fields: fields)
    }

    private static func launchProbeBaseFields(
        configuration: WhisperCppTranscriptionConfiguration,
        executableAccess: SecurityScopedExecutableAccess,
        rootAccess: SecurityScopedResourceAccess,
        currentDirectoryURL: URL
    ) -> [(String, String)] {
        [
            ("stage", "whisper-cli launch probe"),
            ("arguments", "--help"),
            ("configuredExecutablePath", configuration.normalizedExecutablePath),
            ("restoredAuthorizedExecutableURLPath", executableAccess.executableURL.path),
            ("processExecutableURLPath", executableAccess.executableURL.path),
            ("processExecutableURLIsAbsolute", "\(Self.isAbsoluteFileURL(executableAccess.executableURL))"),
            ("currentDirectoryURLPath", currentDirectoryURL.path),
            ("executableBookmarkDataExists", Self.yesNo(configuration.executableBookmarkData?.isEmpty == false)),
            ("executableBookmarkDataByteCount", "\(configuration.executableBookmarkData?.count ?? 0)"),
            ("executableParentDirectoryBookmarkDataExists", Self.yesNo(configuration.executableParentDirectoryBookmarkData?.isEmpty == false)),
            ("executableParentDirectoryBookmarkDataByteCount", "\(configuration.executableParentDirectoryBookmarkData?.count ?? 0)"),
            ("executableAccessStarted", "\(executableAccess.didStartAccessing)"),
            ("executableAccessMode", Self.executableAccessModeDescription(executableAccess.authorizationSource)),
            ("scopeURL", executableAccess.scopeURL.path),
            ("rootDirectoryPath", rootAccess.url.path),
            ("rootDirectoryBookmarkDataExists", Self.yesNo(configuration.whisperCppRootDirectoryBookmarkData?.isEmpty == false)),
            ("rootDirectoryBookmarkDataByteCount", "\(configuration.whisperCppRootDirectoryBookmarkData?.count ?? 0)"),
            ("rootDirectoryAccessStarted", "\(rootAccess.didStartAccessing)"),
            ("modelPath", configuration.normalizedModelPath),
            ("modelBookmarkDataExists", Self.yesNo(configuration.modelBookmarkData?.isEmpty == false)),
            ("modelBookmarkDataByteCount", "\(configuration.modelBookmarkData?.count ?? 0)")
        ]
    }

    private static func bundledLaunchProbeMessage(
        runtime: WhisperCppRuntimeResolution,
        configuration: WhisperCppTranscriptionConfiguration,
        modelAccess: SecurityScopedResourceAccess?,
        modelAccessError: Error?,
        currentDirectoryURL: URL,
        output: WhisperCppProcessOutput?,
        error: Error?
    ) -> String {
        var fields: [(String, String)] = [
            ("stage", "whisper-cli launch probe"),
            ("runtimeMode", runtime.mode.rawValue),
            ("arguments", "--help"),
            ("bundledHelperPath", runtime.bundledHelperURL.path),
            ("bundledHelperExists", "\(runtime.bundledHelperExists)"),
            ("bundledHelperIsExecutable", "\(runtime.bundledHelperIsExecutable)"),
            ("configuredExecutablePath", configuration.normalizedExecutablePath),
            ("restoredAuthorizedExecutableURLPath", runtime.executableURL.path),
            ("processExecutableURLPath", runtime.executableURL.path),
            ("processExecutableURLIsAbsolute", "\(Self.isAbsoluteFileURL(runtime.executableURL))"),
            ("currentDirectoryURLPath", currentDirectoryURL.path),
            ("executableAccessStarted", "false"),
            ("executableAccessMode", Self.executableAccessModeDescription(.bundledHelper)),
            ("scopeURL", currentDirectoryURL.path),
            ("rootDirectoryPath", configuration.normalizedWhisperCppRootDirectoryPath),
            ("rootDirectoryAccessStarted", "false"),
            ("modelPath", modelAccess?.url.path ?? configuration.normalizedModelPath),
            ("modelBookmarkDataExists", Self.yesNo(configuration.modelBookmarkData?.isEmpty == false)),
            ("modelBookmarkDataByteCount", "\(configuration.modelBookmarkData?.count ?? 0)"),
            ("modelAccessStarted", "\(modelAccess?.didStartAccessing ?? false)")
        ]

        if let output {
            fields.append(("terminationStatus", "\(output.exitCode)"))
            fields.append(("stdoutSummary", Self.limited(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000)))
            fields.append(("stderrSummary", Self.limited(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000)))
        } else {
            fields.append(("stdoutSummary", "unavailable_before_process_start"))
            fields.append(("stderrSummary", "unavailable_before_process_start"))
        }

        if let modelAccessError {
            fields.append(contentsOf: errorDiagnosticFields(error: modelAccessError, prefix: "modelAccess"))
        }
        if let error {
            let nsError = error as NSError
            fields.append(("nsErrorDomain", nsError.domain))
            fields.append(("nsErrorCode", "\(nsError.code)"))
            fields.append(("description", nsError.localizedDescription))
            fields.append(contentsOf: errorDiagnosticFields(error: error, prefix: "launchProbe"))
        }

        let title = output?.exitCode == 0 && error == nil
            ? "whisper helper 启动测试成功"
            : "whisper helper 启动测试失败"
        return diagnosticMessage(title: title, fields: fields)
    }

    private static func launchProbeResult(
        succeeded: Bool,
        runtime: WhisperCppRuntimeResolution,
        configuration: WhisperCppTranscriptionConfiguration,
        executableAccess: SecurityScopedExecutableAccess?,
        rootAccess: SecurityScopedResourceAccess?,
        output: WhisperCppProcessOutput?,
        error: Error?,
        diagnosticMessage: String
    ) -> WhisperCppLaunchProbeResult {
        let stdoutSummary = Self.limited(
            (output?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: 300
        )
        let stderrSummary = Self.limited(
            (output?.stderr ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: 300
        )
        let processExecutableURLPath = executableAccess?.executableURL.path
            ?? configuration.normalizedExecutablePath
        let currentDirectoryURLPath = rootAccess?.url.path
            ?? executableAccess?.executableURL.deletingLastPathComponent().path
            ?? "nil"

        let userMessage: String
        if let output {
            let prefix = succeeded ? "whisper-cli 启动测试成功" : "whisper-cli 启动测试失败"
            userMessage = Self.limited(
                "\(prefix)：runtimeMode=\(runtime.mode.rawValue)；exitCode=\(output.exitCode)；stdout=\(stdoutSummary.isEmpty ? "empty" : stdoutSummary)；stderr=\(stderrSummary.isEmpty ? "empty" : stderrSummary)",
                maxCharacters: 520
            )
        } else if let error {
            let nsError = error as NSError
            userMessage = Self.limited(
                "whisper-cli 启动测试失败：runtimeMode=\(runtime.mode.rawValue)；\(nsError.domain) code=\(nsError.code)；\(nsError.localizedDescription)",
                maxCharacters: 360
            )
        } else {
            userMessage = succeeded ? "whisper-cli 启动测试成功" : "whisper-cli 启动测试失败"
        }

        return WhisperCppLaunchProbeResult(
            succeeded: succeeded,
            runtimeMode: runtime.mode,
            userMessage: userMessage,
            diagnosticMessage: diagnosticMessage,
            bundledHelperExists: runtime.bundledHelperExists,
            processExecutableURLPath: processExecutableURLPath,
            currentDirectoryURLPath: currentDirectoryURLPath,
            rootDirectoryAccessStarted: rootAccess?.didStartAccessing ?? false,
            stdoutSummary: stdoutSummary,
            stderrSummary: stderrSummary
        )
    }

    private static func launchProbeResult(
        succeeded: Bool,
        runtime: WhisperCppRuntimeResolution,
        currentDirectoryURL: URL,
        rootDirectoryAccessStarted: Bool,
        output: WhisperCppProcessOutput?,
        error: Error?,
        diagnosticMessage: String
    ) -> WhisperCppLaunchProbeResult {
        let stdoutSummary = Self.limited(
            (output?.stdout ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: 300
        )
        let stderrSummary = Self.limited(
            (output?.stderr ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: 300
        )

        let userMessage: String
        if let output {
            let prefix = succeeded ? "whisper helper 启动测试成功" : "whisper helper 启动测试失败"
            userMessage = Self.limited(
                "\(prefix)：runtimeMode=\(runtime.mode.rawValue)；exitCode=\(output.exitCode)；stdout=\(stdoutSummary.isEmpty ? "empty" : stdoutSummary)；stderr=\(stderrSummary.isEmpty ? "empty" : stderrSummary)",
                maxCharacters: 520
            )
        } else if let error {
            let nsError = error as NSError
            userMessage = Self.limited(
                "whisper helper 启动测试失败：runtimeMode=\(runtime.mode.rawValue)；\(nsError.domain) code=\(nsError.code)；\(nsError.localizedDescription)",
                maxCharacters: 360
            )
        } else {
            userMessage = succeeded ? "whisper helper 启动测试成功" : "whisper helper 启动测试失败"
        }

        return WhisperCppLaunchProbeResult(
            succeeded: succeeded,
            runtimeMode: runtime.mode,
            userMessage: userMessage,
            diagnosticMessage: diagnosticMessage,
            bundledHelperExists: runtime.bundledHelperExists,
            processExecutableURLPath: runtime.executableURL.path,
            currentDirectoryURLPath: currentDirectoryURL.path,
            rootDirectoryAccessStarted: rootDirectoryAccessStarted,
            stdoutSummary: stdoutSummary,
            stderrSummary: stderrSummary
        )
    }

    private static func launchProbeVariantsMessage(
        configuration: WhisperCppTranscriptionConfiguration,
        runtime: WhisperCppRuntimeResolution,
        executableAccess: SecurityScopedExecutableAccess,
        rootAccess: SecurityScopedResourceAccess,
        modelAccess: SecurityScopedResourceAccess?,
        modelAccessError: Error?,
        currentDirectoryURL: URL,
        results: [WhisperCppLaunchProbeVariantResult]
    ) -> String {
        let successfulVariant = results.first(where: \.succeeded)?.variant.name ?? "none"
        var fields: [(String, String)] = [
            ("stage", "whisper-cli launch probe variants"),
            ("runtimeMode", runtime.mode.rawValue),
            ("arguments", "--help"),
            ("bundledHelperPath", runtime.bundledHelperURL.path),
            ("bundledHelperExists", "\(runtime.bundledHelperExists)"),
            ("bundledHelperIsExecutable", "\(runtime.bundledHelperIsExecutable)"),
            ("configuredExecutablePath", configuration.normalizedExecutablePath),
            ("restoredAuthorizedExecutableURLPath", executableAccess.executableURL.path),
            ("currentDirectoryURLPath", currentDirectoryURL.path),
            ("rootDirectoryPath", rootAccess.url.path),
            ("rootDirectoryAccessStarted", "\(rootAccess.didStartAccessing)"),
            ("executableAccessStarted", "\(executableAccess.didStartAccessing)"),
            ("executableAccessMode", Self.executableAccessModeDescription(executableAccess.authorizationSource)),
            ("modelPath", modelAccess?.url.path ?? configuration.normalizedModelPath),
            ("modelAccessStarted", "\(modelAccess?.didStartAccessing ?? false)"),
            ("variantsAttempted", results.map(\.variant.name).joined(separator: ",")),
            ("successfulVariant", successfulVariant)
        ]

        if let modelAccessError {
            fields.append(contentsOf: errorDiagnosticFields(error: modelAccessError, prefix: "modelAccess"))
        }

        for result in results {
            let prefix = "variant.\(result.variant.name)"
            fields.append(("\(prefix).succeeded", "\(result.succeeded)"))
            fields.append(("\(prefix).processRunThrown", "\(result.error != nil)"))
            fields.append(("\(prefix).terminationStatus", result.output.map { "\($0.exitCode)" } ?? "notStarted"))
            fields.append(("\(prefix).stdoutSummary", limited(result.output?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", maxCharacters: 1000)))
            fields.append(("\(prefix).stderrSummary", limited(result.output?.stderr.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", maxCharacters: 1000)))
            for (key, value) in result.diagnostics {
                fields.append(("\(prefix).\(key)", value))
            }
            if let error = result.error {
                fields.append(contentsOf: errorDiagnosticFields(error: error, prefix: prefix))
            }
        }

        let title = successfulVariant == "none"
            ? "whisper-cli 启动测试失败"
            : "whisper-cli 启动测试成功"
        return diagnosticMessage(title: title, fields: fields)
    }

    private static func launchProbeResult(
        configuration: WhisperCppTranscriptionConfiguration,
        runtime: WhisperCppRuntimeResolution,
        executableAccess: SecurityScopedExecutableAccess,
        rootAccess: SecurityScopedResourceAccess,
        results: [WhisperCppLaunchProbeVariantResult],
        diagnosticMessage: String
    ) -> WhisperCppLaunchProbeResult {
        let successfulResult = results.first(where: \.succeeded)
        let representativeResult = successfulResult ?? results.first
        let stdoutSummary = limited(
            representativeResult?.output?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            maxCharacters: 300
        )
        let stderrSummary = limited(
            representativeResult?.output?.stderr.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            maxCharacters: 300
        )
        let succeeded = successfulResult != nil
        let userMessage: String
        if let successfulResult {
            userMessage = limited(
                "whisper-cli 启动测试成功：runtimeMode=\(runtime.mode.rawValue)；variant=\(successfulResult.variant.name)；exitCode=\(successfulResult.output?.exitCode ?? -1)；stdout=\(stdoutSummary.isEmpty ? "empty" : stdoutSummary)；stderr=\(stderrSummary.isEmpty ? "empty" : stderrSummary)",
                maxCharacters: 520
            )
        } else if let error = representativeResult?.error {
            let nsError = error as NSError
            userMessage = limited(
                "whisper-cli 启动测试失败：runtimeMode=\(runtime.mode.rawValue)；variants=\(results.map(\.variant.name).joined(separator: ","))；\(nsError.domain) code=\(nsError.code)；\(nsError.localizedDescription)",
                maxCharacters: 520
            )
        } else {
            userMessage = "whisper-cli 启动测试失败：没有可用 variant 结果"
        }

        return WhisperCppLaunchProbeResult(
            succeeded: succeeded,
            runtimeMode: runtime.mode,
            userMessage: userMessage,
            diagnosticMessage: diagnosticMessage,
            bundledHelperExists: runtime.bundledHelperExists,
            processExecutableURLPath: representativeResult?.variant.executableURL.path
                ?? executableAccess.executableURL.path
                .trimmingCharacters(in: .whitespacesAndNewlines),
            currentDirectoryURLPath: representativeResult?.currentDirectoryURL.path
                ?? rootAccess.url.path,
            rootDirectoryAccessStarted: rootAccess.didStartAccessing,
            stdoutSummary: stdoutSummary,
            stderrSummary: stderrSummary
        )
    }

    private func textOutputMissingMessage(
        outputPrefix: URL,
        candidates: [URL],
        context: WhisperCppProcessLaunchContext
    ) -> String {
        Self.diagnosticMessage(
            title: "whisper-cli 未生成 txt",
            fields: [
                ("stage", "transcript txt reading"),
                ("runtimeMode", context.runtimeMode.rawValue),
                ("bundledHelperExists", "\(context.bundledHelperExists)"),
                ("processExecutableURLPath", context.processExecutableURL.path),
                ("currentDirectoryURLPath", context.currentDirectoryURL?.path ?? "nil"),
                ("modelAccessStarted", "\(context.modelAccessStarted)"),
                ("inputAudioPath", context.inputAudioURL.path),
                ("inputAudioExists", "\(context.inputAudioExists)"),
                ("inputAudioSize", "\(context.inputAudioSize)"),
                ("outputPrefix", outputPrefix.path),
                ("expectedTxt", candidates.first?.path ?? ""),
                ("alternateTxt", candidates.dropFirst().first?.path ?? ""),
                ("matchingFiles", matchingOutputFilesDescription(outputPrefix: outputPrefix))
            ]
        )
    }

    private func matchingOutputFilesDescription(outputPrefix: URL) -> String {
        let directoryURL = outputPrefix.deletingLastPathComponent()
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "directory_unavailable"
        }

        let matching = files
            .filter { $0.lastPathComponent.hasPrefix(outputPrefix.lastPathComponent) }
            .prefix(12)
            .map { url -> String in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if values?.isDirectory == true {
                    return "\(url.lastPathComponent)/"
                }

                return "\(url.lastPathComponent)(\(values?.fileSize ?? 0)b)"
            }

        return matching.isEmpty ? "none" : matching.joined(separator: ", ")
    }

    private static func diagnosticMessage(title: String, fields: [(String, String)]) -> String {
        let fieldText = fields
            .map { key, value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : "\(key)=\(trimmed)"
            }
            .compactMap { $0 }
            .joined(separator: "\n")

        return fieldText.isEmpty ? title : "\(title)：\n\(fieldText)"
    }

    private static func errorDiagnosticFields(error: Error, prefix: String) -> [(String, String)] {
        let nsError = error as NSError
        var fields: [(String, String)] = [
            ("\(prefix).nsErrorDomain", nsError.domain),
            ("\(prefix).nsErrorCode", "\(nsError.code)"),
            ("\(prefix).description", nsError.localizedDescription),
            ("\(prefix).userInfoKeys", nsError.userInfo.keys.map { "\($0)" }.sorted().joined(separator: ","))
        ]

        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            fields.append(("\(prefix).failureReason", failureReason))
        }
        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            fields.append(("\(prefix).recoverySuggestion", recoverySuggestion))
        }
        if let filePath = nsError.userInfo[NSFilePathErrorKey] as? String, !filePath.isEmpty {
            fields.append(("\(prefix).NSFilePathErrorKey", filePath))
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            fields.append(contentsOf: underlyingErrorDiagnosticFields(underlying, prefix: "\(prefix).underlying"))
            if let nestedUnderlying = underlying.userInfo[NSUnderlyingErrorKey] as? NSError {
                fields.append(contentsOf: underlyingErrorDiagnosticFields(
                    nestedUnderlying,
                    prefix: "\(prefix).underlying.underlying"
                ))
            }
        }

        return fields
    }

    private static func underlyingErrorDiagnosticFields(_ error: NSError, prefix: String) -> [(String, String)] {
        var fields: [(String, String)] = [
            ("\(prefix).domain", error.domain),
            ("\(prefix).code", "\(error.code)"),
            ("\(prefix).description", error.localizedDescription),
            ("\(prefix).userInfoKeys", error.userInfo.keys.map { "\($0)" }.sorted().joined(separator: ","))
        ]

        if let failureReason = error.localizedFailureReason, !failureReason.isEmpty {
            fields.append(("\(prefix).failureReason", failureReason))
        }
        if let recoverySuggestion = error.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            fields.append(("\(prefix).recoverySuggestion", recoverySuggestion))
        }
        if let filePath = error.userInfo[NSFilePathErrorKey] as? String, !filePath.isEmpty {
            fields.append(("\(prefix).NSFilePathErrorKey", filePath))
        }

        return fields
    }

    private static func resourceReachabilityDescription(_ url: URL) -> (reachable: String, errorDescription: String) {
        do {
            return (try url.checkResourceIsReachable() ? "true" : "false", "none")
        } catch {
            let nsError = error as NSError
            return ("false", "\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
        }
    }

    private static func posixAccessDescription(path: String) -> (
        result: String,
        errno: String,
        errnoDescription: String
    ) {
        Darwin.errno = 0
        let result = path.withCString { pointer in
            Darwin.access(pointer, X_OK)
        }
        let errorNumber = result == 0 ? 0 : Darwin.errno
        return (
            "\(result)",
            "\(errorNumber)",
            errorNumber == 0 ? "none" : String(cString: strerror(errorNumber))
        )
    }

    private static func posixStatDescription(path: String) -> (
        result: String,
        errno: String,
        errnoDescription: String,
        mode: String,
        uid: String,
        gid: String
    ) {
        var info = stat()
        Darwin.errno = 0
        let result = path.withCString { pointer in
            Darwin.fstatat(AT_FDCWD, pointer, &info, 0)
        }
        let errorNumber = result == 0 ? 0 : Darwin.errno
        return (
            "\(result)",
            "\(errorNumber)",
            errorNumber == 0 ? "none" : String(cString: strerror(errorNumber)),
            result == 0 ? String(format: "%#o", info.st_mode) : "unavailable",
            result == 0 ? "\(info.st_uid)" : "unavailable",
            result == 0 ? "\(info.st_gid)" : "unavailable"
        )
    }

    private static func argumentsDescription(_ arguments: [String]) -> String {
        arguments.joined(separator: " ")
    }

    private static func isAbsoluteFileURL(_ url: URL) -> Bool {
        url.isFileURL && url.path.hasPrefix("/")
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func executableAccessModeDescription(_ source: SecurityScopedExecutableAuthorizationSource) -> String {
        switch source {
        case .bundledHelper:
            return "bundled helper"
        case .fileBookmark:
            return "file bookmark"
        case .parentDirectoryBookmark:
            return "parent directory bookmark"
        }
    }

    private func normalizedLanguageArgument(_ language: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "auto" : trimmed
    }

    private func sanitizedPathComponent(_ value: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return value.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private func isInside(_ url: URL, parent: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == parentPath || filePath.hasPrefix(parentPath + "/")
    }

    private func fileSize(at url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    private func fileExists(_ url: URL, isDirectory expectedIsDirectory: Bool) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        return isDirectory.boolValue == expectedIsDirectory
    }

    private static func limited(_ string: String, maxCharacters: Int) -> String {
        guard string.count > maxCharacters else {
            return string
        }

        return String(string.prefix(maxCharacters)) + "..."
    }

    private static func timeArgument(_ value: TimeInterval) -> String {
        String(format: "%.3f", max(0, value))
    }

    private func debugLogRequest(_ request: TranscriptionRequest) {
        #if DEBUG
        print(
            "[Rokurics][WhisperCppTranscriptionProvider] request: " +
            "taskID=\(request.taskID), " +
            "recordingID=\(request.recordingID), " +
            "audioFile=\(request.audioFileURL.path), " +
            "metadataFile=\(request.metadataFileURL?.path ?? "nil"), " +
            "sourceDuration=\(request.sourceDuration.map(String.init(describing:)) ?? "nil"), " +
            "chunkIndex=\(request.chunkDescriptor?.index.description ?? "nil"), " +
            "outputDirectory=\(request.outputDirectory.path)"
        )
        #endif
    }

    private func debugLogPreparedAudio(_ preparedAudio: AudioConversionResult) {
        #if DEBUG
        print(
            "[Rokurics][WhisperCppTranscriptionProvider] preparedAudio: " +
            "original=\(preparedAudio.originalAudioFileURL.path), " +
            "prepared=\(preparedAudio.preparedAudioFileURL.path), " +
            "didConvert=\(preparedAudio.didConvert), " +
            "workingDirectory=\(preparedAudio.workingDirectoryURL?.path ?? "nil")"
        )
        #endif
    }

    private func debugLogWhisperProcessStart(context: WhisperCppProcessLaunchContext) {
        #if DEBUG
        print(
            "[Rokurics][WhisperCppTranscriptionProvider] run: " +
            "runtimeMode=\(context.runtimeMode.rawValue), " +
            "bundledHelper=\(context.bundledHelperURL.path), " +
            "bundledHelperExists=\(context.bundledHelperExists), " +
            "configuredExecutable=\(context.configuredExecutablePath), " +
            "authorizedExecutable=\(context.restoredAuthorizedExecutableURL.path), " +
            "processExecutableURL=\(context.processExecutableURL.path), " +
            "processExecutableURLIsAbsolute=\(Self.isAbsoluteFileURL(context.processExecutableURL)), " +
            "authorizationSource=\(context.authorizationSource.rawValue), " +
            "scopeURL=\(context.scopeURL.path), " +
            "executableBookmarkBytes=\(context.executableBookmarkDataByteCount), " +
            "executableParentDirectoryBookmarkBytes=\(context.executableParentDirectoryBookmarkDataByteCount), " +
            "executableAccessStarted=\(context.executableAccessStarted), " +
            "model=\(context.modelURL.path), " +
            "modelBookmarkBytes=\(context.modelBookmarkDataByteCount), " +
            "modelAccessStarted=\(context.modelAccessStarted), " +
            "rootDirectory=\(context.rootDirectoryURL?.path ?? context.rootDirectoryConfiguredPath), " +
            "rootDirectoryBookmarkBytes=\(context.rootDirectoryBookmarkDataByteCount), " +
            "rootDirectoryAccessStarted=\(context.rootDirectoryAccessStarted), " +
            "audioFile=\(context.inputAudioURL.path), " +
            "audioExists=\(context.inputAudioExists), " +
            "audioSize=\(context.inputAudioSize), " +
            "arguments=\(Self.argumentsDescription(context.arguments)), " +
            "outputPrefix=\(context.outputPrefix.path), " +
            "expectedTxt=\(context.expectedTextURL.path), " +
            "currentDirectoryURL=\(context.currentDirectoryURL?.path ?? "nil"), " +
            "fallback=\(context.fallbackNote ?? "none")"
        )
        #endif
    }

    private func debugLogWhisperProcessExit(exitCode: Int32, stdout: String, stderr: String) {
        #if DEBUG
        print(
            "[Rokurics][WhisperCppTranscriptionProvider] exit: " +
            "exitCode=\(exitCode), " +
            "stdout=\(Self.limited(stdout.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000)), " +
            "stderr=\(Self.limited(stderr.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 1000))"
        )
        #endif
    }

    private static func debugLogLiveProcessConfiguration(_ process: Process) {
        #if DEBUG
        let executableURL = process.executableURL
        print(
            "[Rokurics][WhisperCppTranscriptionProvider] process.configuration: " +
            "processExecutableURLPath=\(executableURL?.path ?? "nil"), " +
            "processExecutableURLIsFileURL=\(executableURL?.isFileURL ?? false), " +
            "processExecutableURLAbsoluteString=\(executableURL?.absoluteString ?? "nil"), " +
            "currentDirectoryURL=\(process.currentDirectoryURL?.path ?? "nil"), " +
            "currentDirectoryPath=\(FileManager.default.currentDirectoryPath)"
        )
        #endif
    }

    private static func debugLogWhisperProcessLaunchFailure(error: Error, context: WhisperCppProcessLaunchContext) {
        #if DEBUG
        let nsError = error as NSError
        print(
            "[Rokurics][WhisperCppTranscriptionProvider] process.run threw: " +
            "runtimeMode=\(context.runtimeMode.rawValue), " +
            "bundledHelper=\(context.bundledHelperURL.path), " +
            "bundledHelperExists=\(context.bundledHelperExists), " +
            "configuredExecutable=\(context.configuredExecutablePath), " +
            "authorizedExecutable=\(context.restoredAuthorizedExecutableURL.path), " +
            "processExecutableURL=\(context.processExecutableURL.path), " +
            "processExecutableURLIsAbsolute=\(Self.isAbsoluteFileURL(context.processExecutableURL)), " +
            "authorizationSource=\(context.authorizationSource.rawValue), " +
            "scopeURL=\(context.scopeURL.path), " +
            "executableAccessStarted=\(context.executableAccessStarted), " +
            "modelAccessStarted=\(context.modelAccessStarted), " +
            "rootDirectory=\(context.rootDirectoryURL?.path ?? context.rootDirectoryConfiguredPath), " +
            "rootDirectoryAccessStarted=\(context.rootDirectoryAccessStarted), " +
            "inputAudio=\(context.inputAudioURL.path), " +
            "inputAudioExists=\(context.inputAudioExists), " +
            "inputAudioSize=\(context.inputAudioSize), " +
            "outputPrefix=\(context.outputPrefix.path), " +
            "expectedTxt=\(context.expectedTextURL.path), " +
            "nsErrorDomain=\(nsError.domain), " +
            "nsErrorCode=\(nsError.code), " +
            "localizedDescription=\(nsError.localizedDescription)"
        )
        #endif
    }

    private static func debugLogWhisperExecutableParentFallback(previousFailure: String) {
        #if DEBUG
        print(
            "[Rokurics][WhisperCppTranscriptionProvider] executable fallback: " +
            "from=fileBookmark, to=parentDirectoryBookmark, " +
            "previousFailure=\(Self.limited(previousFailure, maxCharacters: 500))"
        )
        #endif
    }

    private static func debugLogLaunchProbe(_ diagnosticMessage: String) {
        #if DEBUG
        print("[Rokurics][WhisperCppTranscriptionProvider] launchProbe: \(diagnosticMessage)")
        #endif
    }

    private func debugLogTextOutput(_ textURL: URL) {
        #if DEBUG
        let values = try? textURL.resourceValues(forKeys: [.fileSizeKey])
        let size = values?.fileSize ?? 0
        print(
            "[Rokurics][WhisperCppTranscriptionProvider] textOutput: " +
            "expectedTxt=\(textURL.path), " +
            "exists=\(fileManager.fileExists(atPath: textURL.path)), " +
            "size=\(size)"
        )
        #endif
    }

    private static func seconds(from timestamp: String) -> Double? {
        let normalized = timestamp
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = normalized.split(separator: ":")

        guard parts.count == 3,
              let hours = Double(parts[0]),
              let minutes = Double(parts[1]),
              let seconds = Double(parts[2]) else {
            return nil
        }

        return hours * 3600 + minutes * 60 + seconds
    }

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

    private struct WhisperCppJSONOutput: Decodable {
        let transcription: [WhisperCppJSONSegment]?
    }

    private struct WhisperCppJSONSegment: Decodable {
        let text: String
        let timestamps: WhisperCppJSONTimestamps?
        let offsets: WhisperCppJSONOffsets?
    }

    private struct WhisperCppJSONTimestamps: Decodable {
        let from: String?
        let to: String?
    }

    private struct WhisperCppJSONOffsets: Decodable {
        let from: Int?
        let to: Int?
    }

    private static let jsonDecoder = JSONDecoder()

    private static let whisperExecutableErrors = ExecutableValidationErrors(
        pathMissing: .executablePathMissing,
        notFound: .executableNotFound,
        isDirectory: .executableIsDirectory,
        notExecutable: .executableNotExecutable,
        sandboxAccessDenied: .executableSandboxAccessDenied,
        executableEntitlementMissing: .executableEntitlementMissing,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )

    private static let modelFileErrors = ReadableFileValidationErrors(
        pathMissing: .modelPathMissing,
        notFound: .modelNotFound,
        isDirectory: .modelIsDirectory,
        sandboxAccessDenied: .modelSandboxAccessDenied,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )

    private static let whisperCppRootDirectoryErrors = ReadableDirectoryValidationErrors(
        pathMissing: .whisperCppRootDirectoryPathMissing,
        notFound: .whisperCppRootDirectoryNotFound,
        isFile: .whisperCppRootDirectoryIsFile,
        sandboxAccessDenied: .whisperCppRootDirectorySandboxAccessDenied,
        bookmarkEntitlementMissing: .bookmarkEntitlementMissing
    )
}
