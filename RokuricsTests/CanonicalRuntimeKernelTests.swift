//
//  CanonicalRuntimeKernelTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalRuntimeKernelTests {
    @Test func fileRuntimeResolvesRootBoundPathsAndRejectsUnsafeTokens() async throws {
        let root = CanonicalRootToken("runtime-root")
        let store = InMemoryCanonicalFileStore(rootBindings: [root: "runtime/root"])
        let safe = CanonicalFileReference(rootToken: root, logicalPathToken: "artifacts/recording-01/audio.m4a")
        let resolved = try await store.resolve(safe)

        #expect(resolved.isInsideRoot)
        #expect(resolved.resolvedPathToken == "runtime/root/artifacts/recording-01/audio.m4a")

        await expectFileError(.absolutePathRejected("/absolute/path")) {
            _ = try await store.resolve(CanonicalFileReference(rootToken: root, logicalPathToken: "/absolute/path"))
        }
        await expectFileError(.schemeURLRejected("file://audio.m4a")) {
            _ = try await store.resolve(CanonicalFileReference(rootToken: root, logicalPathToken: "file://audio.m4a"))
        }
        await expectFileError(.backslashTraversalRejected("folder\\..\\audio.m4a")) {
            _ = try await store.resolve(CanonicalFileReference(rootToken: root, logicalPathToken: "folder\\..\\audio.m4a"))
        }
        await expectFileError(.pathTraversalRejected("folder/../audio.m4a")) {
            _ = try await store.resolve(CanonicalFileReference(rootToken: root, logicalPathToken: "folder/../audio.m4a"))
        }

        let unsafeRootStore = InMemoryCanonicalFileStore(rootBindings: [root: "runtime/../escape"])
        await expectFileError(.rootEscapeRejected("runtime/../escape")) {
            _ = try await unsafeRootStore.resolve(safe)
        }
    }

    @Test func fileRuntimeVerifiesHashesNoOverwriteMetadataAndTombstoneWithoutDelete() async throws {
        let root = CanonicalRootToken("runtime-root")
        let store = InMemoryCanonicalFileStore(rootBindings: [root: "runtime/root"])
        let reference = CanonicalFileReference(
            rootToken: root,
            logicalPathToken: "generated/recording-01/note.md",
            artifactID: "noteMarkdown:recording-01",
            artifactKind: .noteMarkdown
        )
        let bytes = Data("note body".utf8)
        let hash = try #require(InMemoryCanonicalFileStore.hash(bytes, policy: .sha256))
        let result = try await store.write(
            CanonicalFileWriteIntent(
                reference: reference,
                bytes: bytes,
                purpose: .generatedArtifact,
                expectedContentHash: hash,
                expectedByteSize: Int64(bytes.count),
                conflictPolicy: .noOverwrite
            )
        )
        let read = try await store.read(CanonicalFileReadRequest(reference: reference))

        #expect(result.disposition == .created)
        #expect(read.bytes == bytes)
        #expect(read.contentHash == hash)

        let same = try await store.write(
            CanonicalFileWriteIntent(
                reference: reference,
                bytes: bytes,
                purpose: .generatedArtifact,
                expectedContentHash: hash,
                expectedByteSize: Int64(bytes.count),
                conflictPolicy: .idempotentIfSameContent
            )
        )
        #expect(same.disposition == .acceptedExisting)

        await expectFileError(.conflict(reference.logicalPathToken)) {
            _ = try await store.write(
                CanonicalFileWriteIntent(
                    reference: reference,
                    bytes: Data("different".utf8),
                    purpose: .generatedArtifact,
                    conflictPolicy: .noOverwrite
                )
            )
        }

        let metadataRef = CanonicalFileReference(rootToken: root, logicalPathToken: "metadata/recording-01.json")
        let metadataBytes = try CanonicalTransportJSON.encode(["objectID": "recording-01"])
        _ = try await store.write(
            CanonicalFileWriteIntent(
                reference: metadataRef,
                bytes: metadataBytes,
                purpose: .metadataBlob,
                expectedByteSize: Int64(metadataBytes.count),
                conflictPolicy: .replace,
                metadataBlob: CanonicalMetadataBlob(["objectID": "recording-01", "kind": "metadata"])
            )
        )
        let metadata = try await store.read(CanonicalFileReadRequest(reference: metadataRef))
        #expect(metadata.metadataBlob?.fields["kind"] == "metadata")

        _ = try await store.markTombstone(reference, reason: "softDelete")
        await expectFileError(.tombstoned(reference.logicalPathToken)) {
            _ = try await store.read(CanonicalFileReadRequest(reference: reference))
        }
        let tombstoned = try await store.read(CanonicalFileReadRequest(reference: reference, allowTombstonedRead: true))
        #expect(tombstoned.bytes == bytes)
        #expect(tombstoned.tombstoned)
    }

    @Test func transportRuntimeValidatesRoutesCapabilitiesHashesAndIdempotency() async throws {
        let transport = InMemoryCanonicalTransportRuntime()
        let iphone = CanonicalNode(nodeID: "iphone-01", platform: "iPhone", capabilities: [.recordingMetadata, .audioArtifact, .objectProjection])
        let mac = CanonicalNode(nodeID: "mac-01", platform: "Mac", capabilities: [.recordingMetadata, .audioArtifact, .objectProjection])
        await transport.register(node: iphone, allowedRoutes: [.manifestExchange, .uploadStart])
        await transport.register(node: mac, allowedRoutes: [.manifestExchange, .uploadStart])
        await transport.registerHandler(nodeID: mac.nodeID, route: .manifestExchange) { envelope in
            let manifest = try CanonicalTransportJSON.decode(CanonicalManifest.self, from: envelope.body)
            guard manifest.hasValidManifestHash else {
                throw CanonicalTransportRuntimeError.invalidManifestHash(manifest.node.nodeID)
            }
            return CanonicalTransportResponse(ok: true, status: "manifestAccepted", body: envelope.body)
        }

        let manifest = CanonicalManifest.make(node: iphone, objects: [recording()])
        let body = try CanonicalTransportJSON.encode(manifest)
        let envelope = CanonicalTransportEnvelope(
            sourceNodeID: iphone.nodeID,
            destinationNodeID: mac.nodeID,
            route: .manifestExchange,
            body: body,
            idempotencyKey: "manifest-1"
        )
        let first = try await transport.send(envelope)
        let replay = try await transport.send(envelope)

        #expect(first == replay)
        #expect(first.ok)

        let limited = CanonicalNode(nodeID: "limited-01", platform: "Mac", capabilities: [.recordingMetadata])
        await transport.register(node: limited, allowedRoutes: [.uploadStart])
        await expectTransportError(.capabilityMissing(nodeID: limited.nodeID, capability: .audioArtifact)) {
            _ = try await transport.send(
                CanonicalTransportEnvelope(
                    sourceNodeID: iphone.nodeID,
                    destinationNodeID: limited.nodeID,
                    route: .uploadStart
                )
            )
        }
    }

    @Test func resumableUploadRuntimeSupportsResumeIdempotentChunksFinalizeAndRetrySnapshot() async throws {
        let root = CanonicalRootToken("upload-root")
        let store = InMemoryCanonicalFileStore(rootBindings: [root: "upload/root"])
        let runtime = CanonicalResumableUploadRuntime(
            fileStore: store,
            retryPolicy: CanonicalUploadRetryPolicy(maxAttempts: 2, retryDelaySeconds: 10)
        )
        let bytes = Data("abcdefghi".utf8)
        let totalHash = try #require(InMemoryCanonicalFileStore.hash(bytes, policy: .sha256))
        let reference = CanonicalFileReference(rootToken: root, logicalPathToken: "audio/recording-01.m4a", artifactKind: .audio)
        let start = try await runtime.start(
            CanonicalUploadStartRequest(
                objectID: "recording-01",
                targetReference: reference,
                totalBytes: Int64(bytes.count),
                totalHash: totalHash,
                chunkSize: 4
            ),
            now: date(1_000)
        )
        let sessionID = try #require(start.sessionID)
        let firstChunk = bytes.subdata(in: 0..<4)
        let firstHash = try #require(InMemoryCanonicalFileStore.hash(firstChunk, policy: .sha256))
        let first = CanonicalUploadChunk(
            objectID: "recording-01",
            sessionID: sessionID,
            offset: 0,
            bytes: firstChunk,
            chunkHash: firstHash,
            totalHash: totalHash,
            idempotencyKey: "chunk-0"
        )
        let firstResponse = try await runtime.append(first, now: date(1_001))
        let replay = try await runtime.append(first, now: date(1_002))

        #expect(firstResponse.confirmedBytes == 4)
        #expect(replay.confirmedBytes == 4)

        await expectUploadError(.chunkOffsetMismatch(expected: 4, actual: 5)) {
            _ = try await runtime.append(
                CanonicalUploadChunk(
                    objectID: "recording-01",
                    sessionID: sessionID,
                    offset: 5,
                    bytes: Data("x".utf8),
                    chunkHash: try #require(InMemoryCanonicalFileStore.hash(Data("x".utf8), policy: .sha256)),
                    totalHash: totalHash
                )
            )
        }

        _ = try await runtime.recordRetryableFailure(sessionID: sessionID, code: "networkTimeout", now: date(1_003))
        let retry = try await runtime.retryDriveSnapshot(sessionID: sessionID)
        #expect(retry.retryCount == 1)
        #expect(retry.nextRetryAt?.date == date(1_013))

        let secondChunk = bytes.subdata(in: 4..<bytes.count)
        let secondHash = try #require(InMemoryCanonicalFileStore.hash(secondChunk, policy: .sha256))
        _ = try await runtime.append(
            CanonicalUploadChunk(
                objectID: "recording-01",
                sessionID: sessionID,
                offset: 4,
                bytes: secondChunk,
                chunkHash: secondHash,
                totalHash: totalHash,
                idempotencyKey: "chunk-4"
            ),
            now: date(1_014)
        )
        let finalized = try await runtime.finalize(
            CanonicalUploadFinalizeRequest(
                objectID: "recording-01",
                sessionID: sessionID,
                totalBytes: Int64(bytes.count),
                totalHash: totalHash
            ),
            now: date(1_015)
        )
        let stored = try await store.read(CanonicalFileReadRequest(reference: reference))

        #expect(finalized.completed)
        #expect(finalized.confirmedBytes == Int64(bytes.count))
        #expect(stored.bytes == bytes)
        #expect(stored.contentHash == totalHash)
    }

    private func recording() -> CanonicalRecordingObject {
        let metadata = CanonicalRecordingMetadata(
            objectID: "recording-01",
            title: "Lecture",
            createdAt: CanonicalTimestamp(date(1_000)),
            modifiedAt: CanonicalTimestamp(date(2_000)),
            duration: 42
        )
        let audio = CanonicalArtifactFact.audio(
            availability: .available,
            contentHash: CanonicalHash(String(repeating: "a", count: 64)),
            byteSize: 42,
            logicalName: "audio.m4a"
        ).makeArtifact(objectID: metadata.objectID)
        return CanonicalRecordingObject(objectID: metadata.objectID, metadata: metadata, artifacts: [audio])
    }

    private func expectFileError(
        _ expected: CanonicalFileRuntimeError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected file runtime error \(expected)")
        } catch let error as CanonicalFileRuntimeError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    private func expectTransportError(
        _ expected: CanonicalTransportRuntimeError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected transport runtime error \(expected)")
        } catch let error as CanonicalTransportRuntimeError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    private func expectUploadError(
        _ expected: CanonicalUploadRuntimeError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected upload runtime error \(expected)")
        } catch let error as CanonicalUploadRuntimeError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}
