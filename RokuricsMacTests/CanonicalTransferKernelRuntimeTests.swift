//
//  CanonicalTransferKernelRuntimeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalTransferKernelRuntimeTests {
    @Test func macAdapterWrapsExistingReceiveStoreAndDoesNotAddAbortRoute() throws {
        let adapter = try sourceText("RokuricsMac/MacCanonicalTransferReceiveAdapter.swift")
        let executor = try sourceText("RokuricsMac/MacAudioUploadCutoverExecutor.swift")
        let store = try sourceText("RokuricsMac/MacRecordingFileStore.swift")

        #expect(adapter.contains("MacAudioUploadCutoverExecutor"))
        #expect(adapter.contains("startReceive"))
        #expect(adapter.contains("appendReceiveChunk"))
        #expect(adapter.contains("finalizeReceive"))
        #expect(adapter.contains("\"/upload-recording-audio-session/abort\"") == false)
        #expect(executor.contains("MacRecordingFileStore"))
        #expect(store.contains("startResumableAudioUpload"))
        #expect(store.contains("appendResumableAudioChunk"))
        #expect(store.contains("finalizeResumableAudioUpload"))
    }

    @Test func routeListUnchangedAndRequestVerifierRemainsRequired() throws {
        let server = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")
        let verifier = try sourceText("RokuricsMac/RequestVerifier.swift")
        let adapter = try sourceText("RokuricsMac/MacCanonicalTransferReceiveAdapter.swift")

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
        #expect(adapter.contains("RequestVerifier(") == false)
        #expect(server.contains("case (\"POST\", \"/upload-recording-audio-session/start\")"))
        #expect(server.contains("case (\"POST\", \"/upload-recording-audio-session/status\")"))
        #expect(server.contains("case (\"POST\", \"/upload-recording-audio-session/chunk\")"))
        #expect(server.contains("case (\"POST\", \"/upload-recording-audio-session/finalize\")"))
        #expect(server.contains("/upload-recording-audio-session/abort") == false)
    }

    @Test func sharedRuntimeDoesNotTreatPartialReceiveOrCompletedLedgerAsProof() throws {
        let protocolText = try sourceText("RokuricsShared/SyncCore/CanonicalTransferProtocol.swift")
        var partial = CanonicalTransferSessionStateMachine(
            sessionID: CanonicalTransferSessionID("mac-transfer-v930"),
            objectID: CanonicalObjectID("mac-recording-v930"),
            expectedByteSize: 12,
            expectedContentHash: Self.hashA,
            chunkSize: 4
        )
        try partial.markStarted()
        try partial.acceptChunk(offset: 0, length: 4, chunkHash: Self.chunkA)

        #expect(partial.partialReceiveWithoutFinalize)
        #expect(partial.state != .finalized)
        #expect(protocolText.contains("completedLedgerAloneIsPeerProof = false"))
        #expect(protocolText.contains("partialReceiveIsPeerAudioProof = false"))
    }

    @Test func macExistingDifferentAudioNoOverwriteIsStillGuarded() throws {
        let store = try sourceText("RokuricsMac/MacRecordingFileStore.swift")
        var machine = CanonicalTransferSessionStateMachine(
            sessionID: CanonicalTransferSessionID("mac-transfer-v930"),
            objectID: CanonicalObjectID("mac-recording-v930"),
            expectedByteSize: 12,
            expectedContentHash: Self.hashA,
            confirmedBytes: 12
        )
        var rejected = false
        do {
            _ = try machine.validateNoOverwrite(existingByteSize: 12, existingContentHash: Self.hashB)
        } catch CanonicalTransferStateMachineError.existingDifferentObject {
            rejected = true
        }

        #expect(rejected)
        #expect(machine.state == .conflict)
        #expect(store.contains("handleExistingAudioUpload"))
        #expect(store.contains("macRejectExistingAudioDifferentChecksum"))
        #expect(store.contains("throw MacRecordingFileStoreError.audioConflict"))
    }

    @Test func macFinalizeProofShapeIsInputOnlyForV94StatusTruth() throws {
        let proof = CanonicalTransferFinalizeProof.v930(
            receiverNodeID: CanonicalNodeID("mac-node"),
            sessionID: CanonicalTransferSessionID("mac-transfer-v930"),
            objectID: CanonicalObjectID("mac-recording-v930"),
            byteSize: 12,
            contentHash: Self.hashA,
            finalizedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 930)),
            verified: true
        )
        let runtime = try sourceText("RokuricsShared/SyncCore/CanonicalTransferRuntime.swift")

        #expect(proof.isV930VerifiedFinalizeProof)
        #expect(proof.diagnosticSnapshot.contentHashPrefix == String(Self.hashA.value.prefix(12)))
        #expect(runtime.contains("uiCompletedStatusMutated: false"))
        #expect(runtime.contains("finalizeProof: proof"))
    }

    @Test func macConnectionRuntimeOwnsLivenessWithoutReverseConnection() throws {
        let server = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")
        let receiver = try sourceText("RokuricsMac/SecureReceiverService.swift")

        #expect(server.contains("CanonicalConnectionRuntime"))
        #expect(server.contains("recordIncomingHeartbeat"))
        #expect(server.contains("makeSyncRequestedEnvelope"))
        #expect(server.contains("makeStatusRequest"))
        #expect(receiver.contains("canonicalConnectionRuntimeConfiguration"))
        #expect(receiver.contains("canonicalConnectionRuntime: CanonicalConnectionRuntime"))
        #expect(server.contains("SecureMacUploadClient(") == false)
        #expect(receiver.contains("SecureMacUploadClient(") == false)
    }

    @Test func macFinalizeRoutePublishesReceiverAcceptedProofToTruthRuntime() throws {
        let server = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")

        #expect(server.contains("produceMacTransferFinalizeProofFactIfPresent"))
        #expect(server.contains("CanonicalTransferFinalizeProof.v930"))
        #expect(server.contains("source: .transferFinalizeProof"))
        #expect(server.contains("causality: CanonicalStatusCausality(trigger: .transferFinalize)"))
        #expect(server.contains("response.statusCode == 200"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRootURL.appendingPathComponent(relativePath, isDirectory: false)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static let hashA = CanonicalHash(String(repeating: "a", count: 64))
    private static let hashB = CanonicalHash(String(repeating: "b", count: 64))
    private static let chunkA = CanonicalHash(String(repeating: "1", count: 64))
}
