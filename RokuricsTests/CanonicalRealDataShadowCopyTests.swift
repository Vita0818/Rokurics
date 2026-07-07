//
//  CanonicalRealDataShadowCopyTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalRealDataShadowCopyTests {
    @Test func copyWritesMetadataAndAudioDescriptorOnlyToShadowRoot() throws {
        let rootURL = Self.makeScratchRoot("IPhoneRealDataShadowCopy")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let productionRootURL = rootURL.appendingPathComponent("Production", isDirectory: true)
        let shadowRootURL = rootURL.appendingPathComponent("Shadow", isDirectory: true)
        try FileManager.default.createDirectory(at: productionRootURL, withIntermediateDirectories: true)
        let productionMarkerURL = productionRootURL.appendingPathComponent("recording.json")
        try Data("production-before".utf8).write(to: productionMarkerURL)

        let metadata = Self.recordingMetadata()
        let result = IPhoneCanonicalRealDataShadowCopyAdapter().copy(
            IPhoneCanonicalRealDataShadowCopyAdapter.Input(
                productionRootURL: productionRootURL,
                shadowRootURL: shadowRootURL,
                cleanupRootID: "iphone-root-01",
                recordings: [metadata],
                policy: .enabled(cleanupPolicy: .cleanupImmediately)
            )
        )

        #expect(result.completed)
        #expect(result.failure == nil)
        #expect(result.copiedEntryCount == 2)
        #expect(result.descriptorOnlyAudioCount == 1)
        #expect(result.equalityProofCount == 1)
        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent("metadata/recording-01.json").path))
        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent("audio-descriptors/recording-01.json").path))
        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent("audio/recording-01.m4a").path) == false)
        #expect((try? Data(contentsOf: productionMarkerURL)) == Data("production-before".utf8))
        #expect(result.diagnosticsSummary.contains(shadowRootURL.path) == false)
        #expect(result.diagnosticsSummary.contains(productionRootURL.path) == false)
    }

    @Test func runnerRejectsProductionRootTargetsAndEscapingLogicalPaths() throws {
        let rootURL = Self.makeScratchRoot("IPhoneRealDataShadowCopyGuards")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let productionRootURL = rootURL.appendingPathComponent("Production", isDirectory: true)
        try FileManager.default.createDirectory(at: productionRootURL, withIntermediateDirectories: true)

        let bytes = Data("metadata".utf8)
        let productionTarget = CanonicalRealDataShadowCopyPlan(
            sources: [
                .inline(
                    sourceID: "source-01",
                    kind: .recordingMetadata,
                    logicalName: "metadata.json",
                    targetLogicalPathToken: "metadata/recording.json",
                    bytes: bytes
                )
            ],
            target: CanonicalRealDataShadowCopyTarget(
                rootToken: CanonicalRootToken("production-root"),
                rootKind: .productionRootRejected,
                rootURL: productionRootURL,
                prohibitedProductionRootURL: productionRootURL
            ),
            policy: .enabled()
        )
        let productionResult = CanonicalRealDataShadowCopyRunner().run(plan: productionTarget)
        #expect(productionResult.completed == false)
        #expect(productionResult.failure == .targetIsProductionRoot)

        let escapingPath = CanonicalRealDataShadowCopyPlan(
            sources: [
                .inline(
                    sourceID: "source-02",
                    kind: .recordingMetadata,
                    logicalName: "metadata.json",
                    targetLogicalPathToken: "../recording.json",
                    bytes: bytes
                )
            ],
            target: CanonicalRealDataShadowCopyTarget(
                rootToken: CanonicalRootToken("shadow-root"),
                rootURL: rootURL.appendingPathComponent("Shadow", isDirectory: true),
                prohibitedProductionRootURL: productionRootURL
            ),
            policy: .enabled()
        )
        let escapingResult = CanonicalRealDataShadowCopyRunner().run(plan: escapingPath)
        #expect(escapingResult.completed == false)
        #expect(escapingResult.failure == .unsafeLogicalPathToken)
    }

    @Test func runnerRejectsSourceTargetEqualityHashMismatchAndOversizeArtifacts() throws {
        let rootURL = Self.makeScratchRoot("IPhoneRealDataShadowCopyFailures")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let productionRootURL = rootURL.appendingPathComponent("Production", isDirectory: true)
        let shadowRootURL = rootURL.appendingPathComponent("Shadow", isDirectory: true)
        try FileManager.default.createDirectory(at: productionRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shadowRootURL.appendingPathComponent("metadata", isDirectory: true), withIntermediateDirectories: true)
        let sameURL = shadowRootURL.appendingPathComponent("metadata/recording.json")
        try Data("same".utf8).write(to: sameURL)

        let sameResult = CanonicalRealDataShadowCopyRunner().run(
            plan: CanonicalRealDataShadowCopyPlan(
                sources: [
                    .file(
                        sourceID: "same-source",
                        kind: .recordingMetadata,
                        logicalName: "recording.json",
                        targetLogicalPathToken: "metadata/recording.json",
                        productionRootURL: shadowRootURL,
                        sourceURL: sameURL
                    )
                ],
                target: CanonicalRealDataShadowCopyTarget(
                    rootToken: CanonicalRootToken("shadow-root"),
                    rootURL: shadowRootURL,
                    prohibitedProductionRootURL: productionRootURL
                ),
                policy: .enabled()
            )
        )
        #expect(sameResult.failure == .sourceEqualsTarget)

        let mismatchResult = CanonicalRealDataShadowCopyRunner().run(
            plan: CanonicalRealDataShadowCopyPlan(
                sources: [
                    .inline(
                        sourceID: "mismatch-source",
                        kind: .recordingMetadata,
                        logicalName: "recording.json",
                        targetLogicalPathToken: "metadata/mismatch.json",
                        bytes: Data("actual".utf8),
                        contentHash: CanonicalHash.sha256String("wrong")
                    )
                ],
                target: CanonicalRealDataShadowCopyTarget(rootToken: CanonicalRootToken("shadow-root"), rootURL: shadowRootURL),
                policy: .enabled()
            )
        )
        #expect(mismatchResult.failure == .hashMismatch)

        let oversizedResult = IPhoneCanonicalRealDataShadowCopyAdapter().copy(
            IPhoneCanonicalRealDataShadowCopyAdapter.Input(
                productionRootURL: productionRootURL,
                shadowRootURL: shadowRootURL,
                cleanupRootID: "iphone-root-oversized",
                generatedArtifacts: [
                    IPhoneCanonicalRealDataShadowCopyAdapter.GeneratedArtifactFact(
                        artifactID: "note-01",
                        logicalPathToken: "notes/note-01.md",
                        logicalName: "note.md",
                        bytes: Data(repeating: 0x41, count: 8)
                    )
                ],
                policy: CanonicalRealDataShadowCopyPolicy(
                    isEnabled: true,
                    maxGeneratedArtifactBytes: 4
                )
            )
        )
        #expect(oversizedResult.failure == .sourceTooLarge)
    }

    @Test func shadowRootLifecycleCleansRetainsAndRefusesProductionRoot() throws {
        let rootURL = Self.makeScratchRoot("IPhoneRealDataShadowCopyCleanup")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let productionRootURL = rootURL.appendingPathComponent("Production", isDirectory: true)
        let shadowParentURL = rootURL.appendingPathComponent("Shadows", isDirectory: true)
        let currentShadowURL = shadowParentURL.appendingPathComponent("current", isDirectory: true)
        let oldShadowURL = shadowParentURL.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: productionRootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentShadowURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oldShadowURL, withIntermediateDirectories: true)
        try Data("current".utf8).write(to: currentShadowURL.appendingPathComponent("entry.json"))
        try Data("old".utf8).write(to: oldShadowURL.appendingPathComponent("entry.json"))

        let retained = CanonicalShadowRootLifecycle(
            rootID: "current",
            rootKind: .shadowCopy,
            rootURL: currentShadowURL,
            productionRootURL: productionRootURL,
            createdAt: Date(timeIntervalSince1970: 100)
        ).cleanup(
            policy: .retainForDiagnostics(maxAge: 0, maxBytes: 1),
            now: Date(timeIntervalSince1970: 200)
        )
        #expect(retained.status == .retainedForDiagnostics)
        #expect(FileManager.default.fileExists(atPath: currentShadowURL.path))
        #expect(FileManager.default.fileExists(atPath: oldShadowURL.path) == false)

        let removed = CanonicalShadowRootLifecycle(
            rootID: "current",
            rootKind: .shadowCopy,
            rootURL: currentShadowURL,
            productionRootURL: productionRootURL
        ).cleanup(policy: .cleanupImmediately)
        #expect(removed.status == .removed)
        #expect(FileManager.default.fileExists(atPath: currentShadowURL.path) == false)

        let refused = CanonicalShadowRootLifecycle(
            rootID: "production",
            rootKind: .productionRootRejected,
            rootURL: productionRootURL,
            productionRootURL: productionRootURL
        ).cleanup(policy: .cleanupImmediately)
        #expect(refused.status == .refusedProductionRoot)
        #expect(FileManager.default.fileExists(atPath: productionRootURL.path))
    }

    private static func recordingMetadata() -> RecordingMetadata {
        RecordingMetadata(
            id: "recording-01",
            title: "Lecture",
            fileName: "recording-01.m4a",
            relativeAudioPath: "audio/recording-01.m4a",
            relativeMetadataPath: "metadata/recording-01.json",
            createdAt: Date(timeIntervalSince1970: 1_000),
            endedAt: Date(timeIntervalSince1970: 1_060),
            duration: 60,
            format: "m4a",
            codec: "aac",
            sampleRate: 44_100,
            channels: 1,
            bitrate: 64_000,
            fileSize: 1_024,
            uploadStatus: "pending",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            tags: []
        )
    }

    private static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
