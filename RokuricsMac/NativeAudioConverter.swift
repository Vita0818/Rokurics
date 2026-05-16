//
//  NativeAudioConverter.swift
//  RokuricsMac
//
//  Created by Codex on 2026/5/16.
//

import AVFoundation
import Foundation

struct NativeAudioConverter: AudioConverting {
    static let targetSampleRate: Double = 16_000
    static let targetChannelCount: AVAudioChannelCount = 1
    static let targetBitDepth = 16

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func convertToWhisperWAV(inputURL: URL, outputURL: URL) async throws {
        try convertSynchronously(inputURL: inputURL, outputURL: outputURL)
    }

    private func convertSynchronously(inputURL: URL, outputURL: URL) throws {
        try Task.checkCancellation()
        debugLogStart(inputURL: inputURL, outputURL: outputURL)

        guard let targetFormat = Self.makeTargetFormat() else {
            throw TranscriptionError.nativeAudioConverterFailed(
                stage: "target format setup",
                message: "could not create 16kHz mono PCM format"
            )
        }

        try prepareOutputURL(outputURL)
        let outputFile = try makeOutputFile(outputURL: outputURL, targetFormat: targetFormat)
        try convertWithAssetReader(inputURL: inputURL, outputFile: outputFile, targetFormat: targetFormat)
        try validateOutputWAV(outputURL)
        debugLogCompleted(outputURL: outputURL)
    }

