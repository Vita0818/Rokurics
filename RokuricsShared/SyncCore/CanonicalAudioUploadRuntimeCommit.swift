//
//  CanonicalAudioUploadRuntimeCommit.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/7.
//

import Foundation

nonisolated enum CanonicalAudioUploadRuntimeMode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case disabled
    case diagnosticsOnly
    case noCommit
    case testTransportUpload
    case canonicalUploadWithLegacyFallback
    case blocked

    nonisolated var createsJob: Bool {
        switch self {
        case .testTransportUpload, .canonicalUploadWithLegacyFallback:
            return true
        case .disabled, .diagnosticsOnly, .noCommit, .blocked:
            return false
        }
    }

    nonisolated var sendsNetworkOrTransport: Bool {
        switch self {
        case .testTransportUpload, .canonicalUploadWithLegacyFallback:
            return true
        case .disabled, .diagnosticsOnly, .noCommit, .blocked:
            return false
        }
    }
}

nonisolated struct CanonicalAudioUploadRuntimePolicy: Codable, Equatable, Sendable {
    var debugInternalBuild: Bool
    var ownerApprovedCanonicalCommit: Bool
    var allowTestTransportUpload: Bool
    var allowCanonicalUploadWithLegacyFallback: Bool
    var legacyFallbackEnabled: Bool
    var requireExistingSecureUploadRoutes: Bool
    var retryDrainerRequiresExistingRetry: Bool
    var chunkSize: Int
    var retryPolicy: CanonicalAudioUploadRetryPolicy

    nonisolated init(
        debugInternalBuild: Bool = false,
        ownerApprovedCanonicalCommit: Bool = false,
        allowTestTransportUpload: Bool = false,
        allowCanonicalUploadWithLegacyFallback: Bool = false,
        legacyFallbackEnabled: Bool = true,
        requireExistingSecureUploadRoutes: Bool = true,
        retryDrainerRequiresExistingRetry: Bool = true,
        chunkSize: Int = 4 * 1024 * 1024,
        retryPolicy: CanonicalAudioUploadRetryPolicy = CanonicalAudioUploadRetryPolicy()
    ) {
        self.debugInternalBuild = debugInternalBuild
        self.ownerApprovedCanonicalCommit = ownerApprovedCanonicalCommit
        self.allowTestTransportUpload = allowTestTransportUpload
        self.allowCanonicalUploadWithLegacyFallback = allowCanonicalUploadWithLegacyFallback
        self.legacyFallbackEnabled = legacyFallbackEnabled
        self.requireExistingSecureUploadRoutes = requireExistingSecureUploadRoutes
        self.retryDrainerRequiresExistingRetry = retryDrainerRequiresExistingRetry
        self.chunkSize = max(1, chunkSize)
        self.retryPolicy = retryPolicy
    }

    nonisolated static let releaseDefault = CanonicalAudioUploadRuntimePolicy()

    nonisolated static func testTransport(
        chunkSize: Int = 4 * 1024 * 1024,
        retryPolicy: CanonicalAudioUploadRetryPolicy = CanonicalAudioUploadRetryPolicy()
    ) -> CanonicalAudioUploadRuntimePolicy {
        CanonicalAudioUploadRuntimePolicy(
            debugInternalBuild: true,
            ownerApprovedCanonicalCommit: true,
            allowTestTransportUpload: true,
            allowCanonicalUploadWithLegacyFallback: false,
            legacyFallbackEnabled: true,
            requireExistingSecureUploadRoutes: true,
            chunkSize: chunkSize,
            retryPolicy: retryPolicy
        )
    }
}

nonisolated struct CanonicalAudioUploadRuntimeConfiguration: Codable, Equatable, Sendable {
    var mode: CanonicalAudioUploadRuntimeMode
    var policy: CanonicalAudioUploadRuntimePolicy

    nonisolated init(
        mode: CanonicalAudioUploadRuntimeMode = .disabled,
        policy: CanonicalAudioUploadRuntimePolicy = .releaseDefault
    ) {
        self.mode = mode
        self.policy = policy
    }

    nonisolated static let disabled = CanonicalAudioUploadRuntimeConfiguration()

    nonisolated static func diagnosticsOnly(
        policy: CanonicalAudioUploadRuntimePolicy = .releaseDefault
    ) -> CanonicalAudioUploadRuntimeConfiguration {
        CanonicalAudioUploadRuntimeConfiguration(mode: .diagnosticsOnly, policy: policy)
    }

    nonisolated static func noCommit(
        policy: CanonicalAudioUploadRuntimePolicy = .releaseDefault
    ) -> CanonicalAudioUploadRuntimeConfiguration {
        CanonicalAudioUploadRuntimeConfiguration(mode: .noCommit, policy: policy)
    }

    nonisolated static func testTransportUpload(
        chunkSize: Int = 4 * 1024 * 1024,
        retryPolicy: CanonicalAudioUploadRetryPolicy = CanonicalAudioUploadRetryPolicy()
    ) -> CanonicalAudioUploadRuntimeConfiguration {
        CanonicalAudioUploadRuntimeConfiguration(
            mode: .testTransportUpload,
            policy: .testTransport(chunkSize: chunkSize, retryPolicy: retryPolicy)
        )
    }
}

nonisolated enum CanonicalAudioUploadRuntimeOutcome: String, Codable, Equatable, Hashable, Sendable {
    case legacyFallback
    case diagnosticsOnly
    case noCommit
    case noOp
    case deferred
    case uploaded
    case retryScheduled
    case conflict
    case blocked
    case failed
}

nonisolated struct CanonicalAudioUploadRuntimeResult: Codable, Equatable, Sendable {
    var mode: CanonicalAudioUploadRuntimeMode
    var outcome: CanonicalAudioUploadRuntimeOutcome
    var objectID: String
    var sessionID: CanonicalUploadSessionID?
    var createdJob: Bool
    var startedTransport: Bool
    var sentChunkCount: Int
    var confirmedBytes: Int64
    var completed: Bool
    var usedLegacyFallback: Bool
    var legacyFallbackReason: String?
    var finalizeProof: CanonicalAudioUploadFinalizeProof?
    var retryRecord: CanonicalAudioUploadRetryRecord?
    var diagnostics: [CanonicalAudioUploadDiagnostic]

    nonisolated init(
        mode: CanonicalAudioUploadRuntimeMode,
        outcome: CanonicalAudioUploadRuntimeOutcome,
        objectID: String,
        sessionID: CanonicalUploadSessionID? = nil,
        createdJob: Bool = false,
        startedTransport: Bool = false,
        sentChunkCount: Int = 0,
        confirmedBytes: Int64 = 0,
        completed: Bool = false,
        usedLegacyFallback: Bool = false,
        legacyFallbackReason: String? = nil,
        finalizeProof: CanonicalAudioUploadFinalizeProof? = nil,
        retryRecord: CanonicalAudioUploadRetryRecord? = nil,
        diagnostics: [CanonicalAudioUploadDiagnostic] = []
    ) {
        self.mode = mode
        self.outcome = outcome
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.createdJob = createdJob
        self.startedTransport = startedTransport
        self.sentChunkCount = sentChunkCount
        self.confirmedBytes = max(0, confirmedBytes)
        self.completed = completed
        self.usedLegacyFallback = usedLegacyFallback
        self.legacyFallbackReason = CanonicalAudioUploadRuntimeRedaction.safeText(legacyFallbackReason)
        self.finalizeProof = finalizeProof
        self.retryRecord = retryRecord
        self.diagnostics = diagnostics
    }
}

typealias CanonicalAudioUploadSessionID = CanonicalUploadSessionID

nonisolated struct CanonicalAudioUploadChunkID: Codable, Equatable, Hashable, Sendable {
    var rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(
            rawValue,
            fallback: "audio-upload-chunk:unknown"
        )
    }
}

nonisolated enum CanonicalAudioUploadRuntimeBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case runtimeDisabled
    case runtimeBlocked
    case diagnosticsOnly
    case noCommit
    case releaseDefaultDisabled
    case debugInternalRequired
    case ownerApprovalRequired
    case existingSecureRoutesRequired
    case resumableSessionUnsupported
    case realSecureUploadPortRequired
    case peerUnknown
    case localAudioMissing
    case completedLedgerNotAudioProof
    case metadataOnlyNotAudioAvailable
    case existingDifferentAudio
    case retryDrainerFreshJobSuppressed
    case viewRefreshSuppressed
    case finalProofMissing
    case finalHashMismatch
    case finalByteSizeMismatch
    case securityFailure
    case networkFailure
    case unsupported
}

