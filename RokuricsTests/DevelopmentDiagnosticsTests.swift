import Foundation
import Testing
@testable import Rokurics

struct DevelopmentDiagnosticsTests {
    @Test func debugRequestHeaderCarriesCurrentDevelopmentSession() {
        DevelopmentDiagnostics.configureSessionForTests("test-header-propagation")
        #expect(
            DevelopmentDiagnostics.requestHeaderFields()[DevelopmentDiagnostics.sessionHeaderName]
                == "test-header-propagation"
        )
    }

    @Test func sessionStoreWritesValidJSONLAndWriterHealth() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-development-diagnostics-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionID = "test-ios-diagnostics"
        let store = DevelopmentDiagnosticsFileStore(rootURL: root, sessionID: sessionID, node: .iPhone)

        store.enqueue(DevelopmentDiagnosticEvent(
            timestamp: Date(timeIntervalSince1970: 100),
            sessionID: sessionID,
            node: .iPhone,
            subsystem: "connectionSync",
            event: "heartbeatSucceeded",
            severity: .info,
            syncRunID: "sync-run-1",
            traceID: nil,
            details: ["latencyMs": "12.5"]
        ))
        store.flush()

        let sessionRoot = root.appendingPathComponent("DevelopmentSessions/\(sessionID)", isDirectory: true)
        let logURL = sessionRoot.appendingPathComponent("iphone-events.jsonl")
        let healthURL = sessionRoot.appendingPathComponent("iphone-writer-health.json")
        let lines = try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 1)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(DevelopmentDiagnosticEvent.self, from: Data(lines[0].utf8))
        #expect(event.sessionID == sessionID)
        #expect(event.syncRunID == "sync-run-1")
        let health = try decoder.decode(DevelopmentDiagnosticsWriterHealth.self, from: Data(contentsOf: healthURL))
        #expect(health.writtenCount == 1)
        #expect(health.droppedCount == 0)
        #expect(health.writeFailureCount == 0)
    }

    @Test func sessionStoreRejectsPrivatePathsBeforeWriting() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rokurics-development-redaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionID = "test-ios-redaction"
        let store = DevelopmentDiagnosticsFileStore(rootURL: root, sessionID: sessionID, node: .iPhone)

        store.enqueue(DevelopmentDiagnosticEvent(
            timestamp: Date(),
            sessionID: sessionID,
            node: .iPhone,
            subsystem: "file",
            event: "unsafe",
            severity: .error,
            syncRunID: nil,
            traceID: nil,
            details: ["path": "/Users/private/audio.m4a"]
        ))
        store.flush()

        #expect(store.healthSnapshot().redactionRejectedCount == 1)
        #expect(store.healthSnapshot().writtenCount == 0)
    }
}
