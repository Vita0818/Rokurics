//
//  WhisperCppTranscriptionProvider.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/13.
//

import Foundation

struct WhisperCppTranscriptionProvider: TranscriptionProvider {
    let id = "whisperCpp"
    let displayName = "whisper.cpp"

    private let configuration: WhisperCppTranscriptionConfiguration
    private let fileManager: FileManager
    private let timeout: TimeInterval

    init(
        configuration: WhisperCppTranscriptionConfiguration,
        fileManager: FileManager = .default,
        timeout: TimeInterval = 30 * 60
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.timeout = timeout
    }

    func validateConfiguration() async throws {
        try validateExecutable()
        try validateModel()
        try validateDefaultOutputDirectory()
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult {
        try Task.checkCancellation()
        try await validateConfiguration()
        try validateAudioFile(request.audioFileURL)
        try validateOutputDirectory(request.outputDirectory)

        let startedAt = Date()
        let outputPrefix = try outputPrefixURL(for: request)
        let arguments = whisperArguments(
            audioFileURL: request.audioFileURL,
            outputPrefix: outputPrefix,
            language: request.language ?? configuration.normalizedLanguage
        )

        let output = try await runWhisperProcess(arguments: arguments)
        try Task.checkCancellation()

        guard output.exitCode == 0 else {
            throw TranscriptionError.processFailed(
                exitCode: output.exitCode,
                message: processFailureMessage(
                    exitCode: output.exitCode,
                    stderr: output.stderr,
                    audioFileURL: request.audioFileURL
                )
            )
        }

        let text = try readTextOutput(outputPrefix: outputPrefix)
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
        let path = expandedPath(configuration.normalizedExecutablePath)
        guard !path.isEmpty else {
            throw TranscriptionError.executablePathMissing
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw TranscriptionError.executableNotFound
        }

        guard !isDirectory.boolValue else {
            throw TranscriptionError.executableIsDirectory
        }

        guard fileManager.isExecutableFile(atPath: path) else {
            throw TranscriptionError.executableNotExecutable
        }
    }

    private func validateModel() throws {
        let path = expandedPath(configuration.normalizedModelPath)
        guard !path.isEmpty else {
            throw TranscriptionError.modelPathMissing
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw TranscriptionError.modelNotFound
        }

        guard !isDirectory.boolValue else {
            throw TranscriptionError.modelIsDirectory
        }
    }

    private func validateDefaultOutputDirectory() throws {
        let applicationSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let outputURL = applicationSupportURL
            .appendingPathComponent("Rokurics", isDirectory: true)
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

    private func whisperArguments(audioFileURL: URL, outputPrefix: URL, language: String) -> [String] {
        var arguments = [
            "-m", expandedPath(configuration.normalizedModelPath),
            "-f", audioFileURL.path,
            "-l", normalizedLanguageArgument(language),
            "-otxt"
        ]

        if configuration.preferSegmentOutput {
            arguments.append("-oj")
        }

        arguments.append(contentsOf: ["-of", outputPrefix.path])
        return arguments
    }

    private func runWhisperProcess(arguments: [String]) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: expandedPath(configuration.normalizedExecutablePath))
        process.arguments = arguments

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

                func finish(_ result: Result<ProcessOutput, Error>) {
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

                    let output = ProcessOutput(
                        exitCode: terminatedProcess.terminationStatus,
                        stdout: stdoutCapture.stringValue(),
                        stderr: stderrCapture.stringValue()
                    )
                    finish(.success(output))
                }

                do {
                    try process.run()
                } catch {
                    finish(.failure(TranscriptionError.processLaunchFailed(error.localizedDescription)))
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

    private func readTextOutput(outputPrefix: URL) throws -> String {
        let textURL = outputPrefix.appendingPathExtension("txt").standardizedFileURL
        guard fileManager.fileExists(atPath: textURL.path) else {
            throw TranscriptionError.outputMissing
        }

        do {
            let data = try Data(contentsOf: textURL)
            guard let text = String(data: data, encoding: .utf8) else {
                throw TranscriptionError.outputDecodeFailed
            }

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw TranscriptionError.outputMissing
            }

            return trimmed
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.outputDecodeFailed
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

    private func processFailureMessage(exitCode: Int32, stderr: String, audioFileURL: URL) -> String {
        let stderrSnippet = limited(stderr.trimmingCharacters(in: .whitespacesAndNewlines), maxCharacters: 360)
        var message = "whisper.cpp 执行失败（退出码 \(exitCode)）"
        if !stderrSnippet.isEmpty {
            message += "：\(stderrSnippet)"
        }

        if audioFileURL.pathExtension.lowercased() == "m4a" {
            message += "。当前 whisper.cpp 可能不支持 m4a，后续需要加入 ffmpeg 转码或使用支持 m4a 的构建。"
        }

        return message
    }

    private func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
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

    private func limited(_ string: String, maxCharacters: Int) -> String {
        guard string.count > maxCharacters else {
            return string
        }

        return String(string.prefix(maxCharacters)) + "..."
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

    private struct ProcessOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
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
}