nonisolated enum CanonicalAudioUploadCommitResultState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case noOpSameAudio
    case deferredPeerUnknown
    case blockedConflict
    case blockedMissingLocalAudio
    case started
    case resumed
    case finalized
    case failedNetwork
    case failedVerification
    case failedSecurity
    case legacyFallbackUsed
    case blockedUnsupported
    case blockedPolicy
}

nonisolated struct CanonicalAudioUploadCommitRequest: Codable, Equatable, Sendable {
    var candidate: CanonicalAudioUploadCutoverCandidate
    var configuration: CanonicalAudioUploadRuntimeConfiguration
    var syncRunID: String?
    var nodeRole: CanonicalAudioUploadNodeRole

    nonisolated init(
        candidate: CanonicalAudioUploadCutoverCandidate,
        configuration: CanonicalAudioUploadRuntimeConfiguration,
        syncRunID: String? = nil,
        nodeRole: CanonicalAudioUploadNodeRole = .iPhone
    ) {
        self.candidate = candidate
        self.configuration = configuration
        self.syncRunID = CanonicalAudioUploadRuntimeRedaction.safeText(syncRunID)
        self.nodeRole = nodeRole
    }
}

nonisolated struct CanonicalAudioUploadCommitPostcondition: Codable, Equatable, Sendable {
    var finalizeProofAccepted: Bool
    var macFileSizeVerified: Bool
    var macHashVerified: Bool
    var receiveRecordMatchesAudioAvailability: Bool
    var uploadLedgerCompletedAfterProof: Bool
    var legacyDuplicateSuppressedAfterProof: Bool

    nonisolated init(
        finalizeProof: CanonicalAudioUploadFinalizeProof?,
        uploadLedgerCompletedAfterProof: Bool,
        legacyDuplicateSuppressedAfterProof: Bool
    ) {
        self.finalizeProofAccepted = finalizeProof?.accepted == true
        self.macFileSizeVerified = finalizeProof?.macFileSizeVerified == true
        self.macHashVerified = finalizeProof?.macHashVerified == true
        self.receiveRecordMatchesAudioAvailability = finalizeProof?.receiveRecordMatchesAudioAvailability == true
        self.uploadLedgerCompletedAfterProof = uploadLedgerCompletedAfterProof && finalizeProof?.accepted == true
        self.legacyDuplicateSuppressedAfterProof = legacyDuplicateSuppressedAfterProof && finalizeProof?.accepted == true
    }
}

nonisolated struct CanonicalAudioUploadLegacyFallbackDecision: Codable, Equatable, Sendable {
    var legacyFallbackAvailable: Bool
    var legacyFallbackUsed: Bool
    var suppressLegacyDuplicate: Bool
    var reason: String?

    nonisolated init(
        legacyFallbackAvailable: Bool,
        legacyFallbackUsed: Bool,
        suppressLegacyDuplicate: Bool,
        reason: String? = nil
    ) {
        self.legacyFallbackAvailable = legacyFallbackAvailable
        self.legacyFallbackUsed = legacyFallbackUsed
        self.suppressLegacyDuplicate = suppressLegacyDuplicate
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason)
    }
}

nonisolated struct CanonicalAudioUploadCommitResult: Codable, Equatable, Sendable {
    var state: CanonicalAudioUploadCommitResultState
    var runtimeResult: CanonicalAudioUploadRuntimeResult
    var postcondition: CanonicalAudioUploadCommitPostcondition
    var legacyFallbackDecision: CanonicalAudioUploadLegacyFallbackDecision
    var blockers: [CanonicalAudioUploadRuntimeBlocker]

    nonisolated init(
        runtimeResult: CanonicalAudioUploadRuntimeResult,
        legacyFallbackAvailable: Bool = true
    ) {
        self.runtimeResult = runtimeResult
        self.state = runtimeResult.commitResultState
        self.postcondition = CanonicalAudioUploadCommitPostcondition(
            finalizeProof: runtimeResult.finalizeProof,
            uploadLedgerCompletedAfterProof: runtimeResult.completed,
            legacyDuplicateSuppressedAfterProof: runtimeResult.outcome == .uploaded
        )
        self.legacyFallbackDecision = CanonicalAudioUploadLegacyFallbackDecision(
            legacyFallbackAvailable: legacyFallbackAvailable,
            legacyFallbackUsed: runtimeResult.usedLegacyFallback,
            suppressLegacyDuplicate: runtimeResult.outcome == .uploaded || runtimeResult.outcome == .noOp,
            reason: runtimeResult.legacyFallbackReason
        )
        self.blockers = runtimeResult.runtimeBlockers
    }
}

nonisolated struct CanonicalAudioUploadFailure: Codable, Equatable, Sendable {
    var objectID: String
    var state: CanonicalAudioUploadCommitResultState
    var retryable: Bool
    var conflict: Bool
    var reason: String?

    nonisolated init(
        objectID: String,
        state: CanonicalAudioUploadCommitResultState,
        retryable: Bool,
        conflict: Bool,
        reason: String? = nil
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.state = state
        self.retryable = retryable
        self.conflict = conflict
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason)
    }
}

nonisolated struct CanonicalAudioUploadOffset: Codable, Equatable, Comparable, Hashable, Sendable {
    var value: Int64

    nonisolated init(_ value: Int64 = 0) {
        self.value = max(0, value)
    }

    nonisolated static func < (left: CanonicalAudioUploadOffset, right: CanonicalAudioUploadOffset) -> Bool {
        left.value < right.value
    }
}

nonisolated enum CanonicalAudioUploadSessionState: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case idle
    case starting
    case started
    case chunking
    case interrupted
    case resuming
    case finalizing
    case finalized
    case failed
    case aborted
    case conflict
    case blocked

    nonisolated var isTerminal: Bool {
        switch self {
        case .finalized, .failed, .aborted, .conflict, .blocked:
            return true
        case .idle, .starting, .started, .chunking, .interrupted, .resuming, .finalizing:
            return false
        }
    }
}

nonisolated struct CanonicalAudioUploadChunk: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID
    var offset: CanonicalAudioUploadOffset
    var length: Int
    var chunkHashPrefix: String?
    var idempotencyKey: String

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID,
        offset: CanonicalAudioUploadOffset,
        length: Int,
        chunkHash: CanonicalHash? = nil,
        idempotencyKey: String? = nil
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.offset = offset
        self.length = max(0, length)
        self.chunkHashPrefix = chunkHash.flatMap { CanonicalAudioUploadRuntimeRedaction.hashPrefix($0.value) }
        self.idempotencyKey = idempotencyKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "\(self.objectID):\(sessionID.rawValue):\(offset.value):\(self.length)"
    }

    nonisolated var endOffset: Int64 {
        offset.value + Int64(length)
    }
}

nonisolated struct CanonicalAudioUploadFinalizeProof: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID
    var byteSize: Int64
    var contentHashPrefix: String?
    var macFileSizeVerified: Bool
    var macHashVerified: Bool
    var macProofReceived: Bool
    var receiveRecordMatchesAudioAvailability: Bool

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID,
        byteSize: Int64,
        contentHash: CanonicalHash?,
        macFileSizeVerified: Bool,
        macHashVerified: Bool,
        macProofReceived: Bool,
        receiveRecordMatchesAudioAvailability: Bool
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.byteSize = max(0, byteSize)
        self.contentHashPrefix = contentHash.flatMap { CanonicalAudioUploadRuntimeRedaction.hashPrefix($0.value) }
        self.macFileSizeVerified = macFileSizeVerified
        self.macHashVerified = macHashVerified
        self.macProofReceived = macProofReceived
        self.receiveRecordMatchesAudioAvailability = receiveRecordMatchesAudioAvailability
    }

    nonisolated var accepted: Bool {
        macFileSizeVerified && macHashVerified && macProofReceived && receiveRecordMatchesAudioAvailability
    }
}

nonisolated struct CanonicalAudioUploadAbort: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID?
    var reason: String
    var preFinalizeOnly: Bool
    var productionAudioDeleted: Bool
    var receiveRecordDeleted: Bool

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID?,
        reason: String,
        preFinalizeOnly: Bool = true,
        productionAudioDeleted: Bool = false,
        receiveRecordDeleted: Bool = false
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.reason = CanonicalAudioUploadRuntimeRedaction.safeText(reason) ?? "abort"
        self.preFinalizeOnly = preFinalizeOnly
        self.productionAudioDeleted = productionAudioDeleted
        self.receiveRecordDeleted = receiveRecordDeleted
    }
}