    private func convertWithAssetReader(
        inputURL: URL,
        outputFile: AVAudioFile,
        targetFormat: AVAudioFormat
    ) throws {
        let asset = AVURLAsset(url: inputURL)
        let tracks = asset.tracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "asset reader setup",
                message: "no audio track"
            )
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "asset reader setup",
                message: error.localizedDescription
            )
        }

        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: Self.targetWAVSettings)
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else {
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "asset reader setup",
                message: "cannot add audio track output for 16kHz mono PCM"
            )
        }

        reader.add(trackOutput)
        guard reader.startReading() else {
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "asset reader start",
                message: reader.error?.localizedDescription ?? "unknown reader start failure"
            )
        }

        var didLogSourceFormat = false
        while reader.status == .reading {
            try Task.checkCancellation()
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else {
                break
            }

            let pcmBuffer = try makePCMBuffer(from: sampleBuffer)
            if !didLogSourceFormat {
                debugLogSourceFormat(pcmBuffer.format)
                didLogSourceFormat = true
            }
            if Self.formatsAreCompatible(pcmBuffer.format, targetFormat) {
                try write(buffer: pcmBuffer, to: outputFile)
            } else {
                try convertAndWrite(buffer: pcmBuffer, targetFormat: targetFormat, outputFile: outputFile)
            }
        }

        switch reader.status {
        case .completed, .reading:
            return
        case .failed:
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "asset reading",
                message: reader.error?.localizedDescription ?? "asset reader failed"
            )
        case .cancelled:
            throw TranscriptionError.cancelled
        case .unknown:
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "asset reading",
                message: "asset reader ended with unknown status"
            )
        @unknown default:
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "asset reading",
                message: "asset reader ended with unsupported status"
            )
        }
    }

    private func makePCMBuffer(from sampleBuffer: CMSampleBuffer) throws -> AVAudioPCMBuffer {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "sample buffer format",
                message: "missing audio format description"
            )
        }

        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "sample buffer allocation",
                message: "format=\(Self.formatDescription(format)); frameCount=\(frameCount)"
            )
        }

        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else {
            throw TranscriptionError.nativeAudioReaderFailed(
                stage: "sample buffer copy",
                message: "osStatus=\(status)"
            )
        }

        return buffer
    }

    private func prepareOutputURL(_ outputURL: URL) throws {
        do {
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }
        } catch {
            throw TranscriptionError.nativeWAVWritingFailed(
                stage: "output preparation",
                message: error.localizedDescription
            )
        }
    }

    private func makeOutputFile(outputURL: URL, targetFormat: AVAudioFormat) throws -> AVAudioFile {
        do {
            return try AVAudioFile(
                forWriting: outputURL,
                settings: Self.targetWAVSettings,
                commonFormat: targetFormat.commonFormat,
                interleaved: targetFormat.isInterleaved
            )
        } catch {
            throw TranscriptionError.nativeWAVWritingFailed(
                stage: "wav writing setup",
                message: error.localizedDescription
            )
        }
    }

    private func convertAndWrite(
        buffer inputBuffer: AVAudioPCMBuffer,
        targetFormat: AVAudioFormat,
        outputFile: AVAudioFile
    ) throws {
        guard let converter = AVAudioConverter(from: inputBuffer.format, to: targetFormat) else {
            throw TranscriptionError.nativeAudioConverterFailed(
                stage: "converter setup",
                message: "sourceFormat=\(Self.formatDescription(inputBuffer.format)); targetFormat=\(Self.formatDescription(targetFormat))"
            )
        }

        let outputCapacity = Self.outputCapacity(
            forInputCapacity: inputBuffer.frameLength,
            sourceFormat: inputBuffer.format
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw TranscriptionError.nativeAudioConverterFailed(
                stage: "output buffer allocation",
                message: "targetFormat=\(Self.formatDescription(targetFormat))"
            )
        }

        var inputBufferConsumed = false
        var conversionFinished = false

        while !conversionFinished {
            try Task.checkCancellation()
            outputBuffer.frameLength = 0
            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if !inputBufferConsumed {
                    inputBufferConsumed = true
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                outStatus.pointee = .endOfStream
                return nil
            }

            if let conversionError {
                throw TranscriptionError.nativeAudioConverterFailed(
                    stage: "audio conversion",
                    message: conversionError.localizedDescription
                )
            }

            if outputBuffer.frameLength > 0 {
                try write(buffer: outputBuffer, to: outputFile)
            }

            switch status {
            case .haveData, .inputRanDry:
                conversionFinished = inputBufferConsumed && outputBuffer.frameLength == 0
            case .endOfStream:
                conversionFinished = true
            case .error:
                throw TranscriptionError.nativeAudioConverterFailed(
                    stage: "audio conversion",
                    message: "AVAudioConverter returned error"
                )
            @unknown default:
                throw TranscriptionError.nativeAudioConverterFailed(
                    stage: "audio conversion",
                    message: "AVAudioConverter returned unknown status"
                )
            }
        }
    }

    private func write(buffer: AVAudioPCMBuffer, to outputFile: AVAudioFile) throws {
        do {
            try outputFile.write(from: buffer)
        } catch {
            throw TranscriptionError.nativeWAVWritingFailed(
                stage: "wav writing",
                message: error.localizedDescription
            )
        }
    }

    private func validateOutputWAV(_ outputURL: URL) throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw TranscriptionError.nativeOutputWAVMissing(
                "native audio conversion failed: output wav missing: stage=output validation; path=\(outputURL.path)"
            )
        }

        let values = try? outputURL.resourceValues(forKeys: [.fileSizeKey])
        guard (values?.fileSize ?? 0) > 0 else {
            throw TranscriptionError.nativeOutputWAVEmpty(
                "native audio conversion failed: output wav empty: stage=output validation; path=\(outputURL.path)"
            )
        }
    }

    static func makeTargetFormat() -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: true
        )
    }

    static var targetWAVSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: Int(targetChannelCount),
            AVLinearPCMBitDepthKey: targetBitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private static func outputCapacity(
        forInputCapacity inputCapacity: AVAudioFrameCount,
        sourceFormat: AVAudioFormat
    ) -> AVAudioFrameCount {
        let ratio = targetSampleRate / max(sourceFormat.sampleRate, 1)
        let frames = ceil(Double(inputCapacity) * ratio) + 512
        return AVAudioFrameCount(max(1_024, frames))
    }

    private static func formatDescription(_ format: AVAudioFormat) -> String {
        "sampleRate=\(format.sampleRate), channels=\(format.channelCount), commonFormat=\(format.commonFormat.rawValue), interleaved=\(format.isInterleaved)"
    }

    private static func formatsAreCompatible(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        abs(lhs.sampleRate - rhs.sampleRate) < 0.01
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private func debugLogStart(inputURL: URL, outputURL: URL) {
        #if DEBUG
        let inputValues = try? inputURL.resourceValues(forKeys: [.fileSizeKey])
        let asset = AVURLAsset(url: inputURL)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        print(
            "[Rokurics][NativeAudioConverter] start: " +
            "converterStrategy=native, " +
            "inputAudio=\(inputURL.path), " +
            "outputWav=\(outputURL.path), " +
            "inputExists=\(fileManager.fileExists(atPath: inputURL.path)), " +
            "inputSize=\(inputValues?.fileSize ?? 0), " +
            "assetDuration=\(durationSeconds.isFinite ? durationSeconds : 0), " +
            "assetAudioTracks=\(asset.tracks(withMediaType: .audio).count), " +
            "targetFormat=sampleRate=\(Self.targetSampleRate),channels=\(Self.targetChannelCount),pcm_s16le"
        )
        #endif
    }

    private func debugLogSourceFormat(_ format: AVAudioFormat) {
        #if DEBUG
        print(
            "[Rokurics][NativeAudioConverter] source: " +
            "sourceFormat=\(Self.formatDescription(format))"
        )
        #endif
    }

    private func debugLogCompleted(outputURL: URL) {
        #if DEBUG
        let values = try? outputURL.resourceValues(forKeys: [.fileSizeKey])
        print(
            "[Rokurics][NativeAudioConverter] completed: " +
            "outputWav=\(outputURL.path), " +
            "outputExists=\(fileManager.fileExists(atPath: outputURL.path)), " +
            "outputSize=\(values?.fileSize ?? 0)"
        )
        #endif
    }
}
