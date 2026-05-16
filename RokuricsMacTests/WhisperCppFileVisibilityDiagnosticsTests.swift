//
//  WhisperCppFileVisibilityDiagnosticsTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/5/16.
//

import Darwin
import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct WhisperCppFileVisibilityDiagnosticsTests {
    @Test func fileVisibilityProbeStartsAccessAndChecksExpectedPaths() throws {
        let fixture = try makeWhisperCppFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let recorder = SecurityScopeRecorder()
        let diagnostics = WhisperCppFileVisibilityDiagnostics(
            configuration: fixture.configuration,
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                rootBookmark: fixture.rootBookmark,
                rootURL: fixture.rootURL,
                executableBookmark: fixture.executableBookmark,
                executableURL: fixture.executableURL,
                modelBookmark: fixture.modelBookmark,
                modelURL: fixture.modelURL,
                recorder: recorder
            )
        )

        let result = diagnostics.run()

        #expect(result.rootDirectoryAccessStarted)
        #expect(result.executableAccessStarted)
        #expect(result.modelAccessStarted)
        #expect(recorder.startedPaths.contains(fixture.rootURL.path))
        #expect(recorder.startedPaths.contains(fixture.executableURL.path))
        #expect(recorder.startedPaths.contains(fixture.modelURL.path))
        #expect(result.pathResult(label: "root")?.fileExists == true)
        #expect(result.pathResult(label: "build")?.fileExists == true)
        #expect(result.pathResult(label: "build/bin")?.isDirectory == true)
        #expect(result.pathResult(label: "models")?.isDirectory == true)

        let executable = try #require(result.pathResult(label: "build/bin/whisper-cli"))
        #expect(executable.fileExists)
        #expect(executable.isReadable)
        #expect(executable.isExecutable)
        #expect(executable.checkResourceIsReachable)
        #expect(executable.posixReadAccessResult == "0")
        #expect(executable.posixExecuteAccessResult == "0")
        #expect(executable.posixStatResult == "0")
        #expect(executable.posixStatMode.hasSuffix("100755"))
        #expect(executable.posixStatSize != "unavailable")
    }

    @Test func fileVisibilityProbeListsEntriesTruncatesAndFiltersDylibs() throws {
        let fixture = try makeWhisperCppFixture(extraBinEntryCount: 36)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let result = WhisperCppFileVisibilityDiagnostics(
            configuration: fixture.configuration,
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                rootBookmark: fixture.rootBookmark,
                rootURL: fixture.rootURL,
                executableBookmark: fixture.executableBookmark,
                executableURL: fixture.executableURL,
                modelBookmark: fixture.modelBookmark,
                modelURL: fixture.modelURL
            )
        ).run()

        let buildBin = try #require(result.pathResult(label: "build/bin"))
        #expect(buildBin.directoryEntries.count == 30)
        #expect(buildBin.directoryEntryCount == 37)
        #expect(buildBin.directoryEntriesTruncated)
        #expect(result.userSummary.contains("truncated(total=37)"))

        let buildSrc = try #require(result.pathResult(label: "build/src"))
        #expect(buildSrc.dylibRelatedEntries.contains("libwhisper.1.dylib"))

        let ggmlSrc = try #require(result.pathResult(label: "build/ggml/src"))
        #expect(ggmlSrc.dylibRelatedEntries.contains("libggml.0.dylib"))

        let blas = try #require(result.pathResult(label: "build/ggml/src/ggml-blas"))
        #expect(blas.dylibRelatedEntries.contains("libggml-blas.0.dylib"))

        let metal = try #require(result.pathResult(label: "build/ggml/src/ggml-metal"))
        #expect(metal.dylibRelatedEntries.contains("libggml-metal.0.dylib"))
        #expect(result.keyConclusion.contains("dylibDirsVisible=true"))
        #expect(result.keyConclusion.contains("dylibFilesVisible=true"))
    }

    @Test func fileVisibilityProbeDoesNotExposeBookmarkDataOrFileContents() throws {
        let fixture = try makeWhisperCppFixture(secretFileContent: "SECRET_CONTENT_SHOULD_NOT_APPEAR")
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let result = WhisperCppFileVisibilityDiagnostics(
            configuration: fixture.configuration,
            securityScopedEnvironment: makeSecurityScopedEnvironment(
                rootBookmark: fixture.rootBookmark,
                rootURL: fixture.rootURL,
                executableBookmark: fixture.executableBookmark,
                executableURL: fixture.executableURL,
                modelBookmark: fixture.modelBookmark,
                modelURL: fixture.modelURL
            )
        ).run()

        #expect(!result.userSummary.contains("bookmarkData"))
        #expect(!result.debugLogMessage.contains("bookmarkData"))
        #expect(!result.userSummary.contains("SECRET_CONTENT_SHOULD_NOT_APPEAR"))
        #expect(!result.debugLogMessage.contains("SECRET_CONTENT_SHOULD_NOT_APPEAR"))
        #expect(!result.debugLogMessage.contains("sharedSecret"))
        #expect(!result.debugLogMessage.contains("HMAC"))
    }
}

