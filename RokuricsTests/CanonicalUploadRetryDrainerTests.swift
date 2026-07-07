//
//  CanonicalUploadRetryDrainerTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/11.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalUploadRetryDrainerTests {
    @Test func drainerResumesExistingEligibleCanonicalJob() {
        let result = CanonicalUploadRetryDrainerPolicy(statusRefreshSupported: false).evaluate(
            truth: Self.truth(canonicalJobState: .chunking),
            existingCanonicalJob: Self.canonicalRecord(state: .chunking)
        )

        #expect(result.decision == .resumeCanonicalExistingJob)
        #expect(result.resumedExistingJob)
        #expect(result.createdFreshJob == false)
        #expect(result.diagnostics.contains { $0.kind == .canonicalUploadRetryDrainResumedExistingJob })
    }

    @Test func drainerResumesExistingEligibleLegacyJob() {
        let result = CanonicalUploadRetryDrainerPolicy().evaluate(
            truth: Self.truth(),
            existingLegacyJob: Self.legacyRecord(state: .retryPending)
        )

        #expect(result.decision == .resumeLegacyExistingJob)
        #expect(result.resumedExistingJob)
        #expect(result.createdFreshJob == false)
    }

    @Test func drainerDoesNotCreateFreshUnrelatedJob() {
        let result = CanonicalUploadRetryDrainerPolicy().evaluate(truth: Self.truth())

        #expect(result.decision == .didNotCreateFreshJob)
        #expect(result.createdFreshJob == false)
        #expect(result.blockers.contains(.noExistingEligibleJob))
        #expect(result.diagnostics.contains { $0.kind == .canonicalUploadRetryDrainDidNotCreateFreshJob })
    }

    @Test func drainerDoesNotCreateJobFromViewRefresh() {
        let result = CanonicalUploadRetryDrainerPolicy().evaluate(
            truth: Self.truth(trigger: .viewRefresh),
            existingCanonicalJob: Self.canonicalRecord(state: .chunking)
        )

        #expect(result.decision == .skipViewRefresh)
        #expect(result.createdFreshJob == false)
        #expect(result.blockers.contains(.viewRefreshTrigger))
    }

    @Test func drainerSkipsPeerUnknownConflictMissingAndTombstoned() {
        let peerUnknown = CanonicalUploadRetryDrainerPolicy().evaluate(
            truth: Self.truth(peer: .unknown),
            existingCanonicalJob: Self.canonicalRecord(state: .chunking)
        )
        let conflict = CanonicalUploadRetryDrainerPolicy().evaluate(
            truth: Self.truth(peer: .audioAvailable, peerHash: Self.hashB, peerSize: 12, peerProof: true),
            existingCanonicalJob: Self.canonicalRecord(state: .chunking)
        )
        let missing = CanonicalUploadRetryDrainerPolicy().evaluate(
            truth: Self.truth(localExists: false),
            existingCanonicalJob: Self.canonicalRecord(state: .chunking)
        )
        let tombstoned = CanonicalUploadRetryDrainerPolicy().evaluate(
            truth: Self.truth(tombstoned: true),
            existingCanonicalJob: Self.canonicalRecord(state: .chunking)
        )

        #expect(peerUnknown.decision == .skipPeerUnknown)
        #expect(conflict.decision == .skipConflict)
        #expect(missing.decision == .skipMissingLocalAudio)
        #expect(tombstoned.decision == .skipTombstoned)
        #expect(peerUnknown.diagnostics.contains { $0.kind == .canonicalUploadRetryDrainSkippedPeerUnknown })
        #expect(conflict.diagnostics.contains { $0.kind == .canonicalUploadRetryDrainSkippedConflict })
        #expect(missing.diagnostics.contains { $0.kind == .canonicalUploadRetryDrainSkippedMissingLocalAudio })
        #expect(tombstoned.diagnostics.contains { $0.kind == .canonicalUploadRetryDrainSkippedTombstoned })
    }

    @Test func drainerRespectsBackoffAndMaxRetries() {
        let backoff = CanonicalUploadRetryDrainerPolicy().evaluate(
            truth: Self.truth(),
            existingCanonicalJob: Self.canonicalRecord(
                state: .chunking,
                nextRetryAt: CanonicalTimestamp(Self.now.addingTimeInterval(60))
            ),
            now: Self.now
        )
        let maxRetries = CanonicalUploadRetryDrainerPolicy(maxRetries: 2).evaluate(
            truth: Self.truth(),
            existingCanonicalJob: Self.canonicalRecord(state: .chunking, attemptCount: 2),
            now: Self.now
        )

        #expect(backoff.decision == .skipBackoff)
        #expect(maxRetries.decision == .skipMaxRetriesReached)
        #expect(backoff.blockers.contains(.backoffNotElapsed))
        #expect(maxRetries.blockers.contains(.maxRetriesReached))
    }

    @Test func staleInterruptedSessionRequestsStatusRefreshWhenSupported() {
        let result = CanonicalUploadRetryDrainerPolicy(statusRefreshSupported: true).evaluate(
            truth: Self.truth(canonicalJobState: .interrupted, macSession: .partial, confirmedBytes: 5),
            existingCanonicalJob: Self.canonicalRecord(state: .interrupted, offset: 5)
        )

        #expect(result.decision == .refreshStatusBeforeResume)
        #expect(result.requiresStatusRefresh)
        #expect(result.resumeOffset == 5)
    }

    @Test func securityFailureFailsClosedAndNoRetryStorm() {
        let security = CanonicalUploadRetryDrainerPolicy().evaluate(
            truth: Self.truth(),
            existingLegacyJob: Self.legacyRecord(state: .retryPending),
            securityFailure: true
        )
        let exhausted = CanonicalUploadRetryDrainerPolicy(maxRetries: 1).evaluate(
            truth: Self.truth(),
            existingLegacyJob: Self.legacyRecord(state: .retryPending, attemptCount: 1)
        )

        #expect(security.decision == .skipSecurityFailure)
        #expect(security.resumedExistingJob == false)
        #expect(exhausted.decision == .skipMaxRetriesReached)
        #expect(exhausted.resumedExistingJob == false)
    }

    static func truth(
        localExists: Bool = true,
        peer: CanonicalUploadPeerInventoryState = .metadataOnly,
        peerHash: CanonicalHash? = nil,
        peerSize: Int64? = nil,
        peerProof: Bool = false,
        trigger: CanonicalAudioUploadTriggerSource = .retryDrainer,
        canonicalJobState: CanonicalAudioUploadSessionState? = nil,
        macSession: CanonicalUploadMacReceiveSessionState = .none,
        confirmedBytes: Int64? = nil,
        tombstoned: Bool = false
    ) -> CanonicalUploadStateTruth {
        CanonicalUploadStateTruth(
            objectID: "recording-v850-retry",
            localAudioExists: localExists,
            localContentHash: localExists ? hashA : nil,
            localByteSize: localExists ? 12 : nil,
            canonicalJobState: canonicalJobState,
            retryTruth: CanonicalAudioUploadRetryTruth(hasExistingEligibleRetry: true, retryPending: true, canFreshCreateJob: false),
            peerInventoryState: peer,
            peerContentHash: peerHash,
            peerByteSize: peerSize,
            peerHashSizeProven: peerProof,
            macReceiveSessionState: macSession,
            macConfirmedBytes: confirmedBytes,
            tombstoned: tombstoned,
            triggerSource: trigger
        )
    }

    static func canonicalRecord(
        state: CanonicalAudioUploadSessionState,
        attemptCount: Int = 0,
        nextRetryAt: CanonicalTimestamp? = nil,
        offset: Int64 = 0
    ) -> CanonicalAudioUploadRetryRecord {
        let dueRetryAt = nextRetryAt ?? CanonicalTimestamp(now)
        return CanonicalAudioUploadRetryRecord(
            objectID: "recording-v850-retry",
            sessionID: CanonicalAudioUploadSessionID("session-v850-retry"),
            offset: CanonicalAudioUploadOffset(offset),
            chunkSize: 4,
            contentHash: hashA,
            byteSize: 12,
            state: state,
            attemptCount: attemptCount,
            nextRetryAt: dueRetryAt
        )
    }

    static func legacyRecord(
        state: CanonicalUploadLegacyRetryState,
        attemptCount: Int = 0
    ) -> CanonicalUploadLegacyRetryRecord {
        CanonicalUploadLegacyRetryRecord(
            objectID: "recording-v850-retry",
            sessionIDPrefix: "legacy-session-v850",
            confirmedBytes: 4,
            totalBytes: 12,
            contentHashPrefix: String(hashA.value.prefix(12)),
            attemptCount: attemptCount,
            state: state
        )
    }

    static let now = Date(timeIntervalSince1970: 1_000)
    static let hashA = CanonicalHash(String(repeating: "a", count: 64))
    static let hashB = CanonicalHash(String(repeating: "b", count: 64))
}
