//
//  CanonicalProductionPortContractTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalProductionPortContractTests {
    @Test func filePortContractExposesRealReadWriteHashAndRollbackMethods() async throws {
        let file = CanonicalTestProductionFilePort()
        let intent = CanonicalKernelFacadeTestSupport.fileIntent()

        let write = try await file.writeMetadata(intent, rollbackCheckpoint: CanonicalRollbackCheckpoint(checkpointID: "checkpoint-file", domain: .fileRuntime))
        let read = try await file.readMetadata(CanonicalProductionMetadataReadRequest(objectID: "recording-01", reference: intent.reference))
        let hash = try await file.computeHash(CanonicalProductionHashRequest(reference: intent.reference, requireStreaming: true, expectedByteSize: Int64(intent.bytes.count)))
        let rollback = try await file.rollbackWrite(CanonicalProductionFileRollbackRequest(checkpointID: "checkpoint-file", reference: intent.reference))

        #expect(write.evidence.hashVerified)
        #expect(read.bytes == intent.bytes)
        #expect(hash.computedStreaming)
        #expect(rollback.succeeded)
    }

    @Test func transportPortContractExposesRealSignedSendAndVerifyMethods() async throws {
        let transport = CanonicalTestProductionTransportPort()
        let build = CanonicalProductionTransportBuildRequest(
            source: CanonicalProductionTestFixtures.node("iphone-01", platform: "iPhone"),
            destination: CanonicalProductionTestFixtures.node(),
            route: .manifestExchange,
            existingRoutePath: "/sync/inventory",
            body: Data("{}".utf8),
            nonce: "nonce-01"
        )
        let signed = try await transport.buildSignedRequest(build)
        let exchange = try await transport.sendRequest(signed)
        let verification = try await transport.verifyResponse(exchange)

        #expect(signed.bodyHash == CanonicalTransportEnvelope.hash(build.body))
        #expect(exchange.sideEffect?.kind == .networkRequest)
        #expect(verification.responseHashVerified)
    }

    @Test func uploadPortContractExposesSessionChunkFinalizeAndLedgerMethods() async throws {
        let upload = CanonicalTestProductionUploadPort()
        let bytes = Data("abcd".utf8)
        let hash = CanonicalHash.sha256String("abcd")
        let request = CanonicalUploadStartRequest(
            objectID: "recording-01",
            targetReference: CanonicalFileReference(rootToken: CanonicalRootToken("test-root"), logicalPathToken: "audio/recording-01.m4a"),
            totalBytes: Int64(bytes.count),
            totalHash: hash,
            chunkSize: 4
        )
        let start = try await upload.startResumableUpload(request, now: Date())
        let sessionID = try #require(start.sessionID)
        let chunk = CanonicalUploadChunk(objectID: "recording-01", sessionID: sessionID, offset: 0, bytes: bytes, chunkHash: hash, totalHash: hash)
        let chunked = try await upload.uploadChunk(chunk, now: Date())
        let finalized = try await upload.finalizeUpload(CanonicalUploadFinalizeRequest(objectID: "recording-01", sessionID: sessionID, totalBytes: Int64(bytes.count), totalHash: hash), now: Date())
        let ledger = try await upload.writeUploadLedger(CanonicalProductionUploadLedgerSnapshot(objectID: "recording-01", sessionID: sessionID, confirmedBytes: finalized.confirmedBytes, totalBytes: finalized.fileSize, contentHash: finalized.checksum, phase: finalized.phase))

        #expect(chunked.confirmedBytes == Int64(bytes.count))
        #expect(finalized.completed)
        #expect(ledger.phase == .completed)
    }

    @Test func applyPortContractExposesApplyRequestConflictAndRollbackMethods() async throws {
        let apply = CanonicalTestProductionApplyPort()
        let action = CanonicalApplyAction(kind: .recordingMetadataApply, source: .peer, target: CanonicalApplyTarget(objectID: "recording-01"), reason: "peerMetadataNewer")
        let applied = try await apply.applyMetadata(CanonicalProductionApplyExecutionRequest(action: action, rollbackCheckpointID: "checkpoint-apply"))
        let conflict = try await apply.recordConflict(CanonicalProductionApplyExecutionRequest(action: action, rollbackCheckpointID: nil))
        let rollback = try await apply.rollbackApply(CanonicalRollbackAction(actionID: "rollback-apply", kind: .metadataRollback, domain: .apply, checkpointID: "checkpoint-apply"))

        #expect(applied.sideEffect?.kind == .metadataApply)
        #expect(conflict.status == .conflictRecorded)
        #expect(rollback.succeeded == false)
    }

    @Test func existingDryRunPortsStillCompileAndRemainSuppressed() async throws {
        let ports = MacCanonicalDryRunPorts.makePortSet()
        let trace = try await ports.upload?.projectUploadDryRun(
            object: CanonicalProductionTestFixtures.recording(audio: true),
            artifact: CanonicalProductionTestFixtures.audioArtifact()
        )

        #expect(ports.readiness().dryRunOnly)
        #expect(trace?.suppressedBecauseDryRun == true)
    }
}