private struct WhisperCppFixture {
    let rootURL: URL
    let executableURL: URL
    let modelURL: URL
    let rootBookmark: Data
    let executableBookmark: Data
    let modelBookmark: Data
    let configuration: WhisperCppTranscriptionConfiguration
}

private final class SecurityScopeRecorder {
    var startedPaths: [String] = []
    var stoppedPaths: [String] = []
}

private func makeWhisperCppFixture(
    extraBinEntryCount: Int = 0,
    secretFileContent: String = "fixture"
) throws -> WhisperCppFixture {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("RokuricsWhisperVisibility-\(UUID().uuidString)", isDirectory: true)
    let buildBinURL = rootURL.appendingPathComponent("build/bin", isDirectory: true)
    let buildSrcURL = rootURL.appendingPathComponent("build/src", isDirectory: true)
    let ggmlSrcURL = rootURL.appendingPathComponent("build/ggml/src", isDirectory: true)
    let ggmlBlasURL = rootURL.appendingPathComponent("build/ggml/src/ggml-blas", isDirectory: true)
    let ggmlMetalURL = rootURL.appendingPathComponent("build/ggml/src/ggml-metal", isDirectory: true)
    let modelsURL = rootURL.appendingPathComponent("models", isDirectory: true)

    for directoryURL in [
        buildBinURL,
        buildSrcURL,
        ggmlSrcURL,
        ggmlBlasURL,
        ggmlMetalURL,
        modelsURL
    ] {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    let executableURL = buildBinURL.appendingPathComponent("whisper-cli", isDirectory: false)
    try writeFile(at: executableURL, content: secretFileContent, permissions: 0o755)
    let modelURL = modelsURL.appendingPathComponent("ggml-small.bin", isDirectory: false)
    try writeFile(at: modelURL, content: "model fixture", permissions: 0o644)
    try writeFile(
        at: buildSrcURL.appendingPathComponent("libwhisper.1.dylib", isDirectory: false),
        content: "dylib fixture",
        permissions: 0o644
    )
    try writeFile(
        at: ggmlSrcURL.appendingPathComponent("libggml.0.dylib", isDirectory: false),
        content: "dylib fixture",
        permissions: 0o644
    )
    try writeFile(
        at: ggmlBlasURL.appendingPathComponent("libggml-blas.0.dylib", isDirectory: false),
        content: "dylib fixture",
        permissions: 0o644
    )
    try writeFile(
        at: ggmlMetalURL.appendingPathComponent("libggml-metal.0.dylib", isDirectory: false),
        content: "dylib fixture",
        permissions: 0o644
    )

    for index in 0..<extraBinEntryCount {
        try writeFile(
            at: buildBinURL.appendingPathComponent(String(format: "extra-%02d", index), isDirectory: false),
            content: "extra",
            permissions: 0o644
        )
    }

    let rootBookmark = Data([1, 8, 3, 5])
    let executableBookmark = Data([2, 8, 3, 5])
    let modelBookmark = Data([3, 8, 3, 5])
    let configuration = WhisperCppTranscriptionConfiguration(
        executablePath: executableURL.path,
        modelPath: modelURL.path,
        ffmpegExecutablePath: nil,
        whisperCppRootDirectoryPath: rootURL.path,
        whisperCppRootDirectoryBookmarkData: rootBookmark,
        executableBookmarkData: executableBookmark,
        modelBookmarkData: modelBookmark,
        ffmpegExecutableBookmarkData: nil,
        defaultLanguage: "zh",
        preferSegmentOutput: false
    )

    return WhisperCppFixture(
        rootURL: rootURL,
        executableURL: executableURL,
        modelURL: modelURL,
        rootBookmark: rootBookmark,
        executableBookmark: executableBookmark,
        modelBookmark: modelBookmark,
        configuration: configuration
    )
}

private func writeFile(at url: URL, content: String, permissions: Int) throws {
    try Data(content.utf8).write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: permissions)],
        ofItemAtPath: url.path
    )
}

private func makeSecurityScopedEnvironment(
    rootBookmark: Data,
    rootURL: URL,
    executableBookmark: Data,
    executableURL: URL,
    modelBookmark: Data,
    modelURL: URL,
    recorder: SecurityScopeRecorder = SecurityScopeRecorder()
) -> SecurityScopedFileAccessEnvironment {
    let bookmarkURLs: [Data: URL] = [
        rootBookmark: rootURL,
        executableBookmark: executableURL,
        modelBookmark: modelURL
    ]

    return SecurityScopedFileAccessEnvironment(
        hasEntitlement: { _ in true },
        resolveBookmark: { data in
            guard let url = bookmarkURLs[data] else {
                throw CocoaError(.fileNoSuchFile)
            }
            return SecurityScopedBookmarkResolution(url: url, isStale: false)
        },
        startAccessing: { url in
            recorder.startedPaths.append(url.path)
            return true
        },
        stopAccessing: { url in
            recorder.stoppedPaths.append(url.path)
        }
    )
}
