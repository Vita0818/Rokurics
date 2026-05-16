//
//  NativeAudioConverterTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/16.
//

import AVFoundation
import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct NativeAudioConverterTests {
    @Test func targetFormatIsWhisperCompatible() throws {
        let format = try #require(NativeAudioConverter.makeTargetFormat())

        #expect(format.sampleRate == 16_000)
        #expect(format.channelCount == 1)
        #expect(format.commonFormat == .pcmFormatInt16)
        #expect(format.isInterleaved)
        #expect(NativeAudioConverter.targetWAVSettings[AVLinearPCMBitDepthKey] as? Int == 16)
        #expect(NativeAudioConverter.targetWAVSettings[AVLinearPCMIsFloatKey] as? Bool == false)
        #expect(NativeAudioConverter.targetWAVSettings[AVLinearPCMIsBigEndianKey] as? Bool == false)
    }

    @Test func convertsGeneratedM4AToSixteenKilohertzMonoPCM16WAV() async throws {
        let scratchURL = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratchURL) }

        let inputURL = scratchURL.appendingPathComponent("input.m4a", isDirectory: false)
        let outputURL = scratchURL.appendingPathComponent("audio.wav", isDirectory: false)
        try makeM4AFixture(at: inputURL)

        try await NativeAudioConverter().convertToWhisperWAV(inputURL: inputURL, outputURL: outputURL)

        let data = try Data(contentsOf: outputURL)
        #expect(data.count > 44)
        #expect(String(data: data[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: data[8..<12], encoding: .ascii) == "WAVE")
        let formatChunk = try #require(wavChunk(named: "fmt ", in: data))
        #expect(littleEndianUInt16(data, offset: formatChunk.lowerBound) == 1)
        #expect(littleEndianUInt16(data, offset: formatChunk.lowerBound + 2) == 1)
        #expect(littleEndianUInt32(data, offset: formatChunk.lowerBound + 4) == 16_000)
        #expect(littleEndianUInt16(data, offset: formatChunk.lowerBound + 14) == 16)
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
            let phase = 2.0 * Double.pi * 440.0 * Double(frame) / sampleRate
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

    private func littleEndianUInt16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset])
            | (UInt16(data[offset + 1]) << 8)
    }

    private func littleEndianUInt32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func wavChunk(named name: String, in data: Data) -> Range<Int>? {
        var offset = 12
        while offset + 8 <= data.count {
            let chunkName = String(data: data[offset..<(offset + 4)], encoding: .ascii)
            let chunkSize = Int(littleEndianUInt32(data, offset: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize
            guard chunkEnd <= data.count else {
                return nil
            }

            if chunkName == name {
                return chunkStart..<chunkEnd
            }

            offset = chunkEnd + (chunkSize % 2)
        }

        return nil
    }
}