nonisolated struct CanonicalAudioUploadResumeToken: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID
    var offset: CanonicalAudioUploadOffset
    var byteSize: Int64
    var contentHashPrefix: String?

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID,
        offset: CanonicalAudioUploadOffset,
        byteSize: Int64,
        contentHashPrefix: String?
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.offset = offset
        self.byteSize = max(0, byteSize)
        self.contentHashPrefix = CanonicalAudioUploadRuntimeRedaction.hashPrefix(contentHashPrefix)
    }
}

nonisolated struct CanonicalAudioUploadRetryPolicy: Codable, Equatable, Sendable {
    var maxAttempts: Int
    var retryDelaySeconds: TimeInterval

    nonisolated init(maxAttempts: Int = 3, retryDelaySeconds: TimeInterval = 5) {
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelaySeconds = max(0, retryDelaySeconds)
    }
}

nonisolated struct CanonicalAudioUploadRetryRecord: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID?
    var offset: CanonicalAudioUploadOffset
    var chunkSize: Int
    var contentHashPrefix: String?
    var byteSize: Int64
    var state: CanonicalAudioUploadSessionState
    var attemptCount: Int
    var nextRetryAt: CanonicalTimestamp?
    var lastErrorCode: String?
    var terminalConflict: Bool
    var updatedAt: CanonicalTimestamp

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID? = nil,
        offset: CanonicalAudioUploadOffset = CanonicalAudioUploadOffset(),
        chunkSize: Int,
        contentHash: CanonicalHash? = nil,
        contentHashPrefix: String? = nil,
        byteSize: Int64,
        state: CanonicalAudioUploadSessionState,
        attemptCount: Int = 0,
        nextRetryAt: CanonicalTimestamp? = nil,
        lastErrorCode: String? = nil,
        terminalConflict: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.offset = offset
        self.chunkSize = max(1, chunkSize)
        self.contentHashPrefix = contentHash.flatMap { CanonicalAudioUploadRuntimeRedaction.hashPrefix($0.value) }
            ?? CanonicalAudioUploadRuntimeRedaction.hashPrefix(contentHashPrefix)
        self.byteSize = max(0, byteSize)
        self.state = state
        self.attemptCount = max(0, attemptCount)
        self.nextRetryAt = nextRetryAt
        self.lastErrorCode = CanonicalAudioUploadRuntimeRedaction.safeText(lastErrorCode)
        self.terminalConflict = terminalConflict
        self.updatedAt = CanonicalTimestamp(updatedAt)
    }

    nonisolated var resumeToken: CanonicalAudioUploadResumeToken? {
        guard let sessionID else {
            return nil
        }
        return CanonicalAudioUploadResumeToken(
            objectID: objectID,
            sessionID: sessionID,
            offset: offset,
            byteSize: byteSize,
            contentHashPrefix: contentHashPrefix
        )
    }

    nonisolated func isEligibleRetry(now: Date) -> Bool {
        guard !terminalConflict, !state.isTerminal || state == .interrupted else {
            return false
        }
        if state == .conflict || state == .blocked || state == .aborted || state == .finalized || state == .failed {
            return false
        }
        guard let nextRetryAt else {
            return state == .interrupted
        }
        return nextRetryAt.date <= now
    }
}

nonisolated struct CanonicalAudioUploadSession: Codable, Equatable, Sendable {
    var objectID: String
    var sessionID: CanonicalUploadSessionID?
    var state: CanonicalAudioUploadSessionState
    var confirmedBytes: Int64
    var offset: CanonicalAudioUploadOffset
    var chunkSize: Int
    var expectedByteSize: Int64
    var contentHashPrefix: String?
    var finalizedProof: CanonicalAudioUploadFinalizeProof?
    var lastErrorCode: String?

    nonisolated init(
        objectID: String,
        sessionID: CanonicalUploadSessionID? = nil,
        state: CanonicalAudioUploadSessionState = .idle,
        confirmedBytes: Int64 = 0,
        chunkSize: Int,
        expectedByteSize: Int64,
        contentHash: CanonicalHash? = nil,
        contentHashPrefix: String? = nil
    ) {
        self.objectID = CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")
        self.sessionID = sessionID
        self.state = state
        self.confirmedBytes = max(0, confirmedBytes)
        self.offset = CanonicalAudioUploadOffset(confirmedBytes)
        self.chunkSize = max(1, chunkSize)
        self.expectedByteSize = max(0, expectedByteSize)
        self.contentHashPrefix = contentHash.flatMap { CanonicalAudioUploadRuntimeRedaction.hashPrefix($0.value) }
            ?? CanonicalAudioUploadRuntimeRedaction.hashPrefix(contentHashPrefix)
        self.finalizedProof = nil
        self.lastErrorCode = nil
    }

    nonisolated mutating func markStarted(sessionID: CanonicalUploadSessionID, confirmedBytes: Int64 = 0) throws {
        self.sessionID = sessionID
        state = .started
        try updateConfirmedBytes(confirmedBytes)
    }

    nonisolated mutating func updateConfirmedBytes(_ newConfirmedBytes: Int64) throws {
        let bounded = min(max(0, newConfirmedBytes), expectedByteSize)
        guard bounded >= confirmedBytes else {
            throw CanonicalAudioUploadRuntimeError.confirmedBytesRegressed(previous: confirmedBytes, actual: bounded)
        }
        confirmedBytes = bounded
        offset = CanonicalAudioUploadOffset(bounded)
    }

    nonisolated mutating func confirm(_ chunk: CanonicalAudioUploadChunk, serverConfirmedBytes: Int64) throws {
        guard chunk.objectID == objectID else {
            throw CanonicalAudioUploadRuntimeError.sessionConflict("objectMismatch")
        }
        if chunk.offset.value < confirmedBytes {
            guard chunk.endOffset <= confirmedBytes else {
                throw CanonicalAudioUploadRuntimeError.chunkOffsetMismatch(expected: confirmedBytes, actual: chunk.offset.value)
            }
            return
        }
        guard chunk.offset.value == confirmedBytes else {
            throw CanonicalAudioUploadRuntimeError.chunkOffsetMismatch(expected: confirmedBytes, actual: chunk.offset.value)
        }
        guard chunk.endOffset <= expectedByteSize else {
            throw CanonicalAudioUploadRuntimeError.chunkOffsetMismatch(expected: expectedByteSize, actual: chunk.endOffset)
        }
        state = .chunking
        try updateConfirmedBytes(max(serverConfirmedBytes, chunk.endOffset))
    }

    nonisolated mutating func markFinalized(_ proof: CanonicalAudioUploadFinalizeProof) throws {
        guard proof.accepted else {
            state = .conflict
            lastErrorCode = "finalizeProofRejected"
            throw CanonicalAudioUploadRuntimeError.finalizeProofRejected("finalizeProofRejected")
        }
        guard proof.byteSize == expectedByteSize else {
            state = .conflict
            lastErrorCode = "finalByteSizeMismatch"
            throw CanonicalAudioUploadRuntimeError.finalByteSizeMismatch(expected: expectedByteSize, actual: proof.byteSize)
        }
        finalizedProof = proof
        state = .finalized
        confirmedBytes = expectedByteSize
        offset = CanonicalAudioUploadOffset(expectedByteSize)
        lastErrorCode = nil
    }
}

nonisolated enum CanonicalAudioUploadRuntimeError: Error, Equatable, Sendable {
    case modeBlocked(String)
    case missingSource(String)
    case localAudioIncomplete(String)
    case peerUnknownDeferred(String)
    case conflictBlocked(String)
    case retryDrainerFreshJobSuppressed(String)
    case completedLedgerRejectedAsNoOp(String)
    case confirmedBytesRegressed(previous: Int64, actual: Int64)
    case chunkOffsetMismatch(expected: Int64, actual: Int64)
    case chunkReadReturnedEmpty(offset: Int64)
    case sessionConflict(String)
    case finalizeProofRejected(String)
    case finalByteSizeMismatch(expected: Int64, actual: Int64)
    case finalHashMismatch(expectedPrefix: String?, actualPrefix: String?)
}

nonisolated protocol CanonicalAudioUploadByteSource: Sendable {
    var objectID: String { get }
    var targetReference: CanonicalFileReference { get }
    var byteSize: Int64 { get }
    var contentHash: CanonicalHash { get }
    var preferredChunkSize: Int { get }

    func readChunk(offset: CanonicalAudioUploadOffset, maxLength: Int) async throws -> Data
}

