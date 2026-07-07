//
//  CanonicalAudioUploadReceiveTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalAudioUploadReceiveTests {
    @MainActor
    @Test func macCutoverExecutorExistsAndRequiresFinalizeProofBeforeAudioAvailable() async {
        let bytes = Data("v859-mac-proof-required".utf8)
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let candidate = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "v859-mac-proof-required",
            localTruth: .available(hash: hash, byteSize: Int64(bytes.count), logicalPathToken: "audio/v859-mac-proof-required.m4a"),
            peerTruth: CanonicalAudioUploadPeerTruth(state: .metadataOnly),
            trigger: .ordinarySync
        )
        let executor: any CanonicalAudioUploadCutoverExecutor = MacAudioUploadCutoverExecutor()
        let missingProof = await executor.execute(
            CanonicalAudioUploadCutoverExecutionRequest(
                candidate: candidate,
                configuration: .testTransportUpload(chunkSize: 6),
                nodeRole: .mac
            )
        )
        let proof = CanonicalAudioUploadFinalizeProof(
            objectID: candidate.objectID,
            sessionID: CanonicalUploadSessionID("v859-mac-proof-required-session"),
            byteSize: Int64(bytes.count),
            contentHash: hash,
            macFileSizeVerified: true,
            macHashVerified: true,
            macProofReceived: true,
            receiveRecordMatchesAudioAvailability: true
        )
        let finalized = await executor.execute(
            CanonicalAudioUploadCutoverExecutionRequest(
                candidate: candidate,
                configuration: .testTransportUpload(chunkSize: 6),
                nodeRole: .mac,
                serverFinalizeProof: proof
            )
        )

        #expect(missingProof.failure?.kind == .finalizeProofMissing)
        #expect(missingProof.postcondition.accepted == false)
        #expect(finalized.outcome == .uploaded)
        #expect(finalized.postcondition.finalizeProofAccepted)
        #expect(finalized.postcondition.macFileSizeVerified)
        #expect(finalized.postcondition.macHashVerified)
    }

    @MainActor
    @Test func macCutoverExecutorKeepsPartialReceiveAndDifferentAudioSafe() async {
        let bytes = Data("v859-mac-partial-conflict".utf8)
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let partial = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "v859-mac-partial",
            localTruth: .available(hash: hash, byteSize: Int64(bytes.count), logicalPathToken: "audio/v859-mac-partial.m4a"),
            peerTruth: CanonicalAudioUploadPeerTruth(
                state: .metadataOnly,
                receiveRecordExists: true,
                metadataUploaded: true
            ),
            trigger: .ordinarySync
        )
        let different = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "v859-mac-different",
            localTruth: .available(hash: hash, byteSize: Int64(bytes.count), logicalPathToken: "audio/v859-mac-different.m4a"),
            peerTruth: CanonicalAudioUploadPeerTruth(
                state: .different,
                contentHash: CanonicalHash.sha256String("v859-mac-different-hash"),
                byteSize: Int64(bytes.count + 1)
            ),
            trigger: .ordinarySync
        )
        let executor: any CanonicalAudioUploadCutoverExecutor = MacAudioUploadCutoverExecutor()
        let partialResult = await executor.execute(
            CanonicalAudioUploadCutoverExecutionRequest(
                candidate: partial,
                configuration: .testTransportUpload(chunkSize: 6),
                nodeRole: .mac
            )
        )
        let differentResult = await executor.execute(
            CanonicalAudioUploadCutoverExecutionRequest(
                candidate: different,
                configuration: .testTransportUpload(chunkSize: 6),
                nodeRole: .mac
            )
        )

        #expect(partialResult.outcome == .blocked)
        #expect(partialResult.postcondition.partialReceiveNotAudioAvailable)
        #expect(differentResult.outcome == .conflict)
        #expect(differentResult.postcondition.existingDifferentAudioNotOverwritten)
    }

    @Test func secureReceiveFinalizeVerifiesHashSizeAndMarksAudioAvailableOnlyAfterProof() throws {
        let store = try sourceText("RokuricsMac/MacRecordingFileStore.swift")

        #expect(store.contains("func finalizeResumableAudioUpload"))
        #expect(store.contains("session.receivedBytes == request.totalBytes"))
        #expect(store.contains("fileSize(at: partURL) == request.totalBytes"))
        #expect(store.contains("canonicalAudioChecksum("))
        #expect(store.contains("fileURL: partURL"))
        #expect(store.contains("constantTimeEquals(checksum, request.totalSHA256)"))
        #expect(store.contains("moveItem(at: partURL, to: recordingResources.audioURL)"))
        #expect(store.contains("record.audioRelativePath = try relativePath(for: recordingResources.audioURL)"))
        #expect(store.contains("record.status = \"completed\""))
        #expect(store.contains("receiveRecordAudioAvailable"))
    }

    @Test func existingDifferentAudioConflictsAndIsNotOverwritten() throws {
        let store = try sourceText("RokuricsMac/MacRecordingFileStore.swift")

        #expect(store.contains("handleExistingAudioUpload"))
        #expect(store.contains("existingFileSize == incomingFileSize"))
        #expect(store.contains("constantTimeEquals(existingChecksum, incomingChecksum)"))
        #expect(store.contains("macRejectExistingAudioDifferentChecksum"))
        #expect(store.contains("audioConflictDetected"))
        #expect(store.contains("throw MacRecordingFileStoreError.audioConflict"))
        #expect(store.contains("moveItem(at: partURL, to: recordingResources.audioURL)"))
    }

    @Test func resumableRoutesStillUseRequestVerifierAndNoNewUploadRouteWasAdded() throws {
        let server = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")
        let verifier = try sourceText("RokuricsMac/RequestVerifier.swift")
        let executor = try sourceText("RokuricsMac/MacAudioUploadCutoverExecutor.swift")

        #expect(server.contains("requestVerifier.verify(method: method, path: path, headers: headers, body: body)"))
        #expect(server.contains("resumableAudioStartResponse"))
        #expect(server.contains("resumableAudioStatusResponse"))
        #expect(server.contains("resumableAudioChunkResponse"))
        #expect(server.contains("resumableAudioFinalizeResponse"))
        #expect(verifier.contains("\"/upload-recording-audio-session/start\""))
        #expect(verifier.contains("\"/upload-recording-audio-session/status\""))
        #expect(verifier.contains("\"/upload-recording-audio-session/chunk\""))
        #expect(verifier.contains("\"/upload-recording-audio-session/finalize\""))
        #expect(verifier.contains("\"/upload-recording-audio-session/abort\"") == false)
        #expect(executor.contains("MacAudioUploadCutoverExecutor"))
        #expect(executor.contains("startReceive"))
        #expect(executor.contains("appendReceiveChunk"))
        #expect(executor.contains("finalizeReceive"))
        #expect(executor.contains("\"/upload-recording-audio-session/abort\"") == false)
        #expect(executor.contains("RequestVerifier(") == false)
    }

    @Test func partialSessionsAreNotInventoryAudioProof() throws {
        let store = try sourceText("RokuricsMac/MacRecordingFileStore.swift")
        let server = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")

        #expect(store.contains("finalAudioExists: false"))
        #expect(store.contains("state: .transferring"))
        #expect(store.contains("record.status = \"completed\""))
        #expect(store.contains("record.audioRelativePath = try relativePath(for: recordingResources.audioURL)"))
        #expect(server.contains("if entry.audioAvailability == .missing || (!entry.audioAvailable && entry.audioSize == nil && entry.audioChecksum == nil)"))
        #expect(server.contains("} else if entry.audioAvailable, entry.audioChecksum != nil, entry.audioSize != nil {"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRootURL.appendingPathComponent(relativePath, isDirectory: false)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
