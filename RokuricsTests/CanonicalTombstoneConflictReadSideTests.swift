//
//  CanonicalTombstoneConflictReadSideTests.swift
//  RokuricsTests
//
//  Created by Codex on 2026/6/5.
//

import Foundation
import Testing
@testable import Rokurics

struct CanonicalTombstoneConflictReadSideTests {
    @Test func templateReportAndMatrixMarkTombstoneConflictAsNextPilotCandidateOnly() {
        let template = CanonicalTombstoneConflictTemplateReport.currentV826Audit()
        let matrix = CanonicalMigrationDomainMatrix.v826TombstoneConflictNextPilotCandidate(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            generatedArtifactsTemplateCompleteOrObservationReady: true,
            templateReport: template
        )
        let report = matrix.validate()
        let tombstonePolicy = matrix.policy(for: .tombstoneConflict)

        #expect(template.readiness == .readyForNextPilotN0)
        #expect(template.readyForNextPilotN0)
        #expect(tombstonePolicy?.status(for: .nextPilotCandidate) == .nextPilotCandidate)
        #expect(tombstonePolicy?.activePilot == false)
        #expect(tombstonePolicy?.runtimeSwitchEnabled == false)
        #expect(tombstonePolicy?.readPathLegacy == true)
        #expect(report.blockers.contains(.tombstoneConflictActivePilotDeniedV826) == false)
        #expect(CanonicalMigrationGlobalConfigValidator().validate(matrix).valid)
    }

    @Test func matrixBlocksTombstoneConflictCandidateUntilGeneratedArtifactsEvidenceExists() {
        let matrix = CanonicalMigrationDomainMatrix.v826TombstoneConflictNextPilotCandidate(
            libraryMetadataObservationCompleteOrRetirementCandidateReady: true,
            generatedArtifactsTemplateCompleteOrObservationReady: false
        )
        let tombstonePolicy = matrix.policy(for: .tombstoneConflict)

        #expect(tombstonePolicy?.status(for: .nextPilotCandidate) == .blocked)
        #expect(tombstonePolicy?.activePilot == false)
        #expect(tombstonePolicy?.hasReached(.nextPilotCandidate) == false)
    }

    @Test func projectionIsMetadataOnlyRedactedAndRiskAware() {
        let snapshot = CanonicalTombstoneConflictReadProjection.snapshot(
            source: .canonical,
            facts: [
                Self.fact(
                    objectID: "/Users/vita/private/recording-1",
                    tombstoneState: .tombstoned,
                    deletedDisplayState: .tombstoned,
                    tombstoneTimestamp: CanonicalTimestamp(Date(timeIntervalSince1970: 10)),
                    pathLeakRisk: true,
                    fullMetadataIncluded: true,
                    fullContentIncluded: true
                )
            ]
        )

        #expect(snapshot.itemCount == 1)
        #expect(snapshot.fullMetadataIncludedCount == 0)
        #expect(snapshot.fullContentIncludedCount == 0)
        #expect(snapshot.absolutePathIncludedCount == 0)
        #expect(snapshot.metadataExcludedCount == 1)
        #expect(snapshot.contentExcludedCount == 1)
        #expect(snapshot.items.first?.objectID.contains("/Users/") == false)
        #expect(snapshot.diagnosticsSummary.contains("/Users/") == false)
        #expect(snapshot.failures.map(\.kind).contains(.pathLeakRisk))
        #expect(snapshot.failures.map(\.kind).contains(.fullMetadataRejected))
        #expect(snapshot.failures.map(\.kind).contains(.fullContentRejected))
    }

    @Test func parallelDiffReportsEquivalenceAndFatalRiskBlockers() {
        let clean = CanonicalTombstoneConflictReadSideParallelDiff.compare(
            legacy: Self.snapshot(source: .legacy),
            canonical: Self.snapshot(source: .canonical)
        )

        #expect(clean.equivalent)
        #expect(clean.divergenceCount == 0)

        let risky = CanonicalTombstoneConflictReadProjection.snapshot(
            source: .legacy,
            facts: [
                Self.fact(
                    physicalDeleteRisk: true,
                    permanentDeleteRisk: true,
                    tombstoneGCRisk: true,
                    staleLiveResurrectionRisk: true,
                    autoConflictResolutionRisk: true
                )
            ]
        )
        let blocked = CanonicalTombstoneConflictReadSideParallelDiff.compare(
            legacy: risky,
            canonical: Self.snapshot(source: .canonical)
        )

        #expect(blocked.equivalent == false)
        #expect(blocked.fatalDivergenceCount > 0)
        #expect(blocked.blockers.contains(.physicalDeleteRisk))
        #expect(blocked.blockers.contains(.permanentDeleteRisk))
        #expect(blocked.blockers.contains(.tombstoneGCRisk))
        #expect(blocked.blockers.contains(.staleLiveResurrectionRisk))
        #expect(blocked.blockers.contains(.autoConflictResolutionRisk))
    }