actor CanonicalAudioUploadJobStore {
    private struct Ledger: Codable, Sendable {
        var schemaVersion: Int
        var records: [CanonicalAudioUploadRetryRecord]
    }

    private let persistenceURL: URL?
    private var records: [String: CanonicalAudioUploadRetryRecord]

    init(persistenceURL: URL? = nil, initialRecords: [CanonicalAudioUploadRetryRecord] = []) {
        self.persistenceURL = persistenceURL
        records = Dictionary(uniqueKeysWithValues: initialRecords.map { ($0.objectID, $0) })
        if let persistenceURL,
           let data = try? Data(contentsOf: persistenceURL),
           let ledger = try? JSONDecoder().decode(Ledger.self, from: data) {
            records = Dictionary(uniqueKeysWithValues: ledger.records.map { ($0.objectID, $0) })
        }
    }

    func record(for objectID: String) -> CanonicalAudioUploadRetryRecord? {
        records[CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording")]
    }

    func allRecords() -> [CanonicalAudioUploadRetryRecord] {
        records.values.sorted { $0.objectID < $1.objectID }
    }

    func upsert(_ record: CanonicalAudioUploadRetryRecord) async throws -> CanonicalAudioUploadRetryRecord {
        records[record.objectID] = record
        try persist()
        return record
    }

    func remove(objectID: String) async throws {
        records.removeValue(forKey: CanonicalAudioUploadRuntimeRedaction.safeIdentifier(objectID, fallback: "unknown-recording"))
        try persist()
    }

    func hasEligibleRetry(objectID: String, now: Date) -> Bool {
        record(for: objectID)?.isEligibleRetry(now: now) == true
    }

    func eligibleRetryRecords(now: Date) -> [CanonicalAudioUploadRetryRecord] {
        records.values
            .filter { $0.isEligibleRetry(now: now) }
            .sorted { $0.objectID < $1.objectID }
    }

    @discardableResult
    func recordProgress(
        objectID: String,
        sessionID: CanonicalUploadSessionID?,
        offset: CanonicalAudioUploadOffset,
        chunkSize: Int,
        contentHash: CanonicalHash,
        byteSize: Int64,
        state: CanonicalAudioUploadSessionState,
        now: Date
    ) async throws -> CanonicalAudioUploadRetryRecord {
        let existing = record(for: objectID)
        let monotonicOffset = CanonicalAudioUploadOffset(max(existing?.offset.value ?? 0, offset.value))
        let record = CanonicalAudioUploadRetryRecord(
            objectID: objectID,
            sessionID: sessionID,
            offset: monotonicOffset,
            chunkSize: chunkSize,
            contentHash: contentHash,
            byteSize: byteSize,
            state: state,
            attemptCount: existing?.attemptCount ?? 0,
            nextRetryAt: existing?.nextRetryAt,
            lastErrorCode: existing?.lastErrorCode,
            terminalConflict: existing?.terminalConflict ?? false,
            updatedAt: now
        )
        return try await upsert(record)
    }

    @discardableResult
    func scheduleRetry(
        objectID: String,
        sessionID: CanonicalUploadSessionID?,
        offset: CanonicalAudioUploadOffset,
        chunkSize: Int,
        contentHash: CanonicalHash,
        byteSize: Int64,
        policy: CanonicalAudioUploadRetryPolicy,
        errorCode: String,
        now: Date
    ) async throws -> CanonicalAudioUploadRetryRecord {
        let existing = record(for: objectID)
        let nextAttempt = (existing?.attemptCount ?? 0) + 1
        let state: CanonicalAudioUploadSessionState = nextAttempt >= policy.maxAttempts ? .failed : .interrupted
        let nextRetryAt = state == .failed ? nil : CanonicalTimestamp(now.addingTimeInterval(policy.retryDelaySeconds))
        let retry = CanonicalAudioUploadRetryRecord(
            objectID: objectID,
            sessionID: sessionID,
            offset: CanonicalAudioUploadOffset(max(existing?.offset.value ?? 0, offset.value)),
            chunkSize: chunkSize,
            contentHash: contentHash,
            byteSize: byteSize,
            state: state,
            attemptCount: nextAttempt,
            nextRetryAt: nextRetryAt,
            lastErrorCode: errorCode,
            terminalConflict: false,
            updatedAt: now
        )
        return try await upsert(retry)
    }

    @discardableResult
    func markConflict(
        objectID: String,
        sessionID: CanonicalUploadSessionID?,
        offset: CanonicalAudioUploadOffset,
        chunkSize: Int,
        contentHash: CanonicalHash,
        byteSize: Int64,
        errorCode: String,
        now: Date
    ) async throws -> CanonicalAudioUploadRetryRecord {
        let existing = record(for: objectID)
        let conflict = CanonicalAudioUploadRetryRecord(
            objectID: objectID,
            sessionID: sessionID,
            offset: CanonicalAudioUploadOffset(max(existing?.offset.value ?? 0, offset.value)),
            chunkSize: chunkSize,
            contentHash: contentHash,
            byteSize: byteSize,
            state: .conflict,
            attemptCount: existing?.attemptCount ?? 0,
            nextRetryAt: nil,
            lastErrorCode: errorCode,
            terminalConflict: true,
            updatedAt: now
        )
        return try await upsert(conflict)
    }

    private func persist() throws {
        guard let persistenceURL else {
            return
        }
        let directory = persistenceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let ledger = Ledger(schemaVersion: 1, records: records.values.sorted { $0.objectID < $1.objectID })
        let data = try encoder.encode(ledger)
        try data.write(to: persistenceURL, options: [.atomic])
    }
}

struct CanonicalAudioUploadRuntimeExecutor: Sendable {
    init() {}

    func execute(
        candidate: CanonicalAudioUploadCutoverCandidate,
        source: any CanonicalAudioUploadByteSource,
        uploadPort: any CanonicalProductionUploadPort,
        jobStore: CanonicalAudioUploadJobStore,
        configuration: CanonicalAudioUploadRuntimeConfiguration = .disabled,
        syncRunID: String? = nil,
        nodeRole: CanonicalAudioUploadNodeRole = .iPhone,
        now: Date = Date()
    ) async -> CanonicalAudioUploadRuntimeResult {
        var diagnostics = candidateDiagnostics(
            candidate: candidate,
            kind: .canonicalAudioUploadRuntimeModeEvaluated,
            syncRunID: syncRunID,
            nodeRole: nodeRole,
            result: configuration.mode.rawValue,
            reason: "defaultReleaseDisabledUnlessExplicitlyEnabled"
        )

        let mode = configuration.mode
        let policy = configuration.policy

        guard mode != .disabled else {
            diagnostics.append(legacyFallbackDiagnostic(candidate: candidate, syncRunID: syncRunID, nodeRole: nodeRole, reason: "runtimeDisabled"))
            return CanonicalAudioUploadRuntimeResult(
                mode: mode,
                outcome: .legacyFallback,
                objectID: candidate.objectID,
                usedLegacyFallback: policy.legacyFallbackEnabled,
                legacyFallbackReason: "runtimeDisabled",
                diagnostics: diagnostics
            )
        }

        guard mode != .blocked else {
            return blockedResult(
                mode: mode,
                candidate: candidate,
                diagnostics: diagnostics,
                reason: "runtimeBlocked"
            )
        }

        let decision = await candidateDecision(
            candidate: candidate,
            jobStore: jobStore,
            policy: policy,
            now: now
        )
        diagnostics.append(contentsOf: decision.diagnostics.map {
            candidateDiagnostics(candidate: candidate, kind: $0, syncRunID: syncRunID, nodeRole: nodeRole).first!
        })

        switch decision.action {
        case .noOp:
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeSameAudioNoOp,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "noOp",
                    reason: "sameHashAndByteSize"
                )[0]
            )
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeReportBuilt,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "noOpSameAudio",
                    reason: "sameHashAndByteSize"
                )[0]
            )
            return CanonicalAudioUploadRuntimeResult(
                mode: mode,
                outcome: .noOp,
                objectID: candidate.objectID,
                confirmedBytes: candidate.localTruth.byteSize ?? 0,
                completed: true,
                diagnostics: diagnostics
            )
        case .deferred:
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeReportBuilt,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "deferredPeerUnknown",
                    reason: "peerUnknown"
                )[0]
            )
            return CanonicalAudioUploadRuntimeResult(
                mode: mode,
                outcome: .deferred,
                objectID: candidate.objectID,
                diagnostics: diagnostics
            )
        case .conflict:
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeDidNotOverwriteExistingAudio,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "blocked",
                    reason: "existingDifferentAudio"
                )[0]
            )
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeReportBuilt,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "blockedConflict",
                    reason: "existingDifferentAudio"
                )[0]
            )
            return CanonicalAudioUploadRuntimeResult(
                mode: mode,
                outcome: .conflict,
                objectID: candidate.objectID,
                diagnostics: diagnostics
            )
        case .blocked(let reason):
            if shouldUseLegacyFallback(mode: mode, policy: policy, reason: reason) {
                diagnostics.append(legacyFallbackDiagnostic(candidate: candidate, syncRunID: syncRunID, nodeRole: nodeRole, reason: reason))
                return CanonicalAudioUploadRuntimeResult(
                    mode: mode,
                    outcome: .legacyFallback,
                    objectID: candidate.objectID,
                    usedLegacyFallback: true,
                    legacyFallbackReason: reason,
                    diagnostics: diagnostics
                )
            }
            return blockedResult(mode: mode, candidate: candidate, diagnostics: diagnostics, reason: reason)
        case .upload:
            break
        }

        guard mode != .diagnosticsOnly else {
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeCandidateSelected,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "wouldUpload",
                    reason: candidate.reason
                )[0]
            )
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeReportBuilt,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "diagnosticsOnly",
                    reason: "noJobNoNetwork"
                )[0]
            )
            return CanonicalAudioUploadRuntimeResult(
                mode: mode,
                outcome: .diagnosticsOnly,
                objectID: candidate.objectID,
                diagnostics: diagnostics
            )
        }

        guard mode != .noCommit else {
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeCandidateSelected,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "noCommitWouldUpload",
                    reason: candidate.reason
                )[0]
            )
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeReportBuilt,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "noCommit",
                    reason: "noJobNoNetwork"
                )[0]
            )
            return CanonicalAudioUploadRuntimeResult(
                mode: mode,
                outcome: .noCommit,
                objectID: candidate.objectID,
                diagnostics: diagnostics
            )
        }

        guard let modeBlocker = modeBlocker(mode: mode, policy: policy, uploadPort: uploadPort) else {
            return await performUpload(
                candidate: candidate,
                source: source,
                uploadPort: uploadPort,
                jobStore: jobStore,
                configuration: configuration,
                diagnostics: diagnostics,
                syncRunID: syncRunID,
                nodeRole: nodeRole,
                now: now
            )
        }

        if shouldUseLegacyFallback(mode: mode, policy: policy, reason: modeBlocker) {
            diagnostics.append(legacyFallbackDiagnostic(candidate: candidate, syncRunID: syncRunID, nodeRole: nodeRole, reason: modeBlocker))
            return CanonicalAudioUploadRuntimeResult(
                mode: mode,
                outcome: .legacyFallback,
                objectID: candidate.objectID,
                usedLegacyFallback: true,
                legacyFallbackReason: modeBlocker,
                diagnostics: diagnostics
            )
        }
        return blockedResult(mode: mode, candidate: candidate, diagnostics: diagnostics, reason: modeBlocker)
    }

    private func performUpload(
        candidate: CanonicalAudioUploadCutoverCandidate,
        source: any CanonicalAudioUploadByteSource,
        uploadPort: any CanonicalProductionUploadPort,
        jobStore: CanonicalAudioUploadJobStore,
        configuration: CanonicalAudioUploadRuntimeConfiguration,
        diagnostics: [CanonicalAudioUploadDiagnostic],
        syncRunID: String?,
        nodeRole: CanonicalAudioUploadNodeRole,
        now: Date
    ) async -> CanonicalAudioUploadRuntimeResult {
        var diagnostics = diagnostics
        let policy = configuration.policy
        let chunkSize = min(
            max(1, source.preferredChunkSize),
            max(1, uploadPort.chunkSizePolicy),
            max(1, policy.chunkSize)
        )
        var sentChunkCount = 0
        var createdJob = false
        var startedTransport = false

        guard source.objectID == candidate.objectID else {
            return blockedResult(
                mode: configuration.mode,
                candidate: candidate,
                diagnostics: diagnostics,
                reason: "sourceObjectMismatch"
            )
        }
        guard source.byteSize > 0 else {
            return blockedResult(
                mode: configuration.mode,
                candidate: candidate,
                diagnostics: diagnostics,
                reason: "localAudioByteSizeUnavailable"
            )
        }

        do {
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeCandidateSelected,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "upload",
                    reason: candidate.reason
                )[0]
            )

            var existingRecord = await jobStore.record(for: candidate.objectID)
            var session = CanonicalAudioUploadSession(
                objectID: candidate.objectID,
                sessionID: existingRecord?.sessionID,
                state: existingRecord?.sessionID == nil ? .idle : .interrupted,
                confirmedBytes: existingRecord?.offset.value ?? 0,
                chunkSize: chunkSize,
                expectedByteSize: source.byteSize,
                contentHash: source.contentHash
            )

            if candidate.trigger.isRetryDrainer,
               existingRecord?.isEligibleRetry(now: now) != true {
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRetryDrainerFreshJobSuppressed,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "blocked",
                        reason: "retryDrainerCannotCreateFreshAudioUploadJob"
                    )[0]
                )
                return blockedResult(
                    mode: configuration.mode,
                    candidate: candidate,
                    diagnostics: diagnostics,
                    reason: "retryDrainerCannotCreateFreshAudioUploadJob"
                )
            }

            let status: CanonicalUploadSessionStatus
            if let resumeToken = existingRecord?.resumeToken {
                session.state = .resuming
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeResumeStarted,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "status",
                        reason: "staleSessionStatusRefresh"
                    )[0]
                )
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeSessionResumed,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "status",
                        reason: "serverConfirmedOffset"
                    )[0]
                )
                status = try await uploadPort.resumeUpload(
                    CanonicalUploadStatusRequest(
                        objectID: candidate.objectID,
                        sessionID: resumeToken.sessionID,
                        totalHash: source.contentHash
                    ),
                    now: now
                )
            } else {
                session.state = .starting
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeStarted,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "start",
                        reason: "existingSecureRoute:/upload-recording-audio-session/start"
                    )[0]
                )
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeSessionStarted,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "start",
                        reason: "serverSessionCreatedOrAccepted"
                    )[0]
                )
                status = try await uploadPort.startResumableUpload(
                    CanonicalUploadStartRequest(
                        objectID: candidate.objectID,
                        targetReference: source.targetReference,
                        totalBytes: source.byteSize,
                        totalHash: source.contentHash,
                        chunkSize: chunkSize,
                        idempotencyKey: "audio-start:\(candidate.objectID):\(String(source.contentHash.value.prefix(12)))"
                    ),
                    now: now
                )
                createdJob = true
                startedTransport = true
            }

            guard let sessionID = status.sessionID ?? session.sessionID else {
                throw CanonicalAudioUploadRuntimeError.sessionConflict("missingSessionID")
            }
            guard status.confirmedBytes >= session.confirmedBytes else {
                throw CanonicalAudioUploadRuntimeError.confirmedBytesRegressed(
                    previous: session.confirmedBytes,
                    actual: status.confirmedBytes
                )
            }
            try session.markStarted(sessionID: sessionID, confirmedBytes: status.confirmedBytes)
            existingRecord = try await jobStore.recordProgress(
                objectID: candidate.objectID,
                sessionID: sessionID,
                offset: session.offset,
                chunkSize: chunkSize,
                contentHash: source.contentHash,
                byteSize: source.byteSize,
                state: session.state,
                now: now
            )

            while session.confirmedBytes < source.byteSize {
                let remaining = source.byteSize - session.confirmedBytes
                let readLength = min(chunkSize, Int(remaining))
                let data = try await source.readChunk(offset: session.offset, maxLength: readLength)
                guard !data.isEmpty else {
                    throw CanonicalAudioUploadRuntimeError.chunkReadReturnedEmpty(offset: session.offset.value)
                }
                let chunkHash = CanonicalTransportEnvelope.hash(data)
                let runtimeChunk = CanonicalAudioUploadChunk(
                    objectID: candidate.objectID,
                    sessionID: sessionID,
                    offset: session.offset,
                    length: data.count,
                    chunkHash: chunkHash
                )
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeChunkSent,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "offset:\(runtimeChunk.offset.value)",
                        reason: "existingSecureRoute:/upload-recording-audio-session/chunk"
                    )[0]
                )
                let chunkStatus = try await uploadPort.uploadChunk(
                    CanonicalUploadChunk(
                        objectID: candidate.objectID,
                        sessionID: sessionID,
                        offset: session.offset.value,
                        bytes: data,
                        chunkHash: chunkHash,
                        totalHash: source.contentHash,
                        idempotencyKey: runtimeChunk.idempotencyKey
                    ),
                    now: now
                )
                startedTransport = true
                sentChunkCount += 1
                if chunkStatus.disposition == .acceptedExisting {
                    diagnostics.append(
                        candidateDiagnostics(
                            candidate: candidate,
                            kind: .canonicalAudioUploadRuntimeDuplicateChunkAccepted,
                            syncRunID: syncRunID,
                            nodeRole: nodeRole,
                            result: "acceptedExisting",
                            reason: "sameOffsetLengthHash"
                        )[0]
                    )
                }
                try session.confirm(runtimeChunk, serverConfirmedBytes: chunkStatus.confirmedBytes)
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeChunkConfirmed,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "confirmed:\(session.confirmedBytes)",
                        reason: "monotonicConfirmedBytes"
                    )[0]
                )
                existingRecord = try await jobStore.recordProgress(
                    objectID: candidate.objectID,
                    sessionID: sessionID,
                    offset: session.offset,
                    chunkSize: chunkSize,
                    contentHash: source.contentHash,
                    byteSize: source.byteSize,
                    state: .chunking,
                    now: now
                )
            }

            session.state = .finalizing
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeFinalizeStarted,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "finalize",
                    reason: "existingSecureRoute:/upload-recording-audio-session/finalize"
                )[0]
            )
            _ = try await jobStore.recordProgress(
                objectID: candidate.objectID,
                sessionID: sessionID,
                offset: session.offset,
                chunkSize: chunkSize,
                contentHash: source.contentHash,
                byteSize: source.byteSize,
                state: .finalizing,
                now: now
            )
            let finalize = try await uploadPort.finalizeUpload(
                CanonicalUploadFinalizeRequest(
                    objectID: candidate.objectID,
                    sessionID: sessionID,
                    totalBytes: source.byteSize,
                    totalHash: source.contentHash
                ),
                now: now
            )
            let actualFileSize = finalize.fileSize ?? -1
            guard finalize.completed,
                  actualFileSize == source.byteSize else {
                throw CanonicalAudioUploadRuntimeError.finalByteSizeMismatch(expected: source.byteSize, actual: actualFileSize)
            }
            let actualChecksum = finalize.checksum
            guard actualChecksum == source.contentHash else {
                throw CanonicalAudioUploadRuntimeError.finalHashMismatch(
                    expectedPrefix: CanonicalAudioUploadRuntimeRedaction.hashPrefix(source.contentHash.value),
                    actualPrefix: actualChecksum.flatMap { CanonicalAudioUploadRuntimeRedaction.hashPrefix($0.value) }
                )
            }
            let proof = CanonicalAudioUploadFinalizeProof(
                objectID: candidate.objectID,
                sessionID: sessionID,
                byteSize: source.byteSize,
                contentHash: source.contentHash,
                macFileSizeVerified: true,
                macHashVerified: true,
                macProofReceived: true,
                receiveRecordMatchesAudioAvailability: finalize.completed
            )
            try session.markFinalized(proof)
            _ = try await uploadPort.writeUploadLedger(
                CanonicalProductionUploadLedgerSnapshot(
                    objectID: candidate.objectID,
                    sessionID: sessionID,
                    confirmedBytes: source.byteSize,
                    totalBytes: source.byteSize,
                    contentHash: source.contentHash,
                    phase: .completed
                )
            )
            let finalizedRecord = try await jobStore.recordProgress(
                objectID: candidate.objectID,
                sessionID: sessionID,
                offset: CanonicalAudioUploadOffset(source.byteSize),
                chunkSize: chunkSize,
                contentHash: source.contentHash,
                byteSize: source.byteSize,
                state: .finalized,
                now: now
            )
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeFinalizeCompleted,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "verified",
                    reason: "hashAndByteSizeVerified"
                )[0]
            )
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeReportBuilt,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "finalized",
                    reason: "finalizeProofAccepted"
                )[0]
            )
            return CanonicalAudioUploadRuntimeResult(
                mode: configuration.mode,
                outcome: .uploaded,
                objectID: candidate.objectID,
                sessionID: sessionID,
                createdJob: createdJob,
                startedTransport: startedTransport,
                sentChunkCount: sentChunkCount,
                confirmedBytes: source.byteSize,
                completed: true,
                finalizeProof: proof,
                retryRecord: finalizedRecord,
                diagnostics: diagnostics
            )
        } catch {
            let sessionID = await jobStore.record(for: candidate.objectID)?.sessionID
            let offset = await jobStore.record(for: candidate.objectID)?.offset ?? CanonicalAudioUploadOffset()
            let code = Self.errorCode(error)
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeFinalizeFailed,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "failed",
                    reason: code
                )[0]
            )
            if Self.isWrongOffset(error) {
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeWrongOffsetDetected,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "resumeRequired",
                        reason: code
                    )[0]
                )
            }
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeDidNotMarkCompletedWithoutProof,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: "notCompleted",
                    reason: code
                )[0]
            )
            if Self.isConflict(error) {
                let conflict = try? await jobStore.markConflict(
                    objectID: candidate.objectID,
                    sessionID: sessionID,
                    offset: offset,
                    chunkSize: chunkSize,
                    contentHash: source.contentHash,
                    byteSize: source.byteSize,
                    errorCode: code,
                    now: now
                )
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeConflictBlocked,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "blocked",
                        reason: code
                    )[0]
                )
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeDidNotOverwriteExistingAudio,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "blocked",
                        reason: code
                    )[0]
                )
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeReportBuilt,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "blockedConflict",
                        reason: code
                    )[0]
                )
                return CanonicalAudioUploadRuntimeResult(
                    mode: configuration.mode,
                    outcome: .conflict,
                    objectID: candidate.objectID,
                    sessionID: sessionID,
                    createdJob: createdJob,
                    startedTransport: startedTransport,
                    sentChunkCount: sentChunkCount,
                    confirmedBytes: offset.value,
                    retryRecord: conflict,
                    diagnostics: diagnostics
                )
            }
            let retry = try? await jobStore.scheduleRetry(
                objectID: candidate.objectID,
                sessionID: sessionID,
                offset: offset,
                chunkSize: chunkSize,
                contentHash: source.contentHash,
                byteSize: source.byteSize,
                policy: policy.retryPolicy,
                errorCode: code,
                now: now
            )
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeRetryScheduled,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: retry?.state.rawValue ?? "failed",
                    reason: code
                )[0]
            )
            if retry?.state == .failed {
                diagnostics.append(
                    candidateDiagnostics(
                        candidate: candidate,
                        kind: .canonicalAudioUploadRuntimeRetryExhausted,
                        syncRunID: syncRunID,
                        nodeRole: nodeRole,
                        result: "failed",
                        reason: code
                    )[0]
                )
            }
            if policy.legacyFallbackEnabled {
                diagnostics.append(legacyFallbackDiagnostic(candidate: candidate, syncRunID: syncRunID, nodeRole: nodeRole, reason: code))
            }
            diagnostics.append(
                candidateDiagnostics(
                    candidate: candidate,
                    kind: .canonicalAudioUploadRuntimeReportBuilt,
                    syncRunID: syncRunID,
                    nodeRole: nodeRole,
                    result: retry?.state == .failed ? "failedNetwork" : "retryScheduled",
                    reason: code
                )[0]
            )
            return CanonicalAudioUploadRuntimeResult(
                mode: configuration.mode,
                outcome: retry?.state == .failed ? .failed : .retryScheduled,
                objectID: candidate.objectID,
                sessionID: sessionID,
                createdJob: createdJob,
                startedTransport: startedTransport,
                sentChunkCount: sentChunkCount,
                confirmedBytes: retry?.offset.value ?? offset.value,
                usedLegacyFallback: policy.legacyFallbackEnabled,
                legacyFallbackReason: policy.legacyFallbackEnabled ? code : nil,
                retryRecord: retry,
                diagnostics: diagnostics
            )
        }
    }

    private enum CandidateDecision: Equatable {
        case noOp
        case deferred
        case conflict
        case blocked(String)
        case upload
    }

    private struct CandidateDecisionResult: Equatable {
        var action: CandidateDecision
        var diagnostics: [CanonicalAudioUploadDiagnosticKind]
    }

    private func candidateDecision(
        candidate: CanonicalAudioUploadCutoverCandidate,
        jobStore: CanonicalAudioUploadJobStore,
        policy: CanonicalAudioUploadRuntimePolicy,
        now: Date
    ) async -> CandidateDecisionResult {
        var diagnostics: [CanonicalAudioUploadDiagnosticKind] = []

        if candidate.trigger.isViewRefresh {
            diagnostics.append(.canonicalAudioUploadViewRefreshSuppressed)
            return CandidateDecisionResult(action: .blocked("viewRefreshNeverCreatesAudioUploadCandidate"), diagnostics: diagnostics)
        }
        if candidate.trigger.isRetryDrainer {
            let storeHasRetry = await jobStore.hasEligibleRetry(objectID: candidate.objectID, now: now)
            if policy.retryDrainerRequiresExistingRetry,
               !candidate.retryTruth.hasExistingEligibleRetry,
               !storeHasRetry {
                diagnostics.append(.canonicalAudioUploadRetryDrainerFreshJobSuppressed)
                return CandidateDecisionResult(action: .blocked("retryDrainerCannotCreateFreshAudioUploadJob"), diagnostics: diagnostics)
            }
        }
        if candidate.evidenceBlockers.contains(.completedLedgerWithoutPeerMatch) {
            diagnostics.append(.canonicalAudioUploadRuntimeCompletedLedgerRejectedAsNoOp)
        }
        if candidate.actionKind == .audioUploadNoOp {
            diagnostics.append(.canonicalAudioUploadRuntimeSameAudioNoOp)
            return CandidateDecisionResult(action: .noOp, diagnostics: diagnostics)
        }
        if candidate.actionKind == .audioUploadDeferredPeerUnknown || candidate.evidenceBlockers.contains(.peerUnknown) {
            diagnostics.append(.canonicalAudioUploadRuntimePeerUnknownDeferred)
            return CandidateDecisionResult(action: .deferred, diagnostics: diagnostics)
        }
        if candidate.actionKind == .audioUploadConflictRecord || candidate.evidenceStatus == .conflict {
            diagnostics.append(.canonicalAudioUploadRuntimeExistingDifferentAudioBlocked)
            diagnostics.append(.canonicalAudioUploadRuntimeConflictBlocked)
            diagnostics.append(.canonicalAudioUploadRuntimeDidNotOverwriteExistingAudio)
            return CandidateDecisionResult(action: .conflict, diagnostics: diagnostics)
        }
        if candidate.evidenceStatus == .blocked, !candidate.evidenceBlockers.isEmpty {
            diagnostics.append(.canonicalAudioUploadRuntimeCandidateBlocked)
            return CandidateDecisionResult(action: .blocked(candidate.evidenceBlockers.map(\.rawValue).joined(separator: ",")), diagnostics: diagnostics)
        }
        guard candidate.actionKind == .audioUploadCanaryCandidate,
              candidate.evidenceStatus == .complete,
              candidate.localTruth.sufficientForUploadCandidate else {
            diagnostics.append(.canonicalAudioUploadRuntimeCandidateBlocked)
            return CandidateDecisionResult(action: .blocked(candidate.reason), diagnostics: diagnostics)
        }
        if candidate.peerTruth.state == .metadataOnly {
            diagnostics.append(.canonicalAudioUploadRuntimePeerMetadataOnlyCandidate)
        }
        return CandidateDecisionResult(action: .upload, diagnostics: diagnostics)
    }

    private func modeBlocker(
        mode: CanonicalAudioUploadRuntimeMode,
        policy: CanonicalAudioUploadRuntimePolicy,
        uploadPort: any CanonicalProductionUploadPort
    ) -> String? {
        guard policy.requireExistingSecureUploadRoutes else {
            return "existingSecureUploadRoutesRequired"
        }
        guard uploadPort.resumableSessionSupported else {
            return "resumableSessionUnsupported"
        }
        switch mode {
        case .testTransportUpload:
            return policy.allowTestTransportUpload ? nil : "testTransportUploadNotAllowed"
        case .canonicalUploadWithLegacyFallback:
            guard policy.debugInternalBuild else {
                return "canonicalUploadRequiresDebugInternalBuild"
            }
            guard policy.ownerApprovedCanonicalCommit else {
                return "canonicalUploadOwnerApprovalMissing"
            }
            guard policy.allowCanonicalUploadWithLegacyFallback else {
                return "canonicalUploadPolicyDisabled"
            }
            guard !uploadPort.isDryRunOnly else {
                return "canonicalUploadRequiresRealSecureUploadPort"
            }
            return nil
        case .disabled, .diagnosticsOnly, .noCommit, .blocked:
            return nil
        }
    }

    private func shouldUseLegacyFallback(
        mode: CanonicalAudioUploadRuntimeMode,
        policy: CanonicalAudioUploadRuntimePolicy,
        reason: String
    ) -> Bool {
        guard policy.legacyFallbackEnabled else {
            return false
        }
        if mode == .canonicalUploadWithLegacyFallback {
            return true
        }
        if reason.contains("manualUploadButton") {
            return true
        }
        return mode == .disabled
    }

    private func blockedResult(
        mode: CanonicalAudioUploadRuntimeMode,
        candidate: CanonicalAudioUploadCutoverCandidate,
        diagnostics: [CanonicalAudioUploadDiagnostic],
        reason: String
    ) -> CanonicalAudioUploadRuntimeResult {
        var appended = diagnostics
        appended.append(contentsOf: candidateDiagnostics(
            candidate: candidate,
            kind: .canonicalAudioUploadRuntimeCandidateBlocked,
            result: "blocked",
            reason: reason
        ))
        appended.append(contentsOf: candidateDiagnostics(
            candidate: candidate,
            kind: .canonicalAudioUploadRuntimeDidNotMarkCompletedWithoutProof,
            result: "notCompleted",
            reason: "finalizeProofMissing"
        ))
        appended.append(contentsOf: candidateDiagnostics(
            candidate: candidate,
            kind: .canonicalAudioUploadRuntimeReportBuilt,
            result: "blocked",
            reason: reason
        ))
        return CanonicalAudioUploadRuntimeResult(
            mode: mode,
            outcome: .blocked,
            objectID: candidate.objectID,
            diagnostics: appended + candidateDiagnostics(
                candidate: candidate,
                kind: .canonicalAudioUploadRuntimeConflictBlocked,
                result: "blocked",
                reason: reason
            )
        )
    }

    private func legacyFallbackDiagnostic(
        candidate: CanonicalAudioUploadCutoverCandidate,
        syncRunID: String?,
        nodeRole: CanonicalAudioUploadNodeRole,
        reason: String
    ) -> CanonicalAudioUploadDiagnostic {
        CanonicalAudioUploadDiagnostic(
            kind: .canonicalAudioUploadRuntimeLegacyFallbackUsed,
            syncRunID: syncRunID,
            trigger: candidate.trigger,
            nodeRole: nodeRole,
            objectID: candidate.objectID,
            peerState: candidate.peerTruth.state,
            ledgerPhase: candidate.ledgerTruth.phase,
            action: candidate.actionKind,
            result: "legacyFallback",
            reason: reason,
            hashPrefix: candidate.hashPrefix
        )
    }

    private func candidateDiagnostics(
        candidate: CanonicalAudioUploadCutoverCandidate,
        kind: CanonicalAudioUploadDiagnosticKind,
        syncRunID: String? = nil,
        nodeRole: CanonicalAudioUploadNodeRole = .iPhone,
        result: String? = nil,
        reason: String? = nil
    ) -> [CanonicalAudioUploadDiagnostic] {
        [
            CanonicalAudioUploadDiagnostic(
                kind: kind,
                syncRunID: syncRunID,
                trigger: candidate.trigger,
                nodeRole: nodeRole,
                objectID: candidate.objectID,
                peerState: candidate.peerTruth.state,
                ledgerPhase: candidate.ledgerTruth.phase,
                action: candidate.actionKind,
                result: result,
                reason: reason,
                hashPrefix: candidate.hashPrefix
            )
        ]
    }

    private static func isConflict(_ error: Error) -> Bool {
        if let runtimeError = error as? CanonicalAudioUploadRuntimeError {
            switch runtimeError {
            case .conflictBlocked, .completedLedgerRejectedAsNoOp, .sessionConflict, .finalizeProofRejected, .finalByteSizeMismatch, .finalHashMismatch:
                return true
            case .modeBlocked, .missingSource, .localAudioIncomplete, .peerUnknownDeferred, .retryDrainerFreshJobSuppressed, .confirmedBytesRegressed, .chunkOffsetMismatch, .chunkReadReturnedEmpty:
                return false
            }
        }
        if let uploadError = error as? CanonicalUploadRuntimeError {
            switch uploadError {
            case .sessionConflict, .finalHashMismatch, .targetConflict, .chunkHashMismatch:
                return true
            case .invalidRequest, .invalidSession, .sessionMissing, .chunkOffsetMismatch, .sessionIncomplete, .retryLimitExceeded:
                return false
            }
        }
        let text = String(describing: error).lowercased()
        return text.contains("conflict") || text.contains("mismatch") || text.contains("different")
    }

    private static func isWrongOffset(_ error: Error) -> Bool {
        if let runtimeError = error as? CanonicalAudioUploadRuntimeError,
           case .chunkOffsetMismatch = runtimeError {
            return true
        }
        if let uploadError = error as? CanonicalUploadRuntimeError,
           case .chunkOffsetMismatch = uploadError {
            return true
        }
        return String(describing: error).lowercased().contains("offset")
    }

    private static func errorCode(_ error: Error) -> String {
        let raw = String(describing: error)
        return CanonicalAudioUploadRuntimeRedaction.safeText(
            CanonicalAudioUploadRuntimeRedaction.redactLongHexRuns(raw)
        ) ?? "uploadRuntimeError"
    }
}

