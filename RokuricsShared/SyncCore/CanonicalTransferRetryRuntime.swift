//
//  CanonicalTransferRetryRuntime.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/14.
//

import Foundation

nonisolated enum CanonicalTransferRetryTrigger: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case ordinarySync
    case eventDrivenSync
    case retryDrainer
    case viewRefresh
}

nonisolated enum CanonicalTransferRetryBlocker: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case viewRefreshCannotCreateJob
    case retryDrainerRequiresExistingEligibleJob
    case peerUnknown
    case missingLocalAudio
    case tombstone
    case conflict
    case security
    case malformedLedger
    case backoffActive
    case maxAttemptsReached
    case statusRefreshRequired
}

nonisolated enum CanonicalTransferRetryDecision: String, Codable, Equatable, Hashable, Sendable {
    case blocked
    case noExistingEligibleJob
    case refreshStatusBeforeResume
    case eligibleToResume
}

nonisolated struct CanonicalTransferRetryRuntimePolicy: Codable, Equatable, Hashable, Sendable {
    var maxAttempts: Int
    var baseDelaySeconds: TimeInterval
    var maxDelaySeconds: TimeInterval

    nonisolated init(maxAttempts: Int = 3, baseDelaySeconds: TimeInterval = 5, maxDelaySeconds: TimeInterval = 60) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelaySeconds = max(0, baseDelaySeconds)
        self.maxDelaySeconds = max(baseDelaySeconds, maxDelaySeconds)
    }

    nonisolated func nextRetryAfter(attemptCount: Int, now: Date) -> Date {
        let exponent = max(0, attemptCount)
        let rawDelay = baseDelaySeconds * pow(2, Double(exponent))
        return now.addingTimeInterval(min(maxDelaySeconds, rawDelay))
    }
}

nonisolated struct CanonicalTransferRetryJob: Codable, Equatable, Hashable, Sendable {
    var objectID: CanonicalObjectID
    var sessionID: CanonicalTransferSessionID
    var state: CanonicalTransferRuntimeState
    var confirmedBytes: Int64
    var byteSize: Int64
    var hashPrefix: String
    var attemptCount: Int
    var maxAttempts: Int
    var nextRetryAfter: CanonicalTimestamp?
    var requiresStatusRefreshBeforeResume: Bool
    var blockers: [CanonicalTransferRetryBlocker]

    nonisolated init(
        objectID: CanonicalObjectID,
        sessionID: CanonicalTransferSessionID,
        state: CanonicalTransferRuntimeState,
        confirmedBytes: Int64,
        byteSize: Int64,
        hashPrefix: String,
        attemptCount: Int = 0,
        maxAttempts: Int = 3,
        nextRetryAfter: CanonicalTimestamp? = nil,
        requiresStatusRefreshBeforeResume: Bool = false,
        blockers: [CanonicalTransferRetryBlocker] = []
    ) {
        self.objectID = objectID
        self.sessionID = sessionID
        self.state = state
        self.confirmedBytes = max(0, confirmedBytes)
        self.byteSize = max(0, byteSize)
        self.hashPrefix = String(hashPrefix.trimmingCharacters(in: .whitespacesAndNewlines).prefix(12))
        self.attemptCount = max(0, attemptCount)
        self.maxAttempts = max(1, maxAttempts)
        self.nextRetryAfter = nextRetryAfter
        self.requiresStatusRefreshBeforeResume = requiresStatusRefreshBeforeResume
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }

    nonisolated var existingEligibleState: Bool {
        switch state {
        case .started, .chunking, .interrupted, .resuming, .failed:
            return true
        case .idle, .starting, .finalizing, .finalized, .aborted, .conflict, .blocked:
            return false
        }
    }
}

nonisolated struct CanonicalTransferRetryEvaluation: Codable, Equatable, Hashable, Sendable {
    var decision: CanonicalTransferRetryDecision
    var resumedExistingJob: Bool
    var createdFreshJob: Bool
    var requiresStatusRefresh: Bool
    var resumeOffset: Int64?
    var nextRetryAfter: CanonicalTimestamp?
    var blockers: [CanonicalTransferRetryBlocker]

    nonisolated init(
        decision: CanonicalTransferRetryDecision,
        resumedExistingJob: Bool = false,
        createdFreshJob: Bool = false,
        requiresStatusRefresh: Bool = false,
        resumeOffset: Int64? = nil,
        nextRetryAfter: CanonicalTimestamp? = nil,
        blockers: [CanonicalTransferRetryBlocker] = []
    ) {
        self.decision = decision
        self.resumedExistingJob = resumedExistingJob
        self.createdFreshJob = createdFreshJob
        self.requiresStatusRefresh = requiresStatusRefresh
        self.resumeOffset = resumeOffset.map { max(0, $0) }
        self.nextRetryAfter = nextRetryAfter
        self.blockers = Array(Set(blockers)).sorted { $0.rawValue < $1.rawValue }
    }
}

nonisolated struct CanonicalTransferRetryRuntime: Sendable {
    var policy: CanonicalTransferRetryRuntimePolicy

    nonisolated init(policy: CanonicalTransferRetryRuntimePolicy = CanonicalTransferRetryRuntimePolicy()) {
        self.policy = policy
    }

    nonisolated func evaluate(
        trigger: CanonicalTransferRetryTrigger,
        job: CanonicalTransferRetryJob?,
        now: Date,
        statusRouteAvailable: Bool
    ) -> CanonicalTransferRetryEvaluation {
        if trigger == .viewRefresh {
            return CanonicalTransferRetryEvaluation(
                decision: .blocked,
                blockers: [.viewRefreshCannotCreateJob]
            )
        }
        guard let job, job.existingEligibleState else {
            return CanonicalTransferRetryEvaluation(
                decision: .noExistingEligibleJob,
                blockers: [.retryDrainerRequiresExistingEligibleJob]
            )
        }

        if job.blockers.isEmpty == false {
            return CanonicalTransferRetryEvaluation(decision: .blocked, blockers: job.blockers)
        }
        if job.attemptCount >= min(job.maxAttempts, policy.maxAttempts) {
            return CanonicalTransferRetryEvaluation(
                decision: .blocked,
                nextRetryAfter: job.nextRetryAfter,
                blockers: [.maxAttemptsReached]
            )
        }
        if let nextRetryAfter = job.nextRetryAfter, nextRetryAfter.date > now {
            return CanonicalTransferRetryEvaluation(
                decision: .blocked,
                nextRetryAfter: nextRetryAfter,
                blockers: [.backoffActive]
            )
        }
        if statusRouteAvailable, (job.state == .interrupted || job.requiresStatusRefreshBeforeResume) {
            return CanonicalTransferRetryEvaluation(
                decision: .refreshStatusBeforeResume,
                requiresStatusRefresh: true,
                resumeOffset: job.confirmedBytes,
                blockers: [.statusRefreshRequired]
            )
        }

        return CanonicalTransferRetryEvaluation(
            decision: .eligibleToResume,
            resumedExistingJob: true,
            createdFreshJob: false,
            resumeOffset: job.confirmedBytes,
            nextRetryAfter: CanonicalTimestamp(policy.nextRetryAfter(attemptCount: job.attemptCount, now: now))
        )
    }
}
