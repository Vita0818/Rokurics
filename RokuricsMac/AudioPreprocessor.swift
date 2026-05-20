//
//  AudioPreprocessor.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/15.
//

import Foundation

protocol AudioConverting {
    func convertToWhisperWAV(inputURL: URL, outputURL: URL) async throws
}

extension AudioConverting {
    func convertToWhisperWAV(inputURL: URL, outputURL: URL, timeRange: ClosedRange<TimeInterval>?) async throws {
        try await convertToWhisperWAV(inputURL: inputURL, outputURL: outputURL)
    }
}

struct AudioPreprocessor {
    private static let directlyReadableExtensions: Set<String> = ["wav", "wave"]

    private let configuration: AudioPreprocessorConfiguration
    private let converter: any AudioConverting
    private let fileManager: FileManager
    private let securityScopedEnvironment: SecurityScopedFileAccessEnvironment

    init(
        configuration: AudioPreprocessorConfiguration,
        converter: (any AudioConverting)? = nil,
        fileManager: FileManager = .default,
        securityScopedEnvironment: SecurityScopedFileAccessEnvironment = .live
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.securityScopedEnvironment = securityScopedEnvironment
        self.converter = converter ?? Self.makeConverter(
            configuration: configuration,
            fileManager: fileManager,
            securityScopedEnvironment: securityScopedEnvironment
        )
    }

    func validateConfigurationForConvertibleInput() throws {
        guard configuration.conversionStrategy.requiresFFmpegForConfigurationValidation else {
            return
        }

        try FFmpegAudioConverter.validateExecutable(
            atPath: configuration.resolvedFFmpegExecutablePath,
            bookmarkData: configuration.ffmpegExecutableBookmarkData,
            parentDirectoryPath: configuration.ffmpegExecutableParentDirectoryPath,
            parentDirectoryBookmarkData: configuration.ffmpegExecutableParentDirectoryBookmarkData,
            fileManager: fileManager,
            securityScopedEnvironment: securityScopedEnvironment
        )
    }

    func prepareAudio(for request: TranscriptionRequest) async throws -> AudioConversionResult {
        try Task.checkCancellation()
        try validateInputAudio(request.audioFileURL)

        guard Self.requiresConversion(request.audioFileURL) else {
            return AudioConversionResult(
                originalAudioFileURL: request.audioFileURL,
                preparedAudioFileURL: request.audioFileURL,
                didConvert: false,
                workingDirectoryURL: nil
            )
        }

        let workingDirectoryURL = try conversionWorkingDirectory(for: request)
        try fileManager.createDirectory(at: workingDirectoryURL, withIntermediateDirectories: true)

        let outputURL = workingDirectoryURL
            .appendingPathComponent(outputFileName(for: request), isDirectory: false)
            .standardizedFileURL

        debugLogConversionPaths(request: request, workingDirectoryURL: workingDirectoryURL, outputURL: outputURL)
        do {
            try await converter.convertToWhisperWAV(
                inputURL: request.audioFileURL,
                outputURL: outputURL,
                timeRange: request.chunkDescriptor.map { $0.startTime...$0.endTime }
            )
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.nativeAudioConversionFailed(
                stage: "audio preprocessing",
                message: error.localizedDescription
            )
        }
        try Task.checkCancellation()
        try validateConvertedAudio(outputURL)

        return AudioConversionResult(
            originalAudioFileURL: request.audioFileURL,
            preparedAudioFileURL: outputURL,
            didConvert: true,
            workingDirectoryURL: workingDirectoryURL
        )
    }

    static func requiresConversion(_ audioFileURL: URL) -> Bool {
        let fileExtension = audioFileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !directlyReadableExtensions.contains(fileExtension)
    }

    static func sanitizedPathComponent(_ value: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let sanitized = value.unicodeScalars
            .map { allowedCharacters.contains($0) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        return String(sanitized.prefix(96))
    }

    private func validateInputAudio(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw TranscriptionError.audioFileMissing
        }
    }

