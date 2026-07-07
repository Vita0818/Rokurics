//
//  CanonicalAudioUploadRuntimeCommitTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/7.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalAudioUploadRuntimeCommitTests {
    @Test func defaultDisabledUsesLegacyAndCreatesNoJob() async {
        let bytes = Data("audio-runtime-default-disabled".utf8)
        let source = RuntimeMemorySource(objectID: "recording-01", bytes: bytes, chunkSize: 5)
        let candidate = RuntimeTestSupport.candidate(bytes: bytes, peerState: .metadataOnly)
        let store = CanonicalAudioUploadJobStore()
        let port = IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5)

        let result = await CanonicalAudioUploadRuntimeExecutor().execute(
            candidate: candidate,
            source: source,
            uploadPort: port,
            jobStore: store
        )

        #expect(result.outcome == .legacyFallback)
        #expect(result.usedLegacyFallback)
        #expect(result.createdJob == false)
        #expect(result.startedTransport == false)
        #expect(result.sentChunkCount == 0)
        #expect((await store.allRecords()).isEmpty)
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeLegacyFallbackUsed })
    }

    @Test func diagnosticsOnlyAndCandidateDecisionRulesDoNotCommit() async {
        let bytes = Data("audio-runtime-diagnostics".utf8)
        let source = RuntimeMemorySource(objectID: "recording-01", bytes: bytes, chunkSize: 4)
        let store = CanonicalAudioUploadJobStore()
        let port = IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 4)
        let executor = CanonicalAudioUploadRuntimeExecutor()

        let metadataOnly = await executor.execute(
            candidate: RuntimeTestSupport.candidate(bytes: bytes, peerState: .metadataOnly),
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .diagnosticsOnly()
        )
        let peerUnknown = await executor.execute(
            candidate: RuntimeTestSupport.candidate(bytes: bytes, peerState: .unknown),
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .testTransportUpload(chunkSize: 4)
        )
        let same = await executor.execute(
            candidate: RuntimeTestSupport.candidate(bytes: bytes, peerState: .available),
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .testTransportUpload(chunkSize: 4)
        )
        let different = await executor.execute(
            candidate: RuntimeTestSupport.candidate(bytes: bytes, peerState: .different),
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .testTransportUpload(chunkSize: 4)
        )
        let ledgerOnly = await executor.execute(
            candidate: RuntimeTestSupport.completedLedgerOnlyCandidate(bytes: bytes),
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .testTransportUpload(chunkSize: 4)
        )

        #expect(metadataOnly.outcome == .diagnosticsOnly)
        #expect(metadataOnly.createdJob == false)
        #expect(peerUnknown.outcome == .deferred)
        #expect(peerUnknown.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimePeerUnknownDeferred })
        #expect(same.outcome == .noOp)
        #expect(same.completed)
        #expect(different.outcome == .conflict)
        #expect(different.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeExistingDifferentAudioBlocked })
        #expect(ledgerOnly.outcome == .blocked)
        #expect(ledgerOnly.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeCompletedLedgerRejectedAsNoOp })
        #expect((await store.allRecords()).isEmpty)
    }

    @Test func chunkingFinalizeAndDiagnosticsStayRedacted() async throws {
        let bytes = Data("abcdefghijklmnopqrstuvwxyz".utf8)
        let probe = RuntimeReadProbe()
        let source = RuntimeMemorySource(objectID: "recording-redacted", bytes: bytes, chunkSize: 5, probe: probe)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("canonical-audio-upload-runtime-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("jobs.json")
        let store = CanonicalAudioUploadJobStore(persistenceURL: storeURL)
        let port = IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5)

        let result = await CanonicalAudioUploadRuntimeExecutor().execute(
            candidate: RuntimeTestSupport.candidate(objectID: source.objectID, bytes: bytes, peerState: .metadataOnly),
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .testTransportUpload(chunkSize: 5)
        )
        let ledgerText = try String(contentsOf: storeURL, encoding: .utf8)
        let diagnosticsText = result.diagnostics.map(\.diagnosticsSummary).joined(separator: "\n")

        #expect(result.outcome == .uploaded)
        #expect(result.completed)
        #expect(result.confirmedBytes == Int64(bytes.count))
        #expect(result.finalizeProof?.accepted == true)
        #expect(result.sentChunkCount == 6)
        #expect(await probe.maxReadCount() <= 5)
        #expect(ledgerText.contains(source.contentHash.value) == false)
        #expect(diagnosticsText.contains(source.contentHash.value) == false)
        #expect(ledgerText.contains(storeURL.deletingLastPathComponent().path) == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeFinalizeCompleted })
    }

    @Test func duplicateChunkIsIdempotentAndWrongOffsetFails() async throws {
        let bytes = Data("duplicated-chunk".utf8)
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let chunkBytes = Data(bytes.prefix(6))
        let chunkHash = CanonicalTransportEnvelope.hash(chunkBytes)
        let reference = RuntimeTestSupport.reference(objectID: "recording-dup")
        let port = IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 8)
        let start = try await port.startResumableUpload(
            CanonicalUploadStartRequest(
                objectID: "recording-dup",
                targetReference: reference,
                totalBytes: Int64(bytes.count),
                totalHash: hash,
                chunkSize: 8
            ),
            now: Date()
        )
        let sessionID = try #require(start.sessionID)
        let first = try await port.uploadChunk(
            CanonicalUploadChunk(
                objectID: "recording-dup",
                sessionID: sessionID,
                offset: 0,
                bytes: chunkBytes,
                chunkHash: chunkHash,
                totalHash: hash,
                idempotencyKey: "chunk-0"
            ),
            now: Date()
        )
        let duplicate = try await port.uploadChunk(
            CanonicalUploadChunk(
                objectID: "recording-dup",
                sessionID: sessionID,
                offset: 0,
                bytes: chunkBytes,
                chunkHash: chunkHash,
                totalHash: hash,
                idempotencyKey: "chunk-0"
            ),
            now: Date()
        )

        #expect(first.confirmedBytes == 6)
        #expect(duplicate.confirmedBytes == 6)
        do {
            _ = try await port.uploadChunk(
                CanonicalUploadChunk(
                    objectID: "recording-dup",
                    sessionID: sessionID,
                    offset: 12,
                    bytes: Data("bad".utf8),
                    chunkHash: CanonicalTransportEnvelope.hash(Data("bad".utf8)),
                    totalHash: hash
                ),
                now: Date()
            )
            Issue.record("wrong offset unexpectedly accepted")
        } catch let error as CanonicalUploadRuntimeError {
            if case .chunkOffsetMismatch(let expected, let actual) = error {
                #expect(expected == 6)
                #expect(actual == 12)
            } else {
                Issue.record("wrong error for offset mismatch: \(error)")
            }
        }
    }

    @Test func finalizeHashMismatchBecomesConflictAndDoesNotMarkUploaded() async {
        let bytes = Data("finalize-mismatch-audio".utf8)
        let source = RuntimeMemorySource(objectID: "recording-mismatch", bytes: bytes, chunkSize: 6)
        let store = CanonicalAudioUploadJobStore()
        let port = RuntimeFinalizeMismatchUploadPort(chunkSize: 6)

        let result = await CanonicalAudioUploadRuntimeExecutor().execute(
            candidate: RuntimeTestSupport.candidate(objectID: source.objectID, bytes: bytes, peerState: .metadataOnly),
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .testTransportUpload(chunkSize: 6)
        )
        let records = await store.allRecords()

        #expect(result.outcome == .conflict)
        #expect(result.completed == false)
        #expect(result.finalizeProof == nil)
        #expect(records.first?.state == .conflict)
        #expect(records.first?.terminalConflict == true)
    }

    @Test func retryDrainerReplaysExistingRetryFromConfirmedOffsetOnly() async {
        let bytes = Data("retry-resumes-confirmed-offset".utf8)
        let source = RuntimeMemorySource(objectID: "recording-retry", bytes: bytes, chunkSize: 5)
        let store = CanonicalAudioUploadJobStore()
        let port = RuntimeFailSecondChunkOnceUploadPort(chunkSize: 5)
        let policy = CanonicalAudioUploadRetryPolicy(maxAttempts: 3, retryDelaySeconds: 0)
        let executor = CanonicalAudioUploadRuntimeExecutor()

        let first = await executor.execute(
            candidate: RuntimeTestSupport.candidate(objectID: source.objectID, bytes: bytes, peerState: .metadataOnly),
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .testTransportUpload(chunkSize: 5, retryPolicy: policy)
        )
        let retryCandidate = RuntimeTestSupport.candidate(
            objectID: source.objectID,
            bytes: bytes,
            peerState: .metadataOnly,
            trigger: .retryDrainer,
            retryTruth: CanonicalAudioUploadRetryTruth(hasExistingEligibleRetry: true, retryPending: true, canFreshCreateJob: false)
        )
        let replay = await executor.execute(
            candidate: retryCandidate,
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .testTransportUpload(chunkSize: 5, retryPolicy: policy)
        )

        #expect(first.outcome == .retryScheduled)
        #expect(first.retryRecord?.offset.value == 5)
        #expect(replay.outcome == .uploaded)
        #expect(replay.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeResumeStarted })
        #expect(await port.acceptedOffsets() == [0, 5, 10, 15, 20, 25])
    }

    @Test func retryDrainerCannotCreateFreshJob() async {
        let bytes = Data("retry-fresh-denied".utf8)
        let source = RuntimeMemorySource(objectID: "recording-fresh", bytes: bytes, chunkSize: 5)
        let store = CanonicalAudioUploadJobStore()
        let port = IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5)
        let candidate = RuntimeTestSupport.candidate(
            bytes: bytes,
            peerState: .metadataOnly,
            trigger: .retryDrainer,
            retryTruth: CanonicalAudioUploadRetryTruth(hasExistingEligibleRetry: false, retryPending: false, canFreshCreateJob: false)
        )

        let result = await CanonicalAudioUploadRuntimeExecutor().execute(
            candidate: candidate,
            source: source,
            uploadPort: port,
            jobStore: store,
            configuration: .testTransportUpload(chunkSize: 5)
        )

        #expect(result.outcome == .blocked)
        #expect(result.createdJob == false)
        #expect((await store.allRecords()).isEmpty)
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadRetryDrainerFreshJobSuppressed })
    }
}

