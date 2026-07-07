//
//  CanonicalTransferStateTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/2.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalTransferStateTests {
    @Test func legacyTransferStatesMapToCanonicalPhases() {
        #expect(CanonicalTransferStateMachine.phase(fromLegacyState: "completed") == .completed)
        #expect(CanonicalTransferStateMachine.phase(fromLegacyState: "retryPending") == .failedRetryable)
        #expect(CanonicalTransferStateMachine.phase(fromLegacyState: "inFlight") == .inFlight)
        #expect(CanonicalTransferStateMachine.phase(fromLegacyState: "conflict") == .conflict)
        #expect(CanonicalTransferStateMachine.phase(fromLegacyState: "deferred") == .deferred)
        #expect(CanonicalTransferStateMachine.phase(fromLegacyState: "planned") == .planned)
    }

    @Test func jobsProjectRetryFailureAndGeneratedArtifactDownloadWithoutQueueMutation() {
        let retryJob = CanonicalTransferStateMachine.job(
            objectID: "recording-01",
            kind: .recordingAudioUpload,
            direction: .localToPeer,
            legacyState: "retryPending",
            nextRetryAt: date(4_000),
            failureCode: "networkTimeout",
            source: "legacyLedger"
        )
        let generatedDownload = CanonicalTransferStateMachine.job(
            objectID: "recording-01",
            artifactID: "transcriptMarkdown:recording-01",
            kind: .generatedArtifactDownload,
            direction: .peerToLocal,
            legacyState: "planned",
            source: "canonicalPlanner"
        )
        let projection = CanonicalTransferStateMachine.projection(from: [generatedDownload, retryJob])

        #expect(retryJob.phase == .failedRetryable)
        #expect(retryJob.retryPolicy?.nextRetryAt?.date == date(4_000))
        #expect(retryJob.failure?.retryable == true)
        #expect(generatedDownload.phase == .planned)
        #expect(generatedDownload.direction == .peerToLocal)
        #expect(projection.jobs.map(\.jobID.rawValue).sorted() == projection.jobs.map(\.jobID.rawValue))
    }

    private func date(_ value: TimeInterval) -> Date {
        Date(timeIntervalSince1970: value)
    }
}
