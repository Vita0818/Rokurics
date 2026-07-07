//
//  CanonicalTombstoneConflictReadSideTests.swift
//  RokuricsMacTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import RokuricsMac

struct CanonicalTombstoneConflictReadSideTests {
    @Test func macSeamDefaultsOffAndEnabledParallelDoesNotMutate() {
        let disabled = MacTombstoneConflictReadSideSeam().evaluate(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            trigger: .periodic,
            syncRunID: "mac-tombstone-conflict-read-disabled"
        )
        let enabled = MacTombstoneConflictReadSideSeam(
            configuration: .enabled()
        ).evaluate(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            trigger: .periodic,
            syncRunID: "mac-tombstone-conflict-read-enabled"
        )

        #expect(disabled.diffReport == nil)
        #expect(disabled.noMutationAsserted)
        #expect(enabled.diffReport?.equivalent == true)
        #expect(enabled.noMutationAsserted)
        #expect(enabled.storeMutated == false)
        #expect(enabled.uiMutated == false)
        #expect(enabled.uploadJobCreated == false)
        #expect(enabled.receiveJSONMutated == false)
        #expect(enabled.inventoryResponseMutated == false)
        #expect(enabled.audioInboxWritten == false)
        #expect(enabled.transcriptionOrNoteGenerationTriggered == false)
        #expect(enabled.deleteAttempted == false)
        #expect(enabled.restoreAttempted == false)
        #expect(enabled.tombstoneCleared == false)
        #expect(enabled.conflictResolved == false)
        #expect(enabled.diagnostics.map(\.kind).contains(.canonicalTombstoneConflictReadSideEquivalent))
        #expect(enabled.diagnostics.map(\.kind).contains(.canonicalTombstoneConflictNoMutationAsserted))
    }

    @Test func macSharedTemplateRemainsNextPilotOnlyAndReportOnlyRetirement() {
        let template = CanonicalTombstoneConflictTemplateReport.currentV826Audit()
        let matrix = CanonicalMigrationDomainMatrix.v826TombstoneConflictNextPilotCandidate(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            generatedArtifactsTemplateCompleteOrObservationReady: true,
            templateReport: template
        )
        let observationGate = CanonicalTombstoneConflictObservationGate.evaluate(
            window: CanonicalTombstoneConflictObservationWindow()
        )
        let retirement = CanonicalTombstoneConflictRetirementCandidateGate.evaluate(
            observationGate: observationGate
        )
        let tombstonePolicy = matrix.policy(for: .tombstoneConflict)

        #expect(template.readyForNextPilotN0)
        #expect(tombstonePolicy?.status(for: .nextPilotCandidate) == .nextPilotCandidate)
        #expect(tombstonePolicy?.activePilot == false)
        #expect(tombstonePolicy?.runtimeSwitchEnabled == false)
        #expect(retirement.retirementCandidateReady == false)
        #expect(retirement.retirementExecutionPerformed == false)
        #expect(retirement.legacyDeleted == false)
        #expect(retirement.legacyDisabled == false)
    }

    private static func snapshot(
        source: CanonicalTombstoneConflictReadProjectionSource
    ) -> CanonicalTombstoneConflictReadSnapshot {
        CanonicalTombstoneConflictReadProjection.snapshot(
            source: source,
            facts: [
                CanonicalTombstoneConflictReadProjectionFact(
                    objectID: "recording-1",
                    objectKind: .recording,
                    tombstoneState: .tombstoned,
                    deletedDisplayState: .tombstoned,
                    tombstoneTimestamp: CanonicalTimestamp(Date(timeIntervalSince1970: 1)),
                    conflictKind: "activeVsTombstone",
                    conflictStatus: .manualReviewRequired,
                    activeVsTombstoneState: "activeVsTombstone",
                    antiResurrectionStatus: .blocked,
                    generatedArtifactResurrectionBlocked: true,
                    softDeleteMarkerPresent: true,
                    hashPrefix: "abcdef0123456789abcdef0123456789"
                )
            ]
        )
    }
}
