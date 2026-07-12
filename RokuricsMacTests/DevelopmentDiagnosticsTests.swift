import Foundation
import Testing
@testable import RokuricsMac

struct MacDevelopmentDiagnosticsTests {
    @Test func macAdoptsCaseInsensitiveDevelopmentSessionHeader() {
        DevelopmentDiagnostics.configureSessionForTests("test-mac-before-adopt")
        DevelopmentDiagnostics.adoptSessionID(from: [
            "x-rokurics-development-session-id": "test-shared-session"
        ])
        #expect(DevelopmentDiagnostics.activeSessionID == "test-shared-session")
    }

    @Test func sessionStoreRotatesAndPreservesValidJSONL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-mac-development-diagnostics-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionID = "test-mac-diagnostics"
        var configuration = DevelopmentDiagnosticsFileStore.Configuration()
        configuration.maxLogFileBytes = 350
        configuration.rotatedFileCount = 2
        let store = DevelopmentDiagnosticsFileStore(
            rootURL: root,
            sessionID: sessionID,
            node: .Mac,
            configuration: configuration
        )

        for index in 0..<8 {
            store.enqueue(DevelopmentDiagnosticEvent(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                sessionID: sessionID,
                node: .Mac,
                subsystem: "connectionSync",
                event: "routeObserved",
                severity: .info,
                syncRunID: "sync-\(index)",
                traceID: nil,
                details: ["index": String(index)]
            ))
        }
        store.flush()

        let sessionRoot = root.appendingPathComponent("DevelopmentSessions/\(sessionID)", isDirectory: true)
        let currentURL = sessionRoot.appendingPathComponent("mac-events.jsonl")
        let rotatedURL = URL(fileURLWithPath: currentURL.path + ".1")
        #expect(FileManager.default.fileExists(atPath: currentURL.path))
        #expect(FileManager.default.fileExists(atPath: rotatedURL.path))
        #expect(store.healthSnapshot().writtenCount == 8)
        #expect(store.healthSnapshot().droppedCount == 0)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in [currentURL, rotatedURL] {
            let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
            #expect(!lines.isEmpty)
            for line in lines {
                _ = try decoder.decode(DevelopmentDiagnosticEvent.self, from: Data(line.utf8))
            }
        }
    }

    @Test func sessionStoreBoundsRetainedSessionDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-mac-development-retention-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionsRoot = root.appendingPathComponent("DevelopmentSessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        for index in 0..<4 {
            let oldSession = sessionsRoot.appendingPathComponent("test-old-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: oldSession, withIntermediateDirectories: true)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
                ofItemAtPath: oldSession.path
            )
        }

        var configuration = DevelopmentDiagnosticsFileStore.Configuration()
        configuration.maxRetainedSessions = 3
        configuration.maxSessionAge = .greatestFiniteMagnitude
        let sessionID = "test-current-retention"
        let store = DevelopmentDiagnosticsFileStore(
            rootURL: root,
            sessionID: sessionID,
            node: .Mac,
            configuration: configuration
        )
        store.enqueue(DevelopmentDiagnosticEvent(
            timestamp: Date(),
            sessionID: sessionID,
            node: .Mac,
            subsystem: "retention",
            event: "started",
            severity: .info,
            syncRunID: nil,
            traceID: nil,
            details: [:]
        ))
        store.flush()

        let retained = try FileManager.default.contentsOfDirectory(atPath: sessionsRoot.path)
        #expect(retained.count == 3)
        #expect(retained.contains(sessionID))
        #expect(!retained.contains("test-old-0"))
        #expect(!retained.contains("test-old-1"))
    }
}