typealias CanonicalAudioUploadCommitExecutor = CanonicalAudioUploadRuntimeExecutor

nonisolated struct CanonicalAudioUploadRuntimeOwner: Sendable {
    var executor: CanonicalAudioUploadCommitExecutor
    var jobStore: CanonicalAudioUploadJobStore
    var nodeRole: CanonicalAudioUploadNodeRole

    nonisolated init(
        executor: CanonicalAudioUploadCommitExecutor = CanonicalAudioUploadCommitExecutor(),
        jobStore: CanonicalAudioUploadJobStore = CanonicalAudioUploadJobStore(),
        nodeRole: CanonicalAudioUploadNodeRole = .iPhone
    ) {
        self.executor = executor
        self.jobStore = jobStore
        self.nodeRole = nodeRole
    }

    nonisolated func execute(
        candidate: CanonicalAudioUploadCutoverCandidate,
        source: any CanonicalAudioUploadByteSource,
        uploadPort: any CanonicalProductionUploadPort,
        configuration: CanonicalAudioUploadRuntimeConfiguration,
        syncRunID: String? = nil
    ) async -> CanonicalAudioUploadRuntimeResult {
        await executor.execute(
            candidate: candidate,
            source: source,
            uploadPort: uploadPort,
            jobStore: jobStore,
            configuration: configuration,
            syncRunID: syncRunID,
            nodeRole: nodeRole
        )
    }
}

