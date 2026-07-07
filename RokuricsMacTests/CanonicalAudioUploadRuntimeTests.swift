//
//  CanonicalAudioUploadRuntimeTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalAudioUploadRuntimeTests {
    @Test func requestVerifierCoversOnlyExistingResumableUploadRoutes() throws {
        let verifier = try sourceText("RokuricsMac/RequestVerifier.swift")
        let server = try sourceText("RokuricsMac/SecureLocalHTTPSServer.swift")
        let routes = [
            "/upload-recording-audio-session/start",
            "/upload-recording-audio-session/status",
            "/upload-recording-audio-session/chunk",
            "/upload-recording-audio-session/finalize"
        ]

        for route in routes {
            #expect(verifier.contains(route))
            #expect(server.contains(route))
        }
        #expect(verifier.contains("/upload-recording-audio-session/abort") == false)
        #expect(server.contains("/upload-recording-audio-session/abort") == false)
        #expect(verifier.contains("X-Rokurics-Body-SHA256") || verifier.contains("bodySHA256"))
        #expect(verifier.contains("X-Rokurics-Nonce") || verifier.contains("nonce"))
        #expect(verifier.contains("X-Rokurics-Signature") || verifier.contains("signature"))
    }

    @Test func macFakeRuntimeKeepsDuplicateChunksIdempotentAndFinalizesWithProof() async throws {
        let bytes = Data("v849-mac-runtime-duplicate".utf8)
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let firstChunk = Data(bytes.prefix(7))
        let firstHash = CanonicalTransportEnvelope.hash(firstChunk)
        let port = MacCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 8)
        let start = try await port.startResumableUpload(
            CanonicalUploadStartRequest(
                objectID: "v849-mac-runtime",
                targetReference: reference(objectID: "v849-mac-runtime"),
                totalBytes: Int64(bytes.count),
                totalHash: hash,
                chunkSize: 8
            ),
            now: Date()
        )
        let sessionID = try #require(start.sessionID)
        _ = try await port.uploadChunk(
            CanonicalUploadChunk(
                objectID: "v849-mac-runtime",
                sessionID: sessionID,
                offset: 0,
                bytes: firstChunk,
                chunkHash: firstHash,
                totalHash: hash
            ),
            now: Date()
        )
        let duplicate = try await port.uploadChunk(
            CanonicalUploadChunk(
                objectID: "v849-mac-runtime",
                sessionID: sessionID,
                offset: 0,
                bytes: firstChunk,
                chunkHash: firstHash,
                totalHash: hash
            ),
            now: Date()
        )
        let remaining = Data(bytes.dropFirst(7))
        _ = try await port.uploadChunk(
            CanonicalUploadChunk(
                objectID: "v849-mac-runtime",
                sessionID: sessionID,
                offset: 7,
                bytes: remaining,
                chunkHash: CanonicalTransportEnvelope.hash(remaining),
                totalHash: hash
            ),
            now: Date()
        )
        let finalized = try await port.finalizeUpload(
            CanonicalUploadFinalizeRequest(
                objectID: "v849-mac-runtime",
                sessionID: sessionID,
                totalBytes: Int64(bytes.count),
                totalHash: hash
            ),
            now: Date()
        )

        #expect(duplicate.disposition == .acceptedExisting)
        #expect(duplicate.confirmedBytes == 7)
        #expect(finalized.completed)
        #expect(finalized.fileSize == Int64(bytes.count))
        #expect(finalized.checksum == hash)
    }

    private func reference(objectID: String) -> CanonicalFileReference {
        CanonicalFileReference(
            rootToken: CanonicalRootToken("v849-mac-runtime-test-root"),
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
