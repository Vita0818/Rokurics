import Foundation
import Testing
@testable import RokuricsMac

@MainActor
struct KuzioAudioHandoffWriterTests {
    @Test func hiddenTemporaryIsCompleteBeforeAtomicReadyPublishAndSourceIsPreserved() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = scratch.appendingPathComponent("handoff-root", isDirectory: true)
        let sourceURL = scratch.appendingPathComponent("source.m4a", isDirectory: false)
        let sourceBytes = Data((0..<(2 * 1_024 * 1_024 + 137)).map { UInt8($0 % 251) })
        try sourceBytes.write(to: sourceURL, options: .atomic)

        let requestID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
        let observation = PublicationObservation()
        let writer = KuzioAudioHandoffWriter(
            rootURL: root,
            publicationObserver: { temporaryURL, readyURL in
                #expect(temporaryURL.lastPathComponent.hasPrefix("."))
                #expect(!FileManager.default.fileExists(atPath: readyURL.path))
                let temporaryBytes = try Data(contentsOf: temporaryURL)
                #expect(temporaryBytes == sourceBytes)
                observation.record()
            }
        )

        let receipt = try await writer.handoffAudio(
            at: sourceURL,
            displayFileName: "Lecture.m4a",
            requestID: requestID
        )

        let incomingURL = root.appendingPathComponent("Incoming", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: incomingURL.path)
        let readyName = "44444444-4444-4444-8444-444444444444--Lecture.m4a"
        let readyURL = incomingURL.appendingPathComponent(readyName, isDirectory: false)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: readyURL.path)
        let permissions = try #require(fileAttributes[.posixPermissions] as? NSNumber)

        #expect(receipt.requestID == requestID)
        #expect(receipt.displayFileName == "Lecture.m4a")
        #expect(observation.count == 1)
        #expect(names == [readyName])
        #expect(try Data(contentsOf: readyURL) == sourceBytes)
        #expect(try Data(contentsOf: sourceURL) == sourceBytes)
        #expect(permissions.intValue & 0o777 == 0o600)
    }

    @Test func invalidDisplayNamesFailBeforeWritingQueueFiles() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = scratch.appendingPathComponent("handoff-root", isDirectory: true)
        let sourceURL = scratch.appendingPathComponent("source.m4a", isDirectory: false)
        try Data("audio".utf8).write(to: sourceURL)
        let writer = KuzioAudioHandoffWriter(rootURL: root)

        for invalidName in ["", "../Lecture.m4a", "Folder/Lecture.m4a", "Folder\\Lecture.m4a", "bad\u{0001}.m4a"] {
            do {
                _ = try await writer.handoffAudio(
                    at: sourceURL,
                    displayFileName: invalidName
                )
                Issue.record("Expected invalid display file name rejection")
            } catch let error as KuzioAudioHandoffError {
                #expect(error == .invalidDisplayFileName)
            }
        }

        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(try Data(contentsOf: sourceURL) == Data("audio".utf8))
    }

    @Test func unavailableAppGroupFailsWithoutChangingSourceAudio() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let sourceURL = scratch.appendingPathComponent("source.m4a", isDirectory: false)
        let sourceBytes = Data("unchanged-audio".utf8)
        try sourceBytes.write(to: sourceURL)
        let writer = KuzioAudioHandoffWriter(rootURLResolver: { nil })

        do {
            _ = try await writer.handoffAudio(
                at: sourceURL,
                displayFileName: "Lecture.m4a"
            )
            Issue.record("Expected unavailable App Group failure")
        } catch let error as KuzioAudioHandoffError {
            #expect(error == .appGroupUnavailable)
        }

        #expect(try Data(contentsOf: sourceURL) == sourceBytes)
    }

    @Test func nonAudioDisplayNameFailsWithoutCreatingTheQueue() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = scratch.appendingPathComponent("handoff-root", isDirectory: true)
        let sourceURL = scratch.appendingPathComponent("source.m4a", isDirectory: false)
        try Data("audio".utf8).write(to: sourceURL)
        let writer = KuzioAudioHandoffWriter(rootURL: root)

        do {
            _ = try await writer.handoffAudio(
                at: sourceURL,
                displayFileName: "Lecture.txt"
            )
            Issue.record("Expected unsupported audio file rejection")
        } catch let error as KuzioAudioHandoffError {
            #expect(error == .unsupportedAudioFile)
        }

        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func existingReadyFileIsNeverOverwritten() async throws {
        let scratch = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = scratch.appendingPathComponent("handoff-root", isDirectory: true)
        let incomingURL = root.appendingPathComponent("Incoming", isDirectory: true)
        try FileManager.default.createDirectory(
            at: incomingURL,
            withIntermediateDirectories: true
        )

        let sourceURL = scratch.appendingPathComponent("source.m4a", isDirectory: false)
        let sourceBytes = Data("new-audio".utf8)
        try sourceBytes.write(to: sourceURL)
        let requestID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let readyName = "55555555-5555-4555-8555-555555555555--Lecture.m4a"
        let readyURL = incomingURL.appendingPathComponent(readyName, isDirectory: false)
        let existingBytes = Data("existing-audio".utf8)
        try existingBytes.write(to: readyURL)
        let writer = KuzioAudioHandoffWriter(rootURL: root)

        do {
            _ = try await writer.handoffAudio(
                at: sourceURL,
                displayFileName: "Lecture.m4a",
                requestID: requestID
            )
            Issue.record("Expected existing destination rejection")
        } catch let error as KuzioAudioHandoffError {
            #expect(error == .destinationConflict)
        }

        let names = try FileManager.default.contentsOfDirectory(atPath: incomingURL.path)
        let readyBytes = try Data(contentsOf: readyURL)
        let preservedSourceBytes = try Data(contentsOf: sourceURL)
        #expect(names == [readyName])
        #expect(readyBytes == existingBytes)
        #expect(preservedSourceBytes == sourceBytes)
    }

    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "rokurics-kuzio-handoff-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class PublicationObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.withLock { storedCount }
    }

    func record() {
        lock.withLock {
            storedCount += 1
        }
    }
}
