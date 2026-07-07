//
//  CanonicalRealDataShadowCopyTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/3.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalRealDataShadowCopyTests {
    @Test func macAdapterWritesReceiveRecordAndDescriptorsOnlyToShadowRoot() throws {
        let rootURL = Self.makeScratchRoot("MacRealDataShadowCopy")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let productionRootURL = rootURL.appendingPathComponent("Production", isDirectory: true)
        let shadowRootURL = rootURL.appendingPathComponent("Shadow", isDirectory: true)
        try FileManager.default.createDirectory(at: productionRootURL, withIntermediateDirectories: true)
        let receiveJSONURL = productionRootURL.appendingPathComponent("receive.json")
        try Data("receive-before".utf8).write(to: receiveJSONURL)

        let result = MacCanonicalRealDataShadowCopyAdapter().copy(
            MacCanonicalRealDataShadowCopyAdapter.Input(
                productionRootURL: productionRootURL,
                shadowRootURL: shadowRootURL,
                cleanupRootID: "mac-root-01",
                receiveRecords: [Self.receiveRecord()],
                inboxItems: [Self.inboxItem()],
                policy: .enabled(cleanupPolicy: .cleanupImmediately)
            )
        )

        #expect(result.completed)
        #expect(result.failure == nil)
        #expect(result.copiedEntryCount == 3)
        #expect(result.descriptorOnlyAudioCount == 2)
        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent("receive/recording-01.json").path))
        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent("audio-descriptors/recording-01.json").path))
        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent("audio-descriptors/inbox-01.json").path))
        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent("audio/recording-01.m4a").path) == false)
        #expect((try? Data(contentsOf: receiveJSONURL)) == Data("receive-before".utf8))
        #expect(result.diagnosticsSummary.contains(shadowRootURL.path) == false)
        #expect(result.diagnosticsSummary.contains(productionRootURL.path) == false)
    }

    @Test func generatedArtifactCopyIsBoundedAndRequiresProductionRootForFileSources() throws {
        let rootURL = Self.makeScratchRoot("MacRealDataShadowCopyArtifacts")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let productionRootURL = rootURL.appendingPathComponent("Production", isDirectory: true)
        let shadowRootURL = rootURL.appendingPathComponent("Shadow", isDirectory: true)
        try FileManager.default.createDirectory(at: productionRootURL.appendingPathComponent("notes", isDirectory: true), withIntermediateDirectories: true)
        let noteURL = productionRootURL.appendingPathComponent("notes/note-01.md")
        try Data("note".utf8).write(to: noteURL)

        let copied = MacCanonicalRealDataShadowCopyAdapter().copy(
            MacCanonicalRealDataShadowCopyAdapter.Input(
                productionRootURL: productionRootURL,
                shadowRootURL: shadowRootURL,
                cleanupRootID: "mac-root-artifact",
                generatedArtifacts: [
                    MacCanonicalRealDataShadowCopyAdapter.GeneratedArtifactFact(
                        artifactID: "note-01",
                        logicalPathToken: "notes/note-01.md",
                        logicalName: "note.md",
                        sourceURL: noteURL,
                        byteSize: 4
                    )
                ],
                policy: CanonicalRealDataShadowCopyPolicy(
                    isEnabled: true,
                    maxGeneratedArtifactBytes: 16
                )
            )
        )
        #expect(copied.completed)
        #expect(FileManager.default.fileExists(atPath: shadowRootURL.appendingPathComponent("generated/note-01.json").path))

        let oversized = MacCanonicalRealDataShadowCopyAdapter().copy(
            MacCanonicalRealDataShadowCopyAdapter.Input(
                productionRootURL: productionRootURL,
                shadowRootURL: shadowRootURL.appendingPathComponent("Oversized", isDirectory: true),
                cleanupRootID: "mac-root-oversized",
                generatedArtifacts: [
                    MacCanonicalRealDataShadowCopyAdapter.GeneratedArtifactFact(
                        artifactID: "note-02",
                        logicalPathToken: "notes/note-02.md",
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
        #expect(oversized.failure == .sourceTooLarge)
    }

    @Test func runnerRejectsUnsafeRootsAndLifecycleDoesNotRemoveProductionRoot() throws {
        let rootURL = Self.makeScratchRoot("MacRealDataShadowCopyGuards")
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let productionRootURL = rootURL.appendingPathComponent("Production", isDirectory: true)
        try FileManager.default.createDirectory(at: productionRootURL, withIntermediateDirectories: true)

        let insideProduction = CanonicalRealDataShadowCopyRunner().run(
            plan: CanonicalRealDataShadowCopyPlan(
                sources: [
                    .inline(
                        sourceID: "receive-01",
                        kind: .receiveRecord,
                        logicalName: "receive.json",
                        targetLogicalPathToken: "receive/recording.json",
                        bytes: Data("receive".utf8)
                    )
                ],
                target: CanonicalRealDataShadowCopyTarget(
                    rootToken: CanonicalRootToken("shadow-root"),
                    rootURL: productionRootURL.appendingPathComponent("Shadow", isDirectory: true),
                    prohibitedProductionRootURL: productionRootURL
                ),
                policy: .enabled()
            )
        )
        #expect(insideProduction.failure == .targetInsideProductionRoot)

        let refused = CanonicalShadowRootLifecycle(
            rootID: "production",
            rootKind: .productionRootRejected,
            rootURL: productionRootURL,
            productionRootURL: productionRootURL
        ).cleanup(policy: .cleanupImmediately)
        #expect(refused.status == .refusedProductionRoot)
        #expect(FileManager.default.fileExists(atPath: productionRootURL.path))
    }

    private static func receiveRecord() -> RecordingReceiveRecord {
        RecordingReceiveRecord(
            recordingID: "recording-01",
            sanitizedRecordingID: "recording-01",
            receivedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_060),
            sourceDeviceID: "iphone-01",
            sourceDeviceName: "iPhone",
            originalTitle: "Lecture",
            normalizedTitle: "Lecture",
            audioFileName: "recording-01.m4a",
            originalAudioFileName: "recording-01.m4a",
            metadataFileName: "metadata.json",
            status: "completed",
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            processingStatus: "pending",
            suggestedCategory: nil,
            course: nil,
            category: nil,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1_000),
            duration: 60,
            fileSize: 1_024,
            suggestedFolder: nil,
            userConfirmedFolder: nil,
            checksum: String(repeating: "a", count: 64),
            audioRelativePath: "audio/recording-01.m4a",
            metadataRelativePath: "metadata/recording-01.json"
        )
    }

    private static func inboxItem() -> MacRecordingInboxItem {
        MacRecordingInboxItem(
            id: "inbox-01",
            title: "Inbox Lecture",
            receivedAt: Date(timeIntervalSince1970: 1_100),
            duration: 30,
            fileSize: 512,
            sourceDeviceID: "iphone-01",
            sourceDeviceName: "iPhone",
            audioChecksum: String(repeating: "b", count: 64),
            transcriptionStatus: "notStarted",
            noteStatus: "notStarted",
            receiveStatus: "completed",
            hasAudio: true,
            audioRelativePath: "audio/inbox-01.m4a",
            receiveRelativePath: "receive/inbox-01.json",
            transcriptRelativePath: nil,
            transcriptMarkdownRelativePath: nil,
            transcriptionError: nil
        )
    }

    private static func makeScratchRoot(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(name, isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