nonisolated enum CanonicalAudioUploadRuntimeRedaction {
    nonisolated static func hashPrefix(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return String(value.prefix(12))
    }

    nonisolated static func safeIdentifier(_ value: String?, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_:."))
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filtered = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return filtered.nilIfEmpty.map { String($0.prefix(96)) } ?? fallback
    }

    nonisolated static func safeText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let sanitized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            return nil
        }
        return String(sanitized.prefix(160))
    }

    nonisolated static func redactLongHexRuns(_ value: String) -> String {
        let scalars = Array(value.unicodeScalars)
        var output = String()
        var index = scalars.startIndex
        while index < scalars.endIndex {
            guard scalars[index].isASCIIHexDigit else {
                output.unicodeScalars.append(scalars[index])
                index = scalars.index(after: index)
                continue
            }

            let start = index
            var end = index
            while end < scalars.endIndex, scalars[end].isASCIIHexDigit {
                end = scalars.index(after: end)
            }

            let run = scalars[start..<end]
            if run.count >= 32 {
                output += String(String.UnicodeScalarView(run.prefix(12)))
                output += "...redacted"
            } else {
                output += String(String.UnicodeScalarView(run))
            }
            index = end
        }
        return output
    }
}

extension CanonicalAudioUploadRuntimeResult {
    nonisolated var commitResultState: CanonicalAudioUploadCommitResultState {
        switch outcome {
        case .legacyFallback:
            return .legacyFallbackUsed
        case .diagnosticsOnly, .noCommit:
            return .blockedPolicy
        case .noOp:
            return .noOpSameAudio
        case .deferred:
            return .deferredPeerUnknown
        case .uploaded:
            return .finalized
        case .retryScheduled:
            return diagnostics.contains { $0.kind == .canonicalAudioUploadRuntimeSessionResumed || $0.kind == .canonicalAudioUploadRuntimeResumeStarted }
                ? .resumed
                : .started
        case .conflict:
            return .blockedConflict
        case .blocked:
            if runtimeBlockers.contains(.localAudioMissing) {
                return .blockedMissingLocalAudio
            }
            return .blockedPolicy
        case .failed:
            if runtimeBlockers.contains(.securityFailure) {
                return .failedSecurity
            }
            if runtimeBlockers.contains(.finalHashMismatch) || runtimeBlockers.contains(.finalByteSizeMismatch) || runtimeBlockers.contains(.finalProofMissing) {
                return .failedVerification
            }
            return .failedNetwork
        }
    }

