//
//  CanonicalAudioUploadRuntimeCommitTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalAudioUploadRuntimeCommitMacTests {
    @Test func requestVerifierAndServerRouteAllowlistRemainExistingOnly() throws {
        let verifier = try sourceText("RokuricsMac/RequestVerifier.swift")
        let server = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")
        let expectedRoutes = [
            "/upload-recording-audio",
            "/upload-recording-audio-session/start",
            "/upload-recording-audio-session/status",
            "/upload-recording-audio-session/chunk",
            "/upload-recording-audio-session/finalize"
        ]

        for route in expectedRoutes {
            #expect(verifier.contains(route) || server.contains(route))
        }
        #expect(verifier.contains("/upload-recording-audio-session/abort") == false)
        #expect(server.contains("/upload-recording-audio-session/abort") == false)
        #expect(verifier.contains("verify("))
        #expect(verifier.contains("bodySHA256"))
        #expect(server.contains("resumableAudioStartResponse"))
        #expect(server.contains("resumableAudioStatusResponse"))
        #expect(server.contains("resumableAudioChunkResponse"))
        #expect(server.contains("resumableAudioFinalizeResponse"))
    }

    @Test func macReceivePathStillWritesOnlyAfterVerifiedFinalizeAndBlocksDifferentAudio() throws {
        let store = try sourceText("RokuricsMac/MacRecordingFileStore.swift")
        let server = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")

        #expect(server.contains("StreamingBodyWriter"))
        #expect(server.contains("temporaryAudioUploadURL"))
        #expect(store.contains("finalizeResumableAudioUpload"))
        #expect(store.contains("canonicalAudioChecksum("))
        #expect(store.contains("fileURL: partURL"))
        #expect(store.contains("constantTimeEquals(checksum, request.totalSHA256)"))
        #expect(store.contains("moveItem(at: partURL"))
        #expect(store.contains("completedAudioResponseIfPresent"))
        #expect(store.contains("handleExistingAudioUpload"))
        #expect(store.contains("audioConflict"))
    }

    @Test func macCanonicalFakePortDuplicateChunkIsIdempotentAndWrongOffsetFails() async throws {
        let bytes = Data("mac-duplicate-chunk".utf8)
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let chunkBytes = Data(bytes.prefix(5))
        let chunkHash = CanonicalTransportEnvelope.hash(chunkBytes)
        let port = MacCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 8)
        let start = try await port.startResumableUpload(
            CanonicalUploadStartRequest(
                objectID: "mac-recording-dup",
                targetReference: reference(objectID: "mac-recording-dup"),
                totalBytes: Int64(bytes.count),
                totalHash: hash,
                chunkSize: 8
            ),
            now: Date()
        )
        let sessionID = try #require(start.sessionID)
        let first = try await port.uploadChunk(
            CanonicalUploadChunk(
                objectID: "mac-recording-dup",
                sessionID: sessionID,
                offset: 0,
                bytes: chunkBytes,
                chunkHash: chunkHash,
                totalHash: hash
            ),
            now: Date()
        )
        let duplicate = try await port.uploadChunk(
            CanonicalUploadChunk(
                objectID: "mac-recording-dup",
                sessionID: sessionID,
                offset: 0,
                bytes: chunkBytes,
                chunkHash: chunkHash,
                totalHash: hash
            ),
            now: Date()
        )

        #expect(first.confirmedBytes == 5)
        #expect(duplicate.confirmedBytes == 5)
        do {
            _ = try await port.uploadChunk(
                CanonicalUploadChunk(
                    objectID: "mac-recording-dup",
                    sessionID: sessionID,
                    offset: 10,
                    bytes: Data("bad".utf8),
                    chunkHash: CanonicalTransportEnvelope.hash(Data("bad".utf8)),
                    totalHash: hash
                ),
                now: Date()
            )
            Issue.record("wrong offset unexpectedly accepted")
        } catch let error as CanonicalUploadRuntimeError {
            if case .chunkOffsetMismatch(let expected, let actual) = error {
                #expect(expected == 5)
                #expect(actual == 10)
            } else {
                Issue.record("wrong error for offset mismatch: \(error)")
            }
        }
    }

    private func reference(objectID: String) -> CanonicalFileReference {
        CanonicalFileReference(
            rootToken: CanonicalRootToken("mac-runtime-test-root"),
            logicalPathToken: "audio/\(objectID).m4a",
            artifactID: CanonicalProjectionContract.artifactID(objectID: objectID, kind: .audio),
            artifactKind: .audio
        )
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRootURL.appendingPathComponent(relativePath, isDirectory: false)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