    private func validateConvertedAudio(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            if configuration.conversionStrategy == .ffmpegOnly {
                throw TranscriptionError.convertedAudioMissing(
                    "ffmpeg 转码完成后没有生成 wav 文件：\nstage=audio preprocessing\nconvertedWav=\(url.path)"
                )
            }

            throw TranscriptionError.nativeOutputWAVMissing(
                "native audio conversion failed: output wav missing: stage=audio preprocessing; convertedWav=\(url.path)"
            )
        }

        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        guard (values?.fileSize ?? 0) > 0 else {
            if configuration.conversionStrategy == .ffmpegOnly {
                throw TranscriptionError.convertedAudioMissing(
                    "ffmpeg 转码完成后生成了空 wav 文件：\nstage=audio preprocessing\nconvertedWav=\(url.path)"
                )
            }

            throw TranscriptionError.nativeOutputWAVEmpty(
                "native audio conversion failed: output wav empty: stage=audio preprocessing; convertedWav=\(url.path)"
            )
        }
    }

    private static func makeConverter(
        configuration: AudioPreprocessorConfiguration,
        fileManager: FileManager,
        securityScopedEnvironment: SecurityScopedFileAccessEnvironment
    ) -> any AudioConverting {
        switch configuration.conversionStrategy {
        case .nativePreferred:
            return NativeAudioConverter(fileManager: fileManager)
        case .ffmpegOnly:
            return ffmpegConverter(
                configuration: configuration,
                fileManager: fileManager,
                securityScopedEnvironment: securityScopedEnvironment
            )
        case .nativeThenFFmpegFallback:
            return NativeThenFFmpegAudioConverter(
                nativeConverter: NativeAudioConverter(fileManager: fileManager),
                ffmpegConverter: ffmpegConverter(
                    configuration: configuration,
                    fileManager: fileManager,
                    securityScopedEnvironment: securityScopedEnvironment
                )
            )
        }
    }

    private static func ffmpegConverter(
        configuration: AudioPreprocessorConfiguration,
        fileManager: FileManager,
        securityScopedEnvironment: SecurityScopedFileAccessEnvironment
    ) -> FFmpegAudioConverter {
        FFmpegAudioConverter(
            executablePath: configuration.resolvedFFmpegExecutablePath,
            executableBookmarkData: configuration.ffmpegExecutableBookmarkData,
            executableParentDirectoryPath: configuration.ffmpegExecutableParentDirectoryPath,
            executableParentDirectoryBookmarkData: configuration.ffmpegExecutableParentDirectoryBookmarkData,
            fileManager: fileManager,
            securityScopedEnvironment: securityScopedEnvironment
        )
    }

    private struct NativeThenFFmpegAudioConverter: AudioConverting {
        let nativeConverter: any AudioConverting
        let ffmpegConverter: any AudioConverting

        func convertToWhisperWAV(inputURL: URL, outputURL: URL) async throws {
            try await convertToWhisperWAV(inputURL: inputURL, outputURL: outputURL, timeRange: nil)
        }

        func convertToWhisperWAV(inputURL: URL, outputURL: URL, timeRange: ClosedRange<TimeInterval>?) async throws {
            do {
                try await nativeConverter.convertToWhisperWAV(inputURL: inputURL, outputURL: outputURL, timeRange: timeRange)
            } catch {
                debugLogFallback(error: error, inputURL: inputURL, outputURL: outputURL)
                try await ffmpegConverter.convertToWhisperWAV(inputURL: inputURL, outputURL: outputURL, timeRange: timeRange)
            }
        }

        private func debugLogFallback(error: Error, inputURL: URL, outputURL: URL) {
            #if DEBUG
            print(
                "[Rokurics][AudioPreprocessor] fallback: " +
                "from=native, to=ffmpeg, " +
                "inputAudio=\(inputURL.path), " +
                "outputWav=\(outputURL.path), " +
                "reason=\(error.localizedDescription)"
            )
            #endif
        }
    }

    private func conversionWorkingDirectory(for request: TranscriptionRequest) throws -> URL {
        let safeRecordingID = Self.sanitizedPathComponent(request.recordingID)
        let safeTaskID = Self.sanitizedPathComponent(request.taskID)
        let directoryName = [safeRecordingID, safeTaskID]
            .filter { !$0.isEmpty }
            .joined(separator: "-")

        guard !directoryName.isEmpty else {
            throw TranscriptionError.outputDirectoryUnavailable
        }

        let outputDirectory = request.outputDirectory.standardizedFileURL
        let workingDirectoryURL = outputDirectory
            .appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
            .standardizedFileURL

        guard isInside(workingDirectoryURL, parent: outputDirectory) else {
            throw TranscriptionError.outputDirectoryUnavailable
        }

        return workingDirectoryURL
    }

    private func outputFileName(for request: TranscriptionRequest) -> String {
        guard let chunkDescriptor = request.chunkDescriptor else {
            return "audio.wav"
        }

        return "\(chunkDescriptor.id).wav"
    }

    private func isInside(_ url: URL, parent: URL) -> Bool {
        let parentPath = parent.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        return filePath == parentPath || filePath.hasPrefix(parentPath + "/")
    }

    private func debugLogConversionPaths(
        request: TranscriptionRequest,
        workingDirectoryURL: URL,
        outputURL: URL
    ) {
        #if DEBUG
        let inputValues = try? request.audioFileURL.resourceValues(forKeys: [.fileSizeKey])
        print(
            "[Rokurics][AudioPreprocessor] convert: " +
            "converterStrategy=\(configuration.conversionStrategy.displayText), " +
            "taskID=\(request.taskID), " +
            "recordingID=\(request.recordingID), " +
            "inputAudio=\(request.audioFileURL.path), " +
            "inputExists=\(fileManager.fileExists(atPath: request.audioFileURL.path)), " +
            "inputSize=\(inputValues?.fileSize ?? 0), " +
            "workingDirectory=\(workingDirectoryURL.path), " +
            "workingWav=\(outputURL.path)"
        )
        #endif
    }
}