    nonisolated var runtimeBlockers: [CanonicalAudioUploadRuntimeBlocker] {
        var blockers = Set<CanonicalAudioUploadRuntimeBlocker>()

        switch mode {
        case .disabled:
            blockers.insert(.runtimeDisabled)
            blockers.insert(.releaseDefaultDisabled)
        case .blocked:
            blockers.insert(.runtimeBlocked)
        case .diagnosticsOnly:
            blockers.insert(.diagnosticsOnly)
        case .noCommit:
            blockers.insert(.noCommit)
        case .testTransportUpload, .canonicalUploadWithLegacyFallback:
            break
        }

        if outcome == .legacyFallback {
            blockers.insert(.runtimeDisabled)
        }
        if outcome == .deferred {
            blockers.insert(.peerUnknown)
        }
        if outcome == .conflict {
            blockers.insert(.existingDifferentAudio)
        }
        if completed && finalizeProof?.accepted != true && outcome != .noOp {
            blockers.insert(.finalProofMissing)
        }

        let text = ([legacyFallbackReason] + diagnostics.map { $0.reason } + diagnostics.map { $0.result })
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        if text.contains("debuginternal") {
            blockers.insert(.debugInternalRequired)
        }
        if text.contains("ownerapproval") || text.contains("approval") {
            blockers.insert(.ownerApprovalRequired)
        }
        if text.contains("secureuploadroutes") || text.contains("route") {
            blockers.insert(.existingSecureRoutesRequired)
        }
        if text.contains("resumable") && text.contains("unsupported") {
            blockers.insert(.resumableSessionUnsupported)
        }
        if text.contains("realsecureuploadport") || text.contains("dryrun") {
            blockers.insert(.realSecureUploadPortRequired)
        }
        if text.contains("localaudio") || text.contains("sourceunavailable") {
            blockers.insert(.localAudioMissing)
        }
        if text.contains("completedledger") {
            blockers.insert(.completedLedgerNotAudioProof)
        }
        if text.contains("metadataonly") {
            blockers.insert(.metadataOnlyNotAudioAvailable)
        }
        if text.contains("viewrefresh") {
            blockers.insert(.viewRefreshSuppressed)
        }
        if text.contains("retrydrainer") {
            blockers.insert(.retryDrainerFreshJobSuppressed)
        }
        if text.contains("finalhashmismatch") || text.contains("hashmismatch") {
            blockers.insert(.finalHashMismatch)
        }
        if text.contains("finalbytesizemismatch") || text.contains("bytesizemismatch") {
            blockers.insert(.finalByteSizeMismatch)
        }
        if text.contains("proof") {
            blockers.insert(.finalProofMissing)
        }
        if text.contains("security") || text.contains("pinning") || text.contains("hmac") || text.contains("requestverifier") {
            blockers.insert(.securityFailure)
        }
        if outcome == .failed || outcome == .retryScheduled {
            blockers.insert(.networkFailure)
        }
        if outcome == .blocked && blockers.isEmpty {
            blockers.insert(.unsupported)
        }

        return blockers.sorted { $0.rawValue < $1.rawValue }
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension UnicodeScalar {
    nonisolated var isASCIIHexDigit: Bool {
        (value >= 48 && value <= 57)
            || (value >= 65 && value <= 70)
            || (value >= 97 && value <= 102)
    }
}