    @Test func antiResurrectionObservationAndRetirementStayReportOnly() {
        let antiResurrection = CanonicalAntiResurrectionTemplateGate().evaluate(
            tombstonedObjectCannotBeRestoredByStaleLiveMetadata: false
        )
        let window = CanonicalTombstoneConflictObservationWindow()
            .recording(.init(kind: .readSideEquivalent))
        let observationGate = CanonicalTombstoneConflictObservationGate.evaluate(window: window)
        let retirement = CanonicalTombstoneConflictRetirementCandidateGate.evaluate(
            observationGate: observationGate
        )

        #expect(antiResurrection.allowed == false)
        #expect(antiResurrection.reportOnly)
        #expect(antiResurrection.blockers.contains(.staleLiveMetadataCanRestoreTombstone))
        #expect(observationGate.state == .disabled)
        #expect(observationGate.observationComplete == false)
        #expect(retirement.retirementCandidateReady == false)
        #expect(retirement.retirementExecutionPerformed == false)
        #expect(retirement.legacyDeleted == false)
        #expect(retirement.legacyDisabled == false)
        #expect(retirement.manualAuditRequired)
    }

    @Test func iPhoneSeamDefaultsOffAndEnabledParallelDoesNotMutate() {
        let disabled = IPhoneTombstoneConflictReadSideSeam().evaluate(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            trigger: .periodic,
            syncRunID: "tombstone-conflict-read-disabled"
        )
        let enabled = IPhoneTombstoneConflictReadSideSeam(
            configuration: .enabled()
        ).evaluate(
            legacySnapshot: Self.snapshot(source: .legacy),
            canonicalSnapshot: Self.snapshot(source: .canonical),
            trigger: .periodic,
            syncRunID: "tombstone-conflict-read-enabled"
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

    private static func snapshot(
        source: CanonicalTombstoneConflictReadProjectionSource
    ) -> CanonicalTombstoneConflictReadSnapshot {
        CanonicalTombstoneConflictReadProjection.snapshot(
            source: source,
            facts: [Self.fact()]
        )
    }

    private static func fact(
        objectID: String = "recording-1",
        objectKind: CanonicalObjectKind = .recording,
        tombstoneState: CanonicalTombstoneState = .tombstoned,
        deletedDisplayState: CanonicalTombstoneConflictDeletedDisplayState = .tombstoned,
        tombstoneTimestamp: CanonicalTimestamp? = CanonicalTimestamp(Date(timeIntervalSince1970: 1)),
        conflictKind: String? = "activeVsTombstone",
        conflictStatus: CanonicalTombstoneConflictStatus = .manualReviewRequired,
        physicalDeleteRisk: Bool = false,
        permanentDeleteRisk: Bool = false,
        tombstoneGCRisk: Bool = false,
        staleLiveResurrectionRisk: Bool = false,
        autoConflictResolutionRisk: Bool = false,
        pathLeakRisk: Bool = false,
        fullMetadataIncluded: Bool = false,
        fullContentIncluded: Bool = false
    ) -> CanonicalTombstoneConflictReadProjectionFact {
        CanonicalTombstoneConflictReadProjectionFact(
            objectID: objectID,
            objectKind: objectKind,
            tombstoneState: tombstoneState,
            deletedDisplayState: deletedDisplayState,
            tombstoneTimestamp: tombstoneTimestamp,
            conflictKind: conflictKind,
            conflictStatus: conflictStatus,
            activeVsTombstoneState: "activeVsTombstone",
            antiResurrectionStatus: .blocked,
            generatedArtifactResurrectionBlocked: true,
            softDeleteMarkerPresent: true,
            hashPrefix: "abcdef0123456789abcdef0123456789",
            pathLeakRisk: pathLeakRisk,
            fullMetadataIncluded: fullMetadataIncluded,
            fullContentIncluded: fullContentIncluded,
            physicalDeleteRisk: physicalDeleteRisk,
            permanentDeleteRisk: permanentDeleteRisk,
            tombstoneGCRisk: tombstoneGCRisk,
            staleLiveResurrectionRisk: staleLiveResurrectionRisk,
            autoConflictResolutionRisk: autoConflictResolutionRisk
        )
    }
}