private struct RuntimeMemorySource: CanonicalAudioUploadByteSource {
    let objectID: String
    let targetReference: CanonicalFileReference
    let byteSize: Int64
    let contentHash: CanonicalHash
    let preferredChunkSize: Int

    private let bytes: Data
    private let probe: RuntimeReadProbe?

    init(objectID: String, bytes: Data, chunkSize: Int, probe: RuntimeReadProbe? = nil) {
        self.objectID = objectID
        self.bytes = bytes
        targetReference = RuntimeTestSupport.reference(objectID: objectID)
        byteSize = Int64(bytes.count)
        contentHash = CanonicalTransportEnvelope.hash(bytes)
        preferredChunkSize = chunkSize
        self.probe = probe
    }

    func readChunk(offset: CanonicalAudioUploadOffset, maxLength: Int) async throws -> Data {
        let start = min(max(0, Int(offset.value)), bytes.count)
        let end = min(bytes.count, start + max(1, maxLength))
        let chunk = bytes[start..<end]
        await probe?.record(count: chunk.count)
        return Data(chunk)
    }
}

private actor RuntimeReadProbe {
    private var maxRead = 0

    func record(count: Int) {
        maxRead = max(maxRead, count)
    }

    func maxReadCount() -> Int {
        maxRead
    }
}

