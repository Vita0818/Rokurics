//
//  CanonicalTransferRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalTransferRuntimeMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case diagnosticsOnly
    case noCommit
    case canonicalTransferWithLegacyFallback
    case blocked

    nonisolated var createsTransferJob: Bool {
        self == .canonicalTransferWithLegacyFallback
    }
}

nonisolated struct CanonicalTransferRuntimePolicy: Codable, Equatable, Hashable, Sendable {
    var debugInternalBuild: Bool
    var ownerApprovedCanonicalTransfer: Bool
    var defaultReleaseOldKernel: Bool
    var legacyFallbackEnabled: Bool
    var requireExistingSecureUploadRoutes: Bool
    var retryDrainerRequiresExistingJob: Bool
    var chunkSize: Int
    var retryPolicy: CanonicalTransferRetryRuntimePolicy

    nonisolated init(
        debugInternalBuild: Bool = false,
        ownerApprovedCanonicalTransfer: Bool = false,
        defaultReleaseOldKernel: Bool = true,
        legacyFallbackEnabled: Bool = true,
        requireExistingSecureUploadRoutes: Bool = true,
        retryDrainerRequiresExistingJob: Bool = true,
        chunkSize: Int = 4 * 1024 * 1024,
        retryPolicy: CanonicalTransferRetryRuntimePolicy = CanonicalTransferRetryRuntimePolicy()
    ) {
        self.debugInternalBuild = debugInternalBuild
        self.ownerApprovedCanonicalTransfer = ownerApprovedCanonicalTransfer
        self.defaultReleaseOldKernel = defaultReleaseOldKernel
        self.legacyFallbackEnabled = legacyFallbackEnabled
        self.requireExistingSecureUploadRoutes = requireExistingSecureUploadRoutes
        self.retryDrainerRequiresExistingJob = retryDrainerRequiresExistingJob
        self.chunkSize = max(1, chunkSize)
        self.retryPolicy = retryPolicy
    }

    nonisolated static let releaseDefault = CanonicalTransferRuntimePolicy()
}

