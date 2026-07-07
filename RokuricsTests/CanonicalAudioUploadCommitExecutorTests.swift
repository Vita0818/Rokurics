//
//  CanonicalAudioUploadCommitExecutorTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalAudioUploadCommitExecutorTests {
    @Test func cutoverProtocolAndIPhoneExecutorExistAndExecuteMetadataOnlyCandidate() async {
        let bytes = Data("v859-cutover-executor".utf8)
        let source = V849CommitSource(objectID: "v859-cutover-executor", bytes: bytes, chunkSize: 6)
        let candidate = V849CommitSupport.candidate(objectID: source.objectID, bytes: bytes, peerTruth: .metadataOnly)
        let executor: any CanonicalAudioUploadCutoverExecutor = IPhoneAudioUploadCutoverExecutor(
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 6),
            jobStore: CanonicalAudioUploadJobStore()
        )

        let readiness = await executor.canExecute(candidate)
        let result = await executor.execute(
            CanonicalAudioUploadCutoverExecutionRequest(
                candidate: candidate,
                configuration: .testTransportUpload(chunkSize: 6),
                nodeRole: .iPhone
            )
        )

        #expect(readiness.canExecute)
        #expect(result.outcome == .uploaded)
        #expect(result.postcondition.finalizeProofAccepted)
        #expect(result.postcondition.uploadLedgerCompletedAfterProof)
        #expect(result.legacyFallbackDecision.suppressLegacyDuplicate)
    }

    @Test func metadataOnlyPeerUploadsAndOnlyFinalizedProofSuppressesLegacyDuplicate() async {
        let bytes = Data("v849-commit-metadata-only".utf8)
        let source = V849CommitSource(objectID: "v849-commit-metadata-only", bytes: bytes, chunkSize: 6)
        let result = await CanonicalAudioUploadCommitExecutor().execute(
            candidate: V849CommitSupport.candidate(objectID: source.objectID, bytes: bytes, peerTruth: .metadataOnly),
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 6),
            jobStore: CanonicalAudioUploadJobStore(),
            configuration: .testTransportUpload(chunkSize: 6)
        )
        let commit = CanonicalAudioUploadCommitResult(runtimeResult: result)

        #expect(result.outcome == .uploaded)
        #expect(commit.state == .finalized)
        #expect(commit.postcondition.finalizeProofAccepted)
        #expect(commit.postcondition.uploadLedgerCompletedAfterProof)
        #expect(commit.legacyFallbackDecision.suppressLegacyDuplicate)
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimePeerMetadataOnlyCandidate })
    }

    @Test func iPhoneCutoverExecutorStreamsLongRecordingInBoundedChunks() async {
        let bytes = Data((0..<97).map { UInt8($0 % 251) })
        let source = V859BoundedCommitSource(objectID: "v859-bounded-streaming", bytes: bytes, chunkSize: 8)
        let candidate = V849CommitSupport.candidate(objectID: source.objectID, bytes: bytes, peerTruth: .metadataOnly)
        let executor: any CanonicalAudioUploadCutoverExecutor = IPhoneAudioUploadCutoverExecutor(
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 8),
            jobStore: CanonicalAudioUploadJobStore()
        )

        let result = await executor.execute(
            CanonicalAudioUploadCutoverExecutionRequest(
                candidate: candidate,
                configuration: .testTransportUpload(chunkSize: 8),
                nodeRole: .iPhone
            )
        )

        #expect(result.outcome == .uploaded)
        #expect(result.postcondition.finalizeProofAccepted)
        #expect(source.maxObservedReadLength <= 8)
        #expect(source.readCount > 1)
    }

    @Test func sameHashAndByteSizeIsNoOpButCompletedLedgerAloneIsRejected() async {
        let bytes = Data("v849-commit-noop-ledger".utf8)
        let source = V849CommitSource(objectID: "v849-commit-noop-ledger", bytes: bytes, chunkSize: 5)
        let executor = CanonicalAudioUploadCommitExecutor()
        let same = await executor.execute(
            candidate: V849CommitSupport.candidate(objectID: source.objectID, bytes: bytes, peerTruth: .availableSame),
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5),
            jobStore: CanonicalAudioUploadJobStore(),
            configuration: .testTransportUpload(chunkSize: 5)
        )
        let ledgerOnly = await executor.execute(
            candidate: V849CommitSupport.completedLedgerOnlyCandidate(objectID: source.objectID, bytes: bytes),
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5),
            jobStore: CanonicalAudioUploadJobStore(),
            configuration: .testTransportUpload(chunkSize: 5)
        )

        #expect(CanonicalAudioUploadCommitResult(runtimeResult: same).state == .noOpSameAudio)
        #expect(same.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeSameAudioNoOp })
        #expect(ledgerOnly.outcome == .blocked)
        #expect(CanonicalAudioUploadCommitResult(runtimeResult: ledgerOnly).legacyFallbackDecision.suppressLegacyDuplicate == false)
        #expect(ledgerOnly.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeCompletedLedgerRejectedAsNoOp })
        #expect(ledgerOnly.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeDidNotMarkCompletedWithoutProof })
    }

    @Test func peerUnknownDefersAndDifferentPeerAudioConflictsWithoutOverwrite() async {
        let bytes = Data("v849-commit-peer-state".utf8)
        let source = V849CommitSource(objectID: "v849-commit-peer-state", bytes: bytes, chunkSize: 5)
        let executor = CanonicalAudioUploadCommitExecutor()
        let unknown = await executor.execute(
            candidate: V849CommitSupport.candidate(objectID: source.objectID, bytes: bytes, peerTruth: .unknown),
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5),
            jobStore: CanonicalAudioUploadJobStore(),
            configuration: .testTransportUpload(chunkSize: 5)
        )
        let different = await executor.execute(
            candidate: V849CommitSupport.candidate(objectID: source.objectID, bytes: bytes, peerTruth: .different),
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5),
            jobStore: CanonicalAudioUploadJobStore(),
            configuration: .testTransportUpload(chunkSize: 5)
        )

        #expect(CanonicalAudioUploadCommitResult(runtimeResult: unknown).state == .deferredPeerUnknown)
        #expect(unknown.createdJob == false)
        #expect(CanonicalAudioUploadCommitResult(runtimeResult: different).state == .blockedConflict)
        #expect(different.createdJob == false)
        #expect(different.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeDidNotOverwriteExistingAudio })
    }

    @Test func localAudioMissingIsBlockedBeforeNetwork() async {
        let bytes = Data("v849-commit-local-missing".utf8)
        let source = V849CommitSource(objectID: "v849-commit-local-missing", bytes: bytes, chunkSize: 5)
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let candidate = CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: source.objectID,
            localTruth: CanonicalAudioUploadLocalTruth(
                audioAvailable: false,
                contentHash: hash,
                byteSize: Int64(bytes.count),
                logicalPathToken: "audio/\(source.objectID).m4a"
            ),
            peerTruth: CanonicalAudioUploadPeerTruth(state: .metadataOnly),
            trigger: .ordinarySync
        )

        let result = await CanonicalAudioUploadCommitExecutor().execute(
            candidate: candidate,
            source: source,
            uploadPort: IPhoneCanonicalProductionUploadPort(testOnlyChunkSizePolicy: 5),
            jobStore: CanonicalAudioUploadJobStore(),
            configuration: .testTransportUpload(chunkSize: 5)
        )

        #expect(CanonicalAudioUploadCommitResult(runtimeResult: result).state == .blockedMissingLocalAudio)
        #expect(result.startedTransport == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeCandidateBlocked })
    }

    @Test func coordinatorStillKeepsLegacyFallbackAfterCutoverExecutor() throws {
        let coordinator = try sourceText("Rokurics/RecordingUploadCoordinator.swift")
        let secureAdapter = try sourceText("Rokurics/IPhoneCanonicalAudioUploadRuntimeAdapter.swift")

        #expect(coordinator.contains("IPhoneAudioUploadCutoverExecutor"))
        #expect(coordinator.contains("case .legacyFallback:"))
        #expect(coordinator.contains("uploadClient.uploadRecording("))
        #expect(secureAdapter.contains("SecureMacUploadClient"))
        #expect(secureAdapter.contains("startResumableAudioUpload"))
        #expect(secureAdapter.contains("fetchResumableAudioUploadStatus"))
        #expect(secureAdapter.contains("uploadResumableAudioChunk"))
        #expect(secureAdapter.contains("finalizeResumableAudioUpload"))
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let projectRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRootURL.appendingPathComponent(relativePath, isDirectory: false)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private struct V849CommitSource: CanonicalAudioUploadByteSource {
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
            rootToken: CanonicalRootToken("v849-commit-test-root"),
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

private final class V859BoundedCommitSource: @unchecked Sendable, CanonicalAudioUploadByteSource {
    let objectID: String
    let targetReference: CanonicalFileReference
    let byteSize: Int64
    let contentHash: CanonicalHash
    let preferredChunkSize: Int

    private let bytes: Data
    private let lock = NSLock()
    private var _readCount = 0
    private var _maxObservedReadLength = 0

    init(objectID: String, bytes: Data, chunkSize: Int) {
        self.objectID = objectID
        self.bytes = bytes
        self.byteSize = Int64(bytes.count)
        self.contentHash = CanonicalTransportEnvelope.hash(bytes)
        self.preferredChunkSize = chunkSize
        self.targetReference = CanonicalFileReference(
            rootToken: CanonicalRootToken("v859-bounded-test-root"),
            logicalPathToken: "audio/\(objectID).m4a",
            artifactID: CanonicalProjectionContract.artifactID(objectID: objectID, kind: .audio),
            artifactKind: .audio
        )
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _readCount
    }

    var maxObservedReadLength: Int {
        lock.lock()
        defer { lock.unlock() }
        return _maxObservedReadLength
    }

    func readChunk(offset: CanonicalAudioUploadOffset, maxLength: Int) async throws -> Data {
        lock.lock()
        _readCount += 1
        _maxObservedReadLength = max(_maxObservedReadLength, maxLength)
        lock.unlock()

        let start = min(max(0, Int(offset.value)), bytes.count)
        let end = min(bytes.count, start + max(1, maxLength))
        return Data(bytes[start..<end])
    }
}

private enum V849CommitPeerTruth {
    case metadataOnly
    case availableSame
    case unknown
    case different
}

private enum V849CommitSupport {
    static func candidate(
        objectID: String,
        bytes: Data,
        peerTruth kind: V849CommitPeerTruth
    ) -> CanonicalAudioUploadCutoverCandidate {
        let hash = CanonicalTransportEnvelope.hash(bytes)
        let peerTruth: CanonicalAudioUploadPeerTruth
        switch kind {
        case .metadataOnly:
            peerTruth = CanonicalAudioUploadPeerTruth(state: .metadataOnly)
        case .availableSame:
            peerTruth = CanonicalAudioUploadPeerTruth(state: .available, contentHash: hash, byteSize: Int64(bytes.count))
        case .unknown:
            peerTruth = CanonicalAudioUploadPeerTruth(state: .unknown)
        case .different:
            peerTruth = CanonicalAudioUploadPeerTruth(
                state: .different,
                contentHash: CanonicalHash.sha256String("v849-commit-different"),
                byteSize: Int64(bytes.count + 1)
            )
        }
        return CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: objectID,
            localTruth: .available(hash: hash, byteSize: Int64(bytes.count), logicalPathToken: "audio/\(objectID).m4a"),
            peerTruth: peerTruth,
            trigger: .ordinarySync
        )
    }

    static func completedLedgerOnlyCandidate(objectID: String, bytes: Data) -> CanonicalAudioUploadCutoverCandidate {
        let hash = CanonicalTransportEnvelope.hash(bytes)
        return CanonicalAudioUploadCutoverCandidate.evaluate(
            objectID: objectID,
            localTruth: .available(hash: hash, byteSize: Int64(bytes.count), logicalPathToken: "audio/\(objectID).m4a"),
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