private enum RuntimeTestSupport {
    static func reference(objectID: String) -> CanonicalFileReference {
        CanonicalFileReference(
            rootToken: CanonicalRootToken("runtime-test-root"),
            logicalPathToken: "audio/\(objectID).m4a",
            artifactID: CanonicalProjectionContract.artifactID(objectID: objectID, kind: .audio),
            artifactKind: .audio
        )
    }

    static func candidate(
        objectID: String = "recording-01",
        bytes: Data,
        peerState: CanonicalAudioUploadPeerState,
        trigger: CanonicalAudioUploadTriggerSource = .ordinarySync,
        retryTruth: CanonicalAudioUploadRetryTruth = CanonicalAudioUploadRetryTruth()
    ) -> CanonicalAudioUploadCutoverCandidate {
        let localHash = CanonicalTransportEnvelope.hash(bytes)
        let peerTruth: CanonicalAudioUploadPeerTruth
        switch peerState {
        case .available:
            peerTruth = CanonicalAudioUploadPeerTruth(state: .available, contentHash: localHash, byteSize: Int64(bytes.count))
        case .different:
            peerTruth = CanonicalAudioUploadPeerTruth(
                state: .available,
                contentHash: CanonicalHash.sha256String("different"),
                byteSize: Int64(bytes.count + 1)
            )
        default:
            peerTruth = CanonicalAudioUploadPeerTruth(state: peerState)
        }
        return CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: objectID,
            localTruth: .available(hash: localHash, byteSize: Int64(bytes.count), logicalPathToken: "audio/\(objectID).m4a"),
            peerTruth: peerTruth,
            retryTruth: retryTruth,
            trigger: trigger
        )
    }

    static func completedLedgerOnlyCandidate(bytes: Data) -> CanonicalAudioUploadCutoverCandidate {
        let hash = CanonicalTransportEnvelope.hash(bytes)
        return CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: "recording-01",
            localTruth: .available(hash: hash, byteSize: Int64(bytes.count), logicalPathToken: "audio/recording-01.m4a"),
            peerTruth: CanonicalAudioUploadPeerTruth(state: .metadataOnly, receiveRecordExists: true, metadataUploaded: true),
            ledgerTruth: CanonicalAudioUploadLedgerTruth(
                phase: .completed,
                contentHash: hash,
                byteSize: Int64(bytes.count),
                metadataUploaded: true,
                uiUploaded: true,
                receiveRecordExists: true
            ),
            trigger: .ordinarySync
        )
    }
}

