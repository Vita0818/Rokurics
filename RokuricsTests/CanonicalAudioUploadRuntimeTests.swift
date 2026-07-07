//
//  CanonicalAudioUploadRuntimeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalAudioUploadRuntimeTests {
    @Test func defaultDisabledDiagnosticsOnlyAndNoCommitCreateNoJobOrNetwork() async {
        let bytes = Data("v849-runtime-default".utf8)
        let source = V849AudioRuntimeSource(objectID: "v849-runtime-default", bytes: bytes, chunkSize: 4)
        let candidate = V849AudioRuntimeSupport.candidate(objectID: source.objectID, bytes: bytes, peerState: .metadataOnly)
        let executor = CanonicalAudioUploadRuntimeExecutor()
        let store = CanonicalAudioUploadJobStore()
        let port = IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 4)

        let disabled = await executor.execute(candidate: candidate, source: source, uploadPort: port, jobStore: store)
        let diagnosticsOnly = await executor.execute(
            candidate: candidate,
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .diagnosticsOnly()
        )
        let noCommit = await executor.execute(
            candidate: candidate,
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .noCommit()
        )

        #expect(disabled.outcome == .legacyFallback)
        #expect(diagnosticsOnly.outcome == .diagnosticsOnly)
        #expect(noCommit.outcome == .noCommit)
        #expect(disabled.createdJob == false)
        #expect(diagnosticsOnly.createdJob == false)
        #expect(noCommit.createdJob == false)
        #expect(disabled.startedTransport == false)
        #expect(diagnosticsOnly.startedTransport == false)
        #expect(noCommit.startedTransport == false)
        #expect((await store.allRecords()).isEmpty)
    }

    @Test func canonicalUploadWithLegacyFallbackRequiresExplicitDebugInternalPolicy() async {
        let bytes = Data("v849-runtime-policy".utf8)
        let source = V849AudioRuntimeSource(objectID: "v849-runtime-policy", bytes: bytes, chunkSize: 5)
        let candidate = V849AudioRuntimeSupport.candidate(objectID: source.objectID, bytes: bytes, peerState: .metadataOnly)
        let executor = CanonicalAudioUploadRuntimeExecutor()
        let blockedStore = CanonicalAudioUploadJobStore()
        let allowedStore = CanonicalAudioUploadJobStore()

        let blocked = await executor.execute(
            candidate: candidate,
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5),
            jobStore: blockedStore,
            configuration: CanonicalAudioUploadRuntimeConfiguration(mode: .canonicalUploadWithLegacyFallback)
        )
        let allowed = await executor.execute(
            candidate: candidate,
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5),
            jobStore: allowedStore,
            configuration: CanonicalAudioUploadRuntimeConfiguration(
                mode: .canonicalUploadWithLegacyFallback,
                policy: CanonicalAudioUploadRuntimePolicy(
                    debugInternalBuild: true,
                    ownerApprovedCanonicalCommit: true,
                    allowCanonicalUploadWithLegacyFallback: true,
                    legacyFallbackEnabled: true,
                    chunkSize: 5
                )
            )
        )
        let commit = CanonicalAudioUploadCommitResult(runtimeResult: allowed)

        #expect(blocked.outcome == .legacyFallback)
        #expect(blocked.startedTransport == false)
        #expect((await blockedStore.allRecords()).isEmpty)
        #expect(allowed.outcome == .uploaded)
        #expect(allowed.finalizeProof?.accepted == true)
        #expect(commit.state == .finalized)
        #expect(commit.postcondition.uploadLedgerCompletedAfterProof)
        #expect(allowed.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimePeerMetadataOnlyCandidate })
        #expect(allowed.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeSessionStarted })
        #expect(allowed.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeReportBuilt })
    }

    @Test func retryExhaustionAndWrongOffsetDoNotMarkCompletedWithoutFinalizeProof() async {
        let bytes = Data("v849-wrong-offset".utf8)
        let source = V849AudioRuntimeSource(objectID: "v849-wrong-offset", bytes: bytes, chunkSize: 4)
        let candidate = V849AudioRuntimeSupport.candidate(objectID: source.objectID, bytes: bytes, peerState: .metadataOnly)
        let store = CanonicalAudioUploadJobStore()
        let result = await CanonicalAudioUploadRuntimeExecutor().execute(
            candidate: candidate,
            source: source,
            uploadPort: V849WrongOffsetUploadPort(chunkSize: 4),
            jobStore: store,
            configuration: .testTransportUpload(
                chunkSize: 4,
                retryPolicy: CanonicalAudioUploadRetryPolicy(maxAttempts: 1, retryDelaySeconds: 0)
            )
        )
        let commit = CanonicalAudioUploadCommitResult(runtimeResult: result)

        #expect(result.outcome == .failed)
        #expect(result.completed == false)
        #expect(commit.postcondition.uploadLedgerCompletedAfterProof == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeWrongOffsetDetected })
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeRetryExhausted })
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeDidNotMarkCompletedWithoutProof })
    }
}

