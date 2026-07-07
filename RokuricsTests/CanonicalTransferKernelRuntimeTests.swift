//
//  CanonicalTransferKernelRuntimeTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/14.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalTransferKernelRuntimeTests {
    @Test func sharedStateMachineEnforcesOffsetIdempotencyResumeAndFinalizeProof() throws {
        var machine = Self.machine(byteSize: 12, hash: Self.hashA, chunkSize: 4)
        machine.beginStart()
        try machine.markStarted()

        let first = try machine.acceptChunk(offset: 0, length: 4, chunkHash: Self.chunkA)
        let duplicate = try machine.acceptChunk(offset: 0, length: 4, chunkHash: Self.chunkA)

        #expect(first == .accepted)
        #expect(duplicate == .duplicateAccepted)
        #expect(machine.confirmedBytes == 4)
        #expect(machine.nextChunkOffset == 4)

        var wrongOffsetRejected = false
        do {
            _ = try machine.acceptChunk(offset: 8, length: 4, chunkHash: Self.chunkB)
        } catch CanonicalTransferStateMachineError.wrongOffsetRequiresStatusRefresh(let expected, let actual) {
            wrongOffsetRejected = true
            #expect(expected == 4)
            #expect(actual == 8)
        }
        #expect(wrongOffsetRejected)
        #expect(machine.state == .interrupted)

        try machine.refreshStatus(confirmedBytes: 4)
        #expect(machine.state == .resuming)
        try machine.acceptChunk(offset: 4, length: 4, chunkHash: Self.chunkB)
        try machine.acceptChunk(offset: 8, length: 4, chunkHash: Self.chunkC)

        let proof = try machine.finalize(
            receiverNodeID: CanonicalNodeID("mac-node"),
            byteSize: 12,
            contentHash: Self.hashA,
            finalizedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 930))
        )

        #expect(machine.state == .finalized)
        #expect(proof.isV930VerifiedFinalizeProof)
        #expect(proof.receiverNodeID == CanonicalNodeID("mac-node"))
        #expect(proof.byteSize == 12)
        #expect(proof.contentHashPrefix == String(Self.hashA.value.prefix(12)))
    }

    @Test func runtimeRefreshesStatusAndResumesAfterWrongOffsetChunkFailure() async throws {
        let source = RuntimeResumeSource(
            objectID: CanonicalObjectID("recording-runtime-resume"),
            totalBytes: 8,
            totalHash: Self.hashA
        )
        let port = RuntimeWrongOffsetThenResumePort(totalBytes: 8, contentHash: Self.hashA)
        let runtime = CanonicalTransferRuntime(
            configuration: CanonicalTransferRuntimeConfiguration(
                mode: .canonicalTransferWithLegacyFallback,
                policy: CanonicalTransferRuntimePolicy(
                    debugInternalBuild: true,
                    ownerApprovedCanonicalTransfer: true,
                    defaultReleaseOldKernel: true,
                    legacyFallbackEnabled: true,
                    requireExistingSecureUploadRoutes: true,
                    retryDrainerRequiresExistingJob: true,
                    chunkSize: 4
                )
            ),
            port: port,
            sourceNodeID: CanonicalNodeID("iphone-node"),
            destinationNodeID: CanonicalNodeID("mac-node")
        )

        let result = try await runtime.transfer(
            source: source,
            requestedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 9_312))
        )

        #expect(result.outcome == .uploaded)
        #expect(result.confirmedBytes == 8)
        #expect(result.finalizeProof?.isReceiverAcceptedProof == true)
        #expect(result.diagnostics.contains { $0.kind == .statusRefreshed && $0.redactedDetail?.contains("resumeAfterChunkError") == true })
        let sendAttemptCount = await port.sendAttemptCount
        #expect(sendAttemptCount == 2)
    }

    @Test func sharedStateMachineRejectsRegressionPartialFinalizeAndHashSizeConflict() throws {
        var monotonic = Self.machine(byteSize: 12, hash: Self.hashA, chunkSize: 4)
        try monotonic.markStarted(confirmedBytes: 8)
        var regressed = false
        do {
            try monotonic.refreshStatus(confirmedBytes: 4)
        } catch CanonicalTransferStateMachineError.confirmedBytesRegressed(let previous, let attempted) {
            regressed = true
            #expect(previous == 8)
            #expect(attempted == 4)
        }
        #expect(regressed)

        var partial = Self.machine(byteSize: 12, hash: Self.hashA, chunkSize: 4)
        try partial.markStarted()
        try partial.acceptChunk(offset: 0, length: 4, chunkHash: Self.chunkA)
        var partialRejected = false
        do {
            _ = try partial.finalize(
                receiverNodeID: CanonicalNodeID("mac-node"),
                byteSize: 12,
                contentHash: Self.hashA,
                finalizedAt: CanonicalTimestamp(Date())
            )
        } catch CanonicalTransferStateMachineError.partialReceiveCannotFinalize(let confirmedBytes, let expectedBytes) {
            partialRejected = true
            #expect(confirmedBytes == 4)
            #expect(expectedBytes == 12)
        }
        #expect(partialRejected)
        #expect(partial.state != .finalized)

        var mismatch = Self.machine(byteSize: 12, hash: Self.hashA, chunkSize: 12, confirmedBytes: 12)
        var sizeConflict = false
        do {
            _ = try mismatch.finalize(
                receiverNodeID: CanonicalNodeID("mac-node"),
                byteSize: 13,
                contentHash: Self.hashA,
                finalizedAt: CanonicalTimestamp(Date())
            )
        } catch CanonicalTransferStateMachineError.finalizeByteSizeMismatch {
            sizeConflict = true
        }
        #expect(sizeConflict)
        #expect(mismatch.state == .conflict)

        mismatch = Self.machine(byteSize: 12, hash: Self.hashA, chunkSize: 12, confirmedBytes: 12)
        var hashConflict = false
        do {
            _ = try mismatch.finalize(
                receiverNodeID: CanonicalNodeID("mac-node"),
                byteSize: 12,
                contentHash: Self.hashB,
                finalizedAt: CanonicalTimestamp(Date())
            )
        } catch CanonicalTransferStateMachineError.finalizeHashMismatch {
            hashConflict = true
        }
        #expect(hashConflict)
        #expect(mismatch.state == .conflict)
    }

    @Test func sharedNoOverwriteRejectsExistingDifferentAudio() throws {
        var same = Self.machine(byteSize: 12, hash: Self.hashA, confirmedBytes: 12)
        let sameDecision = try same.validateNoOverwrite(existingByteSize: 12, existingContentHash: Self.hashA)
        #expect(sameDecision == .sameObjectNoOp)

        var different = Self.machine(byteSize: 12, hash: Self.hashA, confirmedBytes: 12)
        var rejected = false
        do {
            _ = try different.validateNoOverwrite(existingByteSize: 12, existingContentHash: Self.hashB)
        } catch CanonicalTransferStateMachineError.existingDifferentObject {
            rejected = true
        }
        #expect(rejected)
        #expect(different.state == .conflict)
    }

    @Test func retryRuntimeBlocksFreshJobsViewRefreshBackoffAndStorms() {
        let runtime = CanonicalTransferRetryRuntime(
            policy: CanonicalTransferRetryRuntimePolicy(maxAttempts: 2, baseDelaySeconds: 5, maxDelaySeconds: 20)
        )
        let now = Date(timeIntervalSince1970: 1_000)
        let eligible = CanonicalTransferRetryJob(
            objectID: CanonicalObjectID("recording-v930"),
            sessionID: CanonicalTransferSessionID("transfer-v930"),
            state: .chunking,
            confirmedBytes: 4,
            byteSize: 12,
            hashPrefix: String(Self.hashA.value.prefix(12))
        )

        let viewRefresh = runtime.evaluate(trigger: .viewRefresh, job: eligible, now: now, statusRouteAvailable: true)
        let noJob = runtime.evaluate(trigger: .retryDrainer, job: nil, now: now, statusRouteAvailable: true)
        let backoff = runtime.evaluate(
            trigger: .retryDrainer,
            job: CanonicalTransferRetryJob(
                objectID: eligible.objectID,
                sessionID: eligible.sessionID,
                state: .chunking,
                confirmedBytes: 4,
                byteSize: 12,
                hashPrefix: eligible.hashPrefix,
                nextRetryAfter: CanonicalTimestamp(now.addingTimeInterval(60))
            ),
            now: now,
            statusRouteAvailable: true
        )
        let exhausted = runtime.evaluate(
            trigger: .retryDrainer,
            job: CanonicalTransferRetryJob(
                objectID: eligible.objectID,
                sessionID: eligible.sessionID,
                state: .chunking,
                confirmedBytes: 4,
                byteSize: 12,
                hashPrefix: eligible.hashPrefix,
                attemptCount: 2,
                maxAttempts: 2
            ),
            now: now,
            statusRouteAvailable: true
        )
        let interrupted = runtime.evaluate(
            trigger: .retryDrainer,
            job: CanonicalTransferRetryJob(
                objectID: eligible.objectID,
                sessionID: eligible.sessionID,
                state: .interrupted,
                confirmedBytes: 4,
                byteSize: 12,
                hashPrefix: eligible.hashPrefix
            ),
            now: now,
            statusRouteAvailable: true
        )

        #expect(viewRefresh.createdFreshJob == false)
        #expect(viewRefresh.blockers.contains(.viewRefreshCannotCreateJob))
        #expect(noJob.decision == .noExistingEligibleJob)
        #expect(noJob.createdFreshJob == false)
        #expect(backoff.blockers.contains(.backoffActive))
        #expect(exhausted.blockers.contains(.maxAttemptsReached))
        #expect(interrupted.decision == .refreshStatusBeforeResume)
        #expect(interrupted.requiresStatusRefresh)
    }

    @Test func retryRuntimeBlocksUnsafeTruthStates() {
        let runtime = CanonicalTransferRetryRuntime()
        let blockedReasons: [CanonicalTransferRetryBlocker] = [
            .peerUnknown,
            .missingLocalAudio,
            .tombstone,
            .conflict,
            .security,
            .malformedLedger
        ]

        for blocker in blockedReasons {
            let result = runtime.evaluate(
                trigger: .retryDrainer,
                job: CanonicalTransferRetryJob(
                    objectID: CanonicalObjectID("recording-v930-\(blocker.rawValue)"),
                    sessionID: CanonicalTransferSessionID("transfer-v930-\(blocker.rawValue)"),
                    state: .chunking,
                    confirmedBytes: 0,
                    byteSize: 12,
                    hashPrefix: String(Self.hashA.value.prefix(12)),
                    blockers: [blocker]
                ),
                now: Date(timeIntervalSince1970: 1_000),
                statusRouteAvailable: true
            )
            #expect(result.decision == .blocked)
            #expect(result.blockers.contains(blocker))
            #expect(result.createdFreshJob == false)
        }
    }

    @Test func diagnosticsRedactFullHashPathBodyAndAudioBytes() {
        let fullHash = String(repeating: "a", count: 64)
        let record = CanonicalTransferDiagnosticRecord(
            kind: .finalizeProofRejected,
            objectID: CanonicalObjectID("recording-v930"),
            hashPrefix: fullHash,
            redactedDetail: "path=/Users/example/audio.m4a request body \(fullHash) raw audio bytes"
        )

        #expect(record.hashPrefix == String(fullHash.prefix(12)))
        #expect(record.redactedDetail?.contains(fullHash) == false)
        #expect(record.redactedDetail?.contains("/Users/example") == false)
        #expect(record.redactedDetail?.contains("request body") == false)
        #expect(record.redactedDetail?.contains("raw audio bytes") == false)
        #expect(record.forbiddenSignals.isEmpty)
    }

    @Test func readinessRequiresAllV930TransferEvidenceAndUnsafeGuards() {
        let ready = CanonicalTransferKernelReadiness.v930(
            CanonicalTransferKernelReadinessEvidence(
                stateMachineReady: true,
                finalizeProofReady: true,
                adapterReady: true,
                retryBackoffReady: true,
                idempotencyReady: true,
                noRouteChange: true,
                securityUnchanged: true,
                diagnosticsRedacted: true,
                defaultReleaseOldKernel: true,
                legacyFallbackPreserved: true,
                uploadRouteSchemaUnchanged: true,
                transferDoesNotSetUIComplete: true,
                completedLedgerAloneRejectedAsProof: true,
                partialReceiveRejectedAsProof: true
            )
        )
        let unsafe = CanonicalTransferKernelReadiness.v930(
            CanonicalTransferKernelReadinessEvidence(
                stateMachineReady: true,
                finalizeProofReady: true,
                adapterReady: true,
                retryBackoffReady: true,
                idempotencyReady: true,
                noRouteChange: false,
                securityUnchanged: true,
                diagnosticsRedacted: true,
                defaultReleaseOldKernel: true,
                legacyFallbackPreserved: true,
                uploadRouteSchemaUnchanged: true,
                transferDoesNotSetUIComplete: true,
                completedLedgerAloneRejectedAsProof: true,
                partialReceiveRejectedAsProof: true
            )
        )

        #expect(ready.readyForV930TransferKernelRuntime)
        #expect(unsafe.status == .unsafeToProceed)
        #expect(unsafe.blockers.contains(.routeChanged))
    }

    @Test func iPhoneAdapterUsesExistingSecureUploadClientAndSharedRuntimeIsPortable() throws {
        let adapter = try sourceText("Rokurics/IPhoneCanonicalTransferAdapter.swift")
        let secureClient = try sourceText("Rokurics/SecureMacUploadClient.swift")
        let sharedRuntime = try sourceText("RokuricsShared/SyncCore/CanonicalTransferRuntime.swift")

        #expect(adapter.contains("IPhoneCanonicalSecureAudioUploadPort"))
        #expect(adapter.contains("RecordingSecureUploadTransport"))
        #expect(adapter.contains("SecureMacUploadClient"))
        #expect(adapter.contains("\"/upload-recording-audio-session/abort\"") == false)
        #expect(secureClient.contains("startResumableAudioUpload"))
        #expect(secureClient.contains("fetchResumableAudioUploadStatus"))
        #expect(secureClient.contains("uploadResumableAudioChunk"))
        #expect(secureClient.contains("finalizeResumableAudioUpload"))
        #expect(sharedRuntime.contains("URLSession") == false)
        #expect(sharedRuntime.contains("Network.framework") == false)
    }

    @Test func canonicalKernelSwitchMapsConnectionAndTransferOwnersConservatively() {
        let old = CanonicalKernelSwitchConfiguration.oldKernel.resolve()
        let decisionOnly = CanonicalKernelSwitchConfiguration(
            mode: .canonicalDecisionOnly,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        let applyNoAudio = CanonicalKernelSwitchConfiguration(
            mode: .canonicalApplyNoAudio,
            policy: .debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        let blockedFullSync = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy.debugInternal(manualFullSyncConfirmation: true)
        ).resolve()
        let missingOwner = CanonicalKernelSwitchConfiguration(
            mode: .canonicalFullSync,
            policy: CanonicalKernelSwitchPolicy(
                debugInternalBuild: true,
                ownerApproved: true,
                releaseDefaultBuild: false,
                manualFullSyncConfirmation: true,
                connectionRuntimeReady: false,
                transferRuntimeReady: false
            )
        ).resolve()

        #expect(old.effectiveConfiguration.connectionRuntimeConfiguration.mode == .disabled)
        #expect(old.effectiveConfiguration.transferRuntimeConfiguration.mode == .disabled)
        #expect(decisionOnly.effectiveConfiguration.connectionRuntimeConfiguration.mode == .diagnosticsOnly)
        #expect(decisionOnly.effectiveConfiguration.transferRuntimeConfiguration.mode == .noCommit)
        #expect(applyNoAudio.effectiveConfiguration.connectionRuntimeConfiguration.mode == .diagnosticsOnly)
        #expect(applyNoAudio.effectiveConfiguration.transferRuntimeConfiguration.mode == .blocked)
        #expect(blockedFullSync.effectiveMode == .canonicalFullSync)
        #expect(blockedFullSync.effectiveConfiguration.connectionRuntimeConfiguration.mode == .connectionOwnerWithLegacyFallback)
        #expect(blockedFullSync.effectiveConfiguration.transferRuntimeConfiguration.mode == .canonicalTransferWithLegacyFallback)
        #expect(missingOwner.effectiveMode == .blocked)
        #expect(missingOwner.blockers.contains(.connectionRuntimeReadinessMissing))
        #expect(missingOwner.blockers.contains(.transferRuntimeReadinessMissing))
    }

    @Test func recordingUploadCoordinatorEntersCanonicalTransferRuntimeInFullSync() throws {
        let coordinator = try sourceText("Rokurics/RecordingUploadCoordinator.swift")
        let adapter = try sourceText("Rokurics/IPhoneCanonicalTransferAdapter.swift")

        #expect(coordinator.contains("uploadViaCanonicalTransferRuntimeIfEnabled"))
        #expect(coordinator.contains("CanonicalTransferRuntime("))
        #expect(coordinator.contains("IPhoneCanonicalTransferAdapter"))
        #expect(coordinator.contains("CanonicalTransferRetryRuntime"))
        #expect(coordinator.contains("produceCanonicalTransferFinalizeProofFact"))
        #expect(coordinator.contains("triggerSource.isViewRefreshOnly"))
        #expect(adapter.contains("IPhoneCanonicalSecureAudioUploadPort"))
        #expect(adapter.contains("SecureMacUploadClient"))
    }

    private static func machine(
        byteSize: Int64,
        hash: CanonicalHash,
        chunkSize: Int = 4,
        confirmedBytes: Int64 = 0
    ) -> CanonicalTransferSessionStateMachine {
        CanonicalTransferSessionStateMachine(
            sessionID: CanonicalTransferSessionID("transfer-v930"),
            objectID: CanonicalObjectID("recording-v930"),
            expectedByteSize: byteSize,
            expectedContentHash: hash,
            chunkSize: chunkSize,
            confirmedBytes: confirmedBytes
        )
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
    private static let chunkB = CanonicalHash(String(repeating: "2", count: 64))
    private static let chunkC = CanonicalHash(String(repeating: "3", count: 64))
}

private struct RuntimeResumeSource: CanonicalTransferByteSource {
    var objectID: CanonicalObjectID
    var totalBytes: Int64
    var totalHash: CanonicalHash

    func readChunk(offset: Int64, maxLength: Int) async throws -> CanonicalTransferSourceChunk {
        let length = Int(min(Int64(maxLength), totalBytes - offset))
        return CanonicalTransferSourceChunk(
            offset: offset,
            bytes: Data(repeating: UInt8(offset / 4), count: length),
            chunkHash: CanonicalHash(String(repeating: String((offset / 4) + 1), count: 64))
        )
    }
}

private actor RuntimeWrongOffsetThenResumePort: CanonicalTransferRuntimePort {
    private let sessionID = CanonicalTransferSessionID("runtime-resume-session")
    private let totalBytes: Int64
    private let contentHash: CanonicalHash
    private var acceptedOffset: Int64 = 0
    private var didThrowWrongOffset = false
    private(set) var sendAttemptCount = 0

    init(totalBytes: Int64, contentHash: CanonicalHash) {
        self.totalBytes = totalBytes
        self.contentHash = contentHash
    }

    func start(_ request: CanonicalTransferStartRequest) async throws -> CanonicalTransferSession {
        CanonicalTransferSession(
            sessionID: sessionID,
            request: request,
            state: .started,
            acceptedOffset: acceptedOffset,
            createdAt: request.requestedAt,
            updatedAt: request.requestedAt
        )
    }

    func status(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        CanonicalTransferStatus(
            sessionID: sessionID,
            objectID: CanonicalObjectID("recording-runtime-resume"),
            state: acceptedOffset >= totalBytes ? .finalizing : .chunking,
            acceptedOffset: acceptedOffset,
            totalBytes: totalBytes
        )
    }

    func sendChunk(_ chunk: CanonicalTransferChunk) async throws -> CanonicalTransferChunkAck {
        sendAttemptCount += 1
        if !didThrowWrongOffset {
            didThrowWrongOffset = true
            acceptedOffset = Int64(chunk.bytes.count)
            throw CanonicalTransferStateMachineError.wrongOffsetRequiresStatusRefresh(
                expected: 0,
                actual: chunk.offset
            )
        }
        acceptedOffset = min(totalBytes, chunk.offset + Int64(chunk.bytes.count))
        return CanonicalTransferChunkAck(
            sessionID: chunk.sessionID,
            sequence: chunk.sequence,
            acceptedOffset: chunk.offset,
            acceptedBytes: acceptedOffset,
            acknowledgedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 9_313))
        )
    }

    func finalize(_ request: CanonicalTransferFinalizeRequest) async throws -> CanonicalTransferFinalizeProof {
        CanonicalTransferFinalizeProof.v930(
            receiverNodeID: CanonicalNodeID("mac-node"),
            sessionID: request.sessionID,
            objectID: request.objectID,
            byteSize: request.byteSize,
            contentHash: contentHash,
            finalizedAt: CanonicalTimestamp(Date(timeIntervalSince1970: 9_314)),
            verified: acceptedOffset == totalBytes
        )
    }

    func abortLocalBeforeFinalize(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        CanonicalTransferStatus(
            sessionID: sessionID,
            objectID: CanonicalObjectID("recording-runtime-resume"),
            state: .aborted,
            acceptedOffset: acceptedOffset,
            totalBytes: totalBytes
        )
    }
}
