//
//  CanonicalTransferStateMachine.swift
//  RokuricsShared
//
//  Created by Codex on 2026/6/2.
//

import Foundation

nonisolated struct CanonicalTransferJobID: Codable, Equatable, Hashable, Sendable {
    var rawValue: String

    nonisolated init(_ rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "transfer:unknown"
    }
}

nonisolated enum CanonicalTransferKind: String, Codable, Equatable, CaseIterable, Sendable {
    case recordingAudioUpload
    case generatedArtifactDownload
    case metadataSend
    case metadataApply
    case folderMetadataSend
    case folderMetadataApply
    case studyItemMetadataSend
    case studyItemMetadataApply
    case tombstoneSend
    case tombstoneApply
}

nonisolated enum CanonicalTransferDirection: String, Codable, Equatable, Sendable {
    case localToPeer
    case peerToLocal
    case localOnly
    case peerOnly
}

nonisolated enum CanonicalTransferPhase: String, Codable, Equatable, CaseIterable, Sendable {
    case none
    case planned
    case queued
    case inFlight
    case finalizing
    case completed
    case failedRetryable
    case failedFatal
    case conflict
    case deferred
    case unsupported
}

nonisolated struct CanonicalTransferFailure: Codable, Equatable, Sendable {
    var code: String
    var retryable: Bool
    var detail: String?

    nonisolated init(code: String, retryable: Bool, detail: String? = nil) {
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown"
        self.retryable = retryable
        self.detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

nonisolated struct CanonicalRetryPolicySnapshot: Codable, Equatable, Sendable {
    var retryCount: Int
    var nextRetryAt: CanonicalTimestamp?
    var maxAttempts: Int?
}

nonisolated struct CanonicalTransferJob: Codable, Equatable, Identifiable, Sendable {
    var id: String { jobID.rawValue }
    var jobID: CanonicalTransferJobID
    var objectID: String
    var artifactID: String?
    var kind: CanonicalTransferKind
    var direction: CanonicalTransferDirection
    var phase: CanonicalTransferPhase
    var failure: CanonicalTransferFailure?
    var retryPolicy: CanonicalRetryPolicySnapshot?
    var source: String?

    nonisolated init(
        jobID: CanonicalTransferJobID,
        objectID: String,
        artifactID: String? = nil,
        kind: CanonicalTransferKind,
        direction: CanonicalTransferDirection,
        phase: CanonicalTransferPhase,
        failure: CanonicalTransferFailure? = nil,
        retryPolicy: CanonicalRetryPolicySnapshot? = nil,
        source: String? = nil
    ) {
        self.jobID = jobID
        self.objectID = objectID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown"
        self.artifactID = artifactID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.kind = kind
        self.direction = direction
        self.phase = phase
        self.failure = failure
        self.retryPolicy = retryPolicy
        self.source = source?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

nonisolated struct CanonicalLedgerProjection: Codable, Equatable, Sendable {
    var source: String
    var state: String
    var phase: CanonicalTransferPhase
    var nextRetryAt: CanonicalTimestamp?
    var failure: CanonicalTransferFailure?
}

nonisolated struct CanonicalTransferProjection: Codable, Equatable, Sendable {
    var jobs: [CanonicalTransferJob]
    var ledgers: [CanonicalLedgerProjection]

    nonisolated init(jobs: [CanonicalTransferJob] = [], ledgers: [CanonicalLedgerProjection] = []) {
        self.jobs = jobs.sorted { $0.jobID.rawValue < $1.jobID.rawValue }
        self.ledgers = ledgers
    }
}

nonisolated enum CanonicalTransferStateMachine {
    nonisolated static func phase(fromLegacyState state: String?) -> CanonicalTransferPhase {
        switch state?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "planned":
            return .planned
        case "queued", "pending":
            return .queued
        case "inFlight", "uploading", "downloading", "transferring", "resuming":
            return .inFlight
        case "finalizing", "verifying":
            return .finalizing
        case "completed", "complete", "uploaded":
            return .completed
        case "retryPending", "retryableFailed":
            return .failedRetryable
        case "fatalFailed":
            return .failedFatal
        case "failed":
            return .failedFatal
        case "conflict":
            return .conflict
        case "deferred":
            return .deferred
        case "unsupported":
            return .unsupported
        default:
            return .none
        }
    }

    nonisolated static func job(
        objectID: String,
        artifactID: String? = nil,
        kind: CanonicalTransferKind,
        direction: CanonicalTransferDirection,
        legacyState: String?,
        nextRetryAt: Date? = nil,
        failureCode: String? = nil,
        source: String
    ) -> CanonicalTransferJob {
        let phase = phase(fromLegacyState: legacyState)
        let retry = phase == .failedRetryable
            ? CanonicalRetryPolicySnapshot(retryCount: 0, nextRetryAt: nextRetryAt.map(CanonicalTimestamp.init), maxAttempts: nil)
            : nil
        let failure = failureCode.map {
            CanonicalTransferFailure(code: $0, retryable: phase == .failedRetryable)
        }
        return CanonicalTransferJob(
            jobID: CanonicalTransferJobID([source, kind.rawValue, objectID, artifactID ?? ""].joined(separator: "|")),
            objectID: objectID,
            artifactID: artifactID,
            kind: kind,
            direction: direction,
            phase: phase,
            failure: failure,
            retryPolicy: retry,
            source: source
        )
    }

    nonisolated static func projection(from jobs: [CanonicalTransferJob]) -> CanonicalTransferProjection {
        CanonicalTransferProjection(jobs: jobs)
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