private struct V849AudioRuntimeSource: CanonicalAudioUploadByteSource {
    let objectID: String
    let targetReference: CanonicalFileReference
    let byteSize: Int64
    let contentHash: CanonicalHash
    let preferredChunkSize: Int

    private let bytes: Data

    init(objectID: String, bytes: Data, chunkSize: Int) {
        self.objectID = objectID
        self.bytes = bytes
        self.byteSize = Int64(bytes.count)
        self.contentHash = CanonicalTransportEnvelope.hash(bytes)
        self.preferredChunkSize = chunkSize
        self.targetReference = CanonicalFileReference(
            rootToken: CanonicalRootToken("v849-runtime-test-root"),
            logicalPathToken: "audio/\(objectID).m4a",
            artifactID: CanonicalProjectionContract.artifactID(objectID: objectID, kind: .audio),
            artifactKind: .audio
        )
    }

    func readChunk(offset: CanonicalAudioUploadOffset, maxLength: Int) async throws -> Data {
        let start = min(max(0, Int(offset.value)), bytes.count)
        let end = min(bytes.count, start + max(1, maxLength))
        return Data(bytes[start..<end])
    }
}

private enum V849AudioRuntimeSupport {
    static func candidate(
        objectID: String,
        bytes: Data,
        peerState: CanonicalAudioUploadPeerState,
        trigger: CanonicalAudioUploadTriggerSource = .ordinarySync
    ) -> CanonicalAudioUploadCutoverCandidate {
        let localHash = CanonicalTransportEnvelope.hash(bytes)
        let peerTruth: CanonicalAudioUploadPeerTruth
        switch peerState {
        case .available:
            peerTruth = CanonicalAudioUploadPeerTruth(state: .available, contentHash: localHash, byteSize: Int64(bytes.count))
        case .different:
            peerTruth = CanonicalAudioUploadPeerTruth(
                state: .different,
                contentHash: CanonicalHash.sha256String("v849-different-audio"),
                byteSize: Int64(bytes.count + 1)
            )
        default:
            peerTruth = CanonicalAudioUploadPeerTruth(state: peerState)
        }
        return CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: objectID,
            localTruth: .available(hash: localHash, byteSize: Int64(bytes.count), logicalPathToken: "audio/\(objectID).m4a"),
            peerTruth: peerTruth,
            trigger: trigger
        )
    }
}

private actor V849WrongOffsetUploadPort: CanonicalProductionUploadPort {
    nonisolated let isDryRunOnly = false
    nonisolated let resumableSessionSupported = true
    nonisolated let chunkSizePolicy: Int
    private let base: IPhoneCanonicalProductionUploadPort

    init(chunkSize: Int) {
        self.chunkSizePolicy = chunkSize
        self.base = IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: chunkSize)
    }

    func startResumableUpload(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try await base.startResumableUpload(request, now: now)
    }

    func resumeUpload(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try await base.resumeUpload(request, now: now)
    }

    func uploadChunk(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus {
        throw CanonicalUploadRuntimeError.chunkOffsetMismatch(expected: 0, actual: chunk.offset)
    }

    func queryConfirmedBytes(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> Int64 {
        try await base.queryConfirmedBytes(request, now: now)
    }

    func finalizeUpload(_ request: CanonicalUploadFinalizeRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try await base.finalizeUpload(request, now: now)
    }

    func cancelUpload(_ request: CanonicalProductionUploadCancelRequest, now: Date) async throws -> CanonicalRollbackResult {
        try await base.cancelUpload(request, now: now)
    }

    nonisolated func classifyUploadFailure(_ failure: CanonicalProductionUploadFailure) -> CanonicalProductionUploadFailureClassification {
        CanonicalProductionUploadFailureClassification(kind: .retryable, retry: nil, reason: failure.code)
    }

    func readUploadLedger(objectID: String) async throws -> CanonicalProductionUploadLedgerSnapshot {
        try await base.readUploadLedger(objectID: objectID)
    }

    func writeUploadLedger(_ snapshot: CanonicalProductionUploadLedgerSnapshot) async throws -> CanonicalProductionUploadLedgerSnapshot {
        try await base.writeUploadLedger(snapshot)
    }

    nonisolated func projectRetry(_ snapshot: CanonicalProductionUploadLedgerSnapshot, now: Date) -> CanonicalRetryPolicySnapshot? {
        CanonicalRetryPolicySnapshot(retryCount: 1, nextRetryAt: CanonicalTimestamp(now), maxAttempts: 1)
    }

    func rollbackUploadState(_ request: CanonicalProductionUploadRollbackRequest) async throws -> CanonicalRollbackResult {
        try await base.rollbackUploadState(request)
    }

    func projectUploadDryRun(object: CanonicalRecordingObject, artifact: CanonicalArtifact) async throws -> CanonicalProductionUploadTrace {
        try await base.projectUploadDryRun(object: object, artifact: artifact)
    }
}