private actor RuntimeFinalizeMismatchUploadPort: CanonicalProductionUploadPort {
    nonisolated let isDryRunOnly = false
    nonisolated let resumableSessionSupported = true
    nonisolated let chunkSizePolicy: Int
    private let base: IPhoneCanonicalProductionUploadPort

    init(chunkSize: Int) {
        chunkSizePolicy = chunkSize
        base = IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: chunkSize)
    }

    func startResumableUpload(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try await base.startResumableUpload(request, now: now)
    }

    func resumeUpload(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try await base.resumeUpload(request, now: now)
    }

    func uploadChunk(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus {
        try await base.uploadChunk(chunk, now: now)
    }

    func queryConfirmedBytes(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> Int64 {
        try await base.queryConfirmedBytes(request, now: now)
    }

    func finalizeUpload(_ request: CanonicalUploadFinalizeRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        let status = try await base.finalizeUpload(request, now: now)
        return CanonicalUploadSessionStatus(
            ok: true,
            disposition: status.disposition,
            phase: .completed,
            sessionID: status.sessionID,
            confirmedBytes: status.confirmedBytes,
            nextOffset: status.nextOffset,
            chunkSize: status.chunkSize,
            completed: true,
            finalFile: status.finalFile,
            checksum: CanonicalHash.sha256String("wrong-final-hash"),
            fileSize: status.fileSize,
            retry: nil,
            error: nil
        )
    }

    func cancelUpload(_ request: CanonicalProductionUploadCancelRequest, now: Date) async throws -> CanonicalRollbackResult {
        try await base.cancelUpload(request, now: now)
    }

    nonisolated func classifyUploadFailure(_ failure: CanonicalProductionUploadFailure) -> CanonicalProductionUploadFailureClassification {
        CanonicalProductionUploadFailureClassification(kind: .conflict, retry: nil, reason: failure.code)
    }

    func readUploadLedger(objectID: String) async throws -> CanonicalProductionUploadLedgerSnapshot {
        try await base.readUploadLedger(objectID: objectID)
    }

    func writeUploadLedger(_ snapshot: CanonicalProductionUploadLedgerSnapshot) async throws -> CanonicalProductionUploadLedgerSnapshot {
        try await base.writeUploadLedger(snapshot)
    }

    nonisolated func projectRetry(_ snapshot: CanonicalProductionUploadLedgerSnapshot, now: Date) -> CanonicalRetryPolicySnapshot? {
        nil
    }

    func rollbackUploadState(_ request: CanonicalProductionUploadRollbackRequest) async throws -> CanonicalRollbackResult {
        try await base.rollbackUploadState(request)
    }

    func projectUploadDryRun(object: CanonicalRecordingObject, artifact: CanonicalArtifact) async throws -> CanonicalProductionUploadTrace {
        try await base.projectUploadDryRun(object: object, artifact: artifact)
    }
}

private actor RuntimeFailSecondChunkOnceUploadPort: CanonicalProductionUploadPort {
    nonisolated let isDryRunOnly = false
    nonisolated let resumableSessionSupported = true
    nonisolated let chunkSizePolicy: Int
    private let base: IPhoneCanonicalProductionUploadPort
    private var accepted: [Int64] = []
    private var acceptedFirst = false
    private var failedOnce = false

    init(chunkSize: Int) {
        chunkSizePolicy = chunkSize
        base = IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: chunkSize)
    }

    func acceptedOffsets() -> [Int64] {
        accepted
    }

    func startResumableUpload(_ request: CanonicalUploadStartRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try await base.startResumableUpload(request, now: now)
    }

    func resumeUpload(_ request: CanonicalUploadStatusRequest, now: Date) async throws -> CanonicalUploadSessionStatus {
        try await base.resumeUpload(request, now: now)
    }

    func uploadChunk(_ chunk: CanonicalUploadChunk, now: Date) async throws -> CanonicalUploadSessionStatus {
        if acceptedFirst, !failedOnce {
            failedOnce = true
            throw CanonicalUploadRuntimeError.chunkOffsetMismatch(expected: chunk.offset, actual: chunk.offset + 1)
        }
        let status = try await base.uploadChunk(chunk, now: now)
        accepted.append(chunk.offset)
        acceptedFirst = true
        return status
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
        CanonicalProductionUploadFailureClassification(
            kind: .retryable,
            retry: CanonicalRetryPolicySnapshot(retryCount: 1, nextRetryAt: nil, maxAttempts: 3),
            reason: failure.code
        )
    }

    func readUploadLedger(objectID: String) async throws -> CanonicalProductionUploadLedgerSnapshot {
        try await base.readUploadLedger(objectID: objectID)
    }

    func writeUploadLedger(_ snapshot: CanonicalProductionUploadLedgerSnapshot) async throws -> CanonicalProductionUploadLedgerSnapshot {
        try await base.writeUploadLedger(snapshot)
    }

    nonisolated func projectRetry(_ snapshot: CanonicalProductionUploadLedgerSnapshot, now: Date) -> CanonicalRetryPolicySnapshot? {
        CanonicalRetryPolicySnapshot(retryCount: 1, nextRetryAt: CanonicalTimestamp(now), maxAttempts: 3)
    }

    func rollbackUploadState(_ request: CanonicalProductionUploadRollbackRequest) async throws -> CanonicalRollbackResult {
        try await base.rollbackUploadState(request)
    }

    func projectUploadDryRun(object: CanonicalRecordingObject, artifact: CanonicalArtifact) async throws -> CanonicalProductionUploadTrace {
        try await base.projectUploadDryRun(object: object, artifact: artifact)
    }
}
