//
//  CanonicalProductionAdapterTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalProductionAdapterTests {
    @Test func disabledAdaptersRemainDryRunAndSuppressRealSideEffects() async throws {
        let ports = MacCanonicalProductionPorts.makeDisabledPortSet()
        let readiness = ports.readiness(generatedAt: CanonicalProductionTestFixtures.date(100))
        let transport = MacCanonicalProductionTransportPort()
        let build = CanonicalProductionTransportBuildRequest(
            source: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"),
            destination: CanonicalProductionTestFixtures.node("mac-01"),
            route: .manifestExchange,
            existingRoutePath: transport.existingRoutePath(for: .manifestExchange),
            body: Data("{}".utf8),
            nonce: "nonce-01"
        )
        let signed = try await transport.buildSignedRequest(build)
        let uploadTrace = try await MacCanonicalProductionUploadPort(chunkSizePolicy: 4 * 1024 * 1024).projectUploadDryRun(
            object: CanonicalProductionTestFixtures.recording(audio: true),
            artifact: CanonicalProductionTestFixtures.audioArtifact()
        )
        let applyTrace = try await MacCanonicalProductionApplyPort().projectApplyDryRun(
            CanonicalApplyAction(
                kind: .recordingMetadataApply,
                source: .peer,
                target: CanonicalApplyTarget(objectID: "recording-01"),
                reason: "peerMetadataNewer"
            )
        )

        #expect(readiness.dryRunOnly)
        #expect(signed.bodyHash == CanonicalTransportEnvelope.hash(build.body))
        #expect(signed.signerDescription?.contains("RequestVerifier") == true)
        #expect(uploadTrace.suppressedBecauseDryRun)
        #expect(applyTrace.wouldCallApplySyncManifest == false)

        do {
            _ = try await transport.sendRequest(signed)
            #expect(Bool(false), "disabled transport must not send")
        } catch let error as CanonicalProductionPortError {
            #expect(error == .networkExecutionSuppressed("macProductionTransportSendSuppressed"))
        }
    }

    @Test func filePortUsesTempRootAndRedactedResolutionTokens() async throws {
        let rootURL = try makeTempRoot("mac-file-port")
        let file = MacCanonicalProductionFilePort(testRootURL: rootURL)
        let reference = CanonicalFileReference(
            rootToken: CanonicalRootToken("mac-test-root"),
            logicalPathToken: "metadata/recording-01.json"
        )
        let oldBytes = Data("old".utf8)
        let newBytes = Data("new".utf8)
        _ = try await file.writeMetadata(
            CanonicalFileWriteIntent(
                reference: reference,
                bytes: oldBytes,
                purpose: .metadataBlob,
                expectedContentHash: InMemoryCanonicalFileStore.hash(oldBytes, policy: .sha256),
                expectedByteSize: Int64(oldBytes.count),
                conflictPolicy: .replace
            ),
            rollbackCheckpoint: nil
        )

        let write = try await file.writeMetadata(
            CanonicalFileWriteIntent(
                reference: reference,
                bytes: newBytes,
                purpose: .metadataBlob,
                expectedContentHash: InMemoryCanonicalFileStore.hash(newBytes, policy: .sha256),
                expectedByteSize: Int64(newBytes.count),
                conflictPolicy: .replace
            ),
            rollbackCheckpoint: CanonicalRollbackCheckpoint(checkpointID: "checkpoint-file", domain: .fileRuntime)
        )
        let read = try await file.readMetadata(CanonicalProductionMetadataReadRequest(objectID: "recording-01", reference: reference))
        let hash = try await file.computeHash(CanonicalProductionHashRequest(reference: reference, expectedByteSize: Int64(newBytes.count)))
        let rollback = try await file.rollbackWrite(CanonicalProductionFileRollbackRequest(checkpointID: "checkpoint-file", reference: reference))
        let rolledBack = try await file.readMetadata(CanonicalProductionMetadataReadRequest(objectID: "recording-01", reference: reference))

        #expect(write.disposition == .replaced)
        #expect(read.bytes == newBytes)
        #expect(hash.contentHash == InMemoryCanonicalFileStore.hash(newBytes, policy: .sha256))
        #expect(rollback.succeeded)
        #expect(rolledBack.bytes == oldBytes)
        #expect(write.evidence.resolution.resolvedPathToken == "mac-test-root/metadata/recording-01.json")
        #expect(!write.evidence.resolution.resolvedPathToken.contains(rootURL.path))
    }

    @Test func fakeTransportUploadAndApplyStayInMemory() async throws {
        let transport = MacCanonicalProductionTransportPort(fakeResponder: { _ in
            CanonicalTransportResponse(ok: true, status: "ok", body: Data("{\"ok\":true}".utf8))
        })
        let build = CanonicalProductionTransportBuildRequest(
            source: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"),
            destination: CanonicalProductionTestFixtures.node("mac-01"),
            route: .uploadStart,
            existingRoutePath: transport.existingRoutePath(for: .uploadStart),
            body: Data("{}".utf8),
            nonce: "nonce-02"
        )
        let exchange = try await transport.sendRequest(try await transport.buildSignedRequest(build))

        let upload = MacCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 8)
        let bytes = Data("abcd".utf8)
        let hash = InMemoryCanonicalFileStore.hash(bytes, policy: .sha256) ?? CanonicalHash.sha256String("")
        let start = try await upload.startResumableUpload(
            CanonicalUploadStartRequest(
                objectID: "recording-01",
                targetReference: CanonicalFileReference(rootToken: CanonicalRootToken("mac-test-root"), logicalPathToken: "audio/recording-01.m4a"),
                totalBytes: Int64(bytes.count),
                totalHash: hash,
                chunkSize: 4
            ),
            now: CanonicalProductionTestFixtures.date(101)
        )
        let sessionID = try #require(start.sessionID)
        let chunked = try await upload.uploadChunk(
            CanonicalUploadChunk(objectID: "recording-01", sessionID: sessionID, offset: 0, bytes: bytes, chunkHash: hash, totalHash: hash),
            now: CanonicalProductionTestFixtures.date(102)
        )
        let finalized = try await upload.finalizeUpload(
            CanonicalUploadFinalizeRequest(objectID: "recording-01", sessionID: sessionID, totalBytes: Int64(bytes.count), totalHash: hash),
            now: CanonicalProductionTestFixtures.date(103)
        )

        let apply = MacCanonicalProductionApplyPort(fakeInMemory: true)
        let action = CanonicalApplyAction(kind: .recordingMetadataApply, source: .peer, target: CanonicalApplyTarget(objectID: "recording-01"), reason: "peerMetadataNewer")
        let applied = try await apply.applyMetadata(CanonicalProductionApplyExecutionRequest(action: action, rollbackCheckpointID: "checkpoint-apply"))

        #expect(exchange.responseVerified)
        #expect(transport.realNetworkExecutionEnabled == false)
        #expect(chunked.confirmedBytes == Int64(bytes.count))
        #expect(finalized.completed)
        #expect(finalized.finalFile?.logicalPathToken == "audio/recording-01.m4a")
        #expect(applied.sideEffect?.kind == .metadataApply)
        #expect(applied.rollbackCheckpointID == "checkpoint-apply")
    }

    private func makeTempRoot(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Rokurics-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
