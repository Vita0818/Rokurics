//
//  CanonicalRecordingMetadataRealApplyPortTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/4.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalRecordingMetadataRealApplyPortTests {
    @Test func rootBoundTargetRejectsUnsafeLogicalPaths() throws {
        let token = CanonicalRootToken("mac-test-root")

        #expect(throws: CanonicalRootBoundMetadataWriteFailure.rootEscape) {
            _ = try CanonicalRootBoundMetadataTarget(rootToken: token, objectID: "recording-01", logicalPathToken: "/tmp/metadata.json")
        }
        #expect(throws: CanonicalRootBoundMetadataWriteFailure.rootEscape) {
            _ = try CanonicalRootBoundMetadataTarget(rootToken: token, objectID: "recording-01", logicalPathToken: "recordings/../metadata.json")
        }
        #expect(throws: CanonicalRootBoundMetadataWriteFailure.rootEscape) {
            _ = try CanonicalRootBoundMetadataTarget(rootToken: token, objectID: "recording-01", logicalPathToken: "file:///tmp/metadata.json")
        }
    }

    @Test func failureClassificationCoversRootBoundContract() {
        let failures = Set(CanonicalRootBoundMetadataWriteFailure.allCases)

        #expect(failures.contains(.rootEscape))
        #expect(failures.contains(.productionRootDisabled))
        #expect(failures.contains(.checkpointFailed))
        #expect(failures.contains(.atomicWriteFailed))
        #expect(failures.contains(.postconditionFailed))
        #expect(failures.contains(.rollbackFailed))
        #expect(failures.contains(.unsupportedStoreAPI))
        #expect(failures.contains(.schemaMismatch))
        #expect(failures.contains(.decodingFailed))
        #expect(failures.contains(.permissionDenied))
        #expect(failures.contains(.unknown))
    }

    @Test func defaultApplyPortIsDisabledAndProductionRootRequiresExplicitGuard() async throws {
        let disabled = MacRecordingMetadataRealApplyPort()
        #expect(disabled.isDryRunOnly)
        #expect(disabled.applyPortMode == .disabled)

        let root = try makeTempRoot("mac-production-disabled")
        defer { try? FileManager.default.removeItem(at: root) }
        let port = try MacRecordingMetadataRealApplyPort(productionRootURL: root)
        let candidate = RecordingMetadataCutoverTestSupport.candidate()
        try await configure(port: port, candidate: candidate, payload: metadataPayload("production blocked"), actionKind: .apply)

        do {
            _ = try await port.applyMetadata(CanonicalProductionApplyExecutionRequest(action: candidate.action, rollbackCheckpointID: candidate.effectiveRollbackCheckpointID))
            Issue.record("production root write should be disabled by default")
        } catch let failure as CanonicalRootBoundMetadataWriteFailure {
            #expect(failure == .productionRootDisabled)
        } catch {
            Issue.record("unexpected failure: \(error)")
        }
    }

    @Test func testRootWritesMetadataAtomicallyAndRedactsTrace() async throws {
        let root = try makeTempRoot("mac-real-apply")
        defer { try? FileManager.default.removeItem(at: root) }
        let port = try MacRecordingMetadataRealApplyPort(testRootURL: root)
        let candidate = RecordingMetadataCutoverTestSupport.candidate()
        let bytes = metadataPayload("new metadata")
        try await configure(port: port, candidate: candidate, payload: bytes, actionKind: .apply)

        let result = try await port.applyMetadata(CanonicalProductionApplyExecutionRequest(action: candidate.action, rollbackCheckpointID: candidate.effectiveRollbackCheckpointID))
        let write = try #require(await port.rootBoundWriteResult(for: candidate.action.actionID))
        let encoded = String(data: try JSONEncoder().encode(write), encoding: .utf8) ?? ""

        #expect(result.status == .applied)
        #expect(result.sideEffect?.kind == .metadataApply)
        #expect(result.sideEffect?.domain == .recordingMetadata)
        #expect(write.atomicWriteUsed)
        #expect(write.rollbackAvailable)
        #expect(write.byteCount == Int64(bytes.count))
        #expect(try await port.rootBoundMetadataBytes(objectID: candidate.objectID) == bytes)
        #expect(!encoded.contains(root.path))
        #expect(!encoded.contains(candidate.stableMetadataHash?.value ?? ""))
        #expect(!encoded.contains("new metadata"))
    }

    @Test func rollbackRestoresPreviousMetadata() async throws {
        let root = try makeTempRoot("mac-real-rollback")
        defer { try? FileManager.default.removeItem(at: root) }
        let port = try MacRecordingMetadataRealApplyPort(testRootURL: root)
        let candidate = RecordingMetadataCutoverTestSupport.candidate()
        let oldBytes = metadataPayload("old metadata")
        let newBytes = metadataPayload("new metadata")
        try writeInitialBytes(oldBytes, objectID: candidate.objectID, root: root)
        try await configure(port: port, candidate: candidate, payload: newBytes, actionKind: .apply)

        _ = try await port.applyMetadata(CanonicalProductionApplyExecutionRequest(action: candidate.action, rollbackCheckpointID: candidate.effectiveRollbackCheckpointID))
        let rollback = try await port.rollbackApply(
            CanonicalRollbackAction(
                actionID: "mac-real-rollback",
                kind: .metadataRollback,
                domain: .recordingMetadata,
                checkpointID: candidate.effectiveRollbackCheckpointID,
                objectID: candidate.objectID
            )
        )
        let rootRollback = try #require(await port.rootBoundRollbackResult(for: candidate.effectiveRollbackCheckpointID))

        #expect(rollback.succeeded)
        #expect(rootRollback.rollbackVerified)
        #expect(try await port.rootBoundMetadataBytes(objectID: candidate.objectID) == oldBytes)
    }

    @Test func postconditionMismatchTriggersRollbackThroughExecutor() async throws {
        let root = try makeTempRoot("mac-real-postcondition")
        defer { try? FileManager.default.removeItem(at: root) }
        let port = try MacRecordingMetadataRealApplyPort(testRootURL: root)
        let candidate = RecordingMetadataCutoverTestSupport.candidate()
        let oldBytes = metadataPayload("old metadata")
        try writeInitialBytes(oldBytes, objectID: candidate.objectID, root: root)
        try await configure(port: port, candidate: candidate, payload: metadataPayload("new metadata"), actionKind: .apply)
        await port.injectRootBoundPostconditionFailure(objectID: candidate.objectID)

        let result = await CanonicalRecordingMetadataCutoverRunner().run(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            token: RecordingMetadataCutoverTestSupport.token(),
            evidence: RecordingMetadataCutoverTestSupport.evidence(),
            candidates: [candidate],
            trigger: .periodic,
            nodeRole: .testHarness,
            executor: MacRecordingMetadataCutoverExecutor(applyPort: port)
        )

        #expect(result.commits.first?.failureKind == .postconditionMismatch)
        #expect(result.rollbackResults.first?.succeeded == true)
        #expect(result.duplicateLegacySuppressedActionIDs.isEmpty)
        #expect(try await port.rootBoundMetadataBytes(objectID: candidate.objectID) == oldBytes)
    }

    @Test func checkpointFailureBlocksWriteAndRootEscapeIsRejected() async throws {
        let root = try makeTempRoot("mac-real-failures")
        defer { try? FileManager.default.removeItem(at: root) }
        let port = try MacRecordingMetadataRealApplyPort(testRootURL: root)
        let candidate = RecordingMetadataCutoverTestSupport.candidate()
        try await configure(port: port, candidate: candidate, payload: metadataPayload("new metadata"), actionKind: .apply)
        await port.injectRootBoundCheckpointFailure(objectID: candidate.objectID)

        do {
            _ = try await port.applyMetadata(CanonicalProductionApplyExecutionRequest(action: candidate.action, rollbackCheckpointID: candidate.effectiveRollbackCheckpointID))
            Issue.record("checkpoint failure should block write")
        } catch let failure as CanonicalRootBoundMetadataWriteFailure {
            #expect(failure == .checkpointFailed)
        } catch {
            Issue.record("unexpected failure: \(error)")
        }
        #expect(try await port.rootBoundMetadataBytes(objectID: candidate.objectID) == nil)

        do {
            try await port.setRootBoundMetadataPayload(
                objectID: "escape",
                actionKind: .apply,
                metadataBytes: metadataPayload("escape"),
                logicalPathToken: "../escape.json"
            )
            Issue.record("root escape payload should be rejected")
        } catch let failure as CanonicalRootBoundMetadataWriteFailure {
            #expect(failure == .rootEscape)
        } catch {
            Issue.record("unexpected failure: \(error)")
        }
    }

    @Test func realApplyPortDoesNotAlterAudioLedgerOrGeneratedArtifacts() async throws {
        let root = try makeTempRoot("mac-real-boundaries")
        defer { try? FileManager.default.removeItem(at: root) }
        let port = try MacRecordingMetadataRealApplyPort(testRootURL: root)
        let candidate = RecordingMetadataCutoverTestSupport.candidate()
        try await configure(port: port, candidate: candidate, payload: metadataPayload("new metadata"), actionKind: .apply)
        let audioURL = root.appendingPathComponent("Recordings/recording-01.m4a")
        let ledgerURL = root.appendingPathComponent("Sync/upload-ledger.json")
        let generatedURL = root.appendingPathComponent("Generated/transcript.json")
        let standaloneNoteURL = root.appendingPathComponent("StandaloneNotes/note.md")
        let receiveURL = root.appendingPathComponent("Inbox/recording-01/receive.json")
        let audioInboxURL = root.appendingPathComponent("AudioInbox/recording-01.json")
        try FileManager.default.createDirectory(at: audioURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ledgerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: generatedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: standaloneNoteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: receiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audioInboxURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: audioURL)
        try Data("ledger".utf8).write(to: ledgerURL)
        try Data("receive".utf8).write(to: receiveURL)
        try Data("audio-inbox".utf8).write(to: audioInboxURL)

        _ = try await port.applyMetadata(CanonicalProductionApplyExecutionRequest(action: candidate.action, rollbackCheckpointID: candidate.effectiveRollbackCheckpointID))

        #expect(try Data(contentsOf: audioURL) == Data("audio".utf8))
        #expect(try Data(contentsOf: ledgerURL) == Data("ledger".utf8))
        #expect(try Data(contentsOf: receiveURL) == Data("receive".utf8))
        #expect(try Data(contentsOf: audioInboxURL) == Data("audio-inbox".utf8))
        #expect(!FileManager.default.fileExists(atPath: generatedURL.path))
        #expect(!FileManager.default.fileExists(atPath: standaloneNoteURL.path))
    }

    @Test func commitExecutorCanUseTestRootRealApplyPortAndGateEvidenceBlocksDryRunPorts() async throws {
        let root = try makeTempRoot("mac-real-executor")
        defer { try? FileManager.default.removeItem(at: root) }
        let port = try MacRecordingMetadataRealApplyPort(testRootURL: root)
        let candidate = RecordingMetadataCutoverTestSupport.candidate(title: "Prepared Peer")

        let commit = await MacRecordingMetadataCutoverExecutor(applyPort: port).commitRecordingMetadata(candidate)
        let written = try #require(try await port.rootBoundMetadataBytes(objectID: candidate.objectID))
        let json = try #require(JSONSerialization.jsonObject(with: written) as? [String: Any])
        var dryRunEvidence = RecordingMetadataCutoverTestSupport.evidence()
        dryRunEvidence.realRootBoundApplyPortAvailable = false
        dryRunEvidence.applyPortMode = .dryRun
        dryRunEvidence.rootBoundWriteAvailable = false
        dryRunEvidence.atomicReplaceAvailable = false
        dryRunEvidence.rollbackCheckpointAvailable = false
        dryRunEvidence.rollbackVerified = false
        let gate = CanonicalRecordingMetadataCutoverRunner().evaluateGate(
            configuration: .canary(maxObjects: 1, allowsV87CanaryN1InternalExecution: true),
            token: RecordingMetadataCutoverTestSupport.token(),
            evidence: dryRunEvidence,
            candidates: [candidate],
            trigger: .periodic
        )

        #expect(commit.committed)
        #expect(json["title"] as? String == "Prepared Peer")
        #expect(json["name"] as? String == "Prepared Peer")
        #expect(json["schemaVersion"] as? String == CanonicalRecordingMetadata.businessMetadataHashSchemaVersion)
        #expect(json["metadataHash"] as? String == candidate.stableMetadataHash?.value)
        #expect(commit.sideEffects.map(\.redactedSummary).joined().contains(candidate.stableMetadataHash?.value ?? "") == false)
        #expect(gate.failures.contains(.applyPortDryRunOnly))
        #expect(gate.failures.contains(.rootBoundWriteUnavailable))
        #expect(gate.failures.contains(.atomicReplaceUnavailable))
        #expect(gate.failures.contains(.rollbackCheckpointUnavailable))
        #expect(gate.failures.contains(.rollbackVerificationMissing))
    }

    @Test func defaultPortSetDoesNotUseRealApplyPort() throws {
        let ports = MacCanonicalProductionPorts.makeDisabledPortSet()
        let apply = try #require(ports.apply as? MacCanonicalProductionApplyPort)

        #expect(ports.readiness().dryRunOnly)
        #expect(apply.applyPortMode == .disabled)
        #expect(apply.isDryRunOnly)
    }

    private func configure(
        port: MacRecordingMetadataRealApplyPort,
        candidate: CanonicalRecordingMetadataCutoverCandidate,
        payload: Data,
        actionKind: CanonicalRecordingMetadataCutoverActionKind
    ) async throws {
        try await port.setRootBoundMetadataPayload(
            objectID: candidate.objectID,
            actionKind: actionKind,
            metadataBytes: payload,
            metadataHash: candidate.stableMetadataHash,
            tombstone: candidate.expectedObject?.metadata.isDeleted ?? false,
            modifiedAt: candidate.expectedObject?.metadata.modifiedAt,
            actionID: candidate.action.actionID
        )
    }

    private func metadataPayload(_ title: String) -> Data {
        Data("{\"kind\":\"recordingMetadata\",\"title\":\"\(title)\"}".utf8)
    }

    private func writeInitialBytes(_ bytes: Data, objectID: String, root: URL) throws {
        let path = CanonicalRootBoundMetadataTarget.defaultLogicalPathToken(objectID: objectID)
        let url = root.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }

    private func makeTempRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rokurics-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