nonisolated struct CanonicalTransferRuntimeConfiguration: Codable, Equatable, Hashable, Sendable {
    var mode: CanonicalTransferRuntimeMode
    var policy: CanonicalTransferRuntimePolicy

    nonisolated init(
        mode: CanonicalTransferRuntimeMode = .disabled,
        policy: CanonicalTransferRuntimePolicy = .releaseDefault
    ) {
        self.mode = mode
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalTransferRuntimeConfiguration()
}

nonisolated struct CanonicalTransferSourceChunk: Codable, Equatable, Sendable {
    var offset: Int64
    var bytes: Data
    var chunkHash: CanonicalHash

    nonisolated init(offset: Int64, bytes: Data, chunkHash: CanonicalHash) {
        self.offset = max(0, offset)
        self.bytes = bytes
        self.chunkHash = chunkHash
    }
}

nonisolated protocol CanonicalTransferByteSource: Sendable {
    var objectID: CanonicalObjectID { get }
    var totalBytes: Int64 { get }
    var totalHash: CanonicalHash { get }
    func readChunk(offset: Int64, maxLength: Int) async throws -> CanonicalTransferSourceChunk
}

nonisolated protocol CanonicalTransferRuntimePort: Sendable {
    func start(_ request: CanonicalTransferStartRequest) async throws -> CanonicalTransferSession
    func status(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus
    func sendChunk(_ chunk: CanonicalTransferChunk) async throws -> CanonicalTransferChunkAck
    func finalize(_ request: CanonicalTransferFinalizeRequest) async throws -> CanonicalTransferFinalizeProof
    func abortLocalBeforeFinalize(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus
}

extension CanonicalTransferRuntimePort {
    func abortLocalBeforeFinalize(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        try await status(sessionID: sessionID)
    }
}

nonisolated struct CanonicalTransferPortBridge: CanonicalTransferRuntimePort {
    private let port: any CanonicalTransferPort

    nonisolated init(port: any CanonicalTransferPort) {
        self.port = port
    }

    nonisolated func start(_ request: CanonicalTransferStartRequest) async throws -> CanonicalTransferSession {
        try await port.startTransfer(request)
    }

    nonisolated func status(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        try await port.transferStatus(sessionID: sessionID)
    }

    nonisolated func sendChunk(_ chunk: CanonicalTransferChunk) async throws -> CanonicalTransferChunkAck {
        try await port.sendChunk(chunk)
    }

    nonisolated func finalize(_ request: CanonicalTransferFinalizeRequest) async throws -> CanonicalTransferFinalizeProof {
        try await port.finalizeTransfer(request)
    }

    nonisolated func abortLocalBeforeFinalize(sessionID: CanonicalTransferSessionID) async throws -> CanonicalTransferStatus {
        try await port.abortLocalBeforeFinalize(sessionID: sessionID)
    }
}

nonisolated enum CanonicalTransferRuntimeOutcome: String, Codable, Equatable, Hashable, Sendable {
    case legacyFallback
    case diagnosticsOnly
    case noCommit
    case uploaded
    case retryScheduled
    case conflict
    case blocked
    case failed
}

nonisolated struct CanonicalTransferRuntimeResult: Codable, Equatable, Sendable {
    var mode: CanonicalTransferRuntimeMode
    var outcome: CanonicalTransferRuntimeOutcome
    var objectID: CanonicalObjectID
    var sessionID: CanonicalTransferSessionID?
    var createdJob: Bool
    var sentChunkCount: Int
    var confirmedBytes: Int64
    var finalizeProof: CanonicalTransferFinalizeProof?
    var uiCompletedStatusMutated: Bool
    var diagnostics: [CanonicalTransferDiagnosticRecord]

    nonisolated init(
        mode: CanonicalTransferRuntimeMode,
        outcome: CanonicalTransferRuntimeOutcome,
        objectID: CanonicalObjectID,
        sessionID: CanonicalTransferSessionID? = nil,
        createdJob: Bool = false,
        sentChunkCount: Int = 0,
        confirmedBytes: Int64 = 0,
        finalizeProof: CanonicalTransferFinalizeProof? = nil,
        uiCompletedStatusMutated: Bool = false,
        diagnostics: [CanonicalTransferDiagnosticRecord] = []
    ) {
        self.mode = mode
        self.outcome = outcome
        self.objectID = objectID
        self.sessionID = sessionID
        self.createdJob = createdJob
        self.sentChunkCount = max(0, sentChunkCount)
        self.confirmedBytes = max(0, confirmedBytes)
        self.finalizeProof = finalizeProof
        self.uiCompletedStatusMutated = uiCompletedStatusMutated
        self.diagnostics = diagnostics
    }
}

actor CanonicalTransferRuntime {
    private let configuration: CanonicalTransferRuntimeConfiguration
    private let port: any CanonicalTransferRuntimePort
    private let sourceNodeID: CanonicalNodeID
    private let destinationNodeID: CanonicalNodeID

    init(
        configuration: CanonicalTransferRuntimeConfiguration,
        port: any CanonicalTransferRuntimePort,
        sourceNodeID: CanonicalNodeID,
        destinationNodeID: CanonicalNodeID
    ) {
        self.configuration = configuration
        self.port = port
        self.sourceNodeID = sourceNodeID
        self.destinationNodeID = destinationNodeID
    }

    func transfer(
        source: any CanonicalTransferByteSource,
        requestedAt: CanonicalTimestamp
    ) async throws -> CanonicalTransferRuntimeResult {
        guard configuration.mode.createsTransferJob else {
            return CanonicalTransferRuntimeResult(
                mode: configuration.mode,
                outcome: configuration.mode == .diagnosticsOnly ? .diagnosticsOnly : .legacyFallback,
                objectID: source.objectID,
                diagnostics: [
                    CanonicalTransferDiagnosticRecord(
                        kind: .runtimeBlocked,
                        objectID: source.objectID,
                        redactedDetail: "mode=\(configuration.mode.rawValue),createdJob=false"
                    )
                ]
            )
        }

        let startRequest = CanonicalTransferStartRequest(
            objectID: source.objectID,
            sourceNodeID: sourceNodeID,
            destinationNodeID: destinationNodeID,
            contentHash: source.totalHash,
            byteSize: source.totalBytes,
            preferredChunkSize: configuration.policy.chunkSize,
            requestedAt: requestedAt
        )
        let session = try await port.start(startRequest)
        var machine = CanonicalTransferSessionStateMachine(
            sessionID: session.sessionID,
            objectID: source.objectID,
            expectedByteSize: source.totalBytes,
            expectedContentHash: source.totalHash,
            chunkSize: configuration.policy.chunkSize
        )
        try machine.markStarted(confirmedBytes: session.acceptedOffset)

        var diagnostics: [CanonicalTransferDiagnosticRecord] = [
            CanonicalTransferDiagnosticRecord(
                kind: .startRequested,
                objectID: source.objectID,
                sessionID: session.sessionID,
                confirmedBytes: session.acceptedOffset,
                hashPrefix: source.totalHash.value,
                redactedDetail: "createdJob=true"
            )
        ]
        let refreshedStatus = try await port.status(sessionID: session.sessionID)
        _ = try machine.refreshStatus(confirmedBytes: refreshedStatus.acceptedOffset)
        diagnostics.append(
            CanonicalTransferDiagnosticRecord(
                kind: .statusRefreshed,
                objectID: source.objectID,
                sessionID: session.sessionID,
                confirmedBytes: machine.confirmedBytes,
                hashPrefix: source.totalHash.value,
                redactedDetail: "resumeOffset=\(machine.confirmedBytes)"
            )
        )
        if let existingProof = refreshedStatus.finalizeProof,
           existingProof.isReceiverAcceptedProof {
            _ = try machine.finalize(
                receiverNodeID: existingProof.receiverNodeID,
                byteSize: existingProof.byteSize,
                contentHash: existingProof.contentHash,
                manifestHash: existingProof.manifestHash,
                finalizedAt: existingProof.finalizedAt
            )
            diagnostics.append(CanonicalTransferDiagnostics.finalizeProofAccepted(existingProof))
            return CanonicalTransferRuntimeResult(
                mode: configuration.mode,
                outcome: .uploaded,
                objectID: source.objectID,
                sessionID: session.sessionID,
                createdJob: true,
                sentChunkCount: 0,
                confirmedBytes: machine.confirmedBytes,
                finalizeProof: existingProof,
                uiCompletedStatusMutated: false,
                diagnostics: diagnostics
            )
        }

        var sentChunkCount = 0
        while machine.nextChunkOffset < source.totalBytes {
            let sourceChunk = try await source.readChunk(
                offset: machine.nextChunkOffset,
                maxLength: machine.nextChunkLength
            )
            let chunk = CanonicalTransferChunk(
                sessionID: session.sessionID,
                sequence: CanonicalSequence(UInt64(sentChunkCount)),
                offset: sourceChunk.offset,
                bytes: sourceChunk.bytes,
                chunkHash: sourceChunk.chunkHash
            )
            let ack: CanonicalTransferChunkAck
            do {
                ack = try await port.sendChunk(chunk)
            } catch {
                machine.interrupt(reason: "chunkSendFailedStatusRefresh")
                let refreshed = try await port.status(sessionID: session.sessionID)
                let beforeRefreshOffset = machine.confirmedBytes
                _ = try machine.refreshStatus(confirmedBytes: refreshed.acceptedOffset)
                diagnostics.append(
                    CanonicalTransferDiagnosticRecord(
                        kind: .statusRefreshed,
                        objectID: source.objectID,
                        sessionID: session.sessionID,
                        confirmedBytes: machine.confirmedBytes,
                        hashPrefix: source.totalHash.value,
                        redactedDetail: "resumeAfterChunkError,previousOffset=\(beforeRefreshOffset)"
                    )
                )
                guard machine.confirmedBytes > beforeRefreshOffset else {
                    throw error
                }
                continue
            }
            _ = try machine.acceptChunk(
                offset: sourceChunk.offset,
                length: sourceChunk.bytes.count,
                chunkHash: sourceChunk.chunkHash,
                serverConfirmedBytes: ack.acceptedBytes
            )
            sentChunkCount += 1
            diagnostics.append(
                CanonicalTransferDiagnosticRecord(
                    kind: .chunkAccepted,
                    objectID: source.objectID,
                    sessionID: session.sessionID,
                    confirmedBytes: machine.confirmedBytes,
                    hashPrefix: sourceChunk.chunkHash.value,
                    redactedDetail: "offset=\(sourceChunk.offset),length=\(sourceChunk.bytes.count)"
                )
            )
        }

        let proof = try await port.finalize(
            CanonicalTransferFinalizeRequest(
                sessionID: session.sessionID,
                objectID: source.objectID,
                contentHash: source.totalHash,
                byteSize: source.totalBytes,
                requestedAt: requestedAt
            )
        )
        _ = try machine.finalize(
            receiverNodeID: proof.receiverNodeID,
            byteSize: proof.byteSize,
            contentHash: proof.contentHash,
            manifestHash: proof.manifestHash,
            finalizedAt: proof.finalizedAt
        )

        return CanonicalTransferRuntimeResult(
            mode: configuration.mode,
            outcome: .uploaded,
            objectID: source.objectID,
            sessionID: session.sessionID,
            createdJob: true,
            sentChunkCount: sentChunkCount,
            confirmedBytes: machine.confirmedBytes,
            finalizeProof: proof,
            uiCompletedStatusMutated: false,
            diagnostics: diagnostics + [
                CanonicalTransferDiagnostics.finalizeProofAccepted(proof)
            ]
        )
    }
}
